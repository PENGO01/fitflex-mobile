import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'app_scope.dart';
import 'shared/activity/activity_config.dart';
import 'shared/activity/phone_steps.dart';
import 'shared/activity/run_recorder.dart';
import 'router.dart';
import 'screens/account_recovery.dart';
import 'shared/api_client.dart';
import 'shared/auth_state.dart';
import 'shared/barcode_library.dart';
import 'shared/events/event_claim_link.dart';
import 'shared/friend_invites.dart';
import 'shared/hero_images/hero_image_store.dart';
import 'shared/partner_media/partner_media_store.dart';
import 'shared/inbox/inbox_controller.dart';
import 'shared/pending_org_invite.dart';
import 'shared/push_service.dart';
import 'shared/design_tokens.dart';
import 'shared/i18n.dart';
import 'shared/media/media_src.dart';
import 'shared/promotion_events.dart';
import 'shared/push_banner.dart';
import 'shared/splash/kinetic_splash.dart';
import 'shared/theme_notifier.dart';
import 'firebase_options.dart';

Future<void> main() async {
  // An organisation invitation link opened in the browser: take the token
  // out of the address before the router reads it (it is kept on the
  // device below), so the app opens /invitations with no token in history.
  final linkToken = kIsWeb ? inviteTokenFromPageUri(Uri.base) : null;
  if (linkToken != null) showInvitationsWithoutToken();
  // Likewise a friend invitation link (`/friend-invite/#tok`, or a legacy
  // `/friend-invite/tok`): the app opens /friend-invite with no token.
  final friendLink = kIsWeb && linkToken == null
      ? friendInviteLinkFrom(Uri.base)
      : null;
  if (friendLink != null) showFriendInviteWithoutToken();
  // Likewise an event claim link (`/event-claim/#tok`, events S3 §5.11).
  final claimLink = kIsWeb && linkToken == null && friendLink == null
      ? eventClaimLinkFrom(Uri.base)
      : null;
  if (claimLink != null) showEventClaimWithoutToken();

  WidgetsFlutterBinding.ensureInitialized();
  // Web: scan pages load the pinned barcode library from this app's own
  // origin, not unpkg (vendor tools S8, Q-3).
  useBundledBarcodeLibrary();
  if (linkToken != null) {
    await PendingOrgInvite.save(linkToken);
  } else {
    await PendingOrgInvite.load();
  }
  final friendToken = friendLink?.token;
  if (friendToken != null) {
    await PendingFriendInvite.save(friendToken);
  } else if (friendLink != null) {
    // A malformed link: the page says it is not valid.
    await PendingFriendInvite.clear();
  } else {
    await PendingFriendInvite.load();
  }
  final claimToken = claimLink?.token;
  if (claimToken != null) {
    await PendingEventClaim.save(claimToken);
  } else if (claimLink != null) {
    await PendingEventClaim.clear();
  } else {
    await PendingEventClaim.load();
  }
  const mockAuth = bool.fromEnvironment('MOCK_AUTH');

  // GoRouter uses hash URL strategy by default on web (e.g. /#/member/gyms).
  // This works without server-side rewrites for single-page apps.
  GoRouter.optionURLReflectsImperativeAPIs = true;

  // Load runtime config from bundled .env (API_BASE, etc.).
  // Failure is non-fatal — ApiClient will fall back to its built-in default.
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // .env not bundled or unreadable; continue with defaults.
  }

  // Idempotent: avoids a duplicate-app crash if main() runs twice in one
  // process (e.g. across Patrol integration test cases).
  if (!mockAuth && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  // Phone step counting runs a background reading on Android.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && !mockAuth) {
    await initPhoneStepsBackground();
  }
  final api = ApiClient();
  // Partner photos are drawn only from this host (fitflex-functions#273).
  MediaSrcPolicy.configure(api.baseUrl);
  PromotionEvents.install(api);
  final auth = AuthState(api, push: mockAuth ? null : PushService(api));
  await auth.hydrate();

  final locale = FFLocale();
  final themeNotifier = ThemeNotifier();
  // Restore the language and theme chosen on this device.
  await Future.wait([locale.load(), themeNotifier.load()]);

  runApp(
    FitFlexApp(
      api: api,
      auth: auth,
      locale: locale,
      themeNotifier: themeNotifier,
    ),
  );
}

class FitFlexApp extends StatefulWidget {
  const FitFlexApp({
    super.key,
    required this.api,
    required this.auth,
    required this.locale,
    required this.themeNotifier,
  });

  final ApiClient api;
  final AuthState auth;
  final FFLocale locale;
  final ThemeNotifier themeNotifier;

  @override
  State<FitFlexApp> createState() => _FitFlexAppState();
}

class _FitFlexAppState extends State<FitFlexApp> with WidgetsBindingObserver {
  late final GoRouter _router;
  late final ActivityBackend _activity;
  late final InboxController _inbox;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  PhoneSteps? _phoneSteps;
  RunRecorder? _runs;
  String? _lastToken;
  String? _syncedLocale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = buildRouter(widget.auth);
    final sample = activitySampleDataEnabled();
    _activity = ActivityBackend.create(widget.api, sample: sample);
    // Real steps go to the server, so the phone counter only runs with real
    // activity data (not sample mode).
    if (!sample && phoneStepsSupported()) {
      _phoneSteps = createPhoneSteps()..load();
    }
    // Runs are saved to the server, so recording needs real activity data.
    if (!sample && runRecordingSupported()) {
      _runs = createRunRecorder()..restore();
    }
    _inbox = InboxController(widget.api);
    widget.auth.push?.onOpen = _openFromPush;
    widget.auth.push?.onForeground = _onForegroundPush;
    if (widget.auth.token != null) _inbox.load();
    _lastToken = widget.auth.token;
    widget.auth.addListener(_onAuth);
    widget.locale.addListener(_syncLocale);
    _syncLocale();
    // Admin-published photos (HERO_IMAGES_REMOTE): null with the flag off,
    // so no request is ever made. Bundled photos paint the first frame; the
    // list is read after it.
    _partnerMedia = PartnerMediaStore.startIfEnabled(widget.api);
    _heroImages = HeroImageStore.startIfEnabled(apiBase: widget.api.baseUrl);
    if (_heroImages != null) {
      _syncHeroSession();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _heroImages?.onFirstFrame(),
      );
    }
  }

  HeroImageStore? _heroImages;

  /// Partner home photos and logos (PARTNER_MEDIA_UI): null with the flag
  /// off. Started here so the saved copies are read before a home is built.
  PartnerMediaStore? _partnerMedia;

  void _syncHeroSession() => _heroImages?.setSession(
    signedIn: widget.auth.isSignedIn,
    role: widget.auth.user?['userType']?.toString() ?? widget.auth.role,
  );

  /// Gym messages go out in each member's app language, so the server keeps
  /// a copy of it. Sent on sign-in and whenever the language changes.
  Future<void> _syncLocale() async {
    final lang = widget.locale.locale.languageCode;
    if (widget.auth.token == null || lang == _syncedLocale) return;
    _syncedLocale = lang;
    try {
      await widget.api.updateCommunicationPreferences({'locale': lang});
    } catch (_) {
      // Retried on the next sign-in or language change.
      if (_syncedLocale == lang) _syncedLocale = null;
    }
  }

  /// A push arrived while the app is open: the bell updates, and since the
  /// phone shows nothing for an open app, a banner with a way to open it.
  void _onForegroundPush(
    Map<String, dynamic> data,
    String? title,
    String? body,
  ) {
    _inbox.load();
    final messenger = _messengerKey.currentState;
    if (messenger == null) return;
    final text = localisedNoticeText(
      lang: widget.locale.locale.languageCode,
      data: data,
      title: title ?? '',
      body: body ?? '',
    );
    showPushBanner(
      messenger,
      title: text.title,
      body: text.body,
      openLabel: widget.locale.t('push.open'),
      onOpen: () => _openFromPush(data),
    );
  }

  /// A tapped push opens its message, or the screen it links to.
  Future<void> _openFromPush(Map<String, dynamic> data) async {
    final message = await _inbox.openFromPush(data);
    final role = widget.auth.user?['userType']?.toString() ?? widget.auth.role;
    final target = pushTargetFor(role: role, data: data, message: message);
    if (target.go) {
      _router.go(target.location);
    } else {
      _router.push(target.location);
    }
  }

  void _onAuth() {
    _syncHeroSession();
    final token = widget.auth.token;
    // Signed out: this phone's steps aren't the next person's.
    if (_lastToken != null && token == null) {
      _phoneSteps?.forget();
      _runs?.discard();
      // A partner's saved home photo and logo are not the next person's.
      _partnerMedia?.clearAll();
      _inbox.clear();
      _syncedLocale = null;
      // A kept invitation link is not the next person's.
      PendingOrgInvite.clear();
      PendingFriendInvite.clear();
      PendingEventClaim.clear();
    }
    if (token != null && token != _lastToken) {
      _inbox.load();
      _syncLocale();
      _claimKeptInvite();
      // Only on signing in, not on a persona switch or token refresh.
      if (_lastToken == null) {
        _openKeptOrgInvite();
        _openKeptEventClaim();
      }
    }
    _lastToken = token;
  }

  /// Someone opened a friend-invitation link before signing in: now that
  /// they have, attach it (the server checks it was made for their
  /// verified email / number) and show the request under Notifications.
  Future<void> _claimKeptInvite() async {
    final kept = await PendingFriendInvite.take();
    if (kept == null) return;
    try {
      final res = await widget.api.claimFriendInvitation(kept);
      await _inbox.load();
      final status = ((res['invitation'] as Map?)?['status'] ?? '').toString();
      if (status == 'pending') _router.go('/inbox');
    } catch (_) {
      // Wrong account, expired or withdrawn: the link page explains if reopened.
    }
  }

  /// Someone opened an organisation invitation link before signing in:
  /// open the invitations screen, which takes the kept token. Onboarding,
  /// approval or persona-choice redirects still win; the token then stays
  /// kept (a day) until the person reaches the invitations screen.
  Future<void> _openKeptOrgInvite() async {
    if (await PendingOrgInvite.peek() == null) return;
    if (widget.auth.token == null) return;
    _router.go(AppRoutes.invitations);
  }

  /// Someone opened an event claim link before signing in: back to the
  /// claim page now that they have (events S3 §5.11). The page asks "Is
  /// this you?" and claims; nothing is claimed silently.
  Future<void> _openKeptEventClaim() async {
    if (await PendingEventClaim.peek() == null) return;
    if (widget.auth.token == null) return;
    _router.go(AppRoutes.eventClaim);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto theme: the clock may have crossed dusk or dawn while suspended.
    if (state == AppLifecycleState.resumed) {
      widget.themeNotifier.refresh();
      // App photos: checked again only if the last check is 6 h old.
      _heroImages?.onResume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.auth.removeListener(_onAuth);
    widget.locale.removeListener(_syncLocale);
    widget.auth.push?.onOpen = null;
    widget.auth.push?.onForeground = null;
    _inbox.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      api: widget.api,
      auth: widget.auth,
      activityProvider: _activity.activity,
      goalRepository: _activity.goals,
      workoutRepository: _activity.workouts,
      trainingRepository: _activity.training,
      manualActivityLog: _activity.manualLog,
      phoneSteps: _phoneSteps,
      runRecorder: _runs,
      inbox: _inbox,
      child: ThemeScope(
        notifier: widget.themeNotifier,
        child: FFLocaleScope(
          notifier: widget.locale,
          child: AnimatedBuilder(
            animation: Listenable.merge([widget.locale, widget.themeNotifier]),
            builder: (context, _) {
              return MaterialApp.router(
                title: 'FitFlex',
                scaffoldMessengerKey: _messengerKey,
                debugShowCheckedModeBanner: kDebugMode,
                theme: buildTheme(),
                darkTheme: buildDarkTheme(),
                themeMode: widget.themeNotifier.mode,
                locale: widget.locale.locale,
                supportedLocales: const [Locale('en'), Locale('sw')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                routerConfig: _router,
                // Respect the system font size, but cap it so layouts built
                // for normal text do not break at the largest settings.
                builder: (context, child) => MediaQuery.withClampedTextScaling(
                  minScaleFactor: 1.0,
                  maxScaleFactor: 1.3,
                  child: KineticSplashGate(
                    tagline: splashTagline(widget.locale),
                    child: RecoveryBannerHost(
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
