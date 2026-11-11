// Vendor tools · S5: the one share sheet every vendor document uses (design
// spec docs/design/vendor-documents-s5.md §2): the receipt, a sale's
// receipt or pay-later invoice, a payment receipt, a statement and an order
// invoice. Shown only while the server reports `documents: true`; with it
// off the screens keep their S3/S4 text share.
//
// Rules (§2.2): a link is made lazily, on the first tap of WhatsApp, SMS or
// Copy link, and reused for the rest of this sheet. Closing the sheet
// forgets the URL: the server keeps only its hash (O-5), so it can never be
// shown again; the next share makes a new link. Changing the language after
// a link exists makes no new link. The share texts come from the server
// (texts.en / texts.sw); the app never builds them. SMS goes through the
// device (O-7), never a FitFlex SMS.
//
// Phone rule (§2.1): WhatsApp and SMS are addressed only to a WALK-IN
// customer's phone (vendor-owned data); an app buyer's never.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/file-export.dart';
import '../../../shared/i18n.dart';
import '../../../shared/network/browser_online.dart';
import '../../../shared/pdf-open.dart';
import '../sales/receipt_data.dart' show eatDateTime;
import '../sales/receipt_files.dart';
import '../sales/receipt_page.dart' show shareReceipt;
import '../stock/stock_options.dart' show fillIn;
import 'document_models.dart';

/// What the sheet does outside the app. Tests replace these; nothing here
/// ever talks to a server.
class DocumentActions {
  DocumentActions._();

  /// Opens WhatsApp (wa.me) or the SMS app. False when nothing opened.
  static Future<bool> Function(Uri uri) launch = (uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  static Future<void> Function(String text) copy = (text) =>
      Clipboard.setData(ClipboardData(text: text));

  /// Hands a PDF to the system share sheet (Android).
  static Future<void> Function(Uint8List bytes, String fileName) shareFile =
      (bytes, fileName) async {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes,
                mimeType: 'application/pdf',
                name: fileName,
              ),
            ],
            fileNameOverrides: [fileName],
          ),
        );
      };

  /// S6: hands any file (a report CSV) to the system share sheet.
  static Future<void> Function(
    Uint8List bytes,
    String fileName,
    String mimeType,
  )
  shareTypedFile = (bytes, fileName, mimeType) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
        fileNameOverrides: [fileName],
      ),
    );
  };

  /// S6, Flutter web: the browser downloads the file (a report CSV).
  static Future<void> Function(
    Uint8List bytes,
    String fileName,
    String mimeType,
  )
  download = (bytes, fileName, mimeType) async {
    await saveBytesExport(filename: fileName, bytes: bytes, mimeType: mimeType);
  };

  /// Flutter web: opens the PDF in a new tab.
  static Future<bool> Function(Uint8List bytes, String fileName) openPdf =
      openPdfInNewTab;

  /// Whether this is Flutter web ("Open PDF" instead of "Send PDF").
  static bool Function() isWeb = () => kIsWeb;
}

/// Opens the share sheet for [doc].
///
/// [shareText] gives the S3/S4 plain text in a language, [shareSubject] its
/// subject line. [customerPhone] is a walk-in customer's phone digits (see
/// [walkInPhoneDigits]); never an app buyer's. [queued]: a sale still on
/// this device (no number yet): only Share as text works.
Future<void> showDocumentShareSheet(
  BuildContext context, {
  required DocumentRef doc,
  required String lang,
  required String Function(String lang) shareText,
  required String Function(String lang) shareSubject,
  String? customerPhone,
  bool queued = false,
  ReceiptFileJob Function(String lang)? receiptFile,
}) {
  final title = documentTitle(context.tr, doc);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // A link being made cannot be lost by a drag (§2.2); the close button
    // and back respect the sheet's own PopScope.
    enableDrag: false,
    builder: (_) => FFSheet(
      title: fillIn(context.tr('vendor.documents.shareTitle'), {
        'title': title,
        'number': doc.number ?? '',
      }).trim(),
      child: DocumentShareSheet(
        doc: doc,
        initialLang: lang,
        shareText: shareText,
        shareSubject: shareSubject,
        customerPhone: customerPhone,
        queued: queued,
        hostContext: context,
        receiptFile: receiptFile,
      ),
    ),
  );
}

/// Opens the links list for [doc] on its own (a voided document: no share,
/// but its links can still be turned off, §2.4).
Future<void> showDocumentLinksSheet(BuildContext context, DocumentRef doc) =>
    showFFSheet<void>(
      context,
      title: context.tr('vendor.documents.linksTitle'),
      child: DocumentLinksList(doc: doc),
    );

/// "Receipt", "Invoice", … in [t]'s language.
String documentTitle(String Function(String) t, DocumentRef doc) =>
    t(doc.titleKey);

class DocumentShareSheet extends StatefulWidget {
  const DocumentShareSheet({
    super.key,
    required this.doc,
    required this.initialLang,
    required this.shareText,
    required this.shareSubject,
    this.customerPhone,
    this.queued = false,
    this.hostContext,
    this.receiptFile,
  });

  final DocumentRef doc;
  final String initialLang;
  final String Function(String lang) shareText;
  final String Function(String lang) shareSubject;
  final String? customerPhone;
  final bool queued;

  /// The screen under the sheet (a snack after the sheet closes).
  final BuildContext? hostContext;

  /// Sale extras #3 (Q-10): a walk-in sale's receipt made on the device in
  /// a language. Adds the Image row, and the PDF row falls back to the
  /// on-device PDF when the sale is queued or the device is offline.
  final ReceiptFileJob Function(String lang)? receiptFile;

  @override
  State<DocumentShareSheet> createState() => _DocumentShareSheetState();
}

enum _Row { whatsapp, sms, copy, pdf, pdf80, text, image, localPdf }

class _DocumentShareSheetState extends State<DocumentShareSheet> {
  late String _lang = widget.initialLang == 'sw' ? 'sw' : 'en';
  SharedLink? _link;
  _Row? _busy;
  bool _unavailable = false;
  bool _createFailed = false;

  /// 429 rate_limited: seconds to wait before another link.
  int? _waitSeconds;
  bool _pdfFailed = false;
  _Row? _retry;
  bool _more = false;
  int? _activeCount;
  String? _notice;

  /// Sale extras #3: an on-device file could not be made.
  bool _fileFailed = false;
  bool _tooLong = false;

  @override
  void initState() {
    super.initState();
    BrowserOnline.instance.addListener(_onOnline);
    if (!widget.queued) _loadCount();
  }

  @override
  void dispose() {
    BrowserOnline.instance.removeListener(_onOnline);
    super.dispose();
  }

  void _onOnline() {
    if (mounted) setState(() {});
  }

  bool get _offline => !BrowserOnline.instance.value;

  String _t(String key) => context.tr(key);

  String get _title => documentTitle(_t, widget.doc);
  String get _number => _link?.number ?? widget.doc.number ?? '';

  String _a11y(String key) =>
      fillIn(_t(key), {'title': _title, 'number': _number}).trim();

  Future<void> _loadCount() async {
    try {
      final res = await AppScope.of(context).api.vendorDocumentLinks(
        docType: widget.doc.linksDocType,
        docId: widget.doc.id,
      );
      if (!mounted) return;
      setState(() => _activeCount = (res['activeCount'] as num?)?.toInt());
    } catch (_) {
      // The row shows without a count.
    }
  }

  /// Closes the sheet and tells the screen under it.
  void _closeWith(String message) {
    final host = widget.hostContext;
    Navigator.of(context).pop();
    if (host != null && host.mounted) FFSnack.error(host, message);
  }

  /// The link of this sheet, made on first use (§2.2).
  Future<SharedLink?> _ensureLink(_Row row) async {
    final have = _link;
    if (have != null) return have;
    setState(() {
      _busy = row;
      _createFailed = false;
      _waitSeconds = null;
      _notice = null;
    });
    try {
      final res = await AppScope.of(context).api.vendorShareDocument(
        kind: widget.doc.kind,
        id: widget.doc.id,
        customerId: widget.doc.customerId,
        lang: _lang,
      );
      final link = SharedLink.fromJson(res);
      if (link.url.isEmpty) throw StateError('no url');
      if (!mounted) return null;
      setState(() {
        _link = link;
        _activeCount = (_activeCount ?? 0) + 1;
      });
      return link;
    } on ApiException catch (e) {
      if (!mounted) return null;
      if (e.code == 'public_url_not_configured') {
        setState(() => _unavailable = true);
      } else if (e.code == 'document_cancelled') {
        setState(() => _notice = _t('vendor.documents.voidedNote'));
      } else if (e.code == 'vendor_suspended') {
        _closeWith(_t('vendor.sales.suspended'));
      } else if (e.status == 403) {
        _closeWith(_t('vendor.documents.noAccess'));
      } else if (e.status == 429) {
        final body = e.body is Map ? e.body as Map : const {};
        final s = body['retryAfterSeconds'];
        setState(() {
          _waitSeconds = s is num && s > 0 ? s.ceil() : 60;
          _retry = row;
        });
      } else {
        setState(() {
          _createFailed = true;
          _retry = row;
        });
      }
      return null;
    } catch (_) {
      if (mounted) {
        setState(() {
          _createFailed = true;
          _retry = row;
        });
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _whatsApp() async {
    final link = await _ensureLink(_Row.whatsapp);
    if (link == null || !mounted) return;
    final ok = await _launch(
      whatsAppUri(link.whatsappIn(_lang), phone: widget.customerPhone),
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _notice = _t('vendor.documents.linkReady'));
    } else {
      await DocumentActions.copy(link.urlIn(_lang));
      if (mounted) {
        setState(() => _notice = _t('vendor.documents.noWhatsApp'));
      }
    }
  }

  Future<void> _sms() async {
    final link = await _ensureLink(_Row.sms);
    if (link == null || !mounted) return;
    final ok = await _launch(
      smsUri(link.smsIn(_lang), phone: widget.customerPhone),
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _notice = _t('vendor.documents.linkReady'));
    } else {
      await DocumentActions.copy(link.urlIn(_lang));
      if (mounted) setState(() => _notice = _t('vendor.documents.noSms'));
    }
  }

  Future<bool> _launch(Uri uri) async {
    try {
      return await DocumentActions.launch(uri);
    } catch (_) {
      return false;
    }
  }

  Future<void> _copy() async {
    final link = await _ensureLink(_Row.copy);
    if (link == null || !mounted) return;
    await DocumentActions.copy(link.urlIn(_lang));
    if (mounted) setState(() => _notice = _t('vendor.documents.copied'));
  }

  Future<void> _pdf({String paper = 'a4'}) async {
    final row = paper == '80mm' ? _Row.pdf80 : _Row.pdf;
    setState(() {
      _busy = row;
      _pdfFailed = false;
      _notice = null;
    });
    try {
      final out = await AppScope.of(context).api.vendorDocumentPdf(
        widget.doc.viewDocType,
        widget.doc.id,
        lang: _lang,
        paper: paper,
      );
      final name =
          out.fileName ?? '${_number.isEmpty ? 'document' : _number}.pdf';
      if (DocumentActions.isWeb()) {
        await DocumentActions.openPdf(out.bytes, name);
      } else {
        await DocumentActions.shareFile(out.bytes, name);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'vendor_suspended') {
        _closeWith(_t('vendor.sales.suspended'));
        return;
      }
      if (e.status == 403) {
        _closeWith(_t('vendor.documents.noAccess'));
        return;
      }
      setState(() {
        _pdfFailed = true;
        _retry = row;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _pdfFailed = true;
          _retry = row;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _text() async {
    final link = _link;
    var text = widget.shareText(_lang);
    if (link != null) {
      final line = fillIn(
        FFLocaleScope.of(context).tIn(_lang, 'vendor.documents.textLinkLine'),
        {'url': link.urlIn(_lang)},
      );
      text = '$text\n$line';
    }
    await shareReceipt(text, widget.shareSubject(_lang));
  }

  /// Sale extras #3: the on-device image or PDF; the sheet closes once it
  /// has been handed on.
  Future<void> _file(_Row row) async {
    final make = widget.receiptFile;
    if (make == null || _busy != null) return;
    setState(() {
      _busy = row;
      _fileFailed = false;
      _pdfFailed = false;
      _notice = null;
    });
    try {
      final job = make(_lang);
      final out = row == _Row.image
          ? await shareReceiptImage(context, job)
          : await shareReceiptPdf(job);
      if (!mounted) return;
      final host = widget.hostContext;
      final downloaded = _t('vendor.receipt.downloaded');
      Navigator.of(context).pop();
      if (out == ReceiptFileResult.downloaded && host != null && host.mounted) {
        FFSnack.info(host, downloaded);
      }
    } on ReceiptTooLongForImage {
      if (mounted) setState(() => _tooLong = true);
    } catch (_) {
      if (mounted) setState(() => _fileFailed = true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _openLinks() async {
    await showDocumentLinksSheet(context, widget.doc);
    if (mounted) await _loadCount();
  }

  void _retryLast() {
    switch (_retry) {
      case _Row.whatsapp:
        _whatsApp();
      case _Row.sms:
        _sms();
      case _Row.copy:
        _copy();
      case _Row.pdf:
        _pdf();
      case _Row.pdf80:
        _pdf(paper: '80mm');
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final idle = _busy == null;
    final linkRows = idle && !widget.queued && !_offline && !_unavailable;
    final pdfRows = idle && !widget.queued && !_offline;
    final web = DocumentActions.isWeb();
    final files = widget.receiptFile;
    // Q-10: queued or offline, the PDF row makes the PDF on the device.
    final localPdf = files != null && (widget.queued || _offline);
    final imageTooLong =
        files != null &&
        (_tooLong || receiptTooLongForImage(files(_lang).data));
    final reason = widget.queued
        ? _t(
            files != null
                ? 'vendor.documents.needsNumberFiles'
                : 'vendor.documents.needsNumber',
          )
        : _offline
        ? _t(
            files != null
                ? 'vendor.documents.offlineFiles'
                : 'vendor.documents.offline',
          )
        : null;
    final rows = <Widget>[
      _row(
        key: 'doc-share-whatsapp',
        icon: Icons.chat_outlined,
        label: _t('vendor.documents.whatsapp'),
        semantics: _a11y('vendor.documents.a11y.whatsapp'),
        row: _Row.whatsapp,
        onTap: linkRows ? _whatsApp : null,
      ),
      _row(
        key: 'doc-share-sms',
        icon: Icons.sms_outlined,
        label: _t('vendor.documents.sms'),
        semantics: _a11y('vendor.documents.a11y.sms'),
        row: _Row.sms,
        onTap: linkRows ? _sms : null,
      ),
      _row(
        key: 'doc-share-copy',
        icon: Icons.link,
        label: _t('vendor.documents.copyLink'),
        semantics: _a11y('vendor.documents.a11y.copy'),
        row: _Row.copy,
        onTap: linkRows ? _copy : null,
      ),
      _row(
        key: 'doc-share-pdf',
        icon: Icons.picture_as_pdf_outlined,
        label: _t(
          web ? 'vendor.documents.openPdf' : 'vendor.documents.sendPdf',
        ),
        // UAT D5: what is said matches what is shown.
        semantics: _a11y(
          web ? 'vendor.documents.a11y.openPdf' : 'vendor.documents.a11y.pdf',
        ),
        row: localPdf ? _Row.localPdf : _Row.pdf,
        onTap: localPdf
            ? (idle ? () => _file(_Row.localPdf) : null)
            : pdfRows
            ? () => _pdf()
            : null,
      ),
      if (files != null)
        _row(
          key: 'doc-share-image',
          icon: Icons.image_outlined,
          label: _t(
            web ? 'vendor.receipt.downloadImage' : 'vendor.receipt.asImage',
          ),
          semantics: fillIn(
            _t(
              web
                  ? 'vendor.receipt.a11y.downloadImage'
                  : 'vendor.receipt.a11y.image',
            ),
            {'number': receiptA11yNumber(files(_lang).data)},
          ).trim(),
          row: _Row.image,
          onTap: idle && !imageTooLong ? () => _file(_Row.image) : null,
        ),
      _row(
        key: 'doc-share-text',
        icon: Icons.notes,
        label: _t('vendor.documents.shareText'),
        semantics: _a11y('vendor.documents.a11y.text'),
        row: _Row.text,
        onTap: idle ? _text : null,
      ),
      if (_more)
        _row(
          key: 'doc-share-pdf80',
          icon: Icons.receipt_long_outlined,
          label: _t('vendor.documents.pdfThermal'),
          semantics: _t('vendor.documents.pdfThermal'),
          row: _Row.pdf80,
          onTap: pdfRows ? () => _pdf(paper: '80mm') : null,
        ),
      if (!widget.queued)
        _row(
          key: 'doc-share-links',
          icon: Icons.manage_history,
          label: _activeCount == null
              ? _t('vendor.documents.linksTitle')
              : fillIn(_t('vendor.documents.linksCount'), {'n': _activeCount}),
          semantics: null,
          row: null,
          onTap: idle ? _openLinks : null,
        ),
    ];
    return PopScope(
      // Never lost while a link is being made (§2.2).
      canPop: _busy == null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _t('vendor.documents.language'),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: FFTokens.spacingXs),
          FFSegmented(
            key: const Key('doc-share-language'),
            value: _lang,
            options: [('en', _t('lang.name.en')), ('sw', _t('lang.name.sw'))],
            onChanged: (v) {
              if (_busy != null) return;
              setState(() => _lang = v);
            },
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: FFTokens.spacingXs),
              Expanded(
                child: Text(
                  _t('vendor.documents.privacyNote'),
                  key: const Key('doc-share-privacy'),
                  style: muted,
                ),
              ),
            ],
          ),
          if (reason != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Text(reason, key: const Key('doc-share-reason'), style: muted),
          ],
          if (_unavailable) ...[
            const SizedBox(height: FFTokens.spacingSm),
            FFAlert(
              key: const Key('doc-share-unavailable'),
              message: _t('vendor.documents.unavailable'),
            ),
          ],
          if (_waitSeconds != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Semantics(
              container: true,
              liveRegion: true,
              child: FFAlert(
                key: const Key('doc-share-rate-limited'),
                message: fillIn(_t('vendor.documents.rateLimited'), {
                  'n': _waitSeconds,
                }),
                tone: FFAlertTone.warning,
              ),
            ),
          ],
          if (imageTooLong) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              _t('vendor.receipt.tooLongImage'),
              key: const Key('doc-share-image-too-long'),
              style: muted,
            ),
          ],
          if (_fileFailed) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Semantics(
              container: true,
              liveRegion: true,
              child: FFAlert(
                key: const Key('doc-share-file-failed'),
                message: _t('vendor.receipt.fileFailed'),
                tone: FFAlertTone.error,
              ),
            ),
          ],
          if (_createFailed || _pdfFailed) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Semantics(
              container: true,
              liveRegion: true,
              child: FFAlert(
                key: Key(
                  _createFailed
                      ? 'doc-share-create-failed'
                      : 'doc-share-pdf-failed',
                ),
                message: _t(
                  _createFailed
                      ? 'vendor.documents.createFailed'
                      : 'vendor.documents.pdfFailed',
                ),
                tone: FFAlertTone.error,
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FFButton(
                key: const Key('doc-share-retry'),
                label: _t('common.retry'),
                variant: FFButtonVariant.ghost,
                visualDensity: VisualDensity.standard,
                onPressed: idle ? _retryLast : null,
              ),
            ),
          ],
          if (_busy != null || _notice != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                _busy == null
                    ? _notice!
                    : _t(
                        _busy == _Row.image || _busy == _Row.localPdf
                            ? 'vendor.receipt.preparing'
                            : _busy == _Row.pdf || _busy == _Row.pdf80
                            ? 'vendor.documents.pdfPreparing'
                            : 'vendor.documents.creating',
                      ),
                key: const Key('doc-share-notice'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
          const SizedBox(height: FFTokens.spacingSm),
          LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                );
              }
              final w = (box.maxWidth - FFTokens.spacingSm) / 2;
              return Wrap(
                spacing: FFTokens.spacingSm,
                children: [for (final r in rows) SizedBox(width: w, child: r)],
              );
            },
          ),
          if (!_more && !widget.queued)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FFButton(
                key: const Key('doc-share-more'),
                label: _t('vendor.documents.more'),
                icon: Icons.expand_more,
                variant: FFButtonVariant.ghost,
                visualDensity: VisualDensity.standard,
                onPressed: () => setState(() => _more = true),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row({
    required String key,
    required IconData icon,
    required String label,
    required String? semantics,
    required _Row? row,
    required VoidCallback? onTap,
  }) {
    final busy = row != null && _busy == row;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semantics ?? label,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: ListTile(
          key: Key(key),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: FFTokens.spacingXs,
          ),
          minTileHeight: 56,
          enabled: onTap != null,
          leading: busy
              ? const SizedBox(width: 24, height: 24, child: FFSpinner())
              : Icon(icon),
          title: Text(label),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// The links made for one document (§2.3): when, by whom, last opened,
/// language, and Turn off. Never the URL.
class DocumentLinksList extends StatefulWidget {
  const DocumentLinksList({super.key, required this.doc});
  final DocumentRef doc;

  @override
  State<DocumentLinksList> createState() => _DocumentLinksListState();
}

class _DocumentLinksListState extends State<DocumentLinksList> {
  List<DocumentLinkRow>? _links;
  bool _failed = false;
  bool _busy = false;
  String? _notice;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _links = null;
    });
    try {
      final res = await AppScope.of(context).api.vendorDocumentLinks(
        docType: widget.doc.linksDocType,
        docId: widget.doc.id,
      );
      if (mounted) setState(() => _links = linkRowsOf(res));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 403) {
        Navigator.of(context).pop();
        FFSnack.error(context, context.tr('vendor.documents.noAccess'));
        return;
      }
      setState(() => _failed = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _revoke(DocumentLinkRow row) async {
    final ok = await showFFConfirmDialog(
      context,
      message: context.tr('vendor.documents.revokeConfirm'),
      confirmLabel: context.tr('vendor.documents.revoke'),
      destructive: true,
      confirmKey: const Key('doc-links-revoke-confirm'),
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _notice = null;
      _error = false;
    });
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorRevokeDocumentLink(row.id);
      final link = res['link'];
      if (!mounted) return;
      setState(() {
        final updated = link is Map ? DocumentLinkRow.fromJson(link) : null;
        _links = [
          for (final l in _links ?? const <DocumentLinkRow>[])
            l.id == row.id && updated != null ? updated : l,
        ];
        _notice = context.tr('vendor.documents.revoked');
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _notice = context.tr('vendor.documents.revokeFailed');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeAll(int active) async {
    final ok = await showFFConfirmDialog(
      context,
      message: fillIn(context.tr('vendor.documents.revokeAllConfirm'), {
        'n': active,
      }),
      confirmLabel: context.tr('vendor.documents.revokeAll'),
      destructive: true,
      confirmKey: const Key('doc-links-revoke-all-confirm'),
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _notice = null;
      _error = false;
    });
    try {
      final res = await AppScope.of(context).api.vendorRevokeDocumentLinks(
        docType: widget.doc.linksDocType,
        docId: widget.doc.id,
      );
      if (!mounted) return;
      setState(() {
        _links = linkRowsOf(res);
        _notice = context.tr('vendor.documents.revoked');
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _notice = context.tr('vendor.documents.revokeFailed');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final links = _links;
    if (_failed) {
      return FFErrorState(
        key: const Key('doc-links-error'),
        message: context.tr('vendor.documents.linksFailed'),
        onRetry: _load,
      );
    }
    if (links == null) {
      return FFSkeletonList(
        count: 2,
        semanticLabel: context.tr('common.loading'),
      );
    }
    if (links.isEmpty) {
      return Text(
        context.tr('vendor.documents.noLinks'),
        key: const Key('doc-links-empty'),
      );
    }
    final active = links.where((l) => l.active).length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_notice != null) ...[
          Semantics(
            container: true,
            liveRegion: true,
            child: FFAlert(
              key: const Key('doc-links-notice'),
              message: _notice!,
              tone: _error ? FFAlertTone.error : FFAlertTone.success,
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
        ],
        for (final l in links) ...[
          _LinkCard(row: l, busy: _busy, onRevoke: () => _revoke(l)),
          const SizedBox(height: FFTokens.spacingSm),
        ],
        if (active >= 2)
          FFButton(
            key: const Key('doc-links-revoke-all'),
            label: context.tr('vendor.documents.revokeAll'),
            icon: Icons.link_off,
            variant: FFButtonVariant.destructive,
            fullWidth: true,
            visualDensity: VisualDensity.standard,
            onPressed: _busy ? null : () => _revokeAll(active),
          ),
      ],
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.row,
    required this.busy,
    required this.onRevoke,
  });

  final DocumentLinkRow row;
  final bool busy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    String when(String? iso) => eatDateTime(iso, locale: lang);
    final title = fillIn(context.tr('vendor.documents.linkN'), {'n': row.n});
    final state = row.active
        ? context.tr('vendor.documents.active')
        : fillIn(context.tr('vendor.documents.turnedOff'), {
            'date': when(row.revokedAt),
          });
    final created = row.createdByName == null
        ? fillIn(context.tr('vendor.documents.createdOn'), {
            'date': when(row.createdAt),
          })
        : fillIn(context.tr('vendor.documents.createdBy'), {
            'date': when(row.createdAt),
            'name': row.createdByName,
          });
    final opened = row.lastOpenedAt == null
        ? context.tr('vendor.documents.neverOpened')
        : fillIn(context.tr('vendor.documents.lastOpened'), {
            'date': when(row.lastOpenedAt),
          });
    final langTag = context.tr('vendor.documents.lang.${row.lang}');
    return FFCard(
      key: Key('doc-link-${row.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One screen-reader node for the row; Turn off is its own.
          Semantics(
            container: true,
            label: [title, state, created, opened, langTag].join(', '),
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: FFTokens.spacingSm,
                  runSpacing: FFTokens.spacingXs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    FFBadge(
                      key: Key('doc-link-state-${row.id}'),
                      label: state,
                      tone: row.active ? FFBadgeTone.success : FFBadgeTone.gray,
                      wrap: true,
                    ),
                    FFBadge(label: langTag, tone: FFBadgeTone.gray),
                  ],
                ),
                const SizedBox(height: FFTokens.spacingXs),
                Text(created, style: muted),
                Text(opened, style: muted),
              ],
            ),
          ),
          if (row.active)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FFButton(
                key: Key('doc-link-revoke-${row.id}'),
                label: context.tr('vendor.documents.revoke'),
                semanticLabel: fillIn(
                  context.tr('vendor.documents.a11y.revokeN'),
                  {'n': row.n},
                ),
                icon: Icons.link_off,
                variant: FFButtonVariant.ghost,
                visualDensity: VisualDensity.standard,
                onPressed: busy ? null : onRevoke,
              ),
            ),
        ],
      ),
    );
  }
}
