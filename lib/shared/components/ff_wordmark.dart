import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// The FitFlex wordmark: "Fit" in the text colour, "Flex" on a lime chip
/// (FitFlex DS v1.0). Read as one word, "FitFlex".
class FFWordmark extends StatelessWidget {
  const FFWordmark({super.key, this.size = 20});

  /// Font size of the letters.
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: FFTokens.fontSans,
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.02 * size,
      height: 1.15,
      color: Theme.of(context).colorScheme.onSurface,
    );
    return Semantics(
      label: 'FitFlex',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Fit', style: style),
          SizedBox(width: size * 0.15),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: size * 0.32,
              vertical: size * 0.04,
            ),
            decoration: BoxDecoration(
              color: FFTokens.volt,
              borderRadius: BorderRadius.circular(size * 0.36),
            ),
            child: Text(
              'Flex',
              style: style.copyWith(color: FFTokens.onVolt),
            ),
          ),
        ],
      ),
    );
  }
}
