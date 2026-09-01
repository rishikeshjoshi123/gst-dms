#!/usr/bin/env bash
set -euo pipefail

db_container="${SUPABASE_DB_CONTAINER:-supabase_db_dms}"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

db_psql() {
  docker exec "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"
}

accept_invite() {
  local invite_id="$1"
  local idempotency_key="$2"
  db_psql -c "
    BEGIN;
    SET LOCAL ROLE authenticated;
    SET LOCAL \"request.jwt.claim.role\"='authenticated';
    SET LOCAL \"request.jwt.claim.sub\"='d1000000-0000-0000-0000-000000000003';
    SELECT code FROM public.accept_organisation_invite('$invite_id',NULL,NULL,'$idempotency_key');
    COMMIT;"
}

accept_invite d1200000-0000-0000-0000-000000000001 d1300000-0000-0000-0000-000000000003 > "$temp_dir/first" &
first_pid=$!
accept_invite d1200000-0000-0000-0000-000000000002 d1300000-0000-0000-0000-000000000004 > "$temp_dir/second" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"

accepted_count="$(rg -h '^accepted$' "$temp_dir/first" "$temp_dir/second" | wc -l | tr -d ' ')"
unavailable_count="$(rg -h '^not_available$' "$temp_dir/first" "$temp_dir/second" | wc -l | tr -d ' ')"
[[ "$accepted_count" == '1' ]]
[[ "$unavailable_count" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.organisation_memberships WHERE user_id='d1000000-0000-0000-0000-000000000003' AND state IN ('active','suspended');")" == '1' ]]

echo 'Concurrent cross-organisation invite acceptance left exactly one current membership.'
