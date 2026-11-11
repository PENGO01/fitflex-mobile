// Vendor tools · S3: pieces the sales screens share — the receipt body, the
// "waiting to sync" / "needs fixing" banners, and the gate every sales route
// passes (flag + permission). Built only from the shared FF* components.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/tone_theme.dart';
import '../documents/document_view.dart' show VatBlock;
import '../stock/stock_options.dart';
import 'offline_sale_queue.dart';
import 'receipt_data.dart';
import 'sale_models.dart';

const salesHomeRoute = '/vendor/home?open=sales';
const posRoute = '/vendor/sales/new';
const salesSyncRoute = '/vendor/sales/sync';
String saleReceiptRoute(String id) =>
    '/vendor/sales/receipt/${Uri.encodeComponent(id)}';
String queuedReceiptRoute(String ref) =>
    '/vendor/sales/receipt/queued/${Uri.encodeComponent(ref)}';
String saleDetailRoute(String id) => '/vendor/sales/${Uri.encodeComponent(id)}';

/// Ids and refs in sales addresses: the characters the server issues.
final salesIdPattern = RegExp(r'^[A-Za-z0-9._:-]{1,100}$');

/// Checks a sales route may open: the feature is on and this person has
/// `sales`. Otherwise leaves (no message when the feature is off; a
/// "no access" message without the permission) and answers false.
/// [allowQueued]: the sync screen still opens while sales wait on the
/// device, even with the feature off (§6.6).
Future<VendorTools?> enterSalesRoute(
  BuildContext context, {
  bool allowQueued = false,
}) async {
  final tools = await VendorToolsOptions.of(context);
  if (!context.mounted) return null;
  final session = SalesSession.of(context);
  await session?.load();
  if (!context.mounted) return null;
  if (!tools.walkInSales) {
    if (allowQueued && session != null && !session.isEmpty) {
      session.featureOff();
      return tools;
    }
    context.go('/vendor/home');
    return null;
  }
  session?.featureOn();
  if (!canVendor(context, 'sales')) {
    FFSnack.error(context, context.tr('vendor.sales.noAccess'));
    context.go('/vendor/home');
    return null;
  }
  return tools;
}

/// The words of a payment method in [t]'s language.
String methodLabel(String Function(String) t, String? method) =>
    t(paymentMethodKey(method));

/// "Cash + M-Pesa".
String methodsSummary(BuildContext context, Iterable<Object?> methods) => [
  for (final m in methods) methodLabel(context.tr, m?.toString()),
].join(' + ');

/// Stacked banners: offline note (optional), sales waiting with Sync now,
/// sales needing fixing with a link to the sync screen, and the paused
/// states (switched off, business suspended).
class SalesSyncBanners extends StatelessWidget {
  const SalesSyncBanners({super.key, required this.session, this.offline});

  final SalesSession session;

  /// The POS offline banner text, when offline.
  final String? offline;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final waiting = session.waiting.length;
        final conflicts = session.conflicts.length;
        final children = <Widget>[
          if (offline != null)
            FFAlert(key: const Key('sales-offline-banner'), message: offline!),
          if (session.suspended)
            FFAlert(
              key: const Key('sales-suspended-banner'),
              message: context.tr('vendor.sales.suspended'),
              tone: FFAlertTone.warning,
            ),
          if (waiting > 0)
            _withAction(
              context,
              FFAlert(
                key: const Key('sales-waiting-banner'),
                message: fillIn(
                  context.tr(pluralKey('vendor.sync.banner', waiting)),
                  {'n': waiting},
                ),
              ),
              FFButton(
                key: const Key('sales-sync-now'),
                label: context.tr(
                  session.syncing ? 'vendor.sync.syncing' : 'vendor.sync.now',
                ),
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
                visualDensity: VisualDensity.standard,
                loading: session.syncing,
                onPressed: session.pause == SalesSyncPause.featureOff
                    ? null
                    : () => unawaited(session.sync(manual: true)),
              ),
            ),
          if (conflicts > 0)
            _withAction(
              context,
              FFAlert(
                key: const Key('sales-conflicts-banner'),
                message: fillIn(
                  context.tr(pluralKey('vendor.sync.conflicts', conflicts)),
                  {'n': conflicts},
                ),
                tone: FFAlertTone.warning,
              ),
              FFButton(
                key: const Key('sales-open-sync'),
                label: context.tr('vendor.sync.fix'),
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
                visualDensity: VisualDensity.standard,
                onPressed: () => context.push(salesSyncRoute),
              ),
            ),
        ];
        if (children.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in children)
              Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                child: c,
              ),
          ],
        );
      },
    );
  }

  Widget _withAction(BuildContext context, Widget alert, Widget action) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          alert,
          Align(alignment: AlignmentDirectional.centerEnd, child: action),
        ],
      );
}

/// A label and an amount on one line (amount right, tabular figures).
class MoneyRow extends StatelessWidget {
  const MoneyRow(
    this.label,
    this.amount, {
    super.key,
    this.strong = false,
    this.color,
    this.strike = false,
  });

  final String label;
  final String amount;
  final bool strong;
  final Color? color;
  final bool strike;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        (strong ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
            ?.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
              decoration: strike ? TextDecoration.lineThrough : null,
            );
    // Its own screen-reader node: "Total, TSh 45,000".
    return Semantics(
      container: true,
      label: label.isEmpty ? amount : '$label, $amount',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: style)),
            const SizedBox(width: FFTokens.spacingSm),
            Text(amount, style: style),
          ],
        ),
      ),
    );
  }
}

/// The receipt body (spec §4.1), in the language [t] answers in.
class ReceiptView extends StatelessWidget {
  const ReceiptView({
    super.key,
    required this.data,
    required this.t,
    required this.lang,
    this.audit = false,
    this.headingFocus,
    this.tin,
    this.vrn,
  });

  final ReceiptData data;

  /// S5: the seller's TIN and VRN, only when VAT applied to this sale (the
  /// server's document says so; O-12).
  final String? tin;
  final String? vrn;
  final String Function(String key) t;
  final String lang;

  /// Sale detail: who changed a price, when it reached FitFlex, the note.
  final bool audit;

  /// Focus lands on the receipt number after completion.
  final FocusNode? headingFocus;

  String _fill(String key, Map<String, Object?> v) {
    var out = t(key);
    v.forEach((k, val) => out = out.replaceAll('{$k}', '$val'));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final number = data.number;
    final invoice = data.credit && !data.queued ? data.invoiceNumber : null;
    final heading = invoice != null
        ? '${t('vendor.doc.invoice')} $invoice'
        : number == null || data.queued
        ? t('vendor.documents.receipt')
        : _fill('vendor.pos.receiptNo', {'number': number});
    return FFCard(
      key: const Key('sales-receipt'),
      // Each line of the receipt is its own node (not one long label).
      child: _SemanticRows(
        children: [
          if (data.business != null)
            Text(data.business!, style: theme.textTheme.titleLarge),
          if (data.contact != null) Text(data.contact!, style: muted),
          if (data.address != null) Text(data.address!, style: muted),
          if (tin != null)
            Text(
              _fill('vendor.doc.tin', {'tin': tin}),
              key: const Key('sales-receipt-tin'),
              style: muted,
            ),
          if (vrn != null)
            Text(
              _fill('vendor.doc.vrn', {'vrn': vrn}),
              key: const Key('sales-receipt-vrn'),
              style: muted,
            ),
          const SizedBox(height: FFTokens.spacingSm),
          Focus(
            focusNode: headingFocus,
            child: Semantics(
              header: true,
              child: Text(
                heading,
                key: const Key('sales-receipt-number'),
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          if (invoice != null && number != null)
            Text(
              _fill('vendor.doc.saleRef', {'number': number}),
              key: const Key('sales-receipt-sale-ref'),
              style: muted,
            ),
          if (data.queued) ...[
            const SizedBox(height: FFTokens.spacingXs),
            Wrap(
              spacing: FFTokens.spacingSm,
              runSpacing: FFTokens.spacingXs,
              children: [
                FFBadge(
                  key: const Key('sales-receipt-waiting'),
                  label: t('vendor.pos.waitingSync'),
                  tone: FFBadgeTone.brand,
                  wrap: true,
                ),
                Text(
                  _fill('vendor.pos.tempRef', {'ref': data.tempRef}),
                  style: muted,
                ),
              ],
            ),
            Text(t('vendor.pos.waitingSyncBody'), style: muted),
          ],
          Text(eatDateTime(data.soldAt, locale: lang), style: muted),
          if (data.hasCustomer)
            Text(
              data.customerName != null
                  ? _fill('vendor.receipt.customer', {
                      'name': data.customerName,
                    })
                  : data.queued
                  ? t('vendor.receipt.customerAfterSync')
                  : _fill('vendor.receipt.customer', {
                      'name': t(data.unnamedCustomerKey),
                    }),
              key: const Key('sales-receipt-customer'),
            ),
          // Sale extras (Q-9): the sale detail only, never the receipt.
          if (audit && customerTypeKey(data.customerType) != null)
            Text(
              _fill('vendor.sales.customerTypeLine', {
                'type': t(customerTypeKey(data.customerType)!),
              }),
              key: const Key('sale-detail-customer-type'),
              style: muted,
            ),
          if (data.credit)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FFBadge(
                key: const Key('sales-receipt-paylater'),
                label: t('vendor.sales.payLaterBadge'),
                tone: FFBadgeTone.brand,
              ),
            ),
          if (data.servedBy != null)
            Text(
              _fill('vendor.pos.servedBy', {'name': data.servedBy}),
              style: muted,
            ),
          if (audit && data.lateRecorded && data.recordedAt != null)
            Text(
              _fill('vendor.sales.recordedAt', {
                'time': eatDateTime(data.recordedAt, locale: lang),
              }),
              style: muted,
            ),
          const Divider(height: FFTokens.spacingLg),
          for (final l in data.lines) _line(context, l, muted),
          const Divider(height: FFTokens.spacingLg),
          MoneyRow(t('vendor.pos.subtotal'), formatMoney(data.subtotalTzs)),
          if (data.discountsTzs > 0)
            MoneyRow(
              t('vendor.pos.discounts'),
              '−${formatMoney(data.discountsTzs)}',
            ),
          MoneyRow(
            t('vendor.pos.total'),
            formatCurrency(data.totalTzs),
            strong: true,
            strike: data.voided,
          ),
          // S7 §4.1: active refunds and what the sale is worth after them.
          if (data.refundedTzs > 0 && !data.voided) ...[
            MoneyRow(
              t('vendor.refunds.refundsRow'),
              '−${formatCurrency(data.refundedTzs)}',
              key: const Key('sales-receipt-refunds'),
            ),
            MoneyRow(
              t('vendor.refunds.netAfter'),
              formatCurrency(data.netAfterRefundsTzs),
              strong: true,
              key: const Key('sales-receipt-net-after'),
            ),
          ],
          if (data.hasVat)
            VatBlock(
              vatIncludedTzs: data.vatIncludedTzs,
              rows: data.vatSummary,
              t: t,
            ),
          if (data.payments.isNotEmpty)
            const SizedBox(height: FFTokens.spacingSm),
          for (final p in data.payments)
            MoneyRow(
              p.reference == null
                  ? methodLabel(t, p.method)
                  : '${methodLabel(t, p.method)} (${p.reference})',
              formatMoney(p.amountTzs),
            ),
          if (data.credit) ...[
            const SizedBox(height: FFTokens.spacingSm),
            MoneyRow(
              t('vendor.pos.credit.paidNow'),
              formatMoney(data.paidNowTzs),
              key: const Key('sales-receipt-paid-now'),
            ),
            MoneyRow(
              t('vendor.receipt.balanceAtSale'),
              formatCurrency(data.balanceAtSaleTzs),
              strong: true,
              key: const Key('sales-receipt-balance'),
            ),
            if (data.dueDate != null)
              MoneyRow(
                t('vendor.receipt.dueBy'),
                receiptDay(data.dueDate, lang),
                key: const Key('sales-receipt-due'),
              ),
          ] else if (data.changeTzs > 0)
            MoneyRow(t('vendor.pos.change'), formatMoney(data.changeTzs)),
          if (audit && data.note != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Text(_fill('vendor.sales.noteLabel', {'note': data.note})),
          ],
          const Divider(height: FFTokens.spacingLg),
          if (data.business != null)
            Text(
              _fill(
                data.credit
                    ? 'vendor.receipt.closingCredit'
                    : 'vendor.pos.receiptFooter',
                {'business': data.business},
              ),
            ),
          Text(t('vendor.pos.notFiscal'), style: muted),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, ReceiptLine l, TextStyle? muted) {
    final name = l.variant == null ? l.name : '${l.name} (${l.variant})';
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MoneyRow(
              '${l.qty} × $name',
              l.vatCode == null
                  ? formatMoney(l.qty * l.unitPriceTzs)
                  : '${formatMoney(l.qty * l.unitPriceTzs)} ${l.vatCode}',
            ),
            if (l.qty > 1 || l.priceChanged)
              Text('@ ${formatMoney(l.unitPriceTzs)}', style: muted),
            if (audit && l.priceChanged)
              Text(
                l.priceChangedBy == null
                    ? _fill('vendor.pos.priceChanged', {
                        'amount': formatCurrency(l.listPriceTzs),
                      })
                    : _fill('vendor.pos.priceChangedBy', {
                        'name': l.priceChangedBy,
                        'amount': formatCurrency(l.listPriceTzs),
                      }),
                key: const Key('sales-line-price-changed'),
                style: muted,
              ),
            if (l.discountTzs > 0)
              MoneyRow(
                t('vendor.pos.lineDiscountShort'),
                '−${formatMoney(l.discountTzs)}',
              ),
            if (l.refundedQty > 0 && !data.voided)
              Text(
                _fill('vendor.refunds.lineRefunded', {'n': l.refundedQty}),
                key: const Key('sales-line-refunded'),
                style: muted,
              ),
          ],
        ),
      ),
    );
  }
}

/// English | Kiswahili for the receipt only (never the app language).
class ReceiptLanguageToggle extends StatelessWidget {
  const ReceiptLanguageToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('vendor.pos.receiptLanguage'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: FFTokens.spacingXs),
      FFSegmented(
        key: const Key('sales-receipt-language'),
        value: value,
        options: [
          ('en', context.tr('lang.name.en')),
          ('sw', context.tr('lang.name.sw')),
        ],
        onChanged: onChanged,
      ),
    ],
  );
}

/// The success tone's text colour (change due), readable in both themes.
Color successText(BuildContext context) => FFToneTheme.of(context).success.fg;
Color warningText(BuildContext context) => FFToneTheme.of(context).warning.fg;

/// A receipt column whose rows are separate screen-reader nodes, so a
/// screen reader moves line by line instead of reading one long label.
class _SemanticRows extends StatelessWidget {
  const _SemanticRows({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Semantics(
    explicitChildNodes: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in children)
          c is Divider || c is SizedBox
              ? c
              : Semantics(container: true, child: c),
      ],
    ),
  );
}
