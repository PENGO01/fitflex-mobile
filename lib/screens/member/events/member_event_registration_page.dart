import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/events/event_order.dart';
import '../../../shared/events/event_summary.dart' show EventAvailability;
import '../../../shared/events/event_payment.dart' show EventRefundView;
import '../../../shared/events/event_time.dart';
import '../../../shared/events/events_analytics.dart';
import '../../../shared/events/events_options.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import 'event_cancel_reason_dialog.dart';
import 'events_registration_gate.dart';
import 'results/event_result_entry.dart';
import 'pay/event_payment_cards.dart';

/// `/member/events/registrations/:registrationId` (events S3 spec §5.9, S4
/// spec §5.6): one place — status, its ticket (state, number and "Show
/// ticket"; the code itself is on the ticket page), the participant's
/// details, event, team and order rows, "remove this person" for an unpaid
/// order and "Cancel and refund" for a paid one.
class MemberEventRegistrationPage extends StatefulWidget {
  const MemberEventRegistrationPage({
    super.key,
    required this.registrationId,
    this.options,
  });

  final String registrationId;
  final EventsOptions? options;

  @override
  State<MemberEventRegistrationPage> createState() =>
      _MemberEventRegistrationPageState();
}

class _MemberEventRegistrationPageState
    extends State<MemberEventRegistrationPage> {
  EventRegistration? _reg;

  /// Refunds read from the order when the registration carries none.
  List<EventRefundView> _orderRefunds = const [];
  bool _loading = true;
  Object? _error;
  bool _gone = false;
  bool _busy = false;

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || !eventsRegistrationAllowed(context, _options)) return;
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _reg == null;
      _error = null;
      _gone = false;
    });
    try {
      final json = await _api.getEventRegistration(widget.registrationId);
      if (!mounted) return;
      final reg = EventRegistration.fromJson(json);
      setState(() {
        _reg = reg;
        _loading = false;
      });
      await _loadOrderRefunds(reg);
    } catch (e) {
      if (!mounted) return;
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

  /// The registration read carries its own `refunds`; when it has none for
  /// a paid place, the order's refunds that cover this place are used.
  Future<void> _loadOrderRefunds(EventRegistration reg) async {
    if (reg.refunds.isNotEmpty ||
        !reg.viewerIsPurchaser ||
        reg.orderId.isEmpty ||
        !(reg.orderStatus.wasPaid ||
            reg.status == EventRegistrationStatus.cancelled ||
            reg.status == EventRegistrationStatus.refunded)) {
      return;
    }
    try {
      final d = EventOrderDetail.fromJson(
        await _api.getEventOrder(reg.orderId),
      );
      if (!mounted) return;
      setState(
        () => _orderRefunds = [
          for (final rf in d.refunds)
            if (rf.registrationId == reg.id ||
                (rf.registrationId == null && rf.scope != 'registration'))
              rf,
        ],
      );
    } catch (_) {
      // The page already shows what it has.
    }
  }

  Future<void> _remove() async {
    final r = _reg;
    if (r == null || _busy) return;
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
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'remove_whole_line') {
        final open = await showFFConfirmDialog(
          context,
          title: context.tr('events.order.cancel'),
          message: context
              .tr('events.reg.remove.lastLine')
              .replaceFirst('{ticket}', r.ticketTypeName),
          confirmLabel: context
              .tr('events.reg.openOrder')
              .replaceFirst('{ref}', r.orderReference),
          cancelLabel: context.tr('common.close'),
          confirmKey: const Key('remove-whole-line-open'),
        );
        if (open && mounted) {
          context.push(AppRoutes.memberEventOrder(r.orderId));
        }
        return;
      }
      snack.error(errorMessage(locale, e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      snack.error(errorMessage(locale, e));
    }
  }

  Future<void> _resendInvite() async {
    final r = _reg;
    if (r == null || _busy) return;
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
      await _api.resendEventClaimInvitation(r.orderId, registrationId: r.id);
      if (!mounted) return;
      EventsAnalytics.invitationResent();
      setState(() => _busy = false);
      snack.success(sent);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      snack.error(eventsErrorMessage(locale, e));
    }
  }

  void _back() => context.canPop()
      ? context.pop()
      : context.go(AppRoutes.memberEventOrders);

  @override
  Widget build(BuildContext context) {
    final r = _reg;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.reg.title')),
      ),
      body: _gone
          ? Center(
              child: FFEmptyState(
                key: const Key('reg-gone'),
                icon: Icons.confirmation_number_outlined,
                title: context.tr('events.reg.gone.title'),
                body: context.tr('events.detail.gone.body'),
              ),
            )
          : _loading
          ? FFSkeletonList(
              key: const Key('reg-loading'),
              semanticLabel: context.tr('common.loading'),
            )
          : r == null
          ? Center(
              child: FFErrorState(
                key: const Key('reg-error'),
                message: _error == null
                    ? null
                    : errorMessage(FFLocaleScope.of(context), _error!),
                retryLabel: context.tr('common.retry'),
                onRetry: _load,
              ),
            )
          : ListView(
              key: const Key('reg-scroll'),
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _content(context, r),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  List<Widget> _content(BuildContext context, EventRegistration r) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final e = r.event;
    final off = e?.utcOffsetMinutes ?? 0;
    final abbr = e?.timezoneAbbr ?? '';
    final live = registrationIsLive(r.status, r.orderStatus);
    final statusKey = eventRegistrationStatusKey(r.status, r.orderStatus);
    final reserved = live && r.status == EventRegistrationStatus.reserved;

    Widget line(String label, String? value, {Key? key}) =>
        value == null || value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            key: key,
            padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    label,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                Expanded(child: Text(value, style: tt.bodyMedium)),
              ],
            ),
          );

    return [
      Semantics(
        header: true,
        child: Text(
          r.fullName,
          key: const Key('reg-name'),
          style: tt.titleLarge,
        ),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      // ── status ────────────────────────────────────────────────────────
      if (reserved)
        FFAlert(
          key: const Key('reg-awaiting'),
          tone: FFAlertTone.info,
          message: context
              .tr('events.reg.awaiting')
              .replaceFirst(
                '{time}',
                r.holdExpiresAt == null
                    ? '—'
                    : eventTime(r.holdExpiresAt!, off, abbr, locale: lang),
              ),
        )
      else
        Align(
          alignment: Alignment.centerLeft,
          child: FFBadge(
            key: const Key('reg-status'),
            label: context.tr(statusKey),
            tone: r.status == EventRegistrationStatus.confirmed
                ? FFBadgeTone.success
                : FFBadgeTone.gray,
          ),
        ),
      if (r.orderId.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: FFButton(
            key: const Key('reg-open-order'),
            label: context
                .tr('events.reg.openOrder')
                .replaceFirst('{ref}', r.orderReference),
            variant: FFButtonVariant.ghost,
            size: FFButtonSize.sm,
            onPressed: () =>
                context.push(AppRoutes.memberEventOrder(r.orderId)),
          ),
        ),
      // ── ticket (S4 spec §5.6) ─────────────────────────────────────────
      FFSectionTitle(context.tr('events.reg.ticket')),
      _ticketCard(context, r),
      // Events S6: your result and your run (draws nothing while off).
      EventResultEntry(
        registrationId: r.id,
        event: e,
        options: _options,
        confirmed: r.status == EventRegistrationStatus.confirmed,
        isParticipant:
            r.isSelf || r.relation == 'self' || r.relation == 'claimed',
      ),
      for (final rf in (r.refunds.isNotEmpty ? r.refunds : _orderRefunds))
        EventRefundCard(refund: rf, options: _options, utcOffsetMinutes: off),
      // ── participant ───────────────────────────────────────────────────
      if (r.hasParticipantDetails) ...[
        FFSectionTitle(context.tr('events.reg.participant')),
        FFCard(
          key: const Key('reg-participant'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              line(context.tr('events.participant.phone'), r.phone),
              line(context.tr('events.participant.email'), r.email),
              line(
                context.tr('events.participant.dob'),
                r.dateOfBirth == null
                    ? null
                    : formatDate(r.dateOfBirth, locale: lang),
              ),
              line(
                context.tr('events.participant.gender'),
                r.gender == null
                    ? null
                    : context.tr('onboarding.gender_${r.gender}'),
              ),
              line(
                context.tr('events.participant.kitSize'),
                r.kitSize?.toUpperCase(),
              ),
              if (r.emergencyContact != null && !r.emergencyContact!.isEmpty)
                line(
                  context.tr('events.participant.emergency'),
                  '${r.emergencyContact!.name} · ${r.emergencyContact!.phone}',
                  key: const Key('reg-emergency'),
                ),
            ],
          ),
        ),
      ],
      // ── event ─────────────────────────────────────────────────────────
      if (e != null) ...[
        FFSectionTitle(context.tr('events.reg.event')),
        FFActionTile(
          key: const Key('reg-event'),
          icon: Icons.flag_outlined,
          title: e.title,
          subtitle: [
            r.categoryName,
            if (r.categoryStartsAt ?? e.startsAt case final at?)
              eventDateTime(at, off, abbr, locale: lang),
          ].where((s) => s.isNotEmpty).join(' · '),
          onTap: () => context.push(AppRoutes.memberEventDetailPath(e.id)),
        ),
      ],
      if (r.teamId != null)
        FFActionTile(
          key: const Key('reg-team'),
          icon: Icons.groups_outlined,
          title: r.teamName ?? context.tr('events.review.team'),
          onTap: () => context.push(AppRoutes.memberEventTeamPath(r.teamId!)),
        ),
      // ── consent line ──────────────────────────────────────────────────
      const SizedBox(height: FFTokens.spacingSm),
      Text(
        r.viewerIsPurchaser
            ? context
                  .tr('events.reg.consent.self')
                  .replaceFirst(
                    '{date}',
                    (r.consentAt ?? r.createdAt) == null
                        ? '—'
                        : eventDate(
                            (r.consentAt ?? r.createdAt)!,
                            off,
                            locale: lang,
                          ),
                  )
            : context
                  .tr('events.reg.consent')
                  .replaceFirst('{name}', r.purchaserNameMasked ?? '')
                  .replaceFirst(
                    '{date}',
                    (r.consentAt ?? r.createdAt) == null
                        ? '—'
                        : eventDate(
                            (r.consentAt ?? r.createdAt)!,
                            off,
                            locale: lang,
                          ),
                  ),
        key: const Key('reg-consent'),
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      if (r.canResendInvite) ...[
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
          key: const Key('reg-invite-status'),
          style: tt.bodySmall,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FFButton(
            key: const Key('reg-invite-resend'),
            label: context.tr('events.invite.resend'),
            variant: FFButtonVariant.ghost,
            size: FFButtonSize.sm,
            onPressed: _busy ? null : _resendInvite,
          ),
        ),
      ],
      const SizedBox(height: FFTokens.spacingMd),
      // ── actions ───────────────────────────────────────────────────────
      if (r.viewerIsPurchaser && reserved && r.canCancel)
        FFButton(
          key: const Key('reg-remove'),
          label: context.tr('events.reg.remove'),
          variant: FFButtonVariant.destructive,
          loading: _busy,
          onPressed: _remove,
        )
      else if (r.viewerIsPurchaser && r.canCancelRefund)
        FFButton(
          key: const Key('reg-cancel-refund'),
          label: context.tr('events.cancelpaid.title'),
          variant: FFButtonVariant.destructive,
          onPressed: () => context.push(
            AppRoutes.memberEventRegistrationCancelPath(
              r.id,
              orderId: r.orderId,
            ),
          ),
        )
      else if (!r.viewerIsPurchaser && live)
        Text(
          context
              .tr('events.reg.askPurchaser')
              .replaceFirst(
                '{name}',
                (r.purchaserNameMasked ?? '').split(' ').first,
              ),
          key: const Key('reg-ask-purchaser'),
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
    ];
  }

  /// The ticket slot (spec §5.6). No QR thumbnail here: a shared screen
  /// should not show a code. The state, the number and "Show ticket" are.
  Widget _ticketCard(BuildContext context, EventRegistration r) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final t = r.ticket;
    // The purchaser loses the ticket when the participant claims the place.
    final claimedAway =
        r.viewerIsPurchaser && r.claimState == ClaimState.claimed && !r.isSelf;
    if (t != null && t.isActive && !claimedAway) {
      return FFCard(
        key: const Key('reg-ticket'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FFBadge(
                  key: const Key('reg-ticket-state'),
                  label: context.tr('events.ticket.ready'),
                  tone: FFBadgeTone.success,
                ),
                const SizedBox(width: FFTokens.spacingSm),
                if ((t.displayCode ?? '').isNotEmpty)
                  Expanded(
                    child: Text(
                      context
                          .tr('events.ticket.number')
                          .replaceFirst('{code}', t.displayCode!),
                      key: const Key('reg-ticket-number'),
                      style: tt.bodyMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
            if (r.bibNumber != null) ...[
              const SizedBox(height: FFTokens.spacingSm),
              Semantics(
                label: context
                    .tr('events.ticket.bib.a11y')
                    .replaceFirst('{number}', r.bibNumber!),
                child: ExcludeSemantics(
                  child: Text(
                    context
                        .tr('events.ticket.bib')
                        .replaceFirst('{number}', r.bibNumber!),
                    key: const Key('reg-bib'),
                    style: tt.titleMedium,
                  ),
                ),
              ),
            ],
            const SizedBox(height: FFTokens.spacingSm),
            FFButton(
              key: const Key('reg-show-ticket'),
              label: context.tr('events.ticket.show'),
              onPressed: () =>
                  context.push(AppRoutes.memberEventTicketPath(r.id)),
            ),
          ],
        ),
      );
    }
    if (t != null && t.isRevoked) {
      final eventCancelled =
          r.event?.availability == EventAvailability.cancelled;
      return FFCard(
        key: const Key('reg-ticket-revoked'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FFBadge(
              label: context.tr(
                eventCancelled
                    ? 'events.ticket.revoked.event_cancelled'
                    : 'events.ticket.revoked.cancelled',
              ),
              tone: FFBadgeTone.gray,
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Text(context.tr('events.ticket.revoked.body'), style: tt.bodySmall),
          ],
        ),
      );
    }
    if (r.status == EventRegistrationStatus.confirmed && !claimedAway) {
      // Paid but no ticket row yet (it should not happen): say so, offer a
      // refresh.
      return FFCard(
        key: const Key('reg-ticket-preparing'),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.tr('events.ticket.preparing'),
                style: tt.bodyMedium,
              ),
            ),
            IconButton(
              key: const Key('reg-ticket-refresh'),
              tooltip: context.tr('common.retry'),
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          ],
        ),
      );
    }
    if (claimedAway) return const SizedBox.shrink();
    // Reserved or otherwise not issued: the S3 sentence.
    return FFCard(
      key: const Key('reg-ticket-placeholder'),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                border: Border.all(color: cs.outline),
              ),
              child: Icon(Icons.qr_code_2, size: 48, color: cs.outline),
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('events.reg.ticketSoon'),
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
