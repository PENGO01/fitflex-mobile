// Design System V2 QA fixes: fixed QR ink, map pin colour, Volt-only
// primaries in the dark theme, visible keyboard focus on Volt controls.

import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/tone_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Future<void> _pump(WidgetTester t, ThemeData theme, Widget child) =>
    t.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  group('FFQrCode', () {
    for (final entry in {
      'dark': buildDarkTheme(),
      'light': buildTheme(),
    }.entries) {
      testWidgets('${entry.key} theme: dark ink on white', (t) async {
        await _pump(t, entry.value, const FFQrCode(data: 'tok', size: 200));
        final qr = t.widget<QrImageView>(find.byType(QrImageView));
        expect(qr.eyeStyle.color, FFTokens.qrInk);
        expect(qr.dataModuleStyle.color, FFTokens.qrInk);
        expect(qr.backgroundColor, FFTokens.qrBackground);
      });
    }

    test('QR ink contrast on white is at least 15:1', () {
      expect(
        _contrast(FFTokens.qrInk, FFTokens.qrBackground),
        greaterThanOrEqualTo(15),
      );
    });
  });

  test('map pin is >= 3:1 on light map tiles', () {
    // OSM land tiles are near-white / light beige.
    for (final tile in const [Color(0xFFFFFFFF), Color(0xFFF2EFE9)]) {
      expect(_contrast(FFTokens.mapPin, tile), greaterThanOrEqualTo(3));
    }
  });

  group('dark theme uses Volt, not emerald, as its brand colour', () {
    test('brand tone follows Volt', () {
      final brand = FFToneTheme.dark.brand;
      expect(brand.dot, FFTokens.volt);
      expect(brand.fg, FFTokens.volt);
      expect(brand.dot, isNot(FFTokens.brandVibrant));
      expect(_contrast(brand.fg, brand.bg), greaterThanOrEqualTo(4.5));
    });

    test('controls on Volt use onVolt, not pure black', () {
      final theme = buildDarkTheme();
      expect(theme.colorScheme.onSecondary, FFTokens.onVolt);
      expect(
        theme.filledButtonTheme.style!.foregroundColor!.resolve({}),
        FFTokens.onVolt,
      );
      expect(
        theme.checkboxTheme.checkColor!.resolve({WidgetState.selected}),
        FFTokens.onVolt,
      );
      expect(
        theme.switchTheme.thumbColor!.resolve({WidgetState.selected}),
        FFTokens.onVolt,
      );
    });

    test('disabled filled buttons never sit on Volt', () {
      final style = buildDarkTheme().filledButtonTheme.style!;
      expect(
        style.backgroundColor!.resolve({WidgetState.disabled}),
        isNot(FFTokens.volt),
      );
      expect(style.animationDuration, Duration.zero);
    });
  });

  group('keyboard focus on filled buttons', () {
    for (final entry in {
      'dark': (buildDarkTheme(), FFTokens.darkBg),
      'light': (buildTheme(), FFTokens.lightGround),
    }.entries) {
      test('${entry.key}: 2px outside ring, >= 3:1 on the ground', () {
        final (theme, ground) = entry.value;
        final side = theme.filledButtonTheme.style!.side!;
        expect(side.resolve({}), isNull);
        final ring = side.resolve({WidgetState.focused})!;
        expect(ring.width, 2);
        expect(ring.strokeAlign, BorderSide.strokeAlignOutside);
        expect(_contrast(ring.color, ground), greaterThanOrEqualTo(3));
        expect(
          side.resolve({WidgetState.focused, WidgetState.disabled}),
          isNull,
        );
        expect(
          theme.elevatedButtonTheme.style!.side!.resolve({WidgetState.focused}),
          isNotNull,
        );
      });
    }

    testWidgets('a focused FFButton draws the ring (dark theme)', (t) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await _pump(
        t,
        buildDarkTheme(),
        Focus(
          focusNode: focus,
          child: FFButton(label: 'Go', onPressed: () {}),
        ),
      );
      // Move focus into the button itself.
      focus.requestFocus();
      await t.pump();
      FocusManager.instance.primaryFocus!.nextFocus();
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      await t.pumpAndSettle();
      final material = t.widget<Material>(
        find
            .descendant(
              of: find.byType(FilledButton),
              matching: find.byType(Material),
            )
            .first,
      );
      final shape = material.shape! as OutlinedBorder;
      expect(shape.side.width, 2);
      expect(shape.side.color, ffFocusRingDark);
    });
  });
}
