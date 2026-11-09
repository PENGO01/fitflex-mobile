// My trainer sessions and my refunds. A member cancels a session here (an
// unpaid one any time before it starts, a paid one up to 24 hours before,
// refunded in full), follows each refund from approved to paid, and can ask
// for a pass or plan payment back. The server decides what can be cancelled:
// every booking carries its own `cancellation` answer. A session that took
// place, or that the trainer recorded as missed (`no_show`), can be reviewed.

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../../shared/payment_labels.dart';
import '../../shared/widgets/reviews_section.dart';
import 'widgets/mobile_money_pay.dart';

class MemberSessionsPage extends StatefulWidget {
  const MemberSessionsPage({super.key, this.focusBookingId});

  /// The booking a message linked to (`?booking=`): scrolled into view.
  final String? focusBookingId;

  @override
  State<MemberSessionsPage> createState() => _MemberSessionsPageState();
}

class _MemberSessionsPageState extends State<MemberSessionsPage> {
  List<Map<String, dynamic>>? _bookings;
  List<Map<String, dynamic>> _refunds = const [];
  Object? _error;
  String? _busyId;
  bool _started = false;
  final _focusKey = GlobalKey();
  bool _focused = false;

  /// `GET /payments/options`, asked once for every "Pay now" on the page.
  Future<Map<String, dynamic>>? _payOptions;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Unreachable or refused: no "Pay now", nothing else changes.
    _payOptions = AppScope.of(
      context,
    ).api.paymentOptions().catchError((_) => <String, dynamic>{});
    _load();
  }

  /// One payment request covers every session booked together: "Pay now"
  /// sits on the first card of each group still awaiting payment, for the
  /// group's total (fitflex-functions#240).
  static Map<String, PaymentRequest> _pendingPayments(
    List<Map<String, dynamic>> bookings,
  ) {
    final totals = <String, num>{};
    final firstBooking = <String, String>{};
    for (final b in bookings) {
      final pid = b['paymentRequestId']?.toString() ?? '';
      if (b['status'] != 'payment_pending' || pid.isEmpty) continue;
      totals[pid] = (totals[pid] ?? 0) + ((b['amountTzs'] as num?) ?? 0);
      firstBooking.putIfAbsent(pid, () => b['id']?.toString() ?? '');
    }
    return {
      for (final e in firstBooking.entries)
        e.value: PaymentRequest.fromJson({
          'id': e.key,
          'productType': MomoProduct.trainerSession,
          'amountTzs': totals[e.key],
        }),
    };
  }

  static List<Map<String, dynamic>> _maps(dynamic list) => [
    for (final row in (list as List? ?? const []))
      if (row is Map) row.cast<String, dynamic>(),
  ];

  Future<void> _load() async {
    try {
      final api = AppScope.of(context).api;
      final bookings = await api.myTrainerBookings();
      final refunds = await api.myRefunds();
      if (!mounted) return;
      setState(() {
        _bookings = _maps(bookings)
          ..sort(
            (a, b) => '${b['date']} ${b['slot']}'.compareTo(
              '${a['date']} ${a['slot']}',
            ),
          );
        _refunds = _maps(refunds['refunds']);
        _error = null;
      });
      _focusOnce();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _focusOnce() {
    if (_focused || widget.focusBookingId == null) return;
    _focused = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _focusKey.currentContext;
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(target, alignment: 0.1);
      }
    });
  }

  /// Review the trainer of a session that took place or was missed. The
  /// server decides who may review; the sheet opens on any earlier review.
  Future<void> _review(Map<String, dynamic> booking) async {
    final trainerId = _trainerId(booking);
    if (trainerId == null) return;
    final api = AppScope.of(context).api;
    final locale = FFLocaleScope.of(context);
    final messenger = FFSnack.of(context);
    MyReviewState? mine;
    try {
      mine = await api.myReviewState(ReviewSubject.trainer, trainerId);
    } catch (_) {}
    if (!mounted) return;
    if (mine != null && !mine.eligible && !mine.hasReview) {
      messenger.info(locale.t('reviews.trainerHint'));
      return;
    }
    final result = await showReviewSheet(
      context,
      subject: ReviewSubject.trainer,
      subjectId: trainerId,
      initialRating: mine?.rating,
      initialText: mine?.text,
    );
    if (result != null) messenger.success(locale.t('reviews.posted'));
  }

  static String? _trainerId(Map<String, dynamic> booking) {
    final id = (booking['trainerId'] ?? (booking['trainer'] as Map?)?['id'])
        ?.toString();
    return id == null || id.isEmpty ? null : id;
  }

  Future<void> _cancel(Map<String, dynamic> booking) async {
    final rule = (booking['cancellation'] as Map?) ?? const {};
    final refundable = rule['refundable'] == true;
    final amount = formatCurrency(booking['amountTzs'] as num? ?? 0);
    final confirmed = await showFFConfirmDialog(
      context,
      title: context.tr('sessions.cancelTitle'),
      message: refundable
          ? context
                .tr('sessions.cancelConfirmRefund')
                .replaceFirst('{amount}', amount)
          : context.tr('sessions.cancelConfirm'),
      cancelLabel: context.tr('sessions.keep'),
      confirmLabel: context.tr('sessions.cancel'),
      confirmKey: const Key('session-cancel-confirm'),
    );
    if (confirmed != true || !mounted) return;
    final messenger = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final done = context.tr(
      refundable ? 'sessions.cancelledRefund' : 'sessions.cancelled',
    );
    setState(() => _busyId = booking['id']?.toString());
    try {
      await AppScope.of(
        context,
      ).api.cancelMyTrainerBooking(booking['id'].toString());
      await _load();
      messenger.success(done);
    } catch (e) {
      messenger.error(bookingCancelErrorMessage(locale, e));
      await _load();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _askRefund() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _RefundRequestSheet(),
    );
    if (sent == true && mounted) {
      FFSnack.success(context, context.tr('refunds.requestSent'));
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookings = _bookings;
    final toPay = bookings == null
        ? const <String, PaymentRequest>{}
        : _pendingPayments(bookings);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('sessions.title'))),
      body: bookings == null
          ? (_error == null
                ? const Center(child: FFSpinner())
                : FFEmptyState(
                    title: context.tr('inbox.loadFailed'),
                    body: errorMessage(FFLocaleScope.of(context), _error!),
                    action: FFButton(
                      label: context.tr('comms.retry'),
                      onPressed: _load,
                    ),
                  ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  FFSectionTitle(context.tr('sessions.mine')),
                  if (bookings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: FFTokens.spacingMd,
                      ),
                      child: Text(
                        context.tr('sessions.empty'),
                        key: const Key('sessions-empty'),
                      ),
                    )
                  else
                    for (final b in bookings) ...[
                      _SessionCard(
                        key:
                            widget.focusBookingId != null &&
                                b['id']?.toString() == widget.focusBookingId
                            ? _focusKey
                            : null,
                        booking: b,
                        busy: _busyId == b['id']?.toString(),
                        onCancel: () => _cancel(b),
                        onReview: _trainerId(b) == null
                            ? null
                            : () => _review(b),
                        payNow: switch (toPay[b['id']?.toString()]) {
                          final request? => PayNowButton(
                            key: ValueKey('pay-${request.id}'),
                            request: request,
                            options: _payOptions,
                            onPaid: _load,
                          ),
                          null => null,
                        },
                      ),
                      const SizedBox(height: FFTokens.spacingSm),
                    ],
                  const SizedBox(height: FFTokens.spacingLg),
                  FFSectionTitle(context.tr('refunds.title')),
                  if (_refunds.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: FFTokens.spacingMd,
                      ),
                      child: Text(context.tr('refunds.empty')),
                    )
                  else
                    for (final r in _refunds) ...[
                      _RefundCard(refund: r),
                      const SizedBox(height: FFTokens.spacingSm),
                    ],
                  const SizedBox(height: FFTokens.spacingMd),
                  FFButton(
                    key: const Key('refund-ask'),
                    label: context.tr('refunds.ask'),
                    onPressed: _askRefund,
                    variant: FFButtonVariant.secondary,
                  ),
                  const SizedBox(height: FFTokens.spacingSm),
                  Text(
                    context.tr('refunds.askHint'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    super.key,
    required this.booking,
    required this.busy,
    required this.onCancel,
    this.onReview,
    this.payNow,
  });

  final Map<String, dynamic> booking;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback? onReview;

  /// "Pay now" by mobile money, on the first session of an unpaid booking.
  final Widget? payNow;

  @override
  Widget build(BuildContext context) {
    final status = booking['status']?.toString() ?? '';
    final rule = (booking['cancellation'] as Map?) ?? const {};
    // A missed session is settled: never cancellable here.
    final canCancel = rule['canCancel'] == true && status != 'no_show';
    final canReview =
        onReview != null && (status == 'completed' || status == 'no_show');
    // A paid, upcoming session inside the notice period: say why there is no button.
    final tooLate =
        !canCancel && status == 'confirmed' && rule['cancelBy'] != null;
    final (String key, FFBadgeTone tone) = switch (status) {
      'confirmed' => ('sessions.status.confirmed', FFBadgeTone.success),
      'payment_pending' => ('sessions.status.pending', FFBadgeTone.warning),
      'completed' => ('sessions.status.completed', FFBadgeTone.brand),
      'cancelled' => ('sessions.status.cancelled', FFBadgeTone.gray),
      'no_show' => ('booking.status.no_show', FFBadgeTone.warning),
      _ => ('sessions.status.notPaid', FFBadgeTone.gray),
    };
    final trainer = (booking['trainer'] as Map?)?['displayName']?.toString();
    final gym = (booking['gym'] as Map?)?['name']?.toString();
    return FFCard(
      key: Key('session-${booking['id']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  trainer ?? context.tr('sessions.trainer'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              FFBadge(label: context.tr(key), tone: tone),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              '${booking['date']} · ${context.localSlotTime('${booking['slot']}')}',
              ?gym,
              formatCurrency(booking['amountTzs'] as num? ?? 0),
            ].join(' · '),
          ),
          if (payNow != null)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingSm),
              child: payNow,
            ),
          if (tooLate)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                context.tr('sessions.tooLate'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (canCancel)
            Align(
              alignment: Alignment.centerLeft,
              child: FFButton(
                key: Key('session-cancel-${booking['id']}'),
                label: context.tr('sessions.cancel'),
                onPressed: busy ? null : onCancel,
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
              ),
            ),
          if (canReview)
            Align(
              alignment: Alignment.centerLeft,
              child: FFButton(
                key: Key('session-review-${booking['id']}'),
                label: context.tr('sessions.reviewTrainer'),
                onPressed: onReview,
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
                icon: Icons.rate_review_outlined,
              ),
            ),
        ],
      ),
    );
  }
}

class _RefundCard extends StatelessWidget {
  const _RefundCard({required this.refund});

  final Map<String, dynamic> refund;

  @override
  Widget build(BuildContext context) {
    final status = refund['status']?.toString() ?? 'requested';
    final (String key, FFBadgeTone tone) = switch (status) {
      'approved' => ('refunds.status.approved', FFBadgeTone.brand),
      'paid' => ('refunds.status.paid', FFBadgeTone.success),
      'rejected' => ('refunds.status.rejected', FFBadgeTone.gray),
      _ => ('refunds.status.requested', FFBadgeTone.warning),
    };
    final kind = switch (refund['kind']) {
      'trainer_booking' => 'refunds.kind.session',
      'shop_order' => 'refunds.kind.order',
      _ => 'refunds.kind.pass',
    };
    final detail = switch (status) {
      'paid' =>
        context
            .tr('refunds.paidRef')
            .replaceFirst(
              '{ref}',
              refund['paymentReference']?.toString() ?? '',
            ),
      'rejected' => refund['decisionNote']?.toString() ?? '',
      'approved' => context.tr('refunds.approvedHint'),
      _ => context.tr('refunds.requestedHint'),
    };
    return FFCard(
      key: Key('refund-${refund['id']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${formatCurrency(refund['amountTzs'] as num? ?? 0)} · ${context.tr(kind)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              FFBadge(label: context.tr(key), tone: tone),
            ],
          ),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// Ask for a pass or plan payment back: pick the payment, say why.
class _RefundRequestSheet extends StatefulWidget {
  const _RefundRequestSheet();

  @override
  State<_RefundRequestSheet> createState() => _RefundRequestSheetState();
}

class _RefundRequestSheetState extends State<_RefundRequestSheet> {
  List<Map<String, dynamic>>? _payments;
  String? _paymentId;
  String _reason = 'charged_twice';
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await AppScope.of(context).api.myPayments();
      if (!mounted) return;
      // Only confirmed pass or plan payments: sessions and orders are
      // refunded by cancelling them.
      final payments = [
        for (final p in rows)
          if (p is Map &&
              p['status'] == 'approved' &&
              p['subscriptionId'] != null)
            p.cast<String, dynamic>(),
      ];
      setState(() {
        _payments = payments;
        _paymentId = payments.isEmpty ? null : payments.first['id']?.toString();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _payments = const [];
          _error = errorMessage(FFLocaleScope.of(context), e);
        });
      }
    }
  }

  Future<void> _send() async {
    final note = _note.text.trim();
    if (_reason == 'other' && note.isEmpty) {
      setState(() => _error = context.tr('refunds.noteRequired'));
      return;
    }
    final locale = FFLocaleScope.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context).api.requestRefund(
        paymentRequestId: _paymentId!,
        reasonCode: _reason,
        note: note.isEmpty ? null : note,
      );
      navigator.pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(locale, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _paymentLabel(Map<String, dynamic> p) {
    final what = paymentProductLabel(context, PaymentRequest.fromJson(p));
    // The member's own day, in the app language ("19 Okt 2026").
    final day = context.localDate(
      p['decidedAt'] ?? p['requestedAt'],
      fallback: '',
    );
    return [
      formatCurrency(p['amountTzs'] as num? ?? 0),
      if (what.isNotEmpty) what,
      if (day.isNotEmpty) day,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final payments = _payments;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          0,
          FFTokens.spacingLg,
          FFTokens.spacingLg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('refunds.ask'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: FFTokens.spacingMd),
            if (payments == null)
              const Center(child: FFSpinner())
            else if (payments.isEmpty)
              Text(_error ?? context.tr('refunds.noPayments'))
            else ...[
              DropdownButtonFormField<String>(
                key: const Key('refund-payment'),
                initialValue: _paymentId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('refunds.payment'),
                ),
                items: [
                  for (final p in payments)
                    DropdownMenuItem(
                      value: p['id']?.toString(),
                      child: Text(
                        _paymentLabel(p),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy ? null : (v) => setState(() => _paymentId = v),
              ),
              const SizedBox(height: FFTokens.spacingMd),
              DropdownButtonFormField<String>(
                key: const Key('refund-reason'),
                initialValue: _reason,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('refunds.reason'),
                ),
                items: [
                  for (final r in const [
                    'charged_twice',
                    'not_activated',
                    'other',
                  ])
                    DropdownMenuItem(
                      value: r,
                      child: Text(context.tr('refunds.reason.$r')),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _reason = v ?? 'other'),
              ),
              const SizedBox(height: FFTokens.spacingMd),
              FFTextField(
                key: const Key('refund-note'),
                controller: _note,
                label: context.tr('refunds.note'),
                maxLines: 3,
                maxLength: 500,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FFButton(
                  key: const Key('refund-send'),
                  label: context.tr('refunds.send'),
                  onPressed: _busy || _paymentId == null ? null : _send,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
