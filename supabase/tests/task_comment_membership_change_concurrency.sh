#!/usr/bin/env bash
set -euo pipefail
db_container="${SUPABASE_DB_CONTAINER:-supabase_db_dms}"
task_tmp_dir="$(mktemp -d)"
trap 'rm -rf "$task_tmp_dir"' EXIT
db_psql() { docker exec "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='f1000000-0000-0000-0000-000000000002'; SELECT code FROM public.post_task_comment('f1500000-0000-0000-0000-000000000001','membership-locked post','f1600000-0000-0000-0000-000000000001'); SELECT pg_sleep(2); COMMIT;" > "$task_tmp_dir/post" &
post_pid=$!
sleep 0.2
started_at="$(date +%s)"
db_psql -c "UPDATE public.organisation_memberships SET state='suspended',suspended_at=now(),suspended_by='f1000000-0000-0000-0000-000000000001',suspension_reason='fixture' WHERE id='f1110000-0000-0000-0000-000000000002';" > "$task_tmp_dir/suspend"
elapsed="$(( $(date +%s) - started_at ))"
wait "$post_pid"
rg -q '^ok$' "$task_tmp_dir/post"
[[ "$elapsed" -ge 1 ]]
[[ "$(db_psql -c "SELECT state::text FROM public.organisation_memberships WHERE id='f1110000-0000-0000-0000-000000000002';")" == 'suspended' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.task_comments WHERE task_id='f1500000-0000-0000-0000-000000000001';")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.activity_events WHERE subject_id='f1500000-0000-0000-0000-000000000001' AND event_type='task.comment_posted';")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.activity_projector_outbox_events AS outbox JOIN public.activity_events AS event ON event.id=outbox.activity_event_id WHERE event.subject_id='f1500000-0000-0000-0000-000000000001' AND event.event_type='task.comment_posted';")" == '1' ]]
[[ "$(db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='f1000000-0000-0000-0000-000000000002'; SELECT code FROM public.post_task_comment('f1500000-0000-0000-0000-000000000001','denied after suspension','f1600000-0000-0000-0000-000000000002'); ROLLBACK;")" == 'not_allowed' ]]
echo 'Membership suspension waited for one atomic Task comment/Activity/outbox write, then denied later comment mutation.'
