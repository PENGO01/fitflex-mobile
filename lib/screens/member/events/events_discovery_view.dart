import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/events/event_filter.dart';
import '../../../shared/events/event_summary.dart';
import '../../../shared/events/events_analytics.dart';
import '../../../shared/events/events_cache.dart';
import '../../../shared/events/events_loader.dart';
import '../../../shared/events/events_options.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';
import 'event_card.dart';
import 'event_filters_sheet.dart';

/// Member event discovery (events S2 spec §11.2): search, filter chips, the
/// filter sheet, a result header with sort, and the card list with
/// pagination. Used inline in the Activity tab ([inline]: the parent
/// scrolls; the next page loads as its end comes near) and as the full
/// `/member/events` page (its own scroll view with pull-to-refresh).
class EventsDiscoveryView extends StatefulWidget {
  const EventsDiscoveryView({
    super.key,
    this.inline = false,
    this.options,
    this.now,
  });

  final bool inline;

  /// The server's options; read from [MemberDataScope] when absent.
  final EventsOptions? options;

  /// Injectable clock (date-range filters).
  final DateTime? now;

  /// Every list call carries this (§11.8).
  static const pageSize = 20;

  @override
  State<EventsDiscoveryView> createState() => _EventsDiscoveryViewState();
}

class _EventsDiscoveryViewState extends State<EventsDiscoveryView> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  ScrollPosition? _parentPosition;

  EventFilter _filter = EventFilter.none;
  List<EventSummary> _items = [];
  String? _nextCursor;
  int? _total;

  /// First page in flight (no items shown yet).
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  bool _moreFailed = false;
  bool _unavailable = false;

  /// The list on screen came from the cache after a network failure.
  DateTime? _cachedAt;

  /// Saved state the member changed on this screen (optimistic).
  final Map<String, bool> _saved = {};

  late final EventsLoader<EventFilter, Map<String, dynamic>> _loader =
      EventsLoader(
        fetch: (f) => _api.listEvents(
          f.toQuery(now: widget.now),
          limit: EventsDiscoveryView.pageSize,
        ),
        onResult: _onFirstPage,
        onError: _onFirstPageError,
      );

  ApiClient get _api => AppScope.of(context).api;

  /// Events S3 §4: the "My registrations" chip shows once the member has a
  /// registration or order (one cheap `GET /me/event-registrations?limit=1`,
  /// only with the server's `registration` option on).
  bool _hasMine = false;

  Future<void> _probeMine() async {
    if (!_options.registration) return;
    try {
      final page = await _api.listEventRegistrations(limit: 1);
      if (!mounted) return;
      final items = page['items'];
      setState(() => _hasMine = items is List && items.isNotEmpty);
    } catch (_) {
      // Chip stays hidden; Profile still has the row.
    }
  }

  EventsOptions get _options =>
      widget.options ??
      context
          .dependOnInheritedWidgetOfExactType<MemberDataScope>()
          ?.notifier
          ?.eventsOptions ??
      EventsOptions.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _request(immediate: true);
      _probeMine();
      if (widget.inline) {
        _parentPosition = Scrollable.maybeOf(context)?.position
          ?..addListener(_onParentScroll);
      }
    });
    _scrollCtrl.addListener(_onOwnScroll);
  }

  @override
  void dispose() {
    _parentPosition?.removeListener(_onParentScroll);
    _loader.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── loading ─────────────────────────────────────────────────────────────

  void _request({bool immediate = false}) {
    setState(() {
      _loading = true;
      _error = null;
      _moreFailed = false;
      _unavailable = false;
      // A new first page: the old cursor must not load "page 2" of it.
      _nextCursor = null;
      _loadingMore = false;
    });
    _loader.request(_filter, immediate: immediate);
  }

  List<EventSummary> _parse(Map<String, dynamic> page) => [
    for (final item in (page['items'] as List?) ?? const [])
      if (item is Map) EventSummary.fromJson(Map<String, dynamic>.from(item)),
  ];

  void _onFirstPage(EventFilter f, Map<String, dynamic> page) {
    if (!mounted) return;
    final items = _parse(page);
    setState(() {
      _loading = false;
      _cachedAt = null;
      _items = items;
      _nextCursor = page['nextCursor']?.toString();
      _total = page['total'] is num ? (page['total'] as num).toInt() : null;
    });
    if (f.signature.isEmpty) EventsCache.putList(page);
    EventsAnalytics.listViewed(
      filtersActive: f.activeCount,
      resultCount: _total ?? items.length,
    );
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
  }

  Future<void> _onFirstPageError(EventFilter f, Object e) async {
    if (!mounted) return;
    if (e is ApiException && e.status == 404 && e.code == 'feature_disabled') {
      setState(() {
        _loading = false;
        _unavailable = true;
      });
      return;
    }
    // Offline on the default list: show what we have (§11.8).
    if (isNetworkError(e) && f.signature.isEmpty) {
      final cached = await EventsCache.getList();
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _loading = false;
          _error = e;
          _cachedAt = cached.$1;
          _items = _parse(cached.$2);
          _nextCursor = null;
          _total = null;
        });
        return;
      }
    }
    setState(() {
      _loading = false;
      _error = e;
    });
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore || _loading) return;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    final f = _filter;
    try {
      final page = await _api.listEvents(
        f.toQuery(now: widget.now),
        cursor: cursor,
        limit: EventsDiscoveryView.pageSize,
      );
      if (!mounted || f != _filter) return;
      setState(() {
        _items = [..._items, ..._parse(page)];
        _nextCursor = page['nextCursor']?.toString();
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || f != _filter) return;
      setState(() {
        _loadingMore = false;
        _moreFailed = true;
      });
    }
  }

  void _maybeLoadMore(ScrollPosition p) {
    if (_nextCursor == null || _loadingMore || _moreFailed || _loading) return;
    // Only once the member has scrolled: while a page is being laid out the
    // metrics can briefly read as "at the end".
    if (!p.hasContentDimensions || p.pixels <= 0) return;
    if (p.extentAfter < 600) _loadMore();
  }

  void _onOwnScroll() => _maybeLoadMore(_scrollCtrl.position);

  void _onParentScroll() {
    final p = _parentPosition;
    if (p != null) _maybeLoadMore(p);
  }

  Future<void> _refresh() async {
    _request(immediate: true);
    // Give the loader a frame to report; pull-to-refresh only needs a short wait.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  // ── filters ─────────────────────────────────────────────────────────────

  void _apply(EventFilter f, {bool immediate = true}) {
    _filter = f;
    _request(immediate: immediate);
  }

  Future<void> _openSheet() async {
    final picked = await showEventFiltersSheet(
      context,
      initial: _filter,
      options: _options,
      resultCount: _total ?? (_nextCursor == null ? _items.length : null),
    );
    if (picked == null || !mounted) return;
    _apply(picked);
  }

  void _clearAll() {
    _searchCtrl.clear();
    _apply(EventFilter.none);
  }

  // ── favourites ──────────────────────────────────────────────────────────

  bool _isSaved(EventSummary e) => _saved[e.id] ?? e.isSaved ?? false;

  Future<void> _toggleSave(EventSummary e) async {
    final next = !_isSaved(e);
    setState(() => _saved[e.id] = next);
    EventsAnalytics.saved(eventId: e.id, saved: next);
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    try {
      if (next) {
        await _api.saveEvent(e.id);
      } else {
        await _api.unsaveEvent(e.id);
      }
    } catch (err) {
      if (!mounted) return;
      setState(() => _saved[e.id] = !next);
      snack.error(errorMessage(locale, err));
    }
  }

  void _open(EventSummary e) =>
      context.push('${AppRoutes.memberEvents}/${e.id}');

  // ── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final options = _options;
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final columns = wide ? 2 : 1;
    final header = _header(context, options);
    final body = _body(context, columns);

    if (widget.inline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, ...body],
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        key: const Key('events-scroll'),
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, ...body],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, EventsOptions options) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final count = _filter.activeCount;
    final filtersLabel = count == 0
        ? context.tr('events.chip.filters')
        : context.tr('events.chip.filtersCount').replaceFirst('{n}', '$count');

    FFFilterChip distanceChip(String bucket) => FFFilterChip(
      key: Key('events-chip-$bucket'),
      label: bucket.toUpperCase(),
      selected: _filter.distances.contains(bucket),
      onSelected: () => _apply(
        _filter.copyWith(
          distances: _filter.distances.contains(bucket)
              ? ({..._filter.distances}..remove(bucket))
              : {..._filter.distances, bucket},
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFTextField(
          key: const Key('events-search'),
          controller: _searchCtrl,
          hint: context.tr('events.search.hint'),
          semanticsLabel: context.tr('a11y.search'),
          prefixIcon: const Icon(Icons.search, size: 20),
          textInputAction: TextInputAction.search,
          suffixIcon: _filter.q.isEmpty
              ? null
              : IconButton(
                  key: const Key('events-search-clear'),
                  tooltip: context.tr('a11y.clear'),
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    _apply(_filter.copyWith(q: ''));
                  },
                ),
          onChanged: (v) => _apply(_filter.copyWith(q: v), immediate: false),
        ),
        const SizedBox(height: FFTokens.spacingXs),
        SingleChildScrollView(
          key: const Key('events-chip-scroll'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              FFFilterChip(
                key: const Key('events-chip-open'),
                label: context.tr('events.chip.open'),
                selected: _filter.openOnly,
                onSelected: () =>
                    _apply(_filter.copyWith(openOnly: !_filter.openOnly)),
              ),
              const SizedBox(width: FFTokens.spacingSm),
              FFFilterChip(
                key: const Key('events-chip-thisMonth'),
                label: context.tr('events.chip.thisMonth'),
                selected: _filter.dateRange == EventDateRange.thisMonth,
                onSelected: () => _apply(
                  _filter.copyWith(
                    dateRange: _filter.dateRange == EventDateRange.thisMonth
                        ? EventDateRange.anytime
                        : EventDateRange.thisMonth,
                    clearDates: true,
                  ),
                ),
              ),
              for (final b in const ['5k', '10k', '21k', '42k']) ...[
                const SizedBox(width: FFTokens.spacingSm),
                distanceChip(b),
              ],
              if (options.favourites) ...[
                const SizedBox(width: FFTokens.spacingSm),
                FFFilterChip(
                  key: const Key('events-chip-saved'),
                  label: context.tr('events.chip.saved'),
                  selected: _filter.savedOnly,
                  onSelected: () =>
                      _apply(_filter.copyWith(savedOnly: !_filter.savedOnly)),
                ),
              ],
              const SizedBox(width: FFTokens.spacingSm),
              FFFilterChip(
                key: const Key('events-chip-filters'),
                label: filtersLabel,
                icon: Icons.tune,
                selected: count > 0,
                onSelected: _openSheet,
              ),
              if (options.results.enabled) ...[
                const SizedBox(width: FFTokens.spacingSm),
                FFFilterChip(
                  key: const Key('events-chip-results'),
                  label: context.tr('events.result.entry.myResults'),
                  icon: Icons.emoji_events_outlined,
                  selected: false,
                  onSelected: () =>
                      context.push(AppRoutes.memberEventMyResults),
                ),
              ],
              if (options.results.rewards) ...[
                const SizedBox(width: FFTokens.spacingSm),
                FFFilterChip(
                  key: const Key('events-chip-medals'),
                  label: context.tr('events.rewards.entry'),
                  icon: Icons.military_tech_outlined,
                  selected: false,
                  onSelected: () => context.push(AppRoutes.memberEventMedals),
                ),
              ],
              if (options.registration && _hasMine) ...[
                const SizedBox(width: FFTokens.spacingSm),
                FFFilterChip(
                  key: const Key('events-chip-mine'),
                  label: context.tr('events.mine.title'),
                  icon: Icons.confirmation_number_outlined,
                  selected: false,
                  onSelected: () => context.push(AppRoutes.memberEventOrders),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _loading || _unavailable
                      ? ''
                      : context
                            .tr('events.results.count')
                            .replaceFirst('{n}', '${_total ?? _items.length}'),
                  key: const Key('events-result-count'),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
            FFDropdownField<EventSort>(
              key: const Key('events-sort'),
              value: _filter.sort,
              width: 180,
              isExpanded: true,
              label: context.tr('events.sort'),
              items: [
                for (final (s, key) in const [
                  (EventSort.soonest, 'events.sort.soonest'),
                  (EventSort.priceLow, 'events.sort.priceLow'),
                  (EventSort.newest, 'events.sort.newest'),
                ])
                  DropdownMenuItem(value: s, child: Text(context.tr(key))),
              ],
              onChanged: (s) {
                if (s != null) _apply(_filter.copyWith(sort: s));
              },
            ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingSm),
      ],
    );
  }

  List<Widget> _body(BuildContext context, int columns) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    if (_unavailable) {
      return [
        FFEmptyState(
          key: const Key('events-unavailable'),
          icon: Icons.flag_outlined,
          title: context.tr('events.unavailable.title'),
          body: context.tr('events.unavailable.body'),
        ),
      ];
    }
    if (_loading) {
      return [
        FFSkeletonList(
          key: const Key('events-loading'),
          count: 3,
          semanticLabel: context.tr('common.loading'),
        ),
      ];
    }
    final error = _error;
    if (error != null && _cachedAt == null) {
      final offline = isNetworkError(error);
      return [
        FFErrorState(
          key: const Key('events-error'),
          icon: offline ? Icons.wifi_off : Icons.error_outline,
          title: offline ? context.tr('error.offlineTitle') : null,
          message: offline
              ? context.tr('events.offline.body')
              : errorMessage(FFLocaleScope.of(context), error),
          retryLabel: context.tr('common.retry'),
          onRetry: () => _request(immediate: true),
        ),
      ];
    }
    if (_items.isEmpty) {
      if (_filter.isNarrowing) {
        return [
          FFEmptyState(
            key: const Key('events-empty-filtered'),
            icon: Icons.event_busy_outlined,
            title: context.tr('events.empty.filtered.title'),
            body: context.tr('events.empty.filtered.body'),
            action: FFButton(
              key: const Key('events-clear-filters'),
              label: context.tr('events.empty.filtered.action'),
              variant: FFButtonVariant.ghost,
              onPressed: _clearAll,
            ),
          ),
        ];
      }
      return [
        FFEmptyState(
          key: const Key('events-empty'),
          icon: Icons.event_outlined,
          title: context.tr('events.empty.title'),
          body: context.tr('events.empty.body'),
        ),
      ];
    }

    final cards = [
      for (final e in _items)
        EventCard(
          key: Key('event-card-wrap-${e.id}'),
          event: e,
          onTap: () => _open(e),
          saved: _options.favourites ? _isSaved(e) : null,
          onToggleSave: _options.favourites ? () => _toggleSave(e) : null,
        ),
    ];
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += columns) {
      final slice = cards.sublist(
        i,
        i + columns > cards.length ? cards.length : i + columns,
      );
      rows.add(
        columns == 1
            ? slice.single
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = 0; j < columns; j++) ...[
                    if (j > 0) const SizedBox(width: FFTokens.spacingMd),
                    Expanded(
                      child: j < slice.length ? slice[j] : const SizedBox(),
                    ),
                  ],
                ],
              ),
      );
    }

    return [
      if (_cachedAt != null)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            key: const Key('events-offline-cached'),
            tone: FFAlertTone.warning,
            message:
                '${context.tr('error.offlineTitle')}. '
                '${context.tr('events.offline.savedCopy').replaceFirst('{time}', formatDateTime(_cachedAt, locale: lang))}',
          ),
        ),
      ...rows,
      if (_loadingMore)
        Padding(
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          child: Center(
            child: Semantics(
              label: context.tr('events.loadingMore'),
              child: const FFSpinner(key: Key('events-loading-more')),
            ),
          ),
        )
      else if (_moreFailed)
        Padding(
          padding: const EdgeInsets.all(FFTokens.spacingSm),
          child: Column(
            children: [
              Text(
                context.tr('events.loadMoreFailed'),
                key: const Key('events-more-failed'),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFButton(
                key: const Key('events-load-more'),
                label: context.tr('events.loadMore'),
                variant: FFButtonVariant.secondary,
                onPressed: _loadMore,
              ),
            ],
          ),
        )
      else if (_nextCursor != null && widget.inline)
        // Inline, the parent's scroll also loads the next page; the button
        // is for keyboards and switches.
        Padding(
          padding: const EdgeInsets.all(FFTokens.spacingSm),
          child: FFButton(
            key: const Key('events-load-more'),
            label: context.tr('events.loadMore'),
            variant: FFButtonVariant.ghost,
            onPressed: _loadMore,
          ),
        ),
    ];
  }
}
