import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/tone_theme.dart';
import '../../shared/i18n.dart';
import '../../shared/photo_footer_flag.dart';
import '../../shared/photo_hero_flag.dart';
import '../../app_scope.dart';
import '../../shared/partner_media/partner_hero_builder.dart';
import '../../shared/partner_media/partner_media_flag.dart';
import '../../shared/partner_media/partner_media_models.dart';
import '../../shared/partner_media/partner_media_store.dart';
import 'owner_shell.dart';
import '../../shared/widgets/challenge_manager_page.dart';
import '../../shared/widgets/partner_details_widgets.dart';
import '../../shared/widgets/partner_not_verified.dart';
import '../member/member_group_page.dart' show openGroupManager;
import 'widgets/gym_engagement_widgets.dart';
import 'widgets/latest_checkins_card.dart';

/// PHOTO_HERO_UI (owner 2026-10-22, bands "too dark"): the band grows for
/// [FFTokens.heroBandClearPhoto] of clear photo above its text, but no taller
/// than this on a 390x844 screen, so Check-in (in the band) starts above
/// 55% of the screen
/// (FFHeroBand.maxHeightAt844).
const double ownerHomeBandMaxHeight = 417;

/// Owner dashboard home tab — shows stats, quick actions, and gym summary.
class OwnerHomeTab extends StatefulWidget {
  const OwnerHomeTab({super.key, this.now});

  /// Injectable clock for tests.
  final DateTime? now;

  @override
  State<OwnerHomeTab> createState() => _OwnerHomeTabState();
}

/// Named preset periods for the analytics date filter.
enum _DatePreset { today, yesterday, thisMonth, thisYear, custom }

class _OwnerHomeTabState extends State<OwnerHomeTab> {
  _DatePreset _activePreset = _DatePreset.thisMonth;

  /// Opens the analytics-style date range bottom sheet.
  Future<void> _showDateFilter() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FFTokens.radiusXl),
        ),
      ),
      builder: (ctx) => _DateFilterSheet(
        activePreset: _activePreset,
        onApply: (preset, from, to) async {
          _activePreset = preset;
          final data = OwnerDataScope.of(context);
          data.update((d) {
            d.statsFrom = from;
            d.statsTo = to;
          });
          final shell = context.findAncestorStateOfType<OwnerShellState>();
          await shell?.refreshDashboard();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  String _presetLabel(BuildContext context) {
    return switch (_activePreset) {
      _DatePreset.today => context.tr('owner.filterToday'),
      _DatePreset.yesterday => context.tr('owner.filterYesterday'),
      _DatePreset.thisMonth => context.tr('owner.filterThisMonth'),
      _DatePreset.thisYear => context.tr('owner.filterThisYear'),
      _DatePreset.custom => context.tr('owner.filterCustom'),
    };
  }

  /// Builds a trend label + direction from current vs previous period counts.
  /// Returns null if previous period has no data.
  (FFTrendDirection?, String?) _computeTrend(
    int current,
    int prev,
    BuildContext ctx,
  ) {
    if (prev == 0 && current == 0) return (null, null);
    if (prev == 0) {
      return (
        FFTrendDirection.up,
        ctx.tr('owner.trendUp').replaceAll('{pct}', '100'),
      );
    }
    final pct = ((current - prev) / prev * 100).round();
    if (pct > 0) {
      return (
        FFTrendDirection.up,
        ctx.tr('owner.trendUp').replaceAll('{pct}', pct.abs().toString()),
      );
    } else if (pct < 0) {
      return (
        FFTrendDirection.down,
        ctx.tr('owner.trendDown').replaceAll('{pct}', pct.abs().toString()),
      );
    } else {
      return (FFTrendDirection.neutral, ctx.tr('owner.trendFlat'));
    }
  }

  /// "Good evening, Rehema": the time of day and the first name (today's
  /// rule: the part before any "@", first word).
  String _greetingLine(BuildContext context, String rawName) {
    final cleanName = rawName.split('@').first.split(' ').first;
    final hour = (widget.now ?? DateTime.now()).hour;
    final greeting = context.tr(
      hour < 12
          ? 'member.goodMorning'
          : hour < 17
          ? 'member.goodAfternoon'
          : 'member.goodEvening',
    );
    return '$greeting, $cleanName';
  }

  bool _precached = false;

  /// The band, with the picked gym's saved photo and logo when
  /// PARTNER_MEDIA_UI is on (spec §40.4): read when Home is built, on a gym
  /// switch and when Home comes back into view, never swapped on screen.
  Widget _partnerBand(
    BuildContext context,
    OwnerData data,
    Widget Function(PartnerHeroMedia? media) band,
  ) {
    if (!partnerMediaUi) return band(null);
    final account = AppScope.of(context).auth.user?['id']?.toString();
    final gymId = data.activeGymId;
    return PartnerHeroBuilder(
      subject: account == null || gymId == null
          ? null
          : PartnerMediaSubject.gym(account, gymId),
      builder: (context, media) => band(media),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (photoHeroUi && !_precached) {
      _precached = true;
      precacheHeroPhotos(context, const [FFHeroPhoto.owner]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = OwnerDataScope.of(context);
    final dashboard = data.dashboard;
    final ownerGymList = data.ownerGyms;

    if (ownerGymList.isEmpty) {
      final title = context.tr('role.welcomeTitle');
      final hasBrand = title.contains('FitFlex');
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          // PHOTO_HERO_UI (spec §25.3): no approved gym yet, so a welcome
          // and no action; the unapproved card below says what is next.
          if (photoHeroUi) ...[
            FFHeroBand(
              key: const Key('owner-hero'),
              photo: FFHeroPhoto.owner,
              clearPhoto: FFTokens.heroBandClearPhoto,
              maxHeightAt844: ownerHomeBandMaxHeight,
              eyebrow: _greetingLine(context, data.displayName),
              headlineLead: hasBrand
                  ? title.replaceFirst('FitFlex', '').trim()
                  : title,
              headlineAccent: hasBrand ? 'FitFlex' : null,
            ),
            const SizedBox(height: FFTokens.spacingMd),
          ],
          FFGymUnapprovedCard(
            checking: data.loading,
            onRefresh: () async {
              final shell = context.findAncestorStateOfType<OwnerShellState>();
              await shell?.refreshAll();
            },
          ),
        ],
      );
    }

    final periodVisits = (dashboard?['periodVisits'] as num?)?.toInt() ?? 0;
    final periodMembers = (dashboard?['periodMembers'] as num?)?.toInt() ?? 0;
    // Real registered-member count for the active gym (not period-scoped) —
    // matches the Members page's stats.totalMembers. Used for the summary
    // card below; periodMembers (above) still feeds the trend detail chart.
    final totalMembers = (dashboard?['totalMembers'] as num?)?.toInt() ?? 0;
    final directCount = (dashboard?['directMembers'] as num?)?.toInt() ?? 0;
    final fitflexCount = (dashboard?['fitflexMembers'] as num?)?.toInt() ?? 0;
    // Parse chartSeries from API
    final rawSeries =
        (dashboard?['chartSeries'] as List<dynamic>?) ?? <dynamic>[];
    final chartLabels = rawSeries
        .map((e) => (e as Map<String, dynamic>)['label']?.toString() ?? '')
        .toList();
    final chartDirect = rawSeries
        .map(
          (e) =>
              ((e as Map<String, dynamic>)['direct'] as num?)?.toDouble() ??
              0.0,
        )
        .toList();
    final chartFitflex = rawSeries
        .map(
          (e) =>
              ((e as Map<String, dynamic>)['fitflex'] as num?)?.toDouble() ??
              0.0,
        )
        .toList();

    final prevPeriodVisits =
        (dashboard?['prevPeriodVisits'] as num?)?.toInt() ?? 0;
    final prevPeriodMembers =
        (dashboard?['prevPeriodMembers'] as num?)?.toInt() ?? 0;

    final (visitsTrendDir, visitsTrendLabel) = _computeTrend(
      periodVisits,
      prevPeriodVisits,
      context,
    );
    final (membersTrendDir, membersTrendLabel) = _computeTrend(
      periodMembers,
      prevPeriodMembers,
      context,
    );

    final greetingLine = _greetingLine(context, data.displayName);
    final hero = photoHeroUi;
    final gymName = data.ownerGyms
        .where((g) => g['id']?.toString() == data.activeGymId)
        .map((g) => g['name']?.toString())
        .firstOrNull;

    final bool showChart = directCount > 0 || fitflexCount > 0;

    return footerListView(
      padding: const EdgeInsets.symmetric(
        horizontal: FFTokens.spacingLg,
        vertical: FFTokens.spacingMd,
      ),
      // PHOTO_FOOTER_UI (spec §33.6): once the dashboard has loaded.
      footer: photoFooterUi
          ? FFPhotoFooter.sliver(
              key: const Key('owner-home-footer'),
              pageKey: 'owner.home',
              top: FFHeroPhoto.owner,
              enabled: dashboard != null,
              gap: FFTokens.spacingXl - FFTokens.spacingMd,
            )
          : null,
      children: [
        if (hero) ...[
          // PHOTO_HERO_UI (spec §25.3): the greeting and the daily job on a
          // band hero; numbers, chart and lists stay on solid ground.
          _partnerBand(
            context,
            data,
            (media) => FFHeroBand(
              key: const Key('owner-hero'),
              photo: FFHeroPhoto.owner,
              // PARTNER_MEDIA_UI (spec §40): the picked gym's own photo and
              // logo; null (bundled, no plate) without them.
              ownPhoto: media?.photo,
              logo: partnerLogoPlate(media?.logo),
              clearPhoto: FFTokens.heroBandClearPhoto,
              maxHeightAt844: ownerHomeBandMaxHeight,
              eyebrow: greetingLine,
              headlineLead: context.tr('hero.owner.lead'),
              headlineAccent: context.tr('hero.owner.accent'),
              actions: [
                FFButton(
                  key: const Key('owner-checkin-primary'),
                  icon: Icons.qr_code_scanner,
                  label: context.tr('owner.checkin'),
                  onPressed: () => context.push('/owner/scan'),
                ),
              ],
            ),
          ),
          const SizedBox(height: FFTokens.spacingMd),
        ],
        const PartnerNotVerifiedNotice(),
        // Partner date of birth: a dismissible ask, never blocking.
        if (!data.isStaff) const PartnerDobPromptCard(canEditGender: true),
        // Greeting follows the time of day; the date filter is the one
        // control that scopes everything below it.
        if (!hero) ...[
          Text(
            greetingLine,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: FFTokens.spacing2xs),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                // Under the flag the gym name stays in the app bar only.
                hero
                    ? context.tr('owner.gymSnapshot')
                    : gymName ?? context.tr('owner.gymSnapshot'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            InkWell(
              key: const Key('owner-date-filter'),
              onTap: _showDateFilter,
              borderRadius: BorderRadius.circular(FFTokens.radiusMd),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FFTokens.spacingSm,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        _presetLabel(context),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Icon(Icons.keyboard_arrow_down, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingMd),

        // The daily job first; the rest are one tap away below it.
        // DS v1.0 owner "Today" card: check-ins for the chosen period on
        // lime, and the day's job (scan a member in) as its button.
        if (!hero) ...[
          FFTodayCard(
            key: const Key('owner-today'),
            chipIcon: Icons.event_available,
            chipLabel: _presetLabel(context),
            value: '$periodVisits',
            valueLabel: context.tr('owner.checkins'),
            action: FFButton(
              key: const Key('owner-checkin-primary'),
              fullWidth: true,
              size: FFButtonSize.lg,
              icon: Icons.qr_code_scanner,
              label: context.tr('owner.checkin'),
              onPressed: () => context.push('/owner/scan'),
            ),
          ),
          const SizedBox(height: 4),
        ],
        FFCard(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: IntrinsicHeight(
            child: Row(
              children: [
                _buildQuickAction(
                  context,
                  icon: Icons.wallet_outlined,
                  title: context.tr('owner.earnings'),
                  onTap: () => context.push('/owner/earnings'),
                ),
                _buildActionDivider(context),
                if (data.canAccess('trainers')) ...[
                  _buildQuickAction(
                    context,
                    icon: Icons.sports_gymnastics_outlined,
                    title: context.tr('owner.trainers'),
                    onTap: () => context.go('/owner/trainers'),
                  ),
                  _buildActionDivider(context),
                ],
                _buildQuickAction(
                  context,
                  icon: Icons.people_outline,
                  title: context.tr('owner.members'),
                  onTap: () => context.go('/owner/members'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: FFTokens.spacingLg),

        // Summary cards — active, tap through to their screens.
        Row(
          children: [
            Expanded(
              child: InkWell(
                key: const Key('owner-card-total-members'),
                onTap: () => context.go('/owner/members'),
                borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                child: FFMetricCard(
                  label: context.tr('owner.totalMembers'),
                  value: '$totalMembers',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                key: const Key('owner-card-checkins'),
                onTap: () {
                  final gymId = data.activeGymId;
                  if (gymId != null) {
                    context.push('/owner/gyms/$gymId/checkins');
                  }
                },
                borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                child: FFMetricCard(
                  label: context.tr('owner.checkins'),
                  value: '$periodVisits',
                  trendDirection: visitsTrendDir,
                  trendLabel: visitsTrendLabel,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingLg),

        if (data.activeGymId != null && data.canAccess('checkins')) ...[
          LatestCheckinsCard(
            gymId: data.activeGymId!,
            version: identityHashCode(dashboard),
            onSeeAll: () =>
                context.push('/owner/gyms/${data.activeGymId}/checkins'),
          ),
          const SizedBox(height: FFTokens.spacingLg),
        ],

        // Membership insight: the one trend view, so it sits high.
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('owner.membershipOverview'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: FFTokens.spacingSm),
                  Text(
                    _presetLabel(context),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!showChart) ...[
                // Empty State
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Center(
                        child: Icon(
                          Icons.bar_chart_outlined,
                          size: 48,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.tr('owner.noMembershipData'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr('owner.noMembershipDataSub'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Legends
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _buildLegendItem(
                      context,
                      Theme.of(context).colorScheme.primary,
                      context.tr('owner.directMembers'),
                    ),
                    _buildLegendItem(
                      context,
                      FFToneTheme.of(context).info.dot,
                      context.tr('owner.fitflexRoaming'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Simple line chart using custom paint
                SizedBox(
                  height: 150,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: MembershipLineChartPainter(
                      directPoints: chartDirect,
                      fitflexPoints: chartFitflex,
                      labels: chartLabels,
                      isDark: Theme.of(context).brightness == Brightness.dark,
                      directColor: Theme.of(context).colorScheme.primary,
                      roamingColor: FFToneTheme.of(context).info.dot,
                      gridColor: Theme.of(context).colorScheme.outlineVariant,
                      labelColor: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant,
                      ringColor: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                // Insights underneath
                Row(
                  children: [
                    Expanded(
                      child: _buildChartDetail(
                        context,
                        bulletColor: Theme.of(context).colorScheme.primary,
                        title: context.tr('owner.directMembers'),
                        value: '$directCount',
                        trendDir: membersTrendDir,
                        trendPct: membersTrendLabel,
                      ),
                    ),
                    Container(
                      height: 45,
                      width: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    Expanded(
                      child: _buildChartDetail(
                        context,
                        bulletColor: FFToneTheme.of(context).info.dot,
                        title: context.tr('owner.fitflexRoaming'),
                        value: '$fitflexCount',
                        trendDir: visitsTrendDir,
                        trendPct: visitsTrendLabel,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: FFTokens.spacingLg),
        // Membership engagement from the gym's own check-ins.
        GymEngagementCard(
          gymId: data.activeGymId,
          onOpenMember: (id) => context.push('/owner/members/$id'),
        ),
        const SizedBox(height: FFTokens.spacingLg),
        // Secondary management jobs share one grouped card.
        FFCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              if (data.canAccess('communications')) ...[
                _manageRow(
                  key: const Key('owner-communications'),
                  icon: Icons.campaign_outlined,
                  title: context.tr('comms.title'),
                  subtitle: context.tr('comms.homeTile'),
                  onTap: () => context.push(
                    data.activeGymId == null
                        ? '/owner/communications'
                        : '/owner/communications?gymId=${data.activeGymId}',
                  ),
                ),
                const Divider(height: 1),
              ],
              _manageRow(
                key: const Key('owner-challenges'),
                icon: Icons.emoji_events_outlined,
                title: context.tr('challenge.manageTitle'),
                subtitle: context.tr('challenge.manageBody.owner'),
                onTap: () => openChallengeManager(
                  context,
                  scope: 'owner',
                  gymId: data.activeGymId,
                ),
              ),
              const Divider(height: 1),
              _manageRow(
                key: const Key('owner-groups'),
                icon: Icons.groups_outlined,
                title: context.tr('community.yourGroups'),
                subtitle: context.tr('community.ownerTile.owner'),
                onTap: () => openGroupManager(
                  context,
                  scope: 'owner',
                  gymId: data.activeGymId,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _manageRow({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      key: key,
      minVerticalPadding: FFTokens.spacingSm,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildQuickAction(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 24),
            const SizedBox(height: 8),
            Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildActionDivider(BuildContext context) {
    return VerticalDivider(
      width: 1,
      thickness: 1,
      indent: 8,
      endIndent: 8,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  Widget _buildLegendItem(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildChartDetail(
    BuildContext context, {
    required Color bulletColor,
    required String title,
    required String value,
    FFTrendDirection? trendDir,
    String? trendPct,
  }) {
    final theme = Theme.of(context);

    // Derive badge colours from trend direction
    final Color badgeBg;
    final Color badgeFg;
    final IconData badgeIcon;
    switch (trendDir) {
      case FFTrendDirection.down:
        badgeBg = theme.colorScheme.errorContainer;
        badgeFg = theme.colorScheme.onErrorContainer;
        badgeIcon = Icons.arrow_downward;
      case FFTrendDirection.neutral:
        badgeBg = theme.colorScheme.surfaceContainerHighest;
        badgeFg = theme.colorScheme.onSurfaceVariant;
        badgeIcon = Icons.remove;
      case FFTrendDirection.up:
      case null:
        badgeBg = FFToneTheme.of(context).success.bg;
        badgeFg = FFToneTheme.of(context).success.fg;
        badgeIcon = Icons.arrow_upward;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: bulletColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // In narrow tiles (and longer languages) the trend badge drops
          // under the number instead of overflowing; big numbers shrink.
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
              ),
              if (trendPct != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeIcon, size: 8, color: badgeFg),
                      const SizedBox(width: 1),
                      // The label is a phrase ("vs prev period"), long in
                      // Swahili: wrap rather than overflow the tile.
                      Flexible(
                        child: Text(
                          trendPct,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: badgeFg,
                            fontWeight: FontWeight.bold,
                            fontSize: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class MembershipLineChartPainter extends CustomPainter {
  MembershipLineChartPainter({
    required this.directPoints,
    required this.fitflexPoints,
    required this.labels,
    required this.isDark,
    required this.directColor,
    required this.roamingColor,
    required this.gridColor,
    required this.labelColor,
    required this.ringColor,
  });

  final List<double> directPoints;
  final List<double> fitflexPoints;
  final List<String> labels;
  final bool isDark;
  final Color directColor;
  final Color roamingColor;
  final Color gridColor;
  final Color labelColor;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    const double paddingLeft = 32.0;
    const double paddingBottom = 20.0;
    const double paddingTop = 10.0;
    const double paddingRight = 10.0;

    final double chartWidth = size.width - paddingLeft - paddingRight;
    final double chartHeight = size.height - paddingTop - paddingBottom;

    final int n = directPoints.length;
    if (n == 0) return;

    // Dynamic Y scale: next nice number above the max data value, minimum 5
    final double dataMax = [
      ...directPoints,
      ...fitflexPoints,
    ].fold<double>(0, (a, b) => b > a ? b : a);
    final double maxVal = dataMax <= 0 ? 5 : (dataMax * 1.2).ceilToDouble();

    // Nice round step for Y-axis grid (4 or 5 lines)
    final double rawStep = maxVal / 4;
    final double step = rawStep <= 1
        ? 1
        : rawStep <= 2
        ? 2
        : rawStep <= 5
        ? 5
        : rawStep <= 10
        ? 10
        : (rawStep / 10).ceil() * 10.0;
    final double adjustedMax = (maxVal / step).ceil() * step;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Horizontal grid lines + Y-axis labels
    int gridLines = (adjustedMax / step).round();
    for (int i = 0; i <= gridLines; i++) {
      final double yVal = i * step;
      final double y = paddingTop + chartHeight * (1 - yVal / adjustedMax);
      canvas.drawLine(
        Offset(paddingLeft, y),
        Offset(size.width - paddingRight, y),
        gridPaint,
      );
      textPainter.text = TextSpan(
        text: yVal.toInt().toString(),
        style: TextStyle(color: labelColor, fontSize: 11),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(paddingLeft - textPainter.width - 6, y - textPainter.height / 2),
      );
    }

    final double xStep = n > 1 ? chartWidth / (n - 1) : chartWidth;

    Offset getOffset(int index, double val) {
      final double x = paddingLeft + index * xStep;
      final double clamped = val > adjustedMax ? adjustedMax : val;
      final double y = paddingTop + chartHeight * (1 - clamped / adjustedMax);
      return Offset(x, y);
    }

    // Direct members — shaded gradient area
    final Path fillPath = Path();
    fillPath.moveTo(paddingLeft, paddingTop + chartHeight);
    for (int i = 0; i < n; i++) {
      final offset = getOffset(i, directPoints[i]);
      fillPath.lineTo(offset.dx, offset.dy);
    }
    fillPath.lineTo(paddingLeft + (n - 1) * xStep, paddingTop + chartHeight);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                directColor.withValues(alpha: 0.15),
                directColor.withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromLTWH(paddingLeft, paddingTop, chartWidth, chartHeight),
            ),
    );

    // Direct members — solid line
    final directLinePaint = Paint()
      ..color = directColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Path directPath = Path();
    directPath.moveTo(
      getOffset(0, directPoints[0]).dx,
      getOffset(0, directPoints[0]).dy,
    );
    for (int i = 1; i < n; i++) {
      final offset = getOffset(i, directPoints[i]);
      directPath.lineTo(offset.dx, offset.dy);
    }
    canvas.drawPath(directPath, directLinePaint);

    // Direct dots
    final dotOuterPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.fill;
    final dotPaintDirect = Paint()
      ..color = directColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < n; i++) {
      final offset = getOffset(i, directPoints[i]);
      canvas.drawCircle(offset, 4.0, dotOuterPaint);
      canvas.drawCircle(offset, 2.5, dotPaintDirect);
    }

    // FitFlex — dashed line
    final fitflexLinePaint = Paint()
      ..color = roamingColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Path fitflexPath = Path();
    fitflexPath.moveTo(
      getOffset(0, fitflexPoints[0]).dx,
      getOffset(0, fitflexPoints[0]).dy,
    );
    for (int i = 1; i < n; i++) {
      final offset = getOffset(i, fitflexPoints[i]);
      fitflexPath.lineTo(offset.dx, offset.dy);
    }
    _drawDashedPath(canvas, fitflexPath, fitflexLinePaint);

    // FitFlex dots
    final dotPaintFitflex = Paint()
      ..color = roamingColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < n; i++) {
      final offset = getOffset(i, fitflexPoints[i]);
      canvas.drawCircle(offset, 4.0, dotOuterPaint);
      canvas.drawCircle(offset, 2.5, dotPaintFitflex);
    }

    // X-axis labels from API
    for (int i = 0; i < labels.length && i < n; i++) {
      final offset = getOffset(i, 0);
      textPainter.text = TextSpan(
        text: labels[i],
        style: TextStyle(color: labelColor, fontSize: 11),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(offset.dx - textPainter.width / 2, paddingTop + chartHeight + 6),
      );
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const double dashWidth = 5.0;
    const double dashSpace = 3.0;
    final Path dashedPath = Path();

    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        dashedPath.addPath(
          metric.extractPath(distance, distance + dashWidth),
          Offset.zero,
        );
        distance += dashWidth + dashSpace;
      }
    }
    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(covariant MembershipLineChartPainter old) =>
      old.directPoints != directPoints ||
      old.fitflexPoints != fitflexPoints ||
      old.labels != labels ||
      old.isDark != isDark ||
      old.directColor != directColor ||
      old.roamingColor != roamingColor ||
      old.gridColor != gridColor ||
      old.labelColor != labelColor ||
      old.ringColor != ringColor;
}

// ─────────────────────────── Date Filter Bottom Sheet ────────────────────────

typedef _ApplyCallback =
    Future<void> Function(_DatePreset preset, DateTime from, DateTime to);

class _DateFilterSheet extends StatefulWidget {
  const _DateFilterSheet({required this.activePreset, required this.onApply});

  final _DatePreset activePreset;
  final _ApplyCallback onApply;

  @override
  State<_DateFilterSheet> createState() => _DateFilterSheetState();
}

class _DateFilterSheetState extends State<_DateFilterSheet> {
  late _DatePreset _selected;
  DateTimeRange? _customRange;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.activePreset;
  }

  DateTimeRange _rangeForPreset(_DatePreset preset) {
    final now = DateTime.now();
    return switch (preset) {
      _DatePreset.today => DateTimeRange(
        start: DateTime(now.year, now.month, now.day),
        end: DateTime(now.year, now.month, now.day, 23, 59, 59),
      ),
      _DatePreset.yesterday => () {
        final y = now.subtract(const Duration(days: 1));
        return DateTimeRange(
          start: DateTime(y.year, y.month, y.day),
          end: DateTime(y.year, y.month, y.day, 23, 59, 59),
        );
      }(),
      _DatePreset.thisMonth => DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
      ),
      _DatePreset.thisYear => DateTimeRange(
        start: DateTime(now.year, 1, 1),
        end: DateTime(now.year, 12, 31, 23, 59, 59),
      ),
      _DatePreset.custom =>
        _customRange ??
            DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
    };
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _customRange,
    );
    if (picked != null && mounted) {
      setState(() {
        _customRange = picked;
        _selected = _DatePreset.custom;
      });
    }
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    final range = _rangeForPreset(_selected);
    await widget.onApply(_selected, range.start, range.end);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presets = [
      (
        _DatePreset.today,
        context.tr('owner.filterToday'),
        Icons.today_outlined,
      ),
      (
        _DatePreset.yesterday,
        context.tr('owner.filterYesterday'),
        Icons.history_outlined,
      ),
      (
        _DatePreset.thisMonth,
        context.tr('owner.filterThisMonth'),
        Icons.calendar_month_outlined,
      ),
      (
        _DatePreset.thisYear,
        context.tr('owner.filterThisYear'),
        Icons.calendar_today_outlined,
      ),
    ];

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FFTokens.spacingLg,
                vertical: FFTokens.spacingSm,
              ),
              child: Text(
                context.tr('owner.selectDateRange'),
                style: theme.textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Preset chips grid (2 × 2)
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: FFTokens.spacingSm,
                    crossAxisSpacing: FFTokens.spacingSm,
                    childAspectRatio: 3.4,
                    children: presets.map((entry) {
                      final (preset, label, icon) = entry;
                      final isActive = _selected == preset;
                      return InkWell(
                        onTap: () => setState(() => _selected = preset),
                        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                        child: AnimatedContainer(
                          duration: FFTokens.motionFast,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.12,
                                  )
                                : theme.colorScheme.surfaceContainerHighest,
                            border: Border.all(
                              color: isActive
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              width: isActive ? 1.5 : 1,
                            ),
                            borderRadius: BorderRadius.circular(
                              FFTokens.radiusMd,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                icon,
                                size: 16,
                                color: isActive
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  label,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: isActive
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isActive
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: FFTokens.spacingSm),
                  // Custom range tile
                  InkWell(
                    onTap: _pickCustom,
                    borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                    child: AnimatedContainer(
                      duration: FFTokens.motionFast,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _selected == _DatePreset.custom
                            ? theme.colorScheme.primary.withValues(alpha: 0.12)
                            : theme.colorScheme.surfaceContainerHighest,
                        border: Border.all(
                          color: _selected == _DatePreset.custom
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: _selected == _DatePreset.custom ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.date_range_outlined,
                            size: 16,
                            color: _selected == _DatePreset.custom
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _customRange == null
                                  ? context.tr('owner.filterCustom')
                                  : '${_fmt(_customRange!.start)} → ${_fmt(_customRange!.end)}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: _selected == _DatePreset.custom
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _selected == _DatePreset.custom
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: FFTokens.spacingMd),
                  FFButton(
                    label: context.tr('owner.applyFilter'),
                    onPressed: _applying ? null : _apply,
                    loading: _applying,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
