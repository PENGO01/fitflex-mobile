// Vendor tools · S3: the receipt screen — content, receipt language toggle
// (not the app language), share text, New sale / Done, and a queued sale's
// receipt turning into its R-number in place once it syncs.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/screens/vendor/sales/offline_sale_queue.dart';
import 'package:fitflexmobile/screens/vendor/sales/receipt_page.dart';

import '../support/recording_api.dart';
import 'walkin_support.dart';

const owner = {'id': 'v1', 'userType': 'vendor', 'displayName': 'Asha'};

void main() {
  setUpAll(loadAppFonts);

  apiTest(
    'receipt: header, totals, change, footer, not fiscal; language toggle; share',
    (tester, api) async {
      seedPos(api);
      final shared = <String>[];
      final previous = shareReceipt;
      shareReceipt = (text, subject) async => shared.add('$subject\n$text');
      addTearDown(() => shareReceipt = previous);
      final host = await pumpPage(
        tester,
        api,
        SaleReceiptPage(saleId: 'sal_1', sale: serverSale()),
        user: owner,
        size: const Size(400, 1400),
        extraRoutes: salesRoutes,
      );
      expect(find.text('Receipt R-000001'), findsOneWidget);
      expect(find.text('Dar Gear'), findsOneWidget);
      expect(find.text('Payment received by Dar Gear.'), findsOneWidget);
      expect(find.text('This is not a TRA fiscal receipt.'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(find.text('Served by Asha'), findsOneWidget);
      // Kiswahili receipt, app stays English.
      await tester.tap(find.text('Kiswahili'));
      await tester.pumpAndSettle();
      expect(find.text('Risiti R-000001'), findsOneWidget);
      expect(find.text('Hii si risiti ya kodi ya TRA.'), findsOneWidget);
      expect(find.text(host.tr('vendor.pos.newSale')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sales-receipt-share')));
      await tester.pumpAndSettle();
      // Sale extras #3: Share opens Image / PDF / Share as text.
      await tester.tap(find.byKey(const Key('receipt-share-text')));
      await tester.pumpAndSettle();
      expect(shared.single, startsWith('Dar Gear Risiti R-000001'));
      expect(shared.single, contains('Chenji'));
      await tester.tap(find.byKey(const Key('sales-receipt-done')));
      await tester.pumpAndSettle();
      expect(textContaining('ROUTE-VENDOR-HOME open=sales'), findsOneWidget);
    },
  );

  apiTest('New sale opens an empty POS', (tester, api) async {
    seedPos(api);
    await pumpPage(
      tester,
      api,
      SaleReceiptPage(saleId: 'sal_1', sale: serverSale()),
      user: owner,
      size: const Size(400, 1400),
      extraRoutes: salesRoutes,
    );
    await tester.tap(find.byKey(const Key('sales-receipt-new')));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE-POS'), findsOneWidget);
  });

  apiTest('queued receipt: waiting + temp ref, then its number once synced', (
    tester,
    api,
  ) async {
    SharedPreferences.setMockInitialValues({
      'vendor_sale_queue.v1.v1': jsonEncode([
        {
          'body': {
            'clientRef': 'sale_q_00abcdef',
            'soldAt': '2026-10-19T08:00:00.000Z',
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
          'queuedAt': '2026-10-19T08:00:00.000Z',
          'state': 'waiting',
        },
      ]),
    });
    seedPos(api);
    api.fail('POST /vendor/sales', 503);
    final host = await pumpPage(
      tester,
      api,
      const SaleReceiptPage(clientRef: 'sale_q_00abcdef'),
      user: owner,
      size: const Size(400, 1400),
      extraRoutes: salesRoutes,
    );
    expect(find.byKey(const Key('sales-receipt-waiting')), findsOneWidget);
    expect(find.text('Temporary ref ABCDEF'), findsOneWidget);
    // Back online: Sync now records it and the receipt updates in place.
    api.heal('POST /vendor/sales');
    api.onCall(
      'POST /vendor/sales',
      (_) => {
        'sale': {
          ...serverSale(number: 'R-000007'),
          'clientRef': 'sale_q_00abcdef',
        },
      },
    );
    final session = SalesSession.of(
      tester.element(find.byType(SaleReceiptPage)),
    )!;
    await session.sync(manual: true);
    await tester.pumpAndSettle();
    expect(find.text('Receipt R-000007'), findsOneWidget);
    expect(find.byKey(const Key('sales-receipt-waiting')), findsNothing);
    expect(
      find.text(
        host.tr('vendor.sync.synced').replaceAll('{number}', 'R-000007'),
      ),
      findsOneWidget,
    );
  });
}
