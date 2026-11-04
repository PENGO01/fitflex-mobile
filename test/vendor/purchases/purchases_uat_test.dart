// Vendor tools · S9 UAT on RC (fe1e7b8) fixes: M-1 quantity / cost field
// semantics, L-1/L-5 plurals (EN + SW), L-2 last-cost hint without a
// supplier and "Due in N days" on the supplier profile, L-3 who voided a
// payment, L-6 Try again after a dropped connection, L-9 permissions
// refreshed on a tab switch, L-11 purchases-only staff with the tool off,
// instalments numbered from 1 after a payment at receipt, and Swahili
// 12-hour times in stock history.
import 'package:fitflexmobile/screens/vendor/purchases/purchase_detail_page.dart';
import 'package:fitflexmobile/screens/vendor/purchases/purchase_models.dart';
import 'package:fitflexmobile/screens/vendor/purchases/receive_stock_page.dart';
import 'package:fitflexmobile/screens/vendor/purchases/suppliers_pages.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_history_page.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/recording_api.dart';
import '../stock_support.dart';
import 'purchases_support.dart';

final _now = DateTime.utc(2026, 11, 3, 9);
const _pid = 'vpo_0000000000000012';
const _sid = 'vsp_0000000000000001';

String en(String k) => FFLocale.textOf('en', k) ?? k;
String sw(String k) => FFLocale.textOf('sw', k) ?? k;

Future<PageHost> pumpReceive(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
}) => pumpPage(
  tester,
  api,
  ReceiveStockPage(now: () => _now),
  user: ownerUser,
  lang: lang,
  size: const Size(400, 1600),
  extraRoutes: purchaseRoutes,
);

Future<void> addProduct(
  WidgetTester tester,
  String id, {
  String? variant,
}) async {
  await tapVisible(tester, find.byKey(const Key('purchase-add-item')));
  await tester.tap(find.byKey(Key('purchase-pick-$id')));
  await tester.pumpAndSettle();
  if (variant != null) {
    await tester.tap(find.byKey(Key('purchase-pick-variant-$variant')));
    await tester.pumpAndSettle();
  }
}

Future<PageHost> pumpDetail(
  WidgetTester tester,
  RecordingApi api,
  Map<String, dynamic> purchase,
) {
  api.on('GET /vendor/tools/options', purchasesOnTools);
  api.on('GET /vendor/profile', {'businessName': 'Dar Gear'});
  api.on('GET /vendor/purchases/$_pid', {'purchase': purchase});
  return pumpPage(
    tester,
    api,
    PurchaseDetailPage(
      purchaseId: _pid,
      now: () => DateTime.utc(2026, 11, 3, 12),
    ),
    user: ownerUser,
    size: const Size(420, 2200),
    extraRoutes: purchaseRoutes,
  );
}

void main() {
  setUpAll(loadAppFonts);

  group('M-1 semantics', () {
    apiTest('the quantity field is labelled; a prefilled cost is exposed', (
      tester,
      api,
    ) async {
      final handle = tester.ensureSemantics();
      seedReceive(
        api,
        lastCosts: [
          {
            'productId': 'p1',
            'variant': null,
            'unitCostTzs': 9500,
            'receivedOn': '2026-10-20',
            'supplierName': 'Juma Supplies',
            'number': 'GRN-000004',
          },
        ],
      );
      await pumpReceive(tester, api);
      await addProduct(tester, 'p1');
      final qty = tester.getSemantics(
        find.descendant(
          of: find.byKey(const Key('purchase-line-qty-p1-')),
          matching: find.byType(EditableText),
        ),
      );
      expect(qty.label, contains('Quantity received for Whey 1kg'));
      expect(qty.value, '1');
      final cost = tester.getSemantics(
        find.descendant(
          of: find.byKey(const Key('purchase-line-cost-p1-')),
          matching: find.byType(EditableText),
        ),
      );
      expect(cost.label, contains('Unit cost for Whey 1kg'));
      expect(cost.value, '9500');
      handle.dispose();
    });
  });

  group('L-1/L-5 plurals', () {
    test('one variant / item / payment / day, in English and Swahili', () {
      expect(
        en('vendor.purchases.variantCountOne').replaceAll('{n}', '1'),
        '1 variant',
      );
      expect(
        sw('vendor.purchases.variantCountOne').replaceAll('{n}', '1'),
        'Chaguo 1',
      );
      expect(
        sw('vendor.purchases.variantCount').replaceAll('{n}', '3'),
        'Machaguo 3',
      );
      expect(
        en(
          'vendor.purchases.confirmTitleNoSupplierOne',
        ).replaceAll('{units}', '1'),
        'Receive 1 item?',
      );
      expect(
        en('vendor.purchases.voidPaymentsOne'),
        startsWith('The {n} payment recorded on it'),
      );
      expect(
        instalmentStateText(
          en,
          Instalment.fromJson(
            inst(2, '2026-11-02', 10, 0, 'overdue', daysOverdue: 1),
          ),
        ),
        'Overdue 1 day',
      );
      expect(dueText(en, '2026-11-04', '2026-11-03'), 'Due in 1 day');
    });

    apiTest('picker: "1 variant" for a one-variant product', (
      tester,
      api,
    ) async {
      seedReceive(api);
      api.on('GET /vendor/products', [
        {
          'id': 'p9',
          'name': 'Cap',
          'stock': 2,
          'status': 'active',
          'approvalStatus': 'approved',
          'variants': [
            {'name': 'One size', 'stock': 2},
          ],
        },
      ]);
      await pumpReceive(tester, api);
      await tapVisible(tester, find.byKey(const Key('purchase-add-item')));
      expect(find.textContaining('1 variant ·'), findsOneWidget);
      expect(find.textContaining('variants'), findsNothing);
    });

    apiTest('void dialog: "The 1 payment … is voided too"', (
      tester,
      api,
    ) async {
      await pumpDetail(tester, api, purchaseJson());
      await tapVisible(tester, find.byKey(const Key('purchase-void')));
      expect(
        find.textContaining('The 1 payment recorded on it'),
        findsOneWidget,
      );
    });
  });

  group('L-2', () {
    apiTest('a last cost with no supplier says only the cost and date', (
      tester,
      api,
    ) async {
      seedReceive(
        api,
        lastCosts: [
          {
            'productId': 'p1',
            'variant': null,
            'unitCostTzs': 9500,
            'receivedOn': '2026-10-20',
            'supplierName': null,
            'number': 'GRN-000004',
          },
        ],
      );
      await pumpReceive(tester, api);
      await addProduct(tester, 'p1');
      expect(find.text('Last time: TSh 9,500, 20 Oct 2026'), findsOneWidget);
      expect(find.textContaining('from No supplier'), findsNothing);
    });

    apiTest(
      'supplier profile: an open instalment not due yet says "Due in N days"',
      (tester, api) async {
        api.on('GET /vendor/tools/options', purchasesOnTools);
        api.on('GET /vendor/suppliers/$_sid', {
          'supplier': {'id': _sid, 'name': 'Juma Supplies', 'archived': false},
          'totals': {
            'purchasedTzs': 200000,
            'purchaseCount': 1,
            'paidTzs': 50000,
          },
          'owedTzs': 150000,
          'overdueTzs': 0,
          'aging': {'current': 150000},
          'asOf': '2026-11-03',
          'openInstalments': [
            {
              'purchaseId': _pid,
              'number': 'GRN-000012',
              'seq': 2,
              'dueDate': '2026-11-08',
              'openTzs': 50000,
              'daysOverdue': 0,
            },
          ],
        });
        api.on('GET /vendor/purchases', {'purchases': [], 'nextCursor': null});
        await pumpPage(
          tester,
          api,
          const SupplierProfilePage(supplierId: _sid),
          user: ownerUser,
          size: const Size(400, 1600),
          extraRoutes: purchaseRoutes,
        );
        expect(find.text('Due in 5 days'), findsOneWidget);
        expect(
          find.text('Bought TSh 200,000 in 1 delivery · paid TSh 50,000'),
          findsOneWidget,
        );
      },
    );
  });

  apiTest('L-3: a voided payment says who voided it and when', (
    tester,
    api,
  ) async {
    await pumpDetail(
      tester,
      api,
      purchaseJson(payments: [paymentJson(status: 'voided')], paid: 0),
    );
    expect(
      find.text('Voided by Owner, 3 Nov 2026, 13:00: Recorded twice'),
      findsOneWidget,
    );
  });

  apiTest('L-6: after a dropped connection the save button reads Try again', (
    tester,
    api,
  ) async {
    await pumpDetail(tester, api, purchaseJson());
    api.onCall(
      'POST /vendor/purchases/$_pid/payments',
      (_) => throw http.ClientException('XMLHttpRequest error.'),
    );
    await tapVisible(tester, find.byKey(const Key('purchase-record-payment')));
    await tapVisible(tester, find.byKey(const Key('ppay-save')));
    expect(find.text(en('vendor.purchases.offlineWrite')), findsOneWidget);
    expect(buttonLabelled('Try again'), findsOneWidget);
    expect(FFLocale.textOf('sw', 'common.retry'), 'Jaribu tena');
  });

  apiTest('instalments are numbered from 1 after a payment at receipt', (
    tester,
    api,
  ) async {
    seedReceive(api);
    final host = await pumpReceive(tester, api);
    await addProduct(tester, 'p1');
    await typeInto(
      tester,
      find.byKey(const Key('purchase-line-cost-p1-')),
      '10000',
    );
    await tapVisible(tester, find.byKey(const Key('purchase-choose-supplier')));
    await tester.tap(
      find.byKey(const Key('supplier-pick-vsp_0000000000000001')),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text(host.tr('vendor.purchases.paidPart')));
    await typeInto(tester, find.byKey(const Key('purchase-paid-now')), '4000');
    await tapVisible(tester, find.byKey(const Key('purchase-split')));
    expect(find.text('Instalment 1'), findsOneWidget);
    expect(find.text('Instalment 2'), findsOneWidget);
    expect(find.text('Instalment 3'), findsNothing);
  });

  group('home', () {
    void seed(RecordingApi api, Map<String, dynamic> tools) {
      seedVendorHome(api, products: [stockProduct('p1', 'Whey')], tools: tools);
      api.on('GET /vendor/payables/aging', agingJson());
      api.on('GET /vendor/purchases', {'purchases': [], 'nextCursor': null});
    }

    apiTest('L-11: purchases-only staff, tool off: "not available right now"', (
      tester,
      api,
    ) async {
      seed(api, purchasesOffTools);
      await pumpPage(
        tester,
        api,
        const VendorHomePage(),
        user: staffUser(['purchases']),
        size: const Size(400, 900),
        extraRoutes: purchaseRoutes,
      );
      expect(
        find.byKey(const Key('vendor-purchases-unavailable')),
        findsOneWidget,
      );
      expect(
        find.text('Purchases are not available right now.'),
        findsOneWidget,
      );
      expect(find.text(en('vendor.noAccess')), findsNothing);
    });

    apiTest('L-9: permissions changed meanwhile show on the next tab switch', (
      tester,
      api,
    ) async {
      seed(api, purchasesOnTools);
      var perms = ['products', 'orders'];
      api.onCall(
        'GET /vendor/me',
        (_) => {'vendorRole': 'inventory_manager', 'permissions': perms},
      );
      final host = await pumpPage(
        tester,
        api,
        const VendorHomePage(),
        user: staffUser(['products', 'orders']),
        size: const Size(400, 900),
        extraRoutes: purchaseRoutes,
      );
      expect(find.byKey(const Key('vendor-products-segment')), findsNothing);
      perms = ['products', 'orders', 'purchases'];
      await tester.tap(find.byKey(const Key('vendor-nav-orders')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vendor-nav-products')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vendor-products-segment')), findsOneWidget);
      expect(host.auth.user?['vendorPermissions'], contains('purchases'));
    });
  });

  apiTest('stock history: Swahili times are 12-hour with the part of the day', (
    tester,
    api,
  ) async {
    api.on('GET /vendor/products', [stockProduct('p1', 'Whey')]);
    api.on('GET /vendor/stock/low', []);
    api.on('GET /vendor/tools/options', ledgerOn);
    api.on('GET /vendor/products/p1/stock-movements', {
      'openingStock': 10,
      'closingStock': 8,
      'rows': [
        {
          'id': 'm1',
          'productId': 'p1',
          'variant': null,
          'reason': 'count',
          'kind': 'adjustment',
          'delta': -2,
          'stockBefore': 10,
          'stockAfter': 8,
          'actor': {'id': 'v1', 'name': 'Asha'},
          'createdAt': '2026-10-19T11:05:00Z',
        },
      ],
      'nextCursor': null,
    });
    await pumpPage(
      tester,
      api,
      const StockHistoryPage(productId: 'p1'),
      user: vendorUser,
      lang: 'sw',
      size: const Size(400, 900),
    );
    // 11:05Z is 14:05 in Dar es Salaam: "2:05 mchana".
    expect(find.textContaining('19 Okt, 2:05 mchana'), findsOneWidget);
    expect(find.textContaining('14:05'), findsNothing);
  });
}
