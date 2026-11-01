// Events S6 (docs/design/events-s6-runs-results-medals-rewards.md §3, §5,
// §8.3): a participant's result, as the server returns it. Parsing is
// tolerant: an unknown word reads as the safest wording (stage `none`), a
// missing block as empty, and nothing here ever derives a stage or a rank on
// the device (the server owns both, §3.1).
import 'event_medal.dart';
import 'event_reward.dart';

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

/// What a participant sees about how official a result is (§3.1).
enum ResultStage {
  none,
  provisional,
  official,
  corrected,
  disputed,
  disqualified,
  rejected;

  /// Unknown words read as [none]: "not published", which promises nothing.
  static ResultStage parse(Object? v) => switch (_str(v).trim().toLowerCase()) {
    'provisional' => provisional,
    'official' => official,
    'corrected' => corrected,
    'disputed' || 'under_review' => disputed,
    'disqualified' || 'dq' => disqualified,
    'rejected' => rejected,
    _ => none,
  };

  /// The i18n key of the chip word.
  String get chipKey => switch (this) {
    none => 'events.result.stage.none',
    provisional => 'events.result.stage.provisional',
    official => 'events.result.stage.official',
    corrected => 'events.result.stage.corrected',
    disputed => 'events.result.stage.underReview',
    disqualified => 'events.result.stage.disqualified',
    rejected => 'events.result.stage.rejected',
  };

  /// The i18n key of the one-sentence "what this means" line.
  String get lineKey => switch (this) {
    none => 'events.result.line.none',
    provisional => 'events.result.line.provisional',
    official => 'events.result.line.official',
    corrected => 'events.result.line.corrected',
    disputed => 'events.result.line.underReview',
    disqualified => 'events.result.line.dq',
    rejected => 'events.result.line.rejected',
  };
}

/// One current result row (`result` of §8.3).
class EventResultRow {
  const EventResultRow({
    this.id = '',
    this.revision = 1,
    this.finishStatus = '',
    this.verificationStatus = '',
    this.sourceType = '',
    this.sourceLabel,
    this.netElapsedMs,
    this.gunElapsedMs,
    this.elapsedMs,
    this.overallRank,
    this.categoryRank,
    this.finishersInCategory,
    this.withinCutoff,
    this.verifiedAt,
    this.correctedAt,
    this.reasonCode,
    this.correctionNote,
    this.isPersonalBest = false,
    this.previousBestElapsedMs,
  });

  final String id;
  final int revision;

  /// `finished` | `dnf` | `dns` | `dq` (the server's words).
  final String finishStatus;
  final String verificationStatus;

  /// `timing_provider` | `organizer_verified` | `fitflex_gps` |
  /// `manual_unverified`.
  final String sourceType;
  final String? sourceLabel;
  final int? netElapsedMs;
  final int? gunElapsedMs;

  /// The ranking basis the organizer chose (net or gun).
  final int? elapsedMs;
  final int? overallRank;
  final int? categoryRank;
  final int? finishersInCategory;
  final bool? withinCutoff;
  final DateTime? verifiedAt;
  final DateTime? correctedAt;
  final String? reasonCode;
  final String? correctionNote;
  final bool isPersonalBest;
  final int? previousBestElapsedMs;

  bool get isDnf => finishStatus == 'dnf';
  bool get isDns => finishStatus == 'dns';
  bool get isDq => finishStatus == 'dq';
  bool get isGps => sourceType == 'fitflex_gps';

  /// The time to show: the ranking basis, else net, else gun. Null for
  /// DNF/DNS/DQ rows and when the server sent none.
  int? get shownMs {
    if (isDnf || isDns || isDq) return null;
    return elapsedMs ?? netElapsedMs ?? gunElapsedMs;
  }

  static EventResultRow? fromJson(Object? json) {
    if (json is! Map) return null;
    final pb = json['personalBest'];
    return EventResultRow(
      id: _str(json['id']),
      revision: _int(json['revision']) ?? 1,
      finishStatus: _str(json['finishStatus']),
      verificationStatus: _str(json['verificationStatus']),
      sourceType: _str(json['sourceType']),
      sourceLabel: _opt(json['sourceLabel']),
      netElapsedMs: _int(json['netElapsedMs']),
      gunElapsedMs: _int(json['gunElapsedMs']),
      elapsedMs: _int(json['elapsedMs']),
      overallRank: _int(json['overallRank']),
      categoryRank: _int(json['categoryRank']),
      finishersInCategory: _int(json['finishersInCategory']),
      withinCutoff: json['withinCutoff'] is bool
          ? json['withinCutoff'] as bool
          : null,
      verifiedAt: _date(json['verifiedAt']),
      correctedAt: _date(json['correctedAt']),
      reasonCode: _opt(json['reasonCode']),
      correctionNote: _opt(json['correctionNote']),
      isPersonalBest: pb is Map && pb['isPersonalBest'] == true,
      previousBestElapsedMs: pb is Map
          ? _int(pb['previousBestElapsedMs'])
          : null,
    );
  }
}

class ResultRelease {
  const ResultRelease({this.stage = ResultStage.none, this.releasedAt});

  final ResultStage stage;
  final DateTime? releasedAt;

  static ResultRelease fromJson(Object? json) => json is Map
      ? ResultRelease(
          stage: ResultStage.parse(json['stage']),
          releasedAt: _date(json['releasedAt']),
        )
      : const ResultRelease();
}

/// `dispute` of §8.3. `status` is `open` | `upheld` | `rejected` |
/// `withdrawn`.
class ResultDispute {
  const ResultDispute({
    this.id = '',
    this.status = '',
    this.createdAt,
    this.resolvedAt,
    this.resolutionNote,
    this.canRaise = false,
    this.windowEndsAt,
  });

  final String id;
  final String status;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final String? resolutionNote;

  /// The server decides whether a question can be asked now.
  final bool canRaise;
  final DateTime? windowEndsAt;

  bool get isOpen => status == 'open';
  bool get isClosed => id.isNotEmpty && !isOpen;

  /// A dispute block with nothing in it (no question asked and none allowed).
  bool get isEmpty => id.isEmpty && !canRaise && windowEndsAt == null;

  static ResultDispute? fromJson(Object? json) {
    if (json is! Map) return null;
    return ResultDispute(
      id: _str(json['id']),
      status: _str(json['status']),
      createdAt: _date(json['createdAt']),
      resolvedAt: _date(json['resolvedAt']),
      resolutionNote: _opt(json['resolutionNote']),
      canRaise: json['canRaise'] == true,
      windowEndsAt: _date(json['windowEndsAt']),
    );
  }
}

/// `visibility` of §8.3: who can see the participant's name on the board.
class ResultVisibility {
  const ResultVisibility({
    this.current = 'standard',
    this.canChange = true,
    this.allowed = const ['standard', 'bib_only', 'hidden'],
    this.reason,
  });

  /// `standard` | `bib_only` | `hidden`.
  final String current;
  final bool canChange;
  final List<String> allowed;

  /// `ask` (registered before the public-results clause: ask once) or
  /// `minor` (fixed, under 18) or null.
  final String? reason;

  bool get shouldAsk => reason == 'ask' && canChange;
  bool get isMinor => reason == 'minor';

  static ResultVisibility fromJson(Object? json) {
    if (json is! Map) return const ResultVisibility();
    final allowed = json['allowed'] is List
        ? [for (final a in json['allowed'] as List) a.toString()]
        : const ['standard', 'bib_only', 'hidden'];
    return ResultVisibility(
      current: _opt(json['current']) ?? 'standard',
      canChange: json['canChange'] != false,
      allowed: allowed,
      reason: _opt(json['reason']),
    );
  }
}

/// One FitFlex run tied to a registration (`runLinks` of §8.3).
class EventRunLink {
  const EventRunLink({
    this.id = '',
    this.linkType = 'evidence',
    this.matchStatus = '',
    this.distanceMeters,
    this.movingSeconds,
    this.elapsedMs,
    this.flags = const [],
    this.activityId,
    this.startedAt,
    this.canUnlink = true,
  });

  final String id;

  /// `evidence` (in-person) | `event_run` (virtual).
  final String linkType;
  final String matchStatus;
  final int? distanceMeters;
  final int? movingSeconds;
  final int? elapsedMs;
  final List<String> flags;
  final String? activityId;
  final DateTime? startedAt;
  final bool canUnlink;

  bool get isEventRun => linkType == 'event_run';
  bool get isPendingApproval => isEventRun && matchStatus != 'rejected';
  bool get isFast => flags.contains('implausible_pace');

  static EventRunLink fromJson(Map json) => EventRunLink(
    id: _str(json['id']),
    linkType: _opt(json['linkType']) ?? 'evidence',
    matchStatus: _str(json['matchStatus']),
    distanceMeters: _int(json['distanceMeters']),
    movingSeconds: _int(json['movingSeconds']),
    elapsedMs: _int(json['elapsedMs']),
    flags: json['flags'] is List
        ? [for (final f in json['flags'] as List) f.toString()]
        : const [],
    activityId: _opt(json['activityId']),
    startedAt: _date(json['startedAt']),
    canUnlink: json['canUnlink'] != false,
  );

  static List<EventRunLink> listFrom(Object? json) => json is List
      ? [
          for (final l in json)
            if (l is Map) EventRunLink.fromJson(l),
        ]
      : const [];
}

/// `GET /me/event-registrations/:id/result` (§8.3).
class MemberEventResult {
  const MemberEventResult({
    required this.registrationId,
    this.eventId = '',
    this.eventTitle = '',
    this.eventType = '',
    this.categoryId = '',
    this.categoryName = '',
    this.distanceMeters,
    this.bibNumber,
    this.stage = ResultStage.none,
    this.finishStatus,
    this.statusOnly = false,
    this.result,
    this.release = const ResultRelease(),
    this.dispute,
    this.visibility = const ResultVisibility(),
    this.runLinks = const [],
    this.medals = const [],
    this.rewardsEarned = const [],
    this.registrationStatus,
    this.eventCancelled = false,
    this.claimNeeded = false,
  });

  final String registrationId;
  final String eventId;
  final String eventTitle;
  final String eventType;
  final String categoryId;
  final String categoryName;
  final int? distanceMeters;
  final String? bibNumber;
  final ResultStage stage;

  /// Present in the purchaser's status-only view.
  final String? finishStatus;

  /// `viewer = purchaser_status_only`: only `stage` and `finishStatus` came.
  final bool statusOnly;
  final EventResultRow? result;
  final ResultRelease release;
  final ResultDispute? dispute;
  final ResultVisibility visibility;
  final List<EventRunLink> runLinks;
  final List<MedalAward> medals;
  final List<RewardEntitlement> rewardsEarned;

  /// `cancelled` | `refunded` when the place no longer stands (tolerated).
  final String? registrationStatus;
  final bool eventCancelled;

  /// The place is unclaimed: the claim prompt shows instead of a result.
  final bool claimNeeded;

  bool get isVirtual => eventType == 'virtual';
  bool get placeEnded =>
      registrationStatus == 'cancelled' || registrationStatus == 'refunded';

  EventRunLink? get liveEventRun {
    for (final l in runLinks) {
      if (l.isEventRun && l.matchStatus != 'rejected') return l;
    }
    return null;
  }

  static MemberEventResult fromJson(Map json, {String? registrationId}) {
    final viewer = _str(json['viewer']);
    return MemberEventResult(
      registrationId: _opt(json['registrationId']) ?? registrationId ?? '',
      eventId: _str(json['eventId']),
      eventTitle: _str(json['eventTitle']),
      eventType: _str(json['eventType']),
      categoryId: _str(json['categoryId']),
      categoryName: _str(json['categoryName']),
      distanceMeters: _int(json['distanceMeters']),
      bibNumber: _opt(json['bibNumber']),
      stage: ResultStage.parse(json['stage']),
      finishStatus: _opt(json['finishStatus']),
      statusOnly: viewer == 'purchaser_status_only',
      result: EventResultRow.fromJson(json['result']),
      release: ResultRelease.fromJson(json['release']),
      dispute: ResultDispute.fromJson(json['dispute']),
      visibility: ResultVisibility.fromJson(json['visibility']),
      runLinks: EventRunLink.listFrom(json['runLinks']),
      medals: MedalAward.listFrom(json['medals']),
      rewardsEarned: RewardEntitlement.listFrom(json['rewardsEarned']),
      registrationStatus: _opt(json['registrationStatus']),
      eventCancelled: json['eventCancelled'] == true,
      claimNeeded: json['claimNeeded'] == true,
    );
  }
}

/// One row of `GET /events/:eventId/results` (§8.3).
class ResultBoardRow {
  const ResultBoardRow({
    this.rank,
    this.bibNumber = '',
    this.displayName,
    this.elapsedMs,
    this.finishStatus = '',
    this.stage = ResultStage.official,
    this.badges = const [],
  });

  final int? rank;
  final String bibNumber;

  /// Already shaped by the person's visibility (null or empty: bib only).
  final String? displayName;
  final int? elapsedMs;
  final String finishStatus;
  final ResultStage stage;
  final List<String> badges;

  bool get corrected => badges.contains('corrected');
  bool get underReview => badges.contains('under_review');
  bool get hasTime =>
      elapsedMs != null &&
      finishStatus != 'dnf' &&
      finishStatus != 'dns' &&
      finishStatus != 'dq';

  static ResultBoardRow fromJson(Map json) => ResultBoardRow(
    rank: _int(json['rank']),
    bibNumber: _str(json['bibNumber']),
    displayName: _opt(json['displayName']),
    elapsedMs: _int(json['elapsedMs']),
    finishStatus: _str(json['finishStatus']),
    stage: ResultStage.parse(json['stage']),
    badges: json['badges'] is List
        ? [for (final b in json['badges'] as List) b.toString()]
        : const [],
  );
}

class ResultBoardCategory {
  const ResultBoardCategory({required this.id, required this.name, this.stage});

  final String id;
  final String name;
  final ResultStage? stage;

  static ResultBoardCategory? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _str(json['id']);
    if (id.isEmpty) return null;
    return ResultBoardCategory(
      id: id,
      name: _opt(json['name']) ?? id,
      stage: json['stage'] == null ? null : ResultStage.parse(json['stage']),
    );
  }
}

/// A page of the results board.
class ResultBoardPage {
  const ResultBoardPage({
    this.eventTitle = '',
    this.release = const ResultRelease(),
    this.categories = const [],
    this.items = const [],
    this.mineRank,
    this.mineBib,
    this.nextCursor,
  });

  final String eventTitle;
  final ResultRelease release;
  final List<ResultBoardCategory> categories;
  final List<ResultBoardRow> items;
  final int? mineRank;
  final String? mineBib;
  final String? nextCursor;

  bool get hasMine => (mineBib ?? '').isNotEmpty;

  static ResultBoardPage fromJson(Map json) {
    final event = json['event'] is Map ? json['event'] as Map : const {};
    final mine = json['mine'] is Map ? json['mine'] as Map : null;
    return ResultBoardPage(
      eventTitle: _str(event['title']),
      release: ResultRelease.fromJson(json['release']),
      categories: json['categories'] is List
          ? [
              for (final c in json['categories'] as List)
                ?ResultBoardCategory.fromJson(c),
            ]
          : const [],
      items: json['items'] is List
          ? [
              for (final i in json['items'] as List)
                if (i is Map) ResultBoardRow.fromJson(i),
            ]
          : const [],
      mineRank: mine == null ? null : _int(mine['rank']),
      mineBib: mine == null ? null : _opt(mine['bibNumber']),
      nextCursor: _opt(json['nextCursor']),
    );
  }
}

/// `1:52:08` from milliseconds (rounded down to the second).
String formatResultTime(int ms) {
  final total = ms < 0 ? 0 : ms ~/ 1000;
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// `(hours, minutes, seconds)` for a spoken label.
({int h, int m, int s}) resultTimeParts(int ms) {
  final total = ms < 0 ? 0 : ms ~/ 1000;
  return (h: total ~/ 3600, m: (total % 3600) ~/ 60, s: total % 60);
}
