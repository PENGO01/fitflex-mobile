// Vendor tools · S9: the Purchases view on tab 0 (spec §4.1) — what is owed
// to suppliers, Receive stock, Suppliers / Owed to suppliers, and recent
// deliveries; and the full list with filters ("See all"). No new tab: the
// Products tab gains a Products | Purchases switch; staff with only
// `purchases` see this view alone.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/network/browser_online.dart';
import '../sales/sales_widgets.dart' show warningText;
import '../stock/stock_options.dart';
import 'purchase_models.dart';
import 'purchases_widgets.dart';

class PurchasesHubView extends StatefulWidget {
  const PurchasesHubView({super.key, this.disabled = false});

  /// Staff switched off / business suspended: write buttons disabled.
  final bool disabled;

  @override
  State<PurchasesHubView> createState() => PurchasesHubViewState();
}

class PurchasesHubViewState extends State<PurchasesHubView> {
  Map<String, dynamic>? _aging;
  Object? _agingError;
  List<Map<String, dynamic>>? _recent;
  Object? _recentError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => reload());
  }

  /// Pull to refresh (each card on its own: one failing never hides the
  /// other).
  Future<void> reload() async {
    final api = AppScope.of(context).api;
    await Future.wait([
      () async {
        try {
          final res = await api.vendorPayablesAging(limit: 1);
          if (mounted) {
            setState(() {
              _aging = res;
              _agingError = null;
            });
          }
        } catch (e) {
          if (mounted) setState(() => _agingError = e);
        }
      }(),
      () async {
        try {
          final res = await api.vendorPurchases(limit: 20);
          if (mounted) {
            setState(() {
              _recent = mapsOf(res['purchases']);
              _recentError = null;
            });
          }
        } catch (e) {
          if (mounted) setState(() => _recentError = e);
        }
      }(),
    ]);
  }

  Future<void> _go(String path) async {
    await context.push(path);
    if (mounted) await reload();
  }

  String _errorKey(Object e) => purchaseLoadErrorKey(e);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final left = [_owedCard(), ..._actions()];
        final right = _recentList();
        if (box.maxWidth >= 900) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: _list(left)),
                  Expanded(flex: 6, child: _list(right)),
                ],
              ),
            ),
          );
        }
        return _list([...left, ...right]);
      },
    );
  }

  Widget _list(List<Widget> children) => ListView(
    key: const Key('purchases-hub'),
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(FFTokens.spacingLg),
    children: children,
  );

  Widget _owedCard() {
    final t = context.tr;
    final theme = Theme.of(context);
    if (_agingError != null && _aging == null) {
      return FFErrorState(
        key: const Key('purchases-owed-error'),
        message: t(_errorKey(_agingError!)),
        onRetry: reload,
      );
    }
    if (_aging == null) return const FFSkeletonCard();
    final totals = mapOf(_aging!['totals']);
    final owed = intOfP(totals['owedTzs']);
    final overdue = intOfP(totals['overdueTzs']);
    final soon = intOfP(totals['dueIn7DaysTzs']);
    return Semantics(
      container: true,
      button: true,
      onTap: () => _go(payablesRoute),
      child: FFCard(
        key: const Key('purchases-owed-card'),
        child: InkWell(
          onTap: () => _go(payablesRoute),
          child: owed == 0
              ? ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      t('vendor.payables.nothingOwed'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t('vendor.payables.youOwe'),
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      formatCurrency(owed),
                      key: const Key('purchases-owed'),
                      style: theme.textTheme.titleLarge,
                    ),
                    if (overdue > 0)
                      Text(
                        fillIn(t('vendor.purchases.overdueAmount'), {
                          'amount': formatCurrency(overdue),
                        }),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: warningText(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Text(
                      '${t('vendor.payables.dueSoon')}: ${formatCurrency(soon)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  List<Widget> _actions() {
    final t = context.tr;
    return [
      const SizedBox(height: FFTokens.spacingMd),
      FFButton(
        key: const Key('purchases-receive'),
        label: t('vendor.purchases.receive'),
        icon: Icons.local_shipping,
        fullWidth: true,
        onPressed: widget.disabled ? null : () => _go(receiveStockRoute),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      LayoutBuilder(
        builder: (context, box) {
          final tiles = [
            FFActionTile(
              key: const Key('purchases-suppliers'),
              icon: Icons.storefront_outlined,
              title: t('vendor.suppliers.title'),
              onTap: () => _go(suppliersRoute),
            ),
            FFActionTile(
              key: const Key('purchases-payables'),
              icon: Icons.account_balance_wallet_outlined,
              title: t('vendor.payables.title'),
              onTap: () => _go(payablesRoute),
            ),
          ];
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          if (box.maxWidth / 2 < 160 || textScale > 1.5) {
            return Column(
              children: [
                tiles[0],
                const SizedBox(height: FFTokens.spacingSm),
                tiles[1],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: tiles[0]),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(child: tiles[1]),
            ],
          );
        },
      ),
      const SizedBox(height: FFTokens.spacingMd),
    ];
  }

  List<Widget> _recentList() {
    final t = context.tr;
    final rows = _recent;
    return [
      Row(
        children: [
          Expanded(child: FFSectionTitle(t('vendor.purchases.recent'))),
          if (rows != null && rows.isNotEmpty)
            FFButton(
              key: const Key('purchases-see-all'),
              label: t('vendor.purchases.seeAll'),
              variant: FFButtonVariant.ghost,
              visualDensity: VisualDensity.standard,
              onPressed: () => _go(purchasesListRoute),
            ),
        ],
      ),
      if (_recentError != null && rows == null)
        FFErrorState(
          key: const Key('purchases-recent-error'),
          message: t(_errorKey(_recentError!)),
          onRetry: reload,
        )
      else if (rows == null)
        FFSkeletonList(semanticLabel: t('vendor.purchases.loading'))
      else if (rows.isEmpty)
        FFEmptyState(
          key: const Key('purchases-empty'),
          title: t('vendor.purchases.empty'),
          icon: Icons.local_shipping_outlined,
        )
      else
        FFCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final r in rows)
                PurchaseRowTile(
                  row: r,
                  onTap: purchaseIdPattern.hasMatch('${r['id']}')
                      ? () => _go(purchaseRoute('${r['id']}'))
                      : null,
                ),
            ],
          ),
        ),
    ];
  }
}

/// "See all": every purchase with filters (All · Owing · Overdue ·
/// Voided) and Load more.
class PurchasesListPage extends StatefulWidget {
  const PurchasesListPage({super.key});

  @override
  State<PurchasesListPage> createState() => _PurchasesListPageState();
}

class _PurchasesListPageState extends State<PurchasesListPage> {
  static const _filters = ['all', 'owing', 'overdue', 'voided'];
  String _filter = 'all';
  List<Map<String, dynamic>> _rows = [];
  String? _cursor;
  bool _ready = false;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    BrowserOnline.instance.addListener(_redraw);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await enterPurchasesRoute(context) == null || !mounted) return;
      setState(() => _ready = true);
      await _load();
    });
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    BrowserOnline.instance.removeListener(_redraw);
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      if (!more) _loading = true;
      _error = null;
    });
    try {
      final res = await AppScope.of(context).api.vendorPurchases(
        status: _filter == 'voided'
            ? 'voided'
            : _filter == 'all'
            ? null
            : 'received',
        payment: switch (_filter) {
          'owing' => 'open',
          'overdue' => 'overdue',
          _ => null,
        },
        cursor: more ? _cursor : null,
      );
      if (!mounted) return;
      setState(() {
        final rows = mapsOf(res['purchases']);
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

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    return Scaffold(
      appBar: AppBar(title: Text(t('vendor.purchases.listTitle'))),
      body: !_ready
          ? const Center(child: FFSpinner())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  Wrap(
                    spacing: FFTokens.spacingXs,
                    runSpacing: FFTokens.spacingXs,
                    children: [
                      for (final f in _filters)
                        Semantics(
                          selected: _filter == f,
                          inMutuallyExclusiveGroup: true,
                          child: FFPill(
                            key: Key('purchases-filter-$f'),
                            label: t('vendor.purchases.filter.$f'),
                            filled: _filter == f,
                            onTap: () {
                              setState(() => _filter = f);
                              _load();
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: FFTokens.spacingMd),
                  if (_loading)
                    FFSkeletonList(semanticLabel: t('vendor.purchases.loading'))
                  else if (_error != null)
                    FFErrorState(
                      message: t(purchaseLoadErrorKey(_error!)),
                      onRetry: _load,
                    )
                  else if (_rows.isEmpty)
                    FFEmptyState(
                      key: const Key('purchases-list-empty'),
                      title: t(
                        _filter == 'all'
                            ? 'vendor.purchases.empty'
                            : 'vendor.purchases.emptyFilter',
                      ),
                    )
                  else
                    FFCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final r in _rows)
                            PurchaseRowTile(
                              row: r,
                              onTap: purchaseIdPattern.hasMatch('${r['id']}')
                                  ? () async {
                                      await context.push(
                                        purchaseRoute('${r['id']}'),
                                      );
                                      if (mounted) await _load();
                                    }
                                  : null,
                            ),
                        ],
                      ),
                    ),
                  if (_cursor != null)
                    Center(
                      child: FFButton(
                        key: const Key('purchases-list-more'),
                        label: t('vendor.stock.loadMore'),
                        variant: FFButtonVariant.ghost,
                        onPressed: () => _load(more: true),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Test hook: whether a hub reload is cheap to call (keeps the import of
/// canVendor in one place for the home page).
bool purchasesAllowed(BuildContext context, VendorTools tools) =>
    purchasesOn(tools, (p) => canVendor(context, p));
