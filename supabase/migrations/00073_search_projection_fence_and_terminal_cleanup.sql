-- Search metadata can change without a source-version replacement. Carry a
-- deterministic projection fingerprint from the bounded reader to both
-- fenced writers so a completion based on an older effective projection never
-- becomes the current vector.
BEGIN;

ALTER FUNCTION public.read_current_document_search_index_projection(uuid, uuid[])
  RENAME TO read_current_document_search_index_projection_unfingerprinted;
REVOKE ALL ON FUNCTION public.read_current_document_search_index_projection_unfingerprinted(uuid, uuid[])
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.read_current_document_search_index_projection(
  p_org_id uuid,
  p_document_ids uuid[]
)
RETURNS TABLE (
  document_id uuid,
  document_version_id uuid,
  doc_type text,
  reference_number text,
  summary text,
  financial_years text[],
  issued_by text,
  projection_fingerprint text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT
    projection.document_id,
    projection.document_version_id,
    projection.doc_type,
    projection.reference_number,
    projection.summary,
    projection.financial_years,
    projection.issued_by,
    encode(extensions.digest(jsonb_build_object(
      'document_version_id', projection.document_version_id,
      'doc_type', projection.doc_type,
      'reference_number', projection.reference_number,
      'summary', projection.summary,
      'financial_years', coalesce(to_jsonb(projection.financial_years), '[]'::jsonb),
      'issued_by', projection.issued_by
    )::text, 'sha256'), 'hex') AS projection_fingerprint
  FROM public.read_current_document_search_index_projection_unfingerprinted(
    p_org_id,
    p_document_ids
  ) AS projection
$$;

ALTER FUNCTION public.get_document_search_index_reprocess_input(uuid, uuid)
  RENAME TO get_document_search_index_reprocess_input_unfingerprinted;
REVOKE ALL ON FUNCTION public.get_document_search_index_reprocess_input_unfingerprinted(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.get_document_search_index_reprocess_input(
  p_processing_run_id uuid,
  p_lease_token uuid
)
RETURNS TABLE(
  code text,
  doc_type text,
  reference_number text,
  summary text,
  financial_years text[],
  issued_by text,
  projection_fingerprint text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  run_row public.document_processing_runs%ROWTYPE;
  document_row public.documents%ROWTYPE;
  version_row public.document_versions%ROWTYPE;
  projection_row record;
BEGIN
  IF p_processing_run_id IS NULL OR p_lease_token IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::text, NULL::text, NULL::text, NULL::text[], NULL::text, NULL::text;
    RETURN;
  END IF;
  SELECT * INTO run_row
  FROM public.document_processing_runs AS run
  WHERE run.id = p_processing_run_id
  FOR KEY SHARE;
  IF run_row.id IS NULL OR run_row.scope <> 'search_index'::public.document_processing_scope THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::text, NULL::text, NULL::text, NULL::text[], NULL::text, NULL::text;
    RETURN;
  END IF;
  IF run_row.state <> 'running'::public.document_processing_state
     OR run_row.lease_token IS DISTINCT FROM p_lease_token
     OR run_row.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'stale_lease'::text, NULL::text, NULL::text, NULL::text, NULL::text[], NULL::text, NULL::text;
    RETURN;
  END IF;
  SELECT * INTO document_row
  FROM public.documents AS document
  WHERE document.id = run_row.document_id
    AND document.org_id = run_row.org_id
  FOR KEY SHARE;
  SELECT * INTO version_row
  FROM public.document_versions AS version
  WHERE version.id = run_row.document_version_id
    AND version.org_id = run_row.org_id
    AND version.document_id = run_row.document_id
  FOR KEY SHARE;
  IF document_row.id IS NULL OR version_row.id IS NULL
     OR document_row.current_version_id IS DISTINCT FROM version_row.id
     OR document_row.record_state <> 'active'::public.document_record_state
     OR document_row.deleted_at IS NOT NULL
     OR version_row.state <> 'current'::public.document_version_state
     OR version_row.validation_state <> 'valid'::public.document_version_validation_state THEN
    RETURN QUERY SELECT 'version_not_current'::text, NULL::text, NULL::text, NULL::text, NULL::text[], NULL::text, NULL::text;
    RETURN;
  END IF;
  SELECT * INTO projection_row
  FROM public.read_current_document_search_index_projection(
    run_row.org_id,
    ARRAY[run_row.document_id]
  );
  IF projection_row.document_id IS NULL THEN
    RETURN QUERY SELECT 'version_not_current'::text, NULL::text, NULL::text, NULL::text, NULL::text[], NULL::text, NULL::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT
    'ready'::text,
    projection_row.doc_type,
    projection_row.reference_number,
    projection_row.summary,
    projection_row.financial_years,
    projection_row.issued_by,
    projection_row.projection_fingerprint;
END $$;

ALTER FUNCTION public.write_current_document_search_index_embedding(uuid, uuid, uuid, vector, text, text, integer)
  RENAME TO write_current_document_search_index_embedding_unfingerprinted;
REVOKE ALL ON FUNCTION public.write_current_document_search_index_embedding_unfingerprinted(uuid, uuid, uuid, vector, text, text, integer)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.write_current_document_search_index_embedding(
  p_org_id uuid,
  p_document_id uuid,
  p_document_version_id uuid,
  p_embedding vector(768),
  p_embedding_model text,
  p_embedding_version text,
  p_input_tokens integer,
  p_projection_fingerprint text DEFAULT NULL
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  document_row public.documents%ROWTYPE;
  projection_row record;
  result record;
BEGIN
  IF p_projection_fingerprint IS NULL
     OR p_projection_fingerprint !~ '^[a-f0-9]{64}$' THEN
    RETURN QUERY SELECT 'invalid_request'::text;
    RETURN;
  END IF;
  SELECT * INTO document_row
  FROM public.documents AS document
  WHERE document.org_id = p_org_id
    AND document.id = p_document_id
  FOR UPDATE;
  IF document_row.id IS NULL THEN
    RETURN QUERY SELECT 'version_not_current'::text;
    RETURN;
  END IF;
  SELECT * INTO projection_row
  FROM public.read_current_document_search_index_projection(
    p_org_id,
    ARRAY[p_document_id]
  );
  IF projection_row.document_id IS NULL
     OR projection_row.document_version_id IS DISTINCT FROM p_document_version_id THEN
    RETURN QUERY SELECT 'version_not_current'::text;
    RETURN;
  END IF;
  IF projection_row.projection_fingerprint IS DISTINCT FROM p_projection_fingerprint THEN
    RETURN QUERY SELECT 'projection_changed'::text;
    RETURN;
  END IF;
  SELECT * INTO result
  FROM public.write_current_document_search_index_embedding_unfingerprinted(
    p_org_id,
    p_document_id,
    p_document_version_id,
    p_embedding,
    p_embedding_model,
    p_embedding_version,
    p_input_tokens
  );
  RETURN QUERY SELECT result.code::text;
END $$;

ALTER FUNCTION public.finish_document_search_index_reprocess_work(uuid, uuid, text, vector, text, text, integer)
  RENAME TO finish_document_search_index_reprocess_work_unfingerprinted;
REVOKE ALL ON FUNCTION public.finish_document_search_index_reprocess_work_unfingerprinted(uuid, uuid, text, vector, text, text, integer)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.finish_document_search_index_reprocess_work(
  p_processing_run_id uuid,
  p_lease_token uuid,
  p_outcome text,
  p_embedding vector(768) DEFAULT NULL,
  p_embedding_model text DEFAULT NULL,
  p_embedding_version text DEFAULT NULL,
  p_input_tokens integer DEFAULT NULL,
  p_projection_fingerprint text DEFAULT NULL
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  run_row public.document_processing_runs%ROWTYPE;
  document_row public.documents%ROWTYPE;
  projection_row record;
  result record;
BEGIN
  IF p_outcome IN ('indexed', 'not_indexable')
     AND (p_projection_fingerprint IS NULL
       OR p_projection_fingerprint !~ '^[a-f0-9]{64}$') THEN
    RETURN QUERY SELECT 'invalid_request'::text;
    RETURN;
  END IF;

  SELECT * INTO run_row
  FROM public.document_processing_runs AS run
  WHERE run.id = p_processing_run_id
  FOR UPDATE;
  IF run_row.id IS NOT NULL
     AND run_row.scope = 'search_index'::public.document_processing_scope
     AND run_row.state = 'running'::public.document_processing_state
     AND run_row.lease_token IS NOT DISTINCT FROM p_lease_token
     AND run_row.lease_expires_at > now()
     AND p_outcome IN ('indexed', 'not_indexable') THEN
    SELECT * INTO document_row
    FROM public.documents AS document
    WHERE document.org_id = run_row.org_id
      AND document.id = run_row.document_id
    FOR UPDATE;
    SELECT * INTO projection_row
    FROM public.read_current_document_search_index_projection(
      run_row.org_id,
      ARRAY[run_row.document_id]
    );
    IF document_row.id IS NOT NULL
       AND projection_row.document_id IS NOT NULL
       AND projection_row.document_version_id = run_row.document_version_id
       AND projection_row.projection_fingerprint IS DISTINCT FROM p_projection_fingerprint THEN
      UPDATE public.document_processing_runs AS run
      SET state = 'cancelled'::public.document_processing_state,
          stage = 'ready'::public.document_processing_stage,
          started_at = NULL,
          completed_at = NULL,
          failed_at = NULL,
          safe_error_code = 'search_projection_changed',
          lease_token = NULL,
          lease_expires_at = NULL,
          heartbeat_at = now()
      WHERE run.id = run_row.id;
      RETURN QUERY SELECT 'projection_changed'::text;
      RETURN;
    END IF;
  END IF;

  SELECT * INTO result
  FROM public.finish_document_search_index_reprocess_work_unfingerprinted(
    p_processing_run_id,
    p_lease_token,
    p_outcome,
    p_embedding,
    p_embedding_model,
    p_embedding_version,
    p_input_tokens
  );
  IF result.code = 'not_indexable' THEN
    UPDATE public.documents AS document
    SET embedding = NULL,
        embedding_model = NULL,
        embedding_version = NULL,
        embedding_document_version_id = NULL
    WHERE document.org_id = run_row.org_id
      AND document.id = run_row.document_id
      AND document.current_version_id = run_row.document_version_id;
  END IF;
  RETURN QUERY SELECT result.code::text;
END $$;

REVOKE ALL ON FUNCTION public.read_current_document_search_index_projection(uuid, uuid[])
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_document_search_index_reprocess_input(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.write_current_document_search_index_embedding(uuid, uuid, uuid, vector, text, text, integer, text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finish_document_search_index_reprocess_work(uuid, uuid, text, vector, text, text, integer, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_current_document_search_index_projection(uuid, uuid[])
  TO service_role;
GRANT EXECUTE ON FUNCTION public.get_document_search_index_reprocess_input(uuid, uuid)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.write_current_document_search_index_embedding(uuid, uuid, uuid, vector, text, text, integer, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_document_search_index_reprocess_work(uuid, uuid, text, vector, text, text, integer, text)
  TO service_role;

COMMENT ON FUNCTION public.read_current_document_search_index_projection(uuid, uuid[]) IS
  'Service-only current effective Search projection with a deterministic fingerprint of its searchable values.';
COMMENT ON FUNCTION public.finish_document_search_index_reprocess_work(uuid, uuid, text, vector, text, text, integer, text) IS
  'Service-only Search completion fenced to the current valid version and the exact effective Search projection.';

COMMIT;
