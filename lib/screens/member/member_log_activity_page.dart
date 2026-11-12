import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/activity/activity.dart';
import '../../shared/activity/manual_activity_log.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import '../../shared/social.dart';
import 'widgets/share_picker.dart';
import 'widgets/activity_widgets.dart';
import 'widgets/gym_visit_tile.dart' show visitLinkWindow, withinVisit;
import '../../shared/formatters.dart';

/// Activity → Log activity: a session the member did without FitFlex
/// tracking it. Saved through the existing `POST /me/activities` contract
/// (sample mode keeps it in the session's sample log).
class MemberLogActivityPage extends StatefulWidget {
  const MemberLogActivityPage({
    super.key,
    this.now,
    this.initialType,
    this.gymId,
    this.startedAt,
  });

  /// Injectable clock for tests.
  final DateTime? now;
  final ActivityType? initialType;

  /// Logging from a gym visit: the gym, and when the member checked in.
  final String? gymId;
  final DateTime? startedAt;

  @override
  State<MemberLogActivityPage> createState() => _MemberLogActivityPageState();
}

class _MemberLogActivityPageState extends State<MemberLogActivityPage> {
  late ActivityType _type = widget.initialType ?? ActivityType.walking;
  late DateTime _day;
  late TimeOfDay _time;
  final _duration = TextEditingController();
  final _distance = TextEditingController();
  final _steps = TextEditingController();
  final _name = TextEditingController();
  final _notes = TextEditingController();
  ActivityIntensity? _intensity;
  Map<String, String> _errors = const {};
  String? _submitError;
  bool _saving = false;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    // From a gym visit: when the member checked in. Otherwise today,
    // starting an hour ago. Either way on the quarter hour.
    final start =
        widget.startedAt?.toLocal() ?? _now.subtract(const Duration(hours: 1));
    _day = DateTime(start.year, start.month, start.day);
    _time = TimeOfDay(hour: start.hour, minute: start.minute ~/ 15 * 15);
  }

  @override
  void dispose() {
    for (final c in [_duration, _distance, _steps, _name, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime get _startedAt =>
      DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute);

  ManualActivityDraft _draft() => ManualActivityDraft(
    type: _type,
    startedAt: _startedAt,
    durationMinutes: int.tryParse(_duration.text.trim()),
    distanceKm: double.tryParse(_distance.text.trim().replaceAll(',', '.')),
    steps: int.tryParse(_steps.text.trim().replaceAll(',', '')),
    intensity: _intensity,
    name: _name.text,
    notes: _notes.text,
    shareWith: _share?.toJson(),
    shareChosen: _shareChosen,
    gymId: widget.gymId,
  );

  ShareWith? _share;
  bool _shareChosen = false;

  Future<void> _pickDay() async {
    final now = _now;
    final visitAt = widget.startedAt?.toLocal();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      // From a visit, only the days its 48-hour window covers.
      firstDate: visitAt != null
          ? DateTime(visitAt.year, visitAt.month, visitAt.day)
          : DateTime(now.year, now.month, now.day - manualMaxDaysBack),
      lastDate: visitAt != null && visitAt.add(visitLinkWindow).isBefore(now)
          ? DateTime(
              visitAt.add(visitLinkWindow).year,
              visitAt.add(visitLinkWindow).month,
              visitAt.add(visitLinkWindow).day,
            )
          : DateTime(now.year, now.month, now.day),
    );
    if (picked != null) {
      setState(() {
        _day = picked;
        _errors = {..._errors}..remove('startedAt');
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      // 24-hour clock, like the times everywhere else in the app.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _time = picked;
        _errors = {..._errors}..remove('startedAt');
      });
    }
  }

  Future<void> _save() async {
    final draft = _draft();
    final errors = {...validateManualActivity(draft, _now)};
    // From a visit, the session has to fall within it to show under it.
    final visitAt = widget.startedAt;
    if (visitAt != null &&
        !errors.containsKey('startedAt') &&
        !withinVisit(visitAt, draft.startedAt)) {
      errors['startedAt'] = 'logActivity.error.visitWindow';
    }
    setState(() {
      _errors = errors;
      _submitError = null;
    });
    if (errors.isNotEmpty) return;

    final scope = AppScope.of(context);
    final data = MemberDataScope.of(context);
    final locale = FFLocaleScope.of(context);
    final messenger = FFSnack.of(context);
    final router = GoRouter.of(context);
    final done = context.tr('logActivity.saved');
    setState(() => _saving = true);
    try {
      final saved = await scope.manualLog.log(draft);
      // Everything on the Activity screens (history, totals, goals,
      // streaks, challenges) derives from this list, so they all move.
      data.update(
        (d) =>
            d.activities = [...d.activities, saved]
              ..sort((a, b) => b.startedAt.compareTo(a.startedAt)),
      );
      messenger.success(done);
      if (router.canPop()) {
        router.pop(true);
      } else {
        router.go(AppRoutes.memberActivity);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _submitError = errorMessage(locale, error);
      });
    }
  }

  /// The visit's gym, by name when the app knows it.
  String? _gymName(BuildContext context) {
    final id = widget.gymId;
    if (id == null) return null;
    final data = context
        .dependOnInheritedWidgetOfExactType<MemberDataScope>()
        ?.notifier;
    return data?.checkins
            .where((c) => c.gymId == id)
            .map((c) => c.gym?.name)
            .nonNulls
            .firstOrNull ??
        data?.gyms.where((g) => g.id == id).map((g) => g.name).firstOrNull ??
        id;
  }

  String? _err(String field) {
    final key = _errors[field];
    return key == null ? null : context.tr(key);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = manualFieldsFor(_type);
    final lang = Localizations.localeOf(context).languageCode;
    final dateLabel = DateFormat('EEE d MMM', lang).format(_day);
    final timeLabel = context.localTimeOfDay(_startedAt);

    return ListView(
      key: const Key('log-activity'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FFButton(
            label: context.tr('activity.title'),
            onPressed: () => context.canPop()
                ? context.pop()
                : context.go(AppRoutes.memberActivity),
            variant: FFButtonVariant.ghost,
            size: FFButtonSize.sm,
            icon: Icons.arrow_back,
          ),
        ),
        FFPageHeader(title: context.tr('logActivity.title')),
        Text(context.tr('logActivity.intro'), style: theme.textTheme.bodySmall),
        if (_gymName(context) case final gym?) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Row(
            key: const Key('log-gym'),
            children: [
              Icon(
                Icons.storefront_outlined,
                size: FFTokens.iconSm,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: FFTokens.spacingXs),
              Expanded(
                child: Text(
                  context.tr('logActivity.atGym').replaceAll('{gym}', gym),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        Text(
          context.tr('logActivity.type'),
          style: FFTokens.monoLabel(theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Wrap(
          spacing: FFTokens.spacingSm,
          runSpacing: FFTokens.spacingSm,
          children: [
            for (final t in manualActivityTypes)
              ChoiceChip(
                key: Key('log-type-${t.wire}'),
                avatar: Icon(activityTypeIcon(t), size: FFTokens.iconSm),
                label: Text(activityTypeLabel(context, t)),
                selected: _type == t,
                showCheckmark: false,
                onSelected: (_) => setState(() {
                  _type = t;
                  _errors = const {};
                }),
              ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingLg),
        Row(
          children: [
            Expanded(
              child: FFButton(
                key: const Key('log-date'),
                label: dateLabel,
                onPressed: _pickDay,
                variant: FFButtonVariant.secondary,
                icon: Icons.event_outlined,
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: FFButton(
                key: const Key('log-time'),
                label: timeLabel,
                onPressed: _pickTime,
                variant: FFButtonVariant.secondary,
                icon: Icons.schedule,
              ),
            ),
          ],
        ),
        if (_err('startedAt') case final e?)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingXs),
            child: Text(
              e,
              key: const Key('log-time-error'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: FFTokens.spacingMd),
        if (f.name) ...[
          _field(
            key: 'log-name',
            controller: _name,
            label: context.tr('logActivity.name'),
            hint: context.tr('logActivity.nameHint.${_type.wire}'),
            error: _err('name'),
          ),
          const SizedBox(height: FFTokens.spacingMd),
        ],
        _field(
          key: 'log-duration',
          controller: _duration,
          label: context.tr('logActivity.duration'),
          suffix: context.tr('activity.min'),
          error: _err('duration'),
          digits: true,
        ),
        if (f.distance) ...[
          const SizedBox(height: FFTokens.spacingMd),
          _field(
            key: 'log-distance',
            controller: _distance,
            label: context.tr('logActivity.distance'),
            suffix: 'km',
            error: _err('distance'),
            decimal: true,
          ),
        ],
        if (f.steps) ...[
          const SizedBox(height: FFTokens.spacingMd),
          _field(
            key: 'log-steps',
            controller: _steps,
            label: context.tr('logActivity.steps'),
            error: _err('steps'),
            digits: true,
          ),
        ],
        if (f.intensity) ...[
          const SizedBox(height: FFTokens.spacingMd),
          Text(
            context.tr('logActivity.intensity'),
            style: FFTokens.monoLabel(theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Wrap(
            spacing: FFTokens.spacingSm,
            children: [
              for (final i in ActivityIntensity.values)
                ChoiceChip(
                  key: Key('log-intensity-${i.wire}'),
                  label: Text(context.tr('logActivity.intensity.${i.wire}')),
                  selected: _intensity == i,
                  onSelected: (on) =>
                      setState(() => _intensity = on ? i : null),
                ),
            ],
          ),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        _field(
          key: 'log-notes',
          controller: _notes,
          label: context.tr('logActivity.notes'),
          error: _err('notes'),
          lines: 3,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Text(
          context.tr('logActivity.manualNote'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        FFActionTile(
          key: const Key('log-share'),
          icon: _shareChosen && _share == null
              ? Icons.lock_outline
              : Icons.people_outline,
          title: context.tr('audience.whoCanSee'),
          subtitle: _shareChosen
              ? shareLabel(context, _share)
              : context.tr('audience.useDefault'),
          onTap: () async {
            final r = await pickShare(context, initial: _share);
            if (!r.cancelled) {
              setState(() {
                _share = r.share;
                _shareChosen = true;
              });
            }
          },
        ),
        if (_submitError case final e?) ...[
          const SizedBox(height: FFTokens.spacingMd),
          FFCard(
            key: const Key('log-submit-error'),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: FFTokens.spacingSm),
                Expanded(child: Text(e, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
        ],
        const SizedBox(height: FFTokens.spacingLg),
        SizedBox(
          width: double.infinity,
          child: FFButton(
            key: const Key('log-save'),
            label: context.tr('logActivity.save'),
            onPressed: _saving ? null : _save,
            loading: _saving,
          ),
        ),
      ],
    );
  }

  Widget _field({
    required String key,
    required TextEditingController controller,
    required String label,
    String? hint,
    String? suffix,
    String? error,
    bool digits = false,
    bool decimal = false,
    int lines = 1,
  }) => FFTextField(
    key: Key(key),
    controller: controller,
    label: label,
    hint: hint,
    errorText: error,
    suffixText: suffix,
    keyboardType: digits
        ? TextInputType.number
        : decimal
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    maxLines: lines,
    inputFormatters: [
      if (digits) FilteringTextInputFormatter.digitsOnly,
      if (decimal) FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
    ],
  );
}

/// Opens Log activity, optionally with a type chosen, or for a gym visit
/// ([gymId] and the check-in time [at]).
void openLogActivity(
  BuildContext context, {
  ActivityType? type,
  String? gymId,
  DateTime? at,
}) {
  final query = {
    'type': ?type?.wire,
    'gymId': ?gymId,
    'at': ?at?.toUtc().toIso8601String(),
  };
  context.push(
    Uri(
      path: AppRoutes.memberActivityLog,
      queryParameters: query.isEmpty ? null : query,
    ).toString(),
  );
}
