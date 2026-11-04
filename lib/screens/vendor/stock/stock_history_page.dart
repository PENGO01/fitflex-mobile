// Vendor tools · S1: one product's stock history — every change, why, by
// whom, and the stock before and after (GET
// /vendor/products/:id/stock-movements). Route: /vendor/products/:id/stock.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/tone_theme.dart';
import '../orders/vendor_order_card.dart';
import 'adjust_stock_sheet.dart';
import 'stock_options.dart';

/// Where "back" goes when there is nothing to go back to (opened from a
/// notification): the products, showing the low ones.
const vendorLowProductsRoute = '/vendor/home?open=products&filter=low';

enum _Problem { none, failed, network, notFound, notAllowed }

class StockHistoryPage extends StatefulWidget {
  const StockHistoryPage({
    super.key,
    required this.productId,
    this.variant,
    this.fromPush = false,
  });

  final String productId;

  /// The variant a notification was about; "Adjust stock" starts on it.
  final String? variant;
  final bool fromPush;

  @override
  State<StockHistoryPage> createState() => _StockHistoryPageState();
}

class _StockHistoryPageState extends State<StockHistoryPage> {
  Map<String, dynamic>? _product;
  LowStockIndex _low = LowStockIndex.empty();
  final List<Map<String, dynamic>> _rows = [];
  num? _opening;
  num? _closing;
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _moreFailed = false;
  _Problem _problem = _Problem.none;
  String _range = '30d';
  DateTimeRange? _custom;
  final Set<String> _expanded = {};
  // Opened from a variant's low-stock notice: that variant's history. A
  // variant that no longer exists falls back to the whole product.
  late String? _variantFilter = widget.variant;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  /// The route moved to another product or variant while this page was
  /// open (a notification, go()): start over for it.
  @override
  void didUpdateWidget(StockHistoryPage old) {
    super.didUpdateWidget(old);
    if (old.productId == widget.productId && old.variant == widget.variant) {
      return;
    }
    setState(() {
      _product = null;
      _rows.clear();
      _cursor = null;
      _opening = null;
      _closing = null;
      _expanded.clear();
      _variantFilter = widget.variant;
      _loading = true;
      _problem = _Problem.none;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    if (!canManageProducts(context)) {
      FFSnack.error(context, context.tr('vendor.stock.noProductsAccess'));
      context.go('/vendor/home');
      return;
    }
    final tools = await VendorToolsOptions.of(context);
    if (!mounted) return;
    _walkInSales = tools.walkInSales;
    _purchases = tools.purchases;
    if (!tools.stockLedger) {
      context.go('/vendor/home?open=products');
      return;
    }
    await _load();
  }

  (String, String) get _period {
    final today = eatToday();
    if (_range == 'custom' && _custom != null) {
      return (eatDay(_custom!.start), eatDay(_custom!.end));
    }
    final days = _range == '7d' ? 6 : 29;
    return (eatDay(today.subtract(Duration(days: days))), eatDay(today));
  }

  _Problem _problemOf(Object e) {
    if (e is ApiException) {
      if (e.status == 404 && e.code != 'feature_disabled') {
        return _Problem.notFound;
      }
      if (e.status == 403) return _Problem.notAllowed;
      return _Problem.failed;
    }
    return _Problem.network;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _problem = _Problem.none;
      _moreFailed = false;
    });
    final api = AppScope.of(context).api;
    final (from, to) = _period;
    try {
      final results = await Future.wait<Object?>([
        api.vendorProducts(),
        api
            .vendorLowStock()
            .then<Object?>((v) => v)
            .catchError((Object _) => <dynamic>[]),
        api.vendorStockMovements(
          widget.productId,
          from: from,
          to: to,
          variant: _variantFilter,
        ),
      ]);
      if (!mounted) return;
      final product = (results[0] as List).whereType<Map>().firstWhere(
        (p) => p['id']?.toString() == widget.productId,
        orElse: () => const {},
      );
      final page = results[2] as Map<String, dynamic>;
      setState(() {
        _loading = false;
        if (product.isEmpty) {
          _problem = _Problem.notFound;
          return;
        }
        _product = Map<String, dynamic>.from(product);
        _low = LowStockIndex(results[1] as List? ?? const []);
        _rows
          ..clear()
          ..addAll(_rowsOf(page));
        _opening = page['openingStock'] as num?;
        _closing = page['closingStock'] as num?;
        _cursor = page['nextCursor']?.toString();
      });
    } catch (e) {
      if (!mounted) return;
      if (_variantFilter != null &&
          e is ApiException &&
          e.code == 'variant_not_found') {
        _variantFilter = null;
        return _load();
      }
      setState(() {
        _loading = false;
        _problem = _problemOf(e);
      });
    }
  }

  List<Map<String, dynamic>> _rowsOf(Map<String, dynamic> page) =>
      (page['rows'] as List? ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (cursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    final (from, to) = _period;
    try {
      final page = await AppScope.of(context).api.vendorStockMovements(
        widget.productId,
        from: from,
        to: to,
        variant: _variantFilter,
        cursor: cursor,
      );
      if (!mounted) return;
      setState(() {
        _rows.addAll(_rowsOf(page));
        _cursor = page['nextCursor']?.toString();
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
    await _load();
  }

  /// The orders this person can see (null until known or when it failed).
  Set<String>? _visibleOrders;

  Future<void> _loadVisibleOrders() async {
    if (!canVendor(context, 'orders')) return;
    try {
      final rows = await AppScope.of(context).api.vendorOrders();
      if (!mounted) return;
      _visibleOrders = {
        for (final o in rows.whereType<Map>()) o['id']?.toString() ?? '',
      };
    } catch (_) {
      _visibleOrders = null;
    }
  }

  /// Opens Orders, unless this order is not in the vendor's list yet (an
  /// unpaid order): then say so rather than show an Orders tab without it.
  /// S3: rows of walk-in sales link to the sale (feature on + `sales`).
  bool _walkInSales = false;

  /// S9: GRN numbers link to the purchase (else plain text).
  bool _purchases = false;

  Future<void> _openOrder(String orderId) async {
    if (_visibleOrders == null) await _loadVisibleOrders();
    if (!mounted) return;
    final visible = _visibleOrders;
    if (visible != null && !visible.contains(orderId)) {
      FFSnack.info(context, context.tr('vendor.stock.orderNotVisible'));
      return;
    }
    context.go('/vendor/home?open=orders');
  }

  Future<void> _adjust() async {
    final product = _product;
    if (product == null) return;
    final result = await openAdjustStock(
      context,
      product: product,
      variant: _variantFilter,
    );
    if (result == null || !mounted) return;
    setState(() => _product = withAdjustedStock(product, result.product));
    await _load();
  }

  void _back() {
    if (!widget.fromPush && context.canPop()) {
      context.pop();
    } else {
      context.go(vendorLowProductsRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = _product?['name']?.toString() ?? '';
    final name = _variantFilter == null || product.isEmpty
        ? product
        : fillIn(context.tr('vendor.stock.variantHistory'), {
            'product': product,
            'variant': _variantFilter,
          });
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('vendor.stock.history')),
            if (name.isNotEmpty)
              Semantics(
                label: name,
                excludeSemantics: true,
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          const FFSkeletonCard(),
          const SizedBox(height: FFTokens.spacingMd),
          FFSkeletonList(
            count: 5,
            semanticLabel: context.tr('vendor.stock.loading'),
          ),
        ],
      );
    }
    if (_problem != _Problem.none) {
      final gone =
          _problem == _Problem.notFound || _problem == _Problem.notAllowed;
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          FFErrorState(
            key: const Key('stock-history-error'),
            message: context.tr(switch (_problem) {
              _Problem.notFound => 'vendor.stock.notFound',
              _Problem.notAllowed => 'vendor.stock.notAllowed',
              _Problem.network => 'error.network',
              _ => 'vendor.stock.historyFailed',
            }),
            onRetry: gone
                ? () => context.go('/vendor/home?open=products')
                : _load,
            retryLabel: context.tr(
              gone ? 'vendor.stock.backToProducts' : 'common.retry',
            ),
          ),
        ],
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final header = _header(context, wide);
    final range = _rangePicker(context);
    return ListView(
      key: const Key('stock-history-list'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: header),
              const SizedBox(width: FFTokens.spacingMd),
              Expanded(child: range),
            ],
          )
        else ...[
          header,
          const SizedBox(height: FFTokens.spacingMd),
          range,
        ],
        const SizedBox(height: FFTokens.spacingMd),
        Row(
          children: [
            Expanded(
              child: FFStatTile(
                key: const Key('stock-opening'),
                icon: Icons.first_page,
                value: formatStock(_opening ?? 0),
                label: context.tr('vendor.stock.opening'),
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: FFStatTile(
                key: const Key('stock-closing'),
                icon: Icons.last_page,
                value: formatStock(_closing ?? 0),
                label: context.tr('vendor.stock.closing'),
              ),
            ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingMd),
        if (_rows.isEmpty)
          FFEmptyState(
            key: const Key('stock-history-empty'),
            icon: Icons.history,
            title: context.tr('vendor.stock.historyEmpty'),
            action: FFButton(
              label: context.tr('vendor.stock.adjust'),
              visualDensity: VisualDensity.standard,
              onPressed: _adjust,
            ),
          ),
        for (final row in _rows) _rowTile(context, row),
        if (_moreFailed) ...[
          FFAlert(
            key: const Key('stock-more-failed'),
            message: context.tr('vendor.stock.historyFailed'),
            tone: FFAlertTone.error,
          ),
          const SizedBox(height: FFTokens.spacingSm),
        ],
        if (_cursor != null)
          FFButton(
            key: const Key('stock-load-more'),
            visualDensity: VisualDensity.standard,
            label: context.tr(
              _moreFailed ? 'common.retry' : 'vendor.stock.loadMore',
            ),
            variant: FFButtonVariant.ghost,
            loading: _loadingMore,
            fullWidth: true,
            onPressed: _loadMore,
          ),
      ],
    );
  }

  Widget _header(BuildContext context, bool wide) {
    final theme = Theme.of(context);
    final product = _product!;
    final id = widget.productId;
    final reorder = product['reorderLevel'];
    final variants = trackedVariants(product);
    final lowVariants = _low.lowVariants(id).toSet();
    return FFCard(
      key: const Key('stock-header'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('vendor.stock.current'),
            style: theme.textTheme.labelMedium,
          ),
          Wrap(
            spacing: FFTokens.spacingSm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                formatStock(product['stock'] as num? ?? 0),
                key: const Key('stock-current'),
                style: theme.textTheme.titleLarge,
              ),
              if (_low.productLow(id) || (variants.isEmpty && _low.isLow(id)))
                FFBadge(
                  key: const Key('stock-low-badge'),
                  label: context.tr('vendor.stock.lowBadge'),
                  tone: FFBadgeTone.warning,
                ),
            ],
          ),
          Text(
            '${context.tr('vendor.stock.reorderLevel')}: '
            '${reorder is num ? formatStock(reorder) : '—'}',
            style: theme.textTheme.bodySmall,
          ),
          if (variants.isNotEmpty) ...[
            const SizedBox(height: FFTokens.spacingSm),
            for (final v in variants)
              Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
                child: Wrap(
                  spacing: FFTokens.spacingSm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${v.name} · ${formatStock(v.stock)}'),
                    if (lowVariants.contains(v.name))
                      FFBadge(
                        label: context.tr('vendor.stock.lowBadge'),
                        tone: FFBadgeTone.warning,
                      ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: FFTokens.spacingSm),
          Align(
            alignment: wide
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: FFButton(
              key: const Key('stock-adjust'),
              visualDensity: VisualDensity.standard,
              label: context.tr('vendor.stock.adjust'),
              icon: Icons.tune,
              fullWidth: !wide,
              onPressed: _adjust,
            ),
          ),
        ],
      ),
    );
  }

  /// 7 days / 30 days / Choose dates; the short labels when the full ones
  /// would not fit a third of the width each (Swahili at 375, large text).
  Widget _rangePicker(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      List<(String, String)> labels(String suffix) => [
        ('7d', context.tr('vendor.stock.range.7d$suffix')),
        ('30d', context.tr('vendor.stock.range.30d$suffix')),
        ('custom', context.tr('vendor.stock.range.custom$suffix')),
      ];
      final full = labels('');
      // Measured the way FFSegmented draws a regular option (bold
      // labelLarge, 8px each side, inside its 4px track padding), but for
      // the whole label on ONE line: otherwise "Choose dates" fits word by
      // word and wraps to two lines.
      final style = Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700);
      final scaler = MediaQuery.textScalerOf(context);
      final share =
          (box.maxWidth - 2 * FFTokens.spacingXs) / full.length -
          2 * FFTokens.spacingSm;
      final fits = full.every((option) {
        final painter = TextPainter(
          text: TextSpan(text: option.$2, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width <= share;
      });
      final custom = _custom;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FFSegmented(
            key: const Key('stock-range'),
            value: _range,
            options: fits ? full : labels('Short'),
            onChanged: _pickRange,
          ),
          // The dates chosen, so "Choose dates" says which ones.
          if (_range == 'custom' && custom != null)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                fillIn(context.tr('vendor.stock.customRange'), {
                  'from': _day(custom.start),
                  'to': _day(custom.end),
                }),
                key: const Key('stock-custom-range'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      );
    },
  );

  String _day(DateTime day) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    try {
      return DateFormat('d MMM yyyy', lang).format(day);
    } catch (_) {
      return DateFormat('d MMM yyyy').format(day);
    }
  }

  String _when(String? createdAt) {
    final at = DateTime.tryParse(createdAt ?? '');
    if (at == null) return '';
    final eat = at.toUtc().add(const Duration(hours: 3));
    final lang = FFLocaleScope.of(context).locale.languageCode;
    try {
      return DateFormat('d MMM, HH:mm', lang).format(eat);
    } catch (_) {
      return DateFormat('d MMM, HH:mm').format(eat);
    }
  }

  Widget _rowTile(BuildContext context, Map<String, dynamic> row) {
    final theme = Theme.of(context);
    final tones = FFToneTheme.of(context);
    final id = row['id']?.toString() ?? '';
    final delta = (row['delta'] as num?) ?? 0;
    final reason = stockReasonLabel(context, row['reason']?.toString());
    final variant = row['variant']?.toString() ?? '';
    final before = row['stockBefore'] as num?;
    final after = row['stockAfter'] as num?;
    final actor = row['actor'] is Map
        ? (row['actor'] as Map)['name']?.toString()
        : null;
    final who = row['actor'] is Map
        ? fillIn(context.tr('vendor.stock.by'), {'name': actor ?? '—'})
        : context.tr('vendor.stock.bySystem');
    final when = _when(row['createdAt']?.toString());
    final doc = row['document'] is Map ? row['document'] as Map : null;
    final rawNote = stockNoteLabel(context, row['note']?.toString());
    // S9: a stock-in row's note is its GRN number, already shown as a link.
    final note =
        doc != null &&
            doc['type'] == 'purchase' &&
            rawNote == doc['number']?.toString()
        ? null
        : rawNote;
    final title = variant.isEmpty ? reason : '$reason · $variant';
    // before → after, with an arrow icon (not a "→" glyph: on web it shows
    // as a box until a fallback font loads).
    final small = theme.textTheme.bodySmall;
    final beforeAfter = before == null || after == null
        ? null
        : <InlineSpan>[
            TextSpan(text: formatStock(before)),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.arrow_forward,
                  size: (small?.fontSize ?? 12) + 1,
                  color: small?.color,
                ),
              ),
            ),
            TextSpan(text: formatStock(after)),
          ];
    final deltaWords = delta == 0
        ? context.tr('vendor.stock.deltaNone')
        : fillIn(
            context.tr(
              delta > 0 ? 'vendor.stock.deltaIn' : 'vendor.stock.deltaOut',
            ),
            {'n': formatStock(delta.abs())},
          );
    final label = fillIn(context.tr('vendor.stock.rowLabel'), {
      'reason': title,
      'delta': deltaWords,
      'before': before == null ? '—' : formatStock(before),
      'after': after == null ? '—' : formatStock(after),
      'time': when,
      'actor': who,
    });
    Widget? orderLink;
    if (doc != null && doc['type'] == 'order') {
      final docId = doc['id']?.toString() ?? '';
      // The same order number as Orders and the portal: the document's
      // shortRef (or number) if sent, else the last 6 characters in capitals.
      final ref = vendorOrderRef({
        'id': docId,
        'shortRef': doc['shortRef'] ?? doc['number'],
      });
      final text = fillIn(context.tr('vendor.stock.order'), {'ref': ref});
      orderLink = canVendor(context, 'orders')
          ? FFButton(
              key: Key('stock-order-$id'),
              label: text,
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              onPressed: () => _openOrder(docId),
            )
          : Text(text, style: theme.textTheme.bodySmall);
    }
    if (doc != null && doc['type'] == 'sale') {
      final saleId = doc['id']?.toString() ?? '';
      final text = fillIn(context.tr('vendor.stock.sale'), {
        'number': doc['number'] ?? '',
      });
      orderLink =
          _walkInSales &&
              canVendor(context, 'sales') &&
              RegExp(r'^[A-Za-z0-9._:-]{1,100}$').hasMatch(saleId)
          ? FFButton(
              key: Key('stock-sale-$id'),
              label: text,
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              onPressed: () => context.push('/vendor/sales/$saleId'),
            )
          : Text(text, style: theme.textTheme.bodySmall);
    }
    // S7: a refund's restock (or its undo) names its credit note.
    if (doc != null && doc['type'] == 'refund') {
      final refundId = doc['id']?.toString() ?? '';
      final text = fillIn(context.tr('vendor.stock.creditNote'), {
        'number': doc['number'] ?? '',
      });
      orderLink =
          _walkInSales &&
              canVendor(context, 'sales') &&
              RegExp(r'^[A-Za-z0-9._:-]{1,100}$').hasMatch(refundId)
          ? FFButton(
              key: Key('stock-refund-$id'),
              label: text,
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              onPressed: () => context.push(
                '/vendor/refunds/${Uri.encodeComponent(refundId)}',
              ),
            )
          : Text(text, style: theme.textTheme.bodySmall);
    }
    // S9: stock received from a supplier (or its void) names its GRN; a
    // link only with the tool on and `purchases` (spec §0.2, §0.3).
    if (doc != null && doc['type'] == 'purchase') {
      final purchaseId = doc['id']?.toString() ?? '';
      final text = fillIn(context.tr('vendor.stock.grn'), {
        'number': doc['number'] ?? '',
      });
      orderLink =
          _purchases &&
              canVendor(context, 'purchases') &&
              RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(purchaseId)
          ? FFButton(
              key: Key('stock-purchase-$id'),
              label: text,
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              onPressed: () => context.push(
                '/vendor/purchases/${Uri.encodeComponent(purchaseId)}',
              ),
            )
          : Text(
              text,
              key: Key('stock-purchase-text-$id'),
              style: theme.textTheme.bodySmall,
            );
    }
    final expanded = _expanded.contains(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: FFCard(
        key: Key('stock-row-$id'),
        // Sized by its content: no blank band when a row has no note.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: label,
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(title, style: theme.textTheme.titleSmall),
                      ),
                      Text(
                        formatDelta(delta),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: delta > 0
                              ? tones.success.fg
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  Text.rich(
                    TextSpan(
                      style: small,
                      children: [
                        ...?beforeAfter,
                        TextSpan(
                          text:
                              (beforeAfter == null ? '' : ' · ') +
                              [
                                when,
                                who,
                              ].where((p) => p.isNotEmpty).join(' · '),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (note != null)
              InkWell(
                onTap: () => setState(
                  () => expanded ? _expanded.remove(id) : _expanded.add(id),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                  child: Text(
                    note,
                    maxLines: expanded ? null : 3,
                    overflow: expanded ? null : TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            if (orderLink != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: orderLink,
              ),
          ],
        ),
      ),
    );
  }
}

/// Stored variants with the counts from an adjustment's answer.
List<Map<String, dynamic>> _mergeVariants(List stored, List fresh) {
  final counts = {
    for (final v in fresh.whereType<Map>()) v['name']?.toString(): v['stock'],
  };
  return [
    for (final v in stored.whereType<Map>())
      {
        ...Map<String, dynamic>.from(v),
        if (counts.containsKey(v['name']?.toString()))
          'stock': counts[v['name']?.toString()],
      },
  ];
}

/// [product] with the counts from an adjustment's answer.
Map<String, dynamic> withAdjustedStock(
  Map<String, dynamic> product,
  Map<String, dynamic> fresh,
) => {
  ...product,
  if (fresh['stock'] != null) 'stock': fresh['stock'],
  if (fresh['variants'] is List)
    'variants': _mergeVariants(
      product['variants'] as List? ?? const [],
      fresh['variants'] as List,
    ),
};

/// The date range picker in the app's colours, with readable days inside
/// the chosen range: a light tint of the primary behind normal text (the
/// default M3 fill put white text on Volt in dark, slate on green in light).
/// The first and last day keep the solid primary with its on-colour.
ThemeData stockRangePickerTheme(ThemeData base) {
  final scheme = base.colorScheme;
  final dark = base.brightness == Brightness.dark;
  return base.copyWith(
    datePickerTheme: base.datePickerTheme.copyWith(
      backgroundColor: scheme.surface,
      rangePickerBackgroundColor: scheme.surface,
      rangePickerHeaderBackgroundColor: scheme.surface,
      rangePickerHeaderForegroundColor: scheme.onSurface,
      headerBackgroundColor: scheme.surface,
      headerForegroundColor: scheme.onSurface,
      rangeSelectionBackgroundColor: scheme.primary.withValues(
        alpha: dark ? 0.22 : 0.14,
      ),
      dayForegroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : states.contains(WidgetState.disabled)
            ? scheme.onSurface.withValues(alpha: 0.38)
            : scheme.onSurface,
      ),
      dayBackgroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? scheme.primary : null,
      ),
    ),
  );
}
