#!/usr/bin/env bash
# Proves that the exact 00092 -> 00093 upgrade preserves populated hierarchy
# rows while replacing every destructive FK action with RESTRICT.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cli="$repo_root/node_modules/.bin/supabase"
setup_sql="$repo_root/supabase/tests/trash_physical_delete_cascade_hardening_upgrade_setup.sql"
project_id="$(awk -F'"' '/^project_id = / { print $2; exit }' "$repo_root/supabase/config.toml")"

"$cli" db reset --local --no-seed --version 00092
db_container="$(docker ps --filter "name=^/supabase_db_${project_id}$" --format '{{.ID}}' | head -n 1)"
if [ -z "$db_container" ]; then
  echo "could not resolve the local Supabase Postgres container" >&2
  exit 1
fi

docker exec -i "$db_container" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres <"$setup_sql"
"$cli" migration up --local

catalog="$(docker exec "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "SELECT count(*) FROM pg_constraint WHERE contype='f' AND confdeltype IN ('c','n') AND confrelid IN ('public.clients'::regclass,'public.matters'::regclass,'public.documents'::regclass,'public.document_versions'::regclass,'public.wiki_sections'::regclass,'public.supporting_documents'::regclass);")"
rows="$(docker exec "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "SELECT (SELECT count(*) FROM public.clients WHERE id='93200000-0000-0000-0000-000000000001') || ':' || (SELECT count(*) FROM public.matters WHERE id='93300000-0000-0000-0000-000000000001') || ':' || (SELECT count(*) FROM public.documents WHERE id='93400000-0000-0000-0000-000000000001') || ':' || (SELECT count(*) FROM public.case_notes WHERE id='93500000-0000-0000-0000-000000000001') || ':' || (SELECT count(*) FROM public.wiki_section_versions WHERE id='93800000-0000-0000-0000-000000000001');")"

if [ "$catalog" != "0" ] || [ "$rows" != "1:1:1:1:1" ]; then
  echo "00093 upgrade did not preserve populated hierarchy rows or remove destructive FK actions: catalog=$catalog rows=$rows" >&2
  exit 1
fi

echo "PASS: 00093 preserved populated hierarchy rows and removed direct destructive FK actions."
