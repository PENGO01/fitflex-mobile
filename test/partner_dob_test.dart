// Partner date of birth (plan slice 3, fitflex-functions#253): the
// Trainer and gym-owner registration step, the home prompt card, the
// settings sheet and the error lines. With the server flag off
// (404 feature_disabled) nothing new shows.
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/owner/owner_registration_page.dart';
import 'package:fitflexmobile/screens/trainer/trainer_registration_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/date_of_birth.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/partner_details.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/partner_details_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _off = ApiException(404, {'error': 'feature_disabled'});

Map<String, dynamic> _details({
  String? dob,
  String? gender,
  String? source,
  bool ask = false,
  bool required = true,
  String? genderFrom,
}) => {
  'dateOfBirth': dob,
  'gender': gender,
  'source': source,
  'ask': ask,
  'required': required,
  'genderFrom': genderFrom,
};

class _FakeApi extends ApiClient {
  _FakeApi({this.details, this.detailsError})
    : super(baseUrl: 'http://localhost:0');

  Map<String, dynamic>? details;
  ApiException? detailsError;
  int detailsCalls = 0;

  final saved = <Map<String, dynamic>>[];
  ApiException? saveError;

  final registered = <Map<String, dynamic>>[];
  ApiException registerError = ApiException(500, {'error': 'stop_here'});

  @override
  Future<Map<String, dynamic>> personalDetails() async {
    detailsCalls++;
    if (detailsError != null) throw detailsError!;
    return Map<String, dynamic>.from(details!);
  }

  @override
  Future<Map<String, dynamic>> savePersonalDetails(
    Map<String, dynamic> changes,
  ) async {
    saved.add(changes);
    if (saveError != null) throw saveError!;
    final next = Map<String, dynamic>.from(details!);
    if (changes['dateOfBirth'] is String) {
      next['dateOfBirth'] = changes['dateOfBirth'];
      next['source'] = 'person';
      next['ask'] = false;
    }
    if (changes.containsKey('gender') &&
        next['genderFrom'] != 'trainer_profile') {
      next['gender'] = changes['gender'];
      next['genderFrom'] = changes['gender'] == null ? null : 'person';
    }
    return details = next;
  }

  @override
  Future<Map<String, dynamic>> myTerms({String? lang, String? role}) async => {
    'required': true,
    'accepted': true,
    'version': 'v1',
    'title': 'Partner Agreement',
    'sections': const [],
  };

  @override
  Future<List<dynamic>> listTrainers() async => const [];

  @override
  Future<Map<String, dynamic>> trainerRegister(
    Map<String, dynamic> data,
  ) async {
    registered.add(data);
    throw registerError;
  }

  @override
  Future<Map<String, dynamic>> gymOwnerRegister(
    Map<String, dynamic> data,
  ) async {
    registered.add(data);
    throw registerError;
  }
}

Future<FFLocale> _pump(
  WidgetTester tester,
  _FakeApi api,
  Widget child, {
  String lang = 'en',
  bool signedIn = true,
  bool page = false,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = AuthState(api);
  if (signedIn) {
    await auth.signIn('jwt', {
      'id': 'usr_partner',
      'userType': 'trainer',
      'approvalStatus': 'approved',
      'onboardingCompleted': true,
    });
  }
  final loc = FFLocale()..set(Locale(lang));
  await tester.pumpWidget(
    AppScope(
      api: api,
      auth: auth,
      child: ThemeScope(
        notifier: ThemeNotifier(),
        child: FFLocaleScope(
          notifier: loc,
          child: MaterialApp(
            theme: buildTheme(),
            supportedLocales: const [Locale('en'), Locale('sw')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: page
                ? child
                : Scaffold(
                    body: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [child],
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return loc;
}

String _years(int ago) {
  final today = eastAfricaToday();
  return formatDateOfBirth(DateTime(today.year - ago, 1, 1));
}

TextEditingController _dobController(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('partner-dob')),
        matching: find.byType(TextField),
      ),
    )
    .controller!;

const _under18 = 'You must be 18 or older to be a Trainer or gym owner.';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PartnerDetailsSession.clear();
  });

  group('age rule (matches the server ageOnDay)', () {
    test('18 on the 18th birthday, not the day before', () {
      final now = DateTime.utc(2026, 10, 22, 6);
      expect(ageOn(DateTime(2008, 10, 22), now: now), 18);
      expect(ageOn(DateTime(2008, 10, 23), now: now), 17);
      expect(isUnderPartnerAge('2008-10-22', now: now), isFalse);
      expect(isUnderPartnerAge('2008-10-23', now: now), isTrue);
      // Today is the East Africa day: 21:30 UTC on the 21st is the 22nd.
      expect(
        isUnderPartnerAge('2008-10-22', now: DateTime.utc(2026, 10, 21, 21)),
        isFalse,
      );
      expect(isUnderPartnerAge('not a date', now: now), isFalse);
      expect(isUnderPartnerAge(null, now: now), isFalse);
    });

    test('problem keys: required, invalid, future, under 18', () {
      final now = DateTime.utc(2026, 10, 22, 6);
      expect(partnerDobProblemKey('', now: now), 'onboarding.required');
      expect(partnerDobProblemKey('', required: false, now: now), isNull);
      expect(partnerDobProblemKey('1900-12-31', now: now), 'member.dobInvalid');
      expect(partnerDobProblemKey('2027-01-01', now: now), 'member.dobFuture');
      expect(
        partnerDobProblemKey('2010-01-01', now: now),
        'error.reason.partnerUnder18',
      );
      expect(partnerDobProblemKey('1990-05-10', now: now), isNull);
    });

    test('prefer not to say is sent as null', () {
      expect(partnerGenderToSend(partnerGenderPreferNot), isNull);
      expect(partnerGenderToSend('female'), 'female');
    });
  });

  group('error lines, English and Swahili', () {
    final cases = <ApiException, (String, String)>{
      ApiException(400, {'error': 'partner_under_18'}): (
        _under18,
        'Lazima uwe na miaka 18 au zaidi kuwa trainer au mmiliki wa gym.',
      ),
      ApiException(400, {'error': 'invalid_field', 'field': 'gender'}): (
        'Choose a gender from the list.',
        'Chagua jinsia kutoka kwenye orodha.',
      ),
      ApiException(400, {'error': 'invalid_field', 'field': 'dateOfBirth'}): (
        'Choose a real date of birth.',
        'Chagua tarehe sahihi ya kuzaliwa.',
      ),
      ApiException(503, {'error': 'personal_details_unavailable'}): (
        "Personal details can't be saved right now. Try again later.",
        'Imeshindikana kuhifadhi taarifa binafsi kwa sasa. Jaribu tena baadaye.',
      ),
      ApiException(429, {'error': 'rate_limited', 'retryAfterSeconds': 42}): (
        'Too many changes. Try again in 42 seconds.',
        'Mabadiliko mengi mno. Jaribu tena baada ya sekunde 42.',
      ),
    };

    test('partnerDetailsErrorMessage', () {
      for (final MapEntry(key: e, value: (en, sw)) in cases.entries) {
        expect(partnerDetailsErrorMessage(FFLocale(), e), en);
        expect(
          partnerDetailsErrorMessage(FFLocale()..set(const Locale('sw')), e),
          sw,
        );
      }
    });

    test('the generic mapping knows the new reasons too', () {
      final en = FFLocale();
      final sw = FFLocale()..set(const Locale('sw'));
      expect(
        apiErrorMessage(en, ApiException(400, {'error': 'partner_under_18'})),
        'Request declined: $_under18',
      );
      expect(
        apiErrorMessage(sw, ApiException(400, {'error': 'partner_under_18'})),
        'Ombi limekataliwa: Lazima uwe na miaka 18 au zaidi kuwa trainer au '
        'mmiliki wa gym.',
      );
      expect(
        apiErrorMessage(
          en,
          ApiException(400, {'error': 'invalid_field', 'field': 'gender'}),
        ),
        'Request declined: Choose a gender from the list.',
      );
      expect(
        apiErrorMessage(
          sw,
          ApiException(503, {'error': 'personal_details_unavailable'}),
        ),
        'Ombi limekataliwa: Imeshindikana kuhifadhi taarifa binafsi kwa '
        'sasa. Jaribu tena baadaye.',
      );
      expect(
        apiErrorMessage(
          en,
          ApiException(429, {'error': 'rate_limited', 'retryAfterSeconds': 7}),
        ),
        'Request declined: Too many requests. Try again in 7 seconds.',
      );
      // Without a wait it keeps the old line.
      expect(
        apiErrorMessage(en, ApiException(429, {'error': 'rate_limited'})),
        'Request declined: Too many requests. Wait a moment and try again.',
      );
    });

    test('every new key has English and Swahili', () {
      final en = FFLocale.keysOf('en');
      final sw = FFLocale.keysOf('sw');
      final mine = en.where(
        (k) =>
            k.startsWith('partnerDob.') ||
            k.startsWith('partnerGender.') ||
            k == 'error.reason.partnerUnder18' ||
            k == 'error.reason.personalDetailsUnavailable' ||
            k == 'error.reason.invalidGender' ||
            k == 'error.reason.rateLimitedSeconds',
      );
      expect(mine.length, 18); // + partnerDob.whyLink (slice 5)
      for (final k in mine) {
        expect(sw, contains(k), reason: k);
        expect(FFLocale.textOf('sw', k), isNot(FFLocale.textOf('en', k)));
      }
    });
  });

  group('Trainer registration', () {
    Future<void> toStep2AndSubmit(WidgetTester tester) async {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '20000');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
    }

    testWidgets('flag off: no date of birth, body unchanged', (tester) async {
      final api = _FakeApi(detailsError: _off);
      await _pump(tester, api, const TrainerRegistrationPage(), page: true);
      expect(api.detailsCalls, 1);
      expect(find.byKey(const Key('trainer-reg-dob')), findsNothing);
      await toStep2AndSubmit(tester);
      expect(api.registered, hasLength(1));
      expect(api.registered.single.containsKey('dateOfBirth'), isFalse);
    });

    testWidgets('a failed read (network) keeps the old form', (tester) async {
      final api = _FakeApi(detailsError: ApiException(500, null));
      await _pump(tester, api, const TrainerRegistrationPage(), page: true);
      expect(find.byKey(const Key('trainer-reg-dob')), findsNothing);
    });

    testWidgets('a member date of birth already known: not asked', (
      tester,
    ) async {
      final api = _FakeApi(
        details: _details(dob: '1990-05-10', source: 'member', ask: false),
      );
      await _pump(tester, api, const TrainerRegistrationPage(), page: true);
      expect(find.byKey(const Key('trainer-reg-dob')), findsNothing);
      await toStep2AndSubmit(tester);
      expect(api.registered.single.containsKey('dateOfBirth'), isFalse);
    });

    testWidgets('asked: required, under 18 blocked, then sent', (tester) async {
      final api = _FakeApi(details: _details(ask: true));
      await _pump(tester, api, const TrainerRegistrationPage(), page: true);
      expect(find.byKey(const Key('trainer-reg-dob')), findsOneWidget);
      expect(
        find.text(
          'Used to check you are 18 or over and to suggest shop products '
          'for your age group. Not shown on your profile.',
        ),
        findsOneWidget,
      );
      // Required.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('trainer-reg-dob')), findsOneWidget);
      expect(find.text('This field is required'), findsWidgets);
      // Under 18.
      _dobController(tester).text = _years(16);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text(_under18), findsOneWidget);
      expect(find.byKey(const Key('trainer-reg-dob')), findsOneWidget);
      // Picked from the calendar (48dp pick button).
      expect(
        tester.getSize(find.byKey(const Key('partner-dob-pick'))).height,
        greaterThanOrEqualTo(48),
      );
      // Cleared, the calendar opens 25 years back.
      _dobController(tester).text = '';
      await tester.tap(find.byKey(const Key('partner-dob-pick')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('15'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final today = eastAfricaToday();
      final picked = formatDateOfBirth(
        DateTime(today.year - 25, today.month, 15),
      );
      expect(_dobController(tester).text, picked);
      await toStep2AndSubmit(tester);
      expect(api.registered.single['dateOfBirth'], picked);
    });

    testWidgets('the server refusing under 18 says so plainly', (tester) async {
      final api = _FakeApi(details: _details(ask: true))
        ..registerError = ApiException(400, {'error': 'partner_under_18'});
      await _pump(tester, api, const TrainerRegistrationPage(), page: true);
      _dobController(tester).text = _years(30);
      await toStep2AndSubmit(tester);
      expect(find.text(_under18), findsWidgets);
      // Back on the step with the date of birth.
      expect(find.byKey(const Key('trainer-reg-dob')), findsOneWidget);
    });
  });

  group('Gym owner registration', () {
    testWidgets('flag off: no date of birth or gender', (tester) async {
      final api = _FakeApi(detailsError: _off);
      await _pump(tester, api, const OwnerRegistrationPage(), page: true);
      expect(find.byKey(const Key('owner-reg-dob')), findsNothing);
      expect(find.byKey(const Key('partner-gender')), findsNothing);
    });

    testWidgets('a member date of birth already known: not asked', (
      tester,
    ) async {
      final api = _FakeApi(
        details: _details(dob: '1990-05-10', source: 'member'),
      );
      await _pump(tester, api, const OwnerRegistrationPage(), page: true);
      expect(find.byKey(const Key('owner-reg-dob')), findsNothing);
    });

    testWidgets('asked: date of birth required and 18+, gender optional '
        'with Prefer not to say', (tester) async {
      final api = _FakeApi(details: _details(ask: true));
      await _pump(tester, api, const OwnerRegistrationPage(), page: true);
      expect(find.byKey(const Key('owner-reg-dob')), findsOneWidget);
      expect(find.byKey(const Key('partner-gender')), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'Asha Gym');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('owner-reg-dob')), findsOneWidget);
      _dobController(tester).text = _years(17);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text(_under18), findsOneWidget);
      await tester.tap(find.byKey(const Key('partner-gender')));
      await tester.pumpAndSettle();
      expect(find.text('Prefer not to say'), findsWidgets);
      await tester.tap(find.text('Prefer not to say').last);
      await tester.pumpAndSettle();
      _dobController(tester).text = _years(40);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      // On to the gyms step without leaving the gender unanswered blocking.
      expect(find.byKey(const Key('owner-reg-dob')), findsNothing);
    });
  });

  group('Gym owner registration submit', () {
    Future<void> fillAndSubmit(WidgetTester tester) async {
      await tester.enterText(find.byType(TextFormField).first, 'Asha Said');
      _dobController(tester).text = _years(40);
      await tester.tap(find.byKey(const Key('partner-gender')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prefer not to say').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      for (final (i, v) in const [
        (0, 'Asha Gym'),
        (1, 'Mikocheni'),
        (2, '5000'),
        (3, '20000'),
        (4, '60000'),
      ]) {
        await tester.enterText(fields.at(i), v);
      }
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
    }

    testWidgets('asked: dateOfBirth and gender null are sent', (tester) async {
      final api = _FakeApi(details: _details(ask: true));
      await _pump(tester, api, const OwnerRegistrationPage(), page: true);
      await fillAndSubmit(tester);
      final body = api.registered.single;
      expect(body['dateOfBirth'], _years(40));
      expect(body.containsKey('gender'), isTrue);
      expect(body['gender'], isNull);
    });

    testWidgets('a server gender refusal goes back to the first step', (
      tester,
    ) async {
      final api = _FakeApi(details: _details(ask: true))
        ..registerError = ApiException(400, {
          'error': 'invalid_field',
          'field': 'gender',
        });
      await _pump(tester, api, const OwnerRegistrationPage(), page: true);
      await fillAndSubmit(tester);
      expect(api.registered, hasLength(1));
      expect(find.byKey(const Key('owner-reg-dob')), findsOneWidget);
      final gender = tester.widget<InputDecorator>(
        find.descendant(
          of: find.byKey(const Key('partner-gender')),
          matching: find.byType(InputDecorator),
        ),
      );
      expect(gender.decoration.errorText, 'Choose a gender from the list.');
    });
  });

  group('one read per session', () {
    testWidgets('the card and the tile share one GET; a save from the tile '
        'hides the card without another GET', (tester) async {
      final api = _FakeApi(details: _details(ask: true));
      await _pump(
        tester,
        api,
        const Column(
          children: [
            PartnerDobPromptCard(canEditGender: true),
            PartnerDetailsTile(canEditGender: true),
          ],
        ),
      );
      expect(api.detailsCalls, 1);
      expect(find.byKey(const Key('partner-dob-prompt')), findsOneWidget);
      await tester.tap(find.byKey(const Key('partner-details-tile')));
      await tester.pumpAndSettle();
      _dobController(tester).text = '1985-01-01';
      await tester.tap(find.byKey(const Key('partner-details-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('partner-dob-prompt')), findsNothing);
      // Opened again later in the session: still the one read.
      await _pump(
        tester,
        api,
        PartnerDetailsTile(key: UniqueKey(), canEditGender: true),
      );
      expect(api.detailsCalls, 1);
      expect(PartnerDetailsSession.current.value?.dateOfBirth, '1985-01-01');
    });

    testWidgets('a failed read is not kept; the next screen asks again', (
      tester,
    ) async {
      final api = _FakeApi(detailsError: ApiException(500, null));
      await _pump(tester, api, const PartnerDetailsTile(canEditGender: true));
      expect(find.byKey(const Key('partner-details-tile')), findsNothing);
      api
        ..detailsError = null
        ..details = _details(dob: '1990-05-10');
      await _pump(
        tester,
        api,
        PartnerDetailsTile(key: UniqueKey(), canEditGender: true),
      );
      expect(api.detailsCalls, 2);
      expect(find.byKey(const Key('partner-details-tile')), findsOneWidget);
    });

    testWidgets('feature off is kept for the session', (tester) async {
      final api = _FakeApi(detailsError: _off);
      await _pump(tester, api, const PartnerDetailsTile(canEditGender: true));
      await _pump(
        tester,
        api,
        PartnerDobPromptCard(key: UniqueKey(), canEditGender: true),
      );
      expect(api.detailsCalls, 1);
    });

    test('sign-out forgets the prompt counts and the session copy', () async {
      SharedPreferences.setMockInitialValues({
        PartnerDobPromptStore.countKey('usr_partner'): 2,
        PartnerDobPromptStore.atKey('usr_partner'): 1,
        PartnerDobPromptStore.countKey('usr_other'): 1,
        'ff.locale': 'sw',
      });
      final api = _FakeApi(details: _details(ask: true));
      final auth = AuthState(api);
      await auth.signIn('jwt', {'id': 'usr_partner', 'userType': 'trainer'});
      await PartnerDetailsSession.load(api, 'usr_partner');
      expect(PartnerDetailsSession.current.value, isNotNull);
      await auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((k) => k.startsWith('ff.partnerDob.')),
        isEmpty,
      );
      expect(prefs.getString('ff.locale'), 'sw');
      expect(PartnerDetailsSession.current.value, isNull);
    });
  });

  group('home prompt card', () {
    testWidgets('flag off: nothing', (tester) async {
      final api = _FakeApi(detailsError: _off);
      await _pump(tester, api, const PartnerDobPromptCard(canEditGender: true));
      expect(find.byKey(const Key('partner-dob-prompt')), findsNothing);
    });

    testWidgets('not asked (date known): nothing', (tester) async {
      final api = _FakeApi(details: _details(dob: '1990-05-10'));
      await _pump(tester, api, const PartnerDobPromptCard(canEditGender: true));
      expect(find.byKey(const Key('partner-dob-prompt')), findsNothing);
    });

    testWidgets('signed out: no call at all', (tester) async {
      final api = _FakeApi(details: _details(ask: true));
      await _pump(
        tester,
        api,
        const PartnerDobPromptCard(canEditGender: true),
        signedIn: false,
      );
      expect(api.detailsCalls, 0);
      expect(find.byKey(const Key('partner-dob-prompt')), findsNothing);
    });

    testWidgets('shows in Swahili, Add saves and hides it', (tester) async {
      final api = _FakeApi(details: _details(ask: true));
      await _pump(
        tester,
        api,
        const PartnerDobPromptCard(canEditGender: true),
        lang: 'sw',
      );
      expect(find.text('Ongeza tarehe yako ya kuzaliwa'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('partner-dob-prompt-add'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester
            .getSize(find.byKey(const Key('partner-dob-prompt-dismiss')))
            .height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.byKey(const Key('partner-dob-prompt-add')));
      await tester.pumpAndSettle();
      _dobController(tester).text = '1988-03-02';
      await tester.tap(find.byKey(const Key('partner-details-save')));
      await tester.pumpAndSettle();
      expect(api.saved.single, {'dateOfBirth': '1988-03-02'});
      expect(find.byKey(const Key('partner-dob-prompt')), findsNothing);
    });

    testWidgets('Not now: hidden for 30 days, then back; stops after 3', (
      tester,
    ) async {
      var now = DateTime.utc(2026, 10, 22, 9);
      final api = _FakeApi(details: _details(ask: true));
      Future<void> open() => _pump(
        tester,
        api,
        PartnerDobPromptCard(
          key: UniqueKey(),
          canEditGender: false,
          now: () => now,
        ),
      );

      for (var round = 1; round <= 3; round++) {
        await open();
        expect(
          find.byKey(const Key('partner-dob-prompt')),
          findsOneWidget,
          reason: 'round $round',
        );
        await tester.tap(find.byKey(const Key('partner-dob-prompt-dismiss')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('partner-dob-prompt')), findsNothing);
        // 29 days later: still hidden.
        now = now.add(const Duration(days: 29));
        await open();
        expect(find.byKey(const Key('partner-dob-prompt')), findsNothing);
        now = now.add(const Duration(days: 1));
      }
      // 30 days after the third "Not now": not asked again.
      await open();
      expect(find.byKey(const Key('partner-dob-prompt')), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PartnerDobPromptStore.countKey('usr_partner')), 3);
    });
  });

  group('settings tile and sheet', () {
    testWidgets('flag off: no tile', (tester) async {
      final api = _FakeApi(detailsError: _off);
      await _pump(tester, api, const PartnerDetailsTile(canEditGender: true));
      expect(find.byKey(const Key('partner-details-tile')), findsNothing);
    });

    testWidgets('Trainer: gender read-only from the trainer profile; only '
        'the changed date is sent', (tester) async {
      final api = _FakeApi(
        details: _details(
          dob: '1990-05-10',
          source: 'person',
          gender: 'female',
          genderFrom: 'trainer_profile',
        ),
      );
      await _pump(tester, api, const PartnerDetailsTile(canEditGender: false));
      expect(find.text('Date of birth and gender'), findsOneWidget);
      expect(find.text('Used for the 18+ check and shop suggestions'), findsOneWidget);
      await tester.tap(find.byKey(const Key('partner-details-tile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('partner-gender')), findsNothing);
      expect(find.byKey(const Key('partner-gender-readonly')), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(
        find.text('This comes from your trainer profile. Change it there.'),
        findsOneWidget,
      );
      expect(_dobController(tester).text, '1990-05-10');
      _dobController(tester).text = '1991-06-11';
      await tester.tap(find.byKey(const Key('partner-details-save')));
      await tester.pumpAndSettle();
      expect(api.saved.single, {'dateOfBirth': '1991-06-11'});
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('owner: Prefer not to say sends gender null; date unchanged '
        'is left out', (tester) async {
      final api = _FakeApi(
        details: _details(
          dob: '1979-06-30',
          source: 'person',
          gender: 'male',
          genderFrom: 'person',
        ),
      );
      await _pump(tester, api, const PartnerDetailsTile(canEditGender: true));
      await tester.tap(find.byKey(const Key('partner-details-tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('partner-gender')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prefer not to say').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('partner-details-save')));
      await tester.pumpAndSettle();
      expect(api.saved, hasLength(1));
      expect(api.saved.single, {'gender': null});
      expect(api.saved.single.containsKey('gender'), isTrue);
    });

    testWidgets('owner who is also a Trainer: gender stays read-only', (
      tester,
    ) async {
      final api = _FakeApi(
        details: _details(
          dob: '1979-06-30',
          source: 'person',
          gender: 'male',
          genderFrom: 'trainer_profile',
        ),
      );
      await _pump(tester, api, const PartnerDetailsTile(canEditGender: true));
      await tester.tap(find.byKey(const Key('partner-details-tile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('partner-gender')), findsNothing);
      expect(find.byKey(const Key('partner-gender-readonly')), findsOneWidget);
    });

    testWidgets('server refusals show in the sheet (EN and SW)', (
      tester,
    ) async {
      final api = _FakeApi(details: _details(ask: true))
        ..saveError = ApiException(429, {
          'error': 'rate_limited',
          'retryAfterSeconds': 30,
        });
      await _pump(
        tester,
        api,
        const PartnerDetailsTile(canEditGender: true),
        lang: 'sw',
      );
      await tester.tap(find.byKey(const Key('partner-details-tile')));
      await tester.pumpAndSettle();
      _dobController(tester).text = '1985-01-01';
      await tester.tap(find.byKey(const Key('partner-details-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Mabadiliko mengi mno. Jaribu tena baada ya sekunde 30.'),
        findsOneWidget,
      );
      api.saveError = ApiException(400, {'error': 'partner_under_18'});
      await tester.tap(find.byKey(const Key('partner-details-save')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Lazima uwe na miaka 18 au zaidi kuwa trainer au mmiliki wa gym.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an under-18 date is stopped before it is sent', (
      tester,
    ) async {
      final api = _FakeApi(details: _details(ask: true));
      await _pump(tester, api, const PartnerDetailsTile(canEditGender: true));
      await tester.tap(find.byKey(const Key('partner-details-tile')));
      await tester.pumpAndSettle();
      _dobController(tester).text = _years(12);
      await tester.tap(find.byKey(const Key('partner-details-save')));
      await tester.pumpAndSettle();
      expect(find.text(_under18), findsOneWidget);
      expect(api.saved, isEmpty);
    });

    testWidgets('fits at 1.3x text in Swahili', (tester) async {
      final api = _FakeApi(details: _details(ask: true));
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = AuthState(api);
      await auth.signIn('jwt', {'id': 'usr_partner', 'userType': 'trainer'});
      await tester.pumpWidget(
        AppScope(
          api: api,
          auth: auth,
          child: FFLocaleScope(
            notifier: FFLocale()..set(const Locale('sw')),
            child: MaterialApp(
              theme: buildTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              supportedLocales: const [Locale('en'), Locale('sw')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(16),
                  children: const [
                    PartnerDobPromptCard(canEditGender: true),
                    PartnerDetailsTile(canEditGender: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('partner-dob-prompt')), findsOneWidget);
      await tester.tap(find.byKey(const Key('partner-details-tile')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
