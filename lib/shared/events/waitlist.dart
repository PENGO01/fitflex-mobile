// Events S7 (docs/design/events-s7-hardening-and-pilot.md §4): the wire
// shapes of the waitlist and the one loader the Mine tab and the standalone
// page share. Field names are the server's. Everything tolerates a missing
// key; the server owns every time and every position.
import 'package:flutter/foundation.dart';

import '../api_client.dart';
import '../api_error_message.dart';
import '../i18n.dart';
import 'event_summary.dart';
import 'events_cache.dart';

String _str(Object? v) => v?.toString() ?? '';

int _int(Object? v, [int fallback = 0]) => v is num
    ? v.toInt()
    : (v is String ? int.tryParse(v) ?? fallback : fallback);

String? _opt(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// `EventWaitlistEntry.status` (spec §4.3).
enum WaitlistStatus {
  waiting,
  offered,
  converted,
  expired,
  declined,
  left,
  removed,
  closed,
  other;

  static WaitlistStatus parse(Object? v) => switch (v?.toString()) {
    'waiting' => waiting,
    'offered' => offered,
    'converted' => converted,
    'expired' => expired,
    'declined' => declined,
    'left' => left,
    'removed' => removed,
    'closed' => closed,
    _ => other,
  };

  /// `events.waitlist.status.<wire>`; unknown statuses read as closed.
  String get wire => this == other ? 'closed' : name;

  /// Still in the line (the member can leave).
  bool get live => this == waiting || this == offered;
}

/// The open offer of an `offered` entry: the held order and its deadline.
class WaitlistOffer {
  const WaitlistOffer({
    required this.orderId,
    this.expiresAt,
    this.amountTzs = 0,
    this.currency = 'TZS',
  });

  final String orderId;
  final DateTime? expiresAt;
  final int amountTzs;
  final String currency;

  static WaitlistOffer? fromJson(Object? json) {
    if (json is! Map) return null;
    final orderId = _str(json['orderId']);
    if (orderId.isEmpty) return null;
    return WaitlistOffer(
      orderId: orderId,
      expiresAt: parseInstant(json['expiresAt']),
      amountTzs: _int(json['amountTzs']),
      currency: _opt(json['currency']) ?? 'TZS',
    );
  }
}

/// One row of `GET /me/event-waitlist`, or the `entry` a join answers with.
class WaitlistEntry {
  const WaitlistEntry({
    required this.id,
    this.eventId = '',
    this.eventTitle = '',
    this.startsAt,
    this.timezone = '',
    this.utcOffsetMinutes,
    this.timezoneAbbr = '',
    this.ticketTypeId = '',
    this.ticketTypeName = '',
    this.categoryName = '',
    this.status = WaitlistStatus.other,
    this.position,
    this.joinedAt,
    this.blockedReason,
    this.offer,
    this.endedAt,
    this.endedReason,
    this.priceTzs = 0,
    this.currency = 'TZS',
  });

  final String id;
  final String eventId;
  final String eventTitle;
  final DateTime? startsAt;
  final String timezone;

  /// Optional additive fields: when the server sends them the deadline is
  /// read on exactly that clock.
  final int? utcOffsetMinutes;
  final String timezoneAbbr;
  final String ticketTypeId;
  final String ticketTypeName;
  final String categoryName;
  final WaitlistStatus status;

  /// Only for `waiting`; the queue length is never sent.
  final int? position;
  final DateTime? joinedAt;

  /// `reconsent`: the terms changed, the member must confirm to stay.
  final String? blockedReason;
  final WaitlistOffer? offer;
  final DateTime? endedAt;
  final String? endedReason;
  final int priceTzs;
  final String currency;

  bool get needsReconsent =>
      status == WaitlistStatus.waiting && blockedReason == 'reconsent';

  static WaitlistEntry fromJson(Map json) {
    final event = json['event'] is Map ? json['event'] as Map : const {};
    return WaitlistEntry(
      id: _str(json['id']),
      eventId: _str(json['eventId'] ?? event['id']),
      eventTitle: _str(json['eventTitle'] ?? event['title']),
      startsAt: parseInstant(json['startsAt']),
      timezone: _str(json['timezone']),
      utcOffsetMinutes: json['utcOffsetMinutes'] is num
          ? (json['utcOffsetMinutes'] as num).toInt()
          : null,
      timezoneAbbr: _str(json['timezoneAbbr']),
      ticketTypeId: _str(json['ticketTypeId']),
      ticketTypeName: _str(json['ticketTypeName']),
      categoryName: _str(json['categoryName']),
      status: WaitlistStatus.parse(json['status']),
      position: json['position'] is num
          ? (json['position'] as num).toInt()
          : null,
      joinedAt: parseInstant(json['joinedAt']),
      blockedReason: _opt(json['blockedReason']),
      offer: WaitlistOffer.fromJson(json['offer']),
      endedAt: parseInstant(json['endedAt']),
      endedReason: _opt(json['endedReason']),
      priceTzs: _int(json['priceTzs']),
      currency: _opt(json['currency']) ?? 'TZS',
    );
  }
}

/// `GET /me/event-waitlist`.
class WaitlistPage {
  const WaitlistPage({this.items = const [], this.serverTime});

  final List<WaitlistEntry> items;

  /// The offer clock starts from here, never from the phone's clock.
  final DateTime? serverTime;

  static WaitlistPage fromJson(Map<String, dynamic> json) => WaitlistPage(
    items: [
      for (final e in json['items'] is List ? json['items'] as List : const [])
        if (e is Map) WaitlistEntry.fromJson(e),
    ],
    serverTime: parseInstant(json['serverTime']),
  );
}

/// The `POST /me/event-waitlist` body (spec §4.9): the ticket, the member's
/// own details as the checkout takes them, and the consent given.
Map<String, dynamic> waitlistJoinBody({
  required String ticketTypeId,
  required Map<String, dynamic> participant,
  required String consentTextVersion,
  String? locale,
}) => {
  'ticketTypeId': ticketTypeId,
  'participants': [participant],
  'consent': {'accepted': true, 'textVersion': consentTextVersion},
  'locale': ?locale,
};

/// The words for a refused join or leave (spec §10.2). Anything not in the
/// waitlist set falls back to the events wording.
String waitlistErrorMessage(FFLocale locale, Object error) {
  if (error is ApiException) {
    final key = switch (error.code) {
      'not_sold_out' => 'events.waitlist.error.not_sold_out',
      'already_registered' => 'events.waitlist.error.already_registered',
      'waitlist_full' => 'events.waitlist.error.full',
      'waitlist_lapse_limit' => 'events.waitlist.error.lapse_limit',
      'waitlist_limit_reached' => 'events.waitlist.error.limit',
      'verification_required' => 'events.waitlist.error.verification',
      'waitlist_unavailable' => 'events.waitlist.error.unavailable',
      'payment_pending' => 'events.waitlist.error.payment_pending',
      'rate_limited' => 'events.waitlist.error.rate',
      'feature_disabled' => 'events.waitlist.error.unavailable',
      _ => null,
    };
    if (key != null) return locale.t(key);
  }
  return eventsErrorMessage(locale, error);
}

/// Loads the member's waitlist, keeps the last good copy for offline (24 h
/// like the other Mine lists), and leaves or reconfirms an entry. One
/// instance per screen.
class WaitlistController extends ChangeNotifier {
  WaitlistController({required this.api});

  final ApiClient api;

  static const cacheKind = 'waitlist';

  WaitlistPage page = const WaitlistPage();
  bool loading = false;
  bool loaded = false;
  Object? error;

  /// Set when the shown copy is the saved one (no connection).
  DateTime? cachedAt;
  bool _disposed = false;

  bool get offline => cachedAt != null;
  bool get hasLive => page.items.any((e) => e.status.live);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _tell() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = page.items.isEmpty;
    error = null;
    _tell();
    try {
      final json = await api.listEventWaitlist();
      page = WaitlistPage.fromJson(json);
      cachedAt = null;
      loaded = true;
      loading = false;
      EventsCache.putMine(cacheKind, json);
    } catch (e) {
      if (isNetworkError(e)) {
        final saved = await EventsCache.getFreshMine(cacheKind);
        if (saved != null) {
          page = WaitlistPage.fromJson(saved.$2);
          cachedAt = saved.$1;
          loaded = true;
          loading = false;
          _tell();
          return;
        }
      }
      error = e;
      loading = false;
    }
    _tell();
  }

  /// Leaves the line. Throws the server's refusal (`payment_pending`,
  /// `already_ended`); the caller shows the words.
  Future<void> leave(String id) async {
    await api.leaveEventWaitlist(id);
    await load();
  }

  /// Confirms the changed terms so the entry stays in the line.
  Future<void> reconfirm(String id, {required String textVersion}) async {
    await api.reconfirmEventWaitlist(id, textVersion: textVersion);
    await load();
  }
}
