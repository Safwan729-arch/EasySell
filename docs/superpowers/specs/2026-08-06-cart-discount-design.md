# Cart Discount — Design

**Date:** 2026-08-06
**Feature owner:** Member A (Full Stack)
**Scope:** `supabase/migrations/0009_cart_discount.sql`, `lib/features/cart/**`,
`lib/features/transactions/**`, `lib/l10n/**`
**Status:** built on `feat/cart-discount` (`8ca8e32`..`a3e795c`), all review
findings closed, 401 tests; **migration `0009` not yet applied to the database**
— see §10 and §12
**Related:**
- [[2026-07-07-sale-cart-design]] — the cart and `record_sale_cart` this extends
- [[2026-07-17-customer-credit-khata-design]] — the khata debt must record the
  *discounted* total, so this touches that ledger
- [[2026-07-21-history-sale-detail-design]] — where the discount is displayed

---

## 1. Problem

Shopkeepers routinely knock money off a bill at the counter — rounding ৳487
down to ৳480, or giving a regular customer ৳50 off. The app has no way to
express that, so the shopkeeper either edits quantities to fake it (which
corrupts stock) or records the full amount (which corrupts revenue).

## 2. Decisions taken up front

| Question | Decision | Why |
|---|---|---|
| Discount shape | **Flat amount off the total** | Matches the real behaviour — rounding the bill to a clean number. A percentage produces ৳438.30 and the shopkeeper rounds it anyway, so `%` is one extra step to reach the same place. |
| Over-discount | **Hard cap at the total, soft warning below cost** | The cap prevents a negative bill. The warning respects that clearing near-expiry stock at a loss is deliberate, not a mistake. |
| Visibility | **Sale detail in History only** | A shopkeeper looking at an old receipt must be able to see why ৳1360 became ৳1300. A Reports "discounts given" card was explicitly deferred. |
| Placement | **A row inside the existing checkout bar** | Where the shopkeeper already looks before pressing Checkout, and the bar already owns the total. One tap, no extra screen for the majority of sales that have no discount. |

## 3. The structural problem: there is no receipt

`transactions` is the only sales record. A "receipt" is several rows sharing a
`sale_group_id` — there is no header table. So a cart-level discount has no
natural home, and revenue is **derived, not stored**: `selling_price × quantity`
is recomputed in four places (`get_dashboard_summary`, `get_sales_series`, the
khata total inside `record_sale_cart`, and `Transaction.revenue` in Dart). Any
discount that fails to reach all four makes the books disagree with the
receipts.

## 4. Options considered

| # | Option | Verdict |
|---|---|---|
| A | `discount_amount` column per transaction row, split across lines | **Chosen** |
| B | Separate `sale_discounts` table keyed by `sale_group_id` | Rejected — grain mismatch |
| C | Bake the discount into `selling_price` | Rejected — falsifies history |

**Why not C, despite it needing zero query changes.** `selling_price` is
defined as the product's price *at sale time* (CLAUDE.md §4). Writing ৳43.24
into it makes history claim that was the price that day, and permanently
destroys the distinction between "a discount was given" and "the price
changed". It trades a lie in the books for an evening of work.

**Why not B, despite being the better textbook schema.** The discount would sit
at receipt grain while every aggregate sums at line grain. Subtracting one from
the other requires a subquery; written as a join instead, a 3-line receipt
subtracts its discount three times. That bug reconciles perfectly against
single-line carts and only appears against a real 6-item basket.
`get_sales_series` would also need the discount to carry its own timestamp so it
could be bucketed.

**Why A wins.** Every revenue figure in the app is already a flat sum over
transaction rows. A changes each by **one term** and leaves the query shape
untouched; B changes the shape of all of them. For the one feature in the app
that moves money, the option with no new failure mode beats the tidier schema.

## 5. Data model

```sql
alter table transactions
  add column if not exists discount_amount numeric(10,2) not null default 0
  check (discount_amount >= 0);

alter table transactions
  add constraint transactions_discount_within_line
  check (discount_amount <= selling_price * quantity);
```

Existing rows default to `0`, so there is no backfill and no behaviour change
until the term is added to the queries.

The second constraint is the real guard: **a negative bill becomes structurally
impossible**, not merely blocked by UI code. Voice and scan already exist as
alternate entry paths and more may follow; the database is the only door all of
them pass through.

## 6. The split rule

`record_sale_cart` gains `p_discount numeric default 0`. After the lines are
built:

1. `subtotal := sum(selling_price × quantity)`
2. `p_discount <= 0` → nothing to allocate
3. `p_discount > max` → `raise exception 'Discount exceeds total'`, where
   `max := sum(floor(selling_price × quantity × 100) / 100)` — the sum of the
   **per-line** floors, not the floor of the sum. See below.
4. each line: **`floor`** to 2dp of `p_discount × line_subtotal / subtotal`
5. distribute the remainder a paisa at a time, largest line first, skipping any
   line already at its own subtotal. Ties are broken by `id` — a random
   `gen_random_uuid()`, so the tie-break is arbitrary, not insertion order.
   That is acceptable only because a tie means the lines are the same size, so
   whichever absorbs the stray paisa hides it equally well.

**Floor, not round — this is load-bearing.** `quantity` is `numeric(10,3)`
(0003 widened it for kg/litre), so a line subtotal can carry three decimals:
৳45.00 × 2.501 = ৳112.545. Rounding a full-discount allocation *up* to ৳112.55
would exceed that line's own value and trip the
`transactions_discount_within_line` constraint, failing the whole checkout on a
sale that is perfectly legal. Flooring can never overshoot, so the constraint
and the allocation cannot contradict each other.

Flooring makes the remainder always **positive** and smaller than one paisa per
line, which is why step 5 can hand it out a paisa at a time and always
terminate. The headroom check in step 5 covers the only case where the largest
line cannot absorb it: a discount equal to the entire subtotal.

**The PL/pgSQL locals must be untyped `numeric`, and that is load-bearing.**
Declaring them `numeric(12,2)` — the obvious, tidy-looking choice — silently
undoes everything above, because **PL/pgSQL coerces a value to the declared
typmod on assignment**. The remainder loop then rounds 0.005 of headroom up to
0.01, the line exceeds its own value, and the `transactions_discount_within_line`
constraint added by this very migration rejects a legal sale. Review caught
this; it was not caught by reading the SQL for intent, only by tracing a
fractional-quantity cart through it by hand.

**Consequently the maximum discount is not the subtotal.** A cart's true
subtotal can carry up to five decimals (`numeric(10,2)` price ×
`numeric(10,3)` quantity), and `discount_amount` is `numeric(10,2)` — so a
"100% discount" on such a cart leaves a sub-paisa remainder that simply cannot
be discounted away. **Dart must clamp to the same figure**, or the UI offers a
discount the database refuses and an ordinary checkout fails.

**And that figure is `sum(floor(line))`, not `floor(sum(line))`.** The obvious
form — floor the whole bill — is wrong on multi-line fractional carts, and
wrong in the direction that breaks the invariant below. Two lines of
৳45.00 × 2.501 = ৳112.545 sum to *exactly* ৳225.09, so `floor(sum)` permits the
lot; but each line's own share floors to ৳112.54 and neither has the headroom
for the last paisa, so step 5 skips both and `sum(discount_amount)` comes to
৳225.08 against an entered ৳225.09. Capping at the sum of the per-line floors
(৳225.08) makes the maximum **exactly allocatable by construction** — every
paisa it permits is a paisa some line can hold. The two forms are identical on
ordinary 2-decimal carts, which is why the weaker one survived review.

**Anywhere a rounded value is stored, the guard must test the rounded value
too.** The credit-ledger insert tests `> 0` against what it stores, not against
the exact remainder: `customer_ledger.amount` is `numeric(12,2)` with
`check (amount > 0)`, so testing an exact 0.00499 and then storing 0.00 fails
the constraint and rolls back the entire checkout. Same class of bug as the
typmod one — a value silently changing shape between the test and the write.

Step 5 is also why the sum is exact. Three ৳100 lines with ৳7 off each compute
to 2.3333 → ৳2.33, summing to ৳6.99; the stray paisa lands on the biggest line,
where it is invisible. On the *smallest* line it would be visible and look like
a bug. Because the sum is exact, `sum(discount_amount)` over a group reproduces
the entered discount to the paisa — which is why the receipt can display one
honest number without the discount being stored a second time anywhere.

### The overload trap

`p_discount` changes the signature, so `create or replace` would leave the old
function **alongside** the new one and PostgREST could no longer resolve which
to call — silently breaking checkout. This already bit this project once; the
warning is at the top of `0006_dashboard_summary_day.sql`. The migration must
`drop function if exists` **all three** prior `record_sale_cart` signatures
first.

## 7. Knock-on changes

| Where | Change |
|---|---|
| `get_dashboard_summary` | `revenue` and `profit` subtract `discount_amount` |
| `get_sales_series` | same, inside the `sales` CTE |
| `record_sale_cart` khata total | the debt written to `customer_ledger` is the **discounted** total |
| `Transaction.revenue` (Dart) | `sellingPrice * quantity - discountAmount` |

**`cost` deliberately does not change.** A discount does not alter what was paid
to the supplier, so it comes out of margin:
`profit = sum((selling_price − buying_price) × quantity − discount_amount)`.

The khata line matters more than it appears: ৳50 off a credit sale must record
৳1310 owed, not ৳1360. Computing it inside the same atomic function means
stock, sale, and debt can never disagree.

## 8. UI and state

**A separate `CartDiscountController extends Notifier<double>`**, mirroring the
existing `payment_method_controller.dart` rather than widening
`CartController`'s `List<CartLine>`. Resets on checkout, clear, and empty —
the same three points the payment method resets at.

**Clamping, not hidden state.** If the cart shrinks below the discount, the
controller lowers the *stored* value rather than remembering a larger entered
one and displaying a smaller one. A gap between the number on screen and the
number in the machine is where money bugs live.

**Entry is a modal sheet** matching `showAddToCartSheet` / `showProductPickerSheet`:
one amount field, Apply, and the below-cost warning ("You'd lose ৳12 on this
sale") computed client-side from the cart's `buyingPrice` values. The warning
never disables Apply — see §2.

**The checkout bar shows Subtotal/Discount rows only when a discount exists**,
so the common no-discount sale looks exactly as it does today. A ✕ on the
Discount row clears it in one tap.

**History detail** gets the same three rows when the group's discount is
non-zero.

New `app_en.arb` / `app_bn.arb` keys: the action, sheet title, field label,
below-cost warning, and row label.

## 9. Testing

**The split itself is not testable from this repo.** It runs inside
`record_sale_cart`, and there is no local Postgres here — so the paisa rule,
the floor-vs-round case, and the `Discount exceeds total` rejection are all
verified by the probe checklist the user runs against the real database (§10).
Duplicating the allocation in Dart purely to have something to unit-test would
put the same money logic in two languages, which is a worse failure mode than
the one it solves.

What Dart *does* own, and therefore what `flutter test` covers:

| Layer | Cases |
|---|---|
| `discount_math.dart` (pure) | clamping an entered discount to the subtotal; computing the cart's cost; the below-cost loss figure and its threshold |
| Controller | resets on checkout/clear/empty; clamps down as the cart shrinks; stored value never exceeds the total |
| Widgets | rows hidden with no discount; ✕ clears; warning shows at the right threshold and does not disable Apply |
| Repository | the payload carries `p_discount` |
| `Transaction` | `revenue` is net of `discountAmount`; `cost` is not |

The probe checklist must therefore include the paisa case explicitly — a
3-line cart with a discount that does not divide evenly, checked by summing
`discount_amount` over the group.

## 10. Rollout — order is not symmetric

The SQL is the user's to run — Supabase CLI and credentials are not available
from this repo, so migrations are pasted into the Dashboard SQL editor by hand.
**Run the migration before installing the new build:**

- Old app + new function → fine, `p_discount` defaults to 0.
- New app + old function → **every sale fails**, not just discounted ones,
  because PostgREST cannot find a signature accepting `p_discount`.

A probe checklist ships with the migration.

## 11. Out of scope — deliberately

Do not add these without a new decision:

- **Percentage discounts.** Ruled out in §2; a `%` toggle doubles the UI and
  validation for a path that would go unused.
- **A "discounts given" card in Reports.** Deferred by the user. The data will
  already exist, so it stays cheap to add later.
- **Per-item discounts.** More tapping per sale, which is the opposite of what
  a queue needs.
- **Discounts on `record_sale` / `record_restock`.** Nothing reaches those from
  the cart — `recordSaleCart` has exactly one caller, the cart checkout
  controller, so voice and scan sales already funnel through the cart screen and
  inherit discounts for free.

---

## 12. Built — what the design got wrong

Nine implementation tasks, each reviewed. Suite 322 → 363. Two tasks needed fix
rounds, and both sets of findings were defects in the **design and plan**, not
in the implementation of them. Recorded because the code no longer shows the
wrong version.

### The migration was wrong in five ways (§5, §6)

Its SQL was transcribed verbatim and correctly — a reviewer confirmed it
byte-for-byte — and was still broken, because the source it copied was broken.
Nothing in this repo can execute Postgres, so the only thing that caught these
was a reviewer tracing the PL/pgSQL by hand against specific carts.

1. **The typmods defeated the flooring.** `v_share`, `v_left`, `v_assigned` and
   `v_subtotal` were declared `numeric(12,2)`. **PL/pgSQL coerces to the
   declared typmod on assignment**, so the remainder loop rounded 0.005 of
   headroom up to 0.01 and the line exceeded its own value — violating
   `transactions_discount_within_line`, the constraint this very migration
   adds. The whole floor-don't-round argument in §6 was undone one loop later
   by a variable declaration.
2. **The over-discount guard compared against a rounded bill**, so a discount
   larger than the true subtotal passed it.
3. **A 100% discount on a credit sale rolled back the entire checkout.**
   `customer_ledger.amount` carries `check (amount > 0)`; a zero-total ledger
   insert failed and took the stock decrements with it. §2 explicitly allows a
   discount equal to the total, so this was reachable by design.
4. **A negative `p_discount` was silently ignored** rather than raised.
5. **Then the fix for (3) reintroduced (3).** Guarding `if v_subtotal > 0`
   against the *exact* remainder while inserting into a `numeric(12,2)` column
   means 0.00499 passes the guard and stores as 0.00 — same rollback, narrower
   door. The guard must test the value it stores.

### The consequence nobody's task could see

Fixing (2) moved the maximum legal discount from `subtotal` to
`floor(subtotal × 100) / 100`. Dart's `clampDiscount` still clamped to the raw
subtotal, so the UI would have offered discounts the database rejects — turning
an ordinary checkout into a failure. **This lived in the gap between two tasks**
and was invisible to both task reviewers; it was caught only by holding the
whole plan in view.

Related, from the same fix: `0.29 * 100` is `28.999999999999996` in IEEE 754, so
a bare `.floor()` in the Dart clamp bills 0.28. `_floorPaisa` carries a `1e-9`
epsilon, verified not to promote a genuine 0.005.

### The sheet shipped two silent-money bugs (§8)

1. Typing `1.2.3` — a plausible slip for `1.23` — made `double.tryParse` return
   null, which became `0`, and **Apply then wrote that zero over an
   already-staged discount**. No error; the sheet just closed.
2. The field pre-filled from `'$current'`, rendering a stored 60.0 as `"60.0"`.

The fix for (1) had its own trap worth recording: the obvious repair is to seed
the field with the project's `Money.format`/`Qty.format`, which **localise
digits and add grouping separators** — in Bengali that produces text
`double.tryParse` cannot read back, recreating the silent-zeroing bug in one
locale only. The seed uses a plain ASCII amount, and says so in a comment.

### The whole-branch review found nine more (fixed in one pass)

Task-by-task review passed every task. A review of the **assembled branch**
still found nine defects, six of them in seams no single task owned. The
pattern from §12's opening repeats: what survives per-task review is whatever
requires holding two tasks at once.

1. **The success snackbar reported the gross total.** `_checkout` read
   `cartTotal(lines)` and never subtracted the discount. On credit this was
   worse than cosmetic: `customer_ledger.amount` was written as ৳835 while the
   toast said "Added to Rahim's khata · ৳895", misstating a debt at the moment
   it was created. The discount must be read *before* `checkout()` — a
   successful checkout clears it, so reading it afterwards silently reproduces
   the same gross figure.
2. **`_CheckoutBar` took the NET total and rebuilt the gross** as
   `total + discount` while also watching the discount provider itself. The
   same number in two shapes, one derived from the other in the wrong
   direction — exactly the ambiguity that produced (1). It now takes the GROSS
   and derives the net once, internally.
3. **Dart and Postgres could disagree on the subtotal.** `transactions.quantity`
   is `numeric(10,3)` so the INSERT rounds; `clampCartQuantity` did not. At
   ৳1000/kg a typed 0.1234 gave Dart 123.40 and the database 123.00, so a
   123.40 discount — which the app accepted — made `record_sale_cart` raise
   `Discount exceeds total` and killed the checkout with nothing on screen
   explaining why. This was a **pre-existing, pre-discount bug**: the cart
   already displayed a total the database would not record. The discount only
   turned a silent wrong number into a hard failure.
4. **The last paisa could go unallocated** — see the `sum(floor)` vs
   `floor(sum)` argument in §6. The migration and Dart's cap both changed.
5. **An applied discount could not be edited.** `showDiscountSheet`'s only call
   site was inside the `else` of `if (discount > 0)`, so the sheet could only
   ever open at zero and the seeding logic §12 describes was dead code in
   production. The amount is now a tap target of its own, kept deliberately
   separate from the ✕ so a mis-tap costs a re-open, not the discount.
6. **Two probe steps were unperformable as written.** They told the tester to
   over-discount "in the app" — which `clampDiscount` makes impossible, so the
   tester would see a clean checkout and tick a box having tested nothing.
   Rewritten as direct `select record_sale_cart(...)` calls with an oversized
   `p_discount`. A checklist that cannot fail is worse than no checklist:
   `0009` has still never been executed, and this checklist is the entire
   verification story.
7. **The new widget tests asserted labels, never amounts** — they would have
   passed on a bar showing the gross as the total, or the discount unsigned,
   which is (1) and (2) exactly. Amount assertions added, routed through
   `Money.format` rather than a hardcoded ৳ so they test arithmetic and not
   intl's symbol table.
8. Plus a wrong worked example in the checklist (`45.99 × 2.501` is
   `115.02099`, not `115.02999`) and this document claiming ties break by
   insertion order when the SQL orders by a random uuid.

### What a whole-branch review caught that nine task reviews did not

Each task was reviewed in isolation and passed. Reviewing the branch as one
thing found two Criticals, both of which live in the *gaps* between tasks:

1. **The success snackbar reported the gross total.** Task 8 converted the
   checkout bar to net and Task 5 converted the RPC, but `_checkout`'s own local
   `total` was a third copy nobody's task owned. Every discounted sale confirmed
   the wrong amount — and on credit, the toast misstated the debt at the moment
   it was created. Fixed by passing the **gross** into `_CheckoutBar` and
   deriving the net once, so there is no longer a variable whose meaning depends
   on where you read it.
2. **Dart and Postgres could disagree on the subtotal.** `transactions.quantity`
   is `numeric(10,3)` and rounds on insert; `clampCartQuantity` did not round at
   all. A quantity of `0.1234` gave Dart a subtotal of ৳123.40 and the database
   ৳123.00 — so a near-total discount the app accepted was rejected by the RPC
   and the whole checkout failed, silently and repeatably.

The same pass showed the maximum discount must be **`sum(floor(line))`, not
`floor(sum(lines))`**. On a cart of two ৳112.545 lines the two differ by a
paisa, and the floor-of-sum version permitted a discount the split could not
actually place — quietly falsifying §6's "the sum is exact". Both languages now
use the per-line form; agreement was verified across 200,000 generated carts in
exact integer-paisa arithmetic rather than by inspection.

### Still outstanding

**The migration has never been executed.** Every claim about its behaviour in
this document is a hand-trace. `supabase/README.md` §`0009` carries the probe
checklist, including the paisa case (three ৳100 lines, ৳7 off, `sum` must be
exactly 7.00) and the fractional-quantity credit sale. Apply the migration
**before** installing a build that sends `p_discount` — a new build against the
old function fails *every* sale, not only discounted ones.

### Follow-ups — all five subsequently fixed

These were parked when the review process ran out of fix rounds, then fixed on
request in one pass. Kept here because the reasoning is the valuable part.

1. **Sale detail shows the line's share, not the receipt's discount.** §8 says
   "the group's discount"; `SaleDetailScreen` renders a single `Transaction` and
   gates on that row's `discountAmount`. On a 3-line receipt with ৳7 off, the
   detail reads `Discount −৳2.33` and **the ৳7 the shopkeeper typed appears
   nowhere in History**. Every screen is internally consistent and no money is
   wrong — the stated user need in §2 simply is not met for multi-line receipts,
   which are the only kind the cart exists to make. Fixing it means showing the
   receipt-level figure on the expanded receipt tile in `history_screen.dart`.
2. **The voice path stages an unrounded quantity.** `voice_review_sheet.dart`
   calls `cart.addOrIncrement` with the quantity straight from Member B's JSON,
   bypassing `clampCartQuantity`. It is the one remaining live path where Dart's
   cap can exceed the database's — a model returning `2.5004` for a kg item
   reproduces the failure described above. Pre-existing, but the discount
   feature is what turns it into a failed checkout. Scan is unaffected: it goes
   through `showAddToCartSheet`.
3. **`record_sale_cart`'s over-discount exception prints the raw subtotal, not
   the per-line-floored maximum it compared against** — so the message can read
   as self-contradictory. Unreachable from the app while Dart clamps to the same
   maximum; the probe checklist documents it.
4. **Raw `PostgrestException.message` reaches the shopkeeper**
   (`transaction_repository.dart`), against CLAUDE.md §6's "never raw Postgres
   errors". Pre-existing and consistent with `Insufficient stock: have 3,
   need 5`, so changing it is a separate, app-wide decision.
5. **Unrelated, but found while tracing and worth knowing: a Bengali-only bug in
   the add-to-cart quantity field.** It snaps its text back through
   `Qty.format`, which *localises digits* — so in Bengali the field becomes
   `০.১২৩`, `double.tryParse` returns null on the next edit, and the quantity
   zeroes. This is precisely the trap `discount_sheet.dart` documents avoiding,
   already present in the primary locale.

**How each was closed** (suite 377 → 401):

1. **Receipt discount in History.** `SaleReceipt` gained `discountTotal` and
   `grossRevenue`, and the expanded receipt tile renders one italic
   `Discount −৳7` row under the lines. The database stores no receipt-level
   discount — summing the per-line shares recovers it, which works only because
   the split is exact to the paisa. That exactness stopped being a nicety and
   became load-bearing.
2. **Voice quantity rounding moved down a layer.** `_round3` now runs inside
   `addOrIncrementLine` and `updateLineQuantity`, not only in
   `clampCartQuantity`. Putting it in the sheet's clamp was the bug: the voice
   flow never calls that function, and "every caller is covered" was an
   assumption rather than a fact. Domain functions are where every path meets.
3. **The over-discount exception now names `v_max`**, the value it actually
   compared against, instead of the raw subtotal — which could sit a fraction
   *above* the largest placeable discount and so read as self-contradictory.
4. **Server errors are localised.** `Failure` gained `code` and `detail`;
   `classifyServerMessage` maps our migrations' English sentences to stable
   codes, and `failure_text.dart` translates them. The data layer cannot import
   `l10n`, so classification and translation had to be separated. Tests pin each
   code against the migrations' *exact* text, so rewording a migration fails a
   test rather than silently dropping the app back to English.
5. **The Bengali quantity field.** `add_to_cart_sheet` wrote itself back through
   `Qty.format`, which localises digits — producing `০.১২৩`, which
   `double.tryParse` cannot read. Since the field re-parses on every keystroke,
   one snap-back left text the next edit resolved to `null`, zeroing the
   quantity in the primary locale. Now writes plain ASCII.

**The pattern across (4) and (5), worth naming:** a value formatted for *display*
and a value meant to be *read back* are different things, and `intl` silently
converts the first into something that fails as the second. The discount sheet
documented this trap; the older sheet had been living inside it.
