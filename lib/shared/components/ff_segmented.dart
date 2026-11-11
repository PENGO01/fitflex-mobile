import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Tab-style toggle group — matches portal's Segmented component.
///
/// Each option is at least 48dp tall to tap. Labels may wrap onto a second
/// line at word boundaries, so they stay readable at large text sizes. When a
/// single word would not fit its share of the width the control first tightens
/// (12.5sp text, smaller padding); when it still would not fit (large text scale)
/// it becomes a horizontally scrolling row of one-line segments. A word is
/// never broken mid-way.
class FFSegmented extends StatelessWidget {
  const FFSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<(String id, String label)> options;
  final ValueChanged<String> onChanged;

  static const _optionPadding = FFTokens.spacingSm;
  static const _compactPadding = FFTokens.spacingXs;
  static const _compactFontSize = 12.5;

  bool _fits(
    BuildContext context,
    double maxWidth,
    TextStyle? style,
    double padding,
  ) {
    if (!maxWidth.isFinite) return true;
    final scaler = MediaQuery.textScalerOf(context);
    // [maxWidth] is the space inside the track's own padding.
    final share = maxWidth / options.length;
    for (final opt in options) {
      for (final word in opt.$2.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final painter = TextPainter(
          text: TextSpan(text: word, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final needed = painter.width + 2 * padding;
        painter.dispose();
        if (needed > share) return false;
      }
      // The whole label must also fit in the two lines a segment allows;
      // otherwise it would end in an ellipsis (e.g. a three-word Swahili
      // label at 2x text). Then the row scrolls instead.
      final inner = share - 2 * padding;
      if (inner <= 0) return false;
      final label = TextPainter(
        text: TextSpan(text: opt.$2, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 2,
      )..layout(maxWidth: inner);
      final cut = label.didExceedMaxLines;
      label.dispose();
      if (cut) return false;
    }
    return true;
  }

  Widget _option(
    BuildContext context,
    (String, String) opt, {
    required bool scroll,
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final selected = opt.$1 == value;
    final text = Text(
      opt.$2,
      maxLines: scroll ? 1 : 2,
      softWrap: !scroll,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: theme.textTheme.labelLarge?.copyWith(
        fontSize: compact ? _compactFontSize : null,
        color: selected
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurfaceVariant,
        fontWeight: selected ? FontWeight.w700 : null,
      ),
    );
    final tile = Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: opt.$2,
      excludeSemantics: true,
      onTap: () => onChanged(opt.$1),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => onChanged(opt.$1),
            borderRadius: BorderRadius.circular(FFTokens.radiusFull),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
              child: AnimatedContainer(
                duration: FFTokens.motionFast,
                curve: FFTokens.motionCurve,
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? _compactPadding : _optionPadding,
                  vertical: FFTokens.spacingSm + 2,
                ),
                // Light system: a solid primary thumb (ink on light, Volt on
                // dark) on a card-coloured pill track.
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                ),
                child: text,
              ),
            ),
          ),
        ),
      ),
    );
    if (!scroll) return Flexible(child: tile);
    // Keep the chosen segment in view when the row scrolls. Only this row
    // scrolls: Scrollable.ensureVisible would also scroll every scrollable
    // around it, so choosing a segment made the page jump (Activity).
    return Builder(
      builder: (ctx) {
        if (selected) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!ctx.mounted) return;
            final row = Scrollable.maybeOf(ctx, axis: Axis.horizontal);
            final box = ctx.findRenderObject();
            if (row == null || box == null || !box.attached) return;
            row.position.ensureVisible(
              box,
              alignment: 0.5,
              duration: FFTokens.motionFast,
            );
          });
        }
        return tile;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The selected label is the widest (bold), so measure with it.
    final measure = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final compactMeasure = measure?.copyWith(fontSize: _compactFontSize);
    return Container(
      // Vertical padding lives on each option's tap area, so the whole track
      // height is tappable.
      padding: const EdgeInsets.symmetric(horizontal: FFTokens.spacingXs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(FFTokens.radiusFull),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final regular = _fits(
            context,
            constraints.maxWidth,
            measure,
            _optionPadding,
          );
          final compact =
              !regular &&
              _fits(
                context,
                constraints.maxWidth,
                compactMeasure,
                _compactPadding,
              );
          final scroll = !regular && !compact;
          final row = IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final opt in options)
                  _option(context, opt, scroll: scroll, compact: compact),
              ],
            ),
          );
          if (!scroll) return row;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: row,
          );
        },
      ),
    );
  }
}
