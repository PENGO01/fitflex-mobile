// Screenshots of every reachable page per role (light), for the end-to-end
// design review. Off by default; same flags as design_screens_test.dart.
//
// Off by default. Run with:
//   flutter test test/design_screens_test.dart \
//     --dart-define=DESIGN_SHOTS=true --update-goldens
// The pictures land in test/design_shots/. They are not committed; they are
// review material, not goldens to compare against.
//
// Boots the app the same way as app_regression_test.dart, from the recorded
// fixtures in test/fixtures/regression.json.

import 'dart:convert';
import 'dart:io';

import 'package:fitflexmobile/main.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/shop_home.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vendor/reports_s6_test.dart' show ownerSummary;

const _shots = bool.fromEnvironment('DESIGN_SHOTS');

final Map<String, dynamic> _fixtures = () {
  final f = File('test/fixtures/regression.json');
  return f.existsSync()
      ? jsonDecode(f.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};
}();

MockClient _client() => MockClient((req) async {
  final role = (req.headers['authorization'] ?? '').replaceFirst('Bearer ', '');
  final key = '${req.method} ${req.url.path}';
  if (req.method != 'GET') return http.Response('{}', 200);
  final byRole = (_fixtures[role] as Map?) ?? const {};
  final shared = (_fixtures['_public'] as Map?) ?? const {};
  final body = byRole.containsKey(key) ? byRole[key] : shared[key];
  if (body == null) {
    return http.Response(jsonEncode({'error': 'not_recorded'}), 404);
  }
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});

Future<void> _loadFonts() async {
  Future<ByteData> f(String p) async =>
      ByteData.sublistView(File(p).readAsBytesSync());
  final sans = FontLoader('Plus Jakarta Sans');
  for (final w in [400, 500, 600, 700, 800]) {
    final file = File('assets/fonts/PlusJakartaSans-$w.ttf');
    if (file.existsSync()) sans.addFont(f(file.path));
  }
  await sans.load();
  final mono = FontLoader('JetBrains Mono');
  for (final w in [400, 500, 700]) {
    final file = File('assets/fonts/JetBrainsMono-$w.ttf');
    if (file.existsSync()) mono.addFont(f(file.path));
  }
  await mono.load();
  const material = '/bin/cache/artifacts/material_fonts';
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final roboto = FontLoader('Roboto');
    for (final n in ['Regular', 'Medium', 'Bold']) {
      final file = File('$flutterRoot$material/Roboto-$n.ttf');
      if (file.existsSync()) roboto.addFont(f(file.path));
    }
    await roboto.load();
    final icons = File('$flutterRoot$material/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(f(icons.path))).load();
    }
  }
}

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  // Let asset images (the pass card's dot map) finish decoding first.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump();
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile(name));
}


/// Member states that the recorded fixtures don't cover: built from the
/// member's own fixtures with `/me` changed (and Shop home v2 data).
void _addVariants() {
  final base = Map<String, dynamic>.from((_fixtures['member'] as Map?) ?? {});
  if (base.isEmpty) return;
  Map<String, dynamic> me(void Function(Map<String, dynamic>) edit) {
    final m = jsonDecode(jsonEncode(base['GET /me'])) as Map<String, dynamic>;
    edit(m);
    return {...base, 'GET /me': m};
  }

  _fixtures['member-nopass'] = me((m) {
    m['subscription'] = null;
    m['pendingPayment'] = null;
  });
  _fixtures['member-pending'] = me((m) {
    m['subscription'] = null;
    m['pendingPayment'] = {
      'id': 'pay_1',
      'memberId': 'usr_dev_member',
      'subscriptionId': '',
      'tier': 'pro',
      'productType': 'FITFLEX_PASS',
      'amountTzs': 60000,
      'status': 'pending',
      'provider': 'mpesa',
      'createdAt': '2026-11-15T08:00:00Z',
    };
  });
  _fixtures['member-expired'] = me((m) {
    final sub = Map<String, dynamic>.from(m['subscription'] as Map);
    sub['status'] = 'expired';
    sub['expiresAt'] = '2026-11-10T00:00:00Z';
    sub['renewsAt'] = '2026-11-10T00:00:00Z';
    m['subscription'] = sub;
  });
  final vendor = Map<String, dynamic>.from((_fixtures['vendor'] as Map?) ?? {});
  if (vendor.isNotEmpty) {
    _fixtures['vendor-reports'] = {
      ...vendor,
      'GET /vendor/tools/options': {
        'reports': true,
        'canSeeCost': true,
        'canSeeOrderMoney': true,
      },
      'GET /vendor/reports/summary': ownerSummary(),
      'GET /vendor/sales': {'sales': <Object>[], 'nextCursor': null},
    };
  }
  final products = <String, dynamic>{
    for (final p in [
      ['p1', 'Whey Protein 2kg', 'supplements_nutrition', 85000, null, 12],
      ['p2', 'Yoga Mat', 'equipment', 30000, 24000, 8],
      ['p3', 'Kettlebell 12kg', 'equipment', 45000, null, 0],
      ['p4', 'Running Shoes', 'sportswear_footwear', 120000, null, 5],
    ])
      p[0] as String: {
        'id': p[0],
        'vendorId': 'v1',
        'name': p[1],
        'category': p[2],
        'priceTzs': p[3],
        'discountPriceTzs': p[4],
        'stock': p[5],
        'rating': 4.5,
        'reviewCount': 12,
        'soldCount': 40,
        'deliveryAvailable': true,
      },
  };
  _fixtures['member-shop'] = {
    ...base,
    'GET /shop/home': {
      'serverNow': '2026-11-15T08:00:00Z',
      'currency': 'TZS',
      'mode': 'member',
      'personalised': false,
      'signalsUsed': <String>[],
      'categories': [
        {'key': 'sportswear_footwear', 'en': 'Sportswear & footwear', 'sw': 'Mavazi'},
        {'key': 'supplements_nutrition', 'en': 'Supplements & nutrition', 'sw': 'Virutubisho'},
        {'key': 'equipment', 'en': 'Gym & fitness equipment', 'sw': 'Vifaa'},
        {'key': 'accessories_gear', 'en': 'Accessories & gear', 'sw': 'Zana'},
      ],
      'sections': [
        {
          'key': 'best_sellers',
          'title': {'en': 'Best sellers', 'sw': 'Zinazouzwa zaidi'},
          'viewAll': {'query': {'sort': 'popularity'}},
          'productIds': ['p1', 'p3', 'p4'],
        },
        {
          'key': 'deals',
          'title': {'en': 'Deals', 'sw': 'Ofa'},
          'viewAll': {'query': {'promotions': 'true'}},
          'productIds': ['p2'],
        },
      ],
      'products': products,
    },
  };
}

/// Pages reached by a tap (pushed, not routed): [home, nav index, key].
const _taps = <String, List<(String, int, String)>>{
  'trainer': [
    ('/trainer/home', 0, 'trainer-tile-sessions'),
    ('/trainer/home', 0, 'trainer-tile-earnings'),
    ('/trainer/home', 0, 'trainer-tile-payouts'),
    ('/trainer/home', 0, 'trainer-engagement-inbox'),
    ('/trainer/home', 0, 'trainer-tile-schedule'),
    ('/trainer/home', 4, 'trainer-tile-professional'),
    ('/trainer/home', 4, 'trainer-reviews'),
    ('/trainer/home', 4, 'trainer-verification'),
  ],
  'vendor': [
    ('/vendor/home', 0, 'vendor-add-product'),
    ('/vendor/home', 4, 'vendor-edit-profile'),
    ('/vendor/home', 4, 'vendor-payouts'),
    ('/vendor/home', 4, 'vendor-tax-entry'),
    ('/vendor/home', 4, 'vendor-message-settings'),
    ('/vendor/home', 4, 'vendor-add-staff'),
  ],
  'gym_operator': [
    ('/owner/home', 0, 'owner-checkin-primary'),
  ],
};

const _routes = <String, List<String>>{
  'vendor-reports': ['/vendor/home?open=reports', '/vendor/home?open=orders'],
  'member-nopass': ['/member', '/member/qr', '/member/passes'],
  'member-pending': ['/member', '/member/qr', '/member/payment'],
  'member-expired': ['/member', '/member/qr', '/member/profile'],
  'member-shop': ['/member/shop', '/member/profile'],
  'guest': [
    '/language',
    '/role',
    '/auth',
    '/auth/signup',
    '/auth/email',
    '/offline',
  ],
  'member': [
    '/member/activity/log',
    '/member/activity/history',
    '/member/activity/run',
    '/member/activity/progress',
    '/member/activity/training',
    '/member/activity/training/setup',
    '/member/gyms/gym_50106d',
    '/member/trainers',
    '/member/trainers/trn_e7781397',
    '/member/events',
    '/member/events/orders',
    '/member/events/tickets',
    '/member/events/results',
    '/member/events/medals',
    '/member/events/rewards',
    '/member/events/waitlist',
    '/member/passes',
    '/member/payment',
    '/member/privacy',
    '/member/privacy/activity-sharing',
    '/member/community',
    '/member/benefits',
    '/member/sessions',
    '/member/message-settings',
    '/member/onboarding',
    '/inbox',
    '/friend-invite',
    '/invitations',
    '/personas',
    '/verification',
  ],
  'trainer': ['/trainer/brand-media', '/inbox', '/verification'],
  'gym_operator': [
    '/owner/gyms/gym_dev_owner/checkins',
    '/owner/members/usr_dev_member',
    '/owner/members/usr_dev_member/checkins',
    '/owner/members/usr_dev_member/payments',
    '/owner/members/usr_dev_member/messages',
    '/owner/communications/new',
    '/owner/communications/templates/new',
    '/owner/gyms',
    '/owner/members',
    '/owner/trainers',
    '/owner/communications',
    '/owner/earnings',
    '/owner/shop',
    '/owner/staff',
    '/owner/profile',
    '/owner/brand-media',
    '/verification',
  ],
  'vendor': ['/vendor/merch', '/vendor/brand-media', '/verification'],
};

void main() {
  setUpAll(_loadFonts);
  _addVariants();
  debugShopHomeV2Override = true;

  for (final entry in _routes.entries) {
    final role = entry.key;
    testWidgets('$role pages', skip: !_shots, (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await http.runWithClient(() async {
        final guest = role == 'guest';
        final me = ((_fixtures[role] as Map?)?['GET /me'] as Map?)?['user'];
        SharedPreferences.setMockInitialValues({
          if (!guest) 'token': role,
          if (!guest) 'role': role.split('-').first,
          if (!guest)
            'user': jsonEncode(me ?? {'id': 'u_$role', 'userType': role}),
          'locale': 'en',
          'lang_selected': true,
          ThemeNotifier.prefsKey: 'light',
        });
        final api = ApiClient(baseUrl: 'http://fixtures.local');
        final auth = AuthState(api);
        await auth.hydrate();
        final theme = ThemeNotifier();
        await theme.load();
        await tester.pumpWidget(
          FitFlexApp(
            api: api,
            auth: auth,
            locale: FFLocale()..set(const Locale('en')),
            themeNotifier: theme,
          ),
        );
        await _settle(tester, 12);
        for (final path in entry.value) {
          final name = path
              .substring(1)
              .replaceAll(RegExp('[^a-z0-9]+'), '-');
          try {
            final ctx = tester.element(find.byType(Navigator).first);
            GoRouter.of(ctx).go(path);
            await _settle(tester, 8);
            await _shot(tester, 'design_routes/$role--$name.png');
          } catch (e) {
            // A page that throws is a finding too; note it and go on.
            File('test/design_routes/$role--$name.error.txt')
              ..createSync(recursive: true)
              ..writeAsStringSync('$e');
          }
        }
        for (final (home, tab, key) in _taps[role] ?? const <(String, int, String)>[]) {
          final name = '$role--tap-$key';
          try {
            final nav0 = tester.state<NavigatorState>(
              find.byType(Navigator).first,
            );
            while (nav0.canPop()) {
              nav0.pop();
              await tester.pump();
            }
            GoRouter.of(tester.element(find.byType(Navigator).first)).go(home);
            await _settle(tester, 6);
            final dests = find.byType(NavigationDestination);
            if (dests.evaluate().length > tab) {
              await tester.tap(dests.at(tab));
              await _settle(tester, 4);
            }
            final target = find.byKey(Key(key));
            final list = find.byType(Scrollable);
            if (target.evaluate().isEmpty && list.evaluate().isNotEmpty) {
              await tester.scrollUntilVisible(
                target,
                300,
                scrollable: list.first,
                maxScrolls: 20,
              );
            }
            await tester.ensureVisible(target.first);
            await tester.pump();
            await tester.tap(target.first, warnIfMissed: false);
            await _settle(tester, 8);
            await _shot(tester, 'design_routes/$name.png');
          } catch (e) {
            File('test/design_routes/$name.error.txt')
              ..createSync(recursive: true)
              ..writeAsStringSync('$e');
          }
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 31));
      }, _client);
    });
  }
}
