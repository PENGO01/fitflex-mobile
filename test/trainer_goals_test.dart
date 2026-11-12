import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/goal_widgets.dart';
import 'package:fitflexmobile/screens/trainer/widgets/trainer_goals.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/activity/goal.dart';
import 'package:fitflexmobile/shared/activity/goal_repository.dart';
import 'package:fitflexmobile/shared/activity/progress_engine.dart';
import 'package:fitflexmobile/shared/activity/streaks.dart';
import 'package:fitflexmobile/shared/activity/trainer_connection.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Thursday 24 Sep 2026, 09:00. Week: Mon 21 – Sun 27.
final _now = DateTime(2026, 9, 24, 9);

Map<String, dynamic> _trainerWeekJson() => {
  'id': 'g_t',
  'userId': 'u1',
  'type': 'workouts',
  'period': 'custom',
  'target': 4,
  'startDate': '2026-09-23',
  'endDate': '2026-09-29',
  'source': 'trainer',
  'trainerId': 'trn_1',
  'createdByType': 'trainer',
  'createdById': 'usr_t1',
  'createdBy': {'type': 'trainer', 'id': 'trn_1', 'name': 'Sarah'},
  'status': 'active',
};

Goal _coaching({List<DateTime> done = const []}) => Goal(
  id: 'g_c',
  userId: 'u1',
  type: GoalType.custom,
  target: 3,
  period: GoalPeriod.week,
  startDate: DateTime(2026, 9, 1),
  source: GoalSource.trainer,
  trainerId: 'trn_1',
  createdByType: GoalCreatorType.trainer,
  createdByName: 'Sarah',
  title: 'Stretch after every session',
  completions: done,
);

Activity _run(int day) => Activity(
  id: 'r$day',
  userId: 'u1',
  type: ActivityType.running,
  source: ActivitySource.fitflex,
  startedAt: DateTime(2026, 9, day, 7),
  durationMinutes: 30,
);

/// Records check-ins and returns the goal with the change applied.
class _Repo implements GoalRepository {
  _Repo(this.goal);
  Goal goal;
  final calls = <String>[];

  @override
  Future<Goal> checkIn(String id, {bool undo = false}) async {
    calls.add(undo ? 'undo $id' : 'done $id');
    final c = [...goal.completions];
    undo ? c.removeLast() : c.add(_now);
    return goal = goal.copyWith(completions: c);
  }

  @override
  Future<List<Goal>> list() async => [goal];
  @override
  Future<Goal> create({
    required GoalType type,
    required GoalPeriod period,
    required num target,
    DateTime? startDate,
    DateTime? endDate,
  }) => throw UnimplementedError();
  @override
  Future<Goal> update(String id, {num? target, GoalStatus? status}) =>
      throw UnimplementedError();
}

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://x');
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> trainerAssignGoal(
    String relationshipId,
    Map<String, dynamic> body,
  ) async {
    bodies.add(body);
    return {'goal': {}};
  }
}

Widget _wrap(
  Widget child, {
  ApiClient? api,
  GoalRepository? repo,
  MemberData? data,
}) {
  final a = api ?? _Api();
  return AppScope(
    api: a,
    auth: AuthState(a),
    goalRepository: repo,
    child: FFLocaleScope(
      notifier: FFLocale(),
      child: MemberDataScope(
        data: data ?? MemberData(),
        child: MaterialApp(
          theme: buildTheme(),
          supportedLocales: const [Locale('en'), Locale('sw')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: ListView(children: [child])),
        ),
      ),
    ),
  );
}

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 5000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

void main() {
  group('model', () {
    test('a trainer goal knows who set it', () {
      final g = Goal.tryParse(_trainerWeekJson())!;
      expect(g.isFromTrainer, isTrue);
      expect(g.createdByType, GoalCreatorType.trainer);
      expect(g.createdById, 'usr_t1');
      expect(g.createdByName, 'Sarah');
      expect(g.toJson()['createdByType'], 'trainer');
    });

    test('older rows without createdByType fall back to the source', () {
      final json = _trainerWeekJson()..remove('createdByType');
      expect(Goal.tryParse(json)!.createdByType, GoalCreatorType.trainer);
      final defaults = {..._trainerWeekJson(), 'source': 'default'}
        ..remove('createdByType');
      expect(Goal.tryParse(defaults)!.createdByType, GoalCreatorType.system);
    });

    test('coaching goals parse with title and completions', () {
      final g = Goal.tryParse({
        ..._trainerWeekJson(),
        'type': 'custom',
        'period': 'week',
        'target': 3,
        'title': 'Stretch after every session',
        'completions': ['2026-09-22T05:00:00.000Z'],
      })!;
      expect(g.isCoaching, isTrue);
      expect(g.completions, hasLength(1));
    });
  });

  group('progress', () {
    test('trainer weekly workout goal counts workouts in its dates', () {
      final g = Goal.tryParse(_trainerWeekJson())!;
      final p = evaluateGoal(g, [_run(22), _run(23), _run(24)], _now);
      expect(p.current, 2, reason: 'the 22nd is before 23–29 Sep');
    });

    test('coaching goals count "done" marks in the current period only', () {
      final g = _coaching(
        done: [
          DateTime(2026, 9, 18, 8), // last week
          DateTime(2026, 9, 22, 8),
          DateTime(2026, 9, 23, 8),
        ],
      );
      final p = evaluateGoal(g, const [], _now);
      expect(p.current, 2);
      expect(p.completed, isFalse);
    });

    test('a daily coaching goal feeds the goal streak', () {
      final daily = Goal(
        id: 'd',
        userId: 'u1',
        type: GoalType.custom,
        target: 1,
        period: GoalPeriod.day,
        startDate: DateTime(2026, 9, 1),
        completions: [
          DateTime(2026, 9, 22, 8),
          DateTime(2026, 9, 23, 8),
          DateTime(2026, 9, 24, 8),
        ],
      );
      final s = computeStreak(StreakKind.goal, today: _now, goals: [daily])!;
      expect(s.current, 3);
    });
  });

  group('titles', () {
    testWidgets('dated, coaching and challenge goal titles', (t) async {
      String? dated, coaching, challenge;
      await t.pumpWidget(
        _wrap(
          Builder(
            builder: (c) {
              dated = goalTitle(c, Goal.tryParse(_trainerWeekJson())!);
              coaching = goalTitle(c, _coaching());
              challenge = goalTitle(
                c,
                Goal.tryParse({
                  ..._trainerWeekJson(),
                  'type': 'steps',
                  'target': 30000,
                  'challengeId': 'ch_1',
                  'title': '50K Step Challenge',
                })!,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(dated, '4 workouts, 23–29 Sep');
      expect(coaching, 'Stretch after every session');
      expect(challenge, '50K Step Challenge');
    });
  });

  group('member sees', () {
    testWidgets('trainer goals first, labelled, with who assigned them', (
      t,
    ) async {
      _tall(t);
      final data = MemberData()
        ..goalsLoaded = true
        ..activities = [_run(23), _run(24)]
        ..goals = [
          Goal(
            id: 'mine',
            userId: 'u1',
            type: GoalType.steps,
            target: 8000,
            period: GoalPeriod.day,
            startDate: DateTime(2026, 9, 1),
          ),
          Goal.tryParse(_trainerWeekJson())!,
        ];
      await t.pumpWidget(
        _wrap(
          GoalsBlock(data: data, now: _now),
          data: data,
        ),
      );
      expect(find.text('From your trainer'), findsOneWidget);
      expect(find.text('Your goals'), findsOneWidget);
      expect(find.byKey(const Key('goal-trainer-label-g_t')), findsOneWidget);
      expect(find.text('Trainer goal'), findsOneWidget);
      expect(find.text('Assigned by Sarah'), findsOneWidget);
      expect(find.text('4 workouts, 23–29 Sep'), findsOneWidget);
      expect(find.textContaining('2 of 4'), findsOneWidget);
      final trainerY = t.getTopLeft(find.byKey(const Key('goal-g_t'))).dy;
      final mineY = t.getTopLeft(find.byKey(const Key('goal-mine'))).dy;
      expect(trainerY, lessThan(mineY));
    });

    testWidgets('a coaching goal is marked done and undone', (t) async {
      _tall(t);
      final repo = _Repo(_coaching());
      final data = MemberData()
        ..goalsLoaded = true
        ..goals = [repo.goal];
      await t.pumpWidget(
        _wrap(
          Builder(
            builder: (c) => GoalsBlock(data: MemberDataScope.of(c), now: _now),
          ),
          repo: repo,
          data: data,
        ),
      );
      expect(find.text('Coaching goal'), findsOneWidget);
      expect(find.byKey(const Key('goal-undo-g_c')), findsNothing);
      await t.tap(find.byKey(const Key('goal-mark-g_c')));
      await t.pumpAndSettle();
      expect(repo.calls, ['done g_c']);
      expect(data.goals.single.completions, hasLength(1));
      expect(find.textContaining('1 of 3'), findsOneWidget);
      await t.tap(find.byKey(const Key('goal-undo-g_c')));
      await t.pumpAndSettle();
      expect(repo.calls.last, 'undo g_c');
      expect(find.textContaining('0 of 3'), findsOneWidget);
    });
  });

  group('trainer', () {
    ClientOverview overview({bool goals = false, bool challenges = false}) =>
        ClientOverview.fromJson({
          'client': {
            'id': 'tmr_1',
            'trainerId': 'trn_1',
            'memberId': 'u1',
            'status': 'active',
            'permissions': {'goals': goals, 'challenges': challenges},
            'member': {'id': 'u1', 'displayName': 'Aisha'},
          },
          'assignedGoals': [
            {
              ..._trainerWeekJson(),
              if (goals) 'progress': {'current': 2, 'completed': false},
            },
          ],
          if (challenges)
            'goalChallenges': [
              {
                'id': 'ch_1',
                'name': '50K Step Challenge',
                'type': 'steps',
                'target': 50000,
                'startDate': '2026-09-20',
                'endDate': '2026-09-30',
              },
            ],
        });

    testWidgets('sees goals they set; progress only when shared', (t) async {
      _tall(t);
      await t.pumpWidget(
        _wrap(
          TrainerGoalsSection(
            clientName: 'Aisha',
            relationshipId: 'tmr_1',
            overview: overview(),
            now: _now,
            onChanged: () async {},
          ),
        ),
      );
      expect(find.byKey(const Key('trainer-goal-g_t')), findsOneWidget);
      expect(
        find.byKey(const Key('trainer-goal-progress-hidden')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('trainer-goal-progress-g_t')), findsNothing);

      await t.pumpWidget(
        _wrap(
          TrainerGoalsSection(
            clientName: 'Aisha',
            relationshipId: 'tmr_1',
            overview: overview(goals: true),
            now: _now,
            onChanged: () async {},
          ),
        ),
      );
      expect(
        find.byKey(const Key('trainer-goal-progress-hidden')),
        findsNothing,
      );
      expect(
        t.widget<Text>(find.byKey(const Key('trainer-goal-progress-g_t'))).data,
        '2 of 4 · 50%',
      );
    });

    Future<Map<String, dynamic>?> sheet(
      WidgetTester t,
      Future<void> Function() steps, {
      List<GoalChallenge>? challenges,
    }) async {
      _tall(t);
      Map<String, dynamic>? sent;
      await t.pumpWidget(
        _wrap(
          AssignGoalSheet(
            clientName: 'Aisha',
            challenges: challenges,
            now: DateTime(2026, 9, 23, 9),
            onSave: (b) async {
              sent = b;
              return {};
            },
          ),
        ),
      );
      await steps();
      await t.tap(find.byKey(const Key('assign-goal-save')));
      await t.pumpAndSettle();
      return sent;
    }

    testWidgets('default: 4 workouts over the next 7 days', (t) async {
      final body = await sheet(t, () async {
        expect(find.text('23–29 Sep'), findsOneWidget);
      });
      expect(body, {
        'type': 'workouts',
        'target': 4,
        'period': 'custom',
        'startDate': '2026-09-23',
        'endDate': '2026-09-29',
      });
    });

    testWidgets('steps every day', (t) async {
      final body = await sheet(t, () async {
        await t.tap(find.byKey(const Key('goal-kind-steps')));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('goal-target')), '10000');
        await t.tap(find.byKey(const Key('goal-when-day')));
        await t.pumpAndSettle();
      });
      expect(body, {'type': 'steps', 'target': 10000, 'period': 'day'});
    });

    testWidgets('a coaching goal needs its text', (t) async {
      final missing = await sheet(t, () async {
        await t.tap(find.byKey(const Key('goal-kind-coaching')));
        await t.pumpAndSettle();
      });
      expect(missing, isNull);
      expect(find.text('Say what the coaching goal is.'), findsOneWidget);
    });

    testWidgets('a coaching goal: text, times, every week', (t) async {
      final body = await sheet(t, () async {
        await t.tap(find.byKey(const Key('goal-kind-coaching')));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('goal-title')),
          'Stretch after sessions',
        );
        await t.tap(find.byKey(const Key('goal-when-week')));
        await t.pumpAndSettle();
      });
      expect(body, {
        'type': 'custom',
        'target': 3,
        'title': 'Stretch after sessions',
        'period': 'week',
      });
    });

    testWidgets('no challenge goals when challenges aren\'t shared', (t) async {
      final body = await sheet(t, () async {
        expect(find.byKey(const Key('goal-kind-challenge')), findsNothing);
        expect(find.textContaining('shares challenge data'), findsOneWidget);
      });
      expect(body?['type'], 'workouts');
    });

    testWidgets('a challenge goal takes the chosen challenge', (t) async {
      final c = overview(challenges: true).goalChallenges!;
      final body = await sheet(t, () async {
        await t.tap(find.byKey(const Key('goal-kind-challenge')));
        await t.pumpAndSettle();
        expect(find.text('Runs 20–30 Sep'), findsOneWidget);
        await t.enterText(find.byKey(const Key('goal-target')), '30000');
      }, challenges: c);
      expect(body, {'challengeId': 'ch_1', 'target': 30000});
    });
  });
}
