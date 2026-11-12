// Band and section heroes behind PHOTO_HERO_UI (owner 2026-10-22, "too
// dark"): each grows for up to 100px of clear photo above its text, as far
// as its first control can stay above 55% of the screen; the text stays on
// the >= 0.86 zone and the top band is unchanged. Shop's FitFlex Africa
// sign sits wholly above the text. PIN entry is a thin strip.
//
// Real Inter fonts are loaded so text heights match a phone.

import 'package:fitflexmobile/screens/email_auth_screen.dart';
import 'package:fitflexmobile/screens/pin_flows.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:fitflexmobile/shared/shop_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/hero_band_pages.dart';
import 'support/hero_scrim.dart';
import 'support/recording_api.dart';

/// Least clear photo per screen at 390x844 (iPhone insets, 1.0x), English
/// and Swahili; null: the screen keeps today's band (no clear photo).
const _clear390 = <String, double?>{
  'gyms': 45,
  'trainers': 77,
  'shop': 100,
  // No room: the plan cards would go past 55% (reported in the PR).
  'upgrade': null,
  'upgrade-plan': null,
  'activity': 45,
  'trainer-home': 49.9,
  'vendor-home': 83,
  'owner-home': 90,
};

/// Screens whose Swahili text leaves too little clear photo under the cap.
/// Trainer home used to be one; with Plus Jakarta Sans (DS v1.0) its
/// Swahili text fits and it gets the clear photo too.
const _swNoClear = <String>{};

const _controlShare = FFTokens.heroBandControlShare;

Finder _heroOf(BandScreen s) => find
    .descendant(
      of: find.byKey(Key(s.heroKey)),
      matching: find.byType(FFPhotoHero),
      matchRoot: true,
    )
    .first;

Future<void> _run(
  WidgetTester tester,
  BandScreen s,
  Future<void> Function(RecordingApi api) body,
) async {
  final api = RecordingApi();
  await api.run(() async {
    await body(api);
    await unmountBandScreen(tester);
  });
}

/// The shop sign in its 864x1080 crop (source px: board, then lettering).
const _signBoard = Rect.fromLTRB(265, 55, 842, 280);
const _signLetters = Rect.fromLTRB(304, 120, 788, 239);

/// [src] (crop px) drawn with BoxFit.cover and the shop's focal into [box].
Rect _inBox(Rect src, Rect box) {
  const w = 864.0, h = 1080.0;
  final scale = box.width / w > box.height / h ? box.width / w : box.height / h;
  final focal = FFHeroPhoto.shop.focal;
  final dx = (box.width - w * scale) / 2 * (1 + focal.x);
  final dy = (box.height - h * scale) / 2 * (1 + focal.y);
  return Rect.fromLTRB(
    box.left + dx + src.left * scale,
    box.top + dy + src.top * scale,
    box.left + dx + src.right * scale,
    box.top + dy + src.bottom * scale,
  );
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    debugPhotoHeroUiOverride = true;
    debugShopHomeV2Override = true;
  });
  tearDown(() {
    debugPhotoHeroUiOverride = null;
    debugShopHomeV2Override = null;
  });

  group('rules', () {
    test('heroBandClear: from 760 tall, divided by the text scale', () {
      expect(heroBandClear(100, viewportHeight: 844, textScale: 1), 100);
      expect(heroBandClear(100, viewportHeight: 759, textScale: 1), 0);
      expect(heroBandClear(100, viewportHeight: 844, textScale: 2), 50);
      expect(
        heroBandClear(100, viewportHeight: 640, textScale: 2, everywhere: true),
        100,
      );
      expect(heroBandClear(0, viewportHeight: 844, textScale: 1), 0);
    });

    test('heroBandMaxHeight moves with the viewport at 55%', () {
      expect(heroBandMaxHeight(321, 844), 321);
      expect(heroBandMaxHeight(321, 932), closeTo(321 + 0.55 * 88, 1e-9));
      expect(heroBandMaxHeight(double.infinity, 700), double.infinity);
      // A 59px status bar (430x932) puts the band 12px lower.
      expect(
        heroBandMaxHeight(321, 932, statusBar: 59),
        closeTo(321 + 0.55 * 88 - 12, 1e-9),
      );
      // Android's 24px bar: room for 23px more.
      expect(heroBandMaxHeight(321, 844, statusBar: 24), 344);
    });

    test('heroTallFade: below minClearPhoto the hero keeps today', () {
      // A band (no bar) whose cap leaves ~14px of clear photo.
      final f = heroTallFade(
        text: 332,
        topInset: 0,
        barHosted: false,
        clearPhoto: 100,
        maxHeight: 469,
        minClearPhoto: 24,
      );
      expect(f, 0);
      final g = heroTallFade(
        text: 332,
        topInset: 0,
        barHosted: false,
        clearPhoto: 100,
        maxHeight: 469,
      );
      expect(g, closeTo(469 - 332, 1e-9));
    });
  });

  group('390x844: clear photo above the text, first control above 55%', () {
    for (final s in bandScreens) {
      for (final lang in ['en', 'sw']) {
        for (final dark in [true, false]) {
          final tag = '$s $lang ${dark ? 'dark' : 'light'}';
          testWidgets(tag, (tester) async {
            await _run(tester, s, (api) async {
              await pumpBandScreen(tester, api, s, lang: lang, dark: dark);
              final hero = _heroOf(s);
              final clear = heroClearPhoto(tester, hero: hero).clear;
              final want = lang == 'sw' && _swNoClear.contains(s.name)
                  ? null
                  : _clear390[s.name];
              if (want == null) {
                expect(clear, 0, reason: tag);
              } else {
                expect(clear, greaterThanOrEqualTo(want), reason: tag);
                expect(clear, lessThanOrEqualTo(100.01), reason: tag);
              }
              final control = tester.getRect(s.controlFinder(lang));
              // Upgrade plan's first option was at 468 (55.5%) before this
              // change; its band is unchanged.
              final limit = s.name == 'upgrade-plan'
                  ? 468.01
                  : 844 * _controlShare + 0.01;
              expect(control.top, lessThanOrEqualTo(limit), reason: tag);
              expect(control.bottom, lessThanOrEqualTo(844), reason: tag);
              expectHeroScrimRule(tester, hero: hero);
              expect(tester.takeException(), isNull);
            });
          });
        }
      }
    }
  });

  group('430x932: at least as much clear photo, control above 55%', () {
    for (final s in bandScreens) {
      testWidgets('$s', (tester) async {
        await _run(tester, s, (api) async {
          await pumpBandScreen(tester, api, s, phone: bandP430, dark: true);
          final hero = _heroOf(s);
          final clear = heroClearPhoto(tester, hero: hero).clear;
          final want = _clear390[s.name];
          if (want == null) {
            expect(clear, 0);
          } else {
            expect(clear, greaterThanOrEqualTo(want));
            expect(clear, lessThanOrEqualTo(100.01));
          }
          if (s.name != 'upgrade-plan') {
            expect(
              tester.getRect(s.controlFinder('en')).top,
              lessThanOrEqualTo(932 * _controlShare + 0.01),
            );
          }
          expectHeroScrimRule(tester, hero: hero);
          expect(tester.takeException(), isNull);
        });
      });
    }
  });

  group('under 760 tall: today\'s bands (Shop keeps its clear photo)', () {
    for (final phone in [bandP360, bandP700]) {
      for (final s in bandScreens) {
        testWidgets('$phone $s', (tester) async {
          await _run(tester, s, (api) async {
            await pumpBandScreen(tester, api, s, phone: phone, lang: 'sw');
            final hero = _heroOf(s);
            final clear = heroClearPhoto(tester, hero: hero).clear;
            if (s.name == 'shop') {
              expect(clear, closeTo(100, 0.01));
            } else {
              expect(clear, 0);
            }
            expectHeroScrimRule(tester, hero: hero);
            expect(tester.takeException(), isNull);
          });
        });
      }
    }
  });

  group('Shop: the FitFlex Africa sign wholly above the text', () {
    test('crop and focal', () {
      expect(FFHeroPhoto.shop.focal, Alignment.topCenter);
      expect(FFHeroPhoto.shop.aspect, closeTo(864 / 1080, 1e-9));
    });

    for (final (phone, scale) in [
      (bandP390, 1.0),
      (bandP430, 1.0),
      (bandP360, 1.0),
      (bandP390, 1.3),
    ]) {
      testWidgets('$phone ${scale}x', (tester) async {
        final s = bandScreen('shop');
        await _run(tester, s, (api) async {
          await pumpBandScreen(
            tester,
            api,
            s,
            phone: phone,
            dark: true,
            textScale: scale,
          );
          final hero = _heroOf(s);
          final box = tester.getRect(hero);
          final c = heroClearPhoto(tester, hero: hero);
          final board = _inBox(_signBoard, box);
          final letters = _inBox(_signLetters, box);
          final text = tester.getRect(
            find.descendant(
              of: hero,
              matching: find.byKey(const Key('ff-hero-text-zone')),
            ),
          );
          // Whole sign inside the band, above where the scrim to the text
          // starts (no ramp, no text on it).
          expect(board.left, greaterThanOrEqualTo(box.left));
          expect(board.right, lessThanOrEqualTo(box.right));
          expect(board.top, greaterThanOrEqualTo(box.top));
          expect(board.bottom, lessThanOrEqualTo(c.rampStart));
          expect(board.bottom, lessThan(text.top));
          // The lettering's middle line is in the clear photo (no scrim).
          expect(letters.center.dy, greaterThanOrEqualTo(c.bandEnd));
          expect(letters.bottom, lessThanOrEqualTo(c.rampStart));
        });
      });
    }
  });

  group('PIN entry: thin strip', () {
    const entry = EmailAuthScreen(
      initialEmail: 'qa@example.test',
      initialMode: EmailAuthMode.signIn,
    );
    final pin = BandScreen(
      'pin',
      heroKey: 'pin-hero',
      control: '',
      build: () => entry,
      chrome: BandChrome.own,
    );

    Finder key(String label) => find
        .ancestor(
          of: find.descendant(
            of: find.byType(CustomKeypad),
            matching: find.text(label),
          ),
          matching: find.byType(Material),
        )
        .first;

    test('constants', () {
      expect(pinStripFraction, 0);
      expect(pinHeroClearPhoto, 0);
    });

    for (final phone in [bandP390, bandP430]) {
      for (final lang in ['en', 'sw']) {
        for (final dark in [true, false]) {
          testWidgets('$phone $lang ${dark ? 'dark' : 'light'}: no clear '
              'photo, dots and keys up', (tester) async {
            await _run(tester, pin, (api) async {
              await pumpBandScreen(
                tester,
                api,
                pin,
                phone: phone,
                lang: lang,
                dark: dark,
              );
              final hero = find.byType(FFPhotoHero);
              expect(heroClearPhoto(tester).clear, 0);
              // The hero's photo zone is just the bar: the text starts
              // under it.
              final zone = tester.getRect(
                find.descendant(
                  of: hero,
                  matching: find.byKey(const Key('ff-hero-text-zone')),
                ),
              );
              expect(zone.top, closeTo(phone.top + kToolbarHeight, 0.01));
              final dots = tester.getRect(find.byType(PinInputRow));
              // Before (release-candidate): dots at 342 / 403, key 1 at
              // 426 / 487 (390x844 / 430x932, dark, English).
              final (dotsBefore, keyBefore) = phone == bandP390
                  ? (342.0, 426.0)
                  : (403.0, 487.0);
              expect(dots.top, lessThanOrEqualTo(dotsBefore - 75));
              expect(
                tester.getRect(key('1')).top,
                lessThanOrEqualTo(keyBefore - 75),
              );
              for (final l in ['1', '0', 'OK']) {
                final r = tester.getRect(key(l));
                expect(r.height, greaterThanOrEqualTo(44));
                expect(r.bottom, lessThanOrEqualTo(phone.height));
              }
              expectHeroScrimRule(tester);
              expect(tester.takeException(), isNull);
            });
          });
        }
      }
    }
  });

  group('flag off: no hero on any band screen', () {
    setUp(() => debugPhotoHeroUiOverride = false);
    for (final s in bandScreens) {
      testWidgets('$s', (tester) async {
        await _run(tester, s, (api) async {
          await pumpBandScreen(tester, api, s);
          expect(find.byType(FFPhotoHero), findsNothing);
          expect(find.byKey(Key(s.heroKey)), findsNothing);
        });
      });
    }
  });
}
