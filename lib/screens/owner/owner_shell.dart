import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../shared/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/i18n.dart';
import '../../shared/partner_media/partner_media_flag.dart';
import '../../shared/root_back_navigation.dart';

export 'owner_checkins_page.dart';
export 'owner_earnings_page.dart';
export 'owner_home_tab.dart';
export 'owner_manage_gyms_page.dart';
export 'owner_profile_page.dart';
export 'owner_trainers_page.dart';

/// RBAC scopes assignable to gym staff (receptionists etc.) — mirrors the
/// backend's GYM_STAFF_ACL_SCOPES in fitflex-functions/functions/index.mjs.
const List<String> kGymStaffAclScopes = [
  'members',
  'checkins',
  'payments',
  'trainers',
  'gyms',
  'shop',
  'communications',
];

/// Shared owner data that all owner tabs can access.
class OwnerData extends ChangeNotifier {
  Map<String, dynamic>? me;
  Map<String, dynamic>? dashboard;
  List<Map<String, dynamic>> ownerGyms = [];
  List<Map<String, dynamic>> ownerTrainers = [];
  List<Map<String, dynamic>> pendingTrainerRequests = [];
  bool loading = false;

  /// The gym currently "in view" across every owner page (Home, Manage Gyms,
  /// Members, Trainers, Earnings, ...). Persisted locally so it survives app
  /// restarts — see [OwnerShellState.setActiveGym].
  String? activeGymId;
  String dashboardMemberType = 'all';
  DateTime? statsFrom;
  DateTime? statsTo;

  String get displayName {
    final user = me?['user'] as Map?;
    return (user?['displayName'] ??
            user?['email'] ??
            user?['phone'] ??
            FFLocale.text('common.owner'))
        .toString();
  }

  /// True for gym-level staff (receptionists etc.) created by an owner.
  /// A real gym owner (`gym_operator`) is always unrestricted.
  bool get isStaff => (me?['user'] as Map?)?['userType'] == 'gym_staff';

  List<String> get aclPermissions =>
      ((me?['user'] as Map?)?['aclPermissions'] as List?)
          ?.map((e) => e.toString())
          .toList() ??
      const [];

  /// Whether the current user can access a feature scope. Owners always can;
  /// staff need the matching scope in [aclPermissions].
  bool canAccess(String scope) => !isStaff || aclPermissions.contains(scope);

  /// The active gym's row from GET /owner/gyms, or null when there is none.
  Map<String, dynamic>? get activeGym {
    for (final g in ownerGyms) {
      if (g['id']?.toString() == activeGymId) return g;
    }
    return null;
  }

  /// Display name of the active gym, falling back to the first owned gym.
  String activeGymName(String fallbackLabel) {
    if (ownerGyms.isEmpty) return fallbackLabel;
    final match = ownerGyms.firstWhere(
      (g) => g['id']?.toString() == activeGymId,
      orElse: () => ownerGyms.first,
    );
    return match['name']?.toString() ?? fallbackLabel;
  }

  void update(void Function(OwnerData d) fn) {
    fn(this);
    notifyListeners();
  }
}

/// InheritedWidget exposing shared owner data to subtree.
class OwnerDataScope extends InheritedNotifier<OwnerData> {
  const OwnerDataScope({
    super.key,
    required OwnerData data,
    required super.child,
  }) : super(notifier: data);

  static OwnerData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<OwnerDataScope>();
    assert(scope != null, 'OwnerDataScope missing');
    return scope!.notifier!;
  }

  static OwnerData? maybeOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<OwnerDataScope>();
    return scope?.notifier;
  }
}

/// Bottom navigation shell for owner screens.
class OwnerShell extends StatefulWidget {
  const OwnerShell({super.key, required this.state, required this.child});

  final GoRouterState state;
  final Widget child;

  @override
  OwnerShellState createState() => OwnerShellState();
}

/// Definition for a single bottom-nav destination in [OwnerShell]. When
/// [scope] is non-null the destination is hidden entirely for gym staff who
/// don't have that ACL permission (owners always see every tab).
class _OwnerTabDef {
  const _OwnerTabDef({
    required this.route,
    required this.icon,
    required this.selectedIcon,
    required this.labelKey,
    required this.titleKey,
    this.scope,
  });

  final String route;
  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
  final String titleKey;
  final String? scope;
}

const _kOwnerTabs = [
  _OwnerTabDef(
    route: '/owner/home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    labelKey: 'owner.home',
    titleKey: 'owner.dashboard',
  ),
  _OwnerTabDef(
    route: '/owner/gyms',
    icon: Icons.fitness_center_outlined,
    selectedIcon: Icons.fitness_center,
    labelKey: 'owner.manageGyms',
    titleKey: 'owner.manageGyms',
    scope: 'gyms',
  ),
  _OwnerTabDef(
    route: '/owner/members',
    icon: Icons.people_outlined,
    selectedIcon: Icons.people,
    labelKey: 'owner.members',
    titleKey: 'owner.members',
    scope: 'members',
  ),
  _OwnerTabDef(
    route: '/owner/shop',
    icon: Icons.storefront_outlined,
    selectedIcon: Icons.storefront,
    labelKey: 'owner.shop',
    titleKey: 'owner.shop',
  ),
];

class OwnerShellState extends State<OwnerShell> {
  final OwnerData _data = OwnerData();
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _data.addListener(_onDataChanged);
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  /// Tabs visible to the current user — every tab for a real owner, only the
  /// ACL-permitted ones for gym staff.
  List<_OwnerTabDef> get _visibleTabs => _kOwnerTabs
      .where((t) => t.scope == null || _data.canAccess(t.scope!))
      .toList();

  int get _tabIndex {
    final loc = GoRouterState.of(context).matchedLocation;
    final tabs = _visibleTabs;
    for (var i = 0; i < tabs.length; i++) {
      if (i > 0 && loc.startsWith(tabs[i].route)) return i;
    }
    return 0;
  }

  String get _title {
    // Trainers is reached from Home, not a tab, but still needs its title.
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/owner/trainers')) return context.tr('owner.trainers');
    return context.tr(_visibleTabs[_tabIndex].titleKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    refreshAll();
  }

  @override
  void dispose() {
    _data.removeListener(_onDataChanged);
    _data.dispose();
    super.dispose();
  }

  Future<void> refreshAll() async {
    _data.update((d) => d.loading = true);
    try {
      await Future.wait([_refreshMe(), _refreshOwnerGyms()]);
      await _restoreActiveGym();
      await Future.wait([
        refreshDashboard(),
        _refreshOwnerTrainers(),
        _refreshPendingTrainers(),
      ]);
    } finally {
      _data.update((d) => d.loading = false);
    }
  }

  /// Select the first owned gym after fresh data loads. The selection stays
  /// in memory only so it cannot become stale between sessions.
  Future<void> _restoreActiveGym() async {
    if (_data.ownerGyms.isEmpty) return;
    final ownedIds = _data.ownerGyms.map((g) => g['id']?.toString()).toSet();
    // A notification that opened a gym's photo page, then Back from a cold
    // start (`/owner/home?gymId=`, spec §41.1): that gym, if it is theirs.
    final linked = partnerMediaUi
        ? widget.state.uri.queryParameters['gymId']
        : null;
    if (_data.activeGymId == null && ownedIds.contains(linked)) {
      _data.activeGymId = linked;
    }
    if (_data.activeGymId == null || !ownedIds.contains(_data.activeGymId)) {
      _data.activeGymId = _data.ownerGyms.first['id']?.toString();
    }
  }

  /// Switches the active gym across every owner page,
  /// and refreshes the gym-scoped data (dashboard + trainers). Members list
  /// and Earnings listen to [OwnerData] and reload themselves.
  Future<void> setActiveGym(String gymId) async {
    if (_data.activeGymId == gymId) return;
    _data.update((d) => d.activeGymId = gymId);
    await Future.wait([
      refreshDashboard(),
      _refreshOwnerTrainers(),
      _refreshPendingTrainers(),
    ]);
    if (mounted) setState(() {});
  }

  Future<void> _refreshMe() async {
    try {
      final res = await AppScope.of(context).api.me();
      _data.me = res;
    } on ApiException {
      // ignore
    }
  }

  Future<void> _refreshOwnerGyms() async {
    try {
      final res = await AppScope.of(context).api.ownerGyms();
      _data.ownerGyms = res.cast<Map<String, dynamic>>();
    } on ApiException {
      // ignore
    }
  }

  Future<void> refreshDashboard() async {
    try {
      String dateOnly(DateTime v) => v.toIso8601String().split('T').first;
      final res = await AppScope.of(context).api.operatorDashboard(
        gymId: _data.activeGymId,
        periodStart: _data.statsFrom == null
            ? null
            : dateOnly(_data.statsFrom!),
        periodEnd: _data.statsTo == null ? null : dateOnly(_data.statsTo!),
        memberType: _data.dashboardMemberType,
      );
      _data.dashboard = res;
    } on ApiException {
      // ignore
    }
  }

  Future<void> _refreshOwnerTrainers() async {
    if (!_data.canAccess('trainers')) return;
    try {
      final res = await AppScope.of(
        context,
      ).api.ownerTrainers(gymId: _data.activeGymId);
      _data.ownerTrainers = res.cast<Map<String, dynamic>>();
    } on ApiException {
      // ignore
    }
  }

  Future<void> _refreshPendingTrainers() async {
    if (!_data.canAccess('trainers')) return;
    try {
      final res = await AppScope.of(context).api.ownerPendingTrainers();
      _data.pendingTrainerRequests = res.cast<Map<String, dynamic>>();
    } on ApiException {
      // ignore
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return 'O';
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  void _onTab(int index) {
    final tabs = _visibleTabs;
    if (_data.ownerGyms.isEmpty && index != 0) {
      FFSnack.info(context, context.tr('owner.notApprovedYet'));
      return;
    }
    context.go(tabs[index].route);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _visibleTabs;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        handleRootBack(didPop: didPop);
      },
      child: OwnerDataScope(
        data: _data,
        child: Scaffold(
          appBar: FFOwnerDashboardBar(
            selectedGymName: _data.activeGymName(context.tr('owner.gym')),
            initials: _getInitials(_data.displayName),
            ownerGyms: _data.ownerGyms,
            subtitleLabel: _title,
            onGymSelected: (gymId) => setActiveGym(gymId),
            onAvatarTap: () => context.push(
              partnerMediaUi && _data.activeGymId != null
                  ? Uri(
                      path: '/owner/profile',
                      queryParameters: {'gymId': _data.activeGymId!},
                    ).toString()
                  : '/owner/profile',
            ),
          ),
          body: RefreshIndicator(onRefresh: refreshAll, child: widget.child),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tabIndex,
            onDestinationSelected: _onTab,
            destinations: [
              for (final tab in tabs)
                NavigationDestination(
                  icon: Icon(
                    tab.icon,
                    color: _data.ownerGyms.isEmpty && tab.route != '/owner/home'
                        ? Theme.of(context).disabledColor
                        : null,
                  ),
                  selectedIcon: Icon(
                    tab.selectedIcon,
                    color: _data.ownerGyms.isEmpty && tab.route != '/owner/home'
                        ? Theme.of(context).disabledColor
                        : null,
                  ),
                  label: context.tr(tab.labelKey),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
