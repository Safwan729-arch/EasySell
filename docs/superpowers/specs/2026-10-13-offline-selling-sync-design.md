# Offline Selling with Supabase Sync — Design (parked)

**Date:** 2026-10-13
**Status:** **Parked.** The idea is agreed and recorded here, but the user chose
not to build it yet. The design is unfinished: scope is decided, approaches and
detailed sections were never presented or approved. Resume at "Open questions"
before writing a plan.
**Supersedes:** the 2026-08-06 decision to keep Supabase-only for the MVP (that
analysis was never written up; its findings are folded in below).
**Related:**
- [[2026-10-13-futuremakers-business-plan]] — §11 lists "every sale needs
  internet" as a top business risk; TallyKhata, the main competitor, works offline
- [[2026-07-07-sale-cart-design]] — `record_sale_cart`, the function this changes
- [[2026-08-06-cart-discount-design]] — the discount split the phone would have to
  reproduce exactly (`discount_math.dart` already mirrors the SQL)
- [[2026-07-12-offline-banner-design]] — today's only offline behaviour: a banner

## 1. Problem

Every sale needs internet today. In rural areas the signal is weak or absent, so
a sale either fails while the customer waits or takes a long time to record.
Rural shops are exactly the users the social-impact case is built on.

## 2. Decisions so far

| Decision | Why |
|---|---|
| **Phone first, Supabase as backup/sync**, not phone-only | Phone-only fails one test that outweighs everything else: a lost, stolen or broken phone **wipes the shop's sales history and khata (money owed to the shop)**. It would also kill the loan-referral and sponsored-shop income in the business plan, and owner + helper on two phones |
| **Supabase cannot be removed either way** | Voice and scan call Gemini from Edge Functions. A Gemini key shipped in the APK is extractable, so a server is required while the AI features exist. The question was only ever *where the shop's data lives* |
| **Stage 1 = selling only** (chosen by the user) | Cart sales (cash and baki to an existing customer), plus reading products and customers offline. Everything else keeps needing internet in stage 1. Chosen because a small change is easier to test on the real phone and safer for stock and khata |
| **Stage, don't build everything at once** | Code effort for "everything offline" is a few days of Claude work, not weeks. The real bottlenecks are (a) on-device testing — toggling signal mid-sale on the physical S22, which only the user can do — and (b) money correctness. Staging keeps each change testable |

**Rejected: phone-only storage.** Reasons are in the first row above. Space is
*not* a reason against it (§4).

## 3. Findings from the code (2026-10-13)

These are what make offline harder than "cache the data", and each needs a
server change:

1. **The server mints the sale id.** `record_sale_cart` sets
   `v_group := gen_random_uuid()` (0009). A retry after a lost response records
   the sale **twice**, and that can happen **today** on weak internet, not just
   offline. Fix: the phone generates `sale_group_id`; the function becomes
   idempotent (a second call with the same id returns the existing rows).
   **Done 2026-10-14** — see [[2026-10-14-sale-cart-idempotent-design]]
   (migration `0010`). Offline sync can reuse `p_sale_group_id` as-is; it
   only needs to persist the id with the queued sale.
2. **The server rejects low stock.** `raise exception 'Insufficient stock...'`.
   An offline sale has already happened at the counter, so rejecting it at sync
   time is wrong. Combined with `check (quantity >= 0)` on `products`, a sale
   that syncs after stock was changed elsewhere cannot be stored as-is (see open
   question 2).
3. **Prices are read at sync time, not sale time.** The function copies the
   product's *current* `buying_price`/`selling_price`. A sale synced hours later,
   after a price edit, would freeze the wrong price — breaking the "prices are
   snapshots at sale time" rule in CLAUDE.md §4. Fix: the phone sends the prices
   it sold at, and the server stores those.
4. **Sale time is the server's `now()`.** Offline sales need the phone's sale
   time (`p_sold_at`), with a guard against a badly wrong phone clock.
5. **Surface area:** 7 repositories and about 25 data methods touch Supabase; all
   access goes through repositories, so the UI barely changes. The server logic
   is the real cost: ~19 Postgres functions, 9 tables, 9 RLS policies. Stage 1
   only needs `record_sale_cart` plus read caches of products and customers.

## 4. Phone storage is not a concern

Measured on the live database: **~130 bytes per transaction row** (306 rows),
~159 per product. With local indexes, assume ~300 bytes per sale line.

| Data | Size |
|---|---|
| Typical shop, 100 sale lines/day | ~10 MB / year |
| Busy shop, 200 lines/day | ~20 MB / year |
| 1,000-product catalog, khata | under 1 MB each |
| Queued voice clip / photo (stage 2) | 100–300 KB each, deleted once processed |

The app stores no product photos, and scan photos are not kept. If ever needed,
keep the last 12 months on the phone and older history on the server.

## 5. Stages

| Stage | Scope | Notes |
|---|---|---|
| **1. Offline selling** | Cart checkout (cash; baki to an existing customer; discount) saved locally and queued; products and customers cached for reading; sync queue replays sales to an idempotent `record_sale_cart`; a visible "N sales waiting to sync" count | Server changes from §3 |
| **2. AI later** | With no signal, record the voice clip or photo, mark the sale "waiting", run Gemini when signal returns, and let the shopkeeper approve a batch ("3 sales to check") | Keeps the AI features usable offline, only delayed. The confirm-before-commit rule still holds |
| **3. Everything else offline** | Add/edit products, restock, create customers, record payments, categories | Needs conflict rules for edits |
| **4. Offline reports** | Dashboard and analytics computed on the phone | Today these are Postgres RPCs |

## 6. Open questions (resume here)

1. **Phones per shop.** One phone (simple — no two devices can sell the last
   unit) or several (needs conflict rules). Was being asked when the work was
   parked.
2. **A synced sale exceeds server stock.** Proposal, not agreed: accept the sale
   (it really happened), floor stock at 0, and flag a "stock didn't add up" item
   for the shopkeeper to review instead of failing.
3. **Local database choice** (e.g. drift vs sqflite). Decide in the plan.
4. **First launch** needs internet to download the catalog. Is that acceptable?
5. **Dashboard during stage 1.** Show unsynced sales in today's totals locally,
   or show server totals plus a "waiting to sync" note?
6. **Login offline.** Supabase keeps the session on the phone, but a token
   refresh fails offline. Confirm the app stays usable on an expired token and
   re-auths on reconnect.
7. **Phone clock trust.** How far can a phone's `sold_at` drift from server time
   before it's rejected or clamped?

## 7. Related fix, independent of this one

The AI cost fix (send a ~60-product shortlist instead of the whole catalog, and
move scan to Flash-Lite) is separate from offline and should land first. Without
it a ৳299 shop loses ~৳81/month (see the business plan). A shorter prompt also
means smaller uploads, which helps on weak internet.
