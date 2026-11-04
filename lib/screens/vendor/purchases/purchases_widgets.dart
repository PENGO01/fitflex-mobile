// Vendor tools · S9: pieces the purchase screens share, built only from the
// shared FF* components: a purchase row, the money notice, the payment
// method pills + reference, a date field and the instalment editor.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../customers/customer_models.dart' show formatDay, parseDay, dayString;
import '../sales/sale_models.dart'
    show maxPaymentReference, paymentMethodKey, salePaymentMethods;
import '../stock/stock_history_page.dart' show stockRangePickerTheme;
import '../stock/stock_options.dart';
import 'purchase_models.dart';

String langOf(BuildContext context) =>
    FFLocaleScope.of(context).locale.languageCode;

/// "FitFlex does not pay suppliers…" (always where money appears).
class PurchaseMoneyNotice extends StatelessWidget {
  const PurchaseMoneyNotice({super.key});

  @override
  Widget build(BuildContext context) => FFAlert(
    key: const Key('purchases-money-notice'),
    message: context.tr('vendor.purchases.moneyNotice'),
  );
}

/// One purchase in a list (hub, full list, supplier profile): GRN, supplier,
/// received date, total and the payment badge, ≥ 64dp, one merged label.
class PurchaseRowTile extends StatelessWidget {
  const PurchaseRowTile({super.key, required this.row, required this.onTap});

  final Map<String, dynamic> row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tr;
    final lang = langOf(context);
    final number = row['number']?.toString() ?? '';
    final supplier =
        nameOf(row['supplier']) ?? t('vendor.purchases.noSupplier');
    final date = formatDay(row['receivedOn']?.toString(), locale: lang);
    final total = formatCurrency(intOfP(row['totalTzs']));
    final state = t(paymentStateKey(row));
    final voided = row['status'] == 'voided';
    return Semantics(
      container: true,
      button: onTap != null,
      onTap: onTap,
      label: fillIn(t('vendor.purchases.rowLabel'), {
        'number': number,
        'supplier': supplier,
        'date': date,
        'amount': total,
        'state': state,
      }),
      excludeSemantics: true,
      child: InkWell(
        key: Key('purchase-row-${row['id']}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FFTokens.spacingMd,
              vertical: FFTokens.spacingSm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(number, style: theme.textTheme.titleSmall),
                      Text(supplier, style: theme.textTheme.bodyMedium),
                      Text(date, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: FFTokens.spacingSm),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        total,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.titleSmall?.copyWith(
                          decoration: voided
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: FFTokens.spacing2xs),
                      FFBadge(
                        label: state,
                        tone: paymentStateTone(row),
                        wrap: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The S3 method pills (cash first) and the reference field.
class PurchaseMethodPicker extends StatelessWidget {
  const PurchaseMethodPicker({
    super.key,
    required this.method,
    required this.onMethod,
    required this.reference,
    required this.onReference,
    this.enabled = true,
    this.referenceError,
    this.keyPrefix = 'purchase',
  });

  final String method;
  final ValueChanged<String> onMethod;
  final TextEditingController reference;
  final ValueChanged<String> onReference;
  final bool enabled;
  final String? referenceError;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final needs = const {
      'mpesa',
      'airtel_money',
      'mixx',
      'halopesa',
      'bank',
    }.contains(method);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('vendor.pos.method'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: FFTokens.spacingXs),
        Wrap(
          spacing: FFTokens.spacingXs,
          runSpacing: FFTokens.spacingXs,
          children: [
            for (final m in salePaymentMethods)
              Semantics(
                inMutuallyExclusiveGroup: true,
                selected: method == m,
                child: FFPill(
                  key: Key('$keyPrefix-method-$m'),
                  label: context.tr(paymentMethodKey(m)),
                  filled: method == m,
                  onTap: enabled ? () => onMethod(m) : null,
                ),
              ),
          ],
        ),
        if (method != 'cash') ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFTextField(
            key: Key('$keyPrefix-reference'),
            controller: reference,
            label: context.tr(
              needs ? 'vendor.pos.reference' : 'vendor.pos.referenceOptional',
            ),
            helperText: context.tr('vendor.purchases.referenceHint'),
            errorText: referenceError,
            maxLength: maxPaymentReference,
            textCapitalization: TextCapitalization.characters,
            enabled: enabled,
            onChanged: onReference,
          ),
        ],
      ],
    );
  }
}

/// A labelled date row (≥ 48dp) that opens the localised date picker
/// between [earliest] and [latest] (EAT days).
class PurchaseDateField extends StatelessWidget {
  const PurchaseDateField({
    super.key,
    required this.label,
    required this.value,
    required this.earliest,
    required this.latest,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel,
  });

  final String label;
  final String value;
  final String earliest;
  final String latest;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? semanticLabel;

  Future<void> _pick(BuildContext context) async {
    DateTime local(String day) {
      final d = parseDay(day)!;
      return DateTime(d.year, d.month, d.day);
    }

    final first = local(earliest);
    final last = local(latest);
    var initial = local(value);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDate: initial,
      builder: (context, child) =>
          Theme(data: stockRangePickerTheme(Theme.of(context)), child: child!),
    );
    if (picked == null) return;
    onChanged(dayString(DateTime.utc(picked.year, picked.month, picked.day)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = formatDay(value, locale: langOf(context));
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${semanticLabel ?? label}, $shown',
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? () => _pick(context) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              const Icon(Icons.event_outlined),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.labelLarge),
                    Text(shown),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// The instalment rows: each a due date and an amount, with the live
/// "Instalments add up to {sum} of {left}" line (polite; error tone when
/// different). [rows] is edited in place; [onChanged] redraws.
class InstalmentRowsEditor extends StatefulWidget {
  const InstalmentRowsEditor({
    super.key,
    required this.rows,
    required this.leftTzs,
    required this.earliest,
    required this.latest,
    required this.onChanged,
    this.enabled = true,
    this.firstNumber = 1,
  });

  final List<PlanRow> rows;
  final int leftTzs;
  final String earliest;
  final String latest;
  final VoidCallback onChanged;
  final bool enabled;

  /// The number the first editable row carries (after kept paid rows).
  final int firstNumber;

  @override
  State<InstalmentRowsEditor> createState() => _InstalmentRowsEditorState();
}

class _InstalmentRowsEditorState extends State<InstalmentRowsEditor> {
  final List<TextEditingController> _amounts = [];

  void _sync() {
    while (_amounts.length < widget.rows.length) {
      _amounts.add(TextEditingController());
    }
    while (_amounts.length > widget.rows.length) {
      _amounts.removeLast().dispose();
    }
    for (var i = 0; i < widget.rows.length; i++) {
      final want = '${widget.rows[i].amountTzs}';
      if (int.tryParse(_amounts[i].text) != widget.rows[i].amountTzs) {
        _amounts[i].text = want;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _amounts) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final t = context.tr;
    final sum = widget.rows.fold<int>(0, (s, r) => s + r.amountTzs);
    final ok = sum == widget.leftTzs;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.rows.length; i++) ...[
          Text(
            fillIn(t('vendor.purchases.instalmentN'), {
              'n': widget.firstNumber + i,
            }),
            style: theme.textTheme.titleSmall,
          ),
          PurchaseDateField(
            key: Key('plan-date-$i'),
            label: t('vendor.purchases.dueDateLabel'),
            semanticLabel: fillIn(t('vendor.purchases.instalmentDue'), {
              'n': widget.firstNumber + i,
            }),
            value: widget.rows[i].dueDate,
            earliest: widget.earliest,
            latest: widget.latest,
            enabled: widget.enabled,
            onChanged: (d) {
              widget.rows[i].dueDate = d;
              widget.onChanged();
            },
          ),
          FFTextField(
            key: Key('plan-amount-$i'),
            controller: _amounts[i],
            label: t('vendor.purchases.amount'),
            semanticsLabel: fillIn(t('vendor.purchases.instalmentAmount'), {
              'n': widget.firstNumber + i,
            }),
            suffixText: 'TSh',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            enabled: widget.enabled,
            onChanged: (v) {
              widget.rows[i].amountTzs = int.tryParse(v) ?? 0;
              widget.onChanged();
            },
          ),
          const SizedBox(height: FFTokens.spacingSm),
        ],
        Semantics(
          container: true,
          liveRegion: true,
          child: Text(
            ok
                ? fillIn(t('vendor.purchases.sumCheck'), {
                    'sum': formatCurrency(sum),
                    'left': formatCurrency(widget.leftTzs),
                  })
                : fillIn(t('vendor.purchases.sumWrong'), {
                    'left': formatCurrency(widget.leftTzs),
                  }),
            key: const Key('plan-sum'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: ok ? null : theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}

/// The split controls above the rows: count (2–12), first due date,
/// every (2 weeks / month) and Split evenly.
class SplitControls extends StatelessWidget {
  const SplitControls({
    super.key,
    required this.count,
    required this.onCount,
    required this.firstDue,
    required this.onFirstDue,
    required this.every,
    required this.onEvery,
    required this.onSplit,
    required this.earliest,
    required this.latest,
    this.enabled = true,
    this.minCount = 2,
  });

  /// 2 when splitting a delivery (one row is "Pay by"); 1 for a plan change.
  final int minCount;
  final int count;
  final ValueChanged<int> onCount;
  final String firstDue;
  final ValueChanged<String> onFirstDue;
  final PlanEvery every;
  final ValueChanged<PlanEvery> onEvery;
  final VoidCallback onSplit;
  final String earliest;
  final String latest;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFQuantityStepper(
          key: const Key('plan-count'),
          value: count,
          min: minCount,
          max: purchaseMaxInstalments,
          label: t('vendor.purchases.instalmentCount'),
          addLabel: t('vendor.purchases.instalmentMore'),
          removeLabel: t('vendor.purchases.instalmentFewer'),
          enabled: enabled,
          onChanged: onCount,
        ),
        PurchaseDateField(
          key: const Key('plan-first-due'),
          label: t('vendor.purchases.firstDue'),
          value: firstDue,
          earliest: earliest,
          latest: latest,
          enabled: enabled,
          onChanged: onFirstDue,
        ),
        const SizedBox(height: FFTokens.spacingXs),
        Text(
          t('vendor.purchases.every'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: FFTokens.spacingXs),
        FFSegmented(
          key: const Key('plan-every'),
          value: every.name,
          options: [
            (PlanEvery.twoWeeks.name, t('vendor.purchases.every2w')),
            (PlanEvery.month.name, t('vendor.purchases.everyMonth')),
          ],
          onChanged: (v) => onEvery(
            v == PlanEvery.twoWeeks.name ? PlanEvery.twoWeeks : PlanEvery.month,
          ),
        ),
        const SizedBox(height: FFTokens.spacingXs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FFButton(
            key: const Key('plan-split-evenly'),
            label: t('vendor.purchases.splitEvenly'),
            variant: FFButtonVariant.secondary,
            visualDensity: VisualDensity.standard,
            onPressed: enabled ? onSplit : null,
          ),
        ),
      ],
    );
  }
}

/// A void reason dialog body field (3–200), shared by both void dialogs.
Widget voidReasonField(
  BuildContext context,
  TextEditingController c, {
  required bool enabled,
  required VoidCallback onChanged,
  Key? key,
}) => FFTextField(
  key: key,
  controller: c,
  label: context.tr('vendor.purchases.voidReason'),
  maxLength: purchaseReasonMax,
  maxLines: 3,
  minLines: 1,
  enabled: enabled,
  onChanged: (_) => onChanged(),
);
