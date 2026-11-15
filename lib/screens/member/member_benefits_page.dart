// My wellness benefits: what an employer, insurer or other sponsor gives the
// member through FitFlex, how much is used and what is left. Read-only: the
// server works out every number, and a benefit is used automatically at
// check-in or when a trainer session is completed.

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../../shared/widgets/verify_identifier.dart';
import 'member_requests_page.dart';

class MemberBenefitsPage extends StatefulWidget {
  const MemberBenefitsPage({super.key});

  @override
  State<MemberBenefitsPage> createState() => _MemberBenefitsPageState();
}

class _MemberBenefitsPageState extends State<MemberBenefitsPage> {
  List<Map<String, dynamic>>? _benefits;

  /// Organisations waiting for the member to accept being added
  /// (fitflex-functions#241). Empty on a backend without them.
  List<Map<String, dynamic>> _requests = const [];
  Object? _error;
  String? _unlocking;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await AppScope.of(context).api.myWellnessBenefits();
      if (!mounted) return;
      setState(() {
        _benefits = ((res['benefits'] as List?) ?? const [])
            .map((b) => (b as Map).cast<String, dynamic>())
            .toList();
        _requests = pendingMemberRequests(res['memberRequests']);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Answer organisations' requests, then show what changed.
  Future<void> _openRequests() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MemberRequestsPage()));
    if (mounted) await _load();
  }

  Widget _requestsCard() => _requests.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
          child: MemberRequestsCard(
            count: _requests.length,
            onOpen: _openRequests,
          ),
        );

  /// Ask to pay the member's share of a sponsored pass. The pass starts when
  /// FitFlex confirms the payment.
  Future<void> _unlock(String entitlementId) async {
    final messenger = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final requested = context.tr('benefits.pass.requested');
    setState(() => _unlocking = entitlementId);
    try {
      await AppScope.of(context).api.unlockSponsoredPass(entitlementId);
      await _load();
      messenger.info(requested);
    } catch (e) {
      messenger.error(errorMessage(locale, e));
    } finally {
      if (mounted) setState(() => _unlocking = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _benefits;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('benefits.title'))),
      body: rows == null
          ? (_error == null
                ? const Center(child: FFSpinner())
                : FFEmptyState(
                    title: context.tr('benefits.loadFailed'),
                    body: context.tr('common.loadFailedBody'),
                    action: FFButton(
                      label: context.tr('comms.retry'),
                      onPressed: _load,
                    ),
                  ))
          : rows.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                _requestsCard(),
                FFEmptyState(
                  title: context.tr('benefits.empty.title'),
                  body: context.tr('benefits.empty.body'),
                ),
                _ConfirmContactHint(onVerified: _load),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                _requestsCard(),
                Text(
                  context.tr('benefits.intro'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                for (final row in rows) ...[
                  _BenefitCard(
                    row: row,
                    busy: _unlocking != null,
                    onUnlock: _unlock,
                  ),
                  const SizedBox(height: FFTokens.spacingMd),
                ],
                const _SponsorVisibilityNote(),
              ],
            ),
    );
  }
}

/// Sponsored benefits attach only once the member has verified the email or
/// mobile number their organisation listed. This hint points to Contact
/// details. It never says whether an invite exists, and it is hidden while
/// the backend has identifier verification off.
class _ConfirmContactHint extends StatelessWidget {
  const _ConfirmContactHint({required this.onVerified});

  /// Called after Contact details closes with a new verified email or number.
  final Future<void> Function() onVerified;

  Set<String> _verifiedValues(List<Map<String, dynamic>> items) =>
      items.map((i) => '${i['type']}:${i['value']}').toSet();

  Future<void> _open(BuildContext context) async {
    final auth = AppScope.of(context).auth;
    final before = _verifiedValues(auth.verifiedIdentifiers);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ContactDetailsScreen()),
    );
    final after = _verifiedValues(auth.verifiedIdentifiers);
    if (after.difference(before).isNotEmpty) await onVerified();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (!auth.identifiersEnabled) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingMd),
          child: FFCard(
            key: const Key('benefits-confirm-contact'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('benefits.confirmContact.title'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: FFTokens.spacingSm),
                Text(
                  context.tr(
                    auth.emailCodesAvailable
                        ? 'benefits.confirmContact.body'
                        : 'benefits.confirmContact.bodyPhoneOnly',
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                FFButton(
                  key: const Key('benefits-confirm-contact-action'),
                  label: context.tr(
                    auth.emailCodesAvailable
                        ? 'benefits.confirmContact.action'
                        : 'benefits.confirmContact.actionPhoneOnly',
                  ),
                  onPressed: () => _open(context),
                  variant: FFButtonVariant.secondary,
                  fullWidth: true,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// What the sponsor behind these benefits can and cannot see of the member.
class _SponsorVisibilityNote extends StatelessWidget {
  const _SponsorVisibilityNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('benefits-visibility'),
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('benefits.visibility.title'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('benefits.visibility.sees'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('benefits.visibility.hidden'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _BenefitCard extends StatelessWidget {
  const _BenefitCard({
    required this.row,
    required this.busy,
    required this.onUnlock,
  });

  final Map<String, dynamic> row;
  final bool busy;
  final ValueChanged<String> onUnlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = (row['organization'] as Map).cast<String, dynamic>();
    final program = (row['program'] as Map).cast<String, dynamic>();
    final benefit = (row['benefit'] as Map).cast<String, dynamic>();
    final validity = (benefit['validity'] as Map?)?.cast<String, dynamic>();
    final limit = benefit['usageLimit'] as num?;
    final used = (row['used'] as num?) ?? 0;
    final remaining = row['remaining'] as num?;
    final period = '${benefit['usagePeriod']}';
    final endDate = validity?['endDate'] as String?;

    return FFCard(
      key: Key('benefit-${benefit['id']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${org['name']} · ${program['name']}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Text('${benefit['name']}', style: theme.textTheme.titleMedium),
          Text(
            context.tr('benefits.type.${benefit['benefitType']}'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: FFTokens.spacingSm),
          if (limit != null) ...[
            LinearProgressIndicator(
              value: limit == 0 ? 0 : (used / limit).clamp(0, 1).toDouble(),
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Text(
              context
                  .tr('benefits.used')
                  .replaceAll('{used}', '$used')
                  .replaceAll('{limit}', '$limit')
                  .replaceAll(
                    '{period}',
                    context.tr('benefits.period.$period'),
                  ),
            ),
            Text(
              context
                  .tr('benefits.remaining')
                  .replaceAll('{n}', '${remaining ?? 0}'),
              style: theme.textTheme.titleSmall,
            ),
          ] else if (benefit['benefitType'] == 'sponsored_pass')
            ..._pass(context, (row['pass'] as Map?)?.cast<String, dynamic>())
          else
            Text(context.tr('benefits.unlimited')),
          const SizedBox(height: FFTokens.spacingSm),
          Text(_funding(context, benefit)),
          Text(
            endDate == null
                ? context.tr('benefits.noEnd')
                : context
                      .tr('benefits.validUntil')
                      .replaceAll('{date}', endDate),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// A sponsored pass: whether this month's pass is running, or what the
  /// member pays once to unlock it.
  List<Widget> _pass(BuildContext context, Map<String, dynamic>? pass) {
    final status = pass?['status'] as String?;
    if (status == 'active') return [Text(context.tr('benefits.pass.active'))];
    if (status == 'scheduled') {
      return [Text(context.tr('benefits.pass.scheduled'))];
    }
    if (status != 'awaiting_member') {
      return [Text(context.tr('benefits.pass.awaitingSponsor'))];
    }
    if (pass?['paymentPending'] == true) {
      return [Text(context.tr('benefits.pass.requested'))];
    }
    final amount = formatCurrency((pass?['memberTzs'] as num?) ?? 0);
    return [
      Text(context.tr('benefits.pass.unlockBody')),
      const SizedBox(height: FFTokens.spacingSm),
      FFButton(
        key: Key('unlock-${pass?['entitlementId']}'),
        label: context
            .tr('benefits.pass.unlock')
            .replaceAll('{amount}', amount),
        onPressed: busy ? null : () => onUnlock('${pass?['entitlementId']}'),
      ),
    ];
  }

  String _funding(BuildContext context, Map<String, dynamic> b) {
    final type = '${b['fundingType']}';
    final text = context.tr('benefits.funding.$type');
    switch (type) {
      case 'sponsor_fixed':
        return text.replaceAll(
          '{amount}',
          formatCurrency((b['sponsorAmountTzs'] as num?) ?? 0),
        );
      case 'sponsor_percentage':
        final pct = ((b['sponsorShareBps'] as num?) ?? 0) / 100;
        return text.replaceAll(
          '{pct}',
          pct == pct.roundToDouble() ? '${pct.round()}' : '$pct',
        );
      case 'beneficiary_fixed':
        return text.replaceAll(
          '{amount}',
          formatCurrency((b['beneficiaryAmountTzs'] as num?) ?? 0),
        );
      default:
        return text;
    }
  }
}
