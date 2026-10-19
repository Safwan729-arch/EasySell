// Proof that the backend, the database changes and the AI functions are live.
//
//   EV_CREDS=<creds.json> node deployment_check.mjs
//
// Each database check calls a function with the parameters added by a specific
// migration: if that migration were not applied, the live database would
// answer "function not found" (404). The AI checks use inputs that are
// rejected before Gemini is called, so they cost nothing.
import { ANON, URL_, fn, loadCreds, rpc, save, signIn, stamp } from "./lib.mjs";

const { a } = loadCreds();
const { token } = await signIn(a.email, a.password);
const today = new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const results = [];
const record = (area, name, pass, detail) => {
  results.push({ area, name, pass, ...detail });
  console.log(`${pass ? "PASS" : "FAIL"}  ${name}  ${JSON.stringify(detail)}`);
};

const settings = await fetch(`${URL_}/auth/v1/settings`, { headers: { apikey: ANON } });
const s = await settings.json();
record("auth", "Sign-in service is up, email sign-in on, guest sign-in off",
  settings.ok && s.external?.email === true && s.external?.anonymous_users !== true,
  { status: settings.status, email: s.external?.email, guest: s.external?.anonymous_users ?? false });

const dbChecks = [
  ["0020", "get_dashboard_summary", { p_shop_id: a.shopId, p_period: "month", p_utc_offset_minutes: 360 }],
  ["0020", "get_sales_series", { p_shop_id: a.shopId, p_bucket: "day", p_points: 7, p_utc_offset_minutes: 360 }],
  ["0019", "get_finance_health", { p_shop_id: a.shopId, p_today: today, p_utc_offset_minutes: 360 }],
  ["0017", "get_restock_speeds", { p_shop_id: a.shopId, p_today: today, p_utc_offset_minutes: 360 }],
];
for (const [migration, name, args] of dbChecks) {
  const r = await rpc(name, args, token);
  record("database", `Migration ${migration}: ${name} answers with its newest parameters`, r.status === 200,
    { status: r.status });
}

const ping = await fn("parse-sale", { ping: true, candidates: [] }, token);
record("ai", "parse-sale is deployed and answers a signed-in user", ping.status === 200 && ping.data?.warm === true,
  { status: ping.status, ms: ping.ms });
const scan = await fn("recognize-product", { candidates: [] }, token);
record("ai", "recognize-product is deployed and checks its input", scan.status === 400,
  { status: scan.status, message: scan.data?.error });
const tips = await fn("money-tips", { lang: "toString", facts: {} }, token);
record("ai", "money-tips is deployed with the 19 Oct language fix", tips.status === 400 && /lang must be/.test(tips.data?.error ?? ""),
  { status: tips.status, message: tips.data?.error });

const out = { ranAt: stamp(), passed: results.filter((r) => r.pass).length, total: results.length, results };
save("deployment_check.json", out);
console.log(`${out.passed}/${out.total} passed`);
