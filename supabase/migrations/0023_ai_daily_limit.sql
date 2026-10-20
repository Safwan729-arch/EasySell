-- =============================================================================
-- 0023: a daily limit on AI calls, per user and for the whole app
-- (spec docs/superpowers/specs/2026-10-20-ai-daily-limit-design.md, finding M1)
-- =============================================================================
-- Every signed-in account could call the three AI functions (voice selling,
-- scanning, money tips) without limit, so one account could use up the
-- shared Gemini quota and stop the AI for every shop.
--
-- Now each AI function calls claim_ai_call() just before it calls Gemini.
-- The function counts the call and says no once the user, or the whole app,
-- has reached today's limit. The function then answers 429 without calling
-- Gemini.
--
-- Limits live in ai_limits (one row) so they can be changed from the SQL
-- editor without a new migration:
--   update ai_limits set per_user_daily = 100, app_daily = 1000;
-- A "day" is the UTC day (it starts at 06:00 in Bangladesh).
--
-- Safe to run more than once.
-- =============================================================================

begin;

-- 1. The limits. One row only (id is always true).
create table if not exists ai_limits (
  id             boolean primary key default true check (id),
  per_user_daily integer not null check (per_user_daily >= 0),
  app_daily      integer not null check (app_daily >= 0)
);
insert into ai_limits (id, per_user_daily, app_daily)
values (true, 50, 500)
on conflict (id) do nothing;

-- 2. The counters: calls per user per day, and for the whole app per day.
create table if not exists ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day     date not null,
  calls   integer not null default 0,
  primary key (user_id, day)
);
create table if not exists ai_usage_total (
  day   date primary key,
  calls integer not null default 0
);

-- RLS on with no policies: no API user can read or change any of these.
-- Only claim_ai_call (below) and admin roles touch them.
alter table ai_limits      enable row level security;
alter table ai_usage       enable row level security;
alter table ai_usage_total enable row level security;
revoke all on ai_limits, ai_usage, ai_usage_total from anon, authenticated;

-- 3. Count one AI call for the signed-in user, or refuse it.
-- Returns {"allowed": true|false, "reason": null|"user"|"app", "used", "limit"}.
-- Security definer so it can write the counters the caller cannot see; it
-- only ever acts on auth.uid(), never on an id the caller passes in.
create or replace function claim_ai_call()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user   uuid := auth.uid();
  v_day    date := (now() at time zone 'UTC')::date;
  v_limits ai_limits;
  v_used   integer;
begin
  if v_user is null
     or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Sign in to use the AI' using errcode = '42501';
  end if;

  select * into v_limits from ai_limits where id;
  if v_limits is null then
    raise exception 'AI limits are not set' using errcode = 'P0001';
  end if;

  -- The user's own count first. The upsert only adds 1 while under the
  -- limit, and the row lock makes two calls at once count correctly.
  insert into ai_usage as u (user_id, day, calls)
  select v_user, v_day, 1 where v_limits.per_user_daily > 0
  on conflict (user_id, day) do update
    set calls = u.calls + 1
    where u.calls < v_limits.per_user_daily
  returning calls into v_used;
  if v_used is null then
    return jsonb_build_object('allowed', false, 'reason', 'user',
      'used', v_limits.per_user_daily, 'limit', v_limits.per_user_daily);
  end if;

  -- Then the whole app's count. If that is full, take the user's call back.
  insert into ai_usage_total as t (day, calls)
  select v_day, 1 where v_limits.app_daily > 0
  on conflict (day) do update
    set calls = t.calls + 1
    where t.calls < v_limits.app_daily
  returning calls into v_used;
  if v_used is null then
    update ai_usage set calls = calls - 1 where user_id = v_user and day = v_day;
    return jsonb_build_object('allowed', false, 'reason', 'app',
      'used', v_limits.app_daily, 'limit', v_limits.app_daily);
  end if;

  select calls into v_used from ai_usage where user_id = v_user and day = v_day;
  return jsonb_build_object('allowed', true, 'reason', null,
    'used', v_used, 'limit', v_limits.per_user_daily);
end;
$$;

revoke all on function claim_ai_call() from public, anon;
grant execute on function claim_ai_call() to authenticated;

commit;
