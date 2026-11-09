// Vendor tools · S1: the "Adjust stock" sheet. Every stock change is
// recorded with a reason (POST /vendor/products/:id/stock-adjustments).
//
// - Counted sets the stock to what was counted; the server refuses it
//   (409 stock_changed) if the stock moved since the vendor saw it.
// - Restocked / Returned / Found add; Damaged / Expired / Lost remove;
//   Other asks which way and needs a note.
// - Each new entry gets a new clientRef. A retry of the same entry after a
//   network failure reuses it, so a request that did reach the server is
//   not applied twice. Changing anything makes it a new entry.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../barcodes/scan_widgets.dart';
import '../sales/sale_models.dart' show pluralKey;
import '../barcodes/vendor_scan_controller.dart';
import '../barcodes/vendor_scan_panel.dart';
import 'stock_options.dart';

/// How the sheet ended when it did not save.
enum AdjustExit { notAllowed, notFound, failed }

/// What [openAdjustStock] resolves with after a save.
class AdjustResult {
  AdjustResult(this.movement, this.product);

  /// The ledger row: stockBefore, stockAfter, delta…
  final Map<String, dynamic> movement;

  /// The product's counts after the change: `{id, stock, variants}`.
  final Map<String, dynamic> product;
}

/// A new client reference: 128 random bits as hex (the server allows
/// 8–100 characters of letters, digits and `._:-`).
String newStockClientRef([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return 'adj_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

/// Opens the sheet for [product] (a vendor product map: id, name, stock,
/// variants). [variant] preselects a variant. Shows the result snack and
/// resolves with the saved change, or null when nothing was saved.
/// How [openAdjustStock] reports its outcome when a snackbar would not be
/// seen (e.g. it is opened from inside another sheet, which covers it).
typedef AdjustNotify = void Function(String message, {required bool error});

Future<AdjustResult?> openAdjustStock(
  BuildContext context, {
  required Map<String, dynamic> product,
  String? variant,
  String Function()? makeClientRef,
  AdjustNotify? notify,
  String? initialReason,
}) async {
  final out = await showFFSheet<Object>(
    context,
    title: context.tr('vendor.stock.adjust'),
    child: AdjustStockSheet(
      product: product,
      variant: variant,
      makeClientRef: makeClientRef,
      initialReason: initialReason,
    ),
  );
  if (!context.mounted) return null;
  void tell(String message, {required bool error}) {
    if (notify != null) return notify(message, error: error);
    error ? FFSnack.error(context, message) : FFSnack.success(context, message);
  }

  if (out is AdjustResult) {
    tell(
      fillIn(context.tr('vendor.stock.updated'), {
        'before': formatStock(out.movement['stockBefore'] as num? ?? 0),
        'after': formatStock(out.movement['stockAfter'] as num? ?? 0),
      }),
      error: false,
    );
    return out;
  }
  if (out is AdjustExit) {
    tell(
      context.tr(switch (out) {
        AdjustExit.notAllowed => 'vendor.stock.notAllowed',
        AdjustExit.notFound => 'vendor.stock.notFound',
        AdjustExit.failed => 'vendor.saveFailed',
      }),
      error: true,
    );
  }
  return null;
}

/// Tracked variants (those that keep their own stock) of a product map.
List<({String name, int stock})> trackedVariants(Map<String, dynamic> p) => [
  for (final v in (p['variants'] as List? ?? []).whereType<Map>())
    if (v['stock'] is num && (v['name']?.toString() ?? '').isNotEmpty)
      (name: v['name'].toString(), stock: (v['stock'] as num).toInt()),
];

class AdjustStockSheet extends StatefulWidget {
  const AdjustStockSheet({
    super.key,
    required this.product,
    this.variant,
    this.makeClientRef,
    this.initialReason,
  });

  final Map<String, dynamic> product;
  final String? variant;
  final String Function()? makeClientRef;

  /// A reason chosen up front (S3: "Count stock" from a sale conflict opens
  /// with Counted).
  final String? initialReason;

  @override
  State<AdjustStockSheet> createState() => _AdjustStockSheetState();
}

class _AdjustStockSheetState extends State<AdjustStockSheet> {
  late Map<String, dynamic> _product = Map.of(widget.product);
  String? _variant;
  String? _reason;
  String? _direction; // 'in' | 'out', for Other
  final _quantity = TextEditingController();
  final _note = TextEditingController();
  final _quantityFocus = FocusNode();
  bool _loading = true;
  bool _busy = false;
  String? _clientRef;
  // Alerts at the top of the sheet.
  bool _changed = false;
  bool _networkFailed = false;
  bool _saveFailed = false;
  // A specific problem to fix before saving again (an i18n key).
  String? _notice;
  // Focus the quantity once the save has finished (after a 409).
  bool _refocusQuantity = false;
  String? _quantityError;
  String? _noteError;

  /// S9: "Bought from a supplier? Use Receive stock…" (tool on and
  /// `purchases`).
  bool _purchasesHint = false;

  // S8 (§5.3): "Count by scanning" in Counted (barcodes on).
  bool _barcodes = false;
  bool _countScanOpen = false;
  ScanNotice? _countNotice;
  List<Map<String, dynamic>> _rows = const [];
  late final VendorScanController _countScan = VendorScanController(
    index: () => ProductCodeIndex(_rows.isEmpty ? [_product] : _rows),
    lookup: apiScanLookup(AppScope.of(context).api),
  );
  bool _countScanUsed = false;

  String get _productId => widget.product['id']?.toString() ?? '';

  List<({String name, int stock})> get _variants => trackedVariants(_product);

  @override
  void initState() {
    super.initState();
    final pre = widget.variant;
    if (pre != null && trackedVariants(_product).any((v) => v.name == pre)) {
      _variant = pre;
    }
    if (adjustReasons.contains(widget.initialReason)) {
      _reason = widget.initialReason;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    _quantityFocus.dispose();
    if (_countScanUsed) _countScan.dispose();
    super.dispose();
  }

  /// Fresh counts on open; the ones the sheet was given stand if this fails.
  Future<void> _refresh() async {
    VendorToolsOptions.of(context).then((tools) {
      if (mounted && tools.purchases && canVendor(context, 'purchases')) {
        setState(() => _purchasesHint = true);
      }
      if (mounted && tools.barcodes) setState(() => _barcodes = true);
    });
    try {
      final rows = await AppScope.of(context).api.vendorProducts();
      _rows = rows.whereType<Map>().map(Map<String, dynamic>.from).toList();
      final fresh = rows.whereType<Map>().firstWhere(
        (p) => p['id']?.toString() == _productId,
        orElse: () => const {},
      );
      if (!mounted) return;
      if (fresh.isNotEmpty) {
        setState(() => _product = Map<String, dynamic>.from(fresh));
      }
    } catch (_) {
      // Keep what we have; the server still checks the count.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The stock of the chosen variant, or of the product. Null until a
  /// variant is chosen when the product has variants.
  int? get _current {
    final variants = _variants;
    if (variants.isEmpty) return (_product['stock'] as num?)?.toInt() ?? 0;
    for (final v in variants) {
      if (v.name == _variant) return v.stock;
    }
    return null;
  }

  /// 'count', 'in' or 'out', from the reason (and direction for Other).
  String? get _kind => switch (_reason) {
    'count' => 'count',
    'other' => _direction,
    final r when inReasons.contains(r) => 'in',
    final r when outReasons.contains(r) => 'out',
    _ => null,
  };

  int? get _qty => int.tryParse(_quantity.text.trim());

  bool get _quantityValid {
    final q = _qty;
    if (q == null) return false;
    return _kind == 'count' ? q >= 0 : q >= 1;
  }

  bool get _insufficient {
    final q = _qty;
    final current = _current;
    return _kind == 'out' && q != null && current != null && current - q < 0;
  }

  bool get _canSave =>
      !_loading &&
      !_busy &&
      _current != null &&
      _reason != null &&
      _kind != null &&
      _quantityValid &&
      !_insufficient &&
      // Other needs a note before it can be saved.
      (_reason != 'other' || _note.text.trim().isNotEmpty);

  // ── S8: count by scanning ────────────────────────────────────────────

  /// Each scan of this product's code (the chosen variant's, or a
  /// whole-product code) adds 1 to Counted; another product's code changes
  /// nothing and says whose it is.
  Future<bool> _onCountCode(String raw, {required bool typed}) async {
    final outcome = await _countScan.handle(raw, typed: typed);
    if (outcome == null || !mounted) return false;
    final t = context.tr;
    if (outcome.kind == ScanOutcomeKind.featureOff) {
      setState(() => _countScanOpen = false);
      return false;
    }
    final notice = noticeFor(context, outcome);
    if (notice != null) {
      _countSay(notice);
      return false;
    }
    final mine = outcome.matches.where((m) => m.productId == _productId);
    final m = mine.isNotEmpty ? mine.first : outcome.matches.first;
    final variants = _variants;
    final fits =
        m.productId == _productId &&
        (m.variant == null ||
            m.variant == _variant ||
            (_variant == null && variants.any((v) => v.name == m.variant)));
    if (!fits) {
      _countSay(
        ScanNotice.warning(
          fillIn(t('vendor.scan.otherProduct'), {'name': m.label}),
        ),
      );
      return false;
    }
    if (_variant == null && m.variant != null) _variant = m.variant;
    _countBy(1);
    scanFeedback(context, ScanNoticeKind.added, _countNotice!.message);
    return true;
  }

  void _countSay(ScanNotice notice) {
    setState(() => _countNotice = notice);
    scanFeedback(context, notice.kind, notice.message);
  }

  /// Scans add to what is typed in Counted.
  void _countBy(int delta) {
    final next = (_qty ?? 0) + delta;
    _quantity.text = '${next < 0 ? 0 : next}';
    _edited();
    final n = _qty ?? 0;
    final name = widget.product['name']?.toString() ?? '';
    setState(
      () => _countNotice = ScanNotice.added(
        name: _variant == null ? name : '$name ($_variant)',
        qty: n,
        message: fillIn(context.tr(pluralKey('vendor.scan.counted', n)), {
          'n': n,
        }),
      ),
    );
  }

  /// Anything the vendor changes makes this a new entry.
  void _edited() {
    setState(() {
      _clientRef = null;
      _networkFailed = false;
      _saveFailed = false;
      _notice = null;
      _quantityError = null;
      if (_note.text.trim().isNotEmpty) _noteError = null;
    });
  }

  void _setStock(int stock) {
    final variants = (_product['variants'] as List? ?? [])
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .toList();
    if (_variant != null) {
      for (final v in variants) {
        if (v['name'] == _variant) v['stock'] = stock;
      }
      _product = {..._product, 'variants': variants};
    } else {
      _product = {..._product, 'stock': stock};
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final note = _note.text.trim();
    if (_reason == 'other' && note.isEmpty) {
      setState(() => _noteError = context.tr('vendor.stock.noteMissing'));
      return;
    }
    final ref = _clientRef ??= (widget.makeClientRef ?? newStockClientRef)();
    final body = <String, dynamic>{
      'variant': ?_variant,
      'reason': _reason,
      'quantity': _qty,
      if (_reason == 'count') 'expectedStock': _current,
      if (_reason == 'other') 'direction': _direction,
      if (note.isNotEmpty) 'note': note,
      'clientRef': ref,
    };
    setState(() {
      _busy = true;
      _changed = false;
      _networkFailed = false;
      _saveFailed = false;
    });
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorAdjustStock(_productId, body);
      if (!mounted) return;
      Navigator.of(context).pop(
        AdjustResult(
          Map<String, dynamic>.from(res['movement'] as Map? ?? const {}),
          Map<String, dynamic>.from(res['product'] as Map? ?? const {}),
        ),
      );
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      _onApiError(e);
    } catch (_) {
      // Offline, timed out or cut off: keep everything and the same
      // reference, so "Try again" cannot record it twice.
      if (!mounted) return;
      setState(() => _networkFailed = true);
      _announce(
        '${context.tr('error.network')} ${context.tr('vendor.stock.nothingSaved')}',
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (_refocusQuantity) {
      // After the field is enabled again (it is disabled while saving).
      _refocusQuantity = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _quantityFocus.requestFocus();
      });
    }
  }

  /// The product's variants changed under the vendor (renamed, removed, or
  /// now keeping their own stock): load them again and ask for a pick.
  void _variantsChanged() {
    setState(() {
      _variant = null;
      _clientRef = null;
      _notice = 'vendor.stock.variantsChanged';
      _loading = true;
    });
    _refresh();
  }

  /// Says [message] to a screen reader now (alerts that appear in the
  /// sheet are not always picked up as a live region on web).
  void _announce(String message) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
      assertiveness: Assertiveness.assertive,
    );
  }

  void _onApiError(ApiException e) {
    final body = e.body is Map ? e.body as Map : const {};
    final current = (body['currentStock'] as num?)?.toInt();
    if (e.status >= 500) {
      setState(() => _networkFailed = true);
      _announce(
        '${context.tr('error.network')} ${context.tr('vendor.stock.nothingSaved')}',
      );
      return;
    }
    void notice(String key) => setState(() {
      _notice = key;
      _clientRef = null;
    });
    switch (e.code) {
      case 'stock_changed':
        setState(() {
          if (current != null) _setStock(current);
          _changed = true;
          _clientRef = null;
          _quantity.clear();
        });
        _refocusQuantity = true;
        _announce(context.tr('vendor.stock.changed'));
      case 'insufficient_stock':
        setState(() {
          if (current != null) _setStock(current);
          _clientRef = null;
        });
      case 'variant_required' || 'variant_not_found':
        _variantsChanged();
      case 'expected_stock_required':
        // The count we sent was missing: read it again before a new try.
        notice('vendor.stock.currentUnknown');
        setState(() => _loading = true);
        _refresh();
      case 'invalid_direction':
        setState(() => _direction = null);
        notice('vendor.stock.directionMissing');
      case 'note_required':
        setState(() => _noteError = context.tr('vendor.stock.noteMissing'));
      case 'note_too_long':
        setState(() => _noteError = context.tr('vendor.stock.noteTooLong'));
      case 'invalid_quantity':
        setState(
          () => _quantityError = context.tr('vendor.stock.quantityInvalid'),
        );
      case 'invalid_field':
        switch (body['field']) {
          case 'variant':
            _variantsChanged();
          case 'quantity':
            setState(
              () => _quantityError = context.tr('vendor.stock.quantityInvalid'),
            );
          default:
            notice('vendor.stock.retryEntry');
        }
      case 'invalid_client_ref' || 'client_ref_reused' || 'invalid_reason':
        // Nothing was recorded; the next Save is a new entry.
        notice('vendor.stock.retryEntry');
      case 'not_your_product' || 'vendor_permission_forbidden':
        Navigator.of(context).pop(AdjustExit.notAllowed);
      case 'product_not_found':
        Navigator.of(context).pop(AdjustExit.notFound);
      case 'feature_disabled':
        Navigator.of(context).pop(AdjustExit.failed);
      default:
        if (e.status == 403) {
          Navigator.of(context).pop(AdjustExit.notAllowed);
          return;
        }
        setState(() {
          _saveFailed = true;
          _clientRef = null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final variants = _variants;
    final current = _current;
    final kind = _kind;
    final name = widget.product['name']?.toString() ?? '';
    return PopScope(
      canPop: !_busy,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: name,
              excludeSemantics: true,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            if (_changed) ...[
              Semantics(
                liveRegion: true,
                child: FFAlert(
                  key: const Key('adjust-changed'),
                  message: context.tr('vendor.stock.changed'),
                  tone: FFAlertTone.warning,
                ),
              ),
              const SizedBox(height: FFTokens.spacingSm),
            ],
            if (_networkFailed) ...[
              Semantics(
                liveRegion: true,
                child: FFAlert(
                  key: const Key('adjust-network'),
                  message:
                      '${context.tr('error.network')} ${context.tr('vendor.stock.nothingSaved')}',
                  tone: FFAlertTone.error,
                ),
              ),
              const SizedBox(height: FFTokens.spacingSm),
            ],
            if (_notice != null) ...[
              Semantics(
                liveRegion: true,
                child: FFAlert(
                  key: const Key('adjust-notice'),
                  message: context.tr(_notice!),
                  tone: FFAlertTone.warning,
                ),
              ),
              const SizedBox(height: FFTokens.spacingSm),
            ],
            if (_saveFailed) ...[
              FFAlert(
                key: const Key('adjust-failed'),
                message:
                    '${context.tr('vendor.saveFailed')} ${context.tr('vendor.stock.nothingSaved')}',
                tone: FFAlertTone.error,
              ),
              const SizedBox(height: FFTokens.spacingSm),
            ],
            if (variants.isNotEmpty)
              FFDropdownField<String>(
                key: const Key('adjust-variant'),
                value: _variant,
                isExpanded: true,
                label: context.tr('vendor.stock.variantLabel'),
                items: [
                  for (final v in variants)
                    DropdownMenuItem(
                      value: v.name,
                      child: Text(
                        '${v.name} · ${formatStock(v.stock)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy
                    ? (_) {}
                    : (value) {
                        _variant = value;
                        _edited();
                      },
              ),
            if (variants.isNotEmpty && _variant == null)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                child: Text(
                  context.tr('vendor.stock.pickVariant'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (current != null || _loading) ...[
              const SizedBox(height: FFTokens.spacingMd),
              Text(
                context.tr('vendor.stock.current'),
                style: theme.textTheme.labelMedium,
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: FFTokens.spacingSm),
                  child: FFSkeletonLine(widthFactor: 0.3, height: 24),
                )
              else
                Text(
                  formatStock(current!),
                  key: const Key('adjust-current'),
                  style: theme.textTheme.titleLarge,
                ),
            ],
            const SizedBox(height: FFTokens.spacingMd),
            Text(
              context.tr('vendor.stock.reasonLabel'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Wrap(
              spacing: FFTokens.spacingSm,
              runSpacing: FFTokens.spacingXs,
              children: [
                for (final reason in adjustReasons)
                  Semantics(
                    inMutuallyExclusiveGroup: true,
                    child: FFPill(
                      key: Key('adjust-reason-$reason'),
                      label: context.tr('vendor.stock.reason.$reason'),
                      filled: _reason == reason,
                      // Always tappable (keeps its size while saving);
                      // ignored while a save is in flight.
                      onTap: () {
                        if (_busy) return;
                        final wasCount = _reason == 'count';
                        // A new reason is a new entry: start the number over.
                        if (reason != _reason) _quantity.clear();
                        _reason = reason;
                        _noteError = null;
                        _edited();
                        if (reason == 'count' && !wasCount) {
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _quantityFocus.requestFocus(),
                          );
                        }
                      },
                    ),
                  ),
              ],
            ),
            if (_purchasesHint &&
                (_reason == null || inReasons.contains(_reason)))
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                child: Column(
                  key: const Key('adjust-purchases-hint'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('vendor.purchases.adjustHint'),
                      style: theme.textTheme.bodySmall,
                    ),
                    FFButton(
                      key: const Key('adjust-receive-stock'),
                      label: context.tr('vendor.purchases.receive'),
                      icon: Icons.local_shipping_outlined,
                      variant: FFButtonVariant.ghost,
                      visualDensity: VisualDensity.standard,
                      onPressed: _busy
                          ? null
                          : () {
                              final router = GoRouter.of(context);
                              Navigator.of(context).pop();
                              router.push('/vendor/purchases/receive');
                            },
                    ),
                  ],
                ),
              ),
            if (_reason == 'other') ...[
              const SizedBox(height: FFTokens.spacingSm),
              Text(
                context.tr('vendor.stock.direction'),
                style: theme.textTheme.titleSmall,
              ),
              Wrap(
                spacing: FFTokens.spacingSm,
                runSpacing: FFTokens.spacingXs,
                children: [
                  for (final (dir, key) in [
                    ('in', 'vendor.stock.add'),
                    ('out', 'vendor.stock.remove'),
                  ])
                    Semantics(
                      inMutuallyExclusiveGroup: true,
                      child: FFPill(
                        key: Key('adjust-direction-$dir'),
                        label: context.tr(key),
                        filled: _direction == dir,
                        onTap: () {
                          if (_busy) return;
                          _direction = dir;
                          _edited();
                        },
                      ),
                    ),
                ],
              ),
            ],
            if (kind != null) ...[
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                key: const Key('adjust-quantity'),
                controller: _quantity,
                focusNode: _quantityFocus,
                enabled: !_busy,
                autofocus: _reason == 'count',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                label: context.tr(switch (kind) {
                  'count' => 'vendor.stock.counted',
                  'in' => 'vendor.stock.quantityIn',
                  _ => 'vendor.stock.quantityOut',
                }),
                errorText:
                    _quantityError ??
                    (_insufficient
                        ? fillIn(context.tr('vendor.stock.insufficient'), {
                            'n': formatStock(current ?? 0),
                          })
                        : null),
                onChanged: (_) => _edited(),
              ),
              _preview(context, kind, current),
              if (_barcodes && kind == 'count') ...[
                const SizedBox(height: FFTokens.spacingXs),
                if (_countScanOpen)
                  VendorScanPanel(
                    key: const Key('adjust-count-panel'),
                    controller: _countScan,
                    memoryScope: vendorScanScope(context),
                    onCode: _onCountCode,
                    onClose: () => setState(() {
                      _countScanOpen = false;
                      _countNotice = null;
                    }),
                    result: ScanResultRow(
                      notice: _countNotice,
                      onMore: _busy ? null : () => _countBy(1),
                      onLess: _busy ? null : () => _countBy(-1),
                    ),
                  )
                else
                  FFButton(
                    key: const Key('adjust-count-scan'),
                    label: context.tr('vendor.scan.countByScan'),
                    icon: Icons.qr_code_scanner,
                    variant: FFButtonVariant.ghost,
                    fullWidth: true,
                    visualDensity: VisualDensity.standard,
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _countScanUsed = true;
                            _countScanOpen = true;
                          }),
                  ),
              ],
            ],
            const SizedBox(height: FFTokens.spacingSm),
            FFTextField(
              key: const Key('adjust-note'),
              controller: _note,
              enabled: !_busy,
              minLines: 2,
              maxLines: 4,
              maxLength: 200,
              label: context.tr(
                _reason == 'other'
                    ? 'vendor.stock.noteRequired'
                    : 'vendor.stock.note',
              ),
              errorText: _noteError,
              onChanged: (_) => _edited(),
            ),
            const SizedBox(height: FFTokens.spacingMd),
            FFButton(
              key: const Key('adjust-save'),
              visualDensity: VisualDensity.standard,
              label: context.tr(
                _networkFailed
                    ? 'common.retry'
                    : _reason == 'count'
                    ? 'vendor.stock.saveCount'
                    : 'vendor.stock.save',
              ),
              loading: _busy,
              fullWidth: true,
              onPressed: _canSave ? _save : null,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            FFButton(
              key: const Key('adjust-cancel'),
              visualDensity: VisualDensity.standard,
              label: context.tr('common.cancel'),
              variant: FFButtonVariant.ghost,
              fullWidth: true,
              onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(BuildContext context, String kind, int? current) {
    final q = _qty;
    String? text;
    if (q != null && current != null && _quantityValid) {
      if (kind == 'count') {
        final delta = q - current;
        text = delta == 0
            ? context.tr('vendor.stock.noDifference')
            : fillIn(context.tr('vendor.stock.difference'), {
                'delta': formatDelta(delta),
              });
      } else if (!_insufficient) {
        final after = kind == 'in' ? current + q : current - q;
        text = fillIn(context.tr('vendor.stock.after'), {
          'n': formatStock(after),
        });
      }
    }
    return Semantics(
      container: true,
      liveRegion: true,
      label: text ?? '',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: FFTokens.spacingXs),
        child: Text(
          text ?? '',
          key: const Key('adjust-preview'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
