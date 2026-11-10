// Owner request 2026-11-10: the vendor's "Banners & flash sales" page
// (`/vendor/merch`) always has a back arrow. It pops when it can and
// otherwise goes to the vendor home (the page is often opened with
// `context.go` after saving, by a web reload or by a notification link).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/vendor/merch/vendor_banners_page.dart';
import 'package:fitflexmobile/screens/vendor/merch/vendor_merch_page.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';

const _both = {
  'stockLedger': false,
  'merch': {'banners': true, 'flashSales': true},
};
const _bannersOnly = {
  'stockLedger': false,
  'merch': {'banners': true},
};
const _salesOnly = {
  'stockLedger': false,
  'merch': {'flashSales': true},
};
const _none = {'stockLedger': false, 'merch': <String, dynamic>{}};

Finder _key(String k) => find.byKey(Key(k));
final _back = _key('merch-back');

void _seed(RecordingApi api, Map<String, dynamic> tools) {
  api.on('GET /vendor/tools/options', tools);
  api.on('GET /vendor/flash-sales', {
    'items': [],
    'total': 0,
    'nextCursor': null,
    'vendor': {'canPropose': true, 'reason': null},
    'proposalExpiryDays': 14,
    'openProposals': {'open': 0, 'max': 10},
    'rules': {
      'minDiscountPct': 5,
      'minLengthMs': 3600000,
      'maxLengthMs': 604800000,
      'minLeadMs': 3600000,
      'priceRaiseLookbackDays': 14,
    },
  });
  api.on('GET /vendor/products', [stockProduct('p1', 'Foam Roller')]);
  api.on('GET /vendor/shop-banners', {
    'items': [],
    'total': 0,
    'nextCursor': null,
    'vendor': {'canPropose': true, 'reason': null},
  });
  api.on('GET /vendor/profile', {'businessName': 'Duka la Asha'});
}

/// A stand-in vendor home that opens Promotions the way the real one does
/// (`context.push`).
final _routes = <RouteBase>[
  GoRoute(
    path: AppRoutes.vendorHome,
    builder: (context, _) => Scaffold(
      body: Column(
        children: [
          const Text('ROUTE-VENDOR-HOME'),
          TextButton(
            key: const Key('open-merch'),
            onPressed: () => context.push(AppRoutes.vendorMerch),
            child: const Text('Promotions'),
          ),
        ],
      ),
    ),
  ),
  GoRoute(
    path: AppRoutes.vendorMerch,
    builder: (_, state) => VendorMerchPage(
      tab: state.uri.queryParameters['tab'],
      item: state.uri.queryParameters['item'],
    ),
  ),
];

Future<PageHost> _pumpAt(
  WidgetTester tester,
  RecordingApi api,
  String location, {
  String lang = 'en',
}) => pumpPage(
  tester,
  api,
  const SizedBox(),
  user: vendorUser,
  lang: lang,
  size: const Size(400, 900),
  initialLocation: location,
  extraRoutes: _routes,
);

void main() {
  for (final (name, tools) in [
    ('flash sales on', _both),
    ('flash sales off', _bannersOnly),
    ('flash sales only', _salesOnly),
  ]) {
    group(name, () {
      apiTest('pushed from vendor home: back pops to it', (tester, api) async {
        _seed(api, tools);
        await _pumpAt(tester, api, AppRoutes.vendorHome);
        await tester.tap(_key('open-merch'));
        await tester.pumpAndSettle();
        expect(find.byType(VendorMerchPage), findsOneWidget);
        expect(_back, findsOneWidget);

        await tester.tap(_back);
        await tester.pumpAndSettle();
        expect(find.byType(VendorMerchPage), findsNothing);
        expect(find.text('ROUTE-VENDOR-HOME'), findsOneWidget);
      });

      apiTest('opened with nothing to pop: back goes to vendor home', (
        tester,
        api,
      ) async {
        _seed(api, tools);
        await _pumpAt(tester, api, AppRoutes.vendorMerch);
        expect(find.byType(VendorMerchPage), findsOneWidget);
        expect(_back, findsOneWidget);

        await tester.tap(_back);
        await tester.pumpAndSettle();
        expect(find.byType(VendorMerchPage), findsNothing);
        expect(find.text('ROUTE-VENDOR-HOME'), findsOneWidget);
      });
    });
  }

  apiTest('flash sales off: the standalone banners page has the arrow', (
    tester,
    api,
  ) async {
    _seed(api, _bannersOnly);
    await _pumpAt(tester, api, '${AppRoutes.vendorMerch}?item=b1');
    expect(find.byType(VendorBannersPage), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(_back, findsOneWidget);
  });

  apiTest('both tools: embedded Banners adds no second app bar or arrow', (
    tester,
    api,
  ) async {
    _seed(api, _both);
    await _pumpAt(tester, api, '${AppRoutes.vendorMerch}?tab=banners');
    expect(_key('merch-tab-banners'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(_back, findsOneWidget);
  });

  apiTest('tool off ("isn\'t available yet"): the arrow is still there', (
    tester,
    api,
  ) async {
    _seed(api, _none);
    await _pumpAt(tester, api, AppRoutes.vendorMerch);
    expect(_key('merch-unavailable'), findsOneWidget);
    expect(_back, findsOneWidget);
    await tester.tap(_back);
    await tester.pumpAndSettle();
    expect(find.text('ROUTE-VENDOR-HOME'), findsOneWidget);
  });

  apiTest('suspended business: the arrow is still there', (tester, api) async {
    _seed(api, _both);
    api.fail('GET /vendor/tools/options', 403, {'error': 'account_suspended'});
    await _pumpAt(tester, api, AppRoutes.vendorMerch);
    expect(_key('merch-cannot-propose'), findsOneWidget);
    expect(_back, findsOneWidget);
    await tester.tap(_back);
    await tester.pumpAndSettle();
    expect(find.text('ROUTE-VENDOR-HOME'), findsOneWidget);
  });

  apiTest('staff without products permission: the arrow is still there', (
    tester,
    api,
  ) async {
    _seed(api, _bannersOnly);
    await pumpPage(
      tester,
      api,
      const SizedBox(),
      user: const {
        'id': 's1',
        'userType': 'vendor_staff',
        'vendorPermissions': <String>[],
      },
      size: const Size(400, 900),
      initialLocation: AppRoutes.vendorMerch,
      extraRoutes: _routes,
    );
    expect(_key('merch-restricted'), findsOneWidget);
    expect(_back, findsOneWidget);
  });

  apiTest('the arrow is labelled in Swahili', (tester, api) async {
    _seed(api, _both);
    final host = await _pumpAt(tester, api, AppRoutes.vendorMerch, lang: 'sw');
    expect(host.tr('a11y.back'), 'Rudi');
    expect(find.byTooltip('Rudi'), findsOneWidget);
  });
}
