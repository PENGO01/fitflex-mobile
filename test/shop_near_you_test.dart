// Shop home Phase 2 S3 ("Popular near you"): the on-device area mapping,
// the invite card and the location rationale sheet, the location line, the
// "Delivers to your area" badge, the hidden distance filter, and the vendor
// "Where you sell" pickers.
//
// Contract: fitflex-functions docs/shop-near-you-api.md (GET /shop/areas,
// GET /shop/home?areaId= → nearYou / popular_near_you / reason codes /
// deliversToViewerArea, /shop/preferences `uses` 'location', vendor profile
// cityId / regionId / deliveryAreaIds, /vendor/tools/options
// merch.shopAreas). Mocked at the HTTP level (test/support/recording_api);
// the OS location calls are a fake ShopLocator.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_options.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/rest_log.dart' show redactHeaders;
import 'package:fitflexmobile/shared/shop_home.dart';
import 'package:fitflexmobile/shared/shop_near_you.dart';
import 'package:fitflexmobile/shared/widgets/ff_area_picker.dart';
import 'package:fitflexmobile/shared/widgets/shop_browse_page.dart';
import 'package:fitflexmobile/shared/widgets/shop_home/shop_focus_ring.dart';
import 'package:fitflexmobile/shared/widgets/shop_home/shop_near_you_ui.dart';
import 'package:fitflexmobile/shared/widgets/shop_home/shop_personalisation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_api.dart';

// ── fixtures ────────────────────────────────────────────────────────────

/// Seeded areas (the moderation-promotion migration's shape, plus districts).
final _areasJson = [
  {
    'id': 'tz',
    'level': 'country',
    'name': 'Tanzania',
    'parentId': null,
    'lat': -6.369,
    'lng': 34.889,
    'radiusKm': null,
  },
  {
    'id': 'tz-dar',
    'level': 'region',
    'name': 'Dar es Salaam',
    'parentId': 'tz',
    'lat': -6.792,
    'lng': 39.208,
    'radiusKm': 40,
  },
  {
    'id': 'tz-dar-city',
    'level': 'city',
    'name': 'Dar es Salaam',
    'parentId': 'tz-dar',
    'lat': -6.792,
    'lng': 39.208,
    'radiusKm': 25,
  },
  {
    'id': 'tz-dar-kinondoni',
    'level': 'district',
    'name': 'Kinondoni',
    'parentId': 'tz-dar-city',
    'lat': -6.74,
    'lng': 39.24,
    'radiusKm': 5,
  },
  {
    'id': 'tz-arusha',
    'level': 'region',
    'name': 'Arusha',
    'parentId': 'tz',
    'lat': -3.387,
    'lng': 36.683,
    'radiusKm': 60,
  },
  {
    'id': 'tz-arusha-city',
    'level': 'city',
    'name': 'Arusha',
    'parentId': 'tz-arusha',
    'lat': -3.387,
    'lng': 36.683,
    'radiusKm': 15,
  },
];

final _areas = ShopArea.listFromJson({'areas': _areasJson});

/// A real 1x1 PNG (vendor logo / banner).
const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

// Points used below. Kinondoni centre is inside the district (and the city
// and region around it); Ubungo-ish is inside the city but not the district;
// the Dar outskirts are inside the region only; Mbeya is in nothing.
const _kinondoni = (lat: -6.741, lng: 39.241);
const _darCity = (lat: -6.82, lng: 39.27);
const _darOutskirts = (lat: -6.55, lng: 39.0);
const _mbeya = (lat: -8.9, lng: 33.45);

Map<String, dynamic> _p(String id, String name, {bool delivers = false}) => {
  'id': id,
  'vendorId': 'v1',
  'name': name,
  'category': 'equipment',
  'priceTzs': 10000,
  'stock': 10,
  'rating': 0,
  'reviewCount': 0,
  'soldCount': 0,
  'deliveryAvailable': true,
  'distanceKm': 3,
  if (delivers) 'deliversToViewerArea': true,
};

Map<String, dynamic> _products({bool delivers = false}) => {
  for (final p in [
    _p('p1', 'Whey Protein', delivers: delivers),
    _p('p2', 'Yoga Mat', delivers: delivers),
    _p('p3', 'Kettlebell'),
    _p('p4', 'Running Shoes'),
  ])
    p['id'] as String: p,
};

/// GET /shop/home. [nearYou] null = a backend with SHOP_NEAR_YOU off (no
/// key at all). [areaSection] adds the popular_near_you rail.
Map<String, dynamic> _home({
  Map<String, dynamic>? nearYou,
  bool areaSection = false,
  bool personalised = true,
  bool delivers = false,
}) => {
  'serverNow': '2026-10-22T08:00:00Z',
  'mode': 'member',
  'personalised': personalised,
  'signalsUsed': <String>[],
  'personalisation': {'available': true, 'enabled': personalised},
  'nearYou': ?nearYou,
  'categories': <dynamic>[],
  'sections': [
    {
      'key': 'recommended',
      'title': {'en': 'Recommended for you', 'sw': 'Zilizopendekezwa kwako'},
      'reasonCodes': ['popular_with_role'],
      'viewAll': {'query': <String, String>{}},
      'productIds': ['p3', 'p4'],
    },
    if (areaSection)
      {
        'key': 'popular_near_you',
        'title': {'en': 'Popular near you', 'sw': 'Maarufu karibu nawe'},
        'reasonCodes': ['popular_in_area', 'delivers_to_area'],
        // functions#248: {en, sw} (was a string).
        'reasonParams': {
          'areaName': {'en': 'Dar es Salaam', 'sw': 'Dar es Salaam'},
        },
        'viewAll': {'path': '/shop/products', 'query': <String, String>{}},
        'hasMore': false,
        'productIds': ['p1', 'p2'],
      },
    {
      'key': 'essentials',
      'title': {'en': 'Essentials', 'sw': 'Muhimu'},
      'reasonCodes': ['generic'],
      'viewAll': {'query': <String, String>{}},
      'productIds': ['p4'],
    },
  ],
  'products': _products(delivers: delivers),
};

const _on = {'available': true};
const _off = {'available': false};

void _seed(RecordingApi api, Map<String, dynamic> home, {bool areas = true}) {
  api.on('GET /shop/products', _products().values.toList());
  api.on('GET /me/shop-orders', <dynamic>[]);
  api.on('GET /gyms', <dynamic>[]);
  api.on('GET /shop/home', home);
  if (areas) api.on('GET /shop/areas', {'areas': _areasJson});
}

/// Answers /shop/home with the rail only when an areaId was sent (as the
/// server does).
void _seedAreaAware(RecordingApi api) {
  _seed(api, _home(nearYou: _on));
  api.onCall('GET /shop/home', (r) {
    final areaId = r.headers['x-ff-area'];
    return _home(
      nearYou: areaId == null
          ? _on
          : {
              'available': true,
              'areaId': areaId,
              'areaName': {'en': 'Dar es Salaam', 'sw': 'Dar es Salaam'},
            },
      areaSection: areaId != null,
      delivers: areaId != null,
    );
  });
}

const _member = {'id': 'm1', 'userType': 'member', 'displayName': 'Amina'};

Finder _key(String k) => find.byKey(Key(k));

/// Stands in for the OS. Records every call, in order.
class FakeLocator implements ShopLocator {
  FakeLocator({
    this.access = ShopLocationAccess.denied,
    this.afterRequest = ShopLocationAccess.granted,
    this.fix,
    this.services = true,
    this.web = false,
  });

  ShopLocationAccess access;
  ShopLocationAccess afterRequest;
  ({double lat, double lng})? fix;
  bool services;
  bool web;
  final List<String> calls = [];

  int count(String name) => calls.where((c) => c == name).length;

  @override
  Future<bool> servicesEnabled() async {
    calls.add('services');
    return services;
  }

  @override
  Future<ShopLocationAccess> check() async {
    calls.add('check');
    return access;
  }

  @override
  Future<ShopLocationAccess> request() async {
    calls.add('request');
    access = afterRequest;
    return access;
  }

  @override
  Future<({double lat, double lng})?> position({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    calls.add('position');
    return fix;
  }

  @override
  Future<void> openAppSettings() async => calls.add('settings');

  @override
  bool get canOpenSettings => !web;
}

Future<PageHost> _pumpShop(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
  double scale = 1,
  Size size = const Size(420, 1400),
}) => pumpPage(
  tester,
  api,
  const ShopBrowseBody(mode: ShopHomeMode.member),
  user: _member,
  lang: lang,
  textScale: scale,
  size: size,
  keepRequests: true,
);

/// Every request the app sent, as text (path, query and body).
String _allTraffic(RecordingApi api) => api.requests
    .map((r) => '${r.method} ${r.path}?${r.query} ${jsonEncode(r.body)}')
    .join('\n');

/// No coordinate-looking value left the device.
void _expectNoCoordinates(RecordingApi api) {
  final traffic = _allTraffic(api).toLowerCase();
  for (final word in ['lat', 'lng', 'lon', 'latitude', 'longitude', 'coords']) {
    expect(
      RegExp('\\b$word\\b|$word=|"$word"').hasMatch(traffic),
      isFalse,
      reason: '"$word" in:\n$traffic',
    );
  }
  for (final digits in ['6.74', '39.24', '6.82', '39.27', '8.9', '33.45']) {
    expect(traffic.contains(digits), isFalse, reason: '$digits in:\n$traffic');
  }
}

/// The area sent with each GET /shop/home (the `X-FF-Area` header), and
/// never in the URL.
List<String?> _sentAreaIds(RecordingApi api) => [
  for (final r in api.where('GET', '/shop/home'))
    (() {
      expect(r.query, isNot(contains('areaId')), reason: 'area in the URL');
      return r.headers['x-ff-area'];
    })(),
];

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    debugShopHomeV2Override = true;
    ShopEvents.reset();
    ShopNearYouStore.reset();
  });
  tearDown(() {
    debugShopHomeV2Override = null;
    debugShopLocatorOverride = null;
  });

  // ── pure mapping ──────────────────────────────────────────────────────

  group('areaFor (on the phone)', () {
    test('a point in a district gets the district (most specific)', () {
      expect(
        areaFor(_kinondoni.lat, _kinondoni.lng, _areas)?.id,
        'tz-dar-kinondoni',
      );
    });

    test('outside every district: the city around it', () {
      expect(areaFor(_darCity.lat, _darCity.lng, _areas)?.id, 'tz-dar-city');
    });

    test('outside the city: the region', () {
      expect(
        areaFor(_darOutskirts.lat, _darOutskirts.lng, _areas)?.id,
        'tz-dar',
      );
    });

    test('in nothing: null, and the country (no circle) never matches', () {
      expect(areaFor(_mbeya.lat, _mbeya.lng, _areas), isNull);
      // Exactly on the country centre: still nothing.
      expect(areaFor(-6.369, 34.889, _areas), isNull);
    });

    test('containment is by radius: just outside a circle does not count', () {
      // Arusha city: radius 15 km. 0.2° of latitude ≈ 22 km.
      expect(areaFor(-3.387, 36.683, _areas)?.id, 'tz-arusha-city');
      expect(areaFor(-3.587, 36.683, _areas)?.id, 'tz-arusha');
    });

    test('two at the same level: the smaller circle wins', () {
      final overlapping = [
        const ShopArea(
          id: 'big',
          name: 'Big',
          level: 'city',
          lat: 0,
          lng: 0,
          radiusKm: 50,
        ),
        const ShopArea(
          id: 'small',
          name: 'Small',
          level: 'city',
          lat: 0.01,
          lng: 0.01,
          radiusKm: 5,
        ),
      ];
      expect(areaFor(0.005, 0.005, overlapping)?.id, 'small');
    });

    test('areas without a centre or a radius, and bad input, are skipped', () {
      final odd = ShopArea.listFromJson({
        'areas': [
          {'id': 'x', 'level': 'city', 'name': 'X', 'lat': null, 'lng': 1},
          {'id': 'y', 'level': 'city', 'name': 'Y', 'lat': 0, 'lng': 0},
          {'id': 'z', 'level': 'planet', 'name': 'Z', 'lat': 0, 'lng': 0},
          {'level': 'city', 'name': 'no id'},
        ],
      });
      expect(odd.map((a) => a.id), ['x', 'y']);
      expect(areaFor(0, 0, odd), isNull);
      expect(areaFor(double.nan, 0, _areas), isNull);
    });

    test('haversine agrees with a known distance (Dar → Arusha ≈ 485 km)', () {
      final d = haversineKm(-6.792, 39.208, -3.387, 36.683);
      expect(d, closeTo(470, 30));
    });
  });

  // ── the request ───────────────────────────────────────────────────────

  group('ApiClient', () {
    test('shopHome sends the area only in X-FF-Area: not in the URL, no '
        'latitude/longitude anywhere', () async {
      final seen = <Uri>[];
      final headers = <Map<String, String>>[];
      await http.runWithClient(
        () async {
          final api = ApiClient(baseUrl: 'http://fixtures.local');
          await api.shopHome(mode: 'member', areaId: 'tz-dar-city');
          await api.shopHome(mode: 'member');
          await api.shopAreas();
        },
        () => MockClient((req) async {
          seen.add(req.url);
          headers.add({
            for (final e in req.headers.entries) e.key.toLowerCase(): e.value,
          });
          return http.Response('{}', 200);
        }),
      );
      expect(headers[0]['x-ff-area'], 'tz-dar-city');
      expect(seen[0].query, isNot(contains('tz-dar-city')));
      expect(seen[0].queryParameters.containsKey('areaId'), isFalse);
      expect(headers[1].containsKey('x-ff-area'), isFalse);
      expect(
        redactHeaders({'X-FF-Area': 'tz-dar-city'})['X-FF-Area'],
        '<redacted>',
      );
      expect(seen[2].path, '/shop/areas');
      for (final uri in seen) {
        for (final k in uri.queryParameters.keys) {
          expect(
            k.toLowerCase(),
            isNot(anyOf(contains('lat'), contains('lng'), contains('lon'))),
          );
        }
      }
    });
  });

  // ── invite card, rationale, outcomes ──────────────────────────────────

  group('invite card and rationale sheet', () {
    apiTest('flag off (no nearYou key): no card, no location, filter kept', (
      tester,
      api,
    ) async {
      final loc = debugShopLocatorOverride = FakeLocator();
      _seed(api, _home(), areas: false);
      api.fail('GET /shop/areas', 404, {'error': 'feature_disabled'});
      await _pumpShop(tester, api);
      expect(_key('shop-home-section-recommended'), findsOneWidget);
      expect(_key('shop-near-you-invite'), findsNothing);
      expect(loc.calls, isEmpty);
      expect(_sentAreaIds(api), everyElement(isNull));
    });

    apiTest('not available (personalisation off / under 18): no card, no '
        'location read, even if turned on before', (tester, api) async {
      final loc = debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
        fix: _kinondoni,
      );
      await ShopNearYouStore.save(
        'm1',
        const ShopNearYouState(
          choice: ShopNearYouChoice.on,
          areaId: 'tz-dar-city',
        ),
      );
      _seed(api, _home(nearYou: _off));
      await _pumpShop(tester, api);
      expect(_key('shop-near-you-invite'), findsNothing);
      expect(loc.calls, isEmpty);
      // Nothing sent, and the kept area is forgotten (L1).
      expect(_sentAreaIds(api), everyElement(isNull));
      expect(ShopNearYouStore.peek('m1')!.choice, ShopNearYouChoice.notAsked);
      expect(ShopNearYouStore.peek('m1')!.areaId, isNull);
    });

    apiTest('switch off on the server (personalisation.enabled false): the '
        'kept area is forgotten, nothing sent', (tester, api) async {
      final loc = debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
        fix: _kinondoni,
      );
      await ShopNearYouStore.save(
        'm1',
        const ShopNearYouState(
          choice: ShopNearYouChoice.on,
          areaId: 'tz-dar-city',
        ),
      );
      _seed(api, _home(personalised: false));
      await _pumpShop(tester, api);
      expect(_sentAreaIds(api), everyElement(isNull));
      expect(ShopNearYouStore.peek('m1')!.areaId, isNull);
      expect(loc.calls, isEmpty);
    });

    apiTest('the card sits after Recommended and before Essentials', (
      tester,
      api,
    ) async {
      debugShopLocatorOverride = FakeLocator();
      _seed(api, _home(nearYou: _on));
      final host = await _pumpShop(tester, api);
      expect(_key('shop-near-you-invite'), findsOneWidget);
      expect(find.text(host.tr('shop.near.inviteTitle')), findsOneWidget);
      final rec = tester.getTopLeft(_key('shop-home-section-recommended')).dy;
      final card = tester.getTopLeft(_key('shop-near-you-invite')).dy;
      final ess = tester.getTopLeft(_key('shop-home-section-essentials')).dy;
      expect(rec < card && card < ess, isTrue);
      expect(
        tester.getSize(_key('shop-near-you-use')).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(_key('shop-near-you-not-now')).height,
        greaterThanOrEqualTo(48),
      );
    });

    apiTest('rationale first, then the OS prompt, then only areaId is sent', (
      tester,
      api,
    ) async {
      final loc = debugShopLocatorOverride = FakeLocator(fix: _kinondoni);
      _seedAreaAware(api);
      final host = await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-near-you-use'));

      // The sheet is up and the OS has not been asked.
      expect(_key('shop-location-sheet'), findsOneWidget);
      expect(find.text(host.tr('shop.near.sheetTitle')), findsOneWidget);
      for (final k in [
        'shop.near.point1',
        'shop.near.point2',
        'shop.near.point3',
      ]) {
        expect(find.text(host.tr(k)), findsOneWidget, reason: k);
      }
      expect(_key('shop-location-already'), findsNothing);
      expect(loc.count('request'), 0);
      expect(loc.count('position'), 0);

      await tapVisible(tester, _key('shop-location-use'));
      expect(loc.count('request'), 1);
      expect(loc.count('position'), 1);
      // Rationale (check only) came before the prompt.
      expect(
        loc.calls.indexOf('check'),
        lessThan(loc.calls.indexOf('request')),
      );

      expect(_sentAreaIds(api).last, 'tz-dar-kinondoni');
      expect(_key('shop-home-section-popular_near_you'), findsOneWidget);
      expect(_key('shop-near-you-invite'), findsNothing);
      _expectNoCoordinates(api);

      // Kept for this account: area id and name, never a position.
      final state = ShopNearYouStore.peek('m1')!;
      expect(state.choice, ShopNearYouChoice.on);
      expect(state.areaId, 'tz-dar-kinondoni');
      expect(jsonEncode(state.toJson()), isNot(contains('6.7')));
    });

    apiTest('already granted for gyms: the sheet still shows, says so, and '
        'no OS prompt follows', (tester, api) async {
      final loc = debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
        fix: _darCity,
      );
      _seedAreaAware(api);
      final host = await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-near-you-use'));
      expect(_key('shop-location-sheet'), findsOneWidget);
      expect(find.text(host.tr('shop.near.alreadyAllowed')), findsOneWidget);
      expect(loc.count('position'), 0);
      await tapVisible(tester, _key('shop-location-use'));
      expect(loc.count('request'), 0);
      expect(_sentAreaIds(api).last, 'tz-dar-city');
    });

    apiTest('denied: card and rail gone, a message, never asked again', (
      tester,
      api,
    ) async {
      final loc = debugShopLocatorOverride = FakeLocator(
        afterRequest: ShopLocationAccess.denied,
        fix: _kinondoni,
      );
      _seedAreaAware(api);
      final host = await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-near-you-use'));
      await tapVisible(tester, _key('shop-location-use'));
      expect(host.snack(host.tr('shop.near.denied')), findsOneWidget);
      expect(_key('shop-near-you-invite'), findsNothing);
      expect(_key('shop-home-section-popular_near_you'), findsNothing);
      expect(loc.count('position'), 0);
      expect(ShopNearYouStore.peek('m1')!.choice, ShopNearYouChoice.off);

      // Reopening the shop: no card, no prompt, no area.
      await tester.pumpWidget(const SizedBox());
      loc.calls.clear();
      await _pumpShop(tester, api);
      expect(_key('shop-near-you-invite'), findsNothing);
      expect(loc.calls, isEmpty);
      expect(_sentAreaIds(api), everyElement(isNull));
    });

    apiTest('blocked for good on a phone: Open settings action', (
      tester,
      api,
    ) async {
      final loc = debugShopLocatorOverride = FakeLocator(
        afterRequest: ShopLocationAccess.deniedForever,
      );
      _seedAreaAware(api);
      final host = await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-near-you-use'));
      await tapVisible(tester, _key('shop-location-use'));
      expect(buttonLabelled(host.tr('shop.near.openSettings')), findsOneWidget);
      await tester.tap(buttonLabelled(host.tr('shop.near.openSettings')));
      await tester.pumpAndSettle();
      expect(loc.count('settings'), 1);
    });

    apiTest('blocked in the browser: the browser message, no settings action', (
      tester,
      api,
    ) async {
      debugShopLocatorOverride = FakeLocator(
        afterRequest: ShopLocationAccess.deniedForever,
        web: true,
      );
      _seedAreaAware(api);
      final host = await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-near-you-use'));
      await tapVisible(tester, _key('shop-location-use'));
      expect(
        find.textContaining(host.tr('shop.near.browserBlocked')),
        findsOneWidget,
      );
      expect(buttonLabelled(host.tr('shop.near.openSettings')), findsNothing);
    });

    apiTest('no area matches: a message, no areaId sent', (tester, api) async {
      debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
        fix: _mbeya,
      );
      _seedAreaAware(api);
      final host = await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-near-you-use'));
      await tapVisible(tester, _key('shop-location-use'));
      expect(host.snack(host.tr('shop.near.noArea')), findsOneWidget);
      expect(_sentAreaIds(api), everyElement(isNull));
      expect(_key('shop-home-section-popular_near_you'), findsNothing);
      expect(_key('shop-near-you-invite'), findsNothing);
    });

    apiTest('no fix in time: "Couldn\'t find your area", stays on', (
      tester,
      api,
    ) async {
      debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
      );
      _seedAreaAware(api);
      final host = await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-near-you-use'));
      await tapVisible(tester, _key('shop-location-use'));
      expect(host.snack(host.tr('shop.near.failed')), findsOneWidget);
      expect(ShopNearYouStore.peek('m1')!.choice, ShopNearYouChoice.on);
    });

    apiTest('location off on the phone: says so; the card stays', (
      tester,
      api,
    ) async {
      final loc = debugShopLocatorOverride = FakeLocator(services: false);
      _seedAreaAware(api);
      final host = await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-near-you-use'));
      await tapVisible(tester, _key('shop-location-use'));
      expect(host.snack(host.tr('shop.near.servicesOff')), findsOneWidget);
      expect(loc.count('request'), 0);
      expect(_key('shop-near-you-invite'), findsOneWidget);
    });

    apiTest('"Not now" on the card: gone, nothing read, off on this device', (
      tester,
      api,
    ) async {
      final loc = debugShopLocatorOverride = FakeLocator();
      _seedAreaAware(api);
      await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-near-you-not-now'));
      expect(_key('shop-near-you-invite'), findsNothing);
      expect(loc.calls, isEmpty);
      expect(ShopNearYouStore.peek('m1')!.choice, ShopNearYouChoice.off);
    });

    apiTest('"Not now" on the sheet: same, and no OS prompt', (
      tester,
      api,
    ) async {
      final loc = debugShopLocatorOverride = FakeLocator();
      _seedAreaAware(api);
      await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-near-you-use'));
      await tapVisible(tester, _key('shop-location-not-now'));
      expect(_key('shop-near-you-invite'), findsNothing);
      expect(loc.count('request'), 0);
      expect(loc.count('position'), 0);
    });

    testWidgets('offline: the button is disabled with "Needs internet"', (
      tester,
    ) async {
      final l = FFLocale();
      await tester.pumpWidget(
        FFLocaleScope(
          notifier: l,
          child: MaterialApp(
            home: Scaffold(
              body: ShopNearYouInviteCard(
                offline: true,
                onUse: () {},
                onNotNow: () {},
              ),
            ),
          ),
        ),
      );
      expect(isEnabled(tester, _key('shop-near-you-use')), isFalse);
      expect(find.text(l.t('shop.near.offline')), findsOneWidget);
      expect(isEnabled(tester, _key('shop-near-you-not-now')), isTrue);
    });
  });

  // ── once a session, refresh, switch off ──────────────────────────────

  group('later sessions', () {
    apiTest('turned on before: the kept area is sent once the server says '
        'near-you is available, and the position read once, without asking', (
      tester,
      api,
    ) async {
      final loc = debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
        fix: _darCity,
      );
      await ShopNearYouStore.save(
        'm1',
        const ShopNearYouState(
          choice: ShopNearYouChoice.on,
          areaId: 'tz-dar-kinondoni',
          areaName: 'Kinondoni',
        ),
      );
      _seedAreaAware(api);
      await _pumpShop(tester, api);
      // L1: the first answer this session has not said "available" yet,
      // so the first request carries no area; then the kept one; then,
      // after the position moved, the new one.
      expect(_sentAreaIds(api), [null, 'tz-dar-kinondoni', 'tz-dar-city']);
      expect(loc.count('position'), 1);
      expect(loc.count('request'), 0);
      expect(_key('shop-location-sheet'), findsNothing);

      // A second shop visit in the same session reads nothing.
      await tester.pumpWidget(const SizedBox());
      await _pumpShop(tester, api);
      expect(loc.count('position'), 1);
      _expectNoCoordinates(api);
    });

    apiTest('permission taken back in the OS: turned off quietly', (
      tester,
      api,
    ) async {
      debugShopLocatorOverride = FakeLocator(fix: _darCity);
      await ShopNearYouStore.save(
        'm1',
        const ShopNearYouState(
          choice: ShopNearYouChoice.on,
          areaId: 'tz-dar-city',
        ),
      );
      _seedAreaAware(api);
      await _pumpShop(tester, api);
      expect(ShopNearYouStore.peek('m1')!.choice, ShopNearYouChoice.off);
      expect(_sentAreaIds(api).last, isNull);
      expect(find.byType(SnackBar), findsNothing);
    });

    apiTest(
      '"Personalised shop" off forgets the area; the next home has none',
      (tester, api) async {
        debugShopLocatorOverride = FakeLocator(
          access: ShopLocationAccess.granted,
          fix: _darCity,
        );
        await ShopNearYouStore.save(
          'm1',
          const ShopNearYouState(
            choice: ShopNearYouChoice.on,
            areaId: 'tz-dar-city',
          ),
        );
        _seedAreaAware(api);
        api.on('PUT /shop/preferences', {
          'personalised': false,
          'available': true,
        });
        final host = await _pumpShop(tester, api);
        await tapVisible(tester, _key('shop-home-why-popular_near_you'));
        // The location line with the area, and its actions.
        expect(
          find.text(
            host.tr('shop.why.nearOn').replaceAll('{area}', 'Dar es Salaam'),
          ),
          findsWidgets,
        );
        expect(_key('shop-near-you-turn-off'), findsOneWidget);
        expect(
          find.text(host.tr('shop.why.switchHintMemberArea')),
          findsOneWidget,
        );
        // Why reasons in the app's words.
        expect(
          find.text(
            host
                .tr('shop.why.popularInArea')
                .replaceAll('{areaName}', 'Dar es Salaam'),
          ),
          findsOneWidget,
        );
        expect(find.text(host.tr('shop.why.deliversToArea')), findsOneWidget);

        api.clear();
        await tester.tap(_key('shop-why-personalised'));
        await tester.pumpAndSettle();
        expect(ShopNearYouStore.peek('m1')!.choice, ShopNearYouChoice.notAsked);
        expect(ShopNearYouStore.peek('m1')!.areaId, isNull);
        expect(_sentAreaIds(api), isNotEmpty);
        expect(_sentAreaIds(api), everyElement(isNull));
      },
    );

    apiTest('Turn off in the Why sheet: no area sent afterwards', (
      tester,
      api,
    ) async {
      debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
        fix: _darCity,
      );
      await ShopNearYouStore.save(
        'm1',
        const ShopNearYouState(
          choice: ShopNearYouChoice.on,
          areaId: 'tz-dar-city',
          areaName: 'Dar es Salaam',
        ),
      );
      _seedAreaAware(api);
      final host = await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-home-why-popular_near_you'));
      api.clear();
      await tapVisible(tester, _key('shop-near-you-turn-off'));
      expect(find.text(host.tr('shop.why.nearOff')), findsOneWidget);
      expect(_key('shop-near-you-turn-on'), findsOneWidget);
      expect(_sentAreaIds(api), everyElement(isNull));
      expect(ShopNearYouStore.peek('m1')!.choice, ShopNearYouChoice.off);
    });

    apiTest('Turn on from the Why sheet goes through the rationale sheet', (
      tester,
      api,
    ) async {
      final loc = debugShopLocatorOverride = FakeLocator(fix: _darCity);
      await ShopNearYouStore.save(
        'm1',
        const ShopNearYouState(choice: ShopNearYouChoice.off),
      );
      _seedAreaAware(api);
      await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-home-why-recommended'));
      await tapVisible(tester, _key('shop-near-you-turn-on'));
      expect(_key('shop-location-sheet'), findsOneWidget);
      expect(loc.count('request'), 0);
      await tapVisible(tester, _key('shop-location-use'));
      expect(loc.count('request'), 1);
      expect(_sentAreaIds(api).last, 'tz-dar-city');
    });
  });

  // ── rail and badge ────────────────────────────────────────────────────

  group('rail and badge', () {
    apiTest('popular_near_you renders like any rail; its product sheet has '
        'the badge, others do not', (tester, api) async {
      debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
        fix: _darCity,
      );
      await ShopNearYouStore.save(
        'm1',
        const ShopNearYouState(
          choice: ShopNearYouChoice.on,
          areaId: 'tz-dar-city',
        ),
      );
      _seedAreaAware(api);
      for (final p in _products(delivers: true).values) {
        api.on('GET /shop/products/${p['id']}', {
          ...p,
          // The details answer never carries the area flag.
          'deliversToViewerArea': null,
          'vendor': {'businessName': 'Dar Fit Supplies'},
        });
      }
      final host = await _pumpShop(tester, api);
      final rail = _key('shop-home-section-popular_near_you');
      expect(rail, findsOneWidget);
      expect(
        find.descendant(of: rail, matching: find.text('Popular near you')),
        findsOneWidget,
      );
      // Not on rail cards (spec §7.3).
      expect(_key('shop-delivers-badge'), findsNothing);

      await tapVisible(
        tester,
        find.descendant(of: rail, matching: find.text('Whey Protein')).first,
      );
      expect(_key('shop-delivers-badge'), findsOneWidget);
      expect(find.text(host.tr('shop.near.badge')), findsOneWidget);
      // No vendor-typed km with areas in use.
      expect(find.textContaining(' km'), findsNothing);
      await tapVisible(tester, _key('shop-product-close'));

      await tapVisible(
        tester,
        find
            .descendant(
              of: _key('shop-home-section-recommended'),
              matching: find.text('Kettlebell'),
            )
            .first,
      );
      expect(_key('shop-delivers-badge'), findsNothing);
    });
  });

  // ── distance filter ───────────────────────────────────────────────────

  group('distance filter (Q-10)', () {
    Future<void> openFilters(WidgetTester tester) async {
      await tapVisible(tester, _key('shop-home-browse-all'));
      await tester.tap(_key('shop-more-filters'));
      await tester.pumpAndSettle();
    }

    apiTest('hidden once areas exist', (tester, api) async {
      debugShopLocatorOverride = FakeLocator();
      _seed(api, _home(nearYou: _on));
      await _pumpShop(tester, api);
      await openFilters(tester);
      expect(_key('shop-filter-brand'), findsOneWidget);
      expect(_key('shop-filter-distance'), findsNothing);
    });

    apiTest('kept when the backend has no areas (404)', (tester, api) async {
      debugShopLocatorOverride = FakeLocator();
      _seed(api, _home(), areas: false);
      api.fail('GET /shop/areas', 404, {'error': 'feature_disabled'});
      await _pumpShop(tester, api);
      await openFilters(tester);
      expect(_key('shop-filter-distance'), findsOneWidget);
    });
  });

  // ── privacy sheet ─────────────────────────────────────────────────────

  group('Privacy sheet', () {
    for (final lang in ['en', 'sw']) {
      apiTest('`uses` with location lists the area line and the location '
          'row ($lang)', (tester, api) async {
        debugShopLocatorOverride = FakeLocator();
        api.on('GET /shop/preferences', {
          'personalised': true,
          'available': true,
          'historyDays': 365,
          'uses': ['purchase_history', 'location'],
        });
        final host = await pumpPage(
          tester,
          api,
          const SingleChildScrollView(child: ShopPrivacyTile()),
          user: _member,
          lang: lang,
          size: const Size(375, 1200),
          keepRequests: true,
        );
        await tapVisible(tester, _key('privacy-shop'));
        expect(
          tester.widget<Text>(_key('privacy-shop-use-1')).data,
          host.tr('privacy.shop.usesLocation'),
        );
        if (lang == 'sw') {
          expect(
            host.tr('privacy.shop.usesLocation'),
            'Eneo ulipo sasa, ikiwa tu umeruhusu mahali ulipo',
          );
        } else {
          expect(
            host.tr('privacy.shop.usesLocation'),
            'Your approximate area, only if you allow location',
          );
        }
        expect(_key('shop-near-you-line'), findsOneWidget);
        expect(find.text(host.tr('shop.why.nearOff')), findsOneWidget);
      });
    }

    apiTest('switch off on the Privacy page clears the kept area', (
      tester,
      api,
    ) async {
      debugShopLocatorOverride = FakeLocator();
      await ShopNearYouStore.save(
        'm1',
        const ShopNearYouState(
          choice: ShopNearYouChoice.on,
          areaId: 'tz-dar-city',
          areaName: 'Dar es Salaam',
        ),
      );
      api.on('GET /shop/preferences', {
        'personalised': true,
        'available': true,
        'uses': ['location'],
      });
      api.on('PUT /shop/preferences', {
        'personalised': false,
        'available': true,
        'uses': <String>[],
      });
      await pumpPage(
        tester,
        api,
        const SingleChildScrollView(child: ShopPrivacyTile()),
        user: _member,
        size: const Size(375, 1200),
      );
      await tapVisible(tester, _key('privacy-shop'));
      await tester.tap(_key('shop-why-personalised'));
      await tester.pumpAndSettle();
      expect(ShopNearYouStore.peek('m1')!.areaId, isNull);
      expect(_key('shop-near-you-line'), findsNothing);
    });
  });

  // ── Swahili, 130%, a11y ───────────────────────────────────────────────

  group('Swahili and text size', () {
    for (final lang in ['en', 'sw']) {
      apiTest('card and sheet at 130% fit at 375 ($lang)', (tester, api) async {
        debugShopLocatorOverride = FakeLocator(
          access: ShopLocationAccess.granted,
        );
        _seed(api, _home(nearYou: _on));
        final host = await _pumpShop(
          tester,
          api,
          lang: lang,
          scale: 1.3,
          size: const Size(375, 1600),
        );
        expect(tester.takeException(), isNull);
        expect(find.text(host.tr('shop.near.inviteTitle')), findsOneWidget);
        final node = tester.getSemantics(_key('shop-near-you-not-now'));
        expect(node.tooltip, host.tr('shop.near.notNow'));
        await tapVisible(tester, _key('shop-near-you-use'));
        expect(tester.takeException(), isNull);
        expect(find.text(host.tr('shop.near.alreadyAllowed')), findsOneWidget);
        expect(
          tester.getSize(_key('shop-location-use')).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.getSize(_key('shop-location-not-now')).height,
          greaterThanOrEqualTo(48),
        );
      });
    }

    test('every new key resolves in both languages', () {
      final en = FFLocale()..set(const Locale('en'));
      final sw = FFLocale()..set(const Locale('sw'));
      for (final key in [
        for (final k in [
          'inviteTitle',
          'inviteBody',
          'use',
          'notNow',
          'offline',
          'sheetTitle',
          'point1',
          'point2',
          'point3',
          'alreadyAllowed',
          'noArea',
          'failed',
          'denied',
          'openSettings',
          'browserBlocked',
          'servicesOff',
          'badge',
          'finding',
        ])
          'shop.near.$k',
        'shop.why.nearOn',
        'shop.why.nearOff',
        'shop.why.nearNoArea',
        'shop.why.turnOn',
        'shop.why.turnOff',
        'shop.why.popularInArea',
        'shop.why.sellerInArea',
        'shop.why.switchHintMemberArea',
        'shop.why.switchHintPartnerArea',
        'privacy.shop.usesLocation',
        for (final k in [
          'title',
          'basedIn',
          'basedInRow',
          'basedInMissing',
          'deliversTo',
          'deliversRow',
          'deliversMore',
          'deliversEmpty',
          'included',
          'nationwide',
          'search',
          'selected',
          'noneSelected',
          'done',
          'a11yRow',
          'a11yRowTop',
          'level.country',
          'level.region',
          'level.city',
          'level.district',
          'none',
          'failed',
          'nudge',
          'nudgeAction',
          'nudgeCheck',
          'nudgeCheckAction',
        ])
          'vendor.areas.$k',
      ]) {
        expect(en.t(key), isNot(key), reason: 'en $key');
        expect(sw.t(key), isNot(key), reason: 'sw $key');
        if (key != 'vendor.areas.deliversMore' &&
            key != 'vendor.areas.a11yRowTop') {
          expect(sw.t(key), isNot(en.t(key)), reason: 'sw = en for $key');
        }
      }
      // Placeholders survive translation.
      expect(sw.t('shop.why.nearOn'), contains('{area}'));
      expect(sw.t('shop.why.popularInArea'), contains('{areaName}'));
      expect(sw.t('vendor.areas.a11yRow'), contains('{parent}'));
      expect(sw.t('shop.near.badge'), 'Ina delivery hadi eneo lako');
    });
  });

  // ── vendor pickers ────────────────────────────────────────────────────

  group('vendor "Where you sell"', () {
    Future<Future<Map<String, dynamic>?> Function()> pumpForm(
      WidgetTester tester,
      RecordingApi api, {
      bool shopAreas = true,
      Map<String, dynamic> profile = const {},
      String lang = 'en',
      double scale = 1,
    }) async {
      Map<String, dynamic>? result;
      var done = false;
      final full = {
        'businessName': 'Dar Fit Supplies',
        'description': 'Gear',
        'contactNumber': '0700000000',
        'address': 'Kinondoni',
        'businessHours': {'summary': '8-6'},
        'settlementAccount': {'account': '123'},
        'productCategories': ['equipment'],
        'logo': _png,
        'banner': _png,
        ...profile,
      };
      await pumpPage(
        tester,
        api,
        Builder(
          builder: (context) => Center(
            child: FilledButton(
              key: const Key('open-form'),
              onPressed: () async {
                result = await showModalBottomSheet<Map<String, dynamic>>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) =>
                      VendorProfileForm(profile: full, shopAreas: shopAreas),
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
        lang: lang,
        textScale: scale,
        size: const Size(400, 1600),
      );
      return () async => done ? result : null;
    }

    Future<void> open(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(_key('open-form'));
      await tester.pumpAndSettle();
    }

    apiTest('off: no section, nothing about areas sent', (tester, api) async {
      api.on('GET /shop/areas', {'areas': _areasJson});
      final read = await pumpForm(tester, api, shopAreas: false);
      await open(tester);
      expect(_key('vendor-areas'), findsNothing);
      await tapVisible(tester, _key('vendor-profile-publish'));
      final body = (await read())!;
      expect(body.containsKey('cityId'), isFalse);
      expect(body.containsKey('deliveryAreaIds'), isFalse);
      expect(api.sent('GET', '/shop/areas'), isFalse);
    });

    apiTest('Based in is required; pickers fill the request', (
      tester,
      api,
    ) async {
      api.on('GET /shop/areas', {'areas': _areasJson});
      final read = await pumpForm(tester, api);
      await open(tester);
      expect(_key('vendor-areas'), findsOneWidget);
      final l = FFLocale();

      // Publish without "Based in": refused with the message.
      await tapVisible(tester, _key('vendor-profile-publish'));
      expect(find.text(l.t('vendor.areas.basedInMissing')), findsOneWidget);
      expect(await read(), isNull);

      // Based in: only cities and districts can be picked.
      await tapVisible(tester, _key('vendor-areas-based-in'));
      expect(_key('ff-area-picker'), findsOneWidget);
      expect(_key('ff-area-row-tz-dar'), findsNothing);
      expect(_key('ff-area-row-tz'), findsNothing);
      expect(_key('ff-area-row-tz-dar-city'), findsOneWidget);
      final row = tester.getSemantics(_key('ff-area-row-tz-dar-kinondoni'));
      expect(row.label, 'Kinondoni, district in Dar es Salaam');
      expect(
        tester.getSize(_key('ff-area-row-tz-dar-kinondoni')).height,
        greaterThanOrEqualTo(48),
      );
      await tapVisible(tester, _key('ff-area-row-tz-dar-kinondoni'));
      await tapVisible(tester, _key('ff-area-done'));
      expect(find.text('Based in: Kinondoni, Dar es Salaam'), findsOneWidget);

      // Delivers to: a region covers its city and district.
      await tapVisible(tester, _key('vendor-areas-delivers'));
      await tapVisible(tester, _key('ff-area-row-tz-dar'));
      final covered = tester.getSemantics(_key('ff-area-row-tz-dar-city'));
      expect(
        covered.label,
        'Dar es Salaam, city in Dar es Salaam, Included in Dar es Salaam',
      );
      expect(
        covered.getSemanticsData().flagsCollection.isEnabled,
        Tristate.isFalse,
      );
      await tapVisible(tester, _key('ff-area-row-tz-arusha-city'));
      await tapVisible(tester, _key('ff-area-done'));
      expect(find.text('Delivers to: Dar es Salaam, Arusha'), findsOneWidget);

      await tapVisible(tester, _key('vendor-profile-publish'));
      final body = (await read())!;
      expect(body['cityId'], 'tz-dar-kinondoni');
      expect(body['regionId'], 'tz-dar');
      expect(body['deliveryAreaIds'], ['tz-dar', 'tz-arusha-city']);
      expect(body['publish'], isTrue);
    });

    apiTest('Nationwide (the country) covers everything', (tester, api) async {
      api.on('GET /shop/areas', {'areas': _areasJson});
      final read = await pumpForm(
        tester,
        api,
        profile: {'cityId': 'tz-arusha-city'},
      );
      await open(tester);
      expect(find.text('Based in: Arusha'), findsOneWidget);
      await tapVisible(tester, _key('vendor-areas-delivers'));
      await tapVisible(tester, _key('ff-area-row-tz'));
      expect(find.text('Nationwide (all of Tanzania)'), findsWidgets);
      await tapVisible(tester, _key('ff-area-done'));
      await tapVisible(tester, _key('vendor-profile-publish'));
      final body = (await read())!;
      expect(body['deliveryAreaIds'], ['tz']);
      expect(body['cityId'], 'tz-arusha-city');
      expect(body['regionId'], 'tz-arusha');
    });

    apiTest('search keeps the parents visible', (tester, api) async {
      api.on('GET /shop/areas', {'areas': _areasJson});
      await pumpForm(tester, api);
      await open(tester);
      await tapVisible(tester, _key('vendor-areas-delivers'));
      await tester.enterText(_key('ff-area-search'), 'kino');
      await tester.pumpAndSettle();
      expect(_key('ff-area-row-tz-dar-kinondoni'), findsOneWidget);
      expect(_key('ff-area-row-tz-dar-city'), findsOneWidget);
      expect(_key('ff-area-row-tz-dar'), findsOneWidget);
      expect(_key('ff-area-row-tz-arusha'), findsNothing);
    });

    apiTest('no areas: "Areas aren\'t set up yet", nothing sent', (
      tester,
      api,
    ) async {
      api.on('GET /shop/areas', {'areas': <dynamic>[]});
      final read = await pumpForm(tester, api);
      await open(tester);
      expect(_key('vendor-areas-none'), findsOneWidget);
      await tapVisible(tester, _key('vendor-profile-publish'));
      final body = (await read())!;
      expect(body.containsKey('cityId'), isFalse);
    });

    apiTest('load failure: says so, Try again, stored values untouched', (
      tester,
      api,
    ) async {
      api.fail('GET /shop/areas', 500);
      final read = await pumpForm(
        tester,
        api,
        profile: {'cityId': 'tz-dar-city'},
      );
      await open(tester);
      expect(_key('vendor-areas-failed'), findsOneWidget);
      await tapVisible(tester, _key('vendor-profile-publish'));
      final body = (await read())!;
      expect(body.containsKey('cityId'), isFalse);
      expect(body.containsKey('deliveryAreaIds'), isFalse);
    });

    for (final lang in ['en', 'sw']) {
      apiTest('section and picker at 130% ($lang)', (tester, api) async {
        api.on('GET /shop/areas', {'areas': _areasJson});
        await pumpForm(tester, api, lang: lang, scale: 1.3);
        await open(tester);
        expect(tester.takeException(), isNull);
        await tapVisible(tester, _key('vendor-areas-delivers'));
        await tapVisible(tester, _key('ff-area-row-tz-dar'));
        expect(tester.takeException(), isNull);
      });
    }

    test('coverage helpers match the server rule', () {
      expect(coveredAreaIds({'tz-dar'}, _areas), {
        'tz-dar-city',
        'tz-dar-kinondoni',
      });
      expect(
        topPickedAreas({
          'tz-dar',
          'tz-dar-city',
          'tz-arusha',
        }, _areas).map((a) => a.id),
        ['tz-dar', 'tz-arusha'],
      );
    });

    test('VendorTools reads merch.shopAreas exactly true', () {
      expect(
        VendorTools.fromOptions({
          'merch': {'shopAreas': true},
        }).shopAreas,
        isTrue,
      );
      expect(
        VendorTools.fromOptions({
          'merch': {'shopAreas': 'true'},
        }).shopAreas,
        isFalse,
      );
      expect(VendorTools.fromOptions({}).shopAreas, isFalse);
    });
  });

  // ── review round 1 ─────────────────────────────────────────────────────

  group('review fixes', () {
    apiTest('#6 area list fails (5xx): "Couldn\'t find your area" with Try '
        'again, not "no sellers"; Try again works', (tester, api) async {
      final loc = debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
        fix: _darCity,
      );
      _seedAreaAware(api);
      api.fail('GET /shop/areas', 503);
      final host = await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-near-you-use'));
      await tapVisible(tester, _key('shop-location-use'));
      expect(host.snack(host.tr('shop.near.failed')), findsOneWidget);
      expect(host.snack(host.tr('shop.near.noArea')), findsNothing);
      expect(loc.count('position'), 0);
      // Nothing was decided: the card is still offered.
      expect(
        ShopNearYouStore.peek('m1')?.choice ?? ShopNearYouChoice.notAsked,
        ShopNearYouChoice.notAsked,
      );

      api.heal('GET /shop/areas');
      await tester.tap(buttonLabelled(host.tr('common.retry')));
      await tester.pumpAndSettle();
      expect(loc.count('position'), 1);
      expect(_sentAreaIds(api).last, 'tz-dar-city');
      expect(_key('shop-location-sheet'), findsNothing);
    });

    apiTest('#5 the server did not echo the area: the Why line says "no '
        'sellers listed", not the kept name', (tester, api) async {
      debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
        fix: _darCity,
      );
      await ShopNearYouStore.save(
        'm1',
        const ShopNearYouState(
          choice: ShopNearYouChoice.on,
          areaId: 'tz-dar-city',
          areaName: 'Dar es Salaam',
        ),
      );
      // Available, but the area is not recognised (no areaId echoed).
      _seed(api, _home(nearYou: _on));
      final host = await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-home-why-recommended'));
      expect(
        tester.widget<Text>(_key('shop-near-you-status')).data,
        host.tr('shop.why.nearNoArea'),
      );
    });

    test('only the choice and the area id are stored', () {
      const state = ShopNearYouState(
        choice: ShopNearYouChoice.on,
        areaId: 'tz-dar-city',
        areaName: 'Dar es Salaam',
      );
      expect(state.toJson(), {
        'choice': 'on',
        'areaId': 'tz-dar-city',
        'areaSource': 'device',
      });
      final back = ShopNearYouState.fromJson({
        'choice': 'on',
        'areaId': 'tz-dar-city',
        'areaSource': 'device',
        'areaName': 'old',
      });
      expect(back.areaId, 'tz-dar-city');
      expect(back.areaName, isNull);
      // Areas with no centre never match (M1).
      expect(
        areaFor(0, 0, const [
          ShopArea(id: 'a', name: 'A', level: 'city', radiusKm: 999),
        ]),
        isNull,
      );
    });

    Future<void> pumpSaving(
      WidgetTester tester,
      RecordingApi api,
      Map<String, dynamic> profile,
      List<Map<String, dynamic>?> results, {
      String lang = 'en',
    }) async {
      await pumpPage(
        tester,
        api,
        Builder(
          builder: (context) => Center(
            child: FilledButton(
              key: const Key('open-form'),
              onPressed: () async {
                final api0 = AppScope.of(context).api;
                results.add(
                  await showModalBottomSheet<Map<String, dynamic>>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => VendorProfileForm(
                      profile: profile,
                      shopAreas: true,
                      onSave: api0.vendorSaveProfile,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
        lang: lang,
        size: const Size(400, 1600),
      );
      await tester.tap(_key('open-form'));
      await tester.pumpAndSettle();
    }

    final fullProfile = {
      'businessName': 'Dar Fit Supplies',
      'description': 'Gear',
      'contactNumber': '0700000000',
      'address': 'Kinondoni',
      'businessHours': {'summary': '8-6'},
      'settlementAccount': {'account': '123'},
      'productCategories': ['equipment'],
      'logo': _png,
      'banner': _png,
    };

    for (final lang in ['en', 'sw']) {
      apiTest('vendor: 400 invalid_area is shown in the form, which stays '
          'open ($lang)', (tester, api) async {
        api.on('GET /shop/areas', {'areas': _areasJson});
        api.fail('PUT /vendor/profile', 400, {
          'error': 'invalid_area',
          'field': 'deliveryAreaIds',
          'ids': ['tz-arusha-city'],
          'reason': 'inactive',
        });
        final results = <Map<String, dynamic>?>[];
        await pumpSaving(
          tester,
          api,
          {
            ...fullProfile,
            'cityId': 'tz-dar-city',
            'deliveryAreaIds': ['tz-arusha-city'],
          },
          results,
          lang: lang,
        );
        await tapVisible(tester, _key('vendor-profile-publish'));
        final l = FFLocale()..set(Locale(lang));
        expect(
          tester.widget<Text>(_key('vendor-areas-invalid')).data,
          l.t('vendor.areas.invalid.gone').replaceAll('{areas}', 'Arusha'),
        );
        expect(_key('vendor-areas'), findsOneWidget, reason: 'sheet open');
        expect(results, isEmpty);
        expect(api.where('PUT', '/vendor/profile'), hasLength(1));

        // Saved on a second try: the sheet closes with the body.
        api.heal('PUT /vendor/profile');
        await tapVisible(tester, _key('vendor-profile-publish'));
        expect(results, hasLength(1));
        expect(_key('vendor-areas'), findsNothing);
      });
    }

    apiTest('vendor: other reasons have their own words', (tester, api) async {
      api.on('GET /shop/areas', {'areas': _areasJson});
      final l = FFLocale();
      for (final (reason, key) in [
        ('too_many', 'tooMany'),
        ('wrong_level', 'wrongLevel'),
        ('not_in_region', 'notInRegion'),
        ('not_a_list', 'other'),
      ]) {
        api.fail('PUT /vendor/profile', 400, {
          'error': 'invalid_area',
          'field': 'cityId',
          'ids': <String>[],
          'reason': reason,
        });
        final results = <Map<String, dynamic>?>[];
        await pumpSaving(tester, api, {
          ...fullProfile,
          'cityId': 'tz-dar-city',
        }, results);
        await tapVisible(tester, _key('vendor-profile-publish'));
        expect(
          tester.widget<Text>(_key('vendor-areas-invalid')).data,
          l.t('vendor.areas.invalid.$key'),
          reason: reason,
        );
        await tester.pumpWidget(const SizedBox());
      }
    });

    apiTest('vendor: a non-area failure is shown in the form too', (
      tester,
      api,
    ) async {
      api.on('GET /shop/areas', {'areas': _areasJson});
      api.fail('PUT /vendor/profile', 500);
      final results = <Map<String, dynamic>?>[];
      await pumpSaving(tester, api, {
        ...fullProfile,
        'cityId': 'tz-dar-city',
      }, results);
      await tapVisible(tester, _key('vendor-profile-publish'));
      expect(_key('vendor-profile-save-error'), findsOneWidget);
      expect(results, isEmpty);
    });

    apiTest('vendor: a stored cityId that is no longer usable is dropped', (
      tester,
      api,
    ) async {
      api.on('GET /shop/areas', {'areas': _areasJson});
      final results = <Map<String, dynamic>?>[];
      await pumpSaving(tester, api, {
        ...fullProfile,
        'cityId': 'tz-gone-city',
        'deliveryAreaIds': ['tz-gone-city', 'tz-dar'],
      }, results);
      expect(find.text(FFLocale().t('vendor.areas.basedIn')), findsWidgets);
      await tapVisible(tester, _key('vendor-profile-publish'));
      // Based in must be picked again; nothing was sent.
      expect(
        find.text(FFLocale().t('vendor.areas.basedInMissing')),
        findsOneWidget,
      );
      expect(api.sent('PUT', '/vendor/profile'), isFalse);
      await tapVisible(tester, _key('vendor-areas-based-in'));
      await tapVisible(tester, _key('ff-area-row-tz-dar-city'));
      await tapVisible(tester, _key('ff-area-done'));
      await tapVisible(tester, _key('vendor-profile-publish'));
      final body = api.only('PUT', '/vendor/profile').body as Map;
      expect(body['cityId'], 'tz-dar-city');
      expect(body['deliveryAreaIds'], ['tz-dar']);
    });

    test('iOS: location prompts name the shop use, in English and Swahili', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('approximate area for the shop'));
      expect(plist, contains('<string>sw</string>'));
      final en = File(
        'ios/Runner/en.lproj/InfoPlist.strings',
      ).readAsStringSync();
      final sw = File(
        'ios/Runner/sw.lproj/InfoPlist.strings',
      ).readAsStringSync();
      final keys = RegExp(r'^"(NS\w+)"', multiLine: true);
      final plistKeys = RegExp(
        r'<key>(NS\w+UsageDescription)</key>',
      ).allMatches(plist).map((m) => m.group(1)).toSet();
      expect(keys.allMatches(en).map((m) => m.group(1)).toSet(), plistKeys);
      expect(keys.allMatches(sw).map((m) => m.group(1)).toSet(), plistKeys);
      expect(sw, contains('kukadiria eneo lako kwa ajili ya duka'));
      final pbx = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      expect(pbx, contains('sw.lproj/InfoPlist.strings'));
      expect(pbx, contains('InfoPlist.strings in Resources'));
      expect(RegExp(r'knownRegions = \([^)]*\bsw,').hasMatch(pbx), isTrue);
    });

    test('new wording in both languages', () {
      final en = FFLocale()..set(const Locale('en'));
      final sw = FFLocale()..set(const Locale('sw'));
      for (final k in [
        'gone',
        'wrongLevel',
        'notInRegion',
        'tooMany',
        'other',
      ]) {
        final key = 'vendor.areas.invalid.$k';
        expect(en.t(key), isNot(key));
        expect(sw.t(key), isNot(key));
        expect(sw.t(key), isNot(en.t(key)));
      }
      expect(sw.t('vendor.areas.basedIn'), 'Mahali biashara ilipo');
      expect(
        sw.t('vendor.areas.basedInRow').replaceAll('{area}', 'X'),
        'Biashara ipo: X',
      );
      expect(sw.t('shop.near.badge'), 'Ina delivery hadi eneo lako');
      expect(sw.t('shop.near.inviteTitle'), 'Ona bidhaa maarufu karibu nawe');
      expect(
        sw.t('vendor.areas.nationwide').replaceAll('{area}', 'Tanzania'),
        'Nchi nzima (Tanzania yote)',
      );
      expect(
        en.t('shop.why.deliversToArea'),
        'These sellers deliver to your current area.',
      );
      expect(
        sw.t('shop.why.deliversToArea'),
        'Wauzaji hawa wana delivery hadi eneo ulipo sasa.',
      );
    });
  });

  group('final contract (functions#248)', () {
    test('only locatable areas stand for "where you are"', () {
      final list = ShopArea.listFromJson({
        'areas': [
          {
            'id': 'big-city',
            'level': 'city',
            'name': 'Big',
            'locatable': true,
            'lat': 0,
            'lng': 0,
            'radiusKm': 30,
          },
          // Too small (server says not locatable), even with a circle.
          {
            'id': 'tiny-district',
            'level': 'district',
            'name': 'Tiny',
            'parentId': 'big-city',
            'locatable': false,
            'lat': 0,
            'lng': 0,
            'radiusKm': 1,
          },
          {
            'id': 'no-circle',
            'level': 'district',
            'name': 'Nowhere',
            'parentId': 'big-city',
            'locatable': false,
            'lat': null,
            'lng': null,
            'radiusKm': null,
          },
        ],
      });
      expect(list.map((a) => a.locatable), [true, false, false]);
      expect(areaFor(0, 0, list)?.id, 'big-city');
    });

    test('names.sw is shown in Swahili; English falls back to name', () {
      final a = ShopArea.fromJson({
        'id': 'tz-znz-city',
        'level': 'city',
        'name': 'Zanzibar City',
        'names': {'en': 'Zanzibar City', 'sw': 'Mji wa Zanzibar'},
      })!;
      expect(a.nameIn('sw'), 'Mji wa Zanzibar');
      expect(a.nameIn('en'), 'Zanzibar City');
    });

    test('reasonParams.areaName {en, sw} is read in the shown language', () {
      final section = ShopHomeSection.fromJson({
        'key': 'popular_near_you',
        'reasonCodes': ['popular_in_area'],
        'reasonParams': {
          'areaName': {'en': 'Zanzibar City', 'sw': 'Mji wa Zanzibar'},
        },
        'productIds': ['p1'],
      });
      final params = section.reasonCodes.single.params;
      expect(shopReasonParam(params, 'areaName', 'en'), 'Zanzibar City');
      expect(shopReasonParam(params, 'areaName', 'sw'), 'Mji wa Zanzibar');
      // An older string value still works.
      final old = shopReasonParams({'areaName': 'Arusha'});
      expect(shopReasonParam(old, 'areaName', 'sw'), 'Arusha');
    });

    apiTest('Why sheet names the area in Swahili from reasonParams', (
      tester,
      api,
    ) async {
      debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
        fix: _darCity,
      );
      await ShopNearYouStore.save(
        'm1',
        const ShopNearYouState(
          choice: ShopNearYouChoice.on,
          areaId: 'tz-dar-city',
        ),
      );
      _seedAreaAware(api);
      api.onCall('GET /shop/home', (r) {
        final home = _home(
          nearYou: r.headers['x-ff-area'] == null
              ? _on
              : {
                  'available': true,
                  'areaId': r.headers['x-ff-area'],
                  'areaName': {'en': 'Dar es Salaam', 'sw': 'Mji wa Dar'},
                },
          areaSection: r.headers['x-ff-area'] != null,
        );
        for (final sec in home['sections'] as List) {
          if ((sec as Map)['key'] == 'popular_near_you') {
            sec['reasonParams'] = {
              'areaName': {'en': 'Dar es Salaam', 'sw': 'Mji wa Dar'},
            };
          }
        }
        return home;
      });
      final host = await _pumpShop(tester, api, lang: 'sw');
      await tapVisible(tester, _key('shop-home-why-popular_near_you'));
      expect(
        find.text(
          host
              .tr('shop.why.popularInArea')
              .replaceAll('{areaName}', 'Mji wa Dar'),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(_key('shop-near-you-status')).data,
        host.tr('shop.why.nearOn').replaceAll('{area}', 'Mji wa Dar'),
      );
    });
  });

  // ── QA round 1 (design-QA + UAT on RC 3ea5cf8) ──────────────────────────

  group('QA round 1', () {
    apiTest('#1 Why sheet of the near-you rail follows the switch at once, '
        'even when the rail leaves the page', (tester, api) async {
      debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
        fix: _darCity,
      );
      await ShopNearYouStore.save(
        'm1',
        const ShopNearYouState(
          choice: ShopNearYouChoice.on,
          areaId: 'tz-dar-city',
        ),
      );
      var personalised = true;
      _seedAreaAware(api);
      api.onCall('GET /shop/home', (r) {
        if (!personalised) {
          return _home(nearYou: _off, personalised: false);
        }
        final areaId = r.headers['x-ff-area'];
        final home = _home(
          nearYou: areaId == null
              ? _on
              : {
                  'available': true,
                  'areaId': areaId,
                  'areaName': {'en': 'Dar es Salaam', 'sw': 'Dar es Salaam'},
                },
          areaSection: areaId != null,
          delivers: areaId != null,
        );
        for (final sec in home['sections'] as List) {
          if ((sec as Map)['key'] == 'popular_near_you') {
            sec['reason'] = {
              'en': 'Popular with shoppers in Dar es Salaam.',
              'sw': 'Maarufu kwa wanunuzi wa Dar es Salaam.',
            };
          }
        }
        return home;
      });
      api.onCall('PUT /shop/preferences', (_) {
        personalised = false;
        return {'personalised': false, 'available': true};
      });
      final host = await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-home-why-popular_near_you'));
      final why = _key('shop-why-popular_near_you');
      String whyText() => tester
          .widgetList<Text>(
            find.descendant(of: why, matching: find.byType(Text)),
          )
          .map((t) => t.data ?? '')
          .join('\n');
      expect(whyText(), contains('Dar es Salaam'));

      await tester.tap(_key('shop-why-personalised'));
      await tester.pumpAndSettle();

      // The rail is gone from the page, the sheet is still open and right.
      expect(_key('shop-home-section-popular_near_you'), findsNothing);
      expect(why, findsOneWidget);
      expect(
        tester.widget<Switch>(_key('shop-why-personalised')).value,
        isFalse,
      );
      expect(whyText(), isNot(contains('Dar es Salaam')));
      expect(whyText(), isNot(contains(host.tr('shop.why.deliversToArea'))));
      expect(_key('shop-near-you-line'), findsNothing);
      // #9: the hint no longer names the current area.
      expect(find.text(host.tr('shop.why.switchHintMember')), findsOneWidget);
      expect(find.text(host.tr('shop.why.switchHintMemberArea')), findsNothing);
    });

    apiTest('#4 product list and details carry X-FF-Area; Results tiles '
        'show the badge', (tester, api) async {
      debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
        fix: _darCity,
      );
      await ShopNearYouStore.save(
        'm1',
        const ShopNearYouState(
          choice: ShopNearYouChoice.on,
          areaId: 'tz-dar-city',
        ),
      );
      _seedAreaAware(api);
      api.onCall('GET /shop/products', (r) {
        final area = r.headers['x-ff-area'];
        return [
          for (final p in _products().values)
            {
              ...p,
              if (area != null && p['id'] == 'p3') 'deliversToViewerArea': true,
            },
        ];
      });
      api.onCall(
        'GET /shop/products/p3',
        (r) => {
          ..._products()['p3']!,
          if (r.headers['x-ff-area'] != null) 'deliversToViewerArea': true,
        },
      );
      await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-home-browse-all'));
      final list = api.where('GET', '/shop/products');
      expect(list, isNotEmpty);
      expect(list.last.headers['x-ff-area'], 'tz-dar-city');
      expect(list.last.query, isNot(contains('area')));
      expect(_key('shop-delivers-p3'), findsOneWidget);
      expect(_key('shop-delivers-p4'), findsNothing);
      await tapVisible(tester, find.text('Kettlebell').first);
      expect(
        api.where('GET', '/shop/products/p3').last.headers['x-ff-area'],
        'tz-dar-city',
      );
      expect(_key('shop-delivers-badge'), findsWidgets);
      _expectNoCoordinates(api);
    });

    apiTest('#4 no area header while near-you is not available', (
      tester,
      api,
    ) async {
      debugShopLocatorOverride = FakeLocator();
      await ShopNearYouStore.save(
        'm1',
        const ShopNearYouState(
          choice: ShopNearYouChoice.on,
          areaId: 'tz-dar-city',
        ),
      );
      _seed(api, _home(nearYou: _off));
      await _pumpShop(tester, api);
      await tapVisible(tester, _key('shop-home-browse-all'));
      for (final r in api.where('GET', '/shop/products')) {
        expect(r.headers.containsKey('x-ff-area'), isFalse);
      }
    });

    for (final width in [375.0, 1280.0]) {
      apiTest('#3 #7 #11 invite and sheet buttons are 48 tall, the sheet is '
          '480 wide on desktop (width $width)', (tester, api) async {
        debugShopLocatorOverride = FakeLocator();
        _seed(api, _home(nearYou: _on));
        await _pumpShop(tester, api, size: Size(width, 1400));
        expect(
          tester.getSize(_key('shop-near-you-use')).height,
          greaterThanOrEqualTo(48),
        );
        await tapVisible(tester, _key('shop-near-you-use'));
        for (final k in ['shop-location-use', 'shop-location-not-now']) {
          expect(tester.getSize(_key(k)).height, greaterThanOrEqualTo(48));
          // Two-tone focus ring around each (QA #7).
          expect(
            find.ancestor(of: _key(k), matching: find.byType(ShopFocusRing)),
            findsOneWidget,
          );
        }
        final sheetWidth = tester.getSize(_key('shop-location-sheet')).width;
        if (width >= 1024) {
          expect(find.byType(Dialog), findsOneWidget);
          expect(sheetWidth, lessThanOrEqualTo(480));
        } else {
          expect(find.byType(Dialog), findsNothing);
        }
      });
    }

    test('#5 rationale says FitFlex does not keep the area on its servers', () {
      final en = FFLocale();
      final sw = FFLocale()..set(const Locale('sw'));
      expect(
        en.t('shop.near.point2'),
        contains("doesn't keep it on its servers"),
      );
      expect(en.t('shop.near.point2'), isNot(contains("isn't stored")));
      expect(sw.t('shop.near.point2'), contains('haihifadhi kwenye seva zake'));
    });

    apiTest('#6 single-mode rows read as selected radios; no Nationwide '
        'heading', (tester, api) async {
      api.on('GET /shop/areas', {'areas': _areasJson});
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      final handle = tester.ensureSemantics();
      await pumpPage(
        tester,
        api,
        Builder(
          builder: (context) => Center(
            child: FilledButton(
              key: const Key('open-picker'),
              onPressed: () => showFFAreaPicker(
                context,
                title: 'Pick',
                areas: _areas,
                multi: false,
                levels: const {'city', 'district'},
                selected: const {'tz-dar-city'},
              ),
              child: const Text('open'),
            ),
          ),
        ),
        size: const Size(400, 1600),
      );
      await tester.tap(_key('open-picker'));
      await tester.pumpAndSettle();
      final flags = tester
          .getSemantics(_key('ff-area-row-tz-dar-city'))
          .getSemanticsData()
          .flagsCollection;
      expect(flags.isChecked, CheckedState.isTrue);
      expect(flags.isSelected, Tristate.isTrue);
      expect(flags.isInMutuallyExclusiveGroup, isTrue);
      expect(find.textContaining('Nationwide'), findsNothing);
      handle.dispose();
      await tester.binding.setSurfaceSize(null);
    });

    apiTest('#10 the sheet backdrop is announced as Close, not Scrim', (
      tester,
      api,
    ) async {
      debugShopLocatorOverride = FakeLocator();
      _seed(api, _home(nearYou: _on));
      final handle = tester.ensureSemantics();
      final host = await _pumpShop(tester, api, lang: 'sw');
      await tapVisible(tester, _key('shop-near-you-use'));
      expect(find.bySemanticsLabel('Scrim'), findsNothing);
      expect(find.bySemanticsLabel(host.tr('common.close')), findsWidgets);
      handle.dispose();
    });

    apiTest('#8 the Based in hint shows before Save; Add now opens at Where '
        'you sell', (tester, api) async {
      api.on('GET /shop/areas', {'areas': _areasJson});
      final l = FFLocale();
      await pumpPage(
        tester,
        api,
        Builder(
          builder: (context) => Center(
            child: FilledButton(
              key: const Key('open-form'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => VendorProfileForm(
                  profile: {
                    'businessName': 'Dar Fit Supplies',
                    'description': 'Gear ' * 40,
                    'logo': _png,
                    'banner': _png,
                  },
                  shopAreas: true,
                  scrollToAreas: true,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        size: const Size(400, 640),
      );
      await tester.tap(_key('open-form'));
      await tester.pumpAndSettle();
      expect(find.text(l.t('vendor.areas.basedInMissing')), findsOneWidget);
      // Scrolled so the section is on screen.
      final top = tester.getTopLeft(_key('vendor-areas')).dy;
      expect(top, lessThan(640));
      expect(top, greaterThanOrEqualTo(0));
    });
  });

  // ── QA round 2 (RC e57f1f6) ─────────────────────────────────────────────

  group('QA round 2', () {
    /// Products answer with the badge only when the area header came.
    void seedAreaProducts(RecordingApi api) {
      api.onCall('GET /shop/products', (r) {
        final area = r.headers['x-ff-area'];
        return [
          for (final p in _products().values)
            {
              ...p,
              if (area != null && p['id'] == 'p3') 'deliversToViewerArea': true,
            },
        ];
      });
      api.onCall(
        'GET /shop/products/p3',
        (r) => {
          ..._products()['p3']!,
          if (r.headers['x-ff-area'] != null) 'deliversToViewerArea': true,
        },
      );
    }

    Future<PageHost> pumpAt(
      WidgetTester tester,
      RecordingApi api,
      String location, {
      Size size = const Size(420, 1400),
    }) => pumpPage(
      tester,
      api,
      const ShopBrowseBody(mode: ShopHomeMode.member, routePath: '/'),
      user: _member,
      size: size,
      keepRequests: true,
      initialLocation: location,
    );

    Future<void> keepArea() => ShopNearYouStore.save(
      'm1',
      const ShopNearYouState(
        choice: ShopNearYouChoice.on,
        areaId: 'tz-dar-city',
      ),
    );

    apiTest('#1 cold load of Results (refresh): the badge shows once the '
        'server says near-you is available', (tester, api) async {
      debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
        fix: _darCity,
      );
      await keepArea();
      _seedAreaAware(api);
      seedAreaProducts(api);
      await pumpAt(tester, api, '/?view=results');
      expect(_key('shop-home'), findsNothing);
      final list = api.where('GET', '/shop/products');
      expect(list.first.headers.containsKey('x-ff-area'), isFalse);
      expect(list.last.headers['x-ff-area'], 'tz-dar-city');
      expect(_key('shop-delivers-p3'), findsOneWidget);
      // The probe asked /shop/home without the area.
      final homes = api.where('GET', '/shop/home');
      expect(homes, isNotEmpty);
      expect(homes.first.headers.containsKey('x-ff-area'), isFalse);
      _expectNoCoordinates(api);
    });

    apiTest('#1 cold ?product= link: the open sheet refetches with the area '
        'and shows the badge', (tester, api) async {
      debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
        fix: _darCity,
      );
      await keepArea();
      _seedAreaAware(api);
      seedAreaProducts(api);
      await pumpAt(tester, api, '/?product=p3');
      final details = api.where('GET', '/shop/products/p3');
      expect(details.first.headers.containsKey('x-ff-area'), isFalse);
      expect(details.last.headers['x-ff-area'], 'tz-dar-city');
      expect(_key('shop-delivers-badge'), findsOneWidget);
    });

    for (final location in ['/?view=results', '/?product=p3']) {
      apiTest('#1 not available: no area header on $location', (
        tester,
        api,
      ) async {
        debugShopLocatorOverride = FakeLocator();
        await keepArea();
        _seed(api, _home(nearYou: _off));
        seedAreaProducts(api);
        await pumpAt(tester, api, location);
        for (final r in [
          ...api.where('GET', '/shop/products'),
          ...api.where('GET', '/shop/products/p3'),
          ...api.where('GET', '/shop/home'),
        ]) {
          expect(r.headers.containsKey('x-ff-area'), isFalse, reason: '$r');
        }
        expect(_key('shop-delivers-badge'), findsNothing);
        // The kept area was forgotten (L1).
        expect(ShopNearYouStore.peek('m1')!.areaId, isNull);
      });
    }

    for (final width in [375.0, 1280.0]) {
      apiTest('#2 area picker Done/Cancel are 48 tall (width $width)', (
        tester,
        api,
      ) async {
        await pumpPage(
          tester,
          api,
          Builder(
            builder: (context) => Center(
              child: FilledButton(
                key: const Key('open-picker'),
                onPressed: () => showFFAreaPicker(
                  context,
                  title: 'Pick',
                  areas: _areas,
                  multi: false,
                  levels: const {'city', 'district'},
                ),
                child: const Text('open'),
              ),
            ),
          ),
          size: Size(width, 1600),
        );
        await tester.tap(_key('open-picker'));
        await tester.pumpAndSettle();
        for (final k in ['ff-area-done', 'ff-area-cancel']) {
          final visible = find
              .descendant(of: _key(k), matching: find.byType(Material))
              .first;
          expect(tester.getSize(visible).height, greaterThanOrEqualTo(48));
        }
      });
    }

    for (final lang in ['en', 'sw']) {
      apiTest('#3 product sheet backdrop reads Close, no Scrim or Dismiss '
          '($lang)', (tester, api) async {
        debugShopLocatorOverride = FakeLocator();
        _seed(api, _home(nearYou: _on));
        api.on('GET /shop/products/p3', _products()['p3']);
        final handle = tester.ensureSemantics();
        final host = await pumpAt(
          tester,
          api,
          '/?product=p3',
          size: const Size(420, 1400),
        );
        expect(_key('shop-product-close'), findsOneWidget);
        expect(find.bySemanticsLabel('Scrim'), findsNothing);
        expect(find.bySemanticsLabel('Dismiss'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('Ondoa')), findsNothing);
        expect(find.bySemanticsLabel(host.tr('common.close')), findsWidgets);
        // The handle is still drawn.
        expect(_key('shop-product-handle'), findsOneWidget);
        handle.dispose();
      });
    }
  });

  // ── no manual area (owner decision 2026-10-28) ────────────────────────

  group('no Change area: the area comes only from the device', () {
    void expectNoChangeArea() {
      expect(_key('shop-near-you-change'), findsNothing);
      expect(find.text('Change area'), findsNothing);
      expect(find.text('Badilisha eneo'), findsNothing);
      expect(find.text('Pick your city or district'), findsNothing);
      expect(find.text('Chagua jiji au wilaya yako'), findsNothing);
    }

    Future<void> keepDetectedArea() => ShopNearYouStore.save(
      'm1',
      const ShopNearYouState(
        choice: ShopNearYouChoice.on,
        areaId: 'tz-dar-city',
        areaName: 'Dar es Salaam',
      ),
    );

    for (final lang in ['en', 'sw']) {
      apiTest('Why sheet, near-you on: Turn off only, no Change area ($lang)', (
        tester,
        api,
      ) async {
        debugShopLocatorOverride = FakeLocator(
          access: ShopLocationAccess.granted,
          fix: _darCity,
        );
        await keepDetectedArea();
        _seedAreaAware(api);
        final host = await _pumpShop(tester, api, lang: lang);
        await tapVisible(tester, _key('shop-home-why-popular_near_you'));
        expect(_key('shop-near-you-line'), findsOneWidget);
        expect(_key('shop-near-you-turn-off'), findsOneWidget);
        expect(
          find.text(
            host.tr('shop.why.nearOn').replaceAll('{area}', 'Dar es Salaam'),
          ),
          findsOneWidget,
        );
        expectNoChangeArea();
      });

      apiTest('Why sheet, near-you off: Turn on only, no Change area ($lang)', (
        tester,
        api,
      ) async {
        debugShopLocatorOverride = FakeLocator(fix: _darCity);
        await ShopNearYouStore.save(
          'm1',
          const ShopNearYouState(choice: ShopNearYouChoice.off),
        );
        _seedAreaAware(api);
        await _pumpShop(tester, api, lang: lang);
        await tapVisible(tester, _key('shop-home-why-recommended'));
        expect(_key('shop-near-you-turn-on'), findsOneWidget);
        expect(_key('shop-near-you-turn-off'), findsNothing);
        expectNoChangeArea();
      });

      apiTest('Privacy sheet, near-you on: Turn off only, no Change area '
          '($lang)', (tester, api) async {
        debugShopLocatorOverride = FakeLocator();
        await keepDetectedArea();
        api.on('GET /shop/preferences', {
          'personalised': true,
          'available': true,
          'historyDays': 365,
          'uses': ['purchase_history', 'location'],
        });
        api.on('GET /shop/areas', {'areas': _areasJson});
        await pumpPage(
          tester,
          api,
          const SingleChildScrollView(child: ShopPrivacyTile()),
          user: _member,
          lang: lang,
          size: const Size(375, 1200),
        );
        await tapVisible(tester, _key('privacy-shop'));
        expect(_key('shop-near-you-line'), findsOneWidget);
        expect(_key('shop-near-you-turn-off'), findsOneWidget);
        expectNoChangeArea();
      });
    }

    test('a kept area not marked as worked out on the device is dropped', () {
      // An older build stored the area without a source, and could store
      // one picked by hand: it is not sent; the device works it out again.
      final legacy = ShopNearYouState.fromJson({
        'choice': 'on',
        'areaId': 'tz-dar-city',
      });
      expect(legacy.choice, ShopNearYouChoice.on);
      expect(legacy.areaId, isNull);
      expect(
        ShopNearYouState.fromJson({
          'choice': 'on',
          'areaId': 'tz-dar-city',
          'areaSource': 'manual',
        }).areaId,
        isNull,
      );
    });

    apiTest('a dropped legacy area is worked out again from GPS', (
      tester,
      api,
    ) async {
      final loc = debugShopLocatorOverride = FakeLocator(
        access: ShopLocationAccess.granted,
        fix: _kinondoni,
      );
      // What an older build left on the phone (no areaSource).
      SharedPreferences.setMockInitialValues({
        'ff.shop.nearYou.m1': jsonEncode({
          'choice': 'on',
          'areaId': 'tz-arusha-city',
        }),
      });
      final kept = await ShopNearYouStore.load('m1');
      expect(kept.choice, ShopNearYouChoice.on);
      expect(kept.areaId, isNull);
      _seedAreaAware(api);
      await _pumpShop(tester, api);
      expect(loc.count('position'), 1);
      expect(loc.count('request'), 0);
      expect(ShopNearYouStore.peek('m1')!.areaId, 'tz-dar-kinondoni');
      expect(_sentAreaIds(api), isNot(contains('tz-arusha-city')));
      _expectNoCoordinates(api);
    });

    test('no shopper code opens an area picker or names Change area', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final path = f.path.replaceAll('\\', '/');
        final src = f.readAsStringSync();
        final vendor = path.startsWith('lib/screens/vendor/');
        final picker = path == 'lib/shared/widgets/ff_area_picker.dart';
        if (!vendor && !picker && src.contains('showFFAreaPicker')) {
          offenders.add('$path opens the area picker');
        }
        if (!vendor && !picker && src.contains('FFAreaPicker(')) {
          offenders.add('$path builds the area picker');
        }
        for (final word in [
          'shop.near.changeArea',
          'shop.near.pickArea',
          'shop-near-you-change',
          'manual: true',
        ]) {
          if (path.contains('shop') && src.contains(word)) {
            offenders.add('$path has $word');
          }
        }
      }
      expect(offenders, isEmpty);
      final en = FFLocale();
      final sw = FFLocale()..set(const Locale('sw'));
      for (final k in ['shop.near.changeArea', 'shop.near.pickArea']) {
        expect(en.t(k), isNot('Change area'));
        expect(en.t(k), isNot('Pick your city or district'));
        expect(sw.t(k), isNot('Badilisha eneo'));
      }
    });
  });
}
