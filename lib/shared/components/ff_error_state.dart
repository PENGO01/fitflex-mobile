import 'package:flutter/material.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import 'ff_button.dart';

/// "Could not load" placeholder with a retry button. Title, message and the
/// retry label default to the shared strings; pass [onRetry] null to hide the
/// button.
class FFErrorState extends StatelessWidget {
  const FFErrorState({
    super.key,
    this.icon = Icons.error_outline,
    this.title,
    this.message,
    this.onRetry,
    this.retryLabel,
  });

  final IconData icon;
  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final String? retryLabel;

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
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(
                icon,
                size: FFTokens.iconXl,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              title ?? context.tr('common.errorTitle'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                message ?? context.tr('common.errorBody'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: FFTokens.spacingMd),
              FFButton(
                label: retryLabel ?? context.tr('common.retry'),
                icon: Icons.refresh,
                variant: FFButtonVariant.secondary,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
