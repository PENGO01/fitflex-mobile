// Vendor tools · S8: the pieces every scanning screen shares — the result
// row (§4.3), the unknown-code actions (§4.6), the several-matches chooser
// (§4.5), the feedback (§4.3) and "Add this code to a product" (§4.6).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../sales/sale_models.dart' show pluralKey;
import '../stock/stock_options.dart';
import 'barcode_rules.dart';
import 'vendor_scan_controller.dart';
import 'vendor_scan_panel.dart';

/// What the result row shows.
enum ScanNoticeKind { added, warning, unknown, failed }

class ScanNotice {
  const ScanNotice.added({
    required this.name,
    required this.message,
    required this.qty,
    this.productId,
    this.variant,
  }) : kind = ScanNoticeKind.added,
       code = null,
       offline = false,
       waitSeconds = null;

  const ScanNotice.warning(this.message, {this.waitSeconds})
    : kind = ScanNoticeKind.warning,
      name = null,
      qty = 0,
      productId = null,
      variant = null,
      code = null,
      offline = false;

  const ScanNotice.unknown(
    this.message, {
    required this.code,
    this.offline = false,
  }) : kind = ScanNoticeKind.unknown,
       name = null,
       qty = 0,
       productId = null,
       variant = null,
       waitSeconds = null;

  const ScanNotice.failed(this.message, {this.code})
    : kind = ScanNoticeKind.failed,
      name = null,
      qty = 0,
      productId = null,
      variant = null,
      offline = false,
      waitSeconds = null;

  final ScanNoticeKind kind;
  final String message;
  final String? name;
  final int qty;
  final String? productId;
  final String? variant;
  final String? code;
  final bool offline;

  /// 429: the wait in seconds; the message counts down and clears (UAT L-3).
  final int? waitSeconds;
}

/// "Too many scans. Wait {s} seconds." counting down once a second; calls
/// [onDone] when the wait is over (and then shows nothing). Read out once:
/// its accessible label stays the first message, not every tick.
class RateLimitAlert extends StatefulWidget {
  const RateLimitAlert({super.key, required this.seconds, this.onDone});

  final int seconds;
  final VoidCallback? onDone;

  @override
  State<RateLimitAlert> createState() => _RateLimitAlertState();
}

class _RateLimitAlertState extends State<RateLimitAlert> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left -= 1);
      if (_left <= 0) {
        t.cancel();
        widget.onDone?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _text(int s) =>
      fillIn(context.tr(pluralKey('vendor.scan.rateLimited', s)), {'s': s});

  @override
  Widget build(BuildContext context) {
    if (_left <= 0) return const SizedBox.shrink();
    return Semantics(
      label: _text(widget.seconds),
      excludeSemantics: true,
      child: FFAlert(
        key: const Key('scan-rate-limited'),
        message: _text(_left),
        tone: FFAlertTone.warning,
      ),
    );
  }
}

/// The server's `message: {en, sw}` in the app's language, if it sent one.
String? serverMessage(BuildContext context, Object? body) {
  final m = body is Map ? body['message'] : null;
  if (m is! Map) return null;
  final lang = FFLocaleScope.of(context).locale.languageCode;
  final text = m[lang] ?? m['en'];
  return text is String && text.trim().isNotEmpty ? text : null;
}

/// Haptic + polite announcement for an outcome (§4.3; no sound in v1).
void scanFeedback(BuildContext context, ScanNoticeKind kind, String message) {
  switch (kind) {
    case ScanNoticeKind.added:
      HapticFeedback.lightImpact();
    case ScanNoticeKind.warning ||
        ScanNoticeKind.unknown ||
        ScanNoticeKind.failed:
      HapticFeedback.heavyImpact();
  }
  SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    Directionality.of(context),
  );
}

/// The words for an outcome that did not match (null for a match).
ScanNotice? noticeFor(
  BuildContext context,
  ScanOutcome outcome, {
  bool canManage = false,
}) {
  final t = context.tr;
  final code = outcome.code;
  return switch (outcome.kind) {
    ScanOutcomeKind.matched => null,
    ScanOutcomeKind.notFound => ScanNotice.unknown(
      fillCode(t('vendor.scan.notFound'), code),
      code: code,
    ),
    ScanOutcomeKind.notFoundOffline => ScanNotice.unknown(
      fillCode(t('vendor.scan.notFoundOffline'), code),
      code: code,
      offline: true,
    ),
    ScanOutcomeKind.notProduct => ScanNotice.warning(
      t('vendor.scan.notProduct'),
    ),
    ScanOutcomeKind.rateLimited => ScanNotice.warning(
      fillIn(t(pluralKey('vendor.scan.rateLimited', outcome.seconds ?? 60)), {
        's': outcome.seconds ?? 60,
      }),
      waitSeconds: outcome.seconds ?? 60,
    ),
    ScanOutcomeKind.lookupFailed => ScanNotice.failed(
      t('vendor.scan.lookupFailed'),
      code: code,
    ),
    ScanOutcomeKind.featureOff => ScanNotice.warning(
      t('vendor.barcodes.unavailable'),
    ),
    ScanOutcomeKind.noAccess => ScanNotice.warning(t('vendor.scan.noAccess')),
    ScanOutcomeKind.suspended => ScanNotice.warning(
      t('vendor.sales.suspended'),
    ),
  };
}

/// The last handled code (continuous mode): what was added with a −/+
/// stepper and Undo, or a warning / unknown code / failure.
class ScanResultRow extends StatelessWidget {
  const ScanResultRow({
    super.key,
    required this.notice,
    this.onMore,
    this.onLess,
    this.onUndo,
    this.onRetry,
    this.actions,
    this.onWaitOver,
  });

  /// A 429 wait ended: the screen clears the row.
  final VoidCallback? onWaitOver;

  final ScanNotice? notice;
  final VoidCallback? onMore;
  final VoidCallback? onLess;
  final VoidCallback? onUndo;
  final VoidCallback? onRetry;

  /// Unknown code: the actions under the message.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final n = notice;
    if (n == null) return const SizedBox.shrink();
    final t = context.tr;
    final theme = Theme.of(context);
    const square = Size(48, 48);
    final iconStyle = IconButton.styleFrom(
      minimumSize: square,
      visualDensity: VisualDensity.standard,
    );
    final Widget body;
    switch (n.kind) {
      case ScanNoticeKind.added:
        final name = n.name ?? '';
        body = FFCard(
          key: const Key('scan-result'),
          padding: const EdgeInsets.symmetric(
            horizontal: FFTokens.spacingSm,
            vertical: FFTokens.spacingXs,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              runSpacing: FFTokens.spacingXs,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 160),
                  child: Semantics(
                    container: true,
                    label: fillIn(t('vendor.scan.resultLabel'), {
                      'name': name,
                      'qty': n.qty,
                    }),
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(n.message, key: const Key('scan-result-text')),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onLess != null)
                      IconButton(
                        key: const Key('scan-result-less'),
                        style: iconStyle,
                        tooltip: fillIn(t('vendor.scan.oneFewerScanned'), {
                          'name': name,
                        }),
                        icon: const Icon(Icons.remove),
                        onPressed: onLess,
                      ),
                    if (onMore != null)
                      IconButton(
                        key: const Key('scan-result-more'),
                        style: iconStyle,
                        tooltip: fillIn(t('vendor.scan.oneMoreScanned'), {
                          'name': name,
                        }),
                        icon: const Icon(Icons.add),
                        onPressed: onMore,
                      ),
                    if (onUndo != null)
                      FFButton(
                        key: const Key('scan-result-undo'),
                        label: t('vendor.scan.undo'),
                        semanticLabel: fillIn(t('vendor.scan.undoLabel'), {
                          'name': name,
                        }),
                        variant: FFButtonVariant.ghost,
                        visualDensity: VisualDensity.standard,
                        onPressed: onUndo,
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      case ScanNoticeKind.warning:
        final wait = n.waitSeconds;
        body = wait != null
            ? RateLimitAlert(
                key: ObjectKey(n),
                seconds: wait,
                onDone: onWaitOver,
              )
            : FFAlert(
                key: const Key('scan-warning'),
                message: n.message,
                tone: FFAlertTone.warning,
              );
      case ScanNoticeKind.unknown:
        body = Column(
          key: const Key('scan-unknown'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FFAlert(message: n.message, tone: FFAlertTone.warning),
            if (actions != null) ...[
              const SizedBox(height: FFTokens.spacingXs),
              actions!,
            ],
          ],
        );
      case ScanNoticeKind.failed:
        body = Column(
          key: const Key('scan-failed'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FFAlert(message: n.message, tone: FFAlertTone.error),
            if (onRetry != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FFButton(
                  key: const Key('scan-lookup-retry'),
                  label: t('common.retry'),
                  icon: Icons.refresh,
                  variant: FFButtonVariant.ghost,
                  visualDensity: VisualDensity.standard,
                  onPressed: onRetry,
                ),
              ),
          ],
        );
    }
    return Semantics(liveRegion: true, child: body);
  }
}

/// §4.6: what can be done with a code no product has. The add actions need
/// `products` and a connection; without `products` a muted line says who
/// can add it. Buttons are full width and stacked (long Swahili).
class UnknownCodeActions extends StatelessWidget {
  const UnknownCodeActions({
    super.key,
    required this.code,
    required this.canManage,
    this.offline = false,
    this.onAddToProduct,
    this.onCreateProduct,
    this.onSearchByName,
    this.onScanAgain,
  });

  final String code;
  final bool canManage;
  final bool offline;
  final VoidCallback? onAddToProduct;
  final VoidCallback? onCreateProduct;
  final VoidCallback? onSearchByName;
  final VoidCallback? onScanAgain;

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final adds = canManage && !offline;
    Widget button(
      Key key,
      String label,
      IconData icon,
      VoidCallback? f, {
      FFButtonVariant variant = FFButtonVariant.secondary,
    }) => Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingXs),
      child: FFButton(
        key: key,
        label: label,
        // The button names the code too (§9).
        semanticLabel: '$label, ${spokenCode(code)}',
        icon: icon,
        variant: variant,
        fullWidth: true,
        maxLines: 2,
        visualDensity: VisualDensity.standard,
        onPressed: f,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (adds && onAddToProduct != null)
          button(
            const Key('scan-add-to-product'),
            t('vendor.scan.addToProduct'),
            Icons.link,
            onAddToProduct,
          ),
        if (adds && onCreateProduct != null)
          button(
            const Key('scan-create-product'),
            t('vendor.scan.createProduct'),
            Icons.add_box_outlined,
            onCreateProduct,
          ),
        if (!canManage)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingXs),
            child: Text(
              t('vendor.scan.askProducts'),
              key: const Key('scan-ask-products'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (onSearchByName != null)
          button(
            const Key('scan-search-by-name'),
            t('vendor.scan.searchByName'),
            Icons.search,
            onSearchByName,
            variant: FFButtonVariant.ghost,
          ),
        if (onScanAgain != null)
          button(
            const Key('scan-again'),
            t('vendor.scan.again'),
            Icons.qr_code_scanner,
            onScanAgain,
            variant: FFButtonVariant.ghost,
          ),
      ],
    );
  }
}

/// §4.5: several products share this SKU; resolves with the one picked.
Future<ScanMatch?> pickScanMatch(
  BuildContext context,
  List<ScanMatch> matches,
) => showFFSheet<ScanMatch>(
  context,
  title: context.tr('vendor.scan.pickMatch'),
  focusTitle: true,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final m in matches)
        Builder(
          builder: (sheet) => ListTile(
            key: Key('scan-pick-${m.productId}'),
            minTileHeight: 56,
            title: Text(m.name),
            subtitle: Text(
              [
                ?m.variant,
                fillIn(sheet.tr('vendor.purchases.inStockN'), {'n': m.stock}),
                if (m.priceTzs != null) formatCurrency(m.priceTzs!),
              ].join(' · '),
            ),
            trailing: m.archived
                ? FFBadge(
                    label: sheet.tr('vendor.scan.archivedBadge'),
                    tone: FFBadgeTone.gray,
                  )
                : null,
            onTap: () => Navigator.of(sheet).pop(m),
          ),
        ),
    ],
  ),
);

/// Resolves several matches through the chooser (with the scanner held),
/// or the single one. Null when the vendor cancelled.
Future<ScanMatch?> singleMatch(
  BuildContext context,
  VendorScanController controller,
  List<ScanMatch> matches,
) async {
  if (matches.isEmpty) return null;
  if (matches.length == 1) return matches.single;
  HapticFeedback.selectionClick();
  controller.hold();
  try {
    return await pickScanMatch(context, matches);
  } finally {
    controller.release();
  }
}

/// What "Add this code to a product" ended with.
class AddCodeResult {
  const AddCodeResult({
    this.product,
    this.variant,
    this.inUseBy,
    this.barcodesOff = false,
  });

  /// Barcodes went off on the server (404 feature_disabled, or a 200 that
  /// left the codes out): the screen closes its scanner and asks for the
  /// tools again.
  final bool barcodesOff;

  /// The saved product (the PUT answer) when the code was added.
  final Map<String, dynamic>? product;
  final String? variant;

  /// 409 barcode_in_use: the product that has the code now.
  final String? inUseBy;

  bool get added => product != null;
}

/// §4.6 "Add this code to a product": product picker → variant → confirm →
/// `PUT /vendor/products/:id {addBarcodes: [{code, variant}]}`. Null when
/// the vendor cancelled or the save failed (a snack says why).
Future<AddCodeResult?> addCodeToProduct(
  BuildContext context, {
  required String code,
  required List<Map<String, dynamic>> products,
}) async {
  final t = context.tr;
  final picked = await showFFSheet<Map<String, dynamic>>(
    context,
    title: t('vendor.scan.chooseProduct'),
    child: _CodeProductPicker(products: products),
  );
  if (picked == null || !context.mounted) return null;
  String? variant;
  final names = [
    for (final v in (picked['variants'] as List? ?? const []).whereType<Map>())
      if ((v['name']?.toString() ?? '').isNotEmpty) v['name'].toString(),
  ];
  if (names.isNotEmpty) {
    const whole = '\u0000whole';
    final choice = await showFFSheet<String>(
      context,
      title: t('vendor.barcodes.for'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final n in [whole, ...names])
            Builder(
              builder: (sheet) => ListTile(
                key: Key('scan-add-for-${n == whole ? 'whole' : n}'),
                minTileHeight: 56,
                title: Text(
                  n == whole ? sheet.tr('vendor.barcodes.wholeProduct') : n,
                ),
                onTap: () => Navigator.of(sheet).pop(n),
              ),
            ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return null;
    variant = choice == whole ? null : choice;
  }
  final name = picked['name']?.toString() ?? '';
  final ok = await showFFConfirmDialog(
    context,
    title: fillIn(t('vendor.scan.confirmAddTitle'), {
      'code': code,
      'name': variant == null ? name : '$name ($variant)',
    }),
    confirmLabel: t('vendor.scan.confirmAdd'),
    confirmKey: const Key('scan-confirm-add'),
    cancelKey: const Key('scan-confirm-cancel'),
  );
  if (!ok || !context.mounted) return null;
  try {
    final saved = await AppScope.of(context).api.vendorSaveProduct({
      'addBarcodes': [
        {'code': code, 'variant': ?variant},
      ],
    }, productId: picked['id']?.toString());
    if (!context.mounted) return null;
    if (!saved.containsKey('barcodes')) {
      // 200 without `barcodes`: the flag went off and the code was ignored.
      // Never "code added".
      FFSnack.error(context, t('vendor.barcodes.unavailable'));
      unawaited(VendorToolsOptions.of(context, refresh: true));
      return const AddCodeResult(barcodesOff: true);
    }
    FFSnack.success(
      context,
      fillIn(t('vendor.scan.codeAdded'), {'name': name}),
    );
    return AddCodeResult(product: saved, variant: variant);
  } on ApiException catch (e) {
    if (!context.mounted) return null;
    final body = e.body is Map ? e.body as Map : const {};
    if (e.code == 'barcode_in_use') {
      final key = barcodeInUseKey(body);
      if (key == 'vendor.barcodes.err.inUseRetry') {
        // Nobody named (a retried save failed twice): nothing was saved.
        FFSnack.error(context, t(key));
        return null;
      }
      final holder = body['name']?.toString() ?? '';
      FFSnack.error(
        context,
        fillIn(t('vendor.barcodes.err.inUse'), {'name': holder}),
      );
      return AddCodeResult(inUseBy: holder);
    }
    if (e.status == 404 && e.code == 'feature_disabled') {
      FFSnack.error(context, t('vendor.barcodes.unavailable'));
      unawaited(VendorToolsOptions.of(context, refresh: true));
      return const AddCodeResult(barcodesOff: true);
    }
    if (e.code == 'save_conflict') {
      FFSnack.error(
        context,
        serverMessage(context, body) ?? t('vendor.barcodes.err.saveConflict'),
      );
      return null;
    }
    final key = barcodeErrorKey(e.code, reason: body['reason']?.toString());
    FFSnack.error(
      context,
      fillIn(t(key), {
        'max': body['max'] ?? maxBarcodesPerProduct,
        'variant': body['variant'] ?? '',
        'name': body['name'] ?? '',
      }),
    );
    return null;
  } catch (_) {
    if (context.mounted) FFSnack.error(context, t('error.network'));
    return null;
  }
}

/// Search by name or SKU; archived products are listed with a badge.
class _CodeProductPicker extends StatefulWidget {
  const _CodeProductPicker({required this.products});

  final List<Map<String, dynamic>> products;

  @override
  State<_CodeProductPicker> createState() => _CodeProductPickerState();
}

class _CodeProductPickerState extends State<_CodeProductPicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final q = _q.text.trim().toLowerCase();
    final rows = [
      for (final p in widget.products)
        if (p['deletedAt'] == null &&
            (q.isEmpty ||
                (p['name']?.toString().toLowerCase() ?? '').contains(q) ||
                (p['sku']?.toString().toLowerCase() ?? '').contains(q)))
          p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FFTextField(
          key: const Key('scan-add-search'),
          controller: _q,
          label: t('vendor.purchases.searchProducts'),
          prefixIcon: const Icon(Icons.search),
          onChanged: (_) => setState(() {}),
        ),
        if (rows.isEmpty)
          FFEmptyState(title: t('vendor.purchases.noProducts'))
        else
          for (final p in rows.take(100))
            ListTile(
              key: Key('scan-add-pick-${p['id']}'),
              minTileHeight: 56,
              title: Text(p['name']?.toString() ?? ''),
              subtitle: (p['sku']?.toString() ?? '').isEmpty
                  ? null
                  : Text(p['sku'].toString()),
              trailing: p['status'] == 'archived'
                  ? FFBadge(
                      label: t('vendor.scan.archivedBadge'),
                      tone: FFBadgeTone.gray,
                    )
                  : null,
              onTap: () => Navigator.of(context).pop(p),
            ),
      ],
    );
  }
}
