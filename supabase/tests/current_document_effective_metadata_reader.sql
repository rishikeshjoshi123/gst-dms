-- Run after migration 00069 against a disposable local Supabase database.
-- Rollback-only: verifies the bounded service reader exposes only current,
-- active, same-organisation effective projection rows.
BEGIN;

DO $setup$
DECLARE
  org_a uuid := '68000000-0000-0000-0000-000000000001'; org_b uuid := '68000000-0000-0000-0000-000000000002';
  actor_a uuid := '68100000-0000-0000-0000-000000000001'; actor_b uuid := '68100000-0000-0000-0000-000000000002';
  client_a uuid := '68200000-0000-0000-0000-000000000001'; client_b uuid := '68200000-0000-0000-0000-000000000002';
  matter_a uuid := '68300000-0000-0000-0000-000000000001'; matter_b uuid := '68300000-0000-0000-0000-000000000002';
  document_a uuid := '68400000-0000-0000-0000-000000000001'; document_b uuid := '68400000-0000-0000-0000-000000000002';
  asset_a uuid := '68500000-0000-0000-0000-000000000001'; asset_b uuid := '68500000-0000-0000-0000-000000000002'; asset_old_a uuid := '68500000-0000-0000-0000-000000000003';
  current_version_a uuid := '68600000-0000-0000-0000-000000000001'; superseded_version_a uuid := '68600000-0000-0000-0000-000000000002'; current_version_b uuid := '68600000-0000-0000-0000-000000000003';
  run_a uuid := '68700000-0000-0000-0000-000000000001'; run_b uuid := '68700000-0000-0000-0000-000000000002'; run_old_a uuid := '68700000-0000-0000-0000-000000000003';
BEGIN
  INSERT INTO auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
    ('00000000-0000-0000-0000-000000000000', actor_a, 'authenticated', 'authenticated', 'effective-reader-a@example.test', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    ('00000000-0000-0000-0000-000000000000', actor_b, 'authenticated', 'authenticated', 'effective-reader-b@example.test', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
  INSERT INTO public.organisations(id, name, created_by) VALUES (org_a, 'Effective reader A', actor_a), (org_b, 'Effective reader B', actor_b);
  INSERT INTO public.clients(id, org_id, name) VALUES (client_a, org_a, 'A client'), (client_b, org_b, 'B client');
  INSERT INTO public.matters(id, org_id, client_id, title) VALUES (matter_a, org_a, client_a, 'A matter'), (matter_b, org_b, client_b, 'B matter');
  INSERT INTO public.documents(id, org_id, matter_id, storage_path, created_by) VALUES
    (document_a, org_a, matter_a, 'legacy/a.pdf', actor_a), (document_b, org_b, matter_b, 'legacy/b.pdf', actor_b);
  INSERT INTO public.file_assets(id, org_id, bucket_id, object_key, sha256, byte_size, detected_mime_type, availability, validated_at, validated_page_count, created_by) VALUES
    (asset_a, org_a, 'documents', 'orgs/' || org_a::text || '/assets/' || asset_a::text || '/original.pdf', repeat('a', 64), 41, 'application/pdf', 'available', now(), 2, actor_a),
    (asset_b, org_b, 'documents', 'orgs/' || org_b::text || '/assets/' || asset_b::text || '/original.pdf', repeat('b', 64), 43, 'application/pdf', 'available', now(), 2, actor_b),
    (asset_old_a, org_a, 'documents', 'orgs/' || org_a::text || '/assets/' || asset_old_a::text || '/original.pdf', repeat('c', 64), 45, 'application/pdf', 'available', now(), 2, actor_a);
  INSERT INTO public.document_versions(id, org_id, document_id, asset_id, version_number, original_filename, page_count, validation_state, state, validated_at, promoted_at, superseded_at, created_by) VALUES
    (current_version_a, org_a, document_a, asset_a, 2, 'a-current.pdf', 2, 'valid', 'current', now(), now(), NULL, actor_a),
    (superseded_version_a, org_a, document_a, asset_old_a, 1, 'a-old.pdf', 2, 'valid', 'superseded', now(), now(), now(), actor_a),
    (current_version_b, org_b, document_b, asset_b, 1, 'b-current.pdf', 2, 'valid', 'current', now(), now(), NULL, actor_b);
  UPDATE public.documents SET current_version_id = current_version_a WHERE id = document_a;
  UPDATE public.documents SET current_version_id = current_version_b WHERE id = document_b;
  INSERT INTO public.source_analysis_runs(id, org_id, asset_id, request_key, idempotency_key, analysis_kind, analysis_state, state, started_at, completed_at, lease_token, lease_expires_at, provider, model_identifier, model_config_version, prompt_version, schema_version, catalogue_version, normalizer_version) VALUES
    (run_a, org_a, asset_a, 'analysis.effective-reader.a', 'analysis.effective-reader.a', 'ai_extraction', 'validated', 'succeeded', now() - interval '2 minutes', now() - interval '1 minute', gen_random_uuid(), now() + interval '1 minute', 'vertex-ai', 'gemini-2.5-flash', 'fixture-model', 'fixture-prompt', 'fixture-schema', 'fixture-catalogue', 'fixture-normalizer'),
    (run_b, org_b, asset_b, 'analysis.effective-reader.b', 'analysis.effective-reader.b', 'ai_extraction', 'validated', 'succeeded', now() - interval '2 minutes', now() - interval '1 minute', gen_random_uuid(), now() + interval '1 minute', 'vertex-ai', 'gemini-2.5-flash', 'fixture-model', 'fixture-prompt', 'fixture-schema', 'fixture-catalogue', 'fixture-normalizer'),
    (run_old_a, org_a, asset_old_a, 'analysis.effective-reader.a-old', 'analysis.effective-reader.a-old', 'ai_extraction', 'validated', 'succeeded', now() - interval '2 minutes', now() - interval '1 minute', gen_random_uuid(), now() + interval '1 minute', 'vertex-ai', 'gemini-2.5-flash', 'fixture-model', 'fixture-prompt', 'fixture-schema', 'fixture-catalogue', 'fixture-normalizer');
  PERFORM public.materialize_source_field_candidate(run_a, 'document.reference.current', 'document.reference_number', 'text', '"CURRENT/A"'::jsonb, 1, 'Current reference', NULL, 0.99, 'eligible', NULL);
  PERFORM public.materialize_source_field_candidate(run_b, 'document.reference.current', 'document.reference_number', 'text', '"CURRENT/B"'::jsonb, 1, 'Current reference', NULL, 0.99, 'eligible', NULL);
  PERFORM public.materialize_source_field_candidate(run_old_a, 'document.reference.old', 'document.reference_number', 'text', '"OLD/A"'::jsonb, 1, 'Old reference', NULL, 0.99, 'eligible', NULL);
  PERFORM public.materialize_document_version_analysis(current_version_a, run_a, 'placement', actor_a);
  PERFORM public.materialize_document_version_analysis(superseded_version_a, run_old_a, 'replacement_history', actor_a);
  PERFORM public.materialize_document_version_analysis(current_version_b, run_b, 'placement', actor_b);
END $setup$;

SET LOCAL ROLE service_role;
DO $service_reader_contract$
DECLARE
  row_count integer;
  projection_row record;
  reader_definition text;
BEGIN
  SELECT count(*) INTO row_count
  FROM public.read_current_document_effective_metadata(
    '68000000-0000-0000-0000-000000000001',
    ARRAY[
      '68400000-0000-0000-0000-000000000001'::uuid,
      '68400000-0000-0000-0000-000000000002'::uuid
    ]
  );
  IF row_count <> 1
     OR (SELECT count(*) FROM public.read_current_document_effective_metadata(
       '68000000-0000-0000-0000-000000000001',
       ARRAY['68400000-0000-0000-0000-000000000001'::uuid]
     ) WHERE document_version_id = '68600000-0000-0000-0000-000000000001') <> 1
     OR EXISTS (
       SELECT 1 FROM public.read_current_document_effective_metadata(
         '68000000-0000-0000-0000-000000000001',
         ARRAY['68400000-0000-0000-0000-000000000001'::uuid]
       ) WHERE document_version_id = '68600000-0000-0000-0000-000000000002'
     )
     OR EXISTS (
       SELECT 1 FROM public.read_current_document_effective_metadata(
         '68000000-0000-0000-0000-000000000001',
         ARRAY['68400000-0000-0000-0000-000000000001'::uuid]
     ) WHERE normalized_value = '"OLD/A"'::jsonb
     ) THEN
    RAISE EXCEPTION 'current effective metadata reader did not scope document versions or organisation correctly';
  END IF;
  SELECT * INTO projection_row
  FROM public.read_current_document_search_index_projection(
    '68000000-0000-0000-0000-000000000001',
    ARRAY['68400000-0000-0000-0000-000000000001'::uuid]
  );
  IF projection_row.document_id <> '68400000-0000-0000-0000-000000000001'::uuid
     OR projection_row.document_version_id <> '68600000-0000-0000-0000-000000000001'::uuid
     OR projection_row.reference_number <> 'CURRENT/A'
     OR cardinality(projection_row.financial_years) <> 0 THEN
    RAISE EXCEPTION 'current effective Search projection did not retain bounded current values';
  END IF;
  UPDATE public.document_versions
  SET state = 'pending'::public.document_version_state,
      validation_state = 'pending'::public.document_version_validation_state,
      validated_at = NULL,
      promoted_at = NULL
  WHERE id = '68600000-0000-0000-0000-000000000001'::uuid;
  IF EXISTS (
    SELECT 1 FROM public.read_current_document_effective_metadata(
      '68000000-0000-0000-0000-000000000001',
      ARRAY['68400000-0000-0000-0000-000000000001'::uuid]
    )
  ) THEN
    RAISE EXCEPTION 'current effective metadata reader accepted a non-current version';
  END IF;
  UPDATE public.document_versions
  SET state = 'current'::public.document_version_state,
      validation_state = 'valid'::public.document_version_validation_state,
      validated_at = now(),
      promoted_at = now()
  WHERE id = '68600000-0000-0000-0000-000000000001'::uuid;
  SELECT pg_get_functiondef('public.read_current_document_effective_metadata(uuid,uuid[])'::regprocedure)
  INTO reader_definition;
  IF reader_definition !~ 'version\.state = ''current'''
     OR reader_definition !~ 'version\.validation_state = ''valid''' THEN
    RAISE EXCEPTION 'current effective metadata reader did not require a current valid version';
  END IF;
END $service_reader_contract$;
RESET ROLE;

SET LOCAL ROLE authenticated;
DO $browser_denied$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    PERFORM 1 FROM public.read_current_document_effective_metadata(
      '68000000-0000-0000-0000-000000000001',
      ARRAY['68400000-0000-0000-0000-000000000001'::uuid]
    );
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'browser role could read secured effective metadata'; END IF;
END $browser_denied$;
RESET ROLE;

DO $surface$
BEGIN
  IF has_function_privilege('authenticated', 'public.read_current_document_effective_metadata(uuid,uuid[])', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.read_current_document_effective_metadata(uuid,uuid[])', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.read_current_document_search_index_projection(uuid,uuid[])', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.read_current_document_search_index_projection(uuid,uuid[])', 'EXECUTE')
     OR has_table_privilege('service_role', 'public.document_effective_metadata', 'SELECT') THEN
    RAISE EXCEPTION 'current effective metadata reader authority surface is unsafe';
  END IF;
END $surface$;

ROLLBACK;
