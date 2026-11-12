import 'package:flutter/material.dart';

/// Colours for one semantic tone (badge, alert, trend chip, ...).
@immutable
class FFToneColors {
  const FFToneColors({
    required this.bg,
    required this.fg,
    required this.border,
    required this.dot,
  });

  final Color bg;
  final Color fg;
  final Color border;
  final Color dot;

  static FFToneColors lerp(FFToneColors a, FFToneColors b, double t) =>
      FFToneColors(
        bg: Color.lerp(a.bg, b.bg, t)!,
        fg: Color.lerp(a.fg, b.fg, t)!,
        border: Color.lerp(a.border, b.border, t)!,
        dot: Color.lerp(a.dot, b.dot, t)!,
      );
}

/// Theme-aware tone palette. Light mode uses soft tints with dark text; dark
/// mode uses the tone blended at ~16% over the charcoal card with light text.
/// Every fg/bg pair is >= 4.5:1.
///
/// Read with `FFToneTheme.of(context)`; falls back to the palette for the
/// current brightness when the extension is not installed (bare MaterialApp).
@immutable
class FFToneTheme extends ThemeExtension<FFToneTheme> {
  const FFToneTheme({
    required this.neutral,
    required this.gray,
    required this.brand,
    required this.success,
    required this.danger,
    required this.warning,
    required this.info,
  });

  final FFToneColors neutral;
  final FFToneColors gray;
  final FFToneColors brand;
  final FFToneColors success;
  final FFToneColors danger;
  final FFToneColors warning;
  final FFToneColors info;

  // FitFlex DS v1.0 badge colours: soft fills with no visible outline
  // (border = bg). Every fg/bg pair is >= 5.4:1.
  static const light = FFToneTheme(
    neutral: FFToneColors(
      bg: Color(0xFFEAF0E8),
      fg: Color(0xFF53645A),
      border: Color(0xFFEAF0E8),
      dot: Color(0xFF87938C),
    ),
    gray: FFToneColors(
      bg: Color(0xFFEAF0E8),
      fg: Color(0xFF3A4642),
      border: Color(0xFFEAF0E8),
      dot: Color(0xFF68766F),
    ),
    // "Active", "valid", "paid": the lime badge with forest text (11.5:1).
    brand: FFToneColors(
      bg: Color(0xFFD4EF68),
      fg: Color(0xFF102D24),
      border: Color(0xFFD4EF68),
      dot: Color(0xFF102D24),
    ),
    success: FFToneColors(
      bg: Color(0xFFE4F2E9),
      fg: Color(0xFF1B6542),
      border: Color(0xFFE4F2E9),
      dot: Color(0xFF237A50),
    ),
    danger: FFToneColors(
      bg: Color(0xFFFCE8E7),
      fg: Color(0xFFA52828),
      border: Color(0xFFFCE8E7),
      dot: Color(0xFFBA3434),
    ),
    warning: FFToneColors(
      bg: Color(0xFFFFF2D6),
      fg: Color(0xFF815000),
      border: Color(0xFFFFF2D6),
      dot: Color(0xFF9A6500),
    ),
    info: FFToneColors(
      bg: Color(0xFFE7F0FF),
      fg: Color(0xFF245B91),
      border: Color(0xFFE7F0FF),
      dot: Color(0xFF3275B8),
    ),
  );

  // Dark: the tone at 16% over the charcoal card, light text, no outline.
  // Every fg/bg pair is >= 7.9:1.
  static const dark = FFToneTheme(
    neutral: FFToneColors(
      bg: Color(0xFF2C2F2D),
      fg: Color(0xFFD5DAD6),
      border: Color(0xFF2C2F2D),
      dot: Color(0xFFA3ABA6),
    ),
    gray: FFToneColors(
      bg: Color(0xFF1F2221),
      fg: Color(0xFFD5DAD6),
      border: Color(0xFF1F2221),
      dot: Color(0xFF8A928D),
    ),
    // Volt family: the dark theme's primary is Volt.
    brand: FFToneColors(
      bg: Color(0xFF343A23),
      fg: Color(0xFFD4EF68),
      border: Color(0xFF343A23),
      dot: Color(0xFFD4EF68),
    ),
    success: FFToneColors(
      bg: Color(0xFF1C3024),
      fg: Color(0xFF8EE0A8),
      border: Color(0xFF1C3024),
      dot: Color(0xFF3FB56B),
    ),
    danger: FFToneColors(
      bg: Color(0xFF381E1B),
      fg: Color(0xFFFDA29B),
      border: Color(0xFF381E1B),
      dot: Color(0xFFF97066),
    ),
    warning: FFToneColors(
      bg: Color(0xFF392A14),
      fg: Color(0xFFFEC84B),
      border: Color(0xFF392A14),
      dot: Color(0xFFF79009),
    ),
    info: FFToneColors(
      bg: Color(0xFF192A3A),
      fg: Color(0xFF84CAFF),
      border: Color(0xFF192A3A),
      dot: Color(0xFF2E90FA),
    ),
  );

  static FFToneTheme of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<FFToneTheme>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  FFToneTheme copyWith({
    FFToneColors? neutral,
    FFToneColors? gray,
    FFToneColors? brand,
    FFToneColors? success,
    FFToneColors? danger,
    FFToneColors? warning,
    FFToneColors? info,
  }) => FFToneTheme(
    neutral: neutral ?? this.neutral,
    gray: gray ?? this.gray,
    brand: brand ?? this.brand,
    success: success ?? this.success,
    danger: danger ?? this.danger,
    warning: warning ?? this.warning,
    info: info ?? this.info,
  );

  @override
  FFToneTheme lerp(ThemeExtension<FFToneTheme>? other, double t) {
    if (other is! FFToneTheme) return this;
    return FFToneTheme(
      neutral: FFToneColors.lerp(neutral, other.neutral, t),
      gray: FFToneColors.lerp(gray, other.gray, t),
      brand: FFToneColors.lerp(brand, other.brand, t),
      success: FFToneColors.lerp(success, other.success, t),
      danger: FFToneColors.lerp(danger, other.danger, t),
      warning: FFToneColors.lerp(warning, other.warning, t),
      info: FFToneColors.lerp(info, other.info, t),
    );
  }
}
