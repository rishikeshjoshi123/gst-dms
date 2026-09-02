-- Verified canonical-page locators are distinct from Gemini's short quote.
-- The service-only completion transaction proves each locator against the
-- private native/OCR page artifact before inserting an immutable candidate.
BEGIN;

ALTER TABLE public.source_field_candidates
  ADD COLUMN verified_source_anchor jsonb;

ALTER TABLE public.source_field_candidates
  ADD CONSTRAINT source_field_candidates_verified_source_anchor_valid CHECK (
    verified_source_anchor IS NULL OR (
      jsonb_typeof(verified_source_anchor) = 'object'
      AND verified_source_anchor ?& ARRAY['char_start','char_end','token_start','token_end']
      AND (verified_source_anchor->>'char_start') ~ '^[0-9]{1,8}$'
      AND (verified_source_anchor->>'char_end') ~ '^[1-9][0-9]{0,8}$'
      AND (verified_source_anchor->>'char_end')::integer > (verified_source_anchor->>'char_start')::integer
      AND (verified_source_anchor->'token_start' = 'null'::jsonb OR (verified_source_anchor->>'token_start') ~ '^[0-9]{1,8}$')
      AND (verified_source_anchor->'token_end' = 'null'::jsonb OR (verified_source_anchor->>'token_end') ~ '^[0-9]{1,8}$')
      AND ((verified_source_anchor->'token_start' = 'null'::jsonb AND verified_source_anchor->'token_end' = 'null'::jsonb)
        OR ((verified_source_anchor->>'token_start')::integer <= (verified_source_anchor->>'token_end')::integer))
    )
  );

CREATE FUNCTION public.materialize_verified_source_field_candidate(
  p_source_analysis_run_id uuid, p_semantic_candidate_key text, p_field_path text,
  p_value_type public.source_field_candidate_value_type, p_normalized_value jsonb,
  p_page_number integer, p_quotation text, p_evidence_regions jsonb, p_confidence numeric,
  p_validation_state public.source_field_candidate_validation_state, p_validation_error_codes text[],
  p_verified_source_anchor jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE run_row public.source_analysis_runs%ROWTYPE; existing_row public.source_field_candidates%ROWTYPE;
DECLARE page_text text; word_count integer; candidate_id uuid; canonical_confidence numeric(4,3);
DECLARE start_offset integer; end_offset integer; token_start integer; token_end integer; critical boolean;
BEGIN
  IF p_source_analysis_run_id IS NULL OR p_confidence IS NULL OR p_confidence < 0 OR p_confidence > 1 THEN
    RAISE EXCEPTION 'verified candidate materialization request is incomplete'; END IF;
  critical := p_field_path IN ('document.gstin','document.date','deadline.due_date','document.client_identifier','document.reference_number','document.referenced_document_number','document.matter_assignment_key','document.client_assignment_key') OR p_field_path LIKE 'financial.%';
  IF critical AND p_validation_state='eligible'::public.source_field_candidate_validation_state AND p_verified_source_anchor IS NULL THEN
    RAISE EXCEPTION 'critical eligible candidates require a verified source anchor'; END IF;
  canonical_confidence := round(p_confidence,3)::numeric(4,3);
  SELECT * INTO run_row FROM public.source_analysis_runs WHERE id=p_source_analysis_run_id FOR UPDATE;
  IF run_row.id IS NULL OR run_row.analysis_kind <> 'ai_extraction'::public.source_analysis_kind
     OR run_row.analysis_state <> 'validated'::public.source_analysis_provenance_state THEN
    RAISE EXCEPTION 'verified candidates require a validated AI extraction run'; END IF;
  IF p_verified_source_anchor IS NULL THEN
    IF p_evidence_regions IS NOT NULL THEN RAISE EXCEPTION 'evidence regions require a verified source anchor'; END IF;
  ELSIF jsonb_typeof(p_verified_source_anchor)<>'object' OR NOT (p_verified_source_anchor ?& ARRAY['char_start','char_end','token_start','token_end'])
     OR (p_verified_source_anchor->>'char_start') !~ '^[0-9]{1,8}$' OR (p_verified_source_anchor->>'char_end') !~ '^[1-9][0-9]{0,8}$' THEN
    RAISE EXCEPTION 'verified source anchor is malformed'; END IF;
  IF p_verified_source_anchor IS NOT NULL THEN
  start_offset := (p_verified_source_anchor->>'char_start')::integer; end_offset := (p_verified_source_anchor->>'char_end')::integer;
  IF end_offset <= start_offset THEN RAISE EXCEPTION 'verified source anchor is empty'; END IF;
  SELECT page.page_text,coalesce(jsonb_array_length(page.ocr_words),0) INTO page_text,word_count
  FROM public.document_page_text_artifacts artifact
  JOIN public.document_page_text_pages page ON page.artifact_id=artifact.id AND page.org_id=artifact.org_id
  JOIN public.documents document_row ON document_row.id=artifact.document_id AND document_row.org_id=artifact.org_id
  WHERE artifact.org_id=run_row.org_id AND artifact.source_analysis_run_id=run_row.id AND artifact.state='ready'
    AND artifact.document_version_id=document_row.current_version_id AND document_row.record_state='active'::public.document_record_state
    AND document_row.deleted_at IS NULL AND page.page_number=p_page_number
    AND public.document_page_text_artifact_has_approved_acquisition(artifact.id,artifact.page_count) FOR KEY SHARE;
  IF page_text IS NULL OR end_offset > char_length(page_text)
     OR substring(page_text FROM start_offset+1 FOR end_offset-start_offset) IS DISTINCT FROM p_quotation THEN
    RAISE EXCEPTION 'verified source anchor does not resolve to the canonical page quote'; END IF;
  IF p_verified_source_anchor->'token_start' <> 'null'::jsonb OR p_verified_source_anchor->'token_end' <> 'null'::jsonb THEN
    IF p_verified_source_anchor->'token_start'='null'::jsonb OR p_verified_source_anchor->'token_end'='null'::jsonb
       OR (p_verified_source_anchor->>'token_start') !~ '^[0-9]{1,8}$' OR (p_verified_source_anchor->>'token_end') !~ '^[0-9]{1,8}$' THEN
      RAISE EXCEPTION 'verified source anchor token range is incomplete'; END IF;
    token_start := (p_verified_source_anchor->>'token_start')::integer; token_end := (p_verified_source_anchor->>'token_end')::integer;
    IF token_start > token_end OR token_end >= word_count OR p_evidence_regions IS NULL THEN
      RAISE EXCEPTION 'verified source anchor token/region evidence is invalid'; END IF;
  ELSIF p_evidence_regions IS NOT NULL THEN RAISE EXCEPTION 'evidence regions require token anchors'; END IF;
  END IF;
  SELECT * INTO existing_row FROM public.source_field_candidates WHERE source_analysis_run_id=p_source_analysis_run_id
    AND semantic_candidate_key=p_semantic_candidate_key FOR KEY SHARE;
  IF existing_row.id IS NOT NULL THEN
    IF existing_row.field_path IS DISTINCT FROM p_field_path OR existing_row.value_type IS DISTINCT FROM p_value_type
       OR existing_row.normalized_value IS DISTINCT FROM p_normalized_value OR existing_row.asset_id IS DISTINCT FROM run_row.asset_id
       OR existing_row.page_number IS DISTINCT FROM p_page_number OR existing_row.quotation IS DISTINCT FROM p_quotation
       OR existing_row.evidence_regions IS DISTINCT FROM p_evidence_regions OR existing_row.verified_source_anchor IS DISTINCT FROM p_verified_source_anchor
       OR existing_row.confidence IS DISTINCT FROM canonical_confidence OR existing_row.validation_state IS DISTINCT FROM p_validation_state
       OR existing_row.validation_error_codes IS DISTINCT FROM p_validation_error_codes THEN
      RAISE EXCEPTION 'source field candidate semantic key conflicts with existing materialization'; END IF;
    RETURN existing_row.id;
  END IF;
  INSERT INTO public.source_field_candidates(org_id,source_analysis_run_id,asset_id,semantic_candidate_key,field_path,value_type,normalized_value,page_number,quotation,evidence_regions,verified_source_anchor,confidence,validation_state,validation_error_codes)
  VALUES(run_row.org_id,run_row.id,run_row.asset_id,p_semantic_candidate_key,p_field_path,p_value_type,p_normalized_value,p_page_number,p_quotation,p_evidence_regions,p_verified_source_anchor,canonical_confidence,p_validation_state,p_validation_error_codes)
  RETURNING id INTO candidate_id;
  RETURN candidate_id;
END $$;

-- Explicitly retain the previously audited completion authority. This body is
-- copied from 00067; the sole behavioural change is passing each candidate's
-- verified canonical-page anchor to the anchor-aware materializer below.
CREATE OR REPLACE FUNCTION public.finish_document_processing_ai_extraction(
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
    SELECT public.materialize_verified_source_field_candidate(
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
        ELSE ARRAY(SELECT jsonb_array_elements_text(candidate->'validation_error_codes')) END,
      NULLIF(candidate->'verified_source_anchor', 'null'::jsonb)
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

REVOKE ALL ON FUNCTION public.materialize_verified_source_field_candidate(uuid,text,text,public.source_field_candidate_value_type,jsonb,integer,text,jsonb,numeric,public.source_field_candidate_validation_state,text[],jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.materialize_verified_source_field_candidate(uuid,text,text,public.source_field_candidate_value_type,jsonb,integer,text,jsonb,numeric,public.source_field_candidate_validation_state,text[],jsonb) TO service_role;

COMMENT ON COLUMN public.source_field_candidates.verified_source_anchor IS
  'Exact canonical acquired-page character/token locator validated in the service-only completion transaction; never Gemini-only evidence.';

COMMIT;
