import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../../shared/inbox/inbox_pages.dart';
import '../../shared/models.dart';
import '../../shared/photo_footer_flag.dart';
import '../../shared/partner_media/partner_hero_builder.dart';
import '../partner/partner_media_entry_tile.dart';
import '../../shared/partner_media/partner_media_flag.dart';
import '../../shared/partner_media/partner_media_models.dart';
import '../../shared/partner_media/partner_media_store.dart';
import '../../shared/photo_hero_flag.dart';
import '../../shared/root_back_navigation.dart';
import '../../shared/widgets/partner_details_widgets.dart';
import '../../shared/widgets/partner_not_verified.dart';
import '../../router.dart';
import '../../shared/shop_home.dart';
import '../../shared/widgets/shop_browse_page.dart';
import '../../shared/widgets/social_links.dart';
import '../../shared/widgets/trainer_form_page.dart';
import '../language_screen.dart';
import '../member/member_message_settings_page.dart';
import '../member/member_scan_gym_page.dart';
import 'trainer_clients_tab.dart';
import 'trainer_enquiries_page.dart';
import 'trainer_gyms_tab.dart';
import 'trainer_passes_page.dart';
import 'trainer_payouts_page.dart';
import 'trainer_reviews_page.dart';
import 'trainer_schedule.dart';
import 'widgets/clients_digest.dart';
import 'widgets/trainer_sheets.dart';
import '../../shared/widgets/delete_account.dart';
import '../../shared/widgets/persona_switcher.dart';
import '../../shared/widgets/invitations.dart';
import '../../shared/widgets/verify_identifier.dart';
import '../pin_flows.dart';

/// PHOTO_HERO_UI (owner 2026-10-22, bands "too dark"): the band grows for
/// [FFTokens.heroBandClearPhoto] of clear photo above its text, but no taller
/// than this on a 390x844 screen, so the check-in buttons (in the band)
/// start above 55% of the screen
/// (FFHeroBand.maxHeightAt844).
const double trainerHomeBandMaxHeight = 469;

/// Standalone trainer dashboard shown after trainer is onboarded.
class TrainerHomePage extends StatefulWidget {
  const TrainerHomePage({super.key, this.open});

  /// The part to show first — where a notification leads: `clients`,
  /// `sessions`, `enquiries` or `payouts`.
  final String? open;

  @override
  State<TrainerHomePage> createState() => _TrainerHomePageState();
}

class _TrainerHomePageState extends State<TrainerHomePage> {
  Map<String, dynamic>? _me;
  List<Map<String, dynamic>> _trainers = [];

  /// The trainer's own profile from /trainer/me (works before approval too).
  Map<String, dynamic>? _profile;
  bool _started = false;
  int _tabIndex = 0;
  final _gymsTabKey = GlobalKey<TrainerGymsTabState>();

  /// Enquiries waiting for the trainer (badge on the Home tile).
  int _unreadEnquiries = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (photoHeroUi) precacheHeroPhotos(context, const [FFHeroPhoto.trainer]);
    _refreshAll();
    _show(widget.open);
  }

  @override
  void didUpdateWidget(TrainerHomePage old) {
    super.didUpdateWidget(old);
    // A notification tapped while already here.
    if (widget.open != old.open) _show(widget.open);
  }

  /// Opens the part of the home screen a notification is about.
  void _show(String? part) {
    if (part == null) return;
    if (part == 'clients') {
      setState(() => _tabIndex = 1);
      return;
    }
    // The shop's own links (`?open=shop&view=results…`): the Shop tab.
    if (part == 'shop') {
      setState(() => _tabIndex = 2);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (part) {
        case 'sessions':
          showTrainerSessionsSheet(context);
        case 'enquiries':
          _openEnquiries();
        case 'payouts':
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TrainerPayoutsPage()),
          );
      }
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _refreshMe(),
      _refreshTrainers(),
      _refreshProfile(),
      _refreshEnquiries(),
      if (_gymsTabKey.currentState != null) _gymsTabKey.currentState!.refresh(),
      AppScope.of(context).inbox?.load() ?? Future<void>.value(),
    ]);
  }

  Future<void> _refreshEnquiries() async {
    try {
      final rows = await AppScope.of(context).api.trainerEngagements();
      final unread = rows.whereType<Map>().where((r) => r['unread'] == true);
      if (mounted) setState(() => _unreadEnquiries = unread.length);
    } on ApiException {
      // ignore — the badge just stays as it was
    }
  }

  Future<void> _openEnquiries() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TrainerEnquiriesPage()),
    );
    if (mounted) _refreshEnquiries();
  }

  void _showMyQr() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const TrainerQrPage()));

  /// Scan the QR at the gym entrance (same check-in as a staff scan).
  Future<void> _scanGymQr() async {
    final checkedIn = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const MemberScanGymPage()));
    if (checkedIn == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('checkin.done'))));
    }
  }

  Future<void> _refreshProfile() async {
    try {
      final res = await AppScope.of(context).api.trainerMe();
      if (mounted) setState(() => _profile = res);
    } on ApiException {
      // ignore — falls back to the public trainer list
    }
  }

  Future<void> _refreshMe() async {
    try {
      final res = await AppScope.of(context).api.me();
      if (mounted) setState(() => _me = res);
    } on ApiException {
      // ignore
    }
  }

  Future<void> _refreshTrainers() async {
    try {
      final res = await AppScope.of(context).api.listTrainers();
      if (mounted) {
        setState(() => _trainers = res.cast<Map<String, dynamic>>());
      }
    } on ApiException {
      // ignore
    }
  }

  String get _displayName {
    final user = (_me?['user'] as Map?) ?? AppScope.of(context).auth.user;
    return (user?['displayName'] ??
            user?['email'] ??
            user?['phone'] ??
            'Trainer')
        .toString();
  }

  Map<String, dynamic>? get _myProfile {
    if (_profile != null) return _profile;
    final email = AppScope.of(context).auth.user?['email']?.toString();
    // No email on the account (phone sign-in) must not match a trainer whose
    // email is also missing — that would be someone else's profile.
    if (email == null || email.isEmpty) return null;
    return _trainers.where((t) => t['email']?.toString() == email).firstOrNull;
  }

  Future<void> _signOut() async {
    final confirmed = await showFFConfirmDialog(
      context,
      title: context.tr('home.signout'),
      message: context.tr('confirm.signout'),
      cancelLabel: context.tr('member.cancel'),
      confirmLabel: context.tr('home.signout'),
      destructive: true,
      confirmKey: const Key('trainer-confirm-sign-out'),
    );
    if (confirmed != true || !mounted) return;
    await AppScope.of(context).auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LanguageScreen()),
      (_) => false,
    );
  }

  void _openWhatsAppSupport() {
    final uri = Uri.parse('https://wa.me/255786670499');
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Edit profile: one form for the trainer's name, nickname, phone, photos,
  /// rate, specialties, bio, social handles and availability. The account's
  /// name and phone follow what is saved here.
  Future<void> _editProfessionalProfile() async {
    // The profile may not have loaded yet (slow network, or it was only just
    // linked to this account): fetch it rather than doing nothing.
    if (_myProfile == null) await _refreshProfile();
    if (!mounted) return;
    final trainer = _myProfile;
    if (trainer == null) {
      FFSnack.info(context, context.tr('trainer.profileNotLoaded'));
      return;
    }
    final payload = await openTrainerForm(
      context,
      title: context.tr('trainer.editProfile'),
      initial: trainer,
      selfEdit: true,
    );
    if (payload == null || !mounted) return;
    try {
      final result = await AppScope.of(
        context,
      ).api.trainerUpdateProfile(payload);
      if (!mounted) return;
      final updated = result['trainer'] ?? result;
      if (updated is Map<String, dynamic>) {
        setState(() {
          _profile = updated;
          _trainers = _trainers
              .map((item) => item['id'] == updated['id'] ? updated : item)
              .toList();
        });
      }
      FFSnack.success(context, context.tr('member.profileUpdated'));
      await _syncAccount(payload);
    } on ApiException catch (e) {
      if (!mounted) return;
      final code = e.body is Map ? (e.body as Map)['error']?.toString() : null;
      const known = {
        'invalid_social_handle': 'social.invalidHandle',
        'invalid_phone': 'trainer.error.invalidPhone',
        'invalid_rate': 'trainer.error.invalidRate',
        'too_many_images': 'trainer.error.tooManyPhotos',
        'displayName_required': 'trainer.error.nameRequired',
        'invalid_nickname': 'trainer.nicknameInvalid',
        'trainer_profile_not_found': 'trainer.profileNotLoaded',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            known.containsKey(code)
                ? context.tr(known[code]!)
                : errorMessage(FFLocaleScope.of(context), e),
          ),
        ),
      );
    }
  }

  /// Keep the sign-in account's name and phone the same as the profile just
  /// saved (there is one form for both). The profile is already saved, so a
  /// failure here is not shown.
  Future<void> _syncAccount(Map<String, dynamic> payload) async {
    final name = payload['displayName']?.toString().trim() ?? '';
    final phone = payload['phone']?.toString().trim() ?? '';
    if (name.isEmpty) return;
    try {
      await AppScope.of(context).api.updateProfile({
        'displayName': name,
        if (phone.isNotEmpty) 'phone': phone,
      });
      if (mounted) await _refreshMe();
    } on ApiException {
      // The trainer profile is saved; the account keeps its earlier details.
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        handleRootBack(didPop: didPop);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(context.tr('trainer.dashboard')),
          // Bookings, pass approvals, and FitFlex promotions and news.
          actions: [
            IconButton(
              key: const Key('trainer-appbar-qr'),
              tooltip: context.tr('checkin.showQr'),
              onPressed: _showMyQr,
              icon: const Icon(Icons.qr_code_2),
            ),
            const InboxBellButton(),
            const AppPrefsButtons(),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refreshAll,
          child: IndexedStack(
            index: _tabIndex,
            children: [
              _dashboardTab(),
              const TrainerClientsTab(),
              const ShopBrowseBody(
                mode: ShopHomeMode.trainer,
                routePath: AppRoutes.trainerHome,
                routeQuery: {'open': 'shop'},
              ),
              TrainerGymsTab(
                key: _gymsTabKey,
                onProfileChanged: _refreshProfile,
              ),
              _profileTab(),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: (index) => setState(() => _tabIndex = index),
          destinations: [
            NavigationDestination(
              key: const Key('trainer-nav-home'),
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: context.tr('member.home'),
            ),
            NavigationDestination(
              key: const Key('trainer-nav-clients'),
              icon: const Icon(Icons.groups_outlined),
              selectedIcon: const Icon(Icons.groups),
              label: context.tr('clients.title'),
            ),
            NavigationDestination(
              key: const Key('trainer-nav-shop'),
              icon: const Icon(Icons.storefront_outlined),
              selectedIcon: const Icon(Icons.storefront),
              label: context.tr('member.shop'),
            ),
            NavigationDestination(
              key: const Key('trainer-nav-gyms'),
              icon: const Icon(Icons.fitness_center_outlined),
              selectedIcon: const Icon(Icons.fitness_center),
              label: context.tr('trainer.gyms'),
            ),
            NavigationDestination(
              key: const Key('trainer-nav-profile'),
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: context.tr('trainer.profile'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabScroll(List<Widget> children) => ListView(
    padding: const EdgeInsets.all(FFTokens.spacingLg),
    children: children,
  );

  /// The Home band, with the trainer's saved photo and logo when
  /// PARTNER_MEDIA_UI is on (spec §40.4): read when Home is built or comes
  /// back into view (a tab switch, a page closing), never swapped on screen.
  Widget _partnerBand(Widget Function(PartnerHeroMedia? media) band) {
    if (!partnerMediaUi) return band(null);
    final account = AppScope.of(context).auth.user?['id']?.toString();
    return PartnerHeroBuilder(
      subject: account == null ? null : PartnerMediaSubject.trainer(account),
      visible: _tabIndex == 0,
      builder: (context, media) => band(media),
    );
  }

  Widget _dashboardTab() {
    final trainer = _myProfile;
    final socials = SocialLinks.fromJson(trainer?['socialLinks']);
    final gyms = (trainer?['gyms'] as List?)?.whereType<Map>().toList() ?? [];
    return footerListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      // PHOTO_FOOTER_UI (spec §33.6): Home tab only; the dashboard needs no
      // list, so always enabled.
      footer: photoFooterUi
          ? FFPhotoFooter.sliver(
              key: const Key('trainer-home-footer'),
              pageKey: 'trainer.home',
              top: FFHeroPhoto.trainer,
              gap: FFTokens.spacingXl - FFTokens.spacingLg,
            )
          : null,
      children: [
        if (photoHeroUi) ...[
          // PHOTO_HERO_UI (spec §25.1): the hero carries the gym check-in; the
          // QR itself opens in its own solid sheet, never on the photo.
          _partnerBand(
            (media) => FFHeroBand(
              key: const Key('trainer-hero'),
              photo: FFHeroPhoto.trainer,
              // PARTNER_MEDIA_UI (spec §40): the trainer's own photo and
              // logo; null (bundled, no plate) without them.
              ownPhoto: media?.photo,
              logo: partnerLogoPlate(media?.logo),
              clearPhoto: FFTokens.heroBandClearPhoto,
              maxHeightAt844: trainerHomeBandMaxHeight,
              eyebrow: heroGreeting(
                context,
                DateTime.now(),
                trainer?['displayName']?.toString() ?? _displayName,
              ),
              headlineLead: context.tr('hero.trainer.lead'),
              headlineAccent: context.tr('hero.trainer.accent'),
              subline: context.tr('checkin.body'),
              actions: [
                FFButton(
                  key: const Key('trainer-checkin-scan'),
                  label: context.tr('checkin.scan'),
                  icon: Icons.qr_code_scanner,
                  onPressed: _scanGymQr,
                ),
                FFButton(
                  key: const Key('trainer-checkin-qr'),
                  label: context.tr('checkin.showQr'),
                  icon: Icons.qr_code_2,
                  variant: FFButtonVariant.onPhoto,
                  onPressed: _showMyQr,
                ),
              ],
            ),
          ),
          const SizedBox(height: FFTokens.spacingMd),
        ],
        const PartnerNotVerifiedNotice(),
        // Partner date of birth: a dismissible ask, never blocking.
        const PartnerDobPromptCard(canEditGender: false),
        // Quick gym access: show the check-in QR, or scan the gym's QR.
        if (!photoHeroUi)
          FFCard(
            key: const Key('trainer-checkin-card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.door_front_door_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      context.tr('checkin.title'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr('checkin.body'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('trainer-checkin-qr'),
                        onPressed: _showMyQr,
                        icon: const Icon(Icons.qr_code_2, size: 18),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(context.tr('checkin.showQr')),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('trainer-checkin-scan'),
                        onPressed: _scanGymQr,
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(context.tr('checkin.scan')),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text(
          context.tr('trainer.dashboardBody'),
          style: TextStyle(
            color: Theme.of(context).textTheme.bodySmall?.color,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('trainer.profile'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                trainer?['displayName']?.toString() ?? _displayName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                (trainer?['specialties'] as List? ?? []).join(' / '),
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FFPill(
                    key: const Key('trainer-rate-per-session'),
                    label:
                        '${formatCurrency(trainer?['hourlyRateTzs'] as num? ?? 0, currency: trainer?['sessionRateCurrency'] as String? ?? 'TZS')}${context.tr('trainerReg.perSession')}',
                  ),
                  const Spacer(),
                  SocialLinksRow(links: socials, compact: true),
                ],
              ),
              if (trainer != null && socials.isEmpty)
                FFButton(
                  key: const Key('trainer-add-socials'),
                  label: context.tr('social.addPrompt'),
                  onPressed: _editProfessionalProfile,
                  variant: FFButtonVariant.ghost,
                  size: FFButtonSize.sm,
                  icon: Icons.add_link,
                ),
            ],
          ),
        ),
        ClientsDigest(onOpenClients: () => setState(() => _tabIndex = 1)),
        const SizedBox(height: 12),
        FFMetricCard(
          value: '${gyms.length}',
          label: context.tr('trainer.linkedGymsCount'),
        ),
        _section(context.tr('trainer.sessions')),
        FFActionTile(
          key: const Key('trainer-tile-sessions'),
          icon: Icons.event_available,
          title: context.tr('trainer.todaySessions'),
          onTap: () => showTrainerSessionsSheet(context),
        ),
        FFActionTile(
          key: const Key('trainer-tile-earnings'),
          icon: Icons.payments_outlined,
          title: context.tr('trainer.earnings'),
          onTap: () => showTrainerEarningsSheet(context),
        ),
        FFActionTile(
          key: const Key('trainer-tile-payouts'),
          icon: Icons.account_balance_wallet_outlined,
          title: context.tr('payouts.title'),
          subtitle: context.tr('payouts.tile'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TrainerPayoutsPage()),
          ),
        ),
        FFActionTile(
          key: const Key('trainer-engagement-inbox'),
          icon: Icons.mark_email_unread_outlined,
          title: context.tr('trainer.enquiries'),
          subtitle: _unreadEnquiries > 0
              ? context
                    .tr('enquiry.unreadCount')
                    .replaceAll('{n}', '$_unreadEnquiries')
              : null,
          trailing: _unreadEnquiries > 0
              ? Badge(
                  key: const Key('trainer-enquiries-badge'),
                  label: Text('$_unreadEnquiries'),
                )
              : null,
          onTap: _openEnquiries,
        ),
        FFActionTile(
          key: const Key('trainer-tile-schedule'),
          icon: Icons.calendar_month_outlined,
          title: context.tr('cal.mySchedule'),
          subtitle: context.tr('trainer.scheduleTileHint'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const TrainerSessionsPage(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _profileTab() => _tabScroll([
    Text(
      context.tr('trainer.profile'),
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 12),
    FFActionTile(
      key: const Key('trainer-tile-professional'),
      icon: Icons.edit_outlined,
      title: context.tr('trainer.editProfile'),
      subtitle: context.tr('trainer.editProfessionalHint'),
      onTap: _editProfessionalProfile,
    ),
    // PARTNER_MEDIA_UI (spec §41.1): nothing with the flag off.
    if (partnerMediaUi) const PartnerMediaEntryTile(side: 'trainer'),
    // The trainer's social profiles, as members see them (tap to open).
    if (!SocialLinks.fromJson(_myProfile?['socialLinks']).isEmpty)
      Padding(
        key: const Key('trainer-profile-socials'),
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
        child: SocialLinksRow(
          links: SocialLinks.fromJson(_myProfile?['socialLinks']),
        ),
      ),
    FFActionTile(
      key: const Key('trainer-reviews'),
      icon: Icons.star_outline,
      title: context.tr('reviews.myReviews'),
      subtitle: context.tr('reviews.myReviewsHint'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TrainerReviewsPage()),
      ),
    ),
    FFActionTile(
      key: const Key('trainer-verification'),
      icon: Icons.verified_user_outlined,
      title: context.tr('kyc.entry.title'),
      subtitle: context.tr('kyc.entry.subtitle'),
      onTap: () => context.push('/verification'),
    ),
    FFActionTile(
      key: const Key('trainer-message-settings'),
      icon: Icons.notifications_outlined,
      title: context.tr('msgPrefs.title'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const MemberMessageSettingsPage(),
        ),
      ),
    ),
    FFActionTile(
      key: const Key('trainer-help'),
      icon: Icons.help_outline,
      title: context.tr('member.help'),
      onTap: _openWhatsAppSupport,
    ),
    const InvitationsTile(),
    const ContactDetailsTile(),
    const ChangePinTile(),
    const PartnerDetailsTile(canEditGender: false),
    const PersonaSwitcherTile(),
    const SizedBox(height: 16),
    FFButton(
      key: const Key('trainer-sign-out'),
      label: context.tr('home.signout'),
      onPressed: _signOut,
      variant: FFButtonVariant.secondary,
      icon: Icons.logout,
    ),
    const SizedBox(height: FFTokens.spacingXs),
    const DeleteAccountButton(),
  ]);

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    ),
  );
}
