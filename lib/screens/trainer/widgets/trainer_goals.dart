import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_scope.dart';
import '../../../shared/activity/goal.dart';
import '../../../shared/activity/trainer_connection.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../member/widgets/activity_widgets.dart' show formatSteps;
import '../../member/widgets/goal_widgets.dart' show goalTitle, goalRange;

String _n(num v) =>
    v == v.roundToDouble() ? formatSteps(v.round()) : v.toStringAsFixed(1);

/// Trainer → client → "Goals you set": what this trainer asked of the
/// client, with progress when the client shares goals.
class TrainerGoalsSection extends StatelessWidget {
  const TrainerGoalsSection({
    super.key,
    required this.clientName,
    required this.relationshipId,
    required this.overview,
    required this.now,
    required this.onChanged,
  });

  final String clientName;
  final String relationshipId;
  final ClientOverview overview;
  final DateTime now;

  /// Called after a goal was set, retargeted or archived.
  final Future<void> Function() onChanged;

  Future<void> _set(BuildContext context) async {
    final api = AppScope.of(context).api;
    final ok = await showAssignGoalSheet(
      context,
      clientName: clientName,
      challenges: overview.goalChallenges,
      now: now,
      onSave: (body) => api.trainerAssignGoal(relationshipId, body),
    );
    if (ok == true && context.mounted) {
      FFSnack.success(
        context,
        context.tr('trainerGoal.saved').replaceAll('{name}', clientName),
      );
      await onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goals = overview.assignedGoals;
    final shares = overview.client.permissions.has(TrainerPermission.goals);
    return Column(
      key: const Key('trainer-goals'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: FFSectionTitle(context.tr('trainerGoal.section'))),
            FFButton(
              key: const Key('trainer-goal-add'),
              label: context.tr('trainerGoal.add'),
              onPressed: () => _set(context),
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              icon: Icons.flag_outlined,
            ),
          ],
        ),
        if (goals.isEmpty)
          FFEmptyState(
            title: context.tr('trainerGoal.none'),
            body: context
                .tr('trainerGoal.noneBody')
                .replaceAll('{name}', clientName),
          )
        else ...[
          if (!shares)
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, size: 16),
                  const SizedBox(width: FFTokens.spacingXs),
                  Expanded(
                    child: Text(
                      context
                          .tr('trainerGoal.progressHidden')
                          .replaceAll('{name}', clientName),
                      key: const Key('trainer-goal-progress-hidden'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          for (final a in goals)
            _AssignedGoalCard(
              assigned: a,
              relationshipId: relationshipId,
              onChanged: onChanged,
            ),
        ],
      ],
    );
  }
}

class _AssignedGoalCard extends StatelessWidget {
  const _AssignedGoalCard({
    required this.assigned,
    required this.relationshipId,
    required this.onChanged,
  });

  final AssignedGoal assigned;
  final String relationshipId;
  final Future<void> Function() onChanged;

  Future<void> _update(BuildContext context, Map<String, dynamic> body) async {
    final api = AppScope.of(context).api;
    final messenger = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    try {
      await api.trainerUpdateGoal(relationshipId, assigned.goal.id, body);
      await onChanged();
    } catch (e) {
      messenger.error(errorMessage(locale, e));
    }
  }

  Future<void> _retarget(BuildContext context) async {
    final ctl = TextEditingController(text: _n(assigned.goal.target));
    final target = await showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('trainerGoal.changeTarget')),
        content: FFTextField(
          key: const Key('trainer-goal-target-edit'),
          controller: ctl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('trainer.cancel')),
          ),
          FilledButton(
            key: const Key('trainer-goal-target-save'),
            onPressed: () => Navigator.pop(ctx, num.tryParse(ctl.text.trim())),
            child: Text(ctx.tr('goal.save')),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (target != null && context.mounted) {
      await _update(context, {'target': target});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = assigned.goal;
    final current = assigned.current;
    final fraction = current == null || g.target <= 0
        ? null
        : (current / g.target).toDouble();
    final kind = g.isCoaching
        ? 'trainerGoal.kind.coaching'
        : g.challengeId != null
        ? 'trainerGoal.kind.challenge'
        : null;
    return FFCard(
      key: Key('trainer-goal-${g.id}'),
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
                    if (kind != null)
                      Text(
                        context.tr(kind),
                        style: FFTokens.monoLabel(
                          theme.colorScheme.primary,
                          size: 10,
                        ),
                      ),
                    Text(
                      goalTitle(context, g),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (g.isCoaching)
                      Text(
                        '${context.tr('goal.type.custom').replaceAll('{n}', _n(g.target))} ${context.tr('goal.period.${g.period.wire}')}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (assigned.completed == true)
                FFPill(label: context.tr('challenge.completed'), filled: true),
              PopupMenuButton<String>(
                key: Key('trainer-goal-menu-${g.id}'),
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (v) => v == 'target'
                    ? _retarget(context)
                    : _update(context, {'status': 'archived'}),
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'target',
                    child: Text(ctx.tr('trainerGoal.changeTarget')),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(ctx.tr('trainerGoal.remove')),
                  ),
                ],
              ),
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            ClipRRect(
              borderRadius: BorderRadius.circular(FFTokens.radiusFull),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Text(
              '${context.tr('goal.progressOf').replaceAll('{current}', _n(current!)).replaceAll('{target}', _n(g.target))}'
              ' · ${(fraction * 100).round()}%',
              key: Key('trainer-goal-progress-${g.id}'),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (g.status == GoalStatus.paused)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                context.tr('trainerGoal.pausedByMember'),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Set a goal ─────────────────────────────────────────────────────────────

enum _Kind { workouts, steps, activeMinutes, distance, challenge, coaching }

/// How often the goal runs. `dates` is one stretch (default: the next 7
/// days, e.g. "23–29 Sep"); the others repeat.
enum _When { dates, week, day, month }

/// Opens the "Set a goal" sheet; true when a goal was saved.
Future<bool?> showAssignGoalSheet(
  BuildContext context, {
  required String clientName,
  required List<GoalChallenge>? challenges,
  required DateTime now,
  required Future<Map<String, dynamic>> Function(Map<String, dynamic> body)
  onSave,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  builder: (_) => AssignGoalSheet(
    clientName: clientName,
    challenges: challenges,
    now: now,
    onSave: onSave,
  ),
);

class AssignGoalSheet extends StatefulWidget {
  const AssignGoalSheet({
    super.key,
    required this.clientName,
    required this.challenges,
    required this.now,
    required this.onSave,
  });

  final String clientName;

  /// Null when the client doesn't share challenges.
  final List<GoalChallenge>? challenges;
  final DateTime now;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> body) onSave;

  @override
  State<AssignGoalSheet> createState() => _AssignGoalSheetState();
}

class _AssignGoalSheetState extends State<AssignGoalSheet> {
  _Kind _kind = _Kind.workouts;
  _When _when = _When.dates;
  late DateTimeRange _range;
  GoalChallenge? _challenge;
  final _target = TextEditingController(text: '4');
  final _title = TextEditingController();
  String? _error;
  bool _saving = false;

  static const _defaults = {
    _Kind.workouts: '4',
    _Kind.steps: '50000',
    _Kind.activeMinutes: '150',
    _Kind.distance: '20',
    _Kind.coaching: '3',
  };

  @override
  void initState() {
    super.initState();
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    _range = DateTimeRange(
      start: today,
      end: today.add(const Duration(days: 6)),
    );
  }

  @override
  void dispose() {
    _target.dispose();
    _title.dispose();
    super.dispose();
  }

  void _pickKind(_Kind k) => setState(() {
    _kind = k;
    _error = null;
    if (k == _Kind.challenge) {
      _challenge = widget.challenges?.firstOrNull;
      _target.text = _challenge == null ? '' : _n(_challenge!.target);
    } else {
      _target.text = _defaults[k] ?? '';
    }
  });

  Future<void> _pickRange() async {
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  String get _type => switch (_kind) {
    _Kind.workouts => 'workouts',
    _Kind.steps => 'steps',
    _Kind.activeMinutes => 'active_minutes',
    _Kind.distance => 'distance_km',
    _Kind.coaching => 'custom',
    _Kind.challenge => _challenge?.type.wire ?? '',
  };

  Map<String, dynamic>? _body() {
    final target = num.tryParse(_target.text.trim());
    if (target == null || target <= 0) {
      setState(() => _error = context.tr('trainerGoal.error.target'));
      return null;
    }
    if (_kind == _Kind.coaching) {
      if (_title.text.trim().isEmpty) {
        setState(() => _error = context.tr('trainerGoal.error.title'));
        return null;
      }
      if (target != target.roundToDouble()) {
        setState(() => _error = context.tr('trainerGoal.error.wholeTimes'));
        return null;
      }
    }
    if (_kind == _Kind.challenge) {
      if (_challenge == null) return null;
      return {'challengeId': _challenge!.id, 'target': target};
    }
    return {
      'type': _type,
      'target': target,
      if (_kind == _Kind.coaching) 'title': _title.text.trim(),
      ...switch (_when) {
        _When.dates => {
          'period': 'custom',
          'startDate': formatGoalDate(_range.start),
          'endDate': formatGoalDate(_range.end),
        },
        _When.week => {'period': 'week'},
        _When.day => {'period': 'day'},
        _When.month => {'period': 'month'},
      },
    };
  }

  Future<void> _save() async {
    final body = _body();
    if (body == null) return;
    final locale = FFLocaleScope.of(context);
    final nav = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(body);
      nav.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessage(locale, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canChallenge = widget.challenges?.isNotEmpty ?? false;
    final unit = switch (_kind) {
      _Kind.workouts => context.tr('activity.workoutCount').toLowerCase(),
      _Kind.steps => context.tr('activity.steps').toLowerCase(),
      _Kind.activeMinutes => context.tr('activity.min'),
      _Kind.distance => 'km',
      _Kind.coaching => context.tr('goal.times'),
      _Kind.challenge => switch (_challenge?.type) {
        GoalType.distanceKm => 'km',
        GoalType.activeMinutes => context.tr('activity.min'),
        GoalType.workouts => context.tr('activity.workoutCount').toLowerCase(),
        _ => context.tr('activity.steps').toLowerCase(),
      },
    };
    Widget label(String key) => Padding(
      padding: const EdgeInsets.only(
        top: FFTokens.spacingMd,
        bottom: FFTokens.spacingSm,
      ),
      child: Text(
        context.tr(key),
        style: FFTokens.monoLabel(theme.colorScheme.onSurfaceVariant),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          key: const Key('assign-goal-sheet'),
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context
                    .tr('trainerGoal.title')
                    .replaceAll('{name}', widget.clientName),
                style: theme.textTheme.titleLarge,
              ),
              label('trainerGoal.kind'),
              Wrap(
                spacing: FFTokens.spacingSm,
                runSpacing: FFTokens.spacingSm,
                children: [
                  for (final k in _Kind.values)
                    if (k != _Kind.challenge || canChallenge)
                      ChoiceChip(
                        key: Key('goal-kind-${k.name}'),
                        label: Text(
                          context.tr('trainerGoal.kindOpt.${k.name}'),
                        ),
                        selected: _kind == k,
                        onSelected: (_) => _pickKind(k),
                      ),
                ],
              ),
              if (!canChallenge)
                Padding(
                  padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                  child: Text(
                    context.tr(
                      widget.challenges == null
                          ? 'trainerGoal.challengeNotShared'
                          : 'trainerGoal.challengeNone',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (_kind == _Kind.coaching) ...[
                label('trainerGoal.coachingTitle'),
                FFTextField(
                  key: const Key('goal-title'),
                  controller: _title,
                  hint: context.tr('trainerGoal.coachingHint'),
                  maxLength: 120,
                ),
              ],
              if (_kind == _Kind.challenge && canChallenge) ...[
                label('trainerGoal.challenge'),
                Wrap(
                  spacing: FFTokens.spacingSm,
                  runSpacing: FFTokens.spacingSm,
                  children: [
                    for (final c in widget.challenges!)
                      ChoiceChip(
                        key: Key('goal-challenge-${c.id}'),
                        label: Text(c.name),
                        selected: _challenge?.id == c.id,
                        onSelected: (_) => setState(() {
                          _challenge = c;
                          _target.text = _n(c.target);
                        }),
                      ),
                  ],
                ),
                if (_challenge case final c?)
                  Padding(
                    padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                    child: Text(
                      context
                          .tr('trainerGoal.challengeDates')
                          .replaceAll(
                            '{range}',
                            goalRange(c.startDate, c.endDate),
                          ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
              label('trainerGoal.target'),
              FFTextField(
                key: const Key('goal-target'),
                controller: _target,
                suffixText: unit,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
              ),
              if (_kind != _Kind.challenge) ...[
                label('trainerGoal.when'),
                Wrap(
                  spacing: FFTokens.spacingSm,
                  runSpacing: FFTokens.spacingSm,
                  children: [
                    for (final w in _When.values)
                      ChoiceChip(
                        key: Key('goal-when-${w.name}'),
                        label: Text(
                          w == _When.dates
                              ? goalRange(_range.start, _range.end)
                              : context.tr('trainerGoal.whenOpt.${w.name}'),
                        ),
                        selected: _when == w,
                        onSelected: (_) => setState(() => _when = w),
                      ),
                  ],
                ),
                if (_when == _When.dates)
                  FFButton(
                    key: const Key('goal-dates'),
                    label: context.tr('trainerGoal.changeDates'),
                    onPressed: _pickRange,
                    variant: FFButtonVariant.ghost,
                    size: FFButtonSize.sm,
                    icon: Icons.date_range,
                  ),
              ],
              if (_error case final e?)
                Padding(
                  padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                  child: Text(
                    e,
                    key: const Key('assign-goal-error'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: FFTokens.spacingLg),
              Text(
                context
                    .tr('trainerGoal.memberSees')
                    .replaceAll('{name}', widget.clientName),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              SizedBox(
                width: double.infinity,
                child: FFButton(
                  key: const Key('assign-goal-save'),
                  label: context.tr('trainerGoal.save'),
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
