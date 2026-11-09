import 'package:flutter/material.dart';

import '../../../router.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';
import 'pass_state.dart';
import 'pass_summary_card.dart';

/// Which Home hero to show (docs/design/photo-hero-screens.md §7.2).
enum HomeHeroState {
  loading,

  /// Offline or failed before the profile ever loaded.
  unavailable,
  none,
  pending,
  ended,

  /// A working pass: active, few visits or ending soon (the QR states).
  pass,
}

HomeHeroState homeHeroStateFor(MemberData d) {
  if (d.me == null) {
    return d.offline || d.meLoadFailed
        ? HomeHeroState.unavailable
        : HomeHeroState.loading;
  }
  return switch (passStateFor(d)) {
    PassState.none => HomeHeroState.none,
    PassState.pending => HomeHeroState.pending,
    PassState.ended => HomeHeroState.ended,
    _ => HomeHeroState.pass,
  };
}

/// Whether Home shows the pass card. In the no-QR states the hero carries
/// the state sentence and the action, so the card would repeat both (DD-5).
/// Sponsored members keep today's card until O-11 is decided.
bool homeShowsPassCard(MemberData d) {
  if (d.sponsoredGymAccess && !d.hasActivePass) return true;
  return switch (homeHeroStateFor(d)) {
    HomeHeroState.none || HomeHeroState.pending || HomeHeroState.ended => false,
    _ => true,
  };
}

/// The member Home hero: greeting, one state headline and one next step.
/// Numbers and dates stay on the pass card (DD-4).
class MemberHomeHero extends StatelessWidget {
  const MemberHomeHero({
    super.key,
    required this.data,
    required this.now,
    this.topInset = 0,
    this.panel = false,
  });

  final MemberData data;
  final DateTime now;
  final double topInset;

  /// Desktop banner (>= 840 wide): rounded, horizontal scrim.
  final bool panel;

  @override
  Widget build(BuildContext context) {
    final state = homeHeroStateFor(data);
    final pass = data.me == null ? null : passStateFor(data);
    final greeting = context.tr(
      now.hour < 12
          ? 'member.goodMorning'
          : now.hour < 17
          ? 'member.goodAfternoon'
          : 'member.goodEvening',
    );
    final name = data.me == null
        ? null
        : data.me!.user.knownName ?? context.tr('member.nameFallback');
    final eyebrow = name == null || name.isEmpty
        ? greeting
        : '$greeting, $name';
    final height = MediaQuery.sizeOf(context).height;
    final full = switch (state) {
      HomeHeroState.none ||
      HomeHeroState.pending ||
      HomeHeroState.ended => true,
      _ => false,
    };

    String? chip;
    if (state == HomeHeroState.pass) {
      if (pass == PassState.endingSoon) {
        chip = context.tr('home.hero.chip.endingSoon');
      } else if (pass == PassState.lowVisits) {
        chip = context.tr('home.hero.chip.lowVisits');
      }
    }
    final direct = data.subscription?.isDirect == true;

    Widget primary(String key, String label, String route) => FFButton(
      key: Key(key),
      label: label,
      onPressed: () => PassSummaryCard.go(context, route),
    );
    Widget secondary(String key, String label, String route) => FFButton(
      key: Key(key),
      label: label,
      variant: FFButtonVariant.onPhoto,
      size: FFButtonSize.sm,
      onPressed: () => PassSummaryCard.go(context, route),
    );
    final findGym = context.tr('home.hero.findGym');
    final exploreGyms = context.tr('home.hero.exploreGyms');

    final (
      String? lead,
      String? accent,
      String? sub,
      List<Widget> actions,
    ) = switch (state) {
      HomeHeroState.loading => (null, null, null, const <Widget>[]),
      HomeHeroState.unavailable => (
        context.tr('hero.tagline.lead'),
        context.tr('hero.tagline.accent'),
        null,
        const <Widget>[],
      ),
      HomeHeroState.none => (
        context.tr('home.hero.none.lead'),
        context.tr('home.hero.none.accent'),
        context.tr('pass.state.none'),
        [
          primary(
            'home-hero-primary',
            context.tr('pass.state.choose'),
            AppRoutes.memberPasses,
          ),
          secondary('home-hero-secondary', exploreGyms, AppRoutes.memberGyms),
        ],
      ),
      HomeHeroState.pending => (
        context.tr('home.hero.pending.lead'),
        context.tr('home.hero.pending.accent'),
        context.tr('pass.state.pending'),
        [
          primary(
            'home-hero-primary',
            context.tr('pass.state.viewPayment'),
            AppRoutes.memberPasses,
          ),
        ],
      ),
      HomeHeroState.ended => (
        context.tr('home.hero.ended.lead'),
        context.tr('home.hero.ended.accent'),
        // The card is hidden, so the end date is said once, here.
        passStateMessage(context, data, PassState.ended),
        [
          primary(
            'home-hero-primary',
            context.tr('pass.state.payAgain'),
            AppRoutes.memberPasses,
          ),
          secondary('home-hero-secondary', exploreGyms, AppRoutes.memberGyms),
        ],
      ),
      HomeHeroState.pass => (
        context.tr('home.hero.active.lead'),
        context.tr('home.hero.active.accent'),
        null,
        chip != null && !direct
            ? [
                primary(
                  'home-hero-primary',
                  context.tr('home.hero.nextPass'),
                  AppRoutes.memberPasses,
                ),
                secondary('home-hero-secondary', findGym, AppRoutes.memberGyms),
              ]
            : [primary('home-hero-primary', findGym, AppRoutes.memberGyms)],
      ),
    };

    final withName =
        state != HomeHeroState.loading && state != HomeHeroState.unavailable;
    return FFPhotoHero(
      key: Key('home-hero-${state.name}'),
      photo: state == HomeHeroState.pass
          ? FFHeroPhoto.homePass
          : FFHeroPhoto.homeStart,
      variant: panel
          ? FFHeroVariant.panel
          : full
          ? FFHeroVariant.full
          : FFHeroVariant.compact,
      rounded: panel,
      minHeight: panel
          ? 0
          : full
          ? (height * 0.5).clamp(360.0, double.infinity)
          : (height * 0.3).clamp(260.0, double.infinity),
      topInset: topInset,
      eyebrow: withName ? eyebrow : greeting,
      chip: chip,
      headlineLoading: state == HomeHeroState.loading,
      headlineLead: lead,
      headlineAccent: accent,
      subline: sub,
      actions: actions,
    );
  }
}

/// Three numbered steps for a member with no pass yet.
class HowFitFlexWorksCard extends StatelessWidget {
  const HowFitFlexWorksCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FFCard(
      key: const Key('home-how-it-works'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              context.tr('home.how.title'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          for (final (i, key) in const [
            'home.how.step1',
            'home.how.step2',
            'home.how.step3',
          ].indexed)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingSm),
              child: MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primary.withValues(alpha: 0.14),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: FFTokens.spacingSm + 4),
                    Expanded(
                      child: Text(
                        context.tr(key),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Sent up from Home while scrolling: once the hero has passed under the app
/// bar, the shell makes the bar solid again.
class HomeHeroAppBarNotification extends Notification {
  const HomeHeroAppBarNotification({required this.solid});

  final bool solid;
}

/// Wraps a member tab whose hero sits under the shell's transparent app bar
/// (Activity, Profile; spec C-7): tells the shell to start transparent and
/// to turn solid once the hero (under [heroKey]) has passed under the bar.
class HeroTabScroll extends StatefulWidget {
  const HeroTabScroll({super.key, required this.heroKey, required this.child});

  final GlobalKey heroKey;
  final Widget child;

  @override
  State<HeroTabScroll> createState() => _HeroTabScrollState();
}

class _HeroTabScrollState extends State<HeroTabScroll> {
  bool _passed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        const HomeHeroAppBarNotification(solid: false).dispatch(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) {
        if (n.depth != 0) return false;
        final h = widget.heroKey.currentContext?.size?.height ?? 0;
        final passed =
            h > 0 && n.metrics.pixels >= h - MediaQuery.paddingOf(context).top;
        if (passed != _passed) {
          _passed = passed;
          HomeHeroAppBarNotification(solid: passed).dispatch(context);
        }
        return false;
      },
      child: widget.child,
    );
  }
}

/// The hero's top inset on a member tab under the shell's transparent bar:
/// the status bar and app bar, plus the offline strip when it shows.
double memberHeroTopInset(BuildContext context, MemberData data) =>
    MediaQuery.paddingOf(context).top + (data.offline ? 56.0 : 0.0);
