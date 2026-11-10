import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import 'widgets/statement_models.dart';
import '../../shared/ff_datetime.dart';

FFBadgeTone statementTone(String status) => switch (status) {
  'paid' => FFBadgeTone.success,
  'approved' => FFBadgeTone.brand,
  'in_review' || 'payment_due' => FFBadgeTone.warning,
  _ => FFBadgeTone.gray,
};

/// "−TSh 3,500" for money taken off, "TSh 3,500" otherwise.
String signedCurrency(num value) =>
    '${value < 0 ? '−' : ''}${formatCurrency(value.abs())}';

/// One row of the owner's statements list.
class OwnerStatementCard extends StatelessWidget {
  const OwnerStatementCard({super.key, required this.statement, this.onTap});

  final OwnerStatement statement;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = statement;
    final theme = Theme.of(context);
    return FFCard(
      child: InkWell(
        key: Key('statement-${s.id}'),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(s.monthLabel, style: theme.textTheme.titleSmall),
                ),
                if (s.onHold) ...[
                  FFBadge(
                    label: context.tr('owner.statementOnHold'),
                    tone: FFBadgeTone.danger,
                  ),
                  const SizedBox(width: 6),
                ],
                FFBadge(
                  label: context.tr('owner.statementStatus.${s.status}'),
                  tone: statementTone(s.status),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${s.visits} ${context.tr('owner.statementVisits').toLowerCase()}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  formatCurrency(s.payableTzs),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
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

/// One statement: what the gym earned, what was taken off, and how it was paid.
class OwnerStatementPage extends StatefulWidget {
  const OwnerStatementPage({super.key, required this.statementId, this.load});

  final String statementId;

  /// Replaces the API call in tests.
  final Future<OwnerStatementDetail> Function(String id)? load;

  @override
  State<OwnerStatementPage> createState() => _OwnerStatementPageState();
}

class _OwnerStatementPageState extends State<OwnerStatementPage> {
  OwnerStatementDetail? _detail;
  bool _failed = false;
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
      final load = widget.load;
      final detail = load != null
          ? await load(widget.statementId)
          : OwnerStatementDetail.fromJson(
              await AppScope.of(
                context,
              ).api.ownerSettlement(widget.statementId),
            );
      if (mounted) setState(() => _detail = detail);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          detail?.statement.monthLabel ?? context.tr('owner.statements'),
        ),
      ),
      body: detail == null
          ? Center(
              child: _failed
                  ? FFEmptyState(title: context.tr('owner.statementLoadFailed'))
                  : const FFSpinner(),
            )
          : _body(context, detail),
    );
  }

  Widget _body(BuildContext context, OwnerStatementDetail detail) {
    final s = detail.statement;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(s.gymName ?? '', style: theme.textTheme.bodyMedium),
            ),
            if (s.onHold) ...[
              FFBadge(
                label: context.tr('owner.statementOnHold'),
                tone: FFBadgeTone.danger,
              ),
              const SizedBox(width: 6),
            ],
            FFBadge(
              label: context.tr('owner.statementStatus.${s.status}'),
              tone: statementTone(s.status),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (s.onHold || s.status == 'preparing')
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FFAlert(
              message: context.tr(
                s.onHold
                    ? 'owner.statementOnHoldHint'
                    : 'owner.statementPreparingHint',
              ),
              tone: s.onHold ? FFAlertTone.warning : FFAlertTone.info,
            ),
          ),
        FFCard(
          child: Column(
            children: [
              _Row(
                label: context.tr('owner.statementEarned'),
                value: formatCurrency(s.earnedTzs),
                hint:
                    '${s.visits} ${context.tr('owner.statementVisits').toLowerCase()} · '
                    '${s.members} ${context.tr('owner.statementMembers').toLowerCase()}',
              ),
              if (s.networkAdjustmentTzs != 0)
                _Row(
                  label: context.tr('owner.statementNetwork'),
                  value: signedCurrency(s.networkAdjustmentTzs),
                ),
              if (s.adjustmentsTzs != 0)
                _Row(
                  label: context.tr('owner.statementAdjustments'),
                  value: signedCurrency(s.adjustmentsTzs),
                ),
              if (s.carriedForwardTzs > 0)
                _Row(
                  label: context.tr('owner.statementCarried'),
                  value: formatCurrency(s.carriedForwardTzs),
                ),
              const Divider(height: 20),
              _Row(
                key: const Key('statement-net'),
                label: context.tr(
                  s.isPaid
                      ? 'owner.statementPaidAmount'
                      : 'owner.statementToPay',
                ),
                value: formatCurrency(s.payableTzs),
                strong: true,
              ),
            ],
          ),
        ),
        if (s.isPaid)
          FFCard(
            child: Column(
              children: [
                if (s.paidAt != null)
                  _Row(
                    label: context.tr('owner.statementPaidOn'),
                    value: _date(s.paidAt!),
                  ),
                if (s.paymentReference != null)
                  _Row(
                    label: context.tr('owner.statementReference'),
                    value: s.paymentReference!,
                  ),
                if (s.payoutAccountLast4 != null)
                  _Row(
                    label: context.tr('owner.statementAccount'),
                    value: '····${s.payoutAccountLast4}',
                  ),
              ],
            ),
          ),
        if (detail.lines.isNotEmpty) ...[
          const SizedBox(height: 8),
          FFSectionTitle(context.tr('owner.statementMembers')),
          ...detail.lines.map((l) => _LineCard(line: l)),
        ],
        if (detail.adjustments.isNotEmpty) ...[
          const SizedBox(height: 8),
          FFSectionTitle(context.tr('owner.statementAdjustments')),
          ...detail.adjustments.map(
            (a) => FFCard(
              child: _Row(
                label: context.tr('owner.statementAdjustment.${a.type}'),
                value: signedCurrency(a.amountTzs),
                hint: a.reason,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // Paid dates are shown in East Africa Time, like the statement periods.
  String _date(DateTime at) {
    final eat = at.toUtc().add(const Duration(hours: 3));
    return '${eat.day} ${shortMonthName(eat.month)} ${eat.year}';
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.strong = false,
  });

  final String label;
  final String value;
  final String? hint;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: strong
                      ? theme.textTheme.titleSmall
                      : theme.textTheme.bodyMedium,
                ),
                if (hint != null && hint!.isNotEmpty)
                  Text(hint!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style:
                (strong
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.labelLarge)
                    ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.line});

  final OwnerStatementLine line;

  @override
  Widget build(BuildContext context) {
    final l = line;
    final theme = Theme.of(context);
    final bracket = l.bracket == null || l.bracket == 'none'
        ? null
        : context.tr('owner.statementBracket.${l.bracket}');
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.memberCode ?? '—',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              FFBadge(
                label: context.tr(
                  l.sponsored
                      ? 'owner.statementSponsored'
                      : 'owner.statementPass',
                ),
                tone: l.sponsored ? FFBadgeTone.brand : FFBadgeTone.gray,
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Row(
            label:
                '${l.visits} ${context.tr('owner.statementVisits').toLowerCase()}'
                '${bracket == null ? '' : ' · $bracket'}',
            value: formatCurrency(l.finalTzs),
            hint: l.networkAdjustmentTzs != 0
                ? '${formatCurrency(l.earnedTzs)} ${signedCurrency(l.networkAdjustmentTzs)}'
                : null,
          ),
          if (l.visitDates.isNotEmpty)
            Text(
              l.visitDates.map(statementDay).join(' · '),
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
