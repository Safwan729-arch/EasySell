// Live check of Supabase Auth's per-connection sign-up rate limit
// (Authentication > Rate Limits > "sign ups and sign ins"). Auth uses a token
// bucket: a burst of up to 30 is always allowed, and the setting is the REFILL
// rate. So this script first empties the bucket, then sends one sign-up every
// 5 s for 120 s and counts how many get through. At 15 per 5 minutes that is
// about 6 (one every 20 s); at the default 30, about 12.
//
// Every sign-up uses a 3-character password, which Auth refuses (422), so no
// account is ever created. Afterwards this connection cannot sign up for a few
// minutes, so run it last.
import { writeFileSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { ANON, URL_, stamp } from "../evidence/lib.mjs";

const attempt = async () => (await fetch(`${URL_}/auth/v1/signup`, {
  method: "POST",
  headers: { apikey: ANON, "Content-Type": "application/json" },
  body: JSON.stringify({ email: `nobody-${randomBytes(4).toString("hex")}@easysell-evidence.dev`, password: "abc" }),
})).status;

const out = { ranAt: stamp(), checks: [] };
const record = (name, pass, detail) => { out.checks.push({ name, pass, detail }); console.log(pass ? "PASS" : "FAIL", name, JSON.stringify(detail)); };

const first = await attempt();
record("a sign-up with a too-short password is refused, so no account is made", first === 422 || first === 429, { status: first });
if (first === 200) process.exit(1);

let burst = first === 429 ? 0 : 1;
let s = first;
while (s !== 429 && burst < 120) { s = await attempt(); if (s !== 429) burst++; }
record("a burst of sign-ups from one connection is cut off", s === 429, { passedBeforeFirst429: burst });

const t0 = Date.now();
const through = [];
while (Date.now() - t0 < 120000) {
  await new Promise((r) => setTimeout(r, 5000));
  const st = await attempt();
  if (st === 200) { record("no account created", false, { status: st }); break; }
  if (st !== 429) through.push(Math.round((Date.now() - t0) / 1000));
}
const per5min = Math.round((through.length / 120) * 300);
record("after the burst, sign-ups refill at about 15 per 5 minutes", through.length >= 4 && through.length <= 8,
  { gotThroughAtSeconds: through, countIn120s: through.length, aboutPer5Minutes: per5min });

writeFileSync(new URL("./results/signup_rate_probe.json", import.meta.url), JSON.stringify(out, null, 2));
