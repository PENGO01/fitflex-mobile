import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
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
                        tone: FFBadgeTone.neutral,
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

/// Portrait card used inside a responsive grid.
/// Uses a surface-shade background instead of elevation for separation.
class GymGridCard extends StatelessWidget {
  const GymGridCard({
    super.key,
    required this.gym,
    this.distanceKm,
    this.onTap,
    this.extraBadge,
    this.placement,
    this.imageAspectRatio = 4 / 3,
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

  @override
  Widget build(BuildContext context) => PromotionTracked(
    entityType: 'gym',
    entityId: gym.id,
    promotion: gym.promotion,
    placement: placement,
    child: _card(context),
  );

  Widget _card(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () {
        trackPromotionClick('gym', gym.id, gym.promotion, placement: placement);
        (onTap ?? () => context.go('/member/gyms/${gym.id}'))();
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Image / thumbnail ──────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(FFTokens.radiusLg),
              ),
              child: AspectRatio(
                aspectRatio: imageAspectRatio,
                child: gym.coverThumbnail == null
                    ? Container(
                        color: cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.fitness_center,
                          size: 36,
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    : FFRemoteImage(
                        src: gym.coverThumbnail!,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        fallback: Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            Icons.fitness_center,
                            size: 36,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
            ),
            // ── Content ────────────────────────────────────────────────
            Flexible(
              child: ClipRect(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Up to two lines for the name, with the verified tick
                      // right after it, so at 360 it is read in full instead
                      // of "Dev Owner …".
                      Text.rich(
                        TextSpan(
                          text: gym.name,
                          children: [
                            if (gymIsVerified(gym)) ...[
                              const TextSpan(text: ' '),
                              const WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: GymVerifiedIcon(size: 13),
                              ),
                            ],
                          ],
                        ),
                        key: Key('gym-grid-name-${gym.id}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        gym.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(fontSize: 11),
                      ),
                      // "Not verified" is the trust signal: it has a line of
                      // its own (with a small icon) and may wrap, never cut.
                      if (!gymIsVerified(gym)) ...[
                        const SizedBox(height: 3),
                        Row(
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
                            const Flexible(
                              child: NotVerifiedLabel(maxLines: 2),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          FFBadge(
                            label: gymTierLabel(context, gym),
                            tone: FFBadgeTone.neutral,
                          ),
                          if (distanceKm != null)
                            FFBadge(
                              label: _formatDistance(distanceKm!),
                              tone: FFBadgeTone.gray,
                            ),
                          if (gym.promotion != null)
                            FFPromotionBadge(tag: gym.promotion!),
                          ?extraBadge,
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
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
