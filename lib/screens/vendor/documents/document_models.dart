// Vendor tools · S5 (documents): what the app reads from the server's
// document JSON, share links and link lists (fitflex-functions #229,
// design spec docs/design/vendor-documents-s5.md). Pure Dart: no widgets,
// storage or network, so the rules are tested on their own.
//
// Privacy (§0 ground rules, A-02): the server's document never carries a
// customer's phone, email or address. The only phone the app ever puts in
// a WhatsApp or SMS link is a WALK-IN customer's (vendor-owned data, from
// the customer record); an app buyer's never.
import '../customers/customer_models.dart' show normaliseTzPhone;

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String? _str(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// What a share sheet is for: the route `kind` the server takes
/// (`sale`, `order`, `payment`, `statement`) and the id it names.
class DocumentRef {
  const DocumentRef({
    required this.kind,
    required this.id,
    this.customerId,
    required this.titleKey,
    this.number,
  });

  /// A walk-in sale: a cash receipt (`R-`) or a pay-later invoice (`INV-`).
  factory DocumentRef.sale({
    required String saleId,
    required bool credit,
    String? number,
  }) => DocumentRef(
    kind: 'sale',
    id: saleId,
    titleKey: credit ? 'vendor.doc.invoice' : 'vendor.doc.receipt',
    number: number,
  );

  /// My invoice for an app order (`INV-`).
  factory DocumentRef.order({required String orderId, String? number}) =>
      DocumentRef(
        kind: 'order',
        id: orderId,
        titleKey: 'vendor.doc.order_invoice',
        number: number,
      );

  /// A customer payment receipt (`PMT-`).
  factory DocumentRef.payment({
    required String customerId,
    required String paymentId,
    String? number,
  }) => DocumentRef(
    kind: 'payment',
    id: paymentId,
    customerId: customerId,
    titleKey: 'vendor.doc.payment_receipt',
    number: number,
  );

  /// A customer statement (the link is a snapshot as of the share time).
  factory DocumentRef.statement({required String customerId}) => DocumentRef(
    kind: 'statement',
    id: customerId,
    customerId: customerId,
    titleKey: 'vendor.doc.statement',
  );

  /// S7: a refund's credit note (`CN-`). Its share route is
  /// POST /vendor/refunds/:id/share; links and the PDF use `refund`.
  factory DocumentRef.refund({required String refundId, String? number}) =>
      DocumentRef(
        kind: 'refund',
        id: refundId,
        titleKey: 'vendor.doc.credit_note',
        number: number,
      );

  /// `sale` | `order` | `payment` | `statement` | `refund` (the share route
  /// and the links list's `docType`).
  final String kind;

  /// The sale, order or payment id; the customer id for a statement.
  final String id;

  /// The customer of a payment (its share route names it).
  final String? customerId;

  /// The document's title, e.g. `vendor.doc.receipt`.
  final String titleKey;

  /// R-…, INV-… or PMT-…; null for a statement.
  final String? number;

  /// The `docType` of GET /vendor/document-links and revoke-all.
  String get linksDocType => kind;

  /// The `:docType` of GET /vendor/documents/:docType/:docId.
  String get viewDocType => kind;
}

/// A link just made (POST …/share, 201). The URL exists only here: the
/// server keeps its hash, so it can never be listed again (O-5).
class SharedLink {
  const SharedLink({
    required this.linkId,
    required this.url,
    required this.lang,
    required this.texts,
    this.number,
  });

  factory SharedLink.fromJson(Map json) {
    final texts = <String, ({String whatsapp, String sms})>{};
    final raw = json['texts'];
    if (raw is Map) {
      for (final lang in const ['en', 'sw']) {
        final t = raw[lang];
        if (t is Map) {
          texts[lang] = (
            whatsapp: t['whatsapp']?.toString() ?? '',
            sms: t['sms']?.toString() ?? '',
          );
        }
      }
    }
    final lang = json['lang']?.toString() == 'sw' ? 'sw' : 'en';
    // An answer without both languages still has the one asked for.
    texts.putIfAbsent(
      lang,
      () => (
        whatsapp: json['whatsappText']?.toString() ?? '',
        sms: json['smsText']?.toString() ?? '',
      ),
    );
    return SharedLink(
      linkId: json['linkId']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      lang: lang,
      texts: texts,
      number: _str(json['number']),
    );
  }

  final String linkId;

  /// As made: `{PUBLIC_API_URL}/d/{token}` (+ `?lang=sw` when made in SW).
  final String url;
  final String lang;
  final Map<String, ({String whatsapp, String sms})> texts;
  final String? number;

  /// The same link opening in [lang] (§2.2: changing the language after a
  /// link exists makes no new link; the client sets `?lang=`). As the
  /// server writes it: the link's own language keeps the URL as made;
  /// the other one adds `?lang=`.
  String urlIn(String lang) {
    if (lang == this.lang) return url;
    return withLang(withoutLang(url), lang);
  }

  /// WhatsApp text in [lang]; the server wrote it (the client never builds
  /// it). When the server sent no text in that language, the URL alone.
  String whatsappIn(String lang) => _text(lang, (t) => t.whatsapp);
  String smsIn(String lang) => _text(lang, (t) => t.sms);

  String _text(
    String lang,
    String Function(({String whatsapp, String sms})) f,
  ) {
    final t = texts[lang];
    if (t != null && f(t).isNotEmpty) return f(t);
    return urlIn(lang);
  }
}

/// [url] with `lang=` set to [lang], other query parts kept.
String withLang(String url, String lang) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final q = Map<String, String>.from(uri.queryParameters)..['lang'] = lang;
  return uri.replace(queryParameters: q).toString();
}

/// [url] without its `lang=` query part.
String withoutLang(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.queryParameters.containsKey('lang')) return url;
  final q = Map<String, String>.from(uri.queryParameters)..remove('lang');
  return uri.replace(queryParameters: q.isEmpty ? null : q).toString();
}

/// One row of GET /vendor/document-links (never the URL).
class DocumentLinkRow {
  const DocumentLinkRow({
    required this.id,
    required this.n,
    required this.lang,
    this.createdAt,
    this.createdByName,
    this.lastOpenedAt,
    this.revokedAt,
    required this.active,
  });

  factory DocumentLinkRow.fromJson(Map json) {
    final by = json['createdBy'];
    return DocumentLinkRow(
      id: json['id']?.toString() ?? '',
      n: _int(json['n']),
      lang: json['lang']?.toString() == 'sw' ? 'sw' : 'en',
      createdAt: _str(json['createdAt']),
      createdByName: by is Map ? _str(by['firstName']) : null,
      lastOpenedAt: _str(json['lastOpenedAt']),
      revokedAt: _str(json['revokedAt']),
      active: json['active'] == true && json['revokedAt'] == null,
    );
  }

  final String id;
  final int n;
  final String lang;
  final String? createdAt;
  final String? createdByName;
  final String? lastOpenedAt;
  final String? revokedAt;
  final bool active;
}

List<DocumentLinkRow> linkRowsOf(Object? json) => [
  if (json is Map)
    for (final r in (json['links'] as List? ?? []).whereType<Map>())
      DocumentLinkRow.fromJson(r),
];

/// The digits of a WALK-IN customer's phone for wa.me / sms: (no `+`), or
/// null. An app customer (`source: marketplace`) never has one here: the
/// server does not send it, and the app never fills it in (§2.1).
String? walkInPhoneDigits(Map? customer) {
  if (customer == null || customer['source']?.toString() != 'manual') {
    return null;
  }
  final phone = _str(customer['phone']);
  if (phone == null) return null;
  // wa.me needs the international form without "+": 0712… → 255712….
  final tz = normaliseTzPhone(phone);
  if (tz != null) return tz.substring(1);
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 9 ? digits : null;
}

/// `https://wa.me/{phone?}?text=…` (§2.1).
Uri whatsAppUri(String text, {String? phone}) =>
    Uri.parse('https://wa.me/${phone ?? ''}?text=${Uri.encodeComponent(text)}');

/// `sms:{phone?}?body=…` (Android; O-7: the device sends it, never FitFlex).
Uri smsUri(String text, {String? phone}) =>
    Uri.parse('sms:${phone ?? ''}?body=${Uri.encodeComponent(text)}');

// ── document JSON (GET /vendor/documents/:docType/:docId?format=json) ──────

class DocLine {
  const DocLine({
    required this.name,
    this.variant,
    required this.qty,
    required this.unitPriceTzs,
    required this.discountTzs,
    required this.amountTzs,
    this.vatCode,
  });
  final String name;
  final String? variant;
  final int qty;
  final int unitPriceTzs;
  final int discountTzs;
  final int amountTzs;
  final String? vatCode;
}

class DocVatRow {
  const DocVatRow({
    required this.code,
    this.ratePct,
    required this.netTzs,
    required this.vatTzs,
  });
  final String code;

  /// Null for exempt (shown "Exempt", never "0%").
  final num? ratePct;
  final int netTzs;
  final int vatTzs;
}

class DocPayment {
  const DocPayment(this.method, this.amountTzs, this.reference);
  final String method;
  final int amountTzs;
  final String? reference;
}

/// The server's document, read defensively (every field optional).
class VendorDoc {
  const VendorDoc({
    required this.docType,
    this.number,
    this.saleRef,
    this.orderShortRef,
    this.status,
    this.issuedAt,
    this.businessName,
    this.address,
    this.contactNumber,
    this.tin,
    this.vrn,
    this.soldVia,
    this.customerName,
    this.servedBy,
    this.dueDate,
    this.lines = const [],
    this.subtotalTzs = 0,
    this.discountsTzs = 0,
    this.totalTzs = 0,
    this.vatIncludedTzs = 0,
    this.vatSummary = const [],
    this.payments = const [],
    this.changeTzs = 0,
    this.paidNowTzs,
    this.liveBalanceTzs,
    this.liveAsOf,
    this.paidInFullAt,
    this.paidWith = const [],
    this.paidTowards = const [],
    this.stillOwedTzs,
    this.paymentMethod,
    this.cancelledAt,
    this.vendorId,
  });

  factory VendorDoc.fromJson(Map json) {
    final seller = json['seller'] is Map ? json['seller'] as Map : const {};
    final live = json['liveStatus'] is Map ? json['liveStatus'] as Map : null;
    return VendorDoc(
      docType: json['docType']?.toString() ?? 'receipt',
      number: _str(json['number']),
      // S7: a credit note's saleRef is `{number, invoiceNumber?, soldAt}`.
      saleRef: json['saleRef'] is Map
          ? _str((json['saleRef'] as Map)['number'])
          : _str(json['saleRef']),
      orderShortRef: _str(json['orderShortRef']),
      status: _str(json['status']),
      issuedAt: _str(json['issuedAt']),
      businessName: _str(seller['businessName']),
      address: _str(seller['address']),
      contactNumber: _str(seller['contactNumber']),
      tin: _str(seller['tin']),
      vrn: _str(seller['vrn']),
      soldVia: _str(json['soldVia']),
      customerName: json['customer'] is Map
          ? _str((json['customer'] as Map)['name'])
          : null,
      servedBy: json['servedBy'] is Map
          ? _str((json['servedBy'] as Map)['firstName'])
          : null,
      dueDate: _str(json['dueDate']),
      lines: [
        for (final l in (json['lines'] as List? ?? []).whereType<Map>())
          DocLine(
            name: _str(l['name']) ?? '',
            variant: _str(l['variant']),
            qty: _int(l['qty']),
            unitPriceTzs: _int(l['unitPriceTzs']),
            discountTzs: _int(l['discountTzs']),
            amountTzs: _int(l['amountTzs']),
            vatCode: _str(l['vatCode']),
          ),
      ],
      subtotalTzs: _int(json['subtotalTzs']),
      discountsTzs: _int(json['discountsTzs']),
      totalTzs: _int(json['totalTzs']),
      vatIncludedTzs: _int(json['vatIncludedTzs']),
      vatSummary: vatRowsOf(json['vatSummary']),
      payments: [
        for (final p in (json['payments'] as List? ?? []).whereType<Map>())
          DocPayment(
            p['method']?.toString() ?? 'other',
            _int(p['amountTzs']),
            _str(p['reference']),
          ),
      ],
      changeTzs: _int(json['changeTzs']),
      paidNowTzs: json['paidNowTzs'] == null ? null : _int(json['paidNowTzs']),
      liveBalanceTzs: live == null ? null : _int(live['balanceTzs']),
      liveAsOf: live == null ? null : _str(live['asOf']),
      paidInFullAt: live == null ? null : _str(live['paidInFullAt']),
      paidWith: [
        if (live != null)
          for (final n in (live['paidWith'] as List? ?? [])) '$n',
      ],
      paidTowards: [
        for (final a in (json['paidTowards'] as List? ?? []).whereType<Map>())
          (
            number: a['number']?.toString() ?? '',
            amountTzs: _int(a['amountTzs']),
          ),
      ],
      stillOwedTzs: json['stillOwedTzs'] == null
          ? null
          : _int(json['stillOwedTzs']),
      paymentMethod: _str(json['paymentMethod']),
      cancelledAt: _str(json['cancelledAt']),
      vendorId: _str(json['vendorId']),
    );
  }

  final String docType;
  final String? number;
  final String? saleRef;
  final String? orderShortRef;

  /// paid | pay_later | paid_in_full | cancelled | null (statement).
  final String? status;
  final String? issuedAt;
  final String? businessName;
  final String? address;
  final String? contactNumber;

  /// Only when VAT applied to this document (VRN verified, O-12).
  final String? tin;
  final String? vrn;

  /// Order invoice: "Seller: {business}. Sold through the FitFlex app."
  /// (server text, in the document's language).
  final String? soldVia;
  final String? customerName;
  final String? servedBy;
  final String? dueDate;
  final List<DocLine> lines;
  final int subtotalTzs;
  final int discountsTzs;
  final int totalTzs;
  final int vatIncludedTzs;
  final List<DocVatRow> vatSummary;
  final List<DocPayment> payments;
  final int changeTzs;
  final int? paidNowTzs;
  final int? liveBalanceTzs;
  final String? liveAsOf;
  final String? paidInFullAt;
  final List<String> paidWith;
  final List<({String number, int amountTzs})> paidTowards;
  final int? stillOwedTzs;
  final String? paymentMethod;
  final String? cancelledAt;

  /// Buyer invoices: which seller this one is from.
  final String? vendorId;

  bool get cancelled => status == 'cancelled';
  bool get hasVat => vatIncludedTzs > 0 || vatSummary.isNotEmpty;

  /// `vendor.doc.<docType>` (Receipt, Invoice, …).
  String get titleKey => 'vendor.doc.$docType';
}

/// A VAT summary list (`[{code, ratePct|null, netTzs, vatTzs}]`).
List<DocVatRow> vatRowsOf(Object? raw) => [
  for (final r in (raw is List ? raw : const []).whereType<Map>())
    DocVatRow(
      code: r['code']?.toString() ?? '',
      ratePct: r['ratePct'] is num
          ? r['ratePct'] as num
          : num.tryParse('${r['ratePct']}'),
      netTzs: _int(r['netTzs']),
      vatTzs: _int(r['vatTzs']),
    ),
];

/// "18%" / "16.5%" / "0%"; null for exempt.
String? ratePctText(num? pct) {
  if (pct == null) return null;
  final whole = pct == pct.roundToDouble();
  return '${whole ? pct.toInt() : pct}%';
}

// ── tax profile (GET/PUT /vendor/tax-profile) ─────────────────────────────

class TaxProfile {
  const TaxProfile({
    this.vatRegistered = false,
    this.tin,
    this.tinFromKyc = false,
    this.vrn,
    this.certificateDocumentId,
    this.status = 'none',
    this.rejectReason,
    this.rejectNote,
    this.verifiedAt,
    this.inForce = false,
    this.changePending = false,
    this.everVerified = false,
    this.certificateStands = true,
    this.updatedAt,
  });

  factory TaxProfile.fromJson(Map json) {
    final p = json['taxProfile'] is Map ? json['taxProfile'] as Map : json;
    final verified = p['verified'] is Map ? p['verified'] as Map : null;
    final pending = p['pending'] is Map ? p['pending'] as Map : null;
    final status = _str(p['status']) ?? 'none';
    return TaxProfile(
      vatRegistered: p['vatRegistered'] == true,
      // A change waiting for review: the form shows what was sent.
      tin: _str(pending?['tin']) ?? _str(p['tin']),
      tinFromKyc: p['tinFromKyc'] == true,
      vrn: _str(pending?['vrn']) ?? _str(p['vrn']),
      certificateDocumentId:
          _str(pending?['certificateDocumentId']) ??
          _str(p['certificateDocumentId']),
      status: const {'none', 'pending', 'verified', 'rejected'}.contains(status)
          ? status
          : 'none',
      rejectReason: _str(p['rejectReason']),
      rejectNote: _str(p['rejectNote']),
      verifiedAt: _str(p['verifiedAt']) ?? _str(verified?['verifiedAt']),
      inForce: p['inForce'] == true,
      changePending: p['changePending'] == true,
      everVerified: verified != null || status == 'verified',
      certificateStands: verified == null
          ? true
          : verified['certificateStands'] != false,
      updatedAt: _str(p['updatedAt']),
    );
  }

  final bool vatRegistered;
  final String? tin;
  final bool tinFromKyc;
  final String? vrn;
  final String? certificateDocumentId;

  /// none | pending | verified | rejected.
  final String status;
  final String? rejectReason;
  final String? rejectNote;
  final String? verifiedAt;

  /// VAT, TIN and VRN are on new sales and documents right now.
  final bool inForce;
  final bool changePending;

  /// The vendor's details were verified at some point (the product VAT
  /// code field shows from then on, §6.4).
  final bool everVerified;

  /// False once a reviewer rejected, or the expiry of, the verified
  /// certificate: VAT stopped and the vendor must send it again.
  final bool certificateStands;
  final String? updatedAt;
}

/// The reject reasons the server sends (§10.3).
const taxRejectReasons = {
  'unreadable',
  'number_mismatch',
  'name_mismatch',
  'not_vat_certificate',
  'other',
};

/// TIN: 9 digits once dashes and spaces are removed (as the server).
String? normaliseTin(String raw) {
  final s = raw.replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^\d{9}$').hasMatch(s) ? s : null;
}

/// VRN: 8–15 letters/digits once dashes and spaces are removed, upper case
/// (free format until counsel confirms it, Q-12).
String? normaliseVrn(String raw) {
  final s = raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  return RegExp(r'^[A-Z0-9]{8,15}$').hasMatch(s) ? s : null;
}

/// One VAT code a product may use (GET /vendor/tax-rates).
class VatCodeOption {
  const VatCodeOption({required this.code, this.ratePct, this.exempt = false});
  final String code;
  final num? ratePct;
  final bool exempt;
}

/// The codes the server offers (A, C, E today; B and D only once counsel
/// confirms them and the server lists them).
List<VatCodeOption> vatCodesOf(Object? json) => [
  if (json is Map)
    for (final c in (json['codes'] as List? ?? []).whereType<Map>())
      if (const {'A', 'B', 'C', 'D', 'E'}.contains(c['code']?.toString()))
        VatCodeOption(
          code: c['code'].toString(),
          ratePct: c['ratePct'] is num ? c['ratePct'] as num : null,
          exempt: c['exempt'] == true,
        ),
];
