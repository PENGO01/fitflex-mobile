// Vendor tools · sale extras #3 (docs/design/vendor-sale-extras-1110.md
// §3.5): the customer receipt as an 80 mm PDF, made on the device (works
// offline and for a sale still queued). Same blocks and words as
// ReceiptView(audit: false); real text (selectable, read by screen
// readers); Inter embedded (never the built-in Helvetica, which has no
// glyphs beyond Latin-1). Never the customer's phone or the customer type.
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../shared/formatters.dart';
import '../documents/document_view.dart' show vatCodeLine;
import 'receipt_data.dart';
import 'sales_widgets.dart' show methodLabel;

/// How a printed row looks.
enum ReceiptRowStyle { title, heading, normal, strong, muted, rule }

/// One row of the printed receipt: a text, and an amount on the right.
class ReceiptPrintRow {
  const ReceiptPrintRow(
    this.text, {
    this.amount,
    this.style = ReceiptRowStyle.normal,
  });
  const ReceiptPrintRow.rule()
    : text = '',
      amount = null,
      style = ReceiptRowStyle.rule;

  final String text;
  final String? amount;
  final ReceiptRowStyle style;

  @override
  String toString() => amount == null ? text : '$text  $amount';
}

/// The heading of a receipt file: the invoice or receipt number, or, for a
/// sale still queued on this device, the same heading as the on-screen
/// receipt (`ReceiptView`): "Receipt", followed by "Waiting to sync" and
/// the temporary ref (UAT D5: the image and the PDF read the same).
String receiptFileHeading(ReceiptData r, String Function(String) t) {
  String fill(String key, Map<String, Object?> v) {
    var out = t(key);
    v.forEach((k, val) => out = out.replaceAll('{$k}', '$val'));
    return out;
  }

  if (r.queued || r.number == null) return t('vendor.documents.receipt');
  if (r.credit && r.invoiceNumber != null) {
    return '${t('vendor.doc.invoice')} ${r.invoiceNumber}';
  }
  return fill('vendor.pos.receiptNo', {'number': r.number});
}

/// The receipt as printed rows, in [t]'s language (the receipt toggle).
List<ReceiptPrintRow> receiptPrintRows(
  ReceiptData r,
  String Function(String key) t,
  String lang, {
  String? tin,
  String? vrn,
}) {
  String fill(String key, Map<String, Object?> v) {
    var out = t(key);
    v.forEach((k, val) => out = out.replaceAll('{$k}', '$val'));
    return out;
  }

  const muted = ReceiptRowStyle.muted;
  final rows = <ReceiptPrintRow>[
    if (r.business != null)
      ReceiptPrintRow(r.business!, style: ReceiptRowStyle.title),
    if (r.contact != null) ReceiptPrintRow(r.contact!, style: muted),
    if (r.address != null) ReceiptPrintRow(r.address!, style: muted),
    if (tin != null)
      ReceiptPrintRow(fill('vendor.doc.tin', {'tin': tin}), style: muted),
    if (vrn != null)
      ReceiptPrintRow(fill('vendor.doc.vrn', {'vrn': vrn}), style: muted),
    ReceiptPrintRow(receiptFileHeading(r, t), style: ReceiptRowStyle.heading),
    if (!r.queued && r.credit && r.invoiceNumber != null && r.number != null)
      ReceiptPrintRow(
        fill('vendor.doc.saleRef', {'number': r.number}),
        style: muted,
      ),
    if (r.queued) ...[
      ReceiptPrintRow(
        t('vendor.pos.waitingSync'),
        style: ReceiptRowStyle.strong,
      ),
      ReceiptPrintRow(
        fill('vendor.pos.tempRef', {'ref': r.tempRef ?? ''}),
        style: muted,
      ),
      ReceiptPrintRow(t('vendor.pos.waitingSyncBody'), style: muted),
    ],
  ];
  final when = eatDateTime(r.soldAt, locale: lang);
  if (when.isNotEmpty) rows.add(ReceiptPrintRow(when, style: muted));
  if (r.hasCustomer) {
    // The name only: never the phone, never the customer type (§3.1).
    rows.add(
      ReceiptPrintRow(
        r.customerName != null
            ? fill('vendor.receipt.customer', {'name': r.customerName})
            : r.queued
            ? t('vendor.receipt.customerAfterSync')
            : fill('vendor.receipt.customer', {
                'name': t(r.unnamedCustomerKey),
              }),
      ),
    );
  }
  if (r.credit) rows.add(ReceiptPrintRow(t('vendor.sales.payLaterBadge')));
  if (r.servedBy != null) {
    rows.add(
      ReceiptPrintRow(
        fill('vendor.pos.servedBy', {'name': r.servedBy}),
        style: muted,
      ),
    );
  }
  rows.add(const ReceiptPrintRow.rule());
  for (final l in r.lines) {
    final name = l.variant == null ? l.name : '${l.name} (${l.variant})';
    final gross = formatMoney(l.qty * l.unitPriceTzs);
    rows.add(
      ReceiptPrintRow(
        '${l.qty} × $name',
        amount: l.vatCode == null ? gross : '$gross ${l.vatCode}',
      ),
    );
    if (l.qty > 1 || l.priceChanged) {
      rows.add(
        ReceiptPrintRow('@ ${formatMoney(l.unitPriceTzs)}', style: muted),
      );
    }
    if (l.discountTzs > 0) {
      rows.add(
        ReceiptPrintRow(
          t('vendor.pos.lineDiscountShort'),
          amount: '−${formatMoney(l.discountTzs)}',
        ),
      );
    }
    if (l.refundedQty > 0 && !r.voided) {
      rows.add(
        ReceiptPrintRow(
          fill('vendor.refunds.lineRefunded', {'n': l.refundedQty}),
          style: muted,
        ),
      );
    }
  }
  rows.add(const ReceiptPrintRow.rule());
  rows.add(
    ReceiptPrintRow(
      t('vendor.pos.subtotal'),
      amount: formatMoney(r.subtotalTzs),
    ),
  );
  if (r.discountsTzs > 0) {
    rows.add(
      ReceiptPrintRow(
        t('vendor.pos.discounts'),
        amount: '−${formatMoney(r.discountsTzs)}',
      ),
    );
  }
  rows.add(
    ReceiptPrintRow(
      t('vendor.pos.total'),
      amount: formatCurrency(r.totalTzs),
      style: ReceiptRowStyle.strong,
    ),
  );
  if (r.refundedTzs > 0 && !r.voided) {
    rows.add(
      ReceiptPrintRow(
        t('vendor.refunds.refundsRow'),
        amount: '−${formatCurrency(r.refundedTzs)}',
      ),
    );
    rows.add(
      ReceiptPrintRow(
        t('vendor.refunds.netAfter'),
        amount: formatCurrency(r.netAfterRefundsTzs),
        style: ReceiptRowStyle.strong,
      ),
    );
  }
  if (r.hasVat) {
    rows.add(
      ReceiptPrintRow(
        fill('vendor.doc.includesVat', {'amount': ''}).trim(),
        amount: formatCurrency(r.vatIncludedTzs),
      ),
    );
    if (r.vatSummary.isNotEmpty) {
      rows.add(ReceiptPrintRow(t('vendor.doc.vatSummary')));
      for (final v in r.vatSummary) {
        rows.add(
          ReceiptPrintRow(
            '${vatCodeLine(t, v)} · ${t('vendor.doc.vatNet')} ${formatMoney(v.netTzs)}',
            amount: '${t('vendor.doc.vat')} ${formatMoney(v.vatTzs)}',
            style: muted,
          ),
        );
      }
    }
  }
  for (final p in r.payments) {
    final method = methodLabel(t, p.method);
    rows.add(
      ReceiptPrintRow(
        p.reference == null ? method : '$method (${p.reference})',
        amount: formatMoney(p.amountTzs),
      ),
    );
  }
  if (r.credit) {
    rows.add(
      ReceiptPrintRow(
        t('vendor.pos.credit.paidNow'),
        amount: formatMoney(r.paidNowTzs),
      ),
    );
    rows.add(
      ReceiptPrintRow(
        t('vendor.receipt.balanceAtSale'),
        amount: formatCurrency(r.balanceAtSaleTzs),
        style: ReceiptRowStyle.strong,
      ),
    );
    if (r.dueDate != null) {
      rows.add(
        ReceiptPrintRow(
          t('vendor.receipt.dueBy'),
          amount: receiptDay(r.dueDate, lang),
        ),
      );
    }
  } else if (r.changeTzs > 0) {
    rows.add(
      ReceiptPrintRow(t('vendor.pos.change'), amount: formatMoney(r.changeTzs)),
    );
  }
  rows.add(const ReceiptPrintRow.rule());
  if (r.business != null) {
    rows.add(
      ReceiptPrintRow(
        fill(
          r.credit
              ? 'vendor.receipt.closingCredit'
              : 'vendor.pos.receiptFooter',
          {'business': r.business},
        ),
      ),
    );
  }
  // Always last, on every receipt format.
  rows.add(ReceiptPrintRow(t('vendor.pos.notFiscal'), style: muted));
  return rows;
}

/// The bundled Inter faces, loaded once.
class ReceiptPdfFonts {
  ReceiptPdfFonts._();
  static pw.Font? _regular;
  static pw.Font? _bold;

  /// Where the font bytes come from (tests may replace it).
  static Future<ByteData> Function(String asset) load = rootBundle.load;

  static Future<(pw.Font, pw.Font)> get() async {
    _regular ??= pw.Font.ttf(await load('assets/fonts/Inter-400.ttf'));
    _bold ??= pw.Font.ttf(await load('assets/fonts/Inter-700.ttf'));
    return (_regular!, _bold!);
  }
}

/// The 80 mm roll, as tall as the receipt (§3.5).
final receiptPdfFormat = PdfPageFormat(
  80 * PdfPageFormat.mm,
  double.infinity,
  marginAll: 4 * PdfPageFormat.mm,
);

/// The receipt PDF bytes.
Future<Uint8List> buildReceiptPdf(
  ReceiptData r,
  String Function(String key) t,
  String lang, {
  String? tin,
  String? vrn,
}) async {
  final (regular, bold) = await ReceiptPdfFonts.get();
  final rows = receiptPrintRows(r, t, lang, tin: tin, vrn: vrn);
  final doc = pw.Document(
    title: receiptFileHeading(r, t),
    author: r.business,
    creator: 'FitFlex',
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );
  const grey = PdfColor.fromInt(0xFF475569);
  pw.TextStyle styleOf(ReceiptRowStyle s) => switch (s) {
    ReceiptRowStyle.title => pw.TextStyle(font: bold, fontSize: 12),
    ReceiptRowStyle.heading => pw.TextStyle(font: bold, fontSize: 10),
    ReceiptRowStyle.strong => pw.TextStyle(font: bold, fontSize: 10),
    ReceiptRowStyle.muted => pw.TextStyle(
      font: regular,
      fontSize: 8,
      color: grey,
    ),
    _ => pw.TextStyle(font: regular, fontSize: 9),
  };
  pw.Widget rowOf(ReceiptPrintRow row) {
    if (row.style == ReceiptRowStyle.rule) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Divider(height: 1, thickness: 0.5, color: grey),
      );
    }
    final style = styleOf(row.style);
    final text = pw.Text(row.text, style: style);
    final child = row.amount == null
        ? text
        : pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: text),
              pw.SizedBox(width: 6),
              pw.Text(row.amount!, style: style, textAlign: pw.TextAlign.right),
            ],
          );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: child,
    );
  }

  doc.addPage(
    pw.Page(
      pageFormat: receiptPdfFormat,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [for (final row in rows) rowOf(row)],
      ),
    ),
  );
  return doc.save();
}
