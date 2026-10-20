// Extra attacks for the security self-assessment, run after setup.mjs and
// money_safety.mjs have filled test shop A. Shop B (a real signed-in account)
// tries the cross-tenant and integrity paths the evidence probe does not cover.
import { writeFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { loadCreds, rest, rpc, signIn, fn, stamp } from "../evidence/lib.mjs";

const { a, b } = loadCreds();
const A = await signIn(a.email, a.password);
const B = await signIn(b.email, b.password);
const out = { ranAt: stamp(), checks: [] };
const record = (name, pass, detail) => { out.checks.push({ name, pass, detail }); console.log(pass ? "PASS" : "FAIL", name, JSON.stringify(detail)); };

const aProd = (await rest(`products?shop_id=eq.${a.shopId}&select=id,quantity&limit=1`, { token: A.token })).data[0];
const aCust = (await rest(`customers?shop_id=eq.${a.shopId}&select=id&limit=1`, { token: A.token })).data[0];
// Shop B gets one product of its own, so it can make real sales below.
const bProd = (await rest("products", { token: B.token, method: "POST", prefer: "return=representation",
  body: { shop_id: b.shopId, name: "Probe item", quantity: 10, buying_price: 1, selling_price: 2 } })).data[0];

// 1. Take over shop A by pointing it at B's account (owner_id), or move B's shop onto A.
const steal = await rest(`shops?id=eq.${a.shopId}`, { token: B.token, method: "PATCH", prefer: "return=representation", body: { owner_id: B.userId } });
record("B re-assigns shop A to itself", Array.isArray(steal.data) && steal.data.length === 0, { status: steal.status, rows: steal.data?.length });
const give = await rest(`shops?id=eq.${b.shopId}`, { token: B.token, method: "PATCH", prefer: "return=representation", body: { owner_id: A.userId } });
record("B hands its own shop to A's account", give.status >= 400, { status: give.status, msg: give.data?.message });

// 2. Read or change A's user profile row.
const prof = await rest(`users?id=eq.${A.userId}&select=*`, { token: B.token });
record("B reads A's profile (email, name)", prof.data?.length === 0, { rows: prof.data?.length });

// 3. A credit payment in shop A's name, or against A's customer from B's shop.
const pay = await rpc("record_payment", { p_shop_id: a.shopId, p_customer_id: aCust?.id, p_amount: 1, p_note: "probe", p_payment_id: randomUUID() }, B.token);
record("B records a payment in shop A", pay.status >= 400, { status: pay.status, msg: pay.data?.message });
const pay2 = await rpc("record_payment", { p_shop_id: b.shopId, p_customer_id: aCust?.id, p_amount: 1, p_note: "probe", p_payment_id: randomUUID() }, B.token);
record("B records a payment for A's customer from shop B", pay2.status >= 400, { status: pay2.status, msg: pay2.data?.message });

// 4. Direct row writes that point at another shop's product or customer.
const tx = await rest("transactions", { token: B.token, method: "POST", prefer: "return=representation",
  body: { shop_id: b.shopId, product_id: aProd.id, type: "sale", quantity: 1, buying_price: 0, selling_price: 0 } });
record("B saves a sale row in its own shop that names A's product (direct write)", tx.status >= 400,
  { status: tx.status, msg: tx.data?.message ?? tx.data?.[0]?.id });
const aQty = (await rest(`products?id=eq.${aProd.id}&select=quantity`, { token: A.token })).data[0].quantity;
record("…and shop A's stock is unchanged", Number(aQty) === Number(aProd.quantity), { before: aProd.quantity, after: aQty });
const led = await rest("customer_ledger", { token: B.token, method: "POST", prefer: "return=representation",
  body: { shop_id: b.shopId, customer_id: aCust?.id, entry_type: "payment", amount: 5 } });
record("B saves a ledger row in its own shop that names A's customer (direct write)", led.status >= 400,
  { status: led.status, msg: led.data?.message ?? led.data?.[0]?.id });
const aLedger = (await rest(`customer_ledger?customer_id=eq.${aCust?.id}&select=id`, { token: A.token })).data.length;
const aLedgerAll = (await rest(`customer_ledger?customer_id=eq.${aCust?.id}&select=id,shop_id`, { token: A.token })).data;
record("…and A cannot see that row in its own ledger", aLedgerAll.every((r) => r.shop_id === a.shopId), { rowsVisibleToA: aLedger });

// 5. An owner rewriting its OWN sale history directly (the known open item).
// A real sale through checkout first, then a direct edit of its saved price.
const sale = await rpc("record_sale_cart", { p_shop_id: b.shopId, p_items: [{ product_id: bProd.id, quantity: 1 }], p_source: "manual" }, B.token);
const own = Array.isArray(sale.data) ? sale.data[0] : null;
const edit = own
  ? await rest(`transactions?id=eq.${own.id}`, { token: B.token, method: "PATCH", prefer: "return=representation", body: { selling_price: 999 } })
  : { status: sale.status, data: [] };
record("Owner edits its own past sale directly (succeeds today: open item M2)", edit.data?.length === 1,
  { saleStatus: sale.status, editStatus: edit.status, priceAfter: edit.data?.[0]?.selling_price });

// 6. Negative or zero quantities through the sale function.
const neg = await rpc("record_sale_cart", { p_shop_id: b.shopId, p_items: [{ product_id: bProd?.id, quantity: -5 }], p_source: "manual" }, B.token);
record("A sale of -5 units through the checkout function", neg.status >= 400, { status: neg.status, msg: neg.data?.message });

// 7. AI functions: a token that is not a JWT, and a forged unsigned one.
const fake = Buffer.from(JSON.stringify({ role: "authenticated", sub: randomUUID() })).toString("base64url");
for (const [label, tok] of [["junk token", "not-a-token"], ["forged unsigned token", `eyJhbGciOiJub25lIn0.${fake}.`]]) {
  const r = await fn("parse-sale", { ping: true }, tok);
  record(`parse-sale with a ${label}`, r.status === 401, { status: r.status });
}

writeFileSync(new URL("./results/extra_probe.json", import.meta.url), JSON.stringify(out, null, 2));
