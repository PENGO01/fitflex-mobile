import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app_scope.dart';
import '../../../../router.dart';
import '../../../../shared/activity/activity.dart';
import '../../../../shared/activity/run_metrics.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_detail.dart';
import '../../../../shared/events/event_result.dart';
import '../../../../shared/events/event_time.dart';
import '../../../../shared/events/events_options.dart';
import '../../../../shared/events/run_eligibility.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../../../../shared/shop_checkout.dart';
import '../../widgets/run_widgets.dart' show formatRunKm;
import '../events_registration_gate.dart';
import 'run_card.dart';

enum _Phase { loading, ready, error }

/// `/member/events/registrations/:registrationId/runs` (events S6 spec
/// §10.2): the runs added to this registration, "Start run for this event"
/// where the phone can record, and "Add a recorded run" everywhere. The
/// server checks every run; the chips here only save a pointless tap.
class EventRunLinksPage extends StatefulWidget {
  const EventRunLinksPage({
    super.key,
    required this.registrationId,
    this.options,
  });

  final String registrationId;
  final EventsOptions? options;

  @override
  State<EventRunLinksPage> createState() => _EventRunLinksPageState();
}

class _EventRunLinksPageState extends State<EventRunLinksPage> {
  _Phase _phase = _Phase.loading;
  MemberEventResult? _data;
  EventDetail? _event;
  List<Activity> _runs = const [];
  Object? _error;
  bool _busy = false;
  bool _runsFailed = false;

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || !eventsRegistrationAllowed(context, _options)) return;
    if (!_options.results.runs) {
      setState(() => _phase = _Phase.ready);
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _phase = _data == null ? _Phase.loading : _phase;
      _error = null;
    });
    try {
      final json = await _api.getMyEventResult(widget.registrationId);
      if (!mounted) return;
      final data = MemberEventResult.fromJson(
        json,
        registrationId: widget.registrationId,
      );
      EventDetail? detail = _event;
      if (detail == null && data.eventId.isNotEmpty) {
        try {
          detail = EventDetail.fromJson(await _api.getEvent(data.eventId));
        } catch (_) {
          // Without the dates the chips say "Available" and the server
          // decides.
        }
      }
      var runs = const <Activity>[];
      var failed = false;
      try {
        final now = DateTime.now();
        final raw = await _api.myActivities(
          from: now.subtract(const Duration(days: 7)),
          to: now.add(const Duration(days: 1)),
        );
        runs = [
          for (final a in raw)
            if (a is Map) Activity.fromJson(Map<String, dynamic>.from(a)),
        ].where(isListableRun).take(10).toList();
      } catch (_) {
        failed = true;
      }
      if (!mounted) return;
      setState(() {
        _data = data;
        _event = detail;
        _runs = runs;
        _runsFailed = failed;
        _phase = _Phase.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _phase = _data == null ? _Phase.error : _phase;
      });
    }
  }

  void _back() => context.canPop()
      ? context.pop()
      : context.go(AppRoutes.memberEventResultPath(widget.registrationId));

  RunFit _fit(Activity a) {
    final d = _data!;
    final e = _event?.summary;
    return fitOf(
      a,
      isVirtual: d.isVirtual,
      startsAt: e?.startsAt,
      endsAt: e?.endsAt,
      categoryMeters: d.distanceMeters ?? 0,
      toleranceBps: _options.runs.toleranceBps,
      linkedActivityIds: {
        for (final l in d.runLinks)
          if (l.activityId != null) l.activityId!,
      },
    );
  }

  Future<void> _unlink(EventRunLink link) async {
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    setState(() => _busy = true);
    try {
      await _api.unlinkEventRun(widget.registrationId, link.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      snack.error(errorMessage(locale, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(Activity a) async {
    final d = _data!;
    final ok = await showFFSheet<bool>(
      context,
      title: context.tr('events.run.add'),
      wideDialogWidth: 480,
      child: _ConfirmRunSheet(
        activity: a,
        eventTitle: d.eventTitle,
        isVirtual: d.isVirtual,
        registrationId: widget.registrationId,
        api: _api,
      ),
    );
    if (ok == true && mounted) {
      // After linking: back to the result page with the new run card.
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.memberEventResultPath(widget.registrationId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.run.section')),
      ),
      body: switch (_phase) {
        _Phase.loading => FFSkeletonList(
          key: const Key('runs-loading'),
          semanticLabel: context.tr('events.run.section'),
        ),
        _Phase.error => Center(
          child: FFErrorState(
            key: const Key('runs-error'),
            message: _error == null
                ? null
                : errorMessage(FFLocaleScope.of(context), _error!),
            retryLabel: context.tr('common.retry'),
            onRetry: _load,
          ),
        ),
        _ => ListView(
          key: const Key('runs-scroll'),
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _body(context),
                ),
              ),
            ),
          ],
        ),
      },
    );
  }

  /// Why runs can't be added now, or null when they can.
  String? _closedReason(BuildContext context, MemberEventResult d) {
    final e = _event?.summary;
    if (d.eventCancelled || (e?.availability.wire == 'cancelled')) {
      return context.tr('events.run.cancelled');
    }
    if (d.placeEnded) return context.tr('events.result.cancelled');
    final now = DateTime.now().toUtc();
    final starts = e?.startsAt;
    final ends = e?.endsAt;
    if (starts != null && ends != null) {
      final w = runWindow(
        isVirtual: d.isVirtual,
        startsAt: starts,
        endsAt: ends,
      );
      if (now.isBefore(w.from)) {
        return context
            .tr('events.run.opens')
            .replaceFirst(
              '{date}',
              eventDateTime(
                w.from,
                e!.utcOffsetMinutes,
                e.timezoneAbbr,
                locale: FFLocaleScope.of(context).locale.languageCode,
              ),
            );
      }
      final last = ends.add(Duration(days: _options.runs.maxDaysAfter));
      if (now.isAfter(last)) return context.tr('events.run.closed');
    }
    return null;
  }

  List<Widget> _body(BuildContext context) {
    final d = _data;
    if (!_options.results.runs || d == null) {
      return [
        FFEmptyState(
          key: const Key('runs-unavailable'),
          title: context.tr('events.unavailable.title'),
          body: context.tr('events.unavailable.body'),
        ),
      ];
    }
    if (d.statusOnly) {
      return [
        FFAlert(
          key: const Key('runs-purchaser'),
          message: context.tr('events.result.purchaser'),
        ),
      ];
    }
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final closed = _closedReason(context, d);
    final recorder = AppScope.of(context).runRecorder;
    final canRecord = recorder != null && recorder.supported;
    final official =
        d.stage == ResultStage.official || d.stage == ResultStage.corrected
        ? d.result?.shownMs
        : null;
    return [
      FFPageHeader(
        title: d.eventTitle.isEmpty
            ? context.tr('events.run.section')
            : d.eventTitle,
        description: d.categoryName.isEmpty ? null : d.categoryName,
      ),
      if (closed != null)
        FFAlert(
          key: const Key('runs-closed'),
          tone: FFAlertTone.info,
          message: closed,
        )
      else ...[
        if (canRecord)
          FFButton(
            key: const Key('runs-start'),
            label: context.tr('events.run.start'),
            icon: Icons.play_arrow,
            fullWidth: true,
            onPressed: () => context.push(
              '${AppRoutes.memberRecordRun}'
              '?registration=${Uri.encodeQueryComponent(widget.registrationId)}',
            ),
          )
        else
          FFAlert(
            key: const Key('runs-unsupported'),
            message: context.tr('events.run.unsupported'),
          ),
      ],
      const SizedBox(height: FFTokens.spacingMd),
      for (final l in d.runLinks)
        EventRunCard(
          link: l,
          officialMs: official,
          busy: _busy,
          onUnlink: () => _unlink(l),
        ),
      if (d.runLinks.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: Text(
            context.tr('events.run.empty'),
            key: const Key('runs-empty'),
          ),
        ),
      if (closed == null) ...[
        FFSectionTitle(context.tr('events.run.add')),
        if (_runsFailed)
          FFAlert(
            key: const Key('runs-list-failed'),
            tone: FFAlertTone.warning,
            message: context.tr('events.run.listFailed'),
          )
        else if (_runs.isEmpty)
          Text(
            context.tr('events.run.noneRecent'),
            key: const Key('runs-none-recent'),
          )
        else
          for (final a in _runs) _runTile(context, a, lang),
      ],
    ];
  }

  Widget _runTile(BuildContext context, Activity a, String lang) {
    final fit = _fit(a);
    final distance = formatRunKm(a.distanceKm ?? 0);
    final seconds = a.movingSeconds ?? (a.durationMinutes ?? 0) * 60;
    final (label, tone) = switch (fit) {
      RunFit.available => (
        context.tr('events.run.state.available'),
        FFBadgeTone.success,
      ),
      RunFit.short => (
        context
            .tr('events.run.state.short')
            .replaceFirst(
              '{distance}',
              formatRunKm((_data!.distanceMeters ?? 0) / 1000),
            ),
        FFBadgeTone.warning,
      ),
      RunFit.outside => (
        context.tr('events.run.state.outside'),
        FFBadgeTone.gray,
      ),
      RunFit.linked => (
        context.tr('events.run.state.linked'),
        FFBadgeTone.gray,
      ),
      RunFit.notRecordedInApp => (
        context.tr('events.run.error.activity_not_recorded_in_app'),
        FFBadgeTone.gray,
      ),
    };
    final title = formatDayTime(a.startedAt, locale: lang);
    final sub = [
      distance,
      if (seconds > 0) formatDuration(seconds),
    ].join(' · ');
    return Semantics(
      container: true,
      button: fit == RunFit.available,
      label: '$title, $sub, $label',
      child: ExcludeSemantics(
        child: FFCard(
          key: Key('run-row-${a.id}'),
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: fit == RunFit.available && !_busy ? () => _add(a) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.all(FFTokens.spacingMd),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            sub,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: FFTokens.spacingSm),
                    Flexible(
                      child: FFBadge(label: label, tone: tone, wrap: true),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "This run will be sent to the organizer…" / "…shown next to your official
/// result": exactly what happens, then **Add this run**.
class _ConfirmRunSheet extends StatefulWidget {
  const _ConfirmRunSheet({
    required this.activity,
    required this.eventTitle,
    required this.isVirtual,
    required this.registrationId,
    required this.api,
  });

  final Activity activity;
  final String eventTitle;
  final bool isVirtual;
  final String registrationId;
  final ApiClient api;

  @override
  State<_ConfirmRunSheet> createState() => _ConfirmRunSheetState();
}

class _ConfirmRunSheetState extends State<_ConfirmRunSheet> {
  bool _sending = false;
  String? _error;
  final String _key = newCheckoutKey();

  Future<void> _send() async {
    final locale = FFLocaleScope.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.api.linkEventRun(
        widget.registrationId,
        widget.activity.id,
        idempotencyKey: _key,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = errorMessage(locale, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final a = widget.activity;
    return Padding(
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              [
                formatDayTime(a.startedAt, locale: lang),
                formatRunKm(a.distanceKm ?? 0),
                if ((a.movingSeconds ?? 0) > 0)
                  formatDuration(a.movingSeconds!),
              ].join(' · '),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              widget.isVirtual
                  ? context
                        .tr('events.run.confirm.virtual')
                        .replaceFirst('{event}', widget.eventTitle)
                  : context.tr('events.run.confirm.inPerson'),
              key: const Key('run-confirm-text'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                child: FFAlert(
                  key: const Key('run-confirm-error'),
                  tone: FFAlertTone.error,
                  message: _error!,
                ),
              ),
            const SizedBox(height: FFTokens.spacingMd),
            FFButton(
              key: const Key('run-confirm-add'),
              label: context.tr('events.run.addThis'),
              fullWidth: true,
              loading: _sending,
              onPressed: _sending ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}
