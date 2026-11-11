// Vendor tools · S5: how the S3/S4 screens open the share sheet, and the
// seller TIN/VRN for the native receipt. Each screen keeps its old text
// share while the server reports `documents` off (AC-1).
import 'package:flutter/widgets.dart';

import '../../../app_scope.dart';
import '../../../shared/i18n.dart';
import '../customers/customers_widgets.dart' show customerIdPattern;
import '../sales/receipt_data.dart';
import '../sales/receipt_files.dart';
import '../stock/stock_options.dart';
import 'document_models.dart';
import 'document_share_sheet.dart';

/// A walk-in customer's phone digits for WhatsApp / SMS (§2.1), when this
/// person may read customers. App buyers never have one. Any failure means
/// no number (WhatsApp then opens its chat picker).
Future<String?> walkInPhoneFor(
  BuildContext context,
  String? customerId,
  VendorTools tools,
) async {
  if (customerId == null ||
      !customerIdPattern.hasMatch(customerId) ||
      !tools.customers ||
      !canVendor(context, 'customers')) {
    return null;
  }
  try {
    final res = await AppScope.of(context).api.vendorCustomer(customerId);
    final c = res['customer'];
    return c is Map ? walkInPhoneDigits(c) : null;
  } catch (_) {
    return null;
  }
}

/// The share sheet for a walk-in sale (receipt, or a pay-later invoice).
Future<void> openSaleShareSheet(
  BuildContext context, {
  required ReceiptData data,
  required String lang,
  required VendorTools tools,
  String? tin,
  String? vrn,
}) async {
  final locale = FFLocaleScope.of(context);
  final phone = data.queued
      ? null
      : await walkInPhoneFor(context, data.customerId, tools);
  if (!context.mounted) return;
  final number = data.credit && data.invoiceNumber != null
      ? data.invoiceNumber
      : data.number;
  await showDocumentShareSheet(
    context,
    doc: DocumentRef.sale(
      saleId: data.id ?? data.clientRef ?? '',
      credit: data.credit,
      number: data.queued ? null : number,
    ),
    lang: lang,
    queued: data.queued || data.id == null,
    customerPhone: phone,
    // Sale extras #3 (Q-10): Image, and the on-device PDF when queued or
    // offline, in the sheet's language.
    receiptFile: (l) => ReceiptFileJob(
      data: data,
      lang: l,
      t: (k) => locale.tIn(l, k),
      tin: tin,
      vrn: vrn,
    ),
    shareText: (l) => receiptShareText(data, (k) => locale.tIn(l, k), l),
    shareSubject: (l) => [
      ?data.business,
      if (data.number != null && !data.queued)
        data.credit && data.invoiceNumber != null
            ? '${locale.tIn(l, 'vendor.doc.invoice')} ${data.invoiceNumber}'
            : fillIn(locale.tIn(l, 'vendor.pos.receiptNo'), {
                'number': data.number,
              }),
    ].join(' '),
  );
}

/// The seller's TIN and VRN for a sale's native receipt: the server's
/// document has them only when VAT applied to the sale (O-12). Asked only
/// with documents and VAT both on and the sale carrying VAT.
Future<({String? tin, String? vrn})> sellerTaxIdsFor(
  BuildContext context,
  ReceiptData data,
  VendorTools tools,
) async {
  if (!tools.documents || !tools.vat || !data.hasVat || data.id == null) {
    return (tin: null, vrn: null);
  }
  try {
    final res = await AppScope.of(context).api.vendorDocument('sale', data.id!);
    final d = res['doc'];
    if (d is! Map) return (tin: null, vrn: null);
    final doc = VendorDoc.fromJson(d);
    return (tin: doc.tin, vrn: doc.vrn);
  } catch (_) {
    return (tin: null, vrn: null);
  }
}
