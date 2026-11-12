import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/phone_steps.dart';
import '../../shared/activity/activity.dart';
import '../../shared/activity/activity_config.dart';
import '../../shared/activity/activity_provider.dart';
import '../../shared/activity/challenge.dart';
import '../../shared/activity/goal.dart';
import '../../shared/activity/gym_sharing.dart';
import '../../shared/activity/trainer_connection.dart';
import '../../shared/activity/training_plan.dart';
import '../../shared/activity/workout.dart';
import '../../shared/api_error_message.dart';
import '../../shared/auth_state.dart';
import '../../shared/design_tokens.dart';
import '../../shared/events/event_filter.dart';
import '../../shared/events/event_summary.dart';
import '../../shared/events/events_analytics_transport.dart';
import '../../shared/events/events_options.dart';
import '../../shared/events_flag.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../../shared/root_back_navigation.dart';
import '../../shared/inbox/inbox_pages.dart';
import '../../shared/components/components.dart';
import '../../shared/photo_hero_flag.dart';
import 'widgets/home_hero.dart';

export 'member_home_tab.dart';
export 'member_activity_tab.dart';
export 'member_workout_page.dart';
export 'member_challenge_page.dart';
export 'member_log_activity_page.dart';
export 'member_gyms_tab.dart';
export 'member_gym_detail_page.dart';
export 'member_trainers_tab.dart';
export 'member_trainer_detail_page.dart';
export 'member_qr_tab.dart';
export 'member_profile_tab.dart';
export 'member_passes_page.dart';
export 'member_payment_page.dart';

/// Shared member data that all member tabs can access.
class MemberData extends ChangeNotifier {
  MemberMeResponse? me;
  List<Gym> gyms = [];
  List<TrainerProfile> trainers = [];

  /// F-12: whether the gym / trainer directory request has finished, and
  /// whether it failed. They default to "loaded" (data set directly); the
  /// shell clears them before its first request, so the tabs can show a
  /// loading or error state instead of "Nothing to show yet." App-side
  /// state only, no backend field.
  bool gymsLoaded = true;
  bool gymsLoadFailed = false;
  bool trainersLoaded = true;
  bool trainersLoadFailed = false;
  List<CheckIn> checkins = [];
  List<PassTier> passes = [];
  Set<String> favoriteGymIds = {};
  // Fitness activity — separate from gym [checkins]; a visit is not a workout.
  List<Activity> activities = [];
  bool activityLoaded = false;
  bool activityIsSample = false;
  List<Goal> goals = [];
  bool goalsLoaded = false;
  List<Workout> workouts = [];
  bool workoutsLoaded = false;

  /// The training plan the member is on, if any.
  TrainingPlan? trainingPlan;
  bool trainingLoaded = false;

  /// Plans trainers have made for the member, waiting for an answer.
  List<TrainingPlanOffer> trainingOffers = [];
  List<TrainerConnection> trainerConnections = [];
  List<GymSharing> gymSharing = [];
  List<Challenge> challenges = [];
  bool challengesLoaded = false;

  /// Events S2 (spec §11.1, §13): what `GET /events/options` said. Off until
  /// the probe answers; off again when it fails. Only read with the
  /// `EVENTS_DISCOVERY` build flag on.
  EventsOptions eventsOptions = EventsOptions.off;

  /// Whether event discovery shows (build flag and server probe both on).
  bool get eventsDiscovery => eventsDiscoveryEnabled && eventsOptions.discovery;

  /// The two soonest open events for the Home card (`GET
  /// /events?limit=2&availability=open`); empty hides the card.
  List<EventSummary> upcomingEvents = [];

  /// Gym check-ins as the challenge engine needs them.
  List<({DateTime at, String? gymId})> get checkInMoments => [
    for (final c in checkins)
      if (DateTime.tryParse(c.timestamp) case final at?)
        (at: at, gymId: c.gymId),
  ];

  /// The open (pending or active) connection with [trainerId], if any.
  TrainerConnection? connectionWith(String trainerId) => trainerConnections
      .where((c) => c.trainerId == trainerId && c.status.isOpen)
      .firstOrNull;

  /// Display name for a trainer, from the directory or a connection.
  String? trainerName(String? trainerId) {
    if (trainerId == null) return null;
    final t = trainers.where((t) => t.id == trainerId).firstOrNull;
    if (t != null) return t.displayName;
    return trainerConnections
        .where((c) => c.trainerId == trainerId)
        .firstOrNull
        ?.trainer
        ?.displayName;
  }

  bool passesLoaded = false;
  String? qrToken;
  String selectedTier = 'pro';
  bool loading = false;

  /// The last refresh couldn't reach FitFlex. Screens keep showing what was
  /// loaded before; the shell says so.
  bool offline = false;

  /// The last profile request failed for a reason other than the network.
  bool meLoadFailed = false;

  bool get hasActivePass => me?.hasActivePass == true;

  /// A sponsor (employer, insurer, club) gives this member gym access through
  /// a wellness benefit, so they can check in without a pass of their own.
  bool sponsoredGymAccess = false;
  bool get canCheckIn => hasActivePass || sponsoredGymAccess;
  bool get needsOnboarding => me?.needsOnboarding == true;
  Subscription? get subscription => me?.subscription;
  PaymentRequest? get pendingPayment => me?.pendingPayment;

  /// An open FitFlex Pass payment. A pending gym plan, trainer session or
  /// order is a different product and does not count.
  PaymentRequest? get pendingPass => _openOf('FITFLEX_PASS');

  /// An open plan payment for this gym only.
  PaymentRequest? pendingGymPlan(String gymId) {
    for (final p in me?.pendingPayments ?? const <PaymentRequest>[]) {
      if (p.productType == 'GYM_SUBSCRIPTION' && p.gymId == gymId) return p;
    }
    return null;
  }

  PaymentRequest? _openOf(String productType) {
    for (final p in me?.pendingPayments ?? const <PaymentRequest>[]) {
      if (p.productType == productType) return p;
    }
    // An older server sends no list: its single pending payment is a pass if it has a tier.
    final single = me?.pendingPayment;
    if ((me?.pendingPayments.isEmpty ?? true) &&
        productType == 'FITFLEX_PASS' &&
        single != null &&
        single.productType == null &&
        single.tier.isNotEmpty) {
      return single;
    }
    return null;
  }

  void update(void Function(MemberData d) fn) {
    fn(this);
    notifyListeners();
  }
}

/// InheritedWidget exposing shared member data to subtree.
class MemberDataScope extends InheritedNotifier<MemberData> {
  const MemberDataScope({
    super.key,
    required MemberData data,
    required super.child,
  }) : super(notifier: data);

  static MemberData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MemberDataScope>();
    assert(scope != null, 'MemberDataScope missing');
    return scope!.notifier!;
  }
}

/// Bottom navigation shell for member screens.
class MemberShell extends StatefulWidget {
  const MemberShell({super.key, required this.state, required this.child});

  final GoRouterState state;
  final Widget child;

  @override
  MemberShellState createState() => MemberShellState();
}

class MemberShellState extends State<MemberShell> with WidgetsBindingObserver {
  final MemberData _data = MemberData()
    ..gymsLoaded = false
    ..trainersLoaded = false;
  Timer? _qrTimer;
  Timer? _stepsTimer;
  bool _started = false;
  AuthState? _auth;
  String? _lastToken;

  // Bottom bar (FitFlex DS v1.0): Home, Activity, the central Check in
  // action, Gyms, Shop. Profile lives behind the avatar in the app bar.
  static const _checkInSlot = 2;

  int get _tabIndex {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/member/activity')) return 1;
    // Event discovery is a section of Activity (events S2 spec §11.1).
    if (loc.startsWith('/member/events')) return 1;
    if (loc.startsWith(AppRoutes.memberQr)) return _checkInSlot;
    // Trainer discovery lives under Gyms now that Activity has the tab.
    if (loc.startsWith('/member/gyms')) return 3;
    if (loc.startsWith('/member/trainers')) return 3;
    if (loc.startsWith('/member/shop')) return 4;
    return 0;
  }

  /// True where no tab is current: Profile (and its pages) and the check-in
  /// screen, which the central action shows without a tab highlight.
  bool get _noTabSelected {
    final loc = GoRouterState.of(context).matchedLocation;
    return loc.startsWith('/member/profile') ||
        loc.startsWith('/member/privacy') ||
        loc.startsWith(AppRoutes.memberQr);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A10: track auth-session changes so a fresh sign-up/sign-in reloads
    // gyms/trainers without requiring an app restart.
    final auth = AppScope.of(context).auth;
    if (!identical(_auth, auth)) {
      _auth?.removeListener(_onAuthChanged);
      _auth = auth;
      _lastToken = auth.token;
      auth.addListener(_onAuthChanged);
    }
    // This phone's step counts show as soon as they're read.
    final steps = AppScope.of(context).phoneSteps;
    if (!identical(_steps, steps)) {
      _steps?.removeListener(_showActivities);
      _steps = steps?..addListener(_showActivities);
    }
    if (_started) return;
    _started = true;
    if (photoHeroUi) {
      // Home's photos first, then the other member tabs (spec §28). The
      // Activity tab pre-caches its four sections at their exact size.
      precacheHeroPhotos(context, const [
        FFHeroPhoto.homeStart,
        FFHeroPhoto.homePass,
        FFHeroPhoto.activityToday,
        FFHeroPhoto.profile,
        FFHeroPhoto.upgrade,
        // Section bands (increment plan, slice 1), after the tabs above.
        FFHeroPhoto.gyms,
        FFHeroPhoto.trainers,
        FFHeroPhoto.shop,
      ]);
    }
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
    // Phone step counting: read while the app is open.
    _stepsTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => syncPhoneSteps(),
    );
    _qrTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_data.canCheckIn) _refreshQr();
    });
  }

  void _onAuthChanged() {
    final token = _auth?.token;
    if (token != null && token != _lastToken) {
      _lastToken = token;
      _refreshAll();
    } else {
      _lastToken = token;
    }
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    _qrTimer?.cancel();
    _stepsTimer?.cancel();
    _steps?.removeListener(_showActivities);
    WidgetsBinding.instance.removeObserver(this);
    _data.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) syncPhoneSteps();
  }

  /// Reads this phone's step counter (when counting is on) and, if the
  /// server got new steps, reloads activity so Home and challenges show them.
  Future<void> syncPhoneSteps() async {
    if (!mounted) return;
    final scope = AppScope.of(context);
    final steps = scope.phoneSteps;
    if (steps == null || !steps.enabled || _auth?.token == null) return;
    if (await steps.sync(scope.api) && mounted) await _refreshActivity();
  }

  Future<void> _refreshAll() async {
    _data.update((d) => d.loading = true);
    try {
      // Doesn't hold up the rest: it reloads activity itself if it sent steps.
      unawaited(syncPhoneSteps());
      await Future.wait([
        _refreshMe(),
        _refreshGyms(),
        _refreshTrainers(),
        _refreshCheckins(),
        _refreshPasses(),
        _refreshFavorites(),
        _refreshActivity(),
        _refreshGoals(),
        _refreshWorkouts(),
        _refreshTraining(),
        _refreshConnections(),
        _refreshGymSharing(),
        _refreshChallenges(),
        _refreshBenefits(),
        _refreshEvents(),
      ]);
      if (_data.canCheckIn) await _refreshQr();
    } finally {
      _data.update((d) => d.loading = false);
    }
  }

  Future<void> _refreshMe() async {
    try {
      final res = await AppScope.of(context).api.me();
      _data.update(
        (d) => d
          ..me = MemberMeResponse.fromJson(
            Map<String, dynamic>.from(res as Map),
          )
          ..offline = false
          ..meLoadFailed = false,
      );
      // Distance from phone steps uses the member's height.
      if (_data.activityLoaded) _showActivities();
    } catch (error) {
      // The profile call is the connectivity check for the whole shell.
      if (isNetworkError(error)) {
        _data.update((d) => d.offline = true);
      } else {
        _data.update((d) => d.meLoadFailed = true);
      }
    }
  }

  Future<void> _refreshGyms() async {
    // A retry with nothing cached shows the loading state again.
    if (_data.gyms.isEmpty && _data.gymsLoadFailed) {
      _data.update(
        (d) => d
          ..gymsLoaded = false
          ..gymsLoadFailed = false,
      );
    }
    try {
      final res = await AppScope.of(context).api.listGyms();
      _data.update(
        (d) => d
          ..gyms = res
              .whereType<Map<String, dynamic>>()
              .map(Gym.fromJson)
              .toList()
          ..gymsLoaded = true
          ..gymsLoadFailed = false,
      );
    } catch (_) {
      // What was loaded before stays; the tab says so only if it has none.
      _data.update(
        (d) => d
          ..gymsLoaded = true
          ..gymsLoadFailed = true,
      );
    }
  }

  /// Reloads the gym directory (the Gyms tab's Try again).
  Future<void> refreshGyms() => _refreshGyms();

  Future<void> _refreshTrainers() async {
    if (_data.trainers.isEmpty && _data.trainersLoadFailed) {
      _data.update(
        (d) => d
          ..trainersLoaded = false
          ..trainersLoadFailed = false,
      );
    }
    try {
      final res = await AppScope.of(context).api.listTrainers();
      final trainers = <TrainerProfile>[];
      for (final item in res.whereType<Map>()) {
        try {
          trainers.add(
            TrainerProfile.fromJson(Map<String, dynamic>.from(item)),
          );
        } catch (error) {
          // A single malformed public profile must not hide the rest of the
          // trainer directory from members.
          debugPrint('[MemberShell] Skipping malformed trainer: $error');
        }
      }
      _data.update(
        (d) => d
          ..trainers = trainers
          ..trainersLoaded = true
          ..trainersLoadFailed = false,
      );
    } catch (error) {
      debugPrint('[MemberShell] Could not refresh trainers: $error');
      _data.update(
        (d) => d
          ..trainersLoaded = true
          ..trainersLoadFailed = true,
      );
    }
  }

  Future<void> _refreshFavorites() async {
    try {
      final ids = await AppScope.of(context).api.favoriteGymIds();
      _data.update((d) => d.favoriteGymIds = ids.toSet());
    } catch (_) {
      // Saved gyms are a convenience; the rest of the tab still works.
    }
  }

  /// Activities as the server returned them; [_showActivities] lays this
  /// phone's step counts over them.
  List<Activity> _serverActivities = const [];
  PhoneSteps? _steps;

  void _showActivities() {
    final steps = _steps;
    final local = steps != null && steps.enabled
        ? steps.localDays
        : const <String, int>{};
    _data.update(
      (d) => d.activities = withPhoneSteps(
        _serverActivities,
        local,
        heightCm: d.me?.user.memberProfile?.heightCm,
        userId: _auth?.user?['id']?.toString() ?? '',
      ),
    );
  }

  Future<void> _refreshActivity() async {
    final provider = AppScope.of(context).activity;
    final userId = _auth?.user?['id']?.toString() ?? '';
    try {
      final now = DateTime.now();
      final activities = await provider.getActivities(
        userId: userId,
        from: DateTime(now.year, now.month, now.day - activityHistoryDays + 1),
        to: now.add(const Duration(days: 1)),
      );
      _serverActivities = activities;
      _data.update((d) {
        d.activityIsSample = provider.kind == ActivityProviderKind.sample;
        d.activityLoaded = true;
      });
      _showActivities();
    } catch (error) {
      debugPrint('[MemberShell] Could not load activity: $error');
      _data.update((d) => d.activityLoaded = true);
    }
  }

  Future<void> _refreshGoals() async {
    try {
      final goals = await AppScope.of(context).goals.list();
      _data.update((d) {
        d.goals = goals;
        d.goalsLoaded = true;
      });
    } catch (error) {
      debugPrint('[MemberShell] Could not load goals: $error');
      _data.update((d) => d.goalsLoaded = true);
    }
  }

  Future<void> refreshGoals() async {
    await _refreshGoals();
  }

  Future<void> _refreshWorkouts() async {
    try {
      final now = DateTime.now();
      final workouts = await AppScope.of(context).workouts.list(
        from: DateTime(now.year, now.month, now.day - activityHistoryDays + 1),
        to: DateTime(now.year, now.month, now.day + 14),
      );
      _data.update((d) {
        d.workouts = workouts;
        d.workoutsLoaded = true;
      });
    } catch (error) {
      debugPrint('[MemberShell] Could not load workouts: $error');
      _data.update((d) => d.workoutsLoaded = true);
    }
  }

  Future<void> _refreshTraining() async {
    try {
      final repo = AppScope.of(context).training;
      final plan = await repo.currentPlan();
      // Offers are extra: failing to load them must not hide the plan.
      var offers = const <TrainingPlanOffer>[];
      try {
        offers = await repo.offers();
      } catch (error) {
        debugPrint('[MemberShell] Could not load plan offers: $error');
      }
      _data.update((d) {
        d.trainingPlan = plan;
        d.trainingOffers = offers;
        d.trainingLoaded = true;
      });
    } catch (error) {
      debugPrint('[MemberShell] Could not load the training plan: $error');
      _data.update((d) => d.trainingLoaded = true);
    }
  }

  /// After a plan is made, changed or stopped: the plan and its workouts.
  Future<void> refreshTraining() async {
    await Future.wait([_refreshTraining(), _refreshWorkouts()]);
  }

  Future<void> _refreshConnections() async {
    try {
      final rows = await AppScope.of(context).api.myTrainerConnections();
      _data.update(
        (d) => d.trainerConnections = [
          for (final r in rows.whereType<Map>())
            TrainerConnection.fromJson(Map<String, dynamic>.from(r)),
        ],
      );
    } catch (error) {
      debugPrint('[MemberShell] Could not load trainer connections: $error');
    }
  }

  Future<void> refreshConnections() async {
    await _refreshConnections();
  }

  Future<void> _refreshChallenges() async {
    try {
      final rows = await AppScope.of(context).api.myChallenges();
      _data.update((d) {
        d.challenges = [
          for (final r in rows.whereType<Map>())
            ?Challenge.tryParse(Map<String, dynamic>.from(r)),
        ];
        d.challengesLoaded = true;
      });
    } catch (error) {
      debugPrint('[MemberShell] Could not load challenges: $error');
      _data.update((d) => d.challengesLoaded = true);
    }
  }

  Future<void> refreshChallenges() async {
    await _refreshChallenges();
  }

  Future<void> _refreshGymSharing() async {
    try {
      final rows = await AppScope.of(context).api.myGymSharing();
      _data.update(
        (d) => d.gymSharing = [
          for (final r in rows.whereType<Map>())
            ?GymSharing.tryParse(Map<String, dynamic>.from(r)),
        ],
      );
    } catch (error) {
      debugPrint('[MemberShell] Could not load gym sharing: $error');
    }
  }

  /// After a workout changes: its list, and — once finished — the activity
  /// it was recorded as, which moves goals, progress and streaks.
  Future<void> refreshAfterWorkout() async {
    await Future.wait([
      _refreshWorkouts(),
      _refreshActivity(),
      _refreshTraining(),
    ]);
  }

  Future<void> refreshTrainers() async {
    await _refreshTrainers();
  }

  Future<void> _refreshCheckins() async {
    try {
      final res = await AppScope.of(context).api.myCheckins();
      _data.update(
        (d) => d.checkins = res
            .whereType<Map<String, dynamic>>()
            .map(CheckIn.fromJson)
            .toList(),
      );
    } catch (_) {
      // ignore
    }
  }

  Future<void> _refreshPasses() async {
    final api = AppScope.of(context).api;
    try {
      // Prefer new subscription-tiers endpoint (includes gymAccess per plan)
      final res = await api.listSubscriptionTiers();
      // A7: the "Online Free" option must not be offered to members.
      final tiers = res
          .whereType<Map<String, dynamic>>()
          .map(PassTier.fromJson)
          .where((t) => t.id != 'online_free')
          .toList();
      if (tiers.isEmpty) throw Exception('empty_tiers');
      _data.update((d) {
        d.passes = tiers;
        d.passesLoaded = true;
      });
    } catch (_) {
      // Fallback to legacy /passes endpoint
      try {
        final res = await api.listPasses();
        _data.update((d) {
          d.passes = res
              .whereType<Map<String, dynamic>>()
              .map(PassTier.fromJson)
              .where((t) => t.id != 'online_free')
              .toList();
          d.passesLoaded = true;
        });
      } catch (_) {
        _data.update((d) => d.passesLoaded = true);
      }
    }
  }

  Future<void> _refreshQr() async {
    try {
      final res = await AppScope.of(context).api.myQr();
      _data.update((d) => d.qrToken = res['token'] as String?);
    } catch (_) {
      _data.update((d) => d.qrToken = null);
    }
  }

  Future<void> refreshPasses() async {
    await _refreshPasses();
  }

  Future<void> refreshQr() async {
    if (_data.canCheckIn) await _refreshQr();
  }

  /// Whether a sponsor's benefit lets the member check in. Left as it was if
  /// the call fails, so a blip never locks the QR.
  Future<void> _refreshBenefits() async {
    try {
      final res = await AppScope.of(context).api.myWellnessBenefits();
      final sponsored = ((res['benefits'] as List?) ?? const []).any(
        (b) =>
            b is Map && (b['benefit'] as Map?)?['benefitType'] == 'gym_access',
      );
      _data.update((d) => d.sponsoredGymAccess = sponsored);
    } catch (_) {}
  }

  /// Events S2: probe `GET /events/options`, then the two soonest open
  /// events for the Home card. Nothing is asked with the build flag off; any
  /// failure (404 while the server module is off, offline) means "off" and
  /// an empty card list, never an error on screen.
  Future<void> _refreshEvents() async {
    if (!eventsDiscoveryEnabled) return;
    final api = AppScope.of(context).api;
    EventsOptions options;
    try {
      options = EventsOptions.fromJson(await api.eventsOptions());
    } catch (_) {
      options = EventsOptions.off;
    }
    var upcoming = <EventSummary>[];
    if (options.discovery) {
      try {
        final page = await api.listEvents(
          const EventFilter(openOnly: true).toQuery(),
          limit: 2,
        );
        upcoming = [
          for (final item in (page['items'] as List?) ?? const [])
            if (item is Map)
              EventSummary.fromJson(Map<String, dynamic>.from(item)),
        ];
      } catch (_) {
        upcoming = [];
      }
    }
    // Events S7 (spec §5.4): screen counts are sent only while the server
    // says so; an older server has no block and the transport stays off.
    EventsAnalyticsTransport.instance.configure(
      enabled: options.analytics.enabled,
      send: api.postEventsAnalytics,
    );
    _data.update(
      (d) => d
        ..eventsOptions = options
        ..upcomingEvents = upcoming,
    );
  }

  Future<void> refreshEvents() => _refreshEvents();

  Future<void> refreshMe() async {
    await _refreshMe();
  }

  void _onTab(int index) {
    final routes = [
      AppRoutes.memberHome,
      AppRoutes.memberActivity,
      AppRoutes.memberQr,
      AppRoutes.memberGyms,
      AppRoutes.memberShop,
    ];
    context.go(routes[index]);
  }

  /// Tabs whose app bar floats over a photo hero (PHOTO_HERO_UI).
  static const heroTabRoutes = {
    AppRoutes.memberHome,
    AppRoutes.memberActivity,
    '${AppRoutes.memberActivity}/progress',
    AppRoutes.memberProfile,
  };

  /// The hero tabs' app bar: transparent with light icons until the hero
  /// scrolls under it, then solid `surface` with the theme's colours.
  bool _homeBarSolid = false;
  String? _heroBarLocation;

  /// The bar's own background is animated (not a `flexibleSpace` layer: the
  /// Scaffold gives the app bar a loose height, so a childless box there
  /// lays out at zero height and never paints). With the real colour on the
  /// AppBar, its Material paints it and the status bar style follows it.
  PreferredSizeWidget _heroAppBar(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final solid = _homeBarSolid;
    Widget bar(Widget w) => solid ? w : FFOnPhotoTheme(child: w);
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: solid ? 1 : 0),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        builder: (context, t, _) => AppBar(
          key: const Key('member-home-hero-app-bar'),
          automaticallyImplyLeading: false,
          backgroundColor: surface.withValues(alpha: surface.a * t),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: solid ? null : FFTokens.heroText,
          // Solid: null lets AppBar pick the style from the surface colour,
          // i.e. the theme's.
          systemOverlayStyle: solid ? null : SystemUiOverlayStyle.light,
          title: bar(Text(context.tr('app.title'))),
          actions: [
            bar(
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InboxBellButton(),
                  AppPrefsButtons(),
                  _ProfileAvatarButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroHomeBody(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return NotificationListener<HomeHeroAppBarNotification>(
      onNotification: (n) {
        if (n.solid != _homeBarSolid) setState(() => _homeBarSolid = n.solid);
        return true;
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: RefreshIndicator(
              edgeOffset: top,
              onRefresh: _refreshAll,
              child: FFPhotoBarHost(child: widget.child),
            ),
          ),
          // The bar's band stays put while the hero scrolls (spec §5).
          FFPhotoBarScrim(barBottom: top, visible: !_homeBarSolid),
          // The offline strip keeps its place under the app bar, on a solid
          // surface so it stays readable over the photo.
          Positioned(
            top: top,
            left: 0,
            right: 0,
            child: ListenableBuilder(
              listenable: _data,
              builder: (context, _) => _data.offline
                  ? ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: _OfflineBanner(onRetry: _refreshAll),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final isRootTab = <String>{
      AppRoutes.memberHome,
      AppRoutes.memberActivity,
      AppRoutes.memberGyms,
      AppRoutes.memberTrainers,
      AppRoutes.memberShop,
      AppRoutes.memberProfile,
      AppRoutes.memberQr,
    }.contains(location);
    // PHOTO_HERO_UI: on Home, Activity and Profile at phone width the app
    // bar floats over the hero (spec C-7).
    final heroHome =
        photoHeroUi &&
        heroTabRoutes.contains(location) &&
        MediaQuery.sizeOf(context).width < 840;
    // A tab starts with its hero under a transparent bar.
    if (location != _heroBarLocation) {
      _heroBarLocation = location;
      _homeBarSolid = false;
    }
    return PopScope(
      canPop: !isRootTab,
      onPopInvokedWithResult: (didPop, _) {
        if (isRootTab) handleRootBack(didPop: didPop);
      },
      child: MemberDataScope(
        data: _data,
        child: Scaffold(
          extendBodyBehindAppBar: heroHome,
          appBar: heroHome
              ? _heroAppBar(context)
              : AppBar(
                  automaticallyImplyLeading: false,
                  title: const FFWordmark(),
                  // DS v1.0: bell and avatar only; language and theme live
                  // in Profile.
                  actions: const [InboxBellButton(), _ProfileAvatarButton()],
                ),
          body: heroHome
              ? _heroHomeBody(context)
              : Column(
                  children: [
                    ListenableBuilder(
                      listenable: _data,
                      builder: (context, _) => _data.offline
                          ? _OfflineBanner(onRetry: _refreshAll)
                          : const SizedBox.shrink(),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refreshAll,
                        child: widget.child,
                      ),
                    ),
                  ],
                ),
          // Out of the way while typing, so a form's submit button (the
          // payment page and plan sheets) is never half under it (M16).
          bottomNavigationBar: FFHideWhileTyping(
            child: _MemberNavTheme(
              noneSelected: _noTabSelected,
              child: NavigationBar(
                selectedIndex: _tabIndex,
                onDestinationSelected: _onTab,
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.home_outlined),
                    selectedIcon: const Icon(Icons.home),
                    label: context.tr('member.home'),
                  ),
                  NavigationDestination(
                    key: const Key('member-nav-activity'),
                    icon: const Icon(Icons.directions_run_outlined),
                    selectedIcon: const Icon(Icons.directions_run),
                    label: context.tr('activity.title'),
                  ),
                  NavigationDestination(
                    key: const Key('member-nav-checkin'),
                    icon: const _CheckInAction(),
                    label: context.tr('member.checkInNav'),
                    tooltip: context.tr('checkin.title'),
                  ),
                  NavigationDestination(
                    key: const Key('member-nav-gyms'),
                    icon: const Icon(Icons.fitness_center_outlined),
                    selectedIcon: const Icon(Icons.fitness_center),
                    label: context.tr('member.gyms'),
                  ),
                  NavigationDestination(
                    key: const Key('member-nav-shop'),
                    icon: const Icon(Icons.storefront_outlined),
                    selectedIcon: const Icon(Icons.storefront),
                    label: context.tr('member.shop'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Slim notice under the app bar while FitFlex can't be reached.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('member-offline-banner'),
      color: FFTokens.warning500.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          FFTokens.spacingMd,
          FFTokens.spacingXs,
          FFTokens.spacingXs,
          FFTokens.spacingXs,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: FFTokens.iconSm,
              color: FFTokens.warning500,
            ),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: Text(
                context.tr('offline.banner'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            FFButton(
              key: const Key('member-offline-retry'),
              label: context.tr('home.retry'),
              onPressed: onRetry,
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
            ),
          ],
        ),
      ),
    );
  }
}


/// The member bar's centre slot: a raised round check-in button (forest with
/// a lime QR icon in light, lime with a forest icon in dark). It takes a
/// normal icon's space; the lift above the bar is visual only.
class _CheckInAction extends StatelessWidget {
  const _CheckInAction();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ring = Theme.of(context).navigationBarTheme.backgroundColor ??
        Theme.of(context).colorScheme.surface;
    // Laid out as a normal 24dp icon so its label lines up with the other
    // tabs; the 52dp circle overflows upwards out of the bar.
    return SizedBox(
      width: 60,
      height: 24,
      child: OverflowBox(
        maxHeight: 60,
        maxWidth: 60,
        child: Transform.translate(
          offset: const Offset(0, -18),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: dark ? FFTokens.volt : FFTokens.ink,
              shape: BoxShape.circle,
              border: Border.all(color: ring, width: 4),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.qr_code_2,
              size: 24,
              color: dark ? FFTokens.onVolt : FFTokens.volt,
            ),
          ),
        ),
      ),
    );
  }
}

/// Hides the selected-tab treatment where no tab is current (Profile and
/// the check-in screen), so the bar never points at the wrong tab.
class _MemberNavTheme extends StatelessWidget {
  const _MemberNavTheme({required this.noneSelected, required this.child});

  final bool noneSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!noneSelected) return child;
    final base = NavigationBarTheme.of(context);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return NavigationBarTheme(
      data: base.copyWith(
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStatePropertyAll(IconThemeData(color: muted)),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: FFTokens.fontSans,
            color: muted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Profile, from the app bar: a round avatar with the member's initial.
class _ProfileAvatarButton extends StatelessWidget {
  const _ProfileAvatarButton();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name =
        AppScope.of(context).auth.user?['displayName']?.toString() ?? '';
    final initial = name.trim().isEmpty ? '' : name.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: IconButton(
        key: const Key('member-nav-profile'),
        tooltip: context.tr('member.profile'),
        onPressed: () => context.go(AppRoutes.memberProfile),
        icon: CircleAvatar(
          radius: 18,
          backgroundColor: dark ? FFTokens.volt : FFTokens.ink,
          foregroundColor: dark ? FFTokens.onVolt : FFTokens.volt,
          child: initial.isEmpty
              ? const Icon(Icons.person, size: 18)
              : Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
