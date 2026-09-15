#!/usr/bin/env bash
set -euo pipefail
container="${SUPABASE_DB_CONTAINER:?SUPABASE_DB_CONTAINER is required}"
target_membership="$(docker exec "$container" psql -XAt -U postgres -d postgres -c "select id from public.organisation_memberships where user_id='a0010000-0000-0000-0000-000000000006' and state='active'")"
target_revision="$(docker exec "$container" psql -XAt -U postgres -d postgres -c "select revision from public.organisation_memberships where id='$target_membership'")"

docker exec "$container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -c "begin; set local role authenticated; select set_config('request.jwt.claim.role','authenticated',true); select set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000006',true); select * from public.transition_task('16100000-0000-4000-8000-000000000021','start',1,'16120000-0000-4000-8000-000000000021'); select pg_sleep(3); commit;" >/tmp/casechain-target-mutation.out &
target_pid=$!
sleep 0.4
docker exec "$container" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres -c "begin; set local role authenticated; select set_config('request.jwt.claim.role','authenticated',true); select set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000001',true); select * from public.suspend_standard_organisation_member('$target_membership',$target_revision,'Concurrent access review','return_open_tasks_to_team','16120000-0000-4000-8000-000000000022'); commit;" >/tmp/casechain-suspension.out &
suspend_pid=$!
wait "$target_pid"
wait "$suspend_pid"

result="$(docker exec "$container" psql -XAt -U postgres -d postgres -c "select m.state||':'||t.status||':'||coalesce(t.assignee_user_id::text,'unassigned')||':'||t.revision||':'||(select count(*) from public.task_transition_history h where h.task_id=t.id) from public.organisation_memberships m cross join public.tasks t where m.id='$target_membership' and t.id='16100000-0000-4000-8000-000000000021'")"
if [[ "$result" != "suspended:in_progress:unassigned:3:2" ]]; then
  echo "Unexpected concurrent result: $result" >&2
  exit 1
fi
echo "Concurrent target mutation committed before suspension; suspension then returned the revised in-progress Task atomically."
