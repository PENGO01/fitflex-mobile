// Vendor tools · S3: the Sales tab on the vendor home (spec §5.1) — sales
// waiting on this device first, then the server's history for a range with
// its summary (the server sums it; the app never adds pages up).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../stock/stock_history_page.dart' show stockRangePickerTheme;
import '../stock/stock_options.dart';
import '../customers/customer_models.dart' show customerDisplayName;
import '../customers/customer_profile_page.dart' show saleKindBadges;
import '../customers/customers_widgets.dart' show owedHomeRoute, intOf;
import 'offline_sale_queue.dart';
import 'receipt_data.dart';
import 'sales_sync_page.dart' show queuedSaleRow;
import 'sales_widgets.dart';

enum _Problem { none, failed, network, suspended }

class VendorSalesTab extends StatefulWidget {
  const VendorSalesTab({super.key});

  @override
  State<VendorSalesTab> createState() => VendorSalesTabState();
}

class VendorSalesTabState extends State<VendorSalesTab> {
  SalesSession? _session;
  String _range = 'today';
  DateTimeRange? _custom;
  String _status = 'all';
  bool _mine = false;
  // S4: only pay-later sales (kind=credit), and the "Owed to you" card.
  bool _credit = false;
  VendorTools _tools = VendorTools.off;
  Map<String, dynamic>? _owed;
  List<Map<String, dynamic>> _sales = [];
  Map<String, dynamic>? _summary;
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _moreFailed = false;
  bool _neverSold = false;
  _Problem _problem = _Problem.none;
  StreamSubscription<String>? _synced;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = SalesSession.of(context);
      setState(() => _session = session?..attach());
      _synced = session?.syncedNumbers.listen((_) {
        if (mounted) unawaited(reload(sync: false));
      });
      unawaited(reload());
    });
  }

  @override
  void dispose() {
    _synced?.cancel();
    _session?.detach();
    super.dispose();
  }

  (String, String) get _period {
    final today = eatToday();
    if (_range == 'custom' && _custom != null) {
      return (eatDay(_custom!.start), eatDay(_custom!.end));
    }
    final days = switch (_range) {
      '7d' => 6,
      '30d' => 29,
      _ => 0,
    };
    return (eatDay(today.subtract(Duration(days: days))), eatDay(today));
  }

  /// Pull to refresh: summary, page 1, and a sync attempt.
  Future<void> reload({bool sync = true}) async {
    if (sync) unawaited(_session?.sync());
    setState(() {
      _loading = true;
      _problem = _Problem.none;
      _moreFailed = false;
    });
    final (from, to) = _period;
    final api = AppScope.of(context).api;
    _tools = await VendorToolsOptions.of(context);
    if (!mounted) return;
    if (!_tools.customers) _credit = false;
    if (_tools.customers && canVendor(context, 'customers')) {
      unawaited(_loadOwed());
    } else if (_owed != null) {
      setState(() => _owed = null);
    }
    try {
      final res = await api.vendorSales(
        from: from,
        to: to,
        status: _status,
        mine: _mine,
        limit: 50,
        kind: _credit ? 'credit' : null,
      );
      var neverSold = false;
      final rows = (res['sales'] as List? ?? []).whereType<Map>().toList();
      if (rows.isEmpty && _status == 'all' && !_mine && !_credit) {
        // An empty range: has this shop ever sold anything?
        try {
          final any = await api.vendorSales(limit: 1);
          neverSold = (any['sales'] as List? ?? []).isEmpty;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _sales = [for (final r in rows) Map<String, dynamic>.from(r)];
        _cursor = res['nextCursor']?.toString();
        _summary = res['summary'] is Map
            ? Map<String, dynamic>.from(res['summary'] as Map)
            : null;
        _neverSold = neverSold;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _problem = e.code == 'vendor_suspended'
            ? _Problem.suspended
            : _Problem.failed;
      });
      // The paused notice (banners) says it once for the whole tab.
      if (e.code == 'vendor_suspended') _session?.markSuspended();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _problem = _Problem.network;
      });
    }
  }

  /// "Owed to you: TZS X · n overdue" (people with `customers`).
  Future<void> _loadOwed() async {
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorReceivablesAging(limit: 1);
      if (!mounted) return;
      setState(
        () => _owed = res['totals'] is Map
            ? Map<String, dynamic>.from(res['totals'] as Map)
            : null,
      );
    } catch (_) {
      // The card simply does not show.
      if (mounted && _owed != null) setState(() => _owed = null);
    }
  }

  Widget? _owedCard() {
    final t = _owed;
    if (t == null || intOf(t['owedTzs']) <= 0) return null;
    final n = intOf(t['overdueSaleCount']);
    final text = fillIn(context.tr('vendor.owed.card'), {
      'amount': formatCurrency(intOf(t['owedTzs'])),
      'n': n,
    });
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: FFCard(
        padding: EdgeInsets.zero,
        child: Semantics(
          button: true,
          label: text,
          excludeSemantics: true,
          child: InkWell(
            key: const Key('sales-owed-card'),
            onTap: () => context.go(owedHomeRoute),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.all(FFTokens.spacingMd),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined),
                    const SizedBox(width: FFTokens.spacingSm),
                    Expanded(child: Text(text)),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _more() async {
    final cursor = _cursor;
    if (cursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    final (from, to) = _period;
    try {
      final res = await AppScope.of(context).api.vendorSales(
        from: from,
        to: to,
        status: _status,
        mine: _mine,
        limit: 50,
        cursor: cursor,
        kind: _credit ? 'credit' : null,
      );
      if (!mounted) return;
      setState(() {
        _sales = [
          ..._sales,
          for (final r in (res['sales'] as List? ?? []).whereType<Map>())
            Map<String, dynamic>.from(r),
        ];
        _cursor = res['nextCursor']?.toString();
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _moreFailed = true;
      });
    }
  }

  Future<void> _pickRange(String value) async {
    if (value == 'custom') {
      final today = eatToday();
      final last = DateTime(today.year, today.month, today.day);
      final picked = await showDateRangePicker(
        context: context,
        firstDate: last.subtract(const Duration(days: 730)),
        lastDate: last,
        initialDateRange: _custom,
        builder: (context, child) => Theme(
          data: stockRangePickerTheme(Theme.of(context)),
          child: child!,
        ),
      );
      if (picked == null || !mounted) return;
      _custom = picked;
    }
    setState(() => _range = value);
    await reload(sync: false);
  }

  void _filter(void Function() change) {
    setState(change);
    unawaited(reload(sync: false));
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) return const Center(child: FFSpinner());
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final owed = _owedCard();
          final controls = <Widget>[
            ?owed,
            _rangeControl(),
            const SizedBox(height: FFTokens.spacingSm),
            _filters(),
            const SizedBox(height: FFTokens.spacingSm),
            if (_summary != null && _problem == _Problem.none) _summaryCard(),
          ];
          final rows = <Widget>[
            for (final q in session.all) queuedSaleRow(context, q),
            ..._serverRows(),
          ];
          final banners = SalesSyncBanners(session: session);
          if (!wide) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                FFTokens.spacingLg,
                FFTokens.spacingLg,
                FFTokens.spacingLg,
                96,
              ),
              children: [banners, ...controls, ...rows],
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Padding(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 320,
                      child: ListView(children: [banners, ...controls]),
                    ),
                    const SizedBox(width: FFTokens.spacingLg),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 96),
                        children: rows,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _rangeControl() => FFSegmented(
    key: const Key('sales-range'),
    value: _range,
    options: [
      ('today', context.tr('vendor.sales.today')),
      ('7d', context.tr('vendor.stock.range.7dShort')),
      ('30d', context.tr('vendor.stock.range.30dShort')),
      ('custom', context.tr('vendor.stock.range.customShort')),
    ],
    onChanged: _pickRange,
  );

  Widget _filters() => Wrap(
    spacing: FFTokens.spacingSm,
    runSpacing: FFTokens.spacingXs,
    children: [
      for (final s in const ['all', 'completed', 'voided'])
        Semantics(
          inMutuallyExclusiveGroup: true,
          child: FFPill(
            key: Key('sales-filter-$s'),
            label: context.tr('vendor.sales.filter.$s'),
            filled: _status == s,
            onTap: () => _filter(() => _status = s),
          ),
        ),
      FFPill(
        key: const Key('sales-filter-mine'),
        label: context.tr('vendor.sales.filter.mine'),
        filled: _mine,
        onTap: () => _filter(() => _mine = !_mine),
      ),
      if (_tools.customers)
        Semantics(
          selected: _credit,
          child: FFPill(
            key: const Key('sales-filter-credit'),
            label: context.tr('vendor.sales.filter.credit'),
            filled: _credit,
            onTap: () => _filter(() => _credit = !_credit),
          ),
        ),
    ],
  );

  Widget _summaryCard() {
    final s = _summary!;
    final theme = Theme.of(context);
    final byMethod = (s['byMethod'] as List? ?? []).whereType<Map>().toList();
    final discounts = (s['discountTzs'] as num?) ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      child: FFCard(
        key: const Key('sales-summary'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Both tiles the same height, however the money shrinks.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: FFStatTile(
                      icon: Icons.receipt_long_outlined,
                      value: '${s['count'] ?? 0}',
                      label: context.tr('vendor.sales.count'),
                    ),
                  ),
                  const SizedBox(width: FFTokens.spacingSm),
                  Expanded(
                    child: FFStatTile(
                      icon: Icons.payments_outlined,
                      value: formatCurrency((s['totalTzs'] as num?) ?? 0),
                      label: context.tr('vendor.sales.total'),
                      // Money is never cut off: it shrinks to fit.
                      fitValue: true,
                    ),
                  ),
                ],
              ),
            ),
            // S7: refunds made in the range (minus undos) and the net.
            if (((s['refundTzs'] as num?) ?? 0) > 0)
              Text(
                fillIn(context.tr('vendor.sales.refundsLine'), {
                  'amount': formatCurrency(s['refundTzs'] as num),
                  'net': formatCurrency(
                    (s['netTzs'] as num?) ??
                        ((s['totalTzs'] as num?) ?? 0) -
                            (s['refundTzs'] as num),
                  ),
                }),
                key: const Key('sales-summary-refunds'),
                style: theme.textTheme.bodySmall,
              ),
            if (discounts > 0)
              MoneyRow(
                context.tr('vendor.sales.discountsGiven'),
                formatCurrency(discounts),
              ),
            if (byMethod.isNotEmpty) ...[
              const SizedBox(height: FFTokens.spacingSm),
              Text(
                context.tr('vendor.sales.byMethod'),
                style: theme.textTheme.labelLarge,
              ),
              for (final m in byMethod)
                MoneyRow(
                  methodLabel(context.tr, m['method']?.toString()),
                  formatCurrency((m['amountTzs'] as num?) ?? 0),
                ),
              // S4: what was left owing at the counter (byMethod + this =
              // total). Only sent to people with `customers`.
              if (((s['payLaterTzs'] as num?) ?? 0) > 0)
                MoneyRow(
                  context.tr('vendor.sales.payLaterBadge'),
                  formatCurrency(s['payLaterTzs'] as num),
                  key: const Key('sales-summary-paylater'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _serverRows() {
    if (_loading) {
      return [
        FFSkeletonList(semanticLabel: context.tr('vendor.sales.loading')),
      ];
    }
    switch (_problem) {
      case _Problem.suspended:
        // Shown once, by the paused notice above.
        return const [];
      case _Problem.failed || _Problem.network:
        return [
          FFErrorState(
            key: const Key('sales-failed'),
            title: _problem == _Problem.network
                ? context.tr('vendor.sales.offlineTitle')
                : null,
            message: context.tr(
              _problem == _Problem.network
                  ? 'vendor.sales.offline'
                  : 'vendor.sales.failed',
            ),
            onRetry: reload,
          ),
        ];
      case _Problem.none:
        break;
    }
    if (_sales.isEmpty) {
      return [
        if (_neverSold)
          FFEmptyState(
            key: const Key('sales-empty-first'),
            title: context.tr('vendor.sales.emptyFirst'),
            icon: Icons.point_of_sale_outlined,
            action: FFButton(
              label: context.tr('vendor.pos.newSale'),
              icon: Icons.add_shopping_cart,
              onPressed: () => context.push(posRoute),
            ),
          )
        else
          FFEmptyState(
            key: const Key('sales-empty'),
            title: context.tr('vendor.sales.empty'),
          ),
      ];
    }
    return [
      for (final s in _sales) _row(s),
      if (_moreFailed)
        FFAlert(
          message: context.tr('vendor.sales.failed'),
          tone: FFAlertTone.error,
        ),
      if (_cursor != null)
        Center(
          child: FFButton(
            key: const Key('sales-load-more'),
            label: context.tr(
              _moreFailed ? 'common.retry' : 'vendor.stock.loadMore',
            ),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            loading: _loadingMore,
            onPressed: _more,
          ),
        ),
    ];
  }

  Widget _row(Map<String, dynamic> s) {
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final id = s['id']?.toString() ?? '';
    final number = s['number']?.toString() ?? '';
    final voided = s['status'] == 'voided';
    final total = formatCurrency((s['totalTzs'] as num?) ?? 0);
    final time = eatDateTime(s['soldAt']?.toString(), locale: lang);
    final late =
        s['lateRecorded'] == true ||
        (s['lateRecorded'] == null &&
            recordedLate(s['soldAt']?.toString(), s['recordedAt']?.toString()));
    final override = s['hasOverride'] == true;
    final by = s['createdBy'] is Map
        ? (s['createdBy'] as Map)['name']?.toString()
        : null;
    final methods = methodsSummary(context, (s['methods'] as List? ?? []));
    final customer = s['customer'] is Map
        ? customerDisplayName(s['customer'] as Map, context.tr)
        : null;
    final kindBadges = saleKindBadges(context, s);
    // S7: Part refunded / Refunded.
    final refundState = voided ? 'none' : s['refundState']?.toString();
    final refundKey = switch (refundState) {
      'partial' => 'vendor.refunds.badgePartial',
      'full' => 'vendor.refunds.badgeFull',
      _ => null,
    };
    final status = context.tr(
      voided ? 'vendor.sales.voidedBadge' : 'vendor.sales.filter.completed',
    );
    return Padding(
      key: Key('sales-row-$id'),
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: FFCard(
        padding: EdgeInsets.zero,
        child: Semantics(
          button: true,
          label: [
            fillIn(context.tr('vendor.sales.rowLabel'), {
              'number': number,
              'amount': total,
              'time': time,
              'status': status,
            }),
            ?customer,
            if (s['kind'] == 'credit') ...[
              context.tr('vendor.sales.payLaterBadge'),
              if (!voided)
                (s['balanceTzs'] as num? ?? 0) > 0
                    ? fillIn(context.tr('vendor.sales.owesBadge'), {
                        'amount': formatCurrency(s['balanceTzs'] as num),
                      })
                    : context.tr('vendor.sales.paidOffBadge'),
            ],
            if (late) context.tr('vendor.sales.offlineBadge'),
            if (override) context.tr('vendor.sales.overrideBadge'),
            if (refundKey != null) context.tr(refundKey),
          ].join(', '),
          excludeSemantics: true,
          child: InkWell(
            onTap: salesIdPattern.hasMatch(id)
                ? () => context.push(saleDetailRoute(id))
                : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.all(FFTokens.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            number,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Text(
                          total,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            decoration: voided
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      [
                        time,
                        if (methods.isNotEmpty) methods,
                        ?by,
                        ?customer,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (voided ||
                        late ||
                        override ||
                        refundKey != null ||
                        kindBadges.isNotEmpty) ...[
                      const SizedBox(height: FFTokens.spacingXs),
                      Wrap(
                        spacing: FFTokens.spacingXs,
                        runSpacing: FFTokens.spacingXs,
                        children: [
                          ...kindBadges,
                          if (voided)
                            FFBadge(
                              label: context.tr('vendor.sales.voidedBadge'),
                              tone: FFBadgeTone.gray,
                            ),
                          if (late)
                            FFBadge(
                              label: context.tr('vendor.sales.offlineBadge'),
                              tone: FFBadgeTone.gray,
                              wrap: true,
                            ),
                          if (override)
                            FFBadge(
                              label: context.tr('vendor.sales.overrideBadge'),
                              tone: FFBadgeTone.warning,
                              wrap: true,
                            ),
                          if (refundKey != null)
                            FFBadge(
                              key: Key('sales-row-refund-$id'),
                              label: context.tr(refundKey),
                              tone: refundState == 'full'
                                  ? FFBadgeTone.gray
                                  : FFBadgeTone.info,
                              wrap: true,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
