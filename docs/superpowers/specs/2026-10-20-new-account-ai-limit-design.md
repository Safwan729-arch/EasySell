# Fewer AI calls for brand-new accounts, a sign-up rate limit, and the subscription plan (2026-10-20)

The user pointed out that anyone with the APK can sign up as often as they
like and use the AI. After 0023 ([[2026-10-20-ai-daily-limit-design]]) that
can no longer run up a bill: the whole app is capped at 500 calls a day,
about US$1. What was left is denial of service: about ten fresh accounts
could use up the 500 and leave real shops without AI until the next UTC day.
Migration `0024_new_account_ai_limit.sql` plus one Auth setting.

## Decisions

- **10 AI calls a day for an account's first 24 hours, then 50.** Ten fresh
  accounts now get 100 calls, not 500, so it takes about 50 accounts to drain
  the app cap. A real shop is limited only on its first day, when 10 voice or
  photo sales is enough to try the app. Both numbers (`new_account_daily`,
  `new_account_hours`) live in `ai_limits` and change from the SQL editor;
  `new_account_daily = per_user_daily` turns the rule off. `least()` makes
  sure a first-day limit can never raise the normal one.
- **Account age comes from `auth.users.created_at`**, read inside the
  security-definer `claim_ai_call()`. Users cannot write `auth.users`, so
  they cannot make an account look older. No record means "new" (the
  stricter side).
- **No Edge Function or app change.** The functions already map any refusal
  that is not the app cap to "You have reached today's AI limit", so 0024 is
  SQL only, and the APK stays at build 5. The reply now also carries
  `new_account`, which a later app build can use for a clearer message.
- **Judges are not affected**: the shared demo account is weeks old. A judge
  who signs up fresh gets 10 calls on day one, which is enough to try voice
  and camera selling.
- **Sign-up rate limit (option 1): Supabase Auth's own per-IP limit on
  sign-ups and sign-ins** (Authentication > Rate limits), not our code.
  Suggested 15 per 5 minutes (Supabase's default is 30). Not lower, because
  judges or a shop team on one Wi-Fi share an IP and sign-ins count too.
  `signin_rate_probe.mjs` checks it live with failed sign-ins, so it creates
  no accounts.
- **Rejected for now: a CAPTCHA on sign-up** (needs a new APK and a provider
  key) **and email confirmation** (judges must sign up at once; the built-in
  mailer sends only a few emails an hour). Both stay in the remediation plan
  for after judging (finding L8).

## Future plan: AI for paying subscribers only

The user's decision (20 Oct): later, a proper sign-up and login, and only
shops that pay the monthly subscription can use the AI features. This is the
real answer to mass sign-ups: a free account would get no AI at all, so
fake accounts are worthless. The pieces already line up with it:
`claim_ai_call()` is the single gate every AI call passes, so "is this
account subscribed?" becomes one more check there (a `subscriptions` table
written only by the payment provider's webhook), and the per-user limits
become per-plan limits. Not built; no design yet beyond this.

## Verification

- `docs/hackathon/security/test_0024_pglite.mjs`: the full schema on PGlite,
  16 checks (new account limited to 10 then refused; 23 h still new, 25 h
  gets 50; the same account goes on to 50 once a day old; users cannot
  change their account's age; settings apply at once; the app cap still
  wins; still hidden and security definer; re-run keeps settings).
  `test_0023_pglite.mjs` now uses 2-day-old accounts so its 50-call checks
  still hold.
- Live: `new_account_probe.mjs` (a fresh sign-up is refused after 10 calls,
  then `parse-sale` answers 429) and `signin_rate_probe.mjs`. **20 Oct:
  4/4** (the first run caught the SQL going live mid-run: its early calls
  still had the 50 limit, so it was re-run with a fresh account), and the
  sign-in limit answered 429 on attempt 35.
- **Gotcha: a burst test cannot show the rate limit.** Supabase Auth uses a
  token bucket: up to 30 requests always pass in a burst, and the dashboard
  value is only the refill rate. `signup_rate_probe.mjs` empties the bucket,
  then sends one refused sign-up (3-character password, so no account) every
  5 s for 120 s. Measured on 20 Oct: 13 through (30 per 5 min, the default:
  the first save of 15 had not taken), then, after the user saved again, 6
  through (one every ~20 s = **15 per 5 min**), twice. One run in between let
  21 through, consistent with Auth restarting to apply the change (a restart
  refills the bucket); re-test a minute or two after saving.
- **The setting does not govern password sign-ins.** `/auth/v1/token` kept
  answering one failed sign-in every 2 s after its 30-request burst (about
  1,800 an hour, Supabase's fixed token-endpoint rate). Password guessing is
  therefore limited mainly by password strength: finding L3.
