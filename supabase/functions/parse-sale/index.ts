// Supabase Edge Function: parse-sale
// Voice sale parser. Given a shopkeeper's spoken sentence (audio) + the shop's
// product candidates, it asks an LLM to transcribe the speech and turn it into
// sale line items matched against those candidates, and returns normalized JSON.
//
// Like recognize-product it calls **Frog API** — a single OpenAI-compatible
// gateway serving both OpenAI and Gemini models — so there is one base URL + one
// key. Keys stay in Supabase secrets (never on the device).
//
// AUDIO reaches the model one of two ways, chosen by VOICE_STRATEGY (the
// probe-audio spike tells you which your gateway supports):
//   "multimodal" (default) — one /chat/completions call with an input_audio part
//   "transcribe"           — /audio/transcriptions first, then a text chat call
// Both produce the identical response shape, so the Flutter app is unaffected by
// the choice. MEMBER B owns prompt tuning.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

interface Candidate {
  id: string;
  name: string;
  brand?: string;
  variant?: string;
  unit?: string;
}

// Gateway config. Base URL + model ids default to Frog's values but stay
// overridable via secrets; only FROG_API_KEY must be set.
const BASE_URL = (Deno.env.get("FROG_BASE_URL") ?? "https://frogapi.app/v1").replace(/\/+$/, "");
const API_KEY = Deno.env.get("FROG_API_KEY") ?? "";
// Which model turns speech into structured intent. Model slugs retire, so keep
// this overridable via a secret rather than hardcoded.
const MODEL = Deno.env.get("VOICE_MODEL") ?? Deno.env.get("GEMINI_MODEL") ?? "Gemini-3.1-Pro";
// Only used by the "transcribe" strategy.
const TRANSCRIBE_MODEL = Deno.env.get("VOICE_TRANSCRIBE_MODEL") ?? "whisper-1";
const STRATEGY = (Deno.env.get("VOICE_STRATEGY") ?? "multimodal").toLowerCase();

const instruction = (candidates: Candidate[]) =>
  `You turn a shopkeeper's spoken sentence into sale line items for a point-of-sale.
The speech may be English, Bengali, or a mix of both.

CRITICAL RULE — quantity and size are DIFFERENT fields, never merge them:
- Count words (piece, pcs, packet, ta, টা, টি, পিস) give "quantity".
- Size words (500ml, 1 litre, kg, লিটার, কেজি) are part of "heard" and are used to
  pick the RIGHT product. A size must NEVER become the quantity.
  "pepsi 1 litre" => quantity 1, heard "pepsi 1 litre"  (matches the 1L product)
  "2 pepsi"       => quantity 2, heard "pepsi"

Match each spoken item against the shop's product list below. If the speech does
NOT distinguish between two candidates (e.g. "pepsi" when both 500ml and 1L
exist), return BOTH with SIMILAR confidence — do NOT guess a winner; the app asks
the user. Never invent a product_id that is not in the list. If no count was
spoken for an item, omit "quantity".

Return ONLY minified JSON of this exact shape:
{"heard_text":string,"items":[{"heard":string,"quantity":number,"unit_heard":string|null,"matches":[{"product_id":"<id from the list>","confidence":<0..1>}]}]}
Rank each item's matches by confidence (highest first). If nothing was recognized,
return an empty items array. Product list: ${JSON.stringify(candidates)}`;

function extractJson(text: string): Record<string, unknown> {
  const cleaned = text.trim().replace(/^```json/i, "").replace(/```$/, "").trim();
  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  return JSON.parse(start >= 0 ? cleaned.slice(start, end + 1) : cleaned);
}

// One OpenAI-compatible chat call through Frog. `content` is either a plain
// string (transcribe strategy) or a multimodal content-part array (multimodal
// strategy). NOTE: no `temperature` is sent — some newer models reject
// temperature:0 outright, and the default is fine for this extraction.
async function chat(content: unknown): Promise<Record<string, unknown>> {
  const res = await fetch(`${BASE_URL}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${API_KEY}` },
    body: JSON.stringify({ model: MODEL, messages: [{ role: "user", content }] }),
  });
  // A non-2xx from the gateway (bad key -> 401, rate limit -> 429, outage -> 5xx)
  // does not throw on its own; without this check res.json() would parse the
  // error body, find no choices, and fall through to a misleading empty 200.
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`gateway ${res.status}: ${detail.slice(0, 300)}`);
  }
  const json = await res.json();
  return extractJson(json?.choices?.[0]?.message?.content ?? "{}");
}

// Dedicated speech-to-text endpoint (transcribe strategy only).
async function transcribe(audioB64: string, mime: string): Promise<string> {
  const bytes = Uint8Array.from(atob(audioB64), (c) => c.charCodeAt(0));
  const ext = (mime.split("/")[1] ?? "m4a").replace("mpeg", "mp3");
  const form = new FormData();
  form.append("file", new Blob([bytes], { type: mime }), `audio.${ext}`);
  form.append("model", TRANSCRIBE_MODEL);
  const res = await fetch(`${BASE_URL}/audio/transcriptions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${API_KEY}` },
    body: form,
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`transcribe ${res.status}: ${detail.slice(0, 300)}`);
  }
  return (await res.json())?.text ?? "";
}

async function parse(audioB64: string, mime: string, candidates: Candidate[]) {
  if (STRATEGY === "transcribe") {
    const text = await transcribe(audioB64, mime);
    if (!text.trim()) return { heard_text: "", items: [] };
    const raw = await chat(`${instruction(candidates)}\n\nThe shopkeeper said: "${text}"`);
    return { ...raw, heard_text: raw.heard_text ?? text };
  }
  // multimodal: audio rides inside the chat call as an input_audio part.
  return await chat([
    { type: "text", text: instruction(candidates) },
    { type: "input_audio", input_audio: { data: audioB64, format: mime.split("/")[1] ?? "m4a" } },
  ]);
}

// Never trust the model's output shape. Drop invented ids, clamp confidences,
// and pass quantity through only when it is a real positive number (the app
// defaults a missing quantity to 1 and flags it, rather than us inventing one).
function normalize(raw: Record<string, unknown>, candidates: Candidate[]) {
  const ids = new Set(candidates.map((c) => c.id));
  const rawItems = Array.isArray(raw.items) ? raw.items : [];
  const items = rawItems.map((it: Record<string, unknown>) => {
    const matches = Array.isArray(it?.matches) ? it.matches : [];
    return {
      heard: typeof it?.heard === "string" ? it.heard : "",
      quantity: typeof it?.quantity === "number" && it.quantity > 0 ? it.quantity : null,
      unit_heard: typeof it?.unit_heard === "string" ? it.unit_heard : null,
      matches: matches
        .filter((m: Record<string, unknown>) => ids.has(m?.product_id as string))
        .map((m: Record<string, unknown>) => ({
          product_id: m.product_id,
          confidence: Math.max(0, Math.min(1, Number(m.confidence) || 0)),
        })),
    };
  }).filter((it) => it.heard !== "" || it.matches.length > 0);
  return { heard_text: raw.heard_text ?? null, items };
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  let audioB64: unknown;
  let mime: unknown;
  let candidates: unknown;
  try {
    const body = await req.json();
    audioB64 = body.audio_base64;
    mime = body.audio_mime ?? "audio/m4a";
    candidates = body.candidates;
  } catch (_e) {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (!audioB64 || !Array.isArray(candidates)) {
    return json({ error: "audio_base64 and candidates are required" }, 400);
  }
  try {
    const raw = await parse(audioB64 as string, mime as string, candidates as Candidate[]);
    return json(normalize(raw, candidates as Candidate[]), 200);
  } catch (e) {
    // Genuine failures (bad key, Frog outage, non-JSON reply) return 5xx so the
    // app shows its error/retry state instead of a misleading "heard nothing". A
    // real empty result is still a 200 with items: [] from normalize().
    console.error("parse-sale failed:", e);
    return json({ error: "parse failed" }, 502);
  }
});
