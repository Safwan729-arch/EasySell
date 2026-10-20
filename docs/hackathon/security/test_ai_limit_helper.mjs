// Checks the Edge Functions' daily-limit helper (ai_limit.ts, finding M1)
// against a fake database, on Node 23.6+ (which runs TypeScript directly).
// Usage: node test_ai_limit_helper.mjs <supabase/functions dir>
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const dir = process.argv[2];
let failed = 0;
const check = (name, ok, extra = "") => {
  console.log(`${ok ? "PASS" : "FAIL"} ${name} ${extra}`);
  if (!ok) failed++;
};

const copies = ["parse-sale", "recognize-product", "money-tips"].map((f) => fs.readFileSync(path.join(dir, f, "ai_limit.ts"), "utf8"));
check("the three copies of ai_limit.ts are identical", copies.every((c) => c === copies[0]));
for (const f of ["parse-sale", "recognize-product", "money-tips"]) {
  const src = fs.readFileSync(path.join(dir, f, "index.ts"), "utf8");
  const claimAt = src.indexOf("await claimAiCall(req)");
  const geminiAt = src.indexOf("generativelanguage.googleapis.com");
  const serveAt = src.indexOf("Deno.serve");
  const callAt = src.indexOf(f === "parse-sale" ? "await parseSale(" : f === "money-tips" ? "await tips(" : "await recognize(", serveAt);
  check(`${f} checks the limit before its Gemini call`, claimAt > serveAt && claimAt < callAt && geminiAt > 0, `claim=${claimAt} call=${callAt}`);
  if (f === "parse-sale") check("parse-sale answers a ping before the limit check", src.indexOf("ping === true") < claimAt);
}

const env = { SUPABASE_URL: "https://proj.supabase.co", SUPABASE_ANON_KEY: "anon-key" };
globalThis.Deno = { env: { get: (k) => env[k] } };
const { claimAiCall } = await import(pathToFileURL(path.join(dir, "parse-sale", "ai_limit.ts")).href);

let seen;
const fakeDb = (reply) => { globalThis.fetch = async (url, init) => { seen = { url, init }; return reply(); }; };
const req = () => new Request("https://x/functions/v1/parse-sale", { method: "POST", headers: { Authorization: "Bearer user-token" } });
const ok = (body) => new Response(JSON.stringify(body), { status: 200 });

fakeDb(() => ok({ allowed: true, used: 3, limit: 50 }));
check("under the limit: the call goes ahead", (await claimAiCall(req())) === null);
check("…it asks claim_ai_call with the user's own token",
  seen.url === "https://proj.supabase.co/rest/v1/rpc/claim_ai_call" && seen.init.headers.Authorization === "Bearer user-token" && seen.init.headers.apikey === "anon-key");

fakeDb(() => ok({ allowed: false, reason: "user", limit: 50 }));
let r = await claimAiCall(req());
let b = await r.json();
check("user limit reached: 429 with a plain message", r.status === 429 && b.limit_scope === "user" && b.limit === 50 && /today's AI limit/.test(b.error), JSON.stringify(b));

fakeDb(() => ok({ allowed: false, reason: "app", limit: 500 }));
r = await claimAiCall(req());
b = await r.json();
check("app cap reached: 429, scope app", r.status === 429 && b.limit_scope === "app", JSON.stringify(b));

fakeDb(() => new Response("boom", { status: 500 }));
check("database error: refused with 503 (fails closed)", (await claimAiCall(req())).status === 503);
fakeDb(() => { throw new Error("network down"); });
check("network error: refused with 503 (fails closed)", (await claimAiCall(req())).status === 503);
fakeDb(() => ok({ something: "odd" }));
check("an odd reply is treated as a refusal", (await claimAiCall(req())).status === 429);

console.log(failed ? `${failed} FAILED` : "all passed");
process.exit(failed ? 1 : 0);
