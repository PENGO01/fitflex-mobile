import 'package:flutter/widgets.dart';

import '../../../shared/components/components.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';

/// What the member's pass is doing right now. One place decides this, so
/// Home, My QR and Profile can agree instead of each reading `status`.
enum PassState {
  /// No pass and nothing in flight.
  none,

  /// A payment is waiting for FitFlex to confirm it.
  pending,

  /// Can train.
  active,

  /// Can train, but three visits or fewer are left.
  lowVisits,

  /// Can train, but the pass ends within three days.
  endingSoon,

  /// Was a pass, no longer one.
  ended,
}

/// How a state reads on screen: green you can train, amber waiting or running
/// low, grey not active.
enum PassTone { success, warning, neutral }

const lowVisitsThreshold = 3;
const endingSoonDays = 3;

extension PassStateX on PassState {
  /// The QR is only live in these states.
  bool get canShowQr =>
      this == PassState.active ||
      this == PassState.lowVisits ||
      this == PassState.endingSoon;

  PassTone get tone => switch (this) {
    PassState.active => PassTone.success,
    PassState.lowVisits ||
    PassState.endingSoon ||
    PassState.pending => PassTone.warning,
    PassState.none || PassState.ended => PassTone.neutral,
  };
}

/// Visits left on a capped pass, or null when uncapped / unknown.
int? visitsLeft(MemberData d) {
  final cap = d.me?.visitCap;
  if (cap == null || cap <= 0) return null;
  final left = cap - (d.me?.visitsUsed ?? 0);
  return left < 0 ? 0 : left;
}

PassState passStateFor(MemberData d) {
  final sub = d.subscription;
  if (d.hasActivePass) {
    final days = sub?.daysLeft;
    // A gym membership runs on dates, not visits, even if the API sends a cap.
    final left = sub?.isDirect == true ? null : visitsLeft(d);
    if (days != null && days >= 0 && days <= endingSoonDays) {
      return PassState.endingSoon;
    }
    if (left != null && left <= lowVisitsThreshold) {
      return PassState.lowVisits;
    }
    return PassState.active;
  }
  if (d.pendingPayment != null) return PassState.pending;
  if (sub != null && (sub.isExpired || sub.status != 'inactive')) {
    return PassState.ended;
  }
  return PassState.none;
}

extension PassStateBadge on PassState {
  FFBadgeTone get badgeTone => switch (tone) {
    PassTone.success => FFBadgeTone.success,
    PassTone.warning => FFBadgeTone.warning,
    PassTone.neutral => FFBadgeTone.gray,
  };
}

/// "18 Nov 2026" (sw "18 Nov 2026"), the app's one date format, or "-" when
/// there is no date.
String passDate(BuildContext context, String? iso) => context.localDate(iso);

/// "8 Nov" (sw "8 Nov"): the day and month of an ISO date, for the pass chip.
String passShortDate(BuildContext context, String? iso) {
  final d = localDateTime(iso);
  if (d == null) return '';
  return formatDayMonth(
    d,
    locale: FFLocaleScope.of(context).locale.languageCode,
  );
}

/// The one sentence that explains a state, or null when the pass is simply
/// fine. Home, My QR and Profile all say the same thing.
String? passStateMessage(BuildContext context, MemberData d, PassState state) {
  final ends = passDate(context, d.subscription?.expiresAt);
  return switch (state) {
    PassState.none => context.tr('pass.state.none'),
    PassState.pending => context.tr('pass.state.pending'),
    PassState.ended =>
      context.tr('pass.state.ended').replaceAll('{date}', ends),
    PassState.endingSoon =>
      context.tr('pass.state.endingSoon').replaceAll('{date}', ends),
    PassState.lowVisits =>
      visitsLeft(d) == 0
          ? context.tr('pass.state.noVisits')
          : context
                .tr('pass.state.lowVisits')
                .replaceAll('{n}', '${visitsLeft(d) ?? 0}'),
    PassState.active => null,
  };
}
