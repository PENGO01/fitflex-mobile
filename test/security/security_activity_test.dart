// Security activity (S4a): a read-only list of check-ins made from a web
// browser, its profile tile, and where a push or inbox notice leads.

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/security/security_activity_page.dart';
import 'package:fitflexmobile/screens/security/security_activity_tile.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:fitflexmobile/shared/inbox/inbox_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _event(
  int n, {
  String status = 'inbox',
  String kind = 'web_checkin',
  Map<String, dynamic>? gym = const {'id': 'g1', 'name': 'Iron Gym'},
}) => {
  'id': 'e$n',
  'kind': kind,
  'occurredAt': '2026-11-09T11:30:00.000Z',
  'gym': gym,
  'channel': 'web',
  'status': status,
};

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://localhost:0');

  /// Pages by cursor: null is the first page.
  Map<String?, Map<String, dynamic>> pages = {
    null: {'events': <Map<String, dynamic>>[]},
  };
  Object? error;
  final calls = <({int limit, String? before})>[];

  @override
  Future<Map<String, dynamic>> securityActivity({
    int limit = 20,
    String? before,
  }) async {
    calls.add((limit: limit, before: before));
    if (error case final e?) throw e;
    return pages[before] ?? {'events': const []};
  }
}

class _InboxApi extends ApiClient {
  _InboxApi() : super(baseUrl: 'http://localhost:0');

  @override
  Future<Map<String, dynamic>> notifications() async => {
    'unread': 1,
    'notifications': [
      {
        'id': 'n1',
        'type': 'web_checkin_recorded',
        'title': 'Web check-in',
        'body': 'A check-in was made from a web browser.',
        'data': {'open': 'security_activity', 'gymId': 'g1'},
        'createdAt': '2026-11-09T11:30:00.000Z',
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> markNotificationRead(String id) async => {};
}

Widget _app(_Api api, Widget home, {String lang = 'en', double scale = 1}) =>
    AppScope(
      api: api,
      auth: AuthState(api),
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
          home: home,
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('page', () {
    testWidgets('lists events with gym, EAT time and status', (tester) async {
      final api = _Api()
        ..pages = {
          null: {
            'events': [
              _event(1),
              _event(2, status: 'recorded', gym: {'id': 'g2', 'name': null}),
              _event(3, status: 'notified', gym: null),
              _event(4, kind: 'something_new', status: 'weird'),
            ],
          },
        };
      await tester.pumpWidget(_app(api, const SecurityActivityPage()));
      await _settle(tester);

      expect(find.text('Check-in from a web browser'), findsNWidgets(3));
      expect(find.text('Iron Gym'), findsNWidgets(2));
      // Null gym name and null gym: the generic words.
      expect(find.text('a FitFlex gym'), findsNWidgets(2));
      expect(find.text('9 Nov 2026, 14:30 EAT'), findsNWidgets(4));
      expect(find.text('Alert sent'), findsNWidgets(2));
      expect(find.text('Recorded'), findsOneWidget);
      // Unknown kind: a generic row, no chip for an unknown status.
      expect(find.text('Security event'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Check-in from a web browser, Iron Gym, 9 Nov 2026, 14:30 EAT, '
          'Alert sent',
        ),
        findsOneWidget,
      );
      expect(api.calls.single, (limit: 20, before: null));
    });

    testWidgets('Swahili words', (tester) async {
      final api = _Api()
        ..pages = {
          null: {
            'events': [_event(1, status: 'recorded')],
          },
        };
      await tester.pumpWidget(
        _app(api, const SecurityActivityPage(), lang: 'sw'),
      );
      await _settle(tester);
      expect(find.text('Kuingia gym kupitia kivinjari'), findsOneWidget);
      expect(find.text('Imerekodiwa'), findsOneWidget);
    });

    testWidgets('empty', (tester) async {
      await tester.pumpWidget(_app(_Api(), const SecurityActivityPage()));
      await _settle(tester);
      expect(find.text('Nothing to review'), findsOneWidget);
      expect(find.textContaining('it will show here'), findsOneWidget);
    });

    testWidgets('404 is "not available yet" with no retry', (tester) async {
      final api = _Api()..error = ApiException(404, {'error': 'not_found'});
      await tester.pumpWidget(_app(api, const SecurityActivityPage()));
      await _settle(tester);
      expect(find.text('Not available yet'), findsOneWidget);
      expect(find.text('Security activity is not switched on yet.'), findsOne);
      expect(find.text('Try again'), findsNothing);
      expect(api.calls.length, 1);
    });

    testWidgets('error shows retry, which loads again', (tester) async {
      final api = _Api()..error = Exception('offline');
      await tester.pumpWidget(_app(api, const SecurityActivityPage()));
      await _settle(tester);
      expect(
        find.text('Couldn\'t load your security activity'),
        findsOneWidget,
      );
      api
        ..error = null
        ..pages = {
          null: {
            'events': [_event(1)],
          },
        };
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(find.text('Iron Gym'), findsOneWidget);
      expect(api.calls.length, 2);
    });

    testWidgets('load more passes the cursor back unchanged', (tester) async {
      final api = _Api()
        ..pages = {
          null: {
            'events': [_event(1)],
            'next': 'opaque/cursor==',
          },
          'opaque/cursor==': {
            'events': [
              _event(2, gym: {'id': 'g3', 'name': 'Second Gym'}),
            ],
          },
        };
      await tester.pumpWidget(_app(api, const SecurityActivityPage()));
      await _settle(tester);
      final more = find.byKey(const Key('security-activity-more'));
      expect(find.text('Load more'), findsOneWidget);
      await tester.ensureVisible(more);
      await tester.tap(more);
      await _settle(tester);
      expect(api.calls.last, (limit: 20, before: 'opaque/cursor=='));
      expect(find.text('Iron Gym'), findsOneWidget);
      expect(find.text('Second Gym'), findsOneWidget);
      // Last page: no more button.
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('no overflow at 200% text', (tester) async {
      final api = _Api()
        ..pages = {
          null: {
            'events': [_event(1, status: 'recorded')],
          },
        };
      await tester.pumpWidget(
        _app(api, const SecurityActivityPage(), scale: 2),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Recorded'), findsOneWidget);
    });
  });

  group('tile', () {
    Widget host(_Api api) =>
        _app(api, const Scaffold(body: SecurityActivityTile()));

    testWidgets('hidden on 404', (tester) async {
      final api = _Api()..error = ApiException(404, {'error': 'not_found'});
      await tester.pumpWidget(host(api));
      await _settle(tester);
      expect(find.text('Security activity'), findsNothing);
      expect(api.calls.single, (limit: 1, before: null));
    });

    testWidgets('shown on 200, probed once', (tester) async {
      final api = _Api();
      await tester.pumpWidget(host(api));
      await _settle(tester);
      expect(find.text('Security activity'), findsOneWidget);
      expect(find.text('Check-ins made from web browsers'), findsOneWidget);
      await tester.pumpWidget(host(api));
      await _settle(tester);
      expect(api.calls.length, 1);
    });

    testWidgets('shown on a network error', (tester) async {
      final api = _Api()..error = Exception('offline');
      await tester.pumpWidget(host(api));
      await _settle(tester);
      expect(find.text('Security activity'), findsOneWidget);
    });
  });

  group('status mapping', () {
    test('inbox, notified and recorded', () {
      expect(securityStatusKey('inbox'), 'secAct.status.inbox');
      expect(securityStatusKey('notified'), 'secAct.status.inbox');
      expect(securityStatusKey('recorded'), 'secAct.status.recorded');
      expect(securityStatusKey('other'), isNull);
    });

    test('null gym id and name both parse', () {
      final e = SecurityEvent.fromJson(
        _event(1, gym: {'id': null, 'name': null}),
      );
      expect(e.gymName, isNull);
      expect(SecurityEvent.fromJson(_event(1, gym: null)).gymName, isNull);
    });

    test('time is EAT whatever the zone', () {
      expect(
        securityEventTime(DateTime.utc(2026, 11, 9, 22, 30)),
        '10 Nov 2026, 01:30 EAT',
      );
    });
  });

  group('where a notice leads', () {
    const push = {
      'type': 'web_checkin_recorded',
      'notificationId': 'n1',
      'eventId': 'e1',
      'gymId': 'g1',
      'open': 'security_activity',
    };

    test('push goes to security activity for every role', () {
      for (final role in [
        'member',
        'trainer',
        'gym_operator',
        'gym_staff',
        'vendor',
        null,
      ]) {
        final t = pushTargetFor(role: role, data: push);
        expect(t.location, securityActivityRoute, reason: '$role');
      }
      expect(securityActivityRoute, '/security-activity');
    });

    test('the open hint alone, or the type alone, is enough', () {
      expect(
        pushTargetFor(
          role: 'member',
          data: {'open': 'security_activity', 'gymId': 'g1'},
        ).location,
        securityActivityRoute,
      );
      expect(
        pushTargetFor(
          role: 'trainer',
          data: {'type': 'web_checkin_recorded', 'gymId': 'g1'},
        ).location,
        securityActivityRoute,
      );
    });

    test('other pushes are unchanged', () {
      expect(
        pushTargetFor(role: 'trainer', data: {'type': 'nothing'}).location,
        '/inbox',
      );
    });
  });

  group('inbox detail', () {
    testWidgets('web check-in notice shows Review activity', (tester) async {
      final api = _InboxApi();
      final inbox = InboxController(api);
      await inbox.load();
      await tester.pumpWidget(
        AppScope(
          api: api,
          auth: AuthState(api),
          inbox: inbox,
          child: FFLocaleScope(
            notifier: FFLocale()..set(const Locale('en')),
            child: MaterialApp(
              theme: buildTheme(),
              home: const InboxMessagePage(messageId: 'n1'),
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Review activity'), findsOneWidget);
    });
  });

  test('en and sw keys match', () {
    final en = FFLocale.keysOf('en').where((k) => k.startsWith('secAct.'));
    final sw = FFLocale.keysOf('sw').where((k) => k.startsWith('secAct.'));
    expect(en.toSet(), sw.toSet());
    // 15 for the list (S4a + its own load error) and 34 for the report (S4c + the
    // retry markers).
    expect(en.length, 49);
    for (final k in en) {
      expect(
        FFLocale.textOf('sw', k),
        isNot(FFLocale.textOf('en', k)),
        reason: k,
      );
    }
  });
}
