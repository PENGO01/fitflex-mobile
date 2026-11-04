// Vendor tools · S9: Receive stock (spec §4.2–§4.4, §4.9, §4.10). Who it
// came from, what came, what it cost, what was paid. Online only: the form
// is kept as a local draft (Q-5) and a delivery is never queued. A clientRef
// is made on the first Confirm and reused on Try again.
import 'dart:async';

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
import '../../../shared/vendor_purchase_draft_store.dart';
import '../customers/customer_models.dart' show addDaysTo, formatDay;
import '../sales/receipt_data.dart' show eatDateTime;
import '../sales/sale_models.dart'
    show paymentMethodKey, pluralKey, stockVariants;
import '../stock/stock_options.dart';
import 'purchase_draft_controller.dart';
import 'purchase_models.dart';
import 'purchases_widgets.dart';

class ReceiveStockPage extends StatefulWidget {
  const ReceiveStockPage({super.key, this.supplierId, this.now});

  /// "Receive stock from {name}" (a supplier profile).
  final String? supplierId;

  /// Test hook for "today" (EAT).
  final DateTime Function()? now;

  @override
  State<ReceiveStockPage> createState() => _ReceiveStockPageState();
}

class _ReceiveStockPageState extends State<ReceiveStockPage> {
  late PurchaseDraftController _draft;
  VendorTools _tools = VendorTools.off;
  bool _ready = false;
  List<Map<String, dynamic>> _products = [];
  bool _productsFailed = false;

  /// 403 vendor_suspended (the business is suspended): nothing can be
  /// received; the draft stays.
  bool _suspended = false;

  /// A draft kept from before, waiting for Continue / Start again.
  Map<String, dynamic>? _stored;

  bool _detailsOpen = false;
  String? _supplierError;
  String? _paymentError;
  String? _detailsError;
  String? _generalError;

  final _invoiceRef = TextEditingController();
  final _note = TextEditingController();
  final _paidNow = TextEditingController();
  final _reference = TextEditingController();
  final Map<String, TextEditingController> _qty = {};
  final Map<String, TextEditingController> _cost = {};
  final Set<String> _typedCost = {};
  final _supplierKey = GlobalKey();
  final _paymentKey = GlobalKey();
  final Map<String, GlobalKey> _lineKeys = {};

  @override
  void initState() {
    super.initState();
    _draft = PurchaseDraftController(now: widget.now);
    BrowserOnline.instance.addListener(_redraw);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _redraw() {
    if (!mounted) return;
    _syncLineFields();
    setState(() {});
  }

  /// UAT H-1: the draft holds every typed quantity and unit cost (written on
  /// each change, never on blur) and is the source of truth: a line field
  /// whose text no longer says what the draft holds is put back. Run from
  /// the draft's listener, never during build.
  void _syncLineFields() {
    for (final l in _draft.lines) {
      _controllersFor(l);
      final qty = _qty[l.key]!;
      if ((int.tryParse(qty.text) ?? 0) != l.qty) qty.text = '${l.qty}';
      final cost = _cost[l.key]!;
      if (int.tryParse(cost.text) != l.unitCostTzs) {
        cost.text = l.unitCostTzs == null ? '' : '${l.unitCostTzs}';
      }
    }
  }

  @override
  void dispose() {
    BrowserOnline.instance.removeListener(_redraw);
    _draft.removeListener(_redraw);
    // A pending debounced save still runs (the draft stays on the device).
    unawaited(_draft.saveNow());
    _draft.dispose();
    for (final c in [
      _invoiceRef,
      _note,
      _paidNow,
      _reference,
      ..._qty.values,
      ..._cost.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    final tools = await enterPurchasesRoute(context);
    if (tools == null || !mounted) return;
    final key = VendorPurchaseDraftStore.keyFor(AppScope.of(context).auth.user);
    _draft.removeListener(_redraw);
    _draft.dispose();
    _draft = PurchaseDraftController(storageKey: key, now: widget.now)
      ..addListener(_redraw);
    final stored = await VendorPurchaseDraftStore.load(key);
    if (!mounted) return;
    setState(() {
      _tools = tools;
      _ready = true;
      _stored = stored != null && (stored['lines'] as List? ?? []).isNotEmpty
          ? stored
          : null;
    });
    unawaited(_loadProducts());
    if (widget.supplierId != null &&
        purchaseIdPattern.hasMatch(widget.supplierId!)) {
      unawaited(_preselectSupplier(widget.supplierId!));
    }
  }

  Future<void> _loadProducts() async {
    try {
      final rows = await AppScope.of(context).api.vendorProducts();
      if (!mounted) return;
      setState(() {
        _products = rows.whereType<Map>().map(Map<String, dynamic>.from).where((
          p,
        ) {
          return p['status'] != 'archived' && p['deletedAt'] == null;
        }).toList();
        _productsFailed = false;
      });
      _refreshLineHints();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _productsFailed = true;
        _suspended = e.code == 'vendor_suspended';
      });
    } catch (_) {
      if (mounted) setState(() => _productsFailed = true);
    }
  }

  Future<void> _preselectSupplier(String id) async {
    try {
      final res = await AppScope.of(context).api.vendorSupplier(id);
      final s = mapOf(res['supplier']);
      if (!mounted || s.isEmpty || s['archived'] == true) return;
      _draft.supplier = {
        'id': s['id'],
        'name': s['name'],
        'phone': s['phone'],
        'owedTzs': intOfP(res['owedTzs']),
      };
      _draft.changed();
    } catch (_) {
      // Chosen by hand instead.
    }
  }

  // ── the kept draft ───────────────────────────────────────────────────

  void _continueDraft() {
    final d = _stored;
    if (d == null) return;
    _draft.restore(d);
    _invoiceRef.text = _draft.invoiceRef;
    _note.text = _draft.note;
    _reference.text = _draft.reference;
    _paidNow.text = _draft.paidNowTzs == null ? '' : '${_draft.paidNowTzs}';
    for (final l in _draft.lines) {
      _controllersFor(l);
      if (l.unitCostTzs != null) _typedCost.add(l.key);
    }
    setState(() => _stored = null);
    _refreshLineHints();
  }

  Future<void> _startAgain() async {
    await _draft.discard();
    if (mounted) setState(() => _stored = null);
  }

  // ── lines ────────────────────────────────────────────────────────────

  void _controllersFor(DraftLine l) {
    _qty.putIfAbsent(l.key, () => TextEditingController(text: '${l.qty}'));
    _cost.putIfAbsent(
      l.key,
      () => TextEditingController(
        text: l.unitCostTzs == null ? '' : '${l.unitCostTzs}',
      ),
    );
    _lineKeys.putIfAbsent(l.key, GlobalKey.new);
  }

  Map<String, dynamic>? _productOf(String id) {
    for (final p in _products) {
      if (p['id']?.toString() == id) return p;
    }
    return null;
  }

  /// Stock now and (canSeeCost) the cost price of a line, from the product.
  void _fillFromProduct(DraftLine l) {
    final p = _productOf(l.productId);
    if (p == null) return;
    if (l.variant != null) {
      final v = (p['variants'] as List? ?? []).whereType<Map>().where(
        (v) => v['name']?.toString() == l.variant,
      );
      if (v.isNotEmpty) {
        final m = v.first;
        l.stockBefore = m['stock'] is num
            ? (m['stock'] as num).toInt()
            : intOfP(p['stock']);
        if (_tools.canSeeCost && m.containsKey('costTzs')) {
          l.costKnown = true;
          l.currentCostTzs = m['costTzs'] is num
              ? (m['costTzs'] as num).toInt()
              : null;
        }
        return;
      }
    }
    l.stockBefore = intOfP(p['stock']);
    if (_tools.canSeeCost && p.containsKey('costTzs')) {
      l.costKnown = true;
      l.currentCostTzs = p['costTzs'] is num
          ? (p['costTzs'] as num).toInt()
          : null;
    }
  }

  /// The prefill when nothing was typed: the last purchase cost, else the
  /// product's cost (canSeeCost; the variant's effective cost), else empty.
  int? _prefillOf(DraftLine l) {
    if (l.last != null) return l.last!.unitCostTzs;
    if (!_tools.canSeeCost) return null;
    final p = _productOf(l.productId);
    if (p == null) return null;
    if (l.variant != null) {
      for (final v in (p['variants'] as List? ?? []).whereType<Map>()) {
        if (v['name']?.toString() == l.variant &&
            v['effectiveCostTzs'] is num) {
          return (v['effectiveCostTzs'] as num).toInt();
        }
      }
    }
    return p['costTzs'] is num ? (p['costTzs'] as num).toInt() : null;
  }

  void _applyPrefill(DraftLine l) {
    if (_typedCost.contains(l.key)) return;
    final v = _prefillOf(l);
    if (v == null) return;
    l.unitCostTzs = v;
    _cost[l.key]?.text = '$v';
  }

  Future<void> _refreshLineHints() async {
    for (final l in _draft.lines) {
      _fillFromProduct(l);
    }
    final ids = {for (final l in _draft.lines) l.productId}.toList();
    if (ids.isNotEmpty) {
      try {
        final res = await AppScope.of(context).api.vendorPurchaseLastCosts(ids);
        for (final r in mapsOf(res['rows'])) {
          for (final l in _draft.lines) {
            if (l.productId == r['productId']?.toString() &&
                l.variant == strOf(r['variant'])) {
              l.last = LastCost(
                unitCostTzs: intOfP(r['unitCostTzs']),
                receivedOn: strOf(r['receivedOn']),
                supplierName: strOf(r['supplierName']),
                number: strOf(r['number']),
              );
            }
          }
        }
      } catch (_) {
        // No hint; the product's cost (if any) prefills.
      }
    }
    if (!mounted) return;
    for (final l in _draft.lines) {
      _applyPrefill(l);
    }
    setState(() {});
  }

  Future<void> _addItem() async {
    final picked = await showFFSheet<_Picked>(
      context,
      title: context.tr('vendor.purchases.addItem'),
      child: _ProductPicker(
        products: _products,
        failed: _productsFailed,
        suspended: _suspended,
        added: {for (final l in _draft.lines) l.key},
        onRetry: _loadProducts,
      ),
    );
    if (picked == null || !mounted) return;
    final p = picked.product;
    final existing = _draft.lineOf(p['id'].toString(), picked.variant);
    if (existing != null) {
      _focusLine(existing);
      return;
    }
    final line = _draft.add(
      DraftLine(
        productId: p['id'].toString(),
        variant: picked.variant,
        name: p['name']?.toString() ?? '',
      ),
    );
    _controllersFor(line);
    _fillFromProduct(line);
    _applyPrefill(line);
    setState(() {});
    await _refreshLineHints();
  }

  void _focusLine(DraftLine l) {
    final ctx = _lineKeys[l.key]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.2);
  }

  void _removeLine(DraftLine l) {
    _draft.remove(l);
    _qty.remove(l.key)?.dispose();
    _cost.remove(l.key)?.dispose();
    _typedCost.remove(l.key);
  }

  // ── supplier ─────────────────────────────────────────────────────────

  Future<void> _chooseSupplier() async {
    final out = await showFFSheet<Object>(
      context,
      title: context.tr('vendor.purchases.chooseSupplier'),
      child: const _SupplierPicker(),
    );
    if (out == null || !mounted) return;
    setState(() => _supplierError = null);
    if (out == _SupplierPicker.none) {
      _draft.supplier = null;
      _draft.noSupplier = true;
    } else if (out is Map) {
      _draft.supplier = Map<String, dynamic>.from(out);
      _draft.noSupplier = false;
    }
    _draft.changed();
  }

  // ── save ─────────────────────────────────────────────────────────────

  String _methodName(String m) => context.tr(paymentMethodKey(m));

  Future<void> _review() async {
    if (!_draft.canReview || !BrowserOnline.instance.value) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _draft.clientRef ??= newPurchaseClientRef('grn');
    setState(() {
      _generalError = null;
      _paymentError = null;
      _detailsError = null;
    });
    final out = await showDialog<Object>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmDialog(
        draft: _draft,
        methodName: _methodName,
        body: _draft.toRequest(_draft.clientRef!),
      ),
    );
    if (!mounted || out == null) return;
    if (out is Map<String, dynamic>) return _saved(out);
    if (out is ApiException) _refused(out);
  }

  Future<void> _saved(Map<String, dynamic> res) async {
    final p = mapOf(res['purchase']);
    await _draft.discard();
    if (!mounted) return;
    final id = p['id']?.toString() ?? '';
    FFSnack.success(
      context,
      fillIn(context.tr('vendor.purchases.saved'), {'number': p['number']}),
    );
    if (!purchaseIdPattern.hasMatch(id)) {
      context.go(purchasesHubRoute);
      return;
    }
    final target = purchaseRoute(id);
    if (context.canPop()) {
      context.pushReplacement(target, extra: res);
    } else {
      context.go(target, extra: res);
    }
  }

  void _refused(ApiException e) {
    final t = context.tr;
    final b = e.body is Map ? e.body as Map : const {};
    switch (e.code) {
      case 'product_not_found' || 'product_unavailable':
        final id = b['productId']?.toString();
        for (final l in _draft.lines) {
          if (l.productId == id) {
            l.error = purchaseErrorText(t, e, name: l.label);
          }
        }
        setState(() {});
        final first = _draft.lines.where((l) => l.error != null).firstOrNull;
        if (first != null) _focusLine(first);
      case 'supplier_archived' || 'supplier_not_found' || 'supplier_required':
        setState(
          () => _supplierError = purchaseErrorText(
            t,
            e,
            name: nameOf(_draft.supplier),
          ),
        );
        _ensure(_supplierKey);
      case 'overpayment' ||
          'schedule_mismatch' ||
          'invalid_schedule' ||
          'due_date_out_of_range' ||
          'reference_required' ||
          'invalid_payment' ||
          'invalid_method':
        setState(() => _paymentError = purchaseErrorText(t, e));
        _ensure(_paymentKey);
      case 'received_on_out_of_range' ||
          'supplier_invoice_ref_too_long' ||
          'note_too_long':
        setState(() {
          _detailsOpen = true;
          _detailsError = e.code == 'received_on_out_of_range'
              ? purchaseErrorText(t, e)
              : t('vendor.purchases.err.tooLong');
        });
      case 'vendor_suspended':
        setState(() => _suspended = true);
      case 'feature_disabled':
        FFSnack.info(context, t('vendor.purchases.unavailable'));
        context.go('/vendor/home');
      case 'vendor_permission_forbidden':
        FFSnack.error(context, t('vendor.purchases.noAccess'));
        context.go('/vendor/home');
      default:
        setState(() => _generalError = purchaseErrorText(t, e));
    }
  }

  void _ensure(GlobalKey k) {
    final ctx = k.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.1);
  }

  // ── leaving ──────────────────────────────────────────────────────────

  Future<void> _leave() async {
    if (!_draft.hasContent) return _pop();
    final choice = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        key: const Key('purchase-leave-dialog'),
        title: Text(context.tr('vendor.purchases.leaveTitle')),
        actions: [
          FFButton(
            label: context.tr('common.cancel'),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: () => Navigator.of(d).pop(),
          ),
          FFButton(
            key: const Key('purchase-leave-discard'),
            label: context.tr('vendor.purchases.discard'),
            variant: FFButtonVariant.destructive,
            visualDensity: VisualDensity.standard,
            onPressed: () => Navigator.of(d).pop('discard'),
          ),
          FFButton(
            key: const Key('purchase-leave-keep'),
            label: context.tr('vendor.purchases.keepDraft'),
            visualDensity: VisualDensity.standard,
            onPressed: () => Navigator.of(d).pop('keep'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'discard') {
      await _draft.discard();
    } else {
      await _draft.saveNow();
    }
    if (mounted) _pop();
  }

  void _pop() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(purchasesHubRoute);
    }
  }

  // ── build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    return PopScope(
      canPop: !_draft.hasContent,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            key: const Key('purchase-close'),
            tooltip: t('vendor.purchases.close'),
            icon: const Icon(Icons.close),
            onPressed: _leave,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('vendor.purchases.receive')),
              if (_draft.savedAt != null)
                Text(
                  t('vendor.purchases.draftSaved'),
                  key: const Key('purchase-draft-saved'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        body: !_ready
            ? const Center(child: FFSpinner())
            : LayoutBuilder(
                builder: (context, box) {
                  final wide = box.maxWidth >= 900;
                  final left = [
                    if (_suspended) ...[
                      FFAlert(
                        key: const Key('purchase-suspended'),
                        message: context.tr('vendor.sales.suspended'),
                        tone: FFAlertTone.warning,
                      ),
                      const SizedBox(height: FFTokens.spacingMd),
                    ],
                    ..._draftAlert(),
                    ..._supplierSection(),
                    ..._itemsSection(),
                  ];
                  final right = [
                    ..._detailsSection(),
                    if (_draft.lines.isNotEmpty) ..._paymentSection(),
                  ];
                  if (wide) {
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: _list(left)),
                            Expanded(
                              flex: 4,
                              child: Column(
                                children: [
                                  Expanded(child: _list(right)),
                                  _reviewBar(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      Expanded(child: _list([...left, ...right])),
                      _reviewBar(),
                    ],
                  );
                },
              ),
      ),
    );
  }

  /// UAT H-1: the form is one non-lazy scroll view. A ListView builds only
  /// what is near the screen, so a line scrolled away while its field had
  /// focus was detached (on Flutter web its typed value came back empty).
  /// Here every line stays mounted, keyed by its line id.
  Widget _list(List<Widget> children) => SingleChildScrollView(
    key: const Key('purchase-form'),
    padding: const EdgeInsets.all(FFTokens.spacingLg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  List<Widget> _draftAlert() {
    final d = _stored;
    if (d == null) return const [];
    final at = PurchaseDraftController.savedAtOf(d);
    return [
      FFCard(
        key: const Key('purchase-draft-found'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              fillIn(context.tr('vendor.purchases.draftFound'), {
                'time': at == null
                    ? ''
                    : eatDateTime(
                        at.toIso8601String(),
                        locale: langOf(context),
                      ),
              }),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Wrap(
              spacing: FFTokens.spacingSm,
              runSpacing: FFTokens.spacingXs,
              children: [
                FFButton(
                  key: const Key('purchase-draft-continue'),
                  label: context.tr('vendor.purchases.continue'),
                  visualDensity: VisualDensity.standard,
                  onPressed: _continueDraft,
                ),
                FFButton(
                  key: const Key('purchase-draft-start-again'),
                  label: context.tr('vendor.purchases.startAgain'),
                  variant: FFButtonVariant.secondary,
                  visualDensity: VisualDensity.standard,
                  onPressed: _startAgain,
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: FFTokens.spacingMd),
    ];
  }

  List<Widget> _supplierSection() {
    final t = context.tr;
    final s = _draft.supplier;
    final theme = Theme.of(context);
    final name = nameOf(s);
    final phone = strOf(s?['phone']);
    final owed = intOfP(s?['owedTzs']);
    return [
      FFSectionTitle(t('vendor.purchases.supplier'), key: _supplierKey),
      FFCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (s == null) ...[
              if (_draft.noSupplier)
                Text(
                  t('vendor.purchases.noSupplier'),
                  key: const Key('purchase-no-supplier'),
                  style: theme.textTheme.titleSmall,
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FFButton(
                  key: const Key('purchase-choose-supplier'),
                  label: t(
                    _draft.noSupplier
                        ? 'vendor.purchases.change'
                        : 'vendor.purchases.chooseSupplier',
                  ),
                  icon: Icons.local_shipping_outlined,
                  variant: FFButtonVariant.secondary,
                  visualDensity: VisualDensity.standard,
                  onPressed: _chooseSupplier,
                ),
              ),
              Text(
                t('vendor.purchases.noSupplierHelp'),
                style: theme.textTheme.bodySmall,
              ),
            ] else
              Semantics(
                button: true,
                label: fillIn(t('vendor.purchases.supplierChosen'), {
                  'name': name ?? '',
                }),
                excludeSemantics: true,
                child: InkWell(
                  key: const Key('purchase-supplier-chosen'),
                  onTap: _chooseSupplier,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name ?? '',
                                style: theme.textTheme.titleSmall,
                              ),
                              if (phone != null && phone.length >= 3)
                                Text(
                                  fillIn(t('vendor.purchases.phoneEnds'), {
                                    'digits': phone.substring(phone.length - 3),
                                  }),
                                  style: theme.textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        Text(
                          t('vendor.purchases.change'),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (s != null && owed > 0)
              Text(
                fillIn(t('vendor.purchases.alreadyOwe'), {
                  'amount': formatCurrency(owed),
                }),
                key: const Key('purchase-already-owe'),
                style: theme.textTheme.bodySmall,
              ),
            if (_supplierError != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                  child: FFAlert(
                    key: const Key('purchase-supplier-error'),
                    message: _supplierError!,
                    tone: FFAlertTone.error,
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: FFTokens.spacingMd),
    ];
  }

  List<Widget> _itemsSection() {
    final t = context.tr;
    return [
      FFSectionTitle(t('vendor.purchases.items')),
      if (_draft.lines.isEmpty)
        FFEmptyState(
          key: const Key('purchase-no-items'),
          title: t('vendor.purchases.noItems'),
          icon: Icons.inventory_2_outlined,
        ),
      for (final l in _draft.lines) _lineCard(l),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FFButton(
          key: const Key('purchase-add-item'),
          label: t('vendor.purchases.addItem'),
          icon: Icons.add,
          variant: FFButtonVariant.ghost,
          visualDensity: VisualDensity.standard,
          onPressed: _draft.lines.length >= purchaseMaxLines ? null : _addItem,
        ),
      ),
      const SizedBox(height: FFTokens.spacingMd),
    ];
  }

  Widget _lineCard(DraftLine l) {
    final t = context.tr;
    final theme = Theme.of(context);
    final lang = langOf(context);
    _controllersFor(l);
    final name = l.label;
    String? notice;
    if (l.costOk) {
      if (l.free) {
        notice = t('vendor.purchases.freeLine');
      } else if (l.costChanges) {
        notice = l.costKnown && l.currentCostTzs != null
            ? fillIn(t('vendor.purchases.costWillChange'), {
                'from': formatCurrency(l.currentCostTzs!),
                'to': formatCurrency(l.unitCostTzs!),
              })
            : fillIn(t('vendor.purchases.costWillBeSet'), {
                'to': formatCurrency(l.unitCostTzs!),
              });
      }
    }
    Widget stepButton(IconData icon, String key, String label, int delta) =>
        IconButton(
          key: Key('purchase-line-$key-${l.productId}-${l.variant ?? ''}'),
          tooltip: fillIn(t(label), {'name': name}),
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          icon: Icon(icon),
          onPressed: () {
            final next = (l.qty + delta).clamp(1, purchaseMaxQty);
            _qty[l.key]!.text = '$next';
            _draft.setQty(l, next);
          },
        );
    return Padding(
      key: _lineKeys[l.key],
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: FFCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(name, style: theme.textTheme.titleSmall)),
                IconButton(
                  key: Key(
                    'purchase-line-remove-${l.productId}-${l.variant ?? ''}',
                  ),
                  tooltip: fillIn(t('vendor.purchases.removeLine'), {
                    'name': name,
                  }),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeLine(l),
                ),
              ],
            ),
            Row(
              children: [
                stepButton(
                  Icons.remove,
                  'minus',
                  'vendor.purchases.oneFewer',
                  -1,
                ),
                Expanded(
                  child: FFTextField(
                    key: Key(
                      'purchase-line-qty-${l.productId}-${l.variant ?? ''}',
                    ),
                    controller: _qty[l.key],
                    // UAT M-1: a real label (read with the value).
                    label: t('vendor.purchases.qty'),
                    // UAT L-12: the count is in the label too, so a screen
                    // reader on the web hears a prefilled value before the
                    // field is focused.
                    semanticsLabel: fillIn(t('vendor.purchases.qtyForValue'), {
                      'name': name,
                      'qty': _qty[l.key]!.text,
                    }),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    errorText: l.qtyOk
                        ? null
                        : t('vendor.purchases.qtyInvalid'),
                    onChanged: (v) => _draft.setQty(l, int.tryParse(v) ?? 0),
                  ),
                ),
                stepButton(Icons.add, 'plus', 'vendor.purchases.oneMore', 1),
              ],
            ),
            const SizedBox(height: FFTokens.spacingXs),
            FFTextField(
              key: Key('purchase-line-cost-${l.productId}-${l.variant ?? ''}'),
              controller: _cost[l.key],
              label: t('vendor.purchases.unitCost'),
              // UAT L-12: a prefilled cost is said before focus (web).
              semanticsLabel: l.unitCostTzs == null
                  ? fillIn(t('vendor.purchases.unitCostFor'), {'name': name})
                  : fillIn(t('vendor.purchases.unitCostForValue'), {
                      'name': name,
                      'amount': formatCurrency(l.unitCostTzs!),
                    }),
              prefixIcon: const Padding(
                padding: EdgeInsets.all(FFTokens.spacingSm),
                child: Text('TSh'),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              helperText: l.last == null
                  ? null
                  : l.last!.supplierName == null
                  // UAT L-2: never "from No supplier".
                  ? fillIn(t('vendor.purchases.lastCostNoSupplier'), {
                      'amount': formatCurrency(l.last!.unitCostTzs),
                      'date': formatDay(l.last!.receivedOn, locale: lang),
                    })
                  : fillIn(t('vendor.purchases.lastCost'), {
                      'amount': formatCurrency(l.last!.unitCostTzs),
                      'supplier': l.last!.supplierName,
                      'date': formatDay(l.last!.receivedOn, locale: lang),
                    }),
              errorText: _cost[l.key]!.text.isNotEmpty && !l.costOk
                  ? t('vendor.purchases.costInvalid')
                  : null,
              onChanged: (v) {
                _typedCost.add(l.key);
                _draft.setCost(l, v.isEmpty ? null : int.tryParse(v));
              },
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Row(
              children: [
                if (l.stockBefore != null)
                  Expanded(
                    child: Text(
                      fillIn(t('vendor.purchases.stockChange'), {
                        'from': formatStock(l.stockBefore!),
                        'to': formatStock(
                          l.stockBefore! + (l.qtyOk ? l.qty : 0),
                        ),
                      }),
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else
                  const Spacer(),
                Text(
                  formatCurrency(l.totalTzs),
                  key: Key(
                    'purchase-line-total-${l.productId}-${l.variant ?? ''}',
                  ),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            if (notice != null)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                child: Text(
                  notice,
                  key: Key(
                    'purchase-line-notice-${l.productId}-${l.variant ?? ''}',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (l.error != null)
              Semantics(
                liveRegion: true,
                child: FFAlert(message: l.error!, tone: FFAlertTone.error),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _detailsSection() {
    final t = context.tr;
    final lang = langOf(context);
    final today = _draft.today;
    final summary = [
      _draft.receivedDay == today
          ? t('vendor.purchases.receivedToday')
          : fillIn(t('vendor.purchases.receivedOnDate'), {
              'date': formatDay(_draft.receivedDay, locale: lang),
            }),
      _draft.invoiceRef.trim().isEmpty
          ? t('vendor.purchases.noInvoiceRef')
          : fillIn(t('vendor.purchases.invoiceRefLine'), {
              'ref': _draft.invoiceRef.trim(),
            }),
    ].join(' · ');
    return [
      FFSectionTitle(t('vendor.purchases.details')),
      FFCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: _detailsOpen,
              label: '${t('vendor.purchases.details')}, $summary',
              excludeSemantics: true,
              child: InkWell(
                key: const Key('purchase-details-toggle'),
                onTap: () => setState(() => _detailsOpen = !_detailsOpen),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      Expanded(child: Text(summary)),
                      Icon(
                        _detailsOpen ? Icons.expand_less : Icons.expand_more,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_detailsOpen) ...[
              PurchaseDateField(
                key: const Key('purchase-received-on'),
                label: t('vendor.purchases.receivedOn'),
                value: _draft.receivedDay,
                earliest: addDaysTo(today, -purchaseReceivedBackDays),
                latest: today,
                onChanged: (d) {
                  _draft.receivedOn = d;
                  _draft.changed();
                },
              ),
              FFTextField(
                key: const Key('purchase-invoice-ref'),
                controller: _invoiceRef,
                label: t('vendor.purchases.invoiceRef'),
                maxLength: purchaseInvoiceRefMax,
                onChanged: (v) {
                  _draft.invoiceRef = v;
                  _draft.changed();
                },
              ),
              FFTextField(
                key: const Key('purchase-note'),
                controller: _note,
                label: t('vendor.purchases.note'),
                maxLength: purchaseNoteMax,
                maxLines: 3,
                minLines: 1,
                onChanged: (v) {
                  _draft.note = v;
                  _draft.changed();
                },
              ),
            ],
            if (_detailsError != null)
              FFAlert(message: _detailsError!, tone: FFAlertTone.error),
          ],
        ),
      ),
      const SizedBox(height: FFTokens.spacingMd),
    ];
  }

  List<Widget> _paymentSection() {
    final t = context.tr;
    final theme = Theme.of(context);
    final d = _draft;
    final total = d.totalTzs;
    final latestDue = addDaysTo(d.receivedDay, purchaseDueMaxDays);
    return [
      FFSectionTitle(t('vendor.purchases.payment'), key: _paymentKey),
      FFCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              liveRegion: true,
              child: Row(
                children: [
                  Expanded(child: Text(t('vendor.purchases.total'))),
                  Text(
                    formatCurrency(total),
                    key: const Key('purchase-total'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            FFSegmented(
              key: const Key('purchase-pay-mode'),
              value: d.payMode.name,
              options: [
                (PayMode.full.name, t('vendor.purchases.paidFull')),
                (PayMode.part.name, t('vendor.purchases.paidPart')),
                (PayMode.none.name, t('vendor.purchases.notPaid')),
              ],
              onChanged: (v) {
                setState(() => _paymentError = null);
                d.payMode = PayMode.values.firstWhere((m) => m.name == v);
              },
            ),
            if (d.payMode != PayMode.none) ...[
              const SizedBox(height: FFTokens.spacingSm),
              PurchaseMethodPicker(
                keyPrefix: 'purchase',
                method: d.method,
                onMethod: (m) {
                  d.method = m;
                  d.changed();
                },
                reference: _reference,
                referenceError: d.referenceMissing && _reference.text.isNotEmpty
                    ? t('vendor.pos.referenceRequired')
                    : null,
                onReference: (v) {
                  d.reference = v;
                  d.changed();
                },
              ),
            ],
            if (d.payMode == PayMode.part) ...[
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                key: const Key('purchase-paid-now'),
                controller: _paidNow,
                label: t('vendor.purchases.paidNow'),
                suffixText: 'TSh',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                errorText: _paidNow.text.isNotEmpty && !d.partAmountOk
                    ? fillIn(t('vendor.purchases.err.overTotal'), {
                        'amount': formatCurrency(total),
                      })
                    : null,
                onChanged: (v) {
                  d.paidNowTzs = int.tryParse(v);
                  d.changed();
                },
              ),
            ],
            if (d.payMode != PayMode.full && d.leftTzs > 0) ...[
              const SizedBox(height: FFTokens.spacingSm),
              Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  fillIn(t('vendor.purchases.leftToPay'), {
                    'amount': formatCurrency(d.leftTzs),
                  }),
                  key: const Key('purchase-left'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (!d.split) ...[
                PurchaseDateField(
                  key: const Key('purchase-pay-by'),
                  label: t('vendor.purchases.payBy'),
                  value: d.payBy,
                  earliest: d.receivedDay,
                  latest: latestDue,
                  onChanged: (v) {
                    d.dueDate = v;
                    d.changed();
                  },
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FFButton(
                    key: const Key('purchase-split'),
                    label: t('vendor.purchases.split'),
                    variant: FFButtonVariant.ghost,
                    visualDensity: VisualDensity.standard,
                    onPressed: d.startSplit,
                  ),
                ),
              ] else ...[
                SplitControls(
                  count: d.splitCount,
                  onCount: (n) {
                    d.splitCount = n;
                    d.changed();
                  },
                  firstDue: d.firstDue ?? d.defaultDue,
                  onFirstDue: (v) {
                    d.firstDue = v;
                    d.changed();
                  },
                  every: d.every,
                  onEvery: (e) {
                    d.every = e;
                    d.changed();
                  },
                  onSplit: d.splitEvenly,
                  earliest: d.receivedDay,
                  latest: latestDue,
                ),
                const SizedBox(height: FFTokens.spacingSm),
                InstalmentRowsEditor(
                  rows: d.schedule,
                  leftTzs: d.leftTzs,
                  earliest: d.receivedDay,
                  latest: latestDue,
                  // Numbered from 1, as the portal does (UAT).
                  firstNumber: 1,
                  onChanged: d.changed,
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FFButton(
                    key: const Key('purchase-one-date'),
                    label: t('vendor.purchases.oneDate'),
                    variant: FFButtonVariant.ghost,
                    visualDensity: VisualDensity.standard,
                    onPressed: d.stopSplit,
                  ),
                ),
              ],
            ],
            if (_paymentError != null)
              Semantics(
                liveRegion: true,
                child: FFAlert(
                  key: const Key('purchase-payment-error'),
                  message: _paymentError!,
                  tone: FFAlertTone.error,
                ),
              ),
            const SizedBox(height: FFTokens.spacingSm),
            const PurchaseMoneyNotice(),
          ],
        ),
      ),
      const SizedBox(height: FFTokens.spacingMd),
    ];
  }

  Widget _reviewBar() {
    final t = context.tr;
    final online = BrowserOnline.instance.value;
    final problem = _suspended
        ? 'vendor.sales.suspended'
        : !online
        ? 'vendor.purchases.offline'
        : _draft.problem;
    final theme = Theme.of(context);
    return Material(
      elevation: 4,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_generalError != null) ...[
                Semantics(
                  liveRegion: true,
                  child: FFAlert(
                    key: const Key('purchase-error'),
                    message: _generalError!,
                    tone: FFAlertTone.error,
                  ),
                ),
                const SizedBox(height: FFTokens.spacingXs),
              ],
              if (problem != null) ...[
                Semantics(
                  container: true,
                  liveRegion: true,
                  child: Text(
                    fillIn(t(problem), {
                      'left': formatCurrency(_draft.leftTzs),
                    }),
                    key: const Key('purchase-review-why'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: FFTokens.spacingXs),
              ],
              FFButton(
                key: const Key('purchase-review'),
                label: fillIn(t('vendor.purchases.review'), {
                  'amount': formatCurrency(_draft.totalTzs),
                }),
                fullWidth: true,
                maxLines: 2,
                visualDensity: VisualDensity.standard,
                onPressed: problem == null ? _review : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── confirm (§4.4) ───────────────────────────────────────────────────────

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({
    required this.draft,
    required this.methodName,
    required this.body,
  });

  final PurchaseDraftController draft;
  final String Function(String) methodName;
  final Map<String, dynamic> body;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  bool _saving = false;
  String? _problem;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorReceiveStock(widget.body);
      if (mounted) Navigator.of(context).pop(res);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status >= 500) {
        // Unknown: Try again resends the same clientRef (recorded once).
        setState(() {
          _saving = false;
          _problem = context.tr('vendor.purchases.err.server');
        });
        return;
      }
      if (e.status == 429) {
        setState(() {
          _saving = false;
          _problem = purchaseErrorText(context.tr, e);
        });
        return;
      }
      Navigator.of(context).pop(e);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _problem = context.tr('vendor.purchases.offline');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final d = widget.draft;
    final lang = langOf(context);
    final supplier = nameOf(d.supplier);
    final changes = d.lines.where((l) => l.costChanges).length;
    final plan = d.leftTzs <= 0
        ? null
        : d.split && d.schedule.isNotEmpty
        ? fillIn(t('vendor.purchases.confirmPlan'), {
            'n': d.schedule.length,
            'list': d.schedule
                .map(
                  (r) =>
                      '${formatDay(r.dueDate, locale: lang)} ${formatCurrency(r.amountTzs)}',
                )
                .join(', '),
          })
        : fillIn(t('vendor.purchases.confirmPayBy'), {
            'date': formatDay(d.payBy, locale: lang),
          });
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        key: const Key('purchase-confirm'),
        title: Text(
          supplier == null
              ? fillIn(
                  t(
                    pluralKey(
                      'vendor.purchases.confirmTitleNoSupplier',
                      d.units,
                    ),
                  ),
                  {'units': d.units},
                )
              : fillIn(t(pluralKey('vendor.purchases.confirmTitle', d.units)), {
                  'units': d.units,
                  'supplier': supplier,
                }),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final l in d.lines)
                Text('${l.qty} × ${l.label} · ${formatCurrency(l.totalTzs)}'),
              const SizedBox(height: FFTokens.spacingSm),
              Text(
                '${t('vendor.purchases.total')} ${formatCurrency(d.totalTzs)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (d.paysNow)
                Text(
                  '${fillIn(t('vendor.purchases.confirmPaidNow'), {'method': widget.methodName(d.method)})} ${formatCurrency(d.paidNow)}',
                ),
              if (plan != null) ...[
                Text(
                  fillIn(t('vendor.purchases.leftToPay'), {
                    'amount': formatCurrency(d.leftTzs),
                  }),
                ),
                Text(plan, key: const Key('purchase-confirm-plan')),
              ],
              if (changes > 0)
                Text(
                  fillIn(
                    t(pluralKey('vendor.purchases.costChanges', changes)),
                    {'n': changes},
                  ),
                ),
              if (_saving) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Semantics(
                  liveRegion: true,
                  child: Text(t('vendor.purchases.saving')),
                ),
              ],
              if (_problem != null) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Semantics(
                  liveRegion: true,
                  child: FFAlert(
                    key: const Key('purchase-confirm-problem'),
                    message: _problem!,
                    tone: FFAlertTone.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FFButton(
            key: const Key('purchase-confirm-back'),
            label: t('vendor.purchases.back'),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
          FFButton(
            key: const Key('purchase-confirm-save'),
            label: _problem == null
                ? t('vendor.purchases.confirm')
                : t('common.retry'),
            // UAT L-6: after a lost connection or a lost answer the button
            // is Try again (same clientRef), on screen and to a screen
            // reader.
            semanticLabel: _problem == null
                ? '${t('vendor.purchases.confirm')} ${formatCurrency(d.totalTzs)}'
                : t('common.retry'),
            loading: _saving,
            visualDensity: VisualDensity.standard,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

// ── pickers ──────────────────────────────────────────────────────────────

class _Picked {
  _Picked(this.product, this.variant);
  final Map<String, dynamic> product;
  final String? variant;
}

/// Search by name or SKU over the vendor's products (spec §4.3); tracked
/// variants open a variant chooser. Archived and deleted products are not
/// listed; paused / pending ones are, with a muted badge.
class _ProductPicker extends StatefulWidget {
  const _ProductPicker({
    required this.products,
    required this.failed,
    required this.added,
    required this.onRetry,
    this.suspended = false,
  });

  final List<Map<String, dynamic>> products;
  final bool failed;
  final bool suspended;
  final Set<String> added;
  final Future<void> Function() onRetry;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final _q = TextEditingController();
  Map<String, dynamic>? _variantsOf;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool _added(String id, String? variant) =>
      widget.added.contains('$id\u0000${variant ?? ''}');

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final theme = Theme.of(context);
    final p = _variantsOf;
    if (p != null) {
      final id = p['id'].toString();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${p['name']} · ${t('vendor.purchases.chooseVariant')}',
            style: theme.textTheme.titleSmall,
          ),
          for (final v in stockVariants(p))
            ListTile(
              key: Key('purchase-pick-variant-${v.name}'),
              minTileHeight: 56,
              title: Text(v.name),
              subtitle: Text(
                fillIn(t('vendor.purchases.inStockN'), {'n': v.stock}),
              ),
              trailing: _added(id, v.name)
                  ? FFBadge(label: t('vendor.purchases.added'))
                  : null,
              onTap: () => Navigator.of(context).pop(_Picked(p, v.name)),
            ),
        ],
      );
    }
    final q = _q.text.trim().toLowerCase();
    final rows = widget.products.where((p) {
      if (q.isEmpty) return true;
      return (p['name']?.toString().toLowerCase() ?? '').contains(q) ||
          (p['sku']?.toString().toLowerCase() ?? '').contains(q);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFTextField(
          key: const Key('purchase-product-search'),
          controller: _q,
          label: t('vendor.purchases.searchProducts'),
          prefixIcon: const Icon(Icons.search),
          onChanged: (_) => setState(() {}),
        ),
        if (widget.failed)
          FFErrorState(
            message: t(
              widget.suspended ? 'vendor.sales.suspended' : 'error.network',
            ),
            onRetry: () async {
              await widget.onRetry();
              if (mounted) setState(() {});
            },
          )
        else if (rows.isEmpty)
          FFEmptyState(title: t('vendor.purchases.noProducts'))
        else
          for (final p in rows.take(100)) _productTile(p),
      ],
    );
  }

  Widget _productTile(Map<String, dynamic> p) {
    final t = context.tr;
    final variants = stockVariants(p);
    final id = p['id'].toString();
    final listed =
        (p['status'] ?? 'active') == 'active' &&
        (p['approvalStatus'] ?? 'approved') == 'approved';
    final added = variants.isEmpty && _added(id, null);
    return ListTile(
      key: Key('purchase-pick-$id'),
      minTileHeight: 56,
      title: Text(p['name']?.toString() ?? ''),
      subtitle: Text(
        [
          if (variants.isNotEmpty)
            fillIn(
              t(pluralKey('vendor.purchases.variantCount', variants.length)),
              {'n': variants.length},
            ),
          fillIn(t('vendor.purchases.inStockN'), {'n': intOfP(p['stock'])}),
        ].join(' · '),
      ),
      trailing: Wrap(
        spacing: FFTokens.spacingXs,
        children: [
          if (!listed) FFBadge(label: t('vendor.purchases.notListed')),
          if (added) FFBadge(label: t('vendor.purchases.added')),
        ],
      ),
      onTap: () {
        if (variants.isNotEmpty) {
          setState(() => _variantsOf = p);
        } else {
          Navigator.of(context).pop(_Picked(p, null));
        }
      },
    );
  }
}

/// Active suppliers, recent first; search by name or phone; quick Add
/// supplier (name + phone); No supplier ("only if you paid in full").
class _SupplierPicker extends StatefulWidget {
  const _SupplierPicker();

  static const none = 'no-supplier';

  @override
  State<_SupplierPicker> createState() => _SupplierPickerState();
}

class _SupplierPickerState extends State<_SupplierPicker> {
  final _q = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _failed = false;
  bool _adding = false;
  bool _saving = false;
  String? _addError;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorSuppliers(q: _q.text, sort: 'recent');
      if (!mounted) return;
      setState(() {
        _rows = mapsOf(res['suppliers']);
        _loading = false;
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

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.length < supplierNameMin) {
      setState(() => _addError = context.tr('vendor.suppliers.nameRequired'));
      return;
    }
    setState(() {
      _saving = true;
      _addError = null;
    });
    try {
      final res = await AppScope.of(context).api.vendorCreateSupplier({
        'name': name,
        if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      });
      final s = mapOf(res['supplier']);
      if (mounted) Navigator.of(context).pop({...s, 'owedTzs': 0});
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _addError = purchaseErrorText(
          context.tr,
          e,
          where: 'supplier',
          name: name,
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _addError = context.tr('error.network');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFTextField(
          key: const Key('supplier-picker-search'),
          controller: _q,
          label: t('vendor.suppliers.search'),
          prefixIcon: const Icon(Icons.search),
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 300), _load);
          },
        ),
        if (_loading)
          FFSkeletonList(semanticLabel: t('vendor.suppliers.loading'))
        else if (_failed)
          FFErrorState(message: t('vendor.suppliers.failed'), onRetry: _load)
        else
          for (final s in _rows)
            ListTile(
              key: Key('supplier-pick-${s['id']}'),
              minTileHeight: 56,
              title: Text(s['name']?.toString() ?? ''),
              subtitle: Text(
                intOfP(s['owedTzs']) > 0
                    ? fillIn(t('vendor.suppliers.youOwe'), {
                        'amount': formatCurrency(intOfP(s['owedTzs'])),
                      })
                    : (strOf(s['phone']) ?? strOf(s['contactPerson']) ?? ''),
              ),
              onTap: () => Navigator.of(context).pop(s),
            ),
        const Divider(),
        if (!_adding)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FFButton(
              key: const Key('supplier-picker-add'),
              label: t('vendor.suppliers.add'),
              icon: Icons.add,
              variant: FFButtonVariant.ghost,
              visualDensity: VisualDensity.standard,
              onPressed: () => setState(() => _adding = true),
            ),
          )
        else ...[
          FFTextField(
            key: const Key('supplier-quick-name'),
            controller: _name,
            label: t('vendor.suppliers.name'),
            maxLength: supplierNameMax,
            enabled: !_saving,
          ),
          FFTextField(
            key: const Key('supplier-quick-phone'),
            controller: _phone,
            label: t('vendor.suppliers.phone'),
            helperText: t('vendor.suppliers.phoneHelp'),
            keyboardType: TextInputType.phone,
            enabled: !_saving,
          ),
          if (_addError != null)
            FFAlert(message: _addError!, tone: FFAlertTone.error),
          FFButton(
            key: const Key('supplier-quick-save'),
            label: t('vendor.suppliers.add'),
            loading: _saving,
            visualDensity: VisualDensity.standard,
            onPressed: _saving ? null : _add,
          ),
        ],
        const Divider(),
        ListTile(
          key: const Key('supplier-pick-none'),
          minTileHeight: 56,
          title: Text(t('vendor.purchases.noSupplier')),
          subtitle: Text(
            t('vendor.purchases.noSupplierHelp'),
            style: theme.textTheme.bodySmall,
          ),
          onTap: () => Navigator.of(context).pop(_SupplierPicker.none),
        ),
      ],
    );
  }
}
