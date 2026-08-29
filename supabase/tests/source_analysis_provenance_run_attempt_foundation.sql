-- Run after migration 00063 against a disposable local Supabase database.
-- Rollback-only: this fixture proves the normalized provenance foundation
-- without retaining legal-content or provider-output test data.
BEGIN;

DO $setup$
DECLARE
  org_a uuid := '63000000-0000-0000-0000-000000000001';
  org_b uuid := '63000000-0000-0000-0000-000000000002';
  actor_a uuid := '63100000-0000-0000-0000-000000000001';
  actor_b uuid := '63100000-0000-0000-0000-000000000002';
  asset_a uuid := '63200000-0000-0000-0000-000000000001';
  asset_b uuid := '63200000-0000-0000-0000-000000000002';
  run_a uuid := '63300000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO auth.users(
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES
    ('00000000-0000-0000-0000-000000000000', actor_a, 'authenticated', 'authenticated',
      'provenance-a@example.test', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    ('00000000-0000-0000-0000-000000000000', actor_b, 'authenticated', 'authenticated',
      'provenance-b@example.test', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
  INSERT INTO public.organisations(id, name, created_by) VALUES
    (org_a, 'Provenance A', actor_a),
    (org_b, 'Provenance B', actor_b);
  INSERT INTO public.file_assets(
    id, org_id, bucket_id, object_key, sha256, byte_size, detected_mime_type,
    availability, validated_at, validated_page_count, created_by
  ) VALUES
    (asset_a, org_a, 'documents', 'orgs/' || org_a::text || '/assets/' || asset_a::text || '/original.pdf',
      repeat('a', 64), 17, 'application/pdf', 'available', now(), 1, actor_a),
    (asset_b, org_b, 'documents', 'orgs/' || org_b::text || '/assets/' || asset_b::text || '/original.pdf',
      repeat('b', 64), 19, 'application/pdf', 'available', now(), 1, actor_b);
  INSERT INTO public.source_analysis_runs(
    id, org_id, asset_id, request_key, idempotency_key, analysis_kind, analysis_state,
    provider, model_identifier, model_config_version, prompt_version,
    schema_version, catalogue_version, normalizer_version
  ) VALUES (
    run_a, org_a, asset_a, 'analysis.provenance.a.1', 'analysis.provenance.a.1', 'ai_extraction', 'queued',
    'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24',
    'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'
  );
END $setup$;

DO $tenant_and_idempotency$
DECLARE
  org_a uuid := '63000000-0000-0000-0000-000000000001';
  org_b uuid := '63000000-0000-0000-0000-000000000002';
  asset_a uuid := '63200000-0000-0000-0000-000000000001';
  run_a uuid := '63300000-0000-0000-0000-000000000001';
  rejected boolean := false;
BEGIN
  BEGIN
    INSERT INTO public.source_analysis_runs(
      org_id, asset_id, request_key, idempotency_key, analysis_kind, analysis_state,
      provider, model_identifier, model_config_version, prompt_version,
      schema_version, catalogue_version, normalizer_version
    ) VALUES (
      org_a, asset_a, 'analysis.provenance.a.duplicate-request', 'analysis.provenance.a.1', 'ai_extraction', 'queued',
      'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24',
      'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'
    );
  EXCEPTION WHEN unique_violation THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'source analysis idempotency identity was not unique'; END IF;

  rejected := false;
  BEGIN
    INSERT INTO public.source_analysis_runs(
      org_id, asset_id, request_key, analysis_kind, analysis_state,
      provider, model_identifier, model_config_version, prompt_version,
      schema_version, catalogue_version, normalizer_version
    ) VALUES (
      org_b, asset_a, 'analysis.provenance.cross-tenant', 'ai_extraction', 'queued',
      'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24',
      'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'
    );
  EXCEPTION WHEN foreign_key_violation THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'cross-tenant analysis asset was accepted'; END IF;

  rejected := false;
  BEGIN
    INSERT INTO public.source_analysis_attempts(
      org_id, source_analysis_run_id, attempt_number, provider, model_identifier,
      model_config_version, prompt_version, schema_version, catalogue_version, normalizer_version
    ) VALUES (
      org_b, run_a, 1, 'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24',
      'gst-extraction-2026-08-24', 'source-analysis-schema-2026-08-24',
      'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'
    );
  EXCEPTION WHEN OTHERS THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'cross-tenant analysis attempt was accepted'; END IF;
END $tenant_and_idempotency$;

DO $state_and_immutability$
DECLARE
  org_a uuid := '63000000-0000-0000-0000-000000000001';
  asset_a uuid := '63200000-0000-0000-0000-000000000001';
  run_a uuid := '63300000-0000-0000-0000-000000000001';
  attempt_a uuid := '63400000-0000-0000-0000-000000000001';
  replayable_run uuid := '63500000-0000-0000-0000-000000000001';
  rejected boolean := false;
BEGIN
  INSERT INTO public.source_analysis_attempts(
    id, org_id, source_analysis_run_id, attempt_number, provider, model_identifier,
    model_config_version, prompt_version, schema_version, catalogue_version, normalizer_version
  ) VALUES (
    attempt_a, org_a, run_a, 1, 'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24',
    'gst-extraction-2026-08-24', 'source-analysis-schema-2026-08-24',
    'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'
  );
  UPDATE public.source_analysis_runs
  SET state = 'running', analysis_state = 'running', started_at = now(), provider_request_id = 'request-provenance-a-1',
      lease_token = gen_random_uuid(), lease_expires_at = now() + interval '5 minutes', heartbeat_at = now()
  WHERE id = run_a;
  UPDATE public.source_analysis_attempts
  SET state = 'running', started_at = now(), provider_request_id = 'request-provenance-a-1'
  WHERE id = attempt_a;
  UPDATE public.source_analysis_attempts
  SET state = 'succeeded', completed_at = now(), provider_operation_id = 'operation-provenance-a-1',
      input_tokens = 101, output_tokens = 202, billable_units = 303, cost_amount = 0.123456,
      cost_currency = 'USD', latency_ms = 456, usage_recorded_at = now()
  WHERE id = attempt_a;
  UPDATE public.source_analysis_runs
  SET state = 'succeeded', analysis_state = 'validated', completed_at = now(), provider_operation_id = 'operation-provenance-a-1',
      input_tokens = 101, output_tokens = 202, billable_units = 303, cost_amount = 0.123456,
      cost_currency = 'USD', latency_ms = 456, usage_recorded_at = now()
  WHERE id = run_a;

  BEGIN
    UPDATE public.source_analysis_attempts SET output_tokens = 203 WHERE id = attempt_a;
  EXCEPTION WHEN OTHERS THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'terminal attempt was mutable'; END IF;

  rejected := false;
  BEGIN
    UPDATE public.source_analysis_runs SET prompt_version = 'other-prompt' WHERE id = run_a;
  EXCEPTION WHEN OTHERS THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'run provenance identity was mutable'; END IF;

  rejected := false;
  BEGIN
    DELETE FROM public.source_analysis_runs WHERE id = run_a;
  EXCEPTION WHEN OTHERS THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'source analysis run was deletable'; END IF;

  INSERT INTO public.source_analysis_runs(
    id, org_id, asset_id, request_key, state, started_at, lease_token, lease_expires_at, heartbeat_at
  ) VALUES (
    replayable_run, org_a, asset_a, 'validation.provenance.replay', 'running', now() - interval '10 minutes',
    gen_random_uuid(), now() - interval '1 minute', now() - interval '10 minutes'
  );
  UPDATE public.source_analysis_runs
  SET state = 'queued', started_at = NULL, lease_token = NULL, lease_expires_at = NULL,
      heartbeat_at = now(), safe_error_code = 'work_requeued'
  WHERE id = replayable_run;
  IF (SELECT state FROM public.source_analysis_runs WHERE id = replayable_run) <> 'queued' THEN
    RAISE EXCEPTION 'expired analysis lease was not replayable';
  END IF;
END $state_and_immutability$;

DO $ai_lease_and_retry_fences$
DECLARE
  org_a uuid := '63000000-0000-0000-0000-000000000001';
  asset_a uuid := '63200000-0000-0000-0000-000000000001';
  terminal_run uuid := '63300000-0000-0000-0000-000000000001';
  stale_run uuid := '63600000-0000-0000-0000-000000000001';
  retry_run uuid := '63700000-0000-0000-0000-000000000001';
  rejected boolean := false;
BEGIN
  -- A terminal run cannot accept a late retry row, even if its ordinal would
  -- otherwise be valid.
  BEGIN
    INSERT INTO public.source_analysis_attempts(
      org_id, source_analysis_run_id, attempt_number, retry_reason, provider, model_identifier,
      model_config_version, prompt_version, schema_version, catalogue_version, normalizer_version
    ) VALUES (
      org_a, terminal_run, 2, 'transient_retry', 'vertex-ai', 'gemini-2.5-flash',
      'model-config-2026-08-24', 'gst-extraction-2026-08-24',
      'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'
    );
  EXCEPTION WHEN OTHERS THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'terminal source analysis run accepted a new attempt'; END IF;

  INSERT INTO public.source_analysis_runs(
    id, org_id, asset_id, request_key, analysis_kind, analysis_state,
    provider, model_identifier, model_config_version, prompt_version,
    schema_version, catalogue_version, normalizer_version
  ) VALUES (
    stale_run, org_a, asset_a, 'analysis.provenance.stale-lease', 'ai_extraction', 'queued',
    'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24',
    'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'
  );
  UPDATE public.source_analysis_runs
  SET state = 'running', analysis_state = 'running', started_at = now() - interval '10 minutes',
      lease_token = gen_random_uuid(), lease_expires_at = now() - interval '1 minute', heartbeat_at = now() - interval '10 minutes'
  WHERE id = stale_run;
  rejected := false;
  BEGIN
    UPDATE public.source_analysis_runs
    SET state = 'succeeded', analysis_state = 'validated', completed_at = now()
    WHERE id = stale_run;
  EXCEPTION WHEN OTHERS THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'expired AI lease completed a source analysis run'; END IF;
  UPDATE public.source_analysis_runs
  SET state = 'queued', analysis_state = 'queued', started_at = NULL, lease_token = NULL,
      lease_expires_at = NULL, heartbeat_at = now(), safe_error_code = 'work_requeued'
  WHERE id = stale_run;
  IF (SELECT analysis_state FROM public.source_analysis_runs WHERE id = stale_run) <> 'queued' THEN
    RAISE EXCEPTION 'expired AI analysis lease was not replayable through the controlled path';
  END IF;

  INSERT INTO public.source_analysis_runs(
    id, org_id, asset_id, request_key, analysis_kind, analysis_state,
    provider, model_identifier, model_config_version, prompt_version,
    schema_version, catalogue_version, normalizer_version
  ) VALUES (
    retry_run, org_a, asset_a, 'analysis.provenance.retry-sequence', 'ai_extraction', 'queued',
    'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24',
    'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'
  );
  rejected := false;
  BEGIN
    INSERT INTO public.source_analysis_attempts(
      org_id, source_analysis_run_id, attempt_number, retry_reason, provider, model_identifier,
      model_config_version, prompt_version, schema_version, catalogue_version, normalizer_version
    ) VALUES (
      org_a, retry_run, 2, 'transient_retry', 'vertex-ai', 'gemini-2.5-flash',
      'model-config-2026-08-24', 'gst-extraction-2026-08-24',
      'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'
    );
  EXCEPTION WHEN OTHERS THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'retry sequence skipped its initial attempt'; END IF;
  INSERT INTO public.source_analysis_attempts(
    org_id, source_analysis_run_id, attempt_number, provider, model_identifier,
    model_config_version, prompt_version, schema_version, catalogue_version, normalizer_version
  ) VALUES (
    org_a, retry_run, 1, 'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24',
    'gst-extraction-2026-08-24', 'source-analysis-schema-2026-08-24',
    'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'
  );
  UPDATE public.source_analysis_attempts
  SET state = 'running', started_at = now(), provider_request_id = 'retry-request-1'
  WHERE source_analysis_run_id = retry_run AND attempt_number = 1;
  UPDATE public.source_analysis_attempts
  SET state = 'provider_failed', failed_at = now(), safe_error_category = 'timeout', safe_error_code = 'provider_timeout'
  WHERE source_analysis_run_id = retry_run AND attempt_number = 1;
  rejected := false;
  BEGIN
    INSERT INTO public.source_analysis_attempts(
      org_id, source_analysis_run_id, attempt_number, retry_reason, provider, model_identifier,
      model_config_version, prompt_version, schema_version, catalogue_version, normalizer_version
    ) VALUES (
      org_a, retry_run, 2, 'invalid_output_regeneration', 'vertex-ai', 'gemini-2.5-flash',
      'model-config-2026-08-24', 'gst-extraction-2026-08-24',
      'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'
    );
  EXCEPTION WHEN OTHERS THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'invalid-output regeneration accepted a provider failure'; END IF;
  INSERT INTO public.source_analysis_attempts(
    org_id, source_analysis_run_id, attempt_number, retry_reason, provider, model_identifier,
    model_config_version, prompt_version, schema_version, catalogue_version, normalizer_version
  ) VALUES (
    org_a, retry_run, 2, 'transient_retry', 'vertex-ai', 'gemini-2.5-flash',
    'model-config-2026-08-24', 'gst-extraction-2026-08-24',
    'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'
  );
  UPDATE public.source_analysis_attempts
  SET state = 'running', started_at = now(), provider_request_id = 'retry-request-2'
  WHERE source_analysis_run_id = retry_run AND attempt_number = 2;
  UPDATE public.source_analysis_attempts
  SET state = 'provider_failed', failed_at = now(), safe_error_category = 'throttled', safe_error_code = 'provider_throttled'
  WHERE source_analysis_run_id = retry_run AND attempt_number = 2;
  INSERT INTO public.source_analysis_attempts(
    org_id, source_analysis_run_id, attempt_number, retry_reason, provider, model_identifier,
    model_config_version, prompt_version, schema_version, catalogue_version, normalizer_version
  ) VALUES (
    org_a, retry_run, 3, 'transient_retry', 'vertex-ai', 'gemini-2.5-flash',
    'model-config-2026-08-24', 'gst-extraction-2026-08-24',
    'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'
  );
  rejected := false;
  BEGIN
    INSERT INTO public.source_analysis_attempts(
      org_id, source_analysis_run_id, attempt_number, retry_reason, provider, model_identifier,
      model_config_version, prompt_version, schema_version, catalogue_version, normalizer_version
    ) VALUES (
      org_a, retry_run, 4, 'transient_retry', 'vertex-ai', 'gemini-2.5-flash',
      'model-config-2026-08-24', 'gst-extraction-2026-08-24',
      'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'
    );
  EXCEPTION WHEN OTHERS THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'source analysis retries exceeded the capped limit'; END IF;
END $ai_lease_and_retry_fences$;

DO $supersession_fences$
DECLARE
  org_a uuid := '63000000-0000-0000-0000-000000000001';
  asset_a uuid := '63200000-0000-0000-0000-000000000001';
  cycle_a uuid := '63800000-0000-0000-0000-000000000001';
  cycle_b uuid := '63800000-0000-0000-0000-000000000002';
  older uuid := '63800000-0000-0000-0000-000000000003';
  newer uuid := '63800000-0000-0000-0000-000000000004';
  rejected boolean := false;
BEGIN
  INSERT INTO public.source_analysis_runs(
    id, org_id, asset_id, request_key, analysis_kind, analysis_state, created_at,
    provider, model_identifier, model_config_version, prompt_version, schema_version, catalogue_version, normalizer_version
  ) VALUES
    (cycle_a, org_a, asset_a, 'analysis.provenance.cycle-a', 'ai_extraction', 'queued', now(),
      'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24', 'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'),
    (older, org_a, asset_a, 'analysis.provenance.older', 'ai_extraction', 'queued', now() - interval '2 minutes',
      'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24', 'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'),
    (newer, org_a, asset_a, 'analysis.provenance.newer', 'ai_extraction', 'queued', now(),
      'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24', 'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24');
  INSERT INTO public.source_analysis_runs(
    id, org_id, asset_id, request_key, analysis_kind, analysis_state, created_at, superseded_by_run_id,
    provider, model_identifier, model_config_version, prompt_version, schema_version, catalogue_version, normalizer_version
  ) VALUES (
    cycle_b, org_a, asset_a, 'analysis.provenance.cycle-b', 'ai_extraction', 'queued',
    (SELECT created_at FROM public.source_analysis_runs WHERE id = cycle_a), cycle_a,
    'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24', 'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'
  );
  rejected := false;
  BEGIN
    UPDATE public.source_analysis_runs SET superseded_by_run_id = cycle_b WHERE id = cycle_a;
  EXCEPTION WHEN OTHERS THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'source analysis supersession cycle was accepted'; END IF;
  rejected := false;
  BEGIN
    UPDATE public.source_analysis_runs SET superseded_by_run_id = older WHERE id = newer;
  EXCEPTION WHEN OTHERS THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'source analysis supersession accepted an older run'; END IF;
  rejected := false;
  BEGIN
    UPDATE public.source_analysis_runs SET superseded_by_run_id = cycle_a WHERE id = cycle_a;
  EXCEPTION WHEN OTHERS THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'source analysis supersession accepted self-reference'; END IF;
END $supersession_fences$;

SET LOCAL ROLE service_role;
DO $service_is_not_a_table_authority$
DECLARE denied boolean := false;
BEGIN
  BEGIN PERFORM 1 FROM public.source_analysis_runs LIMIT 1; EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role could read source analysis runs directly'; END IF;
  denied := false;
  BEGIN PERFORM 1 FROM public.source_analysis_attempts LIMIT 1; EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role could read source analysis attempts directly'; END IF;
END $service_is_not_a_table_authority$;
RESET ROLE;

SET LOCAL ROLE authenticated;
DO $browser_is_denied$
DECLARE denied boolean := false;
BEGIN
  BEGIN PERFORM 1 FROM public.source_analysis_runs LIMIT 1; EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'browser role could read source analysis runs'; END IF;
  denied := false;
  BEGIN PERFORM 1 FROM public.source_analysis_attempts LIMIT 1; EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'browser role could read source analysis attempts'; END IF;
END $browser_is_denied$;
RESET ROLE;

DO $surface$
BEGIN
  IF NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid = 'public.source_analysis_runs'::regclass)
     OR NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid = 'public.source_analysis_attempts'::regclass)
     OR EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename IN ('source_analysis_runs', 'source_analysis_attempts')
     )
     OR has_table_privilege('authenticated', 'public.source_analysis_runs', 'SELECT')
     OR has_table_privilege('authenticated', 'public.source_analysis_attempts', 'SELECT')
     OR has_table_privilege('service_role', 'public.source_analysis_runs', 'SELECT')
     OR has_table_privilege('service_role', 'public.source_analysis_attempts', 'SELECT') THEN
    RAISE EXCEPTION 'source analysis provenance RLS or table authority surface is unsafe';
  END IF;
END $surface$;

ROLLBACK;
