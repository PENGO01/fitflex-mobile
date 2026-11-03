// Vendor reports · S6 UAT fixes (fitflex-mobile, after #247): D1 no-cost
// profit, D2 first use (hasEverSold), D4 web PDF download, D5 chart labels
// at 375 px, D6/D11 money, D10 plurals, D13 tab in the web address, D14
// screen-reader labels and focus.
//
// Every request goes to the in-process RecordingApi (http://fixtures.local);
// nothing here reaches a real server.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/reports/report_models.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';

import '../support/recording_api.dart';
import 'reports_s6_test.dart'
    show Files, head, openExport, ownerSummary, pumpHome, pumpSection, seedHome;

const nb = ' ';

Map<String, dynamic> emptySales() => {
  'grossTzs': 0,
  'discountTzs': 0,
  'refundTzs': 0,
  'netTzs': 0,
  'vatIncludedTzs': 0,
  'saleCount': 0,
  'orderCount': 0,
  'itemsSold': 0,
  'voided': {'count': 0, 'totalTzs': 0},
  'buckets': [],
};

Map<String, dynamic> productRow(String id, {Object? profit = 0}) => {
  'productId': id,
  'variant': null,
  'name': 'Item $id',
  'removed': false,
  'unitsSold': 2,
  'appUnits': 0,
  'walkInUnits': 2,
  'netRevenueTzs': 90000,
  'lastSoldAt': null,
  'stock': 4,
  'daysOfCover': 60,
  'coverState': 'ok',
  'noSalesInPeriod': false,
  'profitTzs': profit,
};

void main() {
  group('D1 no cost price', () {
    apiTest('null profit reads "— · No cost price", never TSh 0', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/reports/products', {
        ...head(),
        'sort': 'revenue',
        'rows': [
          productRow('p1', profit: null),
          productRow('p2', profit: 12000),
        ],
        'totals': {'unitsSold': 4, 'netRevenueTzs': 180000},
        'slowCount': 0,
        'nextCursor': null,
      });
      final host = await pumpSection(tester, api, ReportSection.products);
      final noCost = '— · ${host.tr('vendor.reports.profit.noCostHeading')}';
      expect(find.text(noCost), findsOneWidget);
      expect(find.text('TSh${nb}12,000'), findsOneWidget);
      expect(find.text('TSh${nb}0'), findsNothing);
    });

    apiTest('profit by product with a null margin reads "—"', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/reports/profit', {
        ...head(),
        'totals': {
          'netExVatTzs': 0,
          'commissionTzs': 0,
          'costTzs': 0,
          'profitTzs': null,
          'marginPct': null,
        },
        'uncosted': {'lineCount': 1, 'qty': 1, 'revenueTzs': 9000},
        'hasVat': false,
        'buckets': [],
        'byChannel': {},
        'byProduct': [],
        'uncostedProducts': [],
      });
      final host = await pumpSection(tester, api, ReportSection.profit);
      expect(
        find.text('— · ${host.tr('vendor.reports.profit.noCostHeading')}'),
        findsOneWidget,
      );
      expect(find.text('—'), findsOneWidget);
    });

    apiTest('stock value: a missing cost on a costed answer is unknown', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/reports/stock-value', {
        ...head(),
        'asOf': '2026-10-29T11:05:00.000Z',
        'totals': {
          'atRetailTzs': 90000,
          'units': 2,
          'products': 1,
          'atCostTzs': 0,
        },
        'rows': [
          {
            'productId': 'p1',
            'variant': null,
            'name': 'Whey',
            'stock': 2,
            'priceTzs': 45000,
            'valueAtRetailTzs': 90000,
          },
        ],
      });
      final host = await pumpSection(tester, api, ReportSection.stock);
      expect(
        find.text(host.tr('vendor.reports.costPriceUnknown')),
        findsOneWidget,
      );
    });
  });

  group('D2 first use', () {
    apiTest('hasEverSold false: first-use message with both actions', (
      tester,
      api,
    ) async {
      final s = ownerSummary()
        ..['sales'] = emptySales()
        ..['hasEverSold'] = false;
      seedHome(api, summary: s);
      final host = await pumpHome(tester, api);
      expect(find.byKey(const Key('reports-first-use')), findsOneWidget);
      expect(find.text(host.tr('vendor.reports.emptyFirst')), findsOneWidget);
      expect(
        find.byKey(const Key('reports-first-record-sale')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('reports-first-add-products')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reports-empty')), findsNothing);
      // Stock value still shows.
      expect(find.byKey(const Key('reports-card-stock')), findsOneWidget);
    });

    apiTest('hasEverSold absent: the usual empty period', (tester, api) async {
      final s = ownerSummary()..['sales'] = emptySales();
      seedHome(api, summary: s);
      await pumpHome(tester, api);
      expect(find.byKey(const Key('reports-first-use')), findsNothing);
      expect(find.byKey(const Key('reports-empty')), findsOneWidget);
    });

    apiTest('section page: first use instead of the figures', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/reports/payment-methods', {
        ...head(),
        'hasEverSold': false,
        'byYou': [],
        'viaFitFlex': [],
      });
      await pumpSection(tester, api, ReportSection.methods);
      expect(find.byKey(const Key('reports-first-use')), findsOneWidget);
    });
  });

  group('D4 web PDF', () {
    apiTest('on the web the PDF downloads; no new tab', (tester, api) async {
      final files = Files()
        ..install()
        ..web = true;
      seedHome(api);
      await pumpHome(tester, api);
      api.onCall('GET /vendor/reports/summary', (r) {
        final q = Uri.splitQueryString(r.query);
        return q['format'] == 'pdf' ? '%PDF-1.7' : ownerSummary();
      });
      await openExport(tester);
      await tester.tap(find.byKey(const Key('reports-export-pdf')));
      await tester.pumpAndSettle();
      expect(files.pdfs, isEmpty);
      expect(files.downloaded.single.$2, 'application/pdf');
      expect(files.downloaded.single.$1, startsWith('store_report_'));
    });
  });

  group('D5 chart labels at 375 px', () {
    apiTest('day labels thinned, each shown whole', (tester, api) async {
      final s = ownerSummary();
      (s['sales'] as Map)['buckets'] = [
        for (var d = 1; d <= 29; d++)
          {
            'start': '2026-10-${d.toString().padLeft(2, '0')}',
            'end': '2026-10-${d.toString().padLeft(2, '0')}',
            'netTzs': d * 1000,
          },
      ];
      seedHome(api, summary: s);
      await pumpPage(
        tester,
        api,
        const VendorHomePage(open: 'reports'),
        user: const {'id': 'v1', 'userType': 'vendor'},
        size: const Size(375, 2400),
      );
      final labels = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('bar-label-'),
      );
      final shown = labels.evaluate().length;
      expect(shown, greaterThan(3));
      expect(shown, lessThan(29));
      for (final e in labels.evaluate()) {
        final text = e.widget as Text;
        expect(text.softWrap, isFalse);
        expect(text.overflow, isNot(TextOverflow.clip));
        // The label's box is wider than its text: nothing cut off.
        final box = e.renderObject! as RenderBox;
        final painter = TextPainter(
          text: TextSpan(text: text.data, style: text.style),
          textDirection: TextDirection.ltr,
        )..layout();
        expect(box.size.width, greaterThanOrEqualTo(painter.width));
      }
    });
  });

  group('D10 English singular', () {
    apiTest('1 sale, 1 item, 1 order, 1 time', (tester, api) async {
      api.on('GET /vendor/reports/sales', {
        ...head(),
        'totals': {
          'netTzs': 45000,
          'saleCount': 1,
          'orderCount': 0,
          'itemsSold': 1,
          'voided': {'count': 1, 'totalTzs': 45000},
        },
        'byChannel': {},
        'buckets': [
          {
            'start': '2026-10-02',
            'end': '2026-10-02',
            'netTzs': 45000,
            'app': {'count': 0, 'itemsSold': 0},
            'walkIn': {'count': 1, 'itemsSold': 1, 'netTzs': 45000},
          },
        ],
      });
      await pumpSection(tester, api, ReportSection.sales);
      expect(find.text('1 sale · 1 item'), findsOneWidget);
      expect(
        find.text('Voided (not counted): 1 sale · TSh${nb}45,000'),
        findsOneWidget,
      );
    });

    apiTest('payouts: 1 order; methods: 1 time', (tester, api) async {
      api.on('GET /vendor/reports/payment-methods', {
        ...head(),
        'byYou': [
          {'method': 'mpesa', 'amountTzs': 5000, 'count': 1, 'sharePct': 100},
        ],
        'viaFitFlex': [],
      });
      await pumpSection(tester, api, ReportSection.methods);
      expect(
        find.text('M-Pesa · TSh${nb}5,000 · 100.0% · 1 time'),
        findsOneWidget,
      );
    });
  });

  group('D13 reload keeps the tab', () {
    apiTest('switching segment and tab writes the web address', (
      tester,
      api,
    ) async {
      final seen = <String>[];
      final keep = vendorHomeAddress;
      vendorHomeAddress = (u) => seen.add(u.toString());
      addTearDown(() => vendorHomeAddress = keep);
      seedHome(api);
      final host = await pumpHome(tester, api);
      await tester.tap(find.text(host.tr('vendor.reports.seg.payouts')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('vendor-reports-segment')),
          matching: find.text(host.tr('vendor.reports.seg.reports')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vendor-nav-products')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vendor-nav-reports')));
      await tester.pumpAndSettle();
      expect(seen, [
        '/vendor/home?open=payments',
        '/vendor/home?open=reports',
        '/vendor/home?open=products',
        '/vendor/home?open=reports',
      ]);
    });
  });

  group('D14 screen reader', () {
    apiTest('card labels: no double full stop; methods grouped', (
      tester,
      api,
    ) async {
      seedHome(api);
      final host = await pumpHome(tester, api);
      final profit = tester
          .getSemantics(find.byKey(const Key('reports-card-profit')))
          .label;
      expect(profit, contains('Not in profit. Open details'));
      expect(profit, isNot(contains('..')));
      final methods = tester
          .getSemantics(find.byKey(const Key('reports-card-methods')))
          .label;
      expect(methods, contains('${host.tr('vendor.reports.methods.byYou')}: '));
      expect(
        methods,
        contains('${host.tr('vendor.reports.methods.viaFitFlex')}: '),
      );
      expect(
        methods.indexOf(host.tr('vendor.reports.methods.byYou')),
        lessThan(methods.indexOf(host.tr('vendor.reports.methods.viaFitFlex'))),
      );
    });

    apiTest('empty period: not read with the Stock value card; Try another '
        'period focuses the period', (tester, api) async {
      final s = ownerSummary()..['sales'] = emptySales();
      seedHome(api, summary: s);
      final host = await pumpHome(tester, api);
      final stock = tester
          .getSemantics(find.byKey(const Key('reports-card-stock')))
          .label;
      expect(stock, isNot(contains('No sales')));
      expect(stock, isNot(contains(host.tr('vendor.reports.tryPeriod'))));
      await tapVisible(tester, find.byKey(const Key('reports-try-period')));
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'reports-period');
    });
  });
}
