-- Disposable stack only. Committed synthetic rows for two-session lease/Trash fencing.
BEGIN;
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000','16610000-0000-4000-8000-000000000002','authenticated','authenticated','source-concurrency@example.test','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES ('16610000-0000-4000-8000-000000000001','Source concurrency fixture','16610000-0000-4000-8000-000000000002');
INSERT INTO public.clients(id,org_id,name) VALUES ('16610000-0000-4000-8000-000000000003','16610000-0000-4000-8000-000000000001','Fixture client');
INSERT INTO public.matters(id,org_id,client_id,title) VALUES ('16610000-0000-4000-8000-000000000004','16610000-0000-4000-8000-000000000001','16610000-0000-4000-8000-000000000003','Fixture matter');
INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by) VALUES ('16610000-0000-4000-8000-000000000005','16610000-0000-4000-8000-000000000001','16610000-0000-4000-8000-000000000004','legacy/fixture.pdf','16610000-0000-4000-8000-000000000002');
INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
  VALUES ('16610000-0000-4000-8000-000000000006','16610000-0000-4000-8000-000000000001','documents','orgs/16610000-0000-4000-8000-000000000001/assets/16610000-0000-4000-8000-000000000006/original.pdf',repeat('a',64),99,'application/pdf','available',now(),2,'16610000-0000-4000-8000-000000000002');
INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
  VALUES ('16610000-0000-4000-8000-000000000007','16610000-0000-4000-8000-000000000001','16610000-0000-4000-8000-000000000005','16610000-0000-4000-8000-000000000006',1,'fixture.pdf',2,'valid','current',now(),now(),'16610000-0000-4000-8000-000000000002');
UPDATE public.documents SET current_version_id='16610000-0000-4000-8000-000000000007' WHERE id='16610000-0000-4000-8000-000000000005';
INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
  VALUES ('16610000-0000-4000-8000-000000000008','16610000-0000-4000-8000-000000000001','16610000-0000-4000-8000-000000000005','16610000-0000-4000-8000-000000000007','full','fixture.source.concurrency','running','extracting',now(),'16610000-0000-4000-8000-000000000009',now()+interval '10 minutes',now());
COMMIT;
