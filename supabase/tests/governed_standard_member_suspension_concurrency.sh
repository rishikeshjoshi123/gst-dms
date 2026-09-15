#!/usr/bin/env bash
set -euo pipefail
container="${SUPABASE_DB_CONTAINER:?SUPABASE_DB_CONTAINER is required}"
target_membership="$(docker exec "$container" psql -XAt -U postgres -d postgres -c "select id from public.organisation_memberships where user_id='a0010000-0000-0000-0000-000000000006' and state='active'")"
target_revision="$(docker exec "$container" psql -XAt -U postgres -d postgres -c "select revision from public.organisation_memberships where id='$target_membership'")"
target_fingerprint="$(docker exec "$container" psql -XAt -U postgres -d postgres -c "set role authenticated; select set_config('request.jwt.claim.role','authenticated',false); select set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000001',false); select task_impact_fingerprint from public.get_standard_member_suspension_impact('$target_membership')" | tail -1)"

docker exec "$container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -c "begin; set local role authenticated; select set_config('request.jwt.claim.role','authenticated',true); select set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000006',true); select * from public.transition_task('16100000-0000-4000-8000-000000000021','start',1,'16120000-0000-4000-8000-000000000021'); select pg_sleep(3); commit;" >/tmp/casechain-target-mutation.out &
target_pid=$!
sleep 0.4
docker exec "$container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -c "begin; set local role authenticated; select set_config('request.jwt.claim.role','authenticated',true); select set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000001',true); select * from public.suspend_standard_organisation_member('$target_membership',$target_revision,'Concurrent access review','return_open_tasks_to_team','$target_fingerprint','16120000-0000-4000-8000-000000000022'); commit;" >/tmp/casechain-suspension.out &
suspend_pid=$!
wait "$target_pid"
wait "$suspend_pid"

if ! grep -q 'impact_conflict' /tmp/casechain-suspension.out; then
  echo "Concurrent target mutation did not invalidate the preview" >&2
  cat /tmp/casechain-suspension.out >&2
  exit 1
fi
fresh_revision="$(docker exec "$container" psql -XAt -U postgres -d postgres -c "select revision from public.organisation_memberships where id='$target_membership'")"
fresh_fingerprint="$(docker exec "$container" psql -XAt -U postgres -d postgres -c "set role authenticated; select set_config('request.jwt.claim.role','authenticated',false); select set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000001',false); select task_impact_fingerprint from public.get_standard_member_suspension_impact('$target_membership')" | tail -1)"
docker exec "$container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -c "begin; set local role authenticated; select set_config('request.jwt.claim.role','authenticated',true); select set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000001',true); select * from public.suspend_standard_organisation_member('$target_membership',$fresh_revision,'Concurrent access review retry','return_open_tasks_to_team','$fresh_fingerprint','16120000-0000-4000-8000-000000000025'); commit;" >/tmp/casechain-suspension-retry.out

result="$(docker exec "$container" psql -XAt -U postgres -d postgres -c "select m.state||':'||t.status||':'||coalesce(t.assignee_user_id::text,'unassigned')||':'||t.revision||':'||(select count(*) from public.task_transition_history h where h.task_id=t.id) from public.organisation_memberships m cross join public.tasks t where m.id='$target_membership' and t.id='16100000-0000-4000-8000-000000000021'")"
if [[ "$result" != "suspended:in_progress:unassigned:3:2" ]]; then
  echo "Unexpected concurrent result: $result" >&2
  exit 1
fi
echo "Concurrent target mutation invalidated stale impact; a fresh preview then returned the revised in-progress Task atomically."

# Inverse direction: suspension owns the Viewer membership fence before a
# different Admin attempts to assign them. The Admin must receive a controlled
# invalid_assignee result after suspension, never a raw deadlock.
inverse_membership="$(docker exec "$container" psql -XAt -U postgres -d postgres -c "select id from public.organisation_memberships where user_id='a0010000-0000-0000-0000-000000000002' and state='active'")"
inverse_revision="$(docker exec "$container" psql -XAt -U postgres -d postgres -c "select revision from public.organisation_memberships where id='$inverse_membership'")"
inverse_fingerprint="$(docker exec "$container" psql -XAt -U postgres -d postgres -c "set role authenticated; select set_config('request.jwt.claim.role','authenticated',false); select set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000001',false); select task_impact_fingerprint from public.get_standard_member_suspension_impact('$inverse_membership')" | tail -1)"
docker exec "$container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -c "begin; set local statement_timeout='8s'; set local role authenticated; select set_config('request.jwt.claim.role','authenticated',true); select set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000001',true); select * from public.suspend_standard_organisation_member('$inverse_membership',$inverse_revision,'Inverse concurrent review','return_open_tasks_to_team','$inverse_fingerprint','16120000-0000-4000-8000-000000000023'); commit;" >/tmp/casechain-inverse-suspension.out &
inverse_suspend_pid=$!
sleep 0.05
docker exec "$container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -c "begin; set local statement_timeout='8s'; set local role authenticated; select set_config('request.jwt.claim.role','authenticated',true); select set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000004',true); select * from public.transition_task('16100000-0000-4000-8000-000000000022',' set_assignee ',1,'16120000-0000-4000-8000-000000000024','a0010000-0000-0000-0000-000000000002',NULL); commit;" >/tmp/casechain-inverse-assignment.out &
inverse_assign_pid=$!
wait "$inverse_suspend_pid"
wait "$inverse_assign_pid"
if ! grep -q 'invalid_assignee' /tmp/casechain-inverse-assignment.out; then
  echo "Inverse assignment did not return invalid_assignee" >&2
  cat /tmp/casechain-inverse-assignment.out >&2
  exit 1
fi
inverse_result="$(docker exec "$container" psql -XAt -U postgres -d postgres -c "select m.state||':'||coalesce(t.assignee_user_id::text,'unassigned')||':'||t.revision from public.organisation_memberships m cross join public.tasks t where m.id='$inverse_membership' and t.id='16100000-0000-4000-8000-000000000022'")"
if [[ "$inverse_result" != "suspended:unassigned:1" ]]; then
  echo "Unexpected inverse result: $inverse_result" >&2
  exit 1
fi
echo "Inverse Admin assignment returned invalid_assignee after the suspension fence; no deadlock and no Task remained assigned."
