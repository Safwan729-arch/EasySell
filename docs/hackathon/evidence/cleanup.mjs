// Deletes the test shops created by setup.mjs (their products, sales,
// customers and ledger rows go with them). The real demo shop is never
// touched: each test account can only delete its own shop.
//
//   EV_CREDS=<creds.json> node cleanup.mjs
import { loadCreds, rest, signIn } from "./lib.mjs";

const creds = loadCreds();
for (const who of ["a", "b"]) {
  const { email, password, shopId } = creds[who] ?? {};
  if (!shopId) continue;
  const { token } = await signIn(email, password);
  const r = await rest(`shops?id=eq.${shopId}`, { token, method: "DELETE", prefer: "return=representation" });
  console.log(`test shop ${who}: ${r.status === 200 && r.data.length === 1 ? "deleted" : `not deleted (${r.status})`}`);
}
console.log("The two test logins remain; remove them under Authentication > Users if wanted.");
