import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';
import '../../../shared/tone_theme.dart';
import '../member_shell.dart';
import '../../../shared/photo_hero_flag.dart';
import 'pass_state.dart';

/// Built once: it does not depend on the context.
final ThemeData _voltCardTheme = buildVoltCardTheme();

class PassSummaryCard extends StatelessWidget {
  const PassSummaryCard({super.key, required this.data});

  final MemberData data;

  @override
  Widget build(BuildContext context) {
    // PHOTO_HERO_UI: a profile request that failed for a non-network reason
    // gets the generic error and Retry instead of spinning forever.
    if (photoHeroUi && data.me == null && !data.offline && data.meLoadFailed) {
      return FFErrorState(
        key: const Key('pass-summary-error'),
        retryLabel: context.tr('home.retry'),
        onRetry: () => _retry(context),
      );
    }
    // Until the profile arrives we don't know the pass, so don't flash
    // "Choose a pass" at a member who already has one.
    if (data.me == null && !data.offline) {
      return const FFCard(
        key: Key('pass-summary-loading'),
        child: SizedBox(height: 120, child: Center(child: FFSpinner(size: 32))),
      );
    }
    // Offline before the profile ever arrived: we don't know the pass, so
    // say we couldn't load it rather than "No pass yet".
    if (data.me == null && data.offline) {
      return FFErrorState(
        key: const Key('pass-summary-error'),
        icon: Icons.cloud_off_outlined,
        title: context.tr('home.passError.title'),
        retryLabel: context.tr('home.retry'),
        onRetry: () => _retry(context),
      );
    }
    final state = passStateFor(data);
    final sub = data.subscription;
    final pending = data.pendingPayment;
    final directDaysLeft = sub?.isDirect == true ? sub?.daysLeft : null;
    final directDurationDays = _durationDays(sub);
    final directProgress = directDaysLeft == null || directDurationDays == null
        ? null
        : (directDaysLeft / directDurationDays).clamp(0, 1).toDouble();

    // A working pass leads with its own name and status. A purchase still
    // waiting for approval is a different pass, so it gets its own amber
    // line below instead of borrowing this card's title or badge.
    final hasPass = state.canShowQr;
    final pendingAside = hasPass ? pending : null;

    // With no pass the title says so once; the sentence and the button
    // below carry the invitation, so the badge is left out.
    final String title;
    final String? status;
    if (hasPass || (pending == null && sub != null)) {
      title = sub!.isDirect
          ? (sub.homeGym?.name ?? context.tr('member.membership'))
          : context.tr('pass.${sub.tier}');
      // Ending soon says so on the badge instead of "Active", flag on or off
      // (owner, 2026-10-19). Low visits keeps the status wording for now.
      status = state == PassState.endingSoon
          ? context.tr('pass.badge.endingSoon')
          : _statusLabel(context, sub.status);
    } else if (pending != null) {
      title =
          _pendingName(context, pending) ??
          context.tr('pass.state.pendingPurchaseAny');
      // The sentence under the title already says the payment is being
      // confirmed (owner: say a fact once), so no badge repeats it.
      status = null;
    } else {
      title = context.tr('pass.state.noPassYet');
      status = null;
    }

    // Light system: a healthy, active pass is the screen's one Volt card.
    // Act-soon, pending and ended states stay on the normal card with their
    // warning colours. The content is built with the inner context so it
    // takes the Volt card's colours.
    final volt = state == PassState.active;
    final card = Builder(
      builder: (context) => _card(
        context,
        state: state,
        title: title,
        status: status,
        pendingAside: pendingAside,
        hasPass: hasPass,
        directDaysLeft: directDaysLeft,
        directProgress: directProgress,
      ),
    );
    if (!volt) return card;
    return Theme(
      key: const Key('pass-summary-volt'),
      data: _voltCardTheme,
      child: card,
    );
  }

  Widget _card(
    BuildContext context, {
    required PassState state,
    required String title,
    required String? status,
    required PaymentRequest? pendingAside,
    required bool hasPass,
    required int? directDaysLeft,
    required double? directProgress,
  }) {
    final theme = Theme.of(context);
    final sub = data.subscription;
    final pending = data.pendingPayment;
    // A purchase in flight keeps the full card, which has room for its line.
    if (state == PassState.active &&
        sub?.isDirect != true &&
        pendingAside == null) {
      return _voltCard(context, title: title);
    }
    final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Your pass" and the badge share the top line; the title gets the
          // full width below them, so neither is squeezed into broken words
          // at 360px. A long badge wraps inside the space it has.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('member.yourPass'),
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (status != null) ...[
                const SizedBox(width: FFTokens.spacingSm),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: FFBadge(
                      key: const Key('pass-status-badge'),
                      label: status,
                      tone: photoHeroUi && _actSoon(state)
                          ? FFBadgeTone.fuel
                          : state.badgeTone,
                      dot: true,
                      wrap: true,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            title,
            key: const Key('pass-title'),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (pendingAside != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            FFBadge(
              key: const Key('pass-pending-purchase'),
              label: switch (_pendingName(context, pendingAside)) {
                final name? =>
                  context
                      .tr('pass.state.pendingPurchase')
                      .replaceAll('{tier}', name),
                null => context.tr('pass.state.pendingPurchaseAny'),
              },
              tone: FFBadgeTone.warning,
              dot: true,
              wrap: true,
            ),
          ],
          if (sub?.isDirect == true && (hasPass || pending == null)) ...[
            const SizedBox(height: 10),
            Text(
              context.tr('member.plan_${sub!.plan ?? 'monthly'}'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _DirectDateRow(
              key: const Key('direct-membership-start'),
              label: context.tr('member.membershipStart'),
              value: passDate(context, sub.startedAt),
            ),
            _DirectDateRow(
              key: const Key('direct-membership-expiry'),
              label: context.tr('member.membershipExpiry'),
              value: passDate(context, sub.expiresAt),
            ),
            if (directDaysLeft != null) ...[
              _DirectDateRow(
                key: const Key('direct-membership-days-left'),
                label: context.tr('member.membershipDaysLeft'),
                value: '${directDaysLeft < 0 ? 0 : directDaysLeft}',
              ),
              if (directProgress != null) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: directProgress,
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                ),
              ],
            ],
            if (passStateMessage(context, data, state) case final m?) ...[
              const SizedBox(height: FFTokens.spacingSm),
              Text(
                m,
                key: const Key('pass-state-message'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ] else ...[
            const SizedBox(height: FFTokens.spacingMd),
            _stateBody(context, state),
          ],
          const SizedBox(height: FFTokens.spacingMd),
          FFButton(
            key: const Key('pass-primary-action'),
            fullWidth: true,
            label: switch (state) {
              PassState.pending => context.tr('pass.state.viewPayment'),
              PassState.ended => context.tr('pass.state.payAgain'),
              _ when state.canShowQr => context.tr('member.showQr'),
              _ => context.tr('pass.state.choose'),
            },
            icon: state.canShowQr ? Icons.qr_code_2 : null,
            onPressed: () => _go(
              context,
              state.canShowQr ? AppRoutes.memberQr : AppRoutes.memberPasses,
            ),
          ),
          if (state.canShowQr) ...[
            const SizedBox(height: FFTokens.spacingXs),
            FFButton(
              key: const Key('pass-upgrade-action'),
              fullWidth: true,
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              label: context.tr('member.upgradePlan'),
              onPressed: () => _go(context, AppRoutes.memberPasses),
            ),
          ],
        ],
      );
    return FFCard(child: content);
  }

  /// The active platform pass as the screen's lime card (DS v1.0 Home
  /// board): a forest "Active till" chip, "FitFlex Pass · Pro", the visits
  /// left large with "of 18 visits left" beside it, a forest Check in pill,
  /// and the Africa dot map, faint, top right.
  Widget _voltCard(BuildContext context, {required String title}) {
    final theme = Theme.of(context);
    final sub = data.subscription;
    final left = visitsLeft(data);
    final cap = data.me?.visitCap;
    final ofLeft = cap == null
        ? context.tr('pass.unlimited')
        : context.tr('pass.state.ofVisitsLeft').replaceAll('{total}', '$cap');
    final until = sub?.expiresAt == null
        ? null
        : context
              .tr('pass.activeTill')
              .replaceAll('{date}', passShortDate(context, sub!.expiresAt));
    final passName = title.contains('FitFlex')
        ? title
        : '${context.tr('pass.brand')} · $title';
    return Material(
      color: FFTokens.volt,
      borderRadius: BorderRadius.circular(FFTokens.radius2xl),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          PositionedDirectional(
            top: -6,
            end: -10,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: 0.4,
                  child: Image.asset(
                    'assets/brand/africa-dots.png',
                    key: const Key('pass-africa-motif'),
                    width: 150,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  key: const Key('pass-status-badge'),
                  padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                  decoration: BoxDecoration(
                    color: FFTokens.ink,
                    borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.event_available,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        until ?? context.tr('member.status_active'),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FFTokens.spacingMd),
                Text(
                  passName,
                  key: const Key('pass-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: FFTokens.spacingSm),
                LayoutBuilder(
                  builder: (context, c) {
                    // The board puts Check in beside the count; on a narrow
                    // phone or at large text it moves under it.
                    final scale = MediaQuery.textScalerOf(context).scale(1);
                    final numStyle = theme.textTheme.displayMedium?.copyWith(
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      height: 0.95,
                      letterSpacing: -2,
                    );
                    final ofStyle = theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    );
                    double width(String t, TextStyle? st) => (TextPainter(
                      text: TextSpan(text: t, style: st),
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                      maxLines: 1,
                    )..layout()).width;
                    // "11 of 18 visits left" stays on one line (DS v1.0);
                    // when it and the pill don't both fit, the pill drops
                    // to its own row.
                    final need =
                        (left == null ? 44 : width('$left', numStyle)) +
                        6 +
                        width(ofLeft, ofStyle) +
                        FFTokens.spacingSm +
                        width(
                          context.tr('member.checkInNav'),
                          theme.textTheme.labelLarge,
                        ) +
                        24 + 18 + 8 + 4 + 16 + 4;
                    final stacked = need > c.maxWidth || scale > 1.1;
                    final count = Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // No flex: the measured count keeps its width and
                        // "of 18 visits left" gets the rest (one line).
                        Flexible(
                          flex: 0,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.bottomStart,
                            child: Semantics(
                          key: const Key('pass-visits-ring'),
                          container: true,
                          label: left == null ? ofLeft : '$left $ofLeft',
                          child: ExcludeSemantics(
                            child: left == null
                                ? const Icon(Icons.all_inclusive, size: 44)
                                : Text('$left', style: numStyle),
                          ),
                        ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: ExcludeSemantics(
                              child: Text(
                                ofLeft,
                                key: const Key('pass-visits-used'),
                                style: ofStyle,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                    final action = FilledButton.icon(
                      key: const Key('pass-primary-action'),
                      style: FilledButton.styleFrom(
                        backgroundColor: FFTokens.ink,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: () => _go(context, AppRoutes.memberQr),
                      icon: const Icon(Icons.qr_code_2, size: 18),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(context.tr('member.checkInNav')),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward, size: 16),
                        ],
                      ),
                    );
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          count,
                          const SizedBox(height: FFTokens.spacingMd),
                          action,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: count),
                        const SizedBox(width: FFTokens.spacingSm),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: c.maxWidth * 0.45,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.bottomEnd,
                            child: action,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The platform-pass body: the ring and what's next while the pass works,
  /// a plain sentence otherwise.
  Widget _stateBody(BuildContext context, PassState state) {
    final theme = Theme.of(context);
    final sub = data.subscription;
    final left = visitsLeft(data);
    final cap = data.me?.visitCap;
    final ends = passDate(context, sub?.expiresAt);

    var message = passStateMessage(context, data, state);

    if (!state.canShowQr) {
      return Text(
        message ?? '',
        key: const Key('pass-state-message'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    // The ring already says how many are left; say what to do about it.
    if (state == PassState.lowVisits && (left ?? 0) > 0) {
      message = context.tr('pass.state.lowVisitsHint');
    }

    // Beside the ring: how many of the total they have used.
    final usedOf = left == null || cap == null
        ? null
        : context
              .tr('pass.state.usedOf')
              .replaceAll('{used}', '${(cap - left).clamp(0, cap)}')
              .replaceAll('{total}', '$cap');

    final tone = FFToneTheme.of(context);
    // PHOTO_HERO_UI: ending soon and few visits are Fuel ("act soon", canon
    // V2, F-5); payment pending stays amber.
    final ringColor = photoHeroUi && _actSoon(state)
        ? (theme.brightness == Brightness.dark
              ? FFTokens.fuelOnDark
              : FFTokens.fuel)
        : state.tone == PassTone.warning
        ? tone.warning.dot
        : theme.colorScheme.primary;
    return Row(
      children: [
        if (left != null && cap != null)
          _VisitsRing(
            key: const Key('pass-visits-ring'),
            left: left,
            total: cap,
            color: ringColor,
            leftLabel: context.tr('pass.state.left'),
          )
        else
          Icon(Icons.all_inclusive, size: 40, color: ringColor),
        const SizedBox(width: FFTokens.spacingMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Beside the ring's "11 left": "7 of 18 used".
              Text(
                usedOf ?? context.tr('pass.unlimited'),
                key: const Key('pass-visits-used'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              // The ending-soon sentence already carries the date.
              if (sub?.expiresAt != null && state != PassState.endingSoon)
                Text(
                  context.tr('pass.state.endsOn').replaceAll('{date}', ends),
                  style: theme.textTheme.bodyMedium,
                ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: FFTokens.spacing2xs),
                  child: Text(
                    message,
                    key: const Key('pass-state-message'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static bool _actSoon(PassState s) =>
      s == PassState.endingSoon || s == PassState.lowVisits;

  /// Refreshes the QR and profile first so the next screen is current.
  static Future<void> go(BuildContext context, String route) =>
      _go(context, route);

  static Future<void> _go(BuildContext context, String route) async {
    final shellState = context.findAncestorStateOfType<MemberShellState>();
    await shellState?.refreshQr();
    await shellState?.refreshMe();
    if (!context.mounted) return;
    context.go(route);
  }

  /// Loads the profile again (and the QR once it says there is a pass).
  Future<void> _retry(BuildContext context) async {
    final shellState = context.findAncestorStateOfType<MemberShellState>();
    await shellState?.refreshMe();
    if (data.canCheckIn) await shellState?.refreshQr();
  }

  /// The pass name for a tier, or the tier itself for one the app doesn't know.
  static String _tierLabel(BuildContext context, String tier) {
    final key = 'pass.$tier';
    final label = context.tr(key);
    return label == key ? tier : label;
  }

  /// What a waiting payment buys: the pass tier, or the gym for a gym plan.
  static String? _pendingName(BuildContext context, PaymentRequest pending) {
    if (pending.tier.isNotEmpty) return _tierLabel(context, pending.tier);
    final gym = pending.gymName?.trim() ?? '';
    return gym.isEmpty ? null : gym;
  }

  /// Translated status, falling back to the raw value for new ones.
  static String _statusLabel(BuildContext context, String status) {
    final key = 'member.status_$status';
    final label = context.tr(key);
    return label == key ? status : label;
  }

  static int? _durationDays(Subscription? sub) {
    final start = DateTime.tryParse(sub?.startedAt ?? '');
    final end = DateTime.tryParse(sub?.expiresAt ?? '');
    if (start == null || end == null) return null;
    final days = end.difference(start).inHours ~/ 24;
    return days <= 0 ? null : days;
  }
}

class _DirectDateRow extends StatelessWidget {
  const _DirectDateRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

/// Visits left as a ring: the number in the middle with "left" under it.
/// "7 of 18 used" sits beside the ring, so no number is said twice.
class _VisitsRing extends StatelessWidget {
  const _VisitsRing({
    super.key,
    required this.left,
    required this.total,
    required this.color,
    required this.leftLabel,
  });

  final int left;
  final int total;
  final Color color;
  final String leftLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = total <= 0 ? 0.0 : (left / total).clamp(0.0, 1.0);
    // One label for the whole ring ("11 left"); the number and "left" inside
    // it are not read again on their own. "1 of 12 used" is the text beside
    // the ring and is read there, so the ring does not say it too.
    return Semantics(
      label: '$left $leftLabel',
      excludeSemantics: true,
      child: SizedBox(
        width: 96,
        height: 96,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: fraction,
                strokeWidth: 9,
                strokeCap: StrokeCap.round,
                color: color,
                backgroundColor: theme.colorScheme.outlineVariant,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$left',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                Text(
                  leftLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
