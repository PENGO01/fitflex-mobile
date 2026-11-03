// Vendor tools · S7: the refund screen (spec §4.2–§4.7) — gating, steppers
// capped at refundable, restock default on, method hidden when nothing is
// paid back, the reference rule, Review's reasons, the exact request (no
// amounts), 409 refund_exceeds_sold clamping, restock_unavailable, and
// online only: a network failure keeps the dialog and Try again reuses the
// same clientRef, nothing is queued on the device.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/screens/vendor/sales/refunds/refund_page.dart';

import '../support/recording_api.dart';
import 'refunds_support.dart';

Future<PageHost> pumpRefund(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> tools = refundsOn,
  Map<String, dynamic>? sale,
  Map<String, dynamic> user = ownerUser,
  String lang = 'en',
}) async {
  api.on('GET /vendor/tools/options', tools);
  api.on('GET /vendor/sales/sal_1', {'sale': sale ?? refundSale()});
  return pumpPage(
    tester,
    api,
    const RefundPage(saleId: 'sal_1'),
    user: user,
    lang: lang,
    size: const Size(400, 2000),
    extraRoutes: refundRoutes,
  );
}

Future<void> tapKey(WidgetTester tester, String key) =>
    tapVisible(tester, find.byKey(Key(key)));

void main() {
  setUpAll(loadAppFonts);

  apiTest('refunds off: straight back to the sale, no message', (
    tester,
    api,
  ) async {
    await pumpRefund(tester, api, tools: refundsOff);
    expect(find.text('ROUTE-SALE sal_1'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  apiTest('staff who may not refund this sale: back with why', (
    tester,
    api,
  ) async {
    final host = await pumpRefund(
      tester,
      api,
      sale: refundSale(createdById: 'other'),
      user: const {
        'id': 's1',
        'userType': 'vendor_staff',
        'vendorId': 'v1',
        'vendorPermissions': ['sales'],
      },
    );
    expect(find.text('ROUTE-SALE sal_1'), findsOneWidget);
    expect(host.snack(host.tr('vendor.refunds.askOwner')), findsOneWidget);
  });

  apiTest('fully refunded and voided sales say so', (tester, api) async {
    final host = await pumpRefund(
      tester,
      api,
      sale: refundSale(wheyRefunded: 3, wheyRefundedTzs: 10000, matRefunded: 1),
    );
    expect(find.text(host.tr('vendor.refunds.fully')), findsOneWidget);
    expect(find.byKey(const Key('refund-review')), findsNothing);
  });

  apiTest('a voided sale cannot be refunded', (tester, api) async {
    final host = await pumpRefund(
      tester,
      api,
      sale: refundSale(status: 'voided'),
    );
    expect(find.text(host.tr('vendor.refunds.err.saleVoided')), findsOneWidget);
  });

  apiTest('offline at open: no answer, Try again', (tester, api) async {
    api.on('GET /vendor/tools/options', refundsOn);
    api.onCall('GET /vendor/sales/sal_1', (_) => throw Exception('offline'));
    final host = await pumpPage(
      tester,
      api,
      const RefundPage(saleId: 'sal_1'),
      user: ownerUser,
      extraRoutes: refundRoutes,
    );
    expect(find.text(host.tr('error.network')), findsOneWidget);
  });

  apiTest('steppers, restock, reason, reference and the exact request', (
    tester,
    api,
  ) async {
    final host = await pumpRefund(tester, api);
    expect(find.text('Refund from R-000123'), findsOneWidget);
    expect(find.text(host.tr('vendor.refunds.moneyNotice')), findsOneWidget);
    // Review waits for a pick.
    expect(isEnabled(tester, find.byKey(const Key('refund-review'))), isFalse);
    expect(find.text(host.tr('vendor.refunds.selectSome')), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      final inc = find.byKey(const Key('refund-inc-sln_a'));
      if (tester.widget<IconButton>(inc).onPressed == null) break;
      await tapVisible(tester, inc);
    }
    // Capped at the 3 sold.
    expect(find.byKey(const Key('refund-qty-sln_a')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('refund-qty-sln_a'))).data,
      '3',
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('refund-inc-sln_a')))
          .onPressed,
      isNull,
    );
    await tapVisible(tester, find.byKey(const Key('refund-dec-sln_a')));
    await tapVisible(tester, find.byKey(const Key('refund-dec-sln_a')));
    // One unit: 3,333 (AC-6), restock on by default.
    expect(find.text('TSh 3,333'), findsWidgets);
    final restock = tester.widget<SwitchListTile>(
      find.byKey(const Key('refund-restock-sln_a')),
    );
    expect(restock.value, isTrue);
    expect(find.text(host.tr('vendor.refunds.reasonMissing')), findsOneWidget);
    await tapKey(tester, 'refund-reason-returned');
    // The sale was paid by M-Pesa: that is the default, and it needs a ref.
    expect(find.text(host.tr('vendor.pos.referenceRequired')), findsOneWidget);
    expect(isEnabled(tester, find.byKey(const Key('refund-review'))), isFalse);
    await typeInto(tester, find.byKey(const Key('refund-reference')), 'QX9');
    await tester.pumpAndSettle();
    expect(isEnabled(tester, find.byKey(const Key('refund-review'))), isTrue);
    expect(find.text('Review refund TSh 3,333'), findsOneWidget);

    api.on('POST /vendor/sales/sal_1/refunds', {
      'refund': refundJson(method: 'mpesa', reference: 'QX9'),
      'sale': refundSale(wheyRefunded: 1, wheyRefundedTzs: 3333),
    });
    await tapKey(tester, 'refund-review');
    expect(find.text('Refund TSh 3,333 from R-000123?'), findsOneWidget);
    await tapKey(tester, 'refund-confirm');
    final req = api.only('POST', '/vendor/sales/sal_1/refunds');
    final body = req.body as Map;
    expect(body['lines'], [
      {'saleLineId': 'sln_a', 'qty': 1, 'restock': true},
    ]);
    expect(body['reason'], 'Customer returned it');
    expect(body['method'], 'mpesa');
    expect(body['reference'], 'QX9');
    expect(body['clientRef'], matches(RegExp(r'^[A-Za-z0-9._:-]{8,100}$')));
    expect(body.keys.where((k) => k.toString().endsWith('Tzs')), isEmpty);
    // Nothing to pop to: the refund detail, as just saved.
    expect(
      find.text('ROUTE-REFUND-DETAIL vrf_0000000000000001 saved=1'),
      findsOneWidget,
    );
  });

  apiTest('credit sale within the balance: no method asked', (
    tester,
    api,
  ) async {
    final host = await pumpRefund(
      tester,
      api,
      sale: refundSale(kind: 'credit', balanceTzs: 20000),
    );
    await tapKey(tester, 'refund-inc-sln_b');
    expect(find.byKey(const Key('refund-off-balance')), findsOneWidget);
    expect(find.text(host.tr('vendor.refunds.nothingBack')), findsOneWidget);
    expect(find.byKey(const Key('refund-method-cash')), findsNothing);
    await tapKey(tester, 'refund-reason-faulty');
    expect(isEnabled(tester, find.byKey(const Key('refund-review'))), isTrue);
  });

  apiTest('409 refund_exceeds_sold: reload, clamp, highlight', (
    tester,
    api,
  ) async {
    final host = await pumpRefund(
      tester,
      api,
      sale: refundSale(
        payments: const [
          {'method': 'cash', 'amountTzs': 20000},
        ],
      ),
    );
    await tapKey(tester, 'refund-all');
    await tapKey(tester, 'refund-reason-wrong');
    api.fail('POST /vendor/sales/sal_1/refunds', 409, {
      'error': 'refund_exceeds_sold',
      'lines': [
        {
          'saleLineId': 'sln_a',
          'soldQty': 3,
          'refundedQty': 2,
          'refundableQty': 1,
        },
      ],
    });
    // Someone else refunded 2 Whey meanwhile.
    api.on('GET /vendor/sales/sal_1', {
      'sale': refundSale(wheyRefunded: 2, wheyRefundedTzs: 6666),
    });
    await tapKey(tester, 'refund-review');
    await tapKey(tester, 'refund-confirm');
    expect(find.byKey(const Key('refund-confirm')), findsNothing);
    expect(find.byKey(const Key('refund-exceeds')), findsOneWidget);
    expect(find.byKey(const Key('refund-line-exceeds-sln_a')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('refund-qty-sln_a'))).data,
      '1',
    );
    expect(host.tr('vendor.refunds.err.exceeds'), isNotEmpty);
  });

  apiTest('restock_unavailable turns that line\'s restock off', (
    tester,
    api,
  ) async {
    await pumpRefund(tester, api);
    await tapKey(tester, 'refund-inc-sln_b');
    await tapKey(tester, 'refund-reason-faulty');
    await tapKey(tester, 'refund-method-cash');
    api.fail('POST /vendor/sales/sal_1/refunds', 400, {
      'error': 'restock_unavailable',
      'saleLineId': 'sln_b',
      'productId': 'p2',
    });
    await tapKey(tester, 'refund-review');
    await tapKey(tester, 'refund-confirm');
    final sw = tester.widget<SwitchListTile>(
      find.byKey(const Key('refund-restock-sln_b')),
    );
    expect(sw.value, isFalse);
    expect(sw.onChanged, isNull);
    expect(find.byKey(const Key('refund-restock-gone-sln_b')), findsOneWidget);
  });

  apiTest('line_not_on_sale: the sale is read again, its lines shown', (
    tester,
    api,
  ) async {
    await pumpRefund(tester, api);
    await tapKey(tester, 'refund-inc-sln_b');
    await tapKey(tester, 'refund-reason-wrong');
    await tapKey(tester, 'refund-method-cash');
    api.fail('POST /vendor/sales/sal_1/refunds', 400, {
      'error': 'line_not_on_sale',
      'saleLineId': 'sln_b',
    });
    final fresh = refundSale();
    (fresh['lines'] as List).removeLast();
    api.on('GET /vendor/sales/sal_1', {'sale': fresh});
    api.clear();
    await tapKey(tester, 'refund-review');
    await tapKey(tester, 'refund-confirm');
    expect(api.sent('GET', '/vendor/sales/sal_1'), isTrue);
    expect(find.byKey(const Key('refund-confirm-error')), findsNothing);
    expect(find.byKey(const Key('refund-line-sln_b')), findsNothing);
    expect(find.byKey(const Key('refund-line-sln_a')), findsOneWidget);
    expect(isEnabled(tester, find.byKey(const Key('refund-review'))), isFalse);
  });

  apiTest('method_required: the method section says what is missing', (
    tester,
    api,
  ) async {
    final host = await pumpRefund(
      tester,
      api,
      sale: refundSale(kind: 'credit', balanceTzs: 20000),
    );
    await tapKey(tester, 'refund-inc-sln_b');
    await tapKey(tester, 'refund-reason-faulty');
    api.fail('POST /vendor/sales/sal_1/refunds', 400, {
      'error': 'method_required',
    });
    await tapKey(tester, 'refund-review');
    await tapKey(tester, 'refund-confirm');
    expect(find.text(host.tr('vendor.refunds.methodMissing')), findsOneWidget);
    expect(find.byKey(const Key('refund-method-cash')), findsOneWidget);
  });

  apiTest('network failure: dialog stays; Try again reuses the key; '
      'nothing is queued', (tester, api) async {
    final host = await pumpRefund(tester, api);
    await tapKey(tester, 'refund-inc-sln_b');
    await tapKey(tester, 'refund-reason-mind');
    await tapKey(tester, 'refund-method-cash');
    var calls = 0;
    api.onCall('POST /vendor/sales/sal_1/refunds', (_) {
      calls++;
      if (calls == 1) throw Exception('connection lost');
      return {
        'refund': refundJson(amount: 10000),
        'sale': refundSale(matRefunded: 1),
      };
    });
    await tapKey(tester, 'refund-review');
    await tapKey(tester, 'refund-confirm');
    expect(find.byKey(const Key('refund-confirm')), findsOneWidget);
    expect(find.text(host.tr('vendor.refunds.err.unconfirmed')), findsOneWidget);
    await tapKey(tester, 'refund-confirm');
    final sent = api.where('POST', '/vendor/sales/sal_1/refunds');
    expect(sent, hasLength(2));
    expect(
      (sent[0].body as Map)['clientRef'],
      (sent[1].body as Map)['clientRef'],
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where((k) => k.toLowerCase().contains('refund')),
      isEmpty,
    );
  });

  apiTest('Swahili: the screen reads in Swahili', (tester, api) async {
    await pumpRefund(tester, api, lang: 'sw');
    expect(find.text('Marejesho ya R-000123'), findsOneWidget);
    expect(find.text('Mteja anarudisha nini?'), findsOneWidget);
    expect(find.text('Rejesha zote zilizobaki'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
