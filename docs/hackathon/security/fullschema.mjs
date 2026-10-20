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
    create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb default '{}'::jsonb);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth to anon, authenticated;
    grant execute on function auth.uid() to anon, authenticated;
    create publication supabase_realtime;
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
  // Supabase grants table and function access to the API roles by default.
  await db.exec(`
    grant usage on schema public to anon, authenticated;
    grant all on all tables in schema public to anon, authenticated;
    grant execute on all functions in schema public to anon, authenticated;
  `);
  return { db, files };
}

// Runs fn as a signed-in user (role authenticated, auth.uid() = userId),
// inside its own transaction like one PostgREST request.
export async function asUser(db, userId, sql, params) {
  return db.transaction(async (tx) => {
    await tx.query(`select set_config('request.jwt.claim.sub', $1, true)`, [userId]);
    await tx.exec("set local role authenticated");
    return (await tx.query(sql, params)).rows;
  });
}

export async function tryAsUser(db, userId, sql, params) {
  try { return { rows: await asUser(db, userId, sql, params) }; } catch (e) { return { error: e.message }; }
}
