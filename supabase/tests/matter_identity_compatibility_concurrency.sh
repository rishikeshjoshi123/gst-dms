#!/usr/bin/env bash
set -euo pipefail

db_container="${SUPABASE_DB_CONTAINER:?local database container is required}"
result_dir="$(mktemp -d)"
trap 'rm -rf "$result_dir"' EXIT

db_psql() {
  docker exec "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"
}

create_matter() {
  local actor="$1" title="$2" key="$3" output="$4"
  db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='$actor'; SELECT code || ':' || matter_id::text FROM public.create_matter_command('c1481000-0000-0000-0000-000000000001','$title','2027-28','','active'::public.matter_work_state,'adjudication'::public.matter_current_forum,'$key'); COMMIT;" > "$output"
}

create_matter \
  'a1481000-0000-0000-0000-000000000001' \
  'Concurrent owner proceeding' \
  '14810000-0000-0000-0000-000000000001' \
  "$result_dir/owner" &
owner_pid=$!
create_matter \
  'a1481000-0000-0000-0000-000000000002' \
  'Concurrent associate proceeding' \
  '14810000-0000-0000-0000-000000000002' \
  "$result_dir/associate" &
associate_pid=$!
wait "$owner_pid"
wait "$associate_pid"

rg -q '^ok:[0-9a-f-]{36}$' "$result_dir/owner"
rg -q '^ok:[0-9a-f-]{36}$' "$result_dir/associate"

[[ "$(db_psql -c "SELECT count(*) FROM public.matters WHERE org_id='b1481000-0000-0000-0000-000000000001' AND client_id='c1481000-0000-0000-0000-000000000001' AND financial_year='2027-28';")" == '2' ]]
[[ "$(db_psql -c "SELECT count(DISTINCT id)::text || ':' || count(DISTINCT matter_code)::text FROM public.matters WHERE org_id='b1481000-0000-0000-0000-000000000001' AND client_id='c1481000-0000-0000-0000-000000000001' AND financial_year='2027-28';")" == '2:2' ]]
[[ "$(db_psql -c "SELECT array_agg(matter_code ORDER BY matter_code)::text FROM public.matters WHERE org_id='b1481000-0000-0000-0000-000000000001';")" == '{RCC-2728-01,RCC-2728-02}' ]]

for key in \
  '14810000-0000-0000-0000-000000000001' \
  '14810000-0000-0000-0000-000000000002'; do
  [[ "$(db_psql -c "SELECT count(*) FROM public.matter_command_receipts WHERE idempotency_key='$key';")" == '1' ]]
  [[ "$(db_psql -c "SELECT count(*) FROM public.activity_events WHERE idempotency_key='$key' AND event_type='matter.profile_updated';")" == '1' ]]
  [[ "$(db_psql -c "SELECT count(*) FROM public.activity_projector_outbox_events AS outbox JOIN public.activity_events AS event ON event.id=outbox.activity_event_id WHERE event.idempotency_key='$key' AND event.event_type='matter.profile_updated';")" == '1' ]]
done

[[ "$(db_psql -c "SELECT count(*) FROM public.activity_logs WHERE org_id='b1481000-0000-0000-0000-000000000001' AND action='matter_created';")" == '2' ]]
echo 'Concurrent same-client/year creates produced distinct Matters/codes and one receipt/Activity chain each.'
