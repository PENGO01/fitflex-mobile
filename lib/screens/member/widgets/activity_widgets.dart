import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/activity/activity.dart';
import '../../../shared/activity/run_metrics.dart' show formatPace;
import 'share_picker.dart' show showActivityActions;
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../router.dart';
import '../../../shared/i18n.dart';
import '../../../shared/activity/manual_activity_log.dart';
import '../member_log_activity_page.dart' show openLogActivity;
import 'workout_widgets.dart' show showPlanWorkoutSheet;

IconData activityTypeIcon(ActivityType type) => switch (type) {
  ActivityType.walking => Icons.directions_walk,
  ActivityType.running || ActivityType.jogging => Icons.directions_run,
  ActivityType.cycling => Icons.directions_bike,
  ActivityType.hiking => Icons.hiking,
  ActivityType.swimming => Icons.pool,
  ActivityType.sports => Icons.sports_soccer,
  ActivityType.strength => Icons.fitness_center,
  ActivityType.hiit => Icons.bolt,
  ActivityType.functional => Icons.sports_gymnastics,
  ActivityType.groupClass => Icons.groups_outlined,
  ActivityType.personalTraining => Icons.person_outline,
  ActivityType.mobility || ActivityType.stretching => Icons.self_improvement,
  ActivityType.other => Icons.timeline,
};

String activityTypeLabel(BuildContext context, ActivityType type) =>
    context.tr('activity.type.${type.wire}');

String formatSteps(int steps) => formatMoney(steps);

String formatKm(double km) => '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km';

/// Flags generated numbers so members never mistake them for real tracking.
class ActivitySampleBadge extends StatelessWidget {
  const ActivitySampleBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.tr('activity.sampleHint'),
      child: FFPill(
        key: const Key('activity-sample-badge'),
        label: context.tr('activity.sample'),
      ),
    );
  }
}

/// One row in the activity timeline.
class ActivityTimelineTile extends StatelessWidget {
  const ActivityTimelineTile({
    super.key,
    required this.activity,
    this.compact = false,
  });

  final Activity activity;

  /// A plain row with no card or origin label, for inside another card
  /// (a gym visit).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final parts = <String>[
      context.localDayTime(a.startedAt),
      if (a.durationMinutes != null)
        '${a.durationMinutes} ${context.tr('activity.min')}',
      if (a.distanceKm != null && a.distanceKm! > 0) formatKm(a.distanceKm!),
      if (a.steps != null && a.type == ActivityType.walking)
        '${formatSteps(a.steps!)} ${context.tr('activity.steps').toLowerCase()}',
      if (a.isRecordedRun && (a.distanceKm ?? 0) > 0)
        '${formatPace((a.movingSeconds! / a.distanceKm!).round())} /km',
    ];
    final workoutId = a.workoutId;
    final opensRun = a.isRecordedRun;
    // A finished workout is recorded under its own name; a logged
    // session under the name the member gave it.
    final title = workoutId != null && (a.notes ?? '').isNotEmpty
        ? a.notes!
        : manualActivityName(a) ?? activityTypeLabel(context, a.type);
    final VoidCallback onTap = opensRun
        ? () => context.go(
            AppRoutes.memberRunDetail.replaceFirst(
              ':activityId',
              Uri.encodeComponent(a.id),
            ),
          )
        : workoutId == null
        ? (a.isDailyStepTotal || a.isSample || a.origin != DataOrigin.manual
              ? () {}
              : () => showActivityActions(context, a))
        : () => context.go(
            AppRoutes.memberWorkout.replaceFirst(
              ':workoutId',
              Uri.encodeComponent(workoutId),
            ),
          );
    if (compact) {
      final theme = Theme.of(context);
      return InkWell(
        key: Key('activity-${a.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(FFTokens.radiusSm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
            child: Row(
              children: [
                Icon(
                  activityTypeIcon(a.type),
                  size: FFTokens.iconSm,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: FFTokens.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.bodyMedium),
                      Text(parts.join(' · '), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return FFActionTile(
      key: Key('activity-${a.id}'),
      // At most a third of the screen, so a long origin ("Imeingizwa na
      // mtu" at large text) wraps instead of squeezing the title.
      trailing: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width / 3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: ActivityOriginLabel(activity: a)),
            if (workoutId != null || opensRun)
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: FFTokens.iconMd,
              ),
          ],
        ),
      ),
      icon: activityTypeIcon(a.type),
      title: title,
      subtitle: parts.join(' · '),
      onTap: onTap,
    );
  }
}

/// "Device · Apple Health", "FitFlex", "Manual", "By trainer", "Sample":
/// where one activity record came from.
class ActivityOriginLabel extends StatelessWidget {
  const ActivityOriginLabel({super.key, required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = activity;
    final (IconData icon, String label, String? detail) = a.isSample
        ? (Icons.science_outlined, context.tr('origin.sample'), null)
        : switch (a.origin) {
            DataOrigin.device => (
              Icons.watch_outlined,
              context.tr('origin.device'),
              // Phone steps are saved with this English name; show it in
              // the app language.
              a.deviceName == null || a.deviceName == phoneStepsDeviceName
                  ? context.tr('origin.platform.${a.devicePlatform!.wire}')
                  : a.deviceName,
            ),
            DataOrigin.fitflex => (
              Icons.bolt_outlined,
              context.tr('origin.fitflex'),
              null,
            ),
            DataOrigin.manual => (
              Icons.edit_outlined,
              context.tr(switch (a.source) {
                ActivitySource.trainer => 'origin.byTrainer',
                ActivitySource.gym => 'origin.byGym',
                _ => 'origin.manual',
              }),
              null,
            ),
          };
    final muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: [label, ?detail].join(', '),
      excludeSemantics: true,
      child: Column(
        key: Key('activity-origin-${a.id}'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: FFTokens.iconSm, color: muted),
              const SizedBox(width: FFTokens.spacing2xs),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ),
            ],
          ),
          if (detail != null)
            Text(
              detail,
              textAlign: TextAlign.end,
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
        ],
      ),
    );
  }
}

/// Explains device, FitFlex and manual data, and that device data only
/// ever comes from a connected device.
Future<void> showDataOriginsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        Widget row(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: FFTokens.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    Text(body, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        );
        return SafeArea(
          child: Padding(
            key: const Key('data-origins-sheet'),
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('origin.title'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                row(
                  Icons.watch_outlined,
                  context.tr('origin.device'),
                  context.tr('origin.deviceBody'),
                ),
                row(
                  Icons.bolt_outlined,
                  context.tr('origin.fitflex'),
                  context.tr('origin.fitflexBody'),
                ),
                row(
                  Icons.edit_outlined,
                  context.tr('origin.manual'),
                  context.tr('origin.manualBody'),
                ),
                Text(
                  context.tr('origin.noDevicesYet'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );

/// Shown instead of a grid of zeros to a member with no activity yet.
class ActivityGetStartedCard extends StatelessWidget {
  const ActivityGetStartedCard({super.key, this.showAction = true});

  /// Off where a "Plan a workout" button is already on screen.
  final bool showAction;

  @override
  Widget build(BuildContext context) {
    return FFEmptyState(
      key: const Key('activity-get-started'),
      title: context.tr('activity.getStarted.title'),
      body: context.tr('activity.getStarted.body'),
      action: showAction
          ? Wrap(
              alignment: WrapAlignment.center,
              spacing: FFTokens.spacingSm,
              runSpacing: FFTokens.spacingSm,
              children: [
                FilledButton.tonal(
                  key: const Key('activity-get-started-log'),
                  onPressed: () => openLogActivity(context),
                  child: Text(context.tr('logActivity.open')),
                ),
                FFButton(
                  key: const Key('activity-get-started-plan'),
                  label: context.tr('workout.plan'),
                  onPressed: () => showPlanWorkoutSheet(context),
                  variant: FFButtonVariant.secondary,
                ),
              ],
            )
          : null,
    );
  }
}

/// Labelled progress bar toward the daily step goal.
class ActivityGoalBar extends StatelessWidget {
  const ActivityGoalBar({
    super.key,
    required this.steps,
    required this.goal,
    this.dense = false,
  });

  final int steps;
  final int goal;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = goal <= 0 ? 0.0 : steps / goal;
    final percent = (progress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(FFTokens.radiusFull),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: dense ? 6 : 8,
          ),
        ),
        const SizedBox(height: FFTokens.spacingXs),
        Text(
          context.tr('activity.ofGoal').replaceAll('{percent}', '$percent'),
          key: const Key('activity-goal-percent'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
