-- Run after migration 00057 against a disposable local Supabase database.
BEGIN;

DO $setup$
DECLARE
  org_a uuid:='54000000-0000-0000-0000-000000000001';
  org_b uuid:='54000000-0000-0000-0000-000000000002';
  owner uuid:='54100000-0000-0000-0000-000000000001';
  viewer uuid:='54100000-0000-0000-0000-000000000002';
  other uuid:='54100000-0000-0000-0000-000000000003';
  client_id uuid:='54200000-0000-0000-0000-000000000001';
  foreign_client uuid:='54200000-0000-0000-0000-000000000002';
  matter_id uuid:='54300000-0000-0000-0000-000000000001';
  foreign_matter uuid:='54300000-0000-0000-0000-000000000002';
  asset_id uuid:='54400000-0000-0000-0000-000000000001';
  document_id uuid:='54500000-0000-0000-0000-000000000001';
  version_id uuid:='54600000-0000-0000-0000-000000000001';
  foreign_document uuid:='54500000-0000-0000-0000-000000000002';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  SELECT '00000000-0000-0000-0000-000000000000',id,'authenticated','authenticated',id::text||'@reprocess.test','x',now(),'{}','{}',now(),now()
  FROM unnest(ARRAY[owner,viewer,other]) AS id;
  INSERT INTO public.organisations(id,name,created_by) VALUES(org_a,'Reprocess A',owner),(org_b,'Reprocess B',other);
  INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at)
  VALUES('54700000-0000-0000-0000-000000000001',org_a,viewer,'viewer','active',1,now());
  INSERT INTO public.clients(id,org_id,name) VALUES(client_id,org_a,'Reprocess client'),(foreign_client,org_b,'Foreign client');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES(matter_id,org_a,client_id,'Reprocess matter'),(foreign_matter,org_b,foreign_client,'Foreign matter');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
  VALUES(asset_id,org_a,'documents','orgs/'||org_a||'/assets/'||asset_id||'/original.pdf',10,'application/pdf','available',now(),1,owner);
  INSERT INTO public.documents(id,org_id,matter_id,display_title,origin_kind,record_state,content_availability,status,storage_path,created_by)
  VALUES(document_id,org_a,matter_id,'Reprocess target','upload','active','source_attached','placed',NULL,owner),
        (foreign_document,org_b,foreign_matter,'Foreign target','manual_record','active','metadata_only','placed',NULL,other);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,validation_state,state,validated_at,promoted_at)
  VALUES(version_id,org_a,document_id,asset_id,1,'target.pdf','valid','current',now(),now());
  UPDATE public.documents SET current_version_id=version_id WHERE id=document_id;
END $setup$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','54100000-0000-0000-0000-000000000001',true);
DO $owner_command$
DECLARE first_result record; replay record; conflicting_replay record; invalid_scope record; stale_capability record; procedure_definition text;
BEGIN
  IF NOT public.has_organisation_capability('54000000-0000-0000-0000-000000000001','document.reprocess')
     OR (SELECT capability_version FROM public.get_my_organisation_context() LIMIT 1)<>5 THEN
    RAISE EXCEPTION 'reprocess capability projection';
  END IF;
  SELECT pg_get_functiondef('public.request_document_reprocess_unavailable_scope_fence(uuid,public.document_processing_scope,uuid,integer)'::regprocedure)
  INTO procedure_definition;
  IF position('pg_advisory_xact_lock' IN procedure_definition)=0
     OR position('pg_advisory_xact_lock' IN procedure_definition)>position('SELECT * INTO prior' IN procedure_definition) THEN
    RAISE EXCEPTION 'reprocess advisory idempotency lock must precede receipt lookup';
  END IF;
  SELECT * INTO first_result FROM public.request_document_reprocess(
    '54500000-0000-0000-0000-000000000001','search_index',
    '54800000-0000-0000-0000-000000000001',5
  );
  IF first_result.code<>'queued' OR first_result.document_version_id<>'54600000-0000-0000-0000-000000000001'::uuid
     OR first_result.processing_run_id IS NULL OR first_result.outbox_event_id IS NULL OR first_result.scope<>'search_index' THEN
    RAISE EXCEPTION 'scoped reprocess command did not create durable identity';
  END IF;
  PERFORM set_config('test.reprocess_run',first_result.processing_run_id::text,true);
  PERFORM set_config('test.reprocess_event',first_result.outbox_event_id::text,true);
  SELECT * INTO replay FROM public.request_document_reprocess(
    '54500000-0000-0000-0000-000000000001','search_index',
    '54800000-0000-0000-0000-000000000001',5
  );
  IF replay.code<>'already_requested' OR replay.processing_run_id IS DISTINCT FROM first_result.processing_run_id
     OR replay.outbox_event_id IS DISTINCT FROM first_result.outbox_event_id THEN
    RAISE EXCEPTION 'reprocess idempotency changed durable identity';
  END IF;
  SELECT * INTO conflicting_replay FROM public.request_document_reprocess(
    '54500000-0000-0000-0000-000000000001','ocr',
    '54800000-0000-0000-0000-000000000001',5
  );
  IF conflicting_replay.code<>'scope_unavailable'
     OR conflicting_replay.processing_run_id IS NOT NULL OR conflicting_replay.outbox_event_id IS NOT NULL THEN
    RAISE EXCEPTION 'unimplemented scope created durable work';
  END IF;
  SELECT * INTO invalid_scope FROM public.request_document_reprocess(
    '54500000-0000-0000-0000-000000000001','validate',
    '54800000-0000-0000-0000-000000000002',5
  );
  IF invalid_scope.code<>'scope_unavailable' THEN RAISE EXCEPTION 'unimplemented scope must not queue work'; END IF;
  SELECT * INTO stale_capability FROM public.request_document_reprocess(
    '54500000-0000-0000-0000-000000000001','search_index',
    '54800000-0000-0000-0000-000000000003',4
  );
  IF stale_capability.code<>'capability_version_mismatch' THEN RAISE EXCEPTION 'stale capability projection was accepted'; END IF;
END $owner_command$;
RESET ROLE;

DO $owner_inspection$
DECLARE event_id uuid:=current_setting('test.reprocess_event')::uuid; run_id uuid:=current_setting('test.reprocess_run')::uuid;
BEGIN
  IF (SELECT payload FROM public.outbox_events WHERE id=event_id)
       IS DISTINCT FROM jsonb_build_object('document_id','54500000-0000-0000-0000-000000000001','version_id','54600000-0000-0000-0000-000000000001','scope','search_index')
     OR (SELECT event_kind FROM public.outbox_events WHERE id=event_id)<>'document.reprocess_requested.v1'
     OR (SELECT scope FROM public.document_processing_runs WHERE id=run_id)<>'search_index'
     OR (SELECT state FROM public.document_processing_runs WHERE id=run_id)<>'queued'
     OR EXISTS (SELECT 1 FROM public.outbox_events WHERE id=event_id AND payload::text ~* '(path|object|content|token|credential|raw)') THEN
    RAISE EXCEPTION 'scoped reprocess envelope or run is unsafe';
  END IF;
END $owner_inspection$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','54100000-0000-0000-0000-000000000002',true);
DO $viewer_denial$
DECLARE denied record;
BEGIN
  SELECT * INTO denied FROM public.request_document_reprocess(
    '54500000-0000-0000-0000-000000000001','full',
    '54800000-0000-0000-0000-000000000004',5
  );
  IF denied.code<>'scope_unavailable' THEN RAISE EXCEPTION 'unimplemented scope was not safely rejected'; END IF;
END $viewer_denial$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','54100000-0000-0000-0000-000000000001',true);
DO $tenant_denial$
DECLARE denied record;
BEGIN
  SELECT * INTO denied FROM public.request_document_reprocess(
    '54500000-0000-0000-0000-000000000002','full',
    '54800000-0000-0000-0000-000000000005',5
  );
  IF denied.code<>'scope_unavailable' OR denied.document_id IS NOT NULL THEN
    RAISE EXCEPTION 'cross-tenant reprocess disclosed a target';
  END IF;
END $tenant_denial$;
RESET ROLE;

-- Only the proven idempotent search-index scope is automatically requeued.
-- Every other scoped reprocess is fenced into Review/recovery after an
-- uncertain partial effect, never sent back through a blind replay.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','54100000-0000-0000-0000-000000000001',true);
DO $replay_requests$
DECLARE search_result record; unavailable_result record;
BEGIN
  SELECT * INTO search_result FROM public.request_document_reprocess(
    '54500000-0000-0000-0000-000000000001','search_index',
    '54800000-0000-0000-0000-000000000006',5
  );
  SELECT * INTO unavailable_result FROM public.request_document_reprocess(
    '54500000-0000-0000-0000-000000000001','full',
    '54800000-0000-0000-0000-000000000007',5
  );
  PERFORM set_config('test.reprocess_search_run',search_result.processing_run_id::text,true);
  PERFORM set_config('test.reprocess_search_event',search_result.outbox_event_id::text,true);
  IF unavailable_result.code<>'scope_unavailable' OR unavailable_result.processing_run_id IS NOT NULL OR unavailable_result.outbox_event_id IS NOT NULL THEN
    RAISE EXCEPTION 'full scope must remain unavailable without durable queued work';
  END IF;
END $replay_requests$;
RESET ROLE;

DO $replay_expiry$
BEGIN
  UPDATE public.document_processing_runs
  SET state='running',started_at=now()-interval '15 minutes',lease_token=gen_random_uuid(),
      lease_expires_at=now()-interval '1 minute',heartbeat_at=now()-interval '15 minutes',attempt_count=1
  WHERE id=current_setting('test.reprocess_search_run')::uuid;
  UPDATE public.outbox_events SET delivery_state='delivered',delivered_at=now(),lease_token=NULL,lease_expires_at=NULL
  WHERE id=current_setting('test.reprocess_search_event')::uuid;
END $replay_expiry$;

SET LOCAL ROLE service_role;
DO $replay_reconcile$
DECLARE reconciliation record;
BEGIN
  SELECT * INTO reconciliation FROM public.reconcile_document_processing_work(10);
  PERFORM set_config('test.reprocess_requeued',reconciliation.processing_requeued::text,true);
END $replay_reconcile$;
RESET ROLE;

DO $replay_inspection$
BEGIN
  IF current_setting('test.reprocess_requeued')::integer<>1
     OR (SELECT state FROM public.document_processing_runs WHERE id=current_setting('test.reprocess_search_run')::uuid)<>'queued'
     OR (SELECT delivery_state FROM public.outbox_events WHERE id=current_setting('test.reprocess_search_event')::uuid)<>'pending' THEN
    RAISE EXCEPTION 'scoped reprocess replay fence';
  END IF;
END $replay_inspection$;

DO $surface$
BEGIN
  IF has_function_privilege('anon','public.request_document_reprocess(uuid,public.document_processing_scope,uuid,integer)','EXECUTE')
     OR has_function_privilege('service_role','public.request_document_reprocess(uuid,public.document_processing_scope,uuid,integer)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.request_document_reprocess(uuid,public.document_processing_scope,uuid,integer)','EXECUTE')
     OR has_table_privilege('authenticated','public.outbox_events','INSERT')
     OR has_table_privilege('authenticated','public.document_processing_runs','INSERT') THEN
    RAISE EXCEPTION 'scoped reprocess grant surface';
  END IF;
END $surface$;

ROLLBACK;
