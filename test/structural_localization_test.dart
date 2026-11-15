import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/auth_error_message.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/social.dart';
import 'package:fitflexmobile/shared/wire_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Gym tiers, pass access, shop order/payment statuses and the vendor's
// next-step button have their own helpers and tests on release-candidate
// (gym_filters, payment_labels, shop_checkout); these cover what mobile#62
// adds on top.
void main() {
  FFLocale en() => FFLocale();
  FFLocale sw() => FFLocale()..set(const Locale('sw'));

  // FFLocale.set saves the choice without waiting; with no mock the plugin
  // error surfaces later, in whichever test is running.
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(FFLocale.new);

  test('every key exists in both languages', () {
    final english = FFLocale.keysOf('en');
    final swahili = FFLocale.keysOf('sw');
    expect(english.difference(swahili), isEmpty, reason: 'missing in sw');
    expect(swahili.difference(english), isEmpty, reason: 'missing in en');
  });

  test('Swahili never uses the banned terms', () {
    final banned = RegExp(
      r'\b(jimu|kocha|ukocha|mkufunzi|wakufunzi|changamoto|firebase)\b',
      caseSensitive: false,
    );
    final locale = sw();
    for (final key in FFLocale.keysOf('sw').where(_isNew)) {
      expect(locale.t(key), isNot(matches(banned)), reason: key);
    }
  });

  Future<BuildContext> contextIn(WidgetTester tester, FFLocale locale) async {
    late BuildContext captured;
    await tester.pumpWidget(
      FFLocaleScope(
        notifier: locale,
        child: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('account and enquiry statuses get a label', (tester) async {
    var context = await contextIn(tester, en());
    expect(
      statusLabel(context, 'pending_verification'),
      'Pending verification',
    );
    expect(statusLabel(context, 'resolved'), 'Resolved');

    context = await contextIn(tester, sw());
    expect(statusLabel(context, 'draft'), 'Rasimu');
    expect(statusLabel(context, 'open'), 'Wazi');
    expect(statusLabel(context, 'resolved'), 'Imetatuliwa');
    expect(statusLabel(context, 'suspended'), 'Imesimamishwa');
    expect(statusLabel(context, 'canceled'), 'Imeghairiwa');
    // Unknown values are made readable, never shown as a raw code.
    expect(statusLabel(context, 'on_hold_review'), 'On hold review');
    expect(statusLabel(context, null, fallback: '-'), '-');
  });

  group('errors', () {
    test('an unknown server reason is not shown in English to Swahili', () {
      final unknown = ApiException(400, {'error': 'phone_already_used'});
      expect(
        apiErrorMessage(en(), unknown),
        'Request declined: Phone already used',
      );
      expect(
        apiErrorMessage(sw(), unknown),
        isNot(contains('Phone already used')),
      );
      expect(
        apiErrorMessage(sw(), ApiException(404, {'message': 'Gym not found'})),
        'Kitu ulichoomba hakikupatikana.',
      );
      // A known reason is still explained.
      expect(
        apiErrorMessage(sw(), ApiException(400, {'error': 'gym_closed'})),
        'Ombi limekataliwa: Gym hii imefungwa kwa sasa',
      );
    });

    test('sign-in errors never show the SDK message or a raw code', () {
      expect(
        authErrorMessage(en(), 'too-many-requests'),
        'Too many attempts. Wait a moment and try again.',
      );
      expect(
        authErrorMessage(sw(), 'no-current-user'),
        'Hujaingia. Ingia tena kisha ujaribu.',
      );
      expect(
        authErrorMessage(sw(), 'missing-google-id-token'),
        'Imeshindikana kuingia kwa Google. Jaribu tena.',
      );
      expect(
        authErrorMessage(sw(), 'internal-error'),
        'Imeshindikana. Jaribu tena.',
      );
    });
  });

  test('a person with no name gets a translated one', () {
    en();
    expect(const SocialPerson(id: 'p1').name, 'FitFlex member');
    sw();
    expect(const SocialPerson(id: 'p1').name, 'Mwanachama wa FitFlex');
    expect(const SocialPerson(id: 'p1', displayName: ' Asha ').name, 'Asha');
    expect(FFLocale.text('run.channelName'), 'Kurekodi mbio');
  });

  test('a member with no name on record has no known name', () {
    final noName = MemberSummary.fromJson(const {'id': 'u1'});
    expect(noName.knownName, isNull);
    // Unchanged for the owner-side screens that still read it.
    expect(noName.resolvedName, 'Member');
    final named = MemberSummary.fromJson(const {
      'id': 'u2',
      'displayName': 'Asha',
    });
    expect(named.knownName, 'Asha');
  });
}

bool _isNew(String key) =>
    key.startsWith('wire.') ||
    key.startsWith('kyc.country.') ||
    key.startsWith('auth.') ||
    key.startsWith('common.') ||
    key.startsWith('social.') ||
    key.startsWith('run.');
