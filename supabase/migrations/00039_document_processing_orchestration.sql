-- Version-scoped validation and processing claims for durable outbox work.
BEGIN;

ALTER TABLE public.source_analysis_runs
  ADD COLUMN outbox_event_id uuid REFERENCES public.outbox_events(id) ON DELETE RESTRICT,
  ADD COLUMN lease_token uuid,
  ADD COLUMN lease_expires_at timestamptz,
  ADD COLUMN heartbeat_at timestamptz,
  ADD COLUMN attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  ADD CONSTRAINT source_analysis_runs_event_unique UNIQUE (outbox_event_id);
ALTER TABLE public.document_processing_runs
  ADD COLUMN outbox_event_id uuid REFERENCES public.outbox_events(id) ON DELETE RESTRICT,
  ADD COLUMN lease_token uuid,
  ADD COLUMN lease_expires_at timestamptz,
  ADD COLUMN heartbeat_at timestamptz,
  ADD COLUMN attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  ADD COLUMN trigger_run_id text,
  ADD CONSTRAINT document_processing_runs_event_unique UNIQUE (outbox_event_id);
CREATE INDEX source_analysis_runs_claim_idx ON public.source_analysis_runs(state, lease_expires_at);
CREATE INDEX document_processing_runs_claim_idx ON public.document_processing_runs(state, lease_expires_at);

CREATE OR REPLACE FUNCTION public.claim_document_validation_work(p_event_id uuid)
RETURNS TABLE(code text, source_run_id uuid, intake_id uuid, asset_id uuid, bucket_id text, object_key text, expected_bytes bigint, lease_token uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE ev public.outbox_events%ROWTYPE; intake public.intake_items%ROWTYPE; asset public.file_assets%ROWTYPE; run public.source_analysis_runs%ROWTYPE; token uuid;
BEGIN
  IF p_event_id IS NULL THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::uuid; RETURN; END IF;
  SELECT oe.* INTO ev FROM public.outbox_events AS oe WHERE oe.id=p_event_id FOR UPDATE;
  IF ev.id IS NULL OR ev.event_kind<>'document.upload_validation_requested.v1' THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::uuid; RETURN; END IF;
  IF ev.aggregate_type<>'document_upload' OR jsonb_typeof(ev.payload)<>'object' OR NOT pg_input_is_valid(ev.payload->>'intake_id','uuid') OR NOT pg_input_is_valid(ev.payload->>'asset_id','uuid') OR NOT pg_input_is_valid(ev.payload->>'session_id','uuid') THEN RETURN QUERY SELECT 'invalid_event'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::uuid; RETURN; END IF;
  SELECT ii.* INTO intake FROM public.intake_items AS ii WHERE ii.id=(ev.payload->>'intake_id')::uuid AND ii.org_id=ev.org_id AND ii.upload_session_id=(ev.payload->>'session_id')::uuid FOR UPDATE;
  SELECT fa.* INTO asset FROM public.file_assets AS fa WHERE fa.id=intake.asset_id AND fa.org_id=ev.org_id FOR UPDATE;
  IF intake.id IS NULL OR asset.id IS NULL OR asset.id<>(ev.payload->>'asset_id')::uuid OR ev.aggregate_id IS DISTINCT FROM intake.upload_session_id OR intake.state NOT IN ('uploaded','validating','processing') THEN RETURN QUERY SELECT 'invalid_event'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::bigint,NULL::uuid; RETURN; END IF;
  INSERT INTO public.source_analysis_runs(org_id,asset_id,request_key,outbox_event_id,state)
  VALUES(ev.org_id,asset.id,'validation.'||ev.id::text,ev.id,'queued')
  ON CONFLICT (org_id,request_key) DO NOTHING;
  SELECT sar.* INTO run FROM public.source_analysis_runs AS sar WHERE sar.org_id=ev.org_id AND sar.request_key='validation.'||ev.id::text FOR UPDATE;
  IF run.state='succeeded' THEN RETURN QUERY SELECT 'already_complete'::text,run.id,intake.id,asset.id,NULL::text,NULL::text,NULL::bigint,NULL::uuid; RETURN; END IF;
  IF run.state='running' AND run.lease_expires_at>now() THEN RETURN QUERY SELECT 'already_claimed'::text,run.id,intake.id,asset.id,NULL::text,NULL::text,NULL::bigint,NULL::uuid; RETURN; END IF;
  token:=gen_random_uuid();
  UPDATE public.source_analysis_runs AS sar SET state='running',started_at=coalesce(sar.started_at,now()),failed_at=NULL,lease_token=token,lease_expires_at=now()+interval '5 minutes',heartbeat_at=now(),attempt_count=sar.attempt_count+1,safe_error_code=NULL WHERE sar.id=run.id;
  UPDATE public.intake_items AS ii SET state='validating',updated_at=now() WHERE ii.id=intake.id AND ii.state IN ('uploaded','validating','processing');
  RETURN QUERY SELECT 'claimed'::text,run.id,intake.id,asset.id,asset.bucket_id,asset.object_key,asset.byte_size,token;
END $$;

CREATE OR REPLACE FUNCTION public.finish_document_validation_work(p_source_run_id uuid,p_lease_token uuid,p_outcome text,p_page_count integer)
RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE run public.source_analysis_runs%ROWTYPE; ev public.outbox_events%ROWTYPE; result record;
BEGIN
  IF p_source_run_id IS NULL OR p_lease_token IS NULL OR p_outcome NOT IN ('ready','invalid_pdf','encrypted_pdf','storage_missing','validation_failed') THEN RETURN QUERY SELECT 'invalid_request'::text; RETURN; END IF;
  SELECT sar.* INTO run FROM public.source_analysis_runs AS sar WHERE sar.id=p_source_run_id FOR UPDATE;
  IF run.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text; RETURN; END IF;
  IF run.state='succeeded' THEN RETURN QUERY SELECT 'already_complete'::text; RETURN; END IF;
  IF run.state<>'running' OR run.lease_token IS DISTINCT FROM p_lease_token OR run.lease_expires_at<=now() THEN RETURN QUERY SELECT 'stale_lease'::text; RETURN; END IF;
  SELECT oe.* INTO ev FROM public.outbox_events AS oe WHERE oe.id=run.outbox_event_id;
  IF ev.id IS NULL OR jsonb_typeof(ev.payload)<>'object' OR NOT pg_input_is_valid(ev.payload->>'intake_id','uuid') THEN RETURN QUERY SELECT 'invalid_event'::text; RETURN; END IF;
  SELECT * INTO result FROM public.validate_document_intake_asset((ev.payload->>'intake_id')::uuid,p_page_count,p_outcome,ev.id);
  UPDATE public.source_analysis_runs AS sar SET state=CASE WHEN result.code IN ('ok','already_ready') THEN 'succeeded'::public.source_analysis_run_state ELSE 'failed'::public.source_analysis_run_state END, completed_at=CASE WHEN result.code IN ('ok','already_ready') THEN now() ELSE NULL END, failed_at=CASE WHEN result.code IN ('ok','already_ready') THEN NULL ELSE now() END, safe_error_code=CASE WHEN result.code IN ('ok','already_ready') THEN NULL ELSE result.code END,lease_token=NULL,lease_expires_at=NULL,heartbeat_at=now() WHERE sar.id=run.id;
  RETURN QUERY SELECT result.code::text;
END $$;

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
  IF doc.id IS NULL OR ver.id IS NULL OR doc.record_state<>'active' OR doc.current_version_id IS DISTINCT FROM ver.id OR ver.state<>'current' OR asset.availability<>'available' THEN RETURN QUERY SELECT 'no_work'::text,NULL::uuid,doc.id,ver.id,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::uuid; RETURN; END IF;
  SELECT sar.id INTO source_id FROM public.document_version_analysis_bindings AS bind JOIN public.source_analysis_runs AS sar ON sar.id=bind.source_analysis_run_id AND sar.org_id=bind.org_id WHERE bind.document_version_id=ver.id AND bind.org_id=ev.org_id AND sar.asset_id=asset.id AND sar.state='succeeded' ORDER BY sar.completed_at DESC NULLS LAST LIMIT 1;
  IF source_id IS NULL THEN
    SELECT sar.id INTO source_id FROM public.source_analysis_runs AS sar WHERE sar.org_id=ev.org_id AND sar.asset_id=asset.id AND sar.state='succeeded' AND sar.request_key='validation.'||sar.outbox_event_id::text ORDER BY sar.completed_at DESC NULLS LAST LIMIT 1;
    IF source_id IS NOT NULL THEN INSERT INTO public.document_version_analysis_bindings(org_id,document_version_id,source_analysis_run_id,binding_reason) VALUES(ev.org_id,ver.id,source_id,'processing_validation') ON CONFLICT (document_version_id,source_analysis_run_id) DO NOTHING; END IF;
  END IF;
  INSERT INTO public.document_processing_runs(org_id,document_id,document_version_id,source_analysis_run_id,scope,idempotency_key,outbox_event_id,state,stage)
  VALUES(ev.org_id,doc.id,ver.id,source_id,'full','outbox.'||ev.id::text,ev.id,'queued','queued') ON CONFLICT (org_id,idempotency_key) DO NOTHING;
  SELECT dpr.* INTO run FROM public.document_processing_runs AS dpr WHERE dpr.org_id=ev.org_id AND dpr.idempotency_key='outbox.'||ev.id::text FOR UPDATE;
  IF run.state='completed' OR run.state='cancelled' THEN RETURN QUERY SELECT 'already_complete'::text,run.id,doc.id,ver.id,doc.matter_id,doc.created_by,NULL::text,NULL::text,NULL::uuid; RETURN; END IF;
  IF run.state='running' AND run.lease_expires_at>now() THEN RETURN QUERY SELECT 'already_claimed'::text,run.id,doc.id,ver.id,doc.matter_id,doc.created_by,NULL::text,NULL::text,NULL::uuid; RETURN; END IF;
  token:=gen_random_uuid(); UPDATE public.document_processing_runs AS dpr SET state='running',stage='extracting',started_at=coalesce(dpr.started_at,now()),failed_at=NULL,lease_token=token,lease_expires_at=now()+interval '10 minutes',heartbeat_at=now(),attempt_count=dpr.attempt_count+1,trigger_run_id=coalesce(p_trigger_run_id,dpr.trigger_run_id),safe_error_code=NULL WHERE dpr.id=run.id;
  RETURN QUERY SELECT 'claimed'::text,run.id,doc.id,ver.id,doc.matter_id,doc.created_by,asset.bucket_id,asset.object_key,token;
END $$;

CREATE OR REPLACE FUNCTION public.finish_document_processing_work(p_processing_run_id uuid,p_lease_token uuid,p_outcome text)
RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE run public.document_processing_runs%ROWTYPE;
BEGIN
  IF p_processing_run_id IS NULL OR p_lease_token IS NULL OR p_outcome NOT IN ('placed','needs_review','failed','no_work') THEN RETURN QUERY SELECT 'invalid_request'::text; RETURN; END IF;
  SELECT dpr.* INTO run FROM public.document_processing_runs AS dpr WHERE dpr.id=p_processing_run_id FOR UPDATE;
  IF run.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text; RETURN; END IF;
  IF run.state IN ('completed','cancelled') THEN RETURN QUERY SELECT 'already_complete'::text; RETURN; END IF;
  IF run.state<>'running' OR run.lease_token IS DISTINCT FROM p_lease_token OR run.lease_expires_at<=now() THEN RETURN QUERY SELECT 'stale_lease'::text; RETURN; END IF;
  UPDATE public.document_processing_runs AS dpr SET state=CASE WHEN p_outcome='no_work' THEN 'cancelled'::public.document_processing_state WHEN p_outcome IN ('placed','needs_review') THEN 'completed'::public.document_processing_state ELSE 'failed'::public.document_processing_state END,stage=CASE WHEN p_outcome='placed' THEN 'ready'::public.document_processing_stage WHEN p_outcome='needs_review' THEN 'review'::public.document_processing_stage WHEN p_outcome='failed' THEN 'failed'::public.document_processing_stage ELSE dpr.stage END,started_at=CASE WHEN p_outcome='no_work' THEN NULL ELSE dpr.started_at END,completed_at=CASE WHEN p_outcome IN ('placed','needs_review') THEN now() ELSE NULL END,failed_at=CASE WHEN p_outcome='failed' THEN now() ELSE NULL END,safe_error_code=CASE WHEN p_outcome='failed' THEN 'processing_failed' ELSE NULL END,lease_token=NULL,lease_expires_at=NULL,heartbeat_at=now() WHERE dpr.id=run.id;
  IF p_outcome='placed' THEN UPDATE public.documents AS d SET content_availability='source_indexed' WHERE d.id=run.document_id AND d.current_version_id=run.document_version_id AND d.record_state='active'; END IF;
  RETURN QUERY SELECT p_outcome::text;
END $$;

CREATE VIEW public.document_processing_orchestration_diagnostics AS
SELECT 'source_analysis'::text AS run_kind,state::text,count(*)::bigint AS run_count,max(now()-coalesce(heartbeat_at,started_at,created_at)) AS oldest_age,max(safe_error_code) AS safe_error_code FROM public.source_analysis_runs GROUP BY state
UNION ALL SELECT 'document_processing',state::text,count(*)::bigint,max(now()-coalesce(heartbeat_at,started_at,created_at)),max(safe_error_code) FROM public.document_processing_runs GROUP BY state;

REVOKE ALL ON TABLE public.source_analysis_runs, public.document_processing_runs FROM service_role;
REVOKE ALL ON FUNCTION public.claim_document_validation_work(uuid), public.finish_document_validation_work(uuid,uuid,text,integer), public.claim_document_processing_work(uuid,text), public.finish_document_processing_work(uuid,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_document_validation_work(uuid), public.finish_document_validation_work(uuid,uuid,text,integer), public.claim_document_processing_work(uuid,text), public.finish_document_processing_work(uuid,uuid,text) TO service_role;
REVOKE ALL ON TABLE public.document_processing_orchestration_diagnostics FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.document_processing_orchestration_diagnostics TO service_role, postgres;
COMMIT;
