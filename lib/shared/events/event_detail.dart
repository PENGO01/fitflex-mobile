import 'event_summary.dart';

/// A line the server sends in both languages (`{en, sw}`).
class EventText {
  const EventText({this.en = '', this.sw = ''});

  final String en;
  final String sw;

  bool get isEmpty => en.trim().isEmpty && sw.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// The text for [lang]: Swahili when asked for and provided, else English.
  String of(String lang) => lang == 'sw' && sw.trim().isNotEmpty ? sw : en;

  /// Swahili was asked for but the organizer gave none (the English shows).
  bool missingFor(String lang) =>
      lang == 'sw' && sw.trim().isEmpty && en.trim().isNotEmpty;

  static EventText fromJson(Object? json) {
    if (json is Map) {
      return EventText(
        en: json['en']?.toString() ?? '',
        sw: json['sw']?.toString() ?? '',
      );
    }
    if (json is String) return EventText(en: json);
    return const EventText();
  }
}

class EventTicketType {
  const EventTicketType({
    required this.id,
    required this.name,
    this.priceTzs = 0,
    this.currency = 'TZS',
    this.saleOpensAt,
    this.saleClosesAt,
    this.minPerOrder = 1,
    this.maxPerOrder = 10,
    this.availability = EventAvailability.closed,
  });

  final String id;
  final String name;
  final int priceTzs;
  final String currency;
  final DateTime? saleOpensAt;
  final DateTime? saleClosesAt;
  final int minPerOrder;
  final int maxPerOrder;
  final EventAvailability availability;

  bool get isFree => priceTzs == 0;

  static EventTicketType fromJson(Map json) => EventTicketType(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    priceTzs: json['priceTzs'] is num ? (json['priceTzs'] as num).toInt() : 0,
    currency: (json['currency']?.toString() ?? '').isEmpty
        ? 'TZS'
        : json['currency'].toString(),
    saleOpensAt: parseInstant(json['saleOpensAt']),
    saleClosesAt: parseInstant(json['saleClosesAt']),
    minPerOrder: json['minPerOrder'] is num
        ? (json['minPerOrder'] as num).toInt()
        : 1,
    maxPerOrder: json['maxPerOrder'] is num
        ? (json['maxPerOrder'] as num).toInt()
        : 10,
    availability: EventAvailability.parse(json['availability']),
  );
}

class EventCategory {
  const EventCategory({
    required this.id,
    required this.name,
    this.distanceM = 0,
    this.startsAt,
    this.capacity,
    this.availability = EventAvailability.closed,
    this.remaining,
    this.eligibility = const EventText(),
    this.minAge,
    this.ticketTypes = const [],
  });

  final String id;
  final String name;
  final int distanceM;
  final DateTime? startsAt;
  final int? capacity;
  final EventAvailability availability;

  /// Null unless the server says 10 or fewer are left.
  final int? remaining;
  final EventText eligibility;
  final int? minAge;
  final List<EventTicketType> ticketTypes;

  static EventCategory fromJson(Map json) => EventCategory(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    distanceM: json['distanceM'] is num
        ? (json['distanceM'] as num).toInt()
        : 0,
    startsAt: parseInstant(json['startsAt']),
    capacity: json['capacity'] is num
        ? (json['capacity'] as num).toInt()
        : null,
    availability: EventAvailability.parse(json['availability']),
    remaining: json['remaining'] is num
        ? (json['remaining'] as num).toInt()
        : null,
    eligibility: EventText.fromJson(json['eligibility']),
    minAge: json['minAge'] is num ? (json['minAge'] as num).toInt() : null,
    ticketTypes: json['ticketTypes'] is List
        ? [
            for (final t in json['ticketTypes'] as List)
              if (t is Map) EventTicketType.fromJson(t),
          ]
        : const [],
  );
}

class EventWindow {
  const EventWindow({this.opensAt, this.closesAt});
  final DateTime? opensAt;
  final DateTime? closesAt;

  static EventWindow fromJson(Map json) => EventWindow(
    opensAt: parseInstant(json['opensAt']),
    closesAt: parseInstant(json['closesAt']),
  );
}

class EventCollectionPoint {
  const EventCollectionPoint({
    required this.id,
    required this.name,
    this.address = '',
    this.lat,
    this.lng,
    this.windows = const [],
    this.instructions = const EventText(),
  });

  final String id;
  final String name;
  final String address;
  final double? lat;
  final double? lng;
  final List<EventWindow> windows;
  final EventText instructions;

  bool get hasCoordinates => lat != null && lng != null;

  static EventCollectionPoint fromJson(Map json) => EventCollectionPoint(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    address: json['address']?.toString() ?? '',
    lat: json['lat'] is num ? (json['lat'] as num).toDouble() : null,
    lng: json['lng'] is num ? (json['lng'] as num).toDouble() : null,
    windows: json['windows'] is List
        ? [
            for (final w in json['windows'] as List)
              if (w is Map) EventWindow.fromJson(w),
          ]
        : const [],
    instructions: EventText.fromJson(json['instructions']),
  );
}

class EventScheduleItem {
  const EventScheduleItem({this.at, this.label = const EventText()});
  final DateTime? at;
  final EventText label;

  static EventScheduleItem fromJson(Map json) => EventScheduleItem(
    at: parseInstant(json['at']),
    label: EventText.fromJson(json['label']),
  );
}

class EventSponsor {
  const EventSponsor({required this.name, this.logoUrl, this.url});
  final String name;
  final String? logoUrl;
  final String? url;

  static EventSponsor fromJson(Map json) => EventSponsor(
    name: json['name']?.toString() ?? '',
    logoUrl: _blankToNull(json['logoUrl']),
    url: _blankToNull(json['url']),
  );
}

class EventContact {
  const EventContact({this.email, this.phone, this.whatsapp});
  final String? email;
  final String? phone;
  final String? whatsapp;

  bool get isEmpty => email == null && phone == null && whatsapp == null;

  static EventContact fromJson(Object? json) {
    if (json is! Map) return const EventContact();
    return EventContact(
      email: _blankToNull(json['email']),
      phone: _blankToNull(json['phone']),
      whatsapp: _blankToNull(json['whatsapp']),
    );
  }
}

class EventRefundTier {
  const EventRefundTier({this.daysBefore = 0, this.percent = 0});
  final int daysBefore;
  final int percent;
}

class EventRefundPolicy {
  const EventRefundPolicy({
    this.preset = '',
    this.text = const EventText(),
    this.generated = const EventText(),
    this.days,
    this.tiers = const [],
  });

  /// `no_refund`, `refund_until_close`, `full_until_days`, `tiered` or
  /// `custom` (events S4 spec §3.12.1).
  final String preset;

  /// The organizer's own words (the whole policy for `custom`).
  final EventText text;

  /// The plain line the server writes from the structured fields. It is the
  /// single source for the policy line shown before purchase and in the
  /// cancel screens (the app never builds one itself).
  final EventText generated;

  /// `full_until_days`: days before the start.
  final int? days;

  /// `tiered`: up to three `{daysBefore, percent}` steps.
  final List<EventRefundTier> tiers;

  /// The server's line in [lang], or empty.
  String generatedLine(String lang) => generated.of(lang).trim();

  static EventRefundPolicy fromJson(Object? json) {
    if (json is! Map) return const EventRefundPolicy();
    return EventRefundPolicy(
      preset: json['preset']?.toString() ?? '',
      text: EventText.fromJson(json['text']),
      generated: EventText.fromJson(json['generated']),
      days: json['days'] is num ? (json['days'] as num).toInt() : null,
      tiers: json['tiers'] is List
          ? [
              for (final t in json['tiers'] as List)
                if (t is Map)
                  EventRefundTier(
                    daysBefore: t['daysBefore'] is num
                        ? (t['daysBefore'] as num).toInt()
                        : 0,
                    percent: t['percent'] is num
                        ? (t['percent'] as num).toInt()
                        : 0,
                  ),
            ]
          : const [],
    );
  }
}

class EventCancellation {
  const EventCancellation({this.reason = '', this.note = const EventText()});
  final String reason;
  final EventText note;

  static EventCancellation? fromJson(Object? json) {
    if (json is! Map) return null;
    return EventCancellation(
      reason: json['reason']?.toString() ?? '',
      note: EventText.fromJson(json['note']),
    );
  }
}

/// `GET /events/:id` (spec §14.2): the summary plus everything the detail
/// page shows.
class EventDetail {
  const EventDetail({
    required this.summary,
    this.description = const EventText(),
    this.heroImageUrl,
    this.coverAlt,
    this.routeUrl,
    this.routeImageUrl,
    this.routeImageAlt,
    this.accessibility = const EventText(),
    this.inclusions = const EventText(),
    this.categories = const [],
    this.collectionPoints = const [],
    this.schedule = const [],
    this.sponsors = const [],
    this.contact = const EventContact(),
    this.terms = const EventText(),
    this.refundPolicy = const EventRefundPolicy(),
    this.cancellation,
    this.shareUrl,
    this.publishedAt,
    this.version,
    this.resultsStage = 'none',
  });

  final EventSummary summary;
  final EventText description;
  final String? heroImageUrl;
  final String? coverAlt;
  final String? routeUrl;
  final String? routeImageUrl;
  final String? routeImageAlt;
  final EventText accessibility;
  final EventText inclusions;
  final List<EventCategory> categories;
  final List<EventCollectionPoint> collectionPoints;
  final List<EventScheduleItem> schedule;
  final List<EventSponsor> sponsors;
  final EventContact contact;
  final EventText terms;
  final EventRefundPolicy refundPolicy;
  final EventCancellation? cancellation;

  /// Built by the server; the client never assembles one.
  final String? shareUrl;
  final DateTime? publishedAt;
  final int? version;

  /// Events S6 (spec §8.3): `results.stage` of the event, `none` |
  /// `provisional` | `official`. The "Results" button shows when it is not
  /// `none` and the server has the public board on.
  final String resultsStage;

  bool get hasPublishedResults =>
      resultsStage == 'provisional' || resultsStage == 'official';

  String get id => summary.id;
  String get title => summary.title;
  EventAvailability get availability => summary.availability;

  EventDetail copyWith({EventSummary? summary}) => EventDetail(
    summary: summary ?? this.summary,
    description: description,
    heroImageUrl: heroImageUrl,
    coverAlt: coverAlt,
    routeUrl: routeUrl,
    routeImageUrl: routeImageUrl,
    routeImageAlt: routeImageAlt,
    accessibility: accessibility,
    inclusions: inclusions,
    categories: categories,
    collectionPoints: collectionPoints,
    schedule: schedule,
    sponsors: sponsors,
    contact: contact,
    terms: terms,
    refundPolicy: refundPolicy,
    cancellation: cancellation,
    shareUrl: shareUrl,
    publishedAt: publishedAt,
    version: version,
    resultsStage: resultsStage,
  );

  static EventDetail fromJson(Map<String, dynamic> json) => EventDetail(
    summary: EventSummary.fromJson(json),
    description: EventText.fromJson(json['description']),
    heroImageUrl: _blankToNull(json['heroImageUrl']),
    coverAlt: _blankToNull(json['coverAlt']),
    routeUrl: _blankToNull(json['routeUrl']),
    routeImageUrl: _blankToNull(json['routeImageUrl']),
    routeImageAlt: _blankToNull(json['routeImageAlt']),
    accessibility: EventText.fromJson(json['accessibility']),
    inclusions: EventText.fromJson(json['inclusions']),
    categories: json['categories'] is List
        ? [
            for (final c in json['categories'] as List)
              if (c is Map) EventCategory.fromJson(c),
          ]
        : const [],
    collectionPoints: json['collectionPoints'] is List
        ? [
            for (final p in json['collectionPoints'] as List)
              if (p is Map) EventCollectionPoint.fromJson(p),
          ]
        : const [],
    schedule: json['schedule'] is List
        ? [
            for (final s in json['schedule'] as List)
              if (s is Map) EventScheduleItem.fromJson(s),
          ]
        : const [],
    sponsors: json['sponsors'] is List
        ? [
            for (final s in json['sponsors'] as List)
              if (s is Map) EventSponsor.fromJson(s),
          ]
        : const [],
    contact: EventContact.fromJson(json['contact']),
    terms: EventText.fromJson(json['terms']),
    refundPolicy: EventRefundPolicy.fromJson(json['refundPolicy']),
    cancellation: EventCancellation.fromJson(json['cancellation']),
    shareUrl: _blankToNull(json['shareUrl']),
    publishedAt: parseInstant(json['publishedAt']),
    version: json['version'] is num ? (json['version'] as num).toInt() : null,
    resultsStage: json['results'] is Map
        ? ((json['results'] as Map)['stage']?.toString() ?? 'none')
        : 'none',
  );
}

String? _blankToNull(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}
