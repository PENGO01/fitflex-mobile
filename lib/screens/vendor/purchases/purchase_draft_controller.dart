// Vendor tools · S9: the Receive stock form as data (spec §4.2, §4.9) —
// lines, supplier, details, payment choice and plan; the checks that keep
// Review disabled; the request (never a total: the server computes them);
// and the local draft (shared_preferences, debounced 500 ms, cleared on
// success, Discard and sign-out). A clientRef is made on the first Confirm
// and reused on Try again; it is never written to the device.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../shared/vendor_purchase_draft_store.dart';
import '../customers/customer_models.dart'
    show addDaysTo, eatTodayString, parseDay;
import '../sales/sale_models.dart' show referenceRequiredMethods;
import 'purchase_models.dart';

/// The last purchase cost of a product + variant (GET …/last-costs).
class LastCost {
  const LastCost({
    required this.unitCostTzs,
    this.receivedOn,
    this.supplierName,
    this.number,
  });
  final int unitCostTzs;
  final String? receivedOn;
  final String? supplierName;
  final String? number;
}

/// One line of the delivery.
class DraftLine {
  DraftLine({
    required this.productId,
    this.variant,
    required this.name,
    this.qty = 1,
    this.unitCostTzs,
    this.stockBefore,
    this.currentCostTzs,
    this.costKnown = false,
  });

  final String productId;

  /// Null for a product without tracked variants (or an untracked one).
  final String? variant;
  final String name;
  int qty;

  /// Null until typed (or prefilled).
  int? unitCostTzs;

  /// The count before this delivery (for "Stock 3 → 13"); null when unknown.
  int? stockBefore;

  /// The cost price now (the variant's own for a variant line), only for
  /// people who may see cost ([costKnown]).
  int? currentCostTzs;
  bool costKnown;

  /// The last purchase cost (the hint), when known.
  LastCost? last;

  /// A refusal from the server for this line (an i18n'd text).
  String? error;

  String get key => '$productId\u0000${variant ?? ''}';
  String get label => variant == null ? name : '$name ($variant)';
  bool get qtyOk => qty >= 1 && qty <= purchaseMaxQty;
  bool get costOk =>
      unitCostTzs != null &&
      unitCostTzs! >= 0 &&
      unitCostTzs! <= purchaseMaxUnitCost;
  bool get valid => qtyOk && costOk;
  int get totalTzs => valid ? qty * unitCostTzs! : 0;
  bool get free => unitCostTzs == 0;

  /// Whether the cost price will change (P-6). Unknown cost (no canSeeCost):
  /// "will be set" unless the unit cost is the last purchase cost.
  bool get costChanges {
    if (!costOk || free) return false;
    if (costKnown) return currentCostTzs != unitCostTzs;
    return last == null || last!.unitCostTzs != unitCostTzs;
  }

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'variant': variant,
    'name': name,
    'qty': qty,
    'unitCostTzs': unitCostTzs,
  };

  static DraftLine? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['productId']?.toString() ?? '';
    if (id.isEmpty) return null;
    return DraftLine(
      productId: id,
      variant: strOf(raw['variant']),
      name: raw['name']?.toString() ?? '',
      qty: intOfP(raw['qty']).clamp(1, purchaseMaxQty),
      unitCostTzs: raw['unitCostTzs'] is num
          ? (raw['unitCostTzs'] as num).toInt()
          : null,
    );
  }
}

/// Paid in full · Paid part · Not paid yet.
enum PayMode { full, part, none }

class PurchaseDraftController extends ChangeNotifier {
  PurchaseDraftController({
    this.storageKey,
    this.now,
    this.debounce = const Duration(milliseconds: 500),
  });

  final String? storageKey;
  final DateTime Function()? now;
  final Duration debounce;

  String get today => eatTodayString(now?.call());

  // supplier
  Map<String, dynamic>? supplier;
  bool noSupplier = false;

  final List<DraftLine> lines = [];

  // details
  String? receivedOn; // null = today
  String invoiceRef = '';
  String note = '';

  // payment
  PayMode? _payMode;
  String method = 'cash';
  String reference = '';
  int? paidNowTzs; // part only
  String? dueDate; // null = received + 30
  bool split = false;
  List<PlanRow> schedule = [];
  int splitCount = 2;
  String? firstDue;
  PlanEvery every = PlanEvery.month;

  /// Made on the first Confirm, reused on Try again (same delivery). Never
  /// stored.
  String? clientRef;

  DateTime? savedAt;
  bool _dirty = false;
  Timer? _timer;

  bool get hasContent =>
      lines.isNotEmpty ||
      supplier != null ||
      invoiceRef.trim().isNotEmpty ||
      note.trim().isNotEmpty;

  /// The day the stock is said to be received.
  String get receivedDay => receivedOn ?? today;

  // ── payment ──────────────────────────────────────────────────────────

  /// Default: Paid in full without a supplier, else Not paid yet.
  PayMode get payMode =>
      _payMode ?? (supplier == null ? PayMode.full : PayMode.none);
  set payMode(PayMode m) {
    _payMode = m;
    changed();
  }

  int get totalTzs => lines.fold(0, (s, l) => s + l.totalTzs);
  int get units => lines.fold(0, (s, l) => s + (l.qtyOk ? l.qty : 0));

  int get paidNow => switch (payMode) {
    PayMode.full => totalTzs,
    PayMode.part => paidNowTzs ?? 0,
    PayMode.none => 0,
  };

  int get leftTzs => totalTzs - paidNow;

  bool get paysNow => payMode != PayMode.none && paidNow > 0;
  bool get needsReference =>
      paysNow && referenceRequiredMethods.contains(method);
  bool get referenceMissing => needsReference && reference.trim().isEmpty;

  /// Paid part: 1 … total − 1.
  bool get partAmountOk =>
      payMode != PayMode.part ||
      (paidNowTzs != null && paidNowTzs! >= 1 && paidNowTzs! < totalTzs);

  String get defaultDue => addDaysTo(receivedDay, purchaseDefaultDueDays);
  String get payBy => dueDate ?? defaultDue;

  int get scheduledTzs => schedule.fold(0, (s, r) => s + r.amountTzs);

  bool get scheduleDatesOk {
    final latest = addDaysTo(receivedDay, purchaseDueMaxDays);
    return schedule.every(
      (r) =>
          parseDay(r.dueDate) != null &&
          r.dueDate.compareTo(receivedDay) >= 0 &&
          r.dueDate.compareTo(latest) <= 0 &&
          r.amountTzs >= 1,
    );
  }

  bool get scheduleAddsUp =>
      !split || leftTzs <= 0 || (scheduledTzs == leftTzs && scheduleDatesOk);

  bool get supplierOk => supplier != null || leftTzs <= 0;

  /// Why Review is disabled: the first missing thing, an i18n key; null
  /// when the delivery may be reviewed.
  String? get problem {
    if (lines.isEmpty) return 'vendor.purchases.needItem';
    if (lines.any((l) => !l.valid || l.error != null)) {
      return 'vendor.purchases.needLineFix';
    }
    if (totalTzs > purchaseMaxTotal) return 'vendor.purchases.needLineFix';
    if (!partAmountOk) return 'vendor.purchases.needPaidNow';
    if (!supplierOk) return 'vendor.purchases.needSupplier';
    if (referenceMissing) return 'vendor.pos.referenceRequired';
    if (!scheduleAddsUp) return 'vendor.purchases.sumWrong';
    return null;
  }

  bool get canReview => problem == null;

  /// The even split from the editor's count, first date and frequency.
  void splitEvenly() {
    final first = firstDue ?? defaultDue;
    schedule = scheduleFor(totalTzs, paidNow, splitCount, first, every: every);
    changed();
  }

  void startSplit() {
    split = true;
    firstDue ??= defaultDue;
    if (schedule.isEmpty) {
      schedule = scheduleFor(
        totalTzs,
        paidNow,
        splitCount,
        firstDue!,
        every: every,
      );
    }
    changed();
  }

  void stopSplit() {
    split = false;
    changed();
  }

  // ── lines ────────────────────────────────────────────────────────────

  DraftLine? lineOf(String productId, String? variant) {
    for (final l in lines) {
      if (l.productId == productId && l.variant == variant) return l;
    }
    return null;
  }

  /// Adds a line, or (the same product + variant) answers the existing one:
  /// one line per product + variant (duplicate_line never happens).
  DraftLine add(DraftLine line) {
    final existing = lineOf(line.productId, line.variant);
    if (existing != null) return existing;
    lines.add(line);
    changed();
    return line;
  }

  void remove(DraftLine line) {
    lines.remove(line);
    changed();
  }

  void setQty(DraftLine line, int qty) {
    line.qty = qty;
    line.error = null;
    changed();
  }

  void setCost(DraftLine line, int? cost) {
    line.unitCostTzs = cost;
    line.error = null;
    changed();
  }

  // ── request ──────────────────────────────────────────────────────────

  /// The POST /vendor/purchases body. Totals are never sent.
  Map<String, dynamic> toRequest(String clientRef) {
    final body = <String, dynamic>{
      'clientRef': clientRef,
      'supplierId': ?supplier?['id']?.toString(),
      if (receivedOn != null && receivedOn != today) 'receivedOn': receivedOn,
      if (invoiceRef.trim().isNotEmpty) 'supplierInvoiceRef': invoiceRef.trim(),
      if (note.trim().isNotEmpty) 'note': note.trim(),
      'lines': [
        for (final l in lines)
          {
            'productId': l.productId,
            'variant': ?l.variant,
            'qty': l.qty,
            'unitCostTzs': l.unitCostTzs ?? 0,
          },
      ],
    };
    if (paysNow) {
      body['paidNow'] = {
        'amountTzs': paidNow,
        'method': method,
        if (method != 'cash' && reference.trim().isNotEmpty)
          'reference': reference.trim(),
      };
    }
    if (leftTzs > 0) {
      if (split && schedule.isNotEmpty) {
        body['schedule'] = [for (final r in schedule) r.toJson()];
      } else {
        body['dueDate'] = payBy;
      }
    }
    return body;
  }

  // ── the local draft ──────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'savedAt': (savedAt ?? DateTime.now()).toUtc().toIso8601String(),
    if (supplier != null)
      'supplier': {
        'id': supplier!['id'],
        'name': supplier!['name'],
        'phone': supplier!['phone'],
      },
    'lines': [for (final l in lines) l.toJson()],
    'receivedOn': receivedOn,
    'invoiceRef': invoiceRef,
    'note': note,
    'payMode': _payMode?.name,
    'method': method,
    'reference': reference,
    'paidNowTzs': paidNowTzs,
    'dueDate': dueDate,
    'split': split,
    'schedule': [for (final r in schedule) r.toJson()],
    'splitCount': splitCount,
    'firstDue': firstDue,
    'every': every.name,
  };

  /// Puts a kept draft back (Continue). Lines come back without their
  /// stock and cost hints; the screen asks for them again.
  void restore(Map<String, dynamic> d) {
    supplier = d['supplier'] is Map
        ? Map<String, dynamic>.from(d['supplier'] as Map)
        : null;
    lines
      ..clear()
      ..addAll(
        [
          for (final raw in (d['lines'] as List? ?? const []))
            DraftLine.fromJson(raw),
        ].whereType<DraftLine>(),
      );
    final r = d['receivedOn']?.toString();
    receivedOn = parseDay(r) == null ? null : r;
    invoiceRef = d['invoiceRef']?.toString() ?? '';
    note = d['note']?.toString() ?? '';
    _payMode = PayMode.values.where((m) => m.name == d['payMode']).firstOrNull;
    method = d['method']?.toString() ?? 'cash';
    reference = d['reference']?.toString() ?? '';
    paidNowTzs = d['paidNowTzs'] is num
        ? (d['paidNowTzs'] as num).toInt()
        : null;
    final due = d['dueDate']?.toString();
    dueDate = parseDay(due) == null ? null : due;
    split = d['split'] == true;
    schedule = [
      for (final raw in (d['schedule'] as List? ?? const []))
        PlanRow.fromJson(raw),
    ].whereType<PlanRow>().toList();
    splitCount = intOfP(d['splitCount']).clamp(2, purchaseMaxInstalments);
    final first = d['firstDue']?.toString();
    firstDue = parseDay(first) == null ? null : first;
    every = d['every'] == 'twoWeeks' ? PlanEvery.twoWeeks : PlanEvery.month;
    clientRef = null;
    savedAt = DateTime.tryParse(d['savedAt']?.toString() ?? '');
    notifyListeners();
  }

  /// When a kept draft was saved (for "unfinished delivery from {time}").
  static DateTime? savedAtOf(Map<String, dynamic> d) =>
      DateTime.tryParse(d['savedAt']?.toString() ?? '');

  /// Something changed: redraw, and keep the draft (debounced).
  void changed() {
    // A different delivery: a new clientRef on the next Confirm.
    clientRef = null;
    _dirty = true;
    notifyListeners();
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(saveNow()));
  }

  /// Writes the draft now (also on leaving with Keep draft).
  Future<void> saveNow() async {
    _timer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    if (!hasContent) {
      await VendorPurchaseDraftStore.clear(storageKey);
      return;
    }
    savedAt = DateTime.now();
    await VendorPurchaseDraftStore.save(storageKey, toJson());
    // The screen may have closed meanwhile (the save still lands).
    if (!_disposed) notifyListeners();
  }

  /// Success or Discard: the kept draft goes.
  Future<void> discard() async {
    _timer?.cancel();
    _dirty = false;
    await VendorPurchaseDraftStore.clear(storageKey);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
