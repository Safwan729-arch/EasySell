// Supabase Edge Function: money-tips
// Turns the Money health numbers the app has ALREADY calculated into 1-3 short,
// plain tips for the shopkeeper (spec 2026-10-18-money-health-financing-design.md
// §9). Gemini only words and prioritises; it never calculates. Every number it
// may use arrives pre-formatted in `facts`, and the prompt forbids any other.
//
// Same Gemini-direct setup as recognize-product: generateContent, structured
// output, a token cap and a server-side deadline. Only GEMINI_API_KEY is
// required (shared with scan and voice). MEMBER B owns prompt tuning.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const MODEL = Deno.env.get("GEMINI_TIPS_MODEL") ?? "gemini-3.6-flash";

// Three short tips fit easily; a cap hit truncates the JSON and surfaces as a
// fast 502 rather than a hang (same reasoning as recognize-product).
const MAX_OUTPUT_TOKENS = 800;

// Well under the app's 30 s request timeout, so the server's honest 502
// arrives before the client gives up.
const GEMINI_TIMEOUT_MS = 20000;

const LANGUAGES: Record<string, string> = {
  en: "simple English",
  bn: "simple Bangla (Bengali script, Bengali digits)",
};

const instruction = (lang: string, facts: unknown) =>
  `You are a friendly money helper for a small grocery shop owner.
Write 1 to 3 short tips (each under 25 words) in ${LANGUAGES[lang]}.

Rules:
- Use ONLY the facts below. Never invent, calculate or change a number; copy amounts exactly as written.
- "warnings" is the app's complete list of problems. Only these are problems: never call anything else a problem or a drop (a small change in sales between weeks is normal). Handle warnings in the order given.
- With no warnings, the shop is healthy: give practical tips for keeping it so (for example, collecting credit owed before it gets old).
- Each tip says one concrete thing to do this week.
- If a financing option "fits", you may say it could help and to compare the lender's terms first. Never tell them to take a loan. Never name a real bank or lender.
- No greetings, no emojis, no markdown.

Facts (JSON): ${JSON.stringify(facts)}`;

const responseSchema = {
  type: "object",
  properties: {
    tips: { type: "array", items: { type: "string" } },
  },
  required: ["tips"],
};

async function tips(lang: string, facts: unknown): Promise<string[]> {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": GEMINI_API_KEY,
      },
      signal: AbortSignal.timeout(GEMINI_TIMEOUT_MS),
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: instruction(lang, facts) }] }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema,
          // A little warmth for wording; the facts pin the content.
          temperature: 0.4,
          maxOutputTokens: MAX_OUTPUT_TOKENS,
          thinkingConfig: { thinkingLevel: "minimal" },
        },
      }),
    },
  );
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`gemini ${res.status}: ${detail.slice(0, 300)}`);
  }
  const body = await res.json();
  const parts = body?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts) || parts.length === 0) {
    throw new Error(
      `gemini: unexpected response shape: ${JSON.stringify(body).slice(0, 300)}`,
    );
  }
  const text = parts
    .filter((p: Record<string, unknown>) => !p?.thought)
    .map((p: Record<string, unknown>) => (typeof p?.text === "string" ? p.text : ""))
    .join("");
  const raw = JSON.parse(text) as { tips?: unknown };
  // Never trust the shape: strings only, trimmed, non-empty, at most three.
  const clean = (Array.isArray(raw.tips) ? raw.tips : [])
    .filter((t): t is string => typeof t === "string")
    .map((t) => t.trim())
    .filter((t) => t.length > 0)
    .slice(0, 3);
  if (clean.length === 0) throw new Error("gemini: no tips in reply");
  return clean;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Supabase checks the token's signature before a request reaches this code
// (JWT verification is on by default: never deploy with --no-verify-jwt). But
// the public anon key passes that check too, and it ships inside every APK, so
// anyone could unpack the app and spend the Gemini quota with no account.
// Only a signed-in user's token carries role "authenticated"; a guest
// (anonymous) session is refused too, since anyone can create one with the
// anon key.
function isSignedInUser(req: Request): boolean {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const payload = token.split(".")[1];
  if (!payload) return false;
  try {
    const claims = JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/")));
    return claims?.role === "authenticated" && claims?.is_anonymous !== true;
  } catch (_e) {
    return false;
  }
}

// The app's facts are a few hundred characters; anything far bigger is not
// from the app and would only buy a longer (dearer) prompt.
const MAX_FACTS_CHARS = 8000;

Deno.serve(async (req) => {
  if (!isSignedInUser(req)) {
    return json({ error: "sign in required" }, 401);
  }
  let lang: unknown;
  let facts: unknown;
  try {
    const body = await req.json();
    lang = body.lang;
    facts = body.facts;
  } catch (_e) {
    return json({ error: "invalid JSON body" }, 400);
  }
  // Object.hasOwn, not `in`: `in` also matches inherited names, so
  // lang "toString" would pass and put a function's source in the prompt.
  if (typeof lang !== "string" || !Object.hasOwn(LANGUAGES, lang)) {
    return json({ error: "lang must be 'en' or 'bn'" }, 400);
  }
  if (facts === null || typeof facts !== "object") {
    return json({ error: "facts is required" }, 400);
  }
  if (JSON.stringify(facts).length > MAX_FACTS_CHARS) {
    return json({ error: "facts too large" }, 413);
  }
  if (!GEMINI_API_KEY) {
    return json({ error: "GEMINI_API_KEY is not configured" }, 400);
  }
  try {
    return json({ tips: await tips(lang, facts) }, 200);
  } catch (e) {
    console.error("money-tips failed:", e);
    return json({ error: "tips failed" }, 502);
  }
});
