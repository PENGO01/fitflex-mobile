// Vendor reports · S6: Download (spec §9.5, §10.3). One sheet lists
// "Summary (PDF)" and one "{section} (CSV)" per section this person may
// see; the server filters columns by the same rights (§10.1), so a file
// never holds more than the screen.
//
// Files go out the S5 way (DocumentActions): Android hands them to the
// system share sheet; Flutter web downloads both the CSV and the PDF with
// the server's file name (a blob and an anchor with download=; UAT D4: the
// PDF no longer opens in a new tab). Nothing is kept on
// the device. Tests replace DocumentActions; nothing here talks to a real
// server.
import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../documents/document_share_sheet.dart' show DocumentActions;
import '../stock/stock_options.dart' show eatDay, eatToday, fillIn;
import 'report_models.dart';
import 'report_period.dart';
import 'report_widgets.dart';

/// What to download: the period and filters of the screen it was opened on.
class ReportExportRequest {
  const ReportExportRequest({
    required this.period,
    this.channel = 'all',
    this.groupBy,
    this.sort,
    this.q,
    this.businessName,
  });

  final ReportPeriod period;
  final String channel;
  final ReportGroupBy? groupBy;

  /// Products: revenue | units | slow.
  final String? sort;

  /// Products: the search on screen, sent with the CSV (as the portal does).
  final String? q;

  /// The business name, for a file name the server did not give. Null:
  /// asked from the profile, else the person's display name.
  final String? businessName;

  /// The query for [section] (null: the PDF summary).
  Map<String, String?> queryFor(ReportSection? section) => {
    if (section == null || section.usesPeriod) ...{
      'from': period.fromParam,
      'to': period.toParam,
    },
    if (section == null || section.usesChannel) 'channel': channel,
    if (section != null && section.usesGrouping && groupBy != null)
      'groupBy': groupByParam(groupBy!),
    if (section == ReportSection.products) ...{'sort': sort, 'q': _q},
  };

  /// The server takes at most 80 characters.
  String? get _q {
    final v = q?.trim() ?? '';
    if (v.isEmpty) return null;
    return v.length > 80 ? v.substring(0, 80) : v;
  }
}

/// The server's file-name slug (vendor-documents.mjs `slug`): letters,
/// digits, `_` and `-` kept, spaces to `-`, lower case, at most 40
/// characters. (The server first decomposes accents; here an accented
/// letter is dropped. Only used when the server sent no name.)
String reportSlug(String? text) {
  final source = (text ?? '').trim().isEmpty ? 'vendor' : text!;
  var s = source
      .replaceAll(RegExp(r'[^A-Za-z0-9_\s-]'), '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_]+'), '-')
      .replaceAll(RegExp(r'-+'), '-');
  if (s.length > 40) s = s.substring(0, 40);
  return s.isEmpty ? 'document' : s;
}

/// The server's rule (vendor-reports.mjs `reportFileName`):
/// `{business-slug}_{section}_{from}_{to}.{ext}`, the end date left out when
/// it is the start date. The PDF summary is `report`; stock value is dated
/// today (it is "as of now").
String reportFallbackFileName({
  required String? businessName,
  required ReportSection? section,
  required ReportPeriod period,
  DateTime? now,
}) {
  final name = section?.api ?? 'report';
  final ext = section == null ? 'pdf' : 'csv';
  final from = section == ReportSection.stock
      ? eatDay(eatToday(now))
      : period.fromParam;
  final to = section == ReportSection.stock ? from : period.toParam;
  return '${reportSlug(businessName)}_${name}_$from${to == from ? '' : '_$to'}.$ext';
}

/// Whole minutes to wait from a 429 `retryAfterSeconds`: rounded up, at
/// least 1.
int retryMinutes(Object? body) {
  final s = body is Map ? body['retryAfterSeconds'] : null;
  final secs = s is num ? s : num.tryParse('$s') ?? 0;
  final m = (secs / 60).ceil();
  return m < 1 ? 1 : m;
}

/// Opens the Download sheet. [sections] are the CSV rows (already filtered
/// by what this person may see); [pdf] adds "Summary (PDF)".
/// [staffDisabled]: the person's access was turned off — nothing can be
/// downloaded (§11).
Future<void> showReportExportSheet(
  BuildContext context, {
  required ReportExportRequest request,
  required List<ReportSection> sections,
  bool pdf = true,
  bool staffDisabled = false,
}) => showFFSheet<void>(
  context,
  title: context.tr('vendor.reports.export'),
  child: ReportExportSheet(
    request: request,
    sections: sections,
    pdf: pdf,
    staffDisabled: staffDisabled,
    hostContext: context,
  ),
);

class ReportExportSheet extends StatefulWidget {
  const ReportExportSheet({
    super.key,
    required this.request,
    required this.sections,
    required this.hostContext,
    this.pdf = true,
    this.staffDisabled = false,
  });

  final ReportExportRequest request;
  final List<ReportSection> sections;
  final bool pdf;
  final bool staffDisabled;

  /// The screen under the sheet: snacks go there once the sheet closes.
  final BuildContext hostContext;

  @override
  State<ReportExportSheet> createState() => _ReportExportSheetState();
}

class _ReportExportSheetState extends State<ReportExportSheet> {
  /// The row being prepared: a section, or 'pdf'.
  String? _busy;
  bool _tooLarge = false;

  void _closeWith(String message, {bool error = true}) {
    final host = widget.hostContext;
    Navigator.of(context).pop();
    if (!host.mounted) return;
    if (error) {
      FFSnack.error(host, message);
    } else {
      FFSnack.success(host, message);
    }
  }

  Future<void> _download(ReportSection? section) async {
    final lang = reportLang(context);
    final api = AppScope.of(context).api;
    final t = context.tr;
    final format = section == null ? 'pdf' : 'csv';
    setState(() {
      _busy = section?.api ?? 'pdf';
      _tooLarge = false;
    });
    try {
      final out = await api.vendorReportFile(
        section?.api ?? 'summary',
        format: format,
        lang: lang,
        query: widget.request.queryFor(section),
      );
      final name =
          out.fileName ??
          reportFallbackFileName(
            businessName: await _businessName(),
            section: section,
            period: widget.request.period,
          );
      final mime = format == 'pdf' ? 'application/pdf' : 'text/csv';
      if (DocumentActions.isWeb()) {
        if (format == 'pdf') {
          // A download with the server's file name, not a new tab (UAT D4).
          await DocumentActions.download(out.bytes, name, mime);
        } else {
          await DocumentActions.download(out.bytes, name, mime);
        }
      } else if (format == 'pdf') {
        await DocumentActions.shareFile(out.bytes, name);
      } else {
        await DocumentActions.shareTypedFile(out.bytes, name, mime);
      }
      if (mounted) _closeWith(t('vendor.reports.exported'), error: false);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 413 || e.code == 'export_too_large') {
        setState(() => _tooLarge = true);
        return;
      }
      if (e.status == 403) {
        _closeWith(t('vendor.reports.noAccess'));
        return;
      }
      if (e.status == 429 || e.code == 'rate_limited') {
        _closeWith(
          fillIn(t('vendor.reports.rateLimited'), {'n': retryMinutes(e.body)}),
        );
        return;
      }
      if (e.code == 'pdf_unavailable') {
        _closeWith(t('vendor.reports.pdfUnavailable'));
        return;
      }
      _closeWith(t('vendor.reports.exportFailed'));
    } catch (_) {
      if (mounted) _closeWith(t('error.network'));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// The business name for a fallback file name: the one the screen knows,
  /// else the profile (quietly; staff may be refused it), else the
  /// person's display name.
  Future<String?> _businessName() async {
    final known = widget.request.businessName?.trim() ?? '';
    if (known.isNotEmpty) return known;
    final scope = AppScope.of(context);
    try {
      final name = (await scope.api.vendorProfile())['businessName']
          ?.toString()
          .trim();
      if (name != null && name.isNotEmpty) return name;
    } catch (_) {
      // Fall back to the display name.
    }
    return scope.auth.user?['displayName']?.toString();
  }

  Widget _row({
    required String id,
    required String label,
    required String format,
    required String sectionWords,
    required VoidCallback onTap,
  }) {
    final busy = _busy == id;
    final enabled = _busy == null && !widget.staffDisabled;
    final period = periodInWords(
      widget.request.period.from,
      widget.request.period.to,
      reportLang(context),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: busy
          ? context.tr('vendor.reports.preparing')
          : fillIn(context.tr('vendor.reports.a11y.exportRow'), {
              'section': sectionWords,
              'format': format,
              'period': period,
            }),
      liveRegion: busy,
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: ListTile(
        key: Key('reports-export-$id'),
        minTileHeight: 56,
        enabled: enabled,
        leading: busy
            ? const SizedBox(width: 24, height: 24, child: FFSpinner())
            : Icon(
                format == 'PDF'
                    ? Icons.picture_as_pdf_outlined
                    : Icons.table_chart_outlined,
              ),
        title: Text(busy ? context.tr('vendor.reports.preparing') : label),
        onTap: enabled ? onTap : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = reportLang(context);
    final language = context.tr('lang.name.$lang');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.staffDisabled)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: FFAlert(
              key: const Key('reports-export-staff-disabled'),
              message: context.tr('vendor.reports.staffDisabled'),
              tone: FFAlertTone.error,
            ),
          ),
        if (_tooLarge)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: Semantics(
              liveRegion: true,
              child: FFAlert(
                key: const Key('reports-export-too-large'),
                message: context.tr('vendor.reports.exportTooLarge'),
                tone: FFAlertTone.warning,
              ),
            ),
          ),
        if (widget.pdf)
          _row(
            id: 'pdf',
            label: context.tr('vendor.reports.exportPdf'),
            format: 'PDF',
            sectionWords: context.tr('vendor.reports.view.overview'),
            onTap: () => _download(null),
          ),
        for (final s in widget.sections)
          _row(
            id: s.api,
            label: fillIn(context.tr('vendor.reports.exportCsv'), {
              'section': context.tr(s.titleKey),
            }),
            format: 'CSV',
            sectionWords: context.tr(s.titleKey),
            onTap: () => _download(s),
          ),
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingSm),
          child: Text(
            fillIn(context.tr('vendor.reports.exportLang'), {
              'language': language,
            }),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
