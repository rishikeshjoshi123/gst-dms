-- Close the delivery-lease gap on the processing dispatcher and keep only
-- native/Document AI page sources eligible for the downstream chunk worker.
BEGIN;

-- The old RPC signature cannot express the live delivery lease. No supported
-- caller uses it, so replace rather than overload it: PostgREST and generated
-- client types must expose one unambiguous, lease-fenced contract.
DROP FUNCTION public.claim_document_processing_work_for_dispatch(uuid,text,uuid);

CREATE OR REPLACE FUNCTION public.claim_document_processing_work_for_dispatch(
  p_event_id uuid,
  p_trigger_run_id text,
  p_expected_org_id uuid,
  p_delivery_lease_token uuid
) RETURNS TABLE(
  code text,
  org_id uuid,
  processing_run_id uuid,
  document_id uuid,
  document_version_id uuid,
  matter_id uuid,
  actor_id uuid,
  bucket_id text,
  object_key text,
  lease_token uuid
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE event_row public.outbox_events%ROWTYPE;
BEGIN
  IF p_event_id IS NULL OR p_expected_org_id IS NULL OR p_delivery_lease_token IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,
      NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::uuid;
    RETURN;
  END IF;
  SELECT * INTO event_row FROM public.outbox_events WHERE id=p_event_id FOR KEY SHARE;
  IF event_row.id IS NULL OR event_row.event_kind<>'document.processing_requested.v1' THEN
    RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,
      NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::uuid;
    RETURN;
  END IF;
  IF event_row.org_id IS DISTINCT FROM p_expected_org_id THEN
    RETURN QUERY SELECT 'organisation_mismatch'::text,event_row.org_id,NULL::uuid,NULL::uuid,NULL::uuid,
      NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::uuid;
    RETURN;
  END IF;
  -- Trigger starts before dispatcher acknowledgement. The live delivery lease,
  -- rather than delivered_at, proves that this exact envelope is still owned.
  IF event_row.delivery_state<>'leased' OR event_row.lease_token IS DISTINCT FROM p_delivery_lease_token
     OR event_row.lease_expires_at<=now() THEN
    RETURN QUERY SELECT 'delivery_lease_invalid'::text,event_row.org_id,NULL::uuid,NULL::uuid,NULL::uuid,
      NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::uuid;
    RETURN;
  END IF;
  RETURN QUERY
  SELECT
    claimed.code,
    event_row.org_id,
    claimed.processing_run_id,
    claimed.document_id,
    claimed.document_version_id,
    claimed.matter_id,
    claimed.actor_id,
    claimed.bucket_id,
    claimed.object_key,
    claimed.lease_token
  FROM public.claim_document_processing_work(p_event_id,p_trigger_run_id) AS claimed;
END $$;

REVOKE ALL ON FUNCTION public.claim_document_processing_work_for_dispatch(uuid,text,uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_document_processing_work_for_dispatch(uuid,text,uuid,uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.document_page_text_artifact_has_approved_acquisition(
  p_artifact_id uuid,
  p_expected_page_count integer
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT count(*) = p_expected_page_count
    AND bool_and(acquisition_method IN ('native_pdf','document_ai_ocr'))
  FROM public.document_page_text_pages
  WHERE artifact_id=p_artifact_id
$$;

-- Do not let the superseded Gemini-transcript producer remain in the derived
-- index merely because its old rows acquired the migration-safe `legacy`
-- default. Keep the private artifact for lineage, but retract every derived
-- chunk and mark the associated chunk run unavailable.
WITH legacy_artifacts AS (
  SELECT artifact.id
  FROM public.document_page_text_artifacts AS artifact
  WHERE NOT public.document_page_text_artifact_has_approved_acquisition(artifact.id,artifact.page_count)
), retracted AS (
  DELETE FROM public.search_document_chunks AS chunk
  USING legacy_artifacts
  WHERE chunk.artifact_id=legacy_artifacts.id
  RETURNING chunk.artifact_id
)
UPDATE public.search_document_chunk_runs AS run
SET state='not_indexable',artifact_id=NULL,changed_chunk_count=0,safe_error_code='legacy_page_source',updated_at=now()
WHERE run.artifact_id IN (SELECT id FROM legacy_artifacts);

CREATE OR REPLACE FUNCTION public.get_document_search_page_text_reprocess_input(p_processing_run_id uuid, p_lease_token uuid)
RETURNS TABLE(code text, pages jsonb, existing_content_hashes jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE run_row public.document_processing_runs%ROWTYPE; artifact_row public.document_page_text_artifacts%ROWTYPE;
BEGIN
  SELECT * INTO run_row FROM public.document_processing_runs WHERE id=p_processing_run_id FOR KEY SHARE;
  IF run_row.id IS NULL OR run_row.state <> 'running'::public.document_processing_state
    OR run_row.lease_token IS DISTINCT FROM p_lease_token OR run_row.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'stale_lease'::text,NULL::jsonb,NULL::jsonb; RETURN; END IF;
  SELECT a.* INTO artifact_row FROM public.document_page_text_artifacts a JOIN public.documents d
    ON d.id=a.document_id AND d.org_id=a.org_id
    JOIN public.source_analysis_runs source_run ON source_run.id=a.source_analysis_run_id AND source_run.org_id=a.org_id
    JOIN public.document_version_analysis_bindings binding ON binding.org_id=a.org_id
      AND binding.document_version_id=a.document_version_id AND binding.source_analysis_run_id=source_run.id
    WHERE a.org_id=run_row.org_id AND a.document_id=run_row.document_id
    AND a.document_version_id=run_row.document_version_id AND a.state='ready' AND d.current_version_id=a.document_version_id
    AND d.record_state='active'::public.document_record_state AND d.deleted_at IS NULL
    AND source_run.analysis_state='validated'::public.source_analysis_provenance_state
    AND public.document_page_text_artifact_has_approved_acquisition(a.id,a.page_count) FOR KEY SHARE;
  IF artifact_row.id IS NULL THEN RETURN QUERY SELECT 'not_indexable'::text,NULL::jsonb,NULL::jsonb; RETURN; END IF;
  RETURN QUERY SELECT 'ready'::text,
    (SELECT jsonb_agg(jsonb_build_object('page_number',page_number,'text',page_text) ORDER BY page_number)
      FROM public.document_page_text_pages WHERE artifact_id=artifact_row.id),
    (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'page_number',page_start,'char_start',char_start,'char_end',char_end,'content_hash',content_hash
    )),'[]'::jsonb) FROM public.search_document_chunks
      WHERE org_id=run_row.org_id AND document_id=run_row.document_id AND document_version_id=run_row.document_version_id);
END $$;

CREATE OR REPLACE FUNCTION public.write_current_document_search_page_chunks(p_processing_run_id uuid, p_lease_token uuid, p_chunks jsonb)
RETURNS TABLE(code text, changed_chunk_count integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE run_row public.document_processing_runs%ROWTYPE; document_row public.documents%ROWTYPE;
DECLARE artifact_row public.document_page_text_artifacts%ROWTYPE; changed_count integer := 0; valid_chunks boolean := false;
BEGIN
  IF p_processing_run_id IS NULL OR p_lease_token IS NULL OR jsonb_typeof(p_chunks) <> 'array' THEN
    RETURN QUERY SELECT 'invalid_request'::text,0; RETURN; END IF;
  SELECT * INTO run_row FROM public.document_processing_runs WHERE id=p_processing_run_id FOR UPDATE;
  SELECT * INTO document_row FROM public.documents WHERE id=run_row.document_id AND org_id=run_row.org_id FOR UPDATE;
  SELECT a.* INTO artifact_row FROM public.document_page_text_artifacts AS a
    JOIN public.source_analysis_runs AS source_run ON source_run.id=a.source_analysis_run_id AND source_run.org_id=a.org_id
    JOIN public.document_version_analysis_bindings AS binding ON binding.org_id=a.org_id
      AND binding.document_version_id=a.document_version_id AND binding.source_analysis_run_id=source_run.id
    WHERE a.org_id=run_row.org_id AND a.document_id=run_row.document_id
      AND a.document_version_id=run_row.document_version_id AND source_run.analysis_state='validated'::public.source_analysis_provenance_state
      AND a.state='ready' AND public.document_page_text_artifact_has_approved_acquisition(a.id,a.page_count) FOR KEY SHARE;
  IF run_row.id IS NULL OR run_row.state<>'running'::public.document_processing_state OR run_row.lease_token IS DISTINCT FROM p_lease_token
    OR run_row.lease_expires_at<=now() OR document_row.id IS NULL OR document_row.current_version_id IS DISTINCT FROM run_row.document_version_id
    OR document_row.record_state<>'active'::public.document_record_state OR document_row.deleted_at IS NOT NULL THEN
    RETURN QUERY SELECT 'version_not_current'::text,0; RETURN; END IF;
  IF artifact_row.id IS NULL OR artifact_row.state <> 'ready' THEN
    DELETE FROM public.search_document_chunks WHERE org_id=run_row.org_id AND document_id=run_row.document_id;
    INSERT INTO public.search_document_chunk_runs(org_id,document_id,document_version_id,artifact_id,processing_run_id,state,safe_error_code)
      VALUES(run_row.org_id,run_row.document_id,run_row.document_version_id,NULL,run_row.id,'not_indexable','page_text_unavailable')
      ON CONFLICT (processing_run_id) DO UPDATE SET state='not_indexable',artifact_id=NULL,changed_chunk_count=0,safe_error_code='page_text_unavailable',updated_at=now();
    RETURN QUERY SELECT 'not_indexable'::text,0; RETURN; END IF;
  SELECT coalesce(bool_and(jsonb_typeof(value)='object' AND pg_input_is_valid(value->>'ordinal','integer')
    AND pg_input_is_valid(value->>'page_number','integer') AND pg_input_is_valid(value->>'char_start','integer')
    AND pg_input_is_valid(value->>'char_end','integer') AND (value->>'ordinal')::integer>0
    AND value->>'page_number' IN (SELECT page_number::text FROM generate_series(1, artifact_row.page_count) page_number)
    AND (value->>'char_start')::integer>=0 AND (value->>'char_end')::integer>(value->>'char_start')::integer
    AND char_length(value->>'content') BETWEEN 1 AND 4000 AND value->>'content' !~ E'[\\x00-\\x1F\\x7F]'
    AND value->>'content_hash'=encode(extensions.digest(convert_to(value->>'content','utf8'),'sha256'),'hex')
    AND EXISTS (
      SELECT 1 FROM public.document_page_text_pages AS page
      WHERE page.org_id=run_row.org_id AND page.artifact_id=artifact_row.id
        AND page.page_number=(value->>'page_number')::integer
        AND (value->>'char_end')::integer <= char_length(page.page_text)
        AND value->>'content' = substring(
          page.page_text FROM (value->>'char_start')::integer + 1
          FOR (value->>'char_end')::integer - (value->>'char_start')::integer
        )
    )
    AND (value->>'embedding' IS NULL OR (pg_input_is_valid(value->>'embedding','vector') AND vector_dims((value->>'embedding')::vector)=768
      AND value->>'embedding_model' = 'gemini-embedding-001' AND value->>'embedding_version' = 'gemini-embedding-001-768-v1'
      AND pg_input_is_valid(value->>'input_tokens','integer') AND (value->>'input_tokens')::integer>=0))), false)
    INTO valid_chunks FROM jsonb_array_elements(p_chunks) input(value);
  IF NOT valid_chunks
     OR (SELECT count(DISTINCT value->>'ordinal') FROM jsonb_array_elements(p_chunks) input(value)) <> jsonb_array_length(p_chunks)
     OR (SELECT count(DISTINCT ((value->>'page_number') || ':' || (value->>'char_start') || ':' || (value->>'char_end') || ':' || (value->>'content_hash')))
         FROM jsonb_array_elements(p_chunks) input(value)) <> jsonb_array_length(p_chunks) THEN
    RETURN QUERY SELECT 'invalid_request'::text,0; RETURN;
  END IF;
  SELECT count(*) INTO changed_count FROM jsonb_array_elements(p_chunks) input(value)
  WHERE NOT EXISTS (SELECT 1 FROM public.search_document_chunks c WHERE c.org_id=run_row.org_id AND c.document_id=run_row.document_id
    AND c.document_version_id=run_row.document_version_id AND c.page_start=(value->>'page_number')::integer
    AND c.char_start=(value->>'char_start')::integer AND c.char_end=(value->>'char_end')::integer
    AND c.content_hash=value->>'content_hash');
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_chunks) input(value) WHERE NOT EXISTS
      (SELECT 1 FROM public.search_document_chunks c WHERE c.org_id=run_row.org_id AND c.document_id=run_row.document_id
       AND c.document_version_id=run_row.document_version_id AND c.page_start=(value->>'page_number')::integer
       AND c.char_start=(value->>'char_start')::integer AND c.char_end=(value->>'char_end')::integer
       AND c.content_hash=value->>'content_hash') AND value->>'embedding' IS NULL) THEN
    RETURN QUERY SELECT 'invalid_request'::text,0; RETURN; END IF;
  DELETE FROM public.search_document_chunks AS chunk WHERE chunk.org_id=run_row.org_id
    AND chunk.document_id=run_row.document_id AND chunk.document_version_id=run_row.document_version_id AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_chunks) input(value)
      WHERE chunk.page_start=(value->>'page_number')::integer AND chunk.char_start=(value->>'char_start')::integer
        AND chunk.char_end=(value->>'char_end')::integer AND chunk.content_hash=value->>'content_hash');
  INSERT INTO public.search_document_chunks(org_id,document_id,document_version_id,artifact_id,ordinal,page_start,page_end,char_start,char_end,content,content_hash,embedding,embedding_model,embedding_version,input_tokens)
  SELECT run_row.org_id,run_row.document_id,run_row.document_version_id,artifact_row.id,(value->>'ordinal')::integer,(value->>'page_number')::integer,(value->>'page_number')::integer,
    (value->>'char_start')::integer,(value->>'char_end')::integer,value->>'content',value->>'content_hash',
    CASE WHEN value->>'embedding' IS NULL THEN NULL ELSE (value->>'embedding')::vector END,value->>'embedding_model',value->>'embedding_version',
    CASE WHEN value->>'input_tokens' IS NULL THEN NULL ELSE (value->>'input_tokens')::integer END FROM jsonb_array_elements(p_chunks) input(value)
  ON CONFLICT (org_id,artifact_id,page_start,char_start,char_end,content_hash) DO UPDATE SET ordinal=EXCLUDED.ordinal,
    page_end=EXCLUDED.page_end,content=EXCLUDED.content,embedding=coalesce(EXCLUDED.embedding,search_document_chunks.embedding),
    embedding_model=coalesce(EXCLUDED.embedding_model,search_document_chunks.embedding_model),embedding_version=coalesce(EXCLUDED.embedding_version,search_document_chunks.embedding_version),
    input_tokens=coalesce(EXCLUDED.input_tokens,search_document_chunks.input_tokens),updated_at=now();
  INSERT INTO public.search_document_chunk_runs(org_id,document_id,document_version_id,artifact_id,processing_run_id,state,changed_chunk_count)
  VALUES(run_row.org_id,run_row.document_id,artifact_row.document_version_id,artifact_row.id,run_row.id,'indexed',changed_count)
  ON CONFLICT (processing_run_id) DO UPDATE SET state='indexed',artifact_id=EXCLUDED.artifact_id,
    changed_chunk_count=EXCLUDED.changed_chunk_count,safe_error_code=NULL,updated_at=now();
  RETURN QUERY SELECT 'indexed'::text,changed_count;
END $$;

REVOKE ALL ON FUNCTION public.document_page_text_artifact_has_approved_acquisition(uuid,integer)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_document_search_page_text_reprocess_input(uuid,uuid), public.write_current_document_search_page_chunks(uuid,uuid,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_document_search_page_text_reprocess_input(uuid,uuid), public.write_current_document_search_page_chunks(uuid,uuid,jsonb)
  TO service_role;

COMMIT;
