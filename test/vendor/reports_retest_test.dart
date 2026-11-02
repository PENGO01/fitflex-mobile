// Vendor reports · S6 UAT retest fixes: N2 seven- and eight-figure money at
// 375 px in both languages and at large text, N3 and N3b what a null profit
// means, D7 the no-cost products filter, D10/D11 negative counts.
//
// Every request goes to the in-process RecordingApi (http://fixtures.local);
// nothing here reaches a real server.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/reports/report_models.dart';
import 'package:fitflexmobile/screens/vendor/reports/report_section_page.dart';
import 'package:fitflexmobile/screens/vendor/reports/report_widgets.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/components/components.dart';

import '../support/recording_api.dart';
import 'customers_support.dart' show staffUser;
import 'reports_s6_test.dart'
    show head, owner, ownerSummary, ownerTools, pumpSection, reportRoutes;
import 'stock_support.dart' show seedVendorHome;
import 'walkin_support.dart' show textContaining;

const nb = ' ';
const big = 12345678;
const bigText = 'TSh${nb}12,345,678';

Map<String, dynamic> bigSales() => {
  ...head(),
  'totals': {
    'grossTzs': big,
    'discountTzs': big,
    'refundTzs': big,
    'netTzs': big,
    'vatIncludedTzs': big,
    'saleCount': 1234,
    'orderCount': 56,
    'itemsSold': 7890,
    'voided': {'count': 0, 'totalTzs': 0},
  },
  'byChannel': {},
  'buckets': [],
};

Map<String, dynamic> bigProfit() => {
  ...head(),
  'totals': {
    'netExVatTzs': big,
    'commissionTzs': big,
    'costTzs': big,
    'profitTzs': big,
    'marginPct': 27.5,
  },
  'uncosted': {'lineCount': 0, 'qty': 0, 'revenueTzs': 0},
  'hasVat': false,
  'buckets': [],
  'byChannel': {},
  'byProduct': [],
  'uncostedProducts': [],
};

/// No two figures touch, each value stays inside its grid, and it is still
/// large enough to read.
void expectFiguresClear(WidgetTester tester) {
  final grid = find.byType(ReportFigureGrid);
  expect(grid, findsWidgets);
  final bounds = tester.getRect(grid.first);
  final figures = find.descendant(
    of: grid.first,
    matching: find.byType(ReportFigure),
  );
  final rects = [
    for (final e in figures.evaluate()) tester.getRect(find.byWidget(e.widget)),
  ];
  expect(rects.length, greaterThan(1));
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      expect(
        rects[i].overlaps(rects[j]),
        isFalse,
        reason: 'figures $i and $j overlap: ${rects[i]} ${rects[j]}',
      );
    }
  }
  // The bug was paint overflow: the figure's box was fine and its value ran
  // out of it. So every value must sit inside its own figure.
  var values = 0;
  for (final e in figures.evaluate()) {
    final figure = find.byWidget(e.widget);
    final box = tester.getRect(figure);
    final widget = e.widget as ReportFigure;
    final text = find.descendant(of: figure, matching: find.text(widget.value));
    final rect = tester.getRect(text);
    values++;
    // A non-wrapping Text keeps a clamped box and paints past it, so the box
    // cannot show the bug: measure the width it really paints, at any scale
    // a FittedBox applied.
    final paragraph = tester.renderObject<RenderParagraph>(text);
    final applied = rect.width / paragraph.size.width;
    final painted = paragraph.getMaxIntrinsicWidth(double.infinity) * applied;
    final paintedRight = rect.left + painted;
    expect(
      paintedRight,
      lessThanOrEqualTo(box.right + 0.5),
      reason:
          '"${widget.value}" paints to $paintedRight, out of its figure $box',
    );
    expect(paintedRight, lessThanOrEqualTo(bounds.right + 0.5));
    expect(rect.left, greaterThanOrEqualTo(bounds.left - 0.5));
    expect(rect.height, greaterThanOrEqualTo(16), reason: 'too small to read');
  }
  expect(values, rects.length);
}

Map<String, dynamic> productRow(
  String id, {
  required bool hasProfitKey,
  num? profit,
  bool hasMarginKey = true,
  num? margin,
  bool noSales = false,
}) => {
  'productId': id,
  'variant': null,
  'name': 'Item $id',
  'removed': false,
  'unitsSold': noSales ? 0 : 2,
  'appUnits': 0,
  'walkInUnits': noSales ? 0 : 2,
  'netRevenueTzs': noSales ? 0 : 90000,
  'lastSoldAt': null,
  'stock': 4,
  'daysOfCover': 60,
  'coverState': 'ok',
  'noSalesInPeriod': noSales,
  if (hasProfitKey) 'profitTzs': profit,
  if (hasMarginKey) 'marginPct': margin,
};

Map<String, dynamic> productsAnswer(List<Map<String, dynamic>> rows) => {
  ...head(),
  'sort': 'slow',
  'rows': rows,
  'totals': {'unitsSold': 2, 'netRevenueTzs': 90000},
  'slowCount': 0,
  'nextCursor': null,
};

void main() {
  group('N2 large money does not overlap', () {
    for (final lang in const ['en', 'sw']) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        apiTest('Sales at 375 px, $lang, text ×$scale', (tester, api) async {
          await loadAppFonts();
          api.on('GET /vendor/tools/options', ownerTools);
          api.on('GET /vendor/reports/sales', bigSales());
          final errors = await captureFlutterErrors(() async {
            await pumpPage(
              tester,
              api,
              ReportSectionPage(
                section: ReportSection.sales,
                from: '2026-10-01',
                to: '2026-10-29',
                now: DateTime.utc(2026, 10, 29, 10),
              ),
              user: owner,
              lang: lang,
              textScale: scale,
              size: const Size(375, 4000),
              extraRoutes: reportRoutes,
            );
          });
          expect(
            errors.where((e) => e.contains('overflowed')),
            isEmpty,
            reason: errors.join('\n'),
          );
          expectFiguresClear(tester);
        });

        apiTest('Profit at 375 px, $lang, text ×$scale', (tester, api) async {
          await loadAppFonts();
          api.on('GET /vendor/tools/options', ownerTools);
          api.on('GET /vendor/reports/profit', bigProfit());
          final errors = await captureFlutterErrors(() async {
            await pumpPage(
              tester,
              api,
              ReportSectionPage(
                section: ReportSection.profit,
                from: '2026-10-01',
                to: '2026-10-29',
                now: DateTime.utc(2026, 10, 29, 10),
              ),
              user: owner,
              lang: lang,
              textScale: scale,
              size: const Size(375, 4000),
              extraRoutes: reportRoutes,
            );
          });
          expect(
            errors.where((e) => e.contains('overflowed')),
            isEmpty,
            reason: errors.join('\n'),
          );
          expectFiguresClear(tester);
          expect(find.text('27.5%'), findsOneWidget);
        });
      }
    }

    apiTest('overview cards at 375 px: the summary stays clear', (
      tester,
      api,
    ) async {
      await loadAppFonts();
      final s = ownerSummary();
      (s['sales'] as Map)['netTzs'] = big;
      (s['profit'] as Map)['profitTzs'] = big;
      seedVendorHome(api, products: [], tools: ownerTools);
      api.on('GET /vendor/sales', {'sales': [], 'nextCursor': null});
      api.on('GET /vendor/reports/summary', s);
      final errors = await captureFlutterErrors(() async {
        await pumpPage(
          tester,
          api,
          const VendorHomePage(open: 'reports'),
          user: owner,
          lang: 'sw',
          textScale: 2,
          size: const Size(375, 6000),
          extraRoutes: reportRoutes,
        );
      });
      expect(
        errors.where((e) => e.contains('overflowed')),
        isEmpty,
        reason: errors.join('\n'),
      );
      expect(find.text(bigText), findsNWidgets(2));
    });
  });

  group('N3 only a null profit means no cost price', () {
    apiTest('costed, nets to zero: TSh 0, margin —, no label', (
      tester,
      api,
    ) async {
      api.on(
        'GET /vendor/reports/products',
        productsAnswer([productRow('p1', hasProfitKey: true, profit: 0)]),
      );
      final host = await pumpSection(tester, api, ReportSection.products);
      final noCost = host.tr('vendor.reports.profit.noCostHeading');
      expect(textContaining(noCost), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('reports-product-profit')),
          matching: find.text('TSh${nb}0'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('reports-product-margin')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });

    apiTest('a missing marginPct does not bring the label', (
      tester,
      api,
    ) async {
      api.on(
        'GET /vendor/reports/products',
        productsAnswer([
          productRow(
            'p1',
            hasProfitKey: true,
            profit: 5000,
            hasMarginKey: false,
          ),
        ]),
      );
      final host = await pumpSection(tester, api, ReportSection.products);
      expect(
        textContaining(host.tr('vendor.reports.profit.noCostHeading')),
        findsNothing,
      );
      expect(find.text('TSh${nb}5,000'), findsOneWidget);
    });

    apiTest('profit null on a sold product: the label, and no margin row', (
      tester,
      api,
    ) async {
      api.on(
        'GET /vendor/reports/products',
        productsAnswer([productRow('p1', hasProfitKey: true)]),
      );
      final host = await pumpSection(tester, api, ReportSection.products);
      expect(
        find.text('— · ${host.tr('vendor.reports.profit.noCostHeading')}'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reports-product-margin')), findsNothing);
    });

    apiTest('profit null with no sale in the period: — and no label', (
      tester,
      api,
    ) async {
      api.on(
        'GET /vendor/reports/products',
        productsAnswer([productRow('p1', hasProfitKey: true, noSales: true)]),
      );
      final host = await pumpSection(tester, api, ReportSection.products);
      expect(
        textContaining(host.tr('vendor.reports.profit.noCostHeading')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('reports-product-profit')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });

    apiTest('no cost rights (no key): no profit row at all', (
      tester,
      api,
    ) async {
      api.on(
        'GET /vendor/reports/products',
        productsAnswer([
          productRow('p1', hasProfitKey: false, hasMarginKey: false),
        ]),
      );
      await pumpSection(tester, api, ReportSection.products);
      expect(find.byKey(const Key('reports-product-profit')), findsNothing);
      expect(find.byKey(const Key('reports-product-margin')), findsNothing);
    });
  });

  group('N3b profit by period', () {
    Map<String, dynamic> answer(List<Map<String, dynamic>> buckets, num? p) => {
      ...head(),
      'totals': {
        'netExVatTzs': 9000,
        'commissionTzs': 0,
        'costTzs': 5000,
        'profitTzs': p,
        'marginPct': null,
      },
      'uncosted': {'lineCount': 1, 'qty': 1, 'revenueTzs': 5000},
      'hasVat': false,
      'buckets': buckets,
      'byChannel': {},
      'byProduct': [],
      'uncostedProducts': [],
    };
    Map<String, dynamic> day(int d, {num? profit, num uncosted = 0}) => {
      'start': '2026-10-0$d',
      'end': '2026-10-0$d',
      'netExVatTzs': 0,
      'commissionTzs': 0,
      'costTzs': 0,
      'profitTzs': profit,
      'marginPct': null,
      'uncostedRevenueTzs': uncosted,
    };

    apiTest('a no-sale day is plain; a no-cost day says so', (
      tester,
      api,
    ) async {
      api.on(
        'GET /vendor/reports/profit',
        answer([
          day(1, profit: 4000),
          day(2, uncosted: 5000),
          day(3),
          day(4, profit: 0),
        ], 4000),
      );
      final host = await pumpSection(tester, api, ReportSection.profit);
      final noCost = '— · ${host.tr('vendor.reports.profit.noCostHeading')}';
      // Day 2 only.
      expect(find.text(noCost), findsOneWidget);
      // Day 3 reads a bare dash (the other is the total's null margin); day
      // 4 a real zero.
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('TSh${nb}0'), findsWidgets);
      final data = tester
          .widget<ActivityBarChart>(find.byType(ActivityBarChart))
          .data;
      expect(data[0].description, '1 Oct: profit TSh${nb}4,000');
      expect(data[1].description, '2 Oct: no cost price');
      expect(data[2].description, '3 Oct: no sales');
      expect(data[3].description, '4 Oct: profit TSh${nb}0');
      final chart = tester.getSemantics(find.byKey(const Key('reports-chart')));
      expect(chart.label, contains('Highest: 1 Oct, TSh${nb}4,000'));
    });

    apiTest('in Swahili the bars say it too', (tester, api) async {
      api.on(
        'GET /vendor/reports/profit',
        answer([day(1, profit: 4000), day(2, uncosted: 5000), day(3)], 4000),
      );
      await pumpSection(tester, api, ReportSection.profit, lang: 'sw');
      final data = tester
          .widget<ActivityBarChart>(find.byType(ActivityBarChart))
          .data;
      expect(data[1].description, '2 Okt: hakuna bei ya kununua');
      expect(data[2].description, '3 Okt: hakuna mauzo');
    });

    apiTest('no day with a known profit: no chart', (tester, api) async {
      api.on(
        'GET /vendor/reports/profit',
        answer([day(1, uncosted: 5000), day(2)], null),
      );
      final host = await pumpSection(tester, api, ReportSection.profit);
      expect(find.byType(ActivityBarChart), findsNothing);
      // The total says no cost price, as sales without one exist.
      expect(
        find.text('— · ${host.tr('vendor.reports.profit.noCostHeading')}'),
        findsNWidgets(2),
      );
    });
  });

  group('D7 Add cost prices', () {
    const tools = {...ownerTools};
    final products = <Map<String, dynamic>>[
      {'id': 'none', 'name': 'NoCost', 'priceTzs': 1000, 'costTzs': null},
      {'id': 'has', 'name': 'HasCost', 'priceTzs': 1000, 'costTzs': 500},
      {
        'id': 'var',
        'name': 'VariantNoCost',
        'priceTzs': 1000,
        'costTzs': null,
        'variants': [
          {'name': 'Red', 'costTzs': 400, 'effectiveCostTzs': 400},
          {'name': 'Blue', 'costTzs': null, 'effectiveCostTzs': null},
        ],
      },
      {
        'id': 'varok',
        'name': 'VariantsCosted',
        'priceTzs': 1000,
        'costTzs': null,
        'variants': [
          {'name': 'Red', 'costTzs': 400, 'effectiveCostTzs': 400},
        ],
      },
    ];

    apiTest('filter=noCost lists only products with no cost price', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: products, tools: tools);
      final host = await pumpPage(
        tester,
        api,
        const VendorHomePage(open: 'products', filter: 'noCost'),
        user: owner,
        size: const Size(420, 1600),
        extraRoutes: reportRoutes,
      );
      expect(find.byKey(const Key('vendor-product-none')), findsOneWidget);
      expect(find.byKey(const Key('vendor-product-var')), findsOneWidget);
      expect(find.byKey(const Key('vendor-product-has')), findsNothing);
      expect(find.byKey(const Key('vendor-product-varok')), findsNothing);
      expect(find.text('No cost price (2)'), findsOneWidget);
      // All products clears it.
      await tester.tap(find.text(host.tr('vendor.stock.all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vendor-product-has')), findsOneWidget);
      expect(find.byKey(const Key('vendor-filter-no-cost')), findsNothing);
    });

    apiTest('every product costed: says so, with a way back', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [products[1]], tools: tools);
      final host = await pumpPage(
        tester,
        api,
        const VendorHomePage(open: 'products', filter: 'noCost'),
        user: owner,
        size: const Size(420, 1600),
        extraRoutes: reportRoutes,
      );
      expect(find.byKey(const Key('vendor-no-cost-empty')), findsOneWidget);
      expect(find.text(host.tr('vendor.stock.noCostEmpty')), findsOneWidget);
    });

    apiTest('no cost rights: the filter is ignored', (tester, api) async {
      seedVendorHome(
        api,
        products: [
          {'id': 'a', 'name': 'A', 'priceTzs': 1000},
          {'id': 'b', 'name': 'B', 'priceTzs': 1000},
        ],
        tools: {...ownerTools, 'canSeeCost': false},
      );
      await pumpPage(
        tester,
        api,
        const VendorHomePage(open: 'products', filter: 'noCost'),
        user: staffUser(['products', 'reports'], role: 'products'),
        size: const Size(420, 1600),
        extraRoutes: reportRoutes,
      );
      expect(find.byKey(const Key('vendor-product-a')), findsOneWidget);
      expect(find.byKey(const Key('vendor-product-b')), findsOneWidget);
      expect(find.byKey(const Key('vendor-filter-no-cost')), findsNothing);
    });

    apiTest('asking again re-applies the tab and filter', (tester, api) async {
      seedVendorHome(api, products: products, tools: tools);
      api.on('GET /vendor/reports/summary', ownerSummary());
      final at = ValueNotifier<String>('1');
      await pumpPage(
        tester,
        api,
        ValueListenableBuilder<String>(
          valueListenable: at,
          builder: (_, v, _) =>
              VendorHomePage(open: 'products', filter: 'noCost', openAt: v),
        ),
        user: owner,
        size: const Size(420, 1600),
        extraRoutes: reportRoutes,
      );
      await tester.tap(find.byKey(const Key('vendor-nav-reports')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vendor-reports-view')), findsOneWidget);
      at.value = '2';
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vendor-filter-no-cost')), findsOneWidget);
      expect(find.byKey(const Key('vendor-reports-view')), findsNothing);
    });

    apiTest('the link is only for people who may see cost', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/reports/stock-value', {
        ...head(),
        'asOf': '2026-10-29T11:05:00.000Z',
        'totals': {'atRetailTzs': 100, 'units': 1, 'products': 1},
        'costUnknown': {'count': 1, 'units': 1, 'retailTzs': 100},
        'rows': [],
      });
      await pumpSection(
        tester,
        api,
        ReportSection.stock,
        tools: {...ownerTools, 'canSeeCost': false},
        user: staffUser(['reports', 'products'], role: 'products'),
      );
      expect(find.byKey(const Key('reports-add-cost')), findsNothing);
    });

    apiTest('Profit: Add cost prices opens the filtered list', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/reports/profit', {
        ...head(),
        'totals': {'profitTzs': 1000, 'marginPct': 10.0},
        'uncosted': {'lineCount': 1, 'qty': 1, 'revenueTzs': 5000},
        'hasVat': false,
        'buckets': [],
        'byChannel': {},
        'byProduct': [],
        'uncostedProducts': [],
      });
      await pumpSection(tester, api, ReportSection.profit);
      await tapVisible(tester, find.byKey(const Key('reports-add-cost')));
      expect(
        textContaining('ROUTE-VENDOR-HOME open=products&filter=noCost'),
        findsOneWidget,
      );
    });
  });

  group('D10 / D11 negative counts', () {
    test('one minus, U+2212', () {
      expect(reportCount(-3), '−3');
      expect(reportCount(-1234), '−1,234');
      expect(reportCount(3), '3');
      expect(reportCount(0), '0');
      expect(reportCount(-3), isNot(contains('-')));
    });

    apiTest('a refund day reads −1 sale · −1 item', (tester, api) async {
      api.on('GET /vendor/reports/sales', {
        ...head(),
        'totals': {'netTzs': -45000, 'refundTzs': 45000, 'itemsSold': -1},
        'byChannel': {},
        'buckets': [
          {
            'start': '2026-10-02',
            'end': '2026-10-02',
            'netTzs': -45000,
            'app': {'count': -1, 'itemsSold': -1, 'netTzs': -45000},
            'walkIn': {'count': 0, 'itemsSold': 0, 'netTzs': 0},
          },
          {
            'start': '2026-10-03',
            'end': '2026-10-03',
            'netTzs': -90000,
            'app': {'count': -2, 'itemsSold': -3, 'netTzs': -90000},
            'walkIn': {'count': 0, 'itemsSold': 0, 'netTzs': 0},
          },
        ],
      });
      await pumpSection(tester, api, ReportSection.sales);
      expect(find.text('−1 sale · −1 item'), findsOneWidget);
      expect(find.text('−2 sales · −3 items'), findsOneWidget);
      expect(textContaining('-1'), findsNothing);
    });
  });
}
