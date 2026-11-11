import 'package:flutter/material.dart';
import '../design_tokens.dart';
import 'ff_card.dart';

/// Tappable list tile in a card — common pattern throughout the app.
class FFActionTile extends StatelessWidget {
  const FFActionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Shown instead of [subtitle] (e.g. a loading line).
  final Widget? subtitleWidget;
  final Widget? trailing;

  /// Null: the tile is disabled (dimmed, not tappable).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = FFCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        child: Row(
          children: [
            Container(
              width: FFTokens.iconBox,
              height: FFTokens.iconBox,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(FFTokens.radiusFull),
              ),
              child: Icon(
                icon,
                color: theme.colorScheme.primary,
                size: FFTokens.iconMd,
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  if (subtitleWidget != null) ...[
                    const SizedBox(height: FFTokens.spacing2xs),
                    subtitleWidget!,
                  ] else if (subtitle != null) ...[
                    const SizedBox(height: FFTokens.spacing2xs),
                    Text(subtitle!, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: FFTokens.iconMd,
                ),
          ],
        ),
      ),
    );
    return onTap == null ? Opacity(opacity: 0.6, child: tile) : tile;
  }
}
