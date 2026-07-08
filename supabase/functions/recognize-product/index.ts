// Supabase Edge Function: recognize-product
// Routes an item photo + the shop's product candidates to an OpenAI-compatible
// gateway (Frog API) and returns a normalized JSON match result.
//
// Frog is a single OpenAI-compatible endpoint that serves BOTH OpenAI and Gemini
// models, so there is one base URL + one key; VISION_PROVIDER just picks which
// model NAME is sent. Keys stay in Supabase secrets. MEMBER B owns prompt tuning.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

interface Candidate { id: string; name: string; brand?: string; variant?: string }

// Gateway config. Base URL + model ids default to Frog's values but stay
// overridable via secrets; only FROG_API_KEY must be set.
const BASE_URL = (Deno.env.get("FROG_BASE_URL") ?? "https://frogapi.app/v1").replace(/\/+$/, "");
const API_KEY = Deno.env.get("FROG_API_KEY") ?? "";
// Which model family to use now. Both go through the same Frog endpoint/key.
const PROVIDER = (Deno.env.get("VISION_PROVIDER") ?? "openai").toLowerCase();
// Model ids as shown in the Frog dashboard. If the gateway rejects a name,
// set OPENAI_MODEL / GEMINI_MODEL secrets to the exact slug it expects.
const OPENAI_MODEL = Deno.env.get("OPENAI_MODEL") ?? "GPT-5.5";
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "Gemini-3.1-Pro";
const MODEL = PROVIDER === "openai" ? OPENAI_MODEL : GEMINI_MODEL;

const instruction = (candidates: Candidate[]) =>
  `You are identifying a retail product from a photo for a shop's point-of-sale.
Below is the shop's product list (JSON). Decide which listed product(s) appear in the image.
Match the brand/name/size you can read on the packaging to the candidates.
Return ONLY minified JSON of this exact shape:
{"status":"match|multiple|none","read_brand":string|null,"read_name":string|null,"read_size":string|null,"matches":[{"product_id":"<id from the list>","confidence":<0..1>}]}
Rank matches by confidence (highest first). If nothing matches, use status "none" and an empty matches array. Never invent an id that is not in the list.
Product list: ${JSON.stringify(candidates)}`;

function extractJson(text: string): Record<string, unknown> {
  const cleaned = text.trim().replace(/^```json/i, "").replace(/```$/, "").trim();
  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  return JSON.parse(start >= 0 ? cleaned.slice(start, end + 1) : cleaned);
}

// One OpenAI-compatible call through the Frog gateway. The image is sent as a
// data: URL in an image_url content part (the standard OpenAI vision format,
// which gateways translate for Gemini models).
async function recognize(imageB64: string, candidates: Candidate[]) {
  const res = await fetch(`${BASE_URL}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${API_KEY}`,
    },
    body: JSON.stringify({
      model: MODEL,
      temperature: 0,
      messages: [{
        role: "user",
        content: [
          { type: "text", text: instruction(candidates) },
          { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageB64}` } },
        ],
      }],
    }),
  });
  // A non-2xx from the gateway (bad key -> 401, rate limit -> 429, outage ->
  // 5xx) does NOT throw on its own; without this check res.json() would parse
  // the error body, find no choices, and fall through to a misleading
  // status:"none" 200. Throw so the caller's catch returns a 502 instead.
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`gateway ${res.status}: ${detail.slice(0, 300)}`);
  }
  const json = await res.json();
  return extractJson(json?.choices?.[0]?.message?.content ?? "{}");
}

function normalize(raw: Record<string, unknown>, candidates: Candidate[]) {
  const ids = new Set(candidates.map((c) => c.id));
  const matches = Array.isArray(raw.matches) ? raw.matches : [];
  const clean = matches
    .filter((m: Record<string, unknown>) => ids.has(m?.product_id as string))
    .map((m: Record<string, unknown>) => ({
      product_id: m.product_id,
      confidence: Math.max(0, Math.min(1, Number(m.confidence) || 0)),
    }));
  const status = clean.length === 0 ? "none" : (raw.status as string) ?? "match";
  return {
    status,
    read_brand: raw.read_brand ?? null,
    read_name: raw.read_name ?? null,
    read_size: raw.read_size ?? null,
    matches: clean,
  };
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  let imageB64: unknown;
  let candidates: unknown;
  try {
    const body = await req.json();
    imageB64 = body.image_base64;
    candidates = body.candidates;
  } catch (_e) {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (!imageB64 || !Array.isArray(candidates)) {
    return json({ error: "image_base64 and candidates are required" }, 400);
  }
  try {
    const raw = await recognize(imageB64 as string, candidates as Candidate[]);
    return json(normalize(raw, candidates as Candidate[]), 200);
  } catch (e) {
    // Genuine failures (bad key, Frog outage, non-JSON reply) return 5xx so the
    // app shows its error/retry state instead of a misleading "no match". A real
    // "nothing matched" is still a 200 with status:"none" from normalize().
    console.error("recognize-product failed:", e);
    return json({ error: "recognition failed" }, 502);
  }
});
