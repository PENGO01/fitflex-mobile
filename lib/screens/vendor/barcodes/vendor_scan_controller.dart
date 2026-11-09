// Vendor tools · S8: what happens to a scanned or typed code (spec §4.3).
//
// - B-11 filter (FitFlex QR codes and long payloads are not product codes);
// - one code at a time (a code in flight drops the others);
// - debounce: the same codeKey is ignored for 1,500 ms after it was handled
//   (camera only; a typed code is always handled);
// - the screen's loaded product list first (barcode codeKey, then exact
//   SKU), then GET /vendor/products/lookup when online; lookup answers are
//   kept in memory for this session;
// - 429: scanning pauses for retryAfterSeconds, then resumes on its own.
//
// Non-visual: the screens decide what a match does (cart, delivery, count).
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../shared/api_client.dart';
import 'barcode_rules.dart';

/// One product a code points at (a local row, or a lookup match).
class ScanMatch {
  const ScanMatch({
    required this.productId,
    required this.name,
    this.variant,
    this.variants,
    this.priceTzs,
    this.discountPriceTzs,
    this.stock = 0,
    this.status = 'active',
    this.approvalStatus = 'approved',
    this.sku,
    this.matchedBy = 'barcode',
    this.product,
  });

  /// From a GET /vendor/products/lookup match.
  factory ScanMatch.fromLookup(Map m) => ScanMatch(
    productId: m['productId']?.toString() ?? '',
    name: m['name']?.toString() ?? '',
    variant: m['variant'] is String && (m['variant'] as String).isNotEmpty
        ? m['variant'] as String
        : null,
    variants: m['variants'] is List
        ? [
            for (final v in (m['variants'] as List).whereType<Map>())
              if ((v['name']?.toString() ?? '').isNotEmpty)
                {
                  'name': v['name'].toString(),
                  if (v['stock'] is num) 'stock': (v['stock'] as num).toInt(),
                },
          ]
        : null,
    priceTzs: (m['priceTzs'] as num?)?.toInt(),
    discountPriceTzs: (m['discountPriceTzs'] as num?)?.toInt(),
    stock: (m['stock'] as num?)?.toInt() ?? 0,
    status: m['status']?.toString() ?? 'active',
    // Absent: as list rows read it (approved).
    approvalStatus: m['approvalStatus']?.toString() ?? 'approved',
    sku: m['sku']?.toString(),
    matchedBy: m['matchedBy']?.toString() ?? 'barcode',
  );

  /// From a row of the screen's product list.
  factory ScanMatch.fromProduct(
    Map<String, dynamic> p, {
    String? variant,
    String matchedBy = 'barcode',
  }) {
    final variants = (p['variants'] as List? ?? const []).whereType<Map>();
    int stock = (p['stock'] as num?)?.toInt() ?? 0;
    if (variant != null) {
      for (final v in variants) {
        if (v['name']?.toString() == variant && v['stock'] is num) {
          stock = (v['stock'] as num).toInt();
        }
      }
    }
    return ScanMatch(
      productId: p['id']?.toString() ?? '',
      name: p['name']?.toString() ?? '',
      variant: variant,
      priceTzs: (p['priceTzs'] as num?)?.toInt(),
      discountPriceTzs: (p['discountPriceTzs'] as num?)?.toInt(),
      stock: stock,
      status: p['status']?.toString() ?? 'active',
      approvalStatus: p['approvalStatus']?.toString() ?? 'approved',
      sku: p['sku']?.toString(),
      matchedBy: matchedBy,
      product: p,
    );
  }

  final String productId;
  final String name;

  /// The code's variant; null for a whole-product code or a SKU match.
  final String? variant;

  /// Lookup only: `[{name, stock}]` when [variant] is null and the product
  /// keeps stock per variant.
  final List<Map<String, dynamic>>? variants;
  final int? priceTzs;
  final int? discountPriceTzs;
  final int stock;
  final String status;
  final String approvalStatus;
  final String? sku;

  /// `barcode` or `sku`.
  final String matchedBy;

  /// The full row when the match came from the loaded list.
  final Map<String, dynamic>? product;

  bool get archived => status == 'archived';

  /// "Name (variant)".
  String get label => variant == null ? name : '$name ($variant)';

  /// A product map the screens can use: the loaded row, else one built
  /// from the lookup answer (no cost, no images).
  Map<String, dynamic> get asProduct =>
      product ??
      {
        'id': productId,
        'name': name,
        'priceTzs': ?priceTzs,
        'discountPriceTzs': ?discountPriceTzs,
        'stock': stock,
        'status': status,
        'approvalStatus': approvalStatus,
        'sku': ?sku,
        // A variant code: that variant with its own stock, so the stock
        // rules of the screens apply to it.
        'variants':
            variants ??
            [
              if (variant != null) {'name': variant, 'stock': stock},
            ],
      };
}

/// The screen's loaded products, by barcode codeKey and by SKU (B-9).
class ProductCodeIndex {
  ProductCodeIndex(Iterable<Map<String, dynamic>> products) {
    for (final p in products) {
      if (p['deletedAt'] != null) continue;
      for (final b in barcodesOf(p)) {
        _byKey.putIfAbsent(codeKey(b.code), () => (p, b.variant));
      }
      final sku = p['sku']?.toString().trim().toLowerCase() ?? '';
      if (sku.isNotEmpty) _bySku.putIfAbsent(sku, () => []).add(p);
    }
  }

  ProductCodeIndex.empty();

  final Map<String, (Map<String, dynamic>, String?)> _byKey = {};
  final Map<String, List<Map<String, dynamic>>> _bySku = {};
  final Map<String, List<ScanMatch>> _learned = {};

  /// Matches for [raw]: barcode first, then exact SKU (trimmed, any case),
  /// then answers the lookup gave this session. Empty when none.
  List<ScanMatch> match(String raw) {
    final key = codeKey(raw);
    final hit = _byKey[key];
    if (hit != null) return [ScanMatch.fromProduct(hit.$1, variant: hit.$2)];
    final sku = _bySku[raw.trim().toLowerCase()];
    if (sku != null && sku.isNotEmpty) {
      // As the server: by name, then id, at most 10 (B-9).
      final rows = [...sku]
        ..sort((a, b) {
          final byName = (a['name']?.toString() ?? '').compareTo(
            b['name']?.toString() ?? '',
          );
          return byName != 0
              ? byName
              : (a['id']?.toString() ?? '').compareTo(
                  b['id']?.toString() ?? '',
                );
        });
      return [
        for (final p in rows.take(maxSkuMatches))
          ScanMatch.fromProduct(p, matchedBy: 'sku'),
      ];
    }
    return _learned[key] ?? const [];
  }

  /// Only a barcode match (POS Enter: a code beats a text match).
  ScanMatch? barcodeMatch(String raw) {
    final hit = _byKey[codeKey(raw)];
    return hit == null ? null : ScanMatch.fromProduct(hit.$1, variant: hit.$2);
  }

  /// Keeps a lookup answer for this session (§7: memory only).
  void learn(String raw, List<ScanMatch> matches) {
    if (matches.isNotEmpty) _learned[codeKey(raw)] = matches;
  }
}

/// What handling a code came to.
enum ScanOutcomeKind {
  /// One or more products (several only through SKU).
  matched,

  /// No product has this code (online).
  notFound,

  /// Offline and not in the saved list.
  notFoundOffline,

  /// B-11: not a product barcode.
  notProduct,

  /// 429: wait [ScanOutcome.seconds].
  rateLimited,

  /// Network or server failure: Try again.
  lookupFailed,

  /// 404 feature_disabled: barcodes went off on the server.
  featureOff,

  /// 403 (no list permission).
  noAccess,

  /// 403 vendor_suspended.
  suspended,
}

class ScanOutcome {
  const ScanOutcome(
    this.kind,
    this.code, {
    this.matches = const [],
    this.seconds,
  });

  final ScanOutcomeKind kind;

  /// The code as scanned or typed, trimmed.
  final String code;
  final List<ScanMatch> matches;
  final int? seconds;
}

/// Answers GET /vendor/products/lookup?code= (the `matches` list).
typedef ScanLookup = Future<List<ScanMatch>> Function(String code);

/// The default lookup through the app's API client.
ScanLookup apiScanLookup(ApiClient api) => (code) async {
  final res = await api.vendorProductLookup(code);
  return [
    for (final m in (res['matches'] as List? ?? const []).whereType<Map>())
      ScanMatch.fromLookup(m),
  ];
};

class VendorScanController extends ChangeNotifier {
  VendorScanController({
    required ProductCodeIndex Function() index,
    this.lookup,
    bool Function()? online,
    DateTime Function()? now,
    this.debounce = const Duration(milliseconds: 1500),
  }) : _index = index,
       _online = online ?? (() => true),
       _now = now ?? DateTime.now;

  final ProductCodeIndex Function() _index;
  final ScanLookup? lookup;
  final bool Function() _online;
  final DateTime Function() _now;
  final Duration debounce;

  String? _lastKey;
  DateTime? _lastAt;
  bool _busy = false;
  String? _looking;
  DateTime? _pausedUntil;
  Timer? _resumeTimer;

  /// A code is being handled (a lookup in flight, or the screen holds it
  /// while a sheet is open): other detections are dropped.
  bool get busy => _busy;

  /// The code being looked up now (for "Looking up {code}…").
  String? get looking => _looking;

  /// Paused after a 429, until this time.
  DateTime? get pausedUntil => _pausedUntil;

  bool get rateLimited =>
      _pausedUntil != null && _now().isBefore(_pausedUntil!);

  /// The screen holds the scanner while it shows a choice (a sheet or a
  /// dialog); detections are dropped until [release].
  void hold() {
    _busy = true;
    _held = true;
    notifyListeners();
  }

  void release() {
    _busy = false;
    _held = false;
    notifyListeners();
  }

  bool _held = false;

  /// A sheet or dialog is over the scanner: the camera is stopped.
  bool get held => _held;

  /// "Scan again": the same code is handled at once next time.
  void resetDebounce() {
    _lastKey = null;
    _lastAt = null;
  }

  /// Handles [raw]. Null when the code was dropped (busy, debounced, empty,
  /// or a camera detection while paused after a 429). [typed]: from Type
  /// code, the search field or a USB scanner (no debounce).
  Future<ScanOutcome?> handle(String raw, {bool typed = false}) async {
    final code = raw.trim();
    if (code.isEmpty || _busy) return null;
    if (isNotProductCode(code)) {
      // Said once per payload, as any other repeat.
      if (!typed && _debounced(code)) return null;
      _mark(code);
      return ScanOutcome(ScanOutcomeKind.notProduct, code);
    }
    if (!typed && _debounced(code)) return null;
    final local = _index().match(code);
    if (local.isNotEmpty) {
      _mark(code);
      return ScanOutcome(ScanOutcomeKind.matched, code, matches: local);
    }
    final lookup = this.lookup;
    if (lookup == null || !_online()) {
      _mark(code);
      return ScanOutcome(ScanOutcomeKind.notFoundOffline, code);
    }
    if (rateLimited) {
      if (!typed) return null;
      return ScanOutcome(
        ScanOutcomeKind.rateLimited,
        code,
        seconds: _secondsLeft(),
      );
    }
    _busy = true;
    _looking = code;
    notifyListeners();
    try {
      final matches = await lookup(code);
      _index().learn(code, matches);
      _mark(code);
      return ScanOutcome(
        matches.isEmpty ? ScanOutcomeKind.notFound : ScanOutcomeKind.matched,
        code,
        matches: matches,
      );
    } on ApiException catch (e) {
      _mark(code);
      return _refusal(e, code);
    } catch (_) {
      // No answer: nothing is remembered, so Try again looks it up again.
      return ScanOutcome(ScanOutcomeKind.lookupFailed, code);
    } finally {
      _busy = false;
      _looking = null;
      notifyListeners();
    }
  }

  ScanOutcome _refusal(ApiException e, String code) {
    if (e.status == 429) {
      final body = e.body is Map ? e.body as Map : const {};
      final s = (body['retryAfterSeconds'] as num?)?.toInt() ?? 60;
      _pause(s < 1 ? 1 : s);
      return ScanOutcome(ScanOutcomeKind.rateLimited, code, seconds: s);
    }
    if (e.status == 404 && e.code == 'feature_disabled') {
      return ScanOutcome(ScanOutcomeKind.featureOff, code);
    }
    if (e.status == 403) {
      return ScanOutcome(
        e.code == 'vendor_suspended'
            ? ScanOutcomeKind.suspended
            : ScanOutcomeKind.noAccess,
        code,
      );
    }
    // 400 code_required / invalid_code: it cannot be any product's code.
    if (e.status == 400) return ScanOutcome(ScanOutcomeKind.notFound, code);
    return ScanOutcome(ScanOutcomeKind.lookupFailed, code);
  }

  void _pause(int seconds) {
    _pausedUntil = _now().add(Duration(seconds: seconds));
    _resumeTimer?.cancel();
    _resumeTimer = Timer(Duration(seconds: seconds), () {
      _pausedUntil = null;
      notifyListeners();
    });
    notifyListeners();
  }

  int _secondsLeft() {
    final until = _pausedUntil;
    if (until == null) return 0;
    final ms = until.difference(_now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  bool _debounced(String code) {
    final at = _lastAt;
    return _lastKey == codeKey(code) &&
        at != null &&
        _now().difference(at) < debounce;
  }

  void _mark(String code) {
    _lastKey = codeKey(code);
    _lastAt = _now();
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    super.dispose();
  }
}
