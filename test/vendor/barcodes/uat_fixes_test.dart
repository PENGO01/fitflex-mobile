// Vendor tools · S8 UAT on RC (dfe001d): L-1 scan fields keep focus on
// Enter, L-2 offline lookup in the POS, L-3 rate-limit countdown, L-4 copy,
// L-5 form banner, L-6 count notice reset, distinct Receive stepper labels.
import 'package:fitflexmobile/screens/vendor/barcodes/vendor_scan_controller.dart';
import 'package:fitflexmobile/screens/vendor/purchases/receive_stock_page.dart';
import 'package:fitflexmobile/screens/vendor/sales/pos_page.dart';
import 'package:fitflexmobile/screens/vendor/stock/adjust_stock_sheet.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/recording_api.dart';
import '../purchases/purchases_support.dart';
import '../stock_support.dart';
import '../walkin_support.dart';
import 'scan_support.dart';

const owner = {'id': 'v1', 'userType': 'vendor'};
const whey = '6201234567893';

/// Counts how often the focused EditableText under [field] loses focus.
int Function() watchBlurs(WidgetTester tester, Finder field) {
  final node = tester
      .widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      )
      .focusNode;
  var blurs = 0;
  var had = node.hasFocus;
  node.addListener(() {
    if (had && !node.hasFocus) blurs += 1;
    had = node.hasFocus;
  });
  return () => blurs;
}

Future<void> enterAndSubmit(
  WidgetTester tester,
  Finder field,
  String text,
  TextInputAction action,
) async {
  await tester.enterText(field, text);
  await tester.testTextInput.receiveAction(action);
  await tester.pumpAndSettle();
}

Future<PageHost> pumpPos(
  WidgetTester tester,
  RecordingApi api, {
  List<Map<String, dynamic>>? products,
}) {
  seedPos(
    api,
    tools: barcodeTools(),
    products:
        products ??
        [
          posProduct('p1', 'Whey')
            ..['barcodes'] = [
              {'code': whey, 'variant': null},
            ],
        ],
  );
  return pumpPage(
    tester,
    api,
    const PosPage(),
    user: owner,
    size: const Size(400, 1000),
    extraRoutes: salesRoutes,
  );
}

Future<void> openTypeCode(WidgetTester tester, String scanKey) async {
  await tapVisible(tester, find.byKey(Key(scanKey)));
  await tester.tap(find.byKey(const Key('scan-type')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => FakeCameras().install());
  tearDown(FakeCameras.uninstall);

  group('L-1: scan fields keep focus on Enter (no blur + refocus)', () {
    // Not reproduced in Chromium with semantics on (before or after); the
    // framework coalesces unfocus + requestFocus in one frame. These pin the
    // hardening: the fields never ask to unfocus on Enter, and repeated
    // entry keeps working with focus held.
    bool keepsFocus(WidgetTester tester, Finder field) =>
        tester
            .widget<TextField>(
              find.descendant(of: field, matching: find.byType(TextField)),
            )
            .onEditingComplete !=
        null;

    apiTest('POS Type code: 3 entries, never blurred', (tester, api) async {
      final host = await pumpPos(tester, api);
      await openTypeCode(tester, 'pos-scan');
      final field = find.byKey(const Key('scan-type-field'));
      await tester.tap(field);
      await tester.pump();
      expect(keepsFocus(tester, field), isTrue);
      final blurs = watchBlurs(tester, field);
      for (var i = 0; i < 3; i++) {
        await enterAndSubmit(tester, field, whey, TextInputAction.search);
      }
      expect(blurs(), 0);
      expect(
        find.text(host.tr('vendor.pos.items').replaceAll('{n}', '3')),
        findsOneWidget,
      );
    });

    apiTest('POS search (USB scanner): never blurred', (tester, api) async {
      await pumpPos(tester, api);
      final field = find.byKey(const Key('pos-search'));
      await tester.tap(field);
      await tester.pump();
      expect(keepsFocus(tester, field), isTrue);
      final blurs = watchBlurs(tester, field);
      for (var i = 0; i < 2; i++) {
        await enterAndSubmit(tester, field, whey, TextInputAction.search);
      }
      expect(blurs(), 0);
    });

    apiTest('product form Barcode field: 3 entries, never blurred', (
      tester,
      api,
    ) async {
      final form = VendorProductForm(
        product: const {
          'id': 'p1',
          'name': 'Whey',
          'priceTzs': 1000,
          'stock': 1,
          'variants': [],
          'barcodes': [],
        },
        stockLedger: true,
        barcodesOn: true,
        onSave: (_) async => null,
      );
      await pumpPage(
        tester,
        api,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                showFFSheet<bool>(context, title: 'Edit', child: form),
            child: const Text('OPEN'),
          ),
        ),
        user: owner,
        size: const Size(420, 2400),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('vendor-barcode-field'));
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pump();
      expect(keepsFocus(tester, field), isTrue);
      final blurs = watchBlurs(tester, field);
      for (final c in ['5012345678900', '12345670', 'ABC-123']) {
        await enterAndSubmit(tester, field, c, TextInputAction.done);
      }
      expect(blurs(), 0);
      for (final c in ['5012345678900', '12345670', 'ABC-123']) {
        expect(find.byKey(Key('vendor-barcode-row-$c')), findsOneWidget);
      }
    });
  });

  apiTest(
    'L-2: network drops after load → unknown code is "not in the saved list"',
    (tester, api) async {
      api.onCall(
        'GET /vendor/products/lookup',
        (_) => throw http.ClientException('offline'),
      );
      final host = await pumpPos(tester, api);
      await openTypeCode(tester, 'pos-scan');
      await enterAndSubmit(
        tester,
        find.byKey(const Key('scan-type-field')),
        '5012345678900',
        TextInputAction.search,
      );
      expect(api.sent('GET', '/vendor/products/lookup'), isTrue);
      expect(
        find.textContaining("isn't in the saved product list"),
        findsOneWidget,
      );
      expect(find.text(host.tr('vendor.scan.lookupFailed')), findsNothing);
      expect(find.byKey(const Key('scan-add-to-product')), findsNothing);
      expect(find.byKey(const Key('scan-search-by-name')), findsOneWidget);
    },
  );

  test(
    'L-2: other screens still say "Try again" on a network failure',
    () async {
      final c = VendorScanController(
        index: ProductCodeIndex.empty,
        lookup: (_) async => throw http.ClientException('x'),
      );
      expect(
        (await c.handle('5012345678900', typed: true))!.kind,
        ScanOutcomeKind.lookupFailed,
      );
    },
  );

  apiTest('L-3: the rate-limit message counts down and clears', (
    tester,
    api,
  ) async {
    api.fail('GET /vendor/products/lookup', 429, {
      'error': 'rate_limited',
      'retryAfterSeconds': 3,
    });
    await pumpPos(tester, api);
    await openTypeCode(tester, 'pos-scan');
    await enterAndSubmit(
      tester,
      find.byKey(const Key('scan-type-field')),
      '5012345678900',
      TextInputAction.search,
    );
    expect(find.text('Too many scans. Wait 3 seconds.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Too many scans. Wait 2 seconds.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Too many scans. Wait 1 second.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-rate-limited')), findsNothing);
    expect(find.textContaining('Too many scans'), findsNothing);
  });

  test('L-4: the flag-off note says the barcodes above (EN, SW)', () {
    expect(
      FFLocale.textOf('en', 'vendor.barcodes.notSaved'),
      'Your other changes were saved. The barcodes above were not.',
    );
    expect(
      FFLocale.textOf('sw', 'vendor.barcodes.notSaved'),
      contains('hapo juu'),
    );
  });

  apiTest('L-5: removing the refused row clears the banner by Save', (
    tester,
    api,
  ) async {
    final form = VendorProductForm(
      product: const {
        'id': 'p1',
        'name': 'Whey',
        'priceTzs': 1000,
        'stock': 1,
        'variants': [],
        'barcodes': [
          {'code': 'GLV-M', 'variant': null},
          {'code': 'OK-1', 'variant': null},
        ],
      },
      stockLedger: true,
      barcodesOn: true,
      onSave: (_) async => throw ApiException(409, {
        'error': 'barcode_in_use',
        'code': 'GLV-M',
        'productId': 'p2',
        'name': 'Gloves',
        'variant': null,
      }),
    );
    final host = await pumpPage(
      tester,
      api,
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () =>
              showFFSheet<bool>(context, title: 'Edit', child: form),
          child: const Text('OPEN'),
        ),
      ),
      user: owner,
      size: const Size(420, 2400),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('vendor-product-save')));
    expect(find.byKey(const Key('vendor-product-save-error')), findsOneWidget);
    expect(find.text(host.tr('vendor.form.fixErrors')), findsOneWidget);
    await tapVisible(
      tester,
      find.byKey(const Key('vendor-barcode-remove-GLV-M')),
    );
    expect(find.byKey(const Key('vendor-product-save-error')), findsNothing);
  });

  apiTest('L-6: "That\'s {name}" clears when stock_changed resets the count', (
    tester,
    api,
  ) async {
    api.on('GET /vendor/tools/options', barcodeTools());
    final products = [
      stockProduct('p1', 'Whey Protein 1kg', stock: 10)
        ..['barcodes'] = [
          {'code': whey, 'variant': null},
        ],
      stockProduct('p2', 'Gym Gloves', stock: 4)
        ..['barcodes'] = [
          {'code': '12345670', 'variant': null},
        ],
    ];
    api.on('GET /vendor/products', products);
    api.fail('POST /vendor/products/p1/stock-adjustments', 409, {
      'error': 'stock_changed',
      'currentStock': 9,
    });
    await pumpPage(
      tester,
      api,
      Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () => openAdjustStock(
              context,
              product: products.first,
              initialReason: 'count',
            ),
            child: const Text('OPEN'),
          ),
        ),
      ),
      size: const Size(400, 1200),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('adjust-count-scan')));
    await tester.tap(find.byKey(const Key('scan-type')));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('scan-type-field'));
    await enterAndSubmit(tester, field, whey, TextInputAction.search);
    await enterAndSubmit(tester, field, '12345670', TextInputAction.search);
    expect(
      find.text("That's Gym Gloves. Save this count first."),
      findsOneWidget,
    );
    await tapVisible(tester, find.byKey(const Key('adjust-save')));
    expect(find.byKey(const Key('adjust-changed')), findsOneWidget);
    expect(
      find.text("That's Gym Gloves. Save this count first."),
      findsNothing,
    );
  });

  apiTest('Receive: result-row stepper labels differ from the line stepper', (
    tester,
    api,
  ) async {
    seedReceive(api, tools: barcodeTools(walkInSales: false));
    final rows = purchaseProducts()
      ..[0]['barcodes'] = [
        {'code': whey, 'variant': null},
      ];
    api.on('GET /vendor/products', rows);
    final host = await pumpPage(
      tester,
      api,
      ReceiveStockPage(now: () => DateTime.utc(2026, 11, 9, 9)),
      user: ownerUser,
      size: const Size(400, 1400),
      extraRoutes: purchaseRoutes,
    );
    await tapVisible(tester, find.byKey(const Key('purchase-scan')));
    await tester.tap(find.byKey(const Key('scan-type')));
    await tester.pumpAndSettle();
    await enterAndSubmit(
      tester,
      find.byKey(const Key('scan-type-field')),
      whey,
      TextInputAction.search,
    );
    final scanMore = tester
        .widget<IconButton>(find.byKey(const Key('scan-result-more')))
        .tooltip;
    final scanLess = tester
        .widget<IconButton>(find.byKey(const Key('scan-result-less')))
        .tooltip;
    expect(scanMore, 'One more Whey 1kg, last scanned');
    expect(scanLess, 'One fewer Whey 1kg, last scanned');
    expect(
      find.byTooltip(
        host.tr('vendor.purchases.oneMore').replaceAll('{name}', 'Whey 1kg'),
      ),
      findsWidgets,
    );
    expect(
      scanMore,
      isNot(
        host.tr('vendor.purchases.oneMore').replaceAll('{name}', 'Whey 1kg'),
      ),
    );
  });
}
