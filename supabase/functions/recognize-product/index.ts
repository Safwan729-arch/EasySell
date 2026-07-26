// Supabase Edge Function: recognize-product
// Identifies a retail product from a photo by calling Google's official Gemini
// API directly (gemini-3.6-flash) and returns a normalized JSON match result.
//
// History: this function previously routed the image through the Frog gateway
// (OpenAI-compatible, serving GPT/Gemini). It now calls Gemini's generateContent
// endpoint directly — the image goes in as inline_data, and Gemini structured
// output (responseSchema) forces the reply into the exact JSON shape below, so
// there is no brace-scraping. Only GEMINI_API_KEY is required (shared with the
// voice function). MEMBER B owns prompt tuning.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

interface Candidate { id: string; name: string; brand?: string; variant?: string }

// Google Gemini config. Only GEMINI_API_KEY must be set. Model is pinned to
// gemini-3.6-flash but overridable via a secret so a future slug rename never
// needs a code change.
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const MODEL = Deno.env.get("GEMINI_VISION_MODEL") ?? "gemini-3.6-flash";
// The app sends JPEG bytes today; the previous code hard-coded the same mime.
const IMAGE_MIME = "image/jpeg";

const instruction = (candidates: Candidate[]) =>
  `You are identifying a retail product from a photo for a shop's point-of-sale.
Below is the shop's product list (JSON). Decide which listed product(s) appear in the image.
Match the brand/name/size you can read on the packaging to the candidates.
Rank matches by confidence (highest first). If nothing matches, use status "none" and an empty matches array. Never invent an id that is not in the list.
Set read_brand/read_name/read_size to what you can read off the packaging, or null if unreadable.
Product list: ${JSON.stringify(candidates)}`;

// Gemini structured-output schema — forces the reply into the exact response
// contract shape instead of coaxing it via prompt text. (OpenAPI 3.0 subset that
// Gemini accepts: object/array/string/number, enum, nullable, required.)
const responseSchema = {
  type: "object",
  properties: {
    status: { type: "string", enum: ["match", "multiple", "none"] },
    read_brand: { type: "string", nullable: true },
    read_name: { type: "string", nullable: true },
    read_size: { type: "string", nullable: true },
    matches: {
      type: "array",
      items: {
        type: "object",
        properties: {
          product_id: { type: "string" },
          confidence: { type: "number" },
        },
        required: ["product_id", "confidence"],
      },
    },
  },
  required: ["status", "matches"],
};

// One call to Gemini generateContent: image in as inline_data, structured JSON
// out. Same res.ok guard-and-throw discipline as the voice function — a non-2xx
// (bad key -> 400, quota -> 429, outage -> 5xx) must surface as a 502, never a
// misleading empty status:"none".
async function recognize(imageB64: string, candidates: Candidate[]) {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY },
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [
              { text: instruction(candidates) },
              { inline_data: { mime_type: IMAGE_MIME, data: imageB64 } },
            ],
          },
        ],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema,
          temperature: 0,
          // Disable the model's internal "thinking" — identifying a product from
          // a photo against a candidate list is a simple, structured job, and
          // thinking adds several seconds of latency for no quality gain here.
          thinkingConfig: { thinkingBudget: 0 },
        },
      }),
    },
  );
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`gemini ${res.status}: ${detail.slice(0, 300)}`);
  }
  const body = await res.json();
  // A missing/empty candidates array or a non-array parts list is NOT a real
  // "no match" — it means a safety block, quota oddity, or API shape change and
  // must surface as a 502 (retry), never a silent status:"none".
  const parts = body?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(body?.candidates) || body.candidates.length === 0 ||
      !Array.isArray(parts) || parts.length === 0) {
    throw new Error(`gemini: unexpected response shape: ${JSON.stringify(body).slice(0, 300)}`);
  }
  // Join every non-`thought` part's text (a thinking model may emit a thought
  // segment before the answer), then parse. Structured output should already be
  // clean JSON, but parse defensively — a safety truncation can still break it,
  // and a parse failure throws -> 502.
  const text = parts
    .filter((p: Record<string, unknown>) => !p?.thought)
    .map((p: Record<string, unknown>) => (typeof p?.text === "string" ? p.text : ""))
    .join("");
  return JSON.parse(text) as Record<string, unknown>;
}

// Never trust the model's output shape. Drop invented ids, clamp confidences,
// derive status from surviving matches, and coerce read_* fields to string|null.
function normalize(raw: Record<string, unknown>, candidates: Candidate[]) {
  const ids = new Set(candidates.map((c) => c.id));
  const matches = Array.isArray(raw.matches) ? raw.matches : [];
  const clean = matches
    .filter((m: Record<string, unknown>) => ids.has(m?.product_id as string))
    .map((m: Record<string, unknown>) => ({
      product_id: m.product_id,
      confidence: Math.max(0, Math.min(1, Number(m.confidence) || 0)),
    }));
  // Derive status from the matches that SURVIVED filtering, never from the
  // model's raw status — a hallucinated product_id dropped above could otherwise
  // leave a misleading "multiple"/"match" that steers the app's confirmation UI wrong.
  const status = clean.length === 0 ? "none" : clean.length === 1 ? "match" : "multiple";
  return {
    status,
    read_brand: typeof raw.read_brand === "string" ? raw.read_brand : null,
    read_name: typeof raw.read_name === "string" ? raw.read_name : null,
    read_size: typeof raw.read_size === "string" ? raw.read_size : null,
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
  if (typeof imageB64 !== "string" || imageB64.trim().length === 0 || !Array.isArray(candidates)) {
    return json({ error: "image_base64 and candidates are required" }, 400);
  }
  // Fast-fail with a clear message rather than letting an unset key surface as a
  // downstream Gemini 401/403 (which would read as a generic 502).
  if (!GEMINI_API_KEY) {
    return json({ error: "GEMINI_API_KEY is not configured" }, 400);
  }
  try {
    const raw = await recognize(imageB64 as string, candidates as Candidate[]);
    return json(normalize(raw, candidates as Candidate[]), 200);
  } catch (e) {
    // Genuine failures (bad key, Gemini outage, non-JSON reply, safety block)
    // return 5xx so the app shows its error/retry state instead of a misleading
    // "no match". A real "nothing matched" is still a 200 with status:"none".
    console.error("recognize-product failed:", e);
    return json({ error: "recognition failed" }, 502);
  }
});
