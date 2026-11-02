// Vendor reports · S6: the pieces every report screen shares — period,
// channel and grouping controls (§3), the header line, figures, share bars
// and the chart with its spoken summary (§12). Design system V2 only:
// FFCard, FFPill, FFAlert, FFBadge, FFBarChart and FFTokens / FFToneTheme.
import 'package:flutter/material.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/tone_theme.dart';
import '../stock/stock_options.dart' show fillIn, eatToday;
import 'report_period.dart';

/// "TSh 1,250,000"; a negative amount with a real minus sign before it:
/// "−TSh 39,000". The space after TSh does not break (UAT D6), so the sign,
/// the currency and the number always stay on one line.
String reportMoney(num value) {
  final amount = formatCurrency(value.abs()).replaceFirst(' ', '\u00A0');
  return value < 0 ? '−$amount' : amount;
}

/// A counted string: `{key}One` for exactly 1 in English ("1 sale"), else
/// [key]; `{n}` filled with [n] (UAT D10). Swahili keeps one form.
String reportPlural(
  BuildContext context,
  String key,
  num n, [
  Map<String, Object?> values = const {},
]) {
  final one = '${key}One';
  final t = context.tr;
  final template = n == 1 && t(one) != one ? t(one) : t(key);
  return fillIn(template, {...values, 'n': reportCount(n)});
}

/// A count with thousands separators.
String reportCount(num value) => formatMoney(value);

/// The app's language code ('en' / 'sw').
String reportLang(BuildContext context) =>
    FFLocaleScope.of(context).locale.languageCode == 'sw' ? 'sw' : 'en';

const _presetKeys = {
  ReportPreset.today: 'vendor.reports.preset.today',
  ReportPreset.yesterday: 'vendor.reports.preset.yesterday',
  ReportPreset.thisWeek: 'vendor.reports.preset.thisWeek',
  ReportPreset.lastWeek: 'vendor.reports.preset.lastWeek',
  ReportPreset.thisMonth: 'vendor.reports.preset.thisMonth',
  ReportPreset.lastMonth: 'vendor.reports.preset.lastMonth',
  ReportPreset.custom: 'vendor.reports.preset.custom',
};

/// The channel values the API takes, with their words.
const reportChannels = [
  ('all', 'vendor.reports.channel.all'),
  ('app', 'vendor.reports.channel.app'),
  ('walk_in', 'vendor.reports.channel.walkIn'),
];

const _groupKeys = {
  ReportGroupBy.day: 'vendor.reports.group.day',
  ReportGroupBy.week: 'vendor.reports.group.week',
  ReportGroupBy.month: 'vendor.reports.group.month',
};

/// A selectable pill read as "{group}: {label}" with its selected state
/// (§12: "Period: This month, selected"). At least 48dp to tap.
class ReportChoicePill extends StatelessWidget {
  const ReportChoicePill({
    super.key,
    required this.group,
    required this.label,
    required this.selected,
    this.onTap,
    this.focusNode,
  });

  final String group;
  final String label;
  final bool selected;
  final FocusNode? focusNode;

  /// Null: the choice is not available (shown faded, not tappable).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: '$group: $label',
      onTap: onTap,
      excludeSemantics: true,
      child: enabled
          ? FFPill(
              label: label,
              filled: selected,
              onTap: onTap,
              focusNode: focusNode,
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Center(
                widthFactor: 1,
                child: Opacity(
                  opacity: 0.45,
                  child: FFPill(label: label, filled: selected),
                ),
              ),
            ),
    );
  }
}

/// Period presets (+ Choose dates), channel and grouping (§3). Calls back
/// with the new choice; a custom range the server would refuse is shown
/// as an inline error and not applied (the figures stay).
class ReportControls extends StatefulWidget {
  const ReportControls({
    super.key,
    required this.period,
    required this.onPeriod,
    this.channel,
    this.onChannel,
    this.groupBy,
    this.onGroupBy,
    this.periodEnabled = true,
    this.serverError,
    this.periodFocus,
    this.now,
  });

  /// Focus for the selected period pill ("Try another period", UAT D14).
  final FocusNode? periodFocus;

  final ReportPeriod period;
  final ValueChanged<ReportPeriod> onPeriod;

  /// Null hides the channel pills (no walk-in channel, §0.1).
  final String? channel;
  final ValueChanged<String>? onChannel;

  /// Null hides the grouping pills (only Sales and Profit group).
  final ReportGroupBy? groupBy;
  final ValueChanged<ReportGroupBy>? onGroupBy;

  /// False: the period does not apply (Stock value, §8.1).
  final bool periodEnabled;

  /// The server refused the period: the words key to show.
  final String? serverError;

  /// Test clock.
  final DateTime? now;

  @override
  State<ReportControls> createState() => _ReportControlsState();
}

class _ReportControlsState extends State<ReportControls> {
  String? _rangeError;

  Future<void> _pickRange() async {
    final today = eatToday(widget.now);
    final last = DateTime(today.year, today.month, today.day);
    final current = widget.period;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 5),
      lastDate: last,
      initialDateRange: DateTimeRange(
        start: DateTime(
          current.from.year,
          current.from.month,
          current.from.day,
        ),
        end: DateTime(current.to.year, current.to.month, current.to.day),
      ),
      helpText: context.tr('vendor.reports.preset.custom'),
    );
    if (picked == null || !mounted) return;
    final from = DateTime.utc(
      picked.start.year,
      picked.start.month,
      picked.start.day,
    );
    final to = DateTime.utc(picked.end.year, picked.end.month, picked.end.day);
    final problem = checkRange(from, to, now: widget.now);
    if (problem != null) {
      setState(
        () => _rangeError = switch (problem) {
          RangeProblem.tooLong => 'vendor.reports.rangeTooLong',
          RangeProblem.future => 'vendor.reports.rangeFuture',
          RangeProblem.toBeforeFrom => 'vendor.reports.rangeOrder',
        },
      );
      return;
    }
    setState(() => _rangeError = null);
    widget.onPeriod(ReportPeriod.custom(from, to));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final periodGroup = context.tr('vendor.reports.period');
    final error = _rangeError ?? widget.serverError;
    final children = <Widget>[
      Wrap(
        key: const Key('reports-period-pills'),
        spacing: FFTokens.spacingXs,
        runSpacing: FFTokens.spacing2xs,
        children: [
          for (final p in ReportPreset.values)
            ReportChoicePill(
              key: Key('reports-preset-${p.name}'),
              group: periodGroup,
              label: context.tr(_presetKeys[p]!),
              selected: widget.period.preset == p,
              focusNode: widget.period.preset == p ? widget.periodFocus : null,
              onTap: !widget.periodEnabled
                  ? null
                  : p == ReportPreset.custom
                  ? _pickRange
                  : () {
                      setState(() => _rangeError = null);
                      widget.onPeriod(ReportPeriod.preset(p, now: widget.now));
                    },
            ),
        ],
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingXs),
          child: Semantics(
            liveRegion: true,
            child: Text(
              context.tr(error),
              key: const Key('reports-range-error'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ),
      if (widget.channel != null && widget.onChannel != null) ...[
        const SizedBox(height: FFTokens.spacingXs),
        Wrap(
          key: const Key('reports-channel-pills'),
          spacing: FFTokens.spacingXs,
          runSpacing: FFTokens.spacing2xs,
          children: [
            for (final c in reportChannels)
              ReportChoicePill(
                key: Key('reports-channel-${c.$1}'),
                group: context.tr('vendor.reports.channel'),
                label: context.tr(c.$2),
                selected: widget.channel == c.$1,
                onTap: () => widget.onChannel!(c.$1),
              ),
          ],
        ),
      ],
      if (widget.groupBy != null && widget.onGroupBy != null) ...[
        const SizedBox(height: FFTokens.spacingXs),
        Wrap(
          key: const Key('reports-group-pills'),
          spacing: FFTokens.spacingXs,
          runSpacing: FFTokens.spacing2xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ExcludeSemantics(
              child: Text(
                context.tr('vendor.reports.group'),
                style: theme.textTheme.labelMedium,
              ),
            ),
            for (final g in ReportGroupBy.values)
              ReportChoicePill(
                key: Key('reports-group-${g.name}'),
                group: context.tr('vendor.reports.group'),
                label: context.tr(_groupKeys[g]!),
                selected: widget.groupBy == g,
                onTap: widget.period.allows(g)
                    ? () => widget.onGroupBy!(g)
                    : null,
              ),
          ],
        ),
        if (ReportGroupBy.values.any((g) => !widget.period.allows(g)))
          Text(
            context.tr('vendor.reports.groupTooMany'),
            key: const Key('reports-group-helper'),
            style: theme.textTheme.bodySmall,
          ),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// "1–31 Oct 2026 (so far) · All sales · Updated 2:05 pm" with a refresh
/// button (§3, §9). [channel] null: the channel line is [channelText].
class ReportHeaderLine extends StatelessWidget {
  const ReportHeaderLine({
    super.key,
    required this.period,
    this.channel,
    this.channelText,
    this.generatedAt,
    this.inProgress = false,
    this.onRefresh,
    this.showPeriod = true,
  });

  final ReportPeriod period;
  final String? channel;
  final String? channelText;
  final DateTime? generatedAt;
  final bool inProgress;
  final VoidCallback? onRefresh;
  final bool showPeriod;

  @override
  Widget build(BuildContext context) {
    final lang = reportLang(context);
    final theme = Theme.of(context);
    final parts = <String>[
      if (showPeriod)
        inProgress
            ? '${periodInWords(period.from, period.to, lang)} '
                  '${context.tr('vendor.reports.inProgress')}'
            : periodInWords(period.from, period.to, lang),
      channelText ?? channelWords(context, channel),
    ];
    final updated = generatedAt == null
        ? null
        : fillIn(context.tr('vendor.reports.updated'), {
            'time': reportTime(generatedAt!, lang),
          });
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                parts.join(' · '),
                key: const Key('reports-header-line'),
                style: theme.textTheme.titleSmall,
              ),
              if (updated != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    updated,
                    key: const Key('reports-updated'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        if (onRefresh != null)
          IconButton(
            key: const Key('reports-refresh'),
            tooltip: updated == null
                ? context.tr('vendor.reports.refresh')
                : '${context.tr('vendor.reports.refresh')}, $updated',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
      ],
    );
  }
}

/// "All sales" / "App sales" / "Shop sales".
String channelWords(BuildContext context, String? channel) =>
    context.tr(switch (channel) {
      'app' => 'vendor.reports.channel.appSales',
      'walk_in' => 'vendor.reports.channel.shopSales',
      _ => 'vendor.reports.channel.allSales',
    });

/// One figure: a label over a value; the value never wraps mid-number and
/// the label wraps rather than truncating (§13.7).
class ReportFigure extends StatelessWidget {
  const ReportFigure({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.large = false,
  });

  final String label;
  final String value;
  final String? sub;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: FFTokens.spacing2xs),
          Text(
            value,
            softWrap: false,
            overflow: TextOverflow.visible,
            style:
                (large
                        ? theme.textTheme.headlineSmall
                        : theme.textTheme.titleMedium)
                    ?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
          ),
          if (sub != null) ...[
            const SizedBox(height: FFTokens.spacing2xs),
            Text(sub!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Figures two per row on a phone, one per row at large text (§12).
class ReportFigureGrid extends StatelessWidget {
  const ReportFigureGrid({super.key, required this.figures});

  final List<Widget> figures;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final columns = scale >= 1.6 ? 1 : 2;
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - FFTokens.spacingMd * (columns - 1)) / columns;
        return Wrap(
          spacing: FFTokens.spacingMd,
          runSpacing: FFTokens.spacingMd,
          children: [
            for (final f in figures)
              SizedBox(
                width: w,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: w),
                    child: f,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A label and a value on one line, the value on its own line when they do
/// not fit side by side. Read as one.
class ReportRow extends StatelessWidget {
  const ReportRow({
    super.key,
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = strong
        ? theme.textTheme.titleSmall
        : theme.textTheme.bodyMedium;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: FFTokens.spacing2xs),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: FFTokens.spacingSm,
          children: [
            Text(label, style: style),
            Text(
              value,
              softWrap: false,
              style: style?.copyWith(
                fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled card. [onTap] makes the whole card a button (§9) read as one
/// ("Sales report card. … Open details") with a chevron.
class ReportCard extends StatelessWidget {
  const ReportCard({
    super.key,
    required this.title,
    required this.child,
    this.onTap,
    this.semanticSummary,
  });

  final String title;
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticSummary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            if (onTap != null) const Icon(Icons.chevron_right),
          ],
        ),
        const SizedBox(height: FFTokens.spacingSm),
        child,
      ],
    );
    final card = FFCard(child: body);
    if (onTap == null) return card;
    // The template adds its own full stops: a summary ending in one would
    // be read "Not in profit.. Open details" (UAT D14).
    var summary = (semanticSummary ?? '').trim();
    while (summary.endsWith('.')) {
      summary = summary.substring(0, summary.length - 1).trimRight();
    }
    final label = fillIn(context.tr('vendor.reports.a11y.card'), {
      'section': title,
      'summary': summary,
    });
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// A share bar: "M-Pesa · TSh 120,000 · 40.0% · 6" with a bar whose width
/// is the share; the % is always in the text (§8.4).
class ReportShareBar extends StatelessWidget {
  const ReportShareBar({
    super.key,
    required this.label,
    required this.amount,
    required this.sharePct,
    this.count,
  });

  final String label;
  final num amount;
  final num sharePct;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = FFToneTheme.of(context).brand;
    final pct = '${sharePct.toStringAsFixed(1)}%';
    final text = [
      label,
      reportMoney(amount),
      pct,
      if (count != null)
        reportPlural(context, 'vendor.reports.countTimes', count!),
    ].join(' · ');
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: theme.textTheme.bodyMedium),
            const SizedBox(height: FFTokens.spacing2xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(FFTokens.radiusFull),
              child: LinearProgressIndicator(
                value: (sharePct / 100).clamp(0.0, 1.0).toDouble(),
                minHeight: 8,
                color: theme.colorScheme.primary,
                backgroundColor: brand.bg,
                semanticsLabel: label,
                semanticsValue: pct,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One bar of a report chart.
class ReportBar {
  const ReportBar({
    required this.start,
    required this.end,
    required this.value,
    required this.description,
  });
  final DateTime start;
  final DateTime end;
  final num value;
  final String description;
}

/// The label under a bar: a day ("12"), a week ("12 Oct") or a month
/// ("Oct").
String barLabel(DateTime start, ReportGroupBy g, String lang) => switch (g) {
  ReportGroupBy.day => '${start.day}',
  ReportGroupBy.week => dayInWords(start, lang),
  ReportGroupBy.month => dayInWords(start, lang).split(' ').last,
};

/// The words of one bucket: "12 Oct", "Week of 12 Oct", "Oct 2026".
String bucketWords(
  BuildContext context,
  DateTime start,
  DateTime end,
  ReportGroupBy g,
) {
  final lang = reportLang(context);
  return switch (g) {
    ReportGroupBy.day => dayInWords(start, lang),
    ReportGroupBy.week => fillIn(context.tr('vendor.reports.weekOf'), {
      'date': dayInWords(start, lang),
    }),
    ReportGroupBy.month => periodInWords(start, end, lang),
  };
}

/// The bar chart with its spoken summary (§12: "{figure} by {group},
/// {period}. Highest: {date}, {amount}. Total {total}. Table below."), or
/// the "too many days" note when there are more than 31 bars.
class ReportChart extends StatelessWidget {
  const ReportChart({
    super.key,
    required this.bars,
    required this.figure,
    required this.groupBy,
    required this.period,
    required this.total,
    this.height = 160,
  });

  final List<ReportBar> bars;
  final String figure;
  final ReportGroupBy groupBy;
  final ReportPeriod period;
  final num total;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return const SizedBox.shrink();
    if (bars.length > reportChartMaxBars) {
      return Text(
        context.tr('vendor.reports.chartTooMany'),
        key: const Key('reports-chart-too-many'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final lang = reportLang(context);
    var top = bars.first;
    for (final b in bars) {
      if (b.value > top.value) top = b;
    }
    final summary = fillIn(context.tr('vendor.reports.chartSummary'), {
      'figure': figure,
      'group': context.tr(_groupKeys[groupBy]!).toLowerCase(),
      'period': periodInWords(period.from, period.to, lang),
      'date': bucketWords(context, top.start, top.end, groupBy),
      'amount': reportMoney(top.value),
      'total': reportMoney(total),
    });
    return Semantics(
      key: const Key('reports-chart'),
      label: summary,
      container: true,
      child: LayoutBuilder(
        builder: (context, box) {
          final step = labelStep(
            bars: bars.length,
            width: box.maxWidth,
            groupBy: groupBy,
            textScale: MediaQuery.textScalerOf(context).scale(100) / 100,
          );
          return ActivityBarChart(
            height: height,
            wideLabels: true,
            data: [
              for (var i = 0; i < bars.length; i++)
                BarDatum(
                  i % step == 0 ? barLabel(bars[i].start, groupBy, lang) : '',
                  bars[i].value < 0 ? 0 : bars[i].value,
                  bars[i].description,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Show every [labelStep]th bar label so whole labels fit side by side
/// (UAT D5): a day number needs about 24px, "12 Oct" 52px, "Oct" 36px, more
/// at larger text. 1 shows them all.
int labelStep({
  required int bars,
  required double width,
  required ReportGroupBy groupBy,
  double textScale = 1,
}) {
  if (bars <= 1 || width <= 0) return 1;
  final need =
      switch (groupBy) {
        ReportGroupBy.day => 24.0,
        ReportGroupBy.week => 52.0,
        ReportGroupBy.month => 36.0,
      } *
      textScale;
  final step = (bars * need / width).ceil();
  return step < 1 ? 1 : step;
}

/// A neutral note line (period basis, footnotes).
class ReportNote extends StatelessWidget {
  const ReportNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

/// Skeleton cards while a report loads (§11), read as "Loading reports".
class ReportLoading extends StatelessWidget {
  const ReportLoading({super.key, this.count = 3});
  final int count;

  @override
  Widget build(BuildContext context) => FFSkeletonList(
    key: const Key('reports-loading'),
    count: count,
    semanticLabel: context.tr('vendor.reports.loading'),
  );
}
