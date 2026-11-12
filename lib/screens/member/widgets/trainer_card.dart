import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';
import '../../../shared/promotion_events.dart';
import '../../../shared/widgets/partner_not_verified.dart';

/// Portrait card used inside a responsive grid.
/// Uses a surface-shade background instead of elevation for separation.
class TrainerGridCard extends StatelessWidget {
  const TrainerGridCard({
    super.key,
    required this.trainer,
    this.placement,
    this.imageAspectRatio = 1,
    this.row = false,
  });

  final TrainerProfile trainer;

  /// Phone list (DS v1.0 Trainers board): photo left, name, specialties
  /// and rate, and a lime "Book" pill on the right.
  final bool row;

  /// Photo shape; a one-column grid uses a wider one so the card stays short.
  final double imageAspectRatio;

  /// The discovery placement this card was shown in (promotion analytics).
  final String? placement;

  @override
  Widget build(BuildContext context) => PromotionTracked(
    entityType: 'trainer',
    entityId: trainer.id,
    promotion: trainer.promotion,
    placement: placement,
    child: _card(context),
  );

  Widget _card(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final specialties = trainer.specialties.take(2).join(' · ');

    void open() {
      trackPromotionClick(
        'trainer',
        trainer.id,
        trainer.promotion,
        placement: placement,
      );
      context.go('/member/trainers/${trainer.id}');
    }

    return FFSurface(
      color: cs.surface,
      child: InkWell(
        onTap: open,
        child: row ? _row(context, specialties) : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Avatar / photo ─────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(FFTokens.radiusLg),
              ),
              child: AspectRatio(
                aspectRatio: imageAspectRatio,
                child: trainer.photoUrl != null && trainer.photoUrl!.isNotEmpty
                    ? FFRemoteImage(
                        src: trainer.photoUrl!,
                        profilePhoto: true,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        fallback: _AvatarPlaceholder(name: trainer.displayName),
                      )
                    : _AvatarPlaceholder(name: trainer.displayName),
              ),
            ),
            // ── Content ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Up to two lines for the name with the verified tick
                  // right after it (same as the gym card), so a long name
                  // is read in full instead of being cut on one line.
                  Text.rich(
                    TextSpan(
                      text: trainer.displayName,
                      children: [
                        if (trainer.isVerified) ...[
                          const TextSpan(text: ' '),
                          const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(
                              Icons.verified,
                              size: 13,
                              color: FFTokens.success600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    key: Key('trainer-grid-name-${trainer.id}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  // "Not verified" is a trust signal: a line of its own that
                  // may wrap, never cut.
                  if (!trainer.isVerified) ...[
                    const SizedBox(height: 3),
                    NotVerifiedLabel(
                      key: Key('trainer-grid-unverified-${trainer.id}'),
                      maxLines: 2,
                    ),
                  ],
                  if (specialties.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      specialties,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    formatCurrency(
                      trainer.hourlyRateTzs,
                      currency: trainer.sessionRateCurrency,
                    ),
                    style: tt.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                  if (trainer.promotion != null) ...[
                    const SizedBox(height: 6),
                    FFPromotionBadge(tag: trainer.promotion!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photo(BuildContext context) =>
      trainer.photoUrl != null && trainer.photoUrl!.isNotEmpty
      ? FFRemoteImage(
          src: trainer.photoUrl!,
          profilePhoto: true,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          fallback: _AvatarPlaceholder(name: trainer.displayName),
        )
      : _AvatarPlaceholder(name: trainer.displayName);

  Widget _row(BuildContext context, String specialties) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(width: 72, height: 72, child: _photo(context)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: trainer.displayName,
                    children: [
                      if (trainer.isVerified) ...[
                        const TextSpan(text: ' '),
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(
                            Icons.verified,
                            size: 13,
                            color: FFTokens.success600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  key: Key('trainer-grid-name-${trainer.id}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!trainer.isVerified) ...[
                  const SizedBox(height: 2),
                  NotVerifiedLabel(
                    key: Key('trainer-grid-unverified-${trainer.id}'),
                    maxLines: 2,
                  ),
                ],
                if (specialties.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    specialties,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  formatCurrency(
                    trainer.hourlyRateTzs,
                    currency: trainer.sessionRateCurrency,
                  ),
                  style: tt.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                if (trainer.promotion != null) ...[
                  const SizedBox(height: 4),
                  FFPromotionBadge(tag: trainer.promotion!),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: const ShapeDecoration(
                color: FFTokens.volt,
                shape: StadiumBorder(),
              ),
              child: Text(
                context.tr('trainer.bookPill'),
                style: const TextStyle(
                  color: FFTokens.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initials = name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return Container(
      color: cs.primary.withValues(alpha: 0.12),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: cs.primary,
          ),
        ),
      ),
    );
  }
}

class TrainerCard extends StatelessWidget {
  const TrainerCard({super.key, required this.trainer, this.placement});

  final TrainerProfile trainer;

  /// The discovery placement this card was shown in (promotion analytics).
  final String? placement;

  @override
  Widget build(BuildContext context) => PromotionTracked(
    entityType: 'trainer',
    entityId: trainer.id,
    promotion: trainer.promotion,
    placement: placement,
    child: _card(context),
  );

  Widget _card(BuildContext context) {
    final specialties = trainer.specialties.join(' / ');
    return FFCard(
      child: InkWell(
        onTap: () {
          trackPromotionClick(
            'trainer',
            trainer.id,
            trainer.promotion,
            placement: placement,
          );
          context.go('/member/trainers/${trainer.id}');
        },
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        child: Row(
          children: [
            FFAvatar(
              name: trainer.displayName,
              src: trainer.photoUrl,
              size: FFAvatarSize.lg,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name up to two lines with the tick after it; "Not
                  // verified" gets its own line (as on the grid card).
                  Text.rich(
                    TextSpan(
                      text: trainer.displayName,
                      children: [
                        if (trainer.isVerified) ...[
                          const TextSpan(text: ' '),
                          const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(
                              Icons.verified,
                              size: 14,
                              color: FFTokens.success600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    key: Key('trainer-list-name-${trainer.id}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (!trainer.isVerified) ...[
                    const SizedBox(height: 2),
                    const NotVerifiedLabel(maxLines: 2),
                  ],
                  if (specialties.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      specialties,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              '${formatCurrency(trainer.hourlyRateTzs, currency: trainer.sessionRateCurrency)}${context.tr('trainerReg.perSession')}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
