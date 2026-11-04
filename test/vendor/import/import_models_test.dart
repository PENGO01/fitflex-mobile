// Vendor smart import V3: reading the server's answers, the gating rules, the
// file checks, the error wording (never a raw code) and that every string the
// screens use exists in English and Swahili.
import 'dart:io';

import 'package:fitflexmobile/screens/vendor/import/import_errors.dart';
import 'package:fitflexmobile/screens/vendor/import/import_models.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_options.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_support.dart';

String en(String key) => FFLocale.textOf('en', key)!;
String sw(String key) => FFLocale.textOf('sw', key)!;

void main() {
  group('models', () {
    test('a batch is read with its counts and fixed choice', () {
      final b = ImportBatch.from(
        batchJson(
          'vib_1',
          status: 'partial',
          include: true,
          counts_: counts(applied: 6, failed: 1),
        ),
      )!;
      expect(b.status, BatchStatus.partial);
      expect(b.entity, ImportEntity.products);
      expect(b.includes, isTrue);
      expect(b.counts!.applied, 6);
      expect(b.counts!.needsReview, 2);
      expect(b.hasProgress, isTrue);
      expect(b.canDiscard, isFalse);
    });

    test('garbage never throws: unknown status and entity stay neutral', () {
      final b = ImportBatch.from({
        'id': 'x',
        'status': 'teleporting',
        'entity': 'cars',
        'counts': 'many',
      })!;
      expect(b.status, BatchStatus.unknown);
      expect(b.entity, isNull);
      expect(b.counts, isNull);
      expect(b.includeNeedsReview, isNull);
      expect(ImportBatch.from({'status': 'ready'}), isNull);
      expect(ImportBatch.from('nope'), isNull);
      expect(ImportRow.from({'rowNo': 2}), isNull);
    });

    test('discard is offered only before any row was tried', () {
      ImportBatch of(String status, {int applied = 0, int failed = 0}) =>
          ImportBatch.from(
            batchJson(
              'a',
              status: status,
              counts_: counts(applied: applied, failed: failed),
            ),
          )!;
      expect(of('ready').canDiscard, isTrue);
      expect(of('mapping_required').canDiscard, isTrue);
      expect(of('ready', applied: 1).canDiscard, isFalse);
      expect(of('ready', failed: 1).canDiscard, isFalse);
      expect(of('applying').canDiscard, isFalse);
      expect(of('applied').canDiscard, isFalse);
      expect(of('discarded').canDiscard, isFalse);
    });

    test('rows keep the server message in both languages', () {
      final r = ImportRow.from(
        rowJson(
          'r1',
          2,
          name: 'Whey',
          en: 'The price is wrong.',
          sw: 'Bei si sahihi.',
        ),
      )!;
      expect(r.label, 'Whey');
      expect(r.issues.single.message!.of('en'), 'The price is wrong.');
      expect(r.issues.single.message!.of('sw'), 'Bei si sahihi.');
      expect(const LocalText(en: 'Only').of('sw'), 'Only');
      expect(LocalText.from({'en': '', 'sw': ' '}), isNull);
    });

    test('counts: what will be tried and what stays out', () {
      final c = ImportCounts.from(counts())!;
      expect(c.eligible(false), 7);
      expect(c.eligible(true), 9);
      expect(c.notImported(false), 3);
      expect(c.notImported(true), 1);
      expect(c.problems(false), 3);
    });

    test('pages and details tolerate missing lists', () {
      expect(ImportBatchPage.from({}).rows, isEmpty);
      expect(ImportRowsPage.from({'rows': 'x'}).rows, isEmpty);
      expect(ImportDetail.from({}), isNull);
      final d = ImportDetail.from({
        'batch': batchJson('vib_1'),
        'columns': [
          columnJson('Bidhaa', 'name', 'synonym', sample: ['Whey']),
          {'bad': true},
        ],
      })!;
      expect(d.columns.single.match, 'synonym');
      expect(d.columns.single.sample, ['Whey']);
    });
  });

  group('gating (fails closed)', () {
    test('the tool must be exactly true', () {
      for (final v in <Object?>[null, false, 'true', 1, 'yes']) {
        expect(
          VendorTools.fromOptions({'import': v}).dataImport,
          isFalse,
          reason: '$v',
        );
      }
      expect(VendorTools.fromOptions({}).dataImport, isFalse);
      expect(VendorTools.fromOptions({'import': true}).dataImport, isTrue);
      expect(VendorTools.off.dataImport, isFalse);
    });

    test('the permission is needed as well', () {
      const on = VendorTools(dataImport: true);
      expect(importOpen(on, canImport: true), isTrue);
      expect(importOpen(on, canImport: false), isFalse);
      expect(importOpen(VendorTools.off, canImport: true), isFalse);
    });

    test('limits come from the server, with safe fallbacks', () {
      final t = VendorTools.fromOptions({
        'import': true,
        'importLimits': {'maxBytes': 1048576, 'maxRows': 500},
      });
      expect(t.importMaxBytes, 1048576);
      expect(t.importMaxRows, 500);
      for (final bad in <Object?>[
        null,
        'x',
        {'maxBytes': -1, 'maxRows': 0},
      ]) {
        final f = VendorTools.fromOptions({
          'import': true,
          'importLimits': bad,
        });
        expect(f.importMaxBytes, 2 * 1024 * 1024);
        expect(f.importMaxRows, 2000);
      }
    });

    test('only the account holder imports the business profile', () {
      expect(canImportEntity(ImportEntity.profile, isOwner: false), isFalse);
      expect(canImportEntity(ImportEntity.profile, isOwner: true), isTrue);
      expect(canImportEntity(ImportEntity.products, isOwner: false), isTrue);
      expect(canImportEntity(ImportEntity.inventory, isOwner: false), isTrue);
    });
  });

  group('file checks', () {
    const max = 2 * 1024 * 1024;
    test('an Excel file gets its own hint', () {
      for (final n in ['a.xlsx', 'A.XLS', 'b.xlsm', 'c.ods']) {
        expect(
          checkImportFile(name: n, sizeBytes: 10, maxBytes: max),
          ImportFileProblem.spreadsheet,
          reason: n,
        );
      }
    });
    test('empty and too large', () {
      expect(
        checkImportFile(name: 'a.csv', sizeBytes: 0, maxBytes: max),
        ImportFileProblem.empty,
      );
      expect(
        checkImportFile(name: 'a.csv', sizeBytes: max + 1, maxBytes: max),
        ImportFileProblem.tooLarge,
      );
      expect(
        checkImportFile(name: 'a.csv', sizeBytes: max, maxBytes: max),
        isNull,
      );
      expect(
        checkImportFile(name: 'noext', sizeBytes: 5, maxBytes: max),
        isNull,
      );
    });
    test('sizes and names read well', () {
      expect(megabytes(2097152), '2');
      expect(megabytes(1572864), '1.5');
      expect(importFileName(r'C:\x\y\stock.csv'), 'stock.csv');
      expect(importFileName('/a/b/c.csv'), 'c.csv');
      expect(importFileName('c.csv'), 'c.csv');
    });
  });

  group('error wording', () {
    String say(Object e, {String lang = 'en'}) => importErrorText(
      e,
      lang: lang,
      t: (k) => FFLocale.textOf(lang, k) ?? 'MISSING:$k',
    );

    test('the server text is shown as given, in the active language', () {
      final e = ApiException(409, {
        'error': 'duplicate_file',
        'message': {'en': 'Already uploaded.', 'sw': 'Imeshapakiwa.'},
        'reasonMessage': {'en': 'See the list.', 'sw': 'Tazama orodha.'},
        'batchId': 'vib_9',
      });
      expect(say(e), 'Already uploaded. See the list.');
      expect(say(e, lang: 'sw'), 'Imeshapakiwa. Tazama orodha.');
      expect(importDuplicateBatchId(e), 'vib_9');
      expect(
        importDuplicateBatchId(ApiException(409, {'error': 'other'})),
        isNull,
      );
    });

    test('no raw code ever reaches the vendor', () {
      const codes = [
        'rate_limited',
        'file_too_large',
        'too_many_rows',
        'unsupported_file_type',
        'invalid_encoding',
        'duplicate_file',
        'apply_in_progress',
        'import_busy',
        'request_aborted',
        'batch_expired',
        'import_not_found',
        'batch_not_editable',
        'not_ready',
        'nothing_to_retry',
        'not_discardable',
        'profile_import_owner_only',
        'vendor_permission_forbidden',
        'vendor_suspended',
        'account_suspended',
        'feature_disabled',
        'import_quota',
        'empty_file',
        'some_future_code',
        'invalid_cursor',
      ];
      for (final lang in ['en', 'sw']) {
        for (final code in codes) {
          for (final status in [400, 404, 409, 413, 429, 499, 500, 503]) {
            final text = say(ApiException(status, {'error': code}), lang: lang);
            expect(text, isNot(contains(code)), reason: '$status $code');
            expect(text, isNot(contains('MISSING')), reason: '$status $code');
            expect(text, isNotEmpty);
          }
        }
        // No JSON body at all (an HTML error page).
        for (final status in [400, 404, 413, 429, 499, 500, 502]) {
          final text = say(ApiException(status, null), lang: lang);
          expect(text, isNot(contains('MISSING')));
          expect(text, isNot(contains('$status')));
        }
      }
    });

    test('a request that never reached the server is a connection problem', () {
      expect(say(StateError('socket')), en('vendor.import.err.network'));
      expect(
        say(StateError('socket'), lang: 'sw'),
        sw('vendor.import.err.network'),
      );
    });

    test('status-based lines for answers without text', () {
      expect(say(ApiException(429, null)), en('vendor.import.err.rateLimited'));
      expect(say(ApiException(413, null)), en('vendor.import.err.tooLarge'));
      expect(say(ApiException(499, null)), en('vendor.import.err.aborted'));
      expect(say(ApiException(503, null)), en('vendor.import.err.server'));
      expect(say(ApiException(400, null)), en('vendor.import.err.generic'));
    });

    test('extra fields and fatal refusals', () {
      final busy = ApiException(503, {
        'error': 'import_busy',
        'retryAfterSeconds': 5,
      });
      expect(importRetryAfterSeconds(busy), 5);
      expect(importRetryAfterSeconds(ApiException(503, null)), isNull);
      expect(
        importErrorIsFatal(ApiException(404, {'error': 'import_not_found'})),
        isTrue,
      );
      expect(importErrorIsFatal(busy), isFalse);
    });
  });

  group('strings', () {
    test('every key the import screens use exists in English and Swahili', () {
      final used = <String>{};
      final dir = Directory('lib/screens/vendor/import');
      for (final f in dir.listSync().whereType<File>()) {
        final src = f.readAsStringSync();
        used.addAll(
          RegExp(
            r"'(vendor\.import\.[A-Za-z_.]+)'",
          ).allMatches(src).map((m) => m.group(1)!),
        );
      }
      // Built from a value at run time.
      for (final e in ['products', 'inventory', 'profile', 'unknown']) {
        used.add('vendor.import.entity.$e');
      }
      for (final e in ['products', 'inventory', 'profile']) {
        used.add('vendor.import.entity.$e.hint');
      }
      for (final s in BatchStatus.values) {
        used.add('vendor.import.status.${s.wire}');
      }
      for (final m in ['exact', 'synonym', 'fuzzy', 'none']) {
        used.add('vendor.import.match.$m');
      }
      for (final p in ['busy', 'rate', 'network']) {
        used.add('vendor.import.paused.$p');
      }
      for (final s in ['invalid', 'needs_review', 'valid', 'failed']) {
        used.add('vendor.import.rowStatus.$s');
      }
      for (final f in [
        'name',
        'price_tzs',
        'stock',
        'category',
        'description',
        'brand',
        'sku',
        'discount_price_tzs',
        'cost_tzs',
        'reorder_level',
        'image',
        'quantity',
        'variant',
        'businessName',
        'businessCategory',
        'contactNumber',
        'email',
        'address',
        'businessHours',
        'other',
      ]) {
        used.add('vendor.import.field.$f');
      }
      expect(used.length, greaterThan(100));
      final enKeys = FFLocale.keysOf('en');
      final swKeys = FFLocale.keysOf('sw');
      for (final k in used) {
        expect(enKeys, contains(k), reason: 'English $k');
        expect(swKeys, contains(k), reason: 'Swahili $k');
      }
      // Both languages define exactly the same import keys.
      Set<String> ours(Set<String> all) =>
          all.where((k) => k.startsWith('vendor.import.')).toSet();
      expect(ours(swKeys), ours(enKeys));
    });

    test('Swahili is real Swahili, not English left in place', () {
      const sameOk = {
        'vendor.import.field.stock',
        'vendor.import.field.sku',
        'vendor.import.template.swahili',
      };
      for (final k in FFLocale.keysOf('en')) {
        if (!k.startsWith('vendor.import.') || sameOk.contains(k)) continue;
        expect(sw(k), isNot(en(k)), reason: k);
      }
    });

    test(
      'glossary: Stock stays English, TSh not TZS, paused = imesitishwa',
      () {
        for (final k in FFLocale.keysOf('sw')) {
          if (!k.startsWith('vendor.import.')) continue;
          expect(sw(k), isNot(contains('TZS')), reason: k);
          expect(sw(k), isNot(contains('Hisa')), reason: k);
        }
        expect(sw('vendor.import.confirm.products'), contains('zimesitishwa'));
        expect(sw('vendor.import.result.products'), contains('zimesitishwa'));
        expect(sw('vendor.import.field.variant'), 'Chaguo');
        expect(sw('vendor.import.field.price_tzs'), contains('TSh'));
      },
    );

    test('rows and counts are worded without singular/plural forms', () {
      expect(en('vendor.import.confirm.summary'), 'Rows to import: {n}');
      expect(en('vendor.import.rowsTotal'), 'Rows: {n}');
      expect(sw('vendor.import.rowsTotal'), 'Safu mlalo: {n}');
    });
  });
}
