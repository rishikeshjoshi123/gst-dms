#!/usr/bin/env bash
set -euo pipefail
db_container="${SUPABASE_DB_CONTAINER:?local database container is required}"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
db_psql(){ docker exec "$db_container" psql -X -qAt -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
invite(){ local key="$1" hash="$2"; db_psql -c "BEGIN; SET LOCAL ROLE authenticated; SET LOCAL \"request.jwt.claim.role\"='authenticated'; SET LOCAL \"request.jwt.claim.sub\"='16500000-0000-0000-0000-000000000001'; SELECT code FROM public.create_organisation_invite('race-target@invite.test','associate','$hash','$key'); COMMIT;"; }
invite '16520000-0000-0000-0000-000000000001' "$(printf 'a%.0s' {1..64})" >"$temp_dir/one" & first=$!
invite '16520000-0000-0000-0000-000000000002' "$(printf 'b%.0s' {1..64})" >"$temp_dir/two" & second=$!
wait "$first"
wait "$second"
[[ "$(awk '/^created$/{n++}END{print n+0}' "$temp_dir/one" "$temp_dir/two")" == 1 ]]
[[ "$(awk '/^pending_exists$/{n++}END{print n+0}' "$temp_dir/one" "$temp_dir/two")" == 1 ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.organisation_invites WHERE org_id='16510000-0000-0000-0000-000000000001' AND normalized_email='race-target@invite.test' AND state='pending';")" == 1 ]]
[[ "$(db_psql -c "SELECT count(*) FROM public.organisation_invite_deliveries delivery JOIN public.organisation_invites invite ON invite.id=delivery.invite_id WHERE invite.org_id='16510000-0000-0000-0000-000000000001';")" == 1 ]]
echo 'Concurrent same-address invitation creation committed one invitation and delivery.'
