-- Canonical processing write path for validated AI extraction provenance.
--
-- The existing outbox/document-processing lease remains the outer durable
-- authority. These commands create a separate immutable AI run/attempt only
-- while that processing lease is live, then atomically materialize bounded
-- source and document candidates through the 00063--00066 authorities.
BEGIN;

CREATE FUNCTION public.begin_document_processing_ai_extraction(
  p_processing_run_id uuid,
  p_processing_lease_token uuid,
  p_provider text,
  p_model_identifier text,
  p_model_config_version text,
  p_prompt_version text,
  p_schema_version text,
  p_catalogue_version text,
  p_normalizer_version text,
  p_declared_document_id uuid,
  p_declared_document_version_id uuid,
  p_declared_matter_id uuid,
  p_declared_org_id uuid,
  p_declared_bucket_id text,
  p_declared_object_key text,
  p_declared_uploaded_by uuid
)
RETURNS TABLE(code text, source_analysis_run_id uuid, source_analysis_lease_token uuid, page_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  processing_run public.document_processing_runs%ROWTYPE;
  version_row public.document_versions%ROWTYPE;
  asset_row public.file_assets%ROWTYPE;
  document_row public.documents%ROWTYPE;
  matter_row public.matters%ROWTYPE;
  client_row public.clients%ROWTYPE;
  source_run public.source_analysis_runs%ROWTYPE;
  source_lease uuid;
  source_key text;
BEGIN
  IF p_processing_run_id IS NULL OR p_processing_lease_token IS NULL
     OR p_provider IS NULL OR p_model_identifier IS NULL
     OR p_model_config_version IS NULL OR p_prompt_version IS NULL
     OR p_schema_version IS NULL OR p_catalogue_version IS NULL
     OR p_normalizer_version IS NULL OR p_declared_document_id IS NULL
     OR p_declared_document_version_id IS NULL OR p_declared_matter_id IS NULL
     OR p_declared_org_id IS NULL OR p_declared_bucket_id IS NULL
     OR p_declared_object_key IS NULL OR p_declared_uploaded_by IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid, NULL::uuid, NULL::integer;
    RETURN;
  END IF;

  SELECT * INTO processing_run
  FROM public.document_processing_runs
  WHERE id = p_processing_run_id
  FOR UPDATE;
  IF processing_run.id IS NULL
     OR processing_run.state <> 'running'::public.document_processing_state
     OR processing_run.lease_token IS DISTINCT FROM p_processing_lease_token
     OR processing_run.lease_expires_at IS NULL
     OR processing_run.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'processing_lease_invalid'::text, NULL::uuid, NULL::uuid, NULL::integer;
    RETURN;
  END IF;

  SELECT * INTO version_row
  FROM public.document_versions
  WHERE id = processing_run.document_version_id
    AND org_id = processing_run.org_id
  FOR KEY SHARE;
  SELECT * INTO asset_row
  FROM public.file_assets
  WHERE id = version_row.asset_id AND org_id = version_row.org_id
  FOR KEY SHARE;
  SELECT * INTO document_row
  FROM public.documents
  WHERE id = processing_run.document_id AND org_id = processing_run.org_id
  FOR KEY SHARE;
  SELECT * INTO matter_row
  FROM public.matters
  WHERE id = document_row.matter_id AND org_id = processing_run.org_id
  FOR KEY SHARE;
  SELECT * INTO client_row
  FROM public.clients
  WHERE id = matter_row.client_id AND org_id = processing_run.org_id
  FOR KEY SHARE;
  IF version_row.id IS NULL OR asset_row.id IS NULL OR document_row.id IS NULL
     OR matter_row.id IS NULL OR client_row.id IS NULL
     OR version_row.document_id IS DISTINCT FROM processing_run.document_id
     OR processing_run.document_id IS DISTINCT FROM p_declared_document_id
     OR processing_run.document_version_id IS DISTINCT FROM p_declared_document_version_id
     OR processing_run.org_id IS DISTINCT FROM p_declared_org_id
     OR document_row.matter_id IS DISTINCT FROM p_declared_matter_id
     OR document_row.created_by IS DISTINCT FROM p_declared_uploaded_by
     OR asset_row.bucket_id IS DISTINCT FROM p_declared_bucket_id
     OR asset_row.object_key IS DISTINCT FROM p_declared_object_key
     OR version_row.validation_state <> 'valid'::public.document_version_validation_state
     OR version_row.state <> 'current'::public.document_version_state
     OR asset_row.availability <> 'available'::public.file_asset_availability
     OR asset_row.detected_mime_type <> 'application/pdf'
     OR asset_row.validated_page_count IS NULL
     OR version_row.page_count IS NULL
     OR version_row.page_count <> asset_row.validated_page_count THEN
    RETURN QUERY SELECT 'claimed_identity_mismatch'::text, NULL::uuid, NULL::uuid, NULL::integer;
    RETURN;
  END IF;

  source_key := 'ai_extraction.' || processing_run.id::text;
  INSERT INTO public.source_analysis_runs(
    org_id, asset_id, request_key, idempotency_key,
    analysis_kind, analysis_state, state,
    provider, model_identifier, model_config_version, prompt_version,
    schema_version, catalogue_version, normalizer_version
  ) VALUES (
    processing_run.org_id, version_row.asset_id, source_key, source_key,
    'ai_extraction'::public.source_analysis_kind,
    'queued'::public.source_analysis_provenance_state,
    'queued'::public.source_analysis_run_state,
    p_provider, p_model_identifier, p_model_config_version, p_prompt_version,
    p_schema_version, p_catalogue_version, p_normalizer_version
  ) ON CONFLICT (org_id, idempotency_key) DO NOTHING;

  SELECT * INTO source_run
  FROM public.source_analysis_runs
  WHERE org_id = processing_run.org_id AND idempotency_key = source_key
  FOR UPDATE;
  IF source_run.id IS NULL OR source_run.asset_id IS DISTINCT FROM version_row.asset_id
     OR source_run.analysis_kind <> 'ai_extraction'::public.source_analysis_kind THEN
    RAISE EXCEPTION 'document processing provenance identity is inconsistent';
  END IF;
  IF source_run.analysis_state = 'validated'::public.source_analysis_provenance_state THEN
    RETURN QUERY SELECT 'already_validated'::text, source_run.id, NULL::uuid, version_row.page_count;
    RETURN;
  END IF;
  IF source_run.analysis_state IN (
    'invalid_model_output'::public.source_analysis_provenance_state,
    'provider_failed'::public.source_analysis_provenance_state,
    'review_required'::public.source_analysis_provenance_state
  ) THEN
    RETURN QUERY SELECT 'already_terminal'::text, source_run.id, NULL::uuid, version_row.page_count;
    RETURN;
  END IF;
  IF source_run.analysis_state = 'running'::public.source_analysis_provenance_state THEN
    IF source_run.lease_expires_at IS NULL OR source_run.lease_expires_at > now() THEN
      RETURN QUERY SELECT 'already_running'::text, source_run.id, NULL::uuid, version_row.page_count;
      RETURN;
    END IF;
    -- The processing lease is still live but this nested AI lease has expired.
    -- Record the abandoned invocation, reset only through the 00063 replay
    -- transition, and let the same durable processing claim own attempt two.
    UPDATE public.source_analysis_attempts AS attempt
    SET state = 'provider_failed'::public.source_analysis_attempt_state,
        failed_at = now(), safe_error_category = 'timeout'::public.source_analysis_failure_category,
        safe_error_code = 'source_lease_expired'
    WHERE attempt.source_analysis_run_id = source_run.id
      AND attempt.attempt_number = source_run.attempt_count
      AND attempt.state = 'running'::public.source_analysis_attempt_state;
    UPDATE public.source_analysis_runs
    SET state = 'queued'::public.source_analysis_run_state,
        analysis_state = 'queued'::public.source_analysis_provenance_state,
        started_at = NULL, completed_at = NULL, failed_at = NULL,
        lease_token = NULL, lease_expires_at = NULL, heartbeat_at = now(),
        safe_error_category = NULL, safe_error_code = NULL
    WHERE id = source_run.id;
    SELECT * INTO source_run FROM public.source_analysis_runs WHERE id = source_run.id FOR UPDATE;
  END IF;

  source_lease := gen_random_uuid();
  UPDATE public.source_analysis_runs
  SET state = 'running'::public.source_analysis_run_state,
      analysis_state = 'running'::public.source_analysis_provenance_state,
      started_at = coalesce(started_at, now()), failed_at = NULL,
      lease_token = source_lease, lease_expires_at = now() + interval '5 minutes',
      heartbeat_at = now(), attempt_count = attempt_count + 1,
      safe_error_code = NULL, safe_error_category = NULL
  WHERE id = source_run.id;

  INSERT INTO public.source_analysis_attempts(
    org_id, source_analysis_run_id, attempt_number, state, retry_reason,
    provider, model_identifier, model_config_version, prompt_version,
    schema_version, catalogue_version, normalizer_version, started_at
  ) VALUES (
    source_run.org_id, source_run.id, source_run.attempt_count + 1,
    'running'::public.source_analysis_attempt_state,
    CASE WHEN source_run.attempt_count = 0
      THEN 'initial'::public.source_analysis_retry_reason
      ELSE 'operator_recovery'::public.source_analysis_retry_reason END,
    p_provider, p_model_identifier, p_model_config_version, p_prompt_version,
    p_schema_version, p_catalogue_version, p_normalizer_version, now()
  );

  RETURN QUERY SELECT 'claimed'::text, source_run.id, source_lease, version_row.page_count;
END $$;

CREATE FUNCTION public.finish_document_processing_ai_extraction(
  p_processing_run_id uuid,
  p_processing_lease_token uuid,
  p_source_analysis_run_id uuid,
  p_source_analysis_lease_token uuid,
  p_outcome text,
  p_input_tokens bigint,
  p_output_tokens bigint,
  p_latency_ms integer,
  p_candidates jsonb DEFAULT '[]'::jsonb,
  p_review_required boolean DEFAULT false,
  p_legacy_metadata jsonb DEFAULT NULL
)
RETURNS TABLE(code text, binding_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  processing_run public.document_processing_runs%ROWTYPE;
  version_row public.document_versions%ROWTYPE;
  document_row public.documents%ROWTYPE;
  matter_row public.matters%ROWTYPE;
  client_row public.clients%ROWTYPE;
  source_run public.source_analysis_runs%ROWTYPE;
  attempt_row public.source_analysis_attempts%ROWTYPE;
  candidate jsonb;
  candidate_id uuid;
  materialized_binding_id uuid;
  candidate_count integer := 0;
  source_state public.source_analysis_provenance_state;
  attempt_state public.source_analysis_attempt_state;
  error_category public.source_analysis_failure_category;
  error_code text;
BEGIN
  IF p_processing_run_id IS NULL OR p_processing_lease_token IS NULL
     OR p_source_analysis_run_id IS NULL OR p_source_analysis_lease_token IS NULL
     OR p_outcome NOT IN ('validated', 'invalid_model_output', 'provider_failed', 'review_required')
     OR p_input_tokens IS NULL OR p_input_tokens < 0
     OR p_output_tokens IS NULL OR p_output_tokens < 0
     OR p_latency_ms IS NULL OR p_latency_ms < 0
     OR jsonb_typeof(p_candidates) <> 'array' THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid;
    RETURN;
  END IF;
  IF p_outcome <> 'validated' AND jsonb_array_length(p_candidates) <> 0 THEN
    RETURN QUERY SELECT 'invalid_failure_payload'::text, NULL::uuid;
    RETURN;
  END IF;
  IF p_outcome = 'validated' AND p_legacy_metadata IS NULL THEN
    RETURN QUERY SELECT 'legacy_metadata_required'::text, NULL::uuid;
    RETURN;
  END IF;

  SELECT * INTO processing_run
  FROM public.document_processing_runs
  WHERE id = p_processing_run_id
  FOR UPDATE;
  IF processing_run.id IS NULL
     OR processing_run.state <> 'running'::public.document_processing_state
     OR processing_run.lease_token IS DISTINCT FROM p_processing_lease_token
     OR processing_run.lease_expires_at IS NULL
     OR processing_run.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'processing_lease_invalid'::text, NULL::uuid;
    RETURN;
  END IF;

  SELECT * INTO version_row
  FROM public.document_versions
  WHERE id = processing_run.document_version_id AND org_id = processing_run.org_id
  FOR UPDATE;
  SELECT * INTO document_row
  FROM public.documents
  WHERE id = processing_run.document_id AND org_id = processing_run.org_id
  FOR UPDATE;
  SELECT * INTO matter_row
  FROM public.matters
  WHERE id = document_row.matter_id AND org_id = processing_run.org_id
  FOR UPDATE;
  SELECT * INTO client_row
  FROM public.clients
  WHERE id = matter_row.client_id AND org_id = processing_run.org_id
  FOR UPDATE;
  IF version_row.id IS NULL OR document_row.id IS NULL
     OR matter_row.id IS NULL OR client_row.id IS NULL
     OR version_row.document_id IS DISTINCT FROM processing_run.document_id
     OR document_row.current_version_id IS DISTINCT FROM version_row.id
     OR document_row.deleted_at IS NOT NULL
     OR document_row.record_state <> 'active'::public.document_record_state
     OR matter_row.deleted_at IS NOT NULL
     OR matter_row.status <> 'active'::public.matter_status
     OR client_row.deleted_at IS NOT NULL THEN
    RETURN QUERY SELECT 'target_lifecycle_invalid'::text, NULL::uuid;
    RETURN;
  END IF;
  SELECT * INTO source_run
  FROM public.source_analysis_runs
  WHERE id = p_source_analysis_run_id AND org_id = processing_run.org_id
  FOR UPDATE;
  IF version_row.id IS NULL OR source_run.id IS NULL
     OR source_run.asset_id IS DISTINCT FROM version_row.asset_id
     OR source_run.idempotency_key IS DISTINCT FROM ('ai_extraction.' || processing_run.id::text)
     OR source_run.request_key IS DISTINCT FROM ('ai_extraction.' || processing_run.id::text)
     OR source_run.analysis_kind <> 'ai_extraction'::public.source_analysis_kind
  THEN
    RETURN QUERY SELECT 'source_identity_invalid'::text, NULL::uuid;
    RETURN;
  END IF;
  IF source_run.analysis_state <> 'running'::public.source_analysis_provenance_state
     OR source_run.state <> 'running'::public.source_analysis_run_state
     OR source_run.lease_token IS DISTINCT FROM p_source_analysis_lease_token
     OR source_run.lease_expires_at IS NULL
     OR source_run.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'source_lease_invalid'::text, NULL::uuid;
    RETURN;
  END IF;
  SELECT * INTO attempt_row
  FROM public.source_analysis_attempts AS attempt
  WHERE attempt.source_analysis_run_id = source_run.id AND attempt.attempt_number = source_run.attempt_count
  FOR UPDATE;
  IF attempt_row.id IS NULL OR attempt_row.state <> 'running'::public.source_analysis_attempt_state THEN
    RAISE EXCEPTION 'document processing provenance attempt is inconsistent';
  END IF;

  IF p_outcome = 'validated' THEN
    source_state := 'validated'::public.source_analysis_provenance_state;
    attempt_state := 'succeeded'::public.source_analysis_attempt_state;
    error_category := NULL;
    error_code := NULL;
  ELSIF p_outcome = 'invalid_model_output' THEN
    source_state := 'invalid_model_output'::public.source_analysis_provenance_state;
    attempt_state := 'invalid_model_output'::public.source_analysis_attempt_state;
    error_category := 'invalid_model_output'::public.source_analysis_failure_category;
    error_code := 'invalid_model_output';
  ELSIF p_outcome = 'provider_failed' THEN
    source_state := 'provider_failed'::public.source_analysis_provenance_state;
    attempt_state := 'provider_failed'::public.source_analysis_attempt_state;
    error_category := 'provider_unavailable'::public.source_analysis_failure_category;
    error_code := 'provider_unavailable';
  ELSE
    source_state := 'review_required'::public.source_analysis_provenance_state;
    attempt_state := 'succeeded'::public.source_analysis_attempt_state;
    error_category := 'invalid_model_output'::public.source_analysis_failure_category;
    error_code := 'candidate_domain_invalid';
  END IF;

  UPDATE public.source_analysis_attempts
  SET state = attempt_state, completed_at = CASE WHEN attempt_state = 'succeeded' THEN now() ELSE NULL END,
      failed_at = CASE WHEN attempt_state = 'succeeded' THEN NULL ELSE now() END,
      -- A completed attempt may have prompted a safe Review decision, but it
      -- is not itself a failed provider/model attempt (00063 enforces that
      -- succeeded attempts carry no failure details).
      safe_error_category = CASE WHEN attempt_state = 'succeeded' THEN NULL ELSE error_category END,
      safe_error_code = CASE WHEN attempt_state = 'succeeded' THEN NULL ELSE error_code END,
      input_tokens = p_input_tokens, output_tokens = p_output_tokens,
      latency_ms = p_latency_ms, usage_recorded_at = now()
  WHERE id = attempt_row.id;

  -- Terminal source rows deliberately retain their active lease fence. The
  -- 00063 transition guard makes a stale worker unable to rewrite them.
  UPDATE public.source_analysis_runs
  SET state = CASE WHEN source_state = 'validated'::public.source_analysis_provenance_state
        THEN 'succeeded'::public.source_analysis_run_state ELSE 'failed'::public.source_analysis_run_state END,
      analysis_state = source_state,
      completed_at = CASE WHEN source_state = 'validated'::public.source_analysis_provenance_state THEN now() ELSE NULL END,
      failed_at = CASE WHEN source_state = 'validated'::public.source_analysis_provenance_state THEN NULL ELSE now() END,
      heartbeat_at = now(), safe_error_category = error_category, safe_error_code = error_code,
      input_tokens = p_input_tokens, output_tokens = p_output_tokens,
      latency_ms = p_latency_ms, usage_recorded_at = now()
  WHERE id = source_run.id;

  IF p_outcome <> 'validated' THEN
    UPDATE public.documents
    SET status = 'needs_review'::public.doc_status,
        review_reason = CASE
          WHEN p_outcome = 'invalid_model_output' THEN 'provenance_invalid_model_output'
          WHEN p_outcome = 'provider_failed' THEN 'provenance_provider_failed'
          ELSE 'provenance_candidate_review_required' END
    WHERE id = processing_run.document_id AND org_id = processing_run.org_id
      AND current_version_id = version_row.id;
    RETURN QUERY SELECT p_outcome::text, NULL::uuid;
    RETURN;
  END IF;

  FOR candidate IN SELECT value FROM jsonb_array_elements(p_candidates) LOOP
    candidate_count := candidate_count + 1;
    IF jsonb_typeof(candidate) <> 'object' THEN
      RAISE EXCEPTION 'provenance candidate must be an object';
    END IF;
    SELECT public.materialize_source_field_candidate(
      source_run.id,
      candidate->>'semantic_candidate_key',
      candidate->>'field_path',
      (candidate->>'value_type')::public.source_field_candidate_value_type,
      candidate->'normalized_value',
      (candidate->>'page_number')::integer,
      candidate->>'quotation',
      NULLIF(candidate->'evidence_regions', 'null'::jsonb),
      (candidate->>'confidence')::numeric,
      (candidate->>'validation_state')::public.source_field_candidate_validation_state,
      CASE WHEN candidate->'validation_error_codes' IS NULL
        OR candidate->'validation_error_codes' = 'null'::jsonb THEN NULL
        ELSE ARRAY(SELECT jsonb_array_elements_text(candidate->'validation_error_codes')) END
    ) INTO candidate_id;
    IF candidate_id IS NULL THEN
      RAISE EXCEPTION 'provenance candidate materialization returned no identifier';
    END IF;
  END LOOP;
  IF candidate_count = 0 AND NOT p_review_required THEN
    RAISE EXCEPTION 'validated extraction without candidates must be routed to review';
  END IF;

  SELECT public.materialize_document_version_analysis(
    version_row.id, source_run.id, 'processing_ai_extraction', NULL
  ) INTO materialized_binding_id;

  -- `raw_metadata` remains a deliberately temporary copy of the same Zod-
  -- validated payload. It is not provider raw output and can be removed once
  -- existing readers migrate to candidates/effective metadata.
  UPDATE public.documents
  SET doc_type = coalesce(p_legacy_metadata->>'doc_type', 'OTHER'),
      reference_number = p_legacy_metadata->>'reference_number',
      doc_date = CASE WHEN p_legacy_metadata->>'doc_date' IS NULL THEN NULL
        ELSE (p_legacy_metadata->>'doc_date')::date END,
      direction = coalesce(
        (p_legacy_metadata->>'direction')::public.doc_direction,
        'incoming'::public.doc_direction
      ),
      issued_by = p_legacy_metadata->>'issued_by',
      financial_year = NULLIF(p_legacy_metadata #>> '{financial_years,0}', ''),
      summary = p_legacy_metadata->>'summary', raw_metadata = p_legacy_metadata,
      ai_prompt_version = p_legacy_metadata->>'prompt_version',
      status = CASE WHEN p_review_required THEN 'needs_review'::public.doc_status ELSE 'analyzed'::public.doc_status END,
      review_reason = CASE WHEN p_review_required THEN 'provenance_review_required' ELSE NULL END
  WHERE id = processing_run.document_id AND org_id = processing_run.org_id
    AND current_version_id = version_row.id;

  RETURN QUERY SELECT CASE WHEN p_review_required THEN 'review_required' ELSE 'validated' END::text, materialized_binding_id;
END $$;

REVOKE ALL ON FUNCTION public.begin_document_processing_ai_extraction(
  uuid, uuid, text, text, text, text, text, text, text, uuid, uuid, uuid, uuid, text, text, uuid
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finish_document_processing_ai_extraction(
  uuid, uuid, uuid, uuid, text, bigint, bigint, integer, jsonb, boolean, jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.begin_document_processing_ai_extraction(
  uuid, uuid, text, text, text, text, text, text, text, uuid, uuid, uuid, uuid, text, text, uuid
) TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_document_processing_ai_extraction(
  uuid, uuid, uuid, uuid, text, bigint, bigint, integer, jsonb, boolean, jsonb
) TO service_role;

COMMENT ON FUNCTION public.begin_document_processing_ai_extraction(
  uuid, uuid, text, text, text, text, text, text, text, uuid, uuid, uuid, uuid, text, text, uuid
) IS 'Service-only claim for one immutable AI extraction run/attempt under the active durable document-processing lease. Existing terminal/running identities never invoke a duplicate model call.';
COMMENT ON FUNCTION public.finish_document_processing_ai_extraction(
  uuid, uuid, uuid, uuid, text, bigint, bigint, integer, jsonb, boolean, jsonb
) IS 'Service-only terminal provenance write: records validated or invalid attempt outcome, materializes immutable source/document candidates and effective metadata, and retains only transitional validated document metadata.';

COMMIT;
