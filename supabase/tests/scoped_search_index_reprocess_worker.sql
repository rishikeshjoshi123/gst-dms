-- Run after migration 00057 against a disposable local Supabase database.
BEGIN;

DO $setup$
DECLARE
  owner uuid:='55100000-0000-0000-0000-000000000001';
  org_id uuid:='55000000-0000-0000-0000-000000000001';
  client_id uuid:='55200000-0000-0000-0000-000000000001';
  matter_id uuid:='55300000-0000-0000-0000-000000000001';
  asset_id uuid:='55400000-0000-0000-0000-000000000001';
  document_id uuid:='55500000-0000-0000-0000-000000000001';
  version_id uuid:='55600000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000',owner,'authenticated','authenticated','search-worker@test','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES(org_id,'Search worker org',owner);
  INSERT INTO public.clients(id,org_id,name) VALUES(client_id,org_id,'Search worker client');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES(matter_id,org_id,client_id,'Search worker matter');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
  VALUES(asset_id,org_id,'documents','orgs/'||org_id||'/assets/'||asset_id||'/original.pdf',10,'application/pdf','available',now(),1,owner);
  INSERT INTO public.documents(id,org_id,matter_id,display_title,origin_kind,record_state,content_availability,status,doc_type,reference_number,summary,financial_year,issued_by,storage_path,created_by)
  VALUES(document_id,org_id,matter_id,'Search target','upload','active','source_attached','placed','SCN','SCN/1','Synthetic index-safe summary.','2024-25','Authority',NULL,owner);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,validation_state,state,validated_at,promoted_at)
  VALUES(version_id,org_id,document_id,asset_id,1,'target.pdf','valid','current',now(),now());
  UPDATE public.documents SET current_version_id=version_id WHERE id=document_id;
END $setup$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','55100000-0000-0000-0000-000000000001',true);
DO $request$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.request_document_reprocess(
    '55500000-0000-0000-0000-000000000001','search_index',
    '55700000-0000-0000-0000-000000000001',5
  );
  IF result.code<>'queued' THEN RAISE EXCEPTION 'search-index reprocess was not queued'; END IF;
  PERFORM set_config('test.search_worker_event',result.outbox_event_id::text,true);
  PERFORM set_config('test.search_worker_run',result.processing_run_id::text,true);
END $request$;
RESET ROLE;

DO $delivery_lease$
BEGIN
  UPDATE public.outbox_events SET delivery_state='leased',lease_token='55800000-0000-0000-0000-000000000001',
    lease_expires_at=now()+interval '2 minutes',delivered_at=NULL,failed_at=NULL
  WHERE id=current_setting('test.search_worker_event')::uuid;
END $delivery_lease$;

SET LOCAL ROLE service_role;
DO $claim_and_finish$
DECLARE claim record; input_row record; finish_row record; replay record;
BEGIN
  SELECT * INTO claim FROM public.claim_document_search_index_reprocess_work(
    current_setting('test.search_worker_event')::uuid,'scoped-search-test',
    '55000000-0000-0000-0000-000000000001','55800000-0000-0000-0000-000000000001'
  );
  IF claim.code<>'claimed' OR claim.org_id<>'55000000-0000-0000-0000-000000000001'::uuid
     OR claim.document_id<>'55500000-0000-0000-0000-000000000001'::uuid
     OR claim.document_version_id<>'55600000-0000-0000-0000-000000000001'::uuid
     OR claim.lease_token IS NULL THEN
    RAISE EXCEPTION 'search-index claim did not fence exact version identity';
  END IF;
  SELECT * INTO input_row FROM public.get_document_search_index_reprocess_input(claim.processing_run_id,claim.lease_token);
  IF input_row.code<>'ready' OR input_row.summary<>'Synthetic index-safe summary.'
     OR input_row.reference_number<>'SCN/1' THEN
    RAISE EXCEPTION 'search-index worker input was not the bounded typed projection';
  END IF;
  SELECT * INTO finish_row FROM public.finish_document_search_index_reprocess_work(
    claim.processing_run_id,claim.lease_token,'indexed',
    ('['||repeat('0,',767)||'0]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7
  );
  IF finish_row.code<>'indexed' THEN RAISE EXCEPTION 'search-index completion was not accepted'; END IF;
  SELECT * INTO replay FROM public.finish_document_search_index_reprocess_work(
    claim.processing_run_id,claim.lease_token,'indexed',
    ('['||repeat('0,',767)||'0]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7
  );
  IF replay.code<>'already_complete' THEN RAISE EXCEPTION 'search-index completion was not idempotent'; END IF;
END $claim_and_finish$;
RESET ROLE;

DO $completion_inspection$
BEGIN
  IF (SELECT state FROM public.document_processing_runs WHERE id=current_setting('test.search_worker_run')::uuid)<>'completed'
     OR (SELECT stage FROM public.document_processing_runs WHERE id=current_setting('test.search_worker_run')::uuid)<>'ready'
     OR (SELECT content_availability FROM public.documents WHERE id='55500000-0000-0000-0000-000000000001')<>'source_indexed'
     OR (SELECT embedding_model FROM public.documents WHERE id='55500000-0000-0000-0000-000000000001')<>'gemini-embedding-001'
     OR (SELECT vector_dims(embedding) FROM public.documents WHERE id='55500000-0000-0000-0000-000000000001')<>768 THEN
    RAISE EXCEPTION 'search-index completion did not make the canonical projection ready';
  END IF;
END $completion_inspection$;

SET LOCAL ROLE service_role;
DO $tenant_and_scope_fences$
DECLARE denied record; source_definition text;
BEGIN
  SELECT * INTO denied FROM public.claim_document_search_index_reprocess_work(
    current_setting('test.search_worker_event')::uuid,'scoped-search-test',
    '55000000-0000-0000-0000-000000000002','55800000-0000-0000-0000-000000000001'
  );
  IF denied.code<>'delivery_lease_invalid' THEN RAISE EXCEPTION 'claim accepted a forged organisation'; END IF;
  SELECT pg_get_functiondef('public.get_document_search_index_reprocess_input(uuid,uuid)'::regprocedure)
  INTO source_definition;
  IF source_definition ~* '(raw_metadata|object_key|storage_path|signed_url)' THEN
    RAISE EXCEPTION 'search-index worker input exposes source content or paths';
  END IF;
END $tenant_and_scope_fences$;
RESET ROLE;

-- A provider/worker failure waits for the persisted deterministic backoff
-- before its two safe retries (three claims total), then becomes
-- Review/recovery rather than an unbounded automatic replay.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','55100000-0000-0000-0000-000000000001',true);
DO $exhaust_request$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.request_document_reprocess(
    '55500000-0000-0000-0000-000000000001','search_index',
    '55700000-0000-0000-0000-000000000002',5
  );
  PERFORM set_config('test.search_retry_run',result.processing_run_id::text,true);
  PERFORM set_config('test.search_retry_event',result.outbox_event_id::text,true);
END $exhaust_request$;
RESET ROLE;

DO $exhaust_setup$
BEGIN
  UPDATE public.document_processing_runs
  SET state='failed',stage='failed',failed_at=now(),started_at=now()-interval '1 minute',
      attempt_count=1,safe_error_code='search_index_failed',
      next_retry_at=now()+make_interval(secs => public.search_index_reprocess_retry_delay_seconds(
        current_setting('test.search_retry_run')::uuid,1
      ))
  WHERE id=current_setting('test.search_retry_run')::uuid;
  UPDATE public.outbox_events SET delivery_state='delivered',delivered_at=now(),lease_token=NULL,lease_expires_at=NULL
  WHERE id=current_setting('test.search_retry_event')::uuid;
END $exhaust_setup$;

DO $retry_schedule$
DECLARE delay_seconds integer; retry_at timestamptz; reconciliation record;
BEGIN
  SELECT public.search_index_reprocess_retry_delay_seconds(
    current_setting('test.search_retry_run')::uuid,1
  ) INTO delay_seconds;
  SELECT next_retry_at INTO retry_at FROM public.document_processing_runs
  WHERE id=current_setting('test.search_retry_run')::uuid;
  IF delay_seconds NOT BETWEEN 30 AND 44
     OR retry_at IS NULL THEN
    RAISE EXCEPTION 'first search-index retry schedule is not bounded and deterministic';
  END IF;
  SELECT * INTO reconciliation FROM public.reconcile_document_processing_work(10);
  IF reconciliation.processing_requeued<>0
     OR (SELECT state FROM public.document_processing_runs WHERE id=current_setting('test.search_retry_run')::uuid)<>'failed' THEN
    RAISE EXCEPTION 'search-index retry bypassed its persisted backoff';
  END IF;
  UPDATE public.document_processing_runs SET next_retry_at=now()-interval '1 second'
  WHERE id=current_setting('test.search_retry_run')::uuid;
  SELECT * INTO reconciliation FROM public.reconcile_document_processing_work(10);
  IF reconciliation.processing_requeued<>1
     OR (SELECT state FROM public.document_processing_runs WHERE id=current_setting('test.search_retry_run')::uuid)<>'queued' THEN
    RAISE EXCEPTION 'due search-index retry was not requeued exactly once';
  END IF;
END $retry_schedule$;

DO $exhaust_after_retry$
BEGIN
  UPDATE public.document_processing_runs
  SET state='failed',stage='failed',failed_at=now(),started_at=now()-interval '1 minute',
      attempt_count=3,safe_error_code='search_index_failed',next_retry_at=NULL
  WHERE id=current_setting('test.search_retry_run')::uuid;
  UPDATE public.outbox_events SET delivery_state='delivered',delivered_at=now(),lease_token=NULL,lease_expires_at=NULL
  WHERE id=current_setting('test.search_retry_event')::uuid;
END $exhaust_after_retry$;

SET LOCAL ROLE service_role;
SELECT * FROM public.reconcile_document_processing_work(10);
RESET ROLE;

DO $exhaust_inspection$
BEGIN
  IF (SELECT state FROM public.document_processing_runs WHERE id=current_setting('test.search_retry_run')::uuid)<>'failed'
     OR (SELECT stage FROM public.document_processing_runs WHERE id=current_setting('test.search_retry_run')::uuid)<>'review'
     OR (SELECT safe_error_code FROM public.document_processing_runs WHERE id=current_setting('test.search_retry_run')::uuid)<>'search_index_retry_exhausted'
     OR NOT EXISTS (
       SELECT 1 FROM public.document_processing_recovery_cases
       WHERE processing_run_id=current_setting('test.search_retry_run')::uuid
         AND recovery_reason='scoped_search_index_retry_exhausted' AND state='open'
     ) THEN
    RAISE EXCEPTION 'search-index retry exhaustion did not enter recovery';
  END IF;
END $exhaust_inspection$;

-- A queued retired-scope event from before 00056 cannot be acknowledged and
-- stranded. Reconciliation terminalizes the envelope and opens recovery.
DO $legacy_scope_setup$
DECLARE legacy_event uuid:='55900000-0000-0000-0000-000000000001';
DECLARE legacy_run uuid:='56000000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO public.outbox_events(id,org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key)
  VALUES(legacy_event,'55000000-0000-0000-0000-000000000001','document',
    '55500000-0000-0000-0000-000000000001','document.reprocess_requested.v1',
    jsonb_build_object('document_id','55500000-0000-0000-0000-000000000001',
      'version_id','55600000-0000-0000-0000-000000000001','scope','ocr'),
    'legacy-ocr-reprocess');
  INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,outbox_event_id)
  VALUES(legacy_run,'55000000-0000-0000-0000-000000000001',
    '55500000-0000-0000-0000-000000000001','55600000-0000-0000-0000-000000000001',
    'ocr','legacy-ocr-run',legacy_event);
  PERFORM set_config('test.legacy_scope_event',legacy_event::text,true);
  PERFORM set_config('test.legacy_scope_run',legacy_run::text,true);
END $legacy_scope_setup$;

SET LOCAL ROLE service_role;
SELECT * FROM public.reconcile_document_processing_work(10);
RESET ROLE;

DO $legacy_scope_inspection$
BEGIN
  IF (SELECT state FROM public.document_processing_runs WHERE id=current_setting('test.legacy_scope_run')::uuid)<>'failed'
     OR (SELECT stage FROM public.document_processing_runs WHERE id=current_setting('test.legacy_scope_run')::uuid)<>'review'
     OR (SELECT safe_error_code FROM public.document_processing_runs WHERE id=current_setting('test.legacy_scope_run')::uuid)<>'scoped_reprocess_unavailable'
     OR (SELECT delivery_state FROM public.outbox_events WHERE id=current_setting('test.legacy_scope_event')::uuid)<>'dead_letter'
     OR NOT EXISTS (
       SELECT 1 FROM public.document_processing_recovery_cases
       WHERE processing_run_id=current_setting('test.legacy_scope_run')::uuid
         AND recovery_reason='scoped_reprocess_unavailable' AND state='open'
     ) THEN
    RAISE EXCEPTION 'legacy unavailable scoped reprocess was not terminalized into recovery';
  END IF;
END $legacy_scope_inspection$;

-- The Trigger-side fence handles the narrow race where a legacy envelope was
-- already leased when 00057 was applied; it transitions the run before the
-- dispatcher can acknowledge delivery.
DO $leased_legacy_scope_setup$
DECLARE legacy_event uuid:='56100000-0000-0000-0000-000000000001';
DECLARE legacy_run uuid:='56200000-0000-0000-0000-000000000001';
DECLARE delivery_lease uuid:='56300000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO public.outbox_events(id,org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key,
    delivery_state,attempt_count,lease_token,lease_expires_at)
  VALUES(legacy_event,'55000000-0000-0000-0000-000000000001','document',
    '55500000-0000-0000-0000-000000000001','document.reprocess_requested.v1',
    jsonb_build_object('document_id','55500000-0000-0000-0000-000000000001',
      'version_id','55600000-0000-0000-0000-000000000001','scope','full'),
    'leased-legacy-full-reprocess','leased',1,delivery_lease,now()+interval '2 minutes');
  INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,outbox_event_id)
  VALUES(legacy_run,'55000000-0000-0000-0000-000000000001',
    '55500000-0000-0000-0000-000000000001','55600000-0000-0000-0000-000000000001',
    'full','leased-legacy-full-run',legacy_event);
  PERFORM set_config('test.leased_legacy_scope_event',legacy_event::text,true);
  PERFORM set_config('test.leased_legacy_scope_run',legacy_run::text,true);
  PERFORM set_config('test.leased_legacy_scope_token',delivery_lease::text,true);
END $leased_legacy_scope_setup$;

SET LOCAL ROLE service_role;
DO $leased_legacy_scope_recovery$
DECLARE recovery record;
BEGIN
  SELECT * INTO recovery FROM public.recover_unavailable_document_reprocess_event(
    current_setting('test.leased_legacy_scope_event')::uuid,
    '55000000-0000-0000-0000-000000000001',
    current_setting('test.leased_legacy_scope_token')::uuid
  );
  IF recovery.code<>'recovery_opened' THEN
    RAISE EXCEPTION 'leased legacy scoped event was not recovered';
  END IF;
END $leased_legacy_scope_recovery$;
RESET ROLE;

DO $leased_legacy_scope_inspection$
BEGIN
  IF (SELECT state FROM public.document_processing_runs WHERE id=current_setting('test.leased_legacy_scope_run')::uuid)<>'failed'
     OR (SELECT delivery_state FROM public.outbox_events WHERE id=current_setting('test.leased_legacy_scope_event')::uuid)<>'dead_letter'
     OR NOT EXISTS (
       SELECT 1 FROM public.document_processing_recovery_cases
       WHERE processing_run_id=current_setting('test.leased_legacy_scope_run')::uuid
         AND recovery_reason='scoped_reprocess_unavailable' AND state='open'
     ) THEN
    RAISE EXCEPTION 'leased legacy scoped event was acknowledged instead of recovered';
  END IF;
END $leased_legacy_scope_inspection$;

DO $surface$
BEGIN
  IF has_function_privilege('anon','public.claim_document_search_index_reprocess_work(uuid,text,uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.claim_document_search_index_reprocess_work(uuid,text,uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.claim_document_search_index_reprocess_work(uuid,text,uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.finish_document_search_index_reprocess_work(uuid,uuid,text,vector,text,text,integer)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.finish_document_search_index_reprocess_work(uuid,uuid,text,vector,text,text,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'scoped search worker grant surface';
  END IF;
END $surface$;

ROLLBACK;
