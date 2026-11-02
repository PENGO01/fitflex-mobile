import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// Hidden in the iOS app: it has no Firebase iOS client for its bundle ID, and
/// offering it would also need an equal login option (App Store guideline 4.8).
bool get googleSignInAvailable =>
    kIsWeb || defaultTargetPlatform != TargetPlatform.iOS;

class FirebaseAuthService {
  FirebaseAuthService({
    FirebaseAuth? auth,
    this.operationTimeout = const Duration(seconds: 20),
  }) : _authOverride = auth;

  static const _defaultServerClientId = String.fromEnvironment(
    'GOOGLE_SIGN_IN_SERVER_CLIENT_ID',
    defaultValue:
        '318978253903-u6du2v8thfbdbmortdh49k1g06uv91v7.apps.googleusercontent.com',
  );

  // Resolved lazily so a test double can subclass this without Firebase.
  final FirebaseAuth? _authOverride;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  final Duration operationTimeout;
  Future<void>? _googleInit;

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _withTimeout(
      _auth.signInWithEmailAndPassword(email: email, password: password),
    );
  }

  Future<UserCredential> createAccountWithEmail({
    required String email,
    required String password,
  }) {
    return _withTimeout(
      _auth.createUserWithEmailAndPassword(email: email, password: password),
    );
  }

  Future<void> updateEmailPassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed-in Firebase user is available.',
      );
    }
    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );
    await _withTimeout(user.reauthenticateWithCredential(credential));
    await _withTimeout(user.updatePassword(newPassword));
  }

  Future<UserCredential?> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});

    if (kIsWeb) {
      return _withTimeout(_auth.signInWithPopup(provider));
    }

    await _ensureGoogleSignInInitialized();
    final googleUser = await _withTimeout(GoogleSignIn.instance.authenticate());
    final googleIdToken = googleUser.authentication.idToken;
    if (googleIdToken == null) {
      throw FirebaseAuthException(
        code: 'missing-google-id-token',
        message: 'Google did not return an ID token.',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: googleIdToken);
    return _withTimeout(_auth.signInWithCredential(credential));
  }

  Future<void> _ensureGoogleSignInInitialized() {
    return _googleInit ??= _withTimeout(
      GoogleSignIn.instance.initialize(serverClientId: _defaultServerClientId),
    );
  }

  Future<UserCredential?> completeWebRedirect() async {
    if (!kIsWeb) return null;
    return _withTimeout(_auth.getRedirectResult());
  }

  Future<String?> idTokenFor(User? user) {
    if (user == null) return Future.value();
    return _withTimeout(user.getIdToken());
  }

  /// Email of the signed-in Firebase user, if any.
  String? get currentEmail => _auth.currentUser?.email;

  /// Sends Firebase's verification link to the signed-in user's email.
  Future<void> sendEmailVerification() async {
    await _withTimeout(_requireUser().sendEmailVerification());
  }

  /// Reloads the signed-in user from Firebase and reports whether their
  /// email is now verified (the link is opened outside the app).
  Future<bool> reloadEmailVerified() async {
    await _withTimeout(_requireUser().reload());
    return _auth.currentUser?.emailVerified ?? false;
  }

  /// A newly minted ID token, so claims such as `email_verified` are current.
  Future<String?> freshIdToken() {
    final user = _auth.currentUser;
    if (user == null) return Future.value();
    return _withTimeout(user.getIdToken(true));
  }

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed-in Firebase user is available.',
      );
    }
    return user;
  }

  Future<void> signOut() async {
    await _withTimeout(_auth.signOut());
    if (!kIsWeb) {
      try {
        await _ensureGoogleSignInInitialized();
        await _withTimeout(GoogleSignIn.instance.signOut());
      } catch (_) {
        // Firebase sign-out is authoritative for app state.
      }
    }
  }

  Future<T> _withTimeout<T>(Future<T> operation) {
    return authenticationWithTimeout(operation, timeout: operationTimeout);
  }
}

Future<T> authenticationWithTimeout<T>(
  Future<T> operation, {
  Duration timeout = const Duration(seconds: 20),
}) {
  return operation.timeout(
    timeout,
    onTimeout: () => throw FirebaseAuthException(
      code: 'network-request-failed',
      message: 'Authentication timed out. Check your connection and try again.',
    ),
  );
}
