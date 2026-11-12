import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_scope.dart';
import '../../../shared/activity/goal.dart';
import '../../../shared/activity/progress_engine.dart';
import '../../../shared/activity/streaks.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';
import 'activity_widgets.dart';

String _amount(GoalType type, num value) => switch (type) {
  GoalType.steps => formatSteps(value.round()),
  GoalType.distanceKm => value.toStringAsFixed(value >= 10 ? 0 : 1),
  _ => '${value.round()}',
};

/// e.g. "8,000 steps a day", "3 workouts a week", "100 km by 31 Oct",
/// "4 workouts, 21–27 Sep". Coaching and challenge goals use their title.
String goalTitle(BuildContext context, Goal g) {
  final title = g.title?.trim();
  if (title != null &&
      title.isNotEmpty &&
      (g.isCoaching || g.challengeId != null)) {
    return title;
  }
  final what = context
      .tr('goal.type.${g.type.wire}')
      .replaceAll('{n}', _amount(g.type, g.target));
  if (g.period == GoalPeriod.custom) {
    final end = g.endDate ?? g.startDate;
    // A short dated goal (a trainer's "this week") reads as its range.
    if (end.difference(g.startDate).inDays <= 13) {
      return context
          .tr('goal.range')
          .replaceAll('{what}', what)
          .replaceAll('{range}', goalRange(g.startDate, end));
    }
    return '$what ${context.tr('goal.period.custom').replaceAll('{date}', DateFormat('d MMM').format(end))}';
  }
  return '$what ${context.tr('goal.period.${g.period.wire}')}';
}

/// "21–27 Sep", or "28 Sep – 4 Oct" across months.
String goalRange(DateTime start, DateTime end) =>
    start.month == end.month && start.year == end.year
    ? '${start.day}–${DateFormat('d MMM').format(end)}'
    : '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM').format(end)}';

/// Current goals with progress, plus "Add goal".
class GoalsBlock extends StatelessWidget {
  const GoalsBlock({super.key, required this.data, required this.now});

  final MemberData data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final goals = data.goals.where((g) => g.status != GoalStatus.archived);
    return Column(
      key: const Key('progress-goals'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: FFSectionTitle(context.tr('progress.currentGoals')),
            ),
            FFButton(
              key: const Key('goal-add'),
              label: context.tr('progress.addGoal'),
              onPressed: () => showAddGoalSheet(context),
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              icon: Icons.add,
            ),
          ],
        ),
        if (!data.goalsLoaded)
          const Center(child: FFSpinner(size: 32))
        else if (goals.isEmpty)
          FFEmptyState(
            title: context.tr('progress.noGoals'),
            body: context.tr('progress.noGoalsBody'),
          )
        else ...[
          if (goals.any((g) => g.isFromTrainer)) ...[
            _GoalGroupLabel(context.tr('goal.group.trainer')),
            for (final g in goals.where((g) => g.isFromTrainer))
              GoalCard(progress: evaluateGoal(g, data.activities, now)),
            if (goals.any((g) => !g.isFromTrainer))
              _GoalGroupLabel(context.tr('goal.group.yours')),
          ],
          for (final g in goals.where((g) => !g.isFromTrainer))
            GoalCard(progress: evaluateGoal(g, data.activities, now)),
        ],
      ],
    );
  }
}

/// Marks a coaching goal done (or undoes it) and updates the member's goals
/// with the saved result, so the card moves at once.
Future<void> _mark(BuildContext context, Goal g, {bool undo = false}) async {
  final repo = AppScope.of(context).goals;
  final data = MemberDataScope.of(context);
  final messenger = FFSnack.of(context);
  final failed = context.tr('goal.saveFailed');
  try {
    final saved = await repo.checkIn(g.id, undo: undo);
    data.update(
      (d) => d.goals = [for (final x in d.goals) x.id == saved.id ? saved : x],
    );
  } catch (_) {
    messenger.error(failed);
  }
}

class _GoalGroupLabel extends StatelessWidget {
  const _GoalGroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: FFTokens.spacingXs,
      bottom: FFTokens.spacingSm,
    ),
    child: Text(
      text,
      style: FFTokens.monoLabel(Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress;
    final g = p.goal;
    final paused = g.status == GoalStatus.paused;
    final String? status = paused
        ? context.tr('goal.paused')
        : p.upcoming
        ? context
              .tr('goal.upcoming')
              .replaceAll('{date}', DateFormat('d MMM').format(g.startDate))
        : p.completed
        ? context.tr('goal.done.${g.period.wire}')
        : p.ended
        ? context.tr('goal.ended')
        : null;
    // Trainer goals say who set them, so they don't read as a target that
    // appeared from nowhere.
    final origin = g.isFromTrainer
        ? (g.createdByName == null
              ? context.tr('goal.fromTrainer')
              : context
                    .tr('goal.assignedBy')
                    .replaceAll('{name}', g.createdByName!))
        : g.source == GoalSource.challenge
        ? context.tr('goal.fromChallenge')
        : null;
    final canMark =
        g.isCoaching &&
        g.status == GoalStatus.active &&
        !p.completed &&
        !p.upcoming &&
        !p.ended;

    return FFCard(
      key: Key('goal-${g.id}'),
      child: Opacity(
        opacity: paused ? 0.6 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (g.isFromTrainer)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: FFTokens.spacing2xs,
                          ),
                          child: Text(
                            context
                                .tr(
                                  g.isCoaching
                                      ? 'goal.label.coaching'
                                      : 'goal.label.trainer',
                                ),
                            key: Key('goal-trainer-label-${g.id}'),
                            style: FFTokens.monoLabel(
                              theme.colorScheme.primary,
                              size: 10,
                            ),
                          ),
                        ),
                      Text(
                        goalTitle(context, g),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (origin != null)
                        Text(
                          origin,
                          key: Key('goal-origin-${g.id}'),
                          style: theme.textTheme.bodySmall,
                        ),
                      const SizedBox(height: FFTokens.spacingSm),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          FFTokens.radiusFull,
                        ),
                        child: LinearProgressIndicator(
                          value: p.fraction.clamp(0.0, 1.0),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: FFTokens.spacingXs),
                      Text(
                        '${context.tr('goal.progressOf').replaceAll('{current}', _amount(g.type, p.current)).replaceAll('{target}', _amount(g.type, g.target))}'
                        ' · ${(p.fraction * 100).round()}%',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (status != null)
                  Padding(
                    padding: const EdgeInsets.only(left: FFTokens.spacingSm),
                    child: FFPill(
                      label: status,
                      filled: p.completed && !paused,
                    ),
                  ),
                _GoalMenu(goal: g),
              ],
            ),
            if (g.isCoaching && g.status == GoalStatus.active)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                child: Row(
                  children: [
                    FilledButton.tonalIcon(
                      key: Key('goal-mark-${g.id}'),
                      onPressed: canMark ? () => _mark(context, g) : null,
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(context.tr('goal.markDone')),
                    ),
                    if (p.current > 0) ...[
                      const SizedBox(width: FFTokens.spacingSm),
                      FFButton(
                        key: Key('goal-undo-${g.id}'),
                        label: context.tr('goal.undoDone'),
                        onPressed: () => _mark(context, g, undo: true),
                        variant: FFButtonVariant.ghost,
                        size: FFButtonSize.sm,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GoalMenu extends StatelessWidget {
  const _GoalMenu({required this.goal});

  final Goal goal;

  Future<void> _set(BuildContext context, GoalStatus status) async {
    final repo = AppScope.of(context).goals;
    final shell = context.findAncestorStateOfType<MemberShellState>();
    final messenger = FFSnack.of(context);
    final failed = context.tr('goal.saveFailed');
    try {
      await repo.update(goal.id, status: status);
      await shell?.refreshGoals();
    } catch (_) {
      messenger.error(failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paused = goal.status == GoalStatus.paused;
    return PopupMenuButton<GoalStatus>(
      key: Key('goal-menu-${goal.id}'),
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (s) => _set(context, s),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: paused ? GoalStatus.active : GoalStatus.paused,
          child: Text(context.tr(paused ? 'goal.resume' : 'goal.pause')),
        ),
        PopupMenuItem(
          value: GoalStatus.archived,
          child: Text(context.tr('goal.archive')),
        ),
      ],
    );
  }
}

// ── Streak card ─────────────────────────────────────────────────────────────

/// One streak: its count and rule, or — right after a miss — a neutral
/// note that it ended and an invitation to start again.
class StreakCard extends StatelessWidget {
  const StreakCard({super.key, required this.streak});

  final StreakStatus streak;

  @override
  Widget build(BuildContext context) {
    final s = streak;
    final day = s.unit == StreakUnit.day;
    final name = s.kind.name;
    final String value;
    if (s.current > 0) {
      value = context
          .tr('streak.$name.current')
          .replaceAll('{n}', '${s.current}');
    } else if (s.justEnded) {
      value = context
          .tr(day ? 'streak.endedDay' : 'streak.endedWeek')
          .replaceAll('{n}', '${s.endedLength}');
    } else {
      value = context.tr(day ? 'streak.startDay' : 'streak.startWeek');
    }
    final best = s.best > 0
        ? ' · ${context.tr('streak.best').replaceAll('{n}', '${s.best}')}'
        : '';
    return FFCard(
      key: Key('streak-${s.kind.name}'),
      child: Row(
        children: [
          Icon(
            Icons.local_fire_department,
            color: s.current > 0
                ? FFTokens.warning500
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: FFTokens.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${context.tr('streak.rule.$name')}$best',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Add goal ────────────────────────────────────────────────────────────────

Future<void> showAddGoalSheet(BuildContext context) async {
  final repo = AppScope.of(context).goals;
  final shell = context.findAncestorStateOfType<MemberShellState>();
  final created = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AddGoalSheet(
      onSave: (type, period, target) =>
          repo.create(type: type, period: period, target: target),
    ),
  );
  if (created == true) await shell?.refreshGoals();
}

const _defaultTargets = {
  GoalType.steps: {
    GoalPeriod.day: 8000,
    GoalPeriod.week: 50000,
    GoalPeriod.month: 200000,
  },
  GoalType.workouts: {
    GoalPeriod.day: 1,
    GoalPeriod.week: 3,
    GoalPeriod.month: 12,
  },
  GoalType.activeMinutes: {
    GoalPeriod.day: 30,
    GoalPeriod.week: 150,
    GoalPeriod.month: 600,
  },
  GoalType.distanceKm: {
    GoalPeriod.day: 5,
    GoalPeriod.week: 20,
    GoalPeriod.month: 80,
  },
};

class _AddGoalSheet extends StatefulWidget {
  const _AddGoalSheet({required this.onSave});

  final Future<Object?> Function(GoalType, GoalPeriod, num) onSave;

  @override
  State<_AddGoalSheet> createState() => _AddGoalSheetState();
}

class _AddGoalSheetState extends State<_AddGoalSheet> {
  GoalType _type = GoalType.workouts;
  GoalPeriod _period = GoalPeriod.week;
  late final TextEditingController _target = TextEditingController(
    text: '${_defaultTargets[_type]![_period]}',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  void _resetTarget() => _target.text = '${_defaultTargets[_type]![_period]}';

  Future<void> _save() async {
    final target = num.tryParse(_target.text.trim());
    if (target == null || target <= 0) {
      setState(() => _error = context.tr('goal.invalidTarget'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final failed = context.tr('goal.saveFailed');
    try {
      await widget.onSave(_type, _period, target);
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
    final measures = {
      GoalType.steps: context.tr('activity.steps'),
      GoalType.workouts: context.tr('activity.workoutCount'),
      GoalType.activeMinutes: context.tr('activity.activeMinutes'),
      GoalType.distanceKm: context.tr('activity.distance'),
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(
        FFTokens.spacingLg,
        FFTokens.spacingLg,
        FFTokens.spacingLg,
        FFTokens.spacingLg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('goal.sheetTitle'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          Text(
            context.tr('goal.measure'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Wrap(
            spacing: FFTokens.spacingSm,
            children: [
              for (final e in measures.entries)
                ChoiceChip(
                  key: Key('goal-type-${e.key.wire}'),
                  label: Text(e.value),
                  selected: _type == e.key,
                  onSelected: (_) => setState(() {
                    _type = e.key;
                    _resetTarget();
                  }),
                ),
            ],
          ),
          const SizedBox(height: FFTokens.spacingMd),
          Text(
            context.tr('goal.periodLabel'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: FFTokens.spacingXs),
          SizedBox(
            width: double.infinity,
            child: FFSegmented(
              key: const Key('goal-period'),
              value: _period.wire,
              options: [
                for (final p in [
                  GoalPeriod.day,
                  GoalPeriod.week,
                  GoalPeriod.month,
                ])
                  (p.wire, context.tr('goal.periodOpt.${p.wire}')),
              ],
              onChanged: (v) => setState(() {
                _period = GoalPeriod.fromWire(v)!;
                _resetTarget();
              }),
            ),
          ),
          const SizedBox(height: FFTokens.spacingMd),
          FFTextField(
            key: const Key('goal-target'),
            controller: _target,
            label: context.tr('goal.target'),
            errorText: _error,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
          ),
          const SizedBox(height: FFTokens.spacingMd),
          SizedBox(
            width: double.infinity,
            child: FFButton(
              key: const Key('goal-save'),
              label: context.tr('goal.save'),
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}
