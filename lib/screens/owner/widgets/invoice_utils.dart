// B1 — owner invoice model + month ordering helpers.
// Pure Dart (no Flutter imports) so the ordering rule is unit-testable:
// monthly summaries must run from the CURRENT month backwards.

import '../../../shared/ff_datetime.dart';

class OwnerInvoice {
  const OwnerInvoice({
    required this.id,
    this.gymId,
    this.gymName,
    this.amount = 0,
    this.status = 'unpaid',
    this.periodStart,
    this.periodEnd,
    this.createdAt,
  });

  final String id;
  final String? gymId;
  final String? gymName;
  final num amount;
  final String status;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? createdAt;

  factory OwnerInvoice.fromJson(Map<String, dynamic> json) => OwnerInvoice(
    id: json['id'] as String? ?? '',
    gymId: json['gymId'] as String?,
    gymName: json['gymName'] as String?,
    amount: json['amount'] as num? ?? 0,
    status: json['status'] as String? ?? 'unpaid',
    periodStart: _date(json['periodStart']),
    periodEnd: _date(json['periodEnd']),
    createdAt: _date(json['createdAt']),
  );

  static DateTime? _date(Object? v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

  /// Best date to represent the invoice month.
  DateTime? get monthAnchor => periodStart ?? createdAt;

  bool get isPaid => status == 'paid';

  /// e.g. "March 2026" — falls back to the invoice id when undated.
  String get monthLabel {
    final d = monthAnchor;
    if (d == null) return id;
    return monthAndYear(d.year, d.month);
  }
}

/// B1: sorts invoices so the CURRENT month comes first, then backwards in
/// time. Undated invoices sink to the end.
List<OwnerInvoice> sortInvoicesCurrentMonthBackwards(
  List<OwnerInvoice> invoices,
) {
  final sorted = [...invoices];
  sorted.sort((a, b) {
    final da = a.monthAnchor;
    final db = b.monthAnchor;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  });
  return sorted;
}
