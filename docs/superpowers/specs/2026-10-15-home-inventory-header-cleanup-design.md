# Home bell removed, Inventory header decluttered, restock badge — design

Status: built 2026-10-15 (no migration). Feedback from S22 screenshots.

## 1. Home: the notification bell is gone

**Why.** The bell opened the expiry alerts screen. Everything it showed is
already a card on Home itself:
- "Restock soon"
- "Expiring & expired", each with its own **View all**.

Scrolling a little shows the same thing, so the bell was a second door into
the same room, with a badge adding noise to the header.

**Kept.**
- The alerts screen (`AppRoutes.alerts`), because a reminder notification tap
  still opens it.
- The `// MEMBER C` seam moved to that route: push notifications open the
  screen directly.

## 2. Inventory header: two actions, not four

**Why.** On a 360 dp phone (S22), scan, voice, restock and add were four
48 dp filled buttons. Together they took about 220 dp of the title row, so
"Inventory" broke into "Inven / tory" and the value line shrank to
unreadable.

**Now.**
- **The header holds only Restock and Add.**
- **Scan and voice moved inside the search bar** as plain icons, the familiar
  camera-and-mic pattern of a phone's search bar. While typing, Clear takes
  their place.
- **The title is one line** inside a `FittedBox(scaleDown)`. It shrinks a
  little on a narrow phone or a long translation, rather than wrapping or
  being cut off.

**Ruled out.**
- **Smaller (40 dp) header buttons.** Flutter still pads each tap target to
  48 dp, so they take the same layout space and the title gains nothing.
- **A second row of labelled buttons.** It costs a full row of vertical space
  on a screen whose job is the list.

## 2a. Revised the same day: scan and voice back in the header, at 40 dp

**Why.** In the search bar, the user found scan and voice misleading. They
look like "search by camera / by voice", but both of them **sell**. A
shopkeeper would tap them to find an item and land in a sale.

**Now.**
- **Top right, all four buttons are 40 dp with a 20 dp icon** (`_headerButton`).
- **Scan and voice share one tinted pill** (`secondaryContainer`). They read as
  one group of selling tools, apart from the solid blue stock actions, Restock
  and Add.
- **The search bar holds only search.** Clear appears while typing.

**This overturns §2's "ruled out: smaller buttons".** That reasoning was wrong.
The extra space came from Material 3's 48 dp **tap-target padding**, and
`tapTargetSize: MaterialTapTargetSize.shrinkWrap` removes it. `fixedSize`
alone does not. The cluster is now 80 + 6 + 40 + 6 + 40 = 172 dp, against
about 220 before. On the S22, "পণ্যতালিকা" and its value line both fit on one
line.

**Tests** (`inventory_header_test.dart`):
- the search bar has no IconButton;
- scan and voice are level with Add;
- the Add button measures 40 × 40.

## 3. Restock badge

The basket button shows the number of **Buy now** items
(`restockPlanProvider`, the same count as the Home card). It is hidden at
zero.

## Gotchas

- **The test font is wider than a phone's.** Flutter's test font draws every
  glyph as a full square, so the Bengali title (10 code units, about 240 dp at
  24 sp) "overflowed" in tests where a phone fits it easily. `FittedBox` makes
  the guarantee hold on any font. Test: `test/widgets/inventory_header_test.dart`.
  Run it with `--dart-define=VISION_SCAN_ENABLED=true
  --dart-define=VOICE_SALE_ENABLED=true` too, because the release flags add
  the scan/voice pill and leave the title the least room.
- **Other Inventory tests must stub the restock plan.** The Inventory screen
  now reads the restock plan, which reaches `todayProvider`'s midnight timer.
  Tests that pump the screen therefore override `restockPlanProvider`, or
  they fail with "A Timer is still pending".
