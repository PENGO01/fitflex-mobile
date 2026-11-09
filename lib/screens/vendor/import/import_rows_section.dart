// Vendor smart import V3: the rows that need attention, read from
// GET /vendor/imports/:id/preview (problem rows come first). One small page
// at a time, with "Show more". After an apply, a "Failed rows" filter asks
// the server for `applyState=failed`; it is kept only when every row that
// comes back really is failed (an older server ignores the parameter), else
// the filter is hidden and the plain list stays.
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import 'import_errors.dart';
import 'import_models.dart';
import 'import_widgets.dart';

/// A row the vendor should look at: invalid, failed to apply, or needing
/// review and not imported.
bool importRowIsProblem(ImportRow r) =>
    r.status == 'invalid' ||
    r.failed ||
    (r.status == 'needs_review' && r.applyState != 'applied');

class ImportRowsSection extends StatefulWidget {
  const ImportRowsSection({
    super.key,
    required this.batchId,
    required this.version,
    this.offerFailedFilter = false,
    this.failedCount = 0,
  });

  final String batchId;

  /// Changes when the batch moved on: the rows are read again.
  final String version;

  /// After an apply with failed rows: offer "All problems | Failed rows".
  final bool offerFailedFilter;

  /// The server's count of rows that failed to apply. When it is above zero
  /// but no failed row can be listed (a server that cannot filter or order
  /// them), the section says so instead of showing a number with no rows.
  final int failedCount;

  @override
  State<ImportRowsSection> createState() => _ImportRowsSectionState();
}

class _ImportRowsSectionState extends State<ImportRowsSection> {
  static const _pageSize = 20;
  List<ImportRow> _rows = [];
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  bool _failedOnly = false;
  bool _filterUnsupported = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(ImportRowsSection old) {
    super.didUpdateWidget(old);
    if (old.version != widget.version || old.batchId != widget.batchId) {
      _load();
    }
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final res = await AppScope.of(context).api.vendorImportPreview(
        widget.batchId,
        applyState: _failedOnly ? 'failed' : null,
        limit: _pageSize,
        cursor: more ? _cursor : null,
      );
      if (!mounted || generation != _generation) return;
      final page = ImportRowsPage.from(res);
      if (_failedOnly && page.rows.any((r) => !r.failed)) {
        // The server did not filter: hide the filter, show the plain list.
        setState(() {
          _filterUnsupported = true;
          _failedOnly = false;
        });
        await _load();
        return;
      }
      setState(() {
        _rows = more ? [..._rows, ...page.rows] : page.rows;
        _cursor = page.nextCursor;
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _setFailedOnly(bool value) {
    if (_failedOnly == value) return;
    setState(() => _failedOnly = value);
    _load();
  }

  List<ImportRow> get _shown =>
      _failedOnly ? _rows : _rows.where(importRowIsProblem).toList();

  /// Problem rows come first, in bands: invalid, failed, needs review, then
  /// the plain valid rows. A page is therefore worth asking for while no
  /// plain valid row has been seen yet. Applied rows that needed review
  /// share a band with pending ones, so they never end the paging, and a
  /// pending needs-review row is never hidden behind them. An older server
  /// that buries failed rows among the valid ones stops at the first valid
  /// row (the safe behaviour: nothing is guessed about what comes after).
  bool get _canShowMore =>
      _cursor != null &&
      (_failedOnly || !_rows.any((r) => r.status == 'valid' && !r.failed));

  /// Failed rows exist but none is listed and none can still be loaded.
  bool get _failedHidden =>
      widget.failedCount > 0 &&
      !_failedOnly &&
      !_loading &&
      _error == null &&
      !_canShowMore &&
      !_shown.any((r) => r.failed);

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final filter = widget.offerFailedFilter && !_filterUnsupported;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (filter)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Wrap(
              spacing: FFTokens.spacingSm,
              runSpacing: FFTokens.spacingSm,
              children: [
                FFFilterChip(
                  key: const Key('import-rows-all'),
                  label: t('vendor.import.rows.all'),
                  selected: !_failedOnly,
                  onSelected: () => _setFailedOnly(false),
                ),
                FFFilterChip(
                  key: const Key('import-rows-failed'),
                  label: t('vendor.import.rows.failed'),
                  selected: _failedOnly,
                  onSelected: () => _setFailedOnly(true),
                ),
              ],
            ),
          ),
        if (_loading && _rows.isEmpty)
          FFSkeletonList(
            count: 2,
            semanticLabel: t('vendor.import.rows.loading'),
          )
        else if (_error != null && _rows.isEmpty)
          FFErrorState(
            key: const Key('import-rows-error'),
            message: importErrorText(
              _error!,
              lang: importLang(context),
              t: context.tr,
            ),
            onRetry: _load,
          )
        else if (_shown.isEmpty && !_failedHidden)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Text(
              t('vendor.import.rows.none'),
              key: const Key('import-rows-none'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          for (final r in _shown) ImportRowTile(row: r),
        if (_failedHidden)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: FFAlert(
              key: const Key('import-failed-hidden'),
              message: t('vendor.import.rows.failedHidden'),
              tone: FFAlertTone.warning,
            ),
          ),
        if (_canShowMore)
          importButton(
            key: const Key('import-rows-more'),
            label: t('vendor.import.rows.more'),
            variant: FFButtonVariant.secondary,
            loading: _loadingMore,
            onPressed: _loadingMore ? null : () => _load(more: true),
          ),
      ],
    );
  }
}
