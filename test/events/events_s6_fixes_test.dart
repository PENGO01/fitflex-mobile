// Events S6 fix round: the backend's real reason codes, grammatical
// sentences with and without a reason, sign-out and cache rules (security
// review M7), the medal screen-reader label, evicting medal pictures (L6),
// the new refusals, and Swahili layout at 320 dp and 200 % text.
import 'dart:async';
import 'dart:typed_data';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/member/events/results/event_results_board_page.dart';
import 'package:fitflexmobile/screens/member/events/results/event_run_links_page.dart';
import 'package:fitflexmobile/screens/member/events/results/member_event_result_page.dart';
import 'package:fitflexmobile/screens/member/events/results/member_medals_page.dart';
import 'package:fitflexmobile/screens/member/events/results/member_reward_wallet_page.dart';
import 'package:fitflexmobile/screens/member/events/results/results_widgets.dart';
import 'package:fitflexmobile/screens/member/member_record_run_page.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/activity/gps_source.dart';
import 'package:fitflexmobile/shared/activity/phone_steps.dart' show StepStore;
import 'package:fitflexmobile/shared/activity/run_metrics.dart';
import 'package:fitflexmobile/shared/activity/run_recorder.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/events/event_medal.dart';
import 'package:fitflexmobile/shared/events/events_cache.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/recording_api.dart';
import 'fixtures.dart' show detail;
import 's3_support.dart';
import 's6_support.dart';

const _result = 'GET /me/event-registrations/reg_1/result';
const _wallet = 'GET /me/event-rewards';

const _backendReasons = [
  'not_a_valid_run',
  'data_error',
  'duplicate',
  'timing_error',
  'wrong_bib',
  'late_finish_data',
  'rule_violation',
  'course_cut',
  'equipment',
  'identity',
  'virtual_evidence',
  'wrong_category',
  'other',
  'replaced_by_participant',
];

Future<PageHost> _pumpResult(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> user = member,
  String lang = 'en',
}) => pumpPage(
  tester,
  api,
  MemberEventResultPage(registrationId: 'reg_1', options: optsS6()),
  user: user,
  lang: lang,
  size: const Size(375, 2400),
  extraRoutes: s6Routes,
  keepRequests: true,
);

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsCache.reset();
    EventsCache.clock = DateTime.now;
    MedalArtLoader.reset();
    MedalArtLoader.fetch = null;
  });
  tearDown(() {
    debugEventsDiscoveryOverride = null;
    EventsCache.clock = DateTime.now;
    MedalArtLoader.fetch = null;
  });

  group('the backend\'s real reason codes', () {
    test('every code has words in both languages and none leaks the code', () {
      for (final c in _backendReasons) {
        final key = 'events.result.reason.$c';
        expect(FFLocale.keysOf('en'), contains(key), reason: c);
        expect(FFLocale.keysOf('sw'), contains(key), reason: c);
        expect(FFLocale.textOf('en', key), isNot(contains('_')), reason: c);
        expect(FFLocale.textOf('sw', key), isNot(contains('_')), reason: c);
      }
      expect(resultReasonCodes, _backendReasons.toSet());
      for (final c in [
        'result_corrected',
        'disqualified',
        'registration_cancelled',
        'event_cancelled',
        'rule_changed_by_admin',
        'source_revoked',
      ]) {
        expect(FFLocale.keysOf('sw'), contains('events.reason.$c'), reason: c);
      }
    });

    for (final lang in ['en', 'sw']) {
      testWidgets('words for every code ($lang)', (tester) async {
        late BuildContext ctx;
        await tester.pumpWidget(
          FFLocaleScope(
            notifier: FFLocale()..set(Locale(lang)),
            child: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
          ),
        );
        for (final c in _backendReasons) {
          expect(resultReasonWords(ctx, c), isNotEmpty, reason: c);
          expect(resultReasonWords(ctx, c), isNot(c), reason: c);
        }
        // Unknown and missing codes read as no reason, never a raw code.
        expect(resultReasonWords(ctx, 'virtual_gps_rejected'), '');
        expect(resultReasonWords(ctx, null), '');
        expect(medalReasonWords(ctx, 'source_revoked'), isNotEmpty);
        expect(medalReasonWords(ctx, 'made_up'), '');
      });
    }
  });

  group('sentences are whole with and without a reason', () {
    apiTest('disqualified: no reason, no dangling "because"', (
      tester,
      api,
    ) async {
      api.on(
        _result,
        resultPayload(
          stage: 'disqualified',
          result: resultRow(finishStatus: 'dq'),
        ),
      );
      await _pumpResult(tester, api);
      expect(find.text('This result was disqualified.'), findsOneWidget);
      expect(find.textContaining('because'), findsNothing);
    });

    apiTest('disqualified: an unknown code reads as no reason', (
      tester,
      api,
    ) async {
      api.on(
        _result,
        resultPayload(
          stage: 'disqualified',
          result: resultRow(finishStatus: 'dq', reasonCode: 'brand_new_code'),
        ),
      );
      await _pumpResult(tester, api);
      expect(find.text('This result was disqualified.'), findsOneWidget);
    });

    apiTest('rejected, with a reason', (tester, api) async {
      api.on(
        _result,
        resultPayload(
          stage: 'rejected',
          result: resultRow(
            finishStatus: 'finished',
            reasonCode: 'virtual_evidence',
          ),
        ),
      );
      await _pumpResult(tester, api);
      expect(
        find.text(
          "This result wasn't accepted because the run evidence was not accepted.",
        ),
        findsOneWidget,
      );
    });

    apiTest('Swahili: connector inside the sentence', (tester, api) async {
      api.on(
        _result,
        resultPayload(
          stage: 'disqualified',
          result: resultRow(finishStatus: 'dq', reasonCode: 'course_cut'),
        ),
      );
      await _pumpResult(tester, api, lang: 'sw');
      expect(
        find.text('Matokeo haya yamefutwa kwa sababu njia ilifupishwa.'),
        findsOneWidget,
      );
    });
  });

  group('medals', () {
    Future<void> pump(
      WidgetTester tester,
      RecordingApi api,
      Map<String, dynamic> body,
    ) async {
      api.on('GET /me/achievements', body);
      await pumpPage(
        tester,
        api,
        MemberMedalsPage(options: optsS6()),
        user: member,
        extraRoutes: s6Routes,
        keepRequests: true,
        size: const Size(375, 2000),
      );
    }

    apiTest(
      'a removed medal with no reason says only "Removed", and is read as removed',
      (tester, api) async {
        await pump(tester, api, {
          'medals': [
            {
              ...medalJson(
                id: 'aw_9',
                status: 'revoked',
                revokedAt: '2027-03-18T10:00:00Z',
              ),
              'categoryName': null,
            },
          ],
          'achievements': [],
          'removed': [],
        });
        expect(find.text('Removed because'), findsNothing);
        expect(find.text('Removed'), findsNWidgets(2)); // section + tile line
        expect(
          find.bySemanticsLabel(
            'Finisher, Dar Half Marathon, removed 18 Mar 2027',
          ),
          findsOneWidget,
        );
      },
    );

    apiTest('a custom description keeps the event name in the label', (
      tester,
      api,
    ) async {
      final m = medalJson();
      (m['art'] as Map)['altText'] = {'en': 'A green ribbon', 'sw': 'Utepe'};
      await pump(tester, api, {
        'medals': [m],
        'achievements': [],
        'removed': [],
      });
      expect(
        find.bySemanticsLabel(
          'A green ribbon, Dar Half Marathon, 21K, awarded 15 Mar 2027',
        ),
        findsOneWidget,
      );
    });

    apiTest('a reason is spelled out', (tester, api) async {
      await pump(tester, api, {
        'medals': [
          medalJson(
            status: 'revoked',
            reasonCode: 'source_revoked',
            revokedAt: '2027-03-18T10:00:00Z',
          ),
        ],
        'achievements': [],
        'removed': [],
      });
      expect(
        find.text('Removed because the result it came from was removed'),
        findsOneWidget,
      );
    });

    test('achievements read the backend\'s current/target and status', () {
      final a = AchievementView.fromJson({
        'id': null,
        'key': 'three_events_year',
        'title': {'en': 'x', 'sw': 'y'},
        'status': 'locked',
        'awardedAt': null,
        'progress': {'current': 2, 'target': 3},
      })!;
      expect(a.earned, isFalse);
      expect(a.done, 2);
      expect(a.total, 3);
      expect(a.hasProgress, isTrue);
      final b = AchievementView.fromJson({
        'key': 'k',
        'status': 'awarded',
        'awardedAt': '2027-03-15T10:00:00Z',
        'progress': {'current': 3, 'target': 3},
      })!;
      expect(b.earned, isTrue);
      expect(b.hasProgress, isFalse);
    });

    testWidgets(
      'a 404 evicts every size; coming back to the app clears the pictures',
      (tester) async {
        var calls = 0;
        var fail = false;
        MedalArtLoader.fetch = (c, id, v) async {
          calls++;
          if (fail) throw ApiException(404, {'error': 'not_found'});
          return Uint8List.fromList([1, 2, 3]);
        };
        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
          ),
        );
        await MedalArtLoader.load(ctx, 'art_1', 'm256');
        await MedalArtLoader.load(ctx, 'art_1', 'm512');
        await MedalArtLoader.load(ctx, 'art_1', 'm256');
        expect(calls, 2, reason: 'the second m256 comes from memory');
        // App resumed: nothing is kept.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await MedalArtLoader.load(ctx, 'art_1', 'm256');
        expect(calls, 3);
        // Taken down: a 404 drops every size of that picture.
        fail = true;
        await MedalArtLoader.load(ctx, 'art_1', 'm128');
        fail = false;
        await MedalArtLoader.load(ctx, 'art_1', 'm256');
        expect(calls, 4, reason: 'm256 was evicted and the id is known gone');
      },
    );
  });

  group('saved copies (security review M7)', () {
    test(
      'clearAll removes every saved key, the prompts and in-memory copies',
      () async {
        SharedPreferences.setMockInitialValues({
          'events.result.asked.reg_1': 1,
          'unrelated': 'keep',
        });
        await EventsCache.putMine('result.u1.reg_1', {'a': 1});
        await EventsCache.putList({'items': []});
        await EventsCache.putDetail('evt_1', {'id': 'evt_1'});
        var hooked = false;
        EventsCache.clearHooks.add(() => hooked = true);
        addTearDown(EventsCache.clearHooks.clear);
        await EventsCache.clearAll();
        expect(await EventsCache.getMine('result.u1.reg_1'), isNull);
        expect(await EventsCache.getList(), isNull);
        expect(await EventsCache.getDetail('evt_1'), isNull);
        final p = await SharedPreferences.getInstance();
        expect(p.getKeys(), {'unrelated'});
        expect(hooked, isTrue);
      },
    );

    testWidgets('signing out runs it', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await EventsCache.putMine('wallet.u1', {'a': 1});
      final api = ApiClient(baseUrl: 'http://x');
      final auth = AuthState(api);
      await auth.signIn('token', {'id': 'u1', 'userType': 'member'});
      await tester.runAsync(auth.signOut);
      expect(await EventsCache.getMine('wallet.u1'), isNull);
    });

    test('a copy older than a day reads as missing', () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime(2027, 3, 1, 12);
      EventsCache.clock = () => now;
      await EventsCache.putMine('k', {'a': 1});
      // putMine stamps with DateTime.now; age it by moving the clock on.
      EventsCache.clock = () => DateTime.now().add(const Duration(hours: 23));
      expect(await EventsCache.getFreshMine('k'), isNotNull);
      EventsCache.clock = () => DateTime.now().add(const Duration(hours: 25));
      expect(await EventsCache.getFreshMine('k'), isNull);
      expect(await EventsCache.getMine('k'), isNull, reason: 'and is dropped');
    });

    apiTest('another member on the same phone never sees the saved result', (
      tester,
      api,
    ) async {
      api.on(_result, resultPayload());
      await _pumpResult(tester, api);
      expect(find.text('1:52:08'), findsOneWidget);
      api.onCall(_result, (_) => throw StateError('SocketException: offline'));
      await _pumpResult(tester, api, user: {'id': 'u2', 'userType': 'member'});
      expect(find.byKey(const Key('result-cached')), findsNothing);
      expect(find.byKey(const Key('result-error')), findsOneWidget);
      // The first member's own copy is still theirs.
      await _pumpResult(tester, api);
      expect(find.byKey(const Key('result-cached')), findsOneWidget);
    });

    apiTest('a saved result older than a day is not shown offline', (
      tester,
      api,
    ) async {
      api.on(_result, resultPayload());
      await _pumpResult(tester, api);
      api.onCall(_result, (_) => throw StateError('SocketException: offline'));
      EventsCache.clock = () => DateTime.now().add(const Duration(hours: 25));
      await _pumpResult(tester, api);
      expect(find.byKey(const Key('result-cached')), findsNothing);
      expect(find.byKey(const Key('result-error')), findsOneWidget);
    });

    apiTest('the saved copy says when it was last updated', (
      tester,
      api,
    ) async {
      api.on(_result, resultPayload());
      await _pumpResult(tester, api);
      api.onCall(_result, (_) => throw StateError('SocketException: offline'));
      await _pumpResult(tester, api);
      expect(
        find.textContaining('Saved on this phone, updated'),
        findsOneWidget,
      );
    });

    apiTest('a perk code is never written to the phone', (tester, api) async {
      api.on(_wallet, {
        'available': [],
        'redemptions': [
          {
            'id': 'red_2',
            'definitionId': 'rwd_1',
            'title': {'en': 'Perk', 'sw': 'x'},
            'redeemMode': 'perk',
            'status': 'reserved',
            'code': 'FFR-AB12CD34',
            'expiresAt': '2027-04-03T00:00:00Z',
          },
        ],
        'expired': [],
      });
      api.on('GET /me/reward-ledger', {'items': []});
      await pumpPage(
        tester,
        api,
        MemberRewardWalletPage(options: optsS6()),
        user: member,
        extraRoutes: s6Routes,
        keepRequests: true,
      );
      expect(find.text('FFR-AB12CD34'), findsOneWidget, reason: 'shown live');
      final p = await SharedPreferences.getInstance();
      for (final k in p.getKeys()) {
        expect(p.get(k).toString(), isNot(contains('FFR-')), reason: k);
      }
      // Offline: the entry is there, the code is not.
      api.onCall(_wallet, (_) => throw StateError('SocketException: offline'));
      await pumpPage(
        tester,
        api,
        MemberRewardWalletPage(options: optsS6()),
        user: member,
        extraRoutes: s6Routes,
        keepRequests: true,
      );
      expect(find.byKey(const Key('wallet-cached')), findsOneWidget);
      expect(find.text('FFR-AB12CD34'), findsNothing);
    });
  });

  group('new refusals', () {
    for (final lang in ['en', 'sw']) {
      test('words for each ($lang)', () {
        final locale = FFLocale()..set(Locale(lang));
        for (final code in const [
          'evidence_limit',
          'link_locked',
          'linking_closed',
          'registration_not_confirmed',
          'result_exists',
          'no_result',
          'rewards_unavailable',
          'dispute_closed',
          'dispute_not_found',
          'request_in_progress',
          'redemption_expired',
          'ticket_revoked',
          'activity_not_found',
          'link_not_found',
          'invalid_route',
        ]) {
          final msg = errorMessage(locale, ApiException(409, {'error': code}));
          expect(msg, isNot(contains(code)), reason: code);
          expect(msg, isNot(contains('_')), reason: code);
        }
      });
    }

    test(
      'organizer_owner shows the server\'s sentence in the app language',
      () {
        final body = {
          'error': 'organizer_owner',
          'message': 'Transfer or close your organizer account first.',
          'messageSw': 'Hamisha au funga akaunti yako ya mwandaaji kwanza.',
        };
        final en = FFLocale()..set(const Locale('en'));
        final sw = FFLocale()..set(const Locale('sw'));
        expect(
          errorMessage(en, ApiException(409, body)),
          contains('Transfer or close'),
        );
        expect(
          errorMessage(sw, ApiException(409, body)),
          contains('Hamisha au funga'),
        );
        // Without the sentences the app's own copy is used.
        expect(
          errorMessage(en, ApiException(409, {'error': 'organizer_owner'})),
          contains('Transfer or close'),
        );
      },
    );
  });

  group('Swahili mechanical fixes', () {
    String sw(String k) => FFLocale.textOf('sw', k)!;
    test('wording', () {
      expect(sw('events.result.bib'), 'Namba ya mbio {number}');
      expect(sw('events.medals.designBy'), 'Muundo wa {organizer}');
      expect(sw('events.rewards.status.reserved'), 'Inasubiri kutumika');
      expect(sw('events.result.visibility.askBody'), isNot(contains('ubao')));
      expect(
        sw('events.result.visibility.askBody'),
        contains('orodha ya matokeo'),
      );
      expect(
        sw('events.result.visibility.standard'),
        contains('herufi ya jina la mwisho'),
      );
      expect(
        FFLocale.textOf('en', 'events.result.visibility.standard'),
        contains('last initial'),
      );
      expect(sw('events.run.confirm.virtual'), contains('vitashirikishwa'));
      expect(sw('events.run.confirm.virtual'), contains('GPS'));
      expect(sw('events.board.banner.provisional'), 'Matokeo ya awali');
      expect(sw('events.result.stage.provisional'), 'Ya awali');
    });
  });

  group('Swahili at 320 dp and 200 percent text: no overflow', () {
    apiTest('result page', (tester, api) async {
      api.on(
        _result,
        resultPayload(
          stage: 'disqualified',
          result: resultRow(finishStatus: 'dq', reasonCode: 'identity'),
          medals: [medalJson()],
          runLinks: [
            {
              'id': 'l1',
              'linkType': 'event_run',
              'matchStatus': 'pending',
              'distanceMeters': 21200,
              'movingSeconds': 6996,
              'flags': ['implausible_pace'],
              'startedAt': '2027-03-14T04:00:00Z',
            },
          ],
        ),
      );
      await pumpPage(
        tester,
        api,
        MemberEventResultPage(registrationId: 'reg_1', options: optsS6()),
        user: member,
        lang: 'sw',
        size: const Size(320, 3200),
        textScale: 2.0,
        extraRoutes: s6Routes,
        keepRequests: true,
      );
      expect(tester.takeException(), isNull);
    });

    apiTest('board', (tester, api) async {
      api.on('GET /events/evt_1/results', {
        'event': {'title': 'Dar Half Marathon'},
        'release': {'stage': 'provisional'},
        'categories': [
          {'id': 'c1', 'name': '21K'},
          {'id': 'c2', 'name': '10K'},
        ],
        'items': [
          {
            'rank': 1,
            'bibNumber': '1001',
            'displayName': 'Asha M.',
            'elapsedMs': 6728000,
            'finishStatus': 'finished',
            'badges': ['corrected'],
          },
          {
            'rank': null,
            'bibNumber': '1002',
            'displayName': 'Runner',
            'elapsedMs': null,
            'finishStatus': 'dq',
            'badges': ['under_review'],
          },
        ],
        'mine': {'rank': 1, 'bibNumber': '1001'},
      });
      await pumpPage(
        tester,
        api,
        EventResultsBoardPage(
          eventId: 'evt_1',
          options: optsS6(),
          debounce: Duration.zero,
        ),
        user: member,
        lang: 'sw',
        size: const Size(320, 3200),
        textScale: 2.0,
        extraRoutes: s6Routes,
        keepRequests: true,
      );
      expect(tester.takeException(), isNull);
      // The server's literal "Runner" is shown as "Mkimbiaji {bib}".
      expect(find.text('Mkimbiaji 1002'), findsOneWidget);
    });

    apiTest('run links page', (tester, api) async {
      final now = DateTime.now().toUtc();
      api.on(
        _result,
        resultPayload(
          eventType: 'virtual',
          stage: 'none',
          result: null,
          runLinks: [
            {
              'id': 'l1',
              'linkType': 'event_run',
              'matchStatus': 'pending',
              'activityId': 'a1',
              'distanceMeters': 21200,
              'movingSeconds': 6996,
              'flags': ['implausible_pace'],
              'startedAt': now.toIso8601String(),
            },
          ],
        ),
      );
      api.on('GET /events/evt_1', {
        ...detail('evt_1'),
        'type': 'virtual',
        'startsAt': now.subtract(const Duration(hours: 2)).toIso8601String(),
        'endsAt': now.add(const Duration(hours: 4)).toIso8601String(),
      });
      api.on('GET /me/activities', {
        'activities': [
          for (final (id, km) in [('a_ok', 21.2), ('a_short', 5.0)])
            {
              'id': id,
              'userId': 'u1',
              'type': 'running',
              'source': 'fitflex',
              'startedAt': now
                  .subtract(const Duration(minutes: 30))
                  .toIso8601String(),
              'distanceKm': km,
              'movingSeconds': 5000,
              'hasRoute': true,
              'splits': <int>[],
            },
        ],
      });
      await pumpPage(
        tester,
        api,
        EventRunLinksPage(registrationId: 'reg_1', options: optsS6()),
        user: member,
        lang: 'sw',
        size: const Size(320, 3200),
        textScale: 2.0,
        extraRoutes: s6Routes,
        keepRequests: true,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('run-row-a_ok')), findsOneWidget);
    });

    testWidgets('record-run page for an event, finished', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 4200 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final gps = _Gps();
      final api = _Api();
      final r = RunRecorder(gps: gps, store: _Store());
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
            builder: (_, _) => const Scaffold(body: Text('R')),
          ),
          GoRoute(
            path: AppRoutes.memberActivity,
            builder: (_, _) => const Scaffold(body: Text('A')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        AppScope(
          api: api,
          auth: AuthState(api),
          runRecorder: r,
          child: FFLocaleScope(
            notifier: FFLocale()..set(const Locale('sw')),
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
                ).copyWith(textScaler: const TextScaler.linear(2.0)),
                child: c!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run-start')));
      await tester.pump();
      await tester.runAsync(() async {
        for (var i = 0; i <= 10; i++) {
          gps.ctrl!.add(
            TrackPoint(
              -6.8 + i * 0.0009,
              39.28,
              20,
              DateTime.now().toUtc().add(Duration(seconds: i * 30)),
              5,
            ),
          );
        }
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'while recording');
      await tester.tap(find.byKey(const Key('run-pause')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('run-finish')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run-finish-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('run-event-chip')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'when finished');
    });
  });
}

class _Gps implements GpsSource {
  StreamController<TrackPoint>? ctrl;
  @override
  bool get isSupported => true;
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
  @override
  Future<Map<String, dynamic>> getMyEventResult(String registrationId) async =>
      resultPayload(eventType: 'virtual', stage: 'none', result: null);
}
