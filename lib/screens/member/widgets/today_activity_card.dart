import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router.dart';
import '../../../shared/activity/activity_summary.dart';
import '../../../shared/activity/progress_engine.dart';
import '../../../shared/activity/streaks.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';
import 'activity_widgets.dart';
import 'workout_widgets.dart';

/// Compact "Today's activity" summary for the member Home tab.
class TodayActivityCard extends StatelessWidget {
  const TodayActivityCard({
    super.key,
    required this.data,
    this.now,
    this.showWorkout = true,
    this.showStreak = true,
  });

  final MemberData data;

  /// Home hides these when they have a card of their own.
  final bool showWorkout;
  final bool showStreak;

  /// Injectable clock for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    if (!data.activityLoaded) return const SizedBox.shrink();
    // Nothing recorded yet: a way in beats a card of zeros.
    if (data.activities.isEmpty && !data.activityIsSample) {
      return const Padding(
        padding: EdgeInsets.only(top: FFTokens.spacingMd),
        child: ActivityGetStartedCard(),
      );
    }
    final theme = Theme.of(context);
    final today = now ?? DateTime.now();
    final summary = summarizeDay(data.activities, today);
    final streak = computeStreak(
      StreakKind.activity,
      today: today,
      activities: data.activities,
    )!.current;
    final stepGoal = dailyStepGoal(data.goals);
    final workout = showWorkout
        ? todaysWorkouts(data.workouts, today).firstOrNull
        : null;

    return FFCard(
      key: const Key('today-activity-card'),
      margin: const EdgeInsets.only(top: FFTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('activity.today'),
                  style: FFTokens.monoLabel(theme.colorScheme.onSurfaceVariant),
                ),
              ),
              if (data.activityIsSample) const ActivitySampleBadge(),
            ],
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: formatSteps(summary.steps),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                TextSpan(
                  text: ' ${context.tr('activity.steps').toLowerCase()}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            key: const Key('today-activity-steps'),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MiniStat(
                value: '${summary.activeMinutes}',
                label: context.tr('activity.activeMinutes'),
              ),
              _MiniStat(
                value: '${summary.workoutCount}',
                label: context.tr('activity.workoutCount'),
              ),
              if (showStreak)
                _MiniStat(
                  icon: Icons.local_fire_department,
                  value: '$streak',
                  label: context.tr('activity.streak'),
                ),
            ],
          ),
          if (stepGoal != null) ...[
            const SizedBox(height: FFTokens.spacingMd),
            ActivityGoalBar(
              steps: summary.steps,
              goal: stepGoal.target.round(),
              dense: true,
            ),
          ],
          if (workout != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            InkWell(
              key: const Key('home-today-workout'),
              onTap: () => context.go(workoutRoute(workout.id)),
              borderRadius: BorderRadius.circular(FFTokens.radiusMd),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: FFTokens.spacingXs,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.fitness_center,
                      size: FFTokens.iconSm,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: FFTokens.spacingSm),
                    Expanded(
                      child: Text(
                        '${context.tr('workout.today')}: ${workout.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: FFButton(
              key: const Key('today-activity-view'),
              label: context.tr('activity.view'),
              onPressed: () => context.go(AppRoutes.memberActivity),
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label, this.icon});

  final String value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: FFTokens.iconSm, color: FFTokens.warning500),
                const SizedBox(width: FFTokens.spacing2xs),
              ],
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          // Two lines so longer Swahili labels aren't cut off.
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
