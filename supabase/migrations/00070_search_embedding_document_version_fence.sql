-- A transitional document-summary vector is valid only for the exact current
-- source version it was derived from. Keep that provenance on the document,
-- clear it whenever a source version changes, and make every non-worker write
-- pass the same current-version fence as the durable event worker.
BEGIN;

ALTER TABLE public.documents
  ADD COLUMN embedding_document_version_id uuid;

ALTER TABLE public.documents
  ADD CONSTRAINT documents_embedding_document_version_org_fkey
  FOREIGN KEY (org_id, embedding_document_version_id)
  REFERENCES public.document_versions(org_id, id) ON DELETE RESTRICT;

CREATE FUNCTION public.clear_document_search_embedding_on_version_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.current_version_id IS DISTINCT FROM OLD.current_version_id THEN
    NEW.embedding := NULL;
    NEW.embedding_model := NULL;
    NEW.embedding_version := NULL;
    NEW.embedding_document_version_id := NULL;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER documents_clear_search_embedding_on_current_version_change
BEFORE UPDATE OF current_version_id ON public.documents
FOR EACH ROW
WHEN (OLD.current_version_id IS DISTINCT FROM NEW.current_version_id)
EXECUTE FUNCTION public.clear_document_search_embedding_on_version_change();

ALTER FUNCTION public.read_current_document_search_index_projection(uuid, uuid[])
  RENAME TO read_current_document_search_index_projection_unversioned;
REVOKE ALL ON FUNCTION public.read_current_document_search_index_projection_unversioned(uuid, uuid[])
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
  issued_by text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT
    projection.document_id,
    document.current_version_id,
    projection.doc_type,
    projection.reference_number,
    projection.summary,
    projection.financial_years,
    projection.issued_by
  FROM public.read_current_document_search_index_projection_unversioned(
    p_org_id,
    p_document_ids
  ) AS projection
  JOIN public.documents AS document
    ON document.org_id = p_org_id
    AND document.id = projection.document_id
  JOIN public.document_versions AS version
    ON version.org_id = document.org_id
    AND version.id = document.current_version_id
    AND version.document_id = document.id
    AND version.state = 'current'::public.document_version_state
    AND version.validation_state = 'valid'::public.document_version_validation_state
  WHERE document.deleted_at IS NULL
    AND document.record_state = 'active'::public.document_record_state
$$;

CREATE FUNCTION public.write_current_document_search_index_embedding(
  p_org_id uuid,
  p_document_id uuid,
  p_document_version_id uuid,
  p_embedding vector(768),
  p_embedding_model text,
  p_embedding_version text,
  p_input_tokens integer
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_org_id IS NULL OR p_document_id IS NULL OR p_document_version_id IS NULL
     OR p_embedding IS NULL OR vector_dims(p_embedding) <> 768
     OR p_embedding_model IS DISTINCT FROM 'gemini-embedding-001'
     OR p_embedding_version IS DISTINCT FROM 'gemini-embedding-001-768-v1'
     OR p_input_tokens IS NULL OR p_input_tokens < 0 THEN
    RETURN QUERY SELECT 'invalid_request'::text;
    RETURN;
  END IF;

  UPDATE public.documents AS document
  SET embedding = p_embedding,
      embedding_model = p_embedding_model,
      embedding_version = p_embedding_version,
      embedding_document_version_id = p_document_version_id,
      content_availability = CASE
        WHEN document.content_availability = 'source_attached'
          THEN 'source_indexed'::public.document_content_availability
        ELSE document.content_availability
      END
  FROM public.document_versions AS version
  WHERE document.org_id = p_org_id
    AND document.id = p_document_id
    AND document.current_version_id = p_document_version_id
    AND document.record_state = 'active'::public.document_record_state
    AND document.deleted_at IS NULL
    AND version.org_id = document.org_id
    AND version.id = p_document_version_id
    AND version.document_id = document.id
    AND version.state = 'current'::public.document_version_state
    AND version.validation_state = 'valid'::public.document_version_validation_state;

  IF NOT FOUND THEN
    RETURN QUERY SELECT 'version_not_current'::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT 'indexed'::text;
END $$;

ALTER FUNCTION public.finish_document_search_index_reprocess_work(uuid, uuid, text, vector, text, text, integer)
  RENAME TO finish_document_search_index_reprocess_work_vf_legacy;
REVOKE ALL ON FUNCTION public.finish_document_search_index_reprocess_work_vf_legacy(uuid, uuid, text, vector, text, text, integer)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.finish_document_search_index_reprocess_work(
  p_processing_run_id uuid,
  p_lease_token uuid,
  p_outcome text,
  p_embedding vector(768) DEFAULT NULL,
  p_embedding_model text DEFAULT NULL,
  p_embedding_version text DEFAULT NULL,
  p_input_tokens integer DEFAULT NULL
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  result record;
  run_row public.document_processing_runs%ROWTYPE;
BEGIN
  SELECT * INTO result
  FROM public.finish_document_search_index_reprocess_work_vf_legacy(
    p_processing_run_id,
    p_lease_token,
    p_outcome,
    p_embedding,
    p_embedding_model,
    p_embedding_version,
    p_input_tokens
  );
  IF result.code = 'indexed' THEN
    SELECT * INTO run_row
    FROM public.document_processing_runs
    WHERE id = p_processing_run_id;
    UPDATE public.documents AS document
    SET embedding_document_version_id = run_row.document_version_id
    WHERE document.id = run_row.document_id
      AND document.org_id = run_row.org_id
      AND document.current_version_id = run_row.document_version_id
      AND document.embedding IS NOT NULL
      AND document.embedding_model = p_embedding_model
      AND document.embedding_version = p_embedding_version;
  END IF;
  RETURN QUERY SELECT result.code::text;
END $$;

REVOKE ALL ON FUNCTION public.read_current_document_search_index_projection(uuid, uuid[])
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.write_current_document_search_index_embedding(uuid, uuid, uuid, vector, text, text, integer)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finish_document_search_index_reprocess_work(uuid, uuid, text, vector, text, text, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_current_document_search_index_projection(uuid, uuid[])
  TO service_role;
GRANT EXECUTE ON FUNCTION public.write_current_document_search_index_embedding(uuid, uuid, uuid, vector, text, text, integer)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_document_search_index_reprocess_work(uuid, uuid, text, vector, text, text, integer)
  TO service_role;

COMMENT ON FUNCTION public.read_current_document_search_index_projection(uuid, uuid[]) IS
  'Service-only current effective Search projection with the exact current valid document version identity.';
COMMENT ON FUNCTION public.write_current_document_search_index_embedding(uuid, uuid, uuid, vector, text, text, integer) IS
  'Service-only Search embedding write fenced to the exact active current valid document version.';

COMMIT;
