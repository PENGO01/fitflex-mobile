import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app_scope.dart';
import '../../../../router.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/events/event_result.dart';
import '../../../../shared/events/events_cache.dart';
import '../../../../shared/events/events_loader.dart';
import '../../../../shared/events/events_options.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../events_registration_gate.dart';
import 'results_widgets.dart';

typedef _Query = ({String categoryId, String q});

/// `/member/events/:eventId/results` (events S6 spec §10.4): the signed-in
/// results board. Names are whatever each person chose to show (the server
/// shapes them; minors and hidden people are never in the list), the stage
/// banner says how official the board is, DNF/DQ rows show a word where the
/// time would be, and the member's own row is pinned at the top.
class EventResultsBoardPage extends StatefulWidget {
  const EventResultsBoardPage({
    super.key,
    required this.eventId,
    this.options,
    this.debounce = const Duration(milliseconds: 350),
  });

  final String eventId;
  final EventsOptions? options;
  final Duration debounce;

  @override
  State<EventResultsBoardPage> createState() => _EventResultsBoardPageState();
}

class _EventResultsBoardPageState extends State<EventResultsBoardPage> {
  ResultBoardPage? _first;
  final List<ResultBoardRow> _rows = [];
  String? _next;
  bool _loading = true;
  bool _moreBusy = false;
  bool _moreFailed = false;
  Object? _error;
  bool _offline = false;
  DateTime? _savedAt;
  String _category = '';
  String _q = '';
  late final EventsLoader<_Query, ResultBoardPage> _loader;
  final _search = TextEditingController();

  ApiClient get _api => AppScope.of(context).api;
  EventsOptions get _options => eventsOptionsOf(context, widget.options);

  String _cacheKey(_Query q) =>
      memberCacheKey(context, 'board.${widget.eventId}.${q.categoryId}.${q.q}');

  @override
  void initState() {
    super.initState();
    _loader = EventsLoader<_Query, ResultBoardPage>(
      debounce: widget.debounce,
      fetch: (q) async {
        final json = await _api.eventResultsBoard(
          widget.eventId,
          categoryId: q.categoryId,
          q: q.q,
        );
        // Only the unsearched first page is kept for offline use.
        if (q.q.isEmpty) await EventsCache.putMine(_cacheKey(q), json);
        return ResultBoardPage.fromJson(json);
      },
      onLoading: (l) {
        if (mounted && l) setState(() => _loading = true);
      },
      onResult: (q, page) {
        if (!mounted) return;
        setState(() {
          _first = page;
          _rows
            ..clear()
            ..addAll(page.items);
          _next = page.nextCursor;
          _loading = false;
          _error = null;
          _offline = false;
          _moreFailed = false;
          if (_category.isEmpty && page.categories.isNotEmpty) {
            // The server's default category (the first) when none chosen.
            _category = page.categories.first.id;
          }
        });
      },
      onError: (q, e) async {
        if (!mounted) return;
        final cached = isNetworkError(e) && q.q.isEmpty
            ? await EventsCache.getFreshMine(_cacheKey(q))
            : null;
        if (!mounted) return;
        if (cached != null) {
          final page = ResultBoardPage.fromJson(cached.$2);
          setState(() {
            _first = page;
            _rows
              ..clear()
              ..addAll(page.items);
            _next = page.nextCursor;
            _offline = true;
            _savedAt = cached.$1;
            _loading = false;
          });
          return;
        }
        setState(() {
          _error = e;
          _loading = false;
        });
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _loader.dispose();
    _search.dispose();
    super.dispose();
  }

  void _start() {
    if (!mounted || !eventsRegistrationAllowed(context, _options)) return;
    if (!_options.results.public) {
      setState(() => _loading = false);
      return;
    }
    _loader.request((categoryId: _category, q: _q), immediate: true);
  }

  Future<void> _loadMore() async {
    final cursor = _next;
    if (cursor == null || _moreBusy) return;
    setState(() {
      _moreBusy = true;
      _moreFailed = false;
    });
    try {
      final json = await _api.eventResultsBoard(
        widget.eventId,
        categoryId: _category,
        q: _q,
        cursor: cursor,
      );
      if (!mounted) return;
      final page = ResultBoardPage.fromJson(json);
      setState(() {
        _rows.addAll(page.items);
        _next = page.nextCursor;
        _moreBusy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _moreBusy = false;
          _moreFailed = true;
        });
      }
    }
  }

  void _back() => context.canPop()
      ? context.pop()
      : context.go(AppRoutes.memberEventDetailPath(widget.eventId));

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('events.board.title')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 720 : 640),
          child: _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (!_options.results.public) {
      return Padding(
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        child: FFEmptyState(
          key: const Key('board-unavailable'),
          title: context.tr('events.unavailable.title'),
          body: context.tr('events.unavailable.body'),
        ),
      );
    }
    final first = _first;
    if (_loading && first == null) {
      return FFSkeletonList(
        key: const Key('board-loading'),
        semanticLabel: context.tr('events.board.title'),
      );
    }
    if (_error != null && first == null) {
      final signedOut =
          _error is ApiException && (_error as ApiException).status == 401;
      return Center(
        child: signedOut
            ? FFEmptyState(
                key: const Key('board-signin'),
                title: context.tr('events.board.signin'),
              )
            : FFErrorState(
                key: const Key('board-error'),
                message: errorMessage(FFLocaleScope.of(context), _error!),
                retryLabel: context.tr('common.retry'),
                onRetry: _start,
              ),
      );
    }
    final page = first!;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final released = page.release.stage != ResultStage.none;
    final mineFirst = page.hasMine;
    return ListView(
      key: const Key('board-scroll'),
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      children: [
        if (page.eventTitle.isNotEmpty) FFPageHeader(title: page.eventTitle),
        if (_offline)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: FFAlert(
              key: const Key('board-cached'),
              tone: FFAlertTone.warning,
              message: context
                  .tr('events.result.cached')
                  .replaceFirst(
                    '{time}',
                    formatDateTime(_savedAt, locale: lang),
                  ),
            ),
          ),
        if (page.categories.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: FFSegmented(
              value: _category,
              options: [for (final c in page.categories) (c.id, c.name)],
              onChanged: (id) {
                setState(() {
                  _category = id;
                });
                _loader.request((categoryId: id, q: _q), immediate: true);
              },
            ),
          ),
        if (released)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FFBadge(
                key: const Key('board-banner'),
                label: context.tr(
                  page.release.stage == ResultStage.official
                      ? 'events.board.banner.official'
                      : 'events.board.banner.provisional',
                ),
                tone: page.release.stage == ResultStage.official
                    ? FFBadgeTone.success
                    : FFBadgeTone.warning,
                dot: true,
              ),
            ),
          ),
        FFTextField(
          key: const Key('board-search'),
          controller: _search,
          label: context.tr('events.board.search'),
          prefixIcon: const Icon(Icons.search),
          textInputAction: TextInputAction.search,
          onChanged: (v) {
            _q = v;
            _loader.request((categoryId: _category, q: v.trim()));
          },
        ),
        const SizedBox(height: FFTokens.spacingSm),
        if (!released || _rows.isEmpty && !mineFirst)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingMd),
            child: FFEmptyState(
              key: const Key('board-empty'),
              title: context.tr('events.board.empty'),
            ),
          )
        else ...[
          if (mineFirst)
            _BoardRow(
              key: const Key('board-mine'),
              mine: true,
              row: ResultBoardRow(
                rank: page.mineRank,
                bibNumber: page.mineBib ?? '',
                displayName: context.tr('events.board.you'),
              ),
              minePulledFrom: _rows,
            ),
          for (final r in _rows)
            _BoardRow(
              key: Key('board-row-${r.bibNumber}-${r.rank}'),
              row: r,
              mine: false,
            ),
          if (_next != null)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingSm),
              child: Column(
                children: [
                  if (_moreFailed)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: FFTokens.spacingXs,
                      ),
                      child: Text(context.tr('events.loadMoreFailed')),
                    ),
                  FFButton(
                    key: const Key('board-load-more'),
                    label: context.tr('events.loadMore'),
                    variant: FFButtonVariant.secondary,
                    loading: _moreBusy,
                    onPressed: _offline ? null : _loadMore,
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        Text(
          context.tr('events.board.names'),
          key: const Key('board-footer'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({
    super.key,
    required this.row,
    required this.mine,
    this.minePulledFrom,
  });

  final ResultBoardRow row;
  final bool mine;
  final List<ResultBoardRow>? minePulledFrom;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    // The pinned row borrows the time and status from the listed row with
    // the same bib, when that row is on the page.
    ResultBoardRow shown = row;
    if (mine) {
      for (final r in minePulledFrom ?? const <ResultBoardRow>[]) {
        if (r.bibNumber == row.bibNumber) {
          shown = ResultBoardRow(
            rank: r.rank ?? row.rank,
            bibNumber: row.bibNumber,
            displayName: row.displayName,
            elapsedMs: r.elapsedMs,
            finishStatus: r.finishStatus,
            stage: r.stage,
            badges: r.badges,
          );
          break;
        }
      }
    }
    // The server says "Runner" for a name that is not shown.
    final hidden =
        (shown.displayName ?? '').isEmpty ||
        shown.displayName!.trim().toLowerCase() == 'runner';
    final name = mine
        ? context.tr('events.board.you')
        : hidden
        ? context
              .tr('events.board.runner')
              .replaceFirst('{bib}', shown.bibNumber)
        : shown.displayName!;
    final statusWord = switch (shown.finishStatus) {
      'dnf' => context.tr('events.result.status.dnf'),
      'dns' => context.tr('events.result.status.dns'),
      'dq' => context.tr('events.result.status.dq'),
      _ => null,
    };
    final timeText = shown.hasTime ? formatResultTime(shown.elapsedMs!) : null;
    final spoken = shown.hasTime
        ? spokenResultTime(context, shown.elapsedMs!)
        : '';
    final rankText = shown.rank == null ? '–' : '${shown.rank}';
    final label = [
      if (shown.rank != null)
        context.tr('events.board.rank.a11y').replaceFirst('{rank}', rankText),
      context.tr('events.result.bib').replaceFirst('{number}', shown.bibNumber),
      name,
      ?statusWord,
      if (shown.hasTime) spoken,
      if (shown.corrected) context.tr('events.result.stage.corrected'),
      if (shown.underReview) context.tr('events.result.stage.underReview'),
    ].join(', ');
    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          margin: const EdgeInsets.only(bottom: FFTokens.spacingXs),
          padding: const EdgeInsets.symmetric(
            horizontal: FFTokens.spacingMd,
            vertical: FFTokens.spacingSm,
          ),
          decoration: BoxDecoration(
            color: mine ? cs.primaryContainer : cs.surface,
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(FFTokens.radiusMd),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  rankText,
                  style: tt.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: tt.titleSmall),
                    Text(
                      context
                          .tr('events.result.bib')
                          .replaceFirst('{number}', shown.bibNumber),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (shown.corrected || shown.underReview)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: FFBadge(
                          label: context.tr(
                            shown.underReview
                                ? 'events.result.stage.underReview'
                                : 'events.result.stage.corrected',
                          ),
                          tone: FFBadgeTone.warning,
                          wrap: true,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: FFTokens.spacingSm),
              Flexible(
                child: Text(
                  timeText ?? statusWord ?? '',
                  textAlign: TextAlign.end,
                  style: tt.titleSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
