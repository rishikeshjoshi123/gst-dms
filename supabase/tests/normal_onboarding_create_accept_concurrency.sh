#!/usr/bin/env bash
set -euo pipefail

db_container="${SUPABASE_DB_CONTAINER:?local database container is required}"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

db_psql() {
  docker exec "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"
}

create_org() {
  db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='14550000-0000-0000-0000-000000000002'; SELECT code FROM public.create_organisation('Concurrent new organisation','14554000-0000-0000-0000-000000000001'); COMMIT;"
}

accept_invite() {
  db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='14550000-0000-0000-0000-000000000002'; SELECT code FROM public.accept_organisation_invite('14552000-0000-0000-0000-000000000001',NULL,NULL,'14554000-0000-0000-0000-000000000002'); COMMIT;"
}

create_org > "$temp_dir/create" & create_pid=$!
accept_invite > "$temp_dir/accept" & accept_pid=$!
wait "$create_pid"
wait "$accept_pid"

successes="$(awk '/^(ok|accepted)$/{count++} END{print count+0}' "$temp_dir/create" "$temp_dir/accept")"
denials="$(awk '/^not_available$/{count++} END{print count+0}' "$temp_dir/create" "$temp_dir/accept")"
[[ "$successes" == '1' ]]
[[ "$denials" == '1' ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.organisation_memberships WHERE user_id='14550000-0000-0000-0000-000000000002' AND state IN ('active','suspended');")" == '1' ]]

created_count="$(db_psql -c "SELECT count(*) FROM public.organisations WHERE created_by='14550000-0000-0000-0000-000000000002';")"
accepted_count="$(db_psql -c "SELECT count(*) FROM public.organisation_invites WHERE id='14552000-0000-0000-0000-000000000001' AND state='accepted';")"
[[ "$((created_count + accepted_count))" == '1' ]]
echo 'Concurrent create-versus-accept committed exactly one current membership and one entry outcome.'
