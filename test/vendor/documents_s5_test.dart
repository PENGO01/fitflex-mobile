// Vendor tools · S5 (documents and VAT, fitflex-functions #229): gating,
// the share sheet (lazy link, reuse, language, 503, queued, PDF, text),
// links list (turn off one / all), tax details (owner-only edit), product
// VAT code, order and buyer invoices, the VAT push link, and Swahili.
//
// Every request goes to the in-process RecordingApi (http://fixtures.local);
// nothing here ever reaches a real server. WhatsApp, SMS, clipboard and the
// system share sheet are replaced by recorders.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/partner/verification/verification_forms.dart'
    show PickedDocument;
import 'package:fitflexmobile/screens/vendor/customers/payment_sheets.dart'
    show showPaymentReceipt;
import 'package:fitflexmobile/screens/vendor/customers/statement_page.dart';
import 'package:fitflexmobile/screens/vendor/documents/document_models.dart';
import 'package:fitflexmobile/screens/vendor/documents/document_share_sheet.dart';
import 'package:fitflexmobile/screens/vendor/documents/document_view.dart';
import 'package:fitflexmobile/screens/vendor/orders/vendor_order_card.dart';
import 'package:fitflexmobile/screens/vendor/sales/receipt_page.dart';
import 'package:fitflexmobile/screens/vendor/sales/sale_detail_page.dart';
import 'package:fitflexmobile/screens/vendor/settings/tax_details_page.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_options.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';

import '../support/recording_api.dart';
import 'customers_support.dart' show staffUser;
import 'walkin_support.dart';

const owner = {'id': 'v1', 'userType': 'vendor', 'displayName': 'Asha'};
const docsOn = {...walkInOn, 'documents': true, 'customers': true};
const docsOff = {...walkInOn, 'documents': false, 'customers': true};
const url = 'https://docs.test/d/AAAAAAAAAAAAAAAAAAAAAA';

Map<String, dynamic> shareAnswer({
  String lang = 'en',
  String number = 'R-000001',
}) => {
  'linkId': 'dl_1',
  'url': lang == 'sw' ? '$url?lang=sw' : url,
  'lang': lang,
  'docType': 'receipt',
  'docId': 'sal_1',
  'number': number,
  'texts': {
    'en': {
      'whatsapp': 'Dar Gear: Receipt $number, TSh 45,000. View it here: $url',
      'sms': 'Dar Gear Receipt $number TSh 45,000: $url',
    },
    'sw': {
      'whatsapp':
          'Dar Gear: Risiti $number, TSh 45,000. Itazame hapa: $url?lang=sw',
      'sms': 'Dar Gear Risiti $number TSh 45,000: $url?lang=sw',
    },
  },
  'whatsappText': 'unused',
  'smsText': 'unused',
};

/// Records what the sheet would do outside the app.
class Outside {
  final launched = <Uri>[];
  final copied = <String>[];
  final files = <(int, String)>[];
  final shared = <String>[];
  bool launchOk = true;

  void install() {
    final launch = DocumentActions.launch;
    final copy = DocumentActions.copy;
    final shareFile = DocumentActions.shareFile;
    final isWeb = DocumentActions.isWeb;
    final text = shareReceipt;
    DocumentActions.launch = (uri) async {
      launched.add(uri);
      return launchOk;
    };
    DocumentActions.copy = (t) async => copied.add(t);
    DocumentActions.shareFile = (bytes, name) async =>
        files.add((bytes.length, name));
    DocumentActions.isWeb = () => false;
    shareReceipt = (t, subject) async => shared.add(t);
    addTearDown(() {
      DocumentActions.launch = launch;
      DocumentActions.copy = copy;
      DocumentActions.shareFile = shareFile;
      DocumentActions.isWeb = isWeb;
      shareReceipt = text;
    });
  }
}

Future<PageHost> pumpReceipt(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> tools = docsOn,
  Map<String, dynamic>? sale,
  Map<String, dynamic> user = owner,
  String lang = 'en',
}) async {
  seedPos(api, tools: tools);
  return pumpPage(
    tester,
    api,
    SaleReceiptPage(saleId: 'sal_1', sale: sale ?? serverSale()),
    user: user,
    lang: lang,
    size: const Size(420, 1400),
    extraRoutes: salesRoutes,
  );
}

Future<void> openSheet(WidgetTester tester) async {
  await tapVisible(tester, find.byKey(const Key('sales-receipt-share')));
}

void main() {
  setUpAll(loadAppFonts);

  group('gating', () {
    apiTest(
      'documents off: no S5 sheet, no link; Share as text sends the S3 text',
      (tester, api) async {
        final out = Outside()..install();
        await pumpReceipt(tester, api, tools: docsOff);
        await openSheet(tester);
        expect(find.byKey(const Key('doc-share-copy')), findsNothing);
        // Sale extras #3: the documents-off sheet (Image, PDF, Share as text).
        await tapVisible(tester, find.byKey(const Key('receipt-share-text')));
        expect(out.shared.single, startsWith('Dar Gear'));
        expect(api.sent('POST', '/vendor/sales/sal_1/share'), isFalse);
      },
    );

    apiTest('documents on: opening and closing the sheet makes no link', (
      tester,
      api,
    ) async {
      Outside().install();
      await pumpReceipt(tester, api);
      await openSheet(tester);
      expect(find.byKey(const Key('doc-share-whatsapp')), findsOneWidget);
      expect(find.byKey(const Key('doc-share-privacy')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ff-sheet-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('doc-share-whatsapp')), findsNothing);
      expect(api.sent('POST', '/vendor/sales/sal_1/share'), isFalse);
    });

    test('tools: documents and vat only when exactly true', () {
      expect(VendorTools.fromOptions({'documents': true}).documents, isTrue);
      expect(VendorTools.fromOptions({'documents': 'true'}).documents, isFalse);
      expect(VendorTools.fromOptions({'vat': true}).vat, isTrue);
      expect(VendorTools.fromOptions({}).vat, isFalse);
    });
  });

  group('share sheet', () {
    apiTest('Copy link makes one link; WhatsApp then reuses it', (
      tester,
      api,
    ) async {
      final out = Outside()..install();
      api.on('POST /vendor/sales/sal_1/share', shareAnswer());
      await pumpReceipt(tester, api);
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('doc-share-copy')));
      await tester.pumpAndSettle();
      expect(out.copied.single, url);
      final body = api.only('POST', '/vendor/sales/sal_1/share').body as Map;
      expect(body['lang'], 'en');
      await tester.tap(find.byKey(const Key('doc-share-whatsapp')));
      await tester.pumpAndSettle();
      // Still one link (AC-4); the server's text, no number (no customer).
      expect(api.where('POST', '/vendor/sales/sal_1/share'), hasLength(1));
      final wa = out.launched.single;
      expect(wa.host, 'wa.me');
      expect(wa.path, '/');
      expect(
        wa.queryParameters['text'],
        'Dar Gear: Receipt R-000001, TSh 45,000. View it here: $url',
      );
    });

    apiTest('walk-in customer: WhatsApp and SMS go to their phone', (
      tester,
      api,
    ) async {
      final out = Outside()..install();
      api.on('POST /vendor/sales/sal_1/share', shareAnswer());
      api.on('GET /vendor/customers/cus_1', {
        'customer': {
          'id': 'cus_1',
          'source': 'manual',
          'name': 'Juma',
          'phone': '+255712345678',
        },
      });
      await pumpReceipt(
        tester,
        api,
        sale: {
          ...serverSale(),
          'customer': {'id': 'cus_1', 'name': 'Juma'},
        },
      );
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('doc-share-whatsapp')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('doc-share-sms')));
      await tester.pumpAndSettle();
      expect(
        out.launched[0].toString(),
        startsWith('https://wa.me/255712345678?text='),
      );
      expect(out.launched[1].scheme, 'sms');
      expect(out.launched[1].path, '255712345678');
      expect(
        Uri.decodeComponent(out.launched[1].toString().split('body=').last),
        'Dar Gear Receipt R-000001 TSh 45,000: $url',
      );
    });

    apiTest('app customer: no phone is ever filled in', (tester, api) async {
      final out = Outside()..install();
      api.on('POST /vendor/sales/sal_1/share', shareAnswer());
      api.on('GET /vendor/customers/cus_2', {
        'customer': {
          'id': 'cus_2',
          'source': 'marketplace',
          'name': 'Neema',
          'phone': '+255700000009',
        },
      });
      await pumpReceipt(
        tester,
        api,
        sale: {
          ...serverSale(),
          'customer': {'id': 'cus_2', 'name': 'Neema'},
        },
      );
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('doc-share-whatsapp')));
      await tester.pumpAndSettle();
      expect(
        out.launched.single.toString(),
        startsWith('https://wa.me/?text='),
      );
    });

    apiTest('switching to Kiswahili after a link exists makes no new link', (
      tester,
      api,
    ) async {
      final out = Outside()..install();
      api.on('POST /vendor/sales/sal_1/share', shareAnswer());
      await pumpReceipt(tester, api);
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('doc-share-copy')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('doc-share-language')),
          matching: find.text('Kiswahili'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('doc-share-copy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('doc-share-whatsapp')));
      await tester.pumpAndSettle();
      expect(api.where('POST', '/vendor/sales/sal_1/share'), hasLength(1));
      expect(out.copied.last, '$url?lang=sw');
      expect(
        out.launched.single.queryParameters['text'],
        contains('Itazame hapa'),
      );
    });

    apiTest('WhatsApp missing: the link is copied instead', (
      tester,
      api,
    ) async {
      final out = Outside()
        ..install()
        ..launchOk = false;
      api.on('POST /vendor/sales/sal_1/share', shareAnswer());
      final host = await pumpReceipt(tester, api);
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('doc-share-whatsapp')));
      await tester.pumpAndSettle();
      expect(out.copied.single, url);
      expect(find.text(host.tr('vendor.documents.noWhatsApp')), findsOneWidget);
    });

    apiTest('503 public_url_not_configured: link rows off, text still works', (
      tester,
      api,
    ) async {
      final out = Outside()..install();
      api.fail('POST /vendor/sales/sal_1/share', 503, {
        'error': 'public_url_not_configured',
      });
      final host = await pumpReceipt(tester, api);
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('doc-share-copy')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('doc-share-unavailable')), findsOneWidget);
      expect(
        find.text(host.tr('vendor.documents.unavailable')),
        findsOneWidget,
      );
      expect(out.copied, isEmpty);
      final copy = tester.widget<ListTile>(
        find.byKey(const Key('doc-share-copy')),
      );
      final wa = tester.widget<ListTile>(
        find.byKey(const Key('doc-share-whatsapp')),
      );
      expect(copy.enabled, isFalse);
      expect(wa.enabled, isFalse);
      await tester.tap(find.byKey(const Key('doc-share-text')));
      await tester.pumpAndSettle();
      // The S3 text, without a link line (no link was made).
      expect(out.shared.single, startsWith('Dar Gear'));
      expect(out.shared.single, isNot(contains('View:')));
    });

    apiTest('create fails: error + Try again; nothing copied', (
      tester,
      api,
    ) async {
      final out = Outside()..install();
      api.fail('POST /vendor/sales/sal_1/share', 500);
      await pumpReceipt(tester, api);
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('doc-share-copy')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('doc-share-create-failed')), findsOneWidget);
      expect(out.copied, isEmpty);
      api.heal('POST /vendor/sales/sal_1/share');
      api.on('POST /vendor/sales/sal_1/share', shareAnswer());
      await tester.tap(find.byKey(const Key('doc-share-retry')));
      await tester.pumpAndSettle();
      expect(out.copied.single, url);
    });

    apiTest('429 rate_limited: "Wait {n} seconds", then a retry works', (
      tester,
      api,
    ) async {
      final out = Outside()..install();
      api.fail('POST /vendor/sales/sal_1/share', 429, {
        'error': 'rate_limited',
        'retryAfterSeconds': 37,
      });
      await pumpReceipt(tester, api);
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('doc-share-copy')));
      await tester.pumpAndSettle();
      expect(find.text('Too many tries. Wait 37 seconds.'), findsOneWidget);
      expect(find.byKey(const Key('doc-share-create-failed')), findsNothing);
      expect(out.copied, isEmpty);
      api.heal('POST /vendor/sales/sal_1/share');
      api.on('POST /vendor/sales/sal_1/share', shareAnswer());
      await tester.tap(find.byKey(const Key('doc-share-copy')));
      await tester.pumpAndSettle();
      expect(out.copied.single, url);
      expect(find.byKey(const Key('doc-share-rate-limited')), findsNothing);
    });

    apiTest('403: the sheet closes with "no access"', (tester, api) async {
      Outside().install();
      api.fail('POST /vendor/sales/sal_1/share', 403, {
        'error': 'vendor_permission_forbidden',
      });
      final host = await pumpReceipt(tester, api);
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('doc-share-copy')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('doc-share-copy')), findsNothing);
      expect(host.snack(host.tr('vendor.documents.noAccess')), findsOneWidget);
    });

    apiTest('Share as text after a link adds "View: {url}"', (
      tester,
      api,
    ) async {
      final out = Outside()..install();
      api.on('POST /vendor/sales/sal_1/share', shareAnswer());
      await pumpReceipt(tester, api);
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('doc-share-copy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('doc-share-text')));
      await tester.pumpAndSettle();
      expect(out.shared.single, endsWith('View: $url'));
    });

    apiTest('Send PDF: the authenticated PDF goes to the share sheet', (
      tester,
      api,
    ) async {
      final out = Outside()..install();
      api.onCall(
        'GET /vendor/documents/sale/sal_1',
        (_) => const RawResponse(200, '%PDF-1.4 test'),
      );
      await pumpReceipt(tester, api);
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('doc-share-pdf')));
      await tester.pumpAndSettle();
      final req = api.only('GET', '/vendor/documents/sale/sal_1');
      expect(req.query, contains('format=pdf'));
      expect(req.query, contains('paper=a4'));
      expect(out.files.single.$2, 'R-000001.pdf');
      // No public link for a PDF.
      expect(api.sent('POST', '/vendor/sales/sal_1/share'), isFalse);
    });

    apiTest('PDF fails: alert, then retry', (tester, api) async {
      final out = Outside()..install();
      api.fail('GET /vendor/documents/sale/sal_1', 500);
      await pumpReceipt(tester, api);
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('doc-share-pdf')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('doc-share-pdf-failed')), findsOneWidget);
      api.heal('GET /vendor/documents/sale/sal_1');
      api.onCall(
        'GET /vendor/documents/sale/sal_1',
        (_) => const RawResponse(200, '%PDF'),
      );
      await tester.tap(find.byKey(const Key('doc-share-retry')));
      await tester.pumpAndSettle();
      expect(out.files, hasLength(1));
    });

    apiTest('80mm PDF under More', (tester, api) async {
      final out = Outside()..install();
      api.onCall(
        'GET /vendor/documents/sale/sal_1',
        (_) => const RawResponse(200, '%PDF'),
      );
      await pumpReceipt(tester, api);
      await openSheet(tester);
      await tapVisible(tester, find.byKey(const Key('doc-share-more')));
      await tapVisible(tester, find.byKey(const Key('doc-share-pdf80')));
      expect(
        api.only('GET', '/vendor/documents/sale/sal_1').query,
        contains('paper=80mm'),
      );
      expect(out.files, hasLength(1));
    });

    apiTest('a pay-later sale shares as its invoice INV-…', (
      tester,
      api,
    ) async {
      Outside().install();
      api.on(
        'POST /vendor/sales/sal_1/share',
        shareAnswer(number: 'INV-000004'),
      );
      final host = await pumpReceipt(
        tester,
        api,
        sale: {
          ...serverSale(),
          'kind': 'credit',
          'invoiceNumber': 'INV-000004',
          'paidTzs': 0,
          'payments': [],
          'changeTzs': 0,
          'balanceTzs': 45000,
          'dueDate': '2026-10-26',
          'customer': {'id': 'cus_3', 'name': 'Ali'},
        },
      );
      // The receipt says Invoice INV-000004, Sale ref R-000001 (Q-7).
      expect(find.text('Invoice INV-000004'), findsOneWidget);
      expect(find.byKey(const Key('sales-receipt-sale-ref')), findsOneWidget);
      await openSheet(tester);
      expect(
        find.text(
          fillIn(host.tr('vendor.documents.shareTitle'), {
            'title': 'Invoice',
            'number': 'INV-000004',
          }),
        ),
        findsOneWidget,
      );
    });

    apiTest('queued sale: links and PDF off, text works', (tester, api) async {
      final out = Outside()..install();
      seedPos(api, tools: docsOn);
      api.fail('POST /vendor/sales', 503);
      final host = await pumpPage(
        tester,
        api,
        const SaleReceiptPage(clientRef: 'sale_q_00abcdef'),
        user: owner,
        size: const Size(420, 1400),
        extraRoutes: salesRoutes,
      );
      // No such queued sale on the device: nothing to share.
      expect(find.byKey(const Key('sales-receipt-share')), findsNothing);
      // The sheet itself, for a queued sale:
      await tester.pumpWidget(const SizedBox());
      await pumpPage(
        tester,
        api,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDocumentShareSheet(
              context,
              doc: DocumentRef.sale(saleId: 'sale_q', credit: false),
              lang: 'en',
              queued: true,
              shareText: (_) => 'PROVISIONAL',
              shareSubject: (_) => 'S',
            ),
            child: const Text('OPEN'),
          ),
        ),
        user: owner,
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      expect(
        find.text(host.tr('vendor.documents.needsNumber')),
        findsOneWidget,
      );
      for (final k in [
        'doc-share-whatsapp',
        'doc-share-sms',
        'doc-share-copy',
        'doc-share-pdf',
      ]) {
        expect(
          tester.widget<ListTile>(find.byKey(Key(k))).enabled,
          isFalse,
          reason: k,
        );
      }
      expect(find.byKey(const Key('doc-share-links')), findsNothing);
      await tester.tap(find.byKey(const Key('doc-share-text')));
      await tester.pumpAndSettle();
      expect(out.shared.single, 'PROVISIONAL');
      expect(api.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    apiTest('statement: the share sheet makes a statement link', (
      tester,
      api,
    ) async {
      final out = Outside()..install();
      api.on('GET /vendor/tools/options', docsOn);
      api.on('GET /vendor/profile', {'businessName': 'Dar Gear'});
      api.on('GET /vendor/customers/cus_1', {
        'customer': {
          'id': 'cus_1',
          'source': 'manual',
          'name': 'Juma',
          'phone': '+255712345678',
          'owedTzs': 20000,
          'openSales': [],
          'aging': {},
        },
      });
      api.on('GET /vendor/customers/cus_1/payments', {'payments': []});
      api.on('POST /vendor/customers/cus_1/statement/share', {
        ...shareAnswer(),
        'docType': 'statement',
        'number': null,
      });
      await pumpPage(
        tester,
        api,
        const StatementPage(customerId: 'cus_1'),
        user: owner,
        size: const Size(420, 1200),
      );
      await tapVisible(tester, find.byKey(const Key('statement-share')));
      await tester.tap(find.byKey(const Key('doc-share-whatsapp')));
      await tester.pumpAndSettle();
      expect(
        api.sent('POST', '/vendor/customers/cus_1/statement/share'),
        isTrue,
      );
      expect(
        out.launched.single.toString(),
        startsWith('https://wa.me/255712345678'),
      );
    });
  });

  group('VAT on the receipt', () {
    Map<String, dynamic> vatSale() => {
      ...serverSale(),
      'invoiceNumber': null,
      'vatIncludedTzs': 6864,
      'vatSummary': [
        {'code': 'A', 'ratePct': 18, 'netTzs': 38136, 'vatTzs': 6864},
      ],
      'lines': [
        {
          ...(serverSale()['lines'] as List).first as Map<String, dynamic>,
          'vatCode': 'A',
          'vatRatePct': 18,
          'vatTzs': 6864,
        },
      ],
    };

    apiTest('vat on: Includes VAT, summary, code letter; TIN/VRN from doc', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/documents/sale/sal_1', {
        'doc': {
          'docType': 'receipt',
          'seller': {
            'businessName': 'Dar Gear',
            'tin': '123456789',
            'vrn': '40012345X',
          },
        },
      });
      await pumpReceipt(
        tester,
        api,
        tools: {...docsOn, 'vat': true},
        sale: vatSale(),
      );
      expect(find.byKey(const Key('doc-vat-block')), findsOneWidget);
      expect(find.text('TSh 6,864'), findsOneWidget);
      expect(find.text('A 18%'), findsOneWidget);
      expect(find.text('45,000 A'), findsOneWidget);
      expect(find.text('TIN 123456789'), findsOneWidget);
      expect(find.text('VRN 40012345X'), findsOneWidget);
      // The total the customer pays is unchanged (prices include VAT).
      expect(find.text('TSh 45,000'), findsOneWidget);
    });

    apiTest('exempt-only sale (VAT 0): the VAT block still shows', (
      tester,
      api,
    ) async {
      await pumpReceipt(
        tester,
        api,
        tools: {...docsOn, 'vat': true},
        sale: {
          ...serverSale(),
          'vatIncludedTzs': 0,
          'vatSummary': [
            {'code': 'E', 'ratePct': null, 'netTzs': 45000, 'vatTzs': 0},
          ],
          'lines': [
            {
              ...(serverSale()['lines'] as List).first as Map<String, dynamic>,
              'vatCode': 'E',
            },
          ],
        },
      );
      expect(find.byKey(const Key('doc-vat-block')), findsOneWidget);
      expect(find.text('E Exempt'), findsOneWidget);
      expect(find.text('45,000 E'), findsOneWidget);
    });

    apiTest('vat off: no VAT block anywhere, no document asked (AC-2)', (
      tester,
      api,
    ) async {
      await pumpReceipt(tester, api, tools: docsOn, sale: vatSale());
      expect(find.byKey(const Key('doc-vat-block')), findsNothing);
      expect(find.text('45,000 A'), findsNothing);
      expect(api.sent('GET', '/vendor/documents/sale/sal_1'), isFalse);
    });

    apiTest('documents off: a pay-later sale keeps its S4 receipt title', (
      tester,
      api,
    ) async {
      await pumpReceipt(
        tester,
        api,
        tools: docsOff,
        sale: {
          ...serverSale(),
          'kind': 'credit',
          'invoiceNumber': 'INV-000004',
          'payments': [],
          'balanceTzs': 45000,
        },
      );
      expect(find.text('Receipt R-000001'), findsOneWidget);
      expect(textContaining('INV-000004'), findsNothing);
    });
  });

  group('payment receipt', () {
    apiTest('Share opens the sheet; the link is for that payment', (
      tester,
      api,
    ) async {
      final out = Outside()..install();
      api.on('GET /vendor/tools/options', docsOn);
      api.on('GET /vendor/profile', {'businessName': 'Dar Gear'});
      api.on('GET /vendor/customers/cus_1', {
        'customer': {'id': 'cus_1', 'source': 'manual', 'phone': '0712345678'},
      });
      api.on('POST /vendor/customers/cus_1/payments/pay_1/share', {
        ...shareAnswer(number: 'PMT-000002'),
        'docType': 'payment_receipt',
      });
      await pumpPage(
        tester,
        api,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showPaymentReceipt(
              context,
              customerId: 'cus_1',
              customerName: 'Juma',
              payment: {
                'id': 'pay_1',
                'number': 'PMT-000002',
                'status': 'completed',
                'method': 'cash',
                'amountTzs': 20000,
                'receivedOn': '2026-10-20',
                'allocations': [],
              },
              stillOwedTzs: 0,
            ),
            child: const Text('OPEN'),
          ),
        ),
        user: owner,
        size: const Size(420, 1600),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('payment-share')));
      await tester.tap(find.byKey(const Key('doc-share-copy')));
      await tester.pumpAndSettle();
      expect(
        api.sent('POST', '/vendor/customers/cus_1/payments/pay_1/share'),
        isTrue,
      );
      expect(out.copied.single, url);
      await tester.tap(find.byKey(const Key('doc-share-whatsapp')));
      await tester.pumpAndSettle();
      expect(
        out.launched.single.toString(),
        startsWith('https://wa.me/255712345678?'),
      );
    });
  });

  group('links list', () {
    Map<String, dynamic> link(String id, int n, {bool active = true}) => {
      'id': id,
      'n': n,
      'docType': 'receipt',
      'docId': 'sal_1',
      'lang': n == 2 ? 'sw' : 'en',
      'createdAt': '2026-10-20T08:00:00.000Z',
      'createdBy': {'id': 'v1', 'firstName': 'Asha'},
      'lastOpenedAt': n == 1 ? '2026-10-20T09:00:00.000Z' : null,
      'revokedAt': active ? null : '2026-10-20T10:00:00.000Z',
      'active': active,
    };

    Future<PageHost> openLinks(WidgetTester tester, RecordingApi api) async {
      Outside().install();
      final host = await pumpReceipt(tester, api);
      await openSheet(tester);
      await tapVisible(tester, find.byKey(const Key('doc-share-links')));
      return host;
    }

    apiTest('rows: when, who, opened, language; never the URL', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/document-links', {
        'links': [link('dl_1', 1), link('dl_2', 2)],
        'activeCount': 2,
      });
      final host = await openLinks(tester, api);
      final req = api.where('GET', '/vendor/document-links').last;
      expect(req.query, 'docType=sale&docId=sal_1');
      expect(find.text('Link 1'), findsOneWidget);
      expect(
        find.text(host.tr('vendor.documents.neverOpened')),
        findsOneWidget,
      );
      expect(textContaining('Created '), findsNWidgets(2));
      expect(find.text('SW'), findsOneWidget);
      expect(textContaining('https://'), findsNothing);
    });

    apiTest('Turn off one: confirm, then the row says Turned off', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/document-links', {
        'links': [link('dl_1', 1)],
        'activeCount': 1,
      });
      api.on('POST /vendor/documents/dl_1/revoke', {
        'link': link('dl_1', 1, active: false),
      });
      final host = await openLinks(tester, api);
      // One active: no "Turn off all".
      expect(find.byKey(const Key('doc-links-revoke-all')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('doc-link-revoke-dl_1')));
      expect(
        find.text(host.tr('vendor.documents.revokeConfirm')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('doc-links-revoke-confirm')));
      await tester.pumpAndSettle();
      expect(api.sent('POST', '/vendor/documents/dl_1/revoke'), isTrue);
      expect(textContaining('Turned off'), findsOneWidget);
      expect(find.byKey(const Key('doc-link-revoke-dl_1')), findsNothing);
      expect(find.text(host.tr('vendor.documents.revoked')), findsOneWidget);
    });

    apiTest('Turn off all (two active)', (tester, api) async {
      api.on('GET /vendor/document-links', {
        'links': [link('dl_1', 1), link('dl_2', 2)],
        'activeCount': 2,
      });
      api.on('POST /vendor/document-links/revoke', {
        'links': [
          link('dl_1', 1, active: false),
          link('dl_2', 2, active: false),
        ],
        'revokedCount': 2,
      });
      await openLinks(tester, api);
      await tapVisible(tester, find.byKey(const Key('doc-links-revoke-all')));
      await tester.tap(find.byKey(const Key('doc-links-revoke-all-confirm')));
      await tester.pumpAndSettle();
      final body =
          api.only('POST', '/vendor/document-links/revoke').body as Map;
      expect(body, {'docType': 'sale', 'docId': 'sal_1'});
      expect(textContaining('Turned off'), findsNWidgets(2));
    });

    apiTest('empty list and load failure', (tester, api) async {
      api.fail('GET /vendor/document-links', 500);
      final host = await openLinks(tester, api);
      expect(find.byKey(const Key('doc-links-error')), findsOneWidget);
      api.heal('GET /vendor/document-links');
      api.on('GET /vendor/document-links', {'links': [], 'activeCount': 0});
      await tester.tap(find.text(host.tr('common.retry')));
      await tester.pumpAndSettle();
      expect(find.text(host.tr('vendor.documents.noLinks')), findsOneWidget);
    });

    apiTest('voided sale: no Share; links still reachable to turn off', (
      tester,
      api,
    ) async {
      seedPos(api, tools: docsOn);
      api.on('GET /vendor/sales/sal_1', {'sale': serverSale(status: 'voided')});
      api.on('GET /vendor/document-links', {
        'links': [link('dl_1', 1)],
        'activeCount': 1,
      });
      final host = await pumpPage(
        tester,
        api,
        const SaleDetailPage(saleId: 'sal_1'),
        user: owner,
        size: const Size(420, 1400),
        extraRoutes: salesRoutes,
      );
      expect(find.byKey(const Key('sale-detail-share')), findsNothing);
      expect(find.text(host.tr('vendor.documents.voidedNote')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sale-detail-links')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('doc-link-revoke-dl_1')), findsOneWidget);
    });
  });

  group('tax details', () {
    Map<String, dynamic> profile({
      String status = 'none',
      bool registered = false,
      bool tinFromKyc = true,
      Map<String, dynamic>? verified,
      String? reason,
    }) => {
      'taxProfile': {
        'vatRegistered': registered,
        'tin': tinFromKyc ? '123456789' : null,
        'tinFromKyc': tinFromKyc,
        'vrn': registered ? '40012345X' : null,
        'certificateDocumentId': registered ? 'pdoc_1' : null,
        'pricesIncludeVat': true,
        'status': status,
        'rejectReason': reason,
        'rejectNote': null,
        'verifiedAt': verified == null ? null : '2026-10-19T08:00:00.000Z',
        'inForce': verified != null,
        'changePending': false,
        'verified': verified,
        'pending': null,
        'updatedAt': '2026-10-20T08:00:00.000Z',
      },
    };

    Future<PageHost> pumpTax(
      WidgetTester tester,
      RecordingApi api, {
      Map<String, dynamic> user = owner,
      Map<String, dynamic> tools = const {'vat': true},
      PickedDocument? picked,
    }) {
      api.on('GET /vendor/tools/options', tools);
      return pumpPage(
        tester,
        api,
        TaxDetailsPage(pickDocument: (_) async => picked),
        user: user,
        size: const Size(420, 1400),
        extraRoutes: salesRoutes,
      );
    }

    apiTest('vat off: the page leaves at once, nothing loaded', (
      tester,
      api,
    ) async {
      await pumpTax(tester, api, tools: const {'vat': false});
      expect(textContaining('ROUTE-VENDOR-HOME'), findsOneWidget);
      expect(api.sent('GET', '/vendor/tax-profile'), isFalse);
    });

    apiTest('owner registers: VRN + certificate, PUT body, waiting status', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tax-profile', profile());
      api.on('POST /me/kyc/documents/vat_certificate/file', {
        'documents': [
          {
            'id': 'pdoc_9',
            'requirementKey': 'vat_certificate',
            'status': 'pending',
            'createdAt': '2026-10-20T08:00:00.000Z',
          },
        ],
      });
      api.on(
        'PUT /vendor/tax-profile',
        profile(status: 'pending', registered: true),
      );
      final host = await pumpTax(
        tester,
        api,
        picked: PickedDocument(Uint8List.fromList([1, 2, 3]), 'vat.pdf'),
      );
      expect(find.text(host.tr('vendor.tax.statusNone')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tax-registered')));
      await tester.pumpAndSettle();
      // TIN comes from KYC, read-only.
      expect(find.text(host.tr('vendor.tax.tinFromKyc')), findsOneWidget);
      // Save without VRN / certificate: both errors.
      await tapVisible(tester, find.byKey(const Key('tax-save')));
      expect(find.text(host.tr('vendor.tax.vrnInvalid')), findsOneWidget);
      expect(find.text(host.tr('vendor.tax.certRequired')), findsOneWidget);
      expect(api.sent('PUT', '/vendor/tax-profile'), isFalse);
      await typeInto(tester, find.byKey(const Key('tax-vrn')), '40-012345-x');
      await tapVisible(tester, find.byKey(const Key('tax-cert-file')));
      final upload = api.only('POST', '/me/kyc/documents/vat_certificate/file');
      expect((upload.body as Map)['fields'], {'docType': 'vat_certificate'});
      await tapVisible(tester, find.byKey(const Key('tax-save')));
      final put = api.only('PUT', '/vendor/tax-profile').body as Map;
      expect(put['vatRegistered'], isTrue);
      expect(put['vrn'], '40012345X');
      expect(put['certificateDocumentId'], 'pdoc_9');
      expect(put['updatedAt'], '2026-10-20T08:00:00.000Z');
      // The KYC TIN is the server's; the app does not send its own.
      expect(put.containsKey('tin'), isFalse);
      expect(find.text(host.tr('vendor.tax.statusPending')), findsOneWidget);
    });

    apiTest('staff with payments: read-only, Only the owner…', (
      tester,
      api,
    ) async {
      api.on(
        'GET /vendor/tax-profile',
        profile(
          status: 'verified',
          registered: true,
          verified: {
            'tin': '123456789',
            'vrn': '40012345X',
            'verifiedAt': '2026-10-19T08:00:00.000Z',
            'certificateStands': true,
          },
        ),
      );
      final host = await pumpTax(
        tester,
        api,
        user: staffUser(['payments'], role: 'finance'),
      );
      expect(find.byKey(const Key('tax-owner-only')), findsOneWidget);
      expect(find.text(host.tr('vendor.tax.ownerOnly')), findsOneWidget);
      expect(find.byKey(const Key('tax-save')), findsNothing);
      expect(find.byKey(const Key('tax-cert-file')), findsNothing);
      final sw = tester.widget<SwitchListTile>(
        find.byKey(const Key('tax-registered')),
      );
      expect(sw.onChanged, isNull);
    });

    apiTest('staff without payments cannot open it', (tester, api) async {
      final host = await pumpTax(tester, api, user: staffUser(['sales']));
      expect(textContaining('ROUTE-VENDOR-HOME'), findsOneWidget);
      expect(host.snack(host.tr('vendor.tax.noAccess')), findsOneWidget);
      expect(api.sent('GET', '/vendor/tax-profile'), isFalse);
    });

    apiTest('403 owner_only on save is shown, not a generic error', (
      tester,
      api,
    ) async {
      api.on(
        'GET /vendor/tax-profile',
        profile(registered: true, status: 'pending'),
      );
      api.fail('PUT /vendor/tax-profile', 403, {'error': 'owner_only'});
      final host = await pumpTax(tester, api);
      await tapVisible(tester, find.byKey(const Key('tax-save')));
      expect(find.byKey(const Key('tax-save-error')), findsOneWidget);
      expect(find.text(host.tr('vendor.tax.ownerOnly')), findsOneWidget);
    });

    apiTest('kyc_tin_invalid: the TIN field says to fix it in verification', (
      tester,
      api,
    ) async {
      api.on(
        'GET /vendor/tax-profile',
        profile(registered: true, status: 'pending'),
      );
      api.fail('PUT /vendor/tax-profile', 400, {'error': 'kyc_tin_invalid'});
      final host = await pumpTax(tester, api);
      await tapVisible(tester, find.byKey(const Key('tax-save')));
      expect(find.text(host.tr('vendor.tax.kycTinInvalid')), findsOneWidget);
      expect(find.byKey(const Key('tax-save-error')), findsNothing);
    });

    apiTest('409 tax_profile_changed reloads with a notice', (
      tester,
      api,
    ) async {
      api.on(
        'GET /vendor/tax-profile',
        profile(registered: true, status: 'pending'),
      );
      api.fail('PUT /vendor/tax-profile', 409, {
        'error': 'tax_profile_changed',
      });
      final host = await pumpTax(tester, api);
      api.clear();
      await tapVisible(tester, find.byKey(const Key('tax-save')));
      expect(api.sent('GET', '/vendor/tax-profile'), isTrue);
      expect(
        host.snack(host.tr('vendor.tax.changedElsewhere')),
        findsOneWidget,
      );
    });

    apiTest('rejected: reason shown with Send again', (tester, api) async {
      api.on(
        'GET /vendor/tax-profile',
        profile(
          registered: true,
          status: 'rejected',
          reason: 'number_mismatch',
        ),
      );
      final host = await pumpTax(tester, api);
      expect(
        find.text(
          fillIn(host.tr('vendor.tax.statusRejected'), {
            'reason': host.tr('vendor.tax.reason.number_mismatch'),
          }),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('tax-send-again')), findsOneWidget);
    });

    apiTest('stopping VAT on a verified profile asks first, then saves off', (
      tester,
      api,
    ) async {
      api.on(
        'GET /vendor/tax-profile',
        profile(
          status: 'verified',
          registered: true,
          verified: {'vrn': '40012345X', 'certificateStands': true},
        ),
      );
      api.on('PUT /vendor/tax-profile', profile());
      final host = await pumpTax(tester, api);
      await tester.tap(find.byKey(const Key('tax-registered')));
      await tester.pumpAndSettle();
      expect(find.text(host.tr('vendor.tax.stopConfirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tax-stop-confirm')));
      await tester.pumpAndSettle();
      final put = api.only('PUT', '/vendor/tax-profile').body as Map;
      expect(put['vatRegistered'], isFalse);
      expect(put.containsKey('vrn'), isFalse);
    });

    apiTest('verified certificate no longer stands: notice + Send again', (
      tester,
      api,
    ) async {
      api.on(
        'GET /vendor/tax-profile',
        profile(
          status: 'verified',
          registered: true,
          verified: {'vrn': '40012345X', 'certificateStands': false},
        ),
      );
      await pumpTax(tester, api);
      expect(
        find.text(
          'Your VAT certificate is no longer accepted. VAT stops on new '
          'sales until you send a new one.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('tax-send-again')), findsOneWidget);
    });

    test('push vendor_vat_verified / rejected open Tax details', () {
      for (final type in ['vendor_vat_verified', 'vendor_vat_rejected']) {
        expect(
          partnerRouteFor(side: 'vendor', type: type),
          '/vendor/settings/tax',
        );
        expect(partnerLinkFor(side: 'vendor', type: type), 'tax');
      }
      // Not for other sides.
      expect(
        partnerRouteFor(side: 'trainer', type: 'vendor_vat_verified'),
        isNull,
      );
    });
  });

  group('product VAT code', () {
    const codes = [
      VatCodeOption(code: 'A', ratePct: 18),
      VatCodeOption(code: 'C', ratePct: 0),
      VatCodeOption(code: 'E', exempt: true),
    ];

    Future<Map<String, dynamic>?> saveForm(
      WidgetTester tester,
      RecordingApi api, {
      List<VatCodeOption>? vatCodes,
      String? pick,
      Map<String, dynamic>? product,
    }) async {
      Map<String, dynamic>? saved;
      final form = VendorProductForm(
        product:
            product ??
            {
              'id': 'p1',
              'name': 'Whey',
              'priceTzs': 45000,
              'stock': 3,
              'status': 'active',
              'approvalStatus': 'approved',
              'variants': [],
              'vatCode': 'E',
            },
        stockLedger: true,
        canSeeCost: true,
        vatCodes: vatCodes,
        onSave: (body) async => saved = body,
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
      if (pick != null) {
        await tapVisible(
          tester,
          find.byKey(const Key('vendor-product-vat-code')),
        );
        // The labels the server's codes give (§6.4).
        expect(find.text('A · Standard 18%'), findsWidgets);
        expect(find.text('E · Exempt'), findsWidgets);
        await tester.tap(find.text(pick).last);
        await tester.pumpAndSettle();
      }
      await tapVisible(tester, find.byKey(const Key('vendor-product-save')));
      return saved;
    }

    apiTest('shown with codes: labels, stored code kept, picked code sent', (
      tester,
      api,
    ) async {
      final body = await saveForm(
        tester,
        api,
        vatCodes: codes,
        pick: 'C · Zero-rated 0%',
      );
      expect(body!['vatCode'], 'C');
      // Only the private VAT field changed: no reviewed field differs from
      // the product (the server decides approval; vatCode is not reviewed).
      expect(body['name'], 'Whey');
      expect(body['priceTzs'], 45000);
    });

    apiTest('labels A · Standard 18%, E · Exempt; stored E preselected', (
      tester,
      api,
    ) async {
      final body = await saveForm(tester, api, vatCodes: codes);
      expect(body!['vatCode'], 'E');
    });

    apiTest('hidden without codes (vat off / never verified)', (
      tester,
      api,
    ) async {
      final body = await saveForm(tester, api);
      expect(find.byKey(const Key('vendor-product-vat-code')), findsNothing);
      expect(body!.containsKey('vatCode'), isFalse);
    });

    /// The vendor home with one product; answers whether the product form
    /// shows the VAT code field.
    Future<bool> homeShowsVatField(
      WidgetTester tester,
      RecordingApi api, {
      required Map<String, dynamic> tools,
      Map<String, dynamic> user = owner,
      Map<String, dynamic>? taxProfile,
    }) async {
      api.on('GET /vendor/products', [
        {
          'id': 'p1',
          'name': 'Whey',
          'priceTzs': 45000,
          'stock': 3,
          'status': 'active',
          'approvalStatus': 'approved',
          'variants': [],
        },
      ]);
      api.on('GET /vendor/orders', []);
      api.on('GET /vendor/profile', {
        'businessName': 'Store',
        'status': 'published',
      });
      api.on('GET /vendor/payments', {});
      api.on('GET /vendor/enquiries', []);
      api.on('GET /vendor/staff', []);
      api.on('GET /vendor/tools/options', {'stockLedger': true, ...tools});
      api.on('GET /vendor/stock/low', []);
      if (taxProfile != null) {
        api.on('GET /vendor/tax-profile', {'taxProfile': taxProfile});
      } else {
        // Staff without `payments` (as the server answers).
        api.fail('GET /vendor/tax-profile', 403, {
          'error': 'vendor_permission_forbidden',
        });
      }
      api.on('GET /vendor/tax-rates', {
        'codes': [
          {'code': 'A', 'ratePct': 18, 'exempt': false},
          {'code': 'E', 'ratePct': null, 'exempt': true},
        ],
      });
      final host = await pumpPage(
        tester,
        api,
        const VendorHomePage(),
        user: user,
        size: const Size(420, 1200),
        keepRequests: true,
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('vendor-product-p1')),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(host.tr('vendor.edit')).last);
      await tester.pumpAndSettle();
      return find
          .byKey(const Key('vendor-product-vat-code'))
          .evaluate()
          .isNotEmpty;
    }

    apiTest('products-only staff + vatInForce true: field, no tax profile', (
      tester,
      api,
    ) async {
      final shown = await homeShowsVatField(
        tester,
        api,
        tools: {'vat': true, 'vatInForce': true},
        user: staffUser(['products'], role: 'products'),
      );
      expect(shown, isTrue);
      expect(api.sent('GET', '/vendor/tax-profile'), isFalse);
      expect(api.sent('GET', '/vendor/tax-rates'), isTrue);
    });

    apiTest('vatInForce false: no field, nothing asked (wins over profile)', (
      tester,
      api,
    ) async {
      final shown = await homeShowsVatField(
        tester,
        api,
        tools: {'vat': true, 'vatInForce': false},
        taxProfile: {
          'status': 'verified',
          'verified': {'vrn': '40012345X'},
        },
      );
      expect(shown, isFalse);
      expect(api.sent('GET', '/vendor/tax-profile'), isFalse);
      expect(api.sent('GET', '/vendor/tax-rates'), isFalse);
    });

    apiTest('vat off: no field even with vatInForce true', (tester, api) async {
      final shown = await homeShowsVatField(
        tester,
        api,
        tools: {'vat': false, 'vatInForce': true},
      );
      expect(shown, isFalse);
      expect(api.sent('GET', '/vendor/tax-rates'), isFalse);
    });

    apiTest('no vatInForce (older backend): verified profile → field', (
      tester,
      api,
    ) async {
      final shown = await homeShowsVatField(
        tester,
        api,
        tools: {'vat': true},
        taxProfile: {
          'status': 'verified',
          'verified': {'vrn': '40012345X'},
        },
      );
      expect(shown, isTrue);
      expect(api.sent('GET', '/vendor/tax-profile'), isTrue);
    });

    apiTest('no vatInForce: never verified → no field, no codes asked', (
      tester,
      api,
    ) async {
      final shown = await homeShowsVatField(
        tester,
        api,
        tools: {'vat': true},
        taxProfile: {'status': 'pending', 'verified': null},
      );
      expect(shown, isFalse);
      expect(api.sent('GET', '/vendor/tax-rates'), isFalse);
    });

    apiTest('no vatInForce: products-only staff (profile 403) → no field', (
      tester,
      api,
    ) async {
      final shown = await homeShowsVatField(
        tester,
        api,
        tools: {'vat': true},
        user: staffUser(['products'], role: 'products'),
      );
      expect(shown, isFalse);
      expect(api.sent('GET', '/vendor/tax-rates'), isFalse);
    });

    test('tools: vatInForce only as a boolean, else unknown', () {
      expect(VendorTools.fromOptions({'vatInForce': true}).vatInForce, isTrue);
      expect(
        VendorTools.fromOptions({'vatInForce': false}).vatInForce,
        isFalse,
      );
      expect(VendorTools.fromOptions({'vatInForce': 'yes'}).vatInForce, isNull);
      expect(VendorTools.fromOptions({}).vatInForce, isNull);
    });
  });

  group('order and buyer invoices', () {
    Map<String, dynamic> order({String payment = 'paid'}) => {
      'id': 'ord_1',
      'shortRef': 'ABC123',
      'status': 'pending',
      'items': [
        {'name': 'Whey', 'qty': 1},
      ],
      'totalTzs': 45000,
      'paymentStatus': payment,
      'paymentMethod': 'mpesa',
      'deliveryMethod': 'delivery',
    };

    Map<String, dynamic> invoiceDoc({
      String vendorId = 'v1',
      String number = 'INV-000007',
    }) => {
      'docType': 'order_invoice',
      'number': number,
      'orderShortRef': 'ABC123',
      'status': 'paid',
      'issuedAt': '2026-10-20T08:00:00.000Z',
      'lang': 'en',
      'seller': {
        'businessName': 'Dar Gear',
        'tin': '123456789',
        'vrn': '40012345X',
      },
      'soldVia': 'Seller: Dar Gear. Sold through the FitFlex app.',
      'customer': {'name': 'Neema'},
      'lines': [
        {
          'name': 'Whey',
          'variant': null,
          'qty': 1,
          'unitPriceTzs': 10000,
          'discountTzs': 0,
          'amountTzs': 10000,
          'vatCode': 'A',
        },
      ],
      'subtotalTzs': 10000,
      'discountsTzs': 0,
      'totalTzs': 10000,
      'vatIncludedTzs': 1525,
      'vatSummary': [
        {'code': 'A', 'ratePct': 18, 'netTzs': 8475, 'vatTzs': 1525},
      ],
      'payments': [],
      'paymentMethod': 'mpesa',
      'changeTzs': 0,
      'vendorId': vendorId,
    };

    apiTest('order card: Invoice only when paid and documents on', (
      tester,
      api,
    ) async {
      await pumpPage(
        tester,
        api,
        ListView(
          children: [
            VendorOrderCard(
              order: order(),
              tools: VendorTools.fromOptions({'documents': true}),
            ),
            VendorOrderCard(
              order: {
                ...order(payment: 'pending'),
                'id': 'ord_2',
              },
              tools: VendorTools.fromOptions({'documents': true}),
            ),
            VendorOrderCard(
              order: {...order(), 'id': 'ord_3'},
              tools: VendorTools.off,
            ),
          ],
        ),
        user: owner,
        size: const Size(420, 1600),
      );
      expect(
        find.byKey(const Key('vendor-order-invoice-ord_1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('vendor-order-invoice-ord_2')), findsNothing);
      expect(find.byKey(const Key('vendor-order-invoice-ord_3')), findsNothing);
    });

    apiTest('order card: Invoice after a refund too; not for failed', (
      tester,
      api,
    ) async {
      final on = VendorTools.fromOptions({'documents': true});
      await pumpPage(
        tester,
        api,
        ListView(
          children: [
            for (final (id, pay) in const [
              ('ord_rp', 'refund_pending'),
              ('ord_rf', 'refunded'),
              ('ord_fl', 'failed'),
              ('ord_cx', 'cancelled'),
            ])
              VendorOrderCard(
                order: {
                  ...order(payment: pay),
                  'id': id,
                },
                tools: on,
              ),
          ],
        ),
        user: owner,
        size: const Size(420, 2400),
      );
      expect(
        find.byKey(const Key('vendor-order-invoice-ord_rp')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('vendor-order-invoice-ord_rf')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('vendor-order-invoice-ord_fl')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('vendor-order-invoice-ord_cx')),
        findsNothing,
      );
    });

    apiTest('vendor order invoice: seller, sold via, VAT summary, TSh', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', {'documents': true});
      api.on('GET /vendor/documents/order/ord_1', {'doc': invoiceDoc()});
      await pumpPage(
        tester,
        api,
        const VendorOrderInvoicePage(orderId: 'ord_1'),
        user: owner,
        size: const Size(420, 1400),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('doc-title'))).data,
        'Invoice INV-000007',
      );
      expect(
        find.text('Seller: Dar Gear. Sold through the FitFlex app.'),
        findsOneWidget,
      );
      expect(find.text('TIN 123456789'), findsOneWidget);
      expect(find.text('VRN 40012345X'), findsOneWidget);
      expect(find.text('TSh 1,525'), findsOneWidget);
      expect(find.text('A 18%'), findsOneWidget);
      expect(find.text('TSh 10,000'), findsOneWidget);
      expect(textContaining('commission'), findsNothing);
    });

    apiTest('vendor order invoice: not paid yet → after-payment message', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', {'documents': true});
      api.fail('GET /vendor/documents/order/ord_1', 409, {
        'error': 'invoice_not_ready',
      });
      final host = await pumpPage(
        tester,
        api,
        const VendorOrderInvoicePage(orderId: 'ord_1'),
        user: owner,
      );
      expect(
        find.text(host.tr('vendor.documents.invoiceAfterPayment')),
        findsOneWidget,
      );
    });

    apiTest('vendor order invoice: orders-only staff OK, sales-only refused', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', {'documents': true});
      final host = await pumpPage(
        tester,
        api,
        const VendorOrderInvoicePage(orderId: 'ord_1'),
        user: staffUser(['sales']),
        extraRoutes: salesRoutes,
      );
      expect(host.snack(host.tr('vendor.documents.noAccess')), findsOneWidget);
      expect(api.sent('GET', '/vendor/documents/order/ord_1'), isFalse);
    });

    apiTest('buyer: two sellers → one invoice per seller', (tester, api) async {
      api.on('GET /me/shop-orders/ord_1/invoice', {
        'invoices': [
          invoiceDoc(),
          {
            ...invoiceDoc(vendorId: 'v2', number: 'INV-000001'),
            'seller': {'businessName': 'Fit Shop'},
          },
        ],
      });
      final host = await pumpPage(
        tester,
        api,
        const BuyerInvoicePage(orderId: 'ord_1'),
        user: const {'id': 'm1', 'userType': 'member'},
        keepRequests: true,
      );
      expect(find.text(host.tr('shop.invoice.perSeller')), findsOneWidget);
      expect(find.text('INV-000007'), findsOneWidget);
      expect(find.text('INV-000001'), findsOneWidget);
      expect(
        api.only('GET', '/me/shop-orders/ord_1/invoice').query,
        contains('format=json'),
      );
    });

    apiTest('buyer: one seller, Download PDF names the seller', (
      tester,
      api,
    ) async {
      final out = Outside()..install();
      api.on('GET /me/shop-orders/ord_1/invoice', {
        'invoices': [invoiceDoc()],
      });
      await pumpPage(
        tester,
        api,
        const BuyerInvoicePage(orderId: 'ord_1'),
        user: const {'id': 'm1', 'userType': 'member'},
        size: const Size(420, 1400),
      );
      api.clear();
      api.onCall('GET /me/shop-orders/ord_1/invoice', (r) {
        if (r.query.contains('format=pdf')) {
          return const RawResponse(200, '%PDF');
        }
        return {
          'invoices': [invoiceDoc()],
        };
      });
      await tapVisible(tester, find.byKey(const Key('buyer-invoice-pdf')));
      final req = api.only('GET', '/me/shop-orders/ord_1/invoice');
      expect(req.query, contains('vendorId=v1'));
      expect(out.files.single.$2, 'INV-000007.pdf');
      // Buyers never get link sharing.
      expect(find.byKey(const Key('doc-share-copy')), findsNothing);
    });

    apiTest('buyer: 404 → Invoice not found', (tester, api) async {
      api.fail('GET /me/shop-orders/ord_1/invoice', 404, {
        'error': 'invoice_not_ready',
      });
      final host = await pumpPage(
        tester,
        api,
        const BuyerInvoicePage(orderId: 'ord_1'),
        user: const {'id': 'm1', 'userType': 'member'},
      );
      expect(find.text(host.tr('shop.invoice.notFound')), findsOneWidget);
    });
  });

  group('models', () {
    test('SharedLink: both languages, URL with ?lang', () {
      final link = SharedLink.fromJson(shareAnswer());
      expect(link.urlIn('en'), url);
      expect(link.urlIn('sw'), '$url?lang=sw');
      expect(link.whatsappIn('sw'), contains('Itazame hapa'));
      expect(link.smsIn('en'), 'Dar Gear Receipt R-000001 TSh 45,000: $url');
    });

    test('walk-in phone only for manual customers', () {
      expect(
        walkInPhoneDigits({'source': 'manual', 'phone': '+255 712 345 678'}),
        '255712345678',
      );
      expect(
        walkInPhoneDigits({'source': 'marketplace', 'phone': '+255712345678'}),
        isNull,
      );
      expect(walkInPhoneDigits({'source': 'manual'}), isNull);
      expect(walkInPhoneDigits(null), isNull);
    });

    test('TIN / VRN normalising mirrors the server', () {
      expect(normaliseTin('123-456-789'), '123456789');
      expect(normaliseTin('12345678'), isNull);
      expect(normaliseVrn('40-012345-x'), '40012345X');
      expect(normaliseVrn('1234567'), isNull);
    });

    test(
      'tax profile: pending change shows sent values; certificate stands',
      () {
        final p = TaxProfile.fromJson({
          'taxProfile': {
            'status': 'verified',
            'vrn': 'OLD12345',
            'changePending': true,
            'pending': {'vrn': 'NEW12345'},
            'verified': {'vrn': 'OLD12345', 'certificateStands': false},
          },
        });
        expect(p.vrn, 'NEW12345');
        expect(p.everVerified, isTrue);
        expect(p.certificateStands, isFalse);
      },
    );

    test('VAT codes: only A–E; exempt has no rate text', () {
      final codes = vatCodesOf({
        'codes': [
          {'code': 'A', 'ratePct': 18},
          {'code': 'E', 'exempt': true, 'ratePct': null},
          {'code': 'Z', 'ratePct': 5},
        ],
      });
      expect(codes.map((c) => c.code), ['A', 'E']);
      expect(ratePctText(16.5), '16.5%');
      expect(ratePctText(null), isNull);
    });
  });

  group('Swahili', () {
    final s5 = FFLocale.keysOf('en').where(
      (k) =>
          k.startsWith('vendor.documents.') ||
          k.startsWith('vendor.doc.') ||
          k.startsWith('vendor.tax.') ||
          k.startsWith('vendor.vat.') ||
          k.startsWith('vendor.product.vat') ||
          k.startsWith('shop.invoice.') ||
          k == 'inbox.open.tax',
    );

    test('every S5 key has Swahili', () {
      final sw = FFLocale.keysOf('sw');
      expect(s5.length, greaterThan(140));
      expect(s5.where((k) => !sw.contains(k)), isEmpty);
    });

    test('Swahili is a translation, not English left in place', () {
      // Codes and brand words stay as they are (glossary §keep).
      const same = {
        'vendor.documents.whatsapp',
        'vendor.documents.sms',
        'vendor.documents.lang.en',
        'vendor.documents.lang.sw',
        'vendor.doc.vat',
        'vendor.doc.tin',
        'vendor.doc.vrn',
        'vendor.tax.tin',
      };
      final left = [
        for (final k in s5)
          if (!same.contains(k) &&
              FFLocale.textOf('sw', k) == FFLocale.textOf('en', k))
            k,
      ];
      expect(left, isEmpty);
    });

    test('Swahili audit wording (drafts, native review)', () {
      const want = {
        'vendor.doc.servedBy': 'Mhudumu: {name}',
        'vendor.product.vatCode': 'Msimbo wa VAT',
        'vendor.product.vatA11y': 'Msimbo wa VAT wa {product}',
        'vendor.product.vatInvalid': 'Chagua msimbo wa VAT kwenye orodha.',
        'vendor.customers.asOf': 'Kufikia {date}',
        'vendor.tax.stop': 'Zima VAT',
        'vendor.tax.certNotStanding':
            'Cheti chako cha VAT hakikubaliki tena. VAT inasimama kwenye '
            'mauzo mapya hadi utume kipya.',
      };
      want.forEach((k, v) => expect(FFLocale.textOf('sw', k), v, reason: k));
      expect(
        FFLocale.textOf('sw', 'error.network'),
        startsWith('Hakuna intaneti.'),
      );
      expect(
        FFLocale.textOf('sw', 'error.network'),
        isNot(contains('muunganisho')),
      );
      expect(FFLocale.textOf('en', 'vendor.tax.certNoLongerStands'), isNull);
    });

    test('placeholders match between languages', () {
      final ph = RegExp(r'\{(\w+)\}');
      for (final k in s5) {
        Set<String> of(String lang) => ph
            .allMatches(FFLocale.textOf(lang, k) ?? '')
            .map((m) => m[1]!)
            .toSet();
        expect(of('sw'), of('en'), reason: k);
      }
    });

    apiTest('sheet in Kiswahili at 375 and 200% text: no overflow', (
      tester,
      api,
    ) async {
      Outside().install();
      seedPos(api, tools: docsOn);
      final host = await pumpPage(
        tester,
        api,
        SaleReceiptPage(saleId: 'sal_1', sale: serverSale()),
        user: owner,
        lang: 'sw',
        textScale: 2,
        size: const Size(375, 1600),
        extraRoutes: salesRoutes,
      );
      await openSheet(tester);
      expect(find.text(host.tr('vendor.documents.shareText')), findsOneWidget);
      expect(find.text('Tuma kama maandishi'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Rows are at least 56dp tall.
      final row = tester.getSize(find.byKey(const Key('doc-share-copy')));
      expect(row.height, greaterThanOrEqualTo(56));
    });
  });
}
