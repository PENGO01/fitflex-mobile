import 'package:flutter/material.dart';

import '../../../shared/activity/activity_summary.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';

/// Activity overview header from the DS v1.0 Activity board: Week / Month /
/// Year, three stat tiles and a bar chart with lime bars on active days.
///
/// Everything is counted from the member's own data: logged activity
/// (`summarizeDay`) and gym check-ins.
class ActivityPeriodCard extends StatefulWidget {
  const ActivityPeriodCard({super.key, required this.data, required this.now});

  final MemberData data;
  final DateTime now;

  @override
  State<ActivityPeriodCard> createState() => _ActivityPeriodCardState();
}

class _Bucket {
  _Bucket(this.label, this.minutes, this.active);
  final String label;
  final int minutes;
  final bool active;
}

class _ActivityPeriodCardState extends State<ActivityPeriodCard> {
  String _period = 'week';

  static const _dayKeys = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = widget.now;
    final today = DateTime(now.year, now.month, now.day);
    final visitDays = <DateTime>{
      for (final m in widget.data.checkInMoments)
        DateTime(m.at.toLocal().year, m.at.toLocal().month, m.at.toLocal().day),
    };
    final visitsList = [
      for (final m in widget.data.checkInMoments)
        DateTime(m.at.toLocal().year, m.at.toLocal().month, m.at.toLocal().day),
    ];

    // The days in the chosen period, up to today.
    final DateTime start = switch (_period) {
      'month' => DateTime(today.year, today.month),
      'year' => DateTime(today.year),
      _ => today.subtract(Duration(days: today.weekday - 1)),
    };
    final days = <DateTime>[];
    for (var d = start; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1)) {
      days.add(d);
    }
    final summaries = {
      for (final d in days) d: summarizeDay(widget.data.activities, d),
    };
    bool isActive(DateTime d) =>
        visitDays.contains(d) || summaries[d]!.countsForStreak;

    final activeDays = days.where(isActive).length;
    final visits = visitsList.where((d) => !d.isBefore(start) && !d.isAfter(today)).length;
    final minutes = days.fold<int>(0, (s, d) => s + summaries[d]!.activeMinutes);

    final sw = FFLocaleScope.of(context).locale.languageCode == 'sw';
    String dayLetter(int weekday) {
      final s = context.tr('cal.day.${_dayKeys[weekday - 1]}');
      return sw ? s : s.substring(0, 1);
    }

    final List<_Bucket> buckets;
    switch (_period) {
      case 'year':
        buckets = [
          for (var m = 1; m <= 12; m++)
            () {
              final inMonth = days.where((d) => d.month == m);
              return _Bucket(
                '$m',
                inMonth.where(isActive).length,
                inMonth.any(isActive),
              );
            }(),
        ];
      case 'month':
        final last = DateTime(today.year, today.month + 1, 0).day;
        buckets = [
          for (var i = 1; i <= last; i++)
            () {
              final d = DateTime(today.year, today.month, i);
              final s = summaries[d];
              return _Bucket(
                i == 1 || i % 7 == 0 ? '$i' : '',
                s == null ? 0 : s.activeMinutes,
                s != null && isActive(d),
              );
            }(),
        ];
      default:
        buckets = [
          for (var i = 0; i < 7; i++)
            () {
              final d = start.add(Duration(days: i));
              final s = summaries[d];
              return _Bucket(
                dayLetter(d.weekday),
                s == null ? 0 : s.activeMinutes,
                s != null && isActive(d),
              );
            }(),
        ];
    }

    return Column(
      key: const Key('activity-period'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFSegmented(
          key: const Key('activity-period-tabs'),
          value: _period,
          options: [
            ('week', context.tr('activity.period.week')),
            ('month', context.tr('activity.period.month')),
            ('year', context.tr('activity.period.year')),
          ],
          onChanged: (v) => setState(() => _period = v),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        Row(
          children: [
            Expanded(
              child: _Tile(
                key: const Key('activity-stat-days'),
                value: '$activeDays',
                label: context.tr('activity.stat.activeDays'),
                dark: true,
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: _Tile(
                key: const Key('activity-stat-visits'),
                value: '$visits',
                label: context.tr('activity.stat.visits'),
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: _Tile(
                key: const Key('activity-stat-minutes'),
                value: '$minutes',
                label: context.tr('activity.stat.minutes'),
              ),
            ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFCard(
          key: const Key('activity-chart'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Semantics(
            label: context
                .tr('activity.chart.summary')
                .replaceAll('{n}', '$activeDays'),
            child: ExcludeSemantics(
              child: _Bars(
                buckets: buckets,
                dense: _period == 'month',
                inactive: cs.surfaceContainerHighest,
                labelColor: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.value,
    required this.label,
    this.dark = false,
  });

  final String value;
  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = dark ? FFTokens.ink : theme.colorScheme.surface;
    final number = dark ? FFTokens.volt : theme.colorScheme.onSurface;
    final muted = dark
        ? const Color(0xFFC9D3CD)
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(FFTokens.radiusXl),
            boxShadow: dark || theme.brightness == Brightness.dark
                ? null
                : [
                    BoxShadow(
                      color: FFTokens.ink.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: number,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({
    required this.buckets,
    required this.dense,
    required this.inactive,
    required this.labelColor,
  });

  final List<_Bucket> buckets;
  final bool dense;
  final Color inactive;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    final peak = buckets.fold<int>(1, (m, b) => b.minutes > m ? b.minutes : m);
    const chart = 110.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final b in buckets)
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: dense ? 1 : 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: b.active
                        ? (chart * (b.minutes / peak)).clamp(14.0, chart)
                        : 6,
                    decoration: BoxDecoration(
                      color: b.active ? FFTokens.volt : inactive,
                      borderRadius: BorderRadius.circular(dense ? 3 : 8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 14,
                    child: OverflowBox(
                      maxWidth: 24,
                      child: Text(
                        b.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: labelColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
