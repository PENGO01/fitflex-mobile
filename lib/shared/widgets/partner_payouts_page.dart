// My payouts: a trainer's or vendor's weekly statements. Each lists what
// FitFlex is paying for that week (sessions for a trainer, delivered orders
// for a vendor), what the partner earns after commission, and where it stands
// (awaiting approval, approved, ready to pay, paid). Read-only: the server
// works out every number. A partner is paid only once verified with a payout
// account, so the page says when that is still missing.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../api_client.dart';
import '../api_error_message.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../formatters.dart';
import '../i18n.dart';

enum PayoutKind { trainer, vendor }

extension on PayoutKind {
  bool get isVendor => this == PayoutKind.vendor;

  Future<Map<String, dynamic>> list(ApiClient api) =>
      isVendor ? api.vendorPayoutStatements() : api.trainerStatements();

  Future<Map<String, dynamic>> one(ApiClient api, String id) =>
      isVendor ? api.vendorPayoutStatement(id) : api.trainerStatement(id);

  /// How many sessions or orders a statement pays for.
  num count(Map<String, dynamic> s) =>
      (isVendor ? s['orderCount'] : s['sessionCount']) as num? ?? 0;

  /// What was sold before commission.
  num gross(Map<String, dynamic> s) =>
      (isVendor ? s['salesTzs'] : s['listTzs']) as num? ?? 0;

  String key(String name) =>
      isVendor ? 'payouts.vendor.$name' : 'payouts.$name';
}

(String, FFBadgeTone) _status(Map<String, dynamic> s) => switch (s['status']) {
  'paid' => ('payouts.status.paid', FFBadgeTone.success),
  'payable' => ('payouts.status.payable', FFBadgeTone.brand),
  'approved' => ('payouts.status.approved', FFBadgeTone.brand),
  _ => ('payouts.status.submitted', FFBadgeTone.warning),
};

String _week(Map<String, dynamic> s) =>
    '${s['periodStartDate']} – ${s['periodEndDate']}';

class PartnerPayoutsPage extends StatefulWidget {
  const PartnerPayoutsPage({super.key, required this.kind});

  final PayoutKind kind;

  @override
  State<PartnerPayoutsPage> createState() => _PartnerPayoutsPageState();
}

class _PartnerPayoutsPageState extends State<PartnerPayoutsPage> {
  List<Map<String, dynamic>>? _statements;
  bool _payoutReady = true;
  Object? _error;
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
      final res = await widget.kind.list(AppScope.of(context).api);
      if (!mounted) return;
      setState(() {
        _statements = [
          for (final s in (res['statements'] as List? ?? const []))
            if (s is Map) s.cast<String, dynamic>(),
        ];
        _payoutReady = res['payoutReady'] != false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final rows = _statements;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('payouts.title'))),
      body: rows == null
          ? (_error == null
                ? const Center(child: FFSpinner())
                : FFEmptyState(
                    title: context.tr('inbox.loadFailed'),
                    body: errorMessage(FFLocaleScope.of(context), _error!),
                    action: FFButton(
                      label: context.tr('comms.retry'),
                      onPressed: _load,
                    ),
                  ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  Text(
                    context.tr(kind.key('intro')),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: FFTokens.spacingMd),
                  if (!_payoutReady) ...[
                    FFAlert(
                      key: const Key('payouts-not-ready'),
                      tone: FFAlertTone.warning,
                      message: context.tr('payouts.notReady'),
                    ),
                    const SizedBox(height: FFTokens.spacingSm),
                    FFButton(
                      key: const Key('payouts-verify'),
                      label: context.tr('payouts.openVerification'),
                      onPressed: () => context.push(AppRoutes.verification),
                      variant: FFButtonVariant.secondary,
                    ),
                    const SizedBox(height: FFTokens.spacingMd),
                  ],
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: FFTokens.spacingLg,
                      ),
                      child: Text(
                        context.tr(kind.key('empty')),
                        key: const Key('payouts-empty'),
                      ),
                    )
                  else
                    for (final s in rows) ...[
                      _StatementCard(
                        kind: kind,
                        statement: s,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PartnerPayoutDetailPage(
                              kind: kind,
                              statementId: s['id'].toString(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: FFTokens.spacingSm),
                    ],
                ],
              ),
            ),
    );
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({
    required this.kind,
    required this.statement,
    required this.onTap,
  });

  final PayoutKind kind;
  final Map<String, dynamic> statement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (key, tone) = _status(statement);
    return InkWell(
      key: Key('payout-${statement['id']}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      child: FFCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatCurrency(statement['finalNetTzs'] as num? ?? 0),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FFBadge(label: context.tr(key), tone: tone),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_week(statement)} · ${context.tr(kind.key('sessions')).replaceFirst('{n}', '${kind.count(statement)}')}',
            ),
            if (statement['onHold'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.tr('payouts.onHold'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One statement with the sessions or orders it pays for.
class PartnerPayoutDetailPage extends StatefulWidget {
  const PartnerPayoutDetailPage({
    super.key,
    required this.kind,
    required this.statementId,
  });

  final PayoutKind kind;
  final String statementId;

  @override
  State<PartnerPayoutDetailPage> createState() =>
      _PartnerPayoutDetailPageState();
}

class _PartnerPayoutDetailPageState extends State<PartnerPayoutDetailPage> {
  Map<String, dynamic>? _data;
  Object? _error;
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
      final res = await widget.kind.one(
        AppScope.of(context).api,
        widget.statementId,
      );
      if (mounted) setState(() => _data = res);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Widget _line(BuildContext context, Map<String, dynamic> l) {
    final amount = Text(
      formatCurrency(l['payoutTzs'] as num? ?? 0),
      style: Theme.of(context).textTheme.labelLarge,
    );
    if (widget.kind.isVendor) {
      return ListTile(
        key: Key('payout-line-${l['orderId']}'),
        contentPadding: EdgeInsets.zero,
        title: Text('${context.tr('payouts.vendor.order')} ${l['orderId']}'),
        subtitle: Text(
          [
            l['deliveredOn']?.toString() ?? '',
            context
                .tr('payouts.vendor.items')
                .replaceFirst('{n}', '${l['itemCount'] ?? 0}'),
            context
                .tr('payouts.vendor.sales')
                .replaceFirst(
                  '{amount}',
                  formatCurrency(l['salesTzs'] as num? ?? 0),
                ),
          ].join(' · '),
        ),
        trailing: amount,
      );
    }
    return ListTile(
      key: Key('payout-line-${l['bookingId']}'),
      contentPadding: EdgeInsets.zero,
      title: Text(l['memberName']?.toString() ?? context.tr('payouts.member')),
      subtitle: Text(
        [
          '${l['date']}${l['slot'] != null ? ' · ${context.localSlotTime('${l['slot']}')}' : ''}',
          context.tr(
            l['basis'] == 'completed'
                ? 'payouts.basis.completed'
                : 'payouts.basis.tookPlace',
          ),
        ].join(' · '),
      ),
      trailing: amount,
    );
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final data = _data;
    final s = (data?['statement'] as Map?)?.cast<String, dynamic>();
    final lines = [
      for (final l in (data?['lines'] as List? ?? const []))
        if (l is Map) l.cast<String, dynamic>(),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('payouts.statement'))),
      body: s == null
          ? (_error == null
                ? const Center(child: FFSpinner())
                : FFEmptyState(
                    title: context.tr('inbox.loadFailed'),
                    body: errorMessage(FFLocaleScope.of(context), _error!),
                  ))
          : ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatCurrency(s['finalNetTzs'] as num? ?? 0),
                        key: const Key('payout-net'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    FFBadge(
                      label: context.tr(_status(s).$1),
                      tone: _status(s).$2,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_week(s)),
                const SizedBox(height: FFTokens.spacingMd),
                Text(
                  context
                      .tr(kind.key('breakdown'))
                      .replaceFirst('{list}', formatCurrency(kind.gross(s)))
                      .replaceFirst(
                        '{commission}',
                        formatCurrency(s['commissionTzs'] as num? ?? 0),
                      ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (s['status'] == 'paid') ...[
                  const SizedBox(height: FFTokens.spacingMd),
                  FFAlert(
                    key: const Key('payout-paid'),
                    tone: FFAlertTone.success,
                    message: context
                        .tr('payouts.paidTo')
                        .replaceFirst(
                          '{account}',
                          [
                            (s['paidTo'] as Map?)?['provider'],
                            if ((s['paidTo'] as Map?)?['accountLast4'] != null)
                              '····${(s['paidTo'] as Map)['accountLast4']}',
                          ].whereType<Object>().join(' '),
                        )
                        .replaceFirst(
                          '{ref}',
                          s['paymentReference']?.toString() ?? '',
                        ),
                  ),
                ],
                const SizedBox(height: FFTokens.spacingLg),
                FFSectionTitle(context.tr(kind.key('sessionsTitle'))),
                for (final l in lines) _line(context, l),
              ],
            ),
    );
  }
}
