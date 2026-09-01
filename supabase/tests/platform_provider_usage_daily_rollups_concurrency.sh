#!/usr/bin/env bash
# Run after `npx supabase db reset --local --no-seed` on a disposable database.
set -euo pipefail

db_container="supabase_db_dms"
setup_sql="$(dirname "$0")/platform_provider_usage_daily_rollups_concurrency_setup.sql"

db_psql() {
  docker exec -i "$db_container" psql -X -qAt -v ON_ERROR_STOP=1 -U postgres -d postgres "$@"
}

db_psql <"$setup_sql"
runtime_id="$(db_psql -c "SELECT id FROM public.runtime_config_versions WHERE model_key = 'usage-rollup-race-model';")"

write_event() {
  local correlation_id="$1"
  local idempotency_key="$2"
  db_psql -c "
    BEGIN;
    SET LOCAL ROLE service_role;
    SELECT code FROM public.record_provider_usage_event(
      'e7100000-0000-0000-0000-000000000101', 'source_analysis_run', 'e7100000-0000-0000-0000-000000000301',
      'fixture_usage_rollup_race', 'fixture', 'usage-rollup-race-model',
      '$runtime_id',
      '2026-01-03T12:00:00Z', '[{\"unit\":\"input_token\",\"quantity\":5}]', '$correlation_id', '$idempotency_key'
    );
    COMMIT;" >/dev/null
}

write_event 'e7100000-0000-0000-0000-000000000401' 'e7100000-0000-0000-0000-000000000402' &
first_pid=$!
write_event 'e7100000-0000-0000-0000-000000000403' 'e7100000-0000-0000-0000-000000000404' &
second_pid=$!
wait "$first_pid"
wait "$second_pid"

[[ "$(db_psql -c "SELECT event_count || ':' || cost_micro_usd FROM public.provider_usage_daily_rollups WHERE org_id='e7100000-0000-0000-0000-000000000101';")" == '2:20' ]]
[[ "$(db_psql -c "SELECT provider_quantity || ':' || costed_quantity || ':' || uncosted_quantity || ':' || cost_micro_usd FROM public.provider_usage_daily_rollup_line_items;")" == '10:10:0:20' ]]

echo 'provider usage daily rollup concurrency fixture passed'
