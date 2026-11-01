import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app_scope.dart';
import '../../../../router.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_result.dart';
import '../../../../shared/events/events_cache.dart';
import '../../../../shared/events/events_options.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../../../../shared/shop_checkout.dart';
import '../events_registration_gate.dart';
import 'results_widgets.dart';
import 'run_card.dart';

/// Two columns from here (Flutter web desktop; spec §10.3).
const double _wideAt = 840;

enum _Phase { loading, ready, error }

const _disputeReasons = [
  'time_wrong',
  'not_my_result',
  'wrong_category',
  'dq_challenge',
  'other',
];

/// `/member/events/registrations/:registrationId/result` (events S6 spec
/// §10.3): the participant's result, how official it is (the server's own
/// `stage`; the app never works it out), what it earned, and the controls
/// that belong to it (ask a question, who can see my name, the FitFlex run).
class MemberEventResultPage extends StatefulWidget {
  const MemberEventResultPage({
    super.key,
    required this.registrationId,
    this.options,
  });

  final String registrationId;
  final EventsOptions? options;

  @override
  State<MemberEventResultPage> createState() => _MemberEventResultPageState();
}

class _MemberEventResultPageState extends State<MemberEventResultPage> {
  _Phase _phase = _Phase.loading;
  MemberEventResult? _data;
  DateTime? _savedAt;
  bool _offline = false;
  Object? _error;
  bool _busy = false;
  bool _asked = false;
  final _heading = FocusNode(debugLabel: 'result-heading');

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);
  String get _cacheKey =>
      memberCacheKey(context, 'result.${widget.registrationId}');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _heading.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!mounted || !eventsRegistrationAllowed(context, _options)) return;
    if (!_options.results.enabled) {
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
      await EventsCache.putMine(_cacheKey, json);
      if (!mounted) return;
      setState(() {
        _data = MemberEventResult.fromJson(
          json,
          registrationId: widget.registrationId,
        );
        _savedAt = null;
        _offline = false;
        _phase = _Phase.ready;
      });
      _announce();
      _maybeAsk();
    } catch (e) {
      if (!mounted) return;
      final cached = isNetworkError(e)
          ? await EventsCache.getFreshMine(_cacheKey)
          : null;
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _data = MemberEventResult.fromJson(
            cached.$2,
            registrationId: widget.registrationId,
          );
          _savedAt = cached.$1;
          _offline = true;
          _phase = _Phase.ready;
        });
        return;
      }
      setState(() {
        _error = e;
        _phase = _data == null ? _Phase.error : _phase;
      });
    }
  }

  void _announce() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _heading.requestFocus();
  });

  // ── Who can see my name: asked once, then at most once a week ───────────

  Future<void> _maybeAsk() async {
    final d = _data;
    if (_asked || d == null || !d.visibility.shouldAsk) return;
    _asked = true;
    final prefs = await SharedPreferences.getInstance();
    final key = 'events.result.asked.${widget.registrationId}';
    final last = prefs.getInt(key) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < const Duration(days: 7).inMilliseconds) return;
    await prefs.setInt(key, now);
    if (!mounted) return;
    await _visibilitySheet(ask: true);
  }

  Future<void> _visibilitySheet({bool ask = false}) async {
    final d = _data;
    if (d == null) return;
    final picked = await showFFSheet<String>(
      context,
      title: context.tr(
        ask ? 'events.result.visibility.ask' : 'events.result.visibility.title',
      ),
      wideDialogWidth: 480,
      child: _VisibilitySheet(visibility: d.visibility, ask: ask),
    );
    if (picked == null || !mounted || picked == d.visibility.current) return;
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    setState(() => _busy = true);
    try {
      await _api.setEventResultsVisibility(widget.registrationId, picked);
      if (!mounted) return;
      await _load();
    } catch (e) {
      snack.error(errorMessage(locale, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disputeSheet() async {
    final done = await showFFSheet<bool>(
      context,
      title: context.tr('events.result.dispute.title'),
      wideDialogWidth: 480,
      child: _DisputeSheet(registrationId: widget.registrationId, api: _api),
    );
    if (done == true && mounted) await _load();
  }

  Future<void> _withdrawDispute(ResultDispute dispute) async {
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    setState(() => _busy = true);
    try {
      await _api.withdrawEventResultDispute(widget.registrationId, dispute.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      snack.error(errorMessage(locale, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  void _back() => context.canPop()
      ? context.pop()
      : context.go(
          AppRoutes.memberEventRegistrationPath(widget.registrationId),
        );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.result.title')),
      ),
      body: switch (_phase) {
        _Phase.loading => FFSkeletonList(
          key: const Key('result-loading'),
          semanticLabel: context.tr('events.result.title'),
        ),
        _Phase.error => Center(
          child: FFErrorState(
            key: const Key('result-error'),
            message: _error == null
                ? null
                : errorMessage(FFLocaleScope.of(context), _error!),
            retryLabel: context.tr('common.retry'),
            onRetry: _load,
          ),
        ),
        _ => _content(context),
      },
    );
  }

  Widget _content(BuildContext context) {
    final d = _data;
    final List<Widget> children;
    if (!_options.results.enabled || d == null) {
      children = [
        FFEmptyState(
          key: const Key('result-unavailable'),
          title: context.tr('events.unavailable.title'),
          body: context.tr('events.unavailable.body'),
        ),
      ];
    } else {
      children = _ready(context, d);
    }
    final wide = MediaQuery.sizeOf(context).width >= _wideAt;
    return ListView(
      key: const Key('result-scroll'),
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 960 : 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _ready(BuildContext context, MemberEventResult d) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final header = <Widget>[
      Focus(
        focusNode: _heading,
        child: FFPageHeader(
          title: d.eventTitle.isEmpty
              ? context.tr('events.result.title')
              : d.eventTitle,
          description: d.categoryName.isEmpty ? null : d.categoryName,
        ),
      ),
      if (_offline)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: const Key('result-cached'),
            tone: FFAlertTone.warning,
            message: context
                .tr('events.result.cached')
                .replaceFirst('{time}', formatDateTime(_savedAt, locale: lang)),
          ),
        ),
    ];

    if (d.placeEnded || d.eventCancelled) {
      return [
        ...header,
        FFEmptyState(
          key: const Key('result-ended'),
          title: context.tr(
            d.eventCancelled
                ? 'events.availability.cancelled'
                : 'events.result.cancelled',
          ),
          body: d.eventCancelled ? null : context.tr('events.result.cancelled'),
        ),
      ];
    }
    if (d.claimNeeded) {
      return [
        ...header,
        FFCard(
          key: const Key('result-claim'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('events.result.claimFirst')),
              FFButton(
                label: context.tr('events.claim.title'),
                variant: FFButtonVariant.secondary,
                onPressed: () => context.push(
                  AppRoutes.memberEventClaimPath(widget.registrationId),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    if (d.statusOnly) {
      // The purchaser of someone else's place: the stage word only.
      return [
        ...header,
        Align(
          alignment: Alignment.centerLeft,
          child: ResultStageChip(stage: d.stage),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFAlert(
          key: const Key('result-purchaser'),
          message: context.tr('events.result.purchaser'),
        ),
      ];
    }

    final resultCard = <Widget>[
      _resultCard(context, d),
      _meaning(context, d),
      ..._disputeRow(context, d),
    ];
    final rest = <Widget>[
      ..._runSection(context, d),
      ..._medalSection(context, d),
      ..._rewardSection(context, d),
      ..._visibilityRow(context, d),
      if (_options.results.public && d.release.stage != ResultStage.none)
        Align(
          alignment: Alignment.centerLeft,
          child: FFButton(
            key: const Key('result-open-board'),
            label: context.tr('events.board.title'),
            variant: FFButtonVariant.secondary,
            icon: Icons.format_list_numbered,
            onPressed: () =>
                context.push(AppRoutes.memberEventResultsPath(d.eventId)),
          ),
        ),
    ];
    final wide = MediaQuery.sizeOf(context).width >= _wideAt;
    if (!wide) return [...header, ...resultCard, ...rest];
    return [
      ...header,
      Row(
        key: const Key('result-columns'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: resultCard,
            ),
          ),
          const SizedBox(width: FFTokens.spacingLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rest,
            ),
          ),
        ],
      ),
    ];
  }

  // ── Result card ──────────────────────────────────────────────────────────

  Widget _resultCard(BuildContext context, MemberEventResult d) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final r = d.result;
    final ms = r?.shownMs;
    final noResult = r == null;
    final ranked =
        r != null &&
        r.categoryRank != null &&
        (d.stage == ResultStage.official || d.stage == ResultStage.corrected);
    final sourceKey = r == null || r.sourceType.isEmpty
        ? null
        : 'events.result.source.${r.sourceType}';
    final sourceText =
        r?.sourceLabel ?? (sourceKey == null ? null : context.tr(sourceKey));
    return FFCard(
      key: const Key('result-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            container: true,
            child: ResultStageChip(stage: d.stage),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          if (ms != null) ...[
            Semantics(
              container: true,
              label:
                  '${context.tr('events.result.time')} '
                  '${spokenResultTime(context, ms)}',
              child: ExcludeSemantics(
                child: Text(
                  formatResultTime(ms),
                  key: const Key('result-time'),
                  style: tt.displayMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            Text(
              context.tr('events.result.time'),
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ] else if (r != null && (r.isDnf || r.isDns || r.isDq)) ...[
            Text(
              context.tr(
                r.isDnf
                    ? 'events.result.status.dnf'
                    : r.isDns
                    ? 'events.result.status.dns'
                    : 'events.result.status.dq',
              ),
              key: const Key('result-status-word'),
              style: tt.headlineSmall,
            ),
          ] else if (noResult) ...[
            Text(
              context.tr('events.result.noneYet'),
              key: const Key('result-none-yet'),
              style: tt.titleMedium,
            ),
          ],
          if (sourceText != null && ms != null)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                sourceText,
                key: const Key('result-source'),
                style: tt.bodyMedium,
              ),
            ),
          if (ranked)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                context
                    .tr('events.result.rank')
                    .replaceFirst('{rank}', '${r.categoryRank}')
                    .replaceFirst(
                      '{total}',
                      '${r.finishersInCategory ?? r.categoryRank}',
                    )
                    .replaceFirst('{category}', d.categoryName),
                key: const Key('result-rank'),
                style: tt.bodyLarge,
              ),
            ),
          if ((d.bibNumber ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                context
                    .tr('events.result.bib')
                    .replaceFirst('{number}', d.bibNumber!),
                key: const Key('result-bib'),
                style: tt.bodyMedium,
              ),
            ),
          if (r != null && r.isPersonalBest)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingSm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FFBadge(
                  key: const Key('result-pb'),
                  label: context.tr('events.result.pb'),
                  tone: FFBadgeTone.fuel,
                  wrap: true,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _meaning(BuildContext context, MemberEventResult d) {
    final tt = Theme.of(context).textTheme;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final r = d.result;
    var key = d.stage.lineKey;
    if (r != null && r.isDnf) key = 'events.result.line.dnf';
    if (r != null && r.isDns) key = 'events.result.line.dns';
    if (d.stage == ResultStage.none &&
        r == null &&
        d.release.stage != ResultStage.none) {
      key = 'events.result.empty.noneForYou';
    }
    final reason = resultReasonWords(context, r?.reasonCode);
    // Only the sentences that can carry a reason take the "because" clause;
    // with no reason the sentence is complete without it.
    final text = switch (key) {
      'events.result.line.dq' ||
      'events.result.line.rejected' => sentenceWithReason(
        context,
        plainKey: key,
        becauseKey: '$key.because',
        reason: reason,
      ),
      _ =>
        context
            .tr(key)
            .replaceFirst(
              '{date}',
              formatDate(r?.correctedAt, locale: lang, fallback: ''),
            )
            .trim(),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, key: const Key('result-meaning'), style: tt.bodyMedium),
          if (d.isVirtual && r != null && r.isGps)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                context.tr('events.result.line.virtual'),
                key: const Key('result-virtual-note'),
                style: tt.bodySmall,
              ),
            ),
          if ((r?.correctionNote ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                '${context.tr('events.result.note')}: ${r!.correctionNote}',
                key: const Key('result-note'),
                style: tt.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _disputeRow(BuildContext context, MemberEventResult d) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final dp = d.dispute;
    if (dp == null || dp.isEmpty) return const [];
    if (dp.isOpen) {
      return [
        FFCard(
          key: const Key('result-dispute-open'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context
                    .tr('events.result.dispute.open')
                    .replaceFirst(
                      '{date}',
                      formatDate(dp.createdAt, locale: lang),
                    ),
              ),
              FFButton(
                key: const Key('result-dispute-withdraw'),
                label: context.tr('events.result.dispute.withdraw'),
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
                loading: _busy,
                onPressed: () => _withdrawDispute(dp),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      if (dp.isClosed)
        FFCard(
          key: const Key('result-dispute-closed'),
          child: Text(
            context
                .tr('events.result.dispute.closed')
                .replaceFirst(
                  '{date}',
                  formatDate(dp.resolvedAt ?? dp.createdAt, locale: lang),
                )
                .replaceFirst(
                  '{outcome}',
                  [
                    context.tr('events.result.dispute.status.${dp.status}'),
                    if ((dp.resolutionNote ?? '').isNotEmpty)
                      dp.resolutionNote!,
                  ].join('. '),
                ),
          ),
        ),
      if (dp.canRaise)
        FFActionTile(
          key: const Key('result-dispute-ask'),
          icon: Icons.help_outline,
          title: context.tr('events.result.dispute.ask'),
          subtitle: dp.windowEndsAt == null
              ? null
              : context
                    .tr('events.result.dispute.window')
                    .replaceFirst(
                      '{date}',
                      formatDate(dp.windowEndsAt, locale: lang),
                    ),
          onTap: _offline ? null : _disputeSheet,
        )
      else if (dp.windowEndsAt != null && !dp.isOpen && dp.id.isEmpty)
        Text(
          context.tr('events.result.dispute.closedWindow'),
          key: const Key('result-dispute-window-closed'),
        ),
    ];
  }

  // ── Your FitFlex run ─────────────────────────────────────────────────────

  List<Widget> _runSection(BuildContext context, MemberEventResult d) {
    if (!_options.results.runs && d.runLinks.isEmpty) return const [];
    final official =
        d.stage == ResultStage.official || d.stage == ResultStage.corrected
        ? d.result?.shownMs
        : null;
    return [
      FFSectionTitle(context.tr('events.run.section')),
      for (final l in d.runLinks)
        EventRunCard(
          link: l,
          officialMs: official,
          busy: _busy,
          onUnlink: _offline ? null : () => _unlink(l),
        ),
      if (d.runLinks.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: Text(
            context.tr('events.run.empty'),
            key: const Key('result-runs-empty'),
          ),
        ),
      if (_options.results.runs)
        Align(
          alignment: Alignment.centerLeft,
          child: FFButton(
            key: const Key('result-open-runs'),
            label: context.tr('events.run.add'),
            variant: FFButtonVariant.secondary,
            icon: Icons.add,
            onPressed: () => context.push(
              AppRoutes.memberEventRunsPath(widget.registrationId),
            ),
          ),
        ),
    ];
  }

  List<Widget> _medalSection(BuildContext context, MemberEventResult d) {
    final earned = d.medals.where((m) => !m.isRevoked).toList();
    if (earned.isEmpty) return const [];
    final lang = FFLocaleScope.of(context).locale.languageCode;
    return [
      FFSectionTitle(context.tr('events.medals.tab.medals')),
      Wrap(
        key: const Key('result-medals'),
        spacing: FFTokens.spacingMd,
        runSpacing: FFTokens.spacingMd,
        children: [
          for (final m in earned)
            Semantics(
              button: true,
              label: medalSemanticsLabel(
                context,
                m,
                lang,
                dateText: formatDate(m.awardedAt, locale: lang, fallback: ''),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                onTap: () => context.push(AppRoutes.memberEventMedals),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                    maxWidth: 96,
                  ),
                  child: Column(
                    children: [
                      MedalBadge(art: m.art, size: 80),
                      Text(
                        m.name.of(lang),
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: FFTokens.spacingSm),
    ];
  }

  List<Widget> _rewardSection(BuildContext context, MemberEventResult d) {
    if (d.rewardsEarned.isEmpty) return const [];
    final lang = FFLocaleScope.of(context).locale.languageCode;
    return [
      FFSectionTitle(context.tr('events.rewards.title')),
      for (final r in d.rewardsEarned)
        FFActionTile(
          key: Key('result-reward-${r.definitionId}'),
          icon: Icons.card_giftcard,
          title: r.title.of(lang),
          onTap: () => context.push(AppRoutes.memberEventRewards),
        ),
    ];
  }

  List<Widget> _visibilityRow(BuildContext context, MemberEventResult d) {
    final v = d.visibility;
    return [
      FFActionTile(
        key: const Key('result-visibility'),
        icon: Icons.visibility_outlined,
        title: context.tr('events.result.visibility.title'),
        subtitle: v.isMinor
            ? context.tr('events.result.visibility.minor')
            : context.tr('events.result.visibility.${_known(v.current)}'),
        onTap: v.canChange && !v.isMinor && !_offline
            ? () => _visibilitySheet()
            : null,
      ),
    ];
  }
}

String _known(String v) =>
    const {'standard', 'bib_only', 'hidden'}.contains(v) ? v : 'bib_only';

// ── Sheets ─────────────────────────────────────────────────────────────────

class _VisibilitySheet extends StatefulWidget {
  const _VisibilitySheet({required this.visibility, required this.ask});

  final ResultVisibility visibility;
  final bool ask;

  @override
  State<_VisibilitySheet> createState() => _VisibilitySheetState();
}

class _VisibilitySheetState extends State<_VisibilitySheet> {
  late String _picked = _known(widget.visibility.current);

  @override
  Widget build(BuildContext context) {
    final options = widget.ask
        ? const ['standard', 'bib_only']
        : [
            for (final a in const ['standard', 'bib_only', 'hidden'])
              if (widget.visibility.allowed.contains(a)) a,
          ];
    return Padding(
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.ask)
              Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
                child: Text(context.tr('events.result.visibility.askBody')),
              ),
            for (final o in options)
              Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                child: FFChoiceTile(
                  key: Key('visibility-$o'),
                  title: context.tr('events.result.visibility.$o'),
                  selected: _picked == o,
                  onSelected: () => setState(() => _picked = o),
                ),
              ),
            FFButton(
              key: const Key('visibility-save'),
              label: context.tr('common.save'),
              fullWidth: true,
              onPressed: () => Navigator.of(context).pop(_picked),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisputeSheet extends StatefulWidget {
  const _DisputeSheet({required this.registrationId, required this.api});

  final String registrationId;
  final ApiClient api;

  @override
  State<_DisputeSheet> createState() => _DisputeSheetState();
}

class _DisputeSheetState extends State<_DisputeSheet> {
  String? _reason;
  final _note = TextEditingController();
  bool _sending = false;
  String? _error;

  // One key for this sheet: a tap that is repeated or retried is the same
  // question, not two.
  final String _key = newCheckoutKey();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final locale = FFLocaleScope.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.api.raiseEventResultDispute(
        widget.registrationId,
        reasonCode: _reason!,
        note: _note.text,
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
    return Padding(
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final r in _disputeReasons)
              Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                child: FFChoiceTile(
                  key: Key('dispute-reason-$r'),
                  title: context.tr('events.result.dispute.reason.$r'),
                  selected: _reason == r,
                  onSelected: () => setState(() => _reason = r),
                ),
              ),
            FFTextField(
              key: const Key('dispute-note'),
              controller: _note,
              label: context.tr('events.result.dispute.note'),
              maxLines: 3,
              maxLength: 500,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                child: FFAlert(
                  key: const Key('dispute-error'),
                  tone: FFAlertTone.error,
                  message: _error!,
                ),
              ),
            FFButton(
              key: const Key('dispute-send'),
              label: context.tr('events.result.dispute.send'),
              fullWidth: true,
              loading: _sending,
              onPressed: _reason == null || _sending ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}
