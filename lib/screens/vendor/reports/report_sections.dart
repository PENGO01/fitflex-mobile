// Vendor reports · S6: the body of each report section (spec §5–§8), as
// card lists (phone) from the server's answer. The server computes every
// figure; nothing here adds pages up or fills in a missing cost with 0.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../sales/sales_widgets.dart' show posRoute;
import '../stock/stock_options.dart' show canVendor, fillIn;
import 'report_models.dart';
import 'report_period.dart';
import 'report_widgets.dart';

/// Negative figures (discounts, refunds, commission) with a minus sign.
String _minus(num v) => v == 0 ? reportMoney(0) : reportMoney(-v);

/// The server says this vendor has never sold (`hasEverSold: false`, top
/// level of every report answer). Absent or anything else: not first use.
bool neverSold(Map? answer) => answer?['hasEverSold'] == false;

/// The first-use state (spec §11, UAT D2): "Your reports fill up as you
/// sell…" with Record a sale (walk-in sales on + `sales`) and Add products
/// (`products`).
class ReportFirstUse extends StatelessWidget {
  const ReportFirstUse({super.key, required this.access});

  final ReportAccess access;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final actions = <Widget>[
      if (access.walkIn && canVendor(context, 'sales'))
        FFButton(
          key: const Key('reports-first-record-sale'),
          label: t('vendor.reports.recordSale'),
          icon: Icons.point_of_sale_outlined,
          onPressed: () => context.push(posRoute),
        ),
      if (canVendor(context, 'products'))
        FFButton(
          key: const Key('reports-first-add-products'),
          label: t('vendor.reports.addProducts'),
          icon: Icons.add,
          variant: FFButtonVariant.secondary,
          onPressed: () => context.go('/vendor/home?open=products'),
        ),
    ];
    return Semantics(
      container: true,
      child: FFEmptyState(
        key: const Key('reports-first-use'),
        icon: Icons.bar_chart_outlined,
        title: t('vendor.reports.emptyFirst'),
        action: actions.isEmpty
            ? null
            : Wrap(
                alignment: WrapAlignment.center,
                spacing: FFTokens.spacingSm,
                runSpacing: FFTokens.spacingSm,
                children: actions,
              ),
      ),
    );
  }
}

/// Back to the period control: scrolled to the top and the selected
/// period pill focused (UAT D14).
void focusPeriod(BuildContext context, FocusNode node) {
  final position = Scrollable.maybeOf(context)?.position;
  position?.animateTo(
    0,
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOut,
  );
  node.requestFocus();
}

/// A profit figure. Only a null profit can mean "no cost price", and only
/// when something was sold ([sold]): the server also sends null for a day or
/// a product with no sales, which has nothing to explain and reads "—" (UAT
/// D1, N3, N3b). A costed sale that nets to zero is a real "TSh 0".
String profitWords(BuildContext context, Map? m, {required bool sold}) {
  final v = maybeNum(m, 'profitTzs');
  if (v != null) return reportMoney(v);
  return sold
      ? '— · ${context.tr('vendor.reports.profit.noCostHeading')}'
      : '—';
}

/// Sales in the `uncosted` block of a profit answer.
bool hasUncosted(Map? uncosted) =>
    numAt(uncosted, 'qty') != 0 || numAt(uncosted, 'revenueTzs') != 0;

/// An instant (ISO, UTC) as its EAT calendar day: "12 Oct 2026".
String eatDateWords(Object? iso, String lang) {
  final d = DateTime.tryParse(iso?.toString() ?? '');
  if (d == null) return '—';
  final eat = d.toUtc().add(const Duration(hours: 3));
  return formatDate(DateTime(eat.year, eat.month, eat.day), locale: lang);
}

/// A product's name with its variant and "(removed)".
String productWords(BuildContext context, Map row) {
  final name = row['name']?.toString() ?? '';
  final variant = row['variant']?.toString() ?? '';
  final base = variant.isEmpty ? name : '$name · $variant';
  return row['removed'] == true
      ? '$base ${context.tr('vendor.reports.removed')}'
      : base;
}

/// The cover badge + words (§6). "Reorder soon" uses the warning tone and
/// text, never colour alone.
Widget coverBadge(BuildContext context, Map row) {
  final c = coverWording(row);
  final words = c.n == null
      ? context.tr(c.key)
      : fillIn(context.tr(c.key), {'n': c.n});
  final children = <Widget>[
    if (c.soon)
      FFBadge(
        key: const Key('reports-reorder-soon'),
        label: context.tr('vendor.reports.reorderSoon'),
        tone: FFBadgeTone.warning,
      ),
    Text(words, style: Theme.of(context).textTheme.bodySmall),
  ];
  return Wrap(
    spacing: FFTokens.spacingSm,
    runSpacing: FFTokens.spacing2xs,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children,
  );
}

List<ReportBar> _bars(
  BuildContext context,
  List<Map<String, dynamic>> buckets,
  ReportGroupBy g,
  String valueKey,
  String Function(String when, Map<String, dynamic> bucket) describe,
) => [
  for (final b in buckets)
    if (parseDay(b['start']) != null)
      ReportBar(
        start: parseDay(b['start'])!,
        end: parseDay(b['end']) ?? parseDay(b['start'])!,
        value: numAt(b, valueKey),
        known: maybeNum(b, valueKey) != null,
        description: describe(
          bucketWords(
            context,
            parseDay(b['start'])!,
            parseDay(b['end']) ?? parseDay(b['start'])!,
            g,
          ),
          b,
        ),
      ),
];

const _gap = SizedBox(height: FFTokens.spacingMd);

// ── Sales (§5) ───────────────────────────────────────────────────────────

class SalesReportBody extends StatelessWidget {
  const SalesReportBody({
    super.key,
    required this.data,
    required this.period,
    required this.showChannels,
  });

  final Map<String, dynamic> data;
  final ReportPeriod period;

  /// The walk-in channel exists: App / Shop columns.
  final bool showChannels;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final totals = mapAt(data, 'totals') ?? const {};
    final voided = mapAt(totals, 'voided');
    final g = groupByOf(data['groupBy']) ?? period.autoGrouping;
    final buckets = listAt(data, 'buckets');
    final vat = numAt(totals, 'vatIncludedTzs');
    final count = numAt(totals, 'saleCount') + numAt(totals, 'orderCount');
    final byChannel = mapAt(data, 'byChannel');
    final app = mapAt(byChannel, 'app');
    final shop = mapAt(byChannel, 'walkIn');
    final net = numAt(totals, 'netTzs');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFCard(
          child: ReportFigureGrid(
            figures: [
              ReportFigure(
                label: t('vendor.reports.net'),
                value: reportMoney(net),
                large: true,
              ),
              ReportFigure(
                label: t('vendor.reports.gross'),
                value: reportMoney(numAt(totals, 'grossTzs')),
              ),
              ReportFigure(
                label: t('vendor.reports.discounts'),
                value: _minus(numAt(totals, 'discountTzs')),
              ),
              ReportFigure(
                label: t('vendor.reports.refunds'),
                value: _minus(numAt(totals, 'refundTzs')),
              ),
              if (vat > 0)
                ReportFigure(
                  key: const Key('reports-sales-vat'),
                  label: t('vendor.reports.vatIncluded'),
                  value: reportMoney(vat),
                ),
              ReportFigure(
                label: t('vendor.reports.salesCount'),
                value: reportCount(count),
              ),
              ReportFigure(
                label: t('vendor.reports.itemsSold'),
                value: reportCount(numAt(totals, 'itemsSold')),
              ),
            ],
          ),
        ),
        if (numAt(voided, 'count') > 0) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFAlert(
            key: const Key('reports-voided'),
            message: reportPlural(
              context,
              'vendor.reports.voided',
              numAt(voided, 'count'),
              {'amount': reportMoney(numAt(voided, 'totalTzs'))},
            ),
          ),
        ],
        _gap,
        FFCard(
          child: ReportChart(
            figure: t('vendor.reports.net'),
            groupBy: g,
            period: period,
            total: net,
            bars: _bars(
              context,
              buckets,
              g,
              'netTzs',
              (when, b) => fillIn(t('vendor.reports.barNet'), {
                'when': when,
                'amount': reportMoney(numAt(b, 'netTzs')),
              }),
            ),
          ),
        ),
        _gap,
        FFSectionTitle(t('vendor.reports.sales.table')),
        for (final b in buckets)
          if (parseDay(b['start']) != null)
            _SalesBucketCard(
              bucket: b,
              when: bucketWords(
                context,
                parseDay(b['start'])!,
                parseDay(b['end']) ?? parseDay(b['start'])!,
                g,
              ),
              showChannels: showChannels,
            ),
        if (showChannels && app != null && shop != null) ...[
          _gap,
          ReportCard(
            key: const Key('reports-channel-split'),
            title: t('vendor.reports.channelSplit'),
            child: Column(
              children: [
                for (final c in [
                  (t('vendor.reports.channel.app'), app),
                  (t('vendor.reports.channel.walkIn'), shop),
                ])
                  ReportRow(
                    label: c.$1,
                    value: [
                      reportMoney(numAt(c.$2, 'netTzs')),
                      formatPct(
                        net == 0 ? 0 : numAt(c.$2, 'netTzs') * 100 / net,
                      ),
                      reportPlural(
                        context,
                        'vendor.reports.salesN',
                        numAt(c.$2, 'count'),
                      ),
                    ].join(' · '),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SalesBucketCard extends StatelessWidget {
  const _SalesBucketCard({
    required this.bucket,
    required this.when,
    required this.showChannels,
  });

  final Map<String, dynamic> bucket;
  final String when;
  final bool showChannels;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final app = mapAt(bucket, 'app');
    final shop = mapAt(bucket, 'walkIn');
    num sum(String k) => numAt(app, k) + numAt(shop, k);
    final vat = sum('vatIncludedTzs');
    final lines = <String>[
      if (showChannels)
        '${t('vendor.reports.appNet')} ${reportMoney(numAt(app, 'netTzs'))} · '
            '${t('vendor.reports.shopNet')} ${reportMoney(numAt(shop, 'netTzs'))}',
      fillIn(t('vendor.reports.grossLine'), {
        'g': reportMoney(sum('grossTzs')),
        'd': _minus(sum('discountTzs')),
        'r': _minus(sum('refundTzs')),
      }),
      if (vat > 0) '${t('vendor.reports.vatIncluded')} ${reportMoney(vat)}',
      '${reportPlural(context, 'vendor.reports.salesN', sum('count'))} · ${reportPlural(context, 'vendor.reports.itemsN', sum('itemsSold'))}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: MergeSemantics(
        child: FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReportRow(
                label: when,
                value: reportMoney(numAt(bucket, 'netTzs')),
                strong: true,
              ),
              for (final l in lines)
                Text(l, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Products (§6) ────────────────────────────────────────────────────────

class ProductReportRow extends StatelessWidget {
  const ProductReportRow({
    super.key,
    required this.row,
    required this.slow,
    required this.showChannels,
  });

  final Map<String, dynamic> row;
  final bool slow;
  final bool showChannels;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final lang = reportLang(context);
    final theme = Theme.of(context);
    final stock = row['stock'];
    final profit = maybeNum(row, 'profitTzs');
    // Profit is shown only to people who may see cost (the key is there).
    final showsProfit = row.containsKey('profitTzs');
    final units = numAt(row, 'unitsSold');
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: MergeSemantics(
        child: FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                productWords(context, row),
                style: theme.textTheme.titleSmall,
              ),
              if (slow && row['noSalesInPeriod'] == true)
                Text(
                  t('vendor.reports.noSalesPeriod'),
                  style: theme.textTheme.bodySmall,
                ),
              ReportRow(
                label: t('vendor.reports.unitsSold'),
                value: showChannels
                    ? '${reportCount(units)} '
                          '(${t('vendor.reports.channel.app')} '
                          '${reportCount(numAt(row, 'appUnits'))} · '
                          '${t('vendor.reports.channel.walkIn')} '
                          '${reportCount(numAt(row, 'walkInUnits'))})'
                    : reportCount(units),
              ),
              ReportRow(
                label: t('vendor.reports.revenue'),
                value: reportMoney(numAt(row, 'netRevenueTzs')),
              ),
              if (showsProfit)
                ReportRow(
                  key: const Key('reports-product-profit'),
                  label: t('vendor.reports.profit'),
                  value: profitWords(
                    context,
                    row,
                    sold: row['noSalesInPeriod'] != true,
                  ),
                ),
              // A costed product that nets to zero: TSh 0 and margin "—".
              if (showsProfit && profit != null)
                ReportRow(
                  key: const Key('reports-product-margin'),
                  label: t('vendor.reports.margin'),
                  value: formatPct(maybeNum(row, 'marginPct')),
                ),
              ReportRow(
                label: t('vendor.reports.lastSold'),
                value: row['lastSoldAt'] == null
                    ? t('vendor.reports.never')
                    : eatDateWords(row['lastSoldAt'], lang),
              ),
              ReportRow(
                label: t('vendor.reports.inStock'),
                value: stock is num ? reportCount(stock) : '—',
              ),
              const SizedBox(height: FFTokens.spacingXs),
              coverBadge(context, row),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Stock value (§8.1) ───────────────────────────────────────────────────

enum StockSort { value, stock, name }

class StockReportBody extends StatelessWidget {
  const StockReportBody({
    super.key,
    required this.data,
    required this.sort,
    required this.onSort,
    this.onAddCost,
  });

  final Map<String, dynamic> data;
  final StockSort sort;
  final ValueChanged<StockSort> onSort;

  /// "Add cost prices" (needs `products`); null hides the link.
  final VoidCallback? onAddCost;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final lang = reportLang(context);
    final totals = mapAt(data, 'totals') ?? const {};
    final atCost = maybeNum(totals, 'atCostTzs');
    // Cost is visible to this person when the server sent any cost key; a
    // row's missing or null cost is then "unknown", never 0.
    final costVisible =
        totals.containsKey('atCostTzs') ||
        data.containsKey('costUnknown') ||
        listAt(data, 'rows').any((r) => r.containsKey('costTzs'));
    final unknown = mapAt(data, 'costUnknown');
    final asOf = DateTime.tryParse(data['asOf']?.toString() ?? '');
    final rows = listAt(data, 'rows')
      ..sort(
        (a, b) => switch (sort) {
          StockSort.value => numAt(
            b,
            'valueAtRetailTzs',
          ).compareTo(numAt(a, 'valueAtRetailTzs')),
          StockSort.stock => numAt(b, 'stock').compareTo(numAt(a, 'stock')),
          StockSort.name => productWords(
            context,
            a,
          ).toLowerCase().compareTo(productWords(context, b).toLowerCase()),
        },
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (asOf != null)
          ReportNote(
            fillIn(t('vendor.reports.stock.asOf'), {
              'time': reportTime(asOf, lang),
            }),
          ),
        FFCard(
          child: ReportFigureGrid(
            figures: [
              ReportFigure(
                label: t('vendor.reports.stock.atRetail'),
                value: reportMoney(numAt(totals, 'atRetailTzs')),
                large: true,
              ),
              if (atCost != null)
                ReportFigure(
                  key: const Key('reports-stock-at-cost'),
                  label: t('vendor.reports.stock.atCost'),
                  value: reportMoney(atCost),
                  large: true,
                ),
              ReportFigure(
                label: t('vendor.reports.stock.units'),
                value: reportCount(numAt(totals, 'units')),
              ),
              ReportFigure(
                label: t('vendor.reports.view.products'),
                value: reportCount(numAt(totals, 'products')),
              ),
            ],
          ),
        ),
        if (unknown != null && numAt(unknown, 'count') > 0) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFAlert(
            key: const Key('reports-stock-cost-unknown'),
            message: reportPlural(
              context,
              'vendor.reports.stock.costUnknown',
              numAt(unknown, 'count'),
            ),
            tone: FFAlertTone.warning,
          ),
          if (onAddCost != null)
            Align(
              alignment: Alignment.centerLeft,
              child: FFButton(
                key: const Key('reports-add-cost'),
                label: t('vendor.reports.addCost'),
                variant: FFButtonVariant.ghost,
                onPressed: onAddCost,
              ),
            ),
        ],
        _gap,
        FFSegmented(
          value: sort.name,
          options: [
            ('value', t('vendor.reports.sort.value')),
            ('stock', t('vendor.reports.sort.stock')),
            ('name', t('vendor.reports.sort.name')),
          ],
          onChanged: (v) => onSort(StockSort.values.byName(v)),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: MergeSemantics(
              child: FFCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      productWords(context, r),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    ReportRow(
                      label: t('vendor.reports.inStock'),
                      value: reportCount(numAt(r, 'stock')),
                    ),
                    ReportRow(
                      label: t('vendor.reports.sellingPrice'),
                      value: reportMoney(numAt(r, 'priceTzs')),
                    ),
                    ReportRow(
                      label: t('vendor.reports.stock.atRetail'),
                      value: reportMoney(numAt(r, 'valueAtRetailTzs')),
                    ),
                    // Cost columns only when the server sent the keys.
                    if (costVisible)
                      maybeNum(r, 'costTzs') == null
                          ? Padding(
                              padding: const EdgeInsets.only(
                                top: FFTokens.spacingXs,
                              ),
                              child: FFBadge(
                                label: t('vendor.reports.costPriceUnknown'),
                                tone: FFBadgeTone.warning,
                              ),
                            )
                          : ReportRow(
                              label: t('vendor.reports.costPrice'),
                              value: reportMoney(maybeNum(r, 'costTzs')!),
                            ),
                    if (maybeNum(r, 'valueAtCostTzs') != null)
                      ReportRow(
                        label: t('vendor.reports.stock.atCost'),
                        value: reportMoney(maybeNum(r, 'valueAtCostTzs')!),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Profit (§8.2, canSeeCost only) ───────────────────────────────────────

class ProfitReportBody extends StatelessWidget {
  const ProfitReportBody({
    super.key,
    required this.data,
    required this.period,
    this.onAddCost,
  });

  final Map<String, dynamic> data;
  final ReportPeriod period;

  /// "Add cost prices" (cost rights + `products`); null hides the link.
  final VoidCallback? onAddCost;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final totals = mapAt(data, 'totals') ?? const {};
    final uncosted = mapAt(data, 'uncosted');
    final g = groupByOf(data['groupBy']) ?? period.autoGrouping;
    final buckets = listAt(data, 'buckets');
    final profit = numAt(totals, 'profitTzs');
    final byProduct = listAt(data, 'byProduct');
    final noCost = listAt(data, 'uncostedProducts');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data['hasVat'] == true)
          ReportNote(t('vendor.reports.profit.noVat')),
        FFCard(
          child: ReportFigureGrid(
            figures: [
              ReportFigure(
                label: t('vendor.reports.profit'),
                value: profitWords(
                  context,
                  totals,
                  sold: hasUncosted(uncosted),
                ),
                sub: t('vendor.reports.profitHint'),
                large: true,
              ),
              ReportFigure(
                label: t('vendor.reports.margin'),
                value: formatPct(maybeNum(totals, 'marginPct')),
              ),
              ReportFigure(
                label: t('vendor.reports.netExVat'),
                value: reportMoney(numAt(totals, 'netExVatTzs')),
              ),
              ReportFigure(
                label: t('vendor.reports.commission'),
                value: _minus(numAt(totals, 'commissionTzs')),
              ),
              ReportFigure(
                label: t('vendor.reports.cogs'),
                value: _minus(numAt(totals, 'costTzs')),
              ),
            ],
          ),
        ),
        // Never merged with profit (§8.2): its own block.
        if (hasUncosted(uncosted)) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFAlert(
            key: const Key('reports-profit-uncosted'),
            message: reportPlural(
              context,
              'vendor.reports.profit.uncosted',
              numAt(uncosted, 'qty'),
              {'amount': reportMoney(numAt(uncosted, 'revenueTzs'))},
            ),
            tone: FFAlertTone.warning,
          ),
          if (onAddCost != null)
            Align(
              alignment: Alignment.centerLeft,
              child: FFButton(
                key: const Key('reports-add-cost'),
                label: t('vendor.reports.addCost'),
                variant: FFButtonVariant.ghost,
                onPressed: onAddCost,
              ),
            ),
        ],
        // No day has a known profit: there is nothing to chart.
        if (buckets.any((b) => maybeNum(b, 'profitTzs') != null)) ...[
          _gap,
          FFCard(
            child: ReportChart(
              figure: t('vendor.reports.profit'),
              groupBy: g,
              period: period,
              total: profit,
              bars: _bars(context, buckets, g, 'profitTzs', (when, b) {
                final v = maybeNum(b, 'profitTzs');
                if (v != null) {
                  return fillIn(t('vendor.reports.barProfit'), {
                    'when': when,
                    'amount': reportMoney(v),
                  });
                }
                return fillIn(
                  t(
                    numAt(b, 'uncostedRevenueTzs') != 0
                        ? 'vendor.reports.barNoCost'
                        : 'vendor.reports.barNoSales',
                  ),
                  {'when': when},
                );
              }),
            ),
          ),
        ],
        _gap,
        FFSectionTitle(t('vendor.reports.profit.table')),
        for (final b in buckets)
          if (parseDay(b['start']) != null)
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
              child: MergeSemantics(
                child: FFCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReportRow(
                        label: bucketWords(
                          context,
                          parseDay(b['start'])!,
                          parseDay(b['end']) ?? parseDay(b['start'])!,
                          g,
                        ),
                        value: profitWords(
                          context,
                          b,
                          sold: numAt(b, 'uncostedRevenueTzs') != 0,
                        ),
                        strong: true,
                      ),
                      Text(
                        [
                          '${t('vendor.reports.netExVat')} ${reportMoney(numAt(b, 'netExVatTzs'))}',
                          '${t('vendor.reports.commission')} ${_minus(numAt(b, 'commissionTzs'))}',
                          '${t('vendor.reports.cogs')} ${_minus(numAt(b, 'costTzs'))}',
                          '${t('vendor.reports.margin')} ${formatPct(maybeNum(b, 'marginPct'))}',
                          if (numAt(b, 'uncostedRevenueTzs') > 0)
                            '${t('vendor.reports.uncostedSales')} ${reportMoney(numAt(b, 'uncostedRevenueTzs'))}',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        if (byProduct.isNotEmpty) ...[
          _gap,
          FFSectionTitle(t('vendor.reports.profit.byProduct')),
          for (final p in byProduct)
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
              child: MergeSemantics(
                child: FFCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReportRow(
                        label: productWords(context, p),
                        value: profitWords(context, p, sold: true),
                        strong: true,
                      ),
                      Text(
                        [
                          reportPlural(
                            context,
                            'vendor.reports.unitsN',
                            numAt(p, 'units'),
                          ),
                          '${t('vendor.reports.netExVat')} ${reportMoney(numAt(p, 'netExVatTzs'))}',
                          '${t('vendor.reports.cogs')} ${_minus(numAt(p, 'costTzs'))}',
                          '${t('vendor.reports.margin')} ${formatPct(maybeNum(p, 'marginPct'))}',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        if (noCost.isNotEmpty) ...[
          _gap,
          FFSectionTitle(t('vendor.reports.profit.noCostHeading')),
          for (final p in noCost)
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
              child: FFCard(
                child: ReportRow(
                  label:
                      '${productWords(context, p)} · '
                      '${reportPlural(context, 'vendor.reports.unitsN', numAt(p, 'units'))}',
                  value: reportMoney(numAt(p, 'revenueTzs')),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ── App sales after commission (§7) ──────────────────────────────────────

class PayoutsReportBody extends StatelessWidget {
  const PayoutsReportBody({super.key, required this.data, this.onStatement});

  final Map<String, dynamic> data;

  /// Opens the vendor's payout statements (a week on a statement).
  final VoidCallback? onStatement;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final lang = reportLang(context);
    final totals = mapAt(data, 'totals') ?? const {};
    final status = mapAt(data, 'status');
    final weeks = listAt(data, 'weeks');
    Widget state(String key, String labelKey) {
      final s = mapAt(status, key);
      return ReportRow(
        key: Key('reports-payouts-$key'),
        label: t(labelKey),
        value:
            '${reportMoney(numAt(s, 'payoutTzs'))} · '
            '${reportPlural(context, 'vendor.reports.ordersN', numAt(s, 'orders'))}',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportNote(t('vendor.reports.payouts.basis')),
        FFCard(
          child: ReportFigureGrid(
            figures: [
              ReportFigure(
                label: t('vendor.reports.youReceive'),
                value: reportMoney(numAt(totals, 'payoutTzs')),
                large: true,
              ),
              ReportFigure(
                label: t('vendor.reports.appSales'),
                value: reportMoney(numAt(totals, 'grossTzs')),
              ),
              ReportFigure(
                label: t('vendor.reports.commission'),
                value: _minus(numAt(totals, 'commissionTzs')),
              ),
              ReportFigure(
                label: t('vendor.reports.orders'),
                value: reportCount(numAt(totals, 'orderCount')),
              ),
            ],
          ),
        ),
        _gap,
        FFCard(
          child: Column(
            children: [
              state('notDelivered', 'vendor.reports.payouts.notDelivered'),
              state('waiting', 'vendor.reports.payouts.waiting'),
              state('paidOut', 'vendor.reports.payouts.paidOut'),
            ],
          ),
        ),
        _gap,
        FFSectionTitle(t('vendor.reports.payouts.byWeek')),
        for (final w in weeks)
          Builder(
            builder: (context) {
              final st = mapAt(w, 'statement');
              final badge = st == null
                  ? FFBadge(label: t('vendor.reports.payouts.noStatement'))
                  : st['status'] == 'paid'
                  ? FFBadge(
                      label: t('vendor.reports.payouts.paidOut'),
                      tone: FFBadgeTone.success,
                    )
                  : FFBadge(
                      label: t('vendor.reports.payouts.awaiting'),
                      tone: FFBadgeTone.brand,
                    );
              final start = parseDay(w['periodStartDate']);
              final end = parseDay(w['periodEndDate']);
              final card = FFCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ReportRow(
                      label: start == null || end == null
                          ? '—'
                          : periodInWords(start, end, lang),
                      value: reportMoney(numAt(w, 'payoutTzs')),
                      strong: true,
                    ),
                    Text(
                      [
                        reportPlural(
                          context,
                          'vendor.reports.ordersN',
                          numAt(w, 'orderCount'),
                        ),
                        '${t('vendor.reports.appSales')} ${reportMoney(numAt(w, 'grossTzs'))}',
                        '${t('vendor.reports.commission')} ${_minus(numAt(w, 'commissionTzs'))}',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: FFTokens.spacingXs),
                    badge,
                  ],
                ),
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                child: MergeSemantics(
                  child: st != null && onStatement != null
                      ? InkWell(
                          borderRadius: BorderRadius.circular(
                            FFTokens.radiusLg,
                          ),
                          onTap: onStatement,
                          child: card,
                        )
                      : card,
                ),
              );
            },
          ),
        ReportNote(t('vendor.reports.payouts.reconcile')),
      ],
    );
  }
}

// ── Customers and money owed (§8.3) ──────────────────────────────────────

class CustomersReportBody extends StatelessWidget {
  const CustomersReportBody({super.key, required this.data, this.onOpenOwed});

  final Map<String, dynamic> data;
  final VoidCallback? onOpenOwed;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final credit = mapAt(data, 'creditSales');
    final buyers = mapAt(data, 'buyers');
    final aging = mapAt(data, 'aging');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFCard(
          child: ReportFigureGrid(
            figures: [
              ReportFigure(
                label: t('vendor.reports.cust.owedNow'),
                value: reportMoney(numAt(data, 'owedTzs')),
                large: true,
              ),
              ReportFigure(
                label: t('vendor.reports.cust.overdueNow'),
                value: reportMoney(numAt(data, 'overdueTzs')),
                large: true,
              ),
              ReportFigure(
                label: t('vendor.reports.cust.creditSales'),
                value: reportMoney(numAt(credit, 'totalTzs')),
                sub: reportPlural(
                  context,
                  'vendor.reports.salesN',
                  numAt(credit, 'count'),
                ),
              ),
              ReportFigure(
                label: t('vendor.reports.cust.collected'),
                value: reportMoney(numAt(data, 'collectedTzs')),
              ),
              ReportFigure(
                label: t('vendor.reports.cust.buyers'),
                value: reportCount(
                  numAt(buyers, 'shop') + numAt(buyers, 'app'),
                ),
                sub:
                    '${t('vendor.reports.channel.walkIn')} ${reportCount(numAt(buyers, 'shop'))} · '
                    '${t('vendor.reports.channel.app')} ${reportCount(numAt(buyers, 'app'))}',
              ),
            ],
          ),
        ),
        // S7: balance taken off pay-later sales by refunds (not money).
        if (numAt(data, 'refundedOffTzs') != 0)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingXs),
            child: ReportNote(
              fillIn(t('vendor.reports.cust.refundedOff'), {
                'amount': reportMoney(numAt(data, 'refundedOffTzs')),
              }),
            ),
          ),
        if (aging != null) ...[
          _gap,
          ReportCard(
            title: t('vendor.reports.cust.aging'),
            child: Column(
              children: [
                for (final a in const [
                  ('current', 'vendor.reports.cust.agingCurrent'),
                  ('d1_30', 'vendor.reports.cust.aging1'),
                  ('d31_60', 'vendor.reports.cust.aging31'),
                  ('d61_90', 'vendor.reports.cust.aging61'),
                  ('d90plus', 'vendor.reports.cust.aging90'),
                ])
                  ReportRow(
                    label: t(a.$2),
                    value: reportMoney(numAt(aging, a.$1)),
                  ),
              ],
            ),
          ),
        ],
        if (onOpenOwed != null)
          Align(
            alignment: Alignment.centerLeft,
            child: FFButton(
              key: const Key('reports-open-owed'),
              label: t('vendor.reports.cust.openOwed'),
              variant: FFButtonVariant.ghost,
              onPressed: onOpenOwed,
            ),
          ),
      ],
    );
  }
}

// ── Payment methods (§8.4) ───────────────────────────────────────────────

class MethodsReportBody extends StatelessWidget {
  const MethodsReportBody({super.key, required this.data, this.limit});

  final Map<String, dynamic> data;

  /// Rows per group (the overview card shows 3).
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    List<Map<String, dynamic>> cut(List<Map<String, dynamic>> l) =>
        limit == null ? l : l.take(limit!).toList();
    final byYou = cut(listAt(data, 'byYou'));
    final via = cut(listAt(data, 'viaFitFlex'));
    // S7: money paid back on refunds, its own group (never summed with
    // money in; no share).
    final paidBack = cut(listAt(data, 'paidBack'));
    Widget group(
      String title,
      List<Map<String, dynamic>> rows,
      String methodField,
      bool mine,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        if (rows.isEmpty)
          ReportNote(t('vendor.reports.methods.none'))
        else
          for (final r in rows)
            ReportShareBar(
              label: t(methodKey(r[methodField]?.toString(), byYou: mine)),
              amount: numAt(r, 'amountTzs'),
              sharePct: numAt(r, 'sharePct'),
              count: limit == null ? numAt(r, 'count').toInt() : null,
            ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        group(t('vendor.reports.methods.byYou'), byYou, 'method', true),
        if (limit == null) ReportNote(t('vendor.pos.moneyNotice')),
        const SizedBox(height: FFTokens.spacingSm),
        group(
          t('vendor.reports.methods.viaFitFlex'),
          via,
          'paymentMethod',
          false,
        ),
        if (paidBack.isNotEmpty) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Column(
            key: const Key('reports-methods-paid-back'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('vendor.reports.methods.paidBack'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final r in paidBack)
                ReportRow(
                  label: limit == null
                      ? '${t(methodKey(r['method']?.toString()))} · ${reportPlural(context, 'vendor.reports.countTimes', numAt(r, 'count'))}'
                      : t(methodKey(r['method']?.toString())),
                  value: reportMoney(numAt(r, 'amountTzs')),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ── Refunds (S7 §2.11, S6 §8.5) ──────────────────────────────────────────

/// The Refunds report: totals, then one row per credit note and per undo
/// (Undone rows negative), oldest first. Rows open the refund for people
/// who may read it ([onOpen]).
class RefundsReportBody extends StatelessWidget {
  const RefundsReportBody({super.key, required this.data, this.onOpen});

  final Map<String, dynamic> data;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final lang = reportLang(context);
    final totals = mapAt(data, 'totals');
    final rows = listAt(data, 'rows');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFCard(
          key: const Key('reports-refunds-totals'),
          child: ReportFigureGrid(
            figures: [
              ReportFigure(
                label: t('vendor.reports.refunds.count'),
                value: reportCount(numAt(totals, 'count')),
                large: true,
              ),
              ReportFigure(
                label: t('vendor.reports.refunds.amount'),
                value: reportMoney(numAt(totals, 'amountTzs')),
                large: true,
              ),
              ReportFigure(
                label: t('vendor.reports.refunds.paidBack'),
                value: reportMoney(numAt(totals, 'paidOutTzs')),
              ),
              ReportFigure(
                label: t('vendor.reports.refunds.offBalances'),
                value: reportMoney(numAt(totals, 'balanceReducedTzs')),
              ),
              ReportFigure(
                label: t('vendor.reports.refunds.restocked'),
                value: reportCount(numAt(totals, 'restockedUnits')),
              ),
              ReportFigure(
                label: t('vendor.reports.refunds.undoneCount'),
                value: reportCount(numAt(totals, 'revertedCount')),
              ),
            ],
          ),
        ),
        ReportNote(t('vendor.refunds.moneyNotice')),
        _gap,
        for (final r in rows) _row(context, r, lang),
      ],
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> r, String lang) {
    final t = context.tr;
    final theme = Theme.of(context);
    final undo = r['type']?.toString() == 'revert';
    final id = r['refundId']?.toString() ?? '';
    final day = parseDay(r['date']);
    final date = day == null ? '—' : dayInWords(day, lang);
    final type = t(
      undo
          ? 'vendor.reports.refunds.type.revert'
          : 'vendor.reports.refunds.type.refund',
    );
    final method = r['method'] == null
        ? null
        : t(methodKey(r['method']?.toString()));
    final details = [
      date,
      '${r['saleNumber'] ?? ''}',
      if (numAt(r, 'paidOutTzs') != 0)
        '${t('vendor.reports.refunds.paidBack')} ${reportMoney(numAt(r, 'paidOutTzs'))}',
      ?method,
      reportPlural(
        context,
        'vendor.reports.refunds.unitsBack',
        numAt(r, 'restockedUnits'),
      ),
    ].join(' · ');
    final open = onOpen;
    final body = FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: FFTokens.spacingSm,
            children: [
              Text('${r['number'] ?? ''}', style: theme.textTheme.titleSmall),
              Text(
                reportMoney(numAt(r, 'amountTzs')),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FFBadge(
              label: type,
              tone: undo ? FFBadgeTone.gray : FFBadgeTone.info,
            ),
          ),
          Text(details, style: theme.textTheme.bodySmall),
        ],
      ),
    );
    return Padding(
      key: Key('reports-refund-row-$id-${r['type']}'),
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: Semantics(
        container: true,
        button: open != null,
        onTap: open == null || id.isEmpty ? null : () => open(id),
        label: [
          '${r['number'] ?? ''}',
          type,
          reportMoney(numAt(r, 'amountTzs')),
          details,
        ].join(', '),
        excludeSemantics: true,
        child: InkWell(
          onTap: open == null || id.isEmpty ? null : () => open(id),
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          child: body,
        ),
      ),
    );
  }
}
