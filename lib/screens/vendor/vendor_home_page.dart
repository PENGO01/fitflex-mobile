import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/inbox/inbox_pages.dart';
import '../member/member_message_settings_page.dart';
import '../../shared/file-export.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import 'merch/banner_models.dart' show toEatWallClock;
import '../partner/verification/partner_progress_actions.dart';
import '../../shared/api_client.dart';
import '../../shared/api_error_message.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../../shared/photo_footer_flag.dart';
import '../../shared/partner_media/partner_hero_builder.dart';
import '../../shared/partner_media/partner_media_flag.dart';
import '../../shared/partner_media/partner_media_models.dart';
import '../../shared/partner_media/partner_media_store.dart';
import '../partner/partner_media_entry_tile.dart';
import '../../shared/photo_hero_flag.dart';
import '../../shared/product_categories.dart';
import '../../shared/shop_home.dart' show kTargetAgeBands, kTargetGenders;
import '../../shared/tone_theme.dart';
import '../../shared/widgets/product_category_picker.dart';
import '../../shared/widgets/ff_photo_picker_field.dart';
import '../../shared/widgets/partner_payouts_page.dart';
import '../../shared/widgets/invitations.dart';
import '../../shared/widgets/delete_account.dart';
import '../../shared/widgets/persona_switcher.dart';
import '../../shared/widgets/terms_agreement.dart';
import '../pin_flows.dart';
import '../../shared/shop_checkout.dart';
import 'customers/customers_tab.dart';
import 'customers/customers_widgets.dart';
import 'documents/document_models.dart'
    show TaxProfile, VatCodeOption, ratePctText, vatCodesOf;
import 'settings/tax_details_page.dart' show vendorTaxRoute;
import 'orders/vendor_order_card.dart';
import 'reports/report_models.dart';
import 'reports/report_section_page.dart' show reportSectionLink;
import 'reports/report_period.dart' show ReportPeriod;
import 'reports/reports_view.dart';
import 'stock/adjust_stock_sheet.dart';
import 'stock/stock_history_page.dart';
import 'stock/stock_options.dart';
import 'stock/variant_rows_editor.dart';
import 'vendor_areas_section.dart';
import 'sales/offline_sale_queue.dart';
import 'sales/sale_models.dart' show pluralKey;
import 'sales/sales_history_tab.dart';
import 'sales/sales_widgets.dart';

/// Bottom padding for vendor lists: the extended FAB (56) plus margins.
const vendorFabClearance = 96.0;

/// PHOTO_HERO_UI (owner 2026-10-22, bands "too dark"): the band grows for
/// [FFTokens.heroBandClearPhoto] of clear photo above its text, but no taller
/// than this on a 390x844 screen, so Add product (in the band) starts
/// above 55% of the screen
/// (FFHeroBand.maxHeightAt844).
const double vendorHomeBandMaxHeight = 409;

class VendorHomePage extends StatefulWidget {
  const VendorHomePage({super.key, this.open, this.filter, this.view});

  /// The section to show first — where a notification leads: `orders`,
  /// `enquiries`, `products`, `payments`, `sales`, `customers` or (S6)
  /// `reports`.
  final String? open;

  /// S4: with `open=customers`, which segment: `list`, `owed` or
  /// `messages`.
  final String? view;

  /// `low`: start the product list on the low-stock filter (stock ledger).
  final String? filter;

  @override
  State<VendorHomePage> createState() => _VendorHomePageState();
}

class _VendorHomePageState extends State<VendorHomePage> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _enquiries = [];
  List<Map<String, dynamic>> _staff = [];
  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _payments = {};
  bool _loading = true;
  bool _busy = false;
  bool _staffDisabled = false;

  /// The business is suspended (403 account_suspended): an alert instead
  /// of "No products yet".
  bool _accountSuspended = false;
  int _tab = 0;
  // Vendor tools · S1: off (old screens) unless the server says otherwise.
  VendorTools _tools = VendorTools.off;
  LowStockIndex _low = LowStockIndex.empty();
  late bool _lowOnly = widget.filter == 'low';
  // Vendor tools · S3: walk-in sales kept on this device (synced from here).
  SalesSession? _sales;
  // Vendor tools · S4: the Customers tab's segment.
  String _customersView = 'list';
  final _customersListKey = GlobalKey<CustomersListViewState>();
  // Vendor tools · S6: tab 2's segment while Reports is on: `reports` or
  // `payouts` (today's Payments content).
  String _tab2View = 'reports';
  final _reportsKey = GlobalKey<VendorReportsViewState>();
  final _owedKey = GlobalKey<OwedViewState>();

  // PHOTO_HERO_UI (spec §25.2): a band hero on Products only.
  final _heroKey = GlobalKey();
  bool _heroVisible = true;
  int? _heroTab;
  bool _precached = false;

  bool _heroOn(int tab) => photoHeroUi && tab == 0 && !_staffDisabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (photoHeroUi && !_precached) {
      _precached = true;
      precacheHeroPhotos(context, const [FFHeroPhoto.vendor]);
    }
  }

  /// The FAB comes back once the hero's own Add product, at the band's
  /// foot, has scrolled at least half away; until then that one is on
  /// screen. (The band is taller with clear photo above its text, owner
  /// 2026-10-22, so half the band is no longer enough.) The list's top
  /// padding and the band's bottom padding are both spacingLg, so the
  /// button's centre sits half a button above the band's height.
  bool _onProductsScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    final h = _heroKey.currentContext?.size?.height ?? 0;
    final visible = h == 0 || n.metrics.pixels < h - 24;
    if (visible != _heroVisible) setState(() => _heroVisible = visible);
    return false;
  }

  Widget _hero({bool loading = false}) {
    final name = _profile['businessName']?.toString().trim() ?? '';
    final pending = _pendingApproval;
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      child: KeyedSubtree(
        key: _heroKey,
        child: _partnerBand(
          (media) => FFHeroBand(
            key: const Key('vendor-hero'),
            photo: FFHeroPhoto.vendor,
            // PARTNER_MEDIA_UI (spec §40): the vendor's own photo and logo;
            // null (bundled, no plate) without them.
            ownPhoto: media?.photo,
            logo: partnerLogoPlate(media?.logo),
            clearPhoto: FFTokens.heroBandClearPhoto,
            maxHeightAt844: vendorHomeBandMaxHeight,
            eyebrow: name.isEmpty ? context.tr('vendor.title') : name,
            headlineLoading: loading,
            headlineLead: loading
                ? null
                : context.tr(
                    pending ? 'hero.vendor.pending.lead' : 'hero.vendor.lead',
                  ),
            headlineAccent: loading
                ? null
                : context.tr(
                    pending
                        ? 'hero.vendor.pending.accent'
                        : 'hero.vendor.accent',
                  ),
            actions: [
              if (!loading)
                FFButton(
                  key: const Key('vendor-add-product'),
                  label: context.tr('vendor.addProduct'),
                  icon: Icons.add,
                  onPressed: _busy ? null : () => _editProduct(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The Products band, with the vendor's saved photo and logo when
  /// PARTNER_MEDIA_UI is on (spec §40.4), for the vendor and their staff:
  /// read when the tab is built or comes back into view, never swapped on
  /// screen.
  Widget _partnerBand(Widget Function(PartnerHeroMedia? media) band) {
    if (!partnerMediaUi) return band(null);
    final account = AppScope.of(context).auth.user?['id']?.toString();
    return PartnerHeroBuilder(
      subject: account == null ? null : PartnerMediaSubject.vendor(account),
      visible: _tab == 0,
      builder: (context, media) => band(media),
    );
  }

  /// What leads the Products list under the flag: the hero, then the
  /// pending banner (unchanged) directly under it.
  List<Widget> _productsLead() => [
    _hero(),
    if (_isVendorAccount)
      PartnerProgressBanner(
        key: const Key('vendor-progress-banner'),
        padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
        fallback: _pendingApproval
            ? Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
                child: _pendingBannerCard(),
              )
            : null,
      ),
  ];

  bool get _ledger => _tools.stockLedger && _can('products');

  /// Shop home Phase 2 S1/S4: the Promotions entry, only while the server
  /// reports `merch.banners` or `merch.flashSales` and this person may work
  /// on products.
  bool get _merch => (_tools.banners || _tools.flashSales) && _can('products');

  /// How many of this vendor's banners wait for approval (the entry's
  /// subtitle); null until known or when it could not be read.
  int? _merchWaiting;

  Future<void> _loadMerchWaiting() async {
    final api = AppScope.of(context).api;
    // Banners and flash sales waiting, each only while its tool is on.
    Future<int?> count(
      bool on,
      Future<Map<String, dynamic>> Function() get,
    ) async {
      if (!on) return 0;
      try {
        final total = (await get())['total'];
        return total is num ? total.toInt() : null;
      } catch (_) {
        return null;
      }
    }

    final counts = await Future.wait([
      count(
        _tools.banners,
        () => api.vendorShopBanners(limit: 1, status: 'pending_approval'),
      ),
      count(
        _tools.flashSales,
        () => api.vendorFlashSales(limit: 1, status: 'pending_approval'),
      ),
    ]);
    if (!mounted) return;
    // Unknown when nothing could be read; the plain subtitle stays then.
    final known = counts.whereType<int>();
    setState(
      () => _merchWaiting = known.isEmpty
          ? null
          : known.fold<int>(0, (a, b) => a + b),
    );
  }

  Widget _merchEntry() => Padding(
    padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
    child: FFActionTile(
      key: const Key('vendor-merch-entry'),
      icon: Icons.campaign_outlined,
      // QA #14: the tools that are on: "Banners", "Flash sales", or both.
      title: context.tr(
        _tools.banners && _tools.flashSales
            ? 'merch.entry.title'
            : _tools.flashSales
            ? 'merch.sales.title'
            : 'merch.banners.title',
      ),
      subtitle: (_merchWaiting ?? 0) > 0
          ? context
                .tr('merch.entry.waiting')
                .replaceAll('{n}', '$_merchWaiting')
          : context.tr('merch.entry.subtitle'),
      onTap: () async {
        await context.push(AppRoutes.vendorMerch);
        if (mounted && _merch) unawaited(_loadMerchWaiting());
      },
    ),
  );

  /// S5: Tax details (VAT), while the server reports `vat: true`. The
  /// vendor edits; staff with `payments` see it read-only.
  bool get _taxEntryShown => _tools.vat && (_isVendor || _can('payments'));

  Widget _taxEntry() => Padding(
    padding: const EdgeInsets.only(top: FFTokens.spacingMd),
    child: FFActionTile(
      key: const Key('vendor-tax-entry'),
      icon: Icons.receipt_long_outlined,
      title: context.tr('vendor.tax.tile'),
      subtitle: context.tr('vendor.tax.tileSubtitle'),
      onTap: () => context.push(vendorTaxRoute),
    ),
  );

  /// S5: the VAT codes a product may use, or null to hide the field. Shown
  /// only with `vat` on and the vendor's VAT in force (§6.4). The options
  /// answer says so in `vatInForce` (any staff with `products` can read
  /// it); without that field, the tax profile is asked (vendor and
  /// `payments` staff only). Anything unknown hides it (fail closed).
  List<VatCodeOption>? _vatCodes;

  Future<void> _loadVat(VendorTools tools) async {
    List<VatCodeOption>? codes;
    if (tools.vat && _can('products')) {
      try {
        final api = AppScope.of(context).api;
        final inForce =
            tools.vatInForce ??
            TaxProfile.fromJson(await api.vendorTaxProfile()).everVerified;
        if (inForce) {
          final list = vatCodesOf(await api.vendorTaxRates());
          if (list.isNotEmpty) codes = list;
        }
      } catch (_) {
        codes = null;
      }
    }
    if (mounted) setState(() => _vatCodes = codes);
  }

  bool _can(String permission) {
    final user = AppScope.of(context).auth.user;
    if (user?['userType'] != 'vendor_staff') return true;
    return (user?['vendorPermissions'] as List? ?? []).contains(permission);
  }

  /// A vendor whose verification is not approved yet: they can add products,
  /// which FitFlex reviews; nothing is in the shop until they are approved.
  bool get _pendingApproval {
    final auth = AppScope.of(context).auth;
    return auth.isPendingApproval && auth.user?['userType'] == 'vendor';
  }

  static const _friendlyCodes = {
    'invalid_category',
    'invalid_product_category',
    'name_required',
    'priceTzs_required',
    'invalid_stock',
    // A refused logo, banner or product photo (fitflex-functions#273).
    'invalid_media_src',
    'rate_limited',
  };

  /// Reasons the vendor can act on are shown; anything else stays generic.
  String _saveFailedText(Object e) =>
      e is ApiException && e.code == 'invalid_vat_code'
      ? context.tr('vendor.product.vatInvalid')
      // Phase 2 S4: the price can't change while a flash sale is scheduled
      // or live (409 sale_conflict, price_locked_by_flash_sale).
      : e is ApiException && e.code == 'sale_conflict'
      ? context.tr('vendor.priceLockedSave')
      : e is ApiException && _friendlyCodes.contains(e.code)
      ? apiErrorMessage(FFLocaleScope.of(context), e)
      : context.tr('vendor.saveFailed');

  static const _sectionOf = {
    'products': 0,
    'orders': 1,
    'payments': 2,
    'reports': 2,
    'enquiries': 3,
    'customers': 3,
    'sales': _salesSection,
  };

  /// S4: the segment a request opens (`open=enquiries` → Messages).
  void _pickView(String? open, String? view) {
    if (open == 'reports') {
      _tab2View = 'reports';
    } else if (open == 'payments') {
      _tab2View = 'payouts';
    }
    if (open == 'enquiries') {
      _customersView = 'messages';
    } else if (open == 'customers') {
      _customersView = const {'list', 'owed', 'messages'}.contains(view)
          ? view!
          : 'list';
    }
  }

  /// S6: what this person may see in Reports (all off unless the server
  /// says `reports: true` and they have the `reports` permission).
  ReportAccess get _reportAccess => ReportAccess.of(_tools, _can);

  /// S6: tab 2 is "Reports" (Reports | Payouts) when reports are on.
  bool get _reportsTab => _reportAccess.reports;

  /// The segment tab 2 shows: Payouts needs `payments` (spec Q-1).
  String get _tab2Shown => !_reportsTab
      ? 'payouts'
      : !_can('payments')
      ? 'reports'
      : _tab2View;

  /// S4: tab 3 is "Customers" (with segments) when the tool is on.
  bool get _customersTab => _tools.customers && _can('customers');

  /// S3: the Sales tab (after Orders in the bar).
  static const _salesSection = 6;

  /// Shows the section a notification is about, if this person may see it.
  void _show(String? part) {
    final section = _sectionOf[part];
    if (section == null) return;
    _pickView(part, widget.view);
    // Which tabs exist is known only once the tools (walk-in sales) and the
    // profile have loaded: keep the request until then, so the profile's
    // "finish your profile" redirect or a missing Sales tab cannot win.
    if (_loading) {
      _pendingOpen = part;
      return;
    }
    if (!_sections.contains(section)) return;
    setState(() => _tab = section);
  }

  /// A requested section (`open=`) waiting for the tab list to be known.
  String? _pendingOpen;

  /// The unfinished-profile redirect to Business has happened.
  bool _profileNudged = false;

  bool get _walkInSales => _tools.walkInSales && _can('sales');

  @override
  void didUpdateWidget(VendorHomePage old) {
    super.didUpdateWidget(old);
    if (widget.open != old.open ||
        (widget.open == 'customers' && widget.view != old.view)) {
      _show(widget.open);
    }
    if (widget.filter != old.filter) {
      setState(() => _lowOnly = widget.filter == 'low');
    }
  }

  List<int> get _sections {
    final sections = <int>[
      if (_can('products')) 0,
      if (_can('orders')) 1,
      if (_walkInSales) _salesSection,
      if (_can('payments') || _can('reports')) 2,
      if (_can('customers')) 3,
      if (_can('staff') ||
          AppScope.of(context).auth.user?['userType'] != 'vendor_staff')
        4,
    ];
    return sections.isEmpty ? [5] : sections;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sales = SalesSession.of(context)?..attach();
      setState(() => _sales = sales);
      _sales?.signedIn();
      _pendingOpen = widget.open;
      _pickView(widget.open, widget.view);
      _refresh();
      // Vendors have no sign-up form of their own, so the vendor terms are
      // asked here the first time (and again if a new version is published).
      askToAgreeTerms(context, quiet: true);
    });
  }

  /// While waiting for approval, pick up an approval made in the meantime.
  Future<void> _checkApproval() async {
    if (!_pendingApproval) return;
    final scope = AppScope.of(context);
    try {
      final user = (await scope.api.me())['user'];
      if (user is Map &&
          user['approvalStatus']?.toString() != 'pending_approval') {
        await scope.auth.signIn(
          scope.auth.token!,
          Map<String, dynamic>.from(user),
        );
      }
    } catch (_) {
      // Not being able to check changes nothing; the banner stays.
    }
  }

  Future<void> _refresh({bool askTools = false}) async {
    setState(() => _loading = true);
    await _checkApproval();
    if (!mounted) return;
    // Which vendor tools are on; never fails (off when it cannot tell).
    final tools = VendorToolsOptions.of(context, refresh: askTools);
    final api = AppScope.of(context).api;
    final isStaff =
        AppScope.of(context).auth.user?['userType'] == 'vendor_staff';
    // Each part loads on its own: one failing (e.g. the business profile
    // refused to a staff member) must not hide the others. A part that
    // fails keeps what it showed before.
    var failed = false;
    // No answer at all (not a refusal): the device is offline.
    var offline = false;
    // S2: the business owner turned this staff member's access off.
    var staffDisabled = false;
    // The business itself is suspended (403 account_suspended to the
    // vendor account).
    var accountSuspended = false;
    Future<T?> part<T>(
      bool allowed,
      Future<T> Function() load,
      T none, {
      bool quiet = false,
    }) async {
      if (!allowed) return none;
      try {
        return await load();
      } on ApiException catch (e) {
        if (isVendorStaffDisabled(e, vendorStaff: isStaff)) {
          staffDisabled = true;
        } else if (!isStaff &&
            e.status == 403 &&
            e.code == 'account_suspended') {
          accountSuspended = true;
        } else if (!quiet) {
          failed = true;
        }
        return null;
      } catch (_) {
        if (!quiet) failed = true;
        offline = true;
        return null;
      }
    }

    List<Map<String, dynamic>>? maps(List<dynamic>? rows) =>
        rows?.whereType<Map<String, dynamic>>().toList();
    final products = part(_can('products'), api.vendorProducts, <dynamic>[]);
    final orders = part(_can('orders'), api.vendorOrders, <dynamic>[]);
    // Staff do not manage the business profile; its failure stays quiet.
    final profile = part(
      true,
      api.vendorProfile,
      <String, dynamic>{},
      quiet: isStaff,
    );
    final payments = part(
      _can('payments'),
      api.vendorPayments,
      <String, dynamic>{},
    );
    final enquiries = part(_can('customers'), api.vendorEnquiries, <dynamic>[]);
    final staff = part(_can('staff'), api.vendorStaff, <dynamic>[]);
    // Known before the sections are drawn, so a sales-only staff member
    // opens on Sales without a "no access" flash.
    final toolsNow = await tools;
    final loaded = (
      products: maps(await products),
      orders: maps(await orders),
      profile: await profile,
      payments: await payments,
      enquiries: maps(await enquiries),
      staff: maps(await staff),
    );
    // Offline with nothing shown yet: the copy the POS keeps on the device
    // (S3), rather than "no products yet". A fresh list refreshes that copy.
    var products0 = loaded.products;
    if (products0 != null) {
      unawaited(_sales?.saveProducts(products0));
    } else if (offline && _products.isEmpty && _can('products')) {
      final kept = await _sales?.loadProducts();
      if (kept != null && kept.products.isNotEmpty) products0 = kept.products;
    }
    if (!mounted) return;
    setState(() {
      _products = products0 ?? _products;
      _orders = loaded.orders ?? _orders;
      if (loaded.profile != null) {
        _profile = loaded.profile!;
        // An unfinished profile opens on Business once (the first load), not
        // on every refresh: pulling to refresh on Sales stays on Sales.
        if (_profile['status'] != 'published' &&
            !_pendingApproval &&
            !isStaff &&
            !_profileNudged) {
          _profileNudged = true;
          _tab = 4;
        }
      }
      _payments = loaded.payments ?? _payments;
      _enquiries = loaded.enquiries ?? _enquiries;
      _staff = loaded.staff ?? _staff;
      _staffDisabled = staffDisabled;
      _accountSuspended = accountSuspended || toolsNow.suspended;
      _tools = toolsNow;
      _loading = false;
      // Now the tabs are known: honour `open=` (Done after a sale, a
      // notification, a deep link).
      final wanted = _sectionOf[_pendingOpen];
      _pendingOpen = null;
      if (wanted != null && _sections.contains(wanted)) _tab = wanted;
    });
    unawaited(_loadVat(toolsNow));
    // Promotions: how many banners wait for approval (the entry subtitle).
    if (_merch) unawaited(_loadMerchWaiting());
    if (toolsNow.walkInSales) {
      _sales?.featureOn();
    } else {
      _sales?.featureOff();
    }
    if (staffDisabled) {
      FFSnack.error(context, context.tr('error.reason.vendorStaffInactive'));
    } else if (failed && offline) {
      // Offline: say what still works (selling, on the Sales tab).
      final onSales = _sections.contains(_tab) && _tab == _salesSection;
      FFSnack.info(
        context,
        context.tr(
          onSales ? 'vendor.sales.offlineToast' : 'vendor.offlineKept',
        ),
      );
    } else if (failed) {
      FFSnack.error(context, context.tr('vendor.loadFailed'));
    }
    _watchTools(toolsNow);
    await _loadStockTools(toolsNow);
  }

  // Options read from the device copy (offline start): ask the server
  // again once it answers anything, or every minute, and update the tabs in
  // place (the Sales tab appears or goes without a reload).
  Timer? _toolsRetry;
  ApiClient? _watchedApi;
  bool _toolsAsking = false;

  void _watchTools(VendorTools tools) {
    if (tools.fromCache) {
      if (_watchedApi == null) {
        _watchedApi = AppScope.of(context).api..addSuccessListener(_onOnline);
        _toolsRetry = Timer.periodic(
          const Duration(seconds: 60),
          (_) => _askToolsAgain(),
        );
      }
    } else {
      _stopWatchingTools();
    }
  }

  void _stopWatchingTools() {
    _watchedApi?.removeSuccessListener(_onOnline);
    _watchedApi = null;
    _toolsRetry?.cancel();
    _toolsRetry = null;
  }

  void _onOnline(String method, String path) {
    if (path == '/vendor/tools/options') return;
    scheduleMicrotask(_askToolsAgain);
  }

  Future<void> _askToolsAgain() async {
    if (_toolsAsking || !mounted) return;
    _toolsAsking = true;
    try {
      final tools = await VendorToolsOptions.of(context, refresh: true);
      if (!mounted) return;
      setState(() => _tools = tools);
      if (tools.walkInSales) {
        _sales?.featureOn();
      } else {
        _sales?.featureOff();
      }
      _watchTools(tools);
      if (!tools.fromCache) await _loadStockTools(tools);
    } finally {
      _toolsAsking = false;
    }
  }

  @override
  void dispose() {
    _stopWatchingTools();
    _sales?.detach();
    super.dispose();
  }

  /// The stock ledger's extras: on/off, and which products are low. The
  /// low list failing just hides the badge and filter.
  Future<void> _loadStockTools(VendorTools tools) async {
    var low = LowStockIndex.empty();
    if (tools.stockLedger && _can('products')) {
      try {
        low = LowStockIndex(await AppScope.of(context).api.vendorLowStock());
      } catch (_) {
        // No badge, no filter, no error.
      }
    }
    if (!mounted) return;
    setState(() {
      _tools = tools;
      _low = low;
    });
  }

  /// The row menu's flash sale item (Phase 2 S4): "Start a flash sale" on
  /// an active, approved product, "View sale" while its price is locked;
  /// null without the tool or the `products` permission.
  String? _flashSaleFor(Map<String, dynamic> product) {
    if (!_tools.flashSales || !_can('products')) return null;
    if (product['priceLock'] is Map) return 'vendor.viewSale';
    final status = product['status']?.toString() ?? 'active';
    final approval = product['approvalStatus']?.toString() ?? 'approved';
    return status == 'active' && approval == 'approved'
        ? 'merch.sale.start'
        : null;
  }

  Future<void> _openFlashSale(Map<String, dynamic> product) async {
    final id = product['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final lock = product['priceLock'];
    final saleId = lock is Map ? lock['saleId']?.toString() ?? '' : '';
    await context.push(
      lock is Map
          ? Uri(
              path: AppRoutes.vendorMerch,
              queryParameters: {
                'tab': 'sales',
                'item': ?(saleId.isEmpty ? null : saleId),
              },
            ).toString()
          : '${AppRoutes.vendorMerchSaleNew}?productId=${Uri.encodeQueryComponent(id)}',
    );
    if (mounted) unawaited(_refresh());
  }

  Future<void> _editProduct([Map<String, dynamic>? product]) async {
    if (_ledger) return _editProductWithLedger(product);
    final draft = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => VendorProductForm(
        product: product,
        showTargets: _showTargets,
        showFlashSale: _tools.flashSales,
        vatCodes: _vatCodes,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(
        context,
      ).api.vendorSaveProduct(draft, productId: product?['id']?.toString());
      if (!mounted) return;
      FFSnack.success(context, context.tr('vendor.productSaved'));
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'stock_changed') {
        // Stock moved (e.g. an order) while the form was open: say so and
        // show the current count; the vendor edits again.
        FFSnack.error(context, context.tr('vendor.stock.changedForm'));
        await _refresh();
        return;
      }
      FFSnack.error(context, _saveFailedText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Who it's for" (Phase 2 S2) shows only when /vendor/tools/options
  /// says `merch.productTargets: true` (SHOP_PERSONALISATION on). Vendor
  /// rows carry the fields either way, so they are not a signal.
  bool get _showTargets => _tools.productTargets;

  /// The product form with the stock ledger on: it saves itself and stays
  /// open (values kept) when the save fails.
  Future<void> _editProductWithLedger(Map<String, dynamic>? product) async {
    final api = AppScope.of(context).api;
    final productId = product?['id']?.toString();
    var current = product;
    final saved = await showFFSheet<bool>(
      context,
      title: context.tr(
        product == null ? 'vendor.addProduct' : 'vendor.editProduct',
      ),
      child: VendorProductForm(
        product: product,
        showTargets: _showTargets,
        showFlashSale: _tools.flashSales,
        stockLedger: true,
        canSeeCost: _tools.canSeeCost,
        vatCodes: _vatCodes,
        describeError: _saveFailedText,
        onSave: (body) => api.vendorSaveProduct(body, productId: productId),
        onAdjust: current == null
            ? null
            : (variant, notify) async {
                // Told inside the form: a snackbar would sit behind it.
                final result = await openAdjustStock(
                  context,
                  product: current!,
                  variant: variant,
                  notify: notify,
                );
                if (result == null) return null;
                current = withAdjustedStock(current!, result.product);
                _applyAdjusted(result);
                return result.product;
              },
      ),
    );
    if (saved != true || !mounted) return;
    FFSnack.success(context, context.tr('vendor.productSaved'));
    await _refresh();
  }

  /// Shows an adjustment's new counts on the product card at once, then
  /// refreshes the low-stock list.
  void _applyAdjusted(AdjustResult result) {
    final id = result.product['id']?.toString();
    if (!mounted || id == null) return;
    setState(() {
      _products = [
        for (final p in _products)
          p['id']?.toString() == id ? withAdjustedStock(p, result.product) : p,
      ];
    });
    _loadStockTools(_tools);
  }

  Future<void> _adjustStock(Map<String, dynamic> product) async {
    final result = await openAdjustStock(context, product: product);
    if (result != null) _applyAdjusted(result);
  }

  Future<void> _openHistory(Map<String, dynamic> product) async {
    await context.push('/vendor/products/${product['id']}/stock');
    if (!mounted) return;
    // Quietly, so the list keeps its filter and scroll position.
    try {
      final rows = await AppScope.of(context).api.vendorProducts();
      if (!mounted) return;
      setState(
        () => _products = rows.whereType<Map<String, dynamic>>().toList(),
      );
    } catch (_) {
      // The list stays as it was.
    }
    await _loadStockTools(_tools);
  }

  Future<void> _archiveProduct(Map<String, dynamic> product) async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).api.vendorSaveProduct({
        'status': product['status'] == 'paused' ? 'active' : 'paused',
      }, productId: product['id']?.toString());
      await _refresh();
    } on ApiException {
      if (mounted) {
        FFSnack.error(context, context.tr('vendor.saveFailed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _duplicateProduct(Map<String, dynamic> product) async {
    setState(() => _busy = true);
    try {
      await AppScope.of(
        context,
      ).api.vendorDuplicateProduct(product['id'].toString());
      await _refresh();
    } on ApiException {
      if (mounted) {
        FFSnack.error(context, context.tr('vendor.saveFailed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    setState(() => _busy = true);
    try {
      await AppScope.of(
        context,
      ).api.vendorDeleteProduct(product['id'].toString());
      await _refresh();
    } on ApiException {
      if (mounted) {
        FFSnack.error(context, context.tr('vendor.saveFailed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateOrder(String id, String status) async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).api.vendorUpdateOrderStatus(id, status);
      await _refresh();
    } on ApiException catch (e) {
      if (mounted && e.code == 'order_cancelled') {
        // Cancelled meanwhile (e.g. by the buyer): say so and show the list
        // as it is now.
        FFSnack.error(context, context.tr('vendor.orders.cancelledMeanwhile'));
        await _refresh();
        return;
      }
      if (mounted) {
        final isStaff =
            AppScope.of(context).auth.user?['userType'] == 'vendor_staff';
        FFSnack.error(
          context,
          context.tr(
            isVendorStaffDisabled(e, vendorStaff: isStaff)
                ? 'error.reason.vendorStaffInactive'
                : 'vendor.saveFailed',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    if (!await confirmLeaveWithQueuedSales(context)) return;
    if (!mounted) return;
    // S4: customer names held in memory go with the session.
    CustomerRepository.clear(AppScope.of(context).api);
    await AppScope.of(context).auth.signOut();
    if (mounted) context.go(AppRoutes.language);
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    // The tab starts at Products; show the first section this user may use
    // when Products is not one of them.
    final tab = sections.contains(_tab) ? _tab : sections.first;
    // A tab opens at its top, so the Products hero is in view again.
    if (tab != _heroTab) {
      _heroTab = tab;
      _heroVisible = true;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('vendor.title')),
        actions: [
          // Orders, questions and decisions arrive here as well as by push.
          const InboxBellButton(),
          PersonaSwitchButton(
            confirmLeave: (c) =>
                confirmLeaveWithQueuedSales(c, switching: true),
          ),
          // English <-> Swahili in place, the same shared switch members and
          // owners use; the choice is remembered (owner, 2026-10-19).
          const LanguageToggleButton(key: Key('vendor-language')),
          // The vendor and their staff change their own PIN here.
          const ChangePinButton(),
          IconButton(
            key: const Key('vendor-sign-out'),
            tooltip: context.tr('home.signout'),
            onPressed: _busy ? null : _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: AppScope.of(context).auth,
            // Under the flag the Products hero carries it, just below.
            // Partner progress (B4b): the compact tracker while the vendor
            // isn't finished; the old pending banner without it.
            builder: (context, _) => _isVendorAccount && !_heroOn(tab)
                ? PartnerProgressBanner(
                    key: const Key('vendor-progress-banner'),
                    padding: partnerBannerPadding,
                    fallback: _pendingApproval ? _pendingBanner() : null,
                  )
                : const SizedBox.shrink(),
          ),
          // Sales still on this device with the Sales tab gone (feature
          // off) and no Business tab to show them on: reachable here.
          if (_sales != null && !sections.contains(4))
            ListenableBuilder(
              listenable: _sales!,
              builder: (context, _) => _sales!.isEmpty || _walkInSales
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(
                        FFTokens.spacingLg,
                        FFTokens.spacingSm,
                        FFTokens.spacingLg,
                        0,
                      ),
                      child: _salesWaitingTile(),
                    ),
            ),
          if (_accountSuspended && !_staffDisabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FFTokens.spacingLg,
                FFTokens.spacingSm,
                FFTokens.spacingLg,
                0,
              ),
              child: FFAlert(
                key: const Key('vendor-account-suspended'),
                message: context.tr('vendor.accountSuspended'),
                tone: FFAlertTone.error,
              ),
            ),
          if (_staffDisabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FFTokens.spacingLg,
                FFTokens.spacingSm,
                FFTokens.spacingLg,
                0,
              ),
              child: FFAlert(
                key: const Key('vendor-staff-disabled'),
                message: context.tr('error.reason.vendorStaffInactive'),
                tone: FFAlertTone.error,
              ),
            ),
          Expanded(
            child: _loading && _heroOn(tab)
                ? ListView(
                    padding: const EdgeInsets.all(FFTokens.spacingLg),
                    children: [
                      _hero(loading: true),
                      const Center(child: FFSpinner()),
                    ],
                  )
                : _loading
                ? const Center(child: FFSpinner())
                : RefreshIndicator(
                    onRefresh: () async {
                      // S4: the customer lists reload with the page.
                      if (tab == 3 && _customersTab) {
                        unawaited(_customersListKey.currentState?.reload());
                        unawaited(_owedKey.currentState?.reload());
                      }
                      // S6: the reports reload with the page.
                      if (tab == 2 && _tab2Shown == 'reports') {
                        unawaited(_reportsKey.currentState?.reload());
                      }
                      await _refresh(askTools: true);
                    },
                    child: switch (tab) {
                      0 when _heroOn(tab) =>
                        NotificationListener<ScrollNotification>(
                          onNotification: _onProductsScroll,
                          child: _productsTab(),
                        ),
                      0 => _productsTab(),
                      1 => _ordersTab(),
                      2 when _reportsTab => _reportsAndPayoutsTab(),
                      2 => _paymentsTab(),
                      3 when _customersTab => VendorCustomersTab(
                        key: const Key('vendor-customers-tab'),
                        view: _customersView,
                        onView: (v) => setState(() => _customersView = v),
                        messages: _enquiriesTab(),
                        listKey: _customersListKey,
                        owedKey: _owedKey,
                      ),
                      3 => _enquiriesTab(),
                      4 => _businessTab(),
                      _salesSection => const VendorSalesTab(
                        key: Key('vendor-sales-tab'),
                      ),
                      _ => _restrictedTab(),
                    },
                  ),
          ),
        ],
      ),
      // Exactly one "vendor-add-product" at a time: the hero's while the
      // hero shows, this one otherwise.
      floatingActionButton:
          tab == 0 && !(_heroOn(tab) && (_loading || _heroVisible))
          ? FloatingActionButton.extended(
              key: const Key('vendor-add-product'),
              onPressed: _busy ? null : () => _editProduct(),
              icon: const Icon(Icons.add),
              label: Text(context.tr('vendor.addProduct')),
            )
          : tab == 3 && _customersTab && _customersView == 'list' && !_loading
          ? FloatingActionButton.extended(
              key: const Key('vendor-customers-add'),
              onPressed: _staffDisabled
                  ? null
                  : () async {
                      await context.push(newCustomerRoute);
                      if (mounted) {
                        unawaited(_customersListKey.currentState?.reload());
                      }
                    },
              icon: const Icon(Icons.person_add_alt),
              label: Text(context.tr('vendor.customers.add')),
            )
          : tab == _salesSection && !_loading && _sales != null
          ? ListenableBuilder(
              listenable: _sales!,
              builder: (context, _) {
                final n = _sales!.draftCount;
                return FloatingActionButton.extended(
                  key: const Key('vendor-pos-new'),
                  onPressed: _staffDisabled
                      ? null
                      : () => context.push(posRoute),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(
                    n > 0
                        ? fillIn(context.tr('vendor.pos.continueSale'), {
                            'n': n,
                          })
                        : context.tr('vendor.pos.newSale'),
                  ),
                );
              },
            )
          : null,
      // A navigation bar needs two or more destinations; with one section
      // (or none: the "no access" page) there is nothing to switch between.
      bottomNavigationBar: sections.length < 2
          ? null
          : NavigationBar(
              selectedIndex: sections.indexOf(tab),
              onDestinationSelected: (index) =>
                  setState(() => _tab = sections[index]),
              destinations: [
                if (sections.contains(0))
                  NavigationDestination(
                    key: const Key('vendor-nav-products'),
                    icon: _lowBadge(const Icon(Icons.inventory_2_outlined)),
                    selectedIcon: _lowBadge(const Icon(Icons.inventory_2)),
                    label: context.tr('vendor.products'),
                  ),
                if (sections.contains(1))
                  NavigationDestination(
                    key: const Key('vendor-nav-orders'),
                    icon: const Icon(Icons.receipt_long_outlined),
                    selectedIcon: const Icon(Icons.receipt_long),
                    label: context.tr('vendor.orders'),
                  ),
                if (sections.contains(_salesSection))
                  NavigationDestination(
                    key: const Key('vendor-nav-sales'),
                    icon: const Icon(Icons.point_of_sale_outlined),
                    selectedIcon: const Icon(Icons.point_of_sale),
                    label: context.tr('vendor.sales.tab'),
                  ),
                if (sections.contains(2))
                  _reportsTab
                      ? NavigationDestination(
                          key: const Key('vendor-nav-reports'),
                          icon: const Icon(Icons.bar_chart_outlined),
                          selectedIcon: const Icon(Icons.bar_chart),
                          label: context.tr('vendor.reports.tab'),
                        )
                      : NavigationDestination(
                          key: const Key('vendor-nav-payments'),
                          icon: const Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                          selectedIcon: const Icon(
                            Icons.account_balance_wallet,
                          ),
                          label: context.tr('vendor.payments'),
                        ),
                if (sections.contains(3))
                  _customersTab
                      ? NavigationDestination(
                          key: const Key('vendor-nav-customers'),
                          icon: const Icon(Icons.people_outline),
                          selectedIcon: const Icon(Icons.people),
                          label: context.tr('vendor.customers.tab'),
                        )
                      : NavigationDestination(
                          key: const Key('vendor-nav-enquiries'),
                          icon: const Icon(Icons.forum_outlined),
                          selectedIcon: const Icon(Icons.forum),
                          label: context.tr('vendor.enquiries'),
                        ),
                if (sections.contains(4))
                  NavigationDestination(
                    key: const Key('vendor-nav-business'),
                    icon: const Icon(Icons.store_outlined),
                    selectedIcon: const Icon(Icons.store),
                    label: context.tr('vendor.business'),
                  ),
                if (sections.contains(5))
                  NavigationDestination(
                    icon: const Icon(Icons.lock_outline),
                    label: context.tr('vendor.noAccess'),
                  ),
              ],
            ),
    );
  }

  /// The low-stock count on the Products tab (stock ledger only).
  Widget _lowBadge(Widget icon) {
    final n = _ledger ? _low.count : 0;
    if (n == 0) return icon;
    // Low stock is a nudge, not an error: the warning tone, not red. The
    // tab's own label says "Products", so the badge only adds the count.
    final warning = FFToneTheme.of(context).warning;
    return Semantics(
      label: fillIn(context.tr('vendor.stock.lowNavLabel'), {'n': n}),
      excludeSemantics: true,
      child: Badge(
        key: const Key('vendor-nav-low-badge'),
        // The tone pair inverted: a solid amber dot that stands out on the
        // bar, with the pair's pale colour for the count (same >= 4.5:1).
        backgroundColor: warning.fg,
        textColor: warning.bg,
        label: Text(n > 99 ? '99+' : '$n'),
        child: icon,
      ),
    );
  }

  /// The vendor's own account (not staff, not switched off): the one whose
  /// verification and payouts the progress tracker follows. A suspended
  /// business already has its own alert, said once.
  bool get _isVendorAccount =>
      !_staffDisabled &&
      !_accountSuspended &&
      AppScope.of(context).auth.user?['userType'] == 'vendor';

  Widget _pendingBanner() => Padding(
    padding: const EdgeInsets.fromLTRB(
      FFTokens.spacingLg,
      FFTokens.spacingMd,
      FFTokens.spacingLg,
      0,
    ),
    child: _pendingBannerCard(),
  );

  Widget _pendingBannerCard() => FFCard(
    key: const Key('vendor-pending-banner'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.hourglass_top_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(child: Text(context.tr('vendor.pendingBanner'))),
          ],
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FFButton(
            key: const Key('vendor-pending-verification'),
            label: context.tr('kyc.entry.title'),
            onPressed: () => context.push(AppRoutes.verification),
            variant: FFButtonVariant.secondary,
            icon: Icons.verified_user_outlined,
          ),
        ),
      ],
    ),
  );

  Widget _productsTab() {
    final lead = [
      if (_heroOn(0)) ..._productsLead(),
      if (_merch) _merchEntry(),
    ];
    if (_products.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          ...lead,
          // Suspended: the alert above says why the list is empty.
          if (!_accountSuspended)
            FFEmptyState(title: context.tr('vendor.noProducts')),
        ],
      );
    }
    final ledger = _ledger;
    final showFilter = ledger && (_low.count > 0 || _lowOnly);
    final lowOnly = ledger && _lowOnly;
    final products = lowOnly
        ? _products.where((p) => _low.isLow(p['id']?.toString())).toList()
        : _products;
    final itemCount =
        lead.length +
        products.length +
        (showFilter ? 1 : 0) +
        (lowOnly && products.isEmpty ? 1 : 0);
    Widget item(BuildContext context, int index) {
      if (index < lead.length) return lead[index];
      index -= lead.length;
      if (showFilter) {
        if (index == 0) return _stockFilter();
        index -= 1;
      }
      if (index >= products.length) {
        return FFEmptyState(
          key: const Key('vendor-low-empty'),
          title: context.tr('vendor.stock.lowEmpty'),
          action: FFButton(
            label: context.tr('vendor.stock.all'),
            variant: FFButtonVariant.secondary,
            onPressed: () => setState(() => _lowOnly = false),
          ),
        );
      }
      final product = products[index];
      final paused = product['status'] == 'paused';
      final id = product['id']?.toString();
      final name = product['name']?.toString() ?? '';
      final lowVariants = ledger ? _low.lowVariants(id) : const <String>[];
      final low = ledger && _low.isLow(id);
      final subtitle = Text(
        '${formatCurrency(product['priceTzs'] as num? ?? 0)} · ${product['stock'] ?? 0} ${context.tr('vendor.inStock')}',
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
        child: FFCard(
          child: ListTile(
            key: Key('vendor-product-${product['id']}'),
            contentPadding: EdgeInsets.zero,
            onTap: ledger ? () => _openHistory(product) : null,
            leading: const CircleAvatar(
              child: Icon(Icons.shopping_bag_outlined),
            ),
            title: Text(name),
            subtitle: !low
                ? subtitle
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      subtitle,
                      const SizedBox(height: FFTokens.spacingXs),
                      // Badges wrap and are never cut off; both are read.
                      Wrap(
                        spacing: FFTokens.spacingXs,
                        runSpacing: FFTokens.spacingXs,
                        children: [
                          FFBadge(
                            key: Key('vendor-low-badge-$id'),
                            label: context.tr('vendor.stock.lowBadge'),
                            tone: FFBadgeTone.warning,
                            wrap: true,
                          ),
                          if (lowVariants.isNotEmpty)
                            FFBadge(
                              key: Key('vendor-low-variants-$id'),
                              label: fillIn(
                                context.tr(
                                  lowVariants.length == 1
                                      ? 'vendor.stock.lowVariantsOne'
                                      : 'vendor.stock.lowVariants',
                                ),
                                {'n': lowVariants.length},
                              ),
                              tone: FFBadgeTone.warning,
                              wrap: true,
                            ),
                        ],
                      ),
                    ],
                  ),
            trailing: PopupMenuButton<String>(
              // 48dp even where the density is compact (web).
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              // Labelled with the product, ledger on or off (QA 2026-10-22).
              tooltip: fillIn(context.tr('vendor.productActions'), {
                'name': name,
              }),
              onSelected: (value) {
                if (value == 'edit') _editProduct(product);
                if (value == 'adjust') _adjustStock(product);
                if (value == 'history') _openHistory(product);
                if (value == 'archive') _archiveProduct(product);
                if (value == 'duplicate') _duplicateProduct(product);
                if (value == 'delete') _deleteProduct(product);
                if (value == 'flashSale') _openFlashSale(product);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(context.tr('vendor.edit')),
                ),
                // QA #11 (§8.3): from the row too; "View sale" while one
                // is scheduled or live (the price is locked then).
                if (_flashSaleFor(product) case final label?)
                  PopupMenuItem(
                    key: Key('vendor-product-flash-sale-${product['id']}'),
                    value: 'flashSale',
                    child: Text(context.tr(label)),
                  ),
                if (ledger) ...[
                  PopupMenuItem(
                    value: 'adjust',
                    child: Text(context.tr('vendor.stock.adjust')),
                  ),
                  PopupMenuItem(
                    value: 'history',
                    child: Text(context.tr('vendor.stock.history')),
                  ),
                ],
                PopupMenuItem(
                  value: 'archive',
                  child: Text(
                    paused
                        ? context.tr('vendor.restore')
                        : context.tr('vendor.pause'),
                  ),
                ),
                PopupMenuItem(
                  value: 'duplicate',
                  child: Text(context.tr('vendor.duplicate')),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(context.tr('vendor.delete')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // PHOTO_FOOTER_UI (spec §33.6): only on Products while the hero rules
    // show a hero, with at least one product. The FAB overlays the list once
    // the hero has scrolled away, so the footer keeps 88px clear above it.
    if (photoFooterUi && _heroOn(0)) {
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(item, childCount: itemCount),
            ),
          ),
          FFPhotoFooter.sliver(
            key: const Key('vendor-footer'),
            pageKey: 'vendor.products',
            top: FFHeroPhoto.vendor,
            extraBottom: 88,
            gap: FFTokens.spacingXl - FFTokens.spacingLg,
            // A short list keeps today's room for the FAB.
            hiddenExtent: vendorFabClearance - FFTokens.spacingLg,
          ),
        ],
      );
    }
    return ListView.builder(
      // Room under the last card for the floating "Add product" button.
      padding: const EdgeInsets.fromLTRB(
        FFTokens.spacingLg,
        FFTokens.spacingLg,
        FFTokens.spacingLg,
        vendorFabClearance,
      ),
      itemCount: itemCount,
      itemBuilder: item,
    );
  }

  /// All products / Low stock (n). Pills wrap, which long Swahili needs.
  Widget _stockFilter() => Padding(
    padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
    child: Wrap(
      spacing: FFTokens.spacingSm,
      children: [
        FFPill(
          key: const Key('vendor-filter-all'),
          label: context.tr('vendor.stock.all'),
          filled: !_lowOnly,
          onTap: () => setState(() => _lowOnly = false),
        ),
        FFPill(
          key: const Key('vendor-filter-low'),
          label: fillIn(context.tr('vendor.stock.lowFilter'), {
            'n': _low.count,
          }),
          filled: _lowOnly,
          onTap: () => setState(() => _lowOnly = true),
        ),
      ],
    ),
  );

  Widget _ordersTab() {
    if (_orders.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [FFEmptyState(title: context.tr('vendor.noOrders'))],
      );
    }
    return ListView.builder(
      // Room under the last order, so no floating button can cover it.
      padding: const EdgeInsets.fromLTRB(
        FFTokens.spacingLg,
        FFTokens.spacingLg,
        FFTokens.spacingLg,
        vendorFabClearance,
      ),
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        final order = _orders[index];
        final status = order['status']?.toString() ?? 'pending';
        return Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: VendorOrderCard(
            order: order,
            tools: _tools,
            // Legacy `confirmed` / `fulfilled` rows read as accepted /
            // delivered, as the backend reads them.
            actions: shopOrderIsFinal(status)
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                    child: Wrap(
                      spacing: FFTokens.spacingSm,
                      children: [
                        if (vendorNextOrderStatus(order) case final next?)
                          FFButton(
                            key: Key('vendor-next-${order['id']}'),
                            label: vendorMarkStatusLabel(context, next),
                            // Only paid orders can be fulfilled.
                            onPressed:
                                _busy || order['paymentStatus'] == 'pending'
                                ? null
                                : () => _updateOrder(
                                    order['id'].toString(),
                                    next,
                                  ),
                            size: FFButtonSize.sm,
                          ),
                        // Cancelling cannot be undone: it reads as a
                        // destructive action, not as one more safe link.
                        FFButton(
                          key: Key('vendor-cancel-${order['id']}'),
                          label: context.tr('vendor.cancel'),
                          icon: Icons.cancel_outlined,
                          onPressed: _busy
                              ? null
                              : () => _updateOrder(
                                  order['id'].toString(),
                                  'cancelled',
                                ),
                          variant: FFButtonVariant.destructive,
                          size: FFButtonSize.sm,
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  /// S6: tab 2 with Reports on — Reports | Payouts (Payouts only with
  /// `payments`; it is the Payments content unchanged).
  Widget _reportsAndPayoutsTab() {
    final view = _tab2Shown;
    final segments = <(String, String)>[
      ('reports', context.tr('vendor.reports.seg.reports')),
      if (_can('payments'))
        ('payouts', context.tr('vendor.reports.seg.payouts')),
    ];
    final reports = _sales == null
        ? VendorReportsView(
            key: _reportsKey,
            access: _reportAccess,
            staffDisabled: _staffDisabled,
            businessName: _profile['businessName']?.toString(),
          )
        : ListenableBuilder(
            listenable: _sales!,
            builder: (context, _) => VendorReportsView(
              key: _reportsKey,
              access: _reportAccess,
              staffDisabled: _staffDisabled,
              businessName: _profile['businessName']?.toString(),
              pendingSales: _sales!.waiting.length,
            ),
          );
    return Column(
      children: [
        if (segments.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FFTokens.spacingLg,
              FFTokens.spacingMd,
              FFTokens.spacingLg,
              0,
            ),
            child: FFSegmented(
              key: const Key('vendor-reports-segment'),
              value: view,
              options: segments,
              onChanged: (v) => setState(() => _tab2View = v),
            ),
          ),
        Expanded(child: view == 'reports' ? reports : _paymentsTab()),
      ],
    );
  }

  /// "You receive {amount}" under a Payments figure when the server sends
  /// the after-commission value (S6, additive `…NetTzs` fields).
  String? _youReceive(String key) {
    final v = _payments[key];
    if (v is! num) return null;
    return fillIn(context.tr('vendor.reports.youReceiveLine'), {
      'amount': formatCurrency(v),
    });
  }

  Widget _paymentsTab() {
    final net = <String?>[
      _youReceive('todayNetTzs'),
      _youReceive('weeklyNetTzs'),
      _youReceive('monthlyNetTzs'),
      _youReceive('pendingSettlementNetTzs'),
      _youReceive('settledNetTzs'),
    ];
    final cards = <(String, num)>[
      (
        context.tr('vendor.todaySales'),
        _payments['todaySalesTzs'] as num? ?? 0,
      ),
      (
        context.tr('vendor.weeklySales'),
        _payments['weeklySalesTzs'] as num? ?? 0,
      ),
      (
        context.tr('vendor.monthlySales'),
        _payments['monthlySalesTzs'] as num? ?? 0,
      ),
      (
        context.tr('vendor.pendingSettlement'),
        _payments['pendingSettlementTzs'] as num? ?? 0,
      ),
      (
        context.tr('vendor.settledPayments'),
        _payments['settledPaymentsTzs'] as num? ?? 0,
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        if (_taxEntryShown && !_isVendor && !_can('staff')) ...[
          _taxEntry(),
          const SizedBox(height: FFTokens.spacingSm),
        ],
        for (final (i, card) in cards.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: FFCard(
              child: ListTile(
                title: Text(card.$1),
                subtitle: net[i] == null ? null : Text(net[i]!),
                trailing: Text(
                  formatCurrency(card.$2),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ),
        FilledButton.tonalIcon(
          key: const Key('vendor-payouts'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const PartnerPayoutsPage(kind: PayoutKind.vendor),
            ),
          ),
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: Text(context.tr('payouts.title')),
        ),
        // S6: from Payouts to the App sales after commission report.
        if (_reportAccess.payouts) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFButton(
            key: const Key('vendor-payouts-report-link'),
            label: context.tr('vendor.reports.payouts.link'),
            variant: FFButtonVariant.ghost,
            icon: Icons.bar_chart_outlined,
            onPressed: () => context.push(
              reportSectionLink(
                ReportSection.payouts,
                ReportPeriod.initial(),
                'all',
              ),
            ),
          ),
        ],
        const SizedBox(height: FFTokens.spacingSm),
        FFButton(
          key: const Key('vendor-download-statement'),
          label: context.tr('vendor.downloadStatement'),
          onPressed: () async {
            try {
              final statement = await AppScope.of(
                context,
              ).api.vendorStatement();
              await saveTextExport(
                filename: 'fitflex-vendor-statement.csv',
                content: statement,
                mimeType: 'text/csv',
              );
            } catch (_) {
              if (!mounted) return;
              FFSnack.error(context, context.tr('shop.exportFailed'));
            }
          },
          variant: FFButtonVariant.secondary,
          icon: Icons.download_outlined,
        ),
      ],
    );
  }

  Widget _enquiriesTab() {
    if (_enquiries.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [FFEmptyState(title: context.tr('vendor.noEnquiries'))],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      itemCount: _enquiries.length,
      itemBuilder: (context, index) {
        final enquiry = _enquiries[index];
        final messages = (enquiry['messages'] as List? ?? [])
            .whereType<Map>()
            .toList();
        return Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: FFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  messages.isEmpty ? '' : messages.first['message'].toString(),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text('${context.tr('vendor.status')}: ${enquiry['status']}'),
                if (messages.length > 1)
                  Text(
                    '${context.tr('vendor.reply')}: ${messages.last['message']}',
                  ),
                Wrap(
                  children: [
                    FFButton(
                      key: Key('vendor-reply-${enquiry['id']}'),
                      label: context.tr('vendor.reply'),
                      onPressed: () => _replyEnquiry(enquiry),
                      variant: FFButtonVariant.ghost,
                      size: FFButtonSize.sm,
                    ),
                    if (enquiry['status'] != 'resolved')
                      FFButton(
                        label: context.tr('vendor.resolve'),
                        onPressed: () async {
                          await AppScope.of(
                            context,
                          ).api.vendorResolveEnquiry(enquiry['id'].toString());
                          await _refresh();
                        },
                        variant: FFButtonVariant.ghost,
                        size: FFButtonSize.sm,
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _replyEnquiry(Map<String, dynamic> enquiry) async {
    final controller = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('vendor.reply')),
        content: FFTextField(
          key: const Key('vendor-reply-message'),
          controller: controller,
          maxLines: 3,
        ),
        actions: [
          FFButton(
            label: context.tr('shop.send'),
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (send == true && controller.text.trim().isNotEmpty && mounted) {
      await AppScope.of(context).api.vendorReplyEnquiry(
        enquiry['id'].toString(),
        controller.text.trim(),
      );
      await _refresh();
    }
    controller.dispose();
  }

  /// The "Where you sell" nudge's text key, or null. Only for the account
  /// holder of a published profile while `merch.shopAreas` is on.
  String? get _areasNudge {
    if (!_tools.shopAreas || !_isVendor) return null;
    if (_profile['status'] != 'published') return null;
    final city = _profile['cityId']?.toString() ?? '';
    if (city.isEmpty) return 'vendor.areas.nudge';
    if (_profile['areasSource'] == 'backfill') return 'vendor.areas.nudgeCheck';
    return null;
  }

  Widget _businessTab() {
    final api = AppScope.of(context).api;
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _profile['businessName']?.toString() ??
                    context.tr('vendor.profileIncomplete'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${context.tr('vendor.status')}: ${_profile['status'] ?? 'draft'}',
              ),
              Text(_profile['description']?.toString() ?? ''),
              const SizedBox(height: FFTokens.spacingSm),
              if (AppScope.of(context).auth.user?['userType'] != 'vendor_staff')
                Wrap(
                  spacing: FFTokens.spacingSm,
                  runSpacing: FFTokens.spacingSm,
                  children: [
                    FFButton(
                      key: const Key('vendor-edit-profile'),
                      label: context.tr('vendor.editProfile'),
                      onPressed: _editProfile,
                      icon: Icons.edit_outlined,
                    ),
                    FFButton(
                      key: const Key('vendor-verification'),
                      label: context.tr('kyc.entry.title'),
                      onPressed: () => context.push('/verification'),
                      variant: FFButtonVariant.secondary,
                      icon: Icons.verified_user_outlined,
                    ),
                  ],
                ),
            ],
          ),
        ),
        // PARTNER_MEDIA_UI (spec §41.1): the vendor, and staff the server
        // says may change it (vendorRole admin; `canEdit`).
        if (partnerMediaUi)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingMd),
            child: PartnerMediaEntryTile(
              side: 'vendor',
              askServer:
                  AppScope.of(context).auth.user?['userType'] == 'vendor_staff',
            ),
          ),
        // Shop S3: no "Based in" yet (or guessed by the server): say why it
        // matters. Their products still sell; they just miss near-you.
        if (_areasNudge != null)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingMd),
            child: FFCard(
              key: const Key('vendor-areas-nudge'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FFAlert(message: context.tr(_areasNudge!)),
                  const SizedBox(height: FFTokens.spacingSm),
                  FFButton(
                    key: const Key('vendor-areas-nudge-action'),
                    label: context.tr(
                      _areasNudge == 'vendor.areas.nudge'
                          ? 'vendor.areas.nudgeAction'
                          : 'vendor.areas.nudgeCheckAction',
                    ),
                    variant: FFButtonVariant.secondary,
                    // 48 tall at every width (QA2 #4).
                    visualDensity: VisualDensity.standard,
                    // Opens the form at "Where you sell" (QA #8).
                    onPressed: () => _editProfile(toAreas: true),
                  ),
                ],
              ),
            ),
          ),
        // S3: sales still on this device while the Sales tab is gone
        // (feature switched off). They are never deleted for that.
        if (_sales != null)
          ListenableBuilder(
            listenable: _sales!,
            builder: (context, _) => _sales!.isEmpty || _walkInSales
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: FFTokens.spacingMd),
                    child: _salesWaitingTile(),
                  ),
          ),
        if (_taxEntryShown) _taxEntry(),
        // Which offers they get in the app and by push — the same page
        // members and trainers use. Staff without this tab reach it from
        // the inbox.
        Padding(
          padding: const EdgeInsets.only(top: FFTokens.spacingMd),
          child: FFActionTile(
            key: const Key('vendor-message-settings'),
            icon: Icons.notifications_outlined,
            title: context.tr('msgPrefs.title'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MemberMessageSettingsPage(),
              ),
            ),
          ),
        ),
        const SizedBox(height: FFTokens.spacingLg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.tr('vendor.staff'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            // With invitations on, only the vendor itself invites staff.
            if (!_invites || _isVendor)
              FFButton(
                key: const Key('vendor-add-staff'),
                label: context.tr('vendor.addStaff'),
                onPressed: _addStaff,
                variant: FFButtonVariant.ghost,
                size: FFButtonSize.sm,
                icon: Icons.person_add_alt,
              ),
          ],
        ),
        if (_invites && _isVendor)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FFButton(
              key: const Key('vendor-invitations-sent'),
              label: context.tr('invite.sentTitle'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      GymInvitationsPage(gymId: _vendorId, orgType: 'vendor'),
                ),
              ),
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              icon: Icons.outgoing_mail,
            ),
          ),
        for (final staff in _staff)
          FFCard(
            child: ListTile(
              title: Text(staff['displayName']?.toString() ?? ''),
              subtitle: Text('${staff['vendorRole']} · ${staff['email']}'),
              trailing: staff['accountStatus'] == 'suspended'
                  ? Text(context.tr('vendor.disabled'))
                  : FFButton(
                      label: context.tr('vendor.disable'),
                      onPressed: () async {
                        await AppScope.of(
                          context,
                        ).api.vendorDisableStaff(staff['id'].toString());
                        await _refresh();
                      },
                      variant: FFButtonVariant.ghost,
                      size: FFButtonSize.sm,
                    ),
            ),
          ),
        const SizedBox(height: FFTokens.spacingMd),
        DeleteAccountButton(
          confirmLeave: confirmLeaveWithQueuedSales,
          // S4: customer names held in memory go with the session.
          onDeleted: () => CustomerRepository.clear(api),
        ),
      ],
    );
  }

  /// "Sales waiting to sync (n)" → the sync screen (S3).
  Widget _salesWaitingTile() => FFCard(
    child: ListTile(
      key: const Key('vendor-sales-waiting-tile'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.cloud_upload_outlined),
      title: Text(
        fillIn(context.tr('vendor.sync.tile'), {'n': _sales!.all.length}),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(salesSyncRoute),
    ),
  );

  Widget _restrictedTab() {
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [FFEmptyState(title: context.tr('vendor.noAccess'))],
    );
  }

  Future<void> _editProfile({bool toAreas = false}) async {
    final api = AppScope.of(context).api;
    // The form saves itself and stays open on a refusal (S3: invalid_area
    // is shown next to "Where you sell"); it closes only once saved.
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => VendorProfileForm(
        profile: _profile,
        shopAreas: _tools.shopAreas,
        scrollToAreas: toAreas,
        onSave: api.vendorSaveProfile,
        describeError: _saveFailedText,
      ),
    );
    if (result == null || !mounted) return;
    await _refresh();
  }

  bool get _invites => AppScope.of(context).auth.invitesEnabled;
  bool get _isVendor => AppScope.of(context).auth.user?['userType'] == 'vendor';
  String get _vendorId =>
      AppScope.of(context).auth.user?['id']?.toString() ?? '';

  Future<void> _addStaff() async {
    // Identity V2: staff join with their own account; no password is set here.
    if (_invites) {
      await openInvitePersonSheet(
        context,
        gymId: _vendorId,
        role: 'staff',
        orgType: 'vendor',
        vendorSales: _tools.walkInSales,
      );
      if (mounted) await _refresh();
      return;
    }
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => VendorStaffForm(
        walkInSales: _tools.walkInSales,
        customersTool: _tools.customers,
      ),
    );
    if (result == null || !mounted) return;
    await AppScope.of(context).api.vendorCreateStaff(result);
    await _refresh();
  }
}

class VendorProductForm extends StatefulWidget {
  const VendorProductForm({
    super.key,
    this.product,
    this.showTargets = false,
    this.stockLedger = false,
    this.canSeeCost = false,
    this.onSave,
    this.onAdjust,
    this.describeError,
    this.vatCodes,
    this.showFlashSale = false,
  });

  final Map<String, dynamic>? product;

  /// Phase 2 S4 (`merch.flashSales`): "Start a flash sale" on a saved
  /// product, and the price lock while one is scheduled or live (the row's
  /// `priceLock`). Off: neither.
  final bool showFlashSale;

  /// Shop Phase 2 S2: the optional "Made for" and "Age group" pickers, sent
  /// as `targetGender` and `targetAgeBands`. Off: neither is shown or sent.
  final bool showTargets;

  /// S5: the VAT codes offered (GET /vendor/tax-rates), or null to hide the
  /// VAT code field. A private field: saving it never re-queues approval.
  final List<VatCodeOption>? vatCodes;

  /// Vendor tools · S1 is on: per-variant rows, reorder level, cost price,
  /// stock changed only through "Adjust stock". Off: the form as before.
  final bool stockLedger;

  /// Cost price is shown and sent only when this is true.
  final bool canSeeCost;

  /// Ledger on: saves the body; the form stays open (values kept) when it
  /// throws, and closes with `true` when it succeeds.
  final Future<void> Function(Map<String, dynamic> body)? onSave;

  /// Ledger on: opens "Adjust stock" for the product (variant null) or one
  /// variant, resolving with the product's counts `{stock, variants}`. The
  /// outcome is reported through `notify` so the form can show it.
  final Future<Map<String, dynamic>?> Function(
    String? variant,
    AdjustNotify notify,
  )?
  onAdjust;

  /// Ledger on: the words for a failed save.
  final String Function(Object error)? describeError;

  @override
  State<VendorProductForm> createState() => _VendorProductFormState();
}

class _VendorProductFormState extends State<VendorProductForm> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  // The category key to send: the product's own when it is on the list, or
  // the vendor's new pick. Null keeps an older free-text category untouched.
  String? _category;
  late final TextEditingController _brand;
  late final TextEditingController _price;
  late final TextEditingController _discountPrice;
  late final TextEditingController _stock;
  late final TextEditingController _sku;
  late final TextEditingController _weight;
  late final TextEditingController _variants;
  late final TextEditingController _cost;
  late final TextEditingController _reorder;
  final List<VariantDraft> _variantRows = [];
  Map<int, String> _variantErrors = const {};
  String? _saveError;
  String? _nameError;
  String? _priceError;
  final _nameKey = GlobalKey();
  final _priceKey = GlobalKey();
  final _variantsKey = GlobalKey();
  bool _saving = false;
  String? _image;
  String? _secondImage;
  bool _visible = true;
  String _vatCode = 'A';

  /// "Made for": null (everyone), `women` or `men`.
  String? _targetGender;

  /// "Age group": empty means all ages.
  final Set<String> _ageBands = {};

  bool get _creating => widget.product == null;

  /// The stock the form loaded (sent as `stockSeen` with a changed stock).
  int get _stockLoaded => (widget.product?['stock'] as num?)?.toInt() ?? 0;

  /// Whether the vendor changed the Stock field (ledger off).
  bool get _stockEdited =>
      _stock.text.trim() != (widget.product?['stock']?.toString() ?? '');
  bool get _ledger => widget.stockLedger;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?['name']?.toString());
    final storedCategory = product?['category']?.toString();
    if (ProductCategories.current.any((c) => c.key == storedCategory)) {
      _category = storedCategory;
    }
    _description = TextEditingController(
      text: product?['description']?.toString(),
    );
    _brand = TextEditingController(text: product?['brand']?.toString());
    _price = TextEditingController(text: product?['priceTzs']?.toString());
    _discountPrice = TextEditingController(
      text: product?['discountPriceTzs']?.toString(),
    );
    _stock = TextEditingController(text: product?['stock']?.toString());
    _sku = TextEditingController(text: product?['sku']?.toString());
    _weight = TextEditingController(text: product?['weightKg']?.toString());
    _variants = TextEditingController(
      text: (product?['variants'] as List? ?? [])
          .whereType<Map>()
          .map((item) => item['name'])
          .join(', '),
    );
    _cost = TextEditingController(text: product?['costTzs']?.toString());
    _reorder = TextEditingController(
      text: product?['reorderLevel']?.toString(),
    );
    for (final v in (product?['variants'] as List? ?? []).whereType<Map>()) {
      _variantRows.add(VariantDraft.stored(v));
    }
    final images = (product?['images'] as List?)?.whereType<String>().toList();
    _image = images?.firstOrNull;
    _secondImage = images != null && images.length > 1 ? images[1] : null;
    _visible = product?['visibility'] != 'hidden';
    final gender = product?['targetGender']?.toString();
    if (kTargetGenders.contains(gender)) _targetGender = gender;
    for (final b in (product?['targetAgeBands'] as List? ?? const [])) {
      if (kTargetAgeBands.contains(b)) _ageBands.add(b.toString());
    }
    // All four bands is "All ages" (the server stores and returns []).
    if (_ageBands.length == kTargetAgeBands.length) _ageBands.clear();
    final code = product?['vatCode']?.toString();
    final codes = widget.vatCodes ?? const <VatCodeOption>[];
    _vatCode = codes.any((c) => c.code == code)
        ? code!
        : codes.any((c) => c.code == 'A') || codes.isEmpty
        ? 'A'
        : codes.first.code;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _brand.dispose();
    _price.dispose();
    _discountPrice.dispose();
    _stock.dispose();
    _sku.dispose();
    _weight.dispose();
    _variants.dispose();
    _cost.dispose();
    _reorder.dispose();
    for (final row in _variantRows) {
      row.dispose();
    }
    super.dispose();
  }

  /// The fields every save sends, both with and without the ledger.
  Map<String, dynamic>? _common() {
    final price = num.tryParse(_price.text.trim());
    if (_name.text.trim().isEmpty || price == null || price <= 0) return null;
    return {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      if (_category != null) 'category': _category,
      'brand': _brand.text.trim(),
      'priceTzs': price,
      'discountPriceTzs': num.tryParse(_discountPrice.text.trim()),
      'sku': _sku.text.trim(),
      'weightKg': num.tryParse(_weight.text.trim()),
      'visibility': _visible ? 'visible' : 'hidden',
      'images': [?_image, ?_secondImage],
      if (widget.showTargets) ...{
        'targetGender': _targetGender,
        'targetAgeBands': [
          for (final b in kTargetAgeBands)
            if (_ageBands.contains(b)) b,
        ],
      },
      if (widget.vatCodes != null) 'vatCode': _vatCode,
    };
  }

  void _submit() {
    if (_ledger) {
      _submitLedger();
      return;
    }
    final common = _common();
    if (common == null) return;
    Navigator.pop(context, {
      ...common,
      // A new product sends its starting stock. An edit sends stock only
      // when the vendor changed it, with the count the form loaded
      // (`stockSeen`), so a form left open while buyers reserved stock does
      // not overwrite it (live-bug fix, S1 / F2). Variants never carry
      // stock on an edit; the server keeps their stored counts.
      if (_creating) 'stock': int.tryParse(_stock.text.trim()) ?? 0,
      if (!_creating && _stockEdited) ...{
        'stock': int.tryParse(_stock.text.trim()) ?? 0,
        'stockSeen': _stockLoaded,
      },
      'variants': _variants.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .map((value) => {'name': value})
          .toList(),
    });
  }

  int get _variantSum => _variantRows.fold(
    0,
    (sum, row) =>
        sum +
        (_creating
            ? int.tryParse(row.stock.text.trim()) ?? 0
            : row.storedStock ?? 0),
  );

  /// The body with the ledger on. Null when something needs fixing first.
  Map<String, dynamic>? _ledgerBody() {
    final errors = validateVariants(_variantRows);
    final price = num.tryParse(_price.text.trim());
    final nameError = _name.text.trim().isEmpty
        ? context.tr('vendor.form.nameRequired')
        : null;
    final priceError = price == null || price <= 0
        ? context.tr('vendor.form.priceRequired')
        : null;
    final invalid =
        nameError != null || priceError != null || errors.isNotEmpty;
    setState(() {
      _variantErrors = errors;
      _nameError = nameError;
      _priceError = priceError;
      // Never a silent Save: say what to fix, next to the button too.
      _saveError = invalid ? context.tr('vendor.form.fixErrors') : null;
    });
    if (invalid) {
      // Bring the first problem into view.
      final target = nameError != null
          ? _nameKey
          : priceError != null
          ? _priceKey
          : _variantsKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = target.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 200),
          );
        }
      });
      return null;
    }
    final common = _common();
    if (common == null) return null;
    // A variant the vendor tried to remove while it had stock stays in the
    // list (it was never removed), so it is simply saved as kept.
    int? whole(TextEditingController c) => int.tryParse(c.text.trim());
    return {
      ...common,
      if (_creating)
        'stock': _variantRows.isEmpty ? whole(_stock) ?? 0 : _variantSum,
      if (widget.canSeeCost) 'costTzs': whole(_cost),
      'reorderLevel': whole(_reorder),
      'variants': variantsPayload(
        _variantRows,
        creating: _creating,
        withCost: widget.canSeeCost,
      ),
    };
  }

  Future<void> _submitLedger() async {
    final body = _ledgerBody();
    final save = widget.onSave;
    if (body == null || save == null) return;
    setState(() => _saving = true);
    try {
      await save(body);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = _ledgerSaveError(e);
      });
    }
  }

  /// Variant problems the server found are shown on their row.
  String? _ledgerSaveError(Object e) {
    if (e is ApiException) {
      final body = e.body is Map ? e.body as Map : const {};
      final variant = body['variant']?.toString();
      int rowOf(String? name) =>
          _variantRows.indexWhere((r) => (r.original ?? r.trimmedName) == name);
      switch (e.code) {
        case 'variant_has_stock':
          final i = rowOf(variant);
          if (i >= 0) {
            _variantErrors = {
              ..._variantErrors,
              i: 'vendor.variant.removeHasStock',
            };
            return null;
          }
          return context.tr('vendor.variant.removeHasStock');
        case 'duplicate_variant':
          final i = _variantRows.indexWhere(
            (r) => r.trimmedName.toLowerCase() == variant?.toLowerCase(),
          );
          if (i >= 0) {
            _variantErrors = {
              ..._variantErrors,
              i: 'vendor.variant.duplicateName',
            };
            return null;
          }
          return context.tr('vendor.variant.duplicateName');
        case 'variant_has_reservations':
          return fillIn(context.tr('vendor.variant.hasReservations'), {
            'name': variant ?? '',
          });
        case 'variant_stock_mixed':
          return context.tr('vendor.variant.stockMixed');
        case 'cost_forbidden':
          return context.tr('vendor.costForbidden');
        case 'stock_changed':
          // Stock moved since the form opened: show the new counts.
          final current = (body['currentStock'] as num?)?.toInt();
          final i = variant == null ? -1 : rowOf(variant);
          if (i >= 0 && current != null) {
            _variantRows[i].storedStock = current;
          } else if (variant == null && current != null) {
            _stock.text = '$current';
          }
          return context.tr('vendor.stock.changedForm');
      }
    }
    return widget.describeError?.call(e) ?? context.tr('vendor.saveFailed');
  }

  /// The outcome of the last product-level adjustment, shown under its
  /// button (variant ones show under their row).
  ({String message, bool error})? _stockNotice;

  Future<void> _adjust([String? variant]) async {
    final adjust = widget.onAdjust;
    if (adjust == null) return;
    setState(() {
      _stockNotice = null;
      for (final row in _variantRows) {
        row.notice = null;
      }
    });
    final fresh = await adjust(variant, (message, {required error}) {
      if (!mounted) return;
      final notice = (message: message, error: error);
      setState(() {
        if (variant == null) {
          _stockNotice = notice;
        } else {
          for (final row in _variantRows) {
            if (row.original == variant) row.notice = notice;
          }
        }
      });
    });
    if (fresh == null || !mounted) return;
    setState(() {
      if (fresh['stock'] is num) _stock.text = '${fresh['stock']}';
      for (final v in (fresh['variants'] as List? ?? []).whereType<Map>()) {
        for (final row in _variantRows) {
          if (row.original == v['name']) {
            row.storedStock = (v['stock'] as num?)?.toInt();
            if (!row.holdsStock) row.removeBlocked = false;
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ledger) return _ledgerForm(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: FFTokens.spacingLg,
          right: FFTokens.spacingLg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + FFTokens.spacingLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.product == null
                    ? context.tr('vendor.addProduct')
                    : context.tr('vendor.editProduct'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: FFTokens.spacingMd),
              ..._topFields(),
              Row(
                children: [
                  Expanded(child: _priceField()),
                  const SizedBox(width: FFTokens.spacingMd),
                  Expanded(
                    child: FFTextField(
                      key: const Key('vendor-product-stock'),
                      controller: _stock,
                      keyboardType: TextInputType.number,
                      label: context.tr('vendor.stock'),
                    ),
                  ),
                ],
              ),
              ..._middleFields(),
              FFTextField(
                key: const Key('vendor-product-variants'),
                controller: _variants,
                label: context.tr('vendor.variants'),
                hint: context.tr('vendor.variantsHint'),
              ),
              ..._bottomFields(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _topFields() => [
    Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FFPhotoPickerField(
            value: _image,
            onChanged: (value) => setState(() => _image = value),
          ),
          const SizedBox(width: FFTokens.spacingMd),
          FFPhotoPickerField(
            value: _secondImage,
            onChanged: (value) => setState(() => _secondImage = value),
          ),
        ],
      ),
    ),
    KeyedSubtree(
      key: _nameKey,
      child: FFTextField(
        key: const Key('vendor-product-name'),
        controller: _name,
        label: context.tr('vendor.name'),
        errorText: _ledger ? _nameError : null,
        onChanged: _ledger ? (_) => _clearFieldError() : null,
      ),
    ),
    FFTextField(
      key: const Key('vendor-product-brand'),
      controller: _brand,
      label: context.tr('vendor.brand'),
    ),
    FFTextField(
      key: const Key('vendor-product-description'),
      controller: _description,
      label: context.tr('vendor.description'),
    ),
    ProductCategoryDropdown(
      current: widget.product?['category']?.toString(),
      onChanged: (key) => _category = key,
    ),
    if (widget.showTargets) _targetFields(),
  ];

  /// "Who it's for (optional)" (spec §6.2): Made for, single choice; Age
  /// group, several bands, where "All ages" clears the bands and picking a
  /// band clears "All ages".
  Widget _targetFields() {
    final theme = Theme.of(context);
    final madeFor = context.tr('vendor.target.madeFor');
    final ageGroup = context.tr('vendor.target.ageGroup');
    String option(String group, String label) => fillIn(
      context.tr('vendor.target.a11yOption'),
      {'group': group, 'option': label},
    );
    String bandSpoken(String band) {
      final parts = band.split('_');
      return parts.last == 'plus'
          ? fillIn(context.tr('vendor.target.a11yBandPlus'), {
              'from': parts.first,
            })
          : fillIn(context.tr('vendor.target.a11yBand'), {
              'from': parts.first,
              'to': parts.last,
            });
    }

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingSm),
      child: Text(text, style: theme.textTheme.labelLarge),
    );
    Widget chip(
      String key,
      String text,
      bool sel,
      VoidCallback onTap, {
      String? spoken,
      FFChipSelection selection = FFChipSelection.checkbox,
    }) => FFFilterChip(
      key: Key(key),
      label: text,
      semanticLabel: spoken,
      selection: selection,
      selected: sel,
      tone: FFFilterChipTone.tint,
      onSelected: _saving ? () {} : onTap,
    );

    final everyone = context.tr('vendor.target.everyone');
    final allAges = context.tr('vendor.target.allAges');
    return Padding(
      key: const Key('vendor-product-targets'),
      padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              context.tr('vendor.target.title'),
              style: theme.textTheme.titleSmall,
            ),
          ),
          Text(
            context.tr('vendor.target.hint'),
            style: theme.textTheme.bodySmall,
          ),
          label(madeFor),
          Wrap(
            spacing: FFTokens.spacingSm,
            children: [
              chip(
                'vendor-target-gender-everyone',
                everyone,
                _targetGender == null,
                () => setState(() => _targetGender = null),
                spoken: option(madeFor, everyone),
                selection: FFChipSelection.radio,
              ),
              for (final g in kTargetGenders)
                chip(
                  'vendor-target-gender-$g',
                  context.tr('vendor.target.$g'),
                  _targetGender == g,
                  () => setState(() => _targetGender = g),
                  spoken: option(madeFor, context.tr('vendor.target.$g')),
                  selection: FFChipSelection.radio,
                ),
            ],
          ),
          label(ageGroup),
          Wrap(
            spacing: FFTokens.spacingSm,
            children: [
              chip(
                'vendor-target-age-all',
                allAges,
                _ageBands.isEmpty,
                () => setState(_ageBands.clear),
                spoken: option(ageGroup, allAges),
              ),
              for (final b in kTargetAgeBands)
                chip(
                  'vendor-target-age-$b',
                  context.tr('vendor.target.band.$b'),
                  _ageBands.contains(b),
                  () => setState(() {
                    _ageBands.contains(b)
                        ? _ageBands.remove(b)
                        : _ageBands.add(b);
                    // Every band picked is "All ages" (the server's []).
                    if (_ageBands.length == kTargetAgeBands.length) {
                      _ageBands.clear();
                    }
                  }),
                  spoken: option(ageGroup, bandSpoken(b)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Phase 2 S4: the product's `priceLock` (`{saleId, startsAt, endsAt}`)
  /// while an approved flash sale has not ended. Price and discount price
  /// are then read-only (the server refuses a change with 409).
  Map? get _priceLock {
    final lock = widget.product?['priceLock'];
    return widget.showFlashSale && lock is Map ? lock : null;
  }

  /// "Locked while your flash sale runs ({start}–{end})."
  String? _lockHelper() {
    final lock = _priceLock;
    if (lock == null) return null;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    String when(Object? v) {
      final d = DateTime.tryParse('${v ?? ''}');
      return d == null ? '-' : formatDateTime(toEatWallClock(d), locale: lang);
    }

    return context
        .tr('vendor.priceLocked')
        .replaceAll('{start}', when(lock['startsAt']))
        .replaceAll('{end}', when(lock['endsAt']));
  }

  Widget _priceField() => KeyedSubtree(
    key: _priceKey,
    child: FFTextField(
      key: const Key('vendor-product-price'),
      controller: _price,
      keyboardType: TextInputType.number,
      label: context.tr('vendor.price'),
      // Locked: greyed like the discount price, the reason under both.
      enabled: _priceLock == null,
      errorText: _ledger ? _priceError : null,
      onChanged: _ledger ? (_) => _clearFieldError() : null,
    ),
  );

  /// "View sale" under a locked price, and "Start a flash sale" on a saved
  /// product that has none (Phase 2 S4).
  Widget _flashSaleActions() {
    final id = widget.product?['id']?.toString() ?? '';
    if (!widget.showFlashSale || id.isEmpty) return const SizedBox.shrink();
    final lock = _priceLock;
    final saleId = lock?['saleId']?.toString() ?? '';
    final status = widget.product?['status']?.toString() ?? 'active';
    final approval =
        widget.product?['approvalStatus']?.toString() ?? 'approved';
    if (lock == null && (status != 'active' || approval != 'approved')) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FFButton(
        key: Key(
          lock != null
              ? 'vendor-product-view-sale'
              : 'vendor-product-start-sale',
        ),
        label: context.tr(
          lock != null ? 'vendor.viewSale' : 'merch.sale.start',
        ),
        icon: Icons.bolt_outlined,
        variant: FFButtonVariant.ghost,
        visualDensity: VisualDensity.standard,
        maxLines: 2,
        onPressed: () => context.push(
          lock != null
              ? Uri(
                  path: AppRoutes.vendorMerch,
                  queryParameters: {
                    'tab': 'sales',
                    if (saleId.isNotEmpty) 'item': saleId,
                  },
                ).toString()
              : '${AppRoutes.vendorMerchSaleNew}?productId=${Uri.encodeQueryComponent(id)}',
        ),
      ),
    );
  }

  /// Typing clears the previous save's messages.
  void _clearFieldError() {
    if (_nameError == null && _priceError == null && _saveError == null) {
      return;
    }
    setState(() {
      _nameError = null;
      _priceError = null;
      _saveError = null;
    });
  }

  List<Widget> _middleFields() => [
    FFTextField(
      key: const Key('vendor-product-discount-price'),
      controller: _discountPrice,
      keyboardType: TextInputType.number,
      label: context.tr('vendor.discountPrice'),
      enabled: _priceLock == null,
    ),
    // QA #6: its own line, wrapping fully at any width and text size.
    if (_lockHelper() case final why?)
      Padding(
        padding: const EdgeInsets.only(top: FFTokens.spacingXs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(
              child: Icon(Icons.lock_outline, size: FFTokens.iconSm),
            ),
            const SizedBox(width: FFTokens.spacingXs),
            Expanded(
              child: Text(
                why,
                key: const Key('vendor-product-price-locked'),
                softWrap: true,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    _flashSaleActions(),
    Row(
      children: [
        Expanded(
          child: FFTextField(
            key: const Key('vendor-product-sku'),
            controller: _sku,
            label: context.tr('vendor.sku'),
          ),
        ),
        const SizedBox(width: FFTokens.spacingMd),
        Expanded(
          child: FFTextField(
            key: const Key('vendor-product-weight'),
            controller: _weight,
            keyboardType: TextInputType.number,
            label: context.tr('vendor.weight'),
          ),
        ),
      ],
    ),
  ];

  /// "A · Standard 18%", "C · Zero-rated 0%", "E · Exempt".
  String _vatLabel(VatCodeOption c) => fillIn(
    context.tr('vendor.vat.${c.code}'),
    {'rate': ratePctText(c.ratePct) ?? ''},
  );

  Widget _vatField() {
    final codes = widget.vatCodes!;
    final name = _name.text.trim();
    return Semantics(
      label: fillIn(context.tr('vendor.product.vatA11y'), {'product': name}),
      child: DropdownButtonFormField<String>(
        key: const Key('vendor-product-vat-code'),
        initialValue: _vatCode,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: context.tr('vendor.product.vatCode'),
          helperText: context.tr('vendor.product.vatHint'),
          helperMaxLines: 3,
        ),
        items: [
          for (final c in codes)
            DropdownMenuItem(
              value: c.code,
              child: Text(_vatLabel(c), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: _saving
            ? null
            : (v) {
                if (v != null) setState(() => _vatCode = v);
              },
      ),
    );
  }

  List<Widget> _bottomFields() => [
    if (widget.vatCodes != null) ...[
      _vatField(),
      const SizedBox(height: FFTokens.spacingSm),
    ],
    SwitchListTile(
      key: const Key('vendor-product-visibility'),
      contentPadding: EdgeInsets.zero,
      value: _visible,
      onChanged: (value) => setState(() => _visible = value),
      title: Text(context.tr('vendor.visible')),
    ),
    if (_saveError != null) ...[
      FFAlert(
        key: const Key('vendor-product-save-error'),
        message: _saveError!,
        tone: FFAlertTone.error,
      ),
      const SizedBox(height: FFTokens.spacingSm),
    ],
    const SizedBox(height: FFTokens.spacingLg),
    SizedBox(
      width: double.infinity,
      child: FFButton(
        key: const Key('vendor-product-save'),
        label: context.tr('vendor.save'),
        // A full 48dp target on web and desktop too.
        visualDensity: VisualDensity.standard,
        loading: _saving,
        onPressed: _saving ? null : _submit,
      ),
    ),
  ];

  /// Two fields side by side, or one above the other when either would be
  /// narrower than 160 (large text, Swahili).
  Widget _pair(Widget a, Widget b) => LayoutBuilder(
    builder: (context, box) {
      final scaled = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
      // Swahili labels ("Kiwango cha kuagiza tena") need more room.
      final sw = FFLocaleScope.of(context).locale.languageCode == 'sw';
      final minField = sw ? 200.0 : 160.0;
      if (scaled || box.maxWidth < 2 * minField + FFTokens.spacingMd) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            a,
            const SizedBox(height: FFTokens.spacingSm),
            b,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: FFTokens.spacingMd),
          Expanded(child: b),
        ],
      );
    },
  );

  Widget _ledgerStockField() {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    if (_variantRows.isNotEmpty) {
      // O-1: with variants, the product's stock is their total.
      return KeyedSubtree(
        key: ValueKey('vendor-product-total-$_variantSum'),
        child: FFTextField(
          key: const Key('vendor-product-stock'),
          initialValue: '$_variantSum',
          readOnly: true,
          label: context.tr('vendor.stock.totalFromVariants'),
        ),
      );
    }
    if (_creating) {
      return FFTextField(
        key: const Key('vendor-product-stock'),
        controller: _stock,
        keyboardType: TextInputType.number,
        inputFormatters: digits,
        label: context.tr('vendor.stock.initial'),
      );
    }
    return FFTextField(
      key: const Key('vendor-product-stock'),
      controller: _stock,
      readOnly: true,
      label: context.tr('vendor.stock.current'),
      helperText: context.tr('vendor.stock.readOnlyHelp'),
    );
  }

  /// [children] with a small token gap between each.
  List<Widget> _spaced(List<Widget> children) => [
    for (var i = 0; i < children.length; i++) ...[
      if (i > 0) const SizedBox(height: FFTokens.spacingSm),
      children[i],
    ],
  ];

  Widget _ledgerForm(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final reorder = FFTextField(
      key: const Key('vendor-product-reorder'),
      controller: _reorder,
      enabled: !_saving,
      keyboardType: TextInputType.number,
      inputFormatters: digits,
      label: context.tr('vendor.stock.reorderLevel'),
      helperText: context.tr('vendor.stock.reorderHelp'),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AbsorbPointer(
          absorbing: _saving,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            // Token spacing between fields, so floating labels never touch
            // the field above.
            children: _spaced([
              ..._topFields(),
              _pair(_priceField(), _ledgerStockField()),
              if (!_creating && widget.onAdjust != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FFButton(
                    key: const Key('vendor-product-adjust'),
                    label: context.tr('vendor.stock.adjust'),
                    icon: Icons.tune,
                    variant: FFButtonVariant.ghost,
                    visualDensity: VisualDensity.standard,
                    onPressed: () => _adjust(),
                  ),
                ),
              if (_stockNotice case final notice?)
                Semantics(
                  liveRegion: true,
                  child: FFAlert(
                    key: const Key('vendor-product-stock-notice'),
                    message: notice.message,
                    tone: notice.error
                        ? FFAlertTone.error
                        : FFAlertTone.success,
                  ),
                ),
              if (widget.canSeeCost)
                _pair(
                  FFTextField(
                    key: const Key('vendor-product-cost'),
                    controller: _cost,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    label: context.tr('vendor.costPrice'),
                    helperText: context.tr('vendor.costPriceHelp'),
                  ),
                  reorder,
                )
              else
                reorder,
              ..._middleFields(),
              VariantRowsEditor(
                key: _variantsKey,
                rows: _variantRows,
                creating: _creating,
                showCost: widget.canSeeCost,
                errors: _variantErrors,
                enabled: !_saving,
                // Editing variants clears the last save's messages.
                onChanged: () => setState(() {
                  _variantErrors = const {};
                  _saveError = null;
                }),
                onAdjust: widget.onAdjust == null ? null : _adjust,
              ),
              ..._bottomFields(),
            ]),
          ),
        ),
      ),
    );
  }
}

class VendorProfileForm extends StatefulWidget {
  const VendorProfileForm({
    super.key,
    required this.profile,
    this.shopAreas = false,
    this.onSave,
    this.describeError,
    this.scrollToAreas = false,
  });

  final Map<String, dynamic> profile;

  /// Opened from the "Add where you're based" nudge: scroll to "Where you
  /// sell" once it is laid out (QA #8).
  final bool scrollToAreas;

  /// Saves the profile (PUT /vendor/profile). Set: the form stays open on a
  /// failure and says why; it closes with the body once saved. Unset: the
  /// form just closes with the body (the caller saves).
  final Future<Object?> Function(Map<String, dynamic> body)? onSave;

  /// The message for a failed save other than `invalid_area`.
  final String Function(Object error)? describeError;

  /// Shop Phase 2 S3 (`merch.shopAreas`): the "Where you sell" pickers.
  final bool shopAreas;

  @override
  State<VendorProfileForm> createState() => _VendorProfileFormState();
}

class _VendorProfileFormState extends State<VendorProfileForm> {
  late final Map<String, TextEditingController> _fields;
  // The business's product categories (keys from the fixed list).
  late List<String> _categories;
  // A business category typed before the list existed, kept until replaced.
  late final String _legacyCategory;
  String? _logo;
  String? _banner;
  late final VendorAreasController _areas = VendorAreasController(
    widget.profile,
  );

  @override
  void initState() {
    super.initState();
    String value(String key) {
      final raw = widget.profile[key];
      if (raw is List) return raw.join(', ');
      if (raw is Map) return raw.values.join(', ');
      return raw?.toString() ?? '';
    }

    _fields = {
      for (final key in [
        'businessName',
        'description',
        'contactNumber',
        'email',
        'address',
        'businessHours',
        'settlementAccount',
      ])
        key: TextEditingController(text: value(key)),
    };
    final stored = widget.profile['productCategories'];
    _categories = ProductCategories.keysFor([
      if (stored is List) ...stored,
      if (stored is! List || stored.isEmpty) widget.profile['businessCategory'],
    ]);
    _legacyCategory = value('businessCategory').trim();
    _logo = widget.profile['logo']?.toString();
    _banner = widget.profile['banner']?.toString();
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _areas.dispose();
    super.dispose();
  }

  bool _saving = false;
  String? _saveError;
  final _areasKey = GlobalKey(debugLabel: 'vendor-areas');
  bool _revealed = false;

  void _revealAreas() {
    if (_revealed) return;
    _revealed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _areasKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.1,
        duration: MediaQuery.disableAnimationsOf(ctx)
            ? Duration.zero
            : FFTokens.motionMedium,
      );
    });
  }

  Future<void> _save(Map<String, dynamic> body) async {
    final save = widget.onSave;
    if (save == null) {
      Navigator.pop(context, body);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    _areas.clearInvalid();
    try {
      await save(body);
      if (!mounted) return;
      Navigator.pop(context, body);
    } catch (e) {
      if (!mounted) return;
      final areaError = _areas.invalidMessage(e, FFLocaleScope.of(context));
      setState(() {
        _saving = false;
        _saveError = areaError == null
            ? widget.describeError?.call(e) ?? context.tr('vendor.saveFailed')
            : null;
      });
    }
  }

  void _submit() {
    if (_saving) return;
    // "Based in" is needed once the pickers are shown (spec §7.4).
    if (widget.shopAreas && _areas.missingBasedIn) {
      _areas.flagMissing();
      return;
    }
    if (_logo == null || _banner == null) return;
    // The email is optional; everything else is needed to publish.
    if (_fields.entries.any(
      (e) => e.key != 'email' && e.value.text.trim().isEmpty,
    )) {
      return;
    }
    if (_categories.isEmpty && _legacyCategory.isEmpty) return;
    // The server still asks for one business category: the first one picked
    // (its English name) keeps older readers of the profile working.
    final businessCategory = _categories.isEmpty
        ? _legacyCategory
        : ProductCategories.current
              .firstWhere(
                (c) => c.key == _categories.first,
                orElse: () => ProductCategory(
                  _categories.first,
                  _categories.first,
                  _categories.first,
                ),
              )
              .en;
    _save({
      'businessName': _fields['businessName']!.text.trim(),
      'logo': _logo,
      'banner': _banner,
      'description': _fields['description']!.text.trim(),
      'businessCategory': businessCategory,
      'contactNumber': _fields['contactNumber']!.text.trim(),
      'email': _fields['email']!.text.trim(),
      'address': _fields['address']!.text.trim(),
      'businessHours': {'summary': _fields['businessHours']!.text.trim()},
      'settlementAccount': {
        'account': _fields['settlementAccount']!.text.trim(),
      },
      if (_categories.isNotEmpty) 'productCategories': _categories,
      if (widget.shopAreas) ..._areas.body(),
      'publish': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    final labels = {
      'businessName': context.tr('vendor.businessName'),
      'description': context.tr('vendor.businessDescription'),
      'contactNumber': context.tr('vendor.contactNumber'),
      'email': context.tr('vendor.emailOptional'),
      'address': context.tr('vendor.address'),
      'businessHours': context.tr('vendor.businessHours'),
      'settlementAccount': context.tr('vendor.settlementAccount'),
    };
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          0,
          FFTokens.spacingLg,
          MediaQuery.viewInsetsOf(context).bottom + FFTokens.spacingLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('vendor.editProfile'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: FFTokens.spacingMd),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      Text(context.tr('vendor.logo')),
                      FFPhotoPickerField(
                        value: _logo,
                        onChanged: (value) => setState(() => _logo = value),
                      ),
                    ],
                  ),
                  const SizedBox(width: FFTokens.spacingMd),
                  Column(
                    children: [
                      Text(context.tr('vendor.banner')),
                      FFPhotoPickerField(
                        value: _banner,
                        onChanged: (value) => setState(() => _banner = value),
                      ),
                    ],
                  ),
                ],
              ),
              for (final entry in _fields.entries) ...[
                FFTextField(
                  key: Key('vendor-profile-${entry.key}'),
                  controller: entry.value,
                  label: labels[entry.key],
                ),
                // S3: "Where you sell" right after "Address".
                if (entry.key == 'address' && widget.shopAreas)
                  VendorAreasSection(
                    key: _areasKey,
                    controller: _areas,
                    onReady: widget.scrollToAreas ? _revealAreas : null,
                  ),
              ],
              const SizedBox(height: FFTokens.spacingSm),
              ProductCategoryMultiSelect(
                keyPrefix: 'vendor-profile-category',
                selected: _categories,
                onChanged: (next) => setState(() => _categories = next),
              ),
              const SizedBox(height: FFTokens.spacingLg),
              SizedBox(
                width: double.infinity,
                child: FFButton(
                  key: const Key('vendor-profile-publish'),
                  label: context.tr('vendor.publishProfile'),
                  loading: _saving,
                  onPressed: _submit,
                ),
              ),
              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _saveError!,
                      key: const Key('vendor-profile-save-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class VendorStaffForm extends StatefulWidget {
  const VendorStaffForm({
    super.key,
    this.walkInSales = false,
    this.customersTool = false,
  });

  /// S3: offer the `sales` permission (only while walk-in sales are on).
  final bool walkInSales;

  /// S4: `customers` now also covers balances and payments; say so.
  final bool customersTool;

  @override
  State<VendorStaffForm> createState() => _VendorStaffFormState();
}

class _VendorStaffFormState extends State<VendorStaffForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String _role = 'inventory_manager';
  final Set<String> _permissions = {'products'};

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if ([
      _name,
      _email,
      _phone,
      _password,
    ].any((controller) => controller.text.trim().isEmpty)) {
      return;
    }
    Navigator.pop(context, {
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'password': _password.text,
      'role': _role,
      'permissions': _permissions.toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final permissions = [
      'products',
      'orders',
      if (widget.walkInSales) 'sales',
      'customers',
      'reports',
      'payments',
      'staff',
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          0,
          FFTokens.spacingLg,
          MediaQuery.viewInsetsOf(context).bottom + FFTokens.spacingLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr('vendor.addStaff'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              FFTextField(
                key: const Key('vendor-staff-name'),
                controller: _name,
                label: context.tr('vendor.staffName'),
              ),
              FFTextField(
                key: const Key('vendor-staff-email'),
                controller: _email,
                label: context.tr('vendor.email'),
              ),
              FFTextField(
                key: const Key('vendor-staff-phone'),
                controller: _phone,
                label: context.tr('vendor.phone'),
              ),
              FFTextField(
                key: const Key('vendor-staff-password'),
                controller: _password,
                obscureText: true,
                label: context.tr('vendor.password'),
              ),
              FFDropdownField<String>(
                key: const Key('vendor-staff-role'),
                value: _role,
                label: context.tr('vendor.role'),
                items: [
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text(context.tr('vendor.roleAdmin')),
                  ),
                  DropdownMenuItem(
                    value: 'inventory_manager',
                    child: Text(context.tr('vendor.roleInventory')),
                  ),
                  DropdownMenuItem(
                    value: 'orders_manager',
                    child: Text(context.tr('vendor.roleOrders')),
                  ),
                  DropdownMenuItem(
                    value: 'sales',
                    child: Text(context.tr('vendor.roleSales')),
                  ),
                  DropdownMenuItem(
                    value: 'customer_care',
                    child: Text(context.tr('vendor.roleCare')),
                  ),
                ],
                onChanged: (value) => setState(() {
                  _role = value ?? _role;
                  // Q-15: the Sales role starts with the sales permission.
                  if (_role == 'sales' && widget.walkInSales) {
                    _permissions.add('sales');
                  }
                }),
              ),
              for (final permission in permissions)
                CheckboxListTile(
                  dense: true,
                  value: _permissions.contains(permission),
                  title: Text(context.tr('vendor.permission.$permission')),
                  subtitle: permission == 'customers' && widget.customersTool
                      ? Text(context.tr('vendor.permission.customersHint'))
                      : null,
                  onChanged: (selected) => setState(() {
                    if (selected == true) {
                      _permissions.add(permission);
                    } else {
                      _permissions.remove(permission);
                    }
                  }),
                ),
              SizedBox(
                width: double.infinity,
                child: FFButton(
                  key: const Key('vendor-staff-save'),
                  label: context.tr('vendor.saveStaff'),
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// S3: before signing out or switching persona with sales still on this
/// device, say they stay here and offer Sync now. True to carry on.
Future<bool> confirmLeaveWithQueuedSales(
  BuildContext context, {
  bool switching = false,
}) async {
  final session = SalesSession.of(context);
  if (session == null) return true;
  await session.load();
  if (!context.mounted) return false;
  final n = session.all.length;
  if (n == 0) return true;
  final choice = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      key: const Key('vendor-sales-leave-dialog'),
      content: Text(
        fillIn(context.tr(pluralKey('vendor.sync.signOutWarn', n)), {'n': n}),
      ),
      actions: [
        FFButton(
          label: context.tr('common.cancel'),
          variant: FFButtonVariant.ghost,
          visualDensity: VisualDensity.standard,
          onPressed: () => Navigator.of(dialog).pop(),
        ),
        FFButton(
          key: const Key('vendor-sales-leave-sync'),
          label: context.tr('vendor.sync.now'),
          variant: FFButtonVariant.secondary,
          visualDensity: VisualDensity.standard,
          onPressed: () => Navigator.of(dialog).pop('sync'),
        ),
        FFButton(
          key: const Key('vendor-sales-leave-anyway'),
          label: context.tr(
            switching
                ? 'vendor.sync.switchAnyway'
                : 'vendor.sync.signOutAnyway',
          ),
          variant: FFButtonVariant.destructive,
          visualDensity: VisualDensity.standard,
          onPressed: () => Navigator.of(dialog).pop('leave'),
        ),
      ],
    ),
  );
  if (choice == 'sync') {
    await session.sync(manual: true);
    return false;
  }
  return choice == 'leave';
}
