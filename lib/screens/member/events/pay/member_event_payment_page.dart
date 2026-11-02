import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app_scope.dart';
import '../../../../router.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_order.dart';
import '../../../../shared/events/event_payment.dart';
import '../../../../shared/events/event_payment_rules.dart';
import '../../../../shared/events/event_time.dart';
import '../../../../shared/events/events_analytics.dart';
import '../../../../shared/events/events_checkout.dart';
import '../../../../shared/events/events_options.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../../../../shared/manual_payment.dart';
import '../../../../shared/shop_checkout.dart';
import '../../widgets/mobile_money_pay.dart';
import '../events_registration_gate.dart';

/// `/member/events/orders/:orderId/pay` (events S4 spec §5.2, §5.3).
///
/// Manual mode: the labelled-manual alert first, the order recap with the
/// exact amount, the Lipa Namba steps, the transaction ID and paying number,
/// and a confirmation box; sending it never says "paid", only "sent for
/// checking". Provider mode: one mobile-money button. The mode is the
/// server's choice; the page never offers the other one.
class MemberEventPaymentPage extends StatefulWidget {
  const MemberEventPaymentPage({
    super.key,
    required this.orderId,
    this.options,
    this.now,
  });

  final String orderId;
  final EventsOptions? options;
  final DateTime? now;

  @override
  State<MemberEventPaymentPage> createState() => _MemberEventPaymentPageState();
}

enum _Phase { loading, form, expired, gone, error }

class _MemberEventPaymentPageState extends State<MemberEventPaymentPage> {
  EventOrderDetail? _detail;
  _Phase _phase = _Phase.loading;
  Object? _error;
  EventsOptions? _freshOptions;

  final _input = ManualPaymentInput();
  final _heading = FocusNode(debugLabel: 'pay-heading');
  bool _confirmed = false;
  bool _busy = false;
  bool _offline = false;
  bool _unavailable = false;
  bool _momoOffered = true;
  Object? _inlineError;
  CheckoutAttempt? _attempt;
  bool _startedEvent = false;

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options =>
      _freshOptions ?? eventsOptionsOf(context, widget.options);
  DateTime get _now => widget.now ?? DateTime.now();

  /// The server's way to pay: the order's own `next.payment` when it names
  /// one, else the options'.
  String get _mode {
    final fromOrder = _detail?.payment ?? 'none';
    return fromOrder != 'none' ? fromOrder : _options.payment;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _input.dispose();
    _heading.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!mounted || !eventsRegistrationAllowed(context, _options)) return;
    await _load();
  }

  void _toOrder({bool changed = false}) {
    if (context.canPop()) {
      context.pop(changed);
    } else {
      context.go(AppRoutes.memberEventOrder(widget.orderId));
    }
  }

  Future<void> _load() async {
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    try {
      final d = EventOrderDetail.fromJson(
        await _api.getEventOrder(widget.orderId),
      );
      if (!mounted) return;
      _detail = d;
      _offline = false;
      final mode = _mode;
      final late = eventOrderLatePayable(d.order, _options, _now);
      final live = d.paymentView?.state.isLive ?? false;
      // Nothing to pay here: back to the order, which says why (and shows
      // the S3 wording while payment is not open).
      if (mode == 'none' || live) {
        _toOrder();
        return;
      }
      if (d.order.status == EventOrderStatus.expired && !late) {
        setState(() => _phase = _Phase.expired);
        return;
      }
      if (!d.order.isAwaitingPayment && !late) {
        _toOrder();
        return;
      }
      // Retry after a rejection: the old ID is put back to correct.
      final prev = d.paymentView;
      if (prev != null &&
          prev.state == EventPaymentState.rejected &&
          (prev.reference ?? '').isNotEmpty &&
          _input.transactionId.text.isEmpty) {
        _input.transactionId.text = prev.reference!;
      }
      _input.prefillPhone(_profilePhone());
      if (mode == 'provider') await _checkMomo();
      if (!mounted) return;
      if (!_startedEvent) {
        _startedEvent = true;
        EventsAnalytics.paymentStarted(
          orderId: d.order.id,
          mode: mode,
          late: late,
          eventId: d.order.eventId,
        );
      }
      setState(() => _phase = _Phase.form);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _heading.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is ApiException && e.status == 404) {
          _phase = _Phase.gone;
        } else {
          _phase = _Phase.error;
          _error = e;
          _offline = isNetworkError(e);
        }
      });
    }
  }

  String? _profilePhone() {
    final user = AppScope.of(context).auth.user;
    final p = user?['phone']?.toString().trim() ?? '';
    return p.isEmpty ? null : p;
  }

  /// Whether the mobile-money sheet may be offered at all (provider mode).
  Future<void> _checkMomo() async {
    try {
      final options = await _api.paymentOptions();
      _momoOffered = momoOffers(
        options,
        MomoProduct.eventOrder,
        role: 'member',
      );
    } catch (_) {
      _momoOffered = false;
    }
  }

  /// The way to pay changed under us: re-read the options and the order.
  Future<void> _reloadForMode() async {
    try {
      _freshOptions = EventsOptions.fromJson(await _api.eventsOptions());
    } catch (_) {}
    if (!mounted) return;
    await _load();
  }

  bool get _canSubmit {
    final m = _detail?.manualInstructions?.manual;
    if (m == null || _busy || _unavailable || _offline) return false;
    if (transactionIdError(_input.transactionId.text) != null) return false;
    if (m.payerPhoneRequired &&
        payerPhoneError(_input.payerPhone.text) != null) {
      return false;
    }
    return _confirmed;
  }

  void _onEdited(String _) {
    final had = _input.clearErrors();
    setState(() {
      if (had) _inlineError = null;
    });
  }

  Future<void> _submitManual() async {
    final d = _detail;
    final ins = d?.manualInstructions;
    if (d == null || ins == null || _busy) return;
    final checked = _input.check(ins.manual);
    if (checked == null) {
      setState(() {});
      return;
    }
    final body = <String, dynamic>{
      'reference': checked.reference,
      if (ins.manual.payerPhoneRequired && checked.payerPhone != null)
        'payerPhone': checked.payerPhone,
    };
    // A retry of the same entries reuses the key, so a lost answer never
    // becomes a second payment; changing either entry makes a new one.
    _attempt = CheckoutAttempt.forPurchase(
      _attempt,
      '${d.order.id}|${checked.reference.toUpperCase()}|${body['payerPhone'] ?? ''}',
    );
    await _send(body, late: eventOrderLatePayable(d.order, _options, _now));
  }

  Future<void> _send(Map<String, dynamic> body, {required bool late}) async {
    final d = _detail!;
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final sent = context.tr('events.pay.sent.snack');
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    try {
      final res = EventPaymentSubmission.fromJson(
        await _api.payEventOrder(
          d.order.id,
          body: body,
          idempotencyKey: _attempt!.key,
        ),
      );
      if (!mounted) return;
      EventsAnalytics.paymentSubmitted(
        orderId: d.order.id,
        late: late,
        eventId: d.order.eventId,
      );
      if (_mode == 'provider' && res.mode == 'provider') {
        setState(() => _busy = false);
        await _openMomo(res);
        return;
      }
      setState(() => _busy = false);
      snack.success(sent);
      _toOrder(changed: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (!eventOrderOutcomeUnknown(e)) _attempt = null;
      setState(() => _busy = false);
      await _handleRefusal(e, snack, locale);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (isNetworkError(e)) _offline = true;
      // The request may have reached the server: keep the form and the key.
      await _showUncertain();
    }
  }

  Future<void> _handleRefusal(
    ApiException e,
    FFSnackMessenger snack,
    FFLocale locale,
  ) async {
    if (eventOrderOutcomeUnknown(e)) {
      await _showUncertain();
      return;
    }
    switch (e.code) {
      case 'payment_reference_required' ||
          'payment_reference_invalid' ||
          'payment_reference_duplicate' ||
          'payer_phone_required' ||
          'payer_phone_invalid':
        setState(() => _input.takeServerError(e));
      case 'payment_in_progress':
        snack.info(eventsErrorMessage(locale, e));
        _toOrder(changed: true);
      case 'hold_expired':
        await _load();
      case 'order_not_payable':
        snack.error(eventsErrorMessage(locale, e));
        _toOrder(changed: true);
      case 'payment_mode_mismatch':
        snack.info(eventsErrorMessage(locale, e));
        await _reloadForMode();
      case 'unsupported_currency' || 'tickets_unavailable':
        setState(() => _unavailable = true);
      case 'too_many_attempts' || 'rate_limited':
        setState(() => _inlineError = e);
      default:
        snack.error(eventsErrorMessage(locale, e));
    }
  }

  Future<void> _showUncertain() async {
    final open = await showFFConfirmDialog(
      context,
      title: context.tr('events.pay.uncertain.title'),
      message: context.tr('events.pay.uncertain.body'),
      confirmLabel: context.tr('events.pay.uncertain.open'),
      cancelLabel: context.tr('common.close'),
      confirmKey: const Key('pay-uncertain-open'),
      cancelKey: const Key('pay-uncertain-close'),
    );
    if (open && mounted) _toOrder(changed: true);
  }

  Future<void> _submitProvider() async {
    final d = _detail;
    if (d == null || _busy) return;
    _attempt = CheckoutAttempt.forPurchase(_attempt, 'provider|${d.order.id}');
    await _send(const <String, dynamic>{}, late: false);
  }

  Future<void> _openMomo(EventPaymentSubmission res) async {
    final d = _detail!;
    final id = res.paymentRequestId ?? d.paymentRequestId;
    final amount = d.order.totalTzs;
    final done = await offerMobileMoney(
      context,
      paymentRequestId: id,
      amountTzs: amount,
      productType: MomoProduct.eventOrder,
    );
    if (!mounted) return;
    if (!done && !_momoOffered) {
      setState(() => _unavailable = true);
      return;
    }
    // Success, or a sheet closed mid-flight: the order page tells the state.
    _toOrder(changed: true);
  }

  // ── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: () => _toOrder(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.pay.title')),
      ),
      body: switch (_phase) {
        _Phase.loading => FFSkeletonList(
          key: const Key('pay-loading'),
          semanticLabel: context.tr('common.loading'),
        ),
        _Phase.gone => Center(
          child: FFEmptyState(
            key: const Key('pay-gone'),
            icon: Icons.receipt_long_outlined,
            title: context.tr('events.order.gone.title'),
            body: context.tr('events.detail.gone.body'),
          ),
        ),
        _Phase.error => Center(
          child: FFErrorState(
            key: const Key('pay-error'),
            message: _error == null
                ? null
                : errorMessage(FFLocaleScope.of(context), _error!),
            retryLabel: context.tr('common.retry'),
            onRetry: _load,
          ),
        ),
        _Phase.expired => Center(
          child: FFEmptyState(
            key: const Key('pay-expired'),
            icon: Icons.timer_off_outlined,
            title: context.tr('events.pay.hold.ended'),
            body: context.tr('events.order.expired.body'),
            action: FFButton(
              key: const Key('pay-back-expired'),
              label: context.tr('events.pay.back'),
              variant: FFButtonVariant.secondary,
              onPressed: _toOrder,
            ),
          ),
        ),
        _Phase.form => _form(context, _detail!),
      },
      bottomNavigationBar: _phase == _Phase.form ? _bar(context) : null,
    );
  }

  Widget _form(BuildContext context, EventOrderDetail d) {
    final tt = Theme.of(context).textTheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final e = d.event?.summary ?? d.order.event;
    final late = eventOrderLatePayable(d.order, _options, _now);
    final provider = _mode == 'provider';
    final ins = d.manualInstructions;
    final amountTzs = ins?.amountTzs ?? d.order.totalTzs;
    final amount = formatCurrency(amountTzs, currency: d.order.currency);
    final manual = ins?.manual;
    final off = e?.utcOffsetMinutes ?? 0;
    final abbr = e?.timezoneAbbr ?? '';

    final children = <Widget>[
      Focus(
        focusNode: _heading,
        child: Semantics(
          header: true,
          child: FFPageHeader(
            title: context.tr('events.pay.title'),
            description: e?.title,
          ),
        ),
      ),
      if (_offline)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: const Key('pay-offline'),
            tone: FFAlertTone.warning,
            message: context.tr('events.pay.offline'),
          ),
        ),
      if (!provider)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: const Key('pay-manual-banner'),
            tone: FFAlertTone.info,
            message:
                '${context.tr('events.pay.manual.banner.title')}\n'
                '${context.tr('events.pay.manual.banner.body').replaceFirst('{hours}', '${_options.manualConfirmHours}')}',
          ),
        ),
      if (late)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: const Key('pay-late-banner'),
            tone: FFAlertTone.warning,
            message:
                '${context.tr('events.pay.late.banner.title')}\n'
                '${context.tr('events.pay.late.banner.body')}',
          ),
        ),
      if (_unavailable)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: const Key('pay-unavailable'),
            tone: FFAlertTone.error,
            message: context.tr('events.pay.unavailable'),
          ),
        ),
      if (_inlineError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: Semantics(
            liveRegion: true,
            child: FFAlert(
              key: const Key('pay-inline-error'),
              tone: FFAlertTone.warning,
              message: eventsErrorMessage(
                FFLocaleScope.of(context),
                _inlineError!,
              ),
            ),
          ),
        ),
      // ── recap ─────────────────────────────────────────────────────────
      FFCard(
        key: const Key('pay-recap'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('events.pay.recap.title'), style: tt.titleSmall),
            const SizedBox(height: FFTokens.spacingXs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${d.order.reference} · ${context.tr('events.order.places').replaceFirst('{n}', '${d.order.placesCount > 0 ? d.order.placesCount : d.registrations.length}')}',
                    key: const Key('pay-recap-ref'),
                    style: tt.bodyMedium,
                  ),
                ),
                IconButton(
                  key: const Key('pay-copy-ref'),
                  tooltip: context.tr('common.copy'),
                  icon: const Icon(Icons.copy_outlined, size: 20),
                  onPressed: () async {
                    final snack = FFSnack.of(context);
                    final copied = context.tr('common.copied');
                    await Clipboard.setData(
                      ClipboardData(text: d.order.reference),
                    );
                    snack.success(copied);
                  },
                ),
              ],
            ),
            Text(
              context.tr('events.pay.exact').replaceFirst('{amount}', amount),
              key: const Key('pay-exact'),
              style: tt.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (!late && d.order.holdExpiresAt != null) ...[
              const SizedBox(height: FFTokens.spacingXs),
              Text(
                context
                    .tr('events.order.heldUntil')
                    .replaceFirst(
                      '{time}',
                      eventTime(
                        d.order.holdExpiresAt!,
                        off,
                        abbr,
                        locale: lang,
                      ),
                    ),
                style: tt.bodySmall,
              ),
              FFCountdownText(
                key: const Key('pay-countdown'),
                until: d.order.holdExpiresAt!,
                now: widget.now == null ? null : () => widget.now!,
                minutesLabel: context.tr('events.order.left'),
                secondsLabel: context.tr('events.order.leftSeconds'),
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                urgentStyle: tt.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? FFTokens.fuelOnDark
                      : FFTokens.fuel,
                ),
                onDone: _load,
              ),
            ],
          ],
        ),
      ),
      if (provider)
        _providerBody(context)
      else if (manual == null)
        FFAlert(
          key: const Key('pay-no-instructions'),
          tone: FFAlertTone.warning,
          message: context.tr('events.pay.unavailable'),
        )
      else ...[
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (_canSubmit) _submitManual();
            },
          },
          child: ManualPaymentFields(
            manual: manual,
            amountLabel: amount,
            input: _input,
            enabled: !_busy && !_unavailable,
            onChanged: _onEdited,
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        CheckboxListTile(
          key: const Key('pay-confirm-check'),
          value: _confirmed,
          onChanged: _busy
              ? null
              : (v) => setState(() => _confirmed = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(
            context
                .tr('events.pay.confirmCheck')
                .replaceFirst('{amount}', amount)
                .replaceFirst('{name}', manual.accountName),
            style: tt.bodyMedium,
          ),
        ),
      ],
      const SizedBox(height: FFTokens.spacingLg),
    ];
    return ListView(
      key: const Key('pay-scroll'),
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  Widget _providerBody(BuildContext context) {
    if (_momoOffered) return const SizedBox.shrink();
    return FFAlert(
      key: const Key('pay-provider-unavailable'),
      tone: FFAlertTone.warning,
      message: context.tr('events.pay.provider.unavailable'),
    );
  }

  Widget _bar(BuildContext context) {
    final d = _detail!;
    final provider = _mode == 'provider';
    final late = eventOrderLatePayable(d.order, _options, _now);
    final amount = formatCurrency(
      d.manualInstructions?.amountTzs ?? d.order.totalTzs,
      currency: d.order.currency,
    );
    final cs = Theme.of(context).colorScheme;
    final primary = provider
        ? FFButton(
            key: const Key('pay-provider-cta'),
            label: context
                .tr('events.pay.provider.cta')
                .replaceFirst('{amount}', amount),
            fullWidth: true,
            maxLines: 2,
            loading: _busy,
            onPressed: _busy || _unavailable || !_momoOffered || _offline
                ? null
                : _submitProvider,
          )
        : FFButton(
            key: const Key('pay-submit'),
            label: context.tr(
              late ? 'events.pay.late.cta' : 'events.pay.submit',
            ),
            fullWidth: true,
            maxLines: 2,
            loading: _busy,
            onPressed: _canSubmit ? _submitManual : null,
          );
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
              child: Row(
                children: [
                  FFButton(
                    key: const Key('pay-back'),
                    label: context.tr('events.pay.back'),
                    variant: FFButtonVariant.ghost,
                    onPressed: _busy ? null : _toOrder,
                  ),
                  const SizedBox(width: FFTokens.spacingSm),
                  Expanded(child: primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
