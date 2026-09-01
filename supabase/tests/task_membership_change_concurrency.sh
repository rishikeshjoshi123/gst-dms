#!/usr/bin/env bash
set -euo pipefail
db_container="${SUPABASE_DB_CONTAINER:-supabase_db_dms}"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
db_psql() { docker exec "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }

db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='e1000000-0000-0000-0000-000000000002'; SELECT code FROM public.transition_task('e1500000-0000-0000-0000-000000000001','start',1,'e1600000-0000-0000-0000-000000000001'); SELECT pg_sleep(2); COMMIT;" > "$temp_dir/transition" &
transition_pid=$!
sleep 0.2
started_at="$(date +%s)"
db_psql -c "UPDATE public.organisation_memberships SET state='suspended',suspended_at=now(),suspended_by='e1000000-0000-0000-0000-000000000001',suspension_reason='fixture' WHERE id='e1110000-0000-0000-0000-000000000002';" > "$temp_dir/suspend"
elapsed="$(( $(date +%s) - started_at ))"
wait "$transition_pid"
rg -q '^ok$' "$temp_dir/transition"
[[ "$elapsed" -ge 1 ]]
[[ "$(db_psql -c "SELECT state::text FROM public.organisation_memberships WHERE id='e1110000-0000-0000-0000-000000000002';")" == 'suspended' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.activity_events WHERE subject_id='e1500000-0000-0000-0000-000000000001' AND event_type='task.transitioned';")" == '1' ]]
[[ "$(db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='e1000000-0000-0000-0000-000000000002'; SELECT code FROM public.transition_task('e1500000-0000-0000-0000-000000000001','complete',2,'e1600000-0000-0000-0000-000000000002'); ROLLBACK;")" == 'not_allowed' ]]
echo 'Membership suspension waited for one atomic Task transition, then denied subsequent mutation.'
