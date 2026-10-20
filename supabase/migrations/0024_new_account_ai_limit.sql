-- =============================================================================
-- 0024: brand-new accounts get fewer AI calls
-- (spec docs/superpowers/specs/2026-10-20-new-account-ai-limit-design.md)
-- =============================================================================
-- Anyone with the APK can sign up as often as they like. 0023 caps the cost
-- (500 AI calls a day for the whole app, however many accounts exist), but
-- about ten fresh accounts could still use up those 500 and leave real shops
-- without AI for the rest of the day.
--
-- Now an account in its first 24 hours gets new_account_daily calls a day
-- (10) instead of per_user_daily (50). A fake account is worth 5 times less;
-- a real shop is only limited on its first day.
--
-- Change it from the SQL editor, like the other limits:
--   update ai_limits set new_account_daily = 20, new_account_hours = 48;
-- (new_account_daily = per_user_daily turns this off.)
--
-- Needs 0023. Safe to run more than once.
-- =============================================================================

begin;

alter table ai_limits
  add column if not exists new_account_daily integer not null default 10
    check (new_account_daily >= 0),
  add column if not exists new_account_hours integer not null default 24
    check (new_account_hours >= 0);

-- Same as 0023, except the user's limit now depends on the account's age.
-- Returns {"allowed", "reason": null|"user"|"app", "used", "limit",
-- "new_account": true|false}.
create or replace function claim_ai_call()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user    uuid := auth.uid();
  v_day     date := (now() at time zone 'UTC')::date;
  v_limits  ai_limits;
  v_created timestamptz;
  v_new     boolean;
  v_limit   integer;
  v_used    integer;
begin
  if v_user is null
     or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Sign in to use the AI' using errcode = '42501';
  end if;

  select * into v_limits from ai_limits where id;
  if v_limits is null then
    raise exception 'AI limits are not set' using errcode = 'P0001';
  end if;

  -- Account age from Auth's own record, which the user cannot change.
  -- An account with no record is treated as new (the stricter limit).
  select created_at into v_created from auth.users where id = v_user;
  v_new := v_created is null
        or v_created > now() - make_interval(hours => v_limits.new_account_hours);
  v_limit := case when v_new
                  then least(v_limits.per_user_daily, v_limits.new_account_daily)
                  else v_limits.per_user_daily end;

  -- The user's own count first. The upsert only adds 1 while under the
  -- limit, and the row lock makes two calls at once count correctly.
  insert into ai_usage as u (user_id, day, calls)
  select v_user, v_day, 1 where v_limit > 0
  on conflict (user_id, day) do update
    set calls = u.calls + 1
    where u.calls < v_limit
  returning calls into v_used;
  if v_used is null then
    return jsonb_build_object('allowed', false, 'reason', 'user',
      'used', v_limit, 'limit', v_limit, 'new_account', v_new);
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
      'used', v_limits.app_daily, 'limit', v_limits.app_daily, 'new_account', v_new);
  end if;

  select calls into v_used from ai_usage where user_id = v_user and day = v_day;
  return jsonb_build_object('allowed', true, 'reason', null,
    'used', v_used, 'limit', v_limit, 'new_account', v_new);
end;
$$;

revoke all on function claim_ai_call() from public, anon;
grant execute on function claim_ai_call() to authenticated;

commit;
