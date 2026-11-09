// Vendor tools · S3: what a receipt shows, from a recorded sale (the server's
// `sale`) or from a sale still queued on this device, and the plain-text
// version shared through the system share sheet (spec §4.2).
import '../../../shared/formatters.dart';
import '../documents/document_models.dart' show DocVatRow, vatRowsOf;
import 'sale_models.dart';

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String? _str(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

class ReceiptLine {
  const ReceiptLine({
    required this.name,
    this.variant,
    required this.qty,
    required this.unitPriceTzs,
    required this.listPriceTzs,
    required this.discountTzs,
    required this.lineTotalTzs,
    this.priceChangedBy,
    this.vatCode,
    this.refundedQty = 0,
  });

  final String name;
  final String? variant;
  final int qty;
  final int unitPriceTzs;
  final int listPriceTzs;
  final int discountTzs;
  final int lineTotalTzs;
  final String? priceChangedBy;

  /// S5: the line's VAT code (A, C, E) when VAT applied to the sale.
  final String? vatCode;

  /// S7: units given back by active refunds.
  final int refundedQty;

  bool get priceChanged => unitPriceTzs != listPriceTzs;
}

class ReceiptPayment {
  const ReceiptPayment(this.method, this.amountTzs, this.reference);
  final String method;
  final int amountTzs;
  final String? reference;
}

class ReceiptData {
  const ReceiptData({
    this.id,
    this.number,
    this.clientRef,
    this.business,
    this.contact,
    this.address,
    required this.soldAt,
    this.recordedAt,
    this.servedBy,
    this.servedById,
    required this.lines,
    required this.subtotalTzs,
    required this.lineDiscountTzs,
    required this.saleDiscountTzs,
    required this.totalTzs,
    required this.payments,
    required this.changeTzs,
    this.status = 'completed',
    this.note,
    this.voidedBy,
    this.voidedAt,
    this.voidReason,
    this.lateRecorded = false,
    this.queued = false,
    this.kind = 'cash',
    this.customerId,
    this.customerName,
    this.customerForgotten = false,
    this.dueDate,
    this.balanceTzs = 0,
    this.balanceReducedTzs = 0,
    this.paidAtSaleTzs,
    this.allocations = const [],
    this.invoiceNumber,
    this.vatIncludedTzs = 0,
    this.vatSummary = const [],
    this.refundedTzs = 0,
    this.refundState = 'none',
    this.refunds = const [],
  });

  final String? id;
  final String? number;
  final String? clientRef;
  final String? business;
  final String? contact;
  final String? address;
  final String? soldAt;
  final String? recordedAt;
  final String? servedBy;
  final String? servedById;
  final List<ReceiptLine> lines;
  final int subtotalTzs;
  final int lineDiscountTzs;
  final int saleDiscountTzs;
  final int totalTzs;
  final List<ReceiptPayment> payments;
  final int changeTzs;
  final String status;
  final String? note;
  final String? voidedBy;
  final String? voidedAt;
  final String? voidReason;
  final bool lateRecorded;

  /// Still on this device: no receipt number yet.
  final bool queued;

  /// S4: `cash` or `credit` (pay later).
  final String kind;

  /// S4: the customer (name only, never contact details). A queued sale
  /// has the id only: its name shows after sync.
  final String? customerId;
  final String? customerName;

  /// The app buyer deleted their FitFlex account (the server's
  /// `customer.forgotten`). A null name alone never means deleted.
  final bool customerForgotten;

  /// The i18n key for a customer with no name: "Deleted member" when
  /// forgotten, else "FitFlex member".
  String get unnamedCustomerKey => customerForgotten
      ? 'vendor.customers.deletedMember'
      : 'vendor.orders.buyerUnnamed';

  /// Pay later: due day (YYYY-MM-DD) and what is still owed now.
  final String? dueDate;
  final int balanceTzs;

  /// S7: what active refunds took off a pay-later balance.
  final int balanceReducedTzs;

  /// Paid at the counter (later customer payments excluded).
  final int? paidAtSaleTzs;

  /// Paid at the counter: the server's paidAtSaleTzs, else the payments.
  int get paidNowTzs =>
      paidAtSaleTzs ?? payments.fold(0, (s, p) => s + p.amountTzs);

  /// What was left owing when the sale was made. A receipt is historical:
  /// it shows this, never the balance after later payments ([balanceTzs],
  /// shown on the sale detail and the profile only).
  int get balanceAtSaleTzs =>
      totalTzs - paidNowTzs < 0 ? 0 : totalTzs - paidNowTzs;

  /// Customer payments towards this sale (people with `customers` only):
  /// `{paymentId, number, amountTzs, receivedOn, voided}`.
  final List<Map<String, dynamic>> allocations;

  /// S5: a pay-later sale's invoice number (INV-…); the R-number is then
  /// its "Sale ref" (Q-7).
  final String? invoiceNumber;

  /// S5: VAT contained in the prices (0 when none applied) and the summary
  /// per code. Prices include VAT: the total never changes.
  final int vatIncludedTzs;
  final List<DocVatRow> vatSummary;

  bool get hasVat => vatIncludedTzs > 0 || vatSummary.isNotEmpty;

  /// S7: Σ active refunds (credit notes), returned whatever the flags.
  final int refundedTzs;

  /// S7: none | partial | full (every unit refunded).
  final String refundState;

  /// S7: every refund of the sale, active and undone, oldest first:
  /// `{id, number, status, refundedAt, amountTzs}`.
  final List<Map<String, dynamic>> refunds;

  /// What the sale is worth after its active refunds.
  int get netAfterRefundsTzs => totalTzs - refundedTzs;
  bool get hasActiveRefunds =>
      refunds.any((r) => r['status']?.toString() != 'reverted');

  bool get credit => kind == 'credit';
  bool get hasCustomer => customerId != null;

  /// Live (not voided) customer payments allocated to this sale.
  List<Map<String, dynamic>> get liveAllocations =>
      allocations.where((a) => a['voided'] != true).toList();

  bool get voided => status == 'voided';
  int get discountsTzs => lineDiscountTzs + saleDiscountTzs;
  String? get tempRef => clientRef == null ? null : tempRefOf(clientRef!);

  /// A sale as the server sends it (POST /vendor/sales, GET /vendor/sales/:id).
  ///
  /// S5: [documents] shows a pay-later sale's INV number and [vat] the VAT
  /// block, each only while the server reports that tool on (AC-1, AC-2).
  factory ReceiptData.fromSale(
    Map<String, dynamic> sale, {
    Map<String, dynamic> profile = const {},
    bool documents = false,
    bool vat = false,
  }) {
    final vatTzs = vat ? _int(sale['vatIncludedTzs']) : 0;
    // Zero-rated (C) and exempt (E) sales have rows but no VAT amount.
    final vatRows = vat ? vatRowsOf(sale['vatSummary']) : const <DocVatRow>[];
    final vatApplied = vatTzs > 0 || vatRows.isNotEmpty;
    Map? person(Object? v) => v is Map ? v : null;
    final soldAt = _str(sale['soldAt']);
    final recordedAt = _str(sale['recordedAt']);
    final late =
        sale['lateRecorded'] == true ||
        (sale['lateRecorded'] == null && recordedLate(soldAt, recordedAt));
    return ReceiptData(
      id: _str(sale['id']),
      number: _str(sale['number']),
      clientRef: _str(sale['clientRef']),
      business: _str(profile['businessName']),
      contact: _str(profile['contactNumber']),
      address: _str(profile['address']),
      soldAt: soldAt,
      recordedAt: recordedAt,
      servedBy: _str(person(sale['createdBy'])?['name']),
      servedById: _str(person(sale['createdBy'])?['id']),
      lines: [
        for (final l in (sale['lines'] as List? ?? []).whereType<Map>())
          ReceiptLine(
            name: _str(l['nameSnapshot']) ?? '',
            variant: _str(l['variant']),
            qty: _int(l['qty']),
            unitPriceTzs: _int(l['unitPriceTzs']),
            listPriceTzs: _int(l['listPriceTzs']),
            discountTzs: _int(l['discountTzs']),
            lineTotalTzs: _int(l['lineTotalTzs']),
            priceChangedBy: _str(person(l['priceChangedBy'])?['name']),
            vatCode: vatApplied ? _str(l['vatCode']) : null,
            refundedQty: _int(l['refundedQty']),
          ),
      ],
      subtotalTzs: _int(sale['subtotalTzs']),
      lineDiscountTzs: _int(sale['lineDiscountTzs']),
      saleDiscountTzs: _int(sale['discountTzs']),
      totalTzs: _int(sale['totalTzs']),
      payments: [
        for (final p in (sale['payments'] as List? ?? []).whereType<Map>())
          ReceiptPayment(
            p['method']?.toString() ?? 'other',
            _int(p['amountTzs']),
            _str(p['reference']),
          ),
      ],
      changeTzs: _int(sale['changeTzs']),
      status: sale['status']?.toString() ?? 'completed',
      note: _str(sale['note']),
      voidedBy: _str(person(sale['voidedBy'])?['name']),
      voidedAt: _str(sale['voidedAt']),
      voidReason: _str(sale['voidReason']),
      lateRecorded: late,
      kind: sale['kind']?.toString() == 'credit' ? 'credit' : 'cash',
      customerId: _str(person(sale['customer'])?['id']),
      customerName: _str(person(sale['customer'])?['name']),
      customerForgotten: person(sale['customer'])?['forgotten'] == true,
      dueDate: _str(sale['dueDate']),
      balanceTzs: _int(sale['balanceTzs']),
      balanceReducedTzs: _int(sale['balanceReducedTzs']),
      paidAtSaleTzs: sale['paidAtSaleTzs'] == null
          ? null
          : _int(sale['paidAtSaleTzs']),
      allocations: [
        for (final a in (sale['allocations'] as List? ?? []).whereType<Map>())
          Map<String, dynamic>.from(a),
      ],
      invoiceNumber: documents ? _str(sale['invoiceNumber']) : null,
      vatIncludedTzs: vatTzs,
      vatSummary: vatRows,
      refundedTzs: _int(sale['refundedTzs']),
      refundState: const {'partial', 'full'}.contains(sale['refundState'])
          ? sale['refundState'] as String
          : 'none',
      refunds: [
        for (final r in (sale['refunds'] as List? ?? []).whereType<Map>())
          Map<String, dynamic>.from(r),
      ],
    );
  }

  /// A queued sale: its request plus the snapshot taken when it was queued.
  factory ReceiptData.fromQueued(
    Map<String, dynamic> body,
    Map<String, dynamic> display,
  ) {
    final shown = (display['lines'] as List? ?? []).whereType<Map>().toList();
    final rows = (body['lines'] as List? ?? []).whereType<Map>().toList();
    final lines = <ReceiptLine>[];
    var subtotal = 0;
    var lineDiscounts = 0;
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final s = i < shown.length ? shown[i] : const {};
      final list = _int(s['listPriceTzs']);
      final price = r['unitPriceTzs'] == null ? list : _int(r['unitPriceTzs']);
      final qty = _int(r['qty']);
      final discount = _int(r['discountTzs']);
      subtotal += qty * price;
      lineDiscounts += discount;
      lines.add(
        ReceiptLine(
          name: _str(s['name']) ?? '',
          variant: _str(r['variant']),
          qty: qty,
          unitPriceTzs: price,
          listPriceTzs: list,
          discountTzs: discount,
          lineTotalTzs: qty * price - discount,
        ),
      );
    }
    final saleDiscount = _int(body['discountTzs']);
    final total = subtotal - lineDiscounts - saleDiscount;
    final payments = [
      for (final p in (body['payments'] as List? ?? []).whereType<Map>())
        ReceiptPayment(
          p['method']?.toString() ?? 'other',
          _int(p['amountTzs']),
          _str(p['reference']),
        ),
    ];
    final paid = payments.fold(0, (s, p) => s + p.amountTzs);
    return ReceiptData(
      clientRef: _str(body['clientRef']),
      business: _str(display['business']),
      contact: _str(display['contact']),
      address: _str(display['address']),
      soldAt: _str(body['soldAt']),
      servedBy: _str(display['servedBy']),
      lines: lines,
      subtotalTzs: subtotal,
      lineDiscountTzs: lineDiscounts,
      saleDiscountTzs: saleDiscount,
      totalTzs: total,
      payments: payments,
      changeTzs: paid > total ? paid - total : 0,
      note: _str(body['note']),
      queued: true,
      // The queue keeps the customer's id only (A-02): no name until sync.
      customerId: _str(body['customerId']),
    );
  }
}

/// Recorded more than 5 minutes after it was sold (an offline sale).
bool recordedLate(String? soldAt, String? recordedAt) {
  final sold = DateTime.tryParse(soldAt ?? '');
  final recorded = DateTime.tryParse(recordedAt ?? '');
  if (sold == null || recorded == null) return false;
  return recorded.difference(sold) > const Duration(minutes: 5);
}

/// "19 Oct 2026, 14:05" in East Africa time (UTC+3), whatever the device zone.
String eatDateTime(String? iso, {String locale = 'en'}) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return '';
  final eat = d.toUtc().add(const Duration(hours: 3));
  final local = DateTime(eat.year, eat.month, eat.day, eat.hour, eat.minute);
  return formatDateTime(local, locale: locale);
}

/// The EAT calendar day of an instant, for "same day" checks.
DateTime? eatDayOf(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return null;
  final eat = d.toUtc().add(const Duration(hours: 3));
  return DateTime.utc(eat.year, eat.month, eat.day);
}

/// WhatsApp on a phone shows about 32 characters a line (spec §4.2).
const receiptWidth = 32;

/// A label and an amount on one line, the amount right-aligned. When both
/// do not fit (a long method + reference), the label takes its own line and
/// the amount goes under it, still right-aligned, so the column holds.
String _row(String label, String amount, {String indent = ''}) {
  final left = '$indent$label';
  final gap = receiptWidth - left.length - amount.length;
  if (gap >= 1) return '$left${' ' * gap}$amount';
  final pad = receiptWidth - amount.length;
  return '$left\n${' ' * (pad < 0 ? 0 : pad)}$amount';
}

/// The receipt as plain text (spec §4.2), in the language [t] answers in.
/// [t] looks up an i18n key in the receipt's language.
String receiptShareText(
  ReceiptData r,
  String Function(String key) t,
  String lang,
) {
  String fill(String key, Map<String, Object?> v) {
    var out = t(key);
    v.forEach((k, val) => out = out.replaceAll('{$k}', '$val'));
    return out;
  }

  const rule = '--------------------';
  final b = StringBuffer();
  if (r.business != null) b.writeln(r.business);
  if (r.queued || r.number == null) {
    b.writeln(fill('vendor.pos.shareProvisional', {'ref': r.tempRef ?? ''}));
  } else if (r.credit && r.invoiceNumber != null) {
    // S5 (Q-7): a pay-later sale is an invoice; its R-number is the ref.
    b.writeln('${t('vendor.doc.invoice')} ${r.invoiceNumber}');
    b.writeln(fill('vendor.doc.saleRef', {'number': r.number}));
  } else {
    b.writeln(fill('vendor.pos.receiptNo', {'number': r.number}));
  }
  final when = eatDateTime(r.soldAt, locale: lang);
  if (when.isNotEmpty) b.writeln(when);
  if (r.hasCustomer) {
    b.writeln(
      r.customerName != null
          ? fill('vendor.receipt.customer', {'name': r.customerName})
          : r.queued
          ? t('vendor.receipt.customerAfterSync')
          : fill('vendor.receipt.customer', {'name': t(r.unnamedCustomerKey)}),
    );
  }
  b.writeln(rule);
  for (final l in r.lines) {
    final name = l.variant == null ? l.name : '${l.name} (${l.variant})';
    final gross = l.qty * l.unitPriceTzs;
    if (l.qty > 1 || l.priceChanged) {
      b.writeln('${l.qty} x $name');
      b.writeln(
        _row(
          '@ ${formatMoney(l.unitPriceTzs)}',
          formatMoney(gross),
          indent: '   ',
        ),
      );
    } else {
      b.writeln(_row('${l.qty} x $name', formatMoney(gross)));
    }
    if (l.discountTzs > 0) {
      b.writeln(
        _row(
          t('vendor.pos.lineDiscountShort'),
          '-${formatMoney(l.discountTzs)}',
          indent: '   ',
        ),
      );
    }
  }
  b.writeln(rule);
  b.writeln(_row(t('vendor.pos.subtotal'), formatMoney(r.subtotalTzs)));
  if (r.discountsTzs > 0) {
    b.writeln(
      _row(t('vendor.pos.discounts'), '-${formatMoney(r.discountsTzs)}'),
    );
  }
  b.writeln(_row(t('vendor.pos.total'), formatCurrency(r.totalTzs)));
  if (r.hasVat) {
    // S5: VAT is inside the prices; the total is unchanged.
    b.writeln(
      fill('vendor.doc.includesVat', {
        'amount': formatCurrency(r.vatIncludedTzs),
      }),
    );
  }
  for (final p in r.payments) {
    final method = t(paymentMethodKey(p.method));
    b.writeln(
      _row(
        p.reference == null ? method : '$method (${p.reference})',
        formatMoney(p.amountTzs),
      ),
    );
  }
  if (r.credit) {
    // Pay later: never "Change".
    b.writeln(_row(t('vendor.pos.credit.paidNow'), formatMoney(r.paidNowTzs)));
    b.writeln(
      _row(t('vendor.receipt.balanceAtSale'), formatMoney(r.balanceAtSaleTzs)),
    );
    if (r.dueDate != null) {
      b.writeln(_row(t('vendor.receipt.dueBy'), _dayText(r.dueDate!, lang)));
    }
  } else if (r.changeTzs > 0) {
    b.writeln(_row(t('vendor.pos.change'), formatMoney(r.changeTzs)));
  }
  // S7 §6.3: after the payments, the active credit notes ("CN-000004 ·
  // 3 Nov 2026  -6,666") under a Refunds heading, and the total after them.
  if (r.refundedTzs > 0 && !r.voided) {
    b.writeln(t('vendor.doc.refundsOnSale'));
    for (final rf in r.refunds) {
      if (rf['status']?.toString() == 'reverted') continue;
      final day = eatDayOf(rf['refundedAt']?.toString());
      final label = [
        '${rf['number'] ?? ''}',
        if (day != null)
          formatDate(DateTime(day.year, day.month, day.day), locale: lang),
      ].join(' · ');
      b.writeln(_row(label, '-${formatMoney(_int(rf['amountTzs']))}'));
    }
    b.writeln(
      _row(
        t('vendor.doc.totalAfterRefunds'),
        formatCurrency(r.netAfterRefundsTzs),
      ),
    );
  }
  b.writeln(rule);
  if (r.servedBy != null) {
    b.writeln(fill('vendor.pos.servedBy', {'name': r.servedBy}));
  }
  if (r.business != null) {
    b.writeln(
      fill(
        r.credit ? 'vendor.receipt.closingCredit' : 'vendor.pos.receiptFooter',
        {'business': r.business},
      ),
    );
  }
  b.write(t('vendor.pos.notFiscal'));
  return b.toString();
}

/// "27 Oct 2026" for an EAT day (YYYY-MM-DD).
String _dayText(String day, String lang) {
  final d = DateTime.tryParse(day);
  if (d == null) return day;
  return formatDate(DateTime(d.year, d.month, d.day), locale: lang);
}

/// Public for the receipt view.
String receiptDay(String? day, String lang) =>
    day == null ? '' : _dayText(day, lang);
