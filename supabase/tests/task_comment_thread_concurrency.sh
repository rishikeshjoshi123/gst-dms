#!/usr/bin/env bash
set -euo pipefail
db_container="${SUPABASE_DB_CONTAINER:-supabase_db_dms}"
task_tmp_dir="$(mktemp -d)"
trap 'rm -rf "$task_tmp_dir"' EXIT
db_psql() { docker exec "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
post() {
  local actor="$1" key="$2" body="$3" out="$4"
  db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='$actor'; SELECT code || ':' || sequence FROM public.post_task_comment('c1500000-0000-0000-0000-000000000001','$body','$key'); COMMIT;" > "$out"
}
post 'c1000000-0000-0000-0000-000000000001' 'c1600000-0000-0000-0000-000000000001' 'first concurrent' "$task_tmp_dir/one" &
first_pid=$!
post 'c1000000-0000-0000-0000-000000000002' 'c1600000-0000-0000-0000-000000000002' 'second concurrent' "$task_tmp_dir/two" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
rg -q '^ok:[12]$' "$task_tmp_dir/one"
rg -q '^ok:[12]$' "$task_tmp_dir/two"
[[ "$(sort "$task_tmp_dir/one" "$task_tmp_dir/two" | tr '\n' ' ')" == 'ok:1 ok:2 ' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.task_comments WHERE task_id='c1500000-0000-0000-0000-000000000001';")" == '2' ]]
[[ "$(db_psql -c "SELECT next_sequence FROM public.task_comment_threads WHERE task_id='c1500000-0000-0000-0000-000000000001';")" == '3' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.activity_events WHERE subject_id='c1500000-0000-0000-0000-000000000001' AND event_type='task.comment_posted';")" == '2' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.activity_projector_outbox_events AS outbox JOIN public.activity_events AS event ON event.id=outbox.activity_event_id WHERE event.subject_id='c1500000-0000-0000-0000-000000000001' AND event.event_type='task.comment_posted';")" == '2' ]]
echo 'Concurrent Task comment posts produced one thread and monotonic sequences.'
