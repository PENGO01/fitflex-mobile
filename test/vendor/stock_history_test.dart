// Vendor tools · S1: stock history — range, rows, paging with "Load more",
// empty / error / not-found states, order links; and where a low-stock
// notification leads.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/stock/stock_history_page.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_options.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';

const _path = '/vendor/products/p1/stock-movements';

Map<String, dynamic> _row(
  String id, {
  String reason = 'count',
  int delta = -2,
  int after = 8,
  String? note,
  Map<String, dynamic>? actor = const {'id': 'v1', 'name': 'Asha'},
  String? orderId,
}) => {
  'id': id,
  'productId': 'p1',
  'variant': null,
  'reason': reason,
  'kind': orderId == null ? 'adjustment' : 'order',
  'delta': delta,
  'stockBefore': after - delta,
  'stockAfter': after,
  'note': note,
  'actor': actor,
  'orderId': orderId,
  'document': orderId == null
      ? null
      : {'type': 'order', 'id': orderId, 'number': null},
  'createdAt': '2026-10-19T11:05:00Z',
};

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic>? tools = ledgerOn,
  Map<String, dynamic> user = vendorUser,
  String lang = 'en',
  String? variant,
  double textScale = 1,
  Size size = const Size(400, 900),
}) {
  api.on('GET /vendor/products', [
    stockProduct('p1', 'Whey', stock: 8, reorderLevel: 5),
  ]);
  api.on('GET /vendor/stock/low', []);
  if (tools != null) api.on('GET /vendor/tools/options', tools);
  return pumpPage(
    tester,
    api,
    StockHistoryPage(productId: 'p1', variant: variant),
    user: user,
    lang: lang,
    keepRequests: true,
    textScale: textScale,
    size: size,
  );
}

void main() {
  setUpAll(loadAppFonts);

  apiTest('first page: last 30 days, opening/closing, row details', (
    tester,
    api,
  ) async {
    api.on('GET $_path', {
      'productId': 'p1',
      'variant': null,
      'openingStock': 12,
      'closingStock': 8,
      'rows': [
        _row('m2', note: 'product_form'),
        _row(
          'm1',
          reason: 'reserve',
          delta: -2,
          after: 10,
          actor: null,
          orderId: 'ord_abcdef123456',
        ),
      ],
      'nextCursor': null,
    });
    final host = await _pump(tester, api);

    final req = api.only('GET', _path);
    final q = Uri.splitQueryString(req.query);
    final from = DateTime.parse(q['from']!), to = DateTime.parse(q['to']!);
    expect(to.difference(from).inDays, 29);
    expect(q['to'], eatDay(eatToday()));

    expect(find.text('12'), findsWidgets);
    expect(find.text(host.tr('vendor.stock.opening')), findsOneWidget);
    expect(find.text('Counted'), findsOneWidget);
    expect(find.text('−2'), findsNWidgets(2));
    // 11:05Z is 14:05 in Dar es Salaam.
    expect(find.textContaining('8 · 19 Oct, 14:05 · By Asha'), findsOneWidget);
    // before → after uses an icon, not a "→" glyph (tofu on web).
    expect(find.byIcon(Icons.arrow_forward), findsWidgets);
    expect(find.textContaining('→'), findsNothing);
    expect(find.text(host.tr('vendor.stock.fromProductForm')), findsOneWidget);
    expect(find.text('Order placed'), findsOneWidget);
    expect(
      find.textContaining(host.tr('vendor.stock.bySystem')),
      findsOneWidget,
    );
    // No order number yet: a short id; the vendor may open orders.
    expect(find.byKey(const Key('stock-order-m1')), findsOneWidget);
    // Same order number as Orders and the portal: last 6, in capitals.
    expect(find.text('Order 123456'), findsOneWidget);
    expect(find.byKey(const Key('stock-load-more')), findsNothing);
  });

  apiTest('Load more appends the next page and disappears at the end', (
    tester,
    api,
  ) async {
    api.onCall('GET $_path', (r) {
      final cursor = Uri.splitQueryString(r.query)['cursor'];
      return cursor == null
          ? {
              'openingStock': 0,
              'closingStock': 8,
              'rows': [for (var i = 0; i < 3; i++) _row('a$i')],
              'nextCursor': 'c1',
            }
          : {
              'openingStock': 0,
              'closingStock': 8,
              'rows': [_row('b0'), _row('b1')],
              'nextCursor': null,
            };
    });
    await _pump(tester, api);
    expect(find.byKey(const Key('stock-row-a2')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('stock-load-more')));
    final calls = api.where('GET', _path);
    expect(calls, hasLength(2));
    expect(Uri.splitQueryString(calls.last.query)['cursor'], 'c1');
    // Same period on the next page.
    expect(
      Uri.splitQueryString(calls.last.query)['from'],
      Uri.splitQueryString(calls.first.query)['from'],
    );
    expect(find.byKey(const Key('stock-row-a0')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('stock-row-b1')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('stock-row-b1')), findsOneWidget);
    expect(find.byKey(const Key('stock-load-more')), findsNothing);
  });

  apiTest('a failed next page keeps the rows and offers a retry', (
    tester,
    api,
  ) async {
    var n = 0;
    api.onCall('GET $_path', (_) {
      if (++n == 2) throw StateError('boom');
      return {
        'openingStock': 0,
        'closingStock': 8,
        'rows': [_row('a0')],
        'nextCursor': n == 1 ? 'c1' : null,
      };
    });
    final host = await _pump(tester, api);
    await tapVisible(tester, find.byKey(const Key('stock-load-more')));
    expect(find.byKey(const Key('stock-more-failed')), findsOneWidget);
    expect(find.byKey(const Key('stock-row-a0')), findsOneWidget);
    expect(find.text(host.tr('common.retry')), findsOneWidget);
  });

  apiTest('switching to 7 days reloads with a 7-day period', (
    tester,
    api,
  ) async {
    api.on('GET $_path', {
      'openingStock': 8,
      'closingStock': 8,
      'rows': [],
      'nextCursor': null,
    });
    final host = await _pump(tester, api);
    expect(find.byKey(const Key('stock-history-empty')), findsOneWidget);
    await tester.tap(find.text(host.tr('vendor.stock.range.7d')));
    await tester.pumpAndSettle();
    final q = Uri.splitQueryString(api.where('GET', _path).last.query);
    expect(
      DateTime.parse(q['to']!).difference(DateTime.parse(q['from']!)).inDays,
      6,
    );
  });

  apiTest('failed first load: error state with Try again', (tester, api) async {
    api.fail('GET $_path', 500);
    final host = await _pump(tester, api);
    expect(find.text(host.tr('vendor.stock.historyFailed')), findsOneWidget);
    api.heal('GET $_path');
    api.on('GET $_path', {
      'openingStock': 8,
      'closingStock': 8,
      'rows': [_row('a0')],
      'nextCursor': null,
    });
    await tapVisible(tester, find.text(host.tr('common.retry')));
    expect(find.byKey(const Key('stock-row-a0')), findsOneWidget);
  });

  apiTest('deleted product: not-found state', (tester, api) async {
    api.fail('GET $_path', 404, {'error': 'product_not_found'});
    final host = await _pump(tester, api);
    expect(find.text(host.tr('vendor.stock.notFound')), findsOneWidget);
    expect(find.text(host.tr('vendor.stock.backToProducts')), findsOneWidget);
  });

  apiTest('ledger off: the history is never asked for', (tester, api) async {
    await _pump(tester, api, tools: {'stockLedger': false});
    expect(api.sent('GET', _path), isFalse);
  });

  apiTest('staff without orders see the order as plain text', (
    tester,
    api,
  ) async {
    api.on('GET $_path', {
      'openingStock': 10,
      'closingStock': 8,
      'rows': [_row('m1', reason: 'reserve', actor: null, orderId: 'ord_1')],
      'nextCursor': null,
    });
    await _pump(
      tester,
      api,
      user: const {
        'id': 's1',
        'userType': 'vendor_staff',
        'vendorPermissions': ['products'],
      },
    );
    expect(find.byKey(const Key('stock-order-m1')), findsNothing);
    expect(find.text('Order ORD_1'), findsOneWidget);
  });

  apiTest('unknown reasons are never shown raw (Swahili)', (tester, api) async {
    api.on('GET $_path', {
      'openingStock': 10,
      'closingStock': 8,
      // S9 labels stock_in, so a reason no screen knows yet stands in.
      'rows': [_row('m1', reason: 'transfer_in')],
      'nextCursor': null,
    });
    await _pump(tester, api, lang: 'sw');
    expect(find.text('Badiliko la Stock'), findsOneWidget);
    expect(find.textContaining('transfer_in'), findsNothing);
  });

  apiTest('a variant notice shows that variant\'s history', (
    tester,
    api,
  ) async {
    api.on('GET $_path', {
      'openingStock': 3,
      'closingStock': 1,
      'rows': [_row('m1')],
      'nextCursor': null,
    });
    await _pump(tester, api, variant: 'Large');
    expect(
      Uri.splitQueryString(api.only('GET', _path).query)['variant'],
      'Large',
    );
    expect(find.text('Whey · Large'), findsOneWidget);
  });

  apiTest('no variant: the whole product, no variant filter', (
    tester,
    api,
  ) async {
    api.on('GET $_path', {
      'openingStock': 3,
      'closingStock': 1,
      'rows': [],
      'nextCursor': null,
    });
    await _pump(tester, api);
    expect(
      Uri.splitQueryString(api.only('GET', _path).query).containsKey('variant'),
      isFalse,
    );
  });

  apiTest('a variant that is gone falls back to the whole product', (
    tester,
    api,
  ) async {
    api.onCall('GET $_path', (r) {
      if (Uri.splitQueryString(r.query).containsKey('variant')) {
        return RawResponse(404, jsonEncode({'error': 'variant_not_found'}));
      }
      return {
        'openingStock': 3,
        'closingStock': 1,
        'rows': [_row('m1')],
        'nextCursor': null,
      };
    });
    await _pump(tester, api, variant: 'Gone');
    final calls = api.where('GET', _path);
    expect(calls, hasLength(2));
    expect(Uri.splitQueryString(calls.first.query)['variant'], 'Gone');
    expect(
      Uri.splitQueryString(calls.last.query).containsKey('variant'),
      isFalse,
    );
    expect(find.byKey(const Key('stock-row-m1')), findsOneWidget);
    expect(find.text('Whey'), findsOneWidget);
  });

  apiTest('a zero change is read as "no change", not "0 added"', (
    tester,
    api,
  ) async {
    api.on('GET $_path', {
      'openingStock': 8,
      'closingStock': 8,
      'rows': [_row('m1', delta: 0, after: 8)],
      'nextCursor': null,
    });
    final host = await _pump(tester, api);
    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(RegExp(host.tr('vendor.stock.deltaNone'))),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('0 added')), findsNothing);
    handle.dispose();
  });

  apiTest('Swahili at 375 and 2x text: short range labels, no overflow', (
    tester,
    api,
  ) async {
    api.on('GET $_path', {
      'openingStock': 8,
      'closingStock': 8,
      'rows': [_row('m1')],
      'nextCursor': null,
    });
    late PageHost host;
    final errors = await captureFlutterErrors(() async {
      host = await _pump(
        tester,
        api,
        lang: 'sw',
        textScale: 2,
        size: const Size(375, 800),
      );
    });
    expect(errors.where((e) => e.contains('overflowed')), isEmpty);
    expect(find.text(host.tr('vendor.stock.range.7dShort')), findsOneWidget);
    expect(find.text(host.tr('vendor.stock.range.7d')), findsNothing);
  });

  apiTest('English at 400: the full range labels', (tester, api) async {
    api.on('GET $_path', {
      'openingStock': 8,
      'closingStock': 8,
      'rows': [],
      'nextCursor': null,
    });
    final host = await _pump(tester, api);
    expect(find.text(host.tr('vendor.stock.range.30d')), findsOneWidget);
  });

  group('vendor_low_stock deep link', () {
    test('maps to the product stock history with its variant', () {
      expect(
        partnerLinkFor(side: 'vendor', type: 'vendor_low_stock'),
        'lowStock',
      );
      expect(
        partnerRouteFor(
          side: 'vendor',
          type: 'vendor_low_stock',
          productId: 'prd_1',
          variant: 'Large size',
        ),
        '/vendor/products/prd_1/stock?variant=Large+size&from=push',
      );
      expect(
        partnerRouteFor(
          side: 'vendor',
          type: 'vendor_low_stock',
          productId: 'prd_1',
          variant: '',
        ),
        '/vendor/products/prd_1/stock?from=push',
      );
    });

    test('a missing or unsafe id goes to the low products', () {
      for (final id in [null, '', '../x', 'a b']) {
        expect(
          partnerRouteFor(
            side: 'vendor',
            type: 'vendor_low_stock',
            productId: id,
          ),
          vendorLowProductsRoute,
          reason: '$id',
        );
      }
    });

    test('every stock string exists in English and Swahili', () {
      bool stockKey(String k) =>
          k.startsWith('vendor.stock.') ||
          k.startsWith('vendor.variant.') ||
          k == 'vendor.costPrice' ||
          k == 'vendor.costForbidden' ||
          k == 'inbox.open.lowStock';
      final en = FFLocale.keysOf('en').where(stockKey).toSet();
      final sw = FFLocale.keysOf('sw').where(stockKey).toSet();
      expect(en, isNotEmpty);
      expect(sw, en);
      // Swahili is a translation, not the English left in place (short
      // words that are the same in both, like "Stock", aside).
      final same = [
        for (final k in en)
          if (FFLocale.textOf('en', k) == FFLocale.textOf('sw', k)) k,
      ];
      expect(same, isEmpty);
    });
  });
}
