import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../shared/partner_progress.dart';
import '../shared/widgets/partner_progress_tracker.dart';
import '../shared/widgets/delete_account.dart';
import '../shared/widgets/persona_switcher.dart';
import 'partner/verification/partner_progress_actions.dart';
import 'partner/verification/verification_models.dart';
import 'partner/verification/verification_repository.dart';
import 'email_auth_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.authService,
    this.enableFirebaseRecovery = true,
  });

  final FirebaseAuthService? authService;
  final bool enableFirebaseRecovery;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  FirebaseAuthService? _firebaseAuth;
  final _emailCtrl = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _recovering = false;
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

    if (widget.enableFirebaseRecovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recoverWebUser());
    }
  }

  void _validateInput() {
    final text = _emailCtrl.text.trim();
    // Basic email validation or phone number validation (7-15 digits, optional +)
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

  Future<void> _recoverWebUser() async {
    if (!kIsWeb || !mounted || AppScope.of(context).auth.isSignedIn) return;
    final user = _authService.currentUser;
    if (user == null) return;
    setState(() => _recovering = true);
    try {
      await _finishFirebaseUser(user);
    } catch (_) {
      // Keep the normal login screen available if recovery cannot complete.
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showFFAuthErrorDialog(context, message);
  }

  Future<void> _handleSessionApiError(ApiException e) async {
    if (requiresEmailVerification(e.body)) {
      context.go(AppRoutes.verifyEmail);
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
    if (_busy || _recovering) return;
    setState(() {
      _busy = true;
      _error = null;
    });
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
      firebaseAuth: _authService,
    );
    if (!mounted) return;
    context.go(routeForSignedInUser(auth));
  }

  void _continueWithEmail({EmailAuthMode mode = EmailAuthMode.signIn}) {
    pushEmailAuth(context, contact: _emailCtrl.text.trim(), mode: mode);
  }

  void _attemptContinue({EmailAuthMode mode = EmailAuthMode.signIn}) {
    if (!_isValidInput) {
      setState(() => _inputError = context.tr('auth.invalidEmailOrPhone'));
      return;
    }
    setState(() => _inputError = null);
    _continueWithEmail(mode: mode);
  }

  /// Everything under the title: Google, OR, the identifier, Continue and
  /// Create account. Shared by both layouts.
  List<Widget> _formChildren(BuildContext context, bool loading) => [
    // Google sign-in
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
    // Email/Phone field
    FFTextField(
      key: const Key('login-identifier'),
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
    // CONTINUE button
    FilledButton(
      key: const Key('login-continue'),
      onPressed: loading ? null : () => _attemptContinue(),
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
    if (_error != null) ...[
      const SizedBox(height: 16),
      FFAlert(message: _error!, tone: FFAlertTone.error),
    ],
    const SizedBox(height: 24),
    Wrap(
      key: const Key('login-create-account-link'),
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          context.tr('auth.noAccount'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
        FFButton(
          label: context.tr('auth.createAccount'),
          onPressed: loading ? null : () => context.push(AppRoutes.role),
          variant: FFButtonVariant.ghost,
          size: FFButtonSize.sm,
        ),
      ],
    ),
  ];

  /// PHOTO_HERO_UI: the compact photo hero carries the title.
  bool _precachedHome = false;

  Widget _buildPhotoHero(BuildContext context, bool loading) {
    // Home's photos are next once this screen completes (§9).
    if (!_precachedHome) {
      _precachedHome = true;
      precacheHeroPhotos(context, const [
        FFHeroPhoto.pin,
        FFHeroPhoto.homeStart,
        FFHeroPhoto.homePass,
      ]);
    }
    return FFPhotoHeroPage(
      // Taller hero (spec §5.3): the photo gives way so the "Create account"
      // link, the first control that must stay on screen here (owner
      // 2026-10-20), is on screen with Continue above it. Google, the field
      // and Continue are 264px below the hero, the link 72px more (24 gap +
      // 48 button); 8px margin. Larger text: the link wraps to two lines in
      // English at 1.3x, so the reserve grows faster than Continue's alone.
      tallContentReserve: 344,
      tallReserveGrowth: 155,
      leading: IconButton(
        tooltip: context.tr('a11y.back'),
        icon: const Icon(Icons.arrow_back),
        onPressed: loading ? null : () => context.go(AppRoutes.language),
      ),
      logo: const FFWordmark(),
      actions: const [AppPrefsButtons()],
      hero: (context, f) => FFPhotoHero(
        photo: FFHeroPhoto.signIn,
        variant: f.variant,
        minHeight: f.minHeight,
        topInset: f.topInset,
        clearPhoto: f.clearPhoto,
        maxHeight: f.maxHeight,
        wideHeadline: f.wide,
        logo: f.wide ? const FFWordmark() : null,
        eyebrow: context.tr('auth.signIn'),
        headlineLead: context.tr('hero.signIn.lead'),
        headlineAccent: context.tr('hero.signIn.accent'),
        subline: context.tr('hero.signIn.sub'),
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
    final loading = _busy || _recovering;
    if (photoHeroUi) return _buildPhotoHero(context, loading);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: loading ? null : () => context.go(AppRoutes.language),
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
                      // Title
                      Text(
                        context.tr('auth.signIn'),
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

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  bool _checking = false;
  int _pollInterval = 5;
  bool _polling = true;

  /// GET /me/kyc for a partner. Its `progress` (server flag PARTNER_PROGRESS)
  /// replaces the separate approval wording with one tracker; without it the
  /// screen is as before.
  KycOverview? _kyc;
  VerificationRepository? _repo;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo == null) {
      _repo = VerificationRepository(AppScope.of(context).api);
      if (_isPartner) _loadProgress();
    }
  }

  Future<void> _loadProgress() async {
    try {
      final data = await _repo!.overview();
      if (mounted) setState(() => _kyc = data);
    } catch (_) {
      // Keep what is shown (the old wording until progress is known).
    }
  }

  Future<void> _progressAction(PartnerNextAction action) async {
    final kyc = _kyc;
    if (kyc == null) return;
    await runPartnerAction(context, action, repository: _repo!, overview: kyc);
    if (mounted) await _loadProgress();
  }

  @override
  void dispose() {
    _polling = false;
    super.dispose();
  }

  Future<void> _startPolling() async {
    while (_polling && mounted) {
      await Future.delayed(Duration(seconds: _pollInterval));
      if (!_polling || !mounted) break;
      await _checkApproval(silent: true);
      if (mounted && _polling) {
        setState(() {
          _pollInterval = (_pollInterval * 2).clamp(5, 60);
        });
      }
    }
  }

  Future<void> _checkApproval({bool silent = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final scope = AppScope.of(context);
      final meRes = await scope.api.me();
      if (!mounted) return;
      final user = Map<String, dynamic>.from(meRes['user'] as Map);
      final status = user['approvalStatus']?.toString();
      if (status == 'pending_approval' && _isPartner) await _loadProgress();
      if (!mounted) return;
      if (status != 'pending_approval') {
        await scope.auth.signIn(scope.auth.token!, user);
        if (!mounted) return;
        _polling = false;
        context.go(routeForSignedInUser(scope.auth));
      } else if (!silent) {
        FFSnack.info(context, context.tr('auth.stillPending'));
      }
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('auth.checkFailed'))));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Widget _checkIcon(BuildContext context) => _checking
      ? SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            // On the filled button the spinner sits on the primary colour.
            color: _isPartner
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onPrimary,
          ),
        )
      : const Icon(Icons.refresh);

  PartnerProgress? get _progress => _isPartner ? _kyc?.progress : null;

  /// Gym owners, trainers and vendors complete KYC before approval.
  bool get _isPartner {
    final type = AppScope.of(context).auth.user?['userType']?.toString();
    return type == 'gym_operator' || type == 'trainer' || type == 'vendor';
  }

  Future<void> _backToRoles() async {
    _polling = false;
    final auth = AppScope.of(context).auth;
    await auth.signOut();
    if (!mounted) return;
    context.go(AppRoutes.role);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('app.title')),
        // A person whose other role is already approved (say a member who
        // applied as a vendor) must not be stuck here while they wait.
        actions: const [PersonaSwitchButton(), AppPrefsButtons()],
      ),
      body: SafeArea(
        // Scrolls when the extra role tile does not fit a small screen.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - FFTokens.spacingLg * 2,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_progress != null) ...[
                      PartnerProgressTracker(
                        progress: _progress!,
                        busy: _checking,
                        onAction: _progressAction,
                      ),
                      const SizedBox(height: FFTokens.spacingMd),
                    ] else ...[
                      Icon(
                        Icons.pending_actions,
                        size: 72,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        context.tr('auth.pendingTitle'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: FFTokens.spacingSm),
                      Text(
                        context.tr('auth.pendingBody'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (_isPartner && _progress == null) ...[
                      FFButton(
                        key: const Key('pending-verification'),
                        label: context.tr('kyc.pending.cta'),
                        onPressed: () => context.push(AppRoutes.verification),
                        icon: Icons.verified_user_outlined,
                      ),
                      const SizedBox(height: FFTokens.spacingSm),
                      Text(
                        context.tr('kyc.pending.hint'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: FFTokens.spacingMd),
                    ],
                    if (_isPartner)
                      OutlinedButton.icon(
                        onPressed: _checking ? null : () => _checkApproval(),
                        icon: _checkIcon(context),
                        label: Text(context.tr('auth.checkApproval')),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _checking ? null : () => _checkApproval(),
                        icon: _checkIcon(context),
                        label: Text(context.tr('auth.checkApproval')),
                      ),
                    const SizedBox(height: FFTokens.spacingMd),
                    // Only shows when the person has another role to use meanwhile.
                    const PersonaSwitcherTile(),
                    const Spacer(),
                    FFButton(
                      label: context.tr('auth.backToRoles'),
                      onPressed: _backToRoles,
                      variant: FFButtonVariant.secondary,
                    ),
                    const SizedBox(height: FFTokens.spacingXs),
                    const DeleteAccountButton(),
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

class GoogleWebCallbackScreen extends StatefulWidget {
  const GoogleWebCallbackScreen({super.key});

  @override
  State<GoogleWebCallbackScreen> createState() =>
      _GoogleWebCallbackScreenState();
}

class _GoogleWebCallbackScreenState extends State<GoogleWebCallbackScreen> {
  final _firebaseAuth = FirebaseAuthService();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
  }

  Future<void> _complete() async {
    if (!kIsWeb) {
      context.go(AppRoutes.auth);
      return;
    }
    try {
      final credential = await _firebaseAuth.completeWebRedirect();
      final user = credential?.user ?? _firebaseAuth.currentUser;
      final idToken = await _firebaseAuth.idTokenFor(user);
      if (idToken == null) throw StateError('Missing Firebase ID token');
      if (!mounted) return;
      final auth = AppScope.of(context).auth;
      await auth.completeFirebaseSession(
        idToken: idToken,
        firebaseAuth: _firebaseAuth,
      );
      if (!mounted) return;
      context.go(routeForSignedInUser(auth));
    } on ApiException catch (e) {
      if (requiresEmailVerification(e.body)) {
        if (mounted) context.go(AppRoutes.verifyEmail);
        return;
      }
      if (mounted) {
        setState(() => _error = apiErrorMessage(FFLocaleScope.of(context), e));
      }
    } on AdminMobileSignInException {
      if (mounted) setState(() => _error = context.tr('auth.adminPortalOnly'));
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorMessage(FFLocaleScope.of(context), e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _error == null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const FFSpinner(size: 32),
                        const SizedBox(height: 16),
                        Text(context.tr('auth.finishingSignIn')),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FFAlert(message: _error!, tone: FFAlertTone.error),
                        const SizedBox(height: 16),
                        FFButton(
                          label: context.tr('auth.backToSignIn'),
                          onPressed: () => context.go(AppRoutes.auth),
                          variant: FFButtonVariant.secondary,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
