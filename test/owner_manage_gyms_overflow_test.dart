// The owner's Manage gyms cards must never overflow: rows grow with their
// content instead of a fixed card height, on narrow phones, in English and
// Swahili, at normal and large text.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/owner/owner_shell.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';

final _gyms = <Map<String, dynamic>>[
  {
    'id': 'g1',
    'name': 'Mbezi Beach Fitness & Wellness Centre',
    'location': 'Mbezi Beach, Kinondoni, Dar es Salaam',
    'tier': 'premium',
    'status': 'pending_verification',
    'isPayoutOwner': true,
  },
  {'id': 'g2', 'name': 'Sinza Strong', 'tier': 'standard'},
  {
    'id': 'g3',
    'name': 'Kariakoo Gym',
    'location': 'Kariakoo',
    'tier': 'basic',
    'status': 'active',
  },
];

Widget _app({required String lang, required double scale}) {
  final client = ApiClient(baseUrl: 'http://localhost:0');
  final owner = OwnerData()
    ..ownerGyms = _gyms
    ..activeGymId = 'g1';
  return AppScope(
    api: client,
    auth: AuthState(client),
    child: ThemeScope(
      notifier: ThemeNotifier(),
      child: FFLocaleScope(
        notifier: FFLocale()..set(Locale(lang)),
        child: OwnerDataScope(
          data: owner,
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
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: c!,
            ),
            home: const Scaffold(body: OwnerManageGymsPage()),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [360.0, 390.0, 412.0]) {
    for (final lang in ['en', 'sw']) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('Manage gyms cards fit at ${width.toInt()}px, $lang, '
            'text x$scale', (tester) async {
          tester.view.physicalSize = Size(width * 3, 2400 * 3);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(_app(lang: lang, scale: scale));
          await tester.pump();

          expect(tester.takeException(), isNull);
          for (final g in _gyms) {
            expect(
              find.byKey(Key('owner-gym-entrance-qr-${g['id']}')),
              findsOneWidget,
            );
          }
        });
      }
    }
  }
}
