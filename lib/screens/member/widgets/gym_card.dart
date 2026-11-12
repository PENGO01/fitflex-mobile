import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';
import '../../../shared/promotion_events.dart';
import '../../../shared/widgets/partner_not_verified.dart';
import 'gym_filters.dart';

class GymCard extends StatelessWidget {
  const GymCard({
    super.key,
    required this.gym,
    this.distanceKm,
    this.placement,
  });

  final Gym gym;
  final double? distanceKm;

  /// The discovery placement this card was shown in (promotion analytics).
  final String? placement;

  @override
  Widget build(BuildContext context) => PromotionTracked(
    entityType: 'gym',
    entityId: gym.id,
    promotion: gym.promotion,
    placement: placement,
    child: _card(context),
  );

  Widget _card(BuildContext context) {
    return FFCard(
      child: InkWell(
        onTap: () {
          trackPromotionClick(
            'gym',
            gym.id,
            gym.promotion,
            placement: placement,
          );
          context.go('/member/gyms/${gym.id}');
        },
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        child: Row(
          children: [
            SizedBox(width: 72, height: 72, child: _GymThumb(gym: gym)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name up to two lines with the tick after it; "Not
                  // verified" gets its own line so neither pushes the row
                  // past the card at large text sizes.
                  Text.rich(
                    TextSpan(
                      text: gym.name,
                      children: [
                        if (gymIsVerified(gym)) ...[
                          const TextSpan(text: ' '),
                          const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: GymVerifiedIcon(size: 14),
                          ),
                        ],
                      ],
                    ),
                    key: Key('gym-list-name-${gym.id}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (!gymIsVerified(gym)) ...[
                    const SizedBox(height: 2),
                    const NotVerifiedLabel(maxLines: 2),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    gym.location,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      FFBadge(
                        label: gymTierLabel(context, gym),
                        tone: FFBadgeTone.gray,
                      ),
                      if (distanceKm != null)
                        FFBadge(
                          label: _formatDistance(distanceKm!),
                          tone: FFBadgeTone.gray,
                        ),
                      if (gym.promotion != null)
                        FFPromotionBadge(tag: gym.promotion!),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.outline,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

bool gymIsVerified(Gym gym) =>
    gym.isVerified ||
    gym.verificationStatus == 'verified' ||
    gym.verificationStatus == 'approved';

String _formatDistance(double km) {
  if (km < 10) return '${km.toStringAsFixed(1)} km';
  return '${km.round()} km';
}

/// How a [GymGridCard] is laid out.
///
/// * [tile]: photo on top, for grids of two or more columns.
/// * [hero]: the first gym on a phone (DS v1.0 Gyms board): a big photo with
///   a lime distance chip and a "View" pill under the name.
/// * [row]: the rest of the list on a phone: 64px photo, name, area, status
///   and a "View" pill on the right.
enum GymCardLayout { tile, hero, row }

/// The gym card used on the Gyms tab, in the featured strip and elsewhere.
/// White, radius 20, soft shadow in light mode, no border (DS v1.0).
class GymGridCard extends StatelessWidget {
  const GymGridCard({
    super.key,
    required this.gym,
    this.distanceKm,
    this.onTap,
    this.extraBadge,
    this.placement,
    this.imageAspectRatio = 4 / 3,
    this.layout = GymCardLayout.tile,
  });

  final Gym gym;
  final double? distanceKm;

  /// The discovery placement this card was shown in (promotion analytics).
  final String? placement;

  /// Photo shape; a one-column grid uses a wider one so the card stays short.
  final double imageAspectRatio;

  /// Defaults to the member gym page.
  final VoidCallback? onTap;

  /// An extra badge under the tier (e.g. how a trainer gets in).
  final Widget? extraBadge;

  final GymCardLayout layout;

  @override
  Widget build(BuildContext context) => PromotionTracked(
    entityType: 'gym',
    entityId: gym.id,
    promotion: gym.promotion,
    placement: placement,
    child: _shell(context),
  );

  void _open(BuildContext context) {
    trackPromotionClick('gym', gym.id, gym.promotion, placement: placement);
    (onTap ?? () => context.go('/member/gyms/${gym.id}'))();
  }

  Widget _shell(BuildContext context) {
    final theme = Theme.of(context);
    final content = switch (layout) {
      GymCardLayout.tile => _tile(context),
      GymCardLayout.hero => _hero(context),
      GymCardLayout.row => _row(context),
    };
    return Material(
      color: theme.colorScheme.surface,
      elevation: theme.brightness == Brightness.light ? 1 : 0,
      shadowColor: FFTokens.ink.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: () => _open(context), child: content),
    );
  }

  Widget _photo(BuildContext context, {double iconSize = 36}) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: cs.surfaceContainerHighest,
      child: Icon(
        Icons.fitness_center,
        size: iconSize,
        color: cs.onSurfaceVariant,
      ),
    );
    final thumb = gym.coverThumbnail;
    if (thumb == null) return placeholder;
    return FFRemoteImage(
      src: thumb,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      fallback: placeholder,
    );
  }

  Widget _name(BuildContext context, TextStyle? style, double tick) =>
      Text.rich(
        TextSpan(
          text: gym.name,
          children: [
            if (gymIsVerified(gym)) ...[
              const TextSpan(text: ' '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: GymVerifiedIcon(size: tick),
              ),
            ],
          ],
        ),
        key: Key('gym-grid-name-${gym.id}'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );

  /// "Not verified" is the trust signal: it has a line of its own (with a
  /// small icon) and may wrap, never cut.
  Widget _unverified(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      key: Key('gym-grid-unverified-${gym.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.gpp_maybe_outlined,
            size: 13,
            color: tt.bodySmall?.color,
          ),
        ),
        const SizedBox(width: 4),
        const Flexible(child: NotVerifiedLabel(maxLines: 2)),
      ],
    );
  }

  List<Widget> _badges(BuildContext context, {bool distance = true}) => [
    FFBadge(label: gymTierLabel(context, gym), tone: FFBadgeTone.gray),
    if (distance && distanceKm != null)
      FFBadge(label: _formatDistance(distanceKm!), tone: FFBadgeTone.gray),
    if (gym.promotion != null) FFPromotionBadge(tag: gym.promotion!),
    ?extraBadge,
  ];

  Widget _tile(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(aspectRatio: imageAspectRatio, child: _photo(context)),
        Flexible(
          child: ClipRect(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Up to two lines for the name, with the verified tick
                  // right after it, so at 360 it is read in full.
                  _name(
                    context,
                    tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    13,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    gym.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall,
                  ),
                  if (!gymIsVerified(gym)) ...[
                    const SizedBox(height: 3),
                    _unverified(context),
                  ],
                  const SizedBox(height: 8),
                  Wrap(spacing: 4, runSpacing: 4, children: _badges(context)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _hero(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _photo(context, iconSize: 44),
              if (distanceKm != null)
                PositionedDirectional(
                  top: 12,
                  start: 12,
                  child: _LimeChip(
                    key: Key('gym-hero-distance-${gym.id}'),
                    icon: Icons.near_me,
                    label: _formatDistance(distanceKm!),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _name(
                      context,
                      tt.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      15,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      gym.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(fontSize: 13),
                    ),
                    if (!gymIsVerified(gym)) ...[
                      const SizedBox(height: 3),
                      _unverified(context),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: _badges(context, distance: false),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const _ViewPill(filled: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 64,
              height: 64,
              child: _photo(context, iconSize: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _name(
                  context,
                  tt.bodyMedium?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  13,
                ),
                const SizedBox(height: 2),
                Text(
                  gym.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall,
                ),
                if (!gymIsVerified(gym)) ...[
                  const SizedBox(height: 2),
                  _unverified(context),
                ],
                const SizedBox(height: 6),
                Wrap(spacing: 4, runSpacing: 4, children: _badges(context)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const _ViewPill(filled: false),
        ],
      ),
    );
  }
}

/// Lime chip on a photo (distance on the nearest gym).
class _LimeChip extends StatelessWidget {
  const _LimeChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: const ShapeDecoration(
      color: FFTokens.volt,
      shape: StadiumBorder(),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: FFTokens.ink),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: FFTokens.ink,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// "View" pill. The whole card is the button; this is its visible label,
/// so it is hidden from screen readers (the card already reads as a link).
class _ViewPill extends StatelessWidget {
  const _ViewPill({required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fill = filled ? FFTokens.volt : null;
    final fg = filled ? FFTokens.ink : cs.onSurface;
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: ShapeDecoration(
          color: fill,
          shape: StadiumBorder(
            side: filled
                ? BorderSide.none
                : BorderSide(color: cs.onSurface, width: 1.5),
          ),
        ),
        child: Text(
          context.tr('gym.view'),
          style: TextStyle(
            color: fg,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class GymVerifiedIcon extends StatelessWidget {
  const GymVerifiedIcon({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.verified, size: size, color: FFTokens.success600);
}

class _GymThumb extends StatelessWidget {
  const _GymThumb({required this.gym});

  final Gym gym;

  @override
  Widget build(BuildContext context) {
    final thumb = gym.coverThumbnail;
    if (thumb == null) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        ),
        child: Icon(
          Icons.fitness_center,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(FFTokens.radiusMd),
      child: FFRemoteImage(
        src: thumb,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        fallback: Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.fitness_center,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
