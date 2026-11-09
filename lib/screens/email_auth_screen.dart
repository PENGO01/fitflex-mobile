import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_scope.dart';
import '../router.dart';
import '../shared/api_client.dart';
import '../shared/api_error_message.dart';
import '../shared/auth_state.dart';
import '../shared/components/components.dart';
import '../shared/design_tokens.dart';
import '../shared/firebase_auth_service.dart';
import '../shared/i18n.dart';
import '../shared/photo_hero_flag.dart';
import '../shared/pin_credentials.dart';
import 'account_recovery.dart';
import 'pin_flows.dart';
import '../shared/auth_error_message.dart';

enum EmailAuthMode { signIn, signUp }

/// What the email/phone + PIN screen needs, passed as GoRouter `extra`.
///
/// The contact (an email address or phone number) must never go in the URL:
/// it would land in browser history, server/proxy logs and analytics. This
/// class deliberately has no `toJson`, so GoRouter cannot serialise it into
/// browser history state either; it lives in memory only. After a reload or
/// a history restore it is gone and the route sends the user back to the
/// sign-in entry.
@immutable
class EmailAuthArgs {
  const EmailAuthArgs({
    required this.contact,
    this.mode = EmailAuthMode.signIn,
  });

  final String contact;
  final EmailAuthMode mode;
}

/// Opens the email/phone + PIN screen without putting [contact] in the URL.
void pushEmailAuth(
  BuildContext context, {
  required String contact,
  EmailAuthMode mode = EmailAuthMode.signIn,
}) {
  context.push(
    AppRoutes.emailAuth,
    extra: EmailAuthArgs(contact: contact, mode: mode),
  );
}

class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({
    super.key,
    this.initialEmail = '',
    this.initialMode = EmailAuthMode.signIn,
    this.authService,
  });

  final String initialEmail;
  final EmailAuthMode initialMode;
  final FirebaseAuthService? authService;

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  FirebaseAuthService? _firebaseAuth;
  bool _busy = false;
  // Set while this phone holds an account recovery request to look at.
  String? _recoveryToken;
  String _pin = '';
  final int _minPinLength = 4;
  // A new PIN is exactly four digits. Signing in still accepts the longer
  // PINs that could be set before that rule, up to the old limit of eight.
  int get _maxPinLength => widget.initialMode == EmailAuthMode.signUp ? 4 : 8;
  bool _obscurePin = true;

  FirebaseAuthService get _authService =>
      _firebaseAuth ??= widget.authService ?? FirebaseAuthService();

  void _onDigit(int digit) {
    if (_pin.length < _maxPinLength) {
      setState(() => _pin += digit.toString());
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showFFAuthErrorDialog(
      context,
      message,
      onClose: () {
        if (mounted) setState(() => _pin = '');
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadRecoveryToken();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).auth.loadSignInOptions();
    });
  }

  /// Sign in with the PIN FitFlex keeps. An existing user whose PIN is still
  /// with Firebase is taken through moving it across.
  Future<void> _submitWithFitFlexPin() async {
    final scope = AppScope.of(context);
    final locale = FFLocaleScope.of(context).locale.languageCode;
    setState(() => _busy = true);
    try {
      final res = await scope.api.pinLogin(
        contactOf(widget.initialEmail),
        _pin,
        locale: locale,
      );
      if (!mounted) return;
      // Invited with a start PIN, or no profile yet: those have their own steps.
      if (res['startPin'] == true || res['onboarding'] == true) {
        setState(() => _pin = '');
        await openSignInStep(context, res);
        return;
      }
      if (res['setupRequired'] == true) {
        final pin = _pin;
        setState(() => _pin = '');
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PinSetupScreen(
              setupToken: res['setupToken'].toString(),
              contact:
                  res['identifierValue']?.toString() ?? widget.initialEmail,
              needsCode: res['verificationRequired'] == true,
              needsNewPin: res['pinChangeRequired'] == true,
              currentPin: pin,
              resendAfterSeconds:
                  (res['resendAfterSeconds'] as num?)?.toInt() ?? 60,
            ),
          ),
        );
        return;
      }
      await scope.auth.completeFitFlexSession(res);
      EmailAuthExtraCodec.clear();
      if (!mounted) return;
      context.go(routeForSignedInUser(scope.auth));
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog(pinErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AccountRecoveryScreen()),
    );
    _loadRecoveryToken();
  }

  Future<void> _checkRecovery() async {
    final token = _recoveryToken;
    if (token == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecoveryStatusScreen(requestToken: token),
      ),
    );
    _loadRecoveryToken();
  }

  Future<void> _loadRecoveryToken() async {
    final token = await savedRecoveryToken();
    if (mounted) setState(() => _recoveryToken = token);
  }

  /// Forgot PIN by FitFlex code: not for an email while FitFlex cannot send
  /// email codes.
  bool _resetOffered(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return !widget.initialEmail.contains('@') || auth.emailCodesAvailable;
  }

  void _forgotPin() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ForgotPinScreen(contact: widget.initialEmail),
      ),
    );
  }

  Future<void> _submit() async {
    if (_pin.length < _minPinLength) return;
    // When FitFlex keeps the PIN, sign-in goes to FitFlex, not Firebase.
    if (widget.initialMode == EmailAuthMode.signIn &&
        usesFitFlexCodes(AppScope.of(context).auth, widget.initialEmail)) {
      return _submitWithFitFlexPin();
    }
    setState(() => _busy = true);

    try {
      final email = widget.initialEmail;
      final password = firebasePasswordForPin(_pin);

      final credential = widget.initialMode == EmailAuthMode.signUp
          ? await _authService.createAccountWithEmail(
              email: email,
              password: password,
            )
          : await _authService.signInWithEmail(
              email: email,
              password: password,
            );

      final idToken = await _authService.idTokenFor(credential.user);
      if (idToken == null) throw StateError('Missing Firebase ID token');

      if (!mounted) return;
      final auth = AppScope.of(context).auth;
      await auth.completeFirebaseSession(
        idToken: idToken,
        // A role is only supplied while creating an account. During sign-in
        // FitFlex must resolve the existing role stored on the backend.
        requestedRole: widget.initialMode == EmailAuthMode.signUp
            ? auth.role
            : null,
        firebaseAuth: _authService,
      );

      EmailAuthExtraCodec.clear();
      if (!mounted) return;
      context.go(routeForSignedInUser(auth));
    } on FirebaseAuthException catch (e) {
      _showErrorDialog(_firebaseError(e));
    } on ApiException catch (e) {
      await _handleSessionApiError(e);
    } on AdminMobileSignInException {
      _showErrorDialog(context.tr('auth.adminPortalOnly'));
    } catch (e) {
      _showErrorDialog(errorMessage(FFLocaleScope.of(context), e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleSessionApiError(ApiException e) async {
    if (requiresEmailVerification(e.body)) {
      // Keep the Firebase session: the verify step retries with it.
      final auth = AppScope.of(context).auth;
      final role = widget.initialMode == EmailAuthMode.signUp
          ? auth.role
          : null;
      context.go(AppRoutes.verifyEmailFor(role));
      return;
    }
    _showErrorDialog(apiErrorMessage(FFLocaleScope.of(context), e));
  }

  String _firebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return context.tr('auth.emailAlreadyInUse');
      case 'invalid-email':
        return context.tr('onboarding.invalidEmail');
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return context.tr('auth.invalidCredentials');
      case 'weak-password':
        return context.tr('auth.weakPassword');
      case 'network-request-failed':
        return context.tr('auth.networkError');
      default:
        return authErrorMessage(FFLocaleScope.of(context), e.code);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.auth);
    }
  }

  /// PHOTO_HERO_UI shows the hero only from this viewport height up; below
  /// it (and above 1.15x text) the screen is today's, so OK never leaves the
  /// screen (spec §22.1, C-6).
  static const heroMinViewportHeight = 760.0;

  Widget _showHideToggle(BuildContext context) => IconButton(
    tooltip: _obscurePin
        ? context.tr('a11y.showPin')
        : context.tr('a11y.hidePin'),
    icon: Icon(
      _obscurePin ? Icons.visibility : Icons.visibility_off,
      color: Theme.of(context).textTheme.bodySmall?.color,
    ),
    onPressed: () {
      setState(() => _obscurePin = !_obscurePin);
    },
  );

  /// Forgot PIN and the recovery links (unchanged conditions).
  List<Widget> _links(BuildContext context) => [
    if (widget.initialMode == EmailAuthMode.signIn && _resetOffered(context))
      Center(
        child: TextButton(
          key: const Key('forgot-pin'),
          onPressed: _busy || !AppScope.of(context).auth.pinResetEnabled
              ? null
              : _forgotPin,
          child: Text(
            context.tr('auth.forgotPin'),
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    if (widget.initialMode == EmailAuthMode.signIn &&
        _resetOffered(context) &&
        AppScope.of(context).auth.pinResetEnabled) ...[
      Center(
        child: FFButton(
          key: const Key('recovery-link'),
          label: context.tr('rec.link'),
          onPressed: _busy ? null : _recover,
          variant: FFButtonVariant.ghost,
          size: FFButtonSize.sm,
        ),
      ),
      if (_recoveryToken != null)
        Center(
          child: FFButton(
            key: const Key('recovery-check'),
            label: context.tr('rec.check'),
            onPressed: _busy ? null : _checkRecovery,
            variant: FFButtonVariant.ghost,
            size: FFButtonSize.sm,
          ),
        ),
    ],
  ];

  /// PHOTO_HERO_UI: keypad first. The hero takes what the dots, keypad and
  /// links leave; none of them ever sits on the photo.
  Widget _buildPhotoHero(BuildContext context) {
    final signUp = widget.initialMode == EmailAuthMode.signUp;
    // 4 rows of 68 (52px keys) on tall phones, 60 (44px keys) below.
    final rowHeight = MediaQuery.sizeOf(context).height >= 844 ? 68.0 : 60.0;
    return FFPhotoHeroPage(
      pinnedContent: true,
      // A thin strip (owner 2026-10-22): the eyebrow, headline and contact
      // line over the photo, no clear photo above them; the dots and keypad
      // follow right under it, spare room goes below the links.
      phoneFraction: pinStripFraction,
      shortPhoneFraction: pinStripFraction,
      phoneMinHeight: 0,
      compactClearPhoto: pinHeroClearPhoto,
      heroMinViewportHeight: heroMinViewportHeight,
      maxHeroTextScale: 1.15,
      fallback: _buildToday,
      contentMaxWidth: 400,
      leading: IconButton(
        tooltip: context.tr('a11y.back'),
        icon: const Icon(Icons.arrow_back),
        onPressed: _busy ? null : _back,
      ),
      actions: const [AppPrefsButtons()],
      hero: (context, f) => FFPhotoHero(
        key: const Key('pin-hero'),
        photo: FFHeroPhoto.pin,
        variant: f.variant,
        minHeight: f.minHeight,
        topInset: f.topInset,
        clearPhoto: f.clearPhoto,
        maxHeight: f.maxHeight,
        wideHeadline: f.wide,
        eyebrow: context.tr(signUp ? 'auth.createPin' : 'auth.verificationPin'),
        headlineLead: context.tr(
          signUp ? 'hero.pin.create.lead' : 'hero.pin.signIn.lead',
        ),
        headlineAccent: context.tr(
          signUp ? 'hero.pin.create.accent' : 'hero.pin.signIn.accent',
        ),
        // The number or email typed on Sign in.
        subline: widget.initialEmail.isEmpty ? null : widget.initialEmail,
      ),
      content: Column(
        key: const Key('pin-pinned-content'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            alignment: Alignment.centerRight,
            children: [
              PinInputRow(pin: _pin, obscure: _obscurePin),
              _showHideToggle(context),
            ],
          ),
          const SizedBox(height: FFTokens.spacingMd),
          SizedBox(
            key: const Key('pin-keypad-box'),
            height: rowHeight * 4,
            child: CustomKeypad(
              onDigit: _onDigit,
              onDelete: _onDelete,
              onOk: _submit,
              okEnabled: _pin.length >= _minPinLength,
              isLoading: _busy,
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          ..._links(context),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (photoHeroUi) return _buildPhotoHero(context);
    return _buildToday(context);
  }

  /// Today's layout (flag off, short screens, large text).
  Widget _buildToday(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy ? null : _back,
        ),
        actions: const [AppPrefsButtons()],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FFTokens.spacingLg,
            vertical: FFTokens.spacingMd,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              // The keypad keeps 44px keys on short phones: the title
              // block gives way (and scrolls) before the keys shrink.
              child: PinPadLayout(
                key: const Key('pin-pad-layout'),
                gaps: (
                  FFTokens.spacingXl * 1.5,
                  FFTokens.spacingXl * 1.5,
                  FFTokens.spacingLg,
                ),
                header: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: FFTokens.spacingLg),
                    Text(
                      widget.initialMode == EmailAuthMode.signUp
                          ? context.tr('auth.createPin')
                          : context.tr('auth.verificationPin'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: FFTokens.spacingSm),
                    Text(
                      widget.initialEmail,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                pinned: Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    PinInputRow(pin: _pin, obscure: _obscurePin),
                    _showHideToggle(context),
                  ],
                ),
                keypad: CustomKeypad(
                  onDigit: _onDigit,
                  onDelete: _onDelete,
                  onOk: _submit,
                  okEnabled: _pin.length >= _minPinLength,
                  isLoading: _busy,
                ),
                footer: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ..._links(context),
                    const SizedBox(height: FFTokens.spacingMd),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
