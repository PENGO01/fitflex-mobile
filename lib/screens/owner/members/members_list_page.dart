// Members list screen (Gym Owner > Members tab). Pixel-aligned to the
// "Members Management Flow" design. UI only — all data/logic lives in
// [MemberListController] + [MemberRepository].

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../owner_shell.dart';
import 'data/member_models.dart';
import 'data/member_repository.dart';
import 'member_controller.dart';
import 'widgets/add_member_sheet.dart';
import 'widgets/filter_members_sheet.dart';
import 'widgets/member_list_tile.dart';
import '../../../shared/widgets/invitations.dart';

class OwnerMembersPage extends StatefulWidget {
  const OwnerMembersPage({super.key});

  @override
  State<OwnerMembersPage> createState() => _OwnerMembersPageState();
}

class _OwnerMembersPageState extends State<OwnerMembersPage> {
  MemberListController? _controller;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final activeGymId = OwnerDataScope.of(context).activeGymId;
    if (!_started) {
      _started = true;
      _controller = MemberListController(
        MemberRepository(AppScope.of(context).api),
        gymId: activeGymId,
      );
      _controller!.load();
      return;
    }
    // Owner switched the active gym from the shared action bar — reload
    // scoped to the new gym.
    _controller?.setActiveGym(activeGymId);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _controller?.setSearch(value);
    });
  }

  Future<void> _openFilters() async {
    final c = _controller!;
    final result = await openFilterMembersSheet(
      context,
      type: c.typeFilter,
      status: c.statusFilter,
    );
    if (result != null) {
      c.applyFilters(type: result.type, status: result.status);
    }
  }

  Future<void> _addMember() async {
    final owner = OwnerDataScope.of(context);
    final gyms = owner.ownerGyms;
    // Identity V2: invite the member; the plan starts when they accept.
    if (AppScope.of(context).auth.invitesEnabled && gyms.isNotEmpty) {
      final gymId = owner.activeGymId ?? gyms.first['id'].toString();
      final sent = await openInvitePersonSheet(
        context,
        gymId: gymId,
        role: 'member',
      );
      if (sent && mounted) await _controller!.refresh();
      return;
    }
    final payload = await openAddMemberSheet(context, gyms: gyms);
    if (payload == null || !mounted) return;
    final messenger = FFSnack.of(context);
    try {
      await _controller!.repository.createMember(payload);
      await _controller!.refresh();
      if (!mounted) return;
      messenger.success(context.tr('owner.memberAdded'));
    } on ApiException {
      if (!mounted) return;
      messenger.error(context.tr('owner.errorGeneric'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Center(child: FFSpinner());
    }
    return Stack(
      children: [
        SafeArea(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => RefreshIndicator(
              onRefresh: controller.refresh,
              child: _buildBody(context, controller),
            ),
          ),
        ),
        Positioned(
          right: FFTokens.spacingLg,
          bottom: FFTokens.spacingLg,
          child: _ScanQrButton(onTap: () => context.push('/owner/scan')),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, MemberListController c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        FFTokens.spacingLg,
        0,
        FFTokens.spacingLg,
        96,
      ),
      children: [
        Text(
          context.tr('members.title'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: FFTokens.spacingXs),
        Text(
          context.tr('members.subtitle'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        if (c.typeFilter != MemberTypeFilter.fitflex) ...[
          FFButton(
            label: context.tr('members.addMember'),
            onPressed: _addMember,
            icon: Icons.add,
          ),
          const SizedBox(height: FFTokens.spacingMd),
        ],
        _StatsRow(
          stats: c.stats,
          onTotal: () =>
              c.applyFilters(type: MemberTypeFilter.all, status: null),
          onActiveToday: () => c.applyFilters(
            type: MemberTypeFilter.all,
            status: OwnerMemberStatus.checkedIn,
          ),
          onExpiringSoon: () => c.applyFilters(
            type: MemberTypeFilter.all,
            status: OwnerMemberStatus.expiringSoon,
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        Row(
          children: [
            Expanded(
              child: FFTextField(
                controller: _searchCtrl,
                hint: context.tr('members.searchHint'),
                prefixIcon: const Icon(Icons.search, size: FFTokens.iconMd),
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            _FilterButton(active: c.hasActiveFilters, onTap: _openFilters),
          ],
        ),
        const SizedBox(height: FFTokens.spacingMd),
        _QuickFilterChips(controller: c),
        const SizedBox(height: FFTokens.spacingMd),
        if (c.loading && c.members.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: FFTokens.spacing2xl),
            child: Center(child: FFSpinner()),
          )
        else if (c.error != null)
          _ErrorState(onRetry: c.refresh)
        else if (c.isEmpty)
          _EmptyMembers(
            onAdd: c.typeFilter == MemberTypeFilter.fitflex ? null : _addMember,
            onScan: () => context.push('/owner/scan'),
          )
        else
          ...c.members.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
              child: MemberListTile(
                member: m,
                onTap: () => context.push('/owner/members/${m.id}'),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.stats,
    required this.onTotal,
    required this.onActiveToday,
    required this.onExpiringSoon,
  });

  final MemberStats stats;
  final VoidCallback onTotal;
  final VoidCallback onActiveToday;
  final VoidCallback onExpiringSoon;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: InkWell(
              key: const Key('stat-total-members'),
              onTap: onTotal,
              borderRadius: BorderRadius.circular(FFTokens.radiusLg),
              child: FFStatTile(
                icon: Icons.groups_outlined,
                value: '${stats.totalMembers}',
                label: context.tr('members.totalMembers'),
              ),
            ),
          ),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(
            child: InkWell(
              key: const Key('stat-active-today'),
              onTap: onActiveToday,
              borderRadius: BorderRadius.circular(FFTokens.radiusLg),
              child: FFStatTile(
                icon: Icons.trending_up,
                value: '${stats.activeToday}',
                label: context.tr('members.activeToday'),
              ),
            ),
          ),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(
            child: InkWell(
              key: const Key('stat-expiring-soon'),
              onTap: onExpiringSoon,
              borderRadius: BorderRadius.circular(FFTokens.radiusLg),
              child: FFStatTile(
                icon: Icons.schedule,
                value: '${stats.expiringSoon}',
                label: context.tr('members.expiringSoon'),
                accent: FFTokens.warning500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FFTokens.radiusMd),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : theme.colorScheme.surface,
          border: Border.all(
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        ),
        child: Icon(
          Icons.tune,
          size: FFTokens.iconMd,
          color: active
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _QuickFilterChips extends StatelessWidget {
  const _QuickFilterChips({required this.controller});

  final MemberListController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final chips = <(_QuickFilter, String)>[
      (_QuickFilter.all, context.tr('members.filterAll')),
      (_QuickFilter.direct, context.tr('members.tabDirect')),
      (_QuickFilter.fitflex, context.tr('members.tabFitflex')),
      (_QuickFilter.active, context.tr('status.active')),
      (_QuickFilter.expiringSoon, context.tr('status.expiringSoon')),
      (_QuickFilter.expired, context.tr('status.expired')),
    ];
    final selected = _resolveSelected(c);

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: FFTokens.spacingSm),
        itemBuilder: (context, i) {
          final chip = chips[i];
          return _Chip(
            label: chip.$2,
            selected: selected == chip.$1,
            onTap: () => _apply(c, chip.$1),
          );
        },
      ),
    );
  }

  _QuickFilter _resolveSelected(MemberListController c) {
    if (c.statusFilter == OwnerMemberStatus.active) return _QuickFilter.active;
    if (c.statusFilter == OwnerMemberStatus.expiringSoon) {
      return _QuickFilter.expiringSoon;
    }
    if (c.statusFilter == OwnerMemberStatus.expired) {
      return _QuickFilter.expired;
    }
    return switch (c.typeFilter) {
      MemberTypeFilter.direct => _QuickFilter.direct,
      MemberTypeFilter.fitflex => _QuickFilter.fitflex,
      MemberTypeFilter.all => _QuickFilter.all,
    };
  }

  void _apply(MemberListController c, _QuickFilter f) {
    switch (f) {
      case _QuickFilter.all:
        c.applyFilters(type: MemberTypeFilter.all, status: null);
      case _QuickFilter.direct:
        c.applyFilters(type: MemberTypeFilter.direct, status: null);
      case _QuickFilter.fitflex:
        c.applyFilters(type: MemberTypeFilter.fitflex, status: null);
      case _QuickFilter.active:
        c.applyFilters(
          type: MemberTypeFilter.all,
          status: OwnerMemberStatus.active,
        );
      case _QuickFilter.expiringSoon:
        c.applyFilters(
          type: MemberTypeFilter.all,
          status: OwnerMemberStatus.expiringSoon,
        );
      case _QuickFilter.expired:
        c.applyFilters(
          type: MemberTypeFilter.all,
          status: OwnerMemberStatus.expired,
        );
    }
  }
}

enum _QuickFilter { all, direct, fitflex, active, expiringSoon, expired }

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: FFTokens.motionFast,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: FFTokens.spacingMd),
        decoration: BoxDecoration(
          // FitFlex DS v1.0: a selected filter is a solid primary pill.
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surface,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(FFTokens.radiusFull),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ScanQrButton extends StatelessWidget {
  const _ScanQrButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primary,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 64,
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.qr_code_scanner,
                color: theme.colorScheme.onPrimary,
                size: FFTokens.iconLg,
              ),
              const SizedBox(height: 2),
              Text(
                context.tr('members.scanQrShort'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyMembers extends StatelessWidget {
  const _EmptyMembers({required this.onAdd, required this.onScan});

  final VoidCallback? onAdd;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingXl),
      child: FFEmptyState(
        title: context.tr('members.noMembersTitle'),
        body: context.tr('members.noMembersBody'),
        action: Column(
          children: [
            if (onAdd != null) ...[
              SizedBox(
                width: double.infinity,
                child: FFButton(
                  label: context.tr('members.addMember'),
                  onPressed: onAdd,
                ),
              ),
              const SizedBox(height: FFTokens.spacingSm),
            ],
            SizedBox(
              width: double.infinity,
              child: FFButton(
                label: context.tr('members.scanQr'),
                onPressed: onScan,
                variant: FFButtonVariant.secondary,
                icon: Icons.qr_code_scanner,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingXl),
      child: FFEmptyState(
        title: context.tr('members.errorLoading'),
        action: FFButton(
          label: context.tr('members.retry'),
          onPressed: onRetry,
          variant: FFButtonVariant.secondary,
        ),
      ),
    );
  }
}
