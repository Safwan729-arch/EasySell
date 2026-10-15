# EasySell UI reskin — design

Status: approved 2026-10-15, building on `feat/easysell-ui` (branched from
`feat/product-expiry`). Source of truth: the mockups and `new_design.md` in
`EasySell Ui/` (user's folder, not committed).

## 1. What this is

A **visual reskin** of the existing app to the "EasySell" design language:
light = *Pastel glass*, dark = *Neon glass*. Colour, depth, radii, background
and the nav bar change. **What each screen does and shows does not.**

**User's decision (2026-10-15): keep features, new look.** The mockups were
drawn from an older build. Since then Home gained Restock soon / Expiring /
Receivables cards and lost the bell, and the Items header gained Restock and
the scan/voice pill. Where a mockup and today's app disagree on *content*,
today's app wins and the newer element is styled to match its mockup
siblings. Ruled out:
- **Match the mockups exactly:** it would remove or move shipped features
  (bring back the bell, turn Restock soon back into "Low stock").
- **Theme-only change:** too little. Gradients, glow, wave lines and the
  floating nav can't be expressed in `ThemeData` alone.
- **Rewrite screens from the images:** highest break risk, and it fights
  the decision above.

Not to be confused with the abandoned "Khata" redesign (`new design/`, 2026-10-14).
That was a different brief and stays abandoned.

## 2. Decisions where the mockups disagree (`new_design.md` §10)

1. **Reports period control: pills in both themes.** Dark 14/15.png shows
   underline tabs, but that would be a second widget for one screen, and Home
   already uses pills.
2. **Product tile: solid colour + white letter everywhere,** the Cart
   included (17.png's dark tile with a blue letter is the odd one out).
3. **Tile colour is per product, not per category.** Categories are
   user-made and unbounded. The existing `tileColorFor(name)` hash stays,
   narrowed to the 4 mockup colours (green, purple, red, orange) with
   per-theme shades.
4. **The delta arrow follows the sign of the change** (6.png's up-arrow on
   −86.2% is a mockup bug).
5. **Money format and the position of ৳ in Bangla are unchanged.** They're
   already covered by `money_format*_test.dart`, and the mockups agree with them.

## 3. Foundation

**Tokens (`lib/core/config/theme.dart`).** The light/dark palettes take the
hex values from `new_design.md` §3. `AppColors` keeps every existing field,
because 22 files read them. It **adds** the new roles (eyebrow, textDim,
link, chipBlue, successBg, warningBg, barIdle/barEmpty, glow outline, row,
field, iconButton, danger, stop) and the gradients (brand, hero).

**Component themes:**

| Element | Style |
|---|---|
| Cards | radius 22. Light: soft blue shadow. Dark: 1 px glow outline |
| Inputs | radius 18, ~54 high |
| Big buttons | radius 16, 54 high |
| Chips and pills | stadium (fully round) |
| Sheets | top radius 28 with drag handle |
| Dialogs and date picker | radius 32. Selected day is a primary circle |
| AppBar | transparent at rest; solid background when scrolled under |

**Primary buttons are styled in the theme, not swapped widget by widget.**
`ButtonStyle.backgroundBuilder` (Flutter ≥ 3.22; we're on 3.44) paints the
blue→violet gradient behind every `FilledButton` in light mode. Dark mode
stays flat `#4D92FE` with dark text. All 38 filled buttons pick this up, and
the widget tests that find buttons by type keep working.

**The dead `_typeScale` code is removed.** It never applied (see memory
`khata-redesign-abandoned`), so rendered text sizes are unchanged.

**Page backdrop.** One `AppBackdrop` widget paints the solid background plus:
- light: a lavender blur top-right and a sky-blue blur bottom-left
  (radial gradients, not real blur, which is cheap);
- dark: a navy glow and ~13 thin wave lines top-right (CustomPainter in a
  RepaintBoundary, so scrolling doesn't repaint it).

`scaffoldBackgroundColor` becomes transparent. Each page is wrapped in the
backdrop at three points: `_transitionPage` (every full-screen route), the
`MainShell` scaffold (the four tabs) and the `/scan` route.

The backdrop sits **inside** each page, not behind the navigator. So pages stay
opaque, and the fade/slide transition never shows one page through another. A
solid-colour `ColoredBox` behind the navigator is the safety net: a route
that misses the wrap shows plain background, not black.

**New shared widgets (`lib/core/widgets/`):**
- `AppBackdrop`
- brand fill (gradient or flat primary) for selected pills, the Sell button
  and the "+" button
- `ProductTile` (letter avatar)
- restyled `AppBottomNav`: floating and fully rounded in light, with a
  highlight and dot on the active tab; docked with a glowing top edge in dark
- restyled `SegmentPills`: 46 high, brand fill when selected

## 4. Build order

One commit per step. **Gate for every step:** `flutter analyze` clean and the
full `flutter test` suite green.

1. Foundation (§3), plus theme tests.
2. Home: header buttons, period pills, revenue hero, 7-day bars, top
   performer, restock / expiry / receivables cards, Sell button.
3. Items: header, search, filter chips, item cards. Then product detail and
   the product form.
4. Cart and sheets: add to cart, discount, restock confirm, breakdown,
   inventory value, date picker.
5. Reports: donut, legend, Biggest wins ranks. Its hard-coded colours move
   onto tokens.
6. History and sale detail.
7. Settings: section labels, icon tiles, the two-option segments, sign out.
8. Scan and voice.
9. Everything else: customers, restock list, expiry, onboarding, welcome,
   login, insights, trends, categories, archived.

## 5. Risks

- **Overflow on narrow phones.** The S22 is 360 dp, the mockups 390. Bigger
  radii and padding eat width. The existing `inventory_header_test` and
  `breakdown_sheet_fits_test` guard the known hot spots.
- **Contrast** (`new_design.md` §11): `textDim` is for icons and disabled
  states only, never reading text. White on the light gradient needs
  15/600 or larger.
