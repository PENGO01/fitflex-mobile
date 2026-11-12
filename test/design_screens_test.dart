// Screenshots of every role's tabs in light and dark, for design review.
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
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _shots = bool.fromEnvironment('DESIGN_SHOTS');
const _roles = ['member', 'trainer', 'gym_operator', 'vendor'];

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

void main() {
  setUpAll(_loadFonts);

  for (final role in _roles) {
    for (final mode in ['light', 'dark']) {
      testWidgets('$role tabs ($mode)', skip: !_shots, (tester) async {
        tester.view.physicalSize = const Size(390 * 2, 844 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await http.runWithClient(() async {
          final me = ((_fixtures[role] as Map?)?['GET /me'] as Map?)?['user'];
          SharedPreferences.setMockInitialValues({
            'token': role,
            'role': role,
            'user': jsonEncode(me ?? {'id': 'u_$role', 'userType': role}),
            'locale': 'en',
            'lang_selected': true,
            ThemeNotifier.prefsKey: mode,
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

          final bar = find.byType(NavigationBar);
          if (bar.evaluate().isEmpty) {
            await _shot(tester, 'design_shots/$role-0-landing-$mode.png');
          } else {
            final dests = find.descendant(
              of: bar,
              matching: find.byType(NavigationDestination),
            );
            final count = dests.evaluate().length;
            for (var i = 0; i < count; i++) {
              final label = tester
                  .widget<NavigationDestination>(dests.at(i))
                  .label
                  .toLowerCase()
                  .replaceAll(RegExp('[^a-z0-9]+'), '-');
              await tester.tap(dests.at(i));
              await _settle(tester);
              await _shot(tester, 'design_shots/$role-$i-$label-a-$mode.png');
              final scrollable = find.byType(Scrollable);
              if (scrollable.evaluate().isNotEmpty) {
                await tester.drag(scrollable.first, const Offset(0, -700));
                await _settle(tester, 2);
                await _shot(
                  tester,
                  'design_shots/$role-$i-$label-b-$mode.png',
                );
              }
            }
          }
          // Member profile lives behind the avatar in the app bar.
          final profile = find.byKey(const Key('member-nav-profile'));
          if (profile.evaluate().isNotEmpty) {
            await tester.tap(profile.first);
            await _settle(tester);
            await _shot(tester, 'design_shots/$role-9-profile-a-$mode.png');
            final sc = find.byType(Scrollable);
            if (sc.evaluate().isNotEmpty) {
              await tester.drag(sc.first, const Offset(0, -700));
              await _settle(tester, 2);
              await _shot(tester, 'design_shots/$role-9-profile-b-$mode.png');
            }
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 31));
        }, _client);
      });
    }
  }
}
