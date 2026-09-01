import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

function source(relativePath: string) {
  return readFileSync(new URL(relativePath, import.meta.url), 'utf8')
}

test('provider usage daily rollups remain private, deferred, UTC-grained projections', () => {
  const migration = source('../../../supabase/migrations/00107_platform_provider_usage_daily_rollups.sql')
  const fixture = source('../../../supabase/tests/platform_provider_usage_daily_rollups.sql')
  const types = source('../supabase/database.types.ts')

  assert.match(migration, /CREATE CONSTRAINT TRIGGER provider_usage_events_project_daily_rollup[\s\S]*?AFTER INSERT ON public\.provider_usage_events[\s\S]*?DEFERRABLE INITIALLY DEFERRED/)
  assert.match(migration, /\(NEW\.occurred_at AT TIME ZONE 'UTC'\)::date/)
  assert.match(migration, /costed_event_count[\s\S]*?uncosted_event_count[\s\S]*?cost_micro_usd/)
  assert.match(migration, /REVOKE ALL ON TABLE public\.provider_usage_daily_rollups, public\.provider_usage_daily_rollup_line_items[\s\S]*?service_role/)
  assert.doesNotMatch(migration, /CREATE FUNCTION public\.read_|GRANT EXECUTE.*authenticated/)
  assert.match(fixture, /replay produced an unexpected immutable ledger event/)
  assert.match(fixture, /usage_day = '2026-01-02'/)
  assert.match(fixture, /quality = 'legacy_unverified'/)
  assert.match(fixture, /cost_micro_usd IS NULL/)
  assert.match(types, /provider_usage_daily_rollups: \{[\s\S]*?usage_day: string[\s\S]*?uncosted_event_count: number/)
})
