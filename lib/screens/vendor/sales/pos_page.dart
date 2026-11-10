// Vendor tools · S3: the POS (spec §2). Ring up a walk-in sale with correct
// stock, take payment, and record it — or keep it on the device when there
// is no connection.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/network/browser_online.dart';
import '../barcodes/barcode_rules.dart';
import '../barcodes/scan_widgets.dart';
import '../barcodes/vendor_scan_controller.dart';
import '../barcodes/vendor_scan_panel.dart';
import '../customers/customer_models.dart';
import '../customers/customer_picker.dart';
import '../customers/customers_widgets.dart';
import '../stock/stock_options.dart';
import 'offline_sale_queue.dart';
import 'payment_sheet.dart';
import 'receipt_data.dart';
import 'sale_customer_section.dart';
import 'sale_models.dart';
import 'sales_widgets.dart';
import '../vendor_home_page.dart' show openNewProductWithCode;

/// The cart, saved to the device on every change (spec §2.5).
class PosCartController extends ChangeNotifier {
  PosCartController({PosCart? cart, this.onSaved}) : cart = cart ?? PosCart();

  PosCart cart;

  /// Where each change is saved (the session's draft store, once loaded).
  Future<void> Function(PosCart cart)? onSaved;

  void update(void Function(PosCart cart) change) {
    change(cart);
    notifyListeners();
    unawaited(onSaved?.call(cart));
  }

  void replace(PosCart next) {
    cart = next;
    notifyListeners();
    unawaited(onSaved?.call(cart));
  }
}

enum _LoadProblem { none, failed, noCache, noAccess }

class PosPage extends StatefulWidget {
  const PosPage({super.key});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  SalesSession? _session;
  VendorTools _tools = VendorTools.off;
  final _cart = PosCartController();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _lineFocus = <String, FocusNode>{};
  List<Map<String, dynamic>> _products = [];
  Map<String, dynamic> _profile = const {};
  bool _loading = true;
  bool _ready = false;
  bool _offline = false;
  // The product list came from the server (not the device's copy).
  bool _fresh = false;
  String? _cachedAt;
  _LoadProblem _problem = _LoadProblem.none;
  bool _notAllowed = false;
  // A line the server refused: its key and the words to show on it.
  String? _flagged;
  String? _flagText;
  // Move focus to the flagged line's stepper once it is on screen.
  bool _focusFlagged = false;

  // ── S8: barcodes ──
  /// Every product loaded (archived too), for matching codes: an archived
  /// product's code says "archived" instead of "unknown".
  List<Map<String, dynamic>> _allProducts = [];
  ProductCodeIndex _codeIndex = ProductCodeIndex.empty();
  VendorScanController? _scan;
  bool _scanOpen = false;
  ScanNotice? _scanNotice;
  // The line the last scan added to (for −/+ and Undo).
  ({String productId, String? variant})? _lastScanned;
  bool _undoable = false;
  final _scanButtonFocus = FocusNode();

  bool get _wide => MediaQuery.sizeOf(context).width >= 900;

  /// Selling is off: staff disabled, or the business is suspended (the
  /// paused notice shows). Queued sales stay.
  bool get _blocked => _notAllowed || (_session?.suspended ?? false);

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      // Typing again replaces an unknown-code message under the field.
      if (!_scanOpen && _search.text.isNotEmpty) _scanNotice = null;
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _session?.detach();
    _cart.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _scan?.dispose();
    _scanButtonFocus.dispose();
    for (final f in _lineFocus.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    final tools = await enterSalesRoute(context);
    if (tools == null || !mounted) return;
    _tools = tools;
    final session = SalesSession.of(context);
    if (session == null) return;
    _scan = VendorScanController(
      index: () => _codeIndex,
      lookup: apiScanLookup(AppScope.of(context).api),
      // Offline (§7): the saved product list only; a lookup that gets no
      // answer counts as offline too (UAT L-2).
      online: () => !_offline,
      offlineOnNetworkError: true,
    );
    _session = session..attach();
    await session.load();
    // Kept "suspended" from an earlier visit: ask the server whether that
    // still holds; selling stays off until a sales call succeeds.
    if (session.suspended) unawaited(_checkSuspended(session));
    final draft = await session.loadDraft();
    if (!mounted) return;
    _cart.cart = draft ?? PosCart();
    _cart.onSaved = session.saveDraft;
    setState(() => _ready = true);
    // An unfinished sale the seller left; not one just opened from
    // "Edit sale" on the sync screen.
    if (draft != null && draft.replacesClientRef == null) {
      FFSnack.info(context, context.tr('vendor.pos.draftKept'));
    }
    // S4: the draft keeps the customer's id only; its name is asked again.
    // Sale extras: a type kept from when the section was on is not sent
    // while it is off (nothing hidden goes with a sale) — unless the draft
    // was already being sent (it has a clientRef): changing the type would
    // mean a new key and a possible duplicate, and the server stores the
    // type whatever the flag says.
    if (draft?.customerType != null &&
        draft?.clientRef == null &&
        !_tools.saleCustomerDetailsOn) {
      _cart.update((c) => c.setCustomerType(null));
    }
    final customerId = draft?.customerId;
    if (customerId != null) {
      if (!_customersOn) {
        _cart.update((c) => c.setCustomer(null));
      } else {
        unawaited(_restoreCustomerName(customerId));
      }
    }
    final cached = await session.loadProducts();
    if (!mounted) return;
    if (cached != null && cached.products.isNotEmpty) {
      setState(() {
        _setAll(cached.products);
        _products = _sellable(cached.products);
        _cachedAt = cached.cachedAt;
        _loading = false;
      });
    }
    unawaited(_loadProfile());
    await _loadProducts();
  }

  // ── customer (S4) ─────────────────────────────────────────────────────

  /// Customers are on for this POS (attach a customer to a sale).
  bool get _customersOn => _tools.customers;

  /// Pay later: both tools and both permissions (spec §0.2).
  bool get _payLaterOn => payLaterAllowed(
    customersFlag: _tools.customers,
    walkInSales: _tools.walkInSales,
    canSales: canVendor(context, 'sales'),
    canCustomers: canVendor(context, 'customers'),
  );

  Future<void> _restoreCustomerName(String id) async {
    final name = await CustomerRepository.fetchName(context, id);
    if (!mounted || name == null || _cart.cart.customerId != id) return;
    setState(() => _cart.cart.customerName = name);
  }

  Future<void> _pickCustomer() async {
    final picked = await pickCustomer(context);
    if (picked == null || !mounted) return;
    _cart.update(
      (c) => c.setCustomer(
        picked.id,
        name: picked.name,
        owedTzs: picked.owedTzs,
        overdueTzs: picked.overdueTzs,
      ),
    );
  }

  void _removeCustomer() => _cart.update((c) => c.setCustomer(null));

  /// Sale extras #2: the payment sheet's Customer section, when on. Name
  /// and mobile use the S4 customer calls (customers on, online); the
  /// cart keeps the customer's id and the type only.
  SaleCustomerSetup? _customerSetup() {
    if (!_tools.saleCustomerDetailsOn) return null;
    final api = AppScope.of(context).api;
    final seesMoney = canVendor(context, 'customers');
    return SaleCustomerSetup(
      namesAllowed: _customersOn,
      online: () => !_offline && BrowserOnline.instance.value,
      customer: () =>
          (id: _cart.cart.customerId, name: _cart.cart.customerName),
      type: () => _cart.cart.customerType,
      setType: (t) => _cart.update((c) => c.setCustomerType(t)),
      link: (id, name, row) {
        if (name.isNotEmpty) CustomerRepository.remember(context, id, name);
        _cart.update(
          (c) => c.setCustomer(
            id,
            name: name.isEmpty ? null : name,
            owedTzs: seesMoney ? intOf(row['owedTzs']) : null,
            overdueTzs: seesMoney ? intOf(row['overdueTzs']) : null,
          ),
        );
      },
      unlink: _removeCustomer,
      pickCustomer: _pickCustomer,
      search: (q) async {
        final res = await api.vendorCustomers(q: q, limit: 10);
        return [
          for (final r in (res['customers'] as List? ?? []).whereType<Map>())
            Map<String, dynamic>.from(r),
        ];
      },
      create: (body) => api.vendorCreateCustomer(body),
    );
  }

  PayLaterSetup? _payLaterSetup() {
    if (!_payLaterOn) return null;
    final cart = _cart.cart;
    // An edited offline sale keeps its own day; otherwise today.
    final saleDay = cart.keepSoldAt && cart.soldAt != null
        ? eatTodayString(DateTime.tryParse(cart.soldAt!))
        : eatTodayString();
    return PayLaterSetup(
      online: !_offline,
      saleDay: saleDay,
      customer: () => (
        id: _cart.cart.customerId,
        name: _cart.cart.customerName,
        owedTzs: _cart.cart.customerOwedTzs,
        overdueTzs: _cart.cart.customerOverdueTzs,
      ),
      pickCustomer: _pickCustomer,
    );
  }

  Widget _customerChip() {
    final cart = _cart.cart;
    final id = cart.customerId;
    if (id == null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: FFPill(
          key: const Key('pos-customer-add'),
          label: context.tr('vendor.pos.customer.add'),
          onTap: _blocked ? null : _pickCustomer,
        ),
      );
    }
    final name =
        cart.customerName ?? context.tr('vendor.pos.customer.selected');
    return Row(
      children: [
        const Icon(Icons.person_outline),
        const SizedBox(width: FFTokens.spacingXs),
        Expanded(
          child: Text(
            name,
            key: const Key('pos-customer-name'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        IconButton(
          key: const Key('pos-customer-remove'),
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            visualDensity: VisualDensity.standard,
          ),
          tooltip: fillIn(context.tr('vendor.pos.customer.remove'), {
            'name': name,
          }),
          icon: const Icon(Icons.close),
          onPressed: _removeCustomer,
        ),
      ],
    );
  }

  Future<void> _checkSuspended(SalesSession session) async {
    try {
      await AppScope.of(context).api.vendorSales(limit: 1);
      session.salesAnswered();
    } on ApiException catch (e) {
      if (e.code == 'vendor_suspended') session.markSuspended();
    } catch (_) {
      // Offline: stays as it was.
    }
  }

  List<Map<String, dynamic>> _sellable(List<Map<String, dynamic>> rows) => [
    for (final p in rows)
      if (p['status'] != 'archived' && p['deletedAt'] == null) p,
  ];

  /// The receipt header: what this device kept first (works offline),
  /// then the server's, which is kept for next time.
  Future<void> _loadProfile() async {
    final session = _session;
    final api = AppScope.of(context).api;
    final kept = await session?.loadBusiness() ?? const {};
    if (mounted && kept.isNotEmpty && _profile.isEmpty) {
      setState(() => _profile = kept);
    }
    try {
      final p = await api.vendorProfile();
      await session?.saveBusiness(p);
      if (mounted) setState(() => _profile = p);
    } catch (_) {
      // Offline, or staff who may not read the profile: the kept header.
    }
  }

  Future<void> _loadProducts() async {
    final hadCache = _products.isNotEmpty;
    if (!hadCache) setState(() => _loading = true);
    final isStaff =
        AppScope.of(context).auth.user?['userType'] == 'vendor_staff';
    try {
      final rows = await AppScope.of(context).api.vendorProducts();
      final products = rows.whereType<Map<String, dynamic>>().toList();
      await _session?.saveProducts(products);
      if (!mounted) return;
      setState(() {
        _setAll(products);
        _products = _sellable(products);
        _fresh = true;
        _cachedAt = DateTime.now().toUtc().toIso8601String();
        _offline = false;
        _problem = _LoadProblem.none;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (isVendorStaffDisabled(e, vendorStaff: isStaff)) {
          _notAllowed = true;
        } else if (e.status == 403) {
          // Refused the product list (e.g. a permission was removed).
          if (!hadCache) _problem = _LoadProblem.noAccess;
        } else if (!hadCache) {
          _problem = _LoadProblem.failed;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = true;
        if (!hadCache) _problem = _LoadProblem.noCache;
      });
    }
  }

  // ── stock ───────────────────────────────────────────────────────────────

  Map<String, dynamic>? _product(String id) {
    for (final p in _products) {
      if (p['id']?.toString() == id) return p;
    }
    return null;
  }

  /// Known available: last loaded stock, minus sales waiting on this
  /// device, minus the cart (the server is the authority).
  int _available(Map<String, dynamic> p, String? variant, {bool cart = true}) {
    final inCart = cart
        ? _cart.cart.qtyOf(p['id']?.toString() ?? '', variant)
        : 0;
    final left = _stockFor(p, variant) - inCart;
    return left < 0 ? 0 : left;
  }

  /// Known stock for the cart: last loaded stock minus sales waiting on this
  /// device (not minus the cart).
  int _stockFor(Map<String, dynamic> p, String? variant) {
    final id = p['id']?.toString() ?? '';
    final productStock = (p['stock'] as num?)?.toInt() ?? 0;
    var stock = productStock;
    if (variant != null) {
      for (final v in stockVariants(p)) {
        if (v.name == variant) {
          stock = v.stock < productStock ? v.stock : productStock;
        }
      }
    }
    final queued = _session?.queuedQty(id, variant) ?? 0;
    final left = stock - queued;
    return left < 0 ? 0 : left;
  }

  /// What a product row says is left (before the cart).
  int _shownLeft(Map<String, dynamic> p) {
    final variants = stockVariants(p);
    if (variants.isEmpty) return _available(p, null, cart: false);
    return variants.fold(0, (s, v) => s + _available(p, v.name, cart: false));
  }

  // ── cart actions ────────────────────────────────────────────────────────

  void _announce(String message, {bool assertive = false}) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
      assertiveness: assertive ? Assertiveness.assertive : Assertiveness.polite,
    );
  }

  Future<void> _tapProduct(Map<String, dynamic> p) async {
    if (_blocked) return;
    final name = p['name']?.toString() ?? '';
    String? variant;
    if (needsVariant(p)) {
      variant = await _pickVariant(p);
      if (variant == null || !mounted) return;
    }
    _add(p, variant, name);
  }

  /// Adds one; false at the stock limit (a snack says so). A scan gives its
  /// own feedback ([fromScan]).
  bool _add(
    Map<String, dynamic> p,
    String? variant,
    String name, {
    bool fromScan = false,
  }) {
    final available = _stockFor(p, variant);
    var added = false;
    _cart.update(
      (c) => added = c.addOne(
        productId: p['id'].toString(),
        variant: variant,
        name: name,
        priceTzs: walkInPrice(p),
        available: available,
      ),
    );
    if (!added) {
      // At the stock limit: say so instead of doing nothing.
      final text = fillIn(context.tr('vendor.pos.onlyLeft'), {'n': available});
      FFSnack.info(context, text);
      _announce(text);
      return false;
    }
    _clearFlag();
    if (!fromScan) {
      HapticFeedback.selectionClick();
      _announce(fillIn(context.tr('vendor.pos.added'), {'name': name}));
    }
    return true;
  }

  void _clearFlag() {
    if (_flagged != null) {
      setState(() {
        _flagged = null;
        _flagText = null;
      });
    }
  }

  // ── S8: scanning (spec §5.1) ───────────────────────────────────────────

  /// Scanning is offered: barcodes and walk-in sales both on (§0.2).
  bool get _barcodesOn => _tools.barcodes && _tools.walkInSales;

  void _setAll(List<Map<String, dynamic>> rows) {
    _allProducts = rows;
    _codeIndex = ProductCodeIndex(rows);
  }

  /// Barcodes went off on the server (lookup 404, or a save that left the
  /// codes out): the panel closes and the tools are asked again, so the
  /// scan icon goes.
  void _barcodesWentOff() {
    setState(() {
      _scanOpen = false;
      _scanNotice = null;
    });
    VendorToolsOptions.of(context, refresh: true).then((tools) {
      if (mounted) setState(() => _tools = tools);
    });
  }

  void _openScan() {
    if (_blocked || _scan == null) return;
    setState(() {
      _scanOpen = true;
      _scanNotice = null;
    });
  }

  void _closeScan() {
    if (!_scanOpen) return;
    setState(() {
      _scanOpen = false;
      _scanNotice = null;
    });
    // Focus goes back to the scan icon that opened it (§9).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanButtonFocus.requestFocus();
    });
  }

  void _showScanNotice(ScanNotice notice) {
    setState(() {
      _scanNotice = notice;
      _undoable = false;
    });
    scanFeedback(context, notice.kind, notice.message);
  }

  /// The panel's (and Enter's) handler: true when something was added.
  Future<bool> _onScanCode(String raw, {required bool typed}) async {
    final scan = _scan;
    if (scan == null || _blocked) return false;
    final outcome = await scan.handle(raw, typed: typed);
    if (outcome == null || !mounted) return false;
    if (outcome.kind == ScanOutcomeKind.featureOff) {
      FFSnack.info(context, context.tr('vendor.barcodes.unavailable'));
      _barcodesWentOff();
      return false;
    }
    final notice = noticeFor(context, outcome);
    if (notice != null) {
      _showScanNotice(notice);
      return false;
    }
    final match = await singleMatch(context, scan, outcome.matches);
    if (match == null || !mounted) return false;
    return _addScanned(match);
  }

  Future<bool> _addScanned(ScanMatch m) async {
    final t = context.tr;
    if (m.archived) {
      _showScanNotice(
        ScanNotice.warning(fillIn(t('vendor.scan.archived'), {'name': m.name})),
      );
      return false;
    }
    // A product only the lookup knows (added on another device): load the
    // list so its variants are complete before choosing one (online only).
    if (_product(m.productId) == null && m.product == null && !_offline) {
      await _loadProducts();
      if (!mounted) return false;
    }
    final p = _product(m.productId) ?? m.asProduct;
    final name = p['name']?.toString() ?? m.name;
    var variant = m.variant;
    if (variant == null && needsVariant(p)) {
      if (_shownLeft(p) <= 0) {
        _showScanNotice(
          ScanNotice.warning(
            fillIn(t('vendor.scan.outOfStock'), {'name': name}),
          ),
        );
        return false;
      }
      // Whole-product code on a product with variants: which one (§4.4).
      HapticFeedback.selectionClick();
      final scan = _scan!..hold();
      try {
        variant = await _pickVariant(p);
      } finally {
        scan.release();
      }
      if (variant == null || !mounted) return false;
    }
    final label = variant == null ? name : '$name ($variant)';
    if (_available(p, variant) <= 0) {
      _showScanNotice(
        ScanNotice.warning(
          fillIn(t('vendor.scan.outOfStock'), {'name': label}),
        ),
      );
      return false;
    }
    if (!_add(p, variant, name, fromScan: true)) return false;
    final id = p['id'].toString();
    _lastScanned = (productId: id, variant: variant);
    _scanAddedNotice(label, undoable: true);
    scanFeedback(context, ScanNoticeKind.added, _scanNotice!.message);
    return true;
  }

  void _scanAddedNotice(String label, {required bool undoable}) {
    final last = _lastScanned;
    if (last == null) return;
    final qty = _cart.cart.qtyOf(last.productId, last.variant);
    setState(() {
      _undoable = undoable && qty > 0;
      _scanNotice = ScanNotice.added(
        name: label,
        qty: qty,
        productId: last.productId,
        variant: last.variant,
        message: fillIn(context.tr('vendor.scan.added'), {
          'name': label,
          'qty': qty,
        }),
      );
    });
  }

  /// −/+ on the result row, and Undo (the last scan's +1).
  void _stepScanned(int delta, {bool undo = false}) {
    final last = _lastScanned;
    final notice = _scanNotice;
    if (last == null || notice == null) return;
    final line = _cart.cart.lineOf(last.productId, last.variant);
    if (line == null) {
      if (delta > 0) {
        final p = _product(last.productId);
        if (p == null) return;
        _add(p, last.variant, p['name']?.toString() ?? '');
      }
    } else {
      _step(line, delta);
    }
    _scanAddedNotice(notice.name ?? '', undoable: !undo && _undoable);
  }

  Future<void> _addCodeHere(String code) async {
    final scan = _scan;
    if (scan == null) return;
    scan.hold();
    AddCodeResult? res;
    try {
      res = await addCodeToProduct(context, code: code, products: _allProducts);
    } finally {
      scan.release();
    }
    if (res == null || !mounted) return;
    if (res.barcodesOff) {
      _barcodesWentOff();
      return;
    }
    if (res.inUseBy != null) {
      // Someone else just added it: look the code up again.
      scan.resetDebounce();
      await _onScanCode(code, typed: true);
      return;
    }
    final saved = Map<String, dynamic>.from(res.product!);
    setState(() {
      final rows = [
        for (final p in _allProducts)
          p['id']?.toString() == saved['id']?.toString() ? saved : p,
      ];
      _setAll(rows);
      _products = _sellable(rows);
      _scanNotice = null;
    });
    await _addScanned(ScanMatch.fromProduct(saved, variant: res.variant));
  }

  Future<void> _newProductWithCode(String code) async {
    final scan = _scan;
    scan?.hold();
    try {
      await openNewProductWithCode(context, code: code, tools: _tools);
    } finally {
      scan?.release();
    }
    if (!mounted) return;
    setState(() => _scanNotice = null);
    await _loadProducts();
  }

  Widget _scanResult() {
    final notice = _scanNotice;
    return ScanResultRow(
      notice: notice,
      // UAT L-3: the 429 message clears when the wait is over.
      onWaitOver: () {
        if (mounted && identical(_scanNotice, notice)) {
          setState(() => _scanNotice = null);
        }
      },
      onMore: () => _stepScanned(1),
      onLess: () => _stepScanned(-1),
      onUndo: _undoable ? () => _stepScanned(-1, undo: true) : null,
      onRetry: notice?.code == null
          ? null
          : () => _onScanCode(notice!.code!, typed: true),
      actions: notice?.kind == ScanNoticeKind.unknown
          ? UnknownCodeActions(
              code: notice!.code!,
              canManage: canVendor(context, 'products'),
              offline: notice.offline,
              onAddToProduct: () => _addCodeHere(notice.code!),
              onCreateProduct: () => _newProductWithCode(notice.code!),
              onSearchByName: () {
                setState(() {
                  _scanOpen = false;
                  _scanNotice = null;
                });
                _search.clear();
                _searchFocus.requestFocus();
              },
              onScanAgain: () {
                _scan?.resetDebounce();
                setState(() => _scanNotice = null);
              },
            )
          : null,
    );
  }

  Widget _scanPanel() => Padding(
    padding: const EdgeInsets.fromLTRB(
      FFTokens.spacingLg,
      0,
      FFTokens.spacingLg,
      FFTokens.spacingSm,
    ),
    child: Align(
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: VendorScanPanel(
          key: const Key('pos-scan-panel'),
          controller: _scan!,
          memoryScope: vendorScanScope(context),
          onCode: _onScanCode,
          onClose: _closeScan,
          result: _scanResult(),
        ),
      ),
    ),
  );

  Future<String?> _pickVariant(Map<String, dynamic> p) => showFFSheet<String>(
    context,
    title: p['name']?.toString() ?? context.tr('vendor.pos.pickVariant'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('vendor.pos.pickVariant')),
        const SizedBox(height: FFTokens.spacingSm),
        for (final v in stockVariants(p))
          Builder(
            builder: (sheet) {
              final left = _available(p, v.name);
              return ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: ListTile(
                  key: Key('pos-variant-${v.name}'),
                  enabled: left > 0,
                  title: Text(v.name),
                  trailing: left > 0
                      ? Text(fillIn(context.tr('vendor.pos.left'), {'n': left}))
                      : FFBadge(
                          label: context.tr('vendor.pos.outOfStock'),
                          tone: FFBadgeTone.gray,
                        ),
                  onTap: left > 0
                      ? () => Navigator.of(sheet).pop(v.name)
                      : null,
                ),
              );
            },
          ),
      ],
    ),
  );

  void _step(PosLine line, int delta) {
    final p = _product(line.productId);
    if (delta > 0 && p != null && _available(p, line.variant) <= 0) return;
    _cart.update((c) => c.setQty(line, line.qty + delta));
    _clearFlag();
  }

  Future<void> _editLine(PosLine line) async {
    final p = _product(line.productId);
    final cap = p == null
        ? maxQtyPerLine
        : _available(p, line.variant) + line.qty;
    final result = await showFFSheet<Object>(
      context,
      title: fillIn(context.tr('vendor.pos.editLine'), {'name': line.name}),
      child: _LineEditor(line: line, maxQty: cap),
    );
    if (!mounted || result == null) return;
    if (result == 'remove') {
      _cart.update((c) => c.remove(line));
    } else if (result is ({int qty, int? price, int discount})) {
      _cart.update((c) {
        line.qty = result.qty;
        line.unitPriceTzs = result.price == line.listPriceTzs
            ? null
            : result.price;
        line.discountTzs = result.discount;
        c.changed();
      });
    }
    _clearFlag();
  }

  Future<void> _saleDiscount() async {
    final totals = _cart.cart.totals;
    final result = await showFFSheet<int>(
      context,
      title: context.tr('vendor.pos.saleDiscount'),
      child: _DiscountEditor(
        baseTzs: totals.afterLinesTzs,
        currentTzs: _cart.cart.saleDiscountTzs,
      ),
    );
    if (result == null || !mounted) return;
    _cart.update((c) {
      c.saleDiscountTzs = result;
      c.changed();
    });
  }

  Future<void> _clearSale() async {
    final ok = await showFFConfirmDialog(
      context,
      message: context.tr('vendor.pos.clearConfirm'),
      confirmLabel: context.tr('vendor.pos.clearSale'),
      destructive: true,
      confirmKey: const Key('pos-clear-confirm'),
    );
    if (ok && mounted) {
      _cart.update((c) => c.clear());
      _clearFlag();
    }
  }

  // ── charge ──────────────────────────────────────────────────────────────

  Future<void> _charge() async {
    if (_cart.cart.isEmpty || _blocked) return;
    // The phone's cart sheet closes first; the payment sheet takes over.
    await showFFSheet<bool>(
      context,
      title: context.tr('vendor.pos.payTitle'),
      isDismissible: false,
      child: PaymentSheet(
        totalTzs: _cart.cart.totals.totalTzs,
        submit: _submit,
        payLater: _payLaterSetup(),
        referenceOptional: _tools.saleReferenceOptionalOn,
        customerDetails: _customerSetup(),
        onAction: (action) {
          if (action == 'recordToday') _recordToday();
        },
      ),
    );
  }

  Map<String, dynamic> _display() {
    final user = AppScope.of(context).auth.user;
    return {
      'business': ?_profile['businessName'],
      'contact': ?_profile['contactNumber'],
      'address': ?_profile['address'],
      'servedBy': ?(user?['displayName'] ?? user?['name']),
      'lines': [
        for (final l in _cart.cart.lines)
          {'name': l.name, 'listPriceTzs': l.listPriceTzs},
      ],
    };
  }

  /// Sends the sale. Network failure (no answer) → kept on the device.
  Future<PayAttempt> _submit(
    List<Map<String, dynamic>> payments, {
    bool queue = false,
    String? creditDueDate,
  }) async {
    final session = _session;
    if (session == null) return const PayAttempt.close();
    final api = AppScope.of(context).api;
    final display = _display();
    final credit = creditDueDate != null;
    // Online: no soldAt (the server's clock). Kept on the device: the same
    // clientRef with the time of the first Complete.
    final body = _cart.cart.requestBody(payments, creditDueDate: creditDueDate);
    final queuedBody = _cart.cart.requestBody(payments, queued: true);
    final sentOnline = !_cart.cart.keepSoldAt;
    // Persist the fixed key and time before sending: a retry after an app
    // kill reuses them.
    await session.saveDraft(_cart.cart);
    // S4 (Q-11): a pay-later sale is never kept on the device.
    if (queue && !credit) {
      return _queue(queuedBody, display, sentOnline: sentOnline);
    }

    try {
      final res = await api.vendorRecordSale(body);
      final sale = res['sale'];
      if (sale is! Map) {
        return credit
            ? const PayAttempt.stay('vendor.pos.credit.failed')
            : const PayAttempt.server();
      }
      await _finished(Map<String, dynamic>.from(sale));
      return const PayAttempt.close();
    } on ApiException catch (e) {
      if (!mounted) return const PayAttempt.close();
      if (credit && (e.status >= 500 || e.status == 429)) {
        // Nothing recorded; the cart stays; Complete tries the same key.
        return const PayAttempt.stay('vendor.pos.credit.failed');
      }
      return _refused(e);
    } catch (_) {
      // No answer. A pay-later sale is not queued (a debt must not exist
      // only on one phone): the seller tries again or takes full payment.
      if (credit) return const PayAttempt.stay('vendor.pos.credit.failed');
      return _queue(queuedBody, display, sentOnline: sentOnline, offline: true);
    }
  }

  /// "Record with today's date": an edited offline sale older than the
  /// server accepts loses its original time (kept in the note).
  void _recordToday() {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final when = eatDayOf(_cart.cart.soldAt);
    final originally = fillIn(context.tr('vendor.sync.originally'), {
      'date': when == null
          ? ''
          : formatDate(DateTime(when.year, when.month, when.day), locale: lang),
    });
    _cart.update((c) => c.recordToday(originally));
  }

  Future<PayAttempt> _queue(
    Map<String, dynamic> body,
    Map<String, dynamic> display, {
    bool sentOnline = false,
    bool offline = false,
  }) async {
    final session = _session!;
    final replaces = _cart.cart.replacesClientRef;
    await session.enqueue(
      QueuedSale(
        body: body,
        display: display,
        queuedAt: DateTime.now().toUtc().toIso8601String(),
        sentOnline: sentOnline,
      ),
    );
    if (replaces != null) await session.remove(replaces);
    _cart.update((c) => c.clear());
    await session.clearDraft();
    if (!mounted) return const PayAttempt.close();
    // No answer at all, or the seller chose "Save and sync later".
    FFSnack.info(
      context,
      context.tr(offline ? 'vendor.pos.savedOffline' : 'vendor.pos.savedLater'),
    );
    _goAfterSheet(queuedReceiptRoute(body['clientRef'].toString()));
    return const PayAttempt.close();
  }

  Future<void> _finished(Map<String, dynamic> sale) async {
    final session = _session!;
    final replaces = _cart.cart.replacesClientRef;
    if (replaces != null) await session.remove(replaces);
    _cart.update((c) => c.clear());
    await session.clearDraft();
    if (!mounted) return;
    FFSnack.success(
      context,
      fillIn(
        context.tr(
          sale['kind'] == 'credit'
              ? 'vendor.pos.credit.saved'
              : 'vendor.pos.saleSaved',
        ),
        {'number': sale['number']},
      ),
    );
    _goAfterSheet(saleReceiptRoute(sale['id'].toString()), extra: sale);
  }

  /// Navigates once the payment sheet has closed.
  void _goAfterSheet(String route, {Object? extra}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(route, extra: extra);
    });
  }

  PosLine? _lineFor(Map body) {
    final id = body['productId']?.toString();
    if (id == null) return null;
    final variant = body['variant']?.toString();
    for (final l in _cart.cart.lines) {
      if (l.productId == id && (variant == null || l.variant == variant)) {
        return l;
      }
    }
    return null;
  }

  PayAttempt _refused(ApiException e) {
    final body = e.body is Map ? Map<String, dynamic>.from(e.body) : {};
    final code = e.code;
    // 5xx and 429 rate_limited: nothing recorded yet; Try again (same
    // clientRef) or keep it on the device.
    if (e.status >= 500 || e.status == 429) return const PayAttempt.server();
    // S4: customer / pay-later refusals (some are 403 and 404: before the
    // general handling of those).
    final creditKey = creditErrorKey(code);
    if (creditKey != null) {
      if (code == 'customer_not_found' || code == 'customer_archived') {
        // Nothing recorded: the chip is cleared and the picker offered.
        _cart.update((c) => c.setCustomer(null));
      }
      return PayAttempt.stay(creditKey);
    }
    if (e.status == 404 &&
        code == 'feature_disabled' &&
        body['feature'] == 'customers') {
      // Customers went off: the sale can still be recorded without one.
      _cart.update((c) => c.setCustomer(null));
      return const PayAttempt.stay('vendor.pos.customer.gone');
    }
    if (e.status == 403) {
      final isStaff =
          AppScope.of(context).auth.user?['userType'] == 'vendor_staff';
      if (code == 'vendor_suspended') {
        // The paused notice says it (once); no extra snack.
        _session?.markSuspended();
      } else {
        if (isVendorStaffDisabled(e, vendorStaff: isStaff)) {
          setState(() => _notAllowed = true);
        }
        _afterClose(
          () => FFSnack.error(context, context.tr('vendor.pos.err.notAllowed')),
        );
      }
      return const PayAttempt.close();
    }
    if (e.status == 404 && code == 'feature_disabled') {
      _afterClose(
        () => FFSnack.error(context, context.tr('vendor.sync.featureOff')),
      );
      return const PayAttempt.close();
    }
    switch (code) {
      case 'payment_short':
        return PayAttempt.stay(
          'vendor.pos.short',
          values: {'amount': formatCurrency((body['shortTzs'] as num?) ?? 0)},
        );
      case 'reference_required':
        return PayAttempt.stay(
          'vendor.pos.referenceRequired',
          index: (body['index'] as num?)?.toInt(),
        );
      case 'invalid_payment':
        return PayAttempt.stay(
          saleErrorKey(code, reason: body['reason']?.toString()),
          index: (body['index'] as num?)?.toInt(),
        );
      case 'insufficient_stock':
        final line = _lineFor(body);
        final available = (body['available'] as num?)?.toInt();
        if (available != null) {
          _updateStock(
            body['productId']?.toString(),
            body['variant']?.toString(),
            available,
          );
        }
        _flag(
          line,
          line == null || available == null
              // Without the product or the count: no blank name, no "0".
              ? context.tr('vendor.sync.conflictStockGeneric')
              : fillIn(context.tr('vendor.pos.err.stock'), {
                  'available': available,
                  'name': line.name,
                }),
        );
        // Nothing was recorded: the next Complete is a new sale.
        _cart.update((c) => c.changed());
        return const PayAttempt.close();
      case 'discount_exceeds_price':
        _flag(
          _lineFor(body),
          fillIn(context.tr('vendor.pos.discountTooBig'), {
            'amount': formatCurrency((body['maxTzs'] as num?) ?? 0),
          }),
        );
        return const PayAttempt.close();
      case 'product_not_found' ||
          'product_unavailable' ||
          'variant_not_found' ||
          'variant_required' ||
          'invalid_price':
        final line = _lineFor(body);
        _flag(
          line,
          fillIn(context.tr('vendor.pos.err.unavailable'), {
            'name': line?.name ?? '',
          }),
        );
        return const PayAttempt.close();
      case 'sold_at_out_of_range':
        // Only an edited offline sale sends soldAt: too old → it can be
        // recorded with today's date; ahead of the server → the clock.
        if (soldAtTooOld(_cart.cart.soldAt, body)) {
          return const PayAttempt.stay(
            'vendor.pos.err.tooOld',
            action: 'recordToday',
          );
        }
        return const PayAttempt.stay('vendor.pos.err.clock');
      case 'client_ref_reused':
        // The key was used for another sale: a new one next time.
        _cart.update((c) => c.clientRef = null);
        return const PayAttempt.stay('vendor.saveFailed');
      default:
        return PayAttempt.stay(
          'vendor.sync.conflictOther',
          values: {'reason': apiErrorMessage(FFLocaleScope.of(context), e)},
        );
    }
  }

  void _afterClose(VoidCallback f) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) f();
      });

  void _updateStock(String? productId, String? variant, int available) {
    if (productId == null) return;
    setState(() {
      _products = [
        for (final p in _products)
          if (p['id']?.toString() != productId)
            p
          else if (variant == null)
            {
              ...p,
              'stock': available + (_session?.queuedQty(productId, null) ?? 0),
            }
          else
            {
              ...p,
              'variants': [
                for (final v in (p['variants'] as List? ?? []).whereType<Map>())
                  v['name'] == variant ? {...v, 'stock': available} : v,
              ],
            },
      ];
    });
  }

  void _flag(PosLine? line, String text) {
    setState(() {
      _flagged = line?.key;
      _flagText = text;
    });
    _focusFlagged = line != null;
    _afterClose(() {
      _announce(text, assertive: true);
      if (!_wide) _openCart();
    });
  }

  // ── layout ──────────────────────────────────────────────────────────────

  void _back() {
    if (_scanOpen) {
      _closeScan();
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(salesHomeRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    // S8: system back / Esc closes the scan panel first.
    return PopScope(
      canPop: !_scanOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeScan();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _back),
          title: Text(context.tr('vendor.pos.title')),
          actions: [
            ListenableBuilder(
              listenable: _cart,
              builder: (context, _) => PopupMenuButton<String>(
                key: const Key('pos-more'),
                tooltip: context.tr('vendor.pos.more'),
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  visualDensity: VisualDensity.standard,
                ),
                onSelected: (v) {
                  if (v == 'clear') _clearSale();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    key: const Key('pos-clear'),
                    value: 'clear',
                    enabled: !_cart.cart.isEmpty,
                    child: Text(context.tr('vendor.pos.clearSale')),
                  ),
                ],
              ),
            ),
          ],
        ),
        body: !_ready || session == null
            ? const Center(child: FFSpinner())
            : _body(session),
        bottomNavigationBar: !_ready || _wide ? null : _cartBar(),
      ),
    );
  }

  Widget _banners(SalesSession session) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FFTokens.spacingLg,
      FFTokens.spacingSm,
      FFTokens.spacingLg,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_notAllowed)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: FFAlert(
              key: const Key('pos-staff-disabled'),
              message: context.tr('error.reason.vendorStaffInactive'),
              tone: FFAlertTone.error,
            ),
          ),
        SalesSyncBanners(
          session: session,
          offline: _offline && _products.isNotEmpty
              ? fillIn(context.tr('vendor.pos.offlineBanner'), {
                  'time': eatDateTime(
                    _cachedAt,
                    locale: FFLocaleScope.of(context).locale.languageCode,
                  ),
                })
              : null,
        ),
      ],
    ),
  );

  Widget _body(SalesSession session) {
    final products = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FFTokens.spacingLg,
            FFTokens.spacingSm,
            FFTokens.spacingLg,
            FFTokens.spacingSm,
          ),
          child: FFTextField(
            key: const Key('pos-search'),
            controller: _search,
            focusNode: _searchFocus,
            label: context.tr('vendor.pos.search'),
            hint: context.tr('vendor.pos.searchHint'),
            prefixIcon: const Icon(Icons.search),
            autofocus: _wide,
            textInputAction: TextInputAction.search,
            onFieldSubmitted: (_) => _enterInSearch(),
            // Keep focus here for the next code (UAT L-1): no unfocus on Enter.
            onEditingComplete: () {},
            // S3 §2.1 reserved this slot for S8.
            suffixIcon: _barcodesOn
                ? IconButton(
                    key: const Key('pos-scan'),
                    focusNode: _scanButtonFocus,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      visualDensity: VisualDensity.standard,
                    ),
                    tooltip: context.tr('vendor.scan.open'),
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _blocked
                        ? null
                        : _scanOpen
                        ? _closeScan
                        : _openScan,
                  )
                : null,
          ),
        ),
        if (_barcodesOn && _scanOpen && _scan != null)
          _scanPanel()
        else if (_barcodesOn && _scanNotice != null)
          // Enter in search: the unknown-code message under the field.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FFTokens.spacingLg,
              0,
              FFTokens.spacingLg,
              FFTokens.spacingSm,
            ),
            child: _scanResult(),
          ),
        Expanded(child: _productList()),
      ],
    );
    if (!_wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _banners(session),
          Expanded(child: products),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _banners(session),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: products),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 400,
                child: ListenableBuilder(
                  listenable: Listenable.merge([_cart, ?_session]),
                  builder: (context, _) => SingleChildScrollView(
                    padding: const EdgeInsets.all(FFTokens.spacingLg),
                    child: _cartContents(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> get _matches {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _products;
    return [
      for (final p in _products)
        if ([
          p['name'],
          p['brand'],
          p['sku'],
        ].any((f) => (f?.toString().toLowerCase() ?? '').contains(q)))
          p,
    ];
  }

  /// Enter in search (web; also USB scanners): add the one match, or the
  /// exact SKU match. S8 (barcodes on): an exact code match wins first;
  /// with no local match, text that looks like a code is looked up.
  void _enterInSearch() {
    final raw = _search.text.trim();
    final q = raw.toLowerCase();
    if (q.isEmpty) return;
    if (_barcodesOn) {
      final code = _codeIndex.barcodeMatch(raw);
      if (code != null) {
        _search.clear();
        _searchFocus.requestFocus();
        _addScanned(code);
        return;
      }
    }
    final sku = _products
        .where((p) => (p['sku']?.toString().toLowerCase() ?? '') == q)
        .toList();
    final matches = sku.length == 1 ? sku : _matches;
    if (_barcodesOn && matches.isEmpty && looksLikeCode(raw)) {
      _search.clear();
      _searchFocus.requestFocus();
      _onScanCode(raw, typed: true);
      return;
    }
    if (matches.length != 1) return;
    final p = matches.single;
    if (_shownLeft(p) <= 0) return;
    _tapProduct(p).then((_) {
      if (!mounted) return;
      _search.clear();
      _searchFocus.requestFocus();
    });
  }

  Widget _productList() {
    if (_loading && _products.isEmpty) {
      return FFSkeletonList(
        count: 6,
        semanticLabel: context.tr('vendor.pos.loading'),
      );
    }
    switch (_problem) {
      case _LoadProblem.noAccess:
        return ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            FFErrorState(
              key: const Key('pos-no-products-access'),
              message: context.tr('vendor.pos.noProductsAccess'),
              onRetry: _loadProducts,
            ),
          ],
        );
      case _LoadProblem.failed:
        return ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            FFErrorState(
              key: const Key('pos-load-failed'),
              message: context.tr('vendor.pos.loadFailed'),
              onRetry: _loadProducts,
            ),
          ],
        );
      case _LoadProblem.noCache:
        return ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            FFErrorState(
              key: const Key('pos-no-cache'),
              message: context.tr('vendor.pos.noCache'),
              onRetry: _loadProducts,
            ),
          ],
        );
      case _LoadProblem.none:
        break;
    }
    if (_products.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          FFEmptyState(
            key: const Key('pos-no-products'),
            title: context.tr('vendor.pos.noProducts'),
            action: canVendor(context, 'products')
                ? FFButton(
                    label: context.tr('vendor.pos.goToProducts'),
                    variant: FFButtonVariant.secondary,
                    onPressed: () => context.go('/vendor/home?open=products'),
                  )
                : null,
          ),
        ],
      );
    }
    final matches = _matches;
    if (matches.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          Text(
            fillIn(context.tr('vendor.pos.noResults'), {
              'q': _search.text.trim(),
            }),
            key: const Key('pos-no-results'),
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([_cart, ?_session]),
      builder: (context, _) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          0,
          FFTokens.spacingLg,
          FFTokens.spacingLg,
        ),
        itemCount: matches.length,
        itemBuilder: (context, i) => _productRow(matches[i]),
      ),
    );
  }

  Widget _productRow(Map<String, dynamic> p) {
    final theme = Theme.of(context);
    final id = p['id']?.toString() ?? '';
    final name = p['name']?.toString() ?? '';
    final left = _shownLeft(p);
    final out = left <= 0;
    final image = (p['images'] as List?)?.whereType<String>().firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: FFCard(
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          // One node: what it is, its price and stock, and whether it can
          // be added (out of stock reads as disabled).
          child: Semantics(
            button: true,
            enabled: !out && !_blocked,
            label: [
              fillIn(context.tr('vendor.pos.add'), {'name': name}),
              formatCurrency(walkInPrice(p)),
              out
                  ? context.tr('vendor.pos.outOfStock')
                  : fillIn(context.tr('vendor.pos.left'), {'n': left}),
            ].join(', '),
            excludeSemantics: true,
            onTap: out || _blocked ? null : () => _tapProduct(p),
            child: ListTile(
              key: Key('pos-product-$id'),
              enabled: !out && !_blocked,
              onTap: out || _blocked ? null : () => _tapProduct(p),
              leading: ExcludeSemantics(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: image == null
                      ? const Icon(Icons.shopping_bag_outlined)
                      : FFRemoteImage(
                          src: image,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          fallback: const Icon(Icons.shopping_bag_outlined),
                        ),
                ),
              ),
              title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Wrap(
                spacing: FFTokens.spacingSm,
                runSpacing: FFTokens.spacingXs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    formatCurrency(walkInPrice(p)),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (out)
                    FFBadge(
                      key: Key('pos-out-$id'),
                      label: context.tr('vendor.pos.outOfStock'),
                      tone: FFBadgeTone.gray,
                    )
                  else
                    Text(fillIn(context.tr('vendor.pos.left'), {'n': left})),
                ],
              ),
              trailing: const Icon(Icons.add_circle_outline),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cartBar() => ListenableBuilder(
    listenable: Listenable.merge([_cart, ?_session]),
    builder: (context, _) {
      final cart = _cart.cart;
      final total = cart.totals.totalTzs;
      final empty = cart.isEmpty;
      final count = fillIn(
        context.tr(pluralKey('vendor.pos.items', cart.itemCount)),
        {'n': cart.itemCount},
      );
      final charge = FFButton(
        key: const Key('pos-charge'),
        label: fillIn(context.tr('vendor.pos.charge'), {
          'amount': formatCurrency(total),
        }),
        visualDensity: VisualDensity.standard,
        onPressed: empty || _blocked ? null : _charge,
      );
      return SafeArea(
        child: Material(
          elevation: 3,
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Semantics(
            label: fillIn(
              context.tr(pluralKey('vendor.pos.cartBarLabel', cart.itemCount)),
              {'n': cart.itemCount, 'amount': formatCurrency(total)},
            ),
            button: !empty,
            child: InkWell(
              key: const Key('pos-cart-bar'),
              onTap: empty ? null : _openCart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FFTokens.spacingLg,
                    vertical: FFTokens.spacingSm,
                  ),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      // Large text or long Swahili: the count goes above a
                      // full-width button instead of squeezing it.
                      final stack =
                          MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                          c.maxWidth < 340;
                      final label = Text(
                        empty ? context.tr('vendor.pos.cartEmpty') : count,
                        style: Theme.of(context).textTheme.titleSmall,
                      );
                      if (stack) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ExcludeSemantics(child: label),
                            const SizedBox(height: FFTokens.spacingXs),
                            charge,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: ExcludeSemantics(child: label)),
                          const SizedBox(width: FFTokens.spacingSm),
                          Flexible(child: charge),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Future<void> _openCart() async {
    final charge = await showFFSheet<bool>(
      context,
      title: context.tr('vendor.pos.cartTitle'),
      child: ListenableBuilder(
        listenable: Listenable.merge([_cart, ?_session]),
        builder: (sheet, _) =>
            _cartContents(onCharge: () => Navigator.of(sheet).pop(true)),
      ),
    );
    if (charge == true && mounted) await _charge();
  }

  Widget _cartContents({VoidCallback? onCharge}) {
    final theme = Theme.of(context);
    final cart = _cart.cart;
    final totals = cart.totals;
    if (cart.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingLg),
        child: Text(
          context.tr('vendor.pos.cartEmpty'),
          key: const Key('pos-cart-empty'),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in cart.lines) _cartLine(line),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FFButton(
            key: const Key('pos-sale-discount'),
            label: context.tr(
              cart.saleDiscountTzs > 0
                  ? 'vendor.pos.saleDiscount'
                  : 'vendor.pos.addDiscount',
            ),
            icon: Icons.sell_outlined,
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: _saleDiscount,
          ),
        ),
        const Divider(),
        if (_customersOn) ...[
          _customerChip(),
          const SizedBox(height: FFTokens.spacingXs),
        ],
        MoneyRow(
          context.tr('vendor.pos.subtotal'),
          formatCurrency(totals.subtotalTzs),
        ),
        if (totals.discountsTzs > 0)
          MoneyRow(
            context.tr('vendor.pos.discounts'),
            '−${formatCurrency(totals.discountsTzs)}',
          ),
        MoneyRow(
          context.tr('vendor.pos.total'),
          formatCurrency(totals.totalTzs),
          strong: true,
          key: const Key('pos-cart-total'),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        _NoteField(
          note: cart.note,
          onChanged: (v) => _cart.update((c) {
            c.note = v;
            c.changed();
          }),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFButton(
          key: const Key('pos-cart-charge'),
          label: fillIn(context.tr('vendor.pos.charge'), {
            'amount': formatCurrency(totals.totalTzs),
          }),
          fullWidth: true,
          maxLines: 2,
          visualDensity: VisualDensity.standard,
          onPressed: _blocked ? null : (onCharge ?? _charge),
        ),
        // A refusal about no particular line (or one already removed).
        if (_flagText != null &&
            cart.lines.every((l) => l.key != _flagged)) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFAlert(message: _flagText!, tone: FFAlertTone.error),
        ],
        Text(
          context.tr('vendor.pos.discountAudited'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _cartLine(PosLine line) {
    final theme = Theme.of(context);
    final p = _product(line.productId);
    // Checked against the latest product list every build, so a kept cart
    // reopened after a reload shows today's stock (S3 UAT).
    final stock = p == null ? null : _stockFor(p, line.variant);
    final inCart = _cart.cart.qtyOf(line.productId, line.variant);
    final canAdd =
        line.qty < maxQtyPerLine && (stock == null || inCart < stock);
    final atCap = stock != null && inCart >= stock;
    // A kept line whose product is gone from a freshly loaded list.
    final gone = p == null && _fresh;
    final flagged = _flagged == line.key;
    final focus = _lineFocus.putIfAbsent(line.key, FocusNode.new);
    if (flagged && _focusFlagged) {
      _focusFlagged = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (focus.context != null) focus.requestFocus();
      });
    }
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final stockLeft = stock;
    return Padding(
      key: Key('pos-line-${line.productId}-${line.variant ?? ''}'),
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: Container(
        decoration: flagged
            ? BoxDecoration(
                border: Border.all(color: warningText(context), width: 2),
                borderRadius: BorderRadius.circular(FFTokens.radiusMd),
              )
            : null,
        padding: flagged ? const EdgeInsets.all(FFTokens.spacingXs) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _editLine(line),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(line.name, style: theme.textTheme.titleSmall),
                          if (line.variant != null)
                            Text(
                              fillIn(context.tr('vendor.orders.variant'), {
                                'name': line.variant,
                              }),
                              style: muted,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: Key('pos-dec-${line.key}'),
                  focusNode: focus,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    visualDensity: VisualDensity.standard,
                  ),
                  tooltip: fillIn(context.tr('vendor.pos.decrease'), {
                    'name': line.name,
                  }),
                  icon: const Icon(Icons.remove),
                  onPressed: () => _step(line, -1),
                ),
                // Read once: the number, not the number and its value.
                Semantics(
                  label: '${line.qty}',
                  excludeSemantics: true,
                  child: Text(
                    '${line.qty}',
                    key: Key('pos-qty-${line.key}'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: Key('pos-inc-${line.key}'),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    visualDensity: VisualDensity.standard,
                  ),
                  tooltip: fillIn(context.tr('vendor.pos.increase'), {
                    'name': line.name,
                  }),
                  icon: const Icon(Icons.add),
                  onPressed: canAdd ? () => _step(line, 1) : null,
                ),
              ],
            ),
            MoneyRow(
              line.qty > 1 || line.priceChanged
                  ? '@ ${formatMoney(line.priceEach)}'
                  : '',
              formatCurrency(line.lineTotalTzs),
            ),
            if (line.priceChanged)
              Text(
                fillIn(context.tr('vendor.pos.priceChanged'), {
                  'amount': formatCurrency(line.listPriceTzs),
                }),
                style: muted,
              ),
            if (line.discountTzs > 0)
              Text(
                '${context.tr('vendor.pos.lineDiscountShort')} −${formatMoney(line.discountTzs)}',
                style: muted,
              ),
            // After a refusal the server's count replaces the old hint.
            if (gone && !flagged)
              Text(
                fillIn(context.tr('vendor.pos.err.unavailable'), {
                  'name': line.name,
                }),
                key: Key('pos-gone-${line.key}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: warningText(context),
                ),
              ),
            if (atCap && stockLeft != null && !flagged)
              Text(
                fillIn(context.tr('vendor.pos.onlyLeft'), {'n': stockLeft}),
                key: Key('pos-only-left-${line.key}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: warningText(context),
                ),
              ),
            if (flagged && _flagText != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _flagText!,
                  key: const Key('pos-line-error'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (flagged)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FFButton(
                  key: const Key('pos-line-remove'),
                  label: context.tr('vendor.pos.removeItem'),
                  variant: FFButtonVariant.ghost,
                  size: FFButtonSize.sm,
                  semanticLabel: fillIn(context.tr('vendor.pos.removeLine'), {
                    'name': line.name,
                  }),
                  onPressed: () {
                    _cart.update((c) => c.remove(line));
                    _clearFlag();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoteField extends StatefulWidget {
  const _NoteField({required this.note, required this.onChanged});
  final String note;
  final ValueChanged<String> onChanged;

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  late final _controller = TextEditingController(text: widget.note);
  late bool _open = widget.note.isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: FFButton(
          key: const Key('pos-add-note'),
          label: context.tr('vendor.pos.addNote'),
          icon: Icons.note_add_outlined,
          variant: FFButtonVariant.ghost,
          visualDensity: VisualDensity.standard,
          onPressed: () => setState(() => _open = true),
        ),
      );
    }
    return FFTextField(
      key: const Key('pos-note'),
      controller: _controller,
      label: context.tr('vendor.pos.note'),
      maxLength: maxSaleNote,
      maxLines: 3,
      minLines: 1,
      onChanged: widget.onChanged,
    );
  }
}

/// TSh | % and the amount; % turns into whole TSh, rounded down.
class _DiscountField extends StatelessWidget {
  const _DiscountField({
    required this.mode,
    required this.controller,
    required this.onMode,
    required this.onChanged,
    this.errorText,
    this.fieldKey,
  });

  final String mode;
  final TextEditingController controller;
  final ValueChanged<String> onMode;
  final VoidCallback onChanged;
  final String? errorText;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FFSegmented(
        key: const Key('pos-discount-mode'),
        value: mode,
        options: [
          ('tzs', context.tr('vendor.pos.discountTzs')),
          ('pct', context.tr('vendor.pos.discountPct')),
        ],
        onChanged: onMode,
      ),
      const SizedBox(height: FFTokens.spacingSm),
      FFTextField(
        key: fieldKey,
        controller: controller,
        label: context.tr(
          mode == 'pct'
              ? 'vendor.pos.discountPercent'
              : 'vendor.pos.discountAmount',
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(mode == 'pct' ? 3 : 9),
        ],
        errorText: errorText,
        onChanged: (_) => onChanged(),
      ),
    ],
  );
}

int _discountValue(String mode, String text, int base) {
  final n = int.tryParse(text.trim()) ?? 0;
  return mode == 'pct' ? percentOf(base, n) : n;
}

class _LineEditor extends StatefulWidget {
  const _LineEditor({required this.line, required this.maxQty});
  final PosLine line;
  final int maxQty;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late final _qty = TextEditingController(text: '${widget.line.qty}');
  late final _price = TextEditingController(text: '${widget.line.priceEach}');
  late final _discount = TextEditingController(
    text: widget.line.discountTzs > 0 ? '${widget.line.discountTzs}' : '',
  );
  String _mode = 'tzs';

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    _discount.dispose();
    super.dispose();
  }

  int get _q => int.tryParse(_qty.text.trim()) ?? 0;
  int get _p => int.tryParse(_price.text.trim()) ?? 0;
  int get _gross => _q * _p;
  int get _d => _discountValue(_mode, _discount.text, _gross);

  @override
  Widget build(BuildContext context) {
    final cap = widget.maxQty < maxQtyPerLine ? widget.maxQty : maxQtyPerLine;
    final qtyOk = _q >= 1 && _q <= cap;
    final priceOk = _p >= 1;
    final discountOk = _d <= _gross;
    final valid = qtyOk && priceOk && discountOk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('pos-edit-dec'),
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                visualDensity: VisualDensity.standard,
              ),
              tooltip: fillIn(context.tr('vendor.pos.decrease'), {
                'name': widget.line.name,
              }),
              icon: const Icon(Icons.remove),
              onPressed: _q > 1
                  ? () => setState(() => _qty.text = '${_q - 1}')
                  : null,
            ),
            Expanded(
              child: FFTextField(
                key: const Key('pos-edit-qty'),
                controller: _qty,
                label: context.tr('vendor.pos.qty'),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                errorText: _q > cap
                    ? fillIn(context.tr('vendor.pos.onlyLeft'), {'n': cap})
                    : null,
                onChanged: (_) => setState(() {}),
              ),
            ),
            IconButton(
              key: const Key('pos-edit-inc'),
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                visualDensity: VisualDensity.standard,
              ),
              tooltip: fillIn(context.tr('vendor.pos.increase'), {
                'name': widget.line.name,
              }),
              icon: const Icon(Icons.add),
              onPressed: _q < cap
                  ? () => setState(() => _qty.text = '${_q + 1}')
                  : null,
            ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFTextField(
          key: const Key('pos-edit-price'),
          controller: _price,
          label: context.tr('vendor.pos.priceEach'),
          helperText: fillIn(context.tr('vendor.pos.listPrice'), {
            'amount': formatCurrency(widget.line.listPriceTzs),
          }),
          errorText: priceOk ? null : context.tr('vendor.pos.priceZero'),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        Text(
          context.tr('vendor.pos.lineDiscount'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: FFTokens.spacingXs),
        _DiscountField(
          mode: _mode,
          controller: _discount,
          fieldKey: const Key('pos-edit-discount'),
          onMode: (m) => setState(() {
            _mode = m;
            _discount.clear();
          }),
          onChanged: () => setState(() {}),
          errorText: discountOk
              ? null
              : fillIn(context.tr('vendor.pos.discountTooBig'), {
                  'amount': formatCurrency(_gross),
                }),
        ),
        if (_d > 0 && _mode == 'pct')
          Text('−${formatCurrency(_d)}', key: const Key('pos-edit-pct-value')),
        const SizedBox(height: FFTokens.spacingSm),
        MoneyRow(
          context.tr('vendor.pos.total'),
          formatCurrency(_gross - (discountOk ? _d : 0)),
          strong: true,
        ),
        Text(
          context.tr('vendor.pos.discountAudited'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        FFButton(
          key: const Key('pos-edit-save'),
          label: context.tr('vendor.pos.save'),
          fullWidth: true,
          visualDensity: VisualDensity.standard,
          onPressed: valid
              ? () => Navigator.of(
                  context,
                ).pop((qty: _q, price: _p, discount: _d))
              : null,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: FFTokens.spacingSm,
          children: [
            FFButton(
              key: const Key('pos-edit-remove'),
              label: context.tr('vendor.pos.removeItem'),
              variant: FFButtonVariant.destructive,
              visualDensity: VisualDensity.standard,
              semanticLabel: fillIn(context.tr('vendor.pos.removeLine'), {
                'name': widget.line.name,
              }),
              onPressed: () => Navigator.of(context).pop('remove'),
            ),
            FFButton(
              label: context.tr('common.cancel'),
              variant: FFButtonVariant.ghost,
              visualDensity: VisualDensity.standard,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}

class _DiscountEditor extends StatefulWidget {
  const _DiscountEditor({required this.baseTzs, required this.currentTzs});
  final int baseTzs;
  final int currentTzs;

  @override
  State<_DiscountEditor> createState() => _DiscountEditorState();
}

class _DiscountEditorState extends State<_DiscountEditor> {
  late final _amount = TextEditingController(
    text: widget.currentTzs > 0 ? '${widget.currentTzs}' : '',
  );
  String _mode = 'tzs';

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _discountValue(_mode, _amount.text, widget.baseTzs);
    final ok = value <= widget.baseTzs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DiscountField(
          mode: _mode,
          controller: _amount,
          fieldKey: const Key('pos-sale-discount-amount'),
          onMode: (m) => setState(() {
            _mode = m;
            _amount.clear();
          }),
          onChanged: () => setState(() {}),
          errorText: ok
              ? null
              : fillIn(context.tr('vendor.pos.discountTooBig'), {
                  'amount': formatCurrency(widget.baseTzs),
                }),
        ),
        if (value > 0 && _mode == 'pct') Text('−${formatCurrency(value)}'),
        const SizedBox(height: FFTokens.spacingSm),
        Text(
          context.tr('vendor.pos.discountAudited'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        FFButton(
          key: const Key('pos-sale-discount-save'),
          label: context.tr('vendor.pos.save'),
          fullWidth: true,
          visualDensity: VisualDensity.standard,
          onPressed: ok ? () => Navigator.of(context).pop(value) : null,
        ),
        if (widget.currentTzs > 0) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFButton(
            key: const Key('pos-sale-discount-remove'),
            label: context.tr('vendor.pos.removeDiscount'),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: () => Navigator.of(context).pop(0),
          ),
        ],
      ],
    );
  }
}
