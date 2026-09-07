#!/usr/bin/env bash
set -euo pipefail

db_container="${SUPABASE_DB_CONTAINER:-supabase_db_dms}"
test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
result_dir="$(mktemp -d)"
db_psql() { docker exec "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
trap 'rm -rf "$result_dir"' EXIT

docker exec -i "$db_container" psql -X -q -U postgres -d postgres -v ON_ERROR_STOP=1 < "$test_dir/note_removal_membership_change_concurrency_setup.sql"

db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='ba000000-0000-0000-0000-000000000002'; SELECT code FROM public.remove_case_note('ba400000-0000-0000-0000-000000000001',NULL); SELECT pg_sleep(2); COMMIT;" > "$result_dir/removal" &
removal_pid=$!
sleep 0.2
started_at="$(date +%s)"
db_psql -c "UPDATE public.organisation_memberships SET state='suspended',suspended_at=now(),suspended_by='ba000000-0000-0000-0000-000000000001',suspension_reason='fixture' WHERE id='ba110000-0000-0000-0000-000000000002';" > "$result_dir/suspend"
elapsed="$(( $(date +%s) - started_at ))"
wait "$removal_pid"

rg -q '^ok$' "$result_dir/removal"
[[ "$elapsed" -ge 1 ]]
[[ "$(db_psql -c "SELECT state::text FROM public.organisation_memberships WHERE id='ba110000-0000-0000-0000-000000000002';")" == 'suspended' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.case_notes WHERE id='ba400000-0000-0000-0000-000000000001' AND deleted_by='ba000000-0000-0000-0000-000000000002' AND deletion_kind='author';")" == '1' ]]
[[ "$(db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='ba000000-0000-0000-0000-000000000002'; SELECT code FROM public.remove_case_note('ba400000-0000-0000-0000-000000000001',NULL); ROLLBACK;")" == 'not_allowed' ]]

echo 'Membership suspension waited for one atomic note removal, then denied subsequent mutation.'
