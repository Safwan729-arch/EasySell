// Checks every package pinned in pubspec.lock against the OSV vulnerability
// database (api.osv.dev). Sends only package names and versions.
// Usage: node osv.mjs <path to pubspec.lock>
import fs from "node:fs";

const lock = fs.readFileSync(process.argv[2], "utf8").split("\r\n").join("\n");
const pkgs = [];
for (const m of lock.matchAll(/^  ([a-z0-9_]+):\n(?:    .*\n)*?    version: "([^"]+)"/gm)) pkgs.push({ name: m[1], version: m[2] });
const direct = new Set([...lock.matchAll(/^  ([a-z0-9_]+):\n    dependency: "direct main"/gm)].map((m) => m[1]));

const r = await fetch("https://api.osv.dev/v1/querybatch", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ queries: pkgs.map((p) => ({ package: { name: p.name, ecosystem: "Pub" }, version: p.version })) }),
});
const body = await r.json(); if (!body.results) { console.log(r.status, JSON.stringify(body).slice(0, 300), pkgs.length); process.exit(1); } const { results } = body;
const hits = [];
results.forEach((res, i) => { if (res.vulns?.length) hits.push({ ...pkgs.at(i), ids: res.vulns.map((v) => v.id) }); });
console.log(JSON.stringify({ checked: pkgs.length, direct: direct.size, vulnerable: hits }, null, 2));
for (const h of hits) {
  for (const id of h.ids) {
    const v = await (await fetch(`https://api.osv.dev/v1/vulns/${id}`)).json();
    console.log(h.name, h.version, id, "|", v.summary ?? v.details?.slice(0, 160));
  }
}
