// Builds the full database (every migration) on PGlite and checks the daily
// AI limit from migration 0023 (finding M1).
// Usage: node test_0023_pglite.mjs <migrations dir>
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
const claim = async (user, claims) => {
  const r = await tryAsUser(db, user, "select claim_ai_call() r", [], claims);
  return r.error ? { error: r.error } : r.rows[0].r;
};
const newUser = async () => {
  const id = randomUUID();
  await db.query("insert into auth.users (id, email) values ($1, $2)", [id, `${id}@t.dev`]);
  return id;
};

const lim = (await db.query("select per_user_daily, app_daily from ai_limits")).rows;
check("default limits are 50 per user and 500 for the app", lim.length === 1 && lim[0].per_user_daily === 50 && lim[0].app_daily === 500,
  JSON.stringify(lim));

// --- Per-user limit ---
const u = await newUser();
let lastOk = null;
for (let i = 1; i <= 50; i++) lastOk = await claim(u);
check("calls 1 to 50 are allowed", lastOk.allowed === true && lastOk.used === 50, JSON.stringify(lastOk));
const over = await claim(u);
check("call 51 is refused (user limit)", over.allowed === false && over.reason === "user", JSON.stringify(over));
const still = (await db.query("select calls from ai_usage where user_id = $1", [u])).rows[0].calls;
check("…and a refused call is not counted", still === 50, `calls=${still}`);

const v = await newUser();
const other = await claim(v);
check("another user still has their own 50", other.allowed === true && other.used === 1, JSON.stringify(other));

// Yesterday's count does not carry over.
await db.query("update ai_usage set day = day - 1 where user_id = $1", [u]);
const nextDay = await claim(u);
check("a new day starts again from 1", nextDay.allowed === true && nextDay.used === 1, JSON.stringify(nextDay));

// --- Whole-app cap ---
await db.query("update ai_usage_total set calls = 500 where day = (now() at time zone 'UTC')::date");
const w = await newUser();
const capped = await claim(w);
check("once the app has 500 calls today, everyone is refused", capped.allowed === false && capped.reason === "app", JSON.stringify(capped));
const wCalls = (await db.query("select coalesce(sum(calls),0)::int n from ai_usage where user_id = $1", [w])).rows[0].n;
check("…and that refused call is not counted against the user", wCalls === 0, `calls=${wCalls}`);
await db.query("update ai_usage_total set calls = 10 where day = (now() at time zone 'UTC')::date");

// Changing the limit from the SQL editor works at once.
await db.query("update ai_limits set per_user_daily = 2");
const x = await newUser();
await claim(x); await claim(x);
check("a lowered limit applies at once", (await claim(x)).allowed === false);
await db.query("update ai_limits set per_user_daily = 0");
check("a limit of 0 turns the AI off", (await claim(await newUser())).allowed === false);
await db.query("update ai_limits set per_user_daily = 50");

// --- Who may call it ---
const anon = await claim(await newUser(), { is_anonymous: true });
check("a guest (anonymous) session is refused", !!anon.error && /Sign in/.test(anon.error), anon.error ?? JSON.stringify(anon));
const noUser = await tryAsUser(db, "", "select claim_ai_call()", []).catch((e) => ({ error: e.message }));
check("no signed-in user is refused", !!noUser.error, noUser.error ?? "");
const anonRole = await db.transaction(async (tx) => {
  await tx.exec("set local role anon");
  return tx.query("select claim_ai_call()").then(() => null, (e) => e.message);
});
check("the public (anon) role cannot run it at all", !!anonRole && /permission denied/.test(anonRole), anonRole ?? "");

// The counters and limits are hidden from users.
for (const t of ["ai_usage", "ai_usage_total", "ai_limits"]) {
  const r = await tryAsUser(db, u, `select * from ${t}`, []);
  check(`a user cannot read ${t}`, !!r.error && /permission denied/.test(r.error), r.error ?? `rows=${r.rows?.length}`);
}
const reset = await tryAsUser(db, u, "update ai_usage set calls = 0 where user_id = $1", [u]);
check("a user cannot reset their own count", !!reset.error, reset.error ?? "");
const raise = await tryAsUser(db, u, "update ai_limits set per_user_daily = 100000", []);
check("a user cannot raise the limit", !!raise.error, raise.error ?? "");

// The function is security definer with a pinned search_path.
const def = (await db.query(`select prosecdef, proconfig from pg_proc where proname = 'claim_ai_call'`)).rows[0];
check("claim_ai_call is security definer with search_path pinned", def.prosecdef === true && (def.proconfig ?? []).some((c) => c.startsWith("search_path=")),
  JSON.stringify(def));

// Deleting a user removes their counts.
const z = await newUser();
await claim(z);
await db.query("delete from auth.users where id = $1", [z]);
check("deleting an account removes its counts", (await db.query("select count(*)::int n from ai_usage where user_id = $1", [z])).rows[0].n === 0);

// --- Re-run ---
await db.query("update ai_limits set per_user_daily = 77");
await db.exec(fs.readFileSync(path.join(dir, "0023_ai_daily_limit.sql"), "utf8"));
const after = (await db.query("select per_user_daily from ai_limits")).rows;
check("re-running 0023 keeps a changed limit and adds no rows", after.length === 1 && after[0].per_user_daily === 77, JSON.stringify(after));

console.log(failed ? `${failed} FAILED` : "all passed");
process.exit(failed ? 1 : 0);
