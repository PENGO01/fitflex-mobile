// Vendor tools · S9: one goods received note (spec §4.5): items, money,
// instalments, payments; Record payment, Change instalments, Share as
// text, Void payment and Void purchase. Every write is online only and
// never queued. Opened from Receive stock (`extra` = the 201 answer), a
// list, a supplier profile, stock history or a push.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/network/browser_online.dart';
import '../customers/customer_models.dart'
    show addDaysTo, dayString, eatTodayString, formatDay;
import '../customers/payment_sheets.dart' show loadBusinessName;
import '../sales/receipt_data.dart' show eatDateTime, eatDayOf;
import '../sales/receipt_page.dart' show shareReceipt;
import '../sales/sale_models.dart'
    show paymentMethodKey, referenceRequiredMethods;
import '../sales/sales_widgets.dart' show warningText;
import '../stock/adjust_stock_sheet.dart' show openAdjustStock;
import '../stock/stock_options.dart';
import 'purchase_models.dart';
import 'purchases_widgets.dart';

class PurchaseDetailPage extends StatefulWidget {
  const PurchaseDetailPage({
    super.key,
    required this.purchaseId,
    this.initial,
    this.now,
  });

  final String purchaseId;

  /// The receive answer `{purchase, costChanges}` when opened right after
  /// saving (no reload needed).
  final Map<String, dynamic>? initial;

  final DateTime Function()? now;

  @override
  State<PurchaseDetailPage> createState() => _PurchaseDetailPageState();
}

class _PurchaseDetailPageState extends State<PurchaseDetailPage> {
  Map<String, dynamic>? _p;
  VendorTools _tools = VendorTools.off;
  bool _loading = true;
  bool _notFound = false;
  bool _failed = false;
  bool _suspended = false;
  final _headingFocus = FocusNode();
  final _paymentsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    BrowserOnline.instance.addListener(_redraw);
    final first = mapOf(widget.initial?['purchase']);
    if (first['id']?.toString() == widget.purchaseId) _p = first;
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    BrowserOnline.instance.removeListener(_redraw);
    _headingFocus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final tools = await enterPurchasesRoute(context);
    if (tools == null || !mounted) return;
    _tools = tools;
    if (_p != null) {
      setState(() => _loading = false);
      _headingFocus.requestFocus();
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorPurchase(widget.purchaseId);
      if (!mounted) return;
      final p = mapOf(res['purchase']);
      setState(() {
        _p = p.isEmpty ? null : p;
        _notFound = p.isEmpty;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'feature_disabled') {
        FFSnack.info(context, context.tr('vendor.purchases.unavailable'));
        context.go('/vendor/home');
        return;
      }
      setState(() {
        _loading = false;
        _suspended = e.code == 'vendor_suspended';
        _notFound = !_suspended && (e.status == 404 || e.status == 403);
        _failed = !_notFound && !_suspended;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(purchasesHubRoute);
    }
  }

  String get _today => eatTodayString(widget.now?.call());

  Map<String, dynamic>? get _user => AppScope.of(context).auth.user;

  bool _mayVoid(String? byId, String? at) =>
      canVoidPurchaseRecord(_user, byId: byId, at: at, now: widget.now?.call());

  // ── actions ──────────────────────────────────────────────────────────

  Future<void> _recordPayment() async {
    final p = _p!;
    final out = await showFFSheet<Map<String, dynamic>>(
      context,
      title: fillIn(context.tr('vendor.purchases.payTitle'), {
        'supplier':
            nameOf(p['supplier']) ?? context.tr('vendor.purchases.noSupplier'),
      }),
      isDismissible: false,
      child: RecordPurchasePaymentSheet(purchase: p, now: widget.now),
    );
    if (out == null || !mounted) return;
    setState(() => _p = mapOf(out['purchase']));
    FFSnack.success(
      context,
      fillIn(context.tr('vendor.purchases.paySaved'), {
        'amount': formatCurrency(intOfP(mapOf(out['payment'])['amountTzs'])),
      }),
    );
    final ctx = _paymentsKey.currentContext;
    if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx);
  }

  Future<void> _changePlan() async {
    final out = await showFFSheet<Map<String, dynamic>>(
      context,
      title: context.tr('vendor.purchases.changePlan'),
      isDismissible: false,
      child: ChangePlanSheet(purchase: _p!, now: widget.now),
    );
    if (out == null || !mounted) return;
    setState(() => _p = mapOf(out['purchase']));
    FFSnack.success(context, context.tr('vendor.purchases.planSaved'));
  }

  Future<void> _voidPurchase() async {
    final out = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VoidPurchaseDialog(purchase: _p!),
    );
    if (out == null || !mounted) return;
    if (out['reload'] == true) {
      FFSnack.info(context, context.tr('vendor.purchases.err.alreadyVoided'));
      await _load();
      return;
    }
    setState(() => _p = mapOf(out['purchase']));
    FFSnack.success(
      context,
      fillIn(context.tr('vendor.purchases.voided'), {'number': _p?['number']}),
    );
    _headingFocus.requestFocus();
  }

  Future<void> _voidPayment(Map<String, dynamic> payment) async {
    final out = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          VoidPurchasePaymentDialog(purchase: _p!, payment: payment),
    );
    if (out == null || !mounted) return;
    if (out['reload'] == true) {
      await _load();
      return;
    }
    setState(() => _p = mapOf(out['purchase']));
  }

  Future<void> _share() async {
    final p = _p!;
    final business = await loadBusinessName(context);
    if (!mounted) return;
    final locale = FFLocaleScope.of(context);
    final lang = locale.locale.languageCode;
    await shareReceipt(
      purchaseShareText(
        p,
        (k) => locale.tIn(lang, k),
        lang,
        business: business,
      ),
      fillIn(locale.tIn(lang, 'vendor.purchases.grnTitle'), {
        'number': p['number'],
      }),
    );
  }

  // ── build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final p = _p;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(p?['number']?.toString() ?? t('vendor.purchases.tab')),
      ),
      body: _loading && p == null
          ? const Center(child: FFSpinner())
          : p == null
          ? ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                if (_suspended)
                  FFAlert(
                    key: const Key('purchase-suspended'),
                    message: t('vendor.sales.suspended'),
                    tone: FFAlertTone.warning,
                  )
                else if (_failed)
                  FFErrorState(message: t('error.network'), onRetry: _load)
                else
                  FFEmptyState(
                    key: const Key('purchase-not-found'),
                    title: t('vendor.purchases.notFound'),
                  ),
              ],
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(FFTokens.spacingLg),
                    children: _content(p),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: p == null ? null : _actions(p),
    );
  }

  List<Widget> _content(Map<String, dynamic> p) {
    final t = context.tr;
    final theme = Theme.of(context);
    final lang = langOf(context);
    final voided = p['status'] == 'voided';
    final supplier = mapOf(p['supplier']);
    final recordedDay = eatDayOf(p['recordedAt']?.toString());
    final recordedLate =
        recordedDay != null &&
        p['receivedOn'] != null &&
        dayString(recordedDay) != p['receivedOn'].toString();
    final received = formatDay(p['receivedOn']?.toString(), locale: lang);
    final balance = intOfP(p['balanceTzs']);
    final overdue = intOfP(p['overdueTzs']);
    final canSeeCost = _tools.canSeeCost;
    return [
      Focus(
        focusNode: _headingFocus,
        child: Semantics(
          header: true,
          child: Text(
            fillIn(t('vendor.purchases.grnTitle'), {'number': p['number']}),
            key: const Key('purchase-heading'),
            style: theme.textTheme.titleLarge,
          ),
        ),
      ),
      const SizedBox(height: FFTokens.spacingXs),
      Wrap(
        spacing: FFTokens.spacingSm,
        runSpacing: FFTokens.spacingXs,
        children: [
          FFBadge(
            key: const Key('purchase-status'),
            label: t(
              voided
                  ? 'vendor.purchases.state.voided'
                  : 'vendor.purchases.state.received',
            ),
            tone: voided ? FFBadgeTone.gray : FFBadgeTone.success,
            wrap: true,
          ),
          if (!voided)
            FFBadge(
              key: const Key('purchase-payment-state'),
              label: t(paymentStateKey(p)),
              tone: paymentStateTone(p),
              wrap: true,
            ),
        ],
      ),
      const SizedBox(height: FFTokens.spacingSm),
      if (voided) ...[
        FFAlert(
          key: const Key('purchase-voided'),
          message: fillIn(t('vendor.purchases.voidedBy'), {
            'name': nameOf(p['voidedBy']) ?? '—',
            'time': eatDateTime(p['voidedAt']?.toString(), locale: lang),
            'reason': p['voidReason'] ?? '',
          }),
        ),
        const SizedBox(height: FFTokens.spacingSm),
      ],
      // Meta
      if (supplier.isNotEmpty)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FFButton(
            key: const Key('purchase-supplier'),
            label: supplier['name']?.toString() ?? '',
            icon: Icons.local_shipping_outlined,
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: purchaseIdPattern.hasMatch('${supplier['id']}')
                ? () => context.push(supplierRoute('${supplier['id']}'))
                : null,
          ),
        )
      else
        Text(t('vendor.purchases.noSupplier')),
      Text(
        recordedLate
            ? fillIn(t('vendor.purchases.receivedRecorded'), {
                'date': received,
                'time': eatDateTime(p['recordedAt']?.toString(), locale: lang),
              })
            : fillIn(t('vendor.purchases.receivedOnDate'), {'date': received}),
        key: const Key('purchase-received'),
      ),
      if (strOf(p['supplierInvoiceRef']) case final ref?)
        Text(fillIn(t('vendor.purchases.invoiceRefLine'), {'ref': ref})),
      if (nameOf(p['createdBy']) case final by?)
        Text(
          fillIn(t('vendor.purchases.recordedBy'), {'name': by}),
          style: theme.textTheme.bodySmall,
        ),
      if (strOf(p['note']) case final note?)
        Text(note, style: theme.textTheme.bodySmall),
      const SizedBox(height: FFTokens.spacingMd),
      // Items
      FFSectionTitle(t('vendor.purchases.itemsHeading')),
      FFCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final l in mapsOf(p['lines'])) _lineRow(l, canSeeCost),
          ],
        ),
      ),
      const SizedBox(height: FFTokens.spacingMd),
      // Money
      FFCard(
        key: const Key('purchase-money'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _money(t('vendor.purchases.total'), intOfP(p['totalTzs'])),
            _money(t('vendor.purchases.paid'), intOfP(p['paidTzs'])),
            if (!voided)
              _money(
                t('vendor.purchases.leftToPayLabel'),
                balance,
                strong: true,
                key: const Key('purchase-balance'),
              ),
            if (!voided && overdue > 0)
              Text(
                fillIn(t('vendor.purchases.overdueAmount'), {
                  'amount': formatCurrency(overdue),
                }),
                key: const Key('purchase-overdue'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: warningText(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
      if (!voided && instalmentsOf(p).isNotEmpty) ...[
        const SizedBox(height: FFTokens.spacingMd),
        FFSectionTitle(t('vendor.purchases.instalments')),
        FFCard(
          key: const Key('purchase-instalments'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final i in instalmentsOf(p)) _instalmentRow(i),
              if (balance > 0)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FFButton(
                    key: const Key('purchase-change-plan'),
                    label: t('vendor.purchases.changePlan'),
                    variant: FFButtonVariant.ghost,
                    visualDensity: VisualDensity.standard,
                    onPressed: BrowserOnline.instance.value
                        ? _changePlan
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ],
      if (mapsOf(p['payments']).isNotEmpty) ...[
        const SizedBox(height: FFTokens.spacingMd),
        FFSectionTitle(t('vendor.purchases.payments'), key: _paymentsKey),
        FFCard(
          key: const Key('purchase-payments'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final pay in mapsOf(p['payments'])) _paymentRow(pay, voided),
            ],
          ),
        ),
      ],
      const SizedBox(height: FFTokens.spacingMd),
      const PurchaseMoneyNotice(),
      if (!voided &&
          !_mayVoid(idOf(p['createdBy']), p['recordedAt']?.toString())) ...[
        const SizedBox(height: FFTokens.spacingSm),
        Text(
          t('vendor.purchases.askOwner'),
          key: const Key('purchase-ask-owner'),
          style: theme.textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: FFTokens.spacingLg),
    ];
  }

  Widget _money(String label, int v, {bool strong = false, Key? key}) {
    final style = strong
        ? Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(formatCurrency(v), style: style),
        ],
      ),
    );
  }

  Widget _lineRow(Map<String, dynamic> l, bool canSeeCost) {
    final t = context.tr;
    final theme = Theme.of(context);
    final variant = strOf(l['variant']);
    final name = variant == null
        ? '${l['nameSnapshot'] ?? ''}'
        : '${l['nameSnapshot'] ?? ''} ($variant)';
    final tags = <String>[
      if (l['free'] == true) t('vendor.purchases.free'),
      if (l['costUpdated'] == true)
        canSeeCost && l['previousCostTzs'] is num
            ? fillIn(t('vendor.purchases.costUpdatedFrom'), {
                'from': formatCurrency(intOfP(l['previousCostTzs'])),
              })
            : t('vendor.purchases.costUpdated'),
      if (l['costRestoredOnVoid'] == true) t('vendor.purchases.costRestored'),
      if (l['costRestoredOnVoid'] == false) t('vendor.purchases.costKept'),
    ];
    return Padding(
      key: Key('purchase-line-${l['id']}'),
      padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${intOfP(l['qty'])} × $name',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(formatCurrency(intOfP(l['lineTotalTzs']))),
            ],
          ),
          Text(
            '@ ${formatCurrency(intOfP(l['unitCostTzs']))}',
            style: theme.textTheme.bodySmall,
          ),
          if (tags.isNotEmpty)
            Wrap(
              spacing: FFTokens.spacingXs,
              runSpacing: FFTokens.spacingXs,
              children: [
                for (final tag in tags) FFBadge(label: tag, wrap: true),
              ],
            ),
        ],
      ),
    );
  }

  Widget _instalmentRow(Instalment i) {
    final t = context.tr;
    final lang = langOf(context);
    final date = formatDay(i.dueDate, locale: lang);
    final state = i.state == 'due'
        ? dueText(t, i.dueDate, _today)
        : instalmentStateText(t, i);
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label:
          '${fillIn(t('vendor.purchases.instalmentN'), {'n': i.seq})}, $date, ${formatCurrency(i.amountTzs)}, $state',
      excludeSemantics: true,
      child: ConstrainedBox(
        key: Key('purchase-inst-${i.seq}'),
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Text('${i.seq} · $date · ${formatCurrency(i.amountTzs)}'),
            ),
            Flexible(
              child: Text(
                state,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: i.state == 'overdue' ? warningText(context) : null,
                  fontWeight: i.state == 'overdue' ? FontWeight.w600 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentRow(Map<String, dynamic> pay, bool purchaseVoided) {
    final t = context.tr;
    final lang = langOf(context);
    final theme = Theme.of(context);
    final voided = pay['status'] == 'voided';
    final amount = formatCurrency(intOfP(pay['amountTzs']));
    final date = formatDay(pay['paidOn']?.toString(), locale: lang);
    final method = t(paymentMethodKey(pay['method']?.toString()));
    final ref = strOf(pay['reference']);
    final mayVoid =
        !voided &&
        !purchaseVoided &&
        BrowserOnline.instance.value &&
        _mayVoid(idOf(pay['recordedBy']), pay['recordedAt']?.toString());
    return Padding(
      key: Key('purchase-payment-${pay['id']}'),
      padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$date · ${ref == null ? method : '$method ($ref)'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    decoration: voided ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (nameOf(pay['recordedBy']) case final by?)
                  Text(
                    fillIn(t('vendor.purchases.by'), {'name': by}),
                    style: theme.textTheme.bodySmall,
                  ),
                Wrap(
                  spacing: FFTokens.spacingXs,
                  children: [
                    if (pay['atReceipt'] == true)
                      FFBadge(
                        label: t('vendor.purchases.atDelivery'),
                        wrap: true,
                      ),
                    if (voided)
                      FFBadge(
                        label: t('vendor.purchases.state.voided'),
                        tone: FFBadgeTone.gray,
                        wrap: true,
                      ),
                  ],
                ),
                if (voided && strOf(pay['voidReason']) != null)
                  Text(
                    fillIn(t('vendor.purchases.voidedReason'), {
                      'reason': pay['voidReason'],
                    }),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Text(
            amount,
            style: theme.textTheme.titleSmall?.copyWith(
              decoration: voided ? TextDecoration.lineThrough : null,
            ),
          ),
          if (mayVoid)
            PopupMenuButton<String>(
              key: Key('purchase-payment-more-${pay['id']}'),
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              tooltip: t('vendor.purchases.paymentActions'),
              onSelected: (_) => _voidPayment(pay),
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: Key('purchase-payment-void-${pay['id']}'),
                  value: 'void',
                  child: Semantics(
                    label: fillIn(t('vendor.purchases.voidPaymentLabel'), {
                      'amount': amount,
                      'date': date,
                    }),
                    child: Text(t('vendor.purchases.voidPayment')),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget? _actions(Map<String, dynamic> p) {
    final t = context.tr;
    final voided = p['status'] == 'voided';
    final online = BrowserOnline.instance.value;
    final balance = intOfP(p['balanceTzs']);
    final mayVoid =
        !voided && _mayVoid(idOf(p['createdBy']), p['recordedAt']?.toString());
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        child: Wrap(
          spacing: FFTokens.spacingSm,
          runSpacing: FFTokens.spacingSm,
          alignment: WrapAlignment.end,
          children: [
            if (!voided && balance > 0)
              FFButton(
                key: const Key('purchase-record-payment'),
                label: t('vendor.purchases.recordPayment'),
                icon: Icons.payments_outlined,
                visualDensity: VisualDensity.standard,
                onPressed: online ? _recordPayment : null,
              ),
            FFButton(
              key: const Key('purchase-share'),
              label: t('vendor.purchases.shareText'),
              icon: Icons.share,
              variant: FFButtonVariant.secondary,
              visualDensity: VisualDensity.standard,
              onPressed: _share,
            ),
            if (mayVoid)
              FFButton(
                key: const Key('purchase-void'),
                label: t('vendor.purchases.void'),
                semanticLabel: fillIn(t('vendor.purchases.voidA11y'), {
                  'number': p['number'],
                }),
                icon: Icons.block,
                variant: FFButtonVariant.destructive,
                visualDensity: VisualDensity.standard,
                onPressed: online ? _voidPurchase : null,
              ),
          ],
        ),
      ),
    );
  }
}

// ── record payment (§4.5) ────────────────────────────────────────────────

class RecordPurchasePaymentSheet extends StatefulWidget {
  const RecordPurchasePaymentSheet({
    super.key,
    required this.purchase,
    this.now,
  });

  final Map<String, dynamic> purchase;
  final DateTime Function()? now;

  @override
  State<RecordPurchasePaymentSheet> createState() =>
      _RecordPurchasePaymentSheetState();
}

class _RecordPurchasePaymentSheetState
    extends State<RecordPurchasePaymentSheet> {
  late Map<String, dynamic> _p = widget.purchase;
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  String _method = 'cash';
  String? _paidOn;
  bool _saving = false;
  String? _amountError;
  String? _problem;
  // Made once per sheet: Try again after a lost answer records it once.
  // Never ends in `:paid` (reserved for the payment at receipt).
  final String _clientRef = newPurchaseClientRef('vpay');

  String get _today => eatTodayString(widget.now?.call());
  int get _balance => intOfP(_p['balanceTzs']);
  int get _amountTzs => int.tryParse(_amount.text) ?? 0;

  @override
  void initState() {
    super.initState();
    final next = mapOf(_p['nextDue']);
    final v = intOfP(next['openTzs']);
    _amount.text = '${v > 0 ? v : _balance}';
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _needsRef => referenceRequiredMethods.contains(_method);
  bool get _ok =>
      _amountTzs >= 1 &&
      _amountTzs <= _balance &&
      (!_needsRef || _reference.text.trim().isNotEmpty) &&
      BrowserOnline.instance.value;

  Future<void> _save() async {
    if (!_ok || _saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _problem = null;
      _amountError = null;
    });
    final body = {
      'clientRef': _clientRef,
      'amountTzs': _amountTzs,
      if (_paidOn != null && _paidOn != _today) 'paidOn': _paidOn,
      'method': _method,
      if (_method != 'cash' && _reference.text.trim().isNotEmpty)
        'reference': _reference.text.trim(),
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
    };
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorRecordPurchasePayment('${_p['id']}', body);
      if (mounted) Navigator.of(context).pop(res);
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      final b = e.body is Map ? e.body as Map : const {};
      if (e.code == 'overpayment') {
        _p = {..._p, 'balanceTzs': intOfP(b['balanceTzs'])};
        _amountError = purchaseErrorText(context.tr, e, where: 'payment');
      } else {
        _problem = purchaseErrorText(context.tr, e, where: 'payment');
      }
    } catch (_) {
      if (mounted) _problem = context.tr('vendor.purchases.offlineWrite');
    }
    if (mounted) setState(() => _saving = false);
  }

  String _coversText(List<CoveredPart> parts, String lang) {
    final t = context.tr;
    final bits = [
      for (final c in parts)
        c.paysOff && c.instalment.coveredTzs == 0
            ? fillIn(t('vendor.purchases.payCoversInst'), {
                'n': c.instalment.seq,
                'date': formatDay(c.instalment.dueDate, locale: lang),
              })
            : fillIn(t('vendor.purchases.payCoversPart'), {
                'amount': formatCurrency(c.amountTzs),
                'n': c.instalment.seq,
              }),
    ];
    return fillIn(t('vendor.purchases.payCovers'), {
      'list': bits.join(t('vendor.purchases.and')),
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final lang = langOf(context);
    final parts = previewCoverage(instalmentsOf(_p), _amountTzs);
    final received = _p['receivedOn']?.toString() ?? _today;
    return PopScope(
      canPop: !_saving,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_saving) Navigator.of(context).maybePop();
          },
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FFTextField(
              key: const Key('ppay-amount'),
              controller: _amount,
              label: t('vendor.purchases.amount'),
              suffixText: 'TSh',
              helperText: fillIn(t('vendor.purchases.leftToPay'), {
                'amount': formatCurrency(_balance),
              }),
              errorText:
                  _amountError ??
                  (_amountTzs > _balance
                      ? fillIn(t('vendor.purchases.err.overpayment'), {
                          'amount': formatCurrency(_balance),
                        })
                      : null),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              enabled: !_saving,
              onChanged: (_) => setState(() => _amountError = null),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FFButton(
                key: const Key('ppay-all'),
                label: fillIn(t('vendor.purchases.payAll'), {
                  'amount': formatCurrency(_balance),
                }),
                variant: FFButtonVariant.ghost,
                visualDensity: VisualDensity.standard,
                onPressed: _saving
                    ? null
                    : () => setState(() => _amount.text = '$_balance'),
              ),
            ),
            PurchaseDateField(
              key: const Key('ppay-date'),
              label: t('vendor.purchases.paidOn'),
              value: _paidOn ?? _today,
              earliest: received.compareTo(_today) > 0 ? _today : received,
              latest: _today,
              enabled: !_saving,
              onChanged: (d) => setState(() => _paidOn = d),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            PurchaseMethodPicker(
              keyPrefix: 'ppay',
              method: _method,
              onMethod: (m) => setState(() => _method = m),
              reference: _reference,
              onReference: (_) => setState(() {}),
              enabled: !_saving,
            ),
            FFTextField(
              key: const Key('ppay-note'),
              controller: _note,
              label: t('vendor.purchases.note'),
              maxLength: purchasePaymentNoteMax,
              enabled: !_saving,
            ),
            if (parts.isNotEmpty)
              Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  _coversText(parts, lang),
                  key: const Key('ppay-covers'),
                ),
              ),
            const SizedBox(height: FFTokens.spacingSm),
            const PurchaseMoneyNotice(),
            if (_problem != null) ...[
              const SizedBox(height: FFTokens.spacingSm),
              Semantics(
                liveRegion: true,
                child: FFAlert(
                  key: const Key('ppay-problem'),
                  message: _problem!,
                  tone: FFAlertTone.error,
                ),
              ),
            ],
            const SizedBox(height: FFTokens.spacingMd),
            FFButton(
              key: const Key('ppay-save'),
              label: fillIn(t('vendor.purchases.savePayment'), {
                'amount': formatCurrency(_amountTzs),
              }),
              fullWidth: true,
              maxLines: 2,
              loading: _saving,
              visualDensity: VisualDensity.standard,
              onPressed: _ok ? _save : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── change instalments (P-11) ────────────────────────────────────────────

class ChangePlanSheet extends StatefulWidget {
  const ChangePlanSheet({super.key, required this.purchase, this.now});
  final Map<String, dynamic> purchase;
  final DateTime Function()? now;

  @override
  State<ChangePlanSheet> createState() => _ChangePlanSheetState();
}

class _ChangePlanSheetState extends State<ChangePlanSheet> {
  late final List<Instalment> _kept;
  late List<PlanRow> _rows;
  int _count = 1;
  late String _first;
  PlanEvery _every = PlanEvery.month;
  bool _saving = false;
  String? _problem;

  String get _today => eatTodayString(widget.now?.call());
  int get _balance => intOfP(widget.purchase['balanceTzs']);
  String get _latest =>
      addDaysTo('${widget.purchase['receivedOn']}', purchaseDueMaxDays);

  @override
  void initState() {
    super.initState();
    final plan = instalmentsOf(widget.purchase);
    _kept = plan.where((i) => i.coveredTzs > 0).toList();
    final open = plan.where((i) => i.openTzs > 0).toList();
    _rows = [
      for (final i in open)
        PlanRow(
          i.dueDate.compareTo(_today) < 0 ? _today : i.dueDate,
          i.openTzs,
        ),
    ];
    _count = _rows.isEmpty ? 1 : _rows.length;
    _first = _rows.isEmpty ? _today : _rows.first.dueDate;
  }

  int get _sum => _rows.fold(0, (s, r) => s + r.amountTzs);
  bool get _ok =>
      _rows.isNotEmpty &&
      _sum == _balance &&
      _rows.every(
        (r) =>
            r.amountTzs >= 1 &&
            r.dueDate.compareTo(_today) >= 0 &&
            r.dueDate.compareTo(_latest) <= 0,
      ) &&
      BrowserOnline.instance.value;

  Future<void> _save() async {
    if (!_ok || _saving) return;
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      final res = await AppScope.of(context).api.vendorChangePurchasePlan(
        '${widget.purchase['id']}',
        [for (final r in _rows) r.toJson()],
      );
      if (mounted) Navigator.of(context).pop(res);
      return;
    } on ApiException catch (e) {
      if (mounted) _problem = purchaseErrorText(context.tr, e, where: 'plan');
    } catch (_) {
      if (mounted) _problem = context.tr('vendor.purchases.offlineWrite');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final lang = langOf(context);
    return PopScope(
      canPop: !_saving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            fillIn(t('vendor.purchases.paidSoFar'), {
              'amount': formatCurrency(intOfP(widget.purchase['paidTzs'])),
            }),
          ),
          for (final i in _kept)
            Text(
              '${fillIn(t('vendor.purchases.instalmentN'), {'n': i.seq})} · ${formatDay(i.dueDate, locale: lang)} · ${formatCurrency(i.coveredTzs)} · ${t('vendor.purchases.planKept')}',
              key: Key('plan-kept-${i.seq}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            fillIn(t('vendor.purchases.mustAddUp'), {
              'balance': formatCurrency(_balance),
            }),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          SplitControls(
            minCount: 1,
            count: _count,
            onCount: (n) => setState(() => _count = n),
            firstDue: _first,
            onFirstDue: (d) => setState(() => _first = d),
            every: _every,
            onEvery: (e) => setState(() => _every = e),
            onSplit: () => setState(
              () => _rows = scheduleFor(
                _balance,
                0,
                _count,
                _first,
                every: _every,
              ),
            ),
            earliest: _today,
            latest: _latest,
            enabled: !_saving,
          ),
          InstalmentRowsEditor(
            rows: _rows,
            leftTzs: _balance,
            earliest: _today,
            latest: _latest,
            firstNumber: _kept.where((i) => i.openTzs == 0).length + 1,
            enabled: !_saving,
            onChanged: () => setState(() {}),
          ),
          if (_problem != null)
            Semantics(
              liveRegion: true,
              child: FFAlert(message: _problem!, tone: FFAlertTone.error),
            ),
          const SizedBox(height: FFTokens.spacingMd),
          FFButton(
            key: const Key('plan-save'),
            label: t('vendor.purchases.savePlan'),
            fullWidth: true,
            loading: _saving,
            visualDensity: VisualDensity.standard,
            onPressed: _ok ? _save : null,
          ),
        ],
      ),
    );
  }
}

// ── voids ────────────────────────────────────────────────────────────────

class VoidPurchaseDialog extends StatefulWidget {
  const VoidPurchaseDialog({super.key, required this.purchase});
  final Map<String, dynamic> purchase;

  @override
  State<VoidPurchaseDialog> createState() => _VoidPurchaseDialogState();
}

class _VoidPurchaseDialogState extends State<VoidPurchaseDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _short = const [];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _ok => _reason.text.trim().length >= purchaseReasonMin;

  void _close(Map<String, dynamic>? out) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(out);
  }

  Future<void> _submit() async {
    if (!_ok || _busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorVoidPurchase('${widget.purchase['id']}', _reason.text.trim());
      if (mounted) _close(res);
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'already_voided') {
        _close({'reload': true});
        return;
      }
      final b = e.body is Map ? e.body as Map : const {};
      setState(() {
        _short = e.code == 'insufficient_stock' ? mapsOf(b['lines']) : const [];
        _error = purchaseErrorText(context.tr, e, where: 'void');
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.tr('vendor.purchases.offlineWrite'));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _count(Map<String, dynamic> line) async {
    try {
      final rows = await AppScope.of(context).api.vendorProducts();
      final product = rows
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .where((p) => p['id']?.toString() == line['productId']?.toString());
      if (product.isEmpty || !mounted) return;
      await openAdjustStock(
        context,
        product: product.first,
        variant: strOf(line['variant']),
        initialReason: 'count',
      );
    } catch (_) {
      if (mounted) FFSnack.error(context, context.tr('error.network'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final p = widget.purchase;
    final live = mapsOf(p['payments']).where((x) => x['status'] != 'voided');
    final paid = live.fold<int>(0, (s, x) => s + intOfP(x['amountTzs']));
    final costChanged = mapsOf(p['lines']).any((l) => l['costUpdated'] == true);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        key: const Key('purchase-void-dialog'),
        title: Text(
          fillIn(t('vendor.purchases.voidTitle'), {'number': p['number']}),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                fillIn(t('vendor.purchases.voidBody'), {'number': p['number']}),
              ),
              if (live.isNotEmpty) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Text(
                  fillIn(t('vendor.purchases.voidPayments'), {
                    'n': live.length,
                    'amount': formatCurrency(paid),
                  }),
                  key: const Key('purchase-void-payments'),
                ),
              ],
              if (costChanged) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Text(t('vendor.purchases.voidCost')),
              ],
              const SizedBox(height: FFTokens.spacingMd),
              voidReasonField(
                context,
                _reason,
                key: const Key('purchase-void-reason'),
                enabled: !_busy,
                onChanged: () => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Semantics(
                  liveRegion: true,
                  child: FFAlert(
                    key: const Key('purchase-void-error'),
                    message: _error!,
                    tone: FFAlertTone.error,
                  ),
                ),
                if (canVendor(context, 'products'))
                  for (final l in _short)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FFButton(
                        key: Key('purchase-void-count-${l['productId']}'),
                        label:
                            '${t('vendor.refunds.countStock')}: ${l['name'] ?? ''}',
                        variant: FFButtonVariant.ghost,
                        visualDensity: VisualDensity.standard,
                        onPressed: _busy ? null : () => _count(l),
                      ),
                    ),
              ],
            ],
          ),
        ),
        actions: [
          FFButton(
            label: t('common.cancel'),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: _busy ? null : () => _close(null),
          ),
          FFButton(
            key: const Key('purchase-void-confirm'),
            label: t('vendor.purchases.void'),
            variant: FFButtonVariant.destructive,
            visualDensity: VisualDensity.standard,
            loading: _busy,
            onPressed: _ok ? _submit : null,
          ),
        ],
      ),
    );
  }
}

class VoidPurchasePaymentDialog extends StatefulWidget {
  const VoidPurchasePaymentDialog({
    super.key,
    required this.purchase,
    required this.payment,
  });
  final Map<String, dynamic> purchase;
  final Map<String, dynamic> payment;

  @override
  State<VoidPurchasePaymentDialog> createState() =>
      _VoidPurchasePaymentDialogState();
}

class _VoidPurchasePaymentDialogState extends State<VoidPurchasePaymentDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _ok => _reason.text.trim().length >= purchaseReasonMin;

  Future<void> _submit() async {
    if (!_ok || _busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await AppScope.of(context).api.vendorVoidPurchasePayment(
        '${widget.purchase['id']}',
        '${widget.payment['id']}',
        _reason.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(res);
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'already_voided') {
        Navigator.of(context).pop({'reload': true});
        return;
      }
      setState(
        () => _error = purchaseErrorText(
          context.tr,
          e,
          where: 'paymentVoid',
          name: nameOf(widget.purchase['supplier']),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.tr('vendor.purchases.offlineWrite'));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final pay = widget.payment;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        key: const Key('purchase-payment-void-dialog'),
        title: Text(
          fillIn(t('vendor.purchases.voidPaymentTitle'), {
            'amount': formatCurrency(intOfP(pay['amountTzs'])),
            'date': formatDay(
              pay['paidOn']?.toString(),
              locale: langOf(context),
            ),
          }),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('vendor.purchases.voidPaymentBody')),
              const SizedBox(height: FFTokens.spacingMd),
              voidReasonField(
                context,
                _reason,
                key: const Key('purchase-payment-void-reason'),
                enabled: !_busy,
                onChanged: () => setState(() {}),
              ),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: FFAlert(
                    key: const Key('purchase-payment-void-error'),
                    message: _error!,
                    tone: FFAlertTone.error,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          FFButton(
            label: t('common.cancel'),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
          FFButton(
            key: const Key('purchase-payment-void-confirm'),
            label: t('vendor.purchases.voidPayment'),
            variant: FFButtonVariant.destructive,
            visualDensity: VisualDensity.standard,
            loading: _busy,
            onPressed: _ok ? _submit : null,
          ),
        ],
      ),
    );
  }
}
