import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../api_client.dart';
import '../../api_error_message.dart';
import '../../components/components.dart';
import '../../design_tokens.dart';
import '../../i18n.dart';
import '../../photo_hero_flag.dart';
import '../../product_categories.dart';
import '../../../router.dart' show AppRoutes;
import '../../promotion_events.dart' show discoverSessionId;
import '../../shop_home.dart';
import '../../shop_near_you.dart';
import '../shop_browse_page.dart' show ShopCart, ShopProduct;
import 'shop_banner_carousel.dart';
import 'shop_category_row.dart';
import 'shop_product_card.dart';
import 'shop_focus_ring.dart';
import 'shop_near_you_ui.dart';
import 'shop_partner_dob_hint.dart';
import 'shop_personalisation.dart';
import 'shop_product_rail.dart';

/// The server's placement for the marketplace: promotion events from the
/// home must use it (anything else is refused as `invalid_placement`).
const kShopHomePlacement = 'marketplace';

/// PHOTO_HERO_UI (owner 2026-10-22): the member Shop band's clear photo
/// above its text, on every phone, so the FitFlex Africa sign
/// ([FFHeroPhoto.shop], focal top) sits wholly above the text.
const double shopBandClearPhoto = FFTokens.heroBandClearPhoto;

/// The personalised Shop home (V2, Phase 1): search and cart, "Shop by
/// category", then the sections the server chose, in the server's order.
///
/// It owns only the home request; the cart, product details, checkout, the
/// product list and the sticky cart bar belong to the shop screen around it
/// (ShopBrowseBody), reached through the callbacks. [onUnavailable] tells
/// the screen to show today's shop instead: the backend has no shop home
/// (404 / non-JSON), refuses it (403 after a retry without mode), or fails
/// (5xx / timeout) before anything was shown.
class ShopHomeView extends StatefulWidget {
  const ShopHomeView({
    super.key,
    required this.mode,
    required this.cart,
    required this.onOpen,
    required this.onAdd,
    required this.onSearch,
    required this.onCategory,
    required this.onViewAll,
    required this.onBrowseAll,
    required this.onCheckout,
    required this.onUnavailable,
    this.gutter = 16,
    this.initialData,
    this.onData,
    this.catalogue,
    this.catalogueFailed = false,
    this.onNeedCatalogue,
    this.onOfflineChanged,
    this.showHero = false,
    this.heroFocusNode,
    this.onHasContent,
    this.onBanner,
    this.bannerIndex = 0,
    this.onBannerIndex,
  });

  final ShopHomeMode mode;
  final ShopCart cart;
  final void Function(ShopProduct product) onOpen;

  /// Adds one unit (asking for an option first when needed); whether it did.
  final Future<bool> Function(ShopProduct product) onAdd;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onCategory;
  final ValueChanged<Map<String, String>> onViewAll;
  final VoidCallback onBrowseAll;
  final VoidCallback onCheckout;
  final VoidCallback onUnavailable;

  /// Side padding of the page; rails scroll edge to edge inside it.
  final double gutter;

  /// The last home this screen loaded (kept by the screen), shown at once
  /// while it is fetched again, and kept if that fails offline.
  final ShopHomeData? initialData;
  final ValueChanged<ShopHomeData>? onData;

  /// Today's product list (GET /shop/products), for the "All products" grid
  /// when the server sends no sections. Null until loaded.
  final List<ShopProduct>? catalogue;
  final bool catalogueFailed;
  final VoidCallback? onNeedCatalogue;

  /// Whether the last request failed for lack of a connection.
  final ValueChanged<bool>? onOfflineChanged;

  /// The static brand band under the search row (PHOTO_HERO_UI, increment
  /// plan slice 1). Only the member shop asks for it; the trainer and owner
  /// shops and the pushed ShopBrowsePage do not.
  final bool showHero;

  /// The band heading's focus node (the page footer's Back to top).
  final FocusNode? heroFocusNode;

  /// Whether the home shows rails or the All products grid (the page's
  /// footer shows only then). Called after the frame, when it changes.
  final ValueChanged<bool>? onHasContent;

  /// A hero banner's button was tapped (Phase 2 S1): open its target. The
  /// carousel is shown only when this is set and the server sent banners.
  final ValueChanged<ShopBanner>? onBanner;

  /// The slide last shown, so coming back from a banner's target shows it
  /// again.
  final int bannerIndex;
  final ValueChanged<int>? onBannerIndex;

  @override
  State<ShopHomeView> createState() => ShopHomeViewState();
}

class ShopHomeViewState extends State<ShopHomeView> {
  ShopHomeData? _data;
  Object? _error;
  bool _loading = true;
  int _load = 0;
  bool _askedCatalogue = false;

  /// This account's near-you choice on this device (Phase 2 S3), read
  /// before every home request. Never holds a position.
  ShopNearYouState _near = ShopNearYouState.empty;

  /// The area is being worked out (after "Use my location").
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;
    ShopNearYouStore.changes.addListener(_nearChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) reload();
    });
  }

  /// The choice or the area changed (here, in the Why sheet or on the
  /// Privacy page): ask again with the new area, or without one.
  void _nearChanged() {
    if (mounted) reload();
  }

  /// The role the last answer was for (the server's default after a
  /// `mode_not_allowed` retry); events report this one.
  ShopHomeMode _mode(ShopHomeData? data) => ShopHomeMode.values.firstWhere(
    (m) => m.wire == data?.mode,
    orElse: () => widget.mode,
  );

  /// Fetches the home again. Content already shown stays while it loads.
  ///
  /// The only location-derived value sent is the area id the phone worked
  /// out (Phase 2 S3, `X-FF-Area`), and only while this account has
  /// near-you on AND the last answer said near-you is available (L1).
  Future<void> reload() async {
    final scope = AppScope.of(context);
    final id = ++_load;
    setState(() => _loading = true);
    final uid = scope.auth.user?['id']?.toString();
    final recent = await RecentlyViewedProducts.load(uid);
    final near = await ShopNearYouStore.load(uid);
    if (!mounted) return;
    _near = near;
    final areaId = ShopNearYouStore.areaToSend(uid);
    Future<Map<String, dynamic>> fetch(String? mode) => scope.api.shopHome(
      mode: mode,
      // Lets the server sign promotion tokens for Featured cards.
      session: discoverSessionId(),
      recent: recent,
      areaId: areaId,
    );
    try {
      Map<String, dynamic> json;
      try {
        json = await fetch(widget.mode.wire);
      } on ApiException catch (e) {
        // Not allowed to shop as this role: try once with the default role.
        if (e.status != 403 || e.code != 'mode_not_allowed') rethrow;
        json = await fetch(null);
      }
      if (!mounted || id != _load) return;
      final data = ShopHomeData.fromJson(json);
      // Phase 2 S4: every countdown follows the server's clock.
      ShopClock.sync(data.serverNow);
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
      _live.value = data;
      _watchSales(data);
      widget.onData?.call(data);
      widget.onOfflineChanged?.call(false);
      ShopEvents.newLoad();
      ShopEvents.send(scope.api, 'shop_home_viewed', mode: _mode(data));
      final available = data.nearYou?.available == true;
      ShopNearYouStore.setLastAvailable(uid, available);
      // Near-you not available (personalisation off, not allowed, flag
      // switched off) or the switch is off: forget the kept area (L1).
      if (data.nearYou?.available == false ||
          data.personalisation?.enabled == false) {
        unawaited(ShopNearYouStore.clear(uid));
      } else if (available && near.choice == ShopNearYouChoice.on) {
        if (areaId == null && near.areaId != null) {
          // The first answer this session says near-you is available:
          // setLastAvailable bumped `changes`, and the listener asks again
          // with the kept area.
        } else {
          // Work the area out again once a session (never prompting). A
          // change is saved, which reloads the home through the listener.
          final lang = FFLocaleScope.of(context).locale.languageCode;
          unawaited(ShopNearYouFlow.refresh(context, lang));
        }
      }
    } on ApiException catch (e) {
      if (!mounted || id != _load) return;
      if (e.status == 404 || e.status == 403) return _unavailable();
      // A server failure before anything is shown: the spec's fallback
      // layout (categories + "All products" from the product list).
      if (e.status >= 500 && _data == null) return _degraded();
      _failed(e);
    } on FormatException {
      // A success answer that is not JSON. (An HTML error page arrives as an
      // ApiException with its status: 404 → unavailable, 5xx → fallback.)
      if (mounted && id == _load) _unavailable();
    } on TimeoutException catch (e) {
      // Too slow is treated as a server failure, not as being offline.
      if (!mounted || id != _load) return;
      if (_data == null) return _degraded();
      _failed(e);
    } catch (e) {
      if (!mounted || id != _load) return;
      _failed(e);
    }
  }

  void _failed(Object error) {
    setState(() {
      _error = error;
      _loading = false;
    });
    widget.onOfflineChanged?.call(isNetworkError(error));
  }

  /// The home could not be built (5xx / timeout): show the categories and
  /// the "All products" grid from today's product list (AC-02, §9 Partial).
  /// If that list fails too, the grid says so with Try again.
  void _degraded() {
    setState(() {
      _data = ShopHomeData(mode: widget.mode.wire);
      _error = null;
      _loading = false;
    });
  }

  void _unavailable() {
    setState(() => _loading = false);
    widget.onUnavailable();
  }

  void _event(
    String type, {
    String? section,
    String? productId,
    int? position,
    String? once,
  }) => ShopEvents.send(
    AppScope.of(context).api,
    type,
    mode: _mode(_data),
    section: section,
    productId: productId,
    position: position,
    once: once,
  );

  Future<void> _add(ShopProduct product, String section, int position) async {
    final messenger = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final added = await widget.onAdd(product);
    if (!mounted) return;
    if (added) {
      _event(
        'add_to_cart',
        section: section,
        productId: product.id,
        position: position,
      );
      messenger.success(
        locale.t('shop.home.added'),
        actionLabel: locale.t('shop.home.viewCart'),
        onAction: widget.onCheckout,
      );
    } else if (widget.cart.qtyOf(product.id) > 0) {
      // Already in the cart and nothing added: the stock limit was reached.
      // (Nothing in the cart means the option picker was closed.)
      messenger.info(locale.t('shop.home.notAdded'));
    }
  }

  String _roleLine() => switch (_mode(_data)) {
    ShopHomeMode.member => 'shop.why.roleMember',
    ShopHomeMode.trainer => 'shop.why.roleTrainer',
    ShopHomeMode.owner => 'shop.why.roleOwner',
    ShopHomeMode.vendorPersonal => 'shop.why.roleVendor',
  };

  /// A category's name: the server's own list in this answer first, then
  /// the app's compiled-in list.
  String _categoryName(String key, String lang) {
    for (final c in _data?.categories ?? const <ShopHomeCategory>[]) {
      if (c.key == key) return c.label.of(lang);
    }
    return shopCategoryText(key).of(lang);
  }

  /// One translated bullet for a reason code, or null for a code the app
  /// does not know (spec §8.3; the role line is shown separately).
  String? _reasonLine(BuildContext context, ShopReasonCode reason) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    String with_(String key, String name, String? value) =>
        context.tr(key).replaceAll('{$name}', value ?? '');
    return switch (reason.code) {
      'popular_with_role' => context.tr('shop.why.popularWithRole'),
      'bought_category' => with_(
        'shop.why.boughtCategory',
        'category',
        _categoryName(reason.params['category'] ?? '', lang),
      ),
      'bought_product' => with_(
        'shop.why.boughtProduct',
        'product',
        reason.params['productName'] ?? reason.params['product'],
      ),
      // Partner DOB slice 4: in trainer and owner modes these come from the
      // partner's own date of birth (and gender), not a member profile.
      'profile_gender' => context.tr(switch (_mode(_data)) {
        ShopHomeMode.trainer => 'shop.why.genderTrainer',
        ShopHomeMode.owner => 'shop.why.genderOwner',
        _ => 'shop.why.gender',
      }),
      'profile_age' => context.tr(
        isPartnerShopMode(_mode(_data).wire)
            ? 'shop.why.agePartner'
            : 'shop.why.age',
      ),
      'delivers_to_area' => context.tr('shop.why.deliversToArea'),
      'popular_in_area' => with_(
        'shop.why.popularInArea',
        'areaName',
        shopReasonParam(reason.params, 'areaName', lang) ??
            _data?.nearYou?.areaName?.of(lang),
      ),
      'seller_in_area' => with_(
        'shop.why.sellerInArea',
        'areaName',
        shopReasonParam(reason.params, 'areaName', lang) ??
            _data?.nearYou?.areaName?.of(lang),
      ),
      'featured_disclosure' => context.tr('shop.why.featured'),
      // Two different discounts: a time-limited flash sale (later phase)
      // and a seller's ordinary lower price (the Deals section).
      'flash_sale_seller_discount' => context.tr('shop.why.flashSale'),
      'seller_discount' => context.tr('shop.why.sellerDiscount'),
      'best_sellers_30d' => context.tr('shop.why.bestSellers'),
      'profile_goal' => context.tr('shop.why.profileGoal'),
      'trainer_specialty' => context.tr('shop.why.trainerSpecialty'),
      'recently_viewed' => context.tr('shop.why.recentlyViewed'),
      'new_arrival' => context.tr('shop.why.newArrival'),
      'generic' => context.tr('shop.why.generic'),
      _ => null,
    };
  }

  /// The latest home answer, for an open Why sheet to follow (a reload
  /// after the switch changes what may be said).
  final ValueNotifier<ShopHomeData?> _live = ValueNotifier(null);

  /// Partner DOB slice 4: GET /shop/preferences for the trainer or owner
  /// mode, read when their Why sheet opens, so the switch hint follows
  /// `uses` (gender/age only once the server lists them). Null until read,
  /// or when the read failed (the purchases-only hint stays).
  final ValueNotifier<ShopPreferences?> _partnerPrefs = ValueNotifier(null);

  Future<void> _loadPartnerPrefs(ShopHomeMode mode) async {
    try {
      final prefs = ShopPreferences.fromJson(
        await AppScope.of(context).api.shopPreferences(mode: mode.wire),
      );
      if (mounted) _partnerPrefs.value = prefs;
    } catch (_) {
      // Not known: the hint names purchases only.
    }
  }

  /// The signals in play for this answer and preferences: the
  /// preferences' `uses` plus any gender/age the home answer reports.
  static Set<ShopSignal> _signalsOf(
    ShopHomeData? data,
    ShopPreferences? prefs,
  ) {
    final out = <ShopSignal>{...?prefs?.uses};
    void add(String code) {
      final s = ShopSignal.fromWire(code);
      if (s == ShopSignal.gender || s == ShopSignal.age) out.add(s!);
    }

    for (final code in data?.signalsUsed ?? const <String>[]) {
      add(code);
    }
    for (final s in data?.sections ?? const <ShopHomeSection>[]) {
      for (final c in s.reasonCodes) {
        add(c.code);
      }
    }
    return out;
  }

  /// The trainer or owner shop's own "Personalised shop" sheet (what is
  /// used, the date-of-birth hint and the slice 5 explanation).
  Future<void> _openPartnerPrivacy(ShopHomeMode mode, bool enabled) async {
    final initial =
        _partnerPrefs.value ??
        ShopPreferences(
          personalised: enabled,
          available: true,
          mode: mode.wire,
        );
    await showShopSheet<void>(
      context,
      title: context.tr('privacy.shop.title'),
      child: ShopPrivacySheet(
        initial: initial,
        mode: mode.wire,
        onChanged: (prefs) {
          _partnerPrefs.value = prefs;
          if (mounted) reload();
        },
      ),
    );
  }

  @override
  void dispose() {
    ShopNearYouStore.changes.removeListener(_nearChanged);
    _saleTimer?.cancel();
    _refetchTimer?.cancel();
    _live.dispose();
    _partnerPrefs.dispose();
    super.dispose();
  }

  // ── Phase 2 S4: flash sales ending while the home is open ────────────────

  /// Fires when the next sale on screen ends (server clock).
  Timer? _saleTimer;

  /// The one refetch after a sale ended (0–3 s jitter, P1 §9).
  Timer? _refetchTimer;

  /// Tests: the delay before the refetch (default 0–3 s at random).
  @visibleForTesting
  static Duration Function()? debugRefetchJitter;

  /// The earliest sale end still ahead among what [data] shows (the
  /// flash_sale section's end and every product's own sale).
  static DateTime? _nextSaleEnd(ShopHomeData data) {
    final now = ShopClock.now();
    DateTime? next;
    void consider(DateTime? at) {
      if (at == null || !at.isAfter(now)) return;
      if (next == null || at.isBefore(next!)) next = at;
    }

    for (final s in data.sections) {
      if (s.key == 'flash_sale') consider(s.endsAt);
    }
    for (final p in data.products.values) {
      consider(ShopFlashSale.fromJson(p['sale'])?.endsAt);
    }
    return next;
  }

  void _watchSales(ShopHomeData data) {
    _saleTimer?.cancel();
    final next = _nextSaleEnd(data);
    if (next == null) return;
    // A moment after the end, so the sale reads as over when it fires.
    final wait =
        next.difference(ShopClock.now()) + const Duration(milliseconds: 1);
    _saleTimer = Timer(wait, _saleEnded);
  }

  /// A sale on screen just ended: the cards switch to "Sale ended" now
  /// (cart buttons off), and the home is fetched once more after a short
  /// random wait, so phones do not all ask at the same instant.
  void _saleEnded() {
    if (!mounted) return;
    setState(() {});
    if (_refetchTimer?.isActive != true) {
      final jitter =
          debugRefetchJitter?.call() ??
          Duration(milliseconds: math.Random().nextInt(3000));
      _refetchTimer = Timer(jitter, () {
        if (mounted) reload();
      });
    }
    final data = _data;
    if (data != null) _watchSales(data);
  }

  /// The bullets for [section]: translated reason codes, the server's own
  /// sentence only for codes the app does not know. With [personal] false
  /// nothing about the customer's own data is said, whatever was sent (and
  /// the server's sentence is not used either: it may name a purchase).
  List<String> _whyLines(
    BuildContext context,
    ShopHomeSection section, {
    required bool personal,
    required bool serverSentence,
  }) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final lines = <String>[];
    final codes = [
      for (final c in section.reasonCodes)
        if (personal || !kPersonalReasonCodes.contains(c.code)) c,
    ];
    var unknown = codes.isEmpty;
    for (final code in codes) {
      if (code.code == 'role_context') continue;
      final line = _reasonLine(context, code);
      if (line == null) {
        unknown = true;
      } else if (!lines.contains(line)) {
        lines.add(line);
      }
    }
    // Nothing the app could say in its own words (only unknown codes, or
    // just role_context): the server's sentence too.
    if (lines.isEmpty) unknown = true;
    final server = section.reason?.of(lang);
    if (unknown && serverSentence && server != null && server.isNotEmpty) {
      lines.add(server);
    }
    if (lines.isEmpty && !serverSentence) {
      lines.add(context.tr('shop.why.generic'));
    }
    return lines;
  }

  String _offLine() => switch (_mode(_data)) {
    ShopHomeMode.member => 'shop.why.offMember',
    ShopHomeMode.trainer => 'shop.why.offTrainer',
    ShopHomeMode.owner => 'shop.why.offOwner',
    ShopHomeMode.vendorPersonal => 'shop.why.offVendor',
  };

  /// "Why am I seeing this?" (spec §8.1): a bullet per reason code, in the
  /// customer's language, then the role line, then (Phase 2 S2) the
  /// "Personalised shop" switch. The lines follow the switch at once: off
  /// drops every personal reason and says suggestions are off; the home
  /// reloads behind the sheet and the sheet follows the new answer.
  Future<void> _showWhy(ShopHomeSection section) async {
    _live.value = _data;
    final first0 = _data;
    final first = _data?.personalisation;
    final mode = _mode(_data);
    final showSwitch = first?.available == true;
    final partner = isPartnerShopMode(mode.wire);
    if (partner && showSwitch) {
      _partnerPrefs.value = null;
      unawaited(_loadPartnerPrefs(mode));
    }
    // The last signals naming gender/age while the sheet is open (kept when
    // the switch goes off and `uses` empties, so the hint does not change
    // under it).
    Set<ShopSignal>? profileUses;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    // The switch's value as the customer just set it (null: as loaded).
    bool? on;
    await showShopSheet<void>(
      context,
      title: context.tr('shop.why.title'),
      child: ListenableBuilder(
        listenable: Listenable.merge([_live, _partnerPrefs]),
        builder: (sheet, _) => StatefulBuilder(
          builder: (sheet, setSheet) {
            final data = _live.value;
            final signals = _signalsOf(data, _partnerPrefs.value);
            if (usesProfileSignals(signals)) profileUses = signals;
            final theme = Theme.of(sheet);
            final p = data?.personalisation ?? first;
            final live = data?.sections
                .where((x) => x.key == section.key)
                .firstOrNull;
            // The rail can leave the page (near-you after the switch goes
            // off): its old reasons are then only used without anything
            // personal and without the server's sentence (QA #1).
            final current = live ?? section;
            final enabled = on ?? p?.enabled ?? true;
            // A backend without personalisation (null): Phase 1 sheet.
            final personal =
                p == null || (p.available && enabled && p.enabled == enabled);
            // The server's sentence only while it matches the switch and
            // the section is still in the answer it came with.
            final serverSentence =
                (p == null || p.enabled == enabled) &&
                (live != null || identical(data, first0));
            final lines = _whyLines(
              sheet,
              current,
              personal: personal,
              serverSentence: serverSentence,
            );
            final off = p != null && p.available && !enabled;
            return Column(
              key: Key('shop-why-${section.key}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: Text('•  ', style: theme.textTheme.bodyLarge),
                        ),
                        Expanded(
                          child: Text(line, style: theme.textTheme.bodyLarge),
                        ),
                      ],
                    ),
                  ),
                if (off)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        sheet.tr(_offLine()),
                        key: const Key('shop-why-off'),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                Text(
                  sheet.tr(_roleLine()),
                  key: const Key('shop-why-role'),
                  style: theme.textTheme.bodyMedium,
                ),
                if (showSwitch) ...[
                  const SizedBox(height: FFTokens.spacingMd),
                  ShopPersonalisedSwitch(
                    // Keyed: lines appearing above it must not rebuild it
                    // from its first value (QA #1).
                    key: const ValueKey('shop-why-switch'),
                    source: ShopPreferences.sourceWhySheet,
                    mode: mode.wire,
                    initial: first!.enabled,
                    partnerHint: mode != ShopHomeMode.member,
                    // Slice 4: a trainer's or owner's own age/gender, once
                    // the server lists them.
                    partnerUses: partner ? profileUses : null,
                    // Phase 2 S3: near-you can be used, so the hint names
                    // the current area too.
                    // Not while off (QA #9).
                    areaHint: data?.nearYou?.available == true && enabled,
                    onChanged: (prefs) {
                      if (partner) _partnerPrefs.value = prefs;
                      setSheet(() => on = prefs.personalised);
                      // The home reloads behind the sheet (§8.2).
                      if (mounted) reload();
                    },
                  ),
                  // Phase 2 S3: the location line, while near-you can be
                  // used and the switch is on.
                  if (data?.nearYou?.available == true && enabled) ...[
                    const SizedBox(height: FFTokens.spacingSm),
                    ShopNearYouLine(
                      key: ValueKey('near-${data?.nearYou?.areaId}'),
                      inHome: true,
                      serverArea: _serverArea(lang),
                    ),
                  ],
                  if (partner) ...[
                    // Slice 4: no date of birth → only purchases are used.
                    ShopPartnerDobHint(
                      mode: mode.wire,
                      profileSignals:
                          _partnerPrefs.value?.profileSignals ?? false,
                      onSaved: () {
                        if (!mounted) return;
                        reload();
                        unawaited(_loadPartnerPrefs(mode));
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: ShopFocusRing(
                          onPhoto: true,
                          builder: (node) => FFButton(
                            key: const Key('shop-why-partner-privacy'),
                            focusNode: node,
                            label: sheet.tr('shop.why.privacyLink'),
                            variant: FFButtonVariant.ghost,
                            visualDensity: VisualDensity.standard,
                            onPressed: () {
                              Navigator.of(sheet).pop();
                              if (mounted) {
                                _openPartnerPrivacy(mode, enabled);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (mode == ShopHomeMode.member)
                    Padding(
                      padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: ShopFocusRing(
                          onPhoto: true,
                          builder: (node) => FFButton(
                            key: const Key('shop-why-privacy'),
                            focusNode: node,
                            label: sheet.tr('shop.why.privacyLink'),
                            variant: FFButtonVariant.ghost,
                            visualDensity: VisualDensity.standard,
                            onPressed: () {
                              Navigator.of(sheet).pop();
                              // Pushed, so Back returns to the shop.
                              if (mounted) {
                                context.push(AppRoutes.memberPrivacy);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// The area the last answer was built for, with its name in [lang].
  ({String id, String name})? _serverArea(String lang) {
    final near = _data?.nearYou;
    final id = near?.areaId;
    final name = near?.areaName?.of(lang) ?? '';
    return id == null || name.isEmpty ? null : (id: id, name: name);
  }

  /// The server's title; without one, the app's own `shop.section.<key>`,
  /// and a plain "Products" for a key the app does not know.
  String _title(BuildContext context, ShopHomeSection section, String lang) {
    final server = section.title?.of(lang);
    if (server != null && server.isNotEmpty) return server;
    final key = 'shop.section.${section.key}';
    final own = context.tr(key);
    return own == key ? context.tr('shop.section.generic') : own;
  }

  Widget _padded(Widget child) => Padding(
    padding: EdgeInsets.symmetric(horizontal: widget.gutter),
    child: child,
  );

  bool? _reportedContent;

  void _reportContent(bool has) {
    if (widget.onHasContent == null || _reportedContent == has) return;
    _reportedContent = has;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onHasContent?.call(has);
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final children = <Widget>[_padded(_searchRow(context))];
    // Live banners (Phase 2 S1) take slot 3; the brand band is then not in
    // the tree (PH §32.5 rule 4). No banners: exactly today's layout.
    // Image addresses are root-relative on the API server.
    final base = AppScope.of(context).api.baseUrl;
    final banners = widget.onBanner == null
        ? const <ShopBanner>[]
        : [
            for (final b in data?.banners ?? const <ShopBanner>[])
              b.withImageBase(base),
          ];
    // The static brand band (spec §32.5): slot 3, after the search row and
    // after the offline alert (the alert is about the content and must not
    // sit under a photo).
    final band = banners.isNotEmpty
        ? _padded(
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
              child: ShopBannerCarousel(
                banners: banners,
                onOpen: widget.onBanner!,
                initialIndex: widget.bannerIndex,
                onIndexChanged: widget.onBannerIndex,
              ),
            ),
          )
        : widget.showHero && photoHeroUi
        ? _padded(
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
              child: FFHeroBand(
                key: const Key('shop-hero'),
                photo: FFHeroPhoto.shop,
                headingFocusNode: widget.heroFocusNode,
                minHeight: 160,
                // Search sits above the band, so the full clear photo on
                // every phone: the FitFlex Africa sign stays above the
                // text (owner 2026-10-22).
                clearPhoto: shopBandClearPhoto,
                clearPhotoEverywhere: true,
                wideHeight: 200,
                eyebrow: context.tr('member.shopTitle'),
                headlineLead: context.tr('hero.shop.lead'),
                headlineAccent: context.tr('hero.shop.accent'),
              ),
            ),
          )
        // Banners on but none live for this role, and no band (owner and
        // trainer shops; member with PHOTO_HERO_UI off): the navy fallback
        // slide (S1-AC-15). Not while the shop is still getting ready.
        : widget.onBanner != null &&
              data != null &&
              data.bannersOn &&
              data.allProductsCount != 0
        ? _padded(
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
              child: ShopFallbackSlide(onBrowseAll: widget.onBrowseAll),
            ),
          )
        : null;
    if (data == null && _loading) {
      _reportContent(false);
      children.addAll([?band, _padded(const _ShopHomeSkeleton())]);
    } else if (data == null) {
      _reportContent(false);
      children.addAll([?band, _padded(_errorState(context))]);
    } else {
      if (_error != null) {
        children.add(
          _padded(
            Padding(
              padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
              child: FFAlert(
                key: const Key('shop-home-offline-bar'),
                message: context.tr(
                  isNetworkError(_error!)
                      ? 'offline.banner'
                      : 'shop.home.errorTitle',
                ),
              ),
            ),
          ),
        );
      }
      children.addAll([?band, ..._content(context, data)]);
    }
    return Column(
      key: const Key('shop-home'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _searchRow(BuildContext context) {
    final count = widget.cart.itemCount;
    final cartLabel = count == 0
        ? context.tr('shop.home.cart')
        : count == 1
        ? context.tr('shop.home.cartCountOne')
        : context.tr('shop.home.cartCount').replaceAll('{n}', '$count');
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      child: Row(
        children: [
          Expanded(
            child: FFTextField(
              key: const Key('shop-home-search'),
              hint: context.tr('shop.searchHint'),
              prefixIcon: const Icon(Icons.search, size: 20),
              textInputAction: TextInputAction.search,
              onFieldSubmitted: (value) {
                if (value.trim().isEmpty) return;
                // The text itself is never sent: only that a search happened.
                _event('search_submitted');
                widget.onSearch(value.trim());
              },
            ),
          ),
          const SizedBox(width: FFTokens.spacingSm),
          ShopFocusRing(
            shape: BoxShape.circle,
            builder: (node) => IconButton(
              key: const Key('shop-home-cart'),
              focusNode: node,
              style: shopIconButtonStyle(),
              tooltip: cartLabel,
              onPressed: () {
                if (widget.cart.isEmpty) {
                  FFSnack.info(context, context.tr('shop.home.cartEmpty'));
                } else {
                  widget.onCheckout();
                }
              },
              icon: Badge(
                isLabelVisible: count > 0,
                label: Text('$count'),
                child: const Icon(Icons.shopping_cart_outlined),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState(BuildContext context) {
    final offline = _error != null && isNetworkError(_error!);
    return FFErrorState(
      key: Key(offline ? 'shop-home-offline' : 'shop-home-error'),
      icon: offline ? Icons.wifi_off : Icons.error_outline,
      title: context.tr(
        offline ? 'shop.home.offlineTitle' : 'shop.home.errorTitle',
      ),
      message: context.tr(
        offline ? 'shop.home.offlineBody' : 'shop.home.errorBody',
      ),
      onRetry: reload,
    );
  }

  Widget _gettingReady(BuildContext context) => _padded(
    FFEmptyState(
      key: const Key('shop-home-empty'),
      icon: Icons.storefront_outlined,
      title: context.tr('shop.home.emptyTitle'),
      body: context.tr('shop.home.emptyBody'),
    ),
  );

  Widget _card(ShopProduct product, String section, int i, double width) =>
      _ImpressionOnce(
        key: ValueKey('$section/${product.id}'),
        onShown: () => _event(
          'product_impression',
          section: section,
          productId: product.id,
          position: i,
          once: 'impression:$section:${product.id}',
        ),
        child: ShopProductCard(
          product: product,
          width: width,
          qty: widget.cart.qtyOf(product.id),
          placement: kShopHomePlacement,
          onOpen: () {
            _event(
              'product_clicked',
              section: section,
              productId: product.id,
              position: i,
            );
            widget.onOpen(product);
          },
          onAdd: () => _add(product, section, i),
        ),
      );

  List<Widget> _content(BuildContext context, ShopHomeData data) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final products = <String, ShopProduct>{
      for (final e in data.products.entries)
        e.key: ShopProduct.fromJson({'id': e.key, ...e.value}),
    };
    final sections = [
      for (final section in data.sections)
        (
          section,
          [
            for (final id in section.productIds)
              if (products[id] != null) products[id]!,
          ],
        ),
    ].where((entry) => entry.$2.isNotEmpty).toList();

    // No sections: the categories and an "All products" grid (spec §8.5),
    // from the products sent, else today's product list.
    List<ShopProduct>? grid;
    if (sections.isEmpty) {
      // The server's count says the shop is empty: no list to fetch.
      if (data.allProductsCount == 0) {
        _reportContent(false);
        return [_gettingReady(context)];
      }
      grid = products.isNotEmpty ? products.values.toList() : widget.catalogue;
      if (grid == null && !widget.catalogueFailed && !_askedCatalogue) {
        _askedCatalogue = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => widget.onNeedCatalogue?.call(),
        );
      }
      if (grid != null && grid.isEmpty) {
        _reportContent(false);
        return [_gettingReady(context)];
      }
    }
    // Rails, or the All products grid once its list is in.
    _reportContent(sections.isNotEmpty || grid != null);

    final categories = data.categories.isNotEmpty
        ? data.categories
        : [
            for (final c in ProductCategories.current)
              ShopHomeCategory(key: c.key, label: ShopText(c.en, c.sw)),
          ];
    final width = shopRailCardWidth(context);
    // Phase 2 S4: the flash sale rail heads the rails, whatever the order.
    sections.sort(
      (a, b) =>
          (b.$1.key == 'flash_sale' ? 1 : 0) -
          (a.$1.key == 'flash_sale' ? 1 : 0),
    );
    final rails = <Widget>[
      for (final (section, items) in sections)
        ShopProductRail(
          key: Key('shop-home-section-${section.key}'),
          sectionKey: section.key,
          icon: shopSectionIcon(section.key, personalised: data.personalised),
          title: _title(context, section, lang),
          inset: widget.gutter,
          subtitle: section.key == 'flash_sale' && section.endsAt != null
              ? Padding(
                  padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
                  child: FFCountdown(
                    key: const Key('shop-flash-countdown'),
                    endsAt: section.endsAt!,
                    serverOffset: ShopClock.offset,
                    now: ShopClock.deviceNow,
                    chipsLabel: context.tr('shop.home.endsIn'),
                    onEnded: _saleEnded,
                  ),
                )
              : null,
          onShown: () => _event(
            'section_viewed',
            section: section.key,
            once: 'section:${section.key}',
          ),
          onWhy: section.hasWhy ? () => _showWhy(section) : null,
          onViewAll: !section.showViewAll
              ? null
              : () {
                  _event('filter_applied', section: section.key);
                  widget.onViewAll(section.viewAll);
                },
          children: [
            for (var i = 0; i < items.length; i++)
              _card(items[i], section.key, i, width),
          ],
        ),
    ];
    // Phase 2 S3: the near-you slot (after Recommended, before Essentials).
    final slot = _nearYouSlot(context, data, width);
    if (slot != null && sections.isNotEmpty) {
      final keys = [for (final (s, _) in sections) s.key];
      final essentials = keys.indexOf('essentials');
      final recommended = keys.indexOf('recommended');
      final at = essentials >= 0
          ? essentials
          : recommended >= 0
          ? recommended + 1
          : rails.length;
      rails.insert(at, slot);
    }
    return [
      ShopCategoryRow(
        categories: categories,
        inset: widget.gutter,
        onSelected: (key) {
          _event('filter_applied');
          widget.onCategory(key);
        },
      ),
      const SizedBox(height: FFTokens.spacingMd),
      ...rails,
      if (sections.isEmpty) _padded(_allProducts(context, grid)),
      _padded(
        Align(
          child: FFButton(
            key: const Key('shop-home-browse-all'),
            label: context.tr('shop.home.browseAll'),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: widget.onBrowseAll,
          ),
        ),
      ),
    ];
  }

  /// What sits in the near-you slot: the invite card before the person has
  /// answered, card shapes while the area is worked out, else nothing (the
  /// rail itself is a server section). Only while the server says near-you
  /// can be used for this person.
  Widget? _nearYouSlot(BuildContext context, ShopHomeData data, double width) {
    if (data.nearYou?.available != true) return null;
    if (data.sections.any((s) => s.key == 'popular_near_you')) return null;
    if (_locating) return _padded(ShopNearYouSkeleton(cardWidth: width));
    if (_near.choice != ShopNearYouChoice.notAsked) return null;
    return _padded(
      ShopNearYouInviteCard(
        offline: _error != null && isNetworkError(_error!),
        onUse: _useLocation,
        onNotNow: () => ShopNearYouFlow.notNow(context),
      ),
    );
  }

  /// "Use my location" on the invite card: the rationale sheet first, then
  /// (only if needed) the OS prompt. The new area reloads the home through
  /// the store's listener.
  Future<void> _useLocation() async {
    final state = await ShopNearYouFlow.turnOn(
      context,
      onLocating: () {
        if (mounted) setState(() => _locating = true);
      },
    );
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (state != null) _near = state;
    });
  }

  /// "All products": a 2–4 column grid of the same cards.
  Widget _allProducts(BuildContext context, List<ShopProduct>? products) {
    final theme = Theme.of(context);
    final Widget body;
    if (products == null && widget.catalogueFailed) {
      body = FFErrorState(
        key: const Key('shop-home-grid-error'),
        title: context.tr('shop.home.errorTitle'),
        message: context.tr('shop.home.errorBody'),
        onRetry: widget.onNeedCatalogue,
      );
    } else if (products == null) {
      body = Semantics(
        label: context.tr('shop.home.loading'),
        child: const ExcludeSemantics(child: FFSkeletonList(count: 2)),
      );
    } else {
      body = LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth;
          final columns = available < 560
              ? 2
              : available < 900
              ? 3
              : 4;
          final width = (available - 12 * (columns - 1)) / columns;
          return Wrap(
            key: const Key('shop-home-grid'),
            spacing: 12,
            runSpacing: FFTokens.spacingMd,
            children: [
              for (var i = 0; i < products.length; i++)
                _card(products[i], 'all_products', i, width),
            ],
          );
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                header: true,
                child: Text(
                  context.tr('shop.home.allProducts'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          body,
        ],
      ),
    );
  }
}

/// Calls [onShown] once, when first built.
class _ImpressionOnce extends StatefulWidget {
  const _ImpressionOnce({
    super.key,
    required this.onShown,
    required this.child,
  });
  final VoidCallback onShown;
  final Widget child;

  @override
  State<_ImpressionOnce> createState() => _ImpressionOnceState();
}

class _ImpressionOnceState extends State<_ImpressionOnce> {
  @override
  void initState() {
    super.initState();
    widget.onShown();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Category circles and two rails of card shapes, announced once as
/// "Loading the shop" (one semantics node; the shapes are hidden).
class _ShopHomeSkeleton extends StatelessWidget {
  const _ShopHomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final width = shopRailCardWidth(context);
    Widget rail() => Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FFSkeleton(width: 140, height: 18),
          const SizedBox(height: FFTokens.spacingMd),
          ClipRect(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    SizedBox(
                      width: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FFSkeleton(
                            width: width,
                            height: width,
                            radius: FFTokens.radiusMd,
                          ),
                          const SizedBox(height: FFTokens.spacingSm),
                          const FFSkeletonLine(),
                          const SizedBox(height: FFTokens.spacingXs),
                          const FFSkeletonLine(widthFactor: 0.5),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      key: const Key('shop-home-loading'),
      container: true,
      liveRegion: true,
      label: context.tr('shop.home.loading'),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRect(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  children: [
                    for (var i = 0; i < 5; i++)
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Column(
                          children: [
                            FFSkeleton(width: 64, height: 64, radius: 32),
                            SizedBox(height: 6),
                            FFSkeleton(width: 40, height: 10),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: FFTokens.spacingLg),
            rail(),
            rail(),
          ],
        ),
      ),
    );
  }
}
