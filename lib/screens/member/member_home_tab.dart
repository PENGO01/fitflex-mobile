import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import 'member_shell.dart';
import 'events/home_events_card.dart';
import 'home_feed.dart';
import 'widgets/phone_steps_card.dart';
import 'widgets/challenge_widgets.dart';
import 'widgets/goal_widgets.dart';
import 'widgets/home_cards.dart';
import 'widgets/home_hero.dart';
import '../../shared/photo_footer_flag.dart';
import '../../shared/photo_hero_flag.dart';
import 'widgets/pass_summary_card.dart';
import 'widgets/today_activity_card.dart';
import 'widgets/workout_widgets.dart';

class MemberHomeTab extends StatefulWidget {
  const MemberHomeTab({super.key, this.now});

  /// Injectable clock for tests.
  final DateTime? now;

  @override
  State<MemberHomeTab> createState() => _MemberHomeTabState();
}

class _MemberHomeTabState extends State<MemberHomeTab> {
  double? _userLat;
  double? _userLng;
  final _heroKey = GlobalKey();
  bool _heroPassed = false;

  @override
  void initState() {
    super.initState();
    // Refresh QR and user data when home tab becomes visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (photoHeroUi && mounted) {
        const HomeHeroAppBarNotification(solid: false).dispatch(context);
      }
      _refreshData();
      _fetchLocation();
    });
  }

  Future<void> _refreshData() async {
    final shellState = context.findAncestorStateOfType<MemberShellState>();
    await shellState?.refreshQr();
    await shellState?.refreshMe();
  }

  Future<void> _fetchLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      if (!mounted) return;
      setState(() {
        _userLat = position.latitude;
        _userLng = position.longitude;
      });
    } catch (_) {
      // Location is optional on home. Keep showing the backend gym list.
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final me = data.me;
    final displayName = me == null
        ? context.tr('home.welcome')
        : me.user.knownName ?? context.tr('member.nameFallback');
    final now = widget.now ?? DateTime.now();
    final picks = _presentationOrder(
      pickHomeCards(data, now, lat: _userLat, lng: _userLng),
    );
    bool has(HomeCardKind k) => picks.any((p) => p.kind == k);

    if (photoHeroUi) return _buildPhotoHero(context, data, picks, now, has);
    return ListView(
      key: const Key('member-home'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        FFPageHeader(
          title: displayName,
          description: context.tr(
            now.hour < 12
                ? 'member.goodMorning'
                : now.hour < 17
                ? 'member.goodAfternoon'
                : 'member.goodEvening',
          ),
        ),
        for (final p in picks)
          KeyedSubtree(
            key: Key('home-card-${p.kind.name}'),
            child: _card(context, data, p, now, has),
          ),
      ],
    );
  }

  /// PHOTO_HERO_UI: a photo hero leads; content sits on the ground (dark)
  /// or an overlapping sheet (light).
  Widget _buildPhotoHero(
    BuildContext context,
    MemberData data,
    List<HomeCardPick> picks,
    DateTime now,
    bool Function(HomeCardKind) has,
  ) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final showCard = homeShowsPassCard(data);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!showCard && homeHeroStateFor(data) == HomeHeroState.none)
          const Padding(
            padding: EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: HowFitFlexWorksCard(),
          ),
        for (final p in picks)
          if (p.kind != HomeCardKind.passport || showCard)
            KeyedSubtree(
              key: Key('home-card-${p.kind.name}'),
              child: _card(context, data, p, now, has),
            ),
      ],
    );

    // PHOTO_FOOTER_UI (spec §33.6): once the profile has loaded.
    Widget? footer({required bool padded}) => photoFooterUi
        ? FFPhotoFooter.sliver(
            key: const Key('home-footer'),
            pageKey: 'member.home',
            top: homeHeroStateFor(data) == HomeHeroState.pass
                ? FFHeroPhoto.homePass
                : FFHeroPhoto.homeStart,
            enabled: data.me != null,
            gap: padded
                ? FFTokens.spacingXl - FFTokens.spacingLg
                : FFTokens.spacingXl,
          )
        : null;

    if (wide) {
      return footerListView(
        key: const Key('member-home'),
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        footer: footer(padded: true),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MemberHomeHero(data: data, now: now, panel: true),
                  const SizedBox(height: FFTokens.spacingLg),
                  body,
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Under the shell's transparent app bar; the offline strip sits below it.
    final topInset =
        MediaQuery.paddingOf(context).top + (data.offline ? 56.0 : 0.0);
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) {
        if (n.depth != 0) return false;
        final h = _heroKey.currentContext?.size?.height ?? 0;
        final passed =
            h > 0 && n.metrics.pixels >= h - MediaQuery.paddingOf(context).top;
        if (passed != _heroPassed) {
          _heroPassed = passed;
          HomeHeroAppBarNotification(solid: passed).dispatch(context);
        }
        return false;
      },
      child: footerListView(
        key: const Key('member-home'),
        footer: footer(padded: false),
        children: [
          KeyedSubtree(
            key: _heroKey,
            child: MemberHomeHero(data: data, now: now, topInset: topInset),
          ),
          FFHeroSheet(child: body),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context,
    MemberData data,
    HomeCardPick p,
    DateTime now,
    bool Function(HomeCardKind) has,
  ) {
    const gap = SizedBox(height: FFTokens.spacingSm);
    switch (p.kind) {
      case HomeCardKind.passport:
        return Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: PassSummaryCard(data: data),
        );
      case HomeCardKind.todayActivity:
        return Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TodayActivityCard(
                data: data,
                now: now,
                showWorkout: !has(HomeCardKind.todayWorkout),
                showStreak: !has(HomeCardKind.streak),
              ),
              const PhoneStepsCard(dismissible: true),
            ],
          ),
        );
      case HomeCardKind.todayWorkout:
        return Column(
          children: [
            gap,
            TodayWorkoutCard(data: data, now: now),
          ],
        );
      case HomeCardKind.streak:
        return Column(
          children: [
            gap,
            HomeStreakCard(pick: p),
          ],
        );
      case HomeCardKind.goal:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FFSectionTitle(context.tr('home.currentGoal')),
            if (p.goal case final g?)
              GoalCard(progress: g)
            else
              FFActionTile(
                key: const Key('home-set-goal'),
                icon: Icons.flag_outlined,
                title: context.tr('home.setGoal'),
                subtitle: context.tr('home.setGoalBody'),
                onTap: () => showAddGoalSheet(context),
              ),
          ],
        );
      case HomeCardKind.challenge:
        final s = p.standing;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FFSectionTitle(
              context.tr(
                s != null ? 'home.activeChallenge' : 'home.tryChallenge',
              ),
            ),
            ChallengeCard(
              challenge: s?.challenge ?? p.invite!,
              progress: s?.progress,
              now: now,
            ),
          ],
        );
      case HomeCardKind.recommendation:
        final g = p.gym;
        return HomeRecommendation(
          pick: p,
          distanceKm: g == null
              ? null
              : gymDisplayDistanceKm(
                  g,
                  userLat: _userLat,
                  userLng: _userLng,
                  activeFilter: 'home',
                ),
        );
      case HomeCardKind.events:
        return Column(
          children: [
            gap,
            HomeEventsCard(events: data.upcomingEvents),
          ],
        );
    }
  }
}

/// The pass (it holds the check-in QR) leads and the recommendation closes
/// the page; everything else keeps the ranking order from [pickHomeCards].
List<HomeCardPick> _presentationOrder(List<HomeCardPick> picks) {
  int slot(HomeCardPick p) => switch (p.kind) {
    HomeCardKind.passport => 0,
    HomeCardKind.recommendation => 2,
    // Events sit after the recommendation (events S2 spec §11.1).
    HomeCardKind.events => 3,
    _ => 1,
  };
  final indexed = picks.indexed.toList()
    ..sort((a, b) {
      final s = slot(a.$2).compareTo(slot(b.$2));
      return s != 0 ? s : a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}

List<Gym> memberHomeNearGyms(
  List<Gym> gyms, {
  double? userLat,
  double? userLng,
}) {
  if (userLat == null || userLng == null) return gyms.take(2).toList();
  final sorted = List<Gym>.from(gyms);
  sorted.sort(
    (a, b) => gymDistanceKm(
      a,
      userLat,
      userLng,
    ).compareTo(gymDistanceKm(b, userLat, userLng)),
  );
  return sorted.take(2).toList();
}
