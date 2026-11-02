// Vendor reports · S6: which sections a person sees, and small readers for
// the server's answers (fitflex-functions#275, functions/vendor-reports.mjs).
//
// Gating fails closed (spec §0.1, §0.2):
// - the whole area needs `tools.reports` exactly true and the `reports`
//   permission;
// - Profit needs `canSeeCost`; cost, profit and margin keys are ABSENT from
//   the answers otherwise, so a missing key hides its figure (never a 0);
// - App sales after commission needs `canSeeOrderMoney`;
// - Customers needs `tools.customers` and the `customers` permission;
// - Stock value needs `tools.stockLedger`.
// Reports are online only: nothing here is kept on the device.
import '../../../shared/api_client.dart';
import '../stock/stock_options.dart' show VendorTools;

/// A report section: the mobile route segment, the API section, its words.
enum ReportSection {
  sales('sales', 'sales', 'vendor.reports.view.sales'),
  products('products', 'products', 'vendor.reports.view.products'),
  stock('stock', 'stock-value', 'vendor.reports.view.stock'),
  profit('profit', 'profit', 'vendor.reports.view.profit'),
  payouts('payouts', 'marketplace-net', 'vendor.reports.view.payouts'),
  customers('customers', 'customers', 'vendor.reports.view.customers'),
  methods('methods', 'payment-methods', 'vendor.reports.view.methods');

  const ReportSection(this.route, this.api, this.titleKey);

  /// `/vendor/reports/{route}`.
  final String route;

  /// `GET /vendor/reports/{api}`.
  final String api;
  final String titleKey;

  /// Period controls apply (stock value is "as of now").
  bool get usesPeriod => this != ReportSection.stock;

  /// The channel filter applies (§3: not stock, payouts, customers).
  bool get usesChannel =>
      this == ReportSection.sales ||
      this == ReportSection.products ||
      this == ReportSection.profit ||
      this == ReportSection.methods;

  /// Day / Week / Month applies.
  bool get usesGrouping =>
      this == ReportSection.sales || this == ReportSection.profit;

  static ReportSection? ofRoute(String? route) {
    for (final s in values) {
      if (s.route == route) return s;
    }
    return null;
  }
}

/// The mobile address of a section.
String reportSectionRoute(ReportSection s) => '/vendor/reports/${s.route}';

/// The Reports segment of the vendor home.
const reportsHomeRoute = '/vendor/home?open=reports';

/// What this person may see in Reports.
class ReportAccess {
  const ReportAccess({
    required this.reports,
    this.cost = false,
    this.payouts = false,
    this.customers = false,
    this.stock = false,
    this.walkIn = false,
    this.payments = false,
  });

  /// [can] answers a permission (`reports`, `customers`, `payments`).
  factory ReportAccess.of(VendorTools tools, bool Function(String) can) {
    final on = tools.reports && can('reports');
    return ReportAccess(
      reports: on,
      cost: on && tools.canSeeCost,
      payouts: on && tools.canSeeOrderMoney,
      customers: on && tools.customers && can('customers'),
      stock: on && tools.stockLedger,
      walkIn: tools.walkInSales,
      payments: can('payments'),
    );
  }

  static const none = ReportAccess(reports: false);

  final bool reports;
  final bool cost;
  final bool payouts;
  final bool customers;
  final bool stock;

  /// Walk-in sales are on now (the channel pills show; past walk-in data
  /// shows them too, from the answer's `channels.walkIn`).
  final bool walkIn;

  /// The Payouts segment (today's Payments content) needs `payments`.
  final bool payments;

  bool allows(ReportSection s) => switch (s) {
    ReportSection.sales ||
    ReportSection.products ||
    ReportSection.methods => reports,
    ReportSection.stock => stock,
    ReportSection.profit => cost,
    ReportSection.payouts => payouts,
    ReportSection.customers => customers,
  };

  /// The sections offered, in the order of the cards (§9).
  List<ReportSection> get sections => [
    for (final s in const [
      ReportSection.sales,
      ReportSection.products,
      ReportSection.stock,
      ReportSection.profit,
      ReportSection.payouts,
      ReportSection.customers,
      ReportSection.methods,
    ])
      if (allows(s)) s,
  ];
}

// ── readers ──────────────────────────────────────────────────────────────

/// A map inside [m] at [key], or null.
Map<String, dynamic>? mapAt(Map? m, String key) {
  final v = m?[key];
  return v is Map ? Map<String, dynamic>.from(v) : null;
}

/// A list of maps inside [m] at [key] (empty when missing).
List<Map<String, dynamic>> listAt(Map? m, String key) => [
  for (final v in (m?[key] as List? ?? const []))
    if (v is Map) Map<String, dynamic>.from(v),
];

/// A whole number at [key]: 0 when missing (only for figures the server
/// always sends; cost figures use [maybeNum]).
num numAt(Map? m, String key) {
  final v = m?[key];
  return v is num ? v : 0;
}

/// A figure that may be absent (cost, profit, margin): null when the key is
/// missing or null, so the screen hides it rather than showing 0.
num? maybeNum(Map? m, String key) {
  final v = m?[key];
  return v is num ? v : null;
}

/// Whether the answer says walk-in data exists (or walk-in is on).
bool walkInChannel(Map? answer) => mapAt(answer, 'channels')?['walkIn'] == true;

/// A margin in percent with one decimal: "12.5%" (sw "12.5%").
String formatPct(num? pct) {
  if (pct == null) return '—';
  // Always one decimal ("25.0%"), the same minus as money (UAT D11, D12).
  final s = pct.abs().toStringAsFixed(1);
  return pct < 0 ? '−$s%' : '$s%';
}

// ── days of cover (§6, Q-9) ──────────────────────────────────────────────

/// The words for a product row's cover. The server works it out (stock ÷
/// average daily units over the last 30 days, both channels, whatever the
/// period): with 30 in stock and 60 sold in 30 days that is 15 days. The
/// app only words it.
({String key, int? n, bool soon}) coverWording(Map row) {
  final state = row['coverState']?.toString();
  final days = row['daysOfCover'];
  final n = days is num ? days.toInt() : null;
  switch (state) {
    case 'out':
      return (key: 'vendor.reports.outOfStock', n: null, soon: false);
    case 'none':
      return (key: 'vendor.reports.coverNoSales', n: null, soon: false);
    case 'untracked':
      return (key: 'vendor.reports.coverUntracked', n: null, soon: false);
    case 'soon':
      return n != null && n >= 1
          ? (key: 'vendor.reports.coverDays', n: n, soon: true)
          : (key: 'vendor.reports.coverUnderOne', n: null, soon: true);
    case 'ok':
      return n != null && n >= 1
          ? (key: 'vendor.reports.coverDays', n: n, soon: false)
          : (key: 'vendor.reports.coverUnderOne', n: null, soon: false);
    default:
      return (key: 'vendor.reports.coverUntracked', n: null, soon: false);
  }
}

// ── payment methods ──────────────────────────────────────────────────────

/// The words key for a payment method. Cash collected by the vendor is
/// "Cash after change" (§8.4); anything unknown is "Other".
String methodKey(String? method, {bool byYou = false}) => switch (method) {
  'cash' when byYou => 'vendor.reports.methods.netOfChange',
  'cash' => 'vendor.pos.method.cash',
  'halopesa' => 'vendor.pos.method.halopesa',
  'mpesa' ||
  'airtel_money' ||
  'mixx' ||
  'card' ||
  'bank' => 'payment.method.$method',
  _ => 'vendor.pos.method.other',
};

// ── errors ───────────────────────────────────────────────────────────────

/// What went wrong loading a report.
enum ReportFailure {
  /// No answer: the device is offline (§11: no old figures shown).
  offline,

  /// The area is off on the server (404 feature_disabled).
  featureOff,

  /// Refused (403 cost_not_allowed, payout_not_allowed,
  /// vendor_permission_forbidden).
  noAccess,

  /// The staff member's access was turned off.
  staffDisabled,

  /// The period was refused (400 invalid_range, too_many_buckets).
  badRange,

  /// Anything else.
  failed,
}

ReportFailure reportFailureOf(Object error, {bool vendorStaff = false}) {
  if (error is! ApiException) return ReportFailure.offline;
  final code = error.code;
  if (code == 'vendor_staff_inactive' ||
      (vendorStaff && code == 'account_suspended')) {
    return ReportFailure.staffDisabled;
  }
  if (error.status == 404 && code == 'feature_disabled') {
    return ReportFailure.featureOff;
  }
  if (error.status == 403) return ReportFailure.noAccess;
  if (error.status == 400 &&
      (code == 'invalid_range' || code == 'too_many_buckets')) {
    return ReportFailure.badRange;
  }
  return ReportFailure.failed;
}

/// The words for an `invalid_range` reason (or `too_many_buckets`).
String rangeErrorKey(Object error) {
  if (error is ApiException) {
    if (error.code == 'too_many_buckets') {
      return 'vendor.reports.groupTooMany';
    }
    final body = error.body;
    final reason = body is Map ? body['reason']?.toString() : null;
    if (reason == 'too_long') return 'vendor.reports.rangeTooLong';
    if (reason == 'future') return 'vendor.reports.rangeFuture';
    if (reason == 'to_before_from') return 'vendor.reports.rangeOrder';
  }
  return 'vendor.reports.rangeInvalid';
}
