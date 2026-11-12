import 'package:flutter/material.dart';

import '../design_tokens.dart';

final ThemeData _voltTheme = buildVoltCardTheme();

/// The one lime card on a partner's home (DS v1.0 "Today" card): a forest
/// chip, then either a big number with its label or a title, and the day's
/// main action. The member pass card is the member-side twin.
class FFTodayCard extends StatelessWidget {
  const FFTodayCard({
    super.key,
    required this.chipLabel,
    this.chipIcon = Icons.today,
    this.value,
    this.valueLabel,
    this.title,
    this.body,
    this.action,
  });

  final String chipLabel;
  final IconData chipIcon;

  /// Big number (56/800) with [valueLabel] on its baseline.
  final String? value;
  final String? valueLabel;

  /// Shown instead of the number when there is none.
  final String? title;
  final String? body;

  /// Buttons on the lime card use the forest-on-lime card theme.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: Theme(
        data: _voltTheme,
        child: Material(
          color: FFTokens.volt,
          borderRadius: BorderRadius.circular(FFTokens.radius2xl),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              PositionedDirectional(
                top: -6,
                end: -10,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Opacity(
                      opacity: 0.4,
                      child: Image.asset(
                        'assets/brand/africa-dots.png',
                        width: 130,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                        decoration: BoxDecoration(
                          color: FFTokens.ink,
                          borderRadius: BorderRadius.circular(
                            FFTokens.radiusFull,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(chipIcon, size: 14, color: Colors.white),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                chipLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: FFTokens.spacingMd),
                    if (value != null)
                      Semantics(
                        container: true,
                        label: '$value ${valueLabel ?? ''}',
                        child: ExcludeSemantics(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.end,
                            spacing: 8,
                            children: [
                              Text(
                                value!,
                                style: theme.textTheme.displayMedium?.copyWith(
                                  color: FFTokens.ink,
                                  fontSize: 56,
                                  fontWeight: FontWeight.w800,
                                  height: 0.95,
                                  letterSpacing: -2,
                                ),
                              ),
                              if (valueLabel != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    valueLabel!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: FFTokens.ink,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                    else if (title != null)
                      Text(
                        title!,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: FFTokens.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (body != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        body!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF2F4A28),
                        ),
                      ),
                    ],
                    if (action != null) ...[
                      const SizedBox(height: FFTokens.spacingMd),
                      action!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
