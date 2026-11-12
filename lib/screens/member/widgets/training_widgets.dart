import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../router.dart';
import '../../../shared/activity/activity_summary.dart';
import '../../../shared/activity/training_plan.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';

/// "4-week plan".
String trainingPlanTitle(BuildContext context, TrainingPlan plan) =>
    context.tr('training.planWeeks').replaceAll('{n}', '${plan.durationWeeks}');

/// Who the plan is from: "From Coach Amani" for a trainer's plan, else the
/// goal FitFlex built it for.
String trainingPlanByline(BuildContext context, TrainingPlan plan) =>
    plan.fromTrainer
    ? context
          .tr('training.fromTrainer')
          .replaceAll(
            '{name}',
            plan.trainerName ?? context.tr('training.yourTrainer'),
          )
    : trainingGoalLabel(context, plan.goal);

/// The member's goal in words (the same labels as onboarding).
String trainingGoalLabel(BuildContext context, String goal) =>
    context.tr('onboarding.goal_$goal');

String trainingAreaLabel(BuildContext context, String area) =>
    context.tr('training.area.$area');

/// A session's name: what the plan called it, or the areas it trains.
String trainingDayName(BuildContext context, TrainingPlanDay day) {
  final name = day.name;
  if (name != null && name.isNotEmpty) return name;
  if (day.focusAreas.isEmpty) return context.tr('training.session');
  return day.focusAreas
      .take(2)
      .map((a) => trainingAreaLabel(context, a))
      .join(' + ');
}

/// "Mon 12 Oct".
String trainingDate(BuildContext context, DateTime date) => DateFormat(
  'EEE d MMM',
  Localizations.localeOf(context).languageCode,
).format(date);

/// "Week 2 of 4 · 5 of 12 sessions done".
String trainingProgressLine(BuildContext context, TrainingPlan plan) => [
  context
      .tr('training.weekOf')
      .replaceAll('{n}', '${plan.currentWeek}')
      .replaceAll('{total}', '${plan.durationWeeks}'),
  context
      .tr('training.sessionsDone')
      .replaceAll('{n}', '${plan.completed}')
      .replaceAll('{total}', '${plan.sessions}'),
].join(' · ');

/// The Training tab's plan card: the plan the member is on and what comes
/// next — or an invitation to have one made.
class TrainingPlanCard extends StatelessWidget {
  const TrainingPlanCard({super.key, required this.data, required this.now});

  final MemberData data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!data.trainingLoaded) return const SizedBox.shrink();
    final plan = data.trainingPlan;
    if (plan == null) {
      return FFCard(
        key: const Key('training-none'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('training.noneTitle'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Text(
              context.tr('training.noneBody'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: FFTokens.spacingMd),
            SizedBox(
              width: double.infinity,
              child: FFButton(
                key: const Key('training-create'),
                label: context.tr('training.create'),
                onPressed: () => context.go(AppRoutes.memberTrainingSetup),
              ),
            ),
          ],
        ),
      );
    }
    final next = plan.nextOpen(now);
    final today = dayOf(now);
    final String nextLine;
    if (next == null) {
      nextLine = context.tr('training.allDone');
    } else if (next.date == today) {
      nextLine = context
          .tr('training.todayIs')
          .replaceAll('{name}', trainingDayName(context, next));
    } else {
      nextLine = context
          .tr('training.nextIs')
          .replaceAll('{date}', trainingDate(context, next.date))
          .replaceAll('{name}', trainingDayName(context, next));
    }
    return FFCard(
      key: const Key('training-plan-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('training.myPlan'),
            style: FFTokens.monoLabel(theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            trainingPlanTitle(context, plan),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            trainingPlanByline(context, plan),
            key: const Key('training-byline'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          ClipRRect(
            borderRadius: BorderRadius.circular(FFTokens.radiusFull),
            child: LinearProgressIndicator(
              value: plan.completion.clamp(0.0, 1.0),
              minHeight: 8,
              semanticsLabel: context.tr('training.myPlan'),
            ),
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            trainingProgressLine(context, plan),
            key: const Key('training-progress'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            nextLine,
            key: const Key('training-next'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          SizedBox(
            width: double.infinity,
            child: FFButton(
              key: const Key('training-view-plan'),
              label: context.tr('training.viewPlan'),
              onPressed: () => context.go(AppRoutes.memberTrainingPlan),
              variant: FFButtonVariant.secondary,
            ),
          ),
        ],
      ),
    );
  }
}
