#!/usr/bin/env bash
set -euo pipefail

db_container="${SUPABASE_DB_CONTAINER:-supabase_db_dms}"
test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
result_dir="$(mktemp -d)"
trap 'rm -rf "$result_dir"' EXIT
db_psql() { docker exec "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }

docker exec -i "$db_container" psql -X -q -U postgres -d postgres -v ON_ERROR_STOP=1 < "$test_dir/client_mutation_membership_change_concurrency_setup.sql"
db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='bc000000-0000-0000-0000-000000000002'; SELECT code FROM public.create_client_command('Race client','','','bc300000-0000-0000-0000-000000000001'); SELECT pg_sleep(2); COMMIT;" > "$result_dir/create" &
create_pid=$!
sleep 0.2
started_at="$(date +%s)"
db_psql -c "UPDATE public.organisation_memberships SET state='suspended',suspended_at=now(),suspended_by='bc000000-0000-0000-0000-000000000001',suspension_reason='fixture' WHERE id='bc110000-0000-0000-0000-000000000002';" > "$result_dir/suspend"
elapsed="$(( $(date +%s) - started_at ))"
wait "$create_pid"

rg -q '^ok$' "$result_dir/create"
[[ "$elapsed" -ge 1 ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.clients WHERE org_id='bc100000-0000-0000-0000-000000000001' AND name='Race client';")" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.activity_logs WHERE org_id='bc100000-0000-0000-0000-000000000001' AND action='client_created';")" == '1' ]]
[[ "$(db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='bc000000-0000-0000-0000-000000000002'; SELECT code FROM public.create_client_command('Later client','','','bc300000-0000-0000-0000-000000000002'); ROLLBACK;")" == 'not_allowed' ]]

echo 'Membership suspension waited for one atomic client creation, then denied subsequent mutation.'
