// Money safety on the LIVE database, in a throwaway test shop.
//
//   EV_CREDS=<creds.json> node money_safety.mjs
//
// Every check calls the same database functions the app calls, as a signed-in
// shop owner, and then reads the rows back to prove what was (and was not)
// saved.
import { randomUUID } from "node:crypto";
import { loadCreds, rest, rpc, save, signIn, stamp } from "./lib.mjs";

const { a } = loadCreds();
const { token } = await signIn(a.email, a.password);
const shop = a.shopId;
const results = [];
const record = (name, pass, detail) => {
  results.push({ name, pass, ...detail });
  console.log(`${pass ? "PASS" : "FAIL"}  ${name}  ${JSON.stringify(detail)}`);
};

async function product(name, quantity, buy, sell) {
  const r = await rest("products", {
    token, method: "POST", prefer: "return=representation",
    body: { shop_id: shop, name, quantity, buying_price: buy, selling_price: sell },
  });
  if (r.status !== 201) throw new Error(`product insert failed ${JSON.stringify(r)}`);
  return r.data[0].id;
}
const stockOf = async (id) => Number((await rest(`products?id=eq.${id}&select=quantity`, { token })).data[0].quantity);
const setStock = (id, q) => rest(`products?id=eq.${id}`, { token, method: "PATCH", body: { quantity: q } });
const sale = (items, extra = {}) =>
  rpc("record_sale_cart", { p_shop_id: shop, p_items: items, p_source: "manual", ...extra }, token);
const salesOf = async (id) => (await rest(`transactions?product_id=eq.${id}&type=eq.sale&select=id,sale_group_id,quantity,selling_price`, { token })).data;

// 1. Two sales race for the last unit, 10 times over.
const cola = await product("Evidence Cola 500ml", 1, 30, 40);
const rounds = [];
for (let round = 1; round <= 10; round++) {
  await setStock(cola, 1);
  const [x, y] = await Promise.all([
    sale([{ product_id: cola, quantity: 1 }], { p_sale_group_id: randomUUID() }),
    sale([{ product_id: cola, quantity: 1 }], { p_sale_group_id: randomUUID() }),
  ]);
  const ok = [x, y].filter((r) => r.status === 200).length;
  const refused = [x, y].filter((r) => r.status !== 200).map((r) => r.data?.message);
  rounds.push({ round, succeeded: ok, refused, stockAfter: await stockOf(cola) });
}
const colaSales = await salesOf(cola);
record("Two sales race for the last unit (10 rounds)",
  rounds.every((r) => r.succeeded === 1 && r.stockAfter === 0) && colaSales.length === 10,
  { roundsWithExactlyOneSale: rounds.filter((r) => r.succeeded === 1).length, lowestStock: Math.min(...rounds.map((r) => r.stockAfter)), saleRowsSaved: colaSales.length, refusalMessage: rounds[0].refused[0] });

// 2. A retried sale (same id, as after a lost reply) is saved once.
await setStock(cola, 5);
const gid = randomUUID();
const first = await sale([{ product_id: cola, quantity: 2 }], { p_sale_group_id: gid });
const retry = await sale([{ product_id: cola, quantity: 2 }], { p_sale_group_id: gid });
const rows = (await salesOf(cola)).filter((r) => r.sale_group_id === gid);
record("A retried sale is saved once",
  first.status === 200 && retry.status === 200 && rows.length === 1 && (await stockOf(cola)) === 3,
  { firstCall: first.status, retryCall: retry.status, rowsForThatSale: rows.length, stockAfter: await stockOf(cola), stockBefore: 5 });

// 3. A cart is all or nothing: one bad line saves no line.
const chips = await product("Evidence Chips", 10, 8, 10);
const before = { cola: await stockOf(cola), chips: await stockOf(chips) };
const cart = await sale([{ product_id: chips, quantity: 2 }, { product_id: cola, quantity: 99 }], { p_sale_group_id: randomUUID() });
const after = { cola: await stockOf(cola), chips: await stockOf(chips) };
record("A cart is all or nothing",
  cart.status !== 200 && after.chips === before.chips && (await salesOf(chips)).length === 0,
  { callStatus: cart.status, message: cart.data?.message, chipsStockBefore: before.chips, chipsStockAfter: after.chips, chipsSaleRows: (await salesOf(chips)).length });

// 4. Stock can never be set below zero, even by a direct write.
const neg = await setStock(chips, -1);
record("Stock can never go below zero",
  neg.status >= 400 && (await stockOf(chips)) === 10,
  { directWriteStatus: neg.status, message: neg.data?.message, stockAfter: await stockOf(chips) });

// 5. A sale keeps the price it was sold at.
await rest(`products?id=eq.${cola}`, { token, method: "PATCH", body: { selling_price: 99 } });
const frozen = (await salesOf(cola)).find((r) => r.sale_group_id === gid);
record("A price change never rewrites past sales",
  Number(frozen.selling_price) === 40,
  { priceWhenSold: Number(frozen.selling_price), priceNow: 99 });

// 6. A retried credit payment is saved once.
const cust = await rest("customers", { token, method: "POST", prefer: "return=representation", body: { shop_id: shop, name: "Evidence Customer", phone: "01000000000" } });
const customerId = cust.data[0].id;
await setStock(chips, 10);
const credit = await sale([{ product_id: chips, quantity: 4 }], { p_sale_group_id: randomUUID(), p_customer_id: customerId });
const pid = randomUUID();
const pay = () => rpc("record_payment", { p_shop_id: shop, p_customer_id: customerId, p_amount: 25, p_note: "evidence", p_payment_id: pid }, token);
const p1 = await pay();
const p2 = await pay();
const ledger = (await rest(`customer_ledger?customer_id=eq.${customerId}&select=entry_type,amount,id`, { token })).data;
const owed = ledger.reduce((s, r) => s + (r.entry_type === "credit_sale" ? 1 : -1) * Number(r.amount), 0);
record("A retried credit payment is saved once",
  credit.status === 200 && p1.status === 200 && p2.status === 200 && ledger.filter((r) => r.entry_type === "payment").length === 1 && owed === 15,
  { creditSale: 40, paymentCalls: [p1.status, p2.status], paymentRows: ledger.filter((r) => r.entry_type === "payment").length, stillOwed: owed });

// 7. A payment larger than the debt is refused.
const over = await rpc("record_payment", { p_shop_id: shop, p_customer_id: customerId, p_amount: 1000, p_note: "evidence", p_payment_id: randomUUID() }, token);
record("A payment larger than the debt is refused",
  over.status >= 400,
  { callStatus: over.status, message: over.data?.message });

const out = { ranAt: stamp(), passed: results.filter((r) => r.pass).length, total: results.length, results, raceRounds: rounds };
save("money_safety.json", out);
console.log(`${out.passed}/${out.total} passed`);
