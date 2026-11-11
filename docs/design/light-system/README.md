# FitFlex light system

A new look for the app, in light and dark, from Godliving (design).

This branch applies it through the shared theme and components, so every
screen picks it up: colours, buttons, chips, cards, tabs, badges, alerts,
inputs, sheets and the bottom bar. No screen's behaviour, text or navigation
changes. Brand assets and the token reference sit beside this file.

The full set of drawn screens (12 screens, light and dark) is on a design
canvas that Godliving can share.

## The idea in five rules

1. **Light first, dark as a true twin.** A sage page with white cards in
   light mode; a near-black page with charcoal cards in dark mode. Same
   layout, same components.
2. **One lime card per screen.** Volt lime is a fill, never a text colour.
   The lime card is the most important thing on the screen: the pass for a
   member, today's number for a trainer, gym owner or seller.
3. **Everything you can press is a pill.** Buttons, chips and tabs use a full
   radius. Cards use 20 (hero cards 24). No card borders, no shadows.
4. **One typeface, sentence case.** Onest at 400, 500, 600 and 700. No
   all-caps headlines and no mono face in the UI.
5. **Real photos, black and white.** People and gyms in black and white,
   products in colour. No generated images.

## Tokens

Values live in `FFTokens` (`lib/shared/design_tokens.dart`) and the two
theme builders there.

| Role | Light | Dark |
| --- | --- | --- |
| Page ground | `#F1F3EE` | `#090A0A` |
| Card | `#FFFFFF` | `#151716` |
| Raised (chips, image tiles) | `#F1F3EE` on a card | `#1F2221` |
| Hairline | `#E3E7E0` | `#2A2E2C` |
| Text | `#0E2A22` | `#F4F5F2` |
| Secondary text | `#5B6B64` | `#A3ABA6` |
| Primary action fill | `#0E2A22`, white text | `#C8F04A`, `#0E2A22` text |
| Lime card | `#C8F04A`, `#0E2A22` text | the same |

Status chips are the same in both modes:

| State | Background | Text |
| --- | --- | --- |
| Active, valid, paid | `#C8F04A` | `#0E2A22` |
| Pending | `#FCEFD6` | `#9A4A00` |
| Failed | `#FBE4E1` | `#B3261E` |
| Under review, new | `#E2ECFA` | `#2858A0` |
| Expired, done | `#E9ECEA` | `#4A5852` |

Contrast, computed with the WCAG 2 formula:

| Pair | Ratio |
| --- | --- |
| Text on page, light (`#0E2A22` on `#F1F3EE`) | 13.7:1 |
| Secondary text on page, light (`#5B6B64` on `#F1F3EE`) | 5.0:1 |
| Text on lime (`#0E2A22` on `#C8F04A`) | 11.7:1 |
| Text on page, dark (`#F4F5F2` on `#090A0A`) | 18.1:1 |
| Secondary text on card, dark (`#A3ABA6` on `#151716`) | 7.7:1 |
| Status chips, lowest pair (failed) | 5.4:1 |

Lime text on a light surface fails contrast, which is why lime is a fill only.

## Type

| Use | Size / weight |
| --- | --- |
| Hero number | 56 / 700, letter-spacing -0.04em |
| Screen title | 26 to 28 / 700 |
| Card title | 16 to 17 / 600 |
| Body | 15 / 400, line height 22 |
| Secondary | 13 / 400 |
| Bottom bar label | 11 / 500, 700 when selected |

Onest is under the SIL Open Font License. It is not bundled by this pull
request; today the app ships Inter.

## Components

Most of these already exist in `lib/shared/components/`. The proposal
restyles them; it does not ask for a second set.

| Design name | Existing widget | Change |
| --- | --- | --- |
| Pill button | `FFButton` | Full radius. Primary is ink in light and lime in dark. Height 56. |
| Chip, status chip | `FFFilterChip`, `FFPill`, `FFBadge` | Full radius, height 38 (filter) or 26 (status). Selected filter is the primary fill. Status uses the five pairs above. |
| Card | `FFCard` | Radius 20, no border, no shadow, white on sage. |
| Stat tile | `FFStatTile`, `FFMetricCard` | Label 13, number 30 to 40. |
| Segmented tabs | `FFSegmented` | White pill track, primary-fill thumb. |
| Screen header | `FFPageHeader` | Solid page colour, never transparent over scrolling content. Round 44 icon buttons. |
| List row | (rows inside `FFCard`) | 54 high, hairline between rows, grouped in one card. |
| Bar chart | `FFBarChart` | Raised-colour bars, lime for the highlighted ones. |
| Empty and error states | `FFEmptyState`, `FFErrorState` | Unchanged in structure; take the new colours. |
| Pass card | new | The lime card: status chip, plan name, large visits number, check-in pill, Africa motif. |
| Offer carousel | new | Welcome screen. One slide per role (member, trainer, gym owner, seller), advances every 4 seconds, stops for reduced motion, dots are tappable. |
| Bottom bar | member, trainer, owner and vendor shells | Five slots with a raised round centre action: check in (member), new session (trainer), scan member (owner), add product (seller). |
| Photo footer | `FFPhotoFooter` | Not used. Keep `PHOTO_FOOTER_UI` off: a "Back to top" band reads as a website. A screen ends when its content ends. |

## Africa motif

`assets/africa-*.svg`: the continent as a dot grid, a larger dot on every
capital, Tanzania filled in, Dar es Salaam ringed. Built from Natural Earth
data (public domain). Three variants: `light` for sage and white, `lime` for
the pass card, `dark` for black and for photos.

Use it upright and whole, centred where it is the subject (welcome, loading),
and at most once per screen. When FitFlex opens in another country, that
country is filled in.

## Logo

`assets/wordmark-*.svg`: "Fit" followed by "Flex" on a lime chip. The chip
with a single "F" is the browser icon (`favicon.svg`); a white "F" beside it
on ink is the proposed app icon (`app-icon.svg`). Letters are outlined, so no
font is needed. On the loading screen the chip slides in behind "Flex".

The proposal retires the runner-in-pin mark. The app icon is a proposal and
is not wired into the Android or iOS projects here.

## Screens drawn

Member: loading, welcome, home, check in, gyms, trainers, activity, events
and runs, shop, profile. Partner roles: a "Today" screen each for trainer,
gym owner and seller. All in both modes.

Not drawn yet: the inner screens for each partner role, gym detail, checkout,
and empty and error states.

## What this branch changes

| Area | Where | Change |
| --- | --- | --- |
| Colours, both themes | `buildTheme()`, `buildDarkTheme()`, `FFTokens` | The values in the tables above. `onSurfaceVariant` is now set, so secondary text is muted in both themes. |
| Status colours | `FFToneTheme` | New light and dark palettes; no visible outline. |
| Buttons | button themes, `FFButton` | Pills, semibold sentence-case labels. Heights unchanged (40, 48, 52). |
| Cards | `cardTheme`, `FFCard` | Radius 20, no border. |
| Chips | `chipTheme`, `FFFilterChip` | Pills; selected is the primary fill (solid) or Volt (tint). |
| Tabs | `FFSegmented` | Solid primary thumb on a pill track. |
| Tiles, empty and error states | `FFStatTile`, `FFMetricCard`, `FFActionTile`, `FFEmptyState`, `FFErrorState` | No outlines; round icon wells. |
| Bottom bar | `navigationBarTheme` | Selected tab in a Volt pill, label bold. |
| Inputs | `inputDecorationTheme` | Radius 16; borders still >= 3:1. |
| Sheets and dialogs | sheet and dialog themes | Page colour with a 28 top radius, so cards inside keep their edges. |
| Member pass | `PassSummaryCard` | The Volt card while the pass is active; warning states keep the normal card. |
| Splash | `kinetic_splash.dart` | Near-black with Volt instead of navy and teal. |

Not changed: the Inter typeface, button heights, screen layouts, the photo
heroes and footer (still behind their flags, still off), the app icon.

Next steps, each its own pull request:

1. Screen layouts: per-screen arrangement from the design canvas (lead with
   the lime card, grouped list rows, solid headers).
2. Type: bundle Onest and switch `FFTokens.fontSans`; check Swahili strings.
3. Photos: licensed black-and-white photos, one `LICENSES.md` row each.
4. Brand: wordmark on the loading screen, new app icon.

## Review helpers

- `test/design_screens_test.dart` boots each role from the recorded fixtures
  in light and dark and saves a picture of every tab. It is skipped unless
  run with `--dart-define=DESIGN_SHOTS=true --update-goldens`.
- `.github/workflows/design-check.yml` runs analyze, the full suite and the
  screenshots on the fork. It is a review helper and should be dropped
  before merging.

## Open questions for review

- The app's first-run theme is dark (`ThemeNotifier`). The design is light
  first; should new installs start in light?
- Is retiring Inter for Onest acceptable this close to launch?
- The light theme's brand green (`brand500`, `#067647`) is replaced by ink
  (`#0E2A22`) as the primary fill. Anything in the portal that must stay in
  step?
- Dark mode moves from navy (`#020617`) to near-black (`#090A0A`).

## Verification

Prepared without a local Flutter toolchain. `flutter analyze`, the full
`flutter test` suite and the screenshots run in GitHub Actions on the fork
(`design-check.yml`).
