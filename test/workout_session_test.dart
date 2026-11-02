import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/workout_widgets.dart';
import 'package:fitflexmobile/shared/activity/sample_activity_log.dart';
import 'package:fitflexmobile/shared/activity/workout.dart';
import 'package:fitflexmobile/shared/activity/workout_repository.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 23, 18);

Widget _app(MemberData data, WorkoutRepository repo, Widget child) {
  final api = ApiClient();
  return AppScope(
    api: api,
    auth: AuthState(api),
    workoutRepository: repo,
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
          body: MemberDataScope(data: data, child: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets("Today's workout lists exercises with targets", (tester) async {
    final repo = LocalWorkoutRepository(
      log: SampleActivityLog(),
      clock: () => _now,
    );
    final w = await repo.plan(templateId: 'tpl_upper_strength', date: _now);
    final data = MemberData()
      ..workouts = [w]
      ..workoutsLoaded = true;
    await tester.pumpWidget(
      _app(data, repo, TodayWorkoutCard(data: data, now: _now)),
    );

    expect(find.text('Upper Body Strength'), findsOneWidget);
    expect(find.text('5 exercises · 45 min'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('3 × 10'), findsWidgets);
    expect(find.text('Lat Pulldown'), findsOneWidget);
    expect(find.text('3 × 12'), findsWidgets);
    expect(find.text('+1 more'), findsOneWidget);
    expect(find.text('Start workout'), findsOneWidget);
  });

  testWidgets('No workout today invites planning one', (tester) async {
    final repo = LocalWorkoutRepository(
      log: SampleActivityLog(),
      clock: () => _now,
    );
    final data = MemberData()..workoutsLoaded = true;
    await tester.pumpWidget(
      _app(data, repo, TodayWorkoutCard(data: data, now: _now)),
    );
    expect(find.text('No workout planned for today'), findsOneWidget);

    await tester.tap(find.byKey(const Key('workout-plan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('template-tpl_hiit_express')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('workout-plan-save')));
    await tester.pumpAndSettle();
    // The plan sheet dates the workout from the device clock, not `_now`.
    final today = DateTime.now();
    final planned = await repo.list(
      from: today.subtract(const Duration(days: 1)),
      to: today.add(const Duration(days: 1)),
    );
    expect(planned.single.name, 'HIIT Express');
    expect(planned.single.status, WorkoutStatus.planned);
  });

  testWidgets('Start, log sets with weight, finish, and see the summary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    var clock = _now;
    final log = SampleActivityLog();
    final repo = LocalWorkoutRepository(log: log, clock: () => clock);

    // An earlier session sets the bar: 60 kg bench.
    final earlier = await repo.plan(
      templateId: 'tpl_upper_strength',
      date: DateTime(2026, 9, 16),
    );
    final e = (await repo.start(earlier.id)).copy();
    e.exercises.first.workoutSets.first
      ..weight = 60
      ..completed = true;
    final earlierDone = (await repo.complete(e)).workout;

    final w = await repo.plan(templateId: 'tpl_upper_strength', date: _now);
    final data = MemberData()
      ..workouts = [w, earlierDone]
      ..workoutsLoaded = true;
    await tester.pumpWidget(
      _app(data, repo, MemberWorkoutPage(workoutId: w.id, now: () => clock)),
    );

    // Can't log before starting.
    final bench = w.exercises.first;
    final set1 = bench.workoutSets.first;
    expect(
      tester.widget<Checkbox>(find.byKey(Key('set-${set1.id}-done'))).onChanged,
      isNull,
    );

    await tester.tap(find.byKey(const Key('workout-start')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workout-start')), findsNothing);

    await tester.enterText(find.byKey(Key('set-${set1.id}-kg')), '62,5');
    await tester.enterText(find.byKey(Key('set-${set1.id}-reps')), '8');
    await tester.tap(find.byKey(Key('set-${set1.id}-done')));
    await tester.pump();
    // Mark the whole second exercise done in one tap.
    await tester.tap(find.byKey(Key('exercise-done-${w.exercises[1].id}')));
    await tester.pump();
    expect(find.textContaining('4/15 sets'), findsOneWidget);

    await tester.tap(find.byKey(Key('exercise-add-note-${bench.id}')));
    await tester.pump();
    await tester.enterText(
      find.byKey(Key('exercise-note-${bench.id}')),
      'Wider grip',
    );

    clock = _now.add(const Duration(minutes: 38));
    await tester.scrollUntilVisible(
      find.byKey(const Key('workout-finish')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('workout-finish')));
    await tester.pumpAndSettle();
    expect(find.text('Finish workout?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('workout-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('workout-complete')), findsOneWidget);
    expect(find.text('Workout complete'), findsOneWidget);
    expect(find.text('38 min'), findsOneWidget);
    expect(find.text('1/5'), findsOneWidget); // exercises fully done
    expect(find.text('4/15'), findsOneWidget); // sets done
    expect(find.text('New personal records'), findsOneWidget);
    expect(find.text('Bench Press · 62.5 kg'), findsOneWidget);
    expect(find.text('Previous best: 60 kg'), findsOneWidget);

    // Recorded as activity, with the log saved on the workout.
    expect(log.items.last.durationMinutes, 38);
    final stored = (await repo.list(from: _now, to: _now)).single;
    expect(stored.status, WorkoutStatus.completed);
    expect(stored.exercises.first.notes, 'Wider grip');
    expect(stored.exercises.first.workoutSets.first.reps, 8);
    expect(stored.exercises.first.workoutSets.first.weight, 62.5);
  });

  testWidgets('Finishing with nothing done is blocked', (tester) async {
    final repo = LocalWorkoutRepository(
      log: SampleActivityLog(),
      clock: () => _now,
    );
    final w = await repo.plan(templateId: 'tpl_core_mobility', date: _now);
    final data = MemberData()
      ..workouts = [(await repo.start(w.id))]
      ..workoutsLoaded = true;
    await tester.pumpWidget(
      _app(data, repo, MemberWorkoutPage(workoutId: w.id, now: () => _now)),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('workout-finish')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('workout-finish')));
    await tester.pump();
    expect(find.text('Complete at least one set to finish.'), findsOneWidget);
    expect(find.byKey(const Key('workout-complete')), findsNothing);
  });
}
