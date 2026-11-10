import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/pass_state.dart';
import 'package:fitflexmobile/screens/member/widgets/pass_summary_card.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

MemberData _data({
  Map<String, dynamic>? subscription,
  Map<String, dynamic>? pending,
  int used = 0,
  int? cap = 18,
}) {
  return MemberData()
    ..me = MemberMeResponse.fromJson({
      'user': {
        'id': 'm1',
        'displayName': 'Godliving',
        'onboardingCompleted': true,
      },
      'visitsUsed': used,
      'visitCap': cap,
      'subscription': ?subscription,
      'pendingPayment': ?pending,
    });
}

Map<String, dynamic> _direct({String status = 'active', int daysLeft = 20}) => {
  'id': 's2',
  'type': 'direct_sub',
  'plan': 'monthly',
  'status': status,
  'homeGymId': 'g1',
  'homeGym': {
    'id': 'g1',
    'name': 'Mikocheni Fitness',
    'tier': 'standard',
    'location': 'Mikocheni',
    'perVisitRate': 5000,
    'commissionRate': 10,
    'status': 'active',
  },
  'startedAt': DateTime.now()
      .subtract(const Duration(days: 10))
      .toUtc()
      .toIso8601String(),
  'expiresAt': DateTime.now()
      .add(Duration(days: daysLeft, hours: 12))
      .toUtc()
      .toIso8601String(),
};

Map<String, dynamic> _pass({String status = 'active', int daysLeft = 30}) => {
  'id': 's1',
  'type': 'platform_pass',
  'tier': 'pro',
  'status': status,
  'expiresAt': DateTime.now()
      .add(Duration(days: daysLeft, hours: 12))
      .toUtc()
      .toIso8601String(),
};

Future<void> _pumpCard(
  WidgetTester tester,
  MemberData data, {
  Widget Function(MemberData)? body,
  ThemeData? theme,
  String lang = 'en',
}) async {
  await tester.pumpWidget(
    FFLocaleScope(
      notifier: FFLocale()..set(Locale(lang)),
      child: MaterialApp(
        theme: theme ?? buildTheme(),
        supportedLocales: const [Locale('en'), Locale('sw')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MemberDataScope(
          data: data,
          child: Scaffold(
            body: body?.call(data) ?? PassSummaryCard(data: data),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('passStateFor', () {
    test('no pass, nothing in flight', () {
      expect(passStateFor(_data()), PassState.none);
    });

    test('a payment waiting for confirmation', () {
      final d = _data(
        pending: {'id': 'p1', 'status': 'pending', 'tier': 'pro'},
      );
      expect(passStateFor(d), PassState.pending);
      expect(passStateFor(d).canShowQr, isFalse);
    });

    test('active with plenty left', () {
      final d = _data(subscription: _pass(), used: 7);
      expect(passStateFor(d), PassState.active);
      expect(passStateFor(d).tone, PassTone.success);
      expect(visitsLeft(d), 11);
    });

    test('three visits or fewer left is low, and the QR still works', () {
      final d = _data(subscription: _pass(), used: 15);
      expect(passStateFor(d), PassState.lowVisits);
      expect(passStateFor(d).canShowQr, isTrue);
      expect(passStateFor(d).tone, PassTone.warning);
    });

    test('ending within three days beats low visits', () {
      final d = _data(subscription: _pass(daysLeft: 2), used: 17);
      expect(passStateFor(d), PassState.endingSoon);
    });

    test('an uncapped pass has no visits left to count', () {
      final d = _data(subscription: _pass(), cap: null);
      expect(visitsLeft(d), isNull);
      expect(passStateFor(d), PassState.active);
    });

    test('an expired pass is ended and hides the QR', () {
      final d = _data(subscription: _pass(status: 'expired'));
      expect(passStateFor(d), PassState.ended);
      expect(passStateFor(d).canShowQr, isFalse);
    });
  });

  group('PassSummaryCard', () {
    testWidgets('active pass: ring shows visits left and Show my QR', (
      tester,
    ) async {
      await _pumpCard(tester, _data(subscription: _pass(), used: 7));
      expect(find.byKey(const Key('pass-visits-ring')), findsOneWidget);
      // "11 left" in the ring, "7 of 18 used" beside it: no number twice.
      expect(find.text('11'), findsOneWidget);
      // Not repeated as "11 left" / "11 visits" elsewhere. Matched on those
      // words, not on "11 ", which the end date can contain (e.g. 11 Dec).
      expect(find.textContaining(RegExp(r'\b11 (left|visit)')), findsNothing);
      expect(find.text('left'), findsOneWidget);
      expect(find.text('7 of 18 used'), findsOneWidget);
      expect(find.text('Show my QR'), findsOneWidget);
      expect(find.byKey(const Key('pass-upgrade-action')), findsOneWidget);
    });

    for (final lang in ['en', 'sw']) {
      testWidgets('[$lang] at 360 the card says each fact once (M5)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final handle = tester.ensureSemantics();
        await _pumpCard(
          tester,
          _data(subscription: _pass(), used: 7),
          lang: lang,
        );
        String tr(String k) => FFLocale.textOf(lang, k)!;
        final used = tr(
          'pass.state.usedOf',
        ).replaceAll('{used}', '7').replaceAll('{total}', '18');
        // The ring is "11 left" only; the used count is the line beside it.
        expect(
          tester.getSemantics(find.byKey(const Key('pass-visits-ring'))).label,
          '11 ${tr('pass.state.left')}',
        );
        // Across the whole card the used count is announced once.
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(used))),
          findsOneWidget,
        );
        handle.dispose();
      });
    }

    testWidgets('low visits says how many are left', (tester) async {
      await _pumpCard(tester, _data(subscription: _pass(), used: 15));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('left'), findsOneWidget);
      expect(find.text('15 of 18 used'), findsOneWidget);
      // Not said twice: the line beside the ring is what to do about it.
      expect(find.text('3 visits left'), findsNothing);
      expect(
        find.text('Plan your next pass before it runs out.'),
        findsOneWidget,
      );
      expect(find.text('Show my QR'), findsOneWidget);
    });

    testWidgets('a pass with nothing used reads as all visits left', (
      tester,
    ) async {
      await _pumpCard(tester, _data(subscription: _pass(), used: 0));
      expect(find.text('18'), findsOneWidget);
      expect(find.text('left'), findsOneWidget);
      expect(find.text('0 of 18 used'), findsOneWidget);
    });

    test('every pass-state line has its own Swahili', () {
      final keys = FFLocale.keysOf(
        'en',
      ).where((k) => k.startsWith('pass.state.'));
      expect(keys.length, greaterThanOrEqualTo(13));
      for (final k in keys) {
        expect(FFLocale.textOf('sw', k), isNotNull, reason: k);
        expect(
          FFLocale.textOf('sw', k),
          isNot(FFLocale.textOf('en', k)),
          reason: k,
        );
      }
    });

    testWidgets('ending soon says the date once, in the sentence', (
      tester,
    ) async {
      await _pumpCard(tester, _data(subscription: _pass(daysLeft: 2)));
      expect(find.textContaining('Your pass ends'), findsOneWidget);
      expect(find.textContaining('Ends '), findsNothing);
      expect(find.text('Show my QR'), findsOneWidget);
    });

    testWidgets('pending payment: no QR, no ring, a clear sentence', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _data(pending: {'id': 'p1', 'status': 'pending', 'tier': 'pro'}),
      );
      expect(find.byKey(const Key('pass-visits-ring')), findsNothing);
      expect(find.text('Show my QR'), findsNothing);
      expect(find.byKey(const Key('pass-state-message')), findsOneWidget);
      expect(find.text('View payment'), findsOneWidget);
      expect(find.byKey(const Key('pass-upgrade-action')), findsNothing);
    });

    testWidgets('no pass: says so once, one sentence, one button', (
      tester,
    ) async {
      await _pumpCard(tester, _data());
      expect(find.text('No pass yet'), findsOneWidget);
      expect(find.textContaining('Platform Pass'), findsNothing);
      expect(find.byType(FFBadge), findsNothing);
      expect(
        find.text('Pick a pass to open gyms across the network.'),
        findsOneWidget,
      );
      expect(find.text('Choose a pass'), findsOneWidget);
      expect(find.text('Subscribe'), findsNothing);
    });

    testWidgets('pending payment names the pass being paid for', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _data(pending: {'id': 'p1', 'status': 'pending', 'tier': 'pro'}),
      );
      expect(find.text('Pro'), findsOneWidget);
      // Said once, by the sentence (owner: say a fact once).
      expect(find.text('Payment pending admin approval'), findsNothing);
      expect(
        find.text(
          "We're confirming your payment. Your QR unlocks as soon as it's confirmed.",
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Platform Pass'), findsNothing);
    });

    testWidgets(
      'active pass + pending purchase: the pass keeps its own status and '
      'the purchase gets a separate amber line naming its tier',
      (tester) async {
        await _pumpCard(
          tester,
          _data(
            subscription: _pass(),
            used: 7,
            pending: {'id': 'p2', 'status': 'pending', 'tier': 'premium'},
          ),
        );
        // The card is still the Pro pass, marked Active in green.
        expect(find.text('Pro'), findsOneWidget);
        final badges = tester
            .widgetList<FFBadge>(find.byType(FFBadge))
            .toList();
        final status = badges.firstWhere((b) => b.label == 'Active');
        expect(status.tone, FFBadgeTone.success);
        // The old merged badge is gone.
        expect(find.text('Payment pending admin approval'), findsNothing);
        // The purchase is its own amber line, naming what is being paid for.
        final aside = tester.widget<FFBadge>(
          find.byKey(const Key('pass-pending-purchase')),
        );
        expect(aside.label, 'Payment pending: Premium');
        expect(aside.tone, FFBadgeTone.warning);
        // The ring still counts visits left on the working pass, once.
        expect(find.byKey(const Key('pass-visits-ring')), findsOneWidget);
        expect(find.text('11'), findsOneWidget);
        expect(find.text('7 of 18 used'), findsOneWidget);
        expect(find.text('Show my QR'), findsOneWidget);
      },
    );

    testWidgets('pending purchase alone: no separate line, no badge '
        '(the sentence says it once)', (tester) async {
      await _pumpCard(
        tester,
        _data(pending: {'id': 'p1', 'status': 'pending', 'tier': 'pro'}),
      );
      expect(find.byKey(const Key('pass-pending-purchase')), findsNothing);
      expect(find.byType(FFBadge), findsNothing);
      expect(find.byKey(const Key('pass-state-message')), findsOneWidget);
    });

    testWidgets('ended pass + new purchase: titled by what is being paid', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _data(
          subscription: _pass(status: 'expired'),
          pending: {'id': 'p3', 'status': 'pending', 'tier': 'premium'},
        ),
      );
      expect(find.text('Premium'), findsOneWidget);
      expect(find.text('Pro'), findsNothing);
      expect(find.byKey(const Key('pass-state-message')), findsOneWidget);
      expect(find.byKey(const Key('pass-pending-purchase')), findsNothing);
      expect(find.text('View payment'), findsOneWidget);
    });

    testWidgets('ended pass offers Pay again, not the QR', (tester) async {
      await _pumpCard(tester, _data(subscription: _pass(status: 'expired')));
      expect(find.text('Pay again'), findsOneWidget);
      expect(find.text('Show my QR'), findsNothing);
    });
  });

  group('status badge when the pass is ending soon (owner 2026-10-19)', () {
    tearDown(() => debugPhotoHeroUiOverride = null);

    FFBadge badge(WidgetTester tester) =>
        tester.widget<FFBadge>(find.byKey(const Key('pass-status-badge')));

    for (final flag in [false, true]) {
      for (final (lang, ending, active) in [
        ('en', 'Ending soon', 'Active'),
        ('sw', 'Inaisha karibuni', 'Hai'),
      ]) {
        testWidgets('PHOTO_HERO_UI=$flag, $lang: reads "$ending", not '
            '"$active"', (tester) async {
          debugPhotoHeroUiOverride = flag;
          await _pumpCard(
            tester,
            _data(subscription: _pass(daysLeft: 2), used: 5, cap: 12),
            lang: lang,
          );
          expect(badge(tester).label, ending);
          expect(find.text(ending), findsOneWidget);
          expect(find.text(active), findsNothing);
          // Fuel under the flag; today's warning tone with it off.
          expect(
            badge(tester).tone,
            flag ? FFBadgeTone.fuel : FFBadgeTone.warning,
          );
          // The used line beside the ring stays (owner: keep).
          expect(
            find.text(lang == 'en' ? '5 of 12 used' : 'Umetumia 5 kati ya 12'),
            findsOneWidget,
          );
        });
      }
    }

    for (final flag in [false, true]) {
      testWidgets('PHOTO_HERO_UI=$flag: ending soon + pending purchase keeps '
          '"Ending soon" and the separate amber purchase line', (tester) async {
        debugPhotoHeroUiOverride = flag;
        await _pumpCard(
          tester,
          _data(
            subscription: _pass(daysLeft: 2),
            used: 5,
            cap: 12,
            pending: {'id': 'p4', 'status': 'pending', 'tier': 'premium'},
          ),
        );
        expect(find.text('Pro'), findsOneWidget);
        expect(badge(tester).label, 'Ending soon');
        expect(
          badge(tester).tone,
          flag ? FFBadgeTone.fuel : FFBadgeTone.warning,
        );
        final aside = tester.widget<FFBadge>(
          find.byKey(const Key('pass-pending-purchase')),
        );
        expect(aside.label, 'Payment pending: Premium');
        expect(aside.tone, FFBadgeTone.warning);
        expect(find.text('5 of 12 used'), findsOneWidget);
      });
    }

    testWidgets('a gym membership ending soon reads "Ending soon" too', (
      tester,
    ) async {
      debugPhotoHeroUiOverride = false;
      await _pumpCard(tester, _data(subscription: _direct(daysLeft: 2)));
      expect(badge(tester).label, 'Ending soon');
    });

    testWidgets('an active pass still reads Active', (tester) async {
      debugPhotoHeroUiOverride = false;
      await _pumpCard(tester, _data(subscription: _pass(), used: 7));
      expect(badge(tester).label, 'Active');
    });

    testWidgets('low visits keeps its current badge wording', (tester) async {
      debugPhotoHeroUiOverride = false;
      await _pumpCard(tester, _data(subscription: _pass(), used: 15));
      expect(badge(tester).label, 'Active');
    });

    test('the badge key has Swahili of its own', () {
      expect(FFLocale.textOf('en', 'pass.badge.endingSoon'), 'Ending soon');
      expect(
        FFLocale.textOf('sw', 'pass.badge.endingSoon'),
        'Inaisha karibuni',
      );
    });
  });

  group('My QR reads the same state', () {
    Widget qr(MemberData _) => const MemberQrTab();

    testWidgets('low visits: the QR stays and an amber notice says why', (
      tester,
    ) async {
      final d = _data(subscription: _pass(), used: 16)..qrToken = 'tok';
      await _pumpCard(tester, d, body: qr);
      expect(find.byKey(const Key('qr-state-notice')), findsOneWidget);
      expect(find.text('2 visits left'), findsOneWidget);
    });

    testWidgets('dark theme: the QR is fixed dark ink on white, not Volt', (
      tester,
    ) async {
      final d = _data(subscription: _pass(), used: 2)..qrToken = 'tok';
      await _pumpCard(tester, d, body: qr, theme: buildDarkTheme());
      final qrView = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qrView.eyeStyle.color, FFTokens.qrInk);
      expect(qrView.dataModuleStyle.color, FFTokens.qrInk);
      expect(qrView.backgroundColor, FFTokens.qrBackground);
      expect(qrView.eyeStyle.color, isNot(FFTokens.volt));
    });

    testWidgets('an active pass shows no notice', (tester) async {
      final d = _data(subscription: _pass(), used: 2)..qrToken = 'tok';
      await _pumpCard(tester, d, body: qr);
      expect(find.byKey(const Key('qr-state-notice')), findsNothing);
    });

    testWidgets('an ended pass says when it ended and offers Pay again', (
      tester,
    ) async {
      final d = _data(subscription: _pass(status: 'expired'));
      await _pumpCard(tester, d, body: qr);
      expect(find.textContaining('Your pass ended'), findsOneWidget);
      expect(find.text('Pay again'), findsOneWidget);
    });
  });

  group('direct gym membership', () {
    test('runs on dates, so a visit cap never makes it low', () {
      final d = _data(subscription: _direct(), used: 11, cap: 12);
      expect(passStateFor(d), PassState.active);
    });

    test('ending within three days, and ended', () {
      expect(
        passStateFor(_data(subscription: _direct(daysLeft: 2))),
        PassState.endingSoon,
      );
      expect(
        passStateFor(_data(subscription: _direct(status: 'expired'))),
        PassState.ended,
      );
    });

    testWidgets('keeps its dates and shows no ring or visit counts', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        _data(subscription: _direct(), used: 11, cap: 12),
      );
      expect(find.text('Mikocheni Fitness'), findsOneWidget);
      expect(find.byKey(const Key('direct-membership-expiry')), findsOneWidget);
      expect(find.byKey(const Key('pass-visits-ring')), findsNothing);
      expect(find.textContaining('visits left'), findsNothing);
      expect(find.byKey(const Key('pass-state-message')), findsNothing);
      expect(find.text('Show my QR'), findsOneWidget);
    });

    testWidgets('ending soon adds the sentence under the dates', (
      tester,
    ) async {
      await _pumpCard(tester, _data(subscription: _direct(daysLeft: 2)));
      expect(
        find.byKey(const Key('direct-membership-days-left')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pass-state-message')), findsOneWidget);
      expect(find.textContaining('Your pass ends'), findsOneWidget);
    });

    testWidgets('ended offers Pay again', (tester) async {
      await _pumpCard(tester, _data(subscription: _direct(status: 'expired')));
      expect(find.text('Pay again'), findsOneWidget);
      expect(find.text('Show my QR'), findsNothing);
    });
  });
}
