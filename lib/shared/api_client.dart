import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'promotion.dart';
import 'rest_log.dart';
import 'shop_clock.dart';

class ApiException implements Exception {
  final int status;
  final dynamic body;
  ApiException(this.status, this.body);

  /// The backend's machine-readable reason, e.g. 'visits_exhausted'.
  String? get code {
    final b = body;
    if (b is Map) return (b['error'] ?? b['failure'])?.toString();
    return null;
  }

  // Readable fallback for places that still interpolate the exception;
  // screens should use errorMessage() for translated copy.
  @override
  String toString() {
    final c = code;
    if (c == null || c.isEmpty) return 'Request failed ($status)';
    final words = c.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    return words.isEmpty
        ? 'Request failed ($status)'
        : '${words[0].toUpperCase()}${words.substring(1)}';
  }
}

/// Production backend. Used whenever API_BASE is not provided.
const kLiveApiBase = 'https://fitflex-faas.bfast.smartstock.co.tz';

/// Sent on every request; see [ApiClient._request].
const kIdentityV2Client = 'identity-v2';

class ApiClient {
  ApiClient({String? baseUrl, RestLogger? logger})
    : baseUrl = baseUrl ?? _resolveBaseUrl(),
      _log = logger ?? RestLogger();

  /// The API base a default [ApiClient] uses (API_BASE dart-define, then
  /// `.env`, then the live server).
  static String defaultBaseUrl() => _resolveBaseUrl();

  static String _resolveBaseUrl() {
    // 1. Compile-time --dart-define wins (CI/CD, prod builds).
    const compileTime = String.fromEnvironment('API_BASE', defaultValue: '');
    if (compileTime.isNotEmpty) return compileTime;

    // 2. Runtime .env (loaded by main()).
    String? fromEnv;
    try {
      final v = dotenv.maybeGet('API_BASE');
      if (v != null && v.isNotEmpty) fromEnv = v;
    } catch (_) {
      // dotenv not initialised — ignore.
    }
    if (fromEnv != null) return fromEnv;

    // 3. Live server. Builds that set nothing always reach production; local
    //    development opts into its own backend with API_BASE in .env.
    return kLiveApiBase;
  }

  final String baseUrl;
  final RestLogger _log;
  String? _token;
  void Function()? onUnauthorized;

  /// Called when the server holds this session until a start PIN is replaced
  /// (gym staff whose owner chose their PIN, fitflex-functions#260): any
  /// route answers `403 { error: 'password_change_required' }`.
  void Function()? onPasswordChangeRequired;

  void setToken(String? token) => _token = token;

  final List<void Function(String method, String path)> _successListeners = [];

  /// Called after every request that got a 2xx answer (a sign the device is
  /// online). Vendor walk-in sales use it to sync queued sales (S3).
  void addSuccessListener(void Function(String method, String path) l) =>
      _successListeners.add(l);

  void removeSuccessListener(void Function(String method, String path) l) =>
      _successListeners.remove(l);

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? extraHeaders,
    void Function(Map<String, String> headers)? onHeaders,
  }) => _doRequest(
    method,
    path,
    body: body,
    extraHeaders: extraHeaders,
    onHeaders: onHeaders,
    attempt: 0,
  );

  Future<dynamic> _doRequest(
    String method,
    String path, {
    Object? body,
    Map<String, String>? extraHeaders,
    void Function(Map<String, String> headers)? onHeaders,
    required int attempt,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    // The session this request is sent with. An answer about an older one
    // (a request still in flight when the token was replaced, e.g. right
    // after a PIN change that ended earlier sessions) says nothing about the
    // current session.
    final sentToken = _token;
    final headers = <String, String>{
      ...?extraHeaders,
      'content-type': 'application/json',
      // Identity V2 (decision C3b): this build understands persons and
      // personas. The backend ignores it unless its V2 flags are on.
      'x-fitflex-client': kIdentityV2Client,
      if (_token != null) 'authorization': 'Bearer $_token',
    };
    late http.Response res;
    final encoded = body == null ? null : jsonEncode(body);
    _log.request(method, uri, headers, encoded);
    try {
      switch (method) {
        case 'GET':
          res = await http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 12));
          break;
        case 'POST':
          res = await http
              .post(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 12));
          break;
        case 'PUT':
          res = await http
              .put(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 12));
          break;
        case 'PATCH':
          res = await http
              .patch(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 12));
          break;
        case 'DELETE':
          res = await http
              .delete(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 12));
          break;
        default:
          throw ArgumentError('Unsupported method $method');
      }
    } catch (e) {
      _log.error(method, uri, e);
      if (attempt < 2 && _isRetryableError(e)) {
        final delayMs = attempt == 0 ? 400 : 1200;
        _log.retry(method, uri, attempt + 1, delayMs);
        await Future.delayed(Duration(milliseconds: delayMs));
        return _doRequest(
          method,
          path,
          body: body,
          extraHeaders: extraHeaders,
          onHeaders: onHeaders,
          attempt: attempt + 1,
        );
      }
      rethrow;
    }
    _log.response(method, uri, res.statusCode, res.body);
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    final decoded = res.body.isEmpty
        ? null
        : ok
        ? jsonDecode(res.body)
        // An error page that is not JSON (a server's "Cannot POST" for a
        // route it does not have, a proxy's 502 page) still becomes an
        // ApiException, with no body: its HTML never reaches the UI.
        : _decodeErrorBody(res.body);
    if (ok) {
      onHeaders?.call(res.headers);
      for (final l in List.of(_successListeners)) {
        try {
          l(method, path);
        } catch (_) {
          // A listener never breaks the request.
        }
      }
      return decoded;
    }
    // A 401 always means this bearer session can no longer be used.  Do not
    // rely on a particular backend error shape: gateways and proxies often
    // return their own 401 payloads.
    final currentSession = sentToken == _token;
    if (res.statusCode == 401 && onUnauthorized != null && currentSession) {
      onUnauthorized!();
    }
    final exception = ApiException(res.statusCode, decoded);
    if (res.statusCode == 403 &&
        exception.code == 'password_change_required' &&
        onPasswordChangeRequired != null &&
        currentSession) {
      onPasswordChangeRequired!();
    }
    throw exception;
  }

  /// The JSON error body, or null when it is not JSON (an HTML page or a
  /// stack trace is not shown to anyone; the status still is).
  static dynamic _decodeErrorBody(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static bool _isRetryableError(Object e) {
    if (e is http.ClientException) {
      final msg = e.message.toLowerCase();
      return msg.contains('connection abort') ||
          msg.contains('connection reset') ||
          msg.contains('broken pipe') ||
          msg.contains('errno = 103') ||
          msg.contains('errno = 104') ||
          msg.contains('errno = 7') ||
          msg.contains('failed host lookup') ||
          msg.contains('no address associated');
    }
    return false;
  }

  Future<Map<String, dynamic>> requestOtp(String phone, String userType) async {
    return await _request(
      'POST',
      '/auth/otp/request',
      body: {'phone': phone, 'userType': userType},
    );
  }

  Future<Map<String, dynamic>> verifyOtp(String phone, String code) async {
    return await _request(
      'POST',
      '/auth/otp/verify',
      body: {'phone': phone, 'code': code},
    );
  }

  Future<Map<String, dynamic>> firebaseSession(
    String idToken,
    String? requestedRole,
  ) async {
    return await _request(
      'POST',
      '/auth/firebase/session',
      body: {'idToken': idToken, 'requestedRole': ?requestedRole},
    );
  }

  /// Identity V2: the signed-in Person and their personas (User rows).
  /// Answers 404 while the backend's V2 flags are off.
  Future<Map<String, dynamic>> myPersonas() async {
    return await _request('GET', '/me/personas');
  }

  /// Identity V2: add a persona (member, trainer, gym_operator, vendor) to
  /// the signed-in Person. No new account is created.
  Future<Map<String, dynamic>> addPersona(String userType) async {
    return await _request('POST', '/me/personas', body: {'userType': userType});
  }

  // ── Identity V2 · invitations (404 while the backend flag is off) ─────────

  // ── Identity V2 · I7: a PIN kept by FitFlex ───────────────────────────────

  /// True when the backend answers at [path] (anything but "not found" or
  /// "not set up"). An empty request is refused before it does anything.
  Future<bool> _routeAvailable(String path) async {
    try {
      await _request('POST', path, body: const <String, dynamic>{});
      return true;
    } on ApiException catch (e) {
      return e.status != 404 && e.code != 'pin_not_configured';
    } catch (_) {
      return false;
    }
  }

  /// Which sign-in options the server offers (public). Throws on 404 from an
  /// older server; callers fall back to the route probes.
  Future<Map<String, dynamic>> signInOptions() async {
    return await _request('GET', '/auth/options');
  }

  /// Sign-in and registration with a number or email and a PIN are on.
  Future<bool> pinLoginAvailable() => _routeAvailable('/auth/pin/login');

  /// Forgot PIN is on.
  Future<bool> pinResetAvailable() => _routeAvailable('/auth/pin/reset/start');

  /// Sign in with one mobile number or email (`{phone: …}` or `{email: …}`)
  /// and the PIN. Returns a session, or `setupRequired` for an existing user
  /// whose PIN is still held by Firebase.
  Future<Map<String, dynamic>> pinLogin(
    Map<String, String> contact,
    String pin, {
    String? locale,
  }) async {
    return await _request(
      'POST',
      '/auth/pin/login',
      body: {...contact, 'pin': pin, 'locale': ?locale},
    );
  }

  Future<Map<String, dynamic>> pinSetup({
    required String setupToken,
    String? code,
    required String pin,
  }) async {
    return await _request(
      'POST',
      '/auth/pin/setup',
      body: {'setupToken': setupToken, 'code': ?code, 'pin': pin},
    );
  }

  Future<Map<String, dynamic>> registerStart(
    Map<String, String> contact,
    String? locale,
  ) async {
    return await _request(
      'POST',
      '/auth/register/start',
      body: {...contact, 'locale': ?locale},
    );
  }

  Future<Map<String, dynamic>> registerConfirm(
    Map<String, String> contact,
    String code,
  ) async {
    return await _request(
      'POST',
      '/auth/register/confirm',
      body: {...contact, 'code': code},
    );
  }

  Future<Map<String, dynamic>> registerComplete({
    required String registrationToken,
    required String role,
    required String pin,
  }) async {
    return await _request(
      'POST',
      '/auth/register/complete',
      body: {'registrationToken': registrationToken, 'role': role, 'pin': pin},
    );
  }

  Future<Map<String, dynamic>> pinResetStart(
    Map<String, String> contact,
    String? locale,
  ) async {
    return await _request(
      'POST',
      '/auth/pin/reset/start',
      body: {...contact, 'locale': ?locale},
    );
  }

  Future<Map<String, dynamic>> pinResetConfirm(
    Map<String, String> contact,
    String code,
  ) async {
    return await _request(
      'POST',
      '/auth/pin/reset/confirm',
      body: {...contact, 'code': code},
    );
  }

  Future<Map<String, dynamic>> pinResetComplete(
    String resetToken,
    String pin,
  ) async {
    return await _request(
      'POST',
      '/auth/pin/reset/complete',
      body: {'resetToken': resetToken, 'pin': pin},
    );
  }

  /// After signing in with an invitation's start PIN: the person's name and
  /// their own PIN. Answers the onboarding step (their invitations).
  Future<Map<String, dynamic>> inviteBegin({
    required String startToken,
    required String displayName,
    required String pin,
  }) async {
    return await _request(
      'POST',
      '/auth/invite/begin',
      body: {'startToken': startToken, 'displayName': displayName, 'pin': pin},
    );
  }

  /// A person with no profile yet accepts ([accept]) or declines an invitation.
  Future<Map<String, dynamic>> onboardingAnswer(
    String onboardingToken,
    String invitationId, {
    required bool accept,
  }) async {
    return await _request(
      'POST',
      '/auth/onboarding/${accept ? 'accept' : 'decline'}',
      body: {'onboardingToken': onboardingToken, 'invitationId': invitationId},
    );
  }

  /// A person with no profile yet chooses how to use FitFlex.
  Future<Map<String, dynamic>> onboardingRole(
    String onboardingToken,
    String role,
  ) async {
    return await _request(
      'POST',
      '/auth/onboarding/role',
      body: {'onboardingToken': onboardingToken, 'role': role},
    );
  }

  /// Change the PIN. The response is a new session: earlier ones are over.
  Future<Map<String, dynamic>> changePin(
    String currentPin,
    String newPin,
  ) async {
    return await _request(
      'POST',
      '/me/pin',
      body: {'currentPin': currentPin, 'newPin': newPin},
    );
  }

  /// Gym staff replace the start PIN their owner chose
  /// (fitflex-functions#260). The one route a held session may use. The
  /// answer is a new session `{ token, user, partnerVerified }`; every older
  /// token is over. 404 `feature_disabled` while the server flag is off.
  Future<Map<String, dynamic>> staffChangeStartPin(String newPin) async {
    return await _request('POST', '/auth/pin/change', body: {'newPin': newPin});
  }

  /// Identity V2 · I6a: this Person's verified mobile numbers and emails
  /// (`identifiers`) and profile values not verified yet (`unverified`).
  Future<Map<String, dynamic>> myIdentifiers() async {
    return await _request('GET', '/me/identifiers');
  }

  /// Send a FitFlex code to one mobile number (SMS) or email.
  Future<Map<String, dynamic>> requestIdentifierCode({
    String? phone,
    String? email,
    String? locale,
  }) async {
    return await _request(
      'POST',
      '/me/identifiers/verify/request',
      body: {'phone': ?phone, 'email': ?email, 'locale': ?locale},
    );
  }

  Future<Map<String, dynamic>> confirmIdentifierCode({
    String? phone,
    String? email,
    required String code,
  }) async {
    return await _request(
      'POST',
      '/me/identifiers/verify/confirm',
      body: {'phone': ?phone, 'email': ?email, 'code': code},
    );
  }

  /// Replace the mobile number or email the person signs in with: their PIN
  /// and the new value. A code goes to the new value.
  Future<Map<String, dynamic>> requestIdentifierChange({
    String? phone,
    String? email,
    required String pin,
    String? locale,
  }) async {
    return await _request(
      'POST',
      '/me/identifiers/change/request',
      body: {'phone': ?phone, 'email': ?email, 'pin': pin, 'locale': ?locale},
    );
  }

  Future<Map<String, dynamic>> confirmIdentifierChange({
    String? phone,
    String? email,
    required String code,
    String? locale,
  }) async {
    return await _request(
      'POST',
      '/me/identifiers/change/confirm',
      body: {'phone': ?phone, 'email': ?email, 'code': code, 'locale': ?locale},
    );
  }

  // ── Identity V2 · account recovery (member path) ───────────────────────────

  /// Step 1: [oldContact] is what the person signed in with before, [newContact]
  /// the number or email that gets a code. Each is `{phone: …}` or `{email: …}`.
  Future<Map<String, dynamic>> recoveryStart(
    Map<String, String> oldContact,
    Map<String, String> newContact,
    String? locale,
  ) async {
    return await _request(
      'POST',
      '/auth/recovery/start',
      body: {'old': oldContact, 'new': newContact, 'locale': ?locale},
    );
  }

  /// Step 2: the code and the name on the account. Returns `requestToken`.
  Future<Map<String, dynamic>> recoveryConfirm(
    Map<String, String> oldContact,
    Map<String, String> newContact,
    String code,
    String name,
    String? locale,
  ) async {
    return await _request(
      'POST',
      '/auth/recovery/confirm',
      body: {
        'old': oldContact,
        'new': newContact,
        'code': code,
        'name': name,
        'locale': ?locale,
      },
    );
  }

  Future<Map<String, dynamic>> recoveryEvidence(
    String requestToken,
    Map<String, String> answers,
  ) async {
    return await _request(
      'POST',
      '/auth/recovery/evidence',
      body: {'requestToken': requestToken, 'answers': answers},
    );
  }

  Future<Map<String, dynamic>> recoveryStatus(String requestToken) async {
    return await _request(
      'POST',
      '/auth/recovery/status',
      body: {'requestToken': requestToken},
    );
  }

  Future<Map<String, dynamic>> recoveryCancel(String requestToken) async {
    return await _request(
      'POST',
      '/auth/recovery/cancel',
      body: {'requestToken': requestToken},
    );
  }

  /// Is a recovery request open on the signed-in account?
  Future<Map<String, dynamic>> myRecovery() async {
    return await _request('GET', '/me/recovery');
  }

  /// The signed-in owner cancels an open recovery request.
  Future<Map<String, dynamic>> cancelMyRecovery() async {
    return await _request('POST', '/me/recovery/cancel', body: const {});
  }

  /// Open invitations addressed to the signed-in Person.
  Future<Map<String, dynamic>> myInvitations() async {
    return await _request('GET', '/me/invitations');
  }

  /// Open an invitation from its link. Fails with `identifier_not_verified`
  /// unless this Person has verified the phone or email it was sent to.
  Future<Map<String, dynamic>> openInvitation(String token) async {
    return await _request(
      'POST',
      '/me/invitations/open',
      body: {'token': token},
    );
  }

  Future<Map<String, dynamic>> acceptInvitation(String id) async {
    return await _request('POST', '/me/invitations/$id/accept');
  }

  Future<Map<String, dynamic>> declineInvitation(String id) async {
    return await _request('POST', '/me/invitations/$id/decline');
  }

  /// Does this exact phone or email belong to a FitFlex person? Answers only
  /// `{found, maskedName}`.
  // [orgType] is 'gym' (the default) or 'vendor'; [gymId] is then the vendor's id.
  Future<Map<String, dynamic>> gymLookupPerson(
    String gymId, {
    String? phone,
    String? email,
    String orgType = 'gym',
  }) async {
    return await _request(
      'POST',
      '/orgs/$orgType/$gymId/people/lookup',
      body: {'phone': ?phone, 'email': ?email},
    );
  }

  /// Invite a person to a gym as member, staff or trainer. No account or
  /// credentials are created; returns the link token once.
  Future<Map<String, dynamic>> gymCreateInvitation(
    String gymId,
    Map<String, dynamic> body, {
    String orgType = 'gym',
  }) async {
    return await _request(
      'POST',
      '/orgs/$orgType/$gymId/invitations',
      body: body,
    );
  }

  Future<Map<String, dynamic>> gymInvitations(
    String gymId, {
    bool needsResolution = false,
    String orgType = 'gym',
  }) async {
    return await _request(
      'GET',
      '/orgs/$orgType/$gymId/invitations${needsResolution ? '?needsResolution=1' : ''}',
    );
  }

  /// [action] is cancel, resend, reissue or refunded.
  Future<Map<String, dynamic>> gymInvitationAction(
    String gymId,
    String invitationId,
    String action, {
    Map<String, dynamic>? body,
    String orgType = 'gym',
  }) async {
    return await _request(
      'POST',
      '/orgs/$orgType/$gymId/invitations/$invitationId/$action',
      body: body,
    );
  }

  /// Identity V2: a session for another persona of the same Person.
  Future<Map<String, dynamic>> switchPersona(String personaId) async {
    return await _request(
      'POST',
      '/auth/switch-persona',
      body: {'personaId': personaId},
    );
  }

  /// DEV ONLY: mock login bypassing Firebase (blackbox testing). The backend
  /// endpoint is disabled in production. [role] = member | trainer | owner.
  Future<Map<String, dynamic>> devLogin(String role) async {
    return await _request('POST', '/auth/dev/login', body: {'role': role});
  }

  /// DEV ONLY: remove E2E-created test users by email pattern or list.
  Future<Map<String, dynamic>> devCleanup({
    String? emailPattern,
    List<String>? emails,
  }) async {
    return await _request(
      'POST',
      '/auth/dev/cleanup',
      body: {'emailPattern': ?emailPattern, 'emails': ?emails},
    );
  }

  Future<Map<String, dynamic>> me() async => await _request('GET', '/me');

  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> profile,
  ) async => await _request('POST', '/me/profile', body: profile);

  /// Partner date of birth (fitflex-functions#253): the date of birth and
  /// gender kept on the Person → { dateOfBirth, gender, source, ask,
  /// required, genderFrom }. 404 feature_disabled while the server flag
  /// PARTNER_DOB_REQUIRED is off.
  Future<Map<String, dynamic>> personalDetails() async =>
      Map<String, dynamic>.from(
        await _request('GET', '/me/personal-details') as Map,
      );

  /// Saves { dateOfBirth?, gender? }: a key left out keeps the stored value;
  /// dateOfBirth "" clears it; gender null clears it ("prefer not to say").
  /// Answers the same body as [personalDetails].
  Future<Map<String, dynamic>> savePersonalDetails(
    Map<String, dynamic> changes,
  ) async => Map<String, dynamic>.from(
    await _request('PUT', '/me/personal-details', body: changes) as Map,
  );

  Future<List<dynamic>> listPasses() async => await _request('GET', '/passes');

  Future<List<dynamic>> listSubscriptionTiers() async =>
      await _request('GET', '/subscription-tiers');

  Future<List<dynamic>> listGyms() async => await _request('GET', '/gyms');

  /// Ranked discovery with promotion: `/discover/gyms`, `/discover/trainers` or
  /// `/discover/products`. A promotion only ever moves a result that already
  /// matches the search and filters; the answer says which cards are promoted.
  Future<Map<String, dynamic>> discover(
    String kind,
    DiscoverQuery query,
  ) async {
    final path = '/discover/$kind${query.toQueryString()}';
    // Products may carry flash sales (Phase 2 S4): say this build shows them.
    final out = kind == 'products'
        ? await _shopGet(path)
        : await _request('GET', path);
    return Map<String, dynamic>.from(out as Map);
  }

  /// Promotion analytics: `POST /events` (open to anonymous callers). At most
  /// 50 events per request. Returns `{accepted, duplicates, rejected:[{index,
  /// error}]}`; throws [ApiException] on a non-2xx answer.
  Future<Map<String, dynamic>> postEvents(
    List<Map<String, dynamic>> events,
  ) async {
    final out = await _request(
      'POST',
      '/events',
      body: {'source': 'mobile', 'events': events},
    );
    return out is Map ? Map<String, dynamic>.from(out) : <String, dynamic>{};
  }

  /// The signed-in role's terms (member: FitFlex Terms; partner: partner
  /// agreement) and whether the current version is accepted. With [role] it
  /// returns the text for a role the user is about to add.
  Future<Map<String, dynamic>> myTerms({String? lang, String? role}) async =>
      await _request(
            'GET',
            _withQuery('/me/terms', {'lang': ?lang, 'role': ?role}),
          )
          as Map<String, dynamic>;

  /// Accept the current terms for the signed-in role.
  Future<Map<String, dynamic>> acceptTerms(String version) async =>
      await _request('POST', '/me/terms', body: {'version': version})
          as Map<String, dynamic>;

  Future<List<dynamic>> getSpecialties() async =>
      await _request('GET', '/settings/specialties');

  Future<List<dynamic>> listTrainers() async =>
      await _request('GET', '/trainers');

  /// The member's check-ins, newest first. Without a range the server sends
  /// the newest 50; with one, every check-in from [from] up to [to].
  Future<List<dynamic>> myCheckins({DateTime? from, DateTime? to}) async {
    if (from == null && to == null) {
      return await _request('GET', '/me/checkins');
    }
    final query = Uri(
      queryParameters: {
        'from': ?from?.toUtc().toIso8601String(),
        'to': ?to?.toUtc().toIso8601String(),
      },
    ).query;
    return await _request('GET', '/me/checkins?$query');
  }

  /// [reference] is the member's mobile-money transaction ID and
  /// [payerPhone] the number they paid from, sent only while manual Lipa
  /// Namba payment is on (fitflex-functions#188).
  Future<Map<String, dynamic>> requestPass(
    String tier, {
    String? reference,
    String? payerPhone,
  }) async => await _request(
    'POST',
    '/me/subscribe',
    body: {
      'tier': tier,
      'type': 'platform_pass',
      'reference': ?reference,
      'payerPhone': ?payerPhone,
    },
  );

  Future<Map<String, dynamic>> subscribe(String tier) async =>
      await requestPass(tier);

  /// Whether paying by mobile money is available: {enabled, environment}.
  /// `environment` is 'sandbox' while it is being tested (no real money).
  Future<Map<String, dynamic>> paymentOptions() async =>
      await _request('GET', '/payments/options') as Map<String, dynamic>;

  /// Ask the member's phone to approve a pending payment request.
  Future<Map<String, dynamic>> payByMobileMoney(
    String paymentRequestId,
    String phone,
  ) async =>
      await _request(
            'POST',
            '/me/payments/$paymentRequestId/mobile-money',
            body: {'phone': phone},
          )
          as Map<String, dynamic>;

  /// Has the mobile-money payment gone through? state: in_progress |
  /// completed | failed | held | none.
  Future<Map<String, dynamic>> refreshMobileMoney(
    String paymentRequestId,
  ) async =>
      await _request(
            'POST',
            '/me/payments/$paymentRequestId/mobile-money/refresh',
          )
          as Map<String, dynamic>;

  /// The higher FitFlex Pass tiers the member can move up to, each with the
  /// difference they would pay. A 409 means there is no paid pass to upgrade.
  Future<Map<String, dynamic>> upgradeOptions() async =>
      await _request('GET', '/me/upgrade-options') as Map<String, dynamic>;

  /// Upgrade the FitFlex Pass by paying the price difference.
  Future<Map<String, dynamic>> upgradePass(
    String tier, {
    String? reference,
    String? payerPhone,
  }) async =>
      await _request(
            'POST',
            '/me/upgrade',
            body: {
              'tier': tier,
              'reference': ?reference,
              'payerPhone': ?payerPhone,
            },
          )
          as Map<String, dynamic>;

  /// A7: subscribe to a gym's own Daily/Weekly/Monthly plan.
  Future<Map<String, dynamic>> subscribeDirect({
    required String gymId,
    required String plan,
    String? reference,
    String? payerPhone,
  }) async => await _request(
    'POST',
    '/me/subscribe',
    body: {
      'type': 'direct_sub',
      'homeGymId': gymId,
      'plan': plan,
      'reference': ?reference,
      'payerPhone': ?payerPhone,
    },
  );

  Future<Map<String, dynamic>> myQr() async => await _request('GET', '/me/qr');

  /// Member self check-in: scan the static QR posted at the gym entrance.
  Future<Map<String, dynamic>> scanGymQr(String gymQr) async =>
      await _request('POST', '/me/checkins/scan', body: {'gymQr': gymQr})
          as Map<String, dynamic>;

  /// Owner/staff: the printable entrance QR for one of their gyms.
  Future<Map<String, dynamic>> gymEntranceQr(String gymId) async =>
      await _request('GET', '/operator/gyms/$gymId/entrance-qr')
          as Map<String, dynamic>;

  /// Saved gyms (US017).
  Future<List<String>> favoriteGymIds() async {
    final res = await _request('GET', '/me/favorites/gyms');
    return ((res as Map)['favoriteGymIds'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
  }

  Future<void> setFavoriteGym(String gymId, bool favorite) async =>
      await _request(favorite ? 'PUT' : 'DELETE', '/me/favorites/gyms/$gymId');

  /// Push: register / remove this device's FCM token.
  // ── Activity & Progress Engine ────────────────────────────────────────
  Future<List<dynamic>> myActivities({
    required DateTime from,
    required DateTime to,
  }) async {
    final query = Uri(
      queryParameters: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    ).query;
    final res = await _request('GET', '/me/activities?$query');
    return (res as Map)['activities'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> logActivity(Map<String, dynamic> data) async =>
      await _request('POST', '/me/activities', body: data);

  Future<void> deleteActivity(String id) async =>
      await _request('DELETE', '/me/activities/${Uri.encodeComponent(id)}');

  Future<List<dynamic>> myGoals() async {
    final res = await _request('GET', '/me/goals');
    return (res as Map)['goals'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> createGoal(Map<String, dynamic> data) async =>
      await _request('POST', '/me/goals', body: data);

  /// Marks a coaching goal done now, or undoes the latest mark.
  Future<Map<String, dynamic>> goalCheckIn(
    String id, {
    bool undo = false,
  }) async => await _request(
    'POST',
    '/me/goals/${Uri.encodeComponent(id)}/check-in${undo ? '/undo' : ''}',
  );

  /// Trainer: set a goal for a client (see fitflex-functions
  /// POST /trainer/clients/:id/goals).
  Future<Map<String, dynamic>> trainerAssignGoal(
    String relationshipId,
    Map<String, dynamic> body,
  ) async => await _request(
    'POST',
    '/trainer/clients/${Uri.encodeComponent(relationshipId)}/goals',
    body: body,
  );

  /// Trainer: retarget, retitle or archive a goal they set.
  Future<Map<String, dynamic>> trainerUpdateGoal(
    String relationshipId,
    String goalId,
    Map<String, dynamic> body,
  ) async => await _request(
    'PATCH',
    '/trainer/clients/${Uri.encodeComponent(relationshipId)}/goals/${Uri.encodeComponent(goalId)}',
    body: body,
  );

  Future<Map<String, dynamic>> updateGoal(
    String id,
    Map<String, dynamic> data,
  ) async => await _request(
    'PATCH',
    '/me/goals/${Uri.encodeComponent(id)}',
    body: data,
  );

  Future<List<dynamic>> workoutTemplates() async {
    final res = await _request('GET', '/workouts/templates');
    return (res as Map)['templates'] as List? ?? const [];
  }

  Future<List<dynamic>> myWorkouts({String? from, String? to}) async {
    final query = Uri(queryParameters: {'from': ?from, 'to': ?to}).query;
    final res = await _request(
      'GET',
      query.isEmpty ? '/me/workouts' : '/me/workouts?$query',
    );
    return (res as Map)['workouts'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> planWorkout(Map<String, dynamic> data) async =>
      await _request('POST', '/me/workouts', body: data);

  /// `{ workout }` — one of the member's workouts.
  Future<Map<String, dynamic>> myWorkout(String id) async =>
      await _request('GET', '/me/workouts/${Uri.encodeComponent(id)}');

  Future<Map<String, dynamic>> startWorkout(String id) async =>
      await _request('POST', '/me/workouts/${Uri.encodeComponent(id)}/start');

  Future<Map<String, dynamic>> saveWorkout(
    String id,
    Map<String, dynamic> log,
  ) async => await _request(
    'PATCH',
    '/me/workouts/${Uri.encodeComponent(id)}',
    body: log,
  );

  Future<Map<String, dynamic>> completeWorkout(
    String id,
    Map<String, dynamic> log,
  ) async => await _request(
    'POST',
    '/me/workouts/${Uri.encodeComponent(id)}/complete',
    body: log,
  );

  Future<Map<String, dynamic>> skipWorkout(String id) async =>
      await _request('POST', '/me/workouts/${Uri.encodeComponent(id)}/skip');

  /// `{ rating?, exercises?: [{ id, reason }] }` on a finished workout.
  Future<Map<String, dynamic>> workoutFeedback(
    String id,
    Map<String, dynamic> body,
  ) async => await _request(
    'POST',
    '/me/workouts/${Uri.encodeComponent(id)}/feedback',
    body: body,
  );

  /// Exercises that could stand in for one in the member's workout.
  Future<List<dynamic>> workoutExerciseAlternatives(
    String workoutId,
    String exerciseId, {
    String? lang,
  }) async {
    final q = lang == null ? '' : '?lang=${Uri.encodeQueryComponent(lang)}';
    final res = await _request(
      'GET',
      '/me/workouts/${Uri.encodeComponent(workoutId)}/exercises/'
          '${Uri.encodeComponent(exerciseId)}/alternatives$q',
    );
    return (res as Map)['alternatives'] as List? ?? const [];
  }

  /// `{ workout, exercise }` after the swap.
  Future<Map<String, dynamic>> replaceWorkoutExercise(
    String workoutId,
    String exerciseId,
    String libraryId, {
    String? lang,
  }) async => await _request(
    'POST',
    '/me/workouts/${Uri.encodeComponent(workoutId)}/exercises/'
        '${Uri.encodeComponent(exerciseId)}/replace',
    body: {'libraryId': libraryId, 'lang': ?lang},
  );

  // ── Training plans ────────────────────────────────────────────────────
  /// `{ preferences (as chosen), effective (as a plan would use them) }`.
  Future<Map<String, dynamic>> trainingPreferences() async =>
      await _request('GET', '/me/training-preferences');

  Future<Map<String, dynamic>> saveTrainingPreferences(
    Map<String, dynamic> body,
  ) async => await _request('PUT', '/me/training-preferences', body: body);

  /// `{ plan }` — the plan the member is on, or null.
  Future<Map<String, dynamic>> currentTrainingPlan() async =>
      await _request('GET', '/me/training-plans/current');

  /// Has FitFlex make a plan. `{ durationWeeks?, startDate?, replace? }`.
  Future<Map<String, dynamic>> createTrainingPlan(
    Map<String, dynamic> body,
  ) async => await _request('POST', '/me/training-plans', body: body);

  // Plans a trainer makes for a client.
  /// `{ offers }` — trainers' plans the member hasn't answered yet.
  Future<Map<String, dynamic>> trainingPlanOffers() async =>
      await _request('GET', '/me/training-plans/offers');

  /// `{ plan }` — the trainer's plan, now the member's.
  Future<Map<String, dynamic>> acceptTrainingPlan(String id) async =>
      await _request(
        'POST',
        '/me/training-plans/${Uri.encodeComponent(id)}/accept',
      );

  Future<void> declineTrainingPlan(String id) async => await _request(
    'POST',
    '/me/training-plans/${Uri.encodeComponent(id)}/decline',
  );

  /// `{ days, usedClientPreferences }` — FitFlex's first week for a client.
  Future<Map<String, dynamic>> trainerSuggestTrainingPlan(
    String connectionId,
    Map<String, dynamic> body,
  ) async => await _request(
    'POST',
    '/trainer/clients/${Uri.encodeComponent(connectionId)}'
        '/training-plans/suggestion',
    body: body,
  );

  /// Offers a client a plan. `{ name?, note?, durationWeeks, days: [...] }`.
  Future<Map<String, dynamic>> trainerOfferTrainingPlan(
    String connectionId,
    Map<String, dynamic> body,
  ) async => await _request(
    'POST',
    '/trainer/clients/${Uri.encodeComponent(connectionId)}/training-plans',
    body: body,
  );

  Future<List<dynamic>> trainerClientTrainingPlans(String connectionId) async {
    final res = await _request(
      'GET',
      '/trainer/clients/${Uri.encodeComponent(connectionId)}/training-plans',
    );
    return (res as Map)['plans'] as List? ?? const [];
  }

  /// Changes a plan the trainer made. `{ name?, note?, days?, … }`.
  Future<Map<String, dynamic>> trainerUpdateTrainingPlan(
    String planId,
    Map<String, dynamic> body,
  ) async => await _request(
    'PUT',
    '/trainer/training-plans/${Uri.encodeComponent(planId)}',
    body: body,
  );

  Future<void> trainerCancelTrainingPlan(String planId) async => await _request(
    'POST',
    '/trainer/training-plans/${Uri.encodeComponent(planId)}/cancel',
  );

  Future<Map<String, dynamic>> cancelTrainingPlan(String id) async =>
      await _request(
        'POST',
        '/me/training-plans/${Uri.encodeComponent(id)}/cancel',
      );

  // ── Trainer ↔ member connections ──────────────────────────────────────
  Future<List<dynamic>> myTrainerConnections() async {
    final res = await _request('GET', '/me/trainer-connections');
    return (res as Map)['connections'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> requestTrainerConnection(
    String trainerId,
    Map<String, bool> permissions,
  ) async => await _request(
    'POST',
    '/trainers/${Uri.encodeComponent(trainerId)}/connect',
    body: {'permissions': permissions},
  );

  Future<Map<String, dynamic>> updateTrainerConnection(
    String id,
    Map<String, bool> permissions,
  ) async => await _request(
    'PATCH',
    '/me/trainer-connections/${Uri.encodeComponent(id)}',
    body: {'permissions': permissions},
  );

  Future<Map<String, dynamic>> endTrainerConnection(String id) async =>
      await _request(
        'POST',
        '/me/trainer-connections/${Uri.encodeComponent(id)}/end',
      );

  Future<List<dynamic>> trainerClients() async {
    final res = await _request('GET', '/trainer/clients');
    return (res as Map)['clients'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> trainerDecideClient(
    String id, {
    required bool accept,
  }) async => await _request(
    'POST',
    '/trainer/clients/${Uri.encodeComponent(id)}/${accept ? 'accept' : 'decline'}',
  );

  Future<Map<String, dynamic>> trainerEndClient(String id) async =>
      await _request('POST', '/trainer/clients/${Uri.encodeComponent(id)}/end');

  Future<Map<String, dynamic>> trainerClientOverview(String id) async =>
      await _request('GET', '/trainer/clients/${Uri.encodeComponent(id)}');

  Future<Map<String, dynamic>> trainerAssignWorkout(
    String clientId,
    Map<String, dynamic> data,
  ) async => await _request(
    'POST',
    '/trainer/clients/${Uri.encodeComponent(clientId)}/workouts',
    body: data,
  );

  Future<void> trainerCancelWorkout(String workoutId) async => await _request(
    'DELETE',
    '/trainer/workouts/${Uri.encodeComponent(workoutId)}',
  );

  /// The FitFlex exercise library, in [lang] where translated.
  Future<List<dynamic>> trainingExercises({String? lang}) async {
    final q = lang == null ? '' : '?lang=${Uri.encodeQueryComponent(lang)}';
    final res = await _request('GET', '/training/exercises$q');
    return (res as Map)['exercises'] as List? ?? const [];
  }

  Future<List<dynamic>> trainerPlans() async {
    final res = await _request('GET', '/trainer/plans');
    return (res as Map)['plans'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> trainerSavePlan(
    String? id,
    Map<String, dynamic> plan,
  ) async => id == null
      ? await _request('POST', '/trainer/plans', body: plan)
      : await _request(
          'PUT',
          '/trainer/plans/${Uri.encodeComponent(id)}',
          body: plan,
        );

  Future<void> trainerDeletePlan(String id) async =>
      await _request('DELETE', '/trainer/plans/${Uri.encodeComponent(id)}');

  // ── Gym ↔ member sharing ──────────────────────────────────────────────
  Future<List<dynamic>> myGymSharing() async {
    final res = await _request('GET', '/me/gym-sharing');
    return (res as Map)['gyms'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> updateGymSharing(
    String gymId,
    Map<String, bool> permissions,
  ) async => await _request(
    'PUT',
    '/me/gym-sharing/${Uri.encodeComponent(gymId)}',
    body: {'permissions': permissions},
  );

  Future<List<dynamic>> ownerMemberActivity(String memberId) async {
    final res = await _request(
      'GET',
      '/owner/members/${Uri.encodeComponent(memberId)}/activity',
    );
    return (res as Map)['gyms'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> ownerEngagement({
    String? gymId,
  }) async => await _request(
    'GET',
    gymId == null
        ? '/owner/engagement'
        : '/owner/engagement?${Uri(queryParameters: {'gymId': gymId}).query}',
  );

  // ── Challenges ────────────────────────────────────────────────────────
  Future<List<dynamic>> myChallenges() async {
    final res = await _request('GET', '/me/challenges');
    return (res as Map)['challenges'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> joinChallenge(
    String id, {
    String? teamId,
    String? gymId,
    bool leaderboardOptIn = true,
  }) async => await _request(
    'POST',
    '/challenges/${Uri.encodeComponent(id)}/join',
    body: {
      'teamId': ?teamId,
      'gymId': ?gymId,
      'leaderboardOptIn': leaderboardOptIn,
    },
  );

  Future<Map<String, dynamic>> setLeaderboardOptIn(
    String id,
    bool optIn,
  ) async => await _request(
    'PUT',
    '/challenges/${Uri.encodeComponent(id)}/leaderboard-opt-in',
    body: {'optIn': optIn},
  );

  Future<Map<String, dynamic>> challengeLeaderboard(String id) async =>
      await _request(
        'GET',
        '/challenges/${Uri.encodeComponent(id)}/leaderboard',
      );

  Future<Map<String, dynamic>> creatorLeaderboard(
    String scope,
    String id, {
    String? gymId,
  }) async => await _request(
    'GET',
    _creatorPath(
      scope,
      '/${Uri.encodeComponent(id)}/leaderboard',
      gymId: gymId,
    ),
  );

  /// Daily step totals (or other readings) from this phone or a health
  /// platform. Upserted by (devicePlatform, externalId); a day only goes up.
  Future<Map<String, dynamic>> syncDeviceActivities(
    List<Map<String, dynamic>> records,
  ) async => Map<String, dynamic>.from(
    await _request('POST', '/me/device-activities', body: {'records': records})
        as Map,
  );

  /// Save a GPS-recorded run; the server works out the numbers.
  Future<Map<String, dynamic>> recordRun(Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(
        await _request('POST', '/me/activities/runs', body: body) as Map,
      );

  /// The private route of one of the member's own runs.
  Future<Map<String, dynamic>> runRoute(String activityId) async =>
      Map<String, dynamic>.from(
        await _request(
              'GET',
              '/me/activities/${Uri.encodeComponent(activityId)}/route',
            )
            as Map,
      );

  // ── Sharing between members ──────────────────────────────────────────
  Future<Map<String, dynamic>> _map(
    String method,
    String path, {
    Object? body,
  }) async => Map<String, dynamic>.from(
    await _request(method, path, body: body) as Map,
  );
  String _e(String v) => Uri.encodeComponent(v);

  Future<Map<String, dynamic>> socialSettings() =>
      _map('GET', '/me/social/settings');
  Future<Map<String, dynamic>> updateSocialSettings(Object? defaultShare) =>
      _map('PUT', '/me/social/settings', body: {'defaultShare': defaultShare});
  Future<Map<String, dynamic>> setPublicProfile(bool on) =>
      _map('PUT', '/me/social/settings', body: {'publicProfile': on});
  Future<Map<String, dynamic>> explore({String? before}) => _map(
    'GET',
    before == null
        ? '/social/explore'
        : '/social/explore?${Uri(queryParameters: {'before': before}).query}',
  );
  Future<Map<String, dynamic>> personProfile(
    String userId, {
    String? before,
  }) => _map(
    'GET',
    '/social/people/${_e(userId)}${before == null ? '' : '?${Uri(queryParameters: {'before': before}).query}'}',
  );
  Future<Map<String, dynamic>> postEngagement(String activityId) =>
      _map('GET', '/social/activities/${_e(activityId)}/engagement');
  Future<Map<String, dynamic>> connections() => _map('GET', '/me/connections');
  Future<Map<String, dynamic>> findPeople({String? q, String? code}) => _map(
    'GET',
    '/social/people?${Uri(queryParameters: {'q': ?q, 'code': ?code}).query}',
  );
  // Friend invitations: search by email / phone, request or share a link,
  // answer from Notifications. FitFlex sends nothing outside the app.
  Future<Map<String, dynamic>> friendLookup({
    String? email,
    String? phone,
  }) => _map(
    'GET',
    '/me/friend-invitations/lookup?${Uri(queryParameters: {'email': ?email, 'phone': ?phone}).query}',
  );
  Future<Map<String, dynamic>> friendInvitations() =>
      _map('GET', '/me/friend-invitations');
  Future<Map<String, dynamic>> inviteFriend({
    String? userId,
    String? email,
    String? phone,
    String? locale,
  }) => _map(
    'POST',
    '/me/friend-invitations',
    body: {
      'userId': ?userId,
      'email': ?email,
      'phone': ?phone,
      'locale': ?locale,
    },
  );
  Future<Map<String, dynamic>> approveFriendInvitation(String id) =>
      _map('POST', '/me/friend-invitations/${_e(id)}/approve');
  Future<Map<String, dynamic>> rejectFriendInvitation(String id) =>
      _map('POST', '/me/friend-invitations/${_e(id)}/reject');
  Future<Map<String, dynamic>> revokeFriendInvitation(String id) =>
      _map('DELETE', '/me/friend-invitations/${_e(id)}');
  Future<Map<String, dynamic>> claimFriendInvitation(String token) =>
      _map('POST', '/me/friend-invitations/claim', body: {'token': token});

  /// Public: what an invitation link is for. The token goes in the body so
  /// it stays out of server / CDN access logs. While the backend rolls out,
  /// a server without the POST route answers 404 with no FitFlex error code
  /// (or `not_found`); only then is the older GET (token in the path) used.
  /// A 404 `invalid_invitation` is a real answer and is not retried.
  Future<Map<String, dynamic>> previewFriendInvitation(String token) async {
    try {
      return await _map(
        'POST',
        '/friend-invitations/preview',
        body: {'token': token},
      );
    } on ApiException catch (e) {
      final code = e.code;
      if (e.status != 404 || (code != null && code != 'not_found')) rethrow;
      return _map('GET', '/friend-invitations/preview/${_e(token)}');
    }
  }

  Future<Map<String, dynamic>> follow(String userId) =>
      _map('POST', '/me/follows', body: {'userId': userId});
  Future<Map<String, dynamic>> unfollow(String userId) =>
      _map('DELETE', '/me/follows/${_e(userId)}');
  Future<Map<String, dynamic>> removeFollower(String userId) =>
      _map('DELETE', '/me/followers/${_e(userId)}');
  Future<Map<String, dynamic>> block(String userId) =>
      _map('POST', '/me/blocks', body: {'userId': userId});
  Future<Map<String, dynamic>> unblock(String userId) =>
      _map('DELETE', '/me/blocks/${_e(userId)}');
  Future<Map<String, dynamic>> shareActivity(
    String activityId,
    Object? shareWith,
  ) => _map(
    'PUT',
    '/me/activities/${_e(activityId)}/sharing',
    body: {'shareWith': shareWith},
  );
  Future<Map<String, dynamic>> feed({String? before}) => _map(
    'GET',
    before == null
        ? '/me/feed'
        : '/me/feed?${Uri(queryParameters: {'before': before}).query}',
  );
  Future<Map<String, dynamic>> sharedActivity(String id) =>
      _map('GET', '/social/activities/${_e(id)}');
  Future<Map<String, dynamic>> kudos(String id, bool on) =>
      _map(on ? 'POST' : 'DELETE', '/social/activities/${_e(id)}/kudos');
  Future<Map<String, dynamic>> addComment(String id, String text) => _map(
    'POST',
    '/social/activities/${_e(id)}/comments',
    body: {'text': text},
  );
  Future<Map<String, dynamic>> deleteComment(String commentId) =>
      _map('DELETE', '/social/comments/${_e(commentId)}');
  Future<Map<String, dynamic>> report(
    String targetType,
    String targetId, {
    String? reason,
  }) => _map(
    'POST',
    '/social/reports',
    body: {'targetType': targetType, 'targetId': targetId, 'reason': ?reason},
  );

  // ── Member usernames (feature flag on the server) ──
  Future<Map<String, dynamic>> usernameAvailable(String handle) => _map(
    'GET',
    '/me/username/available?${Uri(queryParameters: {'handle': handle}).query}',
  );
  Future<Map<String, dynamic>> setUsername(String handle) =>
      _map('PUT', '/me/username', body: {'username': handle});
  Future<Map<String, dynamic>> clearUsername() =>
      _map('DELETE', '/me/username');

  Future<Map<String, dynamic>> myGroups() => _map('GET', '/me/groups');
  Future<Map<String, dynamic>> createMyGroup(Map<String, dynamic> body) =>
      _map('POST', '/me/groups', body: body);
  Future<Map<String, dynamic>> discoverGroups({String q = ''}) =>
      _map('GET', '/social/groups?${Uri(queryParameters: {'q': q}).query}');
  Future<Map<String, dynamic>> joinGroup({
    String? groupId,
    String? inviteCode,
  }) => _map(
    'POST',
    '/social/groups/join',
    body: {'groupId': ?groupId, 'inviteCode': ?inviteCode},
  );
  Future<Map<String, dynamic>> leaveGroup(String id) =>
      _map('POST', '/social/groups/${_e(id)}/leave');

  /// Group pages: members use `/social/groups`; trainers and gyms their own
  /// prefix ([scope] `trainer` or `owner`, with [gymId] for gyms).
  String _groupBase(String? scope) =>
      scope == null ? '/social/groups' : '/$scope/groups';
  String _gymQ(String? gymId) =>
      gymId == null ? '' : '?${Uri(queryParameters: {'gymId': gymId}).query}';
  Future<Map<String, dynamic>> groupDetail(
    String id, {
    String? scope,
    String? gymId,
  }) => _map('GET', '${_groupBase(scope)}/${_e(id)}${_gymQ(gymId)}');
  Future<Map<String, dynamic>> updateGroup(
    String id,
    Map<String, dynamic> body, {
    String? scope,
    String? gymId,
  }) => _map(
    'PATCH',
    '${_groupBase(scope)}/${_e(id)}${_gymQ(gymId)}',
    body: body,
  );
  Future<Map<String, dynamic>> archiveGroup(
    String id, {
    String? scope,
    String? gymId,
  }) => _map('POST', '${_groupBase(scope)}/${_e(id)}/archive${_gymQ(gymId)}');
  Future<Map<String, dynamic>> groupMemberAction(
    String id,
    String userId,
    String action, {
    String? scope,
    String? gymId,
  }) => _map(
    'POST',
    '${_groupBase(scope)}/${_e(id)}/members/${_e(userId)}/$action${_gymQ(gymId)}',
  );
  Future<Map<String, dynamic>> ownedGroups(String scope, {String? gymId}) =>
      _map('GET', '/$scope/groups${_gymQ(gymId)}');
  Future<Map<String, dynamic>> createOwnedGroup(
    String scope,
    Map<String, dynamic> body, {
    String? gymId,
  }) => _map('POST', '/$scope/groups${_gymQ(gymId)}', body: body);

  /// Rewards the member earned from challenges, and where each stands.
  Future<List<dynamic>> myRewards() async {
    final res = await _request('GET', '/me/rewards');
    return (res as Map)['rewards'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> leaveChallenge(String id) async =>
      await _request('POST', '/challenges/${Uri.encodeComponent(id)}/leave');

  /// Creator endpoints. [scope] is `trainer` or `owner` (gym owner/staff);
  /// gym calls pass [gymId].
  String _creatorPath(String scope, String rest, {String? gymId}) {
    final q = gymId == null
        ? ''
        : '?${Uri(queryParameters: {'gymId': gymId}).query}';
    return '/$scope/challenges$rest$q';
  }

  Future<List<dynamic>> creatorChallenges(String scope, {String? gymId}) async {
    final res = await _request('GET', _creatorPath(scope, '', gymId: gymId));
    return (res as Map)['challenges'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> createChallenge(
    String scope,
    Map<String, dynamic> body, {
    String? gymId,
  }) async =>
      await _request('POST', _creatorPath(scope, '', gymId: gymId), body: body);

  Future<Map<String, dynamic>> cancelChallenge(
    String scope,
    String id, {
    String? gymId,
  }) => challengeAction(scope, id, 'cancel', gymId: gymId);

  /// Edit a challenge you created. Type and format lock once it starts or
  /// anyone joins; the start date locks once it starts.
  Future<Map<String, dynamic>> updateChallenge(
    String scope,
    String id,
    Map<String, dynamic> body, {
    String? gymId,
  }) async => await _request(
    'PATCH',
    _creatorPath(scope, '/${Uri.encodeComponent(id)}', gymId: gymId),
    body: body,
  );

  /// [action]: cancel, close, archive, publish, pause or resume.
  Future<Map<String, dynamic>> challengeAction(
    String scope,
    String id,
    String action, {
    String? gymId,
  }) async => await _request(
    'POST',
    _creatorPath(scope, '/${Uri.encodeComponent(id)}/$action', gymId: gymId),
  );

  Future<Map<String, dynamic>> challengeParticipants(
    String scope,
    String id, {
    String? gymId,
  }) async => await _request(
    'GET',
    _creatorPath(
      scope,
      '/${Uri.encodeComponent(id)}/participants',
      gymId: gymId,
    ),
  );

  Future<void> registerDeviceToken(String token, {String? platform}) async =>
      await _request(
        'POST',
        '/me/device-tokens',
        body: {'token': token, 'platform': ?platform},
      );

  Future<void> unregisterDeviceToken(String token) async => await _request(
    'POST',
    '/me/device-tokens/remove',
    body: {'token': token},
  );

  /// In-app notification inbox (newest first) plus unread count.
  Future<Map<String, dynamic>> notifications() async =>
      await _request('GET', '/me/notifications') as Map<String, dynamic>;

  Future<void> markNotificationRead(String id) async =>
      await _request('POST', '/me/notifications/$id/read');

  /// The member tapped the message's button — in the inbox or on a push.
  Future<void> clickNotification(String id, {String via = 'inbox'}) async =>
      await _request('POST', '/me/notifications/$id/click', body: {'via': via});

  /// A campaign push with no inbox copy was opened.
  Future<void> pushMessageOpened(String messageId) async =>
      await _request('POST', '/me/communications/messages/$messageId/opened');

  /// The member's B2B wellness benefits today, with used and remaining
  /// allowance (all worked out by the server).
  Future<Map<String, dynamic>> myWellnessBenefits() async =>
      await _request('GET', '/b2b/me/benefits') as Map<String, dynamic>;

  /// Organisations waiting for the member to accept being added by user id
  /// (fitflex-functions#241): `{ items: [...] }`. Each item says who is
  /// asking, what they will see (A-02) and what the member would get.
  Future<Map<String, dynamic>> myMemberRequests() async =>
      await _request('GET', '/b2b/me/member-requests') as Map<String, dynamic>;

  /// Accept an organisation's request: the add happens now. Single use.
  Future<Map<String, dynamic>> acceptMemberRequest(String requestId) async =>
      await _request(
            'POST',
            '/b2b/me/member-requests/${Uri.encodeComponent(requestId)}/accept',
          )
          as Map<String, dynamic>;

  /// Decline an organisation's request. Nothing is added.
  Future<Map<String, dynamic>> declineMemberRequest(String requestId) async =>
      await _request(
            'POST',
            '/b2b/me/member-requests/${Uri.encodeComponent(requestId)}/decline',
          )
          as Map<String, dynamic>;

  /// Ask to pay the member's share of a sponsored pass for this month.
  Future<Map<String, dynamic>> unlockSponsoredPass(
    String entitlementId,
  ) async =>
      await _request('POST', '/b2b/me/passes/$entitlementId/unlock')
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> communicationPreferences() async =>
      await _request('GET', '/me/communication-preferences')
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateCommunicationPreferences(
    Map<String, dynamic> changes,
  ) async =>
      await _request('PUT', '/me/communication-preferences', body: changes)
          as Map<String, dynamic>;

  /// Price one or more slots (Pass discount applied) without booking them.
  Future<Map<String, dynamic>> quoteTrainerBooking({
    required String trainerId,
    required String gymId,
    required List<Map<String, String>> slots,
  }) async => await _request(
    'POST',
    '/me/trainer-bookings/quote',
    body: {'trainerId': trainerId, 'gymId': gymId, 'slots': slots},
  );

  /// Book one or more slots. They stay payment_pending until an admin
  /// approves the payment request the backend creates alongside them.
  Future<Map<String, dynamic>> bookTrainer({
    required String trainerId,
    required String gymId,
    required List<Map<String, String>> slots,
  }) async => await _request(
    'POST',
    '/me/trainer-bookings',
    body: {'trainerId': trainerId, 'gymId': gymId, 'slots': slots},
  );

  Future<Map<String, dynamic>> trainerRegister(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/trainer/register', body: data);

  /// C8: trainer updates own professional profile (rate, specialties, bio,
  /// availability, photo).
  Future<Map<String, dynamic>> trainerUpdateProfile(
    Map<String, dynamic> data,
  ) async => await _request('PUT', '/trainer/me', body: data);

  /// C3: sessions for a date (bookings + manual). Defaults to today. With
  /// TRAINER_SESSION_OUTCOMES on, each `source: "booking"` entry carries
  /// `actions: { canComplete, canMarkNoShow }` (fitflex-functions#231).
  Future<Map<String, dynamic>> trainerSessions({String? date}) async {
    final path = (date == null || date.isEmpty)
        ? '/trainer/sessions'
        : '/trainer/sessions?${Uri(queryParameters: {'date': date}).query}';
    return await _request('GET', path);
  }

  /// My weekly payout statements, and whether my payout account is ready.
  Future<Map<String, dynamic>> trainerStatements() async =>
      await _request('GET', '/trainer/statements');

  /// One payout statement with the sessions it pays for.
  Future<Map<String, dynamic>> trainerStatement(String id) async =>
      await _request('GET', '/trainer/statements/${Uri.encodeComponent(id)}');

  /// Vendor: my weekly payout statements, and whether my payout account is ready.
  Future<Map<String, dynamic>> vendorPayoutStatements() async =>
      await _request('GET', '/vendor/statements');

  /// Vendor: one payout statement with the delivered orders it pays for.
  Future<Map<String, dynamic>> vendorPayoutStatement(String id) async =>
      await _request('GET', '/vendor/statements/${Uri.encodeComponent(id)}');

  /// C3: record a manual session (walk-in client).
  Future<Map<String, dynamic>> trainerCreateSession(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/trainer/sessions', body: data);

  /// C2: earnings auto-calculated from bookings + manual sessions.
  Future<Map<String, dynamic>> trainerEarnings({
    String? from,
    String? to,
  }) async {
    final query = <String, String>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
    };
    final path = query.isEmpty
        ? '/trainer/earnings'
        : '/trainer/earnings?${Uri(queryParameters: query).query}';
    return await _request('GET', path);
  }

  /// A4: member sends an enquiry or shows interest in a trainer.
  Future<Map<String, dynamic>> engageTrainer(
    String trainerId, {
    required String type,
    String? message,
    String? gymId,
  }) async => await _request(
    'POST',
    '/trainers/$trainerId/engage',
    body: {'type': type, 'message': ?message, 'gymId': ?gymId},
  );

  /// A4: trainer inbox for member enquiries and expressions of interest —
  /// each with its conversation (`messages`), `status` and `unread`.
  Future<List<dynamic>> trainerEngagements() async =>
      await _request('GET', '/trainer/engagements');

  /// Trainer replies to an enquiry or interest; the member is notified.
  Future<Map<String, dynamic>> trainerReplyEngagement(
    String id,
    String message,
  ) async => await _request(
    'POST',
    '/trainer/engagements/${Uri.encodeComponent(id)}/reply',
    body: {'message': message},
  );

  Future<Map<String, dynamic>> trainerReadEngagement(String id) async =>
      await _request(
        'POST',
        '/trainer/engagements/${Uri.encodeComponent(id)}/read',
      );

  Future<Map<String, dynamic>> trainerCloseEngagement(String id) async =>
      await _request(
        'POST',
        '/trainer/engagements/${Uri.encodeComponent(id)}/close',
      );

  /// The member's enquiries and interests, with each conversation.
  Future<List<dynamic>> myTrainerEngagements() async =>
      await _request('GET', '/me/trainer-engagements');

  /// The member follows up; the trainer is notified.
  Future<Map<String, dynamic>> memberReplyEngagement(
    String id,
    String message,
  ) async => await _request(
    'POST',
    '/me/trainer-engagements/${Uri.encodeComponent(id)}/reply',
    body: {'message': message},
  );

  Future<Map<String, dynamic>> memberReadEngagement(String id) async =>
      await _request(
        'POST',
        '/me/trainer-engagements/${Uri.encodeComponent(id)}/read',
      );

  /// C4: trainer buys one of a gym's trainer passes ('daily' | 'weekly' |
  /// 'monthly'). Pending until an admin approves the payment.
  Future<Map<String, dynamic>> trainerBuyPass(
    String gymId, {
    String? period,
  }) async => await _request(
    'POST',
    '/trainer/gyms/$gymId/trainer-pass',
    body: {'period': ?period},
  );

  /// At a gym that sells no trainer pass, the trainer buys its member plan.
  Future<Map<String, dynamic>> trainerBuyMemberPlan(
    String gymId,
    String plan,
  ) async => await _request(
    'POST',
    '/trainer/gyms/$gymId/member-plan',
    body: {'plan': plan},
  );

  /// Active gyms, each with `trainerAccess` { access, options } and the
  /// trainer's `currentPass` there.
  Future<List<dynamic>> trainerGyms() async =>
      await _request('GET', '/trainer/gyms') as List<dynamic>;

  /// The trainer's trainer passes and gym member plans, newest first.
  Future<List<dynamic>> trainerPasses() async =>
      await _request('GET', '/trainer/passes') as List<dynamic>;

  /// Withdraw a pass/plan request that is still awaiting payment.
  Future<Map<String, dynamic>> trainerCancelPass(String subscriptionId) async =>
      await _request('POST', '/trainer/passes/$subscriptionId/cancel');

  /// The trainer's own profile (linked + pending gyms).
  Future<Map<String, dynamic>> trainerMe() async =>
      await _request('GET', '/trainer/me') as Map<String, dynamic>;

  /// A trainer's bookable calendar (public; booked slots show as taken).
  Future<Map<String, dynamic>> trainerSchedule(
    String trainerId, {
    String? from,
    int? days,
    String? gymId,
  }) async => await _request(
    'GET',
    _withQuery('/trainers/${Uri.encodeComponent(trainerId)}/schedule', {
      'from': ?from,
      'days': ?days?.toString(),
      'gymId': ?gymId,
    }),
  );

  /// The trainer's own calendar, with who booked each taken slot.
  Future<Map<String, dynamic>> trainerMySchedule({
    String? from,
    int? days,
  }) async => await _request(
    'GET',
    _withQuery('/trainer/schedule', {'from': ?from, 'days': ?days?.toString()}),
  );

  /// The product categories vendors choose from (public).
  Future<Map<String, dynamic>> shopCategories() async =>
      await _request('GET', '/shop/categories');

  /// Shop home V2: the sections for the role being shopped as. 404
  /// `feature_disabled` means the screen falls back to the plain list; 403
  /// `mode_not_allowed` means this account cannot shop in [mode].
  ///
  /// [session] (the app's promotion session, as on `/discover/*`) lets the
  /// server sign promotion tokens for Featured cards. [mode] null asks for
  /// the server's default role.
  ///
  /// [areaId] (Phase 2 S3, "Popular near you") is the id of the area the
  /// phone worked out from its own position, sent in the `X-FF-Area` header
  /// (not the URL, so it stays out of URL logs and history). It is the only
  /// location-derived value the app ever sends: there is deliberately no
  /// latitude/longitude parameter here.
  Future<Map<String, dynamic>> shopHome({
    String? mode,
    String? session,
    List<String> recent = const [],
    String? areaId,
  }) async {
    Map<String, String>? headers;
    final out = await _request(
      'GET',
      _withQuery('/shop/home', {
        if (mode != null && mode.isNotEmpty) 'mode': mode,
        if (session != null && _discoverSession.hasMatch(session))
          'session': session,
        if (recent.isNotEmpty) 'recent': recent.join(','),
      }),
      extraHeaders: {
        if (areaId != null && areaId.isNotEmpty) kShopAreaHeader: areaId,
        ..._shopCaps,
      },
      onHeaders: (h) => headers = h,
    );
    ShopClock.syncFrom(out, headers);
    return Map<String, dynamic>.from(out as Map);
  }

  /// The header that carries the near-you area on GET /shop/home.
  static const kShopAreaHeader = 'X-FF-Area';

  /// Phase 2 S4: what this build can show, on GET /shop/home,
  /// /shop/products and /shop/products/:id. Without `flash_sale` the
  /// server leaves out the flash_sale section and the `sale` fields (so
  /// older builds never see prices they can't explain).
  static const kShopCapsHeader = 'X-FF-Shop-Caps';
  static const _shopCaps = {kShopCapsHeader: 'flash_sale'};

  /// GET with the shop capability header, syncing [ShopClock] from the
  /// answer (docs/shop-flash-sales-api.md revision 2, item 4).
  Future<dynamic> _shopGet(String path, {Map<String, String>? headers}) async {
    Map<String, String>? got;
    final out = await _request(
      'GET',
      path,
      extraHeaders: {...?headers, ..._shopCaps},
      onHeaders: (h) => got = h,
    );
    ShopClock.syncFrom(out, got);
    return out;
  }

  /// The active shop areas (Phase 2 S3): `{areas: [{id, level, name, names,
  /// parentId, lat, lng, radiusKm}]}`. 404 `feature_disabled` when
  /// SHOP_NEAR_YOU is off. The same for everyone (nothing personal).
  Future<Map<String, dynamic>> shopAreas() async {
    final out = await _request('GET', '/shop/areas');
    return Map<String, dynamic>.from(out as Map);
  }

  /// Shop personalisation (Phase 2 S2): `{personalised, available}`. 404
  /// `feature_disabled` when SHOP_PERSONALISATION is off.
  ///
  /// [mode] (the role being shopped as, as on /shop/home) lets the server
  /// say what is used in that mode; an older server ignores it.
  Future<Map<String, dynamic>> shopPreferences({String? mode}) async {
    Future<Object?> ask(String? m) => _request(
      'GET',
      _withQuery('/shop/preferences', {
        if (m != null && m.isNotEmpty) 'mode': m,
      }),
    );
    return Map<String, dynamic>.from(await _retryWithoutMode(mode, ask) as Map);
  }

  /// `403 mode_not_allowed` (this person does not hold [mode]): ask once
  /// more without a mode, for the server's default role (as /shop/home).
  Future<Object?> _retryWithoutMode(
    String? mode,
    Future<Object?> Function(String? mode) call,
  ) async {
    try {
      return await call(mode);
    } on ApiException catch (e) {
      if (mode == null ||
          mode.isEmpty ||
          e.status != 403 ||
          e.code != 'mode_not_allowed') {
        rethrow;
      }
      return await call(null);
    }
  }

  /// Turns "Personalised shop" on or off. [source] is `privacy_page` or
  /// `why_sheet`. Answers like [shopPreferences].
  Future<Map<String, dynamic>> updateShopPreferences({
    required bool personalised,
    required String source,
    String? mode,
  }) async {
    // A refused mode saves nothing on the server, so the retry is safe.
    final out = await _retryWithoutMode(
      mode,
      (m) => _request(
        'PUT',
        _withQuery('/shop/preferences', {
          if (m != null && m.isNotEmpty) 'mode': m,
        }),
        body: {'personalised': personalised, 'source': source},
      ),
    );
    return Map<String, dynamic>.from(out as Map);
  }

  /// One shop analytics event (see `ShopEvents`, which decides the fields).
  Future<void> postShopEvent(Map<String, dynamic> event) async =>
      await _request('POST', '/shop/events', body: event);

  // Shop (D1)
  Future<List<dynamic>> listShopProducts({
    String? category,
    String? search,
    String? brand,
    String? vendorId,
    num? minPrice,
    num? maxPrice,
    num? minRating,
    num? maxDistanceKm,
    bool? delivery,
    bool? promotions,
    String? sort,

    /// Shop S3 (QA #4): the near-you area, in `X-FF-Area` (never the URL),
    /// so rows can carry `deliversToViewerArea`.
    String? areaId,
  }) async {
    final query = <String, String>{
      if (category != null && category.isNotEmpty) 'category': category,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (brand != null && brand.trim().isNotEmpty) 'brand': brand.trim(),
      if (vendorId != null && vendorId.isNotEmpty) 'vendorId': vendorId,
      if (minPrice != null) 'minPrice': '$minPrice',
      if (maxPrice != null) 'maxPrice': '$maxPrice',
      if (minRating != null) 'minRating': '$minRating',
      if (maxDistanceKm != null) 'maxDistanceKm': '$maxDistanceKm',
      if (delivery != null) 'delivery': '$delivery',
      if (promotions != null) 'promotions': '$promotions',
      if (sort != null && sort.isNotEmpty) 'sort': sort,
    };
    final path = query.isEmpty
        ? '/shop/products'
        : '/shop/products?${Uri(queryParameters: query).query}';
    Map<String, String>? headers;
    final out = await _request(
      'GET',
      path,
      extraHeaders: {...?_areaHeader(areaId), ..._shopCaps},
      onHeaders: (h) => headers = h,
    );
    ShopClock.syncFrom(out, headers);
    return out;
  }

  Future<Map<String, dynamic>> createShopOrder(
    List<Map<String, dynamic>> items, {
    String? note,
    required String deliveryMethod,
    String? pickupGymId,
    String? deliveryAddress,
    required String paymentMethod,
    String paymentOutcome = 'success',

    /// Makes a retry safe: the server returns the order this key already made
    /// instead of making another (the client also retries dropped connections).
    String? idempotencyKey,
  }) async => await _request(
    'POST',
    '/me/shop-orders',
    extraHeaders: {'Idempotency-Key': ?idempotencyKey},
    body: {
      'items': items,
      'note': ?note,
      'deliveryMethod': deliveryMethod,
      'pickupGymId': ?pickupGymId,
      'deliveryAddress': ?deliveryAddress,
      'paymentMethod': paymentMethod,
      'paymentOutcome': paymentOutcome,
    },
  );

  /// [areaId]: the near-you area in `X-FF-Area` (QA #4), for the
  /// "Delivers to your area" badge.
  Future<Map<String, dynamic>> shopProduct(String id, {String? areaId}) async {
    Map<String, String>? headers;
    final out = await _request(
      'GET',
      '/shop/products/$id',
      extraHeaders: {...?_areaHeader(areaId), ..._shopCaps},
      onHeaders: (h) => headers = h,
    );
    ShopClock.syncFrom(out, headers);
    return out;
  }

  static Map<String, String>? _areaHeader(String? areaId) =>
      areaId == null || areaId.isEmpty ? null : {kShopAreaHeader: areaId};

  Future<Map<String, dynamic>> vendorStore(String id) async =>
      Map<String, dynamic>.from(await _shopGet('/shop/vendors/$id') as Map);

  Future<Map<String, dynamic>> sendMarketplaceEnquiry(
    String productId,
    String message,
  ) async => await _request(
    'POST',
    '/me/marketplace-enquiries',
    body: {'productId': productId, 'message': message},
  );

  Future<Map<String, dynamic>> reviewMarketplaceProduct(
    String orderId,
    String productId,
    int rating,
    String comment,
  ) async => await _request(
    'POST',
    '/me/shop-orders/$orderId/reviews',
    body: {'productId': productId, 'rating': rating, 'comment': comment},
  );

  Future<Map<String, dynamic>> reorderMarketplaceOrder(String orderId) async =>
      await _request('POST', '/me/shop-orders/$orderId/reorder');

  Future<List<dynamic>> myShopOrders() async =>
      await _request('GET', '/me/shop-orders');

  /// Cancel my order before it is dispatched. A paid order is refunded in full.
  Future<Map<String, dynamic>> cancelMyShopOrder(String orderId) async =>
      await _request('POST', '/me/shop-orders/$orderId/cancel');

  // ── Trainer sessions I booked, cancellations and refunds ─────────────

  /// My trainer bookings; each carries `cancellation` (canCancel, refundable, cancelBy).
  Future<List<dynamic>> myTrainerBookings() async =>
      await _request('GET', '/me/trainer-bookings');

  /// Cancel one session: unpaid any time before it starts, paid up to 24
  /// hours before (refunded in full).
  Future<Map<String, dynamic>> cancelMyTrainerBooking(String bookingId) async =>
      await _request('POST', '/me/trainer-bookings/$bookingId/cancel');

  /// Trainer: cancel a session any time before it starts; the member is refunded.
  Future<Map<String, dynamic>> trainerCancelBooking(String bookingId) async =>
      await _request('POST', '/trainer/bookings/$bookingId/cancel');

  /// Trainer: the session took place. Only once it has started
  /// (409 `session_not_started` with `startsAt`).
  Future<Map<String, dynamic>> trainerCompleteBooking(String bookingId) async =>
      await _request(
        'POST',
        '/trainer/bookings/${Uri.encodeComponent(bookingId)}/complete',
      );

  /// Trainer: the client didn't come. The session is paid as booked and the
  /// member is told. 404 `feature_disabled` while the flag is off.
  Future<Map<String, dynamic>> trainerMarkNoShow(String bookingId) async =>
      await _request(
        'POST',
        '/trainer/bookings/${Uri.encodeComponent(bookingId)}/no-show',
      );

  Future<Map<String, dynamic>> myRefunds() async =>
      await _request('GET', '/me/refunds');

  Future<List<dynamic>> myPayments() async =>
      await _request('GET', '/me/payments');

  /// Ask for a pass or plan payment back.
  Future<Map<String, dynamic>> requestRefund({
    required String paymentRequestId,
    required String reasonCode,
    String? note,
  }) async => await _request(
    'POST',
    '/me/refunds',
    body: {
      'paymentRequestId': paymentRequestId,
      'reasonCode': reasonCode,
      'note': ?note,
    },
  );

  Future<List<dynamic>> vendorProducts() async =>
      await _request('GET', '/vendor/products');

  Future<Map<String, dynamic>> vendorSaveProduct(
    Map<String, dynamic> data, {
    String? productId,
  }) async => await _request(
    productId == null ? 'POST' : 'PUT',
    productId == null ? '/vendor/products' : '/vendor/products/$productId',
    body: data,
  );

  // ── Vendor tools (stock ledger, S1) ─────────────────────────────────────

  /// Which vendor tools this server has switched on, e.g.
  /// `{stockLedger: true, ...}`. Anything but `true` means "not on".
  Future<Map<String, dynamic>> vendorToolsOptions() async =>
      await _request('GET', '/vendor/tools/options');

  // ── Vendor flash sales (Shop home Phase 2 S4, SHOP_FLASH_SALES) ───────
  // fitflex-functions docs/shop-flash-sales-api.md "Vendor endpoints".
  // Every route answers 404 `feature_disabled` while the flag is off.

  /// The sales on this vendor's products, one page: `{items: [sale],
  /// total, nextCursor, vendor: {canPropose, reason}, proposalExpiryDays,
  /// openProposals: {open, max}, rules: {...}}`.
  Future<Map<String, dynamic>> vendorFlashSales({
    int limit = 100,
    String? cursor,
    String? status,
    String? productId,
  }) async {
    final out = await _request(
      'GET',
      _withQuery('/vendor/flash-sales', {
        'limit': '$limit',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        if (status != null && status.isNotEmpty) 'status': status,
        if (productId != null && productId.isNotEmpty) 'productId': productId,
      }),
    );
    if (out is List) return {'items': out};
    return out is Map ? Map<String, dynamic>.from(out) : <String, dynamic>{};
  }

  /// `{ok, productId, regularPriceTzs, discountPriceTzs, effectivePriceTzs,
  /// maxSalePriceTzs, raisedAt, raisedOn, earliestStart, lockedBy}` for a
  /// sale on [productId] starting at [startsAt] (default: an hour from now).
  Future<Map<String, dynamic>> vendorFlashSalePriceCheck(
    String productId, {
    DateTime? startsAt,
  }) async {
    final out = await _request(
      'GET',
      _withQuery('/vendor/flash-sales/price-check', {
        'productId': productId,
        if (startsAt != null) 'startsAt': startsAt.toUtc().toIso8601String(),
      }),
    );
    return out is Map ? Map<String, dynamic>.from(out) : <String, dynamic>{};
  }

  /// One sale (`{sale}`); 404 `sale_not_found` for another vendor's.
  Future<Map<String, dynamic>> vendorFlashSale(String id) async =>
      _saleOf(await _request('GET', '/vendor/flash-sales/${_seg(id)}'));

  /// Creates a sale as a draft (`{productId, salePriceTzs, startsAt,
  /// endsAt}`, all required). Answers the sale.
  Future<Map<String, dynamic>> vendorCreateFlashSale(
    Map<String, dynamic> body,
  ) async => _saleOf(await _request('POST', '/vendor/flash-sales', body: body));

  /// Changes `salePriceTzs` / `startsAt` / `endsAt`. A scheduled sale goes
  /// back for approval; a rejected one becomes a draft.
  Future<Map<String, dynamic>> vendorUpdateFlashSale(
    String id,
    Map<String, dynamic> body,
  ) async => _saleOf(
    await _request('PATCH', '/vendor/flash-sales/${_seg(id)}', body: body),
  );

  Future<Map<String, dynamic>> vendorSubmitFlashSale(String id) async =>
      _saleOf(
        await _request(
          'POST',
          '/vendor/flash-sales/${_seg(id)}/submit',
          body: const <String, dynamic>{},
        ),
      );

  Future<Map<String, dynamic>> vendorWithdrawFlashSale(String id) async =>
      _saleOf(
        await _request(
          'POST',
          '/vendor/flash-sales/${_seg(id)}/withdraw',
          body: const <String, dynamic>{},
        ),
      );

  /// Ends the vendor's own live or scheduled sale now.
  Future<Map<String, dynamic>> vendorEndFlashSale(String id) async => _saleOf(
    await _request(
      'POST',
      '/vendor/flash-sales/${_seg(id)}/end',
      body: const <String, dynamic>{},
    ),
  );

  static Map<String, dynamic> _saleOf(Object? out) {
    if (out is Map && out['sale'] is Map) {
      return Map<String, dynamic>.from(out['sale'] as Map);
    }
    return out is Map ? Map<String, dynamic>.from(out) : <String, dynamic>{};
  }

  // ── Vendor shop banners (Shop home Phase 2 S1, SHOP_BANNERS) ──────────

  /// The vendor's own banner proposals, newest first:
  /// `{items: [banner], total, nextCursor, vendor: {canPropose, reason},
  /// proposalExpiryDays}` (docs/shop-banners-api.md). 404
  /// `feature_disabled` while SHOP_BANNERS is off.
  /// One page: [limit] (the server allows up to 100) from [cursor] (the
  /// previous page's `nextCursor`).
  Future<Map<String, dynamic>> vendorShopBanners({
    int limit = 100,
    String? cursor,
    String? status,
  }) async {
    final out = await _request(
      'GET',
      _withQuery('/vendor/shop-banners', {
        'limit': '$limit',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        if (status != null && status.isNotEmpty) 'status': status,
      }),
    );
    if (out is List) return {'items': out};
    return out is Map ? Map<String, dynamic>.from(out) : <String, dynamic>{};
  }

  /// Creates a banner (not yet sent for approval). Answers the banner.
  Future<Map<String, dynamic>> vendorCreateShopBanner(
    Map<String, dynamic> body,
  ) async =>
      _bannerOf(await _request('POST', '/vendor/shop-banners', body: body));

  /// Changes a banner. 409 `not_editable` once it can no longer change.
  Future<Map<String, dynamic>> vendorUpdateShopBanner(
    String id,
    Map<String, dynamic> body,
  ) async => _bannerOf(
    await _request('PATCH', '/vendor/shop-banners/${_seg(id)}', body: body),
  );

  /// Sends a banner to FitFlex for approval.
  Future<Map<String, dynamic>> vendorSubmitShopBanner(String id) async =>
      _bannerOf(
        await _request(
          'POST',
          '/vendor/shop-banners/${_seg(id)}/submit',
          body: const <String, dynamic>{},
        ),
      );

  /// Ends a live banner now.
  Future<Map<String, dynamic>> vendorEndShopBanner(String id) async =>
      _bannerOf(
        await _request(
          'POST',
          '/vendor/shop-banners/${_seg(id)}/end',
          body: const <String, dynamic>{},
        ),
      );

  /// Takes a banner back before it goes live.
  Future<Map<String, dynamic>> vendorWithdrawShopBanner(String id) async =>
      _bannerOf(
        await _request(
          'POST',
          '/vendor/shop-banners/${_seg(id)}/withdraw',
          body: const <String, dynamic>{},
        ),
      );

  /// Uploads a banner's photo: `file`, `people` (`none` |
  /// `product_models`), `rightsConfirmed` and, for models,
  /// `peopleConfirmed`. Answers the banner.
  Future<Map<String, dynamic>> vendorUploadShopBannerImage(
    String id, {
    required List<int> bytes,
    required String filename,
    required String people,
    required bool rightsConfirmed,
    bool peopleConfirmed = false,
    String? confirmationVersion,
    String? consentRef,
    String? licenceRef,
  }) async {
    final uri = Uri.parse('$baseUrl/vendor/shop-banners/${_seg(id)}/image');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      )
      ..fields['people'] = people;
    if (rightsConfirmed) request.fields['rightsConfirmed'] = 'true';
    if (peopleConfirmed) request.fields['peopleConfirmed'] = 'true';
    if (confirmationVersion != null && confirmationVersion.isNotEmpty) {
      request.fields['confirmationVersion'] = confirmationVersion;
    }
    if (consentRef != null && consentRef.isNotEmpty) {
      request.fields['consentRef'] = consentRef;
    }
    if (licenceRef != null && licenceRef.isNotEmpty) {
      request.fields['licenceRef'] = licenceRef;
    }
    request.headers['x-fitflex-client'] = kIdentityV2Client;
    if (_token != null) request.headers['authorization'] = 'Bearer $_token';
    _log.multipart('POST', uri, bytes.length);
    final streamed = await request.send().timeout(const Duration(seconds: 90));
    final res = await http.Response.fromStream(streamed);
    _log.response('POST', uri, res.statusCode, res.body);
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    final decoded = res.body.isEmpty
        ? null
        : ok
        ? jsonDecode(res.body)
        : _decodeErrorBody(res.body);
    if (ok) return _bannerOf(decoded);
    if (res.statusCode == 401 && onUnauthorized != null) onUnauthorized!();
    throw ApiException(res.statusCode, decoded);
  }

  /// A banner answer: the banner itself or `{banner: {...}}`.
  static Map<String, dynamic> _bannerOf(Object? out) {
    if (out is Map && out['banner'] is Map) {
      return Map<String, dynamic>.from(out['banner'] as Map);
    }
    return out is Map ? Map<String, dynamic>.from(out) : <String, dynamic>{};
  }

  /// Records a stock change with a reason. Answers `{movement, product}`;
  /// a retried [body] (same `clientRef`) gets the first answer back.
  Future<Map<String, dynamic>> vendorAdjustStock(
    String productId,
    Map<String, dynamic> body,
  ) async => await _request(
    'POST',
    '/vendor/products/${Uri.encodeComponent(productId)}/stock-adjustments',
    body: body,
  );

  /// One product's stock history, newest first. [from] / [to] are EAT days
  /// (YYYY-MM-DD, inclusive).
  Future<Map<String, dynamic>> vendorStockMovements(
    String productId, {
    String? from,
    String? to,
    String? variant,
    int? limit,
    String? cursor,
  }) async {
    final query = <String, String>{
      'from': ?from,
      'to': ?to,
      if (variant != null && variant.isNotEmpty) 'variant': variant,
      if (limit != null) 'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final path =
        '/vendor/products/${Uri.encodeComponent(productId)}/stock-movements';
    return await _request(
      'GET',
      query.isEmpty ? path : '$path?${Uri(queryParameters: query).query}',
    );
  }

  // ── Vendor walk-in sales (S3) ───────────────────────────────────────────

  /// Records a walk-in sale. 201 and a replay (200, same `clientRef`) both
  /// answer `{sale}`.
  Future<Map<String, dynamic>> vendorRecordSale(
    Map<String, dynamic> body,
  ) async => await _request('POST', '/vendor/sales', body: body);

  /// Walk-in sales, newest first, with the range summary. [from] / [to] are
  /// EAT days (YYYY-MM-DD, inclusive).
  Future<Map<String, dynamic>> vendorSales({
    String? from,
    String? to,
    String? status,
    bool mine = false,
    int? limit,
    String? cursor,
    String? kind,
  }) async {
    final query = <String, String>{
      'from': ?from,
      'to': ?to,
      if (status != null && status.isNotEmpty) 'status': status,
      if (mine) 'createdBy': 'me',
      // S4: cash | credit (pay later); only sent when the filter is used.
      if (kind != null && kind.isNotEmpty && kind != 'all') 'kind': kind,
      if (limit != null) 'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    return await _request(
      'GET',
      query.isEmpty
          ? '/vendor/sales'
          : '/vendor/sales?${Uri(queryParameters: query).query}',
    );
  }

  Future<Map<String, dynamic>> vendorSale(String saleId) async =>
      await _request('GET', '/vendor/sales/${Uri.encodeComponent(saleId)}');

  Future<Map<String, dynamic>> vendorVoidSale(
    String saleId,
    String reason,
  ) async => await _request(
    'POST',
    '/vendor/sales/${Uri.encodeComponent(saleId)}/void',
    body: {'reason': reason},
  );

  // ── Vendor customers, pay later, customer payments (S4) ────────────────

  static String _seg(String id) => Uri.encodeComponent(id);

  /// Customers of my business. Staff with `customers` get money figures;
  /// staff with `sales` only get the POS picker shape (no money).
  Future<Map<String, dynamic>> vendorCustomers({
    String? q,
    String? filter,
    String? bucket,
    String? sort,
    int? limit,
    String? cursor,
  }) async => await _request(
    'GET',
    _withQuery('/vendor/customers', {
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (filter != null && filter.isNotEmpty && filter != 'all')
        'filter': filter,
      if (bucket != null && bucket.isNotEmpty) 'bucket': bucket,
      if (sort != null && sort.isNotEmpty && sort != 'name') 'sort': sort,
      if (limit != null) 'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    }),
  );

  /// Adds a walk-in customer. 201 `{customer, phoneDuplicate}`; a retry
  /// with the same `clientRef` answers 200 with the same customer.
  Future<Map<String, dynamic>> vendorCreateCustomer(
    Map<String, dynamic> body,
  ) async => await _request('POST', '/vendor/customers', body: body);

  /// One customer's profile (owed, aging, open pay-later sales, totals).
  Future<Map<String, dynamic>> vendorCustomer(String id) async =>
      await _request('GET', '/vendor/customers/${_seg(id)}');

  /// Edit, archive or restore. Only the fields sent change.
  Future<Map<String, dynamic>> vendorUpdateCustomer(
    String id,
    Map<String, dynamic> body,
  ) async => await _request('PUT', '/vendor/customers/${_seg(id)}', body: body);

  /// This customer's walk-in sales (the GET /vendor/sales shape).
  Future<Map<String, dynamic>> vendorCustomerSales(
    String id, {
    String? kind,
    int? limit,
    String? cursor,
  }) async => await _request(
    'GET',
    _withQuery('/vendor/customers/${_seg(id)}/sales', {
      if (kind != null && kind.isNotEmpty && kind != 'all') 'kind': kind,
      if (limit != null) 'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    }),
  );

  /// One walk-in sale of this customer (read-only detail for people with
  /// `customers`, whether or not they also have `sales`).
  Future<Map<String, dynamic>> vendorCustomerSale(
    String id,
    String saleId,
  ) async => await _request(
    'GET',
    '/vendor/customers/${_seg(id)}/sales/${_seg(saleId)}',
  );

  /// This app customer's paid app orders with me (no contact details).
  Future<Map<String, dynamic>> vendorCustomerOrders(
    String id, {
    int? limit,
    String? cursor,
  }) async => await _request(
    'GET',
    _withQuery('/vendor/customers/${_seg(id)}/orders', {
      if (limit != null) 'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    }),
  );

  /// This customer's payments, newest first (voided ones too). [from] is an
  /// EAT day (receivedOn ≥ from).
  Future<Map<String, dynamic>> vendorCustomerPayments(
    String id, {
    String? from,
    int? limit,
    String? cursor,
  }) async => await _request(
    'GET',
    _withQuery('/vendor/customers/${_seg(id)}/payments', {
      if (from != null && from.isNotEmpty) 'from': from,
      if (limit != null) 'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    }),
  );

  Future<Map<String, dynamic>> vendorCustomerPayment(
    String id,
    String paymentId,
  ) async => await _request(
    'GET',
    '/vendor/customers/${_seg(id)}/payments/${_seg(paymentId)}',
  );

  /// Records money the customer paid the vendor directly. 201 / 200 replay
  /// (same `clientRef`) answer `{payment, customer}`.
  Future<Map<String, dynamic>> vendorRecordCustomerPayment(
    String id,
    Map<String, dynamic> body,
  ) async => await _request(
    'POST',
    '/vendor/customers/${_seg(id)}/payments',
    body: body,
  );

  Future<Map<String, dynamic>> vendorVoidCustomerPayment(
    String id,
    String paymentId,
    String reason,
  ) async => await _request(
    'POST',
    '/vendor/customers/${_seg(id)}/payments/${_seg(paymentId)}/void',
    body: {'reason': reason},
  );

  /// "Owed to you": totals over every customer who owes, and a page of rows.
  Future<Map<String, dynamic>> vendorReceivablesAging({
    String? bucket,
    String? sort,
    int? limit,
    String? cursor,
  }) async => await _request(
    'GET',
    _withQuery('/vendor/receivables/aging', {
      if (bucket != null && bucket.isNotEmpty) 'bucket': bucket,
      if (sort != null && sort.isNotEmpty && sort != 'overdue') 'sort': sort,
      if (limit != null) 'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    }),
  );

  // ── Vendor documents and VAT (S5) ──────────────────────────────────────

  /// Makes a share link for one document (fitflex-functions #229). [kind] is
  /// `sale`, `order`, `payment` (needs [customerId]) or `statement` ([id] is
  /// the customer id). 201 `{linkId, url, lang, docType, docId, number,
  /// texts: {en: {whatsapp, sms}, sw: {…}}, whatsappText, smsText}`. The
  /// URL is shown once: only its hash is kept on the server. 503
  /// `public_url_not_configured` while the server has no public address.
  Future<Map<String, dynamic>> vendorShareDocument({
    required String kind,
    required String id,
    String? customerId,
    String? lang,
  }) async {
    final path = switch (kind) {
      'sale' => '/vendor/sales/${_seg(id)}/share',
      'order' => '/vendor/orders/${_seg(id)}/share',
      'payment' =>
        '/vendor/customers/${_seg(customerId ?? '')}/payments/${_seg(id)}/share',
      'statement' => '/vendor/customers/${_seg(id)}/statement/share',
      _ => throw ArgumentError.value(kind, 'kind'),
    };
    return await _request('POST', path, body: {'lang': ?lang});
  }

  /// The links made for one document (never their URLs):
  /// `{links: [{id, n, docType, docId, lang, createdAt, createdBy {id,
  /// firstName}, lastOpenedAt, revokedAt, active}], activeCount}`.
  Future<Map<String, dynamic>> vendorDocumentLinks({
    required String docType,
    required String docId,
  }) async => await _request(
    'GET',
    _withQuery('/vendor/document-links', {'docType': docType, 'docId': docId}),
  );

  /// Turns one link off (permanent). `{link}`.
  Future<Map<String, dynamic>> vendorRevokeDocumentLink(String linkId) async =>
      await _request('POST', '/vendor/documents/${_seg(linkId)}/revoke');

  /// Turns every active link of one document off. `{links, revokedCount}`.
  Future<Map<String, dynamic>> vendorRevokeDocumentLinks({
    required String docType,
    required String docId,
  }) async => await _request(
    'POST',
    '/vendor/document-links/revoke',
    body: {'docType': docType, 'docId': docId},
  );

  /// One document as JSON `{doc}` (no link is made). [docType] is `sale`,
  /// `payment`, `statement` (id = customer id, live) or `order`.
  Future<Map<String, dynamic>> vendorDocument(
    String docType,
    String docId, {
    String? lang,
  }) async => await _request(
    'GET',
    _withQuery('/vendor/documents/${_seg(docType)}/${_seg(docId)}', {
      'format': 'json',
      'lang': ?lang,
    }),
  );

  /// The same document as a PDF (`paper` a4 or 80mm). Answers the bytes and
  /// the server's file name.
  Future<({Uint8List bytes, String? fileName})> vendorDocumentPdf(
    String docType,
    String docId, {
    String? lang,
    String paper = 'a4',
  }) => _binary(
    _withQuery('/vendor/documents/${_seg(docType)}/${_seg(docId)}', {
      'format': 'pdf',
      'lang': ?lang,
      'paper': paper,
    }),
  );

  /// My tax (VAT) details: `{taxProfile}`. Vendor, or staff with `payments`.
  Future<Map<String, dynamic>> vendorTaxProfile() async =>
      await _request('GET', '/vendor/tax-profile');

  /// Saves my tax details (vendor account only; staff get 403 owner_only).
  Future<Map<String, dynamic>> vendorSaveTaxProfile(
    Map<String, dynamic> body,
  ) async => await _request('PUT', '/vendor/tax-profile', body: body);

  /// The VAT codes a product may use: `{asOf, codes: [{code, nameEn,
  /// nameSw, exempt, ratePct}]}`.
  Future<Map<String, dynamic>> vendorTaxRates() async =>
      await _request('GET', '/vendor/tax-rates');

  // ── Vendor reports (S6, fitflex-functions#275) ──────────────────────────

  /// The report sections the server answers (GET /vendor/reports/{section}).
  static const vendorReportSections = {
    'summary',
    'sales',
    'products',
    'stock-value',
    'profit',
    'marketplace-net',
    'customers',
    'payment-methods',
  };

  /// One report as JSON. [query] carries `from` / `to` (EAT dates, both or
  /// neither), `channel` (all | app | walk_in), `groupBy`, `sort`, `q`,
  /// `limit`, `cursor`; empty values are left out. Errors come back as
  /// [ApiException]: 400 `invalid_range` {reason}, `too_many_buckets`,
  /// 403 `cost_not_allowed` / `payout_not_allowed` /
  /// `vendor_permission_forbidden`, 404 `feature_disabled`.
  Future<Map<String, dynamic>> vendorReport(
    String section, {
    Map<String, String?> query = const {},
  }) async {
    assert(vendorReportSections.contains(section));
    return Map<String, dynamic>.from(
      await _request(
            'GET',
            _withQuery('/vendor/reports/${_seg(section)}', {
              for (final e in query.entries)
                if ((e.value ?? '').isNotEmpty) e.key: e.value!,
              'format': 'json',
            }),
          )
          as Map,
    );
  }

  /// A report as a file: `csv` (every section but the summary) or `pdf`
  /// (summary only), headers in [lang]. 413 `export_too_large`, 503
  /// `pdf_unavailable`.
  Future<({Uint8List bytes, String? fileName})> vendorReportFile(
    String section, {
    required String format,
    required String lang,
    Map<String, String?> query = const {},
  }) {
    assert(vendorReportSections.contains(section));
    return _binary(
      _withQuery('/vendor/reports/${_seg(section)}', {
        for (final e in query.entries)
          if ((e.value ?? '').isNotEmpty) e.key: e.value!,
        'format': format,
        'lang': lang,
      }),
    );
  }

  /// A binary answer (a PDF) with its file name from Content-Disposition.
  Future<({Uint8List bytes, String? fileName})> _binary(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    _log.request('GET', uri, const {}, null);
    final res = await http
        .get(
          uri,
          headers: {
            'x-fitflex-client': kIdentityV2Client,
            if (_token != null) 'authorization': 'Bearer $_token',
          },
        )
        .timeout(const Duration(seconds: 30));
    _log.response(
      'GET',
      uri,
      res.statusCode,
      '<${res.bodyBytes.length} bytes>',
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final disposition = res.headers['content-disposition'] ?? '';
      final name = RegExp(r'filename="?([^";]+)"?').firstMatch(disposition);
      return (bytes: res.bodyBytes, fileName: name?.group(1));
    }
    if (res.statusCode == 401 && onUnauthorized != null) onUnauthorized!();
    throw ApiException(res.statusCode, _decodeErrorBody(res.body));
  }

  /// My invoices for a paid shop order, one per seller (S5):
  /// `{invoices: [doc + vendorId]}`. 404 `feature_disabled` while documents
  /// are off; 404 `invoice_not_ready` until the order is paid.
  Future<Map<String, dynamic>> myShopOrderInvoices(
    String orderId, {
    String? lang,
  }) async => await _request(
    'GET',
    _withQuery('/me/shop-orders/${_seg(orderId)}/invoice', {
      'format': 'json',
      'lang': ?lang,
    }),
  );

  /// One seller's invoice for my order as a PDF.
  Future<({Uint8List bytes, String? fileName})> myShopOrderInvoicePdf(
    String orderId, {
    required String vendorId,
    String? lang,
  }) => _binary(
    _withQuery('/me/shop-orders/${_seg(orderId)}/invoice', {
      'format': 'pdf',
      'vendorId': vendorId,
      'lang': ?lang,
    }),
  );

  /// Products and variants at or below their reorder level.
  Future<List<dynamic>> vendorLowStock() async =>
      await _request('GET', '/vendor/stock/low');

  Future<List<dynamic>> vendorOrders() async =>
      await _request('GET', '/vendor/orders');

  Future<Map<String, dynamic>> vendorUpdateOrderStatus(
    String orderId,
    String status,
  ) async => await _request(
    'POST',
    '/vendor/orders/$orderId/status',
    body: {'status': status},
  );

  Future<Map<String, dynamic>> vendorProfile() async =>
      await _request('GET', '/vendor/profile');

  Future<Map<String, dynamic>> vendorSaveProfile(
    Map<String, dynamic> data,
  ) async => await _request('PUT', '/vendor/profile', body: data);

  Future<Map<String, dynamic>> vendorDuplicateProduct(String productId) async =>
      await _request('POST', '/vendor/products/$productId/duplicate');

  Future<Map<String, dynamic>> vendorDeleteProduct(String productId) async =>
      await _request('DELETE', '/vendor/products/$productId');

  Future<Map<String, dynamic>> vendorPayments() async =>
      await _request('GET', '/vendor/payments');

  Future<String> vendorStatement() async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/vendor/payments/statement'),
          headers: {if (_token != null) 'authorization': 'Bearer $_token'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }
    throw ApiException(response.statusCode, response.body);
  }

  Future<List<dynamic>> vendorEnquiries({
    String? search,
  }) async => await _request(
    'GET',
    search == null || search.trim().isEmpty
        ? '/vendor/enquiries'
        : '/vendor/enquiries?search=${Uri.encodeQueryComponent(search.trim())}',
  );

  Future<Map<String, dynamic>> vendorReplyEnquiry(
    String enquiryId,
    String message,
  ) async => await _request(
    'POST',
    '/vendor/enquiries/$enquiryId/reply',
    body: {'message': message},
  );

  Future<Map<String, dynamic>> vendorResolveEnquiry(String enquiryId) async =>
      await _request('POST', '/vendor/enquiries/$enquiryId/resolve');

  Future<List<dynamic>> vendorStaff() async =>
      await _request('GET', '/vendor/staff');

  Future<Map<String, dynamic>> vendorCreateStaff(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/vendor/staff', body: data);

  Future<Map<String, dynamic>> vendorDisableStaff(String staffId) async =>
      await _request('POST', '/vendor/staff/$staffId/disable');

  Future<Map<String, dynamic>> trainerApplyToGym(String gymId) async =>
      await _request('POST', '/trainer/gyms/$gymId/apply');

  Future<Map<String, dynamic>> trainerCancelGymApplication(
    String gymId,
  ) async => await _request('POST', '/trainer/gyms/$gymId/apply/cancel');

  Future<Map<String, dynamic>> gymOwnerRegister(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/gym-owner/register', body: data);

  // Owner APIs
  Future<List<dynamic>> ownerGyms() async =>
      await _request('GET', '/owner/gyms');

  Future<Map<String, dynamic>> ownerUpdateGym(
    String gymId,
    Map<String, dynamic> data,
  ) async => await _request('PUT', '/owner/gyms/$gymId', body: data);

  Future<List<dynamic>> ownerTrainers({String? gymId}) async {
    final path = (gymId != null && gymId.isNotEmpty)
        ? '/owner/trainers?${Uri(queryParameters: {'gymId': gymId}).query}'
        : '/owner/trainers';
    return await _request('GET', path);
  }

  Future<List<dynamic>> ownerPendingTrainers() async =>
      await _request('GET', '/owner/trainers/pending');

  Future<Map<String, dynamic>> ownerDecideTrainerJoin(
    String trainerId, {
    required String gymId,
    required String decision,
  }) async => await _request(
    'POST',
    '/owner/trainers/$trainerId/decision',
    body: {'gymId': gymId, 'decision': decision},
  );

  Future<Map<String, dynamic>> ownerEarnings({String? gymId}) async {
    final path = (gymId != null && gymId.isNotEmpty)
        ? '/owner/earnings?${Uri(queryParameters: {'gymId': gymId}).query}'
        : '/owner/earnings';
    return await _request('GET', path);
  }

  Future<List<dynamic>> ownerInvoices() async =>
      await _request('GET', '/owner/invoices');

  /// The gym's monthly FitFlex statements, newest first.
  Future<List<dynamic>> ownerSettlements({String? gymId}) async {
    final path = (gymId != null && gymId.isNotEmpty)
        ? '/owner/settlements?${Uri(queryParameters: {'gymId': gymId}).query}'
        : '/owner/settlements';
    return await _request('GET', path);
  }

  /// One statement with its member lines and applied adjustments.
  Future<Map<String, dynamic>> ownerSettlement(String id) async =>
      await _request('GET', '/owner/settlements/${Uri.encodeComponent(id)}');

  Future<List<dynamic>> ownerGymCheckins(String gymId) async =>
      await _request('GET', '/owner/gyms/$gymId/checkins');

  Future<Map<String, dynamic>> operatorDashboard({
    String? gymId,
    String? periodStart,
    String? periodEnd,
    String? memberType,
  }) async {
    final query = <String, String>{
      if (gymId != null && gymId.isNotEmpty) 'gymId': gymId,
      if (periodStart != null && periodStart.isNotEmpty)
        'periodStart': periodStart,
      if (periodEnd != null && periodEnd.isNotEmpty) 'periodEnd': periodEnd,
      if (memberType != null && memberType.isNotEmpty) 'memberType': memberType,
    };
    final path = query.isEmpty
        ? '/operator/dashboard'
        : '/operator/dashboard?${Uri(queryParameters: query).query}';
    return await _request('GET', path);
  }

  Future<Map<String, dynamic>> operatorVerifyQr(
    String qrToken, {
    String? gymId,
  }) async {
    final body = <String, dynamic>{'qrToken': qrToken};
    if (gymId != null) body['gymId'] = gymId;
    return await _request('POST', '/operator/verify-qr', body: body);
  }

  Future<Map<String, dynamic>> operatorCheckIn(
    String qrToken, {
    String? gymId,
  }) async {
    final body = <String, dynamic>{'qrToken': qrToken};
    if (gymId != null) body['gymId'] = gymId;
    return await _request('POST', '/operator/checkins', body: body);
  }

  // Owner gym CRUD
  Future<Map<String, dynamic>> ownerCreateGym(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/owner/gyms', body: data);

  Future<void> ownerDeleteGym(String gymId) async =>
      await _request('POST', '/owner/gyms/$gymId/delete');

  // Owner trainer management
  Future<Map<String, dynamic>> ownerCreateTrainer(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/owner/trainers', body: data);

  Future<void> ownerRemoveTrainer(String trainerId) async =>
      await _request('POST', '/owner/trainers/$trainerId/remove');

  Future<Map<String, dynamic>> ownerCreateMember(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/owner/members', body: data);

  Future<Map<String, dynamic>> ownerUpdateMember(
    String memberId,
    Map<String, dynamic> data,
  ) async => await _request('PATCH', '/owner/members/$memberId', body: data);

  // Owner member management
  Future<Map<String, dynamic>> ownerMembers({
    String? gymId,
    String? memberType,
    String? status,
    String? search,
  }) async {
    final query = <String, String>{
      if (gymId != null && gymId.isNotEmpty) 'gymId': gymId,
      if (memberType != null && memberType.isNotEmpty && memberType != 'all')
        'memberType': memberType,
      if (status != null && status.isNotEmpty && status != 'all')
        'status': status,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final path = query.isEmpty
        ? '/owner/members'
        : '/owner/members?${Uri(queryParameters: query).query}';
    return await _request('GET', path);
  }

  Future<Map<String, dynamic>> ownerMemberDetail(String memberId) async =>
      await _request('GET', '/owner/members/$memberId');

  Future<Map<String, dynamic>> ownerMemberCheckInSummary(
    String memberId, {
    String? period,
    String? from,
    String? to,
  }) async {
    final query = <String, String>{
      if (period != null && period.isNotEmpty) 'period': period,
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
    };
    final path = query.isEmpty
        ? '/owner/members/$memberId/checkin-summary'
        : '/owner/members/$memberId/checkin-summary?${Uri(queryParameters: query).query}';
    return await _request('GET', path);
  }

  Future<Map<String, dynamic>> ownerMemberCheckins(
    String memberId, {
    int? cursor,
    int? limit,
    String? from,
    String? to,
    String? search,
  }) async {
    final query = <String, String>{
      if (cursor != null) 'cursor': '$cursor',
      if (limit != null) 'limit': '$limit',
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final path = query.isEmpty
        ? '/owner/members/$memberId/checkins'
        : '/owner/members/$memberId/checkins?${Uri(queryParameters: query).query}';
    return await _request('GET', path);
  }

  Future<Map<String, dynamic>> ownerMemberPayments(
    String memberId, {
    int? cursor,
    int? limit,
    String? from,
    String? to,
    String? search,
  }) async {
    final query = <String, String>{
      if (cursor != null) 'cursor': '$cursor',
      if (limit != null) 'limit': '$limit',
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final path = query.isEmpty
        ? '/owner/members/$memberId/payments'
        : '/owner/members/$memberId/payments?${Uri(queryParameters: query).query}';
    return await _request('GET', path);
  }

  Future<Map<String, dynamic>> ownerCheckInMember(
    String memberId, {
    String? gymId,
  }) async => await _request(
    'POST',
    '/owner/members/$memberId/checkin',
    body: {'gymId': ?gymId},
  );

  Future<Map<String, dynamic>> ownerRenewMember(
    String memberId,
    Map<String, dynamic> data,
  ) async =>
      await _request('POST', '/owner/members/$memberId/renew', body: data);

  Future<Map<String, dynamic>> ownerSuspendMember(
    String memberId, {
    required bool suspend,
  }) async => await _request(
    'POST',
    '/owner/members/$memberId/suspend',
    body: {'suspend': suspend},
  );

  // Subscription tiers
  Future<List<dynamic>> subscriptionTiers() async =>
      await _request('GET', '/subscription-tiers');

  // Gym staff roster (RBAC) — owner only
  Future<List<dynamic>> ownerStaff() async =>
      await _request('GET', '/owner/staff');

  Future<Map<String, dynamic>> ownerCreateStaff(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/owner/staff', body: data);

  Future<Map<String, dynamic>> ownerUpdateStaff(
    String id,
    Map<String, dynamic> data,
  ) async => await _request('PUT', '/owner/staff/$id', body: data);

  Future<void> ownerRemoveStaff(String id) async =>
      await _request('POST', '/owner/staff/$id/remove');

  /// Owner: give a staff member a new start PIN (fitflex-functions#260).
  /// Returns the staff row with `passwordChangeRequired: true`; the staff
  /// member is signed out and must choose their own PIN at next sign-in.
  Future<Map<String, dynamic>> ownerResetStaffPin(
    String id,
    String pin,
  ) async => await _request(
    'POST',
    '/owner/staff/${Uri.encodeComponent(id)}/pin',
    body: {'pin': pin},
  );

  // ── Owner communications (messages to the gym's direct members) ─────────

  static final _discoverSession = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

  // ── Events (Marathon & Running Events S2, member discovery) ──────────────
  // docs/design/events-s2-organizer-and-discovery.md §13, §14.1, §14.2,
  // §14.5. Paths, query names and fields are the server's; nothing is
  // invented here.

  /// Public probe: `{discovery, favourites, registration, currency,
  /// closingSoonHours, regions, timezones}`. Answers even while the server
  /// module is off (`discovery: false`); the caller treats a 404 or a
  /// network error as "off".
  Future<Map<String, dynamic>> eventsOptions() async {
    final out = await _request('GET', '/events/options');
    return out is Map ? Map<String, dynamic>.from(out) : <String, dynamic>{};
  }

  /// One page of published events: `{items, nextCursor, total?}`.
  /// [query] holds the filter's parameters (repeated keys as lists, e.g.
  /// `type`, `distance`); [cursor] is the previous page's `nextCursor`;
  /// every call carries `limit`.
  Future<Map<String, dynamic>> listEvents(
    Map<String, List<String>> query, {
    String? cursor,
    int limit = 20,
  }) async {
    final params = <String, dynamic>{
      for (final e in query.entries)
        if (e.value.isNotEmpty)
          e.key: e.value.length == 1 ? e.value.single : e.value,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      'limit': '$limit',
    };
    final out = await _request(
      'GET',
      '/events?${Uri(queryParameters: params).query}',
    );
    if (out is List) return {'items': out, 'nextCursor': null};
    return out is Map ? Map<String, dynamic>.from(out) : <String, dynamic>{};
  }

  /// One event by id (or slug). 404 `event_not_found` for anything not
  /// published to this caller; 404 `feature_disabled` while the module is off.
  Future<Map<String, dynamic>> getEvent(String eventId) async {
    final out = await _request(
      'GET',
      '/events/${Uri.encodeComponent(eventId)}',
    );
    return Map<String, dynamic>.from(out as Map);
  }

  /// Saves an event (favourites flag, §14.5). 204.
  Future<void> saveEvent(String eventId) async => await _request(
    'PUT',
    '/me/event-favourites/${Uri.encodeComponent(eventId)}',
    body: const <String, dynamic>{},
  );

  /// Removes a saved event. 204.
  Future<void> unsaveEvent(String eventId) async => await _request(
    'DELETE',
    '/me/event-favourites/${Uri.encodeComponent(eventId)}',
  );

  // ── Events S3: registration, orders, claims, teams ───────────────────────
  // docs/design/events-s3-registration-and-orders.md §3.4–§3.9. Every
  // route 404s `feature_disabled` while EVENTS_REGISTRATION is off.

  /// Prices and checks an order without holding anything (§3.4).
  Future<Map<String, dynamic>> quoteEventOrder(
    Map<String, dynamic> body,
  ) async => Map<String, dynamic>.from(
    await _request('POST', '/me/event-orders/quote', body: body) as Map,
  );

  /// Places an order and holds its places (§3.5). [idempotencyKey] makes a
  /// retry return the same order; [body] is the quote body plus
  /// `acceptedTerms`, `consentTextVersion` and `expectedTotalTzs`.
  Future<Map<String, dynamic>> createEventOrder(
    Map<String, dynamic> body, {
    required String idempotencyKey,
  }) async => Map<String, dynamic>.from(
    await _request(
          'POST',
          '/me/event-orders',
          extraHeaders: {'Idempotency-Key': idempotencyKey},
          body: body,
        )
        as Map,
  );

  /// My orders, newest first: `{items, nextCursor}` (§3.6).
  Future<Map<String, dynamic>> listEventOrders({
    String? status,
    String? cursor,
    int limit = 20,
  }) async => Map<String, dynamic>.from(
    await _request(
          'GET',
          _withQuery('/me/event-orders', {
            if (status != null && status.isNotEmpty) 'status': status,
            if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
            'limit': '$limit',
          }),
        )
        as Map,
  );

  Future<Map<String, dynamic>> getEventOrder(String orderId) async =>
      Map<String, dynamic>.from(
        await _request(
              'GET',
              '/me/event-orders/${Uri.encodeComponent(orderId)}',
            )
            as Map,
      );

  /// Cancels an order; [reason] from the closed set (§3.8). For a paid
  /// order (events S4 §3.12.2) [expectedRefundTzs] is the refund the member
  /// was shown: the server only compares it with a fresh evaluation (409
  /// `refund_changed`), it never sets the amount.
  Future<Map<String, dynamic>> cancelEventOrder(
    String orderId, {
    required String reason,
    int? expectedRefundTzs,
  }) async => Map<String, dynamic>.from(
    await _request(
          'POST',
          '/me/event-orders/${Uri.encodeComponent(orderId)}/cancel',
          body: {'reason': reason, 'expectedRefundTzs': ?expectedRefundTzs},
        )
        as Map,
  );

  /// Places I bought or hold: `{items, nextCursor}` (§3.6).
  Future<Map<String, dynamic>> listEventRegistrations({
    String? cursor,
    int limit = 20,
  }) async => Map<String, dynamic>.from(
    await _request(
          'GET',
          _withQuery('/me/event-registrations', {
            if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
            'limit': '$limit',
          }),
        )
        as Map,
  );

  Future<Map<String, dynamic>> getEventRegistration(String id) async =>
      Map<String, dynamic>.from(
        await _request(
              'GET',
              '/me/event-registrations/${Uri.encodeComponent(id)}',
            )
            as Map,
      );

  /// Removes one place from an unpaid order (§3.8, D17), or cancels a paid
  /// place (S4 §3.12.2; then [expectedRefundTzs] is required by the server).
  Future<Map<String, dynamic>> cancelEventRegistration(
    String id, {
    required String reason,
    int? expectedRefundTzs,
  }) async => Map<String, dynamic>.from(
    await _request(
          'POST',
          '/me/event-registrations/${Uri.encodeComponent(id)}/cancel',
          body: {'reason': reason, 'expectedRefundTzs': ?expectedRefundTzs},
        )
        as Map,
  );

  /// Unclaimed places whose contact matches one of my verified contacts.
  Future<Map<String, dynamic>> claimableEventRegistrations() async =>
      Map<String, dynamic>.from(
        await _request('GET', '/me/event-registrations/claimable') as Map,
      );

  /// Masked preview of a claim link (public, §3.7).
  Future<Map<String, dynamic>> previewEventClaim(String token) async =>
      Map<String, dynamic>.from(
        await _request(
              'GET',
              '/event-claims/preview/${Uri.encodeComponent(token)}',
            )
            as Map,
      );

  /// Claims a place found in-app (`claimable`), by id (§3.7).
  Future<Map<String, dynamic>> claimEventRegistration(String id) async =>
      Map<String, dynamic>.from(
        await _request(
              'POST',
              '/me/event-registrations/${Uri.encodeComponent(id)}/claim',
              body: const <String, dynamic>{},
            )
            as Map,
      );

  /// Claims the place a link token resolves to (§5.11 alias; the preview
  /// returns no id).
  Future<Map<String, dynamic>> claimEventRegistrationByToken(
    String token,
  ) async => Map<String, dynamic>.from(
    await _request(
          'POST',
          '/me/event-registrations/claim',
          body: {'token': token},
        )
        as Map,
  );

  // ── Events S4: payments, tickets, refunds ────────────────────────────────
  // docs/design/events-s4-payments-and-tickets.md §3.4–§3.12. Payment intake
  // needs the server's payment flags; tickets, cancel and refunds need only
  // EVENTS_REGISTRATION so a member who paid is never stranded.

  /// Starts a payment for an awaiting order (§3.4.1). The body depends on
  /// the server's mode and never carries an amount, currency or provider:
  /// `{reference, payerPhone}` for `manual`, `{}` for `provider`.
  /// [idempotencyKey] is required; a replay returns the first payment.
  Future<Map<String, dynamic>> payEventOrder(
    String orderId, {
    required Map<String, dynamic> body,
    required String idempotencyKey,
  }) async => Map<String, dynamic>.from(
    await _request(
          'POST',
          '/me/event-orders/${Uri.encodeComponent(orderId)}/payment',
          extraHeaders: {'Idempotency-Key': idempotencyKey},
          body: body,
        )
        as Map,
  );

  /// The order's payment and refund state, cheap enough to poll (§3.5).
  Future<Map<String, dynamic>> eventPaymentStatus(String orderId) async =>
      Map<String, dynamic>.from(
        await _request(
              'GET',
              '/me/event-orders/${Uri.encodeComponent(orderId)}/payment-status',
            )
            as Map,
      );

  /// My tickets, soonest event first: `{items, nextCursor}` (§3.8.4). No
  /// token is in the list.
  Future<Map<String, dynamic>> listEventTickets({
    String? cursor,
    int limit = 20,
  }) async => Map<String, dynamic>.from(
    await _request(
          'GET',
          _withQuery('/me/event-tickets', {
            if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
            'limit': '$limit',
          }),
        )
        as Map,
  );

  /// One ticket with its QR payload (§3.8.4). 404 `registration_not_found`
  /// when the caller has no right to see it; 409 `ticket_revoked {reason}`.
  Future<Map<String, dynamic>> getEventTicket(
    String registrationId,
  ) async => Map<String, dynamic>.from(
    await _request(
          'GET',
          '/me/event-registrations/${Uri.encodeComponent(registrationId)}/ticket',
        )
        as Map,
  );

  /// Replaces the ticket code; the old one stops working (§3.8.3).
  Future<Map<String, dynamic>> rotateEventTicket(
    String registrationId,
  ) async => Map<String, dynamic>.from(
    await _request(
          'POST',
          '/me/event-registrations/${Uri.encodeComponent(registrationId)}/ticket/rotate',
          body: const <String, dynamic>{},
        )
        as Map,
  );

  /// What cancelling one paid place would refund (§3.12.2). Read-only.
  Future<Map<String, dynamic>> eventRegistrationCancelPreview(
    String registrationId,
  ) async => Map<String, dynamic>.from(
    await _request(
          'GET',
          '/me/event-registrations/${Uri.encodeComponent(registrationId)}/cancel-preview',
        )
        as Map,
  );

  /// What cancelling a whole paid order would refund (§3.12.2). Read-only.
  Future<Map<String, dynamic>> eventOrderCancelPreview(String orderId) async =>
      Map<String, dynamic>.from(
        await _request(
              'GET',
              '/me/event-orders/${Uri.encodeComponent(orderId)}/cancel-preview',
            )
            as Map,
      );

  /// Sends the claim invitation for an unclaimed place again (§3.10); this
  /// makes a new link and the old one stops working.
  Future<Map<String, dynamic>> resendEventClaimInvitation(
    String orderId, {
    required String registrationId,
  }) async => Map<String, dynamic>.from(
    await _request(
          'POST',
          '/me/event-orders/${Uri.encodeComponent(orderId)}/claim-invitations',
          body: {'registrationId': registrationId},
        )
        as Map,
  );

  /// Creates a team for an event (§3.9): `{team}` with its join code.
  Future<Map<String, dynamic>> createEventTeam({
    required String eventId,
    required String name,
    required String teamType,
  }) async => Map<String, dynamic>.from(
    await _request(
          'POST',
          '/me/event-teams',
          body: {'eventId': eventId, 'name': name, 'teamType': teamType},
        )
        as Map,
  );

  /// Finds a team by join code before an order joins it (§3.9).
  Future<Map<String, dynamic>> lookupEventTeam({
    required String eventId,
    required String joinCode,
  }) async => Map<String, dynamic>.from(
    await _request(
          'POST',
          '/me/event-teams/lookup',
          body: {'eventId': eventId, 'joinCode': joinCode},
        )
        as Map,
  );

  Future<Map<String, dynamic>> getEventTeam(String teamId) async =>
      Map<String, dynamic>.from(
        await _request('GET', '/me/event-teams/${Uri.encodeComponent(teamId)}')
            as Map,
      );

  // ── Events S6: runs, results, medals, rewards ────────────────────────────
  // docs/design/events-s6-runs-results-medals-rewards.md §8.3. Every route
  // 404s `feature_disabled` while its flag is off; the writes carry an
  // Idempotency-Key (or, for the run, the `clientRef` in the body).

  static String _reg(String id) => Uri.encodeComponent(id);

  /// The member's result for one registration (§8.3).
  Future<Map<String, dynamic>> getMyEventResult(String registrationId) async =>
      Map<String, dynamic>.from(
        await _request(
              'GET',
              '/me/event-registrations/${_reg(registrationId)}/result',
            )
            as Map,
      );

  /// My own results across events, newest first: `{items, nextCursor}`.
  Future<Map<String, dynamic>> listMyEventResults({String? cursor}) async =>
      Map<String, dynamic>.from(
        await _request(
              'GET',
              _withQuery('/me/event-results', {
                if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
              }),
            )
            as Map,
      );

  /// Records the finished run and adds it to the event in one step. The same
  /// [body] with the same `clientRef` returns the first answer.
  Future<Map<String, dynamic>> recordEventRun(
    String registrationId,
    Map<String, dynamic> body,
  ) async => Map<String, dynamic>.from(
    await _request(
          'POST',
          '/me/event-registrations/${_reg(registrationId)}/runs',
          body: body,
        )
        as Map,
  );

  /// Adds a run the member already recorded in FitFlex.
  Future<Map<String, dynamic>> linkEventRun(
    String registrationId,
    String activityId, {
    required String idempotencyKey,
  }) async => Map<String, dynamic>.from(
    await _request(
          'POST',
          '/me/event-registrations/${_reg(registrationId)}/run-links',
          extraHeaders: {'Idempotency-Key': idempotencyKey},
          body: {'activityId': activityId},
        )
        as Map,
  );

  Future<Map<String, dynamic>> listEventRunLinks(String registrationId) async =>
      Map<String, dynamic>.from(
        await _request(
              'GET',
              '/me/event-registrations/${_reg(registrationId)}/run-links',
            )
            as Map,
      );

  Future<void> unlinkEventRun(
    String registrationId,
    String linkId,
  ) async => await _request(
    'DELETE',
    '/me/event-registrations/${_reg(registrationId)}/run-links/${_reg(linkId)}',
  );

  /// `standard` | `bib_only` | `hidden`.
  Future<Map<String, dynamic>> setEventResultsVisibility(
    String registrationId,
    String visibility,
  ) async => Map<String, dynamic>.from(
    await _request(
          'PUT',
          '/me/event-registrations/${_reg(registrationId)}/results-visibility',
          body: {'visibility': visibility},
        )
        as Map,
  );

  Future<Map<String, dynamic>> raiseEventResultDispute(
    String registrationId, {
    required String reasonCode,
    String? note,
    required String idempotencyKey,
  }) async => Map<String, dynamic>.from(
    await _request(
          'POST',
          '/me/event-registrations/${_reg(registrationId)}/result/disputes',
          extraHeaders: {'Idempotency-Key': idempotencyKey},
          body: {
            'reasonCode': reasonCode,
            if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
          },
        )
        as Map,
  );

  Future<void> withdrawEventResultDispute(
    String registrationId,
    String disputeId,
  ) async => await _request(
    'DELETE',
    '/me/event-registrations/${_reg(registrationId)}/result/disputes/${_reg(disputeId)}',
  );

  /// The signed-in results board (§8.3).
  Future<Map<String, dynamic>> eventResultsBoard(
    String eventId, {
    String? categoryId,
    String? q,
    String? cursor,
    int limit = 50,
  }) async => Map<String, dynamic>.from(
    await _request(
          'GET',
          _withQuery('/events/${_reg(eventId)}/results', {
            if ((categoryId ?? '').isNotEmpty) 'categoryId': categoryId!,
            if ((q ?? '').trim().isNotEmpty) 'q': q!.trim(),
            if ((cursor ?? '').isNotEmpty) 'cursor': cursor!,
            'limit': '$limit',
          }),
        )
        as Map,
  );

  /// Medals, achievements and removed ones.
  Future<Map<String, dynamic>> myEventAchievements() async =>
      Map<String, dynamic>.from(
        await _request('GET', '/me/achievements') as Map,
      );

  Future<Map<String, dynamic>> myEventRewardLedger({String? cursor}) async =>
      Map<String, dynamic>.from(
        await _request(
              'GET',
              _withQuery('/me/reward-ledger', {
                if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
              }),
            )
            as Map,
      );

  /// The rewards wallet.
  Future<Map<String, dynamic>> myEventRewards() async =>
      Map<String, dynamic>.from(
        await _request('GET', '/me/event-rewards') as Map,
      );

  /// Claims one unit of a reward. [idempotencyKey] makes a retry safe.
  Future<Map<String, dynamic>> claimEventReward(
    String definitionId, {
    required String idempotencyKey,
  }) async => Map<String, dynamic>.from(
    await _request(
          'POST',
          '/me/reward-redemptions',
          extraHeaders: {'Idempotency-Key': idempotencyKey},
          body: {'rewardDefinitionId': definitionId},
        )
        as Map,
  );

  Future<Map<String, dynamic>> getEventRewardRedemption(String id) async =>
      Map<String, dynamic>.from(
        await _request('GET', '/me/reward-redemptions/${_reg(id)}') as Map,
      );

  /// Organizer medal artwork as WebP bytes. The route needs the member's
  /// sign-in, so the picture is fetched here (never as a remote URL) and
  /// drawn from memory. 404 means "taken down or not yours": use the
  /// built-in design.
  Future<Uint8List> eventMedalArtFile(
    String artId, {
    String variant = 'm256',
  }) async {
    final uri = Uri.parse(
      '$baseUrl/events/medal-art/${_reg(artId)}/file'
      '?variant=${Uri.encodeQueryComponent(variant)}',
    );
    final res = await http
        .get(
          uri,
          headers: {
            'x-fitflex-client': kIdentityV2Client,
            if (_token != null) 'authorization': 'Bearer $_token',
          },
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    if (res.statusCode == 401 && onUnauthorized != null) onUnauthorized!();
    throw ApiException(res.statusCode, _decodeErrorBody(res.body));
  }

  static String _withQuery(String path, Map<String, String> query) =>
      query.isEmpty ? path : '$path?${Uri(queryParameters: query).query}';

  Future<Map<String, dynamic>> ownerCommunicationOverview({
    String? gymId,
  }) async => await _request(
    'GET',
    _withQuery('/owner/communications/overview', {
      if (gymId != null && gymId.isNotEmpty) 'gymId': gymId,
    }),
  );

  Future<Map<String, dynamic>> ownerCampaigns({
    String? gymId,
    String? status,
  }) async => await _request(
    'GET',
    _withQuery('/owner/communications/campaigns', {
      if (gymId != null && gymId.isNotEmpty) 'gymId': gymId,
      if (status != null && status.isNotEmpty) 'status': status,
    }),
  );

  Future<Map<String, dynamic>> ownerCampaign(String id) async =>
      await _request('GET', '/owner/communications/campaigns/$id');

  /// Who a campaign went to, one row per member (history).
  Future<Map<String, dynamic>> ownerCampaignRecipients(
    String id, {
    Map<String, String> query = const {},
  }) async => await _request(
    'GET',
    _withQuery('/owner/communications/campaigns/$id/recipients', query),
  );

  /// A member's communications from the owner's gyms, newest first.
  Future<Map<String, dynamic>> ownerMemberCommunications(
    String memberId, {
    Map<String, String> query = const {},
  }) async => await _request(
    'GET',
    _withQuery('/owner/members/$memberId/communications', query),
  );

  /// Results over the last [days]: totals and each campaign / automation.
  Future<Map<String, dynamic>> ownerCommunicationAnalytics({
    int days = 30,
    String? gymId,
  }) async => await _request(
    'GET',
    _withQuery('/owner/communications/analytics', {
      'days': '$days',
      'gymId': ?gymId,
    }),
  );

  Future<Map<String, dynamic>> ownerCampaignAnalytics(String id) async =>
      await _request('GET', '/owner/communications/campaigns/$id/analytics');

  Future<Map<String, dynamic>> ownerAutomationAnalytics(
    String id, {
    int days = 30,
  }) async => await _request(
    'GET',
    _withQuery('/owner/communications/automations/$id/analytics', {
      'days': '$days',
    }),
  );

  /// The gym's lifecycle automations (created switched off on first look).
  Future<Map<String, dynamic>> ownerAutomations({String? gymId}) async =>
      await _request(
        'GET',
        _withQuery('/owner/communications/automations', {'gymId': ?gymId}),
      );

  /// Switch on/off, channels or template. PATCH { status?, channels?, templateId? }
  Future<Map<String, dynamic>> ownerUpdateAutomation(
    String id,
    Map<String, dynamic> body,
  ) async => await _request(
    'PATCH',
    '/owner/communications/automations/$id',
    body: body,
  );

  Future<Map<String, dynamic>> ownerAutomationRuns(String id) async =>
      await _request('GET', '/owner/communications/automations/$id/runs');

  Future<Map<String, dynamic>> ownerAutomationPreview(String id) async =>
      await _request('POST', '/owner/communications/automations/$id/preview');

  /// One message in full: status, times, failure, provider reference.
  Future<Map<String, dynamic>> ownerCommunicationMessage(String id) async =>
      await _request('GET', '/owner/communications/messages/$id');

  /// Audience count and a few names. POST { gymId?, preset?, filter?, purpose? }
  Future<Map<String, dynamic>> ownerAudiencePreview(
    Map<String, dynamic> body,
  ) async => await _request(
    'POST',
    '/owner/communications/audience/preview',
    body: body,
  );

  /// Reach per channel, a real member's message and warnings, unsaved.
  Future<Map<String, dynamic>> ownerPreviewCampaignDraft(
    Map<String, dynamic> body,
  ) async => await _request(
    'POST',
    '/owner/communications/campaigns/preview',
    body: body,
  );

  Future<Map<String, dynamic>> ownerCreateCampaign(
    Map<String, dynamic> body,
  ) async =>
      await _request('POST', '/owner/communications/campaigns', body: body);

  Future<Map<String, dynamic>> ownerUpdateCampaign(
    String id,
    Map<String, dynamic> body,
  ) async => await _request(
    'PATCH',
    '/owner/communications/campaigns/$id',
    body: body,
  );

  Future<void> ownerDeleteCampaign(String id) async =>
      await _request('DELETE', '/owner/communications/campaigns/$id');

  Future<Map<String, dynamic>> ownerScheduleCampaign(
    String id,
    String scheduledAtIso, {
    bool confirmLargeSend = false,
  }) async => await _request(
    'POST',
    '/owner/communications/campaigns/$id/schedule',
    body: {
      'scheduledAt': scheduledAtIso,
      if (confirmLargeSend) 'confirmLargeSend': true,
    },
  );

  Future<Map<String, dynamic>> ownerUnscheduleCampaign(String id) async =>
      await _request('POST', '/owner/communications/campaigns/$id/unschedule');

  Future<Map<String, dynamic>> ownerCancelCampaign(String id) async =>
      await _request('POST', '/owner/communications/campaigns/$id/cancel');

  /// Copies any campaign into a new draft (same audience, message and
  /// channels); the audience is worked out again when the copy is sent.
  Future<Map<String, dynamic>> ownerDuplicateCampaign(String id) async =>
      await _request('POST', '/owner/communications/campaigns/$id/duplicate');

  /// Send now. Repeating the same [sendRequestId] never sends twice.
  Future<Map<String, dynamic>> ownerSendCampaign(
    String id, {
    required String sendRequestId,
    bool confirmLargeSend = false,
  }) async => await _request(
    'POST',
    '/owner/communications/campaigns/$id/send',
    body: {
      'sendRequestId': sendRequestId,
      if (confirmLargeSend) 'confirmLargeSend': true,
    },
  );

  // ── Owner message templates ─────────────────────────────────────────────

  Future<Map<String, dynamic>> ownerTemplates({
    String? gymId,
    String? group,
  }) async => await _request(
    'GET',
    _withQuery('/owner/communications/templates', {
      if (gymId != null && gymId.isNotEmpty) 'gymId': gymId,
      if (group != null && group.isNotEmpty) 'group': group,
    }),
  );

  Future<Map<String, dynamic>> ownerTemplate(String id) async =>
      await _request('GET', '/owner/communications/templates/$id');

  /// How a template looks on each channel in each language.
  Future<Map<String, dynamic>> ownerTemplatePreview(
    String id, {
    String? gymId,
    Map<String, dynamic>? values,
  }) async => await _request(
    'POST',
    '/owner/communications/templates/$id/preview',
    body: {'gymId': ?gymId, 'values': ?values},
  );

  Future<Map<String, dynamic>> ownerCreateTemplate(
    Map<String, dynamic> body,
  ) async =>
      await _request('POST', '/owner/communications/templates', body: body);

  Future<Map<String, dynamic>> ownerUpdateTemplate(
    String id,
    Map<String, dynamic> body,
  ) async => await _request(
    'PATCH',
    '/owner/communications/templates/$id',
    body: body,
  );

  /// Copies a template (e.g. a FitFlex one) into the gym's own to adapt it.
  Future<Map<String, dynamic>> ownerDuplicateTemplate(
    String id, {
    String? gymId,
    String? name,
  }) async => await _request(
    'POST',
    '/owner/communications/templates/$id/duplicate',
    body: {'gymId': ?gymId, 'name': ?name},
  );

  Future<void> ownerArchiveTemplate(String id) async =>
      await _request('POST', '/owner/communications/templates/$id/archive');

  // ── Partner verification (KYC / KYB) ─────────────────────────────────────

  Future<Map<String, dynamic>> myKyc() async =>
      await _request('GET', '/me/kyc');

  Future<Map<String, dynamic>> updateMyKycBusiness(
    Map<String, dynamic> body,
  ) async => await _request('PUT', '/me/kyc/business', body: body);

  Future<Map<String, dynamic>> updateMyKycPerson(
    String role,
    Map<String, dynamic> body,
  ) async => await _request(
    'PUT',
    '/me/kyc/people/${Uri.encodeComponent(role)}',
    body: body,
  );

  Future<Map<String, dynamic>> updateMyKycDocument(
    String requirementKey,
    Map<String, dynamic> body,
  ) async => await _request(
    'PUT',
    '/me/kyc/documents/${Uri.encodeComponent(requirementKey)}',
    body: body,
  );

  /// Uploads a document's file (PDF, JPEG, PNG or WebP, up to 10 MB).
  Future<Map<String, dynamic>> uploadMyKycDocumentFile(
    String requirementKey, {
    required List<int> bytes,
    required String filename,
    String? docType,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/me/kyc/documents/${Uri.encodeComponent(requirementKey)}/file',
    );
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    if (_token != null) request.headers['authorization'] = 'Bearer $_token';
    if (docType != null) request.fields['docType'] = docType;
    _log.multipart('POST', uri, bytes.length);
    // Documents can be a few MB on a slow connection: allow longer than JSON calls.
    final streamed = await request.send().timeout(const Duration(seconds: 90));
    final res = await http.Response.fromStream(streamed);
    _log.response('POST', uri, res.statusCode, res.body);
    final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return (decoded as Map).cast<String, dynamic>();
    }
    if (res.statusCode == 401 && onUnauthorized != null) onUnauthorized!();
    throw ApiException(res.statusCode, decoded);
  }

  /// The stored file of one of my own documents, as bytes.
  Future<Uint8List> myKycDocumentFile(String documentId) async {
    final uri = Uri.parse(
      '$baseUrl/me/kyc/documents/${Uri.encodeComponent(documentId)}/file',
    );
    final res = await http
        .get(
          uri,
          headers: {if (_token != null) 'authorization': 'Bearer $_token'},
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    if (res.statusCode == 401 && onUnauthorized != null) onUnauthorized!();
    dynamic body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      body = null;
    }
    throw ApiException(res.statusCode, body);
  }

  Future<Map<String, dynamic>> addMyKycSettlementAccount(
    Map<String, dynamic> body,
  ) async => await _request('POST', '/me/kyc/settlement-accounts', body: body);

  Future<void> removeMyKycSettlementAccount(String id) async => await _request(
    'DELETE',
    '/me/kyc/settlement-accounts/${Uri.encodeComponent(id)}',
  );

  Future<Map<String, dynamic>> submitMyKyc() async =>
      await _request('POST', '/me/kyc/submit');

  Future<Map<String, dynamic>> withdrawMyKyc() async =>
      await _request('POST', '/me/kyc/withdraw');

  /// The partner terms and verification consent to accept, in [lang] (en or sw).
  Future<Map<String, dynamic>> myKycAgreements(String lang) async =>
      await _request('GET', '/me/kyc/agreements?lang=$lang');

  Future<Map<String, dynamic>> acceptMyKycAgreement(
    String agreementType,
    String version,
  ) async => await _request(
    'POST',
    '/me/kyc/agreements',
    body: {'agreementType': agreementType, 'version': version},
  );

  // ── Gym and trainer reviews ──────────────────────────────────────────
  Future<ReviewSummary> reviewSummary(ReviewSubject subject, String id) async =>
      ReviewSummary.fromJson(
        await _map('GET', '/${subject.path}/${_e(id)}/rating'),
      );

  Future<List<Review>> reviews(ReviewSubject subject, String id) async =>
      Review.listFrom(
        await _request('GET', '/${subject.path}/${_e(id)}/reviews?limit=50'),
      );

  /// Whether the member may review [id], plus their existing review if any.
  Future<MyReviewState> myReviewState(ReviewSubject subject, String id) async {
    final base = '/me/${subject.path}/${_e(id)}';
    final can = await _map('GET', '$base/can-review');
    Map<String, dynamic>? mine;
    if (can['hasExistingReview'] == true) {
      mine = await _map('GET', '$base/review');
    }
    return MyReviewState(
      eligible: can['eligible'] == true,
      reason: can['reason']?.toString(),
      rating: (mine?['rating'] as num?)?.toInt(),
      text: mine?['text'] as String?,
    );
  }

  /// Creates or replaces the member's review. Returns the new average and count.
  Future<({num average, int count})> submitReview(
    ReviewSubject subject,
    String id, {
    required int rating,
    String? text,
  }) async {
    final res = await _map(
      'POST',
      '/me/${subject.path}/${_e(id)}/review',
      body: {
        'rating': rating,
        'text': (text ?? '').trim().isEmpty ? null : text!.trim(),
      },
    );
    return _ratingFrom(res, subject);
  }

  Future<({num average, int count})> deleteMyReview(
    ReviewSubject subject,
    String id,
  ) async => _ratingFrom(
    await _map('DELETE', '/me/${subject.path}/${_e(id)}/review'),
    subject,
  );

  ({num average, int count}) _ratingFrom(
    Map<String, dynamic> res,
    ReviewSubject subject,
  ) {
    final r = res[subject == ReviewSubject.gym ? 'gymRating' : 'trainerRating'];
    final m = r is Map ? r : const {};
    return (
      average: (m['averageRating'] as num?) ?? 0,
      count: (m['reviewCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Trainer: the summary and reviews on their own profile.
  Future<({ReviewSummary summary, List<Review> reviews})>
  myTrainerReviews() async {
    final res = await _map('GET', '/trainer/reviews');
    return (
      summary: ReviewSummary.fromJson(
        Map<String, dynamic>.from(res['summary'] as Map? ?? const {}),
      ),
      reviews: Review.listFrom(res['reviews']),
    );
  }

  // ── Partner home photo and logo (PARTNER_MEDIA, fitflex-functions#277) ──

  /// `GET /partner/media` (gym roles pass [gymId]): the caller's own home
  /// photo and logo, `canEdit`, the confirmation texts and the file rules.
  Future<Map<String, dynamic>> partnerMedia({String? gymId}) async {
    final q = gymId == null || gymId.isEmpty
        ? ''
        : '?gymId=${Uri.encodeQueryComponent(gymId)}';
    final res = await _request('GET', '/partner/media$q');
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  /// The bytes of one live photo or logo, signed in, from the API host only
  /// ([uri] comes from `partnerMediaFileUri`). Redirects are refused, and a
  /// body over [maxBytes] (declared or while reading) answers null. The
  /// files are `Cache-Control: private, no-cache` with `ETag: "<file id>"`
  /// (functions#277 review M1): pass the saved copy's [etag] and a `304`
  /// answers `(status: 304)` without bytes. A refusal from the server (404
  /// `media_not_found` once it is removed, replaced or taken down) throws
  /// [ApiException].
  Future<({int status, Uint8List? bytes, String? etag})?> partnerMediaFile(
    Uri uri, {
    required int maxBytes,
    String? etag,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final base = Uri.parse(baseUrl);
    if (uri.scheme != base.scheme ||
        uri.host != base.host ||
        uri.port != base.port ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final abort = Completer<void>();
    final client = http.Client();
    try {
      final req = http.AbortableRequest('GET', uri, abortTrigger: abort.future)
        ..followRedirects = false
        ..headers['x-fitflex-client'] = kIdentityV2Client;
      if (_token != null) req.headers['authorization'] = 'Bearer $_token';
      if (etag != null && etag.isNotEmpty) req.headers['if-none-match'] = etag;
      Future<({int status, Uint8List? bytes, String? etag})?> run() async {
        final res = await client.send(req);
        if (res case http.BaseResponseWithUrl(:final url)) {
          if (url.host != base.host || url.port != base.port) {
            unawaited(res.stream.drain<void>().catchError((Object _) {}));
            return null;
          }
        }
        if (res.statusCode == 304) {
          unawaited(res.stream.drain<void>().catchError((Object _) {}));
          return (status: 304, bytes: null, etag: res.headers['etag'] ?? etag);
        }
        if (res.statusCode != 200) {
          final body = await _readCapped(res.stream, 16 * 1024);
          if (res.statusCode == 401 && onUnauthorized != null) {
            onUnauthorized!();
          }
          if (res.statusCode >= 300 && res.statusCode < 400) return null;
          throw ApiException(
            res.statusCode,
            body == null ? null : _decodeErrorBody(utf8.decode(body)),
          );
        }
        final declared = res.contentLength;
        if (declared != null && declared > maxBytes) {
          unawaited(res.stream.drain<void>().catchError((Object _) {}));
          return null;
        }
        final bytes = await _readCapped(res.stream, maxBytes);
        return bytes == null
            ? null
            : (status: 200, bytes: bytes, etag: res.headers['etag']);
      }

      return await run().timeout(timeout);
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      rethrow;
    } finally {
      client.close();
    }
  }

  static Future<Uint8List?> _readCapped(Stream<List<int>> s, int limit) async {
    final out = BytesBuilder(copy: false);
    await for (final chunk in s) {
      if (out.length + chunk.length > limit) return null;
      out.add(chunk);
    }
    return out.takeBytes();
  }

  /// `POST /partner/media/hero` or `/logo` (multipart): the original
  /// [bytes] as picked (never downscaled; the server cleans them) and the
  /// text [fields]. [onProgress] follows the bytes as the connection takes
  /// them (on the web the browser sends the body at once). Completing
  /// [abortTrigger] cancels it. Answers `{item}`.
  Future<Map<String, dynamic>> partnerMediaUpload(
    String kind, {
    required List<int> bytes,
    required String filename,
    required Map<String, String> fields,
    void Function(int sent, int total)? onProgress,
    Future<void>? abortTrigger,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/partner/media/${kind == 'logo' ? 'logo' : 'hero'}',
    );
    final form = http.MultipartRequest('POST', uri)
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    final body = await form.finalize().toBytes();
    final req = _ProgressRequest('POST', uri, body, onProgress, abortTrigger)
      ..headers.addAll(form.headers);
    req.headers['x-fitflex-client'] = kIdentityV2Client;
    if (_token != null) req.headers['authorization'] = 'Bearer $_token';
    _log.multipart('POST', uri, bytes.length);
    final client = http.Client();
    try {
      final streamed = await client
          .send(req)
          .timeout(const Duration(seconds: 120));
      final res = await http.Response.fromStream(streamed);
      _log.response('POST', uri, res.statusCode, res.body);
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      final decoded = res.body.isEmpty
          ? null
          : ok
          ? jsonDecode(res.body)
          : _decodeErrorBody(res.body);
      if (ok) {
        return decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
      }
      if (res.statusCode == 401 && onUnauthorized != null) onUnauthorized!();
      throw ApiException(res.statusCode, decoded);
    } finally {
      client.close();
    }
  }

  /// `DELETE /partner/media/:id`: the partner removes their live photo or
  /// logo. Answers `{item}`.
  Future<Map<String, dynamic>> partnerMediaRemove(String id) async {
    final res = await _request('DELETE', '/partner/media/${_seg(id)}');
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }
}

/// A request whose body is handed over in 32 KB pieces, each counted once
/// the connection takes it, for an upload's "Uploading… n%".
class _ProgressRequest extends http.BaseRequest with http.Abortable {
  _ProgressRequest(
    super.method,
    super.url,
    this._body,
    this._onProgress,
    this.abortTrigger,
  ) {
    contentLength = _body.length;
  }

  final Uint8List _body;
  final void Function(int sent, int total)? _onProgress;

  @override
  final Future<void>? abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_chunks());
  }

  Stream<List<int>> _chunks() async* {
    const step = 32 * 1024;
    var sent = 0;
    _onProgress?.call(0, _body.length);
    while (sent < _body.length) {
      final end = sent + step < _body.length ? sent + step : _body.length;
      yield Uint8List.sublistView(_body, sent, end);
      sent = end;
      _onProgress?.call(sent, _body.length);
    }
  }
}
