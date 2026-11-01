import 'package:flutter/material.dart';

import '../../../../shared/activity/run_metrics.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_result.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../../widgets/run_widgets.dart' show formatRunKm;

/// One FitFlex run tied to an event (spec §10.2): date, distance, moving
/// time, the "not official" line, a comparison with the official time when
/// there is one, the organizer-check note when the run was flagged, and
/// "Remove from event".
class EventRunCard extends StatelessWidget {
  const EventRunCard({
    super.key,
    required this.link,
    this.officialMs,
    this.onUnlink,
    this.busy = false,
  });

  final EventRunLink link;

  /// The participant's official time, for the comparison line.
  final int? officialMs;
  final VoidCallback? onUnlink;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final km = link.distanceMeters == null ? null : link.distanceMeters! / 1000;
    final seconds = link.movingSeconds ?? (link.elapsedMs ?? 0) ~/ 1000;
    final compare = _compare(context);
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_run, size: FFTokens.iconMd),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(
                child: Text(
                  link.startedAt == null
                      ? context.tr('events.run.card.title')
                      : formatDayTime(link.startedAt, locale: lang),
                  style: tt.titleSmall,
                ),
              ),
              if (link.isPendingApproval) ...[
                const SizedBox(width: FFTokens.spacingXs),
                Flexible(
                  child: FFBadge(
                    key: const Key('run-card-waiting'),
                    label: context.tr('events.run.waiting'),
                    tone: FFBadgeTone.warning,
                    wrap: true,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            [
              if (km != null) formatRunKm(km),
              if (seconds > 0) formatDuration(seconds),
            ].join(' · '),
            key: const Key('run-card-numbers'),
            style: tt.titleMedium,
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            context.tr('events.run.notOfficial'),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (compare != null)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                compare,
                key: const Key('run-card-compare'),
                style: tt.bodyMedium,
              ),
            ),
          if (link.isFast)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingSm),
              child: FFAlert(
                key: const Key('run-card-flag'),
                tone: FFAlertTone.info,
                message: context.tr('events.run.flag.fast'),
              ),
            ),
          if (link.canUnlink && onUnlink != null)
            Align(
              alignment: Alignment.centerLeft,
              child: FFButton(
                key: const Key('run-card-remove'),
                label: context.tr('events.run.remove'),
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
                loading: busy,
                onPressed: onUnlink,
              ),
            ),
        ],
      ),
    );
  }

  /// "Official time is 4:12 slower than your FitFlex run", only when both
  /// numbers exist and the run was not the result itself.
  String? _compare(BuildContext context) {
    final official = officialMs;
    if (official == null || link.isEventRun) return null;
    final mine = link.movingSeconds;
    if (mine == null || mine <= 0) return null;
    final diff = (official ~/ 1000) - mine;
    if (diff == 0) return null;
    return context
        .tr('events.run.compare')
        .replaceFirst('{diff}', formatDuration(diff.abs()))
        .replaceFirst(
          '{slower}',
          context.tr(diff > 0 ? 'events.run.slower' : 'events.run.faster'),
        );
  }
}
