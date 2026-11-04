// Vendor smart import V3, review round: one result number, what errors.csv
// promises, paging over the server's problem bands (new and old order),
// failed rows buried on an old server, fresh access for staff granted
// `import` later, the staff forms, the long apply timeout, the rate-limit
// wait and the shortened Swahili titles at 320 px.
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/widgets/invitations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_api.dart';
import '../stock_support.dart' show seedVendorHome, stockProduct;
import 'import_support.dart';

const _id = 'vib_1';
const _path = '/vendor/imports/$_id';

void seed(RecordingApi api, Map<String, dynamic> batch) {
  api.on('GET /vendor/tools/options', importToolsOn);
  api.on('GET $_path', {'batch': batch, 'columns': []});
}

Map<String, dynamic> failedRow(String id, int n) => rowJson(
  id,
  n,
  status: 'valid',
  applyState: 'failed',
  name: 'Bag $n',
  lastError: {
    'code': 'sku_exists',
    'message': {'en': 'SKU was added meanwhile.', 'sw': 'SKU iliongezwa.'},
  },
);

void main() {
  setUpAll(loadAppFonts);

  group('K1/K2: result numbers and the errors file', () {
    apiTest('one "not imported" number, no separate Skipped card', (
      tester,
      api,
    ) async {
      final b = batchJson(
        _id,
        status: 'partial',
        include: false,
        // The server marks every leftover row skipped, invalid ones too.
        counts_: counts(applied: 6, failed: 1, pending: 0, skipped: 3),
      );
      seed(api, b);
      api.on('GET $_path/preview', previewJson(b, []));
      final host = await pumpBatch(tester, api);
      expect(find.byKey(const Key('import-result-2')), findsOneWidget);
      expect(find.byKey(const Key('import-result-3')), findsNothing);
      expect(find.text('Skipped'), findsNothing);
      expect(find.text(host.tr('vendor.import.result.notImported')), findsOne);
      expect(find.text('3'), findsOneWidget); // invalid 1 + needs review 2
    });

    apiTest('only failed rows: no errors file is promised; rows are listed', (
      tester,
      api,
    ) async {
      final b = batchJson(
        _id,
        status: 'partial',
        include: false,
        counts_: counts(
          total: 8,
          valid: 8,
          needsReview: 0,
          invalid: 0,
          applied: 6,
          failed: 2,
          pending: 0,
        ),
      );
      seed(api, b);
      api.on(
        'GET $_path/preview',
        previewJson(b, [failedRow('r8', 8), failedRow('r9', 9)]),
      );
      await pumpBatch(tester, api);
      expect(find.byKey(const Key('import-errors-csv')), findsNothing);
      expect(find.byKey(const Key('import-errors-help')), findsNothing);
      expect(find.text('SKU was added meanwhile.'), findsNWidgets(2));
    });

    apiTest('validation problems: the button and help say what is in it', (
      tester,
      api,
    ) async {
      final b = batchJson(
        _id,
        status: 'partial',
        counts_: counts(applied: 6, failed: 1, pending: 0),
      );
      seed(api, b);
      api.on('GET $_path/preview', previewJson(b, [failedRow('r8', 8)]));
      final host = await pumpBatch(tester, api);
      expect(find.byKey(const Key('import-errors-csv')), findsOneWidget);
      final help = host.tr('vendor.import.errorsCsv.help');
      expect(find.text(help), findsOneWidget);
      expect(help, contains('checked'));
      expect(help, contains('on this screen'));
    });
  });

  group('K3/K4: paging over the problem bands', () {
    final partial = batchJson(
      _id,
      status: 'partial',
      include: false,
      counts_: counts(applied: 5, failed: 1, pending: 0),
    );

    apiTest('new order: keeps paging until a ready row is seen', (
      tester,
      api,
    ) async {
      seed(api, partial);
      api.onCall('GET $_path/preview', (r) {
        if (r.query.contains('cursor=c2')) {
          return previewJson(partial, [rowJson('r20', 20, status: 'valid')]);
        }
        if (r.query.contains('cursor=c1')) {
          return previewJson(partial, [
            // An applied one that needed review shares the band with the
            // pending one: it must not end the paging.
            rowJson(
              'r6',
              6,
              status: 'needs_review',
              applyState: 'applied',
              name: 'Done one',
            ),
            rowJson(
              'r7',
              7,
              status: 'needs_review',
              name: 'Pending one',
              en: 'Check it.',
            ),
            rowJson('r30', 30, status: 'valid', name: 'Ready one'),
          ], next: 'c2');
        }
        return previewJson(partial, [
          rowJson('r2', 2, name: 'Bad one', en: 'Wrong.'),
          failedRow('r3', 3),
        ], next: 'c1');
      });
      await pumpBatch(tester, api);
      expect(find.text('Wrong.'), findsOneWidget);
      expect(find.text('SKU was added meanwhile.'), findsOneWidget);
      // Only invalid and failed so far: more pages can still hold problems.
      await tapVisible(tester, find.byKey(const Key('import-rows-more')));
      expect(find.text('Check it.'), findsOneWidget); // pending, not hidden
      expect(find.text('Done one'), findsNothing); // applied: not a problem
      // A ready row was seen: whatever follows is ready too.
      expect(find.byKey(const Key('import-rows-more')), findsNothing);
      expect(find.text('Ready one'), findsNothing);
    });

    apiTest('new order: applied review rows alone never end the paging', (
      tester,
      api,
    ) async {
      seed(api, partial);
      api.onCall('GET $_path/preview', (r) {
        if (r.query.contains('cursor=c1')) {
          return previewJson(partial, [
            rowJson(
              'r9',
              9,
              status: 'needs_review',
              name: 'Pending later',
              en: 'Look.',
            ),
          ]);
        }
        return previewJson(partial, [
          rowJson('r4', 4, status: 'needs_review', applyState: 'applied'),
        ], next: 'c1');
      });
      await pumpBatch(tester, api);
      expect(find.byKey(const Key('import-rows-more')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('import-rows-more')));
      expect(find.text('Look.'), findsOneWidget);
    });

    apiTest('old order: stops at the first ready row (safe behaviour)', (
      tester,
      api,
    ) async {
      seed(api, partial);
      api.on(
        'GET $_path/preview',
        previewJson(partial, [
          rowJson('r2', 2, name: 'Bad one', en: 'Wrong.'),
          rowJson(
            'r3',
            3,
            status: 'needs_review',
            name: 'Pending one',
            en: 'Check it.',
          ),
          rowJson('r4', 4, status: 'valid', applyState: 'applied'),
        ], next: 'c1'),
      );
      await pumpBatch(tester, api);
      expect(find.text('Wrong.'), findsOneWidget);
      expect(find.text('Check it.'), findsOneWidget);
      expect(find.byKey(const Key('import-rows-more')), findsNothing);
    });

    apiTest('failed rows buried on an old server: say so, not a bare number', (
      tester,
      api,
    ) async {
      seed(api, partial);
      api.on(
        'GET $_path/preview',
        previewJson(partial, [
          rowJson('r2', 2, name: 'Bad one', en: 'Wrong.'),
          rowJson('r4', 4, status: 'valid', applyState: 'applied'),
        ], next: 'c1'),
      );
      final host = await pumpBatch(tester, api);
      expect(find.byKey(const Key('import-failed-hidden')), findsOneWidget);
      expect(
        find.text(host.tr('vendor.import.rows.failedHidden')),
        findsOneWidget,
      );
      expect(host.tr('vendor.import.rows.failedHidden'), contains('portal'));
      expect(find.byKey(const Key('import-retry')), findsOneWidget);
    });

    apiTest('failed rows listed: no "hidden" notice', (tester, api) async {
      seed(api, partial);
      api.on('GET $_path/preview', previewJson(partial, [failedRow('r3', 3)]));
      await pumpBatch(tester, api);
      expect(find.byKey(const Key('import-failed-hidden')), findsNothing);
    });
  });

  group('K5: access is refreshed', () {
    apiTest('staff granted `import` after sign-in get in without re-login', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.on('GET /vendor/me', {
        'permissions': ['products', 'import'],
        'vendorRole': 'inventory_manager',
      });
      api.on('GET /vendor/imports', {'batches': [], 'nextCursor': null});
      await pumpHistory(tester, api, user: staffUser(['products']));
      expect(find.byKey(const Key('import-history-empty')), findsOneWidget);
      expect(find.text('ROUTE-VENDOR-HOME'), findsNothing);
    });

    apiTest('/vendor/me unavailable: fails closed', (tester, api) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.fail('GET /vendor/me', 404, {'error': 'feature_disabled'});
      await pumpHistory(tester, api, user: staffUser(['products']));
      expect(find.text('ROUTE-VENDOR-HOME'), findsOneWidget);
      expect(api.sent('GET', '/vendor/imports'), isFalse);
    });

    apiTest('/vendor/me says no import: still turned away', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.on('GET /vendor/me', {
        'permissions': ['products'],
      });
      await pumpHistory(tester, api, user: staffUser(['products']));
      expect(find.text('ROUTE-VENDOR-HOME'), findsOneWidget);
    });
  });

  group('K6: the staff forms offer `import`', () {
    apiTest('VendorStaffForm: only while the tool is on, with a hint', (
      tester,
      api,
    ) async {
      final host = await pumpPage(
        tester,
        api,
        const VendorStaffForm(importTool: true),
        size: const Size(400, 1600),
      );
      expect(find.text(host.tr('vendor.permission.import')), findsOneWidget);
      expect(
        find.text(host.tr('vendor.permission.importHint')),
        findsOneWidget,
      );
      expect(host.tr('vendor.permission.importHint'), contains('Products'));
    });

    apiTest('VendorStaffForm: not offered with the tool off', (
      tester,
      api,
    ) async {
      final host = await pumpPage(
        tester,
        api,
        const VendorStaffForm(),
        size: const Size(400, 1600),
      );
      expect(find.text(host.tr('vendor.permission.import')), findsNothing);
    });

    for (final on in [true, false]) {
      apiTest('invite sheet: import ${on ? 'offered' : 'not offered'}', (
        tester,
        api,
      ) async {
        final host = await pumpPage(
          tester,
          api,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => openInvitePersonSheet(
                context,
                gymId: 'v1',
                role: 'staff',
                orgType: 'vendor',
                vendorImport: on,
              ),
              child: const Text('OPEN'),
            ),
          ),
          size: const Size(400, 1600),
        );
        await tester.tap(find.text('OPEN'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('invite-vendor-permission-import')),
          on ? findsOneWidget : findsNothing,
        );
        if (on) {
          expect(
            find.text(host.tr('vendor.permission.importHint')),
            findsOneWidget,
          );
        }
      });
    }

    apiTest('the labels exist in Swahili too', (tester, api) async {
      // (The form already overflows by under a pixel at 320 px with 130 %
      // text before this change; only the import row is checked here.)
      final host = await pumpPage(
        tester,
        api,
        const VendorStaffForm(importTool: true),
        lang: 'sw',
        size: const Size(360, 1800),
      );
      expect(find.text('Kuingiza data'), findsOneWidget);
      expect(find.text(host.tr('vendor.permission.importHint')), findsOne);
      expect(tester.takeException(), isNull);
    });
  });

  group('K7: a long apply call', () {
    apiTest('still waiting after 140 s: no timeout, no second call', (
      tester,
      api,
    ) async {
      final b = batchJson(_id);
      seed(api, b);
      api.on('GET $_path/preview', previewJson(b, []));
      final hold = api.hold('POST $_path/apply');
      api.on(
        'POST $_path/apply',
        applyJson(
          batchJson(
            _id,
            status: 'applied',
            counts_: counts(applied: 7, pending: 0),
          ),
        ),
      );
      final host = await pumpBatch(tester, api);
      await tester.ensureVisible(find.byKey(const Key('import-apply')));
      await tester.tap(find.byKey(const Key('import-apply')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 140));
      expect(find.byKey(const Key('import-progress')), findsOneWidget);
      expect(find.byKey(const Key('import-paused')), findsNothing);
      expect(find.byKey(const Key('import-run-error')), findsNothing);
      expect(api.where('POST', '$_path/apply'), hasLength(1));
      hold.complete();
      await tester.pumpAndSettle();
      expect(
        find.text(host.tr('vendor.import.result.applied')),
        findsOneWidget,
      );
    });

    apiTest('past 150 s: a calm pause (not an error), Continue offered', (
      tester,
      api,
    ) async {
      final b = batchJson(_id);
      seed(api, b);
      api.on('GET $_path/preview', previewJson(b, []));
      api.hold('POST $_path/apply'); // never answered
      final host = await pumpBatch(tester, api);
      await tester.ensureVisible(find.byKey(const Key('import-apply')));
      await tester.tap(find.byKey(const Key('import-apply')));
      await tester.pump();
      // Five waits of 150 s (the sleep is instant in tests) then the pause.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(seconds: 160));
      }
      expect(find.byKey(const Key('import-paused')), findsOneWidget);
      expect(find.byKey(const Key('import-run-error')), findsNothing);
      expect(
        find.text(host.tr('vendor.import.paused.network')),
        findsOneWidget,
      );
      expect(
        find.text(host.tr('vendor.import.confirm.continue')),
        findsOneWidget,
      );
    });
  });

  group('S6: rate limit wait', () {
    Future<PageHost> limited(
      WidgetTester tester,
      RecordingApi api,
      String body,
    ) async {
      final b = batchJson(_id);
      seed(api, b);
      api.on('GET $_path/preview', previewJson(b, []));
      api.onCall('POST $_path/apply', (_) => RawResponse(429, body));
      final host = await pumpBatch(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-apply')));
      return host;
    }

    apiTest('uses retryAfterSeconds when the server sends it', (
      tester,
      api,
    ) async {
      final host = await limited(
        tester,
        api,
        '{"error":"rate_limited","retryAfterSeconds":20}',
      );
      expect(
        find.text(
          host.tr('vendor.import.paused.rateIn').replaceAll('{n}', '20'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('20 seconds'), findsOneWidget);
    });

    apiTest('generic text otherwise, in Swahili too', (tester, api) async {
      final host = await limited(tester, api, '{"error":"rate_limited"}');
      expect(find.text(host.tr('vendor.import.paused.rate')), findsOneWidget);
      expect(find.textContaining('seconds'), findsNothing);
    });

    apiTest('Swahili seconds', (tester, api) async {
      final b = batchJson(_id);
      seed(api, b);
      api.on('GET $_path/preview', previewJson(b, []));
      api.onCall(
        'POST $_path/apply',
        (_) => const RawResponse(
          429,
          '{"error":"rate_limited","retryAfterSeconds":7}',
        ),
      );
      await pumpBatch(tester, api, lang: 'sw');
      await tapVisible(tester, find.byKey(const Key('import-apply')));
      expect(find.textContaining('baada ya sekunde 7'), findsOneWidget);
    });
  });

  group('S3: Swahili titles at 320 px', () {
    apiTest('app bars and the Business-tab tile do not clip', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.on('GET /vendor/imports', {'batches': [], 'nextCursor': null});
      await pumpHistory(
        tester,
        api,
        lang: 'sw',
        size: const Size(320, 740),
        textScale: 1.3,
      );
      final title = tester.widget<Text>(
        find
            .descendant(of: find.byType(AppBar), matching: find.byType(Text))
            .first,
      );
      expect(title.data, 'Ingiza data');
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    apiTest('the tile on the Business tab', (tester, api) async {
      seedVendorHome(
        api,
        products: [stockProduct('p1', 'Whey')],
        tools: importToolsOn,
      );
      late PageHost host;
      // The Business tab already overflows elsewhere at 320 px with 130 %
      // text (checked with the import tool off); only the tile is judged.
      final errors = await captureFlutterErrors(() async {
        host = await pumpPage(
          tester,
          api,
          const VendorHomePage(),
          lang: 'sw',
          size: const Size(320, 740),
          textScale: 1.3,
          extraRoutes: importRoutes(),
        );
        await tester.tap(find.text(host.tr('vendor.business')).last);
        await tester.pumpAndSettle();
      });
      expect(find.byKey(const Key('vendor-import-entry')), findsOneWidget);
      expect(
        find.text('Ongeza bidhaa, Stock au wasifu kutoka CSV.'),
        findsOneWidget,
      );
      expect(errors.where((e) => e.contains('VendorImportEntryTile')), isEmpty);
      expect(
        tester.getSize(find.byKey(const Key('vendor-import-entry'))).width,
        lessThanOrEqualTo(320),
      );
    });

    apiTest('new import and batch titles', (tester, api) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      await pumpNew(
        tester,
        api,
        lang: 'sw',
        size: const Size(320, 740),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Uingizaji mpya'), findsOneWidget);
    });
  });
}
