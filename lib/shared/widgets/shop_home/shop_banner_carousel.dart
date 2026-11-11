import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../components/components.dart';
import '../../design_tokens.dart';
import '../../i18n.dart';
import '../../shop_home.dart';
import 'shop_focus_ring.dart';
import 'shop_product_rail.dart' show shopIconButtonStyle;

/// Wide screens get the arrows inside the photo's edges (P1 §6.2).
const double kShopBannerWide = 1024;

/// The Shop home's hero carousel (Phase 2 S1; docs/design/shop-home.md §6.3,
/// §11 and shop-home-phase2.md §5.1): the live banners for this role, in the
/// server's order, each drawn with [FFPhotoHero] over its network photo.
///
/// Every slide is as tall as the tallest, its text at the bottom over the
/// scrim. No auto-advance. Swipe, the Previous / Next buttons (48dp; inside
/// the photo's edges on wide screens, under it on phones) or, on phones, a
/// screen reader's increase / decrease change the slide; the page dots sit
/// on the photo, bottom right (pointer only: the slide's label says
/// "Banner 1 of 3"). A vendor's banner shows "From {vendor}" top-left; it is
/// never labelled "Sponsored". With reduced motion the slides change without
/// a fade.
class ShopBannerCarousel extends StatefulWidget {
  const ShopBannerCarousel({
    super.key,
    required this.banners,
    required this.onOpen,
    this.initialIndex = 0,
    this.onIndexChanged,
  });

  final List<ShopBanner> banners;

  /// The slide's button was tapped: open its target.
  final ValueChanged<ShopBanner> onOpen;

  /// The slide to show first (the one shown before leaving the home).
  final int initialIndex;
  final ValueChanged<int>? onIndexChanged;

  @override
  State<ShopBannerCarousel> createState() => _ShopBannerCarouselState();
}

class _ShopBannerCarouselState extends State<ShopBannerCarousel> {
  late int _index = widget.initialIndex;

  /// Dots up to this many slides; past it a "2 / 9" counter.
  static const _maxDots = 6;

  int get _count => widget.banners.length;

  @override
  void initState() {
    super.initState();
    if (_index >= _count || _index < 0) _index = 0;
  }

  @override
  void didUpdateWidget(ShopBannerCarousel old) {
    super.didUpdateWidget(old);
    if (_index >= _count) _index = math.max(0, _count - 1);
  }

  void _go(int index) {
    if (_count < 2) return;
    setState(() => _index = (index + _count) % _count);
    widget.onIndexChanged?.call(_index);
  }

  void _next() => _go(_index + 1);
  void _previous() => _go(_index - 1);

  String _text(ShopText? text, String lang) => text?.of(lang).trim() ?? '';

  String _ctaLabel(BuildContext context, ShopBanner banner, String lang) {
    final own = _text(banner.ctaLabel, lang);
    if (own.isNotEmpty) return own;
    return context.tr(switch (banner.target.type) {
      'product' => 'shop.banner.cta.viewProduct',
      'vendor_store' => 'shop.banner.cta.visitStore',
      'results' => 'shop.banner.cta.viewAll',
      _ => 'shop.banner.cta.shopNow',
    });
  }

  String _fromLabel(BuildContext context, ShopBanner banner) => context
      .tr('shop.banner.from')
      .replaceAll('{vendor}', banner.vendorName!.trim());

  /// "From {vendor}. {headline}. {subline}. Banner {n} of {total}": each
  /// part once, without a doubled full stop.
  String _slideLabel(BuildContext context, ShopBanner banner, int i) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final headline = [
      _text(banner.headlineLead, lang),
      _text(banner.headlineAccent, lang),
    ].where((s) => s.isNotEmpty).join(' ');
    return shopJoinSentences([
      if (banner.fromVendor) _fromLabel(context, banner),
      headline,
      _text(banner.subline, lang),
      context
          .tr('shop.home.bannerOf')
          .replaceAll('{n}', '${i + 1}')
          .replaceAll('{total}', '$_count'),
    ]);
  }

  /// Room kept clear above the text for the "From" chip (two lines at the
  /// current text scale, plus its 16 inset and a gap).
  double _chipReserve(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return FFTokens.spacingMd +
        2 * scaler.scale(16) +
        2 * FFTokens.spacing2xs +
        FFTokens.spacingSm;
  }

  Widget _chip(BuildContext context, ShopBanner banner, bool active) =>
      ExcludeSemantics(
        child: FFBadge(
          key: active ? Key('shop-banner-from-${banner.id}') : null,
          label: _fromLabel(context, banner),
          tone: FFBadgeTone.onPhoto,
          // Two lines at most (a long store name at 130% on a 375 phone);
          // the slide label still reads the whole name.
          maxLines: 2,
          wrap: true,
        ),
      );

  /// The dots on the photo: white (Volt in the dark theme) for this slide,
  /// white 50% for the others. Pointer only, not read out.
  Widget _dots(BuildContext context, bool active) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final on = dark ? FFTokens.volt : Colors.white;
    final off = Colors.white.withValues(alpha: 0.5);
    final Widget body = _count <= _maxDots
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _count; i++)
                InkResponse(
                  key: active ? Key('shop-banner-dot-$i') : null,
                  canRequestFocus: false,
                  radius: 22,
                  onTap: active ? () => _go(i) : null,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: AnimatedContainer(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : FFTokens.motionMedium,
                        width: i == _index ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _index ? on : off,
                          borderRadius: BorderRadius.circular(
                            FFTokens.radiusFull,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          )
        : SizedBox(
            height: 44,
            child: Center(
              child: Text(
                '${_index + 1} / $_count',
                key: active ? const Key('shop-banner-counter') : null,
                style: FFTokens.heroEyebrow(),
              ),
            ),
          );
    return ExcludeSemantics(
      child: KeyedSubtree(
        key: active ? const Key('shop-banner-dots') : null,
        child: body,
      ),
    );
  }

  /// One slide. Only the [active] one has keys, a working button and
  /// semantics; the others are laid out invisibly to reserve the height of
  /// the tallest, so changing slides never moves the page.
  Widget _slide(
    BuildContext context,
    ShopBanner banner,
    int i,
    double width, {
    required bool active,
  }) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final wide = width >= 840;
    final arrowsInside = width >= kShopBannerWide && _count > 1;
    final lead = _text(banner.headlineLead, lang);
    final accent = _text(banner.headlineAccent, lang);
    final subline = _text(banner.subline, lang);
    // Tab order on the slide: the button, then Previous, then Next (§11.3).
    final cta = FocusTraversalOrder(
      order: const NumericFocusOrder(1),
      child: ShopFocusRing(
        onPhoto: true,
        builder: (node) => FFButton(
          key: active ? Key('shop-banner-cta-${banner.id}') : null,
          focusNode: active ? node : null,
          label: _ctaLabel(context, banner, lang),
          trailingIcon: Icons.arrow_forward,
          visualDensity: VisualDensity.standard,
          maxLines: 2,
          onPressed: active ? () => widget.onOpen(banner) : null,
        ),
      ),
    );
    // The button bottom-left, the dots bottom-right on the same line when
    // they fit (else the dots go under the button).
    final actions = _count > 1
        ? SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: FFTokens.spacingXs,
              children: [cta, _dots(context, active)],
            ),
          )
        : cta;
    final chip = banner.fromVendor ? _chip(context, banner, active) : null;
    final hero = FFPhotoHero(
      networkImage: FFHeroNetworkImage(
        banner.image.pick(width, dpr) ?? '',
        focal: Alignment(banner.image.focalX, banner.image.focalY),
      ),
      variant: wide ? FFHeroVariant.panel : FFHeroVariant.band,
      rounded: wide,
      fillHeight: true,
      // Phone about 16:10 (min 200); 3:1 up to 360 on wide screens. Text at
      // large scales grows it.
      minHeight: wide ? math.min(width / 3, 360) : math.max(200, width / 1.6),
      topInset: !wide && chip != null ? _chipReserve(context) : 0,
      panelSidePad: arrowsInside ? 64 : null,
      headlineLead: lead.isEmpty ? null : lead,
      headlineAccent: accent.isEmpty ? null : accent,
      subline: subline.isEmpty ? null : subline,
      logo: wide ? chip : null,
      excludeHeadingSemantics: true,
      actions: [actions],
    );
    final body = chip == null || wide
        ? hero
        : Stack(
            fit: StackFit.passthrough,
            children: [
              hero,
              Positioned(
                left: FFTokens.spacingMd,
                top: FFTokens.spacingMd,
                right: FFTokens.spacingMd,
                child: Align(alignment: Alignment.centerLeft, child: chip),
              ),
            ],
          );
    if (!active) return body;
    // Increase / decrease for TalkBack and VoiceOver on phones. Flutter web
    // would announce such a node as a "slider"; there the Previous / Next
    // buttons do it.
    final adjustable = _count > 1 && !kIsWeb;
    return Semantics(
      key: Key('shop-banner-slide-$i'),
      container: true,
      label: _slideLabel(context, banner, i),
      onIncrease: adjustable ? _next : null,
      onDecrease: adjustable ? _previous : null,
      child: body,
    );
  }

  Widget _arrow(
    String key,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool onPhoto = false,
    double order = 0,
  }) => FocusTraversalOrder(
    order: NumericFocusOrder(order),
    child: ShopFocusRing(
      shape: BoxShape.circle,
      onPhoto: onPhoto,
      builder: (node) => IconButton(
        key: Key(key),
        focusNode: node,
        style: onPhoto
            ? shopIconButtonStyle().copyWith(
                backgroundColor: WidgetStatePropertyAll(
                  Colors.white.withValues(alpha: 0.9),
                ),
                foregroundColor: const WidgetStatePropertyAll(FFTokens.ink),
              )
            : shopIconButtonStyle(),
        tooltip: context.tr(label),
        onPressed: onTap,
        icon: Icon(icon),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    final instant = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final inside = width >= kShopBannerWide && _count > 1;
        final active = _slide(
          context,
          widget.banners[_index],
          _index,
          width,
          active: true,
        );
        Widget slides = Stack(
          children: [
            // The tallest slide sets the height (invisible, not read).
            for (var i = 0; i < _count; i++)
              Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: _slide(
                  context,
                  widget.banners[i],
                  i,
                  width,
                  active: false,
                ),
              ),
            Positioned.fill(
              child: instant
                  ? active
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeOut,
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: [...previous, ?current],
                      ),
                      child: KeyedSubtree(
                        key: ValueKey('${widget.banners[_index].id}#$_index'),
                        child: active,
                      ),
                    ),
            ),
            if (inside) ...[
              Positioned(
                left: FFTokens.spacingSm,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _arrow(
                    'shop-banner-prev',
                    Icons.chevron_left,
                    'shop.home.prevBanner',
                    _previous,
                    onPhoto: true,
                    order: 2,
                  ),
                ),
              ),
              Positioned(
                right: FFTokens.spacingSm,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _arrow(
                    'shop-banner-next',
                    Icons.chevron_right,
                    'shop.home.nextBanner',
                    _next,
                    onPhoto: true,
                    order: 3,
                  ),
                ),
              ),
            ],
          ],
        );
        // CTA → Previous → Next, whatever their place on screen.
        slides = FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: slides,
        );
        if (_count > 1) {
          slides = GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < -200) _next();
              if (v > 200) _previous();
            },
            child: slides,
          );
        }
        return Column(
          key: const Key('shop-banners'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            slides,
            // Phones: Previous / Next under the photo (keyboard and switch
            // access; the dots are on the photo).
            if (_count > 1 && !inside)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _arrow(
                      'shop-banner-prev',
                      Icons.chevron_left,
                      'shop.home.prevBanner',
                      _previous,
                    ),
                    const SizedBox(width: FFTokens.spacingLg),
                    _arrow(
                      'shop-banner-next',
                      Icons.chevron_right,
                      'shop.home.nextBanner',
                      _next,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// [parts] read as sentences: empty ones left out, each ending in one full
/// stop ("store." + "Banner 1 of 3" never reads "store.. Banner").
String shopJoinSentences(Iterable<String> parts) => parts
    .map((p) => p.trim().replaceFirst(RegExp(r'[.!?。]+$'), '').trim())
    .where((p) => p.isNotEmpty)
    .join('. ');

/// The navy slide shown when the server has banners on but none are live
/// for this role, and the page has no photo band (owner and trainer shops,
/// or member with PHOTO_HERO_UI off): P1 §6.3. No photo, no prices; its
/// button opens all products.
class ShopFallbackSlide extends StatelessWidget {
  const ShopFallbackSlide({super.key, required this.onBrowseAll});

  final VoidCallback onBrowseAll;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= 840;
        final hero = FFPhotoHero(
          // No file: the navy placeholder ground.
          networkImage: const FFHeroNetworkImage(''),
          variant: wide ? FFHeroVariant.panel : FFHeroVariant.band,
          rounded: wide,
          minHeight: wide
              ? math.min(width / 3, 360)
              : math.max(200, width / 1.6),
          headlineLead: context.tr('shop.home.fallbackLead'),
          headlineAccent: context.tr('shop.home.fallbackAccent'),
          subline: context.tr('shop.home.fallbackSub'),
          actions: [
            ShopFocusRing(
              onPhoto: true,
              builder: (node) => FFButton(
                key: const Key('shop-fallback-cta'),
                focusNode: node,
                label: context.tr('shop.home.browseAll'),
                trailingIcon: Icons.arrow_forward,
                visualDensity: VisualDensity.standard,
                maxLines: 2,
                onPressed: onBrowseAll,
              ),
            ),
          ],
        );
        return Stack(
          key: const Key('shop-fallback-slide'),
          children: [
            hero,
            // A soft brand glow, top right (decorative).
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0.9, -0.9),
                          radius: 0.9,
                          colors: [
                            FFTokens.fgBrand.withValues(alpha: 0.22),
                            FFTokens.fgBrand.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
