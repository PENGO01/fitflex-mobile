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
| Page ground | `#F3F5F0` | `#090A0A` |
| Card | `#FFFFFF` | `#151716` |
| Raised (chips, image tiles) | `#EAF0E8` | `#1F2221` |
| Hairline | `#E5EAE4` | `#2A2E2C` |
| Text | `#102D24` | `#F4F5F2` |
| Secondary text | `#5B6B64` | `#A3ABA6` |
| Primary action fill | `#102D24`, white text | `#D4EF68`, `#102D24` text |
| Lime card | `#D4EF68`, `#102D24` text | the same |

Status chips are the same in both modes:

| State | Background | Text |
| --- | --- | --- |
| Active, valid, paid | `#D4EF68` | `#102D24` |
| Pending | `#FCEFD6` | `#9A4A00` |
| Failed | `#FBE4E1` | `#B3261E` |
| Under review, new | `#E2ECFA` | `#2858A0` |
| Expired, done | `#E9ECEA` | `#4A5852` |

Contrast, computed with the WCAG 2 formula:

| Pair | Ratio |
| --- | --- |
| Text on page, light (`#102D24` on `#F3F5F0`) | 13.7:1 |
| Secondary text on page, light (`#5B6B64` on `#F3F5F0`) | 5.0:1 |
| Text on lime (`#102D24` on `#D4EF68`) | 11.7:1 |
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

## FitFlex DS v1.0 values

Colours follow Godliving's FitFlex Design System v1.0 (lime `#D4EF68`,
forest `#102D24`, page `#F3F5F0`, border `#E5EAE4`, badge palette, error
`#BA3434`), with three deliberate departures where the spec's own values fail
its accessibility rules:

| Spec value | Problem | Used instead |
| --- | --- | --- |
| Secondary text `#68766F` | 4.3:1 on `#F3F5F0` (needs 4.5:1) | `#5B6B64`, 5.0:1 |
| Input border `#C8D1C9` | 1.6:1 on white (needs 3:1) | `#7F8A84`, 3.6:1 |
| Lime progress fill on `#E5EAE4` track | 1.05:1, the bar disappears | Forest fill in light, lime in dark |

Buttons stay pills (as in the DS v1.0 board) rather than the 16px radius in
its text. Inputs use 12px, cards 20px, the pass 24px.

## Member bottom bar

Home, Activity, a raised round **Check in** action in the centre (forest with
a lime QR icon; lime with a forest icon in dark), Gyms, Shop. Check in opens
the existing QR screen (`/member/qr`). Profile moves to a round avatar button
in the app bar (`member-nav-profile`). On Profile and the check-in screen no
tab is highlighted.

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

Not changed: the Inter typeface, button heights, screen layouts other than
the member bottom bar, the photo heroes and footer (still behind their flags,
still off), the app icon.

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
  (`#102D24`) as the primary fill. Anything in the portal that must stay in
  step?
- Dark mode moves from navy (`#020617`) to near-black (`#090A0A`).

## Verification

Prepared without a local Flutter toolchain. `flutter analyze`, the full
`flutter test` suite and the screenshots run in GitHub Actions on the fork
(`design-check.yml`).

## P.S. for Nassor: code suggestions from design review (16 Nov)

These are suggestions from the design side. Nassor decides the implementation.

Levels: **[HIGH]** fix before release, **[MID]** next pass, **[LOW]** when convenient.

### Design canvases (member app)

All are private until Godliving shares them. Ask him for access if a link doesn't open.

| Canvas | Link |
|---|---|
| Design system | https://claude.ai/artifact/KV5NWBb2RdVKMozBsg92v1 |
| Member Start | https://claude.ai/artifact/BBRu4byqgEv6s36ffQW4bk |
| Member Home | https://claude.ai/artifact/DQDTpqdT4hS5x84eubCA8T |
| Check in & Activity | https://claude.ai/artifact/MTEwovMJCTMsHXWG7vpfDR |
| Gyms, Shop & Profile | https://claude.ai/artifact/AuYRLWLU5HuG6VswEx4sTo |
| Pass & Payment | https://claude.ai/artifact/FCLumfd8qrzCfzTyuTJwhx |
| Trainers, Inbox & Help | https://claude.ai/artifact/LR8WzGj69Ya5mwdBzZU2Wa |

### What the data has today

| Need | Today | Status |
|---|---|---|
| Gender | `MemberProfile.gender` (`/me` > `memberProfile.gender`, nullable) | Exists |
| Preferred language | Not on `/me`. App locale lives in `FFLocale`; `locale` is only sent on auth/OTP calls | App-side only. NEW if it must follow the member across devices |
| Weekly workout goal (days) | `fitnessGoal` / `fitnessGoals` are goal *types* (strings), not a day count. `preferredWorkoutTimes` is times | NEW |
| Pass tier / plan | `Subscription.tier`, `Subscription.plan`, `Subscription.type` | Exists |
| Member since | `MemberSummary.createdAt` | Exists |
| Preferences object | None | NEW |
| Sponsor / employer | `myWellnessBenefits()` (`GET /b2b/me/benefits`) has the data, but Home keeps only the `sponsoredGymAccess` boolean | Exists server-side, not kept |
| Error code | `ApiException.code` (`body.error` or `body.failure`) | Exists |
| Request id / reference | Nothing in `ApiException` or the client headers | NEW (server) |

### a. Greeting engine [MID]

Replace "Good morning, <name>" (`member.goodMorning`) with a small, warm greeting picker.

- Inputs: language (`en` / `sw`), time of day, first name, gender (only if set), pass tier, streak.
- Name: first word of `displayName` only. Never email, phone or publicId (see bug list).
- Data: all existing, except a member "vibe" setting (NEW, see b).

| Kiswahili | English |
|---|---|
| Mambo vipi, Amina? | Look who's back, Amina |
| Niaje Amina, tayari kupiga tizi? | Morning, champ. Ready to move? |
| Habari za asubuhi, Amina | Hey Amina, the gym missed you |
| Vipi mkuu, leo tunapiga tizi? | Day 5 of your streak. Keep it rolling |
| Siku ya 5 mfululizo, endelea hivyo! | Evening, Amina. One more for today? |
| Jioni njema Amina, tumalizie kwa nguvu? | Pro mode on, Amina |

Rules

- Rotate from a pool keyed by language + time of day + context (streak, tier).
- Never show the same line twice in a row (keep the last id in local storage).
- No gendered words when gender is unknown. Use the neutral pool. Never infer gender from the name.
- No age-based forms ("Shikamoo"): age respect can't be known safely.
- Humour off in bad states: expired, suspended, payment failed, errors. Use the plain greeting.
- Respect the member's vibe: Off gives "Habari za asubuhi, Amina" / "Good morning, Amina".

```dart
String greet(GreetCtx c) {
  final pool = greetings[c.lang]!
      .where((g) => g.fits(c))            // time, streak, tier, vibe
      .where((g) => c.gender != null || g.neutral)
      .where((g) => !c.badState || g.plain)
      .where((g) => g.id != c.lastId)
      .toList();
  return pool[Random().nextInt(pool.length)].text(c.firstName);
}
```

### b. Replace "Ready to train?" with a daily line [MID]

A rotating one-liner: motivation, a life lesson or a short reminder. Original lines or public-domain methali only. No copyrighted quotes.

| # | Kiswahili | English |
|---|---|---|
| 1 | Haba na haba hujaza kibaba. | Little by little fills the measure. |
| 2 | Mtaka cha mvunguni sharti ainame. | Want what's under the bed? You have to bend. |
| 3 | Bandu bandu huisha gogo. | Chip by chip, the log is done. |
| 4 | Usipoziba ufa utajenga ukuta. | Fix the crack now, or rebuild the wall later. |
| 5 | Dakika 20 leo ni bora kuliko saa mbili kesho. | 20 minutes today beats two hours someday. |
| 6 | Kunywa maji kabla hujaanza. | Drink some water before you start. |
| 7 | Mwili wako unakumbuka kila hatua. | Your body remembers every rep. |
| 8 | Kupumzika nako ni mazoezi. | Rest is part of the plan too. |

- Pick one per day (seeded by date) so it doesn't flicker on refresh.
- NEW member preference **Vibe**: `coach` (push), `calm` (gentle), `funny`, `off`. Default `calm`. It filters both a and b.
- Data: NEW `preferences.vibe` on `/me` (no preferences object exists today). Local storage is fine for a first version.

### c. Active days goal [MID]

- A weekly goal (days per week, 1 to 7) drives a small progress bar on Home's "This week" card: "3 of 4 days".
- No goal set: a quiet "Set a goal" text button in the card. No nagging.
- Data: NEW `memberProfile.weeklyGoalDays` (int, nullable). `fitnessGoals` are goal types, so don't reuse them.

### d. Visits this month in local time [LOW]

- Count visits with `m.at.toLocal()`, same as the week strip. Today it uses UTC, so visits after 21:00 EAT on the last day of a month land in the wrong month.

```dart
final now = DateTime.now();
final visits = moments.where((m) {
  final t = m.at.toLocal();
  return t.year == now.year && t.month == now.month;
}).length;
```

- Data: existing `checkInMoments`.

### e. Nearest gyms carousel [MID]

- Home shows 3 to 6 nearest gyms as a horizontal scroll of square cards (photo, name, area, distance).
- Sort by `gymDisplayDistanceKm()`; drop gyms without coordinates to the end.
- No location permission: show popular gyms, titled "Popular gyms", no distance.
- Data: existing `listGyms()` + `Gym.latitude/longitude` + `coverThumbnail`. "Popular" needs a NEW sort (e.g. visit count) from the server; until then use backend order.

### f. Payment pending refresh [HIGH]

- Add "Check again" on the pending card (S6, S10) that re-checks the payment and shows "Last checked 9:40".
- Endpoint exists: `refreshMobileMoney(paymentRequestId)` > `POST /me/payments/{id}/mobile-money/refresh`, `state`: `in_progress | completed | failed | held | none`. Then reload `/me` on `completed`.
- Disable the button for ~10 s after a tap. Store the last-checked time locally.

### g. Error friend [HIGH]

Every error answers three things: what happened, what to do, where to check.

| Level | When | Shows |
|---|---|---|
| Low | Nothing lost, retry works (list failed to load) | One line + Retry |
| Mid | Action failed (check-in, booking) | What happened + what to do + link (Payments, Inbox) |
| High | Money or access at stake (payment, suspended) | Mid + reference code + time: "Ref FX-7K2Q · 16 Nov 09:40" |

- Data: `ApiException.code` exists for "what happened". A request id does not exist: NEW, ideally the server returns `requestId` in error bodies (or an `X-Request-Id` header) so support can find it. Until then, show code + time only.

### h. Home bugs found in review

| Level | Bug | Where / fix |
|---|---|---|
| **[HIGH]** | Pass card spins forever when the profile load fails (board layout) | `PassSummaryCard`: the error branch is gated on `photoHeroUi`. Show error + Retry on the board too |
| **[HIGH]** | Check in and QR offered with 0 visits left | `lowVisits` keeps `canShowQr`. Block when `visitsLeft == 0` |
| **[HIGH]** | Sponsored members told "No pass yet / Choose a pass" | Board ignores `sponsoredGymAccess`. Add the sponsored state (S13) |
| **[MID]** | Suspended reads "Your pass ended -." | `passStateFor` sends any non-`inactive` status to ended. Add suspended/cancelled states and the missing `member.status_*` keys |
| **[MID]** | Ending-soon thresholds differ between files | `pass_state` (≤3 days / ≤3 visits) vs `home_feed._passport` (≤1 visit / ≤5 days). One shared constant; scale for daily/weekly plans |
| **[MID]** | Failed check-ins load looks like zero visits | `_refreshCheckins` swallows errors. Add a `checkinsFailed` flag and show "Couldn't load visits" |
| **[LOW]** | Visits this month counted in UTC | See d |
| **[LOW]** | Greeting can show an email or phone as the name | `knownName` falls back to email/phone/publicId. Greet without a name instead |
| **[LOW]** | Unknown server codes are reworded for English readers only | `lib/shared/api_error_message.dart` `_humanize` runs only for `en`; Swahili gets the generic line. Map known codes, and log unknown ones |

### i. Design canvases to review

See "Design canvases (member app)" at the top of this section.

### Round 2 (16 Nov): answers from Godliving

#### j. Gym tiers: an access ladder [HIGH]

Godliving's decision (16 Nov, replaces the earlier "every pass opens every gym" note): passes open gyms on a ladder.

| Pass | Price / visits today (`/subscription-tiers`) | Opens |
|---|---|---|
| Basic | TSh 30,000 · 12 visits | Basic gyms |
| Pro | TSh 60,000 · 30 visits | Pro + Basic gyms |
| Premium | TSh 100,000 · 30 visits | Premium + Pro + Basic gyms |
| Executive | TSh 200,000 · 30 visits | All gyms, plus Executive perks |

**[HIGH] Access ladder: the server enforces, the client explains**

What the code does today:

| Where | What it does |
|---|---|
| `lib/shared/pass_gyms.dart:1-38` | `gymsForPass()` already filters on a ladder from the pass's `gymAccess`: standard < midtier < premium < luxury_executive. A missing or unknown `gymAccess` opens every gym |
| `lib/shared/pass_gyms.dart:52` | `gymsAddedByUpgrade()`: the gyms an upgrade adds |
| `lib/shared/models.dart:847,867` | `PassTier.gymAccess` read from `/subscription-tiers` |
| `lib/screens/member/member_passes_page.dart:585,874,922` | Passes page: upgrade gym list, per-pass gym list, access label |
| `lib/screens/member/member_payment_page.dart:368` | Payment page lists the gyms the pass opens |
| `lib/screens/member/widgets/pass_gyms_sheet.dart:21,43,91` | Pass gyms sheet, grouped by gym tier |
| `lib/shared/api_error_message.dart:292,298` | Server check-in codes `gym_tier_not_covered` / `tier_not_covered` exist, so the server already refuses by tier |

What must change:

- Server: check-in must refuse a gym above the pass (`tier_not_covered`), and `/subscription-tiers` must send the right `gymAccess` per pass (Basic `standard`, Pro `midtier`, Premium `premium`, Executive `luxury_executive`). The client never decides access on its own.
- Client: keep `gymsForPass()` as the explainer only. On a gym above the pass: no lock icon, a quiet line "Opens with Premium" + text link "See Premium pass". On that gym's detail, Check in is disabled with "Your Pro pass doesn't open this gym".
- Map the `tier_not_covered` error to that same sentence instead of "Gym tier not covered" (`lib/shared/i18n.dart:486`).
- Executive: the code has a fourth gym tier, `luxury_executive` (`lib/shared/pass_gyms.dart:9-14`). The spec says Executive opens "all gyms" (Premium + Pro + Basic) plus perks. Decide whether `luxury_executive` gyms exist, or whether Executive is the Premium ladder plus perks.

**[MID] Display names match the pass names**

- Code tiers stay `standard` / `midtier` / `premium`. Display only: Standard → **Basic**, Mid-tier → **Pro**, Premium → **Premium**.
- Change `tier.standard` / `tier.midtier` (`lib/shared/i18n.dart:3118-3121`, plus sw) and `pass.gymAccess.*` (`lib/shared/i18n.dart:2820-2824`, sw `11291-11295`): e.g. "Pro and Basic gyms".
- Used by `gymTierLabel()` (`lib/screens/member/widgets/gym_filters.dart:67`) on gym cards, gym detail and filter chips.

**[MID] Tier badge icons**

- Today the badge is a plain gray `FFBadge` with text only (`lib/screens/member/widgets/gym_card.dart:100-103,269`, `lib/screens/member/member_gym_detail_page.dart:168-171`). Gym detail puts a status `dot` next to it (`member_gym_detail_page.dart:165`).
- Replace with a `TierBadge`: Lucide `star` (Basic), `gem` (Pro), `crown` (Premium). Pill, height 24, icon 14 px. Premium is forest with a lime icon. No rhombus or dots for tiers.
- On photos the pill sits top-right, 10 px in, on its own solid fill.

**[MID] "See [N] gyms" deep link from each plan card**

- Each plan card gets a text button "See 12 gyms" with a chevron (aria-label "See the gyms the Pro pass opens").
- Opens `/member/gyms?tier=<pass>` with chips prefiltered (Pro + Basic selected) and a strip "Gyms your Pro pass opens · Pro and Basic" + "Clear".
- Today `/member/gyms` (`lib/router.dart:235`) takes no query, and the gyms tab filter holds one tier (`lib/screens/member/member_gyms_tab.dart:142-152`). It needs a multi-tier filter and a `tier` query param.
- Needs a per-tier gym count: `gymsForPass(gymAccess, gyms).length` works on the client; a server count is better if the gym list is paged. Show "See gyms" when the count is unknown.

**[MID] Premium and Executive need real differences**

- Premium (TSh 100,000) and Executive (TSh 200,000) both get 30 visits. Pro also gets 30. Only gym access separates them, and Executive's "perks" are not in `/subscription-tiers`.
- The old `/passes` response had `multiGymPerDay` and `trainerDiscountPct` (see `test/fixtures/regression.json:824-848`), but `PassTier` (`lib/shared/models.dart:842-868`) does not read them.
- Suggestion: bring these back on `/subscription-tiers` (or add a `perks` list) and show them on the plan cards, so a member can see why Executive costs double.

#### k. Zero visits left: never show the QR [HIGH]

Godliving's decision: with 0 visits left, the QR never shows.

- Today: `canCheckIn => hasActivePass || sponsoredGymAccess` (`lib/screens/member/member_shell.dart:139`) only looks at pass dates. `hasActivePass` is `status == 'active'` (`lib/shared/models.dart:838`). The QR keeps refreshing every 30 s (`member_shell.dart:282-283`).
- `PassState.lowVisits` covers 0 visits and still has `canShowQr` (`lib/screens/member/widgets/pass_state.dart:39-41`). The QR tab renders whenever `qrToken != null` (`lib/screens/member/member_qr_tab.dart:135`).
- Change: add `PassState.noVisits` when `visitsLeft == 0`, with `canShowQr == false`. Make `canCheckIn` false too, so `_refreshQr` stops asking for a token.
- Card and QR tab: "No visits left" + "Choose your next pass" (`pass.badge.noVisits`, `home.hero.nextPass`).
- Server: keep refusing at 0 (`visits_exhausted` / `visit_cap_reached` already map to copy in `api_error_message.dart:293,299`). Please confirm `/me/qr` itself refuses a token at 0, so the client is not the only guard.

```dart
bool get canCheckIn =>
    sponsoredGymAccess || (hasActivePass && (visitsLeft(me) ?? 1) > 0);
```

#### l. Offline at the door: keep the last QR [HIGH]

- Today: `_refreshQr` (`lib/screens/member/member_shell.dart:671-678`) sets `qrToken = null` when a refresh fails. With the 30 s timer (`member_shell.dart:282`), a member who loses signal at the gym door loses the QR within 30 s.
- Design: keep the last code on screen, paused and blurred, with "Try again".
- If the server accepts a code for a short grace window after it rotates: keep the last code sharp, with its age ("Code from 09:41"), until the window ends. Then blur + Try again.
- On failure, keep the old token and store when it was fetched:

```dart
} catch (_) {
  _data.update((d) => d.qrFailedAt = DateTime.now()); // keep d.qrToken
}
```

- Longer term: a signed offline code (time-boxed, bound to the device) for gyms with poor signal.
- String mismatch: `home.qr.refreshes` says "every 60s" (`lib/shared/i18n.dart:1913`, sw `10361`) but the timer is 30 s. Make one follow the other, ideally from a shared constant.

#### m. Round 3: the rest of the member app (16 Nov)

Checked against the code on this branch. Items already above (weekly goal, Vibe, sponsor names, error ref codes, Premium/Executive perks, per-tier counts, `?tier=` route) are not repeated.

**Pass & Payment**

| Level | Change | Where / data |
|---|---|---|
| **[HIGH]** | Add a member Payments page with receipts: amount, date, provider reference, merchant name, TIN | Only `member_sessions_page.dart:490` calls `myPayments()` (`api_client.dart:2221`). Receipt fields: NEW unless `/me/payments` already has them |
| **[MID]** | Cancel a pending mobile-money request, and resend the prompt | No cancel endpoint for `/me/payments/{id}/mobile-money` (`api_client.dart:836-858`). NEW |
| **[MID]** | Show the failure reason and, for `held`, how long the review takes | `refreshMobileMoney` returns `state` only. NEW `reason`, `reviewEta` |
| **[MID]** | Price per visit on plan cards; "Most picked" badge | Per visit: client math. "Most picked": NEW purchase counts |
| **[LOW]** | Pick the network from the number prefix; share/PDF receipt; refund wording | Client only, except refund ETA (NEW) |

**Check in**

| Level | Change | Where / data |
|---|---|---|
| **[HIGH]** | QR spinner never stops after a failed refresh | `member_qr_tab.dart:135-145` shows `FFSpinner` whenever `qrToken == null`; `_refreshQr` nulls it on failure (`member_shell.dart:671-678`). Fix with item l: last code blurred + Try again |
| **[HIGH]** | Scan page has no camera-denied state | `member_scan_gym_page.dart:99` `MobileScanner` has no `errorBuilder`. Show "Allow camera" + Open settings + "Show my QR instead" |
| **[MID]** | Success screen: live clock + member name, so reception can tell it's not a screenshot | Design only. Depends on the reception question below |

**Activity**

| Level | Change | Where / data |
|---|---|---|
| **[HIGH]** | Run on web shows a dead end | `member_record_run_page.dart:193-200`: `FFEmptyState` with no action. Add "Log a run by hand" > `member_log_activity_page.dart` |
| **[MID]** | Two segmented controls stacked | `member_activity_tab.dart:195` and `widgets/activity_period_card.dart:132`. Keep one |
| **[MID]** | Training setup is one long page; split into 3 steps. Sub-pages show a double header | `member_training_setup_page.dart` |
| **[LOW]** | "Sample" badges on History rows | `widgets/activity_widgets.dart:180` (`isSample`). Confirm sample activities never reach real members |
| **[LOW]** | Title case in Setup labels; check 19–25 Oct days vs the Home week grid | Copy / QA |

**Profile, people and invitations**

| Level | Change | Where / data |
|---|---|---|
| **[HIGH]** | Server wording on Messages, Benefits, Sessions, Inbox and Trainer errors | `apiErrorMessage` shows the server reason, reworded, to English readers (`api_error_message.dart:96-109`). Callers: `member_message_settings_page.dart:64`, `member_benefits_page.dart:88`, `member_sessions_page.dart:509,535`, `shared/inbox/inbox_pages.dart:206`, `member_trainer_detail_page.dart:100`. Raises bug h's last row to HIGH: map codes, never show raw reasons |
| **[HIGH]** | Invitations empty is bare text | `shared/widgets/invitations.dart:232-238` (and `:864`). Use `FFEmptyState` + "Find a gym" |
| **[MID]** | Invite code on profile; refund ETA | NEW fields |
| **[LOW]** | Sharing switches at 44 px with `role=switch` semantics; Friends tabs as a segmented control | `member_community_page.dart:36` (`TabBar`), `:1350,1357` (`SwitchListTile`) |

**Trainers, Inbox & Help**

| Level | Change | Where / data |
|---|---|---|
| **[HIGH]** | Trainer detail's bottom bar collides with the shell's Check in button | `member_trainer_detail_page.dart:237` `bottomNavigationBar`, while the route sits inside the member shell (`router.dart:1819-1826`). Hide the shell nav on detail, or move the route out |
| **[MID]** | Price reads "TZS 15000/session" | `member_trainer_detail_page.dart:368` skips `formatCurrency`. Use "TSh 15,000 / session" (card at `widgets/trainer_card.dart:390` is formatted) |
| **[MID]** | Drop the lime Book pill on every row; the whole row opens the trainer | `widgets/trainer_card.dart:26,255` |
| **[MID]** | Booking flow: trainer confirm/decline, pay-by deadline, free-times count, typical reply time | NEW fields on bookings / trainer |
| **[MID]** | Help: FAQ + search, a support ticket endpoint, support phone and hours | NEW. No help route in code |

**Start (sign in and setup)**

| Level | Change | Where / data |
|---|---|---|
| **[HIGH]** | Wrong PIN: show attempts left and unlock time | `/auth/pin/login` (`api_client.dart:327`) errors map to `invalid_credentials` / `too_many_attempts` only (`api_error_message.dart:356,368`). Server: NEW `attemptsLeft`, `lockedUntil`. The pattern exists in `shared/widgets/verify_identifier.dart:21-26` |
| **[HIGH]** | Onboarding error is a dialog that can lose typed data | `member_onboarding_page.dart:109-130` `_showErrorDialog`. Use an inline Mid alert and keep the form |
| **[MID]** | Setup in 4 steps; height/weight move to Profile; save `weeklyGoalDays` + `vibe` with `updateProfile` (`api_client.dart:719`) | Fields NEW (see c and b) |
| **[MID]** | Drop off-palette role colours on the role picker | Role picker; use DS tokens only |
| **[LOW]** | Preselect the phone's language on first run | `FFLocale._locale` defaults to `en` (`i18n.dart:25`); `load()` only restores a saved choice (`:38-50`). Use the device locale when nothing is saved |
| **[LOW]** | Role names "Trainer" / "Seller"; wordmark on the splash; email PIN reset not live yet | Copy / brand; email reset is server-side |

Dropped from the design log, already handled:

- Reused "Couldn't load your messages" titles: fixed in 42e177d.
- Home "of 18 visits": the code reads the real `visitCap`; 18 appears only in comments (`widgets/pass_summary_card.dart:278,382`). The design canvas is being fixed to 30.
- "Tiers are labels, not access": superseded by the access ladder (item j).

### Questions for Nassor

| Level | Question |
|---|---|
| **[HIGH]** | Where should the new data live: weekly goal days, the Vibe preference, preferred language on `/me`, and a request id in error bodies for "Ref" codes? |
| **[HIGH]** | Does the door/server accept a QR code for a grace window after it rotates (e.g. 60 to 120 s)? If yes, how long? Could a signed offline code work for poor-signal gyms? |
| **[HIGH]** | Does the access ladder (Basic → Basic gyms; Pro → Pro + Basic; Premium → all three; Executive → all + perks) match the business agreements with each gym? Does the server enforce it at check-in today? |
| **[MID]** | Do `luxury_executive` gyms exist, or is Executive the Premium ladder plus perks? |
| **[HIGH]** | Does `/me/qr` refuse a token when visits left is 0? |
| **[MID]** | Should a "Funny" vibe exist at all, or only Coach / Calm / Off? |
| **[HIGH]** | Can a Pro member book a trainer at a Premium gym? If yes, does the session open the gym for that visit? |
| **[HIGH]** | Pay after the trainer confirms: how long is the slot held before it's released? |
| **[HIGH]** | Does reception look at the member's phone at check-in? If yes, the success screen gets a live clock + name |
| **[MID]** | Support phone number and hours, for Help and the suspended-pass card |
| **[MID]** | Ask for location in setup, or on the first Gyms visit? |
| **[MID]** | Real date for the account recovery review (the Start canvas shows a placeholder) |
