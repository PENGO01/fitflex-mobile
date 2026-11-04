// Vendor smart import V3: "Import business data" — the list of my imports
// (file, kind, date, rows, status), with a way to start a new one and to
// discard an import that has not started. Imports need the network: there is
// no offline queue, and the page says so when it cannot reach the server.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import 'import_access.dart';
import 'import_errors.dart';
import 'import_models.dart';
import 'import_routes.dart';
import 'import_widgets.dart';

class ImportHistoryPage extends StatefulWidget {
  const ImportHistoryPage({super.key});

  @override
  State<ImportHistoryPage> createState() => _ImportHistoryPageState();
}

class _ImportHistoryPageState extends State<ImportHistoryPage> {
  bool _ready = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  List<ImportBatch> _batches = [];
  String? _cursor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await enterImportRoute(context) == null || !mounted) return;
      setState(() => _ready = true);
      await _load();
    });
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorImports(cursor: more ? _cursor : null);
      if (!mounted) return;
      final page = ImportBatchPage.from(res);
      setState(() {
        _batches = more ? [..._batches, ...page.rows] : page.rows;
        _cursor = page.nextCursor;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _discard(ImportBatch b) async {
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
    try {
      await AppScope.of(context).api.vendorImportDiscard(b.id);
      if (!mounted) return;
      FFSnack.success(context, t('vendor.import.discarded'));
    } catch (e) {
      if (!mounted) return;
      FFSnack.error(
        context,
        importErrorText(e, lang: importLang(context), t: context.tr),
      );
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    return Scaffold(
      appBar: AppBar(title: Text(t('vendor.import.title'))),
      body: !_ready
          ? const Center(child: FFSpinner())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: _content(),
              ),
            ),
    );
  }

  List<Widget> _content() {
    final t = context.tr;
    final newImport = Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      child: importButton(
        key: const Key('import-new'),
        label: t('vendor.import.new'),
        icon: Icons.add,
        onPressed: () => context.push(vendorImportNewRoute),
      ),
    );
    if (_loading && _batches.isEmpty) {
      return [
        newImport,
        FFSkeletonList(semanticLabel: t('vendor.import.loading')),
      ];
    }
    if (_error != null && _batches.isEmpty) {
      return [
        newImport,
        FFErrorState(
          key: const Key('import-history-error'),
          message: importErrorText(
            _error!,
            lang: importLang(context),
            t: context.tr,
          ),
          onRetry: _load,
        ),
      ];
    }
    return [
      newImport,
      if (_batches.isEmpty)
        FFEmptyState(
          key: const Key('import-history-empty'),
          icon: Icons.upload_file_outlined,
          title: t('vendor.import.empty.title'),
          body: t('vendor.import.empty.body'),
        )
      else
        for (final b in _batches) _row(b),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFAlert(
            message: importErrorText(
              _error!,
              lang: importLang(context),
              t: context.tr,
            ),
            tone: FFAlertTone.error,
          ),
        ),
      if (_cursor != null)
        importButton(
          key: const Key('import-history-more'),
          label: t('vendor.import.more'),
          variant: FFButtonVariant.secondary,
          loading: _loadingMore,
          onPressed: _loadingMore ? null : () => _load(more: true),
        ),
    ];
  }

  Widget _row(ImportBatch b) {
    final theme = Theme.of(context);
    final t = context.tr;
    final lang = importLang(context);
    final date = formatDate(b.createdAt, locale: lang, fallback: '');
    final entity = importEntityLabel(context, b.entity);
    final rows = t(
      'vendor.import.rowsTotal',
    ).replaceAll('{n}', '${b.counts?.total ?? 0}');
    final status = importStatusLabel(context, b.status);
    final name = b.filename.isEmpty ? t('vendor.import.noName') : b.filename;
    return FFCard(
      key: Key('import-batch-${b.id}'),
      padding: EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              onTap: () => context.push(vendorImportBatchRoute(b.id)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingMd),
                  child: Semantics(
                    button: true,
                    container: true,
                    excludeSemantics: true,
                    label: [
                      name,
                      entity,
                      date,
                      rows,
                      status,
                    ].where((s) => s.isNotEmpty).join(', '),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                        const SizedBox(height: FFTokens.spacingXs),
                        Text(
                          [entity, date].where((s) => s.isNotEmpty).join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(rows, style: theme.textTheme.bodySmall),
                        const SizedBox(height: FFTokens.spacingSm),
                        ImportStatusBadge(status: b.status),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (b.canDiscard)
            IconButton(
              key: Key('import-discard-${b.id}'),
              tooltip: t('vendor.import.discard'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _discard(b),
            ),
        ],
      ),
    );
  }
}
