import 'i18n.dart';

/// Copy for a sign-in error code that a screen has no specific message for.
///
/// The auth SDK's own `message` is English, technical and names the vendor,
/// so it is never shown; neither is a raw code such as "too-many-requests".
String authErrorMessage(FFLocale locale, String code) {
  final key = switch (code) {
    'network-request-failed' => 'auth.networkError',
    'too-many-requests' => 'auth.tooManyRequests',
    'user-disabled' => 'auth.userDisabled',
    'no-current-user' ||
    'requires-recent-login' ||
    'user-token-expired' => 'auth.signInAgain',
    'missing-google-id-token' => 'auth.googleFailed',
    _ => 'auth.genericError',
  };
  return locale.t(key);
}
