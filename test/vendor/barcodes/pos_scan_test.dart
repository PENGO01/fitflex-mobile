// Vendor tools · S8 §5.1: scanning in the POS (Type code / USB go through
// the same handler as the camera) — gating, add, +1, Undo, variants, out of
// stock, archived, Enter priority, offline cache, unknown codes, B-11, 429.
import 'dart:convert';

import 'package:fitflexmobile/screens/vendor/sales/pos_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recording_api.dart';
import '../walkin_support.dart';
import 'scan_support.dart';

const owner = {'id': 'v1', 'userType': 'vendor', 'displayName': 'Asha'};
const whey = '6201234567893';
const glovesWhole = '12345670';
const glovesL = 'GLV-L';
const oldMat = '036000291452';

List<Map<String, dynamic>> scanProducts() => [
  posProduct('p1', 'Whey', stock: 10, sku: 'WP-1KG')
    ..['barcodes'] = [
      {'code': whey, 'variant': null},
    ],
  posProduct(
      'p2',
      'Gym Gloves',
      stock: 7,
      variants: [
        {'name': 'S', 'stock': 3},
        {'name': 'M', 'stock': 4},
        {'name': 'L', 'stock': 0},
      ],
    )
    ..['barcodes'] = [
      {'code': glovesWhole, 'variant': null},
      {'code': glovesL, 'variant': 'L'},
    ],
  posProduct('p3', 'Old mat', status: 'archived')
    ..['barcodes'] = [
      {'code': oldMat, 'variant': null},
    ],
  posProduct('p4', 'Shaker', sku: '6201234567886'),
];

Future<PageHost> pumpScanPos(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> user = owner,
  Map<String, dynamic>? tools,
  List<Map<String, dynamic>>? products,
}) async {
  seedPos(
    api,
    tools: tools ?? barcodeTools(),
    products: products ?? scanProducts(),
  );
  return pumpPage(
    tester,
    api,
    const PosPage(),
    user: user,
    size: const Size(400, 1000),
    extraRoutes: salesRoutes,
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

Future<void> openScan(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('pos-scan')));
  await tester.pumpAndSettle();
}

String itemsText(PageHost host, int n) => host
    .tr(n == 1 ? 'vendor.pos.itemsOne' : 'vendor.pos.items')
    .replaceAll('{n}', '$n');

void main() {
  setUpAll(loadAppFonts);
  late FakeCameras cams;
  setUp(() => cams = FakeCameras()..install());
  tearDown(FakeCameras.uninstall);

  apiTest(
    'barcodes off (or missing): no scan icon; Enter on a SKU still adds',
    (tester, api) async {
      final host = await pumpScanPos(
        tester,
        api,
        tools: barcodeTools(barcodes: false),
      );
      expect(find.byKey(const Key('pos-scan')), findsNothing);
      await tester.enterText(find.byKey(const Key('pos-search')), 'wp-1kg');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text(itemsText(host, 1)), findsOneWidget);
      expect(api.sent('GET', '/vendor/products/lookup'), isFalse);
    },
  );

  apiTest('Type code: added, again +1, Undo takes the last one off (AC-16)', (
    tester,
    api,
  ) async {
    final host = await pumpScanPos(tester, api);
    await openScan(tester);
    expect(find.byKey(const Key('pos-scan-panel')), findsOneWidget);
    await typeCode(tester, whey);
    expect(find.text('Whey added · 1 in this sale'), findsOneWidget);
    await typeCode(tester, whey);
    expect(find.text('Whey added · 2 in this sale'), findsOneWidget);
    expect(find.text(itemsText(host, 2)), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-result-undo')));
    await tester.pumpAndSettle();
    expect(find.text(itemsText(host, 1)), findsOneWidget);
    expect(find.byKey(const Key('scan-result-undo')), findsNothing);
    await tester.tap(find.byKey(const Key('scan-result-more')));
    await tester.pumpAndSettle();
    expect(find.text(itemsText(host, 2)), findsOneWidget);
    // Matched locally: no lookup.
    expect(api.sent('GET', '/vendor/products/lookup'), isFalse);
  });

  apiTest('camera: the same code within 1.5 s is added once', (
    tester,
    api,
  ) async {
    final host = await pumpScanPos(tester, api);
    await openScan(tester);
    cams.last.see(whey);
    await tester.pumpAndSettle();
    cams.last.see(whey);
    await tester.pumpAndSettle();
    expect(find.text(itemsText(host, 1)), findsOneWidget);
  });

  apiTest(
    'whole-product code on Gloves: picker with L disabled; M added (AC-17)',
    (tester, api) async {
      final host = await pumpScanPos(tester, api);
      await openScan(tester);
      cams.last.see(glovesWhole);
      await tester.pumpAndSettle();
      final l = tester.widget<ListTile>(find.byKey(const Key('pos-variant-L')));
      expect(l.enabled, isFalse);
      // The camera is held while the sheet is open.
      expect(cams.last.running, isFalse);
      await tester.tap(find.byKey(const Key('pos-variant-M')));
      await tester.pumpAndSettle();
      expect(
        find.text('Gym Gloves (M) added · 1 in this sale'),
        findsOneWidget,
      );
      expect(find.text(itemsText(host, 1)), findsOneWidget);
      expect(cams.last.running, isTrue);
    },
  );

  apiTest('out-of-stock variant code and archived code add nothing', (
    tester,
    api,
  ) async {
    final host = await pumpScanPos(tester, api);
    await openScan(tester);
    await typeCode(tester, glovesL);
    expect(find.text('Gym Gloves (L) is out of stock.'), findsOneWidget);
    await typeCode(tester, oldMat);
    expect(
      find.text('Old mat is archived. Restore it in Products first.'),
      findsOneWidget,
    );
    expect(find.text(host.tr('vendor.pos.cartEmpty')), findsOneWidget);
  });

  apiTest(
    'Enter in search: a code wins over a text match, field clears (AC-18)',
    (tester, api) async {
      // "Whey" text also matches a product called "62012 Whey"; the code wins.
      final products = scanProducts()
        ..add(posProduct('p5', '$whey Whey bundle'));
      final host = await pumpScanPos(tester, api, products: products);
      await tester.enterText(find.byKey(const Key('pos-search')), whey);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text(itemsText(host, 1)), findsOneWidget);
      expect(textOf(tester, find.byKey(const Key('pos-search'))), '');
      await tester.tap(find.byKey(const Key('pos-cart-bar')));
      await tester.pumpAndSettle();
      expect(find.text('Whey'), findsWidgets);
    },
  );

  apiTest('Enter: SKU typed as an EAN still works; unknown code is looked up', (
    tester,
    api,
  ) async {
    api.on('GET /vendor/products/lookup', {
      'code': '5012345678900',
      'codeKey': '5012345678900',
      'matches': [],
    });
    final host = await pumpScanPos(tester, api);
    await tester.enterText(
      find.byKey(const Key('pos-search')),
      '6201234567886',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text(itemsText(host, 1)), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('pos-search')),
      '5012345678900',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
      api.only('GET', '/vendor/products/lookup').query,
      'code=5012345678900',
    );
    expect(find.text('No product has the code 5012345678900.'), findsOneWidget);
    expect(find.byKey(const Key('scan-add-to-product')), findsOneWidget);
    expect(find.byKey(const Key('scan-create-product')), findsOneWidget);
  });

  apiTest('several SKU matches: chooser, pick one (AC-14)', (
    tester,
    api,
  ) async {
    final products = scanProducts()
      ..add(posProduct('p6', 'Band red', sku: 'BAND'))
      ..add(posProduct('p7', 'Band blue', sku: 'band'));
    final host = await pumpScanPos(tester, api, products: products);
    await openScan(tester);
    await typeCode(tester, 'BAND');
    expect(find.text(host.tr('vendor.scan.pickMatch')), findsWidgets);
    await tester.tap(find.byKey(const Key('scan-pick-p6')));
    await tester.pumpAndSettle();
    expect(find.text('Band red added · 1 in this sale'), findsOneWidget);
  });

  apiTest(
    'unknown code → Add this code to a product → addBarcodes, then in the cart (AC-20)',
    (tester, api) async {
      api.on('GET /vendor/products/lookup', {
        'code': '5012345678900',
        'codeKey': '5012345678900',
        'matches': [],
      });
      final saved = scanProducts().first
        ..['barcodes'] = [
          {'code': whey, 'variant': null},
          {'code': '5012345678900', 'variant': null},
        ];
      api.on('PUT /vendor/products/p1', saved);
      final host = await pumpScanPos(tester, api);
      await openScan(tester);
      await typeCode(tester, '5012345678900');
      await tapVisible(tester, find.byKey(const Key('scan-add-to-product')));
      await tester.tap(find.byKey(const Key('scan-add-pick-p1')));
      await tester.pumpAndSettle();
      expect(find.text('Add code 5012345678900 to Whey?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('scan-confirm-add')));
      await tester.pumpAndSettle();
      expect(api.only('PUT', '/vendor/products/p1').body, {
        'addBarcodes': [
          {'code': '5012345678900'},
        ],
      });
      expect(host.snack('Code added to Whey.'), findsOneWidget);
      expect(find.text('Whey added · 1 in this sale'), findsOneWidget);
      // Now matched locally.
      api.clear();
      await typeCode(tester, '5012345678900');
      expect(api.sent('GET', '/vendor/products/lookup'), isFalse);
      expect(find.text('Whey added · 2 in this sale'), findsOneWidget);
    },
  );

  apiTest(
    '409 barcode_in_use with no name: "in use, try again", nothing added',
    (tester, api) async {
      api.on('GET /vendor/products/lookup', {
        'code': '5012345678900',
        'codeKey': '5012345678900',
        'matches': [],
      });
      api.fail('PUT /vendor/products/p1', 409, {
        'error': 'barcode_in_use',
        'code': null,
        'productId': null,
        'name': null,
        'variant': null,
      });
      final host = await pumpScanPos(tester, api);
      await openScan(tester);
      await typeCode(tester, '5012345678900');
      await tapVisible(tester, find.byKey(const Key('scan-add-to-product')));
      await tester.tap(find.byKey(const Key('scan-add-pick-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-confirm-add')));
      await tester.pumpAndSettle();
      expect(
        host.snack(host.tr('vendor.barcodes.err.inUseRetry')),
        findsOneWidget,
      );
      expect(find.text(host.tr('vendor.pos.cartEmpty')), findsOneWidget);
    },
  );

  apiTest('sales-only staff: unknown code asks someone with products (AC-3)', (
    tester,
    api,
  ) async {
    api.on('GET /vendor/products/lookup', {
      'code': 'ZZZZ-1',
      'codeKey': 'ZZZZ-1',
      'matches': [],
    });
    final host = await pumpScanPos(
      tester,
      api,
      user: {
        'id': 's1',
        'userType': 'vendor_staff',
        'vendorId': 'v1',
        'vendorPermissions': ['sales'],
      },
    );
    await openScan(tester);
    await typeCode(tester, 'ZZZZ-1');
    expect(find.text(host.tr('vendor.scan.askProducts')), findsOneWidget);
    expect(find.byKey(const Key('scan-add-to-product')), findsNothing);
    expect(find.byKey(const Key('scan-create-product')), findsNothing);
  });

  apiTest('FitFlex QR codes are not product codes; no lookup (AC-26)', (
    tester,
    api,
  ) async {
    final host = await pumpScanPos(tester, api);
    await openScan(tester);
    cams.last.see('FFEV1:tkt_0001');
    await tester.pumpAndSettle();
    expect(find.text(host.tr('vendor.scan.notProduct')), findsOneWidget);
    expect(api.sent('GET', '/vendor/products/lookup'), isFalse);
  });

  apiTest('429: "Too many scans. Wait 30 seconds." (AC-15)', (
    tester,
    api,
  ) async {
    api.fail('GET /vendor/products/lookup', 429, {
      'error': 'rate_limited',
      'retryAfterSeconds': 30,
    });
    await pumpScanPos(tester, api);
    await openScan(tester);
    await typeCode(tester, '5012345678900');
    expect(find.text('Too many scans. Wait 30 seconds.'), findsOneWidget);
  });

  apiTest('lookup 404 feature_disabled: panel closes with "not available"', (
    tester,
    api,
  ) async {
    api.fail('GET /vendor/products/lookup', 404, {'error': 'feature_disabled'});
    final host = await pumpScanPos(tester, api);
    await openScan(tester);
    await typeCode(tester, '5012345678900');
    expect(find.byKey(const Key('pos-scan-panel')), findsNothing);
    expect(host.snack(host.tr('vendor.barcodes.unavailable')), findsOneWidget);
  });

  apiTest('the cache keeps barcodes and never cost (§7)', (tester, api) async {
    await pumpScanPos(tester, api);
    final prefs = await SharedPreferences.getInstance();
    final cached =
        jsonDecode(prefs.getString('vendor_pos_products.v1')!) as Map;
    final p1 = (cached['products'] as List).cast<Map>().firstWhere(
      (p) => p['id'] == 'p1',
    );
    expect(p1['barcodes'], [
      {'code': whey, 'variant': null},
    ]);
    expect(p1.containsKey('costTzs'), isFalse);
  });

  apiTest(
    'offline: a cached code is added; an unknown one says so, no add actions (AC-19)',
    (tester, api) async {
      final cache = jsonEncode({
        'cachedAt': '2026-11-09T07:00:00.000Z',
        'products': [
          {
            'id': 'p1',
            'name': 'Whey',
            'priceTzs': 45000,
            'stock': 10,
            'status': 'active',
            'variants': [],
            'barcodes': [
              {'code': whey, 'variant': null},
            ],
          },
        ],
      });
      SharedPreferences.setMockInitialValues({'vendor_pos_products.v1': cache});
      seedPos(api, tools: barcodeTools());
      api.onCall(
        'GET /vendor/products',
        (_) => throw http.ClientException('offline'),
      );
      api.onCall(
        'GET /vendor/products/lookup',
        (_) => throw http.ClientException('offline'),
      );
      final host = await pumpPage(
        tester,
        api,
        const PosPage(),
        user: owner,
        size: const Size(400, 1000),
        extraRoutes: salesRoutes,
      );
      await openScan(tester);
      await typeCode(tester, whey);
      expect(find.text('Whey added · 1 in this sale'), findsOneWidget);
      await typeCode(tester, '5012345678900');
      expect(api.sent('GET', '/vendor/products/lookup'), isFalse);
      expect(
        find.textContaining("isn't in the saved product list"),
        findsOneWidget,
      );
      expect(find.byKey(const Key('scan-add-to-product')), findsNothing);
      expect(find.byKey(const Key('scan-search-by-name')), findsOneWidget);
      expect(find.text(itemsText(host, 1)), findsOneWidget);
    },
  );

  apiTest('Stop scanning returns focus to the scan icon; Swahili labels', (
    tester,
    api,
  ) async {
    seedPos(api, tools: barcodeTools(), products: scanProducts());
    final host = await pumpPage(
      tester,
      api,
      const PosPage(),
      user: owner,
      lang: 'sw',
      size: const Size(375, 900),
      extraRoutes: salesRoutes,
    );
    expect(find.byTooltip('Skani msimbopau'), findsOneWidget);
    await openScan(tester);
    expect(find.text(host.tr('vendor.scan.hint')), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pos-scan-panel')), findsNothing);
    final icon = tester.widget<IconButton>(find.byKey(const Key('pos-scan')));
    expect(icon.focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
