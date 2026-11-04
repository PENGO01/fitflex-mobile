// Vendor tools · S9: Owed to suppliers (spec §4.8; the S4 §10 layout with
// supplier wording). Summary tiles, five bucket tiles as filters, rows most
// overdue first. Figures are the server's (never summed here). FitFlex
// moves no money: these are records only.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../customers/customer_models.dart' show formatDay;
import '../customers/customers_widgets.dart' show AgingTiles, overdueBadge;
import '../stock/stock_options.dart';
import 'purchase_models.dart';
import 'purchases_widgets.dart';

class PayablesPage extends StatefulWidget {
  const PayablesPage({super.key});

  @override
  State<PayablesPage> createState() => _PayablesPageState();
}

class _PayablesPageState extends State<PayablesPage> {
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _rows = [];
  String? _cursor;
  String? _bucket;
  bool _ready = false;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await enterPurchasesRoute(context) == null || !mounted) return;
      setState(() => _ready = true);
      await _load();
    });
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      if (!more) _loading = true;
      _error = null;
    });
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorPayablesAging(bucket: _bucket, cursor: more ? _cursor : null);
      if (!mounted) return;
      setState(() {
        _data = res;
        final rows = mapsOf(res['rows']);
        _rows = more ? [..._rows, ...rows] : rows;
        _cursor = strOf(res['nextCursor']);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  void _select(String? bucket) {
    setState(() => _bucket = _bucket == bucket ? null : bucket);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    return Scaffold(
      appBar: AppBar(title: Text(t('vendor.payables.title'))),
      body: !_ready
          ? const Center(child: FFSpinner())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: _content(),
              ),
            ),
    );
  }

  List<Widget> _content() {
    final t = context.tr;
    final theme = Theme.of(context);
    final lang = langOf(context);
    if (_loading && _data == null) {
      return [FFSkeletonList(semanticLabel: t('vendor.payables.loading'))];
    }
    if (_error != null && _data == null) {
      return [
        FFErrorState(
          message: t(
            purchaseLoadErrorKey(_error!) == 'vendor.purchases.failed'
                ? 'vendor.payables.failed'
                : purchaseLoadErrorKey(_error!),
          ),
          onRetry: _load,
        ),
      ];
    }
    final d = _data ?? const {};
    final totals = mapOf(d['totals']);
    final owed = intOfP(totals['owedTzs']);
    Widget stat(String key, String label, String value) => SizedBox(
      width: 160,
      child: FFCard(
        key: Key('payables-$key'),
        child: Semantics(
          container: true,
          label: '$label, $value',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: theme.textTheme.titleMedium),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
    return [
      Wrap(
        spacing: FFTokens.spacingSm,
        runSpacing: FFTokens.spacingSm,
        children: [
          stat('total', t('vendor.payables.total'), formatCurrency(owed)),
          stat(
            'overdue',
            t('vendor.purchases.state.overdue'),
            formatCurrency(intOfP(totals['overdueTzs'])),
          ),
          stat(
            'suppliers',
            t('vendor.payables.suppliersYouOwe'),
            '${intOfP(totals['supplierCount'])}',
          ),
          stat(
            'due-soon',
            t('vendor.payables.dueSoon'),
            formatCurrency(intOfP(totals['dueIn7DaysTzs'])),
          ),
        ],
      ),
      const SizedBox(height: FFTokens.spacingXs),
      Text(
        fillIn(t('vendor.customers.asOf'), {
          'date': formatDay(d['asOf']?.toString(), locale: lang),
        }),
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: FFTokens.spacingMd),
      AgingTiles(
        aging: totals,
        selected: _bucket,
        onSelect: _select,
        keyPrefix: 'payables-bucket',
      ),
      if (_bucket != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingXs),
            child: FFPill(
              key: const Key('payables-all'),
              label: t('vendor.purchases.filter.all'),
              onTap: () => _select(null),
            ),
          ),
        ),
      const SizedBox(height: FFTokens.spacingMd),
      if (_rows.isEmpty)
        FFEmptyState(
          key: const Key('payables-empty'),
          title: t(
            _bucket == null
                ? 'vendor.payables.empty'
                : 'vendor.payables.emptyBucket',
          ),
        )
      else
        FFCard(
          padding: EdgeInsets.zero,
          child: Column(children: [for (final r in _rows) _row(r)]),
        ),
      if (_cursor != null)
        Center(
          child: FFButton(
            key: const Key('payables-more'),
            label: t('vendor.stock.loadMore'),
            variant: FFButtonVariant.ghost,
            onPressed: () => _load(more: true),
          ),
        ),
      const SizedBox(height: FFTokens.spacingMd),
      const PurchaseMoneyNotice(),
    ];
  }

  Widget _row(Map<String, dynamic> r) {
    final t = context.tr;
    final theme = Theme.of(context);
    final lang = langOf(context);
    final id = r['supplierId']?.toString() ?? '';
    final name = r['name']?.toString() ?? '';
    final owed = formatCurrency(intOfP(r['owedTzs']));
    final overdue = intOfP(r['overdueTzs']);
    final days = intOfP(r['maxDaysOverdue']);
    final open = purchaseIdPattern.hasMatch(id)
        ? () => context.push(supplierRoute(id))
        : null;
    return Semantics(
      container: true,
      button: open != null,
      onTap: open,
      label: fillIn(t('vendor.payables.rowLabel'), {
        'name': name,
        'amount': owed,
        'overdue': formatCurrency(overdue),
      }),
      excludeSemantics: true,
      child: InkWell(
        key: Key('payables-row-$id'),
        onTap: open,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FFTokens.spacingMd,
              vertical: FFTokens.spacingSm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: theme.textTheme.titleSmall),
                      Text(
                        fillIn(t('vendor.suppliers.youOwe'), {'amount': owed}),
                      ),
                      if (overdue > 0)
                        Text(
                          fillIn(t('vendor.purchases.overdueAmount'), {
                            'amount': formatCurrency(overdue),
                          }),
                          style: theme.textTheme.bodySmall,
                        ),
                      if (strOf(r['oldestDueDate']) case final due?)
                        Text(
                          '${t('vendor.payables.oldestDue')}: ${formatDay(due, locale: lang)}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (days > 0)
                  Flexible(
                    child: overdueBadge(
                      context,
                      label: fillIn(t('vendor.customers.daysOverdue'), {
                        'n': days,
                      }),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
