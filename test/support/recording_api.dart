// Characterization-test infrastructure: a recording fake backend at the HTTP
// level, plus a page host and a few behaviour-based finders.
//
// Why HTTP and not an ApiClient subclass: the point of these tests is to pin
// the exact method, path and JSON body a screen sends, so the real ApiClient
// stays in the loop and only `package:http` is replaced (the same technique as
// test/app_regression_test.dart).
//
// Finders here are written in terms of behaviour (visible text, whether a
// control is enabled) so they keep working when raw Material controls are
// swapped for the shared FF* widgets.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One request the app sent.
class RecordedRequest {
  RecordedRequest(
    this.method,
    this.path,
    this.query,
    this.body, [
    this.headers = const {},
  ]);
  final String method;

  /// Request headers, lower-cased names.
  final Map<String, String> headers;
  final String path;
  final String query;

  /// Decoded JSON body, or null when the request had none.
  final Object? body;

  String get key => '$method $path';
  @override
  String toString() =>
      '$key${query.isEmpty ? '' : '?$query'} ${jsonEncode(body)}';
}

/// A seeded answer with its own status and a raw body (not JSON-encoded),
/// e.g. the HTML 404 page a backend returns for a route it does not have.
class RawResponse {
  const RawResponse(this.status, this.body);
  final int status;
  final String body;
}

/// A fake backend: answers from seeded JSON by "METHOD /path", records every
/// request, and can fail or hold individual routes.
class RecordingApi {
  final List<RecordedRequest> requests = [];
  final Map<String, FutureOr<Object?> Function(RecordedRequest)> _routes = {};
  final Map<String, int> _failures = {};
  final Map<String, Completer<void>> _holds = {};

  /// Seeds a JSON answer. Un-seeded GETs answer 404 `not_seeded`; un-seeded
  /// writes answer 200 `{}`.
  void on(String key, Object? body) => _routes[key] = (_) => body;

  /// Seeds a computed answer.
  void onCall(
    String key,
    FutureOr<Object?> Function(RecordedRequest) handler,
  ) => _routes[key] = handler;

  /// Makes [key] answer with [status] and an error body.
  void fail(String key, [int status = 500, Object? body]) {
    _failures[key] = status;
    if (body != null) _routes['fail:$key'] = (_) => body;
  }

  /// Stops [key] failing again.
  void heal(String key) => _failures.remove(key);

  /// Holds [key] until the returned completer completes (a loading state).
  Completer<void> hold(String key) => _holds[key] = Completer<void>();

  /// Requests with this method and path, in order.
  List<RecordedRequest> where(String method, String path) =>
      requests.where((r) => r.method == method && r.path == path).toList();

  /// The single request with this method and path (fails if not exactly one).
  RecordedRequest only(String method, String path) {
    final found = where(method, path);
    expect(
      found,
      hasLength(1),
      reason: 'expected exactly one $method $path, saw: $requests',
    );
    return found.single;
  }

  bool sent(String method, String path) => where(method, path).isNotEmpty;

  /// Forget what was recorded so far (after the page finished loading).
  void clear() => requests.clear();

  Future<http.Response> _handle(http.Request req) async {
    // A multipart upload (a photo) is recorded by its size, not decoded.
    final multipart = (req.headers['content-type'] ?? '').startsWith(
      'multipart/',
    );
    final raw = multipart ? '' : req.body;
    final rec = RecordedRequest(
      req.method,
      req.url.path,
      req.url.query,
      multipart
          ? {
              'multipart': true,
              'bytes': req.bodyBytes.length,
              // The text parts (the file part has a filename and is left out).
              'fields': {
                for (final m in RegExp(
                  r'form-data; name="([^"]+)"\r\n\r\n([^\r]*)\r\n',
                ).allMatches(latin1.decode(req.bodyBytes)))
                  m.group(1)!: m.group(2)!,
              },
            }
          : raw.isEmpty
          ? null
          : jsonDecode(raw),
      req.headers.map((k, v) => MapEntry(k.toLowerCase(), v)),
    );
    requests.add(rec);
    final hold = _holds[rec.key];
    if (hold != null) await hold.future;
    final status = _failures[rec.key];
    if (status != null) {
      final body = _routes['fail:${rec.key}']?.call(rec) ?? {'error': 'failed'};
      return http.Response(
        jsonEncode(await body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    final route = _routes[rec.key];
    if (route == null) {
      if (req.method == 'GET') {
        return http.Response(jsonEncode({'error': 'not_seeded'}), 404);
      }
      return http.Response('{}', 200);
    }
    final out = await route(rec);
    if (out is RawResponse) return http.Response(out.body, out.status);
    return http.Response(
      out is String ? out : jsonEncode(out),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  /// Runs [body] with `package:http` answered by this fake.
  Future<T> run<T>(Future<T> Function() body) =>
      http.runWithClient(body, () => MockClient(_handle));
}

/// Real fonts (as test/app_regression_test.dart does) so widths, and
/// therefore overflows, match a device rather than the square test font.
Future<void> loadAppFonts() async {
  Future<ByteData> f(String p) async =>
      ByteData.sublistView(File(p).readAsBytesSync());
  // The app's typeface (FitFlex DS v1.0).
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
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    const material = '/bin/cache/artifacts/material_fonts';
    final icons = File('$flutterRoot$material/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(f(icons.path))).load();
    }
  }
}

/// What a test gets for one pumped page.
class PageHost {
  PageHost(this.tester, this.api, this.auth, this.lang);
  final WidgetTester tester;
  final RecordingApi api;
  final AuthState auth;
  final String lang;

  /// The page's own copy for [key] in this host's language.
  String tr(String key) => (FFLocale()..set(Locale(lang))).t(key);

  /// Dismisses any visible snackbar (it can cover the bottom navigation).
  Future<void> dismissSnacks() async {
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold).first),
    ).clearSnackBars();
    await tester.pumpAndSettle();
  }

  /// A SnackBar that shows [text].
  Finder snack(String text) =>
      find.descendant(of: find.byType(SnackBar), matching: find.text(text));
}

/// Pumps [page] at "/" of a small router (so `context.go(...)` works) inside
/// the app's scopes, signed in as [user].
Future<PageHost> pumpPage(
  WidgetTester tester,
  RecordingApi api,
  Widget page, {
  Map<String, dynamic> user = const {'id': 'u1', 'userType': 'vendor'},
  String lang = 'en',
  double textScale = 1.0,
  Size size = const Size(360, 740),
  bool invitesEnabled = false,
  bool settle = true,
  bool keepRequests = false,
  String initialLocation = '/',
  List<RouteBase> extraRoutes = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final client = ApiClient(baseUrl: 'http://fixtures.local');
  final auth = AuthState(client);
  await auth.signIn('token', Map<String, dynamic>.from(user));
  if (invitesEnabled) {
    api.on('GET /me/invitations', {'invitations': []});
    await auth.refreshInvitations();
  }
  final locale = FFLocale()..set(Locale(lang));
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: page),
      ),
      GoRoute(
        path: AppRoutes.language,
        builder: (_, _) => const Scaffold(body: Text('ROUTE-LANGUAGE')),
      ),
      GoRoute(
        path: AppRoutes.verification,
        builder: (_, _) => const Scaffold(body: Text('ROUTE-VERIFICATION')),
      ),
      ...extraRoutes,
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    AppScope(
      api: client,
      auth: auth,
      child: ThemeScope(
        notifier: ThemeNotifier(),
        child: FFLocaleScope(
          notifier: locale,
          child: MaterialApp.router(
            routerConfig: router,
            theme: buildTheme(),
            supportedLocales: const [Locale('en'), Locale('sw')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, c) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: c!,
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
    if (!keepRequests) api.clear();
  }
  return PageHost(tester, api, auth, lang);
}

/// A testWidgets that gives the body a fresh [RecordingApi] and answers
/// `package:http` from it.
void apiTest(
  String name,
  Future<void> Function(WidgetTester tester, RecordingApi api) body,
) {
  testWidgets(name, (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = RecordingApi();
    await api.run(() async {
      await body(tester, api);
      // Leave cleanly so periodic timers stop.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}

// ── behaviour finders ───────────────────────────────────────────────────

bool _isButtonLike(Widget w) =>
    w is FFButton ||
    w is ButtonStyleButton ||
    w is FloatingActionButton ||
    w is IconButton;

/// The outermost button (shared FFButton, or any Material button) that
/// shows [label]. Matches nothing when there is none.
Finder buttonLabelled(String label) => find.byElementPredicate((element) {
  if (!_isButtonLike(element.widget)) return false;
  var hasLabel = false;
  void scan(Element e) {
    if (hasLabel) return;
    final w = e.widget;
    if (w is Text && w.data == label) {
      hasLabel = true;
      return;
    }
    e.visitChildElements(scan);
  }

  element.visitChildElements(scan);
  if (!hasLabel) return false;
  var nested = false;
  element.visitAncestorElements((a) {
    if (_isButtonLike(a.widget)) {
      nested = true;
      return false;
    }
    return true;
  });
  return !nested;
}, description: 'button labelled "$label"');

/// Whether the control found by [f] (a button, or something inside one, or
/// a keyed button itself) can be pressed right now.
bool isEnabled(WidgetTester tester, Finder f) {
  final element = f.evaluate().single;
  Widget? hit;
  if (_isButtonLike(element.widget)) {
    hit = element.widget;
  } else {
    element.visitAncestorElements((a) {
      if (_isButtonLike(a.widget)) {
        hit = a.widget;
        return false;
      }
      return true;
    });
  }
  final w = hit;
  if (w is FFButton) return w.onPressed != null && !w.loading;
  if (w is ButtonStyleButton) return w.onPressed != null;
  if (w is FloatingActionButton) return w.onPressed != null;
  if (w is IconButton) return w.onPressed != null;
  throw StateError('No button around $f');
}

/// Any loading indicator, whether raw or the shared FFSpinner.
Finder get spinner => find.byType(CircularProgressIndicator);

/// Taps [f], scrolling it into view first if it sits in a scroll view.
Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Types into the text field [f] (a keyed TextField or FFTextField).
Future<void> typeInto(WidgetTester tester, Finder f, String text) async {
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pump();
}

/// The vertical order in which [texts] appear on screen.
List<String> verticalOrder(WidgetTester tester, List<String> texts) {
  final present = texts.where((t) => find.text(t).evaluate().isNotEmpty);
  final sorted = present.toList()
    ..sort(
      (a, b) => tester
          .getTopLeft(find.text(a).first)
          .dy
          .compareTo(tester.getTopLeft(find.text(b).first).dy),
    );
  return sorted;
}

/// The current text of the text field [f] (a TextField or FFTextField, or
/// anything wrapping an EditableText).
String textOf(WidgetTester tester, Finder f) {
  final editable = find.descendant(
    of: f,
    matching: find.byType(EditableText),
    matchRoot: true,
  );
  return tester.widget<EditableText>(editable).controller.text;
}

/// Taps [f] (a dialog's confirm button) and settles.
///
/// Several screens dispose a dialog text field's controller as soon as the
/// dialog is popped, while it is still animating out. If the field still has
/// focus, the focus change rebuilds it with the disposed controller and debug
/// builds report "A TextEditingController was used after being disposed".
/// That is a latent app bug, not what these tests characterize, so the field
/// is unfocused first (as closing the keyboard would). A fixed app passes the
/// same tests.
Future<void> tapAndSettleDialogClose(WidgetTester tester, Finder f) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Runs [body] collecting (instead of failing on) framework error reports.
/// Each is returned as its full report text, rendered at the moment it was
/// reported (the widget tree it describes may be gone afterwards).
Future<List<String>> captureFlutterErrors(Future<void> Function() body) async {
  final previous = FlutterError.onError;
  final errors = <String>[];
  FlutterError.onError = (details) {
    try {
      errors.add(details.toDiagnosticsNode().toStringDeep());
    } catch (_) {
      errors.add(details.exceptionAsString());
    }
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}
