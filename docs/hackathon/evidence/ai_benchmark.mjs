// AI accuracy, speed and cost on the LIVE AI functions.
//
//   EV_CREDS=<creds.json> node ai_benchmark.mjs <photos dir> <audio work dir>
//
// Voice: 20 sale sentences (10 English, 10 Bangla) are turned into speech with
// Google's text-to-speech voice and sent to `parse-sale` as audio, the same way
// the app sends a recording. Camera: 13 photos (11 shop products, 2 things the
// shop does not sell) are sent to `recognize-product`. Both use the demo shop's
// 55-product list. Scoring is strict: the top match must be the right product,
// and for voice the quantity must be exact.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { fn, loadCreds, save, signIn, stamp } from "./lib.mjs";

const [photosDir, audioDir] = process.argv.slice(2);
if (!photosDir || !audioDir) throw new Error("usage: node ai_benchmark.mjs <photos dir> <audio dir>");
mkdirSync(audioDir, { recursive: true });

// The demo shop's catalogue (supabase/seed/demo_data.sql), in seed order.
// [name, brand, variant, unit]
const CATALOGUE = [
  ["Miniket Rice", "Loose", null, "kg"], ["Nazirshail Rice", "Loose", null, "kg"],
  ["Chinigura Rice", "Pran", "1kg", "pcs"], ["Atta", "Fresh", "2kg", "pcs"],
  ["Suji", "Teer", "500g", "pcs"], ["Chira", "Loose", null, "kg"],
  ["Soyabean Oil", "Teer", "1L", "pcs"], ["Soyabean Oil", "Rupchanda", "5L", "pcs"],
  ["Mustard Oil", "Radhuni", "500ml", "pcs"], ["Palm Oil", "Loose", null, "litre"],
  ["Masoor Dal", "Loose", null, "kg"], ["Mung Dal", "Loose", null, "kg"],
  ["Chola", "Loose", null, "kg"], ["Mashkalai Dal", "Loose", null, "kg"],
  ["Onion", "Local", null, "kg"], ["Potato", "Local", null, "kg"],
  ["Garlic", "Local", null, "kg"], ["Ginger", "Local", null, "kg"],
  ["Green Chilli", "Local", null, "kg"], ["Tomato", "Local", null, "kg"],
  ["Turmeric Powder", "Radhuni", "200g", "pcs"], ["Chilli Powder", "Radhuni", "200g", "pcs"],
  ["Cumin Powder", "Radhuni", "100g", "pcs"], ["Garam Masala", "Radhuni", "50g", "pcs"],
  ["Salt", "ACI", "1kg", "pcs"], ["Sugar", "Loose", null, "kg"],
  ["Wheel Powder", "Unilever", "1kg", "pcs"], ["Rin Powder", "Unilever", "500g", "pcs"],
  ["Vim Bar", "Unilever", "300g", "pcs"], ["Harpic", "Reckitt", "500ml", "pcs"],
  ["Lux Soap", "Unilever", "100g", "pcs"], ["Lifebuoy Soap", "Unilever", "100g", "pcs"],
  ["Sunsilk Shampoo", "Unilever", "180ml", "pcs"], ["Toothpaste", "Pepsodent", "100g", "pcs"],
  ["Coconut Oil", "Parachute", "200ml", "pcs"], ["Pepsi", "PepsiCo", "500ml", "pcs"],
  ["Mojo", "Akij", "250ml", "pcs"], ["Coca-Cola", "Coca-Cola", "1L", "pcs"],
  ["Sprite", "Coca-Cola", "250ml", "pcs"], ["Mum Water", "Partex", "500ml", "pcs"],
  ["Tea", "Ispahani", "400g", "pcs"], ["Nescafe Classic", "Nestle", "50g", "pcs"],
  ["Potato Crackers", "Bombay", "22g", "pcs"], ["Chanachur", "Bombay", "150g", "pcs"],
  ["Mr. Noodles", "Square", "Masala", "pcs"], ["Energy Plus", "Olympic", "240g", "pcs"],
  ["Dairy Milk", "Cadbury", "38g", "pcs"], ["Fruit Cake", "Bisk Club", "300g", "pcs"],
  ["Sandwich Bread", "Fresh Bake", "400g", "pcs"], ["Liquid Milk", "Milk Vita", "500ml", "pcs"],
  ["Sweet Yogurt", "Pran", "500g", "pcs"], ["Farm Eggs", "Local", null, "pcs"],
  ["Milk Powder", "Dano", "500g", "pcs"], ["Butter", "Aarong", "200g", "pcs"],
  ["Ghee", "Pran", "200g", "pcs"],
];
const idx = (name, brand) =>
  CATALOGUE.findIndex(([n, b]) => n === name && (!brand || b === brand));

// Same shape the app builds (scan_candidates.dart): list index as the id.
const candidates = (withUnit) =>
  CATALOGUE.map(([name, brand, variant, unit], i) => ({
    i, name,
    ...(brand ? { brand } : {}),
    ...(variant ? { variant } : {}),
    ...(withUnit ? { unit } : {}),
  }));

const VOICE = [
  ["en", "Two Pepsi and one kilo of onion", [["Pepsi", 2], ["Onion", 1]]],
  ["en", "Three Lux soap", [["Lux Soap", 3]]],
  ["en", "Give me five eggs and one bread", [["Farm Eggs", 5], ["Sandwich Bread", 1]]],
  ["en", "One litre Teer soyabean oil", [["Soyabean Oil:Teer", 1]]],
  ["en", "Half kg garlic and two kg potato", [["Garlic", 0.5], ["Potato", 2]]],
  ["en", "Two packets Mr Noodles and one Dairy Milk", [["Mr. Noodles", 2], ["Dairy Milk", 1]]],
  ["en", "One Harpic and two Vim bar", [["Harpic", 1], ["Vim Bar", 2]]],
  ["en", "Four Mum water", [["Mum Water", 4]]],
  ["en", "One kg sugar, one salt and one tea", [["Sugar", 1], ["Salt", 1], ["Tea", 1]]],
  ["en", "Two Coca-Cola and three Sprite", [["Coca-Cola", 2], ["Sprite", 3]]],
  ["bn", "দুইটা পেপসি আর এক কেজি পেঁয়াজ", [["Pepsi", 2], ["Onion", 1]]],
  ["bn", "তিনটা লাক্স সাবান", [["Lux Soap", 3]]],
  ["bn", "পাঁচটা ডিম আর একটা পাউরুটি", [["Farm Eggs", 5], ["Sandwich Bread", 1]]],
  ["bn", "আড়াই কেজি আলু", [["Potato", 2.5]]],
  ["bn", "দেড় কেজি মসুর ডাল", [["Masoor Dal", 1.5]]],
  ["bn", "একটা হারপিক আর দুইটা ভিম বার", [["Harpic", 1], ["Vim Bar", 2]]],
  ["bn", "দুই প্যাকেট চানাচুর", [["Chanachur", 2]]],
  ["bn", "এক কেজি চিনি আর এক প্যাকেট লবণ", [["Sugar", 1], ["Salt", 1]]],
  ["bn", "চারটা মজো", [["Mojo", 4]]],
  ["bn", "আধা কেজি রসুন আর এক কেজি টমেটো", [["Garlic", 0.5], ["Tomato", 1]]],
];

// photo file (without .jpg) -> expected product, or null for "not sold here".
const PHOTOS = {
  coca_cola: "Coca-Cola", pepsi: "Pepsi", lifebuoy: "Lifebuoy Soap", lux: "Lux Soap",
  dairy_milk: "Dairy Milk", pepsodent: "Toothpaste", parachute: "Coconut Oil",
  eggs: "Farm Eggs", onion: "Onion", tomato: "Tomato", garlic: "Garlic",
  banana_none: null, babyruth_none: null,
};

const expectedIndex = (key) => {
  const [name, brand] = key.split(":");
  const i = idx(name, brand);
  if (i < 0) throw new Error(`unknown product ${key}`);
  return String(i);
};
const top = (matches) =>
  [...(matches ?? [])].sort((a, b) => b.confidence - a.confidence)[0]?.product_id ?? null;

async function speech(lang, text, file) {
  if (existsSync(file)) return;
  const u = new URL("https://translate.google.com/translate_tts");
  u.searchParams.set("ie", "UTF-8");
  u.searchParams.set("tl", lang === "bn" ? "bn" : "en-IN");
  u.searchParams.set("client", "tw-ob");
  u.searchParams.set("q", text);
  const r = await fetch(u, { headers: { "User-Agent": "Mozilla/5.0" } });
  if (!r.ok) throw new Error(`TTS failed ${r.status}`);
  writeFileSync(file, Buffer.from(await r.arrayBuffer()));
}

const seconds = (file) =>
  Number(execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file]).toString().trim());

const { a } = loadCreds();
const { token } = await signIn(a.email, a.password);

// Warm both functions first, as the app does, so cold starts are not timed.
await fn("parse-sale", { ping: true, candidates: [] }, token);

const voice = [];
for (const [n, [lang, text, expect]] of VOICE.entries()) {
  const file = join(audioDir, `voice_${String(n + 1).padStart(2, "0")}_${lang}.mp3`);
  await speech(lang, text, file);
  const b64 = readFileSync(file).toString("base64");
  const res = await fn("parse-sale", { audio_base64: b64, audio_mime: "audio/mpeg", candidates: candidates(true) }, token);
  const items = res.data?.items ?? [];
  const got = items.map((it) => ({ product: top(it.matches), quantity: it.quantity, heard: it.heard }));
  const checks = expect.map(([key, qty]) => {
    const want = expectedIndex(key);
    const hit = got.find((g) => g.product === want);
    return { want: CATALOGUE[Number(want)][0], qty, productOk: !!hit, quantityOk: !!hit && Math.abs((hit.quantity ?? 1) - qty) < 0.001 };
  });
  const extra = got.filter((g) => !expect.some(([key]) => expectedIndex(key) === g.product)).length;
  voice.push({
    n: n + 1, lang, said: text, seconds: Number(seconds(file).toFixed(1)), status: res.status, ms: res.ms,
    heard: res.data?.heard_text ?? null, checks, extraItems: extra,
    allRight: res.status === 200 && extra === 0 && checks.every((c) => c.productOk && c.quantityOk),
    returned: got.map((g) => ({ product: g.product === null ? null : CATALOGUE[Number(g.product)]?.[0], quantity: g.quantity })),
  });
  console.log(`voice ${n + 1} ${lang} ${res.status} ${res.ms}ms ${voice.at(-1).allRight ? "OK" : "MISS"} heard="${res.data?.heard_text ?? ""}"`);
}

const scan = [];
for (const [key, want] of Object.entries(PHOTOS)) {
  const b64 = readFileSync(join(photosDir, `${key}.jpg`)).toString("base64");
  const res = await fn("recognize-product", { image_base64: b64, candidates: candidates(false) }, token);
  const t = top(res.data?.matches);
  const gotName = t === null ? null : CATALOGUE[Number(t)]?.[0];
  const ok = want === null ? res.data?.status === "none" : gotName === want;
  scan.push({ photo: key, expected: want, status: res.status, ms: res.ms, result: res.data?.status, top: gotName, read: [res.data?.read_brand, res.data?.read_name, res.data?.read_size].filter(Boolean).join(" "), ok, kb: Math.round(b64.length * 0.75 / 1024) });
  console.log(`scan ${key} ${res.status} ${res.ms}ms ${ok ? "OK" : "MISS"} -> ${gotName ?? res.data?.status}`);
}

// Cost: the functions do not return Gemini's token counts, so tokens are
// estimated from the measured request sizes (text ≈ 4 characters a token,
// audio 32 tokens a second, images up to 1,120 tokens each) and priced at
// Google's list prices.
const PROMPT_CHARS = { voice: 4545, scan: 546 };
const listChars = (withUnit) => JSON.stringify(candidates(withUnit)).length;
const voiceIn = voice.map((v) => (PROMPT_CHARS.voice + listChars(true)) / 4 + v.seconds * 32);
const scanIn = (PROMPT_CHARS.scan + listChars(false)) / 4 + 1120;
const avg = (xs) => xs.reduce((s, x) => s + x, 0) / xs.length;
const median = (xs) => { const s = [...xs].sort((p, q) => p - q); return s[Math.floor(s.length / 2)]; };
const cost = {
  voicePerSale: avg(voiceIn) * 0.30e-6 + 250 * 2.50e-6,
  scanPerPhotoNow: scanIn * 0.75e-6 + 200 * 3.75e-6,
  scanPerPhoto2027: scanIn * 1.50e-6 + 200 * 7.50e-6,
  assumptions: "text ≈ chars/4; audio 32 tokens/s; image ≤1,120 tokens; ~250 output tokens (voice), ~200 (scan); Flash-Lite US$0.30/2.50 per M; 3.6 Flash US$0.75/3.75 per M (US$1.50/7.50 from 1 Jan 2027)",
};

const items = voice.flatMap((v) => v.checks);
const by = (lang) => voice.filter((v) => v.lang === lang);
const summary = {
  ranAt: stamp(),
  voice: {
    sentences: voice.length, allRight: voice.filter((v) => v.allRight).length,
    items: items.length, productRight: items.filter((c) => c.productOk).length, quantityRight: items.filter((c) => c.quantityOk).length,
    english: `${by("en").filter((v) => v.allRight).length}/${by("en").length}`, bangla: `${by("bn").filter((v) => v.allRight).length}/${by("bn").length}`,
    medianMs: median(voice.map((v) => v.ms)), maxMs: Math.max(...voice.map((v) => v.ms)),
  },
  scan: {
    photos: scan.length, right: scan.filter((s) => s.ok).length,
    products: `${scan.filter((s) => s.expected && s.ok).length}/${scan.filter((s) => s.expected).length}`,
    notSold: `${scan.filter((s) => !s.expected && s.ok).length}/${scan.filter((s) => !s.expected).length}`,
    medianMs: median(scan.map((s) => s.ms)), maxMs: Math.max(...scan.map((s) => s.ms)),
  },
  cost,
};
console.log(JSON.stringify(summary, null, 2));
save("ai_benchmark.json", { summary, voice, scan });
