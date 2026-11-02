import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/events/event_order.dart';
import '../../../shared/events/event_payment.dart';
import '../../../shared/events/event_payment_rules.dart';
import '../../../shared/events/event_summary.dart';
import '../../../shared/events/event_time.dart';
import '../../../shared/events/events_analytics.dart';
import '../../../shared/events/events_checkout.dart';
import '../../../shared/events/events_options.dart';
import '../../../shared/events/registration_draft.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/shop_checkout.dart';
import 'event_cancel_reason_dialog.dart';
import 'event_status.dart';
import 'events_registration_gate.dart';
import 'pay/event_payment_cards.dart';
import 'register/quote_summary.dart';

/// `/member/events/orders/:orderId` (events S3 spec §5.7, S4 spec §5.1):
/// awaiting payment with the hold countdown and the payment status card
/// (the labelled "payment isn't open yet" slot while the server's payment
/// mode is `none`), expired, cancelled, paid with its tickets and refunds;
/// per-place removal (D17) and whole-order cancel.
class MemberEventOrderPage extends StatefulWidget {
  const MemberEventOrderPage({
    super.key,
    required this.orderId,
    this.options,
    this.now,
    this.pollEvery = const Duration(seconds: 60),
    this.livePollEvery = const Duration(seconds: 30),
  });

  final String orderId;
  final EventsOptions? options;
  final DateTime? now;

  /// How often an order awaiting payment with nothing sent is re-read.
  final Duration pollEvery;

  /// How often the payment is re-read while one is live (S4 spec §5.1).
  final Duration livePollEvery;

  @override
  State<MemberEventOrderPage> createState() => _MemberEventOrderPageState();
}

class _MemberEventOrderPageState extends State<MemberEventOrderPage>
    with WidgetsBindingObserver {
  EventOrderDetail? _detail;
  bool _loading = true;
  Object? _error;
  bool _gone = false;
  bool _busy = false;
  Timer? _poll;
  final _heading = FocusNode(debugLabel: 'order-heading');
  CheckoutAttempt? _freeAttempt;
  final _seenStates = <String>{};

  /// The payment-status route said 429: look every 60 s instead of 30 s,
  /// without telling the member.
  bool _backOff = false;

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);
  DateTime get _clock => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _heading.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final d = _detail;
    if (state == AppLifecycleState.resumed &&
        d != null &&
        (d.order.isAwaitingPayment || (d.paymentView?.state.isLive ?? false))) {
      _load(quiet: true);
    }
  }

  bool _offerCounted = false;

  Future<void> _start() async {
    if (!mounted || !eventsRegistrationAllowed(context, _options)) return;
    await _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = _detail == null;
        _error = null;
        _gone = false;
      });
    }
    try {
      final json = await _api.getEventOrder(widget.orderId);
      if (!mounted) return;
      final next = EventOrderDetail.fromJson(json);
      final before = _detail;
      setState(() {
        _detail = next;
        _loading = false;
      });
      _noteStateChange(before, next);
      if (before == null && next.order.fromWaitlist && !_offerCounted) {
        // Events S7 (spec §5.3): a held waitlist ticket was opened.
        _offerCounted = true;
        EventsAnalytics.waitlistOfferOpened(eventId: next.order.eventId);
      }
      _schedulePoll();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _heading.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      if (quiet) return;
      setState(() {
        _loading = false;
        if (e is ApiException && e.status == 404) {
          _gone = true;
        } else {
          _error = e;
        }
      });
    }
  }

  /// Records each payment state once (analytics) and announces a change to
  /// confirmed once (screen readers); the card itself is a live region.
  void _noteStateChange(EventOrderDetail? before, EventOrderDetail next) {
    final state = next.paymentView?.state;
    if (state != null && _seenStates.add('${next.order.id}:${state.wire}')) {
      EventsAnalytics.paymentStateSeen(
        orderId: next.order.id,
        state: state.wire,
        eventId: next.order.eventId,
      );
    }
    if (before != null &&
        before.order.status != EventOrderStatus.confirmed &&
        next.order.status == EventOrderStatus.confirmed) {
      final n = next.registrations
          .where((r) => r.ticket?.isActive ?? false)
          .length;
      SemanticsService.sendAnnouncement(
        View.of(context),
        context
            .tr(
              n == 1
                  ? 'events.pay.announce.confirmed.one'
                  : 'events.pay.announce.confirmed',
            )
            .replaceFirst('{n}', '$n'),
        Directionality.of(context),
      );
    }
  }

  /// A payment that is live is re-read often through the cheap
  /// payment-status route (spec §3.5); the full order is read again only
  /// when something changed. An order awaiting payment with nothing sent
  /// is re-read slowly, as in S3.
  void _schedulePoll() {
    _poll?.cancel();
    final d = _detail;
    if (d == null) return;
    if (d.paymentView?.state.isLive ?? false) {
      _poll = Timer(
        _backOff ? widget.pollEvery : widget.livePollEvery,
        _pollPayment,
      );
    } else if (d.order.isAwaitingPayment) {
      _poll = Timer(widget.pollEvery, () => _load(quiet: true));
    }
  }

  Future<void> _pollPayment() async {
    final d = _detail;
    if (d == null || !mounted) return;
    try {
      final st = EventPaymentStatus.fromJson(
        await _api.eventPaymentStatus(widget.orderId),
      );
      if (!mounted) return;
      _backOff = false;
      final changed =
          st.orderStatus != d.order.statusWire ||
          st.payment?.state != d.paymentView?.state ||
          st.holdExpiresAt != d.order.holdExpiresAt ||
          st.refund != null;
      if (changed) {
        await _load(quiet: true);
        return;
      }
    } on ApiException catch (e) {
      // Rate limited: slow down quietly (no banner).
      if (e.status == 429 || e.code == 'rate_limited') _backOff = true;
    } catch (_) {
      // A dropped connection while waiting is not a failed payment.
    }
    if (mounted) _schedulePoll();
  }

  // ── pay ─────────────────────────────────────────────────────────────────

  Future<void> _openPay() async {
    await context.push<bool>(AppRoutes.memberEventOrderPayPath(widget.orderId));
    if (mounted) await _load(quiet: true);
  }

  /// A free order (total 0) is confirmed by the server on one tap; the
  /// "registered" note shows only once the server says it is confirmed.
  Future<void> _confirmFree() async {
    final d = _detail;
    if (d == null || _busy) return;
    _freeAttempt = CheckoutAttempt.forPurchase(
      _freeAttempt,
      'free|${d.order.id}',
    );
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final done = context.tr('events.pay.free.done');
    setState(() => _busy = true);
    try {
      await _api.payEventOrder(
        d.order.id,
        body: const <String, dynamic>{},
        idempotencyKey: _freeAttempt!.key,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _load(quiet: true);
      if (mounted && _detail?.order.status == EventOrderStatus.confirmed) {
        snack.success(done);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e is ApiException && !eventOrderOutcomeUnknown(e)) {
        _freeAttempt = null;
        snack.error(eventsErrorMessage(locale, e));
      } else {
        // The answer was lost: the server may have confirmed it already.
        await _load(quiet: true);
      }
    }
  }

  Future<void> _resendInvite(EventRegistration r) async {
    final d = _detail;
    if (d == null || _busy) return;
    final yes = await showFFConfirmDialog(
      context,
      title: context.tr('events.invite.resend'),
      message: context.tr('events.invite.resend.body'),
      confirmLabel: context.tr('events.invite.resend'),
      cancelLabel: context.tr('common.cancel'),
      confirmKey: const Key('invite-confirm'),
    );
    if (!yes || !mounted) return;
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final sent = context.tr('events.invite.resent');
    setState(() => _busy = true);
    try {
      await _api.resendEventClaimInvitation(d.order.id, registrationId: r.id);
      if (!mounted) return;
      EventsAnalytics.invitationResent(eventId: d.order.eventId);
      setState(() => _busy = false);
      snack.success(sent);
      await _load(quiet: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      snack.error(eventsErrorMessage(locale, e));
    }
  }

  // ── actions ─────────────────────────────────────────────────────────────

  Future<void> _cancelOrder() async {
    final d = _detail;
    if (d == null || _busy) return;
    final reason = await showEventCancelReasonDialog(
      context,
      title: context.tr('events.order.cancel.title'),
      body: context.tr('events.order.cancel.body'),
      confirmLabel: context.tr('events.order.cancel'),
    );
    if (reason == null || !mounted) return;
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final done = context.tr('events.order.cancelled.snack');
    setState(() => _busy = true);
    try {
      final res = await _api.cancelEventOrder(d.order.id, reason: reason);
      if (!mounted) return;
      EventsAnalytics.orderCancelled(orderId: d.order.id, reason: reason);
      final order = res['order'] is Map
          ? EventOrder.fromJson(res['order'] as Map, event: d.order.event)
          : null;
      setState(() {
        _busy = false;
        if (order != null) {
          _detail = d.copyWith(
            order: order,
            registrations: res['registrations'] is List
                ? [
                    for (final r in res['registrations'] as List)
                      if (r is Map)
                        EventRegistration.fromJson(r).withNamesFrom(d.lines),
                  ]
                : d.registrations,
            allowedActions: const [],
          );
        }
      });
      snack.success(done);
      if (order == null) await _load(quiet: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      snack.error(errorMessage(locale, e));
    }
  }

  Future<void> _removePlace(EventRegistration r) async {
    final d = _detail;
    if (d == null || _busy) return;
    final reason = await showEventCancelReasonDialog(
      context,
      title: context
          .tr('events.reg.remove.title')
          .replaceFirst('{name}', r.fullName),
      body: context.tr('events.reg.remove.body'),
      confirmLabel: context.tr('events.order.remove'),
    );
    if (reason == null || !mounted) return;
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    setState(() => _busy = true);
    try {
      await _api.cancelEventRegistration(r.id, reason: reason);
      if (!mounted) return;
      setState(() => _busy = false);
      await _load(quiet: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'remove_whole_line') {
        await showFFConfirmDialog(
          context,
          title: context.tr('events.order.cancel'),
          message: context
              .tr('events.reg.remove.lastLine')
              .replaceFirst('{ticket}', r.ticketTypeName),
          confirmLabel: context.tr('events.order.cancel'),
          cancelLabel: context.tr('common.close'),
          confirmKey: const Key('remove-whole-line-cancel'),
          destructive: true,
        ).then((yes) {
          if (yes && mounted) _cancelOrder();
        });
        return;
      }
      snack.error(errorMessage(locale, e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      snack.error(errorMessage(locale, e));
    }
  }

  /// "Register again": the people of this order become a draft (without
  /// the hold) and the register page offers to continue from it.
  Future<void> _registerAgain() async {
    final d = _detail;
    if (d == null) return;
    final lines = <String, int>{};
    for (final l in d.lines) {
      lines[l.ticketTypeId] = l.quantity;
    }
    await RegistrationDraftStore.save(
      RegistrationDraft(
        eventId: d.order.eventId,
        savedAt: (widget.now ?? DateTime.now()).toUtc(),
        step: 1,
        lines: lines,
        mode: d.registrations.any((r) => r.isSelf)
            ? (d.registrations.length > 1 ? 'selfOthers' : 'self')
            : 'others',
        participants: [
          for (final r in d.registrations)
            EventParticipantInput(
              ticketTypeId: r.ticketTypeId,
              categoryId: r.categoryId,
              isSelf: r.isSelf,
              firstName: r.firstName,
              lastName: r.lastName,
              phone: r.phone ?? '',
              email: r.email ?? '',
              dateOfBirth: r.dateOfBirth ?? '',
              gender: r.gender ?? '',
              emergencyName: r.emergencyContact?.name ?? '',
              emergencyPhone: r.emergencyContact?.phone ?? '',
              kitSize: r.kitSize ?? '',
            ),
        ],
      ),
    );
    if (!mounted) return;
    context.push(AppRoutes.memberEventRegisterPath(d.order.eventId));
  }

  void _back() => context.canPop()
      ? context.pop()
      : context.go(AppRoutes.memberEventOrders);

  // ── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          d == null
              ? context.tr('events.reg.order')
              : context
                    .tr('events.order.title')
                    .replaceFirst('{ref}', d.order.reference),
        ),
      ),
      bottomNavigationBar: d == null ? null : _payBar(context, d),
      body: _gone
          ? Center(
              child: FFEmptyState(
                key: const Key('order-gone'),
                icon: Icons.receipt_long_outlined,
                title: context.tr('events.order.gone.title'),
                body: context.tr('events.detail.gone.body'),
              ),
            )
          : _loading
          ? FFSkeletonList(
              key: const Key('order-loading'),
              semanticLabel: context.tr('common.loading'),
            )
          : d == null
          ? Center(
              child: FFErrorState(
                key: const Key('order-error'),
                message: _error == null
                    ? null
                    : errorMessage(FFLocaleScope.of(context), _error!),
                retryLabel: context.tr('common.retry'),
                onRetry: _load,
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _load(quiet: true),
              child: ListView(
                key: const Key('order-scroll'),
                padding: const EdgeInsets.all(FFTokens.spacingMd),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _content(context, d),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> _content(BuildContext context, EventOrderDetail d) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final o = d.order;
    final e = d.event?.summary ?? o.event;
    final off = e?.utcOffsetMinutes ?? 0;
    final abbr = e?.timezoneAbbr ?? '';
    final status = context.tr(eventOrderStatusKey(o.status));
    final tone = eventOrderStatusTone(o.status);
    final pv = d.paymentView;
    final slot = eventPaymentSlotFor(o, pv, d.refunds);
    final paymentLive = pv?.state.isLive ?? false;
    final eventOpen =
        e != null &&
        (e.availability == EventAvailability.open ||
            e.availability == EventAvailability.closingSoon);

    return [
      // ── header ────────────────────────────────────────────────────────
      Focus(
        focusNode: _heading,
        child: Semantics(
          header: true,
          label:
              '${context.tr('events.order.title').replaceFirst('{ref}', o.reference)}, $status',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e?.title ?? '',
                  key: const Key('order-event-title'),
                  style: tt.titleLarge,
                ),
                const SizedBox(height: FFTokens.spacingXs),
                Wrap(
                  spacing: FFTokens.spacingSm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FFBadge(
                      key: const Key('order-status'),
                      label: status,
                      tone: tone,
                    ),
                    if (o.fromWaitlist)
                      FFBadge(
                        key: const Key('order-waitlist-chip'),
                        label: context.tr('events.waitlist.offer.chip'),
                        tone: FFBadgeTone.info,
                      ),
                    Text(
                      o.reference,
                      key: const Key('order-reference'),
                      style: tt.bodyMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          key: const Key('order-copy-ref'),
          tooltip: context.tr('common.copy'),
          icon: const Icon(Icons.copy_outlined, size: 20),
          onPressed: () async {
            final snack = FFSnack.of(context);
            final copied = context.tr('common.copied');
            await Clipboard.setData(ClipboardData(text: o.reference));
            snack.success(copied);
          },
        ),
      ),
      // ── state banner ──────────────────────────────────────────────────
      if (o.isAwaitingPayment && o.holdExpiresAt != null)
        FFCard(
          key: const Key('order-hold'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context
                    .tr('events.order.heldUntil')
                    .replaceFirst(
                      '{time}',
                      eventTime(o.holdExpiresAt!, off, abbr, locale: lang),
                    ),
                style: tt.titleSmall,
              ),
              FFCountdownText(
                until: o.holdExpiresAt!,
                now: widget.now == null ? null : () => widget.now!,
                minutesLabel: context.tr('events.order.left'),
                secondsLabel: context.tr('events.order.leftSeconds'),
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                urgentStyle: tt.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: fuelTextColor(context),
                ),
                onDone: () => _load(quiet: true),
              ),
            ],
          ),
        ),
      if (o.status == EventOrderStatus.expired)
        FFAlert(
          key: const Key('order-expired'),
          tone: FFAlertTone.warning,
          message: context.tr('events.order.expired.body'),
        ),
      if (o.status == EventOrderStatus.expired && o.fromWaitlist)
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingSm),
          child: FFAlert(
            key: const Key('order-waitlist-passed'),
            tone: FFAlertTone.info,
            message: context.tr('events.waitlist.offer.passed'),
          ),
        ),
      if (o.status == EventOrderStatus.cancelled)
        FFAlert(
          key: const Key('order-cancelled'),
          tone: FFAlertTone.info,
          message: o.closeReason == 'admin'
              ? context.tr('events.order.cancelledByAdmin')
              : context
                    .tr('events.order.cancelled.body')
                    .replaceFirst(
                      '{date}',
                      o.closedAt == null
                          ? '—'
                          : eventDate(o.closedAt!, off, locale: lang),
                    ),
        ),
      if (o.status == EventOrderStatus.expired ||
          o.status == EventOrderStatus.cancelled)
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingSm),
          child: FFButton(
            key: const Key('order-register-again'),
            label: eventOpen || e == null
                ? context.tr('events.order.again')
                : availabilityLabel(context, e),
            fullWidth: true,
            onPressed: eventOpen ? _registerAgain : null,
          ),
        ),
      // ── payment slot (S4 spec §5.1) ───────────────────────────────────
      ..._paymentSlot(context, d, slot),
      // ── quote ─────────────────────────────────────────────────────────
      FFSectionTitle(context.tr('events.review.tickets')),
      FFCard(
        key: const Key('order-quote'),
        child: QuoteLinesTable(
          lines: d.lines,
          currency: o.currency,
          discountTzs: o.discountTzs,
          feesTzs: o.feesTzs,
          totalTzs: o.totalTzs,
        ),
      ),
      // ── participants ──────────────────────────────────────────────────
      FFSectionTitle(context.tr('events.review.participants')),
      for (final r in d.registrations) _participantRow(context, d, r),
      if (d.team case final team?) ...[
        FFSectionTitle(context.tr('events.review.team')),
        FFActionTile(
          key: const Key('order-team'),
          icon: Icons.groups_outlined,
          title: team.name,
          subtitle:
              context.tr('events.team.type.${team.teamType}') ==
                  'events.team.type.${team.teamType}'
              ? null
              : context.tr('events.team.type.${team.teamType}'),
          onTap: () => context.push(AppRoutes.memberEventTeamPath(team.id)),
        ),
      ],
      if (d.event != null) ...[
        FFSectionTitle(context.tr('events.review.refund')),
        FFCard(
          key: const Key('order-refund'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (refundPolicyLine(context, d.event!.refundPolicy)
                  case final line?)
                Text(line, style: tt.titleSmall),
              if (d.event!.refundPolicy.text.isNotEmpty)
                Text(d.event!.refundPolicy.text.of(lang), style: tt.bodySmall),
            ],
          ),
        ),
      ],
      // ── refunds (S4 spec §5.7) ────────────────────────────────────────
      for (final rf in d.refunds)
        EventRefundCard(refund: rf, options: _options, utcOffsetMinutes: off),
      if (o.isAwaitingPayment && d.canCancel && !paymentLive) ...[
        const SizedBox(height: FFTokens.spacingMd),
        FFButton(
          key: const Key('order-cancel'),
          label: context.tr('events.order.cancel'),
          variant: FFButtonVariant.destructive,
          loading: _busy,
          onPressed: _cancelOrder,
        ),
      ],
      if (d.canCancelRefund) ...[
        const SizedBox(height: FFTokens.spacingMd),
        FFButton(
          key: const Key('order-cancel-refund'),
          label: context.tr('events.cancelpaid.title'),
          variant: FFButtonVariant.destructive,
          onPressed: () =>
              context.push(AppRoutes.memberEventOrderCancelPath(o.id)),
        ),
      ],
      const SizedBox(height: FFTokens.spacingLg),
      Text(
        o.createdAt == null
            ? ''
            : eventDateTime(o.createdAt!, off, abbr, locale: lang),
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    ];
  }

  // ── payment slot ────────────────────────────────────────────────────────

  /// Which way the server takes payment: the order's own `next.payment`
  /// when it names one, else the options'.
  String _modeOf(EventOrderDetail d) =>
      d.payment != 'none' ? d.payment : _options.payment;

  List<Widget> _paymentSlot(
    BuildContext context,
    EventOrderDetail d,
    EventPaymentSlot slot,
  ) {
    final o = d.order;
    final tt = Theme.of(context).textTheme;
    final mode = _modeOf(d);
    final e = d.event?.summary ?? o.event;

    // Payment is not open (server mode `none`) and nothing was sent: the
    // S3 slot, with corrected wording.
    if (o.isAwaitingPayment && !d.hasPayment && mode == 'none') {
      return [
        FFSectionTitle(context.tr('events.order.payment.title')),
        FFCard(
          key: const Key('order-payment-slot'),
          child: Column(
            key: const Key('order-payment-placeholder'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('events.order.payment.soon.title'),
                style: tt.titleSmall,
              ),
              const SizedBox(height: FFTokens.spacingXs),
              FFAlert(
                tone: FFAlertTone.info,
                message: context.tr('events.order.payment.soon.body'),
              ),
            ],
          ),
        ),
      ];
    }
    // A mode this release does not know: say nothing it cannot complete.
    if (o.isAwaitingPayment &&
        !d.hasPayment &&
        mode != 'manual' &&
        mode != 'provider') {
      return [
        FFCard(
          child: Text(
            context.tr('events.order.payment.soon.title'),
            key: const Key('order-payment-unsupported'),
            style: tt.titleSmall,
          ),
        ),
      ];
    }
    final late = eventOrderLatePayable(o, _options, _clock);
    return [
      if (slot != EventPaymentSlot.none)
        EventPaymentStatusCard(
          key: const Key('order-payment-card'),
          slot: slot,
          order: o,
          options: _options,
          payment: d.paymentView,
          refunds: d.refunds,
          ticketCount: d.registrations
              .where((r) => r.ticket?.isActive ?? false)
              .length,
          eventTitle: e?.title ?? '',
          utcOffsetMinutes: e?.utcOffsetMinutes ?? 0,
          timezoneAbbr: e?.timezoneAbbr ?? '',
          now: widget.now,
          onTryAgain: _openPay,
          onCheck: () => _load(quiet: true),
          onOpenTickets: () => context.push(AppRoutes.memberEventTickets),
        ),
      // Expired a moment ago: the member who already paid may still send
      // the transaction ID (spec §3.4.1, D26).
      if (late && !(d.paymentView?.state.isLive ?? false))
        Align(
          alignment: Alignment.centerLeft,
          child: FFButton(
            key: const Key('order-already-paid'),
            label: context.tr('events.pay.alreadyPaid'),
            variant: FFButtonVariant.ghost,
            onPressed: _openPay,
          ),
        ),
    ];
  }

  /// The sticky "Pay · TSh …" bar: awaiting payment, nothing sent, and the
  /// server takes payment. Hidden while payment is not open.
  Widget? _payBar(BuildContext context, EventOrderDetail d) {
    final o = d.order;
    final mode = _modeOf(d);
    if (!o.isAwaitingPayment ||
        d.hasPayment ||
        (mode != 'manual' && mode != 'provider')) {
      return null;
    }
    final amount = formatCurrency(o.totalTzs, currency: o.currency);
    final free = o.totalTzs == 0;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingSm),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: FFButton(
                key: const Key('order-pay'),
                label: free
                    ? context.tr('events.pay.free.cta')
                    : context
                          .tr('events.pay.cta')
                          .replaceFirst('{amount}', amount),
                semanticLabel: free
                    ? null
                    : context
                          .tr('events.pay.cta.a11y')
                          .replaceFirst('{amount}', amount)
                          .replaceFirst('{ref}', o.reference),
                fullWidth: true,
                maxLines: 2,
                loading: _busy,
                onPressed: _busy ? null : (free ? _confirmFree : _openPay),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _participantRow(
    BuildContext context,
    EventOrderDetail d,
    EventRegistration r,
  ) {
    final tt = Theme.of(context).textTheme;
    final statusKey = eventRegistrationStatusKey(r.status, d.order.status);
    final live = registrationIsLive(r.status, d.order.status);
    final chip = switch (r.claimState) {
      ClaimState.self => (
        context.tr('events.participant.you'),
        FFBadgeTone.brand,
      ),
      ClaimState.claimed => (
        context.tr('events.claim.chip.claimed'),
        FFBadgeTone.success,
      ),
      ClaimState.unclaimed => (
        context.tr('events.claim.chip.pending'),
        FFBadgeTone.defaultTone,
      ),
    };
    final canRemove =
        d.order.isAwaitingPayment &&
        d.canCancel &&
        !(d.paymentView?.state.isLive ?? false) &&
        live &&
        d.registrations
                .where((x) => x.status != EventRegistrationStatus.cancelled)
                .length >
            1;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    // The purchaser loses the ticket when the participant claims the place
    // (spec §3.8.5): then the S3 masked view shows no ticket button.
    final claimedAway = r.claimState == ClaimState.claimed && !r.isSelf;
    final showTicket =
        d.order.status.wasPaid && (r.ticket?.isActive ?? false) && !claimedAway;
    final inviteLine = r.canResendInvite && d.order.status.wasPaid;
    final statusTone = r.status == EventRegistrationStatus.confirmed
        ? FFBadgeTone.success
        : (live ? FFBadgeTone.warning : FFBadgeTone.gray);
    return FFCard(
      key: Key('order-participant-${r.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () =>
                      context.push(AppRoutes.memberEventRegistrationPath(r.id)),
                  borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(r.fullName, style: tt.titleSmall),
                        Text(
                          [
                            r.categoryName,
                            r.ticketTypeName,
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: tt.bodySmall,
                        ),
                        const SizedBox(height: FFTokens.spacingXs),
                        Wrap(
                          spacing: FFTokens.spacingXs,
                          runSpacing: FFTokens.spacingXs,
                          children: [
                            FFBadge(
                              label: context.tr(statusKey),
                              tone: statusTone,
                            ),
                            FFBadge(label: chip.$1, tone: chip.$2),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (canRemove)
                PopupMenuButton<String>(
                  key: Key('order-participant-menu-${r.id}'),
                  tooltip: context.tr('events.order.remove'),
                  onSelected: (_) => _removePlace(r),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      key: Key('order-participant-remove-${r.id}'),
                      value: 'remove',
                      child: Text(context.tr('events.reg.remove')),
                    ),
                  ],
                ),
            ],
          ),
          if (showTicket) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Align(
              alignment: Alignment.centerLeft,
              child: FFButton(
                key: Key('order-ticket-${r.id}'),
                label: context.tr('events.ticket.show'),
                variant: FFButtonVariant.secondary,
                size: FFButtonSize.sm,
                onPressed: () =>
                    context.push(AppRoutes.memberEventTicketPath(r.id)),
              ),
            ),
          ],
          if (inviteLine) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              r.invitedAt == null
                  ? context.tr('events.invite.notSent')
                  : context
                        .tr('events.invite.sent')
                        .replaceFirst(
                          '{date}',
                          formatDate(r.invitedAt, locale: lang),
                        ),
              key: Key('order-invite-status-${r.id}'),
              style: tt.bodySmall,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FFButton(
                key: Key('order-invite-${r.id}'),
                label: context.tr('events.invite.resend'),
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
                onPressed: _busy ? null : () => _resendInvite(r),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
