import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../member/member_gym_detail_page.dart';
import '../member/member_gyms_tab.dart';
import '../member/widgets/mobile_money_pay.dart';
import '../member/widgets/gym_card.dart';
import '../member/widgets/gym_filters.dart';
import 'trainer_passes_page.dart';

/// Friendly text for trainer pass / plan API errors.
String trainerPassErrorText(BuildContext context, Object error) {
  final code = (error is ApiException && error.body is Map)
      ? (error.body as Map)['error']?.toString()
      : null;
  const known = {
    'period_required',
    'trainer_pass_period_not_offered',
    'trainer_pass_pending',
    'trainer_pass_already_active',
    'trainer_pass_not_offered',
    'home_gym_free',
    'use_trainer_pass',
    'plan_already_held',
    'invalid_plan',
    'not_cancellable',
  };
  return known.contains(code)
      ? context.tr('trainerPass.error.$code')
      : context.tr('owner.errorGeneric');
}

/// Trainer › Gyms: browse every gym the way members do — search, tier and
/// "nearest" chips, price / amenity / verified filters, a photo grid — with
/// how this trainer can train at each gym (linked gym free / trainer pass /
/// member plans) on every card. A gym opens the trainer gym page.
class TrainerGymsTab extends StatefulWidget {
  const TrainerGymsTab({super.key, this.onProfileChanged});

  /// Called after a join request is sent or withdrawn.
  final VoidCallback? onProfileChanged;

  @override
  State<TrainerGymsTab> createState() => TrainerGymsTabState();
}

class TrainerGymsTabState extends State<TrainerGymsTab> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  Map<String, Gym> _gymById = {};
  Set<String> _pendingGymIds = {};
  bool _loading = true;
  bool _started = false;
  String? _error;
  String _search = '';
  String _filter = 'all';
  String _priceFilter = 'any';
  final Set<String> _amenityFilter = {};
  bool _verifiedOnly = false;
  bool _showFilters = false;
  double? _userLat;
  double? _userLng;

  static const _filters = [
    'all',
    'nearest',
    'free',
    'pass',
    'plan',
    'standard',
    'midtier',
    'premium',
  ];
  static const _priceFilters = [
    'any',
    '<60k',
    '<150k',
    '<200k',
    '<350k',
    '350k+',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    refresh();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final api = AppScope.of(context).api;
    try {
      final results = await Future.wait([api.trainerGyms(), api.trainerMe()]);
      if (!mounted) return;
      final me = results[1] as Map<String, dynamic>;
      final rows = (results[0] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      setState(() {
        _rows = rows;
        _gymById = {for (final r in rows) r['id'].toString(): Gym.fromJson(r)};
        _pendingGymIds = ((me['pendingGymIds'] as List?) ?? const [])
            .map((id) => id.toString())
            .toSet();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr('owner.errorGeneric');
      });
    }
  }

  Future<void> _fetchLocation() async {
    if (_userLat != null) return;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      if (!mounted) return;
      setState(() {
        _userLat = position.latitude;
        _userLng = position.longitude;
      });
    } catch (_) {
      // Location is optional; "nearest" then keeps the default order.
    }
  }

  static String accessOf(Map<String, dynamic> gym) =>
      (gym['trainerAccess'] as Map?)?['access']?.toString() ?? 'unavailable';

  List<Map<String, dynamic>> get _visible {
    final byAccess = _rows.where((r) {
      final access = accessOf(r);
      return switch (_filter) {
        'free' => access == 'home',
        'pass' => access == 'trainer_pass',
        'plan' => access == 'member_plan',
        _ => true,
      };
    }).toList();
    final tier = const {'standard', 'midtier', 'premium'}.contains(_filter)
        ? _filter
        : 'all';
    final kept = applyGymFilter(
      byAccess.map((r) => _gymById[r['id'].toString()]!).toList(),
      GymFilter(
        search: _search,
        tier: tier,
        price: _priceFilter,
        amenities: _amenityFilter,
        verifiedOnly: _verifiedOnly,
      ),
    ).map((g) => g.id).toSet();
    final out = byAccess
        .where((r) => kept.contains(r['id'].toString()))
        .toList();
    if (_filter == 'nearest' && _userLat != null && _userLng != null) {
      double km(Map<String, dynamic> r) =>
          gymDistanceKm(_gymById[r['id'].toString()]!, _userLat!, _userLng!);
      out.sort((a, b) => km(a).compareTo(km(b)));
    } else {
      // Home gyms first, then gyms the trainer can get into.
      int rank(Map<String, dynamic> g) => switch (accessOf(g)) {
        'home' => 0,
        'trainer_pass' => 1,
        'member_plan' => 2,
        _ => 3,
      };
      out.sort((a, b) => rank(a).compareTo(rank(b)));
    }
    return out;
  }

  int get _openPassCount => _rows.where((g) => g['currentPass'] is Map).length;

  Future<void> _openPasses() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const TrainerPassesPage()));
    if (mounted) refresh();
  }

  Future<void> _openGym(Map<String, dynamic> row) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TrainerGymDetailPage(
          row: row,
          gym: _gymById[row['id'].toString()]!,
          joinPending: _pendingGymIds.contains(row['id']?.toString()),
        ),
      ),
    );
    if (changed == true && mounted) {
      await refresh();
      widget.onProfileChanged?.call();
    }
  }

  Widget _chip(
    String key,
    String label,
    bool selected,
    VoidCallback onTap, {
    IconData? icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      key: Key('trainer-gym-filter-$key'),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surface,
          border: Border.all(color: selected ? cs.primary : cs.outline),
          borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? cs.onPrimary : cs.onSurface,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: selected ? cs.onPrimary : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Short badge for the narrow grid card; scales down rather than overflow.
  Widget _cardBadge(Map<String, dynamic> row) {
    final current = row['currentPass'] as Map?;
    final active = current?['status'] == 'active';
    final (label, tone) = current == null
        ? trainerAccessBadge(context, row, compact: true)
        : (
            context.tr(
              active ? 'trainerPass.statusActive' : 'trainerPass.statusPending',
            ),
            active ? FFBadgeTone.success : FFBadgeTone.warning,
          );
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: FFBadge(label: label, tone: tone),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final visible = _visible;
    final labels = {
      'all': context.tr('member.all'),
      'nearest': context.tr('member.nearest'),
      'free': context.tr('trainerPass.filterFree'),
      'pass': context.tr('trainerPass.filterPass'),
      'plan': context.tr('trainerPass.filterPlan'),
      'standard': tierLabel(context, 'standard'),
      'midtier': tierLabel(context, 'midtier'),
      'premium': tierLabel(context, 'premium'),
    };
    return LayoutBuilder(
      builder: (context, constraints) => CustomScrollView(
        key: const Key('trainer-gym-scroll'),
        slivers: [
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
                  FFPageHeader(
                    title: context.tr('member.discoverGyms'),
                    actions: Badge(
                      isLabelVisible: _openPassCount > 0,
                      label: Text('$_openPassCount'),
                      child: FFButton(
                        key: const Key('trainer-my-passes'),
                        label: context.tr('trainerPass.myPasses'),
                        onPressed: _openPasses,
                        variant: FFButtonVariant.ghost,
                        size: FFButtonSize.sm,
                        icon: Icons.confirmation_number_outlined,
                      ),
                    ),
                  ),
                  TextField(
                    key: const Key('trainer-gym-search'),
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: context.tr('member.searchGyms'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              tooltip: context.tr('common.close'),
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _search = '');
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                      ),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      key: const Key('trainer-gym-filter-scroll'),
                      scrollDirection: Axis.horizontal,
                      itemCount: _filters.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        if (i == _filters.length) {
                          return _chip(
                            'more',
                            context.tr('member.otherFilters'),
                            _showFilters,
                            () => setState(() => _showFilters = !_showFilters),
                            icon: Icons.tune,
                          );
                        }
                        final f = _filters[i];
                        return _chip(f, labels[f]!, _filter == f, () {
                          setState(() => _filter = f);
                          if (f == 'nearest') _fetchLocation();
                        });
                      },
                    ),
                  ),
                  if (_showFilters) ...[
                    const SizedBox(height: 12),
                    FFCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('member.priceRange'),
                            style: tt.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _priceFilters
                                .map(
                                  (p) => ChoiceChip(
                                    label: Text(
                                      p == 'any'
                                          ? context.tr('member.anyPrice')
                                          : p,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    selected: _priceFilter == p,
                                    onSelected: (_) =>
                                        setState(() => _priceFilter = p),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            context.tr('gym.amenities'),
                            style: tt.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children:
                                availableAmenityOptions(
                                  _gymById.values.toList(),
                                ).map((amenity) {
                                  return FilterChip(
                                    label: Text(
                                      amenity,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    selected: _amenityFilter.contains(amenity),
                                    onSelected: (v) => setState(() {
                                      if (v) {
                                        _amenityFilter.add(amenity);
                                      } else {
                                        _amenityFilter.remove(amenity);
                                      }
                                    }),
                                  );
                                }).toList(),
                          ),
                          Material(
                            color: Colors.transparent,
                            child: SwitchListTile(
                              key: const Key('trainer-gym-filter-verified'),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                context.tr('member.verifiedOnly'),
                                style: tt.labelMedium,
                              ),
                              value: _verifiedOnly,
                              onChanged: (v) =>
                                  setState(() => _verifiedOnly = v),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
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
                    context.tr('trainer.gyms'),
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if (visible.isNotEmpty)
                    Text(
                      '${visible.length}',
                      style: tt.bodySmall?.copyWith(color: cs.primary),
                    ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: FFSpinner(size: 28)),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                child: FFAlert(message: _error!, tone: FFAlertTone.error),
              ),
            )
          else if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                child: FFEmptyState(title: context.tr('member.noData')),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              sliver: Builder(
                builder: (context) {
                  final cols = ffCardGridColumns(context, constraints.maxWidth);
                  // Rows as tall as their tallest card (H3).
                  return SliverFFRowGrid(
                    columns: cols,
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final row = visible[i];
                      final gym = _gymById[row['id'].toString()]!;
                      return GymGridCard(
                        key: Key('trainer-gym-${gym.id}'),
                        gym: gym,
                        imageAspectRatio: cols == 1 ? 16 / 9 : 4 / 3,
                        distanceKm: gymDisplayDistanceKm(
                          gym,
                          userLat: _userLat,
                          userLng: _userLng,
                          activeFilter: _filter,
                        ),
                        extraBadge: _cardBadge(row),
                        onTap: () => _openGym(row),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The badge text + tone for how a trainer gets into a gym.
(String, FFBadgeTone) trainerAccessBadge(
  BuildContext context,
  Map<String, dynamic> gym, {
  bool compact = false,
}) {
  final access = TrainerGymsTabState.accessOf(gym);
  final options = ((gym['trainerAccess'] as Map?)?['options'] as List? ?? [])
      .whereType<Map>()
      .toList();
  final cheapest = options.isEmpty
      ? null
      : options
            .map((o) => (o['feeTzs'] as num?) ?? 0)
            .reduce((a, b) => a < b ? a : b);
  final from = cheapest == null ? '' : formatCurrency(cheapest);
  if (compact) {
    return switch (access) {
      'home' => (context.tr('trainerPass.filterFree'), FFBadgeTone.success),
      'trainer_pass' => (
        context.tr('trainerPass.cardPass').replaceAll('{price}', from),
        FFBadgeTone.brand,
      ),
      'member_plan' => (
        context.tr('trainerPass.cardPlan').replaceAll('{price}', from),
        FFBadgeTone.warning,
      ),
      _ => (context.tr('trainerPass.badgeUnavailable'), FFBadgeTone.gray),
    };
  }
  return switch (access) {
    'home' => (context.tr('trainerPass.badgeHome'), FFBadgeTone.success),
    'trainer_pass' => (
      context.tr('trainerPass.badgePass').replaceAll('{price}', from),
      FFBadgeTone.brand,
    ),
    'member_plan' => (
      context.tr('trainerPass.badgePlan').replaceAll('{price}', from),
      FFBadgeTone.warning,
    ),
    _ => (context.tr('trainerPass.badgeUnavailable'), FFBadgeTone.gray),
  };
}

/// A gym, the way members see it (gallery, verification, ratings,
/// directions, equipment, amenities), with the trainer's own section: how
/// they can train here and the pass or plan to buy. Pops `true` when
/// something changed.
class TrainerGymDetailPage extends StatefulWidget {
  const TrainerGymDetailPage({
    super.key,
    required this.row,
    required this.gym,
    this.joinPending = false,
  });

  final Map<String, dynamic> row;
  final Gym gym;
  final bool joinPending;

  @override
  State<TrainerGymDetailPage> createState() => _TrainerGymDetailPageState();
}

class _TrainerGymDetailPageState extends State<TrainerGymDetailPage> {
  bool _openingDirections = false;

  Future<void> _directions() async {
    setState(() => _openingDirections = true);
    try {
      await openMapDirections(widget.gym);
    } finally {
      if (mounted) setState(() => _openingDirections = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gym = widget.gym;
    final tt = Theme.of(context).textTheme;
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('member.gymDetail'))),
      body: ListView(
        key: const Key('trainer-gym-detail'),
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          GymGallery(gym: gym),
          Text(
            gym.name,
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(gym.location, style: tt.bodySmall?.copyWith(fontSize: 14)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FFBadge(
                label: gymIsVerified(gym)
                    ? context.tr('gym.verified')
                    : context.tr('gym.unverified'),
                tone: gymIsVerified(gym)
                    ? FFBadgeTone.success
                    : FFBadgeTone.gray,
                dot: true,
              ),
              FFBadge(
                label: gymTierLabel(context, gym),
                tone: FFBadgeTone.brand,
              ),
            ],
          ),
          GymRatingsRow(gym: gym),
          FFSectionTitle(context.tr('trainerPass.trainHere')),
          FFCard(
            child: TrainerGymSheet(
              key: const Key('trainer-gym-access'),
              gym: widget.row,
              joinPending: widget.joinPending,
              embedded: true,
              onChanged: () => Navigator.of(context).pop(true),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            key: const Key('trainer-gym-directions'),
            onTap: _openingDirections ? null : _directions,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _openingDirections
                      ? FFSpinner(size: 18)
                      : Icon(Icons.map_outlined, size: 18, color: primary),
                  const SizedBox(width: 6),
                  Text(
                    context.tr('gym.getDirections'),
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          GymFacilities(gym: gym),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// How a trainer can train at a gym, and the pass / plan options to buy.
/// As a bottom sheet it pops `true` when something changed; [embedded] in the
/// trainer gym page it calls [onChanged] instead and leaves the gym's name
/// to the page.
class TrainerGymSheet extends StatefulWidget {
  const TrainerGymSheet({
    super.key,
    required this.gym,
    this.joinPending = false,
    this.embedded = false,
    this.onChanged,
  });

  final Map<String, dynamic> gym;
  final bool joinPending;
  final bool embedded;
  final VoidCallback? onChanged;

  @override
  State<TrainerGymSheet> createState() => _TrainerGymSheetState();
}

class _TrainerGymSheetState extends State<TrainerGymSheet> {
  String? _period;
  bool _busy = false;
  String? _error;

  Map<String, dynamic> get gym => widget.gym;
  String get _access => TrainerGymsTabState.accessOf(gym);
  List<Map> get _options =>
      ((gym['trainerAccess'] as Map?)?['options'] as List? ?? [])
          .whereType<Map>()
          .toList();

  @override
  void initState() {
    super.initState();
    _period = _options.firstOrNull?['period']?.toString();
  }

  /// The pass just bought was paid by mobile money straight away.
  bool _paidNow = false;

  Future<void> _run(Future<void> Function() action, String doneKey) async {
    setState(() {
      _busy = true;
      _error = null;
      _paidNow = false;
    });
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr(_paidNow ? 'trainerPass.paidNow' : doneKey)),
        ),
      );
      if (widget.onChanged != null) {
        widget.onChanged!();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = trainerPassErrorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy() async {
    final option = _options.firstWhere((o) => o['period'] == _period);
    final isPass = _access == 'trainer_pass';
    final price = formatCurrency((option['feeTzs'] as num?) ?? 0);
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr(
        isPass
            ? 'trainerPass.confirmPassTitle'
            : 'trainerPass.confirmPlanTitle',
      ),
      message: context
          .tr('trainerPass.confirmBody')
          .replaceAll('{period}', context.tr('trainerPass.period.$_period'))
          .replaceAll('{gym}', gym['name']?.toString() ?? '')
          .replaceAll('{price}', price),
      cancelLabel: context.tr('member.cancel'),
      confirmLabel: context.tr('trainerPass.request'),
      confirmKey: const Key('trainer-pass-confirm'),
    );
    if (ok != true || !mounted) return;
    final api = AppScope.of(context).api;
    final gymId = gym['id'].toString();
    await _run(() async {
      if (!isPass) {
        await api.trainerBuyMemberPlan(gymId, _period!);
        return;
      }
      final created = await api.trainerBuyPass(gymId, period: _period);
      // With mobile money on for trainer passes, pay straight away
      // (fitflex-functions#240). Otherwise it waits for approval as before.
      final req = created['paymentRequest'];
      if (req is Map && mounted) {
        _paidNow = await offerMobileMoney(
          context,
          paymentRequestId: req['id'] as String?,
          amountTzs: (req['amountTzs'] as num?) ?? 0,
          productType: MomoProduct.trainerGymPass,
          role: 'trainer',
        );
      }
    }, 'trainer.passRequested');
  }

  Future<void> _cancelPending(String subscriptionId) => _run(
    () => AppScope.of(context).api.trainerCancelPass(subscriptionId),
    'trainerPass.cancelled',
  );

  Future<void> _applyToJoin() => _run(
    () => AppScope.of(context).api.trainerApplyToGym(gym['id'].toString()),
    'trainer.applicationSent',
  );

  Future<void> _cancelJoin() => _run(
    () => AppScope.of(
      context,
    ).api.trainerCancelGymApplication(gym['id'].toString()),
    'trainer.applicationCancelled',
  );

  @override
  Widget build(BuildContext context) {
    final current = gym['currentPass'] as Map?;
    final (label, tone) = trainerAccessBadge(context, gym);
    final textTheme = Theme.of(context).textTheme;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.embedded) ...[
          Text(
            gym['name']?.toString() ?? '',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          if ((gym['location']?.toString() ?? '').isNotEmpty)
            Text(gym['location'].toString(), style: textTheme.bodySmall),
          const SizedBox(height: 8),
        ],
        FFBadge(label: label, tone: tone),
        const SizedBox(height: 12),
        Text(
          context.tr('trainerPass.explain.$_access'),
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (current != null)
          _currentPassCard(context, current)
        else if (_options.isNotEmpty)
          ..._optionPicker(context),
        if (_error != null) ...[
          const SizedBox(height: 8),
          FFAlert(message: _error!, tone: FFAlertTone.error),
        ],
        if (_access != 'home') ...[
          const Divider(height: 32),
          Text(
            context.tr('trainerPass.joinTitle'),
            style: textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(context.tr('trainerPass.joinBody'), style: textTheme.bodySmall),
          const SizedBox(height: 8),
          if (widget.joinPending)
            FFButton(
              key: const Key('trainer-gym-cancel-join'),
              label: context.tr('trainerPass.cancelJoin'),
              onPressed: _busy ? null : _cancelJoin,
              variant: FFButtonVariant.secondary,
            )
          else
            FFButton(
              key: const Key('trainer-gym-apply'),
              label: context.tr('trainer.apply'),
              onPressed: _busy ? null : _applyToJoin,
              variant: FFButtonVariant.secondary,
              icon: Icons.handshake_outlined,
            ),
        ],
      ],
    );
    if (widget.embedded) return body;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          0,
          FFTokens.spacingLg,
          FFTokens.spacingLg,
        ),
        child: body,
      ),
    );
  }

  Widget _currentPassCard(BuildContext context, Map current) {
    final active = current['status'] == 'active';
    final until = context.localDate(current['expiresAt'], fallback: '');
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(
              active ? 'trainerPass.statusActive' : 'trainerPass.statusPending',
            ),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            active
                ? context
                      .tr('trainerPass.activeUntil')
                      .replaceAll('{date}', until)
                : context.tr('trainerPass.pendingBody'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (active)
            FFButton(
              key: const Key('trainer-gym-show-qr'),
              label: context.tr('trainerPass.showQr'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TrainerQrPage()),
              ),
              icon: Icons.qr_code_2,
            )
          else
            FFButton(
              key: const Key('trainer-gym-cancel-pass'),
              label: context.tr('trainerPass.cancelRequest'),
              onPressed: _busy
                  ? null
                  : () => _cancelPending(current['id'].toString()),
              variant: FFButtonVariant.secondary,
            ),
        ],
      ),
    );
  }

  List<Widget> _optionPicker(BuildContext context) {
    final isPass = _access == 'trainer_pass';
    return [
      ..._options.map((o) {
        final period = o['period']?.toString() ?? '';
        final selected = period == _period;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            key: Key('trainer-pass-option-$period'),
            onTap: () => setState(() => _period = period),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.tr('trainerPass.period.$period')),
                  ),
                  Text(
                    formatCurrency((o['feeTzs'] as num?) ?? 0),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
      const SizedBox(height: 4),
      Text(
        context.tr('trainerPass.paymentNote'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FFButton(
          key: const Key('trainer-pass-buy'),
          label: context.tr(
            isPass ? 'trainerPass.getPass' : 'trainerPass.getPlan',
          ),
          onPressed: _busy || _period == null ? null : _buy,
          loading: _busy,
        ),
      ),
    ];
  }
}
