// Builds the full database (migrations 0001-0022) on PGlite and checks that
// sales and credit rows change only through the app's database functions.
// Usage: node test0022.mjs <migrations dir>
import { randomUUID } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { buildDb, tryAsUser } from "./fullschema.mjs";

const dir = process.argv[2];
const { db } = await buildDb(dir);
let failed = 0;
const check = (name, ok, extra = "") => {
  console.log(`${ok ? "PASS" : "FAIL"} ${name} ${extra}`);
  if (!ok) failed++;
};
const refused = (r) => !!r.error && /can only be changed|can only be removed/.test(r.error);
const one = async (sql, p) => (await db.query(sql, p)).rows[0];

// Two owners, as Supabase sign-up would make them (admin inserts, like Auth).
const u = randomUUID(), other = randomUUID();
for (const id of [u, other]) await db.query("insert into auth.users (id, email) values ($1, $2)", [id, `${id}@t.dev`]);
const shop = (await one("insert into shops (owner_id, name) values ($1, 'S') returning id", [u])).id;
const prod = (await one("insert into products (shop_id, name, quantity, buying_price, selling_price) values ($1, 'Pepsi', 20, 30, 40) returning id", [shop])).id;
const prod2 = (await one("insert into products (shop_id, name, quantity, buying_price, selling_price) values ($1, 'Rice', 10, 50, 60) returning id", [shop])).id;
const cust = (await one("insert into customers (shop_id, name, phone) values ($1, 'Rahim', '01700000000') returning id", [shop])).id;
const fresh = (await one("insert into customers (shop_id, name, phone) values ($1, 'New', '01700000000') returning id", [shop])).id;

// Each writer function marks itself exactly once.
const defs = await db.query(`select p.proname, pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in ('record_sale','record_sale_cart','record_restock','record_payment','delete_customer','remove_batch_stock','remove_undated_stock','remove_expired_stock')`);
check("all 8 writer functions carry the flag line once", defs.rows.length === 8 && defs.rows.every((r) => r.d.split("easysell.via_rpc").length === 2),
  defs.rows.map((r) => `${r.proname}:${r.d.split("easysell.via_rpc").length - 1}`).join(" "));
for (const r of defs.rows) {
  const at = r.d.indexOf("perform set_config('easysell.via_rpc'");
  const before = r.d.slice(0, at).trimEnd().split(/\s+/).at(-1).toLowerCase();
  if (before !== "begin") check(`${r.proname}: flag line sits right after BEGIN`, false, `follows "${before}"`);
}

// --- The app's own paths still work ---
const g = randomUUID();
const sale = await tryAsUser(db, u, `select * from record_sale_cart($1, $2::jsonb, 'manual', $3, 5, $4, 'credit')`,
  [shop, JSON.stringify([{ product_id: prod, quantity: 2 }, { product_id: prod2, quantity: 1 }]), cust, g]);
check("checkout (2 lines, credit, discount) works", !sale.error && sale.rows.length === 2, sale.error ?? "");
const retry = await tryAsUser(db, u, `select * from record_sale_cart($1, $2::jsonb, 'manual', $3, 5, $4, 'credit')`,
  [shop, JSON.stringify([{ product_id: prod, quantity: 2 }, { product_id: prod2, quantity: 1 }]), cust, g]);
const saleRows = (await one("select count(*)::int n from transactions where sale_group_id = $1", [g])).n;
check("a retried checkout is still saved once", !retry.error && saleRows === 2, retry.error ?? `rows=${saleRows}`);
const disc = (await one("select sum(discount_amount)::numeric n from transactions where sale_group_id = $1", [g])).n;
check("the discount is still split onto the lines", Number(disc) === 5, `sum=${disc}`);
const owed = (await one("select coalesce(sum(case when entry_type='credit_sale' then amount else -amount end),0)::numeric n from customer_ledger where customer_id = $1", [cust])).n;
check("the credit sale reached the ledger", Number(owed) === 135, `owed=${owed}`);

const pay = await tryAsUser(db, u, "select * from record_payment($1, $2, 35, 'cash', $3)", [shop, cust, randomUUID()]);
check("record_payment works", !pay.error, pay.error ?? "");
const rs = await tryAsUser(db, u, "select * from record_restock($1, $2, 10, 'manual', current_date + 30, current_date, $3)", [shop, prod, randomUUID()]);
check("record_restock with an expiry date works", !rs.error, rs.error ?? "");
const batch = (await one("select id from product_batches where product_id = $1 order by created_at desc limit 1", [prod])).id;
const rb = await tryAsUser(db, u, "select * from remove_batch_stock($1, $2, 2, false, $3)", [shop, batch, randomUUID()]);
check("remove_batch_stock works", !rb.error, rb.error ?? "");
const ru = await tryAsUser(db, u, "select * from remove_undated_stock($1, $2, 1, $3)", [shop, prod2, randomUUID()]);
check("remove_undated_stock works", !ru.error, ru.error ?? "");
const old = (await one(`insert into product_batches (shop_id, product_id, quantity, buying_price, received_on, expiry_date, expired_qty)
  values ($1, $2, 3, 30, current_date - 20, current_date - 2, 3) returning id`, [shop, prod])).id;
const re = await tryAsUser(db, u, "select * from remove_expired_stock($1, $2)", [shop, old]);
check("remove_expired_stock works", !re.error, re.error ?? "");

// --- Direct writes by the owner are refused (the M2 attack) ---
const anySale = (await one("select id from transactions where sale_group_id = $1 limit 1", [g])).id;
check("owner changes a past sale's price directly: refused", refused(await tryAsUser(db, u, "update transactions set selling_price = 999 where id = $1", [anySale])));
check("owner deletes a past sale directly: refused", refused(await tryAsUser(db, u, "delete from transactions where id = $1", [anySale])));
check("owner inserts a sale row directly: refused", refused(await tryAsUser(db, u,
  "insert into transactions (shop_id, product_id, type, quantity, buying_price, selling_price) values ($1, $2, 'sale', 1, 0, 0)", [shop, prod])));
const led = (await one("select id from customer_ledger where customer_id = $1 limit 1", [cust])).id;
check("owner changes a credit entry directly: refused", refused(await tryAsUser(db, u, "update customer_ledger set amount = 1 where id = $1", [led])));
check("owner deletes a credit entry directly: refused", refused(await tryAsUser(db, u, "delete from customer_ledger where id = $1", [led])));
check("owner adds a fake payment directly: refused", refused(await tryAsUser(db, u,
  "insert into customer_ledger (shop_id, customer_id, entry_type, amount) values ($1, $2, 'payment', 100)", [shop, cust])));
check("owner deletes a customer with credit history directly: refused", refused(await tryAsUser(db, u, "delete from customers where id = $1", [cust])));
check("the refusal is a permission error (PostgREST answers 403)", /42501|can only/.test((await tryAsUser(db, u, "delete from transactions where id = $1", [anySale])).error ?? ""));
const priceNow = (await one("select selling_price from transactions where id = $1", [anySale])).selling_price;
check("…and the sale is untouched", Number(priceNow) === 40, `price=${priceNow}`);

// Reads still work.
const reads = await tryAsUser(db, u, "select count(*)::int n from transactions where shop_id = $1", [shop]);
check("owner can still read their sales", !reads.error && reads.rows[0].n > 0, reads.error ?? "");
const otherReads = await tryAsUser(db, other, "select count(*)::int n from transactions where shop_id = $1", [shop]);
check("another owner still sees none of them", !otherReads.error && otherReads.rows[0].n === 0);

// --- Things that must keep working ---
const del = await tryAsUser(db, u, "delete from customers where id = $1", [fresh]);
check("deleting a customer with no history directly still works", !del.error, del.error ?? "");
const settled = (await one("insert into customers (shop_id, name, phone) values ($1, 'Settled', '01700000000') returning id", [shop])).id;
await db.query("insert into customer_ledger (shop_id, customer_id, entry_type, amount) values ($1, $2, 'credit_sale', 10), ($1, $2, 'payment', 10)", [shop, settled]);
const dc = await tryAsUser(db, u, "select delete_customer($1, $2)", [shop, settled]);
check("delete_customer on a settled customer with history works", !dc.error, dc.error ?? "");
check("…and removed their ledger", (await one("select count(*)::int n from customer_ledger where customer_id = $1", [settled])).n === 0);
check("admin (SQL editor) can still insert a sale row", !(await db.query(
  "insert into transactions (shop_id, product_id, type, quantity, buying_price, selling_price) values ($1, $2, 'sale', 1, 30, 40)", [shop, prod]).then(() => null, (e) => e.message)));
const picked = (await one("select id from transactions where batch_id is not null limit 1"))?.id;
const bdel = await tryAsUser(db, u, "delete from product_batches where id = $1", [batch]);
check("deleting a delivery still clears batch_id on its sales", !bdel.error, bdel.error ?? `picked=${picked}`);
const shopDel = await tryAsUser(db, u, "delete from shops where id = $1", [shop]);
check("deleting a whole shop still removes everything", !shopDel.error && (await one("select count(*)::int n from transactions where shop_id = $1", [shop])).n === 0, shopDel.error ?? "");

// --- Re-run ---
await db.exec(fs.readFileSync(path.join(dir, "0022_money_rows_rpc_only.sql"), "utf8"));
const again = await db.query(`select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'record_sale_cart'`);
check("re-running 0022 adds nothing", again.rows[0].d.split("easysell.via_rpc").length === 2);

console.log(failed ? `${failed} FAILED` : "all passed");
process.exit(failed ? 1 : 0);
