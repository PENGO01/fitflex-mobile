// Vendor tools · S8 §5.3: "Count by scanning" in the S1 adjust sheet — each
// scan of this product adds 1 to Counted, another product changes nothing,
// and Save is S1's count with expectedStock.
import 'package:fitflexmobile/screens/vendor/stock/adjust_stock_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_api.dart';
import '../stock_support.dart';
import 'scan_support.dart';

const whey = '6201234567893';
const gloves = '12345670';

List<Map<String, dynamic>> countProducts() => [
  stockProduct('p1', 'Whey Protein 1kg', stock: 10)
    ..['barcodes'] = [
      {'code': whey, 'variant': null},
    ],
  stockProduct('p2', 'Gym Gloves', stock: 4)
    ..['barcodes'] = [
      {'code': gloves, 'variant': null},
    ],
];

Future<PageHost> pumpSheet(
  WidgetTester tester,
  RecordingApi api, {
  bool barcodes = true,
}) {
  api.on('GET /vendor/tools/options', barcodeTools(barcodes: barcodes));
  api.on('GET /vendor/products', countProducts());
  return pumpPage(
    tester,
    api,
    Builder(
      builder: (context) => Center(
        child: FilledButton(
          onPressed: () => openAdjustStock(
            context,
            product: countProducts().first,
            initialReason: 'count',
            makeClientRef: () => 'adj_fixed_ref_1',
          ),
          child: const Text('OPEN'),
        ),
      ),
    ),
    size: const Size(400, 1200),
  );
}

Future<void> typeCode(WidgetTester tester, String code) async {
  if (find.byKey(const Key('scan-type-field')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('scan-type')));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byKey(const Key('scan-type-field')), code);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => FakeCameras().install());
  tearDown(FakeCameras.uninstall);

  apiTest('barcodes off: no Count by scanning', (tester, api) async {
    await pumpSheet(tester, api, barcodes: false);
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('adjust-quantity')), findsOneWidget);
    expect(find.byKey(const Key('adjust-count-scan')), findsNothing);
  });

  apiTest(
    '7 scans → Counted 7, difference −3; Gloves warns; Save sends expectedStock (AC-23)',
    (tester, api) async {
      api.on('POST /vendor/products/p1/stock-adjustments', {
        'movement': {'stockBefore': 10, 'stockAfter': 7, 'delta': -3},
        'product': {'id': 'p1', 'stock': 7, 'variants': []},
      });
      final host = await pumpSheet(tester, api);
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('adjust-count-scan')));
      for (var i = 0; i < 7; i++) {
        await typeCode(tester, whey);
      }
      expect(textOf(tester, find.byKey(const Key('adjust-quantity'))), '7');
      expect(find.text('7 counted'), findsOneWidget);
      expect(
        find.text(
          host.tr('vendor.stock.difference').replaceAll('{delta}', '−3'),
        ),
        findsOneWidget,
      );
      await typeCode(tester, gloves);
      expect(
        find.text("That's Gym Gloves. Save this count first."),
        findsOneWidget,
      );
      expect(textOf(tester, find.byKey(const Key('adjust-quantity'))), '7');
      await tapVisible(tester, find.byKey(const Key('adjust-save')));
      final body =
          api.only('POST', '/vendor/products/p1/stock-adjustments').body as Map;
      expect(body['reason'], 'count');
      expect(body['quantity'], 7);
      expect(body['expectedStock'], 10);
    },
  );
}
