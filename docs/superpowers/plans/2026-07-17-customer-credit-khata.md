# Customer Credit ("Khata") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let shopkeepers sell on credit — track a customer list, add credit sales to a customer's running balance, record repayments, and see who owes what, all backed by an append-only ledger.

**Architecture:** A single `customer_ledger` table records every credit sale (+) and payment (−); balances are computed live (`sum(credit_sale) − sum(payment)`), never stored. Credit sales reuse the existing `record_sale_cart` RPC by adding an optional `p_customer_id` parameter, so cash sales and all analytics stay byte-for-byte unchanged. The Flutter side adds a `customers` feature folder (data/domain/presentation) plus a Cash/Credit toggle on the cart and a receivables card on the dashboard.

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod` 3.x), `go_router` 17.x, `supabase_flutter` 2.x, `freezed` + `json_serializable` (config: `field_rename: snake` in `build.yaml`), Postgres RPCs, Flutter localization (`app_en.arb` + `app_bn.arb`).

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-07-17-customer-credit-khata-design.md` — the source of truth; consult it when a task needs more context.
- **Branch:** all work on `feat/customer-credit`, branched from `feat/offline-banner` (CORRECTED during execution — `main` lacks the Bengali-localization infrastructure this feature depends on; `feat/offline-banner` is the dev tip that carries it). The uncommitted `supabase/functions/recognize-product/*` changes are unrelated and were stashed before branching — do not stage them.
- **Never do client-side money/stock math** for persistence. Balances and stock changes are computed/enforced in Postgres RPCs (CLAUDE.md §10). Pure Dart balance helpers are for display/tests only.
- **Every table gets RLS**, shop-scoped via `shop_id in (select id from shops where owner_id = auth.uid())` (CLAUDE.md §4).
- **Accrual revenue:** a credit sale counts as revenue at sale time. Do NOT modify any analytics query or `get_dashboard_summary`.
- **`amount` is always positive**; `entry_type` carries the sign. A balance can never go negative (overpayment is rejected).
- **Repositories return `Result<T>`**, never throw to controllers. Error mapping mirrors `TransactionRepository._map`: `PostgrestException` → `DatabaseFailure(e.message)`, `SocketException` → `NetworkFailure`, else `UnexpectedFailure`.
- **Bilingual:** every new user-facing string goes in BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_bn.arb` (the `l10n_parity_test` enforces identical key sets). Access via `context.l10n.<key>`.
- **Codegen:** after editing any `@freezed`/`@JsonSerializable` model or the `.arb` files, run `dart run build_runner build --delete-conflicting-outputs` and `flutter gen-l10n` (the latter runs automatically on build, but run it explicitly so tests see the getters).
- **Numeric parsing from Postgres:** `numeric` columns arrive as `num`; convert with `(v as num?)?.toDouble() ?? 0`. RPC `returns table(...)` yields a `List` of row maps; RPC `returns <composite>` yields a Map OR a single-element List (handle both, as existing repos do).
- **Verify each task:** `flutter analyze` clean and `flutter test` green before committing.

---

### Task 1: Database migration — tables, RLS, RPCs

**Files:**
- Create: `supabase/migrations/0008_customer_credit.sql`

**Interfaces:**
- Consumes: existing `shops`, `products`, `transactions` tables; `set_updated_at()` trigger fn; existing `record_sale_cart(uuid, jsonb, text)` (this task drops & recreates it with a 4th param).
- Produces (RPC contracts the Dart repository in later tasks calls):
  - `record_sale_cart(p_shop_id uuid, p_items jsonb, p_source text default 'manual', p_customer_id uuid default null) returns setof transactions`
  - `record_payment(p_shop_id uuid, p_customer_id uuid, p_amount numeric, p_note text default null) returns customer_ledger`
  - `get_customer_balances(p_shop_id uuid) returns table(id uuid, name text, phone text, note text, balance numeric, last_activity_at timestamptz)`
  - `get_receivables_summary(p_shop_id uuid) returns table(total_owed numeric, debtor_count bigint)`
  - `delete_customer(p_shop_id uuid, p_customer_id uuid) returns void`
  - Tables `customers` and `customer_ledger` (columns per spec).

This task is SQL applied manually in the Supabase Dashboard SQL Editor (the project has no local `supabase db push` pipeline — see `supabase/README.md`). It has no Dart test; it is verified by the Dart repository tests in later tasks against a real project, and by manual SQL execution. Keep it idempotent so it is safe to re-run.

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/0008_customer_credit.sql`:

```sql
-- =============================================================================
-- 0008_customer_credit.sql — customer credit ("khata").
-- Run AFTER 0007_sale_cart.sql (Dashboard SQL Editor -> paste -> Run).
-- Idempotent (safe to re-run).
--
-- Adds a customer list and an APPEND-ONLY ledger. A customer's balance is
-- computed live as sum(credit_sale) - sum(payment); no balance is stored, so it
-- can never drift (same philosophy as live analytics, CLAUDE.md §5).
--
-- record_sale_cart gains an optional p_customer_id: null => today's cash-sale
-- behaviour, unchanged; non-null => the same atomic checkout PLUS one
-- 'credit_sale' ledger row for the receipt total, all in one transaction.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- TABLES
-- ---------------------------------------------------------------------------
create table if not exists customers (
  id          uuid primary key default gen_random_uuid(),
  shop_id     uuid not null references shops(id) on delete cascade,
  name        text not null,
  phone       text not null,
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists customer_ledger (
  id             uuid primary key default gen_random_uuid(),
  shop_id        uuid not null references shops(id) on delete cascade,
  customer_id    uuid not null references customers(id) on delete cascade,
  entry_type     text not null check (entry_type in ('credit_sale', 'payment')),
  amount         numeric(12, 2) not null check (amount > 0),
  sale_group_id  uuid,
  note           text,
  created_at     timestamptz not null default now()
);

create index if not exists idx_customers_shop on customers (shop_id);
create index if not exists idx_customer_ledger_customer on customer_ledger (customer_id, created_at desc);
create index if not exists idx_customer_ledger_shop on customer_ledger (shop_id);

-- keep updated_at fresh on customers
drop trigger if exists trg_customers_updated_at on customers;
create trigger trg_customers_updated_at before update on customers
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- ROW LEVEL SECURITY (shop-scoped, same shape as 0001)
-- ---------------------------------------------------------------------------
alter table customers        enable row level security;
alter table customer_ledger  enable row level security;

drop policy if exists "shop members read/write own customers" on customers;
create policy "shop members read/write own customers"
  on customers for all
  using (shop_id in (select id from shops where owner_id = auth.uid()))
  with check (shop_id in (select id from shops where owner_id = auth.uid()));

drop policy if exists "shop members read/write own customer_ledger" on customer_ledger;
create policy "shop members read/write own customer_ledger"
  on customer_ledger for all
  using (shop_id in (select id from shops where owner_id = auth.uid()))
  with check (shop_id in (select id from shops where owner_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- record_sale_cart — extended with optional p_customer_id (credit sale).
-- p_customer_id null => identical to 0007 behaviour.
-- ---------------------------------------------------------------------------
drop function if exists record_sale_cart(uuid, jsonb, text);
drop function if exists record_sale_cart(uuid, jsonb, text, uuid);

create function record_sale_cart(
  p_shop_id uuid,
  p_items jsonb,              -- [{"product_id": "...", "quantity": 2}, ...]
  p_source text default 'manual',
  p_customer_id uuid default null
) returns setof transactions
language plpgsql
as $$
declare
  v_group uuid := gen_random_uuid();
  v_item record;
  v_product products;
  v_total numeric(12, 2);
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'Cart is empty';
  end if;

  -- A credit sale needs a valid customer in THIS shop before we touch stock.
  if p_customer_id is not null then
    perform 1 from customers
      where id = p_customer_id and shop_id = p_shop_id;
    if not found then
      raise exception 'Customer not found';
    end if;
  end if;

  for v_item in
    select * from jsonb_to_recordset(p_items) as x(product_id uuid, quantity numeric)
  loop
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Quantity must be greater than zero';
    end if;

    select * into v_product from products
      where id = v_item.product_id and shop_id = p_shop_id
      for update;

    if v_product is null then
      raise exception 'Product not found';
    end if;

    if v_product.quantity < v_item.quantity then
      raise exception 'Insufficient stock for %: have %, need %',
        v_product.name, v_product.quantity, v_item.quantity;
    end if;

    update products set quantity = quantity - v_item.quantity, updated_at = now()
      where id = v_item.product_id;

    insert into transactions(shop_id, product_id, type, quantity, buying_price,
                              selling_price, source, sale_group_id)
    values (p_shop_id, v_item.product_id, 'sale', v_item.quantity,
            v_product.buying_price, v_product.selling_price, p_source, v_group);
  end loop;

  -- On credit: record the debt for the receipt total in the same transaction,
  -- so stock and debt can never disagree.
  if p_customer_id is not null then
    select coalesce(sum(selling_price * quantity), 0) into v_total
      from transactions where sale_group_id = v_group;

    insert into customer_ledger(shop_id, customer_id, entry_type, amount, sale_group_id)
    values (p_shop_id, p_customer_id, 'credit_sale', v_total, v_group);
  end if;

  return query select * from transactions where sale_group_id = v_group;
end;
$$;

-- ---------------------------------------------------------------------------
-- record_payment — append a 'payment' ledger row. Rejects <=0 and overpayment.
-- ---------------------------------------------------------------------------
create or replace function record_payment(
  p_shop_id uuid,
  p_customer_id uuid,
  p_amount numeric,
  p_note text default null
) returns customer_ledger
language plpgsql
as $$
declare
  v_balance numeric(12, 2);
  v_row customer_ledger;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment must be greater than zero';
  end if;

  -- Lock the customer row so two concurrent payments can't both pass the
  -- overpayment check against a stale balance (mirrors record_sale's row lock).
  perform 1 from customers
    where id = p_customer_id and shop_id = p_shop_id
    for update;
  if not found then
    raise exception 'Customer not found';
  end if;

  select coalesce(sum(case when entry_type = 'credit_sale' then amount
                           else -amount end), 0)
    into v_balance
    from customer_ledger
    where customer_id = p_customer_id;

  if p_amount > v_balance then
    raise exception 'Payment exceeds balance: owes %', v_balance;
  end if;

  insert into customer_ledger(shop_id, customer_id, entry_type, amount, note)
  values (p_shop_id, p_customer_id, 'payment', p_amount, p_note)
  returning * into v_row;

  return v_row;
end;
$$;

-- ---------------------------------------------------------------------------
-- get_customer_balances — every customer + live balance + last activity.
-- ---------------------------------------------------------------------------
create or replace function get_customer_balances(p_shop_id uuid)
returns table (
  id uuid, name text, phone text, note text,
  balance numeric, last_activity_at timestamptz
)
language sql
as $$
  select c.id, c.name, c.phone, c.note,
    coalesce(sum(case when l.entry_type = 'credit_sale' then l.amount
                      else -l.amount end), 0)::numeric as balance,
    max(l.created_at) as last_activity_at
  from customers c
  left join customer_ledger l on l.customer_id = c.id
  where c.shop_id = p_shop_id
  group by c.id, c.name, c.phone, c.note
  order by balance desc, c.name asc;
$$;

-- ---------------------------------------------------------------------------
-- get_receivables_summary — total owed + debtor count (dashboard card).
-- ---------------------------------------------------------------------------
create or replace function get_receivables_summary(p_shop_id uuid)
returns table (total_owed numeric, debtor_count bigint)
language sql
as $$
  select
    coalesce(sum(b.balance), 0)::numeric as total_owed,
    count(*)::bigint as debtor_count
  from get_customer_balances(p_shop_id) b
  where b.balance > 0;
$$;

-- ---------------------------------------------------------------------------
-- delete_customer — only when settled (balance = 0). Ledger cascades.
-- ---------------------------------------------------------------------------
create or replace function delete_customer(p_shop_id uuid, p_customer_id uuid)
returns void
language plpgsql
as $$
declare
  v_balance numeric(12, 2);
begin
  select coalesce(sum(case when entry_type = 'credit_sale' then amount
                           else -amount end), 0)
    into v_balance
    from customer_ledger
    where customer_id = p_customer_id;

  if v_balance <> 0 then
    raise exception 'Cannot delete a customer who still owes money';
  end if;

  delete from customers where id = p_customer_id and shop_id = p_shop_id;
end;
$$;
```

- [ ] **Step 2: Apply the migration**

Paste the whole file into the Supabase Dashboard SQL Editor and Run. Confirm it completes without error. Re-run once to confirm idempotency (should also succeed).

- [ ] **Step 3: Smoke-test the RPCs in the SQL Editor**

With a real `shop_id` from your project, run:

```sql
-- create a customer
insert into customers(shop_id, name, phone) values ('<shop_id>', 'Test Rahim', '01700000000') returning id;
-- record a payment with no balance -> must error "Payment exceeds balance: owes 0"
select record_payment('<shop_id>', '<customer_id>', 100);
-- balances -> Test Rahim, balance 0
select * from get_customer_balances('<shop_id>');
-- clean up
select delete_customer('<shop_id>', '<customer_id>');
```

Expected: the `record_payment` call raises `Payment exceeds balance: owes 0`; `get_customer_balances` lists the customer at balance 0; `delete_customer` succeeds.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0008_customer_credit.sql
git commit -m "feat(db): customer credit tables, RLS, and ledger RPCs

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Domain models

**Files:**
- Create: `lib/features/customers/domain/customer.dart`
- Create: `lib/features/customers/domain/ledger_entry.dart`
- Create: `lib/features/customers/domain/customer_balance.dart`
- Create: `lib/features/customers/domain/receivables_summary.dart`
- Test: `test/customer_balance_test.dart`

**Interfaces:**
- Consumes: `freezed_annotation`, `json_serializable` (via `build.yaml` `field_rename: snake`).
- Produces:
  - `Customer` (freezed): `id, shopId, name, phone, note?, createdAt?`; `Customer.fromJson`.
  - `LedgerEntryType` enum: `creditSale`, `payment`; `LedgerEntryType.fromDb(String)` and `.dbValue`.
  - `LedgerEntry` (freezed): `id, customerId, entryType (LedgerEntryType), amount (double), saleGroupId?, note?, createdAt`; `LedgerEntry.fromJson`.
  - `CustomerBalance` (plain, `fromMap`): `id, name, phone, note?, balance (double), lastActivityAt?`. Has `bool get owes => balance > 0`.
  - `ReceivablesSummary` (plain, `fromMap`): `totalOwed (double), debtorCount (int)`; `const ReceivablesSummary.empty`.

`Customer` and `LedgerEntry` map table rows → use freezed like `Category`/`Transaction`. `CustomerBalance` and `ReceivablesSummary` map RPC `returns table(...)` rows → use hand-written `fromMap` like `DashboardSummary` (their shapes are query-specific, not table rows).

- [ ] **Step 1: Write the failing test**

Create `test/customer_balance_test.dart`:

```dart
import 'package:ai_shopkeeper/features/customers/domain/customer_balance.dart';
import 'package:ai_shopkeeper/features/customers/domain/ledger_entry.dart';
import 'package:ai_shopkeeper/features/customers/domain/receivables_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CustomerBalance.fromMap', () {
    test('parses numeric balance as double and flags who owes', () {
      final b = CustomerBalance.fromMap({
        'id': 'c1',
        'name': 'Rahim',
        'phone': '01700000000',
        'note': null,
        'balance': 150, // Postgres numeric may arrive as int or double
        'last_activity_at': '2026-07-17T10:00:00Z',
      });
      expect(b.name, 'Rahim');
      expect(b.balance, 150.0);
      expect(b.owes, isTrue);
    });

    test('a zero balance does not owe and tolerates a null last activity', () {
      final b = CustomerBalance.fromMap({
        'id': 'c2',
        'name': 'Karim',
        'phone': '01800000000',
        'note': 'next door',
        'balance': 0,
        'last_activity_at': null,
      });
      expect(b.owes, isFalse);
      expect(b.lastActivityAt, isNull);
      expect(b.note, 'next door');
    });
  });

  group('ReceivablesSummary.fromMap', () {
    test('parses totals', () {
      final s = ReceivablesSummary.fromMap({
        'total_owed': 4500,
        'debtor_count': 7,
      });
      expect(s.totalOwed, 4500.0);
      expect(s.debtorCount, 7);
    });

    test('empty is zero', () {
      expect(ReceivablesSummary.empty.totalOwed, 0);
      expect(ReceivablesSummary.empty.debtorCount, 0);
    });
  });

  group('LedgerEntryType', () {
    test('round-trips the db value', () {
      expect(LedgerEntryType.fromDb('credit_sale'), LedgerEntryType.creditSale);
      expect(LedgerEntryType.fromDb('payment'), LedgerEntryType.payment);
      expect(LedgerEntryType.creditSale.dbValue, 'credit_sale');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/customer_balance_test.dart`
Expected: FAIL — target files/URIs do not exist.

- [ ] **Step 3: Write the models**

`lib/features/customers/domain/customer.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'customer.freezed.dart';
part 'customer.g.dart';

/// A shop-scoped customer who may buy on credit. `name` and `phone` are
/// required (product decision); `note` is optional.
@freezed
abstract class Customer with _$Customer {
  const Customer._();

  const factory Customer({
    required String id,
    required String shopId,
    required String name,
    required String phone,
    String? note,
    DateTime? createdAt,
  }) = _Customer;

  factory Customer.fromJson(Map<String, dynamic> json) =>
      _$CustomerFromJson(json);
}
```

`lib/features/customers/domain/ledger_entry.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'ledger_entry.freezed.dart';
part 'ledger_entry.g.dart';

/// The kind of ledger movement. The DB stores snake_case strings; the enum is
/// the app-side representation.
enum LedgerEntryType {
  creditSale('credit_sale'),
  payment('payment');

  const LedgerEntryType(this.dbValue);
  final String dbValue;

  static LedgerEntryType fromDb(String value) => switch (value) {
    'credit_sale' => LedgerEntryType.creditSale,
    'payment' => LedgerEntryType.payment,
    _ => throw ArgumentError('Unknown ledger entry_type: $value'),
  };
}

/// One immutable row of a customer's ledger — a credit sale (+) or a payment
/// (−). `amount` is always positive; [entryType] carries the sign.
@freezed
abstract class LedgerEntry with _$LedgerEntry {
  const LedgerEntry._();

  const factory LedgerEntry({
    required String id,
    required String customerId,
    required LedgerEntryType entryType,
    required double amount,
    String? saleGroupId,
    String? note,
    required DateTime createdAt,
  }) = _LedgerEntry;

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
    id: json['id'] as String,
    customerId: json['customer_id'] as String,
    entryType: LedgerEntryType.fromDb(json['entry_type'] as String),
    amount: (json['amount'] as num).toDouble(),
    saleGroupId: json['sale_group_id'] as String?,
    note: json['note'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );
}
```

> Note: `LedgerEntry.fromJson` is hand-written (not `_$LedgerEntryFromJson`) because `entryType` needs enum-from-db mapping and `createdAt` needs `.toLocal()`. The `part 'ledger_entry.g.dart'` is still required for freezed's generated `toJson`/equality — keep it. If build_runner complains about an unused generator, remove the `.g.dart` part and the `_$...FromJson` expectation is already avoided; verify after Step 5.

`lib/features/customers/domain/customer_balance.dart`:

```dart
/// A customer plus their live balance, as returned by the
/// `get_customer_balances` RPC. Not a table row — a query-shaped projection,
/// so it uses a hand-written `fromMap` like `DashboardSummary`.
class CustomerBalance {
  const CustomerBalance({
    required this.id,
    required this.name,
    required this.phone,
    required this.balance,
    this.note,
    this.lastActivityAt,
  });

  final String id;
  final String name;
  final String phone;
  final String? note;
  final double balance;
  final DateTime? lastActivityAt;

  /// True when this customer currently owes money.
  bool get owes => balance > 0;

  factory CustomerBalance.fromMap(Map<String, dynamic> map) {
    final rawActivity = map['last_activity_at'] as String?;
    return CustomerBalance(
      id: map['id'] as String,
      name: map['name'] as String,
      phone: map['phone'] as String,
      note: map['note'] as String?,
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
      lastActivityAt: rawActivity == null
          ? null
          : DateTime.parse(rawActivity).toLocal(),
    );
  }
}
```

`lib/features/customers/domain/receivables_summary.dart`:

```dart
/// Total outstanding receivables + how many customers owe, from the
/// `get_receivables_summary` RPC. Backs the dashboard card.
class ReceivablesSummary {
  const ReceivablesSummary({
    required this.totalOwed,
    required this.debtorCount,
  });

  final double totalOwed;
  final int debtorCount;

  static const empty = ReceivablesSummary(totalOwed: 0, debtorCount: 0);

  factory ReceivablesSummary.fromMap(Map<String, dynamic> map) {
    return ReceivablesSummary(
      totalOwed: (map['total_owed'] as num?)?.toDouble() ?? 0,
      debtorCount: (map['debtor_count'] as num?)?.toInt() ?? 0,
    );
  }
}
```

- [ ] **Step 4: Run codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: generates `customer.freezed.dart`, `customer.g.dart`, `ledger_entry.freezed.dart`, `ledger_entry.g.dart` with no errors.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/customer_balance_test.dart`
Expected: PASS. Then `flutter analyze` — expected: no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/customers/domain/ test/customer_balance_test.dart
git commit -m "feat(customers): domain models for customer, ledger, balances

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Pure balance helper

**Files:**
- Create: `lib/features/customers/domain/ledger_math.dart`
- Test: `test/ledger_math_test.dart`

**Interfaces:**
- Consumes: `LedgerEntry`, `LedgerEntryType` from Task 2.
- Produces: `double balanceOf(List<LedgerEntry> entries)` — `sum(creditSale) − sum(payment)`. Display/verification helper only; the DB is the source of truth for persistence.

This exists so the customer-detail screen can show a running balance from the entries it already loaded (no extra round-trip), and so the sign convention is unit-tested in one place.

- [ ] **Step 1: Write the failing test**

Create `test/ledger_math_test.dart`:

```dart
import 'package:ai_shopkeeper/features/customers/domain/ledger_entry.dart';
import 'package:ai_shopkeeper/features/customers/domain/ledger_math.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerEntry _e(LedgerEntryType type, double amount) => LedgerEntry(
  id: 'x',
  customerId: 'c',
  entryType: type,
  amount: amount,
  createdAt: DateTime(2026, 7, 17),
);

void main() {
  group('balanceOf', () {
    test('an empty ledger is zero', () {
      expect(balanceOf(const []), 0);
    });

    test('credit sales add, payments subtract', () {
      final entries = [
        _e(LedgerEntryType.creditSale, 200),
        _e(LedgerEntryType.payment, 50),
        _e(LedgerEntryType.creditSale, 30),
      ];
      expect(balanceOf(entries), 180);
    });

    test('a fully paid customer nets to zero', () {
      final entries = [
        _e(LedgerEntryType.creditSale, 100),
        _e(LedgerEntryType.payment, 100),
      ];
      expect(balanceOf(entries), 0);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ledger_math_test.dart`
Expected: FAIL — `ledger_math.dart` does not exist.

- [ ] **Step 3: Write the helper**

`lib/features/customers/domain/ledger_math.dart`:

```dart
import 'ledger_entry.dart';

/// A customer's balance from their ledger: credit sales add, payments subtract.
/// Display/verification helper — Postgres remains the source of truth for what
/// is persisted (see `get_customer_balances`).
double balanceOf(List<LedgerEntry> entries) {
  var total = 0.0;
  for (final e in entries) {
    total += switch (e.entryType) {
      LedgerEntryType.creditSale => e.amount,
      LedgerEntryType.payment => -e.amount,
    };
  }
  return total;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ledger_math_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/customers/domain/ledger_math.dart test/ledger_math_test.dart
git commit -m "feat(customers): pure balanceOf ledger helper

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Customer repository

**Files:**
- Create: `lib/features/customers/data/customer_repository.dart`
- Test: `test/customer_repository_error_mapping_test.dart`

**Interfaces:**
- Consumes: `supabaseClientProvider` (`lib/shared/providers/supabase_provider.dart`), `Result`, `Failure` subtypes, Task 2 models.
- Produces `customerRepositoryProvider` exposing `CustomerRepository`:
  - `Future<Result<List<CustomerBalance>>> customerBalances(String shopId)`
  - `Future<Result<ReceivablesSummary>> receivablesSummary(String shopId)`
  - `Future<Result<Customer>> createCustomer({required String shopId, required String name, required String phone, String? note})`
  - `Future<Result<Customer>> updateCustomer({required String id, required String name, required String phone, String? note})`
  - `Future<Result<void>> deleteCustomer({required String shopId, required String id})`
  - `Future<Result<List<LedgerEntry>>> ledgerFor(String customerId)`
  - `Future<Result<LedgerEntry>> recordPayment({required String shopId, required String customerId, required double amount, String? note})`
  - `@visibleForTesting Failure mapError(Object e)` (exposes `_map` for the unit test, mirroring how auth exposes `mapSupabaseError`).

- [ ] **Step 1: Write the failing test**

Create `test/customer_repository_error_mapping_test.dart`:

```dart
import 'dart:io';

import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/features/customers/data/customer_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final repo = CustomerRepository(SupabaseClient('http://localhost', 'anon'));

  group('CustomerRepository.mapError', () {
    test('an RPC exception surfaces its message as DatabaseFailure', () {
      final f = repo.mapError(
        const PostgrestException(message: 'Payment exceeds balance: owes 150'),
      );
      expect(f, isA<DatabaseFailure>());
      expect(f.message, 'Payment exceeds balance: owes 150');
    });

    test('a SocketException maps to NetworkFailure', () {
      expect(
        repo.mapError(const SocketException('no route')),
        isA<NetworkFailure>(),
      );
    });

    test('anything else maps to UnexpectedFailure', () {
      expect(repo.mapError(Exception('boom')), isA<UnexpectedFailure>());
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/customer_repository_error_mapping_test.dart`
Expected: FAIL — `CustomerRepository` does not exist.

- [ ] **Step 3: Write the repository**

`lib/features/customers/data/customer_repository.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../domain/customer.dart';
import '../domain/customer_balance.dart';
import '../domain/ledger_entry.dart';
import '../domain/receivables_summary.dart';

/// The only layer that touches Supabase for the customer-credit feature.
/// Balances and the overpayment guard live in Postgres RPCs (never client-side
/// money math); this maps rows to models and returns [Result]s.
class CustomerRepository {
  CustomerRepository(this._client);

  final SupabaseClient _client;

  static const _customers = 'customers';
  static const _ledger = 'customer_ledger';

  Future<Result<List<CustomerBalance>>> customerBalances(String shopId) async {
    try {
      final rows = await _client.rpc(
        'get_customer_balances',
        params: {'p_shop_id': shopId},
      );
      return Result.success([
        for (final r in rows as List)
          CustomerBalance.fromMap(Map<String, dynamic>.from(r as Map)),
      ]);
    } catch (e) {
      return Result.failure(mapError(e));
    }
  }

  Future<Result<ReceivablesSummary>> receivablesSummary(String shopId) async {
    try {
      final result = await _client.rpc(
        'get_receivables_summary',
        params: {'p_shop_id': shopId},
      );
      final row = result is List
          ? (result.isEmpty ? const {} : result.first)
          : result;
      return Result.success(
        ReceivablesSummary.fromMap(Map<String, dynamic>.from(row as Map)),
      );
    } catch (e) {
      return Result.failure(mapError(e));
    }
  }

  Future<Result<Customer>> createCustomer({
    required String shopId,
    required String name,
    required String phone,
    String? note,
  }) async {
    try {
      final row = await _client
          .from(_customers)
          .insert({
            'shop_id': shopId,
            'name': name,
            'phone': phone,
            if (note != null && note.isNotEmpty) 'note': note,
          })
          .select()
          .single();
      return Result.success(Customer.fromJson(row));
    } catch (e) {
      return Result.failure(mapError(e));
    }
  }

  Future<Result<Customer>> updateCustomer({
    required String id,
    required String name,
    required String phone,
    String? note,
  }) async {
    try {
      final row = await _client
          .from(_customers)
          .update({
            'name': name,
            'phone': phone,
            'note': (note == null || note.isEmpty) ? null : note,
          })
          .eq('id', id)
          .select()
          .single();
      return Result.success(Customer.fromJson(row));
    } catch (e) {
      return Result.failure(mapError(e));
    }
  }

  Future<Result<void>> deleteCustomer({
    required String shopId,
    required String id,
  }) async {
    try {
      await _client.rpc(
        'delete_customer',
        params: {'p_shop_id': shopId, 'p_customer_id': id},
      );
      return const Result.success(null);
    } catch (e) {
      return Result.failure(mapError(e));
    }
  }

  Future<Result<List<LedgerEntry>>> ledgerFor(String customerId) async {
    try {
      final rows = await _client
          .from(_ledger)
          .select()
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);
      return Result.success([
        for (final r in rows as List)
          LedgerEntry.fromJson(Map<String, dynamic>.from(r as Map)),
      ]);
    } catch (e) {
      return Result.failure(mapError(e));
    }
  }

  Future<Result<LedgerEntry>> recordPayment({
    required String shopId,
    required String customerId,
    required double amount,
    String? note,
  }) async {
    try {
      final result = await _client.rpc(
        'record_payment',
        params: {
          'p_shop_id': shopId,
          'p_customer_id': customerId,
          'p_amount': amount,
          if (note != null && note.isNotEmpty) 'p_note': note,
        },
      );
      final row = result is List ? result.first : result;
      return Result.success(
        LedgerEntry.fromJson(Map<String, dynamic>.from(row as Map)),
      );
    } catch (e) {
      return Result.failure(mapError(e));
    }
  }

  /// RPC/Postgres exceptions carry user-meaningful messages (e.g. "Payment
  /// exceeds balance: owes 150") — surface them directly. Mirrors
  /// `TransactionRepository._map`.
  @visibleForTesting
  Failure mapError(Object e) {
    if (e is PostgrestException) {
      return DatabaseFailure(
        e.message.isNotEmpty
            ? e.message
            : 'Could not complete the request. Please try again.',
      );
    }
    if (e is SocketException) {
      return const NetworkFailure('No internet connection. Please try again.');
    }
    return const UnexpectedFailure('Something went wrong. Please try again.');
  }
}

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(ref.watch(supabaseClientProvider));
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/customer_repository_error_mapping_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/customers/data/ test/customer_repository_error_mapping_test.dart
git commit -m "feat(customers): repository over credit RPCs and tables

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Localization strings

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_bn.arb`
- Create: `lib/core/l10n/customer_labels.dart`

**Interfaces:**
- Consumes: existing `AppLocalizations`, `l10n_ext.dart` (`context.l10n`), `LedgerEntryType` (Task 2).
- Produces: new localized getters (listed below) available as `context.l10n.<key>`, plus `String ledgerEntryTypeLabel(AppLocalizations l10n, LedgerEntryType t)`.

Add these keys to BOTH arb files (English values shown; provide natural Bengali translations in `app_bn.arb`). The `l10n_parity_test` fails if the key sets differ.

- [ ] **Step 1: Add keys to `app_en.arb`**

Insert before the closing brace (place-insensitive; grouped for clarity):

```json
  "customers_title": "Customers",
  "customers_receivablesHeader": "{amount} owed by {count, plural, =1{1 customer} other{{count} customers}}",
  "@customers_receivablesHeader": { "placeholders": { "amount": { "type": "String" }, "count": { "type": "int", "format": "decimalPattern" } } },
  "customers_empty": "No customers yet",
  "customers_emptyHint": "Add a customer to start a khata, or choose Credit at checkout.",
  "customers_searchHint": "Search by name or phone",
  "customers_add": "Add customer",
  "customers_edit": "Edit customer",
  "customers_fieldName": "Name",
  "customers_fieldPhone": "Phone",
  "customers_fieldNote": "Note (optional)",
  "customers_nameRequired": "Enter a name",
  "customers_phoneRequired": "Enter a phone number",
  "customers_save": "Save",
  "customers_delete": "Delete customer",
  "customers_deleteConfirmTitle": "Delete {name}?",
  "@customers_deleteConfirmTitle": { "placeholders": { "name": { "type": "String" } } },
  "customers_deleteConfirmBody": "This removes the customer and their khata history. Only settled customers can be deleted.",
  "customers_owes": "Owes {amount}",
  "@customers_owes": { "placeholders": { "amount": { "type": "String" } } },
  "customers_settled": "Settled",
  "customers_balance": "Balance",
  "customers_ledgerEmpty": "No khata activity yet",
  "customers_recordPayment": "Record payment",
  "customers_paymentAmount": "Amount",
  "customers_paymentNote": "Note (optional)",
  "customers_paymentAmountRequired": "Enter an amount",
  "customers_paymentTooLarge": "More than what is owed",
  "customers_paymentRecorded": "Payment recorded",
  "customers_ledgerCreditSale": "Credit sale",
  "customers_ledgerPayment": "Payment",
  "cart_paymentMethod": "Payment",
  "cart_paymentCash": "Cash",
  "cart_paymentCredit": "Credit",
  "cart_selectCustomer": "Select customer",
  "cart_addToKhata": "Add to {name}'s khata",
  "@cart_addToKhata": { "placeholders": { "name": { "type": "String" } } },
  "cart_addedToKhata": "Added to {name}'s khata · {total}",
  "@cart_addedToKhata": { "placeholders": { "name": { "type": "String" }, "total": { "type": "String" } } },
  "dashboard_receivablesTitle": "Receivables",
```

- [ ] **Step 2: Add the same keys to `app_bn.arb`**

Add every key above with a natural Bengali translation and identical placeholder metadata (`@`-entries copied verbatim — placeholder config is language-independent). Example for two of them:

```json
  "customers_title": "গ্রাহক",
  "customers_recordPayment": "টাকা জমা করুন",
```

Translate the rest consistently with the app's existing Bengali tone (see neighbouring keys in the file).

- [ ] **Step 3: Write the ledger-label helper**

`lib/core/l10n/customer_labels.dart`:

```dart
import 'package:ai_shopkeeper/l10n/app_localizations.dart';

import '../../features/customers/domain/ledger_entry.dart';

/// Localized label for a ledger row's type, used by the customer-detail history.
String ledgerEntryTypeLabel(AppLocalizations l10n, LedgerEntryType t) =>
    switch (t) {
      LedgerEntryType.creditSale => l10n.customers_ledgerCreditSale,
      LedgerEntryType.payment => l10n.customers_ledgerPayment,
    };
```

- [ ] **Step 4: Regenerate localizations and verify parity**

Run: `flutter gen-l10n`
Then: `flutter test test/l10n_parity_test.dart`
Expected: PASS (identical key sets). Then `flutter analyze` — no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_bn.arb lib/core/l10n/customer_labels.dart
git commit -m "feat(l10n): customer credit strings (en + bn)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Customers list + detail controllers

**Files:**
- Create: `lib/features/customers/presentation/customers_controller.dart`
- Create: `lib/features/customers/presentation/customer_detail_controller.dart`
- Create: `lib/features/customers/presentation/receivables_controller.dart`

**Interfaces:**
- Consumes: `customerRepositoryProvider` (Task 4), `myShopProvider` (`lib/features/auth/data/auth_repository.dart`), `dataRefreshProvider` (`lib/shared/providers/refresh_provider.dart`), Task 2 models.
- Produces:
  - `customersControllerProvider` — `AsyncNotifierProvider<CustomersController, List<CustomerBalance>>`; methods `Future<void> refresh()`.
  - `receivablesControllerProvider` — `AsyncNotifierProvider<ReceivablesController, ReceivablesSummary>`.
  - `customerDetailControllerProvider` — `AsyncNotifierProvider.family<CustomerDetailController, List<LedgerEntry>, String>` (arg = customerId).
  - Mutation methods returning `Future<bool>` (true = success): on `CustomersController`: `createCustomer`, `updateCustomer`, `deleteCustomer`; on `CustomerDetailController`: `recordPayment`. Each invalidates the other providers + bumps `dataRefreshProvider` on success, and sets `AsyncError(Failure)` on failure.

These are wiring controllers with no pure logic to unit-test in isolation; they are exercised by the widget tests in later tasks and manual QA. No standalone test file. (Follows the same "controller has no independently testable pure logic" judgement as `CartCheckoutController`, which also has no unit test.)

- [ ] **Step 1: Write `customers_controller.dart`**

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../data/customer_repository.dart';
import '../domain/customer_balance.dart';
import 'receivables_controller.dart';

/// Loads the shop's customers with live balances (highest balance first) and
/// owns customer create/update/delete. Mutations refresh the receivables card
/// and any open detail view.
class CustomersController extends AsyncNotifier<List<CustomerBalance>> {
  @override
  Future<List<CustomerBalance>> build() async {
    ref.watch(dataRefreshProvider);
    final shopId = ref.watch(myShopProvider).value?.id;
    if (shopId == null) return const [];
    final result = await ref
        .read(customerRepositoryProvider)
        .customerBalances(shopId);
    return result.when(success: (v) => v, failure: (f) => throw f);
  }

  Future<bool> createCustomer({
    required String name,
    required String phone,
    String? note,
  }) {
    return _run(
      (repo, shopId) => repo.createCustomer(
        shopId: shopId,
        name: name,
        phone: phone,
        note: note,
      ),
    );
  }

  Future<bool> updateCustomer({
    required String id,
    required String name,
    required String phone,
    String? note,
  }) {
    return _run(
      (repo, _) =>
          repo.updateCustomer(id: id, name: name, phone: phone, note: note),
    );
  }

  Future<bool> deleteCustomer(String id) {
    return _run((repo, shopId) => repo.deleteCustomer(shopId: shopId, id: id));
  }

  /// Runs a repository mutation, refreshing dependent views on success and
  /// surfacing the failure on the controller on error. Generic over the
  /// Result's payload so create/update/delete share one path.
  Future<bool> _run<T>(
    Future<Result<T>> Function(CustomerRepository repo, String shopId) action,
  ) async {
    final shopId = ref.read(myShopProvider).value?.id;
    if (shopId == null) {
      state = AsyncError(
        const AuthFailure('No shop found for this account.'),
        StackTrace.current,
      );
      return false;
    }
    final result = await action(ref.read(customerRepositoryProvider), shopId);
    return result.when(
      success: (_) {
        _refreshAll();
        return true;
      },
      failure: (f) {
        state = AsyncError(f, StackTrace.current);
        return false;
      },
    );
  }

  void _refreshAll() {
    ref.invalidateSelf();
    ref.invalidate(receivablesControllerProvider);
    ref.read(dataRefreshProvider.notifier).bump();
  }
}

final customersControllerProvider =
    AsyncNotifierProvider<CustomersController, List<CustomerBalance>>(
      CustomersController.new,
    );
```

- [ ] **Step 2: Write `receivables_controller.dart`**

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../data/customer_repository.dart';
import '../domain/receivables_summary.dart';

/// Total receivables + debtor count for the dashboard card. Recomputes whenever
/// a sale/payment bumps [dataRefreshProvider].
class ReceivablesController extends AsyncNotifier<ReceivablesSummary> {
  @override
  Future<ReceivablesSummary> build() async {
    ref.watch(dataRefreshProvider);
    final shopId = ref.watch(myShopProvider).value?.id;
    if (shopId == null) return ReceivablesSummary.empty;
    final result = await ref
        .read(customerRepositoryProvider)
        .receivablesSummary(shopId);
    return result.when(success: (v) => v, failure: (f) => throw f);
  }
}

final receivablesControllerProvider =
    AsyncNotifierProvider<ReceivablesController, ReceivablesSummary>(
      ReceivablesController.new,
    );
```

- [ ] **Step 3: Write `customer_detail_controller.dart`**

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../data/customer_repository.dart';
import '../domain/ledger_entry.dart';
import 'customers_controller.dart';
import 'receivables_controller.dart';

/// One customer's ledger (newest first) + the record-payment action.
class CustomerDetailController
    extends FamilyAsyncNotifier<List<LedgerEntry>, String> {
  @override
  Future<List<LedgerEntry>> build(String customerId) async {
    ref.watch(dataRefreshProvider);
    final result = await ref
        .read(customerRepositoryProvider)
        .ledgerFor(customerId);
    return result.when(success: (v) => v, failure: (f) => throw f);
  }

  Future<bool> recordPayment({required double amount, String? note}) async {
    final shopId = ref.read(myShopProvider).value?.id;
    if (shopId == null) return false;
    final result = await ref
        .read(customerRepositoryProvider)
        .recordPayment(
          shopId: shopId,
          customerId: arg,
          amount: amount,
          note: note,
        );
    return result.when(
      success: (_) {
        ref.invalidateSelf();
        ref.invalidate(customersControllerProvider);
        ref.invalidate(receivablesControllerProvider);
        ref.read(dataRefreshProvider.notifier).bump();
        return true;
      },
      failure: (f) {
        state = AsyncError(f, StackTrace.current);
        return false;
      },
    );
  }
}

final customerDetailControllerProvider = AsyncNotifierProvider.family<
  CustomerDetailController,
  List<LedgerEntry>,
  String
>(CustomerDetailController.new);
```

- [ ] **Step 4: Verify it compiles**

Run: `flutter analyze lib/features/customers/presentation/`
Expected: no issues. (Confirm the `_run` form from Step 1's note is what you wrote — not the `_mutate` sketch.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/customers/presentation/customers_controller.dart lib/features/customers/presentation/receivables_controller.dart lib/features/customers/presentation/customer_detail_controller.dart
git commit -m "feat(customers): list, detail, and receivables controllers

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Customer form + payment sheets

**Files:**
- Create: `lib/features/customers/presentation/customer_form_sheet.dart`
- Create: `lib/features/customers/presentation/record_payment_sheet.dart`
- Test: `test/widgets/record_payment_sheet_test.dart`

**Interfaces:**
- Consumes: Task 6 controllers, `context.l10n` (Task 5 strings), `Money`/`Qty` (`lib/shared/extensions/format.dart`), `AppHaptics` (`lib/core/config/haptics.dart`), `CustomerBalance`/`Customer`.
- Produces:
  - `Future<void> showCustomerFormSheet(BuildContext context, {Customer? existing})` — modal bottom sheet; add or edit. Validates name & phone non-empty. On save calls the controller; closes on success.
  - `Future<void> showRecordPaymentSheet(BuildContext context, {required CustomerBalance customer})` — amount (+ optional note); validates amount > 0 and ≤ `customer.balance`; calls `recordPayment`; closes on success.

- [ ] **Step 1: Write the failing widget test**

Create `test/widgets/record_payment_sheet_test.dart`:

```dart
import 'package:ai_shopkeeper/features/customers/domain/customer_balance.dart';
import 'package:ai_shopkeeper/features/customers/presentation/record_payment_sheet.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _customer = CustomerBalance(
  id: 'c1',
  name: 'Rahim',
  phone: '01700000000',
  balance: 150,
);

Widget _host() => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showRecordPaymentSheet(context, customer: _customer),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('rejects a payment larger than the balance', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Enter 500 against a 150 balance.
    await tester.enterText(find.byType(TextFormField).first, '500');
    // Tap the record button (the sheet's primary action).
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    // The over-balance validation message shows; the sheet stays open.
    expect(find.text('More than what is owed'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/record_payment_sheet_test.dart`
Expected: FAIL — `record_payment_sheet.dart` does not exist.

- [ ] **Step 3: Write `record_payment_sheet.dart`**

Implement a `StatefulWidget` sheet body shown via `showModalBottomSheet` with `isScrollControlled: true` and viewInsets padding. A `Form` with:
- amount `TextFormField` (`keyboardType: TextInputType.numberWithOptions(decimal: true)`), validator: parse to double; null/≤0 → `l10n.customers_paymentAmountRequired`; `> customer.balance` → `l10n.customers_paymentTooLarge`.
- optional note `TextFormField`.
- a `Consumer`-wrapped `FilledButton` labelled `l10n.customers_recordPayment`; on press, validate the form, then `await ref.read(customerDetailControllerProvider(customer.id).notifier).recordPayment(...)`; on `true` call `AppHaptics.success()` and `Navigator.pop`, on `false` leave the sheet open (the controller has set an error the detail screen's `ref.listen` surfaces).

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/haptics.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../domain/customer_balance.dart';
import 'customer_detail_controller.dart';

Future<void> showRecordPaymentSheet(
  BuildContext context, {
  required CustomerBalance customer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RecordPaymentSheet(customer: customer),
  );
}

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  const _RecordPaymentSheet({required this.customer});
  final CustomerBalance customer;

  @override
  ConsumerState<_RecordPaymentSheet> createState() =>
      _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final ok = await ref
        .read(customerDetailControllerProvider(widget.customer.id).notifier)
        .recordPayment(
          amount: double.parse(_amount.text.trim()),
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      AppHaptics.success();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.customers_recordPayment,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l10n.customers_paymentAmount),
              validator: (v) {
                final parsed = double.tryParse((v ?? '').trim());
                if (parsed == null || parsed <= 0) {
                  return l10n.customers_paymentAmountRequired;
                }
                if (parsed > widget.customer.balance) {
                  return l10n.customers_paymentTooLarge;
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: InputDecoration(labelText: l10n.customers_paymentNote),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(l10n.customers_recordPayment),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/record_payment_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Write `customer_form_sheet.dart`**

Same sheet pattern. `showCustomerFormSheet(context, {Customer? existing})`:
- name `TextFormField` (required → `l10n.customers_nameRequired`), phone `TextFormField` (`keyboardType: TextInputType.phone`, required → `l10n.customers_phoneRequired`), optional note.
- Pre-fill from `existing` when editing; title `l10n.customers_add` vs `l10n.customers_edit`.
- On save: `existing == null` → `customersControllerProvider.notifier.createCustomer(...)`, else `.updateCustomer(id: existing.id, ...)`. Pop on `true`.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/haptics.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../domain/customer.dart';
import 'customers_controller.dart';

Future<void> showCustomerFormSheet(
  BuildContext context, {
  Customer? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CustomerFormSheet(existing: existing),
  );
}

class _CustomerFormSheet extends ConsumerStatefulWidget {
  const _CustomerFormSheet({this.existing});
  final Customer? existing;

  @override
  ConsumerState<_CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends ConsumerState<_CustomerFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final notifier = ref.read(customersControllerProvider.notifier);
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final ok = widget.existing == null
        ? await notifier.createCustomer(name: name, phone: phone, note: note)
        : await notifier.updateCustomer(
            id: widget.existing!.id, name: name, phone: phone, note: note);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      AppHaptics.success();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? l10n.customers_add : l10n.customers_edit,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.customers_fieldName),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? l10n.customers_nameRequired : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: l10n.customers_fieldPhone),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? l10n.customers_phoneRequired : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: InputDecoration(labelText: l10n.customers_fieldNote),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(l10n.customers_save),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Verify and commit**

Run: `flutter test test/widgets/record_payment_sheet_test.dart` and `flutter analyze`
Expected: PASS / no issues.

```bash
git add lib/features/customers/presentation/customer_form_sheet.dart lib/features/customers/presentation/record_payment_sheet.dart test/widgets/record_payment_sheet_test.dart
git commit -m "feat(customers): add/edit and record-payment sheets

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Customers list + detail screens, and routing

**Files:**
- Create: `lib/features/customers/presentation/customers_screen.dart`
- Create: `lib/features/customers/presentation/customer_detail_screen.dart`
- Modify: `lib/core/router/app_router.dart`

**Interfaces:**
- Consumes: Task 6 controllers, Task 7 sheets, Task 5 strings + `ledgerEntryTypeLabel`, `Money` formatter, `myShopProvider` (for currency), `_transitionPage`/`_rootKey` in the router.
- Produces: routes `AppRoutes.customers = '/customers'` and `'/customers/:id'`; `CustomersScreen`; `CustomerDetailScreen({required String customerId})`.

- [ ] **Step 1: Write `customers_screen.dart`**

A `ConsumerStatefulWidget` (holds a search `TextEditingController`). Watches `customersControllerProvider`. Renders:
- `AppBar(title: l10n.customers_title)`.
- A header showing `receivablesControllerProvider` total via `l10n.customers_receivablesHeader(Money.format(totalOwed, currencyCode: currency), debtorCount)` — hidden when `debtorCount == 0`.
- A search `TextField` (`l10n.customers_searchHint`) filtering the list case-insensitively over name and phone.
- The list: each row shows name, phone, and a trailing balance chip — `l10n.customers_owes(Money.format(balance,...))` when `owes`, else `l10n.customers_settled`. Tap → `context.push('/customers/${c.id}')`.
- Empty state (`l10n.customers_empty` / `customers_emptyHint`) when the unfiltered list is empty.
- A `FloatingActionButton` → `showCustomerFormSheet(context)`.
- `AsyncValue` handling: loading → centered spinner; error → the failure message centered (mirror how other screens render `AsyncError`).

- [ ] **Step 2: Write `customer_detail_screen.dart`**

A `ConsumerWidget` taking `customerId`. Watches `customerDetailControllerProvider(customerId)` for the ledger and reads the matching `CustomerBalance` from `customersControllerProvider` (find by id; if absent, fall back to a header from the ledger via `balanceOf`). Renders:
- `AppBar(title: customer name)` with an edit action → `showCustomerFormSheet(context, existing: ...)`. (Build a `Customer` from the balance row's id/name/phone/note.)
- A balance header: `l10n.customers_balance` + `Money.format(balance, ...)`.
- The ledger list, newest first: each row shows `ledgerEntryTypeLabel(l10n, e.entryType)`, the date, and a signed amount (`+`/`−` with `Money.format(e.amount, ...)`), colored via `AppColors` positive/negative like other money rows. Empty → `l10n.customers_ledgerEmpty`.
- A bottom `FilledButton` `l10n.customers_recordPayment` → `showRecordPaymentSheet(context, customer: balanceRow)`; disable when balance == 0.
- `ref.listen` on the detail provider to surface `AsyncError` failures (e.g. a payment race) as a snackbar, mirroring `cart_screen.dart`.

- [ ] **Step 3: Wire routes in `app_router.dart`**

Add constants to `AppRoutes`:

```dart
  static const String customers = '/customers';
```

Add imports for the two screens, and register (root navigator, like `/categories`):

```dart
      GoRoute(
        path: AppRoutes.customers,
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, _) => _transitionPage(const CustomersScreen()),
      ),
      GoRoute(
        path: '/customers/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, state) => _transitionPage(
          CustomerDetailScreen(customerId: state.pathParameters['id']!),
        ),
      ),
```

- [ ] **Step 4: Verify**

Run: `flutter analyze`
Expected: no issues. Run `flutter test` (full suite) — expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/customers/presentation/customers_screen.dart lib/features/customers/presentation/customer_detail_screen.dart lib/core/router/app_router.dart
git commit -m "feat(customers): list + detail screens and routes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Payment-method controller (cart)

**Files:**
- Create: `lib/features/cart/presentation/payment_method_controller.dart`
- Test: `test/payment_method_controller_test.dart`

**Interfaces:**
- Consumes: `flutter_riverpod`, `Customer` (Task 2).
- Produces:
  - `enum PaymentMethod { cash, credit }`.
  - `PaymentSelection` (immutable): `PaymentMethod method`, `Customer? customer`; `bool get isReady => method == PaymentMethod.cash || customer != null`; `const PaymentSelection.cash()`.
  - `paymentMethodControllerProvider` — `NotifierProvider<PaymentMethodController, PaymentSelection>` with `setCash()`, `setCredit()`, `chooseCustomer(Customer)`, `reset()`.

- [ ] **Step 1: Write the failing test**

Create `test/payment_method_controller_test.dart`:

```dart
import 'package:ai_shopkeeper/features/cart/presentation/payment_method_controller.dart';
import 'package:ai_shopkeeper/features/customers/domain/customer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _rahim = Customer(id: 'c1', shopId: 's', name: 'Rahim', phone: '017');

void main() {
  late ProviderContainer c;
  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  PaymentSelection read() => c.read(paymentMethodControllerProvider);
  PaymentMethodController notifier() =>
      c.read(paymentMethodControllerProvider.notifier);

  test('defaults to cash and is ready', () {
    expect(read().method, PaymentMethod.cash);
    expect(read().isReady, isTrue);
  });

  test('credit with no customer is not ready', () {
    notifier().setCredit();
    expect(read().method, PaymentMethod.credit);
    expect(read().customer, isNull);
    expect(read().isReady, isFalse);
  });

  test('choosing a customer makes credit ready', () {
    notifier().setCredit();
    notifier().chooseCustomer(_rahim);
    expect(read().customer, _rahim);
    expect(read().isReady, isTrue);
  });

  test('switching back to cash clears the customer and is ready', () {
    notifier().setCredit();
    notifier().chooseCustomer(_rahim);
    notifier().setCash();
    expect(read().method, PaymentMethod.cash);
    expect(read().customer, isNull);
    expect(read().isReady, isTrue);
  });

  test('reset returns to cash', () {
    notifier().setCredit();
    notifier().chooseCustomer(_rahim);
    notifier().reset();
    expect(read().method, PaymentMethod.cash);
    expect(read().customer, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/payment_method_controller_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the controller**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../customers/domain/customer.dart';

/// How the current cart will be paid for.
enum PaymentMethod { cash, credit }

/// The cart's payment selection: the method and, for credit, the chosen
/// customer. A credit sale is only [isReady] once a customer is chosen.
class PaymentSelection {
  const PaymentSelection({required this.method, this.customer});
  const PaymentSelection.cash() : this(method: PaymentMethod.cash);

  final PaymentMethod method;
  final Customer? customer;

  bool get isReady =>
      method == PaymentMethod.cash || customer != null;

  PaymentSelection copyWith({PaymentMethod? method, Customer? customer}) =>
      PaymentSelection(
        method: method ?? this.method,
        customer: customer ?? this.customer,
      );
}

class PaymentMethodController extends Notifier<PaymentSelection> {
  @override
  PaymentSelection build() => const PaymentSelection.cash();

  void setCash() => state = const PaymentSelection.cash();

  void setCredit() =>
      state = const PaymentSelection(method: PaymentMethod.credit);

  void chooseCustomer(Customer customer) => state =
      PaymentSelection(method: PaymentMethod.credit, customer: customer);

  void reset() => state = const PaymentSelection.cash();
}

final paymentMethodControllerProvider =
    NotifierProvider<PaymentMethodController, PaymentSelection>(
      PaymentMethodController.new,
    );
```

> Note: `copyWith` cannot null-out `customer` (nullable copyWith limitation), which is why `setCash`/`setCredit` build fresh instances instead. `copyWith` is retained only if a later call site needs it; if unused, delete it to keep the class lean.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/payment_method_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/cart/presentation/payment_method_controller.dart test/payment_method_controller_test.dart
git commit -m "feat(cart): payment-method (cash/credit) selection state

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: Thread customerId through checkout

**Files:**
- Modify: `lib/features/transactions/data/transaction_repository.dart` (`recordSaleCart`, ~lines 33-51)
- Modify: `lib/features/cart/presentation/cart_checkout_controller.dart`

**Interfaces:**
- Consumes: `record_sale_cart` RPC's new `p_customer_id` param (Task 1); `paymentMethodControllerProvider` (Task 9); `customersControllerProvider` + `receivablesControllerProvider` (Task 6).
- Produces:
  - `recordSaleCart({..., String? customerId})` — forwards `p_customer_id` only when non-null.
  - `CartCheckoutController.checkout({String source = 'manual', String? customerId})` — passes `customerId`; on success additionally invalidates customer/receivables providers.

- [ ] **Step 1: Extend `recordSaleCart`**

In `transaction_repository.dart`, change the signature and params:

```dart
  Future<Result<List<Transaction>>> recordSaleCart({
    required String shopId,
    required List<Map<String, dynamic>> items,
    String source = 'manual',
    String? customerId,
  }) async {
    try {
      final result = await _client.rpc(
        'record_sale_cart',
        params: {
          'p_shop_id': shopId,
          'p_items': items,
          'p_source': source,
          if (customerId != null) 'p_customer_id': customerId,
        },
      );
      final rows = result as List;
      return Result.success([
        for (final r in rows)
          Transaction.fromJson(Map<String, dynamic>.from(r as Map)),
      ]);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }
```

- [ ] **Step 2: Extend `CartCheckoutController.checkout`**

Add the parameter and post-success invalidation. Add imports for `customersControllerProvider` and `receivablesControllerProvider`:

```dart
  Future<bool> checkout({String source = 'manual', String? customerId}) async {
    final shopId = ref.read(myShopProvider).value?.id;
    final lines = ref.read(cartControllerProvider);
    if (shopId == null) {
      state = AsyncError(
        const AuthFailure('No shop found for this account.'),
        StackTrace.current,
      );
      return false;
    }
    if (lines.isEmpty) return false;

    state = const AsyncLoading();
    final result = await ref
        .read(transactionRepositoryProvider)
        .recordSaleCart(
          shopId: shopId,
          items: cartItemsPayload(lines),
          source: source,
          customerId: customerId,
        );
    return result.when(
      success: (_) {
        ref.read(cartControllerProvider.notifier).clear();
        ref.invalidate(productsStreamProvider);
        ref.read(dataRefreshProvider.notifier).bump();
        if (customerId != null) {
          ref.invalidate(customersControllerProvider);
          ref.invalidate(receivablesControllerProvider);
        }
        state = const AsyncData(null);
        return true;
      },
      failure: (f) {
        state = AsyncError(f, StackTrace.current);
        return false;
      },
    );
  }
```

- [ ] **Step 3: Verify existing tests still pass**

Run: `flutter test test/cart_math_test.dart test/widgets/cart_screen_test.dart`
Expected: PASS (signatures are additive; the cash path is unchanged). Then `flutter analyze`.

- [ ] **Step 4: Commit**

```bash
git add lib/features/transactions/data/transaction_repository.dart lib/features/cart/presentation/cart_checkout_controller.dart
git commit -m "feat(cart): thread optional customerId through checkout

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11: Cart Cash/Credit UI + customer picker

**Files:**
- Create: `lib/features/customers/presentation/customer_picker_sheet.dart`
- Modify: `lib/features/cart/presentation/cart_screen.dart`
- Test: `test/widgets/cart_payment_toggle_test.dart`

**Interfaces:**
- Consumes: `paymentMethodControllerProvider` (Task 9), `customersControllerProvider` (Task 6), `showCustomerFormSheet` (Task 7), Task 5 strings, `SegmentPills` (`lib/core/widgets/segment_pills.dart`).
- Produces:
  - `Future<Customer?> showCustomerPickerSheet(BuildContext context)` — searchable list of customers + "add new"; returns the chosen `Customer` (or null if dismissed).
  - Cart screen: a Cash/Credit `SegmentPills` above the checkout bar; when Credit, a row showing the chosen customer or a "Select customer" button; checkout button label switches to `cart_addToKhata(name)` and is **disabled** while credit is selected without a customer; checkout passes `customerId`; success snackbar uses `cart_addedToKhata` for credit.

- [ ] **Step 1: Write `customer_picker_sheet.dart`**

A modal sheet (`ConsumerStatefulWidget`) that watches `customersControllerProvider`, shows a search field + tappable list (name + phone; balance chip optional), and a top "＋ Add new" action that calls `showCustomerFormSheet(context)` then, after it returns, lets the user pick the newly added customer from the refreshed list. Tapping a customer `Navigator.pop(context, customer)`.

- [ ] **Step 2: Wire the toggle into `cart_screen.dart`**

In the `_CheckoutBar` (or as a new section directly above it), read `paymentMethodControllerProvider`:
- Add a `SegmentPills<PaymentMethod>` with labels `cart_paymentCash` / `cart_paymentCredit`, calling `setCash()` / `setCredit()`.
- When `method == credit`: show the selected customer's name, or a `cart_selectCustomer` button that does `final chosen = await showCustomerPickerSheet(context); if (chosen != null) ref.read(paymentMethodControllerProvider.notifier).chooseCustomer(chosen);`.
- Checkout button: label is `cart_checkout` for cash, `cart_addToKhata(customer.name)` for credit; `onPressed` is null (disabled) when `!selection.isReady || isLoading`.
- Update `_checkout(...)` to read the selection, pass `customerId: selection.customer?.id`, and after success reset the selection: `ref.read(paymentMethodControllerProvider.notifier).reset();`. For the success snackbar, use `cart_addedToKhata(name, total)` when it was a credit sale, else the existing `cart_itemsSold`.

Because `_CheckoutBar` is currently a `StatelessWidget` taking plain values, convert it to a `ConsumerWidget` (or lift the selection read into `CartScreen.build` and pass `selection` + callbacks down). Keep the `MainAxisSize.min` bounded-height structure noted in its doc comment.

Also: clear the payment selection when the cart is cleared — in `_confirmClear`'s success branch and wherever `cartControllerProvider.clear()` is called from this screen, also call `paymentMethodControllerProvider.notifier).reset()`.

- [ ] **Step 3: Write the failing widget test**

Create `test/widgets/cart_payment_toggle_test.dart`. Override providers so the cart has one line and `myShopProvider` yields a shop; pump `CartScreen`; assert:
- Cash is selected by default and the checkout button is enabled.
- Tapping "Credit" disables the checkout button (no customer yet) and shows the `cart_selectCustomer` affordance.

Use the existing `test/widgets/cart_screen_test.dart` as the template for provider overrides and pumping. Assert on the disabled state via `tester.widget<FilledButton>(...).onPressed == null` (or `.enabled`).

- [ ] **Step 4: Run tests**

Run: `flutter test test/widgets/cart_payment_toggle_test.dart test/widgets/cart_screen_test.dart`
Expected: PASS. Then `flutter analyze`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/customers/presentation/customer_picker_sheet.dart lib/features/cart/presentation/cart_screen.dart test/widgets/cart_payment_toggle_test.dart
git commit -m "feat(cart): Cash/Credit toggle with customer picker

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 12: Dashboard receivables card

**Files:**
- Create: `lib/features/dashboard/presentation/receivables_card.dart`
- Modify: `lib/features/dashboard/presentation/dashboard_screen.dart`

**Interfaces:**
- Consumes: `receivablesControllerProvider` (Task 6), `Money` formatter, `myShopProvider` (currency), `AppRoutes.customers` (Task 8), `context.l10n`.
- Produces: `ReceivablesCard` — renders nothing when `debtorCount == 0` or while loading/errored; otherwise a tappable card ("Receivables · {amount} owed · {n} customers") that `context.push(AppRoutes.customers)`.

- [ ] **Step 1: Write `receivables_card.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../../customers/presentation/receivables_controller.dart';

/// Dashboard card summarizing outstanding customer credit. Hidden entirely when
/// nobody owes anything, so cash-only shops see no extra clutter.
class ReceivablesCard extends ConsumerWidget {
  const ReceivablesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(receivablesControllerProvider).valueOrNull;
    if (summary == null || summary.debtorCount == 0) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(AppRoutes.customers),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.dashboard_receivablesTitle,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      l10n.customers_receivablesHeader(
                        Money.format(summary.totalOwed, currencyCode: currency),
                        summary.debtorCount,
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Mount it on the dashboard**

In `dashboard_screen.dart`, add `import '...receivables_card.dart';` and place `const ReceivablesCard()` in the dashboard's scrolling column — directly under the revenue hero / above the secondary cards. Match the surrounding padding/spacing (wrap in the same horizontal padding the neighbouring sections use). Since the card self-hides at zero debtors, no conditional is needed at the call site.

- [ ] **Step 3: Verify**

Run: `flutter analyze` and `flutter test`
Expected: no issues; all tests green. Confirm the dashboard still renders by reading the file to ensure the widget sits inside the existing scroll view (not below a fixed-height region).

- [ ] **Step 4: Commit**

```bash
git add lib/features/dashboard/presentation/receivables_card.dart lib/features/dashboard/presentation/dashboard_screen.dart
git commit -m "feat(dashboard): receivables card linking to customers

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 13: Full-suite verification + manual QA

**Files:** none (verification only).

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze` then `flutter test`
Expected: no analyzer issues; entire suite green (including `l10n_parity_test`).

- [ ] **Step 2: Manual QA on the physical S22**

Build/run with the Supabase dart-defines. Walk the flow:
1. Dashboard shows no receivables card (no debts yet).
2. Add a customer (name + phone required; empty either → validation error).
3. Cart → Credit → pick that customer → "Add to {name}'s khata" → sale commits; stock drops; success snackbar.
4. Dashboard now shows the receivables card with the right total; tap → customers list; customer shows the owed amount.
5. Open the customer → ledger shows the credit sale; Record payment for part of it → balance drops; for the full remainder → balance hits 0, "Settled".
6. Try to overpay → blocked with the "more than what is owed" message.
7. Delete a settled customer → succeeds; delete one who owes (add a fresh debt first) → blocked with the DB message.
8. Toggle app to Bengali (Settings) → all new screens/labels render in Bengali, no `MISSING` keys.
9. Airplane mode → the offline banner shows; a credit checkout fails cleanly (no hang, snackbar error), cart preserved.

- [ ] **Step 3: Final commit (if any QA fixes were needed)**

Commit any fixes discovered during QA with a clear message. If none, nothing to do.

---

## Notes on the atomicity guarantee (the design's keystone)

The insufficient-stock-mid-credit-sale rollback (spec's "critical" test) is enforced entirely by Postgres: `record_sale_cart` runs its whole body — customer check, per-line stock locks/decrements/inserts, and the ledger insert — inside one implicit transaction, so any `raise exception` rolls back everything. It cannot be exercised by a Dart unit test without a live database, so it is verified by **Task 1 Step 3** (SQL smoke test — extend it to attempt a two-line credit sale where the second line oversells, then confirm `select * from customer_ledger` and stock are unchanged) and **Task 13 Step 2**. Do not attempt to reproduce this in-memory; asserting on the real DB is the meaningful test.
