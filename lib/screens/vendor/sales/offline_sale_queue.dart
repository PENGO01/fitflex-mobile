// Vendor tools · S3: walk-in sales kept on this device until FitFlex has them
// (spec §6), the draft cart (§2.5) and the product list used offline (§6.1).
//
// - Everything is keyed by vendor + person, so another person signing in on
//   the same device never sees or sends someone else's sales.
// - A sale is queued only when no answer came back (network failure or
//   timeout), or when the seller chose "Save and sync later" after a 5xx.
//   4xx answers are never queued.
// - Queued sales sync one at a time, oldest first, each with its own
//   clientRef, so a retry after a lost answer records exactly one sale.
// - Nothing is ever deleted because the feature went off; only Discard
//   removes a queued sale.
// - shared_preferences (localStorage on web) is not encrypted: no cost price
//   and no customer data are stored. S4: a paid sale with a customer keeps
//   the customer's opaque id only (never a name or phone); a pay-later sale
//   is never queued.
//
// Pattern from SmartStock's offline_sale_queue.dart; no new packages.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import 'sale_models.dart';

/// One sale kept on this device.
class QueuedSale {
  QueuedSale({
    required this.body,
    required this.display,
    required this.queuedAt,
    this.attempts = 0,
    this.lastAttemptAt,
    this.state = 'waiting',
    this.error,
    this.sentOnline = false,
  });

  /// The exact request (with its clientRef and soldAt).
  final Map<String, dynamic> body;

  /// What the receipt needs: business, line names and list prices, served by.
  final Map<String, dynamic> display;
  final String queuedAt;
  int attempts;
  String? lastAttemptAt;

  /// waiting | syncing | conflict
  String state;

  /// The server's refusal (conflicts): `{code, status, body}`.
  Map<String, dynamic>? error;

  /// The till first sent this sale online, without `soldAt` (the server's
  /// clock), before it was kept here. If that send was in fact recorded, the
  /// server answers client_ref_reused to this body (with `soldAt`); the
  /// queue then replays the online body to get the recorded sale.
  final bool sentOnline;

  /// The body as the till sent it online (no soldAt).
  Map<String, dynamic> get onlineBody =>
      Map<String, dynamic>.from(body)..remove('soldAt');

  String get clientRef => body['clientRef']?.toString() ?? '';
  bool get isConflict => state == 'conflict';
  String? get errorCode => error?['code']?.toString();
  Map<String, dynamic> get errorBody =>
      error?['body'] is Map ? Map<String, dynamic>.from(error!['body']) : {};

  int get totalTzs {
    final rows = (body['lines'] as List? ?? []).whereType<Map>().toList();
    final shown = (display['lines'] as List? ?? []).whereType<Map>().toList();
    var total = 0;
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final list = i < shown.length
          ? (shown[i]['listPriceTzs'] as num? ?? 0)
          : 0;
      final price = (r['unitPriceTzs'] as num?) ?? list;
      total +=
          ((r['qty'] as num? ?? 0) * price - (r['discountTzs'] as num? ?? 0))
              .toInt();
    }
    return total - ((body['discountTzs'] as num?)?.toInt() ?? 0);
  }

  Map<String, dynamic> toJson() => {
    'body': body,
    'display': display,
    'queuedAt': queuedAt,
    'attempts': attempts,
    'lastAttemptAt': ?lastAttemptAt,
    'state': state,
    'error': ?error,
    if (sentOnline) 'sentOnline': true,
  };

  static QueuedSale? fromJson(Object? raw) {
    if (raw is! Map || raw['body'] is! Map) return null;
    final body = Map<String, dynamic>.from(raw['body'] as Map);
    if ((body['clientRef']?.toString() ?? '').isEmpty) return null;
    final state = raw['state']?.toString();
    return QueuedSale(
      body: body,
      display: raw['display'] is Map
          ? Map<String, dynamic>.from(raw['display'] as Map)
          : {},
      queuedAt: raw['queuedAt']?.toString() ?? '',
      attempts: (raw['attempts'] as num?)?.toInt() ?? 0,
      lastAttemptAt: raw['lastAttemptAt']?.toString(),
      // A sale cut off mid-sync (app killed) is simply waiting again.
      state: state == 'conflict' ? 'conflict' : 'waiting',
      error: raw['error'] is Map
          ? Map<String, dynamic>.from(raw['error'] as Map)
          : null,
      sentOnline: raw['sentOnline'] == true,
    );
  }
}

/// Why automatic syncing is paused.
enum SalesSyncPause {
  none,

  /// 404 feature_disabled: until the options say walkInSales again.
  featureOff,

  /// 403 vendor_suspended: until it changes (a Sync now or resume asks again).
  suspended,

  /// 403 permission / staff inactive: stops for this person.
  notAllowed,

  /// 401: until the person signs in again.
  signedOut,
}

/// The product fields the POS keeps for offline use. Never cost price.
/// S8 (§7, overrides the S3 §6.1 allowlist): also the product's barcodes,
/// `[{code, variant}]` only, so a scan matches offline.
const _cachedProductFields = [
  'id',
  'name',
  'brand',
  'sku',
  'priceTzs',
  'discountPriceTzs',
  'status',
  'stock',
];

Map<String, dynamic> cacheableProduct(Map<String, dynamic> p) {
  final images = (p['images'] as List?)?.whereType<String>().toList();
  return {
    for (final f in _cachedProductFields)
      if (p[f] != null) f: p[f],
    if (images != null && images.isNotEmpty) 'images': [images.first],
    'variants': [
      for (final v in (p['variants'] as List? ?? []).whereType<Map>())
        {'name': v['name'], if (v['stock'] is num) 'stock': v['stock']},
    ],
    if (p['barcodes'] is List)
      'barcodes': [
        for (final b in (p['barcodes'] as List).whereType<Map>())
          if (b['code'] is String)
            {
              'code': b['code'],
              'variant': b['variant'] is String ? b['variant'] : null,
            },
      ],
  };
}

/// The walk-in sales on this device for one vendor and one person.
class SalesSession extends ChangeNotifier with WidgetsBindingObserver {
  SalesSession({
    required this.api,
    required this.vendorId,
    required this.personId,
    DateTime Function()? now,
    this.timerDelay = const Duration(seconds: 60),
  }) : _now = now ?? DateTime.now;

  final ApiClient api;
  final String vendorId;
  final String personId;
  final DateTime Function() _now;

  /// The steady sync interval while sales wait (and the first back-off).
  final Duration timerDelay;

  String get queueKey => 'vendor_sale_queue.$vendorId.$personId';
  String get draftKey => 'vendor_pos_draft.$vendorId.$personId';
  String get productsKey => 'vendor_pos_products.$vendorId';
  String get businessKey => 'vendor_pos_business.$vendorId';
  String get suspendedKey => 'vendor_sales_suspended.$vendorId.$personId';

  List<QueuedSale> _queue = [];
  bool _loaded = false;
  Future<void>? _loading;
  Future<void>? _running;
  SalesSyncPause _pause = SalesSyncPause.none;
  bool _suspended = false;
  int _failures = 0;
  Timer? _timer;
  int _attached = 0;
  int _draftCount = 0;
  String? _lastTry;
  DateTime? _retryAt;

  /// Server sales that a queued sale became, by clientRef (this session).
  final Map<String, Map<String, dynamic>> synced = {};

  /// Announced once per sync result (e.g. by the open page).
  final StreamController<String> _syncedNumbers =
      StreamController<String>.broadcast();
  Stream<String> get syncedNumbers => _syncedNumbers.stream;

  bool get loaded => _loaded;
  bool get syncing => _running != null;
  SalesSyncPause get pause => _pause;
  String? get lastTry => _lastTry;
  int get draftCount => _draftCount;

  /// Oldest first.
  List<QueuedSale> get all => List.unmodifiable(_queue);
  List<QueuedSale> get waiting => _queue.where((q) => !q.isConflict).toList();
  List<QueuedSale> get conflicts => _queue.where((q) => q.isConflict).toList();
  bool get isEmpty => _queue.isEmpty;

  QueuedSale? byRef(String clientRef) {
    for (final q in _queue) {
      if (q.clientRef == clientRef) return q;
    }
    return null;
  }

  // ── which session ───────────────────────────────────────────────────────

  static final Expando<SalesSession> _sessions = Expando('salesSession');

  /// The vendor and person a signed-in user acts as, or null (not a vendor).
  static ({String vendorId, String personId})? identityOf(
    Map<String, dynamic>? user,
  ) {
    final type = user?['userType']?.toString();
    final id = user?['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    if (type == 'vendor') return (vendorId: id, personId: id);
    if (type == 'vendor_staff') {
      final vendor = user?['vendorId']?.toString() ?? '';
      if (vendor.isEmpty) return null;
      return (vendorId: vendor, personId: id);
    }
    return null;
  }

  /// The session of whoever is signed in (a new one when the person or
  /// vendor changed). Null when the user is not a vendor or their staff.
  static SalesSession? of(BuildContext context) {
    final scope = AppScope.of(context);
    final who = identityOf(scope.auth.user);
    if (who == null) return null;
    final hit = _sessions[scope.api];
    if (hit != null &&
        hit.vendorId == who.vendorId &&
        hit.personId == who.personId) {
      return hit;
    }
    hit?._stop();
    final session = SalesSession(
      api: scope.api,
      vendorId: who.vendorId,
      personId: who.personId,
    );
    _sessions[scope.api] = session;
    unawaited(session.load());
    return session;
  }

  /// Test hook: forget the cached sessions of [api].
  @visibleForTesting
  static void forget(ApiClient api) {
    _sessions[api]?._stop();
    _sessions[api] = null;
  }

  // ── storage ─────────────────────────────────────────────────────────────

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(queueKey);
      if (raw != null) {
        final list = jsonDecode(raw);
        if (list is List) {
          _queue = [for (final e in list) ?QueuedSale.fromJson(e)];
        }
      }
      // Kept across restarts: the till stays off until a sales call
      // succeeds again (S3 UAT, D4).
      if (prefs.getBool(suspendedKey) == true) {
        _suspended = true;
        if (_pause == SalesSyncPause.none) _pause = SalesSyncPause.suspended;
      }
      final draft = prefs.getString(draftKey);
      if (draft != null) {
        _draftCount = PosCart.fromJson(jsonDecode(draft)).itemCount;
      }
    } catch (_) {
      // An unreadable store is treated as empty; it is not overwritten
      // until something new is saved.
    }
    _loaded = true;
    notifyListeners();
    _schedule();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      queueKey,
      jsonEncode([for (final q in _queue) q.toJson()]),
    );
  }

  /// Keeps [sale] on this device (it syncs later).
  Future<void> enqueue(QueuedSale sale) async {
    await load();
    _queue.removeWhere((q) => q.clientRef == sale.clientRef);
    _queue.add(sale);
    await _save();
    notifyListeners();
    _schedule();
  }

  /// Removes a queued sale (Discard, or its edited copy was recorded).
  Future<void> remove(String clientRef) async {
    await load();
    _queue.removeWhere((q) => q.clientRef == clientRef);
    await _save();
    notifyListeners();
    _schedule();
  }

  /// "Record with today's date" for a sale too old to keep its date: the
  /// same lines and payments under a new clientRef, no soldAt (the server's
  /// now), and the original date in the note. Then it syncs.
  Future<void> recordToday(String clientRef, String originally) async {
    await load();
    final item = byRef(clientRef);
    if (item == null) return;
    final next = QueuedSale(
      body: recordTodayBody(item.body, originally),
      display: item.display,
      queuedAt: item.queuedAt,
    );
    _queue[_queue.indexOf(item)] = next;
    await _save();
    notifyListeners();
    await sync(manual: true);
  }

  /// "Try again" on a conflict: the unchanged sale, same clientRef.
  Future<void> retry(String clientRef) async {
    await load();
    final item = byRef(clientRef);
    if (item == null) return;
    item.state = 'waiting';
    item.error = null;
    await _save();
    notifyListeners();
    await sync(manual: true);
  }

  /// S4 "Try again without customer": the customer was archived or is gone,
  /// so the same sale is sent again without one (same clientRef: the
  /// refused attempt recorded nothing).
  Future<void> retryWithoutCustomer(String clientRef) async {
    await load();
    final item = byRef(clientRef);
    if (item == null) return;
    item.body.remove('customerId');
    item.state = 'waiting';
    item.error = null;
    await _save();
    notifyListeners();
    await sync(manual: true);
  }

  /// Units of a product (or variant) in sales still waiting on this device.
  int queuedQty(String productId, String? variant) {
    var n = 0;
    for (final q in _queue) {
      if (q.isConflict) continue;
      for (final l in (q.body['lines'] as List? ?? []).whereType<Map>()) {
        final v = l['variant']?.toString();
        if (l['productId']?.toString() == productId &&
            (v == null || v.isEmpty ? null : v) == variant) {
          n += (l['qty'] as num? ?? 0).toInt();
        }
      }
    }
    return n;
  }

  // Draft cart ------------------------------------------------------------

  Future<PosCart?> loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(draftKey);
      if (raw == null) return null;
      final cart = PosCart.fromJson(jsonDecode(raw));
      return cart.isEmpty ? null : cart;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDraft(PosCart cart) async {
    final prefs = await SharedPreferences.getInstance();
    if (cart.isEmpty) {
      await prefs.remove(draftKey);
    } else {
      await prefs.setString(draftKey, jsonEncode(cart.toJson()));
    }
    if (_draftCount != cart.itemCount) {
      _draftCount = cart.itemCount;
      notifyListeners();
    }
  }

  Future<void> clearDraft() => saveDraft(PosCart());

  // Business header (receipts made offline) -------------------------------

  /// Keeps what a receipt header needs from the business profile.
  Future<void> saveBusiness(Map<String, dynamic> profile) async {
    final keep = {
      for (final f in const ['businessName', 'contactNumber', 'address'])
        if ((profile[f]?.toString() ?? '').trim().isNotEmpty) f: profile[f],
    };
    if (keep.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(businessKey, jsonEncode(keep));
  }

  Future<Map<String, dynamic>> loadBusiness() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(businessKey);
      final data = raw == null ? null : jsonDecode(raw);
      return data is Map ? Map<String, dynamic>.from(data) : {};
    } catch (_) {
      return {};
    }
  }

  /// The till was told the business is suspended (403 vendor_suspended).
  void markSuspended() {
    final changed = !_suspended || _pause != SalesSyncPause.suspended;
    _suspended = true;
    _pause = SalesSyncPause.suspended;
    unawaited(_keepSuspended(true));
    if (changed) notifyListeners();
  }

  /// The business is suspended (403 vendor_suspended), as last heard from
  /// the server; kept on the device until a sales call succeeds.
  bool get suspended => _suspended;

  /// A sales call succeeded: the business is not suspended (any more).
  void salesAnswered() {
    if (!_suspended) return;
    _suspended = false;
    if (_pause == SalesSyncPause.suspended) _pause = SalesSyncPause.none;
    unawaited(_keepSuspended(false));
    notifyListeners();
    _schedule();
  }

  Future<void> _keepSuspended(bool on) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      on
          ? await prefs.setBool(suspendedKey, true)
          : await prefs.remove(suspendedKey);
    } catch (_) {}
  }

  // Product cache ---------------------------------------------------------

  Future<void> saveProducts(List<Map<String, dynamic>> products) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      productsKey,
      jsonEncode({
        'cachedAt': _now().toUtc().toIso8601String(),
        'products': [for (final p in products) cacheableProduct(p)],
      }),
    );
  }

  Future<({List<Map<String, dynamic>> products, String? cachedAt})?>
  loadProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(productsKey);
      if (raw == null) return null;
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      return (
        products: [
          for (final p in (data['products'] as List? ?? []).whereType<Map>())
            Map<String, dynamic>.from(p),
        ],
        cachedAt: data['cachedAt']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  // ── sync ────────────────────────────────────────────────────────────────

  /// Widgets that show sales attach while they are on screen: the 60-second
  /// timer, app resume and "any successful vendor call" only run then.
  void attach() {
    _attached += 1;
    if (_attached == 1) {
      WidgetsBinding.instance.addObserver(this);
      api.addSuccessListener(_onApiSuccess);
      _schedule();
    }
  }

  void detach() {
    if (_attached == 0) return;
    _attached -= 1;
    if (_attached == 0) {
      WidgetsBinding.instance.removeObserver(this);
      api.removeSuccessListener(_onApiSuccess);
      _timer?.cancel();
      _timer = null;
    }
  }

  void _stop() {
    _attached = 1;
    detach();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Being back may mean a suspension or a lost connection is over.
      if (_pause == SalesSyncPause.suspended) _pause = SalesSyncPause.none;
      unawaited(sync());
    }
  }

  void _onApiSuccess(String method, String path) {
    if (!path.startsWith('/vendor/')) return;
    if (path.startsWith('/vendor/sales')) salesAnswered();
    // Our own sync calls arrive here too: the running loop ignores them.
    if (_running != null || waiting.isEmpty) return;
    scheduleMicrotask(() => unawaited(sync()));
  }

  /// The feature is on again (options say walkInSales).
  void featureOn() {
    if (_pause == SalesSyncPause.featureOff) {
      _pause = SalesSyncPause.none;
      notifyListeners();
      unawaited(sync());
    }
  }

  /// The feature is off (options say so). Queued sales stay.
  void featureOff() {
    if (_pause == SalesSyncPause.none) {
      _pause = SalesSyncPause.featureOff;
      notifyListeners();
    }
  }

  /// The person signed in again.
  void signedIn() {
    if (_pause == SalesSyncPause.signedOut) _pause = SalesSyncPause.none;
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_attached == 0 || waiting.isEmpty) return;
    if (_pause != SalesSyncPause.none) return;
    // Back-off after failures: 60 s → 2 min → 5 min (cap).
    var delay = switch (_failures) {
      0 || 1 => timerDelay,
      2 => timerDelay * 2,
      _ => timerDelay * 5,
    };
    // 429: not before the server's Retry-After.
    final retryAt = _retryAt;
    if (retryAt != null) {
      final wait = retryAt.difference(_now());
      if (wait > delay) delay = wait;
    }
    _timer = Timer(delay, () => unawaited(sync()));
  }

  /// Sends waiting sales, oldest first, one at a time. One loop at a time:
  /// a call while it runs gets the running one. [manual]: Sync now, which
  /// also asks again after a suspension.
  Future<void> sync({bool manual = false}) {
    final running = _running;
    if (running != null) {
      // A manual retry waits for the running loop, then goes again for
      // sales that loop did not pick up.
      return manual ? running.then((_) => sync(manual: true)) : running;
    }
    if (manual &&
        (_pause == SalesSyncPause.suspended ||
            _pause == SalesSyncPause.notAllowed)) {
      _pause = SalesSyncPause.none;
    }
    if (_pause != SalesSyncPause.none) return Future.value();
    // Rate limited: automatic attempts wait for Retry-After.
    final retryAt = _retryAt;
    if (!manual && retryAt != null && _now().isBefore(retryAt)) {
      return Future.value();
    }
    final run = _syncLoop();
    _running = run;
    notifyListeners();
    return run.whenComplete(() {
      _running = null;
      notifyListeners();
      _schedule();
    });
  }

  Future<void> _syncLoop() async {
    await load();
    final batch = waiting..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    for (final item in batch) {
      if (!_queue.contains(item)) continue;
      item.state = 'syncing';
      item.attempts += 1;
      item.lastAttemptAt = _lastTry = _now().toUtc().toIso8601String();
      notifyListeners();
      try {
        Map<String, dynamic> res;
        try {
          res = await api.vendorRecordSale(item.body);
        } on ApiException catch (e) {
          // The online send was recorded after all: fetch it by replaying
          // that exact body (same clientRef → 200 with the same sale).
          if (!item.sentOnline || e.code != 'client_ref_reused') rethrow;
          res = await api.vendorRecordSale(item.onlineBody);
        }
        final sale = res['sale'];
        // An answer without the sale is not proof it was recorded: keep it.
        if (sale is! Map) throw StateError('no sale in the answer');
        _queue.remove(item);
        _retryAt = null;
        salesAnswered();
        synced[item.clientRef] = Map<String, dynamic>.from(sale);
        final number = sale['number']?.toString();
        if (number != null) _syncedNumbers.add(number);
        _failures = 0;
        await _save();
        notifyListeners();
      } on ApiException catch (e) {
        final stop = _refused(item, e);
        await _save();
        notifyListeners();
        if (stop) return;
      } catch (_) {
        // No answer: still waiting; try later.
        item.state = 'waiting';
        _failures = min(_failures + 1, 3);
        await _save();
        notifyListeners();
        return;
      }
    }
  }

  /// Applies a refusal to [item]. Returns true when the loop must stop.
  bool _refused(QueuedSale item, ApiException e) {
    final code = e.code;
    final body = e.body is Map ? Map<String, dynamic>.from(e.body) : {};
    void conflict() {
      item.state = 'conflict';
      item.error = {'code': code, 'status': e.status, 'body': body};
    }

    if (e.status == 401) {
      item.state = 'waiting';
      _pause = SalesSyncPause.signedOut;
      return true;
    }
    // S4: customers switched off while a sale with a customer waited: that
    // sale needs fixing (send it without the customer); the rest go on.
    if (e.status == 404 &&
        code == 'feature_disabled' &&
        body['feature'] == 'customers') {
      conflict();
      return false;
    }
    if (e.status == 404 && code == 'feature_disabled') {
      item.state = 'waiting';
      _pause = SalesSyncPause.featureOff;
      return true;
    }
    if (e.status == 403 && code == 'vendor_suspended') {
      item.state = 'waiting';
      markSuspended();
      return true;
    }
    if (e.status == 403) {
      conflict();
      _pause = SalesSyncPause.notAllowed;
      return true;
    }
    if (e.status == 429) {
      item.state = 'waiting';
      final after = (body['retryAfterSeconds'] as num?)?.toInt() ?? 60;
      _retryAt = _now().add(Duration(seconds: after.clamp(1, 3600)));
      return true;
    }
    if (e.status >= 500 || e.status == 408) {
      item.state = 'waiting';
      _failures = min(_failures + 1, 3);
      return true;
    }
    // 400 / 404 / 409: this sale needs fixing; the next one is independent.
    conflict();
    return false;
  }

  @override
  void dispose() {
    _stop();
    _syncedNumbers.close();
    super.dispose();
  }
}
