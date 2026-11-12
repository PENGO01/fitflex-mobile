// Whole-app regression: boots the real app (router, shells, screens) signed
// in as each role and visits every bottom-nav tab, in English and Swahili.
// Any exception or layout overflow fails the test.
//
// API responses are real ones recorded from a local backend
// (test/fixtures/regression.json). To refresh them:
//   1. flutter test test/app_regression_test.dart --dart-define=RECORD=true
//      (writes build/regression_requests.json: what each role asked for)
//   2. node ../fitflex-functions/scripts/record-app-fixtures.mjs
//      (fetches those from a local backend into the fixtures file)
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

const _record = bool.fromEnvironment('RECORD');
const _roles = ['member', 'trainer', 'gym_operator', 'vendor'];

final Map<String, dynamic> _fixtures = () {
  final f = File('test/fixtures/regression.json');
  return f.existsSync()
      ? jsonDecode(f.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};
}();
final Map<String, Set<String>> _requested = {};

/// Answers from the role's recorded responses. The token is the role name.
MockClient _client() => MockClient((req) async {
  final role = (req.headers['authorization'] ?? '').replaceFirst('Bearer ', '');
  final key = '${req.method} ${req.url.path}';
  (_requested[role] ??= {}).add(
    req.method == 'GET'
        ? '$key${req.url.hasQuery ? '?${req.url.query}' : ''}'
        : key,
  );
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

Future<void> _boot(WidgetTester tester, String role, String lang) async {
  final me = ((_fixtures[role] as Map?)?['GET /me'] as Map?)?['user'];
  SharedPreferences.setMockInitialValues({
    'token': role,
    'role': role,
    'user': jsonEncode(me ?? {'id': 'u_$role', 'userType': role}),
    'locale': lang,
    'lang_selected': true,
  });
  final api = ApiClient(baseUrl: 'http://fixtures.local');
  final auth = AuthState(api);
  await auth.hydrate();
  final locale = FFLocale()..set(Locale(lang));
  await tester.pumpWidget(
    FitFlexApp(
      api: api,
      auth: auth,
      locale: locale,
      themeNotifier: ThemeNotifier(),
    ),
  );
  // Splash animation, redirects and the shell's first loads.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<List<String>> _visitTabs(WidgetTester tester) async {
  final visited = <String>[];
  final bar = find.byType(NavigationBar);
  if (bar.evaluate().isEmpty) return visited;
  final dests = find.descendant(
    of: bar,
    matching: find.byType(NavigationDestination),
  );
  final count = dests.evaluate().length;
  for (var i = 0; i < count; i++) {
    final d = tester.widget<NavigationDestination>(dests.at(i));
    await tester.tap(dests.at(i));
    for (var k = 0; k < 6; k++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    visited.add(d.label);
    // Scroll the tab to the end so lazily built content renders too.
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.drag(scrollable.first, const Offset(0, -3000));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }
  return visited;
}

/// Real fonts, so text widths (and overflows) match the device, not the
/// test font's full-width squares.
Future<void> _loadFonts() async {
  Future<ByteData> f(String p) async =>
      ByteData.sublistView(File(p).readAsBytesSync());
  final sans = FontLoader('Plus Jakarta Sans');
  for (final w in [400, 500, 600, 700, 800]) {
    sans.addFont(f('assets/fonts/PlusJakartaSans-$w.ttf'));
  }
  await sans.load();
  final mono = FontLoader('JetBrains Mono');
  for (final w in [400, 500, 700]) {
    mono.addFont(f('assets/fonts/JetBrainsMono-$w.ttf'));
  }
  await mono.load();
  // Roboto too, for runs of builds that predate the Inter theme.
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

void main() {
  setUpAll(_loadFonts);
  tearDownAll(() {
    if (!_record) return;
    final out = File('build/regression_requests.json')
      ..createSync(recursive: true);
    out.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        for (final e in _requested.entries) e.key: e.value.toList()..sort(),
      }),
    );
  });

  for (final role in _roles) {
    for (final lang in ['en', 'sw']) {
      testWidgets('$role app boots and every tab renders ($lang)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await http.runWithClient(() async {
          await _boot(tester, role, lang);
          final tabs = await _visitTabs(tester);
          if (!_record) {
            expect(
              tabs,
              isNotEmpty,
              reason: '$role should land in a shell with a bottom nav',
            );
          }
          // Leave cleanly so periodic timers (QR refresh) stop.
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 31));
        }, _client);
      });
    }
  }
}
