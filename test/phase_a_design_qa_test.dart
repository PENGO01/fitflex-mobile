// Design-QA fixes on the journey-audit Phase A screens: layouts at a 360px
// phone in English and Swahili (H1–H3), Swahili time (M2), one screen-reader
// label for the visits ring (M5), and the related UAT items (D2, D3, D6, D7,
// H6, M6, M15).
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/gym_card.dart';
import 'package:fitflexmobile/screens/member/widgets/gym_visit_tile.dart';
import 'package:fitflexmobile/screens/member/widgets/pass_summary_card.dart';
import 'package:fitflexmobile/screens/owner/owner_qr_scanner_page.dart';
import 'package:fitflexmobile/screens/route_status_pages.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/formatters.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/manual_payment.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/payment_labels.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/partner_not_verified.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_api.dart';

const _langs = ['en', 'sw'];

/// A 360px-wide phone (the narrowest the design supports).
void _phone360(WidgetTester tester, {double height = 800}) {
  tester.view.physicalSize = Size(360, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(Widget child, {String lang = 'en', double textScale = 1}) =>
    FFLocaleScope(
      notifier: FFLocale()..set(Locale(lang)),
      child: MaterialApp(
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
        home: Scaffold(body: child),
      ),
    );

FFLocale _locale(String lang) => FFLocale()..set(Locale(lang));

RenderParagraph _paragraph(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)).first,
    );

/// How many lines a Text was laid out on.
int _lines(WidgetTester tester, Finder text) {
  final p = _paragraph(tester, text);
  final str = p.text.toPlainText();
  final boxes = p.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: str.length),
  );
  return boxes.map((b) => b.top.round()).toSet().length;
}

const _manual = ManualPayment(
  lipaNamba: '55512345',
  accountName: 'FitFlex DQA Test',
  network: 'M-Pesa',
);

MemberData _member({
  Map<String, dynamic>? subscription,
  Map<String, dynamic>? pending,
  int used = 0,
  int? cap = 18,
}) => MemberData()
  ..me = MemberMeResponse.fromJson({
    'user': {'id': 'm1', 'displayName': 'Dqa', 'onboardingCompleted': true},
    'visitsUsed': used,
    'visitCap': cap,
    'subscription': ?subscription,
    'pendingPayment': ?pending,
  });

Map<String, dynamic> _pass({int daysLeft = 30}) => {
  'id': 's1',
  'type': 'platform_pass',
  'tier': 'pro',
  'status': 'active',
  'expiresAt': DateTime.now()
      .add(Duration(days: daysLeft, hours: 12))
      .toUtc()
      .toIso8601String(),
};

void main() {
  group('H1 Lipa Namba steps at 360px', () {
    for (final lang in _langs) {
      testWidgets('the number stays on one line and is said once ($lang)', (
        tester,
      ) async {
        _phone360(tester);
        await tester.pumpWidget(
          _app(
            ListView(
              // The payment page's own padding plus the card's.
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: const [
                ManualPaymentSteps(manual: _manual, amountLabel: 'TSh 60,000'),
              ],
            ),
            lang: lang,
            textScale: 1.3,
          ),
        );
        expect(tester.takeException(), isNull);
        final number = find.byKey(const Key('manual-pay-number'));
        expect(_lines(tester, number), 1);
        // Said once: only the big number carries it, not the sentence too.
        expect(find.textContaining('55512345'), findsOneWidget);
        // Amount and network are held together ("M-Pesa" never "M- / Pesa").
        final sentence = _locale(lang)
            .t('manualPay.step1Network')
            .replaceAll('{amount}', 'TSh 60,000')
            .replaceAll('{name}', 'FitFlex DQA Test')
            .replaceAll('{network}', 'M⁠-⁠Pesa');
        expect(find.text(sentence), findsOneWidget);
        // Copy is a 48dp target.
        final copy = tester.getSize(find.byKey(const Key('manual-pay-copy')));
        expect(copy.width, greaterThanOrEqualTo(48));
        expect(copy.height, greaterThanOrEqualTo(48));
      });
    }

    testWidgets('a very long number shrinks rather than wrapping', (
      tester,
    ) async {
      _phone360(tester);
      await tester.pumpWidget(
        _app(
          const ManualPaymentSteps(
            manual: ManualPayment(
              lipaNamba: '255712345678901234',
              accountName: 'X',
            ),
            amountLabel: 'TSh 1',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(_lines(tester, find.byKey(const Key('manual-pay-number'))), 1);
    });

    test('phone examples never break between their groups', () {
      for (final lang in _langs) {
        final l = _locale(lang);
        expect(l.t('manualPay.phoneInvalid'), contains('0712 345 678'));
        expect(l.t('manualPay.phoneHint'), contains('0712 345 678'));
      }
      expect(keepTogether('M-Pesa'), 'M⁠-⁠Pesa');
      expect(keepTogether('TSh 60,000'), 'TSh 60,000');
    });

    for (final lang in _langs) {
      testWidgets('an upgrade says it applies to the current pass ($lang)', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            const SingleChildScrollView(
              child: ManualPaymentSteps(
                manual: _manual,
                amountLabel: 'TSh 40,000',
                upgrade: true,
              ),
            ),
            lang: lang,
          ),
        );
        final l = _locale(lang);
        expect(find.text(l.t('manualPay.step3Upgrade')), findsOneWidget);
        expect(find.text(l.t('manualPay.step3')), findsNothing);
        expect(l.t('manualPay.step3Upgrade'), isNot(l.t('manualPay.step3')));
      });
    }

    testWidgets('D3: a refused clipboard still shows the number', (
      tester,
    ) async {
      final saved = manualPayCopier;
      addTearDown(() => manualPayCopier = saved);
      manualPayCopier = (_) async => throw Exception('clipboard blocked');
      await tester.pumpWidget(
        _app(
          const SingleChildScrollView(
            child: ManualPaymentSteps(manual: _manual, amountLabel: 'TSh 1'),
          ),
          lang: 'sw',
        ),
      );
      await tester.tap(find.byKey(const Key('manual-pay-copy')));
      await tester.pump();
      expect(
        find.text(
          _locale(
            'sw',
          ).t('manualPay.copyFailed').replaceAll('{number}', '55512345'),
        ),
        findsOneWidget,
      );
      expect(find.text(_locale('sw').t('manualPay.copied')), findsNothing);
    });
  });

  group('H2 pass card header at 360px', () {
    for (final lang in _langs) {
      testWidgets('pending only: title whole, no duplicate badge ($lang)', (
        tester,
      ) async {
        _phone360(tester);
        await tester.pumpWidget(
          _app(
            MemberDataScope(
              data: _member(
                pending: {'id': 'p1', 'status': 'pending', 'tier': 'pro'},
              ),
              child: Builder(
                builder: (context) => ListView(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  children: [
                    PassSummaryCard(data: MemberDataScope.of(context)),
                  ],
                ),
              ),
            ),
            lang: lang,
            textScale: 1.3,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(_lines(tester, find.byKey(const Key('pass-title'))), 1);
        expect(
          _lines(tester, find.text(_locale(lang).t('member.yourPass'))),
          1,
        );
        // The sentence says it; no badge repeats it (M3).
        expect(find.byKey(const Key('pass-status-badge')), findsNothing);
        expect(find.byKey(const Key('pass-state-message')), findsOneWidget);
      });

      testWidgets('long badge wraps beside "Your pass", title whole ($lang)', (
        tester,
      ) async {
        _phone360(tester);
        await tester.pumpWidget(
          _app(
            MemberDataScope(
              data: _member(subscription: _pass(daysLeft: 2), used: 2),
              child: Builder(
                builder: (context) => ListView(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  children: [
                    PassSummaryCard(data: MemberDataScope.of(context)),
                  ],
                ),
              ),
            ),
            lang: lang,
            textScale: 1.3,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('pass-status-badge')), findsOneWidget);
        expect(_lines(tester, find.byKey(const Key('pass-title'))), 1);
        expect(
          _lines(tester, find.text(_locale(lang).t('member.yourPass'))),
          1,
        );
      });
    }
  });

  group('H3 gym grid card at 360px', () {
    for (final lang in _langs) {
      testWidgets('an unverified gym keeps its name ($lang)', (tester) async {
        final gym = Gym.fromJson({
          'id': 'g1',
          'name': 'Dev Owner Gym',
          'tier': 'standard',
          'location': 'Mikocheni, Dar es Salaam',
          'perVisitRate': 5000,
          'commissionRate': 10,
          'status': 'active',
          'verified': false,
        });
        _phone360(tester);
        // Two columns at 360: (360 - 2×16 - 12) / 2 = 158 wide. The row is
        // as tall as its card (SliverFFRowGrid), so only the width is set.
        await tester.pumpWidget(
          _app(
            Center(
              child: SizedBox(
                width: 158,
                child: IntrinsicHeight(child: GymGridCard(gym: gym)),
              ),
            ),
            lang: lang,
          ),
        );
        expect(tester.takeException(), isNull);
        // The name has the whole content width (158 - 2×12 padding) to
        // itself; "Not verified" is on the line below, not beside it. (The
        // test font is wider than the real one, so the width is what is
        // checked, not whether this name fits.)
        final nameFinder = find.byKey(const Key('gym-grid-name-g1'));
        expect(tester.getSize(nameFinder).width, greaterThanOrEqualTo(133));
        expect(
          tester.getTopLeft(find.byType(NotVerifiedLabel)).dy,
          greaterThan(tester.getBottomLeft(nameFinder).dy - 1),
        );
        // A short name is shown whole.
        expect(find.text('Dev Owner Gym'), findsOneWidget);
        expect(find.byType(NotVerifiedLabel), findsOneWidget);
      });
    }
  });

  group('M2 Swahili time of day', () {
    setUp(() => debugLocalOffsetOverride = const Duration(hours: 3));
    tearDown(() => debugLocalOffsetOverride = null);

    test('day and time use the 12-hour Swahili clock', () {
      final at = DateTime.utc(2026, 10, 19, 14, 30); // 17:30 EAT, a Monday
      expect(formatDayTime(at), 'Mon 19 Oct · 17:30');
      expect(formatDayTime(at, locale: 'sw'), 'Jumatatu 19 Okt · 5:30 jioni');
      expect(
        formatDayTime(at, locale: 'sw', withYear: true),
        'Jumatatu 19 Okt 2026 · 5:30 jioni',
      );
    });

    for (final lang in _langs) {
      testWidgets('a gym visit shows the time the member reads ($lang)', (
        tester,
      ) async {
        _phone360(tester);
        final at = DateTime.utc(2026, 10, 19, 14, 30);
        final visit = CheckIn(
          id: 'c1',
          memberId: 'm1',
          timestamp: at.toIso8601String(),
          gymTier: 'standard',
          gymId: 'g1',
          gym: Gym.fromJson({'id': 'g1', 'name': 'Iron House'}),
        );
        await tester.pumpWidget(
          _app(
            MemberDataScope(
              data: _member(),
              child: GymVisitTile(
                entry: RecentVisitEntry(visit, at, const []),
                now: DateTime.utc(2026, 10, 19, 18),
              ),
            ),
            lang: lang,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.text(
            lang == 'sw'
                ? 'Jumatatu 19 Okt · 5:30 jioni'
                : 'Mon 19 Oct · 17:30',
          ),
          findsOneWidget,
        );
        if (lang == 'sw') expect(find.textContaining('17:30'), findsNothing);
      });
    }
  });

  group('M5 visits ring', () {
    testWidgets('is read once, as one label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          MemberDataScope(
            data: _member(subscription: _pass(), used: 7),
            child: Builder(
              builder: (context) => SingleChildScrollView(
                child: PassSummaryCard(data: MemberDataScope.of(context)),
              ),
            ),
          ),
        ),
      );
      // DS v1.0 lime card: "11 of 18 visits left" is read once, on the
      // number (polish round 2: each fact once).
      expect(find.bySemanticsLabel('11 of 18 visits left'), findsOneWidget);
      final ring = tester.getSemantics(
        find.byKey(const Key('pass-visits-ring')),
      );
      expect(ring.label, '11 of 18 visits left');
      var children = 0;
      ring.visitChildren((_) {
        children++;
        return true;
      });
      expect(children, 0);
      handle.dispose();
    });
  });

  group('labels in both languages', () {
    testWidgets('D6 gym access and M6 payment words are translated', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
          lang: 'sw',
        ),
      );
      expect(passGymAccessLabel(ctx, 'midtier'), 'Gym za kawaida + kati');
      expect(passGymAccessLabel(ctx, 'new_level'), 'new_level');
      expect(shopPaymentStatusLabel(ctx, 'paid'), 'Imelipwa');
      expect(shopPaymentStatusLabel(ctx, 'pending'), 'Inasubiri malipo');
      expect(shopPaymentMethodLabel(ctx, 'bank'), 'Uhamisho wa benki');
      expect(shopPaymentMethodLabel(ctx, 'mpesa'), 'M-Pesa');
      expect(shopPaymentStatusLabel(ctx, null), '-');
    });

    test('every new line has its own Swahili', () {
      const keys = [
        'manualPay.step3Upgrade',
        'manualPay.submittedUpgrade',
        'manualPay.copyFailed',
        'manualPay.numberA11y',
        'member.chooseFirst',
        'member.passLastsDays',
        'member.planDurationOne',
        'member.qrCheckIn',
        'shop.orderRef',
        'shop.orderProgress',
        'payment.status.paid',
        'payment.status.failed',
        'payment.status.refund_pending',
        'payment.status.refunded',
        'payment.method.card',
        'payment.method.bank',
        'vendor.pickupGymUnknown',
        'ownerScan.camera.denied',
        'ownerScan.camera.unsupported',
        'ownerScan.camera.error',
        'ownerScan.openMembers',
        'startup.offline.title',
        'startup.offline.body',
        'startup.offline.stillOffline',
        'notFound.title',
        'notFound.body',
        'notFound.home',
      ];
      for (final k in keys) {
        final en = FFLocale.textOf('en', k);
        final sw = FFLocale.textOf('sw', k);
        expect(en, isNotNull, reason: 'en $k');
        expect(sw, isNotNull, reason: 'sw $k');
        expect(sw, isNot(en), reason: 'sw copied from en: $k');
      }
      // L3: one gym is open, not "the ones".
      expect(FFLocale.textOf('sw', 'member.openNow'), 'Iko wazi sasa');
      expect(
        FFLocale.textOf('en', 'member.planDuration'),
        isNot(contains('(s)')),
      );
    });
  });

  group('M15 camera error', () {
    for (final lang in _langs) {
      testWidgets('says why in the owner language, with a way out ($lang)', (
        tester,
      ) async {
        _phone360(tester);
        await tester.pumpWidget(
          _app(
            OwnerScanCameraError(
              code: MobileScannerErrorCode.genericError,
              onRetry: () {},
            ),
            lang: lang,
          ),
        );
        final l = _locale(lang);
        expect(find.text(l.t('ownerScan.camera.error')), findsOneWidget);
        expect(find.text('An unexpected error occurred.'), findsNothing);
        expect(find.byKey(const Key('owner-scan-retry')), findsOneWidget);
        expect(find.byKey(const Key('owner-scan-members')), findsOneWidget);
      });
    }

    test('permission and unsupported have their own message', () {
      expect(
        ownerScanCameraErrorKey(MobileScannerErrorCode.permissionDenied),
        'ownerScan.camera.denied',
      );
      expect(
        ownerScanCameraErrorKey(MobileScannerErrorCode.unsupported),
        'ownerScan.camera.unsupported',
      );
    });
  });

  group('D2 submitting offline', () {
    apiTest('the payment page says there is no connection', (
      tester,
      api,
    ) async {
      api.on('GET /payments/options', {
        'enabled': false,
        'manual': {
          'enabled': true,
          'lipaNamba': '5123456',
          'accountName': 'FitFlex',
          'referenceRequired': true,
        },
      });
      api.onCall(
        'POST /me/subscribe',
        (_) => throw http.ClientException('XMLHttpRequest error.'),
      );
      final data = MemberData()
        ..selectedTier = 'pro'
        ..passes = [PassTier(id: 'pro', price: 60000, visitCap: 30)];
      final host = await pumpPage(
        tester,
        api,
        MemberDataScope(data: data, child: const MemberPaymentPage()),
        user: const {'id': 'm1', 'userType': 'member'},
        lang: 'sw',
        size: const Size(400, 1600),
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('manual-pay-transaction-id')),
          matching: find.byType(EditableText),
        ),
        'QGH7XK2L9P',
      );
      await tapVisible(tester, find.byKey(const Key('payment-submit')));
      await tester.pumpAndSettle();
      expect(host.snack(host.tr('error.network')), findsOneWidget);
    });
  });

  group('H6 start-up with the backend unreachable', () {
    Future<AuthState> hydrateOffline(
      RecordingApi api,
      Map<String, Object> prefs,
    ) async {
      SharedPreferences.setMockInitialValues(prefs);
      api.onCall(
        'GET /me',
        (_) => throw http.ClientException('XMLHttpRequest error.'),
      );
      final auth = AuthState(ApiClient(baseUrl: 'http://fixtures.local'));
      await auth.hydrate();
      return auth;
    }

    apiTest('no kept profile: a connection page, never member setup', (
      tester,
      api,
    ) async {
      final auth = await hydrateOffline(api, {'token': 't', 'role': 'member'});
      expect(auth.isSignedIn, isTrue);
      expect(auth.profileUnconfirmed, isTrue);
      expect(routeForSignedInUser(auth), AppRoutes.startupOffline);
      expect(routeForSignedInUser(auth), isNot(AppRoutes.memberOnboarding));

      // Back online: Retry loads the profile and the member goes home.
      api.on('GET /me', {
        'user': {'id': 'm1', 'userType': 'member', 'onboardingCompleted': true},
      });
      expect(await auth.retryProfile(), isTrue);
      expect(auth.profileUnconfirmed, isFalse);
      expect(routeForSignedInUser(auth), AppRoutes.memberHome);
    });

    apiTest('a kept, set-up profile opens home as before', (tester, api) async {
      final auth = await hydrateOffline(api, {
        'token': 't',
        'role': 'member',
        'user': '{"id":"m1","userType":"member","onboardingCompleted":true}',
      });
      expect(auth.profileUnconfirmed, isTrue);
      expect(routeForSignedInUser(auth), AppRoutes.memberHome);
    });

    apiTest('a member who really has not set up still gets setup online', (
      tester,
      api,
    ) async {
      SharedPreferences.setMockInitialValues({'token': 't', 'role': 'member'});
      api.on('GET /me', {
        'user': {
          'id': 'm1',
          'userType': 'member',
          'onboardingCompleted': false,
        },
      });
      final auth = AuthState(ApiClient(baseUrl: 'http://fixtures.local'));
      await auth.hydrate();
      expect(auth.profileUnconfirmed, isFalse);
      expect(routeForSignedInUser(auth), AppRoutes.memberOnboarding);
    });

    apiTest('the router holds the member on the connection page', (
      tester,
      api,
    ) async {
      final auth = await hydrateOffline(api, {'token': 't', 'role': 'member'});
      await _pumpRouter(tester, auth, AppRoutes.memberOnboarding);
      expect(find.byType(StartupOfflinePage), findsOneWidget);
      expect(
        find.text(_locale('en').t('startup.offline.title')),
        findsOneWidget,
      );
    });
  });

  group('D7 unknown address', () {
    apiTest('/vendor/orders shows a translated page with a way home', (
      tester,
      api,
    ) async {
      final auth = AuthState(ApiClient(baseUrl: 'http://fixtures.local'));
      await auth.signIn('t', {
        'id': 'v1',
        'userType': 'vendor',
        'approvalStatus': 'approved',
      });
      await _pumpRouter(tester, auth, '/vendor/orders', lang: 'sw');
      expect(find.byType(NotFoundPage), findsOneWidget);
      expect(find.text(_locale('sw').t('notFound.title')), findsOneWidget);
      expect(find.textContaining('GoException'), findsNothing);
      expect(find.byKey(const Key('not-found-home')), findsOneWidget);
    });
  });
}

/// The app's real router, opened at [location].
Future<void> _pumpRouter(
  WidgetTester tester,
  AuthState auth,
  String location, {
  String lang = 'en',
}) async {
  _phone360(tester);
  final router = buildRouter(auth);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    AppScope(
      api: auth.api,
      auth: auth,
      child: ThemeScope(
        notifier: ThemeNotifier(),
        child: FFLocaleScope(
          notifier: FFLocale()..set(Locale(lang)),
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
      ),
    ),
  );
  router.go(location);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
