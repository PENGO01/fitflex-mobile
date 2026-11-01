// The signed-in user's messages: booking, payment and renewal notifications
// the app already sends, plus messages from their gym and from FitFlex.
// One controller for the whole app, so the bell's unread badge, the inbox
// and push taps all agree.

import 'package:flutter/foundation.dart';

import '../api_client.dart';
import '../partner_media/partner_media_flag.dart';

/// What kind of message this is, for filtering and labels.
enum InboxCategory { membership, payments, offers, announcements, other }

class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    this.category,
    this.gymId,
    this.campaignId,
    this.createdAt,
    this.readAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;

  /// 'transactional' | 'marketing' for gym/FitFlex messages, else null.
  final String? category;
  final String? gymId;
  final String? campaignId;
  final DateTime? createdAt;
  final DateTime? readAt;

  bool get unread => readAt == null;

  /// A request to connect: answered with Approve / Reject on the card.
  bool get isFriendInvitation => type == 'friend_invitation';
  String get friendStatus => data['status']?.toString() ?? 'pending';
  String? get invitationId => _nonEmpty(data['invitationId']);
  bool get fromCampaign => data['source'] == 'communication';
  String get deepLink => data['deepLink']?.toString() ?? '';
  String? get ctaLabel => _nonEmpty(data['ctaLabel']);
  String? get senderName => _nonEmpty(data['senderName']);

  InboxCategory get kind {
    if (fromCampaign) {
      if (category == 'marketing') return InboxCategory.offers;
      return switch (deepLink) {
        'membership' || 'renewal' => InboxCategory.membership,
        'payment' => InboxCategory.payments,
        _ => InboxCategory.announcements,
      };
    }
    if (type.startsWith('subscription_')) return InboxCategory.membership;
    if (type.contains('payment') || type == 'trainer_booking_confirmed') {
      return InboxCategory.payments;
    }
    return InboxCategory.other;
  }

  InboxMessage copyWith({DateTime? readAt, Map<String, dynamic>? data}) =>
      InboxMessage(
        id: id,
        type: type,
        title: title,
        body: body,
        data: data ?? this.data,
        category: category,
        gymId: gymId,
        campaignId: campaignId,
        createdAt: createdAt,
        readAt: readAt ?? this.readAt,
      );

  factory InboxMessage.fromJson(Map<String, dynamic> j) => InboxMessage(
    id: j['id'].toString(),
    type: j['type']?.toString() ?? '',
    title: j['title']?.toString() ?? '',
    body: j['body']?.toString() ?? '',
    data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
    category: j['category']?.toString(),
    gymId: j['gymId']?.toString(),
    campaignId: j['campaignId']?.toString(),
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
    readAt: DateTime.tryParse(j['readAt']?.toString() ?? '')?.toLocal(),
  );

  static String? _nonEmpty(dynamic v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }
}

/// The kind of screen a message leads to (`membership`, `trainer`,
/// `trainingOffer`…), from its own link or, failing that, its type. Empty
/// when it leads nowhere. Also names the button: `inbox.open.<link>`.
String memberLinkFor({required String deepLink, required String type}) =>
    deepLink.isNotEmpty
    ? deepLink
    : switch (type) {
        'subscription_renewal' || 'subscription_activated' => 'membership',
        // A trainer answered the member's enquiry: open that trainer.
        'trainer_enquiry_reply' => 'trainer',
        // A trainer made the member a plan: open the offer to answer it.
        'training_plan_offered' => 'trainingOffer',
        // Their trainer changed or stopped the plan they are on.
        'training_plan_updated' || 'training_plan_stopped' => 'trainingPlan',
        // Their trainer recorded that they missed a session: open it.
        'trainer_booking_no_show' => 'session',
        // An organisation asked to add them: open the requests to answer.
        b2bMemberRequestType => 'memberRequests',
        // A running event (events S2; a future `event` notice type with
        // `data.eventId`): open the event, or the list without an id.
        'event' => 'event',
        // Events S3 (spec §3.14): the purchaser's order notices open the
        // order; "Is this you?" opens the claim page; a claim opens the
        // registration.
        'event_order_created' ||
        'event_order_expired' ||
        'event_order_cancelled' => 'eventOrder',
        'event_claim_available' => 'eventClaim',
        'event_place_claimed' || 'event_place_cancelled' => 'eventRegistration',
        // Events S4 (spec §3.16): payment and refund notices open the
        // order; a rejection opens the pay page to try again; confirmed
        // opens the tickets; a ticket for a participant opens the ticket;
        // a cancelled place opens the registrations list.
        'event_payment_submitted' ||
        'event_payment_refund_due' ||
        'event_payment_late_received' ||
        'event_cancelled_refund' ||
        'event_refund_requested' ||
        'event_refund_approved' ||
        'event_refund_paid' ||
        'event_refund_rejected' => 'eventOrder',
        'event_payment_confirmed' => 'eventTickets',
        'event_payment_rejected' => 'eventPay',
        // Events S5 (spec §4.6): kit collected / bib assigned open the ticket.
        'event_ticket_ready' ||
        'event_kit_collected' ||
        'event_bib_assigned' => 'eventTicket',
        'event_place_cancelled_by_purchaser' => 'eventRegistrations',
        // Events S6 (spec §11): results, corrections, rejections and
        // disputes open the result; medals and rewards open their screens.
        'event_result_published' ||
        'event_result_corrected' ||
        'event_result_rejected' ||
        'event_dispute_update' => 'eventResult',
        'event_medal_awarded' || 'event_medal_revoked' => 'eventMedals',
        'event_reward_earned' || 'event_reward_reversed' => 'eventRewards',
        _ => '',
      };

/// Messages whose push opens their screen directly, not the message: the
/// screen says everything the message does, and is where the member acts.
bool opensScreenDirectly(String type) {
  final link = memberLinkFor(deepLink: '', type: type);
  return link.startsWith('training') || link == 'memberRequests';
}

/// The notice an organisation's request to add someone by user id sends
/// (fitflex-functions#241); its data carries `open: 'b2b_member_requests'`.
const b2bMemberRequestType = 'b2b_member_request';

/// Where organisation requests are answered. Not under `/member`: a request
/// for an organisation role can reach anyone with a FitFlex account.
const b2bMemberRequestsRoute = '/organisation-requests';

/// Whether a notice (push data or inbox message) is an organisation asking
/// to add the user, whatever side of FitFlex they are signed in on.
bool isB2BMemberRequest(String type, Map<String, dynamic> data) =>
    type == b2bMemberRequestType || data['open'] == 'b2b_member_requests';

/// The notice a FitFlex admin's direct add sends (fitflex-functions#241);
/// its data carries `kind` and `open: 'b2b_benefits'`.
const b2bAdminAddedType = 'b2b_admin_added';

/// The member's wellness benefits (same path as `AppRoutes.memberBenefits`).
const memberBenefitsRoute = '/member/benefits';

/// Whether a FitFlex admin's add opens the member's Benefits: only for a
/// member enrolled or linked to a staff record. A portal role (`org_user`),
/// or anyone not signed in as a member, sees the message itself instead.
bool adminAddedOpensBenefits(String? role, Map<String, dynamic> data) =>
    role == 'member' && data['kind']?.toString() != 'org_user';

/// Where a message's button (or a tap on its push) takes a member. Null
/// means "show the message itself". Only fixed app screens are allowed.
String? memberRouteFor({
  required String deepLink,
  required String type,
  String? gymId,
  String? trainerId,
  String? planId,
  String? bookingId,
  String? eventId,
  String? orderId,
  String? registrationId,
}) {
  final link = memberLinkFor(deepLink: deepLink, type: type);
  return switch (link) {
    'membership' || 'renewal' => '/member/passes',
    'payment' => '/member/payment',
    'gym' when gymId != null && gymId.isNotEmpty => '/member/gyms/$gymId',
    'trainer' when trainerId != null && _safeId.hasMatch(trainerId) =>
      '/member/trainers/$trainerId',
    'trainingOffer' when planId != null && _safeId.hasMatch(planId) =>
      '/member/activity/training/offers/$planId',
    'trainingPlan' => '/member/activity/training',
    'session' when bookingId != null && _safeId.hasMatch(bookingId) => Uri(
      path: '/member/sessions',
      queryParameters: {'booking': bookingId},
    ).toString(),
    'session' => '/member/sessions',
    'memberRequests' || 'b2b_member_requests' => b2bMemberRequestsRoute,
    'event' when eventId != null && _safeId.hasMatch(eventId) =>
      '/member/events/$eventId',
    'event' => '/member/events',
    'eventOrder' when orderId != null && _safeId.hasMatch(orderId) =>
      '/member/events/orders/$orderId',
    'eventOrder' => '/member/events/orders',
    'eventClaim'
        when registrationId != null && _safeId.hasMatch(registrationId) =>
      '/member/events/claim/$registrationId',
    'eventClaim' => '/member/events/orders',
    'eventRegistration'
        when registrationId != null && _safeId.hasMatch(registrationId) =>
      '/member/events/registrations/$registrationId',
    'eventRegistration' => '/member/events/orders',
    'eventTickets' => '/member/events/tickets',
    'eventPay' when orderId != null && _safeId.hasMatch(orderId) =>
      '/member/events/orders/$orderId/pay',
    'eventPay' => '/member/events/orders',
    'eventTicket'
        when registrationId != null && _safeId.hasMatch(registrationId) =>
      '/member/events/registrations/$registrationId/ticket',
    'eventTicket' => '/member/events/tickets',
    'eventRegistrations' => '/member/events/orders?tab=registrations',
    'eventResult'
        when registrationId != null && _safeId.hasMatch(registrationId) =>
      '/member/events/registrations/$registrationId/result',
    // Without an id the member's own results list is the nearest screen.
    'eventResult' => '/member/events/results',
    'eventMedals' => '/member/events/medals',
    'eventRewards' => '/member/events/rewards',
    _ => null,
  };
}

/// Where a tapped push takes the signed-in user: `go` replaces the stack
/// with a screen; otherwise the location is pushed over it. Members with a
/// plan from their trainer, and partners with news about one of their
/// screens, go straight there; anything else (a gym or FitFlex campaign,
/// for every role) opens its in-app copy, or the inbox when there is none.
({String location, bool go}) pushTargetFor({
  required String? role,
  required Map<String, dynamic> data,
  InboxMessage? message,
}) {
  final type = data['type']?.toString() ?? '';
  // An organisation asked to add them: open the requests, where they accept
  // or decline (any side; an organisation role can go to anyone).
  if (isB2BMemberRequest(type, data)) {
    return (location: b2bMemberRequestsRoute, go: true);
  }
  // A FitFlex admin added them: a member's benefits, else the message.
  if (type == b2bAdminAddedType && adminAddedOpensBenefits(role, data)) {
    return (location: memberBenefitsRoute, go: true);
  }
  // A plan from their trainer opens on the plan itself, where they answer.
  if (role == 'member' && opensScreenDirectly(type)) {
    final direct = memberRouteFor(
      deepLink: '',
      type: type,
      planId: data['planId']?.toString(),
    );
    if (direct != null) return (location: direct, go: true);
  }
  // Trainers, vendors and gyms go straight to the screen the news is about.
  if (partnerSide(role) case final side?) {
    final direct = partnerRouteFor(
      side: side,
      type: type,
      gymId: data['gymId']?.toString(),
      memberId: data['memberId']?.toString(),
      productId: data['productId']?.toString(),
      variant: data['variant']?.toString(),
      saleId: data['saleId']?.toString(),
      customerId: data['customerId']?.toString(),
      bannerId: (data['bannerId'] ?? data['item'])?.toString(),
      flashSaleId: (data['saleId'] ?? data['item'])?.toString(),
    );
    if (direct != null) return (location: direct, go: true);
  }
  if (message != null) {
    // A friend request is answered on its card in the list.
    return (
      location: message.isFriendInvitation ? '/inbox' : '/inbox/${message.id}',
      go: false,
    );
  }
  final route = role == 'member'
      ? memberRouteFor(
          deepLink: data['deepLink']?.toString() ?? '',
          type: type,
          gymId: data['gymId']?.toString(),
          trainerId: data['trainerId']?.toString(),
          planId: data['planId']?.toString(),
          bookingId: data['bookingId']?.toString(),
          eventId: data['eventId']?.toString(),
          orderId: data['orderId']?.toString(),
          registrationId: data['registrationId']?.toString(),
        )
      : null;
  if (route != null) return (location: route, go: true);
  return (location: '/inbox', go: false);
}

/// A notice's words in the app language. Some notices carry both languages
/// in their data (`titleEn`/`bodyEn`, `titleSw`/`bodySw`, e.g.
/// trainer_booking_no_show), while the top-level title/body follow the
/// member's saved `locale`, which may differ from the app's. The app
/// language's copy wins; a missing line keeps the server's text.
({String title, String body}) localisedNoticeText({
  required String lang,
  required Map<String, dynamic> data,
  required String title,
  required String body,
}) {
  final suffix = lang == 'sw' ? 'Sw' : 'En';
  final t = data['title$suffix']?.toString().trim() ?? '';
  final b = data['body$suffix']?.toString().trim() ?? '';
  return (title: t.isEmpty ? title : t, body: b.isEmpty ? body : b);
}

final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

// ── Trainers, vendors and gyms ──────────────────────────────────────────────

/// The notice sent when FitFlex takes down a partner's home photo or logo.
const partnerMediaTakenDownType = 'partner_media.taken_down';

/// The side of FitFlex a signed-in partner works on, from their account
/// type: `trainer`, `vendor` (and vendor staff) or `gym` (owner and staff).
/// Null for members and anyone else.
String? partnerSide(String? userType) => switch (userType) {
  'trainer' => 'trainer',
  'vendor' || 'vendor_staff' => 'vendor',
  'gym_operator' || 'gym_staff' => 'gym',
  _ => null,
};

/// The kind of screen a partner's message leads to — also the name of its
/// button (`inbox.open.<link>`). Empty when the message leads nowhere, or
/// isn't one this side of the app receives.
String partnerLinkFor({required String side, required String type}) =>
    switch (side) {
      'trainer' => switch (type) {
        'trainer_client_request' ||
        'training_plan_accepted' ||
        'training_plan_declined' ||
        'training_plan_stopped' => 'clients',
        'trainer_booking_requested' ||
        'trainer_booking_confirmed' ||
        'trainer_booking_cancelled' => 'sessions',
        'trainer_enquiry' || 'trainer_interest' => 'enquiries',
        'trainer_payout_paid' => 'payouts',
        // FitFlex took down a home photo or logo (spec §44.3).
        partnerMediaTakenDownType when partnerMediaUi => 'brandMedia',
        _ => '',
      },
      'vendor' => switch (type) {
        'vendor_new_order' || 'vendor_order_cancelled' => 'orders',
        'vendor_customer_enquiry' => 'customerQuestions',
        'vendor_product_approved' || 'vendor_product_rejected' => 'products',
        'vendor_payout_paid' => 'payments',
        'vendor_low_stock' => 'lowStock',
        // S3: a walk-in sale was voided (sent to the vendor account).
        'vendor_sale_voided' => 'sale',
        // S4: the daily overdue digest, and a payment voided by staff.
        'vendor_customers_overdue' => 'owed',
        'vendor_customer_payment_voided' => 'customer',
        // S5: a KYC reviewer verified or did not accept the VAT details
        // (push data.open = 'tax').
        'vendor_vat_verified' || 'vendor_vat_rejected' => 'tax',
        // Shop home Phase 2 S1: a banner was approved, rejected, expired or
        // ended by FitFlex (push `vendor_shop_banner_*`, inbox
        // `shop_banner_*`).
        'vendor_shop_banner_approved' ||
        'vendor_shop_banner_rejected' ||
        'vendor_shop_banner_expired' ||
        'vendor_shop_banner_ended' ||
        'shop_banner_approved' ||
        'shop_banner_rejected' ||
        'shop_banner_expired' ||
        'shop_banner_ended' => 'merch',
        // Phase 2 S4: a flash sale was approved, rejected, expired or ended
        // by FitFlex (data `{saleId, open: merch, tab: sales, item}`).
        'vendor_flash_sale_approved' ||
        'vendor_flash_sale_rejected' ||
        'vendor_flash_sale_expired' ||
        'vendor_flash_sale_ended' => 'merchSale',
        // FitFlex took down a home photo or logo (spec §44.3).
        partnerMediaTakenDownType when partnerMediaUi => 'brandMedia',
        _ => '',
      },
      'gym' => switch (type) {
        'gym_checkin' => 'checkins',
        'gym_member_joined' => 'member',
        // A renewal is a payment: open what that member has paid.
        'gym_membership_renewed' => 'memberPayments',
        'gym_trainer_request' => 'gymTrainers',
        'gym_review' => 'gyms',
        'gym_statement_approved' || 'gym_payout_paid' => 'earnings',
        // FitFlex took down a home photo or logo (spec §44.3).
        partnerMediaTakenDownType when partnerMediaUi => 'brandMedia',
        _ => '',
      },
      _ => '',
    };

/// Where a partner's message (or a tap on its push) takes them. Null means
/// "show the message itself". Only fixed app screens; ids are checked.
String? partnerRouteFor({
  required String side,
  required String type,
  String? gymId,
  String? memberId,
  String? productId,
  String? variant,
  String? saleId,
  String? customerId,
  String? bannerId,
  String? flashSaleId,
}) {
  bool ok(String? id) => id != null && _safeId.hasMatch(id);
  return switch (partnerLinkFor(side: side, type: type)) {
    // Trainers and vendors work from one home screen: say which part.
    'clients' => '/trainer/home?open=clients',
    'sessions' => '/trainer/home?open=sessions',
    'enquiries' => '/trainer/home?open=enquiries',
    'payouts' => '/trainer/home?open=payouts',
    'orders' => '/vendor/home?open=orders',
    'customerQuestions' => '/vendor/home?open=enquiries',
    'products' => '/vendor/home?open=products',
    'payments' => '/vendor/home?open=payments',
    // Low stock: that product's stock history (the screen checks the ledger
    // is on and the person may see products); else the low products.
    'lowStock' when ok(productId) => Uri(
      path: '/vendor/products/$productId/stock',
      queryParameters: {
        if (variant != null && variant.isNotEmpty) 'variant': variant,
        'from': 'push',
      },
    ).toString(),
    'lowStock' => '/vendor/home?open=products&filter=low',
    // The sale detail checks the feature and the `sales` permission.
    'sale' when ok(saleId) => '/vendor/sales/$saleId',
    'sale' => '/vendor/home?open=sales',
    // The customer pages check the feature and the `customers` permission.
    'owed' => '/vendor/home?open=customers&view=owed',
    'customer' when ok(customerId) => '/vendor/customers/$customerId',
    'customer' => '/vendor/home?open=customers',
    // The page checks the `vat` tool and who may see it.
    'tax' => '/vendor/settings/tax',
    // The Promotions page checks the tool and the `products` permission.
    'merch' when ok(bannerId) => '/vendor/merch?item=$bannerId',
    'merch' => '/vendor/merch',
    'merchSale' when ok(flashSaleId) =>
      '/vendor/merch?tab=sales&item=$flashSaleId',
    'merchSale' => '/vendor/merch?tab=sales',
    'checkins' when ok(gymId) => '/owner/gyms/$gymId/checkins',
    'member' when ok(memberId) => '/owner/members/$memberId',
    'memberPayments' when ok(memberId) => '/owner/members/$memberId/payments',
    'gymTrainers' => '/owner/trainers',
    'gyms' => '/owner/gyms',
    'earnings' => '/owner/earnings',
    // Never the server's own `route`: the app builds it, ids checked. A gym
    // the person can't edit opens the page's "no access" state (§41.1).
    'brandMedia' when side == 'gym' =>
      ok(gymId) ? '/owner/brand-media?gymId=$gymId' : '/owner/brand-media',
    'brandMedia' when side == 'trainer' => '/trainer/brand-media',
    'brandMedia' => '/vendor/brand-media',
    _ => null,
  };
}

class InboxController extends ChangeNotifier {
  InboxController(this._api);

  final ApiClient _api;

  List<InboxMessage> _messages = const [];
  int _unread = 0;
  bool _loading = false;
  Object? _error;

  List<InboxMessage> get messages => _messages;
  int get unread => _unread;
  bool get loading => _loading;
  Object? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _api.notifications();
      _messages = ((res['notifications'] as List?) ?? const [])
          .map((n) => InboxMessage.fromJson((n as Map).cast()))
          .toList();
      _unread = (res['unread'] as num?)?.toInt() ?? 0;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Signed out: nothing from the last person may linger.
  void clear() {
    _messages = const [];
    _unread = 0;
    _error = null;
    notifyListeners();
  }

  InboxMessage? byId(String id) =>
      _messages.where((m) => m.id == id).firstOrNull;

  Future<void> markRead(String id) async {
    final m = byId(id);
    if (m != null && !m.unread) return;
    _setRead(id);
    try {
      await _api.markNotificationRead(id);
    } catch (_) {
      // Reading must never fail for the member; the server catches up.
    }
  }

  Future<void> markAllRead() async {
    _messages = [
      for (final m in _messages)
        m.unread ? m.copyWith(readAt: DateTime.now()) : m,
    ];
    _unread = 0;
    notifyListeners();
    try {
      await _api.markNotificationRead('all');
    } catch (_) {}
  }

  /// The member tapped the message's button (or its push).
  Future<void> click(String id, {String via = 'inbox'}) async {
    _setRead(id);
    try {
      await _api.clickNotification(id, via: via);
    } catch (_) {}
  }

  /// A push was tapped: records that the push was opened and its inbox
  /// copy read, and returns that copy (loading the inbox if needed). Null
  /// for a push with no inbox copy — the caller follows its link instead.
  Future<InboxMessage?> openFromPush(Map<String, dynamic> data) async {
    final messageId = data['messageId']?.toString() ?? '';
    if (data['source'] == 'communication' && messageId.isNotEmpty) {
      try {
        await _api.pushMessageOpened(messageId);
      } catch (_) {}
    }
    final id = data['notificationId']?.toString() ?? '';
    if (id.isEmpty) return null;
    if (byId(id) == null) await load();
    await markRead(id);
    return byId(id);
  }

  final Set<String> _answering = {};
  bool isAnswering(String id) => _answering.contains(id);

  /// Approve or reject a friend invitation from its card. Returns the
  /// invitation's status afterwards, or null if it couldn't be answered
  /// (the card then stays as it was and the member can retry).
  Future<String?> answerFriendInvitation(
    String id, {
    required bool approve,
  }) async {
    final m = byId(id);
    final invitationId = m?.invitationId;
    if (m == null || invitationId == null || _answering.contains(id)) {
      return null;
    }
    _answering.add(id);
    notifyListeners();
    try {
      final res = approve
          ? await _api.approveFriendInvitation(invitationId)
          : await _api.rejectFriendInvitation(invitationId);
      final status =
          ((res['invitation'] as Map?)?['status'] ??
                  (approve ? 'accepted' : 'rejected'))
              .toString();
      _setStatus(id, status);
      return status;
    } catch (e) {
      // Already answered elsewhere, expired, or withdrawn: show what is true now.
      final status = _statusFromError(e);
      if (status != null) {
        _setStatus(id, status);
        return status;
      }
      return null;
    } finally {
      _answering.remove(id);
      notifyListeners();
    }
  }

  static String? _statusFromError(Object e) {
    final code = e is ApiException ? e.code : null;
    for (final s in const ['accepted', 'rejected', 'expired', 'revoked']) {
      if (code == 'invitation_$s') return s;
    }
    return null;
  }

  void _setStatus(String id, String status) {
    final i = _messages.indexWhere((m) => m.id == id);
    if (i < 0) return;
    final wasUnread = _messages[i].unread;
    _messages = [..._messages]
      ..[i] = _messages[i].copyWith(
        readAt: DateTime.now(),
        data: {..._messages[i].data, 'status': status},
      );
    if (wasUnread && _unread > 0) _unread -= 1;
  }

  void _setRead(String id) {
    final i = _messages.indexWhere((m) => m.id == id && m.unread);
    if (i < 0) return;
    _messages = [..._messages]
      ..[i] = _messages[i].copyWith(readAt: DateTime.now());
    if (_unread > 0) _unread -= 1;
    notifyListeners();
  }
}
