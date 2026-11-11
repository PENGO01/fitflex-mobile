import 'package:flutter/painting.dart';

/// Proposed tokens for the light system (see
/// `docs/design/light-system/README.md`).
///
/// Nothing imports this file yet. It exists so the proposal has one reviewed
/// source of values; the migration plan in the README moves them into
/// `FFTokens` and the two `ThemeData` builders slice by slice.
abstract final class FFNext {
  // Light mode.
  static const Color ground = Color(0xFFF1F3EE); // page
  static const Color card = Color(0xFFFFFFFF);
  static const Color line = Color(0xFFE3E7E0); // hairlines only
  static const Color ink = Color(0xFF0E2A22); // text, primary fill
  static const Color inkMuted = Color(0xFF5B6B64); // secondary text

  /// Same value as `FFTokens.volt`. A fill only; text on it is [ink].
  static const Color volt = Color(0xFFC8F04A);

  // Dark mode.
  static const Color darkGround = Color(0xFF090A0A);
  static const Color darkCard = Color(0xFF151716);
  static const Color darkRaised = Color(0xFF1F2221); // chips, image tiles
  static const Color darkLine = Color(0xFF2A2E2C);
  static const Color darkText = Color(0xFFF4F5F2);
  static const Color darkTextMuted = Color(0xFFA3ABA6);

  // Status chips: background and text, the same in both modes.
  static const Color pendingBg = Color(0xFFFCEFD6);
  static const Color pendingText = Color(0xFF9A4A00);
  static const Color failedBg = Color(0xFFFBE4E1);
  static const Color failedText = Color(0xFFB3261E);
  static const Color reviewBg = Color(0xFFE2ECFA);
  static const Color reviewText = Color(0xFF2858A0);
  static const Color doneBg = Color(0xFFE9ECEA);
  static const Color doneText = Color(0xFF4A5852);

  // Shape.
  static const double radiusCard = 20;
  static const double radiusHero = 24;
  static const double radiusSheet = 36; // top corners of the welcome sheet
  static const double radiusPill = 999; // every button and chip

  // Controls.
  static const double buttonHeight = 56;
  static const double chipHeight = 38;
  static const double iconButton = 44;

  /// Proposed UI family (SIL Open Font License). Not bundled yet.
  static const String fontSans = 'Onest';
}
