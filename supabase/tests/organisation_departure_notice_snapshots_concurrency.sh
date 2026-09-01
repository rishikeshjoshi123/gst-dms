#!/usr/bin/env bash
# Confirms concurrent prospective-policy updates and invite acceptance serialize
# to one complete private policy snapshot on a disposable local Supabase DB.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cli="$repo_root/node_modules/.bin/supabase"
setup_sql="$repo_root/supabase/tests/organisation_departure_notice_snapshots_concurrency_setup.sql"
policy_sql="$repo_root/supabase/tests/organisation_departure_notice_snapshots_concurrency_policy_update.sql"
project_id="$(awk -F'"' '/^project_id = / { print $2; exit }' "$repo_root/supabase/config.toml")"
result_file="$(mktemp -t departure-notice-snapshot-race.XXXXXX)"
policy_pid=""

cleanup() {
  if [ -n "$policy_pid" ] && kill -0 "$policy_pid" 2>/dev/null; then
    kill "$policy_pid" 2>/dev/null || true
    wait "$policy_pid" 2>/dev/null || true
  fi
  rm -f "$result_file"
}
trap cleanup EXIT

"$cli" db reset --local --no-seed
db_container="$(docker ps --filter "name=^/supabase_db_${project_id}$" --format '{{.ID}}' | head -n 1)"
if [ -z "$db_container" ]; then
  echo "could not resolve the local Supabase Postgres container" >&2
  exit 1
fi
db_psql() {
  docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres "$@"
}

db_psql <"$setup_sql"
db_psql <"$policy_sql" >"$result_file" &
policy_pid=$!
ready_sql="SELECT NOT pg_try_advisory_lock(hashtextextended('departure-notice-snapshot-race-ready', 112));"
for _ in $(seq 1 100); do
  if db_psql -c "$ready_sql" | grep -qx 't'; then break; fi
  sleep 0.05
done
if ! db_psql -c "$ready_sql" | grep -qx 't'; then
  echo "policy update did not enter its locked transaction" >&2
  exit 1
fi

accept_result="$(db_psql -c "BEGIN; SET LOCAL statement_timeout='5s'; SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.role','authenticated',true); SELECT set_config('request.jwt.claim.sub','d3100000-0000-0000-0000-000000000002',true); SELECT code FROM public.accept_organisation_invite(NULL,repeat('b',64),NULL,'d3300000-0000-0000-0000-000000000002'); COMMIT;" | tail -n 1)"
wait "$policy_pid"
policy_pid=""
if [ "$accept_result" != 'accepted' ]; then
  echo "concurrent invite acceptance failed: $accept_result" >&2
  exit 1
fi

snapshot="$(db_psql -c "SELECT departure_notice_days || ':' || departure_notice_policy_version || ':' || (departure_notice_accepted_at = joined_at) FROM public.organisation_memberships WHERE org_id='d3200000-0000-0000-0000-000000000001' AND user_id='d3100000-0000-0000-0000-000000000002';")"
if [ "$snapshot" != '60:2:true' ] || ! grep -q . "$result_file"; then
  echo "invite acceptance observed an inconsistent departure-policy snapshot: $snapshot" >&2
  exit 1
fi

echo 'PASS: concurrent policy update and invitation acceptance produced one complete immutable snapshot.'
