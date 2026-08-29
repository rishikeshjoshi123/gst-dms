-- Search may use only an embedding whose recorded source is the document's
-- exact current valid version. Browser roles retain their established document
-- mutations, but cannot manufacture or relabel Search vectors directly.
BEGIN;

CREATE OR REPLACE FUNCTION public.match_documents_v2(
  query_embedding vector(768),
  match_threshold float,
  match_count int,
  p_matter_id uuid,
  p_embedding_model text,
  p_embedding_version text
)
RETURNS TABLE (
  id uuid,
  reference_number text,
  similarity float
)
LANGUAGE sql STABLE
AS $$
  SELECT
    document.id,
    document.reference_number,
    1 - (document.embedding <=> query_embedding) AS similarity
  FROM public.documents AS document
  JOIN public.document_versions AS version
    ON version.org_id = document.org_id
    AND version.id = document.current_version_id
    AND version.document_id = document.id
    AND version.state = 'current'::public.document_version_state
    AND version.validation_state = 'valid'::public.document_version_validation_state
  WHERE document.matter_id = p_matter_id
    AND (auth.role() = 'service_role' OR public.is_org_member(document.org_id))
    AND document.record_state = 'active'::public.document_record_state
    AND document.deleted_at IS NULL
    AND document.current_version_id IS NOT NULL
    AND document.embedding_document_version_id = document.current_version_id
    AND document.embedding_model = p_embedding_model
    AND document.embedding_version = p_embedding_version
    AND document.embedding IS NOT NULL
    AND 1 - (document.embedding <=> query_embedding) > match_threshold
  ORDER BY document.embedding <=> query_embedding
  LIMIT LEAST(match_count, 30);
$$;

CREATE OR REPLACE FUNCTION public.match_all_documents_v2(
  query_embedding vector(768),
  match_threshold float,
  match_count int,
  p_org_id uuid,
  p_embedding_model text,
  p_embedding_version text
)
RETURNS TABLE (
  id uuid,
  reference_number text,
  similarity float
)
LANGUAGE sql STABLE
AS $$
  SELECT
    document.id,
    document.reference_number,
    1 - (document.embedding <=> query_embedding) AS similarity
  FROM public.documents AS document
  JOIN public.document_versions AS version
    ON version.org_id = document.org_id
    AND version.id = document.current_version_id
    AND version.document_id = document.id
    AND version.state = 'current'::public.document_version_state
    AND version.validation_state = 'valid'::public.document_version_validation_state
  WHERE document.org_id = p_org_id
    AND (auth.role() = 'service_role' OR public.is_org_member(document.org_id))
    AND document.record_state = 'active'::public.document_record_state
    AND document.deleted_at IS NULL
    AND document.current_version_id IS NOT NULL
    AND document.embedding_document_version_id = document.current_version_id
    AND document.embedding_model = p_embedding_model
    AND document.embedding_version = p_embedding_version
    AND document.embedding IS NOT NULL
    AND 1 - (document.embedding <=> query_embedding) > match_threshold
  ORDER BY document.embedding <=> query_embedding
  LIMIT LEAST(match_count, 30);
$$;

-- Migration 00002 granted table-wide browser INSERT. Regrant the compatible
-- non-embedding columns explicitly so ordinary browser document operations
-- remain available while all vector fields are service-owned.
REVOKE INSERT, UPDATE ON TABLE public.documents FROM authenticated;
REVOKE INSERT (embedding, embedding_model, embedding_version, embedding_document_version_id)
  ON TABLE public.documents FROM authenticated;
REVOKE UPDATE (embedding, embedding_model, embedding_version, embedding_document_version_id)
  ON TABLE public.documents FROM authenticated;
GRANT INSERT (
  ai_prompt_version, confidence_scores, content_availability, content_hash,
  copied_from_document_id, created_at, created_by, current_version_id,
  deleted_at, direction, display_title, doc_date, doc_type,
  document_category, document_class, effective_filename,
  effective_size_bytes, file_hash_sha256, financial_year, id, issued_by,
  lifecycle_revision, lifecycle_updated_at, matter_id, org_id,
  origin_external_key, origin_kind, raw_metadata, record_state,
  reference_number, restored_at, review_reason, review_status, reviewed_at,
  reviewed_by, search_vector, source, status, storage_path, summary,
  trashed_at, trashed_by, trashed_reason
) ON TABLE public.documents TO authenticated;
GRANT UPDATE (
  matter_id, org_id, doc_type, reference_number, doc_date, direction,
  issued_by, financial_year, status, review_status, reviewed_by, reviewed_at,
  summary, raw_metadata, ai_prompt_version, storage_path, file_hash_sha256,
  content_hash, deleted_at, document_class, document_category,
  confidence_scores, review_reason, source
) ON TABLE public.documents TO authenticated;

COMMENT ON FUNCTION public.match_documents_v2(vector, float, int, uuid, text, text) IS
  'Current-version-only transitional vector match within a matter; vectors without exact document-version provenance are excluded.';
COMMENT ON FUNCTION public.match_all_documents_v2(vector, float, int, uuid, text, text) IS
  'Current-version-only transitional vector match within an organisation; vectors without exact document-version provenance are excluded.';

COMMIT;
