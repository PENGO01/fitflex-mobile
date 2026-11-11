# FitFlex mobile design system

Shared tokens live in `lib/shared/design_tokens.dart` (`FFTokens`, plus the
light and dark `ThemeData`). Shared widgets live in `lib/shared/components/`
and are exported from `components.dart`:

```dart
import 'package:fitflexmobile/shared/components/components.dart';
```

All user-visible strings go through `context.tr('key')` with an entry in both
the `en` and `sw` maps in `lib/shared/i18n.dart`.

## Token roles

| Role | Tokens | Use |
| --- | --- | --- |
| Brand ramp | `brand50` ... `brand800`, `brandBright` | `brand500` (portal brand-600) is the primary fill; white on it is AA. `brand50`/`brand200` for tints and borders, `brand700`/`brand800` for text on tints. `brand400` and `brandBright` are bright accents for graphics and dark surfaces only, never for text on white. |
| Semantic | `success*` (teal, distinct from brand), `warning*`, `error*`, `info*`, `accent` (gold, fills only) | `*50` background, `*200` border, `*700` text on light. On dark use `errorOnDark` for error text/icons. |
| Surfaces and text | `Theme.of(context).colorScheme` (`surface`, `onSurface`, `onSurfaceVariant`, `outline`) | Prefer the colour scheme over `FFTokens.fg*`/`bg*` (those are dark values) so both themes work. Never hardcode `Colors.white` or `Colors.black`, except on-primary text via `colorScheme.onPrimary`. |
| Input borders | `inputBorderLight`, `inputBorderDark` | Form-control outlines, at least 3:1 against the surface (WCAG 1.4.11). Applied by the theme's `inputDecorationTheme`; do not use them for decorative dividers (`outline` is for those). |
| Spacing, radius, icons, motion | `spacing*`, `radius*`, `icon*`, `motion*` | Use these instead of literal numbers. |

## Widgets

### FFButton

Variants `primary`, `secondary`, `ghost`, `destructive`; sizes `sm` (40dp,
48dp hit area), `md` (48), `lg` (52). `loading` keeps the width, shows a
spinner and ignores taps.

```dart
FFButton(label: context.tr('common.confirm'), onPressed: save);
FFButton(
  label: 'Delete',
  variant: FFButtonVariant.destructive,
  icon: Icons.delete_outline,
  loading: _busy,
  fullWidth: true,
  onPressed: delete,
);
```

Pass `onPressed: null` for a disabled button.

### FFSnack

Transient feedback after an action. Replaces any snackbar already showing.
Use `FFAlert` instead for messages that must stay on screen.

```dart
FFSnack.success(context, context.tr('profile.saved'));
FFSnack.error(context, message, actionLabel: context.tr('common.retry'), onAction: retry);
```

Also `FFSnack.info` and `FFSnack.warning`. 4s, errors 6s.

### showFFConfirmDialog

```dart
final ok = await showFFConfirmDialog(
  context,
  title: 'Delete this gym?',
  message: 'This cannot be undone.',
  destructive: true,
);
if (ok) { ... }
```

Cancel and confirm labels default to `common.cancel` and `common.confirm`.
Dismissing the dialog returns `false`.

### FFSheet / showFFSheet

Bottom sheet with drag handle, title, close button, keyboard padding and
scrolling content.

```dart
await showFFSheet<void>(context, title: 'Filters', child: FilterForm());
```

### FFSkeleton, FFSkeletonLine, FFSkeletonCard, FFSkeletonList

Placeholders while a list or card loads. They pulse gently and stand still
when the OS asks for reduced motion.

```dart
if (loading) return FFSkeletonList(count: 4, semanticLabel: context.tr('common.loading'));
```

Use `FFSpinner` for short, in-place waits (a button, a refresh) and skeletons
when the shape of the content is known.

### FFEmptyState and FFErrorState

`FFEmptyState` says there is nothing yet (optional `icon`, `body`, `action`).
`FFErrorState` says loading failed and offers a retry; its texts default to
`common.errorTitle` / `common.errorBody`.

```dart
FFEmptyState(icon: Icons.fitness_center, title: 'No sessions yet', body: '...');
FFErrorState(onRetry: _load);
```

## Accessibility rules

- Every `IconButton` needs a `tooltip` (it is also the screen-reader label).
  Shared keys: `common.close`, `a11y.back`, `a11y.refresh`, `a11y.copy`, ...
- Tappable things are at least 48x48dp. `FFPill(onTap:)` and `FFSegmented`
  already comply.
- Text scale is clamped to 1.0-1.3 in `MaterialApp.builder`. Let text wrap or
  ellipsize; do not shrink it with `FittedBox`.
- Titles use `FFSectionTitle` / `FFPageHeader` so they are announced as
  headings. Long Swahili labels must not overflow: use `maxLines` and
  `overflow`, and avoid fixed widths.
- Check new UI in light and dark.

## Proposed: light system

A proposed restyle (light and dark) is documented in
`docs/design/light-system/README.md`. It is a proposal: the tokens above are
still the ones in use.
