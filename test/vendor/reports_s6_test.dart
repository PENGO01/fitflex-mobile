// Vendor reports · S6 (fitflex-functions#275) on screen: tab 2 gating
// (Payments vs Reports | Payouts), the overview cards and what each right
// shows, section pages (sales, products, stock, profit, payouts, customers,
// methods), deep-link rules, offline, stale answers, a refused period,
// Download (CSV / PDF / too large) and Swahili.
//
// Every request goes to the in-process RecordingApi (http://fixtures.local);
// nothing here reaches a real server. The share sheet and the browser
// download are replaced by recorders (DocumentActions).
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/screens/vendor/documents/document_share_sheet.dart';
import 'package:fitflexmobile/screens/vendor/reports/report_models.dart';
import 'package:fitflexmobile/screens/vendor/reports/report_section_page.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';

import '../support/recording_api.dart';
import 'customers_support.dart' show staffUser;
import 'stock_support.dart' show seedVendorHome;
import 'walkin_support.dart' show textContaining;

const owner = {'id': 'v1', 'userType': 'vendor', 'displayName': 'Asha'};

const ownerTools = {
  'reports': true,
  'canSeeCost': true,
  'canSeeOrderMoney': true,
  'stockLedger': true,
  'customers': true,
  'walkInSales': true,
};
const reportsOnlyTools = {
  'reports': true,
  'canSeeCost': false,
  'canSeeOrderMoney': false,
  'stockLedger': true,
  'customers': true,
  'walkInSales': true,
};

Map<String, dynamic> head({bool walkIn = true, bool inProgress = true}) => {
  'from': '2026-10-01',
  'to': '2026-10-29',
  'channel': 'all',
  'groupBy': 'day',
  // 11:05 UTC = 14:05 EAT.
  'generatedAt': '2026-10-29T11:05:00.000Z',
  'timezone': 'Africa/Dar_es_Salaam',
  'inProgress': inProgress,
  'channels': {'app': true, 'walkIn': walkIn},
};

List<Map<String, dynamic>> netBuckets() => [
  {'start': '2026-10-01', 'end': '2026-10-01', 'netTzs': 100000},
  {'start': '2026-10-02', 'end': '2026-10-02', 'netTzs': 250000},
  {'start': '2026-10-03', 'end': '2026-10-03', 'netTzs': 0},
];

/// A summary as the owner gets it (every section present).
Map<String, dynamic> ownerSummary() => {
  ...head(),
  'sales': {
    'grossTzs': 400000,
    'discountTzs': 30000,
    'refundTzs': 20000,
    'netTzs': 350000,
    'vatIncludedTzs': 0,
    'saleCount': 9,
    'orderCount': 3,
    'itemsSold': 17,
    'voided': {'count': 1, 'totalTzs': 45000},
    'buckets': netBuckets(),
  },
  'topProducts': [
    {
      'productId': 'p1',
      'variant': null,
      'name': 'Whey',
      'removed': false,
      'unitsSold': 6,
      'netRevenueTzs': 270000,
    },
  ],
  'slowCount': 2,
  'methods': {
    'byYou': [
      {'method': 'cash', 'amountTzs': 120000, 'count': 5, 'sharePct': 60.0},
      {'method': 'mpesa', 'amountTzs': 80000, 'count': 3, 'sharePct': 40.0},
    ],
    'viaFitFlex': [
      {
        'paymentMethod': 'mpesa',
        'amountTzs': 150000,
        'count': 3,
        'sharePct': 100.0,
      },
    ],
  },
  'stock': {
    'atRetailTzs': 900000,
    'units': 40,
    'atCostTzs': 600000,
    'costUnknownCount': 2,
  },
  'profit': {
    'profitTzs': 81000,
    'marginPct': 27.0,
    'netExVatTzs': 300000,
    'commissionTzs': 19000,
    'costTzs': 200000,
    'uncosted': {'qty': 3, 'revenueTzs': 50000},
  },
  'payouts': {
    'grossTzs': 150000,
    'commissionTzs': 15000,
    'payoutTzs': 135000,
    'paidOutTzs': 90000,
    'waitingTzs': 45000,
    'notDeliveredTzs': 0,
  },
  'customers': {'owedTzs': 70000, 'overdueTzs': 20000, 'collectedTzs': 30000},
};

/// What a `reports`-only staff member gets: no cost, payouts or customers.
Map<String, dynamic> staffSummary() {
  final s = ownerSummary()
    ..remove('profit')
    ..remove('payouts')
    ..remove('customers');
  s['stock'] = {'atRetailTzs': 900000, 'units': 40};
  return s;
}

void seedHome(
  RecordingApi api, {
  Map<String, dynamic> tools = ownerTools,
  Map<String, dynamic>? summary,
}) {
  seedVendorHome(api, products: [], tools: tools);
  api.on('GET /vendor/sales', {'sales': [], 'nextCursor': null});
  api.on('GET /vendor/reports/summary', summary ?? ownerSummary());
}

Future<PageHost> pumpHome(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> user = owner,
  String lang = 'en',
  String open = 'reports',
}) => pumpPage(
  tester,
  api,
  VendorHomePage(open: open),
  user: user,
  lang: lang,
  size: const Size(420, 2400),
  keepRequests: true,
  extraRoutes: reportRoutes,
);

/// Report pages as markers (the home pushes them).
final reportRoutes = <RouteBase>[
  GoRoute(
    path: '/vendor/home',
    builder: (_, s) => Scaffold(body: Text('ROUTE-VENDOR-HOME ${s.uri.query}')),
  ),
  GoRoute(
    path: '/vendor/reports/:section',
    builder: (_, s) => Scaffold(body: Text('ROUTE-REPORT ${s.uri}')),
  ),
];

/// A section page at "/" (so go() / pop() work), signed in as [user].
Future<PageHost> pumpSection(
  WidgetTester tester,
  RecordingApi api,
  ReportSection section, {
  Map<String, dynamic> tools = ownerTools,
  Map<String, dynamic> user = owner,
  String lang = 'en',
  String? from = '2026-10-01',
  String? to = '2026-10-29',
  bool settle = true,
}) {
  api.on('GET /vendor/tools/options', tools);
  return pumpPage(
    tester,
    api,
    ReportSectionPage(
      section: section,
      from: from,
      to: to,
      now: DateTime.utc(2026, 10, 29, 10),
    ),
    user: user,
    lang: lang,
    size: const Size(420, 2600),
    keepRequests: true,
    settle: settle,
    extraRoutes: reportRoutes,
  );
}

/// Records files handed to the share sheet or downloaded.
class Files {
  final shared = <(String, String)>[];
  final downloaded = <(String, String)>[];
  final pdfs = <String>[];
  bool web = false;

  void install() {
    final typed = DocumentActions.shareTypedFile;
    final download = DocumentActions.download;
    final shareFile = DocumentActions.shareFile;
    final openPdf = DocumentActions.openPdf;
    final isWeb = DocumentActions.isWeb;
    DocumentActions.shareTypedFile = (b, name, mime) async =>
        shared.add((name, mime));
    DocumentActions.download = (b, name, mime) async =>
        downloaded.add((name, mime));
    DocumentActions.shareFile = (b, name) async => pdfs.add(name);
    DocumentActions.openPdf = (b, name) async {
      pdfs.add('web:$name');
      return true;
    };
    DocumentActions.isWeb = () => web;
    addTearDown(() {
      DocumentActions.shareTypedFile = typed;
      DocumentActions.download = download;
      DocumentActions.shareFile = shareFile;
      DocumentActions.openPdf = openPdf;
      DocumentActions.isWeb = isWeb;
    });
  }
}

/// Opens Download on the Reports segment (scrolled to, as the list builds
/// lazily and Swahili cards are taller).
Future<void> openExport(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('reports-export')),
    400,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('vendor-reports-view')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('reports-export')));
  await tester.pumpAndSettle();
}

Map<String, String> queryOf(RecordedRequest r) => Uri.splitQueryString(r.query);

void main() {
  group('tab 2 gating', () {
    apiTest('reports off: the tab stays Payments, no Reports, no call', (
      tester,
      api,
    ) async {
      seedHome(api, tools: {...ownerTools, 'reports': false});
      final host = await pumpHome(tester, api, open: 'payments');
      expect(find.byKey(const Key('vendor-nav-payments')), findsOneWidget);
      expect(find.byKey(const Key('vendor-nav-reports')), findsNothing);
      expect(find.byKey(const Key('vendor-reports-segment')), findsNothing);
      expect(find.text(host.tr('vendor.reports.tab')), findsNothing);
      expect(api.sent('GET', '/vendor/reports/summary'), isFalse);
    });

    apiTest('options failing: Payments (fail closed)', (tester, api) async {
      seedHome(api);
      api.fail('GET /vendor/tools/options', 500);
      await pumpHome(tester, api, open: 'payments');
      expect(find.byKey(const Key('vendor-nav-payments')), findsOneWidget);
      expect(find.byKey(const Key('vendor-nav-reports')), findsNothing);
      expect(api.sent('GET', '/vendor/reports/summary'), isFalse);
    });

    apiTest('owner: Reports tab with Reports | Payouts; Payouts unchanged', (
      tester,
      api,
    ) async {
      seedHome(api);
      api.on('GET /vendor/payments', {
        'todaySalesTzs': 50000,
        'todayNetTzs': 45000,
      });
      final host = await pumpHome(tester, api);
      expect(find.byKey(const Key('vendor-nav-reports')), findsOneWidget);
      expect(find.byKey(const Key('vendor-nav-payments')), findsNothing);
      expect(find.byKey(const Key('vendor-reports-segment')), findsOneWidget);
      expect(find.byKey(const Key('vendor-reports-view')), findsOneWidget);
      final q = queryOf(api.where('GET', '/vendor/reports/summary').last);
      expect(q['format'], 'json');
      expect(q['channel'], 'all');
      expect(q['from'], isNotEmpty);
      expect(q['to'], isNotEmpty);
      // Payouts: today's Payments content, plus "You receive" and the link.
      await tester.tap(find.text(host.tr('vendor.reports.seg.payouts')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('vendor-download-statement')),
        findsOneWidget,
      );
      expect(find.text('You receive TSh 45,000'), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const Key('vendor-payouts-report-link')),
      );
      expect(
        textContaining('ROUTE-REPORT /vendor/reports/payouts'),
        findsOneWidget,
      );
    });

    apiTest('staff with reports only: no Payouts segment, no money cards', (
      tester,
      api,
    ) async {
      seedHome(api, tools: reportsOnlyTools, summary: staffSummary());
      final host = await pumpHome(
        tester,
        api,
        user: staffUser(['reports'], role: 'reports'),
      );
      expect(find.byKey(const Key('vendor-nav-reports')), findsNothing);
      // One section only (no navigation bar), the Reports view itself.
      expect(find.byKey(const Key('vendor-reports-view')), findsOneWidget);
      expect(find.byKey(const Key('vendor-reports-segment')), findsNothing);
      expect(find.byKey(const Key('reports-card-sales')), findsOneWidget);
      expect(find.byKey(const Key('reports-card-stock')), findsOneWidget);
      expect(find.byKey(const Key('reports-card-profit')), findsNothing);
      expect(find.byKey(const Key('reports-card-payouts')), findsNothing);
      expect(find.byKey(const Key('reports-card-customers')), findsNothing);
      // No cost words anywhere.
      expect(find.byKey(const Key('reports-card-stock-cost')), findsNothing);
      expect(
        textContaining(host.tr('vendor.reports.stock.atCost')),
        findsNothing,
      );
      expect(textContaining(host.tr('vendor.reports.profit')), findsNothing);
    });

    apiTest('cost right but no profit in the answer: no card, never zeros', (
      tester,
      api,
    ) async {
      final summary = ownerSummary()..remove('profit');
      seedHome(api, summary: summary);
      await pumpHome(tester, api);
      expect(find.byKey(const Key('reports-card-profit')), findsNothing);
      expect(find.byKey(const Key('reports-card-payouts')), findsOneWidget);
    });
  });

  group('overview cards', () {
    apiTest('owner: every card, header line, voided, pending sync', (
      tester,
      api,
    ) async {
      seedHome(api);
      final host = await pumpHome(tester, api);
      expect(find.text('TSh 350,000'), findsWidgets);
      expect(
        textContaining('Gross TSh 400,000 · Discounts −TSh 30,000'),
        findsOneWidget,
      );
      expect(find.text('12 sales · 17 items'), findsOneWidget);
      expect(
        find.text('Voided (not counted): 1 sales · TSh 45,000'),
        findsOneWidget,
      );
      expect(find.text('Updated 14:05'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('reports-header-line'))).data,
        contains('(so far) · All sales'),
      );
      for (final k in [
        'sales',
        'products',
        'stock',
        'profit',
        'payouts',
        'customers',
        'methods',
      ]) {
        expect(find.byKey(Key('reports-card-$k')), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('reports-card-stock-cost')), findsOneWidget);
      expect(
        find.text(
          'Sold without a cost price: 3 items · TSh 50,000. Not in profit.',
        ),
        findsOneWidget,
      );
      expect(find.text('27.0%'), findsOneWidget);
      expect(find.text('Slow sellers: 2'), findsOneWidget);
      expect(
        textContaining(host.tr('vendor.reports.methods.netOfChange')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reports-pending-sync')), findsNothing);
      // Cards open their section with the same period.
      await tapVisible(tester, find.byKey(const Key('reports-card-profit')));
      expect(
        textContaining('ROUTE-REPORT /vendor/reports/profit?from='),
        findsOneWidget,
      );
    });

    apiTest('channel pills appear with walk-in; picking Shop asks again', (
      tester,
      api,
    ) async {
      seedHome(api);
      await pumpHome(tester, api);
      expect(find.byKey(const Key('reports-channel-pills')), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const Key('reports-channel-walk_in')),
      );
      expect(
        queryOf(api.where('GET', '/vendor/reports/summary').last)['channel'],
        'walk_in',
      );
    });

    apiTest('no walk-in channel: no channel pills', (tester, api) async {
      final s = ownerSummary()..addAll(head(walkIn: false));
      seedHome(api, tools: {...ownerTools, 'walkInSales': false}, summary: s);
      await pumpHome(tester, api);
      expect(find.byKey(const Key('reports-channel-pills')), findsNothing);
    });

    apiTest('a period with no sales: empty state, stock still shown', (
      tester,
      api,
    ) async {
      final s = ownerSummary();
      s['sales'] = {
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
      seedHome(api, summary: s);
      final host = await pumpHome(tester, api);
      expect(find.byKey(const Key('reports-empty')), findsOneWidget);
      expect(find.text(host.tr('vendor.reports.tryPeriod')), findsOneWidget);
      expect(find.byKey(const Key('reports-card-stock')), findsOneWidget);
      expect(find.byKey(const Key('reports-card-sales')), findsNothing);
    });

    apiTest('offline: No connection with Try again and no old figures', (
      tester,
      api,
    ) async {
      seedHome(api);
      final host = await pumpHome(tester, api);
      expect(find.text('TSh 350,000'), findsWidgets);
      api.onCall(
        'GET /vendor/reports/summary',
        (_) => throw Exception('offline'),
      );
      await tapVisible(tester, find.byKey(const Key('reports-refresh')));
      // The client retries twice before giving up.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reports-offline')), findsOneWidget);
      expect(find.text(host.tr('error.network')), findsOneWidget);
      expect(find.text('TSh 350,000'), findsNothing);
      expect(find.byKey(const Key('reports-export')), findsNothing);
    });

    apiTest('one failing load: error with Try again; retry recovers', (
      tester,
      api,
    ) async {
      seedHome(api);
      api.fail('GET /vendor/reports/summary', 500);
      final host = await pumpHome(tester, api);
      expect(find.byKey(const Key('reports-failed')), findsOneWidget);
      api.heal('GET /vendor/reports/summary');
      await tapVisible(tester, find.text(host.tr('common.retry')));
      expect(find.byKey(const Key('reports-card-sales')), findsOneWidget);
    });

    apiTest('two quick period changes: only the last answer shows', (
      tester,
      api,
    ) async {
      seedHome(api);
      final slow = Completer<void>();
      var holdNext = false;
      api.onCall('GET /vendor/reports/summary', (r) async {
        final s = ownerSummary();
        if (holdNext) {
          // "Today": held, then answers after "Yesterday" did.
          holdNext = false;
          await slow.future;
          (s['sales'] as Map)['netTzs'] = 111;
        } else {
          (s['sales'] as Map)['netTzs'] = 222;
        }
        return s;
      });
      await pumpHome(tester, api);
      holdNext = true;
      await tester.tap(find.byKey(const Key('reports-preset-today')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('reports-preset-yesterday')));
      await tester.pumpAndSettle();
      slow.complete();
      await tester.pumpAndSettle();
      expect(find.text('TSh 222'), findsWidgets);
      expect(find.text('TSh 111'), findsNothing);
    });

    apiTest('a period the server refuses: inline error, figures stay', (
      tester,
      api,
    ) async {
      seedHome(api);
      await pumpHome(tester, api);
      api.fail('GET /vendor/reports/summary', 400, {
        'error': 'invalid_range',
        'reason': 'future',
        'today': '2026-10-29',
      });
      await tapVisible(
        tester,
        find.byKey(const Key('reports-preset-lastMonth')),
      );
      expect(find.byKey(const Key('reports-range-error')), findsOneWidget);
      expect(find.text('Choose dates up to today.'), findsOneWidget);
      expect(find.byKey(const Key('reports-card-sales')), findsOneWidget);
    });

    apiTest('pending offline sales: the banner says how many', (
      tester,
      api,
    ) async {
      // Two walk-in sales waiting on this device; syncing fails, so they
      // stay queued.
      Map<String, dynamic> queued(String ref) => {
        'body': {
          'clientRef': ref,
          'soldAt': '2026-10-29T08:00:00.000Z',
          'lines': [
            {'productId': 'p1', 'qty': 1},
          ],
          'payments': [
            {'method': 'cash', 'amountTzs': 45000},
          ],
        },
        'display': {
          'business': 'Dar Gear',
          'lines': [
            {'name': 'Whey', 'listPriceTzs': 45000},
          ],
        },
        'queuedAt': '2026-10-29T08:00:00.000Z',
        'state': 'waiting',
      };
      SharedPreferences.setMockInitialValues({
        'vendor_sale_queue.v1.v1': jsonEncode([
          queued('sale_q_00000001'),
          queued('sale_q_00000002'),
        ]),
      });
      seedHome(api);
      api.fail('POST /vendor/sales', 503);
      await pumpHome(tester, api);
      expect(find.byKey(const Key('reports-pending-sync')), findsOneWidget);
      expect(
        find.text(
          '2 sales on this phone are waiting to sync and are not in these '
          'figures.',
        ),
        findsOneWidget,
      );
    });
  });

  group('section pages', () {
    apiTest('Sales: totals, VAT only when there is some, chart summary', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/reports/sales', {
        ...head(),
        'totals': {
          'grossTzs': 400000,
          'discountTzs': 30000,
          'refundTzs': 20000,
          'netTzs': 350000,
          'vatIncludedTzs': 0,
          'saleCount': 9,
          'orderCount': 3,
          'itemsSold': 17,
          'voided': {'count': 1, 'totalTzs': 45000},
        },
        'byChannel': {
          'app': {'netTzs': 150000, 'count': 3},
          'walkIn': {'netTzs': 200000, 'count': 9},
        },
        'buckets': [
          for (final b in netBuckets())
            {
              ...b,
              'app': {
                'grossTzs': 0,
                'discountTzs': 0,
                'refundTzs': 0,
                'netTzs': 0,
                'vatIncludedTzs': 0,
                'count': 0,
                'itemsSold': 0,
              },
              'walkIn': {
                'grossTzs': b['netTzs'],
                'discountTzs': 0,
                'refundTzs': 0,
                'netTzs': b['netTzs'],
                'vatIncludedTzs': 0,
                'count': 1,
                'itemsSold': 1,
              },
            },
        ],
      });
      final host = await pumpSection(tester, api, ReportSection.sales);
      expect(find.text(host.tr('vendor.reports.view.sales')), findsWidgets);
      expect(find.byKey(const Key('reports-sales-vat')), findsNothing);
      expect(find.byKey(const Key('reports-voided')), findsOneWidget);
      expect(find.byKey(const Key('reports-group-pills')), findsOneWidget);
      final chart = tester.getSemantics(find.byKey(const Key('reports-chart')));
      // The spoken summary first; the selected bar's readout follows it.
      expect(
        chart.label,
        startsWith(
          'Net sales by day, 1–29 Oct 2026. Highest: 2 Oct, TSh 250,000. '
          'Total TSh 350,000. Table below.',
        ),
      );
      expect(find.byKey(const Key('reports-channel-split')), findsOneWidget);
      final q = queryOf(api.where('GET', '/vendor/reports/sales').last);
      expect(q['from'], '2026-10-01');
      expect(q['to'], '2026-10-29');
      expect(q['channel'], 'all');
      expect(q.containsKey('groupBy'), isFalse);
      // Week grouping is asked for explicitly.
      await tapVisible(tester, find.byKey(const Key('reports-group-week')));
      expect(
        queryOf(api.where('GET', '/vendor/reports/sales').last)['groupBy'],
        'week',
      );
    });

    apiTest('Sales with VAT shows VAT included', (tester, api) async {
      api.on('GET /vendor/reports/sales', {
        ...head(),
        'totals': {
          'netTzs': 118000,
          'vatIncludedTzs': 18000,
          'saleCount': 1,
          'itemsSold': 1,
        },
        'byChannel': {},
        'buckets': [],
      });
      await pumpSection(tester, api, ReportSection.sales);
      expect(find.byKey(const Key('reports-sales-vat')), findsOneWidget);
      expect(find.text('TSh 18,000'), findsOneWidget);
    });

    apiTest('Products: cover from the server, Reorder soon, sorts, no profit '
        'key → no profit row', (tester, api) async {
      api.on('GET /vendor/reports/products', {
        ...head(),
        'sort': 'revenue',
        'rows': [
          {
            'productId': 'p1',
            'variant': null,
            'name': 'Whey',
            'removed': false,
            'unitsSold': 60,
            'appUnits': 20,
            'walkInUnits': 40,
            'netRevenueTzs': 2700000,
            'lastSoldAt': '2026-10-28T20:30:00.000Z',
            'stock': 30,
            'avgDailyUnits30': 2,
            'daysOfCover': 15,
            'coverState': 'ok',
            'noSalesInPeriod': false,
          },
          {
            'productId': 'p2',
            'variant': 'Red',
            'name': 'Mat',
            'removed': false,
            'unitsSold': 30,
            'appUnits': 0,
            'walkInUnits': 30,
            'netRevenueTzs': 300000,
            'lastSoldAt': null,
            'stock': 5,
            'avgDailyUnits30': 1,
            'daysOfCover': 5,
            'coverState': 'soon',
            'noSalesInPeriod': false,
          },
        ],
        'totals': {'unitsSold': 90, 'netRevenueTzs': 3000000},
        'slowCount': 0,
        'nextCursor': 'b2:50',
      });
      final host = await pumpSection(
        tester,
        api,
        ReportSection.products,
        tools: reportsOnlyTools,
        user: staffUser(['reports'], role: 'reports'),
      );
      expect(find.text('15 days'), findsOneWidget);
      expect(find.text('5 days'), findsOneWidget);
      expect(find.byKey(const Key('reports-reorder-soon')), findsOneWidget);
      expect(find.text('Mat · Red'), findsOneWidget);
      expect(find.text(host.tr('vendor.reports.never')), findsOneWidget);
      // 20:30 UTC on 28 Oct is 23:30 EAT the same day.
      expect(find.text('28 Oct 2026'), findsOneWidget);
      expect(find.byKey(const Key('reports-product-profit')), findsNothing);
      // Load more sends the cursor; Slow sellers asks the server.
      await tapVisible(tester, find.byKey(const Key('reports-load-more')));
      expect(
        queryOf(api.where('GET', '/vendor/reports/products').last)['cursor'],
        'b2:50',
      );
      await tapVisible(tester, find.text(host.tr('vendor.reports.slow')));
      expect(
        queryOf(api.where('GET', '/vendor/reports/products').last)['sort'],
        'slow',
      );
    });

    apiTest('Stock value: as of now, cost only with the keys, add-cost link', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/reports/stock-value', {
        ...head(),
        'asOf': '2026-10-29T11:05:00.000Z',
        'totals': {
          'atRetailTzs': 900000,
          'units': 40,
          'products': 3,
          'atCostTzs': 600000,
        },
        'costUnknown': {'count': 2, 'units': 5, 'retailTzs': 100000},
        'rows': [
          {
            'productId': 'p1',
            'variant': null,
            'name': 'Whey',
            'stock': 10,
            'priceTzs': 45000,
            'valueAtRetailTzs': 450000,
            'costTzs': 30000,
            'valueAtCostTzs': 300000,
          },
          {
            'productId': 'p2',
            'variant': null,
            'name': 'Mat',
            'stock': 5,
            'priceTzs': 20000,
            'valueAtRetailTzs': 100000,
            'costTzs': null,
            'valueAtCostTzs': null,
          },
        ],
      });
      final host = await pumpSection(tester, api, ReportSection.stock);
      expect(
        find.text('As of 14:05 today. The period you picked does not apply.'),
        findsOneWidget,
      );
      // The period does not apply: no controls are offered.
      expect(find.byKey(const Key('reports-period-pills')), findsNothing);
      expect(find.byKey(const Key('reports-stock-at-cost')), findsOneWidget);
      expect(
        find.byKey(const Key('reports-stock-cost-unknown')),
        findsOneWidget,
      );
      expect(
        find.text(host.tr('vendor.reports.costPriceUnknown')),
        findsOneWidget,
      );
      final q = queryOf(api.where('GET', '/vendor/reports/stock-value').last);
      expect(q.containsKey('from'), isFalse);
      expect(q.containsKey('channel'), isFalse);
      await tapVisible(tester, find.byKey(const Key('reports-add-cost')));
      expect(find.text('ROUTE-VENDOR-HOME open=products'), findsOneWidget);
    });

    apiTest('Stock value without cost keys: no cost words at all', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/reports/stock-value', {
        ...head(),
        'asOf': '2026-10-29T11:05:00.000Z',
        'totals': {'atRetailTzs': 450000, 'units': 10, 'products': 1},
        'rows': [
          {
            'productId': 'p1',
            'variant': null,
            'name': 'Whey',
            'stock': 10,
            'priceTzs': 45000,
            'valueAtRetailTzs': 450000,
          },
        ],
      });
      final host = await pumpSection(
        tester,
        api,
        ReportSection.stock,
        tools: reportsOnlyTools,
        user: staffUser(['reports'], role: 'reports'),
      );
      expect(find.byKey(const Key('reports-stock-at-cost')), findsNothing);
      expect(find.byKey(const Key('reports-stock-cost-unknown')), findsNothing);
      expect(textContaining(host.tr('vendor.reports.costPrice')), findsNothing);
      expect(
        textContaining(host.tr('vendor.reports.stock.atCost')),
        findsNothing,
      );
    });

    apiTest('Profit: uncosted block apart, commission as a minus', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/reports/profit', {
        ...head(),
        'totals': {
          'netExVatTzs': 300000,
          'commissionTzs': 19000,
          'costTzs': 200000,
          'profitTzs': 81000,
          'marginPct': 27.0,
        },
        'uncosted': {
          'lineCount': 2,
          'qty': 3,
          'revenueTzs': 50000,
          'netExVatTzs': 42373,
        },
        'hasVat': true,
        'buckets': [],
        'byChannel': {},
        'byProduct': [],
        'uncostedProducts': [
          {
            'productId': 'p9',
            'variant': null,
            'name': 'Gloves',
            'removed': false,
            'units': 3,
            'revenueTzs': 50000,
          },
        ],
      });
      final host = await pumpSection(tester, api, ReportSection.profit);
      expect(find.byKey(const Key('reports-profit-uncosted')), findsOneWidget);
      expect(find.text('−TSh 19,000'), findsOneWidget);
      expect(find.text('27.0%'), findsOneWidget);
      expect(find.text(host.tr('vendor.reports.profit.noVat')), findsOneWidget);
      expect(
        find.text(host.tr('vendor.reports.profit.noCostHeading')),
        findsOneWidget,
      );
    });

    apiTest('Payouts: basis, statuses, week badges', (tester, api) async {
      api.on('GET /vendor/reports/marketplace-net', {
        ...head(),
        'basis': 'delivered',
        'totals': {
          'orderCount': 3,
          'grossTzs': 150000,
          'commissionTzs': 15000,
          'payoutTzs': 135000,
        },
        'status': {
          'notDelivered': {'orders': 1, 'payoutTzs': 9000},
          'waiting': {'orders': 1, 'payoutTzs': 45000},
          'paidOut': {'orders': 2, 'payoutTzs': 90000},
        },
        'weeks': [
          {
            'periodStartDate': '2026-10-05',
            'periodEndDate': '2026-10-11',
            'orderCount': 2,
            'grossTzs': 100000,
            'commissionTzs': 10000,
            'payoutTzs': 90000,
            'paidOut': true,
            'statement': {'id': 'vs1', 'status': 'paid', 'finalNetTzs': 90000},
          },
          {
            'periodStartDate': '2026-10-19',
            'periodEndDate': '2026-10-25',
            'orderCount': 1,
            'grossTzs': 50000,
            'commissionTzs': 5000,
            'payoutTzs': 45000,
            'paidOut': false,
            'statement': null,
          },
        ],
      });
      final host = await pumpSection(tester, api, ReportSection.payouts);
      expect(
        find.text(host.tr('vendor.reports.payouts.basis')),
        findsOneWidget,
      );
      expect(find.text('5–11 Oct 2026'), findsOneWidget);
      expect(
        find.text(host.tr('vendor.reports.payouts.paidOut')),
        findsWidgets,
      );
      expect(
        find.text(host.tr('vendor.reports.payouts.noStatement')),
        findsOneWidget,
      );
      // App only: no channel pills; the channel is not sent.
      expect(find.byKey(const Key('reports-channel-pills')), findsNothing);
      expect(
        queryOf(
          api.where('GET', '/vendor/reports/marketplace-net').last,
        ).containsKey('channel'),
        isFalse,
      );
    });

    apiTest('Customers: owed, aging and Open Owed to you', (tester, api) async {
      api.on('GET /vendor/reports/customers', {
        ...head(),
        'asOf': '2026-10-29',
        'owedTzs': 70000,
        'overdueTzs': 20000,
        'aging': {
          'current': 50000,
          'd1_30': 20000,
          'd31_60': 0,
          'd61_90': 0,
          'd90plus': 0,
        },
        'creditSales': {'count': 2, 'totalTzs': 60000},
        'collectedTzs': 30000,
        'buyers': {'shop': 4, 'app': 3},
      });
      await pumpSection(tester, api, ReportSection.customers);
      expect(find.text('TSh 70,000'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('reports-open-owed')));
      expect(
        textContaining('ROUTE-VENDOR-HOME open=customers'),
        findsOneWidget,
      );
    });

    apiTest('Payment methods: two groups never added together', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/reports/payment-methods', {
        ...head(),
        'byYou': [
          {'method': 'cash', 'amountTzs': 120000, 'count': 5, 'sharePct': 60.0},
          {'method': 'mpesa', 'amountTzs': 80000, 'count': 3, 'sharePct': 40.0},
        ],
        'viaFitFlex': [],
      });
      final host = await pumpSection(tester, api, ReportSection.methods);
      expect(
        find.text(host.tr('vendor.reports.methods.byYou')),
        findsOneWidget,
      );
      expect(
        find.text(host.tr('vendor.reports.methods.viaFitFlex')),
        findsOneWidget,
      );
      expect(
        find.text('Cash after change · TSh 120,000 · 60.0% · 5 times'),
        findsOneWidget,
      );
      expect(find.text(host.tr('vendor.reports.methods.none')), findsOneWidget);
      expect(find.text(host.tr('vendor.pos.moneyNotice')), findsOneWidget);
    });
  });

  group('deep links', () {
    apiTest('reports off: to vendor home, no message', (tester, api) async {
      await pumpSection(
        tester,
        api,
        ReportSection.sales,
        tools: {...ownerTools, 'reports': false},
      );
      expect(find.text('ROUTE-VENDOR-HOME '), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(api.sent('GET', '/vendor/reports/sales'), isFalse);
    });

    apiTest('no reports permission: vendor home + no access', (
      tester,
      api,
    ) async {
      final host = await pumpSection(
        tester,
        api,
        ReportSection.sales,
        user: staffUser(['payments'], role: 'payments'),
      );
      expect(find.text('ROUTE-VENDOR-HOME '), findsOneWidget);
      expect(host.snack(host.tr('vendor.reports.noAccess')), findsOneWidget);
    });

    apiTest('Profit without cost: Reports home + no access, nothing asked', (
      tester,
      api,
    ) async {
      final host = await pumpSection(
        tester,
        api,
        ReportSection.profit,
        tools: reportsOnlyTools,
        user: staffUser(['reports'], role: 'reports'),
      );
      expect(find.text('ROUTE-VENDOR-HOME open=reports'), findsOneWidget);
      expect(host.snack(host.tr('vendor.reports.noAccess')), findsOneWidget);
      expect(api.sent('GET', '/vendor/reports/profit'), isFalse);
    });

    apiTest('the server refuses (403 payout_not_allowed): Reports home', (
      tester,
      api,
    ) async {
      api.fail('GET /vendor/reports/marketplace-net', 403, {
        'error': 'payout_not_allowed',
      });
      final host = await pumpSection(tester, api, ReportSection.payouts);
      expect(find.text('ROUTE-VENDOR-HOME open=reports'), findsOneWidget);
      expect(host.snack(host.tr('vendor.reports.noAccess')), findsOneWidget);
    });

    apiTest('feature switched off on the server: vendor home', (
      tester,
      api,
    ) async {
      api.fail('GET /vendor/reports/sales', 404, {'error': 'feature_disabled'});
      await pumpSection(tester, api, ReportSection.sales);
      expect(find.text('ROUTE-VENDOR-HOME '), findsOneWidget);
    });

    apiTest('the period of the link is the one asked', (tester, api) async {
      api.on('GET /vendor/reports/payment-methods', {
        ...head(),
        'byYou': [],
        'viaFitFlex': [],
      });
      await pumpSection(
        tester,
        api,
        ReportSection.methods,
        from: '2026-10-26',
        to: '2026-10-29',
      );
      final q = queryOf(
        api.where('GET', '/vendor/reports/payment-methods').last,
      );
      expect((q['from'], q['to']), ('2026-10-26', '2026-10-29'));
      final pill = tester.getSemantics(
        find.byKey(const Key('reports-preset-thisWeek')),
      );
      expect(pill.label, 'Period: This week');
      expect(pill.flagsCollection.isSelected, Tristate.isTrue);
    });
  });

  group('download', () {
    apiTest('CSV of a section goes to the share sheet, in the app language', (
      tester,
      api,
    ) async {
      final files = Files()..install();
      seedHome(api);
      api.on('GET /vendor/reports/sales', '﻿Period start,Net sales (TZS)\r\n');
      final host = await pumpHome(tester, api);
      await openExport(tester);
      // Every section this owner may see has a CSV row, plus the PDF.
      for (final s in ReportSection.values) {
        expect(find.byKey(Key('reports-export-${s.api}')), findsOneWidget);
      }
      expect(find.byKey(const Key('reports-export-pdf')), findsOneWidget);
      expect(find.text('Downloads use English.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reports-export-sales')));
      await tester.pumpAndSettle();
      final r = api.where('GET', '/vendor/reports/sales').last;
      expect(queryOf(r)['format'], 'csv');
      expect(queryOf(r)['lang'], 'en');
      expect(files.shared.single.$2, 'text/csv');
      expect(files.shared.single.$1, startsWith('store_sales_'));
      expect(host.snack(host.tr('vendor.reports.exported')), findsOneWidget);
    });

    apiTest('reports-only staff: CSV rows only for their sections', (
      tester,
      api,
    ) async {
      Files().install();
      seedHome(api, tools: reportsOnlyTools, summary: staffSummary());
      await pumpHome(
        tester,
        api,
        user: staffUser(['reports'], role: 'reports'),
      );
      await openExport(tester);
      expect(find.byKey(const Key('reports-export-profit')), findsNothing);
      expect(
        find.byKey(const Key('reports-export-marketplace-net')),
        findsNothing,
      );
      expect(find.byKey(const Key('reports-export-customers')), findsNothing);
      expect(find.byKey(const Key('reports-export-sales')), findsOneWidget);
    });

    apiTest('PDF summary; on the web the CSV downloads, the PDF opens', (
      tester,
      api,
    ) async {
      final files = Files()..install();
      seedHome(api);
      await pumpHome(tester, api);
      // Summary JSON stays seeded; the PDF call shares the path.
      api.onCall('GET /vendor/reports/summary', (r) {
        final q = Uri.splitQueryString(r.query);
        return q['format'] == 'pdf' ? '%PDF-1.7' : ownerSummary();
      });
      await openExport(tester);
      await tester.tap(find.byKey(const Key('reports-export-pdf')));
      await tester.pumpAndSettle();
      expect(files.pdfs.single, startsWith('store_report_'));
      final pdf = api.where('GET', '/vendor/reports/summary').last;
      expect(queryOf(pdf)['format'], 'pdf');
      expect(queryOf(pdf)['channel'], 'all');

      files.web = true;
      api.on('GET /vendor/reports/payment-methods', 'a,b\r\n');
      await openExport(tester);
      await tester.tap(find.byKey(const Key('reports-export-payment-methods')));
      await tester.pumpAndSettle();
      expect(files.downloaded.single.$2, 'text/csv');
    });

    apiTest('too large: the sheet says so and stays open', (tester, api) async {
      final files = Files()..install();
      seedHome(api);
      api.fail('GET /vendor/reports/products', 413, {
        'error': 'export_too_large',
        'maxRows': 50000,
      });
      final host = await pumpHome(tester, api);
      await openExport(tester);
      await tester.tap(find.byKey(const Key('reports-export-products')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reports-export-too-large')), findsOneWidget);
      expect(
        find.text(host.tr('vendor.reports.exportTooLarge')),
        findsOneWidget,
      );
      expect(files.shared, isEmpty);
    });

    apiTest('PDF not available (503): its own message', (tester, api) async {
      Files().install();
      seedHome(api);
      final host = await pumpHome(tester, api);
      api.onCall('GET /vendor/reports/summary', (r) {
        final q = Uri.splitQueryString(r.query);
        if (q['format'] == 'pdf') {
          return const RawResponse(503, '{"error":"pdf_unavailable"}');
        }
        return ownerSummary();
      });
      await openExport(tester);
      await tester.tap(find.byKey(const Key('reports-export-pdf')));
      await tester.pumpAndSettle();
      expect(
        host.snack(host.tr('vendor.reports.pdfUnavailable')),
        findsOneWidget,
      );
    });

    apiTest('too many downloads (429): wait n minutes', (tester, api) async {
      Files().install();
      seedHome(api);
      api.fail('GET /vendor/reports/sales', 429, {
        'error': 'rate_limited',
        'retryAfterSeconds': 75,
      });
      final host = await pumpHome(tester, api);
      await openExport(tester);
      await tester.tap(find.byKey(const Key('reports-export-sales')));
      await tester.pumpAndSettle();
      expect(
        host.snack("You've downloaded too often. Try again in 2 minute(s)."),
        findsOneWidget,
      );
    });

    apiTest('products CSV passes the search on screen', (tester, api) async {
      final files = Files()..install();
      api.onCall('GET /vendor/reports/products', (r) {
        if (Uri.splitQueryString(r.query)['format'] == 'csv') return 'a\r\n';
        return {
          ...head(),
          'sort': 'revenue',
          'rows': [
            {
              'productId': 'p1',
              'variant': null,
              'name': 'Whey',
              'removed': false,
              'unitsSold': 1,
              'appUnits': 0,
              'walkInUnits': 1,
              'netRevenueTzs': 45000,
              'lastSoldAt': null,
              'stock': 3,
              'daysOfCover': 90,
              'coverState': 'ok',
              'noSalesInPeriod': false,
            },
          ],
          'totals': {'unitsSold': 1, 'netRevenueTzs': 45000},
          'slowCount': 0,
          'nextCursor': null,
        };
      });
      await pumpSection(tester, api, ReportSection.products);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('reports-products-search')),
          matching: find.byType(EditableText),
        ),
        'whey',
      );
      await tester.pump();
      await tapVisible(tester, find.byKey(const Key('reports-section-export')));
      await tester.tap(find.byKey(const Key('reports-export-products')));
      await tester.pumpAndSettle();
      final csv = api
          .where('GET', '/vendor/reports/products')
          .lastWhere((r) => queryOf(r)['format'] == 'csv');
      expect(queryOf(csv)['q'], 'whey');
      expect(files.shared, hasLength(1));
    });

    apiTest('section page: Download offers this section and the PDF', (
      tester,
      api,
    ) async {
      Files().install();
      api.on('GET /vendor/reports/payment-methods', {
        ...head(),
        'byYou': [],
        'viaFitFlex': [],
      });
      await pumpSection(tester, api, ReportSection.methods);
      await tapVisible(tester, find.byKey(const Key('reports-section-export')));
      expect(
        find.byKey(const Key('reports-export-payment-methods')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reports-export-sales')), findsNothing);
      expect(find.byKey(const Key('reports-export-pdf')), findsOneWidget);
    });
  });

  group('Swahili', () {
    apiTest('tab, segments, pills, figures and the 12-hour clock', (
      tester,
      api,
    ) async {
      seedHome(api);
      final host = await pumpHome(tester, api, lang: 'sw');
      expect(find.text('Ripoti'), findsWidgets);
      expect(find.text('Malipo yako'), findsOneWidget);
      expect(find.text('Mwezi huu'), findsOneWidget);
      expect(find.text('Imesasishwa 2:05 mchana'), findsOneWidget);
      expect(find.text('Mauzo 12 · bidhaa 17'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('reports-header-line'))).data,
        contains('(hadi sasa) · Mauzo yote'),
      );
      await openExport(tester);
      expect(find.text('Upakuaji unatumia Kiswahili.'), findsOneWidget);
      expect(find.text(host.tr('vendor.reports.exportPdf')), findsOneWidget);
    });

    apiTest('375 px, 200% text, Swahili: nothing overflows', (
      tester,
      api,
    ) async {
      await loadAppFonts();
      seedHome(api);
      final errors = await captureFlutterErrors(() async {
        await pumpPage(
          tester,
          api,
          const VendorHomePage(open: 'reports'),
          user: owner,
          lang: 'sw',
          textScale: 2.0,
          size: const Size(375, 4000),
          extraRoutes: reportRoutes,
        );
      });
      expect(
        errors.where((e) => e.contains('overflowed')),
        isEmpty,
        reason: errors.join('\n'),
      );
    });
  });
}
