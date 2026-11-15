import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/email_auth_screen.dart';
import 'package:fitflexmobile/screens/pin_flows.dart';
import 'package:fitflexmobile/screens/sign_up_screen.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';

// Identity V2 · I7d: registering, signing in and recovering a PIN that
// FitFlex keeps.

Map<String, dynamic> _session([String userType = 'member']) => {
  'token': 'jwt-new',
  'user': {
    'id': 'usr_1',
    'userType': userType,
    'approvalStatus': 'approved',
    'onboardingCompleted': true,
  },
};

class _FakeApi extends ApiClient {
  _FakeApi({this.pinLoginOn = true, this.pinResetOn = true})
    : super(baseUrl: 'http://localhost:0');

  bool pinLoginOn;
  bool pinResetOn;
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];
  final errors = <String, ApiException>{};
  Map<String, dynamic>? loginResponse;

  Map<String, dynamic> _do(
    String name,
    Map<String, dynamic> body,
    Map<String, dynamic> ok,
  ) {
    calls.add(name);
    bodies.add(body);
    final error = errors.remove(name);
    if (error != null) throw error;
    return ok;
  }

  @override
  Future<bool> pinLoginAvailable() async => pinLoginOn;
  @override
  Future<bool> pinResetAvailable() async => pinResetOn;

  @override
  Future<Map<String, dynamic>> pinLogin(
    Map<String, String> contact,
    String pin, {
    String? locale,
  }) async =>
      _do('login', {...contact, 'pin': pin}, loginResponse ?? _session());

  @override
  Future<Map<String, dynamic>> pinSetup({
    required String setupToken,
    String? code,
    required String pin,
  }) async => _do('setup', {
    'setupToken': setupToken,
    'code': ?code,
    'pin': pin,
  }, _session());

  @override
  Future<Map<String, dynamic>> registerStart(
    Map<String, String> contact,
    String? locale,
  ) async => _do(
    'registerStart',
    {...contact, 'locale': ?locale},
    {'sent': true, 'identifierValue': '+255712345678', 'resendAfterSeconds': 0},
  );

  @override
  Future<Map<String, dynamic>> registerConfirm(
    Map<String, String> contact,
    String code,
  ) async => _do(
    'registerConfirm',
    {...contact, 'code': code},
    {'registrationToken': 'reg-token'},
  );

  @override
  Future<Map<String, dynamic>> registerComplete({
    required String registrationToken,
    required String role,
    required String pin,
  }) async => _do('registerComplete', {
    'registrationToken': registrationToken,
    'role': role,
    'pin': pin,
  }, _session(role == 'gym_owner' ? 'gym_operator' : role));

  @override
  Future<Map<String, dynamic>> pinResetStart(
    Map<String, String> contact,
    String? locale,
  ) async => _do(
    'resetStart',
    {...contact},
    {
      'sent': true,
      'identifierValue': 'amina@example.com',
      'resendAfterSeconds': 0,
    },
  );

  @override
  Future<Map<String, dynamic>> pinResetConfirm(
    Map<String, String> contact,
    String code,
  ) async => _do(
    'resetConfirm',
    {...contact, 'code': code},
    {'resetToken': 'reset-token'},
  );

  @override
  Future<Map<String, dynamic>> pinResetComplete(
    String resetToken,
    String pin,
  ) async =>
      _do('resetComplete', {'resetToken': resetToken, 'pin': pin}, _session());

  @override
  Future<Map<String, dynamic>> changePin(
    String currentPin,
    String newPin,
  ) async => _do('changePin', {
    'currentPin': currentPin,
    'newPin': newPin,
  }, _session());

  // What follows a sign-in; nothing to load in these tests.
  @override
  Future<Map<String, dynamic>> myInvitations() async =>
      throw ApiException(404, {'error': 'not_found'});
  @override
  Future<Map<String, dynamic>> myIdentifiers() async =>
      throw ApiException(404, {'error': 'not_found'});
}

Future<AuthState> _auth(_FakeApi api) async {
  final auth = AuthState(api);
  await auth.loadSignInOptions();
  return auth;
}

Widget _app(AuthState auth, Widget home) {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(path: '/start', builder: (_, _) => home),
      GoRoute(
        path: AppRoutes.auth,
        builder: (_, _) => const Scaffold(body: Text('sign-in screen')),
      ),
    ],
    // Wherever a finished flow sends the person.
    errorBuilder: (_, state) => Scaffold(body: Text('opened ${state.uri}')),
  );
  return AppScope(
    api: auth.api,
    auth: auth,
    child: ThemeScope(
      notifier: ThemeNotifier(),
      child: FFLocaleScope(
        notifier: FFLocale(),
        child: MaterialApp.router(
          theme: buildTheme(),
          routerConfig: router,
          supportedLocales: const [Locale('en'), Locale('sw')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    ),
  );
}

Future<void> _typePin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit).last);
    await tester.pump();
  }
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void _tall(WidgetTester tester, {double width = 1080}) {
  tester.view.physicalSize = Size(width, 3200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the sign-in options follow the backend', () async {
    final off = await _auth(_FakeApi(pinLoginOn: false, pinResetOn: false));
    expect(off.pinLoginEnabled, isFalse);
    expect(off.pinResetEnabled, isFalse);
    final on = await _auth(_FakeApi());
    expect(on.pinLoginEnabled, isTrue);
    expect(on.pinResetEnabled, isTrue);
    expect(contactOf(' 0712 345 678 '), {'phone': '0712 345 678'});
    expect(contactOf('A@b.co'), {'email': 'A@b.co'});
  });

  testWidgets('register: code, then the PIN typed twice, then signed in', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi();
    final auth = await _auth(api);
    await auth.setRole('trainer');
    await tester.pumpWidget(
      _app(auth, const RegisterFlowScreen(contact: '0712345678')),
    );
    await tester.pumpAndSettle();
    expect(api.calls, ['registerStart']);
    expect(api.bodies.last, {'phone': '0712345678', 'locale': 'en'});
    expect(find.textContaining('+255712345678'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('pin-flow-code')), '123456');
    await tester.tap(find.byKey(const Key('pin-flow-code-continue')));
    await tester.pumpAndSettle();
    expect(api.bodies.last, {'phone': '0712345678', 'code': '123456'});
    expect(find.text('Choose a 4-digit PIN'), findsOneWidget);

    // A mismatch starts the PIN again and creates nothing.
    await _typePin(tester, '4821');
    expect(find.text('Type your PIN again'), findsOneWidget);
    await _typePin(tester, '4822');
    expect(find.text('PINs do not match.'), findsOneWidget);
    expect(find.text('Choose a 4-digit PIN'), findsOneWidget);
    expect(api.calls.contains('registerComplete'), isFalse);

    await _typePin(tester, '4821');
    await _typePin(tester, '4821');
    expect(api.bodies.last, {
      'registrationToken': 'reg-token',
      'role': 'trainer',
      'pin': '4821',
    });
    expect(auth.isSignedIn, isTrue);
    expect(auth.token, 'jwt-new');
    expect(find.textContaining('opened'), findsOneWidget);
  });

  testWidgets('register: an account that already exists is sent to sign-in', (
    tester,
  ) async {
    final api = _FakeApi()
      ..errors['registerStart'] = ApiException(409, {
        'error': 'already_registered',
      });
    final auth = await _auth(api);
    await tester.pumpWidget(
      _app(auth, const RegisterFlowScreen(contact: 'amina@example.com')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('An account already uses this mobile number or email.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('pin-flow-code')), findsNothing);
    await tester.tap(find.byKey(const Key('pin-flow-go-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('sign-in screen'), findsOneWidget);
  });

  testWidgets('register: a network sign-up limit is not called wrong tries', (
    tester,
  ) async {
    final api = _FakeApi()
      ..errors['registerStart'] = ApiException(429, {
        'error': 'too_many_attempts',
        'retryAfterSeconds': 61,
      });
    final auth = await _auth(api);
    await tester.pumpWidget(
      _app(auth, const RegisterFlowScreen(contact: '0712345678')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Too many sign-ups are coming from your network right now. Try again in 2 minutes, or switch between Wi-Fi and mobile data.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('wrong tries'), findsNothing);
  });

  testWidgets('register: send failures keep the could-not-send message', (
    tester,
  ) async {
    for (final code in ['code_not_sent', 'registration_busy']) {
      final api = _FakeApi()
        ..errors['registerStart'] = ApiException(503, {'error': code});
      final auth = await _auth(api);
      await tester.pumpWidget(
        _app(auth, const RegisterFlowScreen(contact: '0712345678')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('We could not send the code right now. Try again later.'),
        findsOneWidget,
        reason: code,
      );
      expect(find.textContaining('wrong tries'), findsNothing, reason: code);
      expect(find.byKey(const Key('pin-flow-code')), findsNothing);
    }
  });

  testWidgets('sign-up opens the code flow only when FitFlex keeps the PIN', (
    tester,
  ) async {
    // Wide enough for the test font on the Google button.
    _tall(tester, width: 1800);
    final api = _FakeApi();
    final auth = await _auth(api);
    await tester.pumpWidget(_app(auth, const SignUpScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '0712345678');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    expect(api.calls, ['registerStart']);
    expect(find.byKey(const Key('pin-flow-code')), findsOneWidget);
  });

  testWidgets('sign in with a number and PIN; a wrong PIN says so', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi()
      ..errors['login'] = ApiException(401, {'error': 'invalid_credentials'});
    final auth = await _auth(api);
    await tester.pumpWidget(
      _app(auth, const EmailAuthScreen(initialEmail: '0712345678')),
    );
    await tester.pumpAndSettle();

    await _typePin(tester, '0000');
    expect(
      find.text('That mobile number, email or PIN is not right.'),
      findsOneWidget,
    );
    expect(auth.isSignedIn, isFalse);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    api.errors['login'] = ApiException(429, {
      'error': 'too_many_attempts',
      'retryAfterSeconds': 900,
    });
    await _typePin(tester, '0000');
    expect(
      find.text('Too many wrong tries. Try again in 15 minutes.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await _typePin(tester, '4821');
    expect(api.bodies.last, {'phone': '0712345678', 'pin': '4821'});
    expect(auth.isSignedIn, isTrue);
    expect(find.textContaining('opened'), findsOneWidget);
  });

  testWidgets(
    'an existing user moves their PIN across: code, and a new PIN when the old one was longer',
    (tester) async {
      _tall(tester);
      final api = _FakeApi()
        ..loginResponse = {
          'setupRequired': true,
          'setupToken': 'setup-token',
          'verificationRequired': true,
          'pinChangeRequired': true,
          'identifierValue': 'amina@example.com',
          'resendAfterSeconds': 0,
        };
      final auth = await _auth(api);
      await tester.pumpWidget(
        _app(auth, const EmailAuthScreen(initialEmail: 'amina@example.com')),
      );
      await tester.pumpAndSettle();
      await _typePin(tester, '135790');
      expect(api.bodies.last, {'email': 'amina@example.com', 'pin': '135790'});
      expect(find.text('One-time check'), findsOneWidget);
      expect(auth.isSignedIn, isFalse);

      await tester.enterText(find.byKey(const Key('pin-flow-code')), '654321');
      await tester.tap(find.byKey(const Key('pin-flow-code-continue')));
      await tester.pumpAndSettle();
      expect(
        api.calls.contains('setup'),
        isFalse,
        reason: 'the PIN comes first',
      );
      await _typePin(tester, '7310');
      await _typePin(tester, '7310');
      expect(api.bodies.last, {
        'setupToken': 'setup-token',
        'code': '654321',
        'pin': '7310',
      });
      expect(auth.isSignedIn, isTrue);
    },
  );

  testWidgets(
    'an existing user with a four-digit PIN keeps it after the code',
    (tester) async {
      _tall(tester);
      final api = _FakeApi()
        ..loginResponse = {
          'setupRequired': true,
          'setupToken': 'setup-token',
          'verificationRequired': true,
          'pinChangeRequired': false,
          'identifierValue': 'amina@example.com',
        };
      final auth = await _auth(api);
      await tester.pumpWidget(
        _app(auth, const EmailAuthScreen(initialEmail: 'amina@example.com')),
      );
      await tester.pumpAndSettle();
      await _typePin(tester, '2468');
      await tester.enterText(find.byKey(const Key('pin-flow-code')), '654321');
      await tester.tap(find.byKey(const Key('pin-flow-code-continue')));
      await tester.pumpAndSettle();
      expect(api.bodies.last, {
        'setupToken': 'setup-token',
        'code': '654321',
        'pin': '2468',
      });
      expect(auth.isSignedIn, isTrue);
    },
  );

  testWidgets('forgot PIN: from the sign-in screen to a new PIN', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi();
    final auth = await _auth(api);
    await tester.pumpWidget(
      _app(auth, const EmailAuthScreen(initialEmail: 'amina@example.com')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forgot-pin')));
    await tester.pumpAndSettle();
    expect(find.text('Reset your PIN'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('pin-flow-contact')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      'amina@example.com',
    );

    await tester.tap(find.byKey(const Key('pin-flow-send')));
    await tester.pumpAndSettle();
    expect(api.bodies.last, {'email': 'amina@example.com'});
    await tester.enterText(find.byKey(const Key('pin-flow-code')), '111222');
    await tester.tap(find.byKey(const Key('pin-flow-code-continue')));
    await tester.pumpAndSettle();
    await _typePin(tester, '5050');
    await _typePin(tester, '5050');
    expect(api.calls, ['resetStart', 'resetConfirm', 'resetComplete']);
    expect(api.bodies.last, {'resetToken': 'reset-token', 'pin': '5050'});
    expect(auth.isSignedIn, isTrue);
  });

  testWidgets('forgot PIN is switched off while the backend has it off', (
    tester,
  ) async {
    _tall(tester);
    final auth = await _auth(_FakeApi(pinResetOn: false));
    await tester.pumpWidget(
      _app(auth, const EmailAuthScreen(initialEmail: 'amina@example.com')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextButton>(find.byKey(const Key('forgot-pin'))).onPressed,
      isNull,
    );
  });

  testWidgets('change PIN: checks the new PIN, reports a wrong current one', (
    tester,
  ) async {
    final api = _FakeApi();
    final auth = await _auth(api);
    await auth.signIn('jwt-old', {'id': 'usr_1', 'userType': 'trainer'});
    await tester.pumpWidget(_app(auth, const Scaffold(body: ChangePinTile())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('change-pin-tile')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('change-pin-current')), '4821');
    await tester.enterText(find.byKey(const Key('change-pin-new')), '7310');
    await tester.enterText(find.byKey(const Key('change-pin-again')), '7311');
    await tester.tap(find.byKey(const Key('change-pin-save')));
    await tester.pumpAndSettle();
    expect(find.text('PINs do not match.'), findsOneWidget);
    expect(api.calls, isEmpty);

    api.errors['changePin'] = ApiException(400, {
      'error': 'current_pin_incorrect',
    });
    await tester.enterText(find.byKey(const Key('change-pin-again')), '7310');
    await tester.tap(find.byKey(const Key('change-pin-save')));
    await tester.pumpAndSettle();
    expect(find.text('Your current PIN is not right.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('change-pin-save')));
    await tester.pumpAndSettle();
    expect(api.bodies.last, {'currentPin': '4821', 'newPin': '7310'});
    expect(auth.token, 'jwt-new', reason: 'the new session replaces the old');
    expect(
      find.text('Your PIN was changed. Other devices were signed out.'),
      findsOneWidget,
    );
  });

  testWidgets('the vendor screen\'s change-PIN button opens the same dialog', (
    tester,
  ) async {
    final api = _FakeApi();
    final auth = await _auth(api);
    await auth.signIn('jwt-old', {'id': 'usr_1', 'userType': 'vendor_staff'});
    await tester.pumpWidget(
      _app(auth, Scaffold(appBar: AppBar(actions: const [ChangePinButton()]))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('change-pin-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('change-pin-current')), '4821');
    await tester.enterText(find.byKey(const Key('change-pin-new')), '7310');
    await tester.enterText(find.byKey(const Key('change-pin-again')), '7310');
    await tester.tap(find.byKey(const Key('change-pin-save')));
    await tester.pumpAndSettle();
    expect(api.bodies.last, {'currentPin': '4821', 'newPin': '7310'});
    expect(auth.token, 'jwt-new');
    expect(
      find.text('Your PIN was changed. Other devices were signed out.'),
      findsOneWidget,
    );

    // Let the first message finish (messages queue), then: an account with no
    // FitFlex PIN is told how to set one.
    ScaffoldMessenger.of(
      tester.element(find.byKey(const Key('change-pin-button'))),
    ).clearSnackBars();
    await tester.pumpAndSettle();
    api.errors['changePin'] = ApiException(409, {'error': 'pin_not_set'});
    await tester.tap(find.byKey(const Key('change-pin-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('change-pin-current')), '4821');
    await tester.enterText(find.byKey(const Key('change-pin-new')), '7310');
    await tester.enterText(find.byKey(const Key('change-pin-again')), '7310');
    await tester.tap(find.byKey(const Key('change-pin-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('This account has no PIN yet.'), findsOneWidget);
  });

  testWidgets(
    'the change-PIN button is hidden while FitFlex does not keep PINs',
    (tester) async {
      final auth = await _auth(_FakeApi(pinLoginOn: false));
      await tester.pumpWidget(
        _app(
          auth,
          Scaffold(appBar: AppBar(actions: const [ChangePinButton()])),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('change-pin-button')), findsNothing);
    },
  );

  testWidgets('change PIN is hidden while FitFlex does not keep PINs', (
    tester,
  ) async {
    final auth = await _auth(_FakeApi(pinLoginOn: false));
    await tester.pumpWidget(_app(auth, const Scaffold(body: ChangePinTile())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('change-pin-tile')), findsNothing);
  });
}
