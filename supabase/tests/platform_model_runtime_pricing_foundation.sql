-- Run only against a disposable local database after migration 00103. This
-- rollback fixture proves the private immutable pending-verification boundary;
-- it leaves neither legacy nor platform configuration rows behind.
BEGIN;

-- The migration has already seeded repository legacy rows. This fixture adds a
-- unique legacy row and compares its durable records with the initial count;
-- it never mutates previously seeded immutable history.
INSERT INTO public.model_pricing (model_name, input_price_per_1m, output_price_per_1m, created_at, updated_at)
VALUES ('fixture-model-v1', 0.0750, 0.3000, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');

SET LOCAL ROLE service_role;
DO $test$
DECLARE first_run record; replay record;
BEGIN
  SELECT * INTO first_run FROM public.backfill_legacy_model_pricing();
  IF first_run.code <> 'seeded' OR first_run.seeded_count <> 1 OR first_run.skipped_count <> 0 OR first_run.conflict_count <> 0 THEN
    RAISE EXCEPTION 'legacy price seed did not identify exactly one eligible legacy row';
  END IF;
  SELECT * INTO replay FROM public.backfill_legacy_model_pricing();
  IF replay.code <> 'seeded' OR replay.seeded_count <> 0 OR replay.skipped_count <> 0 OR replay.conflict_count <> 0 THEN
    RAISE EXCEPTION 'legacy price seed was not idempotent';
  END IF;
END;
$test$;
RESET ROLE;

DO $test$
DECLARE result record; rejected boolean;
BEGIN
  PERFORM set_config('casechain.platform_configuration.write', '', true);
  IF NOT EXISTS (
    SELECT 1 FROM public.model_catalogue_versions
    WHERE provider_key = 'legacy' AND model_key = 'fixture-model-v1' AND revision = 1
  ) OR NOT EXISTS (
    SELECT 1 FROM public.provider_pricing_versions
    WHERE provider_key = 'legacy' AND model_key = 'fixture-model-v1' AND revision = 1
  ) THEN
    RAISE EXCEPTION 'legacy seed did not preserve immutable catalogue/pricing records';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.provider_pricing_versions
    WHERE origin <> 'legacy_seed_pending_verification'
       OR pricing_state <> 'legacy_seed_pending_verification'
       OR reason_code <> 'legacy_seed_pending_verification'
  ) THEN
    RAISE EXCEPTION 'legacy pricing was represented as verified';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.provider_pricing_rate_items AS rate
    JOIN public.provider_pricing_versions AS pricing ON pricing.id = rate.pricing_version_id
    WHERE pricing.model_key = 'fixture-model-v1' AND rate.billable_unit = 'input_token' AND rate.unit_quantity = 1000000 AND rate.micro_usd_amount = 75000
  ) OR NOT EXISTS (
    SELECT 1 FROM public.provider_pricing_rate_items AS rate
    JOIN public.provider_pricing_versions AS pricing ON pricing.id = rate.pricing_version_id
    WHERE pricing.model_key = 'fixture-model-v1' AND rate.billable_unit = 'output_token' AND rate.unit_quantity = 1000000 AND rate.micro_usd_amount = 300000
  ) THEN
    RAISE EXCEPTION 'legacy rates were not converted to integer micro-USD per million tokens';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.provider_pricing_rate_items AS rate
    JOIN public.provider_pricing_versions AS pricing ON pricing.id = rate.pricing_version_id
    WHERE pricing.model_key = 'text-embedding-004'
      AND pricing.pricing_contract = 'input_characters'
      AND rate.billable_unit = 'character'
      AND rate.unit_quantity = 1000000
      AND rate.micro_usd_amount = 25000
  ) OR EXISTS (
    SELECT 1 FROM public.provider_pricing_rate_items AS rate
    JOIN public.provider_pricing_versions AS pricing ON pricing.id = rate.pricing_version_id
    WHERE pricing.model_key = 'text-embedding-004' AND rate.billable_unit = 'output_token'
  ) THEN
    RAISE EXCEPTION 'character-billed embedding pricing was represented as token pricing';
  END IF;
  SELECT * INTO result FROM public.resolve_verified_provider_pricing_version('legacy', 'fixture-model-v1', '2026-01-02T00:00:00Z');
  IF result.code <> 'unpriced' OR result.pricing_version_id IS NOT NULL THEN
    RAISE EXCEPTION 'pending legacy pricing did not fail closed as unpriced';
  END IF;
  SELECT * INTO result FROM public.resolve_verified_provider_pricing_version('missing', 'missing', '2026-01-02T00:00:00Z');
  IF result.code <> 'unpriced' OR result.pricing_version_id IS NOT NULL THEN
    RAISE EXCEPTION 'missing pricing did not fail closed as unpriced';
  END IF;
  rejected := false;
  BEGIN
    INSERT INTO public.model_catalogue_versions (provider_key, model_key, revision, state, origin, reason_code, effective_from)
    VALUES ('legacy', 'fixture-model-v1', 2, 'legacy_seed_pending_verification', 'legacy_seed_pending_verification', 'legacy_seed_pending_verification', '2026-01-01T00:00:00Z');
  EXCEPTION WHEN raise_exception THEN rejected := SQLERRM = 'platform configuration requires the trusted configuration contract';
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'direct catalogue write bypassed trusted contract'; END IF;
  PERFORM set_config('casechain.platform_configuration.write', 'legacy_backfill', true);
  rejected := false;
  BEGIN
    INSERT INTO public.model_catalogue_versions (provider_key, model_key, revision, state, origin, reason_code, effective_from)
    VALUES ('legacy', 'fixture-model-v1', 2, 'legacy_seed_pending_verification', 'legacy_seed_pending_verification', 'legacy_seed_pending_verification', '2026-01-02T00:00:00Z');
  EXCEPTION WHEN raise_exception THEN rejected := SQLERRM = 'platform configuration effective windows must not overlap';
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'overlapping catalogue effective windows were accepted'; END IF;
  PERFORM set_config('casechain.platform_configuration.write', '', true);
  rejected := false;
  BEGIN DELETE FROM public.provider_pricing_rate_items; EXCEPTION WHEN raise_exception THEN rejected := SQLERRM = 'provider pricing rate item history is append-only'; END;
  IF NOT rejected THEN RAISE EXCEPTION 'pricing rate history was mutable'; END IF;
END;
$test$;

DO $test$
DECLARE verified_catalogue_id uuid; incomplete_price_id uuid; result record; conflict_result record;
BEGIN
  PERFORM set_config('casechain.platform_configuration.write', 'trusted_configuration', true);
  INSERT INTO public.model_catalogue_versions (
    provider_key, model_key, revision, state, origin, reason_code, effective_from
  ) VALUES (
    'fixture', 'verified-model', 1, 'active', 'platform_verified', 'fixture_verified', '2026-01-01T00:00:00Z'
  ) RETURNING id INTO verified_catalogue_id;
  INSERT INTO public.provider_pricing_versions (
    catalogue_version_id, provider_key, model_key, revision, pricing_contract, pricing_state, origin, reason_code, effective_from
  ) VALUES (
    verified_catalogue_id, 'fixture', 'verified-model', 1, 'input_output_tokens', 'priced', 'platform_verified', 'fixture_verified', '2026-01-01T00:00:00Z'
  ) RETURNING id INTO incomplete_price_id;
  INSERT INTO public.provider_pricing_rate_items (pricing_version_id, billable_unit, unit_quantity, micro_usd_amount)
  VALUES (incomplete_price_id, 'input_token', 1000000, 1);
  SELECT * INTO result FROM public.resolve_verified_provider_pricing_version('fixture', 'verified-model', '2026-01-02T00:00:00Z');
  IF result.code <> 'unpriced' OR result.pricing_version_id IS NOT NULL THEN
    RAISE EXCEPTION 'priced input/output contract with a missing output rate did not fail closed';
  END IF;
  INSERT INTO public.provider_pricing_rate_items (pricing_version_id, billable_unit, unit_quantity, micro_usd_amount)
  VALUES (incomplete_price_id, 'output_token', 1000000, 1);
  SELECT * INTO result FROM public.resolve_verified_provider_pricing_version('fixture', 'verified-model', '2026-01-02T00:00:00Z');
  IF result.code <> 'priced' OR result.pricing_version_id <> incomplete_price_id THEN
    RAISE EXCEPTION 'complete input/output pricing contract did not resolve exactly once';
  END IF;

  INSERT INTO public.model_catalogue_versions (
    provider_key, model_key, revision, state, origin, reason_code, effective_from
  ) VALUES (
    'legacy', 'fixture-conflict', 1, 'active', 'platform_verified', 'fixture_verified', '2026-01-01T00:00:00Z'
  );
  PERFORM set_config('casechain.platform_configuration.write', '', true);
  INSERT INTO public.model_pricing (model_name, input_price_per_1m, output_price_per_1m, created_at, updated_at)
  VALUES ('fixture-conflict', 0.1000, 0.2000, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');
  SET LOCAL ROLE service_role;
  SELECT * INTO conflict_result FROM public.backfill_legacy_model_pricing();
  RESET ROLE;
  IF conflict_result.code <> 'conflict' OR conflict_result.conflict_count <> 1 OR conflict_result.seeded_count <> 0 THEN
    RAISE EXCEPTION 'legacy seed did not fail closed on a verified catalogue conflict';
  END IF;
  IF EXISTS (SELECT 1 FROM public.provider_pricing_versions WHERE model_key = 'fixture-conflict') THEN
    RAISE EXCEPTION 'pending legacy pricing attached to a verified catalogue';
  END IF;
END;
$test$;

DO $test$
BEGIN
  IF has_table_privilege('authenticated','public.model_catalogue_versions','SELECT')
     OR has_table_privilege('anon','public.provider_pricing_versions','INSERT')
     OR has_table_privilege('service_role','public.provider_pricing_rate_items','INSERT')
     OR has_function_privilege('authenticated','public.backfill_legacy_model_pricing()','EXECUTE')
     OR has_function_privilege('authenticated','public.resolve_verified_provider_pricing_version(text,text,timestamptz)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.backfill_legacy_model_pricing()','EXECUTE') THEN
    RAISE EXCEPTION 'private configuration privilege boundary is unsafe';
  END IF;
END;
$test$;

SET LOCAL ROLE authenticated;
DO $test$
DECLARE statement text;
BEGIN
  FOREACH statement IN ARRAY ARRAY[
    $sql$SELECT * FROM public.model_catalogue_versions$sql$,
    $sql$SELECT * FROM public.provider_pricing_versions$sql$,
    $sql$INSERT INTO public.provider_pricing_rate_items (pricing_version_id,billable_unit,unit_quantity,micro_usd_amount) VALUES ('00000000-0000-0000-0000-000000000001','input_token',1,1)$sql$,
    $sql$SELECT * FROM public.backfill_legacy_model_pricing()$sql$
  ] LOOP
    BEGIN EXECUTE statement; RAISE EXCEPTION 'authenticated configuration bypass unexpectedly succeeded: %', statement;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
END;
$test$;
RESET ROLE;

ROLLBACK;
