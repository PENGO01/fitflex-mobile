// Vendor reports · S6: the Reports segment of the vendor home's tab 2
// (spec §9): period and channel, the header line, a pending-sync banner,
// one card per section this person may see, and Download.
//
// One call (GET /vendor/reports/summary) fills every card. Sections the
// server leaves out (no cost right, no payout right, customers off, stock
// ledger off) have no card: never a zero or a blurred figure. Online only.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../stock/stock_options.dart' show fillIn;
import 'report_export.dart';
import 'report_models.dart';
import 'report_period.dart';
import 'report_section_page.dart' show reportSectionLink;
import 'report_sections.dart';
import 'report_widgets.dart';

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class VendorReportsView extends StatefulWidget {
  const VendorReportsView({
    super.key,
    required this.access,
    this.pendingSales = 0,
    this.staffDisabled = false,
    this.businessName,
    this.now,
  });

  final ReportAccess access;

  /// For a download file name the server did not give.
  final String? businessName;

  /// Walk-in sales on this device still waiting to sync (§9.3).
  final int pendingSales;

  /// The staff member's access was turned off: no downloads (§11).
  final bool staffDisabled;

  /// Test clock.
  final DateTime? now;

  @override
  State<VendorReportsView> createState() => VendorReportsViewState();
}

class VendorReportsViewState extends State<VendorReportsView> {
  late ReportPeriod _period = ReportPeriod.initial(now: widget.now);
  String _channel = 'all';
  Map<String, dynamic>? _data;
  ReportFailure? _failure;
  String? _rangeError;
  bool _loading = true;
  int _seq = 0;
  bool _started = false;
  ({ReportPeriod period, Map<String, dynamic>? data})? _previous;
  final _periodFocus = FocusNode(debugLabel: 'reports-period');

  @override
  void dispose() {
    _periodFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(reload());
  }

  /// Asks the server again (pull to refresh, the refresh button).
  Future<void> reload() async {
    final mine = ++_seq;
    setState(() {
      _loading = true;
      _failure = null;
    });
    final isStaff =
        AppScope.of(context).auth.user?['userType'] == 'vendor_staff';
    try {
      final data = await AppScope.of(context).api.vendorReport(
        'summary',
        query: {
          'from': _period.fromParam,
          'to': _period.toParam,
          'channel': _channel,
        },
      );
      if (!mounted || mine != _seq) return;
      setState(() {
        _data = data;
        _loading = false;
        _rangeError = null;
      });
    } catch (e) {
      if (!mounted || mine != _seq) return;
      final failure = reportFailureOf(e, vendorStaff: isStaff);
      final prev = _previous;
      setState(() {
        _loading = false;
        if (failure == ReportFailure.badRange) {
          _rangeError = rangeErrorKey(e);
          if (prev != null) {
            _period = prev.period;
            _data = prev.data;
          }
        } else {
          _failure = failure;
          // Offline: no old figures (§11).
          if (failure == ReportFailure.offline) _data = null;
        }
      });
    }
  }

  void _change(void Function() change) {
    _previous = (period: _period, data: _data);
    setState(() {
      change();
      _data = null;
    });
    unawaited(reload());
  }

  void _open(ReportSection s) =>
      unawaited(context.push(reportSectionLink(s, _period, _channel)));

  bool get _showChannels => widget.access.walkIn || walkInChannel(_data);

  bool get _empty {
    final sales = mapAt(_data, 'sales');
    return sales != null &&
        numAt(sales, 'saleCount') + numAt(sales, 'orderCount') == 0 &&
        numAt(sales, 'itemsSold') == 0 &&
        numAt(sales, 'refundTzs') == 0;
  }

  Widget _salesCard(Map<String, dynamic> sales) {
    final t = context.tr;
    final g = groupByOf(_data?['groupBy']) ?? _period.autoGrouping;
    final buckets = listAt(sales, 'buckets');
    final net = numAt(sales, 'netTzs');
    final voided = mapAt(sales, 'voided');
    final count = numAt(sales, 'saleCount') + numAt(sales, 'orderCount');
    final grossLine = fillIn(t('vendor.reports.grossLine'), {
      'g': reportMoney(numAt(sales, 'grossTzs')),
      'd': reportMoney(-numAt(sales, 'discountTzs')),
      'r': reportMoney(-numAt(sales, 'refundTzs')),
    });
    final countLine =
        '${reportPlural(context, 'vendor.reports.salesN', count)} · ${reportPlural(context, 'vendor.reports.itemsN', numAt(sales, 'itemsSold'))}';
    return ReportCard(
      key: const Key('reports-card-sales'),
      title: t('vendor.reports.view.sales'),
      semanticSummary:
          '${t('vendor.reports.net')} ${reportMoney(net)}. $grossLine. $countLine',
      onTap: () => _open(ReportSection.sales),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReportFigure(
            label: t('vendor.reports.net'),
            value: reportMoney(net),
            large: true,
          ),
          Text(grossLine, style: Theme.of(context).textTheme.bodySmall),
          if (buckets.length > 1 && buckets.length <= reportChartMaxBars) ...[
            const SizedBox(height: FFTokens.spacingSm),
            ExcludeSemantics(
              child: ReportChart(
                figure: t('vendor.reports.net'),
                groupBy: g,
                period: _period,
                total: net,
                height: 96,
                bars: [
                  for (final b in buckets)
                    if (parseDay(b['start']) != null)
                      ReportBar(
                        start: parseDay(b['start'])!,
                        end: parseDay(b['end']) ?? parseDay(b['start'])!,
                        value: numAt(b, 'netTzs'),
                        description: fillIn(t('vendor.reports.barNet'), {
                          'when': bucketWords(
                            context,
                            parseDay(b['start'])!,
                            parseDay(b['end']) ?? parseDay(b['start'])!,
                            g,
                          ),
                          'amount': reportMoney(numAt(b, 'netTzs')),
                        }),
                      ),
                ],
              ),
            ),
          ],
          const SizedBox(height: FFTokens.spacingXs),
          Text(countLine, style: Theme.of(context).textTheme.bodySmall),
          if (numAt(voided, 'count') > 0)
            Text(
              reportPlural(
                context,
                'vendor.reports.voided',
                numAt(voided, 'count'),
                {'amount': reportMoney(numAt(voided, 'totalTzs'))},
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _productsCard() {
    final t = context.tr;
    final top = listAt(_data, 'topProducts').take(3).toList();
    final slow = fillIn(t('vendor.reports.slowCount'), {
      'n': numAt(_data, 'slowCount'),
    });
    return ReportCard(
      key: const Key('reports-card-products'),
      title: t('vendor.reports.topProducts'),
      semanticSummary: [
        for (final p in top)
          '${productWords(context, p)} ${reportMoney(numAt(p, 'netRevenueTzs'))}',
        slow,
      ].join('. '),
      onTap: () => _open(ReportSection.products),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (top.isEmpty) ReportNote(t('vendor.reports.noSalesPeriod')),
          for (final p in top)
            ReportRow(
              label:
                  '${productWords(context, p)} · '
                  '${reportPlural(context, 'vendor.reports.unitsN', numAt(p, 'unitsSold'))}',
              value: reportMoney(numAt(p, 'netRevenueTzs')),
            ),
          Text(slow, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _stockCard(Map<String, dynamic> stock) {
    final t = context.tr;
    final atCost = maybeNum(stock, 'atCostTzs');
    final unknown = maybeNum(stock, 'costUnknownCount');
    final lines = <String>[
      '${t('vendor.reports.stock.atRetail')} ${reportMoney(numAt(stock, 'atRetailTzs'))}',
      if (atCost != null)
        '${t('vendor.reports.stock.atCost')} ${reportMoney(atCost)}',
      '${t('vendor.reports.stock.units')} ${reportCount(numAt(stock, 'units'))}',
    ];
    return ReportCard(
      key: const Key('reports-card-stock'),
      title: t('vendor.reports.view.stock'),
      semanticSummary: lines.join('. '),
      onTap: () => _open(ReportSection.stock),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReportRow(
            label: t('vendor.reports.stock.atRetail'),
            value: reportMoney(numAt(stock, 'atRetailTzs')),
            strong: true,
          ),
          if (atCost != null)
            ReportRow(
              key: const Key('reports-card-stock-cost'),
              label: t('vendor.reports.stock.atCost'),
              value: reportMoney(atCost),
              strong: true,
            ),
          ReportRow(
            label: t('vendor.reports.stock.units'),
            value: reportCount(numAt(stock, 'units')),
          ),
          if (unknown != null && unknown > 0)
            Text(
              reportPlural(
                context,
                'vendor.reports.stock.costUnknown',
                unknown,
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _profitCard(Map<String, dynamic> profit) {
    final t = context.tr;
    final uncosted = mapAt(profit, 'uncosted');
    final value = profitWords(context, profit);
    final margin = formatPct(maybeNum(profit, 'marginPct'));
    final uncostedText =
        uncosted != null &&
            (numAt(uncosted, 'qty') > 0 || numAt(uncosted, 'revenueTzs') > 0)
        ? reportPlural(
            context,
            'vendor.reports.profit.uncosted',
            numAt(uncosted, 'qty'),
            {'amount': reportMoney(numAt(uncosted, 'revenueTzs'))},
          )
        : null;
    return ReportCard(
      key: const Key('reports-card-profit'),
      title: t('vendor.reports.view.profit'),
      semanticSummary: [
        '${t('vendor.reports.profit')} $value',
        '${t('vendor.reports.margin')} $margin',
        ?uncostedText,
      ].join('. '),
      onTap: () => _open(ReportSection.profit),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReportFigure(
            label: t('vendor.reports.profit'),
            value: value,
            sub: t('vendor.reports.profitHint'),
            large: true,
          ),
          ReportRow(label: t('vendor.reports.margin'), value: margin),
          if (uncostedText != null)
            Text(uncostedText, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _payoutsCard(Map<String, dynamic> p) {
    final t = context.tr;
    final rows = [
      (t('vendor.reports.youReceive'), numAt(p, 'payoutTzs')),
      (t('vendor.reports.payouts.paidOut'), numAt(p, 'paidOutTzs')),
      (t('vendor.reports.payouts.waiting'), numAt(p, 'waitingTzs')),
    ];
    return ReportCard(
      key: const Key('reports-card-payouts'),
      title: t('vendor.reports.view.payouts'),
      semanticSummary: [
        for (final r in rows) '${r.$1} ${reportMoney(r.$2)}',
      ].join('. '),
      onTap: () => _open(ReportSection.payouts),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            ReportRow(
              label: rows[i].$1,
              value: reportMoney(rows[i].$2),
              strong: i == 0,
            ),
        ],
      ),
    );
  }

  Widget _customersCard(Map<String, dynamic> c) {
    final t = context.tr;
    final rows = [
      (t('vendor.owed.title'), numAt(c, 'owedTzs')),
      (t('vendor.owed.overdue'), numAt(c, 'overdueTzs')),
      (t('vendor.reports.cust.collected'), numAt(c, 'collectedTzs')),
    ];
    return ReportCard(
      key: const Key('reports-card-customers'),
      title: t('vendor.reports.view.customers'),
      semanticSummary: [
        for (final r in rows) '${r.$1} ${reportMoney(r.$2)}',
      ].join('. '),
      onTap: () => _open(ReportSection.customers),
      child: Column(
        children: [
          for (final r in rows)
            ReportRow(label: r.$1, value: reportMoney(r.$2)),
        ],
      ),
    );
  }

  Widget _methodsCard() {
    final t = context.tr;
    final methods = mapAt(_data, 'methods') ?? const <String, dynamic>{};
    return ReportCard(
      key: const Key('reports-card-methods'),
      title: t('vendor.reports.view.methods'),
      // Each group read under its own name, the shop's money apart from the
      // app's (UAT D14): "Collected by you: Cash after change TSh 120,000,
      // M-Pesa TSh 80,000. Paid through FitFlex: M-Pesa TSh 150,000".
      semanticSummary: [
        for (final g in [
          ('vendor.reports.methods.byYou', 'byYou', 'method', true),
          (
            'vendor.reports.methods.viaFitFlex',
            'viaFitFlex',
            'paymentMethod',
            false,
          ),
        ])
          '${t(g.$1)}: ${[for (final r in listAt(methods, g.$2).take(3)) '${t(methodKey(r[g.$3]?.toString(), byYou: g.$4))} '
                '${reportMoney(numAt(r, 'amountTzs'))}'].join(', ').ifEmpty(t('vendor.reports.methods.none'))}',
      ].join('. '),
      onTap: () => _open(ReportSection.methods),
      child: MethodsReportBody(data: methods, limit: 3),
    );
  }

  List<Widget> _cards() {
    final a = widget.access;
    final d = _data!;
    final sales = mapAt(d, 'sales');
    final stock = mapAt(d, 'stock');
    final profit = mapAt(d, 'profit');
    final payouts = mapAt(d, 'payouts');
    final customers = mapAt(d, 'customers');
    final lang = reportLang(context);
    return [
      if (neverSold(d))
        ReportFirstUse(access: a)
      else if (_empty)
        // Its own node: never read as part of the Stock value card (D14).
        Semantics(
          container: true,
          child: FFEmptyState(
            key: const Key('reports-empty'),
            icon: Icons.bar_chart_outlined,
            title: fillIn(context.tr('vendor.reports.empty'), {
              'period': periodInWords(_period.from, _period.to, lang),
            }),
            action: FFButton(
              key: const Key('reports-try-period'),
              label: context.tr('vendor.reports.tryPeriod'),
              variant: FFButtonVariant.secondary,
              onPressed: () => focusPeriod(context, _periodFocus),
            ),
          ),
        )
      else ...[
        if (sales != null) _salesCard(sales),
        _productsCard(),
      ],
      // Stock value is not period-based: it shows on an empty period too.
      if (a.stock && stock != null) _stockCard(stock),
      if (!_empty && !neverSold(d)) ...[
        if (a.cost && profit != null) _profitCard(profit),
        if (a.payouts && payouts != null) _payoutsCard(payouts),
        if (a.customers && customers != null) _customersCard(customers),
        _methodsCard(),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final data = _data;
    final generatedAt = DateTime.tryParse(
      data?['generatedAt']?.toString() ?? '',
    );
    final Widget content;
    if (_failure == ReportFailure.offline) {
      content = FFErrorState(
        key: const Key('reports-offline'),
        icon: Icons.wifi_off_outlined,
        message: t('error.network'),
        onRetry: reload,
      );
    } else if (_failure == ReportFailure.staffDisabled) {
      content = FFAlert(
        key: const Key('reports-staff-disabled'),
        message: t('error.reason.vendorStaffInactive'),
        tone: FFAlertTone.error,
      );
    } else if (_failure != null) {
      content = FFErrorState(
        key: const Key('reports-failed'),
        message: t('vendor.reports.failed'),
        onRetry: reload,
      );
    } else if (data == null) {
      content = const ReportLoading(count: 4);
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Each card its own node (UAT D14).
          for (final c in _cards())
            Semantics(
              container: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
                child: c,
              ),
            ),
        ],
      );
    }
    return ListView(
      key: const Key('vendor-reports-view'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        ReportControls(
          period: _period,
          now: widget.now,
          serverError: _rangeError,
          periodFocus: _periodFocus,
          onPeriod: (p) => _change(() => _period = p),
          channel: _showChannels ? _channel : null,
          onChannel: (c) {
            if (c != _channel) _change(() => _channel = c);
          },
        ),
        const SizedBox(height: FFTokens.spacingSm),
        ReportHeaderLine(
          period: _period,
          channel: _channel,
          generatedAt: generatedAt,
          inProgress: data?['inProgress'] == true,
          onRefresh: _loading ? null : reload,
        ),
        if (widget.pendingSales > 0) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFAlert(
            key: const Key('reports-pending-sync'),
            message: reportPlural(
              context,
              'vendor.reports.pendingSync',
              widget.pendingSales,
            ),
            tone: FFAlertTone.warning,
          ),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        content,
        if (_failure != ReportFailure.offline)
          FFButton(
            key: const Key('reports-export'),
            label: t('vendor.reports.export'),
            icon: Icons.download_outlined,
            variant: FFButtonVariant.secondary,
            fullWidth: true,
            // A disabled staff member still opens the sheet: it says why
            // nothing can be downloaded (§11).
            onPressed: data == null
                ? null
                : () => showReportExportSheet(
                    context,
                    request: ReportExportRequest(
                      period: _period,
                      channel: _channel,
                      businessName: widget.businessName,
                    ),
                    sections: widget.access.sections,
                    staffDisabled: widget.staffDisabled,
                  ),
          ),
      ],
    );
  }
}
