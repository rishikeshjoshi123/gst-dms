-- Run after migration 00039 against a disposable local Supabase database.
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

DO $surface$
BEGIN
 IF has_table_privilege('service_role','public.source_analysis_runs','UPDATE') OR has_table_privilege('service_role','public.document_processing_runs','INSERT') OR has_function_privilege('authenticated','public.claim_document_validation_work(uuid)','EXECUTE') OR NOT (SELECT relforcerowsecurity FROM pg_class WHERE oid='public.source_analysis_runs'::regclass) OR pg_get_viewdef('public.document_processing_orchestration_diagnostics'::regclass) ~* '(object|path|payload|content|filename|token)' THEN RAISE EXCEPTION 'processing orchestration surface'; END IF;
END $surface$;
ROLLBACK;
