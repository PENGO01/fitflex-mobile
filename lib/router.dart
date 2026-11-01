import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'shared/auth_state.dart';
import 'shared/held_nav_extras.dart';
import 'shared/inbox/inbox_controller.dart' show b2bMemberRequestsRoute;
import 'screens/splash_screen.dart';
import 'screens/route_status_pages.dart';
import 'screens/language_screen.dart';
import 'screens/role_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/pin_flows.dart' show StaffPinChangeScreen;
import 'screens/sign_up_screen.dart';
import 'screens/email_auth_screen.dart';
import 'screens/verify_email_screen.dart';
import 'shared/widgets/persona_switcher.dart';
import 'screens/member/member_activity_history_page.dart';
import 'screens/member/member_shell.dart';
import 'screens/member/member_training_offer_page.dart';
import 'screens/member/member_training_plan_page.dart';
import 'screens/member/member_training_setup_page.dart';
import 'shared/activity/activity.dart';
import 'screens/member/member_shop_tab.dart';
import 'screens/member/member_onboarding_page.dart';
import 'screens/member/member_privacy_page.dart';
import 'screens/member/member_community_page.dart';
import 'screens/member/member_group_page.dart';
import 'screens/member/member_person_page.dart';
import 'screens/member/member_shared_activity_page.dart';
import 'screens/member/member_record_run_page.dart';
import 'screens/member/member_run_detail_page.dart';
import 'screens/member/events/event_claim_page.dart';
import 'screens/member/events/event_team_page.dart';
import 'screens/member/events/member_event_detail_page.dart';
import 'screens/member/events/cancel/member_event_cancel_page.dart';
import 'screens/member/events/member_event_order_page.dart';
import 'screens/member/events/pay/member_event_payment_page.dart';
import 'screens/member/events/results/event_results_board_page.dart';
import 'screens/member/events/results/event_run_links_page.dart';
import 'screens/member/events/results/member_event_result_page.dart';
import 'screens/member/events/results/member_event_results_list_page.dart';
import 'screens/member/events/results/member_medals_page.dart';
import 'screens/member/events/results/member_reward_wallet_page.dart';
import 'screens/member/events/tickets/member_event_ticket_page.dart';
import 'screens/member/events/member_event_orders_page.dart';
import 'screens/member/events/member_event_registration_page.dart';
import 'screens/member/events/member_events_page.dart';
import 'screens/member/events/register/member_event_register_page.dart';
import 'shared/events/event_claim_link.dart';
import 'shared/events_flag.dart';
import 'screens/trainer/trainer_registration_page.dart';
import 'screens/trainer/trainer_home_page.dart';
import 'screens/owner/owner_registration_page.dart';
import 'screens/owner/owner_qr_scanner_page.dart';
import 'screens/owner/owner_shop_page.dart';
import 'screens/owner/owner_staff_page.dart';
import 'screens/owner/owner_shell.dart';
import 'screens/owner/members/members_list_page.dart';
import 'screens/owner/members/member_detail_page.dart';
import 'screens/owner/members/member_history_page.dart';
import 'screens/owner/communications/campaign_composer_page.dart';
import 'screens/owner/communications/campaign_detail_page.dart';
import 'screens/owner/communications/communication_center_page.dart';
import 'screens/owner/communications/template_pages.dart';
import 'screens/owner/communications/history_pages.dart';
import 'screens/owner/communications/automation_pages.dart';
import 'screens/member/member_benefits_page.dart';
import 'screens/member/member_requests_page.dart';
import 'screens/member/member_sessions_page.dart';
import 'screens/member/member_message_settings_page.dart';
import 'shared/friend_invites.dart';
import 'shared/inbox/inbox_pages.dart';
import 'screens/vendor/vendor_home_page.dart';
import 'screens/partner/partner_media_page.dart';
import 'shared/partner_media/partner_hero_builder.dart' show PartnerRouteWatch;
import 'shared/partner_media/partner_media_flag.dart';
import 'screens/vendor/stock/stock_history_page.dart';
import 'screens/vendor/merch/banner_form_route.dart';
import 'screens/vendor/merch/flash_sale_form_page.dart';
import 'screens/vendor/merch/vendor_merch_page.dart';
import 'screens/vendor/sales/pos_page.dart';
import 'screens/vendor/sales/receipt_page.dart';
import 'screens/vendor/sales/sale_detail_page.dart';
import 'screens/vendor/sales/sales_sync_page.dart';
import 'screens/vendor/sales/sales_widgets.dart' show salesIdPattern;
import 'screens/vendor/customers/customer_form_page.dart';
import 'screens/vendor/customers/customer_profile_page.dart';
import 'screens/vendor/customers/statement_page.dart';
import 'screens/vendor/customers/customers_widgets.dart' show customerIdPattern;
import 'screens/vendor/documents/document_view.dart';
import 'screens/vendor/settings/tax_details_page.dart';
import 'screens/vendor/reports/report_models.dart'
    show ReportSection, reportsHomeRoute;
import 'screens/vendor/reports/report_section_page.dart';
import 'screens/partner/verification/verification_center_page.dart';
import 'shared/widgets/invitations.dart';
import 'shared/pending_org_invite.dart';

/// Route path constants.
abstract class AppRoutes {
  static const splash = '/';

  /// Signed in but the account could not be loaded (see [StartupOfflinePage]).
  static const startupOffline = '/offline';
  static const language = '/language';
  static const role = '/role';
  static const auth = '/auth';
  static const signUp = '/auth/signup';
  static const emailAuth = '/auth/email';
  static const verifyEmail = '/auth/verify-email';
  static const personaPicker = '/personas';
  static const invitations = '/invitations';

  /// Verify-email step, carrying the role to retry with (sign-up only).
  static String verifyEmailFor(String? requestedRole) =>
      requestedRole == null || requestedRole.isEmpty
      ? verifyEmail
      : '$verifyEmail?role=${Uri.encodeQueryComponent(requestedRole)}';
  static const googleWebCallback = '/auth/google-web-callback';
  static const pending = '/pending';

  /// Gym staff choose their own PIN before anything else (the owner chose
  /// the one they signed in with; fitflex-functions#260).
  static const staffPinChange = '/staff/choose-pin';

  /// Partner KYC / KYB — open to partners while they wait for approval.
  static const verification = '/verification';
  static const home = '/home';

  // Trainer
  static const trainerRegistration = '/trainer/register';
  static const trainerHome = '/trainer/home';

  // Vendor
  static const vendorHome = '/vendor/home';

  /// Shop home Phase 2 S1: the vendor's Promotions (banner proposals).
  static const vendorMerch = '/vendor/merch';

  /// The banner form (its own address, so a refresh restores it).
  static const vendorMerchNew = '/vendor/merch/banner/new';
  static String vendorMerchEdit(String id) => '/vendor/merch/banner/$id/edit';

  /// Phase 2 S4: the flash sale form (its own address too).
  static const vendorMerchSaleNew = '/vendor/merch/sale/new';
  static String vendorMerchSaleEdit(String id) => '/vendor/merch/sale/$id/edit';

  /// Vendor tools · S1: one product's stock history.
  static String vendorStockHistory(String productId) =>
      '/vendor/products/$productId/stock';

  // Owner sub-routes (shell)
  static const ownerRegistration = '/owner/register';
  static const ownerHome = '/owner/home';
  static const ownerGyms = '/owner/gyms';
  static const ownerGymCheckins = '/owner/gyms/:gymId/checkins';
  static const ownerMembers = '/owner/members';
  static const ownerMemberDetail = '/owner/members/:memberId';
  static const ownerMemberCheckins = '/owner/members/:memberId/checkins';
  static const ownerMemberPayments = '/owner/members/:memberId/payments';
  static const inbox = '/inbox';

  /// The friend-invitation page; the token is kept on the device, never in
  /// the location.
  static const friendInvite = '/friend-invite';

  /// Links sent before the token moved to the fragment. Matched only to be
  /// redirected to [friendInvite] once the token is kept.
  static const friendInviteLegacy = '/friend-invite/:token';
  static const inboxMessage = '/inbox/:messageId';
  static const memberMessageSettings = '/member/message-settings';
  static const memberBenefits = '/member/benefits';

  /// Organisations asking to add the user by account id (accept / decline).
  static const memberRequests = b2bMemberRequestsRoute;
  static const memberSessions = '/member/sessions';
  static const ownerCommunications = '/owner/communications';
  static const ownerCampaignNew = '/owner/communications/new';
  static const ownerCampaignDetail =
      '/owner/communications/campaigns/:campaignId';
  static const ownerTemplateNew = '/owner/communications/templates/new';
  static const ownerTemplateDetail =
      '/owner/communications/templates/:templateId';
  static const ownerTemplateEdit =
      '/owner/communications/templates/:templateId/edit';
  static const ownerCampaignEdit =
      '/owner/communications/campaigns/:campaignId/edit';
  static const ownerCampaignRecipients =
      '/owner/communications/campaigns/:campaignId/recipients';
  static const ownerMemberMessages = '/owner/members/:memberId/messages';
  static const ownerAutomation =
      '/owner/communications/automations/:automationId';
  static const ownerTrainers = '/owner/trainers';
  static const ownerProfile = '/owner/profile';
  static const ownerQrScanner = '/owner/scan';
  static const ownerEarnings = '/owner/earnings';
  static const ownerShop = '/owner/shop';
  static const ownerStaff = '/owner/staff';

  /// Partner home photo and logo (PARTNER_MEDIA_UI, spec §41.1).
  static const ownerBrandMedia = '/owner/brand-media';
  static const trainerBrandMedia = '/trainer/brand-media';
  static const vendorBrandMedia = '/vendor/brand-media';

  // Member sub-routes (shell)
  static const memberOnboarding = '/member/onboarding';
  static const memberHome = '/member';
  static const memberActivity = '/member/activity';
  static const memberActivityLog = '/member/activity/log';
  static const memberActivityHistory = '/member/activity/history';
  static const memberRecordRun = '/member/activity/run';
  static const memberRunDetail = '/member/activity/runs/:activityId';
  static const memberProgress = '/member/activity/progress';
  static const memberWorkout = '/member/activity/workouts/:workoutId';
  static const memberTrainingPlan = '/member/activity/training';
  static const memberTrainingSetup = '/member/activity/training/setup';
  static const memberTrainingOffer =
      '/member/activity/training/offers/:offerId';
  static const memberChallenge = '/member/activity/challenges/:challengeId';
  static const memberGyms = '/member/gyms';
  static const memberGymDetail = '/member/gyms/:gymId';

  /// Running events (events S2 spec §11.1). Only registered with the
  /// `EVENTS_DISCOVERY` build flag on; off, they fall through to Not found.
  static const memberEvents = '/member/events';
  static const memberEventDetail = '/member/events/:eventId';

  /// Events S3 (spec §4): registration, orders, registrations, claims and
  /// teams. The static segments sit before `:eventId` so they never read as
  /// an event id.
  static const memberEventRegister = '/member/events/:eventId/register';
  static const memberEventOrders = '/member/events/orders';
  static const memberEventOrderDetail = '/member/events/orders/:orderId';
  static const memberEventRegistration =
      '/member/events/registrations/:registrationId';
  static const memberEventClaim = '/member/events/claim/:registrationId';

  /// Events S4 (spec §4): pay, tickets, ticket, cancel and refund.
  static const memberEventTickets = '/member/events/tickets';
  static const memberEventOrderPay = '/member/events/orders/:orderId/pay';
  static const memberEventOrderCancel = '/member/events/orders/:orderId/cancel';
  static const memberEventTicket =
      '/member/events/registrations/:registrationId/ticket';
  static const memberEventRegistrationCancel =
      '/member/events/registrations/:registrationId/cancel';
  static const memberEventTeam = '/member/events/teams/:teamId';

  /// Events S6 (spec §10.1): result, runs, board, medals, rewards. The
  /// static segments (`results`, `medals`, `rewards`) sit before `:eventId`.
  static const memberEventResult =
      '/member/events/registrations/:registrationId/result';
  static const memberEventRuns =
      '/member/events/registrations/:registrationId/runs';
  static const memberEventResults = '/member/events/:eventId/results';
  static const memberEventMyResults = '/member/events/results';
  static const memberEventMedals = '/member/events/medals';
  static const memberEventRewards = '/member/events/rewards';

  /// The claim-link page (`/event-claim/#<token>`); the token is kept on
  /// the device, never in the location. Sits beside [friendInvite].
  static const eventClaim = '/event-claim';
  static const eventClaimLegacy = '/event-claim/:token';

  static String memberEventDetailPath(String eventId) =>
      '/member/events/${Uri.encodeComponent(eventId)}';
  static String memberEventRegisterPath(String eventId, {String? ticket}) =>
      '/member/events/${Uri.encodeComponent(eventId)}/register'
      '${ticket == null ? '' : '?ticket=${Uri.encodeQueryComponent(ticket)}'}';
  static String memberEventOrder(String orderId) =>
      '/member/events/orders/${Uri.encodeComponent(orderId)}';
  static String memberEventRegistrationPath(String id) =>
      '/member/events/registrations/${Uri.encodeComponent(id)}';
  static String memberEventOrderPayPath(String orderId) =>
      '/member/events/orders/${Uri.encodeComponent(orderId)}/pay';
  static String memberEventOrderCancelPath(String orderId) =>
      '/member/events/orders/${Uri.encodeComponent(orderId)}/cancel';
  static String memberEventTicketPath(String registrationId) =>
      '/member/events/registrations/${Uri.encodeComponent(registrationId)}/ticket';
  static String memberEventRegistrationCancelPath(
    String registrationId, {
    String? orderId,
  }) =>
      '/member/events/registrations/${Uri.encodeComponent(registrationId)}/cancel'
      '${orderId == null || orderId.isEmpty ? '' : '?order=${Uri.encodeQueryComponent(orderId)}'}';
  static String memberEventResultPath(String registrationId) =>
      '/member/events/registrations/${Uri.encodeComponent(registrationId)}/result';
  static String memberEventRunsPath(String registrationId) =>
      '/member/events/registrations/${Uri.encodeComponent(registrationId)}/runs';
  static String memberEventResultsPath(String eventId) =>
      '/member/events/${Uri.encodeComponent(eventId)}/results';
  static String memberEventClaimPath(String id) =>
      '/member/events/claim/${Uri.encodeComponent(id)}';
  static String memberEventTeamPath(String id) =>
      '/member/events/teams/${Uri.encodeComponent(id)}';
  static const memberTrainers = '/member/trainers';
  static const memberTrainerDetail = '/member/trainers/:trainerId';
  static const memberQr = '/member/qr';
  static const memberShop = '/member/shop';
  static const memberProfile = '/member/profile';
  static const memberPasses = '/member/passes';
  static const memberPayment = '/member/payment';
  static const memberPrivacy = '/member/privacy';
  static const memberCommunity = '/member/community';
  static const memberSharedActivity =
      '/member/community/activities/:activityId';
  static const memberGroup = '/member/community/groups/:groupId';
  static const memberPerson = '/member/community/people/:userId';
  static const memberActivitySharing = '/member/privacy/activity-sharing';
}

bool _isOnboarded(AuthState auth, String role) {
  if (role == 'gym_operator') {
    // Gym owner must have at least 1 gym to be considered onboarded
    final gymIds = auth.user?['gymIds'];
    return gymIds is List && gymIds.isNotEmpty;
  }
  if (role == 'gym_staff') {
    // Staff accounts are created directly by their gym owner — always
    // fully onboarded, never self-register or await approval.
    return true;
  }
  if (role == 'trainer') {
    // Trainers are approved at once, so approval no longer says whether they
    // registered. The server marks onboardingCompleted when a trainer has a
    // profile (and claims one an admin made); without one they register.
    return auth.user?['onboardingCompleted'] == true;
  }
  // Member
  return auth.user?['onboardingCompleted'] == true;
}

/// A stock history path with a safe product id.
/// An event id or slug as a path segment (events S2).
final _safeEventId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// A gym id in a `/owner/brand-media?gymId=` link.
final _brandMediaGymId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

final _vendorStockPath = RegExp(
  r'^/vendor/products/[A-Za-z0-9_-]{1,64}/stock$',
);

/// Walk-in sales pages (S3). Pending vendors may sell too (Q-4).
final _vendorSalesPath = RegExp(
  r'^/vendor/sales/(new|sync|receipt/queued/[A-Za-z0-9._:-]{1,100}|receipt/[A-Za-z0-9._:-]{1,100}|[A-Za-z0-9._:-]{1,100})$',
);

/// Document pages (S5): tax details and my order invoice. Pending vendors
/// keep their own records too (§2.4).
final _vendorDocumentsPath = RegExp(
  r'^/vendor/(settings/tax|orders/[A-Za-z0-9._:-]{1,100}/invoice)$',
);

/// Promotions and the banner form (Phase 2 S1). Pending vendors see why
/// they cannot propose yet.
final _vendorMerchPath = RegExp(
  r'^/vendor/merch(/(banner|sale)/(new|[A-Za-z0-9_-]{1,64}/edit))?$',
);

/// Report pages (S6). Pending vendors see their own figures too (§11).
final _vendorReportsPath = RegExp(r'^/vendor/reports/[a-z]{1,20}$');

/// Customer pages (S4). Pending vendors keep their own records too.
final _vendorCustomersPath = RegExp(
  r'^/vendor/customers/(new|[A-Za-z0-9._:-]{1,100}(/edit|/statement|/sales/[A-Za-z0-9._:-]{1,100})?)$',
);

/// The inbox and one message (a tapped bell or push). Pending vendors get
/// FitFlex's messages too, and can choose which offers they get.
final _inboxPath = RegExp(r'^/inbox(/[A-Za-z0-9._:-]{1,100})?$');

String routeForSignedInUser(AuthState auth) {
  final route = _landingFor(auth);
  // An organisation invitation link opened before signing in comes first,
  // once the account is ready (onboarding / approval still win).
  if (PendingOrgInvite.hasPending &&
      !auth.isPendingApproval &&
      _homeRoutes.contains(route)) {
    return AppRoutes.invitations;
  }
  return route;
}

const _homeRoutes = {
  AppRoutes.memberHome,
  AppRoutes.trainerHome,
  AppRoutes.ownerHome,
  AppRoutes.vendorHome,
  AppRoutes.home,
};

/// The account could not be loaded and what this device kept would send the
/// person to setup or registration (or is missing): wait for the server
/// instead of guessing (H6). With a kept account that is already set up the
/// app opens as usual and its own offline banner takes over.
bool _waitForProfile(AuthState auth) {
  if (!auth.isSignedIn || !auth.profileUnconfirmed) return false;
  if (auth.user == null) return true;
  final role = auth.user?['userType']?.toString() ?? auth.role;
  return const {'member', 'trainer', 'gym_operator'}.contains(role) &&
      !_isOnboarded(auth, role);
}

String _landingFor(AuthState auth) {
  // Held to the PIN change: nothing else until it is done.
  if (auth.pinChangeRequired) return AppRoutes.staffPinChange;
  if (_waitForProfile(auth)) return AppRoutes.startupOffline;
  final role = auth.user?['userType']?.toString() ?? auth.role;
  final onboarded = _isOnboarded(auth, role);
  if (auth.isPendingApproval) {
    if (role == 'trainer' && !onboarded) {
      return AppRoutes.trainerRegistration;
    }
    if (role == 'gym_operator' && !onboarded) {
      return AppRoutes.ownerRegistration;
    }
    // A vendor waiting for approval can already add products.
    if (role == 'vendor') return AppRoutes.vendorHome;
    return AppRoutes.pending;
  }
  if (role == 'member') {
    return onboarded ? AppRoutes.memberHome : AppRoutes.memberOnboarding;
  }
  if (role == 'trainer') {
    return onboarded ? AppRoutes.trainerHome : AppRoutes.trainerRegistration;
  }
  if (role == 'gym_operator') {
    return onboarded ? AppRoutes.ownerHome : AppRoutes.ownerRegistration;
  }
  if (role == 'gym_staff') {
    // Staff reuse the owner shell, gated by their ACL permissions.
    return AppRoutes.ownerHome;
  }
  if (role == 'vendor' || role == 'vendor_staff') return AppRoutes.vendorHome;
  return AppRoutes.home;
}

/// The [EmailAuthArgs] a navigation carried, or null when there are none
/// (deep link, reload, browser history restore) or the contact is blank.
EmailAuthArgs? emailAuthArgsOf(GoRouterState state) {
  final extra = state.extra;
  if (extra is EmailAuthArgs && extra.contact.trim().isNotEmpty) return extra;
  return null;
}

/// GoRouter `extra` codec that keeps [EmailAuthArgs] (an email address or
/// phone number) in memory ([HeldNavExtras]). Browser history state only ever
/// holds a random opaque key; after a reload, sign-out or sign-in the key
/// resolves to nothing and the user starts again from sign-in. Other extras
/// keep GoRouter's default JSON behaviour (non-JSON values are dropped).
class EmailAuthExtraCodec extends Codec<Object?, Object?> {
  const EmailAuthExtraCodec();

  static const _memKey = 'ffMem';
  static const _jsonKey = 'ffJson';

  /// Forgets every held contact not shown by a mounted screen. Called on
  /// sign-out and after a successful sign-in or sign-up, so a later user
  /// pressing browser Back cannot see the previous user's contact.
  static void clear() => HeldNavExtras.clear();

  @override
  Converter<Object?, Object?> get encoder => const _EmailAuthExtraEncoder();

  @override
  Converter<Object?, Object?> get decoder => const _EmailAuthExtraDecoder();
}

class _EmailAuthExtraEncoder extends Converter<Object?, Object?> {
  const _EmailAuthExtraEncoder();

  @override
  Object? convert(Object? input) {
    if (input == null) return null;
    if (input is EmailAuthArgs) {
      return <String, Object?>{
        EmailAuthExtraCodec._memKey: HeldNavExtras.hold(input),
      };
    }
    try {
      return <String, Object?>{
        EmailAuthExtraCodec._jsonKey: json.encode(input),
      };
    } on JsonUnsupportedObjectError {
      return null;
    }
  }
}

class _EmailAuthExtraDecoder extends Converter<Object?, Object?> {
  const _EmailAuthExtraDecoder();

  @override
  Object? convert(Object? input) {
    if (input is! Map) return null;
    final key = input[EmailAuthExtraCodec._memKey];
    if (key is String) {
      final held = HeldNavExtras.lookup(key);
      return held is EmailAuthArgs ? held : null;
    }
    final encoded = input[EmailAuthExtraCodec._jsonKey];
    if (encoded is String) return json.decode(encoded);
    return null;
  }
}

/// Keeps the held [args] while the email/phone screen is mounted (so an
/// auth-state refresh or a mid-flow sign-out still finds it) and forgets
/// them once the screen is disposed.
class _HoldEmailAuthArgs extends StatefulWidget {
  const _HoldEmailAuthArgs({required this.args});

  final EmailAuthArgs args;

  @override
  State<_HoldEmailAuthArgs> createState() => _HoldEmailAuthArgsState();
}

class _HoldEmailAuthArgsState extends State<_HoldEmailAuthArgs> {
  @override
  void initState() {
    super.initState();
    HeldNavExtras.pin(widget.args);
  }

  @override
  void didUpdateWidget(_HoldEmailAuthArgs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.args, widget.args)) {
      HeldNavExtras.pin(widget.args);
      HeldNavExtras.release(oldWidget.args);
    }
  }

  @override
  void dispose() {
    HeldNavExtras.release(widget.args);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EmailAuthScreen(
    initialEmail: widget.args.contact,
    initialMode: widget.args.mode,
  );
}

/// Shown for a moment when the email/phone screen is opened without its
/// in-memory args (reload, history restore): sends the user to sign-in.
class _BackToSignIn extends StatefulWidget {
  const _BackToSignIn();

  @override
  State<_BackToSignIn> createState() => _BackToSignInState();
}

class _BackToSignInState extends State<_BackToSignIn> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(AppRoutes.auth);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

GoRouter buildRouter(AuthState auth) {
  // PARTNER_MEDIA_UI: lets partner homes know when a page over them closes
  // (spec §40.1). Not registered with the flag off.
  final partnerPages = partnerMediaUi
      ? (PartnerRouteWatch.root = PartnerRouteWatch())
      : null;
  return GoRouter(
    initialLocation: AppRoutes.splash,
    observers: [?partnerPages],
    extraCodec: const EmailAuthExtraCodec(),
    debugLogDiagnostics: false,
    refreshListenable: auth,
    redirect: (context, state) {
      final loggedIn = auth.isSignedIn;
      final isPending = auth.isPendingApproval;
      final loc = state.matchedLocation;

      // Splash controls its own transition; skip auth redirects while showing.
      if (loc == AppRoutes.splash) return null;

      // Public routes that don't need auth
      final publicRoutes = [
        AppRoutes.language,
        AppRoutes.role,
        AppRoutes.auth,
        AppRoutes.signUp,
        AppRoutes.emailAuth,
        AppRoutes.verifyEmail,
        AppRoutes.googleWebCallback,
      ];

      // A friend-invitation link (`/friend-invite/#tok`, a full
      // `https://…/friend-invite/#tok` from an Android App Link, or a legacy
      // `/friend-invite/tok`): keep the token on the device and open the
      // page without it, so it stays out of the location and history. A
      // malformed token drops any earlier kept one, so the page says the
      // link is not valid.
      final friendLink = friendInviteLinkFrom(state.uri);
      if (friendLink != null) {
        showFriendInviteWithoutToken();
        final token = friendLink.token;
        return (token == null
                ? PendingFriendInvite.clear()
                : PendingFriendInvite.save(token))
            .then((_) => AppRoutes.friendInvite);
      }
      // Gym staff held to choosing their own PIN (fitflex-functions#260):
      // that screen only — no scanner, check-ins or anything else — until
      // the PIN is changed or they sign out.
      if (loggedIn && auth.pinChangeRequired) {
        return loc == AppRoutes.staffPinChange
            ? null
            : AppRoutes.staffPinChange;
      }
      if (loc == AppRoutes.staffPinChange) {
        return loggedIn ? routeForSignedInUser(auth) : AppRoutes.language;
      }

      // The invitation page opens for anyone; the token is kept through
      // sign-in.
      if (loc == AppRoutes.friendInvite || loc.startsWith('/friend-invite/')) {
        return null;
      }

      // An event claim link (events S3 §3.7, §5.11): the same pattern as a
      // friend invitation. The token is kept even while registration is
      // off, so a link opened before the flag flips still works (§4).
      final claimLink = eventClaimLinkFrom(state.uri);
      if (claimLink != null) {
        showEventClaimWithoutToken();
        final token = claimLink.token;
        return (token == null
                ? PendingEventClaim.clear()
                : PendingEventClaim.save(token))
            .then((_) => AppRoutes.eventClaim);
      }
      if (loc == AppRoutes.eventClaim || loc.startsWith('/event-claim/')) {
        return null;
      }

      // An organisation invitation link: keep its token on the device and
      // drop it from the address (and history), then route as usual.
      if (loc == AppRoutes.invitations) {
        final token = state.uri.queryParameters['token'];
        if (token != null && token.isNotEmpty) {
          showInvitationsWithoutToken();
          return PendingOrgInvite.save(
            token,
          ).then((_) => AppRoutes.invitations);
        }
      }

      if (!loggedIn && !publicRoutes.contains(loc)) {
        return AppRoutes.language;
      }

      // Never onboarding on the strength of a failed /me (H6).
      if (_waitForProfile(auth)) {
        return loc == AppRoutes.startupOffline
            ? null
            : AppRoutes.startupOffline;
      }
      if (loc == AppRoutes.startupOffline) return routeForSignedInUser(auth);

      // Identity V2: several personas and none used last — ask first.
      if (loggedIn && auth.personaChoiceRequired) {
        return loc == AppRoutes.personaPicker ? null : AppRoutes.personaPicker;
      }
      if (loc == AppRoutes.personaPicker && loggedIn) {
        return routeForSignedInUser(auth);
      }

      // Trainer/Owner: redirect to registration if onboarding not done, even while pending
      if (loggedIn && isPending) {
        final role = auth.user?['userType']?.toString() ?? auth.role;
        final onboarded = _isOnboarded(auth, role);
        if (role == 'trainer' &&
            !onboarded &&
            loc != AppRoutes.trainerRegistration) {
          return AppRoutes.trainerRegistration;
        }
        if (role == 'gym_operator' &&
            !onboarded &&
            loc != AppRoutes.ownerRegistration) {
          return AppRoutes.ownerRegistration;
        }
        if (role == 'vendor') {
          // Vendors work on products while FitFlex verifies them; the
          // verification centre is the only other place they need.
          if (loc == AppRoutes.vendorHome ||
              loc == AppRoutes.verification ||
              // Shows why proposing waits for approval.
              _vendorMerchPath.hasMatch(loc) ||
              _vendorStockPath.hasMatch(loc) ||
              _vendorSalesPath.hasMatch(loc) ||
              _vendorCustomersPath.hasMatch(loc) ||
              _vendorDocumentsPath.hasMatch(loc) ||
              _vendorReportsPath.hasMatch(loc) ||
              _inboxPath.hasMatch(loc) ||
              // Their own home photo and logo (spec §41.3: allowed while
              // pending).
              (partnerMediaUi && loc == AppRoutes.vendorBrandMedia) ||
              loc == AppRoutes.memberMessageSettings) {
            return null;
          }
          return AppRoutes.vendorHome;
        }
        if (loc != AppRoutes.pending &&
            loc != AppRoutes.verification &&
            loc != AppRoutes.trainerRegistration &&
            loc != AppRoutes.ownerRegistration &&
            loc != AppRoutes.ownerProfile) {
          return AppRoutes.pending;
        }
        return null;
      }

      if (loggedIn && !isPending && publicRoutes.contains(loc)) {
        return routeForSignedInUser(auth);
      }

      // Redirect member to onboarding if not completed
      if (loggedIn && !isPending) {
        final role = auth.user?['userType']?.toString() ?? auth.role;
        final onboarded = _isOnboarded(auth, role);
        if (role == 'member' &&
            !onboarded &&
            loc != AppRoutes.memberOnboarding) {
          return AppRoutes.memberOnboarding;
        }
        if (role == 'trainer' &&
            !onboarded &&
            loc != AppRoutes.trainerRegistration) {
          return AppRoutes.trainerRegistration;
        }
        if (role == 'gym_operator' &&
            !onboarded &&
            loc != AppRoutes.ownerRegistration) {
          return AppRoutes.ownerRegistration;
        }
      }

      return null;
    },
    // An address that matches no page gets a translated page with a way
    // home, not go_router's raw "GoException" text (D7).
    errorBuilder: (context, state) => const NotFoundPage(),
    routes: [
      GoRoute(
        path: AppRoutes.startupOffline,
        name: 'startupOffline',
        builder: (context, state) => const StartupOfflinePage(),
      ),
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.language,
        name: 'language',
        builder: (context, state) => const LanguageScreen(),
      ),
      GoRoute(
        path: AppRoutes.role,
        name: 'role',
        builder: (context, state) => const RoleScreen(),
      ),
      GoRoute(
        path: AppRoutes.auth,
        name: 'auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        name: 'signUp',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SignUpScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.05),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  ),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                ),
                child: child,
              ),
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.emailAuth,
        name: 'emailAuth',
        // The contact comes only from in-memory `extra` (never the URL). A
        // deep link, reload or history restore has none: back to sign-in.
        redirect: (context, state) =>
            emailAuthArgsOf(state) == null ? AppRoutes.auth : null,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          // Restored history entries skip route redirects, so check again.
          child: emailAuthArgsOf(state) == null
              ? const _BackToSignIn()
              : _HoldEmailAuthArgs(args: emailAuthArgsOf(state)!),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.05),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  ),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                ),
                child: child,
              ),
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.invitations,
        name: 'invitations',
        builder: (context, state) =>
            InvitationsScreen(token: state.uri.queryParameters['token']),
      ),
      GoRoute(
        path: AppRoutes.personaPicker,
        name: 'personaPicker',
        builder: (context, state) => const PersonaPickerScreen(),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        name: 'verifyEmail',
        builder: (context, state) =>
            VerifyEmailScreen(requestedRole: state.uri.queryParameters['role']),
      ),
      GoRoute(
        path: AppRoutes.googleWebCallback,
        name: 'googleWebCallback',
        builder: (context, state) => const GoogleWebCallbackScreen(),
      ),
      GoRoute(
        path: AppRoutes.staffPinChange,
        name: 'staffPinChange',
        builder: (context, state) => const StaffPinChangeScreen(),
      ),
      GoRoute(
        path: AppRoutes.pending,
        name: 'pending',
        builder: (context, state) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: AppRoutes.verification,
        name: 'verification',
        builder: (context, state) => const VerificationCenterPage(),
      ),
      GoRoute(
        path: AppRoutes.memberOnboarding,
        name: 'memberOnboarding',
        builder: (context, state) => const MemberOnboardingPage(),
      ),
      // Trainer routes
      GoRoute(
        path: AppRoutes.trainerRegistration,
        name: 'trainerRegistration',
        builder: (context, state) => const TrainerRegistrationPage(),
      ),
      GoRoute(
        path: AppRoutes.trainerHome,
        name: 'trainerHome',
        builder: (context, state) =>
            TrainerHomePage(open: state.uri.queryParameters['open']),
      ),
      GoRoute(
        path: AppRoutes.vendorHome,
        name: 'vendorHome',
        builder: (context, state) => VendorHomePage(
          open: state.uri.queryParameters['open'],
          filter: state.uri.queryParameters['filter'],
          view: state.uri.queryParameters['view'],
        ),
      ),
      // Partner home photo and logo (spec §41.1). With the build flag off the
      // routes do not exist.
      if (partnerMediaUi) ...[
        GoRoute(
          path: AppRoutes.ownerBrandMedia,
          name: 'ownerBrandMedia',
          builder: (context, state) {
            final gymId = state.uri.queryParameters['gymId'];
            return PartnerMediaPage(
              side: 'gym',
              gymId: gymId != null && _brandMediaGymId.hasMatch(gymId)
                  ? gymId
                  : null,
            );
          },
        ),
        GoRoute(
          path: AppRoutes.trainerBrandMedia,
          name: 'trainerBrandMedia',
          builder: (context, state) => const PartnerMediaPage(side: 'trainer'),
        ),
        GoRoute(
          path: AppRoutes.vendorBrandMedia,
          name: 'vendorBrandMedia',
          builder: (context, state) => const PartnerMediaPage(side: 'vendor'),
        ),
      ],
      // Shop home Phase 2 S1: the page checks the tool (merch.banners) and
      // the `products` permission itself.
      // Phase 2 S4: "Flash sales | Banners" (`?tab=sales|banners`); with
      // flash sales off it is the banners page as before.
      GoRoute(
        path: AppRoutes.vendorMerch,
        name: 'vendorMerch',
        builder: (context, state) => VendorMerchPage(
          tab: state.uri.queryParameters['tab'],
          item: state.uri.queryParameters['item'],
        ),
      ),
      GoRoute(
        path: AppRoutes.vendorMerchSaleNew,
        name: 'vendorMerchSaleNew',
        builder: (context, state) => VendorFlashSaleFormRoute(
          copyId: state.uri.queryParameters['copy'],
          productId: state.uri.queryParameters['productId'],
        ),
      ),
      GoRoute(
        path: '/vendor/merch/sale/:saleId/edit',
        name: 'vendorMerchSaleEdit',
        redirect: (context, state) =>
            RegExp(
              r'^[A-Za-z0-9_-]{1,64}$',
            ).hasMatch(state.pathParameters['saleId'] ?? '')
            ? null
            : '${AppRoutes.vendorMerch}?tab=sales',
        builder: (context, state) =>
            VendorFlashSaleFormRoute(saleId: state.pathParameters['saleId']),
      ),
      GoRoute(
        path: AppRoutes.vendorMerchNew,
        name: 'vendorMerchNew',
        builder: (context, state) =>
            VendorBannerFormRoute(copyId: state.uri.queryParameters['copy']),
      ),
      GoRoute(
        path: '/vendor/merch/banner/:bannerId/edit',
        name: 'vendorMerchEdit',
        redirect: (context, state) =>
            RegExp(
              r'^[A-Za-z0-9_-]{1,64}$',
            ).hasMatch(state.pathParameters['bannerId'] ?? '')
            ? null
            : AppRoutes.vendorMerch,
        builder: (context, state) =>
            VendorBannerFormRoute(bannerId: state.pathParameters['bannerId']),
      ),
      // Vendor customers (S4). Each page checks the feature and the
      // `customers` permission itself; `new` comes before `:customerId`.
      GoRoute(
        path: '/vendor/customers/new',
        name: 'vendorCustomerNew',
        builder: (context, state) => const CustomerFormPage(),
      ),
      GoRoute(
        path: '/vendor/customers/:customerId',
        name: 'vendorCustomer',
        redirect: (context, state) =>
            customerIdPattern.hasMatch(state.pathParameters['customerId'] ?? '')
            ? null
            : '${AppRoutes.vendorHome}?open=customers',
        builder: (context, state) {
          final extra = state.extra;
          final dup = extra is Map && extra['phoneDuplicate'] is Map
              ? Map<String, dynamic>.from(extra['phoneDuplicate'] as Map)
              : null;
          // Keyed by id: another customer is a fresh page (UAT D1).
          return CustomerProfilePage(
            key: ValueKey('customer-${state.pathParameters['customerId']}'),
            customerId: state.pathParameters['customerId']!,
            phoneDuplicate: dup,
          );
        },
        routes: [
          GoRoute(
            path: 'edit',
            name: 'vendorCustomerEdit',
            builder: (context, state) => CustomerFormPage(
              customerId: state.pathParameters['customerId'],
            ),
          ),
          // A sale from the customer's profile: the customer gate, read
          // through the customer-scoped endpoint; Share / Void only for
          // people who also have `sales`.
          GoRoute(
            path: 'sales/:saleId',
            name: 'vendorCustomerSale',
            redirect: (context, state) =>
                salesIdPattern.hasMatch(state.pathParameters['saleId'] ?? '')
                ? null
                : '${AppRoutes.vendorHome}?open=customers',
            builder: (context, state) => SaleDetailPage(
              saleId: state.pathParameters['saleId']!,
              customerId: state.pathParameters['customerId'],
            ),
          ),
          GoRoute(
            path: 'statement',
            name: 'vendorCustomerStatement',
            builder: (context, state) =>
                StatementPage(customerId: state.pathParameters['customerId']!),
          ),
        ],
      ),
      GoRoute(
        path: '/vendor/products/:productId/stock',
        name: 'vendorStockHistory',
        redirect: (context, state) => _vendorStockPath.hasMatch(state.uri.path)
            ? null
            : '${AppRoutes.vendorHome}?open=products&filter=low',
        builder: (context, state) {
          final variant = state.uri.queryParameters['variant'];
          return StockHistoryPage(
            productId: state.pathParameters['productId']!,
            variant: variant == null || variant.isEmpty ? null : variant,
            fromPush: state.uri.queryParameters['from'] == 'push',
          );
        },
      ),
      // Vendor reports (S6). The page checks the tool (`reports`) and the
      // person's rights itself; an unknown section opens Reports home.
      GoRoute(
        path: '/vendor/reports/:section',
        name: 'vendorReportSection',
        redirect: (context, state) =>
            ReportSection.ofRoute(state.pathParameters['section']) == null
            ? reportsHomeRoute
            : null,
        builder: (context, state) {
          final q = state.uri.queryParameters;
          return ReportSectionPage(
            key: ValueKey('report-${state.uri}'),
            section: ReportSection.ofRoute(state.pathParameters['section'])!,
            from: q['from'],
            to: q['to'],
            channel: q['channel'],
          );
        },
      ),
      // Vendor documents and VAT (S5). Each page checks its feature
      // (`documents` / `vat`) and permission itself.
      GoRoute(
        path: vendorTaxRoute,
        name: 'vendorTaxDetails',
        builder: (context, state) => const TaxDetailsPage(),
      ),
      GoRoute(
        path: '/vendor/orders/:orderId/invoice',
        name: 'vendorOrderInvoice',
        redirect: (context, state) =>
            documentIdPattern.hasMatch(state.pathParameters['orderId'] ?? '')
            ? null
            : '${AppRoutes.vendorHome}?open=orders',
        builder: (context, state) =>
            VendorOrderInvoicePage(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(
        path: '/shop/orders/:orderId/invoice',
        name: 'shopOrderInvoice',
        redirect: (context, state) =>
            documentIdPattern.hasMatch(state.pathParameters['orderId'] ?? '')
            ? null
            : AppRoutes.memberShop,
        builder: (context, state) {
          final vendor = state.uri.queryParameters['vendor'];
          return BuyerInvoicePage(
            key: ValueKey('buyer-invoice-${state.uri}'),
            orderId: state.pathParameters['orderId']!,
            vendorId: vendor != null && documentIdPattern.hasMatch(vendor)
                ? vendor
                : null,
          );
        },
      ),
      // Vendor walk-in sales (S3). Each page checks the feature and the
      // `sales` permission itself; `new` and `sync` come before `:saleId`.
      GoRoute(
        path: '/vendor/sales/new',
        name: 'vendorPos',
        builder: (context, state) => const PosPage(),
      ),
      GoRoute(
        path: '/vendor/sales/sync',
        name: 'vendorSalesSync',
        builder: (context, state) => const SalesSyncPage(),
      ),
      GoRoute(
        path: '/vendor/sales/receipt/queued/:clientRef',
        name: 'vendorQueuedReceipt',
        redirect: (context, state) =>
            salesIdPattern.hasMatch(state.pathParameters['clientRef'] ?? '')
            ? null
            : '${AppRoutes.vendorHome}?open=sales',
        builder: (context, state) =>
            SaleReceiptPage(clientRef: state.pathParameters['clientRef']),
      ),
      GoRoute(
        path: '/vendor/sales/receipt/:saleId',
        name: 'vendorSaleReceipt',
        redirect: (context, state) =>
            salesIdPattern.hasMatch(state.pathParameters['saleId'] ?? '')
            ? null
            : '${AppRoutes.vendorHome}?open=sales',
        builder: (context, state) => SaleReceiptPage(
          saleId: state.pathParameters['saleId'],
          sale: state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : null,
        ),
      ),
      GoRoute(
        path: '/vendor/sales/:saleId',
        name: 'vendorSaleDetail',
        redirect: (context, state) =>
            salesIdPattern.hasMatch(state.pathParameters['saleId'] ?? '')
            ? null
            : '${AppRoutes.vendorHome}?open=sales',
        builder: (context, state) =>
            SaleDetailPage(saleId: state.pathParameters['saleId']!),
      ),
      // Owner routes
      GoRoute(
        path: AppRoutes.ownerRegistration,
        name: 'ownerRegistration',
        builder: (context, state) => const OwnerRegistrationPage(),
      ),
      GoRoute(
        path: AppRoutes.ownerQrScanner,
        name: 'ownerQrScanner',
        builder: (context, state) => const OwnerQrScannerPage(),
      ),
      GoRoute(
        path: AppRoutes.ownerEarnings,
        name: 'ownerEarnings',
        builder: (context, state) => const OwnerEarningsPage(),
      ),
      GoRoute(
        path: AppRoutes.ownerStaff,
        name: 'ownerStaff',
        builder: (context, state) => const OwnerStaffPage(),
      ),
      GoRoute(
        path: AppRoutes.ownerGymCheckins,
        name: 'ownerGymCheckins',
        builder: (context, state) {
          final gymId = state.pathParameters['gymId']!;
          return OwnerCheckinsPage(gymId: gymId);
        },
      ),
      GoRoute(
        path: AppRoutes.ownerProfile,
        name: 'ownerProfile',
        builder: (context, state) => const OwnerProfilePage(),
      ),
      GoRoute(
        path: AppRoutes.ownerMemberDetail,
        name: 'ownerMemberDetail',
        builder: (context, state) =>
            MemberDetailPage(memberId: state.pathParameters['memberId']!),
      ),
      GoRoute(
        path: AppRoutes.ownerMemberCheckins,
        name: 'ownerMemberCheckins',
        builder: (context, state) => MemberHistoryPage(
          memberId: state.pathParameters['memberId']!,
          kind: MemberHistoryKind.checkins,
        ),
      ),
      GoRoute(
        path: AppRoutes.ownerMemberPayments,
        name: 'ownerMemberPayments',
        builder: (context, state) => MemberHistoryPage(
          memberId: state.pathParameters['memberId']!,
          kind: MemberHistoryKind.payments,
        ),
      ),
      // The member's messages from this gym (communication history).
      GoRoute(
        path: AppRoutes.ownerMemberMessages,
        name: 'ownerMemberMessages',
        builder: (context, state) => MemberCommunicationsPage(
          memberId: state.pathParameters['memberId']!,
        ),
      ),
      // Inbox — every signed-in role's messages.
      GoRoute(
        path: AppRoutes.friendInvite,
        builder: (context, state) => const FriendInvitePage(),
      ),
      // Never shown: the redirect keeps the token and moves on.
      GoRoute(
        path: AppRoutes.friendInviteLegacy,
        builder: (context, state) => const FriendInvitePage(),
      ),
      // Events S3: a claim link's page (pre-sign-in capable, like
      // /friend-invite). Registered regardless of the build flag so a kept
      // token is honoured once the feature is on.
      GoRoute(
        path: AppRoutes.eventClaim,
        name: 'eventClaim',
        builder: (context, state) => const EventClaimPage.link(),
      ),
      GoRoute(
        path: AppRoutes.eventClaimLegacy,
        builder: (context, state) => const EventClaimPage.link(),
      ),
      GoRoute(
        path: AppRoutes.inbox,
        name: 'inbox',
        builder: (context, state) => const InboxPage(),
      ),
      GoRoute(
        path: AppRoutes.inboxMessage,
        name: 'inboxMessage',
        builder: (context, state) =>
            InboxMessagePage(messageId: state.pathParameters['messageId']!),
      ),
      GoRoute(
        path: AppRoutes.memberMessageSettings,
        name: 'memberMessageSettings',
        builder: (context, state) => const MemberMessageSettingsPage(),
      ),
      GoRoute(
        path: AppRoutes.memberBenefits,
        name: 'memberBenefits',
        builder: (context, state) => const MemberBenefitsPage(),
      ),
      GoRoute(
        path: AppRoutes.memberRequests,
        name: 'memberRequests',
        builder: (context, state) => const MemberRequestsPage(),
      ),
      GoRoute(
        path: AppRoutes.memberSessions,
        name: 'memberSessions',
        builder: (context, state) => MemberSessionsPage(
          focusBookingId: state.uri.queryParameters['booking'],
        ),
      ),
      // Message templates. "new" comes before ":templateId" so it wins.
      GoRoute(
        path: AppRoutes.ownerTemplateNew,
        name: 'ownerTemplateNew',
        builder: (context, state) =>
            TemplateEditorPage(gymId: state.uri.queryParameters['gymId']),
      ),
      GoRoute(
        path: AppRoutes.ownerTemplateDetail,
        name: 'ownerTemplateDetail',
        builder: (context, state) => TemplateDetailPage(
          templateId: state.pathParameters['templateId']!,
          gymId: state.uri.queryParameters['gymId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.ownerTemplateEdit,
        name: 'ownerTemplateEdit',
        builder: (context, state) => TemplateEditorPage(
          templateId: state.pathParameters['templateId'],
          gymId: state.uri.queryParameters['gymId'],
        ),
      ),
      // Communication Center — messages to the gym's direct members.
      GoRoute(
        path: AppRoutes.ownerCommunications,
        name: 'ownerCommunications',
        builder: (context, state) =>
            CommunicationCenterPage(gymId: state.uri.queryParameters['gymId']),
      ),
      GoRoute(
        path: AppRoutes.ownerCampaignNew,
        name: 'ownerCampaignNew',
        builder: (context, state) => CampaignComposerPage(
          gymId: state.uri.queryParameters['gymId'],
          templateId: state.uri.queryParameters['templateId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.ownerCampaignDetail,
        name: 'ownerCampaignDetail',
        builder: (context, state) =>
            CampaignDetailPage(campaignId: state.pathParameters['campaignId']!),
      ),
      GoRoute(
        path: AppRoutes.ownerCampaignEdit,
        name: 'ownerCampaignEdit',
        builder: (context, state) => CampaignComposerPage(
          campaignId: state.pathParameters['campaignId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.ownerAutomation,
        name: 'ownerAutomation',
        builder: (context, state) => AutomationDetailPage(
          automationId: state.pathParameters['automationId']!,
          gymId: state.uri.queryParameters['gymId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.ownerCampaignRecipients,
        name: 'ownerCampaignRecipients',
        builder: (context, state) => CampaignRecipientsPage(
          campaignId: state.pathParameters['campaignId']!,
        ),
      ),
      // Owner shell with bottom nav
      ShellRoute(
        builder: (context, state, child) =>
            OwnerShell(state: state, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.ownerHome,
            name: 'ownerHome',
            builder: (context, state) => const OwnerHomeTab(),
          ),
          GoRoute(
            path: AppRoutes.ownerGyms,
            name: 'ownerGyms',
            builder: (context, state) => const OwnerManageGymsPage(),
          ),
          GoRoute(
            path: AppRoutes.ownerMembers,
            name: 'ownerMembers',
            builder: (context, state) => const OwnerMembersPage(),
          ),
          GoRoute(
            path: AppRoutes.ownerShop,
            name: 'ownerShop',
            builder: (context, state) => const OwnerShopPage(),
          ),
          // Reached from Home (and inbox deep links); not a bottom tab.
          GoRoute(
            path: AppRoutes.ownerTrainers,
            name: 'ownerTrainers',
            builder: (context, state) => const OwnerTrainersPage(),
          ),
        ],
      ),
      // Member shell with bottom nav
      ShellRoute(
        builder: (context, state, child) =>
            MemberShell(state: state, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.memberHome,
            name: 'memberHome',
            builder: (context, state) => const MemberHomeTab(),
          ),
          GoRoute(
            path: AppRoutes.memberActivity,
            name: 'memberActivity',
            builder: (context, state) => const MemberActivityTab(),
            routes: [
              GoRoute(
                path: 'progress',
                name: 'memberProgress',
                builder: (context, state) =>
                    const MemberActivityTab(initialSection: 'progress'),
              ),
              GoRoute(
                path: 'run',
                name: 'memberRecordRun',
                builder: (context, state) => MemberRecordRunPage(
                  eventRegistrationId:
                      state.uri.queryParameters['registration'],
                ),
              ),
              GoRoute(
                path: 'runs/:activityId',
                name: 'memberRunDetail',
                builder: (context, state) => MemberRunDetailPage(
                  activityId: state.pathParameters['activityId']!,
                ),
              ),
              GoRoute(
                path: 'history',
                name: 'memberActivityHistory',
                builder: (context, state) => const MemberActivityHistoryPage(),
              ),
              GoRoute(
                path: 'log',
                name: 'memberActivityLog',
                builder: (context, state) => MemberLogActivityPage(
                  initialType: ActivityType.values
                      .where((t) => t.wire == state.uri.queryParameters['type'])
                      .firstOrNull,
                  gymId: state.uri.queryParameters['gymId'],
                  startedAt: DateTime.tryParse(
                    state.uri.queryParameters['at'] ?? '',
                  ),
                ),
              ),
              GoRoute(
                path: 'challenges/:challengeId',
                name: 'memberChallenge',
                builder: (context, state) => MemberChallengePage(
                  challengeId: state.pathParameters['challengeId']!,
                ),
              ),
              GoRoute(
                path: 'training',
                name: 'memberTrainingPlan',
                builder: (context, state) => const MemberTrainingPlanPage(),
                routes: [
                  GoRoute(
                    path: 'offers/:offerId',
                    name: 'memberTrainingOffer',
                    builder: (context, state) => MemberTrainingOfferPage(
                      offerId: state.pathParameters['offerId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'setup',
                    name: 'memberTrainingSetup',
                    builder: (context, state) =>
                        const MemberTrainingSetupPage(),
                  ),
                ],
              ),
              GoRoute(
                path: 'workouts/:workoutId',
                name: 'memberWorkout',
                builder: (context, state) => MemberWorkoutPage(
                  workoutId: state.pathParameters['workoutId']!,
                ),
              ),
            ],
          ),
          // Events S2 (spec §11.1): a section of Activity with its own
          // full-page list and detail, inside the shell so the bottom nav
          // stays. With the build flag off the routes do not exist.
          if (eventsDiscoveryEnabled)
            GoRoute(
              path: AppRoutes.memberEvents,
              name: 'memberEvents',
              builder: (context, state) => const MemberEventsPage(),
              routes: [
                // Events S3 (spec §4). Static segments first.
                GoRoute(
                  path: 'orders',
                  name: 'memberEventOrders',
                  builder: (context, state) => MemberEventOrdersPage(
                    initialTab: state.uri.queryParameters['tab'] ?? '',
                  ),
                  routes: [
                    GoRoute(
                      path: ':orderId',
                      name: 'memberEventOrder',
                      redirect: (context, state) =>
                          _safeEventId.hasMatch(
                            state.pathParameters['orderId'] ?? '',
                          )
                          ? null
                          : AppRoutes.memberEventOrders,
                      builder: (context, state) => MemberEventOrderPage(
                        orderId: state.pathParameters['orderId']!,
                      ),
                      routes: [
                        // Events S4 (spec §4).
                        GoRoute(
                          path: 'pay',
                          name: 'memberEventOrderPay',
                          builder: (context, state) => MemberEventPaymentPage(
                            orderId: state.pathParameters['orderId']!,
                          ),
                        ),
                        GoRoute(
                          path: 'cancel',
                          name: 'memberEventOrderCancel',
                          builder: (context, state) =>
                              MemberEventCancelPage.order(
                                orderId: state.pathParameters['orderId']!,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Events S6 (spec §10.1): static segments before :eventId.
                GoRoute(
                  path: 'results',
                  name: 'memberEventMyResults',
                  builder: (context, state) =>
                      const MemberEventResultsListPage(),
                ),
                GoRoute(
                  path: 'medals',
                  name: 'memberEventMedals',
                  builder: (context, state) => const MemberMedalsPage(),
                ),
                GoRoute(
                  path: 'rewards',
                  name: 'memberEventRewards',
                  builder: (context, state) => const MemberRewardWalletPage(),
                ),
                // The ticket wallet is a segment of the same page.
                GoRoute(
                  path: 'tickets',
                  name: 'memberEventTickets',
                  builder: (context, state) =>
                      const MemberEventOrdersPage(initialTab: 'tickets'),
                ),
                GoRoute(
                  path: 'registrations/:registrationId',
                  name: 'memberEventRegistration',
                  redirect: (context, state) =>
                      _safeEventId.hasMatch(
                        state.pathParameters['registrationId'] ?? '',
                      )
                      ? null
                      : AppRoutes.memberEventOrders,
                  builder: (context, state) => MemberEventRegistrationPage(
                    registrationId: state.pathParameters['registrationId']!,
                  ),
                  routes: [
                    GoRoute(
                      path: 'ticket',
                      name: 'memberEventTicket',
                      builder: (context, state) => MemberEventTicketPage(
                        registrationId: state.pathParameters['registrationId']!,
                      ),
                    ),
                    GoRoute(
                      path: 'result',
                      name: 'memberEventResult',
                      builder: (context, state) => MemberEventResultPage(
                        registrationId: state.pathParameters['registrationId']!,
                      ),
                    ),
                    GoRoute(
                      path: 'runs',
                      name: 'memberEventRuns',
                      builder: (context, state) => EventRunLinksPage(
                        registrationId: state.pathParameters['registrationId']!,
                      ),
                    ),
                    GoRoute(
                      path: 'cancel',
                      name: 'memberEventRegistrationCancel',
                      builder: (context, state) =>
                          MemberEventCancelPage.registration(
                            registrationId:
                                state.pathParameters['registrationId']!,
                            orderId: state.uri.queryParameters['order'],
                          ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'claim/:registrationId',
                  name: 'memberEventClaim',
                  redirect: (context, state) =>
                      _safeEventId.hasMatch(
                        state.pathParameters['registrationId'] ?? '',
                      )
                      ? null
                      : AppRoutes.memberEventOrders,
                  builder: (context, state) => EventClaimPage.inApp(
                    registrationId: state.pathParameters['registrationId']!,
                  ),
                ),
                GoRoute(
                  path: 'teams/:teamId',
                  name: 'memberEventTeam',
                  redirect: (context, state) =>
                      _safeEventId.hasMatch(
                        state.pathParameters['teamId'] ?? '',
                      )
                      ? null
                      : AppRoutes.memberEventOrders,
                  builder: (context, state) =>
                      EventTeamPage(teamId: state.pathParameters['teamId']!),
                ),
                GoRoute(
                  path: ':eventId',
                  name: 'memberEventDetail',
                  redirect: (context, state) =>
                      _safeEventId.hasMatch(
                        state.pathParameters['eventId'] ?? '',
                      )
                      ? null
                      : AppRoutes.memberEvents,
                  builder: (context, state) => MemberEventDetailPage(
                    eventId: state.pathParameters['eventId']!,
                  ),
                  routes: [
                    GoRoute(
                      path: 'results',
                      name: 'memberEventResults',
                      builder: (context, state) => EventResultsBoardPage(
                        eventId: state.pathParameters['eventId']!,
                      ),
                    ),
                    GoRoute(
                      path: 'register',
                      name: 'memberEventRegister',
                      builder: (context, state) => MemberEventRegisterPage(
                        eventId: state.pathParameters['eventId']!,
                        preselectTicketId: state.uri.queryParameters['ticket'],
                        source: state.uri.queryParameters['ticket'] == null
                            ? 'cta'
                            : 'ticket_row',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          GoRoute(
            path: AppRoutes.memberGyms,
            name: 'memberGyms',
            builder: (context, state) => const MemberGymsTab(),
            routes: [
              GoRoute(
                path: ':gymId',
                name: 'memberGymDetail',
                builder: (context, state) {
                  final gymId = state.pathParameters['gymId']!;
                  return MemberGymDetailPage(gymId: gymId);
                },
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.memberTrainers,
            name: 'memberTrainers',
            builder: (context, state) => const MemberTrainersTab(),
            routes: [
              GoRoute(
                path: ':trainerId',
                name: 'memberTrainerDetail',
                builder: (context, state) {
                  final trainerId = state.pathParameters['trainerId']!;
                  return MemberTrainerDetailPage(trainerId: trainerId);
                },
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.memberQr,
            name: 'memberQr',
            builder: (context, state) => const MemberQrTab(),
          ),
          GoRoute(
            path: AppRoutes.memberShop,
            name: 'memberShop',
            builder: (context, state) => const MemberShopTab(),
          ),
          GoRoute(
            path: AppRoutes.memberProfile,
            name: 'memberProfile',
            builder: (context, state) => const MemberProfileTab(),
          ),
          GoRoute(
            path: AppRoutes.memberPasses,
            name: 'memberPasses',
            builder: (context, state) => const MemberPassesPage(),
          ),
          GoRoute(
            path: AppRoutes.memberCommunity,
            name: 'memberCommunity',
            builder: (context, state) => MemberCommunityPage(
              initialTab:
                  int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
            ),
            routes: [
              GoRoute(
                path: 'activities/:activityId',
                name: 'memberSharedActivity',
                builder: (context, state) => MemberSharedActivityPage(
                  activityId: state.pathParameters['activityId']!,
                ),
              ),
              GoRoute(
                path: 'people/:userId',
                name: 'memberPerson',
                builder: (context, state) =>
                    MemberPersonPage(userId: state.pathParameters['userId']!),
              ),
              GoRoute(
                path: 'groups/:groupId',
                name: 'memberGroup',
                builder: (context, state) =>
                    GroupPage(groupId: state.pathParameters['groupId']!),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.memberPrivacy,
            name: 'memberPrivacy',
            builder: (context, state) => const MemberPrivacyPage(),
            routes: [
              GoRoute(
                path: 'activity-sharing',
                name: 'memberActivitySharing',
                builder: (context, state) => const MemberActivitySharingPage(),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.memberPayment,
            name: 'memberPayment',
            builder: (context, state) => const MemberPaymentPage(),
          ),
        ],
      ),
    ],
  );
}
