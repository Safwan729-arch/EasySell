// Daily AI limit (migration 0023, spec 2026-10-20-ai-daily-limit-design.md).
// Each AI function calls claimAiCall() right before it calls Gemini. It asks
// the database to count one call for the signed-in user; once the user or the
// whole app has reached today's limit, the function answers 429 and Gemini is
// never called.
//
// This file is kept identical in parse-sale, recognize-product and money-tips:
// a dashboard deploy cannot import from another folder.
//
// Fails closed: if the count cannot be checked (database down, env missing),
// the AI call is refused with 503 rather than let through unchecked.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const CHECK_TIMEOUT_MS = 5000;

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Returns null when the call may go ahead, or the Response to send back. */
export async function claimAiCall(req: Request): Promise<Response | null> {
  // The public key only identifies the project; the user's own token (passed
  // through unchanged) is what the database checks, so auth.uid() is theirs.
  const apiKey = SUPABASE_ANON_KEY || req.headers.get("apikey") || "";
  const auth = req.headers.get("Authorization") ?? "";
  if (!SUPABASE_URL || !apiKey || !auth) {
    console.error("ai-limit: missing SUPABASE_URL, api key or Authorization");
    return json({ error: "AI usage check unavailable" }, 503);
  }
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/claim_ai_call`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: apiKey, Authorization: auth },
      body: "{}",
      signal: AbortSignal.timeout(CHECK_TIMEOUT_MS),
    });
    if (!res.ok) {
      console.error(`ai-limit: check failed ${res.status}: ${(await res.text()).slice(0, 200)}`);
      return json({ error: "AI usage check unavailable" }, 503);
    }
    const out = await res.json();
    if (out?.allowed === true) return null;
    const scope = out?.reason === "app" ? "app" : "user";
    return json({
      error: scope === "app"
        ? "The AI has reached today's limit for the app. Try again tomorrow."
        : "You have reached today's AI limit. Try again tomorrow.",
      limit_scope: scope,
      limit: out?.limit ?? null,
    }, 429);
  } catch (e) {
    console.error("ai-limit: check failed:", e);
    return json({ error: "AI usage check unavailable" }, 503);
  }
}
