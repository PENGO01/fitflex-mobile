// Vendor tools · sale extras (docs/design/vendor-sale-extras-1110.md):
// #1 the optional reference on every sale payment method (flag
// referenceOptional), #2 the optional Customer section (flag
// saleCustomerDetails): find / match / create / duplicate phone / offline,
// and the privacy rule that a typed name or phone never reaches the sale
// body, the draft or the offline queue.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/screens/vendor/sales/pos_page.dart';
import 'package:fitflexmobile/screens/vendor/sales/sale_customer_section.dart';
import 'package:fitflexmobile/screens/vendor/sales/sale_models.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_options.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/network/browser_online.dart';

import '../support/recording_api.dart';
import 'customers_support.dart';
import 'walkin_support.dart';

const wide = Size(1200, 1400);
const queueKey = 'vendor_sale_queue.v1.v1';

const extrasOn = {
  ...customersOn,
  'referenceOptional': true,
  'saleCustomerDetails': true,
};

Future<PageHost> pumpPos(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> user = ownerUser,
  String lang = 'en',
}) => pumpPage(
  tester,
  api,
  const PosPage(),
  user: user,
  lang: lang,
  size: wide,
  extraRoutes: salesRoutes,
);

void seed(RecordingApi api, {Map<String, dynamic> tools = extrasOn}) {
  seedPos(
    api,
    tools: tools,
    products: [posProduct('p1', 'Whey', price: 95000, stock: 5)],
  );
  seedCustomers(api);
  // The mobile lookup: Asha has 0712 345 678; two customers share
  // 0755 000 111; a name that merely contains digits never matches.
  api.onCall('GET /vendor/customers', (r) {
    final q = Uri.splitQueryString(r.query)['q'] ?? '';
    final rows = switch (q) {
      '712345678' => [
        customerRow('cus_asha', 'Asha', phone: '+255712345678', owed: 0),
        customerRow('cus_x', 'Shop 712345678', phone: '+255700000000'),
      ],
      '755000111' => [
        customerRow('cus_a', 'Baraka', phone: '+255755000111'),
        customerRow('cus_b', 'Baraka M', phone: '+255755000111'),
      ],
      '' => [customerRow('cus_1', 'Juma Mussa')],
      _ => <Map<String, dynamic>>[],
    };
    return {'customers': rows, 'nextCursor': null, 'asOf': '2026-11-10'};
  });
  api.onCall('POST /vendor/sales', (_) => {'sale': serverSale(id: 'sal_9')});
}

Future<void> openPayment(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('pos-product-p1')));
  await tester.pumpAndSettle();
  await tapVisible(tester, find.byKey(const Key('pos-cart-charge')));
}

Future<void> expandCustomer(WidgetTester tester) =>
    tapVisible(tester, find.byKey(const Key('pos-cust-toggle')));

Future<void> typeMobile(WidgetTester tester, String v) async {
  await typeInto(tester, find.byKey(const Key('pos-cust-mobile')), v);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

const draftKey = 'vendor_pos_draft.v1.v1';

Map<String, dynamic> draftJson({String? customerType, String? clientRef}) => {
  'lines': [
    {
      'productId': 'p1',
      'name': 'Whey',
      'listPriceTzs': 95000,
      'qty': 1,
      'discountTzs': 0,
    },
  ],
  'saleDiscountTzs': 0,
  'note': '',
  'clientRef': ?clientRef,
  'customerType': ?customerType,
};

Map saleBody(RecordingApi api) => api.only('POST', '/vendor/sales').body as Map;

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => BrowserOnline.debugSet(true));

  group('models', () {
    test('options: both keys exactly true and only with walk-in sales', () {
      final off = VendorTools.fromOptions({'walkInSales': true});
      expect(off.saleReferenceOptionalOn, isFalse);
      expect(off.saleCustomerDetailsOn, isFalse);
      final on = VendorTools.fromOptions({
        'walkInSales': true,
        'referenceOptional': true,
        'saleCustomerDetails': true,
      });
      expect(on.saleReferenceOptionalOn, isTrue);
      expect(on.saleCustomerDetailsOn, isTrue);
      final noSales = VendorTools.fromOptions({
        'walkInSales': false,
        'referenceOptional': true,
        'saleCustomerDetails': true,
      });
      expect(noSales.saleReferenceOptionalOn, isFalse);
      expect(noSales.saleCustomerDetailsOn, isFalse);
      expect(
        VendorTools.fromOptions({
          'walkInSales': true,
          'referenceOptional': 'true',
        }).saleReferenceOptionalOn,
        isFalse,
      );
    });

    test('flag off: today\'s rule; the shared constant is untouched', () {
      final mpesa = PaymentRow(method: 'mpesa', amountTzs: 10);
      expect(mpesa.needsReference, isTrue);
      expect(mpesa.referenceMissing, isTrue);
      final cash = PaymentRow(method: 'cash', amountTzs: 10, reference: 'X1');
      expect(cash.toRequest().containsKey('reference'), isFalse);
      expect(referenceRequiredMethods, {
        'mpesa',
        'airtel_money',
        'mixx',
        'halopesa',
        'bank',
      });
    });

    test('flag on: no method needs one; cash reference sent, cleaned', () {
      for (final m in salePaymentMethods) {
        final r = PaymentRow(method: m, amountTzs: 10, referenceOptional: true);
        expect(r.needsReference, isFalse, reason: m);
      }
      final check = PaymentCheck(10, [
        PaymentRow(method: 'bank', amountTzs: 10, referenceOptional: true),
      ]);
      expect(check.missingReferences, isEmpty);
      expect(check.canComplete, isTrue);
      final cash = PaymentRow(
        method: 'cash',
        amountTzs: 10,
        reference: '  TILL-889\n',
        referenceOptional: true,
      );
      expect(cash.toRequest(), {
        'method': 'cash',
        'amountTzs': 10,
        'reference': 'TILL-889',
      });
      expect(cleanReference('A\nB\tC'), 'A B C');
      // The server's \p{Cc}: C1 controls too (NEL U+0085, U+0080, U+009F).
      expect(cleanReference('A\u0085B\u0080C\u009F'), 'A B C');
      expect(referenceControlChars.hasMatch('\u0085'), isTrue);
      expect(referenceControlChars.hasMatch('\u00A0'), isFalse);
      expect(referenceControlChars.hasMatch('Ā-ü'), isFalse);
      expect(
        PaymentRow(
          method: 'cash',
          amountTzs: 1,
          referenceOptional: true,
        ).toRequest().containsKey('reference'),
        isFalse,
      );
    });

    test('customerType: only when set; body unchanged without it', () {
      PosCart make() => PosCart(
        lines: [PosLine(productId: 'p1', name: 'Whey', listPriceTzs: 100)],
      );
      final before = make().requestBody(
        const [],
        makeClientRef: () => 'sale_abcdefgh',
        now: () => DateTime.utc(2026, 11, 10),
      );
      expect(before.containsKey('customerType'), isFalse);
      expect(before.keys.toSet(), {'clientRef', 'lines', 'payments'});
      final cart = make()..setCustomerType('walk_in');
      final body = cart.requestBody(
        const [],
        makeClientRef: () => 'sale_abcdefgh',
      );
      expect(body['customerType'], 'walk_in');
      // Draft keeps the type, never a name.
      cart.setCustomer('cus_1', name: 'Juma Mussa');
      final json = jsonEncode(cart.toJson());
      expect(json, contains('walk_in'));
      expect(json, isNot(contains('Juma')));
      expect(PosCart.fromJson(cart.toJson()).customerType, 'walk_in');
      expect(PosCart.fromJson({'customerType': 'vip'}).customerType, isNull);
      // A new type is a new key at the next Complete.
      cart.clientRef = 'sale_fixed000';
      cart.setCustomerType('online');
      expect(cart.clientRef, isNull);
      cart.clear();
      expect(cart.customerType, isNull);
      // Edit sale from the queue keeps it.
      final back = PosCart.fromQueuedRequest(
        {'lines': [], 'customerType': 'returning'},
        const [],
        replaces: 'sale_q',
      );
      expect(back.customerType, 'returning');
    });

    test('phone matches: full phone equal, or last 3 for the picker shape', () {
      const n = '+255712345678';
      expect(
        phoneMatches([
          {'id': 'a', 'phone': '+255712345678'},
          {'id': 'b', 'phone': '+255700000000', 'name': '712345678'},
          {'id': 'c', 'phone': '+255712345678', 'archived': true},
          {'id': 'd', 'phoneLast3': '678'},
          {'id': 'e', 'phoneLast3': '111'},
        ], n).map((r) => r['id']),
        ['a', 'd'],
      );
    });

    test('customer type keys exist in both languages', () {
      final en = FFLocale();
      final sw = FFLocale()..set(const Locale('sw'));
      for (final t in saleCustomerTypes) {
        expect(customerTypeKey(t), 'vendor.customerType.$t');
        expect(en.t(customerTypeKey(t)!), isNot(customerTypeKey(t)));
      }
      expect(customerTypeKey('vip'), isNull);
      expect(sw.t('vendor.customerType.returning'), 'Anayerudi');
      expect(sw.t('vendor.customerType.walk_in'), 'Wa dukani');
      expect(sw.t('vendor.pos.cust.section'), 'Mteja (si lazima)');
      // Security review: the cash hint steers away from the phone.
      expect(
        en.t('vendor.pos.referenceHintCash'),
        contains('not the customer'),
      );
    });
  });

  group('#1 reference', () {
    apiTest('flag off (AC-1): M-Pesa required, Cash has no field', (
      tester,
      api,
    ) async {
      seed(api, tools: {...customersOn, 'saleCustomerDetails': false});
      final host = await pumpPos(tester, api);
      await openPayment(tester);
      expect(find.byKey(const Key('pos-reference-0')), findsNothing);
      expect(find.byKey(const Key('pos-cust-section')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('pos-method-0-mpesa')));
      expect(find.text(host.tr('vendor.pos.reference')), findsOneWidget);
      expect(isEnabled(tester, find.byKey(const Key('pos-complete'))), isFalse);
      await typeInto(tester, find.byKey(const Key('pos-reference-0')), 'QK1');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      expect(saleBody(api)['payments'], [
        {'method': 'mpesa', 'amountTzs': 95000, 'reference': 'QK1'},
      ]);
    });

    apiTest('flag on (AC-2..4): optional everywhere, cash reference kept', (
      tester,
      api,
    ) async {
      seed(api);
      final host = await pumpPos(tester, api);
      await openPayment(tester);
      // Cash shows the field with the cash hint.
      expect(find.byKey(const Key('pos-reference-0')), findsOneWidget);
      expect(
        find.text(host.tr('vendor.pos.referenceHintCash')),
        findsOneWidget,
      );
      for (final m in salePaymentMethods) {
        await tapVisible(tester, find.byKey(Key('pos-method-0-$m')));
        expect(
          find.text(host.tr('vendor.pos.referenceOptional')),
          findsOneWidget,
          reason: m,
        );
        // No method needs a reference: Complete stays on.
        expect(
          isEnabled(tester, find.byKey(const Key('pos-complete'))),
          isTrue,
          reason: m,
        );
      }
      // M-Pesa with nothing typed completes.
      await tapVisible(tester, find.byKey(const Key('pos-method-0-mpesa')));
      expect(isEnabled(tester, find.byKey(const Key('pos-complete'))), isTrue);
      // AC-4: typed on M-Pesa, switched to Cash, still there.
      await typeInto(
        tester,
        find.byKey(const Key('pos-reference-0')),
        'TILL-889\nX',
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('pos-method-0-cash')));
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      final payments = saleBody(api)['payments'] as List;
      expect(payments.single['method'], 'cash');
      // Newlines never reach the server (single line).
      expect(payments.single['reference'], 'TILL-889X');
    });

    apiTest('flag on: bank with an empty reference is sent without one', (
      tester,
      api,
    ) async {
      seed(api);
      await pumpPos(tester, api);
      await openPayment(tester);
      await tapVisible(tester, find.byKey(const Key('pos-method-0-bank')));
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      expect(saleBody(api)['payments'], [
        {'method': 'bank', 'amountTzs': 95000},
      ]);
    });
  });

  group('#2 customer section', () {
    apiTest('collapsed and untouched (AC-10): no type, no customer', (
      tester,
      api,
    ) async {
      seed(api);
      final host = await pumpPos(tester, api);
      await openPayment(tester);
      expect(find.text(host.tr('vendor.pos.cust.empty')), findsOneWidget);
      expect(find.byKey(const Key('pos-cust-name')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      final body = saleBody(api);
      expect(body.containsKey('customerType'), isFalse);
      expect(body.containsKey('customerId'), isFalse);
      expect(api.sent('POST', '/vendor/customers'), isFalse);
    });

    apiTest('type only (AC-11): Walk-in sent; tap again clears', (
      tester,
      api,
    ) async {
      seed(api);
      await pumpPos(tester, api);
      await openPayment(tester);
      await expandCustomer(tester);
      await tapVisible(tester, find.byKey(const Key('pos-cust-type-online')));
      await tapVisible(tester, find.byKey(const Key('pos-cust-type-online')));
      await tapVisible(tester, find.byKey(const Key('pos-cust-type-walk_in')));
      expect(textContaining('Walk-in'), findsWidgets);
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      expect(saleBody(api)['customerType'], 'walk_in');
      expect(saleBody(api).containsKey('customerId'), isFalse);
    });

    apiTest('mobile match (AC-12): linked, Returning, no new customer', (
      tester,
      api,
    ) async {
      seed(api);
      await pumpPos(tester, api);
      await openPayment(tester);
      await expandCustomer(tester);
      await typeInto(tester, find.byKey(const Key('pos-cust-name')), 'Typed');
      await typeMobile(tester, '0712 345 678');
      expect(find.text('Already a customer: Asha'), findsOneWidget);
      expect(find.byKey(const Key('pos-cust-name')), findsNothing);
      final lookup = api.where('GET', '/vendor/customers').last;
      expect(Uri.splitQueryString(lookup.query)['q'], '712345678');
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      final body = saleBody(api);
      expect(body['customerId'], 'cus_asha');
      expect(body['customerType'], 'returning');
      expect(api.sent('POST', '/vendor/customers'), isFalse);
      expect(jsonEncode(body), isNot(contains('Typed')));
      expect(jsonEncode(body), isNot(contains('712345678')));
    });

    apiTest('new name + mobile (AC-13): created first, then the sale', (
      tester,
      api,
    ) async {
      seed(api);
      api.onCall(
        'POST /vendor/customers',
        (r) => {
          'customer': {
            'id': 'cus_juma',
            'source': 'manual',
            'name': 'Juma',
            'phone': '+255688123456',
          },
          'phoneDuplicate': null,
        },
      );
      await pumpPos(tester, api);
      await openPayment(tester);
      await expandCustomer(tester);
      await typeInto(tester, find.byKey(const Key('pos-cust-name')), 'Juma');
      await typeMobile(tester, '0688 123 456');
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      final created = api.only('POST', '/vendor/customers').body as Map;
      expect(created['name'], 'Juma');
      expect(created['phone'], '+255688123456');
      expect(created['clientRef'], startsWith('cus_'));
      // Order: the customer before the sale.
      final order = api.requests
          .where((r) => r.method == 'POST')
          .map((r) => r.path)
          .toList();
      expect(order, ['/vendor/customers', '/vendor/sales']);
      final body = saleBody(api);
      expect(body['customerId'], 'cus_juma');
      expect(body['customerType'], 'new');
      expect(jsonEncode(body), isNot(contains('Juma')));
      expect(jsonEncode(body), isNot(contains('688123456')));
      // Nothing typed was kept on the device.
      final stored = await deviceStorage();
      expect(stored, isNot(contains('Juma')));
      expect(stored, isNot(contains('688123456')));
    });

    apiTest('name only (AC-14): a customer with no phone', (tester, api) async {
      seed(api);
      api.onCall(
        'POST /vendor/customers',
        (r) => {
          'customer': {'id': 'cus_neema', 'source': 'manual', 'name': 'Neema'},
          'phoneDuplicate': null,
        },
      );
      await pumpPos(tester, api);
      await openPayment(tester);
      await expandCustomer(tester);
      await tapVisible(tester, find.byKey(const Key('pos-cust-type-other')));
      await typeInto(tester, find.byKey(const Key('pos-cust-name')), 'Neema');
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      final created = api.only('POST', '/vendor/customers').body as Map;
      expect(created.containsKey('phone'), isFalse);
      expect(saleBody(api)['customerId'], 'cus_neema');
      // A type chosen by the seller is kept (not replaced by New).
      expect(saleBody(api)['customerType'], 'other');
    });

    apiTest('mobile without name / invalid mobile (AC-15): blocked inline', (
      tester,
      api,
    ) async {
      seed(api);
      final host = await pumpPos(tester, api);
      await openPayment(tester);
      await expandCustomer(tester);
      await typeMobile(tester, '0688 123 456');
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      expect(find.text(host.tr('vendor.pos.cust.nameNeeded')), findsOneWidget);
      expect(api.sent('POST', '/vendor/sales'), isFalse);
      expect(api.sent('POST', '/vendor/customers'), isFalse);
      await typeInto(tester, find.byKey(const Key('pos-cust-name')), 'Rehema');
      await typeMobile(tester, '12345');
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      expect(
        find.text(host.tr('vendor.customers.phoneInvalid')),
        findsOneWidget,
      );
      expect(api.sent('POST', '/vendor/sales'), isFalse);
    });

    apiTest('two customers share the number (AC-16): choose one', (
      tester,
      api,
    ) async {
      seed(api);
      await pumpPos(tester, api);
      await openPayment(tester);
      await expandCustomer(tester);
      await typeInto(tester, find.byKey(const Key('pos-cust-name')), 'Baraka');
      await typeMobile(tester, '0755 000 111');
      expect(
        find.text(
          '2 customers have this number. Search customers to choose one.',
        ),
        findsOneWidget,
      );
      // Never a third copy, never silently dropped.
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      expect(api.sent('POST', '/vendor/customers'), isFalse);
      expect(api.sent('POST', '/vendor/sales'), isFalse);
      // Search customers → the picker → linked.
      await tapVisible(tester, find.byKey(const Key('pos-cust-search')));
      await tapVisible(tester, find.byKey(const Key('picker-row-cus_1')));
      expect(find.text('Already a customer: Juma Mussa'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      expect(saleBody(api)['customerId'], 'cus_1');
    });

    apiTest('save fails (AC-20): Complete without customer keeps the type', (
      tester,
      api,
    ) async {
      seed(api);
      api.onCall(
        'POST /vendor/customers',
        (_) => throw http.ClientException('offline'),
      );
      final host = await pumpPos(tester, api);
      await openPayment(tester);
      await expandCustomer(tester);
      await tapVisible(tester, find.byKey(const Key('pos-cust-type-walk_in')));
      await typeInto(tester, find.byKey(const Key('pos-cust-name')), 'Zawadi');
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      expect(find.text(host.tr('vendor.pos.cust.saveFailed')), findsOneWidget);
      expect(api.sent('POST', '/vendor/sales'), isFalse);
      // Try again uses the same key.
      await tapVisible(tester, find.byKey(const Key('pos-cust-retry')));
      final tries = api.where('POST', '/vendor/customers');
      expect(tries, hasLength(2));
      expect(
        (tries[0].body as Map)['clientRef'],
        (tries[1].body as Map)['clientRef'],
      );
      await tapVisible(tester, find.byKey(const Key('pos-cust-without')));
      final body = saleBody(api);
      expect(body['customerType'], 'walk_in');
      expect(body.containsKey('customerId'), isFalse);
      expect(jsonEncode(body), isNot(contains('Zawadi')));
    });

    apiTest('queued after a created customer: id and type only on device', (
      tester,
      api,
    ) async {
      seed(api);
      api.onCall(
        'POST /vendor/customers',
        (r) => {
          'customer': {
            'id': 'cus_juma',
            'source': 'manual',
            'name': 'Juma',
            'phone': '+255688123456',
          },
          'phoneDuplicate': null,
        },
      );
      api.onCall(
        'POST /vendor/sales',
        (_) => throw http.ClientException('offline'),
      );
      await pumpPos(tester, api);
      await openPayment(tester);
      await expandCustomer(tester);
      await typeInto(tester, find.byKey(const Key('pos-cust-name')), 'Juma');
      await typeMobile(tester, '0688123456');
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(queueKey)!;
      final queued = (jsonDecode(raw) as List).single as Map;
      expect(queued['body']['customerId'], 'cus_juma');
      expect(queued['body']['customerType'], 'new');
      // The raw stored JSON: no typed name, no phone (security review).
      expect(raw, isNot(contains('Juma')));
      expect(raw, isNot(contains('688123456')));
      final stored = await deviceStorage();
      expect(stored, isNot(contains('Juma')));
      expect(stored, isNot(contains('688123456')));
    });

    apiTest('offline (AC-18): type only, queued with the type', (
      tester,
      api,
    ) async {
      seed(api);
      api.onCall(
        'POST /vendor/sales',
        (_) => throw http.ClientException('offline'),
      );
      final host = await pumpPos(tester, api);
      BrowserOnline.debugSet(false);
      await openPayment(tester);
      await expandCustomer(tester);
      expect(find.byKey(const Key('pos-cust-name')), findsNothing);
      expect(find.byKey(const Key('pos-cust-mobile')), findsNothing);
      expect(find.text(host.tr('vendor.pos.cust.offline')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('pos-cust-type-walk_in')));
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      final queued =
          (jsonDecode(prefs.getString(queueKey)!) as List).single as Map;
      expect(queued['body']['customerType'], 'walk_in');
      expect((queued['body'] as Map).containsKey('customerId'), isFalse);
      expect(api.sent('POST', '/vendor/customers'), isFalse);
    });

    apiTest('pay later (AC-21): type only; the credit body has it', (
      tester,
      api,
    ) async {
      seed(api);
      api.onCall(
        'POST /vendor/sales',
        (_) => {
          'sale': {
            ...serverSale(id: 'sal_c'),
            'kind': 'credit',
            'customer': {'id': 'cus_1', 'name': 'Juma Mussa'},
          },
        },
      );
      await pumpPos(tester, api);
      await tester.tap(find.byKey(const Key('pos-product-p1')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('pos-customer-add')));
      await tapVisible(tester, find.byKey(const Key('picker-row-cus_1')));
      await tapVisible(tester, find.byKey(const Key('pos-cart-charge')));
      await typeInto(tester, find.byKey(const Key('pos-amount-0')), '20000');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('vendor-pos-paylater')));
      await expandCustomer(tester);
      expect(find.byKey(const Key('pos-cust-name')), findsNothing);
      expect(find.byKey(const Key('pos-cust-matched')), findsNothing);
      await tapVisible(
        tester,
        find.byKey(const Key('pos-cust-type-returning')),
      );
      await tapVisible(tester, find.byKey(const Key('pos-credit-complete')));
      final body = saleBody(api);
      expect(body['kind'], 'credit');
      expect(body['customerType'], 'returning');
    });

    apiTest('customers off (AC-22): type only', (tester, api) async {
      seed(api, tools: {...extrasOn, 'customers': false});
      await pumpPos(tester, api);
      await openPayment(tester);
      await expandCustomer(tester);
      expect(find.byKey(const Key('pos-cust-type-new')), findsOneWidget);
      expect(find.byKey(const Key('pos-cust-name')), findsNothing);
      expect(find.byKey(const Key('pos-cust-offline')), findsNothing);
    });

    apiTest('sales-only staff (AC-17): match shows the name only', (
      tester,
      api,
    ) async {
      seed(api);
      api.onCall('GET /vendor/customers', (r) {
        return {
          'customers': [
            {
              'id': 'cus_asha',
              'source': 'manual',
              'name': 'Asha',
              'phoneLast3': '678',
              'forgotten': false,
            },
          ],
          'nextCursor': null,
        };
      });
      await pumpPos(tester, api, user: staffUser(['sales']));
      await openPayment(tester);
      await expandCustomer(tester);
      await typeMobile(tester, '0712345678');
      expect(find.text('Already a customer: Asha'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('pos-cust-section')),
          matching: textContaining('TSh'),
        ),
        findsNothing,
      );
    });

    apiTest('Swahili: pills and labels', (tester, api) async {
      seed(api);
      await pumpPos(tester, api, lang: 'sw');
      await openPayment(tester);
      expect(find.text('Mteja (si lazima)'), findsOneWidget);
      await expandCustomer(tester);
      for (final w in [
        'Mpya',
        'Anayerudi',
        'Wa dukani',
        'Mtandaoni',
        'Nyingine',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(const Key('pos-cust-section')),
            matching: find.text(w),
          ),
          findsOneWidget,
          reason: w,
        );
      }
      expect(find.text('Jina la mteja'), findsOneWidget);
      expect(find.text('Namba ya simu'), findsOneWidget);
    });

    apiTest('section off: a draft type not yet sent is dropped', (
      tester,
      api,
    ) async {
      SharedPreferences.setMockInitialValues({
        draftKey: jsonEncode(draftJson(customerType: 'walk_in')),
      });
      seed(api, tools: customersOn);
      await pumpPos(tester, api);
      await tapVisible(tester, find.byKey(const Key('pos-cart-charge')));
      expect(find.byKey(const Key('pos-cust-section')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      expect(saleBody(api).containsKey('customerType'), isFalse);
    });

    apiTest('section off: a draft already being sent keeps key and type', (
      tester,
      api,
    ) async {
      // Killed mid-send (clientRef fixed), reopened with the flag off: the
      // retry must replay the same sale, not make a new key (duplicate).
      SharedPreferences.setMockInitialValues({
        draftKey: jsonEncode(
          draftJson(customerType: 'walk_in', clientRef: 'sale_kept0001'),
        ),
      });
      seed(api, tools: customersOn);
      await pumpPos(tester, api);
      await tapVisible(tester, find.byKey(const Key('pos-cart-charge')));
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      final body = saleBody(api);
      expect(body['clientRef'], 'sale_kept0001');
      expect(body['customerType'], 'walk_in');
    });
  });
}
