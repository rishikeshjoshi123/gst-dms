#!/usr/bin/env bash
set -euo pipefail
db_container="${SUPABASE_DB_CONTAINER:-supabase_db_dms}"
task_tmp_dir="$(mktemp -d)"
trap 'rm -rf "$task_tmp_dir"' EXIT
db_psql() { docker exec "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='d1000000-0000-0000-0000-000000000002'; SELECT code FROM public.post_task_comment('d1500000-0000-0000-0000-000000000001','post before trash','d1600000-0000-0000-0000-000000000001'); SELECT pg_sleep(2); COMMIT;" > "$task_tmp_dir/post" &
post_pid=$!
sleep 0.2
started_at="$(date +%s)"
db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='d1000000-0000-0000-0000-000000000001'; SELECT code FROM public.trash_resource('matter','d1300000-0000-0000-0000-000000000001','task.comment.trash'); COMMIT;" > "$task_tmp_dir/trash"
elapsed="$(( $(date +%s) - started_at ))"
wait "$post_pid"
rg -q '^ok$' "$task_tmp_dir/post"
rg -q '^trashed$' "$task_tmp_dir/trash"
[[ "$elapsed" -ge 1 ]]
[[ "$(db_psql -c "SELECT record_state::text FROM public.matters WHERE id='d1300000-0000-0000-0000-000000000001';")" == 'trashed' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.task_comments WHERE task_id='d1500000-0000-0000-0000-000000000001';")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.activity_events WHERE subject_id='d1500000-0000-0000-0000-000000000001' AND event_type='task.comment_posted';")" == '1' ]]
[[ "$(db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='d1000000-0000-0000-0000-000000000002'; SELECT code FROM public.post_task_comment('d1500000-0000-0000-0000-000000000001','post after trash','d1600000-0000-0000-0000-000000000002'); ROLLBACK;")" == 'context_unavailable' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.task_comments WHERE task_id='d1500000-0000-0000-0000-000000000001';")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.activity_projector_outbox_events AS outbox JOIN public.activity_events AS event ON event.id=outbox.activity_event_id WHERE event.subject_id='d1500000-0000-0000-0000-000000000001' AND event.event_type='task.comment_posted';")" == '1' ]]
echo 'Matter Trash waited for the in-flight comment, then fenced all later comment/Activity/outbox writes.'
