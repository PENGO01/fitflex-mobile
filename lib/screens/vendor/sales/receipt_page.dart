// Vendor tools · S3: the receipt after a sale (spec §4), for a recorded sale
// or one still waiting on this device. Shared as plain text; not a TRA
// fiscal receipt. Done and system back never return to the completed cart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../documents/document_entry.dart';
import '../stock/stock_options.dart';
import 'offline_sale_queue.dart';
import 'receipt_data.dart';
import 'receipt_files.dart';
import 'sales_widgets.dart';

/// Shares [text] through the system share sheet. Replaceable in tests.
typedef ShareReceipt = Future<void> Function(String text, String subject);

ShareReceipt shareReceipt = (text, subject) async {
  await SharePlus.instance.share(ShareParams(text: text, subject: subject));
};

class SaleReceiptPage extends StatefulWidget {
  const SaleReceiptPage({super.key, this.saleId, this.clientRef, this.sale});

  final String? saleId;

  /// A queued sale (no number yet).
  final String? clientRef;

  /// The sale just recorded (from the POS), so nothing has to load.
  final Map<String, dynamic>? sale;

  @override
  State<SaleReceiptPage> createState() => _SaleReceiptPageState();
}

class _SaleReceiptPageState extends State<SaleReceiptPage> {
  SalesSession? _session;
  Map<String, dynamic>? _sale;
  Map<String, dynamic> _profile = const {};
  bool _loading = true;
  bool _notFound = false;
  bool _failed = false;
  String? _lang;
  final _heading = FocusNode();
  StreamSubscription<String>? _synced;
  VendorTools _tools = VendorTools.off;
  ({String? tin, String? vrn}) _taxIds = (tin: null, vrn: null);
  String? _taxIdsFor;

  @override
  void initState() {
    super.initState();
    _sale = widget.sale;
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _synced?.cancel();
    _session?.removeListener(_onSession);
    _session?.detach();
    _heading.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final tools = await enterSalesRoute(context, allowQueued: true);
    if (tools == null || !mounted) return;
    setState(() => _tools = tools);
    final session = SalesSession.of(context);
    _session = session?..attach();
    session?.addListener(_onSession);
    _synced = session?.syncedNumbers.listen((number) {
      if (!mounted) return;
      FFSnack.success(
        context,
        fillIn(context.tr('vendor.sync.synced'), {'number': number}),
      );
    });
    unawaited(_loadProfile());
    if (_sale == null && widget.saleId != null) {
      await _load();
    } else {
      setState(() => _loading = false);
    }
    if (mounted) _heading.requestFocus();
  }

  void _onSession() {
    if (!mounted) return;
    final ref = widget.clientRef;
    if (ref != null && _sale == null) {
      final sale = _session?.synced[ref];
      if (sale != null) setState(() => _sale = sale);
    }
    setState(() {});
  }

  /// The receipt header: the server's profile, else the one this device
  /// kept (offline, or staff who may not read the profile).
  Future<void> _loadProfile() async {
    final api = AppScope.of(context).api;
    final session = SalesSession.of(context);
    try {
      final p = await api.vendorProfile();
      await session?.saveBusiness(p);
      if (mounted) setState(() => _profile = p);
    } catch (_) {
      final kept = await session?.loadBusiness() ?? const {};
      if (mounted && kept.isNotEmpty) setState(() => _profile = kept);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final res = await AppScope.of(context).api.vendorSale(widget.saleId!);
      if (!mounted) return;
      setState(() {
        _sale = res['sale'] is Map
            ? Map<String, dynamic>.from(res['sale'] as Map)
            : null;
        _notFound = _sale == null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notFound = e.status == 404 || e.status == 403;
        _failed = !_notFound;
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

  ReceiptData? get _data {
    final sale = _sale;
    if (sale != null) {
      return ReceiptData.fromSale(
        sale,
        profile: _profile,
        documents: _tools.documents,
        vat: _tools.vat,
      );
    }
    final ref = widget.clientRef;
    final queued = ref == null ? null : _session?.byRef(ref);
    if (queued != null) {
      // A sale queued before the header was known gets the kept one.
      return ReceiptData.fromQueued(queued.body, {
        'business': ?_profile['businessName'],
        'contact': ?_profile['contactNumber'],
        'address': ?_profile['address'],
        ...queued.display,
      });
    }
    return null;
  }

  void _newSale() => context.go(posRoute);
  void _done() => context.go(salesHomeRoute);

  /// S5: the seller's TIN/VRN when VAT applied (asked once per sale).
  void _loadTaxIds(ReceiptData data) {
    if (data.id == null || _taxIdsFor == data.id || !data.hasVat) return;
    _taxIdsFor = data.id;
    sellerTaxIdsFor(context, data, _tools).then((ids) {
      if (mounted) setState(() => _taxIds = ids);
    });
  }

  Future<void> _share(ReceiptData data, String lang) async {
    if (_tools.documents) {
      return openSaleShareSheet(
        context,
        data: data,
        lang: lang,
        tools: _tools,
        tin: _taxIds.tin,
        vrn: _taxIds.vrn,
      );
    }
    // Sale extras #3: Image, PDF (made on the device) and Share as text.
    await showReceiptShareSheet(
      context,
      data: data,
      lang: lang,
      tin: _taxIds.tin,
      vrn: _taxIds.vrn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLang = FFLocaleScope.of(context).locale.languageCode;
    final lang = _lang ?? appLang;
    final locale = FFLocaleScope.of(context);
    final data = _data;
    if (data != null) _loadTaxIds(data);
    final queued = widget.clientRef == null
        ? null
        : _session?.byRef(widget.clientRef!);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _newSale();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(context.tr('vendor.documents.receipt')),
        ),
        body: _loading
            ? const Center(child: FFSpinner())
            : data == null
            ? ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  if (_failed)
                    FFErrorState(
                      message: context.tr('vendor.sales.failed'),
                      onRetry: _load,
                    )
                  else
                    FFEmptyState(
                      key: const Key('sales-receipt-not-found'),
                      title: context.tr('vendor.sales.notFound'),
                    ),
                ],
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: ListView(
                    padding: const EdgeInsets.all(FFTokens.spacingLg),
                    children: [
                      if (queued != null && queued.isConflict) ...[
                        FFAlert(
                          key: const Key('sales-receipt-conflict'),
                          message: context.tr('vendor.sync.needsFixing'),
                          tone: FFAlertTone.warning,
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: FFButton(
                            label: context.tr('vendor.sync.fix'),
                            variant: FFButtonVariant.ghost,
                            visualDensity: VisualDensity.standard,
                            onPressed: () => context.push(salesSyncRoute),
                          ),
                        ),
                        const SizedBox(height: FFTokens.spacingSm),
                      ],
                      ReceiptView(
                        data: data,
                        lang: lang,
                        t: (k) => locale.tIn(lang, k),
                        headingFocus: _heading,
                        tin: _taxIds.tin,
                        vrn: _taxIds.vrn,
                      ),
                      const SizedBox(height: FFTokens.spacingMd),
                      ReceiptLanguageToggle(
                        value: lang,
                        onChanged: (v) => setState(() => _lang = v),
                      ),
                    ],
                  ),
                ),
              ),
        bottomNavigationBar: _loading
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FFButton(
                        key: const Key('sales-receipt-new'),
                        label: context.tr('vendor.pos.newSale'),
                        icon: Icons.add_shopping_cart,
                        fullWidth: true,
                        visualDensity: VisualDensity.standard,
                        onPressed: _newSale,
                      ),
                      const SizedBox(height: FFTokens.spacingSm),
                      Wrap(
                        spacing: FFTokens.spacingSm,
                        runSpacing: FFTokens.spacingSm,
                        alignment: WrapAlignment.center,
                        children: [
                          if (data != null && !data.voided)
                            FFButton(
                              key: const Key('sales-receipt-share'),
                              label: context.tr('vendor.pos.share'),
                              icon: Icons.share,
                              variant: FFButtonVariant.secondary,
                              visualDensity: VisualDensity.standard,
                              onPressed: () => _share(data, lang),
                            ),
                          FFButton(
                            key: const Key('sales-receipt-done'),
                            label: context.tr('vendor.pos.done'),
                            variant: FFButtonVariant.ghost,
                            visualDensity: VisualDensity.standard,
                            onPressed: _done,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
