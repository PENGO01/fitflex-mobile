import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/activity/activity_summary.dart';
import '../../../shared/activity/streaks.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';
import '../member_shell.dart';
import 'home_hero.dart' show HomeHeroState, homeHeroStateFor;

/// The home screen's fixed arrangement (FitFlex DS v1.0 "Home" board):
/// greeting, the pass, this week, streak and visits, the nearest gym.
/// The ranked cards from [pickHomeCards] follow below.

/// "Good evening, Muta" over a state-aware headline ("Ready to train?").
class HomeGreeting extends StatelessWidget {
  const HomeGreeting({
    super.key,
    required this.data,
    required this.name,
    required this.now,
  });

  final MemberData data;
  final String? name;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final greeting = context.tr(
      now.hour < 12
          ? 'member.goodMorning'
          : now.hour < 17
          ? 'member.goodAfternoon'
          : 'member.goodEvening',
    );
    final state = switch (homeHeroStateFor(data)) {
      HomeHeroState.pending => 'pending',
      HomeHeroState.ended => 'ended',
      HomeHeroState.none => 'none',
      _ => 'active',
    };
    final first = name?.trim().split(RegExp(r'\s+')).first ?? '';
    return Padding(
      key: const Key('home-greeting'),
      padding: const EdgeInsets.only(
        top: FFTokens.spacingXs,
        bottom: FFTokens.spacingLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            first.isEmpty ? greeting : '$greeting,',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            first.isEmpty
                ? '${context.tr('home.hero.$state.lead')} '
                      '${context.tr('home.hero.$state.accent')}'
                : first,
            key: const Key('home-headline'),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: 28,
              height: 32 / 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Seven day circles for this week (Monday first). A day is done when it
/// has a gym check-in or a logged activity that counts for the streak;
/// today is the solid circle.
class HomeWeekCard extends StatelessWidget {
  const HomeWeekCard({super.key, required this.data, required this.now});

  final MemberData data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final days = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    final checkinDays = <DateTime>{
      for (final m in data.checkInMoments)
        DateTime(m.at.toLocal().year, m.at.toLocal().month, m.at.toLocal().day),
    };
    bool done(DateTime d) =>
        !d.isAfter(today) &&
        (checkinDays.contains(d) ||
            summarizeDay(data.activities, d).countsForStreak);
    final active = days.where(done).length;
    const dayKeys = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    final sw = FFLocaleScope.of(context).locale.languageCode == 'sw';
    String dayName(DateTime d) {
      final s = context.tr('cal.day.${dayKeys[d.weekday - 1]}');
      // English "Mo", "Tu"; Swahili keeps its three-letter forms.
      return !sw && s.length > 2 ? s.substring(0, 2) : s;
    }

    return FFCard(
      key: const Key('home-week'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('home.week.title'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              InkWell(
                key: const Key('home-week-count'),
                borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                onTap: () => context.go('/member/activity'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context
                            .tr('home.week.activeDays')
                            .replaceAll('{n}', '$active'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: FFTokens.spacingMd),
          Row(
            children: [
              for (final d in days)
                Expanded(
                  child: _DayDot(
                    label: dayName(d),
                    number: d.day,
                    done: done(d),
                    today: d == today,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.label,
    required this.number,
    required this.done,
    required this.today,
  });

  final String label;
  final int number;
  final bool done;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final Color fill;
    final Color fg;
    if (today) {
      // Forest in light, near-white in dark: never the same as a done day.
      fill = cs.onSurface;
      fg = cs.surface;
    } else if (done) {
      fill = FFTokens.volt;
      fg = FFTokens.onVolt;
    } else {
      fill = Colors.transparent;
      fg = cs.onSurface;
    }
    return Semantics(
      label: '$label $number',
      selected: today,
      child: ExcludeSemantics(
        child: Column(
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
              child: done && !today
                  ? Icon(Icons.check, size: 18, color: fg)
                  : Text(
                      '$number',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Streak (forest tile, lime number) beside visits this month.
class HomeStatsRow extends StatelessWidget {
  const HomeStatsRow({super.key, required this.data, required this.now});

  final MemberData data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final streak = data.activityLoaded
        ? computeStreak(
                StreakKind.activity,
                today: now,
                activities: data.activities,
              )?.current ??
              0
        : 0;
    final visits = data.checkInMoments
        .where((m) => m.at.year == now.year && m.at.month == now.month)
        .length;
    // Last four weeks, oldest first: active days and gym visits per week.
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    List<int> perWeek(bool Function(DateTime day) hit) => [
      for (var w = 3; w >= 0; w--)
        [
          for (var d = 0; d < 7; d++)
            monday.subtract(Duration(days: 7 * w)).add(Duration(days: d)),
        ].where((d) => !d.isAfter(today) && hit(d)).length,
    ];
    final visitDays = <DateTime>[
      for (final m in data.checkInMoments)
        DateTime(m.at.toLocal().year, m.at.toLocal().month, m.at.toLocal().day),
    ];
    final activeWeeks = perWeek(
      (d) =>
          visitDays.contains(d) ||
          summarizeDay(data.activities, d).countsForStreak,
    );
    final visitWeeks = perWeek(visitDays.contains);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatTile(
              key: const Key('home-stat-streak'),
              label: context.tr('home.stat.streak'),
              value: '$streak',
              unit: context.tr('home.stat.days'),
              dark: true,
              icon: Icons.local_fire_department,
              bars: activeWeeks,
            ),
          ),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(
            child: _StatTile(
              key: const Key('home-stat-visits'),
              label: context.tr('home.stat.visitsMonth'),
              value: '$visits',
              unit: context.tr('home.stat.checkins'),
              dark: false,
              bars: visitWeeks,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.dark,
    this.icon,
    this.bars = const [],
  });

  final String label;
  final String value;
  final String unit;
  final IconData? icon;

  /// Real counts for the last four weeks, oldest first (mini bar chart).
  final List<int> bars;

  /// The forest tile (lime number) in both themes.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = dark ? FFTokens.ink : theme.colorScheme.surface;
    final fg = dark ? Colors.white : theme.colorScheme.onSurface;
    final muted = dark
        ? const Color(0xFFC9D3CD) // 10.9:1 on forest
        : theme.colorScheme.onSurfaceVariant;
    final number = dark ? FFTokens.volt : theme.colorScheme.onSurface;
    return Semantics(
      label: '$label: $value $unit',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(FFTokens.radiusXl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: number),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FFTokens.spacingMd),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 6,
                      children: [
                        Text(
                          value,
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: number,
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            letterSpacing: -1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            unit,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: fg,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (bars.isNotEmpty) _MiniBars(values: bars, dark: dark),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The nearest gym (or a suggested one without location): photo, name,
/// area and distance, and an Open pill.
class HomeNearestGym extends StatelessWidget {
  const HomeNearestGym({super.key, required this.gym, this.distanceKm});

  final Gym gym;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final thumb = gym.coverThumbnail;
    final distance = distanceKm == null
        ? null
        : distanceKm! < 1
        ? '${(distanceKm! * 1000).round()} m'
        : '${distanceKm!.toStringAsFixed(1)} km';
    final place = [
      if (gym.location.trim().isNotEmpty) gym.location.trim(),
      ?distance,
    ].join(' · ');
    void open() => context.go('/member/gyms/${gym.id}');
    final tile = Container(
      width: 64,
      height: 64,
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.fitness_center, color: cs.onSurfaceVariant),
    );
    return Material(
      key: const Key('home-nearest-gym'),
      color: cs.surface,
      borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingSm),
          child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: thumb == null
                ? tile
                : FFRemoteImage(
                    src: thumb,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    fallback: tile,
                  ),
          ),
          const SizedBox(width: FFTokens.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(
                    distanceKm != null
                        ? 'home.nearest.title'
                        : 'home.nearest.suggested',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  gym.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (place.isNotEmpty)
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          place,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: FFTokens.spacingSm),
          FilledButton(
            key: const Key('home-nearest-open'),
            style: FilledButton.styleFrom(
              backgroundColor: FFTokens.volt,
              foregroundColor: FFTokens.onVolt,
              minimumSize: const Size(64, 40),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            onPressed: open,
            child: Text(context.tr('home.nearest.open')),
          ),
        ],
      ),
        ),
      ),
    );
  }
}


/// Four small bars of real weekly counts (oldest first), lime. Hidden from
/// screen readers: the tile's label already says the number.
class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.values, required this.dark});

  final List<int> values;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final top = values.fold<int>(1, (m, v) => v > m ? v : m);
    final empty = dark
        ? Colors.white.withValues(alpha: 0.16)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    return ExcludeSemantics(
      child: SizedBox(
        height: 28,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final v in values) ...[
              Container(
                width: 6,
                height: v == 0 ? 4 : 6 + 22 * v / top,
                decoration: BoxDecoration(
                  color: v == 0 ? empty : FFTokens.volt,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 3),
            ],
          ],
        ),
      ),
    );
  }
}
