// Vendor tools · S9: Receive stock (spec §4.2–§4.4, §4.9–§4.10) on the fake
// backend: the gate, the supplier rule, adding items (merge, variants, no
// archived products), the prefill and cost notices by canSeeCost, a free
// line, Review's reasons, offline, Try again with the same clientRef, the
// error mapping, the saved purchase opening, and the kept draft.
import 'package:fitflexmobile/screens/vendor/purchases/receive_stock_page.dart';
import 'package:fitflexmobile/shared/network/browser_online.dart';
import 'package:fitflexmobile/shared/vendor_purchase_draft_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recording_api.dart';
import 'purchases_support.dart';

final _now = DateTime.utc(2026, 11, 3, 9);

Future<PageHost> pumpReceive(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> user = ownerUser,
  String? supplierId,
  String lang = 'en',
}) => pumpPage(
  tester,
  api,
  ReceiveStockPage(supplierId: supplierId, now: () => _now),
  user: user,
  lang: lang,
  size: const Size(400, 1400),
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

Finder line(String what, String id, [String variant = '']) =>
    find.byKey(Key('purchase-line-$what-$id-$variant'));

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => BrowserOnline.debugSet(true));

  apiTest('tool off: goes to the vendor home with no message', (
    tester,
    api,
  ) async {
    seedReceive(api, tools: purchasesOffTools);
    await pumpReceive(tester, api);
    expect(find.textContaining('ROUTE-VENDOR-HOME'), findsOneWidget);
  });

  apiTest('no purchases permission: home with "no access"', (
    tester,
    api,
  ) async {
    seedReceive(api);
    final host = await pumpReceive(tester, api, user: staffUser(['products']));
    expect(find.textContaining('ROUTE-VENDOR-HOME'), findsOneWidget);
    expect(host.snack(host.tr('vendor.purchases.noAccess')), findsOneWidget);
  });

  apiTest('a stale session: the gate asks GET /vendor/me before refusing', (
    tester,
    api,
  ) async {
    seedReceive(api);
    api.on('GET /vendor/me', {
      'vendorRole': 'admin',
      'permissions': ['products', 'purchases'],
    });
    await pumpReceive(
      tester,
      api,
      user: staffUser(['products'], role: 'admin'),
    );
    expect(find.textContaining('ROUTE-VENDOR-HOME'), findsNothing);
    expect(find.byKey(const Key('purchase-add-item')), findsOneWidget);
  });

  apiTest('empty: Review is off with "Add at least one item."', (
    tester,
    api,
  ) async {
    seedReceive(api);
    final host = await pumpReceive(tester, api);
    expect(find.byKey(const Key('purchase-no-items')), findsOneWidget);
    expect(
      isEnabled(tester, find.byKey(const Key('purchase-review'))),
      isFalse,
    );
    expect(find.text(host.tr('vendor.purchases.needItem')), findsOneWidget);
    expect(find.text(host.tr('vendor.purchases.moneyNotice')), findsNothing);
  });

  apiTest('picker: archived not listed; a paused one is, with a badge', (
    tester,
    api,
  ) async {
    seedReceive(api);
    final host = await pumpReceive(tester, api);
    await tapVisible(tester, find.byKey(const Key('purchase-add-item')));
    expect(find.byKey(const Key('purchase-pick-p3')), findsNothing);
    expect(find.byKey(const Key('purchase-pick-p2')), findsOneWidget);
    expect(find.text(host.tr('vendor.purchases.notListed')), findsOneWidget);
    await typeInto(
      tester,
      find.byKey(const Key('purchase-product-search')),
      'wh1',
    );
    expect(find.byKey(const Key('purchase-pick-p1')), findsOneWidget);
    expect(find.byKey(const Key('purchase-pick-p2')), findsNothing);
  });

  apiTest(
    'owner: last cost prefills; "will change from X to Y"; stock 3 → 13',
    (tester, api) async {
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
      expect(
        api.only('GET', '/vendor/purchases/last-costs').query,
        contains('productIds=p1'),
      );
      final cost = tester.widget<EditableText>(
        find.descendant(
          of: line('cost', 'p1'),
          matching: find.byType(EditableText),
        ),
      );
      expect(cost.controller.text, '9500');
      expect(
        find.text('Last time: TSh 9,500 from Juma Supplies, 20 Oct 2026'),
        findsOneWidget,
      );
      expect(
        find.text('Cost price will change from TSh 9,000 to TSh 9,500.'),
        findsOneWidget,
      );
      await tapVisible(tester, line('plus', 'p1'));
      expect(find.text('Stock 3 → 5'), findsOneWidget);
      await typeInto(tester, line('qty', 'p1'), '10');
      expect(find.text('Stock 3 → 13'), findsOneWidget);
      expect(find.text('TSh 95,000'), findsWidgets);
    },
  );

  apiTest('AC-4 purchases-only staff: no "from" figure, cost not prefilled', (
    tester,
    api,
  ) async {
    seedReceive(api, tools: purchasesOnNoCost);
    await pumpReceive(tester, api, user: staffUser(['purchases']));
    await addProduct(tester, 'p1');
    await typeInto(tester, line('cost', 'p1'), '9500');
    expect(find.text('Cost price will be set to TSh 9,500.'), findsOneWidget);
    expect(find.textContaining('9,000'), findsNothing);
  });

  apiTest('AC-10: a free line says so and changes no cost', (
    tester,
    api,
  ) async {
    seedReceive(api);
    final host = await pumpReceive(tester, api);
    await addProduct(tester, 'p1');
    await typeInto(tester, line('cost', 'p1'), '0');
    expect(find.text(host.tr('vendor.purchases.freeLine')), findsOneWidget);
  });

  apiTest('AC-9/AC-11: variants chosen; the same item twice is one line', (
    tester,
    api,
  ) async {
    seedReceive(api);
    final host = await pumpReceive(tester, api);
    await addProduct(tester, 'p2', variant: 'M');
    expect(line('qty', 'p2', 'M'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('purchase-add-item')));
    await tester.tap(find.byKey(const Key('purchase-pick-p2')));
    await tester.pumpAndSettle();
    expect(find.text(host.tr('vendor.purchases.added')), findsOneWidget);
    await tester.tap(find.byKey(const Key('purchase-pick-variant-M')));
    await tester.pumpAndSettle();
    expect(line('qty', 'p2', 'M'), findsOneWidget);
    // M's own cost (6,000) is the one that changes, not the product's.
    await typeInto(tester, line('cost', 'p2', 'M'), '7000');
    expect(
      find.text('Cost price will change from TSh 6,000 to TSh 7,000.'),
      findsOneWidget,
    );
  });

  apiTest('AC-12: Not paid yet without a supplier keeps Review off', (
    tester,
    api,
  ) async {
    seedReceive(api);
    final host = await pumpReceive(tester, api);
    await addProduct(tester, 'p1');
    await typeInto(tester, line('cost', 'p1'), '9500');
    expect(isEnabled(tester, find.byKey(const Key('purchase-review'))), isTrue);
    await tapVisible(tester, find.text(host.tr('vendor.purchases.notPaid')));
    expect(
      isEnabled(tester, find.byKey(const Key('purchase-review'))),
      isFalse,
    );
    expect(find.text(host.tr('vendor.purchases.needSupplier')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('purchase-choose-supplier')));
    await tester.tap(
      find.byKey(const Key('supplier-pick-vsp_0000000000000001')),
    );
    await tester.pumpAndSettle();
    expect(find.text('You already owe TSh 40,000'), findsOneWidget);
    expect(isEnabled(tester, find.byKey(const Key('purchase-review'))), isTrue);
  });

  apiTest('offline: Review off with the draft-kept line', (tester, api) async {
    seedReceive(api);
    final host = await pumpReceive(tester, api);
    await addProduct(tester, 'p1');
    await typeInto(tester, line('cost', 'p1'), '9500');
    BrowserOnline.debugSet(false);
    await tester.pumpAndSettle();
    expect(
      isEnabled(tester, find.byKey(const Key('purchase-review'))),
      isFalse,
    );
    expect(find.text(host.tr('vendor.purchases.offline')), findsOneWidget);
  });

  apiTest('AC-14: a 5xx keeps the dialog; Try again sends the same clientRef', (
    tester,
    api,
  ) async {
    seedReceive(api);
    api.fail('POST /vendor/purchases', 503);
    final host = await pumpReceive(tester, api);
    await addProduct(tester, 'p1');
    await typeInto(tester, line('cost', 'p1'), '9500');
    await tapVisible(tester, find.byKey(const Key('purchase-review')));
    expect(find.byKey(const Key('purchase-confirm')), findsOneWidget);
    expect(find.text('Receive 1 item?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('purchase-confirm-save')));
    await tester.pumpAndSettle();
    expect(find.text(host.tr('vendor.purchases.err.server')), findsOneWidget);
    api.heal('POST /vendor/purchases');
    api.on('POST /vendor/purchases', {
      'purchase': purchaseJson(),
      'costChanges': [],
    });
    await tester.tap(find.byKey(const Key('purchase-confirm-save')));
    await tester.pumpAndSettle();
    final sent = api.where('POST', '/vendor/purchases');
    expect(sent, hasLength(2));
    expect(
      (sent[0].body as Map)['clientRef'],
      (sent[1].body as Map)['clientRef'],
    );
    expect((sent[1].body as Map)['paidNow'], {
      'amountTzs': 9500,
      'method': 'cash',
    });
    expect(find.text('ROUTE-PURCHASE vpo_0000000000000012'), findsOneWidget);
    expect(host.snack('Stock received: GRN-000012'), findsOneWidget);
    // The kept draft is gone after success.
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where(
        (k) => k.startsWith(VendorPurchaseDraftStore.prefix),
      ),
      isEmpty,
    );
  });

  apiTest('404 product_not_found: that line says it cannot be received', (
    tester,
    api,
  ) async {
    seedReceive(api);
    api.fail('POST /vendor/purchases', 404, {
      'error': 'product_not_found',
      'productId': 'p1',
    });
    await pumpReceive(tester, api);
    await addProduct(tester, 'p1');
    await typeInto(tester, line('cost', 'p1'), '9500');
    await tapVisible(tester, find.byKey(const Key('purchase-review')));
    await tester.tap(find.byKey(const Key('purchase-confirm-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-confirm')), findsNothing);
    expect(
      find.text("Whey 1kg can't be received any more. Remove it."),
      findsOneWidget,
    );
    expect(
      isEnabled(tester, find.byKey(const Key('purchase-review'))),
      isFalse,
    );
  });

  apiTest('409 supplier_archived: shown on the supplier', (tester, api) async {
    seedReceive(api);
    api.fail('POST /vendor/purchases', 409, {
      'error': 'supplier_archived',
      'supplierId': 'vsp_0000000000000001',
    });
    final host = await pumpReceive(tester, api);
    await addProduct(tester, 'p1');
    await typeInto(tester, line('cost', 'p1'), '9500');
    await tapVisible(tester, find.byKey(const Key('purchase-choose-supplier')));
    await tester.tap(
      find.byKey(const Key('supplier-pick-vsp_0000000000000001')),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text(host.tr('vendor.purchases.paidFull')));
    await tapVisible(tester, find.byKey(const Key('purchase-review')));
    await tester.tap(find.byKey(const Key('purchase-confirm-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-supplier-error')), findsOneWidget);
    expect(find.textContaining('Juma Supplies is archived'), findsOneWidget);
  });

  apiTest('a suspended vendor (403 on products): nothing can be received', (
    tester,
    api,
  ) async {
    seedReceive(api);
    api.fail('GET /vendor/products', 403, {'error': 'vendor_suspended'});
    await pumpReceive(tester, api, user: staffUser(['purchases']));
    expect(find.byKey(const Key('purchase-suspended')), findsOneWidget);
    expect(
      isEnabled(tester, find.byKey(const Key('purchase-review'))),
      isFalse,
    );
  });

  apiTest('AC-32: a kept draft is offered; Continue puts the lines back', (
    tester,
    api,
  ) async {
    seedReceive(api);
    await VendorPurchaseDraftStore.save('vendor_purchase_draft.v1.v1', {
      'savedAt': '2026-11-03T06:00:00.000Z',
      'lines': [
        {
          'productId': 'p1',
          'variant': null,
          'name': 'Whey 1kg',
          'qty': 4,
          'unitCostTzs': 9400,
        },
      ],
    });
    final host = await pumpReceive(tester, api);
    expect(find.byKey(const Key('purchase-draft-found')), findsOneWidget);
    expect(find.textContaining('unfinished delivery'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('purchase-draft-continue')));
    expect(line('qty', 'p1'), findsOneWidget);
    expect(find.text('TSh 37,600'), findsWidgets);
    expect(find.text(host.tr('vendor.purchases.needItem')), findsNothing);
  });

  apiTest('leaving with lines asks Keep draft / Discard', (tester, api) async {
    seedReceive(api);
    await pumpReceive(tester, api);
    await addProduct(tester, 'p1');
    await tapVisible(tester, find.byKey(const Key('purchase-close')));
    expect(find.byKey(const Key('purchase-leave-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('purchase-leave-keep')));
    await tester.pumpAndSettle();
    expect(
      await VendorPurchaseDraftStore.load('vendor_purchase_draft.v1.v1'),
      isNotNull,
    );
  });

  apiTest('Swahili: the receive screen in Kiswahili', (tester, api) async {
    seedReceive(api);
    await pumpReceive(tester, api, lang: 'sw');
    expect(find.text('Pokea Stock'), findsWidgets);
    expect(find.text('Nini kimeingia?'), findsOneWidget);
  });
}
