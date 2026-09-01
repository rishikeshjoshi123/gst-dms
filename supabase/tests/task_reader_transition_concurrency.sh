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
    SET LOCAL \"request.jwt.claim.sub\"='b1000000-0000-0000-0000-000000000001';
    SELECT code || ':' || revision::text || ':' || replayed::text
    FROM public.transition_task(
      'b1500000-0000-0000-0000-000000000001','start',1,
      'b1600000-0000-0000-0000-000000000001');
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

rg -q '^ok:2:false$' "$temp_dir/first"
rg -q '^ok:2:true$' "$temp_dir/second"
[[ "$elapsed" -ge 1 ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.task_transition_history WHERE task_id='b1500000-0000-0000-0000-000000000001';")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.task_transition_receipts WHERE task_id='b1500000-0000-0000-0000-000000000001';")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.activity_events WHERE subject_id='b1500000-0000-0000-0000-000000000001' AND event_type='task.transitioned';")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.activity_projector_outbox_events AS outbox JOIN public.activity_events AS event ON event.id=outbox.activity_event_id WHERE event.subject_id='b1500000-0000-0000-0000-000000000001' AND event.event_type='task.transitioned';")" == '1' ]]
[[ "$(db_psql -c "SELECT revision::text || ':' || status::text FROM public.tasks WHERE id='b1500000-0000-0000-0000-000000000001';")" == '2:in_progress' ]]

echo 'Task transition same-key concurrency passed with one durable revision and receipt.'
