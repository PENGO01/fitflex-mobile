import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/components/components.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';

/// A2/A3 — Membership card shown on the member profile:
/// plan/tier, status, start + expiry date, days left, and the subscribed gym
/// for direct memberships.
class MembershipCard extends StatelessWidget {
  const MembershipCard({super.key, required this.subscription});

  final Subscription? subscription;

  @override
  Widget build(BuildContext context) {
    final sub = subscription;
    if (sub == null) {
      return FFCard(
        child: Row(
          children: [
            Icon(
              Icons.card_membership_outlined,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('member.noMembership'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    final daysLeft = sub.daysLeft;
    final expired = sub.isExpired;
    final planLabel = sub.isDirect
        ? context.tr('member.plan_${sub.plan ?? 'monthly'}')
        : _titleCase(sub.tier ?? '-');
    final statusTone = expired
        ? FFBadgeTone.danger
        : sub.isActive
        ? FFBadgeTone.success
        : FFBadgeTone.warning;
    final statusLabel = expired
        ? context.tr('member.membershipExpired')
        : context.tr('member.status_${sub.status}');

    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('member.membership'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              FFBadge(label: statusLabel, tone: statusTone, dot: true),
            ],
          ),
          const SizedBox(height: 10),
          _MembershipRow(
            label: context.tr('member.membershipPlan'),
            value: planLabel,
          ),
          _MembershipRow(
            label: context.tr('member.membershipStart'),
            value: context.localDate(sub.startedAt),
          ),
          _MembershipRow(
            key: const Key('membership-expiry'),
            label: context.tr('member.membershipExpiry'),
            value: context.localDate(sub.expiresAt),
          ),
          if (daysLeft != null && !expired)
            _MembershipRow(
              key: const Key('membership-days-left'),
              label: context.tr('member.membershipDaysLeft'),
              value: '$daysLeft',
            ),
          if (sub.isDirect && sub.homeGym != null) ...[
            const Divider(height: 20),
            InkWell(
              key: const Key('membership-gym'),
              onTap: () => context.go('/member/gyms/${sub.homeGym!.id}'),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Icon(
                    Icons.fitness_center,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sub.homeGym!.name,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (sub.homeGym!.location.isNotEmpty)
                          Text(
                            sub.homeGym!.location,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MembershipRow extends StatelessWidget {
  const _MembershipRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// "premium" → "Premium" (DS v1.0: sentence case, no capitals).
String _titleCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
