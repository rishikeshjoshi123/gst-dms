-- Run after migration 00067 against a disposable local Supabase database.
-- Rollback-only: validates the fenced processing provenance command, exact
-- claimed identity, expired nested-lease recovery, and safe Review terminality.
BEGIN;

DO $setup$
DECLARE
  org_id uuid := '67000000-0000-0000-0000-000000000001';
  actor_id uuid := '67100000-0000-0000-0000-000000000001';
  client_id uuid := '67200000-0000-0000-0000-000000000001';
  matter_id uuid := '67300000-0000-0000-0000-000000000001';
  document_id uuid := '67400000-0000-0000-0000-000000000001';
  asset_id uuid := '67500000-0000-0000-0000-000000000001';
  version_id uuid := '67600000-0000-0000-0000-000000000001';
  processing_run_id uuid := '67700000-0000-0000-0000-000000000001';
  processing_lease uuid := '67800000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000', actor_id, 'authenticated', 'authenticated', 'provenance-write@example.test', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
  INSERT INTO public.organisations(id, name, created_by) VALUES (org_id, 'Provenance write fixture', actor_id);
  INSERT INTO public.clients(id, org_id, name) VALUES (client_id, org_id, 'Fixture client');
  INSERT INTO public.matters(id, org_id, client_id, title) VALUES (matter_id, org_id, client_id, 'Fixture matter');
  INSERT INTO public.documents(id, org_id, matter_id, storage_path, created_by) VALUES (document_id, org_id, matter_id, 'legacy/fixture.pdf', actor_id);
  INSERT INTO public.file_assets(id, org_id, bucket_id, object_key, sha256, byte_size, detected_mime_type, availability, validated_at, validated_page_count, created_by)
  VALUES (asset_id, org_id, 'documents', 'orgs/' || org_id::text || '/assets/' || asset_id::text || '/original.pdf', repeat('a', 64), 99, 'application/pdf', 'available', now(), 2, actor_id);
  INSERT INTO public.document_versions(id, org_id, document_id, asset_id, version_number, original_filename, page_count, validation_state, state, validated_at, promoted_at, created_by)
  VALUES (version_id, org_id, document_id, asset_id, 1, 'fixture.pdf', 2, 'valid', 'current', now(), now(), actor_id);
  UPDATE public.documents SET current_version_id = version_id WHERE id = document_id;
  INSERT INTO public.document_processing_runs(id, org_id, document_id, document_version_id, scope, idempotency_key, state, stage, started_at, lease_token, lease_expires_at, heartbeat_at)
  VALUES (processing_run_id, org_id, document_id, version_id, 'full', 'fixture.provenance.write', 'running', 'extracting', now(), processing_lease, now() + interval '10 minutes', now());
END $setup$;

DO $command_contract$
DECLARE
  org_id uuid := '67000000-0000-0000-0000-000000000001';
  actor_id uuid := '67100000-0000-0000-0000-000000000001';
  client_id uuid := '67200000-0000-0000-0000-000000000001';
  matter_id uuid := '67300000-0000-0000-0000-000000000001';
  document_id uuid := '67400000-0000-0000-0000-000000000001';
  version_id uuid := '67600000-0000-0000-0000-000000000001';
  processing_run_id uuid := '67700000-0000-0000-0000-000000000001';
  processing_lease uuid := '67800000-0000-0000-0000-000000000001';
  unrelated_source_id uuid := '67900000-0000-0000-0000-000000000001';
  unrelated_source_lease uuid := '68000000-0000-0000-0000-000000000001';
  first_claim record; recovered_claim record; finish_result record; rejected record;
BEGIN
  SELECT * INTO rejected FROM public.begin_document_processing_ai_extraction(
    processing_run_id, processing_lease, 'vertex-ai', 'gemini-2.5-flash', 'fixture-model', 'fixture-prompt', 'fixture-schema', 'fixture-catalogue', 'fixture-normalizer',
    document_id, version_id, matter_id, org_id, 'documents', 'wrong/object.pdf', actor_id
  );
  IF rejected.code <> 'claimed_identity_mismatch' THEN RAISE EXCEPTION 'mismatched processing payload was not rejected'; END IF;

  UPDATE public.document_versions SET page_count = 3 WHERE id = version_id;
  SELECT * INTO rejected FROM public.begin_document_processing_ai_extraction(
    processing_run_id, processing_lease, 'vertex-ai', 'gemini-2.5-flash', 'fixture-model', 'fixture-prompt', 'fixture-schema', 'fixture-catalogue', 'fixture-normalizer',
    document_id, version_id, matter_id, org_id, 'documents', 'orgs/' || org_id::text || '/assets/67500000-0000-0000-0000-000000000001/original.pdf', actor_id
  );
  IF rejected.code <> 'claimed_identity_mismatch' THEN
    RAISE EXCEPTION 'version page count that disagrees with validated asset count was accepted';
  END IF;
  UPDATE public.document_versions SET page_count = 2 WHERE id = version_id;

  SELECT * INTO first_claim FROM public.begin_document_processing_ai_extraction(
    processing_run_id, processing_lease, 'vertex-ai', 'gemini-2.5-flash', 'fixture-model', 'fixture-prompt', 'fixture-schema', 'fixture-catalogue', 'fixture-normalizer',
    document_id, version_id, matter_id, org_id, 'documents', 'orgs/' || org_id::text || '/assets/67500000-0000-0000-0000-000000000001/original.pdf', actor_id
  );
  IF first_claim.code <> 'claimed' OR first_claim.page_count <> 2 THEN RAISE EXCEPTION 'valid processing provenance claim failed'; END IF;

  UPDATE public.source_analysis_runs SET lease_expires_at = now() - interval '1 second' WHERE id = first_claim.source_analysis_run_id;
  SELECT * INTO recovered_claim FROM public.begin_document_processing_ai_extraction(
    processing_run_id, processing_lease, 'vertex-ai', 'gemini-2.5-flash', 'fixture-model', 'fixture-prompt', 'fixture-schema', 'fixture-catalogue', 'fixture-normalizer',
    document_id, version_id, matter_id, org_id, 'documents', 'orgs/' || org_id::text || '/assets/67500000-0000-0000-0000-000000000001/original.pdf', actor_id
  );
  IF recovered_claim.code <> 'claimed'
     OR (SELECT count(*) FROM public.source_analysis_attempts WHERE source_analysis_run_id = first_claim.source_analysis_run_id AND state = 'provider_failed') <> 1
     OR (SELECT count(*) FROM public.source_analysis_attempts WHERE source_analysis_run_id = first_claim.source_analysis_run_id AND state = 'running') <> 1 THEN
    RAISE EXCEPTION 'expired source lease was not safely recovered into a bounded retry';
  END IF;

  -- A different AI run for the same immutable asset is never an acceptable
  -- finalization target for this processing claim.
  INSERT INTO public.source_analysis_runs(
    id, org_id, asset_id, request_key, idempotency_key,
    analysis_kind, analysis_state, state, provider, model_identifier,
    model_config_version, prompt_version, schema_version, catalogue_version,
    normalizer_version, started_at, lease_token, lease_expires_at, heartbeat_at
  ) VALUES (
    unrelated_source_id, org_id, '67500000-0000-0000-0000-000000000001',
    'ai_extraction.unrelated', 'ai_extraction.unrelated',
    'ai_extraction', 'running', 'running', 'vertex-ai', 'gemini-2.5-flash',
    'fixture-model', 'fixture-prompt', 'fixture-schema', 'fixture-catalogue',
    'fixture-normalizer', now(), unrelated_source_lease, now() + interval '10 minutes', now()
  );
  SELECT * INTO rejected FROM public.finish_document_processing_ai_extraction(
    processing_run_id, processing_lease, unrelated_source_id, unrelated_source_lease,
    'review_required', 0, 0, 1, '[]'::jsonb, true, NULL
  );
  IF rejected.code <> 'source_identity_invalid' THEN
    RAISE EXCEPTION 'same-asset but mismatched source run was accepted';
  END IF;

  UPDATE public.documents
  SET deleted_at = now(), record_state = 'trashed', trashed_at = now()
  WHERE id = document_id;
  SELECT * INTO rejected FROM public.finish_document_processing_ai_extraction(
    processing_run_id, processing_lease, recovered_claim.source_analysis_run_id, recovered_claim.source_analysis_lease_token,
    'review_required', 0, 0, 1, '[]'::jsonb, true, NULL
  );
  IF rejected.code <> 'target_lifecycle_invalid' THEN
    RAISE EXCEPTION 'deleted or non-active document was accepted for provenance finalization';
  END IF;
  UPDATE public.documents
  SET deleted_at = NULL, record_state = 'active', trashed_at = NULL
  WHERE id = document_id;

  UPDATE public.matters SET status = 'closed' WHERE id = matter_id;
  SELECT * INTO rejected FROM public.finish_document_processing_ai_extraction(
    processing_run_id, processing_lease, recovered_claim.source_analysis_run_id, recovered_claim.source_analysis_lease_token,
    'review_required', 0, 0, 1, '[]'::jsonb, true, NULL
  );
  IF rejected.code <> 'target_lifecycle_invalid' THEN
    RAISE EXCEPTION 'inactive matter was accepted for provenance finalization';
  END IF;
  UPDATE public.matters SET status = 'active' WHERE id = matter_id;

  UPDATE public.clients SET deleted_at = now() WHERE id = client_id;
  SELECT * INTO rejected FROM public.finish_document_processing_ai_extraction(
    processing_run_id, processing_lease, recovered_claim.source_analysis_run_id, recovered_claim.source_analysis_lease_token,
    'review_required', 0, 0, 1, '[]'::jsonb, true, NULL
  );
  IF rejected.code <> 'target_lifecycle_invalid'
     OR (SELECT analysis_state FROM public.source_analysis_runs WHERE id = recovered_claim.source_analysis_run_id) <> 'running'
     OR EXISTS (SELECT 1 FROM public.source_field_candidates WHERE source_analysis_run_id = recovered_claim.source_analysis_run_id) THEN
    RAISE EXCEPTION 'deleted client was accepted or lifecycle rejection wrote provenance metadata';
  END IF;
  UPDATE public.clients SET deleted_at = NULL WHERE id = client_id;

  SELECT * INTO finish_result FROM public.finish_document_processing_ai_extraction(
    processing_run_id, processing_lease, recovered_claim.source_analysis_run_id, recovered_claim.source_analysis_lease_token,
    'review_required', 0, 0, 1, '[]'::jsonb, true, NULL
  );
  IF finish_result.code <> 'review_required'
     OR (SELECT analysis_state FROM public.source_analysis_runs WHERE id = recovered_claim.source_analysis_run_id) <> 'review_required'
     OR (SELECT status FROM public.documents WHERE id = document_id) <> 'needs_review'
     OR EXISTS (SELECT 1 FROM public.source_field_candidates WHERE source_analysis_run_id = recovered_claim.source_analysis_run_id) THEN
    RAISE EXCEPTION 'candidate-domain Review did not terminalize safely';
  END IF;
END $command_contract$;

SET LOCAL ROLE authenticated;
DO $browser_denied$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.begin_document_processing_ai_extraction(
      '67700000-0000-0000-0000-000000000001', '67800000-0000-0000-0000-000000000001',
      'vertex-ai', 'gemini-2.5-flash', 'fixture-model', 'fixture-prompt', 'fixture-schema', 'fixture-catalogue', 'fixture-normalizer',
      '67400000-0000-0000-0000-000000000001', '67600000-0000-0000-0000-000000000001', '67300000-0000-0000-0000-000000000001', '67000000-0000-0000-0000-000000000001',
      'documents', 'orgs/67000000-0000-0000-0000-000000000001/assets/67500000-0000-0000-0000-000000000001/original.pdf', '67100000-0000-0000-0000-000000000001'
    );
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'browser role could claim processing provenance'; END IF;
END $browser_denied$;
RESET ROLE;

ROLLBACK;
