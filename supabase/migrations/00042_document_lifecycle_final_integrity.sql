-- Final lifecycle integrity remediation: version-authorised reads, conservative
-- legacy-processing recovery, and physical-storage-aware quota accounting.
BEGIN;

-- A lifecycle row is retained after an object is removed, so a tombstone is
-- required to distinguish an historical record from bytes still consuming the
-- private bucket. Failed removals deliberately remain counted.
ALTER TABLE public.file_assets
  ADD COLUMN storage_deleted_at timestamptz,
  ADD COLUMN storage_delete_attempted_at timestamptz,
  ADD COLUMN storage_deletion_lease_token uuid,
  ADD COLUMN storage_deletion_lease_expires_at timestamptz,
  ADD COLUMN storage_delete_failure_code text,
  ADD CONSTRAINT file_assets_storage_delete_lease_consistent CHECK (
    (storage_deletion_lease_token IS NULL AND storage_deletion_lease_expires_at IS NULL)
    OR (storage_deletion_lease_token IS NOT NULL AND storage_deletion_lease_expires_at IS NOT NULL)
  ),
  ADD CONSTRAINT file_assets_storage_tombstone_terminal CHECK (
    storage_deleted_at IS NULL OR availability IN ('failed','expired','quarantined')
  );
CREATE INDEX file_assets_terminal_storage_cleanup_idx
  ON public.file_assets (availability, storage_deletion_lease_expires_at, created_at)
  WHERE storage_deleted_at IS NULL;

CREATE OR REPLACE FUNCTION public.document_retained_asset_bytes(p_org_id uuid)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT coalesce(sum(byte_size),0)::bigint
  FROM public.file_assets
  WHERE org_id=p_org_id AND byte_size IS NOT NULL AND storage_deleted_at IS NULL
$$;

CREATE OR REPLACE FUNCTION public.document_platform_retained_asset_bytes()
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT coalesce(sum(byte_size),0)::bigint
  FROM public.file_assets
  WHERE byte_size IS NOT NULL AND storage_deleted_at IS NULL
$$;

-- The browser never supplies a bucket or object key. The caller can request a
-- version they are authorised to view; the server action alone turns this
-- grant into a short-lived Storage URL.
CREATE OR REPLACE FUNCTION public.get_document_version_read_grant(p_document_version_id uuid)
RETURNS TABLE(code text, bucket_id text, object_key text)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
  SELECT CASE WHEN v.id IS NULL THEN 'not_found' ELSE 'ok' END,
         CASE WHEN v.id IS NULL THEN NULL ELSE a.bucket_id END,
         CASE WHEN v.id IS NULL THEN NULL ELSE a.object_key END
  FROM (SELECT org_id FROM public.get_my_organisation_context()
        WHERE state='active' AND 'document.view'=ANY(capabilities) LIMIT 1) AS actor
  LEFT JOIN public.document_versions AS v ON v.id=p_document_version_id AND v.org_id=actor.org_id
  LEFT JOIN public.documents AS d ON d.id=v.document_id AND d.org_id=actor.org_id
  LEFT JOIN public.file_assets AS a ON a.id=v.asset_id AND a.org_id=actor.org_id
  WHERE d.id IS NOT NULL
    AND d.record_state='active'
    AND d.deleted_at IS NULL
    AND v.validation_state='valid'
    AND v.state IN ('current','superseded')
    AND a.availability='available'
    AND a.storage_deleted_at IS NULL
$$;

-- Only service-side code that has already received a successful Storage
-- deletion response may write a tombstone. The function is intentionally
-- idempotent: duplicate clean-up attempts cannot resurrect quota usage.
CREATE OR REPLACE FUNCTION public.record_document_asset_storage_deleted(p_asset_id uuid)
RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE asset public.file_assets%ROWTYPE;
BEGIN
  IF p_asset_id IS NULL THEN RETURN QUERY SELECT 'invalid_request'::text; RETURN; END IF;
  SELECT * INTO asset FROM public.file_assets WHERE id=p_asset_id FOR UPDATE;
  IF asset.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text; RETURN; END IF;
  IF asset.storage_deleted_at IS NOT NULL THEN RETURN QUERY SELECT 'already_deleted'::text; RETURN; END IF;
  IF asset.availability NOT IN ('failed','expired','quarantined')
     OR EXISTS (SELECT 1 FROM public.document_versions WHERE asset_id=asset.id) THEN
    RETURN QUERY SELECT 'not_deletable'::text; RETURN;
  END IF;
  UPDATE public.file_assets
  SET storage_deleted_at=now(), storage_delete_attempted_at=now(),
      storage_deletion_lease_token=NULL, storage_deletion_lease_expires_at=NULL,
      storage_delete_failure_code=NULL
  WHERE id=asset.id;
  RETURN QUERY SELECT 'deleted'::text;
END $$;

-- A completion rejection still follows a successful server-side object read.
-- Persist that observed size before terminalising the session, otherwise a
-- failed physical delete could fall back to the browser's smaller declaration.
CREATE OR REPLACE FUNCTION public.record_document_upload_observed_bytes(p_session uuid,p_observed_bytes bigint)
RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE session_row public.upload_sessions%ROWTYPE; asset public.file_assets%ROWTYPE;
BEGIN
  IF p_session IS NULL OR p_observed_bytes IS NULL OR p_observed_bytes<=0 THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  SELECT * INTO session_row FROM public.upload_sessions WHERE id=p_session FOR UPDATE;
  IF session_row.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text; RETURN; END IF;
  SELECT * INTO asset FROM public.file_assets WHERE id=session_row.asset_id FOR UPDATE;
  IF asset.id IS NULL OR asset.availability NOT IN ('reserved','uploaded','validating')
     OR EXISTS (SELECT 1 FROM public.document_versions WHERE asset_id=asset.id) THEN
    RETURN QUERY SELECT 'not_available'::text; RETURN;
  END IF;
  IF asset.byte_size IS NOT NULL AND asset.byte_size<>p_observed_bytes THEN
    RETURN QUERY SELECT 'observation_conflict'::text; RETURN;
  END IF;
  UPDATE public.file_assets SET byte_size=p_observed_bytes WHERE id=asset.id;
  RETURN QUERY SELECT 'ok'::text;
END $$;

-- Expiry and terminal validation are database facts; object deletion is an
-- external effect. Lease it separately, then tombstone only after Storage
-- confirms the delete. A failed delete is retryable and remains in quota.
CREATE OR REPLACE FUNCTION public.claim_document_asset_storage_deletion_work(p_batch_size integer DEFAULT 100)
RETURNS TABLE(asset_id uuid, bucket_id text, object_key text, lease_token uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  IF p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'invalid batch size';
  END IF;
  RETURN QUERY
  WITH candidates AS (
    SELECT fa.id
    FROM public.file_assets AS fa
    WHERE fa.storage_deleted_at IS NULL
      AND fa.availability IN ('failed','expired','quarantined')
      AND NOT EXISTS (SELECT 1 FROM public.document_versions AS dv WHERE dv.asset_id=fa.id)
      AND (fa.storage_deletion_lease_expires_at IS NULL OR fa.storage_deletion_lease_expires_at<=now())
    ORDER BY fa.created_at
    FOR UPDATE SKIP LOCKED
    LIMIT p_batch_size
  ), leased AS (
    UPDATE public.file_assets AS fa
    SET storage_delete_attempted_at=now(), storage_deletion_lease_token=gen_random_uuid(),
        storage_deletion_lease_expires_at=now()+interval '10 minutes', storage_delete_failure_code=NULL
    FROM candidates AS c
    WHERE fa.id=c.id
    RETURNING fa.id,fa.bucket_id,fa.object_key,fa.storage_deletion_lease_token
  ) SELECT id,bucket_id,object_key,storage_deletion_lease_token FROM leased;
END $$;

CREATE OR REPLACE FUNCTION public.finish_document_asset_storage_deletion_work(p_asset_id uuid,p_lease_token uuid,p_outcome text)
RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE asset public.file_assets%ROWTYPE;
BEGIN
  IF p_asset_id IS NULL OR p_lease_token IS NULL OR p_outcome NOT IN ('deleted','failed') THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  SELECT * INTO asset FROM public.file_assets WHERE id=p_asset_id FOR UPDATE;
  IF asset.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text; RETURN; END IF;
  IF asset.storage_deleted_at IS NOT NULL THEN RETURN QUERY SELECT 'already_deleted'::text; RETURN; END IF;
  IF asset.storage_deletion_lease_token IS DISTINCT FROM p_lease_token
     OR asset.storage_deletion_lease_expires_at<=now() THEN
    RETURN QUERY SELECT 'stale_lease'::text; RETURN;
  END IF;
  IF p_outcome='deleted' THEN
    UPDATE public.file_assets
    SET storage_deleted_at=now(), storage_delete_attempted_at=now(),
        storage_deletion_lease_token=NULL, storage_deletion_lease_expires_at=NULL,
        storage_delete_failure_code=NULL
    WHERE id=asset.id;
  ELSE
    UPDATE public.file_assets
    SET storage_delete_attempted_at=now(), storage_deletion_lease_token=NULL,
        storage_deletion_lease_expires_at=NULL, storage_delete_failure_code='storage_delete_failed'
    WHERE id=asset.id;
  END IF;
  RETURN QUERY SELECT p_outcome::text;
END $$;

-- The old Trigger job mutates links, deadlines, activity, and notifications
-- without a processing-run fence. Never replay it automatically after a lease
-- expires or reports failure. Retain a service-only recovery record instead.
CREATE TABLE public.document_processing_recovery_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  processing_run_id uuid NOT NULL REFERENCES public.document_processing_runs(id) ON DELETE RESTRICT,
  recovery_reason text NOT NULL CHECK (recovery_reason IN ('legacy_processing_replay_unsafe')),
  state text NOT NULL DEFAULT 'open' CHECK (state IN ('open','resolved')),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (processing_run_id)
);
ALTER TABLE public.document_processing_recovery_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_processing_recovery_cases FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.document_processing_recovery_cases FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON public.document_processing_recovery_cases TO service_role;

-- Disambiguate the binding uniqueness target. PostgreSQL otherwise treats the
-- output-column name of this PL/pgSQL function as ambiguous at runtime.
CREATE OR REPLACE FUNCTION public.claim_document_processing_work(p_event_id uuid,p_trigger_run_id text DEFAULT NULL)
RETURNS TABLE(code text, processing_run_id uuid, document_id uuid, document_version_id uuid, matter_id uuid, actor_id uuid, bucket_id text, object_key text, lease_token uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE ev public.outbox_events%ROWTYPE; doc public.documents%ROWTYPE; ver public.document_versions%ROWTYPE; asset public.file_assets%ROWTYPE; run public.document_processing_runs%ROWTYPE; source_id uuid; token uuid;
BEGIN
  IF p_event_id IS NULL THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::uuid; RETURN; END IF;
  SELECT oe.* INTO ev FROM public.outbox_events AS oe WHERE oe.id=p_event_id FOR UPDATE;
  IF ev.id IS NULL OR ev.event_kind<>'document.processing_requested.v1' THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::uuid; RETURN; END IF;
  IF ev.aggregate_type<>'document' OR jsonb_typeof(ev.payload)<>'object' OR NOT pg_input_is_valid(ev.payload->>'document_id','uuid') OR NOT pg_input_is_valid(ev.payload->>'version_id','uuid') OR ev.aggregate_id IS DISTINCT FROM (ev.payload->>'document_id')::uuid THEN RETURN QUERY SELECT 'invalid_event'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::uuid; RETURN; END IF;
  SELECT d.* INTO doc FROM public.documents AS d WHERE d.id=(ev.payload->>'document_id')::uuid AND d.org_id=ev.org_id FOR UPDATE;
  SELECT dv.* INTO ver FROM public.document_versions AS dv WHERE dv.id=(ev.payload->>'version_id')::uuid AND dv.document_id=doc.id AND dv.org_id=ev.org_id FOR UPDATE;
  SELECT fa.* INTO asset FROM public.file_assets AS fa WHERE fa.id=ver.asset_id AND fa.org_id=ev.org_id;
  IF doc.id IS NULL OR ver.id IS NULL OR doc.record_state<>'active' OR doc.current_version_id IS DISTINCT FROM ver.id OR ver.state<>'current' OR asset.availability<>'available' OR asset.storage_deleted_at IS NOT NULL THEN RETURN QUERY SELECT 'no_work'::text,NULL::uuid,doc.id,ver.id,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::uuid; RETURN; END IF;
  SELECT sar.id INTO source_id FROM public.document_version_analysis_bindings AS bind JOIN public.source_analysis_runs AS sar ON sar.id=bind.source_analysis_run_id AND sar.org_id=bind.org_id WHERE bind.document_version_id=ver.id AND bind.org_id=ev.org_id AND sar.asset_id=asset.id AND sar.state='succeeded' ORDER BY sar.completed_at DESC NULLS LAST LIMIT 1;
  IF source_id IS NULL THEN
    SELECT sar.id INTO source_id FROM public.source_analysis_runs AS sar WHERE sar.org_id=ev.org_id AND sar.asset_id=asset.id AND sar.state='succeeded' AND sar.request_key='validation.'||sar.outbox_event_id::text ORDER BY sar.completed_at DESC NULLS LAST LIMIT 1;
    IF source_id IS NOT NULL THEN INSERT INTO public.document_version_analysis_bindings(org_id,document_version_id,source_analysis_run_id,binding_reason) VALUES(ev.org_id,ver.id,source_id,'processing_validation') ON CONFLICT ON CONSTRAINT document_version_analysis_bindings_unique DO NOTHING; END IF;
  END IF;
  INSERT INTO public.document_processing_runs(org_id,document_id,document_version_id,source_analysis_run_id,scope,idempotency_key,outbox_event_id,state,stage)
  VALUES(ev.org_id,doc.id,ver.id,source_id,'full','outbox.'||ev.id::text,ev.id,'queued','queued') ON CONFLICT (org_id,idempotency_key) DO NOTHING;
  SELECT dpr.* INTO run FROM public.document_processing_runs AS dpr WHERE dpr.org_id=ev.org_id AND dpr.idempotency_key='outbox.'||ev.id::text FOR UPDATE;
  -- Legacy processing has no run-level fence around downstream effects. Once
  -- reconciliation records an open recovery case it is terminal to automated
  -- claims; do not clear the fence or lease it again on a later dispatch.
  IF run.safe_error_code='legacy_processing_recovery_required'
     OR EXISTS (SELECT 1 FROM public.document_processing_recovery_cases AS rc WHERE rc.processing_run_id=run.id AND rc.state='open') THEN
    RETURN QUERY SELECT 'recovery_required'::text,run.id,doc.id,ver.id,doc.matter_id,doc.created_by,NULL::text,NULL::text,NULL::uuid; RETURN;
  END IF;
  IF run.state='completed' OR run.state='cancelled' THEN RETURN QUERY SELECT 'already_complete'::text,run.id,doc.id,ver.id,doc.matter_id,doc.created_by,NULL::text,NULL::text,NULL::uuid; RETURN; END IF;
  IF run.state='running' AND run.lease_expires_at>now() THEN RETURN QUERY SELECT 'already_claimed'::text,run.id,doc.id,ver.id,doc.matter_id,doc.created_by,NULL::text,NULL::text,NULL::uuid; RETURN; END IF;
  token:=gen_random_uuid(); UPDATE public.document_processing_runs AS dpr SET state='running',stage='extracting',started_at=coalesce(dpr.started_at,now()),failed_at=NULL,lease_token=token,lease_expires_at=now()+interval '10 minutes',heartbeat_at=now(),attempt_count=dpr.attempt_count+1,trigger_run_id=coalesce(p_trigger_run_id,dpr.trigger_run_id),safe_error_code=NULL WHERE dpr.id=run.id;
  RETURN QUERY SELECT 'claimed'::text,run.id,doc.id,ver.id,doc.matter_id,doc.created_by,asset.bucket_id,asset.object_key,token;
END $$;

CREATE OR REPLACE FUNCTION public.reconcile_document_processing_work(p_batch_size integer DEFAULT 100)
RETURNS TABLE(validation_requeued integer, processing_requeued integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE validation_count integer:=0; recovery_count integer:=0;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'invalid batch size'; END IF;
  WITH candidates AS (
    SELECT sar.id,sar.outbox_event_id FROM public.source_analysis_runs AS sar
    WHERE sar.outbox_event_id IS NOT NULL AND sar.state='running' AND sar.lease_expires_at<=now()
    ORDER BY coalesce(sar.lease_expires_at,sar.created_at) FOR UPDATE SKIP LOCKED LIMIT p_batch_size
  ), reset_runs AS (
    UPDATE public.source_analysis_runs AS sar
    SET state='queued',started_at=NULL,failed_at=NULL,safe_error_code='work_requeued',
        lease_token=NULL,lease_expires_at=NULL,heartbeat_at=now()
    FROM candidates AS c WHERE sar.id=c.id RETURNING c.outbox_event_id
  ), reset_events AS (
    UPDATE public.outbox_events AS oe
    SET delivery_state='pending',delivered_at=NULL,failed_at=NULL,lease_token=NULL,
        lease_expires_at=NULL,next_attempt_at=now(),last_error_code='dispatch_failed',updated_at=now()
    FROM reset_runs AS r WHERE oe.id=r.outbox_event_id AND oe.delivery_state='delivered'
    RETURNING oe.id
  ) SELECT count(*) INTO validation_count FROM reset_events;

  WITH candidates AS (
    SELECT dpr.id,dpr.org_id
    FROM public.document_processing_runs AS dpr
    WHERE dpr.outbox_event_id IS NOT NULL
      AND (dpr.state='failed' OR (dpr.state='running' AND dpr.lease_expires_at<=now()))
    ORDER BY coalesce(dpr.lease_expires_at,dpr.failed_at,dpr.created_at)
    FOR UPDATE SKIP LOCKED LIMIT p_batch_size
  ), fenced AS (
    UPDATE public.document_processing_runs AS dpr
    SET state='failed',stage='failed',failed_at=coalesce(dpr.failed_at,now()),
        safe_error_code='legacy_processing_recovery_required',lease_token=NULL,
        lease_expires_at=NULL,heartbeat_at=now()
    FROM candidates AS c WHERE dpr.id=c.id
    RETURNING dpr.id,dpr.org_id
  ), recorded AS (
    INSERT INTO public.document_processing_recovery_cases(org_id,processing_run_id,recovery_reason)
    SELECT org_id,id,'legacy_processing_replay_unsafe' FROM fenced
    ON CONFLICT (processing_run_id) DO UPDATE SET updated_at=now()
    RETURNING id
  ) SELECT count(*) INTO recovery_count FROM recorded;

  RETURN QUERY SELECT validation_count,0;
END $$;

CREATE OR REPLACE VIEW public.document_processing_orchestration_diagnostics AS
SELECT 'source_analysis'::text AS run_kind,state::text,count(*)::bigint AS run_count,
       max(now()-coalesce(heartbeat_at,started_at,created_at)) AS oldest_age,max(safe_error_code) AS safe_error_code
FROM public.source_analysis_runs GROUP BY state
UNION ALL
SELECT 'document_processing',state::text,count(*)::bigint,
       max(now()-coalesce(heartbeat_at,started_at,created_at)),max(safe_error_code)
FROM public.document_processing_runs GROUP BY state
UNION ALL
SELECT 'document_processing_recovery',state,count(*)::bigint,max(now()-created_at),max(recovery_reason)
FROM public.document_processing_recovery_cases GROUP BY state;

REVOKE ALL ON FUNCTION public.get_document_version_read_grant(uuid), public.record_document_asset_storage_deleted(uuid), public.record_document_upload_observed_bytes(uuid,bigint), public.claim_document_asset_storage_deletion_work(integer), public.finish_document_asset_storage_deletion_work(uuid,uuid,text), public.reconcile_document_processing_work(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_document_version_read_grant(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_document_asset_storage_deleted(uuid), public.record_document_upload_observed_bytes(uuid,bigint), public.claim_document_asset_storage_deletion_work(integer), public.finish_document_asset_storage_deletion_work(uuid,uuid,text), public.reconcile_document_processing_work(integer) TO service_role;
REVOKE ALL ON TABLE public.document_processing_orchestration_diagnostics FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.document_processing_orchestration_diagnostics TO service_role, postgres;
COMMIT;
