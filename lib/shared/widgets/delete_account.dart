// Permanent, user-initiated account deletion (DELETE /me): one flow behind one
// button on every role's account area (Apple guideline 5.1.1(v)).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../screens/partner/verification/partner_progress_actions.dart'
    show openPartnerSupport;
import '../api_client.dart';
import '../api_error_message.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../firebase_auth_service.dart';
import '../i18n.dart';

/// `DELETE /me` refusals that support has to resolve: retrying cannot help,
/// so the sheet offers WhatsApp instead of the delete button.
const _blockedCodes = {
  'gym_owner_has_checkin_activity',
  'trainer_has_bookings',
  'organizer_owner',
  'open_paid_order',
};

/// The "Delete account" action. Draws nothing for gym and vendor staff: their
/// accounts are created and removed by the business that owns them.
class DeleteAccountButton extends StatelessWidget {
  const DeleteAccountButton({
    super.key,
    this.confirmLeave,
    this.onDeleted,
    this.firebaseAuth,
    this.openSupport = openPartnerSupport,
  });

  /// Asked before the sheet opens; false stops here (a vendor's sales still
  /// waiting to sync).
  final Future<bool> Function(BuildContext context)? confirmLeave;

  /// Runs once the account is gone, for data held in memory by the caller.
  final VoidCallback? onDeleted;

  /// Null: the app's Firebase session.
  final FirebaseAuthService? firebaseAuth;
  final Future<void> Function() openSupport;

  static bool availableTo(Object? userType) =>
      userType != 'gym_staff' && userType != 'vendor_staff';

  Future<void> _open(BuildContext context) async {
    final confirm = confirmLeave;
    if (confirm != null && !await confirm(context)) return;
    if (!context.mounted) return;
    await showFFSheet<void>(
      context,
      title: context.tr('account.delete.title'),
      showClose: false,
      isDismissible: false,
      child: DeleteAccountSheet(
        onDeleted: onDeleted,
        firebaseAuth: firebaseAuth,
        openSupport: openSupport,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!availableTo(AppScope.of(context).auth.user?['userType'])) {
      return const SizedBox.shrink();
    }
    return FFButton(
      key: const Key('delete-account'),
      label: context.tr('account.delete.title'),
      icon: Icons.delete_outline,
      variant: FFButtonVariant.ghost,
      foregroundColor: Theme.of(context).colorScheme.error,
      fullWidth: true,
      onPressed: () => _open(context),
    );
  }
}

/// What deletion means, the typed confirmation, and every outcome of the call.
class DeleteAccountSheet extends StatefulWidget {
  const DeleteAccountSheet({
    super.key,
    this.onDeleted,
    this.firebaseAuth,
    this.openSupport = openPartnerSupport,
  });

  final VoidCallback? onDeleted;
  final FirebaseAuthService? firebaseAuth;
  final Future<void> Function() openSupport;

  @override
  State<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<DeleteAccountSheet> {
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _blockedReason;

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  bool get _confirmed =>
      _confirmation.text.trim().toUpperCase() ==
      context.tr('account.delete.word');

  Future<void> _delete() async {
    if (_busy || !_confirmed) return;
    // The session ends below, which can take this sheet away with the page.
    final auth = AppScope.of(context).auth;
    final router = GoRouter.maybeOf(context);
    final snack = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final done = context.tr('account.delete.done');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.deleteAccount(
        firebaseAuth: widget.firebaseAuth ?? FirebaseAuthService(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        final blocked =
            error is ApiException &&
            error.status == 409 &&
            _blockedCodes.contains(error.code);
        if (blocked) {
          final body = error.body;
          _blockedReason = errorReasonText(
            locale,
            error.code!,
            body is Map ? Map<String, dynamic>.from(body) : null,
          );
        } else {
          _error = errorMessage(locale, error);
        }
      });
      return;
    }
    widget.onDeleted?.call();
    if (mounted) Navigator.of(context).pop();
    router?.go(AppRoutes.language);
    snack.success(done);
  }

  Future<void> _contactSupport() async {
    final snack = FFSnack.of(context);
    final failed = context.tr('error.requestFailed');
    try {
      await widget.openSupport();
    } catch (_) {
      snack.error(failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: _blockedReason == null ? _confirmStep(context) : _blocked(context),
    );
  }

  Widget _confirmStep(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final otherProfiles = AppScope.of(context).auth.personas.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FFAlert(
          message: context.tr('account.delete.warning'),
          tone: FFAlertTone.error,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Text(context.tr('account.delete.whatGoes')),
        const SizedBox(height: FFTokens.spacingSm),
        Text(context.tr('account.delete.retained'), style: muted),
        if (otherProfiles) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('account.delete.otherProfiles'),
            key: const Key('delete-account-other-profiles'),
          ),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        FFTextField(
          key: const Key('delete-account-confirm'),
          controller: _confirmation,
          enabled: !_busy,
          label: context
              .tr('account.delete.confirmLabel')
              .replaceFirst('{word}', context.tr('account.delete.word')),
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
        ),
        if (_error != null) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFAlert(
            key: const Key('delete-account-error'),
            message: _error!,
            tone: FFAlertTone.error,
          ),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        FFButton(
          key: const Key('delete-account-submit'),
          label: context.tr(
            _error == null ? 'account.delete.action' : 'common.retry',
          ),
          variant: FFButtonVariant.destructive,
          fullWidth: true,
          loading: _busy,
          onPressed: _confirmed && !_busy ? _delete : null,
        ),
        const SizedBox(height: FFTokens.spacingXs),
        FFButton(
          key: const Key('delete-account-cancel'),
          label: context.tr('common.cancel'),
          variant: FFButtonVariant.ghost,
          fullWidth: true,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _blocked(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FFAlert(
          key: const Key('delete-account-blocked'),
          message: _blockedReason!,
          tone: FFAlertTone.warning,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        FFButton(
          key: const Key('delete-account-support'),
          label: context.tr('account.delete.contactSupport'),
          icon: Icons.chat_outlined,
          fullWidth: true,
          onPressed: _contactSupport,
        ),
        const SizedBox(height: FFTokens.spacingXs),
        FFButton(
          key: const Key('delete-account-close'),
          label: context.tr('common.close'),
          variant: FFButtonVariant.ghost,
          fullWidth: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
