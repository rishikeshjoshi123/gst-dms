#!/usr/bin/env bash
set -euo pipefail

operation_id="$1"
db_container="${SUPABASE_DB_CONTAINER:-supabase_db_dms}"

db_psql() {
  docker exec "$db_container" psql -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"
}

db_psql -c "SELECT set_config('request.jwt.claim.role','authenticated',false); SELECT set_config('request.jwt.claim.sub','88100000-0000-0000-0000-000000000010',false); SELECT code FROM public.restore_trash_operation('$operation_id','restore.fixture.concurrent');" > /private/tmp/casechain-restore-a.log &
first_pid=$!
db_psql -c "SELECT set_config('request.jwt.claim.role','authenticated',false); SELECT set_config('request.jwt.claim.sub','88100000-0000-0000-0000-000000000010',false); SELECT code FROM public.restore_trash_operation('$operation_id','restore.fixture.concurrent');" > /private/tmp/casechain-restore-b.log &
second_pid=$!
wait "$first_pid"
wait "$second_pid"

grep -q restored /private/tmp/casechain-restore-a.log
grep -q restored /private/tmp/casechain-restore-b.log
test "$(db_psql -Atc "SELECT count(*) FROM public.trash_restore_receipts WHERE operation_id='$operation_id'")" = "1"
