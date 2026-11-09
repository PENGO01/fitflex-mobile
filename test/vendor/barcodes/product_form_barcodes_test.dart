// Vendor tools · S8 §5.4: the product form's Barcodes section — add and
// remove, validation, For, variant rename / removal, `barcodes` sent only
// with the tool on (never inside a variant), server errors on their row.
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_api.dart';
import 'scan_support.dart';

const owner = {'id': 'v1', 'userType': 'vendor'};

Map<String, dynamic> gloves() => {
  'id': 'p2',
  'name': 'Gym Gloves',
  'priceTzs': 30000,
  'stock': 4,
  'status': 'active',
  'approvalStatus': 'approved',
  'variants': [
    {'name': 'M', 'stock': 4},
    {'name': 'L', 'stock': 0},
  ],
  'barcodes': [
    {'code': '6201234567893', 'variant': null},
    {'code': 'GLV-M', 'variant': 'M'},
    {'code': 'GLV-L', 'variant': 'L'},
  ],
};

/// Opens the ledger form; [onSave] answers each save.
Future<PageHost> openForm(
  WidgetTester tester,
  RecordingApi api,
  List<Map<String, dynamic>> sent, {
  bool barcodesOn = true,
  Map<String, dynamic>? product,
  Object? Function(Map<String, dynamic> body)? onSave,
  String lang = 'en',
}) async {
  final form = VendorProductForm(
    product: product ?? gloves(),
    stockLedger: true,
    canSeeCost: true,
    barcodesOn: barcodesOn,
    onSave: (body) async {
      sent.add(body);
      final error = onSave?.call(body);
      if (error != null) throw error;
    },
  );
  final host = await pumpPage(
    tester,
    api,
    Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => showFFSheet<bool>(context, title: 'Edit', child: form),
        child: const Text('OPEN'),
      ),
    ),
    user: owner,
    lang: lang,
    size: const Size(420, 2600),
  );
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
  return host;
}

Future<void> addCode(WidgetTester tester, String code) async {
  await typeInto(tester, find.byKey(const Key('vendor-barcode-field')), code);
  await tapVisible(tester, find.byKey(const Key('vendor-barcode-add')));
}

Future<void> save(WidgetTester tester) =>
    tapVisible(tester, find.byKey(const Key('vendor-product-save')));

void main() {
  setUpAll(loadAppFonts);
  setUp(() => FakeCameras().install());
  tearDown(FakeCameras.uninstall);

  apiTest('tool off: no section and no barcodes key in the body', (
    tester,
    api,
  ) async {
    final sent = <Map<String, dynamic>>[];
    await openForm(tester, api, sent, barcodesOn: false);
    expect(find.byKey(const Key('vendor-barcodes')), findsNothing);
    await save(tester);
    expect(sent.single.containsKey('barcodes'), isFalse);
  });

  apiTest('stored codes show; the whole list is sent; never inside a variant', (
    tester,
    api,
  ) async {
    final sent = <Map<String, dynamic>>[];
    await openForm(tester, api, sent);
    expect(find.byKey(const Key('vendor-barcode-row-GLV-M')), findsOneWidget);
    await save(tester);
    expect(sent.single['barcodes'], [
      {'code': '6201234567893'},
      {'code': 'GLV-M', 'variant': 'M'},
      {'code': 'GLV-L', 'variant': 'L'},
    ]);
    for (final v in (sent.single['variants'] as List).cast<Map>()) {
      expect(v.containsKey('barcodes'), isFalse);
    }
  });

  apiTest('validation inline, value kept (AC-7)', (tester, api) async {
    final sent = <Map<String, dynamic>>[];
    final host = await openForm(tester, api, sent);
    for (final (code, key) in [
      ('123', 'vendor.barcodes.err.tooShort'),
      ('A${'1' * 48}', 'vendor.barcodes.err.tooLong'),
      ('AB 12', 'vendor.barcodes.err.badChars'),
      ('6201234567891', 'vendor.barcodes.err.checkDigit'),
    ]) {
      await addCode(tester, code);
      expect(find.text(host.tr(key)), findsOneWidget, reason: code);
      expect(
        textOf(tester, find.byKey(const Key('vendor-barcode-field'))),
        code,
      );
    }
    // The same item as a stored code (UPC-A vs its EAN-13 key): duplicate.
    await addCode(tester, '06201234567893');
    expect(find.text(host.tr('vendor.barcodes.err.duplicate')), findsOneWidget);
    // 8 digits are accepted (no EAN-8 check).
    await addCode(tester, '12345670');
    expect(
      find.byKey(const Key('vendor-barcode-row-12345670')),
      findsOneWidget,
    );
  });

  apiTest('the 21st code is refused (max 20)', (tester, api) async {
    final sent = <Map<String, dynamic>>[];
    final product = gloves()
      ..['barcodes'] = [
        for (var i = 0; i < 20; i++) {'code': 'CODE-$i', 'variant': null},
      ];
    final host = await openForm(tester, api, sent, product: product);
    await addCode(tester, 'CODE-20');
    expect(
      find.text(
        host.tr('vendor.barcodes.err.tooMany').replaceAll('{max}', '20'),
      ),
      findsOneWidget,
    );
  });

  apiTest(
    'For a variant; removing a code; variant rename carries codes; removal drops them (AC-10)',
    (tester, api) async {
      final sent = <Map<String, dynamic>>[];
      // S1: a variant still holding stock cannot be renamed, so M has none.
      final product = gloves()
        ..['stock'] = 0
        ..['variants'] = [
          {'name': 'M', 'stock': 0},
          {'name': 'L', 'stock': 0},
        ];
      final host = await openForm(tester, api, sent, product: product);
      await tapVisible(
        tester,
        find.byKey(const Key('vendor-barcode-remove-6201234567893')),
      );
      await tapVisible(tester, find.byType(DropdownButtonFormField<int>));
      await tester.tap(find.text('M').last);
      await tester.pumpAndSettle();
      await addCode(tester, 'NEW-M');
      // Rename M → Medium.
      await typeInto(tester, find.byKey(const Key('variant-name-0')), 'Medium');
      await tester.pumpAndSettle();
      // Remove L (stock 0): its code goes with it.
      await tapVisible(tester, find.byKey(const Key('variant-remove-1')));
      expect(
        find.text(
          host.tr('vendor.barcodes.removedWithVariant').replaceAll('{n}', '1'),
        ),
        findsOneWidget,
      );
      await save(tester);
      expect(sent.single['barcodes'], [
        {'code': 'GLV-M', 'variant': 'Medium'},
        {'code': 'NEW-M', 'variant': 'Medium'},
      ]);
    },
  );

  apiTest(
    '409 barcode_in_use: "Already on Whey" on that row; the form stays (AC-9)',
    (tester, api) async {
      final sent = <Map<String, dynamic>>[];
      await openForm(
        tester,
        api,
        sent,
        onSave: (_) => ApiException(409, {
          'error': 'barcode_in_use',
          'code': 'GLV-M',
          'productId': 'p1',
          'name': 'Whey',
          'variant': null,
        }),
      );
      await save(tester);
      expect(
        find.byKey(const Key('vendor-barcode-error-GLV-M')),
        findsOneWidget,
      );
      expect(find.text('Already on Whey.'), findsOneWidget);
      expect(find.byKey(const Key('vendor-product-save')), findsOneWidget);
    },
  );

  apiTest(
    '409 with no product named (deadlock retry failed): "in use, try again"',
    (tester, api) async {
      final sent = <Map<String, dynamic>>[];
      final host = await openForm(
        tester,
        api,
        sent,
        onSave: (_) => ApiException(409, {
          'error': 'barcode_in_use',
          'code': null,
          'productId': null,
          'name': null,
          'variant': null,
        }),
      );
      await save(tester);
      expect(
        find.text(host.tr('vendor.barcodes.err.inUseRetry')),
        findsOneWidget,
      );
      expect(find.text('Already on .'), findsNothing);
    },
  );

  apiTest('server check-digit error and too_many_barcodes', (
    tester,
    api,
  ) async {
    final sent = <Map<String, dynamic>>[];
    var answer = <String, dynamic>{
      'error': 'invalid_check_digit',
      'code': 'GLV-L',
    };
    final host = await openForm(
      tester,
      api,
      sent,
      onSave: (_) => ApiException(400, answer),
    );
    await save(tester);
    expect(find.byKey(const Key('vendor-barcode-error-GLV-L')), findsOneWidget);
    answer = {'error': 'too_many_barcodes', 'max': 20};
    await save(tester);
    expect(
      find.text(
        host.tr('vendor.barcodes.err.tooMany').replaceAll('{max}', '20'),
      ),
      findsOneWidget,
    );
  });

  apiTest('the scan icon fills the field (Type code in the sheet)', (
    tester,
    api,
  ) async {
    final sent = <Map<String, dynamic>>[];
    await openForm(tester, api, sent);
    await tapVisible(tester, find.byKey(const Key('vendor-barcode-scan')));
    await tester.tap(find.byKey(const Key('scan-type')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('scan-type-field')),
      '5012345678900',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
      textOf(tester, find.byKey(const Key('vendor-barcode-field'))),
      '5012345678900',
    );
  });

  apiTest('Swahili: For and Add stack; nothing overflows', (tester, api) async {
    final sent = <Map<String, dynamic>>[];
    await openForm(tester, api, sent, lang: 'sw');
    expect(find.text('Misimbopau'), findsOneWidget);
    final add = tester.getTopLeft(find.byKey(const Key('vendor-barcode-add')));
    final forField = tester.getTopLeft(
      find.byType(DropdownButtonFormField<int>),
    );
    expect(add.dy, greaterThan(forField.dy));
    expect(tester.takeException(), isNull);
  });
}
