// Vendor tools · S9 on existing screens: tab 0's Products | Purchases switch
// (flag off, failing options, owner, purchases-only staff, products-only
// staff, open=products&view=purchases), the staff form's `purchases`
// permission, stock history rows (stock_in / stock_in_void labelled, the GRN
// linked or plain text), S6 "Paid to suppliers" and the adjust-sheet hint.
import 'package:fitflexmobile/screens/vendor/reports/report_sections.dart';
import 'package:fitflexmobile/screens/vendor/stock/adjust_stock_sheet.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_history_page.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_api.dart';
import '../stock_support.dart';
import 'purchases_support.dart';

void seedHome(RecordingApi api, Map<String, dynamic> tools) {
  seedVendorHome(api, products: [stockProduct('p1', 'Whey')], tools: tools);
  api.on('GET /vendor/payables/aging', agingJson());
  api.on('GET /vendor/purchases', {'purchases': [], 'nextCursor': null});
}

Future<PageHost> pumpHome(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> user = ownerUser,
  String? open,
  String? view,
}) => pumpPage(
  tester,
  api,
  VendorHomePage(open: open, view: view),
  user: user,
  size: const Size(400, 900),
  extraRoutes: purchaseRoutes,
);

const _path = '/vendor/products/p1/stock-movements';

Map<String, dynamic> stockInRow(String id, String reason, int delta) => {
  'id': id,
  'productId': 'p1',
  'variant': null,
  'reason': reason,
  'kind': reason,
  'delta': delta,
  'stockBefore': 3,
  'stockAfter': 3 + delta,
  'note': 'GRN-000012',
  'actor': {'id': 'v1', 'name': 'Asha'},
  'document': {
    'type': 'purchase',
    'id': 'vpo_0000000000000012',
    'number': 'GRN-000012',
  },
  'createdAt': '2026-11-03T07:05:00Z',
};

Future<PageHost> pumpHistory(
  WidgetTester tester,
  RecordingApi api,
  Map<String, dynamic> tools, {
  Map<String, dynamic> user = ownerUser,
}) {
  api.on('GET /vendor/products', [stockProduct('p1', 'Whey', stock: 13)]);
  api.on('GET /vendor/stock/low', []);
  api.on('GET /vendor/tools/options', tools);
  api.on('GET $_path', {
    'productId': 'p1',
    'variant': null,
    'openingStock': 3,
    'closingStock': 3,
    'rows': [
      stockInRow('m2', 'stock_in_void', -10),
      stockInRow('m1', 'stock_in', 10),
    ],
    'nextCursor': null,
  });
  return pumpPage(
    tester,
    api,
    const StockHistoryPage(productId: 'p1'),
    user: user,
    size: const Size(400, 1200),
    extraRoutes: purchaseRoutes,
  );
}

void main() {
  setUpAll(loadAppFonts);

  group('tab 0', () {
    apiTest('AC-1 flag off: no Purchases switch, no S9 calls', (
      tester,
      api,
    ) async {
      seedHome(api, purchasesOffTools);
      await pumpHome(tester, api);
      expect(find.byKey(const Key('vendor-products-segment')), findsNothing);
      expect(find.byKey(const Key('purchases-receive')), findsNothing);
      expect(api.sent('GET', '/vendor/payables/aging'), isFalse);
    });

    apiTest('options failing: off (fail closed)', (tester, api) async {
      seedHome(api, purchasesOnTools);
      api.fail('GET /vendor/tools/options', 500);
      await pumpHome(tester, api, open: 'products', view: 'purchases');
      expect(find.byKey(const Key('vendor-products-segment')), findsNothing);
      expect(find.byKey(const Key('purchases-hub')), findsNothing);
    });

    apiTest('owner: Products | Purchases; switching shows the hub', (
      tester,
      api,
    ) async {
      seedHome(api, purchasesOnTools);
      final host = await pumpHome(tester, api);
      expect(find.byKey(const Key('vendor-products-segment')), findsOneWidget);
      expect(find.byKey(const Key('vendor-product-p1')), findsOneWidget);
      await tester.tap(find.text(host.tr('vendor.purchases.segPurchases')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('purchases-hub')), findsOneWidget);
      expect(find.byKey(const Key('purchases-receive')), findsOneWidget);
      // No Add product over the Purchases view.
      expect(find.byKey(const Key('vendor-add-product')), findsNothing);
    });

    apiTest('open=products&view=purchases opens the Purchases view', (
      tester,
      api,
    ) async {
      seedHome(api, purchasesOnTools);
      await pumpHome(tester, api, open: 'products', view: 'purchases');
      expect(find.byKey(const Key('purchases-hub')), findsOneWidget);
    });

    apiTest('AC-4 purchases-only staff: tab 0 reads Purchases, no switch', (
      tester,
      api,
    ) async {
      seedHome(api, purchasesOnNoCost);
      final host = await pumpHome(
        tester,
        api,
        user: staffUser(['purchases', 'orders']),
      );
      expect(find.byKey(const Key('vendor-nav-purchases')), findsOneWidget);
      expect(find.text(host.tr('vendor.purchases.tab')), findsWidgets);
      expect(find.byKey(const Key('vendor-nav-products')), findsNothing);
      expect(find.byKey(const Key('vendor-products-segment')), findsNothing);
      expect(find.byKey(const Key('purchases-hub')), findsOneWidget);
      expect(find.byKey(const Key('vendor-add-product')), findsNothing);
    });

    apiTest(
      'contract check: admin staff signed in before the backfill see Purchases (GET /vendor/me)',
      (tester, api) async {
        seedHome(api, purchasesOnTools);
        api.on('GET /vendor/me', {
          'vendorId': 'v1',
          'userType': 'vendor_staff',
          'vendorRole': 'admin',
          'permissions': ['products', 'purchases'],
        });
        final host = await pumpHome(
          tester,
          api,
          user: staffUser(['products'], role: 'admin'),
        );
        expect(
          find.byKey(const Key('vendor-products-segment')),
          findsOneWidget,
        );
        expect(
          host.auth.user?['vendorPermissions'],
          containsAll(['products', 'purchases']),
        );
      },
    );

    apiTest('GET /vendor/me failing keeps the session permissions', (
      tester,
      api,
    ) async {
      seedHome(api, purchasesOnTools);
      api.fail('GET /vendor/me', 404, {'error': 'feature_disabled'});
      final host = await pumpHome(tester, api, user: staffUser(['products']));
      expect(find.byKey(const Key('vendor-products-segment')), findsNothing);
      expect(host.auth.user?['vendorPermissions'], ['products']);
    });

    apiTest('AC-5 products-only staff: no Purchases anywhere', (
      tester,
      api,
    ) async {
      seedHome(api, purchasesOnTools);
      await pumpHome(
        tester,
        api,
        user: staffUser(['products']),
        open: 'products',
        view: 'purchases',
      );
      expect(find.byKey(const Key('vendor-products-segment')), findsNothing);
      expect(find.byKey(const Key('purchases-hub')), findsNothing);
      expect(find.byKey(const Key('vendor-product-p1')), findsOneWidget);
    });
  });

  group('AC-3 staff form', () {
    Future<void> pumpForm(WidgetTester tester, RecordingApi api, bool on) =>
        pumpPage(
          tester,
          api,
          SingleChildScrollView(child: VendorStaffForm(purchasesTool: on)),
          user: ownerUser,
          size: const Size(400, 1600),
        );

    apiTest('purchases listed with its hint while the tool is on', (
      tester,
      api,
    ) async {
      await pumpForm(tester, api, true);
      expect(find.text('Suppliers and stock in'), findsOneWidget);
      expect(
        find.text(
          'Suppliers, receiving stock, cost prices from deliveries and what you owe',
        ),
        findsOneWidget,
      );
    });

    apiTest('not offered while the tool is off', (tester, api) async {
      await pumpForm(tester, api, false);
      expect(find.text('Suppliers and stock in'), findsNothing);
    });
  });

  group('stock history', () {
    apiTest('variant_gone is said in words, never the raw code', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/products', [stockProduct('p1', 'Whey', stock: 13)]);
      api.on('GET /vendor/stock/low', []);
      api.on('GET /vendor/tools/options', purchasesOnTools);
      api.on('GET $_path', {
        'productId': 'p1',
        'variant': null,
        'openingStock': 3,
        'closingStock': 4,
        'rows': [
          {
            ...stockInRow('m3', 'sale_void', 1),
            'note': 'variant_gone',
            'document': {'type': 'sale', 'id': 'sal_1', 'number': 'R-000001'},
          },
        ],
        'nextCursor': null,
      });
      final host = await pumpPage(
        tester,
        api,
        const StockHistoryPage(productId: 'p1'),
        user: ownerUser,
        lang: 'sw',
        size: const Size(400, 1200),
        extraRoutes: purchaseRoutes,
      );
      expect(
        find.text(host.tr('vendor.stock.note.variantGone')),
        findsOneWidget,
      );
      expect(find.text('Chaguo hili halipo tena'), findsOneWidget);
      expect(find.textContaining('variant_gone'), findsNothing);
    });

    apiTest(
      'stock_in / stock_in_void labelled; the GRN links to the purchase',
      (tester, api) async {
        await pumpHistory(tester, api, purchasesOnTools);
        expect(find.text('Received from supplier'), findsOneWidget);
        expect(
          find.text('Delivery voided, out of stock again'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('stock-purchase-m1')), findsOneWidget);
        await tapVisible(tester, find.byKey(const Key('stock-purchase-m1')));
        expect(
          find.text('ROUTE-PURCHASE vpo_0000000000000012'),
          findsOneWidget,
        );
      },
    );

    apiTest('AC-2 flag off: the GRN is plain text', (tester, api) async {
      await pumpHistory(tester, api, purchasesOffTools);
      expect(find.text('Received from supplier'), findsOneWidget);
      expect(find.byKey(const Key('stock-purchase-m1')), findsNothing);
      expect(find.byKey(const Key('stock-purchase-text-m1')), findsOneWidget);
      expect(find.text('Delivery GRN-000012'), findsNWidgets(2));
    });

    apiTest('products without purchases: plain text', (tester, api) async {
      await pumpHistory(
        tester,
        api,
        purchasesOnTools,
        user: staffUser(['products']),
      );
      expect(find.byKey(const Key('stock-purchase-m1')), findsNothing);
      expect(find.byKey(const Key('stock-purchase-text-m1')), findsOneWidget);
    });
  });

  group('reports', () {
    apiTest('AC-30: "Paid to suppliers (by you)" is its own group', (
      tester,
      api,
    ) async {
      await pumpPage(
        tester,
        api,
        const SingleChildScrollView(
          child: MethodsReportBody(
            data: {
              'byYou': [
                {
                  'method': 'cash',
                  'amountTzs': 100000,
                  'count': 3,
                  'sharePct': 100,
                },
              ],
              'viaFitFlex': [],
              'paidBack': [],
              'paidToSuppliers': [
                {'method': 'mpesa', 'amountTzs': 70000, 'count': 1},
              ],
            },
          ),
        ),
        user: ownerUser,
        size: const Size(400, 1200),
        extraRoutes: purchaseRoutes,
      );
      expect(
        find.byKey(const Key('reports-methods-paid-to-suppliers')),
        findsOneWidget,
      );
      expect(find.text('Paid to suppliers (by you)'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('reports-open-payables')));
      expect(find.text('ROUTE-PAYABLES'), findsOneWidget);
    });

    apiTest('absent when the server leaves it out', (tester, api) async {
      await pumpPage(
        tester,
        api,
        const MethodsReportBody(
          data: {'byYou': [], 'viaFitFlex': [], 'paidBack': []},
        ),
        user: ownerUser,
      );
      expect(
        find.byKey(const Key('reports-methods-paid-to-suppliers')),
        findsNothing,
      );
    });
  });

  group('adjust sheet', () {
    Future<void> openSheet(
      WidgetTester tester,
      RecordingApi api,
      Map<String, dynamic> tools,
    ) async {
      api.on('GET /vendor/tools/options', tools);
      api.on('GET /vendor/products', [stockProduct('p1', 'Whey')]);
      await pumpPage(
        tester,
        api,
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                openAdjustStock(context, product: stockProduct('p1', 'Whey')),
            child: const Text('OPEN'),
          ),
        ),
        user: ownerUser,
        size: const Size(400, 1200),
        extraRoutes: purchaseRoutes,
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
    }

    apiTest('purchases on: hint links to Receive stock', (tester, api) async {
      await openSheet(tester, api, purchasesOnTools);
      expect(find.byKey(const Key('adjust-purchases-hint')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('adjust-receive-stock')));
      expect(find.text('ROUTE-RECEIVE '), findsOneWidget);
    });

    apiTest('purchases off: no hint', (tester, api) async {
      await openSheet(tester, api, purchasesOffTools);
      expect(find.byKey(const Key('adjust-purchases-hint')), findsNothing);
    });
  });
}
