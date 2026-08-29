-- Release fences for the sole executable scoped reprocess worker.
BEGIN;

ALTER FUNCTION public.request_document_reprocess(uuid,public.document_processing_scope,uuid,integer)
  RENAME TO request_document_reprocess_unavailable_scope_fence;
REVOKE ALL ON FUNCTION public.request_document_reprocess_unavailable_scope_fence(uuid,public.document_processing_scope,uuid,integer) FROM PUBLIC, anon, authenticated, service_role;
CREATE FUNCTION public.request_document_reprocess(p_document_id uuid,p_scope public.document_processing_scope,p_idempotency uuid,p_capability_version integer)
RETURNS TABLE(code text,document_id uuid,document_version_id uuid,processing_run_id uuid,outbox_event_id uuid,scope public.document_processing_scope)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF p_scope IS DISTINCT FROM 'search_index'::public.document_processing_scope THEN
    RETURN QUERY SELECT 'scope_unavailable'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::public.document_processing_scope;
    RETURN;
  END IF;
  RETURN QUERY SELECT * FROM public.request_document_reprocess_unavailable_scope_fence(p_document_id,p_scope,p_idempotency,p_capability_version);
END $$;
REVOKE ALL ON FUNCTION public.request_document_reprocess(uuid,public.document_processing_scope,uuid,integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.request_document_reprocess(uuid,public.document_processing_scope,uuid,integer) TO authenticated;

ALTER FUNCTION public.claim_document_search_index_reprocess_work(uuid,text,uuid)
  RENAME TO claim_document_search_index_reprocess_work_unfenced;
REVOKE ALL ON FUNCTION public.claim_document_search_index_reprocess_work_unfenced(uuid,text,uuid) FROM PUBLIC, anon, authenticated, service_role;
CREATE FUNCTION public.claim_document_search_index_reprocess_work(p_event_id uuid,p_trigger_run_id text,p_expected_org_id uuid,p_delivery_lease_token uuid)
RETURNS TABLE(code text,org_id uuid,processing_run_id uuid,document_id uuid,document_version_id uuid,lease_token uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  -- Trigger starts before dispatcher acknowledgement. A still-live outbox
  -- delivery lease is therefore the authority, not delivered_at.
  PERFORM 1 FROM public.outbox_events AS event
  WHERE event.id=p_event_id AND event.org_id=p_expected_org_id
    AND event.delivery_state='leased' AND event.lease_token=p_delivery_lease_token
    AND event.lease_expires_at>now()
  FOR KEY SHARE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'delivery_lease_invalid'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid;
    RETURN;
  END IF;
  RETURN QUERY SELECT * FROM public.claim_document_search_index_reprocess_work_unfenced(p_event_id,p_trigger_run_id,p_expected_org_id);
END $$;
REVOKE ALL ON FUNCTION public.claim_document_search_index_reprocess_work(uuid,text,uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_document_search_index_reprocess_work(uuid,text,uuid,uuid) TO service_role;

ALTER TABLE public.document_processing_runs
  ADD COLUMN search_embedding_model text,
  ADD COLUMN search_embedding_version text,
  ADD COLUMN search_embedding_task_type text,
  ADD COLUMN search_embedding_input_tokens integer,
  ADD CONSTRAINT document_processing_runs_search_embedding_usage_check CHECK (
    (search_embedding_input_tokens IS NULL AND search_embedding_model IS NULL AND search_embedding_version IS NULL AND search_embedding_task_type IS NULL)
    OR (search_embedding_input_tokens>=0 AND search_embedding_model='gemini-embedding-001'
      AND search_embedding_version='gemini-embedding-001-768-v1'
      AND search_embedding_task_type='RETRIEVAL_DOCUMENT')
  );

ALTER FUNCTION public.finish_document_search_index_reprocess_work(uuid,uuid,text,vector,text,text)
  RENAME TO finish_document_search_index_reprocess_work_unfenced;
REVOKE ALL ON FUNCTION public.finish_document_search_index_reprocess_work_unfenced(uuid,uuid,text,vector,text,text) FROM PUBLIC, anon, authenticated, service_role;
CREATE FUNCTION public.finish_document_search_index_reprocess_work(
  p_processing_run_id uuid,p_lease_token uuid,p_outcome text,p_embedding vector(768) DEFAULT NULL,
  p_embedding_model text DEFAULT NULL,p_embedding_version text DEFAULT NULL,p_input_tokens integer DEFAULT NULL
) RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE result record; run_row public.document_processing_runs%ROWTYPE;
BEGIN
  IF (p_outcome='indexed' AND (p_embedding_model IS DISTINCT FROM 'gemini-embedding-001'
      OR p_embedding_version IS DISTINCT FROM 'gemini-embedding-001-768-v1'
      OR p_input_tokens IS NULL OR p_input_tokens<0))
    OR (p_outcome<>'indexed' AND p_input_tokens IS NOT NULL) THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  SELECT * INTO result FROM public.finish_document_search_index_reprocess_work_unfenced(
    p_processing_run_id,p_lease_token,p_outcome,p_embedding,p_embedding_model,p_embedding_version
  );
  IF result.code='indexed' THEN
    UPDATE public.document_processing_runs SET search_embedding_model=p_embedding_model,
      search_embedding_version=p_embedding_version,search_embedding_task_type='RETRIEVAL_DOCUMENT',
      search_embedding_input_tokens=p_input_tokens
    WHERE id=p_processing_run_id;
  ELSIF result.code='not_indexable' THEN
    SELECT * INTO run_row FROM public.document_processing_runs WHERE id=p_processing_run_id;
    UPDATE public.documents SET embedding=NULL,embedding_model=NULL,embedding_version=NULL
    WHERE id=run_row.document_id AND org_id=run_row.org_id
      AND current_version_id=run_row.document_version_id;
  END IF;
  RETURN QUERY SELECT result.code::text;
END $$;
REVOKE ALL ON FUNCTION public.finish_document_search_index_reprocess_work(uuid,uuid,text,vector,text,text,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finish_document_search_index_reprocess_work(uuid,uuid,text,vector,text,text,integer) TO service_role;
COMMIT;
