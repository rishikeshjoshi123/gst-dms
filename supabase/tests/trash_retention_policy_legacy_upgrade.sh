#!/usr/bin/env bash
# Replays the exact 00089 -> 00090 upgrade with a legacy row whose NULL days
# are valid under 00079's three-valued CHECK expression.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cli="$repo_root/node_modules/.bin/supabase"
setup_sql="$repo_root/supabase/tests/trash_retention_policy_legacy_upgrade_setup.sql"
project_id="$(awk -F'"' '/^project_id = / { print $2; exit }' "$repo_root/supabase/config.toml")"

"$cli" db reset --local --no-seed --version 00089
db_container="$(docker ps --filter "name=^/supabase_db_${project_id}$" --format '{{.ID}}' | head -n 1)"
if [ -z "$db_container" ]; then
  echo "could not resolve the local Supabase Postgres container" >&2
  exit 1
fi

docker exec -i "$db_container" psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres <"$setup_sql"
"$cli" migration up --local

upgraded_policy="$(docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres -c "SELECT trash_retention_mode||':'||trash_retention_days||':'||auto_purge_enabled||':'||policy_version FROM public.organisation_retention_settings WHERE org_id='92000000-0000-0000-0000-000000000001';")"
if [ "$upgraded_policy" != "retention_period:90:true:1" ]; then
  echo "legacy NULL retention row did not normalize during 00090 upgrade: $upgraded_policy" >&2
  exit 1
fi

echo "PASS: migration 00090 normalized the legacy NULL retention period to automatic 90 days."
