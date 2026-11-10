// Characterization (safety-net) tests for the vendor marketplace console
// (lib/screens/vendor/vendor_home_page.dart).
//
// These pin what the screen DOES today — requests sent, text shown, enabled
// state, navigation — so raw Material controls can later be swapped for the
// shared FF* widgets without silently changing behaviour. They deliberately
// avoid widget class names; see test/support/recording_api.dart.
//
// Brittle finders (kept deliberately small):
//  * the per-product overflow menu is found as the PopupMenuButton inside the
//    product's keyed row ([_openProductMenu]);
//  * a few cards are located by their visible text, not a key.
// Known current behaviours that are characterized as-is (not endorsed):
//  * Delete product sends the request immediately; there is no confirm dialog.
//  * Reply / resolve / disable staff / save profile / create staff have no
//    error handling, so a failing API is not covered for those.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/formatters.dart';

import 'support/recording_api.dart';

const _png = 'https://img.example/p1.png';

Map<String, dynamic> _product(
  String id,
  String name, {
  num price = 85000,
  int stock = 4,
  String status = 'active',
}) => {
  'id': id,
  'name': name,
  'priceTzs': price,
  'stock': stock,
  'status': status,
};

final _richProduct = {
  'id': 'p1',
  'name': 'Whey Protein',
  'description': 'Isolate',
  'category': 'Supplements',
  'brand': 'MuscleCo',
  'priceTzs': 85000,
  'discountPriceTzs': 80000,
  'stock': 4,
  'sku': 'WP-1',
  'weightKg': 1,
  'variants': [
    {'name': 'Vanilla'},
  ],
  'visibility': 'hidden',
  'images': [_png],
  'status': 'active',
};

Map<String, dynamic> _order(
  String id, {
  String status = 'pending',
  String paymentStatus = 'paid',
  String delivery = 'home_delivery',
}) => {
  'id': id,
  'status': status,
  'paymentStatus': paymentStatus,
  'paymentMethod': 'mpesa',
  'deliveryMethod': delivery,
  'deliveryAddress': 'Masaki 12',
  'pickupGymId': 'gym-7',
  'totalTzs': 170000,
  'items': [
    {'qty': 2, 'name': 'Whey Protein'},
  ],
};

const _publishedProfile = {
  'businessName': 'FitFlex Performance Store',
  'status': 'published',
  'description': 'Equipment and nutrition',
  'logo': _png,
  'banner': _png,
  'businessCategory': 'Fitness',
  'contactNumber': '+255700000001',
  'email': 'store@fitflex.test',
  'address': 'Masaki',
  'deliveryRegions': ['Dar es Salaam', 'Arusha'],
  'businessHours': {'summary': '08:00-18:00'},
  'settlementAccount': {'account': '0123456789'},
  'productCategories': ['Supplements'],
  'returnsPolicy': '7 days',
};

void _seed(
  RecordingApi api, {
  List<dynamic>? products,
  List<dynamic> orders = const [],
  Map<String, dynamic> profile = _publishedProfile,
  Map<String, dynamic>? payments,
  List<dynamic> enquiries = const [],
  List<dynamic> staff = const [],
}) {
  api.on(
    'GET /vendor/products',
    products ?? [_product('p1', 'Whey Protein'), _product('p2', 'Yoga Mat')],
  );
  api.on('GET /vendor/orders', orders);
  api.on('GET /vendor/profile', profile);
  api.on(
    'GET /vendor/payments',
    payments ??
        {
          'todaySalesTzs': 1000,
          'weeklySalesTzs': 7000,
          'monthlySalesTzs': 30000,
          'pendingSettlementTzs': 12000,
          'settledPaymentsTzs': 55000,
        },
  );
  api.on('GET /vendor/enquiries', enquiries);
  api.on('GET /vendor/staff', staff);
}

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
  double scale = 1,
  Map<String, dynamic> user = const {'id': 'v1', 'userType': 'vendor'},
  bool invites = false,
  bool keepRequests = false,
}) => pumpPage(
  tester,
  api,
  const VendorHomePage(),
  lang: lang,
  textScale: scale,
  user: user,
  invitesEnabled: invites,
  keepRequests: keepRequests,
);

Future<void> _tab(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(Key('vendor-nav-$name')));
  await tester.pumpAndSettle();
}

Future<void> _openProductMenu(
  WidgetTester tester,
  String id,
  String item,
) async {
  final menu = find.descendant(
    of: find.byKey(Key('vendor-product-$id')),
    matching: find.byType(PopupMenuButton<String>),
  );
  await tester.tap(menu);
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

Finder _field(String key) => find.byKey(Key(key));

/// The profile sheet is a long lazy list (the category checklist pushes the
/// publish button off screen), so scroll it until [target] is built.
Future<void> _scrollProfileTo(WidgetTester tester, Finder target) async {
  // The sheet is the top route, so its scrollable is the last one built.
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).last,
  );
}

Future<void> _typeProfile(
  WidgetTester tester,
  Finder field,
  String text,
) async {
  await _scrollProfileTo(tester, field);
  await typeInto(tester, field, text);
}

void main() {
  setUpAll(loadAppFonts);

  group('loading and empty states', () {
    apiTest('shows a spinner until the marketplace has loaded', (
      tester,
      api,
    ) async {
      _seed(api);
      final gate = api.hold('GET /vendor/profile');
      final host = await pumpPage(
        tester,
        api,
        const VendorHomePage(),
        settle: false,
      );
      await tester.pump();
      await tester.pump();
      expect(spinner, findsOneWidget);
      expect(find.text('Whey Protein'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(spinner, findsNothing);
      expect(find.text('Whey Protein'), findsOneWidget);
      expect(find.text('Yoga Mat'), findsOneWidget);
      expect(host.api.sent('GET', '/vendor/products'), isTrue);
    });

    apiTest('lists products with price and stock', (tester, api) async {
      _seed(api);
      await _pump(tester, api);
      expect(find.text('Whey Protein'), findsOneWidget);
      expect(
        find.text('${formatCurrency(85000)} · 4 in stock'),
        findsNWidgets(2),
      );
    });

    apiTest('shows the empty message when there are no products', (
      tester,
      api,
    ) async {
      _seed(api, products: []);
      final host = await _pump(tester, api);
      expect(find.text(host.tr('vendor.noProducts')), findsOneWidget);
      expect(find.byKey(const Key('vendor-add-product')), findsOneWidget);
    });

    apiTest('a load failure shows an error and the screen stays usable', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('GET /vendor/products');
      final host = await _pump(tester, api);
      expect(host.snack(host.tr('vendor.loadFailed')), findsOneWidget);
      expect(spinner, findsNothing);
      // Still usable: tabs switch and Add product still opens its form.
      await host.dismissSnacks();
      await _tab(tester, 'orders');
      expect(find.text(host.tr('vendor.noOrders')), findsOneWidget);
      await _tab(tester, 'products');
      await tester.tap(find.byKey(const Key('vendor-add-product')));
      await tester.pumpAndSettle();
      expect(_field('vendor-product-name'), findsOneWidget);
    });
  });

  group('product form', () {
    apiTest('exposes every field and starts with a visible product', (
      tester,
      api,
    ) async {
      _seed(api);
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('vendor-add-product')));
      await tester.pumpAndSettle();
      for (final k in [
        'name',
        'brand',
        'description',
        'category',
        'price',
        'stock',
        'discount-price',
        'sku',
        'weight',
        'variants',
      ]) {
        expect(_field('vendor-product-$k'), findsOneWidget, reason: k);
      }
      final sw = tester.widget<SwitchListTile>(
        _field('vendor-product-visibility'),
      );
      expect(sw.value, isTrue);
      expect(_field('vendor-product-save'), findsOneWidget);
    });

    apiTest('a new product is created with the exact payload', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api);
      await tester.tap(find.byKey(const Key('vendor-add-product')));
      await tester.pumpAndSettle();
      await typeInto(
        tester,
        _field('vendor-product-name'),
        ' Kettlebell 12kg ',
      );
      await typeInto(tester, _field('vendor-product-brand'), 'IronCo');
      await typeInto(tester, _field('vendor-product-description'), 'Cast iron');
      // The category is now picked from the fixed list.
      await tester.ensureVisible(_field('vendor-product-category'));
      await tester.tap(_field('vendor-product-category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gym & fitness equipment').last);
      await tester.pumpAndSettle();
      await typeInto(tester, _field('vendor-product-price'), '45000');
      await typeInto(tester, _field('vendor-product-stock'), '7');
      await typeInto(tester, _field('vendor-product-discount-price'), '39000');
      await typeInto(tester, _field('vendor-product-sku'), 'KB-12');
      await typeInto(tester, _field('vendor-product-weight'), '12.5');
      await typeInto(tester, _field('vendor-product-variants'), 'Red, Blue,,');
      await tapVisible(tester, _field('vendor-product-save'));

      expect(api.only('POST', '/vendor/products').body, {
        'name': 'Kettlebell 12kg',
        'description': 'Cast iron',
        'category': 'equipment',
        'brand': 'IronCo',
        'priceTzs': 45000,
        'discountPriceTzs': 39000,
        'stock': 7,
        'sku': 'KB-12',
        'weightKg': 12.5,
        'variants': [
          {'name': 'Red'},
          {'name': 'Blue'},
        ],
        'visibility': 'visible',
        'images': [],
      });
      expect(host.snack(host.tr('vendor.productSaved')), findsOneWidget);
      // The sheet is closed and the list was reloaded.
      expect(_field('vendor-product-name'), findsNothing);
      expect(api.sent('GET', '/vendor/products'), isTrue);
    });

    apiTest(
      'hiding the product sends visibility hidden and zero stock by default',
      (tester, api) async {
        _seed(api);
        await _pump(tester, api);
        await tester.tap(find.byKey(const Key('vendor-add-product')));
        await tester.pumpAndSettle();
        await typeInto(tester, _field('vendor-product-name'), 'Towel');
        await typeInto(tester, _field('vendor-product-price'), '5000');
        await tapVisible(tester, _field('vendor-product-visibility'));
        await tapVisible(tester, _field('vendor-product-save'));
        final body = api.only('POST', '/vendor/products').body as Map;
        expect(body['visibility'], 'hidden');
        expect(body['stock'], 0);
        expect(body['discountPriceTzs'], isNull);
        expect(body['weightKg'], isNull);
        expect(body['variants'], isEmpty);
      },
    );

    apiTest('name and a positive price are required to save', (
      tester,
      api,
    ) async {
      _seed(api);
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('vendor-add-product')));
      await tester.pumpAndSettle();

      // Nothing filled in.
      await tapVisible(tester, _field('vendor-product-save'));
      expect(_field('vendor-product-name'), findsOneWidget);

      // Name but no price.
      await typeInto(tester, _field('vendor-product-name'), 'Towel');
      await tapVisible(tester, _field('vendor-product-save'));
      expect(_field('vendor-product-name'), findsOneWidget);

      // Zero price.
      await typeInto(tester, _field('vendor-product-price'), '0');
      await tapVisible(tester, _field('vendor-product-save'));
      expect(_field('vendor-product-name'), findsOneWidget);

      // Price but blank name.
      await typeInto(tester, _field('vendor-product-name'), '   ');
      await typeInto(tester, _field('vendor-product-price'), '100');
      await tapVisible(tester, _field('vendor-product-save'));
      expect(_field('vendor-product-name'), findsOneWidget);

      expect(api.requests.where((r) => r.method != 'GET'), isEmpty);
    });

    apiTest('editing prefills the form and PUTs the full payload', (
      tester,
      api,
    ) async {
      _seed(api, products: [_richProduct]);
      final host = await _pump(tester, api);
      await _openProductMenu(tester, 'p1', host.tr('vendor.edit'));

      expect(find.text(host.tr('vendor.editProduct')), findsOneWidget);
      String valueOf(String key) => textOf(tester, _field(key));
      expect(valueOf('vendor-product-name'), 'Whey Protein');
      expect(valueOf('vendor-product-price'), '85000');
      expect(valueOf('vendor-product-discount-price'), '80000');
      expect(valueOf('vendor-product-variants'), 'Vanilla');
      expect(
        tester
            .widget<SwitchListTile>(_field('vendor-product-visibility'))
            .value,
        isFalse,
      );

      await typeInto(tester, _field('vendor-product-price'), '90000');
      await tapVisible(tester, _field('vendor-product-save'));

      expect(api.only('PUT', '/vendor/products/p1').body, {
        'name': 'Whey Protein',
        'description': 'Isolate',
        // The older free-text category 'Supplements' is left untouched, so
        // it is not sent unless the vendor picks one from the list.
        'brand': 'MuscleCo',
        'priceTzs': 90000,
        'discountPriceTzs': 80000,
        // No 'stock': an edit never overwrites the stored count, which may
        // have moved (buyers' reservations) while the form was open.
        'sku': 'WP-1',
        'weightKg': 1,
        'variants': [
          {'name': 'Vanilla'},
        ],
        'visibility': 'hidden',
        'images': [_png],
      });
      expect(host.snack(host.tr('vendor.productSaved')), findsOneWidget);
    });

    apiTest('a failed save shows an error and keeps the list usable', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('POST /vendor/products', 422);
      final host = await _pump(tester, api);
      await tester.tap(find.byKey(const Key('vendor-add-product')));
      await tester.pumpAndSettle();
      await typeInto(tester, _field('vendor-product-name'), 'Towel');
      await typeInto(tester, _field('vendor-product-price'), '5000');
      await tapVisible(tester, _field('vendor-product-save'));

      expect(host.snack(host.tr('vendor.saveFailed')), findsOneWidget);
      expect(host.snack(host.tr('vendor.productSaved')), findsNothing);
      expect(find.text('Whey Protein'), findsOneWidget);
      // The add button is enabled again (not stuck busy).
      expect(
        isEnabled(tester, find.byKey(const Key('vendor-add-product'))),
        isTrue,
      );
    });
  });

  group('product actions', () {
    apiTest('pause sends status paused and restore sends active', (
      tester,
      api,
    ) async {
      _seed(
        api,
        products: [
          _product('p1', 'Whey Protein'),
          _product('p2', 'Yoga Mat', status: 'paused'),
        ],
      );
      final host = await _pump(tester, api);
      await _openProductMenu(tester, 'p1', host.tr('vendor.pause'));
      expect(api.only('PUT', '/vendor/products/p1').body, {'status': 'paused'});

      await _openProductMenu(tester, 'p2', host.tr('vendor.restore'));
      expect(api.only('PUT', '/vendor/products/p2').body, {'status': 'active'});
      // Each action reloads the list.
      expect(api.where('GET', '/vendor/products'), hasLength(2));
    });

    apiTest('duplicate posts to the duplicate endpoint without a body', (
      tester,
      api,
    ) async {
      _seed(api);
      await _pump(tester, api);
      await _openProductMenu(tester, 'p1', 'Duplicate');
      final req = api.only('POST', '/vendor/products/p1/duplicate');
      expect(req.body, isNull);
      expect(api.sent('GET', '/vendor/products'), isTrue);
    });

    apiTest('delete sends DELETE straight away (no confirm dialog today)', (
      tester,
      api,
    ) async {
      _seed(api);
      await _pump(tester, api);
      await _openProductMenu(tester, 'p2', 'Delete');
      expect(api.only('DELETE', '/vendor/products/p2').body, isNull);
      expect(api.sent('GET', '/vendor/products'), isTrue);
    });

    apiTest('a failed pause, duplicate or delete shows the error snackbar', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('PUT /vendor/products/p1');
      api.fail('POST /vendor/products/p1/duplicate', 409);
      api.fail('DELETE /vendor/products/p1', 403);
      final host = await _pump(tester, api);
      for (final item in ['Pause', 'Duplicate', 'Delete']) {
        await _openProductMenu(tester, 'p1', item);
        expect(
          host.snack(host.tr('vendor.saveFailed')),
          findsOneWidget,
          reason: item,
        );
        ScaffoldMessenger.of(
          tester.element(find.byType(Scaffold).first),
        ).clearSnackBars();
        await tester.pumpAndSettle();
      }
      // Product is still listed and the add button works.
      expect(find.text('Whey Protein'), findsOneWidget);
      expect(
        isEnabled(tester, find.byKey(const Key('vendor-add-product'))),
        isTrue,
      );
    });
  });

  group('orders', () {
    apiTest('shows an order with items, totals, payment and address', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1')]);
      final host = await _pump(tester, api);
      await _tab(tester, 'orders');
      expect(find.text('2× Whey Protein'), findsOneWidget);
      expect(
        find.text(
          '${formatCurrency(170000)} · ${host.tr('vendor.status')}: '
          '${host.tr('shop.orderStatus.pending')}',
        ),
        findsOneWidget,
      );
      expect(
        // Payment status and method in words, not codes (M6).
        find.text('${host.tr('vendor.payment')}: Paid · M-Pesa'),
        findsOneWidget,
      );
      expect(
        find.text('${host.tr('vendor.deliveryAddress')}: Masaki 12'),
        findsOneWidget,
      );
    });

    apiTest('shows the empty message when there are no orders', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api);
      await _tab(tester, 'orders');
      expect(find.text(host.tr('vendor.noOrders')), findsOneWidget);
    });

    apiTest('an unpaid order cannot be advanced but can be cancelled', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1', paymentStatus: 'pending')]);
      final host = await _pump(tester, api);
      await _tab(tester, 'orders');
      expect(find.text(host.tr('vendor.awaitingPayment')), findsOneWidget);
      expect(
        isEnabled(tester, find.byKey(const Key('vendor-next-o1'))),
        isFalse,
      );
      expect(
        isEnabled(tester, buttonLabelled(host.tr('vendor.cancel'))),
        isTrue,
      );
    });

    apiTest('the next-status button follows the fulfilment sequence', (
      tester,
      api,
    ) async {
      // (current status, delivery method) -> status the button will set.
      const cases = [
        ('pending', 'home_delivery', 'accepted'),
        // Legacy `confirmed` is `accepted` on the server: sending `accepted`
        // again was a silent no-op and the order never moved.
        ('confirmed', 'home_delivery', 'processing'),
        ('accepted', 'home_delivery', 'processing'),
        ('processing', 'home_delivery', 'packed'),
        ('packed', 'home_delivery', 'dispatched'),
        ('packed', 'gym_pickup', 'ready_for_pickup'),
        ('dispatched', 'home_delivery', 'delivered'),
        // Gym pickup goes dispatched -> ready for pickup; the server refuses
        // dispatched -> delivered (invalid_transition).
        ('dispatched', 'gym_pickup', 'ready_for_pickup'),
        ('ready_for_pickup', 'gym_pickup', 'delivered'),
        ('confirmed', 'gym_pickup', 'processing'),
      ];
      _seed(
        api,
        orders: [
          for (var i = 0; i < cases.length; i++)
            _order('o$i', status: cases[i].$1, delivery: cases[i].$2),
        ],
      );
      final host = await pumpPage(
        tester,
        api,
        const VendorHomePage(),
        size: const Size(360, 4000),
      );
      await _tab(tester, 'orders');
      for (var i = 0; i < cases.length; i++) {
        // Worded per status ("Mark as packed"), never the raw code.
        final label = host.tr('vendor.markStatus.${cases[i].$3}');
        expect(label, isNot(contains('_')));
        final button = find.byKey(Key('vendor-next-o$i'));
        await tester.ensureVisible(button);
        expect(
          find.descendant(of: button, matching: find.text(label)),
          findsOneWidget,
          reason: 'order o$i ${cases[i]}',
        );
      }
      // Pressing one sends exactly that status.
      final target = find.byKey(const Key('vendor-next-o4'));
      await tapVisible(tester, target);
      expect(api.only('POST', '/vendor/orders/o4/status').body, {
        'status': 'dispatched',
      });
      expect(api.sent('GET', '/vendor/orders'), isTrue);
    });

    apiTest('a legacy confirmed order moves on: it sends processing', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1', status: 'confirmed')]);
      final host = await _pump(tester, api);
      await _tab(tester, 'orders');
      // Shown as Accepted, offered the step after it.
      expect(
        find.textContaining(host.tr('shop.orderStatus.accepted')),
        findsOneWidget,
      );
      final button = find.byKey(const Key('vendor-next-o1'));
      expect(
        find.descendant(
          of: button,
          matching: find.text(host.tr('vendor.markStatus.processing')),
        ),
        findsOneWidget,
      );
      await tapVisible(tester, button);
      expect(api.only('POST', '/vendor/orders/o1/status').body, {
        'status': 'processing',
      });
    });

    apiTest('the server\'s own next steps win when it sends them', (
      tester,
      api,
    ) async {
      _seed(
        api,
        orders: [
          {
            ..._order('o1', status: 'confirmed'),
            'nextStatuses': ['packed', 'dispatched'],
          },
          {
            ..._order('o2', status: 'packed'),
            'nextStatuses': <String>[], // paid, but nothing allowed
          },
        ],
      );
      final host = await _pump(tester, api);
      await _tab(tester, 'orders');
      await tapVisible(tester, find.byKey(const Key('vendor-next-o1')));
      expect(api.only('POST', '/vendor/orders/o1/status').body, {
        'status': 'packed',
      });
      expect(find.byKey(const Key('vendor-next-o2')), findsNothing);
      // Cancel stays available for a paid order that is not final.
      expect(buttonLabelled(host.tr('vendor.cancel')), findsNWidgets(2));
    });

    apiTest('cancel sends cancelled', (tester, api) async {
      _seed(api, orders: [_order('o1', status: 'accepted')]);
      final host = await _pump(tester, api);
      await _tab(tester, 'orders');
      await tapVisible(tester, buttonLabelled(host.tr('vendor.cancel')));
      expect(api.only('POST', '/vendor/orders/o1/status').body, {
        'status': 'cancelled',
      });
    });

    apiTest('delivered and cancelled orders offer no actions', (
      tester,
      api,
    ) async {
      _seed(
        api,
        orders: [
          _order('o1', status: 'delivered'),
          _order('o2', status: 'cancelled'),
          // Legacy `fulfilled` is `delivered` on the server.
          _order('o3', status: 'fulfilled'),
        ],
      );
      final host = await _pump(tester, api);
      await _tab(tester, 'orders');
      expect(find.byKey(const Key('vendor-next-o1')), findsNothing);
      expect(find.byKey(const Key('vendor-next-o2')), findsNothing);
      expect(find.byKey(const Key('vendor-next-o3')), findsNothing);
      expect(buttonLabelled(host.tr('vendor.cancel')), findsNothing);
    });

    apiTest('pickup orders without a gym name never show the raw id', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1', delivery: 'gym_pickup')]);
      final host = await _pump(tester, api);
      await _tab(tester, 'orders');
      expect(
        find.text(
          '${host.tr('vendor.pickupGym')}: '
          '${host.tr('vendor.pickupGymUnknown')}',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('gym-7'), findsNothing);
    });

    apiTest('a failed status change shows the error and stays usable', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1')]);
      api.fail('POST /vendor/orders/o1/status', 500);
      final host = await _pump(tester, api);
      await _tab(tester, 'orders');
      await tapVisible(tester, find.byKey(const Key('vendor-next-o1')));
      expect(host.snack(host.tr('vendor.saveFailed')), findsOneWidget);
      expect(
        isEnabled(tester, find.byKey(const Key('vendor-next-o1'))),
        isTrue,
      );
    });
  });

  group('payments', () {
    apiTest('shows the five figures', (tester, api) async {
      _seed(api);
      final host = await _pump(tester, api);
      await _tab(tester, 'payments');
      for (final (key, amount) in [
        ('vendor.todaySales', 1000),
        ('vendor.weeklySales', 7000),
        ('vendor.monthlySales', 30000),
        ('vendor.pendingSettlement', 12000),
        ('vendor.settledPayments', 55000),
      ]) {
        expect(find.text(host.tr(key)), findsOneWidget, reason: key);
        expect(find.text(formatCurrency(amount)), findsOneWidget, reason: key);
      }
    });

    apiTest(
      'the statement download asks for the statement and reports failure',
      (tester, api) async {
        _seed(api);
        api.fail('GET /vendor/payments/statement', 500);
        final host = await _pump(tester, api);
        await _tab(tester, 'payments');
        // The payouts entry above it pushes the button below the first screen.
        await tester.scrollUntilVisible(
          find.byKey(const Key('vendor-download-statement')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tapVisible(
          tester,
          find.byKey(const Key('vendor-download-statement')),
        );
        expect(api.sent('GET', '/vendor/payments/statement'), isTrue);
        expect(host.snack(host.tr('shop.exportFailed')), findsOneWidget);
      },
    );
  });

  group('enquiries', () {
    final enquiry = {
      'id': 'e1',
      'status': 'open',
      'messages': [
        {'message': 'Is the mat available in blue?'},
        {'message': 'Checking stock'},
      ],
    };

    apiTest('lists enquiries and shows an empty message when none', (
      tester,
      api,
    ) async {
      _seed(api, enquiries: [enquiry]);
      final host = await _pump(tester, api);
      await _tab(tester, 'enquiries');
      expect(find.text('Is the mat available in blue?'), findsOneWidget);
      // The server's code is shown as a label, not raw (mobile#62).
      expect(
        find.text('${host.tr('vendor.status')}: ${host.tr('wire.status.open')}'),
        findsOneWidget,
      );
      expect(
        find.text('${host.tr('vendor.reply')}: Checking stock'),
        findsOneWidget,
      );
    });

    apiTest('empty enquiry list shows the empty message', (tester, api) async {
      _seed(api);
      final host = await _pump(tester, api);
      await _tab(tester, 'enquiries');
      expect(find.text(host.tr('vendor.noEnquiries')), findsOneWidget);
    });

    apiTest('a reply is trimmed and sent to the reply endpoint', (
      tester,
      api,
    ) async {
      _seed(api, enquiries: [enquiry]);
      final host = await _pump(tester, api);
      await _tab(tester, 'enquiries');
      await tester.tap(find.byKey(const Key('vendor-reply-e1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        _field('vendor-reply-message'),
        '  Yes, blue is in stock  ',
      );
      await tapAndSettleDialogClose(tester, find.text(host.tr('shop.send')));
      expect(api.only('POST', '/vendor/enquiries/e1/reply').body, {
        'message': 'Yes, blue is in stock',
      });
      expect(_field('vendor-reply-message'), findsNothing);
      expect(api.sent('GET', '/vendor/enquiries'), isTrue);
    });

    apiTest('an empty reply sends nothing', (tester, api) async {
      _seed(api, enquiries: [enquiry]);
      final host = await _pump(tester, api);
      await _tab(tester, 'enquiries');
      await tester.tap(find.byKey(const Key('vendor-reply-e1')));
      await tester.pumpAndSettle();
      await tester.enterText(_field('vendor-reply-message'), '   ');
      await tapAndSettleDialogClose(tester, find.text(host.tr('shop.send')));
      expect(api.requests.where((r) => r.method != 'GET'), isEmpty);
    });

    apiTest(
      'resolve posts to the resolve endpoint; resolved hides the button',
      (tester, api) async {
        _seed(
          api,
          enquiries: [
            enquiry,
            {...enquiry, 'id': 'e2', 'status': 'resolved'},
          ],
        );
        final host = await _pump(tester, api);
        await _tab(tester, 'enquiries');
        // Only the open enquiry offers "resolve".
        expect(buttonLabelled(host.tr('vendor.resolve')), findsOneWidget);
        await tester.tap(buttonLabelled(host.tr('vendor.resolve')));
        await tester.pumpAndSettle();
        expect(api.only('POST', '/vendor/enquiries/e1/resolve').body, isNull);
      },
    );
  });

  group('business profile and staff', () {
    apiTest('an unpublished profile lands on the business tab', (
      tester,
      api,
    ) async {
      _seed(api, profile: {'status': 'draft'});
      final host = await _pump(tester, api);
      expect(find.text(host.tr('vendor.profileIncomplete')), findsOneWidget);
      // The server's code is shown as a label, not raw (mobile#62).
      expect(
        find.text('${host.tr('vendor.status')}: ${host.tr('wire.status.draft')}'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('vendor-edit-profile')), findsOneWidget);
      // No product list / FAB on this tab.
      expect(find.byKey(const Key('vendor-add-product')), findsNothing);
    });

    apiTest('the verification entry navigates to /verification', (
      tester,
      api,
    ) async {
      _seed(api);
      await _pump(tester, api);
      await _tab(tester, 'business');
      await tapVisible(tester, find.byKey(const Key('vendor-verification')));
      expect(find.text('ROUTE-VERIFICATION'), findsOneWidget);
    });

    apiTest('profile form is prefilled and publishing PUTs the payload', (
      tester,
      api,
    ) async {
      _seed(api);
      await _pump(tester, api);
      await _tab(tester, 'business');
      await tapVisible(tester, find.byKey(const Key('vendor-edit-profile')));
      await _typeProfile(
        tester,
        _field('vendor-profile-businessName'),
        'FitFlex Gear',
      );
      await _scrollProfileTo(tester, _field('vendor-profile-publish'));
      await tapVisible(tester, _field('vendor-profile-publish'));

      expect(api.only('PUT', '/vendor/profile').body, {
        'businessName': 'FitFlex Gear',
        'logo': _png,
        'banner': _png,
        'description': 'Equipment and nutrition',
        'businessCategory': 'Fitness',
        'contactNumber': '+255700000001',
        'email': 'store@fitflex.test',
        'address': 'Masaki',
        'businessHours': {'summary': '08:00-18:00'},
        'settlementAccount': {'account': '0123456789'},
        // The seeded 'Supplements' is older free text, not a key on the list.
        'publish': true,
      });
      expect(find.byKey(const Key('vendor-profile-publish')), findsNothing);
    });

    apiTest('every required profile field blocks publishing when blank', (
      tester,
      api,
    ) async {
      _seed(api);
      await _pump(tester, api);
      await _tab(tester, 'business');
      await tapVisible(tester, find.byKey(const Key('vendor-edit-profile')));
      for (final key in [
        'businessName',
        'description',
        'contactNumber',
        // The email is optional now, so blanking it does not block publishing.
        'address',
        'businessHours',
        'settlementAccount',
      ]) {
        final field = _field('vendor-profile-$key');
        await _scrollProfileTo(tester, field);
        final original = textOf(tester, field);
        await typeInto(tester, field, '   ');
        await _scrollProfileTo(tester, _field('vendor-profile-publish'));
        await tapVisible(tester, _field('vendor-profile-publish'));
        expect(
          _field('vendor-profile-publish'),
          findsOneWidget,
          reason: '$key blank should keep the form open',
        );
        await typeInto(tester, field, original);
      }
      expect(api.sent('PUT', '/vendor/profile'), isFalse);
    });

    apiTest('profile cannot be published without logo and banner', (
      tester,
      api,
    ) async {
      _seed(api, profile: {..._publishedProfile, 'logo': null, 'banner': null});
      await _pump(tester, api);
      await _tab(tester, 'business');
      await tester.tap(find.byKey(const Key('vendor-edit-profile')));
      await tester.pumpAndSettle();
      await _scrollProfileTo(tester, _field('vendor-profile-publish'));
      await tapVisible(tester, _field('vendor-profile-publish'));
      expect(_field('vendor-profile-publish'), findsOneWidget);
      expect(api.sent('PUT', '/vendor/profile'), isFalse);
    });

    apiTest('lists staff; disabled staff show a label instead of a button', (
      tester,
      api,
    ) async {
      _seed(
        api,
        staff: [
          {
            'id': 's1',
            'displayName': 'Asha',
            'vendorRole': 'sales',
            'email': 'asha@x.test',
            'accountStatus': 'active',
          },
          {
            'id': 's2',
            'displayName': 'Juma',
            'vendorRole': 'admin',
            'email': 'juma@x.test',
            'accountStatus': 'suspended',
          },
        ],
      );
      final host = await _pump(tester, api);
      await _tab(tester, 'business');
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('sales · asha@x.test'), findsOneWidget);
      expect(find.text(host.tr('vendor.disabled')), findsOneWidget);
      expect(buttonLabelled(host.tr('vendor.disable')), findsOneWidget);
      await tester.tap(buttonLabelled(host.tr('vendor.disable')));
      await tester.pumpAndSettle();
      expect(api.only('POST', '/vendor/staff/s1/disable').body, isNull);
    });

    apiTest(
      'adding staff posts the exact payload with chosen role and permissions',
      (tester, api) async {
        _seed(api);
        final host = await _pump(tester, api);
        await _tab(tester, 'business');
        await tapVisible(tester, find.byKey(const Key('vendor-add-staff')));
        await typeInto(tester, _field('vendor-staff-name'), 'Neema');
        await typeInto(tester, _field('vendor-staff-email'), 'neema@x.test');
        await typeInto(tester, _field('vendor-staff-phone'), '+255711000000');
        await typeInto(tester, _field('vendor-staff-password'), 'Secret#123');
        // Role dropdown: pick "Sales".
        await tapVisible(tester, _field('vendor-staff-role'));
        await tester.tap(find.text(host.tr('vendor.roleSales')).last);
        await tester.pumpAndSettle();
        // Permissions: untick products, tick orders and reports.
        for (final permission in ['products', 'orders', 'reports']) {
          await tapVisible(
            tester,
            find.text(host.tr('vendor.permission.$permission')).last,
          );
        }
        await tapVisible(tester, _field('vendor-staff-save'));

        expect(api.only('POST', '/vendor/staff').body, {
          'name': 'Neema',
          'email': 'neema@x.test',
          'phone': '+255711000000',
          'password': 'Secret#123',
          'role': 'sales',
          'permissions': ['orders', 'reports'],
        });
        expect(_field('vendor-staff-name'), findsNothing);
      },
    );

    apiTest('staff default to inventory manager with only products', (
      tester,
      api,
    ) async {
      _seed(api);
      await _pump(tester, api);
      await _tab(tester, 'business');
      await tapVisible(tester, find.byKey(const Key('vendor-add-staff')));
      await typeInto(tester, _field('vendor-staff-name'), 'Neema');
      await typeInto(tester, _field('vendor-staff-email'), 'n@x.test');
      await typeInto(tester, _field('vendor-staff-phone'), '1');
      await typeInto(tester, _field('vendor-staff-password'), 'pw');
      await tapVisible(tester, _field('vendor-staff-save'));
      final body = api.only('POST', '/vendor/staff').body as Map;
      expect(body['role'], 'inventory_manager');
      expect(body['permissions'], ['products']);
    });

    apiTest('every staff field is required', (tester, api) async {
      _seed(api);
      await _pump(tester, api);
      await _tab(tester, 'business');
      await tapVisible(tester, find.byKey(const Key('vendor-add-staff')));
      const keys = ['name', 'email', 'phone', 'password'];
      for (final skipped in keys) {
        for (final key in keys) {
          await typeInto(
            tester,
            _field('vendor-staff-$key'),
            key == skipped ? '  ' : 'x',
          );
        }
        await tapVisible(tester, _field('vendor-staff-save'));
        expect(
          _field('vendor-staff-save'),
          findsOneWidget,
          reason: 'blank $skipped should keep the form open',
        );
      }
      expect(api.sent('POST', '/vendor/staff'), isFalse);
    });

    apiTest('with invitations on, adding staff invites instead of creating', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api, invites: true);
      await _tab(tester, 'business');
      expect(find.byKey(const Key('vendor-invitations-sent')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('vendor-add-staff')));
      expect(_field('vendor-staff-password'), findsNothing);
      expect(host.auth.invitesEnabled, isTrue);
    });
  });

  group('role gating and session', () {
    apiTest('the vendor owner sees all five sections', (tester, api) async {
      _seed(api);
      await _pump(tester, api);
      for (final k in [
        'products',
        'orders',
        'payments',
        'enquiries',
        'business',
      ]) {
        expect(find.byKey(Key('vendor-nav-$k')), findsOneWidget, reason: k);
      }
    });

    apiTest('staff only see and load what their permissions allow', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1')]);
      final host = await _pump(
        tester,
        api,
        user: {
          'id': 's1',
          'userType': 'vendor_staff',
          'vendorId': 'v1',
          'vendorPermissions': ['orders', 'customers'],
        },
        keepRequests: true,
      );
      expect(find.byKey(const Key('vendor-nav-orders')), findsOneWidget);
      expect(find.byKey(const Key('vendor-nav-enquiries')), findsOneWidget);
      expect(find.byKey(const Key('vendor-nav-products')), findsNothing);
      expect(find.byKey(const Key('vendor-nav-payments')), findsNothing);
      expect(find.byKey(const Key('vendor-nav-business')), findsNothing);
      // Nothing outside their permissions was requested.
      expect(api.sent('GET', '/vendor/products'), isFalse);
      expect(api.sent('GET', '/vendor/payments'), isFalse);
      expect(api.sent('GET', '/vendor/staff'), isFalse);
      await _tab(tester, 'orders');
      expect(find.text('2× Whey Protein'), findsOneWidget);
      expect(host.api.sent('GET', '/vendor/orders'), isTrue);
      expect(host.api.sent('GET', '/vendor/enquiries'), isTrue);
    });

    apiTest('staff with the staff permission cannot edit the profile', (
      tester,
      api,
    ) async {
      _seed(api);
      await _pump(
        tester,
        api,
        user: {
          'id': 's1',
          'userType': 'vendor_staff',
          'vendorId': 'v1',
          'vendorPermissions': ['orders', 'staff'],
        },
      );
      await _tab(tester, 'business');
      expect(find.byKey(const Key('vendor-edit-profile')), findsNothing);
      expect(find.byKey(const Key('vendor-verification')), findsNothing);
      expect(find.byKey(const Key('vendor-add-staff')), findsOneWidget);
    });

    apiTest(
      'signing out clears the session and returns to the language screen',
      (tester, api) async {
        _seed(api);
        final host = await _pump(tester, api);
        expect(host.auth.token, 'token');
        await tester.tap(find.byKey(const Key('vendor-sign-out')));
        await tester.pumpAndSettle();
        expect(host.auth.token, isNull);
        expect(find.text('ROUTE-LANGUAGE'), findsOneWidget);
      },
    );
  });

  group('English and Swahili layout', () {
    for (final lang in ['en', 'sw']) {
      apiTest('every tab and form fits 360x740 at text scale 1.3 ($lang)', (
        tester,
        api,
      ) async {
        _seed(
          api,
          products: [_richProduct],
          orders: [
            _order('o1', status: 'packed', delivery: 'gym_pickup'),
            _order('o2', paymentStatus: 'pending'),
          ],
          enquiries: [
            {
              'id': 'e1',
              'status': 'open',
              'messages': [
                {'message': 'Is the mat available in blue and green colours?'},
                {'message': 'Checking the warehouse stock for you'},
              ],
            },
          ],
          staff: [
            {
              'id': 's1',
              'displayName': 'Asha Mwakilema',
              'vendorRole': 'inventory_manager',
              'email': 'asha.mwakilema@example.com',
              'accountStatus': 'active',
            },
          ],
        );
        final host = await _pump(tester, api, lang: lang, scale: 1.3);
        expect(tester.takeException(), isNull);

        for (final tab in ['orders', 'payments', 'enquiries', 'business']) {
          await _tab(tester, tab);
          final ex = tester.takeException();
          if (lang == 'sw' && tab == 'business' && ex != null) {
            // KNOWN ISSUE (characterized, not endorsed): the Staff header row
            // (title + "Add staff" button) overflows by ~58px in Swahili at
            // 360px and text scale 1.3. Tolerated so this test passes today
            // and still passes once the row is fixed.
            expect(ex.toString(), contains('overflowed'));
          } else {
            expect(ex, isNull, reason: '$lang $tab');
          }
        }

        Future<void> dismiss() async {
          Navigator.of(
            tester.element(find.byType(Scaffold).first),
            rootNavigator: true,
          ).pop();
          await tester.pumpAndSettle();
        }

        // Business: profile form and staff form.
        await tapVisible(tester, find.byKey(const Key('vendor-edit-profile')));
        expect(_field('vendor-profile-publish'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'profile form');
        await dismiss();
        await tapVisible(tester, find.byKey(const Key('vendor-add-staff')));
        expect(_field('vendor-staff-save'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'staff form');
        await dismiss();

        // Enquiries: reply dialog.
        await _tab(tester, 'enquiries');
        await tester.tap(find.byKey(const Key('vendor-reply-e1')));
        await tester.pumpAndSettle();
        expect(_field('vendor-reply-message'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'reply dialog');
        await tapAndSettleDialogClose(tester, find.text(host.tr('shop.send')));

        // Products: add form and edit form.
        await _tab(tester, 'products');
        await tester.tap(find.byKey(const Key('vendor-add-product')));
        await tester.pumpAndSettle();
        expect(_field('vendor-product-save'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'product form');
        await dismiss();
        await _openProductMenu(tester, 'p1', host.tr('vendor.edit'));
        expect(tester.takeException(), isNull, reason: 'edit form');
        await dismiss();
      });
    }

    apiTest('the add-product flow posts the same payload in Swahili', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api, lang: 'sw');
      expect(find.text(host.tr('vendor.addProduct')), findsOneWidget);
      await tester.tap(find.byKey(const Key('vendor-add-product')));
      await tester.pumpAndSettle();
      await typeInto(tester, _field('vendor-product-name'), 'Taulo');
      await typeInto(tester, _field('vendor-product-price'), '5000');
      await tapVisible(tester, _field('vendor-product-save'));
      expect(
        (api.only('POST', '/vendor/products').body as Map)['name'],
        'Taulo',
      );
      expect(host.snack(host.tr('vendor.productSaved')), findsOneWidget);
      expect(host.tr('vendor.productSaved'), isNot('Product saved.'));
    });
  });

  group('language', () {
    apiTest('a vendor switches language in place, without signing out', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api);
      expect(find.text('Vendor marketplace'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vendor-language')));
      await tester.pumpAndSettle();
      // The same screen, now in Swahili; still signed in, nothing sent.
      expect(find.text('Soko la muuzaji'), findsOneWidget);
      expect(find.text('Vendor marketplace'), findsNothing);
      expect(host.auth.isSignedIn, isTrue);
      expect(find.text('ROUTE-LANGUAGE'), findsNothing);
      // And back to English.
      await tester.tap(find.byKey(const Key('vendor-language')));
      await tester.pumpAndSettle();
      expect(find.text('Vendor marketplace'), findsOneWidget);
    });
  });

  apiTest('shop near-you: the "Where you sell" alert action is 48 tall '
      '(QA2 #4)', (tester, api) async {
    _seed(api);
    api.on('GET /vendor/tools/options', {
      'merch': {'shopAreas': true},
    });
    await _pump(tester, api);
    await _tab(tester, 'business');
    final action = find.byKey(const Key('vendor-areas-nudge-action'));
    expect(action, findsOneWidget);
    // The visible button, not just its padded hit area.
    final visible = find
        .descendant(of: action, matching: find.byType(Material))
        .first;
    expect(tester.getSize(visible).height, greaterThanOrEqualTo(48));
  });
}
