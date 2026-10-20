// Builds the full database (every migration) on PGlite and checks migration
// 0024: accounts in their first 24 hours get fewer AI calls.
// Usage: node test_0024_pglite.mjs <migrations dir>
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
const claim = async (user) => {
  const r = await tryAsUser(db, user, "select claim_ai_call() r", []);
  return r.error ? { error: r.error } : r.rows[0].r;
};
const account = async (age) => {
  const id = randomUUID();
  await db.query(`insert into auth.users (id, email, created_at) values ($1, $2, now() - $3::interval)`, [id, `${id}@t.dev`, age]);
  return id;
};
const callsUntilRefused = async (user, max = 60) => {
  let n = 0, r;
  do { r = await claim(user); n++; } while (r.allowed === true && n < max);
  return { allowed: n - 1, last: r };
};

const lim = (await db.query("select per_user_daily, new_account_daily, new_account_hours from ai_limits")).rows[0];
check("defaults: 50 a day, 10 a day for accounts under 24 hours old",
  lim.per_user_daily === 50 && lim.new_account_daily === 10 && lim.new_account_hours === 24, JSON.stringify(lim));

const fresh = await account("5 minutes");
const first = await claim(fresh);
check("a new account is marked as new, with a limit of 10", first.allowed === true && first.new_account === true && first.limit === 10, JSON.stringify(first));
const f = await callsUntilRefused(fresh);
check("a new account gets 10 calls in all, then is refused", f.allowed === 9 && f.last.reason === "user" && f.last.limit === 10,
  `allowed after the first=${f.allowed} ${JSON.stringify(f.last)}`);

const day = await account("23 hours");
check("an account 23 hours old is still new", (await claim(day)).new_account === true);

const old = await account("25 hours");
const o = await claim(old);
check("an account 25 hours old gets the full 50", o.allowed === true && o.new_account === false && o.limit === 50, JSON.stringify(o));
const oRun = await callsUntilRefused(old);
check("…and is refused only after 50", oRun.allowed === 49 && oRun.last.limit === 50, `allowed after the first=${oRun.allowed}`);

// The same account, once it is older than 24 hours, gets the rest of its 50.
await db.query("update auth.users set created_at = now() - interval '2 days' where id = $1", [fresh]);
const grown = await claim(fresh);
check("once a day old, the same account can go on to 50", grown.allowed === true && grown.used === 11 && grown.limit === 50, JSON.stringify(grown));

// A user cannot make their account look older.
const fake = await tryAsUser(db, fresh, "update auth.users set created_at = now() - interval '9 days' where id = $1", [fresh]);
check("a user cannot change their account's age", !!fake.error, fake.error ?? "");

// The settings still work from the SQL editor.
await db.query("update ai_limits set new_account_daily = 2");
const two = await account("1 minute");
check("a changed new-account limit applies at once (2 calls, then refused)", (await callsUntilRefused(two)).allowed === 2);
await db.query("update ai_limits set new_account_daily = 50");
check("new_account_daily = per_user_daily turns the first-day limit off", (await claim(await account("1 minute"))).limit === 50);
await db.query("update ai_limits set new_account_daily = 99");
check("a first-day limit above the daily limit never raises it", (await claim(await account("1 minute"))).limit === 50);
await db.query("update ai_limits set new_account_daily = 10");

// The app-wide cap still comes first for everyone.
await db.query("update ai_usage_total set calls = 500 where day = (now() at time zone 'UTC')::date");
const capped = await claim(await account("3 days"));
check("the app-wide cap still refuses everyone", capped.allowed === false && capped.reason === "app", JSON.stringify(capped));
await db.query("update ai_usage_total set calls = 0");

// Still hidden, still only for signed-in users.
const read = await tryAsUser(db, fresh, "select * from ai_limits", []);
check("a user still cannot read the limits", !!read.error && /permission denied/.test(read.error), read.error ?? "");
const def = (await db.query(`select prosecdef, proconfig from pg_proc where proname = 'claim_ai_call'`)).rows[0];
check("claim_ai_call is still security definer with search_path pinned", def.prosecdef === true && (def.proconfig ?? []).some((c) => c.startsWith("search_path=")));
const anonRole = await db.transaction(async (tx) => {
  await tx.exec("set local role anon");
  return tx.query("select claim_ai_call()").then(() => null, (e) => e.message);
});
check("the public (anon) role still cannot run it", !!anonRole && /permission denied/.test(anonRole), anonRole ?? "");

// Re-run keeps changed settings.
await db.query("update ai_limits set new_account_daily = 7");
await db.exec(fs.readFileSync(path.join(dir, "0024_new_account_ai_limit.sql"), "utf8"));
check("re-running 0024 keeps a changed setting", (await db.query("select new_account_daily from ai_limits")).rows[0].new_account_daily === 7);

console.log(failed ? `${failed} FAILED` : "all passed");
process.exit(failed ? 1 : 0);
