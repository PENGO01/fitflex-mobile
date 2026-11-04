// Vendor tools · S9: Owed to suppliers (spec §4.8) and the Purchases hub
// (§4.1) — server totals shown as sent, bucket tiles as filters, rows,
// empty; the hub's owed card, Receive stock, recent deliveries and "See all"
// with its filters.
import 'package:fitflexmobile/screens/vendor/purchases/payables_page.dart';
import 'package:fitflexmobile/screens/vendor/purchases/purchases_hub.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_api.dart';
import 'purchases_support.dart';

Map<String, dynamic> listJson() => {
  'purchases': [
    {
      'id': 'vpo_0000000000000012',
      'number': 'GRN-000012',
      'status': 'received',
      'receivedOn': '2026-11-03',
      'supplier': {'id': 'vsp_0000000000000001', 'name': 'Juma Supplies'},
      'totalTzs': 200000,
      'paidTzs': 50000,
      'balanceTzs': 150000,
      'overdueTzs': 0,
      'paymentState': 'part_paid',
    },
    {
      'id': 'vpo_0000000000000011',
      'number': 'GRN-000011',
      'status': 'voided',
      'receivedOn': '2026-11-01',
      'supplier': null,
      'totalTzs': 9000,
      'paidTzs': 9000,
      'balanceTzs': 0,
      'overdueTzs': 0,
      'paymentState': 'paid',
    },
  ],
  'nextCursor': null,
  'summary': {
    'count': 1,
    'totalTzs': 200000,
    'paidTzs': 50000,
    'balanceTzs': 150000,
    'units': 21,
  },
};

void main() {
  setUpAll(loadAppFonts);

  apiTest('payables: totals, rows most overdue first; buckets filter', (
    tester,
    api,
  ) async {
    api.on('GET /vendor/tools/options', purchasesOnTools);
    api.on('GET /vendor/payables/aging', agingJson());
    final host = await pumpPage(
      tester,
      api,
      const PayablesPage(),
      user: ownerUser,
      size: const Size(400, 1600),
      extraRoutes: purchaseRoutes,
    );
    expect(find.text('TSh 150,000'), findsWidgets);
    expect(find.text(host.tr('vendor.payables.dueSoon')), findsOneWidget);
    expect(find.text('TSh 30,000'), findsOneWidget);
    expect(find.text('14 days overdue'), findsOneWidget);
    expect(find.text(host.tr('vendor.purchases.moneyNotice')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('payables-bucket-d1_30')));
    expect(api.requests.last.query, contains('bucket=d1_30'));
    await tapVisible(tester, find.byKey(const Key('payables-all')));
    expect(api.requests.last.query, isNot(contains('bucket')));
    await tapVisible(
      tester,
      find.byKey(const Key('payables-row-vsp_0000000000000001')),
    );
    expect(find.text('ROUTE-SUPPLIER vsp_0000000000000001'), findsOneWidget);
  });

  apiTest('payables: empty', (tester, api) async {
    api.on('GET /vendor/tools/options', purchasesOnTools);
    api.on('GET /vendor/payables/aging', agingJson(owed: 0, overdue: 0));
    final host = await pumpPage(
      tester,
      api,
      const PayablesPage(),
      user: ownerUser,
      size: const Size(400, 1400),
      extraRoutes: purchaseRoutes,
    );
    expect(find.text(host.tr('vendor.payables.empty')), findsOneWidget);
  });

  apiTest('payables: tool off goes home', (tester, api) async {
    api.on('GET /vendor/tools/options', purchasesOffTools);
    await pumpPage(
      tester,
      api,
      const PayablesPage(),
      user: ownerUser,
      extraRoutes: purchaseRoutes,
    );
    expect(find.textContaining('ROUTE-VENDOR-HOME'), findsOneWidget);
    expect(api.sent('GET', '/vendor/payables/aging'), isFalse);
  });

  apiTest('hub: owed card, Receive stock, recent rows with badges', (
    tester,
    api,
  ) async {
    api.on('GET /vendor/payables/aging', agingJson());
    api.on('GET /vendor/purchases', listJson());
    final host = await pumpPage(
      tester,
      api,
      const PurchasesHubView(),
      user: ownerUser,
      size: const Size(400, 1400),
      extraRoutes: purchaseRoutes,
    );
    expect(find.byKey(const Key('purchases-owed')), findsOneWidget);
    expect(find.text('Overdue TSh 20,000'), findsOneWidget);
    expect(find.text('GRN-000012'), findsOneWidget);
    expect(
      find.text(host.tr('vendor.purchases.state.part_paid')),
      findsOneWidget,
    );
    expect(find.text(host.tr('vendor.purchases.state.voided')), findsOneWidget);
    expect(find.text(host.tr('vendor.purchases.noSupplier')), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'GRN-000012, Juma Supplies, 3 Nov 2026, TSh 200,000, Part paid',
      ),
      findsOneWidget,
    );
    await tapVisible(tester, find.byKey(const Key('purchases-receive')));
    expect(find.text('ROUTE-RECEIVE '), findsOneWidget);
  });

  apiTest('hub: nothing yet; a failing owed card keeps the list', (
    tester,
    api,
  ) async {
    api.fail('GET /vendor/payables/aging', 500);
    api.on('GET /vendor/purchases', {'purchases': [], 'nextCursor': null});
    final host = await pumpPage(
      tester,
      api,
      const PurchasesHubView(),
      user: ownerUser,
      size: const Size(400, 1200),
      extraRoutes: purchaseRoutes,
    );
    expect(find.byKey(const Key('purchases-owed-error')), findsOneWidget);
    expect(find.text(host.tr('vendor.purchases.empty')), findsOneWidget);
  });

  apiTest('See all: filters as sent', (tester, api) async {
    api.on('GET /vendor/tools/options', purchasesOnTools);
    api.on('GET /vendor/purchases', listJson());
    await pumpPage(
      tester,
      api,
      const PurchasesListPage(),
      user: ownerUser,
      size: const Size(400, 1200),
      extraRoutes: purchaseRoutes,
    );
    await tapVisible(tester, find.byKey(const Key('purchases-filter-overdue')));
    expect(
      api.requests.last.query,
      allOf(contains('status=received'), contains('payment=overdue')),
    );
    await tapVisible(tester, find.byKey(const Key('purchases-filter-voided')));
    expect(api.requests.last.query, 'status=voided');
  });
}
