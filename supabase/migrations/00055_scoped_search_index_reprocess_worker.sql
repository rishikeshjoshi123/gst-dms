-- Execute the one currently proven-idempotent reprocess scope without ever
-- routing it through the legacy document processor. The outbox envelope stays
-- identifier-only; this worker claims and finishes the exact persisted
-- document version under a fenced database lease.

-- PostgreSQL does not permit a newly-added enum value to be used until the
-- transaction that adds it has committed.
ALTER TYPE public.document_processing_stage ADD VALUE IF NOT EXISTS 'indexing';

BEGIN;

ALTER TABLE public.document_processing_recovery_cases
  DROP CONSTRAINT document_processing_recovery_cases_recovery_reason_check;
ALTER TABLE public.document_processing_recovery_cases
  ADD CONSTRAINT document_processing_recovery_cases_recovery_reason_check
  CHECK (recovery_reason IN (
    'legacy_processing_replay_unsafe',
    'scoped_reprocess_replay_unsafe',
    'scoped_search_index_retry_exhausted'
  ));

CREATE OR REPLACE FUNCTION public.claim_document_search_index_reprocess_work(
  p_event_id uuid,
  p_trigger_run_id text,
  p_expected_org_id uuid
)
RETURNS TABLE(
  code text,
  org_id uuid,
  processing_run_id uuid,
  document_id uuid,
  document_version_id uuid,
  lease_token uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  event_row public.outbox_events%ROWTYPE;
  run_row public.document_processing_runs%ROWTYPE;
  document_row public.documents%ROWTYPE;
  version_row public.document_versions%ROWTYPE;
  token uuid;
BEGIN
  IF p_event_id IS NULL OR p_expected_org_id IS NULL
     OR p_trigger_run_id IS NULL
     OR p_trigger_run_id !~ '^[A-Za-z0-9._:-]{1,200}$' THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid;
    RETURN;
  END IF;

  SELECT oe.* INTO event_row
  FROM public.outbox_events AS oe
  WHERE oe.id=p_event_id
  FOR UPDATE;

  IF event_row.id IS NULL OR event_row.event_kind<>'document.reprocess_requested.v1' THEN
    RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid;
    RETURN;
  END IF;
  IF event_row.org_id IS DISTINCT FROM p_expected_org_id THEN
    RETURN QUERY SELECT 'organisation_mismatch'::text,event_row.org_id,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid;
    RETURN;
  END IF;
  IF event_row.aggregate_type<>'document'
     OR jsonb_typeof(event_row.payload)<>'object'
     OR NOT pg_input_is_valid(event_row.payload->>'document_id','uuid')
     OR NOT pg_input_is_valid(event_row.payload->>'version_id','uuid')
     OR event_row.aggregate_id IS DISTINCT FROM (event_row.payload->>'document_id')::uuid
     OR event_row.payload IS DISTINCT FROM jsonb_build_object(
       'document_id',event_row.aggregate_id::text,
       'version_id',event_row.payload->>'version_id',
       'scope','search_index'
     ) THEN
    RETURN QUERY SELECT 'invalid_event'::text,event_row.org_id,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid;
    RETURN;
  END IF;

  SELECT dpr.* INTO run_row
  FROM public.document_processing_runs AS dpr
  WHERE dpr.outbox_event_id=event_row.id
    AND dpr.org_id=event_row.org_id
    AND dpr.document_id=(event_row.payload->>'document_id')::uuid
    AND dpr.document_version_id=(event_row.payload->>'version_id')::uuid
    AND dpr.scope='search_index'
  FOR UPDATE;
  IF run_row.id IS NULL THEN
    RETURN QUERY SELECT 'invalid_event'::text,event_row.org_id,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid;
    RETURN;
  END IF;
  IF run_row.state IN ('completed','cancelled') THEN
    RETURN QUERY SELECT 'already_complete'::text,event_row.org_id,run_row.id,run_row.document_id,run_row.document_version_id,NULL::uuid;
    RETURN;
  END IF;
  IF run_row.state='running' AND run_row.lease_expires_at>now() THEN
    RETURN QUERY SELECT 'already_claimed'::text,event_row.org_id,run_row.id,run_row.document_id,run_row.document_version_id,NULL::uuid;
    RETURN;
  END IF;
  -- An expired or failed lease is reconciled deliberately. Never reclaim it
  -- here because the caller cannot prove whether its provider call committed.
  IF run_row.state<>'queued' THEN
    RETURN QUERY SELECT CASE WHEN run_row.state='running' THEN 'lease_expired' ELSE 'retry_pending' END,
      event_row.org_id,run_row.id,run_row.document_id,run_row.document_version_id,NULL::uuid;
    RETURN;
  END IF;

  SELECT d.* INTO document_row
  FROM public.documents AS d
  WHERE d.id=run_row.document_id AND d.org_id=event_row.org_id
  FOR UPDATE;
  SELECT dv.* INTO version_row
  FROM public.document_versions AS dv
  WHERE dv.id=run_row.document_version_id
    AND dv.document_id=run_row.document_id
    AND dv.org_id=event_row.org_id
  FOR KEY SHARE;
  IF document_row.id IS NULL OR version_row.id IS NULL
     OR document_row.record_state<>'active' OR document_row.deleted_at IS NOT NULL
     OR document_row.current_version_id IS DISTINCT FROM version_row.id
     OR version_row.state<>'current' OR version_row.validation_state<>'valid' THEN
    UPDATE public.document_processing_runs AS dpr
    SET state='cancelled',started_at=NULL,completed_at=NULL,failed_at=NULL,
        safe_error_code='version_not_current',lease_token=NULL,lease_expires_at=NULL,
        heartbeat_at=now()
    WHERE dpr.id=run_row.id;
    RETURN QUERY SELECT 'version_not_current'::text,event_row.org_id,run_row.id,run_row.document_id,run_row.document_version_id,NULL::uuid;
    RETURN;
  END IF;

  token:=gen_random_uuid();
  UPDATE public.document_processing_runs AS dpr
  SET state='running',stage='indexing',started_at=coalesce(dpr.started_at,now()),
      completed_at=NULL,failed_at=NULL,safe_error_code=NULL,lease_token=token,
      lease_expires_at=now()+interval '5 minutes',heartbeat_at=now(),
      attempt_count=dpr.attempt_count+1,trigger_run_id=p_trigger_run_id
  WHERE dpr.id=run_row.id;
  RETURN QUERY SELECT 'claimed'::text,event_row.org_id,run_row.id,run_row.document_id,run_row.document_version_id,token;
END $$;

-- The worker receives this input only after it holds the lease above. It uses
-- typed, bounded effective columns; raw metadata and source/file content are
-- intentionally absent from both this response and every Trigger payload.
CREATE OR REPLACE FUNCTION public.get_document_search_index_reprocess_input(
  p_processing_run_id uuid,
  p_lease_token uuid
)
RETURNS TABLE(
  code text,
  doc_type text,
  reference_number text,
  summary text,
  financial_year text,
  issued_by text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE run_row public.document_processing_runs%ROWTYPE;
DECLARE document_row public.documents%ROWTYPE;
BEGIN
  IF p_processing_run_id IS NULL OR p_lease_token IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::text,NULL::text,NULL::text,NULL::text,NULL::text;
    RETURN;
  END IF;
  SELECT dpr.* INTO run_row FROM public.document_processing_runs AS dpr
  WHERE dpr.id=p_processing_run_id FOR KEY SHARE;
  IF run_row.id IS NULL OR run_row.scope<>'search_index' THEN
    RETURN QUERY SELECT 'not_found'::text,NULL::text,NULL::text,NULL::text,NULL::text,NULL::text;
    RETURN;
  END IF;
  IF run_row.state<>'running' OR run_row.lease_token IS DISTINCT FROM p_lease_token
     OR run_row.lease_expires_at<=now() THEN
    RETURN QUERY SELECT 'stale_lease'::text,NULL::text,NULL::text,NULL::text,NULL::text,NULL::text;
    RETURN;
  END IF;
  SELECT d.* INTO document_row FROM public.documents AS d
  WHERE d.id=run_row.document_id AND d.org_id=run_row.org_id
    AND d.current_version_id=run_row.document_version_id
    AND d.record_state='active' AND d.deleted_at IS NULL;
  IF document_row.id IS NULL THEN
    RETURN QUERY SELECT 'version_not_current'::text,NULL::text,NULL::text,NULL::text,NULL::text,NULL::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT 'ready'::text,document_row.doc_type,document_row.reference_number,
    CASE WHEN char_length(coalesce(document_row.summary,''))<=12000 THEN document_row.summary ELSE NULL END,
    document_row.financial_year,document_row.issued_by;
END $$;

CREATE OR REPLACE FUNCTION public.finish_document_search_index_reprocess_work(
  p_processing_run_id uuid,
  p_lease_token uuid,
  p_outcome text,
  p_embedding vector(768) DEFAULT NULL,
  p_embedding_model text DEFAULT NULL,
  p_embedding_version text DEFAULT NULL
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE run_row public.document_processing_runs%ROWTYPE;
DECLARE document_row public.documents%ROWTYPE;
DECLARE event_row public.outbox_events%ROWTYPE;
BEGIN
  IF p_processing_run_id IS NULL OR p_lease_token IS NULL
     OR p_outcome NOT IN ('indexed','not_indexable','failed') THEN
    RETURN QUERY SELECT 'invalid_request'::text;
    RETURN;
  END IF;
  IF (p_outcome='indexed' AND (
        p_embedding IS NULL OR vector_dims(p_embedding)<>768
        OR p_embedding_model IS NULL OR p_embedding_model !~ '^[A-Za-z0-9._:-]{1,200}$'
        OR p_embedding_version IS NULL OR p_embedding_version !~ '^[A-Za-z0-9._:-]{1,200}$'
      )) OR (p_outcome<>'indexed' AND (
        p_embedding IS NOT NULL OR p_embedding_model IS NOT NULL OR p_embedding_version IS NOT NULL
      )) THEN
    RETURN QUERY SELECT 'invalid_request'::text;
    RETURN;
  END IF;
  SELECT dpr.* INTO run_row FROM public.document_processing_runs AS dpr
  WHERE dpr.id=p_processing_run_id FOR UPDATE;
  IF run_row.id IS NULL OR run_row.scope<>'search_index' THEN
    RETURN QUERY SELECT 'not_found'::text;
    RETURN;
  END IF;
  IF run_row.state IN ('completed','cancelled') THEN
    RETURN QUERY SELECT 'already_complete'::text;
    RETURN;
  END IF;
  IF run_row.state<>'running' OR run_row.lease_token IS DISTINCT FROM p_lease_token
     OR run_row.lease_expires_at<=now() THEN
    RETURN QUERY SELECT 'stale_lease'::text;
    RETURN;
  END IF;
  SELECT oe.* INTO event_row FROM public.outbox_events AS oe
  WHERE oe.id=run_row.outbox_event_id;
  SELECT d.* INTO document_row FROM public.documents AS d
  WHERE d.id=run_row.document_id AND d.org_id=run_row.org_id FOR UPDATE;
  IF event_row.id IS NULL OR event_row.event_kind<>'document.reprocess_requested.v1'
     OR event_row.org_id IS DISTINCT FROM run_row.org_id
     OR event_row.aggregate_id IS DISTINCT FROM run_row.document_id
     OR event_row.payload IS DISTINCT FROM jsonb_build_object(
       'document_id',run_row.document_id::text,
       'version_id',run_row.document_version_id::text,
       'scope','search_index'
     )
     OR document_row.id IS NULL OR document_row.record_state<>'active'
     OR document_row.deleted_at IS NOT NULL
     OR document_row.current_version_id IS DISTINCT FROM run_row.document_version_id THEN
    UPDATE public.document_processing_runs AS dpr
    SET state='cancelled',started_at=NULL,completed_at=NULL,failed_at=NULL,
        safe_error_code='version_not_current',lease_token=NULL,lease_expires_at=NULL,
        heartbeat_at=now()
    WHERE dpr.id=run_row.id;
    RETURN QUERY SELECT 'version_not_current'::text;
    RETURN;
  END IF;
  IF p_outcome='indexed' THEN
    UPDATE public.documents AS d
    SET embedding=p_embedding,embedding_model=p_embedding_model,
        embedding_version=p_embedding_version,
        content_availability=CASE WHEN d.content_availability='source_attached'
          THEN 'source_indexed'::public.document_content_availability ELSE d.content_availability END
    WHERE d.id=run_row.document_id AND d.org_id=run_row.org_id
      AND d.current_version_id=run_row.document_version_id
      AND d.record_state='active' AND d.deleted_at IS NULL;
  END IF;
  UPDATE public.document_processing_runs AS dpr
  SET state=CASE WHEN p_outcome='failed' THEN 'failed'::public.document_processing_state
        ELSE 'completed'::public.document_processing_state END,
      stage=CASE WHEN p_outcome='failed' THEN 'failed'::public.document_processing_stage
        ELSE 'ready'::public.document_processing_stage END,
      completed_at=CASE WHEN p_outcome='failed' THEN NULL ELSE now() END,
      failed_at=CASE WHEN p_outcome='failed' THEN now() ELSE NULL END,
      safe_error_code=CASE WHEN p_outcome='failed' THEN 'search_index_failed'
        WHEN p_outcome='not_indexable' THEN 'search_index_not_indexable' ELSE NULL END,
      lease_token=NULL,lease_expires_at=NULL,heartbeat_at=now()
  WHERE dpr.id=run_row.id;
  RETURN QUERY SELECT p_outcome::text;
END $$;

-- Reconciliation may replay only an index write. It has a hard attempt cap;
-- once exhausted, preserve the run and send it to Review/recovery rather than
-- performing an unbounded provider retry.
CREATE OR REPLACE FUNCTION public.reconcile_document_processing_work(p_batch_size integer DEFAULT 100)
RETURNS TABLE(validation_requeued integer, processing_requeued integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE validation_count integer:=0; processing_count integer:=0;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'invalid batch size';
  END IF;
  WITH candidates AS (
    SELECT sar.id,sar.outbox_event_id FROM public.source_analysis_runs AS sar
    WHERE sar.outbox_event_id IS NOT NULL AND sar.state='running' AND sar.lease_expires_at<=now()
    ORDER BY coalesce(sar.lease_expires_at,sar.created_at) FOR UPDATE SKIP LOCKED LIMIT p_batch_size
  ), reset_runs AS (
    UPDATE public.source_analysis_runs AS sar
    SET state='queued',started_at=NULL,failed_at=NULL,safe_error_code='work_requeued',
        lease_token=NULL,lease_expires_at=NULL,heartbeat_at=now()
    FROM candidates AS candidate WHERE sar.id=candidate.id RETURNING candidate.outbox_event_id
  ), reset_events AS (
    UPDATE public.outbox_events AS event
    SET delivery_state='pending',delivered_at=NULL,failed_at=NULL,lease_token=NULL,
        lease_expires_at=NULL,next_attempt_at=now(),last_error_code='dispatch_failed',updated_at=now()
    FROM reset_runs AS run WHERE event.id=run.outbox_event_id AND event.delivery_state='delivered'
    RETURNING event.id
  ) SELECT count(*) INTO validation_count FROM reset_events;

  WITH candidates AS (
    SELECT run.id,run.outbox_event_id FROM public.document_processing_runs AS run
    JOIN public.outbox_events AS event ON event.id=run.outbox_event_id
    WHERE event.event_kind='document.reprocess_requested.v1'
      AND run.scope='search_index' AND run.attempt_count<3
      AND (run.state='failed' OR (run.state='running' AND run.lease_expires_at<=now()))
    ORDER BY coalesce(run.lease_expires_at,run.failed_at,run.created_at)
    FOR UPDATE OF run SKIP LOCKED LIMIT p_batch_size
  ), reset_runs AS (
    UPDATE public.document_processing_runs AS run
    SET state='queued',stage='queued',started_at=NULL,failed_at=NULL,
        safe_error_code='work_requeued',lease_token=NULL,lease_expires_at=NULL,heartbeat_at=now()
    FROM candidates AS candidate WHERE run.id=candidate.id RETURNING candidate.outbox_event_id
  ), reset_events AS (
    UPDATE public.outbox_events AS event
    SET delivery_state='pending',delivered_at=NULL,failed_at=NULL,lease_token=NULL,
        lease_expires_at=NULL,next_attempt_at=now(),last_error_code='dispatch_failed',updated_at=now()
    FROM reset_runs AS run WHERE event.id=run.outbox_event_id AND event.delivery_state='delivered'
    RETURNING event.id
  ) SELECT count(*) INTO processing_count FROM reset_events;

  WITH candidates AS (
    SELECT run.id,run.org_id,
      CASE
        WHEN event.event_kind='document.reprocess_requested.v1' AND run.scope='search_index'
          THEN 'scoped_search_index_retry_exhausted'
        WHEN event.event_kind='document.reprocess_requested.v1'
          THEN 'scoped_reprocess_replay_unsafe'
        ELSE 'legacy_processing_replay_unsafe'
      END AS reason
    FROM public.document_processing_runs AS run
    JOIN public.outbox_events AS event ON event.id=run.outbox_event_id
    WHERE run.outbox_event_id IS NOT NULL
      AND NOT (event.event_kind='document.reprocess_requested.v1'
        AND run.scope='search_index' AND run.attempt_count<3)
      AND (run.state='failed' OR (run.state='running' AND run.lease_expires_at<=now()))
    ORDER BY coalesce(run.lease_expires_at,run.failed_at,run.created_at)
    FOR UPDATE OF run SKIP LOCKED LIMIT p_batch_size
  ), fenced AS (
    UPDATE public.document_processing_runs AS run
    SET state='failed',stage=CASE WHEN candidate.reason IN ('scoped_reprocess_replay_unsafe','scoped_search_index_retry_exhausted')
          THEN 'review'::public.document_processing_stage ELSE 'failed'::public.document_processing_stage END,
        failed_at=coalesce(run.failed_at,now()),safe_error_code=CASE
          WHEN candidate.reason='scoped_reprocess_replay_unsafe' THEN 'scoped_reprocess_replay_unsafe'
          WHEN candidate.reason='scoped_search_index_retry_exhausted' THEN 'search_index_retry_exhausted'
          ELSE 'legacy_processing_recovery_required'
        END,
        lease_token=NULL,lease_expires_at=NULL,heartbeat_at=now()
    FROM candidates AS candidate WHERE run.id=candidate.id
    RETURNING run.id,run.org_id,candidate.reason
  )
  INSERT INTO public.document_processing_recovery_cases(org_id,processing_run_id,recovery_reason)
  SELECT org_id,id,reason FROM fenced
  ON CONFLICT (processing_run_id) DO UPDATE SET updated_at=now();

  RETURN QUERY SELECT validation_count,processing_count;
END $$;

REVOKE ALL ON FUNCTION public.claim_document_search_index_reprocess_work(uuid,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_document_search_index_reprocess_input(uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finish_document_search_index_reprocess_work(uuid,uuid,text,vector,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_document_search_index_reprocess_work(uuid,text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_document_search_index_reprocess_input(uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_document_search_index_reprocess_work(uuid,uuid,text,vector,text,text) TO service_role;

COMMIT;
