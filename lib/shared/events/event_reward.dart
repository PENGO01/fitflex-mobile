// Events S6 (docs/design/events-s6-runs-results-medals-rewards.md §7.4, §8.3):
// rewards, the wallet and the ledger. There is no points currency (D44): a
// ledger entry counts one entitlement of one reward, and the app never adds
// units of different rewards together or shows a balance number.
import 'event_detail.dart' show EventText;

String _str(Object? v) => v?.toString() ?? '';

String? _opt(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

int? _int(Object? v) => v is num
    ? v.toInt()
    : v is String
    ? int.tryParse(v)
    : null;

DateTime? _date(Object? v) => DateTime.tryParse(_str(v))?.toUtc();

/// `rewardsEarned` of a result: a reward this result earned.
class RewardEntitlement {
  const RewardEntitlement({
    this.definitionId = '',
    this.title = const EventText(),
    this.units = 1,
  });

  final String definitionId;
  final EventText title;
  final int units;

  static RewardEntitlement? fromJson(Object? json) {
    if (json is! Map) return null;
    return RewardEntitlement(
      definitionId: _str(json['definitionId'] ?? json['id']),
      title: EventText.fromJson(json['title'] ?? json['titleOf']),
      units: _int(json['units']) ?? 1,
    );
  }

  static List<RewardEntitlement> listFrom(Object? json) => json is List
      ? [for (final r in json) ?RewardEntitlement.fromJson(r)]
      : const [];
}

/// One reward the member can claim (`available` of the wallet).
class RewardAvailable {
  const RewardAvailable({
    required this.definitionId,
    this.title = const EventText(),
    this.terms = const EventText(),
    this.units = 0,
    this.nextExpiry,
    this.redeemMode = 'certificate',
    this.canClaim = true,
  });

  final String definitionId;
  final EventText title;
  final EventText terms;
  final int units;
  final DateTime? nextExpiry;

  /// `certificate` | `perk`.
  final String redeemMode;
  final bool canClaim;

  bool get isPerk => redeemMode == 'perk';

  static RewardAvailable? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _str(json['definitionId'] ?? json['id']);
    if (id.isEmpty) return null;
    return RewardAvailable(
      definitionId: id,
      title: EventText.fromJson(json['title']),
      terms: EventText.fromJson(json['terms']),
      units: _int(json['units']) ?? 0,
      nextExpiry: _date(json['nextExpiry'] ?? json['expiredAt']),
      redeemMode: _opt(json['redeemMode']) ?? 'certificate',
      canClaim: json['canClaim'] != false,
    );
  }
}

/// A claimed reward (`redemptions` of the wallet). `status` is `reserved` |
/// `redeemed` | `cancelled` | `expired`.
class RewardRedemptionView {
  const RewardRedemptionView({
    required this.id,
    this.definitionId = '',
    this.title = const EventText(),
    this.redeemMode = 'certificate',
    this.status = 'redeemed',
    this.code,
    this.expiresAt,
    this.redeemedAt,
    this.eventTitle,
    this.resultLine,
  });

  final String id;
  final String definitionId;
  final EventText title;
  final String redeemMode;
  final String status;

  /// Present for a `perk` while it is `reserved`.
  final String? code;
  final DateTime? expiresAt;
  final DateTime? redeemedAt;

  /// For the certificate card (tolerated; shown when sent).
  final String? eventTitle;
  final String? resultLine;

  bool get isReserved => status == 'reserved';
  bool get isCertificate => redeemMode == 'certificate';

  static RewardRedemptionView? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _str(json['id']);
    if (id.isEmpty) return null;
    final cert = json['certificate'] is Map ? json['certificate'] as Map : null;
    return RewardRedemptionView(
      id: id,
      definitionId: _str(json['definitionId']),
      title: EventText.fromJson(json['title']),
      redeemMode: _opt(json['redeemMode']) ?? 'certificate',
      status: _opt(json['status']) ?? 'redeemed',
      code: _opt(json['code']),
      expiresAt: _date(json['expiresAt']),
      redeemedAt: _date(json['redeemedAt']),
      eventTitle: _opt(json['eventTitle'] ?? cert?['eventTitle']),
      resultLine: _opt(json['resultLine'] ?? cert?['resultLine']),
    );
  }
}

/// `GET /me/event-rewards`.
class RewardWallet {
  const RewardWallet({
    this.available = const [],
    this.redemptions = const [],
    this.expired = const [],
  });

  final List<RewardAvailable> available;
  final List<RewardRedemptionView> redemptions;
  final List<RewardAvailable> expired;

  bool get isEmpty =>
      available.isEmpty && redemptions.isEmpty && expired.isEmpty;

  static RewardWallet fromJson(Object? json) {
    if (json is! Map) return const RewardWallet();
    List<T> list<T>(Object? v, T? Function(Object?) f) =>
        v is List ? [for (final e in v) ?f(e)] : <T>[];
    return RewardWallet(
      available: list(json['available'], RewardAvailable.fromJson),
      redemptions: list(json['redemptions'], RewardRedemptionView.fromJson),
      expired: list(json['expired'], RewardAvailable.fromJson),
    );
  }
}

/// One ledger line in plain words: `entryType` is `earn` | `redeem` |
/// `expire` | `reverse`. Units are +1 / -1 and are never summed.
class RewardLedgerLine {
  const RewardLedgerLine({
    required this.id,
    this.entryType = 'earn',
    this.title = const EventText(),
    this.occurredAt,
  });

  final String id;
  final String entryType;
  final EventText title;
  final DateTime? occurredAt;

  static RewardLedgerLine? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _str(json['id']);
    if (id.isEmpty) return null;
    return RewardLedgerLine(
      id: id,
      entryType: _opt(json['entryType']) ?? 'earn',
      title: EventText.fromJson(json['titleOf'] ?? json['title']),
      occurredAt: _date(json['occurredAt']),
    );
  }
}

class RewardLedgerPage {
  const RewardLedgerPage({this.items = const [], this.nextCursor});

  final List<RewardLedgerLine> items;
  final String? nextCursor;

  static RewardLedgerPage fromJson(Object? json) {
    if (json is! Map) return const RewardLedgerPage();
    return RewardLedgerPage(
      items: json['items'] is List
          ? [
              for (final e in json['items'] as List)
                ?RewardLedgerLine.fromJson(e),
            ]
          : const [],
      nextCursor: _opt(json['nextCursor']),
    );
  }
}
