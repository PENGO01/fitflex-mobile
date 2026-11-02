import 'package:flutter/material.dart';

import '../design_tokens.dart';

class BarDatum {
  final String label;
  final num value;

  /// Read aloud and shown when the bar is selected, e.g. "Week of 8 Sep: 210
  /// active minutes".
  final String description;

  const BarDatum(this.label, this.value, this.description);
}

/// Single-series bar chart built from plain widgets: thin bars with rounded
/// data ends on a recessive baseline, one label under each bar, and the
/// selected bar's value called out above the plot. Tap a bar to select it;
/// the latest bar is selected by default.
class ActivityBarChart extends StatefulWidget {
  const ActivityBarChart({
    super.key,
    required this.data,
    this.height = 140,
    this.formatValue,
    this.wideLabels = false,
  });

  final List<BarDatum> data;
  final double height;
  final String Function(num value)? formatValue;

  /// Each label is centred under its bar and may be wider than the bar, so
  /// it is never clipped ("12 Oct" under a thin bar). The caller leaves
  /// labels empty to thin them out so they do not overlap (vendor reports,
  /// UAT D5). Off: one clipped label per bar, as before.
  final bool wideLabels;

  @override
  State<ActivityBarChart> createState() => _ActivityBarChartState();
}

class _ActivityBarChartState extends State<ActivityBarChart> {
  int? _selected;

  @override
  void didUpdateWidget(ActivityBarChart old) {
    super.didUpdateWidget(old);
    if (old.data.length != widget.data.length) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data;
    if (data.isEmpty) return const SizedBox.shrink();
    final selected = _selected ?? data.length - 1;
    final max = data.map((d) => d.value).fold<num>(0, (a, b) => b > a ? b : a);
    final barColor = theme.colorScheme.primary;
    final mutedBar = theme.colorScheme.onSurface.withValues(alpha: 0.12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected value readout — the one direct label on the chart.
        Semantics(
          liveRegion: true,
          child: Text(
            data[selected].description,
            key: const Key('bar-chart-readout'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        SizedBox(
          height: widget.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < data.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == selected,
                    label: data[i].description,
                    child: GestureDetector(
                      key: Key('bar-$i'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _selected = i),
                      child: Padding(
                        // 2px surface gap each side between adjacent bars.
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: max <= 0
                                ? 0.02
                                : (data[i].value / max).clamp(0.02, 1.0),
                            widthFactor: 0.6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: data[i].value <= 0
                                    ? mutedBar
                                    : i == selected
                                    ? barColor
                                    : barColor.withValues(alpha: 0.55),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: FFTokens.spacingXs),
        ExcludeSemantics(
          child: widget.wideLabels
              ? _wideLabels(context, selected)
              : Row(
                  children: [
                    for (var i = 0; i < data.length; i++)
                      Expanded(
                        child: Text(
                          data[i].label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: i == selected
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Labels centred on their bars, as wide as they need (up to 4 bars).
  Widget _wideLabels(BuildContext context, int selected) {
    final theme = Theme.of(context);
    final data = widget.data;
    return LayoutBuilder(
      builder: (context, box) {
        final slot = box.maxWidth / data.length;
        final labelWidth = (slot * 4).clamp(slot, box.maxWidth).toDouble();
        TextStyle? style(int i) => theme.textTheme.labelSmall?.copyWith(
          color: i == selected
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Gives the row its height.
            Opacity(opacity: 0, child: Text('0', style: style(0))),
            for (var i = 0; i < data.length; i++)
              if (data[i].label.isNotEmpty)
                Positioned(
                  left: (slot * (i + 0.5) - labelWidth / 2)
                      .clamp(0.0, box.maxWidth - labelWidth)
                      .toDouble(),
                  width: labelWidth,
                  child: Text(
                    data[i].label,
                    key: Key('bar-label-$i'),
                    textAlign: slot * (i + 0.5) < labelWidth / 2
                        ? TextAlign.left
                        : slot * (i + 0.5) > box.maxWidth - labelWidth / 2
                        ? TextAlign.right
                        : TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: style(i),
                  ),
                ),
          ],
        );
      },
    );
  }
}
