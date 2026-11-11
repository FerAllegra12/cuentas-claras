#!/usr/bin/env bash
# Corre migración + pruebas contra un Postgres local (host/puerto por variables PGHOST/PGPORT/PGUSER)
set -euo pipefail
DB=${DB:-cc_test}
HERE=$(cd "$(dirname "$0")" && pwd)
psql -q -d postgres -c "drop database if exists $DB" -c "create database $DB"
psql -q -d "$DB" -v ON_ERROR_STOP=1 <<'SQL'
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
end $$;
create schema auth;
create table auth.users (id uuid primary key default gen_random_uuid(), email text, raw_user_meta_data jsonb default '{}'::jsonb);
create function auth.uid() returns uuid language sql stable as $f$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $f$;
SQL
psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$HERE/../migrations/0001_init.sql"
psql -q -d "$DB" -v ON_ERROR_STOP=1 -f "$HERE/flows.sql" 2>&1 | grep -E "NOTICE|ERROR|TODO OK" | sed -E 's/^psql:[^ ]+ NOTICE:  //'
