// Vendor tools · S8 §5.2: scanning in Receive stock — a new line with the
// S9 cost prefill, +1 on the same line, variant chooser, archived refused.
import 'package:fitflexmobile/screens/vendor/purchases/receive_stock_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_api.dart';
import '../purchases/purchases_support.dart';
import 'scan_support.dart';

const whey = '6201234567893';
const teeWhole = 'TEE-ALL';
const oldMat = '036000291452';

List<Map<String, dynamic>> scanPurchaseProducts() {
  final rows = purchaseProducts();
  rows[0]['barcodes'] = [
    {'code': whey, 'variant': null},
  ];
  rows[1]['barcodes'] = [
    {'code': teeWhole, 'variant': null},
  ];
  rows[2]['barcodes'] = [
    {'code': oldMat, 'variant': null},
  ];
  return rows;
}

Future<PageHost> pumpScanReceive(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic>? tools,
  Map<String, dynamic> user = ownerUser,
}) {
  seedReceive(api, tools: tools ?? barcodeTools(walkInSales: false));
  api.on('GET /vendor/products', scanPurchaseProducts());
  return pumpPage(
    tester,
    api,
    ReceiveStockPage(now: () => DateTime.utc(2026, 11, 9, 9)),
    user: user,
    size: const Size(400, 1400),
    extraRoutes: purchaseRoutes,
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

Finder line(String what, String id, [String variant = '']) =>
    find.byKey(Key('purchase-line-$what-$id-$variant'));

void main() {
  setUpAll(loadAppFonts);
  setUp(() => FakeCameras().install());
  tearDown(FakeCameras.uninstall);

  apiTest('barcodes off: no Scan items', (tester, api) async {
    await pumpScanReceive(tester, api, tools: barcodeTools(barcodes: false));
    expect(find.byKey(const Key('purchase-scan')), findsNothing);
  });

  apiTest('Whey twice → one line, qty 2, cost prefilled (AC-21)', (
    tester,
    api,
  ) async {
    final host = await pumpScanReceive(tester, api);
    await tapVisible(tester, find.byKey(const Key('purchase-scan')));
    await typeCode(tester, whey);
    expect(find.text('Whey 1kg added · 1 received'), findsOneWidget);
    await typeCode(tester, whey);
    expect(find.text('Whey 1kg added · 2 received'), findsOneWidget);
    expect(textOf(tester, line('qty', 'p1')), '2');
    expect(textOf(tester, line('cost', 'p1')), '9000');
    expect(find.byKey(const Key('purchase-no-items')), findsNothing);
    expect(api.sent('GET', '/vendor/products/lookup'), isFalse);
    // −: one fewer; Undo gone after a manual step.
    await tester.tap(find.byKey(const Key('scan-result-less')));
    await tester.pumpAndSettle();
    expect(textOf(tester, line('qty', 'p1')), '1');
    expect(host.tr('vendor.scan.scanItems'), 'Scan items');
  });

  apiTest('archived product code is refused; nothing added', (
    tester,
    api,
  ) async {
    await pumpScanReceive(tester, api);
    await tapVisible(tester, find.byKey(const Key('purchase-scan')));
    await typeCode(tester, oldMat);
    expect(
      find.text('Old mat is archived. Restore it in Products first.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('purchase-no-items')), findsOneWidget);
  });

  apiTest('whole-product code with tracked variants asks which one', (
    tester,
    api,
  ) async {
    await pumpScanReceive(tester, api);
    await tapVisible(tester, find.byKey(const Key('purchase-scan')));
    await typeCode(tester, teeWhole);
    await tester.tap(find.byKey(const Key('purchase-scan-variant-M')));
    await tester.pumpAndSettle();
    expect(line('qty', 'p2', 'M'), findsOneWidget);
    expect(textOf(tester, line('cost', 'p2', 'M')), '6000');
  });

  apiTest('the product picker has a scan icon that opens the panel', (
    tester,
    api,
  ) async {
    await pumpScanReceive(tester, api);
    await tapVisible(tester, find.byKey(const Key('purchase-add-item')));
    await tester.tap(find.byKey(const Key('purchase-picker-scan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-scan-panel')), findsOneWidget);
  });

  apiTest('purchases-only staff: unknown code, no add actions (AC-4)', (
    tester,
    api,
  ) async {
    api.on('GET /vendor/products/lookup', {
      'code': 'ZZZZ-9',
      'codeKey': 'ZZZZ-9',
      'matches': [],
    });
    final host = await pumpScanReceive(
      tester,
      api,
      user: staffUser(['purchases']),
    );
    await tapVisible(tester, find.byKey(const Key('purchase-scan')));
    await typeCode(tester, 'ZZZZ-9');
    expect(find.text('No product has the code ZZZZ-9.'), findsOneWidget);
    expect(find.text(host.tr('vendor.scan.askProducts')), findsOneWidget);
    expect(find.byKey(const Key('scan-add-to-product')), findsNothing);
  });
}
