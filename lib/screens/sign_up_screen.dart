import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_scope.dart';
import '../router.dart';
import '../shared/api_client.dart';
import '../shared/api_error_message.dart';
import '../shared/auth_state.dart';
import '../shared/components/components.dart';
import '../shared/photo_hero_flag.dart';
import '../shared/design_tokens.dart';
import '../shared/firebase_auth_service.dart';
import '../shared/i18n.dart';
import 'email_auth_screen.dart';
import 'pin_flows.dart';

/// Independent account-creation entry point, reached only from the
/// sign-in screen's "Create account" link. Kept separate from
/// [AuthScreen] so the sign-in / sign-up flows don't confuse users.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, this.authService});

  final FirebaseAuthService? authService;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen>
    with SingleTickerProviderStateMixin {
  FirebaseAuthService? _firebaseAuth;
  final _emailCtrl = TextEditingController();
  bool _busy = false;
  bool _isValidInput = false;
  String? _inputError;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  FirebaseAuthService get _authService =>
      _firebaseAuth ??= widget.authService ?? FirebaseAuthService();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: FFTokens.motionSlow,
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _animController.forward();
    _emailCtrl.addListener(_validateInput);
  }

  void _validateInput() {
    final text = _emailCtrl.text.trim();
    final isEmail = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(text);
    final isPhone = RegExp(r'^\+?[0-9]{7,15}$').hasMatch(text);

    final isValid = isEmail || isPhone;
    if (_isValidInput != isValid || (isValid && _inputError != null)) {
      setState(() {
        _isValidInput = isValid;
        if (isValid) _inputError = null;
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showFFAuthErrorDialog(context, message);
  }

  Future<void> _handleSessionApiError(ApiException e) async {
    if (requiresEmailVerification(e.body)) {
      final auth = AppScope.of(context).auth;
      context.go(AppRoutes.verifyEmailFor(auth.role));
      return;
    }
    _showErrorDialog(apiErrorMessage(FFLocaleScope.of(context), e));
  }

  String _firebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return context.tr('auth.cancelled');
      case 'network-request-failed':
        return context.tr('auth.networkError');
      default:
        return e.message ?? e.code;
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    setState(() => _busy = true);
    final adminPortalOnlyMsg = context.tr('auth.adminPortalOnly');
    try {
      final credential = await _authService.signInWithGoogle();
      final user = credential?.user ?? _authService.currentUser;
      await _finishFirebaseUser(user);
    } on FirebaseAuthException catch (e) {
      _showErrorDialog(_firebaseError(e));
    } on ApiException catch (e) {
      await _handleSessionApiError(e);
    } on AdminMobileSignInException {
      _showErrorDialog(adminPortalOnlyMsg);
    } catch (e) {
      if (mounted) _showErrorDialog(errorMessage(FFLocaleScope.of(context), e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishFirebaseUser(User? firebaseUser) async {
    final idToken = await _authService.idTokenFor(firebaseUser);
    if (idToken == null) throw StateError('Missing Firebase ID token');
    if (!mounted) return;
    final auth = AppScope.of(context).auth;
    await auth.completeFirebaseSession(
      idToken: idToken,
      requestedRole: auth.role,
      firebaseAuth: _authService,
    );
    if (!mounted) return;
    context.go(routeForSignedInUser(auth));
  }

  void _attemptContinue() {
    if (!_isValidInput) {
      setState(() => _inputError = context.tr('auth.invalidEmailOrPhone'));
      return;
    }
    setState(() => _inputError = null);
    // When FitFlex keeps the PIN: prove the number or email with a code, then
    // choose the PIN. Otherwise the Firebase email + PIN path, as before.
    final auth = AppScope.of(context).auth;
    final contact = _emailCtrl.text.trim();
    if (auth.pinLoginEnabled &&
        !contact.contains('@') &&
        !auth.smsCodesAvailable) {
      setState(() => _inputError = context.tr('auth.phoneSignUpUnavailable'));
      return;
    }
    if (usesFitFlexCodes(auth, contact)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RegisterFlowScreen(contact: contact),
        ),
      );
      return;
    }
    pushEmailAuth(
      context,
      contact: _emailCtrl.text.trim(),
      mode: EmailAuthMode.signUp,
    );
  }

  /// Google, OR, the identifier and Continue. Shared by both layouts.
  List<Widget> _formChildren(BuildContext context, bool loading) => [
    if (googleSignInAvailable) ...[
      FFGoogleSignInButton(
        label: context.tr('auth.continueWithGoogle').toUpperCase(),
        onTap: loading ? null : _signInWithGoogle,
        loading: _busy,
      ),
      const SizedBox(height: 28),
      FFDividerLabel(label: context.tr('auth.or')),
      const SizedBox(height: 28),
    ],
    FFTextField(
      controller: _emailCtrl,
      enabled: !loading,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      hint: context.tr('auth.emailOrPhone'),
      errorText: _inputError,
      prefixIcon: const Icon(Icons.mail_outline_rounded),
      textInputAction: TextInputAction.done,
      onFieldSubmitted: loading ? null : (_) => _attemptContinue(),
    ),
    const SizedBox(height: 24),
    FilledButton(
      onPressed: loading ? null : _attemptContinue,
      child: loading
          ? FFSpinner(size: 18, color: Theme.of(context).colorScheme.onPrimary)
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  context.tr('lang.continue').toUpperCase(),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    // The text style carries the body
                    // colour; on the primary fill the
                    // label must use on-primary.
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: FFTokens.spacingSm),
                const Icon(Icons.chevron_right, size: FFTokens.iconMd),
              ],
            ),
    ),
  ];

  /// Hero copy keys for the chosen account type.
  static String _roleKey(String role) => switch (role) {
    'gym_owner' => 'owner',
    'trainer' => 'trainer',
    'vendor' => 'vendor',
    'gym_staff' => 'staff',
    _ => 'member',
  };

  /// PHOTO_HERO_UI: the hero names the chosen role and what it is for.
  bool _precachedHome = false;

  Widget _buildPhotoHero(BuildContext context, bool loading) {
    // Home's photos are next once this screen completes (§9).
    if (!_precachedHome) {
      _precachedHome = true;
      precacheHeroPhotos(context, const [
        FFHeroPhoto.homeStart,
        FFHeroPhoto.homePass,
      ]);
    }
    final role = _roleKey(AppScope.of(context).auth.role);
    return FFPhotoHeroPage(
      // Taller hero (spec §5.3): the photo gives way so Continue stays on
      // screen (Google, the field and Continue are 264px below the hero).
      tallContentReserve: 272,
      tallReserveGrowth: 60,
      leading: IconButton(
        tooltip: context.tr('a11y.back'),
        icon: const Icon(Icons.arrow_back),
        onPressed: loading
            ? null
            : () =>
                  context.canPop() ? context.pop() : context.go(AppRoutes.auth),
      ),
      actions: const [AppPrefsButtons()],
      hero: (context, f) => FFPhotoHero(
        key: Key('signup-hero-$role'),
        photo: FFHeroPhoto.signUp,
        variant: f.variant,
        minHeight: f.minHeight,
        topInset: f.topInset,
        clearPhoto: f.clearPhoto,
        maxHeight: f.maxHeight,
        wideHeadline: f.wide,
        eyebrow: context.tr('role.$role'),
        headlineLead: context.tr('hero.signUp.$role.lead'),
        headlineAccent: context.tr('hero.signUp.$role.accent'),
        subline: context.tr('role.${role}Body'),
      ),
      content: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _formChildren(context, loading),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = _busy;
    if (photoHeroUi) return _buildPhotoHero(context, loading);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: loading
              ? null
              : () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.auth),
        ),
        actions: const [AppPrefsButtons()],
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: FFTokens.spacingLg,
                vertical: FFTokens.spacingMd,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        context.tr('auth.signUp'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 36),
                      ..._formChildren(context, loading),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
