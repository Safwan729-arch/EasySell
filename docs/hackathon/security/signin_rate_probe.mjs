// Live check of Supabase Auth's per-connection rate limit on sign-ups and
// sign-ins (Authentication > Rate limits). Sends failed sign-ins (a made-up
// email, wrong password) until Auth answers 429, so no account is created.
//
// Run it LAST: afterwards this connection cannot sign in or sign up for up to
// 5 minutes.
import { writeFileSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { ANON, URL_, stamp } from "../evidence/lib.mjs";

const MAX = 80;
const statuses = [];
let limitedAt = null;
for (let i = 1; i <= MAX; i++) {
  const r = await fetch(`${URL_}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON, "Content-Type": "application/json" },
    body: JSON.stringify({ email: `nobody-${randomBytes(4).toString("hex")}@easysell-evidence.dev`, password: "wrong-password" }),
  });
  statuses.push(r.status);
  if (r.status === 429) { limitedAt = i; break; }
}
const pass = limitedAt !== null;
const out = {
  ranAt: stamp(),
  checks: [{
    name: "Repeated sign-in attempts from one connection are rate limited",
    pass,
    detail: { attemptsBeforeLimit: pass ? limitedAt - 1 : MAX, limitedOnAttempt: limitedAt, otherStatuses: [...new Set(statuses.filter((s) => s !== 429))] },
  }],
};
console.log(pass ? "PASS" : "FAIL", out.checks[0].name, JSON.stringify(out.checks[0].detail));
writeFileSync(new URL("./results/signin_rate_probe.json", import.meta.url), JSON.stringify(out, null, 2));
