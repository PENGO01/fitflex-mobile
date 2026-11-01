import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app_scope.dart';
import '../../../../router.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_summary.dart';
import '../../../../shared/events/events_options.dart';
import '../../../../shared/events/run_eligibility.dart';
import '../../../../shared/i18n.dart';

/// The S6 entry points on the ticket and registration pages (events S6 spec
/// §5.6, §10.1): "Your result" once the event has started, and "Start run for
/// this event" (Android, where recording works) or "Add a recorded run"
/// (every platform) inside the run window. Draws nothing while the server has
/// the parts switched off, so with every S6 flag off the pages are unchanged.
class EventResultEntry extends StatelessWidget {
  const EventResultEntry({
    super.key,
    required this.registrationId,
    required this.event,
    required this.options,
    required this.confirmed,
    required this.isParticipant,
    this.now,
  });

  final String registrationId;
  final EventSummary? event;
  final EventsOptions options;
  final bool confirmed;

  /// The account holder is the person running (not only the purchaser).
  final bool isParticipant;

  /// For tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final results = options.results;
    final e = event;
    if (!confirmed ||
        !isParticipant ||
        e == null ||
        (!results.enabled && !results.runs) ||
        e.availability == EventAvailability.cancelled ||
        e.status == 'cancelled') {
      return const SizedBox.shrink();
    }
    final at = (now ?? DateTime.now()).toUtc();
    final starts = e.startsAt;
    final ends = e.endsAt;
    final started = starts != null && !at.isBefore(starts);
    var inRunWindow = false;
    if (results.runs && starts != null && ends != null) {
      final w = runWindow(
        isVirtual: e.type == 'virtual',
        startsAt: starts,
        endsAt: ends,
      );
      inRunWindow =
          !at.isBefore(w.from) &&
          !at.isAfter(ends.add(Duration(days: options.runs.maxDaysAfter)));
    }
    final showResult = results.enabled && started;
    if (!showResult && !inRunWindow) return const SizedBox.shrink();
    final recorder = AppScope.of(context).runRecorder;
    final canRecord = recorder != null && recorder.supported;
    return Column(
      key: const Key('result-entry'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: FFTokens.spacingMd),
        if (showResult)
          FFActionTile(
            key: const Key('entry-result'),
            icon: Icons.emoji_events_outlined,
            title: context.tr('events.result.title'),
            onTap: () =>
                context.push(AppRoutes.memberEventResultPath(registrationId)),
          ),
        if (inRunWindow) ...[
          if (canRecord)
            FFButton(
              key: const Key('entry-start-run'),
              label: context.tr('events.run.start'),
              icon: Icons.play_arrow,
              onPressed: () => context.push(
                '${AppRoutes.memberRecordRun}'
                '?registration=${Uri.encodeQueryComponent(registrationId)}',
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
              child: Text(
                context.tr('events.run.unsupported'),
                key: const Key('entry-run-unsupported'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          FFButton(
            key: const Key('entry-add-run'),
            label: context.tr('events.run.add'),
            variant: FFButtonVariant.secondary,
            icon: Icons.add,
            onPressed: () =>
                context.push(AppRoutes.memberEventRunsPath(registrationId)),
          ),
        ],
      ],
    );
  }
}
