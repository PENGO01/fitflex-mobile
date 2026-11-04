// Vendor tools · S9: the purchase detail (spec §4.5) — heading and badges,
// cost tags by canSeeCost, instalment states in words, the payment sheet
// (coverage preview, overpayment with the fresh balance), void purchase
// (insufficient_stock list, has_others_payments), void payment, M2
// visibility, the voided state and the text share content.
import 'package:fitflexmobile/screens/vendor/purchases/purchase_detail_page.dart';
import 'package:fitflexmobile/screens/vendor/sales/receipt_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_api.dart';
import 'purchases_support.dart';

const _id = 'vpo_0000000000000012';
final _now = DateTime.utc(2026, 11, 3, 12);

Future<PageHost> pumpDetail(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> tools = purchasesOnTools,
  Map<String, dynamic>? purchase,
  Map<String, dynamic> user = ownerUser,
  String lang = 'en',
}) async {
  api.on('GET /vendor/tools/options', tools);
  api.on('GET /vendor/profile', {'businessName': 'Dar Gear'});
  api.on('GET /vendor/purchases/$_id', {
    'purchase': purchase ?? purchaseJson(),
  });
  return pumpPage(
    tester,
    api,
    PurchaseDetailPage(purchaseId: _id, now: () => _now),
    user: user,
    lang: lang,
    size: const Size(420, 2200),
    extraRoutes: purchaseRoutes,
  );
}

void main() {
  setUpAll(loadAppFonts);

  apiTest('the GRN: heading, badges, items, money, instalments in words', (
    tester,
    api,
  ) async {
    final host = await pumpDetail(
      tester,
      api,
      purchase: purchaseJson(
        overdue: 20000,
        instalments: [
          inst(1, '2026-11-03', 50000, 50000, 'paid'),
          inst(2, '2026-10-20', 50000, 30000, 'part_paid'),
          inst(3, '2026-12-01', 50000, 0, 'due'),
          inst(4, '2026-10-01', 50000, 0, 'overdue', daysOverdue: 33),
        ],
      ),
    );
    expect(find.text('Stock received GRN-000012'), findsOneWidget);
    expect(
      find.text(host.tr('vendor.purchases.state.received')),
      findsOneWidget,
    );
    expect(find.text(host.tr('vendor.purchases.state.overdue')), findsWidgets);
    expect(find.text('20 × Whey 1kg'), findsOneWidget);
    expect(find.text('1 × Tee (M)'), findsOneWidget);
    expect(find.text('Cost price updated (was TSh 9,000)'), findsOneWidget);
    expect(find.text('Overdue TSh 20,000'), findsOneWidget);
    expect(find.text('Paid'), findsWidgets);
    expect(find.text('TSh 30,000 of TSh 50,000 paid'), findsOneWidget);
    expect(find.text('Due in 28 days'), findsOneWidget);
    expect(find.text('Overdue 33 days'), findsOneWidget);
    expect(find.text(host.tr('vendor.purchases.atDelivery')), findsOneWidget);
    expect(find.text(host.tr('vendor.purchases.moneyNotice')), findsOneWidget);
    expect(find.byKey(const Key('purchase-void')), findsOneWidget);
  });

  apiTest('without canSeeCost: "Cost price updated", no "was" figure', (
    tester,
    api,
  ) async {
    await pumpDetail(
      tester,
      api,
      tools: purchasesOnNoCost,
      user: staffUser(['purchases']),
      purchase: purchaseJson(previousCost: null),
    );
    expect(find.text('Cost price updated'), findsOneWidget);
    expect(find.textContaining('was TSh'), findsNothing);
  });

  apiTest('received on an earlier day shows the recorded time too', (
    tester,
    api,
  ) async {
    await pumpDetail(
      tester,
      api,
      purchase: purchaseJson(receivedOn: '2026-11-01'),
    );
    expect(
      find.text('Received 1 Nov 2026 · recorded 3 Nov 2026, 10:05'),
      findsOneWidget,
    );
  });

  apiTest('AC-17: record 70,000 — preview, then the purchase updates', (
    tester,
    api,
  ) async {
    final host = await pumpDetail(tester, api);
    api.on('POST /vendor/purchases/$_id/payments', {
      'purchase': purchaseJson(
        paid: 120000,
        instalments: [
          inst(1, '2026-11-03', 50000, 50000, 'paid'),
          inst(2, '2026-12-03', 50000, 50000, 'paid'),
          inst(3, '2027-01-03', 50000, 20000, 'part_paid'),
          inst(4, '2027-02-03', 50000, 0, 'due'),
        ],
      ),
      'payment': paymentJson(id: 'vpp_2', amount: 70000, atReceipt: false),
      'covered': [],
    });
    await tapVisible(tester, find.byKey(const Key('purchase-record-payment')));
    expect(find.text('Record payment to Juma Supplies'), findsOneWidget);
    expect(find.text(host.tr('vendor.purchases.moneyNotice')), findsWidgets);
    await typeInto(tester, find.byKey(const Key('ppay-amount')), '70000');
    expect(
      find.text(
        'Covers instalment 2 (3 Dec 2026) and TSh 20,000 of instalment 3',
      ),
      findsOneWidget,
    );
    await typeInto(tester, find.byKey(const Key('ppay-amount')), '160000');
    expect(isEnabled(tester, find.byKey(const Key('ppay-save'))), isFalse);
    await typeInto(tester, find.byKey(const Key('ppay-amount')), '70000');
    await tapVisible(tester, find.byKey(const Key('ppay-method-mpesa')));
    expect(isEnabled(tester, find.byKey(const Key('ppay-save'))), isFalse);
    await typeInto(tester, find.byKey(const Key('ppay-reference')), 'QX9');
    await tapVisible(tester, find.byKey(const Key('ppay-save')));
    final body =
        api.only('POST', '/vendor/purchases/$_id/payments').body as Map;
    expect(body['amountTzs'], 70000);
    expect(body['method'], 'mpesa');
    expect(body['reference'], 'QX9');
    expect(body.containsKey('paidOn'), isFalse);
    expect((body['clientRef'] as String).endsWith(':paid'), isFalse);
    expect(host.snack('Payment saved: TSh 70,000'), findsOneWidget);
    expect(find.text('TSh 20,000 of TSh 50,000 paid'), findsOneWidget);
  });

  apiTest('409 overpayment: the amount field shows the fresh balance', (
    tester,
    api,
  ) async {
    await pumpDetail(tester, api);
    api.fail('POST /vendor/purchases/$_id/payments', 409, {
      'error': 'overpayment',
      'balanceTzs': 80000,
    });
    await tapVisible(tester, find.byKey(const Key('purchase-record-payment')));
    await typeInto(tester, find.byKey(const Key('ppay-amount')), '100000');
    await tapVisible(tester, find.byKey(const Key('ppay-save')));
    expect(
      find.text('That is more than is owed (TSh 80,000).'),
      findsOneWidget,
    );
  });

  apiTest(
    'AC-23: void refused for stock lists every short line + Count stock',
    (tester, api) async {
      final host = await pumpDetail(tester, api);
      api.fail('POST /vendor/purchases/$_id/void', 409, {
        'error': 'insufficient_stock',
        'lines': [
          {
            'productId': 'p1',
            'variant': null,
            'name': 'Whey 1kg',
            'receivedQty': 20,
            'available': 4,
          },
        ],
      });
      await tapVisible(tester, find.byKey(const Key('purchase-void')));
      expect(find.text('Void GRN-000012?'), findsOneWidget);
      expect(find.byKey(const Key('purchase-void-payments')), findsOneWidget);
      expect(find.text(host.tr('vendor.purchases.voidCost')), findsOneWidget);
      expect(
        isEnabled(tester, find.byKey(const Key('purchase-void-confirm'))),
        isFalse,
      );
      await typeInto(
        tester,
        find.byKey(const Key('purchase-void-reason')),
        'Wrong delivery',
      );
      await tester.tap(find.byKey(const Key('purchase-void-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('purchase-void-dialog')), findsOneWidget);
      expect(
        find.textContaining('Whey 1kg: received 20, in stock 4'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('purchase-void-count-p1')), findsOneWidget);
    },
  );

  apiTest('#327: has_others_payments says to ask the owner or an admin', (
    tester,
    api,
  ) async {
    await pumpDetail(tester, api, user: staffUser(['purchases'], id: 'v1'));
    api.fail('POST /vendor/purchases/$_id/void', 403, {
      'error': 'void_not_allowed',
      'reason': 'has_others_payments',
    });
    await tapVisible(tester, find.byKey(const Key('purchase-void')));
    await typeInto(
      tester,
      find.byKey(const Key('purchase-void-reason')),
      'Mistake',
    );
    await tester.tap(find.byKey(const Key('purchase-void-confirm')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Ask the owner or an admin to void this; it has payments recorded by someone else.',
      ),
      findsOneWidget,
    );
  });

  apiTest(
    '#327: own purchase today but a payment by someone else — Void hidden',
    (tester, api) async {
      final host = await pumpDetail(
        tester,
        api,
        user: staffUser(['purchases']),
        purchase: purchaseJson(
          createdById: 's1',
          recordedAt: '2026-11-03T07:00:00.000Z',
          payments: [paymentJson(recordedById: 'v1')],
        ),
      );
      expect(find.byKey(const Key('purchase-void')), findsNothing);
      expect(
        find.text(host.tr('vendor.purchases.err.hasOthersPayments')),
        findsOneWidget,
      );
    },
  );

  apiTest('admin staff: others\' payments do not hide Void', (
    tester,
    api,
  ) async {
    await pumpDetail(
      tester,
      api,
      user: staffUser(['purchases'], role: 'admin'),
      purchase: purchaseJson(payments: [paymentJson(recordedById: 'v1')]),
    );
    expect(find.byKey(const Key('purchase-void')), findsOneWidget);
  });

  apiTest('AC-22: voided — banner with reason, no actions but Share', (
    tester,
    api,
  ) async {
    final host = await pumpDetail(tester, api);
    api.on('POST /vendor/purchases/$_id/void', {
      'purchase': purchaseJson(
        status: 'voided',
        costRestored: true,
        payments: [paymentJson(status: 'voided')],
      ),
      'costRestored': [
        {'productId': 'p1', 'variant': null, 'name': 'Whey 1kg'},
      ],
      'costKept': [],
      'paymentsVoided': 1,
    });
    await tapVisible(tester, find.byKey(const Key('purchase-void')));
    await typeInto(
      tester,
      find.byKey(const Key('purchase-void-reason')),
      'Wrong delivery',
    );
    await tester.tap(find.byKey(const Key('purchase-void-confirm')));
    await tester.pumpAndSettle();
    expect(host.snack('GRN-000012 voided'), findsOneWidget);
    expect(find.byKey(const Key('purchase-voided')), findsOneWidget);
    expect(find.textContaining('Wrong delivery'), findsWidgets);
    expect(find.text(host.tr('vendor.purchases.costRestored')), findsOneWidget);
    expect(find.byKey(const Key('purchase-void')), findsNothing);
    expect(find.byKey(const Key('purchase-record-payment')), findsNothing);
    expect(find.byKey(const Key('purchase-share')), findsOneWidget);
    expect(find.text(host.tr('vendor.purchases.state.voided')), findsWidgets);
  });

  apiTest('M2: other staff, not their record — no Void, "ask the owner"', (
    tester,
    api,
  ) async {
    final host = await pumpDetail(tester, api, user: staffUser(['purchases']));
    expect(find.byKey(const Key('purchase-void')), findsNothing);
    expect(find.byKey(const Key('purchase-payment-more-vpp_1')), findsNothing);
    expect(find.text(host.tr('vendor.purchases.askOwner')), findsOneWidget);
  });

  apiTest('M2: staff void their own payment today; supplier_required words', (
    tester,
    api,
  ) async {
    final host = await pumpDetail(
      tester,
      api,
      user: staffUser(['purchases']),
      purchase: purchaseJson(
        createdById: 's1',
        recordedAt: '2026-11-03T07:00:00.000Z',
        payments: [paymentJson(recordedById: 's1')],
      ),
    );
    api.fail('POST /vendor/purchases/$_id/payments/vpp_1/void', 409, {
      'error': 'supplier_required',
    });
    expect(find.byKey(const Key('purchase-void')), findsOneWidget);
    await tester.tap(find.byKey(const Key('purchase-payment-more-vpp_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('purchase-payment-void-vpp_1')));
    await tester.pumpAndSettle();
    expect(
      find.text('Void payment of TSh 50,000 on 3 Nov 2026?'),
      findsOneWidget,
    );
    await typeInto(
      tester,
      find.byKey(const Key('purchase-payment-void-reason')),
      'Twice',
    );
    await tester.tap(find.byKey(const Key('purchase-payment-void-confirm')));
    await tester.pumpAndSettle();
    expect(
      find.text(host.tr('vendor.purchases.err.noSupplierDebt')),
      findsOneWidget,
    );
  });

  apiTest('Change instalments: paid rows kept; must add up to the balance', (
    tester,
    api,
  ) async {
    await pumpDetail(tester, api);
    api.on('PUT /vendor/purchases/$_id/instalments', {
      'purchase': purchaseJson(),
    });
    await tapVisible(tester, find.byKey(const Key('purchase-change-plan')));
    expect(find.byKey(const Key('plan-kept-1')), findsOneWidget);
    expect(find.text('Must add up to TSh 150,000'), findsOneWidget);
    await typeInto(tester, find.byKey(const Key('plan-amount-0')), '40000');
    expect(isEnabled(tester, find.byKey(const Key('plan-save'))), isFalse);
    await typeInto(tester, find.byKey(const Key('plan-amount-0')), '50000');
    await tapVisible(tester, find.byKey(const Key('plan-save')));
    final body =
        api.only('PUT', '/vendor/purchases/$_id/instalments').body as Map;
    expect(
      (body['schedule'] as List).fold<int>(
        0,
        (s, r) => s + (r['amountTzs'] as int),
      ),
      150000,
    );
  });

  apiTest('Share as text: no previous cost, note or recorder', (
    tester,
    api,
  ) async {
    final shared = <String>[];
    final keep = shareReceipt;
    shareReceipt = (text, subject) async => shared.add(text);
    addTearDown(() => shareReceipt = keep);
    await pumpDetail(tester, api);
    await tapVisible(tester, find.byKey(const Key('purchase-share')));
    expect(shared.single, contains('Dar Gear'));
    expect(shared.single, contains('GRN-000012'));
    expect(shared.single, isNot(contains('9,000')));
    expect(shared.single, isNot(contains('Back door')));
    expect(shared.single, isNot(contains('Asha')));
  });

  apiTest('not found / tool off', (tester, api) async {
    api.on('GET /vendor/tools/options', purchasesOnTools);
    api.fail('GET /vendor/purchases/$_id', 404, {
      'error': 'purchase_not_found',
    });
    final host = await pumpPage(
      tester,
      api,
      PurchaseDetailPage(purchaseId: _id, now: () => _now),
      user: ownerUser,
      extraRoutes: purchaseRoutes,
    );
    expect(find.text(host.tr('vendor.purchases.notFound')), findsOneWidget);
  });

  apiTest('Swahili: badges and money in words', (tester, api) async {
    await pumpDetail(tester, api, lang: 'sw');
    expect(find.text('Hati ya kupokea Stock GRN-000012'), findsOneWidget);
    expect(find.text('Imepokelewa'), findsOneWidget);
    expect(find.text('Kiasi kilichobaki'), findsOneWidget);
  });
}
