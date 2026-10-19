---
tags: [design, layout, fix]
---

# Cramped Items and History rows — fix notes

Date: 2026-10-18. Bounded fixes from on-device screenshots (S22), no plan.

## What the user saw

- **Items:** product names broken mid-word ("Powde / r", "Cleanin / g").
- **History:** the table looked "very compacted": "২:২৩PM" touching the
  product name, the Qty header cut to "প…", the Cash/Digital label tiny.

## The trap: it is not the font size

`lib/app.dart` pins text scaling to 1.0, so the phone's Font size setting
(1.5 on the test phone) does nothing to the app. **Screen zoom does**: the
phone's density was 540 instead of 480, so the app saw a ~320 dp wide screen.
I first blamed the font scale and offered a "cap text at 1.3×" fix, which
would have made the app *bigger*. Check `adb shell wm density` first.

Narrow screens are real (small phones, zoom used by older shopkeepers), so
the layouts were fixed for ~320 dp rather than blamed on the setting.

## Fixes

- **Items row:** stock count moved under the category; only the price stays
  on the right. In the right-hand column, "0 pcs in stock" set that column's
  width and left the name a sliver.
- **History table** (kept as a sortable table; the header still lines up):
  time column shows the clock over a small AM/PM, then a 10 dp gap
  (`_gap`) applied to the header, summary rows, expanded lines and the
  discount line alike; Qty widened 34 → 44 and header labels scale down
  instead of ellipsizing; names may wrap to two lines; the payment label is
  `bodySmall` instead of `labelSmall`.
- Rejected: replacing the History table with a two-line card list. It reads
  well but loses the column headers that the sort controls live on; too big
  a change two days before the hackathon deadline.
