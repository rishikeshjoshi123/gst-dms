#!/usr/bin/env bash
# Verifies overlapping hierarchy roots serialize rather than deadlock or emit
# a duplicate operation. Run only against the disposable local Supabase DB.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cli="$repo_root/node_modules/.bin/supabase"
setup_sql="$repo_root/supabase/tests/hierarchical_resource_trash_commands_concurrency_setup.sql"
session_a_sql="$repo_root/supabase/tests/hierarchical_resource_trash_commands_concurrency_session_a.sql"
project_id="$(awk -F'"' '/^project_id = / { print $2; exit }' "$repo_root/supabase/config.toml")"
result_file="$(mktemp -t trash-hierarchy-race.XXXXXX)"
session_a_pid=""

cleanup() {
  if [ -n "$session_a_pid" ] && kill -0 "$session_a_pid" 2>/dev/null; then
    kill "$session_a_pid" 2>/dev/null || true
    wait "$session_a_pid" 2>/dev/null || true
  fi
  rm -f "$result_file"
}
trap cleanup EXIT

"$cli" db reset --local --no-seed
"$cli" db query --local --file "$setup_sql"

db_container="$(docker ps --filter "name=^/supabase_db_${project_id}$" --format '{{.ID}}' | head -n 1)"
if [ -z "$db_container" ]; then
  echo "could not resolve the local Supabase Postgres container" >&2
  exit 1
fi

docker exec -i "$db_container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres <"$session_a_sql" &
session_a_pid=$!

ready_sql="SELECT NOT pg_try_advisory_lock(hashtextextended('hierarchical-resource-trash-race-ready', 80));"
for _ in $(seq 1 100); do
  if docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "$ready_sql" | grep -qx 't'; then
    break
  fi
  sleep 0.05
done

if ! docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "$ready_sql" | grep -qx 't'; then
  echo "session A did not acquire the hierarchy race readiness lock" >&2
  exit 1
fi

docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "BEGIN; SET LOCAL statement_timeout='5s'; SELECT set_config('request.jwt.claim.sub','81100000-0000-0000-0000-000000000001',true); SELECT set_config('request.jwt.claim.role','authenticated',true); SELECT code FROM public.trash_resource('matter','81300000-0000-0000-0000-000000000001','fixture.race.matter'); COMMIT;" >"$result_file"

wait "$session_a_pid"
session_a_pid=""
if ! grep -qx 'not_available' "$result_file"; then
  echo "overlapping matter command did not serialize to not_available" >&2
  exit 1
fi
operation_count="$(docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "SELECT count(*) FROM public.trash_operations WHERE org_id='81000000-0000-0000-0000-000000000001';")"
if [ "$operation_count" != '1' ]; then
  echo "overlapping hierarchy commands created more than one operation" >&2
  exit 1
fi

echo "PASS: overlapping client/matter Trash commands serialized without deadlock or duplicate effect."
