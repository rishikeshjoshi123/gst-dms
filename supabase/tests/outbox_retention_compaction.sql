-- Run after migration 00058 against a disposable local Supabase database.
BEGIN;

DO $fixture$
DECLARE
  owner_id uuid := '58100000-0000-0000-0000-000000000001';
  org_id uuid := '58200000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000',owner_id,'authenticated','authenticated','outbox-retention@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES(org_id,'Outbox retention org',owner_id);
  INSERT INTO public.clients(id,org_id,name)
  VALUES ('58800000-0000-0000-0000-000000000001',org_id,'Outbox retention client');
  INSERT INTO public.matters(id,org_id,client_id,title)
  VALUES ('58900000-0000-0000-0000-000000000001',org_id,'58800000-0000-0000-0000-000000000001','Outbox retention matter');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
  VALUES ('59000000-0000-0000-0000-000000000001',org_id,'documents','orgs/'||org_id||'/assets/59000000-0000-0000-0000-000000000001/original.pdf',10,'application/pdf','available',now(),1,owner_id);
  INSERT INTO public.documents(id,org_id,matter_id,display_title,origin_kind,record_state,content_availability,status,doc_type,reference_number,summary,financial_year,issued_by,storage_path,created_by)
  VALUES ('59100000-0000-0000-0000-000000000001',org_id,'58900000-0000-0000-0000-000000000001','Retention target','upload','active','source_attached','placed','SCN','RET/1','Safe retention fixture.','2024-25','Authority',NULL,owner_id);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,validation_state,state,validated_at,promoted_at)
  VALUES ('59200000-0000-0000-0000-000000000001',org_id,'59100000-0000-0000-0000-000000000001','59000000-0000-0000-0000-000000000001',1,'retention.pdf','valid','current',now(),now());
  UPDATE public.documents SET current_version_id='59200000-0000-0000-0000-000000000001'
  WHERE id='59100000-0000-0000-0000-000000000001';

  INSERT INTO public.outbox_events(id,org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key)
  VALUES
    ('58300000-0000-0000-0000-000000000001',org_id,'document','58400000-0000-0000-0000-000000000001','document.processing_requested.v1',jsonb_build_object('document_id','58400000-0000-0000-0000-000000000001','version_id','58500000-0000-0000-0000-000000000001','intake_id','58600000-0000-0000-0000-000000000001'),'retention-delivered-old'),
    ('58300000-0000-0000-0000-000000000002',org_id,'document','58400000-0000-0000-0000-000000000002','document.processing_requested.v1',jsonb_build_object('document_id','58400000-0000-0000-0000-000000000002','version_id','58500000-0000-0000-0000-000000000002','intake_id','58600000-0000-0000-0000-000000000002'),'retention-delivered-boundary'),
    ('58300000-0000-0000-0000-000000000003',org_id,'document','58400000-0000-0000-0000-000000000003','document.processing_requested.v1',jsonb_build_object('document_id','58400000-0000-0000-0000-000000000003','version_id','58500000-0000-0000-0000-000000000003','intake_id','58600000-0000-0000-0000-000000000003'),'retention-pending'),
    ('58300000-0000-0000-0000-000000000004',org_id,'document','58400000-0000-0000-0000-000000000004','document.processing_requested.v1',jsonb_build_object('document_id','58400000-0000-0000-0000-000000000004','version_id','58500000-0000-0000-0000-000000000004','intake_id','58600000-0000-0000-0000-000000000004'),'retention-leased'),
    ('58300000-0000-0000-0000-000000000005',org_id,'document','58400000-0000-0000-0000-000000000005','document.processing_requested.v1',jsonb_build_object('document_id','58400000-0000-0000-0000-000000000005','version_id','58500000-0000-0000-0000-000000000005','intake_id','58600000-0000-0000-0000-000000000005'),'retention-dead'),
    ('58300000-0000-0000-0000-000000000006',org_id,'document','58400000-0000-0000-0000-000000000006','document.processing_requested.v1',jsonb_build_object('document_id','58400000-0000-0000-0000-000000000006','version_id','58500000-0000-0000-0000-000000000006','intake_id','58600000-0000-0000-0000-000000000006'),'retention-legacy-zero-attempt'),
    ('58300000-0000-0000-0000-000000000007',org_id,'document','58400000-0000-0000-0000-000000000007','document.processing_requested.v1',jsonb_build_object('document_id','58400000-0000-0000-0000-000000000007','version_id','58500000-0000-0000-0000-000000000007','intake_id','58600000-0000-0000-0000-000000000007'),'retention-legacy-missing-run');

  UPDATE public.outbox_events SET delivery_state='delivered',attempt_count=2,trigger_run_id='retention-run-old',delivered_at=now()-interval '31 days' WHERE id='58300000-0000-0000-0000-000000000001';
  UPDATE public.outbox_events SET delivery_state='delivered',attempt_count=1,trigger_run_id='retention-run-boundary',delivered_at=now()-interval '30 days'+interval '1 second' WHERE id='58300000-0000-0000-0000-000000000002';
  UPDATE public.outbox_events SET delivery_state='leased',attempt_count=1,lease_token='58700000-0000-0000-0000-000000000004',lease_expires_at=now()+interval '1 hour' WHERE id='58300000-0000-0000-0000-000000000004';
  UPDATE public.outbox_events SET delivery_state='dead_letter',attempt_count=5,failed_at=now()-interval '60 days',last_error_code='dispatch_failed' WHERE id='58300000-0000-0000-0000-000000000005';
  UPDATE public.outbox_events SET delivery_state='delivered',attempt_count=0,trigger_run_id='retention-run-legacy-zero',delivered_at=now()-interval '32 days' WHERE id='58300000-0000-0000-0000-000000000006';
  UPDATE public.outbox_events SET delivery_state='delivered',attempt_count=1,delivered_at=now()-interval '33 days' WHERE id='58300000-0000-0000-0000-000000000007';
  INSERT INTO public.outbox_dispatch_attempts(event_id,org_id,attempt_number,lease_fingerprint,outcome)
  VALUES ('58300000-0000-0000-0000-000000000001',org_id,1,repeat('a',64),'leased');
  INSERT INTO public.outbox_dispatch_attempts(event_id,org_id,attempt_number,lease_fingerprint,outcome,trigger_run_id)
  VALUES ('58300000-0000-0000-0000-000000000001',org_id,2,repeat('b',64),'accepted','retention-run-old');
  INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,outbox_event_id,state,started_at,completed_at)
  VALUES ('59300000-0000-0000-0000-000000000001',org_id,'59000000-0000-0000-0000-000000000001','retention-source-run','58300000-0000-0000-0000-000000000001','succeeded',now(),now());
  INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,source_analysis_run_id,scope,stage,state,idempotency_key,outbox_event_id)
  VALUES ('59400000-0000-0000-0000-000000000001',org_id,'59100000-0000-0000-0000-000000000001','59200000-0000-0000-0000-000000000001','59300000-0000-0000-0000-000000000001','search_index','queued','queued','retention-processing-run','58300000-0000-0000-0000-000000000001');
END $fixture$;

DO $authority_surface$
DECLARE blocked boolean := false; direct_delete_blocked boolean := false; result record;
BEGIN
  SET LOCAL ROLE service_role;
  BEGIN
    SELECT * INTO result FROM public.compact_delivered_document_outbox_events(10,now()-interval '30 days');
  EXCEPTION WHEN insufficient_privilege THEN blocked := true;
  END;
  PERFORM set_config('document_lifecycle.outbox_compaction_delete','on',true);
  BEGIN
    DELETE FROM public.outbox_events WHERE id='58300000-0000-0000-0000-000000000005';
  EXCEPTION WHEN insufficient_privilege THEN direct_delete_blocked := true;
  END;
  RESET ROLE;
  IF NOT blocked OR NOT direct_delete_blocked
    OR has_function_privilege('authenticated','public.compact_delivered_document_outbox_events(integer,timestamp with time zone)','EXECUTE')
    OR has_function_privilege('service_role','public.cleanup_compacted_outbox_delivery_receipts(integer,timestamp with time zone)','EXECUTE')
    OR NOT has_function_privilege('postgres','public.compact_delivered_document_outbox_events(integer,timestamp with time zone)','EXECUTE') THEN
    RAISE EXCEPTION 'outbox retention authority is available to a service or ordinary role';
  END IF;
END $authority_surface$;

DO $compaction$
DECLARE result record; blocked boolean := false;
BEGIN
  SELECT * INTO result FROM public.compact_delivered_document_outbox_events(3,now()-interval '30 days');
  IF result.compacted_count<>1 THEN RAISE EXCEPTION 'bounded old delivered event compaction failed'; END IF;
  SELECT * INTO result FROM public.compact_delivered_document_outbox_events(3,now()-interval '30 days');
  IF result.compacted_count<>0 THEN RAISE EXCEPTION 'compaction retry was not idempotent'; END IF;
  BEGIN
    SELECT * INTO result FROM public.compact_delivered_document_outbox_events(1,now()-interval '29 days');
  EXCEPTION WHEN raise_exception THEN blocked := SQLERRM='delivered outbox compaction cutoff must retain at least 30 days';
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'compaction accepted a too-recent cutoff'; END IF;
END $compaction$;

DO $inspection$
DECLARE receipt record; definition text;
BEGIN
  SELECT * INTO receipt FROM public.outbox_delivery_receipts WHERE event_id='58300000-0000-0000-0000-000000000001';
  IF receipt.event_id IS NULL OR receipt.org_id<>'58200000-0000-0000-0000-000000000001'::uuid
     OR receipt.aggregate_id<>'58400000-0000-0000-0000-000000000001'::uuid
     OR receipt.event_kind<>'document.processing_requested.v1' OR receipt.event_version<>1
     OR receipt.final_trigger_run_id<>'retention-run-old' OR receipt.attempt_count<>2
     OR receipt.delivered_at IS NULL THEN RAISE EXCEPTION 'delivery receipt omitted required safe proof'; END IF;
  IF EXISTS (SELECT 1 FROM public.outbox_events WHERE id='58300000-0000-0000-0000-000000000001')
     OR EXISTS (SELECT 1 FROM public.outbox_dispatch_attempts WHERE event_id='58300000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'compaction did not atomically remove delivered detail';
  END IF;
  IF EXISTS (SELECT 1 FROM public.outbox_events WHERE id IN ('58300000-0000-0000-0000-000000000002','58300000-0000-0000-0000-000000000003','58300000-0000-0000-0000-000000000004','58300000-0000-0000-0000-000000000005','58300000-0000-0000-0000-000000000006','58300000-0000-0000-0000-000000000007')) THEN NULL; ELSE
    RAISE EXCEPTION 'compaction removed a boundary or unresolved event';
  END IF;
  IF (SELECT delivery_state FROM public.outbox_events WHERE id='58300000-0000-0000-0000-000000000002')<>'delivered'
     OR (SELECT delivery_state FROM public.outbox_events WHERE id='58300000-0000-0000-0000-000000000003')<>'pending'
     OR (SELECT delivery_state FROM public.outbox_events WHERE id='58300000-0000-0000-0000-000000000004')<>'leased'
     OR (SELECT delivery_state FROM public.outbox_events WHERE id='58300000-0000-0000-0000-000000000005')<>'dead_letter'
     OR (SELECT delivery_state FROM public.outbox_events WHERE id='58300000-0000-0000-0000-000000000006')<>'delivered'
     OR (SELECT delivery_state FROM public.outbox_events WHERE id='58300000-0000-0000-0000-000000000007')<>'delivered' THEN
    RAISE EXCEPTION 'compaction altered a non-eligible event state';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.outbox_delivery_compaction_skips
      WHERE event_id='58300000-0000-0000-0000-000000000006'
        AND observed_attempt_count=0 AND reason_code='attempt_count_unrepresentable') THEN
    RAISE EXCEPTION 'legacy delivered attempt count was not safely retained and recorded';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.outbox_delivery_compaction_skips
      WHERE event_id='58300000-0000-0000-0000-000000000007'
        AND observed_attempt_count=1 AND reason_code='missing_final_trigger_run_id') THEN
    RAISE EXCEPTION 'legacy delivered row without final Trigger run was not safely retained and recorded';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.outbox_delivery_compaction_skips'::regclass AND attname IN ('payload','path','object_key','content')) THEN
    RAISE EXCEPTION 'compaction skip journal stores unsafe delivery content';
  END IF;
  IF (SELECT outbox_event_id FROM public.source_analysis_runs WHERE id='59300000-0000-0000-0000-000000000001') IS NOT NULL
     OR (SELECT outbox_event_id FROM public.document_processing_runs WHERE id='59400000-0000-0000-0000-000000000001') IS NOT NULL THEN
    RAISE EXCEPTION 'compaction did not atomically retain run references as null';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.outbox_delivery_receipts'::regclass AND attname IN ('payload','path','object_key','content')) THEN
    RAISE EXCEPTION 'delivery receipt stores unsafe delivery content';
  END IF;
  SELECT pg_get_functiondef('public.compact_delivered_document_outbox_events(integer,timestamp with time zone)'::regprocedure) INTO definition;
  IF definition !~ 'SKIP LOCKED' OR definition !~ 'delivery_state = ''delivered''' THEN
    RAISE EXCEPTION 'compaction lacks a safe concurrent delivery fence';
  END IF;
  IF (SELECT count(*) FROM public.outbox_retention_maintenance_runs WHERE operation='compact_delivered' AND affected_count IN (0,1))<>2 THEN
    RAISE EXCEPTION 'compaction execution was not auditable with safe counts';
  END IF;
END $inspection$;

DO $receipt_cleanup$
DECLARE result record; blocked boolean := false;
BEGIN
  UPDATE public.outbox_delivery_receipts SET compacted_at=now()-interval '181 days'
  WHERE event_id='58300000-0000-0000-0000-000000000001';
  SELECT * INTO result FROM public.cleanup_compacted_outbox_delivery_receipts(1,now()-interval '180 days');
  IF result.deleted_receipt_count<>1 OR EXISTS (SELECT 1 FROM public.outbox_delivery_receipts WHERE event_id='58300000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'bounded receipt cleanup did not remove only expired receipt'; END IF;
  BEGIN
    SELECT * INTO result FROM public.cleanup_compacted_outbox_delivery_receipts(1,now()-interval '179 days');
  EXCEPTION WHEN raise_exception THEN blocked := SQLERRM='outbox receipt cleanup cutoff must retain at least 180 days';
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'receipt cleanup accepted a too-recent cutoff'; END IF;
END $receipt_cleanup$;

DO $hot_path$
DECLARE index_count integer;
BEGIN
  SELECT count(*) INTO index_count FROM pg_indexes
  WHERE schemaname='public' AND tablename='outbox_events'
    AND indexname IN ('outbox_events_due_pending_idx','outbox_events_due_pending_org_idx','outbox_events_expired_lease_idx');
  IF index_count<>3 THEN RAISE EXCEPTION 'outbox compaction changed a dispatcher hot-path index'; END IF;
END $hot_path$;

ROLLBACK;
