// Vendor tools · S7: one refund (its credit note), /vendor/refunds/:refundId
// (spec §4.4–§4.5). Opened right after a refund is saved, from the sale's
// Refunds card, from stock history, from the Refunds report and from the
// vendor_sale_refunded / vendor_refund_reverted notifications.
//
// Readable whenever walk-in sales are on and the person has `sales`, even
// with the refunds tool off (§0.2: refunds made stay visible): Share and
// Undo then hide. Undo is online only and needs a reason.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app_scope.dart';
import '../../../../shared/api_client.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/formatters.dart';
import '../../../../shared/i18n.dart';
import '../../../../shared/network/browser_online.dart';
import '../../customers/customers_widgets.dart'
    show customerIdPattern, customerRoute;
import '../../documents/document_models.dart' show DocumentRef;
import '../../documents/document_share_sheet.dart';
import '../../documents/document_view.dart' show VatBlock;
import '../../stock/stock_options.dart';
import '../offline_sale_queue.dart' show SalesSession;
import '../receipt_data.dart';
import '../receipt_page.dart' show shareReceipt;
import '../sale_models.dart';
import '../sales_widgets.dart';
import 'refund_models.dart';

class RefundDetailPage extends StatefulWidget {
  const RefundDetailPage({
    super.key,
    required this.refundId,
    this.saved = false,
    this.initial,
    this.now,
  });

  final String refundId;

  /// Opened right after saving: snack + focus on the heading (§3.3).
  final bool saved;

  /// The refund the save answered with (no second request).
  final Map<String, dynamic>? initial;

  /// Test clock (the undo "same day" rule).
  final DateTime? now;

  @override
  State<RefundDetailPage> createState() => _RefundDetailPageState();
}

enum _State { loading, ready, notFound, failed, offline }

class _RefundDetailPageState extends State<RefundDetailPage> {
  _State _state = _State.loading;
  RefundRecord? _refund;
  VendorTools _tools = VendorTools.off;
  String? _business;
  final _heading = FocusNode(debugLabel: 'refund-heading');

  @override
  void initState() {
    super.initState();
    BrowserOnline.instance.addListener(_onOnline);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    BrowserOnline.instance.removeListener(_onOnline);
    _heading.dispose();
    super.dispose();
  }

  void _onOnline() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    final tools = await enterSalesRoute(context);
    if (tools == null || !mounted) return;
    _tools = tools;
    final api = AppScope.of(context).api;
    final session = SalesSession.of(context);
    () async {
      try {
        final p = await api.vendorProfile();
        if (mounted) setState(() => _business = p['businessName']?.toString());
      } catch (_) {
        final kept = await session?.loadBusiness() ?? const {};
        if (mounted) {
          setState(() => _business = kept['businessName']?.toString());
        }
      }
    }();
    final initial = widget.initial;
    if (initial != null) {
      setState(() {
        _refund = RefundRecord.fromJson(initial);
        _state = _State.ready;
      });
    } else {
      await _load();
    }
    if (!mounted || _refund == null || !widget.saved) return;
    FFSnack.success(
      context,
      fillIn(context.tr('vendor.refunds.saved'), {'number': _refund!.number}),
    );
    _heading.requestFocus();
  }

  Future<void> _load() async {
    setState(() => _state = _State.loading);
    try {
      final res = await AppScope.of(context).api.vendorRefund(widget.refundId);
      if (!mounted) return;
      final r = res['refund'];
      setState(() {
        _refund = r is Map ? RefundRecord.fromJson(r) : null;
        _state = _refund == null ? _State.notFound : _State.ready;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _state = e.status == 404 || e.status == 403
            ? _State.notFound
            : _State.failed,
      );
    } catch (_) {
      if (mounted) setState(() => _state = _State.offline);
    }
  }

  void _toSale() {
    final saleId = _refund?.saleId;
    if (context.canPop()) {
      context.pop();
    } else if (saleId != null && salesIdPattern.hasMatch(saleId)) {
      context.go(saleDetailRoute(saleId));
    } else {
      context.go(salesHomeRoute);
    }
  }

  void _openSale() {
    final saleId = _refund?.saleId;
    if (saleId == null || !salesIdPattern.hasMatch(saleId)) return;
    context.push(saleDetailRoute(saleId));
  }

  String _methodWords(String lang, String? m) =>
      FFLocaleScope.of(context).tIn(lang, paymentMethodKey(m));

  Future<void> _share(RefundRecord r) async {
    final locale = FFLocaleScope.of(context);
    final lang = locale.locale.languageCode;
    String text(String l) => creditNoteShareText(
      r,
      t: (k) => locale.tIn(l, k),
      lang: l,
      method: (m) => _methodWords(l, m),
      business: _business,
    );
    String subject(String l) => [
      ?_business,
      '${locale.tIn(l, 'vendor.doc.credit_note')} ${r.number}',
    ].join(' ');
    if (_tools.documents) {
      await showDocumentShareSheet(
        context,
        doc: DocumentRef.refund(refundId: r.id, number: r.number),
        lang: lang,
        shareText: text,
        shareSubject: subject,
      );
      return;
    }
    await shareReceipt(text(lang), subject(lang));
  }

  Future<void> _revert(RefundRecord r) async {
    final out = await showDialog<_RevertOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RevertDialog(refund: r),
    );
    if (!mounted || out == null) return;
    if (out.refund != null) {
      setState(() => _refund = RefundRecord.fromJson(out.refund!));
    } else {
      // already_reverted on a retry: the undo went through; read it again.
      await _load();
      if (!mounted) return;
    }
    FFSnack.success(
      context,
      fillIn(context.tr('vendor.refunds.reverted'), {'number': r.number}),
    );
    _heading.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final r = _refund;
    final user = AppScope.of(context).auth.user;
    final actions = r != null && _tools.refundsOn && !r.reverted;
    final mayUndo = actions && canRevertRefund(user, r, now: widget.now);
    final online = BrowserOnline.instance.value;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _toSale),
        title: Text(r == null ? t('vendor.doc.credit_note') : r.number),
        actions: [
          if (r != null && (mayUndo || (r.reverted && _tools.documents)))
            PopupMenuButton<String>(
              key: const Key('refund-more'),
              tooltip: t('vendor.refunds.more'),
              onSelected: (v) {
                if (v == 'undo') _revert(r);
                if (v == 'links') {
                  showDocumentLinksSheet(
                    context,
                    DocumentRef.refund(refundId: r.id, number: r.number),
                  );
                }
              },
              itemBuilder: (_) => [
                if (mayUndo)
                  PopupMenuItem(
                    key: const Key('refund-undo'),
                    value: 'undo',
                    enabled: online,
                    height: 48,
                    child: Semantics(
                      label: fillIn(t('vendor.refunds.a11y.undo'), {
                        'number': r.number,
                      }),
                      excludeSemantics: true,
                      child: Text(
                        t('vendor.refunds.revert'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                if (r.reverted && _tools.documents)
                  PopupMenuItem(
                    key: const Key('refund-links'),
                    value: 'links',
                    height: 48,
                    child: Text(t('vendor.documents.linksTitle')),
                  ),
              ],
            ),
        ],
      ),
      body: switch (_state) {
        _State.loading => Padding(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: FFSkeletonList(count: 3, semanticLabel: t('common.loading')),
        ),
        _State.notFound => ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            FFEmptyState(
              key: const Key('refund-not-found'),
              title: t('vendor.refunds.notFound'),
            ),
          ],
        ),
        _State.failed => ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            FFErrorState(
              key: const Key('refund-detail-failed'),
              message: t('vendor.refunds.loadFailed'),
              onRetry: _load,
            ),
          ],
        ),
        _State.offline => ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            FFErrorState(
              key: const Key('refund-detail-offline'),
              icon: Icons.wifi_off_outlined,
              message: t('error.network'),
              onRetry: _load,
            ),
          ],
        ),
        _State.ready => _content(context, r!),
      },
      bottomNavigationBar: _state == _State.ready && r != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  FFTokens.spacingLg,
                  FFTokens.spacingSm,
                  FFTokens.spacingLg,
                  FFTokens.spacingMd,
                ),
                child: Wrap(
                  spacing: FFTokens.spacingSm,
                  runSpacing: FFTokens.spacingSm,
                  alignment: WrapAlignment.end,
                  children: [
                    if (actions)
                      FFButton(
                        key: const Key('refund-share'),
                        label: t('vendor.refunds.share'),
                        icon: Icons.share,
                        visualDensity: VisualDensity.standard,
                        onPressed: () => _share(r),
                      ),
                    FFButton(
                      key: const Key('refund-done'),
                      label: t('vendor.refunds.done'),
                      variant: FFButtonVariant.secondary,
                      visualDensity: VisualDensity.standard,
                      onPressed: _toSale,
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _content(BuildContext context, RefundRecord r) {
    final t = context.tr;
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final saleLink = r.credit && r.saleInvoiceNumber != null
        ? fillIn(t('vendor.refunds.forInvoice'), {
            'number': r.saleInvoiceNumber,
          })
        : fillIn(t('vendor.doc.forReceipt'), {'number': r.saleNumber ?? ''});
    final customer =
        r.customerName ??
        (r.customerId == null
            ? null
            : t(
                r.customerForgotten
                    ? 'vendor.customers.deletedMember'
                    : 'vendor.orders.buyerUnnamed',
              ));
    String money(int v) => formatCurrency(v);
    final paidBack = r.reference == null
        ? _methodWords(lang, r.method)
        : '${_methodWords(lang, r.method)} (${r.reference})';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            Focus(
              focusNode: _heading,
              child: Semantics(
                header: true,
                child: Text(
                  fillIn(t('vendor.refunds.cnTitle'), {'number': r.number}),
                  key: const Key('refund-heading'),
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FFBadge(
                key: const Key('refund-status'),
                label: t(
                  r.reverted
                      ? 'vendor.refunds.status.reverted'
                      : 'vendor.refunds.status.active',
                ),
                tone: r.reverted ? FFBadgeTone.gray : FFBadgeTone.info,
              ),
            ),
            if (r.reverted) ...[
              const SizedBox(height: FFTokens.spacingSm),
              FFAlert(
                key: const Key('refund-reverted-by'),
                message: fillIn(t('vendor.refunds.revertedBy'), {
                  'name': r.revertedByName ?? '—',
                  'time': eatDateTime(r.revertedAt, locale: lang),
                  'reason': r.revertReason ?? '',
                }),
              ),
            ],
            const SizedBox(height: FFTokens.spacingSm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FFButton(
                key: const Key('refund-sale-link'),
                label: saleLink,
                icon: Icons.receipt_long_outlined,
                variant: FFButtonVariant.ghost,
                visualDensity: VisualDensity.standard,
                onPressed:
                    r.saleId != null && salesIdPattern.hasMatch(r.saleId!)
                    ? _openSale
                    : null,
              ),
            ),
            Text(eatDateTime(r.refundedAt, locale: lang), style: muted),
            if (r.createdByName != null)
              Text(
                fillIn(t('vendor.pos.servedBy'), {'name': r.createdByName}),
                style: muted,
              ),
            if (customer != null)
              Text(
                fillIn(t('vendor.receipt.customer'), {'name': customer}),
                key: const Key('refund-customer'),
              ),
            const SizedBox(height: FFTokens.spacingMd),
            FFCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final l in r.lines)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: FFTokens.spacingXs,
                      ),
                      child: Semantics(
                        container: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            MoneyRow(
                              '${l.qty} × ${l.displayName}',
                              l.vatCode == null
                                  ? money(l.amountTzs)
                                  : '${money(l.amountTzs)} ${l.vatCode}',
                              strike: r.reverted,
                            ),
                            Text(
                              t(
                                l.restock
                                    ? 'vendor.refunds.backInStock'
                                    : 'vendor.refunds.notBackInStock',
                              ),
                              style: muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Divider(height: FFTokens.spacingLg),
                  MoneyRow(
                    r.reverted
                        ? '${t('vendor.refunds.total')} · ${t('vendor.refunds.status.reverted')}'
                        : t('vendor.refunds.total'),
                    money(r.amountTzs),
                    strong: true,
                    strike: r.reverted,
                    key: const Key('refund-detail-total'),
                  ),
                  if (r.balanceReducedTzs > 0)
                    MoneyRow(
                      t('vendor.refunds.offBalanceShort'),
                      '−${money(r.balanceReducedTzs)}',
                      key: const Key('refund-detail-off-balance'),
                    ),
                  if (r.paidOutTzs > 0)
                    MoneyRow(
                      fillIn(t('vendor.refunds.paidBackBy'), {
                        'method': paidBack,
                      }),
                      money(r.paidOutTzs),
                      key: const Key('refund-detail-paid-back'),
                    )
                  else if (r.balanceReducedTzs == 0)
                    Text(t('vendor.doc.nothingPaidBack'), style: muted),
                  if (r.hasVat)
                    VatBlock(
                      vatIncludedTzs: r.vatTzs,
                      rows: r.vatSummary,
                      t: t,
                    ),
                ],
              ),
            ),
            if (r.reason != null) ...[
              const SizedBox(height: FFTokens.spacingSm),
              Text(
                fillIn(t('vendor.refunds.reasonLabel'), {'reason': r.reason}),
                key: const Key('refund-reason-text'),
              ),
            ],
            const SizedBox(height: FFTokens.spacingSm),
            FFAlert(
              key: const Key('refund-detail-money-notice'),
              message: t('vendor.refunds.moneyNotice'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── undo (§4.5) ──────────────────────────────────────────────────────────

/// The undo's answer: the refund as it is now, or null when the server
/// said already_reverted (read it again).
class _RevertOutcome {
  const _RevertOutcome(this.refund);
  final Map<String, dynamic>? refund;
}

class _RevertDialog extends StatefulWidget {
  const _RevertDialog({required this.refund});
  final RefundRecord refund;

  @override
  State<_RevertDialog> createState() => _RevertDialogState();
}

class _RevertDialogState extends State<_RevertDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _fieldError;

  /// insufficient_stock: the product to count.
  String? _countProductId;
  String? _countVariant;

  /// customer_archived: the customer to restore.
  String? _customerId;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _ok => _reason.text.trim().length >= refundReasonMin;

  void _close(_RevertOutcome? out) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(out);
  }

  Future<void> _submit() async {
    if (!_ok || _busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _fieldError = null;
      _countProductId = null;
      _customerId = null;
    });
    final t = context.tr;
    final r = widget.refund;
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorRevertRefund(r.id, _reason.text.trim());
      if (!mounted) return;
      final refund = res['refund'];
      _close(
        _RevertOutcome(
          refund is Map ? Map<String, dynamic>.from(refund) : null,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      final b = e.body is Map ? e.body as Map : const {};
      switch (e.code) {
        case 'already_reverted':
          // A retry after a lost answer: the undo went through (#318 review).
          _close(const _RevertOutcome(null));
          return;
        case 'insufficient_stock':
          final productId = b['productId']?.toString();
          final variant = b['variant']?.toString();
          setState(() {
            _countProductId = productId;
            _countVariant = variant;
            _error = fillIn(t('vendor.refunds.err.revertStock'), {
              'available': b['available'] ?? 0,
              'name': r.nameOfProduct(productId, variant) ?? '',
            });
          });
        case 'customer_archived':
          setState(() {
            _customerId = b['customerId']?.toString() ?? r.customerId;
            _error = fillIn(t('vendor.refunds.err.customerArchived'), {
              'name': r.customerName ?? t('vendor.orders.buyerUnnamed'),
            });
          });
        case 'reason_required' || 'reason_too_long':
          setState(() => _fieldError = t('vendor.refunds.reasonMissing'));
        case 'revert_not_allowed':
          setState(() => _error = t('vendor.refunds.askOwner'));
        default:
          setState(
            () => _error = t(
              e.status == 403 && e.code != 'vendor_suspended'
                  ? 'vendor.pos.err.notAllowed'
                  : refundErrorKey(e.code),
            ),
          );
      }
      setState(() => _busy = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = t('vendor.refunds.offline');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final r = widget.refund;
    final amount = formatCurrency(r.amountTzs);
    final productId = _countProductId;
    final customerId = _customerId;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          fillIn(t('vendor.refunds.revertTitle'), {'number': r.number}),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(fillIn(t('vendor.refunds.revertBody'), {'amount': amount})),
              if (r.credit && r.balanceReducedTzs > 0) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Text(
                  fillIn(t('vendor.refunds.revertCredit'), {
                    'amount': formatCurrency(r.balanceReducedTzs),
                    'name': r.customerName ?? t('vendor.orders.buyerUnnamed'),
                  }),
                  key: const Key('refund-revert-credit'),
                ),
              ],
              if (r.anyRestocked) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Text(
                  t('vendor.refunds.revertStock'),
                  key: const Key('refund-revert-stock'),
                ),
              ],
              const SizedBox(height: FFTokens.spacingMd),
              FFTextField(
                key: const Key('refund-revert-reason'),
                controller: _reason,
                label: t('vendor.refunds.revertReason'),
                maxLength: refundReasonMax,
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
                    key: const Key('refund-revert-error'),
                    message: _error!,
                    tone: FFAlertTone.error,
                  ),
                ),
                if (productId != null &&
                    salesIdPattern.hasMatch(productId) &&
                    canVendor(context, 'products'))
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FFButton(
                      key: const Key('refund-revert-count-stock'),
                      label: t('vendor.refunds.countStock'),
                      variant: FFButtonVariant.ghost,
                      visualDensity: VisualDensity.standard,
                      onPressed: () => context.push(
                        Uri(
                          path: '/vendor/products/$productId/stock',
                          queryParameters: {
                            if (_countVariant != null &&
                                _countVariant!.isNotEmpty)
                              'variant': _countVariant!,
                          },
                        ).toString(),
                      ),
                    ),
                  ),
                if (customerId != null &&
                    customerIdPattern.hasMatch(customerId) &&
                    canVendor(context, 'customers'))
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FFButton(
                      key: const Key('refund-revert-customer'),
                      label: r.customerName ?? t('vendor.orders.buyerUnnamed'),
                      icon: Icons.person_outline,
                      variant: FFButtonVariant.ghost,
                      visualDensity: VisualDensity.standard,
                      onPressed: () => context.push(customerRoute(customerId)),
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          FFButton(
            label: t('common.cancel'),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: _busy ? null : () => _close(null),
          ),
          FFButton(
            key: const Key('refund-revert-confirm'),
            label: t('vendor.refunds.revert'),
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
