-- Run only against a disposable local database after migration 00104. This
-- rollback fixture exercises the private trusted-worker ledger boundary and
-- leaves no users, organisations, runs, configuration, ledger, or alert data.
BEGIN;

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('00000000-0000-0000-0000-000000000000', 'e4000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'usage-a@example.test', 'not-used', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'e4000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'usage-b@example.test', 'not-used', now(), '{}', '{}', now(), now());

INSERT INTO public.organisations (id, name, created_by) VALUES
  ('e4000000-0000-0000-0000-000000000101', 'Usage fixture A', 'e4000000-0000-0000-0000-000000000001'),
  ('e4000000-0000-0000-0000-000000000102', 'Usage fixture B', 'e4000000-0000-0000-0000-000000000002');

INSERT INTO public.file_assets (id, org_id, bucket_id, object_key, byte_size, availability) VALUES
  ('e4000000-0000-0000-0000-000000000201', 'e4000000-0000-0000-0000-000000000101', 'documents', 'orgs/e4000000-0000-0000-0000-000000000101/assets/e4000000-0000-0000-0000-000000000201/original.pdf', 1, 'reserved'),
  ('e4000000-0000-0000-0000-000000000202', 'e4000000-0000-0000-0000-000000000102', 'documents', 'orgs/e4000000-0000-0000-0000-000000000102/assets/e4000000-0000-0000-0000-000000000202/original.pdf', 1, 'reserved');

INSERT INTO public.source_analysis_runs (id, org_id, asset_id, request_key, idempotency_key) VALUES
  ('e4000000-0000-0000-0000-000000000301', 'e4000000-0000-0000-0000-000000000101', 'e4000000-0000-0000-0000-000000000201', 'usage-fixture-a', 'usage-fixture-a'),
  ('e4000000-0000-0000-0000-000000000302', 'e4000000-0000-0000-0000-000000000102', 'e4000000-0000-0000-0000-000000000202', 'usage-fixture-b', 'usage-fixture-b');

DO $test$
DECLARE catalogue_id uuid; runtime_id uuid; pricing_id uuid; unpriced_catalogue_id uuid; unpriced_runtime_id uuid;
BEGIN
  PERFORM set_config('casechain.platform_configuration.write', 'trusted_configuration', true);
  INSERT INTO public.model_catalogue_versions (
    provider_key, model_key, revision, state, origin, reason_code, effective_from
  ) VALUES (
    'fixture', 'usage-model', 1, 'active', 'platform_verified', 'fixture_verified', '2026-01-01T00:00:00Z'
  ) RETURNING id INTO catalogue_id;
  INSERT INTO public.runtime_config_versions (
    catalogue_version_id, provider_key, model_key, operation_family, revision, state, reason_code, effective_from
  ) VALUES (
    catalogue_id, 'fixture', 'usage-model', 'fixture_usage', 1, 'enabled', 'fixture_verified', '2026-01-01T00:00:00Z'
  ) RETURNING id INTO runtime_id;
  INSERT INTO public.provider_pricing_versions (
    catalogue_version_id, provider_key, model_key, revision, pricing_contract, pricing_state, origin, reason_code, effective_from
  ) VALUES (
    catalogue_id, 'fixture', 'usage-model', 1, 'input_output_tokens', 'priced', 'platform_verified', 'fixture_verified', '2026-01-01T00:00:00Z'
  ) RETURNING id INTO pricing_id;
  INSERT INTO public.provider_pricing_rate_items (pricing_version_id, billable_unit, unit_quantity, micro_usd_amount) VALUES
    (pricing_id, 'input_token', 1, 2),
    (pricing_id, 'output_token', 1, 3);
  INSERT INTO public.model_catalogue_versions (
    provider_key, model_key, revision, state, origin, reason_code, effective_from
  ) VALUES (
    'fixture', 'unpriced-model', 1, 'active', 'platform_verified', 'fixture_verified', '2026-01-01T00:00:00Z'
  ) RETURNING id INTO unpriced_catalogue_id;
  INSERT INTO public.runtime_config_versions (
    catalogue_version_id, provider_key, model_key, operation_family, revision, state, reason_code, effective_from
  ) VALUES (
    unpriced_catalogue_id, 'fixture', 'unpriced-model', 'fixture_unpriced', 1, 'enabled', 'fixture_verified', '2026-01-01T00:00:00Z'
  ) RETURNING id INTO unpriced_runtime_id;
  PERFORM set_config('casechain.platform_configuration.write', '', true);
  PERFORM set_config('casechain.fixture.runtime_id', runtime_id::text, true);
  PERFORM set_config('casechain.fixture.unpriced_runtime_id', unpriced_runtime_id::text, true);
END;
$test$;

SET LOCAL ROLE service_role;
DO $test$
DECLARE runtime_id uuid := current_setting('casechain.fixture.runtime_id')::uuid;
DECLARE unpriced_runtime_id uuid := current_setting('casechain.fixture.unpriced_runtime_id')::uuid;
DECLARE priced record; replay record; conflict record; unpriced record; invalid record; unavailable record; mismatch record;
BEGIN
  SELECT * INTO priced FROM public.record_provider_usage_event(
    'e4000000-0000-0000-0000-000000000101', 'source_analysis_run', 'e4000000-0000-0000-0000-000000000301',
    'fixture_usage', 'fixture', 'usage-model', runtime_id, '2026-01-02T00:00:00Z',
    '[{"unit":"output_token","quantity":3},{"unit":"input_token","quantity":5}]',
    'e4000000-0000-0000-0000-000000000401', 'e4000000-0000-0000-0000-000000000402'
  );
  IF priced.code <> 'recorded_priced' OR priced.provider_usage_event_id IS NULL
     OR priced.quality <> 'priced' OR priced.cost_micro_usd <> 19 OR priced.pricing_version_id IS NULL THEN
    RAISE EXCEPTION 'exact integer provider cost was not recorded as priced';
  END IF;
  SELECT * INTO replay FROM public.record_provider_usage_event(
    'e4000000-0000-0000-0000-000000000101', 'source_analysis_run', 'e4000000-0000-0000-0000-000000000301',
    'fixture_usage', 'fixture', 'usage-model', runtime_id, '2026-01-02T00:00:00Z',
    '[{"unit":"input_token","quantity":5},{"unit":"output_token","quantity":3}]',
    'e4000000-0000-0000-0000-000000000401', 'e4000000-0000-0000-0000-000000000402'
  );
  IF replay.code <> 'replayed' OR replay.provider_usage_event_id <> priced.provider_usage_event_id THEN
    RAISE EXCEPTION 'canonical line-item replay was not idempotent';
  END IF;
  SELECT * INTO conflict FROM public.record_provider_usage_event(
    'e4000000-0000-0000-0000-000000000102', 'source_analysis_run', 'e4000000-0000-0000-0000-000000000302',
    'fixture_usage', 'fixture', 'usage-model', runtime_id, '2026-01-02T00:00:00Z',
    '[{"unit":"input_token","quantity":5},{"unit":"output_token","quantity":3}]',
    'e4000000-0000-0000-0000-000000000401', 'e4000000-0000-0000-0000-000000000402'
  );
  IF conflict.code <> 'idempotency_conflict' THEN
    RAISE EXCEPTION 'cross-subject idempotency reuse was accepted';
  END IF;
  SELECT * INTO conflict FROM public.record_provider_usage_event(
    'e4000000-0000-0000-0000-000000000101', 'source_analysis_run', 'e4000000-0000-0000-0000-000000000302',
    'fixture_usage', 'fixture', 'usage-model', runtime_id, '2026-01-02T00:00:00Z',
    '[{"unit":"input_token","quantity":1},{"unit":"output_token","quantity":1}]',
    'e4000000-0000-0000-0000-000000000403', 'e4000000-0000-0000-0000-000000000404'
  );
  IF conflict.code <> 'invalid_subject' THEN
    RAISE EXCEPTION 'cross-tenant run was accepted as a usage subject';
  END IF;
  SELECT * INTO mismatch FROM public.record_provider_usage_event(
    'e4000000-0000-0000-0000-000000000101', 'source_analysis_run', 'e4000000-0000-0000-0000-000000000301',
    'fixture_usage', 'fixture', 'usage-model', runtime_id, '2026-01-02T00:00:00Z',
    '[{"unit":"character","quantity":7}]',
    'e4000000-0000-0000-0000-000000000405', 'e4000000-0000-0000-0000-000000000406'
  );
  IF mismatch.code <> 'pricing_contract_mismatch' OR mismatch.provider_usage_event_id IS NOT NULL THEN
    RAISE EXCEPTION 'character usage was accepted under an input/output token price contract';
  END IF;
  SELECT * INTO unpriced FROM public.record_provider_usage_event(
    'e4000000-0000-0000-0000-000000000101', 'source_analysis_run', 'e4000000-0000-0000-0000-000000000301',
    'fixture_unpriced', 'fixture', 'unpriced-model', unpriced_runtime_id, '2026-01-02T00:00:00Z',
    '[{"unit":"input_token","quantity":7}]',
    'e4000000-0000-0000-0000-000000000417', 'e4000000-0000-0000-0000-000000000418'
  );
  IF unpriced.code <> 'recorded_unpriced' OR unpriced.quality <> 'unpriced'
     OR unpriced.cost_micro_usd IS NOT NULL OR unpriced.pricing_version_id IS NOT NULL THEN
    RAISE EXCEPTION 'missing pricing did not become an explicit unpriced event';
  END IF;
  SELECT * INTO invalid FROM public.record_provider_usage_event(
    'e4000000-0000-0000-0000-000000000101', 'source_analysis_run', 'e4000000-0000-0000-0000-000000000301',
    'fixture_usage', 'fixture', 'usage-model', runtime_id, '2026-01-02T00:00:00Z',
    '[{"unit":"input_tokens","quantity":1,"raw_provider_payload":"forbidden"}]',
    'e4000000-0000-0000-0000-000000000407', 'e4000000-0000-0000-0000-000000000408'
  );
  IF invalid.code <> 'invalid_request' THEN
    RAISE EXCEPTION 'invalid unit or raw provider payload key was accepted';
  END IF;
  SELECT * INTO unavailable FROM public.record_provider_usage_event(
    'e4000000-0000-0000-0000-000000000101', 'source_analysis_run', 'e4000000-0000-0000-0000-000000000301',
    'fixture_usage', 'fixture', 'usage-model', runtime_id, '2025-12-31T23:59:59Z',
    '[{"unit":"input_token","quantity":1},{"unit":"output_token","quantity":1}]',
    'e4000000-0000-0000-0000-000000000409', 'e4000000-0000-0000-0000-000000000410'
  );
  IF unavailable.code <> 'configuration_unavailable' THEN
    RAISE EXCEPTION 'stale runtime configuration was accepted';
  END IF;
END;
$test$;
RESET ROLE;

DO $test$
DECLARE rejected boolean;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.provider_usage_line_items AS line
    JOIN public.provider_usage_events AS event ON event.id = line.provider_usage_event_id
    WHERE event.org_id = 'e4000000-0000-0000-0000-000000000101'
      AND event.quality = 'unpriced' AND line.billable_unit = 'input_token'
      AND line.provider_quantity = 7 AND line.pricing_rate_item_id IS NULL AND line.cost_micro_usd IS NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM public.platform_alerts
    WHERE alert_kind = 'provider_usage_unpriced' AND subject_type = 'organisation'
      AND subject_id = 'e4000000-0000-0000-0000-000000000101'
  ) THEN
    RAISE EXCEPTION 'unpriced usage lacked its exact provider unit or safe alert';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.provider_pricing_rate_finalizations AS finalized
    JOIN public.provider_pricing_versions AS pricing ON pricing.id = finalized.pricing_version_id
    WHERE pricing.provider_key = 'fixture' AND pricing.model_key = 'usage-model'
  ) THEN
    RAISE EXCEPTION 'priced ledger usage did not finalize its pricing snapshot';
  END IF;
  PERFORM set_config('casechain.provider_usage.write', '', true);
  rejected := false;
  BEGIN UPDATE public.provider_usage_events SET quality = 'unpriced'; EXCEPTION WHEN raise_exception THEN rejected := SQLERRM = 'provider usage ledger is append-only'; END;
  IF NOT rejected THEN RAISE EXCEPTION 'provider usage event history was mutable'; END IF;
  rejected := false;
  BEGIN DELETE FROM public.provider_usage_line_items; EXCEPTION WHEN raise_exception THEN rejected := SQLERRM = 'provider usage ledger is append-only'; END;
  IF NOT rejected THEN RAISE EXCEPTION 'provider usage line-item history was mutable'; END IF;
  IF has_table_privilege('authenticated', 'public.provider_usage_events', 'SELECT')
     OR has_table_privilege('anon', 'public.provider_usage_line_items', 'INSERT')
     OR has_table_privilege('service_role', 'public.provider_usage_events', 'INSERT')
     OR has_table_privilege('service_role', 'public.provider_pricing_rate_finalizations', 'INSERT')
     OR has_function_privilege('authenticated', 'public.record_provider_usage_event(uuid,public.provider_usage_subject_type,uuid,text,text,text,uuid,timestamptz,jsonb,uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.finalize_provider_pricing_version(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_provider_usage_event(uuid,public.provider_usage_subject_type,uuid,text,text,text,uuid,timestamptz,jsonb,uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'provider ledger privilege boundary is unsafe';
  END IF;
END;
$test$;

DO $test$
DECLARE usage_pricing_id uuid; extra_catalogue_id uuid; extra_pricing_id uuid; finalized record; rejected boolean;
BEGIN
  SELECT id INTO usage_pricing_id FROM public.provider_pricing_versions
  WHERE provider_key = 'fixture' AND model_key = 'usage-model';
  PERFORM set_config('casechain.platform_configuration.write', 'trusted_configuration', true);
  rejected := false;
  BEGIN
    INSERT INTO public.provider_pricing_rate_items (pricing_version_id, billable_unit, unit_quantity, micro_usd_amount)
    VALUES (usage_pricing_id, 'cached_input_token', 1, 1);
  EXCEPTION WHEN raise_exception THEN rejected := SQLERRM = 'provider pricing rate snapshot is finalized';
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'a finalized price accepted a later rate item'; END IF;

  INSERT INTO public.model_catalogue_versions (
    provider_key, model_key, revision, state, origin, reason_code, effective_from
  ) VALUES (
    'fixture', 'extra-rate-model', 1, 'active', 'platform_verified', 'fixture_verified', '2026-01-01T00:00:00Z'
  ) RETURNING id INTO extra_catalogue_id;
  INSERT INTO public.provider_pricing_versions (
    catalogue_version_id, provider_key, model_key, revision, pricing_contract, pricing_state, origin, reason_code, effective_from
  ) VALUES (
    extra_catalogue_id, 'fixture', 'extra-rate-model', 1, 'input_output_tokens', 'priced', 'platform_verified', 'fixture_verified', '2026-01-01T00:00:00Z'
  ) RETURNING id INTO extra_pricing_id;
  INSERT INTO public.provider_pricing_rate_items (pricing_version_id, billable_unit, unit_quantity, micro_usd_amount) VALUES
    (extra_pricing_id, 'input_token', 1, 1),
    (extra_pricing_id, 'output_token', 1, 1),
    (extra_pricing_id, 'character', 1, 1);
  PERFORM set_config('casechain.platform_configuration.write', '', true);
  SELECT * INTO finalized FROM public.finalize_provider_pricing_version(extra_pricing_id);
  IF finalized.code <> 'invalid_rate_contract' OR finalized.pricing_version_id <> extra_pricing_id
     OR EXISTS (SELECT 1 FROM public.provider_pricing_rate_finalizations WHERE pricing_version_id = extra_pricing_id) THEN
    RAISE EXCEPTION 'an extra unit rate was accepted as an input/output token price snapshot';
  END IF;
END;
$test$;

SET LOCAL ROLE authenticated;
DO $test$
DECLARE statement text;
BEGIN
  FOREACH statement IN ARRAY ARRAY[
    $sql$SELECT * FROM public.provider_usage_events$sql$,
    $sql$SELECT * FROM public.provider_usage_line_items$sql$,
    $sql$INSERT INTO public.provider_usage_events (org_id,subject_type,subject_id,operation_family,provider_key,model_key,quality,occurred_at,correlation_id,idempotency_key,request_fingerprint) VALUES ('e4000000-0000-0000-0000-000000000101','source_analysis_run','e4000000-0000-0000-0000-000000000301','fixture_usage','fixture','usage-model','legacy_unverified',now(),'e4000000-0000-0000-0000-000000000411','e4000000-0000-0000-0000-000000000412',repeat('a',64))$sql$,
    $sql$SELECT * FROM public.record_provider_usage_event('e4000000-0000-0000-0000-000000000101','source_analysis_run','e4000000-0000-0000-0000-000000000301','fixture_usage','fixture','usage-model','e4000000-0000-0000-0000-000000000000',now(),'[]','e4000000-0000-0000-0000-000000000413','e4000000-0000-0000-0000-000000000414')$sql$
  ] LOOP
    BEGIN EXECUTE statement; RAISE EXCEPTION 'authenticated provider ledger bypass unexpectedly succeeded: %', statement;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
END;
$test$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $test$
BEGIN
  BEGIN
    INSERT INTO public.provider_usage_events (
      org_id, subject_type, subject_id, operation_family, provider_key, model_key,
      quality, occurred_at, correlation_id, idempotency_key, request_fingerprint
    ) VALUES (
      'e4000000-0000-0000-0000-000000000101', 'source_analysis_run', 'e4000000-0000-0000-0000-000000000301',
      'fixture_usage', 'fixture', 'usage-model', 'legacy_unverified', now(),
      'e4000000-0000-0000-0000-000000000415', 'e4000000-0000-0000-0000-000000000416', repeat('a', 64)
    );
    RAISE EXCEPTION 'service role directly inserted provider usage';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$test$;
RESET ROLE;

ROLLBACK;
