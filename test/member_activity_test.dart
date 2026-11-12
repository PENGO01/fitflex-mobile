import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/gym_visit_tile.dart';
import 'package:fitflexmobile/screens/member/widgets/today_activity_card.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/activity/activity_summary.dart';
import 'package:fitflexmobile/shared/activity/goal.dart';
import 'package:fitflexmobile/shared/activity/streaks.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 23, 20);

Activity _act(
  String id,
  DateTime at, {
  ActivityType type = ActivityType.walking,
  ActivitySource source = ActivitySource.device,
  int? steps,
  int? minutes,
  double? km,
  int? calories,
  String? gymId,
}) => Activity(
  id: id,
  userId: 'u1',
  type: type,
  source: source,
  startedAt: at,
  steps: steps,
  durationMinutes: minutes,
  activeMinutes: minutes,
  distanceKm: km,
  calories: calories,
  gymId: gymId,
);

CheckIn _visit(String id, DateTime at, {String gymId = 'gym_1'}) => CheckIn(
  id: id,
  memberId: 'u1',
  timestamp: at.toUtc().toIso8601String(),
  gymTier: 'gold',
  gymId: gymId,
  gym: Gym.fromJson({'id': gymId, 'name': 'Iron House'}),
);

DateTime _daysAgo(int n, [int hour = 8, int minute = 0]) =>
    DateTime(_now.year, _now.month, _now.day - n, hour, minute);

/// Today: 6,240 steps (78% of 8,000), a 52-min run → 1 workout.
/// Streak: today + 7 previous days of ≥30 active minutes, then a gap.
List<Activity> _history() => [
  _act('today-walk', _daysAgo(0, 7), steps: 6240, minutes: 40, km: 4.7),
  _act(
    'today-run',
    _daysAgo(0, 18),
    type: ActivityType.running,
    source: ActivitySource.fitflex,
    minutes: 12,
    km: 2.1,
    calories: 120,
  ),
  for (var d = 1; d <= 7; d++)
    _act('walk-$d', _daysAgo(d), steps: 5000, minutes: 45),
  _act('gap-walk', _daysAgo(9), steps: 900, minutes: 8),
];

Widget _wrap(Widget child, MemberData data) => FFLocaleScope(
  notifier: FFLocale(),
  child: MaterialApp(
    theme: buildTheme(),
    supportedLocales: const [Locale('en'), Locale('sw')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: MemberDataScope(data: data, child: child),
    ),
  ),
);

final _stepGoal = Goal(
  id: 'g-steps',
  userId: 'u1',
  type: GoalType.steps,
  target: 8000,
  period: GoalPeriod.day,
  startDate: DateTime(2026, 9, 1),
  source: GoalSource.defaults,
);

MemberData _data({
  bool sample = false,
  List<Activity>? activities,
  List<Goal>? goals,
}) => MemberData()
  ..activities = activities ?? _history()
  ..activityLoaded = true
  ..activityIsSample = sample
  ..goals = goals ?? [_stepGoal]
  ..goalsLoaded = true;

int _activityStreak(List<Activity> acts) =>
    computeStreak(StreakKind.activity, today: _now, activities: acts)!.current;

void main() {
  group('activity summary', () {
    test('totals today and separates workouts from passive steps', () {
      final s = summarizeDay(_history(), _now);
      expect(s.steps, 6240);
      expect(s.distanceKm, closeTo(6.8, 1e-9));
      expect(s.activeMinutes, 52);
      expect(s.calories, 120);
      expect(s.activityCount, 2);
      expect(s.workoutCount, 1);
      expect((s.goalProgress() * 100).round(), 78);
    });

    test('calories are unknown, not zero, when nothing reports them', () {
      expect(summarizeDay(_history(), _daysAgo(1)).calories, isNull);
    });

    test('manual walks count as workouts, device step walks do not', () {
      final manual = _act(
        'm',
        _now,
        source: ActivitySource.manual,
        minutes: 30,
      );
      expect(manual.isWorkout, isTrue);
      expect(_act('d', _now, steps: 100).isWorkout, isFalse);
    });

    test('streak counts back until the first inactive day', () {
      expect(_activityStreak(_history()), 8);
    });

    test('an unfinished today does not break the streak', () {
      final noToday = _history()
          .where((a) => !a.id.startsWith('today'))
          .toList();
      expect(_activityStreak(noToday), 7);
    });
  });

  testWidgets('Home card shows today, streak and goal progress', (
    tester,
  ) async {
    final data = _data(sample: true);
    await tester.pumpWidget(
      _wrap(TodayActivityCard(data: data, now: _now), data),
    );

    expect(find.text("Today's activity"), findsOneWidget);
    expect(find.textContaining('6,240'), findsOneWidget);
    expect(find.text('52'), findsOneWidget); // active minutes
    expect(find.text('8'), findsOneWidget); // streak
    expect(find.text("78% of today's goal"), findsOneWidget);
    expect(find.byKey(const Key('activity-sample-badge')), findsOneWidget);
    expect(find.text('View activity'), findsOneWidget);
  });

  testWidgets('Home card stays hidden until activity has loaded', (
    tester,
  ) async {
    final data = MemberData();
    await tester.pumpWidget(_wrap(TodayActivityCard(data: data), data));
    expect(find.byKey(const Key('today-activity-card')), findsNothing);
  });

  testWidgets('Home card hides the goal bar without a daily step goal', (
    tester,
  ) async {
    final data = _data(goals: []);
    await tester.pumpWidget(
      _wrap(TodayActivityCard(data: data, now: _now), data),
    );
    expect(find.byKey(const Key('activity-goal-percent')), findsNothing);
    expect(find.textContaining('6,240'), findsOneWidget);
  });

  testWidgets('Home card hides the sample badge for real data', (tester) async {
    final data = _data();
    await tester.pumpWidget(
      _wrap(TodayActivityCard(data: data, now: _now), data),
    );
    expect(find.byKey(const Key('activity-sample-badge')), findsNothing);
  });

  testWidgets('Activity has one Log activity action, in the header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final data = _data(sample: true);
    await tester.pumpWidget(_wrap(MemberActivityTab(now: _now), data));
    expect(find.byKey(const Key('activity-log-open')), findsOneWidget);
    expect(find.text('Log activity'), findsOneWidget);

    await tester.tap(find.text('Training'));
    await tester.pump();
    expect(find.byKey(const Key('activity-log-open')), findsOneWidget);
    expect(find.byKey(const Key('workouts-log-open')), findsNothing);
  });

  testWidgets('Activity tab overview and section switching', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final data = _data(sample: true);
    await tester.pumpWidget(_wrap(MemberActivityTab(now: _now), data));

    for (final label in ['Today', 'Training', 'Challenges', 'Progress']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.textContaining('6,240'), findsWidgets);
    expect(find.text('120'), findsOneWidget); // calories
    expect(find.byKey(const Key('activity-daily-goal')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('activity-streak')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('8-day activity streak'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('activity-no-challenge')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No active challenge'), findsOneWidget);

    Finder section(String label) => find.descendant(
      of: find.byKey(const Key('activity-sections')),
      matching: find.text(label),
    );
    // Back to the top, where the section control lives.
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 3000),
      3000,
    );
    await tester.pumpAndSettle();
    // The section control may scroll sideways at phone width.
    await tester.ensureVisible(section('Training'));
    await tester.tap(section('Training'));
    await tester.pumpAndSettle();
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Walking'), findsNothing);

    // The section control may scroll sideways at phone width.
    await tester.ensureVisible(section('Progress'));
    await tester.tap(section('Progress'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('progress-goals')), findsOneWidget);
  });

  testWidgets('Activity tab shows empty states without history', (
    tester,
  ) async {
    final data = _data(activities: []);
    await tester.pumpWidget(_wrap(MemberActivityTab(now: _now), data));
    await tester.scrollUntilVisible(
      find.text('No activity logged yet.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No activity logged yet.'), findsOneWidget);
    expect(find.text('Start a streak today.'), findsOneWidget);
  });

  testWidgets('no activity yet: a get-started card, not a card of zeros', (
    tester,
  ) async {
    final data = MemberData()..activityLoaded = true;
    await tester.pumpWidget(_wrap(TodayActivityCard(data: data), data));
    expect(find.byKey(const Key('activity-get-started')), findsOneWidget);
    expect(find.byKey(const Key('activity-get-started-plan')), findsOneWidget);
    expect(find.byKey(const Key('today-activity-steps')), findsNothing);

    // Sample mode always has history to show.
    data.activityIsSample = true;
    await tester.pumpWidget(_wrap(TodayActivityCard(data: data), data));
    expect(find.byKey(const Key('activity-get-started')), findsNothing);
  });

  group('recent timeline with gym visits', () {
    test('visits sit among activities, newest first', () {
      final t = recentTimeline(
        [_act('a1', _daysAgo(0, 7)), _act('a2', _daysAgo(2, 7))],
        [_visit('v1', _daysAgo(1, 18))],
      );
      expect(t.map((e) => e.at), [
        _daysAgo(0, 7),
        _daysAgo(1, 18),
        _daysAgo(2, 7),
      ]);
      expect(t[1], isA<RecentVisitEntry>());
    });

    test(
      'the next day still counts; past 48 hours or well before does not',
      () {
        final visitAt = _daysAgo(3, 18);
        final t = recentTimeline(
          [
            _act(
              'next-day',
              visitAt.add(const Duration(hours: 30)),
              gymId: 'gym_1',
            ),
            _act(
              'too-late',
              visitAt.add(const Duration(hours: 49)),
              gymId: 'gym_1',
            ),
            _act(
              'too-early',
              visitAt.subtract(const Duration(hours: 2)),
              gymId: 'gym_1',
            ),
            _act(
              'warm-up',
              visitAt.subtract(const Duration(minutes: 30)),
              gymId: 'gym_1',
            ),
          ],
          [_visit('v1', visitAt)],
          limit: null,
        );
        final visit = t.whereType<RecentVisitEntry>().single;
        expect(visit.activities.map((a) => a.id), ['warm-up', 'next-day']);
        expect(
          t.whereType<RecentActivityEntry>().map((e) => e.activity.id).toSet(),
          {'too-late', 'too-early'},
        );
      },
    );

    test('weeks of the month: W1 1–7 … W4 22 to month end', () {
      expect(monthWeekOf(DateTime(2026, 1, 1)).week, 1);
      expect(monthWeekOf(DateTime(2026, 1, 7)).week, 1);
      expect(monthWeekOf(DateTime(2026, 1, 8)).week, 2);
      expect(monthWeekOf(DateTime(2026, 1, 21)).week, 3);
      expect(monthWeekOf(DateTime(2026, 1, 31)).week, 4);
      expect(monthWeekRange((year: 2026, month: 1, week: 4)), (
        DateTime(2026, 1, 22),
        DateTime(2026, 1, 31),
      ));
      expect(
        monthWeekRange((year: 2026, month: 2, week: 4)).$2,
        DateTime(2026, 2, 28),
      );
    });

    test('groups newest week first, entries keep their order', () {
      final t = recentTimeline(
        [
          _act('feb2', DateTime(2026, 2, 3, 9)),
          _act('jan31', DateTime(2026, 1, 31, 9)),
          _act('jan23', DateTime(2026, 1, 23, 9)),
          _act('jan2', DateTime(2026, 1, 2, 9)),
        ],
        const [],
        limit: null,
      );
      final g = groupByMonthWeek(t);
      expect(g.map((e) => (e.$1.month, e.$1.week)), [(2, 1), (1, 4), (1, 1)]);
      expect(g[1].$2.map((e) => e.at.day), [31, 23]);
    });

    test('an activity at the visit gym that day goes inside the visit', () {
      final lifted = _act(
        'lift',
        _daysAgo(1, 19),
        type: ActivityType.strength,
        source: ActivitySource.manual,
        gymId: 'gym_1',
      );
      final elsewhere = _act('other-gym', _daysAgo(1, 9), gymId: 'gym_2');
      final t = recentTimeline(
        [lifted, elsewhere],
        [_visit('v1', _daysAgo(1, 18))],
      );
      expect(t.length, 2);
      final visit = t.whereType<RecentVisitEntry>().single;
      expect(visit.activities.map((a) => a.id), ['lift']);
      expect(t.whereType<RecentActivityEntry>().map((e) => e.activity.id), [
        'other-gym',
      ]);
    });

    test('two visits the same day: the activity joins the closer one', () {
      final t = recentTimeline(
        [_act('pm', _daysAgo(1, 18), gymId: 'gym_1')],
        [_visit('am', _daysAgo(1, 7)), _visit('eve', _daysAgo(1, 17))],
      );
      final byId = {
        for (final v in t.whereType<RecentVisitEntry>())
          v.checkin.id: v.activities.length,
      };
      expect(byId, {'am': 0, 'eve': 1});
    });

    test('keeps at most eight rows', () {
      final t = recentTimeline(
        [for (var d = 0; d < 6; d++) _act('a$d', _daysAgo(d))],
        [for (var d = 0; d < 6; d++) _visit('v$d', _daysAgo(d, 18))],
      );
      expect(t.length, 8);
    });
  });

  testWidgets('Recent activity offers View more', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(MemberActivityTab(now: _now), _data()));
    await tester.scrollUntilVisible(
      find.byKey(const Key('activity-view-more')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('View more'), findsOneWidget);
  });

  testWidgets('a plain gym visit opens to log what was done', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final data = _data()..checkins = [_visit('v1', _daysAgo(0, 19))];
    await tester.pumpWidget(_wrap(MemberActivityTab(now: _now), data));
    await tester.scrollUntilVisible(
      find.byKey(const Key('visit-v1')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Gym visit · Iron House'), findsOneWidget);
    expect(find.textContaining('Nothing logged yet'), findsOneWidget);
    expect(find.byKey(const Key('visit-log-v1')), findsNothing);

    await tester.tap(find.byKey(const Key('visit-toggle-v1')));
    await tester.pump();
    expect(find.byKey(const Key('visit-log-v1')), findsOneWidget);
    expect(find.text('Log what you did'), findsOneWidget);
  });

  testWidgets('a visit with a logged session lists it once, inside', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final data = _data(
      activities: [
        ..._history(),
        _act(
          'lift',
          _daysAgo(0, 19, 30),
          type: ActivityType.strength,
          source: ActivitySource.manual,
          minutes: 50,
          gymId: 'gym_1',
        ),
      ]..sort((a, b) => b.startedAt.compareTo(a.startedAt)),
    )..checkins = [_visit('v1', _daysAgo(0, 19))];
    await tester.pumpWidget(_wrap(MemberActivityTab(now: _now), data));
    await tester.scrollUntilVisible(
      find.byKey(const Key('visit-v1')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('1 logged'), findsOneWidget);
    expect(find.byKey(const Key('activity-lift')), findsNothing);

    await tester.tap(find.byKey(const Key('visit-toggle-v1')));
    await tester.pump();
    expect(find.byKey(const Key('activity-lift')), findsOneWidget);
    expect(find.text('Log another activity'), findsOneWidget);
  });

  testWidgets('a visit past 90 days can be opened but not logged', (
    tester,
  ) async {
    final c = _visit('old', _daysAgo(100, 18));
    await tester.pumpWidget(
      _wrap(
        GymVisitTile(
          entry: RecentVisitEntry(c, _daysAgo(100, 18), const []),
          now: _now,
        ),
        _data(),
      ),
    );
    await tester.tap(find.byKey(const Key('visit-toggle-old')));
    await tester.pump();
    expect(find.byKey(const Key('visit-too-old-old')), findsOneWidget);
    expect(find.text('Nothing logged'), findsOneWidget);
    expect(find.byKey(const Key('visit-log-old')), findsNothing);
  });
}
