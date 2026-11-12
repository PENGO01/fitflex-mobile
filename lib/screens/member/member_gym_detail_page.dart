import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/photo_footer_flag.dart';
import '../../shared/design_tokens.dart';
import '../../shared/tone_theme.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../../shared/widgets/reviews_section.dart';
import 'member_shell.dart';
import '../../shared/promotion_events.dart';
import '../../shared/widgets/photo_gallery.dart';
import 'widgets/gym_card.dart';
import 'widgets/gym_plans_sheet.dart';
import 'widgets/trainer_card.dart';
import 'widgets/gym_filters.dart';

class MemberGymDetailPage extends StatefulWidget {
  const MemberGymDetailPage({super.key, required this.gymId});

  final String gymId;

  @override
  State<MemberGymDetailPage> createState() => _MemberGymDetailPageState();
}

class _MemberGymDetailPageState extends State<MemberGymDetailPage> {
  bool _openingDirections = false;

  @override
  void initState() {
    super.initState();
    // Only counts when the member arrived from a promoted card (fresh touch).
    PromotionEvents.instance.recordForTouched(
      'detail_view',
      'gym',
      widget.gymId,
    );
  }

  Future<void> _handleDirections(Gym gym) async {
    setState(() => _openingDirections = true);
    try {
      await openMapDirections(gym);
    } finally {
      if (mounted) setState(() => _openingDirections = false);
    }
  }

  // A7: Subscribe → gym's own Daily/Weekly/Monthly plans.
  Future<void> _openPlans(Gym gym) async {
    final data = MemberDataScope.of(context);
    PromotionEvents.instance.recordForTouched(
      'subscription_click',
      'gym',
      gym.id,
    );
    final subscribed = await showGymPlansSheet(context, gym);
    if (subscribed == true && mounted) {
      final res = await AppScope.of(context).api.me();
      if (!mounted) return;
      data.update(
        (d) => d.me = MemberMeResponse.fromJson(
          Map<String, dynamic>.from(res as Map),
        ),
      );
      if (!mounted) return;
      FFSnack.info(context, context.tr('member.subscribeRequested'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final gym = data.gyms.where((g) => g.id == widget.gymId).firstOrNull;

    if (gym == null) {
      return Center(child: FFEmptyState(title: context.tr('member.noData')));
    }

    final trainersAtGym = data.trainers
        .where((t) {
          return t.gymIds.contains(widget.gymId) ||
              t.gyms.any((g) => g.id == widget.gymId);
        })
        .take(2)
        .toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: () => context.go(AppRoutes.memberGyms),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('member.gymDetail')),
        actions: [_SaveGymButton(gymId: gym.id)],
      ),
      // A8 — section order: gallery → name → location → verification →
      // ratings → plans → directions → about → equipment → amenities →
      // trainers → reviews → actions.
      body: footerListView(
        key: const Key('gym-detail-scroll'),
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        // PHOTO_FOOTER_UI: footer only, no stock top hero (the partner's
        // own photos lead the page, decision D-1).
        footer: photoFooterUi
            ? FFPhotoFooter.sliver(
                key: const Key('gym-detail-footer'),
                pageKey: 'member.gymDetail',
                gap: FFTokens.spacingXl - FFTokens.spacingLg,
              )
            : null,
        children: [
          // 1. Scrollable photo gallery
          _GymHero(key: const Key('gym-section-gallery'), gym: gym),

          // 2. Name + 3. Location
          Row(
            key: const Key('gym-section-name'),
            children: [
              Flexible(
                child: Text(
                  gym.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            gym.location,
            key: const Key('gym-section-location'),
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),

          // 4. Verification status (A6)
          Row(
            key: const Key('gym-section-verification'),
            children: [
              FFBadge(
                key: const Key('gym-verification-badge'),
                label: gymIsVerified(gym)
                    ? context.tr('gym.verified')
                    : gym.profileComplete
                    ? context.tr('gym.profileComplete')
                    : context.tr('gym.unverified'),
                tone: gymIsVerified(gym)
                    ? FFBadgeTone.success
                    : gym.profileComplete
                    ? FFBadgeTone.brand
                    : FFBadgeTone.gray,
                dot: true,
              ),
              const SizedBox(width: 6),
              FFBadge(
                label: gymTierLabel(context, gym),
                tone: FFBadgeTone.neutral,
              ),
              if (gym.isFreeOnline) ...[
                const SizedBox(width: 6),
                FFBadge(
                  label: context.tr('gym.free'),
                  tone: FFBadgeTone.success,
                ),
              ],
            ],
          ),

          // 5. Ratings
          _GymRatings(key: const Key('gym-section-ratings'), gym: gym),

          // 6. Gym plans (A7)
          FFSectionTitle(
            context.tr('member.gymPlansTitle'),
            key: const Key('gym-section-plans'),
          ),
          _GymPlansPreview(gym: gym, onSubscribe: () => _openPlans(gym)),

          // 7. Directions
          InkWell(
            key: const Key('gym-section-directions'),
            onTap: _openingDirections ? null : () => _handleDirections(gym),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _openingDirections
                      ? FFSpinner(size: 18)
                      : Icon(
                          Icons.map_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  const SizedBox(width: 6),
                  Text(
                    context.tr('gym.getDirections'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 8. About
          FFSectionTitle(
            context.tr('member.about'),
            key: const Key('gym-section-about'),
          ),
          FFCard(
            child: Text(
              gym.venueType == 'online'
                  ? context.tr('member.planBody')
                  : '${context.tr('member.openNow')} - ${context.tr('member.qrCheckIn')} - ${formatCurrency(gym.perVisitRate)}',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                height: 1.4,
              ),
            ),
          ),

          // 9. Equipment
          if (gym.equipment.isNotEmpty) ...[
            FFSectionTitle(
              context.tr('gym.equipment'),
              key: const Key('gym-section-equipment'),
            ),
            _CategorizedItems(
              items: gym.equipment,
              categories: _equipmentCategories,
              tone: FFBadgeTone.gray,
            ),
          ],

          // 10. Amenities
          if (gym.amenities.isNotEmpty) ...[
            FFSectionTitle(
              context.tr('gym.amenities'),
              key: const Key('gym-section-amenities'),
            ),
            _CategorizedItems(
              items: gym.amenities,
              categories: _amenityCategories,
              tone: FFBadgeTone.brand,
            ),
          ],

          // 11. Trainers
          FFSectionTitle(
            context.tr('member.trainersAtGym'),
            key: const Key('gym-section-trainers'),
          ),
          if (trainersAtGym.isEmpty)
            FFEmptyState(title: context.tr('member.noData'))
          else
            ...trainersAtGym.map((t) => TrainerCard(trainer: t)),

          // 12. Reviews
          FFSectionTitle(
            context.tr('gym.reviews'),
            key: const Key('gym-section-reviews'),
          ),
          ReviewsSection(
            subject: ReviewSubject.gym,
            subjectId: gym.id,
            onRatingChanged: (average, count) => data.update(
              (d) => d.gyms = [
                for (final g in d.gyms)
                  g.id == gym.id ? g.withRating(average, count) : g,
              ],
            ),
          ),

          // 13. Actions
          const SizedBox(height: 16),
          if (data.pendingGymPlan(gym.id) != null) ...[
            FFAlert(
              message: context.tr('member.gymPlanPending'),
              tone: FFAlertTone.warning,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            key: const Key('gym-section-actions'),
            children: [
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: const Key('gym-subscribe-button'),
                  // Only this gym's own open plan payment holds the button.
                  onPressed: data.pendingGymPlan(gym.id) != null
                      ? null
                      : () => _openPlans(gym),
                  child: Text(context.tr('member.subscribe')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.go(AppRoutes.memberQr),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(context.tr('member.visitWithPass')),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> openMapDirections(Gym gym) async {
  final origin = await _currentLocation();
  final uri = gymDirectionsUri(
    gym,
    originLat: origin?.latitude,
    originLng: origin?.longitude,
  );
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<Position?> _currentLocation() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return null;

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return null;
  }

  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    );
  } catch (_) {
    return null;
  }
}

Uri gymDirectionsUri(Gym gym, {double? originLat, double? originLng}) {
  final query = <String, String>{
    'api': '1',
    'destination': gym.hasCoordinates
        ? '${gym.latitude},${gym.longitude}'
        : gym.location,
    'travelmode': 'driving',
  };
  if (originLat != null && originLng != null) {
    query['origin'] = '$originLat,$originLng';
  }

  return Uri.https('www.google.com', '/maps/dir/', query);
}

/// A8 — ratings summary row: members' average star rating and review count.
class _GymRatings extends StatelessWidget {
  const _GymRatings({super.key, required this.gym});

  final Gym gym;

  @override
  Widget build(BuildContext context) {
    final rated = gym.reviewCount > 0;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const Icon(Icons.star, color: FFTokens.warning500, size: 18),
          const SizedBox(width: 4),
          Text(
            rated ? gym.rating.toStringAsFixed(1) : context.tr('gym.noRatings'),
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (rated) ...[
            const SizedBox(width: 6),
            Text(
              reviewCountLabel(context, gym.reviewCount),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ],
      ),
    );
  }
}

/// A7 — inline preview of the gym's Daily/Weekly/Monthly plans with a
/// subscribe CTA opening the full plan sheet.
class _GymPlansPreview extends StatelessWidget {
  const _GymPlansPreview({required this.gym, required this.onSubscribe});

  final Gym gym;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final plans = gymPlansFor(gym);
    if (plans.isEmpty) {
      return FFEmptyState(title: context.tr('member.noGymPlans'));
    }
    return FFCard(
      child: Column(
        children: [
          ...plans.map(
            (p) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('member.plan_${p.id}'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    formatCurrency(p.price),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FFButton(
              key: const Key('gym-plans-cta'),
              label: context.tr('member.viewPlans'),
              onPressed: onSubscribe,
              variant: FFButtonVariant.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _GymHero extends StatelessWidget {
  const _GymHero({super.key, required this.gym});

  final Gym gym;

  @override
  Widget build(BuildContext context) => PhotoGallery(images: gym.images);
}

class _ItemCategory {
  const _ItemCategory(
    this.titleKey,
    this.icon,
    this.items, {
    this.asRatings = false,
  });

  final String titleKey;
  final IconData icon;
  final Set<String> items;
  final bool asRatings;
}

final _amenityCategories = [
  _ItemCategory('gym.category.wellness', Icons.spa_outlined, {
    'dry sauna',
    'infrared sauna',
    'steam room',
    'hot tub',
    'hot tub / jacuzzi',
    'jacuzzi',
    'cold plunge',
    'plunge pool',
    'indoor pool',
  }),
  _ItemCategory('gym.category.facilities', Icons.shower_outlined, {
    'lockers',
    'showers',
    'towel service',
    'wifi',
    'wi-fi',
    'reception',
  }),
  _ItemCategory('gym.category.environment', Icons.auto_awesome_outlined, {
    'cleanliness',
    'layout',
    'lighting',
    'size',
    'operating hours',
  }, asRatings: true),
];

final _equipmentCategories = [
  _ItemCategory('gym.category.strength', Icons.fitness_center, {
    'chest press',
    'smith machine',
    'leg press',
    'cable machines',
    'ez curl bars',
    'lat pulldown',
    'squat racks',
    'power racks',
    'benches',
    'dumbbell racks',
    'barbell + plate stations',
    'kettlebell sets',
  }),
  _ItemCategory('gym.category.functional', Icons.sports_gymnastics_outlined, {
    'battle ropes',
    'pull-up bars',
    'plyo boxes',
    'crossfit rig',
    'olympic platform',
    'trx',
    'suspension trainers',
    'multi-station',
    'jungle gym',
  }),
  _ItemCategory('gym.category.combat', Icons.sports_mma_outlined, {
    'heavy bags',
    'boxing',
  }),
  _ItemCategory('gym.category.mobility', Icons.self_improvement_outlined, {
    'yoga',
    'pilates',
    'stretching area',
  }),
  _ItemCategory('gym.category.cardio', Icons.directions_run, {
    'treadmills',
    'stationary bikes',
    'spin',
    'cycling bikes',
    'ellipticals',
    'rowing machines',
    'stair climbers',
  }),
];

class _CategorizedItems extends StatelessWidget {
  const _CategorizedItems({
    required this.items,
    required this.categories,
    required this.tone,
  });

  final List<String> items;
  final List<_ItemCategory> categories;
  final FFBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final remaining = [...items];
    final groups =
        <
          ({String titleKey, IconData icon, List<String> items, bool asRatings})
        >[];
    for (final category in categories) {
      final matched = remaining
          .where((item) => category.items.any((known) => _matches(item, known)))
          .toList();
      if (matched.isEmpty) continue;
      remaining.removeWhere(matched.contains);
      groups.add((
        titleKey: category.titleKey,
        icon: category.icon,
        items: matched,
        asRatings: category.asRatings,
      ));
    }
    if (remaining.isNotEmpty) {
      groups.add((
        titleKey: 'gym.category.other',
        icon: Icons.more_horiz,
        items: remaining,
        asRatings: false,
      ));
    }

    // Sort categories by item count descending (most items first)
    groups.sort((a, b) => b.items.length.compareTo(a.items.length));

    return Column(
      children: groups
          .map(
            (group) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ExpandableChipGroup(
                title: context.tr(group.titleKey),
                icon: group.icon,
                items: group.items,
                tone: tone,
                asRatings: group.asRatings,
                highlightAvailable: true,
              ),
            ),
          )
          .toList(),
    );
  }

  bool _matches(String value, String known) {
    final normalized = value.toLowerCase();
    return normalized == known || normalized.contains(known);
  }
}

class _ExpandableChipGroup extends StatefulWidget {
  const _ExpandableChipGroup({
    required this.title,
    required this.icon,
    required this.items,
    required this.tone,
    required this.asRatings,
    this.highlightAvailable = false,
  });

  final String title;
  final IconData icon;
  final List<String> items;
  final FFBadgeTone tone;
  final bool asRatings;
  final bool highlightAvailable;

  @override
  State<_ExpandableChipGroup> createState() => _ExpandableChipGroupState();
}

class _ExpandableChipGroupState extends State<_ExpandableChipGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final visible = _expanded || widget.items.length <= 8
        ? widget.items
        : widget.items.take(8).toList();
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                widget.icon,
                color: Theme.of(context).colorScheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.asRatings)
            Column(
              children: visible
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _ratingLabel(item),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.star,
                            color: FFTokens.warning500,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _ratingValue(item).toStringAsFixed(1),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: visible
                  .map(
                    (item) => widget.highlightAvailable
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: FFToneTheme.of(context).success.bg,
                              border: Border.all(
                                color: FFToneTheme.of(context).success.border,
                              ),
                              borderRadius: BorderRadius.circular(
                                FFTokens.radiusMd,
                              ),
                            ),
                            child: Text(
                              item,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: FFToneTheme.of(context).success.fg,
                              ),
                            ),
                          )
                        : FFBadge(label: item, tone: widget.tone),
                  )
                  .toList(),
            ),
          if (widget.items.length > 8) ...[
            const SizedBox(height: 8),
            FFButton(
              label: _expanded
                  ? context.tr('gym.showLess')
                  : context.tr('gym.viewAll'),
              onPressed: () => setState(() => _expanded = !_expanded),
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
            ),
          ],
        ],
      ),
    );
  }

  String _ratingLabel(String value) => value
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty && double.tryParse(part) == null)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  double _ratingValue(String value) {
    final match = RegExp(r'([0-5](?:\.\d)?)').firstMatch(value);
    final parsed = match == null ? null : double.tryParse(match.group(1)!);
    return parsed == null ? 4.0 : parsed.clamp(0, 5).toDouble();
  }
}

/// US017 — save / unsave this gym. Optimistic, reverted if the call fails.
class _SaveGymButton extends StatefulWidget {
  const _SaveGymButton({required this.gymId});

  final String gymId;

  @override
  State<_SaveGymButton> createState() => _SaveGymButtonState();
}

class _SaveGymButtonState extends State<_SaveGymButton> {
  bool _busy = false;

  Future<void> _toggle(MemberData data, bool saved) async {
    final api = AppScope.of(context).api;
    final messenger = FFSnack.of(context);
    final failed = context.tr('error.requestFailed');
    setState(() => _busy = true);
    if (!saved) {
      PromotionEvents.instance.recordForTouched('save', 'gym', widget.gymId);
    }
    data.update((d) {
      final next = {...d.favoriteGymIds};
      saved ? next.remove(widget.gymId) : next.add(widget.gymId);
      d.favoriteGymIds = next;
    });
    try {
      await api.setFavoriteGym(widget.gymId, !saved);
    } catch (_) {
      data.update((d) {
        final next = {...d.favoriteGymIds};
        saved ? next.add(widget.gymId) : next.remove(widget.gymId);
        d.favoriteGymIds = next;
      });
      messenger.error(failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final saved = data.favoriteGymIds.contains(widget.gymId);
    return IconButton(
      key: const Key('gym-save-toggle'),
      tooltip: context.tr(saved ? 'member.unsaveGym' : 'member.saveGym'),
      onPressed: _busy ? null : () => _toggle(data, saved),
      icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
      color: saved ? Theme.of(context).colorScheme.primary : null,
    );
  }
}

// ── Shared with the trainer gym page ─────────────────────────────────────────

/// The gym's scrollable photo gallery (tap for full screen).
class GymGallery extends StatelessWidget {
  const GymGallery({super.key, required this.gym});

  final Gym gym;

  @override
  Widget build(BuildContext context) => _GymHero(gym: gym);
}

/// The gym's ratings summary row.
class GymRatingsRow extends StatelessWidget {
  const GymRatingsRow({super.key, required this.gym});

  final Gym gym;

  @override
  Widget build(BuildContext context) => _GymRatings(gym: gym);
}

/// Equipment and amenities, grouped into categories, with section titles.
class GymFacilities extends StatelessWidget {
  const GymFacilities({super.key, required this.gym});

  final Gym gym;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (gym.equipment.isNotEmpty) ...[
        FFSectionTitle(context.tr('gym.equipment')),
        _CategorizedItems(
          items: gym.equipment,
          categories: _equipmentCategories,
          tone: FFBadgeTone.gray,
        ),
      ],
      if (gym.amenities.isNotEmpty) ...[
        FFSectionTitle(context.tr('gym.amenities')),
        _CategorizedItems(
          items: gym.amenities,
          categories: _amenityCategories,
          tone: FFBadgeTone.brand,
        ),
      ],
    ],
  );
}
