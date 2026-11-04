// Vendor smart import V3: a new import. Choose what is being imported
// (products, stock counts, or the business profile for the account holder),
// get the template if needed, pick a CSV and upload it. The server parses,
// matches columns and checks rows; this screen only checks the file's size
// and kind first to save a wasted upload. Excel files get a "save as CSV"
// hint. Column matching that needs a person's confirmation happens on a
// computer (the batch page says so).
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/network/browser_online.dart';
import '../stock/stock_options.dart' show VendorTools;
import 'import_access.dart';
import 'import_errors.dart';
import 'import_models.dart';
import 'import_routes.dart';
import 'import_widgets.dart';

/// A file the person picked. [read] is called only once the size is fine.
class PickedImportFile {
  const PickedImportFile({
    required this.name,
    required this.size,
    required this.read,
  });
  final String name;
  final int size;
  final Future<Uint8List> Function() read;
}

typedef PickImportFile = Future<PickedImportFile?> Function();

/// The device's file picker (web-safe: the bytes are read through the
/// picker, never a path).
Future<PickedImportFile?> pickImportFileFromDevice() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['csv', 'txt', 'xlsx', 'xls'],
  );
  if (file == null) return null;
  return PickedImportFile(
    name: importFileName(file.name),
    size: await file.length(),
    read: file.readAsBytes,
  );
}

class ImportNewPage extends StatefulWidget {
  const ImportNewPage({super.key, this.pickFile});

  /// The file picker; tests replace it.
  final PickImportFile? pickFile;

  @override
  State<ImportNewPage> createState() => _ImportNewPageState();
}

class _ImportNewPageState extends State<ImportNewPage> {
  ImportAccess? _access;
  ImportEntity? _entity;
  String? _templateLang;
  bool _example = false;
  bool _templateBusy = false;
  PickedImportFile? _file;
  ImportFileProblem? _problem;
  bool _uploading = false;
  String? _error;
  String? _duplicateOf;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final access = await enterImportRoute(context);
      if (access == null || !mounted) return;
      setState(() => _access = access);
    });
  }

  String get _lang => importLang(context);
  int get _maxBytes =>
      _access?.tools.importMaxBytes ?? VendorTools.defaultImportMaxBytes;

  void _choose(ImportEntity e) => setState(() {
    _entity = e;
    _error = null;
    _duplicateOf = null;
  });

  Future<void> _template() async {
    final entity = _entity;
    if (entity == null || _templateBusy) return;
    if (!BrowserOnline.instance.value) {
      setState(() => _error = context.tr('vendor.import.offline'));
      return;
    }
    setState(() {
      _templateBusy = true;
      _error = null;
    });
    final lang = _templateLang ?? _lang;
    try {
      final out = await AppScope.of(context).api.vendorImportTemplate(
        entity: entity.name,
        lang: lang,
        example: _example,
      );
      await deliverImportCsv(
        out.bytes,
        out.fileName ?? 'fitflex-import-${entity.name}-$lang.csv',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = importErrorText(e, lang: _lang, t: context.tr));
      }
    } finally {
      if (mounted) setState(() => _templateBusy = false);
    }
  }

  Future<void> _pick() async {
    final picked = await (widget.pickFile ?? pickImportFileFromDevice)();
    if (picked == null || !mounted) return;
    setState(() {
      _file = picked;
      _problem = checkImportFile(
        name: picked.name,
        sizeBytes: picked.size,
        maxBytes: _maxBytes,
      );
      _error = null;
      _duplicateOf = null;
    });
  }

  Future<void> _upload() async {
    final entity = _entity;
    final file = _file;
    if (entity == null || file == null || _problem != null || _uploading) {
      return;
    }
    if (!BrowserOnline.instance.value) {
      setState(() => _error = context.tr('vendor.import.offline'));
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
      _duplicateOf = null;
    });
    final api = AppScope.of(context).api;
    try {
      final bytes = await file.read();
      final problem = checkImportFile(
        name: file.name,
        sizeBytes: bytes.length,
        maxBytes: _maxBytes,
      );
      if (problem != null) {
        if (mounted) setState(() => _problem = problem);
        return;
      }
      final res = await api.vendorImportUpload(
        entity: entity.name,
        bytes: bytes,
        filename: file.name,
      );
      if (!mounted) return;
      final batch = ImportBatch.from(res['batch']);
      if (batch == null) {
        setState(() => _error = context.tr('vendor.import.err.generic'));
        return;
      }
      context.pushReplacement(vendorImportBatchRoute(batch.id));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = importErrorText(e, lang: _lang, t: context.tr);
        _duplicateOf = importDuplicateBatchId(e);
      });
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _problemText() {
    final t = context.tr;
    return switch (_problem) {
      ImportFileProblem.spreadsheet => t('vendor.import.file.spreadsheet'),
      ImportFileProblem.empty => t('vendor.import.file.empty'),
      ImportFileProblem.tooLarge => t(
        'vendor.import.file.tooLarge',
      ).replaceAll('{mb}', megabytes(_maxBytes)),
      null => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tr;
    final access = _access;
    return Scaffold(
      appBar: AppBar(title: Text(t('vendor.import.new'))),
      body: access == null
          ? const Center(child: FFSpinner())
          // A short, fixed form: every part is built (a lazy list would not
          // build the parts below the fold for assistive tech or tests).
          : SingleChildScrollView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _content(access),
              ),
            ),
    );
  }

  Widget _heading(String key) => Padding(
    padding: const EdgeInsets.only(
      top: FFTokens.spacingMd,
      bottom: FFTokens.spacingSm,
    ),
    child: Semantics(
      header: true,
      child: Text(
        context.tr(key),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
  );

  Widget _entityTile(ImportEntity e, ImportAccess access) {
    final t = context.tr;
    final allowed = canImportEntity(e, isOwner: access.isOwner);
    final tile = FFChoiceTile(
      key: Key('import-entity-${e.name}'),
      title: t('vendor.import.entity.${e.name}'),
      subtitle: allowed
          ? t('vendor.import.entity.${e.name}.hint')
          : t('vendor.import.profileOwnerOnly'),
      selected: _entity == e,
      onSelected: allowed ? () => _choose(e) : () {},
    );
    if (allowed) return tile;
    // Shown but not available: the reason is the subtitle.
    return Semantics(
      enabled: false,
      child: Opacity(opacity: 0.6, child: IgnorePointer(child: tile)),
    );
  }

  List<Widget> _content(ImportAccess access) {
    final t = context.tr;
    final theme = Theme.of(context);
    final maxBytes = access.tools.importMaxBytes;
    final entity = _entity;
    final file = _file;
    return [
      FFAlert(
        key: const Key('import-needs-network'),
        message: t('vendor.import.needsNetwork'),
      ),
      _heading('vendor.import.step.entity'),
      for (final e in ImportEntity.values) ...[
        _entityTile(e, access),
        const SizedBox(height: FFTokens.spacingSm),
      ],
      if (entity != null) ...[
        _heading('vendor.import.step.template'),
        Text(
          t('vendor.import.template.body'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFSegmented(
          key: const Key('import-template-lang'),
          value: _templateLang ?? _lang,
          options: [
            ('en', t('vendor.import.template.english')),
            ('sw', t('vendor.import.template.swahili')),
          ],
          onChanged: (v) => setState(() => _templateLang = v),
        ),
        SwitchListTile(
          key: const Key('import-template-example'),
          contentPadding: EdgeInsets.zero,
          title: Text(t('vendor.import.template.example')),
          value: _example,
          onChanged: (v) => setState(() => _example = v),
        ),
        importButton(
          key: const Key('import-template-download'),
          label: t('vendor.import.template.download'),
          icon: Icons.download_outlined,
          variant: FFButtonVariant.secondary,
          loading: _templateBusy,
          onPressed: _templateBusy ? null : _template,
        ),
        _heading('vendor.import.step.file'),
        Text(
          t('vendor.import.file.hint')
              .replaceAll('{mb}', megabytes(maxBytes))
              .replaceAll('{rows}', '${access.tools.importMaxRows}'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        importButton(
          key: const Key('import-pick'),
          label: t(
            file == null
                ? 'vendor.import.file.pick'
                : 'vendor.import.file.change',
          ),
          icon: Icons.attach_file,
          variant: FFButtonVariant.secondary,
          onPressed: _uploading ? null : _pick,
        ),
        if (file != null)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingSm),
            child: FFCard(
              key: const Key('import-file'),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined),
                  const SizedBox(width: FFTokens.spacingSm),
                  Expanded(
                    child: Text(
                      '${file.name} · ${_size(file.size)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingSm),
            child: FFAlert(
              key: const Key('import-file-problem'),
              message: _problemText(),
              tone: FFAlertTone.error,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingSm),
            child: FFAlert(
              key: const Key('import-error'),
              message: _error!,
              tone: FFAlertTone.error,
            ),
          ),
        if (_duplicateOf != null)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingSm),
            child: importButton(
              key: const Key('import-open-existing'),
              label: t('vendor.import.openExisting'),
              variant: FFButtonVariant.secondary,
              onPressed: () => context.pushReplacement(
                vendorImportBatchRoute(_duplicateOf!),
              ),
            ),
          ),
        const SizedBox(height: FFTokens.spacingMd),
        importButton(
          key: const Key('import-upload'),
          label: t(
            _uploading ? 'vendor.import.uploading' : 'vendor.import.upload',
          ),
          icon: Icons.cloud_upload_outlined,
          loading: _uploading,
          onPressed: file == null || _problem != null || _uploading
              ? null
              : _upload,
        ),
      ],
    ];
  }

  String _size(int bytes) => bytes >= 1024 * 1024
      ? '${megabytes(bytes)} MB'
      : '${(bytes / 1024).ceil()} KB';
}
