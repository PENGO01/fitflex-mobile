import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/api_client.dart';
import '../../shared/api_error_message.dart';
import '../../shared/events/event_result.dart';
import '../../shared/activity/gps_source.dart';
import '../../shared/activity/run_metrics.dart';
import '../../shared/activity/run_recorder.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import '../../shared/social.dart';
import 'widgets/run_widgets.dart';
import 'widgets/share_picker.dart';

/// Record a run with GPS: Start, Pause/Resume, Finish, then save or discard.
/// Everything is measured automatically; the route is private.
class MemberRecordRunPage extends StatefulWidget {
  const MemberRecordRunPage({super.key, this.eventRegistrationId});

  /// Events S6 (spec §10.2): record this run for an event registration. The
  /// run is saved first; adding it to the event can be refused, and the
  /// member is told why and can keep the run without it.
  final String? eventRegistrationId;

  @override
  State<MemberRecordRunPage> createState() => _MemberRecordRunPageState();
}

class _MemberRecordRunPageState extends State<MemberRecordRunPage> {
  bool _saving = false;
  final _notes = TextEditingController();
  ShareWith? _share;
  bool _shareChosen = false;

  // Events S6: the event this run is for (title from the result route).
  String? _eventTitle;
  String? _eventRefusal;
  bool _eventBound = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reg = widget.eventRegistrationId;
    final r = AppScope.of(context).runRecorder;
    if (!_eventBound && reg != null && reg.isNotEmpty && r != null) {
      _eventBound = true;
      // A run already under way for another registration stays as it is.
      final ok = r.bindEvent(reg);
      if (ok) _loadEventTitle(reg);
    }
  }

  Future<void> _loadEventTitle(String reg) async {
    try {
      final json = await AppScope.of(context).api.getMyEventResult(reg);
      if (!mounted) return;
      setState(
        () => _eventTitle = MemberEventResult.fromJson(
          json,
          registrationId: reg,
        ).eventTitle,
      );
    } catch (_) {
      // The chip falls back to "this event".
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _start(RunRecorder r, {bool resume = false}) async {
    final title = context.tr('run.notificationTitle');
    final text = context.tr('run.notificationText');
    if (resume) {
      await r.resume(notificationTitle: title, notificationText: text);
    } else {
      await r.start(notificationTitle: title, notificationText: text);
    }
  }

  Future<void> _finish(RunRecorder r) async {
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr('run.finishTitle'),
      message: context.tr('run.finishBody'),
      cancelLabel: context.tr('run.keepGoing'),
      confirmLabel: context.tr('run.finish'),
      confirmKey: const Key('run-finish-confirm'),
    );
    if (ok == true) await r.finish();
  }

  Future<void> _save(RunRecorder r, {bool withoutEvent = false}) async {
    final scope = AppScope.of(context);
    final shell = context.findAncestorStateOfType<MemberShellState>();
    final messenger = ScaffoldMessenger.of(context);
    final messengerSnack = FFSnack.of(context);
    final saved = context.tr('run.savedToast');
    final tr = FFLocaleScope.of(context).t;
    final locale = FFLocaleScope.of(context);
    final reg = r.eventRegistrationId;
    final forEvent = reg != null && !withoutEvent;
    setState(() {
      _saving = true;
      _eventRefusal = null;
    });
    try {
      if (withoutEvent) {
        await r.saveWithoutEvent(
          scope.api,
          notes: _notes.text,
          shareWith: _share?.toJson(),
          shareChosen: _shareChosen,
        );
      } else {
        await r.save(
          scope.api,
          notes: _notes.text,
          shareWith: _share?.toJson(),
          shareChosen: _shareChosen,
        );
      }
      // The run is saved by now: a refresh that fails must not say it wasn't.
      try {
        await shell?.refreshAfterWorkout();
      } catch (_) {}
      messengerSnack.success(saved);
      if (mounted) {
        context.go(
          forEvent
              ? AppRoutes.memberEventResultPath(reg)
              : AppRoutes.memberActivity,
        );
      }
    } catch (e) {
      // A refusal to add the run to the event (outside the time, too short,
      // already added…) is explained in words; the run is still on the phone
      // and "Keep the run without adding it to the event" saves it.
      if (forEvent && e is ApiException && e.status >= 400 && e.status < 500) {
        final known = _eventRunRefusals.contains(e.code);
        if (known) {
          if (mounted) setState(() => _eventRefusal = errorMessage(locale, e));
          return;
        }
      }
      messenger.showSnackBar(
        SnackBar(
          key: const Key('run-save-failed'),
          content: Text(
            forEvent && isNetworkError(e)
                ? tr('events.run.offlinePending')
                : tr(runSaveFailureKey(e)),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discard(RunRecorder r) async {
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr('run.discardTitle'),
      message: context.tr('run.discardBody'),
      cancelLabel: context.tr('trainer.cancel'),
      confirmLabel: context.tr('run.discard'),
      confirmKey: const Key('run-discard-confirm'),
    );
    if (ok == true) await r.discard();
  }

  @override
  Widget build(BuildContext context) {
    final r = AppScope.of(context).runRecorder;
    if (r == null || !r.supported) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('run.title'))),
        body: FFEmptyState(
          title: context.tr('run.unsupportedTitle'),
          body: context.tr('run.unsupportedBody'),
        ),
      );
    }
    final weightKg = MemberDataScope.of(
      context,
    ).me?.user.memberProfile?.weightKg;
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) {
        final m = r.metrics;
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            title: Text(context.tr('run.title')),
            leading: BackButton(
              onPressed: () => context.go(AppRoutes.memberActivity),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            children: [
              if (r.restored)
                Padding(
                  padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
                  child: FFAlert(
                    key: const Key('run-restored'),
                    message: context.tr('run.restoredBody'),
                  ),
                ),
              if (r.eventRegistrationId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FFBadge(
                      key: const Key('run-event-chip'),
                      label: context
                          .tr('events.run.recordingFor')
                          .replaceFirst(
                            '{event}',
                            (_eventTitle ?? '').isEmpty
                                ? context.tr('events.run.thisEvent')
                                : _eventTitle!,
                          ),
                      tone: FFBadgeTone.brand,
                      wrap: true,
                    ),
                  ),
                ),
              if (r.access != null && r.access != GpsAccess.granted)
                _AccessAlert(recorder: r),
              RunMap(
                segments: r.segments,
                follow: r.state == RunState.recording,
                height: r.state == RunState.finished ? 220 : 280,
              ),
              const SizedBox(height: FFTokens.spacingMd),
              if (r.state == RunState.finished) ...[
                RunSummaryGrid(
                  distanceKm: m.distanceKm,
                  seconds: m.movingSeconds,
                  elevationGainM: m.elevationGainM,
                  calories: runCalories(
                    distanceKm: m.distanceKm,
                    movingSeconds: m.movingSeconds,
                    weightKg: weightKg,
                  ),
                ),
                const SizedBox(height: FFTokens.spacingMd),
                RunSplits(splits: m.splits),
                const SizedBox(height: FFTokens.spacingMd),
                FFTextField(
                  controller: _notes,
                  label: context.tr('run.notes'),
                  hint: context.tr('run.notesHint'),
                  maxLength: 200,
                ),
                FFActionTile(
                  key: const Key('run-share'),
                  icon: _shareChosen && _share == null
                      ? Icons.lock_outline
                      : Icons.people_outline,
                  title: context.tr('audience.whoCanSee'),
                  subtitle: _shareChosen
                      ? shareLabel(context, _share)
                      : context.tr('audience.useDefault'),
                  onTap: () async {
                    final res = await pickShare(context, initial: _share);
                    if (!res.cancelled) {
                      setState(() {
                        _share = res.share;
                        _shareChosen = true;
                      });
                    }
                  },
                ),
                Text(
                  context.tr('run.privateNote'),
                  style: theme.textTheme.bodySmall,
                ),
                if (_eventRefusal != null) ...[
                  const SizedBox(height: FFTokens.spacingSm),
                  FFAlert(
                    key: const Key('run-event-refused'),
                    tone: FFAlertTone.warning,
                    message: _eventRefusal!,
                  ),
                  FFButton(
                    key: const Key('run-keep-without-event'),
                    label: context.tr('events.run.keep'),
                    variant: FFButtonVariant.secondary,
                    onPressed: _saving
                        ? null
                        : () => _save(r, withoutEvent: true),
                  ),
                ],
                const SizedBox(height: FFTokens.spacingMd),
                Row(
                  children: [
                    Expanded(
                      child: FFButton(
                        key: const Key('run-discard'),
                        label: context.tr('run.discard'),
                        maxLines: 3,
                        onPressed: _saving ? null : () => _discard(r),
                        variant: FFButtonVariant.secondary,
                      ),
                    ),
                    const SizedBox(width: FFTokens.spacingSm),
                    Expanded(
                      child: FFButton(
                        key: const Key('run-save'),
                        label: context.tr(
                          r.eventRegistrationId != null
                              ? 'events.run.save'
                              : 'run.save',
                        ),
                        maxLines: 3,
                        onPressed: _saving ? null : () => _save(r),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                FFCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RunStat(
                        value: formatRunKm(m.distanceKm),
                        label: context.tr('run.distance'),
                        big: true,
                      ),
                      const SizedBox(height: FFTokens.spacingMd),
                      Row(
                        children: [
                          Expanded(
                            child: RunStat(
                              value: formatDuration(r.elapsed.inSeconds),
                              label: context.tr('run.time'),
                            ),
                          ),
                          Expanded(
                            child: RunStat(
                              value: formatPace(m.paceSecPerKm),
                              label: context.tr('run.avgPace'),
                            ),
                          ),
                          Expanded(
                            child: RunStat(
                              value: '${m.elevationGainM} m',
                              label: context.tr('run.climb'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FFTokens.spacingSm),
                Text(
                  context.tr(switch (r.state) {
                    RunState.recording when !r.hasFix => 'run.waitingGps',
                    RunState.recording => 'run.recordingHint',
                    RunState.paused => 'run.pausedHint',
                    _ => 'run.startHint',
                  }),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: FFTokens.spacingLg),
                _Controls(
                  recorder: r,
                  onStart: () => _start(r),
                  onResume: () => _start(r, resume: true),
                  onFinish: () => _finish(r),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Refusals of "add this run to the event" that the member can read and act
/// on (spec §5.2). Anything else is the general save failure.
const _eventRunRefusals = {
  'run_outside_window',
  'distance_too_short',
  'activity_not_recorded_in_app',
  'activity_already_linked',
  'run_already_linked',
  'event_not_open_for_results',
  'registration_not_found',
  'feature_disabled',
};

class _Controls extends StatelessWidget {
  const _Controls({
    required this.recorder,
    required this.onStart,
    required this.onResume,
    required this.onFinish,
  });

  final RunRecorder recorder;
  final VoidCallback onStart;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final big = FilledButton.styleFrom(minimumSize: const Size.fromHeight(56));
    switch (recorder.state) {
      case RunState.idle:
        return FilledButton.icon(
          key: const Key('run-start'),
          style: big,
          onPressed: onStart,
          icon: const Icon(Icons.play_arrow),
          label: Text(context.tr('run.start')),
        );
      case RunState.recording:
        return FilledButton.tonalIcon(
          key: const Key('run-pause'),
          style: big,
          onPressed: recorder.pause,
          icon: const Icon(Icons.pause),
          label: Text(context.tr('run.pause')),
        );
      case RunState.paused:
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('run-resume'),
                style: big,
                onPressed: onResume,
                icon: const Icon(Icons.play_arrow),
                label: Text(context.tr('run.resume')),
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('run-finish'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: onFinish,
                icon: const Icon(Icons.flag),
                label: Text(context.tr('run.finish')),
              ),
            ),
          ],
        );
      case RunState.finished:
        return const SizedBox.shrink();
    }
  }
}

class _AccessAlert extends StatelessWidget {
  const _AccessAlert({required this.recorder});

  final RunRecorder recorder;

  @override
  Widget build(BuildContext context) {
    final off = recorder.access == GpsAccess.serviceOff;
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FFAlert(
            key: const Key('run-access'),
            tone: FFAlertTone.warning,
            message: context.tr(
              off ? 'run.locationOffBody' : 'run.permissionBody',
            ),
          ),
          FFButton(
            label: context.tr('phoneSteps.openSettings'),
            onPressed: off
                ? recorder.gps.openLocationSettings
                : recorder.gps.openAppSettings,
            variant: FFButtonVariant.ghost,
            size: FFButtonSize.sm,
          ),
        ],
      ),
    );
  }
}
