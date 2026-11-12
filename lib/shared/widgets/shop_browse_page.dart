import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../file-export.dart';

import '../../app_scope.dart';
import '../api_client.dart';
import '../api_error_message.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../formatters.dart';
import '../discovery_loader.dart';
import '../i18n.dart';
import '../photo_footer_flag.dart';
import '../payment_labels.dart';
import '../product_categories.dart';
import '../promotion.dart';
import '../promotion_events.dart';
import '../root_back_navigation.dart';
import '../shop_checkout.dart';
import '../shop_home.dart';
import '../shop_near_you.dart';
import '../../screens/vendor/documents/document_view.dart'
    show buyerInvoiceRoute, documentIdPattern;
import 'shop_home/shop_flash_sale.dart';
import 'shop_home/shop_home_page.dart';
import 'shop_home/shop_near_you_ui.dart' show ShopDeliversBadge;
import 'shop_home/shop_product_card.dart'
    show
        ShopOutOfStockBadge,
        shopOnSale,
        shopDiscountPercent,
        shopSalePrice,
        shopSalePriceLabel,
        shopWasPrice;

num _shopNumber(dynamic value, [num fallback = 0]) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? fallback;
}

Future<void> openShopBrowsePage(BuildContext context) {
  return Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const ShopBrowsePage()));
}

class ShopProduct {
  const ShopProduct({
    required this.id,
    required this.vendorId,
    required this.name,
    this.vendorName,
    this.description,
    this.category,
    this.brand,
    this.priceTzs = 0,
    this.discountPriceTzs,
    this.stock = 0,
    this.images = const [],
    this.rating = 0,
    this.reviewCount = 0,
    this.soldCount = 0,
    this.deliveryAvailable = true,
    this.distanceKm,
    this.vendor = const {},
    this.reviews = const [],
    this.similarProducts = const [],
    this.promotion,
    this.variants = const [],
    this.deliversToViewerArea = false,
    this.sale,
    this.effectivePriceTzs,
  });

  /// What checkout charges now, per the server (`effectivePriceTzs`, on
  /// every row while SHOP_FLASH_SALES is on; null otherwise). Its presence
  /// is how the app knows the server checks `expectedPriceTzs`.
  final num? effectivePriceTzs;

  /// The server prices this row with flash sales on: checkout sends the
  /// price shown as `expectedPriceTzs`. Off: the order body is unchanged.
  bool get serverChecksPrice => effectivePriceTzs != null;

  /// Phase 2 S4: the live flash sale on this product (SHOP_FLASH_SALES),
  /// else null. While it is on, its price is the price.
  final ShopFlashSale? sale;

  /// The flash sale is on now by the server's clock.
  bool get flashSaleLive => sale?.live == true;

  /// The row came with a sale that has ended since (the screen has not
  /// been refreshed yet): "Sale ended", and no adding until it is.
  bool get flashSaleEnded => sale != null && !sale!.live;

  /// Phase 2 S3: the seller delivers to the area this phone worked out
  /// (sent on Shop home rows only, and only while near-you is on). Shows
  /// "Delivers to your area"; never blocks checkout.
  final bool deliversToViewerArea;

  /// The same product with [deliversToViewerArea] set (the details
  /// request does not carry it; the home row it was opened from does).
  ShopProduct withDeliversToViewerArea() => ShopProduct(
    id: id,
    vendorId: vendorId,
    name: name,
    vendorName: vendorName,
    description: description,
    category: category,
    brand: brand,
    priceTzs: priceTzs,
    discountPriceTzs: discountPriceTzs,
    stock: stock,
    images: images,
    rating: rating,
    reviewCount: reviewCount,
    soldCount: soldCount,
    deliveryAvailable: deliveryAvailable,
    distanceKm: distanceKm,
    vendor: vendor,
    reviews: reviews,
    similarProducts: similarProducts,
    promotion: promotion,
    variants: variants,
    deliversToViewerArea: true,
    sale: sale,
    effectivePriceTzs: effectivePriceTzs,
  );

  final String id;
  final String vendorId;
  final String name;

  /// The seller's business name on the product row (functions
  /// fix/shop-banners-qa2), for a store list's heading after a refresh.
  final String? vendorName;
  final String? description;
  final String? category;
  final String? brand;
  final num priceTzs;
  final num? discountPriceTzs;
  final int stock;
  final List<String> images;
  final num rating;
  final int reviewCount;
  final int soldCount;
  final bool deliveryAvailable;
  final num? distanceKm;
  final Map<String, dynamic> vendor;
  final List<Map<String, dynamic>> reviews;
  final List<ShopProduct> similarProducts;

  /// Set when this product is promoted for what the customer is looking at.
  final PromotionTag? promotion;

  /// Options the customer chooses between (size, flavour). `stock` is set only
  /// when the vendor counts that option separately.
  final List<ShopVariant> variants;

  factory ShopProduct.fromJson(Map<String, dynamic> json) => ShopProduct(
    id: json['id'] as String? ?? '',
    vendorId: json['vendorId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    vendorName: json['vendorName'] is String
        ? (json['vendorName'] as String).trim()
        : null,
    description: json['description'] as String?,
    category: json['category'] as String?,
    brand: json['brand'] as String?,
    priceTzs: _shopNumber(json['priceTzs']),
    discountPriceTzs: json['discountPriceTzs'] == null
        ? null
        : _shopNumber(json['discountPriceTzs']),
    stock: _shopNumber(json['stock']).toInt(),
    images: (json['images'] as List?)?.whereType<String>().toList() ?? [],
    rating: _shopNumber(json['rating']),
    reviewCount: _shopNumber(json['reviewCount']).toInt(),
    soldCount: _shopNumber(json['soldCount']).toInt(),
    deliveryAvailable: json['deliveryAvailable'] != false,
    distanceKm: json['distanceKm'] == null
        ? null
        : _shopNumber(json['distanceKm']),
    vendor: json['vendor'] is Map
        ? Map<String, dynamic>.from(json['vendor'] as Map)
        : const {},
    reviews: (json['reviews'] as List? ?? [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(),
    similarProducts: (json['similarProducts'] as List? ?? [])
        .whereType<Map>()
        .map((value) => ShopProduct.fromJson(Map<String, dynamic>.from(value)))
        .toList(),
    promotion: PromotionTag.fromJson(json['promotion']),
    variants: (json['variants'] as List? ?? [])
        .whereType<Map>()
        .map((value) => ShopVariant.fromJson(Map<String, dynamic>.from(value)))
        .where((value) => value.name.isNotEmpty)
        .toList(),
    deliversToViewerArea: json['deliversToViewerArea'] == true,
    sale: ShopFlashSale.fromJson(json['sale']),
    effectivePriceTzs: json['effectivePriceTzs'] is num
        ? json['effectivePriceTzs'] as num
        : null,
  );

  bool get inStock => stock > 0;

  /// The price without a flash sale: the seller's own discount, if any.
  num get regularEffectivePrice =>
      discountPriceTzs != null &&
          discountPriceTzs! > 0 &&
          discountPriceTzs! < priceTzs
      ? discountPriceTzs!
      : priceTzs;

  /// What one unit costs now: the flash sale's price while it is on.
  num get effectivePrice =>
      flashSaleLive ? sale!.salePriceTzs : regularEffectivePrice;
}

/// "4 in stock" / "Zipo 4", one placeholder line in both languages.
String _inStock(BuildContext context, ShopProduct product) =>
    context.tr('shop.inStockCount').replaceAll('{n}', '${product.stock}');

class ShopVariant {
  const ShopVariant({required this.name, this.stock});
  final String name;
  final int? stock;

  bool get soldOut => stock != null && stock! <= 0;

  factory ShopVariant.fromJson(Map<String, dynamic> json) => ShopVariant(
    name: json['name']?.toString().trim() ?? '',
    stock: json['stock'] is num ? (json['stock'] as num).toInt() : null,
  );
}

class ShopCart {
  final Map<String, int> _qty = {};
  final Map<String, ShopProduct> _products = {};

  /// The option chosen for a product. One option per product per order.
  final Map<String, String> _variant = {};

  String? variantOf(String productId) => _variant[productId];
  void setVariant(String productId, String name) => _variant[productId] = name;

  int get itemCount => _qty.values.fold(0, (a, b) => a + b);

  /// What is in the cart, in the order it was added: product, quantity and
  /// the option chosen (if any).
  List<(ShopProduct, int, String?)> get lines => [
    for (final e in _qty.entries)
      if (_products[e.key] != null)
        (_products[e.key]!, e.value, _variant[e.key]),
  ];
  bool get isEmpty => _qty.isEmpty;
  int qtyOf(String productId) => _qty[productId] ?? 0;

  /// Unit prices the server gave in a `409 price_changed` that the buyer
  /// confirmed, for lines whose product could not be fetched again
  /// (Phase 2 S4). A fresh product row replaces it.
  final Map<String, num> _confirmed = {};

  /// What one unit of [productId] costs as the cart shows it.
  num unitPriceOf(String productId) =>
      _confirmed[productId] ?? _products[productId]?.effectivePrice ?? 0;

  num get totalTzs => _qty.entries.fold(
    0,
    (sum, entry) => sum + unitPriceOf(entry.key) * entry.value,
  );

  /// Lines whose flash sale has ended since they were added (the price
  /// shown is the regular one now).
  List<ShopProduct> get saleEndedProducts => [
    for (final e in _qty.keys)
      if (_products[e] case final p?
          when p.flashSaleEnded && !_confirmed.containsKey(e))
        p,
  ];

  /// Puts a fresh copy of a product in the cart (after prices changed); the
  /// quantity and option stay. With [keepConfirmed] (a background refresh of
  /// the home or the list) a price the buyer confirmed after a 409 stays
  /// the line's price, so "Continue with {total}" sends what it showed.
  void refreshProduct(ShopProduct product, {bool keepConfirmed = false}) {
    if (!_qty.containsKey(product.id)) return;
    _products[product.id] = product;
    if (!keepConfirmed) _confirmed.remove(product.id);
  }

  /// The server's current unit price for a line, kept until the product is
  /// fetched again.
  void confirmPrice(String productId, num priceTzs) {
    if (_qty.containsKey(productId)) _confirmed[productId] = priceTzs;
  }

  bool add(ShopProduct product) {
    final current = _qty[product.id] ?? 0;
    if (current >= product.stock) return false;
    // An option the vendor counts separately is a second limit.
    final chosen = _variant[product.id];
    final variantStock = chosen == null
        ? null
        : product.variants.where((v) => v.name == chosen).firstOrNull?.stock;
    if (variantStock != null && current >= variantStock) return false;
    _products[product.id] = product;
    _qty[product.id] = current + 1;
    return true;
  }

  void removeOne(String productId) {
    final current = _qty[productId] ?? 0;
    if (current <= 1) {
      _qty.remove(productId);
      _products.remove(productId);
      _variant.remove(productId);
      _confirmed.remove(productId);
    } else {
      _qty[productId] = current - 1;
    }
  }

  void remove(String productId) {
    _qty.remove(productId);
    _products.remove(productId);
    _variant.remove(productId);
    _confirmed.remove(productId);
  }

  void clear() {
    _qty.clear();
    _products.clear();
    _variant.clear();
    _confirmed.clear();
  }

  /// The order lines. While the server prices with flash sales (its rows
  /// carry `effectivePriceTzs`), each line also says the unit price the app
  /// showed (`expectedPriceTzs`), so a price that moved is caught as
  /// `409 price_changed` instead of being charged. Otherwise the body is
  /// exactly as before.
  List<Map<String, dynamic>> toOrderItems() => _qty.entries
      .map(
        (entry) => {
          'productId': entry.key,
          'qty': entry.value,
          if (_variant[entry.key] != null) 'variant': _variant[entry.key],
          if (_products[entry.key]?.serverChecksPrice == true ||
              _confirmed.containsKey(entry.key))
            'expectedPriceTzs': unitPriceOf(entry.key).round(),
        },
      )
      .toList();
}

class ShopBrowsePage extends StatelessWidget {
  const ShopBrowsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('member.shopTitle'))),
      body: const ShopBrowseBody(),
    );
  }
}

class ShopBrowseBody extends StatefulWidget {
  const ShopBrowseBody({
    super.key,
    this.mode = ShopHomeMode.member,
    this.routePath,
    this.routeQuery = const {},
    this.showHero = false,
  });

  /// The role this shop is opened as. Only used by the Shop home (V2 flag):
  /// it picks the suggestions, never which products can be browsed.
  final ShopHomeMode mode;

  /// The route this shop is the page for (member and owner shop). With the
  /// V2 flag on, the product list, its filters and an open product are kept
  /// in this route's query (`?view=results&category=…&sort=…&product=…`), so
  /// browser Back and a refresh work. Null: no URL.
  final String? routePath;

  /// Extra query the host page needs to show the shop (the trainer home's
  /// `open=shop`, which selects its Shop tab). Kept in every URL the shop
  /// writes and ignored when reading.
  final Map<String, String> routeQuery;

  /// Show the Shop home's photo band (PHOTO_HERO_UI). The member Shop tab
  /// only; never the trainer or owner shop or the pushed ShopBrowsePage.
  final bool showHero;

  @override
  State<ShopBrowseBody> createState() => _ShopBrowseBodyState();
}

class _ShopBrowseBodyState extends State<ShopBrowseBody> {
  List<ShopProduct> _products = [];

  /// Featured and promoted products from the server's ranked discovery, with
  /// their labels. Empty when the server has none or cannot be reached.
  List<ShopProduct> _featured = [];
  Map<String, PromotionTag> _promoTags = {};
  String? _placement;
  List<Map<String, dynamic>> _orders = [];
  final ShopCart _cart = ShopCart();
  final Set<String> _saved = {};
  bool _loading = true;
  bool _ordering = false;

  /// The checkout in progress, kept while the cart is unchanged so a retry is
  /// recognised by the server and never makes a second order.
  CheckoutAttempt? _attempt;
  String _search = '';
  String? _category;
  String _sort = 'newest';
  bool _deliveryOnly = false;
  bool _promotionsOnly = false;

  /// Phase 2 S4: only products in a live flash sale (the rail's View all,
  /// `flashSale=true`).
  bool _flashSaleOnly = false;
  String _brand = '';
  String _vendorId = '';

  /// The store's name when the list was opened from a banner's "Visit
  /// store" (shown as the list's heading); empty otherwise.
  String _vendorName = '';

  /// The carousel slide shown last (Back from a banner's target).
  int _bannerIndex = 0;

  /// The store heading for a seller's product list: the banner's name, or
  /// (after a refresh) the name on that seller's products.
  String get _storeName {
    if (_vendorName.isNotEmpty) return _vendorName;
    for (final p in _products) {
      if (p.vendorId != _vendorId) continue;
      final name = (p.vendorName ?? '').isNotEmpty
          ? p.vendorName!
          : p.vendor['businessName']?.toString().trim() ?? '';
      if (name.isNotEmpty) return name;
    }
    return '';
  }

  num? _minPrice;
  num? _maxPrice;
  num? _minRating;
  num? _maxDistanceKm;

  /// Phase 2 S3 (spec Q-10, §7.3): GET /shop/areas returned areas, so the
  /// vendor-typed distance is not used: no "Maximum distance" filter, any
  /// `maxDistanceKm` is ignored, and no "{n} km" text shows.
  bool _areasExist = false;
  int _section = 0;
  Timer? _trackingTimer;
  bool _trackingRequest = false;

  /// Why the last catalogue load failed (offline or a server error).
  Object? _loadError;

  // Shop home V2: the landing is shown until the customer searches, picks a
  // category or taps "View all"; the backend can switch it off (404/403).
  bool _homeUnavailable = false;
  bool _results = false;
  final _searchController = TextEditingController();
  final _homeKey = GlobalKey<ShopHomeViewState>();

  bool get _showHome => shopHomeV2Enabled && !_homeUnavailable && !_results;

  /// PHOTO_FOOTER_UI (member shop home only, spec §33.6): whether the home
  /// shows rails or the All products grid, and the band heading's focus
  /// node for the footer's Back to top.
  bool _homeHasContent = false;
  final FocusNode _heroFocus = FocusNode(debugLabel: 'shop-hero-heading');

  // With the home on, today's product list (and discovery) is fetched only
  // when something needs it: the list, the fallback, a reorder, the grid.
  bool _catalogueLoaded = false;
  bool _catalogueWanted = false;
  bool get _needsCatalogue =>
      !shopHomeV2Enabled || _homeUnavailable || _catalogueWanted;

  /// The last home loaded, so switching to My orders and back (or going
  /// offline) keeps what was on screen.
  ShopHomeData? _homeCache;
  bool _homeOffline = false;

  // URL state (see [ShopBrowseBody.routePath]).
  bool get _syncUrl => shopHomeV2Enabled && widget.routePath != null;
  String? _lastLocation;
  String? _openProductId;
  BuildContext? _sheetContext;
  bool _closingFromUrl = false;

  /// The product the address switched to while a sheet was open.
  String? _replaceWith;
  ScaffoldMessengerState? _messenger;

  /// The selected category chip, scrolled into view when the list opens.
  final _selectedChipKey = GlobalKey(debugLabel: 'shop-chip-selected');

  void _revealSelectedChip() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _selectedChipKey.currentContext;
      if (chip == null || !chip.mounted) return;
      Scrollable.ensureVisible(
        chip,
        alignment: 0.5,
        duration: MediaQuery.disableAnimationsOf(chip)
            ? Duration.zero
            : FFTokens.motionMedium,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _lifecycle;
    addRootBackHandler(_onRootBack);
    ShopNearYouStore.changes.addListener(_nearChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadAreas();
      _probeNearYou();
    });
    _trackingTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshTracking(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _heroFocus.dispose();
    removeRootBackHandler(_onRootBack);
    ShopNearYouStore.changes.removeListener(_nearChanged);
    // "Added to cart" belongs to the shop: it does not follow to other tabs.
    // After this frame, and only if the app (and its messenger) is still
    // there: on a full teardown the messenger goes too.
    final messenger = _messenger;
    if (shopHomeV2Enabled && messenger != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (messenger.mounted) messenger.removeCurrentSnackBar();
      });
    }
    _trackingTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
    // QA #1: coming back to the Shop tab (a tab kept alive in an
    // IndexedStack) fetches again, so a sale that started meanwhile shows.
    final visible = Visibility.of(context);
    if (visible && _shown == false) _refreshOnReturn();
    _shown = visible;
    _syncFromUrl();
  }

  /// Whether the shop was visible last time (null before the first look).
  bool? _shown;

  /// When the shop last fetched what it shows (device time).
  DateTime? _lastFetch;

  /// Returning within this long of the last fetch keeps what is shown.
  static const _refetchAfter = Duration(seconds: 30);

  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: () {
      if (mounted && (_shown ?? true)) _refreshOnReturn();
    },
  );

  /// Fetches the home (or the list) again when the shop is looked at again,
  /// unless it was fetched in the last 30 s. What is on screen stays while
  /// it loads (the home keeps its last answer; the list its rows).
  void _refreshOnReturn() {
    final last = _lastFetch;
    if (last == null ||
        ShopClock.deviceNow().difference(last) < _refetchAfter) {
      return;
    }
    _lastFetch = ShopClock.deviceNow();
    if (_catalogueLoaded) unawaited(_load());
    if (_section == 0 && _showHome) {
      unawaited(_homeKey.currentState?.reload());
    } else if (!_catalogueLoaded) {
      unawaited(_load());
    }
  }

  /// Android Back (and the shells' root PopScope): from the product list,
  /// back to the Shop home instead of out of the app. Only for the shop the
  /// user is looking at (the trainer shop sits in a hidden tab otherwise).
  bool _onRootBack() {
    if (!mounted || !shopHomeV2Enabled || _homeUnavailable) return false;
    if (_section != 0 || !_results) return false;
    if (!Visibility.of(context)) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    _backToHome();
    return true;
  }

  Map<String, String> _stateQuery() => {
    if (_results) 'view': 'results',
    if (_results && _category != null) 'category': _category!,
    if (_results && _search.trim().isNotEmpty) 'q': _search.trim(),
    if (_results && _sort != 'newest') 'sort': _sort,
    if (_results && _promotionsOnly) 'promotions': 'true',
    if (_results && _flashSaleOnly) 'flashSale': 'true',
    if (_results && _deliveryOnly) 'delivery': 'true',
    if (_results && _vendorId.isNotEmpty) 'vendorId': _vendorId,
    'product': ?_openProductId,
  };

  /// Writes the current view into the URL (a new history entry, so browser
  /// Back returns to the previous view).
  void _pushUrl() {
    if (!_syncUrl || !mounted) return;
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final state = _stateQuery();
    final query = state.isEmpty && !_results
        ? <String, String>{}
        : {...widget.routeQuery, ...state};
    final location = Uri(
      path: widget.routePath,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    if (location == _lastLocation) return;
    _lastLocation = location;
    router.go(location);
  }

  /// Reads the view from the URL: a refresh, a deep link or browser Back.
  void _syncFromUrl() {
    if (!_syncUrl) return;
    Uri uri;
    try {
      uri = GoRouterState.of(context).uri;
    } catch (_) {
      return;
    }
    if (uri.path != widget.routePath) return;
    final location = uri.toString();
    if (location == _lastLocation) return;
    _lastLocation = location;
    final q = uri.queryParameters;
    if (q['view'] == 'results') {
      _applyResults(
        search: q['q'] ?? '',
        query: {
          'category': ?q['category'],
          'sort': ?q['sort'],
          'promotions': ?q['promotions'],
          'flashSale': ?q['flashSale'],
          'delivery': ?q['delivery'],
          'vendorId': ?q['vendorId'],
        },
      );
    } else if (_results) {
      _results = false;
      _search = '';
      _searchController.clear();
      _category = null;
      if (mounted) setState(() {});
    }
    final product = q['product'];
    if (product != null && product != _openProductId) {
      final open = _sheetContext;
      if (open != null && open.mounted) {
        // QA #13: another product while a sheet is open: close this one
        // and open that one in its place (never two sheets stacked).
        _replaceWith = product;
        _closingFromUrl = true;
        Navigator.of(open).maybePop();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openProductById(product);
        });
      }
    } else if (product == null && _sheetContext != null) {
      _closingFromUrl = true;
      final sheet = _sheetContext!;
      if (sheet.mounted) Navigator.of(sheet).maybePop();
    }
  }

  /// A product from the URL: from what is loaded, else from the server.
  Future<void> _openProductById(String id) async {
    final known = [
      ..._products,
      ..._featured,
    ].where((p) => p.id == id).firstOrNull;
    if (known != null) return _openProduct(known);
    final messenger = FFSnack.of(context);
    final gone = context.tr('shop.home.productGone');
    try {
      final json = await AppScope.of(
        context,
      ).api.shopProduct(id, areaId: _areaToSend);
      if (!mounted) return;
      await _openProduct(ShopProduct.fromJson(json));
    } catch (_) {
      if (!mounted) return;
      messenger.info(gone);
      _openProductId = null;
      _pushUrl();
    }
  }

  /// Loads today's product list if it is not loaded yet.
  Future<void> _ensureCatalogue() async {
    _catalogueWanted = true;
    if (!_catalogueLoaded) await _load();
  }

  void _shopEvent(String type, {String? productId}) {
    if (!shopHomeV2Enabled) return;
    ShopEvents.send(
      AppScope.of(context).api,
      type,
      mode: widget.mode,
      productId: productId,
    );
  }

  /// Leaves the Shop home for the product list, with only these filters.
  void _openResults({
    String? search,
    String? category,
    Map<String, String> query = const {},
  }) {
    _applyResults(search: search, category: category, query: query);
    _pushUrl();
    _revealSelectedChip();
  }

  void _applyResults({
    String? search,
    String? category,
    Map<String, String> query = const {},
  }) {
    if (!_catalogueLoaded) unawaited(_ensureCatalogue());
    setState(() {
      _results = true;
      _search = search ?? query['search'] ?? '';
      _searchController.text = _search;
      _category = category ?? _nonEmpty(query['category']);
      _brand = query['brand'] ?? '';
      _vendorId = query['vendorId'] ?? '';
      if (_vendorId.isEmpty) _vendorName = '';
      _minPrice = num.tryParse(query['minPrice'] ?? '');
      _maxPrice = num.tryParse(query['maxPrice'] ?? '');
      _minRating = num.tryParse(query['minRating'] ?? '');
      _maxDistanceKm = _areasExist
          ? null
          : num.tryParse(query['maxDistanceKm'] ?? '');
      _deliveryOnly = query['delivery'] == 'true';
      _promotionsOnly = query['promotions'] == 'true';
      _flashSaleOnly = query['flashSale'] == 'true';
      const sorts = {
        'newest',
        'popularity',
        'price_asc',
        'price_desc',
        'rating',
      };
      _sort = sorts.contains(query['sort']) ? query['sort']! : 'newest';
    });
  }

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;

  /// A hero banner's button (Phase 2 S1): its product's details, the
  /// seller's products, a category, or the product list.
  void _openBanner(ShopBanner banner) {
    final target = banner.target;
    switch (target.type) {
      case 'product':
        unawaited(_openProductById(target.value));
      case 'vendor_store':
        _vendorName = banner.vendorName?.trim() ?? '';
        _openResults(query: {'vendorId': target.value});
      case 'category':
        _openResults(category: target.value);
      default:
        if (target.query['vendorId'] == null) _vendorName = '';
        _openResults(query: target.query);
    }
  }

  void _backToHome() {
    setState(() {
      _results = false;
      _vendorId = '';
      _vendorName = '';
      _search = '';
      _searchController.clear();
      _category = null;
    });
    _pushUrl();
  }

  Future<void> _refreshTracking() async {
    if (!mounted ||
        _loading ||
        _ordering ||
        _trackingRequest ||
        _section != 1 ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      return;
    }
    _trackingRequest = true;
    try {
      final rows = await AppScope.of(context).api.myShopOrders();
      if (!mounted) return;
      final latest = rows.whereType<Map<String, dynamic>>().toList();
      final previous = {
        for (final order in _orders) order['id']: order['status'],
      };
      final changed = latest.any(
        (order) =>
            previous.containsKey(order['id']) &&
            previous[order['id']] != order['status'],
      );
      setState(() => _orders = latest);
      if (changed) {
        FFSnack.success(context, context.tr('shop.trackingUpdated'));
      }
    } on ApiException {
      // Preserve the last successful timeline and retry on the next interval.
    } finally {
      _trackingRequest = false;
    }
  }

  /// The near-you area to send with product requests (QA #4), or null.
  String? get _areaToSend => ShopNearYouStore.areaToSend(
    AppScope.of(context).auth.user?['id']?.toString(),
  );

  /// The area changed or went (S3): the product list asks again, so
  /// "Delivers to your area" follows it.
  void _nearChanged() {
    if (!mounted) return;
    if (_catalogueLoaded) unawaited(_load());
    // An open product sheet asks again too, for its badge (QA2 #1).
    final open = _sheetProduct;
    if (open != null) unawaited(_refetchOpenProduct(open));
  }

  /// The product shown in the open details sheet (null when closed).
  ValueNotifier<ShopProduct>? _sheetProduct;

  Future<void> _refetchOpenProduct(ValueNotifier<ShopProduct> open) async {
    final id = open.value.id;
    try {
      final fresh = ShopProduct.fromJson(
        await AppScope.of(context).api.shopProduct(id, areaId: _areaToSend),
      );
      if (!mounted || _sheetProduct != open || open.value.id != id) return;
      open.value =
          open.value.deliversToViewerArea &&
              !fresh.deliversToViewerArea &&
              _areaToSend != null
          ? fresh.withDeliversToViewerArea()
          : fresh;
    } catch (_) {
      // Keep what is shown.
    }
  }

  /// Cold Results or a `?product=` link (no Shop home on screen): learn
  /// once whether near-you is available, so the area can be sent (QA2 #1).
  /// The answer bumps the store's `changes`, which refetches.
  void _probeNearYou() {
    if (!mounted || _showHome) return;
    final scope = AppScope.of(context);
    unawaited(
      ShopNearYouStore.probe(
        scope.api,
        scope.auth.user?['id']?.toString(),
        mode: widget.mode.wire,
      ),
    );
  }

  /// Whether the shop has areas (S3). A backend without them (404) keeps
  /// the distance filter.
  Future<void> _loadAreas() async {
    if (!mounted) return;
    final areas = await ShopAreas.load(AppScope.of(context).api);
    if (!mounted || areas.isEmpty == !_areasExist) return;
    setState(() {
      _areasExist = areas.isNotEmpty;
      if (_areasExist) _maxDistanceKm = null;
    });
  }

  /// Replaces the cart's copies of [fresh] products, so the cart bar and
  /// the cart show the price the buyer will pay now, not the price when the
  /// line was added (QA #2). Quantity and option stay.
  void _refreshCart(Iterable<ShopProduct> fresh) {
    if (_cart.isEmpty) return;
    for (final p in fresh) {
      if (_cart.qtyOf(p.id) > 0) _cart.refreshProduct(p, keepConfirmed: true);
    }
  }

  Future<void> _load() async {
    _lastFetch = ShopClock.deviceNow();
    setState(() => _loading = true);
    final catalogue = _needsCatalogue;
    try {
      final results = await Future.wait([
        if (catalogue)
          AppScope.of(context).api.listShopProducts(areaId: _areaToSend),
        AppScope.of(context).api.myShopOrders(),
      ]);
      if (!mounted) return;
      setState(() {
        if (catalogue) {
          _products = results.first
              .whereType<Map<String, dynamic>>()
              .map(ShopProduct.fromJson)
              .toList();
          _catalogueLoaded = true;
          _refreshCart(_products);
        }
        _orders = results.last.whereType<Map<String, dynamic>>().toList();
        _loading = false;
        _loadError = null;
      });
      if (catalogue) await _loadPromotions();
    } catch (e) {
      // Offline or a server error: the list says so instead of "no products".
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e;
        });
      }
    }
  }

  /// Which products are Featured or promoted. Only labels and the Featured
  /// section come from here; the list keeps its own filters and sort. Any
  /// failure just leaves the catalogue as it was.
  Future<void> _loadPromotions() async {
    if (!kServerDiscovery) return;
    try {
      final result = DiscoverResult.fromJson<ShopProduct>(
        await AppScope.of(context).api.discover(
          'products',
          DiscoverQuery(limit: 50, session: discoverSessionId()),
        ),
        ShopProduct.fromJson,
      );
      if (!mounted) return;
      setState(() {
        _featured = result.featured;
        _placement = result.placement;
        _promoTags = {
          for (final p in [...result.featured, ...result.items])
            if (p.promotion != null) p.id: p.promotion!,
        };
      });
    } catch (_) {
      // Discovery is an improvement, never a requirement.
    }
  }

  /// Whether a product passes the search and every filter the customer set.
  /// The Featured section uses the same test, so a featured product that does
  /// not match what they asked for is not shown.
  bool _passes(ShopProduct product) {
    final query = _search.trim().toLowerCase();
    {
      final searchMatch =
          query.isEmpty ||
          [
            product.name,
            product.category,
            product.brand,
            product.description,
          ].any((value) => (value ?? '').toLowerCase().contains(query));
      return searchMatch &&
          (_category == null || product.category == _category) &&
          (!_deliveryOnly || product.deliveryAvailable) &&
          // On sale exactly as the server counts it: 0 < sale < price.
          (!_promotionsOnly || product.effectivePrice < product.priceTzs) &&
          (!_flashSaleOnly || product.flashSaleLive) &&
          (_brand.isEmpty ||
              (product.brand ?? '').toLowerCase().contains(
                _brand.toLowerCase(),
              )) &&
          (_vendorId.isEmpty || product.vendorId == _vendorId) &&
          (_minPrice == null || product.effectivePrice >= _minPrice!) &&
          (_maxPrice == null || product.effectivePrice <= _maxPrice!) &&
          (_minRating == null || product.rating >= _minRating!) &&
          (_maxDistanceKm == null ||
              _areasExist ||
              (product.distanceKm != null &&
                  product.distanceKm! <= _maxDistanceKm!));
    }
  }

  /// Featured products that match what the customer asked for. An explicit
  /// sort switches promotion off, as it does on the server.
  List<ShopProduct> get _visibleFeatured => _sort == 'newest'
      ? _featured.where(_passes).toList()
      : const <ShopProduct>[];

  List<ShopProduct> get _visible {
    final values = _products.where(_passes).toList();
    if (_sort == 'price_asc') {
      values.sort((a, b) => a.effectivePrice.compareTo(b.effectivePrice));
    } else if (_sort == 'price_desc') {
      values.sort((a, b) => b.effectivePrice.compareTo(a.effectivePrice));
    } else if (_sort == 'rating') {
      values.sort((a, b) => b.rating.compareTo(a.rating));
    } else if (_sort == 'popularity') {
      values.sort((a, b) => b.soldCount.compareTo(a.soldCount));
    }
    return values;
  }

  /// The delivery and payment choices from the last checkout sheet, so
  /// "Back to cart" from the price-changed sheet keeps what was entered.
  Map<String, String>? _lastCheckout;

  Future<void> _checkout() async {
    if (_cart.isEmpty || _ordering) return;
    final checkout = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => Semantics(
        namesRoute: true,
        explicitChildNodes: true,
        label: sheet.tr('shop.checkout'),
        child: _CheckoutSheet(
          cart: shopHomeV2Enabled ? _cart : null,
          initial: _lastCheckout,
        ),
      ),
    );
    if (checkout == null || !mounted || _ordering) return;
    _lastCheckout = checkout;
    final cartTotal = _cart.totalTzs;
    setState(() => _ordering = true);
    final messenger = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    try {
      final order = await _placeOrder(checkout);
      if (!mounted) return;
      await _orderPlaced(order, cartTotal, messenger, locale);
    } catch (e) {
      if (!mounted) return;
      // A clear refusal means nothing was ordered, so the next attempt is a new one.
      // When the outcome is unknown the key is kept: the retry cannot duplicate.
      if (!orderOutcomeUnknown(e)) _attempt = null;
      // Phase 2 S4: a price moved (a sale ended or started): show what
      // changed and let the buyer confirm the new total.
      final change = ShopPriceChange.fromError(e);
      if (change != null) {
        await _pricesChanged(change, checkout, messenger, locale);
        return;
      }
      setState(() => _ordering = false);
      messenger.error(shopCheckoutErrorMessage(locale, e));
      // Stock or prices moved: show the customer the current catalogue.
      if (shopCheckoutErrorKey(e) != null) await _load();
    }
  }

  /// Sends the cart as an order. The same key is reused while the purchase
  /// is unchanged: a timeout followed by another tap returns the first
  /// order, not a second one.
  Future<Map<String, dynamic>> _placeOrder(Map<String, String> checkout) {
    final items = _cart.toOrderItems();
    final attempt = _attempt = CheckoutAttempt.forPurchase(
      _attempt,
      checkoutSignature(
        items: items,
        deliveryMethod: checkout['deliveryMethod']!,
        pickupGymId: checkout['pickupGymId'],
        deliveryAddress: checkout['deliveryAddress'],
        paymentMethod: checkout['paymentMethod']!,
      ),
    );
    return AppScope.of(context).api.createShopOrder(
      items,
      deliveryMethod: checkout['deliveryMethod']!,
      pickupGymId: checkout['pickupGymId'],
      deliveryAddress: checkout['deliveryAddress'],
      paymentMethod: checkout['paymentMethod']!,
      idempotencyKey: attempt.key,
    );
  }

  Future<void> _orderPlaced(
    Map<String, dynamic> order,
    num cartTotal,
    FFSnackMessenger messenger,
    FFLocale locale,
  ) async {
    // The order exists on the server: only now is the cart given up.
    _attempt = null;
    _lastCheckout = null;
    setState(() {
      _cart.clear();
      _ordering = false;
      _section = 1;
    });
    final paid = shopOrderPayment(order) == ShopOrderPayment.paid;
    final serverTotal = order['totalTzs'];
    // The total the server priced is the one that counts; say so if it differs.
    final differs = serverTotal is num && serverTotal != cartTotal;
    if (paid) {
      messenger.success(locale.t('shop.paymentConfirmed'));
    } else if (differs) {
      messenger.info(
        '${locale.t('shop.orderPending')} '
        '${locale.t('shop.orderTotalIs')}: ${formatCurrency(serverTotal)}.',
      );
    } else {
      messenger.info(locale.t('shop.orderPending'));
    }
    await _load();
  }

  /// The cart after a `409 price_changed`: each changed product fetched
  /// again (its sale state, for the cart lines) and its line priced at the
  /// server's current price, which is what the next attempt says it
  /// expects. The Shop home is asked again too, so its rails match.
  Future<void> _applyPriceChange(ShopPriceChange change) async {
    final api = AppScope.of(context).api;
    final area = _areaToSend;
    await Future.wait([
      for (final line in change.lines)
        api
            .shopProduct(line.productId, areaId: area)
            .then((json) {
              _cart.refreshProduct(ShopProduct.fromJson(json));
            })
            .catchError((Object _) {}),
    ]);
    for (final line in change.lines) {
      _cart.confirmPrice(line.productId, line.currentPriceTzs);
    }
    if (!mounted) return;
    setState(() {});
    if (_section == 0 && _showHome) {
      unawaited(_homeKey.currentState?.reload());
    }
  }

  /// "Prices have changed" (spec §8.2): "Continue with {new total}" sends
  /// the order again with the new prices; if they move again the same
  /// sheet updates; "Back to cart" (or Back) returns to the cart.
  Future<void> _pricesChanged(
    ShopPriceChange first,
    Map<String, String> checkout,
    FFSnackMessenger messenger,
    FFLocale locale,
  ) async {
    await _applyPriceChange(first);
    if (!mounted) return;
    // The sheet shows its own progress; the cart bar is idle behind it
    // (the sheet is modal, so it can't be tapped meanwhile).
    setState(() => _ordering = false);
    final change = ValueNotifier(first);
    Map<String, dynamic>? placed;
    Object? failure;
    var total = _cart.totalTzs;
    await showShopPriceChangedSheet(
      context,
      change: change,
      product: (id) => _cart.lines.where((l) => l.$1.id == id).firstOrNull?.$1,
      onContinue: () async {
        total = _cart.totalTzs;
        try {
          placed = await _placeOrder(checkout);
          return ShopPriceRetry.placed;
        } catch (e) {
          if (!orderOutcomeUnknown(e)) _attempt = null;
          final again = ShopPriceChange.fromError(e);
          if (again != null && mounted) {
            await _applyPriceChange(again);
            change.value = again;
            return ShopPriceRetry.changedAgain;
          }
          // No answer: the key is kept, so trying again cannot duplicate.
          if (isNetworkError(e)) return ShopPriceRetry.offline;
          failure = e;
          return ShopPriceRetry.failed;
        }
      },
    );
    change.dispose();
    if (!mounted) return;
    if (placed case final order?) {
      await _orderPlaced(order, total, messenger, locale);
      return;
    }
    setState(() => _ordering = false);
    if (failure case final e?) {
      messenger.error(shopCheckoutErrorMessage(locale, e));
      if (shopCheckoutErrorKey(e) != null) await _load();
      return;
    }
    // Back to cart: the cart (with its new prices) opens again.
    if (shopHomeV2Enabled) unawaited(_checkout());
  }

  /// Add one unit; a product with options asks which one first. Returns
  /// whether a unit was added.
  Future<bool> _addToCart(ShopProduct product, {bool track = true}) async {
    if (product.variants.isNotEmpty && _cart.variantOf(product.id) == null) {
      final chosen = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text(dialogContext.tr('shop.chooseOption')),
          children: [
            for (final option in product.variants)
              SimpleDialogOption(
                key: Key('shop-variant-${product.id}-${option.name}'),
                onPressed: option.soldOut
                    ? null
                    : () => Navigator.pop(dialogContext, option.name),
                child: Text(
                  option.soldOut
                      ? '${option.name} · ${dialogContext.tr('shop.optionOutOfStock')}'
                      : option.name,
                ),
              ),
          ],
        ),
      );
      if (chosen == null || !mounted) return false;
      _cart.setVariant(product.id, chosen);
    }
    final added = _cart.add(product);
    if (mounted) setState(() {});
    if (added && track) _shopEvent('add_to_cart', productId: product.id);
    return added;
  }

  /// Re-read an order that is waiting for payment confirmation. Never places
  /// anything: the payment is confirmed by FitFlex, this only looks again.
  Future<void> _checkPayment(Map<String, dynamic> order) async {
    final messenger = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    try {
      await _load();
      final fresh = _orders.where((o) => o['id'] == order['id']).firstOrNull;
      if (fresh == null) return;
      messenger.info(
        locale.t(
          shopOrderPayment(fresh) == ShopOrderPayment.awaitingConfirmation
              ? 'shop.stillAwaiting'
              : shopOrderPayment(fresh) == ShopOrderPayment.paid
              ? 'shop.paymentConfirmed'
              : shopOrderPaymentKey(fresh) ?? 'shop.stillAwaiting',
        ),
      );
    } catch (e) {
      messenger.error(errorMessage(locale, e));
    }
  }

  /// Cancel an order that is not on its way yet; a paid one is refunded.
  Future<void> _cancelOrder(Map<String, dynamic> order) async {
    final paid = order['paymentStatus'] == 'paid';
    final confirmed = await showFFConfirmDialog(
      context,
      title: context.tr('shop.cancelOrder'),
      message: context.tr(
        paid ? 'shop.cancelConfirmPaid' : 'shop.cancelConfirm',
      ),
      cancelLabel: context.tr('sessions.keep'),
      confirmLabel: context.tr('shop.cancelOrder'),
      confirmKey: const Key('order-cancel-confirm'),
    );
    if (confirmed != true || !mounted) return;
    final messenger = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final done = context.tr(paid ? 'shop.cancelledRefund' : 'shop.cancelled');
    try {
      await AppScope.of(context).api.cancelMyShopOrder(order['id'].toString());
      await _load();
      messenger.success(done);
    } catch (e) {
      messenger.error(errorMessage(locale, e));
    }
  }

  Future<void> _openProduct(ShopProduct product) async {
    if (shopHomeV2Enabled) {
      unawaited(
        RecentlyViewedProducts.add(
          AppScope.of(context).auth.user?['id']?.toString(),
          product.id,
        ),
      );
    }
    var detailedProduct = product;
    final sentArea = _areaToSend;
    try {
      detailedProduct = ShopProduct.fromJson(
        await AppScope.of(
          context,
        ).api.shopProduct(product.id, areaId: sentArea),
      );
    } on ApiException {
      // The cached catalogue record still supports cart actions offline.
    }
    // The details request has no area: keep the home row's badge (S3).
    if (product.deliversToViewerArea && !detailedProduct.deliversToViewerArea) {
      detailedProduct = detailedProduct.withDeliversToViewerArea();
    }
    if (!mounted) return;
    PromotionEvents.instance.recordForTouched(
      'detail_view',
      'product',
      product.id,
    );
    _openProductId = product.id;
    _pushUrl();
    final shown = _sheetProduct = ValueNotifier(detailedProduct);
    // The area became sendable while it loaded (a link opened before the
    // Shop home answered): ask again for the badge (QA2 #1).
    if (_areaToSend != sentArea) unawaited(_refetchOpenProduct(shown));
    final buyNow = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      // The handle is drawn by the sheet and kept out of semantics: the
      // framework's handle is read as an untranslated "Dismiss" (QA2 #3).
      // Swiping down and the sheet's own Close button still close it.
      showDragHandle: false,
      // Read as "Close", not the framework's "Scrim" (QA2 #3).
      barrierLabel: context.tr('common.close'),
      builder: (sheet) {
        _sheetContext = sheet;
        // Follows a refetch (the area became sendable after it opened).
        return ValueListenableBuilder<ShopProduct>(
          valueListenable: shown,
          // QA #15: the sheet's route is named by the product.
          builder: (_, product, _) => Semantics(
            namesRoute: true,
            explicitChildNodes: true,
            label: product.name,
            child: _ProductDetailsSheet(
              product: product,
              showDistance: !_areasExist,
              onAdd: () => _addToCart(product),
            ),
          ),
        );
      },
    );
    if (_sheetProduct == shown) _sheetProduct = null;
    shown.dispose();
    _sheetContext = null;
    _openProductId = null;
    if (!mounted) return;
    // Closed by the user (not by browser Back): drop it from the URL.
    if (!_closingFromUrl) _pushUrl();
    _closingFromUrl = false;
    setState(() {});
    final next = _replaceWith;
    _replaceWith = null;
    if (next != null) {
      // The address now names another product: open it in this one's place.
      await _openProductById(next);
      return;
    }
    if (buyNow == true) await _checkout();
  }

  Future<void> _openFilters() async {
    final values = await showModalBottomSheet<_MarketplaceFilterValues>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MarketplaceFiltersSheet(
        showDistance: !_areasExist,
        initial: _MarketplaceFilterValues(
          brand: _brand,
          vendorId: _vendorId,
          minPrice: _minPrice,
          maxPrice: _maxPrice,
          minRating: _minRating,
          maxDistanceKm: _maxDistanceKm,
        ),
      ),
    );
    if (values == null || !mounted) return;
    _shopEvent('filter_applied');
    setState(() {
      _brand = values.brand;
      if (values.vendorId != _vendorId) _vendorName = '';
      _vendorId = values.vendorId;
      _minPrice = values.minPrice;
      _maxPrice = values.maxPrice;
      _minRating = values.minRating;
      _maxDistanceKm = values.maxDistanceKm;
    });
  }

  Future<void> _reorder(Map<String, dynamic> order) async {
    // The cart is filled from today's product list.
    if (!_catalogueLoaded) await _ensureCatalogue();
    if (!mounted) return;
    final result = await AppScope.of(
      context,
    ).api.reorderMarketplaceOrder(order['id'].toString());
    for (final item in (result['items'] as List? ?? []).whereType<Map>()) {
      final product = _products
          .where((value) => value.id == item['productId'])
          .firstOrNull;
      if (product == null) continue;
      // Keep the option bought last time: products whose options keep their
      // own stock cannot be ordered without one (400 variant_required).
      final variant = item['variant']?.toString() ?? '';
      if (variant.isNotEmpty &&
          product.variants.any((option) => option.name == variant)) {
        _cart.setVariant(product.id, variant);
      }
      for (var count = 0; count < (item['qty'] as num? ?? 1); count++) {
        _cart.add(product);
      }
    }
    if (mounted) setState(() => _section = 0);
  }

  /// S5: whether the server has seller invoices on (null = not asked yet).
  /// A 404 feature_disabled keeps the plain-text invoice for this session.
  bool? _sellerInvoices;

  /// Invoice: a paid order opens the sellers' invoices (one per seller,
  /// O-11) while the server has them on; otherwise the plain text as before.
  Future<void> _openInvoice(Map<String, dynamic> order) async {
    final id = order['id']?.toString() ?? '';
    if (_sellerInvoices != false &&
        shopOrderPayment(order) != ShopOrderPayment.awaitingConfirmation &&
        documentIdPattern.hasMatch(id)) {
      try {
        final res = await AppScope.of(context).api.myShopOrderInvoices(
          id,
          lang: FFLocaleScope.of(context).locale.languageCode,
        );
        _sellerInvoices = true;
        final list = (res['invoices'] as List? ?? []).whereType<Map>().toList();
        if (list.isNotEmpty && mounted) {
          final vendor = list.length == 1 ? list.single['vendorId'] : null;
          await context.push(
            buyerInvoiceRoute(id, vendorId: vendor?.toString()),
          );
          return;
        }
      } on ApiException catch (e) {
        if (e.code == 'feature_disabled') _sellerInvoices = false;
      } catch (_) {
        // No answer: the plain-text invoice below.
      }
    }
    if (mounted) _showInvoice(order);
  }

  void _showInvoice(Map<String, dynamic> order) {
    final items = (order['items'] as List? ?? []).whereType<Map>();
    final invoice = <String>[
      context.tr('shop.invoiceTitle'),
      '${context.tr('shop.order')}: ${order['id']}',
      ...items.map((item) => '${item['qty']} × ${item['name']}'),
      '${context.tr('shop.total')}: ${formatCurrency(order['totalTzs'] as num? ?? 0)}',
    ].join('\n');
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('shop.invoice')),
        content: SelectableText(invoice),
        actions: [
          FFButton(
            key: const Key('shop-download-receipt'),
            label: context.tr('shop.downloadReceipt'),
            variant: FFButtonVariant.ghost,
            onPressed: () async {
              try {
                await saveTextExport(
                  filename: 'fitflex-receipt-${order['id']}.txt',
                  content: invoice,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (_) {
                if (!dialogContext.mounted) return;
                FFSnack.error(
                  dialogContext,
                  dialogContext.tr('shop.exportFailed'),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = _section == 0 && _showHome;
    final segments = SegmentedButton<int>(
      // 48dp targets whatever density the platform uses (AC-46).
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        // A visible keyboard ring on the focused segment, including the
        // Volt-filled "Browse" in dark theme (AC-45).
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? ffFocusRingDark
                      : ffFocusRingLight,
                  width: 2,
                )
              : BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      segments: [
        ButtonSegment(
          value: 0,
          icon: const Icon(Icons.storefront_outlined),
          label: Text(context.tr('shop.browse')),
        ),
        ButtonSegment(
          value: 1,
          icon: const Icon(Icons.local_shipping_outlined),
          label: Text(context.tr('shop.myOrders')),
        ),
      ],
      selected: {_section},
      onSelectionChanged: (value) => setState(() => _section = value.first),
    );
    final list = LayoutBuilder(
      builder: (context, constraints) {
        // Shop home: a 16px gutter (rails scroll edge to edge inside it), in
        // a centred column of at most 1200px on wide screens (spec §6).
        const gutter = 16.0;
        final side = home && constraints.maxWidth > 1200 + 2 * gutter
            ? (constraints.maxWidth - 1200 - 2 * gutter) / 2
            : 0.0;
        return RefreshIndicator(
          onRefresh: () async {
            await _load();
            if (_section == 0 && _showHome) {
              await _homeKey.currentState?.reload();
            }
          },
          child: footerListView(
            padding: home
                ? EdgeInsets.symmetric(
                    vertical: FFTokens.spacingLg,
                    horizontal: side,
                  )
                : const EdgeInsets.all(FFTokens.spacingLg),
            // After "Browse all products", once the home has content.
            footer: home && widget.showHero && photoFooterUi
                ? FFPhotoFooter.sliver(
                    key: const Key('shop-footer'),
                    pageKey: 'member.shop',
                    top: FFHeroPhoto.shop,
                    backToTop: true,
                    headingFocus: _heroFocus,
                    enabled: _homeHasContent,
                    gap: FFTokens.spacingXl - FFTokens.spacingLg,
                  )
                : null,
            children: [
              if (home)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: gutter),
                  child: segments,
                )
              else
                segments,
              const SizedBox(height: FFTokens.spacingMd),
              if (home)
                ShopHomeView(
                  key: _homeKey,
                  mode: widget.mode,
                  showHero: widget.showHero,
                  heroFocusNode: _heroFocus,
                  onHasContent: (has) {
                    if (mounted && has != _homeHasContent) {
                      setState(() => _homeHasContent = has);
                    }
                  },
                  cart: _cart,
                  gutter: gutter,
                  initialData: _homeCache,
                  onData: (data) {
                    _homeCache = data;
                    _lastFetch = ShopClock.deviceNow();
                    // QA #2: the cart follows the fresh rows (a sale that
                    // started, ended or was ended early).
                    setState(
                      () => _refreshCart([
                        for (final e in data.products.entries)
                          ShopProduct.fromJson({'id': e.key, ...e.value}),
                      ]),
                    );
                  },
                  catalogue: _catalogueLoaded ? _products : null,
                  catalogueFailed: !_catalogueLoaded && _loadError != null,
                  onNeedCatalogue: () => unawaited(_ensureCatalogue()),
                  onOfflineChanged: (offline) {
                    if (mounted && offline != _homeOffline) {
                      setState(() => _homeOffline = offline);
                    }
                  },
                  onOpen: _openProduct,
                  onAdd: (product) => _addToCart(product, track: false),
                  onSearch: (text) => _openResults(search: text),
                  onCategory: (key) => _openResults(category: key),
                  onViewAll: (query) => _openResults(query: query),
                  onBrowseAll: () => _openResults(),
                  onBanner: _openBanner,
                  bannerIndex: _bannerIndex,
                  onBannerIndex: (i) => _bannerIndex = i,
                  onCheckout: _checkout,
                  onUnavailable: () {
                    setState(() => _homeUnavailable = true);
                    unawaited(_ensureCatalogue());
                  },
                )
              else if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(FFTokens.spacingXl),
                    child: FFSpinner(),
                  ),
                )
              else if (_section == 0)
                ..._buildCatalogue()
              else
                ..._buildOrders(),
            ],
          ),
        );
      },
    );
    if (!home || _cart.isEmpty) return list;
    return Column(
      children: [
        Expanded(child: list),
        // Phase 2 S4 (P1 §9): a sale in the cart ended or is about to.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ShopCartSaleNotice(
            key: const Key('shop-cartbar-sale-notice'),
            cart: _cart,
            // A line's sale ended: the bar's total is the price paid now.
            onChanged: () {
              if (mounted) setState(() {});
            },
          ),
        ),
        _cartBar(context),
      ],
    );
  }

  /// The Shop home's sticky cart bar (spec §5.1 #10), above the bottom
  /// navigation. It opens the same checkout as the list's button; offline it
  /// is disabled and says checkout needs a connection.
  Widget _cartBar(BuildContext context) {
    final count = _cart.itemCount;
    final total = formatCurrency(_cart.totalTzs);
    final label = _homeOffline
        ? context.tr('shop.home.checkoutOffline')
        : (count == 1
                  ? context.tr('shop.home.cartBarOne')
                  : context
                        .tr('shop.home.cartBar')
                        .replaceAll('{count}', '$count'))
              .replaceAll('{total}', total);
    final a11y =
        (count == 1
                ? context.tr('shop.a11y.cartBarOne')
                : context
                      .tr('shop.a11y.cartBar')
                      .replaceAll('{count}', '$count'))
            .replaceAll('{total}', total);
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final button = Semantics(
      button: true,
      excludeSemantics: true,
      label: _homeOffline ? label : a11y,
      onTap: _homeOffline || _ordering ? null : _checkout,
      child: FFButton(
        key: const Key('shop-home-checkout'),
        label: label,
        // 48dp on web/desktop too, and long Swahili wraps instead of "…".
        visualDensity: VisualDensity.standard,
        maxLines: 2,
        trailingIcon: _homeOffline ? null : Icons.arrow_forward,
        fullWidth: !wide,
        onPressed: _homeOffline || _ordering ? null : _checkout,
        loading: _ordering,
      ),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: wide
            ? Align(
                alignment: Alignment.centerRight,
                child: SizedBox(width: 360, child: button),
              )
            : button,
      ),
    );
  }

  List<Widget> _buildCatalogue() {
    final featured = _visibleFeatured;
    final categories = {
      ..._products.map((product) => product.category).whereType<String>(),
      // A category chosen on the home (tile, View all) is always a chip, and
      // shows as selected, even when nothing in it is loaded yet.
      ?_category,
    }.toList();
    return [
      if (shopHomeV2Enabled && !_homeUnavailable)
        Align(
          alignment: Alignment.centerLeft,
          child: FFButton(
            key: const Key('shop-back-to-home'),
            label: context.tr('shop.home.backToShop'),
            onPressed: _backToHome,
            variant: FFButtonVariant.ghost,
            size: FFButtonSize.sm,
            icon: Icons.arrow_back,
          ),
        ),
      if (_vendorId.isNotEmpty && _storeName.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: Semantics(
            header: true,
            child: Text(
              _storeName,
              key: const Key('shop-results-vendor'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      FFTextField(
        key: const Key('shop-search'),
        controller: _searchController,
        hint: context.tr('shop.searchHint'),
        prefixIcon: const Icon(Icons.search, size: 20),
        onChanged: (value) => setState(() => _search = value),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      SingleChildScrollView(
        key: const Key('shop-category-chips'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChip(
              materialTapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
              label: Text(context.tr('shop.allCategories')),
              selected: _category == null,
              onSelected: (_) => setState(() => _category = null),
            ),
            for (final category in categories) ...[
              const SizedBox(width: 6),
              FilterChip(
                key: _category == category
                    ? _selectedChipKey
                    : Key('shop-chip-$category'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
                label: Text(
                  ProductCategories.labelFor(
                    category,
                    FFLocaleScope.of(context).locale.languageCode,
                  ),
                ),
                selected: _category == category,
                onSelected: (_) => setState(() => _category = category),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: FFTokens.spacingMd),
      Row(
        children: [
          Expanded(
            child: FFDropdownField<String>(
              key: const Key('shop-sort'),
              value: _sort,
              label: context.tr('shop.sort'),
              items: [
                DropdownMenuItem(
                  value: 'newest',
                  child: Text(context.tr('shop.newest')),
                ),
                DropdownMenuItem(
                  value: 'popularity',
                  child: Text(context.tr('shop.popularity')),
                ),
                DropdownMenuItem(
                  value: 'price_asc',
                  child: Text(context.tr('shop.priceLow')),
                ),
                DropdownMenuItem(
                  value: 'price_desc',
                  child: Text(context.tr('shop.priceHigh')),
                ),
                DropdownMenuItem(
                  value: 'rating',
                  child: Text(context.tr('shop.rating')),
                ),
              ],
              onChanged: (value) => setState(() => _sort = value ?? 'newest'),
            ),
          ),
          IconButton(
            key: const Key('shop-more-filters'),
            tooltip: context.tr('shop.filters'),
            onPressed: _openFilters,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      Wrap(
        spacing: 6,
        children: [
          FilterChip(
            key: const Key('shop-delivery-filter'),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.standard,
            label: Text(context.tr('shop.delivery')),
            selected: _deliveryOnly,
            onSelected: (value) => setState(() => _deliveryOnly = value),
          ),
          FilterChip(
            key: const Key('shop-promotions-filter'),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.standard,
            label: Text(context.tr('shop.promotions')),
            selected: _promotionsOnly,
            onSelected: (value) => setState(() => _promotionsOnly = value),
          ),
          // Phase 2 S4: shown while it is on (from the flash sale rail), or
          // while something is on a flash sale.
          if (_flashSaleOnly || _products.any((p) => p.flashSaleLive))
            FilterChip(
              key: const Key('shop-flash-filter'),
              materialTapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
              label: Text(context.tr('shop.section.flash_sale')),
              selected: _flashSaleOnly,
              onSelected: (value) {
                setState(() => _flashSaleOnly = value);
                _pushUrl();
              },
            ),
        ],
      ),
      const SizedBox(height: FFTokens.spacingMd),
      if (featured.isNotEmpty)
        FFFeaturedStrip(
          title: context.tr('member.featuredProducts'),
          count: featured.length,
          // Grows with the text size so the card text is never clipped.
          height: 140 + MediaQuery.textScalerOf(context).scale(70),
          itemWidth: 160,
          itemBuilder: (context, i) => _FeaturedProductCard(
            key: Key('shop-featured-${featured[i].id}'),
            product: featured[i],
            placement: _placement,
            onOpen: () => _openProduct(featured[i]),
          ),
        ),
      if (_visible.isEmpty &&
          featured.isEmpty &&
          _products.isEmpty &&
          _loadError != null)
        isNetworkError(_loadError!)
            ? FFErrorState(
                key: const Key('shop-offline'),
                icon: Icons.wifi_off,
                title: context.tr('shop.home.offlineTitle'),
                message: context.tr('shop.home.offlineBody'),
                onRetry: _load,
              )
            : FFErrorState(
                key: const Key('shop-load-error'),
                title: context.tr('shop.home.errorTitle'),
                message: context.tr('shop.home.errorBody'),
                onRetry: _load,
              )
      else if (_visible.isEmpty && featured.isEmpty)
        FFEmptyState(title: context.tr('shop.noProducts'))
      else
        ..._visible.map(
          (product) => Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: _ProductTile(
              key: Key('shop-product-${product.id}'),
              product: product,
              promotion: _promoTags[product.id],
              placement: _placement,
              qty: _cart.qtyOf(product.id),
              saved: _saved.contains(product.id),
              onOpen: () => _openProduct(product),
              onSave: () => setState(() {
                if (_saved.add(product.id)) {
                  PromotionEvents.instance.recordForTouched(
                    'save',
                    'product',
                    product.id,
                  );
                  _shopEvent('product_favorited', productId: product.id);
                } else {
                  _saved.remove(product.id);
                }
                _cart.remove(product.id);
              }),
              onAdd: product.inStock ? () => _addToCart(product) : null,
              onRemove: _cart.qtyOf(product.id) > 0
                  ? () => setState(() => _cart.removeOne(product.id))
                  : null,
            ),
          ),
        ),
      if (_saved.isNotEmpty) ...[
        const SizedBox(height: FFTokens.spacingSm),
        Text('${context.tr('shop.savedForLater')}: ${_saved.length}'),
      ],
      if (!_cart.isEmpty) ...[
        const SizedBox(height: FFTokens.spacingMd),
        FFButton(
          key: const Key('shop-checkout'),
          label:
              '${context.tr('shop.checkout')} · ${formatCurrency(_cart.totalTzs)}',
          onPressed: _ordering ? null : _checkout,
          loading: _ordering,
        ),
      ],
    ];
  }

  List<Widget> _buildOrders() {
    if (_orders.isEmpty) {
      return [FFEmptyState(title: context.tr('shop.noOrders'))];
    }
    return _orders.map((order) {
      final status = order['status']?.toString() ?? 'pending';
      // The status is said once: as the last step of the order's progress
      // ("Pending → Accepted"), not again beside the amount.
      final steps = <String>[];
      for (final entry in (order['timeline'] as List? ?? []).whereType<Map>()) {
        final label = shopOrderStatusLabel(context, entry['status']);
        if (steps.isEmpty || steps.last != label) steps.add(label);
      }
      final current = shopOrderStatusLabel(context, status);
      if (steps.isEmpty || steps.last != current) steps.add(current);
      return Padding(
        padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
        child: FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context
                    .tr('shop.orderRef')
                    .replaceAll('{ref}', shopOrderRef(order)),
                key: Key('order-ref-${order['id']}'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(formatCurrency(order['totalTzs'] as num? ?? 0)),
              // Plain text, not chips: nothing here can be ticked or tapped.
              Text(
                steps.join(' → '),
                key: Key('order-status-${order['id']}'),
                semanticsLabel:
                    '${context.tr('shop.orderProgress')}: ${steps.join(', ')}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (shopOrderPaymentKey(order) case final paymentKey?)
                Text(
                  context.tr(paymentKey),
                  key: Key('order-payment-${order['id']}'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (shopOrderPayment(order) ==
                  ShopOrderPayment.awaitingConfirmation)
                FFButton(
                  key: Key('order-check-payment-${order['id']}'),
                  label: context.tr('shop.checkPayment'),
                  onPressed: () => _checkPayment(order),
                  variant: FFButtonVariant.ghost,
                  size: FFButtonSize.sm,
                ),
              const SizedBox(height: 6),
              Wrap(
                children: [
                  if (order['canCancel'] == true)
                    FFButton(
                      key: Key('order-cancel-${order['id']}'),
                      label: context.tr('shop.cancelOrder'),
                      onPressed: () => _cancelOrder(order),
                      variant: FFButtonVariant.ghost,
                      size: FFButtonSize.sm,
                    ),
                  // UAT D2 (AC-28): only once the order is paid (also
                  // after a refund was asked for or made).
                  if (const {
                    ShopOrderPayment.paid,
                    ShopOrderPayment.refundPending,
                    ShopOrderPayment.refunded,
                  }.contains(shopOrderPayment(order)))
                    FFButton(
                      key: Key('shop-invoice-${order['id']}'),
                      label: context.tr('shop.invoice'),
                      onPressed: () => _openInvoice(order),
                      variant: FFButtonVariant.ghost,
                      size: FFButtonSize.sm,
                    ),
                  FFButton(
                    key: Key('shop-reorder-${order['id']}'),
                    label: context.tr('shop.reorder'),
                    onPressed: () => _reorder(order),
                    variant: FFButtonVariant.ghost,
                    size: FFButtonSize.sm,
                  ),
                  if (status == 'delivered')
                    FFButton(
                      label: context.tr('shop.review'),
                      onPressed: () => _review(order),
                      variant: FFButtonVariant.ghost,
                      size: FFButtonSize.sm,
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Future<void> _review(Map<String, dynamic> order) async {
    final items = (order['items'] as List? ?? []).whereType<Map>().toList();
    if (items.isEmpty) return;
    final controller = TextEditingController();
    var rating = 5;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('shop.review')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Kept as the compact rating picker: FFDropdownField is a full-width
              // bordered field and would crowd the comment box below it.
              DropdownButton<int>(
                value: rating,
                items: [1, 2, 3, 4, 5]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$value '),
                            const Icon(Icons.star, size: 16),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => rating = value ?? 5),
              ),
              FFTextField(
                controller: controller,
                label: context.tr('shop.comment'),
              ),
            ],
          ),
          actions: [
            FFButton(
              label: context.tr('shop.submitReview'),
              onPressed: () => Navigator.pop(dialogContext, true),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await AppScope.of(context).api.reviewMarketplaceProduct(
        order['id'].toString(),
        items.first['productId'].toString(),
        rating,
        controller.text,
      );
      await _load();
    }
    controller.dispose();
  }
}

class _MarketplaceFilterValues {
  const _MarketplaceFilterValues({
    this.brand = '',
    this.vendorId = '',
    this.minPrice,
    this.maxPrice,
    this.minRating,
    this.maxDistanceKm,
  });

  final String brand;
  final String vendorId;
  final num? minPrice;
  final num? maxPrice;
  final num? minRating;
  final num? maxDistanceKm;
}

class _MarketplaceFiltersSheet extends StatefulWidget {
  const _MarketplaceFiltersSheet({
    required this.initial,
    this.showDistance = true,
  });
  final _MarketplaceFilterValues initial;

  /// False once the shop has areas (S3): the field is not rendered.
  final bool showDistance;

  @override
  State<_MarketplaceFiltersSheet> createState() =>
      _MarketplaceFiltersSheetState();
}

class _MarketplaceFiltersSheetState extends State<_MarketplaceFiltersSheet> {
  late final TextEditingController _brand;
  late final TextEditingController _vendor;
  late final TextEditingController _minPrice;
  late final TextEditingController _maxPrice;
  late final TextEditingController _rating;
  late final TextEditingController _distance;

  @override
  void initState() {
    super.initState();
    _brand = TextEditingController(text: widget.initial.brand);
    _vendor = TextEditingController(text: widget.initial.vendorId);
    _minPrice = TextEditingController(
      text: widget.initial.minPrice?.toString(),
    );
    _maxPrice = TextEditingController(
      text: widget.initial.maxPrice?.toString(),
    );
    _rating = TextEditingController(text: widget.initial.minRating?.toString());
    _distance = TextEditingController(
      text: widget.initial.maxDistanceKm?.toString(),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _brand,
      _vendor,
      _minPrice,
      _maxPrice,
      _rating,
      _distance,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  num? _number(TextEditingController controller) =>
      num.tryParse(controller.text.trim());

  @override
  Widget build(BuildContext context) {
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
                context.tr('shop.filters'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              FFTextField(
                key: const Key('shop-filter-brand'),
                controller: _brand,
                label: context.tr('shop.brand'),
              ),
              FFTextField(
                key: const Key('shop-filter-vendor'),
                controller: _vendor,
                label: context.tr('shop.vendor'),
              ),
              Row(
                children: [
                  Expanded(
                    child: FFTextField(
                      key: const Key('shop-filter-min-price'),
                      controller: _minPrice,
                      keyboardType: TextInputType.number,
                      label: context.tr('shop.minPrice'),
                    ),
                  ),
                  const SizedBox(width: FFTokens.spacingSm),
                  Expanded(
                    child: FFTextField(
                      key: const Key('shop-filter-max-price'),
                      controller: _maxPrice,
                      keyboardType: TextInputType.number,
                      label: context.tr('shop.maxPrice'),
                    ),
                  ),
                ],
              ),
              FFTextField(
                key: const Key('shop-filter-rating'),
                controller: _rating,
                keyboardType: TextInputType.number,
                label: context.tr('shop.minimumRating'),
              ),
              if (widget.showDistance)
                FFTextField(
                  key: const Key('shop-filter-distance'),
                  controller: _distance,
                  keyboardType: TextInputType.number,
                  label: context.tr('shop.maximumDistance'),
                ),
              const SizedBox(height: FFTokens.spacingLg),
              Row(
                children: [
                  FFButton(
                    key: const Key('shop-clear-filters'),
                    label: context.tr('shop.clearFilters'),
                    onPressed: () => Navigator.pop(
                      context,
                      const _MarketplaceFilterValues(),
                    ),
                    variant: FFButtonVariant.ghost,
                    size: FFButtonSize.sm,
                  ),
                  const Spacer(),
                  FFButton(
                    key: const Key('shop-apply-filters'),
                    label: context.tr('shop.applyFilters'),
                    onPressed: () => Navigator.pop(
                      context,
                      _MarketplaceFilterValues(
                        brand: _brand.text.trim(),
                        vendorId: _vendor.text.trim(),
                        minPrice: _number(_minPrice),
                        maxPrice: _number(_maxPrice),
                        minRating: _number(_rating),
                        maxDistanceKm: widget.showDistance
                            ? _number(_distance)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A product in the Featured row: image, name, price and its label.
class _FeaturedProductCard extends StatelessWidget {
  const _FeaturedProductCard({
    super.key,
    required this.product,
    required this.onOpen,
    this.placement,
  });

  final ShopProduct product;
  final VoidCallback onOpen;
  final String? placement;

  @override
  Widget build(BuildContext context) => PromotionTracked(
    entityType: 'product',
    entityId: product.id,
    promotion: product.promotion,
    placement: placement,
    child: _card(context),
  );

  Widget _card(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tag = product.promotion;
    return FFCard(
      child: InkWell(
        onTap: () {
          trackPromotionClick(
            'product',
            product.id,
            product.promotion,
            placement: placement,
          );
          onOpen();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                ),
                child: product.images.isEmpty
                    ? Icon(
                        Icons.shopping_bag_outlined,
                        color: colors.onSurfaceVariant,
                      )
                    : FFRemoteImage(
                        src: product.images.first,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        fallback: Icon(
                          Icons.shopping_bag_outlined,
                          color: colors.primary,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              formatCurrency(product.effectivePrice),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (tag != null) FFPromotionBadge(tag: tag),
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    super.key,
    required this.product,
    this.promotion,
    this.placement,
    required this.qty,
    required this.saved,
    required this.onOpen,
    required this.onSave,
    required this.onAdd,
    required this.onRemove,
  });
  final ShopProduct product;
  final PromotionTag? promotion;
  final String? placement;
  final int qty;
  final bool saved;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => PromotionTracked(
    entityType: 'product',
    entityId: product.id,
    promotion: promotion,
    placement: placement,
    child: _card(context),
  );

  Widget _card(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FFCard(
      child: InkWell(
        onTap: () {
          trackPromotionClick(
            'product',
            product.id,
            promotion,
            placement: placement,
          );
          onOpen();
        },
        child: Row(
          children: [
            // Out of stock: the photo is dimmed (AC-14).
            Opacity(
              key: Key('shop-image-${product.id}'),
              opacity: product.inStock ? 1 : 0.4,
              child: Container(
                width: 64,
                height: 64,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                ),
                child: product.images.isEmpty
                    ? Icon(
                        Icons.shopping_bag_outlined,
                        color: colors.onSurfaceVariant,
                      )
                    : FFRemoteImage(
                        src: product.images.first,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        fallback: Icon(
                          Icons.shopping_bag_outlined,
                          color: colors.primary,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (product.brand != null)
                    Text(
                      product.brand!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (promotion != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: FFPromotionBadge(tag: promotion!),
                    ),
                  if (!product.inStock)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: ShopOutOfStockBadge(
                        key: Key('shop-oos-${product.id}'),
                        label: context.tr('shop.outOfStock'),
                      ),
                    ),
                  // S3 (QA #4): the seller delivers to the shopper's area.
                  if (product.deliversToViewerArea)
                    Padding(
                      key: Key('shop-delivers-${product.id}'),
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: const ShopDeliversBadge(),
                    ),
                  if (shopOnSale(product)) ...[
                    // QA #7 (§8.1): the same "−N%" Fuel badge as the cards;
                    // the % is already in the price's label.
                    if (shopDiscountPercent(product) >= 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: ExcludeSemantics(
                          child: FFBadge(
                            key: Key('shop-discount-${product.id}'),
                            label: '−${shopDiscountPercent(product)}%',
                            tone: FFBadgeTone.fuel,
                          ),
                        ),
                      ),
                    // Sale price in Fuel, the original struck through below;
                    // read once as "Sale price …, was …".
                    Text(
                      formatCurrency(shopSalePrice(product)),
                      key: Key('shop-sale-${product.id}'),
                      semanticsLabel: shopSalePriceLabel(context, product),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? FFTokens.fuelOnDark
                            : FFTokens.fuel,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    ExcludeSemantics(
                      child: Text(
                        formatCurrency(shopWasPrice(product)),
                        key: Key('shop-was-${product.id}'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: FFTokens.mutedText(context),
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                  ] else
                    // A regular price in text-strong (brand green is for
                    // actions, not prices).
                    Text(
                      formatCurrency(product.effectivePrice),
                      key: Key('shop-price-${product.id}'),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  // A rating only with real reviews: never "★ 0.0".
                  Row(
                    children: [
                      if (product.reviewCount > 0 && product.rating > 0) ...[
                        const Icon(Icons.star, size: 16),
                        Flexible(
                          child: Text(
                            ' ${product.rating.toStringAsFixed(1)} (${product.reviewCount}) · ${_inStock(context, product)}',
                          ),
                        ),
                      ] else
                        Flexible(child: Text(_inStock(context, product))),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  key: Key('shop-save-${product.id}'),
                  style: _tileButton,
                  tooltip: context.tr('shop.saveForLater'),
                  icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                  onPressed: onSave,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (qty > 0)
                      IconButton(
                        tooltip: context.tr('a11y.decrease'),
                        style: _tileButton,
                        key: Key('shop-remove-${product.id}'),
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: onRemove,
                      ),
                    if (qty > 0) Text('$qty'),
                    // No cart button for an out-of-stock product (AC-14).
                    if (product.inStock)
                      IconButton(
                        tooltip: context.tr('a11y.increase'),
                        style: _tileButton,
                        key: Key('shop-add-${product.id}'),
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: onAdd,
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 48x48 for the list's icon buttons on every platform (AC-46).
final ButtonStyle _tileButton = IconButton.styleFrom(
  minimumSize: const Size(48, 48),
  tapTargetSize: MaterialTapTargetSize.padded,
  visualDensity: VisualDensity.standard,
);

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({this.cart, this.initial});

  /// The choices from the last time (after "Back to cart").
  final Map<String, String>? initial;

  /// With the Shop home on, the sheet starts with the cart itself (lines and
  /// total), so "View cart" and the cart bar open the real cart.
  final ShopCart? cart;
  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  String _delivery = 'home_delivery';
  String _payment = 'mpesa';
  final _address = TextEditingController();
  String? _gymId;
  List<Map<String, dynamic>> _gyms = [];
  String _gymSearch = '';
  Position? _pickupPosition;

  double? _gymDistance(Map<String, dynamic> gym) {
    final coordinates = gym['coordinates'];
    if (_pickupPosition == null || coordinates is! Map) return null;
    final lat = double.tryParse('${coordinates['lat']}');
    final lng = double.tryParse(
      '${coordinates['lng'] ?? coordinates['longitude']}',
    );
    if (lat == null || lng == null) return null;
    return Geolocator.distanceBetween(
          _pickupPosition!.latitude,
          _pickupPosition!.longitude,
          lat,
          lng,
        ) /
        1000;
  }

  Future<void> _nearestGyms() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      setState(() {
        _pickupPosition = position;
        _gyms.sort(
          (a, b) => (_gymDistance(a) ?? double.infinity).compareTo(
            _gymDistance(b) ?? double.infinity,
          ),
        );
      });
    } catch (_) {
      if (!mounted) return;
      FFSnack.error(context, context.tr('shop.locationUnavailable'));
    }
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _delivery = initial['deliveryMethod'] ?? _delivery;
      _address.text = initial['deliveryAddress'] ?? '';
      _gymId = initial['pickupGymId'];
      _payment = initial['paymentMethod'] ?? _payment;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final rows = await AppScope.of(context).api.listGyms();
        if (mounted) {
          setState(
            () => _gyms = rows.whereType<Map<String, dynamic>>().toList(),
          );
        }
      } on ApiException {
        // The address checkout remains available when gym discovery is offline.
      }
    });
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  /// The cart: each line (name, option, quantity, line price) and the total.
  Widget _cartSummary(BuildContext context, ShopCart cart) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('shop-cart-summary'),
      padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (product, qty, variant) in cart.lines)
            Padding(
              key: Key('shop-cart-line-${product.id}'),
              padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$qty × ${product.name}${variant == null ? '' : ' · $variant'}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        // Phase 2 S4: a line whose flash sale ended since it
                        // was added now costs the regular price.
                        if (product.flashSaleEnded)
                          Text(
                            context.tr('shop.sale.cartLineEnded'),
                            key: Key('shop-cart-line-ended-${product.id}'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: FFTokens.mutedText(context),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: FFTokens.spacingSm),
                  if (product.flashSaleLive)
                    // Sale price in Fuel, the "was" total struck below it;
                    // read once.
                    Semantics(
                      container: true,
                      excludeSemantics: true,
                      label: shopSalePriceLabel(context, product),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatCurrency(cart.unitPriceOf(product.id) * qty),
                            key: Key('shop-cart-line-sale-${product.id}'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.brightness == Brightness.dark
                                  ? FFTokens.fuelOnDark
                                  : FFTokens.fuel,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            formatCurrency(shopWasPrice(product) * qty),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: FFTokens.mutedText(context),
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      formatCurrency(cart.unitPriceOf(product.id) * qty),
                      style: theme.textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
          ShopCartSaleNotice(cart: cart),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('shop.total'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                formatCurrency(cart.totalTzs),
                key: const Key('shop-cart-total'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (_delivery == 'home_delivery' && _address.text.trim().isEmpty) {
      FFSnack.error(context, context.tr('shop.addressRequired'));
      return;
    }
    if (_delivery == 'gym_pickup' && _gymId == null) {
      FFSnack.error(context, context.tr('shop.pickupGymRequired'));
      return;
    }
    Navigator.pop(context, {
      'deliveryMethod': _delivery,
      if (_delivery == 'home_delivery') 'deliveryAddress': _address.text.trim(),
      if (_delivery == 'gym_pickup') 'pickupGymId': _gymId!,
      'paymentMethod': _payment,
    });
  }

  @override
  Widget build(BuildContext context) {
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
                context.tr('shop.checkout'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (widget.cart case final cart?) _cartSummary(context, cart),
              RadioGroup<String>(
                groupValue: _delivery,
                onChanged: (value) => setState(() => _delivery = value!),
                child: Column(
                  children: [
                    RadioListTile(
                      value: 'home_delivery',
                      title: Text(context.tr('shop.homeDelivery')),
                    ),
                    RadioListTile(
                      value: 'gym_pickup',
                      title: Text(context.tr('shop.gymPickup')),
                    ),
                  ],
                ),
              ),
              if (_delivery == 'home_delivery')
                FFTextField(
                  key: const Key('shop-delivery-address'),
                  controller: _address,
                  label: context.tr('shop.deliveryAddress'),
                )
              else ...[
                FFTextField(
                  key: const Key('shop-pickup-search'),
                  label: context.tr('shop.searchPickup'),
                  onChanged: (value) =>
                      setState(() => _gymSearch = value.trim().toLowerCase()),
                ),
                FFButton(
                  label: context.tr('shop.nearestGyms'),
                  onPressed: _nearestGyms,
                  variant: FFButtonVariant.ghost,
                  size: FFButtonSize.sm,
                  icon: Icons.near_me_outlined,
                ),
                FFDropdownField<String>(
                  key: const Key('shop-pickup-gym'),
                  value: _gymId,
                  label: context.tr('shop.selectGym'),
                  items: _gyms
                      .where(
                        (gym) =>
                            gym['id'] == _gymId ||
                            '${gym['name']} ${gym['location'] ?? ''}'
                                .toLowerCase()
                                .contains(_gymSearch),
                      )
                      .map(
                        (gym) => DropdownMenuItem(
                          value: gym['id'].toString(),
                          child: Text(
                            '${gym['name']} · ${gym['location'] ?? ''}'
                            '${_gymDistance(gym) == null ? '' : ' · ${_gymDistance(gym)!.toStringAsFixed(1)} km'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _gymId = value),
                  isExpanded: true,
                ),
              ],
              const SizedBox(height: FFTokens.spacingMd),
              FFDropdownField<String>(
                key: const Key('shop-payment-method'),
                value: _payment,
                label: context.tr('shop.paymentMethod'),
                items: [
                  for (final method in const [
                    'mpesa',
                    'airtel_money',
                    'mixx',
                    'card',
                    'bank',
                  ])
                    DropdownMenuItem(
                      value: method,
                      child: Text(shopPaymentMethodLabel(context, method)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _payment = value ?? 'mpesa'),
              ),
              const SizedBox(height: FFTokens.spacingLg),
              SizedBox(
                width: double.infinity,
                child: FFButton(
                  key: const Key('shop-place-order'),
                  label: context.tr('shop.payAndOrder'),
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

class _ProductDetailsSheet extends StatelessWidget {
  const _ProductDetailsSheet({
    required this.product,
    required this.onAdd,
    this.showDistance = true,
  });
  final ShopProduct product;

  /// False once the shop has areas (S3): no vendor-typed "{n} km".
  final bool showDistance;
  final Future<bool> Function() onAdd;

  Future<void> _chat(BuildContext context) async {
    final controller = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('shop.chatVendor')),
        content: FFTextField(
          key: const Key('shop-enquiry-message'),
          controller: controller,
          maxLines: 3,
          hint: context.tr('shop.enquiryHint'),
        ),
        actions: [
          FFButton(
            key: const Key('shop-enquiry-send'),
            label: context.tr('shop.send'),
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (send == true && controller.text.trim().isNotEmpty && context.mounted) {
      await AppScope.of(
        context,
      ).api.sendMarketplaceEnquiry(product.id, controller.text.trim());
    }
    controller.dispose();
  }

  Future<void> _visitStore(BuildContext context) async {
    try {
      final store = await AppScope.of(
        context,
      ).api.vendorStore(product.vendorId);
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => VendorStoreSheet(store: store),
      );
    } on ApiException {
      if (!context.mounted) return;
      FFSnack.error(context, context.tr('shop.storeLoadFailed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            // Decorative handle (QA2 #3): the same look as the framework's,
            // not announced.
            ExcludeSemantics(
              child: Center(
                child: Container(
                  key: const Key('shop-product-handle'),
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                key: const Key('shop-product-close'),
                tooltip: context.tr('member.close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            if (product.images.isNotEmpty)
              SizedBox(
                height: 220,
                child: PageView(
                  children: product.images
                      .map(
                        (image) => FFRemoteImage(src: image, fit: BoxFit.cover),
                      )
                      .toList(),
                ),
              ),
            Text(
              product.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (product.brand != null) Text(product.brand!),
            if (product.flashSaleLive) ...[
              // Phase 2 S4: the sale price in Fuel, the "was" price struck
              // below it, read once; then when the sale ends (spec §8.1).
              Semantics(
                container: true,
                excludeSemantics: true,
                label: shopSalePriceLabel(context, product),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: FFTokens.spacingSm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          formatCurrency(shopSalePrice(product)),
                          key: Key('shop-detail-sale-${product.id}'),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? FFTokens.fuelOnDark
                                    : FFTokens.fuel,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        FFBadge(
                          label: '−${product.sale!.percentOff}%',
                          tone: FFBadgeTone.fuel,
                        ),
                      ],
                    ),
                    Text(
                      formatCurrency(shopWasPrice(product)),
                      key: Key('shop-detail-was-${product.id}'),
                      style: TextStyle(
                        color: FFTokens.mutedText(context),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                ),
              ),
              ShopSaleEndsLine(sale: product.sale!),
            ] else ...[
              Text(
                formatCurrency(product.effectivePrice),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              // Same rule as the cards: a real reduction only (0 < discount
              // < price); a 0 or higher "discount" is not a sale.
              if (product.effectivePrice < product.priceTzs)
                Text(
                  formatCurrency(product.priceTzs),
                  style: const TextStyle(
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              // The sale ended while the sheet was open (or before it was
              // refreshed): said, with the price it costs now.
              if (product.flashSaleEnded)
                Text(
                  context.tr('shop.home.saleEnded'),
                  key: const Key('shop-detail-sale-ended'),
                ),
            ],
            Row(
              children: [
                if (product.reviewCount > 0 && product.rating > 0) ...[
                  Text('${_inStock(context, product)} · '),
                  const Icon(Icons.star, size: 16),
                  Text(
                    ' ${product.rating.toStringAsFixed(1)} (${product.reviewCount})',
                  ),
                ] else
                  Text(_inStock(context, product)),
              ],
            ),
            if (showDistance && product.distanceKm != null)
              Text('${product.distanceKm} km · ${context.tr('shop.delivery')}'),
            const SizedBox(height: FFTokens.spacingMd),
            Text(product.description ?? ''),
            if (product.vendor.isNotEmpty) ...[
              const SizedBox(height: FFTokens.spacingSm),
              Text(
                '${context.tr('shop.vendor')}: ${product.vendor['businessName'] ?? product.vendorId}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
            // S3: under the seller line. Never a "doesn't deliver" message.
            if (product.deliversToViewerArea) ...[
              const SizedBox(height: FFTokens.spacingXs),
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: ShopDeliversBadge(),
              ),
            ],
            const SizedBox(height: FFTokens.spacingMd),
            Text(
              context.tr('shop.reviews'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (product.reviews.isEmpty)
              Text(context.tr('shop.noReviews'))
            else
              ...product.reviews.map(
                (review) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _RatingLabel(rating: review['rating']),
                  title: Text(
                    review['comment']?.toString().trim().isNotEmpty == true
                        ? review['comment'].toString()
                        : context.tr('shop.ratingOnly'),
                  ),
                ),
              ),
            if (product.similarProducts.isNotEmpty) ...[
              Text(
                context.tr('shop.similarProducts'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ...product.similarProducts.map(
                (similar) => ListTile(
                  key: Key('shop-similar-${similar.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.shopping_bag_outlined),
                  title: Text(similar.name),
                  // QA #9: a product on sale says so here too: −N%, the
                  // sale price and the struck "was" price (read once).
                  subtitle:
                      shopOnSale(similar) && shopDiscountPercent(similar) >= 1
                      ? Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: ExcludeSemantics(
                            child: FFBadge(
                              key: Key('shop-similar-discount-${similar.id}'),
                              label: '−${shopDiscountPercent(similar)}%',
                              tone: FFBadgeTone.fuel,
                            ),
                          ),
                        )
                      : null,
                  trailing: shopOnSale(similar)
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatCurrency(shopSalePrice(similar)),
                              key: Key('shop-similar-sale-${similar.id}'),
                              semanticsLabel: shopSalePriceLabel(
                                context,
                                similar,
                              ),
                              style: TextStyle(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? FFTokens.fuelOnDark
                                    : FFTokens.fuel,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            ExcludeSemantics(
                              child: Text(
                                formatCurrency(shopWasPrice(similar)),
                                style: TextStyle(
                                  color: FFTokens.mutedText(context),
                                  decoration: TextDecoration.lineThrough,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Text(formatCurrency(similar.effectivePrice)),
                ),
              ),
            ],
            const SizedBox(height: FFTokens.spacingLg),
            FFButton(
              key: Key('shop-detail-add-${product.id}'),
              label: context.tr('shop.addToCart'),
              onPressed: product.inStock ? () => onAdd() : null,
            ),
            FFButton(
              label: context.tr('shop.buyNow'),
              onPressed: product.inStock
                  ? () async {
                      // Only go on to checkout once a unit really is in the cart.
                      if (await onAdd() && context.mounted) {
                        Navigator.pop(context, true);
                      }
                    }
                  : null,
              variant: FFButtonVariant.secondary,
            ),
            FFButton(
              key: const Key('shop-chat-vendor'),
              label: context.tr('shop.chatVendor'),
              onPressed: () => _chat(context),
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
            ),
            FFButton(
              key: const Key('shop-visit-store'),
              label: context.tr('shop.visitStore'),
              onPressed: () => _visitStore(context),
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
            ),
          ],
        ),
      ),
    );
  }
}

class VendorStoreSheet extends StatefulWidget {
  const VendorStoreSheet({super.key, required this.store});
  final Map<String, dynamic> store;

  @override
  State<VendorStoreSheet> createState() => _VendorStoreSheetState();
}

class _VendorStoreSheetState extends State<VendorStoreSheet> {
  String _search = '';

  List<ShopProduct> get _products => (widget.store['products'] as List? ?? [])
      .whereType<Map>()
      .map((value) => ShopProduct.fromJson(Map<String, dynamic>.from(value)))
      .where(
        (product) =>
            _search.isEmpty ||
            [product.name, product.category, product.brand].any(
              (value) =>
                  (value ?? '').toLowerCase().contains(_search.toLowerCase()),
            ),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final products = _products;
    final categories = products
        .map((product) => product.category)
        .whereType<String>()
        .toSet()
        .map(
          (c) => ProductCategories.labelFor(
            c,
            FFLocaleScope.of(context).locale.languageCode,
          ),
        )
        .join(', ');
    final reviews = (store['reviews'] as List? ?? []).whereType<Map>();
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: ListView(
          key: const Key('shop-vendor-storefront'),
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                key: const Key('shop-store-close'),
                tooltip: context.tr('member.close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            if (store['banner']?.toString().isNotEmpty == true)
              ClipRRect(
                borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                child: FFRemoteImage(
                  src: store['banner'].toString(),
                  height: 160,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: FFTokens.spacingMd),
            Row(
              children: [
                if (store['logo']?.toString().isNotEmpty == true)
                  ClipOval(
                    child: FFRemoteImage(
                      src: store['logo'].toString(),
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(width: FFTokens.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store['businessName']?.toString() ??
                            context.tr('shop.vendorStore'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      // A score only with real reviews: never "★ 0.0 (0)".
                      if (_shopNumber(store['reviewCount']) > 0 &&
                          _shopNumber(store['rating']) > 0)
                        Row(
                          key: const Key('shop-store-rating'),
                          children: [
                            const Icon(Icons.star, size: 16),
                            Text(
                              ' ${_shopNumber(store['rating']).toStringAsFixed(1)} (${_shopNumber(store['reviewCount']).toInt()})',
                            ),
                          ],
                        )
                      else
                        Text(
                          context.tr('reviews.none'),
                          key: const Key('shop-store-no-reviews'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingMd),
            Text(store['description']?.toString() ?? ''),
            Text(
              '${context.tr('shop.contact')}: ${store['contactNumber'] ?? ''}',
            ),
            Text('${store['email'] ?? ''} · ${store['address'] ?? ''}'),
            if (categories.isNotEmpty)
              Text('${context.tr('shop.categories')}: $categories'),
            const SizedBox(height: FFTokens.spacingMd),
            FFTextField(
              key: const Key('shop-store-search'),
              label: context.tr('shop.searchStore'),
              prefixIcon: const Icon(Icons.search),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: FFTokens.spacingMd),
            Text(
              context.tr('shop.products'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (products.isEmpty)
              Text(context.tr('shop.noProducts'))
            else
              ...products.map(
                (product) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.shopping_bag_outlined),
                  title: Text(product.name),
                  subtitle: Text(
                    ProductCategories.labelFor(
                      product.category,
                      FFLocaleScope.of(context).locale.languageCode,
                    ),
                  ),
                  trailing: Text(formatCurrency(product.effectivePrice)),
                ),
              ),
            Text(
              context.tr('shop.reviews'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (reviews.isEmpty)
              Text(context.tr('shop.noReviews'))
            else
              ...reviews.map(
                (review) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _RatingLabel(rating: review['rating']),
                  title: Text(review['comment']?.toString() ?? ''),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RatingLabel extends StatelessWidget {
  const _RatingLabel({required this.rating});
  final dynamic rating;

  @override
  Widget build(BuildContext context) {
    // A review without a score shows no star rather than "0".
    final value = _shopNumber(rating);
    if (value <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${value % 1 == 0 ? value.toInt() : value} '),
        const Icon(Icons.star, size: 16),
      ],
    );
  }
}
