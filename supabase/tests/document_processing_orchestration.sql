-- Run after migration 00042 against a disposable local Supabase database.
BEGIN;

DO $fixture$
DECLARE org uuid:='39000000-0000-0000-0000-000000000001'; actor uuid:='39100000-0000-0000-0000-000000000001'; client_id uuid:='39200000-0000-0000-0000-000000000001'; matter_id uuid:='39300000-0000-0000-0000-000000000001'; asset_id uuid:='39400000-0000-0000-0000-000000000001'; session_id uuid:='39500000-0000-0000-0000-000000000001'; intake_id uuid:='39600000-0000-0000-0000-000000000001'; event_id uuid:='39700000-0000-0000-0000-000000000001';
BEGIN
 INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES('00000000-0000-0000-0000-000000000000',actor,'authenticated','authenticated','processing@test.invalid','x',now(),'{}','{}',now(),now());
 INSERT INTO public.organisations(id,name,created_by) VALUES(org,'Processing fixture',actor); INSERT INTO public.clients(id,org_id,name) VALUES(client_id,org,'Client'); INSERT INTO public.matters(id,org_id,client_id,title) VALUES(matter_id,org,client_id,'Matter');
 INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,byte_size,detected_mime_type,availability,created_by) VALUES(asset_id,org,'documents','orgs/'||org||'/assets/'||asset_id||'/original.pdf',10,'application/pdf','uploaded',actor);
 INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,uploaded_at,finalized_at) VALUES(session_id,org,asset_id,'safe.pdf','application/pdf',10,'finalized',actor,now(),now());
 INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,state,uploaded_by) VALUES(intake_id,org,asset_id,session_id,'uploaded',actor);
 INSERT INTO public.outbox_events(id,org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key) VALUES(event_id,org,'document_upload',session_id,'document.upload_validation_requested.v1',jsonb_build_object('intake_id',intake_id::text,'asset_id',asset_id::text,'session_id',session_id::text),'processing-validation');
 INSERT INTO public.outbox_events(id,org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key) VALUES
 ('39700000-0000-0000-0000-000000000002',org,'document_upload',session_id,'document.upload_validation_requested.v1','null','processing-invalid-null'),
 ('39700000-0000-0000-0000-000000000003',org,'document_upload',session_id,'document.upload_validation_requested.v1','[]','processing-invalid-array'),
 ('39700000-0000-0000-0000-000000000004',org,'document_upload',session_id,'document.upload_validation_requested.v1','{"intake_id":"not-a-uuid","asset_id":"not-a-uuid","session_id":"not-a-uuid"}','processing-invalid-uuid');
 PERFORM set_config('test.processing_event',event_id::text,true);
END $fixture$;

SET LOCAL ROLE service_role;
DO $claims$
DECLARE r record; denied boolean:=false;
BEGIN
 BEGIN PERFORM 1 FROM public.source_analysis_runs LIMIT 1; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'service source run select allowed'; END IF;
 SELECT * INTO r FROM public.claim_document_validation_work(current_setting('test.processing_event')::uuid);
 IF r.code<>'claimed' OR r.source_run_id IS NULL OR r.lease_token IS NULL OR r.object_key IS NULL THEN RAISE EXCEPTION 'validation claim'; END IF;
 PERFORM set_config('test.processing_run',r.source_run_id::text,true); PERFORM set_config('test.processing_lease',r.lease_token::text,true);
 SELECT * INTO r FROM public.claim_document_validation_work(current_setting('test.processing_event')::uuid); IF r.code<>'already_claimed' THEN RAISE EXCEPTION 'claim idempotency'; END IF;
 SELECT * INTO r FROM public.claim_document_validation_work('39700000-0000-0000-0000-000000000002'); IF r.code<>'invalid_event' THEN RAISE EXCEPTION 'null payload safe handling'; END IF;
 SELECT * INTO r FROM public.claim_document_validation_work('39700000-0000-0000-0000-000000000003'); IF r.code<>'invalid_event' THEN RAISE EXCEPTION 'array payload safe handling'; END IF;
 SELECT * INTO r FROM public.claim_document_validation_work('39700000-0000-0000-0000-000000000004'); IF r.code<>'invalid_event' THEN RAISE EXCEPTION 'malformed UUID safe handling'; END IF;
 SELECT * INTO r FROM public.finish_document_validation_work(current_setting('test.processing_run')::uuid,'39000000-0000-0000-0000-000000000099','ready',1); IF r.code<>'stale_lease' THEN RAISE EXCEPTION 'stale validation fence'; END IF;
 SELECT * INTO r FROM public.finish_document_validation_work(current_setting('test.processing_run')::uuid,current_setting('test.processing_lease')::uuid,'invalid_pdf',NULL); IF r.code<>'invalid_pdf' THEN RAISE EXCEPTION 'validation terminal result'; END IF;
END $claims$;
RESET ROLE;

-- A gateway acknowledgement is not a completion guarantee. Expired worker
-- leases return to the same outbox event, while terminal PDF validation stays
-- terminal and is never requeued.
DO $reconciliation$
DECLARE org uuid:='39000000-0000-0000-0000-000000000001'; actor uuid:='39100000-0000-0000-0000-000000000001'; asset uuid:='39400000-0000-0000-0000-000000000099'; event uuid:='39700000-0000-0000-0000-000000000099'; run uuid:='39800000-0000-0000-0000-000000000099'; r record;
BEGIN
 INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,byte_size,detected_mime_type,availability,created_by)
   VALUES(asset,org,'documents','orgs/'||org||'/assets/'||asset||'/original.pdf',10,'application/pdf','uploaded',actor);
 INSERT INTO public.outbox_events(id,org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key,delivery_state,delivered_at,trigger_run_id)
   VALUES(event,org,'document_upload','39500000-0000-0000-0000-000000000001','document.upload_validation_requested.v1','{}','processing-reconcile','delivered',now(),'reconcile-run');
 INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,outbox_event_id,state,started_at,lease_token,lease_expires_at,heartbeat_at,attempt_count)
   VALUES(run,org,asset,'validation.reconcile',event,'running',now()-interval '10 minutes','39900000-0000-0000-0000-000000000099',now()-interval '5 minutes',now()-interval '10 minutes',1);
 SELECT * INTO r FROM public.reconcile_document_processing_work(10);
 IF r.validation_requeued<>1 OR (SELECT state FROM public.source_analysis_runs WHERE id=run)<>'queued' OR (SELECT delivery_state FROM public.outbox_events WHERE id=event)<>'pending' THEN RAISE EXCEPTION 'expired validation work was not durably requeued'; END IF;
 IF (SELECT state FROM public.source_analysis_runs WHERE id=current_setting('test.processing_run')::uuid)<>'failed' THEN RAISE EXCEPTION 'terminal validation was incorrectly requeued'; END IF;
END $reconciliation$;

-- A validated intake with a still-active intended matter is materialised by a
-- separate, replay-safe outbox continuation. This runs as service role but
-- retains the original uploader as the document actor.
DO $intended_matter_assignment$
DECLARE org uuid:='39000000-0000-0000-0000-000000000001'; actor uuid:='39100000-0000-0000-0000-000000000001'; matter_id uuid:='39300000-0000-0000-0000-000000000001';
  asset_id uuid:='39400000-0000-0000-0000-000000000010'; session_id uuid:='39500000-0000-0000-0000-000000000010'; intake_id uuid:='39600000-0000-0000-0000-000000000010'; event_id uuid:='39700000-0000-0000-0000-000000000010'; validation_event uuid; processing_event uuid; r record;
BEGIN
 INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,byte_size,detected_mime_type,availability,created_by)
   VALUES(asset_id,org,'documents','orgs/'||org||'/assets/'||asset_id||'/original.pdf',10,'application/pdf','uploaded',actor);
 INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,uploaded_at,finalized_at)
   VALUES(session_id,org,asset_id,'intended.pdf','application/pdf',10,'finalized',actor,now(),now());
 INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,intended_matter_id,state,uploaded_by)
   VALUES(intake_id,org,asset_id,session_id,matter_id,'uploaded',actor);
 INSERT INTO public.outbox_events(id,org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key)
   VALUES(event_id,org,'document_upload',session_id,'document.upload_validation_requested.v1',jsonb_build_object('intake_id',intake_id::text,'asset_id',asset_id::text,'session_id',session_id::text),'processing-intended-validation');
 SELECT * INTO r FROM public.claim_document_validation_work(event_id); IF r.code<>'claimed' THEN RAISE EXCEPTION 'intended validation claim'; END IF;
 SELECT * INTO r FROM public.finish_document_validation_work(r.source_run_id,r.lease_token,'ready',1); IF r.code<>'ok' THEN RAISE EXCEPTION 'intended validation finish'; END IF;
 SELECT id INTO validation_event FROM public.outbox_events WHERE aggregate_type='document' AND aggregate_id=intake_id AND event_kind='document.intake_validated.v1';
 SELECT * INTO r FROM public.auto_assign_intended_matter_intake(intake_id,validation_event); IF r.code<>'ok' OR r.document_id IS NULL OR r.document_version_id IS NULL THEN RAISE EXCEPTION 'intended assignment'; END IF;
 PERFORM set_config('test.intended_document',r.document_id::text,true);
 PERFORM set_config('test.intended_version',r.document_version_id::text,true);
 SELECT id INTO processing_event FROM public.outbox_events WHERE event_kind='document.processing_requested.v1' AND aggregate_id=r.document_id;
 PERFORM set_config('test.intended_processing_event',processing_event::text,true);
 SELECT * INTO r FROM public.auto_assign_intended_matter_intake(intake_id,validation_event); IF r.code<>'ok' THEN RAISE EXCEPTION 'intended assignment replay'; END IF;
 IF (SELECT state FROM public.intake_items WHERE id=intake_id)<>'assigned' OR (SELECT d.matter_id FROM public.documents d WHERE d.id=r.document_id)<>matter_id OR (SELECT d.current_version_id FROM public.documents d WHERE d.id=r.document_id) IS DISTINCT FROM r.document_version_id THEN RAISE EXCEPTION 'intended assignment lineage'; END IF;
END $intended_matter_assignment$;

-- A matter document created by the versioned intake path has no legacy
-- storage_path. Its viewer grant is therefore version-authorised, and never
-- accepts a browser-supplied bucket/object key.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','39100000-0000-0000-0000-000000000001',true);
DO $version_read_grant$
DECLARE v uuid; r record;
BEGIN
 v:=current_setting('test.intended_version')::uuid;
 SELECT * INTO r FROM public.get_document_version_read_grant(v);
 IF r.code<>'ok' OR r.bucket_id<>'documents' OR r.object_key IS NULL THEN
   RAISE EXCEPTION 'version-authorised read grant';
 END IF;
 IF EXISTS (SELECT 1 FROM public.get_document_version_read_grant('00000000-0000-0000-0000-000000000000') WHERE code='ok') THEN
   RAISE EXCEPTION 'unknown version read grant';
 END IF;
END $version_read_grant$;
RESET ROLE;

-- storage_missing is a durable operator-resolution state, not an automatic
-- retry: the failed intake/asset contract cannot be replayed safely until a
-- distinct, authorised recovery command exists.
DO $storage_missing_is_terminal$
DECLARE org uuid:='39000000-0000-0000-0000-000000000001'; actor uuid:='39100000-0000-0000-0000-000000000001';
  asset uuid:='39400000-0000-0000-0000-000000000088'; session_id uuid:='39500000-0000-0000-0000-000000000088';
  intake_id uuid:='39600000-0000-0000-0000-000000000088'; event_id uuid:='39700000-0000-0000-0000-000000000088'; r record;
BEGIN
 INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,byte_size,detected_mime_type,availability,created_by)
   VALUES(asset,org,'documents','orgs/'||org||'/assets/'||asset||'/original.pdf',10,'application/pdf','uploaded',actor);
 INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,uploaded_at,finalized_at)
   VALUES(session_id,org,asset,'missing.pdf','application/pdf',10,'finalized',actor,now(),now());
 INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,state,uploaded_by)
   VALUES(intake_id,org,asset,session_id,'uploaded',actor);
 INSERT INTO public.outbox_events(id,org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key,delivery_state,delivered_at)
   VALUES(event_id,org,'document_upload',session_id,'document.upload_validation_requested.v1',jsonb_build_object('intake_id',intake_id::text,'asset_id',asset::text,'session_id',session_id::text),'processing-storage-missing','delivered',now());
 SELECT * INTO r FROM public.claim_document_validation_work(event_id);
 IF r.code<>'claimed' THEN RAISE EXCEPTION 'storage missing validation claim'; END IF;
 SELECT * INTO r FROM public.finish_document_validation_work(r.source_run_id,r.lease_token,'storage_missing',NULL);
 IF r.code<>'storage_missing' THEN RAISE EXCEPTION 'storage missing validation finish'; END IF;
 SELECT * INTO r FROM public.reconcile_document_processing_work(10);
 IF r.validation_requeued<>0
    OR (SELECT state FROM public.source_analysis_runs WHERE id=(SELECT id FROM public.source_analysis_runs WHERE outbox_event_id=event_id))<>'failed'
    OR (SELECT state FROM public.intake_items WHERE id=intake_id)<>'failed'
    OR (SELECT delivery_state FROM public.outbox_events WHERE id=event_id)<>'delivered' THEN
   RAISE EXCEPTION 'storage missing was incorrectly requeued';
 END IF;
 SELECT * INTO r FROM public.claim_document_validation_work(event_id);
 IF r.code<>'invalid_event' THEN RAISE EXCEPTION 'storage missing unexpectedly re-claimed'; END IF;
END $storage_missing_is_terminal$;

-- A lease-expired legacy process is never replayed. It is failed behind the
-- run fence and represented by one durable recovery case for an operator.
SET LOCAL ROLE service_role;
DO $legacy_processing_claim$
DECLARE r record;
BEGIN
 SELECT * INTO r FROM public.claim_document_processing_work(current_setting('test.intended_processing_event')::uuid,'legacy-processing-test');
 IF r.code<>'claimed' THEN RAISE EXCEPTION 'processing claim'; END IF;
 PERFORM set_config('test.legacy_processing_run',r.processing_run_id::text,true);
END $legacy_processing_claim$;
RESET ROLE;
DO $legacy_processing_expiry$
BEGIN
 UPDATE public.document_processing_runs SET lease_expires_at=now()-interval '1 minute' WHERE id=current_setting('test.legacy_processing_run')::uuid;
 UPDATE public.outbox_events SET delivery_state='delivered',delivered_at=now(),failed_at=NULL,lease_token=NULL,lease_expires_at=NULL WHERE id=current_setting('test.intended_processing_event')::uuid;
END $legacy_processing_expiry$;
SET LOCAL ROLE service_role;
DO $legacy_processing_reconcile$
DECLARE r record;
BEGIN
 SELECT * INTO r FROM public.reconcile_document_processing_work(10);
 IF r.processing_requeued<>0 THEN RAISE EXCEPTION 'legacy processing was requeued'; END IF;
END $legacy_processing_reconcile$;
RESET ROLE;
DO $legacy_processing_assertions$
DECLARE run_id uuid:=current_setting('test.legacy_processing_run')::uuid; event_id uuid:=current_setting('test.intended_processing_event')::uuid;
BEGIN
 IF (SELECT state FROM public.document_processing_runs WHERE id=run_id)<>'failed'
    OR (SELECT safe_error_code FROM public.document_processing_runs WHERE id=run_id)<>'legacy_processing_recovery_required'
    OR (SELECT delivery_state FROM public.outbox_events WHERE id=event_id)<>'delivered'
    OR (SELECT count(*) FROM public.document_processing_recovery_cases WHERE processing_run_id=run_id AND state='open')<>1 THEN
   RAISE EXCEPTION 'legacy processing replay safety';
 END IF;
END $legacy_processing_assertions$;
SET LOCAL ROLE service_role;
DO $legacy_processing_never_reclaims$
DECLARE r record;
BEGIN
 SELECT * INTO r FROM public.claim_document_processing_work(current_setting('test.intended_processing_event')::uuid,'legacy-processing-retry');
 IF r.code<>'recovery_required' THEN RAISE EXCEPTION 'legacy processing was re-claimed after recovery fence'; END IF;
END $legacy_processing_never_reclaims$;
RESET ROLE;
DO $legacy_processing_fence_persists$
DECLARE run_id uuid:=current_setting('test.legacy_processing_run')::uuid;
BEGIN
 IF (SELECT state FROM public.document_processing_runs WHERE id=run_id)<>'failed'
    OR (SELECT safe_error_code FROM public.document_processing_runs WHERE id=run_id)<>'legacy_processing_recovery_required'
    OR (SELECT count(*) FROM public.document_processing_recovery_cases WHERE processing_run_id=run_id AND state='open')<>1 THEN
   RAISE EXCEPTION 'legacy processing recovery fence was cleared';
 END IF;
END $legacy_processing_fence_persists$;

DO $surface$
BEGIN
 IF has_table_privilege('service_role','public.source_analysis_runs','UPDATE') OR has_table_privilege('service_role','public.document_processing_runs','INSERT') OR has_function_privilege('authenticated','public.claim_document_validation_work(uuid)','EXECUTE') OR has_function_privilege('authenticated','public.auto_assign_intended_matter_intake(uuid,uuid)','EXECUTE') OR has_function_privilege('authenticated','public.reconcile_document_processing_work(integer)','EXECUTE') OR has_function_privilege('authenticated','public.record_document_asset_storage_deleted(uuid)','EXECUTE') OR NOT has_function_privilege('service_role','public.reconcile_document_processing_work(integer)','EXECUTE') OR NOT has_function_privilege('authenticated','public.get_document_version_read_grant(uuid)','EXECUTE') OR NOT (SELECT relforcerowsecurity FROM pg_class WHERE oid='public.source_analysis_runs'::regclass) OR pg_get_viewdef('public.document_processing_orchestration_diagnostics'::regclass) ~* '(object|path|payload|content|filename|token)' THEN RAISE EXCEPTION 'processing orchestration surface'; END IF;
END $surface$;
ROLLBACK;
