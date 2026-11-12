import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/home_feed.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/activity/challenge.dart';
import 'package:fitflexmobile/shared/activity/goal.dart';
import 'package:fitflexmobile/shared/activity/trainer_connection.dart';
import 'package:fitflexmobile/shared/activity/workout.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Thursday 24 Sep 2026, 18:00.
final _evening = DateTime(2026, 9, 24, 18);
final _morning = DateTime(2026, 9, 24, 9);

Map<String, dynamic> _gymJson(String id, String name) => {
  'id': id,
  'name': name,
  'tier': 'standard',
  'location': 'Dar es Salaam',
  'perVisitRate': 5000,
  'commissionRate': 10,
  'status': 'active',
};

MemberMeResponse _me({bool pass = true}) => MemberMeResponse.fromJson({
  'user': {
    'id': 'u1',
    'displayName': 'Amina Said',
    'onboardingCompleted': true,
  },
  'visitsUsed': 2,
  'visitCap': 12,
  if (pass)
    'subscription': {
      'id': 's1',
      'type': 'pass',
      'tier': 'pro',
      'status': 'active',
      'startedAt': '2026-09-01T00:00:00.000Z',
      'expiresAt': '2099-10-01T00:00:00.000Z',
    },
});

/// A 40-minute run on each of [days] (days of September 2026).
List<Activity> _runs(Iterable<int> days) => [
  for (final d in days)
    Activity(
      id: 'run$d',
      userId: 'u1',
      type: ActivityType.running,
      source: ActivitySource.fitflex,
      startedAt: DateTime(2026, 9, d, 7),
      durationMinutes: 40,
      activeMinutes: 40,
    ),
];

CheckIn _visit(String gymId, int day) => CheckIn.fromJson({
  'id': 'ci$day',
  'memberId': 'u1',
  'timestamp': '2026-09-${day.toString().padLeft(2, '0')}T05:00:00Z',
  'gymTier': 'standard',
  'gymId': gymId,
});

Workout _workout({WorkoutStatus status = WorkoutStatus.planned}) => Workout(
  id: 'w1',
  userId: 'u1',
  name: 'Upper body',
  activityType: ActivityType.strength,
  scheduledDate: DateTime(2026, 9, 24),
  status: status,
  exercises: const [],
);

Goal _goal(String id, GoalType type, GoalPeriod period, num target) => Goal(
  id: id,
  userId: 'u1',
  type: type,
  target: target,
  period: period,
  startDate: DateTime(2026, 9, 1),
);

Challenge _challenge({
  String end = '2026-10-10',
  bool joined = true,
  num target = 50000,
  String type = 'steps',
}) => Challenge.tryParse({
  'id': 'c1',
  'name': '50K Step Challenge',
  'type': type,
  'target': target,
  'startDate': '2026-09-20',
  'endDate': end,
  'creatorType': 'fitflex',
  'creator': {'type': 'fitflex'},
  'phase': 'active',
  'joined': joined,
  'participantCount': 12,
})!;

/// A member with an active pass and everything loaded but empty.
MemberData _base() => MemberData()
  ..me = _me()
  ..gyms = [
    Gym.fromJson(_gymJson('g1', 'Mikocheni Fitness')),
    Gym.fromJson(_gymJson('g2', 'Oyster Bay Gym')),
  ]
  ..trainers = [
    TrainerProfile.fromJson({'id': 't1', 'displayName': 'Coach Sarah'}),
  ]
  ..checkins = [_visit('g1', 20)]
  ..activityLoaded = true
  ..goalsLoaded = true
  ..goals = [_goal('g', GoalType.steps, GoalPeriod.day, 8000)]
  ..workoutsLoaded = true
  ..challengesLoaded = true;

List<String> _kinds(List<HomeCardPick> p) => [for (final x in p) x.kind.name];
HomeReason? _reason(List<HomeCardPick> p, HomeCardKind k) =>
    p.where((x) => x.kind == k).firstOrNull?.reason;

void main() {
  test('a quiet day gives a short Home', () {
    final p = pickHomeCards(_base()..activities = _runs([20]), _morning);
    expect(_kinds(p), ['todayActivity', 'passport', 'recommendation']);
    expect(
      _kinds(pickHomeCards(_base(), _morning)).take(2),
      ['passport', 'todayActivity'],
      reason: 'with no history, today\'s card is a get-started card',
    );
    final direct = _base()
      ..activities = _runs([20])
      ..me = MemberMeResponse.fromJson({
        'user': {'id': 'u1', 'onboardingCompleted': true},
        'subscription': {
          'type': 'direct_sub',
          'status': 'active',
          'homeGymId': 'g1',
          'expiresAt': '2099-01-01T00:00:00.000Z',
        },
      });
    expect(
      _kinds(pickHomeCards(direct, _morning)),
      ['todayActivity', 'passport'],
      reason: 'a single-gym member who visits needs no suggestion',
    );
  });

  test('no pass: the passport comes first and asks for action', () {
    final d = _base()
      ..me = _me(pass: false)
      ..checkins = [];
    final p = pickHomeCards(d, _morning);
    expect(p.first.kind, HomeCardKind.passport);
    expect(p.first.reason, HomeReason.passNeedsAction);
    expect(_reason(p, HomeCardKind.recommendation), HomeReason.gymExplore);
  });

  test('a pass never used: recommends the nearest gym', () {
    final d = _base()..checkins = [];
    final p = pickHomeCards(d, _morning, lat: -6.77, lng: 39.24);
    expect(p.first.reason, HomeReason.gymUsePass);
    expect(p.first.gym, isNotNull);
  });

  test('a multi-gym pass used at one gym: suggests another gym', () {
    final p = pickHomeCards(_base(), _morning);
    // Below today's activity and the passport, but still shown.
    expect(_kinds(p), contains('recommendation'));
    final r = p.firstWhere((x) => x.kind == HomeCardKind.recommendation);
    expect(r.reason, HomeReason.gymTryNew);
    expect(r.gym!.id, 'g2', reason: 'g1 was visited already');
  });

  test('a workout in progress goes to the top', () {
    final d = _base()..workouts = [_workout(status: WorkoutStatus.inProgress)];
    final p = pickHomeCards(d, _morning);
    expect(p.first.kind, HomeCardKind.todayWorkout);
    expect(p.first.reason, HomeReason.workoutInProgress);
  });

  test('a streak is only at risk late in the day with nothing counted', () {
    final d = _base()..activities = _runs([19, 20, 21, 22, 23]);
    expect(_reason(pickHomeCards(d, _morning), HomeCardKind.streak), isNull);
    final p = pickHomeCards(d, _evening);
    expect(_reason(p, HomeCardKind.streak), HomeReason.streakAtRisk);
    expect(p.first.kind, HomeCardKind.streak);

    d.activities = _runs([18, 19, 20, 21, 22, 23, 24]);
    expect(
      _reason(pickHomeCards(d, _evening), HomeCardKind.streak),
      HomeReason.streakMilestone,
      reason: '7 days',
    );
    d.activities = _runs([20, 21, 22, 23, 24]);
    final best = pickHomeCards(d, _evening);
    expect(_reason(best, HomeCardKind.streak), HomeReason.streakBest);
    expect(
      _kinds(best).indexOf('todayActivity'),
      lessThan(_kinds(best).indexOf('streak')),
      reason: "a personal best doesn't outrank today's numbers",
    );
    d.activities = _runs([17, 18, 19, 20, 21, 22]);
    expect(
      _reason(pickHomeCards(d, _evening), HomeCardKind.streak),
      HomeReason.streakEnded,
    );
  });

  test('never more than four cards, and the passport always stays', () {
    final d = _base()
      ..workouts = [_workout(status: WorkoutStatus.inProgress)]
      ..activities = _runs([19, 20, 21, 22, 23])
      ..challenges = [
        _challenge(end: '2026-09-25', type: 'workouts', target: 20),
      ]
      ..goals = [_goal('w', GoalType.workouts, GoalPeriod.month, 6)];
    final p = pickHomeCards(d, _evening);
    expect(p, hasLength(4));
    expect(
      _kinds(p),
      ['todayWorkout', 'streak', 'challenge', 'passport'],
      reason: 'the goal and today\'s activity make way for the passport',
    );
    expect(_reason(p, HomeCardKind.challenge), HomeReason.challengeEndingSoon);
  });

  test('goals: almost there beats in progress; step goal stays in the bar', () {
    final d = _base()
      ..activities = _runs([20, 21, 22])
      ..goals = [
        _goal('steps', GoalType.steps, GoalPeriod.day, 8000),
        _goal('far', GoalType.activeMinutes, GoalPeriod.month, 1000),
        _goal('near', GoalType.workouts, GoalPeriod.month, 4),
      ];
    final g = pickHomeCards(
      d,
      _morning,
    ).firstWhere((x) => x.kind == HomeCardKind.goal);
    expect(g.reason, HomeReason.goalAlmostThere);
    expect(g.goal!.goal.id, 'near');

    d.goals = [];
    expect(
      _reason(pickHomeCards(d, _morning, max: 10), HomeCardKind.goal),
      HomeReason.goalSetOne,
    );
  });

  test('trainer suggestion only for regulars without a trainer', () {
    final d = _base()
      ..checkins = [_visit('g1', 20), _visit('g2', 21)]
      ..activities = _runs([10, 14, 20]);
    expect(
      _reason(pickHomeCards(d, _morning), HomeCardKind.recommendation),
      HomeReason.trainerRegular,
    );
    d.trainerConnections = [
      TrainerConnection.fromJson({
        'id': 'r1',
        'trainerId': 't1',
        'memberId': 'u1',
        'status': 'active',
      }),
    ];
    expect(
      _reason(pickHomeCards(d, _morning), HomeCardKind.recommendation),
      isNull,
    );
  });

  test('an open challenge is an invitation, not a priority', () {
    final d = _base()..challenges = [_challenge(joined: false)];
    final c = pickHomeCards(
      d,
      _morning,
    ).firstWhere((x) => x.kind == HomeCardKind.challenge);
    expect(c.reason, HomeReason.challengeInvite);
    expect(c.score, lessThan(50));
  });

  testWidgets('Home renders the picks in order without the old lists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final data = _base()
      ..activities = _runs([19, 20, 21, 22, 23])
      ..workouts = [_workout()];
    final api = ApiClient();
    await tester.pumpWidget(
      AppScope(
        api: api,
        auth: AuthState(api),
        child: FFLocaleScope(
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
              body: MemberDataScope(
                data: data,
                child: MemberHomeTab(now: _evening),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final order = [
      // The pass (check-in QR) always leads; the rest keep their ranking.
      for (final k in ['passport', 'streak', 'todayWorkout'])
        tester.getTopLeft(find.byKey(Key('home-card-$k'))).dy,
    ];
    expect(order, [...order]..sort());
    // DS v1.0: This week and the stat tiles replace today's activity card.
    expect(find.byKey(const Key('home-card-todayActivity')), findsNothing);
    expect(find.textContaining('Good evening'), findsOneWidget);
    // DS v1.0 Home board: the streak is the forest tile beside visits.
    expect(
      find.descendant(
        of: find.byKey(const Key('home-stat-streak')),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('home-week')), findsOneWidget);
    // Its own cards exist, so the activity card drops those rows.
    expect(find.byKey(const Key('home-today-workout')), findsNothing);
    expect(find.text('Featured trainers'), findsNothing);
    expect(find.text('Gyms near you'), findsNothing);
    expect(find.byKey(const Key('home-recommendation')), findsNothing);
  });
}
