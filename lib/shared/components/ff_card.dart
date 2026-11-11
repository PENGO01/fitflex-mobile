import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Surface card: white on the sage page (light), charcoal on black (dark).
/// Light system: radius 20, no border, no shadow.
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
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        ),
        clipBehavior: Clip.antiAlias,
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
