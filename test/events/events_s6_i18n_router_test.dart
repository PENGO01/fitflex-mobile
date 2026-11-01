// Events S6 (spec §10.7, §12.2): every new string exists in both languages,
// the routes sit behind the events flag and before :eventId, the eight push
// types open the right screen, each refusal has words, the models read
// tolerant JSON, and an older server (no `results` block) switches all of it
// off.
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/member/events/member_event_detail_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/events/event_detail.dart';
import 'package:fitflexmobile/shared/events/event_medal.dart';
import 'package:fitflexmobile/shared/events/event_result.dart';
import 'package:fitflexmobile/shared/events/event_reward.dart';
import 'package:fitflexmobile/shared/events/event_time.dart';
import 'package:fitflexmobile/shared/events/events_cache.dart';
import 'package:fitflexmobile/shared/events/events_options.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's6_support.dart';

const s6Keys = <String>[
  'events.result.reason.not_a_valid_run',
  'events.result.reason.data_error',
  'events.result.reason.duplicate',
  'events.result.reason.timing_error',
  'events.result.reason.wrong_bib',
  'events.result.reason.late_finish_data',
  'events.result.reason.rule_violation',
  'events.result.reason.course_cut',
  'events.result.reason.equipment',
  'events.result.reason.identity',
  'events.result.reason.virtual_evidence',
  'events.reason.source_revoked',
  'events.result.line.dq.because',
  'events.result.line.rejected.because',
  'events.medals.removedNoReason',
  'events.medals.alt.removed',
  'events.medals.awardedOn',
  'events.medals.removedOn',
  'events.error.evidence_limit',
  'events.error.link_locked',
  'events.error.linking_closed',
  'events.error.registration_not_confirmed',
  'events.error.result_exists',
  'events.error.no_result',
  'events.error.rewards_unavailable',
  'events.error.dispute_closed',
  'events.error.dispute_not_found',
  'events.error.request_in_progress',
  'events.error.redemption_expired',
  'events.error.activity_not_found',
  'events.error.link_not_found',
  'events.error.organizer_owner',
  'events.result.title',
  'events.result.stage.provisional',
  'events.result.stage.official',
  'events.result.stage.corrected',
  'events.result.stage.underReview',
  'events.result.stage.disqualified',
  'events.result.stage.rejected',
  'events.result.stage.none',
  'events.result.line.none',
  'events.result.line.provisional',
  'events.result.line.official',
  'events.result.line.corrected',
  'events.result.line.underReview',
  'events.result.line.dnf',
  'events.result.line.dns',
  'events.result.line.dq',
  'events.result.line.rejected',
  'events.result.line.virtual',
  'events.result.source.timing_provider',
  'events.result.source.organizer_verified',
  'events.result.source.fitflex_gps',
  'events.result.source.manual_unverified',
  'events.result.rank',
  'events.result.pb',
  'events.result.bib',
  'events.result.time',
  'events.result.note',
  'events.result.noneYet',
  'events.result.status.dnf',
  'events.result.status.dns',
  'events.result.status.dq',
  'events.result.empty.noneForYou',
  'events.result.empty.mine',
  'events.result.purchaser',
  'events.result.cancelled',
  'events.result.claimFirst',
  'events.result.cached',
  'events.result.entry.myResults',
  'events.result.reason.replaced_by_participant',
  'events.result.reason.wrong_category',
  'events.result.reason.other',
  'events.result.dispute.ask',
  'events.result.dispute.title',
  'events.result.dispute.reason.time_wrong',
  'events.result.dispute.reason.not_my_result',
  'events.result.dispute.reason.wrong_category',
  'events.result.dispute.reason.dq_challenge',
  'events.result.dispute.reason.other',
  'events.result.dispute.note',
  'events.result.dispute.send',
  'events.result.dispute.open',
  'events.result.dispute.closed',
  'events.result.dispute.status.open',
  'events.result.dispute.status.upheld',
  'events.result.dispute.status.rejected',
  'events.result.dispute.status.withdrawn',
  'events.result.dispute.window',
  'events.result.dispute.closedWindow',
  'events.result.dispute.withdraw',
  'events.result.error.dispute_open',
  'events.result.error.result_not_found',
  'events.result.error.visibility_not_allowed',
  'events.result.visibility.title',
  'events.result.visibility.standard',
  'events.result.visibility.bib_only',
  'events.result.visibility.hidden',
  'events.result.visibility.minor',
  'events.result.visibility.ask',
  'events.result.visibility.askBody',
  'events.result.visibility.save',
  'events.duration.spoken.hms',
  'events.duration.spoken.ms',
  'events.run.start',
  'events.run.save',
  'events.run.keep',
  'events.run.add',
  'events.run.addThis',
  'events.run.section',
  'events.run.card.title',
  'events.run.empty',
  'events.run.noneRecent',
  'events.run.listFailed',
  'events.run.unsupported',
  'events.run.state.available',
  'events.run.state.short',
  'events.run.state.outside',
  'events.run.state.linked',
  'events.run.confirm.virtual',
  'events.run.confirm.inPerson',
  'events.run.notOfficial',
  'events.run.compare',
  'events.run.slower',
  'events.run.faster',
  'events.run.flag.fast',
  'events.run.waiting',
  'events.run.remove',
  'events.run.closed',
  'events.run.cancelled',
  'events.run.opens',
  'events.run.recordingFor',
  'events.run.thisEvent',
  'events.run.offlinePending',
  'events.run.error.run_outside_window',
  'events.run.error.distance_too_short',
  'events.run.error.activity_not_recorded_in_app',
  'events.run.error.activity_already_linked',
  'events.run.error.run_already_linked',
  'events.run.error.event_not_open_for_results',
  'events.board.title',
  'events.board.banner.provisional',
  'events.board.banner.official',
  'events.board.search',
  'events.board.you',
  'events.board.runner',
  'events.board.names',
  'events.board.empty',
  'events.board.signin',
  'events.board.rank.a11y',
  'events.medals.title',
  'events.medals.tab.medals',
  'events.medals.tab.achievements',
  'events.medals.empty',
  'events.medals.why',
  'events.medals.rule',
  'events.medals.removed',
  'events.medals.removedWhy',
  'events.medals.share',
  'events.medals.share.includeTime',
  'events.medals.designBy',
  'events.medals.report',
  'events.medals.report.sent',
  'events.medals.alt',
  'events.medals.tapHint',
  'events.achievement.progress',
  'events.achievement.earnedOn',
  'events.achievements.empty',
  'events.notice.medalArtTakenDown',
  'events.reason.result_corrected',
  'events.reason.disqualified',
  'events.reason.registration_cancelled',
  'events.reason.event_cancelled',
  'events.reason.rule_changed_by_admin',
  'events.rewards.title',
  'events.rewards.entry',
  'events.rewards.available',
  'events.rewards.claimed',
  'events.rewards.claim',
  'events.rewards.claim.confirm',
  'events.rewards.claim.bodyCertificate',
  'events.rewards.claim.bodyPerk',
  'events.rewards.claim.done',
  'events.rewards.terms',
  'events.rewards.expires',
  'events.rewards.expiredOn',
  'events.rewards.offline',
  'events.rewards.status.reserved',
  'events.rewards.status.redeemed',
  'events.rewards.status.expired',
  'events.rewards.status.cancelled',
  'events.rewards.code',
  'events.rewards.code.copy',
  'events.rewards.code.copied',
  'events.rewards.code.help',
  'events.rewards.certificate',
  'events.rewards.history',
  'events.rewards.entry.earn',
  'events.rewards.entry.redeem',
  'events.rewards.entry.expire',
  'events.rewards.entry.reverse',
  'events.rewards.empty',
  'events.rewards.error.reward_unavailable',
  'events.rewards.error.not_enough_units',
  'inbox.open.eventResult',
  'inbox.open.eventMedals',
  'inbox.open.eventRewards',
];

void main() {
  group('copy', () {
    test('every S6 key exists in both languages, and the maps match', () {
      final en = FFLocale.keysOf('en');
      final sw = FFLocale.keysOf('sw');
      for (final k in s6Keys) {
        expect(en, contains(k), reason: 'en $k');
        expect(sw, contains(k), reason: 'sw $k');
      }
      expect(en, sw);
    });

    test('Swahili is written, not English left in place', () {
      for (final k in s6Keys) {
        expect(
          FFLocale.textOf('sw', k),
          isNot(FFLocale.textOf('en', k)),
          reason: k,
        );
      }
    });

    test('glossary: "app" not "programu"; offline is "Hakuna intaneti"', () {
      for (final k in s6Keys) {
        expect(
          FFLocale.textOf('sw', k)!.toLowerCase(),
          isNot(contains('programu')),
          reason: k,
        );
      }
      expect(
        FFLocale.textOf('sw', 'events.run.offlinePending'),
        startsWith('Hakuna intaneti'),
      );
      expect(
        FFLocale.textOf('sw', 'events.rewards.offline'),
        startsWith('Hakuna intaneti'),
      );
    });

    test('placeholders are the same in both languages', () {
      final ph = RegExp(r'\{[a-zA-Z]+\}');
      for (final k in s6Keys) {
        final en = ph
            .allMatches(FFLocale.textOf('en', k)!)
            .map((m) => m[0])
            .toSet();
        final sw = ph
            .allMatches(FFLocale.textOf('sw', k)!)
            .map((m) => m[0])
            .toSet();
        expect(sw, en, reason: k);
      }
    });

    test('every stage and refusal the screens can name has copy', () {
      for (final s in ResultStage.values) {
        expect(FFLocale.keysOf('en'), contains(s.chipKey));
        expect(FFLocale.keysOf('en'), contains(s.lineKey));
      }
    });
  });

  group('refusals have words in both languages', () {
    for (final lang in ['en', 'sw']) {
      test(lang, () {
        final locale = FFLocale()..set(Locale(lang));
        for (final code in const [
          'run_outside_window',
          'activity_not_recorded_in_app',
          'activity_already_linked',
          'run_already_linked',
          'event_not_open_for_results',
          'dispute_open',
          'dispute_window_closed',
          'result_not_found',
          'visibility_not_allowed',
          'reward_unavailable',
          'not_enough_units',
        ]) {
          final msg = errorMessage(locale, ApiException(409, {'error': code}));
          expect(msg, isNot(contains(code)), reason: code);
          expect(msg, isNot(contains('_')), reason: code);
        }
        final short = errorMessage(
          locale,
          ApiException(422, {
            'error': 'distance_too_short',
            'measuredMeters': 20000,
            'requiredMeters': 21097,
          }),
        );
        expect(short, contains('21.10 km'));
        // Without the numbers it still reads as words.
        expect(
          errorMessage(
            locale,
            ApiException(422, {'error': 'distance_too_short'}),
          ),
          isNot(contains('_')),
        );
      });
    }
  });

  group('routes', () {
    tearDown(() => debugEventsDiscoveryOverride = null);

    GoRouterMatch match(String path) {
      final router = buildRouter(AuthState(ApiClient(baseUrl: 'http://x')));
      addTearDown(router.dispose);
      final m = router.configuration.findMatch(Uri.parse(path));
      return (
        name: m.isError ? null : m.last.route.name,
        params: m.pathParameters,
      );
    }

    test('flag on: each route matches its page', () {
      debugEventsDiscoveryOverride = true;
      expect(
        match('/member/events/registrations/reg_1/result').name,
        'memberEventResult',
      );
      expect(
        match(
          '/member/events/registrations/reg_1/result',
        ).params['registrationId'],
        'reg_1',
      );
      expect(
        match('/member/events/registrations/reg_1/runs').name,
        'memberEventRuns',
      );
      expect(match('/member/events/evt_1/results').name, 'memberEventResults');
      expect(match('/member/events/evt_1/results').params['eventId'], 'evt_1');
      // Static segments are not read as an event id.
      expect(match('/member/events/medals').name, 'memberEventMedals');
      expect(match('/member/events/rewards').name, 'memberEventRewards');
      expect(match('/member/events/results').name, 'memberEventMyResults');
      // The older routes are untouched.
      expect(match('/member/events/evt_1').name, 'memberEventDetail');
      expect(
        match('/member/events/registrations/reg_1/ticket').name,
        'memberEventTicket',
      );
      expect(match('/member/events/orders').name, 'memberEventOrders');
    });

    test('flag off: none of them exist', () {
      debugEventsDiscoveryOverride = false;
      for (final p in [
        '/member/events/registrations/reg_1/result',
        '/member/events/registrations/reg_1/runs',
        '/member/events/evt_1/results',
        '/member/events/medals',
        '/member/events/rewards',
        '/member/events/results',
      ]) {
        final router = buildRouter(AuthState(ApiClient(baseUrl: 'http://x')));
        addTearDown(router.dispose);
        expect(
          router.configuration.findMatch(Uri.parse(p)).isError,
          isTrue,
          reason: p,
        );
      }
    });

    test('the record-run route takes the registration from the query', () {
      debugEventsDiscoveryOverride = true;
      expect(
        match('/member/activity/run?registration=reg_1').name,
        'memberRecordRun',
      );
    });

    test('path helpers encode ids', () {
      expect(
        AppRoutes.memberEventResultPath('a b'),
        '/member/events/registrations/a%20b/result',
      );
      expect(
        AppRoutes.memberEventRunsPath('r1'),
        '/member/events/registrations/r1/runs',
      );
      expect(
        AppRoutes.memberEventResultsPath('e1'),
        '/member/events/e1/results',
      );
    });
  });

  group('notices open the right screen', () {
    String? route(String type, {String? registrationId}) => memberRouteFor(
      deepLink: '',
      type: type,
      registrationId: registrationId,
    );

    test('results, corrections, rejections and questions open the result', () {
      for (final t in [
        'event_result_published',
        'event_result_corrected',
        'event_result_rejected',
        'event_dispute_update',
      ]) {
        expect(
          route(t, registrationId: 'r1'),
          '/member/events/registrations/r1/result',
          reason: t,
        );
        // No id (or an unsafe one): the member's own results list.
        expect(route(t), '/member/events/results', reason: t);
        expect(
          route(t, registrationId: 'bad id!'),
          '/member/events/results',
          reason: t,
        );
        expect(memberLinkFor(deepLink: '', type: t), 'eventResult');
      }
    });

    test('medals and rewards', () {
      expect(route('event_medal_awarded'), '/member/events/medals');
      expect(route('event_medal_revoked'), '/member/events/medals');
      expect(route('event_reward_earned'), '/member/events/rewards');
      expect(route('event_reward_reversed'), '/member/events/rewards');
    });

    test('each link has a button label in both languages', () {
      for (final l in ['eventResult', 'eventMedals', 'eventRewards']) {
        expect(FFLocale.keysOf('en'), contains('inbox.open.$l'));
        expect(FFLocale.keysOf('sw'), contains('inbox.open.$l'));
      }
    });

    test('a push tap goes there directly', () {
      final t = pushTargetFor(
        role: 'member',
        data: {'type': 'event_result_published', 'registrationId': 'r1'},
      );
      expect(t.location, '/member/events/registrations/r1/result');
      expect(t.go, isTrue);
    });
  });

  group('options', () {
    test('an older server (no results block) switches everything off', () {
      final o = EventsOptions.fromJson({...optionsS3});
      expect(o.results.enabled, isFalse);
      expect(o.results.runs, isFalse);
      expect(o.results.public, isFalse);
      expect(o.results.rewards, isFalse);
      expect(o.results.medalArt, isFalse);
      expect(o.results.any, isFalse);
      expect(o.runs.toleranceBps, 200);
      expect(o.runs.maxDaysAfter, 7);
    });

    test('flags are read one by one', () {
      final o = optsS6(public: false, medalArt: false);
      expect(o.results.enabled, isTrue);
      expect(o.results.runs, isTrue);
      expect(o.results.public, isFalse);
      expect(o.results.rewards, isTrue);
      expect(o.results.medalArt, isFalse);
      expect(EventsOptions.off.results.any, isFalse);
    });

    test('junk reads as off', () {
      expect(EventsResultsOptions.fromJson('x').enabled, isFalse);
      expect(
        EventsResultsOptions.fromJson({'enabled': 'yes'}).enabled,
        isFalse,
      );
    });
  });

  group('models', () {
    test('stages: the server\'s words; unknown reads as "not published"', () {
      expect(ResultStage.parse('official'), ResultStage.official);
      expect(ResultStage.parse('under_review'), ResultStage.disputed);
      expect(ResultStage.parse('disputed'), ResultStage.disputed);
      expect(ResultStage.parse('dq'), ResultStage.disqualified);
      expect(ResultStage.parse('something_new'), ResultStage.none);
      expect(ResultStage.parse(null), ResultStage.none);
    });

    test('a full result payload', () {
      final r = MemberEventResult.fromJson(
        resultPayload(
          stage: 'corrected',
          runLinks: [
            {
              'id': 'l1',
              'linkType': 'event_run',
              'matchStatus': 'pending',
              'distanceMeters': 21200,
              'movingSeconds': 6996,
              'flags': ['implausible_pace'],
              'activityId': null,
              'canUnlink': true,
            },
          ],
          medals: [medalJson()],
          rewards: [
            {
              'definitionId': 'rwd_1',
              'title': {'en': 'Certificate', 'sw': 'Cheti'},
              'units': 1,
            },
          ],
        ),
      );
      expect(r.stage, ResultStage.corrected);
      expect(r.result!.shownMs, 6728000);
      expect(r.result!.categoryRank, 12);
      expect(r.runLinks.single.isFast, isTrue);
      expect(r.liveEventRun, isNotNull);
      expect(r.medals.single.name.of('sw'), 'Mshindi');
      expect(r.rewardsEarned.single.title.of('sw'), 'Cheti');
      expect(r.visibility.canChange, isTrue);
    });

    test('missing blocks and a DNF never invent a time', () {
      final r = MemberEventResult.fromJson({'registrationId': 'r'});
      expect(r.stage, ResultStage.none);
      expect(r.result, isNull);
      expect(r.runLinks, isEmpty);
      expect(r.medals, isEmpty);
      expect(r.visibility.current, 'standard');
      final dnf = EventResultRow.fromJson({
        'finishStatus': 'dnf',
        'elapsedMs': 5000,
      })!;
      expect(dnf.shownMs, isNull);
    });

    test('the ranking time wins, then net, then gun', () {
      expect(
        EventResultRow.fromJson({
          'elapsedMs': 3000,
          'netElapsedMs': 2000,
        })!.shownMs,
        3000,
      );
      expect(
        EventResultRow.fromJson({
          'netElapsedMs': 2000,
          'gunElapsedMs': 2500,
        })!.shownMs,
        2000,
      );
      expect(EventResultRow.fromJson({'gunElapsedMs': 2500})!.shownMs, 2500);
    });

    test('time formats', () {
      expect(formatResultTime(6728000), '1:52:08');
      expect(formatResultTime(754000), '12:34');
      expect(formatResultTime(-5), '0:00');
      expect(resultTimeParts(6728000), (h: 1, m: 52, s: 8));
    });

    test('medals: strings or maps for the organizer, art falls back', () {
      final m = MedalAward.fromJson({
        ...medalJson(),
        'organizerName': null,
        'organizer': {'name': 'Pwani Runners'},
        'art': null,
      })!;
      expect(m.organizerName, 'Pwani Runners');
      expect(m.art.isCustom, isFalse);
      expect(MedalAward.fromJson({'id': ''}), isNull);
      expect(MedalAward.fromJson('x'), isNull);
    });

    test('achievements: progress only for the unearned', () {
      final a = AchievementView.fromJson({
        'key': 'k',
        'title': {'en': 'T', 'sw': 'U'},
        'progress': {'done': 1, 'total': 3},
      })!;
      expect(a.earned, isFalse);
      expect(a.hasProgress, isTrue);
      final b = AchievementView.fromJson({
        'key': 'k',
        'earned': true,
        'progress': {'done': 3, 'total': 3},
      })!;
      expect(b.hasProgress, isFalse);
    });

    test('wallet: claimable units and the perk flag; no balance field', () {
      final w = RewardWallet.fromJson({
        'available': [
          {
            'definitionId': 'd1',
            'title': {'en': 'A', 'sw': 'B'},
            'units': 2,
            'redeemMode': 'perk',
          },
        ],
        'redemptions': [
          {
            'id': 'r1',
            'status': 'reserved',
            'code': 'FFR-1',
            'redeemMode': 'perk',
          },
        ],
      });
      expect(w.available.single.isPerk, isTrue);
      expect(w.available.single.canClaim, isTrue);
      expect(w.redemptions.single.isReserved, isTrue);
      expect(w.isEmpty, isFalse);
      expect(RewardWallet.fromJson(null).isEmpty, isTrue);
    });
  });

  group('event detail: Results button', () {
    setUp(() {
      debugEventsDiscoveryOverride = true;
      debugPhotoHeroUiOverride = false;
      debugDeviceOffsetMinutesOverride = 180;
      EventsCache.reset();
    });
    tearDown(() {
      debugEventsDiscoveryOverride = null;
      debugPhotoHeroUiOverride = null;
      debugDeviceOffsetMinutesOverride = null;
    });

    Future<void> pump(
      WidgetTester tester,
      RecordingApi api, {
      required String stage,
      bool public = true,
    }) async {
      api.on('GET /events/evt_1', {
        ...detail('evt_1'),
        'results': {'stage': stage, 'releasedAt': null, 'categories': []},
      });
      await pumpPage(
        tester,
        api,
        MemberEventDetailPage(
          eventId: 'evt_1',
          options: optsS6(public: public),
          now: DateTime.utc(2027, 3, 10, 12),
        ),
        user: const {'id': 'u1', 'userType': 'member'},
        size: const Size(375, 5000),
        extraRoutes: s6Routes,
        keepRequests: true,
      );
    }

    apiTest('official: the Results tile opens the board', (tester, api) async {
      await pump(tester, api, stage: 'official');
      expect(find.byKey(const Key('event-results')), findsOneWidget);
      expect(find.text('Official results'), findsOneWidget);
    });

    apiTest('provisional: says so', (tester, api) async {
      await pump(tester, api, stage: 'provisional');
      expect(find.text('Provisional results'), findsOneWidget);
    });

    apiTest('none, or the public board off: no button', (tester, api) async {
      await pump(tester, api, stage: 'none');
      expect(find.byKey(const Key('event-results')), findsNothing);
      await pump(tester, api, stage: 'official', public: false);
      expect(find.byKey(const Key('event-results')), findsNothing);
    });

    test('the detail model reads the stage; absent means none', () {
      expect(
        EventDetail.fromJson({
          ...detail('e'),
          'results': {'stage': 'official'},
        }).hasPublishedResults,
        isTrue,
      );
      expect(EventDetail.fromJson(detail('e')).hasPublishedResults, isFalse);
      expect(EventDetail.fromJson(detail('e')).resultsStage, 'none');
    });
  });
}

typedef GoRouterMatch = ({String? name, Map<String, String> params});
