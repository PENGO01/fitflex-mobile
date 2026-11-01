/// What the server switched on for events (`GET /events/options`, spec §13).
/// The endpoint is public and answers even while the server module is off
/// (`discovery: false`), so a 404 or a network error simply means "off".
class EventsRegion {
  const EventsRegion({required this.code, required this.nameEn, this.nameSw});

  final String code;
  final String nameEn;
  final String? nameSw;

  /// The region's name in [lang] (Swahili when given, else English).
  String name(String lang) =>
      lang == 'sw' && (nameSw ?? '').trim().isNotEmpty ? nameSw! : nameEn;

  static EventsRegion? fromJson(Object? json) {
    if (json is! Map) return null;
    final code = json['code']?.toString() ?? '';
    if (code.isEmpty) return null;
    final name = json['name'];
    if (name is Map) {
      return EventsRegion(
        code: code,
        nameEn: name['en']?.toString() ?? code,
        nameSw: name['sw']?.toString(),
      );
    }
    return EventsRegion(code: code, nameEn: name?.toString() ?? code);
  }
}

/// Which contact types the claim screen can verify in the app (events S3
/// spec §3.1 `claim`, copied by the server from `/auth/options`).
class EventsClaimOptions {
  const EventsClaimOptions({this.smsCodes = false, this.emailCodes = false});

  final bool smsCodes;
  final bool emailCodes;

  /// Whether a contact of [type] (`phone` | `email`) can be verified now.
  bool verifiable(String type) => type == 'phone' ? smsCodes : emailCodes;

  static EventsClaimOptions fromJson(Object? json) {
    if (json is! Map) return const EventsClaimOptions();
    return EventsClaimOptions(
      smsCodes: json['smsCodes'] == true,
      emailCodes: json['emailCodes'] == true,
    );
  }
}

/// Hold rules the server quotes (events S4 spec §3.1 `hold`). The app only
/// uses them for wording; the server owns every time.
class EventsHoldOptions {
  const EventsHoldOptions({
    this.manualExtendHours = 24,
    this.manualMaxHours = 48,
    this.providerExtendMinutes = 10,
    this.lateGraceHours = 24,
  });

  final int manualExtendHours;
  final int manualMaxHours;
  final int providerExtendMinutes;
  final int lateGraceHours;

  static EventsHoldOptions fromJson(Object? json) {
    if (json is! Map) return const EventsHoldOptions();
    int n(Object? v, int d) => v is num ? v.toInt() : d;
    return EventsHoldOptions(
      manualExtendHours: n(json['manualExtendHours'], 24),
      manualMaxHours: n(json['manualMaxHours'], 48),
      providerExtendMinutes: n(json['providerExtendMinutes'], 10),
      lateGraceHours: n(json['lateGraceHours'], 24),
    );
  }
}

/// `tickets` of the options (events S4 spec §3.1): whether tickets carry a
/// QR, and whether kit scanning is live (S5 flips it; the ticket page
/// wording depends on it).
class EventsTicketOptions {
  const EventsTicketOptions({this.qr = false, this.scanning = false});

  final bool qr;
  final bool scanning;

  static EventsTicketOptions fromJson(Object? json) {
    if (json is! Map) return const EventsTicketOptions();
    return EventsTicketOptions(
      qr: json['qr'] == true,
      scanning: json['scanning'] == true,
    );
  }
}

/// `results` of the options (events S6 spec §8.3): which parts of runs,
/// results, medals and rewards the server switched on. Every part is off
/// until the server says otherwise, so an older server changes nothing.
class EventsResultsOptions {
  const EventsResultsOptions({
    this.enabled = false,
    this.runs = false,
    this.public = false,
    this.rewards = false,
    this.medalArt = false,
  });

  /// `EVENTS_RESULTS`: the My result page.
  final bool enabled;

  /// `EVENTS_RUNS`: Start run for this event / Add a recorded run.
  final bool runs;

  /// `EVENTS_RESULTS_PUBLIC`: the signed-in results board.
  final bool public;

  /// `EVENTS_REWARDS`: medals, achievements and the rewards wallet.
  final bool rewards;

  /// `EVENTS_MEDAL_ART`: organizer artwork (the app still falls back to the
  /// built-in design whatever this says).
  final bool medalArt;

  bool get any => enabled || rewards;

  static EventsResultsOptions fromJson(Object? json) {
    if (json is! Map) return const EventsResultsOptions();
    return EventsResultsOptions(
      enabled: json['enabled'] == true,
      runs: json['runs'] == true,
      public: json['public'] == true,
      rewards: json['rewards'] == true,
      medalArt: json['medalArt'] == true,
    );
  }
}

/// `runs` of the options: the wording numbers only; the server checks.
class EventsRunsOptions {
  const EventsRunsOptions({this.toleranceBps = 200, this.maxDaysAfter = 7});

  final int toleranceBps;
  final int maxDaysAfter;

  static EventsRunsOptions fromJson(Object? json) {
    if (json is! Map) return const EventsRunsOptions();
    int n(Object? v, int d) => v is num ? v.toInt() : d;
    return EventsRunsOptions(
      toleranceBps: n(json['toleranceBps'], 200),
      maxDaysAfter: n(json['maxDaysAfter'], 7),
    );
  }
}

class EventsOptions {
  const EventsOptions({
    this.discovery = false,
    this.favourites = false,
    this.registration = false,
    this.currency = 'TZS',
    this.closingSoonHours = 72,
    this.regions = const [],
    this.timezones = const [],
    this.holdTtlMinutes = 30,
    this.maxParticipantsPerOrder = 10,
    this.payment = 'none',
    this.teams = false,
    this.corporate = false,
    this.claim = const EventsClaimOptions(),
    this.consentTextVersion = '',
    this.manualConfirmHours = 24,
    this.refundDays = 5,
    this.hold = const EventsHoldOptions(),
    this.tickets = const EventsTicketOptions(),
    this.results = const EventsResultsOptions(),
    this.runs = const EventsRunsOptions(),
  });

  /// Everything off: the probe failed or the module is off.
  static const off = EventsOptions();

  final bool discovery;
  final bool favourites;
  final bool registration;
  final String currency;
  final int closingSoonHours;
  final List<EventsRegion> regions;
  final List<String> timezones;

  // ── Registration (S3 spec §3.1); present only with `registration: true` ──

  /// How long an unpaid order holds its places.
  final int holdTtlMinutes;

  /// Most people in one member order (`EVENTS_MAX_PARTICIPANTS_PER_ORDER`).
  final int maxParticipantsPerOrder;

  /// `none` | `manual` | `provider` (S4 spec §3.1): the one way the server
  /// takes payment right now. `none` keeps the "payment isn't open yet"
  /// slot on the order page.
  final String payment;
  final bool teams;
  final bool corporate;
  final EventsClaimOptions claim;

  /// `EVENTS_CONSENT_TEXT_VERSION`; the quote carries the authoritative one.
  final String consentTextVersion;

  // ── Payments and tickets (S4 spec §3.1) ──

  /// The target hours the app quotes for a manual confirmation (a target,
  /// never a promise). Present when `payment` is `manual`.
  final int manualConfirmHours;

  /// Working days FitFlex quotes for sending a refund.
  final int refundDays;
  final EventsHoldOptions hold;
  final EventsTicketOptions tickets;

  // ── Runs, results, medals and rewards (S6 spec §8.3) ──

  final EventsResultsOptions results;
  final EventsRunsOptions runs;

  /// Whether a payment can be started in the app at all (`manual` or
  /// `provider`). `none` keeps the S3 "payment isn't open yet" slot.
  bool get paymentsOn => payment == 'manual' || payment == 'provider';

  static EventsOptions fromJson(Object? json) {
    if (json is! Map) return off;
    int intOf(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    return EventsOptions(
      discovery: json['discovery'] == true,
      favourites: json['favourites'] == true,
      registration: json['registration'] == true,
      holdTtlMinutes: intOf(json['holdTtlMinutes'], 30),
      maxParticipantsPerOrder: intOf(json['maxParticipantsPerOrder'], 10),
      payment: (json['payment']?.toString() ?? '').isEmpty
          ? 'none'
          : json['payment'].toString(),
      teams: json['teams'] == true,
      corporate: json['corporate'] == true,
      claim: EventsClaimOptions.fromJson(json['claim']),
      consentTextVersion: json['consentTextVersion']?.toString() ?? '',
      manualConfirmHours: intOf(json['manualConfirmHours'], 24),
      refundDays: intOf(json['refundDays'], 5),
      hold: EventsHoldOptions.fromJson(json['hold']),
      tickets: EventsTicketOptions.fromJson(json['tickets']),
      results: EventsResultsOptions.fromJson(json['results']),
      runs: EventsRunsOptions.fromJson(json['runs']),
      currency: (json['currency']?.toString() ?? '').isEmpty
          ? 'TZS'
          : json['currency'].toString(),
      closingSoonHours: json['closingSoonHours'] is num
          ? (json['closingSoonHours'] as num).toInt()
          : 72,
      regions: json['regions'] is List
          ? [for (final r in json['regions'] as List) ?EventsRegion.fromJson(r)]
          : const [],
      timezones: json['timezones'] is List
          ? [for (final t in json['timezones'] as List) t.toString()]
          : const [],
    );
  }
}
