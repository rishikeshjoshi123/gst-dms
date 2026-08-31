#!/usr/bin/env bash
# Verifies duplicate workers use SKIP LOCKED and Restore loses safely once the
# durable purge claim has fenced the root lifecycle.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
db_container="${SUPABASE_DB_CONTAINER:-supabase_db_dms}"
setup_sql="$repo_root/supabase/tests/root_operation_permanent_delete_concurrency_setup.sql"
session_a_sql="$repo_root/supabase/tests/root_operation_permanent_delete_concurrency_session_a.sql"
blocker_writer_sql="$repo_root/supabase/tests/root_operation_permanent_delete_concurrency_blocker_writer.sql"
blocker_setup_sql="$repo_root/supabase/tests/root_operation_permanent_delete_concurrency_blocker_setup.sql"
temp_dir="$(mktemp -d)"
session_a_pid=""

cleanup() {
  if [[ -n "$session_a_pid" ]] && kill -0 "$session_a_pid" 2>/dev/null; then
    kill "$session_a_pid" 2>/dev/null || true
    wait "$session_a_pid" 2>/dev/null || true
  fi
  rm -rf "$temp_dir"
}
trap cleanup EXIT

db_psql() {
  docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres "$@"
}

fixture="$(db_psql <"$setup_sql" | tail -n 1)"
IFS='|' read -r operation_id owner_id document_id blocker_document_id <<<"$fixture"
[[ -n "$operation_id" && -n "$owner_id" && -n "$document_id" && -n "$blocker_document_id" ]]

db_psql -v operation_id="$operation_id" <"$session_a_sql" >"$temp_dir/session-a" &
session_a_pid=$!
ready_sql="SELECT NOT pg_try_advisory_lock(hashtextextended('root-operation-purge-race-ready',91));"
for _ in $(seq 1 100); do
  if db_psql -c "$ready_sql" | rg -qx 't'; then break; fi
  sleep 0.05
done
db_psql -c "$ready_sql" | rg -qx 't'

# The locked queued row is invisible to a duplicate claimant.
duplicate_claim="$(db_psql -c "SELECT count(*) FROM public.claim_trash_purge_work(50,120) WHERE operation_id='$operation_id';")"
[[ "$duplicate_claim" == '0' ]]

started_at="$(date +%s)"
db_psql -c "BEGIN; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='$owner_id'; SELECT code FROM public.restore_trash_operation('$operation_id','purge.concurrent.restore'); COMMIT;" >"$temp_dir/restore" &
restore_pid=$!
wait "$session_a_pid"
session_a_pid=""
wait "$restore_pid"
elapsed="$(( $(date +%s) - started_at ))"
rg -qx 'not_available' "$temp_dir/restore"
(( elapsed >= 1 ))

job_lease="$(rg '^[0-9a-f-]+\|[0-9a-f-]+$' "$temp_dir/session-a" | tail -n 1)"
IFS='|' read -r job_id lease_token <<<"$job_lease"
[[ -n "$job_id" && -n "$lease_token" ]]
prepare_code="$(db_psql -c "SELECT code FROM public.prepare_trash_purge_database('$job_id','$lease_token');")"
[[ "$prepare_code" == 'prepared' ]]
finish_code="$(db_psql -c "SELECT code FROM public.finish_trash_purge_attempt('$job_id','$lease_token');")"
[[ "$finish_code" == 'purged' ]]
terminal="$(db_psql -c "SELECT operation.state||':'||document.record_state FROM public.trash_operations operation JOIN public.documents document ON document.id='$document_id' WHERE operation.id='$operation_id';")"
[[ "$terminal" == 'purged:purged' ]]

# A dependency writer that starts after claim but wins the preparation mutex
# must commit before preparation proceeds; preparation then blocks without
# deleting content or the dependency record.
blocker_operation_id="$(db_psql -v owner_id="$owner_id" -v document_id="$blocker_document_id" <"$blocker_setup_sql" | tail -n 1)"
[[ -n "$blocker_operation_id" ]]
blocker_job_lease="$(db_psql -c "SELECT job_id||'|'||lease_token FROM public.claim_trash_purge_work(50,120) WHERE operation_id='$blocker_operation_id';")"
IFS='|' read -r blocker_job_id blocker_lease_token <<<"$blocker_job_lease"
[[ -n "$blocker_job_id" && -n "$blocker_lease_token" ]]
db_psql -v operation_id="$blocker_operation_id" -v document_id="$blocker_document_id" <"$blocker_writer_sql" >"$temp_dir/blocker-writer" &
session_a_pid=$!
blocker_ready_sql="SELECT NOT pg_try_advisory_lock(hashtextextended('root-operation-purge-blocker-ready',91));"
for _ in $(seq 1 100); do
  if db_psql -c "$blocker_ready_sql" | rg -qx 't'; then break; fi
  sleep 0.05
done
db_psql -c "$blocker_ready_sql" | rg -qx 't'
started_at="$(date +%s)"
blocked_prepare="$(db_psql -c "SELECT code FROM public.prepare_trash_purge_database('$blocker_job_id','$blocker_lease_token');")"
wait "$session_a_pid"
session_a_pid=""
elapsed="$(( $(date +%s) - started_at ))"
[[ "$blocked_prepare" == 'blocked' ]]
(( elapsed >= 1 ))
blocked_terminal="$(db_psql -c "SELECT operation.state||':'||job.state||':'||document.display_title||':'||(SELECT count(*) FROM public.trash_purge_blockers blocker WHERE blocker.operation_id=operation.id AND blocker.state='active') FROM public.trash_operations operation JOIN public.trash_purge_jobs job ON job.operation_id=operation.id JOIN public.documents document ON document.id='$blocker_document_id' WHERE operation.id='$blocker_operation_id';")"
[[ "$blocked_terminal" == 'purge_failed:blocked:Blocker race document:1' ]]

echo 'PASS: claim fenced Restore, duplicate workers skipped locked work, and a post-claim blocker atomically prevented preparation without cleanup.'
