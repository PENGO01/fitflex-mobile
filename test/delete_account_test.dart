import 'dart:io';

import 'package:fitflexmobile/shared/firebase_auth_service.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/widgets/delete_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/recording_api.dart';

// Account deletion, Apple guideline 5.1.1(v). Contract: DELETE /me
// (fitflex-functions src/services/account-service.mjs).

const _member = {'id': 'u1', 'userType': 'member'};

class _FakeFirebase extends FirebaseAuthService {
  int signOuts = 0;

  @override
  Future<void> signOut() async => signOuts++;
}

Finder get _open => find.byKey(const Key('delete-account'));
Finder get _submit => find.byKey(const Key('delete-account-submit'));
Finder get _field => find.descendant(
  of: find.byKey(const Key('delete-account-confirm')),
  matching: find.byType(EditableText),
);

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(_open);
  await tester.pumpAndSettle();
}

Future<void> _confirmAndSubmit(
  WidgetTester tester, [
  String word = 'DELETE',
]) async {
  await tester.enterText(_field, word);
  await tester.pump();
  await tester.ensureVisible(_submit);
  await tester.pumpAndSettle();
  await tester.tap(_submit);
  await tester.pumpAndSettle();
}

void main() {
  group('confirmation', () {
    apiTest('nothing is sent until the word is typed', (tester, api) async {
      await pumpPage(tester, api, const DeleteAccountButton(), user: _member);
      await _openSheet(tester);

      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(find.textContaining('without your name'), findsOneWidget);
      expect(isEnabled(tester, _submit), isFalse);

      await tester.enterText(_field, 'delet');
      await tester.pump();
      expect(isEnabled(tester, _submit), isFalse);

      await tester.enterText(_field, ' delete ');
      await tester.pump();
      expect(isEnabled(tester, _submit), isTrue);
      expect(api.sent('DELETE', '/me'), isFalse);
    });

    apiTest('Swahili asks for the Swahili word', (tester, api) async {
      await pumpPage(
        tester,
        api,
        const DeleteAccountButton(),
        user: _member,
        lang: 'sw',
      );
      await _openSheet(tester);
      expect(find.text('Andika FUTA ili kuthibitisha'), findsOneWidget);

      await tester.enterText(_field, 'DELETE');
      await tester.pump();
      expect(isEnabled(tester, _submit), isFalse);

      await tester.enterText(_field, 'futa');
      await tester.pump();
      expect(isEnabled(tester, _submit), isTrue);
    });

    apiTest('Cancel closes it and keeps the account', (tester, api) async {
      await pumpPage(tester, api, const DeleteAccountButton(), user: _member);
      await _openSheet(tester);
      final cancel = find.byKey(const Key('delete-account-cancel'));
      await tester.ensureVisible(cancel);
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(_submit, findsNothing);
      expect(api.sent('DELETE', '/me'), isFalse);
    });
  });

  group('success', () {
    apiTest('signs out fully and goes to the start screen', (
      tester,
      api,
    ) async {
      api.on('DELETE /me', {'ok': true, 'message': 'Deleted.'});
      final firebase = _FakeFirebase();
      var deleted = 0;
      final host = await pumpPage(
        tester,
        api,
        DeleteAccountButton(firebaseAuth: firebase, onDeleted: () => deleted++),
        user: _member,
      );
      await _openSheet(tester);
      await _confirmAndSubmit(tester);

      api.only('DELETE', '/me');
      expect(host.auth.token, isNull);
      expect(host.auth.user, isNull);
      expect(firebase.signOuts, 1);
      expect(deleted, 1);
      expect(find.text('ROUTE-LANGUAGE'), findsOneWidget);
      expect(find.text('Your account has been deleted.'), findsOneWidget);
    });

    apiTest('an answer lost on the way counts as deleted', (tester, api) async {
      api.fail('DELETE /me', 404, {'error': 'user_not_found'});
      final host = await pumpPage(
        tester,
        api,
        DeleteAccountButton(firebaseAuth: _FakeFirebase()),
        user: _member,
      );
      await _openSheet(tester);
      await _confirmAndSubmit(tester);

      expect(host.auth.token, isNull);
      expect(find.text('ROUTE-LANGUAGE'), findsOneWidget);
    });
  });

  group('blocked by the backend', () {
    apiTest('shows the reason and a way to support; stays signed in', (
      tester,
      api,
    ) async {
      api.fail('DELETE /me', 409, {
        'error': 'trainer_has_bookings',
        'message': 'Your trainer profile has bookings.',
      });
      final firebase = _FakeFirebase();
      var support = 0;
      final host = await pumpPage(
        tester,
        api,
        DeleteAccountButton(
          firebaseAuth: firebase,
          openSupport: () async => support++,
        ),
        user: const {'id': 'u1', 'userType': 'trainer'},
      );
      await _openSheet(tester);
      await _confirmAndSubmit(tester);

      expect(
        find.textContaining('Your trainer profile has bookings'),
        findsOneWidget,
      );
      expect(_submit, findsNothing);
      expect(host.auth.token, 'token');
      expect(firebase.signOuts, 0);

      await tester.tap(find.byKey(const Key('delete-account-support')));
      await tester.pump();
      expect(support, 1);
    });

    apiTest('the gym reason is in the app language', (tester, api) async {
      api.fail('DELETE /me', 409, {
        'error': 'gym_owner_has_checkin_activity',
        'message': 'Your gym(s) have check-in activity.',
      });
      await pumpPage(
        tester,
        api,
        DeleteAccountButton(firebaseAuth: _FakeFirebase()),
        user: const {'id': 'u1', 'userType': 'gym_operator'},
        lang: 'sw',
      );
      await _openSheet(tester);
      await _confirmAndSubmit(tester, 'FUTA');

      expect(find.textContaining('Gym yako ina rekodi'), findsOneWidget);
    });

    apiTest('a paid order on its way blocks deletion, in Swahili too', (
      tester,
      api,
    ) async {
      api.fail('DELETE /me', 409, {'error': 'open_paid_order'});
      await pumpPage(
        tester,
        api,
        DeleteAccountButton(firebaseAuth: _FakeFirebase()),
        user: _member,
        lang: 'sw',
      );
      await _openSheet(tester);
      await _confirmAndSubmit(tester, 'FUTA');

      expect(find.textContaining('oda iliyolipiwa'), findsOneWidget);
      expect(find.byKey(const Key('delete-account-blocked')), findsOneWidget);
    });

    apiTest('organizer owners get the server\'s Swahili sentence', (
      tester,
      api,
    ) async {
      api.fail('DELETE /me', 409, {
        'error': 'organizer_owner',
        'message': 'Transfer or close your organizer account first.',
        'messageSw': 'Sentensi ya seva.',
      });
      await pumpPage(
        tester,
        api,
        DeleteAccountButton(firebaseAuth: _FakeFirebase()),
        user: _member,
        lang: 'sw',
      );
      await _openSheet(tester);
      await _confirmAndSubmit(tester, 'FUTA');

      expect(find.text('Sentensi ya seva.'), findsOneWidget);
      expect(find.byKey(const Key('delete-account-support')), findsOneWidget);
    });
  });

  group('failure', () {
    apiTest('offline: stays signed in, says so, and can try again', (
      tester,
      api,
    ) async {
      var offline = true;
      api.onCall('DELETE /me', (_) {
        if (offline) throw http.ClientException('offline');
        return {'ok': true};
      });
      final firebase = _FakeFirebase();
      final host = await pumpPage(
        tester,
        api,
        DeleteAccountButton(firebaseAuth: firebase),
        user: _member,
      );
      await _openSheet(tester);
      await _confirmAndSubmit(tester);

      expect(host.auth.token, 'token');
      expect(firebase.signOuts, 0);
      expect(find.byKey(const Key('delete-account-error')), findsOneWidget);
      final retry = buttonLabelled('Try again');
      expect(isEnabled(tester, retry), isTrue);

      offline = false;
      await tapVisible(tester, retry);
      expect(host.auth.token, isNull);
      expect(find.text('ROUTE-LANGUAGE'), findsOneWidget);
    });

    apiTest('a server error keeps the session', (tester, api) async {
      api.fail('DELETE /me', 500);
      final host = await pumpPage(
        tester,
        api,
        DeleteAccountButton(firebaseAuth: _FakeFirebase()),
        user: _member,
      );
      await _openSheet(tester);
      await _confirmAndSubmit(tester);

      expect(host.auth.token, 'token');
      expect(find.byKey(const Key('delete-account-error')), findsOneWidget);
    });
  });

  apiTest('double tap sends one request', (tester, api) async {
    final held = api.hold('DELETE /me');
    await pumpPage(
      tester,
      api,
      DeleteAccountButton(firebaseAuth: _FakeFirebase()),
      user: _member,
    );
    await _openSheet(tester);
    await tester.enterText(_field, 'DELETE');
    await tester.pump();
    await tester.ensureVisible(_submit);
    await tester.pumpAndSettle();
    await tester.tap(_submit);
    await tester.pump();
    expect(isEnabled(tester, _submit), isFalse);
    expect(
      isEnabled(tester, find.byKey(const Key('delete-account-cancel'))),
      isFalse,
    );
    await tester.tap(_submit, warnIfMissed: false);
    await tester.pump();

    held.complete();
    await tester.pumpAndSettle();
    api.only('DELETE', '/me');
  });

  apiTest('another profile on the account is mentioned, not deleted', (
    tester,
    api,
  ) async {
    api.on('GET /me/personas', {
      'personas': [
        {'id': 'u1', 'userType': 'member'},
        {'id': 'u2', 'userType': 'vendor'},
      ],
    });
    final host = await pumpPage(
      tester,
      api,
      const DeleteAccountButton(),
      user: _member,
    );
    await host.auth.refreshPersonas();
    await _openSheet(tester);

    expect(
      find.byKey(const Key('delete-account-other-profiles')),
      findsOneWidget,
    );
  });

  group('who sees it', () {
    for (final role in ['member', 'trainer', 'gym_operator', 'vendor']) {
      apiTest('$role sees the action', (tester, api) async {
        await pumpPage(
          tester,
          api,
          const DeleteAccountButton(),
          user: {'id': 'u1', 'userType': role},
        );
        expect(_open, findsOneWidget);
      });
    }

    for (final role in ['gym_staff', 'vendor_staff']) {
      apiTest('$role does not', (tester, api) async {
        await pumpPage(
          tester,
          api,
          const DeleteAccountButton(),
          user: {'id': 'u1', 'userType': role},
        );
        expect(_open, findsNothing);
      });
    }

    test('every account area carries it', () {
      for (final path in [
        'lib/screens/member/member_profile_tab.dart',
        'lib/screens/owner/owner_profile_page.dart',
        'lib/screens/trainer/trainer_home_page.dart',
        'lib/screens/vendor/vendor_home_page.dart',
        // Partners still waiting for approval have no profile tab yet.
        'lib/screens/auth_screen.dart',
      ]) {
        expect(
          File(path).readAsStringSync(),
          contains('DeleteAccountButton('),
          reason: path,
        );
      }
    });
  });

  test('every string has English and Swahili', () {
    final en = FFLocale.keysOf('en');
    final sw = FFLocale.keysOf('sw');
    final keys = en.where(
      (k) =>
          k.startsWith('account.delete.') ||
          k == 'error.reason.gymOwnerHasCheckins' ||
          k == 'error.reason.trainerHasBookings',
    );
    expect(keys, hasLength(12));
    expect(sw, containsAll(keys));
  });
}
