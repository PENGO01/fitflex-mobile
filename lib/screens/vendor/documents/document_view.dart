// Vendor tools · S5: the native view of a server document (design spec
// §4.1 blocks, §4.4 vendor order invoice, §4.5 buyer invoice). The content
// comes from GET /vendor/documents/:docType/:docId?format=json (or the
// buyer's GET /me/shop-orders/:id/invoice?format=json); the app only lays
// it out. Never a phone, email, address, commission or payout: the server
// does not send them.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../sales/receipt_data.dart' show eatDateTime, eatDayOf, receiptDay;
import '../sales/sale_models.dart' show paymentMethodKey;
import '../sales/sales_widgets.dart' show MoneyRow, ReceiptLanguageToggle;
import '../stock/stock_options.dart';
import 'document_models.dart';
import 'document_share_sheet.dart';

/// The route of my invoice for an app order.
String vendorOrderInvoiceRoute(String orderId) =>
    '/vendor/orders/${Uri.encodeComponent(orderId)}/invoice';

/// The buyer's invoice page for a paid order (one seller, or a picker).
String buyerInvoiceRoute(String orderId, {String? vendorId}) => Uri(
  path: '/shop/orders/${Uri.encodeComponent(orderId)}/invoice',
  queryParameters: vendorId == null ? null : {'vendor': vendorId},
).toString();

/// Ids in these routes: the characters the server issues.
final documentIdPattern = RegExp(r'^[A-Za-z0-9._:-]{1,100}$');

/// "A 18%" / "E Exempt" / "C 0%" in [t]'s language.
String vatCodeLine(String Function(String) t, DocVatRow r) {
  final rate = ratePctText(r.ratePct);
  return rate == null
      ? '${r.code} ${t('vendor.doc.exempt')}'
      : '${r.code} $rate';
}

/// The VAT part of a document (§4.1 items 6–7): "Includes VAT TSh X" and
/// the summary Code · Rate · Before VAT · VAT. Nothing when no VAT applied.
class VatBlock extends StatelessWidget {
  const VatBlock({
    super.key,
    required this.vatIncludedTzs,
    required this.rows,
    required this.t,
  });

  final int vatIncludedTzs;
  final List<DocVatRow> rows;
  final String Function(String) t;

  @override
  Widget build(BuildContext context) {
    if (vatIncludedTzs <= 0 && rows.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      key: const Key('doc-vat-block'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MoneyRow(
          fillIn(t('vendor.doc.includesVat'), {'amount': ''}).trim(),
          formatCurrency(vatIncludedTzs),
          key: const Key('doc-vat-included'),
        ),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: FFTokens.spacingXs),
          Text(t('vendor.doc.vatSummary'), style: theme.textTheme.labelLarge),
          for (final r in rows)
            Semantics(
              container: true,
              label: [
                vatCodeLine(t, r),
                '${t('vendor.doc.vatNet')} ${formatCurrency(r.netTzs)}',
                '${t('vendor.doc.vat')} ${formatCurrency(r.vatTzs)}',
              ].join(', '),
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Wrap(
                  spacing: FFTokens.spacingMd,
                  runSpacing: 2,
                  children: [
                    Text(vatCodeLine(t, r)),
                    Text(
                      '${t('vendor.doc.vatNet')} ${formatMoney(r.netTzs)}',
                      style: muted,
                    ),
                    Text(
                      '${t('vendor.doc.vat')} ${formatMoney(r.vatTzs)}',
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// A document laid out natively, in the language [t] answers in.
class VendorDocumentView extends StatelessWidget {
  const VendorDocumentView({
    super.key,
    required this.doc,
    required this.t,
    required this.lang,
  });

  final VendorDoc doc;
  final String Function(String key) t;
  final String lang;

  String _fill(String key, Map<String, Object?> v) => fillIn(t(key), v);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final title = [t(doc.titleKey), ?doc.number].join(' ');
    // UAT D1: a cancelled ORDER reads as an order cancellation (as the
    // server's page), never as a voided document.
    final orderCancelled = doc.cancelled && doc.docType == 'order_invoice';
    final cancelledDay = _day(doc.cancelledAt, lang);
    final status = switch (doc.status) {
      'paid' => ('vendor.doc.statusPaid', FFBadgeTone.success),
      'pay_later' => ('vendor.doc.statusPayLater', FFBadgeTone.brand),
      'paid_in_full' => ('vendor.doc.statusPaidInFull', FFBadgeTone.success),
      // S7: a sale fully refunded, or a pay-later balance a credit note
      // settled (fitflex-functions#318).
      'refunded' => ('vendor.doc.statusRefunded', FFBadgeTone.gray),
      'settled_by_credit_note' => (
        'vendor.doc.statusSettledByCreditNote',
        FFBadgeTone.success,
      ),
      // S7: a credit note that stands (an undone one reads Cancelled).
      'issued' => ('vendor.doc.statusIssued', FFBadgeTone.info),
      'cancelled' when orderCancelled => (
        cancelledDay == null
            ? 'vendor.doc.orderCancelledBadge'
            : 'vendor.doc.orderCancelledOn',
        FFBadgeTone.danger,
      ),
      'cancelled' => ('vendor.doc.statusCancelled', FFBadgeTone.danger),
      _ => null,
    };
    return FFCard(
      key: const Key('doc-view'),
      child: Semantics(
        explicitChildNodes: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (doc.businessName != null)
              Text(doc.businessName!, style: theme.textTheme.titleLarge),
            if (doc.address != null) Text(doc.address!, style: muted),
            if (doc.contactNumber != null)
              Text(doc.contactNumber!, style: muted),
            if (doc.tin != null)
              Text(
                _fill('vendor.doc.tin', {'tin': doc.tin}),
                key: const Key('doc-tin'),
                style: muted,
              ),
            if (doc.vrn != null)
              Text(
                _fill('vendor.doc.vrn', {'vrn': doc.vrn}),
                key: const Key('doc-vrn'),
                style: muted,
              ),
            if (doc.soldVia != null)
              Text(doc.soldVia!, key: const Key('doc-sold-via'), style: muted),
            const SizedBox(height: FFTokens.spacingSm),
            Semantics(
              header: true,
              child: Text(
                title,
                key: const Key('doc-title'),
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (doc.saleRef != null)
              Text(
                _fill('vendor.doc.saleRef', {'number': doc.saleRef}),
                style: muted,
              ),
            if (doc.orderShortRef != null)
              Text(
                _fill('vendor.doc.orderRef', {'ref': doc.orderShortRef}),
                style: muted,
              ),
            if (status != null) ...[
              const SizedBox(height: FFTokens.spacingXs),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FFBadge(
                  key: const Key('doc-status'),
                  label: _fill(status.$1, {'date': cancelledDay}),
                  tone: status.$2,
                  wrap: true,
                ),
              ),
            ],
            if (doc.cancelled) ...[
              const SizedBox(height: FFTokens.spacingXs),
              FFAlert(
                key: const Key('doc-cancelled'),
                message: orderCancelled
                    ? t('vendor.doc.orderCancelled')
                    : _fill('vendor.doc.cancelled', {
                        'date': eatDateTime(doc.cancelledAt, locale: lang),
                        'business': doc.businessName ?? '',
                      }),
                tone: FFAlertTone.error,
              ),
            ],
            const SizedBox(height: FFTokens.spacingXs),
            Text(eatDateTime(doc.issuedAt, locale: lang), style: muted),
            if (doc.customerName != null)
              Text(_fill('vendor.doc.customer', {'name': doc.customerName})),
            if (doc.dueDate != null)
              Text(
                _fill('vendor.doc.dueBy', {
                  'date': receiptDay(doc.dueDate, lang),
                }),
              ),
            if (doc.servedBy != null)
              Text(
                _fill('vendor.doc.servedBy', {'name': doc.servedBy}),
                style: muted,
              ),
            if (doc.paymentMethod != null)
              Text(
                _fill('vendor.doc.paidBy', {
                  'method': t(paymentMethodKey(doc.paymentMethod)),
                }),
              ),
            if (doc.lines.isNotEmpty) ...[
              const Divider(height: FFTokens.spacingLg),
              for (final l in doc.lines) _line(context, l, muted),
            ],
            const Divider(height: FFTokens.spacingLg),
            if (doc.docType != 'payment_receipt' && doc.docType != 'statement')
              MoneyRow(t('vendor.doc.subtotal'), formatMoney(doc.subtotalTzs)),
            if (doc.discountsTzs > 0)
              MoneyRow(
                t('vendor.doc.discounts'),
                '−${formatMoney(doc.discountsTzs)}',
              ),
            MoneyRow(
              t(
                doc.docType == 'statement'
                    ? 'vendor.doc.totalOwed'
                    : 'vendor.doc.total',
              ),
              formatCurrency(doc.totalTzs),
              strong: true,
              strike: doc.cancelled,
              key: const Key('doc-total'),
            ),
            VatBlock(
              vatIncludedTzs: doc.vatIncludedTzs,
              rows: doc.vatSummary,
              t: t,
            ),
            if (doc.payments.isNotEmpty) ...[
              const SizedBox(height: FFTokens.spacingSm),
              for (final p in doc.payments)
                MoneyRow(
                  p.reference == null
                      ? t(paymentMethodKey(p.method))
                      : '${t(paymentMethodKey(p.method))} (${p.reference})',
                  formatMoney(p.amountTzs),
                ),
            ],
            if (doc.changeTzs > 0)
              MoneyRow(t('vendor.doc.change'), formatMoney(doc.changeTzs)),
            if (doc.paidNowTzs != null)
              MoneyRow(t('vendor.doc.paidNow'), formatMoney(doc.paidNowTzs!)),
            if (doc.liveBalanceTzs != null && !doc.cancelled) ...[
              const SizedBox(height: FFTokens.spacingSm),
              FFCard(
                key: const Key('doc-live-status'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _fill('vendor.doc.statusOn', {
                        'date': receiptDay(doc.liveAsOf, lang),
                      }),
                      style: theme.textTheme.labelLarge,
                    ),
                    if (doc.liveBalanceTzs! > 0)
                      MoneyRow(
                        t('vendor.doc.balanceDue'),
                        formatCurrency(doc.liveBalanceTzs!),
                        strong: true,
                      )
                    else
                      Text(
                        _fill('vendor.doc.paidInFull', {
                          'date': receiptDay(doc.paidInFullAt, lang),
                        }),
                      ),
                    if (doc.paidWith.isNotEmpty)
                      Text(
                        _fill('vendor.doc.paidWith', {
                          'numbers': doc.paidWith.join(', '),
                        }),
                        style: muted,
                      ),
                  ],
                ),
              ),
            ],
            if (doc.paidTowards.isNotEmpty) ...[
              const SizedBox(height: FFTokens.spacingSm),
              Text(
                t('vendor.doc.paidTowards'),
                style: theme.textTheme.labelLarge,
              ),
              for (final a in doc.paidTowards)
                MoneyRow(a.number, formatMoney(a.amountTzs)),
            ],
            if (doc.stillOwedTzs != null)
              MoneyRow(
                t('vendor.doc.stillOwed'),
                formatCurrency(doc.stillOwedTzs!),
              ),
            const Divider(height: FFTokens.spacingLg),
            if (doc.businessName != null &&
                (doc.docType == 'receipt' || doc.docType == 'payment_receipt'))
              Text(
                _fill('vendor.doc.receivedBy', {'business': doc.businessName}),
              ),
            Text(t('vendor.doc.notFiscal'), style: muted),
          ],
        ),
      ),
    );
  }

  /// "20 Oct 2026" for an instant, on the EAT calendar; null when unknown.
  static String? _day(String? iso, String lang) {
    final d = eatDayOf(iso);
    if (d == null) return null;
    return formatDate(DateTime(d.year, d.month, d.day), locale: lang);
  }

  Widget _line(BuildContext context, DocLine l, TextStyle? muted) {
    final name = l.variant == null ? l.name : '${l.name} (${l.variant})';
    final code = l.vatCode == null ? '' : ' ${l.vatCode}';
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MoneyRow('${l.qty} × $name', '${formatMoney(l.amountTzs)}$code'),
          if (l.qty > 1) Text('@ ${formatMoney(l.unitPriceTzs)}', style: muted),
          if (l.discountTzs > 0)
            Text(
              '${t('vendor.doc.discount')} −${formatMoney(l.discountTzs)}',
              style: muted,
            ),
        ],
      ),
    );
  }
}

enum _DocProblem { none, failed, notFound, notReady, noAccess }

_DocProblem _problemOf(Object e) {
  if (e is ApiException) {
    if (e.code == 'invoice_not_ready') return _DocProblem.notReady;
    if (e.status == 403) return _DocProblem.noAccess;
    if (e.status == 404) return _DocProblem.notFound;
  }
  return _DocProblem.failed;
}

Widget _problemView(BuildContext context, _DocProblem p, VoidCallback retry) =>
    switch (p) {
      _DocProblem.notReady => FFEmptyState(
        key: const Key('doc-not-ready'),
        title: context.tr('vendor.documents.invoiceAfterPayment'),
      ),
      _DocProblem.notFound => FFEmptyState(
        key: const Key('doc-not-found'),
        title: context.tr('vendor.documents.notFound'),
      ),
      _DocProblem.noAccess => FFEmptyState(
        key: const Key('doc-no-access'),
        title: context.tr('vendor.documents.noAccess'),
      ),
      _ => FFErrorState(
        key: const Key('doc-failed'),
        message: context.tr('vendor.documents.loadFailed'),
        onRetry: retry,
      ),
    };

/// My invoice for an app order (§4.4): the vendor's own lines only, with
/// Share and PDF. Needs `documents` on and the `orders` permission.
class VendorOrderInvoicePage extends StatefulWidget {
  const VendorOrderInvoicePage({super.key, required this.orderId});
  final String orderId;

  @override
  State<VendorOrderInvoicePage> createState() => _VendorOrderInvoicePageState();
}

class _VendorOrderInvoicePageState extends State<VendorOrderInvoicePage> {
  VendorDoc? _doc;
  bool _loading = true;
  _DocProblem _problem = _DocProblem.none;
  String? _lang;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final tools = await VendorToolsOptions.of(context);
    if (!mounted) return;
    if (!tools.documents) {
      context.go('/vendor/home');
      return;
    }
    if (!canVendor(context, 'orders')) {
      FFSnack.error(context, context.tr('vendor.documents.noAccess'));
      context.go('/vendor/home');
      return;
    }
    await _load();
  }

  String get _langNow => _lang ?? FFLocaleScope.of(context).locale.languageCode;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _problem = _DocProblem.none;
    });
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorDocument('order', widget.orderId, lang: _langNow);
      final d = res['doc'];
      if (d is! Map) throw ApiException(404, null);
      if (!mounted) return;
      setState(() {
        _doc = VendorDoc.fromJson(d);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _doc = null;
          _loading = false;
          _problem = _problemOf(e);
        });
      }
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/vendor/home?open=orders');
    }
  }

  DocumentRef _ref(VendorDoc d) =>
      DocumentRef.order(orderId: widget.orderId, number: d.number);

  Future<void> _share(VendorDoc d) => showDocumentShareSheet(
    context,
    doc: _ref(d),
    lang: _langNow,
    shareText: (lang) => documentShareText(d, FFLocaleScope.of(context), lang),
    shareSubject: (lang) => [
      ?d.businessName,
      FFLocaleScope.of(context).tIn(lang, d.titleKey),
      ?d.number,
    ].join(' '),
  );

  @override
  Widget build(BuildContext context) {
    final locale = FFLocaleScope.of(context);
    final lang = _langNow;
    final d = _doc;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(
          d == null
              ? context.tr('vendor.documents.invoice')
              : [context.tr(d.titleKey), ?d.number].join(' '),
        ),
        actions: [
          if (d != null && !d.cancelled)
            IconButton(
              key: const Key('order-invoice-share'),
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              tooltip: context.tr('vendor.documents.share'),
              icon: const Icon(Icons.share),
              onPressed: () => _share(d),
            ),
          if (d != null && d.cancelled)
            IconButton(
              key: const Key('order-invoice-links'),
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              tooltip: context.tr('vendor.documents.linksTitle'),
              icon: const Icon(Icons.manage_history),
              onPressed: () => showDocumentLinksSheet(context, _ref(d)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: FFSpinner())
          : d == null
          ? ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [_problemView(context, _problem, _load)],
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  children: [
                    VendorDocumentView(
                      doc: d,
                      t: (k) => locale.tIn(lang, k),
                      lang: lang,
                    ),
                    const SizedBox(height: FFTokens.spacingMd),
                    ReceiptLanguageToggle(
                      value: lang,
                      onChanged: (v) {
                        setState(() => _lang = v);
                        _load();
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// A document as plain text (Share as text of an order invoice), in [lang].
String documentShareText(VendorDoc d, FFLocale locale, String lang) {
  String t(String k) => locale.tIn(lang, k);
  final b = StringBuffer();
  if (d.businessName != null) b.writeln(d.businessName);
  b.writeln([t(d.titleKey), ?d.number].join(' '));
  if (d.orderShortRef != null) {
    b.writeln(fillIn(t('vendor.doc.orderRef'), {'ref': d.orderShortRef}));
  }
  final when = eatDateTime(d.issuedAt, locale: lang);
  if (when.isNotEmpty) b.writeln(when);
  for (final l in d.lines) {
    final name = l.variant == null ? l.name : '${l.name} (${l.variant})';
    b.writeln('${l.qty} x $name  ${formatMoney(l.amountTzs)}');
  }
  b.writeln('${t('vendor.doc.total')}: ${formatCurrency(d.totalTzs)}');
  if (d.vatIncludedTzs > 0) {
    b.writeln(
      fillIn(t('vendor.doc.includesVat'), {
        'amount': formatCurrency(d.vatIncludedTzs),
      }),
    );
  }
  if (d.soldVia != null) b.writeln(d.soldVia);
  b.write(t('vendor.doc.notFiscal'));
  return b.toString();
}

/// The buyer's invoice (§4.5): one per seller; a picker when several.
/// No link sharing (links are vendor-issued only); Download PDF and Done.
class BuyerInvoicePage extends StatefulWidget {
  const BuyerInvoicePage({super.key, required this.orderId, this.vendorId});
  final String orderId;
  final String? vendorId;

  @override
  State<BuyerInvoicePage> createState() => _BuyerInvoicePageState();
}

class _BuyerInvoicePageState extends State<BuyerInvoicePage> {
  List<VendorDoc>? _invoices;
  bool _loading = true;
  bool _offline = false;
  _DocProblem _problem = _DocProblem.none;
  String? _lang;
  bool _pdfBusy = false;
  bool _pdfFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _langNow => _lang ?? FFLocaleScope.of(context).locale.languageCode;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _offline = false;
      _problem = _DocProblem.none;
    });
    try {
      final res = await AppScope.of(
        context,
      ).api.myShopOrderInvoices(widget.orderId, lang: _langNow);
      final list = [
        for (final d in (res['invoices'] as List? ?? []).whereType<Map>())
          VendorDoc.fromJson(d),
      ];
      if (!mounted) return;
      setState(() {
        _invoices = list;
        _loading = false;
        if (list.isEmpty) _problem = _DocProblem.notFound;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _invoices = null;
        _problem = e.status == 404 ? _DocProblem.notFound : _DocProblem.failed;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _invoices = null;
          _offline = true;
          _problem = _DocProblem.failed;
        });
      }
    }
  }

  VendorDoc? get _selected {
    final list = _invoices ?? const <VendorDoc>[];
    if (list.length == 1) return list.single;
    final v = widget.vendorId;
    if (v == null) return null;
    for (final d in list) {
      if (d.vendorId == v) return d;
    }
    return null;
  }

  Future<void> _pdf(VendorDoc d) async {
    final vendorId = d.vendorId;
    if (vendorId == null) return;
    setState(() {
      _pdfBusy = true;
      _pdfFailed = false;
    });
    try {
      final out = await AppScope.of(context).api.myShopOrderInvoicePdf(
        widget.orderId,
        vendorId: vendorId,
        lang: _langNow,
      );
      final name = out.fileName ?? '${d.number ?? 'invoice'}.pdf';
      if (DocumentActions.isWeb()) {
        await DocumentActions.openPdf(out.bytes, name);
      } else {
        await DocumentActions.shareFile(out.bytes, name);
      }
    } catch (_) {
      if (mounted) setState(() => _pdfFailed = true);
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  void _done() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/member/shop');
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = FFLocaleScope.of(context);
    final lang = _langNow;
    final selected = _selected;
    final list = _invoices;
    Widget body;
    if (_loading) {
      body = FFSkeletonList(semanticLabel: context.tr('common.loading'));
    } else if (list == null || list.isEmpty) {
      body = _problem == _DocProblem.notFound
          ? FFEmptyState(
              key: const Key('buyer-invoice-not-found'),
              title: context.tr('shop.invoice.notFound'),
            )
          : FFErrorState(
              key: const Key('buyer-invoice-failed'),
              message: context.tr(
                _offline ? 'error.network' : 'shop.invoice.failed',
              ),
              onRetry: _load,
            );
    } else if (selected == null) {
      // Several sellers: one invoice each (O-11).
      body = Column(
        key: const Key('buyer-invoice-picker'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('shop.invoice.perSeller'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: FFTokens.spacingSm),
          for (final d in list)
            FFCard(
              child: ListTile(
                key: Key('buyer-invoice-seller-${d.vendorId}'),
                minTileHeight: 56,
                contentPadding: EdgeInsets.zero,
                title: Text(d.businessName ?? ''),
                subtitle: Text(d.number ?? ''),
                trailing: Text(formatCurrency(d.totalTzs)),
                onTap: d.vendorId == null
                    ? null
                    : () => context.push(
                        buyerInvoiceRoute(widget.orderId, vendorId: d.vendorId),
                      ),
              ),
            ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VendorDocumentView(
            doc: selected,
            t: (k) => locale.tIn(lang, k),
            lang: lang,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          ReceiptLanguageToggle(
            value: lang,
            onChanged: (v) {
              setState(() => _lang = v);
              _load();
            },
          ),
          if (_pdfFailed) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Semantics(
              liveRegion: true,
              child: FFAlert(
                key: const Key('buyer-invoice-pdf-failed'),
                message: context.tr('vendor.documents.pdfFailed'),
                tone: FFAlertTone.error,
              ),
            ),
          ],
          const SizedBox(height: FFTokens.spacingMd),
          Wrap(
            spacing: FFTokens.spacingSm,
            runSpacing: FFTokens.spacingSm,
            children: [
              FFButton(
                key: const Key('buyer-invoice-pdf'),
                label: context.tr('shop.invoice.download'),
                icon: Icons.picture_as_pdf_outlined,
                variant: FFButtonVariant.secondary,
                visualDensity: VisualDensity.standard,
                loading: _pdfBusy,
                onPressed: _pdfBusy ? null : () => _pdf(selected),
              ),
              FFButton(
                key: const Key('buyer-invoice-done'),
                label: context.tr('vendor.pos.done'),
                variant: FFButtonVariant.ghost,
                visualDensity: VisualDensity.standard,
                onPressed: _done,
              ),
            ],
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('shop.invoice.open'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            children: [body],
          ),
        ),
      ),
    );
  }
}
