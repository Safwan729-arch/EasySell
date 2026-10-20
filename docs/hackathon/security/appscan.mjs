// Scans lib/ for logging, plain-HTTP URLs, screen protection, local storage
// and password rules. Usage: node appscan.mjs <repo root>
import fs from "node:fs";
import path from "node:path";

const root = path.join(process.argv[2], "lib");
const checks = {
  print: /\bprint\(/,
  debugPrint: /debugPrint\(/,
  httpUrl: /http:\/\//,
  devLog: /developer\.log|\blog\(/,
  secureScreen: /FLAG_SECURE|secure_screen|flutter_secure_storage|FlutterSecureStorage/,
  prefs: /SharedPreferences\.getInstance/,
  password: /password/i,
  authStorage: /localStorage|authOptions|FlutterAuthClientOptions/,
};
const out = Object.fromEntries(Object.keys(checks).map((k) => [k, []]));
(function walk(d) {
  for (const f of fs.readdirSync(d)) {
    const q = path.join(d, f);
    if (fs.statSync(q).isDirectory()) { walk(q); continue; }
    if (!q.endsWith(".dart") || /\.(g|freezed)\.dart$/.test(q) || q.includes(`${path.sep}l10n${path.sep}`)) continue;
    fs.readFileSync(q, "utf8").split("\n").forEach((l, i) => {
      for (const [k, re] of Object.entries(checks)) {
        if (re.test(l)) out[k].push(`${path.relative(process.argv[2], q).split(path.sep).join("/")}:${i + 1}: ${l.trim().slice(0, 120)}`);
      }
    });
  }
})(root);
for (const [k, v] of Object.entries(out)) {
  console.log(`## ${k} ${v.length}`);
  v.slice(0, k === "password" ? 25 : 10).forEach((x) => console.log("  " + x));
}
