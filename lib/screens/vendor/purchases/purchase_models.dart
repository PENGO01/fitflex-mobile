// Vendor tools · S9: suppliers, receiving stock (GRN) and what is owed to
// suppliers (design spec docs/design/vendor-purchases-s9.md, backend
// fitflex-functions#327). The rules the screens share, without widgets:
// routes, the gate every purchase route passes, the even split of an
// instalment plan, the coverage preview (mirrors P-5), who may void (M2),
// error words and the text share.
//
// FitFlex moves no money for payables: these are records only. Online only:
// nothing here is ever queued.
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../customers/customer_models.dart'
    show addDaysTo, daysBetween, dayString, eatTodayString, parseDay;
import '../sales/receipt_data.dart' show eatDayOf;
import '../sales/sale_models.dart' show paymentMethodKey, pluralKey;
import '../stock/stock_options.dart';

// ── limits (server src/shared/vendor-purchase.mjs) ──────────────────────

const purchaseMaxLines = 200;
const purchaseMaxQty = 100000;
const purchaseMaxUnitCost = 100000000;
const purchaseMaxTotal = 1000000000;
const purchaseMaxInstalments = 12;
const purchaseReceivedBackDays = 30;
const purchaseDueMaxDays = 365;
const purchaseDefaultDueDays = 30;
const purchaseInvoiceRefMax = 60;
const purchaseNoteMax = 200;
const purchasePaymentNoteMax = 200;
const purchaseReasonMin = 3;
const purchaseReasonMax = 200;
const supplierNameMin = 2;
const supplierNameMax = 120;
const supplierFieldMax = {
  'phone': 20,
  'email': 254,
  'contactPerson': 120,
  'address': 300,
  'tin': 20,
  'note': 500,
};

// ── routes ──────────────────────────────────────────────────────────────

const purchasesHubRoute = '/vendor/home?open=products&view=purchases';
const purchasesListRoute = '/vendor/purchases';
const receiveStockRoute = '/vendor/purchases/receive';
String receiveFromRoute(String supplierId) =>
    '$receiveStockRoute?supplierId=${Uri.encodeQueryComponent(supplierId)}';
String purchaseRoute(String id) =>
    '/vendor/purchases/${Uri.encodeComponent(id)}';
const suppliersRoute = '/vendor/suppliers';
const newSupplierRoute = '/vendor/suppliers/new';
String supplierRoute(String id) =>
    '/vendor/suppliers/${Uri.encodeComponent(id)}';
String editSupplierRoute(String id) => '${supplierRoute(id)}/edit';
const payablesRoute = '/vendor/payables';

/// Ids in purchase and supplier addresses (`vpo_…`, `vsp_…`): the app's
/// `_safeId`.
final purchaseIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// The Purchases view may show: the tool is on and this person has
/// `purchases`.
bool purchasesOn(VendorTools tools, bool Function(String) can) =>
    tools.purchases && can('purchases');

/// Checks a purchase route may open (spec §3.1): the tool off → the vendor
/// home with no message; no `purchases` → the home (first allowed section)
/// with "no access". Answers null when it left.
Future<VendorTools?> enterPurchasesRoute(BuildContext context) async {
  final tools = await VendorToolsOptions.of(context);
  if (!context.mounted) return null;
  if (!tools.purchases) {
    context.go('/vendor/home');
    return null;
  }
  // The session may predate the `purchases` backfill: ask the server's
  // stored staff record once before refusing.
  if (!canVendor(context, 'purchases')) await refreshVendorAccess(context);
  if (!context.mounted) return null;
  if (!canVendor(context, 'purchases')) {
    FFSnack.error(context, context.tr('vendor.purchases.noAccess'));
    context.go('/vendor/home');
    return null;
  }
  return tools;
}

/// Vendor staff: replaces the session's permissions with the server's
/// (GET /vendor/me, the stored staff record). Answers whether they changed.
/// Quiet: any failure (VENDOR_PORTAL off → 404, offline) keeps the session's.
Future<bool> refreshVendorAccess(BuildContext context) async {
  final scope = AppScope.of(context);
  if (scope.auth.user?['userType'] != 'vendor_staff') return false;
  try {
    final me = await scope.api.vendorMe();
    final perms = me['permissions'];
    if (perms is! List) return false;
    return await scope.auth.updateVendorAccess(
      permissions: [for (final p in perms) p.toString()],
      vendorRole: me['vendorRole']?.toString(),
    );
  } catch (_) {
    return false;
  }
}

int intOfP(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String? strOf(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

Map<String, dynamic> mapOf(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> mapsOf(Object? v) => [
  for (final e in (v is List ? v : const []))
    if (e is Map) Map<String, dynamic>.from(e),
];

/// A new idempotency key (128 random bits). Never ends in `:paid`, which the
/// server keeps for the payment made at receipt.
String newPurchaseClientRef(String prefix, [Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return '${prefix}_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

// ── instalment plans ────────────────────────────────────────────────────

/// One row of a plan being typed: an EAT due day and an amount.
class PlanRow {
  PlanRow(this.dueDate, this.amountTzs);
  String dueDate;
  int amountTzs;

  Map<String, dynamic> toJson() => {'dueDate': dueDate, 'amountTzs': amountTzs};

  static PlanRow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final d = raw['dueDate']?.toString();
    if (parseDay(d) == null) return null;
    return PlanRow(d!, intOfP(raw['amountTzs']));
  }
}

/// How often instalments fall due when split evenly.
enum PlanEvery { twoWeeks, month }

/// [day] moved [months] calendar months on (the day kept, else the month's
/// last day: 31 Jan → 28 Feb).
String addMonthsTo(String day, int months) {
  final d = parseDay(day)!;
  final m0 = d.month - 1 + months;
  final y = d.year + (m0 ~/ 12);
  final m = m0 % 12 + 1;
  final last = DateTime.utc(y, m + 1, 0).day;
  return dayString(DateTime.utc(y, m, min(d.day, last)));
}

/// The even split (spec §0.4): what is left after [paidNow] in [n] rows from
/// [firstDue], every [every]; each row the floor of the share, the last one
/// takes the remainder. Never a row below 1 (fewer rows when the amount is
/// smaller than [n]).
List<PlanRow> scheduleFor(
  int total,
  int paidNow,
  int n,
  String firstDue, {
  PlanEvery every = PlanEvery.month,
}) {
  final left = total - paidNow;
  if (left <= 0 || n < 1 || parseDay(firstDue) == null) return [];
  final count = min(n, left);
  final share = left ~/ count;
  return [
    for (var i = 0; i < count; i++)
      PlanRow(
        every == PlanEvery.month
            ? addMonthsTo(firstDue, i)
            : addDaysTo(firstDue, 14 * i),
        i == count - 1 ? left - share * (count - 1) : share,
      ),
  ];
}

/// One instalment as the server sends it (active plan, in cover order).
class Instalment {
  Instalment({
    required this.seq,
    required this.dueDate,
    required this.amountTzs,
    required this.coveredTzs,
    required this.openTzs,
    required this.state,
    required this.daysOverdue,
  });

  factory Instalment.fromJson(Map m) => Instalment(
    seq: intOfP(m['seq']),
    dueDate: m['dueDate']?.toString() ?? '',
    amountTzs: intOfP(m['amountTzs']),
    coveredTzs: intOfP(m['coveredTzs']),
    openTzs: intOfP(m['openTzs']),
    state: m['state']?.toString() ?? 'due',
    daysOverdue: intOfP(m['daysOverdue']),
  );

  final int seq;
  final String dueDate;
  final int amountTzs;
  final int coveredTzs;
  final int openTzs;
  final String state;
  final int daysOverdue;
}

List<Instalment> instalmentsOf(Map? purchase) => [
  for (final m in mapsOf(purchase?['instalments'])) Instalment.fromJson(m),
];

/// What a payment of [amount] covers, oldest due first (P-5; the server's
/// `coveredBy`): each instalment it reaches and how much of it, and whether
/// that pays the instalment off.
class CoveredPart {
  CoveredPart(this.instalment, this.amountTzs);
  final Instalment instalment;
  final int amountTzs;
  bool get paysOff => instalment.coveredTzs + amountTzs >= instalment.amountTzs;
}

List<CoveredPart> previewCoverage(List<Instalment> plan, int amount) {
  final out = <CoveredPart>[];
  var left = amount;
  for (final i in plan) {
    if (left <= 0) break;
    if (i.openTzs <= 0) continue;
    final take = min(left, i.openTzs);
    out.add(CoveredPart(i, take));
    left -= take;
  }
  return out;
}

/// An instalment's state in words (never a code).
String instalmentStateText(String Function(String) t, Instalment i) {
  switch (i.state) {
    case 'paid':
      return t('vendor.purchases.inst.paid');
    case 'part_paid':
      return fillIn(t('vendor.purchases.inst.part'), {
        'covered': formatCurrency(i.coveredTzs),
        'amount': formatCurrency(i.amountTzs),
      });
    case 'overdue':
      return fillIn(
        t(pluralKey('vendor.purchases.inst.overdue', i.daysOverdue)),
        {'n': i.daysOverdue},
      );
  }
  return '';
}

/// "Due in 5 days" / "Due today" for an instalment not yet due.
String dueText(String Function(String) t, String dueDate, String today) {
  final d = parseDay(dueDate) == null ? 0 : daysBetween(dueDate, today);
  if (d <= 0) return t('vendor.purchases.inst.dueToday');
  return fillIn(t(pluralKey('vendor.purchases.inst.dueIn', d)), {'n': d});
}

// ── who may void (M2, mirrors the server) ───────────────────────────────

/// The vendor account and `vendorRole=admin` staff void anything; other
/// staff with `purchases` only a record they made, on the EAT day they made
/// it. The server still decides (403 void_not_allowed).
bool canVoidPurchaseRecord(
  Map<String, dynamic>? user, {
  String? byId,
  String? at,
  DateTime? now,
}) {
  final type = user?['userType']?.toString();
  if (type == 'vendor') return true;
  if (type != 'vendor_staff') return false;
  final perms = (user?['vendorPermissions'] as List? ?? []);
  if (!perms.contains('purchases')) return false;
  if (user?['vendorRole']?.toString() == 'admin') return true;
  if (byId == null || byId != user?['id']?.toString()) return false;
  final day = eatDayOf(at);
  return day != null && dayString(day) == eatTodayString(now);
}

/// Whether the server would refuse [user]'s purchase void with
/// `has_others_payments`: staff who are not admin, and an active payment on
/// it recorded by someone else (#327 security review; as the portal).
bool othersPaymentsBlockVoid(Map<String, dynamic>? user, Map purchase) {
  if (user?['userType']?.toString() != 'vendor_staff') return false;
  if (user?['vendorRole']?.toString() == 'admin') return false;
  final me = user?['id']?.toString();
  return mapsOf(
    purchase['payments'],
  ).any((p) => p['status'] != 'voided' && idOf(p['recordedBy']) != me);
}

String? idOf(Object? person) => person is Map ? person['id']?.toString() : null;
String? nameOf(Object? person) => person is Map ? strOf(person['name']) : null;

// ── words ───────────────────────────────────────────────────────────────

/// The payment badge's key: Overdue beats Part paid / Unpaid.
String paymentStateKey(Map p) {
  if (p['status'] == 'voided') return 'vendor.purchases.state.voided';
  if (intOfP(p['overdueTzs']) > 0) return 'vendor.purchases.state.overdue';
  return switch (p['paymentState']?.toString()) {
    'paid' => 'vendor.purchases.state.paid',
    'part_paid' => 'vendor.purchases.state.part_paid',
    _ => 'vendor.purchases.state.unpaid',
  };
}

FFBadgeTone paymentStateTone(Map p) {
  if (p['status'] == 'voided') return FFBadgeTone.gray;
  if (intOfP(p['overdueTzs']) > 0) return FFBadgeTone.warning;
  return switch (p['paymentState']?.toString()) {
    'paid' => FFBadgeTone.success,
    'part_paid' => FFBadgeTone.info,
    _ => FFBadgeTone.gray,
  };
}

/// Where the receive screen shows a refusal.
enum PurchaseErrorPlace { supplier, line, payment, details, general }

/// The words for an S9 error code (spec §8.6; the raw code is never shown).
/// [where]: `receive`, `payment` (record a payment), `void`,
/// `paymentVoid`, `plan` or `supplier`.
String purchaseErrorText(
  String Function(String) t,
  ApiException e, {
  String where = 'receive',
  String? name,
}) {
  final b = e.body is Map ? e.body as Map : const {};
  String fill(String key, Map<String, Object?> v) => fillIn(t(key), v);
  switch (e.code) {
    case 'product_not_found' || 'product_unavailable':
      return fill('vendor.purchases.err.productGone', {'name': name ?? ''});
    case 'supplier_archived':
      return fill('vendor.purchases.err.supplierArchived', {
        'name': name ?? '',
      });
    case 'supplier_required':
      return t(
        where == 'paymentVoid'
            ? 'vendor.purchases.err.noSupplierDebt'
            : 'vendor.purchases.needSupplier',
      );
    case 'overpayment':
      return where == 'receive'
          ? fill('vendor.purchases.err.overTotal', {
              'amount': formatCurrency(intOfP(b['totalTzs'])),
            })
          : fill('vendor.purchases.err.overpayment', {
              'amount': formatCurrency(intOfP(b['balanceTzs'])),
            });
    case 'nothing_owed':
      return t('vendor.purchases.err.nothingOwed');
    case 'insufficient_stock':
      return fill('vendor.purchases.err.voidStock', {
        'list': mapsOf(b['lines'])
            .map(
              (l) => fill('vendor.purchases.err.voidStockLine', {
                'name': l['name'] ?? '',
                'received': intOfP(l['receivedQty']),
                'available': intOfP(l['available']),
              }),
            )
            .join('; '),
      });
    case 'already_voided':
      return t('vendor.purchases.err.alreadyVoided');
    case 'duplicate_supplier':
      return fill('vendor.purchases.err.duplicateSupplier', {
        'name': name ?? '',
      });
    case 'received_on_out_of_range' ||
        'due_date_out_of_range' ||
        'paid_on_out_of_range':
      return fill('vendor.purchases.err.dateRange', {
        'earliest': strOf(b['earliest']) ?? '',
        'latest': strOf(b['latest']) ?? '',
      });
    case 'schedule_mismatch':
      return fill('vendor.purchases.sumWrong', {
        'left': formatCurrency(intOfP(b['expectedTzs'])),
      });
    case 'reference_required':
      return t('vendor.pos.referenceRequired');
    case 'void_not_allowed':
      // #327 security review: a non-admin cannot void a purchase that
      // carries someone else's payment.
      return t(
        b['reason'] == 'has_others_payments'
            ? 'vendor.purchases.err.hasOthersPayments'
            : 'vendor.purchases.askOwner',
      );
    case 'supplier_has_balance':
      return fill('vendor.suppliers.archiveOwes', {
        'amount': formatCurrency(intOfP(b['owedTzs'])),
      });
    case 'feature_disabled':
      return t('vendor.purchases.unavailable');
    case 'vendor_suspended':
      return t('vendor.sales.suspended');
    case 'vendor_permission_forbidden':
      return t('vendor.purchases.noAccess');
    case 'rate_limited':
      final n = intOfP(b['retryAfterSeconds']);
      return fill('vendor.customers.rateLimited', {'n': n > 0 ? n : 60});
    case 'purchase_voided':
      return t('vendor.purchases.err.alreadyVoided');
    case 'name_required' || 'name_too_long':
      return t('vendor.suppliers.nameRequired');
    case 'invalid_phone':
      return t('vendor.suppliers.invalidPhone');
    case 'invalid_email':
      return t('vendor.suppliers.invalidEmail');
  }
  if ((e.code ?? '').endsWith('_not_found')) {
    return t('vendor.purchases.notFound');
  }
  return t('vendor.purchases.err.server');
}

/// A failed read's words: suspended business, no access, network, else
/// "could not load".
String purchaseLoadErrorKey(Object e) {
  if (e is! ApiException) return 'error.network';
  if (e.code == 'vendor_suspended') return 'vendor.sales.suspended';
  if (e.code == 'vendor_permission_forbidden') {
    return 'vendor.purchases.noAccess';
  }
  return 'vendor.purchases.failed';
}

// ── text share (spec §6; Q-4: no S5 document) ───────────────────────────

const _width = 32;
const _rule = '--------------------';

String _row(String label, String amount, {String indent = ''}) {
  final left = '$indent$label';
  final gap = _width - left.length - amount.length;
  if (gap >= 1) return '$left${' ' * gap}$amount';
  final pad = _width - amount.length;
  return '$left\n${' ' * (pad < 0 ? 0 : pad)}$amount';
}

String _day(String? day, String lang) {
  final d = parseDay(day);
  if (d == null) return '';
  return formatDate(DateTime(d.year, d.month, d.day), locale: lang);
}

/// The GRN as plain text, in [lang] ([t] answers in that language). Never
/// the previous cost prices, the note or who recorded it.
String purchaseShareText(
  Map purchase,
  String Function(String) t,
  String lang, {
  String? business,
}) {
  final b = StringBuffer();
  if (business != null && business.trim().isNotEmpty) {
    b.writeln(business.trim());
  }
  b.writeln(
    fillIn(t('vendor.purchases.grnTitle'), {'number': purchase['number']}),
  );
  final supplier = nameOf(purchase['supplier']);
  if (supplier != null) {
    b.writeln(fillIn(t('vendor.purchases.share.from'), {'name': supplier}));
  }
  b.writeln(
    fillIn(t('vendor.purchases.share.received'), {
      'date': _day(purchase['receivedOn']?.toString(), lang),
    }),
  );
  if (strOf(purchase['supplierInvoiceRef']) case final ref?) {
    b.writeln(fillIn(t('vendor.purchases.invoiceRefLine'), {'ref': ref}));
  }
  b.writeln(_rule);
  for (final l in mapsOf(purchase['lines'])) {
    final variant = strOf(l['variant']);
    final name = variant == null
        ? '${l['nameSnapshot'] ?? ''}'
        : '${l['nameSnapshot'] ?? ''} ($variant)';
    b.writeln('${intOfP(l['qty'])} x $name');
    b.writeln(
      _row(
        '@ ${formatMoney(intOfP(l['unitCostTzs']))}',
        formatMoney(intOfP(l['lineTotalTzs'])),
        indent: '   ',
      ),
    );
  }
  b.writeln(_rule);
  b.writeln(
    _row(
      t('vendor.purchases.total'),
      formatCurrency(intOfP(purchase['totalTzs'])),
    ),
  );
  final voided = purchase['status'] == 'voided';
  for (final p in mapsOf(purchase['payments'])) {
    if (p['status'] == 'voided') continue;
    b.writeln(
      _row(
        fillIn(t('vendor.purchases.share.paid'), {
          'method': t(paymentMethodKey(p['method']?.toString())),
        }),
        formatMoney(intOfP(p['amountTzs'])),
      ),
    );
  }
  if (!voided && intOfP(purchase['balanceTzs']) > 0) {
    b.writeln(
      _row(
        t('vendor.purchases.leftToPayLabel'),
        formatMoney(intOfP(purchase['balanceTzs'])),
      ),
    );
    for (final i in instalmentsOf(purchase)) {
      if (i.openTzs <= 0) continue;
      b.writeln(
        _row(_day(i.dueDate, lang), formatMoney(i.openTzs), indent: ' '),
      );
    }
  }
  if (voided) b.writeln(t('vendor.purchases.state.voided'));
  b.writeln(_rule);
  b.write(t('vendor.pos.notFiscal'));
  return b.toString();
}
