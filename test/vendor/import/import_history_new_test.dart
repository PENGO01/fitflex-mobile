// Vendor smart import V3: the history list, the new-import screen and the
// entry/gating around them. Everything runs against the RecordingApi fake.
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_api.dart';
import '../stock_support.dart' show seedVendorHome, stockProduct;
import 'import_support.dart';

void main() {
  setUpAll(loadAppFonts);

  group('history', () {
    apiTest('lists my imports with file, kind, date, rows and status', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.on('GET /vendor/imports', {
        'batches': [
          batchJson('vib_1'),
          batchJson(
            'vib_2',
            entity: 'inventory',
            status: 'partial',
            filename: 'stock-count.csv',
            counts_: counts(applied: 5, failed: 2),
          ),
        ],
        'nextCursor': null,
      });
      final host = await pumpHistory(tester, api);
      expect(find.text('products.csv'), findsOneWidget);
      expect(find.text('stock-count.csv'), findsOneWidget);
      expect(find.text('Products · 3 Nov 2026'), findsOneWidget);
      expect(find.text('Stock counts · 3 Nov 2026'), findsOneWidget);
      expect(find.text('Rows: 10'), findsNWidgets(2));
      expect(find.text(host.tr('vendor.import.status.ready')), findsOneWidget);
      expect(
        find.text(host.tr('vendor.import.status.partial')),
        findsOneWidget,
      );
      // Only the untouched import can be discarded from the list.
      expect(find.byKey(const Key('import-discard-vib_1')), findsOneWidget);
      expect(find.byKey(const Key('import-discard-vib_2')), findsNothing);
    });

    apiTest('an empty history says so and offers a new import', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.on('GET /vendor/imports', {'batches': [], 'nextCursor': null});
      final host = await pumpHistory(tester, api);
      expect(find.byKey(const Key('import-history-empty')), findsOneWidget);
      expect(find.text(host.tr('vendor.import.empty.title')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('import-new')));
      expect(find.text('ROUTE-IMPORT-NEW'), findsOneWidget);
    });

    apiTest('a failed load shows a calm error with retry, never a code', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.fail('GET /vendor/imports', 500, {'error': 'internal_error'});
      final host = await pumpHistory(tester, api);
      expect(find.byKey(const Key('import-history-error')), findsOneWidget);
      expect(find.text(host.tr('vendor.import.err.server')), findsOneWidget);
      expect(find.textContaining('internal_error'), findsNothing);
      api.heal('GET /vendor/imports');
      api.on('GET /vendor/imports', {'batches': [], 'nextCursor': null});
      await tapVisible(tester, buttonLabelled(host.tr('common.retry')));
      expect(find.byKey(const Key('import-history-empty')), findsOneWidget);
    });

    apiTest('Show more loads the next page with the cursor', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.onCall('GET /vendor/imports', (r) {
        return r.query.contains('cursor=c1')
            ? {
                'batches': [batchJson('vib_2', filename: 'second.csv')],
                'nextCursor': null,
              }
            : {
                'batches': [batchJson('vib_1')],
                'nextCursor': 'c1',
              };
      });
      await pumpHistory(tester, api);
      expect(find.text('second.csv'), findsNothing);
      await tapVisible(tester, find.byKey(const Key('import-history-more')));
      expect(find.text('second.csv'), findsOneWidget);
      expect(find.byKey(const Key('import-history-more')), findsNothing);
    });

    apiTest('discarding asks first, then reloads', (tester, api) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.on('GET /vendor/imports', {
        'batches': [batchJson('vib_1')],
        'nextCursor': null,
      });
      api.on('POST /vendor/imports/vib_1/discard', {
        'batch': batchJson('vib_1', status: 'discarded'),
      });
      final host = await pumpHistory(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-discard-vib_1')));
      expect(find.text(host.tr('vendor.import.discard.title')), findsOneWidget);
      // Keeping it sends nothing.
      await tapVisible(
        tester,
        buttonLabelled(host.tr('vendor.import.discard.cancel')),
      );
      expect(api.sent('POST', '/vendor/imports/vib_1/discard'), isFalse);
      await tapVisible(tester, find.byKey(const Key('import-discard-vib_1')));
      await tapVisible(tester, find.byKey(const Key('import-discard-confirm')));
      expect(api.sent('POST', '/vendor/imports/vib_1/discard'), isTrue);
      expect(api.where('GET', '/vendor/imports'), hasLength(1));
    });

    apiTest('a refused discard shows the server text in the language', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.on('GET /vendor/imports', {
        'batches': [batchJson('vib_1')],
        'nextCursor': null,
      });
      api.fail('POST /vendor/imports/vib_1/discard', 409, {
        'error': 'not_discardable',
        'message': {
          'en': 'Rows were already imported.',
          'sw': 'Safu mlalo zimeshaingizwa.',
        },
      });
      final host = await pumpHistory(tester, api, lang: 'sw');
      await tapVisible(tester, find.byKey(const Key('import-discard-vib_1')));
      await tapVisible(tester, find.byKey(const Key('import-discard-confirm')));
      expect(host.snack('Safu mlalo zimeshaingizwa.'), findsOneWidget);
    });

    apiTest('tapping an import opens it', (tester, api) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.on('GET /vendor/imports', {
        'batches': [batchJson('vib_1')],
        'nextCursor': null,
      });
      await pumpHistory(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-batch-vib_1')));
      expect(find.text('ROUTE-IMPORT-BATCH vib_1'), findsOneWidget);
    });

    for (final w in [320.0, 375.0]) {
      apiTest('Swahili at ${w.toInt()}px, large text, does not clip', (
        tester,
        api,
      ) async {
        api.on('GET /vendor/tools/options', importToolsOn);
        api.on('GET /vendor/imports', {
          'batches': [
            batchJson(
              'vib_1',
              filename: 'orodha-ya-bidhaa-za-duka-kubwa-sana-2026-novemba.csv',
              entity: 'inventory',
              status: 'mapping_required',
            ),
            batchJson('vib_2', status: 'partial'),
          ],
          'nextCursor': 'more',
        });
        await pumpHistory(
          tester,
          api,
          lang: 'sw',
          size: Size(w, 740),
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.text(
            FFLocale.textOf('sw', 'vendor.import.status.mapping_required')!,
          ),
          findsWidgets,
        );
      });
    }
  });

  group('gating', () {
    apiTest('tool off: the page leaves for the vendor home', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOff);
      await pumpHistory(tester, api);
      expect(find.text('ROUTE-VENDOR-HOME'), findsOneWidget);
      expect(api.sent('GET', '/vendor/imports'), isFalse);
    });

    apiTest('tool answer missing or failing: also off (fail closed)', (
      tester,
      api,
    ) async {
      api.fail('GET /vendor/tools/options', 500);
      await pumpHistory(tester, api);
      expect(find.text('ROUTE-VENDOR-HOME'), findsOneWidget);
      expect(api.sent('GET', '/vendor/imports'), isFalse);
    });

    apiTest('staff without the import permission are turned away', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      final host = await pumpHistory(
        tester,
        api,
        user: staffUser(['products']),
      );
      expect(find.text('ROUTE-VENDOR-HOME'), findsOneWidget);
      expect(api.sent('GET', '/vendor/imports'), isFalse);
      expect(host.snack(host.tr('vendor.import.noAccess')), findsOneWidget);
    });

    apiTest('staff with the permission may open it', (tester, api) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.on('GET /vendor/imports', {'batches': [], 'nextCursor': null});
      await pumpHistory(tester, api, user: staffUser(['import']));
      expect(find.byKey(const Key('import-history-empty')), findsOneWidget);
    });
  });

  group('entry on the Business tab', () {
    Future<PageHost> openBusiness(
      WidgetTester tester,
      RecordingApi api,
      Map<String, dynamic> tools, {
      Map<String, dynamic> user = ownerUser,
    }) async {
      seedVendorHome(api, products: [stockProduct('p1', 'Whey')], tools: tools);
      final host = await pumpPage(
        tester,
        api,
        const VendorHomePage(),
        user: user,
        size: const Size(400, 900),
        extraRoutes: importRoutes(),
      );
      final tab = find.text(host.tr('vendor.business'));
      if (tab.evaluate().isNotEmpty) {
        await tester.tap(tab.last);
        await tester.pumpAndSettle();
      }
      return host;
    }

    apiTest('shown when the tool is on; opens the history', (
      tester,
      api,
    ) async {
      final host = await openBusiness(tester, api, importToolsOn);
      expect(find.byKey(const Key('vendor-import-entry')), findsOneWidget);
      expect(find.text(host.tr('vendor.import.tile')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('vendor-import-entry')));
      expect(find.text('ROUTE-IMPORT-LIST'), findsOneWidget);
    });

    apiTest('hidden when the flag is off or missing', (tester, api) async {
      await openBusiness(tester, api, importToolsOff);
      expect(find.byKey(const Key('vendor-import-entry')), findsNothing);
    });

    apiTest('hidden when the options answer has no import field', (
      tester,
      api,
    ) async {
      await openBusiness(tester, api, {'stockLedger': true});
      expect(find.byKey(const Key('vendor-import-entry')), findsNothing);
    });

    apiTest('hidden for staff who lack the import permission', (
      tester,
      api,
    ) async {
      await openBusiness(
        tester,
        api,
        importToolsOn,
        user: staffUser(['staff', 'products']),
      );
      expect(find.byKey(const Key('vendor-import-entry')), findsNothing);
    });

    apiTest('shown for staff who have it', (tester, api) async {
      await openBusiness(
        tester,
        api,
        importToolsOn,
        user: staffUser(['staff', 'import']),
      );
      expect(find.byKey(const Key('vendor-import-entry')), findsOneWidget);
    });
  });

  group('new import', () {
    apiTest('the owner can pick all three kinds; nothing else is shown first', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      final host = await pumpNew(tester, api);
      expect(find.byKey(const Key('import-entity-products')), findsOneWidget);
      expect(find.byKey(const Key('import-entity-inventory')), findsOneWidget);
      expect(find.byKey(const Key('import-entity-profile')), findsOneWidget);
      expect(find.byKey(const Key('import-pick')), findsNothing);
      expect(find.text(host.tr('vendor.import.needsNetwork')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('import-entity-products')));
      expect(find.byKey(const Key('import-pick')), findsOneWidget);
    });

    apiTest('staff see the profile disabled with the owner-only message', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      final host = await pumpNew(tester, api, user: staffUser(['import']));
      expect(
        find.descendant(
          of: find.byKey(const Key('import-entity-profile')),
          matching: find.text(host.tr('vendor.import.profileOwnerOnly')),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('import-entity-profile')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      // Still nothing chosen: the next step did not open.
      expect(find.byKey(const Key('import-pick')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('import-entity-products')));
      expect(find.byKey(const Key('import-pick')), findsOneWidget);
    });

    apiTest('template: download in the chosen language, with examples', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.on('GET /vendor/imports/template', 'jina,bei_tzs\r\n');
      final sent = captureDeliveries(web: true);
      final host = await pumpNew(tester, api, lang: 'en');
      await tapVisible(
        tester,
        find.byKey(const Key('import-entity-inventory')),
      );
      await tapVisible(
        tester,
        find.text(host.tr('vendor.import.template.swahili')),
      );
      await tapVisible(
        tester,
        find.byKey(const Key('import-template-example')),
      );
      await tapVisible(
        tester,
        find.byKey(const Key('import-template-download')),
      );
      final req = api.only('GET', '/vendor/imports/template');
      expect(req.query, contains('entity=inventory'));
      expect(req.query, contains('lang=sw'));
      expect(req.query, contains('example=1'));
      expect(sent.single.name, 'fitflex-import-inventory-sw.csv');
      expect(sent.single.text, 'jina,bei_tzs\r\n');
      expect(sent.single.mime, 'text/csv');
    });

    apiTest('template defaults to the app language, no examples', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.on('GET /vendor/imports/template', 'x\r\n');
      final sent = captureDeliveries(web: false);
      await pumpNew(tester, api, lang: 'sw');
      await tapVisible(tester, find.byKey(const Key('import-entity-products')));
      await tapVisible(
        tester,
        find.byKey(const Key('import-template-download')),
      );
      final req = api.only('GET', '/vendor/imports/template');
      expect(req.query, contains('lang=sw'));
      expect(req.query, contains('example=0'));
      expect(sent, hasLength(1)); // handed to the share sheet on a phone
    });

    apiTest('a refused template download shows calm text', (tester, api) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.fail('GET /vendor/imports/template', 429, {'error': 'rate_limited'});
      captureDeliveries(web: true);
      final host = await pumpNew(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-entity-products')));
      await tapVisible(
        tester,
        find.byKey(const Key('import-template-download')),
      );
      expect(
        find.text(host.tr('vendor.import.err.rateLimited')),
        findsOneWidget,
      );
    });

    apiTest('uploads the CSV as multipart with entity, then opens the batch', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.on('POST /vendor/imports', {'batch': batchJson('vib_77')});
      await pumpNew(
        tester,
        api,
        pick: pickOf('bidhaa.csv', 'name,price_tzs,stock\nWhey,15000,3\n'),
      );
      await tapVisible(tester, find.byKey(const Key('import-entity-products')));
      expect(
        isEnabled(tester, find.byKey(const Key('import-upload'))),
        isFalse,
      );
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      expect(find.textContaining('bidhaa.csv'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('import-upload')));
      final up = api.only('POST', '/vendor/imports');
      final body = up.body as Map;
      expect(body['multipart'], isTrue);
      expect((body['fields'] as Map)['entity'], 'products');
      expect(body['bytes'], greaterThan(30));
      expect(find.text('ROUTE-IMPORT-BATCH vib_77'), findsOneWidget);
    });

    apiTest('an Excel file is stopped with a "save as CSV" hint', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      final host = await pumpNew(tester, api, pick: pickOf('stock.xlsx', 'PK'));
      await tapVisible(tester, find.byKey(const Key('import-entity-products')));
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      expect(
        find.text(host.tr('vendor.import.file.spreadsheet')),
        findsOneWidget,
      );
      expect(
        isEnabled(tester, find.byKey(const Key('import-upload'))),
        isFalse,
      );
      expect(api.sent('POST', '/vendor/imports'), isFalse);
    });

    apiTest('a file over the server limit is stopped before upload', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', {
        'import': true,
        'importLimits': {'maxBytes': 1048576, 'maxRows': 100},
      });
      final host = await pumpNew(
        tester,
        api,
        pick: pickOf('big.csv', 'x', size: 3 * 1024 * 1024),
      );
      await tapVisible(tester, find.byKey(const Key('import-entity-products')));
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      expect(
        find.text(
          host.tr('vendor.import.file.tooLarge').replaceAll('{mb}', '1'),
        ),
        findsOneWidget,
      );
      expect(
        isEnabled(tester, find.byKey(const Key('import-upload'))),
        isFalse,
      );
    });

    apiTest('an empty file is stopped before upload', (tester, api) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      final host = await pumpNew(tester, api, pick: pickOf('e.csv', ''));
      await tapVisible(tester, find.byKey(const Key('import-entity-products')));
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      expect(find.text(host.tr('vendor.import.file.empty')), findsOneWidget);
    });

    apiTest('a duplicate file links to the earlier import', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.fail('POST /vendor/imports', 409, {
        'error': 'duplicate_file',
        'batchId': 'vib_5',
        'status': 'ready',
        'createdAt': '2026-11-02T08:00:00Z',
        'message': {'en': 'Already uploaded.', 'sw': 'Imeshapakiwa.'},
      });
      final host = await pumpNew(
        tester,
        api,
        pick: pickOf('a.csv', 'a,b\n1,2\n'),
      );
      await tapVisible(tester, find.byKey(const Key('import-entity-products')));
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      await tapVisible(tester, find.byKey(const Key('import-upload')));
      expect(find.text('Already uploaded.'), findsOneWidget);
      expect(find.textContaining('duplicate_file'), findsNothing);
      await tapVisible(tester, find.byKey(const Key('import-open-existing')));
      expect(find.text('ROUTE-IMPORT-BATCH vib_5'), findsOneWidget);
      expect(host.lang, 'en');
    });

    apiTest('server refusals are shown in Swahili with their reason', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.fail('POST /vendor/imports', 415, {
        'error': 'unsupported_file_type',
        'hint': 'binary_or_utf16',
        'message': {'en': 'Only CSV.', 'sw': 'CSV pekee.'},
        'reasonMessage': {'en': 'Not text.', 'sw': 'Si maandishi.'},
      });
      await pumpNew(
        tester,
        api,
        lang: 'sw',
        pick: pickOf('a.csv', 'a,b\n1,2\n'),
      );
      await tapVisible(tester, find.byKey(const Key('import-entity-products')));
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      await tapVisible(tester, find.byKey(const Key('import-upload')));
      expect(find.text('CSV pekee. Si maandishi.'), findsOneWidget);
    });

    apiTest('a failed upload can be tried again', (tester, api) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.fail('POST /vendor/imports', 503);
      await pumpNew(tester, api, pick: pickOf('a.csv', 'a,b\n1,2\n'));
      await tapVisible(tester, find.byKey(const Key('import-entity-products')));
      await tapVisible(tester, find.byKey(const Key('import-pick')));
      await tapVisible(tester, find.byKey(const Key('import-upload')));
      expect(find.byKey(const Key('import-error')), findsOneWidget);
      expect(isEnabled(tester, find.byKey(const Key('import-upload'))), isTrue);
    });

    for (final w in [320.0, 375.0]) {
      apiTest('Swahili at ${w.toInt()}px, large text, does not clip', (
        tester,
        api,
      ) async {
        api.on('GET /vendor/tools/options', importToolsOn);
        await pumpNew(
          tester,
          api,
          lang: 'sw',
          size: Size(w, 740),
          textScale: 1.3,
          pick: pickOf('orodha-ya-bidhaa-za-duka-kubwa-sana.csv', 'a,b\n1,2\n'),
        );
        await tapVisible(
          tester,
          find.byKey(const Key('import-entity-products')),
        );
        await tapVisible(tester, find.byKey(const Key('import-pick')));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
