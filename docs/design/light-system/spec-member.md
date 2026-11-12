# Member app spec (from the FitFlex DS v1.0 board)

Source of truth: Godliving's "FitFlex Design System v1.0" board (home phone,
foundations, components) and the approved canvas boards for the other member
screens. Every screen is checked side by side against these before it ships.
Sizes are logical pixels on a 390 wide phone.

## Foundations

| Token | Value |
| --- | --- |
| Typeface | Plus Jakarta Sans (OFL), one family |
| Display | 48/56 Bold |
| Page heading | 28/32 SemiBold |
| Section heading | 20/24 SemiBold |
| Card title | 16/20 SemiBold |
| Body | 15/18 Regular |
| Supporting | 13/16 Regular |
| Small | 11/14 Medium |
| Spacing | 4 8 12 16 24 32 40 48 |
| Radius | small 8, control 12, button 14 (we use pills), card 20, feature 24, pill 999 |
| Elevation | 0 flat; 1 card `0 2 8 rgba(16,45,36,.05)` (light only); 2 elevated `0 4 12 rgba(16,45,36,.08)` |
| Icons | one family, 2px stroke look, 24 default, 20 compact |

Colour roles are in `README.md`. Lime `#D4EF68` is a fill with forest text,
never text on white.

## Components

| Component | Spec |
| --- | --- |
| Primary button | Lime fill, forest label 15/600, optional trailing arrow, pill, 44 to 52 tall |
| Secondary button | Forest fill, white label, pill |
| Tertiary button | Transparent, 1.5 forest outline, forest label, pill |
| Chip, active | Lime fill, forest 13/600 |
| Chip, neutral | `#EAF0E8` fill, forest |
| Count chip | Forest circle, white "+2" |
| Status chip on a lime card | Forest fill, white 13/600, leading icon (calendar for dates) |
| Search input | Pill, white, 1px border, leading search icon, trailing clear (x) |
| Select | Same shell, trailing chevron |
| Alert, success | Lime tint fill, forest check-circle icon, text, close (x) |
| Alert, info | Blue tint fill, info icon, title, "View details ›" link |
| Progress ring | 72-96 diameter, 8 stroke, centre label 20/700 |
| Card | White, radius 20, elevation 1, padding 16 |
| Feature card | Lime, radius 24, padding 20 |
| Stat tile | Radius 20, label 13, number 40/800, unit 14, mini bar chart of real data bottom right. Dark variant: forest fill, lime number, white unit |

## Bottom bar

Home, Activity, raised Check in, Gyms, Shop. White bar, top hairline.
Selected: filled icon, forest label 12/700. Unselected: outline icon, muted
label 12/500. No pill behind the selected icon. Check in: 60 forest circle,
lime QR icon, white 4px ring, lifted half above the bar (lime circle, forest
icon in dark).

## App bar

Wordmark left ("Fit" + "Flex" on a lime chip). Right: bell in a 44 white
circle with a red dot when unread; avatar 44, forest circle with a lime
initial. Nothing else.

## Home

1. Greeting: "Good morning," 18/500, then the first name 28/700.
2. Pass (feature card): forest status chip with calendar icon ("Active till
   8 Nov"); "FitFlex Pass · Pro" 20/600; "11" 56/800 with "of 18 visits left"
   15/500 on the baseline; forest "Check in" pill with QR icon and arrow on the
   right; dot map of Africa, faint, top right.
3. This week (card): "This week" 16/600; right "2 of 3 workouts ›" 13 muted,
   tappable. Seven columns: day 12 muted; 36 circle. Done: lime with forest
   check. Today: forest with white number. Other: plain number 15/600.
4. Stat row, two tiles: Streak (dark variant, flame icon in the label) and
   Visits this month (light). Each with a mini bar chart of the last four
   weeks.
5. Nearest gym (card, padding 10): 64 photo radius 14; "Nearest on your
   pass" 12 muted; name 16/700; pin icon and distance 12 muted; lime "Open"
   pill.

## Other member screens (canvas boards)

| Screen | Must have |
| --- | --- |
| Check in | Lime pass summary strip on top; QR on a white card; refresh progress bar and "New code in 37 s"; "Visit 8 of 18"; tertiary "Scan the gym's code instead"; "The code needs signal to refresh" |
| Gyms | "Find your gym" 28/700; search pill; filter chips; nearest gym as a large photo card with a lime distance chip; then rows with photo, name, area, status and a View / Upgrade pill |
| Activity | Week / Month / Year tabs; three stat tiles; bar chart with lime bars for active days; recent check-ins as grouped rows with status chips |
| Shop | Browse / My orders tabs; featured store photo banner; category chips; best sellers grid with stock chip and a round add button |
| Profile | Profile card (avatar, name, member since, plan chip); dark "Own a gym, train or sell?" card with lime Add role; grouped rows with value and chevron; Sign out as a soft red pill |

## Review loop

For each screen: build, screenshot on GitHub (light and dark), put it side
by side with the board, have an independent reviewer list the gaps, fix,
repeat.
