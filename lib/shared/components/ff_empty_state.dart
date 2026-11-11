import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Empty state placeholder — matches portal's EmptyState component.
class FFEmptyState extends StatelessWidget {
  const FFEmptyState({
    super.key,
    required this.title,
    this.body,
    this.action,
    this.icon,
  });

  final String title;
  final String? body;
  final Widget? action;

  /// Optional illustration icon shown above the title.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: FFTokens.spacingLg,
        vertical: FFTokens.spacing2xl,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            ExcludeSemantics(
              child: Icon(
                icon,
                size: FFTokens.iconXl,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: FFTokens.spacingSm),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          if (body != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                body!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: FFTokens.spacingMd),
            action!,
          ],
        ],
      ),
    );
  }
}
