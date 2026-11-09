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
import '../shared/auth_error_message.dart';

/// Shown when the backend answers a sign-in with
/// `409 email_verification_required`: the email matches a FitFlex profile
/// this Firebase account doesn't own yet, so Firebase must verify the email
/// first. The Firebase session stays signed in while the person verifies.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, this.requestedRole, this.authService});

  /// Role to send again when retrying: set during sign-up, null for sign-in.
  final String? requestedRole;
  final FirebaseAuthService? authService;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  FirebaseAuthService? _ownedAuthService;
  FirebaseAuthService get _authService =>
      widget.authService ?? (_ownedAuthService ??= FirebaseAuthService());

  bool _busy = false;
  bool _sending = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await _authService.sendEmailVerification();
      if (mounted) setState(() => _notice = context.tr('auth.verifyEmailSent'));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'no-current-user') {
        _startOver();
        return;
      }
      setState(() => _notice = context.tr('auth.verifyEmailSendFailed'));
    } catch (_) {
      if (mounted) {
        setState(() => _notice = context.tr('auth.verifyEmailSendFailed'));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final verified = await _authService.reloadEmailVerified();
      if (!mounted) return;
      if (!verified) {
        setState(() => _notice = context.tr('auth.verifyEmailNotYet'));
        return;
      }
      // The old ID token still says email_verified: false.
      final idToken = await _authService.freshIdToken();
      if (idToken == null) {
        _startOver();
        return;
      }
      if (!mounted) return;
      final auth = AppScope.of(context).auth;
      await auth.completeFirebaseSession(
        idToken: idToken,
        requestedRole: widget.requestedRole,
        firebaseAuth: _authService,
      );
      if (!mounted) return;
      context.go(routeForSignedInUser(auth));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'no-current-user') {
        _startOver();
        return;
      }
      setState(
        () => _notice = authErrorMessage(FFLocaleScope.of(context), e.code),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _notice = requiresEmailVerification(e.body)
            ? context.tr('auth.verifyEmailNotYet')
            : apiErrorMessage(FFLocaleScope.of(context), e);
      });
    } on AdminMobileSignInException {
      if (mounted) setState(() => _notice = context.tr('auth.adminPortalOnly'));
    } catch (e) {
      if (mounted) {
        setState(() => _notice = errorMessage(FFLocaleScope.of(context), e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useOtherAccount() async {
    try {
      await _authService.signOut();
    } catch (_) {
      // Leaving this screen matters more than a failed sign-out.
    }
    if (mounted) _startOver();
  }

  void _startOver() => context.go(AppRoutes.auth);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = _authService.currentEmail ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('app.title')),
        actions: const [AppPrefsButtons()],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.mark_email_unread_outlined,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(
                context.tr('auth.verifyEmailTitle'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              Text(
                context.tr('auth.verifyEmailBody').replaceAll('{email}', email),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              if (_notice != null) ...[
                const SizedBox(height: FFTokens.spacingMd),
                Text(
                  _notice!,
                  key: const Key('verify-email-notice'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('verify-email-continue'),
                onPressed: _busy ? null : _continue,
                icon: _busy
                    ? SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(context.tr('auth.verifyEmailContinue')),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              FFButton(
                key: const Key('verify-email-resend'),
                label: context.tr('auth.verifyEmailResend'),
                onPressed: _sending ? null : _send,
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
              ),
              const Spacer(),
              FFButton(
                label: context.tr('auth.verifyEmailOtherAccount'),
                onPressed: _useOtherAccount,
                variant: FFButtonVariant.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
