// Events S6 (spec §10.3, §14): the result page shows the server's own stage,
// the right words for each, the purchaser's status-only view, the offline
// copy, the once-only name prompt, and the dispute sheet.
import 'package:fitflexmobile/screens/member/events/results/member_event_result_page.dart';
import 'package:fitflexmobile/shared/events/events_cache.dart';
import 'package:fitflexmobile/shared/events/events_options.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/recording_api.dart';
import 's3_support.dart';
import 's6_support.dart';

const _path = 'GET /me/event-registrations/reg_1/result';

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
  Size size = const Size(375, 2400),
  double textScale = 1.0,
  EventsOptions? options,
}) => pumpPage(
  tester,
  api,
  MemberEventResultPage(registrationId: 'reg_1', options: options ?? optsS6()),
  user: member,
  lang: lang,
  size: size,
  textScale: textScale,
  extraRoutes: s6Routes,
  keepRequests: true,
);

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsCache.reset();
  });
  tearDown(() => debugEventsDiscoveryOverride = null);

  group('each stage shows its word, line and time', () {
    for (final (stage, chip, line) in const [
      ('official', 'Official', 'Verified and published by the organizer.'),
      ('provisional', 'Provisional', 'These times may still change.'),
      (
        'disputed',
        'Under review',
        'The organizer is reviewing a question about this result.',
      ),
    ]) {
      apiTest(stage, (tester, api) async {
        api.on(_path, resultPayload(stage: stage));
        await _pump(tester, api);
        expect(find.text(chip), findsOneWidget);
        expect(find.text(line), findsOneWidget);
        // 6,728,000 ms: 1:52:08, read out in words for a screen reader.
        expect(find.text('1:52:08'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Finish time 1 hr 52 min 8 sec'),
          findsOneWidget,
        );
        expect(find.text('Official timing'), findsOneWidget);
        expect(find.text('Bib 1042'), findsOneWidget);
      });
    }

    apiTest('official shows the rank line; provisional does not', (
      tester,
      api,
    ) async {
      api.on(_path, resultPayload(stage: 'official'));
      await _pump(tester, api);
      expect(find.text('Rank 12 of 430 in 21K'), findsOneWidget);
      api.on(_path, resultPayload(stage: 'provisional'));
      await _pump(tester, api);
      expect(find.textContaining('Rank 12'), findsNothing);
    });

    apiTest('corrected names the date and the organizer note', (
      tester,
      api,
    ) async {
      api.on(
        _path,
        resultPayload(
          stage: 'corrected',
          result: resultRow(
            correctedAt: '2027-03-16T09:00:00Z',
            correctionNote: 'Mat read late',
          ),
        ),
      );
      await _pump(tester, api);
      expect(find.text('Corrected'), findsOneWidget);
      expect(
        find.textContaining('The organizer corrected this result on 16 Mar'),
        findsOneWidget,
      );
      expect(
        find.text('Note from the organizer: Mat read late'),
        findsOneWidget,
      );
    });

    apiTest('disqualified shows no time and the word, with the reason', (
      tester,
      api,
    ) async {
      api.on(
        _path,
        resultPayload(
          stage: 'disqualified',
          result: resultRow(finishStatus: 'dq', reasonCode: 'rule_violation'),
        ),
      );
      await _pump(tester, api);
      expect(find.text('Disqualified'), findsWidgets);
      expect(find.byKey(const Key('result-time')), findsNothing);
      expect(
        find.text(
          'This result was disqualified because a rule of the event was broken.',
        ),
        findsOneWidget,
      );
    });

    apiTest('DNF shows "Did not finish", never a time', (tester, api) async {
      api.on(
        _path,
        resultPayload(
          stage: 'official',
          result: resultRow(finishStatus: 'dnf', categoryRank: null),
        ),
      );
      await _pump(tester, api);
      expect(find.text('Did not finish'), findsOneWidget);
      expect(find.text('No finish time was recorded.'), findsOneWidget);
      expect(find.byKey(const Key('result-time')), findsNothing);
    });

    apiTest('not published yet', (tester, api) async {
      api.on(
        _path,
        resultPayload(stage: 'none', result: null, releaseStage: 'none'),
      );
      await _pump(tester, api);
      expect(find.text('Not published'), findsOneWidget);
      expect(
        find.text(
          "Results aren't published yet. We'll tell you when they are.",
        ),
        findsOneWidget,
      );
    });

    apiTest('released but no result for this person', (tester, api) async {
      api.on(_path, resultPayload(stage: 'none', result: null));
      await _pump(tester, api);
      expect(
        find.text(
          'We have no result for you. If you finished, ask the organizer.',
        ),
        findsOneWidget,
      );
    });

    apiTest('personal best chip', (tester, api) async {
      api.on(_path, resultPayload(result: resultRow(pb: true)));
      await _pump(tester, api);
      expect(find.text('Personal best at this distance'), findsOneWidget);
    });

    apiTest('virtual GPS result says it is moving time', (tester, api) async {
      api.on(
        _path,
        resultPayload(
          eventType: 'virtual',
          stage: 'provisional',
          result: resultRow(sourceType: 'fitflex_gps'),
        ),
      );
      await _pump(tester, api);
      expect(find.text('Virtual run, GPS'), findsOneWidget);
      expect(
        find.text(
          'Virtual run. The time is moving time recorded by FitFlex GPS.',
        ),
        findsOneWidget,
      );
    });
  });

  group('who sees what', () {
    apiTest('the purchaser sees the stage word only', (tester, api) async {
      api.on(_path, {
        'registrationId': 'reg_1',
        'stage': 'official',
        'finishStatus': 'finished',
        'viewer': 'purchaser_status_only',
      });
      await _pump(tester, api);
      expect(find.text('Official'), findsOneWidget);
      expect(
        find.text(
          'Results for this ticket are shown to the person it belongs to.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('result-time')), findsNothing);
      expect(find.byKey(const Key('result-visibility')), findsNothing);
    });

    apiTest('a cancelled place shows no result', (tester, api) async {
      api.on(_path, resultPayload(registrationStatus: 'cancelled'));
      await _pump(tester, api);
      expect(
        find.text('Your place was cancelled, so no result is shown.'),
        findsWidgets,
      );
      expect(find.byKey(const Key('result-time')), findsNothing);
    });

    apiTest('options off: nothing is requested', (tester, api) async {
      await _pump(tester, api, options: optsS6(enabled: false));
      expect(api.sent('GET', '/me/event-registrations/reg_1/result'), isFalse);
      expect(find.byKey(const Key('result-unavailable')), findsOneWidget);
    });
  });

  group('offline and errors', () {
    apiTest('a network error with a saved copy shows it, labelled', (
      tester,
      api,
    ) async {
      api.on(_path, resultPayload());
      await _pump(tester, api);
      expect(find.byKey(const Key('result-cached')), findsNothing);
      // Second visit, phone offline.
      api.onCall(_path, (_) => throw const _Offline());
      await _pump(tester, api);
      expect(find.byKey(const Key('result-cached')), findsOneWidget);
      expect(
        find.textContaining('Saved on this phone, updated'),
        findsOneWidget,
      );
      expect(find.text('1:52:08'), findsOneWidget);
      // Actions that need the network are off.
      final tile = tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(const Key('result-visibility')),
          matching: find.byType(InkWell),
        ),
      );
      expect(tile.onTap, isNull);
    });

    apiTest('a server error shows the retry state', (tester, api) async {
      api.fail(_path, 500, {'error': 'server_error'});
      await _pump(tester, api);
      expect(find.byKey(const Key('result-error')), findsOneWidget);
      api.heal(_path);
      api.on(_path, resultPayload());
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('1:52:08'), findsOneWidget);
    });
  });

  group('who can see my name', () {
    apiTest('asked once for an older registration; the choice is a PUT', (
      tester,
      api,
    ) async {
      SharedPreferences.setMockInitialValues({});
      api.on(
        _path,
        resultPayload(
          visibility: {
            'current': 'bib_only',
            'canChange': true,
            'allowed': ['standard', 'bib_only', 'hidden'],
            'reason': 'ask',
          },
        ),
      );
      await _pump(tester, api);
      expect(find.text('Show your name on the results?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('visibility-standard')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('visibility-save')));
      await tester.pumpAndSettle();
      final put = api.only(
        'PUT',
        '/me/event-registrations/reg_1/results-visibility',
      );
      expect(put.body, {'visibility': 'standard'});
    });

    apiTest('dismissing keeps the current choice and sends nothing', (
      tester,
      api,
    ) async {
      SharedPreferences.setMockInitialValues({});
      api.on(
        _path,
        resultPayload(
          visibility: {
            'current': 'bib_only',
            'canChange': true,
            'allowed': ['standard', 'bib_only', 'hidden'],
            'reason': 'ask',
          },
        ),
      );
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('ff-sheet-close')));
      await tester.pumpAndSettle();
      expect(
        api.sent('PUT', '/me/event-registrations/reg_1/results-visibility'),
        isFalse,
      );
    });

    apiTest('not asked again within a week', (tester, api) async {
      SharedPreferences.setMockInitialValues({
        'events.result.asked.reg_1': DateTime.now().millisecondsSinceEpoch,
      });
      api.on(
        _path,
        resultPayload(
          visibility: {
            'current': 'bib_only',
            'canChange': true,
            'allowed': ['standard', 'bib_only', 'hidden'],
            'reason': 'ask',
          },
        ),
      );
      await _pump(tester, api);
      expect(find.text('Show your name on the results?'), findsNothing);
    });

    apiTest('a minor sees the fixed state and cannot change it', (
      tester,
      api,
    ) async {
      api.on(
        _path,
        resultPayload(
          visibility: {
            'current': 'bib_only',
            'canChange': false,
            'allowed': ['bib_only'],
            'reason': 'minor',
          },
        ),
      );
      await _pump(tester, api);
      expect(
        find.text('Results for under-18s show only the bib number.'),
        findsOneWidget,
      );
      final tile = tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(const Key('result-visibility')),
          matching: find.byType(InkWell),
        ),
      );
      expect(tile.onTap, isNull);
    });
  });

  group('questions about the result', () {
    apiTest('raise: a reason is required; one POST with an Idempotency-Key', (
      tester,
      api,
    ) async {
      api.on(_path, resultPayload());
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('result-dispute-ask')));
      await tester.pumpAndSettle();
      final send = find.byKey(const Key('dispute-send'));
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(of: send, matching: find.byType(FilledButton)),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('dispute-reason-time_wrong')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('dispute-note')), 'Mat late');
      await tester.tap(send);
      await tester.pumpAndSettle();
      final post = api.only(
        'POST',
        '/me/event-registrations/reg_1/result/disputes',
      );
      expect(post.body, {'reasonCode': 'time_wrong', 'note': 'Mat late'});
      expect(post.headers['idempotency-key'], isNotEmpty);
    });

    apiTest('an open question shows since-date and can be withdrawn', (
      tester,
      api,
    ) async {
      api.on(
        _path,
        resultPayload(
          stage: 'disputed',
          dispute: {
            'id': 'dsp_1',
            'status': 'open',
            'createdAt': '2027-03-16T09:00:00Z',
            'canRaise': false,
          },
        ),
      );
      await _pump(tester, api);
      expect(find.text('Under review since 16 Mar 2027'), findsOneWidget);
      expect(find.byKey(const Key('result-dispute-ask')), findsNothing);
      await tester.tap(find.byKey(const Key('result-dispute-withdraw')));
      await tester.pumpAndSettle();
      expect(
        api.sent(
          'DELETE',
          '/me/event-registrations/reg_1/result/disputes/dsp_1',
        ),
        isTrue,
      );
    });

    apiTest('an answered question shows the outcome and the note', (
      tester,
      api,
    ) async {
      api.on(
        _path,
        resultPayload(
          dispute: {
            'id': 'dsp_1',
            'status': 'rejected',
            'resolvedAt': '2027-03-17T09:00:00Z',
            'resolutionNote': 'Chip data checked',
            'canRaise': false,
          },
        ),
      );
      await _pump(tester, api);
      expect(
        find.textContaining(
          'Answered on 17 Mar 2027: No change was needed. Chip data checked',
        ),
        findsOneWidget,
      );
    });

    apiTest('a refused question shows the plain reason', (tester, api) async {
      api.on(_path, resultPayload());
      api.fail('POST /me/event-registrations/reg_1/result/disputes', 409, {
        'error': 'dispute_open',
      });
      await _pump(tester, api);
      await tester.tap(find.byKey(const Key('result-dispute-ask')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dispute-reason-other')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('dispute-send')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('already have a question open'),
        findsOneWidget,
      );
    });
  });

  group('layout', () {
    apiTest('two columns from 840 dp', (tester, api) async {
      api.on(_path, resultPayload());
      await _pump(tester, api, size: const Size(1000, 1400));
      expect(find.byKey(const Key('result-columns')), findsOneWidget);
    });

    apiTest('one column on a phone', (tester, api) async {
      api.on(_path, resultPayload());
      await _pump(tester, api);
      expect(find.byKey(const Key('result-columns')), findsNothing);
    });

    apiTest('Swahili at 320 dp and 200 percent text does not overflow', (
      tester,
      api,
    ) async {
      api.on(
        _path,
        resultPayload(
          stage: 'corrected',
          result: resultRow(
            correctedAt: '2027-03-16T09:00:00Z',
            correctionNote: 'Mat read late',
            pb: true,
          ),
          medals: [medalJson()],
        ),
      );
      await _pump(
        tester,
        api,
        lang: 'sw',
        size: const Size(320, 2600),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Yamesahihishwa'), findsOneWidget);
    });
  });
}

class _Offline implements Exception {
  const _Offline();
  @override
  String toString() => 'SocketException: Failed host lookup';
}
