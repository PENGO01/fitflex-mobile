// Vendor tools · S8 §5.3 / §4.6 on the Products tab: find a product by
// scanning → action sheet → Count stock; unknown code → New product with
// this code (POST with the code); gating by tool and permission.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_api.dart';
import '../stock_support.dart';
import 'scan_support.dart';

const whey = '6201234567893';

List<Map<String, dynamic>> tabProducts() => [
  stockProduct('p1', 'Whey Protein 1kg', stock: 10)
    ..['barcodes'] = [
      {'code': whey, 'variant': null},
    ],
];

Future<void> scanSheetType(WidgetTester tester, String code) async {
  await tapVisible(tester, find.byKey(const Key('products-scan')));
  await tester.tap(find.byKey(const Key('scan-type')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('scan-type-field')), code);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => FakeCameras().install());
  tearDown(FakeCameras.uninstall);

  apiTest('tool off: no scan entry', (tester, api) async {
    seedVendorHome(
      api,
      products: tabProducts(),
      tools: barcodeTools(barcodes: false),
    );
    await pumpVendorHome(tester, api);
    expect(find.byKey(const Key('products-scan')), findsNothing);
  });

  apiTest('scan Whey → stock now 10 → Count stock opens Counted (AC-23)', (
    tester,
    api,
  ) async {
    seedVendorHome(api, products: tabProducts(), tools: barcodeTools());
    final host = await pumpVendorHome(tester, api);
    await scanSheetType(tester, whey);
    expect(find.text('Stock now: 10'), findsOneWidget);
    await tester.tap(find.byKey(const Key('products-scan-count')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('adjust-quantity')), findsOneWidget);
    expect(find.text(host.tr('vendor.stock.counted')), findsWidgets);
  });

  apiTest(
    'unknown code → New product with this code → POST carries it (AC-20)',
    (tester, api) async {
      seedVendorHome(api, products: tabProducts(), tools: barcodeTools());
      api.on('GET /vendor/products/lookup', {
        'code': '5012345678900',
        'codeKey': '5012345678900',
        'matches': [],
      });
      api.on('POST /vendor/products', {'id': 'p9', 'name': 'Shaker'});
      await pumpVendorHome(tester, api);
      await scanSheetType(tester, '5012345678900');
      expect(
        find.text('No product has the code 5012345678900.'),
        findsOneWidget,
      );
      await tapVisible(tester, find.byKey(const Key('scan-create-product')));
      expect(
        find.byKey(const Key('vendor-barcode-row-5012345678900')),
        findsOneWidget,
      );
      await typeInto(
        tester,
        find.byKey(const Key('vendor-product-name')),
        'Shaker',
      );
      await typeInto(
        tester,
        find.byKey(const Key('vendor-product-price')),
        '9000',
      );
      await tapVisible(tester, find.byKey(const Key('vendor-product-save')));
      final body = api.only('POST', '/vendor/products').body as Map;
      expect(body['barcodes'], [
        {'code': '5012345678900'},
      ]);
    },
  );
}
