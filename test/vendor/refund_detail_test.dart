// Vendor tools · S7: the refund detail / credit note (spec §4.4–§4.5) — the
// S5 share sheet with the credit note, the text share when documents are
// off, read-only with the refunds tool off, the undo dialog and its
// answers (insufficient_stock, already_reverted treated as done, 429), and
// the undone state.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/documents/document_share_sheet.dart';
import 'package:fitflexmobile/screens/vendor/sales/receipt_page.dart';
import 'package:fitflexmobile/screens/vendor/sales/refunds/refund_detail_page.dart';

import '../support/recording_api.dart';
import 'refunds_support.dart';

const _id = 'vrf_0000000000000001';

Future<PageHost> pumpDetail(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> tools = refundsOn,
  Map<String, dynamic>? refund,
  Map<String, dynamic> user = ownerUser,
  String lang = 'en',
  bool saved = false,
}) async {
  api.on('GET /vendor/tools/options', tools);
  api.on('GET /vendor/profile', {'businessName': 'Dar Gear'});
  api.on('GET /vendor/refunds/$_id', {'refund': refund ?? refundJson()});
  return pumpPage(
    tester,
    api,
    RefundDetailPage(
      refundId: _id,
      saved: saved,
      now: DateTime.utc(2026, 11, 3, 12),
    ),
    user: user,
    lang: lang,
    size: const Size(400, 1600),
    extraRoutes: refundRoutes,
  );
}

Future<void> openUndo(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('refund-more')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('refund-undo')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  apiTest('the credit note: lines, money, reason and the notice', (
    tester,
    api,
  ) async {
    final host = await pumpDetail(tester, api, saved: true);
    expect(find.text('Credit note CN-000004'), findsOneWidget);
    expect(find.text(host.tr('vendor.refunds.status.active')), findsOneWidget);
    expect(find.text('For receipt R-000123'), findsOneWidget);
    expect(find.text(host.tr('vendor.refunds.backInStock')), findsOneWidget);
    expect(find.text('Reason: Customer returned it'), findsOneWidget);
    expect(find.text(host.tr('vendor.refunds.moneyNotice')), findsOneWidget);
    expect(host.snack('Refund saved: CN-000004'), findsOneWidget);
    expect(find.byKey(const Key('refund-share')), findsOneWidget);
  });

  apiTest('documents on: Share opens the S5 sheet for the credit note', (
    tester,
    api,
  ) async {
    final launched = <Uri>[];
    final launch = DocumentActions.launch;
    DocumentActions.launch = (uri) async {
      launched.add(uri);
      return true;
    };
    addTearDown(() => DocumentActions.launch = launch);
    api.on('GET /vendor/document-links', {'links': [], 'activeCount': 0});
    api.on('POST /vendor/refunds/$_id/share', {
      'linkId': 'lnk_1',
      'url': 'https://api.example/d/abc',
      'lang': 'en',
      'docType': 'credit_note',
      'docId': _id,
      'number': 'CN-000004',
      'texts': {
        'en': {'whatsapp': 'Credit note CN-000004 https://api.example/d/abc'},
      },
    });
    await pumpDetail(tester, api, tools: {...refundsOn, 'documents': true});
    await tapVisible(tester, find.byKey(const Key('refund-share')));
    expect(find.textContaining('CN-000004'), findsWidgets);
    await tapVisible(tester, find.byKey(const Key('doc-share-whatsapp')));
    expect(api.sent('POST', '/vendor/refunds/$_id/share'), isTrue);
    expect(launched.single.toString(), contains('wa.me'));
  });

  apiTest('documents off: the credit note as text', (tester, api) async {
    final shared = <String>[];
    final keep = shareReceipt;
    shareReceipt = (text, subject) async => shared.add(text);
    addTearDown(() => shareReceipt = keep);
    await pumpDetail(tester, api);
    await tapVisible(tester, find.byKey(const Key('refund-share')));
    expect(shared.single, contains('Credit note CN-000004'));
    expect(shared.single, contains('For receipt R-000123'));
    expect(shared.single, isNot(contains('Customer returned it')));
  });

  apiTest('refunds off: read-only (no Share, no Undo)', (tester, api) async {
    await pumpDetail(tester, api, tools: refundsOff);
    expect(find.text('Credit note CN-000004'), findsOneWidget);
    expect(find.byKey(const Key('refund-share')), findsNothing);
    expect(find.byKey(const Key('refund-more')), findsNothing);
    expect(find.byKey(const Key('refund-done')), findsOneWidget);
  });

  apiTest('undo needs a reason; success updates in place', (tester, api) async {
    final host = await pumpDetail(tester, api);
    await openUndo(tester);
    expect(find.text('Undo refund CN-000004?'), findsOneWidget);
    expect(find.byKey(const Key('refund-revert-stock')), findsOneWidget);
    expect(
      isEnabled(tester, find.byKey(const Key('refund-revert-confirm'))),
      isFalse,
    );
    await typeInto(
      tester,
      find.byKey(const Key('refund-revert-reason')),
      'Wrong sale',
    );
    api.on('POST /vendor/refunds/$_id/revert', {
      'refund': refundJson(status: 'reverted'),
      'sale': refundSale(),
    });
    await tapVisible(tester, find.byKey(const Key('refund-revert-confirm')));
    expect(api.only('POST', '/vendor/refunds/$_id/revert').body, {
      'reason': 'Wrong sale',
    });
    expect(find.text(host.tr('vendor.refunds.status.reverted')), findsWidgets);
    expect(find.byKey(const Key('refund-reverted-by')), findsOneWidget);
    expect(find.byKey(const Key('refund-share')), findsNothing);
    expect(host.snack('Refund CN-000004 undone'), findsOneWidget);
  });

  apiTest('undo: insufficient_stock keeps the dialog with Count stock', (
    tester,
    api,
  ) async {
    await pumpDetail(tester, api);
    await openUndo(tester);
    await typeInto(
      tester,
      find.byKey(const Key('refund-revert-reason')),
      'Wrong sale',
    );
    api.fail('POST /vendor/refunds/$_id/revert', 409, {
      'error': 'insufficient_stock',
      'productId': 'p1',
      'variant': null,
      'available': 0,
    });
    await tapVisible(tester, find.byKey(const Key('refund-revert-confirm')));
    expect(
      find.text(
        "Only 0 of Whey left in stock, so this refund can't be undone. "
        'Count the stock first.',
      ),
      findsOneWidget,
    );
    await tapVisible(
      tester,
      find.byKey(const Key('refund-revert-count-stock')),
    );
    expect(find.text('ROUTE-STOCK p1'), findsOneWidget);
  });

  apiTest('undo retried after a lost answer: already_reverted is done', (
    tester,
    api,
  ) async {
    final host = await pumpDetail(tester, api);
    await openUndo(tester);
    await typeInto(
      tester,
      find.byKey(const Key('refund-revert-reason')),
      'Wrong sale',
    );
    api.fail('POST /vendor/refunds/$_id/revert', 409, {
      'error': 'already_reverted',
      'revertedAt': '2026-11-03T12:00:00.000Z',
    });
    api.on('GET /vendor/refunds/$_id', {
      'refund': refundJson(status: 'reverted'),
    });
    await tapVisible(tester, find.byKey(const Key('refund-revert-confirm')));
    expect(find.byKey(const Key('refund-revert-confirm')), findsNothing);
    expect(find.byKey(const Key('refund-reverted-by')), findsOneWidget);
    expect(host.snack('Refund CN-000004 undone'), findsOneWidget);
  });

  apiTest('undo: 429 says wait, nothing changed', (tester, api) async {
    final host = await pumpDetail(tester, api);
    await openUndo(tester);
    await typeInto(
      tester,
      find.byKey(const Key('refund-revert-reason')),
      'Wrong sale',
    );
    api.fail('POST /vendor/refunds/$_id/revert', 429, {
      'error': 'rate_limited',
      'retryAfterSeconds': 30,
    });
    await tapVisible(tester, find.byKey(const Key('refund-revert-confirm')));
    expect(
      find.text(host.tr('vendor.refunds.err.rateLimited')),
      findsOneWidget,
    );
  });

  apiTest('staff: no Undo on another person\'s refund', (tester, api) async {
    await pumpDetail(
      tester,
      api,
      refund: refundJson(createdById: 'someone'),
      user: const {
        'id': 's1',
        'userType': 'vendor_staff',
        'vendorId': 'v1',
        'vendorPermissions': ['sales'],
      },
    );
    expect(find.byKey(const Key('refund-more')), findsNothing);
    expect(find.byKey(const Key('refund-share')), findsOneWidget);
  });

  apiTest('unknown refund: not found', (tester, api) async {
    api.on('GET /vendor/tools/options', refundsOn);
    api.fail('GET /vendor/refunds/$_id', 404, {'error': 'refund_not_found'});
    final host = await pumpPage(
      tester,
      api,
      const RefundDetailPage(refundId: _id),
      user: ownerUser,
      extraRoutes: refundRoutes,
    );
    expect(find.text(host.tr('vendor.refunds.notFound')), findsOneWidget);
  });

  apiTest('Swahili undone credit note', (tester, api) async {
    await pumpDetail(
      tester,
      api,
      lang: 'sw',
      refund: refundJson(status: 'reverted'),
    );
    expect(find.text('Hati ya marejesho CN-000004'), findsOneWidget);
    expect(find.text('Imetenduliwa'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
