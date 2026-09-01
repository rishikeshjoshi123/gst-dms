#!/usr/bin/env bash
set -euo pipefail

db_container="${SUPABASE_DB_CONTAINER:-supabase_db_dms}"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

db_psql() {
  docker exec -i "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"
}

db_psql < "$(dirname "$0")/task_legacy_note_action_item_backfill_concurrency_setup.sql"

run_backfill() {
  local pause="$1"
  db_psql -c "
    BEGIN;
    SET LOCAL ROLE service_role;
    SELECT disposition || ':' || result_count::text
    FROM public.backfill_legacy_note_action_items('11700000-0000-0000-0000-000000000001', 1);
    SELECT pg_sleep($pause);
    COMMIT;"
}

run_backfill 2 > "$temp_dir/first" &
first_pid=$!
sleep 0.2
run_backfill 0 > "$temp_dir/second"
wait "$first_pid"

rg -q '^migrated:1$' "$temp_dir/first"
[[ ! -s "$temp_dir/second" ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.tasks WHERE origin_note_id='11a00000-0000-0000-0000-000000000001';")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.task_legacy_note_backfill_diagnostics WHERE source_note_id='11a00000-0000-0000-0000-000000000001' AND disposition='migrated';")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.activity_projector_outbox_events AS outbox JOIN public.activity_events AS event ON event.id=outbox.activity_event_id WHERE event.org_id='11700000-0000-0000-0000-000000000001' AND outbox.org_id='11700000-0000-0000-0000-000000000001' AND event.event_type='task.created' AND event.actor_kind='system' AND event.subject_id=(SELECT task_id FROM public.task_legacy_note_backfill_diagnostics WHERE source_org_id='11700000-0000-0000-0000-000000000001' AND source_note_id='11a00000-0000-0000-0000-000000000001');")" == '1' ]]

echo 'Legacy action-item backfill concurrent runs produced one Task, disposition, and Activity outbox event.'
