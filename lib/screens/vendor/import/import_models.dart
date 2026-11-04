// Vendor smart import V3: what the server answers, read defensively, and the
// rules the screens share (gating, file checks, which state a batch is in).
// Contract: fitflex-functions functions/vendor-imports.mjs and
// docs/design/vendor-import-v1.md. The server parses, matches columns and
// checks rows; the app only uploads, shows the answers and drives the apply
// loop. Nothing here talks to a server.
import '../stock/stock_options.dart' show VendorTools;

/// What a file holds. `profile` is for the account holder only.
enum ImportEntity { products, inventory, profile }

ImportEntity? importEntityOf(Object? v) {
  for (final e in ImportEntity.values) {
    if (e.name == v) return e;
  }
  return null;
}

/// A batch's state on the server.
enum BatchStatus {
  mappingRequired('mapping_required'),
  ready('ready'),
  applying('applying'),
  applied('applied'),
  partial('partial'),
  discarded('discarded'),
  unknown('unknown');

  const BatchStatus(this.wire);
  final String wire;

  static BatchStatus of(Object? v) {
    for (final s in BatchStatus.values) {
      if (s.wire == v && s != unknown) return s;
    }
    return unknown;
  }

  /// Nothing more will be applied (partial can still be retried).
  bool get isTerminal =>
      this == applied || this == partial || this == discarded;
}

int _int(Object? v) => v is num ? v.toInt() : 0;
String? _str(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

List<dynamic> _list(Object? v) => v is List ? v : const [];

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// A message the server sends in both languages.
class LocalText {
  const LocalText({this.en, this.sw});
  final String? en;
  final String? sw;

  static LocalText? from(Object? v) {
    if (v is! Map) return null;
    final t = LocalText(en: _str(v['en']), sw: _str(v['sw']));
    return t.en == null && t.sw == null ? null : t;
  }

  /// The text in [lang], else the other language's rather than nothing.
  String? of(String lang) => lang == 'sw' ? (sw ?? en) : (en ?? sw);
}

class ImportCounts {
  const ImportCounts({
    this.total = 0,
    this.valid = 0,
    this.needsReview = 0,
    this.invalid = 0,
    this.pending = 0,
    this.applied = 0,
    this.failed = 0,
    this.skipped = 0,
  });

  final int total;
  final int valid;
  final int needsReview;
  final int invalid;
  final int pending;
  final int applied;
  final int failed;
  final int skipped;

  static ImportCounts? from(Object? v) {
    if (v is! Map) return null;
    return ImportCounts(
      total: _int(v['total']),
      valid: _int(v['valid']),
      needsReview: _int(v['needs_review']),
      invalid: _int(v['invalid']),
      pending: _int(v['pending']),
      applied: _int(v['applied']),
      failed: _int(v['failed']),
      skipped: _int(v['skipped']),
    );
  }

  /// Rows this batch will try: the valid ones, plus the ones that need
  /// review when the batch includes them.
  int eligible(bool includeNeedsReview) =>
      valid + (includeNeedsReview ? needsReview : 0);

  /// Rows that were not imported and will not be without the vendor's help:
  /// invalid ones, and those needing review that were left out.
  int notImported(bool includeNeedsReview) =>
      invalid + (includeNeedsReview ? 0 : needsReview);

  /// Rows worth listing or exporting: problems, and rows that failed.
  int problems(bool includeNeedsReview) =>
      notImported(includeNeedsReview) + failed;
}

class ImportBatch {
  const ImportBatch({
    required this.id,
    required this.entity,
    required this.status,
    this.filename = '',
    this.sizeBytes = 0,
    this.counts,
    this.includeNeedsReview,
    this.needsConfirmation = false,
    this.missingRequired = const [],
    this.createdAt,
    this.updatedAt,
    this.finishedAt,
  });

  final String id;

  /// Null for a kind this app does not know (shown neutrally).
  final ImportEntity? entity;
  final BatchStatus status;
  final String filename;
  final int sizeBytes;
  final ImportCounts? counts;

  /// Null until the first apply; then fixed for the batch's whole life.
  final bool? includeNeedsReview;
  final bool needsConfirmation;
  final List<String> missingRequired;
  final String? createdAt;
  final String? updatedAt;
  final String? finishedAt;

  static ImportBatch? from(Object? v) {
    if (v is! Map) return null;
    final id = _str(v['id']);
    if (id == null) return null;
    return ImportBatch(
      id: id,
      entity: importEntityOf(v['entity']),
      status: BatchStatus.of(v['status']),
      filename: _str(v['filename']) ?? '',
      sizeBytes: _int(v['sizeBytes']),
      counts: ImportCounts.from(v['counts']),
      includeNeedsReview: v['includeNeedsReview'] is bool
          ? v['includeNeedsReview'] as bool
          : null,
      needsConfirmation: v['needsConfirmation'] == true,
      missingRequired: [
        for (final f in _list(v['missingRequired']))
          if (f is String) f,
      ],
      createdAt: _str(v['createdAt']),
      updatedAt: _str(v['updatedAt']),
      finishedAt: _str(v['finishedAt']),
    );
  }

  /// Whether the apply call should send the needs-review rows too.
  bool get includes => includeNeedsReview == true;

  /// Some rows were applied or failed: the batch is being worked through
  /// (the server refuses mapping edits and discard from here on).
  bool get hasProgress => (counts?.applied ?? 0) + (counts?.failed ?? 0) > 0;

  /// Offered when nothing was tried yet. The server has the last word
  /// (409 `not_discardable`).
  bool get canDiscard =>
      (status == BatchStatus.mappingRequired || status == BatchStatus.ready) &&
      !hasProgress;

  /// Detects a change worth re-reading the rows for.
  String get version =>
      '${status.wire}|$updatedAt|${counts?.applied}|${counts?.failed}';
}

/// One file column and how it was matched.
class ImportColumn {
  const ImportColumn({
    required this.source,
    this.field,
    this.match = 'none',
    this.confirmed = false,
    this.sample = const [],
  });

  final String source;
  final String? field;

  /// `exact` | `synonym` | `fuzzy` | `none`.
  final String match;
  final bool confirmed;
  final List<String> sample;

  static ImportColumn? from(Object? v) {
    if (v is! Map) return null;
    final source = v['source']?.toString();
    if (source == null) return null;
    final match = v['match']?.toString();
    return ImportColumn(
      source: source,
      field: _str(v['field']),
      match: const {'exact', 'synonym', 'fuzzy', 'none'}.contains(match)
          ? match!
          : 'none',
      confirmed: v['confirmed'] == true,
      sample: [for (final s in _list(v['sample'])) ?s?.toString()],
    );
  }
}

class ImportIssue {
  const ImportIssue({
    required this.code,
    this.field,
    this.severity = 'error',
    this.message,
  });

  final String code;
  final String? field;

  /// `error` | `warning` | `info`.
  final String severity;
  final LocalText? message;

  static ImportIssue? from(Object? v) {
    if (v is! Map) return null;
    final code = _str(v['code']);
    if (code == null) return null;
    final sev = v['severity']?.toString();
    return ImportIssue(
      code: code,
      field: _str(v['field']),
      severity: const {'error', 'warning', 'info'}.contains(sev)
          ? sev!
          : 'error',
      message: LocalText.from(v['message']),
    );
  }
}

class ImportRow {
  const ImportRow({
    required this.id,
    required this.rowNo,
    required this.status,
    required this.applyState,
    this.issues = const [],
    this.values = const {},
    this.lastErrorMessage,
    this.hasLastError = false,
  });

  final String id;

  /// 2 is the first data row (the header is row 1).
  final int rowNo;

  /// `valid` | `needs_review` | `invalid`.
  final String status;

  /// `pending` | `applied` | `failed` | `skipped`.
  final String applyState;
  final List<ImportIssue> issues;
  final Map<String, dynamic> values;
  final LocalText? lastErrorMessage;
  final bool hasLastError;

  static ImportRow? from(Object? v) {
    if (v is! Map) return null;
    final id = _str(v['id']);
    if (id == null) return null;
    final lastError = v['lastError'];
    return ImportRow(
      id: id,
      rowNo: _int(v['rowNo']),
      status: _str(v['status']) ?? 'valid',
      applyState: _str(v['applyState']) ?? 'pending',
      issues: [for (final i in _list(v['issues'])) ?ImportIssue.from(i)],
      values: _map(v['values']),
      hasLastError: lastError is Map,
      lastErrorMessage: lastError is Map
          ? LocalText.from(lastError['message'])
          : null,
    );
  }

  bool get failed => applyState == 'failed';

  /// What to call the row: its name, else its SKU, else nothing.
  String? get label =>
      _str(values['name']) ??
      _str(values['businessName']) ??
      _str(values['sku']);
}

/// One page of rows.
class ImportRowsPage {
  const ImportRowsPage({required this.rows, this.nextCursor});
  final List<ImportRow> rows;
  final String? nextCursor;

  static ImportRowsPage from(Map<String, dynamic> json) => ImportRowsPage(
    rows: [for (final r in _list(json['rows'])) ?ImportRow.from(r)],
    nextCursor: _str(json['nextCursor']),
  );
}

class ImportBatchPage {
  const ImportBatchPage({required this.rows, this.nextCursor});
  final List<ImportBatch> rows;
  final String? nextCursor;

  static ImportBatchPage from(Map<String, dynamic> json) => ImportBatchPage(
    rows: [for (final b in _list(json['batches'])) ?ImportBatch.from(b)],
    nextCursor: _str(json['nextCursor']),
  );
}

/// `GET /vendor/imports/:id`.
class ImportDetail {
  const ImportDetail({required this.batch, this.columns = const []});
  final ImportBatch batch;
  final List<ImportColumn> columns;

  static ImportDetail? from(Map<String, dynamic> json) {
    final batch = ImportBatch.from(json['batch']);
    if (batch == null) return null;
    return ImportDetail(
      batch: batch,
      columns: [for (final c in _list(json['columns'])) ?ImportColumn.from(c)],
    );
  }
}

// ── Gating ────────────────────────────────────────────────────────────────

/// The import entry and routes are open only when the server says the tool
/// is on (exactly `true`) AND this person has the staff permission `import`.
/// A missing flag is "off" (fail closed).
bool importOpen(VendorTools tools, {required bool canImport}) =>
    tools.dataImport && canImport;

/// The business profile is written only by the account holder
/// (server: 403 `profile_import_owner_only` for staff, even with `import`).
bool canImportEntity(ImportEntity entity, {required bool isOwner}) =>
    entity != ImportEntity.profile || isOwner;

// ── File checks (before an upload is wasted) ──────────────────────────────

enum ImportFileProblem { empty, tooLarge, spreadsheet }

/// The extension of [name] without the dot, lower case.
String _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// What is wrong with a picked file, or null when it may be uploaded. An
/// Excel file gets its own hint ("save as CSV"); the server also refuses it
/// (415 `unsupported_file_type`).
ImportFileProblem? checkImportFile({
  required String name,
  required int sizeBytes,
  required int maxBytes,
}) {
  final ext = _extension(name);
  if (ext == 'xlsx' || ext == 'xls' || ext == 'xlsm' || ext == 'ods') {
    return ImportFileProblem.spreadsheet;
  }
  if (sizeBytes <= 0) return ImportFileProblem.empty;
  if (sizeBytes > maxBytes) return ImportFileProblem.tooLarge;
  return null;
}

/// "2" for 2 MB, "1.5" for 1.5 MB.
String megabytes(int bytes) {
  final mb = (bytes / (1024 * 1024) * 10).round() / 10;
  return mb == mb.roundToDouble() ? '${mb.round()}' : '$mb';
}

/// The file name without folders (some pickers return a path).
String importFileName(String name) {
  final i = name.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? name : name.substring(i + 1);
}
