# Sale detail: expiry date of the delivery sold from

**Status:** built 2026-10-15 on `feat/product-expiry`. No plan (bounded change, approved in chat).

## What

Opening a sale from History shows an **Expiry date** row under Quantity: the
expiry date of the delivery (`product_batches` row) the units came from.

## Why it is possible

Since 0012 every sale line can name its delivery (`transactions.batch_id`).
The cart fills it in for every dated sale: a chosen delivery, the only dated
option, or one row per delivery when a checkout draws from several
(`batch_pick.dart`). So each sale row has at most one delivery and one date. No
migration was needed.

## Decisions

- **Embed, don't fetch separately.** `recentSales` and `salesForDay` select
  `*, batch:product_batches(expiry_date)` (`saleSelect` in
  `transaction_repository.dart`). The detail screen gets the `Transaction` via
  go_router `extra`, so the date arrives with the list and the screen has no
  loading state. A per-screen fetch would have needed a provider, a spinner and
  an error state for one line of text. The embed is unambiguous because
  `transactions` has exactly one FK to `product_batches` (0012). A second FK
  would make PostgREST reject the query and break History, so it would need an
  explicit `!fk_name` hint.
- **Closed deliveries still resolve.** A sold-out or removed delivery is
  closed (`closed_at`), not deleted, so its date still shows. Only a deleted
  batch row (FK `on delete set null`) loses it.
- **Hidden, not "—", when unknown.** A null `batch_id` means one of these:
  undated stock, a product without expiry tracking, or a sale from before 0012.
  The app can't tell these apart from the row, and "—" would wrongly suggest
  "this had no expiry" for an old sale that simply predates tracking.
- **No guessing from FEFO.** For a sale with no `batch_id`, the app does not
  guess a delivery from the oldest-first estimate. The detail screen shows
  frozen facts (spec of 2026-07-21), and a guess would be presented as one.
- **`batchExpiry` is read-only on the model.** It uses
  `@JsonKey(readValue: …, includeToJson: false)`, so a `toJson()` can never
  send a non-existent `batch_expiry` column. `batchId` does serialise, since it
  is a real column.
- **Label and format are reused.** The row uses `expiry_dateLabel` and
  `formatExpiryDate`, so it reads the same as the Deliveries section and in
  Bengali. There are no new strings.

## Tests

- `test/transaction_batch_expiry_test.dart`: reads the embed, handles null and
  absent embeds, and never writes the embed back.
- `test/widgets/sale_detail_screen_test.dart`: the row is shown with a date and
  hidden without one.
- Checked on the S22 (Bengali): Aerosol showed ৩১ অক্টো, ২০২৬ and Pepsi showed
  ৩০ অক্টো, ২০২৬.
