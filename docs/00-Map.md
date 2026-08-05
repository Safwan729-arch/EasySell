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
- [[2026-07-27-voice-noise-latency-design|Design]] / [[2026-07-27-voice-noise-latency|Plan]] — fix ~30s timeout hang in noisy environments
- [[2026-07-27-voice-brain-gemini-migration-design|Design]] (no separate plan — folded into the scan/voice migration below) — merge transcribe+parse into one Gemini 3.6 Flash call
- [[2026-07-22-voice-sale-assistant-design|Design]] / [[2026-07-22-voice-sale-assistant|Plan]] — "speak a sale → cart" voice assistant, on-device speech-to-text pivot

## Vision scan
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

## Sale cart
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
New feature work under `superpowers:brainstorming` / `superpowers:writing-plans`
still lands in `docs/superpowers/plans/` and `docs/superpowers/specs/` as
`YYYY-MM-DD-feature-slug[-design].md` — that convention is what makes the
`[[wikilink]]`s above resolve without a folder path. **Add one line to the
right section above whenever a new plan/spec pair lands**, so this file stays
the single place both you and I look first instead of re-scanning the whole
`docs/` tree.
