// Events S6 (docs/design/events-s6-runs-results-medals-rewards.md §7, §8.3):
// medals and achievements as the server returns them. `art` only names the
// artwork; the picture itself is fetched with the member's sign-in (never a
// remote URL, spec §7.7) and falls back to the built-in design from `artKey`.
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

/// The built-in designs (spec §7.7), the default and the fallback.
const builtinMedalArtKeys = [
  'finisher_green',
  'finisher_gold',
  'podium_gold',
  'podium_silver',
  'podium_bronze',
  'time_blue',
  'charity_red',
  'virtual_teal',
];

/// `art` of a medal: `source` is `custom` or `builtin`.
class MedalArt {
  const MedalArt({
    this.source = 'builtin',
    this.artId,
    this.revision,
    this.artKey = 'finisher_green',
    this.altText = const EventText(),
  });

  final String source;
  final String? artId;
  final int? revision;
  final String artKey;
  final EventText altText;

  bool get isCustom => source == 'custom' && (artId ?? '').isNotEmpty;

  /// A key the app can draw; anything else draws the default.
  String get safeArtKey =>
      builtinMedalArtKeys.contains(artKey) ? artKey : 'finisher_green';

  static MedalArt fromJson(Object? json) {
    if (json is! Map) return const MedalArt();
    final alt = json['altText'];
    return MedalArt(
      source: _opt(json['source']) ?? 'builtin',
      artId: _opt(json['artId']),
      revision: _int(json['revision']),
      artKey: _opt(json['artKey']) ?? 'finisher_green',
      altText: alt == null ? const EventText() : EventText.fromJson(alt),
    );
  }
}

/// `MedalAward` of §8.3.
class MedalAward {
  const MedalAward({
    required this.id,
    this.eventId = '',
    this.eventTitle = '',
    this.organizerName,
    this.categoryName,
    this.templateId = '',
    this.tier = 'finisher',
    this.name = const EventText(),
    this.description = const EventText(),
    this.art = const MedalArt(),
    this.status = 'awarded',
    this.awardedAt,
    this.revokedAt,
    this.reasonCode,
    this.rank,
    this.elapsedMs,
  });

  final String id;
  final String eventId;
  final String eventTitle;

  /// "Design by {organizer}": the organizer's display name, never a person's.
  final String? organizerName;
  final String? categoryName;
  final String templateId;
  final String tier;
  final EventText name;
  final EventText description;
  final MedalArt art;
  final String status;
  final DateTime? awardedAt;
  final DateTime? revokedAt;
  final String? reasonCode;
  final int? rank;
  final int? elapsedMs;

  bool get isRevoked => status == 'revoked';

  static MedalAward? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _str(json['id']);
    if (id.isEmpty) return null;
    final summary = json['resultSummary'] is Map
        ? json['resultSummary'] as Map
        : const {};
    final organizer = json['organizer'];
    return MedalAward(
      id: id,
      eventId: _str(json['eventId']),
      eventTitle: _str(json['eventTitle']),
      organizerName:
          _opt(json['organizerName']) ??
          (organizer is Map ? _opt(organizer['name']) : _opt(organizer)),
      categoryName: _opt(json['categoryName']),
      templateId: _str(json['templateId']),
      tier: _opt(json['tier']) ?? 'finisher',
      name: EventText.fromJson(json['name']),
      description: EventText.fromJson(json['description']),
      art: MedalArt.fromJson(json['art']),
      status: _opt(json['status']) ?? 'awarded',
      awardedAt: _date(json['awardedAt']),
      revokedAt: _date(json['revokedAt']),
      reasonCode: _opt(json['reasonCode']),
      rank: _int(summary['rank']),
      elapsedMs: _int(summary['elapsedMs']),
    );
  }

  static List<MedalAward> listFrom(Object? json) =>
      json is List ? [for (final m in json) ?MedalAward.fromJson(m)] : const [];
}

/// One platform-wide achievement (`UserAchievementView`). Progress is only
/// sent for count-based ones that are not earned yet; the app never works it
/// out.
class AchievementView {
  const AchievementView({
    required this.key,
    this.title = const EventText(),
    this.earned = false,
    this.earnedAt,
    this.done,
    this.total,
  });

  final String key;
  final EventText title;
  final bool earned;
  final DateTime? earnedAt;
  final int? done;
  final int? total;

  bool get hasProgress =>
      !earned && done != null && total != null && total! > 0;

  static AchievementView? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = _opt(json['key']) ?? _opt(json['id']);
    if (key == null) return null;
    final progress = json['progress'] is Map ? json['progress'] as Map : null;
    final status = _opt(json['status']);
    return AchievementView(
      key: key,
      title: EventText.fromJson(json['title']),
      // The server sends `status: awarded|locked` and `progress {current,
      // target}`; `earned`, `done` and `total` are read as well if sent.
      earned:
          json['earned'] == true ||
          status == 'awarded' ||
          (status == null &&
              _date(json['awardedAt'] ?? json['earnedAt']) != null),
      earnedAt: _date(json['awardedAt'] ?? json['earnedAt']),
      done: _int(progress?['current'] ?? progress?['done'] ?? json['done']),
      total: _int(progress?['target'] ?? progress?['total'] ?? json['total']),
    );
  }
}

/// A removed medal or achievement with its plain reason.
class RemovedItem {
  const RemovedItem({
    this.kind = 'medal',
    this.id = '',
    this.title = const EventText(),
    this.reasonCode,
    this.revokedAt,
  });

  final String kind;
  final String id;
  final EventText title;
  final String? reasonCode;
  final DateTime? revokedAt;

  static RemovedItem? fromJson(Object? json) {
    if (json is! Map) return null;
    return RemovedItem(
      kind: _opt(json['kind']) ?? 'medal',
      id: _str(json['id']),
      title: EventText.fromJson(json['title']),
      reasonCode: _opt(json['reasonCode']),
      revokedAt: _date(json['revokedAt']),
    );
  }
}

/// `GET /me/achievements`.
class MedalsPayload {
  const MedalsPayload({
    this.medals = const [],
    this.achievements = const [],
    this.removed = const [],
  });

  final List<MedalAward> medals;
  final List<AchievementView> achievements;
  final List<RemovedItem> removed;

  /// Awarded medals first; revoked ones (from either list) go to "Removed".
  List<MedalAward> get awarded => [
    for (final m in medals)
      if (!m.isRevoked) m,
  ];

  List<MedalAward> get revokedMedals => [
    for (final m in medals)
      if (m.isRevoked) m,
  ];

  static MedalsPayload fromJson(Object? json) {
    if (json is! Map) return const MedalsPayload();
    return MedalsPayload(
      medals: MedalAward.listFrom(json['medals']),
      achievements: json['achievements'] is List
          ? [
              for (final a in json['achievements'] as List)
                ?AchievementView.fromJson(a),
            ]
          : const [],
      removed: json['removed'] is List
          ? [for (final r in json['removed'] as List) ?RemovedItem.fromJson(r)]
          : const [],
    );
  }
}
