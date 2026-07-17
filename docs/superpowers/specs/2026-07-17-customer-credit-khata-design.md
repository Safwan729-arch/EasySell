# Design: Customer credit ("khata")

**Date:** 2026-07-17
**Feature branch:** feat/customer-credit (new, from main)
**Owner:** Member A (Flutter + Supabase)

## Problem

Small shopkeepers routinely sell on credit — a regular customer takes goods now
and pays later. Today the app can only record a sale as immediately paid, so
shopkeepers who run a paper *khata* have no way to record who owes them what.
They must either skip logging the sale (breaking inventory and analytics) or log
it as paid (breaking their cash reconciliation).

We want a full ledger: a customer list, credit sales that add to a customer's
balance, repayments that reduce it, and a per-customer history of both.

## Approach

**Append-only ledger, balance computed live.** Every credit event — a sale taken
on credit, a repayment made — is one immutable row in `customer_ledger`. A
customer's balance is `sum(credit_sale) - sum(payment)`, aggregated on read.

This mirrors the decision already made for analytics (CLAUDE.md §5): live
aggregation over a maintained rollup. Volumes are tiny, and a stored `balance`
column can silently drift out of sync the moment any write path misses an
update — the same class of bug `record_sale` exists to prevent. The ledger is
also, for free, the per-customer purchase/payment history the feature needs.

**Rejected:** a denormalized `balance` column on `customers` (drift risk, no
history); deriving balance from `transactions` + a separate `payments` table
(truth split across two tables, history requires a union query).

### Revenue timing: accrual

A credit sale counts toward revenue/profit **at sale time**, exactly like a cash
sale. The goods have left the shelf and the price is frozen on the transaction
row; the debt is tracked separately as receivables. Consequently
`get_dashboard_summary` and every existing analytics query are **unchanged** —
they already aggregate all `type = 'sale'` rows regardless of how they were paid.

## Data model

Migration: `supabase/migrations/0008_customer_credit.sql` (idempotent, same
conventions as 0007 — run in the Supabase Dashboard SQL Editor).

### customers

| Column | Type | Notes |
|---|---|---|
| `id` | uuid pk | `default gen_random_uuid()` |
| `shop_id` | uuid not null | `references shops(id) on delete cascade` |
| `name` | text not null | required |
| `phone` | text not null | required (per product decision) |
| `note` | text | optional |
| `created_at` | timestamptz not null | `default now()` |
| `updated_at` | timestamptz not null | `default now()`, `set_updated_at` trigger |

Duplicate names are allowed — two customers may legitimately be called "Rahim".
No unique constraint on `phone` either; a household may share one number.

### customer_ledger

Append-only. Rows are never updated or deleted (except by cascade when a
zero-balance customer is deleted).

| Column | Type | Notes |
|---|---|---|
| `id` | uuid pk | `default gen_random_uuid()` |
| `shop_id` | uuid not null | `references shops(id) on delete cascade` |
| `customer_id` | uuid not null | `references customers(id) on delete cascade` |
| `entry_type` | text not null | `check (entry_type in ('credit_sale','payment'))` |
| `amount` | numeric(12,2) not null | `check (amount > 0)` — always positive; `entry_type` carries the sign |
| `sale_group_id` | uuid | set for `credit_sale` (links to the `transactions` rows of that receipt); null for `payment` |
| `note` | text | optional |
| `created_at` | timestamptz not null | `default now()` |

### Indexes

```sql
create index if not exists idx_customers_shop on customers (shop_id);
create index if not exists idx_customer_ledger_customer on customer_ledger (customer_id, created_at desc);
create index if not exists idx_customer_ledger_shop on customer_ledger (shop_id);
```

### RLS

Both tables shop-scoped via `shops.owner_id = auth.uid()`, identical in shape to
the existing policies in 0001:

```sql
alter table customers enable row level security;
create policy "shop members read/write own customers"
  on customers for all
  using (shop_id in (select id from shops where owner_id = auth.uid()))
  with check (shop_id in (select id from shops where owner_id = auth.uid()));
```

Equivalent policy on `customer_ledger`.

## Business-logic RPCs

### 1. `record_sale_cart` — extended, not duplicated

The credit checkout must do everything `record_sale_cart` already does (lock each
product row, verify stock, decrement, freeze prices, insert lines under one
`sale_group_id`) **plus** write the ledger entry — all atomically.

Rather than clone that body into a second function, **add an optional
`p_customer_id` parameter to the existing `record_sale_cart`**:

```sql
drop function if exists record_sale_cart(uuid, jsonb, text);

create function record_sale_cart(
  p_shop_id uuid,
  p_items jsonb,
  p_source text default 'manual',
  p_customer_id uuid default null   -- non-null => sale is on credit
) returns setof transactions
```

Behaviour when `p_customer_id is null` is byte-for-byte today's behaviour, so the
existing Dart call site and every cash sale are unaffected.

When `p_customer_id` is not null, after the item loop:

1. Verify the customer exists **and belongs to `p_shop_id`** — otherwise
   `raise exception 'Customer not found'`. (Guards against a customer id from
   another shop; RLS protects reads but the RPC runs the insert itself.)
2. Compute the receipt total: `sum(selling_price * quantity)` over the rows just
   inserted for `v_group`.
3. Insert one `customer_ledger` row: `entry_type = 'credit_sale'`,
   `amount = total`, `sale_group_id = v_group`.

The whole function body is one Postgres transaction, so a failure on any line
(insufficient stock, unknown product, unknown customer) rolls back every lock,
decrement, insert **and** the ledger entry. There is no partial credit sale: no
stock leaves without a debt recorded, and no debt is recorded without stock
leaving.

**Rationale for extending over cloning:** duplicating the stock-locking loop —
the most correctness-critical code in the app — into a near-identical twin
invites the two copies to drift when one is fixed and the other is not. One
function with an optional customer keeps a single audited implementation.

> **Deviation flagged:** the approved verbal design described this as "a twin of
> `record_sale_cart`". This spec refines it to one function with an optional
> parameter for the reason above. Externally observable behaviour is identical.

### 2. `record_payment`

```sql
create or replace function record_payment(
  p_shop_id uuid,
  p_customer_id uuid,
  p_amount numeric,
  p_note text default null
) returns customer_ledger
```

- Rejects `p_amount is null or p_amount <= 0` → `'Payment must be greater than zero'`.
- Verifies the customer belongs to `p_shop_id` → `'Customer not found'`.
- Computes the customer's current balance and rejects overpayment:
  `raise exception 'Payment exceeds balance: owes %', v_balance`.
- Inserts the `payment` ledger row and returns it.

Because overpayment is rejected, **a balance can never go negative**. Every
balance in the system is `>= 0`, which keeps `total_owed` a plain `sum(balance)`.

Concurrency note: two simultaneous payments could each read a stale balance and
both pass the check. Take `for update` locks on the customer's ledger rows (or
the `customers` row) before computing the balance, mirroring how `record_sale`
locks the product row before its stock check.

### 3. `get_customer_balances`

```sql
create or replace function get_customer_balances(p_shop_id uuid)
returns table (
  id uuid, name text, phone text, note text,
  balance numeric, last_activity_at timestamptz
)
```

Left-joins `customers` to `customer_ledger` and aggregates:
`coalesce(sum(case when entry_type = 'credit_sale' then amount else -amount end), 0)`.
Returns **all** customers including zero-balance ones (this backs the full
customer list, not just debtors). Ordered by `balance desc`, then `name asc`, so
the people who owe most surface first.

### 4. `get_receivables_summary`

```sql
create or replace function get_receivables_summary(p_shop_id uuid)
returns table (total_owed numeric, debtor_count bigint)
```

`total_owed` = sum of balances over customers with `balance > 0`;
`debtor_count` = how many such customers. Backs the Dashboard card.

### 5. `delete_customer`

```sql
create or replace function delete_customer(p_shop_id uuid, p_customer_id uuid)
returns void
```

Raises `'Cannot delete a customer who still owes money'` when balance `<> 0`;
otherwise deletes the customer (ledger rows cascade). Deleting a settled
customer discards their history by design — the alternative (archiving, as
products do) is out of scope for this MVP.

## Flutter components

New feature folder `lib/features/customers/`, following the established
`data / domain / presentation` split.

### Domain (`freezed` + `json_serializable`)

| File | Type |
|---|---|
| `domain/customer.dart` | `Customer` — id, shopId, name, phone, note, createdAt |
| `domain/customer_balance.dart` | `CustomerBalance` — id, name, phone, note, balance, lastActivityAt (the `get_customer_balances` row shape) |
| `domain/ledger_entry.dart` | `LedgerEntry` — id, customerId, entryType (`LedgerEntryType` enum: `creditSale` / `payment`), amount, saleGroupId, note, createdAt |
| `domain/receivables_summary.dart` | `ReceivablesSummary` — totalOwed, debtorCount |

`LedgerEntryType` gets a localized label via the existing
`core/l10n/enum_labels.dart` pattern.

### Data

`data/customer_repository.dart` — wraps the Supabase client, returns `Result<T>`,
maps errors with the same `PostgrestException` / `SocketException` handling as
`TransactionRepository._map` (RPC-raised messages are already user-meaningful and
surface directly).

Methods: `customerBalances(shopId)`, `createCustomer(...)`,
`updateCustomer(...)`, `deleteCustomer(...)`, `ledgerFor(customerId)`,
`recordPayment(...)`, `receivablesSummary(shopId)`.

### Presentation

| File | Purpose |
|---|---|
| `presentation/customers_controller.dart` | `AsyncNotifier<List<CustomerBalance>>` for the list |
| `presentation/customer_detail_controller.dart` | `AsyncNotifier` — one customer's balance + ledger |
| `presentation/customer_form_controller.dart` | create/edit submission state |
| `presentation/customers_screen.dart` | list + search + total header + "add" FAB |
| `presentation/customer_detail_screen.dart` | balance header, ledger history newest-first, "Record payment" button |
| `presentation/customer_form_sheet.dart` | name + phone (required), note (optional) |
| `presentation/record_payment_sheet.dart` | amount entry + optional note |
| `presentation/customer_picker_sheet.dart` | searchable picker used by the cart; includes "+ Add new" |

Controllers call repositories; widgets stay dumb. Mutations invalidate the
relevant providers and bump `dataRefreshProvider`, as `CartCheckoutController`
already does.

### Cart changes

- `lib/features/cart/presentation/payment_method_controller.dart` (new): holds
  `PaymentMethod { cash, credit }` and the selected `Customer?`. Reset to
  `cash` / `null` after a successful checkout and when the cart is cleared.
- `cart_screen.dart`: a Cash/Credit segmented control (reuse
  `core/widgets/segment_pills.dart`). Choosing Credit reveals the customer
  picker. The checkout button label becomes "Add to {name}'s khata" and stays
  **disabled** while Credit is selected with no customer chosen.
- `cart_checkout_controller.dart`: pass `customerId` through to
  `recordSaleCart` when the method is credit. On success, additionally invalidate
  the customers/receivables providers.
- `transaction_repository.dart`: `recordSaleCart` gains an optional
  `String? customerId`, forwarded as `p_customer_id`.

### Dashboard changes

- `lib/features/dashboard/presentation/receivables_card.dart` (new): reads
  `get_receivables_summary`, renders "৳4,500 owed · 7 customers", taps through to
  `/customers`. Follows the existing `metric_card.dart` visual language.
- Hidden entirely when `debtor_count == 0`, so shops that never sell on credit
  see no new clutter.

### Routing

`core/router/app_router.dart`: add `AppRoutes.customers = '/customers'` and
`/customers/:id`, both on the root navigator via `_transitionPage` — matching how
`/insights`, `/trends`, and `/categories` are registered. No bottom-nav change.

### Localization

All new user-facing strings go in `lib/l10n/app_en.arb` **and** `lib/l10n/app_bn.arb`
(the app ships English + Bengali), then codegen. Covers: screen titles, Cash /
Credit labels, "Add to {name}'s khata", field labels and validation messages,
"Record payment", "Owed", the receivables card copy, empty states, and the RPC
error messages surfaced to users.

## Error handling

`Result<T>` / `Failure` throughout; user-friendly messages, never raw Postgres
errors.

| Case | Behaviour |
|---|---|
| Insufficient stock mid-credit-sale | Whole checkout rolls back; existing "Insufficient stock for X: have N, need M" message; cart preserved |
| Credit selected, no customer picked | Checkout button disabled (prevented, not errored) |
| Payment > balance | Rejected by `record_payment`; "Payment exceeds balance: owes ৳150" |
| Payment ≤ 0 | Rejected by `record_payment` and by client-side field validation |
| Empty name or phone | Client-side form validation |
| Delete customer with balance ≠ 0 | Rejected by `delete_customer` |
| Customer id from another shop | Rejected by RPC ("Customer not found") |
| Offline | Existing offline banner covers it; `NetworkFailure` surfaces from `_map` and the checkout fails fast rather than hanging |

## Testing

- **Unit:** balance math — credit_sale/payment mix sums correctly; empty ledger →
  0; overpayment guard rejects.
- **Unit:** `PaymentMethod` controller resets to cash/null after checkout and on
  cart clear.
- **Repository:** success and failure paths for `recordPayment`, `createCustomer`,
  `customerBalances` (error mapping produces the right `Failure` types).
- **Critical:** a credit checkout where one line has insufficient stock writes
  **nothing** — no stock decrement, no transaction rows, no ledger entry.
  This is the atomicity guarantee the whole design rests on.
- **Widget:** checkout button disabled when Credit is selected with no customer;
  receivables card hidden at `debtor_count == 0`.
- **Manual (physical S22):** credit sale → appears on customer's ledger and the
  dashboard card; partial repayment → balance drops; overpayment → blocked;
  cash sale path unchanged.

## Out of scope

- **Partial payment at sale time** (pay some now, owe the rest). Considered and
  deferred; a credit sale is fully unpaid, and repayments are recorded separately.
- **Payment reminders / SMS / WhatsApp** — `phone` is stored to enable this later.
- **Credit limits** per customer, interest, or due dates.
- **Customer-linked cash sales** — customers exist only for credit. A cash sale
  is not attributable to a person.
- **Editing or reversing a ledger entry.** The ledger is append-only; a mistaken
  credit sale is corrected by recording an offsetting payment. Full reversal
  semantics are a future concern.
- **Showing a credit badge on the History screen.** The link exists in the data
  (`customer_ledger.sale_group_id` → `transactions.sale_group_id`), so this can
  be added later without a migration.
- **Archiving customers** (products-style soft delete).

## Files touched

| File | Change |
|---|---|
| `supabase/migrations/0008_customer_credit.sql` | new: tables, indexes, RLS, RPCs; extends `record_sale_cart` |
| `lib/features/customers/domain/*.dart` | new: 4 models + codegen |
| `lib/features/customers/data/customer_repository.dart` | new |
| `lib/features/customers/presentation/*.dart` | new: 3 controllers, 2 screens, 3 sheets |
| `lib/features/cart/presentation/payment_method_controller.dart` | new |
| `lib/features/cart/presentation/cart_screen.dart` | Cash/Credit toggle + customer picker |
| `lib/features/cart/presentation/cart_checkout_controller.dart` | pass customerId; invalidate customer providers |
| `lib/features/transactions/data/transaction_repository.dart` | `recordSaleCart` gains optional `customerId` |
| `lib/features/dashboard/presentation/receivables_card.dart` | new |
| `lib/features/dashboard/presentation/dashboard_screen.dart` | mount receivables card |
| `lib/core/router/app_router.dart` | `/customers`, `/customers/:id` |
| `lib/core/l10n/enum_labels.dart` | `LedgerEntryType` labels |
| `lib/l10n/app_en.arb`, `lib/l10n/app_bn.arb` | new strings (en + bn) |
