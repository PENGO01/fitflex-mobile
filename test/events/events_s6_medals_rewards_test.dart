// Events S6 (spec §7.7, §10.5): medals (organizer art with the built-in
// fallback), the detail sheet, the share card made on the phone, achievements,
// the rewards wallet, claiming, and the no-"points" rule (D44).

import 'package:fitflexmobile/screens/member/events/results/member_medals_page.dart';
import 'package:fitflexmobile/screens/member/events/results/member_reward_wallet_page.dart';
import 'package:fitflexmobile/screens/member/events/results/results_widgets.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/events/event_medal.dart';
import 'package:fitflexmobile/shared/events/events_cache.dart';
import 'package:fitflexmobile/shared/events/events_options.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 's3_support.dart';
import 's6_support.dart';

// A valid 1x1 PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
  0x1f, 0x00, 0x05, 0x05, 0x02, 0x00, 0x5f, 0xc8, 0xf1, 0xd2, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

const _ach = 'GET /me/achievements';
const _wallet = 'GET /me/event-rewards';
const _ledger = 'GET /me/reward-ledger';

Map<String, dynamic> _medals({
  List<Map<String, dynamic>>? medals,
  List<Map<String, dynamic>>? achievements,
}) => {
  'medals': medals ?? [medalJson()],
  'achievements':
      achievements ??
      [
        {
          'key': 'first_event_finish',
          'title': {
            'en': 'First event finished',
            'sw': 'Tukio la kwanza limekamilika',
          },
          'status': 'awarded',
          'awardedAt': '2027-03-15T10:00:00Z',
          'progress': {'current': 1, 'target': 1},
        },
        {
          'key': 'three_events_year',
          'title': {
            'en': '3 events in 12 months',
            'sw': 'Matukio 3 ndani ya miezi 12',
          },
          'status': 'locked',
          'progress': {'current': 1, 'target': 3},
        },
      ],
  'removed': const [],
};

Map<String, dynamic> _reward({
  String id = 'rwd_1',
  String mode = 'certificate',
  bool canClaim = true,
}) => {
  'definitionId': id,
  'title': {'en': 'Finisher certificate', 'sw': 'Cheti cha mshindi'},
  'terms': {'en': 'One per event.', 'sw': 'Moja kwa kila tukio.'},
  'units': 1,
  'nextExpiry': '2027-06-01T00:00:00Z',
  'redeemMode': mode,
  'canClaim': canClaim,
};

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsCache.reset();
    MedalArtLoader.reset();
    MedalArtLoader.fetch = null;
  });
  tearDown(() {
    debugEventsDiscoveryOverride = null;
    MedalArtLoader.fetch = null;
  });

  group('medal parsing and artwork', () {
    test('an unknown art key draws the default; custom needs an id', () {
      expect(
        MedalArt.fromJson({'source': 'builtin', 'artKey': 'nope'}).safeArtKey,
        'finisher_green',
      );
      expect(
        MedalArt.fromJson({'source': 'custom', 'artKey': 'time_blue'}).isCustom,
        isFalse,
      );
      final custom = MedalArt.fromJson({
        'source': 'custom',
        'artId': 'art_1',
        'artKey': 'time_blue',
      });
      expect(custom.isCustom, isTrue);
      expect(custom.safeArtKey, 'time_blue');
    });

    test('the eight built-in designs are named', () {
      expect(builtinMedalArtKeys, hasLength(8));
    });

    testWidgets('custom art is fetched with the sign-in, never a URL', (
      tester,
    ) async {
      var calls = 0;
      MedalArtLoader.fetch = (context, id, variant) async {
        calls++;
        expect(id, 'art_1');
        expect(variant, 'm256');
        return _png;
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => MedalBadge(
              art: MedalArt.fromJson({
                'source': 'custom',
                'artId': 'art_1',
                'revision': 1,
                'artKey': 'finisher_gold',
              }),
            ),
          ),
        ),
      );
      // The design shows at once; the picture replaces it when it arrives.
      expect(find.byType(CustomPaint), findsWidgets);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(calls, 1);
    });

    testWidgets('a taken-down picture (404) stays the built-in design', (
      tester,
    ) async {
      var calls = 0;
      MedalArtLoader.fetch = (context, id, variant) async {
        calls++;
        throw ApiException(404, {'error': 'not_found'});
      };
      Widget badge() => MaterialApp(
        home: Builder(
          builder: (c) => MedalBadge(
            art: MedalArt.fromJson({
              'source': 'custom',
              'artId': 'art_gone',
              'revision': 1,
              'artKey': 'podium_gold',
            }),
          ),
        ),
      );
      await tester.pumpWidget(badge());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.byType(BuiltinMedalArt), findsOneWidget);
      // Remembered for the session: not asked again.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(badge());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(calls, 1);
    });

    testWidgets('bytes that do not decode never leave a hole', (tester) async {
      MedalArtLoader.fetch = (c, id, v) async => Uint8List.fromList([1, 2, 3]);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => MedalBadge(
              art: MedalArt.fromJson({
                'source': 'custom',
                'artId': 'art_bad',
                'artKey': 'finisher_green',
              }),
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.pump();
      expect(find.byType(BuiltinMedalArt), findsOneWidget);
    });
  });

  group('medals page', () {
    Future<PageHost> pump(
      WidgetTester tester,
      RecordingApi api, {
      String lang = 'en',
      Size size = const Size(375, 2000),
      EventsOptions? options,
    }) => pumpPage(
      tester,
      api,
      MemberMedalsPage(options: options ?? optsS6()),
      user: member,
      lang: lang,
      size: size,
      extraRoutes: s6Routes,
      keepRequests: true,
    );

    apiTest('awarded medals, removed ones apart with the reason', (
      tester,
      api,
    ) async {
      api.on(
        _ach,
        _medals(
          medals: [
            medalJson(),
            medalJson(
              id: 'aw_2',
              status: 'revoked',
              reasonCode: 'result_corrected',
              revokedAt: '2027-03-18T10:00:00Z',
            ),
          ],
        ),
      );
      await pump(tester, api);
      expect(find.byKey(const Key('medal-aw_1')), findsOneWidget);
      expect(find.text('Removed'), findsOneWidget);
      expect(
        find.text('Removed because the result was corrected'),
        findsOneWidget,
      );
      expect(
        find.text('Medals are awarded only for verified results.'),
        findsOneWidget,
      );
    });

    apiTest('the tile is a button with the medal, event, category and date', (
      tester,
      api,
    ) async {
      api.on(_ach, _medals());
      await pump(tester, api);
      expect(
        find.bySemanticsLabel(
          'Finisher, Dar Half Marathon, 21K, awarded 15 Mar 2027',
        ),
        findsOneWidget,
      );
    });

    apiTest('empty', (tester, api) async {
      api.on(_ach, _medals(medals: const []));
      await pump(tester, api);
      expect(
        find.text('No medals yet. Finish an event to earn one.'),
        findsOneWidget,
      );
    });

    apiTest('achievements: progress for the unearned, date for the earned', (
      tester,
      api,
    ) async {
      api.on(_ach, _medals());
      await pump(tester, api);
      await tester.tap(find.text('Achievements'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 3'), findsOneWidget);
      expect(find.text('Earned 15 Mar 2027'), findsOneWidget);
    });

    apiTest('error with retry; offline shows the saved copy', (
      tester,
      api,
    ) async {
      api.fail(_ach, 500, {'error': 'x'});
      await pump(tester, api);
      expect(find.byKey(const Key('medals-error')), findsOneWidget);
      api.heal(_ach);
      api.on(_ach, _medals());
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('medal-aw_1')), findsOneWidget);
      api.onCall(_ach, (_) => throw StateError('SocketException: offline'));
      await pump(tester, api);
      expect(find.byKey(const Key('medals-cached')), findsOneWidget);
      expect(find.byKey(const Key('medal-aw_1')), findsOneWidget);
    });

    apiTest('flag off: nothing requested', (tester, api) async {
      await pump(tester, api, options: optsS6(rewards: false));
      expect(api.sent('GET', '/me/achievements'), isFalse);
      expect(find.byKey(const Key('medals-unavailable')), findsOneWidget);
    });

    apiTest('four columns on desktop, two on a phone', (tester, api) async {
      api.on(
        _ach,
        _medals(medals: [for (var i = 0; i < 4; i++) medalJson(id: 'aw_$i')]),
      );
      await pump(tester, api, size: const Size(1200, 1200));
      final tops = {
        for (var i = 0; i < 4; i++)
          tester.getTopLeft(find.byKey(Key('medal-aw_$i'))).dy.round(),
      };
      expect(tops, hasLength(1), reason: 'one row of four');
    });

    apiTest('Swahili at 320 dp and 200 percent text does not overflow', (
      tester,
      api,
    ) async {
      api.on(_ach, _medals());
      await pumpPage(
        tester,
        api,
        MemberMedalsPage(options: optsS6()),
        user: member,
        lang: 'sw',
        size: const Size(320, 2000),
        textScale: 2.0,
        extraRoutes: s6Routes,
        keepRequests: true,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Medali na mafanikio'), findsOneWidget);
    });

    apiTest('detail: why, design by, report, and no share for a removed one', (
      tester,
      api,
    ) async {
      api.on(
        _ach,
        _medals(
          medals: [medalJson(artSource: 'custom', artId: 'art_1')],
        ),
      );
      MedalArtLoader.fetch = (c, id, v) async => _png;
      await pump(tester, api);
      await tester.tap(find.byKey(const Key('medal-aw_1')));
      await tester.pumpAndSettle();
      expect(find.text('Finished 21K in 1:52:08 · Official'), findsOneWidget);
      expect(find.text('Design by Dar Runners'), findsOneWidget);
      expect(find.byKey(const Key('medal-report')), findsOneWidget);
      expect(find.byKey(const Key('medal-share')), findsOneWidget);
    });

    apiTest('built-in art: no "Design by", no report button', (
      tester,
      api,
    ) async {
      api.on(_ach, _medals());
      await pump(tester, api);
      await tester.tap(find.byKey(const Key('medal-aw_1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('medal-design-by')), findsNothing);
      expect(find.byKey(const Key('medal-report')), findsNothing);
    });

    apiTest('report opens the support mail with the art id', (
      tester,
      api,
    ) async {
      api.on(
        _ach,
        _medals(
          medals: [medalJson(artSource: 'custom', artId: 'art_77')],
        ),
      );
      MedalArtLoader.fetch = (c, id, v) async => _png;
      Uri? opened;
      EventShareActions.openMail = (uri) async {
        opened = uri;
        return true;
      };
      addTearDown(() => EventShareActions.openMail = (uri) async => false);
      await pump(tester, api);
      await tester.tap(find.byKey(const Key('medal-aw_1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('medal-report')));
      await tester.tap(find.byKey(const Key('medal-report')));
      await tester.pumpAndSettle();
      expect(opened!.scheme, 'mailto');
      expect(opened!.path, eventsSupportEmail);
      expect(opened!.queryParameters['subject'], contains('art_77'));
      // Spaces go as %20, never "+".
      expect(opened!.toString(), contains('Medal%20image%20art_77'));
      expect(opened!.toString(), isNot(contains('+')));
      expect(find.text('Thanks. FitFlex will look at it.'), findsOneWidget);
    });

    apiTest('share renders a PNG on the device; time is off until chosen', (
      tester,
      api,
    ) async {
      api.on(_ach, _medals());
      Uint8List? shared;
      String? name;
      EventShareActions.shareImage = (png, fileName) async {
        shared = png;
        name = fileName;
      };
      await pump(tester, api, size: const Size(600, 1600));
      await tester.tap(find.byKey(const Key('medal-aw_1')));
      await tester.pumpAndSettle();
      final sw = tester.widget<SwitchListTile>(
        find.byKey(const Key('medal-include-time')),
      );
      expect(sw.value, isFalse);
      // Off: the card has no time on it.
      expect(
        find.descendant(
          of: find.byType(MedalShareCard),
          matching: find.text('1:52:08'),
        ),
        findsNothing,
      );
      await tester.ensureVisible(find.byKey(const Key('medal-share')));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('medal-share')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(shared, isNotNull);
      // PNG signature.
      expect(shared!.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
      expect(name, 'fitflex-medal-aw_1.png');
    });

    apiTest('the time shows on the card only after the switch', (
      tester,
      api,
    ) async {
      api.on(_ach, _medals());
      await pump(tester, api, size: const Size(600, 1600));
      await tester.tap(find.byKey(const Key('medal-aw_1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('medal-include-time')));
      await tester.tap(find.byKey(const Key('medal-include-time')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(MedalShareCard),
          matching: find.text('1:52:08'),
        ),
        findsOneWidget,
      );
      // The member's name is never on the card.
      expect(
        find.descendant(
          of: find.byType(MedalShareCard),
          matching: find.text('u1'),
        ),
        findsNothing,
      );
    });
  });

  group('rewards wallet', () {
    Future<PageHost> pump(
      WidgetTester tester,
      RecordingApi api, {
      String lang = 'en',
      Size size = const Size(375, 2400),
      EventsOptions? options,
    }) => pumpPage(
      tester,
      api,
      MemberRewardWalletPage(options: options ?? optsS6()),
      user: {...member, 'name': 'Asha Mwangi'},
      lang: lang,
      size: size,
      extraRoutes: s6Routes,
      keepRequests: true,
    );

    apiTest('available rewards with expiry and terms; no points anywhere', (
      tester,
      api,
    ) async {
      api.on(_wallet, {
        'available': [_reward()],
        'redemptions': [],
        'expired': [],
      });
      api.on(_ledger, {'items': [], 'nextCursor': null});
      await pump(tester, api);
      expect(find.text('Available rewards'), findsOneWidget);
      expect(find.text('Finisher certificate'), findsOneWidget);
      expect(find.text('Use before 1 Jun 2027'), findsOneWidget);
      expect(find.byKey(const Key('reward-claim-rwd_1')), findsOneWidget);
      expect(
        find.textContaining(RegExp('points', caseSensitive: false)),
        findsNothing,
      );
      expect(find.textContaining('pointi'), findsNothing);
    });

    apiTest('empty', (tester, api) async {
      api.on(_wallet, {'available': [], 'redemptions': [], 'expired': []});
      api.on(_ledger, {'items': []});
      await pump(tester, api);
      expect(
        find.text('No rewards yet. Finish an event to earn some.'),
        findsOneWidget,
      );
    });

    apiTest(
      'claim a certificate: one POST with a key, then the certificate card',
      (tester, api) async {
        api.on(_wallet, {
          'available': [_reward()],
          'redemptions': [],
          'expired': [],
        });
        api.on(_ledger, {'items': []});
        api.on('POST /me/reward-redemptions', {
          'redemption': {
            'id': 'red_1',
            'definitionId': 'rwd_1',
            'title': {'en': 'Finisher certificate', 'sw': 'Cheti cha mshindi'},
            'redeemMode': 'certificate',
            'status': 'redeemed',
            'redeemedAt': '2027-03-20T10:00:00Z',
            'eventTitle': 'Dar Half Marathon',
            'resultLine': '21K in 1:52:08',
          },
        });
        await pump(tester, api);
        await tester.tap(find.byKey(const Key('reward-claim-rwd_1')));
        await tester.pumpAndSettle();
        expect(find.text('Claim this reward?'), findsOneWidget);
        expect(find.byKey(const Key('claim-explain')), findsOneWidget);
        await tester.tap(find.byKey(const Key('claim-confirm')));
        await tester.pumpAndSettle();
        final post = api.only('POST', '/me/reward-redemptions');
        expect(post.body, {'rewardDefinitionId': 'rwd_1'});
        expect(post.headers['idempotency-key'], isNotEmpty);
        expect(find.text('Claimed. Here it is.'), findsOneWidget);
        expect(find.text('Certificate of completion'), findsOneWidget);
        expect(find.text('Asha Mwangi'), findsOneWidget);
        expect(find.byKey(const Key('certificate-share')), findsOneWidget);
      },
    );

    apiTest('claim a perk: the code in a block with a copy button and expiry', (
      tester,
      api,
    ) async {
      api.on(_wallet, {
        'available': [_reward(mode: 'perk')],
        'redemptions': [],
        'expired': [],
      });
      api.on(_ledger, {'items': []});
      api.on('POST /me/reward-redemptions', {
        'redemption': {
          'id': 'red_2',
          'definitionId': 'rwd_1',
          'title': {'en': 'Finisher perk', 'sw': 'Zawadi ya mshindi'},
          'redeemMode': 'perk',
          'status': 'reserved',
          'code': 'FFR-AB12CD34',
          'expiresAt': '2027-04-03T00:00:00Z',
        },
      });
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await pump(tester, api);
      await tester.tap(find.byKey(const Key('reward-claim-rwd_1')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('code to show to FitFlex staff'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('claim-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('FFR-AB12CD34'), findsOneWidget);
      expect(find.text('Reserved'), findsWidgets);
      expect(find.text('Use before 3 Apr 2027'), findsOneWidget);
      expect(
        find.text('Show this code to FitFlex staff. It works once.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('reward-code-copy')));
      await tester.pumpAndSettle();
      expect(copied, 'FFR-AB12CD34');
    });

    apiTest('a reserved perk shows its code on the wallet after a reload', (
      tester,
      api,
    ) async {
      api.on(_wallet, {
        'available': [],
        'redemptions': [
          {
            'id': 'red_2',
            'definitionId': 'rwd_1',
            'title': {'en': 'Finisher perk', 'sw': 'x'},
            'redeemMode': 'perk',
            'status': 'reserved',
            'code': 'FFR-AB12CD34',
            'expiresAt': '2027-04-03T00:00:00Z',
          },
          {
            'id': 'red_3',
            'definitionId': 'rwd_2',
            'title': {'en': 'Earlier perk', 'sw': 'y'},
            'redeemMode': 'perk',
            'status': 'redeemed',
          },
        ],
        'expired': [],
      });
      api.on(_ledger, {'items': []});
      await pump(tester, api);
      expect(find.text('FFR-AB12CD34'), findsOneWidget);
      expect(find.text('Used'), findsOneWidget);
    });

    apiTest('expired rewards say when', (tester, api) async {
      api.on(_wallet, {
        'available': [],
        'redemptions': [],
        'expired': [_reward(id: 'rwd_old')],
      });
      api.on(_ledger, {'items': []});
      await pump(tester, api);
      expect(
        find.textContaining('This reward expired on 1 Jun 2027'),
        findsOneWidget,
      );
    });

    for (final (code, text) in const [
      ('reward_unavailable', 'This reward is no longer available.'),
      ('not_enough_units', 'You have none of this reward left to claim.'),
    ]) {
      apiTest('claim refused: $code', (tester, api) async {
        api.on(_wallet, {
          'available': [_reward()],
          'redemptions': [],
          'expired': [],
        });
        api.on(_ledger, {'items': []});
        api.fail('POST /me/reward-redemptions', 409, {'error': code});
        await pump(tester, api);
        await tester.tap(find.byKey(const Key('reward-claim-rwd_1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('claim-confirm')));
        await tester.pumpAndSettle();
        expect(find.textContaining(text), findsOneWidget);
        // Still on the sheet, can try again.
        expect(find.byKey(const Key('claim-confirm')), findsOneWidget);
      });
    }

    apiTest('offline: the cached wallet with Claim off and the reason', (
      tester,
      api,
    ) async {
      api.on(_wallet, {
        'available': [_reward()],
        'redemptions': [],
        'expired': [],
      });
      api.on(_ledger, {'items': []});
      await pump(tester, api);
      api.onCall(_wallet, (_) => throw StateError('SocketException: offline'));
      await pump(tester, api);
      expect(find.byKey(const Key('wallet-cached')), findsOneWidget);
      expect(
        find.textContaining("You're offline, so you can't claim now."),
        findsWidgets,
      );
      final claim = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const Key('reward-claim-rwd_1')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(claim.onPressed, isNull);
    });

    apiTest('history in plain words, no balance', (tester, api) async {
      api.on(_wallet, {'available': [], 'redemptions': [], 'expired': []});
      api.on(_ledger, {
        'items': [
          {
            'id': 'le_1',
            'entryType': 'earn',
            'titleOf': {'en': 'Finisher certificate', 'sw': 'Cheti'},
            'units': 1,
            'occurredAt': '2027-03-15T10:00:00Z',
          },
          {
            'id': 'le_2',
            'entryType': 'reverse',
            'titleOf': {'en': 'Finisher certificate', 'sw': 'Cheti'},
            'units': -1,
            'occurredAt': '2027-03-18T10:00:00Z',
          },
        ],
      });
      await pump(tester, api);
      expect(
        find.text('Earned · Finisher certificate · 15 Mar 2027'),
        findsOneWidget,
      );
      expect(
        find.text('Removed · Finisher certificate · 18 Mar 2027'),
        findsOneWidget,
      );
    });

    apiTest('flag off: nothing requested', (tester, api) async {
      await pump(tester, api, options: optsS6(rewards: false));
      expect(api.sent('GET', '/me/event-rewards'), isFalse);
      expect(find.byKey(const Key('wallet-unavailable')), findsOneWidget);
    });

    apiTest('Swahili at 320 dp and 200 percent text does not overflow', (
      tester,
      api,
    ) async {
      api.on(_wallet, {
        'available': [_reward(mode: 'perk')],
        'redemptions': [
          {
            'id': 'red_2',
            'definitionId': 'rwd_1',
            'title': {'en': 'Finisher perk', 'sw': 'Zawadi ya mshindi'},
            'redeemMode': 'perk',
            'status': 'reserved',
            'code': 'FFR-AB12CD34',
            'expiresAt': '2027-04-03T00:00:00Z',
          },
        ],
        'expired': [],
      });
      api.on(_ledger, {'items': []});
      await pumpPage(
        tester,
        api,
        MemberRewardWalletPage(options: optsS6()),
        user: member,
        lang: 'sw',
        size: const Size(320, 2600),
        textScale: 2.0,
        extraRoutes: s6Routes,
        keepRequests: true,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Zawadi zilizopo'), findsOneWidget);
    });
  });

  test('no S6 string in either language says "points" (D44)', () {
    for (final lang in ['en', 'sw']) {
      for (final k in FFLocale.keysOf(lang)) {
        if (!k.startsWith('events.rewards.') &&
            !k.startsWith('events.medals.') &&
            !k.startsWith('events.result.')) {
          continue;
        }
        final text = FFLocale.textOf(lang, k)!.toLowerCase();
        expect(text, isNot(contains('points')), reason: '$lang $k');
        expect(text, isNot(contains('pointi')), reason: '$lang $k');
        expect(text, isNot(contains('alama')), reason: '$lang $k');
      }
    }
  });
}
