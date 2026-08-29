#!/usr/bin/env bash
# Reproduces the formerly unsafe interleaving with two persistent local
# PostgreSQL sessions. The Supabase CLI cannot send this session's multi-command
# transaction as a prepared statement, so it is used only for reset/fixture;
# Docker's local Supabase Postgres container runs both `psql` sessions. Session
# A holds a provenance-style target version/document prefix while session B runs
# placement for another document in the same matter. Placement must return
# target_snapshot_busy before it can wait on that target while holding the
# matter fence.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cli="$repo_root/node_modules/.bin/supabase"
session_a_sql="$repo_root/supabase/tests/document_processing_relationship_placement_deadlock_session_a.sql"
fixture_sql="$repo_root/supabase/tests/document_processing_relationship_placement.sql"
result_file="$(mktemp -t placement-deadlock-result.XXXXXX)"
project_id="$(awk -F'"' '/^project_id = / { print $2; exit }' "$repo_root/supabase/config.toml")"
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
"$cli" db query --local --file "$fixture_sql"

if [ -z "$project_id" ]; then
  echo "could not resolve Supabase project_id from supabase/config.toml" >&2
  exit 1
fi
db_container="$(docker ps --filter "name=^/supabase_db_${project_id}$" --format '{{.ID}}' | head -n 1)"
if [ -z "$db_container" ]; then
  echo "could not resolve the local Supabase Postgres container for project $project_id" >&2
  exit 1
fi

docker exec -i "$db_container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres <"$session_a_sql" &
session_a_pid=$!

ready_sql="SELECT NOT pg_try_advisory_lock(hashtextextended('placement-deadlock-harness-ready', 78)) AS ready;"
for _ in $(seq 1 100); do
  if docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "$ready_sql" | grep -qx 't'; then
    break
  fi
  sleep 0.05
done

if ! docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "$ready_sql" | grep -qx 't'; then
  echo "session A did not acquire its provenance-style version/document locks" >&2
  exit 1
fi

docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "SET statement_timeout = '2s'; SELECT code FROM public.place_document_processing_relationships('78000000-0000-0000-0000-000000000001'::uuid, '78300000-0000-0000-0000-000000000001'::uuid, '78400000-0000-0000-0000-000000000001'::uuid, (SELECT current_version_id FROM public.documents WHERE id = '78400000-0000-0000-0000-000000000001'::uuid), '78100000-0000-0000-0000-000000000001'::uuid);" >"$result_file"

wait "$session_a_pid"
session_a_pid=""
if ! grep -q 'target_snapshot_busy' "$result_file"; then
  echo "placement did not safely return target_snapshot_busy" >&2
  exit 1
fi

echo "PASS: two-session provenance/placement interleaving returned target_snapshot_busy without waiting."
