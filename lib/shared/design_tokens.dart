import 'package:flutter/material.dart';

import 'tone_theme.dart';

/// FitFlex design tokens — mirror `fitflex-portal/app/globals.css`.
///
/// Brand ramp: the portal ramp (brand-25…950) is canonical. 400–500 are the
/// bright "energy" greens (dark-surface accents, charts); 600+ are AA-safe with
/// white (white on brand-600 = 5.7:1).
/// Legacy mobile names are kept and now map one portal step up so existing
/// call sites keep their contrast: brand500 = portal 600, brand600 = portal
/// 700, brand700 = portal 800, brand800 = portal 900.
class FFTokens {
  FFTokens._();

  // ── Brand scale (maps to --color-brand-*) ──
  static const Color brand50 = Color(0xFFEDFDF3);
  static const Color brand100 = Color(0xFFD3FAE5);
  static const Color brand200 = Color(0xFFAAF4CF);
  static const Color brand300 = Color(0xFF75E7B3);
  static const Color brand400 = Color(0xFF3DD98E);
  // Portal-parity names for the bright greens.
  static const Color brandBright = Color(0xFF17B26A); // portal brand-500
  static const Color brand500 = Color(0xFF067647); // portal brand-600
  static const Color brand600 = Color(0xFF085D3A); // portal brand-700
  static const Color brand700 = Color(0xFF074D31); // portal brand-800
  static const Color brand800 = Color(0xFF053321); // portal brand-900

  // Legacy aliases
  static const Color brand = brand500;
  static const Color brandDark = brand700;
  static const Color brandLight = brand50;

  // ── Semantic colors ──
  static const Color accent = Color(0xFFEAAA08); // gold: fills/graphics only
  static const Color accent50 = Color(0xFFFEFDF0);
  static const Color accent700 = Color(0xFF854A0E);

  static const Color info50 = Color(0xFFEFF8FF);
  static const Color info200 = Color(0xFFB2DDFF);
  static const Color info600 = Color(0xFF1570EF);
  static const Color info700 = Color(0xFF175CD3);

  static const Color error50 = Color(0xFFFEF3F2);
  static const Color error200 = Color(0xFFFECDCA);
  static const Color error500 = Color(0xFFDC2626);
  static const Color error600 = Color(0xFFD92D20);
  static const Color error700 = Color(0xFFB42318);

  /// Error foreground on dark surfaces (>= 4.5:1 on slate-900/950).
  static const Color errorOnDark = Color(0xFFF97066);
  // DS v1.0 error: 5.8:1 on white.
  static const Color danger = Color(0xFFBA3434);

  // Success is teal-leaning so it is distinct from the brand green.
  static const Color success50 = Color(0xFFF0FDF9);
  static const Color success200 = Color(0xFF99F6E0);
  static const Color success500 = Color(0xFF0E9384);
  static const Color success600 = Color(0xFF107569);
  static const Color success700 = Color(0xFF125D56);
  static const Color success = success500;

  static const Color warning50 = Color(0xFFFFFBEB);
  static const Color warning200 = Color(0xFFFEDF89);
  static const Color warning500 = Color(0xFFF79009);
  static const Color warning700 = Color(0xFFB54708);

  // ── Foreground / text ── (dark-mode values)
  static const Color fgPrimary = Color(0xFFF4F5F2);
  static const Color fgSecondary = Color(0xFFD5DAD6);
  static const Color fgTertiary = Color(0xFFBAC1BC);
  static const Color fgQuaternary = Color(0xFFA3ABA6);
  static const Color fgDisabled = Color(0xFF5E6662);
  static const Color fgBrand = volt;

  // Legacy aliases
  static const Color text = fgPrimary;
  static const Color textMuted = fgQuaternary;

  // ── Background / surface ── (dark-mode values)
  static const Color bgPrimary = Color(0xFF090A0A);
  static const Color bgSecondary = Color(0xFF151716);
  static const Color bgTertiary = Color(0xFF1F2221);

  // Legacy aliases
  static const Color surface = bgPrimary;
  static const Color surface2 = bgSecondary;

  // Form-control boundaries, >= 3:1 against their surface (WCAG 1.4.11).
  static const Color inputBorderLight = Color(0xFF7F8A84);
  static const Color inputBorderDark = Color(0xFF6E7672);

  // ── Borders ── (dark-mode values)
  static const Color borderPrimary = Color(0xFF2A2E2C);
  static const Color borderSecondary = Color(0xFF2A2E2C);

  // Legacy alias
  static const Color border = borderSecondary;

  // ── Gray scale ── (dark-mode values)
  static const Color gray100 = Color(0xFF1F2221);
  static const Color gray200 = Color(0xFF2A2E2C);
  static const Color gray500 = Color(0xFF8A928D);
  static const Color gray700 = Color(0xFFD5DAD6);

  // ── Radii ──
  static const double radiusXs = 6;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;

  /// Hero cards (the pass) and sheet tops.
  static const double radius2xl = 24;
  static const double radiusFull = 999;

  // ── Spacing ──
  static const double spacing2xs = 2;
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 16;
  static const double spacingLg = 24;
  static const double spacingXl = 32;
  static const double spacing2xl = 48;

  // ── Icon sizes ──
  static const double iconXs = 14;
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double iconXl = 32;

  /// Standard square container that wraps a leading icon.
  static const double iconBox = 40;

  // ── Type families (bundled in assets/fonts) ──
  static const String fontSans = 'Inter';
  static const String fontMono = 'JetBrains Mono';

  /// Small section label: section eyebrows, data tags, field labels.
  /// FitFlex DS v1.0: one typeface, sentence case, no tracking. (The name is
  /// kept so existing call sites don't change.)
  static TextStyle monoLabel(Color color, {double size = 11}) => TextStyle(
    fontFamily: fontSans,
    fontSize: size + 2,
    fontWeight: FontWeight.w600,
    color: color,
  );

  // ── Motion (durations + curves) ──
  static const Duration motionFast = Duration(milliseconds: 100);
  static const Duration motionMedium = Duration(milliseconds: 200);
  static const Duration motionSlow = Duration(milliseconds: 400);
  static const Curve motionCurve = Curves.easeInOut;
  static const Curve motionEmphasized = Curves.easeOutCubic;

  // ── Shadows ──
  static List<BoxShadow> get shadowXs => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.18),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get shadowSm => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.25),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  // ── Dark mode surfaces ──
  // Light system (docs/design/light-system): a near-black page, charcoal
  // cards, a lighter "raised" step for chips and image tiles, and a hairline
  // used only between list rows.
  static const Color darkBg = Color(0xFF090A0A);
  static const Color darkSurface = Color(0xFF151716);
  static const Color darkRaised = Color(0xFF1F2221);
  static const Color darkBorder = Color(0xFF2A2E2C);

  // ── Light mode surfaces (light system) ──
  // A sage page, white cards, a raised step for chips and image tiles inside
  // cards, and forest ink for text and the primary fill.
  static const Color lightGround = Color(0xFFF3F5F0);
  static const Color lightRaised = Color(0xFFEAF0E8);
  static const Color lightLine = Color(0xFFE5EAE4);
  static const Color ink = Color(0xFF102D24); // forest (DS v1.0)

  // ── Vibrant brand green (dark-mode CTA + selection state) ──
  static const Color brandVibrant = Color(0xFF17B26A);

  // ── V2 accents (Design System V2, approved) ──
  // Volt is the member-app accent on the Pulse (dark) theme: primary CTAs,
  // selection and focus. Always pair it with [onVolt] text (15.4:1).
  static const Color volt = Color(0xFFD4EF68); // FitFlex lime (DS v1.0)
  static const Color onVolt = ink; // 11.5:1 on Volt
  // Fuel is the warm "act soon" accent (expiring passes, streak heat).
  // [fuel] for light surfaces, [fuelOnDark] for text/icons on dark.
  static const Color fuel = Color(0xFFB8452C);
  static const Color fuelOnDark = Color(0xFFFF8A6B);
  static const Color fuel50 = Color(0xFFFFF4EE);
  static const Color fuel200 = Color(0xFFFBD9CC);
  // Calm is the warm light canvas used by operator (portal) surfaces.
  static const Color calmGround = Color(0xFFF7F5F0);
  static const Color calmBorder = Color(0xFFEBE7DE);

  // ── Scannable codes ──
  // QR modules/eyes are always this fixed dark ink on white, whatever the
  // theme, so scanners get maximum contrast (never the theme primary).
  static const Color qrInk = Color(0xFF020617);
  static const Color qrBackground = Color(0xFFFFFFFF);

  // ── Map markers ──
  // Pins sit on light map tiles in both themes; forest ink is >= 13:1 on
  // white/near-white tiles. Paired with a white halo.
  static const Color mapPin = ink;
  static const Color mapPinHalo = Color(0xFFFFFFFF);

  // ── On-dark text ──
  static const Color darkFgPrimary = Color(0xFFF4F5F2); // 18.1:1 on darkBg
  static const Color darkFgSecondary = Color(0xFFD5DAD6);
  static const Color darkFgMuted = Color(0xFFA3ABA6); // 7.7:1 on darkSurface

  // ── Photo hero (docs/design/photo-hero-screens.md §3.3, §5) ──
  // The hero is an always-dark island: a photo under a slate-950 scrim with
  // light text, in both themes. Contrast is guaranteed against a pure-white
  // photo pixel, so it holds for any photo. Owner 2026-10-20 ("lighter"):
  // the scrim is local. A band behind the status bar and app bar, the photo
  // clear in between, and a ramp into a dark zone that holds all text.
  // A neutral near-black chosen so hero text keeps >= 13.2:1 over a
  // pure-white pixel at the 86% zone (13.5:1), while the 0.46 top band
  // stays the lowest value that holds 3:1 (0.45 gives 2.98:1).
  static const Color heroScrim = Color(0xFF040505);

  /// Behind the status bar, app bar icons and logo (no other text): held
  /// over the bar, then faded out. 0.46 is the lowest value that keeps
  /// [heroText] icons at 3:1 over a pure-white pixel (3.04:1).
  static const double heroScrimTop = 0.46;

  /// Where the bar band has faded to 0, as a share of the hero's height
  /// (never above the bar's bottom edge plus [heroScrimBarFade]).
  static const double heroScrimTopFade = 0.16;

  /// The bar band's fade below the bar, in logical px.
  static const double heroScrimBarFade = 32;

  /// Minimum under any text, chip or button (13.2:1 for [heroText] over
  /// pure white), from the first line of text down to the bottom edge.
  static const double heroScrimText = 0.86;

  /// The ramp up to [heroScrimText]: a soft lead-in from 0 to
  /// [heroScrimLeadIn] over [heroScrimLeadInLength] px, then the steep part
  /// from there to [heroScrimText] over the 24px above the first line of
  /// text (the text zone's top padding).
  static const double heroScrimLeadIn = 0.40;
  static const double heroScrimLeadInLength = 48;
  static const double heroScrimRampLength = spacingLg;

  /// Dark theme bottom edge: seamless into the page ground.
  static const double heroScrimGround = 1.00;

  /// Taller heroes (owner 2026-10-20, spec §5.3): on phones at least
  /// [heroTallMinViewport] tall, the clear photo between the bar band and
  /// the ramp's lead-in aims for this share of the viewport height, clamped
  /// to [heroTallClearMin] .. [heroTallClearMax] at 1.0x text (divided by
  /// the text scale above it). A page may cap the hero so its first control
  /// stays on screen; the clear photo then shrinks, never the text.
  static const double heroTallClearShare = 0.19;
  static const double heroTallClearMin = 120;
  static const double heroTallClearMax = 200;
  static const double heroTallMinViewport = 760;

  /// Band heroes (owner 2026-10-22, "too dark"): the clear photo a band
  /// keeps above its text on phones from [heroTallMinViewport] tall, at
  /// 1.0x text (divided by the text scale above it). A screen caps its band
  /// so its first control stays above [heroBandControlShare] of the screen
  /// (FFHeroBand.maxHeightAt844); the clear photo then gives way. The bar
  /// band and the scrim under the text are unchanged.
  static const double heroBandClearPhoto = 100;

  /// How far down the screen a band screen's first control may sit (its top
  /// edge, as a share of the viewport height).
  static const double heroBandControlShare = 0.55;

  /// The least clear photo a capped band grows for; with less it keeps
  /// today's height.
  static const double heroBandMinClearPhoto = 24;

  /// Horizontal (panel / wide banner) scrim: the text column's leading edge
  /// and the far edge. The text column itself stays at >= [heroScrimText].
  static const double heroScrimPanelLead = 0.92;
  static const double heroScrimPanelTail = 0.15;

  /// Photo footer (spec §33, owner 2026-10-20): the band's height is this
  /// share of the viewport height, clamped to [footerMinHeight] ..
  /// [footerMaxHeight]; larger text makes it taller still.
  static const double footerViewportShare = 0.48;
  static const double footerMinHeight = 320;
  static const double footerMaxHeight = 440;

  /// The photo the footer always keeps clear above its lockup zone.
  static const double footerClearMin = 140;

  /// The page ground fading into the footer photo at its top edge.
  static const double footerTopFade = 40;

  /// The footer lockup zone's bottom edge (top edge is [heroScrimText]).
  static const double footerScrimBottom = 0.92;

  static const Color heroText = Color(0xFFF1F5F9);

  /// Subline and body text on a hero. Never slate-400 (#94A3B8) on a hero.
  static const Color heroTextBody = Color(0xFFCBD5E1);

  /// Accent word: Volt in the dark theme; brand-500 in light (large only).
  static const Color heroAccentDark = volt;
  static const Color heroAccentLight = fgBrand;

  /// Fuel state chip on the hero. The border is 3.6:1 against the 86% zone
  /// over pure white (0.6 gave 2.9:1).
  static const Color heroChipFuelText = fuelOnDark;
  static Color get heroChipFuelBorder => fuelOnDark.withValues(alpha: 0.7);
  static Color get heroChipFuelFill => heroScrim.withValues(alpha: 0.4);

  /// Shown before the photo decodes, under high contrast and on failure.
  static const Color heroPlaceholder = Color(0xFF151716);

  /// Partner logo plate on a band (spec §40.2): 40 tall, at most 120 wide,
  /// 6px side padding, the logo inside 108 x 28.
  static const double logoPlateHeight = 40;
  static const double logoPlateMaxWidth = 120;
  static const double logoPlateMinWidth = 40;
  static const double logoPlatePad = 6;
  static const double logoPlateLogoMaxWidth = 108;
  static const double logoPlateLogoMaxHeight = 28;

  /// The focus-point crosshair (spec §42.2): a white ring and dot with a
  /// slate-950 edge, readable on any photo.
  static const Color focalRing = Color(0xFFFFFFFF);
  static const Color focalRingEdge = darkBg;

  /// The phone band keeps this much from its top edge to the top of the
  /// eyebrow while a plate shows (16 + 40 + 12).
  static const double logoPlateReserve = 68;

  /// Light plate (dark or coloured logos): white with a 12% slate-950 edge.
  static const Color logoPlateLight = Color(0xFFFFFFFF);
  static Color get logoPlateLightBorder => darkBg.withValues(alpha: 0.12);

  /// Dark plate (light or white logos): the navy ground with a 40% edge
  /// (full opacity under high contrast).
  static const Color logoPlateDark = heroPlaceholder;
  static const Color logoPlateDarkBorderStrong = Color(0xFFF1F5F9);
  static Color get logoPlateDarkBorder =>
      logoPlateDarkBorderStrong.withValues(alpha: 0.4);

  /// Light theme: the content sheet overlaps the hero by this much.
  static const double heroSheetOverlap = 24;
  static const double heroSheetRadius = radiusXl;

  /// Headline size / line height: 34/36 from 375 wide, 30/32 below.
  static const double heroDisplaySize = 34;
  static const double heroDisplayLine = 36;
  static const double heroDisplaySizeSmall = 30;
  static const double heroDisplayLineSmall = 32;

  /// Panel variant (>= 1024 wide): canon h1.
  static const double heroDisplaySizeWide = 48;
  static const double heroDisplayLineWide = 52;

  /// Hero eyebrow: uppercase mono label, tracking 0.18em.
  static TextStyle heroEyebrow({Color color = heroText}) =>
      monoLabel(color, size: 11).copyWith(letterSpacing: 11 * 0.18);

  // ── Canon role colours (photo hero role tiles, F-6) ──
  static const Color roleMemberLight = Color(0xFF1F7A3A);
  static const Color roleMemberDark = Color(0xFF17B26A);
  static const Color roleTrainer = Color(0xFF3B82F6);
  static const Color roleVendor = Color(0xFFA855F7);

  // ── Muted text on light grounds ──
  // 5.0:1 on the sage page, 5.6:1 on white.
  static const Color lightFgMuted = Color(0xFF5B6B64);

  /// Muted secondary text (struck-through prices, hints) for the current
  /// theme. Matches `colorScheme.onSurfaceVariant` in both themes.
  static Color mutedText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? darkFgMuted
      : lightFgMuted;

  // ── Role-card accent icon colors ──
  static const Color iconAccentGreen = Color(0xFF17B26A);
  static const Color accentOrange = Color(0xFFF79009);
  static const Color accentIndigo = Color(0xFF6366F1);
}

/// Keyboard focus ring for filled controls: a 2px ring drawn *outside* the
/// button so it sits on the page ground, not on the fill. Material's default
/// focus cue (a 10% overlay) is ~1.25:1 on Volt and practically invisible.
/// [color] must contrast >= 3:1 with the page ground.
WidgetStateProperty<BorderSide?> ffFocusRing(Color color) =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused) &&
          !states.contains(WidgetState.disabled)) {
        return BorderSide(
          color: color,
          width: 2,
          strokeAlign: BorderSide.strokeAlignOutside,
        );
      }
      return null;
    });

/// Focus ring colour on the dark ground (slate-100 on slate-950: 17:1).
const Color ffFocusRingDark = FFTokens.darkFgPrimary;

/// Focus ring colour on the light ground (forest ink on sage: 13.4:1).
const Color ffFocusRingLight = FFTokens.ink;

/// Shared shapes of the light system: every button and chip is a pill.
const OutlinedBorder _ffPill = StadiumBorder();

/// Button label: sentence case, semibold, no extra tracking.
const TextStyle _ffButtonLabel = TextStyle(
  fontFamily: FFTokens.fontSans,
  fontWeight: FontWeight.w600,
  fontSize: 15,
  letterSpacing: 0,
);

ThemeData buildDarkTheme() {
  const bg = FFTokens.darkBg;
  const surface = FFTokens.darkSurface;
  const raised = FFTokens.darkRaised;
  const muted = FFTokens.darkFgMuted;
  const onSurface = FFTokens.darkFgPrimary;
  const primary = FFTokens.volt;
  const bord = FFTokens.darkBorder;

  return ThemeData(
    useMaterial3: true,
    fontFamily: FFTokens.fontSans,
    brightness: Brightness.dark,
    extensions: const <ThemeExtension<dynamic>>[FFToneTheme.dark],
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      onPrimary: FFTokens.onVolt,
      secondary: primary,
      onSecondary: FFTokens.onVolt,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: muted,
      surfaceContainerHighest: raised,
      surfaceContainerLow: Color(0xFF121413),
      outlineVariant: bord,
      outline: bord,
      error: FFTokens.errorOnDark,
      onError: Colors.black,
    ),
    // ── Text ──────────────────────────────────────────────────────────────────
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 57,
        fontWeight: FontWeight.w400,
      ),
      displayMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 45,
        fontWeight: FontWeight.w400,
      ),
      displaySmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 36,
        fontWeight: FontWeight.w400,
      ),
      headlineLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 40,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
      ),
      headlineMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineSmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleSmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: FFTokens.darkFgMuted,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: FFTokens.darkFgMuted,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: FFTokens.darkFgMuted,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    ),
    // ── App bar ───────────────────────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      foregroundColor: onSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: onSurface),
    ),
    // ── Bottom navigation ─────────────────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      elevation: 0,
      height: 72,
      surfaceTintColor: Colors.transparent,
      // The selected tab sits in a Volt pill in both themes.
      indicatorColor: FFTokens.volt,
      indicatorShape: _ffPill,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: FFTokens.onVolt);
        }
        return const IconThemeData(color: muted);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontFamily: FFTokens.fontSans,
            color: onSurface,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          );
        }
        return const TextStyle(
          fontFamily: FFTokens.fontSans,
          color: muted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        );
      }),
    ),
    // ── Card ──────────────────────────────────────────────────────────────────
    // White (light) or charcoal (dark) on the page; no border, no shadow.
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      ),
    ),
    // ── Buttons ───────────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: FFTokens.onVolt,
        // Disabled sits on the card colour, never grey-on-Volt.
        disabledBackgroundColor: raised,
        disabledForegroundColor: FFTokens.darkFgMuted,
        // No colour tween: otherwise the label fades grey -> onVolt over
        // Volt for 200ms when a button becomes enabled.
        animationDuration: Duration.zero,
        shape: _ffPill,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: const TextStyle(
          fontFamily: FFTokens.fontSans,
          fontWeight: FontWeight.w600,
          fontSize: 15,
          letterSpacing: 0,
        ),
      ).copyWith(side: ffFocusRing(ffFocusRingDark)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(side: ffFocusRing(ffFocusRingDark)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(side: ffFocusRing(ffFocusRingDark)),
    ),
    // FABs default to the Volt fill; a 45% onVolt overlay gives >= 3:1
    // between the focused and unfocused fill.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      focusColor: FFTokens.onVolt.withValues(alpha: 0.45),
      shape: _ffPill,
      elevation: 2,
      highlightElevation: 4,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onSurface,
        side: const BorderSide(color: onSurface, width: 1.5),
        shape: _ffPill,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: _ffButtonLabel,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        shape: _ffPill,
        textStyle: _ffButtonLabel,
      ),
    ),
    // ── Input ─────────────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      labelStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: FFTokens.darkFgMuted,
        fontSize: 14,
      ),
      hintStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: FFTokens.darkFgMuted,
      ),
      suffixIconColor: FFTokens.darkFgMuted,
      prefixIconColor: FFTokens.darkFgMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.inputBorderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.inputBorderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.errorOnDark),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.errorOnDark, width: 2),
      ),
    ),
    // ── Misc ──────────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(color: bord, thickness: 1),
    // Tracks must contrast with cards (surfaceContainerHighest is the card
    // colour), so an empty bar still reads as a bar.
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: Color(0xFF3A3F3C),
    ),
    iconTheme: const IconThemeData(color: FFTokens.darkFgMuted),
    listTileTheme: const ListTileThemeData(
      textColor: onSurface,
      iconColor: FFTokens.darkFgMuted,
      tileColor: surface,
    ),
    // Pill chips with a hairline. Selected chips are Volt with ink text.
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: FFTokens.volt,
      side: const BorderSide(color: bord),
      shape: _ffPill,
      labelStyle: TextStyle(
        fontFamily: FFTokens.fontSans,
        fontWeight: FontWeight.w500,
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? FFTokens.onVolt
              : onSurface,
        ),
      ),
      checkmarkColor: FFTokens.onVolt,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surface,
      contentTextStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
      ),
      actionTextColor: primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    // Sheets and dialogs use the page colour, so white or charcoal cards
    // inside them keep their edges.
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: muted,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: bord),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FFTokens.radius2xl + 4),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: bord),
        borderRadius: BorderRadius.circular(FFTokens.radius2xl + 4),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: FFTokens.darkFgSecondary,
        fontSize: 14,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(FFTokens.onVolt),
      side: const BorderSide(color: bord, width: 2),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return FFTokens.onVolt;
        return FFTokens.darkFgMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return bord;
      }),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return bord;
      }),
    ),
  );
}

ThemeData buildTheme() {
  // ── Light-mode palette (light system) ──
  const bg = FFTokens.lightGround;
  const surface = Colors.white;
  const onSurface = FFTokens.ink; // 13.4:1 on the page, 14.8:1 on white
  const primary = FFTokens.ink; // primary fill: forest ink, white text
  const onPrimary = Colors.white;
  const bord = FFTokens.lightLine;
  const raised = FFTokens.lightRaised;
  const muted = FFTokens.lightFgMuted; // 5.0:1 on the page

  return ThemeData(
    useMaterial3: true,
    fontFamily: FFTokens.fontSans,
    brightness: Brightness.light,
    extensions: const <ThemeExtension<dynamic>>[FFToneTheme.light],
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.light(
      primary: primary,
      onPrimary: onPrimary,
      secondary: primary,
      onSecondary: onPrimary,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: muted,
      surfaceContainerHighest: raised,
      surfaceContainerLow: bg,
      outlineVariant: bord,
      outline: bord,
      error: FFTokens.danger,
      onError: Colors.white,
    ),
    // ── Text ──────────────────────────────────────────────────────────────────
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 57,
        fontWeight: FontWeight.w400,
      ),
      displayMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 45,
        fontWeight: FontWeight.w400,
      ),
      displaySmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 36,
        fontWeight: FontWeight.w400,
      ),
      headlineLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 40,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
      ),
      headlineMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineSmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleSmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: muted,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: muted,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: muted,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    ),
    // ── App bar ───────────────────────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      foregroundColor: onSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: onSurface),
    ),
    // ── Bottom navigation ─────────────────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      elevation: 0,
      height: 72,
      surfaceTintColor: Colors.transparent,
      // The selected tab sits in a Volt pill in both themes.
      indicatorColor: FFTokens.volt,
      indicatorShape: _ffPill,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: FFTokens.onVolt);
        }
        return const IconThemeData(color: muted);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontFamily: FFTokens.fontSans,
            color: onSurface,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          );
        }
        return const TextStyle(
          fontFamily: FFTokens.fontSans,
          color: muted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        );
      }),
    ),
    // ── Card ──────────────────────────────────────────────────────────────────
    // White (light) or charcoal (dark) on the page; no border, no shadow.
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      ),
    ),
    // ── Buttons ───────────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        disabledBackgroundColor: bord,
        disabledForegroundColor: muted,
        shape: _ffPill,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: const TextStyle(
          fontFamily: FFTokens.fontSans,
          fontWeight: FontWeight.w600,
          fontSize: 15,
          letterSpacing: 0,
          color: onPrimary,
        ),
      ).copyWith(side: ffFocusRing(ffFocusRingLight)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(side: ffFocusRing(ffFocusRingLight)),
    ),
    // Ink pill with white content; a 24% white overlay marks focus.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: onPrimary,
      focusColor: Colors.white.withValues(alpha: 0.24),
      shape: _ffPill,
      elevation: 2,
      highlightElevation: 4,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onSurface,
        side: const BorderSide(color: onSurface, width: 1.5),
        shape: _ffPill,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: _ffButtonLabel,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        shape: _ffPill,
        textStyle: _ffButtonLabel,
      ),
    ),
    // ── Input ─────────────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      labelStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: muted,
        fontSize: 14,
      ),
      hintStyle: const TextStyle(fontFamily: FFTokens.fontSans, color: muted),
      suffixIconColor: muted,
      prefixIconColor: muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.inputBorderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.inputBorderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        borderSide: const BorderSide(color: FFTokens.danger, width: 2),
      ),
    ),
    // ── Misc ──────────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(color: bord, thickness: 1),
    // Tracks must contrast with cards (surfaceContainerHighest is the card
    // colour), so an empty bar still reads as a bar.
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: Color(0xFFD3D9D0),
    ),
    iconTheme: const IconThemeData(color: muted),
    listTileTheme: const ListTileThemeData(
      textColor: onSurface,
      iconColor: muted,
      tileColor: surface,
    ),
    // Pill chips with a hairline. Selected chips are Volt with ink text.
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: FFTokens.volt,
      side: const BorderSide(color: bord),
      shape: _ffPill,
      labelStyle: TextStyle(
        fontFamily: FFTokens.fontSans,
        fontWeight: FontWeight.w500,
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? FFTokens.onVolt
              : onSurface,
        ),
      ),
      checkmarkColor: FFTokens.onVolt,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: onSurface,
      contentTextStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: Colors.white,
      ),
      actionTextColor: FFTokens.volt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    // Sheets and dialogs use the page colour, so white or charcoal cards
    // inside them keep their edges.
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: muted,
      shape: RoundedRectangleBorder(
        side: BorderSide.none,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FFTokens.radius2xl + 4),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide.none,
        borderRadius: BorderRadius.circular(FFTokens.radius2xl + 4),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: FFTokens.fontSans,
        color: muted,
        fontSize: 14,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: bord, width: 2),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return muted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return bord;
      }),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return bord;
      }),
    ),
  );
}

/// Theme for the one Volt card on a screen (the member's active pass).
///
/// The card looks the same in light and dark mode: Volt fill, forest-ink
/// text (11.5:1), muted text 7.7:1, an ink primary button with white text,
/// and status badges as ink pills. Wrap the card in
/// `Theme(data: buildVoltCardTheme(), child: ...)` and build its content
/// with the inner context.
ThemeData buildVoltCardTheme() {
  const ink = FFTokens.ink;
  const inkMuted = Color(0xFF2F4A28); // 7.7:1 on Volt
  final base = buildTheme();
  const inkPill = FFToneColors(
    bg: ink,
    fg: Colors.white,
    border: ink,
    dot: FFTokens.volt,
  );
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      surface: FFTokens.volt,
      onSurface: ink,
      onSurfaceVariant: inkMuted,
      primary: ink,
      onPrimary: Colors.white,
      outline: ink.withValues(alpha: 0.24),
      outlineVariant: ink.withValues(alpha: 0.16),
    ),
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    extensions: <ThemeExtension<dynamic>>[
      FFToneTheme.light.copyWith(
        brand: inkPill,
        success: inkPill,
        neutral: inkPill,
        gray: inkPill,
      ),
    ],
  );
}
