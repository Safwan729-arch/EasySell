// Lists every JWT found inside an unpacked APK and prints only its role claim
// (never the token itself). Usage: node apk_tokens.mjs <unpacked apk dir>
import fs from "node:fs";
import path from "node:path";

const seen = new Map();
(function walk(d) {
  for (const f of fs.readdirSync(d)) {
    const q = path.join(d, f);
    if (fs.statSync(q).isDirectory()) { walk(q); continue; }
    const s = fs.readFileSync(q).toString("latin1");
    for (const m of s.matchAll(/eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g)) {
      if (seen.has(m[0])) continue;
      const c = JSON.parse(Buffer.from(m[0].split(".")[1], "base64url"));
      seen.set(m[0], `${path.relative(process.argv[2], q).split(path.sep).join("/")} role=${c.role}`);
    }
  }
})(process.argv[2]);
for (const v of seen.values()) console.log(v);
console.log("tokens found:", seen.size);
