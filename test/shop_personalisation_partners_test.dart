// Partner DOB slices 4 and 5: shop personalisation for Trainers and gym
// owners (server flag SHOP_PERSONALISATION_PARTNERS). In trainer and owner
// modes the Why sheet and the "Personalised shop" sheet follow what the
// server lists (`uses`, reason codes), word gender/age as the partner's own
// date of birth, point a partner with no date of birth to add one, and
// carry the slice 5 explanation (draft pending counsel).
//
// Contract: GET/PUT /shop/preferences?mode=trainer|owner (`available`,
// `uses` may hold profile_gender/profile_age), GET /shop/home reason codes,
// GET /me/personal-details (`ask`, `dateOfBirth`). Mocked at the HTTP level.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/partner_details.dart';
import 'package:fitflexmobile/shared/shop_home.dart';
import 'package:fitflexmobile/shared/widgets/partner_details_widgets.dart';
import 'package:fitflexmobile/shared/widgets/shop_browse_page.dart';
import 'package:fitflexmobile/shared/widgets/shop_home/shop_partner_dob_hint.dart';

import 'support/recording_api.dart';

Finder _key(String k) => find.byKey(Key(k));

const _products = {
  'p1': {
    'id': 'p1',
    'vendorId': 'v1',
    'name': 'Whey Protein',
    'category': 'equipment',
    'priceTzs': 10000,
    'stock': 10,
    'rating': 0,
    'reviewCount': 0,
    'soldCount': 0,
    'deliveryAvailable': true,
  },
};

Map<String, dynamic> _home({
  required String mode,
  List<String> codes = const ['popular_with_role', 'role_context'],
  Map<String, dynamic>? personalisation = const {
    'available': true,
    'enabled': true,
  },
}) => {
  'serverNow': '2026-11-10T08:00:00Z',
  'mode': mode,
  'personalised': true,
  'signalsUsed': <String>[],
  'personalisation': ?personalisation,
  'categories': <dynamic>[],
  'sections': [
    {
      'key': 'recommended',
      'title': {'en': 'Recommended for you', 'sw': 'Kwako'},
      'reasonCodes': codes,
      'viewAll': {'query': <String, String>{}},
      'productIds': ['p1'],
    },
  ],
  'products': _products,
};

const _noDob = {
  'dateOfBirth': null,
  'gender': null,
  'ask': true,
  'required': true,
};

void _seed(
  RecordingApi api,
  Map<String, dynamic> home, {
  List<String>? uses,
  Map<String, dynamic>? details,
  // functions#346: true only in trainer/owner mode with both server flags
  // on; null leaves the key out (an older server, or a flag off).
  bool? profileSignals = true,
}) {
  api.on('GET /shop/products', _products.values.toList());
  api.on('GET /me/shop-orders', <dynamic>[]);
  api.on('GET /gyms', <dynamic>[]);
  api.on('GET /shop/home', home);
  if (uses != null) {
    api.on('GET /shop/preferences', {
      'personalised': true,
      'available': true,
      'historyDays': 365,
      'mode': home['mode'],
      'uses': uses,
      'profileSignals': ?profileSignals,
    });
  }
  if (details != null) api.on('GET /me/personal-details', details);
}

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api,
  ShopHomeMode mode, {
  String lang = 'en',
}) => pumpPage(
  tester,
  api,
  ShopBrowseBody(mode: mode),
  user: {
    'id': 'p-${mode.wire}',
    'userType': mode == ShopHomeMode.owner ? 'owner' : mode.wire,
    'displayName': 'Asha',
  },
  lang: lang,
  size: const Size(420, 1200),
  keepRequests: true,
);

Future<void> _openWhy(WidgetTester tester) async {
  await tapVisible(tester, _key('shop-home-why-recommended'));
  expect(_key('shop-why-recommended'), findsOneWidget);
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    debugShopHomeV2Override = true;
    ShopEvents.reset();
    PartnerDetailsSession.clear();
  });
  tearDown(() {
    debugShopHomeV2Override = null;
    PartnerDetailsSession.clear();
  });

  group('Why sheet, trainer and owner modes', () {
    apiTest('trainer: uses lists age, so the hint names age and gender', (
      tester,
      api,
    ) async {
      _seed(
        api,
        _home(mode: 'trainer'),
        uses: ['purchase_history', 'profile_age', 'specialty'],
        details: {'dateOfBirth': '1990-04-01', 'ask': false, 'required': true},
      );
      final host = await _pump(tester, api, ShopHomeMode.trainer);
      await _openWhy(tester);
      await tester.pumpAndSettle();
      expect(
        api.where('GET', '/shop/preferences').map((r) => r.query),
        contains('mode=trainer'),
      );
      // Age (no gender) and specialties are listed: exactly those.
      expect(
        find.text(host.tr('shop.why.switchHintPartnerAgeSpecialty')),
        findsOneWidget,
      );
      expect(find.text(host.tr('shop.why.switchHintPartner')), findsNothing);
      // A date of birth is known: no hint to add one.
      expect(_key('shop-partner-dob-hint'), findsNothing);
      // The partner link, not the member Privacy page link.
      expect(_key('shop-why-partner-privacy'), findsOneWidget);
      expect(_key('shop-why-privacy'), findsNothing);
    });

    apiTest('owner without a date of birth: purchases only, and the hint', (
      tester,
      api,
    ) async {
      _seed(
        api,
        _home(mode: 'owner'),
        uses: ['purchase_history'],
        details: _noDob,
      );
      final host = await _pump(tester, api, ShopHomeMode.owner);
      await _openWhy(tester);
      await tester.pumpAndSettle();
      expect(find.text(host.tr('shop.why.switchHintPartner')), findsOneWidget);
      expect(_key('shop-partner-dob-hint'), findsOneWidget);
      expect(find.text(host.tr('shop.partnerDob.hint')), findsOneWidget);
      // Add opens the slice 3 sheet, with the owner's gender choice.
      await tapVisible(tester, _key('shop-partner-dob-add'));
      expect(_key('partner-dob'), findsOneWidget);
      expect(_key('partner-gender'), findsOneWidget);
    });

    apiTest('saving a date of birth from the hint hides it and reloads', (
      tester,
      api,
    ) async {
      _seed(
        api,
        _home(mode: 'trainer'),
        uses: ['purchase_history'],
        details: _noDob,
      );
      api.on('PUT /me/personal-details', {
        'dateOfBirth': '1990-04-01',
        'gender': 'female',
        'genderFrom': 'trainer_profile',
        'ask': false,
        'required': true,
      });
      await _pump(tester, api, ShopHomeMode.trainer);
      await _openWhy(tester);
      await tester.pumpAndSettle();
      final homeLoads = api.where('GET', '/shop/home').length;
      await tapVisible(tester, _key('shop-partner-dob-add'));
      // A trainer's gender is the trainer profile's: no picker.
      expect(_key('partner-gender'), findsNothing);
      tester
              .widget<TextField>(
                find.descendant(
                  of: _key('partner-dob'),
                  matching: find.byType(TextField),
                ),
              )
              .controller!
              .text =
          '1990-04-01';
      await tapVisible(tester, _key('partner-details-save'));
      await tester.pumpAndSettle();
      expect(api.only('PUT', '/me/personal-details').body, {
        'dateOfBirth': '1990-04-01',
      });
      expect(_key('shop-partner-dob-hint'), findsNothing);
      expect(api.where('GET', '/shop/home').length, greaterThan(homeLoads));
    });

    apiTest('profileSignals absent: no hint, personal details not asked', (
      tester,
      api,
    ) async {
      _seed(
        api,
        _home(mode: 'owner'),
        uses: ['purchase_history'],
        details: _noDob,
        profileSignals: null,
      );
      final host = await _pump(tester, api, ShopHomeMode.owner);
      await _openWhy(tester);
      await tester.pumpAndSettle();
      expect(find.text(host.tr('shop.why.switchHintPartner')), findsOneWidget);
      expect(_key('shop-partner-dob-hint'), findsNothing);
      expect(api.sent('GET', '/me/personal-details'), isFalse);
      // The partner sheet has no hint either.
      await tapVisible(tester, _key('shop-why-partner-privacy'));
      expect(_key('privacy-shop-sheet'), findsOneWidget);
      expect(_key('shop-partner-dob-hint'), findsNothing);
      expect(api.sent('GET', '/me/personal-details'), isFalse);
    });

    apiTest('profileSignals false: no hint', (tester, api) async {
      _seed(
        api,
        _home(mode: 'trainer'),
        uses: ['purchase_history'],
        details: _noDob,
        profileSignals: false,
      );
      await _pump(tester, api, ShopHomeMode.trainer);
      await _openWhy(tester);
      await tester.pumpAndSettle();
      expect(_key('shop-partner-dob-hint'), findsNothing);
      expect(api.sent('GET', '/me/personal-details'), isFalse);
    });

    apiTest('an old server (no profileSignals, no mode, no uses): no hint, '
        'the purchases-only wording', (tester, api) async {
      _seed(api, _home(mode: 'owner'), details: _noDob);
      api.on('GET /shop/preferences', {
        'personalised': true,
        'available': true,
      });
      final host = await _pump(tester, api, ShopHomeMode.owner);
      await _openWhy(tester);
      await tester.pumpAndSettle();
      expect(find.text(host.tr('shop.why.switchHintPartner')), findsOneWidget);
      expect(_key('shop-partner-dob-hint'), findsNothing);
      expect(api.sent('GET', '/me/personal-details'), isFalse);
    });

    apiTest('the hint button wraps at large text in Swahili', (
      tester,
      api,
    ) async {
      _seed(
        api,
        _home(mode: 'owner'),
        uses: ['purchase_history'],
        details: _noDob,
      );
      await pumpPage(
        tester,
        api,
        const ShopBrowseBody(mode: ShopHomeMode.owner),
        user: const {'id': 'p-owner', 'userType': 'owner'},
        lang: 'sw',
        textScale: 2,
        size: const Size(375, 1600),
        keepRequests: true,
      );
      await _openWhy(tester);
      await tester.pumpAndSettle();
      final label = find.descendant(
        of: _key('shop-partner-dob-add'),
        matching: find.byType(Text),
      );
      expect(label, findsOneWidget);
      final text = tester.widget<Text>(label);
      expect(text.maxLines, greaterThan(1));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: label, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
    });

    apiTest('a known under-18 date of birth never gets the hint', (
      tester,
      api,
    ) async {
      _seed(
        api,
        _home(mode: 'owner'),
        uses: ['purchase_history'],
        // Even if a server said ask, a date under 18 is never prompted.
        details: {'dateOfBirth': '2012-01-01', 'ask': true, 'required': true},
      );
      await _pump(tester, api, ShopHomeMode.owner);
      await _openWhy(tester);
      await tester.pumpAndSettle();
      expect(_key('shop-partner-dob-hint'), findsNothing);
    });

    apiTest('not available (under 18 / flag off): no switch, no hint, '
        'no extra calls', (tester, api) async {
      _seed(
        api,
        _home(
          mode: 'owner',
          personalisation: {'available': false, 'enabled': false},
        ),
        details: _noDob,
      );
      await _pump(tester, api, ShopHomeMode.owner);
      await _openWhy(tester);
      await tester.pumpAndSettle();
      expect(_key('shop-why-personalised'), findsNothing);
      expect(_key('shop-partner-dob-hint'), findsNothing);
      expect(_key('shop-why-partner-privacy'), findsNothing);
      expect(api.sent('GET', '/shop/preferences'), isFalse);
      expect(api.sent('GET', '/me/personal-details'), isFalse);
    });

    apiTest('profile reason codes read as the partner\'s own details', (
      tester,
      api,
    ) async {
      _seed(
        api,
        _home(
          mode: 'trainer',
          codes: ['profile_gender', 'profile_age', 'role_context'],
        ),
        uses: ['purchase_history', 'profile_gender', 'profile_age'],
      );
      final host = await _pump(tester, api, ShopHomeMode.trainer);
      await _openWhy(tester);
      await tester.pumpAndSettle();
      expect(find.text(host.tr('shop.why.genderTrainer')), findsOneWidget);
      expect(find.text(host.tr('shop.why.agePartner')), findsOneWidget);
      expect(find.text(host.tr('shop.why.gender')), findsNothing);
      expect(find.text(host.tr('shop.why.age')), findsNothing);
    });

    apiTest('switching off keeps the age-and-gender hint', (tester, api) async {
      _seed(
        api,
        _home(mode: 'owner'),
        uses: ['purchase_history', 'profile_gender', 'profile_age'],
      );
      api.on('PUT /shop/preferences', {
        'personalised': false,
        'available': true,
        'mode': 'owner',
        'uses': <String>[],
      });
      final host = await _pump(tester, api, ShopHomeMode.owner);
      await _openWhy(tester);
      await tester.pumpAndSettle();
      await tester.tap(_key('shop-why-personalised'));
      await tester.pumpAndSettle();
      expect(
        find.text(host.tr('shop.why.switchHintPartnerGender')),
        findsOneWidget,
      );
    });

    apiTest('member mode is unchanged: no partner calls or texts', (
      tester,
      api,
    ) async {
      _seed(
        api,
        _home(mode: 'member', codes: ['profile_gender', 'role_context']),
        details: _noDob,
      );
      final host = await _pump(tester, api, ShopHomeMode.member);
      await _openWhy(tester);
      await tester.pumpAndSettle();
      expect(find.text(host.tr('shop.why.gender')), findsOneWidget);
      expect(find.text(host.tr('shop.why.switchHintMember')), findsOneWidget);
      expect(_key('shop-partner-dob-hint'), findsNothing);
      expect(_key('shop-why-partner-privacy'), findsNothing);
      expect(api.sent('GET', '/shop/preferences'), isFalse);
      expect(api.sent('GET', '/me/personal-details'), isFalse);
    });

    apiTest('the partner link opens the Personalised shop sheet with the '
        'explanation', (tester, api) async {
      _seed(
        api,
        _home(mode: 'owner'),
        uses: ['purchase_history', 'profile_gender', 'profile_age'],
      );
      final host = await _pump(tester, api, ShopHomeMode.owner, lang: 'sw');
      await _openWhy(tester);
      await tester.pumpAndSettle();
      await tapVisible(tester, _key('shop-why-partner-privacy'));
      expect(_key('privacy-shop-sheet'), findsOneWidget);
      expect(
        tester.widget<Text>(_key('privacy-shop-use-1')).data,
        host.tr('privacy.shop.usesGenderAgePartner'),
      );
      expect(_key('partner-shop-explainer'), findsOneWidget);
      expect(find.text(host.tr('shop.partnerAbout.title')), findsOneWidget);
      expect(find.text(host.tr('shop.partnerAbout.never')), findsOneWidget);
      // The member "never" line is replaced, and the draft note shown once.
      expect(find.text(host.tr('privacy.shop.never')), findsNothing);
      expect(find.text(host.tr('privacy.shop.draft')), findsOneWidget);
      expect(
        find.text(host.tr('shop.why.switchHintPartnerGender')),
        findsOneWidget,
      );
    });
  });

  group('date of birth field (slice 5)', () {
    apiTest('"How we use it" opens the explanation', (tester, api) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final host = await pumpPage(
        tester,
        api,
        Material(
          child: PartnerDobField(
            controller: controller,
            role: PartnerRole.trainer,
          ),
        ),
        user: const {'id': 't1', 'userType': 'trainer'},
      );
      expect(find.text(host.tr('partnerDob.help')), findsOneWidget);
      await tapVisible(tester, _key('partner-dob-why'));
      expect(_key('partner-shop-explainer'), findsOneWidget);
      expect(find.text(host.tr('shop.partnerAbout.title')), findsOneWidget);
      for (final k in PartnerShopExplainer.linesFor(PartnerRole.trainer)) {
        expect(find.text(host.tr(k)), findsOneWidget, reason: k);
      }
      // The trainer wording, not the owner's.
      expect(find.text(host.tr('shop.partnerAbout.askedOwner')), findsNothing);
      expect(_key('partner-shop-explainer-draft'), findsOneWidget);
    });

    apiTest('the owner explanation has the owner wording', (tester, api) async {
      final host = await pumpPage(
        tester,
        api,
        const Material(child: PartnerShopExplainer(role: PartnerRole.owner)),
      );
      for (final k in PartnerShopExplainer.linesFor(PartnerRole.owner)) {
        expect(find.text(host.tr(k)), findsOneWidget, reason: k);
      }
      expect(
        find.text(host.tr('shop.partnerAbout.askedTrainer')),
        findsNothing,
      );
      expect(find.text(host.tr('shop.partnerAbout.useTrainer')), findsNothing);
    });

    apiTest('without help (compact use) there is no link', (tester, api) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpPage(
        tester,
        api,
        Material(
          child: PartnerDobField(
            controller: controller,
            role: PartnerRole.owner,
            showHelp: false,
          ),
        ),
      );
      expect(_key('partner-dob-why'), findsNothing);
    });
  });

  group('helpers and texts', () {
    test('only trainer and owner are partner shop modes', () {
      expect(isPartnerShopMode('trainer'), isTrue);
      expect(isPartnerShopMode('owner'), isTrue);
      expect(isPartnerShopMode('member'), isFalse);
      expect(isPartnerShopMode('vendor_personal'), isFalse);
      expect(isPartnerShopMode(null), isFalse);
    });

    test('the hint applies only when asked and no date of birth is known', () {
      expect(partnerDobHintApplies(null), isFalse);
      expect(partnerDobHintApplies(PersonalDetails.fromJson(_noDob)), isTrue);
      expect(
        partnerDobHintApplies(
          PersonalDetails.fromJson({'dateOfBirth': null, 'ask': false}),
        ),
        isFalse,
      );
      expect(
        partnerDobHintApplies(
          PersonalDetails.fromJson({'dateOfBirth': '2012-01-01', 'ask': true}),
        ),
        isFalse,
      );
    });

    test('the switch hint follows uses', () {
      Set<ShopSignal> u(List<String> w) => {
        for (final x in w) ?ShopSignal.fromWire(x),
      };
      expect(partnerSwitchHintKey(null, area: false), isNull);
      expect(partnerSwitchHintKey(u(['purchase_history']), area: true), isNull);
      expect(
        partnerSwitchHintKey(u(['profile_gender', 'profile_age']), area: false),
        'shop.why.switchHintPartnerGender',
      );
      expect(
        partnerSwitchHintKey(u(['profile_age']), area: true),
        'shop.why.switchHintPartnerAgeArea',
      );
      expect(
        partnerSwitchHintKey(
          u(['profile_gender', 'profile_age', 'location', 'specialty']),
          area: true,
        ),
        'shop.why.switchHintPartnerGenderSpecialtyArea',
      );
    });

    test('profileSignals is parsed, absent = false', () {
      expect(
        ShopPreferences.fromJson({'available': true}).profileSignals,
        isFalse,
      );
      expect(
        ShopPreferences.fromJson({'profileSignals': true}).profileSignals,
        isTrue,
      );
      expect(
        ShopPreferences.fromJson({'profileSignals': 'true'}).profileSignals,
        isFalse,
      );
    });

    test('every new key has English and Swahili', () {
      final en = FFLocale()..set(const Locale('en'));
      final sw = FFLocale()..set(const Locale('sw'));
      for (final key in [
        for (final g in ['Gender', 'Age'])
          for (final sp in ['', 'Specialty'])
            for (final a in ['', 'Area']) 'shop.why.switchHintPartner$g$sp$a',
        'shop.why.genderTrainer',
        'shop.why.genderOwner',
        'shop.why.agePartner',
        'privacy.shop.usesGenderAgePartner',
        'privacy.shop.usesGenderPartner',
        'privacy.shop.usesAgePartner',
        'shop.partnerDob.hint',
        'shop.partnerAbout.title',
        ...PartnerShopExplainer.linesFor(PartnerRole.trainer),
        ...PartnerShopExplainer.linesFor(PartnerRole.owner),
        'partnerDob.whyLink',
        'partnerDob.help',
        'partnerDob.tileSubtitle',
      ]) {
        expect(en.t(key), isNot(key), reason: 'en $key');
        expect(sw.t(key), isNot(key), reason: 'sw $key');
        expect(sw.t(key), isNot(en.t(key)), reason: 'sw = en $key');
      }
      // Glossary: the switch name and "trainer" are reused, never variants.
      expect(
        sw.t('shop.partnerAbout.switchOff'),
        contains('Duka kwa ajili yako'),
      );
      expect(
        en.t('shop.partnerAbout.switchOff'),
        contains('“Personalised shop”'),
      );
      expect(
        sw.t('shop.partnerAbout.switchOff'),
        contains('“Duka kwa ajili yako”'),
      );
      for (final key in [
        ...PartnerShopExplainer.linesFor(PartnerRole.trainer),
        ...PartnerShopExplainer.linesFor(PartnerRole.owner),
      ]) {
        expect(sw.t(key), isNot(contains('mkufunzi')));
        expect(sw.t(key), isNot(contains('kocha')));
      }
      expect(
        sw.t('privacy.shop.usesGenderAgePartner'),
        contains('(havitumiki kwa walio chini ya miaka 18)'),
      );
    });
  });
}
