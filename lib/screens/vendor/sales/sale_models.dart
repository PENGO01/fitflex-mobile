// Vendor tools · S3 (walk-in sales): the cart, its totals, the payment rules
// and the request body. Pure Dart: no widgets, no storage, no network, so the
// money maths is tested on its own.
//
// The client mirrors the server (fitflex-functions src/shared/vendor-sale.mjs)
// to guide the seller; the server recomputes every total and wins. Money is
// whole TZS everywhere.
import 'dart:math';

/// Payment methods, in the order the payment sheet offers them.
const salePaymentMethods = [
  'cash',
  'mpesa',
  'airtel_money',
  'mixx',
  'halopesa',
  'card',
  'bank',
  'other',
];

/// Methods whose transaction reference is required (owner rule 2026-10-19).
const referenceRequiredMethods = {
  'mpesa',
  'airtel_money',
  'mixx',
  'halopesa',
  'bank',
};

/// Sale extras §1.3: the methods whose reference the SALE sheet requires.
/// With `referenceOptional` on, none (cash references are kept too); off,
/// today's rule. Customer payments, refunds and purchases keep
/// [referenceRequiredMethods] (Q-1).
Set<String> saleReferenceRequired({required bool referenceOptional}) =>
    referenceOptional ? const <String>{} : referenceRequiredMethods;

/// Characters the server refuses in a payment reference: Unicode control
/// characters (`\p{Cc}`: U+0000–U+001F, U+007F and U+0080–U+009F, e.g. NEL
/// U+0085), newlines included. Stripped as the seller types or pastes.
final referenceControlChars = RegExp(r'[\x00-\x1F\x7F-\x9F]');

/// A reference as it is sent: control characters removed, trimmed.
String cleanReference(String raw) =>
    raw.replaceAll(referenceControlChars, ' ').trim();

/// Sale extras §2.1 (Q-5): what kind of customer this purchase was from,
/// in the order the pills show them. Stored on the sale, never printed on
/// a receipt.
const saleCustomerTypes = ['new', 'returning', 'walk_in', 'online', 'other'];

/// The i18n key naming a customer type; null for anything unknown (the raw
/// code is never shown).
String? customerTypeKey(String? type) =>
    saleCustomerTypes.contains(type) ? 'vendor.customerType.$type' : null;

const maxQtyPerLine = 1000;
const maxSaleLines = 100;
const maxSalePayments = 10;
const maxSaleNote = 200;
const maxPaymentReference = 100;
const voidReasonMin = 3;
const voidReasonMax = 200;

/// Server limits (vendor-sale.mjs): change may be at most the total plus
/// 1,000,000; a sale and its payments at most 100,000,000.
const maxChangeOverTotalTzs = 1000000;
const maxSaleTzs = 100000000;

/// The i18n key naming [method] (never the raw code).
String paymentMethodKey(String? method) => switch (method) {
  'cash' => 'vendor.pos.method.cash',
  'halopesa' => 'vendor.pos.method.halopesa',
  'mpesa' ||
  'airtel_money' ||
  'mixx' ||
  'card' ||
  'bank' => 'payment.method.$method',
  _ => 'vendor.pos.method.other',
};

/// A new idempotency key for one sale: 128 random bits, matching the
/// server's `[A-Za-z0-9._:-]{8,100}`. Same generator as S1's stock
/// adjustments (no uuid package).
String newSaleClientRef([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return 'sale_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

/// The last 6 characters of a clientRef, in capitals: what a queued sale's
/// provisional receipt shows.
String tempRefOf(String clientRef) {
  final clean = clientRef.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  final tail = clean.length <= 6 ? clean : clean.substring(clean.length - 6);
  return tail.toUpperCase();
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// The walk-in price of a vendor product map (Q-3): the discount price when
/// set and below the price, else the price. Same rule as the server.
int walkInPrice(Map<String, dynamic> product) {
  final price = _int(product['priceTzs']);
  final discount = _int(product['discountPriceTzs']);
  return discount > 0 && discount < price ? discount : price;
}

/// Variants of a product map that keep their own stock (`stock` is a number).
List<({String name, int stock})> stockVariants(Map<String, dynamic> p) => [
  for (final v in (p['variants'] as List? ?? []).whereType<Map>())
    if (v['stock'] is num && (v['name']?.toString() ?? '').isNotEmpty)
      (name: v['name'].toString(), stock: (v['stock'] as num).toInt()),
];

/// Whether a sale of this product needs a variant picked (the server answers
/// variant_required when its variants keep stock).
bool needsVariant(Map<String, dynamic> p) => stockVariants(p).isNotEmpty;

/// [pct] percent of [base], in whole TZS rounded down (Q-5).
int percentOf(int base, num pct) {
  if (base <= 0 || pct <= 0) return 0;
  return (base * pct / 100).floor();
}

/// One line of the cart.
class PosLine {
  PosLine({
    required this.productId,
    this.variant,
    required this.name,
    required this.listPriceTzs,
    this.qty = 1,
    this.unitPriceTzs,
    this.discountTzs = 0,
  });

  final String productId;
  final String? variant;
  final String name;

  /// The shop's walk-in price when the line was added.
  final int listPriceTzs;
  int qty;

  /// The seller's own price; null keeps [listPriceTzs].
  int? unitPriceTzs;

  /// Discount for the whole line (not per unit).
  int discountTzs;

  String get key => keyOf(productId, variant);
  static String keyOf(String productId, String? variant) =>
      '$productId\u0000${variant ?? ''}';

  int get priceEach => unitPriceTzs ?? listPriceTzs;
  bool get priceChanged => unitPriceTzs != null && unitPriceTzs != listPriceTzs;
  int get grossTzs => qty * priceEach;
  int get lineTotalTzs => grossTzs - discountTzs;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'variant': ?variant,
    'name': name,
    'listPriceTzs': listPriceTzs,
    'qty': qty,
    'unitPriceTzs': ?unitPriceTzs,
    'discountTzs': discountTzs,
  };

  static PosLine? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['productId']?.toString() ?? '';
    final qty = _int(raw['qty']);
    if (id.isEmpty || qty < 1) return null;
    final variant = raw['variant']?.toString();
    return PosLine(
      productId: id,
      variant: variant == null || variant.isEmpty ? null : variant,
      name: raw['name']?.toString() ?? '',
      listPriceTzs: _int(raw['listPriceTzs']),
      qty: min(qty, maxQtyPerLine),
      unitPriceTzs: raw['unitPriceTzs'] == null
          ? null
          : _int(raw['unitPriceTzs']),
      discountTzs: _int(raw['discountTzs']),
    );
  }

  /// The request line: `unitPriceTzs` only when changed, `discountTzs` only
  /// when above 0.
  Map<String, dynamic> toRequest() => {
    'productId': productId,
    'variant': ?variant,
    'qty': qty,
    if (priceChanged) 'unitPriceTzs': unitPriceTzs,
    if (discountTzs > 0) 'discountTzs': discountTzs,
  };
}

/// The cart's totals (a preview: the server's own totals win).
class CartTotals {
  const CartTotals({
    required this.subtotalTzs,
    required this.lineDiscountTzs,
    required this.saleDiscountTzs,
  });

  /// Σ qty × price each, before discounts.
  final int subtotalTzs;
  final int lineDiscountTzs;
  final int saleDiscountTzs;

  int get afterLinesTzs => subtotalTzs - lineDiscountTzs;
  int get discountsTzs => lineDiscountTzs + saleDiscountTzs;
  int get totalTzs => max(0, subtotalTzs - discountsTzs);
}

/// The cart: lines, sale discount and note, plus the idempotency key and
/// sale time fixed when Complete is first tapped.
class PosCart {
  PosCart({
    List<PosLine>? lines,
    this.saleDiscountTzs = 0,
    this.note = '',
    this.clientRef,
    this.soldAt,
    this.replacesClientRef,
    this.keepSoldAt = false,
    this.customerId,
    String? customerType,
  }) : lines = lines ?? [],
       customerType = saleCustomerTypes.contains(customerType)
           ? customerType
           : null;

  final List<PosLine> lines;
  int saleDiscountTzs;
  String note;

  /// Set at the first Complete; reused on every retry of the same sale.
  String? clientRef;

  /// Device time at the first Complete (UTC ISO).
  String? soldAt;

  /// "Edit sale" from a conflict: the queued sale this one replaces.
  String? replacesClientRef;

  /// An edited conflict keeps the original sale time.
  bool keepSoldAt;

  /// S4: the customer of this sale — an opaque id only. Their name is never
  /// stored on the device (A-02); see [customerName].
  String? customerId;

  /// The customer's name for the chip, in memory only (never in [toJson]).
  String? customerName;

  /// Sale extras: the customer type (one of [saleCustomerTypes]) or null.
  /// Not personal data: kept in the draft and the queued body (§2.7).
  String? customerType;

  /// Sets or clears the type. It is part of the server's fingerprint, so a
  /// different type is a new key at the next Complete.
  void setCustomerType(String? type) {
    final next = saleCustomerTypes.contains(type) ? type : null;
    if (next != customerType) clientRef = null;
    customerType = next;
  }

  /// S4: what the chosen customer already owes (people with `customers`
  /// only), for the pay-later warning. In memory only.
  int? customerOwedTzs;
  int? customerOverdueTzs;

  /// Sets or clears the customer. A different customer is a different
  /// sale: a new key at the next Complete.
  void setCustomer(String? id, {String? name, int? owedTzs, int? overdueTzs}) {
    if (id != customerId) clientRef = null;
    customerId = id;
    customerName = id == null ? null : name;
    customerOwedTzs = id == null ? null : owedTzs;
    customerOverdueTzs = id == null ? null : overdueTzs;
  }

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.fold(0, (s, l) => s + l.qty);

  CartTotals get totals => CartTotals(
    subtotalTzs: lines.fold(0, (s, l) => s + l.grossTzs),
    lineDiscountTzs: lines.fold(0, (s, l) => s + l.discountTzs),
    saleDiscountTzs: saleDiscountTzs,
  );

  int qtyOf(String productId, String? variant) => lines
      .where((l) => l.productId == productId && l.variant == variant)
      .fold(0, (s, l) => s + l.qty);

  PosLine? lineOf(String productId, String? variant) {
    for (final l in lines) {
      if (l.productId == productId && l.variant == variant) return l;
    }
    return null;
  }

  /// Any change to what is sold is a new sale: a new key at the next Complete.
  void changed() {
    clientRef = null;
    if (!keepSoldAt) soldAt = null;
    // A sale discount larger than what is left after line discounts drops.
    final after = totals.afterLinesTzs;
    if (saleDiscountTzs > after) saleDiscountTzs = max(0, after);
  }

  /// Adds one of a product (or variant). Returns false at [available] or the
  /// per-line cap.
  bool addOne({
    required String productId,
    String? variant,
    required String name,
    required int priceTzs,
    int? available,
  }) {
    final existing = lineOf(productId, variant);
    final have = existing?.qty ?? 0;
    final cap = min(maxQtyPerLine, available ?? maxQtyPerLine);
    if (have + 1 > cap) return false;
    if (existing != null) {
      existing.qty += 1;
    } else {
      if (lines.length >= maxSaleLines) return false;
      lines.add(
        PosLine(
          productId: productId,
          variant: variant,
          name: name,
          listPriceTzs: priceTzs,
        ),
      );
    }
    changed();
    return true;
  }

  void setQty(PosLine line, int qty) {
    if (qty < 1) {
      remove(line);
      return;
    }
    line.qty = min(qty, maxQtyPerLine);
    // A line discount larger than the line drops to the line.
    if (line.discountTzs > line.grossTzs) line.discountTzs = line.grossTzs;
    changed();
  }

  void remove(PosLine line) {
    lines.remove(line);
    changed();
  }

  void clear() {
    lines.clear();
    saleDiscountTzs = 0;
    note = '';
    clientRef = null;
    soldAt = null;
    replacesClientRef = null;
    keepSoldAt = false;
    setCustomer(null);
    customerType = null;
  }

  /// Fixes the key and the sale time (once) and returns the request body.
  ///
  /// A sale recorded online sends no `soldAt`: the server uses its own clock
  /// (a wrong phone clock cannot misdate it). `soldAt` is sent only for a
  /// sale kept on the device ([queued]) or an edited offline sale that keeps
  /// its original time ([keepSoldAt]).
  ///
  /// S4: `customerId` when a customer is attached. A pay-later sale passes
  /// [creditDueDate] (kind `credit`); it is never queued.
  ///
  /// Sale extras: `customerType` only when set, so a sale without one has
  /// the same body (and server fingerprint) as before. Never a name or a
  /// phone: the queue stores this body as it is.
  Map<String, dynamic> requestBody(
    List<Map<String, dynamic>> payments, {
    bool queued = false,
    String Function()? makeClientRef,
    DateTime Function()? now,
    String? creditDueDate,
  }) {
    clientRef ??= (makeClientRef ?? newSaleClientRef)();
    soldAt ??= (now ?? DateTime.now)().toUtc().toIso8601String();
    final trimmed = note.trim();
    return {
      'clientRef': clientRef,
      if (queued || keepSoldAt) 'soldAt': soldAt,
      'lines': [for (final l in lines) l.toRequest()],
      if (saleDiscountTzs > 0) 'discountTzs': saleDiscountTzs,
      'payments': payments,
      if (trimmed.isNotEmpty) 'note': trimmed,
      'customerId': ?customerId,
      'customerType': ?customerType,
      if (creditDueDate != null) ...{
        'kind': 'credit',
        'dueDate': creditDueDate,
      },
    };
  }

  /// "Record with today's date" (a sale older than the server accepts):
  /// a new key, no `soldAt` (the server's now), and the original date in
  /// the note ([originally] is e.g. "originally 12 Oct 2026").
  void recordToday(String originally) {
    note = withOriginalDate(note, originally);
    keepSoldAt = false;
    soldAt = null;
    clientRef = null;
  }

  Map<String, dynamic> toJson() => {
    'lines': [for (final l in lines) l.toJson()],
    'saleDiscountTzs': saleDiscountTzs,
    'note': note,
    'clientRef': ?clientRef,
    'soldAt': ?soldAt,
    'replacesClientRef': ?replacesClientRef,
    if (keepSoldAt) 'keepSoldAt': true,
    // The id only: never the customer's name or phone (A-02, spec §8).
    'customerId': ?customerId,
    'customerType': ?customerType,
  };

  static PosCart fromJson(Object? raw) {
    if (raw is! Map) return PosCart();
    return PosCart(
      lines: [
        for (final l in (raw['lines'] as List? ?? [])) ?PosLine.fromJson(l),
      ],
      saleDiscountTzs: _int(raw['saleDiscountTzs']),
      note: raw['note']?.toString() ?? '',
      clientRef: raw['clientRef']?.toString(),
      soldAt: raw['soldAt']?.toString(),
      replacesClientRef: raw['replacesClientRef']?.toString(),
      keepSoldAt: raw['keepSoldAt'] == true,
      customerId: raw['customerId']?.toString(),
      customerType: raw['customerType']?.toString(),
    );
  }

  /// A queued sale's request back in the cart ("Edit sale"): same lines and
  /// sale time, a new key at the next Complete.
  static PosCart fromQueuedRequest(
    Map<String, dynamic> body,
    List<Map<String, dynamic>> displayLines, {
    required String replaces,
  }) {
    final rows = (body['lines'] as List? ?? []).whereType<Map>().toList();
    final lines = <PosLine>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final shown = i < displayLines.length ? displayLines[i] : const {};
      final list = _int(shown['listPriceTzs']);
      final price = r['unitPriceTzs'] == null ? null : _int(r['unitPriceTzs']);
      final line = PosLine.fromJson({
        'productId': r['productId'],
        'variant': r['variant'],
        'name': shown['name'] ?? '',
        'listPriceTzs': list > 0 ? list : (price ?? 0),
        'qty': r['qty'],
        'unitPriceTzs': price,
        'discountTzs': r['discountTzs'] ?? 0,
      });
      if (line != null) lines.add(line);
    }
    return PosCart(
      lines: lines,
      saleDiscountTzs: _int(body['discountTzs']),
      note: body['note']?.toString() ?? '',
      soldAt: body['soldAt']?.toString(),
      keepSoldAt: true,
      replacesClientRef: replaces,
      customerId: body['customerId']?.toString(),
      customerType: body['customerType']?.toString(),
    );
  }
}

/// One payment row in the payment sheet.
class PaymentRow {
  PaymentRow({
    this.method,
    this.amountTzs = 0,
    this.reference = '',
    this.referenceOptional = false,
  });
  String? method;
  int amountTzs;
  String reference;

  /// Sale extras #1: every method may carry a reference (cash too) and
  /// none needs one. Off: today's rule (§1.5, an older server).
  final bool referenceOptional;

  bool get needsReference =>
      method != null &&
      saleReferenceRequired(
        referenceOptional: referenceOptional,
      ).contains(method);
  bool get referenceMissing =>
      needsReference && cleanReference(reference).isEmpty;

  /// Whether this row's reference is sent: never for cash unless
  /// [referenceOptional].
  bool get sendsReference => method != 'cash' || referenceOptional;

  Map<String, dynamic> toRequest() {
    final ref = cleanReference(reference);
    return {
      'method': method,
      'amountTzs': amountTzs,
      if (sendsReference && ref.isNotEmpty) 'reference': ref,
    };
  }
}

/// Where a set of payment rows stands against a total (mirrors the server:
/// Σ payments ≥ total, only cash gives change).
class PaymentCheck {
  PaymentCheck(this.totalTzs, List<PaymentRow> rows)
    : rows = List.unmodifiable(rows) {
    paidTzs = rows.fold(0, (s, r) => s + max(0, r.amountTzs));
    cashTzs = rows
        .where((r) => r.method == 'cash')
        .fold(0, (s, r) => s + max(0, r.amountTzs));
  }

  final int totalTzs;
  final List<PaymentRow> rows;
  late final int paidTzs;
  late final int cashTzs;

  bool get nothingToPay => totalTzs == 0;
  int get remainingTzs => nothingToPay ? 0 : max(0, totalTzs - paidTzs);
  int get overTzs => nothingToPay ? 0 : max(0, paidTzs - totalTzs);

  /// Change to give back: only when the excess is covered by cash.
  int get changeTzs => overTzs > 0 && overTzs <= cashTzs ? overTzs : 0;

  /// Non-cash methods together pay more than the total.
  bool get nonCashOver => overTzs > cashTzs;

  /// The first non-cash method, for the "Lower the {method} amount" line.
  String? get overMethod => nonCashOver
      ? rows
            .where((r) => r.method != null && r.method != 'cash')
            .firstOrNull
            ?.method
      : null;

  /// Change beyond what the server accepts (likely a typo in the amount).
  bool get changeTooLarge => changeTzs > totalTzs + maxChangeOverTotalTzs;

  /// More paid than any sale may hold.
  bool get paidTooLarge => paidTzs > maxSaleTzs;

  List<int> get missingReferences => [
    for (var i = 0; i < rows.length; i++)
      if (rows[i].referenceMissing) i,
  ];

  bool get rowsComplete =>
      rows.every((r) => r.method != null && r.amountTzs >= 1);

  /// Whether Complete sale may be pressed.
  bool get canComplete {
    if (nothingToPay) return true;
    return rows.isNotEmpty &&
        rows.length <= maxSalePayments &&
        rowsComplete &&
        remainingTzs == 0 &&
        !nonCashOver &&
        !changeTooLarge &&
        !paidTooLarge &&
        missingReferences.isEmpty;
  }

  /// The request's payments (`[]` when the total is 0, Q-8).
  List<Map<String, dynamic>> toRequest() =>
      nothingToPay ? const [] : [for (final r in rows) r.toRequest()];
}

/// The quick cash chips for an amount still due: Exact, then up to three
/// round-ups (next 1,000 / 5,000 / 10,000 above it), duplicates dropped.
List<int> quickCashAmounts(int due) {
  if (due <= 0) return const [];
  final out = <int>[due];
  for (final step in const [1000, 5000, 10000]) {
    final up = (due ~/ step + 1) * step;
    if (!out.contains(up)) out.add(up);
  }
  return out;
}

/// The i18n key for a server refusal of a sale (spec §9.6); never the raw
/// code. [reason] is `invalid_payment`'s reason, when sent.
String saleErrorKey(String? code, {String? reason}) => switch (code) {
  'insufficient_stock' => 'vendor.sync.conflictStock',
  'payment_short' => 'vendor.pos.short',
  'discount_exceeds_price' => 'vendor.pos.discountTooBig',
  'invalid_payment' when reason == 'change_too_large' =>
    'vendor.pos.err.changeTooLarge',
  'invalid_payment' when reason == 'paid_too_large' =>
    'vendor.pos.err.paidTooLarge',
  'invalid_payment' || 'reference_required' => 'vendor.pos.err.payment',
  'product_not_found' ||
  'product_unavailable' ||
  'variant_not_found' ||
  'variant_required' => 'vendor.pos.err.unavailable',
  'sold_at_out_of_range' => 'vendor.sync.conflictTooOld',
  'vendor_permission_forbidden' ||
  'vendor_staff_inactive' ||
  'account_suspended' => 'vendor.sync.conflictNotAllowed',
  'vendor_suspended' => 'vendor.sales.suspended',
  _ => 'vendor.sync.conflictOther',
};

/// [note] with "originally {date}" added, within the 200-character limit.
String withOriginalDate(String note, String originally) {
  final base = note.trim();
  final joined = base.isEmpty ? originally : '$base · $originally';
  if (joined.length <= maxSaleNote) return joined;
  final room = maxSaleNote - originally.length - 3;
  return room <= 0
      ? originally.substring(0, maxSaleNote)
      : '${base.substring(0, room)} · $originally';
}

/// A queued request recorded "with today's date": a new clientRef, no
/// soldAt, the original date in the note.
Map<String, dynamic> recordTodayBody(
  Map<String, dynamic> body,
  String originally, {
  String Function()? makeClientRef,
}) => {
  ...Map<String, dynamic>.from(body)..remove('soldAt'),
  'clientRef': (makeClientRef ?? newSaleClientRef)(),
  'note': withOriginalDate(body['note']?.toString() ?? '', originally),
};

/// Whether a refused `soldAt` was too old (before the server's earliest),
/// as opposed to ahead of its clock (the phone's date is wrong).
bool soldAtTooOld(String? soldAt, Map body) {
  final sold = DateTime.tryParse(soldAt ?? '');
  final earliest = DateTime.tryParse(body['earliest']?.toString() ?? '');
  if (sold == null) return false;
  if (earliest == null) {
    return DateTime.now().toUtc().difference(sold) > const Duration(days: 7);
  }
  return sold.isBefore(earliest);
}

/// The key for [n] of something: `{key}One` when [n] is 1 (English "1 sale"
/// vs "2 sales"), else [key].
String pluralKey(String key, num n) => n == 1 ? '${key}One' : key;
