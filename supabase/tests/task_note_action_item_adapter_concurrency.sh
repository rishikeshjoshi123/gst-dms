#!/usr/bin/env bash
set -euo pipefail

db_container="${SUPABASE_DB_CONTAINER:-supabase_db_dms}"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

db_psql() {
  docker exec "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"
}

run_command() {
  local pause="$1"
  db_psql -c "
    BEGIN;
    SET LOCAL ROLE authenticated;
    SET LOCAL \"request.jwt.claim.role\"='authenticated';
    SET LOCAL \"request.jwt.claim.sub\"='95600000-0000-0000-0000-000000000001';
    SELECT code || ':' || replayed::text
    FROM public.create_note_with_optional_task(
      '95900000-0000-0000-0000-000000000001','Concurrent action item','general',true,
      '96000000-0000-0000-0000-000000000001');
    SELECT pg_sleep($pause);
    COMMIT;"
}

run_command 2 > "$temp_dir/first" &
first_pid=$!
sleep 0.2
started_at="$(date +%s)"
run_command 0 > "$temp_dir/second"
elapsed="$(( $(date +%s) - started_at ))"
wait "$first_pid"

rg -q '^ok:false$' "$temp_dir/first"
rg -q '^ok:true$' "$temp_dir/second"
[[ "$elapsed" -ge 1 ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.tasks WHERE org_id='95700000-0000-0000-0000-000000000001' AND origin_note_id=(SELECT note_id FROM public.task_command_receipts WHERE idempotency_key='96000000-0000-0000-0000-000000000001');")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.activity_projector_outbox_events outbox JOIN public.activity_events event ON event.id=outbox.activity_event_id WHERE event.org_id='95700000-0000-0000-0000-000000000001' AND event.event_type='task.created' AND event.subject_type='task' AND event.subject_id=(SELECT task_id FROM public.task_command_receipts WHERE idempotency_key='96000000-0000-0000-0000-000000000001');")" == '1' ]]

echo 'Task note-adapter same-key concurrency passed with one durable Task and Activity outbox event.'
