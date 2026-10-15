---
tags: [moc, index]
---

# 📍 Project Map — start here

This is the front door to the design/planning history in this repo. Read **this
file first** when a task needs background on a past feature — it's one short
file instead of grepping through 30+ plan/spec docs.

Each feature below has up to two docs:
- **Design** — the *why*: problem statement, options considered, tradeoffs.
- **Plan** — the *what/how*: the task-by-task build log, checkbox-tracked.

Newest first within each area. A missing Plan means the Design was exploratory
or superseded before a build plan was written — the Design alone still has the
reasoning.

> Nothing below is auto-loaded. [[CLAUDE.md]] is read every session; open a
> link here only when the current task actually touches that area.

## Core project docs
- [[CLAUDE.md]] — ownership, DB schema, `record_sale` RPC contract, RLS, working agreements
- [[README]] — Flutter boilerplate pointers
- [[RUN]] — run the app against Supabase (`dart_defines.json`, build commands)
- [[claude_code_kickoff_prompt]] — the original project-kickoff prompt (historical, rarely needed)
- Supabase
  - [[supabase/README|Supabase project setup]] — hosted project + applying `migrations/0001_init.sql`
  - [[supabase/functions/parse-sale/README|parse-sale Edge Function]] — voice sentence → sale line items (Gemini)
  - [[supabase/functions/recognize-product/README|recognize-product Edge Function]] — item photo → matched product (Gemini vision)

## Voice sale
- [[2026-08-05-voice-wait-ux-design|Design]] (no separate plan — built straight from the brief) — shorten the post-speech wait and let the parse finish in the background; **records why chunked upload was rejected**, plus two follow-up fixes to the background banner (§8 the dead zone where a parsing sale was invisible and the mic silently ate it; §9 why a widget mounted above `MaterialApp.router` cannot push a route — and why the test suite stayed green through both)
- [[2026-07-27-voice-noise-latency-design|Design]] / [[2026-07-27-voice-noise-latency|Plan]] — fix ~30s timeout hang in noisy environments
- [[2026-07-27-voice-brain-gemini-migration-design|Design]] (no separate plan — folded into the scan/voice migration below) — merge transcribe+parse into one Gemini 3.6 Flash call
- [[2026-07-22-voice-sale-assistant-design|Design]] / [[2026-07-22-voice-sale-assistant|Plan]] — "speak a sale → cart" voice assistant, on-device speech-to-text pivot

## Vision scan
- [[2026-08-10-fast-scan-session-design|Design]] / [[2026-08-10-fast-scan-session|Plan]] — live viewfinder + background recognition + one review tray, replacing the serial camera→wait→sheet loop (~40 taps/75s → ~11 taps/20s for ten items); **records why the per-item confirmation sheet was a safety mechanism and what its removal costs** (§8), why one-photo-many-items and barcodes were rejected (§2), that the prompt re-sends the whole catalog every scan and ~90% of spend is that list not the photo (§6), and that the Edge Functions must deploy BEFORE the app or scans silently degrade to "no match" (§6.1). Final whole-branch review fix wave: `.superpowers/sdd/2026-08-10-fast-scan-session/final-fix-report.md` — an overlapping shutter tap silently swallowed (uncaught throw + no in-flight guard), a scrim tap on the leave-confirm dialog discarding the tray and exiting (`barrierDismissible` true + null mapped to Discard), a non-permission camera fault leaving a dead spinner forever, a concurrent `initialize()` race leaking a bound `CameraController` (generation-counter fix, reasoned through by hand — the file has no test seam), a sub-threshold single match silently auto-resolving instead of asking (the §8 auto-resolve confidence lever moving from 0.80 to 0.50 unnoticed), and "Open settings" not opening settings (relabelled to "Try again" — a recorded downgrade from spec §7, not wired to `permission_handler`/`app_settings`)
- [[2026-07-27-scan-gemini-migration-design|Design]] / [[2026-07-27-scan-gemini-migration|Plan]] — migrate `recognize-product` off Frog/OpenAI to Gemini 3.6 Flash direct
- [[2026-07-27-scan-quantity-confirmation-design|Design]] / [[2026-07-27-scan-quantity-confirmation|Plan]] — confirm sheet for scanned quantity before committing
- [[2026-07-04-vision-product-scan-design|Design]] / [[2026-07-04-vision-product-scan|Plan]] — original camera → Gemini/OpenAI closed-set product match

## Scan + voice (cross-cutting)
- [[2026-07-27-qol-scan-voice-batch1-design|Design]] / [[2026-07-27-qol-scan-voice-batch1|Plan]] — show AI read-back on scan, edit misheard transcript + re-parse, undo last cart add

## Dashboard / Home
- [[2026-07-02-dashboard-day-drilldown-design|Design]] / [[2026-07-02-dashboard-day-drilldown|Plan]] — tap a day on the trend chart to drill into that day's sales
- [[2026-06-26-dashboard-redesign-design|Design]] (no separate plan) — Home tab redesign
- [[2026-06-23-kalo-dark-ui-redesign-design|Design]] / [[2026-06-23-kalo-dark-ui-redesign|Plan]] — the "Kalo-dark" visual theme rebuild

## Reports / Analytics
- [[2026-06-27-reports-tab-redesign-design|Design]] (no separate plan) — Analytics tab redesign

## History (transactions)
- [[2026-07-21-history-sale-detail-design|Design]] / [[2026-07-21-history-sale-detail|Plan]] — tap a past sale to see its line-item detail
- [[2026-07-03-history-calendar-day-filter-design|Design]] / [[2026-07-03-history-calendar-day-filter|Plan]] — calendar day filter + shop-lifetime floor date

## Restock planner
- [[2026-10-15-restock-planner-design|Design]] (spec, not built yet) — "what to restock and how much" from a 4-week weighted sales speed (0.4/0.3/0.2/0.1) that skips out-of-stock days, so one spike week doesn't drive the buy; why not Gemini or a threshold-only alert; speed in Postgres, days-left/suggestion in Dart.

## Inventory
- [[2026-10-14-product-expiry-design|Design]] / [[2026-10-14-product-expiry|Plan]] (built 2026-10-14; migrations 0011–0015) — expiry date per delivery, in-app alerts + a daily phone reminder, expired stock never sold by default. **Records why one date per product and exact lot tracking were rejected**, the shelf-life warning rule (bread warned the day before, not on arrival), why the expired count must be locked once (or sales silently eat it), that dates must be the phone's local date (server UTC is "yesterday" before 6 AM in Bangladesh), and that adjustment rows must be positive (0009's discount check). Phone reminder built here by the user's choice despite Member C owning notifications. **§11 is a 24-item edge-case review** — notably sold-out deliveries must auto-close (or an undated restock revives them as a false alarm), checkout must wait for expired-count locks, a batch needs a composite `(product_id, shop_id)` key because RLS only checks `shop_id`, and restock is made retry-safe in the same migration. Reconcile reads deliveries BEFORE stock, because the two streams refresh independently and a restock's delivery arriving first would close the old delivery as sold out. **§12 records the final review: the new cart block had undone 0010 (an unanswered identical retry must always get past any check in front of `record_sale_cart`)**, plus offline start cancelling reminders and the 1000-row cap. **§13 (2026-10-15): pick the batch at checkout** — a per-delivery `picked_qty` counted inside `record_sale_cart` (not lot tracking; why the two alternatives were rejected), the cart defaulting to soonest-expiry-first with every part naming its delivery, why an unanswered retry must re-send its old split rather than re-split (else a double sale), and why reconcile now reads deliveries + stock in ONE joined request (a picked sale between two reads would close an old delivery that still has stock). **§14: "None left" removed** — it closed a delivery without lowering stock, so items thrown away a day early stayed sellable; every unexpired delivery now has "Remove from stock" (`remove_batch_stock`, 0013, needs 0012). **§15: remove part of a delivery** — "How many?" on Remove; a partial removal counts as a pick so the right batch loses the units (hand-editing stock takes them from the oldest batch), and it needed a phone-minted removal id because an open delivery can no longer use "already closed" to catch a retry (0014). **§16: stock moves only through sales, Restock and Remove** — Edit product lost its stock box (`toUpdateRow` never writes stock), Edit delivery shows its amount read-only, and undated stock (all of a soap's) got its own "No expiry date" row with Remove (0015); records the accepted gap of an over-dated batch. **§17: the seller must choose the batch** — several batches means "Choose" and checkout waits, one batch is shown with no tap; "several batches, soonest expiry first" survives only when no single batch holds the line (why not one cart line per batch). **§18: "Thrown away: N pcs · ৳X lost"** replaces the Closed list — summed from removal `adjustment` rows at their frozen buying price; closed rows stay in the DB. **§19: identical deliveries merge** (0016) — same expiry, date added and buying price join one row via a `BEFORE INSERT` trigger (why a trigger, why price must match); existing duplicates merged once.

## Sale cart
- [[2026-10-14-sale-cart-idempotent-design|Design]] (no separate plan — bounded fix) — a retry after a lost reply could record a sale twice; the phone now mints the sale id and `record_sale_cart` records an id once (migration `0010`). **Records why the replay check must run before the stock check**, why an advisory lock (not a unique column), why a changed cart gets a new id, and that **0010 must be applied before the app ships or every checkout fails**. `0010` is applied (2026-10-14)
- [[2026-08-06-cart-discount-design|Design]] / [[2026-08-06-cart-discount|Plan]] — flat-amount discount before cashout, split across the transaction rows. **Records why a separate `sale_discounts` table was rejected** (grain mismatch double-counts a multi-line receipt), why the split floors rather than rounds, and — in §12 — what review caught afterwards. Two rounds of it: five defects in the migration (including that **PL/pgSQL rounds on assignment to a declared typmod**, which silently undid the flooring the whole design rests on), then two Criticals that nine per-task reviews had each passed — a **gross** total in the success snackbar, misstating every discounted sale and every khata debt, and `numeric(10,3)` quantity rounding that let Dart and Postgres disagree on the bill. Also records why the cap is `sum(floor(line))` and not `floor(sum(line))`. Migration `0009` is applied (verified 2026-10-14: the live function body matches the repo).
- [[2026-07-07-sale-cart-design|Design]] / [[2026-07-07-sale-cart|Plan]] — multi-line cart before committing to `record_sale_cart`

## Customer credit
- [[2026-07-17-customer-credit-khata-design|Design]] / [[2026-07-17-customer-credit-khata|Plan]] — "khata" running-credit ledger per customer

## Onboarding
- [[2026-07-11-onboarding-redesign-design|Design]] / [[2026-07-11-onboarding-redesign|Plan]] — first-time setup flow redesign

## Localization
- [[2026-07-11-bengali-localization-design|Design]] / [[2026-07-11-bengali-localization|Plan]] — Bengali translation + in-app language switcher

## Reliability
- [[2026-07-12-offline-banner-design|Design]] / [[2026-07-12-offline-banner|Plan]] — app-wide "no internet" banner

---

### Keeping this map useful
Design and plan docs live in `docs/superpowers/specs/` and
`docs/superpowers/plans/` as `YYYY-MM-DD-feature-slug[-design].md` — that
convention is what makes the `[[wikilink]]`s above resolve without a folder
path. **Add one line to the right section above whenever a new doc lands**, so
this file stays the single place both you and I look first instead of
re-scanning the whole `docs/` tree.

This holds for work built straight from a conversation, not only for work
driven by a `superpowers` skill — see the rule in
[[CLAUDE.md]] §10. Skill-less work is the case most likely to leave this map
quietly incomplete, because nothing automatic prompts the entry. A doc is
worth writing for anything a future session would want the *reasoning* for,
including approaches that were investigated and **rejected**; the map notes
which entries carry a rejection record, since those are the ones that stop the
same analysis being redone.
