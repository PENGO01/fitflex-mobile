import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'firebase_auth_service.dart';
import 'held_nav_extras.dart';
import 'events/event_claim_link.dart';
import 'events/event_ticket.dart' show EventTicketCache;
import 'events/events_cache.dart' show EventsCache;
import 'partner_details.dart';
import 'pending_friend_invite.dart';
import 'pending_org_invite.dart';
import 'push_service.dart';

/// Global session state. In a larger app this would be DI'd via Riverpod/Provider.
class AuthState extends ChangeNotifier {
  AuthState(this.api, {this.push}) {
    api.onUnauthorized = () => signOut();
    api.onPasswordChangeRequired = holdForPinChange;
  }

  final ApiClient api;

  /// Optional: registers the device for push while a session exists.
  final PushService? push;
  String? _token;
  Map<String, dynamic>? _user;
  String _role = 'member';
  // Identity V2: the Person's personas (User rows). Empty while the backend's
  // V2 flags are off, which keeps the app on single-persona behaviour.
  List<Map<String, dynamic>> _personas = const [];
  List<String> _addablePersonaTypes = const [];
  bool _personaChoiceRequired = false;
  // Identity V2 invitations. `_invitesEnabled` follows the backend flag:
  // while it is off the app keeps the legacy "create" forms.
  bool _invitesEnabled = false;
  List<Map<String, dynamic>> _invitations = const [];
  // A trainer or gym owner: is their own verification approved? Null for
  // other roles, and for a backend that does not report it.
  bool? _partnerVerified;
  // Identity V2 · I7: FitFlex keeps the PIN (sign-in and registration with a
  // number or email + PIN), and forgot PIN. Both follow the backend flags.
  bool _pinLoginEnabled = false;
  bool _pinResetEnabled = false;
  bool _emailCodesAvailable = true;
  bool _smsCodesAvailable = true;
  bool _signInOptionsLoaded = false;
  // Identity V2 identifiers: what this Person has proved is theirs.
  bool _identifiersEnabled = false;
  List<Map<String, dynamic>> _verifiedIdentifiers = const [];
  List<Map<String, dynamic>> _unverifiedIdentifiers = const [];
  // Which kind to suggest adding as a second contact ('email' or 'phone'),
  // and whether the person dismissed the reminder in this session.
  String? _secondContactMissing;
  bool _secondContactDismissed = false;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  String get role => _role;
  bool get isSignedIn => _token != null;

  /// Signed in, but /me could not be reached at start-up (offline, timeout,
  /// server error), so the account's state is only what this device kept.
  /// The router never treats that as "not onboarded" (H6): it shows a
  /// connection page with Retry instead of the setup flow.
  bool get profileUnconfirmed => _profileUnconfirmed;
  bool _profileUnconfirmed = false;
  bool get isPendingApproval =>
      _user?['approvalStatus']?.toString() == 'pending_approval';

  /// Gym staff whose PIN their owner chose (at creation or by a reset) must
  /// choose their own before anything else (fitflex-functions#260, flag
  /// STAFF_PIN_CHANGE_REQUIRED). The server says so with
  /// `user.passwordChangeRequired: true` at sign-in, or by refusing any
  /// route with `403 password_change_required`. With the flag off the field
  /// is false or absent and nothing changes.
  bool get pinChangeRequired =>
      _token != null &&
      _staffRole(_user?['userType']?.toString() ?? _role) &&
      _user?['passwordChangeRequired'] == true;

  static bool _staffRole(String role) => role == 'gym_staff';

  /// The server refused a request with `403 password_change_required`: hold
  /// this gym-staff session on the choose-your-own-PIN screen.
  void holdForPinChange() {
    if (_token == null) return;
    if (!_staffRole(_user?['userType']?.toString() ?? _role)) return;
    if (_user?['passwordChangeRequired'] == true) return;
    _user = {...?_user, 'passwordChangeRequired': true};
    // A held session is the server's answer, not a missing profile.
    _profileUnconfirmed = false;
    notifyListeners();
    final user = _user!;
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setString('user', jsonEncode(user)),
      ),
    );
  }

  /// The staff member chose their own PIN: [res] is the new session from
  /// `POST /auth/pin/change`. Every older token is over, so it is stored at
  /// once.
  Future<void> completeStaffPinChange(Map<String, dynamic> res) async {
    await completeFitFlexSession(res);
    // The change answer has no personas list; read it again.
    unawaited(refreshPersonas());
  }

  /// All live personas of the signed-in Person (empty before Identity V2).
  List<Map<String, dynamic>> get personas => _personas;

  /// Personas this session can switch to: not the current one, not
  /// portal-only, not suspended or rejected.
  List<Map<String, dynamic>> get switchablePersonas => _personas
      .where(
        (p) =>
            p['id'] != _user?['id'] &&
            p['portalOnly'] != true &&
            p['accountStatus'] != 'suspended' &&
            p['approvalStatus'] != 'rejected',
      )
      .toList(growable: false);

  /// Roles this Person could still add (empty unless the backend offers it).
  List<String> get addablePersonaTypes => _addablePersonaTypes;

  /// True when organisations invite people instead of creating accounts.
  bool get invitesEnabled => _invitesEnabled;

  /// Open invitations addressed to this Person.
  List<Map<String, dynamic>> get invitations => _invitations;

  /// False while a trainer or gym owner is active but not verified yet.
  bool? get partnerVerified => _partnerVerified;

  /// True when sign-in and registration use a number or email and a PIN that
  /// FitFlex keeps. While false the app signs in through Firebase as before.
  bool get pinLoginEnabled => _pinLoginEnabled;

  /// True when forgot PIN is available.
  bool get pinResetEnabled => _pinResetEnabled;

  /// True when FitFlex can send codes to an email. While false, email
  /// accounts stay on the Firebase path.
  bool get emailCodesAvailable => _emailCodesAvailable;

  /// True when FitFlex can send codes to a mobile number.
  bool get smsCodesAvailable => _smsCodesAvailable;

  /// Ask the backend which sign-in options are on. Safe to call repeatedly;
  /// it asks once unless [force] is set. Offline leaves the options off.
  Future<void> loadSignInOptions({bool force = false}) async {
    if (_signInOptionsLoaded && !force) return;
    Map<String, dynamic>? options;
    try {
      options = await api.signInOptions();
    } catch (_) {
      options = null; // older server (404) or offline: probe the routes
    }
    if (options != null && options['pinLogin'] is bool) {
      _pinLoginEnabled = options['pinLogin'] == true;
      _pinResetEnabled = options['pinReset'] == true;
      _emailCodesAvailable = options['emailCodes'] != false;
      _smsCodesAvailable = options['smsCodes'] != false;
    } else {
      final results = await Future.wait([
        api.pinLoginAvailable(),
        api.pinResetAvailable(),
      ]);
      _pinLoginEnabled = results[0];
      _pinResetEnabled = results[1];
      _emailCodesAvailable = true;
      _smsCodesAvailable = true;
    }
    _signInOptionsLoaded = true;
    notifyListeners();
  }

  /// Store a session that a PIN flow returned (sign-in, registration, PIN
  /// setup, reset or change) and load what follows a sign-in.
  Future<Map<String, dynamic>> completeFitFlexSession(
    Map<String, dynamic> res,
  ) async {
    final user = Map<String, dynamic>.from(res['user'] as Map);
    if (user['userType']?.toString() == 'admin') {
      await signOut();
      throw const AdminMobileSignInException();
    }
    await signInWithFitFlexSession(res['token'] as String, user);
    _partnerVerified = res['partnerVerified'] as bool?;
    await _applyPersonaPayload(res);
    unawaited(refreshInvitations());
    unawaited(refreshIdentifiers());
    return user;
  }

  /// True when the backend lets a person verify a mobile number or email.
  bool get identifiersEnabled => _identifiersEnabled;

  /// Mobile numbers and emails this Person has verified.
  List<Map<String, dynamic>> get verifiedIdentifiers => _verifiedIdentifiers;

  /// Profile values (mobile number, email) not verified yet.
  List<Map<String, dynamic>> get unverifiedIdentifiers =>
      _unverifiedIdentifiers;

  /// 'email' or 'phone' when only one kind is verified and the reminder to add
  /// the other has not been dismissed this session; otherwise null.
  String? get secondContactReminder =>
      _secondContactDismissed ? null : _secondContactMissing;

  void dismissSecondContactReminder() {
    _secondContactDismissed = true;
    notifyListeners();
  }

  /// Set when the backend couldn't pick a persona (several, none used last).
  bool get personaChoiceRequired => _personaChoiceRequired;

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    final u = prefs.getString('user');
    _user = u == null ? null : jsonDecode(u) as Map<String, dynamic>;
    _role = prefs.getString('role') ?? 'member';
    _personas = _decodePersonas(prefs.getString('personas'));
    api.setToken(_token);
    unawaited(loadSignInOptions());

    // If we have a token, refresh user from backend to get latest status
    if (_token != null) {
      try {
        final meRes = await api.me();
        final freshUser = Map<String, dynamic>.from(meRes['user'] as Map);
        _user = freshUser;
        _partnerVerified = meRes['partnerVerified'] as bool?;
        await prefs.setString('user', jsonEncode(freshUser));
        unawaited(push?.register());
        await refreshPersonas();
        await refreshInvitations();
        await refreshIdentifiers();
        _profileUnconfirmed = false;
      } on ApiException catch (e) {
        if (e.code == 'password_change_required') {
          // Held to the PIN change: the session is good, the profile
          // cannot be read until the PIN is changed (holdForPinChange).
          _profileUnconfirmed = false;
        } else if (e.status == 401 || e.status == 404) {
          // Token invalid or user deleted — clear session
          _token = null;
          _user = null;
          api.setToken(null);
          await prefs.remove('token');
          await prefs.remove('user');
        } else {
          // Server error: keep cached data, but it is unconfirmed.
          _profileUnconfirmed = true;
        }
      } catch (_) {
        // Network failure — keep cached data, but it is unconfirmed: the
        // router must not send this person to onboarding on its strength.
        _profileUnconfirmed = true;
      }
    }

    // Sync role with the authoritative userType from user object
    final userType = _user?['userType']?.toString();
    if (userType != null && userType != _role) {
      _role = userType;
      await prefs.setString('role', userType);
    }

    notifyListeners();
  }

  /// Tries /me again after a failed start-up. True once the profile is
  /// loaded (the router then moves on); false while it still cannot be
  /// reached. A session the server refuses is signed out.
  Future<bool> retryProfile() async {
    if (_token == null) return false;
    try {
      final meRes = await api.me();
      final freshUser = Map<String, dynamic>.from(meRes['user'] as Map);
      _user = freshUser;
      _partnerVerified = meRes['partnerVerified'] as bool?;
      final userType = freshUser['userType']?.toString();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user', jsonEncode(freshUser));
      if (userType != null && userType != _role) {
        _role = userType;
        await prefs.setString('role', userType);
      }
      _profileUnconfirmed = false;
      unawaited(push?.register());
      await refreshPersonas();
      await refreshInvitations();
      await refreshIdentifiers();
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.code == 'password_change_required' && pinChangeRequired) {
        // The router moves on to the PIN change.
        _profileUnconfirmed = false;
        notifyListeners();
        return true;
      }
      if (e.status == 401 || e.status == 404) {
        _profileUnconfirmed = false;
        await signOut();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setRole(String role) async {
    _role = role;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('role', role);
    notifyListeners();
  }

  Future<void> signIn(String token, Map<String, dynamic> user) async {
    _token = token;
    // A session the server just handed over is confirmed.
    _profileUnconfirmed = false;
    _user = user;
    // The backend owns role assignment. Persist the role returned with every
    // session so a later app launch (or a logout followed by login) cannot
    // reuse a stale role selected during an earlier registration attempt.
    final sessionRole = user['userType']?.toString();
    if (sessionRole != null && sessionRole.isNotEmpty) {
      _role = sessionRole;
    }
    api.setToken(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('user', jsonEncode(user));
    if (sessionRole != null && sessionRole.isNotEmpty) {
      await prefs.setString('role', sessionRole);
    }
    notifyListeners();
    unawaited(push?.register());
  }

  Future<void> signInWithFitFlexSession(
    String token,
    Map<String, dynamic> user,
  ) async {
    await signIn(token, user);
  }

  Future<Map<String, dynamic>> completeFirebaseSession({
    required String idToken,
    String? requestedRole,
    FirebaseAuthService? firebaseAuth,
  }) async {
    Map<String, dynamic> res;
    try {
      res = await api.firebaseSession(idToken, requestedRole);
    } on ApiException catch (error) {
      final fallbackRole = requestedRole == null
          ? preferredAutomaticRole(error.body)
          : null;
      if (fallbackRole == null) rethrow;
      res = await api.firebaseSession(idToken, fallbackRole);
    }
    final user = Map<String, dynamic>.from(res['user'] as Map);
    if (user['userType']?.toString() == 'admin') {
      await firebaseAuth?.signOut();
      await signOut();
      throw const AdminMobileSignInException();
    }
    await signInWithFitFlexSession(res['token'] as String, user);
    _partnerVerified = res['partnerVerified'] as bool?;
    await _applyPersonaPayload(res);
    unawaited(refreshInvitations());
    unawaited(refreshIdentifiers());
    return user;
  }

  /// Identity V2: move this session onto another persona of the same Person.
  Future<void> switchPersona(String personaId) async {
    final res = await api.switchPersona(personaId);
    final user = Map<String, dynamic>.from(res['user'] as Map);
    // A kept invitation link belongs to the session it was opened in, not
    // to the persona switched to.
    await PendingOrgInvite.clear();
    await PendingFriendInvite.clear();
    await PendingEventClaim.clear();
    // Push belongs to the persona: drop it for the old one, the new session
    // registers again in signIn().
    await push?.unregister();
    await signIn(res['token'] as String, user);
    await _applyPersonaPayload(res);
    await refreshPartnerVerified();
  }

  /// Re-read whether this trainer or gym owner is verified yet.
  Future<void> refreshPartnerVerified() async {
    if (_token == null) return;
    try {
      _partnerVerified = (await api.me())['partnerVerified'] as bool?;
    } catch (_) {
      _partnerVerified = null;
    }
    notifyListeners();
  }

  /// Identity V2: add a role to this Person, then continue as it. The new
  /// persona goes through that role's normal registration and approval.
  Future<void> addPersona(String userType) async {
    final res = await api.addPersona(userType);
    await _applyPersonaPayload(res, keepChoice: true);
    final persona = res['persona'];
    if (persona is Map && persona['id'] != null) {
      await switchPersona(persona['id'].toString());
    }
  }

  /// The user picked the persona they're already in.
  void keepCurrentPersona() {
    if (!_personaChoiceRequired) return;
    _personaChoiceRequired = false;
    notifyListeners();
  }

  /// Re-read this Person's invitations; a 404 means invitations are off.
  Future<void> refreshInvitations() async {
    if (_token == null) return;
    try {
      final res = await api.myInvitations();
      final raw = res['invitations'];
      _invitesEnabled = true;
      _invitations = raw is List
          ? raw
                .whereType<Map>()
                .map((i) => Map<String, dynamic>.from(i))
                .toList()
          : const [];
    } on ApiException catch (e) {
      if (e.status == 404) {
        _invitesEnabled = false;
        _invitations = const [];
      }
    } catch (_) {
      // Offline: keep what we have.
    }
    notifyListeners();
  }

  /// Re-read what this Person has verified; a 404 means verification is off.
  Future<void> refreshIdentifiers() async {
    if (_token == null) return;
    List<Map<String, dynamic>> listOf(Object? raw) => raw is List
        ? raw.whereType<Map>().map((i) => Map<String, dynamic>.from(i)).toList()
        : const [];
    try {
      final res = await api.myIdentifiers();
      _identifiersEnabled = true;
      _verifiedIdentifiers = listOf(res['identifiers']);
      _unverifiedIdentifiers = listOf(res['unverified']);
      final second = res['secondContact'];
      final missing = second is Map ? second['missing']?.toString() : null;
      _secondContactMissing = missing == 'email' || missing == 'phone'
          ? missing
          : null;
    } on ApiException catch (e) {
      if (e.status == 404) {
        _identifiersEnabled = false;
        _verifiedIdentifiers = const [];
        _unverifiedIdentifiers = const [];
        _secondContactMissing = null;
      }
    } catch (_) {
      // Offline: keep what we have.
    }
    notifyListeners();
  }

  /// Re-read the personas list; a 404 means Identity V2 is off.
  Future<void> refreshPersonas() async {
    if (_token == null) return;
    try {
      await _applyPersonaPayload(await api.myPersonas(), keepChoice: true);
    } on ApiException catch (e) {
      if (e.status == 404) await _applyPersonaPayload(const {});
    } catch (_) {
      // Offline: keep what we have.
    }
  }

  Future<void> _applyPersonaPayload(
    Map<String, dynamic> res, {
    bool keepChoice = false,
  }) async {
    final raw = res['personas'];
    _personas = raw is List
        ? raw.whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList()
        : const [];
    final addable = res['addablePersonaTypes'];
    _addablePersonaTypes = addable is List
        ? addable.map((t) => t.toString()).toList(growable: false)
        : const [];
    if (!keepChoice) {
      _personaChoiceRequired =
          res['personaChoiceRequired'] == true && _personas.length > 1;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('personas', jsonEncode(_personas));
    notifyListeners();
  }

  static List<Map<String, dynamic>> _decodePersonas(String? raw) {
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      return list is List
          ? list
                .whereType<Map>()
                .map((p) => Map<String, dynamic>.from(p))
                .toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> signOut() async {
    // Forget sign-in contacts held for browser history, so the next person
    // cannot press Back into this user's email/phone screen. A screen still
    // mounted (a 401 during sign-in lands here too) keeps its own.
    HeldNavExtras.clear();
    // Ending a real session: a kept invitation link is not the next
    // person's. Sign-in error paths (no session yet) keep it.
    if (_token != null) {
      await PendingOrgInvite.clear();
      await PendingFriendInvite.clear();
      await PendingEventClaim.clear();
      // Event tickets saved for offline use are this member's alone.
      await EventTicketCache.clearAll();
      // And so are results, medals, rewards and the event lists (M7).
      await EventsCache.clearAll();
    }
    // Partner date of birth: the session copy and the device-side prompt
    // counts are not the next person's (security review L1/L2).
    PartnerDetailsSession.clear();
    if (_token != null) await PartnerDobPromptStore.clearAll();
    // While the session token is still set, so the backend accepts the call.
    await push?.unregister();
    _token = null;
    _user = null;
    _profileUnconfirmed = false;
    _personas = const [];
    _addablePersonaTypes = const [];
    _personaChoiceRequired = false;
    _invitesEnabled = false;
    _invitations = const [];
    _identifiersEnabled = false;
    _verifiedIdentifiers = const [];
    _unverifiedIdentifiers = const [];
    _secondContactMissing = null;
    _secondContactDismissed = false;
    _partnerVerified = null;
    api.setToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user');
    await prefs.remove('personas');
    notifyListeners();
  }
}

String? preferredAutomaticRole(Object? errorBody) {
  if (errorBody is! Map ||
      errorBody['error']?.toString() != 'profile_role_required') {
    return null;
  }
  final availableRoles = errorBody['availableRoles'];
  if (availableRoles is! Iterable) return null;
  final operationalRoles = availableRoles
      .map((role) => role.toString())
      .where((role) => role.isNotEmpty && role != 'member')
      .toSet();
  return operationalRoles.length == 1 ? operationalRoles.single : null;
}

/// True when the backend refused a sign-in until Firebase verifies the
/// account's email (an unverified email can't claim an existing profile).
bool requiresEmailVerification(Object? errorBody) =>
    errorBody is Map &&
    errorBody['error']?.toString() == 'email_verification_required';

class AdminMobileSignInException implements Exception {
  const AdminMobileSignInException();
}
