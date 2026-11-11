// Vendor tools · sale extras #3 (docs/design/vendor-sale-extras-1110.md §3):
// "Share receipt" as an image (PNG), a PDF or text, all made on the device
// from the same ReceiptData in the receipt's language. Works offline and
// for a sale still queued. No flag (Q-11): it only changes what the
// vendor's own Share button produces, and nothing leaves the device until
// the vendor shares it.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../shared/capture_png.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../documents/document_share_sheet.dart' show DocumentActions;
import '../stock/stock_options.dart' show fillIn;
import 'receipt_data.dart';
import 'receipt_page.dart' show shareReceipt;
import 'receipt_pdf.dart';
import 'sales_widgets.dart';

/// One receipt to make into a file, in one language.
class ReceiptFileJob {
  const ReceiptFileJob({
    required this.data,
    required this.lang,
    required this.t,
    this.tin,
    this.vrn,
  });

  final ReceiptData data;
  final String lang;

  /// i18n lookup in [lang].
  final String Function(String key) t;
  final String? tin;
  final String? vrn;
}

/// The receipt is too tall for one image (§3.4): use the PDF.
class ReceiptTooLongForImage implements Exception {
  const ReceiptTooLongForImage();
}

/// Image limits (§3.4): 360 logical px wide at 3x (1080 px); 2x above
/// 4,000 px tall; no image above 6,000 px (GPU texture limits on low-end
/// phones and on the web).
const receiptImageWidth = 360.0;
const receiptImagePadding = 16.0;
const receiptImageRatioDropAt = 4000.0;
const receiptImageMaxHeight = 6000.0;

/// The pixel ratio for a receipt [height] logical px tall; null: too tall.
double? receiptImagePixelRatio(double height) => height > receiptImageMaxHeight
    ? null
    : height > receiptImageRatioDropAt
    ? 2
    : 3;

/// A cautious guess of the image height before anything is drawn, to
/// disable the Image row for a very long receipt (AC-29). Calibrated on the
/// spec's figure (4,000 px is "about 60 lines", so ~60 px a line), which is
/// above what a plain line measures, so the guess errs towards PDF. The
/// real height is measured again when the image is made.
double estimateReceiptHeight(ReceiptData r) {
  const perLine = 60.0;
  var h = 2 * receiptImagePadding + 330; // header, dividers, footer
  for (final l in r.lines) {
    h += perLine;
    if (l.discountTzs > 0) h += 22;
  }
  h += 22 * r.payments.length;
  h += 22 * r.vatSummary.length;
  if (r.queued) h += 60;
  if (r.credit) h += 70;
  if (r.refundedTzs > 0) h += 48;
  return h;
}

bool receiptTooLongForImage(ReceiptData r) =>
    estimateReceiptHeight(r) > receiptImageMaxHeight;

/// `receipt-R-000123.png`; a queued sale `receipt-pending-20261110-1405.png`
/// (EAT, from its sale time). File names are never translated.
String receiptFileName(ReceiptData r, String ext, {DateTime? now}) {
  final number = r.queued
      ? null
      : (r.credit ? r.invoiceNumber : null) ?? r.number;
  if (number != null && number.isNotEmpty) {
    final safe = number.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    return 'receipt-$safe.$ext';
  }
  final at =
      DateTime.tryParse(r.soldAt ?? '')?.toUtc() ??
      (now ?? DateTime.now()).toUtc();
  final eat = at.add(const Duration(hours: 3));
  String two(int v) => v.toString().padLeft(2, '0');
  return 'receipt-pending-${eat.year}${two(eat.month)}${two(eat.day)}'
      '-${two(eat.hour)}${two(eat.minute)}.$ext';
}

/// The receipt image, drawn off-screen in the light theme on white
/// (§3.4). Replaceable in tests.
Future<Uint8List> renderReceiptImage(
  BuildContext context,
  ReceiptFileJob job,
) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  final key = GlobalKey();
  final entry = OverlayEntry(
    builder: (ctx) => Positioned(
      // Off-screen: drawn, never seen, never touched, never read aloud.
      left: -100000,
      top: 0,
      width: receiptImageWidth,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.noScaling),
            child: Theme(
              data: buildTheme(),
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(receiptImagePadding),
                    child: ReceiptView(
                      data: job.data,
                      t: job.t,
                      lang: job.lang,
                      tin: job.tin,
                      vrn: job.vrn,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) throw StateError('not drawn');
    final ratio = receiptImagePixelRatio(box.size.height);
    if (ratio == null) throw const ReceiptTooLongForImage();
    final png = await capturePng(key, pixelRatio: ratio);
    if (png == null) throw StateError('no image');
    return png;
  } finally {
    entry.remove();
  }
}

/// What the receipt sheet does. Tests replace these; sharing itself goes
/// through [DocumentActions] (share file, download, open PDF, is web).
class ReceiptFileActions {
  ReceiptFileActions._();

  static Future<Uint8List> Function(BuildContext context, ReceiptFileJob job)
  image = renderReceiptImage;

  static Future<Uint8List> Function(ReceiptFileJob job) pdf = (job) =>
      buildReceiptPdf(job.data, job.t, job.lang, tin: job.tin, vrn: job.vrn);

  static DateTime Function() now = DateTime.now;
}

/// How a file share ended.
enum ReceiptFileResult { shared, downloaded }

/// Makes the image and hands it on: the system share sheet (Android), a
/// download (web). Throws on a render or share failure.
Future<ReceiptFileResult> shareReceiptImage(
  BuildContext context,
  ReceiptFileJob job,
) async {
  final png = await ReceiptFileActions.image(context, job);
  final name = receiptFileName(job.data, 'png', now: ReceiptFileActions.now());
  if (DocumentActions.isWeb()) {
    await DocumentActions.download(png, name, 'image/png');
    return ReceiptFileResult.downloaded;
  }
  await DocumentActions.shareTypedFile(png, name, 'image/png');
  return ReceiptFileResult.shared;
}

/// Makes the PDF and hands it on: the system share sheet (Android), a new
/// tab (web), or a download when the tab was blocked.
Future<ReceiptFileResult> shareReceiptPdf(ReceiptFileJob job) async {
  final bytes = await ReceiptFileActions.pdf(job);
  final name = receiptFileName(job.data, 'pdf', now: ReceiptFileActions.now());
  if (DocumentActions.isWeb()) {
    final opened = await DocumentActions.openPdf(bytes, name);
    if (opened) return ReceiptFileResult.shared;
    await DocumentActions.download(bytes, name, 'application/pdf');
    return ReceiptFileResult.downloaded;
  }
  await DocumentActions.shareTypedFile(bytes, name, 'application/pdf');
  return ReceiptFileResult.shared;
}

/// The plain-text subject of a receipt share.
String receiptShareSubject(ReceiptData data, String Function(String) t) => [
  ?data.business,
  if (data.number != null && !data.queued)
    data.credit && data.invoiceNumber != null
        ? '${t('vendor.doc.invoice')} ${data.invoiceNumber}'
        : fillIn(t('vendor.pos.receiptNo'), {'number': data.number}),
].join(' ');

/// The number used in a11y labels: the receipt number, or the queued
/// sale's provisional ref.
String receiptA11yNumber(ReceiptData data) => data.queued || data.number == null
    ? (data.tempRef ?? '')
    : (data.credit && data.invoiceNumber != null
          ? data.invoiceNumber!
          : data.number!);

/// Documents off (§3.2): "Share receipt" with Image, PDF and Share as text.
Future<void> showReceiptShareSheet(
  BuildContext context, {
  required ReceiptData data,
  required String lang,
  String? tin,
  String? vrn,
}) {
  final locale = FFLocaleScope.of(context);
  return showFFSheet<void>(
    context,
    title: context.tr('vendor.pos.share'),
    child: ReceiptShareSheet(
      job: ReceiptFileJob(
        data: data,
        lang: lang,
        t: (k) => locale.tIn(lang, k),
        tin: tin,
        vrn: vrn,
      ),
      hostContext: context,
    ),
  );
}

enum _Busy { image, pdf, text }

class ReceiptShareSheet extends StatefulWidget {
  const ReceiptShareSheet({super.key, required this.job, this.hostContext});

  final ReceiptFileJob job;

  /// The screen under the sheet (the "Downloaded" snack after it closes).
  final BuildContext? hostContext;

  @override
  State<ReceiptShareSheet> createState() => _ReceiptShareSheetState();
}

class _ReceiptShareSheetState extends State<ReceiptShareSheet> {
  _Busy? _busy;
  bool _failed = false;
  bool _tooLong = false;

  ReceiptData get _data => widget.job.data;

  String _a11y(String key) => fillIn(context.tr(key), {
    'number': receiptA11yNumber(_data),
  }).replaceAll(RegExp(r'\s+'), ' ').trim();

  void _close(ReceiptFileResult? result) {
    final host = widget.hostContext;
    final downloaded = context.tr('vendor.receipt.downloaded');
    Navigator.of(context).pop();
    if (result == ReceiptFileResult.downloaded &&
        host != null &&
        host.mounted) {
      FFSnack.info(host, downloaded);
    }
  }

  Future<void> _run(
    _Busy which,
    Future<ReceiptFileResult?> Function() go,
  ) async {
    if (_busy != null) return;
    setState(() {
      _busy = which;
      _failed = false;
    });
    try {
      final out = await go();
      if (mounted) _close(out);
    } on ReceiptTooLongForImage {
      if (mounted) {
        setState(() {
          _busy = null;
          _tooLong = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = null;
          _failed = true;
        });
      }
    }
  }

  Future<void> _image() =>
      _run(_Busy.image, () => shareReceiptImage(context, widget.job));

  Future<void> _pdf() => _run(_Busy.pdf, () => shareReceiptPdf(widget.job));

  Future<void> _text() => _run(_Busy.text, () async {
    final job = widget.job;
    await shareReceipt(
      receiptShareText(job.data, job.t, job.lang),
      receiptShareSubject(job.data, job.t),
    );
    return null;
  });

  @override
  Widget build(BuildContext context) {
    final web = DocumentActions.isWeb();
    final idle = _busy == null;
    final tooLong = _tooLong || receiptTooLongForImage(_data);
    final theme = Theme.of(context);
    return PopScope(
      // Not dismissed while a file is being made (§3.6).
      canPop: idle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_failed) ...[
            Semantics(
              container: true,
              liveRegion: true,
              child: FFAlert(
                key: const Key('receipt-share-failed'),
                message: context.tr('vendor.receipt.fileFailed'),
                tone: FFAlertTone.error,
              ),
            ),
            const SizedBox(height: FFTokens.spacingSm),
          ],
          if (_busy != null && _busy != _Busy.text) ...[
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                context.tr('vendor.receipt.preparing'),
                key: const Key('receipt-share-preparing'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: FFTokens.spacingSm),
          ],
          ReceiptShareRow(
            key: const Key('receipt-share-image'),
            icon: Icons.image_outlined,
            label: context.tr(
              web ? 'vendor.receipt.downloadImage' : 'vendor.receipt.asImage',
            ),
            semantics: _a11y(
              web
                  ? 'vendor.receipt.a11y.downloadImage'
                  : 'vendor.receipt.a11y.image',
            ),
            reason: tooLong ? context.tr('vendor.receipt.tooLongImage') : null,
            busy: _busy == _Busy.image,
            onTap: idle && !tooLong ? _image : null,
          ),
          ReceiptShareRow(
            key: const Key('receipt-share-pdf'),
            icon: Icons.picture_as_pdf_outlined,
            label: context.tr(
              web ? 'vendor.documents.openPdf' : 'vendor.receipt.asPdf',
            ),
            semantics: web
                ? fillIn(context.tr('vendor.documents.a11y.openPdf'), {
                    'title': context.tr('vendor.documents.receipt'),
                    'number': receiptA11yNumber(_data),
                  }).trim()
                : _a11y('vendor.receipt.a11y.pdf'),
            busy: _busy == _Busy.pdf,
            onTap: idle ? _pdf : null,
          ),
          ReceiptShareRow(
            key: const Key('receipt-share-text'),
            icon: Icons.notes,
            label: context.tr('vendor.documents.shareText'),
            semantics: fillIn(context.tr('vendor.documents.a11y.text'), {
              'title': context.tr('vendor.documents.receipt'),
              'number': receiptA11yNumber(_data),
            }).trim(),
            busy: _busy == _Busy.text,
            onTap: idle ? _text : null,
          ),
        ],
      ),
    );
  }
}

/// One share row (56dp, icon, label, spinner while busy, an optional
/// reason under it when disabled). Built like the S5 sheet's rows.
class ReceiptShareRow extends StatelessWidget {
  const ReceiptShareRow({
    super.key,
    required this.icon,
    required this.label,
    required this.semantics,
    required this.onTap,
    this.busy = false,
    this.reason,
  });

  final IconData icon;
  final String label;
  final String semantics;
  final VoidCallback? onTap;
  final bool busy;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: reason == null ? semantics : '$semantics. $reason',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: FFTokens.spacingXs,
          ),
          minTileHeight: 56,
          enabled: onTap != null,
          leading: busy
              ? const SizedBox(width: 24, height: 24, child: FFSpinner())
              : Icon(icon),
          title: Text(label),
          subtitle: reason == null
              ? null
              : Text(
                  reason!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
          onTap: onTap,
        ),
      ),
    );
  }
}
