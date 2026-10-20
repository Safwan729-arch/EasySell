// Live check of the daily AI limit (migration 0023 + redeployed AI functions,
// finding M1). Uses test account B only, after setup.mjs. It fills B's daily
// count through claim_ai_call directly, so it spends no Gemini quota; the one
// AI request at the end must then be refused before Gemini is called.
// Uses up B's 50 calls for today (UTC) and 50 of the app's 500.
import { writeFileSync } from "node:fs";
import { loadCreds, rest, rpc, signIn, fn, stamp } from "../evidence/lib.mjs";

const { b } = loadCreds();
const B = await signIn(b.email, b.password);
const out = { ranAt: stamp(), checks: [] };
const record = (name, pass, detail) => { out.checks.push({ name, pass, detail }); console.log(pass ? "PASS" : "FAIL", name, JSON.stringify(detail)); };

// 1. Nobody can read or change the counters or the limits.
for (const t of ["ai_usage", "ai_usage_total", "ai_limits"]) {
  const r = await rest(`${t}?select=*`, { token: B.token });
  record(`a user reads ${t}: refused`, r.status >= 400, { status: r.status, msg: r.data?.message });
}
const raise = await rest("ai_limits?id=eq.true", { token: B.token, method: "PATCH", body: { per_user_daily: 100000 } });
record("a user raises the limit: refused", raise.status >= 400, { status: raise.status, msg: raise.data?.message });
const anon = await rpc("claim_ai_call", {}, undefined);
record("the public key alone runs claim_ai_call: refused", anon.status >= 400, { status: anon.status, msg: anon.data?.message });

// 2. Fill B's count for today.
let first, last, n = 0;
do {
  last = await rpc("claim_ai_call", {}, B.token);
  first ??= last;
  n++;
} while (last.status === 200 && last.data?.allowed === true && n < 60);
record("a signed-in user is counted", first.status === 200 && first.data?.allowed === true, { first: first.data });
record("the user is refused once today's limit is reached", last.data?.allowed === false && last.data?.reason === "user",
  { callsUntilRefused: n, reply: last.data });

// 3. A real AI request is now refused before Gemini is called.
const ai = await fn("parse-sale", { transcript: "2 pepsi", candidates: [{ id: "x", name: "Pepsi" }] }, B.token);
record("parse-sale over the limit answers 429", ai.status === 429, { status: ai.status, body: ai.data, ms: ai.ms });
const tips = await fn("money-tips", { lang: "en", facts: { warnings: [] } }, B.token);
record("money-tips over the limit answers 429", tips.status === 429, { status: tips.status, body: tips.data });

// 4. A ping still works (it is never counted).
const ping = await fn("parse-sale", { ping: true }, B.token);
record("a ping still answers 200", ping.status === 200, { status: ping.status });

writeFileSync(new URL("./results/ai_limit_probe.json", import.meta.url), JSON.stringify(out, null, 2));
