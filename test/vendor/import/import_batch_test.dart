// Vendor smart import V3: one import's page: mapping_required ("continue on
// a computer"), the checked rows and the choice, the apply loop with its
// waits, the result, retry, "Failed rows", errors.csv, discard, and who may
// do what. The fake server answers everything; no real backend is used.
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/network/browser_online.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_api.dart';
import 'import_support.dart';

const _id = 'vib_1';
const _path = '/vendor/imports/$_id';

Map<String, dynamic> readyBatch({bool? include, Map<String, int>? c}) =>
    batchJson(_id, include: include, counts_: c);

void seed(
  RecordingApi api,
  Map<String, dynamic> batch, {
  List<Map<String, dynamic>>? columns,
}) {
  api.on('GET /vendor/tools/options', importToolsOn);
  api.on('GET $_path', {'batch': batch, 'columns': columns ?? []});
}

/// Preview rows as the server orders them: invalid, failed, needs_review, valid.
final _problemRows = [
  rowJson(
    'r2',
    2,
    name: 'Whey',
    en: 'The price is wrong.',
    sw: 'Bei si sahihi.',
  ),
  rowJson(
    'r3',
    3,
    status: 'needs_review',
    name: 'Tee',
    en: 'Check the price.',
    sw: 'Hakiki bei.',
  ),
  rowJson('r4', 4, status: 'valid', name: 'Fine one'),
];

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => BrowserOnline.debugSet(true));

  group('mapping_required', () {
    apiTest('says to continue on a computer and edits nothing', (
      tester,
      api,
    ) async {
      seed(
        api,
        batchJson(_id, status: 'mapping_required', counts_: counts(total: 5)),
        columns: [
          columnJson('Bidhaa', 'name', 'synonym', sample: ['Whey']),
          columnJson('Bei ya kuuza', 'price_tzs', 'synonym'),
          columnJson('Notes', null, 'none'),
          columnJson('Idadi', 'stock', 'fuzzy'),
        ],
      );
      final host = await pumpBatch(tester, api);
      expect(find.byKey(const Key('import-mapping-required')), findsOneWidget);
      expect(
        find.textContaining(host.tr('vendor.import.mapping.title')),
        findsOneWidget,
      );
      expect(
        find.textContaining('FitFlex vendor portal on a computer'),
        findsOneWidget,
      );
      // No URL is hard-coded in the message.
      expect(find.textContaining('http'), findsNothing);
      // The columns are shown read-only, in words.
      expect(find.text('Bidhaa'), findsOneWidget);
      expect(find.text('Used for: Name'), findsOneWidget);
      expect(find.text('Used for: Price (TSh)'), findsOneWidget);
      expect(
        find.text(host.tr('vendor.import.mapping.unused')),
        findsOneWidget,
      );
      expect(find.text(host.tr('vendor.import.match.fuzzy')), findsOneWidget);
      expect(find.textContaining('price_tzs'), findsNothing);
      // Nothing to apply or map from here.
      expect(find.byKey(const Key('import-apply')), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(api.sent('PUT', '$_path/mapping'), isFalse);
      expect(api.sent('GET', '$_path/preview'), isFalse);
      // It can still be thrown away.
      expect(find.byKey(const Key('import-discard')), findsOneWidget);
    });

    apiTest('the message is Swahili in Swahili at 320 px, large text', (
      tester,
      api,
    ) async {
      seed(
        api,
        batchJson(_id, status: 'mapping_required'),
        columns: [
          columnJson('Bidhaa', 'name', 'fuzzy', sample: ['Whey']),
        ],
      );
      await pumpBatch(
        tester,
        api,
        lang: 'sw',
        size: const Size(320, 740),
        textScale: 1.3,
      );
      expect(find.textContaining('Endelea kwenye kompyuta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ready', () {
    Future<PageHost> open(
      WidgetTester tester,
      RecordingApi api, {
      String lang = 'en',
      Map<String, dynamic>? batch,
      Size size = const Size(360, 900),
      double scale = 1.0,
      Map<String, dynamic> user = ownerUser,
    }) async {
      seed(api, batch ?? readyBatch());
      api.on(
        'GET $_path/preview',
        previewJson(batch ?? readyBatch(), _problemRows),
      );
      return pumpBatch(
        tester,
        api,
        lang: lang,
        size: size,
        textScale: scale,
        user: user,
      );
    }

    apiTest(
      'counts, problem rows with the server text, and an off-by-default choice',
      (tester, api) async {
        final host = await open(tester, api);
        expect(find.byKey(const Key('import-count-0')), findsOneWidget);
        expect(find.text('7'), findsOneWidget); // valid rows
        expect(find.text('2'), findsWidgets); // rows to review
        expect(find.text('10'), findsOneWidget);
        expect(find.text('Rows to import: 7'), findsOneWidget);
        // Problem rows only, in the server's order, in the active language.
        expect(find.text('The price is wrong.'), findsOneWidget);
        expect(find.text('Check the price.'), findsOneWidget);
        expect(find.text('Fine one'), findsNothing);
        expect(
          verticalOrder(tester, ['The price is wrong.', 'Check the price.']),
          ['The price is wrong.', 'Check the price.'],
        );
        expect(find.text('Row 2'), findsOneWidget);
        final sw = tester.widget<SwitchListTile>(
          find.byKey(const Key('import-include-review')),
        );
        expect(sw.value, isFalse);
        expect(
          find.text(host.tr('vendor.import.confirm.products')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('import-errors-csv')), findsOneWidget);
        expect(find.textContaining('price_invalid'), findsNothing);
      },
    );

    apiTest('Swahili uses the server Swahili text', (tester, api) async {
      await open(tester, api, lang: 'sw');
      expect(find.text('Bei si sahihi.'), findsOneWidget);
      expect(find.text('Hakiki bei.'), findsOneWidget);
      expect(find.text('Safu mlalo za kuingiza: 7'), findsOneWidget);
      expect(find.text('Safu mlalo 2'), findsOneWidget);
    });

    for (final w in [320.0, 375.0]) {
      apiTest('Swahili at ${w.toInt()} px with large text does not clip', (
        tester,
        api,
      ) async {
        await open(tester, api, lang: 'sw', size: Size(w, 740), scale: 1.3);
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('import-apply')), findsOneWidget);
      });
    }

    apiTest('nothing ready: Apply is off and the file must be fixed', (
      tester,
      api,
    ) async {
      final b = readyBatch(
        c: counts(total: 3, valid: 0, needsReview: 0, invalid: 3),
      );
      final host = await open(tester, api, batch: b);
      expect(
        find.text(host.tr('vendor.import.check.nothingReady')),
        findsOneWidget,
      );
      expect(isEnabled(tester, find.byKey(const Key('import-apply'))), isFalse);
    });

    apiTest(
      'apply sends the choice, loops until nothing remains, then shows the result',
      (tester, api) async {
        await open(tester, api);
        final steps = [
          applyJson(
            batchJson(
              _id,
              status: 'ready',
              include: false,
              counts_: counts(applied: 4, pending: 6),
            ),
            processed: 4,
            remaining: 3,
          ),
          applyJson(
            batchJson(
              _id,
              status: 'applied',
              include: false,
              counts_: counts(
                applied: 7,
                pending: 0,
                needsReview: 2,
                invalid: 1,
              ),
            ),
            processed: 3,
            remaining: 0,
          ),
        ];
        var i = 0;
        api.onCall('POST $_path/apply', (_) => steps[i++]);
        api.on(
          'GET $_path/preview',
          previewJson(batchJson(_id, status: 'applied'), [
            _problemRows[0],
            _problemRows[1],
          ]),
        );
        final host = await pumpBatchAgain(tester, api);
        await tapVisible(tester, find.byKey(const Key('import-apply')));
        final calls = api.where('POST', '$_path/apply');
        expect(calls, hasLength(2));
        expect((calls.first.body as Map)['includeNeedsReview'], false);
        expect((calls.last.body as Map)['includeNeedsReview'], false);
        // The result.
        expect(
          find.text(host.tr('vendor.import.result.applied')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('import-result-0')), findsOneWidget);
        expect(
          find.text(host.tr('vendor.import.result.products')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('import-to-products')), findsOneWidget);
        expect(find.byKey(const Key('import-retry')), findsNothing);
      },
    );

    apiTest('"also import rows that need review" is sent when switched on', (
      tester,
      api,
    ) async {
      await open(tester, api);
      final done = applyJson(
        batchJson(
          _id,
          status: 'applied',
          include: true,
          counts_: counts(applied: 9, pending: 0),
        ),
      );
      api.on('POST $_path/apply', done);
      api.on(
        'GET $_path/preview',
        previewJson(batchJson(_id, status: 'applied'), []),
      );
      final host = await pumpBatchAgain(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-include-review')));
      expect(find.text('Rows to import: 9'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('import-apply')));
      expect(
        (api.only('POST', '$_path/apply').body as Map)['includeNeedsReview'],
        true,
      );
      expect(
        find.text(host.tr('vendor.import.result.applied')),
        findsOneWidget,
      );
    });

    apiTest('409 apply_in_progress, then finished: shows the result', (
      tester,
      api,
    ) async {
      await open(tester, api);
      var n = 0;
      api.onCall(
        'POST $_path/apply',
        (_) => n++ == 0
            ? const RawResponse(
                409,
                '{"error":"apply_in_progress","message":{"en":"Busy.","sw":"Shughuli."}}',
              )
            : applyJson(
                batchJson(
                  _id,
                  status: 'applied',
                  counts_: counts(applied: 7, pending: 0),
                ),
              ),
      );
      api.onCall(
        'GET $_path',
        (_) => {
          'batch': batchJson(
            _id,
            status: 'applying',
            counts_: counts(applied: 3, pending: 4),
          ),
          'columns': [],
        },
      );
      api.on(
        'GET $_path/preview',
        previewJson(batchJson(_id, status: 'applied'), []),
      );
      final host = await pumpBatchAgain(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-apply')));
      expect(api.where('POST', '$_path/apply'), hasLength(2));
      expect(
        find.text(host.tr('vendor.import.result.applied')),
        findsOneWidget,
      );
      expect(find.text('Busy.'), findsNothing);
    });

    apiTest('import_busy and 429 are waited out; no raw code is shown', (
      tester,
      api,
    ) async {
      await open(tester, api);
      var n = 0;
      api.onCall('POST $_path/apply', (_) {
        n++;
        if (n == 1) {
          return const RawResponse(
            503,
            '{"error":"import_busy","retryAfterSeconds":5}',
          );
        }
        if (n == 2) {
          return const RawResponse(
            429,
            '{"error":"rate_limited","retryAfterSeconds":2}',
          );
        }
        return applyJson(
          batchJson(
            _id,
            status: 'applied',
            counts_: counts(applied: 7, pending: 0),
          ),
        );
      });
      api.on(
        'GET $_path/preview',
        previewJson(batchJson(_id, status: 'applied'), []),
      );
      final host = await pumpBatchAgain(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-apply')));
      expect(n, 3);
      expect(
        find.text(host.tr('vendor.import.result.applied')),
        findsOneWidget,
      );
      expect(find.textContaining('import_busy'), findsNothing);
      expect(find.textContaining('rate_limited'), findsNothing);
    });

    apiTest('a server that stays busy ends in a calm pause with Continue', (
      tester,
      api,
    ) async {
      await open(tester, api);
      api.onCall(
        'POST $_path/apply',
        (_) => const RawResponse(503, '{"error":"import_busy"}'),
      );
      final host = await pumpBatchAgain(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-apply')));
      expect(find.byKey(const Key('import-paused')), findsOneWidget);
      expect(find.text(host.tr('vendor.import.paused.busy')), findsOneWidget);
      expect(find.byKey(const Key('import-run-error')), findsNothing);
      // Continue is offered and works once the server has room again.
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
      api.on(
        'GET $_path/preview',
        previewJson(batchJson(_id, status: 'applied'), []),
      );
      expect(
        find.text(host.tr('vendor.import.confirm.continue')),
        findsOneWidget,
      );
      await tapVisible(tester, find.byKey(const Key('import-apply')));
      expect(
        find.text(host.tr('vendor.import.result.applied')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('import-paused')), findsNothing);
    });

    apiTest('a proxy error page (no JSON) is a calm server message', (
      tester,
      api,
    ) async {
      await open(tester, api);
      api.fail('POST $_path/apply', 502); // a proxy page, no JSON
      // No code in the answer: a refusal with calm text. A dropped
      // connection (waited out) is covered by the state-machine tests.
      final host = await pumpBatchAgain(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-apply')));
      expect(find.text(host.tr('vendor.import.err.server')), findsOneWidget);
    });

    apiTest('one apply call may take longer than the usual 12 seconds', (
      tester,
      api,
    ) async {
      await open(tester, api);
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
      api.on(
        'GET $_path/preview',
        previewJson(batchJson(_id, status: 'applied'), []),
      );
      final host = await pumpBatchAgain(tester, api);
      await tester.ensureVisible(find.byKey(const Key('import-apply')));
      await tester.tap(find.byKey(const Key('import-apply')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 40));
      // Still waiting for the one answer: no timeout error, no second call.
      expect(find.byKey(const Key('import-progress')), findsOneWidget);
      expect(find.byKey(const Key('import-run-error')), findsNothing);
      expect(find.byKey(const Key('import-paused')), findsNothing);
      expect(api.where('POST', '$_path/apply'), hasLength(1));
      hold.complete();
      await tester.pumpAndSettle();
      expect(
        find.text(host.tr('vendor.import.result.applied')),
        findsOneWidget,
      );
    });

    apiTest('offline: says so and sends nothing', (tester, api) async {
      await open(tester, api);
      BrowserOnline.debugSet(false);
      final host = await pumpBatchAgain(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-apply')));
      expect(find.text(host.tr('vendor.import.offline')), findsOneWidget);
      expect(api.sent('POST', '$_path/apply'), isFalse);
    });

    apiTest('a refused apply (not owner for a profile) shows the server text', (
      tester,
      api,
    ) async {
      await open(tester, api);
      api.fail('POST $_path/apply', 403, {
        'error': 'profile_import_owner_only',
        'message': {
          'en': 'Only the account holder can import the business profile.',
          'sw': 'Ni mmiliki pekee.',
        },
      });
      await pumpBatchAgain(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-apply')));
      expect(
        find.text('Only the account holder can import the business profile.'),
        findsOneWidget,
      );
    });

    apiTest('discard from the page asks first and returns to the list', (
      tester,
      api,
    ) async {
      final host = await open(tester, api);
      api.on('POST $_path/discard', {
        'batch': batchJson(_id, status: 'discarded'),
      });
      await tapVisible(tester, find.byKey(const Key('import-discard')));
      await tapVisible(
        tester,
        buttonLabelled(host.tr('vendor.import.discard.cancel')),
      );
      expect(api.sent('POST', '$_path/discard'), isFalse);
      await tapVisible(tester, find.byKey(const Key('import-discard')));
      await tapVisible(tester, find.byKey(const Key('import-discard-confirm')));
      expect(api.sent('POST', '$_path/discard'), isTrue);
      expect(find.text('ROUTE-IMPORT-LIST'), findsOneWidget);
    });

    apiTest(
      'discard refused (rows tried meanwhile): server text, page reloads',
      (tester, api) async {
        final host = await open(tester, api);
        api.fail('POST $_path/discard', 409, {'error': 'not_discardable'});
        await tapVisible(tester, find.byKey(const Key('import-discard')));
        await tapVisible(
          tester,
          find.byKey(const Key('import-discard-confirm')),
        );
        expect(
          host.snack(host.tr('vendor.import.err.notDiscardable')),
          findsOneWidget,
        );
        expect(api.where('GET', _path), hasLength(1));
      },
    );
  });

  group('resuming', () {
    apiTest('a half-done batch continues where it stopped', (
      tester,
      api,
    ) async {
      final b = batchJson(
        _id,
        include: false,
        counts_: counts(applied: 4, failed: 1, pending: 5),
      );
      seed(api, b);
      api.on(
        'POST $_path/apply',
        applyJson(
          batchJson(
            _id,
            status: 'applied',
            include: false,
            counts_: counts(applied: 9, failed: 1, pending: 0),
          ),
        ),
      );
      api.on(
        'GET $_path/preview',
        previewJson(batchJson(_id, status: 'applied'), []),
      );
      final host = await pumpBatch(tester, api);
      expect(find.byKey(const Key('import-resume')), findsOneWidget);
      expect(find.byKey(const Key('import-include-review')), findsNothing);
      expect(
        find.text(host.tr('vendor.import.continue.imported')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('import-discard')), findsNothing);
      expect(find.byKey(const Key('import-retry')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('import-apply')));
      expect(api.where('POST', '$_path/apply'), hasLength(1));
      expect(find.text(host.tr('vendor.import.result.partial')), findsNothing);
    });

    apiTest('the first choice stays fixed on a started batch', (
      tester,
      api,
    ) async {
      final b = batchJson(
        _id,
        include: true,
        counts_: counts(applied: 4, pending: 5),
      );
      seed(api, b);
      api.on(
        'POST $_path/apply',
        applyJson(
          batchJson(
            _id,
            status: 'applied',
            include: true,
            counts_: counts(applied: 9, pending: 0),
          ),
        ),
      );
      api.on(
        'GET $_path/preview',
        previewJson(batchJson(_id, status: 'applied'), []),
      );
      await pumpBatch(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-apply')));
      expect(
        (api.only('POST', '$_path/apply').body as Map)['includeNeedsReview'],
        true,
      );
    });
  });

  group('result', () {
    final partial = batchJson(
      _id,
      status: 'partial',
      include: false,
      counts_: counts(applied: 6, failed: 1, pending: 0),
    );
    final failedRow = rowJson(
      'r9',
      9,
      status: 'valid',
      applyState: 'failed',
      name: 'Gym bag',
      lastError: {
        'code': 'sku_exists',
        'message': {
          'en': 'A product with this SKU was added.',
          'sw': 'Bidhaa yenye SKU hii iliongezwa.',
        },
      },
    );
    final ordered = [_problemRows[0], failedRow, _problemRows[1]];

    apiTest('partial: counts, retry, errors file, and the rows to check', (
      tester,
      api,
    ) async {
      seed(api, partial);
      api.on('GET $_path/preview', previewJson(partial, ordered));
      final host = await pumpBatch(tester, api);
      expect(
        find.text(host.tr('vendor.import.result.partial')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('import-retry')), findsOneWidget);
      expect(find.byKey(const Key('import-errors-csv')), findsOneWidget);
      expect(find.text('A product with this SKU was added.'), findsOneWidget);
      expect(find.text('The price is wrong.'), findsOneWidget);
      expect(
        find.text(host.tr('vendor.import.rowStatus.failed')),
        findsWidgets,
      );
      expect(
        find.text(host.tr('vendor.import.result.products')),
        findsOneWidget,
      );
    });

    apiTest('retry failed rows calls /retry and shows the new result', (
      tester,
      api,
    ) async {
      seed(api, partial);
      api.on('GET $_path/preview', previewJson(partial, ordered));
      api.on(
        'POST $_path/retry',
        applyJson(
          batchJson(
            _id,
            status: 'applied',
            include: false,
            counts_: counts(applied: 7, failed: 0, pending: 0),
          ),
        ),
      );
      final host = await pumpBatch(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-retry')));
      expect(api.sent('POST', '$_path/retry'), isTrue);
      expect(
        find.text(host.tr('vendor.import.result.applied')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('import-retry')), findsNothing);
    });

    apiTest('a retry in progress keeps the result on screen with progress', (
      tester,
      api,
    ) async {
      seed(api, partial);
      api.on('GET $_path/preview', previewJson(partial, ordered));
      final hold = api.hold('POST $_path/retry');
      api.on(
        'POST $_path/retry',
        applyJson(
          batchJson(
            _id,
            status: 'applied',
            include: false,
            counts_: counts(applied: 7, failed: 0, pending: 0),
          ),
        ),
      );
      final host = await pumpBatch(tester, api);
      await tester.ensureVisible(find.byKey(const Key('import-retry')));
      await tester.tap(find.byKey(const Key('import-retry')));
      await tester.pump();
      expect(find.byKey(const Key('import-progress')), findsOneWidget);
      expect(
        find.text(host.tr('vendor.import.result.partial')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('import-apply')), findsNothing);
      hold.complete();
      await tester.pumpAndSettle();
      expect(
        find.text(host.tr('vendor.import.result.applied')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('import-progress')), findsNothing);
    });

    apiTest('batch_expired on retry: calm explanation, no retry button', (
      tester,
      api,
    ) async {
      seed(api, partial);
      api.on('GET $_path/preview', previewJson(partial, ordered));
      api.fail('POST $_path/retry', 409, {
        'error': 'batch_expired',
        'message': {
          'en': 'This import ended more than 30 days ago.',
          'sw': 'Uingizaji uliisha.',
        },
      });
      final host = await pumpBatch(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-retry')));
      expect(find.byKey(const Key('import-expired')), findsOneWidget);
      expect(
        find.textContaining('This import ended more than 30 days ago.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(host.tr('vendor.import.expired.title')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('import-retry')), findsNothing);
      expect(find.textContaining('batch_expired'), findsNothing);
    });

    apiTest('"Failed rows" asks the server and lists only failed rows', (
      tester,
      api,
    ) async {
      seed(api, partial);
      api.onCall(
        'GET $_path/preview',
        (r) => r.query.contains('applyState=failed')
            ? previewJson(partial, [failedRow])
            : previewJson(partial, ordered),
      );
      final host = await pumpBatch(tester, api);
      expect(find.byKey(const Key('import-rows-failed')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('import-rows-failed')));
      expect(
        api.where('GET', '$_path/preview').last.query,
        contains('applyState=failed'),
      );
      expect(find.text('A product with this SKU was added.'), findsOneWidget);
      expect(find.text('The price is wrong.'), findsNothing);
      await tapVisible(tester, find.byKey(const Key('import-rows-all')));
      expect(find.text('The price is wrong.'), findsOneWidget);
      expect(host.lang, 'en');
    });

    apiTest('a server that ignores the filter: the filter is hidden', (
      tester,
      api,
    ) async {
      seed(api, partial);
      // Always answers every row, whatever is asked.
      api.on('GET $_path/preview', previewJson(partial, ordered));
      await pumpBatch(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-rows-failed')));
      expect(find.byKey(const Key('import-rows-failed')), findsNothing);
      expect(find.byKey(const Key('import-rows-all')), findsNothing);
      // The plain list stays, nothing mislabelled as "failed".
      expect(find.text('The price is wrong.'), findsOneWidget);
      expect(find.text('A product with this SKU was added.'), findsOneWidget);
    });

    apiTest('no failed rows: no filter at all', (tester, api) async {
      final b = batchJson(
        _id,
        status: 'applied',
        counts_: counts(applied: 7, pending: 0),
      );
      seed(api, b);
      api.on('GET $_path/preview', previewJson(b, [_problemRows[0]]));
      await pumpBatch(tester, api);
      expect(find.byKey(const Key('import-rows-failed')), findsNothing);
    });

    apiTest('rows load a page at a time with Show more', (tester, api) async {
      seed(api, partial);
      api.onCall(
        'GET $_path/preview',
        (r) => r.query.contains('cursor=n1')
            ? previewJson(partial, [
                rowJson('r5', 5, name: 'Second page', en: 'Also wrong.'),
              ])
            : previewJson(partial, [
                rowJson('r2', 2, name: 'First page', en: 'Wrong.'),
              ], next: 'n1'),
      );
      await pumpBatch(tester, api);
      expect(find.text('Also wrong.'), findsNothing);
      await tapVisible(tester, find.byKey(const Key('import-rows-more')));
      expect(find.text('Also wrong.'), findsOneWidget);
      expect(find.byKey(const Key('import-rows-more')), findsNothing);
    });

    apiTest('errors.csv is fetched signed in and handed on (web download)', (
      tester,
      api,
    ) async {
      seed(api, partial);
      api.on('GET $_path/preview', previewJson(partial, ordered));
      api.on('GET $_path/errors.csv', 'row,field\r\n2,price_tzs\r\n');
      final sent = captureDeliveries(web: true);
      await pumpBatch(tester, api);
      await tapVisible(tester, find.byKey(const Key('import-errors-csv')));
      final req = api.only('GET', '$_path/errors.csv');
      expect(req.headers['authorization'], 'Bearer token');
      expect(sent.single.name, 'import-vib_1-errors.csv');
      expect(sent.single.text, startsWith('row,field'));
    });

    apiTest(
      'errors.csv on a phone goes to the share sheet; a refusal is calm',
      (tester, api) async {
        seed(api, partial);
        api.on('GET $_path/preview', previewJson(partial, ordered));
        api.fail('GET $_path/errors.csv', 429, {'error': 'rate_limited'});
        final sent = captureDeliveries(web: false);
        final host = await pumpBatch(tester, api);
        await tapVisible(tester, find.byKey(const Key('import-errors-csv')));
        expect(sent, isEmpty);
        expect(
          host.snack(host.tr('vendor.import.err.rateLimited')),
          findsOneWidget,
        );
      },
    );

    apiTest('inventory and profile results say what happened to them', (
      tester,
      api,
    ) async {
      final inv = batchJson(
        _id,
        entity: 'inventory',
        status: 'applied',
        counts_: counts(applied: 7, pending: 0, invalid: 0, needsReview: 0),
      );
      seed(api, inv);
      final host = await pumpBatch(tester, api);
      expect(
        find.text(host.tr('vendor.import.result.inventory')),
        findsOneWidget,
      );
      expect(find.text(host.tr('vendor.import.result.products')), findsNothing);
      expect(find.byKey(const Key('import-to-products')), findsOneWidget);
    });

    apiTest('a profile import has no Products link', (tester, api) async {
      final b = batchJson(
        _id,
        entity: 'profile',
        status: 'applied',
        counts_: counts(
          total: 1,
          applied: 1,
          pending: 0,
          valid: 1,
          invalid: 0,
          needsReview: 0,
        ),
      );
      seed(api, b);
      final host = await pumpBatch(tester, api);
      expect(
        find.text(host.tr('vendor.import.result.profile')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('import-to-products')), findsNothing);
    });

    for (final w in [320.0, 375.0]) {
      apiTest(
        'Swahili result at ${w.toInt()} px with large text does not clip',
        (tester, api) async {
          seed(api, partial);
          api.on('GET $_path/preview', previewJson(partial, ordered));
          await pumpBatch(
            tester,
            api,
            lang: 'sw',
            size: Size(w, 740),
            textScale: 1.3,
          );
          expect(find.text('Uingizaji umekamilika kwa sehemu'), findsOneWidget);
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -3000),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Bidhaa yenye SKU hii iliongezwa.'), findsOneWidget);
        },
      );
    }
  });

  group('who may do what', () {
    apiTest(
      'staff cannot import the business profile: apply and retry are off',
      (tester, api) async {
        final b = batchJson(
          _id,
          entity: 'profile',
          counts_: counts(total: 1, valid: 1, needsReview: 0, invalid: 0),
        );
        seed(api, b);
        final host = await pumpBatch(tester, api, user: staffUser(['import']));
        expect(find.byKey(const Key('import-owner-only')), findsOneWidget);
        expect(
          find.text(host.tr('vendor.import.profileOwnerOnly')),
          findsWidgets,
        );
        expect(
          isEnabled(tester, find.byKey(const Key('import-apply'))),
          isFalse,
        );
        expect(api.sent('POST', '$_path/apply'), isFalse);
      },
    );

    apiTest('the owner can apply a profile import', (tester, api) async {
      final b = batchJson(
        _id,
        entity: 'profile',
        counts_: counts(total: 1, valid: 1, needsReview: 0, invalid: 0),
      );
      seed(api, b);
      await pumpBatch(tester, api);
      expect(find.byKey(const Key('import-owner-only')), findsNothing);
      expect(isEnabled(tester, find.byKey(const Key('import-apply'))), isTrue);
    });

    apiTest('staff may apply products', (tester, api) async {
      seed(api, readyBatch());
      api.on('GET $_path/preview', previewJson(readyBatch(), []));
      await pumpBatch(tester, api, user: staffUser(['import']));
      expect(isEnabled(tester, find.byKey(const Key('import-apply'))), isTrue);
    });

    apiTest('tool off: leaves; nothing is read', (tester, api) async {
      api.on('GET /vendor/tools/options', importToolsOff);
      await pumpBatch(tester, api);
      expect(find.text('ROUTE-VENDOR-HOME'), findsOneWidget);
      expect(api.sent('GET', _path), isFalse);
    });
  });

  group('other states', () {
    apiTest('an unknown id is a calm "not found" with retry, no code', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', importToolsOn);
      api.fail('GET $_path', 404, {
        'error': 'import_not_found',
        'message': {
          'en': 'Import not found.',
          'sw': 'Uingizaji haujapatikana.',
        },
      });
      await pumpBatch(tester, api);
      expect(find.byKey(const Key('import-batch-error')), findsOneWidget);
      expect(find.text('Import not found.'), findsOneWidget);
      expect(find.textContaining('import_not_found'), findsNothing);
    });

    apiTest('a discarded import says so', (tester, api) async {
      seed(api, batchJson(_id, status: 'discarded'));
      final host = await pumpBatch(tester, api);
      expect(find.byKey(const Key('import-discarded')), findsOneWidget);
      expect(
        find.text(host.tr('vendor.import.discarded.title')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('import-apply')), findsNothing);
    });

    apiTest('a status this app does not know is explained, not shown raw', (
      tester,
      api,
    ) async {
      seed(api, batchJson(_id, status: 'teleporting'));
      final host = await pumpBatch(tester, api);
      expect(find.byKey(const Key('import-unknown-status')), findsOneWidget);
      expect(
        find.text(host.tr('vendor.import.status.unknown')),
        findsOneWidget,
      );
      expect(find.textContaining('teleporting'), findsNothing);
    });

    apiTest('while applying elsewhere the page offers to continue', (
      tester,
      api,
    ) async {
      seed(
        api,
        batchJson(
          _id,
          status: 'applying',
          counts_: counts(applied: 3, pending: 4),
        ),
      );
      final host = await pumpBatch(tester, api);
      expect(find.byKey(const Key('import-resume')), findsOneWidget);
      expect(
        find.text(host.tr('vendor.import.confirm.continue')),
        findsOneWidget,
      );
    });

    test('FFLocale knows the batch title in both languages', () {
      expect(FFLocale.textOf('en', 'vendor.import.batch.title'), 'Import');
      expect(FFLocale.textOf('sw', 'vendor.import.batch.title'), 'Uingizaji');
    });
  });
}

/// Pumps the batch page again on the same fake (after the seeds changed).
Future<PageHost> pumpBatchAgain(WidgetTester tester, RecordingApi api) async {
  await tester.pumpWidget(const SizedBox());
  return pumpBatch(tester, api);
}
