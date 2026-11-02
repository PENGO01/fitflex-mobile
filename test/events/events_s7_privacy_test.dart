// Events S7 (spec §5.2): the one-sentence note on Settings > Privacy & data
// says the app counts events-screen use, only while the server does.
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_privacy_page.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/events/events_options.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(MemberData data, {String lang = 'en'}) {
  final api = ApiClient(baseUrl: 'http://fixtures.local');
  return AppScope(
    api: api,
    auth: AuthState(api),
    child: FFLocaleScope(
      notifier: FFLocale()..set(Locale(lang)),
      child: MaterialApp(
        theme: buildTheme(),
        supportedLocales: const [Locale('en'), Locale('sw')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: MemberDataScope(data: data, child: const MemberPrivacyPage()),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('analytics on: the sentence shows, in both languages', (
    tester,
  ) async {
    final data = MemberData()
      ..eventsOptions = EventsOptions.fromJson({
        'analytics': {'enabled': true},
      });
    await tester.pumpWidget(_app(data));
    expect(
      find.text(
        'We count how the events screens are used, without your name or account.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(_app(data, lang: 'sw'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Tunahesabu jinsi skrini za matukio zinavyotumika, bila jina lako wala akaunti yako.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('analytics off or an older server: no sentence', (tester) async {
    await tester.pumpWidget(_app(MemberData()));
    expect(find.byKey(const Key('privacy-events-analytics')), findsNothing);
  });
}
