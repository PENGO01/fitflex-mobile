// Vendor tools · S4: one customer (spec §5) — owed and aging, totals, open
// pay-later sales, activity (shop sales, app orders, payments), and the
// place to record a payment. Online only; nothing is kept on the device.
//
// A-02: an app customer shows a name only — never phone, email or address,
// even while one of their orders is inside its contact window.
import '../../../shared/network/browser_online.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/shop_checkout.dart';
import '../sales/receipt_data.dart' show eatDateTime;
import '../sales/sales_widgets.dart';
import '../stock/stock_options.dart';
import '../sales/sale_models.dart' show pluralKey;
import 'customer_models.dart';
import 'customers_widgets.dart';
import 'payment_sheets.dart';

/// Opens the phone app; tests replace it.
@visibleForTesting
Future<bool> Function(Uri uri) customerDialer = (uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

class CustomerProfilePage extends StatefulWidget {
  const CustomerProfilePage({
    super.key,
    required this.customerId,
    this.phoneDuplicate,
  });

  final String customerId;

  /// Just saved with a phone another customer has (Q-7): `{id, name}`.
  final Map<String, dynamic>? phoneDuplicate;

  @override
  State<CustomerProfilePage> createState() => _CustomerProfilePageState();
}

class _Activity {
  List<Map<String, dynamic>> rows = [];
  String? cursor;
  bool loading = false;
  bool loaded = false;
  bool failed = false;
}

class _CustomerProfilePageState extends State<CustomerProfilePage> {
  // No answer from the server on the last call: Record payment is greyed
  // out (a payment is never queued). Any answer, from any screen, clears it.
  bool _requestOffline = false;

  /// Offline: a call got no answer, or (web) the browser says offline.
  bool get _offline => _requestOffline || !BrowserOnline.instance.value;
  ApiClient? _api;
  Map<String, dynamic>? _customer;
  bool _loading = true;
  CustomerLoadProblem _problem = CustomerLoadProblem.none;
  late Map<String, dynamic>? _dup = widget.phoneDuplicate;
  String _tab = 'sales';
  final _activity = {
    'sales': _Activity(),
    'orders': _Activity(),
    'payments': _Activity(),
  };
  final _heading = FocusNode();

  /// Owes nothing but bought on credit before: "All paid off" (§5.1).
  bool _hadCredit = false;

  String get _id => widget.customerId;

  @override
  void initState() {
    super.initState();
    BrowserOnline.instance.addListener(_onBrowserOnline);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _onBrowserOnline() {
    if (mounted) setState(() {});
  }

  /// UAT D1: the same page shown for another customer (deep link or hash
  /// change while a profile is open). Nothing of the old customer stays on
  /// screen, and answers for the old one are dropped when they land.
  @override
  void didUpdateWidget(CustomerProfilePage old) {
    super.didUpdateWidget(old);
    if (old.customerId == widget.customerId) return;
    setState(() {
      _customer = null;
      _loading = true;
      _problem = CustomerLoadProblem.none;
      _dup = widget.phoneDuplicate;
      _tab = 'sales';
      _hadCredit = false;
      for (final k in _activity.keys.toList()) {
        _activity[k] = _Activity();
      }
    });
    if (_api != null) unawaited(_load());
  }

  @override
  void dispose() {
    BrowserOnline.instance.removeListener(_onBrowserOnline);
    _api?.removeSuccessListener(_onAnswer);
    _heading.dispose();
    super.dispose();
  }

  void _onAnswer(String method, String path) {
    if (_requestOffline && mounted) setState(() => _requestOffline = false);
  }

  /// Whether [e] means "no answer at all" (no connection).
  void _noteFailure(Object e) {
    if (e is! ApiException && mounted && !_requestOffline) {
      setState(() => _requestOffline = true);
    }
  }

  Future<void> _start() async {
    final tools = await enterCustomersRoute(context);
    if (tools == null || !mounted) return;
    _api = AppScope.of(context).api..addSuccessListener(_onAnswer);
    await _load();
    if (mounted) _heading.requestFocus();
  }

  Future<void> _load() async {
    final id = _id;
    setState(() {
      _loading = true;
      _problem = CustomerLoadProblem.none;
    });
    try {
      final res = await AppScope.of(context).api.vendorCustomer(id);
      final c = res['customer'];
      if (c is! Map) throw ApiException(404, null);
      if (!mounted || id != _id) return;
      final customer = Map<String, dynamic>.from(c);
      CustomerRepository.remember(
        context,
        _id,
        customerDisplayName(customer, context.tr),
      );
      setState(() {
        _customer = customer;
        _loading = false;
        for (final a in _activity.values) {
          a.loaded = false;
        }
      });
      unawaited(_loadActivity(_tab));
      if (intOf(customer['owedTzs']) <= 0) unawaited(_checkCredit());
    } catch (e) {
      if (!mounted || id != _id) return;
      _noteFailure(e);
      if (mounted && _customer != null) {
        // A refresh failed: keep what is shown (memory only).
        setState(() => _loading = false);
        if (e is! ApiException) {
          FFSnack.error(context, context.tr('error.network'));
        }
      } else if (mounted) {
        setState(() {
          _loading = false;
          _problem = problemOf(e);
        });
      }
    }
  }

  Future<void> _checkCredit() async {
    final id = _id;
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorCustomerSales(id, kind: 'credit', limit: 1);
      final any = (res['sales'] as List? ?? []).isNotEmpty;
      if (mounted && id == _id && any != _hadCredit) {
        setState(() => _hadCredit = any);
      }
    } catch (_) {
      // No "paid off" line; nothing else depends on it.
    }
  }

  Future<void> _loadActivity(String tab, {bool more = false}) async {
    final id = _id;
    final a = _activity[tab]!;
    if (a.loading) return;
    setState(() {
      a.loading = true;
      a.failed = false;
    });
    final api = AppScope.of(context).api;
    final cursor = more ? a.cursor : null;
    try {
      final Map<String, dynamic> res = switch (tab) {
        'orders' => await api.vendorCustomerOrders(
          id,
          limit: activityPageSize,
          cursor: cursor,
        ),
        'payments' => await api.vendorCustomerPayments(
          id,
          limit: activityPageSize,
          cursor: cursor,
        ),
        _ => await api.vendorCustomerSales(
          id,
          limit: activityPageSize,
          cursor: cursor,
        ),
      };
      final key = switch (tab) {
        'orders' => 'orders',
        'payments' => 'payments',
        _ => 'sales',
      };
      final rows = [
        for (final r in (res[key] as List? ?? []).whereType<Map>())
          Map<String, dynamic>.from(r),
      ];
      // The page moved on to another customer: this list is stale.
      if (!mounted || id != _id) return;
      setState(() {
        a.rows = more ? [...a.rows, ...rows] : rows;
        a.cursor = res['nextCursor']?.toString();
        a.loading = false;
        a.loaded = true;
      });
    } catch (e) {
      if (!mounted || id != _id) return;
      _noteFailure(e);
      if (mounted) {
        setState(() {
          a.loading = false;
          a.failed = true;
        });
      }
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(customersHomeRoute);
    }
  }

  String get _name => customerDisplayName(_customer, context.tr);

  Future<void> _recordPayment() async {
    if (_customer == null || _offline) return;
    // Fresh balances before the form opens; with no connection it never
    // opens (nothing to fill in only to be refused).
    final Map<String, dynamic> c;
    try {
      final res = await AppScope.of(context).api.vendorCustomer(_id);
      final fresh = res['customer'];
      if (fresh is! Map) throw ApiException(404, null);
      c = Map<String, dynamic>.from(fresh);
    } catch (e) {
      _noteFailure(e);
      if (mounted) {
        FFSnack.error(
          context,
          context.tr(
            e is ApiException
                ? 'vendor.customers.failed'
                : 'vendor.pay.offline',
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _customer = c);
    if (intOf(c['owedTzs']) <= 0) return;
    final out = await recordCustomerPayment(context, customer: c);
    if (out != null && mounted) {
      _activity['payments']!.loaded = false;
      await _load();
    }
  }

  Future<void> _openPayment(Map<String, dynamic> p) async {
    final changed = await showPaymentReceipt(
      context,
      customerId: _id,
      customerName: _name,
      payment: p,
      stillOwedTzs: intOf(_customer?['owedTzs']),
      customerArchived: _customer?['archived'] == true,
    );
    if (changed && mounted) {
      _activity['payments']!.loaded = false;
      await _load();
    }
  }

  Future<void> _edit() async {
    final out = await context.push<Object?>(editCustomerRoute(_id));
    if (!mounted) return;
    if (out is Map && out['phoneDuplicate'] is Map) {
      setState(
        () => _dup = Map<String, dynamic>.from(out['phoneDuplicate'] as Map),
      );
    }
    await _load();
  }

  Future<void> _setArchived(bool archived) async {
    final c = _customer!;
    if (archived) {
      final owed = intOf(c['owedTzs']);
      if (owed > 0) {
        FFSnack.warning(
          context,
          fillIn(context.tr('vendor.customers.archiveHasBalance'), {
            'amount': formatCurrency(owed),
          }),
        );
        return;
      }
      final ok = await showFFConfirmDialog(
        context,
        title: fillIn(context.tr('vendor.customers.archiveTitle'), {
          'name': _name,
        }),
        message: context.tr('vendor.customers.archiveBody'),
        confirmLabel: context.tr('vendor.customers.archive'),
        destructive: true,
        confirmKey: const Key('customer-archive-confirm'),
      );
      if (!ok || !mounted) return;
    }
    try {
      await AppScope.of(context).api.vendorUpdateCustomer(_id, {
        'archived': archived,
        'updatedAt': ?c['updatedAt'],
      });
      if (mounted) await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      final b = e.body is Map ? e.body as Map : const {};
      FFSnack.error(context, switch (e.code) {
        'customer_has_balance' => fillIn(
          context.tr('vendor.customers.archiveHasBalance'),
          {'amount': formatCurrency(intOf(b['owedTzs']))},
        ),
        'customer_changed' => context.tr('vendor.customers.changedElsewhere'),
        _ => context.tr('vendor.saveFailed'),
      });
      if (e.code == 'customer_changed') await _load();
    } catch (_) {
      if (mounted) {
        FFSnack.error(context, context.tr('vendor.customers.saveOffline'));
      }
    }
  }

  Future<void> _call(String phone) async {
    await customerDialer(Uri(scheme: 'tel', path: phone));
  }

  @override
  Widget build(BuildContext context) {
    final c = _customer;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(c == null ? context.tr('vendor.customers.tab') : _name),
        actions: [
          if (c != null)
            PopupMenuButton<String>(
              key: const Key('customer-menu'),
              tooltip: context.tr('vendor.pos.more'),
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                visualDensity: VisualDensity.standard,
              ),
              onSelected: (v) => switch (v) {
                'edit' => _edit(),
                'statement' => context.push(statementRoute(_id)),
                'archive' => _setArchived(true),
                'restore' => _setArchived(false),
                _ => null,
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: const Key('customer-menu-edit'),
                  value: 'edit',
                  child: Text(context.tr('vendor.customers.editTitle')),
                ),
                PopupMenuItem(
                  key: const Key('customer-menu-statement'),
                  value: 'statement',
                  child: Text(context.tr('vendor.statement.share')),
                ),
                PopupMenuItem(
                  key: Key(
                    c['archived'] == true
                        ? 'customer-menu-restore'
                        : 'customer-menu-archive',
                  ),
                  value: c['archived'] == true ? 'restore' : 'archive',
                  child: Text(
                    context.tr(
                      c['archived'] == true
                          ? 'vendor.customers.restore'
                          : 'vendor.customers.archive',
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _loading && c == null
          ? Padding(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              child: FFSkeletonList(
                semanticLabel: context.tr('vendor.customers.loading'),
              ),
            )
          : c == null
          ? ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                customerErrorState(
                  context,
                  _problem,
                  key: const Key('customer-failed'),
                  failedKey: 'vendor.customers.failed',
                  onRetry: _load,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                Center(
                  child: FFButton(
                    label: context.tr('vendor.customers.back'),
                    variant: FFButtonVariant.ghost,
                    visualDensity: VisualDensity.standard,
                    onPressed: () => context.go(customersHomeRoute),
                  ),
                ),
              ],
            )
          : RefreshIndicator(onRefresh: _load, child: _content(c)),
    );
  }

  Widget _content(Map<String, dynamic> c) {
    return LayoutBuilder(
      builder: (context, box) {
        final left = [
          _header(c),
          if (_dup != null) _dupAlert(),
          _owedCard(c),
          _totals(c),
          if ((c['note']?.toString() ?? '').trim().isNotEmpty) _note(c),
        ];
        final right = [_openSales(c), _activityCard()];
        if (box.maxWidth >= 900) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 360,
                    child: ListView(
                      padding: const EdgeInsets.all(FFTokens.spacingLg),
                      children: _spaced(left),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(FFTokens.spacingLg),
                      children: _spaced(right),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          key: const Key('customer-profile'),
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: _spaced([...left, ...right]),
        );
      },
    );
  }

  List<Widget> _spaced(List<Widget> ws) => [
    for (final w in ws)
      Padding(
        padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
        child: w,
      ),
  ];

  Widget _header(Map<String, dynamic> c) {
    final theme = Theme.of(context);
    final manual = c['source'] == 'manual';
    final phone = manual ? c['phone']?.toString() : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          focusNode: _heading,
          child: Semantics(
            header: true,
            child: Text(
              _name,
              key: const Key('customer-name-heading'),
              style: theme.textTheme.headlineSmall,
            ),
          ),
        ),
        const SizedBox(height: FFTokens.spacingXs),
        Wrap(
          spacing: FFTokens.spacingXs,
          runSpacing: FFTokens.spacingXs,
          children: [
            customerSourceBadge(context, c),
            if (c['archived'] == true)
              FFBadge(
                key: const Key('customer-archived-badge'),
                label: context.tr('vendor.customers.badge.archived'),
                tone: FFBadgeTone.gray,
              ),
          ],
        ),
        // A-02: an app customer's contact details stay on the order.
        if (!manual) ...[
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            context.tr('vendor.customers.appContactHint'),
            key: const Key('customer-app-contact-hint'),
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (phone != null && phone.isNotEmpty) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FFButton(
              key: const Key('customer-call'),
              label: phone,
              semanticLabel: fillIn(context.tr('vendor.customers.call'), {
                'name': _name,
              }),
              icon: Icons.call_outlined,
              variant: FFButtonVariant.secondary,
              visualDensity: VisualDensity.standard,
              onPressed: () => _call(phone),
            ),
          ),
        ],
        if (manual &&
            ((c['email']?.toString() ?? '').isNotEmpty ||
                (c['address']?.toString() ?? '').isNotEmpty)) ...[
          const SizedBox(height: FFTokens.spacingXs),
          if ((c['email']?.toString() ?? '').isNotEmpty)
            Text(c['email'].toString(), style: theme.textTheme.bodySmall),
          if ((c['address']?.toString() ?? '').isNotEmpty)
            Text(c['address'].toString(), style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }

  Widget _dupAlert() {
    final dup = _dup!;
    final id = dup['id']?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFAlert(
          key: const Key('customer-phone-duplicate'),
          message: fillIn(context.tr('vendor.customers.phoneDuplicate'), {
            'name': customerDisplayName(dup, context.tr),
          }),
          tone: FFAlertTone.warning,
        ),
        if (customerIdPattern.hasMatch(id) && id != _id)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FFButton(
              key: const Key('customer-phone-duplicate-open'),
              label: context.tr('vendor.customers.open'),
              variant: FFButtonVariant.ghost,
              visualDensity: VisualDensity.standard,
              onPressed: () => context.push(customerRoute(id)),
            ),
          ),
      ],
    );
  }

  Widget _owedCard(Map<String, dynamic> c) {
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final owed = intOf(c['owedTzs']);
    final overdue = intOf(c['overdueTzs']);
    final aging = c['aging'] is Map ? c['aging'] as Map : const {};
    if (owed <= 0) {
      if (!_hadCredit) return const SizedBox.shrink();
      return FFAlert(
        key: const Key('customer-paid-off'),
        message: context.tr('vendor.customers.paidOff'),
        tone: FFAlertTone.success,
      );
    }
    return FFCard(
      key: const Key('customer-owed-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('vendor.customers.owes'),
            style: theme.textTheme.labelLarge,
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              formatCurrency(owed),
              key: const Key('customer-owed'),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (overdue > 0)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: overdueBadge(
                  context,
                  label: fillIn(context.tr('vendor.customers.overdueAmount'), {
                    'amount': formatCurrency(overdue),
                  }),
                ),
              ),
            ),
          const SizedBox(height: FFTokens.spacingMd),
          AgingTiles(aging: aging, keyPrefix: 'customer-aging'),
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            fillIn(context.tr('vendor.customers.asOf'), {
              'date': formatDay(c['asOf']?.toString(), locale: lang),
            }),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          FFButton(
            key: const Key('customer-record-payment'),
            label: context.tr('vendor.pay.record'),
            icon: Icons.payments_outlined,
            fullWidth: true,
            visualDensity: VisualDensity.standard,
            onPressed: c['archived'] != true && !_offline
                ? _recordPayment
                : null,
          ),
          if (_offline)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                context.tr('vendor.pay.offline'),
                key: const Key('customer-record-payment-offline'),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _totals(Map<String, dynamic> c) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final t = c['totals'] is Map ? c['totals'] as Map : const {};
    final last = t['lastPurchaseAt'] ?? c['lastPurchaseAt'];
    final tiles = [
      FFStatTile(
        icon: Icons.point_of_sale_outlined,
        value: formatCurrency(intOf(t['shopSalesTzs'])),
        label:
            '${context.tr('vendor.customers.shopSales')} (${intOf(t['shopSalesCount'])})',
        fitValue: true,
      ),
      if (c['source'] == 'marketplace')
        FFStatTile(
          icon: Icons.shopping_bag_outlined,
          value: formatCurrency(intOf(t['appOrdersTzs'])),
          label:
              '${context.tr('vendor.customers.appOrders')} (${intOf(t['appOrdersCount'])})',
          fitValue: true,
        ),
      if (last != null)
        FFStatTile(
          icon: Icons.event_outlined,
          value: formatDate(last, locale: lang),
          label: context.tr('vendor.customers.lastBoughtLabel'),
          fitValue: true,
        ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final perRow = box.maxWidth < 420 ? 2 : 3;
        const gap = FFTokens.spacingSm;
        final w = (box.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          key: const Key('customer-totals'),
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }

  Widget _note(Map<String, dynamic> c) {
    final theme = Theme.of(context);
    return Text(
      fillIn(context.tr('vendor.sales.noteLabel'), {'note': c['note']}),
      key: const Key('customer-note-text'),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _openSales(Map<String, dynamic> c) {
    final open = openSalesOf(c);
    if (open.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    return Column(
      key: const Key('customer-open-sales'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            context.tr('vendor.customers.openSales'),
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        for (final s in open)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: FFCard(
              padding: EdgeInsets.zero,
              child: InkWell(
                key: Key('customer-open-sale-${s.id}'),
                onTap: salesIdPattern.hasMatch(s.id)
                    ? () async {
                        await context.push(customerSaleRoute(_id, s.id));
                        if (mounted) unawaited(_load());
                      }
                    : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Padding(
                    padding: const EdgeInsets.all(FFTokens.spacingMd),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MoneyRow(s.number, formatCurrency(s.balanceTzs)),
                        Wrap(
                          spacing: FFTokens.spacingXs,
                          runSpacing: FFTokens.spacingXs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              [
                                formatDate(s.soldAt, locale: lang),
                                fillIn(context.tr('vendor.customers.dueOn'), {
                                  'date': formatDay(s.dueDate, locale: lang),
                                }),
                              ].join(' · '),
                              style: theme.textTheme.bodySmall,
                            ),
                            if (s.daysOverdue > 0)
                              overdueBadge(
                                context,
                                label: fillIn(
                                  context.tr(
                                    pluralKey(
                                      'vendor.customers.daysOverdue',
                                      s.daysOverdue,
                                    ),
                                  ),
                                  {'n': s.daysOverdue},
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _activityCard() {
    final a = _activity[_tab]!;
    final rows = <Widget>[];
    if (!a.loaded && a.loading) {
      rows.add(
        FFSkeletonList(semanticLabel: context.tr('vendor.customers.loading')),
      );
    } else if (a.failed && !a.loaded) {
      rows.add(
        FFAlert(
          key: const Key('customer-activity-failed'),
          message: context.tr('vendor.customers.activityFailed'),
          tone: FFAlertTone.error,
        ),
      );
      rows.add(
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FFButton(
            label: context.tr('common.retry'),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: () => _loadActivity(_tab),
          ),
        ),
      );
    } else if (a.rows.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          child: Text(
            context.tr('vendor.customers.noActivity'),
            key: const Key('customer-activity-empty'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      for (final r in a.rows) {
        rows.add(switch (_tab) {
          'orders' => _orderRow(r),
          'payments' => _paymentRow(r),
          _ => _saleRow(r),
        });
      }
      if (a.failed) {
        rows.add(
          FFAlert(
            message: context.tr('vendor.customers.activityFailed'),
            tone: FFAlertTone.error,
          ),
        );
      }
      if (a.cursor != null) {
        rows.add(
          Center(
            child: FFButton(
              key: const Key('customer-activity-more'),
              label: context.tr(
                a.failed ? 'common.retry' : 'vendor.stock.loadMore',
              ),
              variant: FFButtonVariant.ghost,
              visualDensity: VisualDensity.standard,
              loading: a.loading,
              onPressed: () => _loadActivity(_tab, more: true),
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFSegmented(
          key: const Key('customer-activity-tabs'),
          value: _tab,
          options: [
            ('sales', context.tr('vendor.customers.shopSales')),
            if (_customer?['source'] == 'marketplace')
              ('orders', context.tr('vendor.customers.appOrders')),
            ('payments', context.tr('vendor.customers.payments')),
          ],
          onChanged: (v) {
            setState(() => _tab = v);
            if (!_activity[v]!.loaded) unawaited(_loadActivity(v));
          },
        ),
        const SizedBox(height: FFTokens.spacingSm),
        ...rows,
      ],
    );
  }

  Widget _rowCard({
    required Key key,
    required List<Widget> children,
    VoidCallback? onTap,
    String? semantics,
  }) => Padding(
    key: key,
    padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
    child: FFCard(
      padding: EdgeInsets.zero,
      child: Semantics(
        button: onTap != null,
        label: semantics,
        excludeSemantics: semantics != null,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _saleRow(Map<String, dynamic> s) {
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final id = s['id']?.toString() ?? '';
    final voided = s['status'] == 'voided';
    return _rowCard(
      key: Key('customer-sale-$id'),
      onTap: salesIdPattern.hasMatch(id)
          ? () => context.push(customerSaleRoute(_id, id))
          : null,
      children: [
        MoneyRow(
          s['number']?.toString() ?? '',
          formatCurrency(intOf(s['totalTzs'])),
          strike: voided,
        ),
        Wrap(
          spacing: FFTokens.spacingXs,
          runSpacing: FFTokens.spacingXs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              eatDateTime(s['soldAt']?.toString(), locale: lang),
              style: theme.textTheme.bodySmall,
            ),
            ...saleKindBadges(context, s),
            if (voided)
              FFBadge(
                label: context.tr('vendor.sales.voidedBadge'),
                tone: FFBadgeTone.gray,
              ),
          ],
        ),
      ],
    );
  }

  Widget _orderRow(Map<String, dynamic> o) {
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final id = o['id']?.toString() ?? '';
    final status = o['status']?.toString() ?? 'pending';
    // There is no order page in the app: the Orders tab, for those who may
    // see orders. No phone or address here, ever (A-02).
    return _rowCard(
      key: Key('customer-order-$id'),
      onTap: canVendor(context, 'orders')
          ? () => context.go('/vendor/home?open=orders')
          : null,
      children: [
        MoneyRow(
          context
              .tr('vendor.orders.ref')
              .replaceAll('{ref}', vendorShortRef(o)),
          formatCurrency(intOf(o['totalTzs'])),
        ),
        Wrap(
          spacing: FFTokens.spacingXs,
          runSpacing: FFTokens.spacingXs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              formatDate(o['createdAt'], locale: lang),
              style: theme.textTheme.bodySmall,
            ),
            FFBadge(
              label: shopOrderStatusLabel(context, status),
              tone: FFBadgeTone.defaultTone,
              wrap: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _paymentRow(Map<String, dynamic> p) {
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final id = p['id']?.toString() ?? '';
    final voided = p['status'] == 'voided';
    final sales = (p['allocations'] as List? ?? [])
        .whereType<Map>()
        .map((a) => a['saleNumber']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');
    return _rowCard(
      key: Key('customer-payment-$id'),
      onTap: () => _openPayment(p),
      children: [
        MoneyRow(
          p['number']?.toString() ?? '',
          formatCurrency(intOf(p['amountTzs'])),
          strike: voided,
        ),
        Wrap(
          spacing: FFTokens.spacingXs,
          runSpacing: FFTokens.spacingXs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              [
                formatDay(p['receivedOn']?.toString(), locale: lang),
                methodLabel(context.tr, p['method']?.toString()),
                if (sales.isNotEmpty)
                  fillIn(context.tr('vendor.pay.paidSales'), {
                    'numbers': sales,
                  }),
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            if (voided)
              FFBadge(
                label: context.tr('vendor.sales.voidedBadge'),
                tone: FFBadgeTone.gray,
              ),
          ],
        ),
      ],
    );
  }
}

/// The order number for a customer's app order row.
String vendorShortRef(Map<String, dynamic> o) => shopOrderRef(o);

/// One status badge of a sale row: its i18n key, tone and `{amount}`.
typedef SaleBadge = ({String key, FFBadgeTone tone, int? amount});

/// The status badges of a sale row, the ONE rule the sales list and the
/// customer profile share (S7 retest; same as the portal and the document
/// status):
/// - pay later: "Pay later";
/// - fully refunded (refundState full): "Refunded" (document `refunded`);
/// - else, pay later with something owed: "Owes {amount}";
/// - else, pay later with nothing owed: "Settled by credit note" when a
///   refund took the balance off (`balanceReducedTzs` > 0, document
///   `settled_by_credit_note`), otherwise "Paid off" (`paid_in_full`);
/// - plus "Part refunded" when partly refunded.
/// A voided sale keeps only "Pay later" (its Voided badge says the rest).
List<SaleBadge> saleStatusBadges(Map s) {
  final credit = s['kind'] == 'credit';
  final voided = s['status'] == 'voided';
  final state = s['refundState']?.toString();
  final balance = intOf(s['balanceTzs']);
  return [
    if (credit)
      (
        key: 'vendor.sales.payLaterBadge',
        tone: FFBadgeTone.brand,
        amount: null,
      ),
    if (!voided) ...[
      if (state == 'full')
        (key: 'vendor.refunds.badgeFull', tone: FFBadgeTone.gray, amount: null)
      else if (credit)
        if (balance > 0)
          (
            key: 'vendor.sales.owesBadge',
            tone: FFBadgeTone.warning,
            amount: balance,
          )
        else if (intOf(s['balanceReducedTzs']) > 0)
          (
            key: 'vendor.doc.statusSettledByCreditNote',
            tone: FFBadgeTone.success,
            amount: null,
          )
        else
          (
            key: 'vendor.sales.paidOffBadge',
            tone: FFBadgeTone.success,
            amount: null,
          ),
      if (state == 'partial')
        (
          key: 'vendor.refunds.badgePartial',
          tone: FFBadgeTone.info,
          amount: null,
        ),
    ],
  ];
}

/// The words of one [SaleBadge] ("Owes TSh 5,000").
String saleBadgeText(BuildContext context, SaleBadge b) => b.amount == null
    ? context.tr(b.key)
    : fillIn(context.tr(b.key), {'amount': formatCurrency(b.amount!)});

/// The status badges of a sale row as widgets ([saleStatusBadges]).
List<Widget> saleKindBadges(BuildContext context, Map s) => [
  for (final b in saleStatusBadges(s))
    FFBadge(
      key: b.key.startsWith('vendor.refunds.')
          ? Key('sales-row-refund-${s['id']}')
          : null,
      label: saleBadgeText(context, b),
      tone: b.tone,
      wrap: true,
    ),
];
