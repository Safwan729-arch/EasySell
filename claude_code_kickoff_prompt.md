# Claude Code Kickoff Prompt — AI Shopkeeper Assistant (Member A)

> Paste the prompt below into Claude Code at the **root of an empty repository**, with the
> `CLAUDE.md` file already placed there. It is written to be pasted in one go. Sections are ordered
> so Claude builds the riskiest, most foundational pieces first.

---

## THE PROMPT

You are helping me build **my part** of the *AI Shopkeeper Assistant* — a Flutter + Supabase app that
lets small grocery shopkeepers manage inventory, sales, and profit. I am **Member A**, responsible for
the **Flutter frontend and the Supabase backend only**. The Gemini/AI layer and the device plugins
(camera, speech, push) are owned by teammates — I integrate with them but do not build them.

**Before doing anything, read `CLAUDE.md` in the repo root and treat it as the source of truth** for
stack, folder layout, schema, conventions, and working agreements. If anything I ask conflicts with
CLAUDE.md, point it out before proceeding.

### Stack (non-negotiable)
Flutter (Dart, Material 3) · Riverpod · go_router · freezed + json_serializable · supabase_flutter ·
Supabase Postgres / Auth / Storage / Edge Functions / Realtime. Do not introduce other state managers,
backends (Firebase is Member C's concern for FCM only), or REST wrappers around Supabase.

### How I want you to work
- Work in **small, reviewable increments**. After each milestone below, stop and summarize what you
  built and what I should verify before continuing. Do not build everything in one pass.
- Explain non-obvious decisions briefly as you go. Keep widgets dumb; logic lives in
  controllers/repositories.
- Where a teammate owns the seam, **stub it** and leave a `// MEMBER B` or `// MEMBER C` comment with a
  short note on the expected data contract — do not implement their parts.
- Never hardcode secrets. Supabase URL/anon key come from `--dart-define`. Add a `.env.example`.
- After generating code, run `flutter analyze` and `dart format .` and fix what they flag.

---

### Milestone 0 — Project scaffold
Create the Flutter project and the exact folder structure described in CLAUDE.md (feature-first:
`core/`, `features/<feature>/{data,domain,presentation}`, `shared/`, `supabase/migrations`,
`supabase/functions`). Set up:
- `main.dart` with `Supabase.initialize` (keys from `--dart-define`) wrapped in `ProviderScope`.
- `app.dart` with `MaterialApp.router`, a Material 3 theme in `core/config/theme.dart`.
- `core/router/app_router.dart` with go_router and an auth-redirect guard (placeholder routes ok).
- `pubspec.yaml` with the agreed dependencies and the `Result<T>` + `Failure` types in `core/error/`.
- `.env.example` listing `SUPABASE_URL` and `SUPABASE_ANON_KEY`.

Stop and show me the tree and `pubspec.yaml`.

### Milestone 1 — Database foundation (highest priority)
In `supabase/migrations/`, write a single ordered SQL migration that creates the schema from CLAUDE.md:
`users`, `shops`, `products`, `transactions`, `analytics_daily`, `notifications`, with the exact columns,
constraints, and checks specified. Then:
- Enable **Row Level Security** on every table, shop-scoped to `auth.uid()` via `shops.owner_id`.
- Implement the **`record_sale` RPC exactly as written in CLAUDE.md** — row lock, stock check, atomic
  decrement + transaction insert, prices frozen on the row. This is the most important artifact in the
  project; get it exactly right.
- Add a `record_restock` RPC mirroring it for inventory increases (type `'restock'`, increments stock).
- Add a `get_dashboard_summary(p_shop_id, p_period)` function returning revenue, cost, profit,
  inventory value computed **live from `transactions`** (do not depend on `analytics_daily`).

Explain how I run these migrations locally, then stop for review.

### Milestone 2 — Auth module
Build the auth feature end-to-end: `auth_repository` (email + Google sign-in via Supabase Auth),
`auth_controller` (Riverpod AsyncNotifier), `login_screen`, and `profile_setup_screen` (creates the
user's `shop` row on first login). Wire the go_router guard to redirect unauthenticated users to login.
Surface failures as friendly messages, never raw Postgres/Auth errors. Stop for review.

### Milestone 3 — Inventory module
Build the inventory feature as the **template** other features will follow:
- `product.dart` domain model (freezed + json_serializable).
- `product_repository` (CRUD against Supabase, returns `Result<T>`).
- `inventory_controller`, `inventory_list_screen` (search + filter + low-stock indicator),
  `product_form_screen` (add/edit), `product_detail_screen`.
- Subscribe to **Supabase Realtime** on `products` so stock changes appear live.
Stop for review.

### Milestone 4 — Transactions + sale flow
Build `transaction_repository` and `transaction_controller` that call the `record_sale` /
`record_restock` RPCs (never client-side stock math). Add a reusable **confirmation sheet** widget:
any sale arriving from voice/image (Member B's parsed JSON) must pass through this sheet before
committing. For now, drive it from a manual "record sale" button on the product detail screen; leave a
`// MEMBER B` seam where parsed-intent JSON will arrive. Stop for review.

### Milestone 5 — Dashboard + analytics
Build `dashboard_screen` with revenue and profit cards and `analytics_screen` with period summaries,
all backed by `get_dashboard_summary` / Postgres views (computation stays in the database; Flutter only
renders). Add simple charts for daily/weekly/monthly revenue and profit. Stop for review.

### Milestone 6 — Insights, trends, settings (read-only + shell)
- `insights_screen` and `trend_screen` that **render JSON produced by Member B** from the `insights` /
  `trend_data` tables, read-only. Define the expected JSON shape in comments as a contract.
- `settings_screen` (profile, shop info, sign out).
- Reorder-alert surface: a dashboard banner when any product is at/below its threshold (the push side is
  Member C's; I only show the in-app alert).
Stop for review.

---

### Definition of done for my scope
- Auth → shop creation → inventory CRUD → record a sale via `record_sale` → dashboard/analytics update —
  all working against Supabase with RLS enforced.
- No client-side stock arithmetic anywhere; all stock changes go through the RPCs.
- All AI/voice/image and notification points are clean, well-commented stubs ready for Members B and C.
- `flutter analyze` is clean and the app builds a release APK with `--dart-define` secrets.

Begin with **Milestone 0**. After each milestone, pause and wait for my go-ahead before continuing.

---

## Notes for you (not part of the prompt)

- **Paste location:** run this from the repo root with `CLAUDE.md` already committed there, so Claude
  Code reads it as project memory.
- **One milestone at a time:** the prompt tells Claude to pause between milestones — this keeps diffs
  reviewable and lets you catch a wrong assumption (e.g. the `shops.owner_id` column name) early instead
  of after six features are built on top of it.
- **If your team chose Bloc/Provider instead of Riverpod**, change the stack line and Milestone 0/2/3
  wording before pasting, and update CLAUDE.md to match.
- **The `record_sale` RPC is the crux.** When you review Milestone 1, test it deliberately: try selling
  more than the available stock and confirm it raises an error and does *not* record a transaction.
