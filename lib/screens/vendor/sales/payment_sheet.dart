// Vendor tools · S3: the payment sheet (spec §3) — how the customer paid,
// possibly with several methods, and the change to give back. The sheet
// mirrors the server's rules; the POS sends the sale and tells the sheet
// whether to close or to show a problem.
import '../../../shared/network/browser_online.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../customers/customer_models.dart';
import '../stock/stock_options.dart';
import 'sale_customer_section.dart';
import 'sale_models.dart';
import 'sales_widgets.dart';

/// What the POS made of one Complete.
class PayAttempt {
  const PayAttempt._(
    this.kind, {
    this.messageKey,
    this.values,
    this.index,
    this.action,
  });

  /// The sheet closes; the POS carries on (receipt, cart, snack).
  const PayAttempt.close() : this._(PayAttemptKind.close);

  /// The sheet stays with an inline problem ([index]: that payment row).
  const PayAttempt.stay(
    String messageKey, {
    Map<String, Object?>? values,
    int? index,
    String? action,
  }) : this._(
         PayAttemptKind.stay,
         messageKey: messageKey,
         values: values,
         index: index,
         action: action,
       );

  /// 5xx: the sheet stays with Try again and "Save and sync later".
  const PayAttempt.server() : this._(PayAttemptKind.server);

  final PayAttemptKind kind;
  final String? messageKey;
  final Map<String, Object?>? values;
  final int? index;

  /// A fix the seller can choose in the sheet, e.g. `recordToday` (a sale
  /// too old to keep its date is recorded with today's date).
  final String? action;
}

enum PayAttemptKind { close, stay, server }

/// [creditDueDate]: a pay-later sale (S4) due that EAT day.
typedef PaySubmit =
    Future<PayAttempt> Function(
      List<Map<String, dynamic>> payments, {
      bool queue,
      String? creditDueDate,
    });

/// The customer attached to the sale, as the sheet shows it.
typedef SaleCustomer = ({
  String? id,
  String? name,
  int? owedTzs,
  int? overdueTzs,
});

/// S4: what pay later needs from the POS. Null when this person may not
/// sell on credit (needs `sales` and `customers`, and both tools on).
class PayLaterSetup {
  const PayLaterSetup({
    required this.online,
    required this.saleDay,
    required this.customer,
    required this.pickCustomer,
  });

  /// Pay later is online only (never queued).
  final bool online;

  /// The sale's EAT day (YYYY-MM-DD): due dates run from it to +365.
  final String saleDay;

  /// The cart's customer right now.
  final SaleCustomer Function() customer;

  /// Opens the customer picker (updates the cart).
  final Future<void> Function() pickCustomer;
}

class _Row {
  _Row(PaymentRow row)
    : row = row,
      amount = TextEditingController(
        text: row.amountTzs > 0 ? '${row.amountTzs}' : '',
      ),
      reference = TextEditingController(text: row.reference);
  final PaymentRow row;
  final TextEditingController amount;
  final TextEditingController reference;
  void dispose() {
    amount.dispose();
    reference.dispose();
  }
}

class PaymentSheet extends StatefulWidget {
  const PaymentSheet({
    super.key,
    required this.totalTzs,
    required this.submit,
    this.onAction,
    this.payLater,
    this.referenceOptional = false,
    this.customerDetails,
  });

  final int totalTzs;
  final PaySubmit submit;

  /// Sale extras #1 (`tools.walkInSales && tools.referenceOptional`): an
  /// optional reference on every method, cash included. False: today's rule.
  final bool referenceOptional;

  /// Sale extras #2: the optional Customer section; null hides it.
  final SaleCustomerSetup? customerDetails;

  /// S4 pay later; null hides it.
  final PayLaterSetup? payLater;

  /// Applies a [PayAttempt.action] before Complete is tried again.
  final void Function(String action)? onAction;

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  late final List<_Row> _rows = [
    _Row(
      PaymentRow(
        method: 'cash',
        amountTzs: widget.totalTzs,
        referenceOptional: widget.referenceOptional,
      ),
    ),
  ];

  /// Sale extras #2: the Customer section's state (typed name and mobile
  /// in memory only, discarded when the sheet closes).
  late final SaleCustomerController? _customer = widget.customerDetails == null
      ? null
      : (SaleCustomerController(widget.customerDetails!)
          ..addListener(_onCustomer));

  void _onCustomer() {
    if (mounted) setState(() {});
  }

  bool _saving = false;
  bool _server = false;
  String? _problem;
  int? _problemIndex;
  String? _action;

  // S4 pay later.
  bool _credit = false;
  String _due = '7';
  String? _customDue;

  @override
  void dispose() {
    BrowserOnline.instance.removeListener(_onBrowserOnline);
    for (final r in _rows) {
      r.dispose();
    }
    _customer
      ?..removeListener(_onCustomer)
      ..dispose();
    super.dispose();
  }

  PaymentCheck get _check =>
      PaymentCheck(widget.totalTzs, [for (final r in _rows) r.row]);

  int _dueBefore(int index) {
    var paid = 0;
    for (var i = 0; i < _rows.length; i++) {
      if (i != index) paid += _rows[i].row.amountTzs;
    }
    return widget.totalTzs - paid;
  }

  void _edited() => setState(() {
    _problem = null;
    _problemIndex = null;
    _action = null;
    _server = false;
  });

  void _setAmount(_Row r, int amount) {
    r.row.amountTzs = amount;
    r.amount.text = '$amount';
    _edited();
  }

  /// Pay later needs a connection: the POS's own signal and (web) the
  /// browser's online state.
  bool _online(PayLaterSetup setup) =>
      setup.online && BrowserOnline.instance.value;

  @override
  void initState() {
    super.initState();
    BrowserOnline.instance.addListener(_onBrowserOnline);
  }

  void _onBrowserOnline() {
    if (mounted) setState(() {});
  }

  CreditCheck get _creditCheck =>
      CreditCheck(widget.totalTzs, [for (final r in _rows) r.row]);

  String? get _dueDate {
    final setup = widget.payLater;
    if (setup == null) return null;
    if (_due == 'custom') return _customDue;
    return addDaysTo(setup.saleDay, int.parse(_due));
  }

  bool get _creditReady {
    final setup = widget.payLater;
    if (setup == null) return false;
    final c = setup.customer();
    return _creditCheck.canComplete(
      hasCustomer: c.id != null,
      hasDueDate: _dueDate != null,
      online: setup.online && BrowserOnline.instance.value,
    );
  }

  Future<void> _completeCredit() async {
    if (!_creditReady || _saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _problem = null;
      _server = false;
    });
    final out = await widget.submit(
      _creditCheck.toRequest(),
      creditDueDate: _dueDate,
    );
    if (!mounted) return;
    if (out.kind == PayAttemptKind.close) {
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(context).pop(true);
      return;
    }
    // A pay-later sale is never kept on the device: every other answer
    // stays here with its reason; Complete tries again (same key).
    setState(() {
      _saving = false;
      _problem = fillIn(
        context.tr(out.messageKey ?? 'vendor.pos.credit.failed'),
        out.values ?? const {},
      );
      _problemIndex = out.index;
    });
  }

  Future<void> _chooseDue() async {
    final setup = widget.payLater!;
    final range = dueDateRange(setup.saleDay);
    DateTime local(String day) {
      final d = parseDay(day)!;
      return DateTime(d.year, d.month, d.day);
    }

    final picked = await showDatePicker(
      context: context,
      firstDate: local(range.earliest),
      lastDate: local(range.latest),
      initialDate: local(_dueDate ?? addDaysTo(setup.saleDay, defaultDueDays)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _due = 'custom';
      _customDue = dayString(
        DateTime.utc(picked.year, picked.month, picked.day),
      );
    });
    _edited();
  }

  Future<void> _pickCustomer() async {
    await widget.payLater?.pickCustomer();
    if (mounted) _edited();
  }

  Future<void> _complete({bool queue = false}) async {
    final check = _check;
    if (!check.canComplete || _saving) return;
    // D8: let go of the focused field BEFORE it is disabled. Disabling a
    // focused text field throws in Flutter web's semantics text editing
    // (with accessibility on).
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _problem = null;
      _server = false;
    });
    // Sale extras #2 (§2.5): the typed name / mobile become a customer id
    // first (match or create); only then is the sale sent or queued.
    final customer = _customer;
    if (customer != null && !await customer.prepare()) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (!mounted) return;
    final out = await widget.submit(check.toRequest(), queue: queue);
    if (!mounted) return;
    switch (out.kind) {
      case PayAttemptKind.close:
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(context).pop(true);
        return;
      case PayAttemptKind.stay:
        setState(() {
          _saving = false;
          _problem = fillIn(
            context.tr(out.messageKey ?? 'vendor.pos.err.payment'),
            out.values ?? const {},
          );
          _problemIndex = out.index;
          _action = out.action;
        });
      case PayAttemptKind.server:
        setState(() {
          _saving = false;
          _server = true;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final check = _check;
    final status = _statusLine(context, check);
    return PopScope(
      canPop: !_saving,
      // D8: let go of the amount / reference field before the sheet goes
      // (a field still focused while its route closes can throw on web).
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) FocusManager.instance.primaryFocus?.unfocus();
      },
      // Escape closes the sheet on web / desktop (not while saving).
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_saving) Navigator.of(context).maybePop();
          },
        },
        child: Focus(
          autofocus: true,
          child: _credit
              ? _creditBody(context)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.tr('vendor.pos.amountDue'),
                      style: theme.textTheme.labelLarge,
                    ),
                    Text(
                      formatCurrency(widget.totalTzs),
                      key: const Key('pos-pay-total'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: FFTokens.spacingMd),
                    if (check.nothingToPay)
                      Text(
                        context.tr('vendor.pos.nothingToPay'),
                        key: const Key('pos-nothing-to-pay'),
                      )
                    else ...[
                      for (var i = 0; i < _rows.length; i++)
                        _rowEditor(context, i),
                      if (check.remainingTzs > 0 &&
                          _rows.length < maxSalePayments)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FFButton(
                            key: const Key('pos-add-payment'),
                            label: context.tr('vendor.pos.addPayment'),
                            icon: Icons.add,
                            variant: FFButtonVariant.ghost,
                            visualDensity: VisualDensity.standard,
                            onPressed: _saving
                                ? null
                                : () {
                                    setState(
                                      () => _rows.add(
                                        _Row(
                                          PaymentRow(
                                            amountTzs: check.remainingTzs,
                                            referenceOptional:
                                                widget.referenceOptional,
                                          ),
                                        ),
                                      ),
                                    );
                                    _edited();
                                  },
                          ),
                        ),
                    ],
                    if (status != null) ...[
                      const SizedBox(height: FFTokens.spacingSm),
                      Semantics(
                        container: true,
                        liveRegion: true,
                        child: status,
                      ),
                    ],
                    ..._payLaterEntry(context, check),
                    ..._customerSection(context),
                    if (_problem != null) ...[
                      const SizedBox(height: FFTokens.spacingSm),
                      Semantics(
                        container: true,
                        liveRegion: true,
                        child: FFAlert(
                          key: const Key('pos-pay-problem'),
                          message: _problem!,
                          tone: FFAlertTone.error,
                        ),
                      ),
                      if (_action == 'recordToday' &&
                          widget.onAction != null) ...[
                        const SizedBox(height: FFTokens.spacingSm),
                        FFButton(
                          key: const Key('pos-record-today'),
                          label: context.tr('vendor.sync.recordToday'),
                          variant: FFButtonVariant.secondary,
                          fullWidth: true,
                          visualDensity: VisualDensity.standard,
                          onPressed: _saving
                              ? null
                              : () {
                                  widget.onAction!('recordToday');
                                  _edited();
                                  _complete();
                                },
                        ),
                      ],
                    ],
                    const SizedBox(height: FFTokens.spacingMd),
                    FFAlert(
                      key: const Key('pos-money-notice'),
                      message: context.tr('vendor.pos.moneyNotice'),
                    ),
                    const SizedBox(height: FFTokens.spacingMd),
                    if (_server) ...[
                      FFAlert(
                        key: const Key('pos-server-error'),
                        message: context.tr('vendor.pos.err.server'),
                        tone: FFAlertTone.error,
                      ),
                      const SizedBox(height: FFTokens.spacingSm),
                      FFButton(
                        key: const Key('pos-retry'),
                        label: context.tr('common.retry'),
                        fullWidth: true,
                        visualDensity: VisualDensity.standard,
                        loading: _saving,
                        onPressed: () => _complete(),
                      ),
                      const SizedBox(height: FFTokens.spacingSm),
                      FFButton(
                        key: const Key('pos-sync-later'),
                        label: context.tr('vendor.pos.syncLater'),
                        variant: FFButtonVariant.secondary,
                        fullWidth: true,
                        visualDensity: VisualDensity.standard,
                        onPressed: _saving
                            ? null
                            : () => _complete(queue: true),
                      ),
                    ] else
                      FFButton(
                        key: const Key('pos-complete'),
                        label: context.tr(
                          _saving
                              ? 'vendor.pos.completing'
                              : 'vendor.pos.complete',
                        ),
                        fullWidth: true,
                        maxLines: 2,
                        visualDensity: VisualDensity.standard,
                        loading: _saving,
                        onPressed: check.canComplete ? () => _complete() : null,
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  /// "Pay later" under the rows while something is left to pay (§3.3).
  List<Widget> _payLaterEntry(BuildContext context, PaymentCheck check) {
    final setup = widget.payLater;
    if (setup == null || check.nothingToPay || check.remainingTzs <= 0) {
      return const [];
    }
    return [
      const SizedBox(height: FFTokens.spacingSm),
      FFButton(
        key: const Key('vendor-pos-paylater'),
        label: context.tr('vendor.pos.payLater'),
        icon: Icons.schedule,
        variant: FFButtonVariant.secondary,
        fullWidth: true,
        visualDensity: VisualDensity.standard,
        onPressed: _saving || !_online(setup)
            ? null
            : () {
                setState(() => _credit = true);
                _edited();
                if (setup.customer().id == null) _pickCustomer();
              },
      ),
      if (!_online(setup))
        Semantics(
          container: true,
          liveRegion: true,
          child: Text(
            context.tr('vendor.pos.credit.needsConnection'),
            key: const Key('pos-paylater-offline'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ];
  }

  Widget _creditBody(BuildContext context) {
    final theme = Theme.of(context);
    final setup = widget.payLater!;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final credit = _creditCheck;
    final customer = setup.customer();
    final due = _dueDate;
    final owed = customer.owedTzs ?? 0;
    final overdue = customer.overdueTzs ?? 0;
    String? status;
    if (credit.fullyPaid) {
      status = context.tr('vendor.pos.credit.fullyPaid');
    } else if (credit.wouldGiveChange) {
      status = context.tr('vendor.pos.credit.noChange');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            fillIn(context.tr('vendor.pos.credit.title'), {
              'amount': formatCurrency(credit.balanceTzs),
            }),
            key: const Key('pos-credit-title'),
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        // Customer (required).
        Semantics(
          button: true,
          label: customer.id == null
              ? context.tr('vendor.pos.customer.pick')
              : fillIn(context.tr('vendor.receipt.customer'), {
                  'name':
                      customer.name ?? context.tr('vendor.customers.unnamed'),
                }),
          excludeSemantics: true,
          child: ListTile(
            key: const Key('pos-credit-customer'),
            minTileHeight: 56,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(
              customer.id == null
                  ? context.tr('vendor.pos.customer.pick')
                  : customer.name ?? context.tr('vendor.customers.unnamed'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _saving ? null : _pickCustomer,
          ),
        ),
        if (customer.id != null && owed > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: FFAlert(
              key: const Key('pos-credit-already-owes'),
              message: [
                fillIn(context.tr('vendor.pos.credit.alreadyOwes'), {
                  'name':
                      customer.name ?? context.tr('vendor.customers.unnamed'),
                  'amount': formatCurrency(owed),
                }),
                if (overdue > 0)
                  fillIn(context.tr('vendor.customers.overdueAmount'), {
                    'amount': formatCurrency(overdue),
                  }),
              ].join(' '),
              tone: FFAlertTone.warning,
            ),
          ),
        Text(
          context.tr('vendor.pos.dueDate'),
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: FFTokens.spacingXs),
        Wrap(
          spacing: FFTokens.spacingXs,
          runSpacing: FFTokens.spacingXs,
          children: [
            for (final d in const ['7', '14', '30'])
              Semantics(
                inMutuallyExclusiveGroup: true,
                selected: _due == d,
                child: FFPill(
                  key: Key('pos-due-$d'),
                  label: context.tr('vendor.pos.credit.in$d'),
                  filled: _due == d,
                  onTap: _saving
                      ? null
                      : () {
                          setState(() => _due = d);
                          _edited();
                        },
                ),
              ),
            Semantics(
              inMutuallyExclusiveGroup: true,
              selected: _due == 'custom',
              child: FFPill(
                key: const Key('pos-due-custom'),
                label: context.tr('vendor.pos.credit.choose'),
                filled: _due == 'custom',
                onTap: _saving ? null : _chooseDue,
              ),
            ),
          ],
        ),
        if (due != null)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingXs),
            child: Text(
              fillIn(context.tr('vendor.pos.credit.dueOn'), {
                'date': formatDay(due, locale: lang),
              }),
              key: const Key('pos-due-resolved'),
            ),
          ),
        const SizedBox(height: FFTokens.spacingMd),
        Text(
          context.tr('vendor.pos.credit.paidNow'),
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: FFTokens.spacingXs),
        for (var i = 0; i < _rows.length; i++) _rowEditor(context, i),
        if (_rows.length < maxSalePayments)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FFButton(
              key: const Key('pos-add-payment'),
              label: context.tr('vendor.pos.addPayment'),
              icon: Icons.add,
              variant: FFButtonVariant.ghost,
              visualDensity: VisualDensity.standard,
              onPressed: _saving
                  ? null
                  : () {
                      setState(
                        () => _rows.add(
                          _Row(
                            PaymentRow(
                              referenceOptional: widget.referenceOptional,
                            ),
                          ),
                        ),
                      );
                      _edited();
                    },
            ),
          ),
        Semantics(
          container: true,
          liveRegion: true,
          child: Text(
            fillIn(context.tr('vendor.pos.credit.balance'), {
              'amount': formatCurrency(credit.balanceTzs),
            }),
            key: const Key('pos-credit-balance'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (status != null) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              status,
              key: const Key('pos-credit-status'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: warningText(context),
              ),
            ),
          ),
        ],
        ..._customerSection(context, typeOnly: true),
        if (_problem != null) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Semantics(
            container: true,
            liveRegion: true,
            child: FFAlert(
              key: const Key('pos-pay-problem'),
              message: _problem!,
              tone: FFAlertTone.error,
            ),
          ),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        FFAlert(
          key: const Key('pos-money-notice'),
          message: context.tr('vendor.pos.moneyNotice'),
        ),
        const SizedBox(height: FFTokens.spacingXs),
        FFAlert(
          key: const Key('pos-credit-notice'),
          message: context.tr('vendor.pos.credit.notice'),
        ),
        if (!_online(setup)) ...[
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            context.tr('vendor.pos.credit.needsConnection'),
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        FFButton(
          key: const Key('pos-credit-complete'),
          label: context.tr('vendor.pos.credit.complete'),
          fullWidth: true,
          maxLines: 2,
          visualDensity: VisualDensity.standard,
          loading: _saving,
          onPressed: _creditReady ? _completeCredit : null,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFButton(
          key: const Key('pos-credit-back'),
          label: context.tr('vendor.pos.credit.backToFull'),
          variant: FFButtonVariant.ghost,
          fullWidth: true,
          maxLines: 2,
          visualDensity: VisualDensity.standard,
          onPressed: _saving
              ? null
              : () {
                  setState(() => _credit = false);
                  _edited();
                },
        ),
      ],
    );
  }

  /// Sale extras #2 (§2.4 item 6): the Customer card, and the "couldn't
  /// save the customer" alert with Try again / Complete without customer.
  List<Widget> _customerSection(BuildContext context, {bool typeOnly = false}) {
    final c = _customer;
    if (c == null) return const [];
    return [
      const SizedBox(height: FFTokens.spacingSm),
      SaleCustomerSection(controller: c, saving: _saving, typeOnly: typeOnly),
      if (c.saveFailed && !typeOnly) ...[
        const SizedBox(height: FFTokens.spacingSm),
        Semantics(
          container: true,
          liveRegion: true,
          child: FFAlert(
            key: const Key('pos-cust-save-failed'),
            message: context.tr('vendor.pos.cust.saveFailed'),
            tone: FFAlertTone.error,
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFButton(
          key: const Key('pos-cust-retry'),
          label: context.tr('common.retry'),
          fullWidth: true,
          visualDensity: VisualDensity.standard,
          onPressed: _saving ? null : () => _complete(),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFButton(
          key: const Key('pos-cust-without'),
          label: context.tr('vendor.pos.cust.completeWithout'),
          variant: FFButtonVariant.secondary,
          fullWidth: true,
          maxLines: 2,
          visualDensity: VisualDensity.standard,
          onPressed: _saving
              ? null
              : () {
                  c.completeWithout();
                  _complete();
                },
        ),
      ],
    ];
  }

  Widget? _statusLine(BuildContext context, PaymentCheck check) {
    final theme = Theme.of(context);
    if (check.nothingToPay) return null;
    if (check.remainingTzs > 0) {
      return Text(
        fillIn(context.tr('vendor.pos.remaining'), {
          'amount': formatCurrency(check.remainingTzs),
        }),
        key: const Key('pos-remaining'),
        style: theme.textTheme.titleSmall?.copyWith(
          color: warningText(context),
        ),
      );
    }
    if (check.nonCashOver) {
      return Text(
        fillIn(context.tr('vendor.pos.overNonCash'), {
          'method': context.tr(paymentMethodKey(check.overMethod)),
        }),
        key: const Key('pos-over-non-cash'),
        style: theme.textTheme.titleSmall?.copyWith(
          color: warningText(context),
        ),
      );
    }
    // Caught here, before sending (the server refuses the same).
    if (check.paidTooLarge) {
      return Text(
        context.tr('vendor.pos.err.paidTooLargeLocal'),
        key: const Key('pos-paid-too-large'),
        style: theme.textTheme.titleSmall?.copyWith(
          color: warningText(context),
        ),
      );
    }
    if (check.changeTooLarge) {
      return Text(
        fillIn(context.tr('vendor.pos.err.changeTooLargeLocal'), {
          'amount': formatCurrency(check.totalTzs + maxChangeOverTotalTzs),
        }),
        key: const Key('pos-change-too-large'),
        style: theme.textTheme.titleSmall?.copyWith(
          color: warningText(context),
        ),
      );
    }
    if (check.changeTzs > 0) {
      return Text(
        fillIn(context.tr('vendor.pos.changeDue'), {
          'amount': formatCurrency(check.changeTzs),
        }),
        key: const Key('pos-change-due'),
        style: theme.textTheme.titleMedium?.copyWith(
          color: successText(context),
        ),
      );
    }
    return null;
  }

  Widget _rowEditor(BuildContext context, int index) {
    final r = _rows[index];
    final method = r.row.method;
    final cash = method == 'cash';
    final due = _dueBefore(index);
    // Complete stays disabled while it is missing, so say why at once.
    final showRefError = r.row.referenceMissing;
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      child: FFCard(
        key: Key('pos-payment-$index'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('vendor.pos.method'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (_rows.length >= 2 || _credit)
                  IconButton(
                    key: Key('pos-remove-payment-$index'),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      visualDensity: VisualDensity.standard,
                    ),
                    tooltip: fillIn(context.tr('vendor.pos.removePayment'), {
                      'method': context.tr(paymentMethodKey(method)),
                    }),
                    icon: const Icon(Icons.close),
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() => _rows.removeAt(index).dispose());
                            _edited();
                          },
                  ),
              ],
            ),
            Wrap(
              spacing: FFTokens.spacingXs,
              runSpacing: FFTokens.spacingXs,
              children: [
                for (final m in salePaymentMethods)
                  Semantics(
                    inMutuallyExclusiveGroup: true,
                    child: FFPill(
                      key: Key('pos-method-$index-$m'),
                      label: context.tr(paymentMethodKey(m)),
                      filled: method == m,
                      onTap: () {
                        if (_saving) return;
                        r.row.method = m;
                        // Sale extras #1 (AC-4): with references optional,
                        // switching to Cash keeps what was typed.
                        if (m == 'cash' && !widget.referenceOptional) {
                          r.row.reference = '';
                        }
                        _edited();
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingSm),
            FFTextField(
              key: Key('pos-amount-$index'),
              controller: r.amount,
              label: context.tr(
                cash ? 'vendor.pos.cashReceived' : 'vendor.pos.amount',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              enabled: !_saving,
              // A refusal about this row (e.g. its reference) shows on it too.
              errorText: _problemIndex == index ? _problem : null,
              onChanged: (v) {
                r.row.amountTzs = int.tryParse(v) ?? 0;
                _edited();
              },
            ),
            if (cash && due > 0) ...[
              const SizedBox(height: FFTokens.spacingXs),
              Wrap(
                spacing: FFTokens.spacingXs,
                runSpacing: FFTokens.spacingXs,
                children: [
                  for (final (i, amount) in quickCashAmounts(due).indexed)
                    FFPill(
                      key: Key('pos-quick-$index-$amount'),
                      label: i == 0
                          ? context.tr('vendor.pos.exact')
                          : formatMoney(amount),
                      filled: r.row.amountTzs == amount,
                      onTap: () {
                        if (!_saving) _setAmount(r, amount);
                      },
                    ),
                ],
              ),
            ],
            if (method != null && (!cash || widget.referenceOptional)) ...[
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                key: Key('pos-reference-$index'),
                controller: r.reference,
                label: context.tr(
                  r.row.needsReference
                      ? 'vendor.pos.reference'
                      : 'vendor.pos.referenceOptional',
                ),
                semanticsLabel: widget.referenceOptional
                    ? fillIn(context.tr('vendor.pos.a11y.referenceFor'), {
                        'method': context.tr(paymentMethodKey(method)),
                      })
                    : null,
                helperText: context.tr(
                  cash
                      ? 'vendor.pos.referenceHintCash'
                      : 'vendor.pos.referenceHint',
                ),
                errorText: showRefError
                    ? context.tr('vendor.pos.referenceRequired')
                    : null,
                maxLength: maxPaymentReference,
                // One line: the server refuses control characters (a
                // pasted newline included).
                inputFormatters: [
                  FilteringTextInputFormatter.deny(referenceControlChars),
                ],
                textCapitalization: TextCapitalization.characters,
                enabled: !_saving,
                onChanged: (v) {
                  r.row.reference = v;
                  _edited();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
