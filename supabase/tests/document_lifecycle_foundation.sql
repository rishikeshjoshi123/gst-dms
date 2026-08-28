-- Run only after migration 00035 against a disposable local Supabase database.
-- This is intentionally a foundation contract: metadata-only creation, quota
-- concurrency commands, storage policies, and upload cut-over are later gates.
BEGIN;

DO $test$
DECLARE
  org_a uuid := '35000000-0000-0000-0000-000000000001'; org_b uuid := '35000000-0000-0000-0000-000000000002';
  user_a uuid := '35100000-0000-0000-0000-000000000001'; user_b uuid := '35100000-0000-0000-0000-000000000002';
  client_a uuid := '35200000-0000-0000-0000-000000000001'; client_b uuid := '35200000-0000-0000-0000-000000000002'; matter_a uuid := '35300000-0000-0000-0000-000000000001'; matter_b uuid := '35300000-0000-0000-0000-000000000002';
  doc_a uuid := '35400000-0000-0000-0000-000000000001'; doc_b uuid := '35400000-0000-0000-0000-000000000002';
  asset_a uuid := '35500000-0000-0000-0000-000000000001'; asset_b uuid := '35500000-0000-0000-0000-000000000002'; asset_cross uuid := '35500000-0000-0000-0000-000000000003';
  version_a uuid := '35600000-0000-0000-0000-000000000001'; version_b uuid := '35600000-0000-0000-0000-000000000002'; version_unpointed uuid := '35600000-0000-0000-0000-000000000003';
  session_a uuid := '35700000-0000-0000-0000-000000000001'; intake_a uuid := '35800000-0000-0000-0000-000000000001'; run_a uuid := '35900000-0000-0000-0000-000000000001';
  before_count bigint; before_digest text; failed boolean;
BEGIN
  SELECT count(*), md5(string_agg(id::text || ':' || origin_kind::text || ':' || record_state::text || ':' || content_availability::text, ',' ORDER BY id)) INTO before_count, before_digest FROM public.documents;
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
    ('00000000-0000-0000-0000-000000000000',user_a,'authenticated','authenticated','lifecycle-a@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',user_b,'authenticated','authenticated','lifecycle-b@example.test','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES (org_a,'Lifecycle A',user_a),(org_b,'Lifecycle B',user_b);
  INSERT INTO public.clients(id,org_id,name) VALUES(client_a,org_a,'Fixture client'),(client_b,org_b,'Other client');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES(matter_a,org_a,client_a,'Fixture matter'),(matter_b,org_b,client_b,'Other matter');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by) VALUES(doc_a,org_a,matter_a,'legacy/a.pdf',user_a),(doc_b,org_b,matter_b,'legacy/b.pdf',user_b);
  IF (SELECT origin_kind FROM public.documents WHERE id=doc_a) <> 'legacy_migration' OR (SELECT content_availability FROM public.documents WHERE id=doc_a) <> 'source_attached' OR (SELECT current_version_id FROM public.documents WHERE id=doc_a) IS NOT NULL THEN RAISE EXCEPTION 'legacy compatibility defaults failed'; END IF;
  IF (SELECT count(*) FROM public.documents WHERE id NOT IN (doc_a,doc_b)) <> before_count OR (SELECT md5(string_agg(id::text || ':' || origin_kind::text || ':' || record_state::text || ':' || content_availability::text, ',' ORDER BY id)) FROM public.documents WHERE id NOT IN (doc_a,doc_b)) IS DISTINCT FROM before_digest THEN RAISE EXCEPTION 'legacy document digest changed'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_tables t WHERE t.schemaname='public' AND t.tablename='file_assets' AND t.rowsecurity) OR NOT (SELECT relforcerowsecurity FROM pg_class WHERE oid='public.file_assets'::regclass) THEN RAISE EXCEPTION 'RLS FORCE missing'; END IF;
  IF has_table_privilege('authenticated','public.file_assets','SELECT') OR has_table_privilege('authenticated','public.outbox_events','INSERT') OR has_function_privilege('authenticated','public.document_lifecycle_prevent_delete()','EXECUTE') THEN RAISE EXCEPTION 'lifecycle public grant surface'; END IF;
  IF NOT has_table_privilege('service_role','public.file_assets','SELECT') OR has_table_privilege('service_role','public.outbox_events','INSERT') OR has_table_privilege('service_role','public.outbox_events','UPDATE') OR has_table_privilege('service_role','public.outbox_events','DELETE') OR NOT has_function_privilege('service_role','public.lease_document_outbox_events(integer,integer)','EXECUTE') OR NOT has_function_privilege('service_role','public.ack_document_outbox_event(uuid,uuid,text)','EXECUTE') OR NOT has_function_privilege('service_role','public.fail_document_outbox_event(uuid,uuid,text)','EXECUTE') OR has_table_privilege('service_role','public.file_assets','DELETE') OR has_table_privilege('service_role','public.document_version_analysis_bindings','UPDATE') OR NOT has_table_privilege('service_role','public.document_version_analysis_bindings','INSERT') THEN RAISE EXCEPTION 'service role grant surface'; END IF;

  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,availability,validated_at) VALUES(asset_a,org_a,'documents','orgs/'||org_a||'/assets/'||asset_a||'/original.pdf',repeat('a',64),100,'available',now());
  failed := false; BEGIN INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size) VALUES('35500000-0000-0000-0000-000000000010',org_a,'documents','orgs/'||org_a||'/assets/35500000-0000-0000-0000-000000000010/original.pdf',repeat('a',64),101); EXCEPTION WHEN unique_violation THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'same-org sha duplicate allowed'; END IF;
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,availability,validated_at) VALUES(asset_cross,org_b,'documents','orgs/'||org_b||'/assets/'||asset_cross||'/original.pdf',repeat('a',64),100,'available',now());
  failed := false; BEGIN INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,byte_size) VALUES('35500000-0000-0000-0000-000000000011',org_b,'documents','orgs/'||org_b||'/assets/35500000-0000-0000-0000-000000000011/not-original.pdf',100); EXCEPTION WHEN check_violation THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'noncanonical asset path allowed'; END IF;
  failed := false; BEGIN INSERT INTO public.upload_sessions(org_id,asset_id,declared_filename,declared_byte_size) VALUES(org_b,asset_a,'x.pdf',1); EXCEPTION WHEN foreign_key_violation THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'cross-org asset FK allowed'; END IF;
  failed := false; BEGIN UPDATE public.file_assets SET object_key='mutated.pdf' WHERE id=asset_a; EXCEPTION WHEN raise_exception THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'asset identity mutated'; END IF;

  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,validation_state,state,validated_at,promoted_at) VALUES(version_a,org_a,doc_a,asset_a,1,'a.pdf','valid','current',now(),now());
  UPDATE public.documents SET current_version_id=version_a WHERE id=doc_a;
  failed := false; BEGIN UPDATE public.documents SET current_version_id=version_a WHERE id=doc_b; SET CONSTRAINTS ALL IMMEDIATE; EXCEPTION WHEN raise_exception OR foreign_key_violation THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'cross-document current version allowed'; END IF;
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,availability,validated_at) VALUES(asset_b,org_a,'documents','orgs/'||org_a||'/assets/'||asset_b||'/original.pdf',repeat('b',64),101,'available',now());
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,validation_state,state,validated_at) VALUES(version_b,org_a,doc_a,asset_b,2,'b.pdf','valid','pending',now());
  -- Deferred constraints permit the atomic replacement ordering but reject any
  -- transaction that leaves the pointer/version pair inconsistent.
  UPDATE public.document_versions SET state='superseded', superseded_at=now() WHERE id=version_a;
  UPDATE public.document_versions SET state='current', promoted_at=now() WHERE id=version_b;
  UPDATE public.documents SET current_version_id=version_b WHERE id=doc_a;
  SET CONSTRAINTS ALL IMMEDIATE;
  failed := false; BEGIN UPDATE public.document_versions SET state='pending', promoted_at=NULL WHERE id=version_b; SET CONSTRAINTS ALL IMMEDIATE; EXCEPTION WHEN raise_exception THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'noncurrent pointed version allowed'; END IF;
  failed := false; BEGIN INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,validation_state,state,validated_at,promoted_at) VALUES(version_unpointed,org_b,doc_b,asset_cross,1,'unpointed.pdf','valid','current',now(),now()); SET CONSTRAINTS ALL IMMEDIATE; EXCEPTION WHEN raise_exception THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'unpointed current version allowed'; END IF;
  IF (SELECT state FROM public.document_versions WHERE id=version_a) <> 'superseded' OR (SELECT state FROM public.document_versions WHERE id=version_b) <> 'current' OR (SELECT current_version_id FROM public.documents WHERE id=doc_a) <> version_b OR EXISTS (SELECT 1 FROM public.document_lifecycle_foundation_diagnostics) THEN RAISE EXCEPTION 'atomic replacement final state failed'; END IF;
  failed := false; BEGIN UPDATE public.document_versions SET original_filename='changed.pdf' WHERE id=version_a; EXCEPTION WHEN raise_exception THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'version identity mutated'; END IF;

  INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_byte_size,state,uploaded_at) VALUES(session_a,org_a,asset_a,'a.pdf',100,'uploaded',now());
  INSERT INTO public.storage_reservations(org_id,upload_session_id,reserved_bytes) VALUES(org_a,session_a,100);
  -- The shared related-identity trigger must allow each table's ordinary
  -- lifecycle/audit transition while retaining its own row shape.
  UPDATE public.storage_reservations SET state='released',released_at=now() WHERE upload_session_id=session_a;
  IF (SELECT state FROM public.storage_reservations WHERE upload_session_id=session_a)<>'released' THEN RAISE EXCEPTION 'reservation transition blocked'; END IF;
  failed := false; BEGIN INSERT INTO public.upload_sessions(org_id,asset_id,declared_filename,declared_byte_size,expires_at) VALUES(org_a,asset_a,'too-long.pdf',100,now()+interval '25 hours'); EXCEPTION WHEN check_violation THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'session expiry boundary allowed'; END IF;
  INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_byte_size) VALUES('35700000-0000-0000-0000-000000000002',org_a,asset_a,'reservation.pdf',100);
  failed := false; BEGIN INSERT INTO public.storage_reservations(org_id,upload_session_id,reserved_bytes,expires_at) VALUES(org_a,'35700000-0000-0000-0000-000000000002',100,now()+interval '25 hours'); EXCEPTION WHEN check_violation THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'reservation expiry boundary allowed'; END IF;
  failed := false; BEGIN INSERT INTO public.upload_sessions(org_id,asset_id,declared_filename,declared_byte_size,state,failed_at,expired_at) VALUES(org_a,asset_a,'bad-state.pdf',100,'failed',now(),now()); EXCEPTION WHEN check_violation THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'incompatible session terminal timestamps allowed'; END IF;
  INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,intended_matter_id,state) VALUES(intake_a,org_a,asset_a,session_a,matter_a,'ready');
  failed := false; BEGIN INSERT INTO public.intake_items(org_id,asset_id,intended_matter_id) VALUES(org_a,asset_a,matter_b); EXCEPTION WHEN foreign_key_violation THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'cross-org intended matter allowed'; END IF;
  INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,state,started_at,completed_at) VALUES(run_a,org_a,asset_a,'analysis-a','succeeded',now(),now());
  INSERT INTO public.document_version_analysis_bindings(org_id,document_version_id,source_analysis_run_id,binding_reason) VALUES(org_a,version_a,run_a,'assignment');
  UPDATE public.document_version_analysis_bindings SET created_by=user_a WHERE document_version_id=version_a AND source_analysis_run_id=run_a;
  IF (SELECT created_by FROM public.document_version_analysis_bindings WHERE document_version_id=version_a AND source_analysis_run_id=run_a)<>user_a THEN RAISE EXCEPTION 'binding audit transition blocked'; END IF;
  INSERT INTO public.source_analysis_runs(org_id,asset_id,request_key) VALUES(org_a,asset_b,'analysis-b');
  UPDATE public.source_analysis_runs SET state='running',started_at=now() WHERE request_key='analysis-b';
  UPDATE public.source_analysis_runs SET state='succeeded',completed_at=now() WHERE request_key='analysis-b';
  IF (SELECT state FROM public.source_analysis_runs WHERE request_key='analysis-b')<>'succeeded' THEN RAISE EXCEPTION 'analysis transition blocked'; END IF;
  failed := false; BEGIN INSERT INTO public.document_version_analysis_bindings(org_id,document_version_id,source_analysis_run_id,binding_reason) SELECT org_a,version_a,id,'wrong asset' FROM public.source_analysis_runs WHERE request_key='analysis-b'; EXCEPTION WHEN raise_exception THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'cross-asset binding allowed'; END IF;
  INSERT INTO public.document_processing_runs(org_id,document_id,document_version_id,source_analysis_run_id,scope,idempotency_key) VALUES(org_a,doc_a,version_a,run_a,'extract','processing-a');
  failed := false; BEGIN INSERT INTO public.document_processing_runs(org_id,document_id,document_version_id,scope,idempotency_key) VALUES(org_a,doc_b,version_a,'extract','processing-b'); EXCEPTION WHEN raise_exception OR foreign_key_violation THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'processing lineage allowed'; END IF;
  failed := false; BEGIN INSERT INTO public.document_processing_runs(org_id,document_id,document_version_id,source_analysis_run_id,scope,idempotency_key) SELECT org_a,doc_a,version_a,id,'extract','processing-asset-mismatch' FROM public.source_analysis_runs WHERE request_key='analysis-b'; EXCEPTION WHEN raise_exception THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'processing source asset mismatch allowed'; END IF;

  INSERT INTO public.outbox_events(org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key) VALUES(org_a,'document',doc_a,'document.processing_requested.v1',jsonb_build_object('document_id',doc_a::text,'version_id',version_b::text,'intake_id',intake_a::text),'outbox-a');
  failed := false; BEGIN INSERT INTO public.outbox_events(org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key) VALUES(org_a,'document',doc_a,'document.processing_requested.v1','{"signed_url":"forbidden"}','outbox-secret'); EXCEPTION WHEN check_violation THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'forbidden outbox key allowed'; END IF;
  failed := false; BEGIN INSERT INTO public.outbox_events(org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key) VALUES(org_a,'document',doc_a,'document.processing_requested.v1',jsonb_build_object('document_id',doc_a::text,'version_id',version_b::text,'intake_id',intake_a::text),'outbox-a'); EXCEPTION WHEN unique_violation THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'outbox idempotency allowed'; END IF;
  UPDATE public.outbox_events SET delivery_state='delivered', delivered_at=now(), attempt_count=1 WHERE idempotency_key='outbox-a';
  failed := false; BEGIN UPDATE public.outbox_events SET payload='{"changed":true}' WHERE idempotency_key='outbox-a'; EXCEPTION WHEN raise_exception THEN failed := true; END; IF NOT failed THEN RAISE EXCEPTION 'outbox payload mutated'; END IF;
  IF EXISTS (SELECT 1 FROM public.document_lifecycle_foundation_diagnostics) THEN RAISE EXCEPTION 'diagnostics should be clear for a consistent fixture'; END IF;
END $test$;

SET LOCAL ROLE service_role;
DO $service_outbox_dml_denial$
DECLARE denied boolean:=false;
BEGIN
  BEGIN
    UPDATE public.outbox_events SET attempt_count=2, last_error_code=NULL WHERE idempotency_key='outbox-a';
  EXCEPTION WHEN insufficient_privilege THEN
    denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'service role direct outbox update allowed'; END IF;
END $service_outbox_dml_denial$;
RESET ROLE;

-- Browser roles have neither a lifecycle table DML surface nor permission to
-- update lifecycle columns, while legacy document fields retain their existing
-- RLS/grant compatibility until the command cut-over.
SELECT set_config('request.jwt.claim.sub','35100000-0000-0000-0000-000000000001',true);
SET LOCAL ROLE authenticated;
DO $browser$
DECLARE denied boolean;
BEGIN
  denied := false; BEGIN INSERT INTO public.file_assets(org_id,bucket_id,object_key,byte_size) VALUES('35000000-0000-0000-0000-000000000001','x','x',1); EXCEPTION WHEN insufficient_privilege THEN denied := true; END; IF NOT denied THEN RAISE EXCEPTION 'browser file asset DML allowed'; END IF;
  denied := false; BEGIN UPDATE public.documents SET record_state='trashed' WHERE id='35400000-0000-0000-0000-000000000001'; EXCEPTION WHEN insufficient_privilege THEN denied := true; END; IF NOT denied THEN RAISE EXCEPTION 'browser lifecycle update allowed'; END IF;
  UPDATE public.documents SET summary='legacy compatibility write' WHERE id='35400000-0000-0000-0000-000000000001';
END $browser$;
RESET ROLE;
ROLLBACK;
