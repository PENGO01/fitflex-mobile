import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/firebase_auth_service.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../../shared/photo_footer_flag.dart';
import '../../shared/photo_hero_flag.dart';
import '../../shared/pin_credentials.dart';
import 'member_shell.dart';
import 'widgets/home_hero.dart';
import 'widgets/membership_card.dart';
import 'widgets/pass_state.dart';
import 'member_edit_profile_page.dart';
import '../../shared/widgets/delete_account.dart';
import '../../shared/widgets/persona_switcher.dart';
import '../../shared/widgets/invitations.dart';
import '../../shared/widgets/verify_identifier.dart';
import '../pin_flows.dart';

class MemberProfileTab extends StatefulWidget {
  const MemberProfileTab({super.key});

  @override
  State<MemberProfileTab> createState() => _MemberProfileTabState();
}

class _MemberProfileTabState extends State<MemberProfileTab> {
  final _heroKey = GlobalKey();
  String? _pinError(String value) {
    if (value.trim().isEmpty) return context.tr('onboarding.required');
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      return context.tr('auth.pinDigitsOnly');
    }
    if (value.length < 4 || value.length > 8) {
      return context.tr('auth.pinLength');
    }
    return null;
  }

  /// A new PIN is exactly four digits (the current one may be older and longer).
  String? _newPinError(String value) {
    if (value.trim().isEmpty) return context.tr('onboarding.required');
    if (!RegExp(r'^\d{4}$').hasMatch(value)) {
      return context.tr('auth.pinExactlyFour');
    }
    return null;
  }

  Future<void> _refreshMemberData(MemberData data) async {
    final res = await AppScope.of(context).api.me();
    if (!mounted) return;
    data.update(
      (d) => d.me = MemberMeResponse.fromJson(
        Map<String, dynamic>.from(res as Map),
      ),
    );
    final updatedUser = Map<String, dynamic>.from(
      (res as Map)['user'] as Map? ?? {},
    );
    final token = AppScope.of(context).auth.token;
    if (token != null) {
      await AppScope.of(context).auth.signIn(token, updatedUser);
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showFFConfirmDialog(
      context,
      title: context.tr('home.signout'),
      message: context.tr('confirm.signout'),
      cancelLabel: context.tr('member.cancel'),
      confirmLabel: context.tr('home.signout'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await AppScope.of(context).auth.signOut();
    if (!mounted) return;
    context.go(AppRoutes.language);
  }

  Future<void> _openEditProfile() async {
    final data = MemberDataScope.of(context);
    final me = data.me;
    if (me == null) return;
    final saved = await openMemberEditProfile(context, me);
    if (saved == true && mounted) {
      try {
        await _refreshMemberData(data);
      } catch (_) {}
      if (mounted) {
        FFSnack.success(context, context.tr('member.profileUpdated'));
      }
    }
  }

  void _openWhatsAppSupport() {
    final uri = Uri.parse('https://wa.me/255786670499');
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openChangePinDialog() async {
    // FitFlex keeps the PIN: change it there. An account whose PIN is still
    // with Firebase (false) falls through to the old dialog below.
    if (AppScope.of(context).auth.pinLoginEnabled) {
      final messenger = FFSnack.of(context);
      final changedText = context.tr('pin.changed');
      final changed = await showChangePinDialog(context);
      if (changed == null || !mounted) return;
      if (changed) {
        messenger.info(changedText);
        return;
      }
    }
    final currentPinCtrl = TextEditingController();
    final newPinCtrl = TextEditingController();
    final confirmPinCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final authService = FirebaseAuthService();
    final email = MemberDataScope.of(context).me?.user.email ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var busy = false;
        String? error;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(context.tr('member.changePin')),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: currentPinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      validator: (value) => _pinError(value ?? ''),
                      decoration: InputDecoration(
                        labelText: context.tr('member.currentPin'),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: newPinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      validator: (value) => _newPinError(value ?? ''),
                      decoration: InputDecoration(
                        labelText: context.tr('member.newPin'),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmPinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      validator: (value) => value != newPinCtrl.text
                          ? context.tr('auth.pinMismatch')
                          : null,
                      decoration: InputDecoration(
                        labelText: context.tr('auth.confirmPin'),
                        counterText: '',
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      FFAlert(message: error!, tone: FFAlertTone.error),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx, false),
                child: Text(context.tr('member.cancel')),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await authService.updateEmailPassword(
                            email: email,
                            currentPassword: firebasePasswordForPin(
                              currentPinCtrl.text,
                            ),
                            newPassword: firebasePasswordForPin(
                              newPinCtrl.text,
                            ),
                          );
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } on FirebaseAuthException catch (e) {
                          setDialogState(() {
                            busy = false;
                            error = switch (e.code) {
                              'invalid-credential' || 'wrong-password' =>
                                context.tr('auth.invalidCredentials'),
                              _ => e.message ?? e.code,
                            };
                          });
                        } catch (e) {
                          setDialogState(() {
                            busy = false;
                            error = errorMessage(FFLocaleScope.of(context), e);
                          });
                        }
                      },
                child: busy
                    ? FFSpinner(size: 18)
                    : Text(context.tr('member.save')),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('member.pinUpdated'))));
    }
    await Future<void>.delayed(kThemeAnimationDuration);
    currentPinCtrl.dispose();
    newPinCtrl.dispose();
    confirmPinCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final me = data.me;
    final displayName =
        me?.user.resolvedName ?? context.tr('member.nameFallback');
    final passState = passStateFor(data);
    final stateMessage = passState == PassState.active
        ? null
        : passStateMessage(context, data, passState);
    final tier = data.subscription?.tier;
    final badge = FFBadge(
      key: const Key('profile-plan-badge'),
      label: data.subscription?.isDirect == true
          ? context.tr('member.plan_${data.subscription?.plan ?? 'monthly'}')
          : passState == PassState.pending
          ? context.tr('pass.pending')
          : tier != null && tier.isNotEmpty
          ? _tierLabel(context, tier)
          : context.tr('pass.state.noPass'),
      tone: passState.badgeTone,
      dot: true,
    );
    if (photoHeroUi) {
      return _buildPhotoHero(
        context,
        data,
        displayName: displayName,
        badge: badge,
        stateMessage: stateMessage,
        passState: passState,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        // Profile header
        FFCard(
          child: Row(
            children: [
              FFAvatar(
                name: displayName,
                src: me?.user.photoUrl,
                size: FFAvatarSize.lg,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    badge,
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (stateMessage != null) ...[
          FFAlert(
            key: const Key('profile-pass-state'),
            message: stateMessage,
            tone: passState.tone == PassTone.neutral
                ? FFAlertTone.info
                : FFAlertTone.warning,
          ),
          const SizedBox(height: 12),
        ],

        // Membership (A2/A3): plan, expiry date, days left, subscribed gym
        MembershipCard(subscription: data.subscription),
        const SizedBox(height: 12),

        ..._settings(context),
      ],
    );
  }

  /// Account settings, the tiles and Sign out (the same in both layouts).
  List<Widget> _settings(BuildContext context) => [
    // Settings
    FFSectionTitle(context.tr('member.accountSettings')),
    FFActionTile(
      key: const Key('profile-edit'),
      icon: Icons.edit,
      title: context.tr('member.editProfile'),
      subtitle: context.tr('member.editProfileSubtitle'),
      onTap: _openEditProfile,
    ),
    FFActionTile(
      key: const Key('profile-community'),
      icon: Icons.people_outline,
      title: context.tr('community.title'),
      subtitle: context.tr('community.profileHint'),
      onTap: () => context.push(AppRoutes.memberCommunity),
    ),
    FFActionTile(
      key: const Key('profile-benefits'),
      icon: Icons.volunteer_activism_outlined,
      title: context.tr('benefits.title'),
      subtitle: context.tr('benefits.tile'),
      onTap: () => context.push(AppRoutes.memberBenefits),
    ),
    FFActionTile(
      key: const Key('profile-sessions'),
      icon: Icons.event_repeat_outlined,
      title: context.tr('sessions.title'),
      subtitle: context.tr('sessions.tile'),
      onTap: () => context.push(AppRoutes.memberSessions),
    ),
    // Events S3 §4: always when registration is on.
    if (MemberDataScope.of(context).eventsDiscovery &&
        MemberDataScope.of(context).eventsOptions.registration)
      FFActionTile(
        key: const Key('profile-event-registrations'),
        icon: Icons.confirmation_number_outlined,
        title: context.tr('events.mine.title'),
        subtitle: context.tr('events.mine.empty.body'),
        onTap: () => context.push(AppRoutes.memberEventOrders),
      ),
    FFActionTile(
      key: const Key('profile-privacy'),
      icon: Icons.privacy_tip_outlined,
      title: context.tr('privacy.title'),
      onTap: () => context.go(AppRoutes.memberPrivacy),
    ),
    FFActionTile(
      icon: Icons.lock_outline,
      title: context.tr('member.changePin'),
      onTap: _openChangePinDialog,
    ),
    FFActionTile(
      icon: Icons.help_outline,
      title: context.tr('member.help'),
      onTap: _openWhatsAppSupport,
    ),
    const InvitationsTile(),
    const ContactDetailsTile(),
    const PersonaSwitcherTile(),
    const SizedBox(height: 16),
    OutlinedButton.icon(
      onPressed: _confirmSignOut,
      icon: Icon(Icons.logout, color: Theme.of(context).colorScheme.onSurface),
      label: Text(
        context.tr('home.signout'),
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      ),
    ),
    const SizedBox(height: FFTokens.spacingXs),
    const DeleteAccountButton(),
  ];

  /// PHOTO_HERO_UI (spec §21): avatar and name on a compact hero under the
  /// shell's transparent bar; the plan badge leads the solid content.
  Widget _buildPhotoHero(
    BuildContext context,
    MemberData data, {
    required String displayName,
    required Widget badge,
    required String? stateMessage,
    required PassState passState,
  }) {
    final me = data.me;
    final loading = me == null && !data.offline && !data.meLoadFailed;
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final avatar = Container(
      key: const Key('profile-hero-avatar'),
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        // 13.2:1 on the 86% text zone, so the edge shows on any photo.
        border: Border.fromBorderSide(
          BorderSide(color: FFTokens.heroText, width: 2),
        ),
      ),
      child: loading
          ? const ClipOval(
              child: SizedBox(
                width: 48,
                height: 48,
                child: FFSkeleton(width: 48, height: 48, radius: 24),
              ),
            )
          : FFAvatar(
              name: displayName,
              src: me?.user.photoUrl,
              size: FFAvatarSize.lg,
            ),
    );
    final height = MediaQuery.sizeOf(context).height;
    final topInset = memberHeroTopInset(context, data);
    final hero = FFPhotoHero(
      key: const Key('profile-hero'),
      photo: FFHeroPhoto.profile,
      variant: wide ? FFHeroVariant.panel : FFHeroVariant.compact,
      rounded: wide,
      minHeight: wide ? 0 : (height * 0.3).clamp(240.0, double.infinity),
      topInset: wide ? 0 : topInset,
      // Taller hero on phones (spec §5.3): clear photo above the name.
      clearPhoto: MediaQuery.sizeOf(context).width < 600
          ? heroTallClearTarget(height, scale)
          : 0,
      leading: avatar,
      eyebrow: context.tr('member.profile'),
      // The name, no accent: an accent-coloured name reads as a link.
      headlineLead: loading ? null : displayName,
      headlineLoading: loading,
      headlineMaxLines: scale > 1.15 ? 3 : 2,
    );
    final content = <Widget>[
      // Nothing loaded yet: no plan to name (never "No pass yet").
      if (me != null) ...[
        Align(alignment: Alignment.centerLeft, child: badge),
        const SizedBox(height: 12),
      ] else if (loading) ...[
        const Align(
          alignment: Alignment.centerLeft,
          child: FFSkeleton(
            key: Key('profile-badge-loading'),
            width: 120,
            height: 24,
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (me != null && stateMessage != null) ...[
        FFAlert(
          key: const Key('profile-pass-state'),
          message: stateMessage,
          tone: passState.tone == PassTone.neutral
              ? FFAlertTone.info
              : FFAlertTone.warning,
        ),
        const SizedBox(height: 12),
      ],
      MembershipCard(subscription: data.subscription),
      const SizedBox(height: 12),
      ..._settings(context),
    ];
    // PHOTO_FOOTER_UI (spec §33.6): once the profile has loaded.
    Widget? footer({required bool padded}) => photoFooterUi
        ? FFPhotoFooter.sliver(
            key: const Key('profile-footer'),
            pageKey: 'member.profile',
            top: FFHeroPhoto.profile,
            enabled: data.me != null,
            gap: padded
                ? FFTokens.spacingXl - FFTokens.spacingLg
                : FFTokens.spacingXl,
          )
        : null;
    if (wide) {
      return footerListView(
        key: const Key('profile-scroll'),
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        footer: footer(padded: true),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hero,
                  const SizedBox(height: FFTokens.spacingLg),
                  ...content,
                ],
              ),
            ),
          ),
        ],
      );
    }
    return HeroTabScroll(
      heroKey: _heroKey,
      child: footerListView(
        key: const Key('profile-scroll'),
        footer: footer(padded: false),
        children: [
          KeyedSubtree(key: _heroKey, child: hero),
          FFHeroSheet(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: content,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Premium" for a known tier, the raw value for one we have no label for.
String _tierLabel(BuildContext context, String tier) {
  final key = 'pass.$tier';
  final label = context.tr(key);
  return label == key ? tier : label;
}
