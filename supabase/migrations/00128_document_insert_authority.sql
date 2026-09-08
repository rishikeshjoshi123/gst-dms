-- Retire browser/service direct document materialisation. Canonical creation
-- remains available only through the existing capability-checked commands.

DROP POLICY IF EXISTS "documents_insert" ON public.documents;
REVOKE INSERT ON TABLE public.documents FROM PUBLIC, anon, authenticated, service_role;
REVOKE INSERT (
  active_trash_membership_id, ai_prompt_version, confidence_scores,
  content_availability, content_hash, copied_from_document_id, created_at,
  created_by, current_version_id, deleted_at, direction, display_title,
  doc_date, doc_type, document_category, document_class, effective_filename,
  effective_size_bytes, embedding, embedding_document_version_id,
  embedding_model, embedding_version, file_hash_sha256, financial_year, id,
  issued_by, lifecycle_revision, lifecycle_updated_at, matter_id, org_id,
  origin_external_key, origin_kind, raw_metadata, record_state,
  reference_number, restored_at, review_reason, review_status, reviewed_at,
  reviewed_by, search_vector, source, status, storage_path, summary,
  trashed_at, trashed_by, trashed_reason
) ON public.documents FROM PUBLIC, anon, authenticated, service_role;
