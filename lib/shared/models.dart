import 'promotion.dart';
// Typed data models matching the portal's TypeScript interfaces in api.ts.
// Keeps the mobile app aligned with the backend/portal data contract.

import 'ff_datetime.dart';

class Gym {
  final String id;
  final String name;
  final String tier;
  final String location;
  final num perVisitRate;
  final num? ratePerDay;
  final num? ratePerWeek;
  final num? ratePerMonth;
  final num commissionRate;
  final String status;
  final String? accessMode;
  final String? venueType;
  final bool isVerified;

  /// The gym's listing is filled in (photos, hours, rates…). Separate from
  /// [isVerified], which follows the owner's KYC.
  final bool profileComplete;
  final String? verificationStatus;
  final double? latitude;
  final double? longitude;
  final List<String> images;

  /// Small WebP previews, parallel to [images] (same index = same photo).
  final List<String> thumbnails;
  final List<String> amenities;
  final List<String> equipment;

  /// Members' average star rating (0 when unrated) and published review count.
  final num rating;
  final int reviewCount;

  /// Set when this gym is promoted for what the customer is looking at.
  final PromotionTag? promotion;

  Gym({
    required this.id,
    required this.name,
    required this.tier,
    required this.location,
    required this.perVisitRate,
    this.ratePerDay,
    this.ratePerWeek,
    this.ratePerMonth,
    required this.commissionRate,
    required this.status,
    this.accessMode,
    this.venueType,
    this.isVerified = false,
    this.profileComplete = false,
    this.verificationStatus,
    this.latitude,
    this.longitude,
    this.images = const [],
    this.thumbnails = const [],
    this.amenities = const [],
    this.equipment = const [],
    this.rating = 0,
    this.reviewCount = 0,
    this.promotion,
  });

  factory Gym.fromJson(Map<String, dynamic> json) {
    final coordinates = json['coordinates'];
    final lat =
        _coordinateValue(json['lat']) ??
        (coordinates is Map ? _coordinateValue(coordinates['lat']) : null) ??
        (coordinates is List && coordinates.isNotEmpty
            ? _coordinateValue(coordinates[0])
            : null);
    final lng =
        _coordinateValue(json['lng']) ??
        _coordinateValue(json['longitude']) ??
        (coordinates is Map
            ? _coordinateValue(coordinates['lng']) ??
                  _coordinateValue(coordinates['longitude'])
            : null) ??
        (coordinates is List && coordinates.length > 1
            ? _coordinateValue(coordinates[1])
            : null);

    return Gym(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      tier: json['tier'] as String? ?? '',
      location: json['location'] as String? ?? '',
      perVisitRate: json['perVisitRate'] as num? ?? 0,
      ratePerDay: json['ratePerDay'] as num?,
      ratePerWeek: json['ratePerWeek'] as num?,
      ratePerMonth: json['ratePerMonth'] as num?,
      commissionRate: json['commissionRate'] as num? ?? 0,
      status: json['status'] as String? ?? 'active',
      accessMode: json['accessMode'] as String?,
      venueType: json['venueType'] as String?,
      isVerified: _boolValue(json['isVerified'] ?? json['verified']),
      profileComplete: _boolValue(json['profileComplete']),
      verificationStatus: json['verificationStatus'] as String?,
      latitude: lat,
      longitude: lng,
      images: (json['images'] as List?)?.whereType<String>().toList() ?? [],
      thumbnails:
          (json['thumbnails'] as List?)?.whereType<String>().toList() ?? [],
      amenities:
          (json['amenities'] as List?)?.whereType<String>().toList() ?? [],
      equipment:
          (json['equipment'] as List?)?.whereType<String>().toList() ?? [],
      rating: _numValue(json['rating']) ?? 0,
      reviewCount: (_numValue(json['reviewCount']) ?? 0).toInt(),
      promotion: PromotionTag.fromJson(json['promotion']),
    );
  }

  /// This gym with a new rating — after the member reviews it.
  Gym withRating(num rating, int reviewCount) => Gym(
    id: id,
    name: name,
    tier: tier,
    location: location,
    perVisitRate: perVisitRate,
    ratePerDay: ratePerDay,
    ratePerWeek: ratePerWeek,
    ratePerMonth: ratePerMonth,
    commissionRate: commissionRate,
    status: status,
    accessMode: accessMode,
    venueType: venueType,
    isVerified: isVerified,
    profileComplete: profileComplete,
    verificationStatus: verificationStatus,
    latitude: latitude,
    longitude: longitude,
    images: images,
    thumbnails: thumbnails,
    amenities: amenities,
    equipment: equipment,
    rating: rating,
    reviewCount: reviewCount,
    promotion: promotion,
  );

  bool get isFreeOnline => accessMode == 'free_online';
  bool get isPaidVisit => accessMode == 'paid_visit';
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Small preview image for cards/lists — falls back to the full image for
  /// gyms created before thumbnails existed.
  String? get coverThumbnail =>
      thumbnails.isNotEmpty ? thumbnails.first : images.firstOrNull;
}

double? _coordinateValue(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// Numbers that may arrive as strings (older API builds sent decimals as "4.50").
num? _numValue(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

bool _boolValue(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.toLowerCase() == 'true';
  return false;
}

class TrainerProfile {
  final String id;
  final String? userId;
  final String? email;
  final String displayName;
  final String? photoUrl;
  final List<String> specialties;
  final String? bio;
  final num? rating;
  final int? reviewCount;
  final num hourlyRateTzs;
  final String sessionRateCurrency;
  final int? experienceYears;
  final List<String> gymIds;
  final List<Gym> gyms;
  final String status;
  final String? approvalStatus;
  final bool isVerified;

  /// False while the trainer is not verified yet: they are listed, but cannot
  /// be booked or connected with.
  final bool bookable;
  final List<TrainerAvailability> availability;
  final SocialLinks socialLinks;

  /// The trainer's photo gallery (first = profile picture). Empty for
  /// profiles that only ever had a single [photoUrl].
  final List<String> images;

  /// Every photo to show: the gallery, or just the profile picture.
  List<String> get photos {
    if (images.isNotEmpty) return images;
    final p = photoUrl;
    return p == null || p.isEmpty ? const [] : [p];
  }

  /// Set when this trainer is promoted for what the customer is looking at.
  final PromotionTag? promotion;

  TrainerProfile({
    required this.id,
    this.userId,
    this.email,
    required this.displayName,
    this.photoUrl,
    this.specialties = const [],
    this.bio,
    this.rating,
    this.reviewCount,
    required this.hourlyRateTzs,
    this.sessionRateCurrency = 'TZS',
    this.experienceYears,
    this.gymIds = const [],
    this.gyms = const [],
    required this.status,
    this.approvalStatus,
    this.isVerified = false,
    this.bookable = true,
    this.availability = const [],
    this.socialLinks = const SocialLinks(),
    this.images = const [],
    this.promotion,
  });

  factory TrainerProfile.fromJson(Map<String, dynamic> json) => TrainerProfile(
    id: json['id'] as String? ?? '',
    userId: json['userId'] as String?,
    email: json['email'] as String?,
    displayName: json['displayName'] as String? ?? '',
    photoUrl: json['photoUrl'] as String?,
    specialties:
        (json['specialties'] as List?)?.whereType<String>().toList() ?? [],
    bio: json['bio'] as String?,
    rating: _numValue(json['rating']),
    reviewCount: _numValue(json['reviewCount'])?.toInt(),
    hourlyRateTzs: json['hourlyRateTzs'] as num? ?? 0,
    sessionRateCurrency: json['sessionRateCurrency'] as String? ?? 'TZS',
    experienceYears: json['experienceYears'] as int?,
    gymIds: (json['gymIds'] as List?)?.whereType<String>().toList() ?? [],
    gyms:
        (json['gyms'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(Gym.fromJson)
            .toList() ??
        [],
    status: json['status'] as String? ?? 'active',
    approvalStatus: json['approvalStatus'] as String?,
    isVerified: _boolValue(json['isVerified'] ?? json['verified']),
    // Older backends don't send it: every listed trainer was bookable.
    bookable: json['bookable'] == null || _boolValue(json['bookable']),
    availability: _trainerAvailabilityFromJson(json['availability']),
    socialLinks: SocialLinks.fromJson(json['socialLinks']),
    images:
        (json['images'] as List?)
            ?.whereType<String>()
            .where((s) => s.isNotEmpty)
            .toList() ??
        const [],
    promotion: PromotionTag.fromJson(json['promotion']),
  );

  /// This trainer with a new rating — after the member reviews them.
  TrainerProfile withRating(num rating, int reviewCount) => TrainerProfile(
    id: id,
    userId: userId,
    email: email,
    displayName: displayName,
    photoUrl: photoUrl,
    specialties: specialties,
    bio: bio,
    rating: rating,
    reviewCount: reviewCount,
    hourlyRateTzs: hourlyRateTzs,
    sessionRateCurrency: sessionRateCurrency,
    experienceYears: experienceYears,
    gymIds: gymIds,
    gyms: gyms,
    status: status,
    approvalStatus: approvalStatus,
    isVerified: isVerified,
    bookable: bookable,
    availability: availability,
    socialLinks: socialLinks,
    images: images,
    promotion: promotion,
  );
}

/// A trainer's social profiles, stored as bare handles (no URL, no '@').
class SocialLinks {
  final String? instagram;
  final String? facebook;
  final String? twitter;

  const SocialLinks({this.instagram, this.facebook, this.twitter});

  factory SocialLinks.fromJson(Object? json) {
    if (json is! Map) return const SocialLinks();
    String? handle(String key) {
      final v = json[key]?.toString().trim() ?? '';
      return v.isEmpty ? null : v;
    }

    return SocialLinks(
      instagram: handle('instagram'),
      facebook: handle('facebook'),
      twitter: handle('twitter'),
    );
  }

  bool get isEmpty => instagram == null && facebook == null && twitter == null;

  Map<String, String> toJson() => {
    'instagram': instagram ?? '',
    'facebook': facebook ?? '',
    'twitter': twitter ?? '',
  };
}

/// One hourly slot in a trainer's dated calendar (GET /trainers/:id/schedule).
class ScheduleSlot {
  final String slot;

  /// 'available' | 'booked' | 'past'
  final String status;
  final List<String> gymIds;

  /// Only in the trainer's own view: who booked it.
  final String? bookingId;
  final String? memberName;
  final String? bookingStatus;

  const ScheduleSlot({
    required this.slot,
    required this.status,
    this.gymIds = const [],
    this.bookingId,
    this.memberName,
    this.bookingStatus,
  });

  bool get isAvailable => status == 'available';
  bool get isBooked => status == 'booked';

  factory ScheduleSlot.fromJson(Map<String, dynamic> json) {
    final booking = json['booking'] is Map ? json['booking'] as Map : null;
    final member = booking?['member'] is Map ? booking!['member'] as Map : null;
    return ScheduleSlot(
      slot: json['slot']?.toString() ?? '',
      status: json['status']?.toString() ?? 'past',
      gymIds: (json['gymIds'] as List?)?.whereType<String>().toList() ?? [],
      bookingId: booking?['id']?.toString(),
      memberName: member?['displayName']?.toString(),
      bookingStatus: booking?['status']?.toString(),
    );
  }
}

/// One calendar day (EAT) of a trainer's schedule.
class ScheduleDay {
  final String date; // YYYY-MM-DD
  final String weekday; // 'monday'…
  final List<ScheduleSlot> slots;

  const ScheduleDay({
    required this.date,
    required this.weekday,
    this.slots = const [],
  });

  int get openCount => slots.where((s) => s.isAvailable).length;

  factory ScheduleDay.fromJson(Map<String, dynamic> json) => ScheduleDay(
    date: json['date']?.toString() ?? '',
    weekday: json['weekday']?.toString() ?? '',
    slots:
        (json['slots'] as List?)
            ?.whereType<Map>()
            .map((s) => ScheduleSlot.fromJson(Map<String, dynamic>.from(s)))
            .toList() ??
        [],
  );

  static List<ScheduleDay> listFromResponse(Object? response) {
    final days = response is Map ? response['days'] : null;
    if (days is! List) return const [];
    return days
        .whereType<Map>()
        .map((d) => ScheduleDay.fromJson(Map<String, dynamic>.from(d)))
        .toList();
  }
}

List<TrainerAvailability> _trainerAvailabilityFromJson(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (item) => TrainerAvailability.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList();
}

class TrainerAvailability {
  /// Day of week (e.g. 'monday', 'tuesday') or legacy date string (e.g. '2026-05-05').
  final String day;

  /// Gym ID where the trainer is available, null if any gym.
  final String? gymId;

  /// Gym name (resolved on read), null if not hydrated.
  final String? gymName;

  /// Time slots available on this day at this gym.
  final List<String> slots;

  TrainerAvailability({
    required this.day,
    this.gymId,
    this.gymName,
    required this.slots,
  });

  factory TrainerAvailability.fromJson(Map<String, dynamic> json) =>
      TrainerAvailability(
        day: json['day'] as String? ?? json['date'] as String? ?? '',
        gymId: json['gymId'] as String?,
        gymName: json['gymName'] as String?,
        slots: (json['slots'] as List?)?.whereType<String>().toList() ?? [],
      );

  /// The day's name in the app language ("Monday" / "Jumatatu").
  String get dayLabel {
    return weekdayName(day) ?? day;
  }
}

class MemberProfile {
  final String? fitnessGoal;
  final List<String> fitnessGoals;
  final String? fitnessLevel;
  final num? heightCm;
  final num? weightKg;
  final String? dateOfBirth;
  final String? gender;
  final List<String> preferredWorkoutTimes;

  MemberProfile({
    this.fitnessGoal,
    this.fitnessGoals = const [],
    this.fitnessLevel,
    this.heightCm,
    this.weightKg,
    this.dateOfBirth,
    this.gender,
    this.preferredWorkoutTimes = const [],
  });

  factory MemberProfile.fromJson(Map<String, dynamic> json) => MemberProfile(
    fitnessGoal: json['fitnessGoal'] as String?,
    fitnessGoals:
        (json['fitnessGoals'] as List?)?.whereType<String>().toList() ??
        const [],
    fitnessLevel: json['fitnessLevel'] as String?,
    heightCm: json['heightCm'] as num?,
    weightKg: json['weightKg'] as num?,
    dateOfBirth: json['dateOfBirth'] as String?,
    gender: json['gender'] as String?,
    preferredWorkoutTimes:
        (json['preferredWorkoutTimes'] as List?)
            ?.whereType<String>()
            .toList() ??
        [],
  );
}

class MemberSummary {
  final String id;
  final String? email;
  final String? phone;
  final String? displayName;
  final String? photoUrl;
  final String? publicId;
  final String userType;
  final String? accountStatus;
  final MemberProfile? memberProfile;
  final Subscription? subscription;
  final PaymentRequest? pendingPayment;
  final bool? onboardingCompleted;

  MemberSummary({
    required this.id,
    this.email,
    this.phone,
    this.displayName,
    this.photoUrl,
    this.publicId,
    required this.userType,
    this.accountStatus,
    this.memberProfile,
    this.subscription,
    this.pendingPayment,
    this.onboardingCompleted,
  });

  factory MemberSummary.fromJson(Map<String, dynamic> json) => MemberSummary(
    id: json['id'] as String? ?? '',
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    displayName: json['displayName'] as String?,
    photoUrl: json['photoUrl'] as String?,
    publicId: json['publicId'] as String? ?? json['userCode'] as String?,
    userType: json['userType'] as String? ?? 'member',
    accountStatus: json['accountStatus'] as String?,
    memberProfile: json['memberProfile'] is Map<String, dynamic>
        ? MemberProfile.fromJson(json['memberProfile'] as Map<String, dynamic>)
        : null,
    subscription: json['subscription'] is Map<String, dynamic>
        ? Subscription.fromJson(json['subscription'] as Map<String, dynamic>)
        : null,
    pendingPayment: json['pendingPayment'] is Map<String, dynamic>
        ? PaymentRequest.fromJson(
            json['pendingPayment'] as Map<String, dynamic>,
          )
        : null,
    onboardingCompleted: json['onboardingCompleted'] as bool?,
  );

  String get resolvedName => knownName ?? 'Member';

  /// The best name on record, or null when there is none to show. Screens
  /// use this with a translated fallback (`member.nameFallback`).
  String? get knownName => displayName ?? email ?? phone ?? publicId;
}

class Subscription {
  final String? id;
  final String? type;
  final String? tier;

  /// Direct-sub plan: 'daily' | 'weekly' | 'monthly' (null for platform pass).
  final String? plan;
  final String status;
  final String? startedAt;
  final String? renewsAt;
  final String? expiresAt;
  final String? homeGymId;

  /// The subscribed gym for direct subscriptions (A3), hydrated by /me.
  final Gym? homeGym;

  Subscription({
    this.id,
    this.type,
    this.tier,
    this.plan,
    required this.status,
    this.startedAt,
    this.renewsAt,
    this.expiresAt,
    this.homeGymId,
    this.homeGym,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
    id: json['id'] as String?,
    type: json['type'] as String?,
    tier: json['tier'] as String?,
    plan: json['plan'] as String?,
    status: json['status'] as String? ?? 'inactive',
    startedAt: json['startedAt'] as String?,
    renewsAt: json['renewsAt'] as String?,
    expiresAt: json['expiresAt'] as String?,
    homeGymId: json['homeGymId'] as String?,
    homeGym: json['homeGym'] is Map<String, dynamic>
        ? Gym.fromJson(json['homeGym'] as Map<String, dynamic>)
        : null,
  );

  bool get isActive => status == 'active';
  bool get isDirect => type == 'direct_sub';

  DateTime? get expiryDate =>
      expiresAt == null ? null : DateTime.tryParse(expiresAt!);

  /// Whole days remaining until expiry (negative when already expired).
  int? get daysLeft {
    final expiry = expiryDate;
    if (expiry == null) return null;
    return expiry.difference(DateTime.now()).inHours ~/ 24;
  }

  bool get isExpired {
    if (status == 'expired') return true;
    final expiry = expiryDate;
    return expiry != null && DateTime.now().isAfter(expiry);
  }
}

class PaymentRequest {
  final String id;
  final String memberId;
  final String subscriptionId;
  final String tier;

  /// What the request buys: FITFLEX_PASS, GYM_SUBSCRIPTION, TRAINER_SERVICE,
  /// TRAINER_GYM_PASS or SHOP_ORDER (null from an older server).
  final String? productType;

  /// Daily / weekly / monthly for a gym plan.
  final String? plan;
  final String? gymId;
  final String? gymName;

  /// An event-ticket request (EVENT_ORDER): the event's title and the
  /// order's reference, when the server sends them (events S4 §8 item 11).
  final String? eventTitle;
  final String? eventOrderReference;
  final num amountTzs;
  final String status;
  final String provider;
  final String? reference;

  /// The transaction ID the member typed when paying a Lipa Namba by hand
  /// (upper-cased by the server). Such a request is not paid by "Pay now".
  final String? memberReference;

  /// The mobile-money number the member says they paid from (+255…).
  final String? payerPhone;
  final String? note;
  final String requestedAt;
  final String? decidedAt;

  PaymentRequest({
    required this.id,
    required this.memberId,
    required this.subscriptionId,
    required this.tier,
    this.productType,
    this.plan,
    this.gymId,
    this.gymName,
    this.eventTitle,
    this.eventOrderReference,
    required this.amountTzs,
    required this.status,
    required this.provider,
    this.reference,
    this.memberReference,
    this.payerPhone,
    this.note,
    required this.requestedAt,
    this.decidedAt,
  });

  factory PaymentRequest.fromJson(Map<String, dynamic> json) => PaymentRequest(
    id: json['id'] as String? ?? '',
    memberId: json['memberId'] as String? ?? '',
    subscriptionId: json['subscriptionId'] as String? ?? '',
    tier: json['tier'] as String? ?? '',
    productType: json['productType'] as String?,
    plan: json['plan'] as String?,
    gymId: json['gymId'] as String?,
    gymName: json['gym'] is Map
        ? (json['gym'] as Map)['name'] as String?
        : null,
    eventTitle: json['eventTitle'] as String?,
    eventOrderReference: json['eventOrderReference'] as String?,
    amountTzs: json['amountTzs'] as num? ?? 0,
    status: json['status'] as String? ?? 'pending',
    provider: json['provider'] as String? ?? '',
    reference: json['reference'] as String?,
    memberReference:
        (json['memberReference'] as String?)?.trim().isEmpty == true
        ? null
        : json['memberReference'] as String?,
    payerPhone: (json['payerPhone'] as String?)?.trim().isEmpty == true
        ? null
        : json['payerPhone'] as String?,
    note: json['note'] as String?,
    requestedAt: json['requestedAt'] as String? ?? '',
    decidedAt: json['decidedAt'] as String?,
  );
}

class CheckIn {
  final String id;
  final String memberId;
  final String? memberPhone;
  final String? memberEmail;
  final String timestamp;
  final String? passTier;
  final int? visitNumberInCycle;
  final String gymTier;
  final Gym? gym;
  final String? gymId;

  CheckIn({
    required this.id,
    required this.memberId,
    this.memberPhone,
    this.memberEmail,
    required this.timestamp,
    this.passTier,
    this.visitNumberInCycle,
    required this.gymTier,
    this.gym,
    this.gymId,
  });

  factory CheckIn.fromJson(Map<String, dynamic> json) => CheckIn(
    id: json['id'] as String? ?? '',
    memberId: json['memberId'] as String? ?? '',
    memberPhone: json['memberPhone'] as String?,
    memberEmail: json['memberEmail'] as String?,
    timestamp: json['timestamp'] as String? ?? '',
    passTier: json['passTier'] as String?,
    visitNumberInCycle: json['visitNumberInCycle'] as int?,
    gymTier: json['gymTier'] as String? ?? '',
    gym: json['gym'] is Map<String, dynamic>
        ? Gym.fromJson(json['gym'] as Map<String, dynamic>)
        : null,
    gymId: json['gymId'] as String?,
  );
}

class TrainerBooking {
  final String id;
  final String memberId;
  final String trainerId;
  final String gymId;
  final String date;
  final String slot;
  final num amountTzs;
  final String status;
  final String? createdAt;

  TrainerBooking({
    required this.id,
    required this.memberId,
    required this.trainerId,
    required this.gymId,
    required this.date,
    required this.slot,
    required this.amountTzs,
    required this.status,
    this.createdAt,
  });

  factory TrainerBooking.fromJson(Map<String, dynamic> json) => TrainerBooking(
    id: json['id'] as String? ?? '',
    memberId: json['memberId'] as String? ?? '',
    trainerId: json['trainerId'] as String? ?? '',
    gymId: json['gymId'] as String? ?? '',
    date: json['date'] as String? ?? '',
    slot: json['slot'] as String? ?? '',
    amountTzs: json['amountTzs'] as num? ?? 0,
    status: json['status'] as String? ?? 'confirmed',
    createdAt: json['createdAt'] as String?,
  );
}

/// Response from /me endpoint — matches portal's MemberMeResponse.
class MemberMeResponse {
  final MemberSummary user;
  final Subscription? subscription;
  final PaymentRequest? pendingPayment;

  /// Every open payment, each labelled by product (pass, gym plan, trainer session, ...).
  final List<PaymentRequest> pendingPayments;
  final int visitsUsed;
  final int? visitCap;

  /// The member's username, when they have one. [usernameEnabled] is true
  /// when the server sent the username fields at all (feature on).
  final String? username;
  final DateTime? usernameChangeableAt;
  final bool usernameEnabled;

  MemberMeResponse({
    required this.user,
    this.subscription,
    this.pendingPayment,
    this.pendingPayments = const [],
    required this.visitsUsed,
    this.visitCap,
    this.username,
    this.usernameChangeableAt,
    this.usernameEnabled = false,
  });

  factory MemberMeResponse.fromJson(
    Map<String, dynamic> json,
  ) => MemberMeResponse(
    user: MemberSummary.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
    subscription: json['subscription'] is Map<String, dynamic>
        ? Subscription.fromJson(json['subscription'] as Map<String, dynamic>)
        : null,
    pendingPayment: json['pendingPayment'] is Map<String, dynamic>
        ? PaymentRequest.fromJson(
            json['pendingPayment'] as Map<String, dynamic>,
          )
        : null,
    pendingPayments: [
      for (final p in (json['pendingPayments'] as List? ?? const []))
        if (p is Map<String, dynamic>) PaymentRequest.fromJson(p),
    ],
    visitsUsed: (json['visitsUsed'] as num?)?.toInt() ?? 0,
    visitCap: (json['visitCap'] as num?)?.toInt(),
    username: json['username'] as String?,
    usernameChangeableAt: DateTime.tryParse(
      json['usernameChangeableAt']?.toString() ?? '',
    )?.toLocal(),
    usernameEnabled: json.containsKey('username'),
  );

  bool get hasActivePass => subscription?.isActive == true;
  bool get needsOnboarding => user.onboardingCompleted != true;
}

class PassTier {
  final String id;
  final num price;
  final int? visitCap;
  final String? label;
  final String? gymAccess;

  PassTier({
    required this.id,
    required this.price,
    this.visitCap,
    this.label,
    this.gymAccess,
  });

  /// Parse from /passes (legacy) or /subscription-tiers (new).
  factory PassTier.fromJson(Map<String, dynamic> json) => PassTier(
    id: json['id'] as String? ?? json['key'] as String? ?? '',
    price: json['price'] as num? ?? json['monthlyPrice'] as num? ?? 0,
    visitCap:
        (json['visitCap'] as num?)?.toInt() ??
        ((json['visits'] as num?)?.toInt() == -1
            ? null
            : (json['visits'] as num?)?.toInt()),
    label: json['label'] as String?,
    gymAccess: json['gymAccess'] as String?,
  );
}

// ── Reviews ────────────────────────────────────────────────────────────────

/// What a member can review: a gym (after a visit or direct subscription) or a
/// trainer (after a completed session). [path] is the API collection.
enum ReviewSubject {
  gym('gyms'),
  trainer('trainers');

  const ReviewSubject(this.path);
  final String path;
}

/// One published review as the public sees it — the reviewer's first name and
/// initial, never their id.
class Review {
  final String id;
  final int rating;
  final String? text;
  final String memberName;

  /// The reviewer's username, when they have one.
  final String? memberUsername;
  final String? memberPhotoUrl;
  final DateTime? createdAt;

  const Review({
    required this.id,
    required this.rating,
    this.text,
    required this.memberName,
    this.memberUsername,
    this.memberPhotoUrl,
    this.createdAt,
  });

  /// "@amina_k" for a reviewer with a username, else first name and initial.
  String get memberLabel =>
      (memberUsername ?? '').isNotEmpty ? '@$memberUsername' : memberName;

  factory Review.fromJson(Map<String, dynamic> json) => Review(
    id: json['id'] as String? ?? '',
    rating: (_numValue(json['rating']) ?? 0).toInt(),
    text: json['text'] as String?,
    memberName: json['memberName'] as String? ?? '',
    memberUsername: json['memberUsername'] as String?,
    memberPhotoUrl: json['memberPhotoUrl'] as String?,
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
  );

  static List<Review> listFrom(Object? json) => (json is List ? json : const [])
      .whereType<Map>()
      .map((r) => Review.fromJson(Map<String, dynamic>.from(r)))
      .toList();
}

/// Average (null when there are no reviews), count and 1–5 star distribution.
class ReviewSummary {
  final double? average;
  final int count;
  final Map<int, int> distribution;

  const ReviewSummary({
    this.average,
    this.count = 0,
    this.distribution = const {},
  });

  factory ReviewSummary.fromJson(Map<String, dynamic> json) {
    final dist = json['distribution'];
    return ReviewSummary(
      average: _numValue(json['averageRating'])?.toDouble(),
      count: (_numValue(json['reviewCount']) ?? 0).toInt(),
      distribution: {
        for (var star = 1; star <= 5; star++)
          star: dist is Map ? (_numValue(dist['$star']) ?? 0).toInt() : 0,
      },
    );
  }
}

/// The signed-in member's own review, and whether they may write one.
class MyReviewState {
  final bool eligible;

  /// Why the member can't review yet, e.g. 'no_completed_booking'.
  final String? reason;
  final int? rating;
  final String? text;

  const MyReviewState({
    required this.eligible,
    this.reason,
    this.rating,
    this.text,
  });

  bool get hasReview => rating != null;
}
