// Vendor smart import V3: one import. What it shows follows the batch's
// status from the server:
//  - mapping_required: a file column needs a person to confirm its match.
//    Mobile does not edit mappings; it explains "continue on a computer".
//  - ready: counts, the rows with problems, the "also import rows that need
//    review" choice (off by default, fixed at the first apply), Apply.
//  - applying / ready with progress: continue where it stopped.
//  - applied / partial: the result, retry for failed rows, errors.csv.
//  - discarded.
// Applying repeats POST /apply until nothing remains (see driveApply) and
// waits out a busy server. Imported products arrive PAUSED and waiting for
// FitFlex approval; the vendor restores them in Products to publish.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/network/browser_online.dart';
import 'import_access.dart';
import 'import_apply.dart';
import 'import_errors.dart';
import 'import_models.dart';
import 'import_routes.dart';
import 'import_rows_section.dart';
import 'import_widgets.dart';

/// Tuning of the apply loop's waits; tests make them instant.
class ImportRunConfig {
  const ImportRunConfig({
    this.sleep,
    this.maxWaits = 5,
    this.baseDelay = const Duration(milliseconds: 1500),
  });
  final Future<void> Function(Duration)? sleep;
  final int maxWaits;
  final Duration baseDelay;
}

class ImportBatchPage extends StatefulWidget {
  const ImportBatchPage({
    super.key,
    required this.batchId,
    this.runConfig = const ImportRunConfig(),
    this.gateway,
  });

  final String batchId;
  final ImportRunConfig runConfig;

  /// The apply loop's server access; tests replace it.
  final ImportGateway? gateway;

  @override
  State<ImportBatchPage> createState() => _ImportBatchPageState();
}

class _ImportBatchPageState extends State<ImportBatchPage> {
  ImportAccess? _access;
  ImportDetail? _detail;
  bool _loading = true;
  Object? _error;

  bool _running = false;

  /// The run started from a batch nobody had worked on yet: the page keeps
  /// showing the first view (counts, choice) while the status moves.
  bool _runFromFresh = false;

  /// The status the run started from: the page keeps that view while the
  /// status moves under it (a retry from the result stays on the result).
  BatchStatus _runStartStatus = BatchStatus.unknown;
  ImportPause? _pause;
  String? _runError;
  bool _expired = false;
  bool _include = false;
  bool _csvBusy = false;
  bool _discarding = false;

  String get _lang => importLang(context);
  ImportBatch? get _batch => _detail?.batch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final access = await enterImportRoute(context);
      if (access == null || !mounted) return;
      setState(() => _access = access);
      await _load();
    });
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final detail = ImportDetail.from(
        await AppScope.of(context).api.vendorImport(widget.batchId),
      );
      if (!mounted) return;
      if (detail == null) throw StateError('no batch');
      setState(() {
        _detail = detail;
        _error = null;
      });
    } catch (e) {
      if (mounted && !quiet) setState(() => _error = e);
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  bool get _readOnly {
    final b = _batch;
    return b != null &&
        b.entity != null &&
        !canImportEntity(b.entity!, isOwner: _access?.isOwner ?? false);
  }

  /// A batch nobody has worked on: the check view.
  bool get _fresh {
    final b = _batch;
    if (b == null) return false;
    return b.status == BatchStatus.ready && !b.hasProgress;
  }

  Future<void> _run(ApplyStart first) async {
    final b = _batch;
    if (b == null || _running || _readOnly) return;
    if (!BrowserOnline.instance.value) {
      setState(() => _runError = context.tr('vendor.import.offline'));
      return;
    }
    final include = b.includeNeedsReview ?? _include;
    setState(() {
      _running = true;
      _runFromFresh = _fresh;
      _runStartStatus = _fresh ? BatchStatus.ready : b.status;
      _pause = null;
      _runError = null;
      _expired = false;
    });
    final outcome = await driveApply(
      gateway: widget.gateway ?? ApiImportGateway(AppScope.of(context).api),
      id: b.id,
      includeNeedsReview: include,
      first: first,
      onProgress: (batch, remaining) {
        if (mounted) _adopt(batch);
      },
      shouldStop: () => !mounted,
      sleep: widget.runConfig.sleep,
      maxWaits: widget.runConfig.maxWaits,
      baseDelay: widget.runConfig.baseDelay,
    );
    if (!mounted) return;
    setState(() => _running = false);
    switch (outcome) {
      case ApplyDone(:final batch):
        _adopt(batch);
      case ApplyPaused(:final reason, :final batch):
        if (batch != null) _adopt(batch);
        setState(() => _pause = reason);
      case ApplyFailed(:final error):
        setState(() {
          _expired = importErrorCode(error) == 'batch_expired';
          _runError = importErrorText(error, lang: _lang, t: context.tr);
        });
        // Whatever the refusal, show the batch as the server has it now.
        await _load(quiet: true);
    }
  }

  void _adopt(ImportBatch batch) => setState(
    () => _detail = ImportDetail(
      batch: batch,
      columns: _detail?.columns ?? const [],
    ),
  );

  Future<void> _discard() async {
    final b = _batch;
    if (b == null || _discarding) return;
    final t = context.tr;
    final ok = await showFFConfirmDialog(
      context,
      title: t('vendor.import.discard.title'),
      message: t('vendor.import.discard.body'),
      confirmLabel: t('vendor.import.discard.confirm'),
      cancelLabel: t('vendor.import.discard.cancel'),
      destructive: true,
      confirmKey: const Key('import-discard-confirm'),
    );
    if (!ok || !mounted) return;
    setState(() => _discarding = true);
    try {
      await AppScope.of(context).api.vendorImportDiscard(b.id);
      if (!mounted) return;
      FFSnack.success(context, t('vendor.import.discarded'));
      context.go(vendorImportRoute);
    } catch (e) {
      if (!mounted) return;
      FFSnack.error(context, importErrorText(e, lang: _lang, t: context.tr));
      // Rows were tried meanwhile: the batch is no longer throw-away.
      await _load(quiet: true);
    } finally {
      if (mounted) setState(() => _discarding = false);
    }
  }

  Future<void> _downloadErrors() async {
    final b = _batch;
    if (b == null || _csvBusy) return;
    if (!BrowserOnline.instance.value) {
      FFSnack.error(context, context.tr('vendor.import.offline'));
      return;
    }
    setState(() => _csvBusy = true);
    try {
      final out = await AppScope.of(context).api.vendorImportErrorsCsv(b.id);
      await deliverImportCsv(
        out.bytes,
        out.fileName ?? 'import-${b.id}-errors.csv',
      );
    } catch (e) {
      if (mounted) {
        FFSnack.error(context, importErrorText(e, lang: _lang, t: context.tr));
      }
    } finally {
      if (mounted) setState(() => _csvBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    return Scaffold(
      appBar: AppBar(title: Text(t('vendor.import.batch.title'))),
      body: _access == null || (_loading && _detail == null)
          ? const Center(child: FFSpinner())
          : RefreshIndicator(
              onRefresh: () => _load(quiet: _detail != null),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _content(),
                ),
              ),
            ),
    );
  }

  List<Widget> _content() {
    final t = context.tr;
    final b = _batch;
    if (b == null) {
      return [
        FFErrorState(
          key: const Key('import-batch-error'),
          message: _error == null
              ? t('vendor.import.err.generic')
              : importErrorText(_error!, lang: _lang, t: context.tr),
          onRetry: _load,
        ),
      ];
    }
    final view = _running ? _runStartStatus : b.status;
    return [
      _header(b),
      const SizedBox(height: FFTokens.spacingMd),
      if (_readOnly)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
          child: FFAlert(
            key: const Key('import-owner-only'),
            message: t('vendor.import.profileOwnerOnly'),
          ),
        ),
      ...switch (view) {
        BatchStatus.mappingRequired => _mapping(b),
        BatchStatus.ready || BatchStatus.applying => _work(b),
        BatchStatus.applied || BatchStatus.partial => _result(b),
        BatchStatus.discarded => _discarded(),
        BatchStatus.unknown => [
          FFAlert(
            key: const Key('import-unknown-status'),
            message: t('vendor.import.status.unknownBody'),
            tone: FFAlertTone.warning,
          ),
        ],
      },
    ];
  }

  Widget _header(ImportBatch b) {
    final theme = Theme.of(context);
    final t = context.tr;
    final date = formatDate(b.createdAt, locale: _lang, fallback: '');
    return FFCard(
      key: const Key('import-header'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            b.filename.isEmpty ? t('vendor.import.noName') : b.filename,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            [
              importEntityLabel(context, b.entity),
              date,
            ].where((s) => s.isNotEmpty).join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: FFTokens.spacingSm),
          ImportStatusBadge(status: b.status),
        ],
      ),
    );
  }

  // ── mapping_required ────────────────────────────────────────────────────

  List<Widget> _mapping(ImportBatch b) {
    final t = context.tr;
    final theme = Theme.of(context);
    final columns = _detail?.columns ?? const [];
    return [
      FFAlert(
        key: const Key('import-mapping-required'),
        tone: FFAlertTone.warning,
        message:
            '${t('vendor.import.mapping.title')}\n${t('vendor.import.mapping.body')}',
      ),
      if (columns.isNotEmpty) ...[
        const SizedBox(height: FFTokens.spacingMd),
        Semantics(
          header: true,
          child: Text(
            t('vendor.import.mapping.columns'),
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        for (final (i, c) in columns.indexed) _columnTile(i, c),
      ],
      const SizedBox(height: FFTokens.spacingMd),
      if (b.canDiscard) _discardButton(),
    ];
  }

  Widget _columnTile(int i, ImportColumn c) {
    final theme = Theme.of(context);
    final t = context.tr;
    final field = c.field == null
        ? t('vendor.import.mapping.unused')
        : t(
            'vendor.import.mapping.feeds',
          ).replaceAll('{field}', importFieldLabel(context, c.field!));
    final match = t('vendor.import.match.${c.match}');
    final sample = c.sample.isEmpty ? null : c.sample.first;
    return FFCard(
      key: Key('import-column-$i'),
      child: Semantics(
        container: true,
        excludeSemantics: true,
        label: [c.source, field, match, ?sample].join('. '),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.source, style: theme.textTheme.titleSmall),
            Text(field, style: theme.textTheme.bodyMedium),
            const SizedBox(height: FFTokens.spacingXs),
            FFBadge(
              label: match,
              tone: switch (c.match) {
                'exact' => FFBadgeTone.success,
                'synonym' => FFBadgeTone.info,
                'fuzzy' => FFBadgeTone.warning,
                _ => FFBadgeTone.gray,
              },
              wrap: true,
            ),
            if (sample != null)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                child: Text(sample, style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }

  // ── ready / applying ───────────────────────────────────────────────────

  List<Widget> _work(ImportBatch b) {
    final t = context.tr;
    final theme = Theme.of(context);
    final c = b.counts ?? const ImportCounts();
    final fixed = b.includeNeedsReview != null;
    final include = fixed ? b.includes : _include;
    final resuming = !(_fresh || (_running && _runFromFresh));
    final eligible = c.eligible(include);
    final waiting = (eligible - c.applied - c.failed).clamp(0, 1 << 30);
    final noteKey = switch (b.entity) {
      ImportEntity.inventory => 'vendor.import.confirm.inventory',
      ImportEntity.profile => 'vendor.import.confirm.profile',
      _ => 'vendor.import.confirm.products',
    };
    return [
      if (!resuming) ...[
        ImportCountsGrid(
          keyPrefix: 'import-count',
          items: [
            (t('vendor.import.count.valid'), c.valid),
            (t('vendor.import.count.needs_review'), c.needsReview),
            (t('vendor.import.count.invalid'), c.invalid),
            (t('vendor.import.count.total'), c.total),
          ],
        ),
        if (c.valid == 0 && c.needsReview == 0)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingMd),
            child: FFAlert(
              key: const Key('import-nothing-ready'),
              message: t('vendor.import.check.nothingReady'),
              tone: FFAlertTone.warning,
            ),
          ),
        if (c.invalid + c.needsReview > 0) ...[
          const SizedBox(height: FFTokens.spacingMd),
          Semantics(
            header: true,
            child: Text(
              t('vendor.import.rows.title'),
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          ImportRowsSection(batchId: b.id, version: b.version),
          _errorsButton(),
        ],
        const SizedBox(height: FFTokens.spacingMd),
      ] else ...[
        FFAlert(
          key: const Key('import-resume'),
          message: t('vendor.import.continue.body'),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        ImportCountsGrid(
          keyPrefix: 'import-count',
          items: [
            (t('vendor.import.continue.imported'), c.applied),
            (t('vendor.import.continue.failed'), c.failed),
            (t('vendor.import.continue.waiting'), waiting),
          ],
        ),
        const SizedBox(height: FFTokens.spacingMd),
      ],
      Text(
        t('vendor.import.confirm.summary').replaceAll('{n}', '$eligible'),
        key: const Key('import-summary'),
        style: theme.textTheme.titleSmall,
      ),
      if (!resuming && c.needsReview > 0) ...[
        const SizedBox(height: FFTokens.spacingSm),
        if (fixed)
          Text(
            t(
              include
                  ? 'vendor.import.confirm.includeFixed'
                  : 'vendor.import.confirm.excludeFixed',
            ),
            style: theme.textTheme.bodySmall,
          )
        else
          SwitchListTile(
            key: const Key('import-include-review'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              t(
                'vendor.import.confirm.includeReview',
              ).replaceAll('{n}', '${c.needsReview}'),
            ),
            subtitle: Text(t('vendor.import.confirm.includeReviewHint')),
            value: _include,
            onChanged: _running || _readOnly
                ? null
                : (v) => setState(() => _include = v),
          ),
      ],
      const SizedBox(height: FFTokens.spacingSm),
      FFAlert(key: const Key('import-confirm-note'), message: t(noteKey)),
      const SizedBox(height: FFTokens.spacingMd),
      ..._runStatus(b, eligible),
      importButton(
        key: const Key('import-apply'),
        label: t(
          _running
              ? 'vendor.import.confirm.starting'
              : resuming || _pause != null
              ? 'vendor.import.confirm.continue'
              : 'vendor.import.confirm.start',
        ),
        icon: Icons.play_arrow_outlined,
        loading: _running,
        onPressed: _running || _readOnly || (!resuming && eligible == 0)
            ? null
            : () => _run(ApplyStart.apply),
      ),
      if (resuming && c.failed > 0 && !_running) ...[
        const SizedBox(height: FFTokens.spacingSm),
        importButton(
          key: const Key('import-retry'),
          label: t('vendor.import.continue.retry'),
          variant: FFButtonVariant.secondary,
          onPressed: _readOnly ? null : () => _run(ApplyStart.retry),
        ),
      ],
      if (b.canDiscard && !_running) ...[
        const SizedBox(height: FFTokens.spacingSm),
        _discardButton(),
      ],
    ];
  }

  /// Progress while running, the waiting message after a pause, a refusal.
  List<Widget> _runStatus(ImportBatch b, int total) {
    final t = context.tr;
    final theme = Theme.of(context);
    final c = b.counts ?? const ImportCounts();
    final done = (c.applied + c.failed).clamp(0, total);
    return [
      if (_running)
        Padding(
          key: const Key('import-progress'),
          padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
          child: Semantics(
            liveRegion: true,
            container: true,
            label: t(
              'vendor.import.confirm.progress',
            ).replaceAll('{done}', '$done').replaceAll('{total}', '$total'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('vendor.import.confirm.progress')
                      .replaceAll('{done}', '$done')
                      .replaceAll('{total}', '$total'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: FFTokens.spacingSm),
                LinearProgressIndicator(
                  value: total <= 0 ? null : done / total,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                ),
                const SizedBox(height: FFTokens.spacingSm),
                Text(
                  t('vendor.import.confirm.keepOpen'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      if (_pause != null)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
          child: FFAlert(
            key: const Key('import-paused'),
            message: t('vendor.import.paused.${_pause!.name}'),
          ),
        ),
      if (_runError != null && !_expired)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
          child: FFAlert(
            key: const Key('import-run-error'),
            message: _runError!,
            tone: FFAlertTone.error,
          ),
        ),
    ];
  }

  // ── applied / partial ───────────────────────────────────────────────────

  List<Widget> _result(ImportBatch b) {
    final t = context.tr;
    final theme = Theme.of(context);
    final c = b.counts ?? const ImportCounts();
    final include = b.includes;
    final problems = c.problems(include);
    final noteKey = switch (b.entity) {
      ImportEntity.inventory => 'vendor.import.result.inventory',
      ImportEntity.profile => 'vendor.import.result.profile',
      _ => 'vendor.import.result.products',
    };
    return [
      Semantics(
        header: true,
        liveRegion: true,
        child: Text(
          t(
            b.status == BatchStatus.applied
                ? 'vendor.import.result.applied'
                : 'vendor.import.result.partial',
          ),
          style: theme.textTheme.titleMedium,
        ),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      ImportCountsGrid(
        keyPrefix: 'import-result',
        items: [
          (t('vendor.import.result.imported'), c.applied),
          (t('vendor.import.result.failed'), c.failed),
          (t('vendor.import.result.notImported'), c.notImported(include)),
          (t('vendor.import.result.skipped'), c.skipped),
        ],
      ),
      const SizedBox(height: FFTokens.spacingMd),
      FFAlert(
        key: const Key('import-result-note'),
        message: t(noteKey),
        tone: b.entity == ImportEntity.products
            ? FFAlertTone.warning
            : FFAlertTone.info,
      ),
      const SizedBox(height: FFTokens.spacingMd),
      ..._runStatus(b, c.eligible(include)),
      if (_expired)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
          child: FFAlert(
            key: const Key('import-expired'),
            message: '${t('vendor.import.expired.title')}\n$_runError',
            tone: FFAlertTone.warning,
          ),
        ),
      if (b.entity != ImportEntity.profile)
        importButton(
          key: const Key('import-to-products'),
          label: t('vendor.import.result.viewProducts'),
          icon: Icons.inventory_2_outlined,
          onPressed: () => context.go('/vendor/home?open=products'),
        ),
      if (b.status == BatchStatus.partial &&
          c.failed > 0 &&
          !_expired &&
          !_readOnly) ...[
        const SizedBox(height: FFTokens.spacingSm),
        importButton(
          key: const Key('import-retry'),
          label: t('vendor.import.result.retry'),
          variant: FFButtonVariant.secondary,
          loading: _running,
          onPressed: _running ? null : () => _run(ApplyStart.retry),
        ),
      ],
      if (problems > 0) _errorsButton(),
      const SizedBox(height: FFTokens.spacingSm),
      importButton(
        key: const Key('import-another'),
        label: t('vendor.import.result.newImport'),
        variant: FFButtonVariant.ghost,
        onPressed: () => context.pushReplacement(vendorImportNewRoute),
      ),
      importButton(
        key: const Key('import-back-list'),
        label: t('vendor.import.backToList'),
        variant: FFButtonVariant.ghost,
        onPressed: () => context.go(vendorImportRoute),
      ),
      if (problems > 0) ...[
        const SizedBox(height: FFTokens.spacingMd),
        Semantics(
          header: true,
          child: Text(
            t('vendor.import.result.rowsTitle'),
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        ImportRowsSection(
          batchId: b.id,
          version: b.version,
          offerFailedFilter: c.failed > 0,
        ),
      ],
    ];
  }

  Widget _errorsButton() => Padding(
    padding: const EdgeInsets.only(top: FFTokens.spacingSm),
    child: importButton(
      key: const Key('import-errors-csv'),
      label: context.tr('vendor.import.errorsCsv'),
      icon: Icons.download_outlined,
      variant: FFButtonVariant.secondary,
      loading: _csvBusy,
      onPressed: _csvBusy ? null : _downloadErrors,
    ),
  );

  Widget _discardButton() => importButton(
    key: const Key('import-discard'),
    label: context.tr('vendor.import.discard'),
    icon: Icons.delete_outline,
    variant: FFButtonVariant.ghost,
    loading: _discarding,
    onPressed: _discarding ? null : _discard,
  );

  List<Widget> _discarded() => [
    FFEmptyState(
      key: const Key('import-discarded'),
      icon: Icons.delete_outline,
      title: context.tr('vendor.import.discarded.title'),
      body: context.tr('vendor.import.discarded.body'),
    ),
    const SizedBox(height: FFTokens.spacingMd),
    importButton(
      key: const Key('import-back-list'),
      label: context.tr('vendor.import.backToList'),
      onPressed: () => context.go(vendorImportRoute),
    ),
  ];
}
