// Vendor tools · S7 UAT fixes on RC (mobile eca479c): M-1/L-7 only the
// restock row toggles restock, L-1 pills expose selected state, L-4 focus
// to the first affected line after refund_exceeds_sold, L-5 "Try again"
// and an honest message after a network failure, L-6 a lone refund row is
// its own button, L-8 the sticky Review is ≥ 44dp, L-3 a pay-later sale
// cleared by a refund never reads "Paid off".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/sales/refunds/refund_page.dart';
import 'package:fitflexmobile/screens/vendor/sales/sale_detail_page.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';

import '../support/recording_api.dart';
import 'refunds_support.dart';
import 'stock_support.dart' show seedVendorHome;

Future<PageHost> pumpRefund(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic>? sale,
  String lang = 'en',
}) async {
  api.on('GET /vendor/tools/options', refundsOn);
  api.on('GET /vendor/sales/sal_1', {'sale': sale ?? refundSale()});
  return pumpPage(
    tester,
    api,
    const RefundPage(saleId: 'sal_1'),
    user: ownerUser,
    lang: lang,
    size: const Size(400, 2000),
    extraRoutes: refundRoutes,
  );
}

Future<void> tapKey(WidgetTester tester, String key) =>
    tapVisible(tester, find.byKey(Key(key)));

bool restockOn(WidgetTester tester, String line) => tester
    .widget<SwitchListTile>(find.byKey(Key('refund-restock-$line')))
    .value;

void main() {
  setUpAll(loadAppFonts);

  apiTest('M-1/L-7: name, counts and amount never toggle restock', (
    tester,
    api,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpRefund(tester, api);
    await tapKey(tester, 'refund-inc-sln_a');
    expect(restockOn(tester, 'sln_a'), isTrue);
    final card = find.byKey(const Key('refund-line-sln_a'));
    for (final f in [
      find.descendant(of: card, matching: find.text('Whey')),
      find.descendant(of: card, matching: find.text('Sold 3 · refunded 0')),
      find.byKey(const Key('refund-amount-sln_a')),
    ]) {
      await tester.tap(f);
      await tester.pumpAndSettle();
      expect(restockOn(tester, 'sln_a'), isTrue, reason: 'tapped $f');
    }
    // The switch has its own node, with only its own label.
    final node = tester.getSemantics(
      find.bySemanticsLabel('Put Whey back in stock'),
    );
    expect(node.label, 'Put Whey back in stock');
    expect(
      node,
      isSemantics(
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );
    // The card is not announced as the switch.
    expect(
      find.bySemanticsLabel(RegExp(r'Whey.*Sold 3.*back in stock')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('refund-restock-sln_a')));
    await tester.pumpAndSettle();
    expect(restockOn(tester, 'sln_a'), isFalse);
    semantics.dispose();
  });

  apiTest('L-1: reason and method pills expose selected state', (
    tester,
    api,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpRefund(tester, api);
    await tapKey(tester, 'refund-inc-sln_b');
    await tapKey(tester, 'refund-reason-faulty');
    expect(
      tester.getSemantics(find.bySemanticsLabel('Faulty or damaged')),
      isSemantics(
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Wrong item')),
      isSemantics(
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    // The sale was paid by M-Pesa: that method is the selected one.
    expect(
      tester.getSemantics(find.bySemanticsLabel('M-Pesa')),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Cash')),
      isSemantics(isButton: true, isSelected: false),
    );
    semantics.dispose();
  });

  apiTest(
    'L-4: after refund_exceeds_sold focus is on the first affected line',
    (tester, api) async {
      await pumpRefund(
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
            'saleLineId': 'sln_b',
            'soldQty': 1,
            'refundedQty': 1,
            'refundableQty': 0,
          },
        ],
      });
      api.on('GET /vendor/sales/sal_1', {'sale': refundSale(matRefunded: 1)});
      await tapKey(tester, 'refund-review');
      await tapKey(tester, 'refund-confirm');
      await tester.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus;
      expect(focused?.debugLabel, 'refund-sln_b');
      expect(focused?.debugLabel, isNot(contains('close')));
    },
  );

  for (final (lang, retry, message) in const [
    (
      'en',
      'Try again',
      "We couldn't confirm the refund. Try again — it won't be made twice.",
    ),
    (
      'sw',
      'Jaribu tena',
      'Hatukuweza kuthibitisha marejesho. Jaribu tena — hayatafanywa mara mbili.',
    ),
  ]) {
    apiTest('L-5 ($lang): network failure reads Try again, never "nothing '
        'changed"', (tester, api) async {
      final semantics = tester.ensureSemantics();
      await pumpRefund(tester, api, lang: lang);
      await tapKey(tester, 'refund-inc-sln_b');
      await tapKey(tester, 'refund-reason-mind');
      await tapKey(tester, 'refund-method-cash');
      api.onCall(
        'POST /vendor/sales/sal_1/refunds',
        (_) => throw Exception('connection lost'),
      );
      await tapKey(tester, 'refund-review');
      await tapKey(tester, 'refund-confirm');
      expect(
        find.descendant(
          of: find.byKey(const Key('refund-confirm')),
          matching: find.text(retry),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(retry), findsWidgets);
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('Nothing was changed'), findsNothing);
      expect(find.textContaining('Hakuna kilichobadilishwa'), findsNothing);
      semantics.dispose();
    });
  }

  apiTest('L-8: the sticky Review button is at least 44dp tall', (
    tester,
    api,
  ) async {
    await pumpRefund(tester, api);
    expect(
      tester.getSize(find.byKey(const Key('refund-review'))).height,
      greaterThanOrEqualTo(44),
    );
  });

  apiTest('L-6: a single refund row is its own button, not the heading', (
    tester,
    api,
  ) async {
    final semantics = tester.ensureSemantics();
    api.on('GET /vendor/tools/options', refundsOn);
    api.on('GET /vendor/profile', {'businessName': 'Dar Gear'});
    api.on('GET /vendor/sales/sal_1', {
      'sale': refundSale(
        wheyRefunded: 1,
        wheyRefundedTzs: 3333,
        refunds: const [
          {
            'id': 'vrf_a',
            'number': 'CN-000001',
            'status': 'active',
            'refundedAt': '2026-11-03T09:00:00.000Z',
            'amountTzs': 3333,
          },
        ],
      ),
    });
    await pumpPage(
      tester,
      api,
      const SaleDetailPage(saleId: 'sal_1'),
      user: ownerUser,
      size: const Size(400, 2400),
      extraRoutes: refundRoutes,
    );
    final row = find.bySemanticsLabel(RegExp(r'^Credit note CN-000001, '));
    expect(row, findsOneWidget);
    final node = tester.getSemantics(row);
    expect(node, isSemantics(isButton: true, hasTapAction: true));
    expect(node.label, isNot(contains('Refunds')));
    // The heading is read on its own.
    expect(find.bySemanticsLabel(RegExp(r'^Refunds.*CN-000001')), findsNothing);
    semantics.dispose();
  });

  group('L-3: a pay-later sale cleared by a refund is not "Paid off"', () {
    Map<String, dynamic> row(String id, String state, {int reduced = 0}) => {
      'id': id,
      'number': 'R-$id',
      'soldAt': '2026-11-03T08:00:00.000Z',
      'recordedAt': '2026-11-03T08:00:00.000Z',
      'status': 'completed',
      'kind': 'credit',
      'balanceTzs': 0,
      'dueDate': '2026-11-30',
      'totalTzs': 20000,
      'itemCount': 1,
      'methods': const [],
      'createdBy': {'id': 'v1', 'name': 'Owner'},
      'refundedTzs': state == 'none' ? 0 : 5000,
      'refundState': state,
      if (reduced > 0) 'balanceReducedTzs': reduced,
    };

    apiTest('Refunded / Part refunded / settled / Paid off', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [], tools: refundsOn);
      api.on('GET /vendor/sales', {
        'sales': [
          row('full', 'full'),
          row('part', 'partial'),
          row('settled', 'partial', reduced: 5000),
          row('paid', 'none'),
        ],
        'nextCursor': null,
        'summary': {'count': 4, 'totalTzs': 80000, 'voidedCount': 0},
      });
      final host = await pumpPage(
        tester,
        api,
        const VendorHomePage(open: 'sales'),
        user: ownerUser,
        size: const Size(400, 2400),
      );
      final paidOff = host.tr('vendor.sales.paidOffBadge');
      Finder inRow(String id, String text) => find.descendant(
        of: find.byKey(Key('sales-row-$id')),
        matching: find.text(text),
      );
      expect(inRow('full', paidOff), findsNothing);
      expect(
        inRow('full', host.tr('vendor.refunds.badgeFull')),
        findsOneWidget,
      );
      expect(inRow('part', paidOff), findsNothing);
      expect(
        inRow('part', host.tr('vendor.refunds.badgePartial')),
        findsOneWidget,
      );
      expect(inRow('settled', paidOff), findsNothing);
      expect(
        inRow('settled', host.tr('vendor.doc.statusSettledByCreditNote')),
        findsOneWidget,
      );
      expect(inRow('paid', paidOff), findsOneWidget);
    });
  });
}
