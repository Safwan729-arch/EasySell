// Live check of migration 0024: a brand-new account gets only 10 AI calls on
// its first day. Signs up one throwaway account (its login stays in Auth, like
// the evidence accounts a and b), fills its count through claim_ai_call (no
// Gemini spend), then expects 429 from parse-sale. Uses 10 of the app's 500.
import { writeFileSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { ANON, URL_, rpc, signIn, fn, stamp } from "../evidence/lib.mjs";

const out = { ranAt: stamp(), checks: [] };
const record = (name, pass, detail) => { out.checks.push({ name, pass, detail }); console.log(pass ? "PASS" : "FAIL", name, JSON.stringify(detail)); };

const email = `evidence-new-${randomBytes(3).toString("hex")}@easysell-evidence.dev`;
const password = randomBytes(18).toString("base64url");
const up = await fetch(`${URL_}/auth/v1/signup`, {
  method: "POST",
  headers: { apikey: ANON, "Content-Type": "application/json" },
  body: JSON.stringify({ email, password }),
});
record("sign up a brand-new account", up.ok, { status: up.status });

if (up.ok) {
  const N = await signIn(email, password);
  let first, last, k = 0;
  do {
    last = await rpc("claim_ai_call", {}, N.token);
    first ??= last;
    k++;
  } while (last.status === 200 && last.data?.allowed === true && k < 60);
  record("a brand-new account is marked new, with a limit of 10", first.data?.new_account === true && first.data?.limit === 10, { first: first.data });
  record("a brand-new account is refused after 10 calls", k === 11 && last.data?.allowed === false && last.data?.reason === "user",
    { callsUntilRefused: k, reply: last.data });
  const ai = await fn("parse-sale", { transcript: "2 pepsi", candidates: [{ id: "x", name: "Pepsi" }] }, N.token);
  record("…and its AI request then answers 429, before Gemini", ai.status === 429, { status: ai.status, body: ai.data, ms: ai.ms });
}

writeFileSync(new URL("./results/new_account_probe.json", import.meta.url), JSON.stringify(out, null, 2));
