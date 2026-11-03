// Vendor tools · S7: refunds on walk-in sales (design spec
// docs/design/vendor-refunds-s7.md; backend fitflex-functions#318). Pure
// Dart: what the refund screen picks, the preview of what it gives back,
// the server's refund read defensively, who may refund or undo, the error
// words and the credit note as plain text. No widgets, storage or network.
//
// The client never sends money: POST /vendor/sales/:id/refunds carries
// sale line ids, quantities, restock flags, the reason and (when money is
// given back) a method and reference. [previewRefund] mirrors the server's
// rounding (spec §1 M-2..M-4) for display only; the server's figures win.
//
// Refunds are online only (§4.7): nothing here is ever queued or kept on
// the device.
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../shared/formatters.dart';
import '../../documents/document_models.dart' show DocVatRow, vatRowsOf;
import '../receipt_data.dart' show eatDateTime, eatDayOf;
import '../sale_models.dart';

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String? _str(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// A refund or undo reason: 3–200 characters after trimming (server rule).
const refundReasonMin = 3;
const refundReasonMax = 200;

/// The reason suggestions, in the order the pills show them (§4.2).
const refundReasonKeys = ['returned', 'faulty', 'wrong', 'mind', 'other'];

/// A new idempotency key for one refund: 128 random bits, matching the
/// server's `[A-Za-z0-9._:-]{8,100}` (same generator as S3 sales).
String newRefundClientRef([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return 'rfd_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

// ── the sale's lines, as the refund screen sees them ─────────────────────

/// One line of the sale with its refund counters (the S7 sale view).
class RefundableLine {
  const RefundableLine({
    required this.saleLineId,
    required this.name,
    this.variant,
    this.productId,
    required this.qty,
    required this.lineNetTzs,
    this.refundedQty = 0,
    this.refundedTzs = 0,
    this.vatTzs = 0,
  });

  /// From a line of GET /vendor/sales/:id. Missing counters read as none
  /// refunded; `lineNetTzs` falls back to `lineTotalTzs` (older answer).
  factory RefundableLine.fromSaleLine(Map line) {
    final qty = _int(line['qty']);
    final refunded = _int(line['refundedQty']).clamp(0, qty);
    return RefundableLine(
      saleLineId: line['id']?.toString() ?? '',
      name: _str(line['nameSnapshot']) ?? '',
      variant: _str(line['variant']),
      productId: _str(line['productId']),
      qty: qty,
      lineNetTzs: line['lineNetTzs'] is num
          ? _int(line['lineNetTzs'])
          : _int(line['lineTotalTzs']),
      refundedQty: refunded,
      refundedTzs: _int(line['refundedTzs']),
      vatTzs: _int(line['vatTzs']),
    );
  }

  final String saleLineId;
  final String name;
  final String? variant;
  final String? productId;

  /// Sold quantity (Q).
  final int qty;

  /// What the customer paid for the line (M-1).
  final int lineNetTzs;

  /// Units and amount already given back by ACTIVE refunds (a, A).
  final int refundedQty;
  final int refundedTzs;

  /// The line's VAT (inside the price).
  final int vatTzs;

  int get refundableQty => max(0, qty - refundedQty);
  String get displayName => variant == null ? name : '$name ($variant)';
}

/// The refundable lines of a sale map (lines without an id are left out:
/// they can never be named in a request).
List<RefundableLine> refundableLinesOf(Map? sale) => [
  for (final l in (sale?['lines'] as List? ?? []).whereType<Map>())
    if ((l['id']?.toString() ?? '').isNotEmpty) RefundableLine.fromSaleLine(l),
];

// ── money preview (M-2, M-3, M-4) ────────────────────────────────────────

/// What refunding [q] more units gives back when [a] units and [given] of
/// [total] were already given back by active refunds, out of [sold]
/// (spec §1 M-2; the server's `cumulativeShare`). Rounds down; the last
/// unit takes the rest; never below 0 or above what is left.
int cumulativeShare({
  required int total,
  required int sold,
  required int a,
  required int given,
  required int q,
}) {
  if (sold <= 0 || q <= 0) return 0;
  if (a + q == sold) return total - given;
  return max(0, min(total - given, (total * (a + q)) ~/ sold - given));
}

/// The preview of one refund.
class RefundPreview {
  const RefundPreview({
    required this.lineAmounts,
    required this.totalTzs,
    required this.vatTzs,
    required this.balanceReducedTzs,
    required this.paidOutTzs,
  });

  static const none = RefundPreview(
    lineAmounts: {},
    totalTzs: 0,
    vatTzs: 0,
    balanceReducedTzs: 0,
    paidOutTzs: 0,
  );

  /// Per sale line id: what its picked units give back.
  final Map<String, int> lineAmounts;
  final int totalTzs;

  /// VAT inside [totalTzs]. An estimate: the server keeps the VAT already
  /// given back per line, the sale view does not send it.
  final int vatTzs;

  /// Pay later: taken off what the customer still owes (no money moves).
  final int balanceReducedTzs;

  /// Money the vendor gives back.
  final int paidOutTzs;
}

/// The preview for [picks] (sale line id → units) on [lines]. A pay-later
/// sale ([credit]) takes the refund off [balanceTzs] first (M-4).
RefundPreview previewRefund(
  List<RefundableLine> lines,
  Map<String, int> picks, {
  bool credit = false,
  int balanceTzs = 0,
}) {
  final amounts = <String, int>{};
  var total = 0;
  var vat = 0;
  for (final l in lines) {
    final q = min(picks[l.saleLineId] ?? 0, l.refundableQty);
    if (q <= 0) continue;
    final amount = cumulativeShare(
      total: l.lineNetTzs,
      sold: l.qty,
      a: l.refundedQty,
      given: l.refundedTzs,
      q: q,
    );
    // VAT already given back is not in the sale view: estimated as what
    // the refunded units took when refunded in order (exact unless an
    // earlier refund was undone in the middle).
    final vatGiven = l.refundedQty >= l.qty
        ? l.vatTzs
        : (l.vatTzs * l.refundedQty) ~/ max(1, l.qty);
    final lineVat = cumulativeShare(
      total: l.vatTzs,
      sold: l.qty,
      a: l.refundedQty,
      given: vatGiven,
      q: q,
    );
    amounts[l.saleLineId] = amount;
    total += amount;
    vat += min(lineVat, amount);
  }
  final reduced = credit ? min(total, max(0, balanceTzs)) : 0;
  return RefundPreview(
    lineAmounts: amounts,
    totalTzs: total,
    vatTzs: vat,
    balanceReducedTzs: reduced,
    paidOutTzs: total - reduced,
  );
}

// ── the draft (what the refund screen has picked) ────────────────────────

/// What stops Review, first missing thing first (§4.2).
enum RefundProblem { selectSome, reasonMissing, referenceRequired }

/// The i18n key for a [RefundProblem].
String refundProblemKey(RefundProblem p) => switch (p) {
  RefundProblem.selectSome => 'vendor.refunds.selectSome',
  RefundProblem.reasonMissing => 'vendor.refunds.reasonMissing',
  RefundProblem.referenceRequired => 'vendor.pos.referenceRequired',
};

/// Picked quantities, restock flags, reason and method for one refund, and
/// its idempotency key once Confirm was first tapped (spec §0.4).
class RefundDraftController extends ChangeNotifier {
  RefundDraftController({
    required List<RefundableLine> lines,
    this.credit = false,
    this.balanceTzs = 0,
    String? defaultMethod,
  }) : _lines = List.unmodifiable(lines),
       method = salePaymentMethods.contains(defaultMethod)
           ? defaultMethod!
           : 'cash';

  List<RefundableLine> _lines;
  List<RefundableLine> get lines => _lines;
  final bool credit;
  int balanceTzs;

  final Map<String, int> _qty = {};
  final Map<String, bool> _restock = {};
  String reason = '';
  String method;
  String reference = '';

  /// The server asked for a method although the preview gives nothing back
  /// (the balance changed since): the method section shows anyway.
  bool methodForced = false;

  /// Set at the first Confirm; reused on every Try again of the same
  /// refund. Any change to what is refunded drops it.
  String? clientRef;

  int qtyOf(String saleLineId) => _qty[saleLineId] ?? 0;
  bool restockOf(String saleLineId) => _restock[saleLineId] ?? true;

  bool get hasPicks => _qty.values.any((q) => q > 0);
  int get pickedUnits => _qty.values.fold(0, (s, q) => s + q);

  RefundableLine? lineOf(String saleLineId) {
    for (final l in _lines) {
      if (l.saleLineId == saleLineId) return l;
    }
    return null;
  }

  void _changed() {
    clientRef = null;
    notifyListeners();
  }

  /// Sets a line's units, kept within 0..refundable.
  void setQty(String saleLineId, int qty) {
    final line = lineOf(saleLineId);
    if (line == null) return;
    final next = qty.clamp(0, min(line.refundableQty, maxQtyPerLine)).toInt();
    if (next == qtyOf(saleLineId)) return;
    if (next == 0) {
      _qty.remove(saleLineId);
    } else {
      _qty[saleLineId] = next;
    }
    _changed();
  }

  void increment(String saleLineId) =>
      setQty(saleLineId, qtyOf(saleLineId) + 1);
  void decrement(String saleLineId) =>
      setQty(saleLineId, qtyOf(saleLineId) - 1);

  /// "Refund everything left": every line to its refundable quantity.
  void refundAll() {
    for (final l in _lines) {
      final q = min(l.refundableQty, maxQtyPerLine);
      if (q > 0) _qty[l.saleLineId] = q;
    }
    _changed();
  }

  void setRestock(String saleLineId, bool value) {
    if (restockOf(saleLineId) == value) return;
    _restock[saleLineId] = value;
    _changed();
  }

  void setReason(String value) {
    if (value == reason) return;
    reason = value;
    _changed();
  }

  void setMethod(String value) {
    if (!salePaymentMethods.contains(value) || value == method) return;
    method = value;
    if (value == 'cash') reference = '';
    _changed();
  }

  void setReference(String value) {
    if (value == reference) return;
    reference = value;
    _changed();
  }

  /// Fresh counters from the server (after 409 refund_exceeds_sold): the
  /// picks are clamped to what is still refundable. Returns the ids whose
  /// pick went down.
  Set<String> replaceLines(List<RefundableLine> lines, {int? balanceTzs}) {
    _lines = List.unmodifiable(lines);
    if (balanceTzs != null) this.balanceTzs = balanceTzs;
    final lowered = <String>{};
    for (final id in _qty.keys.toList()) {
      final line = lineOf(id);
      final cap = line?.refundableQty ?? 0;
      if (_qty[id]! > cap) {
        lowered.add(id);
        if (cap <= 0) {
          _qty.remove(id);
        } else {
          _qty[id] = cap;
        }
      }
    }
    _changed();
    return lowered;
  }

  RefundPreview get preview =>
      previewRefund(_lines, _qty, credit: credit, balanceTzs: balanceTzs);

  /// A method is asked only when money is given back (M-6).
  bool get needsMethod => preview.paidOutTzs > 0 || methodForced;

  bool get referenceRequired =>
      needsMethod && referenceRequiredMethods.contains(method);

  String get _reason => reason.trim();

  /// The first thing stopping Review, or null.
  RefundProblem? get problem {
    if (!hasPicks) return RefundProblem.selectSome;
    if (_reason.length < refundReasonMin) return RefundProblem.reasonMissing;
    if (referenceRequired && reference.trim().isEmpty) {
      return RefundProblem.referenceRequired;
    }
    return null;
  }

  bool get canReview => problem == null && _reason.length <= refundReasonMax;

  /// Fixes the key (once) and returns the request body. No amounts, ever.
  Map<String, dynamic> requestBody({String Function()? makeClientRef}) {
    clientRef ??= (makeClientRef ?? newRefundClientRef)();
    final ref = reference.trim();
    return {
      'clientRef': clientRef,
      'lines': [
        for (final l in _lines)
          if (qtyOf(l.saleLineId) > 0)
            {
              'saleLineId': l.saleLineId,
              'qty': qtyOf(l.saleLineId),
              'restock': restockOf(l.saleLineId),
            },
      ],
      'reason': _reason,
      if (needsMethod) 'method': method,
      if (needsMethod && method != 'cash' && ref.isNotEmpty) 'reference': ref,
    };
  }
}

/// The method a refund pays back with by default: the sale's first
/// payment method, cash when it had none (M-6).
String defaultRefundMethod(Map? sale) {
  final pays = (sale?['payments'] as List? ?? []).whereType<Map>();
  final first = pays.isEmpty ? null : pays.first['method']?.toString();
  return salePaymentMethods.contains(first) ? first! : 'cash';
}

// ── a refund as the server sends it ──────────────────────────────────────

class RefundLineRecord {
  const RefundLineRecord({
    required this.saleLineId,
    this.productId,
    required this.name,
    this.variant,
    required this.qty,
    required this.amountTzs,
    this.vatCode,
    required this.restock,
  });
  final String saleLineId;
  final String? productId;
  final String name;
  final String? variant;
  final int qty;
  final int amountTzs;
  final String? vatCode;
  final bool restock;

  String get displayName => variant == null ? name : '$name ($variant)';
}

/// One refund (`refund` of POST …/refunds, …/revert and GET /vendor/refunds/:id).
class RefundRecord {
  const RefundRecord({
    required this.id,
    required this.number,
    required this.status,
    this.saleId,
    this.saleNumber,
    this.saleInvoiceNumber,
    this.saleKind = 'cash',
    this.refundedAt,
    this.createdById,
    this.createdByName,
    this.reason,
    this.method,
    this.reference,
    this.amountTzs = 0,
    this.balanceReducedTzs = 0,
    this.paidOutTzs = 0,
    this.vatTzs = 0,
    this.vatSummary = const [],
    this.customerId,
    this.customerName,
    this.customerForgotten = false,
    this.lines = const [],
    this.revertedByName,
    this.revertedAt,
    this.revertReason,
  });

  factory RefundRecord.fromJson(Map json) {
    Map? person(Object? v) => v is Map ? v : null;
    final customer = person(json['customer']);
    return RefundRecord(
      id: json['id']?.toString() ?? '',
      number: _str(json['number']) ?? '',
      status: json['status']?.toString() == 'reverted' ? 'reverted' : 'active',
      saleId: _str(json['saleId']),
      saleNumber: _str(json['saleNumber']),
      saleInvoiceNumber: _str(json['saleInvoiceNumber']),
      saleKind: json['saleKind']?.toString() == 'credit' ? 'credit' : 'cash',
      refundedAt: _str(json['refundedAt']),
      createdById: _str(person(json['createdBy'])?['id']),
      createdByName: _str(person(json['createdBy'])?['name']),
      reason: _str(json['reason']),
      method: _str(json['method']),
      reference: _str(json['reference']),
      amountTzs: _int(json['amountTzs']),
      balanceReducedTzs: _int(json['balanceReducedTzs']),
      paidOutTzs: _int(json['paidOutTzs']),
      vatTzs: _int(json['vatTzs']),
      vatSummary: vatRowsOf(json['vatSummary']),
      customerId: _str(customer?['id']),
      customerName: _str(customer?['name']),
      customerForgotten: customer?['forgotten'] == true,
      lines: [
        for (final l in (json['lines'] as List? ?? []).whereType<Map>())
          RefundLineRecord(
            saleLineId: l['saleLineId']?.toString() ?? '',
            productId: _str(l['productId']),
            name: _str(l['nameSnapshot']) ?? '',
            variant: _str(l['variant']),
            qty: _int(l['qty']),
            amountTzs: _int(l['amountTzs']),
            vatCode: _str(l['vatCode']),
            restock: l['restock'] == true,
          ),
      ],
      revertedByName: _str(person(json['revertedBy'])?['name']),
      revertedAt: _str(json['revertedAt']),
      revertReason: _str(json['revertReason']),
    );
  }

  final String id;
  final String number;

  /// active | reverted (undone).
  final String status;
  final String? saleId;
  final String? saleNumber;
  final String? saleInvoiceNumber;
  final String saleKind;
  final String? refundedAt;
  final String? createdById;
  final String? createdByName;
  final String? reason;
  final String? method;
  final String? reference;
  final int amountTzs;
  final int balanceReducedTzs;
  final int paidOutTzs;
  final int vatTzs;
  final List<DocVatRow> vatSummary;
  final String? customerId;
  final String? customerName;
  final bool customerForgotten;
  final List<RefundLineRecord> lines;
  final String? revertedByName;
  final String? revertedAt;
  final String? revertReason;

  bool get reverted => status == 'reverted';
  bool get credit => saleKind == 'credit';
  bool get anyRestocked => lines.any((l) => l.restock);
  bool get hasVat => vatTzs > 0 || vatSummary.isNotEmpty;

  /// The name of the line that holds [productId] (+ [variant]), for the
  /// undo's insufficient_stock message.
  String? nameOfProduct(String? productId, String? variant) {
    for (final l in lines) {
      if (l.productId == productId &&
          (variant == null || variant.isEmpty || l.variant == variant)) {
        return l.displayName;
      }
    }
    return null;
  }
}

/// One refund in a sale's `refunds` list (oldest first).
class SaleRefundRow {
  const SaleRefundRow({
    required this.id,
    required this.number,
    required this.status,
    this.refundedAt,
    required this.amountTzs,
  });
  final String id;
  final String number;
  final String status;
  final String? refundedAt;
  final int amountTzs;

  bool get reverted => status == 'reverted';
}

List<SaleRefundRow> saleRefundRowsOf(Object? raw) => [
  for (final r in (raw is List ? raw : const []).whereType<Map>())
    if ((r['id']?.toString() ?? '').isNotEmpty)
      SaleRefundRow(
        id: r['id'].toString(),
        number: _str(r['number']) ?? '',
        status: r['status']?.toString() == 'reverted' ? 'reverted' : 'active',
        refundedAt: _str(r['refundedAt']),
        amountTzs: _int(r['amountTzs']),
      ),
];

// ── who may refund or undo (mirrors the server's M2 rule, Q-1) ───────────

/// Why the Refund items button is not offered for a sale that otherwise
/// could be refunded.
enum RefundBlock {
  /// May refund.
  none,

  /// Staff without `sales`: no refund UI at all.
  noAccess,

  /// Staff who are not admin: another person's sale, or not today's.
  askOwner,
}

bool _vendorSide(Map<String, dynamic>? user, String permission) {
  final type = user?['userType']?.toString();
  if (type == 'vendor') return true;
  if (type != 'vendor_staff') return false;
  return (user?['vendorPermissions'] as List? ?? []).contains(permission);
}

bool _anyRecord(Map<String, dynamic>? user) =>
    user?['userType']?.toString() == 'vendor' ||
    user?['vendorRole']?.toString() == 'admin';

/// Whether [user] may refund the sale recorded by [servedById] at
/// [soldAt]: the vendor account and admin staff any sale; other `sales`
/// staff only their own, on its EAT sale day. The server enforces it (403
/// refund_not_allowed); the app hides the button where it would be refused.
RefundBlock refundBlockFor(
  Map<String, dynamic>? user, {
  required String? servedById,
  required String? soldAt,
  DateTime? now,
}) {
  if (!_vendorSide(user, 'sales')) return RefundBlock.noAccess;
  if (_anyRecord(user)) return RefundBlock.none;
  final own = servedById != null && servedById == user?['id']?.toString();
  return own && eatDayOf(soldAt) == _eatToday(now)
      ? RefundBlock.none
      : RefundBlock.askOwner;
}

/// Whether [user] may undo [refund]: the same rule applied to the refund
/// (own refund, on the EAT day it was made).
bool canRevertRefund(
  Map<String, dynamic>? user,
  RefundRecord refund, {
  DateTime? now,
}) {
  if (refund.reverted) return false;
  if (!_vendorSide(user, 'sales')) return false;
  if (_anyRecord(user)) return true;
  final own =
      refund.createdById != null &&
      refund.createdById == user?['id']?.toString();
  return own && eatDayOf(refund.refundedAt) == _eatToday(now);
}

DateTime _eatToday(DateTime? now) {
  final eat = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 3));
  return DateTime.utc(eat.year, eat.month, eat.day);
}

// ── error words (§8.5: never the raw code) ───────────────────────────────

/// The i18n key for a refund or undo refusal.
String refundErrorKey(String? code) => switch (code) {
  'refund_exceeds_sold' => 'vendor.refunds.err.exceeds',
  'sale_voided' => 'vendor.refunds.err.saleVoided',
  'restock_unavailable' => 'vendor.refunds.err.restockUnavailable',
  'insufficient_stock' => 'vendor.refunds.err.revertStock',
  'already_reverted' => 'vendor.refunds.err.alreadyReverted',
  'customer_archived' => 'vendor.refunds.err.customerArchived',
  'refund_not_allowed' || 'revert_not_allowed' => 'vendor.refunds.askOwner',
  'reference_required' => 'vendor.pos.referenceRequired',
  'feature_disabled' => 'vendor.refunds.unavailable',
  'refund_not_found' => 'vendor.refunds.notFound',
  'vendor_suspended' => 'vendor.sales.suspended',
  // 429 (refunds share the sales limit; undo too): nothing changed.
  'rate_limited' => 'vendor.refunds.err.rateLimited',
  _ => 'vendor.refunds.err.server',
};

// ── the credit note as text (§6.4) ───────────────────────────────────────

/// WhatsApp on a phone shows about 32 characters a line (S3 rule).
const _width = 32;

String _row(String label, String amount) {
  final gap = _width - label.length - amount.length;
  if (gap >= 1) return '$label${' ' * gap}$amount';
  final pad = _width - amount.length;
  return '$label\n${' ' * (pad < 0 ? 0 : pad)}$amount';
}

/// The credit note as plain text, in the language [t] answers in. [method]
/// gives a payment method's words in that language.
String creditNoteShareText(
  RefundRecord r, {
  required String Function(String key) t,
  required String lang,
  required String Function(String? method) method,
  String? business,
}) {
  String fill(String key, Map<String, Object?> v) {
    var out = t(key);
    v.forEach((k, val) => out = out.replaceAll('{$k}', '$val'));
    return out;
  }

  const rule = '--------------------';
  final b = StringBuffer();
  if (business != null) b.writeln(business);
  b.writeln('${t('vendor.doc.credit_note')} ${r.number}');
  b.writeln(
    r.credit && r.saleInvoiceNumber != null
        ? fill('vendor.doc.forInvoice', {'number': r.saleInvoiceNumber})
        : fill('vendor.doc.forReceipt', {'number': r.saleNumber ?? ''}),
  );
  final when = eatDateTime(r.refundedAt, locale: lang);
  if (when.isNotEmpty) b.writeln(when);
  b.writeln(rule);
  for (final l in r.lines) {
    b.writeln('${l.qty} x ${l.displayName}');
    b.writeln(_row('', formatMoney(l.amountTzs)));
  }
  b.writeln(rule);
  b.writeln(_row(t('vendor.doc.refundTotal'), formatCurrency(r.amountTzs)));
  if (r.balanceReducedTzs > 0) {
    b.writeln(
      _row(
        t('vendor.refunds.offBalanceShort'),
        formatMoney(r.balanceReducedTzs),
      ),
    );
  }
  if (r.paidOutTzs > 0) {
    final m = method(r.method);
    b.writeln(
      _row(
        fill('vendor.refunds.paidBackBy', {
          'method': r.reference == null ? m : '$m (${r.reference})',
        }),
        formatMoney(r.paidOutTzs),
      ),
    );
  } else if (r.balanceReducedTzs == 0) {
    b.writeln(t('vendor.doc.nothingPaidBack'));
  }
  b.writeln(rule);
  if (business != null) {
    b.writeln(fill('vendor.doc.refundGivenBy', {'business': business}));
  }
  b.write(t('vendor.pos.notFiscal'));
  return b.toString();
}
