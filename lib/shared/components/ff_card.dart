import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Surface card: white on the sage page (light), charcoal on black (dark).
/// DS v1.0: radius 20, no border, elevation 1 in light (a soft forest
/// shadow), flat in dark.
class FFCard extends StatelessWidget {
  const FFCard({super.key, required this.child, this.padding, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: margin ?? const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: FFSurface(
        color: theme.colorScheme.surface,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(FFTokens.spacingMd),
          child: child,
        ),
      ),
    );
  }
}

/// Card header with bottom border — matches portal's CardHeader.
class FFCardHeader extends StatelessWidget {
  const FFCardHeader({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FFTokens.spacingLg,
        vertical: FFTokens.spacingMd,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: child,
    );
  }
}

/// Card content area — matches portal's CardContent.
class FFCardContent extends StatelessWidget {
  const FFCardContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FFTokens.spacingLg,
        vertical: FFTokens.spacingMd,
      ),
      child: child,
    );
  }
}

/// Card footer with top border — matches portal's CardFooter.
class FFCardFooter extends StatelessWidget {
  const FFCardFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FFTokens.spacingLg,
        vertical: FFTokens.spacingMd,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: child,
    );
  }
}

/// A white (charcoal in dark) radius-20 surface with the DS v1.0 card
/// shadow, `0 2 12 rgba(16,45,36,.05)`, in light mode only. No border.
class FFSurface extends StatelessWidget {
  const FFSurface({
    super.key,
    required this.color,
    required this.child,
    this.radius = FFTokens.radiusXl,
  });

  final Color color;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: light
            ? [
                BoxShadow(
                  color: FFTokens.ink.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(borderRadius: shape),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
