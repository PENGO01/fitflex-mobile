// Vendor tools · sale extras #3 (docs/design/vendor-sale-extras-1110.md §3):
// "Share receipt" as Image, PDF and Text made on the device — rows per
// platform (fakes for share / download / new tab), queued sales, language,
// the long-receipt image limit, failures, the S5 sheet's Image row and
// on-device PDF fallback (Q-10), and the customer type on the sale detail
// only (never on a receipt). The PDF builder and the image renderer also
// run for real.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/screens/vendor/documents/document_share_sheet.dart';
import 'package:fitflexmobile/screens/vendor/sales/receipt_data.dart';
import 'package:fitflexmobile/screens/vendor/sales/receipt_files.dart';
import 'package:fitflexmobile/screens/vendor/sales/receipt_page.dart';
import 'package:fitflexmobile/screens/vendor/sales/receipt_pdf.dart';
import 'package:fitflexmobile/screens/vendor/sales/sale_detail_page.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/network/browser_online.dart';

import '../support/recording_api.dart';
import 'walkin_support.dart';

const owner = {'id': 'v1', 'userType': 'vendor', 'displayName': 'Asha'};
const docsOff = {...walkInOn, 'documents': false, 'customers': true};
const docsOn = {...walkInOn, 'documents': true, 'customers': true};

/// A sale with a customer, a type and a cash reference.
Map<String, dynamic> saleWithExtras({int lines = 1}) => {
  ...serverSale(),
  'customer': {'id': 'cus_asha', 'name': 'Asha Juma'},
  'customerType': 'returning',
  'payments': [
    {'method': 'cash', 'amountTzs': 50000, 'reference': 'TILL-889'},
  ],
  if (lines > 1)
    'lines': [
      for (var i = 0; i < lines; i++)
        {
          'productId': 'p$i',
          'nameSnapshot': 'Item $i',
          'qty': 1,
          'listPriceTzs': 450,
          'unitPriceTzs': 450,
          'discountTzs': 0,
          'lineTotalTzs': 450,
        },
    ],
};

/// Records what the sheet hands on.
class Fakes {
  final files = <(String name, String mime, int bytes)>[];
  final downloads = <(String name, String mime)>[];
  final opened = <String>[];
  final texts = <String>[];
  final jobs = <ReceiptFileJob>[];
  bool web = false;
  bool openOk = true;
  Object? imageError;

  void install() {
    final keep = (
      DocumentActions.shareTypedFile,
      DocumentActions.download,
      DocumentActions.openPdf,
      DocumentActions.isWeb,
      ReceiptFileActions.image,
      ReceiptFileActions.pdf,
      ReceiptFileActions.now,
      shareReceipt,
    );
    DocumentActions.shareTypedFile = (b, name, mime) async =>
        files.add((name, mime, b.length));
    DocumentActions.download = (b, name, mime) async =>
        downloads.add((name, mime));
    DocumentActions.openPdf = (b, name) async {
      opened.add(name);
      return openOk;
    };
    DocumentActions.isWeb = () => web;
    ReceiptFileActions.image = (context, job) async {
      jobs.add(job);
      if (imageError != null) throw imageError!;
      return Uint8List.fromList([137, 80, 78, 71]);
    };
    ReceiptFileActions.pdf = (job) async {
      jobs.add(job);
      return Uint8List.fromList(utf8.encode('%PDF-1.4'));
    };
    ReceiptFileActions.now = () => DateTime.utc(2026, 11, 10, 9, 5);
    shareReceipt = (text, subject) async => texts.add(text);
    addTearDown(() {
      DocumentActions.shareTypedFile = keep.$1;
      DocumentActions.download = keep.$2;
      DocumentActions.openPdf = keep.$3;
      DocumentActions.isWeb = keep.$4;
      ReceiptFileActions.image = keep.$5;
      ReceiptFileActions.pdf = keep.$6;
      ReceiptFileActions.now = keep.$7;
      shareReceipt = keep.$8;
    });
  }
}

Future<PageHost> pumpReceipt(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> tools = docsOff,
  Map<String, dynamic>? sale,
  String lang = 'en',
}) {
  seedPos(api, tools: tools);
  return pumpPage(
    tester,
    api,
    SaleReceiptPage(saleId: 'sal_1', sale: sale ?? saleWithExtras()),
    user: owner,
    lang: lang,
    size: const Size(420, 1400),
    extraRoutes: salesRoutes,
  );
}

bool rowEnabled(WidgetTester tester, String key) => tester
    .widget<ListTile>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(ListTile),
      ),
    )
    .enabled;

Future<void> openShare(WidgetTester tester) =>
    tapVisible(tester, find.byKey(const Key('sales-receipt-share')));

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => BrowserOnline.debugSet(true));

  group('pure', () {
    final locale = FFLocale();
    String en(String k) => locale.tIn('en', k);
    String sw(String k) => locale.tIn('sw', k);

    test('printed rows: fiscal line last (EN + SW), name, no type/phone', () {
      final data = ReceiptData.fromSale(
        saleWithExtras(),
        profile: {'businessName': 'Dar Gear', 'contactNumber': '+255700000001'},
      );
      expect(data.customerType, 'returning');
      for (final (t, fiscal) in [
        (en, 'This is not a TRA fiscal receipt.'),
        (sw, 'Hii si risiti ya kodi ya TRA.'),
      ]) {
        final rows = receiptPrintRows(data, t, 'en');
        expect(rows.last.text, fiscal);
        final all = rows.join('\n');
        expect(all, contains('Asha Juma'));
        expect(all, contains('(TILL-889)'));
        expect(all, isNot(contains('Returning')));
        expect(all, isNot(contains('Anayerudi')));
      }
      expect(receiptPrintRows(data, en, 'en')[0].text, 'Dar Gear');
      expect(receiptFileHeading(data, en), 'Receipt R-000001');
    });

    test('text share never has the type either', () {
      final data = ReceiptData.fromSale(saleWithExtras());
      final text = receiptShareText(data, en, 'en');
      expect(text, contains('Cash (TILL-889)'));
      expect(text, isNot(contains('Returning')));
    });

    test('file names and the image limits', () {
      final recorded = ReceiptData.fromSale(saleWithExtras());
      expect(receiptFileName(recorded, 'png'), 'receipt-R-000001.png');
      final queued = ReceiptData.fromQueued({
        'clientRef': 'sale_q_00abcdef',
        'soldAt': '2026-10-19T08:00:00.000Z',
        'lines': [],
        'payments': [],
      }, const {});
      expect(
        receiptFileName(queued, 'pdf'),
        'receipt-pending-20261019-1100.pdf',
      );
      expect(receiptImagePixelRatio(1200), 3);
      expect(receiptImagePixelRatio(4500), 2);
      expect(receiptImagePixelRatio(6500), isNull);
      expect(receiptTooLongForImage(recorded), isFalse);
      expect(
        receiptTooLongForImage(
          ReceiptData.fromSale(saleWithExtras(lines: 100)),
        ),
        isTrue,
      );
      expect(
        receiptTooLongForImage(ReceiptData.fromSale(saleWithExtras(lines: 40))),
        isFalse,
      );
    });

    testWidgets('the PDF is built for real (Inter embedded, 80 mm)', (
      tester,
    ) async {
      final data = ReceiptData.fromSale(
        saleWithExtras(lines: 100),
        profile: {'businessName': 'Duka la Ūnicode — Zanzibar'},
      );
      final bytes = (await tester.runAsync(
        () => buildReceiptPdf(data, sw, 'sw'),
      ))!;
      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
      final raw = latin1.decode(bytes);
      // Inter embedded, never the built-in Helvetica.
      expect(raw, contains('Inter'));
      expect(raw, isNot(contains('/Helvetica')));
      // 80 mm wide.
      expect(raw, contains('226.7'));
    });
  });

  group('documents off: the new sheet', () {
    apiTest('three rows; Image and PDF go to the share sheet (Android)', (
      tester,
      api,
    ) async {
      final f = Fakes()..install();
      final host = await pumpReceipt(tester, api);
      await openShare(tester);
      expect(find.text(host.tr('vendor.pos.share')), findsWidgets);
      expect(find.byKey(const Key('receipt-share-image')), findsOneWidget);
      expect(find.byKey(const Key('receipt-share-pdf')), findsOneWidget);
      expect(find.byKey(const Key('receipt-share-text')), findsOneWidget);
      expect(find.text('Image'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('receipt-share-image')));
      expect(f.files.single, ('receipt-R-000001.png', 'image/png', 4));
      // The sheet closed.
      expect(find.byKey(const Key('receipt-share-image')), findsNothing);
      await openShare(tester);
      await tapVisible(tester, find.byKey(const Key('receipt-share-pdf')));
      expect(f.files.last.$1, 'receipt-R-000001.pdf');
      expect(f.files.last.$2, 'application/pdf');
      expect(f.jobs.last.lang, 'en');
      await openShare(tester);
      await tapVisible(tester, find.byKey(const Key('receipt-share-text')));
      expect(f.texts.single, contains('Cash (TILL-889)'));
      // No server document call for any of it.
      expect(api.requests.where((r) => r.path.contains('/documents')), isEmpty);
    });

    apiTest('web: Download image (snack), Open PDF in a new tab', (
      tester,
      api,
    ) async {
      final f = Fakes()
        ..web = true
        ..install();
      final host = await pumpReceipt(tester, api);
      await openShare(tester);
      expect(
        find.text(host.tr('vendor.receipt.downloadImage')),
        findsOneWidget,
      );
      expect(find.text(host.tr('vendor.documents.openPdf')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('receipt-share-image')));
      expect(f.downloads.single, ('receipt-R-000001.png', 'image/png'));
      expect(host.snack(host.tr('vendor.receipt.downloaded')), findsOneWidget);
      await host.dismissSnacks();
      await openShare(tester);
      await tapVisible(tester, find.byKey(const Key('receipt-share-pdf')));
      expect(f.opened.single, 'receipt-R-000001.pdf');
      // A blocked tab falls back to a download.
      f.openOk = false;
      await openShare(tester);
      await tapVisible(tester, find.byKey(const Key('receipt-share-pdf')));
      expect(f.downloads.last, ('receipt-R-000001.pdf', 'application/pdf'));
    });

    apiTest('files follow the receipt language toggle (Swahili)', (
      tester,
      api,
    ) async {
      final f = Fakes()..install();
      await pumpReceipt(tester, api);
      await tester.tap(find.text('Kiswahili'));
      await tester.pumpAndSettle();
      await openShare(tester);
      await tapVisible(tester, find.byKey(const Key('receipt-share-pdf')));
      expect(f.jobs.single.lang, 'sw');
      expect(
        f.jobs.single.t('vendor.pos.notFiscal'),
        'Hii si risiti ya kodi ya TRA.',
      );
    });

    apiTest('a failed file shows the reason; rows work again', (
      tester,
      api,
    ) async {
      final f = Fakes()
        ..imageError = StateError('gpu')
        ..install();
      final host = await pumpReceipt(tester, api);
      await openShare(tester);
      await tapVisible(tester, find.byKey(const Key('receipt-share-image')));
      expect(find.text(host.tr('vendor.receipt.fileFailed')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('receipt-share-text')));
      expect(f.texts, hasLength(1));
    });

    apiTest('a 100-line receipt (AC-29): Image off with the reason', (
      tester,
      api,
    ) async {
      Fakes().install();
      final host = await pumpReceipt(
        tester,
        api,
        sale: saleWithExtras(lines: 100),
      );
      await openShare(tester);
      expect(find.text(host.tr('vendor.receipt.tooLongImage')), findsOneWidget);
      expect(rowEnabled(tester, 'receipt-share-image'), isFalse);
      expect(rowEnabled(tester, 'receipt-share-pdf'), isTrue);
    });

    apiTest('queued sale (AC-27): Image and PDF work, pending file names', (
      tester,
      api,
    ) async {
      final f = Fakes()..install();
      SharedPreferences.setMockInitialValues({
        'vendor_sale_queue.v1.v1': jsonEncode([
          {
            'body': {
              'clientRef': 'sale_q_00abcdef',
              'soldAt': '2026-10-19T08:00:00.000Z',
              'lines': [
                {'productId': 'p1', 'qty': 1},
              ],
              'payments': [
                {'method': 'cash', 'amountTzs': 45000},
              ],
              'customerType': 'walk_in',
            },
            'display': {
              'business': 'Dar Gear',
              'lines': [
                {'name': 'Whey', 'listPriceTzs': 45000},
              ],
            },
            'queuedAt': '2026-10-19T08:00:00.000Z',
            'state': 'waiting',
          },
        ]),
      });
      seedPos(api);
      api.fail('POST /vendor/sales', 503);
      await pumpPage(
        tester,
        api,
        const SaleReceiptPage(clientRef: 'sale_q_00abcdef'),
        user: owner,
        size: const Size(420, 1400),
        extraRoutes: salesRoutes,
      );
      await openShare(tester);
      await tapVisible(tester, find.byKey(const Key('receipt-share-image')));
      await openShare(tester);
      await tapVisible(tester, find.byKey(const Key('receipt-share-pdf')));
      expect(f.files.map((e) => e.$1), [
        'receipt-pending-20261019-1100.png',
        'receipt-pending-20261019-1100.pdf',
      ]);
      expect(f.jobs.first.data.queued, isTrue);
      // The provisional heading (no number yet).
      expect(
        receiptFileHeading(f.jobs.first.data, f.jobs.first.t),
        contains('ABCDEF'),
      );
    });
  });

  group('documents on (Q-10)', () {
    apiTest('S5 sheet gains Image; offline its PDF row is the device PDF', (
      tester,
      api,
    ) async {
      final f = Fakes()..install();
      api.on('GET /vendor/documents/links', {'activeCount': 0, 'links': []});
      await pumpReceipt(tester, api, tools: docsOn);
      await openShare(tester);
      expect(find.byKey(const Key('doc-share-image')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('doc-share-image')));
      expect(f.files.single.$1, 'receipt-R-000001.png');
      // Offline: link rows off, the PDF row makes the PDF on the device.
      BrowserOnline.debugSet(false);
      await openShare(tester);
      await tapVisible(tester, find.byKey(const Key('doc-share-pdf')));
      expect(f.files.last, ('receipt-R-000001.pdf', 'application/pdf', 8));
      expect(api.requests.where((r) => r.path.contains('/pdf')), isEmpty);
    });
  });

  group('sale detail', () {
    apiTest('customer type line (Q-9) and the same share rows (AC-31)', (
      tester,
      api,
    ) async {
      Fakes().install();
      seedPos(api, tools: docsOff);
      api.on('GET /vendor/sales/sal_1', {'sale': saleWithExtras()});
      final host = await pumpPage(
        tester,
        api,
        const SaleDetailPage(saleId: 'sal_1'),
        user: owner,
        size: const Size(420, 1600),
        extraRoutes: salesRoutes,
      );
      expect(find.text('Customer type: Returning'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('sale-detail-share')));
      expect(find.byKey(const Key('receipt-share-image')), findsOneWidget);
      expect(find.byKey(const Key('receipt-share-pdf')), findsOneWidget);
      expect(find.byKey(const Key('receipt-share-text')), findsOneWidget);
      expect(host.tr('vendor.sales.customerTypeLine'), 'Customer type: {type}');
    });

    apiTest('the receipt page never shows the type', (tester, api) async {
      await pumpReceipt(tester, api);
      expect(find.byKey(const Key('sale-detail-customer-type')), findsNothing);
      expect(textContaining('Returning'), findsNothing);
    });
  });

  group('the image, drawn for real', () {
    apiTest('1080 px wide PNG from the off-screen receipt', (
      tester,
      api,
    ) async {
      seedPos(api);
      await pumpReceipt(tester, api);
      final context = tester.element(find.byType(SaleReceiptPage));
      final locale = FFLocale();
      final job = ReceiptFileJob(
        data: ReceiptData.fromSale(saleWithExtras()),
        lang: 'en',
        t: (k) => locale.tIn('en', k),
      );
      Uint8List? png;
      await tester.runAsync(() async {
        final pending = renderReceiptImage(context, job);
        // Let the overlay entry lay out and paint.
        for (var i = 0; i < 5 && png == null; i++) {
          tester.binding.scheduleFrame();
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        png = await pending;
      });
      expect(png, isNotNull);
      // PNG signature and IHDR width (big-endian at byte 16).
      expect(png!.sublist(0, 4), [137, 80, 78, 71]);
      final width = ByteData.sublistView(png!, 16, 20).getUint32(0);
      expect(width, 1080);
    });
  });
}
