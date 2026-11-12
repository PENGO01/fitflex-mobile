import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/discovery_loader.dart';
import '../../shared/promotion_events.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../../shared/photo_footer_flag.dart';
import '../../shared/photo_hero_flag.dart';
import '../../shared/promotion.dart';
import 'member_shell.dart';
import 'widgets/directory_states.dart';
import 'widgets/trainer_card.dart';

/// PHOTO_HERO_UI (owner 2026-10-22, bands "too dark"): the band grows for
/// [FFTokens.heroBandClearPhoto] of clear photo above its text, but no taller
/// than this on a 390x844 screen, so search (16px under it) starts
/// above 55% of the screen
/// (FFHeroBand.maxHeightAt844).
const double trainersBandMaxHeight = 321;

class MemberTrainersTab extends StatefulWidget {
  const MemberTrainersTab({super.key});

  @override
  State<MemberTrainersTab> createState() => _MemberTrainersTabState();
}

class _MemberTrainersTabState extends State<MemberTrainersTab> {
  final TextEditingController _searchCtrl = TextEditingController();

  /// The band's heading: the footer's Back to top moves focus here.
  final FocusNode _heroFocus = FocusNode(debugLabel: 'trainers-hero-heading');
  String _search = '';
  String _filter = 'all';

  /// The server's ranked answer for the current search and specialty: a
  /// Featured section and the results below it. Null until it arrives, or if
  /// the server cannot be reached, in which case the plain list is filtered on
  /// the phone as before.
  DiscoverResult<TrainerProfile>? _discovery;
  bool _discoveryLoading = false;
  late final DiscoveryLoader<TrainerProfile> _loader =
      DiscoveryLoader<TrainerProfile>(
        fetch: (q) async => DiscoverResult.fromJson<TrainerProfile>(
          await AppScope.of(
            context,
          ).api.discover('trainers', q.withSession(discoverSessionId())),
          TrainerProfile.fromJson,
        ),
        onResult: (r) {
          if (mounted) setState(() => _discovery = r);
        },
        onLoading: (v) {
          if (mounted) setState(() => _discoveryLoading = v);
        },
      );

  void _requestDiscovery({bool immediate = false}) => _loader.request(
    DiscoverQuery(
      q: _search,
      filters: {if (_filter != 'all') 'specialty': _norm(_filter)},
      limit: 50,
    ),
    immediate: immediate,
  );

  static const _specialtyFilters = [
    'all',
    'Weights',
    'Cardio',
    'Yoga',
    'Boxing',
  ];

  /// What each specialty chip says (the filter value itself is the data
  /// value and stays English).
  static const _specialtyLabelKeys = {
    'all': 'member.all',
    'Weights': 'member.specialtyWeights',
    'Cardio': 'trainerReg.specialty_cardio',
    'Yoga': 'trainerReg.specialty_yoga',
    'Boxing': 'trainerReg.specialty_boxing',
  };

  @override
  void initState() {
    super.initState();
    // The trainer catalogue can be populated just after an authenticated
    // session is established. Refresh it whenever the directory opens so a
    // stale initial request never leaves it empty.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.findAncestorStateOfType<MemberShellState>()?.refreshTrainers();
      _requestDiscovery(immediate: true);
    });
  }

  @override
  void dispose() {
    _loader.dispose();
    _searchCtrl.dispose();
    _heroFocus.dispose();
    super.dispose();
  }

  String _norm(Object? v) => v?.toString().trim().toLowerCase() ?? '';

  /// The server's ranked list when there is one (search and specialty already
  /// applied), otherwise the full list filtered here.
  List<TrainerProfile> _filtered(List<TrainerProfile> trainers) =>
      _discovery?.items ?? _plainFiltered(trainers);

  List<TrainerProfile> _plainFiltered(List<TrainerProfile> trainers) {
    var result = trainers;
    final q = _norm(_search);
    if (q.isNotEmpty) {
      result = result
          .where(
            (t) =>
                _norm(t.displayName).contains(q) ||
                _norm(t.bio).contains(q) ||
                t.specialties.any((s) => _norm(s).contains(q)) ||
                t.gyms.any(
                  (g) =>
                      _norm(g.name).contains(q) ||
                      _norm(g.location).contains(q),
                ),
          )
          .toList();
    }
    if (_filter != 'all') {
      final f = _norm(_filter).replaceAll(' ', '');
      result = result
          .where(
            (t) => t.specialties.any(
              (s) => _norm(s).replaceAll(' ', '').contains(f),
            ),
          )
          .toList();
    }
    return result;
  }

  /// "Clear search and filters": back to the full list.
  void _clearSearchAndFilters() {
    _searchCtrl.clear();
    setState(() {
      _search = '';
      _filter = 'all';
    });
    _requestDiscovery(immediate: true);
  }

  static OutlineInputBorder _pill(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final trainers = _filtered(data.trainers);
    final featured = _discovery?.featured ?? const <TrainerProfile>[];
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = ffCardGridColumns(context, constraints.maxWidth);
        // DS v1.0 Trainers board: rows on phones (under 600 wide).
        final rows = constraints.maxWidth < 600;

        return CustomScrollView(
          key: const Key('trainer-page-scroll'),
          slivers: [
            // ── Header + controls ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (photoHeroUi) ...[
                      // PHOTO_HERO_UI (increment plan, slice 1): a band in
                      // place of the page title.
                      FFHeroBand(
                        key: const Key('trainers-hero'),
                        photo: FFHeroPhoto.trainers,
                        headingFocusNode: _heroFocus,
                        minHeight: 160,
                        clearPhoto: FFTokens.heroBandClearPhoto,
                        maxHeightAt844: trainersBandMaxHeight,
                        wideHeight: 200,
                        eyebrow: context.tr('member.trainers'),
                        headlineLead: context.tr('hero.trainers.lead'),
                        headlineAccent: context.tr('hero.trainers.accent'),
                      ),
                      const SizedBox(height: FFTokens.spacingMd),
                    ] else
                      FFPageHeader(
                        title: context.tr('member.findTrainerTitle'),
                      ),
                    FFSearchFocusScroll(
                      enabled: photoHeroUi,
                      builder: (context, focusNode) => TextField(
                        key: const Key('trainer-search'),
                        focusNode: focusNode,
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: context.tr('member.searchTrainers'),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _search.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: context.tr('common.close'),
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _search = '');
                                    _requestDiscovery(immediate: true);
                                  },
                                ),
                          // DS v1.0: the search field is a white pill.
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          border: _pill(
                            Theme.of(context).colorScheme.outlineVariant,
                          ),
                          enabledBorder: _pill(
                            Theme.of(context).colorScheme.outlineVariant,
                          ),
                          focusedBorder: _pill(
                            Theme.of(context).colorScheme.onSurface,
                            1.5,
                          ),
                        ),
                        onChanged: (v) {
                          setState(() => _search = v);
                          _requestDiscovery();
                        },
                      ),
                    ),
                    if (_discoveryLoading)
                      const LinearProgressIndicator(minHeight: 2),
                    // The chips' 48px hit area brings its own space above.
                    const SizedBox(height: 4),
                    // ── Specialty filter chips (F-11: 48px, keyboard) ──
                    // A plain row (not a lazy list) so Tab reaches every
                    // chip; 2px side padding keeps the focus ring visible.
                    SingleChildScrollView(
                      key: const Key('trainer-filter-scroll'),
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Row(
                        children: [
                          for (
                            var i = 0;
                            i < _specialtyFilters.length;
                            i++
                          ) ...[
                            if (i > 0) const SizedBox(width: 8),
                            FFFilterChip(
                              key: Key(
                                'trainer-filter-${_specialtyFilters[i]}',
                              ),
                              label: context.tr(
                                _specialtyLabelKeys[_specialtyFilters[i]]!,
                              ),
                              selected: _filter == _specialtyFilters[i],
                              onSelected: () {
                                setState(() => _filter = _specialtyFilters[i]);
                                _requestDiscovery(immediate: true);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Featured (labelled; only trainers that match this search) ──
            SliverToBoxAdapter(
              child: FFFeaturedStrip(
                title: context.tr('member.featuredTrainers'),
                count: featured.length,
                // As tall as the tallest card: a two-line name or a large
                // text size is never cut (same as Gyms).
                fitContent: true,
                itemBuilder: (context, i) => TrainerGridCard(
                  key: Key('trainer-featured-${featured[i].id}'),
                  trainer: featured[i],
                  placement: _discovery?.placement,
                ),
              ),
            ),

            // ── Section header with shade separation ─────────────────────
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.only(top: 20),
                padding: const EdgeInsets.symmetric(
                  horizontal: FFTokens.spacingLg,
                  vertical: 10,
                ),
                color: cs.surfaceContainerLow,
                child: Row(
                  children: [
                    Text(
                      context.tr('member.topRated'),
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (trainers.isNotEmpty)
                      Text(
                        '${trainers.length}',
                        style: tt.bodySmall?.copyWith(color: cs.primary),
                      ),
                  ],
                ),
              ),
            ),

            // ── Grid ──────────────────────────────────────────────────────
            // F-12: loading and failure have their own states (flag on and
            // off); "Nothing to show yet." only once loaded and empty.
            if (data.trainers.isEmpty && !data.trainersLoaded)
              DirectorySkeletonGrid(
                key: const Key('trainer-grid-loading'),
                columns: cols,
                childAspectRatio: 0.68,
              )
            else if (data.trainers.isEmpty && data.trainersLoadFailed)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  child: FFErrorState(
                    key: const Key('trainer-load-error'),
                    title: context.tr('member.trainersLoadError'),
                    retryLabel: context.tr('common.retry'),
                    onRetry: () => context
                        .findAncestorStateOfType<MemberShellState>()
                        ?.refreshTrainers(),
                  ),
                ),
              )
            else if (trainers.isEmpty && featured.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  child:
                      data.trainers.isNotEmpty &&
                          (_search.isNotEmpty || _filter != 'all')
                      ? FFEmptyState(
                          key: const Key('trainer-no-match'),
                          title: context.tr('member.trainersNoMatch'),
                          action: FFButton(
                            key: const Key('trainer-clear-search'),
                            label: context.tr('member.clearSearchFilters'),
                            variant: FFButtonVariant.ghost,
                            onPressed: _clearSearchAndFilters,
                          ),
                        )
                      : FFEmptyState(title: context.tr('member.noData')),
                ),
              )
            else if (trainers.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                // Rows as tall as their tallest card, not a fixed aspect
                // ratio: a long name or a large text size makes the row
                // taller instead of overflowing it.
                sliver: SliverFFRowGrid(
                  columns: rows ? 1 : cols,
                  itemCount: trainers.length,
                  itemBuilder: (context, i) => TrainerGridCard(
                    key: Key('trainer-card-${trainers[i].id}'),
                    trainer: trainers[i],
                    placement: _discovery?.placement,
                    imageAspectRatio: cols == 1 ? 4 / 3 : 1,
                    row: rows,
                  ),
                ),
              ),
            // PHOTO_FOOTER_UI (spec §33.6): once loaded, with results.
            if (photoFooterUi)
              FFPhotoFooter.sliver(
                key: const Key('trainers-footer'),
                pageKey: 'member.trainers',
                top: FFHeroPhoto.trainers,
                backToTop: true,
                headingFocus: _heroFocus,
                enabled: data.trainersLoaded && trainers.isNotEmpty,
                // The grid already ends with 24px of padding.
                gap: FFTokens.spacingXl - FFTokens.spacingLg,
              ),
          ],
        );
      },
    );
  }
}
