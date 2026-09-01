-- Run after `npx supabase db reset --local --no-seed` on a disposable database.
-- This fixture is rollback-only and exercises the private trigger-owned usage
-- projection through the same service-only ledger writer used by production.
BEGIN;

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'e7000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
  'usage-rollup@example.test', 'not-used', now(), '{}', '{}', now(), now()
);

INSERT INTO public.organisations (id, name, created_by) VALUES
  ('e7000000-0000-0000-0000-000000000101', 'Usage rollup fixture', 'e7000000-0000-0000-0000-000000000001');
INSERT INTO public.file_assets (id, org_id, bucket_id, object_key, byte_size, availability) VALUES
  ('e7000000-0000-0000-0000-000000000201', 'e7000000-0000-0000-0000-000000000101', 'documents',
   'orgs/e7000000-0000-0000-0000-000000000101/assets/e7000000-0000-0000-0000-000000000201/original.pdf', 1, 'reserved');
INSERT INTO public.source_analysis_runs (id, org_id, asset_id, request_key, idempotency_key) VALUES
  ('e7000000-0000-0000-0000-000000000301', 'e7000000-0000-0000-0000-000000000101',
   'e7000000-0000-0000-0000-000000000201', 'usage-rollup-fixture', 'usage-rollup-fixture');

DO $setup$
DECLARE catalogue_id uuid; runtime_id uuid; unpriced_catalogue_id uuid; unpriced_runtime_id uuid; pricing_id uuid;
BEGIN
  PERFORM set_config('casechain.platform_configuration.write', 'trusted_configuration', true);
  INSERT INTO public.model_catalogue_versions (provider_key, model_key, revision, state, origin, reason_code, effective_from)
  VALUES ('fixture', 'usage-rollup-model', 1, 'active', 'platform_verified', 'fixture_verified', '2026-01-01T00:00:00Z')
  RETURNING id INTO catalogue_id;
  INSERT INTO public.runtime_config_versions (
    catalogue_version_id, provider_key, model_key, operation_family, revision, state, reason_code, effective_from
  ) VALUES (
    catalogue_id, 'fixture', 'usage-rollup-model', 'fixture_usage_rollup', 1, 'enabled', 'fixture_verified', '2026-01-01T00:00:00Z'
  ) RETURNING id INTO runtime_id;
  INSERT INTO public.provider_pricing_versions (
    catalogue_version_id, provider_key, model_key, revision, pricing_contract, pricing_state, origin, reason_code, effective_from
  ) VALUES (
    catalogue_id, 'fixture', 'usage-rollup-model', 1, 'input_output_tokens', 'priced', 'platform_verified', 'fixture_verified', '2026-01-01T00:00:00Z'
  ) RETURNING id INTO pricing_id;
  INSERT INTO public.provider_pricing_rate_items (pricing_version_id, billable_unit, unit_quantity, micro_usd_amount) VALUES
    (pricing_id, 'input_token', 1, 2),
    (pricing_id, 'output_token', 1, 3);

  INSERT INTO public.model_catalogue_versions (provider_key, model_key, revision, state, origin, reason_code, effective_from)
  VALUES ('fixture', 'usage-rollup-unpriced-model', 1, 'active', 'platform_verified', 'fixture_verified', '2026-01-01T00:00:00Z')
  RETURNING id INTO unpriced_catalogue_id;
  INSERT INTO public.runtime_config_versions (
    catalogue_version_id, provider_key, model_key, operation_family, revision, state, reason_code, effective_from
  ) VALUES (
    unpriced_catalogue_id, 'fixture', 'usage-rollup-unpriced-model', 'fixture_usage_rollup', 1, 'enabled', 'fixture_verified', '2026-01-01T00:00:00Z'
  ) RETURNING id INTO unpriced_runtime_id;
  PERFORM set_config('casechain.fixture.runtime_id', runtime_id::text, true);
  PERFORM set_config('casechain.fixture.unpriced_runtime_id', unpriced_runtime_id::text, true);
  PERFORM set_config('casechain.platform_configuration.write', '', true);
END;
$setup$;

SET LOCAL ROLE service_role;
DO $writer$
DECLARE runtime_id uuid := current_setting('casechain.fixture.runtime_id')::uuid;
DECLARE unpriced_runtime_id uuid := current_setting('casechain.fixture.unpriced_runtime_id')::uuid;
DECLARE recorded record; replay record;
BEGIN
  SELECT * INTO recorded FROM public.record_provider_usage_event(
    'e7000000-0000-0000-0000-000000000101', 'source_analysis_run', 'e7000000-0000-0000-0000-000000000301',
    'fixture_usage_rollup', 'fixture', 'usage-rollup-model', runtime_id, '2026-01-01T23:59:59Z',
    '[{"unit":"input_token","quantity":5},{"unit":"output_token","quantity":3}]',
    'e7000000-0000-0000-0000-000000000401', 'e7000000-0000-0000-0000-000000000402'
  );
  IF recorded.code <> 'recorded_priced' OR recorded.cost_micro_usd <> 19 THEN
    RAISE EXCEPTION 'priced fixture event was not accepted';
  END IF;
  SELECT * INTO replay FROM public.record_provider_usage_event(
    'e7000000-0000-0000-0000-000000000101', 'source_analysis_run', 'e7000000-0000-0000-0000-000000000301',
    'fixture_usage_rollup', 'fixture', 'usage-rollup-model', runtime_id, '2026-01-01T23:59:59Z',
    '[{"unit":"output_token","quantity":3},{"unit":"input_token","quantity":5}]',
    'e7000000-0000-0000-0000-000000000401', 'e7000000-0000-0000-0000-000000000402'
  );
  IF replay.code <> 'replayed' OR replay.provider_usage_event_id <> recorded.provider_usage_event_id THEN
    RAISE EXCEPTION 'idempotent replay wrote another provider usage event';
  END IF;
  SELECT * INTO recorded FROM public.record_provider_usage_event(
    'e7000000-0000-0000-0000-000000000101', 'source_analysis_run', 'e7000000-0000-0000-0000-000000000301',
    'fixture_usage_rollup', 'fixture', 'usage-rollup-unpriced-model', unpriced_runtime_id, '2026-01-01T23:59:59Z',
    '[{"unit":"input_token","quantity":7}]',
    'e7000000-0000-0000-0000-000000000403', 'e7000000-0000-0000-0000-000000000404'
  );
  IF recorded.code <> 'recorded_unpriced' OR recorded.cost_micro_usd IS NOT NULL THEN
    RAISE EXCEPTION 'unpriced fixture event was not accepted as an unknown cost';
  END IF;
  SELECT * INTO recorded FROM public.record_provider_usage_event(
    'e7000000-0000-0000-0000-000000000101', 'source_analysis_run', 'e7000000-0000-0000-0000-000000000301',
    'fixture_usage_rollup', 'fixture', 'usage-rollup-model', runtime_id, '2026-01-02T00:00:00Z',
    '[{"unit":"input_token","quantity":2},{"unit":"output_token","quantity":1}]',
    'e7000000-0000-0000-0000-000000000405', 'e7000000-0000-0000-0000-000000000406'
  );
  IF recorded.code <> 'recorded_priced' OR recorded.cost_micro_usd <> 7 THEN
    RAISE EXCEPTION 'UTC-next-day priced fixture event was not accepted';
  END IF;
END;
$writer$;
RESET ROLE;

-- No production backfill is introduced. This trusted migration fixture adds a
-- legacy-classified immutable event solely to prove the projection preserves
-- its explicit unknown-cost state.
SELECT set_config('casechain.provider_usage.write', 'trusted_worker', true);
INSERT INTO public.provider_usage_events (
  id, org_id, subject_type, subject_id, operation_family, provider_key, model_key, quality,
  occurred_at, correlation_id, idempotency_key, request_fingerprint
) VALUES (
  'e7000000-0000-0000-0000-000000000501', 'e7000000-0000-0000-0000-000000000101', 'source_analysis_run',
  'e7000000-0000-0000-0000-000000000301', 'fixture_usage_rollup', 'fixture', 'usage-rollup-legacy-model', 'legacy_unverified',
  '2026-01-01T23:59:59Z', 'e7000000-0000-0000-0000-000000000502', 'e7000000-0000-0000-0000-000000000503', repeat('a', 64)
);
INSERT INTO public.provider_usage_line_items (provider_usage_event_id, billable_unit, provider_quantity)
VALUES ('e7000000-0000-0000-0000-000000000501', 'input_token', 11);

SET CONSTRAINTS provider_usage_events_project_daily_rollup IMMEDIATE;

DO $assert$
DECLARE rejected boolean;
BEGIN
  IF (SELECT count(*) FROM public.provider_usage_events WHERE org_id = 'e7000000-0000-0000-0000-000000000101') <> 4 THEN
    RAISE EXCEPTION 'replay produced an unexpected immutable ledger event';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.provider_usage_daily_rollups
    WHERE org_id = 'e7000000-0000-0000-0000-000000000101' AND usage_day = '2026-01-01'
      AND model_key = 'usage-rollup-model' AND quality = 'priced'
      AND event_count = 1 AND costed_event_count = 1 AND uncosted_event_count = 0 AND cost_micro_usd = 19
  ) OR NOT EXISTS (
    SELECT 1 FROM public.provider_usage_daily_rollups
    WHERE org_id = 'e7000000-0000-0000-0000-000000000101' AND usage_day = '2026-01-01'
      AND model_key = 'usage-rollup-unpriced-model' AND quality = 'unpriced'
      AND event_count = 1 AND costed_event_count = 0 AND uncosted_event_count = 1 AND cost_micro_usd IS NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM public.provider_usage_daily_rollups
    WHERE org_id = 'e7000000-0000-0000-0000-000000000101' AND usage_day = '2026-01-01'
      AND model_key = 'usage-rollup-legacy-model' AND quality = 'legacy_unverified'
      AND event_count = 1 AND costed_event_count = 0 AND uncosted_event_count = 1 AND cost_micro_usd IS NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM public.provider_usage_daily_rollups
    WHERE org_id = 'e7000000-0000-0000-0000-000000000101' AND usage_day = '2026-01-02'
      AND model_key = 'usage-rollup-model' AND quality = 'priced'
      AND event_count = 1 AND cost_micro_usd = 7
  ) THEN
    RAISE EXCEPTION 'daily rollup lost a quality state, exact cost, or UTC boundary';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.provider_usage_daily_rollup_line_items AS line
    JOIN public.provider_usage_daily_rollups AS rollup ON rollup.id = line.provider_usage_daily_rollup_id
    WHERE rollup.usage_day = '2026-01-01' AND rollup.model_key = 'usage-rollup-model' AND rollup.quality = 'priced'
      AND line.billable_unit = 'input_token' AND line.provider_quantity = 5 AND line.costed_quantity = 5
      AND line.uncosted_quantity = 0 AND line.cost_micro_usd = 10
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.provider_usage_daily_rollup_line_items AS line
    JOIN public.provider_usage_daily_rollups AS rollup ON rollup.id = line.provider_usage_daily_rollup_id
    WHERE rollup.usage_day = '2026-01-01' AND rollup.model_key = 'usage-rollup-unpriced-model' AND rollup.quality = 'unpriced'
      AND line.billable_unit = 'input_token' AND line.provider_quantity = 7 AND line.costed_quantity = 0
      AND line.uncosted_quantity = 7 AND line.cost_micro_usd IS NULL
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.provider_usage_daily_rollup_line_items AS line
    JOIN public.provider_usage_daily_rollups AS rollup ON rollup.id = line.provider_usage_daily_rollup_id
    WHERE rollup.usage_day = '2026-01-01' AND rollup.model_key = 'usage-rollup-legacy-model' AND rollup.quality = 'legacy_unverified'
      AND line.billable_unit = 'input_token' AND line.provider_quantity = 11 AND line.costed_quantity = 0
      AND line.uncosted_quantity = 11 AND line.cost_micro_usd IS NULL
  ) THEN
    RAISE EXCEPTION 'daily unit rollups confused unpriced quantity with zero cost';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name IN ('provider_usage_daily_rollups', 'provider_usage_daily_rollup_line_items')
      AND column_name IN ('document_id', 'user_id', 'payload', 'path', 'object_key', 'content')
  ) THEN
    RAISE EXCEPTION 'daily usage projection contains prohibited private dimensions';
  END IF;
  IF has_table_privilege('anon', 'public.provider_usage_daily_rollups', 'SELECT')
     OR has_table_privilege('authenticated', 'public.provider_usage_daily_rollup_line_items', 'SELECT')
     OR has_table_privilege('service_role', 'public.provider_usage_daily_rollups', 'INSERT')
     OR has_function_privilege('authenticated', 'public.project_provider_usage_daily_rollup()', 'EXECUTE') THEN
    RAISE EXCEPTION 'daily usage projection privilege boundary is unsafe';
  END IF;
  PERFORM set_config('casechain.provider_usage_rollup.write', '', true);
  rejected := false;
  BEGIN UPDATE public.provider_usage_daily_rollups SET event_count = 9; EXCEPTION WHEN raise_exception THEN rejected := SQLERRM = 'provider usage daily rollups require the ledger event trigger'; END;
  IF NOT rejected THEN RAISE EXCEPTION 'daily usage rollup was directly mutable'; END IF;
END;
$assert$;

SET LOCAL ROLE authenticated;
DO $permissions$
BEGIN
  BEGIN
    SELECT * FROM public.provider_usage_daily_rollups;
    RAISE EXCEPTION 'authenticated caller read private usage projection';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$permissions$;
RESET ROLE;

ROLLBACK;
