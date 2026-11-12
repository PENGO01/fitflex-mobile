import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/payment_labels.dart';
import '../../shared/models.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import 'member_scan_gym_page.dart';
import 'member_shell.dart';
import 'widgets/checkin_list.dart';
import 'widgets/pass_state.dart';

class MemberQrTab extends StatelessWidget {
  const MemberQrTab({super.key});

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final state = passStateFor(data);
    final notice = state == PassState.lowVisits || state == PassState.endingSoon
        ? passStateMessage(context, data, state)
        : null;

    // Check in is a tab of its own now (DS v1.0 bar): no second app bar and
    // no back arrow under the shell's bar, just the page title.
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          FFPageHeader(title: context.tr('member.checkInNav')),
          if (data.pendingPayment != null) _PendingPaymentCard(data: data),
          // Amber heads-up while the QR still works: running low or ending.
          if (notice != null && data.canCheckIn) ...[
            FFAlert(
              key: const Key('qr-state-notice'),
              message: notice,
              tone: FFAlertTone.warning,
            ),
            const SizedBox(height: 12),
          ],
          // DS v1.0 Check in board: the pass, small and lime, above the code.
          if (data.canCheckIn && data.subscription?.isDirect != true) ...[
            _QrPassStrip(data: data),
            const SizedBox(height: 12),
          ],
          if (data.canCheckIn)
            _QrCard(data: data)
          else
            _QrLockedCard(data: data, state: state),
          if (data.canCheckIn) ...[
            const SizedBox(height: 12),
            // Tech Brief §5: self check-in by scanning the gym's entrance QR.
            FFButton(
              key: const Key('member-scan-gym-qr'),
              label: context.tr('checkin.scanInstead'),
              onPressed: () => _scanGym(context, data),
              variant: FFButtonVariant.secondary,
              icon: Icons.qr_code_scanner,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              context.tr('qr.needsSignal'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: FFTokens.spacingLg),

          // Recent checkins
          FFSectionTitle(context.tr('member.recentCheckins')),
          CheckinList(checkins: data.checkins, limit: 5),
        ],
      ),
    );
  }
}

Future<void> _scanGym(BuildContext context, MemberData data) async {
  final api = AppScope.of(context).api;
  final checkedIn = await Navigator.of(
    context,
  ).push<bool>(MaterialPageRoute(builder: (_) => const MemberScanGymPage()));
  if (checkedIn != true) return;
  try {
    final res = await api.myCheckins();
    data.update(
      (d) => d.checkins = res
          .whereType<Map<String, dynamic>>()
          .map(CheckIn.fromJson)
          .toList(),
    );
  } catch (_) {
    // The list refreshes on the next app resume anyway.
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.data});

  final MemberData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final left = visitsLeft(data);
    final cap = data.me?.visitCap;
    // The visit this scan would be: used so far plus one.
    final visit = left == null || cap == null
        ? null
        : context
              .tr('qr.visitOf')
              .replaceAll('{n}', '${(cap - left + 1).clamp(1, cap)}')
              .replaceAll('{total}', '$cap');
    return FFCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          Text(
            context.tr('home.qr'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: FFTokens.spacingLg),
          // The code always sits on white with a forest frame, so scanners
          // read it in dark mode too.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: FFTokens.ink, width: 2),
            ),
            child: data.qrToken != null
                ? FFQrCode(
                    key: const Key('member-qr'),
                    data: data.qrToken!,
                    size: 210,
                  )
                : const SizedBox(
                    width: 210,
                    height: 210,
                    child: Center(child: FFSpinner(size: 32)),
                  ),
          ),
          const SizedBox(height: FFTokens.spacingMd),
          _QrRefresh(token: data.qrToken),
          if (visit != null) ...[
            const SizedBox(height: FFTokens.spacingMd),
            Text(
              visit,
              key: const Key('qr-visit-of'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QrLockedCard extends StatelessWidget {
  const _QrLockedCard({required this.data, required this.state});

  final MemberData data;
  final PassState state;

  @override
  Widget build(BuildContext context) {
    final isPending = data.pendingPayment != null;
    final title = isPending
        ? context.tr('home.qr.pendingTitle')
        : context.tr('home.qr.lockedTitle');
    // An ended pass says so (and when) instead of the generic locked copy.
    final ended = state == PassState.ended;
    final body = isPending
        ? context.tr('home.qr.pendingBody')
        : ended
        ? passStateMessage(context, data, state)!
        : context.tr('home.qr.lockedBody');

    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                ),
                child: Icon(
                  Icons.qr_code_2,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isPending) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FFButton(
                label: ended
                    ? context.tr('pass.state.payAgain')
                    : context.tr('member.subscribe'),
                onPressed: () => context.go(AppRoutes.memberPasses),
                icon: Icons.card_membership,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PendingPaymentCard extends StatelessWidget {
  const _PendingPaymentCard({required this.data});

  final MemberData data;

  @override
  Widget build(BuildContext context) {
    final pending = data.pendingPayment!;
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FFBadge(
            label: context.tr('pass.pending'),
            tone: FFBadgeTone.warning,
            dot: true,
          ),
          const SizedBox(height: 8),
          Text(
            '${paymentProductLabel(context, pending)} - ${formatCurrency(pending.amountTzs)}',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontSize: 14,
            ),
          ),
          if (pending.memberReference case final ref?) ...[
            const SizedBox(height: 4),
            Text(
              context.tr('manualPay.idShown').replaceAll('{id}', ref),
              key: const Key('qr-pending-transaction-id'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (pending.payerPhone case final phone?) ...[
            const SizedBox(height: 2),
            Text(
              context
                  .tr('manualPay.paidFromShown')
                  .replaceAll('{phone}', phone),
              key: const Key('qr-pending-payer-phone'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}


/// The active pass, small, on lime: status chip and plan on the left, the
/// visits left large on the right (DS v1.0 Check in board).
class _QrPassStrip extends StatelessWidget {
  const _QrPassStrip({required this.data});

  final MemberData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = data.subscription;
    final left = visitsLeft(data);
    final tier = sub?.tier ?? data.selectedTier;
    final tierKey = 'pass.$tier';
    final tierName = context.tr(tierKey) == tierKey ? tier : context.tr(tierKey);
    final until = sub?.expiresAt == null
        ? context.tr('member.status_active')
        : context
              .tr('pass.activeTill')
              .replaceAll('{date}', passShortDate(context, sub!.expiresAt));
    const ink = FFTokens.ink;
    return Container(
      key: const Key('qr-pass-strip'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: FFTokens.volt,
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ink,
                    borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                  ),
                  child: Text(
                    until,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${context.tr('pass.brand')} · $tierName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (left != null)
            Semantics(
              label: '$left ${context.tr('pass.state.left')}',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$left',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: ink,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    Text(
                      context.tr('qr.visitsLeft'),
                      style: theme.textTheme.bodySmall?.copyWith(color: ink),
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

/// DS v1.0 Check in board: a thin lime bar that empties until the next code
/// and "New code in 37 s". The shell fetches a new code every 30 seconds
/// (`MemberShellState`), so the count restarts whenever the code changes.
class _QrRefresh extends StatefulWidget {
  const _QrRefresh({required this.token});

  final String? token;

  @override
  State<_QrRefresh> createState() => _QrRefreshState();
}

class _QrRefreshState extends State<_QrRefresh> {
  static const _period = 30;
  Timer? _tick;
  int _left = _period;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _left = _left > 1 ? _left - 1 : _period);
    });
  }

  @override
  void didUpdateWidget(_QrRefresh old) {
    super.didUpdateWidget(old);
    if (old.token != widget.token) _left = _period;
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('qr-refresh'),
      children: [
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              width: 210,
              child: LinearProgressIndicator(
                value: _left / _period,
                minHeight: 4,
                color: FFTokens.volt,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Read once, not every second, by screen readers.
        Semantics(
          liveRegion: false,
          label: context.tr('home.qr.refreshes'),
          child: ExcludeSemantics(
            child: Text(
              context.tr('qr.newCodeIn').replaceAll('{n}', '$_left'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
