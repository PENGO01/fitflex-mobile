// Vendor tools · S7: the refund screen, /vendor/sales/:saleId/refund (spec
// §4.2–§4.3, §4.6). Pick the units the customer brings back, whether they
// go back in stock, a reason, and how the money goes back; then confirm.
//
// Online only (§4.7): the sale is always read fresh (the counters must be
// the server's), and a refund is never queued. A network failure at
// Confirm keeps the dialog with Try again, which reuses the same clientRef
// (a refund that did reach the server answers 200 with the same refund).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app_scope.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../../stock/stock_options.dart';
import '../receipt_data.dart';
import '../sale_models.dart';
import '../sales_widgets.dart';
import 'refund_models.dart';

/// `/vendor/sales/:saleId/refund`.
String saleRefundRoute(String saleId) =>
    '/vendor/sales/${Uri.encodeComponent(saleId)}/refund';

/// `/vendor/refunds/:refundId`; [saved] right after the refund was made.
String refundDetailRoute(String refundId, {bool saved = false}) => Uri(
  path: '/vendor/refunds/${Uri.encodeComponent(refundId)}',
  queryParameters: saved ? {'saved': '1'} : null,
).toString();

/// What the refund screen hands back to the sale detail: the refund made
/// and the sale as it is now.
typedef RefundOutcome = ({
  Map<String, dynamic> refund,
  Map<String, dynamic>? sale,
});

enum _Stop { none, loading, failed, offline, notFound, voided, full }

class RefundPage extends StatefulWidget {
  const RefundPage({super.key, required this.saleId, this.now});
  final String saleId;

  /// Test clock (the M2 "same day" rule).
  final DateTime? now;

  @override
  State<RefundPage> createState() => _RefundPageState();
}

class _RefundPageState extends State<RefundPage> {
  _Stop _stop = _Stop.loading;
  Map<String, dynamic>? _sale;
  RefundDraftController? _draft;
  final _reason = TextEditingController();
  final _reference = TextEditingController();
  final _reasonFocus = FocusNode(debugLabel: 'refund-reason');
  final _referenceFocus = FocusNode(debugLabel: 'refund-reference');
  final Map<String, FocusNode> _lineFocus = {};
  String? _reasonPill;

  /// Lines the server said were refunded elsewhere (409), highlighted.
  Set<String> _exceeded = {};
  bool _exceedsNotice = false;

  /// restock_unavailable: lines whose product was deleted.
  final Set<String> _noRestock = {};
  String? _referenceError;
  String? _methodError;
  String? _reasonError;
  bool _saleVoidedNow = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _draft?.dispose();
    _reason.dispose();
    _reference.dispose();
    _reasonFocus.dispose();
    _referenceFocus.dispose();
    for (final f in _lineFocus.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// Moves focus to a line card once the dialog has closed and the route
  /// has given focus back (UAT L-4: never left on Close).
  void _focusLine(String id) {
    void go() {
      if (!mounted) return;
      final node = _focusOf(id);
      final ctx = node.context;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 150),
        );
      }
      node.requestFocus();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      go();
      // The dialog route may hand focus back a frame later: ask again.
      WidgetsBinding.instance.addPostFrameCallback((_) => go());
    });
  }

  FocusNode _focusOf(String id) =>
      _lineFocus.putIfAbsent(id, () => FocusNode(debugLabel: 'refund-$id'));

  void _toSale() => context.go(saleDetailRoute(widget.saleId));

  Future<void> _start() async {
    final tools = await enterSalesRoute(context);
    if (tools == null || !mounted) return;
    // Flag off (or options failed): no refund route, no message (§3.1).
    if (!tools.refundsOn) {
      _toSale();
      return;
    }
    await _load();
  }

  Future<void> _load({bool afterExceeds = false}) async {
    if (!afterExceeds) setState(() => _stop = _Stop.loading);
    try {
      final res = await AppScope.of(context).api.vendorSale(widget.saleId);
      if (!mounted) return;
      final sale = res['sale'] is Map
          ? Map<String, dynamic>.from(res['sale'] as Map)
          : null;
      if (sale == null) {
        setState(() => _stop = _Stop.notFound);
        return;
      }
      _apply(sale, afterExceeds: afterExceeds);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'vendor_suspended') {
        FFSnack.error(context, context.tr('vendor.sales.suspended'));
        _toSale();
        return;
      }
      setState(
        () => _stop = e.status == 404 || e.status == 403
            ? _Stop.notFound
            : _Stop.failed,
      );
    } catch (_) {
      if (mounted) setState(() => _stop = _Stop.offline);
    }
  }

  void _apply(Map<String, dynamic> sale, {bool afterExceeds = false}) {
    final user = AppScope.of(context).auth.user;
    final createdBy = sale['createdBy'] is Map
        ? (sale['createdBy'] as Map)['id']?.toString()
        : null;
    final block = refundBlockFor(
      user,
      servedById: createdBy,
      soldAt: sale['soldAt']?.toString(),
      now: widget.now,
    );
    if (block != RefundBlock.none) {
      // A crafted route: back to the sale with why (§4.6).
      FFSnack.error(context, context.tr('vendor.refunds.askOwner'));
      _toSale();
      return;
    }
    final lines = refundableLinesOf(sale);
    final credit = sale['kind']?.toString() == 'credit';
    final balance = (sale['balanceTzs'] as num?)?.toInt() ?? 0;
    final voided = sale['status']?.toString() == 'voided';
    final full = lines.isNotEmpty && lines.every((l) => l.refundableQty == 0);
    if (afterExceeds && _draft != null) {
      final lowered = _draft!.replaceLines(lines, balanceTzs: balance);
      setState(() {
        _sale = sale;
        _exceeded = {..._exceeded, ...lowered};
        _stop = voided ? _Stop.voided : _Stop.none;
      });
      return;
    }
    final draft = RefundDraftController(
      lines: lines,
      credit: credit,
      balanceTzs: balance,
      defaultMethod: defaultRefundMethod(sale),
    )..addListener(_onDraft);
    _draft?.dispose();
    setState(() {
      _sale = sale;
      _draft = draft;
      _stop = voided
          ? _Stop.voided
          : full
          ? _Stop.full
          : _Stop.none;
    });
  }

  void _onDraft() {
    if (mounted) setState(() {});
  }

  Future<bool> _confirmLeave() async {
    final draft = _draft;
    if (draft == null || !draft.hasPicks) return true;
    return showFFConfirmDialog(
      context,
      title: context.tr('vendor.refunds.discardTitle'),
      confirmLabel: context.tr('vendor.refunds.discard'),
      confirmKey: const Key('refund-discard'),
    );
  }

  Future<void> _close() async {
    if (!await _confirmLeave() || !mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      _toSale();
    }
  }

  void _pickReason(String key) {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _reasonPill = key);
    if (key == 'other') {
      _reason.clear();
      draft.setReason('');
      _reasonFocus.requestFocus();
      return;
    }
    final text = context.tr('vendor.refunds.reason.$key');
    _reason.text = text;
    draft.setReason(text);
    _reasonError = null;
  }

  Future<void> _review() async {
    final draft = _draft;
    final sale = _sale;
    if (draft == null || sale == null || !draft.canReview) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final out = await showDialog<_ConfirmResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmDialog(
        saleId: widget.saleId,
        number: sale['number']?.toString() ?? '',
        draft: draft,
        customerName: _customerName(sale),
      ),
    );
    if (!mounted || out == null) return;
    switch (out) {
      case _Saved(:final refund, :final sale):
        final result = (refund: refund, sale: sale);
        if (context.canPop()) {
          context.pop(result);
        } else {
          final id = refund['id']?.toString() ?? '';
          context.go(refundDetailRoute(id, saved: true));
        }
      case _Exceeds(:final lineIds):
        setState(() {
          _exceeded = lineIds;
          _exceedsNotice = true;
        });
        await _load(afterExceeds: true);
        if (!mounted) return;
        final first = draft.lines
            .where((l) => _exceeded.contains(l.saleLineId))
            .firstOrNull;
        if (first != null) _focusLine(first.saleLineId);
      case _LinesChanged():
        await _load(afterExceeds: true);
      case _SaleVoided():
        setState(() => _saleVoidedNow = true);
      case _RestockGone(:final saleLineId):
        draft.setRestock(saleLineId, false);
        setState(() => _noRestock.add(saleLineId));
        _focusLine(saleLineId);
      case _FieldError(:final field, :final key):
        setState(() {
          if (field == 'reference') {
            _referenceError = context.tr(key);
            _referenceFocus.requestFocus();
          } else if (field == 'method') {
            draft.methodForced = true;
            _methodError = context.tr(key);
          } else {
            _reasonError = context.tr(key);
            _reasonFocus.requestFocus();
          }
        });
      case _Leave(:final key):
        FFSnack.error(context, context.tr(key));
        if (context.canPop()) {
          context.pop();
        } else {
          _toSale();
        }
    }
  }

  String? _customerName(Map sale) {
    final c = sale['customer'];
    if (c is! Map) return null;
    final n = c['name']?.toString().trim() ?? '';
    if (n.isNotEmpty) return n;
    return context.tr(
      c['forgotten'] == true
          ? 'vendor.customers.deletedMember'
          : 'vendor.orders.buyerUnnamed',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final sale = _sale;
    final number = sale?['number']?.toString() ?? '';
    final draft = _draft;
    return PopScope(
      canPop: !(draft?.hasPicks ?? false),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          if (context.canPop()) {
            context.pop();
          } else {
            _toSale();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            key: const Key('refund-close'),
            tooltip: t('vendor.refunds.close'),
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.close),
            onPressed: _close,
          ),
          title: Text(
            number.isEmpty
                ? t('vendor.refunds.section')
                : fillIn(t('vendor.refunds.title'), {'number': number}),
          ),
        ),
        body: _body(context),
        bottomNavigationBar: _stop == _Stop.none && draft != null
            ? _reviewBar(context, draft)
            : null,
      ),
    );
  }

  Widget _stopView(BuildContext context) {
    final t = context.tr;
    Widget back() => FFButton(
      key: const Key('refund-back'),
      label: t('vendor.refunds.back'),
      variant: FFButtonVariant.secondary,
      visualDensity: VisualDensity.standard,
      onPressed: () => context.canPop() ? context.pop() : _toSale(),
    );
    final child = switch (_stop) {
      _Stop.loading => FFSkeletonList(
        count: 4,
        semanticLabel: t('vendor.refunds.loading'),
      ),
      _Stop.failed => FFErrorState(
        key: const Key('refund-load-failed'),
        message: t('vendor.refunds.loadFailed'),
        onRetry: _load,
      ),
      _Stop.offline => FFErrorState(
        key: const Key('refund-offline'),
        icon: Icons.wifi_off_outlined,
        message: t('error.network'),
        onRetry: _load,
      ),
      _Stop.notFound => FFEmptyState(
        key: const Key('refund-sale-not-found'),
        title: t('vendor.sales.notFound'),
        action: back(),
      ),
      _Stop.voided => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FFAlert(
            key: const Key('refund-sale-voided'),
            message: t('vendor.refunds.err.saleVoided'),
            tone: FFAlertTone.error,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          back(),
        ],
      ),
      _Stop.full => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FFAlert(
            key: const Key('refund-fully'),
            message: t('vendor.refunds.fully'),
          ),
          const SizedBox(height: FFTokens.spacingMd),
          back(),
        ],
      ),
      _Stop.none => const SizedBox.shrink(),
    };
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [child],
    );
  }

  Widget _body(BuildContext context) {
    if (_stop != _Stop.none) return _stopView(context);
    final draft = _draft!;
    final sale = _sale!;
    final items = _itemsSection(context, draft);
    final money = _moneySection(context, draft, sale);
    final reason = _reasonSection(context, draft);
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final info = _infoLine(context, sale);
        if (!wide) {
          return ListView(
            key: const Key('refund-list'),
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            children: [info, ...items, ...reason, ...money],
          );
        }
        // Flutter web ≥ 900: Items 60 %, Money back 40 % (§4.2).
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: ListView(
                    key: const Key('refund-list'),
                    padding: const EdgeInsets.all(FFTokens.spacingLg),
                    children: [info, ...items, ...reason],
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: ListView(
                    padding: const EdgeInsets.all(FFTokens.spacingLg),
                    children: money,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _infoLine(BuildContext context, Map<String, dynamic> sale) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final methods = methodsSummary(context, [
      for (final p in (sale['payments'] as List? ?? []).whereType<Map>())
        p['method'],
    ]);
    final total = formatCurrency((sale['totalTzs'] as num?) ?? 0);
    return Text(
      [
        eatDateTime(sale['soldAt']?.toString(), locale: lang),
        total,
        if (methods.isNotEmpty) methods,
        ?_customerName(sale),
      ].join(' · '),
      key: const Key('refund-info'),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  List<Widget> _itemsSection(
    BuildContext context,
    RefundDraftController draft,
  ) {
    final t = context.tr;
    final preview = draft.preview;
    return [
      FFSectionTitle(t('vendor.refunds.pickItems')),
      if (_exceedsNotice)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: Semantics(
            liveRegion: true,
            child: FFAlert(
              key: const Key('refund-exceeds'),
              message: t('vendor.refunds.err.exceeds'),
              tone: FFAlertTone.warning,
            ),
          ),
        ),
      if (_saleVoidedNow)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: Semantics(
            liveRegion: true,
            child: FFAlert(
              key: const Key('refund-voided-now'),
              message: t('vendor.refunds.err.saleVoided'),
              tone: FFAlertTone.error,
            ),
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FFButton(
          key: const Key('refund-all'),
          label: t('vendor.refunds.refundAll'),
          variant: FFButtonVariant.ghost,
          visualDensity: VisualDensity.standard,
          maxLines: 2,
          onPressed: draft.lines.any((l) => l.refundableQty > 0)
              ? draft.refundAll
              : null,
        ),
      ),
      for (final l in draft.lines)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: _LineCard(
            line: l,
            qty: draft.qtyOf(l.saleLineId),
            restock: draft.restockOf(l.saleLineId),
            amount: preview.lineAmounts[l.saleLineId] ?? 0,
            highlighted: _exceeded.contains(l.saleLineId),
            restockGone: _noRestock.contains(l.saleLineId),
            focusNode: _focusOf(l.saleLineId),
            onIncrement: () {
              setState(() => _exceeded.remove(l.saleLineId));
              draft.increment(l.saleLineId);
            },
            onDecrement: () => draft.decrement(l.saleLineId),
            onRestock: (v) => draft.setRestock(l.saleLineId, v),
          ),
        ),
    ];
  }

  List<Widget> _reasonSection(
    BuildContext context,
    RefundDraftController draft,
  ) {
    final t = context.tr;
    return [
      FFSectionTitle(t('vendor.refunds.reason')),
      Wrap(
        spacing: FFTokens.spacingXs,
        runSpacing: FFTokens.spacingXs,
        children: [
          for (final k in refundReasonKeys)
            _ChoicePill(
              pillKey: Key('refund-reason-$k'),
              label: t('vendor.refunds.reason.$k'),
              selected: _reasonPill == k,
              onTap: () => _pickReason(k),
            ),
        ],
      ),
      const SizedBox(height: FFTokens.spacingSm),
      FFTextField(
        key: const Key('refund-reason'),
        controller: _reason,
        focusNode: _reasonFocus,
        label: t('vendor.refunds.reason'),
        maxLength: refundReasonMax,
        maxLines: 3,
        minLines: 1,
        errorText: _reasonError,
        onChanged: (v) {
          _reasonError = null;
          draft.setReason(v);
        },
      ),
    ];
  }

  List<Widget> _moneySection(
    BuildContext context,
    RefundDraftController draft,
    Map<String, dynamic> sale,
  ) {
    final t = context.tr;
    final p = draft.preview;
    final name = _customerName(sale) ?? '';
    final success = successText(context);
    return [
      FFSectionTitle(t('vendor.refunds.moneyBack')),
      if (draft.hasPicks) ...[
        // Polite live region: the totals are announced as quantities change.
        Semantics(
          liveRegion: true,
          container: true,
          child: FFCard(
            key: const Key('refund-summary'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MoneyRow(
                  t('vendor.refunds.total'),
                  formatCurrency(p.totalTzs),
                  key: const Key('refund-total'),
                ),
                if (draft.credit && p.balanceReducedTzs > 0)
                  MoneyRow(
                    fillIn(t('vendor.refunds.offBalance'), {'name': name}),
                    '−${formatCurrency(p.balanceReducedTzs)}',
                    key: const Key('refund-off-balance'),
                  ),
                MoneyRow(
                  t('vendor.refunds.payBack'),
                  formatCurrency(p.paidOutTzs),
                  strong: true,
                  color: success,
                  key: const Key('refund-pay-back'),
                ),
                if (p.vatTzs > 0)
                  MoneyRow(
                    fillIn(t('vendor.doc.includesVat'), {'amount': ''}).trim(),
                    formatCurrency(p.vatTzs),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        if (draft.needsMethod) ...[
          Text(
            t('vendor.refunds.method'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Wrap(
            spacing: FFTokens.spacingXs,
            runSpacing: FFTokens.spacingXs,
            children: [
              for (final m in salePaymentMethods)
                _ChoicePill(
                  pillKey: Key('refund-method-$m'),
                  label: t(paymentMethodKey(m)),
                  selected: draft.method == m,
                  onTap: () {
                    setState(() {
                      _methodError = null;
                      _referenceError = null;
                    });
                    draft.setMethod(m);
                    if (m == 'cash') _reference.clear();
                  },
                ),
            ],
          ),
          if (_methodError != null)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                _methodError!,
                key: const Key('refund-method-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (draft.method != 'cash') ...[
            const SizedBox(height: FFTokens.spacingSm),
            FFTextField(
              key: const Key('refund-reference'),
              controller: _reference,
              focusNode: _referenceFocus,
              label: t(
                draft.referenceRequired
                    ? 'vendor.pos.reference'
                    : 'vendor.pos.referenceOptional',
              ),
              helperText: t('vendor.pos.referenceHint'),
              errorText: _referenceError,
              maxLength: maxPaymentReference,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                LengthLimitingTextInputFormatter(maxPaymentReference),
              ],
              onChanged: (v) {
                _referenceError = null;
                draft.setReference(v);
              },
            ),
          ],
        ] else
          FFAlert(
            key: const Key('refund-nothing-back'),
            message: t('vendor.refunds.nothingBack'),
          ),
        const SizedBox(height: FFTokens.spacingSm),
      ],
      FFAlert(
        key: const Key('refund-money-notice'),
        message: t('vendor.refunds.moneyNotice'),
      ),
    ];
  }

  Widget _reviewBar(BuildContext context, RefundDraftController draft) {
    final t = context.tr;
    final problem = draft.problem;
    final amount = formatCurrency(draft.preview.totalTzs);
    final label = fillIn(t('vendor.refunds.review'), {'amount': amount});
    final enabled = draft.canReview && !_saleVoidedNow;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          FFTokens.spacingSm,
          FFTokens.spacingLg,
          FFTokens.spacingMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (problem != null && !_saleVoidedNow)
              Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
                child: Text(
                  t(refundProblemKey(problem)),
                  key: const Key('refund-problem'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            FFButton(
              key: const Key('refund-review'),
              // ≥ 48dp on web too (compact density takes 8 off; UAT L-8).
              visualDensity: VisualDensity.standard,
              label: label,
              semanticLabel: label,
              fullWidth: true,
              maxLines: 2,
              onPressed: enabled ? _review : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// One sale line on the refund screen.
class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.qty,
    required this.restock,
    required this.amount,
    required this.highlighted,
    required this.restockGone,
    required this.focusNode,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRestock,
  });

  final RefundableLine line;
  final int qty;
  final bool restock;
  final int amount;
  final bool highlighted;
  final bool restockGone;
  final FocusNode focusNode;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final ValueChanged<bool> onRestock;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final name = line.displayName;
    final done = line.refundableQty == 0;
    final card = FFCard(
      key: Key('refund-line-${line.saleLineId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: theme.textTheme.titleSmall),
          Text(
            fillIn(t('vendor.refunds.soldRefunded'), {
              'sold': line.qty,
              'refunded': line.refundedQty,
            }),
            style: muted,
          ),
          if (done)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                t('vendor.refunds.lineAllDone'),
                key: Key('refund-line-done-${line.saleLineId}'),
                style: muted,
              ),
            )
          else ...[
            if (highlighted)
              Semantics(
                liveRegion: true,
                child: Text(
                  t('vendor.refunds.err.exceeds'),
                  key: Key('refund-line-exceeds-${line.saleLineId}'),
                  style: TextStyle(color: warningText(context)),
                ),
              ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: FFTokens.spacingSm,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // One label for screen readers (the tooltip alone was read twice).
                    Semantics(
                      container: true,
                      button: true,
                      enabled: qty > 0,
                      label: fillIn(t('vendor.refunds.decrease'), {
                        'name': name,
                      }),
                      onTap: qty > 0 ? onDecrement : null,
                      excludeSemantics: true,
                      child: IconButton(
                        key: Key('refund-dec-${line.saleLineId}'),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          visualDensity: VisualDensity.standard,
                        ),
                        tooltip: fillIn(t('vendor.refunds.decrease'), {
                          'name': name,
                        }),
                        icon: const Icon(Icons.remove),
                        onPressed: qty > 0 ? onDecrement : null,
                      ),
                    ),
                    Semantics(
                      label: fillIn(t('vendor.refunds.qtyLabel'), {
                        'name': name,
                      }),
                      value: fillIn(t('vendor.refunds.a11y.qtyValue'), {
                        'qty': qty,
                        'refundable': line.refundableQty,
                      }),
                      excludeSemantics: true,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 32),
                        child: Text(
                          '$qty',
                          key: Key('refund-qty-${line.saleLineId}'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                    // One label for screen readers (the tooltip alone was read twice).
                    Semantics(
                      container: true,
                      button: true,
                      enabled: qty < line.refundableQty,
                      label: fillIn(t('vendor.refunds.increase'), {
                        'name': name,
                      }),
                      onTap: qty < line.refundableQty ? onIncrement : null,
                      excludeSemantics: true,
                      child: IconButton(
                        key: Key('refund-inc-${line.saleLineId}'),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          visualDensity: VisualDensity.standard,
                        ),
                        tooltip: fillIn(t('vendor.refunds.increase'), {
                          'name': name,
                        }),
                        icon: const Icon(Icons.add),
                        onPressed: qty < line.refundableQty
                            ? onIncrement
                            : null,
                      ),
                    ),
                  ],
                ),
                Text(
                  formatCurrency(amount),
                  key: Key('refund-amount-${line.saleLineId}'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (qty > 0) ...[
              // Its own node (UAT M-1/L-7): only this row toggles restock;
              // the card, name, counts and amount never do.
              Semantics(
                container: true,
                label: fillIn(t('vendor.refunds.a11y.restock'), {'name': name}),
                toggled: restock,
                enabled: !restockGone,
                excludeSemantics: true,
                onTap: restockGone ? null : () => onRestock(!restock),
                child: SwitchListTile(
                  key: Key('refund-restock-${line.saleLineId}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('vendor.refunds.restock')),
                  value: restock,
                  onChanged: restockGone ? null : onRestock,
                ),
              ),
              if (restockGone)
                Text(
                  fillIn(t('vendor.refunds.err.restockUnavailable'), {
                    'name': name,
                  }),
                  key: Key('refund-restock-gone-${line.saleLineId}'),
                  style: TextStyle(color: theme.colorScheme.error),
                )
              else if (!restock)
                Text(t('vendor.refunds.restockOff'), style: muted),
            ],
          ],
        ],
      ),
    );
    // The card is a semantics boundary with separate children (never read
    // or tapped as the switch), and the focus target after a 409 (L-4).
    final framed = highlighted
        ? DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: warningText(context), width: 2),
              borderRadius: BorderRadius.circular(FFTokens.radiusLg),
            ),
            child: card,
          )
        : card;
    return Focus(
      focusNode: focusNode,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: framed,
      ),
    );
  }
}

// ── confirm (§4.3) ───────────────────────────────────────────────────────

sealed class _ConfirmResult {
  const _ConfirmResult();
}

class _Saved extends _ConfirmResult {
  const _Saved(this.refund, this.sale);
  final Map<String, dynamic> refund;
  final Map<String, dynamic>? sale;
}

class _Exceeds extends _ConfirmResult {
  const _Exceeds(this.lineIds);
  final Set<String> lineIds;
}

/// 400 line_not_on_sale: reload the sale and show its lines as they are.
class _LinesChanged extends _ConfirmResult {
  const _LinesChanged();
}

class _SaleVoided extends _ConfirmResult {
  const _SaleVoided();
}

class _RestockGone extends _ConfirmResult {
  const _RestockGone(this.saleLineId);
  final String saleLineId;
}

class _FieldError extends _ConfirmResult {
  const _FieldError(this.field, this.key);
  final String field;
  final String key;
}

/// Leave the refund screen with a message (refund_not_allowed,
/// feature_disabled, sale not found).
class _Leave extends _ConfirmResult {
  const _Leave(this.key);
  final String key;
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({
    required this.saleId,
    required this.number,
    required this.draft,
    this.customerName,
  });
  final String saleId;
  final String number;
  final RefundDraftController draft;
  final String? customerName;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  bool _busy = false;
  String? _error;

  void _close(_ConfirmResult? r) => Navigator.of(context).pop(r);

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // The key is made at the first Confirm and reused on Try again.
    final body = widget.draft.requestBody();
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorRefundSale(widget.saleId, body);
      if (!mounted) return;
      final refund = res['refund'];
      if (refund is! Map) throw StateError('no refund');
      _close(
        _Saved(
          Map<String, dynamic>.from(refund),
          res['sale'] is Map
              ? Map<String, dynamic>.from(res['sale'] as Map)
              : null,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      final b = e.body is Map ? e.body as Map : const {};
      switch (e.code) {
        case 'refund_exceeds_sold':
          final ids = <String>{
            for (final l in (b['lines'] as List? ?? []).whereType<Map>())
              if (l['saleLineId'] != null) l['saleLineId'].toString(),
          };
          _close(_Exceeds(ids));
          return;
        case 'sale_voided':
          _close(const _SaleVoided());
          return;
        case 'restock_unavailable':
          _close(_RestockGone(b['saleLineId']?.toString() ?? ''));
          return;
        case 'reference_required':
          _close(
            const _FieldError('reference', 'vendor.pos.referenceRequired'),
          );
          return;
        case 'reference_too_long':
          _close(const _FieldError('reference', 'vendor.pos.err.payment'));
          return;
        case 'method_required' || 'invalid_method':
          _close(const _FieldError('method', 'vendor.refunds.methodMissing'));
          return;
        case 'reason_too_long':
          _close(const _FieldError('reason', 'vendor.refunds.reasonTooLong'));
          return;
        case 'reason_required':
          _close(const _FieldError('reason', 'vendor.refunds.reasonMissing'));
          return;
        case 'line_not_on_sale':
          // The sale changed under the screen: read it again (as the portal).
          _close(const _LinesChanged());
          return;
        case 'refund_not_allowed':
          _close(const _Leave('vendor.refunds.askOwner'));
          return;
        case 'feature_disabled':
          _close(const _Leave('vendor.refunds.unavailable'));
          return;
        case 'sale_not_found':
          _close(const _Leave('vendor.sales.notFound'));
          return;
        case 'client_ref_reused':
          // Another body under this key: the next Confirm makes a new one.
          widget.draft.clientRef = null;
          setState(() => _error = context.tr('vendor.refunds.err.server'));
        case 'vendor_suspended':
          setState(() => _error = context.tr('vendor.sales.suspended'));
        default:
          setState(
            () => _error = context.tr(
              e.status == 403
                  ? 'vendor.pos.err.notAllowed'
                  : refundErrorKey(e.code),
            ),
          );
      }
      setState(() => _busy = false);
    } catch (_) {
      // No answer: nothing is queued; Try again reuses the same key.
      if (mounted) {
        setState(() {
          _busy = false;
          // It may have reached the server: never say nothing changed
          // (UAT L-5). Try again reuses the key, so it is never made twice.
          _error = context.tr('vendor.refunds.err.unconfirmed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final draft = widget.draft;
    final p = draft.preview;
    final amount = formatCurrency(p.totalTzs);
    final confirm = fillIn(t('vendor.refunds.confirm'), {'amount': amount});
    final confirmLabel = _busy
        ? t('vendor.refunds.saving')
        : _error != null
        ? t('vendor.refunds.tryAgain')
        : confirm;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          fillIn(t('vendor.refunds.confirmTitle'), {
            'amount': amount,
            'number': widget.number,
          }),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final l in draft.lines)
                if (draft.qtyOf(l.saleLineId) > 0)
                  Text(
                    [
                      '${draft.qtyOf(l.saleLineId)} × ${l.displayName}',
                      formatCurrency(p.lineAmounts[l.saleLineId] ?? 0),
                      t(
                        draft.restockOf(l.saleLineId)
                            ? 'vendor.refunds.backInStock'
                            : 'vendor.refunds.notBackInStock',
                      ),
                    ].join(' · '),
                  ),
              const Divider(height: FFTokens.spacingLg),
              MoneyRow(t('vendor.refunds.total'), amount),
              if (draft.credit && p.balanceReducedTzs > 0)
                MoneyRow(
                  fillIn(t('vendor.refunds.offBalance'), {
                    'name': widget.customerName ?? '',
                  }),
                  '−${formatCurrency(p.balanceReducedTzs)}',
                ),
              MoneyRow(
                t('vendor.refunds.payBack'),
                formatCurrency(p.paidOutTzs),
                strong: true,
                color: successText(context),
              ),
              if (draft.needsMethod)
                Text(
                  draft.reference.trim().isEmpty || draft.method == 'cash'
                      ? t(paymentMethodKey(draft.method))
                      : '${t(paymentMethodKey(draft.method))} (${draft.reference.trim()})',
                ),
              const SizedBox(height: FFTokens.spacingSm),
              FFAlert(message: t('vendor.refunds.moneyNotice')),
              const SizedBox(height: FFTokens.spacingSm),
              Text(t('vendor.refunds.confirmBody')),
              if (_error != null) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Semantics(
                  liveRegion: true,
                  child: FFAlert(
                    key: const Key('refund-confirm-error'),
                    message: _error!,
                    tone: FFAlertTone.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FFButton(
            key: const Key('refund-confirm-cancel'),
            label: t('common.cancel'),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: _busy ? null : () => _close(null),
          ),
          FFButton(
            key: const Key('refund-confirm'),
            label: confirmLabel,
            semanticLabel: confirmLabel,
            visualDensity: VisualDensity.standard,
            loading: _busy,
            maxLines: 2,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

/// A single-choice pill (reason, method) read as one button with its
/// selected state, in a mutually exclusive group (UAT L-1).
class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.pillKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key pillKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    inMutuallyExclusiveGroup: true,
    selected: selected,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: FFPill(key: pillKey, label: label, filled: selected, onTap: onTap),
  );
}
