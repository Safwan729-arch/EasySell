// Shared helpers for the execution-evidence scripts. Talks to the LIVE
// Supabase project over plain HTTPS, exactly as the app does: the public anon
// key plus, where needed, a signed-in user's token.
//
// Needs `dart_defines.json` (git-ignored) at the repo root for the URL and the
// public anon key, and EV_CREDS pointing at a JSON file with the test accounts'
// emails and passwords (kept outside the repo; see setup.mjs).
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..", "..", "..");
const defines = JSON.parse(readFileSync(join(ROOT, "dart_defines.json"), "utf8"));
export const URL_ = defines.SUPABASE_URL;
export const ANON = defines.SUPABASE_ANON_KEY;

export const CREDS_PATH = process.env.EV_CREDS;

export function loadCreds() {
  if (!CREDS_PATH) throw new Error("set EV_CREDS to the test-accounts JSON file");
  return JSON.parse(readFileSync(CREDS_PATH, "utf8"));
}

export async function signIn(email, password) {
  const r = await fetch(`${URL_}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const b = await r.json();
  if (!r.ok) throw new Error(`sign-in failed: ${r.status} ${JSON.stringify(b)}`);
  return { token: b.access_token, userId: b.user.id };
}

/** PostgREST call as a user (token) or as the public (no token). */
export async function rest(path, { token, method = "GET", body, prefer } = {}) {
  const headers = { apikey: ANON, Authorization: `Bearer ${token ?? ANON}` };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (prefer) headers.Prefer = prefer;
  const r = await fetch(`${URL_}/rest/v1/${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await r.text();
  let data;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  return { status: r.status, data, range: r.headers.get("content-range") };
}

export const rpc = (name, args, token) =>
  rest(`rpc/${name}`, { token, method: "POST", body: args });

/** Edge Function call; returns status, body and the round-trip time in ms. */
export async function fn(name, body, token) {
  const headers = { "Content-Type": "application/json", apikey: ANON };
  if (token !== null) headers.Authorization = `Bearer ${token ?? ANON}`;
  const t0 = performance.now();
  const r = await fetch(`${URL_}/functions/v1/${name}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  const text = await r.text();
  const ms = Math.round(performance.now() - t0);
  let data;
  try { data = JSON.parse(text); } catch { data = text; }
  return { status: r.status, data, ms };
}

export function save(name, obj) {
  const dir = join(HERE, "results");
  mkdirSync(dir, { recursive: true });
  const file = join(dir, name);
  writeFileSync(file, typeof obj === "string" ? obj : JSON.stringify(obj, null, 2));
  return file;
}

export const stamp = () => new Date().toISOString();
