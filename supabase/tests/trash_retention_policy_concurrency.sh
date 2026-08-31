#!/usr/bin/env bash
# Confirms a concurrent policy save and Trash command serialize to one complete
# policy snapshot. Run only against the disposable local Supabase database.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cli="$repo_root/node_modules/.bin/supabase"
setup_sql="$repo_root/supabase/tests/trash_retention_policy_concurrency_setup.sql"
session_a_sql="$repo_root/supabase/tests/trash_retention_policy_concurrency_session_a.sql"
projection_a_sql="$repo_root/supabase/tests/trash_retention_attention_concurrency_session_a.sql"
project_id="$(awk -F'"' '/^project_id = / { print $2; exit }' "$repo_root/supabase/config.toml")"
result_file="$(mktemp -t trash-retention-race.XXXXXX)"
projection_result_file="$(mktemp -t trash-retention-projection-race.XXXXXX)"
session_a_pid=""
projection_a_pid=""

cleanup() {
  if [ -n "$session_a_pid" ] && kill -0 "$session_a_pid" 2>/dev/null; then
    kill "$session_a_pid" 2>/dev/null || true
    wait "$session_a_pid" 2>/dev/null || true
  fi
  if [ -n "$projection_a_pid" ] && kill -0 "$projection_a_pid" 2>/dev/null; then
    kill "$projection_a_pid" 2>/dev/null || true
    wait "$projection_a_pid" 2>/dev/null || true
  fi
  rm -f "$result_file" "$projection_result_file"
}
trap cleanup EXIT

"$cli" db reset --local --no-seed
db_container="$(docker ps --filter "name=^/supabase_db_${project_id}$" --format '{{.ID}}' | head -n 1)"
if [ -z "$db_container" ]; then
  echo "could not resolve the local Supabase Postgres container" >&2
  exit 1
fi
docker exec -i "$db_container" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres <"$setup_sql"

docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres <"$session_a_sql" >"$result_file" &
session_a_pid=$!
ready_sql="SELECT NOT pg_try_advisory_lock(hashtextextended('trash-retention-policy-race-ready',90));"
for _ in $(seq 1 100); do
  if docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "$ready_sql" | grep -qx 't'; then break; fi
  sleep 0.05
done
if ! docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "$ready_sql" | grep -qx 't'; then
  echo "policy session did not enter its locked transaction" >&2
  exit 1
fi

trash_result="$(docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "BEGIN; SET LOCAL statement_timeout='5s'; SELECT set_config('request.jwt.claim.role','authenticated',true); SELECT set_config('request.jwt.claim.sub','91100000-0000-0000-0000-000000000001',true); SELECT code FROM public.trash_resource('document','91400000-0000-0000-0000-000000000001','retention.race.trash'); COMMIT;" | tail -n 1)"
wait "$session_a_pid"
session_a_pid=""
if [ "$trash_result" != "trashed" ]; then
  echo "concurrent Trash command failed: $trash_result" >&2
  exit 1
fi

snapshot="$(docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "SELECT retention_days||':'||retention_policy_version||':'||(auto_purge_at=created_at+interval '30 days') FROM public.trash_operations WHERE idempotency_key='retention.race.trash';")"
if [ "$snapshot" != "30:2:true" ]; then
  echo "Trash command observed an inconsistent policy snapshot: $snapshot" >&2
  exit 1
fi
if ! grep -qx 'updated' "$result_file"; then
  echo "concurrent policy update did not complete" >&2
  exit 1
fi

docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "UPDATE public.trash_operations SET purge_eligible_at=now()+interval '23 hours',auto_purge_at=now()+interval '23 hours' WHERE idempotency_key='retention.race.trash';"
docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres <"$projection_a_sql" >"$projection_result_file" &
projection_a_pid=$!
projection_ready_sql="SELECT NOT pg_try_advisory_lock(hashtextextended('trash-retention-attention-race-ready',90));"
for _ in $(seq 1 100); do
  if docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "$projection_ready_sql" | grep -qx 't'; then break; fi
  sleep 0.05
done
if ! docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "$projection_ready_sql" | grep -qx 't'; then
  echo "first attention projector did not enter its locked transaction" >&2
  exit 1
fi
projection_b="$(docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "SELECT projected_count||':'||already_projected_count FROM public.project_due_trash_retention_team_attention(100);")"
wait "$projection_a_pid"
projection_a_pid=""
projection_count="$(docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "SELECT count(*) FROM public.trash_retention_team_attention_items item JOIN public.trash_operations operation ON operation.id=item.operation_id AND operation.org_id=item.org_id WHERE operation.idempotency_key='retention.race.trash';")"
if ! grep -qx '1:0' "$projection_result_file" || [ "$projection_b" != "0:0" ] || [ "$projection_count" != "1" ]; then
  echo "concurrent attention projectors did not preserve one durable item: first=$(tr '\n' ',' <"$projection_result_file") second=$projection_b count=$projection_count" >&2
  exit 1
fi

echo "PASS: policy/Trash locking is consistent and concurrent attention projection creates exactly one item."
