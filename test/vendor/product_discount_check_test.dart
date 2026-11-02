// The product form refuses a discount price at or above the price, with the
// stock ledger on and off. The server ignores such a discount, so without
// this the vendor would see a discount buyers never get.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';

Finder _k(String key) => find.byKey(Key(key));

void main() {
  setUpAll(loadAppFonts);

  const put = '/vendor/products/p1';
  final product = stockProduct('p1', 'Whey');

  Future<PageHost> openEdit(
    WidgetTester tester,
    RecordingApi api, {
    Map<String, dynamic>? tools,
    Map<String, dynamic>? item,
    String lang = 'en',
  }) async {
    seedVendorHome(api, products: [item ?? product], tools: tools);
    api.on('PUT $put', {'ok': true});
    final host = await pumpVendorHome(tester, api, lang: lang);
    await productMenu(tester, 'p1', host.tr('vendor.edit'));
    return host;
  }

  for (final ledger in [false, true]) {
    final tools = ledger ? ledgerOn : null;
    final mode = ledger ? 'ledger on' : 'ledger off';

    apiTest('$mode: discount equal to the price is refused', (
      tester,
      api,
    ) async {
      final host = await openEdit(tester, api, tools: tools);
      await typeInto(tester, _k('vendor-product-discount-price'), '85000');
      await tapVisible(tester, _k('vendor-product-save'));
      expect(api.sent('PUT', put), isFalse);
      expect(find.text(host.tr('vendor.form.discountBelowPrice')), findsOne);
      expect(_k('vendor-product-save-error'), findsOneWidget);
    });

    apiTest('$mode: fixing the discount clears the error and saves', (
      tester,
      api,
    ) async {
      final host = await openEdit(tester, api, tools: tools);
      await typeInto(tester, _k('vendor-product-discount-price'), '90000');
      await tapVisible(tester, _k('vendor-product-save'));
      await typeInto(tester, _k('vendor-product-discount-price'), '60000');
      expect(
        find.text(host.tr('vendor.form.discountBelowPrice')),
        findsNothing,
      );
      await tapVisible(tester, _k('vendor-product-save'));
      expect((api.only('PUT', put).body as Map)['discountPriceTzs'], 60000);
    });

    apiTest('$mode: lowering the price under the discount is refused', (
      tester,
      api,
    ) async {
      final host = await openEdit(
        tester,
        api,
        tools: tools,
        item: {...product, 'discountPriceTzs': 60000},
      );
      await typeInto(tester, _k('vendor-product-price'), '50000');
      await tapVisible(tester, _k('vendor-product-save'));
      expect(api.sent('PUT', put), isFalse);
      expect(find.text(host.tr('vendor.form.discountBelowPrice')), findsOne);
    });

    for (final none in ['', '0']) {
      apiTest('$mode: "$none" means no discount and saves', (
        tester,
        api,
      ) async {
        await openEdit(
          tester,
          api,
          tools: tools,
          item: {...product, 'discountPriceTzs': 60000},
        );
        await typeInto(tester, _k('vendor-product-discount-price'), none);
        await tapVisible(tester, _k('vendor-product-save'));
        expect(api.sent('PUT', put), isTrue);
      });
    }
  }

  apiTest('locked price: a bad stored discount does not block saving', (
    tester,
    api,
  ) async {
    await openEdit(
      tester,
      api,
      tools: const {
        'merch': {'flashSales': true},
      },
      item: {
        ...product,
        'discountPriceTzs': 90000,
        'priceLock': {'saleId': 'fls_1'},
      },
    );
    await tapVisible(tester, _k('vendor-product-save'));
    expect(api.sent('PUT', put), isTrue);
  });

  apiTest('the message is in Swahili', (tester, api) async {
    await openEdit(tester, api, lang: 'sw');
    await typeInto(tester, _k('vendor-product-discount-price'), '85000');
    await tapVisible(tester, _k('vendor-product-save'));
    expect(
      find.text(
        'Bei ya punguzo lazima iwe chini ya bei. Ibadilishe au iache wazi.',
      ),
      findsOneWidget,
    );
  });
}
