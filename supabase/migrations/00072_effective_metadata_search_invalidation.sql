-- An effective metadata change can alter the transitional Search projection
-- without changing the source file version. Withdraw its old vector before it
-- can be served, then enqueue the existing fenced, replayable Search worker.
BEGIN;

CREATE FUNCTION public.invalidate_effective_metadata_search_embedding(
  p_org_id uuid,
  p_document_id uuid,
  p_document_version_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  document_row public.documents%ROWTYPE;
  version_row public.document_versions%ROWTYPE;
  event_id uuid;
  idempotency_suffix text;
BEGIN
  SELECT * INTO document_row
  FROM public.documents AS document
  WHERE document.org_id = p_org_id
    AND document.id = p_document_id
  FOR UPDATE;
  SELECT * INTO version_row
  FROM public.document_versions AS version
  WHERE version.org_id = p_org_id
    AND version.id = p_document_version_id
    AND version.document_id = p_document_id
  FOR KEY SHARE;
  IF document_row.id IS NULL OR version_row.id IS NULL
     OR document_row.record_state <> 'active'::public.document_record_state
     OR document_row.deleted_at IS NOT NULL
     OR document_row.current_version_id IS DISTINCT FROM version_row.id
     OR version_row.state <> 'current'::public.document_version_state
     OR version_row.validation_state <> 'valid'::public.document_version_validation_state THEN
    RETURN;
  END IF;

  UPDATE public.documents AS document
  SET embedding = NULL,
      embedding_model = NULL,
      embedding_version = NULL,
      embedding_document_version_id = NULL
  WHERE document.id = document_row.id
    AND document.org_id = document_row.org_id
    AND document.current_version_id = version_row.id;

  -- A queued reindex reads the projection at claim time, so it incorporates
  -- further effective changes before work starts. A running worker may have
  -- already read older values; keep one queued successor for that case.
  IF EXISTS (
    SELECT 1
    FROM public.document_processing_runs AS run
    WHERE run.org_id = document_row.org_id
      AND run.document_id = document_row.id
      AND run.document_version_id = version_row.id
      AND run.scope = 'search_index'::public.document_processing_scope
      AND run.state = 'queued'::public.document_processing_state
  ) THEN
    RETURN;
  END IF;

  idempotency_suffix := version_row.id::text || '.' || txid_current()::text;
  INSERT INTO public.outbox_events(
    org_id, aggregate_type, aggregate_id, event_kind, payload, idempotency_key
  ) VALUES (
    document_row.org_id,
    'document',
    document_row.id,
    'document.reprocess_requested.v1',
    jsonb_build_object(
      'document_id', document_row.id::text,
      'version_id', version_row.id::text,
      'scope', 'search_index'
    ),
    'effective-search.' || idempotency_suffix
  ) ON CONFLICT (org_id, idempotency_key) DO NOTHING
  RETURNING id INTO event_id;
  IF event_id IS NULL THEN
    RETURN;
  END IF;
  INSERT INTO public.document_processing_runs(
    org_id, document_id, document_version_id, scope, stage, state,
    idempotency_key, outbox_event_id
  ) VALUES (
    document_row.org_id,
    document_row.id,
    version_row.id,
    'search_index'::public.document_processing_scope,
    'queued'::public.document_processing_stage,
    'queued'::public.document_processing_state,
    'effective-search.' || idempotency_suffix,
    event_id
  );
END $$;

CREATE FUNCTION public.document_effective_metadata_invalidate_search_embedding()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  affected record;
BEGIN
  FOR affected IN
    SELECT DISTINCT org_id, document_id, document_version_id
    FROM new_document_effective_metadata
    WHERE field_path IN (
      'document.type',
      'document.reference_number',
      'document.financial_year',
      'document.issued_by'
    )
  LOOP
    PERFORM public.invalidate_effective_metadata_search_embedding(
      affected.org_id,
      affected.document_id,
      affected.document_version_id
    );
  END LOOP;
  RETURN NULL;
END $$;

CREATE TRIGGER document_effective_metadata_invalidate_search_embedding
  AFTER INSERT ON public.document_effective_metadata
  REFERENCING NEW TABLE AS new_document_effective_metadata
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.document_effective_metadata_invalidate_search_embedding();

-- The only permitted vector writes are the SECURITY DEFINER completion and
-- current-version writer functions. Service callers retain every non-vector
-- document mutation required by existing controlled work.
REVOKE INSERT, UPDATE ON TABLE public.documents FROM service_role;
REVOKE INSERT (embedding, embedding_model, embedding_version, embedding_document_version_id)
  ON TABLE public.documents FROM service_role;
REVOKE UPDATE (embedding, embedding_model, embedding_version, embedding_document_version_id)
  ON TABLE public.documents FROM service_role;
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
) ON TABLE public.documents TO service_role;
GRANT UPDATE (
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
) ON TABLE public.documents TO service_role;

REVOKE ALL ON FUNCTION public.invalidate_effective_metadata_search_embedding(uuid, uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.document_effective_metadata_invalidate_search_embedding()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.invalidate_effective_metadata_search_embedding(uuid, uuid, uuid) IS
  'Internal effective-metadata Search invalidation: removes stale current-version vector and queues one fenced resumable Search reindex.';

COMMIT;
