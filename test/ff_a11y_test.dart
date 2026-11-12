import 'package:fitflexmobile/main.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ff_harness.dart';

/// Real Inter metrics (the default test font has very wide glyphs, so nothing
/// would "fit" and the segmented control would always scroll).
Future<void> _loadInter() async {
  final loader = FontLoader(FFTokens.fontSans)
    ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-400.ttf'))
    ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-700.ttf'));
  await loader.load();
}

void main() {
  testWidgets('app clamps system text scale to 1.3', (t) async {
    SharedPreferences.setMockInitialValues({});
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final api = ApiClient(baseUrl: 'http://localhost:0');
    final auth = AuthState(api);
    await auth.hydrate();
    await t.pumpWidget(
      FitFlexApp(
        api: api,
        auth: auth,
        locale: FFLocale(),
        themeNotifier: ThemeNotifier(),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 500));
    }
    final ctx = t.element(find.byType(Scaffold).first);
    expect(MediaQuery.textScalerOf(ctx).scale(10), closeTo(13, 0.01));
    // Below the cap it is left alone.
    t.platformDispatcher.textScaleFactorTestValue = 1.1;
    await t.pump();
    final ctx2 = t.element(find.byType(Scaffold).first);
    expect(MediaQuery.textScalerOf(ctx2).scale(10), closeTo(11, 0.01));
  });

  group('tap targets', () {
    testWidgets('FFPill with onTap is >= 48dp and reports button semantics', (
      t,
    ) async {
      var taps = 0;
      await pumpFF(t, FFPill(label: 'all_gyms', onTap: () => taps++));
      final size = t.getSize(find.byType(FFPill));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
      await t.tap(find.byType(FFPill));
      expect(taps, 1);
      expect(find.byType(InkWell), findsOneWidget);
      expect(find.bySemanticsLabel('all gyms'), findsOneWidget);
    });

    testWidgets('FFPill without onTap stays small', (t) async {
      await pumpFF(t, const FFPill(label: 'Gold'));
      expect(t.getSize(find.byType(FFPill)).height, lessThan(40));
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('FFSegmented options are >= 48dp and tappable', (t) async {
      String value = 'a';
      await pumpFF(
        t,
        StatefulBuilder(
          builder: (c, set) => FFSegmented(
            value: value,
            options: const [('a', 'One'), ('b', 'Two')],
            onChanged: (v) => set(() => value = v),
          ),
        ),
        width: 300,
      );
      for (final o in ['One', 'Two']) {
        final inkwell = find.ancestor(
          of: find.text(o),
          matching: find.byType(InkWell),
        );
        expect(t.getSize(inkwell).height, greaterThanOrEqualTo(48));
      }
      await t.tap(find.text('Two'));
      await t.pump();
      expect(value, 'b');
    });

    testWidgets('FFSegmented wraps long labels at spaces at 1.3x scale', (
      t,
    ) async {
      await pumpFF(
        t,
        FFSegmented(
          value: 'a',
          options: const [
            ('a', 'Wanachama wote wa gym'),
            ('b', 'Walio na malipo yaliyochelewa'),
          ],
          onChanged: (_) {},
        ),
        width: 300,
        textScale: 1.3,
      );
      expect(t.takeException(), isNull);
      expect(find.byType(FittedBox), findsNothing);
    });

    testWidgets(
      'FFSegmented tightens before it scrolls: Swahili labels fit at phone width',
      (t) async {
        await _loadInter();
        await pumpFF(
          t,
          FFSegmented(
            value: 'leo',
            options: const [
              ('leo', 'Leo'),
              ('past', 'Mazoezi'),
              ('ch', 'Challenges'),
              ('prog', 'Maendeleo'),
            ],
            onChanged: (_) {},
          ),
          width: 327,
          lang: 'sw',
        );
        expect(t.takeException(), isNull);
        // Everything is visible at once: no scroller, no wrapped word.
        expect(
          find.descendant(
            of: find.byType(FFSegmented),
            matching: find.byType(SingleChildScrollView),
          ),
          findsNothing,
        );
        for (final label in ['Challenges', 'Maendeleo']) {
          expect(t.getSize(find.text(label)).height, lessThan(26));
        }
      },
    );

    testWidgets(
      'FFSegmented scrolls instead of breaking a word at large text scale',
      (t) async {
        await _loadInter();
        String value = 'leo';
        await pumpFF(
          t,
          StatefulBuilder(
            builder: (c, set) => FFSegmented(
              value: value,
              options: const [
                ('leo', 'Leo'),
                ('past', 'Mazoezi'),
                ('ch', 'Challenges'),
                ('prog', 'Maendeleo'),
              ],
              onChanged: (v) => set(() => value = v),
            ),
          ),
          width: 327,
          lang: 'sw',
          textScale: 1.3,
        );
        expect(t.takeException(), isNull);
        expect(
          find.descendant(
            of: find.byType(FFSegmented),
            matching: find.byType(SingleChildScrollView),
          ),
          findsOneWidget,
        );
        for (final label in ['Challenges', 'Maendeleo']) {
          expect(t.getSize(find.text(label)).height, lessThan(34));
        }
        await t.tap(find.text('Leo'));
        await t.pump();
        expect(value, 'leo');
      },
    );

    testWidgets('FFSegmented keeps equal segments when every word fits', (
      t,
    ) async {
      await _loadInter();
      await pumpFF(
        t,
        FFSegmented(
          value: 'a',
          options: const [('a', 'Bidhaa'), ('b', 'Oda zangu')],
          onChanged: (_) {},
        ),
        width: 327,
        lang: 'sw',
      );
      expect(
        find.descendant(
          of: find.byType(FFSegmented),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
    });
  });

  group('FFBadge', () {
    testWidgets('long label does not overflow 120px at 1.3x scale', (t) async {
      await pumpFF(
        t,
        const FFBadge(
          label: 'Inasubiri idhini ya msimamizi wa mfumo',
          dot: true,
        ),
        width: 120,
        textScale: 1.3,
      );
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(FFBadge)).width, lessThanOrEqualTo(120));
    });
  });

  group('semantics', () {
    testWidgets('section title and page header are headers', (t) async {
      final h = t.ensureSemantics();
      await pumpFF(
        t,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FFSectionTitle('Plans'),
            FFPageHeader(title: 'Gyms'),
          ],
        ),
      );
      for (final label in ['Plans', 'Gyms']) {
        expect(
          t.getSemantics(find.text(label)),
          matchesSemantics(label: label, isHeader: true),
        );
      }
      h.dispose();
    });

    testWidgets('ThemeToggleButton tooltip names the choice', (t) async {
      await t.pumpWidget(
        ThemeScope(
          notifier: ThemeNotifier(),
          child: FFLocaleScope(
            notifier: FFLocale()..set(const Locale('sw')),
            child: const MaterialApp(home: Scaffold(body: ThemeToggleButton())),
          ),
        ),
      );
      expect(find.byTooltip('Mandhari: Giza'), findsOneWidget);
    });
  });
}
