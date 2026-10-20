// Builds the whole EasySell database on PGlite: Supabase stubs (auth schema,
// auth.uid(), the anon/authenticated roles, the realtime publication), then
// every migration in order. Exports a ready db plus helpers to act as a user.
import { PGlite } from "@electric-sql/pglite";
import fs from "node:fs";
import path from "node:path";

export async function buildDb(migrationsDir, { upTo } = {}) {
  const db = new PGlite();
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin bypassrls;
    create schema auth;
    create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb default '{}'::jsonb, created_at timestamptz default now());
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create function auth.jwt() returns jsonb language sql stable as
      $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
    grant usage on schema auth to anon, authenticated;
    grant execute on function auth.uid(), auth.jwt() to anon, authenticated;
    create publication supabase_realtime;
    -- Supabase grants new tables and functions to the API roles by default,
    -- at creation time, so a migration's own revoke still takes effect.
    grant usage on schema public to anon, authenticated;
    alter default privileges in schema public grant all on tables to anon, authenticated;
    alter default privileges in schema public grant all on sequences to anon, authenticated;
    alter default privileges in schema public grant execute on functions to anon, authenticated;
  `);
  const files = fs.readdirSync(migrationsDir).filter((f) => /^\d{4}_.*\.sql$/.test(f)).sort();
  for (const f of files) {
    if (upTo && f > upTo) break;
    try {
      await db.exec(fs.readFileSync(path.join(migrationsDir, f), "utf8").replace(/create extension[^;]*;/gi, "-- (extension skipped on PGlite; gen_random_uuid is built in)"));
    } catch (e) {
      throw new Error(`${f}: ${e.message}`);
    }
  }
  return { db, files };
}

// Runs fn as a signed-in user (role authenticated, auth.uid() = userId),
// inside its own transaction like one PostgREST request. `claims` adds to the
// token's claims (e.g. { is_anonymous: true }).
export async function asUser(db, userId, sql, params, claims = {}) {
  return db.transaction(async (tx) => {
    await tx.query(`select set_config('request.jwt.claim.sub', $1, true)`, [userId]);
    await tx.query(`select set_config('request.jwt.claims', $1, true)`,
      [JSON.stringify({ sub: userId, role: "authenticated", ...claims })]);
    await tx.exec("set local role authenticated");
    return (await tx.query(sql, params)).rows;
  });
}

export async function tryAsUser(db, userId, sql, params, claims) {
  try { return { rows: await asUser(db, userId, sql, params, claims) }; } catch (e) { return { error: e.message }; }
}
