// Security activity (S4c): the "This wasn't me" report of a web check-in
// (fitflex-functions docs/security-incident-report-api.md).

import 'dart:async';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/security/security_activity_page.dart';
import 'package:fitflexmobile/screens/security/security_report_sheet.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _event(
  int n, {
  String kind = 'web_checkin',
  Map<String, dynamic>? report,
}) => {
  'id': 'e$n',
  'kind': kind,
  'occurredAt': '2026-11-09T11:30:00.000Z',
  'gym': {'id': 'g1', 'name': 'Iron Gym'},
  'channel': 'web',
  'status': 'inbox',
  'report': report,
};

Map<String, dynamic> _reported(
  String status, {
  bool? pending,
  bool? retryable,
}) => {
  'incidentId': 'inc1',
  'status': status,
  'reportedAt': '2026-11-10T08:00:00.000Z',
  'protectionPending': ?pending,
  'protectionRetryable': ?retryable,
};

const _failedProtection = <String, dynamic>{
  'requested': true,
  'sessionsEnded': false,
  'pinResetRequired': 'not_applicable',
  'failed': true,
};

Map<String, dynamic> _result({
  bool idempotent = false,
  bool signedOut = false,
  Map<String, dynamic> protection = const {
    'requested': false,
    'sessionsEnded': false,
    'pinResetRequired': false,
  },
}) => {
  'ok': true,
  'idempotent': idempotent,
  'incident': {
    'id': 'inc1',
    'status': 'open',
    'reportedAt': '2026-11-10T08:00:00.000Z',
  },
  'protection': protection,
  'signedOut': signedOut,
};

class _Api extends ApiClient {
  _Api({this.pinOn = false}) : super(baseUrl: 'http://localhost:0');

  final bool pinOn;
  bool reportEnabled = true;
  List<Map<String, dynamic>> events = [_event(1)];
  int lists = 0;

  /// Thrown by every list read after the first.
  Object? listError;

  /// Answers to the report calls, in order: a map, or something to throw.
  final answers = <Object>[];

  /// How the list shows an event once a report call has answered. The
  /// default is an older backend's: no protection fields.
  Map<String, dynamic> listed = _reported('open');

  /// A report call that throws was still taken up by the server: the list
  /// shows [listed] afterwards.
  bool recordedOnError = false;

  /// When set, a report call waits for it.
  Completer<void>? gate;
  final reports = <({String eventId, bool secureAccount})>[];

  @override
  Future<Map<String, dynamic>> securityActivity({
    int limit = 20,
    String? before,
  }) async {
    lists++;
    final error = listError;
    if (error != null && lists > 1) throw error;
    return {'events': events, 'reportEnabled': reportEnabled};
  }

  @override
  Future<Map<String, dynamic>> reportSecurityActivity(
    String eventId, {
    bool secureAccount = true,
  }) async {
    reports.add((eventId: eventId, secureAccount: secureAccount));
    await gate?.future;
    final answer = answers.removeAt(0);
    if (answer is Map<String, dynamic>) {
      // The server now lists the event as reported.
      events = [
        for (final e in events)
          e['id'] == eventId ? {...e, 'report': listed} : e,
      ];
      return answer;
    }
    if (recordedOnError) {
      events = [
        for (final e in events)
          e['id'] == eventId ? {...e, 'report': listed} : e,
      ];
    }
    throw answer;
  }

  @override
  Future<Map<String, dynamic>> signInOptions() async => {
    'pinLogin': pinOn,
    'pinReset': pinOn,
  };
}

Widget _app(_Api api, AuthState auth, {String lang = 'en', double scale = 1}) =>
    AppScope(
      api: api,
      auth: auth,
      child: FFLocaleScope(
        notifier: FFLocale()..set(Locale(lang)),
        child: MaterialApp(
          theme: buildTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const SecurityActivityPage(),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls [finder] into view.
Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

const _action = Key('security-report-e1');
const _secure = Key('security-report-secure');
const _only = Key('security-report-only');
const _cancel = Key('security-report-cancel');
const _retry = Key('security-report-retry-e1');
const _wait = Key('security-report-wait-e1');
const _support = Key('security-report-support-e1');
const _notice = Key('security-report-notice-e1');
const _cooldown = Duration(seconds: 60);

bool _enabled(WidgetTester tester, Key key) {
  final before = tester.widget<FFButton>(find.byKey(key));
  return before.onPressed != null;
}

const _changePin = Key('security-report-change-pin-e1');
const _forgotPin = Key('security-report-forgot-pin-e1');
const _signedOutOk = Key('security-report-signed-out-ok');

Future<AuthState> _signedIn(_Api api) async {
  final auth = AuthState(api);
  await auth.signIn('tok', {'id': 'u1', 'userType': 'member'});
  await auth.loadSignInOptions(force: true);
  return auth;
}

/// Opens the page, then the sheet, and taps [choice].
Future<AuthState> _open(
  WidgetTester tester,
  _Api api, {
  Key? choice,
  String lang = 'en',
  double scale = 1,
}) async {
  final auth = await _signedIn(api);
  await tester.pumpWidget(_app(api, auth, lang: lang, scale: scale));
  await _settle(tester);
  if (choice == null) return auth;
  await _show(tester, find.byKey(_action));
  await tester.tap(find.byKey(_action));
  await _settle(tester);
  await _show(tester, find.byKey(choice));
  await tester.tap(find.byKey(choice));
  await _settle(tester);
  return auth;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('when the action shows', () {
    testWidgets('hidden while reportEnabled is false', (tester) async {
      final api = _Api()..reportEnabled = false;
      await _open(tester, api);
      expect(find.text('Iron Gym'), findsOneWidget);
      expect(find.text("This wasn't me"), findsNothing);
      expect(find.byKey(_action), findsNothing);
      // Exactly the S4a row: one semantics label, no report words.
      expect(
        find.bySemanticsLabel(
          'Check-in from a web browser, Iron Gym, 9 Nov 2026, 14:30 EAT, '
          'Alert sent',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shown on web check-ins only', (tester) async {
      final api = _Api()
        ..events = [_event(1), _event(2, kind: 'something_new')];
      await _open(tester, api);
      expect(find.text("This wasn't me"), findsOneWidget);
      expect(find.byKey(_action), findsOneWidget);
      expect(find.byKey(const Key('security-report-e2')), findsNothing);
      expect(
        find.bySemanticsLabel(
          "This wasn't me. Report this check-in to FitFlex support",
        ),
        findsOneWidget,
      );
      // At least 48 high.
      expect(
        tester.getSize(find.byKey(_action)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('hidden once reported; a chip says how far it is', (
      tester,
    ) async {
      final api = _Api()
        ..events = [
          _event(1, report: _reported('open')),
          _event(2, report: _reported('acknowledged')),
          _event(3, report: _reported('resolved')),
          _event(4, report: _reported('something_new')),
        ];
      await _open(tester, api);
      expect(find.text("This wasn't me"), findsNothing);
      expect(find.text('Reported'), findsNWidgets(2));
      expect(find.text('Being reviewed'), findsOneWidget);
      expect(find.text('Reviewed'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Check-in from a web browser, Iron Gym, 9 Nov 2026, 14:30 EAT, '
          'Alert sent, Being reviewed',
        ),
        findsOneWidget,
      );
    });
  });

  group('sheet', () {
    testWidgets('says what happens and offers both choices', (tester) async {
      final api = _Api();
      await _open(tester, api);
      await tester.tap(find.byKey(_action));
      await _settle(tester);
      expect(find.text('Report this check-in'), findsOneWidget);
      expect(
        find.text('We will record a report for FitFlex support to review.'),
        findsOneWidget,
      );
      expect(
        find.text('The visit is not removed automatically.'),
        findsOneWidget,
      );
      expect(find.text('Report and secure my account'), findsOneWidget);
      expect(
        find.text(
          'Signs you out on every device. If you sign in with a PIN, you '
          'then set a new one with Forgot PIN.',
        ),
        findsOneWidget,
      );
      expect(find.text('Report only'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      for (final k in [_secure, _only, _cancel]) {
        expect(tester.getSize(find.byKey(k)).height, greaterThanOrEqualTo(48));
      }

      await tester.tap(find.byKey(_cancel));
      await _settle(tester);
      expect(find.text('Report this check-in'), findsNothing);
      expect(api.reports, isEmpty);
      expect(find.byKey(_action), findsOneWidget);
    });
  });

  group('results', () {
    testWidgets('report only: confirmation, chip and a fresh list', (
      tester,
    ) async {
      final api = _Api()..answers.add(_result());
      final auth = await _open(tester, api, choice: _only);
      expect(api.reports.single, (eventId: 'e1', secureAccount: false));
      expect(
        find.text('Report sent. FitFlex support will review it.'),
        findsOneWidget,
      );
      expect(find.text('Reported'), findsOneWidget);
      expect(find.byKey(_action), findsNothing);
      expect(api.lists, 2);
      expect(auth.isSignedIn, isTrue);
    });

    testWidgets('secured with a PIN: told to use Forgot PIN, then signed '
        'out', (tester) async {
      final api = _Api()
        ..answers.add(
          _result(
            signedOut: true,
            protection: {
              'requested': true,
              'sessionsEnded': true,
              'pinResetRequired': true,
            },
          ),
        );
      final auth = await _open(tester, api, choice: _secure);
      expect(api.reports.single, (eventId: 'e1', secureAccount: true));
      expect(find.text('You have been signed out'), findsOneWidget);
      expect(find.textContaining('use Forgot PIN'), findsOneWidget);
      // Still this session until the member has read it.
      expect(auth.isSignedIn, isTrue);
      await tester.tap(find.byKey(_signedOutOk));
      await _settle(tester);
      expect(auth.isSignedIn, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token'), isNull);
      expect(prefs.getString('user'), isNull);
    });

    testWidgets('secured without a FitFlex PIN: told to sign in again', (
      tester,
    ) async {
      final api = _Api()
        ..answers.add(
          _result(
            signedOut: true,
            protection: {
              'requested': true,
              'sessionsEnded': true,
              'pinResetRequired': 'not_applicable',
            },
          ),
        );
      final auth = await _open(tester, api, choice: _secure);
      expect(find.textContaining('Sign in again to continue'), findsOneWidget);
      expect(find.textContaining('Forgot PIN'), findsNothing);
      await tester.tap(find.byKey(_signedOutOk));
      await _settle(tester);
      expect(auth.isSignedIn, isFalse);
    });

    testWidgets('limited: recorded, nothing locked again, still signed in', (
      tester,
    ) async {
      final api = _Api()
        ..answers.add(
          _result(
            protection: {
              'requested': true,
              'sessionsEnded': false,
              'pinResetRequired': false,
              'limited': true,
            },
          ),
        );
      final auth = await _open(tester, api, choice: _secure);
      expect(
        find.text(
          'Report recorded. Your account was already secured recently, so '
          'nothing more was changed.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reported'), findsOneWidget);
      expect(find.byKey(_retry), findsNothing);
      expect(find.byKey(_action), findsNothing);
      expect(auth.isSignedIn, isTrue);
    });

    testWidgets('failed: change PIN now, and a retry that secures', (
      tester,
    ) async {
      final api = _Api(pinOn: true)
        ..answers.addAll([
          _result(
            protection: {
              'requested': true,
              'sessionsEnded': false,
              'pinResetRequired': false,
              'failed': true,
            },
          ),
          _result(
            idempotent: true,
            signedOut: true,
            protection: {
              'requested': true,
              'sessionsEnded': true,
              'pinResetRequired': true,
            },
          ),
        ]);
      final auth = await _open(tester, api, choice: _secure);
      expect(
        find.text(
          'Report recorded, but we could not secure your account. Change '
          'your PIN now.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reported'), findsOneWidget);
      expect(find.byKey(_action), findsNothing);
      expect(auth.isSignedIn, isTrue);

      // The way to change the PIN.
      await _show(tester, find.byKey(_changePin));
      await tester.tap(find.byKey(_changePin));
      await _settle(tester);
      expect(find.byKey(const Key('change-pin-save')), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await _settle(tester);

      // The retry asks the server to secure again, once the server's
      // cooldown since the first attempt is over.
      await _show(tester, find.byKey(_retry));
      expect(find.text('Try securing again'), findsOneWidget);
      expect(_enabled(tester, _retry), isFalse);
      await tester.pump(_cooldown);
      await tester.pump();
      expect(_enabled(tester, _retry), isTrue);
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(api.reports.last, (eventId: 'e1', secureAccount: true));
      expect(api.reports.length, 2);
      await tester.tap(find.byKey(_signedOutOk));
      await _settle(tester);
      expect(auth.isSignedIn, isFalse);
    });

    testWidgets('failed with no FitFlex PIN: no PIN words, only the retry', (
      tester,
    ) async {
      // PIN sign-in is on, but FitFlex holds no PIN for this account.
      final api = _Api(pinOn: true)
        ..answers.add(
          _result(
            protection: {
              'requested': true,
              'sessionsEnded': false,
              'pinResetRequired': 'not_applicable',
              'failed': true,
            },
          ),
        );
      await _open(tester, api, choice: _secure);
      expect(
        find.text('Report recorded, but we could not secure your account.'),
        findsOneWidget,
      );
      expect(find.textContaining('PIN'), findsNothing);
      expect(find.byKey(_changePin), findsNothing);
      expect(find.byKey(_forgotPin), findsNothing);
      expect(find.byKey(_retry), findsOneWidget);
    });

    testWidgets('failed while PIN sign-in is off: no PIN words either', (
      tester,
    ) async {
      final api = _Api()
        ..answers.add(
          _result(
            protection: {
              'requested': true,
              'sessionsEnded': false,
              'pinResetRequired': false,
              'failed': true,
            },
          ),
        );
      await _open(tester, api, choice: _secure);
      expect(find.textContaining('PIN'), findsNothing);
      expect(find.byKey(_changePin), findsNothing);
      expect(find.byKey(_forgotPin), findsNothing);
      expect(find.byKey(_retry), findsOneWidget);
    });

    testWidgets('failed with the PIN already off: Forgot PIN, not Change '
        'PIN', (tester) async {
      final api = _Api(pinOn: true)
        ..answers.add(
          _result(
            protection: {
              'requested': true,
              'sessionsEnded': false,
              'pinResetRequired': true,
              'failed': true,
            },
          ),
        );
      final auth = await _open(tester, api, choice: _secure);
      expect(
        find.text(
          'Report recorded, but we could not finish securing your account. '
          'Your PIN no longer works. Set a new one with Forgot PIN.',
        ),
        findsOneWidget,
      );
      expect(auth.isSignedIn, isTrue);
      expect(find.byKey(_changePin), findsNothing);
      expect(find.byKey(_retry), findsOneWidget);
      expect(find.text('Try securing again'), findsOneWidget);

      // The existing Forgot PIN flow opens.
      await _show(tester, find.byKey(_forgotPin));
      await tester.tap(find.byKey(_forgotPin));
      await _settle(tester);
      expect(find.byKey(const Key('pin-flow-send')), findsOneWidget);
    });
  });

  group('errors', () {
    testWidgets('429: the real wait the server gave', (tester) async {
      final api = _Api()
        ..answers.add(
          ApiException(429, {
            'error': 'report_limit_reached',
            'retryAfterSeconds': 5 * 3600 + 600,
          }),
        );
      await _open(tester, api, choice: _only);
      expect(
        find.text(
          'You have sent the most reports allowed for now. Try again in '
          'about 6 hours.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(_retry), findsNothing);
      expect(find.byKey(_action), findsOneWidget);
      expect(find.text('Reported'), findsNothing);
    });

    testWidgets('429 without a wait: try again later, with no time', (
      tester,
    ) async {
      final api = _Api()
        ..answers.add(ApiException(429, {'error': 'report_limit_reached'}));
      await _open(tester, api, choice: _only);
      expect(
        find.text(
          'You have sent the most reports allowed for now. Try again later.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('minute'), findsNothing);
      expect(find.textContaining('hour'), findsNothing);
      expect(find.byKey(_retry), findsNothing);
      // Not reported: the action is still there.
      expect(find.byKey(_action), findsOneWidget);
      expect(find.text('Reported'), findsNothing);
    });

    testWidgets('404: not available, list read again', (tester) async {
      final api = _Api()
        ..answers.add(ApiException(404, {'error': 'not_found'}));
      final auth = await _open(tester, api, choice: _only);
      expect(
        find.text('Reporting is not available for this check-in.'),
        findsOneWidget,
      );
      expect(find.byKey(_retry), findsNothing);
      expect(api.lists, 2);
      expect(auth.isSignedIn, isTrue);
    });

    testWidgets('400: could not send, retry sends the same choice', (
      tester,
    ) async {
      final api = _Api()
        ..answers.addAll([
          ApiException(400, {'error': 'invalid_secure_account'}),
          _result(),
        ]);
      await _open(tester, api, choice: _only);
      expect(
        find.text("We couldn't send your report. Try again."),
        findsOneWidget,
      );
      await _show(tester, find.byKey(_retry));
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(api.reports, [
        (eventId: 'e1', secureAccount: false),
        (eventId: 'e1', secureAccount: false),
      ]);
      expect(find.text('Reported'), findsOneWidget);
      expect(find.byKey(_retry), findsNothing);
    });

    testWidgets('network error on "secure": the retry waits 60 seconds', (
      tester,
    ) async {
      final api = _Api()..answers.addAll([Exception('offline'), _result()]);
      final auth = await _open(tester, api, choice: _secure);
      expect(
        find.text('No connection. Check your internet and try again.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(auth.isSignedIn, isTrue);
      // The request may have arrived: the list is read again, and the
      // server's cooldown is respected.
      expect(api.lists, 2);
      expect(find.byKey(_action), findsOneWidget);
      expect(find.text('Wait a minute, then try again.'), findsOneWidget);
      expect(_enabled(tester, _retry), isFalse);
      await tester.tap(find.byKey(_retry), warnIfMissed: false);
      await _settle(tester);
      expect(api.reports.length, 1);

      await tester.pump(_cooldown);
      await tester.pump();
      expect(find.byKey(_wait), findsNothing);
      expect(_enabled(tester, _retry), isTrue);
      await _show(tester, find.byKey(_retry));
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(api.reports.last, (eventId: 'e1', secureAccount: true));
      expect(find.text('Reported'), findsOneWidget);
      expect(find.byKey(_retry), findsNothing);
    });

    testWidgets('503 on "secure": the retry waits too', (tester) async {
      final api = _Api()
        ..answers.add(ApiException(503, {'error': 'unavailable'}));
      await _open(tester, api, choice: _secure);
      expect(
        find.text("We couldn't send your report. Try again."),
        findsOneWidget,
      );
      expect(api.lists, 2);
      expect(find.byKey(_wait), findsOneWidget);
      expect(_enabled(tester, _retry), isFalse);
    });

    testWidgets('400 on "secure": refused outright, retry at once', (
      tester,
    ) async {
      final api = _Api()
        ..answers.add(ApiException(400, {'error': 'invalid_secure_account'}));
      await _open(tester, api, choice: _secure);
      expect(find.byKey(_wait), findsNothing);
      expect(_enabled(tester, _retry), isTrue);
    });

    testWidgets('network error on "report only": retry at once', (
      tester,
    ) async {
      final api = _Api()..answers.addAll([Exception('offline'), _result()]);
      await _open(tester, api, choice: _only);
      expect(
        find.text('No connection. Check your internet and try again.'),
        findsOneWidget,
      );
      expect(api.lists, 1);
      expect(find.byKey(_wait), findsNothing);
      expect(_enabled(tester, _retry), isTrue);
      await _show(tester, find.byKey(_retry));
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(api.reports.last, (eventId: 'e1', secureAccount: false));
      expect(find.text('Reported'), findsOneWidget);
    });
  });

  group('a "secure" report whose answer was lost', () {
    testWidgets('the list shows it arrived and is still owed: the failed '
        'notice, waiting', (tester) async {
      final api = _Api()
        ..recordedOnError = true
        ..listed = _reported('open', pending: true)
        ..answers.add(Exception('timeout'));
      await _open(tester, api, choice: _secure);
      expect(api.lists, 2);
      // The list's state, not the error.
      expect(find.textContaining('No connection'), findsNothing);
      expect(
        find.text('Report recorded, but we could not secure your account.'),
        findsOneWidget,
      );
      expect(find.text('Reported'), findsOneWidget);
      expect(find.byKey(_action), findsNothing);
      expect(find.byKey(_notice), findsOneWidget);
      expect(find.text('Try securing again'), findsOneWidget);
      expect(find.byKey(_wait), findsOneWidget);
      expect(_enabled(tester, _retry), isFalse);
    });

    testWidgets('the list shows it arrived and nothing is owed: no notice', (
      tester,
    ) async {
      final api = _Api()
        ..recordedOnError = true
        ..listed = _reported('open', pending: false)
        ..answers.add(Exception('timeout'));
      await _open(tester, api, choice: _secure);
      expect(find.text('Reported'), findsOneWidget);
      expect(find.byKey(_notice), findsNothing);
      expect(find.byKey(_retry), findsNothing);
      expect(find.byKey(_action), findsNothing);
    });

    testWidgets('a retry answered "failed" is not final: the list says it '
        'is secured, so no notice', (tester) async {
      final api = _Api()
        ..answers.addAll([
          Exception('timeout'),
          // The server ignored the repeat: the first attempt was running.
          _result(idempotent: true, protection: _failedProtection),
        ]);
      await _open(tester, api, choice: _secure);
      expect(find.textContaining('No connection'), findsOneWidget);
      await tester.pump(_cooldown);
      await tester.pump();
      // By now the first attempt has finished and nothing is owed.
      api.listed = _reported('open', pending: false);
      await _show(tester, find.byKey(_retry));
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(api.reports.length, 2);
      expect(find.text('Reported'), findsOneWidget);
      expect(find.textContaining('could not secure'), findsNothing);
      expect(find.byKey(_notice), findsNothing);
      expect(find.byKey(_retry), findsNothing);
    });

    testWidgets('a retry answered "failed", and the list agrees: the failed '
        'notice, waiting', (tester) async {
      final api = _Api()
        ..listed = _reported('open', pending: true)
        ..answers.addAll([
          Exception('timeout'),
          _result(idempotent: true, protection: _failedProtection),
        ]);
      await _open(tester, api, choice: _secure);
      await tester.pump(_cooldown);
      await tester.pump();
      await _show(tester, find.byKey(_retry));
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(
        find.text('Report recorded, but we could not secure your account.'),
        findsOneWidget,
      );
      expect(find.byKey(_notice), findsOneWidget);
      expect(find.byKey(_wait), findsOneWidget);
      expect(_enabled(tester, _retry), isFalse);
    });
  });

  group('errors on a retry of securing', () {
    for (final (name, error) in <(String, Object)>[
      ('network', Exception('offline')),
      ('503', ApiException(503, {'error': 'unavailable'})),
    ]) {
      testWidgets('$name: could not reach FitFlex, and the retry waits', (
        tester,
      ) async {
        final api = _Api()
          ..events = [_event(1, report: _reported('open', pending: true))]
          ..answers.add(error);
        await _open(tester, api);
        expect(_enabled(tester, _retry), isTrue);
        await tester.tap(find.byKey(_retry));
        await _settle(tester);
        expect(api.reports.single, (eventId: 'e1', secureAccount: true));
        expect(
          find.text(
            'We could not reach FitFlex to secure your account. Try again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('send your report'), findsNothing);
        expect(find.textContaining('No connection'), findsNothing);
        // One notice; the list was read again and still owes the securing.
        expect(api.lists, 2);
        expect(find.byKey(_notice), findsOneWidget);
        expect(find.text('Wait a minute, then try again.'), findsOneWidget);
        expect(_enabled(tester, _retry), isFalse);
        await tester.pump(_cooldown);
        await tester.pump();
        expect(find.byKey(_wait), findsNothing);
        expect(_enabled(tester, _retry), isTrue);
      });
    }

    testWidgets('the list then says it is secured: the error goes', (
      tester,
    ) async {
      final api = _Api()
        ..events = [_event(1, report: _reported('open', pending: true))]
        ..recordedOnError = true
        ..listed = _reported('open', pending: false)
        ..answers.add(Exception('timeout'));
      await _open(tester, api);
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(find.byKey(_notice), findsNothing);
      expect(find.byKey(_retry), findsNothing);
      expect(find.text('Reported'), findsOneWidget);
    });

    testWidgets('a refresh that fails keeps the list and the notice', (
      tester,
    ) async {
      final api = _Api()
        ..events = [_event(1, report: _reported('open', pending: true))]
        ..answers.add(Exception('offline'))
        ..listError = ApiException(503, {'error': 'unavailable'});
      await _open(tester, api);
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(find.text('Iron Gym'), findsOneWidget);
      expect(find.byKey(_notice), findsOneWidget);
      expect(find.textContaining('could not reach FitFlex'), findsOneWidget);
    });
  });

  testWidgets('one report at a time: no second send while one is in flight', (
    tester,
  ) async {
    final api = _Api()
      ..events = [_event(1), _event(2)]
      ..gate = Completer<void>()
      ..answers.add(_result());
    await _open(tester, api, choice: _only);
    expect(api.reports.length, 1);

    // This event's button shows progress and ignores taps; the other is off.
    await tester.tap(find.byKey(_action), warnIfMissed: false);
    await _settle(tester);
    expect(find.text('Report this check-in'), findsNothing);
    final other = find.byKey(const Key('security-report-e2'));
    await _show(tester, other);
    await tester.tap(other, warnIfMissed: false);
    await _settle(tester);
    expect(find.text('Report this check-in'), findsNothing);
    expect(api.reports.length, 1);

    api.gate!.complete();
    await _settle(tester);
    expect(api.reports.length, 1);
    expect(find.text('Reported'), findsOneWidget);
    // The other event can be reported again now.
    expect(find.byKey(const Key('security-report-e2')), findsOneWidget);
  });

  group('securing still owed, from the list', () {
    testWidgets('a fresh page offers the retry, which secures', (tester) async {
      final api = _Api()
        ..events = [_event(1, report: _reported('open', pending: true))]
        ..answers.add(
          _result(
            idempotent: true,
            signedOut: true,
            protection: {
              'requested': true,
              'sessionsEnded': true,
              'pinResetRequired': 'not_applicable',
            },
          ),
        );
      final auth = await _open(tester, api);
      expect(api.reports, isEmpty);
      expect(
        find.text('Report recorded, but we could not secure your account.'),
        findsOneWidget,
      );
      expect(find.byKey(_action), findsNothing);
      expect(find.byKey(_support), findsNothing);
      // Nothing is known about a cooldown on a fresh page.
      expect(find.byKey(_wait), findsNothing);
      expect(_enabled(tester, _retry), isTrue);
      await _show(tester, find.byKey(_retry));
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(api.reports.single, (eventId: 'e1', secureAccount: true));
      await tester.tap(find.byKey(_signedOutOk));
      await _settle(tester);
      expect(auth.isSignedIn, isFalse);
    });

    testWidgets('reopened page: a retry answered "failed" with no marker '
        'waits, with no error text', (tester) async {
      final api = _Api()
        ..events = [_event(1, report: _reported('open', pending: true))]
        ..listed = _reported('open', pending: true)
        ..answers.add(_result(idempotent: true, protection: _failedProtection));
      await _open(tester, api);
      expect(find.byKey(_wait), findsNothing);
      expect(_enabled(tester, _retry), isTrue);
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(api.reports.single, (eventId: 'e1', secureAccount: true));
      expect(_enabled(tester, _retry), isFalse);
      expect(find.text('Wait a minute, then try again.'), findsOneWidget);
      // Told to wait; nothing reads as a new error.
      expect(find.byKey(_notice), findsOneWidget);
      expect(
        find.text('Report recorded, but we could not secure your account.'),
        findsOneWidget,
      );
      expect(find.textContaining('could not reach'), findsNothing);
      expect(find.textContaining("couldn't send"), findsNothing);
      expect(find.textContaining('No connection'), findsNothing);
      expect(find.textContaining('support'), findsNothing);
    });

    testWidgets('not retryable: no retry, contact support', (tester) async {
      final api = _Api()
        ..events = [
          _event(
            1,
            report: _reported('acknowledged', pending: true, retryable: false),
          ),
        ];
      await _open(tester, api);
      expect(
        find.text(
          'Report recorded, but we could not secure your account. Contact '
          'FitFlex support.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(_retry), findsNothing);
      expect(find.byKey(_action), findsNothing);
    });

    testWidgets('nothing for reports that are not pending, or resolved', (
      tester,
    ) async {
      final api = _Api()
        ..events = [
          _event(1, report: _reported('open', pending: false)),
          _event(2, report: _reported('open')),
          // Never sent by the server; a resolved report is not pending.
          _event(3, report: _reported('resolved', pending: true)),
          _event(
            4,
            report: _reported('resolved', pending: false, retryable: false),
          ),
        ];
      await _open(tester, api);
      for (var n = 1; n <= 4; n++) {
        expect(find.byKey(Key('security-report-notice-e$n')), findsNothing);
        expect(find.byKey(Key('security-report-retry-e$n')), findsNothing);
      }
      expect(find.textContaining('could not secure'), findsNothing);
      expect(find.textContaining('support'), findsNothing);
    });

    testWidgets('hidden while reportEnabled is false', (tester) async {
      final api = _Api()
        ..reportEnabled = false
        ..events = [_event(1, report: _reported('open', pending: true))];
      await _open(tester, api);
      expect(find.byKey(_notice), findsNothing);
      expect(find.byKey(_retry), findsNothing);
    });

    testWidgets('one notice per event after a failed report', (tester) async {
      final api = _Api()
        ..listed = _reported('open', pending: true)
        ..answers.add(_result(protection: _failedProtection));
      await _open(tester, api, choice: _secure);
      expect(api.lists, 2);
      expect(find.byKey(_notice), findsOneWidget);
      expect(find.textContaining('could not secure'), findsOneWidget);
      expect(find.byKey(_retry), findsOneWidget);
    });

    testWidgets('the notice goes once the list says it is secured', (
      tester,
    ) async {
      final api = _Api()
        ..listed = _reported('open', pending: false)
        ..answers.add(_result(protection: _failedProtection));
      await _open(tester, api, choice: _secure);
      expect(find.byKey(_notice), findsNothing);
      expect(find.byKey(_retry), findsNothing);
      expect(find.text('Reported'), findsOneWidget);
    });
  });

  group('not retryable, from the report call', () {
    testWidgets('first report: no retry, contact support', (tester) async {
      final api = _Api()
        ..answers.add(
          _result(protection: {..._failedProtection, 'retryable': false}),
        );
      final auth = await _open(tester, api, choice: _secure);
      expect(
        find.text(
          'Report recorded, but we could not secure your account. Contact '
          'FitFlex support.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(_retry), findsNothing);
      expect(find.byKey(_wait), findsNothing);
      expect(find.text('Reported'), findsOneWidget);
      expect(auth.isSignedIn, isTrue);
    });

    testWidgets('with a PIN to change: the PIN step and the support line', (
      tester,
    ) async {
      final api = _Api(pinOn: true)
        ..answers.add(
          _result(
            protection: {
              'requested': true,
              'sessionsEnded': false,
              'pinResetRequired': false,
              'failed': true,
              'retryable': false,
            },
          ),
        );
      await _open(tester, api, choice: _secure);
      expect(find.textContaining('Change your PIN now'), findsOneWidget);
      expect(find.byKey(_changePin), findsOneWidget);
      expect(
        find.text(
          'Trying again here will not secure your account. Contact FitFlex '
          'support.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(_retry), findsNothing);
    });

    testWidgets('the last retry used: the retry goes', (tester) async {
      final api = _Api()
        ..events = [_event(1, report: _reported('open', pending: true))]
        ..listed = _reported('open', pending: true, retryable: false)
        ..answers.add(
          _result(
            idempotent: true,
            protection: {..._failedProtection, 'retryable': false},
          ),
        );
      await _open(tester, api);
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(api.reports.length, 1);
      expect(api.lists, 2);
      expect(find.byKey(_retry), findsNothing);
      expect(find.byKey(_notice), findsOneWidget);
      expect(find.textContaining('Contact FitFlex support'), findsOneWidget);
    });
  });

  group('cooldown', () {
    testWidgets('a failed retry waits 60 seconds, then can be tried again', (
      tester,
    ) async {
      final api = _Api()
        ..events = [_event(1, report: _reported('open', pending: true))]
        ..listed = _reported('open', pending: true)
        ..answers.addAll([
          _result(idempotent: true, protection: _failedProtection),
          _result(idempotent: true, protection: _failedProtection),
        ]);
      await _open(tester, api);
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(api.reports.length, 1);
      // The list was read again and agrees: one notice, still pending.
      expect(api.lists, 2);
      expect(find.byKey(_notice), findsOneWidget);
      expect(find.text('Wait a minute, then try again.'), findsOneWidget);
      expect(_enabled(tester, _retry), isFalse);
      await tester.tap(find.byKey(_retry), warnIfMissed: false);
      await _settle(tester);
      expect(api.reports.length, 1);

      // Just before the minute is up: still waiting.
      await tester.pump(const Duration(seconds: 58));
      expect(_enabled(tester, _retry), isFalse);
      expect(find.byKey(_wait), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byKey(_wait), findsNothing);
      expect(_enabled(tester, _retry), isTrue);

      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(api.reports.length, 2);
      // And it waits again.
      expect(find.byKey(_wait), findsOneWidget);
      expect(_enabled(tester, _retry), isFalse);
    });

    testWidgets('per event: another event can still be retried', (
      tester,
    ) async {
      final api = _Api()
        ..events = [
          _event(1, report: _reported('open', pending: true)),
          _event(2, report: _reported('open', pending: true)),
        ]
        ..listed = _reported('open', pending: true)
        ..answers.add(_result(idempotent: true, protection: _failedProtection));
      await _open(tester, api);
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(_enabled(tester, _retry), isFalse);
      expect(_enabled(tester, const Key('security-report-retry-e2')), isTrue);
      expect(find.byKey(const Key('security-report-wait-e2')), findsNothing);
    });

    testWidgets('no second send while a retry is in flight', (tester) async {
      final api = _Api()
        ..events = [_event(1, report: _reported('open', pending: true))]
        ..listed = _reported('open', pending: true)
        ..gate = Completer<void>()
        ..answers.add(_result(idempotent: true, protection: _failedProtection));
      await _open(tester, api);
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      await tester.tap(find.byKey(_retry), warnIfMissed: false);
      await _settle(tester);
      expect(api.reports.length, 1);
      api.gate!.complete();
      await _settle(tester);
      expect(api.reports.length, 1);
    });
  });

  group('limit message', () {
    String en(Object? body) =>
        securityReportLimitMessage((k) => FFLocale.textOf('en', k) ?? k, body);
    const lead = 'You have sent the most reports allowed for now. ';
    test('rounds up to minutes, then hours, never down', () {
      String wait(int seconds) {
        final text = en({'retryAfterSeconds': seconds});
        expect(text, startsWith('${lead}Try again in about '));
        return text.substring('${lead}Try again in about '.length);
      }

      expect(wait(1), 'a minute.');
      expect(wait(60), 'a minute.');
      expect(wait(61), '2 minutes.');
      expect(wait(120), '2 minutes.');
      expect(wait(59 * 60), '59 minutes.');
      expect(wait(59 * 60 + 1), 'an hour.');
      expect(wait(3600), 'an hour.');
      expect(wait(3601), '2 hours.');
      expect(wait(5399), '2 hours.');
      expect(wait(7200), '2 hours.');
      expect(wait(7201), '3 hours.');
      expect(wait(86399), '24 hours.');
      expect(wait(86400), '24 hours.');
    });
    test('missing or invalid: no time', () {
      for (final body in <Object?>[
        null,
        'nope',
        <String, dynamic>{},
        {'retryAfterSeconds': null},
        {'retryAfterSeconds': '3600'},
        {'retryAfterSeconds': 0},
        {'retryAfterSeconds': -5},
        {'retryAfterSeconds': 86401},
        {'retryAfterSeconds': double.nan},
      ]) {
        expect(en(body), '${lead}Try again later.', reason: '$body');
      }
    });
    test('Swahili', () {
      String sw(int s) => securityReportLimitMessage(
        (k) => FFLocale.textOf('sw', k) ?? k,
        {'retryAfterSeconds': s},
      );
      expect(sw(1800), contains('takriban dakika 30'));
      expect(sw(7200), contains('takriban saa 2'));
      expect(sw(1800), isNot(contains('{n}')));
    });
  });

  group('200% text, Swahili, new notices', () {
    testWidgets('list retry, cooldown line and support lines do not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _Api(pinOn: true)
        ..events = [
          _event(1, report: _reported('open', pending: true)),
          _event(2, report: _reported('open', pending: true, retryable: false)),
          _event(3),
        ]
        ..listed = _reported('open', pending: true)
        ..answers.addAll([
          _result(
            idempotent: true,
            protection: {
              'requested': true,
              'sessionsEnded': false,
              'pinResetRequired': false,
              'failed': true,
            },
          ),
          ApiException(429, {
            'error': 'report_limit_reached',
            'retryAfterSeconds': 7200,
          }),
        ]);
      await _open(tester, api, lang: 'sw', scale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text('Jaribu kulinda tena'), findsOneWidget);
      expect(
        find.text(
          'Ripoti imerekodiwa, lakini hatukuweza kulinda akaunti yako. '
          'Wasiliana na timu ya msaada ya FitFlex.',
        ),
        findsOneWidget,
      );
      await _show(tester, find.byKey(_retry));
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.text('Subiri dakika moja kisha ujaribu tena.'),
        findsOneWidget,
      );
      // The 429 wait, on the event not yet reported.
      const third = Key('security-report-e3');
      await _show(tester, find.byKey(third));
      await tester.tap(find.byKey(third));
      await _settle(tester);
      await _show(tester, find.byKey(_only));
      await tester.tap(find.byKey(_only));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('takriban saa 2'), findsOneWidget);
    });

    testWidgets('a retry that could not reach FitFlex does not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _Api()
        ..events = [_event(1, report: _reported('open', pending: true))]
        ..answers.add(Exception('offline'));
      await _open(tester, api, lang: 'sw', scale: 2);
      await _show(tester, find.byKey(_retry));
      await tester.tap(find.byKey(_retry));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Hatukuweza kuwasiliana na FitFlex ili kulinda akaunti yako. '
          'Jaribu tena.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Subiri dakika moja kisha ujaribu tena.'),
        findsOneWidget,
      );
    });

    testWidgets('PIN step with the support line does not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _Api(pinOn: true)
        ..answers.add(
          _result(
            protection: {
              'requested': true,
              'sessionsEnded': false,
              'pinResetRequired': true,
              'failed': true,
              'retryable': false,
            },
          ),
        );
      await _open(tester, api, choice: _secure, lang: 'sw', scale: 2);
      expect(tester.takeException(), isNull);
      expect(find.byKey(_forgotPin), findsOneWidget);
      expect(
        find.text(
          'Kujaribu tena hapa hakutalinda akaunti yako. Wasiliana na timu ya '
          'msaada ya FitFlex.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(_retry), findsNothing);
    });
  });

  group('200% text', () {
    testWidgets('row, sheet and notice do not overflow on a small phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _Api(pinOn: true)
        ..events = [_event(1), _event(2, report: _reported('acknowledged'))]
        ..answers.add(
          _result(
            protection: {
              'requested': true,
              'sessionsEnded': false,
              'pinResetRequired': false,
              'failed': true,
            },
          ),
        );
      await _open(tester, api, lang: 'sw', scale: 2);
      expect(tester.takeException(), isNull);
      await _show(tester, find.byKey(_action));
      await tester.tap(find.byKey(_action));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _show(tester, find.byKey(_secure));
      await tester.tap(find.byKey(_secure));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(_changePin), findsOneWidget);
      expect(find.byKey(_retry), findsOneWidget);
    });

    testWidgets('signed-out dialog does not overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _Api()
        ..answers.add(
          _result(
            signedOut: true,
            protection: {
              'requested': true,
              'sessionsEnded': true,
              'pinResetRequired': true,
            },
          ),
        );
      await _open(tester, api, choice: _secure, lang: 'sw', scale: 2);
      expect(tester.takeException(), isNull);
      expect(find.byKey(_signedOutOk), findsOneWidget);
    });
  });

  testWidgets('Swahili', (tester) async {
    final api = _Api()
      ..events = [_event(1), _event(2, report: _reported('resolved'))]
      ..answers.add(_result());
    await _open(tester, api, lang: 'sw');
    expect(find.text('Sikuwa mimi'), findsOneWidget);
    expect(find.text('Imepitiwa'), findsOneWidget);
    await tester.tap(find.byKey(_action));
    await _settle(tester);
    expect(find.text('Ripoti kujiandikisha huku'), findsOneWidget);
    expect(find.text('Ziara haiondolewi kiotomatiki.'), findsOneWidget);
    expect(find.text('Ripoti na linda akaunti yangu'), findsOneWidget);
    expect(find.text('Ripoti tu'), findsOneWidget);
    expect(find.text('Ghairi'), findsOneWidget);
    await tester.tap(find.byKey(_only));
    await _settle(tester);
    expect(
      find.text('Ripoti imetumwa. Timu ya msaada ya FitFlex itaipitia.'),
      findsOneWidget,
    );
    expect(find.text('Imeripotiwa'), findsOneWidget);
  });

  group('parsing', () {
    test('report result', () {
      final r = SecurityReportResult.fromJson(
        _result(
          signedOut: true,
          protection: {
            'requested': true,
            'sessionsEnded': true,
            'pinResetRequired': 'not_applicable',
          },
        ),
      );
      expect(r.incidentId, 'inc1');
      expect(r.status, 'open');
      expect(r.signedOut, isTrue);
      expect(r.pinResetRequired, isFalse);
      expect(r.pinNotApplicable, isTrue);
      expect(r.limited, isFalse);
      expect(r.failed, isFalse);
      // Nothing but `ok`: reads as a plain, unprotected report.
      final bare = SecurityReportResult.fromJson({'ok': true});
      expect(bare.signedOut, isFalse);
      expect(bare.failed, isFalse);
      expect(bare.pinNotApplicable, isFalse);
      expect(bare.retryable, isTrue);
      expect(r.retryable, isTrue);
      // `retryable` only ever comes as false, beside `failed`.
      final stuck = SecurityReportResult.fromJson(
        _result(protection: {..._failedProtection, 'retryable': false}),
      );
      expect(stuck.failed, isTrue);
      expect(stuck.retryable, isFalse);
      final again = SecurityReportResult.fromJson(
        _result(protection: _failedProtection),
      );
      expect(again.failed, isTrue);
      expect(again.retryable, isTrue);
    });

    test('event report: protection fields', () {
      SecurityReport parse(Map<String, dynamic> report) =>
          SecurityEvent.fromJson(_event(1, report: report)).report!;
      // An older backend: neither field. Not pending, nothing known.
      final old = parse(_reported('open'));
      expect(old.protectionPending, isFalse);
      expect(old.protectionRetryable, isTrue);
      expect(old.protectionKnown, isFalse);
      expect(old.securingPending, isFalse);

      final pending = parse(_reported('open', pending: true));
      expect(pending.protectionPending, isTrue);
      expect(pending.protectionRetryable, isTrue);
      expect(pending.protectionKnown, isTrue);
      expect(pending.securingPending, isTrue);

      final stuck = parse(_reported('open', pending: true, retryable: false));
      expect(stuck.protectionPending, isTrue);
      expect(stuck.protectionRetryable, isFalse);
      expect(stuck.securingPending, isTrue);

      final done = parse(_reported('acknowledged', pending: false));
      expect(done.protectionPending, isFalse);
      expect(done.protectionKnown, isTrue);

      // Anything but real booleans reads as not pending, retryable.
      final odd = parse({
        ..._reported('open'),
        'protectionPending': 'true',
        'protectionRetryable': 'false',
      });
      expect(odd.protectionPending, isFalse);
      expect(odd.protectionRetryable, isTrue);
      expect(odd.protectionKnown, isFalse);

      // A resolved report is never pending, whatever it says.
      expect(
        parse(_reported('resolved', pending: true)).securingPending,
        isFalse,
      );
    });

    test('event report', () {
      expect(SecurityEvent.fromJson(_event(1)).report, isNull);
      final e = SecurityEvent.fromJson(
        _event(1, report: _reported('acknowledged')),
      );
      expect(e.report?.incidentId, 'inc1');
      expect(e.report?.statusKey, 'secAct.report.status.acknowledged');
      // An older server: no `report` key at all.
      expect(
        SecurityEvent.fromJson({'id': 'e9', 'kind': 'web_checkin'}).report,
        isNull,
      );
    });
  });

  test('en and sw report keys match and differ', () {
    final en = FFLocale.keysOf(
      'en',
    ).where((k) => k.startsWith('secAct.report.'));
    final sw = FFLocale.keysOf(
      'sw',
    ).where((k) => k.startsWith('secAct.report.'));
    expect(en.toSet(), sw.toSet());
    expect(en.length, 34);
    for (final k in en) {
      expect(
        FFLocale.textOf('sw', k),
        isNot(FFLocale.textOf('en', k)),
        reason: k,
      );
    }
  });
}
