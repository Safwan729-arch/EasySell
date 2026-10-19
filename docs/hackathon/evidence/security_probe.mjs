// Security test of the LIVE project from outside.
//
//   EV_CREDS=<creds.json> node security_probe.mjs
//
// Part 1 uses only the public anon key, which ships inside every APK: it is
// what anyone who unpacks the app can do. Part 2 signs in as test shop B and
// tries to read and change test shop A's data.
import { randomUUID } from "node:crypto";
import { ANON, URL_, fn, loadCreds, rest, rpc, save, signIn, stamp } from "./lib.mjs";

const TABLES = ["users", "shops", "products", "transactions", "customers", "customer_ledger",
  "product_batches", "categories", "analytics_daily", "notifications"];
const results = [];
const record = (part, name, pass, detail) => {
  results.push({ part, name, pass, ...detail });
  console.log(`${pass ? "PASS" : "FAIL"}  ${name}  ${JSON.stringify(detail)}`);
};

// ---- Part 1: the public key only ----
const tableReads = [];
for (const t of TABLES) {
  const r = await rest(`${t}?select=*&limit=5`, { prefer: "count=exact" });
  tableReads.push({ table: t, status: r.status, rows: Array.isArray(r.data) ? r.data.length : 0, total: r.range });
}
record(1, "Every table returns 0 rows to the public key",
  tableReads.every((t) => t.rows === 0),
  { tables: tableReads.length, rowsVisible: tableReads.reduce((s, t) => s + t.rows, 0) });

const schema = await rest("");
record(1, "The database schema listing is not public", !(schema.data && schema.data.paths),
  { status: schema.status });

for (const f of ["parse-sale", "recognize-product", "money-tips"]) {
  const noToken = await fn(f, {}, null);
  const anon = await fn(f, {}, ANON);
  record(1, `${f}: refused without sign-in`, noToken.status === 401 && anon.status === 401,
    { noToken: noToken.status, publicKey: anon.status });
}

const guest = await fetch(`${URL_}/auth/v1/signup`, {
  method: "POST", headers: { apikey: ANON, "Content-Type": "application/json" }, body: "{}",
});
const guestBody = await guest.json().catch(() => ({}));
record(1, "Guest (anonymous) sign-in is off", !guest.ok,
  { status: guest.status, message: guestBody.msg ?? guestBody.error_description ?? guestBody.error_code });

const buckets = await fetch(`${URL_}/storage/v1/bucket`, { headers: { apikey: ANON, Authorization: `Bearer ${ANON}` } });
const bucketList = await buckets.json().catch(() => []);
record(1, "No file storage is open to the public", !Array.isArray(bucketList) || bucketList.length === 0,
  { status: buckets.status, buckets: Array.isArray(bucketList) ? bucketList.length : 0 });

// ---- Part 2: a signed-in owner of shop B against shop A ----
const { a, b } = loadCreds();
const A = await signIn(a.email, a.password);
const B = await signIn(b.email, b.password);
const aProducts = (await rest(`products?shop_id=eq.${a.shopId}&select=id,quantity,selling_price`, { token: A.token })).data;
const target = aProducts[0];

const reads = [];
for (const t of ["shops", "products", "transactions", "customers", "customer_ledger"]) {
  const col = t === "shops" ? "id" : "shop_id";
  const r = await rest(`${t}?${col}=eq.${a.shopId}&select=*`, { token: B.token });
  reads.push({ table: t, rows: r.data.length });
}
record(2, "Shop B reads shop A's tables: 0 rows", reads.every((r) => r.rows === 0),
  { aOwnRows: aProducts.length, bSees: reads });

const summary = await rpc("get_dashboard_summary", { p_shop_id: a.shopId, p_period: "month", p_utc_offset_minutes: 360 }, B.token);
const s = Array.isArray(summary.data) ? summary.data[0] : summary.data;
const allZero = s && Object.values(s).every((v) => v === null || Number(v) === 0);
record(2, "Shop B asks for shop A's dashboard: all zeros", summary.status === 200 && allZero,
  { status: summary.status, revenueSeen: s?.revenue ?? null });

const steal = await rpc("record_sale_cart", { p_shop_id: a.shopId, p_items: [{ product_id: target.id, quantity: 1 }], p_sale_group_id: randomUUID() }, B.token);
const qtyAfterSteal = (await rest(`products?id=eq.${target.id}&select=quantity`, { token: A.token })).data[0].quantity;
record(2, "Shop B tries to record a sale in shop A: refused", steal.status !== 200 && Number(qtyAfterSteal) === Number(target.quantity),
  { status: steal.status, message: steal.data?.message, aStockBefore: Number(target.quantity), aStockAfter: Number(qtyAfterSteal) });

const edit = await rest(`products?id=eq.${target.id}`, { token: B.token, method: "PATCH", prefer: "return=representation", body: { selling_price: 1 } });
const priceAfter = (await rest(`products?id=eq.${target.id}&select=selling_price`, { token: A.token })).data[0].selling_price;
record(2, "Shop B tries to change shop A's price: nothing changes", Number(priceAfter) === Number(target.selling_price),
  { status: edit.status, rowsChanged: Array.isArray(edit.data) ? edit.data.length : 0, aPriceAfter: Number(priceAfter) });

const plant = await rest("products", { token: B.token, method: "POST", body: { shop_id: a.shopId, name: "planted", quantity: 1, selling_price: 1 } });
record(2, "Shop B tries to add a product to shop A: refused", plant.status >= 400,
  { status: plant.status, message: plant.data?.message });

const big = await fn("parse-sale", { transcript: "x".repeat(2500), candidates: [{ i: 0, name: "x" }] }, B.token);
record(2, "Oversized AI request refused before reaching Gemini", big.status === 413, { status: big.status });

const out = { ranAt: stamp(), passed: results.filter((r) => r.pass).length, total: results.length, results, tableReads };
save("security_probe.json", out);
console.log(`${out.passed}/${out.total} passed`);
