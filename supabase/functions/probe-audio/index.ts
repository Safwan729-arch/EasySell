// Supabase Edge Function: probe-audio  (THROWAWAY DIAGNOSTIC — delete after use)
// =============================================================================
// Answers ONE question for the Voice Sale feature's Task 0 spike: does the Frog
// gateway accept AUDIO, and by which route?
//   Strategy 1 (multimodal): audio as an `input_audio` part in /chat/completions
//   Strategy 2 (transcribe):  a dedicated /audio/transcriptions endpoint
//
// It runs server-side, so it uses the FROG_API_KEY already in your Supabase
// secrets — the key never leaves the server. It embeds a tiny silent WAV so you
// can invoke it with NO body; a 200 means "the endpoint accepted audio", a 4xx
// about the content-part/file means "not supported". (Transcription of silence
// is meaningless — we're testing endpoint ACCEPTANCE, not accuracy.)
//
// Optional body overrides (all optional):
//   { "audio_base64": "...", "audio_mime": "audio/m4a",
//     "chat_model": "...", "transcribe_model": "..." }
// Pass a real clip via audio_base64 for a stronger signal if you like.
// =============================================================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const BASE_URL = (Deno.env.get("FROG_BASE_URL") ?? "https://frogapi.app/v1").replace(/\/+$/, "");
const API_KEY = Deno.env.get("FROG_API_KEY") ?? "";
// Reuse the same model config the scan feature already relies on, so this probes
// what the app would actually call. Overridable per-request.
// Prefer the SAME model the scan feature uses (OPENAI_MODEL, e.g. GPT-5.6-Sol)
// so we probe what the app would actually call. Gemini was only the old default
// and it kept coming back "under maintenance".
const DEFAULT_CHAT_MODEL =
  Deno.env.get("VOICE_MODEL") ?? Deno.env.get("OPENAI_MODEL") ?? "GPT-5.6-Sol";
const DEFAULT_TRANSCRIBE_MODEL = Deno.env.get("VOICE_TRANSCRIBE_MODEL") ?? "whisper-1";

// A ~0.15s silent 8-bit mono 8kHz WAV. Just enough to exercise the endpoints.
const SILENT_WAV_B64 =
  "UklGRtQEAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YbAEAACAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIA=";

function pretty(body: unknown, status = 200) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function tryMultimodal(audioB64: string, mime: string, model: string) {
  try {
    const res = await fetch(`${BASE_URL}/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${API_KEY}` },
      body: JSON.stringify({
        model,
        messages: [{
          role: "user",
          content: [
            { type: "text", text: "Transcribe this audio. If silent, reply exactly: SILENT." },
            { type: "input_audio", input_audio: { data: audioB64, format: mime.split("/")[1] ?? "wav" } },
          ],
        }],
      }),
    });
    const text = await res.text();
    return {
      model,
      http_status: res.status,
      accepted_audio: res.ok,
      body_snippet: text.slice(0, 600),
    };
  } catch (e) {
    return { model, error: String(e).slice(0, 400) };
  }
}

async function tryTranscribe(audioB64: string, mime: string, model: string) {
  try {
    const bytes = Uint8Array.from(atob(audioB64), (c) => c.charCodeAt(0));
    const ext = (mime.split("/")[1] ?? "wav").replace("mpeg", "mp3");
    const form = new FormData();
    form.append("file", new Blob([bytes], { type: mime }), `audio.${ext}`);
    form.append("model", model);
    const res = await fetch(`${BASE_URL}/audio/transcriptions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${API_KEY}` },
      body: form,
    });
    const text = await res.text();
    return {
      model,
      http_status: res.status,
      accepted_audio: res.ok,
      body_snippet: text.slice(0, 600),
    };
  } catch (e) {
    return { model, error: String(e).slice(0, 400) };
  }
}

Deno.serve(async (req) => {
  if (!API_KEY) {
    return pretty({ error: "FROG_API_KEY is not set in this project's secrets." }, 500);
  }
  const body = await req.json().catch(() => ({}));
  const audioB64: string = body.audio_base64 ?? SILENT_WAV_B64;
  const mime: string = body.audio_mime ?? "audio/wav";
  const chatModel: string = body.chat_model ?? DEFAULT_CHAT_MODEL;
  const transcribeModel: string = body.transcribe_model ?? DEFAULT_TRANSCRIBE_MODEL;

  const [multimodal, transcribe] = await Promise.all([
    tryMultimodal(audioB64, mime, chatModel),
    tryTranscribe(audioB64, mime, transcribeModel),
  ]);

  // Recommend the strategy the app should use. Distinguish a genuine audio
  // refusal from a transient model-maintenance blip (503) so a temporarily-down
  // model is not mistaken for "no audio support".
  const mmStatus = (multimodal as { http_status?: number }).http_status;
  const mmSnippet = (multimodal as { body_snippet?: string }).body_snippet ?? "";
  const mmMaintenance = mmStatus === 503 || /maintenance/i.test(mmSnippet);

  let recommendation: string;
  if (multimodal.accepted_audio) {
    recommendation = "VOICE_STRATEGY=multimodal — one chat call with an input_audio part works. Simplest.";
  } else if (transcribe.accepted_audio) {
    recommendation = "VOICE_STRATEGY=transcribe — chat/completions rejected audio, but /audio/transcriptions works. Use the two-step fallback.";
  } else if (mmMaintenance) {
    recommendation = "INCONCLUSIVE — the chat model was under maintenance (503), not an audio refusal. Retry in a few minutes; if it persists, try another model via {\"chat_model\":\"...\"}.";
  } else {
    recommendation = "NEITHER — the gateway genuinely rejected audio both ways. Escalate before building parse-sale.";
  }

  return pretty({
    base_url: BASE_URL,
    used: { chat_model: chatModel, transcribe_model: transcribeModel, audio_bytes_b64_len: audioB64.length },
    strategy_1_multimodal: multimodal,
    strategy_2_transcribe: transcribe,
    recommendation,
  });
});
