// Vendor tools · S8, review round on #285: sign-out clears the POS device
// copies (keeps queued sales), the camera never double-starts and stops if
// it was stopped while starting, mobile_scanner is pinned, the iOS camera
// text names product barcodes, lookup-only products are loaded in full,
// "Add this code" never says "added" when the server dropped the code.
import 'dart:async';
import 'dart:io';

import 'package:fitflexmobile/screens/vendor/barcodes/vendor_scan_controller.dart';
import 'package:fitflexmobile/screens/vendor/barcodes/vendor_scan_panel.dart';
import 'package:fitflexmobile/screens/vendor/sales/pos_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recording_api.dart';
import '../walkin_support.dart';
import 'scan_support.dart';

/// A camera whose start waits for [gate].
class _SlowCamera extends FakeScanCamera {
  _SlowCamera(this.gate) : super(startsAs: VendorCameraStatus.error);
  final Completer<void> gate;
  @override
  Future<void> start() async {
    starts += 1;
    await gate.future;
    await super.start();
    starts -= 1; // super.start counted it again
  }
}

void main() {
  setUpAll(loadAppFonts);
  tearDown(FakeCameras.uninstall);

  test(
    'L1: sign-out clears vendor_pos_products/business, keeps the queue',
    () async {
      SharedPreferences.setMockInitialValues({
        'vendor_pos_products.v1': '{"products":[]}',
        'vendor_pos_business.v1': '{}',
        'vendor_sale_queue.v1.v1': '[{"clientRef":"sale_x"}]',
        'vendor_pos_draft.v1.v1': '{}',
      });
      final api = RecordingApi();
      await api.run(() async {
        final auth = AuthState(ApiClient(baseUrl: 'http://fixtures.local'));
        await auth.signIn('jwt', {'id': 'v1', 'userType': 'vendor'});
        await auth.signOut();
      });
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('vendor_pos_products.v1'), isFalse);
      expect(prefs.containsKey('vendor_pos_business.v1'), isFalse);
      expect(prefs.getString('vendor_sale_queue.v1.v1'), isNotNull);
      expect(prefs.getString('vendor_pos_draft.v1.v1'), isNotNull);
    },
  );

  apiTest(
    'L2: paused while starting → stopped after start, no failure kept, one start',
    (tester, api) async {
      final gate = Completer<void>();
      late _SlowCamera cam;
      VendorScanPanel.debugInsecure = false;
      VendorScanPanel.debugCameraFactory = () => cam = _SlowCamera(gate);
      final controller = VendorScanController(index: ProductCodeIndex.empty);
      addTearDown(controller.dispose);
      await pumpPage(
        tester,
        api,
        VendorScanPanel(
          controller: controller,
          memoryScope: 'v1',
          onClose: () {},
          onCode: (_, {required typed}) async => true,
        ),
        settle: false,
      );
      await tester.pump();
      await tester.pump();
      expect(cam.starts, 1);
      // Held (a sheet) and released while still starting: no second start.
      controller.hold();
      await tester.pump();
      controller.release();
      await tester.pump();
      expect(cam.starts, 1);
      controller.hold();
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(cam.stops, greaterThanOrEqualTo(1));
      expect(cam.running, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(VendorScanMemory.key('v1')), isNull);
    },
  );

  test('L3: mobile_scanner pinned to 6.0.11 (pubspec and lock)', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains(RegExp(r'^  mobile_scanner: 6\.0\.11$', multiLine: true)),
    );
    final lock = File('pubspec.lock').readAsStringSync();
    final i = lock.indexOf('  mobile_scanner:');
    expect(
      lock.substring(i, lock.indexOf('\n  ', i + 20) + 200),
      contains('version: "6.0.11"'),
    );
  });

  test('L4: iOS camera text names product barcodes (EN and SW)', () {
    expect(
      File('ios/Runner/Info.plist').readAsStringSync(),
      contains('product barcodes'),
    );
    expect(
      File('ios/Runner/en.lproj/InfoPlist.strings').readAsStringSync(),
      contains('product barcodes'),
    );
    expect(
      File('ios/Runner/sw.lproj/InfoPlist.strings').readAsStringSync(),
      contains('misimbopau ya bidhaa'),
    );
  });

  apiTest('lookup-only product: the list is loaded again before using it', (
    tester,
    api,
  ) async {
    FakeCameras().install();
    var calls = 0;
    seedPos(api, tools: barcodeTools());
    api.onCall('GET /vendor/products', (_) {
      calls += 1;
      return [
        posProduct('p1', 'Whey'),
        if (calls > 1)
          posProduct(
            'p9',
            'New tee',
            stock: 5,
            variants: [
              {'name': 'Red', 'stock': 2},
              {'name': 'Blue', 'stock': 3},
            ],
          ),
      ];
    });
    api.on('GET /vendor/products/lookup', {
      'code': 'TEE-1',
      'codeKey': 'TEE-1',
      'matches': [
        {
          'productId': 'p9',
          'name': 'New tee',
          'variant': null,
          'variants': null,
          'priceTzs': 9000,
          'stock': 5,
          'status': 'active',
          'sku': null,
          'matchedBy': 'barcode',
        },
      ],
    });
    await pumpPage(
      tester,
      api,
      const PosPage(),
      user: const {'id': 'v1', 'userType': 'vendor'},
      size: const Size(400, 1000),
      extraRoutes: salesRoutes,
    );
    expect(calls, 1);
    await tester.tap(find.byKey(const Key('pos-scan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-type')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('scan-type-field')), 'TEE-1');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(calls, 2);
    // Its real variants, from the list (the lookup sent none).
    expect(find.byKey(const Key('pos-variant-Blue')), findsOneWidget);
  });

  apiTest(
    'M-1 Add this code: 200 without barcodes → "not available", never "added"',
    (tester, api) async {
      FakeCameras().install();
      seedPos(
        api,
        tools: barcodeTools(),
        products: [posProduct('p1', 'Whey')..['barcodes'] = []],
      );
      api.on('GET /vendor/products/lookup', {
        'code': 'ZZZZ-1',
        'codeKey': 'ZZZZ-1',
        'matches': [],
      });
      api.on('PUT /vendor/products/p1', posProduct('p1', 'Whey'));
      final host = await pumpPage(
        tester,
        api,
        const PosPage(),
        user: const {'id': 'v1', 'userType': 'vendor'},
        size: const Size(400, 1000),
        extraRoutes: salesRoutes,
      );
      await tester.tap(find.byKey(const Key('pos-scan')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-type')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('scan-type-field')),
        'ZZZZ-1',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      api.clear();
      await tapVisible(tester, find.byKey(const Key('scan-add-to-product')));
      await tester.tap(find.byKey(const Key('scan-add-pick-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-confirm-add')));
      await tester.pumpAndSettle();
      expect(
        host.snack(host.tr('vendor.barcodes.unavailable')),
        findsOneWidget,
      );
      expect(find.text('Code added to Whey.'), findsNothing);
      expect(find.byKey(const Key('pos-scan-panel')), findsNothing);
      expect(api.sent('GET', '/vendor/tools/options'), isTrue);
      expect(find.text(host.tr('vendor.pos.cartEmpty')), findsOneWidget);
    },
  );

  apiTest('POS cache keeps approvalStatus', (tester, api) async {
    FakeCameras().install();
    seedPos(api, tools: barcodeTools());
    await pumpPage(
      tester,
      api,
      const PosPage(),
      user: const {'id': 'v1', 'userType': 'vendor'},
      size: const Size(400, 1000),
      extraRoutes: salesRoutes,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('vendor_pos_products.v1'),
      contains('"approvalStatus":"approved"'),
    );
  });
}
