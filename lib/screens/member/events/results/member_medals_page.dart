import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app_scope.dart';
import '../../../../router.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_medal.dart';
import '../../../../shared/events/event_result.dart';
import '../../../../shared/events/events_cache.dart';
import '../../../../shared/events/events_options.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../events_registration_gate.dart';
import 'results_widgets.dart';

/// Where "Report this image" goes (the FitFlex support mailbox).
const eventsSupportEmail = 'support@fitflexaf.co.tz';

enum _Phase { loading, ready, error }

/// `/member/events/medals` (events S6 spec §10.5): medals (the organizer's
/// own design with the built-in one as fallback) and achievements, with the
/// removed ones listed apart and in plain words.
class MemberMedalsPage extends StatefulWidget {
  const MemberMedalsPage({super.key, this.options});

  final EventsOptions? options;

  @override
  State<MemberMedalsPage> createState() => _MemberMedalsPageState();
}

class _MemberMedalsPageState extends State<MemberMedalsPage> {
  _Phase _phase = _Phase.loading;
  MedalsPayload _data = const MedalsPayload();
  DateTime? _savedAt;
  bool _offline = false;
  Object? _error;
  String _tab = 'medals';

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || !eventsRegistrationAllowed(context, _options)) return;
    if (!_options.results.rewards) {
      setState(() => _phase = _Phase.ready);
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _phase = _phase == _Phase.ready ? _phase : _Phase.loading;
      _error = null;
    });
    try {
      final json = await _api.myEventAchievements();
      if (!mounted) return;
      await EventsCache.putMine(memberCacheKey(context, 'medals'), json);
      if (!mounted) return;
      setState(() {
        _data = MedalsPayload.fromJson(json);
        _offline = false;
        _savedAt = null;
        _phase = _Phase.ready;
      });
    } catch (e) {
      if (!mounted) return;
      final cached = isNetworkError(e)
          ? await EventsCache.getFreshMine(memberCacheKey(context, 'medals'))
          : null;
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _data = MedalsPayload.fromJson(cached.$2);
          _offline = true;
          _savedAt = cached.$1;
          _phase = _Phase.ready;
        });
        return;
      }
      setState(() {
        _error = e;
        _phase = _Phase.error;
      });
    }
  }

  void _back() =>
      context.canPop() ? context.pop() : context.go(AppRoutes.memberEvents);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.medals.title')),
      ),
      body: switch (_phase) {
        _Phase.loading => FFSkeletonList(
          key: const Key('medals-loading'),
          semanticLabel: context.tr('events.medals.title'),
        ),
        _Phase.error => Center(
          child: FFErrorState(
            key: const Key('medals-error'),
            message: errorMessage(FFLocaleScope.of(context), _error!),
            retryLabel: context.tr('common.retry'),
            onRetry: _load,
          ),
        ),
        _ => _content(context),
      },
    );
  }

  Widget _content(BuildContext context) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    if (!_options.results.rewards) {
      return Padding(
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        child: FFEmptyState(
          key: const Key('medals-unavailable'),
          title: context.tr('events.unavailable.title'),
          body: context.tr('events.unavailable.body'),
        ),
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 840 ? 4 : 2;
    return ListView(
      key: const Key('medals-scroll'),
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_offline)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                    child: FFAlert(
                      key: const Key('medals-cached'),
                      tone: FFAlertTone.warning,
                      message: context
                          .tr('events.result.cached')
                          .replaceFirst(
                            '{time}',
                            formatDateTime(_savedAt, locale: lang),
                          ),
                    ),
                  ),
                FFActionTile(
                  key: const Key('medals-open-wallet'),
                  icon: Icons.card_giftcard,
                  title: context.tr('events.rewards.title'),
                  onTap: () => context.push(AppRoutes.memberEventRewards),
                ),
                const SizedBox(height: FFTokens.spacingSm),
                FFSegmented(
                  value: _tab,
                  options: [
                    ('medals', context.tr('events.medals.tab.medals')),
                    (
                      'achievements',
                      context.tr('events.medals.tab.achievements'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _tab = v),
                ),
                const SizedBox(height: FFTokens.spacingMd),
                if (_tab == 'medals')
                  ..._medals(context, lang, columns)
                else
                  ..._achievements(context, lang),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _medals(BuildContext context, String lang, int columns) {
    final awarded = _data.awarded;
    final removed = _data.revokedMedals;
    return [
      if (awarded.isEmpty && removed.isEmpty)
        FFEmptyState(
          key: const Key('medals-empty'),
          title: context.tr('events.medals.empty'),
          icon: Icons.emoji_events_outlined,
        )
      else
        _Grid(
          columns: columns,
          children: [for (final m in awarded) _MedalTile(award: m, lang: lang)],
        ),
      if (removed.isNotEmpty) ...[
        FFSectionTitle(context.tr('events.medals.removed')),
        _Grid(
          columns: columns,
          children: [
            for (final m in removed)
              _MedalTile(award: m, lang: lang, removed: true),
          ],
        ),
      ],
      Padding(
        padding: const EdgeInsets.only(top: FFTokens.spacingMd),
        child: Text(
          context.tr('events.medals.rule'),
          key: const Key('medals-rule'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ];
  }

  List<Widget> _achievements(BuildContext context, String lang) {
    final list = _data.achievements;
    if (list.isEmpty) {
      return [
        FFEmptyState(
          key: const Key('achievements-empty'),
          title: context.tr('events.achievements.empty'),
          icon: Icons.military_tech_outlined,
        ),
      ];
    }
    return [
      for (final a in list)
        FFCard(
          key: Key('achievement-${a.key}'),
          child: Row(
            children: [
              Icon(
                a.earned ? Icons.verified : Icons.radio_button_unchecked,
                color: a.earned
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title.of(lang),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (a.earned && a.earnedAt != null)
                      Text(
                        context
                            .tr('events.achievement.earnedOn')
                            .replaceFirst(
                              '{date}',
                              formatDate(a.earnedAt, locale: lang),
                            ),
                      )
                    else if (a.hasProgress)
                      Text(
                        context
                            .tr('events.achievement.progress')
                            .replaceFirst('{done}', '${a.done}')
                            .replaceFirst('{total}', '${a.total}'),
                        key: Key('achievement-progress-${a.key}'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      for (final r in _data.removed.where((r) => r.kind != 'medal'))
        FFCard(
          child: Text(
            '${r.title.of(lang)} · ${sentenceWithReason(context, plainKey: 'events.medals.removedNoReason', becauseKey: 'events.medals.removedWhy', reason: medalReasonWords(context, r.reasonCode))}',
          ),
        ),
    ];
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = FFTokens.spacingMd;
        final w = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: w, child: child),
          ],
        );
      },
    );
  }
}

class _MedalTile extends StatelessWidget {
  const _MedalTile({
    required this.award,
    required this.lang,
    this.removed = false,
  });

  final MedalAward award;
  final String lang;
  final bool removed;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final date = formatDate(
      removed ? award.revokedAt : award.awardedAt,
      locale: lang,
    );
    final label = medalSemanticsLabel(context, award, lang, dateText: date);
    return Semantics(
      button: true,
      label: label,
      hint: context.tr('events.medals.tapHint'),
      child: ExcludeSemantics(
        child: InkWell(
          key: Key('medal-${award.id}'),
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          onTap: () => showFFSheet<void>(
            context,
            title: award.name.of(lang),
            wideDialogWidth: 480,
            child: MedalDetail(award: award),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Column(
              children: [
                MedalBadge(art: award.art, size: 96, dimmed: removed),
                const SizedBox(height: FFTokens.spacingXs),
                Text(
                  award.name.of(lang),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: tt.titleSmall,
                ),
                Text(
                  [
                    award.eventTitle,
                    date,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: tt.bodySmall,
                ),
                if (removed)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      sentenceWithReason(
                        context,
                        plainKey: 'events.medals.removedNoReason',
                        becauseKey: 'events.medals.removedWhy',
                        reason: medalReasonWords(context, award.reasonCode),
                      ),
                      textAlign: TextAlign.center,
                      style: tt.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The detail sheet of one medal: the art large, why it was earned, who
/// designed it, "Report this image", and Share (a picture made on this phone).
class MedalDetail extends StatefulWidget {
  const MedalDetail({super.key, required this.award});

  final MedalAward award;

  @override
  State<MedalDetail> createState() => _MedalDetailState();
}

class _MedalDetailState extends State<MedalDetail> {
  final _cardKey = GlobalKey();
  bool _includeTime = false;
  bool _sharing = false;

  Future<void> _share() async {
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final a = widget.award;
    setState(() => _sharing = true);
    try {
      final png = await capturePng(_cardKey);
      if (png == null) return;
      await EventShareActions.shareImage(png, 'fitflex-medal-${a.id}.png');
    } catch (e) {
      snack.error(errorMessage(locale, e));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _report() async {
    final snack = FFSnack.of(context);
    final thanks = context.tr('events.medals.report.sent');
    final a = widget.award;
    // Spaces as %20 (a mail app shows "+" literally).
    String enc(String v) => Uri.encodeComponent(v);
    final uri = Uri(
      scheme: 'mailto',
      path: eventsSupportEmail,
      query:
          'subject=${enc('Medal image ${a.art.artId ?? ''}')}'
          '&body=${enc('Medal ${a.id}\nImage ${a.art.artId ?? ''}\n')}',
    );
    var opened = false;
    try {
      opened = await EventShareActions.openMail(uri);
      if (!opened) opened = await launchUrl(uri);
    } catch (_) {}
    if (opened) snack.success(thanks);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.award;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final tt = Theme.of(context).textTheme;
    final time = a.elapsedMs == null ? null : formatResultTime(a.elapsedMs!);
    final why = time == null
        ? a.description.of(lang)
        : context
              .tr('events.medals.why')
              .replaceFirst('{category}', a.categoryName ?? a.eventTitle)
              .replaceFirst('{time}', time)
              .replaceFirst(
                '{stage}',
                context.tr('events.result.stage.official'),
              );
    final eventLine = [
      a.eventTitle,
      if ((a.categoryName ?? '').isNotEmpty) a.categoryName!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Semantics(
                image: true,
                label: medalSemanticsLabel(
                  context,
                  a,
                  lang,
                  dateText: formatDate(
                    a.isRevoked ? a.revokedAt : a.awardedAt,
                    locale: lang,
                    fallback: '',
                  ),
                ),
                child: MedalBadge(
                  art: a.art,
                  size: 200,
                  variant: 'm512',
                  dimmed: a.isRevoked,
                ),
              ),
            ),
            const SizedBox(height: FFTokens.spacingMd),
            if (why.isNotEmpty)
              Text(why, key: const Key('medal-why'), style: tt.bodyLarge),
            if (eventLine.isNotEmpty) Text(eventLine, style: tt.bodyMedium),
            if (a.art.isCustom && (a.organizerName ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                child: Text(
                  context
                      .tr('events.medals.designBy')
                      .replaceFirst('{organizer}', a.organizerName!),
                  key: const Key('medal-design-by'),
                  style: tt.bodySmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                context.tr('events.medals.rule'),
                style: tt.bodySmall,
              ),
            ),
            if (a.art.isCustom)
              Align(
                alignment: Alignment.centerLeft,
                child: FFButton(
                  key: const Key('medal-report'),
                  label: context.tr('events.medals.report'),
                  variant: FFButtonVariant.ghost,
                  size: FFButtonSize.sm,
                  onPressed: _report,
                ),
              ),
            if (!a.isRevoked) ...[
              const SizedBox(height: FFTokens.spacingSm),
              // What will be shared, exactly as it will look.
              Center(
                child: RepaintBoundary(
                  key: _cardKey,
                  child: MedalShareCard(
                    art: a.art,
                    medalName: a.name.of(lang),
                    eventLine: eventLine,
                    timeText: _includeTime ? time : null,
                  ),
                ),
              ),
              if (time != null)
                SwitchListTile(
                  key: const Key('medal-include-time'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('events.medals.share.includeTime')),
                  value: _includeTime,
                  onChanged: (v) => setState(() => _includeTime = v),
                ),
              FFButton(
                key: const Key('medal-share'),
                label: context.tr('events.medals.share'),
                icon: Icons.ios_share,
                fullWidth: true,
                loading: _sharing,
                onPressed: _share,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
