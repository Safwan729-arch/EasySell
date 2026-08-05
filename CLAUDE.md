# CLAUDE.md — AI Shopkeeper Assistant (Member A: Flutter + Supabase)

This file guides Claude Code when working on **my part** of the AI Shopkeeper Assistant project.
Scope: **Frontend (Flutter)** and **Backend (Supabase)**. The AI/Gemini layer (Member B) and the
device plugins/QA layer (Member C) are owned by teammates — I integrate with their contracts but do
not implement them.

---

## 1. Project Context

**Product:** AI Shopkeeper Assistant — an app that lets small grocery/retail shopkeepers manage
inventory, sales, and profit through voice, images, and Gemini-powered insights.

**My ownership (Member A — Full Stack Product Lead):**
- Flutter UI: Auth, Dashboard, Inventory, Analytics, AI Insights, Trend Dashboard, Settings, Navigation
- Supabase: schema design, auth, storage, Row Level Security, business logic (Postgres functions/RPC),
  analytics queries, deployment
- Deliverables: Authentication Module, Inventory Module, Transaction Module, Dashboard, Analytics, Deployment

**Not my ownership (integrate, don't build):**
- Gemini prompts / intent parsing / vision / insights generation (Member B) — I consume their JSON output
- Camera, speech-to-text, push notification plugins (Member C) — I provide the screens/hooks they wire into

**Timeline:** 10-day MVP. Prioritize correctness of transactions and inventory over polish.

---

## 2. Tech Stack (my layers only)

| Layer | Choice |
|---|---|
| App framework | Flutter (stable channel), Dart |
| UI | Material 3 |
| State management | Riverpod (`flutter_riverpod`) |
| Routing | `go_router` |
| Backend SDK | `supabase_flutter` |
| Database | Supabase PostgreSQL |
| Auth | Supabase Auth (email, Google, optional phone OTP) |
| Storage | Supabase Storage (product images) |
| Server logic | Supabase Edge Functions + Postgres functions (RPC) |
| Realtime | Supabase Realtime (inventory/analytics live updates) |

**Do not introduce** other state managers (Bloc/GetX), other backends (Firebase except FCM owned by
Member C), or REST wrappers around Supabase. Use the `supabase_flutter` client directly via repositories.

---

## 3. Repository Layout

Feature-first structure. Keep data/domain/presentation separated per feature.

```
lib/
  main.dart                  # App entry, Supabase.initialize, ProviderScope
  app.dart                   # MaterialApp.router, theme, router config
  core/
    config/
      supabase_config.dart   # URL + anon key from --dart-define (never hardcode)
      theme.dart             # Material 3 theme, colors, text styles
    router/
      app_router.dart        # go_router routes + auth redirect guard
    error/
      failure.dart           # Failure types
      result.dart            # Result<T> wrapper for repo returns
    widgets/                 # Shared widgets (buttons, loaders, empty states)
  features/
    auth/
      data/auth_repository.dart
      presentation/
        login_screen.dart
        profile_setup_screen.dart
        auth_controller.dart       # Riverpod controller (AsyncNotifier)
    inventory/
      data/product_repository.dart
      domain/product.dart          # Product model (freezed/json_serializable)
      presentation/
        inventory_list_screen.dart
        product_form_screen.dart
        product_detail_screen.dart
        inventory_controller.dart
    transactions/
      data/transaction_repository.dart
      domain/transaction.dart
      presentation/
        transaction_controller.dart
    dashboard/
      presentation/
        dashboard_screen.dart
        revenue_card.dart
        profit_card.dart
    analytics/
      data/analytics_repository.dart
      presentation/
        analytics_screen.dart
        analytics_controller.dart
    insights/
      presentation/insights_screen.dart   # renders Member B's insight JSON
    trends/
      presentation/trend_screen.dart       # renders Member B's trend JSON
    settings/
      presentation/settings_screen.dart
  shared/
    providers/
      supabase_provider.dart     # exposes Supabase client
    extensions/
supabase/
  migrations/                    # SQL migrations (schema, RLS, functions)
  functions/                     # Edge Functions (Deno/TypeScript)
```

---

## 4. Database Schema (Supabase / Postgres)

Tables I own: `users`, `shops`, `products`, `transactions`, `analytics_daily`, `notifications`.
(`insights` and `trend_data` are written by Member B's Edge Functions; I only read them.)

### products
```
id                uuid primary key default gen_random_uuid()
shop_id           uuid not null references shops(id) on delete cascade
name              text not null
brand             text
variant           text
category          text
quantity          integer not null default 0 check (quantity >= 0)
buying_price      numeric(10,2) not null default 0
selling_price     numeric(10,2) not null default 0
reorder_threshold integer not null default 0
image_urls        text[] default '{}'
created_at        timestamptz default now()
updated_at        timestamptz default now()
```

### transactions
```
id             uuid primary key default gen_random_uuid()
shop_id        uuid not null references shops(id) on delete cascade
product_id     uuid not null references products(id)
type           text not null check (type in ('sale','restock','adjustment'))
quantity       integer not null
buying_price   numeric(10,2) not null   -- frozen at transaction time
selling_price  numeric(10,2) not null   -- frozen at transaction time
source         text check (source in ('voice','image','manual'))
created_at     timestamptz default now()
```

**Rule:** prices on a transaction are **snapshots taken at sale time**. Never join transactions back to
the current product price for historical reporting — read the frozen values on the row.

### Atomic sale function (critical — always use this, never client-side stock math)

Stock decrement + transaction insert MUST be atomic. Implement as a Postgres RPC so a sale can never
record without decrementing stock, and stock can never go negative.

```sql
create or replace function record_sale(
  p_shop_id uuid,
  p_product_id uuid,
  p_quantity integer,
  p_source text default 'manual'
) returns transactions
language plpgsql
as $$
declare
  v_product products;
  v_txn transactions;
begin
  -- Lock the row to prevent concurrent oversell
  select * into v_product from products
    where id = p_product_id and shop_id = p_shop_id
    for update;

  if v_product is null then
    raise exception 'Product not found';
  end if;

  if v_product.quantity < p_quantity then
    raise exception 'Insufficient stock: have %, need %', v_product.quantity, p_quantity;
  end if;

  update products set quantity = quantity - p_quantity, updated_at = now()
    where id = p_product_id;

  insert into transactions(shop_id, product_id, type, quantity, buying_price, selling_price, source)
  values (p_shop_id, p_product_id, 'sale', p_quantity,
          v_product.buying_price, v_product.selling_price, p_source)
  returning * into v_txn;

  return v_txn;
end;
$$;
```

Flutter calls this via `supabase.rpc('record_sale', params: {...})`. The voice and image flows
(from Members B/C) ultimately resolve to this same RPC.

### Row Level Security
Every table is shop-scoped. Enable RLS on all tables and restrict rows to the authenticated user's shop.

```sql
alter table products enable row level security;
create policy "shop members read/write own products"
  on products for all
  using (shop_id in (select id from shops where owner_id = auth.uid()))
  with check (shop_id in (select id from shops where owner_id = auth.uid()));
```
Apply the equivalent policy to `transactions`, `analytics_daily`, and `notifications`.

---

## 5. Analytics

**Decision for MVP: compute analytics live from `transactions` via SQL, not from a maintained
`analytics_daily` rollup.** Data volumes during the build are tiny; live aggregation is simpler and
avoids rollup-sync bugs. Keep `analytics_daily` in the schema as a future optimization but do not
depend on it for the demo.

Formulas:
- Revenue = `selling_price * quantity` (sales only)
- Cost = `buying_price * quantity` (sales only)
- Profit = Revenue − Cost
- Inventory Value = `buying_price * quantity` (current stock)
- Inventory Turnover = Units Sold ÷ Average Inventory

Expose these as Postgres views or RPC functions (e.g. `get_dashboard_summary(p_shop_id, p_period)`)
so the heavy lifting stays in the database and Flutter just renders numbers.

---

## 6. Frontend Conventions

- **State:** Riverpod `AsyncNotifier`/`Notifier` controllers per feature. UI watches providers; no
  business logic in widgets.
- **Data access:** Repositories wrap the Supabase client. Controllers call repositories, never the
  Supabase client directly from widgets.
- **Models:** Use `freezed` + `json_serializable` for domain models. Map Supabase rows in repositories.
- **Errors:** Repositories return a `Result<T>` (success/failure); controllers surface failures as
  `AsyncError`. Show user-friendly messages, never raw Postgres errors.
- **Routing:** `go_router` with an auth-redirect guard (unauthenticated → login).
- **Realtime:** Subscribe to `products` changes on the inventory screen so stock updates from voice/image
  flows appear live.
- **AI confirmation UI:** When a sale/product originates from voice or image (Member B's parsed JSON),
  show a **confirmation sheet** before committing the `record_sale` RPC. Never auto-commit AI output.

---

## 7. Integration Contracts (with teammates)

- **Member B (AI):** provides parsed intent as JSON, e.g.
  `{ "action": "sale", "product": "Pepsi", "variant": "500ml", "quantity": 10 }`.
  I resolve `product` + `variant` to a `product_id` (fuzzy match → confirmation UI), then call
  `record_sale`. Insights/trends arrive as JSON in `insights`/`trend_data`; I render them read-only.
- **Member C (mobile):** owns mic/camera/notification plugins. I expose screens and callbacks they
  trigger (e.g. "voice result ready" → open confirmation sheet; "image captured" → upload to Storage,
  hand URL to Member B's vision function).

---

## 8. Environment & Config

- Supabase URL and anon key passed via `--dart-define` (e.g. `SUPABASE_URL`, `SUPABASE_ANON_KEY`).
  **Never hardcode keys or commit them.**
- Use the anon key on-device; service-role key only inside Edge Functions, never in the app.
- Provide a `.env.example` listing required defines.

---

## 9. Commands

```bash
# Setup
flutter pub get

# Run (with secrets)
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...

# Codegen (freezed/json_serializable)
dart run build_runner build --delete-conflicting-outputs

# Analyze & format
flutter analyze
dart format .

# Tests
flutter test

# Build release
flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...

# Supabase (local migrations)
supabase migration new <name>
supabase db push
```

---

## 10. Working Agreements for Claude Code

- **Always use the `record_sale` RPC** for sales. Never decrement stock with separate client calls.
- **Freeze prices** on transaction rows; never recompute historical profit from current product prices.
- **Enable RLS** on every new table and scope it to the shop.
- Keep widgets dumb; logic lives in controllers/repositories.
- Prefer Postgres views/RPC for aggregation over pulling raw rows into Dart.
- Don't implement Gemini prompts or device plugins — stub the integration points and leave a `// MEMBER B`
  or `// MEMBER C` comment at the seam.
- When unsure about a teammate's data shape, propose a contract in the integration section and flag it,
  rather than guessing silently.
- Match the established folder structure; new features follow the `data/domain/presentation` pattern.
- **Every substantive piece of work gets a design doc and a map entry — whether or not a skill
  wrote it.** "Substantive" means anything a future session would want the reasoning for: a new
  feature, a behaviour change users can notice, a non-obvious fix, or an option investigated and
  **rejected**. Trivial edits (typos, formatting, a renamed variable) do not qualify.
  - Write it to `docs/superpowers/specs/YYYY-MM-DD-feature-slug-design.md`. That naming is what
    makes the `[[wikilink]]`s in the map resolve without a folder path.
  - Add one line for it to the matching section of [`docs/00-Map.md`](docs/00-Map.md) **in the same
    turn**. That file is the index I read first for feature history instead of scanning the whole
    `docs/` tree, and it goes stale the moment a doc lands without a corresponding entry.
  - Record *why*, not *what* — the diff already says what changed. Capture the decisions that are
    not recoverable from the code: thresholds and why they sit where they do, approaches ruled out
    and the evidence that ruled them out, and any gotcha that cost real time to discover.
  - This applies to work built straight from a conversation, not just work driven by a
    `superpowers` skill. Building without a skill is the case most likely to leave the map
    quietly incomplete, so it is exactly the case the rule has to cover.
