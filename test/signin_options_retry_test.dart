import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';

// A sign-in options request that failed on the network (a weak connection at
// launch) must not switch registration by code off for the rest of the
// session: the next call asks again.

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://localhost:0');

  bool offline = true;
  int asked = 0;

  @override
  Future<Map<String, dynamic>> signInOptions() async {
    asked++;
    if (offline) throw Exception('network down');
    return {'pinLogin': true, 'pinReset': true, 'smsCodes': true};
  }

  // The route probes fail the same way while offline.
  @override
  Future<bool> pinLoginAvailable() async => !offline;
  @override
  Future<bool> pinResetAvailable() async => !offline;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a failed request is not an answer; the next call asks again', () async {
    final api = _Api();
    final auth = AuthState(api);
    await auth.loadSignInOptions();
    expect(auth.signInOptionsKnown, isFalse);
    expect(auth.pinLoginEnabled, isFalse);

    api.offline = false;
    await auth.loadSignInOptions();
    expect(auth.signInOptionsKnown, isTrue);
    expect(auth.pinLoginEnabled, isTrue);
    expect(auth.smsCodesAvailable, isTrue);
  });

  test(
    'once answered it does not ask again, and a later failure keeps it',
    () async {
      final api = _Api()..offline = false;
      final auth = AuthState(api);
      await auth.loadSignInOptions();
      final asked = api.asked;
      await auth.loadSignInOptions();
      expect(api.asked, asked);

      api.offline = true;
      await auth.loadSignInOptions(force: true);
      expect(auth.pinLoginEnabled, isTrue);
    },
  );

  test('an older server (404) is an answer: the options stay off', () async {
    final auth = AuthState(_NotFoundApi());
    await auth.loadSignInOptions();
    expect(auth.signInOptionsKnown, isTrue);
    expect(auth.pinLoginEnabled, isFalse);
  });
}

class _NotFoundApi extends ApiClient {
  _NotFoundApi() : super(baseUrl: 'http://localhost:0');
  @override
  Future<Map<String, dynamic>> signInOptions() async =>
      throw ApiException(404, {'error': 'not_found'});
  @override
  Future<bool> pinLoginAvailable() async => false;
  @override
  Future<bool> pinResetAvailable() async => false;
}
