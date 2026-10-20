# Daily AI limit per user and for the whole app (2026-10-20)

Fixes security finding M1: any signed-in account could call the three AI
functions (`parse-sale`, `recognize-product`, `money-tips`) without limit, so
one account could use up the shared Gemini quota (or, with billing on, run up
a bill) and stop the AI for every shop. Migration `0023_ai_daily_limit.sql`
plus a check in each function (`ai_limit.ts`).

## Decisions

- **Limits: 50 calls per user per day, 500 for the whole app.** 50 is the
  user's call ("keep it capped at 50 for now"); a busy shop selling by voice
  all day might pass it, which is accepted while the app is a hackathon
  prototype. 500 for the app is my call: ten shops at their full limit,
  which puts a ceiling on a day's AI cost (about US$1 at the measured
  US$0.0013-0.0023 a call). Both live in the one-row `ai_limits` table, so they change
  with one `update` in the SQL editor (a limit of 0 turns the AI off), no
  migration and no redeploy.
- **The count lives in Postgres, not in the function.** Edge Function
  instances are short-lived and many run at once, so an in-memory counter
  would be per-instance and lost. `claim_ai_call()` does a conditional
  upsert (`on conflict … do update … where calls < limit`), so two calls at
  once cannot both take the last slot, and a refused call is not counted.
- **Security definer, on `auth.uid()` only.** The counters must be hidden
  from users (RLS on, no policies, privileges revoked), so the function that
  writes them runs as its owner. It takes no arguments: it can only ever count
  the caller. `search_path` is pinned; execute is granted to `authenticated`
  only; guest (anonymous) tokens are refused inside it too.
- **The function asks with the user's own token** (PostgREST RPC with the
  public key + the caller's `Authorization`), so no service-role key is
  needed in the functions. **Fails closed:** if the check errors or times out
  (5 s), the AI call is refused with 503.
- **Counted only right before Gemini**, after every validation, so a ping
  (the voice warm-up) or a malformed request costs nothing.
- **A day is the UTC day** (06:00 in Bangladesh). Matching the shop's own
  time zone was ruled out: it adds a setting per user for no security gain.
- **`ai_limit.ts` is copied into each function folder** (identical; a test
  checks this) rather than shared from `_shared/`, because the functions
  have been deployed from the dashboard editor, which cannot import from
  another folder.
- **No app change, no new APK.** A 429 reaches the app as a
  `FunctionException`, which it already shows as its "couldn't do that, try
  again" error. A friendlier "daily limit reached" message is left for the
  next app build.

## Accepted for now

- A user can call `claim_ai_call` directly and use up their own 50 without
  any AI call. That also takes 50 of the app's 500, so ten accounts could
  close the AI for the day. This is no worse than ten accounts making real
  AI calls, which was already possible; it is bounded and costs nothing.
  Closing it needs sign-up control (email confirmation, below).
- **Email confirmation stays off until judging is over** (part of M1).
  Judges must be able to sign up at once, and Supabase's built-in mailer
  sends only a few emails an hour. Before public launch: confirmation on,
  with a proper email service (custom SMTP).

## Verification

- `docs/hackathon/security/test_0023_pglite.mjs`: the full schema on PGlite,
  21 checks (limits, refusal not counted, per-user isolation, new day, app
  cap, changing the limit, guest/anon refused, counters hidden, re-run safe).
  `fullschema.mjs` now grants the API roles through default privileges at
  creation time, like Supabase, so a migration's own `revoke` holds.
- `test_ai_limit_helper.mjs`: the function-side helper against a fake
  database on Node 24 (allowed, 429 user/app, 503 on errors, the three copies
  identical, the check placed before each Gemini call and after the ping).
- `ai_limit_probe.mjs`: live, after deploy; fills test account B's count via
  the RPC (no Gemini spend), then expects 429 from `parse-sale` and
  `money-tips`.
