// Vendor tools · S9 UAT H-1: typed quantities and unit costs survive their
// line scrolling out of view while the field has focus (375×812), and
// tapping Paid part right after typing the last line.
import 'package:fitflexmobile/screens/vendor/purchases/receive_stock_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_api.dart';
import 'purchases_support.dart';

final _now = DateTime.utc(2026, 11, 3, 9);

List<Map<String, dynamic>> _threeProducts() => [
  for (final (id, name) in [
    ('p1', 'Whey 1kg'),
    ('p4', 'Bottle'),
    ('p5', 'Rope'),
  ])
    {
      'id': id,
      'name': name,
      'priceTzs': 15000,
      'stock': 4,
      'status': 'active',
      'approvalStatus': 'approved',
      'variants': [],
    },
];

Future<PageHost> _pump(WidgetTester tester, RecordingApi api) {
  seedReceive(api, tools: purchasesOnNoCost);
  api.on('GET /vendor/products', _threeProducts());
  return pumpPage(
    tester,
    api,
    ReceiveStockPage(now: () => _now),
    user: ownerUser,
    size: const Size(375, 812),
    extraRoutes: purchaseRoutes,
  );
}

Future<void> _add(WidgetTester tester, String id) async {
  await tapVisible(tester, find.byKey(const Key('purchase-add-item')));
  await tester.tap(find.byKey(Key('purchase-pick-$id')));
  await tester.pumpAndSettle();
}

Finder _cost(String id) => find.byKey(Key('purchase-line-cost-$id-'));

String _text(WidgetTester tester, Finder f) => tester
    .widget<EditableText>(
      find.descendant(of: f, matching: find.byType(EditableText)),
    )
    .controller
    .text;

Finder get _scroll => find.byType(Scrollable).first;

/// Scrolls the form until [f] is built and on screen.
Future<void> _reach(WidgetTester tester, Finder f) async {
  await tester.drag(_scroll, const Offset(0, 4000));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(f, 200, scrollable: _scroll);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  apiTest('H-1: a focused cost survives scrolling away and back', (
    tester,
    api,
  ) async {
    await _pump(tester, api);
    for (final id in ['p1', 'p4', 'p5']) {
      await _add(tester, id);
    }
    await _reach(tester, _cost('p1'));
    await tester.tap(_cost('p1'));
    await tester.enterText(_cost('p1'), '9500');
    await tester.pump();
    final field = tester.state(
      find.descendant(of: _cost('p1'), matching: find.byType(EditableText)),
    );
    // Still focused: scroll to Payment and back.
    await tester.drag(_scroll, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('purchase-pay-mode')), findsOneWidget);
    // Never detached while away: the same field, still holding the value.
    expect(_cost('p1'), findsOneWidget);
    expect(_text(tester, _cost('p1')), '9500');
    await _reach(tester, _cost('p1'));
    expect(_text(tester, _cost('p1')), '9500');
    expect(
      identical(
        tester.state(
          find.descendant(of: _cost('p1'), matching: find.byType(EditableText)),
        ),
        field,
      ),
      isTrue,
    );
    expect(find.byKey(const Key('purchase-line-total-p1-')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('purchase-line-total-p1-')))
          .data,
      'TSh 9,500',
    );
  });

  apiTest('H-1: typing the last line then tapping Paid part keeps it', (
    tester,
    api,
  ) async {
    final host = await _pump(tester, api);
    for (final id in ['p1', 'p4', 'p5']) {
      await _add(tester, id);
    }
    for (final (id, v) in [('p1', '1000'), ('p4', '2000')]) {
      await _reach(tester, _cost(id));
      await tester.enterText(_cost(id), v);
      await tester.pump();
    }
    await _reach(tester, _cost('p5'));
    await tester.tap(_cost('p5'));
    await tester.enterText(_cost('p5'), '3000');
    await tester.pump();
    await tapVisible(tester, find.text(host.tr('vendor.purchases.paidPart')));
    for (final (id, v) in [('p1', '1000'), ('p4', '2000'), ('p5', '3000')]) {
      await _reach(tester, _cost(id));
      expect(_text(tester, _cost(id)), v, reason: id);
    }
    expect(find.text('Review TSh 6,000'), findsOneWidget);
  });
}
