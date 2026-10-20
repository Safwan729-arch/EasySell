// Runs migration 0021 on PGlite against a minimal copy of the schema and
// checks every same-shop link. Usage: node test0021.mjs <path to 0021 sql>
import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";

const migration = readFileSync(process.argv[2], "utf8");
let failed = 0;
const check = (name, ok, extra = "") => {
  console.log(`${ok ? "PASS" : "FAIL"} ${name} ${extra}`);
  if (!ok) failed++;
};

const schema = `
  create table shops (id uuid primary key default gen_random_uuid());
  create table categories (id uuid primary key default gen_random_uuid(),
    shop_id uuid not null references shops(id) on delete cascade);
  create table products (id uuid primary key default gen_random_uuid(),
    shop_id uuid not null references shops(id) on delete cascade,
    category_id uuid references categories(id) on delete set null,
    constraint products_id_shop_unique unique (id, shop_id));
  create table product_batches (id uuid primary key default gen_random_uuid(),
    shop_id uuid not null references shops(id) on delete cascade, product_id uuid not null,
    constraint product_batches_product_same_shop foreign key (product_id, shop_id)
      references products (id, shop_id) on delete cascade);
  create table transactions (id uuid primary key default gen_random_uuid(),
    shop_id uuid not null references shops(id) on delete cascade,
    product_id uuid not null references products(id),
    batch_id uuid references product_batches (id) on delete set null);
  create table customers (id uuid primary key default gen_random_uuid(),
    shop_id uuid not null references shops(id) on delete cascade);
  create table customer_ledger (id uuid primary key default gen_random_uuid(),
    shop_id uuid not null references shops(id) on delete cascade,
    customer_id uuid not null references customers(id) on delete cascade);
  create table notifications (id uuid primary key default gen_random_uuid(),
    shop_id uuid not null references shops(id) on delete cascade,
    product_id uuid references products(id) on delete set null);
`;

const fresh = async () => {
  const db = new PGlite();
  await db.exec(schema);
  return db;
};
const one = async (db, sql, params) => (await db.query(sql, params)).rows[0];
const fails = async (db, sql, params) => {
  try { await db.query(sql, params); return null; } catch (e) { return e.message; }
};

// Two shops, each with a category, product, batch and customer.
async function seed(db) {
  const ids = {};
  for (const s of ["a", "b"]) {
    ids[s] = (await one(db, "insert into shops default values returning id")).id;
    ids[`${s}cat`] = (await one(db, "insert into categories (shop_id) values ($1) returning id", [ids[s]])).id;
    ids[`${s}prod`] = (await one(db, "insert into products (shop_id, category_id) values ($1, $2) returning id", [ids[s], ids[`${s}cat`]])).id;
    ids[`${s}batch`] = (await one(db, "insert into product_batches (shop_id, product_id) values ($1, $2) returning id", [ids[s], ids[`${s}prod`]])).id;
    ids[`${s}cust`] = (await one(db, "insert into customers (shop_id) values ($1) returning id", [ids[s]])).id;
  }
  return ids;
}

// --- A: the migration on a clean database, run twice ---
{
  const db = await fresh();
  const ids = await seed(db);
  await db.exec(migration);
  check("migration runs", true);
  await db.exec(migration);
  check("migration re-runs with no change", true);

  const fk = await db.query("select conname from pg_constraint where contype = 'f' and conname like '%same_shop' order by 1");
  check("6 same-shop links in place (5 new + 1 from 0011)", fk.rows.length === 6, fk.rows.map((r) => r.conname).join(","));
  const single = await db.query(`select c.conname from pg_constraint c where c.contype = 'f'
    and array_length(c.conkey, 1) = 1 and c.confrelid in ('products'::regclass, 'customers'::regclass, 'product_batches'::regclass, 'categories'::regclass)`);
  check("no single-column link to those tables is left", single.rows.length === 0, single.rows.map((r) => r.conname).join(","));

  // Same-shop rows still work.
  const tx = await one(db, "insert into transactions (shop_id, product_id, batch_id) values ($1, $2, $3) returning id", [ids.b, ids.bprod, ids.bbatch]);
  check("same-shop sale row with a batch is saved", !!tx.id);
  check("same-shop ledger row is saved", !(await fails(db, "insert into customer_ledger (shop_id, customer_id) values ($1, $2)", [ids.b, ids.bcust])));
  check("same-shop notification is saved", !(await fails(db, "insert into notifications (shop_id, product_id) values ($1, $2)", [ids.b, ids.bprod])));
  check("same-shop category on a product is saved", !(await fails(db, "insert into products (shop_id, category_id) values ($1, $2)", [ids.b, ids.bcat])));
  check("a sale row with no batch is saved", !(await fails(db, "insert into transactions (shop_id, product_id) values ($1, $2)", [ids.b, ids.bprod])));

  // Cross-shop rows are refused (the L1 attack).
  check("sale row naming another shop's product refused", !!(await fails(db, "insert into transactions (shop_id, product_id) values ($1, $2)", [ids.b, ids.aprod])));
  check("sale row naming another shop's batch refused", !!(await fails(db, "insert into transactions (shop_id, product_id, batch_id) values ($1, $2, $3)", [ids.b, ids.bprod, ids.abatch])));
  check("ledger row naming another shop's customer refused", !!(await fails(db, "insert into customer_ledger (shop_id, customer_id) values ($1, $2)", [ids.b, ids.acust])));
  check("notification naming another shop's product refused", !!(await fails(db, "insert into notifications (shop_id, product_id) values ($1, $2)", [ids.b, ids.aprod])));
  check("product naming another shop's category refused", !!(await fails(db, "insert into products (shop_id, category_id) values ($1, $2)", [ids.b, ids.acat])));
  check("moving a sale row's shop_id away from its product refused", !!(await fails(db, "update transactions set shop_id = $1 where id = $2", [ids.a, tx.id])));

  // Delete behaviour unchanged.
  await db.query("delete from product_batches where id = $1", [ids.bbatch]);
  const after = await one(db, "select batch_id, shop_id from transactions where id = $1", [tx.id]);
  check("deleting a batch clears batch_id and keeps shop_id", after.batch_id === null && after.shop_id === ids.b);
  await db.query("delete from customers where id = $1", [ids.bcust]);
  check("deleting a customer still deletes their ledger", (await one(db, "select count(*)::int n from customer_ledger where customer_id = $1", [ids.bcust])).n === 0);
  await db.query("delete from categories where id = $1", [ids.bcat]);
  const prod = await one(db, "select category_id, shop_id from products where id = $1", [ids.bprod]);
  check("deleting a category clears category_id and keeps shop_id", prod.category_id === null && prod.shop_id === ids.b);
  check("a product with sales still can't be deleted", !!(await fails(db, "delete from products where id = $1", [ids.bprod])));
  await db.query("delete from shops where id = $1", [ids.b]);
  check("deleting a whole shop still removes all its rows", (await one(db, "select count(*)::int n from transactions where shop_id = $1", [ids.b])).n === 0);
}

// --- B: an existing cross-shop row stops the migration and changes nothing ---
{
  const db = await fresh();
  const ids = await seed(db);
  await db.query("insert into transactions (shop_id, product_id) values ($1, $2)", [ids.b, ids.aprod]);
  let msg = null; try { await db.exec(migration); } catch (e) { msg = e.message; }
  check("existing cross-shop row stops the migration with a clear message", /0021: 1 transactions rows name another shop's product/.test(msg ?? ""), msg ?? "");
  await db.exec("rollback").catch(() => {});
  const n = (await one(db, "select count(*)::int n from pg_constraint where conname like '%same_shop' or conname like '%id_shop_unique'")).n;
  check("…and leaves the schema as it was", n === 2, `constraints=${n}`);
}

console.log(failed ? `${failed} FAILED` : "all passed");
process.exit(failed ? 1 : 0);
