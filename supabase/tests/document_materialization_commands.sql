-- Run after migration 00044 against a disposable local Supabase database.
BEGIN;

DO $setup$
DECLARE oa uuid:='37000000-0000-0000-0000-000000000001'; ob uuid:='37000000-0000-0000-0000-000000000002';
  owner uuid:='37100000-0000-0000-0000-000000000001'; admin uuid:='37100000-0000-0000-0000-000000000002'; associate uuid:='37100000-0000-0000-0000-000000000003'; viewer uuid:='37100000-0000-0000-0000-000000000004'; suspended uuid:='37100000-0000-0000-0000-000000000005'; other uuid:='37100000-0000-0000-0000-000000000006';
  ca uuid:='37200000-0000-0000-0000-000000000001'; cb uuid:='37200000-0000-0000-0000-000000000002'; ma uuid:='37300000-0000-0000-0000-000000000001'; mb uuid:='37300000-0000-0000-0000-000000000002';
BEGIN
 INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 SELECT '00000000-0000-0000-0000-000000000000',x,'authenticated','authenticated',x::text||'@material.test','x',now(),'{}','{}',now(),now() FROM unnest(ARRAY[owner,admin,associate,viewer,suspended,other]) x;
 INSERT INTO public.organisations(id,name,created_by) VALUES(oa,'Material A',owner),(ob,'Material B',other);
 IF (SELECT count(*) FROM public.organisation_memberships WHERE org_id=oa AND user_id=owner AND state='active')<>1 OR (SELECT count(*) FROM public.organisation_memberships WHERE org_id=ob AND user_id=other AND state='active')<>1 OR EXISTS(SELECT 1 FROM public.organisation_memberships WHERE org_id=oa AND user_id=other) THEN RAISE EXCEPTION 'organisation trigger owner fixture or tenant leakage'; END IF;
 INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at) VALUES
 ('37400000-0000-0000-0000-000000000002',oa,admin,'admin','active',1,now()),('37400000-0000-0000-0000-000000000003',oa,associate,'associate','active',1,now()),('37400000-0000-0000-0000-000000000004',oa,viewer,'viewer','active',1,now()),('37400000-0000-0000-0000-000000000005',oa,suspended,'associate','active',1,now());
 UPDATE public.organisation_memberships SET state='suspended',suspended_at=now(),suspended_by=owner,suspension_reason='fixture' WHERE id='37400000-0000-0000-0000-000000000005';
 INSERT INTO public.clients(id,org_id,name) VALUES(ca,oa,'Material client'),(cb,ob,'Other client'); INSERT INTO public.matters(id,org_id,client_id,title) VALUES(ma,oa,ca,'Active matter'),(mb,ob,cb,'Other matter');
END $setup$;

SELECT set_config('request.jwt.claim.sub','37100000-0000-0000-0000-000000000001',true);
SET LOCAL ROLE authenticated;
DO $metadata$
DECLARE r record; did uuid; revision bigint; denied boolean;
BEGIN
 IF NOT public.has_organisation_capability('37000000-0000-0000-0000-000000000001','document.record.create') OR NOT public.has_organisation_capability('37000000-0000-0000-0000-000000000001','document.version.replace') THEN RAISE EXCEPTION 'owner document capabilities'; END IF;
 IF (SELECT count(*) FROM public.get_my_organisation_context())<>1 OR EXISTS(SELECT 1 FROM public.get_my_organisation_context() WHERE org_id='37000000-0000-0000-0000-000000000002') THEN RAISE EXCEPTION 'owner context tenant leakage'; END IF;
 IF (SELECT capabilities FROM public.get_my_team_members() WHERE membership_id=(SELECT id FROM public.organisation_memberships WHERE org_id='37000000-0000-0000-0000-000000000001' AND user_id='37100000-0000-0000-0000-000000000001')) IS DISTINCT FROM ARRAY['team.view','team.invite.standard','team.role.manage_standard','team.membership.suspend_standard','organisation.profile.manage','organisation.operations.manage','team.invite.admin','team.role.manage_admin','team.membership.manage_admin','team.ownership.transfer','trash.purge','document.view','document.intake.create','document.record.create','document.intake.assign','document.intake.discard','document.version.attach','document.version.replace']::text[] THEN RAISE EXCEPTION 'owner member capability projection'; END IF;
 denied:=false; BEGIN PERFORM 1 FROM public.document_versions LIMIT 1; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'authenticated document version select was not denied'; END IF;
 denied:=false; BEGIN PERFORM 1 FROM public.document_command_receipts LIMIT 1; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'authenticated command receipt select was not denied'; END IF;
 denied:=false; BEGIN PERFORM 1 FROM public.outbox_events LIMIT 1; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'authenticated outbox select was not denied'; END IF;
 SELECT * INTO r FROM public.create_metadata_only_document('37300000-0000-0000-0000-000000000001','Register entry','Notice','REF-1',current_date,'37500000-0000-0000-0000-000000000001'); IF r.code<>'ok' OR r.document_id IS NULL OR r.lifecycle_revision IS NULL THEN RAISE EXCEPTION 'metadata create'; END IF; did:=r.document_id; revision:=r.lifecycle_revision;
 SELECT * INTO r FROM public.create_metadata_only_document('37300000-0000-0000-0000-000000000001','changed','x',NULL,NULL,'37500000-0000-0000-0000-000000000001'); IF r.code<>'ok' OR r.document_id IS DISTINCT FROM did OR r.lifecycle_revision IS DISTINCT FROM revision THEN RAISE EXCEPTION 'metadata idempotency'; END IF;
 PERFORM set_config('test.material_document',did::text,true); PERFORM set_config('test.material_revision',revision::text,true);
END $metadata$;
RESET ROLE;
DO $metadata_inspection$
DECLARE did uuid:=current_setting('test.material_document')::uuid;
BEGIN
 IF (SELECT count(*) FROM public.document_versions WHERE document_id=did)<>0 OR (SELECT storage_path IS NULL AND embedding IS NULL AND file_hash_sha256 IS NULL AND content_hash IS NULL FROM public.documents WHERE id=did) IS NOT TRUE OR (SELECT count(*) FROM public.activity_logs WHERE entity_id=did AND action='document.metadata_created')<>1 OR (SELECT count(*) FROM public.outbox_events WHERE aggregate_id=did AND event_kind='document.metadata_created.v1')<>1 THEN RAISE EXCEPTION 'metadata-only materialisation'; END IF;
END $metadata_inspection$;

SET LOCAL ROLE authenticated;
DO $matrix$
DECLARE r record;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','37100000-0000-0000-0000-000000000002',true); IF NOT public.has_organisation_capability('37000000-0000-0000-0000-000000000001','document.intake.assign') OR NOT public.has_organisation_capability('37000000-0000-0000-0000-000000000001','document.intake.discard') OR NOT public.has_organisation_capability('37000000-0000-0000-0000-000000000001','document.version.replace') THEN RAISE EXCEPTION 'admin capability'; END IF;
 PERFORM set_config('request.jwt.claim.sub','37100000-0000-0000-0000-000000000003',true); IF NOT public.has_organisation_capability('37000000-0000-0000-0000-000000000001','document.intake.assign') OR NOT public.has_organisation_capability('37000000-0000-0000-0000-000000000001','document.intake.discard') OR NOT public.has_organisation_capability('37000000-0000-0000-0000-000000000001','document.version.attach') THEN RAISE EXCEPTION 'associate capability'; END IF;
 PERFORM set_config('request.jwt.claim.sub','37100000-0000-0000-0000-000000000004',true); IF public.has_organisation_capability('37000000-0000-0000-0000-000000000001','document.record.create') OR public.has_organisation_capability('37000000-0000-0000-0000-000000000001','document.intake.discard') OR NOT public.has_organisation_capability('37000000-0000-0000-0000-000000000001','document.view') THEN RAISE EXCEPTION 'viewer matrix'; END IF;
 PERFORM set_config('request.jwt.claim.sub','37100000-0000-0000-0000-000000000005',true); IF public.has_organisation_capability('37000000-0000-0000-0000-000000000001','document.view') THEN RAISE EXCEPTION 'suspended matrix'; END IF;
END $matrix$;
RESET ROLE;

-- Service fixtures deliberately use trusted database facts rather than browser
-- values. They exercise success, failure/retry, and no-secret event payloads.
SET LOCAL ROLE service_role;
DO $service$
DECLARE org uuid:='37000000-0000-0000-0000-000000000001'; actor uuid:='37100000-0000-0000-0000-000000000001'; a1 uuid:='37600000-0000-0000-0000-000000000001'; a2 uuid:='37600000-0000-0000-0000-000000000002'; a3 uuid:='37600000-0000-0000-0000-000000000003'; a4 uuid:='37600000-0000-0000-0000-000000000004'; s1 uuid:='37700000-0000-0000-0000-000000000001'; s2 uuid:='37700000-0000-0000-0000-000000000002'; s3 uuid:='37700000-0000-0000-0000-000000000003'; s4 uuid:='37700000-0000-0000-0000-000000000004'; i1 uuid:='37800000-0000-0000-0000-000000000001'; i2 uuid:='37800000-0000-0000-0000-000000000002'; i3 uuid:='37800000-0000-0000-0000-000000000003'; i4 uuid:='37800000-0000-0000-0000-000000000004'; r record; denied boolean:=false;
BEGIN
 BEGIN PERFORM 1 FROM public.outbox_events LIMIT 1; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'service outbox select allowed'; END IF;
 INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,byte_size,detected_mime_type,availability,validated_at,created_by) VALUES
 (a1,org,'documents','orgs/'||org||'/assets/'||a1||'/original.pdf',10,'application/pdf','available',now(),actor),(a2,org,'documents','orgs/'||org||'/assets/'||a2||'/original.pdf',20,'application/pdf','available',now(),actor),(a3,org,'documents','orgs/'||org||'/assets/'||a3||'/original.pdf',30,'application/pdf','available',now(),actor),(a4,org,'documents','orgs/'||org||'/assets/'||a4||'/original.pdf',40,'application/pdf','available',now(),actor);
 UPDATE public.file_assets SET sha256=lpad(replace(id::text,'-',''),64,'0') WHERE org_id=org;
 INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,uploaded_at,finalized_at) VALUES(s1,org,a1,'first.pdf','application/pdf',10,'finalized',actor,now(),now()),(s2,org,a2,'second.pdf','application/pdf',20,'finalized',actor,now(),now()),(s3,org,a3,'bad.pdf','application/pdf',30,'finalized',actor,now(),now()),(s4,org,a4,'assigned.pdf','application/pdf',40,'finalized',actor,now(),now());
 INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,state,uploaded_by) VALUES(i1,org,a1,s1,'uploaded',actor),(i2,org,a2,s2,'uploaded',actor),(i3,org,a3,s3,'uploaded',actor),(i4,org,a4,s4,'uploaded',actor);
 SELECT * INTO r FROM public.validate_document_intake_asset(i1,2,'ready','37900000-0000-0000-0000-000000000001'); IF r.code<>'ok' OR r.intake_item_id IS NULL OR r.asset_id IS NULL THEN RAISE EXCEPTION 'validation success'; END IF; SELECT * INTO r FROM public.validate_document_intake_asset(i1,999,'ready','37900000-0000-0000-0000-000000000001'); IF r.code<>'ok' OR r.intake_item_id IS NULL OR r.asset_id IS NULL OR (SELECT validated_page_count FROM public.file_assets WHERE id=a1)<>2 THEN RAISE EXCEPTION 'validation receipt retry'; END IF;
 SELECT * INTO r FROM public.validate_document_intake_asset(i3,NULL,'encrypted_pdf','37900000-0000-0000-0000-000000000003'); IF r.code<>'encrypted_pdf' OR (SELECT state FROM public.intake_items WHERE id=i3)<>'failed' OR (SELECT availability FROM public.file_assets WHERE id=a3)<>'quarantined' THEN RAISE EXCEPTION 'validation failure'; END IF;
 PERFORM set_config('test.intake_one',i1::text,true); PERFORM set_config('test.intake_two',i2::text,true); PERFORM set_config('test.intake_three',i4::text,true);
 SELECT * INTO r FROM public.validate_document_intake_asset(i2,3,'ready','37900000-0000-0000-0000-000000000002'); IF r.code<>'ok' THEN RAISE EXCEPTION 'second validation'; END IF;
 SELECT * INTO r FROM public.validate_document_intake_asset(i4,4,'ready','37900000-0000-0000-0000-000000000004'); IF r.code<>'ok' OR r.intake_item_id IS NULL OR r.asset_id IS NULL THEN RAISE EXCEPTION 'third validation'; END IF;
END $service$;
RESET ROLE;
DO $validation_outbox_inspection$
DECLARE i1 uuid:=current_setting('test.intake_one')::uuid; i3 uuid:=current_setting('test.intake_three')::uuid;
BEGIN
 IF EXISTS(SELECT 1 FROM public.outbox_events WHERE aggregate_id IN (i1,i3) AND payload::text ~* '(path|object|content|filename|token)') THEN RAISE EXCEPTION 'validation outbox secrecy'; END IF;
END $validation_outbox_inspection$;

SET LOCAL ROLE authenticated;
DO $commands$
DECLARE d uuid:=current_setting('test.material_document')::uuid; rev bigint:=current_setting('test.material_revision')::bigint; i1 uuid:=current_setting('test.intake_one')::uuid; i2 uuid:=current_setting('test.intake_two')::uuid; i3 uuid:=current_setting('test.intake_three')::uuid; r record; v1 uuid; v2 uuid; assigned_document uuid; assigned_version uuid;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','37100000-0000-0000-0000-000000000001',true);
 SELECT * INTO r FROM public.assign_intake_to_new_document(i3,'37300000-0000-0000-0000-000000000001','Assigned record','37100000-0000-0000-0000-000000000001','37500000-0000-0000-0000-000000000009'); IF r.code<>'ok' OR r.document_id IS NULL OR r.document_version_id IS NULL OR r.lifecycle_revision IS NULL THEN RAISE EXCEPTION 'assign v1'; END IF; assigned_document:=r.document_id; assigned_version:=r.document_version_id;
 PERFORM set_config('test.assigned_document',assigned_document::text,true); PERFORM set_config('test.assigned_version',assigned_version::text,true); PERFORM set_config('test.assigned_revision',r.lifecycle_revision::text,true);
 SELECT * INTO r FROM public.attach_intake_to_document(d,i1,rev,'37100000-0000-0000-0000-000000000001','37500000-0000-0000-0000-000000000010'); IF r.code<>'ok' OR r.document_version_id IS NULL OR r.lifecycle_revision IS NULL THEN RAISE EXCEPTION 'attach v1'; END IF; v1:=r.document_version_id; rev:=r.lifecycle_revision;
 PERFORM set_config('test.attached_version',v1::text,true); PERFORM set_config('test.attached_revision',rev::text,true);
 SELECT * INTO r FROM public.attach_intake_to_document(d,i2,rev,'37100000-0000-0000-0000-000000000001','37500000-0000-0000-0000-000000000011'); IF r.code<>'document_not_metadata_only' THEN RAISE EXCEPTION 'attach only metadata'; END IF;
 SELECT * INTO r FROM public.replace_document_version(d,i2,rev-1,'Corrected scan','37100000-0000-0000-0000-000000000001','37500000-0000-0000-0000-000000000012'); IF r.code<>'stale_revision' THEN RAISE EXCEPTION 'stale revision'; END IF;
 SELECT * INTO r FROM public.replace_document_version(d,i2,rev,'Corrected scan','37100000-0000-0000-0000-000000000001','37500000-0000-0000-0000-000000000013'); IF r.code<>'ok' OR r.document_version_id IS NULL OR r.lifecycle_revision IS NULL THEN RAISE EXCEPTION 'replace v2'; END IF; v2:=r.document_version_id; rev:=r.lifecycle_revision;
 PERFORM set_config('test.replacement_version',v2::text,true); PERFORM set_config('test.replacement_revision',rev::text,true);
 SELECT * INTO r FROM public.replace_document_version(d,i1,rev,'again','37100000-0000-0000-0000-000000000001','37500000-0000-0000-0000-000000000014'); IF r.code NOT IN ('intake_unavailable','same_asset') THEN RAISE EXCEPTION 'duplicate intake denied'; END IF;
END $commands$;
RESET ROLE;

DO $commands_inspection$
DECLARE d uuid:=current_setting('test.material_document')::uuid; i3 uuid:=current_setting('test.intake_three')::uuid; assigned_document uuid:=current_setting('test.assigned_document')::uuid; assigned_version uuid:=current_setting('test.assigned_version')::uuid; v1 uuid:=current_setting('test.attached_version')::uuid; v2 uuid:=current_setting('test.replacement_version')::uuid;
BEGIN
 IF (SELECT current_version_id FROM public.documents WHERE id=assigned_document) IS DISTINCT FROM assigned_version OR (SELECT version_number FROM public.document_versions WHERE id=assigned_version)<>1 OR (SELECT state FROM public.intake_items WHERE id=i3)<>'assigned' THEN RAISE EXCEPTION 'assignment materialisation'; END IF;
 IF (SELECT state FROM public.document_versions WHERE id=v1)<>'superseded' OR (SELECT state FROM public.document_versions WHERE id=v2)<>'current' OR (SELECT current_version_id FROM public.documents WHERE id=d)<>v2 OR (SELECT count(*) FROM public.intake_item_assignments WHERE document_id=d)<>2 THEN RAISE EXCEPTION 'version history/pointer'; END IF;
 IF EXISTS(SELECT 1 FROM public.document_materialization_diagnostics) OR EXISTS(SELECT 1 FROM public.outbox_events WHERE aggregate_id=d AND payload::text ~* '(path|object|content|filename|token)') THEN RAISE EXCEPTION 'materialization diagnostics/secrecy'; END IF;
END $commands_inspection$;

SET LOCAL ROLE service_role;
WITH changed AS (UPDATE public.documents AS document_record SET record_state='trashed',trashed_at=now() WHERE document_record.id=current_setting('test.material_document')::uuid RETURNING document_record.lifecycle_revision)
SELECT set_config('test.trashed_revision',lifecycle_revision::text,true) FROM changed;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','37100000-0000-0000-0000-000000000001',true);
DO $trashed$
DECLARE r record; d uuid:=current_setting('test.material_document')::uuid; i uuid:=current_setting('test.intake_one')::uuid;
BEGIN
 SELECT * INTO r FROM public.replace_document_version(d,i,current_setting('test.trashed_revision')::bigint,'nope','37100000-0000-0000-0000-000000000001','37500000-0000-0000-0000-000000000015'); IF r.code<>'record_trashed' THEN RAISE EXCEPTION 'trashed denial'; END IF;
END $trashed$;
RESET ROLE;

DO $surface$
BEGIN
 IF NOT (SELECT relforcerowsecurity FROM pg_class WHERE oid='public.document_command_receipts'::regclass) OR has_table_privilege('authenticated','public.document_command_receipts','INSERT') OR has_function_privilege('authenticated','public.validate_document_intake_asset(uuid,integer,text,uuid)','EXECUTE') OR has_function_privilege('anon','public.create_metadata_only_document(uuid,text,text,text,date,uuid)','EXECUTE') THEN RAISE EXCEPTION 'materialization grant surface'; END IF;
END $surface$;
SET LOCAL ROLE authenticated;
DO $direct_dml_denial$
DECLARE denied boolean:=false;
BEGIN
  BEGIN
    INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code)
    VALUES('37000000-0000-0000-0000-000000000001','37100000-0000-0000-0000-000000000001','create_metadata','37500000-0000-0000-0000-000000000099','37300000-0000-0000-0000-000000000001','ok');
  EXCEPTION WHEN insufficient_privilege THEN
    denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'direct receipt DML was not denied'; END IF;
END $direct_dml_denial$;
RESET ROLE;
ROLLBACK;
