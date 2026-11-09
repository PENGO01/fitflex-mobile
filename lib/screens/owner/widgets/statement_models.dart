// Gym statements as the owner sees them (GET /owner/settlements).
// Pure Dart (no Flutter imports) so parsing is unit-testable.

import '../../../shared/ff_datetime.dart';

class OwnerStatement {
  const OwnerStatement({
    required this.id,
    this.gymId,
    this.gymName,
    this.periodStart,
    this.status = 'preparing',
    this.onHold = false,
    this.members = 0,
    this.visits = 0,
    this.earnedTzs = 0,
    this.networkAdjustmentTzs = 0,
    this.adjustmentsTzs = 0,
    this.carriedForwardTzs = 0,
    this.payableTzs = 0,
    this.paidAt,
    this.paymentReference,
    this.payoutAccountLast4,
  });

  final String id;
  final String? gymId;
  final String? gymName;

  /// First day of the statement's month, "YYYY-MM-DD" in East Africa Time.
  final String? periodStart;

  /// preparing | in_review | approved | payment_due | paid
  final String status;
  final bool onHold;
  final int members;
  final int visits;
  final num earnedTzs;
  final num networkAdjustmentTzs;
  final num adjustmentsTzs;
  final num carriedForwardTzs;
  final num payableTzs;
  final DateTime? paidAt;
  final String? paymentReference;
  final String? payoutAccountLast4;

  factory OwnerStatement.fromJson(Map<String, dynamic> json) => OwnerStatement(
    id: json['id'] as String? ?? '',
    gymId: json['gymId'] as String?,
    gymName: json['gymName'] as String?,
    periodStart: json['periodStartDate'] as String?,
    status: json['status'] as String? ?? 'preparing',
    onHold: json['onHold'] == true,
    members: (json['members'] as num?)?.toInt() ?? 0,
    visits: (json['visits'] as num?)?.toInt() ?? 0,
    earnedTzs: json['earnedTzs'] as num? ?? 0,
    networkAdjustmentTzs: json['networkAdjustmentTzs'] as num? ?? 0,
    adjustmentsTzs: json['adjustmentsTzs'] as num? ?? 0,
    carriedForwardTzs: json['carriedForwardTzs'] as num? ?? 0,
    payableTzs: json['payableTzs'] as num? ?? 0,
    paidAt: DateTime.tryParse(json['paidAt'] as String? ?? ''),
    paymentReference: json['paymentReference'] as String?,
    payoutAccountLast4: json['payoutAccountLast4'] as String?,
  );

  bool get isPaid => status == 'paid';

  /// e.g. "October 2026" — falls back to the id when undated.
  String get monthLabel {
    final parts = (periodStart ?? '').split('-');
    final year = parts.length >= 2 ? int.tryParse(parts[0]) : null;
    final month = parts.length >= 2 ? int.tryParse(parts[1]) : null;
    if (year == null || month == null || month < 1 || month > 12) return id;
    return monthAndYear(year, month);
  }
}

class OwnerStatementLine {
  const OwnerStatementLine({
    this.memberCode,
    this.sponsored = false,
    this.visits = 0,
    this.visitDates = const [],
    this.bracket,
    this.earnedTzs = 0,
    this.networkAdjustmentTzs = 0,
    this.finalTzs = 0,
  });

  final String? memberCode;
  final bool sponsored;
  final int visits;
  final List<String> visitDates;
  final String? bracket;
  final num earnedTzs;
  final num networkAdjustmentTzs;
  final num finalTzs;

  factory OwnerStatementLine.fromJson(Map<String, dynamic> json) =>
      OwnerStatementLine(
        memberCode: json['memberCode'] as String?,
        sponsored: json['funding'] == 'sponsored',
        visits: (json['visits'] as num?)?.toInt() ?? 0,
        visitDates: (json['visitDates'] as List? ?? const [])
            .whereType<String>()
            .toList(),
        bracket: json['bracket'] as String?,
        earnedTzs: json['earnedTzs'] as num? ?? 0,
        networkAdjustmentTzs: json['networkAdjustmentTzs'] as num? ?? 0,
        finalTzs: json['finalTzs'] as num? ?? 0,
      );
}

class OwnerStatementAdjustment {
  const OwnerStatementAdjustment({
    this.amountTzs = 0,
    this.type = 'manual',
    this.reason = '',
  });

  final num amountTzs;
  final String type;
  final String reason;

  factory OwnerStatementAdjustment.fromJson(Map<String, dynamic> json) =>
      OwnerStatementAdjustment(
        amountTzs: json['amountTzs'] as num? ?? 0,
        type: json['type'] as String? ?? 'manual',
        reason: json['reason'] as String? ?? '',
      );
}

class OwnerStatementDetail {
  const OwnerStatementDetail({
    required this.statement,
    this.lines = const [],
    this.adjustments = const [],
  });

  final OwnerStatement statement;
  final List<OwnerStatementLine> lines;
  final List<OwnerStatementAdjustment> adjustments;

  factory OwnerStatementDetail.fromJson(Map<String, dynamic> json) =>
      OwnerStatementDetail(
        statement: OwnerStatement.fromJson(
          (json['statement'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        lines: (json['lines'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OwnerStatementLine.fromJson)
            .toList(),
        adjustments: (json['adjustments'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OwnerStatementAdjustment.fromJson)
            .toList(),
      );
}

/// "3 Oct" from "2026-10-03" (already an East Africa Time day).
String statementDay(String date) {
  final parts = date.split('-');
  if (parts.length < 3) return date;
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2].substring(0, parts[2].length.clamp(0, 2)));
  if (month == null || day == null || month < 1 || month > 12) return date;
  return '$day ${shortMonthName(month)}';
}
