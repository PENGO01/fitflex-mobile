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
    final grouped = _FFTileSlot.of(context);
    final Widget tile;
    if (grouped != null) {
      // Inside an [FFTileGroup]: a flat row, hairline above all but the first.
      tile = DecoratedBox(
        decoration: BoxDecoration(
          border: grouped.first
              ? null
              : Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
        ),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FFTokens.spacingMd,
                vertical: 10,
              ),
              child: _row(theme),
            ),
          ),
        ),
      );
    } else {
      tile = FFCard(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FFTokens.radiusXl),
          child: _row(theme),
        ),
      );
    }
    return onTap == null ? Opacity(opacity: 0.6, child: tile) : tile;
  }

  Widget _row(ThemeData theme) => Row(
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
        );
}

/// Several [FFActionTile]s in one white card with hairlines between them
/// (DS v1.0 grouped rows). Children that render nothing leave no gap.
class FFTileGroup extends StatelessWidget {
  const FFTileGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: Material(
        color: theme.colorScheme.surface,
        elevation: theme.brightness == Brightness.light ? 1 : 0,
        shadowColor: FFTokens.ink.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++)
              _FFTileSlot(first: i == 0, child: children[i]),
          ],
        ),
      ),
    );
  }
}

class _FFTileSlot extends InheritedWidget {
  const _FFTileSlot({required this.first, required super.child});

  final bool first;

  static _FFTileSlot? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FFTileSlot>();

  @override
  bool updateShouldNotify(_FFTileSlot old) => old.first != first;
}
