// Vendor reports · S6: one report section on its own page,
// `/vendor/reports/:section?from&to&channel` (spec §2.2, §5–§8).
//
// Deep-link rules (§2.2), checked here once the tools are known:
// - reports off (tools.reports not exactly true) → /vendor/home, no message;
// - no `reports` permission → /vendor/home (its first allowed tab) + "You
//   don't have access to this report.";
// - a section this person may not see (Profit without cost …) → Reports
//   home + the same message. Unknown sections never reach this page (the
//   route sends them to Reports home).
// Online only: the answer lives in this page's memory and nowhere else.
// Changing the period cancels what was asked before: only the latest
// answer is shown (§11, stale request).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/widgets/partner_payouts_page.dart';
import '../customers/customers_widgets.dart' show owedHomeRoute;
import '../stock/stock_options.dart';
import 'report_export.dart';
import 'report_models.dart';
import 'report_period.dart';
import 'report_sections.dart';
import 'report_widgets.dart';

/// The period a deep link asks for: the matching preset, a custom range, or
/// This month when the dates are missing or would be refused.
ReportPeriod periodFromLink(String? from, String? to, {DateTime? now}) {
  final f = parseDay(from), t = parseDay(to);
  if (f == null || t == null || checkRange(f, t, now: now) != null) {
    return ReportPeriod.initial(now: now);
  }
  for (final p in ReportPreset.values) {
    if (p == ReportPreset.custom) continue;
    final candidate = ReportPeriod.preset(p, now: now);
    if (candidate.from == f && candidate.to == t) return candidate;
  }
  return ReportPeriod.custom(f, t);
}

/// The address of [section] for [period] and [channel].
String reportSectionLink(
  ReportSection section,
  ReportPeriod period,
  String channel,
) => Uri(
  path: reportSectionRoute(section),
  queryParameters: {
    'from': period.fromParam,
    'to': period.toParam,
    if (channel != 'all') 'channel': channel,
  },
).toString();

class ReportSectionPage extends StatefulWidget {
  const ReportSectionPage({
    super.key,
    required this.section,
    this.from,
    this.to,
    this.channel,
    this.now,
  });

  final ReportSection section;
  final String? from;
  final String? to;
  final String? channel;

  /// Test clock.
  final DateTime? now;

  @override
  State<ReportSectionPage> createState() => _ReportSectionPageState();
}

const _productSorts = ['revenue', 'units', 'slow'];

class _ReportSectionPageState extends State<ReportSectionPage> {
  ReportAccess? _access;
  late ReportPeriod _period = periodFromLink(
    widget.from,
    widget.to,
    now: widget.now,
  );
  late String _channel =
      const {'all', 'app', 'walk_in'}.contains(widget.channel)
      ? widget.channel!
      : 'all';
  ReportGroupBy? _groupBy;
  Map<String, dynamic>? _data;
  ReportFailure? _failure;
  String? _rangeError;
  bool _loading = true;
  bool _staffDisabled = false;
  int _seq = 0;
  bool _started = false;

  /// What was shown before the last filter change, put back if the server
  /// refuses the new period (§11: previous figures stay).
  ({ReportPeriod period, Map<String, dynamic>? data, ReportGroupBy? groupBy})?
  _previous;
  final _scroll = ScrollController();
  final _periodFocus = FocusNode(debugLabel: 'reports-period');

  // Products (§6).
  String _sort = 'revenue';
  List<Map<String, dynamic>> _rows = [];
  String? _nextCursor;
  bool _loadingMore = false;
  String _search = '';
  String _serverQ = '';

  // Stock value.
  StockSort _stockSort = StockSort.value;

  ReportSection get _section => widget.section;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_start());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _periodFocus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final tools = await VendorToolsOptions.of(context);
    if (!mounted) return;
    final access = ReportAccess.of(tools, (p) => canVendor(context, p));
    if (!tools.reports) {
      context.go('/vendor/home');
      return;
    }
    if (!access.reports) {
      FFSnack.error(context, context.tr('vendor.reports.noAccess'));
      context.go('/vendor/home');
      return;
    }
    if (!access.allows(_section)) {
      FFSnack.error(context, context.tr('vendor.reports.noAccess'));
      context.go(reportsHomeRoute);
      return;
    }
    setState(() => _access = access);
    await _load();
  }

  Map<String, String?> _query({String? cursor}) => {
    if (_section.usesPeriod) ...{
      'from': _period.fromParam,
      'to': _period.toParam,
    },
    if (_section.usesChannel) 'channel': _channel,
    if (_section.usesGrouping && _groupBy != null)
      'groupBy': groupByParam(_groupBy!),
    if (_section == ReportSection.products) ...{
      'sort': _sort,
      'q': _serverQ,
      'cursor': cursor,
    },
  };

  bool get _isStaff =>
      AppScope.of(context).auth.user?['userType'] == 'vendor_staff';

  Future<void> _load() async {
    final mine = ++_seq;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final data = await AppScope.of(
        context,
      ).api.vendorReport(_section.api, query: _query());
      if (!mounted || mine != _seq) return;
      setState(() {
        _data = data;
        _loading = false;
        _rangeError = null;
        if (_section == ReportSection.products) {
          _rows = listAt(data, 'rows');
          _nextCursor = data['nextCursor']?.toString();
        }
      });
    } catch (e) {
      if (!mounted || mine != _seq) return;
      final failure = reportFailureOf(e, vendorStaff: _isStaff);
      switch (failure) {
        case ReportFailure.featureOff:
          context.go('/vendor/home');
          return;
        case ReportFailure.noAccess:
          FFSnack.error(context, context.tr('vendor.reports.noAccess'));
          context.go(reportsHomeRoute);
          return;
        case ReportFailure.badRange:
          // The figures shown before stay; the control says why.
          final prev = _previous;
          setState(() {
            _loading = false;
            _rangeError = rangeErrorKey(e);
            if (prev != null) {
              _period = prev.period;
              _data = prev.data;
              _groupBy = prev.groupBy;
              if (_section == ReportSection.products) {
                _rows = listAt(prev.data, 'rows');
                _nextCursor = prev.data?['nextCursor']?.toString();
              }
            }
          });
          return;
        case ReportFailure.offline:
          // No old figures when offline (§11).
          setState(() {
            _loading = false;
            _data = null;
            _failure = failure;
          });
          return;
        case ReportFailure.staffDisabled:
        case ReportFailure.failed:
          setState(() {
            _loading = false;
            _failure = failure;
            _staffDisabled = failure == ReportFailure.staffDisabled;
          });
      }
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore) return;
    final mine = _seq;
    setState(() => _loadingMore = true);
    try {
      final data = await AppScope.of(
        context,
      ).api.vendorReport(_section.api, query: _query(cursor: cursor));
      if (!mounted || mine != _seq) return;
      setState(() {
        _rows = [..._rows, ...listAt(data, 'rows')];
        _nextCursor = data['nextCursor']?.toString();
      });
    } catch (_) {
      if (mounted) FFSnack.error(context, context.tr('vendor.reports.failed'));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// A new filter: the old figures go (they are for another period) and
  /// are kept aside in case the server refuses the new one.
  void _changeFilter(void Function() change) {
    _previous = (period: _period, data: _data, groupBy: _groupBy);
    setState(() {
      change();
      _data = null;
      _rows = [];
      _nextCursor = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_load());
  }

  void _setPeriod(ReportPeriod p) => _changeFilter(() {
    _period = p;
    // A grouping the new period cannot take goes back to auto.
    if (_groupBy != null && !p.allows(_groupBy!)) _groupBy = null;
  });

  void _export() {
    final access = _access;
    if (access == null) return;
    unawaited(
      showReportExportSheet(
        context,
        request: ReportExportRequest(
          period: _period,
          channel: _channel,
          groupBy: _groupBy,
          sort: _sort,
          // What is searched on screen (or asked of the server).
          q: _search.trim().isNotEmpty ? _search : _serverQ,
        ),
        sections: [_section],
        staffDisabled: _staffDisabled,
      ),
    );
  }

  bool get _showChannels => (_access?.walkIn ?? false) || walkInChannel(_data);

  bool get _empty {
    final d = _data;
    if (d == null) return false;
    switch (_section) {
      case ReportSection.sales:
        final t = mapAt(d, 'totals');
        return numAt(t, 'saleCount') + numAt(t, 'orderCount') == 0 &&
            numAt(t, 'itemsSold') == 0 &&
            numAt(t, 'refundTzs') == 0;
      case ReportSection.products:
        return _rows.isEmpty && _serverQ.isEmpty;
      case ReportSection.profit:
        final t = mapAt(d, 'totals');
        final u = mapAt(d, 'uncosted');
        return numAt(t, 'netExVatTzs') == 0 &&
            numAt(t, 'costTzs') == 0 &&
            numAt(u, 'qty') == 0;
      case ReportSection.methods:
        return listAt(d, 'byYou').isEmpty && listAt(d, 'viaFitFlex').isEmpty;
      case ReportSection.payouts:
        final s = mapAt(d, 'status');
        return listAt(d, 'weeks').isEmpty &&
            numAt(mapAt(s, 'notDelivered'), 'orders') == 0;
      case ReportSection.stock:
        return listAt(d, 'rows').isEmpty;
      case ReportSection.customers:
        return false;
    }
  }

  Widget _body() {
    final t = context.tr;
    final data = _data;
    if (_failure == ReportFailure.offline) {
      return FFErrorState(
        key: const Key('reports-offline'),
        icon: Icons.wifi_off_outlined,
        message: t('error.network'),
        onRetry: _load,
      );
    }
    if (_failure == ReportFailure.staffDisabled) {
      return FFAlert(
        key: const Key('reports-staff-disabled'),
        message: t('error.reason.vendorStaffInactive'),
        tone: FFAlertTone.error,
      );
    }
    if (_failure != null) {
      return FFErrorState(
        key: const Key('reports-failed'),
        message: t('vendor.reports.failed'),
        onRetry: _load,
      );
    }
    if (data == null) return const ReportLoading();
    // Never sold (`hasEverSold: false`): first use, not "no sales in …".
    // Stock value is about what is on the shelf, so it still shows.
    if (neverSold(data) && _section != ReportSection.stock) {
      return ReportFirstUse(access: _access ?? ReportAccess.none);
    }
    if (_empty) {
      final lang = reportLang(context);
      return FFEmptyState(
        key: const Key('reports-empty'),
        icon: Icons.bar_chart_outlined,
        title: _section == ReportSection.stock
            ? t('vendor.reports.stock.empty')
            : fillIn(t('vendor.reports.empty'), {
                'period': periodInWords(_period.from, _period.to, lang),
              }),
        action: _section.usesPeriod
            ? FFButton(
                key: const Key('reports-try-period'),
                label: t('vendor.reports.tryPeriod'),
                variant: FFButtonVariant.secondary,
                onPressed: () {
                  if (_scroll.hasClients) {
                    _scroll.animateTo(
                      0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                  }
                  _periodFocus.requestFocus();
                },
              )
            : null,
      );
    }
    switch (_section) {
      case ReportSection.sales:
        return SalesReportBody(
          data: data,
          period: _period,
          showChannels: _showChannels,
        );
      case ReportSection.products:
        return _productsBody();
      case ReportSection.stock:
        return StockReportBody(
          data: data,
          sort: _stockSort,
          onSort: (s) => setState(() => _stockSort = s),
          onAddCost: canVendor(context, 'products')
              ? () => context.go('/vendor/home?open=products')
              : null,
        );
      case ReportSection.profit:
        return ProfitReportBody(data: data, period: _period);
      case ReportSection.payouts:
        return PayoutsReportBody(
          data: data,
          onStatement: (_access?.payments ?? false)
              ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const PartnerPayoutsPage(kind: PayoutKind.vendor),
                  ),
                )
              : null,
        );
      case ReportSection.customers:
        return CustomersReportBody(
          data: data,
          onOpenOwed: () => context.go(owedHomeRoute),
        );
      case ReportSection.methods:
        return MethodsReportBody(data: data);
    }
  }

  Widget _productsBody() {
    final t = context.tr;
    final q = _search.trim().toLowerCase();
    final rows = q.isEmpty
        ? _rows
        : _rows
              .where(
                (r) => (r['name']?.toString() ?? '').toLowerCase().contains(q),
              )
              .toList();
    final totals = mapAt(_data, 'totals');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFSegmented(
          value: _sort,
          options: [
            ('revenue', t('vendor.reports.best')),
            ('units', t('vendor.reports.mostUnits')),
            ('slow', t('vendor.reports.slow')),
          ],
          onChanged: (v) {
            if (!_productSorts.contains(v) || v == _sort) return;
            _changeFilter(() => _sort = v);
          },
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFTextField(
          key: const Key('reports-products-search'),
          label: t('vendor.reports.searchProducts'),
          prefixIcon: const Icon(Icons.search),
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _search = v),
          // More rows on the server than loaded: ask it to search too.
          onFieldSubmitted: (v) {
            final next = v.trim();
            if ((_nextCursor != null || _serverQ.isNotEmpty) &&
                next != _serverQ) {
              _changeFilter(
                () =>
                    _serverQ = next.length > 80 ? next.substring(0, 80) : next,
              );
            }
          },
        ),
        const SizedBox(height: FFTokens.spacingSm),
        if (_sort == 'revenue' && totals != null)
          FFCard(
            child: Column(
              children: [
                ReportRow(
                  label: t('vendor.reports.unitsSold'),
                  value: reportCount(numAt(totals, 'unitsSold')),
                  strong: true,
                ),
                ReportRow(
                  label: t('vendor.reports.revenue'),
                  value: reportMoney(numAt(totals, 'netRevenueTzs')),
                  strong: true,
                ),
              ],
            ),
          ),
        const SizedBox(height: FFTokens.spacingSm),
        if (rows.isEmpty) ReportNote(t('vendor.reports.noMatch')),
        for (final r in rows)
          ProductReportRow(
            row: r,
            slow: _sort == 'slow',
            showChannels: _showChannels,
          ),
        if (_nextCursor != null)
          FFButton(
            key: const Key('reports-load-more'),
            label: t('vendor.reports.loadMore'),
            variant: FFButtonVariant.secondary,
            loading: _loadingMore,
            onPressed: _loadMore,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final access = _access;
    final data = _data;
    final generatedAt = DateTime.tryParse(
      data?['generatedAt']?.toString() ?? '',
    );
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(reportsHomeRoute),
        ),
        title: Text(t(_section.titleKey)),
        actions: [
          if (access != null)
            IconButton(
              key: const Key('reports-section-export'),
              tooltip: t('vendor.reports.export'),
              onPressed: _export,
              icon: const Icon(Icons.download_outlined),
            ),
        ],
      ),
      body: access == null
          ? const Padding(
              padding: EdgeInsets.all(FFTokens.spacingLg),
              child: ReportLoading(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  if (_section.usesPeriod)
                    ReportControls(
                      period: _period,
                      periodFocus: _periodFocus,
                      now: widget.now,
                      onPeriod: _setPeriod,
                      serverError: _rangeError,
                      channel: _section.usesChannel && _showChannels
                          ? _channel
                          : null,
                      onChannel: (c) {
                        if (c == _channel) return;
                        _changeFilter(() => _channel = c);
                      },
                      groupBy: _section.usesGrouping
                          ? (_groupBy ??
                                groupByOf(data?['groupBy']) ??
                                _period.autoGrouping)
                          : null,
                      onGroupBy: (g) => _changeFilter(() => _groupBy = g),
                    ),
                  const SizedBox(height: FFTokens.spacingSm),
                  ReportHeaderLine(
                    period: _period,
                    showPeriod: _section.usesPeriod,
                    channel: _section.usesChannel ? _channel : null,
                    channelText: switch (_section) {
                      ReportSection.payouts => t(
                        'vendor.reports.channel.appOnly',
                      ),
                      ReportSection.stock || ReportSection.customers => t(
                        'vendor.reports.channel.allChannels',
                      ),
                      _ => null,
                    },
                    generatedAt: generatedAt,
                    inProgress: data?['inProgress'] == true,
                    onRefresh: _loading ? null : _load,
                  ),
                  if (_loading && data != null)
                    const LinearProgressIndicator(
                      key: Key('reports-reloading'),
                    ),
                  const SizedBox(height: FFTokens.spacingSm),
                  _loading && data == null ? const ReportLoading() : _body(),
                ],
              ),
            ),
    );
  }
}
