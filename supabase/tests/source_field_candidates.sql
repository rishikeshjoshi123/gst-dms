-- Run after migration 00064 against a disposable local Supabase database.
-- Rollback-only: candidate values and quotations are synthetic bounded test
-- fixtures, never raw provider responses or production legal content.
BEGIN;

DO $setup$
DECLARE
  org_a uuid := '64000000-0000-0000-0000-000000000001';
  org_b uuid := '64000000-0000-0000-0000-000000000002';
  actor_a uuid := '64100000-0000-0000-0000-000000000001';
  actor_b uuid := '64100000-0000-0000-0000-000000000002';
  asset_a uuid := '64200000-0000-0000-0000-000000000001';
  asset_b uuid := '64200000-0000-0000-0000-000000000002';
  asset_unvalidated uuid := '64200000-0000-0000-0000-000000000003';
  asset_non_pdf uuid := '64200000-0000-0000-0000-000000000004';
  run_a uuid := '64300000-0000-0000-0000-000000000001';
  queued_run uuid := '64300000-0000-0000-0000-000000000002';
  unvalidated_run uuid := '64300000-0000-0000-0000-000000000003';
  non_pdf_run uuid := '64300000-0000-0000-0000-000000000004';
BEGIN
  INSERT INTO auth.users(
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES
    ('00000000-0000-0000-0000-000000000000', actor_a, 'authenticated', 'authenticated',
      'source-candidate-a@example.test', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    ('00000000-0000-0000-0000-000000000000', actor_b, 'authenticated', 'authenticated',
      'source-candidate-b@example.test', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
  INSERT INTO public.organisations(id, name, created_by) VALUES
    (org_a, 'Source candidate A', actor_a),
    (org_b, 'Source candidate B', actor_b);
  INSERT INTO public.file_assets(
    id, org_id, bucket_id, object_key, sha256, byte_size, detected_mime_type,
    availability, validated_at, validated_page_count, created_by
  ) VALUES
    (asset_a, org_a, 'documents', 'orgs/' || org_a::text || '/assets/' || asset_a::text || '/original.pdf',
      repeat('a', 64), 17, 'application/pdf', 'available', now(), 2, actor_a),
    (asset_b, org_b, 'documents', 'orgs/' || org_b::text || '/assets/' || asset_b::text || '/original.pdf',
      repeat('b', 64), 19, 'application/pdf', 'available', now(), 1, actor_b),
    (asset_unvalidated, org_a, 'documents', 'orgs/' || org_a::text || '/assets/' || asset_unvalidated::text || '/original.pdf',
      repeat('c', 64), 23, 'application/pdf', 'uploaded', NULL, 1, actor_a),
    (asset_non_pdf, org_a, 'documents', 'orgs/' || org_a::text || '/assets/' || asset_non_pdf::text || '/original.pdf',
      repeat('d', 64), 29, 'text/plain', 'available', now(), 1, actor_a);
  INSERT INTO public.source_analysis_runs(
    id, org_id, asset_id, request_key, idempotency_key, analysis_kind, analysis_state,
    state, started_at, completed_at, lease_token, lease_expires_at,
    provider, model_identifier, model_config_version, prompt_version,
    schema_version, catalogue_version, normalizer_version
  ) VALUES
    (run_a, org_a, asset_a, 'analysis.source-candidate.a', 'analysis.source-candidate.a', 'ai_extraction', 'validated',
      'succeeded', now() - interval '1 minute', now(), gen_random_uuid(), now() + interval '1 minute',
      'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24',
      'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'),
    (queued_run, org_a, asset_a, 'analysis.source-candidate.queued', 'analysis.source-candidate.queued', 'ai_extraction', 'queued',
      'queued', NULL, NULL, NULL, NULL,
      'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24',
      'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'),
    (unvalidated_run, org_a, asset_unvalidated, 'analysis.source-candidate.unvalidated', 'analysis.source-candidate.unvalidated', 'ai_extraction', 'validated',
      'succeeded', now() - interval '1 minute', now(), gen_random_uuid(), now() + interval '1 minute',
      'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24',
      'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'),
    (non_pdf_run, org_a, asset_non_pdf, 'analysis.source-candidate.non-pdf', 'analysis.source-candidate.non-pdf', 'ai_extraction', 'validated',
      'succeeded', now() - interval '1 minute', now(), gen_random_uuid(), now() + interval '1 minute',
      'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24',
      'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24');
END $setup$;

DO $candidate_contract$
DECLARE
  org_b uuid := '64000000-0000-0000-0000-000000000002';
  asset_b uuid := '64200000-0000-0000-0000-000000000002';
  run_a uuid := '64300000-0000-0000-0000-000000000001';
  queued_run uuid := '64300000-0000-0000-0000-000000000002';
  unvalidated_run uuid := '64300000-0000-0000-0000-000000000003';
  non_pdf_run uuid := '64300000-0000-0000-0000-000000000004';
  candidate_a uuid;
  duplicate_candidate uuid;
  rejected boolean := false;
BEGIN
  candidate_a := public.materialize_source_field_candidate(
    run_a, 'document.reference_number.abc123', 'document.reference_number', 'code',
    '"ABC/123"'::jsonb, 2, 'Reference ABC/123',
    '[{"x":0.1,"y":0.2,"width":0.3,"height":0.1}]'::jsonb,
    0.9754, 'eligible', NULL
  );
  duplicate_candidate := public.materialize_source_field_candidate(
    run_a, 'document.reference_number.abc123', 'document.reference_number', 'code',
    '"ABC/123"'::jsonb, 2, 'Reference ABC/123',
    '[{"x":0.1,"y":0.2,"width":0.3,"height":0.1}]'::jsonb,
    0.975, 'eligible', NULL
  );
  IF candidate_a IS DISTINCT FROM duplicate_candidate
     OR (SELECT confidence FROM public.source_field_candidates WHERE id = candidate_a) <> 0.975
     OR (SELECT count(*) FROM public.source_field_candidates WHERE source_analysis_run_id = run_a) <> 1 THEN
    RAISE EXCEPTION 'candidate materialization did not normalize confidence idempotently';
  END IF;

  BEGIN
    PERFORM public.materialize_source_field_candidate(
      run_a, 'document.reference_number.abc123', 'document.reference_number', 'code',
      '"XYZ/987"'::jsonb, 2, 'Reference XYZ/987', NULL, 0.975, 'eligible', NULL
    );
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'candidate semantic-key collision overwrote materialized evidence'; END IF;

  rejected := false;
  BEGIN
    INSERT INTO public.source_field_candidates(
      org_id, source_analysis_run_id, asset_id, semantic_candidate_key, field_path,
      value_type, normalized_value, page_number, quotation, confidence, validation_state
    ) VALUES (
      org_b, run_a, asset_b, 'document.title.cross_tenant', 'document.title',
      'text', '"Cross tenant"'::jsonb, 1, 'Cross tenant', 0.8, 'eligible'
    );
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'cross-tenant candidate was accepted'; END IF;

  rejected := false;
  BEGIN
    PERFORM public.materialize_source_field_candidate(
      queued_run, 'document.title.queued', 'document.title', 'text',
      '"Queued title"'::jsonb, 1, 'Queued title', NULL, 0.8, 'eligible', NULL
    );
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'non-terminal run materialized a candidate'; END IF;

  rejected := false;
  BEGIN
    PERFORM public.materialize_source_field_candidate(
      unvalidated_run, 'document.title.unvalidated', 'document.title', 'text',
      '"Unvalidated title"'::jsonb, 1, 'Unvalidated title', NULL, 0.8, 'eligible', NULL
    );
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'unvalidated PDF asset materialized a candidate'; END IF;

  rejected := false;
  BEGIN
    PERFORM public.materialize_source_field_candidate(
      non_pdf_run, 'document.title.non_pdf', 'document.title', 'text',
      '"Non PDF title"'::jsonb, 1, 'Non PDF title', NULL, 0.8, 'eligible', NULL
    );
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'non-PDF asset materialized a candidate'; END IF;

  rejected := false;
  BEGIN
    PERFORM public.materialize_source_field_candidate(
      run_a, 'document.title.badpage', 'document.title', 'text',
      '"Short title"'::jsonb, 3, 'Short title', NULL, 0.8, 'eligible', NULL
    );
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'out-of-bounds candidate page was accepted'; END IF;

  IF (SELECT evidence_page_count FROM public.source_field_candidates WHERE id = candidate_a) <> 2 THEN
    RAISE EXCEPTION 'candidate did not snapshot its validated page boundary';
  END IF;
  rejected := false;
  BEGIN
    UPDATE public.file_assets SET validated_page_count = 1
    WHERE id = '64200000-0000-0000-0000-000000000001';
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'candidate evidence boundary allowed a later asset page-count shrink'; END IF;

  rejected := false;
  BEGIN
    PERFORM public.materialize_source_field_candidate(
      run_a, 'document.title.badregions', 'document.title', 'text',
      '"Short title"'::jsonb, 1, 'Short title', '[{"x":0,"y":0,"width":2,"height":1}]'::jsonb, 0.8, 'eligible', NULL
    );
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'invalid evidence region was accepted'; END IF;

  rejected := false;
  BEGIN
    PERFORM public.materialize_source_field_candidate(
      run_a, 'document.date.badvalue', 'document.date', 'date',
      '"2026-02-30"'::jsonb, 1, 'Date text', NULL, 0.8, 'eligible', NULL
    );
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'invalid typed normalized value was accepted'; END IF;

  rejected := false;
  BEGIN
    PERFORM public.materialize_source_field_candidate(
      run_a, 'document.title.confidence-out-of-range', 'document.title', 'text',
      '"Bounded confidence"'::jsonb, 1, 'Bounded confidence', NULL, 1.0001, 'eligible', NULL
    );
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'out-of-range confidence was accepted'; END IF;

  PERFORM public.materialize_source_field_candidate(
    run_a, 'document.title.invalid', 'document.title', 'text',
    '"Needs validation"'::jsonb, 1, 'Needs validation', NULL, 0.2, 'invalid', ARRAY['catalogue_mismatch']
  );
  rejected := false;
  BEGIN
    PERFORM public.materialize_source_field_candidate(
      run_a, 'document.title.invalid-null-errors', 'document.title', 'text',
      '"Needs validation"'::jsonb, 1, 'Needs validation', NULL, 0.2, 'invalid', NULL
    );
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'invalid candidate accepted null validation errors'; END IF;
  rejected := false;
  BEGIN
    PERFORM public.materialize_source_field_candidate(
      run_a, 'document.title.eligible-errors', 'document.title', 'text',
      '"Eligible title"'::jsonb, 1, 'Eligible title', NULL, 0.8, 'eligible', ARRAY['catalogue_mismatch']
    );
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'terminal valid candidate accepted validation errors'; END IF;

  rejected := false;
  BEGIN
    UPDATE public.source_field_candidates SET confidence = 0.5 WHERE id = candidate_a;
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'source candidate was mutable'; END IF;
  rejected := false;
  BEGIN
    DELETE FROM public.source_field_candidates WHERE id = candidate_a;
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'source candidate was deletable'; END IF;
END $candidate_contract$;

-- This rollback-only fixture runs in one transaction, so it cannot create a
-- second committed writer. Assert the command's parent-row lock directly;
-- the sequential exact-replay and collision cases above exercise the result
-- after that lock has serialized concurrent callers.
DO $materialization_serialization_contract$
BEGIN
  IF pg_get_functiondef(
       'public.materialize_source_field_candidate(uuid,text,text,public.source_field_candidate_value_type,jsonb,integer,text,jsonb,numeric,public.source_field_candidate_validation_state,text[])'::regprocedure
     ) !~ 'FOR UPDATE' THEN
    RAISE EXCEPTION 'source candidate materialization does not serialize on its parent run';
  END IF;
END $materialization_serialization_contract$;

SET LOCAL ROLE service_role;
DO $service_command_surface$
DECLARE
  run_a uuid := '64300000-0000-0000-0000-000000000001';
  denied boolean := false;
BEGIN
  BEGIN
    PERFORM 1 FROM public.source_field_candidates LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'service role could read source field candidates directly'; END IF;

  PERFORM public.materialize_source_field_candidate(
    run_a, 'document.direction.service', 'document.direction', 'code',
    '"incoming"'::jsonb, 1, 'Incoming', NULL, 0.9, 'provisional', NULL
  );
END $service_command_surface$;
RESET ROLE;

SET LOCAL ROLE authenticated;
DO $browser_is_denied$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    PERFORM 1 FROM public.source_field_candidates LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'browser role could read source field candidates'; END IF;
  denied := false;
  BEGIN
    PERFORM public.materialize_source_field_candidate(
      '64300000-0000-0000-0000-000000000001', 'document.direction.browser', 'document.direction', 'code',
      '"incoming"'::jsonb, 1, 'Incoming', NULL, 0.9, 'provisional', NULL
    );
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'browser role could materialize source candidates'; END IF;
END $browser_is_denied$;
RESET ROLE;

DO $surface$
BEGIN
  IF NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid = 'public.source_field_candidates'::regclass)
     OR EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'source_field_candidates')
     OR has_table_privilege('authenticated', 'public.source_field_candidates', 'SELECT')
     OR has_table_privilege('service_role', 'public.source_field_candidates', 'SELECT')
     OR has_function_privilege('authenticated', 'public.materialize_source_field_candidate(uuid,text,text,public.source_field_candidate_value_type,jsonb,integer,text,jsonb,numeric,public.source_field_candidate_validation_state,text[])', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.materialize_source_field_candidate(uuid,text,text,public.source_field_candidate_value_type,jsonb,integer,text,jsonb,numeric,public.source_field_candidate_validation_state,text[])', 'EXECUTE') THEN
    RAISE EXCEPTION 'source field candidate authority surface is unsafe';
  END IF;
END $surface$;

ROLLBACK;
