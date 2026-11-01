// Events S6 (spec §5, §10.2): the run window and distance pre-check, the run
// recorder's event binding (a clientRef that survives a failed save), the
// entry points on the ticket and registration pages, the "Add a recorded
// run" list, and the record-run screen when it is for an event.
import 'dart:async';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/member/events/results/event_result_entry.dart';
import 'package:fitflexmobile/screens/member/events/results/event_run_links_page.dart';
import 'package:fitflexmobile/screens/member/member_record_run_page.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/activity/gps_source.dart';
import 'package:fitflexmobile/shared/activity/phone_steps.dart' show StepStore;
import 'package:fitflexmobile/shared/activity/run_metrics.dart';
import 'package:fitflexmobile/shared/activity/run_recorder.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/events/event_summary.dart';
import 'package:fitflexmobile/shared/events/events_cache.dart';
import 'package:fitflexmobile/shared/events/run_eligibility.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';
import 's6_support.dart';

Activity _act(
  String id, {
  required DateTime at,
  double km = 21.2,
  String source = 'fitflex',
  String type = 'running',
  bool route = true,
}) => Activity.fromJson({
  'id': id,
  'userId': 'u1',
  'type': type,
  'source': source,
  'startedAt': at.toUtc().toIso8601String(),
  'distanceKm': km,
  'movingSeconds': (km * 330).round(),
  'hasRoute': route,
  'splits': <int>[],
});

Map<String, dynamic> _actJson(
  String id,
  DateTime at, {
  double km = 21.2,
  String source = 'fitflex',
}) => {
  'id': id,
  'userId': 'u1',
  'type': 'running',
  'source': source,
  'startedAt': at.toUtc().toIso8601String(),
  'distanceKm': km,
  'movingSeconds': (km * 330).round(),
  'hasRoute': true,
  'splits': <int>[],
};

class _Gps implements GpsSource {
  _Gps({this.supported = true});
  final bool supported;
  StreamController<TrackPoint>? ctrl;
  @override
  bool get isSupported => supported;
  @override
  Future<GpsAccess> ensureAccess() async => GpsAccess.granted;
  @override
  Stream<TrackPoint> track({
    required String notificationTitle,
    required String notificationText,
  }) {
    ctrl = StreamController<TrackPoint>();
    return ctrl!.stream;
  }

  @override
  Future<void> openAppSettings() async {}
  @override
  Future<void> openLocationSettings() async {}
}

class _Store implements StepStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

class _Api extends ApiClient {
  final eventCalls = <(String, Map<String, dynamic>)>[];
  final plainCalls = <Map<String, dynamic>>[];
  Object? failEvent;

  Map<String, dynamic> get _ok => {
    'activity': {
      'id': 'act_1',
      'userId': 'u1',
      'type': 'running',
      'source': 'fitflex',
      'startedAt': DateTime.utc(2027, 3, 14, 4).toIso8601String(),
      'distanceKm': 1.0,
      'movingSeconds': 300,
      'hasRoute': true,
      'splits': <int>[],
    },
  };

  @override
  Future<Map<String, dynamic>> recordEventRun(
    String registrationId,
    Map<String, dynamic> body,
  ) async {
    eventCalls.add((registrationId, body));
    if (failEvent != null) throw failEvent!;
    return _ok;
  }

  @override
  Future<Map<String, dynamic>> recordRun(Map<String, dynamic> body) async {
    plainCalls.add(body);
    return _ok;
  }

  @override
  Future<Map<String, dynamic>> getMyEventResult(String registrationId) async =>
      resultPayload(eventType: 'virtual', stage: 'none', result: null);
}

DateTime get _now => DateTime.now().toUtc();

/// A run due north, one point per 100 m at 30 s each.
List<TrackPoint> _track(int meters, {required DateTime start}) => [
  for (var i = 0; i <= meters ~/ 100; i++)
    TrackPoint(
      -6.8 + i * 0.0009,
      39.28,
      20,
      start.add(Duration(seconds: i * 30)),
      5,
    ),
];

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsCache.reset();
  });
  tearDown(() => debugEventsDiscoveryOverride = null);

  group(
    'the pre-check (the server decides; this only saves a pointless tap)',
    () {
      final starts = DateTime.utc(2027, 3, 14, 3);
      final ends = DateTime.utc(2027, 3, 14, 8);
      RunFit fit(
        Activity a, {
        bool virtual = false,
        int category = 21097,
        Set<String> linked = const {},
      }) => fitOf(
        a,
        isVirtual: virtual,
        startsAt: starts,
        endsAt: ends,
        categoryMeters: category,
        toleranceBps: 200,
        linkedActivityIds: linked,
      );

      test('available inside the window', () {
        expect(
          fit(_act('a', at: DateTime.utc(2027, 3, 14, 3, 30))),
          RunFit.available,
        );
      });

      test('in person: two hours before the start to twelve after the end', () {
        expect(
          fit(_act('a', at: DateTime.utc(2027, 3, 14, 1, 5))),
          RunFit.available,
        );
        expect(
          fit(_act('a', at: DateTime.utc(2027, 3, 14, 0, 50))),
          RunFit.outside,
        );
        expect(
          fit(_act('a', at: DateTime.utc(2027, 3, 14, 19, 59))),
          RunFit.available,
        );
        expect(
          fit(_act('a', at: DateTime.utc(2027, 3, 14, 20, 1))),
          RunFit.outside,
        );
      });

      test('virtual: the run has to start inside the event window', () {
        expect(
          fit(_act('a', at: DateTime.utc(2027, 3, 14, 2, 59)), virtual: true),
          RunFit.outside,
        );
        expect(
          fit(_act('a', at: DateTime.utc(2027, 3, 14, 5)), virtual: true),
          RunFit.available,
        );
      });

      test('virtual needs the distance within the 2 percent tolerance', () {
        final at = DateTime.utc(2027, 3, 14, 5);
        // 21.097 km x 0.98 = 20.675 km
        expect(
          fit(_act('a', at: at, km: 20.7), virtual: true),
          RunFit.available,
        );
        expect(fit(_act('a', at: at, km: 20.6), virtual: true), RunFit.short);
        // In person any length may be added as evidence.
        expect(fit(_act('a', at: at, km: 5)), RunFit.available);
      });

      test('already added, and runs not recorded in FitFlex', () {
        final at = DateTime.utc(2027, 3, 14, 5);
        expect(fit(_act('a', at: at), linked: {'a'}), RunFit.linked);
        expect(
          fit(_act('a', at: at, source: 'device')),
          RunFit.notRecordedInApp,
        );
        expect(
          fit(_act('a', at: at, type: 'cycling')),
          RunFit.notRecordedInApp,
        );
        expect(fit(_act('a', at: at, route: false)), RunFit.notRecordedInApp);
      });
    },
  );

  group('RunRecorder for an event', () {
    late _Gps gps;
    late _Store store;
    late _Api api;
    RunRecorder make() => RunRecorder(gps: gps, store: store);

    setUp(() {
      gps = _Gps();
      store = _Store();
      api = _Api();
    });

    test('a plain run still uses the plain route', () async {
      final r = make();
      await r.start(notificationTitle: 't', notificationText: 'x');
      for (final p in _track(500, start: DateTime.now().toUtc())) {
        gps.ctrl!.add(p);
      }
      await Future<void>.delayed(Duration.zero);
      await r.finish();
      await r.save(api);
      expect(api.plainCalls, hasLength(1));
      expect(api.plainCalls.single.containsKey('clientRef'), isFalse);
      expect(api.eventCalls, isEmpty);
    });

    test(
      'bound: saves to the event route with the clientRef from the start',
      () async {
        final r = make();
        expect(r.bindEvent('reg_1', makeRef: () => 'run-ref-0001'), isTrue);
        await r.start(notificationTitle: 't', notificationText: 'x');
        for (final p in _track(500, start: DateTime.now().toUtc())) {
          gps.ctrl!.add(p);
        }
        await Future<void>.delayed(Duration.zero);
        await r.finish();
        await r.save(api);
        final (reg, body) = api.eventCalls.single;
        expect(reg, 'reg_1');
        expect(body['clientRef'], 'run-ref-0001');
        expect(body['segments'], isNotEmpty);
        expect(api.plainCalls, isEmpty);
        // The run is gone from the phone after a saved run, binding included.
        expect(r.eventRegistrationId, isNull);
      },
    );

    test(
      'a failed (offline) save keeps the run and retries with the same clientRef',
      () async {
        final r = make();
        r.bindEvent('reg_1', makeRef: () => 'run-ref-0002');
        await r.start(notificationTitle: 't', notificationText: 'x');
        for (final p in _track(500, start: DateTime.now().toUtc())) {
          gps.ctrl!.add(p);
        }
        await Future<void>.delayed(Duration.zero);
        await r.finish();
        api.failEvent = TimeoutException('offline');
        await expectLater(r.save(api), throwsA(isA<TimeoutException>()));
        expect(r.state, RunState.finished);
        api.failEvent = null;
        await r.save(api);
        expect(api.eventCalls.map((c) => c.$2['clientRef']), [
          'run-ref-0002',
          'run-ref-0002',
        ]);
      },
    );

    test(
      'the binding and clientRef come back after the app is closed',
      () async {
        final r = make();
        r.bindEvent('reg_9', makeRef: () => 'run-ref-0003');
        await r.start(notificationTitle: 't', notificationText: 'x');
        for (final p in _track(500, start: DateTime.now().toUtc())) {
          gps.ctrl!.add(p);
        }
        await Future<void>.delayed(Duration.zero);
        await r.pause();
        final again = make();
        await again.restore();
        expect(again.eventRegistrationId, 'reg_9');
        expect(again.clientRef, 'run-ref-0003');
      },
    );

    test(
      'keep the run without the event: the plain route, no clientRef',
      () async {
        final r = make();
        r.bindEvent('reg_1', makeRef: () => 'run-ref-0004');
        await r.start(notificationTitle: 't', notificationText: 'x');
        for (final p in _track(500, start: DateTime.now().toUtc())) {
          gps.ctrl!.add(p);
        }
        await Future<void>.delayed(Duration.zero);
        await r.finish();
        await r.saveWithoutEvent(api);
        expect(api.plainCalls, hasLength(1));
        expect(api.plainCalls.single.containsKey('clientRef'), isFalse);
        expect(api.eventCalls, isEmpty);
      },
    );

    test('a run under way for another registration is not re-bound', () async {
      final r = make();
      r.bindEvent('reg_1', makeRef: () => 'run-ref-0005');
      await r.start(notificationTitle: 't', notificationText: 'x');
      expect(r.bindEvent('reg_2'), isFalse);
      expect(r.eventRegistrationId, 'reg_1');
    });
  });

  group('entry points on the ticket and registration pages', () {
    Future<void> pumpEntry(
      WidgetTester tester,
      RecordingApi api, {
      required DateTime startsAt,
      required DateTime endsAt,
      bool supported = true,
      bool runs = true,
      bool results = true,
      bool confirmed = true,
      bool participant = true,
      String status = 'published',
    }) async {
      final recorder = RunRecorder(
        gps: _Gps(supported: supported),
        store: _Store(),
      );
      final event = EventSummary.fromJson({
        ...summary('evt_1'),
        'status': status,
        'startsAt': startsAt.toIso8601String(),
        'endsAt': endsAt.toIso8601String(),
      });
      await pumpPage(
        tester,
        api,
        Builder(
          builder: (context) {
            final outer = AppScope.of(context);
            return AppScope(
              api: outer.api,
              auth: outer.auth,
              runRecorder: recorder,
              child: EventResultEntry(
                registrationId: 'reg_1',
                event: event,
                options: optsS6(runs: runs, enabled: results),
                confirmed: confirmed,
                isParticipant: participant,
              ),
            );
          },
        ),
        user: member,
        extraRoutes: s6Routes,
      );
    }

    apiTest(
      'running now, Android: Start run, Add a recorded run, Your result',
      (tester, api) async {
        await pumpEntry(
          tester,
          api,
          startsAt: _now.subtract(const Duration(hours: 1)),
          endsAt: _now.add(const Duration(hours: 4)),
        );
        expect(find.byKey(const Key('entry-start-run')), findsOneWidget);
        expect(find.byKey(const Key('entry-add-run')), findsOneWidget);
        expect(find.byKey(const Key('entry-result')), findsOneWidget);
        await tester.tap(find.byKey(const Key('entry-start-run')));
        await tester.pumpAndSettle();
        expect(find.text('ROUTE-RECORD-reg_1'), findsOneWidget);
      },
    );

    apiTest('a phone that cannot record: the fallback and Add a recorded run', (
      tester,
      api,
    ) async {
      await pumpEntry(
        tester,
        api,
        supported: false,
        startsAt: _now.subtract(const Duration(hours: 1)),
        endsAt: _now.add(const Duration(hours: 4)),
      );
      expect(find.byKey(const Key('entry-start-run')), findsNothing);
      expect(find.byKey(const Key('entry-run-unsupported')), findsOneWidget);
      await tester.tap(find.byKey(const Key('entry-add-run')));
      await tester.pumpAndSettle();
      expect(find.text('ROUTE-RUNS-reg_1'), findsOneWidget);
    });

    apiTest('before the event: nothing (no result yet, window not open)', (
      tester,
      api,
    ) async {
      await pumpEntry(
        tester,
        api,
        startsAt: _now.add(const Duration(days: 20)),
        endsAt: _now.add(const Duration(days: 20, hours: 5)),
      );
      expect(find.byKey(const Key('result-entry')), findsNothing);
    });

    apiTest('long after the event: Your result stays, runs are closed', (
      tester,
      api,
    ) async {
      await pumpEntry(
        tester,
        api,
        startsAt: _now.subtract(const Duration(days: 30, hours: 5)),
        endsAt: _now.subtract(const Duration(days: 30)),
      );
      expect(find.byKey(const Key('entry-result')), findsOneWidget);
      expect(find.byKey(const Key('entry-start-run')), findsNothing);
      expect(find.byKey(const Key('entry-add-run')), findsNothing);
    });

    apiTest('flags off, purchaser, unconfirmed, cancelled: nothing at all', (
      tester,
      api,
    ) async {
      final s = _now.subtract(const Duration(hours: 1));
      final e = _now.add(const Duration(hours: 4));
      await pumpEntry(
        tester,
        api,
        startsAt: s,
        endsAt: e,
        runs: false,
        results: false,
      );
      expect(find.byKey(const Key('result-entry')), findsNothing);
      await pumpEntry(tester, api, startsAt: s, endsAt: e, participant: false);
      expect(find.byKey(const Key('result-entry')), findsNothing);
      await pumpEntry(tester, api, startsAt: s, endsAt: e, confirmed: false);
      expect(find.byKey(const Key('result-entry')), findsNothing);
      await pumpEntry(tester, api, startsAt: s, endsAt: e, status: 'cancelled');
      expect(find.byKey(const Key('result-entry')), findsNothing);
    });

    apiTest('runs on, results off: only the run entries', (tester, api) async {
      await pumpEntry(
        tester,
        api,
        results: false,
        startsAt: _now.subtract(const Duration(hours: 1)),
        endsAt: _now.add(const Duration(hours: 4)),
      );
      expect(find.byKey(const Key('entry-result')), findsNothing);
      expect(find.byKey(const Key('entry-add-run')), findsOneWidget);
    });
  });

  group('Add a recorded run', () {
    const runsPath = 'GET /me/event-registrations/reg_1/result';

    Future<void> pump(
      WidgetTester tester,
      RecordingApi api, {
      String eventType = 'road',
      List<Map<String, dynamic>> runLinks = const [],
      List<Map<String, dynamic>>? activities,
      DateTime? startsAt,
    }) async {
      final s = startsAt ?? _now.subtract(const Duration(hours: 2));
      api.on(
        runsPath,
        resultPayload(
          eventType: eventType,
          stage: 'none',
          result: null,
          runLinks: runLinks,
        ),
      );
      api.on('GET /events/evt_1', {
        ...detail('evt_1'),
        'type': eventType,
        'startsAt': s.toIso8601String(),
        'endsAt': s.add(const Duration(hours: 6)).toIso8601String(),
      });
      api.on('GET /me/activities', {
        'activities':
            activities ??
            [_actJson('a_ok', _now.subtract(const Duration(minutes: 30)))],
      });
      await pumpPage(
        tester,
        api,
        EventRunLinksPage(registrationId: 'reg_1', options: optsS6()),
        user: member,
        extraRoutes: s6Routes,
        keepRequests: true,
      );
    }

    apiTest('lists recent FitFlex runs with their state, and nothing else', (
      tester,
      api,
    ) async {
      await pump(
        tester,
        api,
        eventType: 'virtual',
        activities: [
          _actJson('a_ok', _now.subtract(const Duration(minutes: 30))),
          _actJson(
            'a_short',
            _now.subtract(const Duration(minutes: 40)),
            km: 5,
          ),
          _actJson('a_old', _now.subtract(const Duration(days: 3))),
          _actJson(
            'a_dev',
            _now.subtract(const Duration(minutes: 50)),
            source: 'device',
          ),
        ],
      );
      expect(find.byKey(const Key('run-row-a_ok')), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text("Doesn't reach 21.10 km"), findsOneWidget);
      expect(find.text('Outside the event time'), findsOneWidget);
      // A device-synced run is not listed at all.
      expect(find.byKey(const Key('run-row-a_dev')), findsNothing);
    });

    apiTest('an already added run is marked and cannot be added again', (
      tester,
      api,
    ) async {
      await pump(
        tester,
        api,
        runLinks: [
          {
            'id': 'lnk_1',
            'linkType': 'evidence',
            'activityId': 'a_ok',
            'distanceMeters': 21200,
            'movingSeconds': 6996,
            'startedAt': _now.toIso8601String(),
            'canUnlink': true,
          },
        ],
      );
      expect(find.text('Already added'), findsOneWidget);
      await tester.tap(find.byKey(const Key('run-row-a_ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('run-confirm-add')), findsNothing);
    });

    apiTest(
      'in person: says it is shown beside the result; one POST with a key',
      (tester, api) async {
        await pump(tester, api);
        await tester.tap(find.byKey(const Key('run-row-a_ok')));
        await tester.pumpAndSettle();
        expect(
          find.text(
            "This run will be shown next to your official result. It isn't sent to the organizer.",
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('run-confirm-add')));
        await tester.pumpAndSettle();
        final post = api.only(
          'POST',
          '/me/event-registrations/reg_1/run-links',
        );
        expect(post.body, {'activityId': 'a_ok'});
        expect(post.headers['idempotency-key'], isNotEmpty);
      },
    );

    apiTest('virtual: says it goes to the organizer', (tester, api) async {
      await pump(tester, api, eventType: 'virtual');
      await tester.tap(find.byKey(const Key('run-row-a_ok')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The distance, time, pace and GPS quality checks of this run will be shared with the organizer of Dar Half Marathon to review. Your route is not shared.',
        ),
        findsOneWidget,
      );
    });

    apiTest('a refusal is explained in words, with the distance', (
      tester,
      api,
    ) async {
      await pump(tester, api, eventType: 'virtual');
      api.fail('POST /me/event-registrations/reg_1/run-links', 422, {
        'error': 'distance_too_short',
        'measuredMeters': 20000,
        'requiredMeters': 20675,
      });
      await tester.tap(find.byKey(const Key('run-row-a_ok')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run-confirm-add')));
      await tester.pumpAndSettle();
      expect(find.textContaining('shorter than 20.68 km'), findsOneWidget);
    });

    apiTest('removing a run asks the server and reloads', (tester, api) async {
      await pump(
        tester,
        api,
        runLinks: [
          {
            'id': 'lnk_1',
            'linkType': 'evidence',
            'activityId': 'a_other',
            'distanceMeters': 5000,
            'movingSeconds': 1500,
            'startedAt': _now.toIso8601String(),
            'canUnlink': true,
          },
        ],
      );
      await tester.tap(find.byKey(const Key('run-card-remove')));
      await tester.pumpAndSettle();
      expect(
        api.sent('DELETE', '/me/event-registrations/reg_1/run-links/lnk_1'),
        isTrue,
      );
    });

    apiTest('a phone that cannot record says so; the list is still there', (
      tester,
      api,
    ) async {
      await pump(tester, api);
      expect(find.byKey(const Key('runs-unsupported')), findsOneWidget);
      expect(find.byKey(const Key('runs-start')), findsNothing);
      expect(find.byKey(const Key('run-row-a_ok')), findsOneWidget);
    });

    apiTest('before the window: opens on a date, nothing to add', (
      tester,
      api,
    ) async {
      await pump(tester, api, startsAt: _now.add(const Duration(days: 10)));
      expect(find.byKey(const Key('runs-closed')), findsOneWidget);
      expect(find.textContaining('Adding runs opens'), findsOneWidget);
      expect(find.byKey(const Key('run-row-a_ok')), findsNothing);
    });

    apiTest('after the grace days: closed', (tester, api) async {
      await pump(
        tester,
        api,
        startsAt: _now.subtract(const Duration(days: 30)),
      );
      expect(find.text('Adding runs has closed.'), findsOneWidget);
    });

    apiTest('a waiting virtual run shows the organizer chip', (
      tester,
      api,
    ) async {
      await pump(
        tester,
        api,
        eventType: 'virtual',
        runLinks: [
          {
            'id': 'lnk_1',
            'linkType': 'event_run',
            'matchStatus': 'pending',
            'activityId': 'a_ok',
            'distanceMeters': 21200,
            'movingSeconds': 6996,
            'flags': ['implausible_pace'],
            'startedAt': _now.toIso8601String(),
          },
        ],
      );
      expect(find.text('Waiting for the organizer'), findsWidgets);
      expect(
        find.text(
          'Your run looks unusually fast. The organizer will check it.',
        ),
        findsOneWidget,
      );
    });

    apiTest('flag off: no request is made', (tester, api) async {
      await pumpPage(
        tester,
        api,
        EventRunLinksPage(
          registrationId: 'reg_1',
          options: optsS6(runs: false),
        ),
        user: member,
        extraRoutes: s6Routes,
        keepRequests: true,
      );
      expect(api.sent('GET', '/me/event-registrations/reg_1/result'), isFalse);
      expect(find.byKey(const Key('runs-unavailable')), findsOneWidget);
    });
  });

  group('the record-run screen for an event', () {
    Widget app(RunRecorder r, ApiClient api) {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => MemberDataScope(
              data: MemberData(),
              child: const MemberRecordRunPage(eventRegistrationId: 'reg_1'),
            ),
          ),
          GoRoute(
            path: AppRoutes.memberEventResult,
            builder: (_, _) => const Scaffold(body: Text('ROUTE-RESULT')),
          ),
          GoRoute(
            path: AppRoutes.memberActivity,
            builder: (_, _) => const Scaffold(body: Text('ROUTE-ACTIVITY')),
          ),
        ],
      );
      addTearDown(router.dispose);
      return AppScope(
        api: api,
        auth: AuthState(api),
        runRecorder: r,
        child: FFLocaleScope(
          notifier: FFLocale(),
          child: MaterialApp.router(
            routerConfig: router,
            theme: buildTheme(),
            supportedLocales: const [Locale('en'), Locale('sw')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        ),
      );
    }

    testWidgets('chip, "Save and add to event", refusal, keep without event', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final gps = _Gps();
      final api = _Api()
        ..failEvent = ApiException(422, {'error': 'run_outside_window'});
      final r = RunRecorder(gps: gps, store: _Store());
      await tester.pumpWidget(app(r, api));
      await tester.pumpAndSettle();
      expect(r.eventRegistrationId, 'reg_1');
      expect(find.text('Recording for Dar Half Marathon'), findsOneWidget);

      await tester.tap(find.byKey(const Key('run-start')));
      await tester.pump();
      await tester.runAsync(() async {
        for (final p in _track(1000, start: DateTime.now().toUtc())) {
          gps.ctrl!.add(p);
        }
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.tap(find.byKey(const Key('run-pause')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('run-finish')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run-finish-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Save and add to event'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('run-save')));
      await tester.tap(find.byKey(const Key('run-save')));
      await tester.pumpAndSettle();
      expect(api.eventCalls, hasLength(1));
      expect(
        find.textContaining('This run is outside the event time.'),
        findsOneWidget,
      );
      expect(r.state, RunState.finished, reason: 'the run is kept');

      await tester.ensureVisible(
        find.byKey(const Key('run-keep-without-event')),
      );
      await tester.tap(find.byKey(const Key('run-keep-without-event')));
      await tester.pumpAndSettle();
      expect(api.plainCalls, hasLength(1));
      expect(r.state, RunState.idle);
      expect(find.text('ROUTE-ACTIVITY'), findsOneWidget);
    });

    testWidgets('a good save goes back to the result page', (tester) async {
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final gps = _Gps();
      final api = _Api();
      final r = RunRecorder(gps: gps, store: _Store());
      await tester.pumpWidget(app(r, api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run-start')));
      await tester.pump();
      await tester.runAsync(() async {
        for (final p in _track(1000, start: DateTime.now().toUtc())) {
          gps.ctrl!.add(p);
        }
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.tap(find.byKey(const Key('run-pause')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('run-finish')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run-finish-confirm')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('run-save')));
      await tester.tap(find.byKey(const Key('run-save')));
      await tester.pumpAndSettle();
      expect(find.text('ROUTE-RESULT'), findsOneWidget);
    });
  });
}
