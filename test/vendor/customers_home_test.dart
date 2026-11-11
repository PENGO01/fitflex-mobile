// Vendor tools · S4 on the vendor home: gating (flag + permissions), the
// Customers tab and its segments, the Owed view, open=customers&view=owed,
// sales-only / customers-only staff, the staff-form hint, the notification
// links, nothing about customers kept on the device, and EN/SW coverage.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/customers/customer_form_page.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';

import 'package:fitflexmobile/screens/vendor/customers/customers_widgets.dart';

import '../support/recording_api.dart';
import 'customers_support.dart';
import 'stock_support.dart';

Future<PageHost> pumpHome(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> user = ownerUser,
  String? open,
  String? view,
  String lang = 'en',
  Size size = const Size(400, 900),
}) => pumpPage(
  tester,
  api,
  VendorHomePage(open: open, view: view),
  user: user,
  lang: lang,
  size: size,
  extraRoutes: customerRoutes,
);

void seedHome(RecordingApi api, {Map<String, dynamic> tools = customersOn}) {
  seedVendorHome(api, products: [stockProduct('p1', 'Whey')], tools: tools);
  api.on('GET /vendor/sales', {
    'sales': [],
    'nextCursor': null,
    'summary': {'count': 0, 'totalTzs': 0, 'byMethod': []},
  });
  seedCustomers(api);
}

void main() {
  setUpAll(loadAppFonts);

  apiTest('flag off: tab reads Messages, no segments, no customer calls', (
    tester,
    api,
  ) async {
    seedHome(api, tools: customersOff);
    final host = await pumpHome(tester, api, open: 'enquiries');
    expect(find.byKey(const Key('vendor-nav-enquiries')), findsOneWidget);
    expect(find.byKey(const Key('vendor-nav-customers')), findsNothing);
    expect(find.byKey(const Key('customers-segments')), findsNothing);
    expect(find.text(host.tr('vendor.noEnquiries')), findsOneWidget);
    expect(api.sent('GET', '/vendor/customers'), isFalse);
    expect(api.sent('GET', '/vendor/receivables/aging'), isFalse);
  });

  apiTest('options failing: same as off (fail closed)', (tester, api) async {
    seedHome(api);
    api.fail('GET /vendor/tools/options', 500);
    await pumpHome(tester, api, open: 'customers');
    expect(find.byKey(const Key('vendor-nav-customers')), findsNothing);
    expect(find.byKey(const Key('customers-segments')), findsNothing);
  });

  apiTest('flag on: Customers tab with Customers | Owed | Messages', (
    tester,
    api,
  ) async {
    seedHome(api);
    final host = await pumpHome(tester, api, open: 'customers');
    expect(find.byKey(const Key('vendor-nav-customers')), findsOneWidget);
    expect(find.text(host.tr('vendor.customers.tab')), findsWidgets);
    expect(find.byKey(const Key('customers-segments')), findsOneWidget);
    expect(find.byKey(const Key('customers-row-cus_1')), findsOneWidget);
    expect(find.text('Juma Mussa'), findsOneWidget);
    expect(find.text('TSh 50,000'), findsOneWidget);
    expect(find.byKey(const Key('vendor-customers-add')), findsOneWidget);

    await tester.tap(find.text(host.tr('vendor.customers.seg.messages')));
    await tester.pumpAndSettle();
    expect(find.text(host.tr('vendor.noEnquiries')), findsOneWidget);
    expect(find.byKey(const Key('vendor-customers-add')), findsNothing);
  });

  apiTest('open=enquiries with the flag on lands on Messages', (
    tester,
    api,
  ) async {
    seedHome(api);
    final host = await pumpHome(tester, api, open: 'enquiries');
    expect(find.byKey(const Key('customers-segments')), findsOneWidget);
    expect(find.text(host.tr('vendor.noEnquiries')), findsOneWidget);
  });

  apiTest('open=customers&view=owed: totals, buckets, rows; bucket filters', (
    tester,
    api,
  ) async {
    seedHome(api);
    final host = await pumpHome(
      tester,
      api,
      open: 'customers',
      view: 'owed',
      size: const Size(400, 1600),
    );
    expect(find.byKey(const Key('owed-summary')), findsOneWidget);
    expect(find.byKey(const Key('owed-row-cus_1')), findsOneWidget);
    expect(
      find.text(agingTileLabel('d1_30', host.tr('vendor.aging.d1_30'))),
      findsOneWidget,
    );
    api.clear();
    await tapVisible(tester, find.byKey(const Key('owed-bucket-d1_30')));
    final req = api.only('GET', '/vendor/receivables/aging');
    expect(req.query, contains('bucket=d1_30'));
  });

  apiTest('filters and search go to the server', (tester, api) async {
    seedHome(api);
    await pumpHome(tester, api, open: 'customers');
    api.clear();
    await tapVisible(tester, find.byKey(const Key('customers-filter-owes')));
    expect(api.only('GET', '/vendor/customers').query, contains('filter=owes'));
    api.clear();
    await tester.enterText(find.byKey(const Key('customers-search')), 'Jum');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(api.only('GET', '/vendor/customers').query, contains('q=Jum'));
  });

  apiTest('forgotten app customer reads "Deleted member"', (tester, api) async {
    seedHome(api);
    seedCustomers(
      api,
      rows: [
        customerRow('cus_9', null, source: 'marketplace', forgotten: true),
      ],
    );
    await pumpHome(tester, api, open: 'customers');
    expect(find.text('Deleted member'), findsOneWidget);
  });

  apiTest('sales-only staff: no Customers tab', (tester, api) async {
    seedHome(api);
    await pumpHome(tester, api, user: staffUser(['sales']));
    expect(find.byKey(const Key('vendor-nav-customers')), findsNothing);
    expect(api.sent('GET', '/vendor/customers'), isFalse);
  });

  apiTest('customers-only staff: Customers, no Sales tab (AC-4)', (
    tester,
    api,
  ) async {
    seedHome(api);
    await pumpHome(
      tester,
      api,
      user: staffUser(['customers'], role: 'support'),
    );
    expect(find.byKey(const Key('customers-segments')), findsOneWidget);
    expect(find.byKey(const Key('vendor-nav-sales')), findsNothing);
  });

  apiTest('Sales tab: "Owed to you" card opens the Owed view', (
    tester,
    api,
  ) async {
    seedHome(api);
    await pumpHome(tester, api, open: 'sales');
    expect(find.byKey(const Key('sales-owed-card')), findsOneWidget);
    expect(find.text('Owed to you: TSh 50,000 · 1 overdue'), findsOneWidget);
    expect(find.byKey(const Key('sales-filter-credit')), findsOneWidget);
    api.clear();
    await tapVisible(tester, find.byKey(const Key('sales-filter-credit')));
    expect(
      api.where('GET', '/vendor/sales').last.query,
      contains('kind=credit'),
    );
  });

  apiTest('Sales tab for sales-only staff: no owed card, no aging call', (
    tester,
    api,
  ) async {
    seedHome(api);
    await pumpHome(tester, api, user: staffUser(['sales']), open: 'sales');
    expect(find.byKey(const Key('sales-owed-card')), findsNothing);
    expect(api.sent('GET', '/vendor/receivables/aging'), isFalse);
  });

  apiTest('nothing about customers is kept on the device (A-02)', (
    tester,
    api,
  ) async {
    seedHome(api);
    await pumpHome(tester, api, open: 'customers', view: 'owed');
    await tester.tap(find.text('Customers').first);
    await tester.pumpAndSettle();
    final stored = await deviceStorage();
    expect(stored, isNot(contains('Juma')));
    expect(stored, isNot(contains('cus_1')));
    expect(stored, isNot(contains('+255')));
  });

  apiTest('a customer route with the flag off goes home, no message', (
    tester,
    api,
  ) async {
    seedHome(api, tools: customersOff);
    await pumpPage(
      tester,
      api,
      const CustomerFormPage(),
      extraRoutes: customerRoutes,
    );
    expect(find.textContaining('ROUTE-VENDOR-HOME'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  apiTest('a customer route without `customers`: no-access message', (
    tester,
    api,
  ) async {
    seedHome(api);
    final host = await pumpPage(
      tester,
      api,
      const CustomerFormPage(),
      user: staffUser(['sales']),
      extraRoutes: customerRoutes,
    );
    expect(find.textContaining('ROUTE-VENDOR-HOME'), findsOneWidget);
    expect(find.text(host.tr('vendor.customers.noAccess')), findsOneWidget);
  });

  test('notification links (§9)', () {
    expect(
      partnerRouteFor(side: 'vendor', type: 'vendor_customers_overdue'),
      '/vendor/home?open=customers&view=owed',
    );
    expect(
      partnerRouteFor(
        side: 'vendor',
        type: 'vendor_customer_payment_voided',
        customerId: 'cus_1',
      ),
      '/vendor/customers/cus_1',
    );
    expect(
      partnerRouteFor(
        side: 'vendor',
        type: 'vendor_customer_payment_voided',
        customerId: '../x',
      ),
      '/vendor/home?open=customers',
    );
  });

  test('every S4 string has English and a Swahili draft', () {
    final en = FFLocale.keysOf('en');
    final sw = FFLocale.keysOf('sw');
    const prefixes = [
      'vendor.customers.',
      'vendor.pay.',
      'vendor.owed.',
      'vendor.aging.',
      'vendor.statement.',
      'vendor.pos.customer.',
      'vendor.pos.credit.',
      'vendor.receipt.',
    ];
    final keys = en.where((k) => prefixes.any(k.startsWith)).toList();
    expect(keys.length, greaterThan(150));
    for (final k in keys) {
      expect(sw, contains(k), reason: k);
      // Same on purpose: amounts, day ranges and "A–Z".
      // Sale extras: "PDF" is "PDF" in both languages (spec §7).
      if (const {
        'vendor.customers.sort.name',
        'vendor.receipt.asPdf',
      }.contains(k)) {
        continue;
      }
      expect(
        FFLocale.textOf('sw', k),
        isNot(FFLocale.textOf('en', k)),
        reason: k,
      );
    }
  });
}
