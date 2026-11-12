import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/activity/activity_summary.dart';
import '../../../shared/activity/workout.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';
import 'activity_widgets.dart';
import 'training_widgets.dart';

String workoutRoute(String id) =>
    AppRoutes.memberWorkout.replaceFirst(':workoutId', Uri.encodeComponent(id));

/// Translated muscle group, or the raw value for ones we don't know.
String muscleLabel(BuildContext context, String group) {
  final key = 'muscle.$group';
  final label = context.tr(key);
  if (label != key) return label;
  // Plan workouts name the training area (quadriceps, obliques…).
  final areaKey = 'training.area.$group';
  final area = context.tr(areaKey);
  return area == areaKey ? group.replaceAll('_', ' ') : area;
}

/// "3 × 10" for rep-based exercises, "3 × 30 s" for timed ones.
String exerciseTarget(BuildContext context, WorkoutExercise e) {
  if (e.isTimed) {
    return '${e.sets} × ${e.duration} ${context.tr('workout.secondsShort')}';
  }
  return '${e.sets} × ${e.reps ?? '-'}';
}

String workoutMeta(BuildContext context, Workout w) {
  final parts = [
    context
        .tr('workout.exerciseCount')
        .replaceAll('{n}', '${w.exercises.length}'),
    if (w.estimatedDuration != null)
      '${w.estimatedDuration} ${context.tr('activity.min')}',
  ];
  return parts.join(' · ');
}

/// "From Coach Amani" (or "From your trainer" if the name isn't loaded).
String trainerLabel(BuildContext context, MemberData data, Workout w) {
  final name = data.trainerName(w.trainerId);
  return name == null
      ? context.tr('plan.fromYourTrainer')
      : context.tr('plan.from').replaceAll('{name}', name);
}

/// Today's open workouts (planned or in progress), newest first.
List<Workout> todaysWorkouts(List<Workout> workouts, DateTime now) {
  final today = dayOf(now);
  return workouts
      .where((w) => w.status.isOpen && dayOf(w.scheduledDate) == today)
      .toList();
}

/// Today's workout: name, size, the first few exercises with their targets
/// and a Start / Continue button — or an invitation to plan one.
class TodayWorkoutCard extends StatelessWidget {
  const TodayWorkoutCard({super.key, required this.data, required this.now});

  final MemberData data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!data.workoutsLoaded) return const SizedBox.shrink();
    final today = todaysWorkouts(data.workouts, now);
    if (today.isEmpty) {
      // On a training plan, a day without a session is a recovery day.
      final plan = data.trainingPlan;
      if (plan != null) {
        final next = plan.nextOpen(now);
        return FFEmptyState(
          key: const Key('today-recovery'),
          title: context.tr('training.recoveryDay'),
          body: next == null
              ? context.tr('training.allDone')
              : context
                    .tr('training.nextWorkoutOn')
                    .replaceAll('{date}', trainingDate(context, next.date)),
          action: FilledButton.tonal(
            key: const Key('today-view-plan'),
            onPressed: () => context.go(AppRoutes.memberTrainingPlan),
            child: Text(context.tr('training.viewPlan')),
          ),
        );
      }
      return FFEmptyState(
        key: const Key('today-workout-empty'),
        title: context.tr('workout.noneToday'),
        body: context.tr('workout.noneTodayBody'),
        action: FilledButton.tonal(
          key: const Key('workout-plan'),
          onPressed: () => showPlanWorkoutSheet(context),
          child: Text(context.tr('workout.plan')),
        ),
      );
    }
    final w = today.first;
    final inProgress = w.status == WorkoutStatus.inProgress;
    const preview = 4;
    return FFCard(
      key: const Key('today-workout'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('workout.today'),
            style: FFTokens.monoLabel(theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            w.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(workoutMeta(context, w), style: theme.textTheme.bodySmall),
          if (w.fromTrainer)
            Text(
              trainerLabel(context, data, w),
              key: const Key('today-workout-trainer'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: FFTokens.spacingMd),
          for (final e in w.exercises.take(preview))
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.exerciseName,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    exerciseTarget(context, e),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (w.exercises.length > preview)
            Text(
              context
                  .tr('workout.more')
                  .replaceAll('{n}', '${w.exercises.length - preview}'),
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: FFTokens.spacingMd),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('today-workout-open'),
              onPressed: () => context.go(workoutRoute(w.id)),
              icon: Icon(inProgress ? Icons.play_circle : Icons.play_arrow),
              label: Text(
                context.tr(inProgress ? 'workout.continue' : 'workout.start'),
              ),
            ),
          ),
          if (today.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingSm),
              child: Text(
                context
                    .tr('workout.alsoToday')
                    .replaceAll('{n}', '${today.length - 1}'),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// One workout in a list: upcoming, or done.
class WorkoutTile extends StatelessWidget {
  const WorkoutTile({super.key, required this.workout});

  final Workout workout;

  @override
  Widget build(BuildContext context) {
    final w = workout;
    final date = DateFormat('EEE d MMM').format(w.scheduledDate);
    final status = switch (w.status) {
      WorkoutStatus.completed =>
        '${context.tr('workout.status.completed')} · '
            '${w.setsCompleted}/${w.setsTotal} ${context.tr('workout.sets')}',
      WorkoutStatus.skipped => context.tr('workout.status.skipped'),
      WorkoutStatus.inProgress => context.tr('workout.status.in_progress'),
      WorkoutStatus.planned => workoutMeta(context, w),
    };
    final from = w.fromTrainer
        ? ' · ${trainerLabel(context, MemberDataScope.of(context), w)}'
        : '';
    return FFActionTile(
      key: Key('workout-tile-${w.id}'),
      icon: w.status == WorkoutStatus.completed
          ? Icons.check_circle_outline
          : activityTypeIcon(w.activityType),
      title: w.name,
      subtitle: '$date · $status$from',
      onTap: () => context.go(workoutRoute(w.id)),
    );
  }
}

// ── Plan a workout ──────────────────────────────────────────────────────────

Future<void> showPlanWorkoutSheet(BuildContext context) async {
  final repo = AppScope.of(context).workouts;
  final shell = context.findAncestorStateOfType<MemberShellState>();
  final planned = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PlanWorkoutSheet(
      loadTemplates: repo.templates,
      onPlan: (templateId, date) =>
          repo.plan(templateId: templateId, date: date),
    ),
  );
  if (planned == true) await shell?.refreshAfterWorkout();
}

class _PlanWorkoutSheet extends StatefulWidget {
  const _PlanWorkoutSheet({required this.loadTemplates, required this.onPlan});

  final Future<List<WorkoutTemplate>> Function() loadTemplates;
  final Future<Object?> Function(String templateId, DateTime date) onPlan;

  @override
  State<_PlanWorkoutSheet> createState() => _PlanWorkoutSheetState();
}

class _PlanWorkoutSheetState extends State<_PlanWorkoutSheet> {
  late final Future<List<WorkoutTemplate>> _templates = widget.loadTemplates();
  String? _selected;
  bool _tomorrow = false;
  bool _saving = false;
  String? _error;

  Future<void> _plan() async {
    final id = _selected;
    if (id == null) return;
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, now.day + (_tomorrow ? 1 : 0));
    final navigator = Navigator.of(context);
    final failed = context.tr('workout.planFailed');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onPlan(id, date);
      navigator.pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        child: FutureBuilder<List<WorkoutTemplate>>(
          future: _templates,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 200,
                child: Center(child: FFSpinner(size: 32)),
              );
            }
            final templates = snap.data ?? const <WorkoutTemplate>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('workout.plan'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: FFTokens.spacingSm),
                if (snap.hasError || templates.isEmpty)
                  FFEmptyState(title: context.tr('workout.noTemplates'))
                else
                  Flexible(
                    child: RadioGroup<String>(
                      groupValue: _selected,
                      onChanged: (v) => setState(() => _selected = v),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final t in templates)
                            RadioListTile<String>(
                              key: Key('template-${t.id}'),
                              value: t.id,
                              contentPadding: EdgeInsets.zero,
                              title: Text(t.name),
                              subtitle: Text(
                                [
                                  context
                                      .tr('workout.exerciseCount')
                                      .replaceAll(
                                        '{n}',
                                        '${t.exercises.length}',
                                      ),
                                  if (t.estimatedDuration != null)
                                    '${t.estimatedDuration} ${context.tr('activity.min')}',
                                  if (t.description != null) t.description!,
                                ].join(' · '),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: FFTokens.spacingSm),
                SizedBox(
                  width: double.infinity,
                  child: FFSegmented(
                    key: const Key('workout-plan-day'),
                    value: _tomorrow ? 'tomorrow' : 'today',
                    options: [
                      ('today', context.tr('workout.dayToday')),
                      ('tomorrow', context.tr('workout.dayTomorrow')),
                    ],
                    onChanged: (v) =>
                        setState(() => _tomorrow = v == 'tomorrow'),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: FFTokens.spacingMd),
                SizedBox(
                  width: double.infinity,
                  child: FFButton(
                    key: const Key('workout-plan-save'),
                    label: context.tr('workout.planSave'),
                    onPressed: _selected == null || _saving ? null : _plan,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// My Trainer Plan: for each trainer who assigns workouts, what's coming
/// up and what's been done.
class TrainerPlanBlock extends StatelessWidget {
  const TrainerPlanBlock({super.key, required this.data, required this.now});

  final MemberData data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = dayOf(now);
    final byTrainer = <String, List<Workout>>{};
    for (final w in data.workouts.where((w) => w.fromTrainer)) {
      byTrainer.putIfAbsent(w.trainerId!, () => []).add(w);
    }
    final connected = data.trainerConnections
        .where((c) => c.status.isOpen)
        .map((c) => c.trainerId);
    for (final id in connected) {
      byTrainer.putIfAbsent(id, () => []);
    }
    if (byTrainer.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('trainer-plan'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FFSectionTitle(context.tr('plan.title')),
        for (final e in byTrainer.entries)
          () {
            final name =
                data.trainerName(e.key) ?? context.tr('connect.yourTrainer');
            final upcoming =
                e.value
                    .where(
                      (w) =>
                          w.status.isOpen && !w.scheduledDate.isBefore(today),
                    )
                    .toList()
                  ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
            final done = e.value
                .where((w) => w.status == WorkoutStatus.completed)
                .length;
            final pending =
                data.connectionWith(e.key)?.status.wire == 'pending';
            return FFCard(
              key: Key('trainer-plan-${e.key}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    pending
                        ? context.tr('plan.waiting')
                        : context
                              .tr('plan.summary')
                              .replaceAll('{upcoming}', '${upcoming.length}')
                              .replaceAll('{done}', '$done'),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (upcoming.isEmpty && !pending)
                    Padding(
                      padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                      child: Text(
                        context.tr('plan.nothingYet'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  for (final w in upcoming.take(3))
                    Padding(
                      padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                      child: InkWell(
                        onTap: () => context.go(workoutRoute(w.id)),
                        child: Row(
                          children: [
                            Icon(
                              w.status == WorkoutStatus.inProgress
                                  ? Icons.play_circle_outline
                                  : Icons.event_outlined,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: FFTokens.spacingSm),
                            Expanded(
                              child: Text(
                                w.name,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            Text(
                              dayOf(w.scheduledDate) == today
                                  ? context.tr('workout.dayToday')
                                  : DateFormat(
                                      'EEE d MMM',
                                    ).format(w.scheduledDate),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          }(),
      ],
    );
  }
}
