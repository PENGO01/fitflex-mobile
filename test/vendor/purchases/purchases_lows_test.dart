// Vendor tools · S9 retest Lows: L-6 the Receive stock confirm reads Try
// again (on screen and to a screen reader) after a lost connection and
// after a lost answer, with the same clientRef; L-4 a duplicate supplier
// is named and linked from the server's `existing {id, name}`
// (functions#330), falling back to supplierId and the typed name; L-12 a
// prefilled quantity and unit cost are in the semantics before focus.
import 'package:fitflexmobile/screens/vendor/purchases/purchase_models.dart';
import 'package:fitflexmobile/screens/vendor/purchases/receive_stock_page.dart';
import 'package:fitflexmobile/screens/vendor/purchases/suppliers_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/recording_api.dart';
import 'purchases_support.dart';

final _now = DateTime.utc(2026, 11, 3, 9);

Future<PageHost> pumpReceive(WidgetTester tester, RecordingApi api) => pumpPage(
  tester,
  api,
  ReceiveStockPage(now: () => _now),
  user: ownerUser,
  size: const Size(400, 1600),
  extraRoutes: purchaseRoutes,
);

Future<void> addWhey(WidgetTester tester) async {
  await tapVisible(tester, find.byKey(const Key('purchase-add-item')));
  await tester.tap(find.byKey(const Key('purchase-pick-p1')));
  await tester.pumpAndSettle();
}

Future<void> openConfirm(WidgetTester tester) async {
  await addWhey(tester);
  await typeInto(
    tester,
    find.byKey(const Key('purchase-line-cost-p1-')),
    '9500',
  );
  await tapVisible(tester, find.byKey(const Key('purchase-review')));
}

Finder get _save => find.byKey(const Key('purchase-confirm-save'));

void main() {
  setUpAll(loadAppFonts);

  group('L-6 confirm reads Try again', () {
    apiTest('request dropped before sending: Try again, same clientRef', (
      tester,
      api,
    ) async {
      final handle = tester.ensureSemantics();
      seedReceive(api);
      var drop = true;
      api.onCall('POST /vendor/purchases', (_) {
        if (drop) throw http.ClientException('XMLHttpRequest error.');
        return {'purchase': purchaseJson(), 'costChanges': []};
      });
      final host = await pumpReceive(tester, api);
      await openConfirm(tester);
      expect(
        tester.getSemantics(_save).label,
        startsWith('Receive stock TSh 9,500'),
      );
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(find.text(host.tr('vendor.purchases.offline')), findsOneWidget);
      expect(buttonLabelled('Try again'), findsOneWidget);
      expect(tester.getSemantics(_save).label, 'Try again');
      expect(find.bySemanticsLabel(RegExp('Receive stock TSh')), findsNothing);
      drop = false;
      await tester.tap(_save);
      await tester.pumpAndSettle();
      final sent = api.where('POST', '/vendor/purchases');
      expect(sent, hasLength(2));
      expect(
        (sent[0].body as Map)['clientRef'],
        (sent[1].body as Map)['clientRef'],
      );
      expect(find.text('ROUTE-PURCHASE vpo_0000000000000012'), findsOneWidget);
      handle.dispose();
    });

    apiTest(
      'answer lost after the server saved: Try again replays (same clientRef)',
      (tester, api) async {
        seedReceive(api);
        final saved = <String>{};
        api.onCall('POST /vendor/purchases', (r) {
          final ref = (r.body as Map)['clientRef'] as String;
          if (saved.add(ref)) {
            // Saved on the server; the answer never arrives.
            throw http.ClientException(
              'Connection closed before full header was received',
            );
          }
          return {'purchase': purchaseJson(), 'costChanges': []}; // 200 replay
        });
        await pumpReceive(tester, api);
        await openConfirm(tester);
        await tester.tap(_save);
        await tester.pumpAndSettle();
        expect(buttonLabelled('Try again'), findsOneWidget);
        await tester.tap(_save);
        await tester.pumpAndSettle();
        expect(saved, hasLength(1));
        expect(
          find.text('ROUTE-PURCHASE vpo_0000000000000012'),
          findsOneWidget,
        );
      },
    );

    apiTest('Swahili: Jaribu tena', (tester, api) async {
      seedReceive(api);
      api.onCall(
        'POST /vendor/purchases',
        (_) => throw http.ClientException('XMLHttpRequest error.'),
      );
      await pumpPage(
        tester,
        api,
        ReceiveStockPage(now: () => _now),
        user: ownerUser,
        lang: 'sw',
        size: const Size(400, 1600),
        extraRoutes: purchaseRoutes,
      );
      await openConfirm(tester);
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(buttonLabelled('Jaribu tena'), findsOneWidget);
    });
  });

  group('L-4 duplicate supplier', () {
    test('existing {id, name} wins; falls back to supplierId + typed name', () {
      final dup = duplicateSupplierOf({
        'supplierId': 'vsp_1',
        'existing': {'id': 'vsp_2', 'name': 'Juma Supplies'},
      }, typedName: 'JUMA supplies');
      expect(dup.id, 'vsp_2');
      expect(dup.name, 'Juma Supplies');
      final old = duplicateSupplierOf({
        'supplierId': 'vsp_1',
      }, typedName: ' JUMA supplies ');
      expect(old.id, 'vsp_1');
      expect(old.name, 'JUMA supplies');
    });

    apiTest('the form names and opens the existing supplier', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', purchasesOnTools);
      api.fail('POST /vendor/suppliers', 409, {
        'error': 'duplicate_supplier',
        'supplierId': 'vsp_0000000000000001',
        'existing': {'id': 'vsp_0000000000000001', 'name': 'Juma Supplies'},
      });
      await pumpPage(
        tester,
        api,
        const SupplierFormPage(),
        user: ownerUser,
        size: const Size(400, 1400),
        extraRoutes: purchaseRoutes,
      );
      await typeInto(
        tester,
        find.byKey(const Key('supplier-form-name')),
        'JUMA supplies',
      );
      await tapVisible(tester, find.byKey(const Key('supplier-form-save')));
      expect(
        find.text('You already have a supplier called Juma Supplies.'),
        findsOneWidget,
      );
      expect(buttonLabelled('Open Juma Supplies'), findsOneWidget);
      expect(find.textContaining('JUMA supplies.'), findsNothing);
      await tapVisible(
        tester,
        find.byKey(const Key('supplier-form-open-duplicate')),
      );
      expect(find.text('ROUTE-SUPPLIER vsp_0000000000000001'), findsOneWidget);
    });

    apiTest('quick add in Receive stock names the existing supplier', (
      tester,
      api,
    ) async {
      seedReceive(api);
      api.fail('POST /vendor/suppliers', 409, {
        'error': 'duplicate_supplier',
        'supplierId': 'vsp_0000000000000001',
        'existing': {'id': 'vsp_0000000000000001', 'name': 'Juma Supplies'},
      });
      await pumpReceive(tester, api);
      await tapVisible(
        tester,
        find.byKey(const Key('purchase-choose-supplier')),
      );
      await tapVisible(tester, find.byKey(const Key('supplier-picker-add')));
      await typeInto(
        tester,
        find.byKey(const Key('supplier-quick-name')),
        'JUMA supplies',
      );
      await tapVisible(tester, find.byKey(const Key('supplier-quick-save')));
      expect(
        find.text('You already have a supplier called Juma Supplies.'),
        findsOneWidget,
      );
    });
  });

  apiTest('L-12: prefilled quantity and unit cost are said before focus', (
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
    await addWhey(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    SemanticsNode node(String key) => tester.getSemantics(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      ),
    );
    expect(
      node('purchase-line-qty-p1-').label,
      contains('Quantity received for Whey 1kg, 1'),
    );
    expect(
      node('purchase-line-cost-p1-').label,
      contains('Unit cost for Whey 1kg, Tanzanian shillings, TSh 9,500'),
    );
    await tapVisible(tester, find.byKey(const Key('purchase-line-plus-p1-')));
    expect(node('purchase-line-qty-p1-').label, contains('Whey 1kg, 2'));
    handle.dispose();
  });
}
