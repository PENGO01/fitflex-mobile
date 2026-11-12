import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';

import '../../shared/activity/activity.dart';
import '../../shared/activity/activity_summary.dart';
import '../../shared/activity/goal.dart';
import '../../shared/activity/progress_engine.dart';
import '../../shared/activity/streaks.dart';
import '../../shared/activity/workout.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/photo_footer_flag.dart';
import '../../shared/photo_hero_flag.dart';
import 'member_shell.dart';
import 'events/events_discovery_view.dart';
import 'widgets/activity_period_card.dart';
import 'widgets/home_hero.dart';
import 'widgets/phone_steps_card.dart';
import 'widgets/run_widgets.dart';
import 'widgets/activity_widgets.dart';
import 'widgets/challenge_widgets.dart';
import 'widgets/goal_widgets.dart';
import 'widgets/gym_visit_tile.dart';
import 'widgets/progress_section.dart';
import 'widgets/training_offer.dart';
import 'widgets/training_widgets.dart';
import 'widgets/workout_widgets.dart';

/// Member Activity tab: Today · Training · Challenges · Progress.
class MemberActivityTab extends StatefulWidget {
  const MemberActivityTab({
    super.key,
    this.now,
    this.initialSection = 'overview',
  });

  /// Injectable clock for tests.
  final DateTime? now;

  /// `overview`, `workouts`, `challenges` or `progress`.
  final String initialSection;

  @override
  State<MemberActivityTab> createState() => _MemberActivityTabState();
}

/// PHOTO_HERO_UI (owner 2026-10-22, heroes "too dark"): Activity's hero
/// grows for [FFTokens.heroBandClearPhoto] of clear photo above its text on
/// phones from 760 tall, but the section switcher under it keeps its top
/// edge above [FFTokens.heroBandControlShare] of the screen; the clear
/// photo gives way (45px at 390x844).
const double activityHeroClearPhoto = FFTokens.heroBandClearPhoto;

/// The Sample badge's height at 1.0x text (an [FFPill]).
const double _sampleBadgeHeight = 28;

/// PHOTO_HERO_UI: each section's photo and headline keys (spec §24).
const activityHeroSections = <String, (FFHeroPhoto, String)>{
  'overview': (FFHeroPhoto.activityToday, 'hero.activity.today'),
  'workouts': (FFHeroPhoto.activityTraining, 'hero.activity.training'),
  'challenges': (FFHeroPhoto.activityChallenges, 'hero.activity.challenges'),
  'progress': (FFHeroPhoto.activityProgress, 'hero.activity.progress'),
};

class _MemberActivityTabState extends State<MemberActivityTab> {
  late String _section = widget.initialSection;
  final _heroKey = GlobalKey();
  bool _precached = false;

  /// Same rule as today for the page header's Log activity button.
  bool _showLog(MemberData data) =>
      data.activityLoaded &&
      (data.activities.isNotEmpty || _section != 'overview');

  /// The hero's least height: fixed, so switching sections never moves
  /// the segmented control (spec §24). With clear photo above the text the
  /// hero is taller, and as fixed (its text keeps the tallest headline's
  /// room).
  double _heroHeight(BuildContext context, double topInset) =>
      topInset +
      (Theme.of(context).brightness == Brightness.dark ? 228.0 : 252.0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (photoHeroUi && !_precached) {
      _precached = true;
      // All four photos at the hero's exact size, so a switch never shows
      // the placeholder.
      final data = MemberDataScope.of(context);
      final width = MediaQuery.sizeOf(context).width;
      final topInset = memberHeroTopInset(context, data);
      precacheHeroPhotos(context, [
        for (final v in activityHeroSections.values) v.$1,
      ], box: Size(width, _heroHeight(context, topInset)));
      // Again at the hero's laid-out size, which the clear photo makes
      // taller than its least height: the sizes share a cache entry.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final size = _heroKey.currentContext?.size;
        if (!mounted || size == null || size.isEmpty) return;
        precacheHeroPhotos(context, [
          for (final v in activityHeroSections.values) v.$1,
        ], box: size);
      });
    }
  }

  Widget _hero(BuildContext context, MemberData data, {bool panel = false}) {
    final (photo, key) =
        activityHeroSections[_section] ?? activityHeroSections['overview']!;
    Widget logButton(Key? k) => FFButton(
      key: k,
      label: context.tr('logActivity.open'),
      onPressed: () => openLogActivity(context),
      variant: FFButtonVariant.onPhoto,
      size: FFButtonSize.sm,
      icon: Icons.add,
    );
    final topInset = memberHeroTopInset(context, data);
    return FFPhotoHero(
      key: const Key('activity-hero'),
      photo: photo,
      variant: panel ? FFHeroVariant.panel : FFHeroVariant.compact,
      rounded: panel,
      minHeight: panel ? 200 : _heroHeight(context, topInset),
      topInset: panel ? 0 : topInset,
      clearPhoto: panel
          ? 0
          : heroBandClear(
              activityHeroClearPhoto,
              viewportHeight: MediaQuery.sizeOf(context).height,
              textScale: MediaQuery.textScalerOf(context).scale(1),
            ),
      // The hero starts at the top of the screen; the switcher follows it
      // 24px down on the dark ground, or right at its edge on the light
      // sheet that overlaps it, and below the Sample badge when shown.
      maxHeight: panel
          ? double.infinity
          : FFTokens.heroBandControlShare * MediaQuery.sizeOf(context).height -
                (Theme.of(context).brightness == Brightness.dark
                    ? FFTokens.spacingLg
                    : 0) -
                (data.activityIsSample
                    ? FFTokens.spacingSm +
                          _sampleBadgeHeight *
                              MediaQuery.textScalerOf(context).scale(1)
                    : 0),
      minClearPhoto: FFTokens.heroBandMinClearPhoto,
      eyebrow: context.tr('activity.title'),
      headlineLead: context.tr('$key.lead'),
      headlineAccent: context.tr('$key.accent'),
      // Room for the tallest section headline: the hero keeps one height.
      headlineReserve: [
        for (final (_, k) in activityHeroSections.values)
          (context.tr('$k.lead'), context.tr('$k.accent')),
      ],
      actions: [
        if (_showLog(data))
          logButton(const Key('activity-log-open'))
        else if (data.activityLoaded)
          // Hidden on an empty Today (today's rule), but its room is kept
          // so switching sections does not change the hero's height.
          Visibility(
            visible: false,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: logButton(null),
          ),
      ],
    );
  }

  /// Everything below the hero: the same as today, minus the page header.
  List<Widget> _sheet(BuildContext context, MemberData data, DateTime today) =>
      [
        if (data.activityIsSample)
          const Padding(
            padding: EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActivitySampleBadge(),
            ),
          ),
        _sections(context, data),
        const SizedBox(height: FFTokens.spacingMd),
        ..._sectionContent(context, data, today),
      ];

  Widget _sections(BuildContext context, MemberData data) => SizedBox(
    width: double.infinity,
    child: FFSegmented(
      key: const Key('activity-sections'),
      value: _section,
      options: [
        ('overview', context.tr('activity.overview')),
        ('workouts', context.tr('activity.workouts')),
        ('challenges', context.tr('activity.challenges')),
        ('progress', context.tr('activity.progress')),
        // Events S2 (spec §11.1): only with the build flag and the server
        // probe on. The hero keeps the Activity photo set.
        if (data.eventsDiscovery) ('events', context.tr('activity.events')),
      ],
      onChanged: (v) => setState(() => _section = v),
    ),
  );

  List<Widget> _sectionContent(
    BuildContext context,
    MemberData data,
    DateTime today,
  ) => [
    // Events have their own loading states and do not wait for activity.
    if (_section == 'events' && data.eventsDiscovery)
      const EventsDiscoveryView(key: Key('activity-events'), inline: true)
    else if (!data.activityLoaded)
      const Padding(
        padding: EdgeInsets.all(FFTokens.spacingXl),
        child: Center(child: FFSpinner(size: 32)),
      )
    else
      ...switch (_section) {
        'workouts' => _workouts(context, data, today),
        'challenges' => buildChallengesSection(context, data, today),
        'progress' => buildProgressSection(context, data, today),
        _ => _overview(context, data.activities, data.goals, today),
      },
  ];

  /// PHOTO_HERO_UI: the section's photo hero leads; the rest sits on the
  /// ground (dark) or an overlapping sheet (light).
  Widget _buildPhotoHero(
    BuildContext context,
    MemberData data,
    DateTime today,
  ) {
    // PHOTO_FOOTER_UI (spec §33.6): one footer for all four sections,
    // once activity has loaded.
    Widget? footer({required bool padded}) => photoFooterUi
        ? FFPhotoFooter.sliver(
            key: const Key('activity-footer'),
            pageKey: 'member.activity',
            top:
                (activityHeroSections[_section] ??
                        activityHeroSections['overview']!)
                    .$1,
            enabled: data.activityLoaded,
            gap: padded
                ? FFTokens.spacingXl - FFTokens.spacingLg
                : FFTokens.spacingXl,
          )
        : null;
    if (MediaQuery.sizeOf(context).width >= 840) {
      return footerListView(
        key: const Key('activity-scroll'),
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        footer: footer(padded: true),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _hero(context, data, panel: true),
                  const SizedBox(height: FFTokens.spacingLg),
                  ..._sheet(context, data, today),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return HeroTabScroll(
      heroKey: _heroKey,
      child: footerListView(
        key: const Key('activity-scroll'),
        footer: footer(padded: false),
        children: [
          KeyedSubtree(key: _heroKey, child: _hero(context, data)),
          FFHeroSheet(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _sheet(context, data, today),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final today = widget.now ?? DateTime.now();
    if (photoHeroUi) return _buildPhotoHero(context, data, today);

    return ListView(
      key: const Key('activity-scroll'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        FFPageHeader(
          title: context.tr('activity.title'),
          actions:
              data.activityLoaded &&
                  (data.activities.isNotEmpty || _section != 'overview')
              ? _besideTitle(
                  context,
                  FFButton(
                    key: const Key('activity-log-open'),
                    label: context.tr('logActivity.open'),
                    onPressed: () => openLogActivity(context),
                    variant: FFButtonVariant.secondary,
                    size: FFButtonSize.sm,
                    icon: Icons.add,
                    maxLines: 2,
                  ),
                )
              : null,
        ),
        if (data.activityIsSample)
          const Padding(
            padding: EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActivitySampleBadge(),
            ),
          ),
        _sections(context, data),
        const SizedBox(height: FFTokens.spacingMd),
        ..._sectionContent(context, data, today),
      ],
    );
  }

  /// A button next to a title, kept to under half the screen's width so a
  /// long label (Swahili, large text) wraps onto a second line instead of
  /// pushing the row off screen.
  Widget _besideTitle(BuildContext context, Widget button) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width * 0.45,
    ),
    child: button,
  );

  List<Widget> _overview(
    BuildContext context,
    List<Activity> activities,
    List<Goal> goals,
    DateTime today,
  ) {
    final s = summarizeDay(activities, today);
    final stepGoal = dailyStepGoal(goals)?.target.round();
    final streak = computeStreak(
      StreakKind.activity,
      today: today,
      activities: activities,
    )!;
    final data = MemberDataScope.of(context);
    // Gym visits sit in the same list, with what was logged during them.
    final recent = recentTimeline(activities, data.checkins);
    return [
      // DS v1.0 Activity board: Week / Month / Year, three tiles, bars.
      ActivityPeriodCard(data: data, now: today),
      const SizedBox(height: FFTokens.spacingMd),
      // Planning lives on the Workouts tab; Overview only surfaces a
      // workout that's actually on for today.
      if (todaysWorkouts(data.workouts, today).isNotEmpty)
        TodayWorkoutCard(data: data, now: today),
      FFSectionTitle(context.tr('activity.today')),
      const PhoneStepsCard(),
      const RecordRunButton(),
      if (activities.isEmpty)
        const ActivityGetStartedCard()
      else ...[
        _TodaySummary(
          steps: s.steps,
          stepGoal: stepGoal,
          cells: [
            (
              Icons.straighten,
              formatKm(s.distanceKm),
              context.tr(
                activities.any(
                      (a) =>
                          a.devicePlatform == DevicePlatform.phoneSensor &&
                          (a.distanceKm ?? 0) > 0 &&
                          dayOf(a.startedAt) == dayOf(today),
                    )
                    ? 'activity.distanceEstimated'
                    : 'activity.distance',
              ),
            ),
            (
              Icons.timer_outlined,
              '${s.activeMinutes}',
              context.tr('activity.activeMinutes'),
            ),
            (
              Icons.local_fire_department_outlined,
              s.calories == null ? '—' : formatSteps(s.calories!),
              context.tr('activity.calories'),
            ),
            (
              Icons.timeline,
              '${s.activityCount}',
              context.tr('activity.activities'),
            ),
            (
              Icons.fitness_center,
              '${s.workoutCount}',
              context.tr('activity.workoutCount'),
            ),
          ],
        ),
      ],
      const SizedBox(height: FFTokens.spacingSm),
      StreakCard(key: const Key('activity-streak'), streak: streak),
      FFSectionTitle(context.tr('activity.currentChallenge')),
      currentChallengeBlock(context, data, today),
      Row(
        children: [
          Expanded(child: FFSectionTitle(context.tr('activity.recent'))),
          _besideTitle(
            context,
            FFButton(
              key: const Key('data-origins-info'),
              label: context.tr('origin.link'),
              onPressed: () => showDataOriginsSheet(context),
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              icon: Icons.info_outline,
              maxLines: 2,
            ),
          ),
        ],
      ),
      if (recent.isEmpty)
        FFEmptyState(title: context.tr('activity.noActivity'))
      else ...[
        for (final e in recent) recentEntryTile(e),
        Align(
          alignment: Alignment.centerRight,
          child: FFButton(
            key: const Key('activity-view-more'),
            label: context.tr('activity.viewMore'),
            onPressed: () => context.push(AppRoutes.memberActivityHistory),
            variant: FFButtonVariant.ghost,
            size: FFButtonSize.sm,
            icon: Icons.history,
          ),
        ),
      ],
    ];
  }

  List<Widget> _workouts(BuildContext context, MemberData data, DateTime now) {
    final todayIds = todaysWorkouts(
      data.workouts,
      now,
    ).map((w) => w.id).toSet();
    final upcoming =
        data.workouts
            .where((w) => w.status.isOpen && !todayIds.contains(w.id))
            .where((w) => !w.scheduledDate.isBefore(dayOf(now)))
            .toList()
          ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
    final done = data.workouts
        .where((w) => w.status == WorkoutStatus.completed)
        .toList();
    // Workouts recorded some other way (a run, a class) — completed
    // structured workouts are already listed above.
    final other = data.activities
        .where((a) => a.isWorkout && a.workoutId == null)
        .toList();
    final noPlanNoWorkout =
        data.trainingLoaded &&
        data.workoutsLoaded &&
        data.trainingPlan == null &&
        todayIds.isEmpty;
    return [
      for (final offer in data.trainingOffers) TrainingOfferCard(offer: offer),
      TrainingPlanCard(data: data, now: now),
      if (noPlanNoWorkout)
        // One invitation, two actions: the plan card above already offers
        // "Create my plan", so the empty workout card becomes a quiet link.
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFButton(
            key: const Key('workout-plan'),
            fullWidth: true,
            variant: FFButtonVariant.secondary,
            label: context.tr('workout.plan'),
            onPressed: () => showPlanWorkoutSheet(context),
          ),
        )
      else
        TodayWorkoutCard(data: data, now: now),
      TrainerPlanBlock(data: data, now: now),
      if (todayIds.isNotEmpty || upcoming.isNotEmpty)
        Align(
          alignment: Alignment.centerRight,
          child: FFButton(
            key: const Key('workout-plan-more'),
            label: context.tr('workout.plan'),
            onPressed: () => showPlanWorkoutSheet(context),
            variant: FFButtonVariant.ghost,
            size: FFButtonSize.sm,
            icon: Icons.add,
          ),
        ),
      if (upcoming.isNotEmpty) ...[
        FFSectionTitle(context.tr('workout.upcoming')),
        for (final w in upcoming) WorkoutTile(workout: w),
      ],
      if (done.isNotEmpty) ...[
        FFSectionTitle(context.tr('workout.completedList')),
        for (final w in done) WorkoutTile(workout: w),
      ],
      FFSectionTitle(context.tr('workout.otherActivity')),
      if (other.isEmpty)
        FFEmptyState(title: context.tr('activity.noWorkouts'))
      else
        for (final a in other) ActivityTimelineTile(activity: a),
    ];
  }
}

/// Today's numbers in one card: steps (with the daily goal bar when there
/// is one) on top, the other measures in a compact grid below.
class _TodaySummary extends StatelessWidget {
  const _TodaySummary({
    required this.steps,
    required this.stepGoal,
    required this.cells,
  });

  final int steps;
  final int? stepGoal;
  final List<(IconData, String, String)> cells;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FFCard(
      key: stepGoal != null ? const Key('activity-daily-goal') : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
              stepGoal != null ? 'activity.dailyGoal' : 'activity.steps',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.directions_walk,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: FFTokens.spacingXs),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: formatSteps(steps),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    children: [
                      if (stepGoal != null)
                        TextSpan(
                          text: ' / ${formatSteps(stepGoal!)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (stepGoal != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            ActivityGoalBar(steps: steps, goal: stepGoal!),
          ],
          const Divider(height: FFTokens.spacingLg * 2),
          Wrap(
            runSpacing: FFTokens.spacingMd,
            children: [
              for (final c in cells)
                FractionallySizedBox(
                  widthFactor: 0.5,
                  child: Row(
                    children: [
                      Icon(c.$1, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: FFTokens.spacingSm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.$2,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              c.$3,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
