// Vendor tools · S1 (stock ledger): which tools the server has on, and the
// small helpers the stock screens share.
//
// The server says which vendor tools are on (GET /vendor/tools/options). The
// app shows the stock ledger only when `stockLedger` is exactly `true`; a
// failed call, a missing field or anything else keeps the old screens. A
// failure is not remembered, so the next refresh asks again.
//
// S3 UAT (decision 2026-10-20): the last successful answer is kept on the
// device per vendor + person. When the call fails WITHOUT an answer (no
// connection), the kept answer is used if it is under 7 days old, so walk-in
// sales keep working after an offline restart. A refusal from the server
// (403, 404, 5xx) still means everything off, as does no kept answer.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';

/// The vendor tools switched on for this session.
class VendorTools {
  const VendorTools({
    this.stockLedger = false,
    this.canSeeCost = false,
    this.buyerContact = false,
    this.walkInSales = false,
    this.customers = false,
    this.banners = false,
    this.flashSales = false,
    this.productTargets = false,
    this.shopAreas = false,
    this.documents = false,
    this.vat = false,
    this.vatInForce,
    this.reports = false,
    this.refunds = false,
    this.purchases = false,
    this.barcodes = false,
    this.dataImport = false,
    this.importMaxBytes = defaultImportMaxBytes,
    this.importMaxRows = defaultImportMaxRows,
    this.canSeeOrderMoney = false,
    this.referenceOptional = false,
    this.saleCustomerDetails = false,
    this.suspended = false,
    this.fromCache = false,
  });

  /// The server refused with 403 `account_suspended`: the business is
  /// suspended. Every tool is off, and screens say why (not "isn't
  /// available yet").
  final bool suspended;

  static const accountSuspended = VendorTools(suspended: true);

  /// Everything off: the old screens.
  static const off = VendorTools();

  /// Stock history, reasons, per-variant stock, reorder levels, low stock.
  final bool stockLedger;

  /// Cost price may be seen and sent (the vendor and their admin staff).
  final bool canSeeCost;

  /// S2: the buyer's phone is shared inside the O-3 window
  /// (VENDOR_ORDER_BUYER_CONTACT). The server enforces it; the app only uses
  /// it to explain why the phone and address are gone.
  final bool buyerContact;

  /// S3: walk-in (counter) sales — POS, sales history, void
  /// (VENDOR_WALKIN_SALES). Exactly `true` from the server, else off.
  final bool walkInSales;

  /// S4: vendor customers, pay later, customer payments and "Owed to you"
  /// (VENDOR_CUSTOMERS). Exactly `true` from the server, else off. Pay later
  /// also needs [walkInSales] (it lives in the POS).
  final bool customers;

  /// Shop home Phase 2 S1: vendors propose hero banners (SHOP_BANNERS),
  /// from `merch: {banners: true}`. Exactly `true`, else off.
  final bool banners;

  /// Shop home Phase 2 S4: vendors propose flash sales (SHOP_FLASH_SALES),
  /// from `merch: {flashSales: true}`. Exactly `true`, else off.
  final bool flashSales;

  /// Shop home Phase 2 S2: products may carry "Made for" / "Age group"
  /// (SHOP_PERSONALISATION), from `merch: {productTargets: true}`. Exactly
  /// `true`, else off.
  final bool productTargets;

  /// Shop home Phase 2 S3: "Where you sell" ("Based in" / "Delivers to")
  /// on the business profile (SHOP_NEAR_YOU), from `merch: {shopAreas:
  /// true}`. Exactly `true`, else off.
  final bool shopAreas;

  /// S5: share links, PDFs, the share sheet and order invoices
  /// (VENDOR_DOCUMENTS). Exactly `true`, else the S3/S4 text share.
  final bool documents;

  /// S5: tax details, product VAT codes and VAT blocks (VENDOR_VAT).
  /// Exactly `true`, else none of them.
  final bool vat;

  /// S5: the vendor's VAT is in force right now (verified, certificate
  /// stands), from the options answer. Null when the server does not send
  /// it (older backend): screens then ask GET /vendor/tax-profile.
  final bool? vatInForce;

  /// S6: vendor reports and their CSV / PDF downloads (VENDOR_REPORTS).
  /// Exactly `true`, else the tab stays "Payments" with no Reports.
  final bool reports;

  /// S7: making, undoing and sharing refunds on walk-in sales
  /// (VENDOR_REFUNDS). Exactly `true`, else off. Refunds live on walk-in
  /// sales, so screens also need [walkInSales] (see [refundsOn]). Refunds
  /// already made stay readable with this off.
  final bool refunds;

  /// Refund items / Undo may be offered: walk-in sales and refunds both on
  /// (spec §0.2, fail closed).
  bool get refundsOn => walkInSales && refunds;

  /// S9: suppliers, receiving stock (GRN) and what is owed to suppliers
  /// (VENDOR_TOOLS + VENDOR_STOCK_LEDGER + VENDOR_PURCHASES on the server).
  /// Exactly `true`, else off: no Purchases view, routes go home.
  final bool purchases;

  /// S8: barcodes on products, scanning in the POS, Receive stock and the
  /// Products tab (VENDOR_TOOLS + VENDOR_STOCK_LEDGER + VENDOR_BARCODES on
  /// the server). Exactly `true`, else off (fail closed): no scan buttons,
  /// no Barcodes section, Enter in the POS search as before (SKU).
  final bool barcodes;

  /// Smart import V3 (VENDOR_TOOLS + VENDOR_IMPORT): CSV import of
  /// products, stock counts and the business profile, from the options
  /// answer's `import`. Exactly `true`, else off (fail closed). The person
  /// also needs the staff permission `import` (see `importOpen`).
  final bool dataImport;

  /// The file caps from `importLimits` (the server enforces them; the app
  /// only checks first to save a wasted upload). Defaults when the server
  /// sends nothing usable.
  final int importMaxBytes;
  final int importMaxRows;

  static const defaultImportMaxBytes = 2 * 1024 * 1024;
  static const defaultImportMaxRows = 2000;

  /// S6: this person may see commission and payouts (the vendor, admin
  /// staff, staff with `payments`): the "App sales after commission"
  /// report. Exactly `true`, else hidden.
  final bool canSeeOrderMoney;

  /// Sale extras #1 (VENDOR_SALE_REFERENCE_OPTIONAL): every walk-in sale
  /// payment row has an optional reference, cash included. Exactly `true`,
  /// else today's rule (required for mobile money and bank, none for cash).
  /// Use [saleReferenceOptionalOn] (needs [walkInSales] too).
  final bool referenceOptional;

  /// Sale extras #2 (VENDOR_SALE_CUSTOMER_DETAILS): the optional Customer
  /// section in the payment sheet. Exactly `true`, else hidden. Use
  /// [saleCustomerDetailsOn] (needs [walkInSales] too).
  final bool saleCustomerDetails;

  /// The sale sheet's references are optional for every method (fail
  /// closed: a missing key, an older server, or walk-in sales off).
  bool get saleReferenceOptionalOn => walkInSales && referenceOptional;

  /// The payment sheet shows the Customer section.
  bool get saleCustomerDetailsOn => walkInSales && saleCustomerDetails;

  /// The answer is the one kept on this device (the server could not be
  /// reached): ask again once the connection is back.
  final bool fromCache;

  static VendorTools fromOptions(Map options, {bool fromCache = false}) =>
      VendorTools(
        stockLedger: options['stockLedger'] == true,
        canSeeCost: options['canSeeCost'] == true,
        buyerContact: options['buyerContact'] == true,
        walkInSales: options['walkInSales'] == true,
        customers: options['customers'] == true,
        banners:
            options['merch'] is Map &&
            (options['merch'] as Map)['banners'] == true,
        flashSales:
            options['merch'] is Map &&
            (options['merch'] as Map)['flashSales'] == true,
        productTargets:
            options['merch'] is Map &&
            (options['merch'] as Map)['productTargets'] == true,
        shopAreas:
            options['merch'] is Map &&
            (options['merch'] as Map)['shopAreas'] == true,
        documents: options['documents'] == true,
        vat: options['vat'] == true,
        vatInForce: options['vatInForce'] is bool
            ? options['vatInForce'] as bool
            : null,
        reports: options['reports'] == true,
        refunds: options['refunds'] == true,
        purchases: options['purchases'] == true,
        barcodes: options['barcodes'] == true,
        dataImport: options['import'] == true,
        importMaxBytes: _positiveInt(
          options['importLimits'],
          'maxBytes',
          defaultImportMaxBytes,
        ),
        importMaxRows: _positiveInt(
          options['importLimits'],
          'maxRows',
          defaultImportMaxRows,
        ),
        canSeeOrderMoney: options['canSeeOrderMoney'] == true,
        referenceOptional: options['referenceOptional'] == true,
        saleCustomerDetails: options['saleCustomerDetails'] == true,
        fromCache: fromCache,
      );
}

int _positiveInt(Object? limits, String key, int fallback) {
  final v = limits is Map ? limits[key] : null;
  return v is num && v > 0 ? v.toInt() : fallback;
}

class _Cached {
  _Cached(this.token, this.tools);
  final String? token;
  final VendorTools tools;
}

/// Asks the server which vendor tools are on (GET /vendor/tools/options).
class VendorToolsOptions {
  VendorToolsOptions._();

  // One answer per API client and signed-in session (token).
  static final Expando<_Cached> _cache = Expando<_Cached>('vendorTools');

  /// The tools on for this session. Asks once per session, or again when
  /// [refresh] is set (pull to refresh). Never throws: a failure means
  /// everything off and is not remembered.
  static Future<VendorTools> load(
    ApiClient api,
    String? token, {
    bool refresh = false,
    Map<String, dynamic>? user,
    DateTime Function()? now,
  }) async {
    final hit = _cache[api];
    if (!refresh && hit != null && hit.token == token) return hit.tools;
    final key = keptKey(user);
    try {
      final options = await api.vendorToolsOptions();
      final tools = VendorTools.fromOptions(options);
      _cache[api] = _Cached(token, tools);
      if (key != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            key,
            jsonEncode({
              'at': (now ?? DateTime.now)().toUtc().toIso8601String(),
              'options': options,
            }),
          );
        } catch (_) {
          // Not kept; the live answer still applies.
        }
      }
      return tools;
    } on ApiException catch (e) {
      // The server answered and refused: off (fail closed). A suspended
      // business is told so.
      _cache[api] = null;
      return e.status == 403 && e.code == 'account_suspended'
          ? VendorTools.accountSuspended
          : VendorTools.off;
    } catch (_) {
      // No answer: the last one kept on this device, if recent enough. Not
      // remembered in memory, so the next load asks the server again.
      _cache[api] = null;
      return await _kept(key, now) ?? VendorTools.off;
    }
  }

  static const keptFor = Duration(days: 7);

  /// Where the last answer for this vendor + person is kept.
  static String? keptKey(Map<String, dynamic>? user) {
    final type = user?['userType']?.toString();
    final id = user?['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final vendor = type == 'vendor_staff'
        ? (user?['vendorId']?.toString() ?? '')
        : type == 'vendor'
        ? id
        : '';
    if (vendor.isEmpty) return null;
    return 'vendor_tools_options.$vendor.$id';
  }

  static Future<VendorTools?> _kept(
    String? key,
    DateTime Function()? now,
  ) async {
    if (key == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final data = jsonDecode(raw);
      if (data is! Map || data['options'] is! Map) return null;
      final at = DateTime.tryParse(data['at']?.toString() ?? '');
      if (at == null) return null;
      final age = (now ?? DateTime.now)().toUtc().difference(at);
      if (age.isNegative || age > keptFor) return null;
      return VendorTools.fromOptions(data['options'] as Map, fromCache: true);
    } catch (_) {
      return null;
    }
  }

  /// Same as [load], for a widget's context.
  static Future<VendorTools> of(BuildContext context, {bool refresh = false}) {
    final scope = AppScope.of(context);
    return load(
      scope.api,
      scope.auth.token,
      refresh: refresh,
      user: scope.auth.user,
    );
  }
}

/// Whether the signed-in vendor (or staff member) may work on products.
bool canManageProducts(BuildContext context) => canVendor(context, 'products');

/// Whether the signed-in vendor (or staff member) has [permission].
bool canVendor(BuildContext context, String permission) {
  final user = AppScope.of(context).auth.user;
  if (user?['userType'] != 'vendor_staff') return true;
  return (user?['vendorPermissions'] as List? ?? []).contains(permission);
}

/// [template] with each `{name}` replaced by its value.
String fillIn(String template, Map<String, Object?> values) {
  var out = template;
  values.forEach((key, value) => out = out.replaceAll('{$key}', '$value'));
  return out;
}

/// A stock count: plain under 10,000, grouped above (no currency).
String formatStock(num value) =>
    value.abs() < 10000 ? '${value.toInt()}' : formatMoney(value);

/// A signed change, with a real minus sign: `+5`, `−2`, `0`.
String formatDelta(num delta) {
  if (delta > 0) return '+${formatStock(delta)}';
  if (delta < 0) return '−${formatStock(-delta)}';
  return '0';
}

/// Reasons a vendor gives, in the order the chips show them.
const adjustReasons = [
  'count',
  'restock',
  'returned',
  'found',
  'damaged',
  'expired',
  'lost',
  'other',
];

const inReasons = {'restock', 'returned', 'found'};
const outReasons = {'damaged', 'expired', 'lost'};

const _labelledReasons = {
  ...adjustReasons,
  'reserve',
  'release',
  'sale',
  'sale_void',
  // S7: a refund put units back; its undo took them out again.
  'refund_restock',
  'refund_revert',
  // S9: received from a supplier (a GRN), and its void.
  'stock_in',
  'stock_in_void',
};

/// The words for a ledger row's reason; never the raw code.
String stockReasonLabel(BuildContext context, String? reason) => context.tr(
  _labelledReasons.contains(reason)
      ? 'vendor.stock.reason.$reason'
      : 'vendor.stock.reason.unknown',
);

/// Notes the server writes itself, shown in words.
String? stockNoteLabel(BuildContext context, String? note) => switch (note) {
  null || '' => null,
  'product_form' => context.tr('vendor.stock.fromProductForm'),
  'product_created' => context.tr('vendor.stock.initial'),
  'variants_tracked' => context.tr('vendor.stock.toVariants'),
  // A sale / refund void or a GRN whose variant was removed meanwhile: the
  // units went to (or came from) the product's own count.
  'variant_gone' => context.tr('vendor.stock.note.variantGone'),
  _ => note,
};

/// Today in East Africa (UTC+3, no daylight saving), as a date.
DateTime eatToday([DateTime? now]) {
  final eat = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 3));
  return DateTime.utc(eat.year, eat.month, eat.day);
}

/// A day as the server takes it: YYYY-MM-DD.
String eatDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// The low-stock list (GET /vendor/stock/low), by product.
class LowStockIndex {
  LowStockIndex(List<dynamic> rows)
    : _rows = rows.whereType<Map>().map(Map<String, dynamic>.from).toList();

  LowStockIndex.empty() : _rows = const [];

  final List<Map<String, dynamic>> _rows;

  /// Products that are low (the product itself or any of its variants).
  Set<String> get productIds =>
      _rows.map((r) => r['productId']?.toString() ?? '').toSet()..remove('');

  int get count => productIds.length;

  bool isLow(String? productId) => productIds.contains(productId);

  /// Variant names of [productId] that are low.
  List<String> lowVariants(String? productId) => [
    for (final r in _rows)
      if (r['productId']?.toString() == productId &&
          (r['variant']?.toString() ?? '').isNotEmpty)
        r['variant'].toString(),
  ];

  /// Whether this product row itself (no variant) is low.
  bool productLow(String? productId) => _rows.any(
    (r) =>
        r['productId']?.toString() == productId &&
        (r['variant']?.toString() ?? '').isEmpty,
  );
}
