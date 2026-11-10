// Vendor tools · S3: one recorded walk-in sale (spec §5.3) — the receipt plus
// its audit trail, Share, and Void. Voids need a connection and are never
// queued.
//
// Who may void (backend #214): the vendor account and admin-role staff any
// sale; other staff only a sale they recorded, on the same EAT day it was
// sold. The server enforces it (403 void_not_allowed); the app hides Void
// where it would be refused.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/formatters.dart';
import '../../../shared/network/browser_online.dart';
import '../customers/customer_profile_page.dart'
    show saleBadgeText, saleStatusBadges;
import '../customers/customers_widgets.dart';
import '../customers/payment_sheets.dart';
import '../documents/document_entry.dart';
import '../documents/document_models.dart' show DocumentRef;
import '../documents/document_share_sheet.dart' show showDocumentLinksSheet;
import '../stock/stock_options.dart';
import 'offline_sale_queue.dart';
import 'receipt_data.dart';
import 'receipt_files.dart';
import 'refunds/refund_models.dart';
import 'refunds/refund_page.dart';
import 'sale_models.dart';
import 'sales_widgets.dart';

/// Whether [user] may void [sale] (mirrors the server's rule).
bool canVoidSale(
  Map<String, dynamic>? user,
  ReceiptData sale, {
  DateTime? now,
}) {
  if (sale.voided || sale.queued) return false;
  final type = user?['userType']?.toString();
  if (type == 'vendor') return true;
  if (type != 'vendor_staff') return false;
  final perms = (user?['vendorPermissions'] as List? ?? []);
  if (!perms.contains('sales')) return false;
  if (user?['vendorRole']?.toString() == 'admin') return true;
  final own = sale.servedById != null && sale.servedById == user?['id'];
  return own && eatDayOf(sale.soldAt) == eatToday(now);
}

class SaleDetailPage extends StatefulWidget {
  const SaleDetailPage({super.key, required this.saleId, this.customerId});
  final String saleId;

  /// S4: opened from this customer's profile. The page then checks the
  /// customers gate (not the sales one) and reads the sale through
  /// GET /vendor/customers/:id/sales/:saleId, so staff with `customers`
  /// but not `sales` can see it. Share and Void stay for people who also
  /// have `sales` (and walk-in sales on).
  final String? customerId;

  @override
  State<SaleDetailPage> createState() => _SaleDetailPageState();
}

class _SaleDetailPageState extends State<SaleDetailPage> {
  Map<String, dynamic>? _sale;
  Map<String, dynamic> _profile = const {};
  bool _loading = true;
  bool _notFound = false;
  bool _failed = false;
  bool _suspended = false;
  String? _lang;
  VendorTools _tools = VendorTools.off;
  ({String? tin, String? vrn}) _taxIds = (tin: null, vrn: null);
  String? _taxIdsFor;

  @override
  void initState() {
    super.initState();
    BrowserOnline.instance.addListener(_onBrowserOnline);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _onBrowserOnline() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    BrowserOnline.instance.removeListener(_onBrowserOnline);
    super.dispose();
  }

  Future<void> _start() async {
    final tools = widget.customerId == null
        ? await enterSalesRoute(context)
        : await enterCustomersRoute(context);
    if (tools == null || !mounted) return;
    _tools = tools;
    final api = AppScope.of(context).api;
    final session = SalesSession.of(context);
    () async {
      try {
        final p = await api.vendorProfile();
        await session?.saveBusiness(p);
        if (mounted) setState(() => _profile = p);
      } catch (_) {
        // Staff who may not read the profile: the header this device kept.
        final kept = await session?.loadBusiness() ?? const {};
        if (mounted && kept.isNotEmpty) setState(() => _profile = kept);
      }
    }();
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final api = AppScope.of(context).api;
      final res = widget.customerId == null
          ? await api.vendorSale(widget.saleId)
          : await api.vendorCustomerSale(widget.customerId!, widget.saleId);
      if (!mounted) return;
      setState(() {
        _sale = res['sale'] is Map
            ? Map<String, dynamic>.from(res['sale'] as Map)
            : null;
        _notFound = _sale == null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _suspended = e.code == 'vendor_suspended';
        _notFound = !_suspended && (e.status == 404 || e.status == 403);
        _failed = !_notFound && !_suspended;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(
        widget.customerId == null
            ? salesHomeRoute
            : customerRoute(widget.customerId!),
      );
    }
  }

  /// Share and Void are sales actions: the sales tool on and `sales`.
  bool get _salesActions =>
      widget.customerId == null ||
      (_tools.walkInSales && canVendor(context, 'sales'));

  Future<void> _void(ReceiptData data) async {
    final out = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _VoidDialog(
        saleId: widget.saleId,
        number: data.number ?? '',
        credit: data.credit,
        customerId: data.customerId,
      ),
    );
    if (!mounted || out == null) return;
    if (out['sale'] is Map) {
      setState(() => _sale = Map<String, dynamic>.from(out['sale'] as Map));
      FFSnack.success(
        context,
        fillIn(context.tr('vendor.sales.voided'), {'number': data.number}),
      );
    } else if (out['reload'] == true) {
      final key = out['message']?.toString();
      if (key != null) FFSnack.info(context, context.tr(key));
      await _load();
    }
  }

  /// S7: opens the refund screen; back with a refund, the sale updates and
  /// the refund's credit note opens (§3.3).
  Future<void> _refund() async {
    final out = await context.push<Object?>(saleRefundRoute(widget.saleId));
    if (!mounted) return;
    if (out is RefundOutcome) {
      if (out.sale != null) setState(() => _sale = out.sale);
      final id = out.refund['id']?.toString() ?? '';
      if (salesIdPattern.hasMatch(id)) {
        await context.push(
          refundDetailRoute(id, saved: true),
          extra: out.refund,
        );
      }
    }
    if (mounted) await _load();
  }

  Future<void> _openRefund(String id) async {
    if (!salesIdPattern.hasMatch(id)) return;
    await context.push(refundDetailRoute(id));
    if (mounted) await _load();
  }

  /// S4: customers screens are on and this person has `customers`.
  bool get _seesCustomers =>
      _tools.customers && canVendor(context, 'customers');

  Future<void> _recordPayment(ReceiptData data) async {
    final id = data.customerId;
    if (id == null) return;
    // Fresh balances first; no connection → the form never opens.
    final Map<String, dynamic> customer;
    try {
      final res = await AppScope.of(context).api.vendorCustomer(id);
      final c = res['customer'];
      if (c is! Map) throw ApiException(404, null);
      customer = Map<String, dynamic>.from(c);
    } on ApiException {
      if (mounted) {
        FFSnack.error(context, context.tr('vendor.customers.failed'));
      }
      return;
    } catch (_) {
      if (mounted) FFSnack.error(context, context.tr('vendor.pay.offline'));
      return;
    }
    if (!mounted) return;
    final out = await recordCustomerPayment(context, customer: customer);
    if (out != null && mounted) await _load();
  }

  /// S5: the seller's TIN/VRN when VAT applied (asked once per sale).
  void _loadTaxIds(ReceiptData data) {
    if (data.id == null || _taxIdsFor == data.id || !data.hasVat) return;
    _taxIdsFor = data.id;
    sellerTaxIdsFor(context, data, _tools).then((ids) {
      if (mounted) setState(() => _taxIds = ids);
    });
  }

  Future<void> _share(ReceiptData data, String lang) async {
    if (_tools.documents) {
      return openSaleShareSheet(
        context,
        data: data,
        lang: lang,
        tools: _tools,
        tin: _taxIds.tin,
        vrn: _taxIds.vrn,
      );
    }
    // Sale extras #3 (AC-31): the same rows as the receipt page.
    await showReceiptShareSheet(
      context,
      data: data,
      lang: lang,
      tin: _taxIds.tin,
      vrn: _taxIds.vrn,
    );
  }

  /// S7 §4.1 item 5: whether Refund items shows, and the muted line
  /// instead of it.
  _RefundUi _refundUi(
    Map<String, dynamic>? user,
    ReceiptData data,
    Map<String, dynamic> sale,
  ) {
    if (!_tools.refundsOn || !_salesActions) return _RefundUi.hidden;
    if (data.voided) return _RefundUi.hidden;
    if (data.queued || data.id == null) return _RefundUi.queued;
    final lines = refundableLinesOf(sale);
    if (data.refundState == 'full' ||
        (lines.isNotEmpty && lines.every((l) => l.refundableQty == 0))) {
      return _RefundUi.fully;
    }
    final block = refundBlockFor(
      user,
      servedById: data.servedById,
      soldAt: data.soldAt,
    );
    if (block == RefundBlock.noAccess) return _RefundUi.hidden;
    if (block == RefundBlock.askOwner) return _RefundUi.askOwner;
    return BrowserOnline.instance.value ? _RefundUi.button : _RefundUi.offline;
  }

  String? _refundNote(_RefundUi ui) => switch (ui) {
    _RefundUi.fully => 'vendor.refunds.fully',
    _RefundUi.queued => 'vendor.refunds.queuedNo',
    _RefundUi.askOwner => 'vendor.refunds.askOwner',
    _RefundUi.offline => 'vendor.refunds.offline',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final locale = FFLocaleScope.of(context);
    final lang = _lang ?? locale.locale.languageCode;
    final sale = _sale;
    final data = sale == null
        ? null
        : ReceiptData.fromSale(
            sale,
            profile: _profile,
            documents: _tools.documents,
            vat: _tools.vat,
          );
    if (data != null) _loadTaxIds(data);
    final user = AppScope.of(context).auth.user;
    // S7 (Q-3): a sale with active refunds cannot be voided.
    final hasRefunds = data != null && data.hasActiveRefunds;
    final mayVoid =
        data != null && _salesActions && !hasRefunds && canVoidSale(user, data);
    final refundState = data == null
        ? _RefundUi.hidden
        : _refundUi(user, data, sale!);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(
          data?.number == null
              ? context.tr('vendor.documents.receipt')
              : data!.credit && data.invoiceNumber != null
              ? '${context.tr('vendor.doc.invoice')} ${data.invoiceNumber}'
              : fillIn(context.tr('vendor.pos.receiptNo'), {
                  'number': data.number,
                }),
        ),
        actions: [
          // S5: an app-bar Share (§1.1), and a voided sale's links, which
          // can still be turned off (§2.4).
          if (data != null && _salesActions && _tools.documents)
            IconButton(
              key: Key(
                data.voided ? 'sale-detail-links' : 'sale-detail-share-icon',
              ),
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              tooltip: context.tr(
                data.voided
                    ? 'vendor.documents.linksTitle'
                    : 'vendor.documents.share',
              ),
              icon: Icon(data.voided ? Icons.manage_history : Icons.share),
              onPressed: data.voided
                  ? () => showDocumentLinksSheet(
                      context,
                      DocumentRef.sale(
                        saleId: widget.saleId,
                        credit: data.credit,
                        number: data.invoiceNumber ?? data.number,
                      ),
                    )
                  : () => _share(data, _lang ?? locale.locale.languageCode),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: FFSpinner())
          : data == null
          ? ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                if (_suspended)
                  FFAlert(
                    key: const Key('sale-detail-suspended'),
                    message: context.tr('vendor.sales.suspended'),
                    tone: FFAlertTone.warning,
                  )
                else if (_failed)
                  FFErrorState(
                    message: context.tr('vendor.sales.failed'),
                    onRetry: _load,
                  )
                else
                  FFEmptyState(
                    key: const Key('sale-detail-not-found'),
                    title: context.tr('vendor.sales.notFound'),
                  ),
              ],
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  children: [
                    Wrap(
                      spacing: FFTokens.spacingSm,
                      runSpacing: FFTokens.spacingXs,
                      children: [
                        FFBadge(
                          key: const Key('sale-detail-status'),
                          label: context.tr(
                            data.voided
                                ? 'vendor.sales.voidedBadge'
                                : 'vendor.sales.filter.completed',
                          ),
                          tone: data.voided
                              ? FFBadgeTone.gray
                              : FFBadgeTone.success,
                        ),
                        if (data.lateRecorded)
                          FFBadge(
                            label: context.tr('vendor.sales.offlineBadge'),
                            tone: FFBadgeTone.gray,
                          ),
                        // The ONE badge rule the sales list shares; the receipt
                        // below already carries the Pay later badge.
                        for (final b in saleStatusBadges({
                          'kind': data.kind,
                          'status': data.status,
                          'balanceTzs': data.balanceTzs,
                          'balanceReducedTzs': data.balanceReducedTzs,
                          'refundState': data.refundState,
                        }).where((b) => b.key != 'vendor.sales.payLaterBadge'))
                          FFBadge(
                            key: b.key.startsWith('vendor.refunds.')
                                ? const Key('sale-detail-refund-badge')
                                : null,
                            label: saleBadgeText(context, b),
                            tone: b.tone,
                            wrap: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: FFTokens.spacingSm),
                    if (data.voided) ...[
                      FFAlert(
                        key: const Key('sale-detail-voided'),
                        message: fillIn(context.tr('vendor.sales.voidedBy'), {
                          'name': data.voidedBy ?? '—',
                          'time': eatDateTime(data.voidedAt, locale: lang),
                          'reason': data.voidReason ?? '',
                        }),
                      ),
                      const SizedBox(height: FFTokens.spacingSm),
                    ],
                    if (data.voided && _tools.documents) ...[
                      FFAlert(
                        key: const Key('sale-detail-voided-note'),
                        message: context.tr('vendor.documents.voidedNote'),
                      ),
                      const SizedBox(height: FFTokens.spacingSm),
                    ],
                    ReceiptView(
                      data: data,
                      lang: lang,
                      t: (k) => locale.tIn(lang, k),
                      audit: true,
                      tin: _taxIds.tin,
                      vrn: _taxIds.vrn,
                    ),
                    if (data.refunds.isNotEmpty)
                      _RefundsCard(
                        refunds: saleRefundRowsOf(data.refunds),
                        lang: lang,
                        onOpen: _salesActions && canVendor(context, 'sales')
                            ? _openRefund
                            : null,
                      ),
                    // From the profile itself there is nothing to go back to.
                    if (widget.customerId == null &&
                        data.hasCustomer &&
                        _seesCustomers &&
                        customerIdPattern.hasMatch(data.customerId!)) ...[
                      const SizedBox(height: FFTokens.spacingSm),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FFButton(
                          key: const Key('sale-detail-customer'),
                          label: data.customerName == null
                              ? context.tr(data.unnamedCustomerKey)
                              : data.customerName!,
                          icon: Icons.person_outline,
                          variant: FFButtonVariant.ghost,
                          visualDensity: VisualDensity.standard,
                          onPressed: () =>
                              context.push(customerRoute(data.customerId!)),
                        ),
                      ),
                    ],
                    // The receipt above is historical; what is owed now:
                    if (data.credit && !data.voided) ...[
                      const SizedBox(height: FFTokens.spacingSm),
                      MoneyRow(
                        context.tr('vendor.pay.stillOwed'),
                        formatCurrency(data.balanceTzs),
                        strong: true,
                        key: const Key('sale-detail-balance-now'),
                      ),
                    ],
                    if (data.credit && data.liveAllocations.isNotEmpty) ...[
                      const SizedBox(height: FFTokens.spacingSm),
                      Text(
                        context.tr('vendor.customers.payments'),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      for (final a in data.liveAllocations)
                        MoneyRow(
                          a['number']?.toString() ?? '',
                          formatCurrency((a['amountTzs'] as num?) ?? 0),
                        ),
                    ],
                    const SizedBox(height: FFTokens.spacingMd),
                    if (!data.voided)
                      ReceiptLanguageToggle(
                        value: lang,
                        onChanged: (v) => setState(() => _lang = v),
                      ),
                    const SizedBox(height: FFTokens.spacingMd),
                    Wrap(
                      spacing: FFTokens.spacingSm,
                      runSpacing: FFTokens.spacingSm,
                      children: [
                        if (!data.voided && _salesActions)
                          FFButton(
                            key: const Key('sale-detail-share'),
                            label: context.tr('vendor.pos.share'),
                            icon: Icons.share,
                            variant: FFButtonVariant.secondary,
                            visualDensity: VisualDensity.standard,
                            onPressed: () => _share(data, lang),
                          ),
                        if (data.credit &&
                            !data.voided &&
                            data.balanceTzs > 0 &&
                            _seesCustomers)
                          FFButton(
                            key: const Key('sale-detail-record-payment'),
                            label: context.tr('vendor.pay.record'),
                            icon: Icons.payments_outlined,
                            visualDensity: VisualDensity.standard,
                            onPressed: BrowserOnline.instance.value
                                ? () => _recordPayment(data)
                                : null,
                          ),
                        if (refundState == _RefundUi.button ||
                            refundState == _RefundUi.offline)
                          FFButton(
                            key: const Key('sale-detail-refund'),
                            label: context.tr('vendor.refunds.open'),
                            semanticLabel: fillIn(
                              context.tr('vendor.refunds.a11y.open'),
                              {'number': data.number ?? ''},
                            ),
                            icon: Icons.assignment_return_outlined,
                            variant: FFButtonVariant.secondary,
                            visualDensity: VisualDensity.standard,
                            onPressed: BrowserOnline.instance.value
                                ? _refund
                                : null,
                          ),
                        if (mayVoid)
                          FFButton(
                            key: const Key('sale-detail-void'),
                            label: context.tr('vendor.sales.void'),
                            icon: Icons.block,
                            variant: FFButtonVariant.destructive,
                            visualDensity: VisualDensity.standard,
                            onPressed: () => _void(data),
                          ),
                      ],
                    ),
                    if (_refundNote(refundState) case final key?)
                      Padding(
                        padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                        child: Semantics(
                          container: true,
                          liveRegion: refundState == _RefundUi.offline,
                          child: Text(
                            context.tr(key),
                            key: const Key('sale-detail-refund-note'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    if (hasRefunds &&
                        !data.voided &&
                        _salesActions &&
                        canVoidSale(user, data))
                      Padding(
                        padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                        child: Text(
                          context.tr('vendor.sales.voidHasRefunds'),
                          key: const Key('sale-detail-void-has-refunds'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (data.credit &&
                        !data.voided &&
                        data.balanceTzs > 0 &&
                        _seesCustomers &&
                        !BrowserOnline.instance.value)
                      Semantics(
                        container: true,
                        liveRegion: true,
                        child: Text(
                          context.tr('vendor.pay.offline'),
                          key: const Key('sale-detail-pay-offline'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _VoidDialog extends StatefulWidget {
  const _VoidDialog({
    required this.saleId,
    required this.number,
    this.credit = false,
    this.customerId,
  });
  final String saleId;
  final String number;

  /// S4: a pay-later sale (its balance is cancelled with it).
  final bool credit;
  final String? customerId;

  @override
  State<_VoidDialog> createState() => _VoidDialogState();
}

class _VoidDialogState extends State<_VoidDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _fieldError;

  /// S4 (Q-2): customer payments allocated to the sale: `{id, number}`.
  List<Map> _payments = const [];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _ok => _reason.text.trim().length >= voidReasonMin;

  /// D8: the reason field lets go of focus before the dialog closes.
  void _close(Map<String, dynamic>? result) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(result);
  }

  Future<void> _submit() async {
    if (!_ok || _busy) return;
    // D8: unfocus the reason before it is disabled (web semantics).
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _fieldError = null;
    });
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorVoidSale(widget.saleId, _reason.text.trim());
      if (mounted) _close(res);
    } on ApiException catch (e) {
      if (!mounted) return;
      final body = e.body is Map ? e.body as Map : const {};
      switch (e.code) {
        case 'already_voided':
          _close({'reload': true, 'message': 'vendor.sales.alreadyVoided'});
          return;
        case 'reason_required' || 'reason_too_long':
          setState(
            () => _fieldError = context.tr('vendor.sales.voidReasonMissing'),
          );
        case 'void_not_allowed':
          setState(
            () => _error = context.tr(
              body['reason'] == 'too_old'
                  ? 'vendor.sales.voidTooOld'
                  : 'vendor.sales.voidNotOwn',
            ),
          );
        case 'vendor_suspended':
          setState(() => _error = context.tr('vendor.sales.suspended'));
        case 'has_refunds':
          // S7 (Q-3): undo the refunds first (or refund the rest).
          setState(() => _error = context.tr('vendor.sales.voidHasRefunds'));
        case 'sale_has_payments':
          final pays = (body['payments'] as List? ?? [])
              .whereType<Map>()
              .toList();
          setState(() {
            _payments = pays;
            _error = fillIn(context.tr('vendor.sales.voidHasPayments'), {
              'numbers': pays.map((p) => p['number']).join(', '),
            });
          });
        default:
          setState(
            () => _error = context.tr(
              e.status == 403
                  ? 'vendor.sales.err.voidNotAllowed'
                  : 'vendor.saveFailed',
            ),
          );
      }
      setState(() => _busy = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = context.tr('vendor.sales.voidOffline');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) FocusManager.instance.primaryFocus?.unfocus();
      },
      child: AlertDialog(
        title: Text(
          fillIn(context.tr('vendor.sales.voidTitle'), {
            'number': widget.number,
          }),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('vendor.sales.voidBody')),
              if (widget.credit) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Text(
                  context.tr('vendor.sales.voidCreditBody'),
                  key: const Key('sale-void-credit-body'),
                ),
              ],
              const SizedBox(height: FFTokens.spacingMd),
              FFTextField(
                key: const Key('sale-void-reason'),
                controller: _reason,
                label: context.tr('vendor.sales.voidReason'),
                maxLength: voidReasonMax,
                maxLines: 3,
                minLines: 1,
                errorText: _fieldError,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Semantics(
                  liveRegion: true,
                  child: FFAlert(
                    key: const Key('sale-void-error'),
                    message: _error!,
                    tone: FFAlertTone.error,
                  ),
                ),
                // Links to each payment: void those first (§6.3).
                if (widget.customerId != null &&
                    canVendor(context, 'customers'))
                  Wrap(
                    spacing: FFTokens.spacingXs,
                    children: [
                      for (final p in _payments)
                        if (customerIdPattern.hasMatch('${p['id']}'))
                          FFButton(
                            key: Key('sale-void-payment-${p['id']}'),
                            label: p['number']?.toString() ?? '',
                            variant: FFButtonVariant.ghost,
                            visualDensity: VisualDensity.standard,
                            onPressed: _busy
                                ? null
                                : () async {
                                    final changed = await openPaymentById(
                                      context,
                                      customerId: widget.customerId!,
                                      paymentId: p['id'].toString(),
                                    );
                                    if (changed && mounted) {
                                      setState(() {
                                        _payments = _payments
                                            .where((x) => x['id'] != p['id'])
                                            .toList();
                                        if (_payments.isEmpty) _error = null;
                                      });
                                    }
                                  },
                          ),
                    ],
                  ),
              ],
            ],
          ),
        ),
        actions: [
          FFButton(
            label: context.tr('common.cancel'),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: _busy ? null : () => _close(null),
          ),
          FFButton(
            key: const Key('sale-void-confirm'),
            label: context.tr('vendor.sales.void'),
            variant: FFButtonVariant.destructive,
            visualDensity: VisualDensity.standard,
            loading: _busy,
            onPressed: _ok ? _submit : null,
          ),
        ],
      ),
    );
  }
}

enum _RefundUi { hidden, button, offline, fully, queued, askOwner }

/// S7 §4.1 item 4: the sale's refunds, oldest first. Each row opens the
/// refund (its credit note); an undone one is struck through and says so.
class _RefundsCard extends StatelessWidget {
  const _RefundsCard({
    required this.refunds,
    required this.lang,
    required this.onOpen,
  });

  final List<SaleRefundRow> refunds;
  final String lang;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final theme = Theme.of(context);
    return Column(
      key: const Key('sale-detail-refunds'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFSectionTitle(t('vendor.refunds.section')),
        FFCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final r in refunds)
                Builder(
                  builder: (context) {
                    final status = t(
                      r.reverted
                          ? 'vendor.refunds.status.reverted'
                          : 'vendor.refunds.status.active',
                    );
                    final date = eatDateTime(r.refundedAt, locale: lang);
                    final amount = formatCurrency(r.amountTzs);
                    final open = onOpen;
                    // Its own node, never merged into the heading (L-6).
                    return Semantics(
                      container: true,
                      button: open != null,
                      onTap: open == null ? null : () => open(r.id),
                      label: fillIn(t('vendor.refunds.rowLabel'), {
                        'number': r.number,
                        'amount': amount,
                        'date': date,
                        'status': status,
                      }),
                      excludeSemantics: true,
                      child: InkWell(
                        key: Key('sale-detail-refund-${r.id}'),
                        onTap: open == null ? null : () => open(r.id),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: FFTokens.spacingMd,
                              vertical: FFTokens.spacingSm,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r.number,
                                        style: theme.textTheme.titleSmall,
                                      ),
                                      Text(
                                        date,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      amount,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            decoration: r.reverted
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                    ),
                                    if (r.reverted)
                                      FFBadge(
                                        label: status,
                                        tone: FFBadgeTone.gray,
                                      ),
                                  ],
                                ),
                                if (open != null)
                                  const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
