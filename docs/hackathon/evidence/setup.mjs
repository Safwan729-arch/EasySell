// Creates (or reuses) two throwaway test accounts, each with its own test shop,
// on the live project. The team's real demo shop is never touched.
//
//   EV_CREDS=<file outside the repo> node setup.mjs
//
// The file gets the accounts' emails and passwords and is never committed.
import { existsSync, writeFileSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { ANON, URL_, CREDS_PATH, rest, signIn } from "./lib.mjs";

if (!CREDS_PATH) throw new Error("set EV_CREDS");

async function signUp(email, password) {
  const r = await fetch(`${URL_}/auth/v1/signup`, {
    method: "POST",
    headers: { apikey: ANON, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const b = await r.json();
  if (!r.ok) throw new Error(`sign-up failed for ${email}: ${r.status} ${JSON.stringify(b)}`);
}

const creds = existsSync(CREDS_PATH)
  ? JSON.parse((await import("node:fs")).readFileSync(CREDS_PATH, "utf8"))
  : {};

for (const who of ["a", "b"]) {
  if (!creds[who]) {
    const email = `evidence-${who}-${randomBytes(3).toString("hex")}@easysell-evidence.dev`;
    const password = randomBytes(18).toString("base64url");
    await signUp(email, password);
    creds[who] = { email, password };
    console.log(`signed up test account ${who}`);
  }
  const { token, userId } = await signIn(creds[who].email, creds[who].password);
  creds[who].userId = userId;
  const mine = await rest(`shops?owner_id=eq.${userId}&select=id`, { token });
  if (mine.data.length) {
    creds[who].shopId = mine.data[0].id;
  } else {
    const made = await rest("shops", {
      token,
      method: "POST",
      prefer: "return=representation",
      body: { owner_id: userId, name: `Evidence test shop ${who.toUpperCase()}`, currency: "BDT" },
    });
    if (made.status !== 201) throw new Error(`shop create failed: ${JSON.stringify(made)}`);
    creds[who].shopId = made.data[0].id;
    console.log(`created test shop ${who}`);
  }
}

writeFileSync(CREDS_PATH, JSON.stringify(creds, null, 2));
console.log("ready: accounts a and b, each with its own shop");
