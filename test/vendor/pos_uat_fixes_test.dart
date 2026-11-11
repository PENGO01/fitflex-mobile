// Vendor tools · S3 UAT fixes (2026-10-20): open=sales waits for the tab
// list (D1), offline receipts keep the business header (D2), money never
// cut off (D3), selling off while suspended (D4), a 409 clears the stale
// hint and focuses the stepper (D5), screen-reader labels (D6), plurals and
// wording (D7), queued sales reachable without a Business tab (D9), and the
// client-side change cap.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/screens/vendor/sales/pos_page.dart';
import 'package:fitflexmobile/screens/vendor/sales/receipt_page.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/widgets/invitations.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';
import 'walkin_support.dart';

const owner = {'id': 'v1', 'userType': 'vendor', 'displayName': 'Asha'};

Map<String, dynamic> queuedEntry(String ref) => {
  'body': {
    'clientRef': ref,
    'soldAt': '2026-10-19T08:00:00.000Z',
    'lines': [
      {'productId': 'p1', 'qty': 1},
    ],
    'payments': [
      {'method': 'cash', 'amountTzs': 45000},
    ],
  },
  'display': {
    'lines': [
      {'name': 'Whey', 'listPriceTzs': 45000},
    ],
  },
  'queuedAt': '2026-10-19T08:00:00.000Z',
  'state': 'waiting',
};

void seedSalesList(RecordingApi api, {int total = 45000}) =>
    api.on('GET /vendor/sales', {
      'sales': [
        {
          'id': 'sal_1',
          'number': 'R-000001',
          'soldAt': '2026-10-19T08:00:00.000Z',
          'recordedAt': '2026-10-19T09:00:00.000Z',
          'status': 'completed',
          'totalTzs': total,
          'itemCount': 1,
          'methods': ['cash'],
          'createdBy': {'id': 'v1', 'name': 'Asha'},
          'lateRecorded': true,
        },
      ],
      'nextCursor': null,
      'summary': {
        'count': 1,
        'totalTzs': total,
        'voidedCount': 0,
        'byMethod': [
          {'method': 'cash', 'amountTzs': total},
        ],
      },
    });

void main() {
  setUpAll(loadAppFonts);

  group('D1 open=sales', () {
    apiTest('waits for the tools, and beats the unfinished-profile redirect', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [], tools: walkInOn);
      api.on('GET /vendor/profile', {
        'businessName': 'Dar Gear',
        'status': 'draft',
      });
      seedSalesList(api);
      final hold = api.hold('GET /vendor/tools/options');
      await pumpPage(
        tester,
        api,
        const VendorHomePage(open: 'sales'),
        user: owner,
        size: const Size(400, 1200),
        extraRoutes: salesRoutes,
        settle: false,
      );
      await tester.pump();
      hold.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vendor-sales-tab')), findsOneWidget);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      // Products, Orders, Sales, …: Sales is the third destination.
      expect(bar.selectedIndex, 2);
    });

    apiTest('without open=, an unfinished profile still opens on Business', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [], tools: walkInOn);
      api.on('GET /vendor/profile', {
        'businessName': 'Dar Gear',
        'status': 'draft',
      });
      await pumpVendorHome(tester, api, user: owner);
      expect(find.byKey(const Key('vendor-edit-profile')), findsOneWidget);
    });
  });

  group('D2 offline receipts keep the business header', () {
    apiTest('POS opened offline uses the kept header in the queued sale', (
      tester,
      api,
    ) async {
      SharedPreferences.setMockInitialValues({
        'vendor_pos_products.v1': jsonEncode({
          'cachedAt': '2026-10-19T08:00:00.000Z',
          'products': [posProduct('p1', 'Whey')..remove('costTzs')],
        }),
        'vendor_pos_business.v1': jsonEncode({
          'businessName': 'Dar Gear',
          'contactNumber': '+255700000001',
          'address': 'Masaki',
        }),
      });
      api.on('GET /vendor/tools/options', walkInOn);
      api.onCall(
        'GET /vendor/products',
        (_) => throw http.ClientException('offline'),
      );
      api.onCall(
        'GET /vendor/profile',
        (_) => throw http.ClientException('offline'),
      );
      api.onCall(
        'POST /vendor/sales',
        (_) => throw http.ClientException('offline'),
      );
      await pumpPage(
        tester,
        api,
        const PosPage(),
        user: owner,
        size: const Size(400, 900),
        extraRoutes: salesRoutes,
      );
      expect(find.byKey(const Key('sales-offline-banner')), findsOneWidget);
      await tester.tap(find.byKey(const Key('pos-product-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-charge')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      final prefs = await SharedPreferences.getInstance();
      final queue =
          jsonDecode(prefs.getString('vendor_sale_queue.v1.v1')!) as List;
      final display = (queue.single as Map)['display'] as Map;
      expect(display['business'], 'Dar Gear');
      expect(display['contact'], '+255700000001');
      expect(display['address'], 'Masaki');
    });

    apiTest('queued receipt without a header gets the kept one; spec wording', (
      tester,
      api,
    ) async {
      SharedPreferences.setMockInitialValues({
        'vendor_sale_queue.v1.v1': jsonEncode([queuedEntry('sale_q_00abcdef')]),
        'vendor_pos_business.v1': jsonEncode({'businessName': 'Dar Gear'}),
      });
      api.on('GET /vendor/tools/options', walkInOn);
      api.fail('GET /vendor/profile', 503);
      api.fail('POST /vendor/sales', 503);
      final shared = <String>[];
      final previous = shareReceipt;
      shareReceipt = (text, subject) async => shared.add(text);
      addTearDown(() => shareReceipt = previous);
      await pumpPage(
        tester,
        api,
        const SaleReceiptPage(clientRef: 'sale_q_00abcdef'),
        user: owner,
        size: const Size(400, 1400),
        extraRoutes: salesRoutes,
      );
      expect(find.text('Dar Gear'), findsOneWidget);
      expect(find.text('Payment received by Dar Gear.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sales-receipt-share')));
      await tester.pumpAndSettle();
      // Sale extras #3: Share opens Image / PDF / Share as text.
      await tester.tap(find.byKey(const Key('receipt-share-text')));
      await tester.pumpAndSettle();
      expect(
        shared.single,
        contains('Provisional receipt, number to follow (ref ABCDEF)'),
      );
    });
  });

  apiTest('D3 summary money at 375 is never cut off', (tester, api) async {
    seedVendorHome(api, products: [], tools: walkInOn);
    seedSalesList(api, total: 18450000);
    await pumpPage(
      tester,
      api,
      const VendorHomePage(open: 'sales'),
      user: owner,
      size: const Size(375, 1200),
      extraRoutes: salesRoutes,
    );
    final value = find.descendant(
      of: find.byKey(const Key('sales-summary')),
      matching: find.text('TSh 18,450,000'),
    );
    expect(value, findsWidgets);
    for (final t in tester.widgetList<Text>(value)) {
      expect(t.overflow, isNot(TextOverflow.ellipsis));
    }
  });

  apiTest('D5 after a 409 the old hint goes and focus is on the stepper', (
    tester,
    api,
  ) async {
    seedPos(api, products: [posProduct('p1', 'Whey', stock: 1)]);
    api.fail('POST /vendor/sales', 409, {
      'error': 'insufficient_stock',
      'productId': 'p1',
      'variant': null,
      'available': 0,
    });
    await pumpPage(
      tester,
      api,
      const PosPage(),
      user: owner,
      size: const Size(400, 900),
      extraRoutes: salesRoutes,
    );
    await tester.tap(find.byKey(const Key('pos-product-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-charge')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('pos-complete')));
    await tester.pumpAndSettle();
    expect(
      find.text('Only 0 of Whey left. Lower the quantity.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('pos-only-left-p1\u0000')), findsNothing);
    final dec = tester.widget<IconButton>(
      find.byKey(const Key('pos-dec-p1\u0000')),
    );
    expect(dec.focusNode?.hasFocus, isTrue);
  });

  group('D6 screen readers', () {
    apiTest(
      'out-of-stock rows are one disabled node with name, price and stock',
      (tester, api) async {
        final handle = tester.ensureSemantics();
        seedPos(api);
        await pumpPage(
          tester,
          api,
          const PosPage(),
          user: owner,
          size: const Size(400, 900),
          extraRoutes: salesRoutes,
        );
        final mat = tester.getSemantics(
          find.byKey(const Key('pos-product-p2')),
        );
        expect(mat.label, 'Add Mat to the sale, TSh 10,000, Out of stock');
        expect(mat.flagsCollection.isEnabled, isNot(true));
        final whey = tester.getSemantics(
          find.byKey(const Key('pos-product-p1')),
        );
        expect(whey.label, 'Add Whey to the sale, TSh 45,000, 2 left');
        handle.dispose();
      },
    );

    apiTest('a history row says "Recorded offline"', (tester, api) async {
      final handle = tester.ensureSemantics();
      seedVendorHome(api, products: [], tools: walkInOn);
      seedSalesList(api);
      await pumpPage(
        tester,
        api,
        const VendorHomePage(open: 'sales'),
        user: owner,
        size: const Size(400, 1200),
        extraRoutes: salesRoutes,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Receipt R-000001, .*Recorded offline$'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('D7 wording', () {
    apiTest('one sale waiting: singular', (tester, api) async {
      SharedPreferences.setMockInitialValues({
        'vendor_sale_queue.v1.v1': jsonEncode([queuedEntry('sale_q_00abcdef')]),
      });
      seedVendorHome(api, products: [], tools: walkInOn);
      seedSalesList(api);
      api.fail('POST /vendor/sales', 503);
      await pumpPage(
        tester,
        api,
        const VendorHomePage(open: 'sales'),
        user: owner,
        size: const Size(400, 1200),
        extraRoutes: salesRoutes,
      );
      expect(find.text('1 sale waiting to sync'), findsOneWidget);
    });

    apiTest('after a 5xx, Save and sync later says it will sync', (
      tester,
      api,
    ) async {
      seedPos(api);
      api.fail('POST /vendor/sales', 500);
      final host = await pumpPage(
        tester,
        api,
        const PosPage(),
        user: owner,
        size: const Size(400, 900),
        extraRoutes: salesRoutes,
      );
      await tester.tap(find.byKey(const Key('pos-product-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-charge')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      await tapVisible(tester, find.byKey(const Key('pos-sync-later')));
      await tester.pumpAndSettle();
      expect(find.text(host.tr('vendor.pos.savedLater')), findsOneWidget);
      expect(find.text(host.tr('vendor.pos.savedOffline')), findsNothing);
    });

    apiTest('history offline: a sales-specific message', (tester, api) async {
      seedVendorHome(api, products: [], tools: walkInOn);
      api.onCall(
        'GET /vendor/sales',
        (_) => throw http.ClientException('offline'),
      );
      final host = await pumpPage(
        tester,
        api,
        const VendorHomePage(open: 'sales'),
        user: owner,
        size: const Size(400, 1200),
        extraRoutes: salesRoutes,
      );
      expect(find.text(host.tr('vendor.sales.offline')), findsOneWidget);
    });

    apiTest('Edit sale draft does not say "unfinished sale was kept"', (
      tester,
      api,
    ) async {
      SharedPreferences.setMockInitialValues({
        'vendor_pos_draft.v1.v1': jsonEncode({
          'lines': [
            {
              'productId': 'p1',
              'name': 'Whey',
              'listPriceTzs': 45000,
              'qty': 1,
              'discountTzs': 0,
            },
          ],
          'soldAt': '2026-10-19T08:00:00.000Z',
          'keepSoldAt': true,
          'replacesClientRef': 'sale_old_000001',
        }),
      });
      seedPos(api);
      final host = await pumpPage(
        tester,
        api,
        const PosPage(),
        user: owner,
        size: const Size(400, 900),
        extraRoutes: salesRoutes,
      );
      expect(find.text(host.tr('vendor.pos.draftKept')), findsNothing);
      expect(find.text('Charge TSh 45,000'), findsOneWidget);
    });

    apiTest('vendor invite sheet speaks of shop staff, not gym staff', (
      tester,
      api,
    ) async {
      await pumpPage(
        tester,
        api,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openInvitePersonSheet(
              context,
              gymId: 'v1',
              role: 'staff',
              orgType: 'vendor',
              vendorSales: true,
            ),
            child: const Text('open'),
          ),
        ),
        user: owner,
        size: const Size(400, 1200),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Invite: shop staff'), findsOneWidget);
      expect(find.textContaining('Gym Staff'), findsNothing);
      expect(
        find.byKey(const Key('invite-vendor-permission-sales')),
        findsOneWidget,
      );
    });
  });

  apiTest('D9 sales-only staff, feature off, sales queued: the entry shows', (
    tester,
    api,
  ) async {
    SharedPreferences.setMockInitialValues({
      'vendor_sale_queue.v1.s1': jsonEncode([queuedEntry('sale_q_00abcdef')]),
    });
    seedVendorHome(api, products: [], tools: walkInOff);
    api.fail('POST /vendor/sales', 404, {'error': 'feature_disabled'});
    await pumpPage(
      tester,
      api,
      const VendorHomePage(),
      user: {
        'id': 's1',
        'userType': 'vendor_staff',
        'vendorId': 'v1',
        'vendorPermissions': ['sales'],
      },
      size: const Size(400, 900),
      extraRoutes: salesRoutes,
    );
    expect(find.byKey(const Key('vendor-sales-waiting-tile')), findsOneWidget);
    await tester.tap(find.byKey(const Key('vendor-sales-waiting-tile')));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE-SYNC'), findsOneWidget);
  });

  apiTest('change cap: more than total + 1,000,000 is stopped before sending', (
    tester,
    api,
  ) async {
    seedPos(api);
    await pumpPage(
      tester,
      api,
      const PosPage(),
      user: owner,
      size: const Size(400, 900),
      extraRoutes: salesRoutes,
    );
    await tester.tap(find.byKey(const Key('pos-product-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-charge')));
    await tester.pumpAndSettle();
    await typeInto(tester, find.byKey(const Key('pos-amount-0')), '2000000');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pos-change-too-large')), findsOneWidget);
    expect(
      find.text(
        "The change can't be more than TSh 1,045,000. Check the amount received.",
      ),
      findsOneWidget,
    );
    expect(isEnabled(tester, find.byKey(const Key('pos-complete'))), isFalse);
    await typeInto(tester, find.byKey(const Key('pos-amount-0')), '1000000');
    await tester.pumpAndSettle();
    expect(isEnabled(tester, find.byKey(const Key('pos-complete'))), isTrue);
  });
}
