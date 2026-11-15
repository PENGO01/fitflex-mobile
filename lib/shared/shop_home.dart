// Shop home V2 (Phase 1): the data the personalised shop landing is built
// from, the build flag, the analytics events and the device's recently-viewed
// list. Screens live in lib/shared/widgets/shop_home/.
//
// Contract (Phase 1): GET /shop/home only. The backend has no
// /shop/preferences or /shop/events yet; the event model below is kept for
// Phase 2 and sends nothing unless SHOP_EVENTS is switched on.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'product_categories.dart';
import 'shop_near_you.dart';
import 'shop_clock.dart';

export 'shop_clock.dart';

/// `--dart-define=SHOP_HOME_V2=true` turns the new shop home on. Off (the
/// default) leaves today's shop screen exactly as it was.
const bool kShopHomeV2 = bool.fromEnvironment(
  'SHOP_HOME_V2',
  defaultValue: false,
);

/// Lets tests switch the flag without a rebuild of the binary.
@visibleForTesting
bool? debugShopHomeV2Override;

bool get shopHomeV2Enabled => debugShopHomeV2Override ?? kShopHomeV2;

/// `--dart-define=SHOP_EVENTS=true` sends shop analytics to POST
/// /shop/events. Off by default: that endpoint does not exist yet (Phase 2).
const bool kShopEvents = bool.fromEnvironment(
  'SHOP_EVENTS',
  defaultValue: false,
);

@visibleForTesting
bool? debugShopEventsOverride;

bool get shopEventsEnabled => debugShopEventsOverride ?? kShopEvents;

/// A live flash sale on a product row (Phase 2 S4, SHOP_FLASH_SALES;
/// fitflex-functions docs/shop-flash-sales-api.md "Product rows"): `sale`
/// = `{id, salePriceTzs, wasPriceTzs, regularPriceTzs, discountPct,
/// startsAt, endsAt}`, sent only while live. The app still checks [endsAt]
/// against [ShopClock], so a sale that ends while the screen is open stops
/// at once.
class ShopFlashSale {
  const ShopFlashSale({
    required this.id,
    required this.salePriceTzs,
    required this.wasPriceTzs,
    required this.endsAt,
    this.startsAt,
    this.discountPct,
  });

  final String id;
  final num salePriceTzs;

  /// The regular price the sale is measured against (struck through): the
  /// price when it was approved.
  final num wasPriceTzs;
  final DateTime? startsAt;
  final DateTime endsAt;

  /// The server's floor((was − sale) × 100 / was), when sent.
  final int? discountPct;

  /// A sale the app can show: an id, an end, and a sale price above zero
  /// and below the "was" price. Anything else is ignored (no sale UI).
  static ShopFlashSale? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id']?.toString() ?? '';
    num? n(Object? v) => v is num ? v : num.tryParse(v?.toString() ?? '');
    DateTime? d(Object? v) => DateTime.tryParse(v?.toString() ?? '')?.toUtc();
    final sale = n(json['salePriceTzs']);
    final was = n(json['wasPriceTzs']) ?? n(json['regularPriceTzs']);
    final ends = d(json['endsAt']);
    if (id.isEmpty || sale == null || was == null || ends == null) return null;
    if (sale <= 0 || sale >= was) return null;
    final pct = n(json['discountPct']);
    return ShopFlashSale(
      id: id,
      salePriceTzs: sale,
      wasPriceTzs: was,
      startsAt: d(json['startsAt']),
      endsAt: ends,
      discountPct: pct?.toInt(),
    );
  }

  /// Still on by the server's clock (live means now < endsAt).
  bool get live => ShopClock.now().isBefore(endsAt);

  /// floor((was − sale) × 100 / was): never overstated. The server's own
  /// figure when it sent one.
  int get percentOff =>
      discountPct ??
      (wasPriceTzs <= 0
          ? 0
          : ((wasPriceTzs - salePriceTzs) * 100 / wasPriceTzs).floor());
}

/// The role the customer is shopping as. A default for what is suggested,
/// never a limit on what can be browsed.
enum ShopHomeMode {
  member('member'),
  trainer('trainer'),
  owner('owner'),
  vendorPersonal('vendor_personal');

  const ShopHomeMode(this.wire);
  final String wire;
}

/// A line the server sends in both languages.
class ShopText {
  const ShopText(this.en, this.sw);
  final String en;
  final String sw;

  static ShopText? fromJson(Object? json) {
    if (json is! Map) return null;
    final en = json['en']?.toString() ?? '';
    final sw = json['sw']?.toString() ?? '';
    if (en.isEmpty && sw.isEmpty) return null;
    return ShopText(en, sw);
  }

  String of(String lang) => lang == 'sw' && sw.isNotEmpty
      ? sw
      : en.isNotEmpty
      ? en
      : sw;
}

class ShopHomeCategory {
  const ShopHomeCategory({required this.key, required this.label});
  final String key;
  final ShopText label;
}

/// One reason a section is shown, as a code the app translates (spec §8.3),
/// with its values (e.g. `{category: equipment}`).
class ShopReasonCode {
  const ShopReasonCode(this.code, [this.params = const {}]);
  final String code;
  final Map<String, String> params;

  /// Accepts `"best_sellers_30d"` or `{code, params}`; anything else is null.
  static ShopReasonCode? fromJson(Object? json) {
    if (json is String && json.isNotEmpty) return ShopReasonCode(json);
    if (json is! Map) return null;
    final code = json['code']?.toString() ?? '';
    if (code.isEmpty) return null;
    final params = json['params'];
    return ShopReasonCode(
      code,
      params is Map ? shopReasonParams(params) : const {},
    );
  }
}

/// Reason values as strings. A value sent in both languages (`areaName:
/// {en, sw}`, slice 3) becomes `areaName` (English) and `areaName.sw`; read
/// it with [shopReasonParam].
Map<String, String> shopReasonParams(Map raw) {
  final out = <String, String>{};
  for (final e in raw.entries) {
    final key = e.key.toString();
    final v = e.value;
    if (v == null) continue;
    if (v is Map) {
      final text = ShopText.fromJson(v);
      if (text == null) continue;
      out[key] = text.of('en');
      out['$key.sw'] = text.of('sw');
    } else {
      out[key] = v.toString();
    }
  }
  return out;
}

/// The value of [key] in [lang] from [shopReasonParams] output.
String? shopReasonParam(Map<String, String> params, String key, String lang) =>
    (lang == 'sw' ? params['$key.sw'] : null) ?? params[key];

class ShopHomeSection {
  const ShopHomeSection({
    required this.key,
    this.title,
    this.reason,
    this.reasonCodes = const [],
    this.viewAll = const {},
    this.hasMore,
    this.productIds = const [],
    this.endsAt,
  });

  /// Phase 2 S4: the `flash_sale` section's end, the earliest end among
  /// the products shown (count down against `serverNow`).
  final DateTime? endsAt;

  /// featured, recommended, best_sellers, popular_near_you, essentials,
  /// recently_viewed, deals, new_arrivals (others are shown the same way).
  final String key;

  /// Null when the server sent none: the app then uses `shop.section.<key>`.
  final ShopText? title;
  final ShopText? reason;

  /// Reason codes, shown as translated bullets in "Why am I seeing this?".
  final List<ShopReasonCode> reasonCodes;

  bool get hasWhy => reason != null || reasonCodes.isNotEmpty;

  /// The filters "View all" opens the product list with.
  final Map<String, String> viewAll;

  /// Whether "View all" can show more than the rail (functions#179). Null
  /// from an older backend that does not send it.
  final bool? hasMore;
  final List<String> productIds;

  /// "View all" only leads somewhere when there are filters to open the list
  /// with, or more to see. Recently viewed is this device's own list: the
  /// product list cannot show it, so it never has one.
  bool get showViewAll =>
      key != 'recently_viewed' && (hasMore ?? viewAll.isNotEmpty);

  factory ShopHomeSection.fromJson(Map<String, dynamic> json) {
    final viewAll = json['viewAll'];
    final query = viewAll is Map ? viewAll['query'] : null;
    // Phase 2 S2: `reasonParams` ({category} / {productName}) sits on the
    // section; `reasonCodes` stays a list of strings. Codes sent without
    // their own params take the section's.
    final rawParams = json['reasonParams'];
    final sectionParams = rawParams is Map
        ? shopReasonParams(rawParams)
        : const <String, String>{};
    return ShopHomeSection(
      key: json['key']?.toString() ?? '',
      title: ShopText.fromJson(json['title']),
      reason: ShopText.fromJson(json['reason']),
      reasonCodes: (json['reasonCodes'] as List? ?? [])
          .map(ShopReasonCode.fromJson)
          .whereType<ShopReasonCode>()
          .map(
            (c) => c.params.isEmpty && sectionParams.isNotEmpty
                ? ShopReasonCode(c.code, sectionParams)
                : c,
          )
          .toList(),
      hasMore: json['hasMore'] is bool ? json['hasMore'] as bool : null,
      viewAll: query is Map
          ? {
              for (final e in query.entries)
                if (e.value != null) e.key.toString(): e.value.toString(),
            }
          : const {},
      productIds: (json['productIds'] as List? ?? [])
          .map((id) => id.toString())
          .where((id) => id.isNotEmpty)
          .toList(),
      endsAt: DateTime.tryParse(json['endsAt']?.toString() ?? '')?.toUtc(),
    );
  }
}

/// Where a banner's button leads (Phase 2 S1). [type] is one of
/// [ShopBannerTarget.types]; [value] is a product id, a vendor id or a
/// category key. A `results` target carries the product list's filters
/// (the GET /shop/products query: category, search, brand, vendorId,
/// promotions, sort, delivery) in [query]; none means every product.
class ShopBannerTarget {
  const ShopBannerTarget(this.type, this.value, [this.query = const {}]);
  final String type;
  final String value;
  final Map<String, String> query;

  static const types = {'product', 'vendor_store', 'category', 'results'};

  static ShopBannerTarget? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = json['type']?.toString() ?? '';
    if (!types.contains(type)) return null;
    final raw = json['value'];
    if (type == 'results') {
      return ShopBannerTarget(type, '', _query(raw));
    }
    final value = raw is String || raw is num ? raw.toString() : '';
    // Everything but "all products" needs something to open.
    if (value.isEmpty) return null;
    return ShopBannerTarget(type, value);
  }

  static Map<String, String> _query(Object? raw) {
    if (raw is Map) {
      return {
        for (final e in raw.entries)
          if (e.value != null && '${e.value}'.isNotEmpty)
            e.key.toString(): e.value.toString(),
      };
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        return Uri.splitQueryString(
          raw.startsWith('?') ? raw.substring(1) : raw,
        );
      } catch (_) {
        return const {};
      }
    }
    return const {};
  }
}

/// A banner's image in three sizes: 1x and 2x phone crops and a wide crop
/// for 840 px and up, and where `BoxFit.cover` keeps the subject ([focalX],
/// [focalY], -1..1, as an Alignment). The server sends root-relative
/// `/storage/...` addresses; [resolved] makes them absolute.
class ShopBannerImage {
  const ShopBannerImage({
    this.url1x = '',
    this.url2x = '',
    this.urlWide = '',
    this.focalX = 0,
    this.focalY = 0,
  });
  final String url1x;
  final String url2x;
  final String urlWide;
  final double focalX;
  final double focalY;

  /// An absolute http(s) address or a root-relative path ("/storage/..."),
  /// else empty (no "//host", no other schemes).
  static String _url(Object? v) {
    final s = v?.toString().trim() ?? '';
    if (s.startsWith('https://') || s.startsWith('http://')) return s;
    if (s.startsWith('/') && !s.startsWith('//')) return s;
    return '';
  }

  static double _focal(Object? v) =>
      v is num && v.isFinite ? v.toDouble().clamp(-1.0, 1.0) : 0;

  static ShopBannerImage fromJson(Object? json) {
    if (json is! Map) return const ShopBannerImage();
    final focal = json['focal'] is Map ? json['focal'] as Map : const {};
    return ShopBannerImage(
      url1x: _url(json['url1x']),
      url2x: _url(json['url2x']),
      urlWide: _url(json['urlWide']),
      focalX: _focal(focal['x']),
      focalY: _focal(focal['y']),
    );
  }

  bool get isEmpty => url1x.isEmpty && url2x.isEmpty && urlWide.isEmpty;

  /// Root-relative addresses on the API server [base].
  ShopBannerImage resolved(String base) {
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    String abs(String u) => u.startsWith('/') ? '$root$u' : u;
    return ShopBannerImage(
      url1x: abs(url1x),
      url2x: abs(url2x),
      urlWide: abs(urlWide),
      focalX: focalX,
      focalY: focalY,
    );
  }

  /// The best file for a slide [width] logical px wide at [dpr], falling
  /// back to whichever exists. Null when there is none.
  String? pick(double width, double dpr) {
    final order = width >= 840
        ? [urlWide, url2x, url1x]
        : dpr > 1.5
        ? [url2x, url1x, urlWide]
        : [url1x, url2x, urlWide];
    for (final u in order) {
      if (u.isNotEmpty) return u;
    }
    return null;
  }
}

/// One hero banner on the Shop home (Phase 2 S1, flag SHOP_BANNERS on the
/// server). Only live, approved banners for this role are sent.
class ShopBanner {
  const ShopBanner({
    required this.id,
    required this.image,
    required this.headlineLead,
    required this.target,
    this.imageAlt,
    this.headlineAccent,
    this.subline,
    this.ctaLabel,
    this.origin = 'staff',
    this.vendorName,
    this.endsAt,
  });

  final String id;
  final ShopBannerImage image;

  /// Sent by the server; the slide's photo is decorative (the headline
  /// carries the meaning), so this is not read out.
  final ShopText? imageAlt;
  final ShopText headlineLead;
  final ShopText? headlineAccent;
  final ShopText? subline;
  final ShopText? ctaLabel;
  final ShopBannerTarget target;

  /// `vendor` or `staff`.
  final String origin;
  final String? vendorName;
  final DateTime? endsAt;

  /// The same banner with its image addresses on the API server [base].
  ShopBanner withImageBase(String base) => ShopBanner(
    id: id,
    image: image.resolved(base),
    imageAlt: imageAlt,
    headlineLead: headlineLead,
    headlineAccent: headlineAccent,
    subline: subline,
    ctaLabel: ctaLabel,
    target: target,
    origin: origin,
    vendorName: vendorName,
    endsAt: endsAt,
  );

  /// A vendor's banner shows "From {vendor}"; staff banners show nothing.
  bool get fromVendor =>
      origin == 'vendor' && (vendorName ?? '').trim().isNotEmpty;

  /// A banner the app can show: an id, a headline and a target it knows.
  static ShopBanner? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id']?.toString() ?? '';
    final lead = ShopText.fromJson(json['headlineLead']);
    final target = ShopBannerTarget.fromJson(json['target']);
    if (id.isEmpty || lead == null || target == null) return null;
    return ShopBanner(
      id: id,
      image: ShopBannerImage.fromJson(json['image']),
      imageAlt: ShopText.fromJson(json['imageAlt']),
      headlineLead: lead,
      headlineAccent: ShopText.fromJson(json['headlineAccent']),
      subline: ShopText.fromJson(json['subline']),
      ctaLabel: ShopText.fromJson(json['ctaLabel']),
      target: target,
      origin: json['origin']?.toString() == 'vendor' ? 'vendor' : 'staff',
      vendorName: json['vendorName']?.toString(),
      endsAt: DateTime.tryParse(json['endsAt']?.toString() ?? ''),
    );
  }
}

/// The answer to GET /shop/home. Products stay raw JSON here so the shop's own
/// product model reads them, exactly as it reads the product list.
class ShopHomeData {
  const ShopHomeData({
    required this.mode,
    this.personalised = false,
    this.signalsUsed = const [],
    this.categories = const [],
    this.sections = const [],
    this.products = const {},
    this.serverNow,
    this.allProductsCount,
    this.banners = const [],
    this.bannersOn = false,
    this.personalisation,
    this.nearYou,
  });

  /// Phase 2 S3 (SHOP_NEAR_YOU): whether "Popular near you" may be used for
  /// this person now, and the area the answer was built for. Null from a
  /// backend without the flag: no invite, no rail, no location read.
  final ShopNearYou? nearYou;

  /// Phase 2 S2 (SHOP_PERSONALISATION): whether the "Personalised shop"
  /// switch is offered and on. Null from a backend without the flag: no
  /// switch and nothing personal is shown.
  final ShopPersonalisation? personalisation;

  /// The server sent a `banners` key (SHOP_BANNERS on), even if empty.
  /// Off: no key, and the home is laid out exactly as before.
  final bool bannersOn;

  /// Hero banners (Phase 2 S1), in the server's order. Empty when the
  /// server's SHOP_BANNERS is off or sends none: the home is then laid out
  /// exactly as before.
  final List<ShopBanner> banners;

  final String mode;
  final bool personalised;
  final List<String> signalsUsed;
  final List<ShopHomeCategory> categories;
  final List<ShopHomeSection> sections;
  final Map<String, Map<String, dynamic>> products;
  final DateTime? serverNow;

  /// How many products the shop lists in all (functions#179); 0 means the
  /// shop is getting ready. Null from an older backend.
  final int? allProductsCount;

  factory ShopHomeData.fromJson(Map<String, dynamic> json) {
    final rawProducts = json['products'];
    final serverNow = DateTime.tryParse(json['serverNow']?.toString() ?? '');
    return ShopHomeData(
      personalisation: ShopPersonalisation.fromJson(json['personalisation']),
      nearYou: ShopNearYou.fromJson(json['nearYou']),
      bannersOn: json['banners'] is List,
      banners: (json['banners'] is List ? json['banners'] as List : const [])
          .map(ShopBanner.fromJson)
          .whereType<ShopBanner>()
          // One that ended by the server's own clock is not shown.
          .where(
            (b) =>
                b.endsAt == null ||
                serverNow == null ||
                b.endsAt!.isAfter(serverNow),
          )
          .toList(),
      mode: json['mode']?.toString() ?? '',
      personalised: json['personalised'] == true,
      signalsUsed: (json['signalsUsed'] as List? ?? [])
          .map((s) => s.toString())
          .toList(),
      serverNow: serverNow,
      allProductsCount: json['allProductsCount'] is num
          ? (json['allProductsCount'] as num).toInt()
          : null,
      categories: (json['categories'] as List? ?? [])
          .whereType<Map>()
          .map((c) {
            final key = c['key']?.toString() ?? '';
            return ShopHomeCategory(
              key: key,
              label: ShopText.fromJson(c) ?? shopCategoryText(key),
            );
          })
          .where((c) => c.key.isNotEmpty)
          .toList(),
      sections: (json['sections'] as List? ?? [])
          .whereType<Map>()
          .map((s) => ShopHomeSection.fromJson(Map<String, dynamic>.from(s)))
          .where((s) => s.key.isNotEmpty)
          .toList(),
      products: rawProducts is Map
          ? {
              for (final e in rawProducts.entries)
                if (e.value is Map)
                  e.key.toString(): Map<String, dynamic>.from(e.value as Map),
            }
          : const {},
    );
  }
}

/// `personalisation` on GET /shop/home (Phase 2 S2). [available] is false
/// when the flag is off for this account or it may not be personalised
/// (under 18): the switch is then hidden and nothing personal is shown.
class ShopPersonalisation {
  const ShopPersonalisation({required this.available, required this.enabled});
  final bool available;
  final bool enabled;

  /// Personal reasons may be shown only when both are true.
  bool get active => available && enabled;

  static ShopPersonalisation? fromJson(Object? json) {
    if (json is! Map) return null;
    return ShopPersonalisation(
      available: json['available'] == true,
      enabled: json['enabled'] == true,
    );
  }
}

/// GET/PUT /shop/preferences (Phase 2 S2). A 404 `feature_disabled` (or any
/// 404 / non-JSON answer) means personalisation does not exist here: every
/// personalisation control is hidden.
class ShopPreferences {
  const ShopPreferences({
    required this.personalised,
    required this.available,
    this.historyDays,
    this.uses,
    this.mode,
    this.profileSignals = false,
  });
  final bool personalised;
  final bool available;

  /// Partner DOB slice 4 (functions#346): true only in trainer and owner
  /// mode while the server uses a partner's own date of birth for gender
  /// and age (SHOP_PERSONALISATION_PARTNERS and PARTNER_DOB_REQUIRED on).
  /// Absent (any older server, or a flag off) = false.
  final bool profileSignals;

  /// The shopping mode the answer is for (`member`, `trainer`, `owner`,
  /// `vendor_personal`); null from a backend that does not say.
  final String? mode;

  /// How far back purchase history is read (server `SHOP_HISTORY_DAYS`).
  /// Null from a backend that does not say.
  final int? historyDays;

  /// The signals actually in use for this account right now, as
  /// [ShopSignal] names. Null from a backend that does not send `uses`.
  final Set<ShopSignal>? uses;

  /// Where a change was made, sent with every PUT.
  static const sourcePrivacyPage = 'privacy_page';
  static const sourceWhySheet = 'why_sheet';

  /// [historyDays] as whole months (365 → 12), at least 1. Null when unknown.
  int? get historyMonths {
    final days = historyDays;
    if (days == null || days <= 0) return null;
    final months = (days / 30.4).round();
    return months < 1 ? 1 : months;
  }

  static ShopPreferences fromJson(Object? json) {
    final m = json is Map ? json : const {};
    final rawUses = m['uses'];
    return ShopPreferences(
      // Default on (O-6): only an explicit false is off.
      personalised: m['personalised'] != false,
      available: m['available'] == true,
      profileSignals: m['profileSignals'] == true,
      mode: m['mode'] is String ? m['mode'] as String : null,
      historyDays: m['historyDays'] is num
          ? (m['historyDays'] as num).toInt()
          : null,
      uses: rawUses is List
          ? {for (final u in rawUses) ?ShopSignal.fromWire(u?.toString())}
          : null,
    );
  }
}

/// A signal the shop uses, as listed in `uses` (functions#239), in the
/// server's order. Anything else is ignored.
enum ShopSignal {
  purchaseHistory('purchase_history'),
  gender('profile_gender'),
  age('profile_age'),

  /// Phase 2 S3: "your current area is used if you allow location on this
  /// device" (the server cannot know the device's choice).
  location('location'),
  goal('goal'),
  specialty('specialty');

  const ShopSignal(this.wire);
  final String wire;

  static ShopSignal? fromWire(String? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }
}

/// Product "Made for" values on the wire (null = everyone), Phase 2 S2.
const kTargetGenders = ['women', 'men'];

/// Product "Age group" bands on the wire, in display order (none = all ages).
const kTargetAgeBands = ['18_29', '30_44', '45_59', '60_plus'];

/// Reason codes that rest on the customer's own data. Never shown unless
/// the server says personalisation is available and on.
const kPersonalReasonCodes = {
  'bought_category',
  'bought_product',
  'profile_gender',
  'profile_age',
  'delivers_to_area',
  'popular_in_area',
  'seller_in_area',
};

/// The app's own name for a category key (the compiled-in list), or the key
/// itself when even that does not know it.
ShopText shopCategoryText(String key) {
  for (final c in ProductCategories.current) {
    if (c.key == key) return ShopText(c.en, c.sw);
  }
  return ShopText(key, '');
}

/// Shop analytics: `POST /shop/events`, one event per call, fire and forget.
///
/// Only the fields in the contract are ever sent (type, section, productId,
/// position, mode), so no name, phone, email or search text can leave the
/// device through here. A 404 (backend without the endpoint) switches it off
/// for the rest of the session; every other failure is ignored.
class ShopEvents {
  ShopEvents._();

  static const types = {
    'shop_home_viewed',
    'section_viewed',
    'product_impression',
    'product_clicked',
    'search_submitted',
    'filter_applied',
    'product_favorited',
    'add_to_cart',
  };

  static const allowedFields = {
    'type',
    'section',
    'productId',
    'position',
    'mode',
  };

  static bool _disabled = false;
  static final Set<String> _seen = {};

  @visibleForTesting
  static void reset() {
    _disabled = false;
    _seen.clear();
  }

  /// The exact body sent for one event.
  static Map<String, dynamic> build(
    String type, {
    required ShopHomeMode mode,
    String? section,
    String? productId,
    int? position,
  }) => {
    'type': type,
    'mode': mode.wire,
    if (section != null && section.isNotEmpty) 'section': section,
    if (productId != null && productId.isNotEmpty) 'productId': productId,
    'position': ?position,
  };

  /// Sends one event without waiting. [once] drops repeats of the same key
  /// (impressions and section views are counted once per load).
  static void send(
    ApiClient api,
    String type, {
    required ShopHomeMode mode,
    String? section,
    String? productId,
    int? position,
    String? once,
  }) {
    if (!shopEventsEnabled || _disabled || !types.contains(type)) return;
    if (once != null && !_seen.add(once)) return;
    final body = build(
      type,
      mode: mode,
      section: section,
      productId: productId,
      position: position,
    );
    unawaited(
      Future<void>(() async {
        try {
          await api.postShopEvent(body);
        } on ApiException catch (e) {
          if (e.status == 404) _disabled = true;
        } on FormatException {
          // A non-JSON answer (an HTML 404 page): no such endpoint here.
          _disabled = true;
        } catch (_) {
          // Analytics never get in the way of shopping.
        }
      }),
    );
  }

  /// Forget which impressions were already counted (a new home load).
  static void newLoad() => _seen.clear();
}

/// Products opened on this device, newest first, at most [max]. Kept per
/// signed-in account so one person's history is not sent for another.
class RecentlyViewedProducts {
  RecentlyViewedProducts._();

  static const max = 20;
  static const _prefix = 'ff.shop.recent';

  static String _key(String? userId) =>
      userId == null || userId.isEmpty ? _prefix : '$_prefix.$userId';

  static Future<List<String>> load(String? userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_key(userId)) ?? const <String>[])
          .take(max)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> add(String? userId, String productId) async {
    if (productId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = [
        productId,
        ...(prefs.getStringList(_key(userId)) ?? const <String>[]).where(
          (id) => id != productId,
        ),
      ].take(max).toList();
      await prefs.setStringList(_key(userId), list);
    } catch (_) {
      // Not remembered; nothing else depends on it.
    }
  }
}
