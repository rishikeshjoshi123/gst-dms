-- Run after migration 00036 against a disposable local Supabase database.
BEGIN;

DO $setup$
DECLARE org_a uuid:='36000000-0000-0000-0000-000000000001'; org_b uuid:='36000000-0000-0000-0000-000000000002';
 owner_a uuid:='36100000-0000-0000-0000-000000000001'; admin_a uuid:='36100000-0000-0000-0000-000000000002'; associate_a uuid:='36100000-0000-0000-0000-000000000003'; viewer_a uuid:='36100000-0000-0000-0000-000000000004'; suspended_a uuid:='36100000-0000-0000-0000-000000000005'; owner_b uuid:='36100000-0000-0000-0000-000000000006';
 m1 uuid:='36300000-0000-0000-0000-000000000001'; m2 uuid:='36300000-0000-0000-0000-000000000002'; c1 uuid:='36200000-0000-0000-0000-000000000001'; c2 uuid:='36200000-0000-0000-0000-000000000002';
BEGIN
 INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) SELECT '00000000-0000-0000-0000-000000000000',x,'authenticated','authenticated',x::text||'@upload.test','x',now(),'{}','{}',now(),now() FROM unnest(ARRAY[owner_a,admin_a,associate_a,viewer_a,suspended_a,owner_b]) x;
 INSERT INTO public.organisations(id,name,created_by) VALUES(org_a,'Upload A',owner_a),(org_b,'Upload B',owner_b);
 -- Organisation creation already creates both legacy and canonical owner rows;
 -- query them instead of inserting either owner representation again.
 IF NOT EXISTS (SELECT 1 FROM public.organisation_memberships AS om WHERE om.org_id=org_a AND om.user_id=owner_a AND om.state='active') OR NOT EXISTS (SELECT 1 FROM public.organisation_memberships AS om WHERE om.org_id=org_b AND om.user_id=owner_b AND om.state='active') THEN RAISE EXCEPTION 'organisation owner membership trigger'; END IF;
 INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at) VALUES
 ('36400000-0000-0000-0000-000000000002',org_a,admin_a,'admin','active',1,now()),('36400000-0000-0000-0000-000000000003',org_a,associate_a,'associate','active',1,now()),('36400000-0000-0000-0000-000000000004',org_a,viewer_a,'viewer','active',1,now()),('36400000-0000-0000-0000-000000000005',org_a,suspended_a,'associate','active',1,now());
 UPDATE public.organisation_memberships SET state='suspended',suspended_at=now(),suspended_by=owner_a,suspension_reason='fixture' WHERE id='36400000-0000-0000-0000-000000000005';
 INSERT INTO public.clients(id,org_id,name) VALUES(c1,org_a,'Upload Client'),(c2,org_b,'Other Client'); INSERT INTO public.matters(id,org_id,client_id,title) VALUES(m1,org_a,c1,'Open matter'),(m2,org_b,c2,'Other matter');
END $setup$;

-- The role matrix and reserve validation use the authenticated command only.
SELECT set_config('request.jwt.claim.sub','36100000-0000-0000-0000-000000000001',true);
SET LOCAL ROLE authenticated;
DO $authenticated$
DECLARE r record; sid uuid; aid uuid; iid uuid;
BEGIN
 SELECT * INTO r FROM public.reserve_document_upload('one.pdf','application/pdf',1024,'36300000-0000-0000-0000-000000000001','36500000-0000-0000-0000-000000000001'); IF r.code<>'ok' THEN RAISE EXCEPTION 'owner reserve'; END IF; sid:=r.upload_session_id; aid:=r.asset_id; iid:=r.intake_item_id;
 PERFORM set_config('test.document_upload_session',sid::text,true); PERFORM set_config('test.document_upload_asset',aid::text,true); PERFORM set_config('test.document_upload_intake',iid::text,true); PERFORM set_config('test.document_upload_expiry',r.expires_at::text,true);
 SELECT * INTO r FROM public.reserve_document_upload('changed.pdf','application/pdf',1025,NULL,'36500000-0000-0000-0000-000000000001'); IF r.code<>'ok' OR r.upload_session_id<>sid OR r.asset_id<>aid OR r.intake_item_id<>iid THEN RAISE EXCEPTION 'reserve idempotency'; END IF;
 SELECT * INTO r FROM public.reserve_document_upload('bad.txt','application/pdf',1,NULL,'36500000-0000-0000-0000-000000000002'); IF r.code<>'invalid_filename' THEN RAISE EXCEPTION 'filename validation'; END IF;
 SELECT * INTO r FROM public.reserve_document_upload('bad.pdf','text/plain',1,NULL,'36500000-0000-0000-0000-000000000003'); IF r.code<>'invalid_mime' THEN RAISE EXCEPTION 'mime validation'; END IF;
 SELECT * INTO r FROM public.reserve_document_upload('bad.pdf','application/pdf',0,NULL,'36500000-0000-0000-0000-000000000004'); IF r.code<>'invalid_size' THEN RAISE EXCEPTION 'size validation'; END IF;
 SELECT * INTO r FROM public.reserve_document_upload('bad.pdf','application/pdf',1,'36300000-0000-0000-0000-000000000002','36500000-0000-0000-0000-000000000005'); IF r.code<>'invalid_matter' THEN RAISE EXCEPTION 'matter validation'; END IF;
 IF NOT public.has_organisation_capability('36000000-0000-0000-0000-000000000001','document.view') OR NOT public.has_organisation_capability('36000000-0000-0000-0000-000000000001','document.intake.create') THEN RAISE EXCEPTION 'owner capabilities'; END IF;
 BEGIN PERFORM 1 FROM public.upload_sessions LIMIT 1; RAISE EXCEPTION 'direct lifecycle select allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO public.file_assets(org_id,bucket_id,object_key) VALUES('36000000-0000-0000-0000-000000000001','documents','x'); RAISE EXCEPTION 'direct DML allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF has_function_privilege('authenticated','public.complete_document_upload(uuid,bigint,text,text,uuid)','EXECUTE') OR has_function_privilege('authenticated','public.maintain_document_upload_sessions(integer)','EXECUTE') THEN RAISE EXCEPTION 'service function grant'; END IF;
END $authenticated$;
RESET ROLE;

-- The authenticated block persisted only the RPC result in transaction-local
-- settings. Inspect private lifecycle rows after resetting to a privileged role.
DO $privileged_reserve_assertions$
DECLARE sid uuid:=current_setting('test.document_upload_session')::uuid; aid uuid:=current_setting('test.document_upload_asset')::uuid; iid uuid:=current_setting('test.document_upload_intake')::uuid; exp timestamptz:=current_setting('test.document_upload_expiry')::timestamptz;
BEGIN
 IF exp IS NULL OR (SELECT us.state FROM public.upload_sessions AS us WHERE us.id=sid)<>'reserved' OR (SELECT fa.availability FROM public.file_assets AS fa WHERE fa.id=aid)<>'reserved' OR (SELECT sr.state FROM public.storage_reservations AS sr WHERE sr.upload_session_id=sid)<>'active' OR (SELECT sr.expires_at FROM public.storage_reservations AS sr WHERE sr.upload_session_id=sid) IS DISTINCT FROM exp OR (SELECT ii.state FROM public.intake_items AS ii WHERE ii.id=iid)<>'awaiting_upload' THEN RAISE EXCEPTION 'new reservation lineage/expiry'; END IF;
 IF (SELECT osp.max_pdf_bytes FROM public.organisation_storage_policies AS osp WHERE osp.org_id='36000000-0000-0000-0000-000000000001')<>26214400 OR (SELECT osp.unique_asset_entitlement_bytes FROM public.organisation_storage_policies AS osp WHERE osp.org_id='36000000-0000-0000-0000-000000000001')<>104857600 OR (SELECT psp.unique_asset_guard_bytes FROM public.platform_storage_policy AS psp WHERE psp.singleton)<>786432000 THEN RAISE EXCEPTION '25MiB/100MiB/750MiB defaults'; END IF;
 IF (SELECT count(*) FROM public.outbox_events AS oe WHERE oe.aggregate_id=sid AND oe.event_kind='document.upload_reserved.v1')<>1 THEN RAISE EXCEPTION 'reserve outbox count'; END IF;
END $privileged_reserve_assertions$;

SET LOCAL ROLE authenticated;
DO $roles$
DECLARE r record;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','36100000-0000-0000-0000-000000000002',true); SELECT * INTO r FROM public.reserve_document_upload('admin.pdf','application/pdf',1,NULL,'36500000-0000-0000-0000-000000000010'); IF r.code<>'ok' THEN RAISE EXCEPTION 'admin capability'; END IF;
 PERFORM set_config('request.jwt.claim.sub','36100000-0000-0000-0000-000000000003',true); SELECT * INTO r FROM public.reserve_document_upload('associate.pdf','application/pdf',1,NULL,'36500000-0000-0000-0000-000000000011'); IF r.code<>'ok' THEN RAISE EXCEPTION 'associate capability'; END IF;
 PERFORM set_config('request.jwt.claim.sub','36100000-0000-0000-0000-000000000004',true); SELECT * INTO r FROM public.reserve_document_upload('viewer.pdf','application/pdf',1,NULL,'36500000-0000-0000-0000-000000000012'); IF r.code<>'not_allowed' THEN RAISE EXCEPTION 'viewer denied'; END IF;
 PERFORM set_config('request.jwt.claim.sub','36100000-0000-0000-0000-000000000005',true); SELECT * INTO r FROM public.reserve_document_upload('suspended.pdf','application/pdf',1,NULL,'36500000-0000-0000-0000-000000000013'); IF r.code<>'not_allowed' OR public.has_organisation_capability('36000000-0000-0000-0000-000000000001','document.view') THEN RAISE EXCEPTION 'suspended denied'; END IF;
END $roles$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $service$
DECLARE r record; first_session uuid; duplicate_session uuid; cross_session uuid; count_before integer; h text:=repeat('a',64);
BEGIN
 -- Unique completion and stable retry; observed facts are the one allowed
 -- identity mutation and exact outbox payloads remain free of storage secrets.
 SELECT id INTO first_session FROM public.upload_sessions WHERE idempotency_key='36500000-0000-0000-0000-000000000001';
 SELECT * INTO r FROM public.complete_document_upload(first_session,1024,h,'application/pdf','36600000-0000-0000-0000-000000000001'); IF r.code<>'ok' THEN RAISE EXCEPTION 'unique completion'; END IF;
 SELECT * INTO r FROM public.complete_document_upload(first_session,1024,h,'application/pdf','36600000-0000-0000-0000-000000000002'); IF r.code<>'ok' THEN RAISE EXCEPTION 'completion retry'; END IF;
 IF (SELECT count(*) FROM public.outbox_events WHERE aggregate_id=first_session AND event_kind='document.upload_validation_requested.v1')<>1 OR EXISTS(SELECT 1 FROM public.outbox_events WHERE aggregate_id=first_session AND payload::text ~ '(filename|object|path|token|email)') THEN RAISE EXCEPTION 'safe complete event'; END IF;
 -- Same-org SHA is a duplicate, while a separate tenant keeps independent
 -- accounting and its own asset.
 EXECUTE 'SET LOCAL ROLE authenticated'; PERFORM set_config('request.jwt.claim.sub','36100000-0000-0000-0000-000000000001',true); SELECT * INTO r FROM public.reserve_document_upload('duplicate.pdf','application/pdf',5,NULL,'36500000-0000-0000-0000-000000000020'); EXECUTE 'SET LOCAL ROLE service_role'; duplicate_session:=r.upload_session_id;
 SELECT * INTO r FROM public.complete_document_upload(duplicate_session,5,h,'application/pdf','36600000-0000-0000-0000-000000000020'); IF r.code<>'duplicate' OR r.duplicate_asset_id IS NULL THEN RAISE EXCEPTION 'same org duplicate'; END IF;
 EXECUTE 'SET LOCAL ROLE authenticated'; PERFORM set_config('request.jwt.claim.sub','36100000-0000-0000-0000-000000000006',true); SELECT * INTO r FROM public.reserve_document_upload('cross.pdf','application/pdf',5,NULL,'36500000-0000-0000-0000-000000000021'); EXECUTE 'SET LOCAL ROLE service_role'; cross_session:=r.upload_session_id;
 SELECT * INTO r FROM public.complete_document_upload(cross_session,5,h,'application/pdf','36600000-0000-0000-0000-000000000021'); IF r.code<>'ok' THEN RAISE EXCEPTION 'cross org hash isolation'; END IF;
 -- Fail is allowlisted, terminal and idempotent.
 EXECUTE 'SET LOCAL ROLE authenticated'; PERFORM set_config('request.jwt.claim.sub','36100000-0000-0000-0000-000000000001',true); SELECT * INTO r FROM public.reserve_document_upload('fail.pdf','application/pdf',5,NULL,'36500000-0000-0000-0000-000000000022'); EXECUTE 'SET LOCAL ROLE service_role'; SELECT * INTO r FROM public.fail_document_upload(r.upload_session_id,'bad-error','36600000-0000-0000-0000-000000000022'); IF r.code<>'invalid_error_code' THEN RAISE EXCEPTION 'failure allowlist'; END IF;
 SELECT * INTO r FROM public.fail_document_upload((SELECT id FROM public.upload_sessions WHERE idempotency_key='36500000-0000-0000-0000-000000000022'),'upload_failed','36600000-0000-0000-0000-000000000023'); IF r.code<>'ok' THEN RAISE EXCEPTION 'fail command'; END IF; SELECT * INTO r FROM public.fail_document_upload(r.upload_session_id,'upload_failed','36600000-0000-0000-0000-000000000024'); IF r.code<>'ok' THEN RAISE EXCEPTION 'fail retry'; END IF;
 -- The initial 25MiB per-file boundary is exact; 100MiB entitlement and
 -- 750MiB platform guard defaults were asserted above. Observed size is
 -- independently rechecked rather than trusting the reservation.
 EXECUTE 'SET LOCAL ROLE authenticated'; SELECT * INTO r FROM public.reserve_document_upload('ceiling.pdf','application/pdf',26214400,NULL,'36500000-0000-0000-0000-000000000030'); IF r.code<>'ok' THEN RAISE EXCEPTION '25MiB file boundary'; END IF; SELECT * INTO r FROM public.reserve_document_upload('over.pdf','application/pdf',26214401,NULL,'36500000-0000-0000-0000-000000000031'); IF r.code<>'file_too_large' THEN RAISE EXCEPTION '25MiB boundary exceed'; END IF; EXECUTE 'SET LOCAL ROLE service_role'; SELECT * INTO r FROM public.complete_document_upload((SELECT id FROM public.upload_sessions WHERE idempotency_key='36500000-0000-0000-0000-000000000030'),26214401,repeat('b',64),'application/pdf','36600000-0000-0000-0000-000000000030'); IF r.code<>'file_too_large' THEN RAISE EXCEPTION 'observed quota recheck'; END IF;
 -- Stale reservation release uses a valid historical fixture, not immutable
 -- timestamp mutation; finalised history remains untouched.
 INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,availability,created_by,created_at) VALUES ('36700000-0000-0000-0000-000000000001','36000000-0000-0000-0000-000000000001','documents','orgs/36000000-0000-0000-0000-000000000001/assets/36700000-0000-0000-0000-000000000001/original.pdf','reserved','36100000-0000-0000-0000-000000000002',now()-interval '25 hours');
 INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,created_at,expires_at) VALUES ('36800000-0000-0000-0000-000000000001','36000000-0000-0000-0000-000000000001','36700000-0000-0000-0000-000000000001','stale.pdf','application/pdf',1,'reserved','36100000-0000-0000-0000-000000000002',now()-interval '25 hours',now()-interval '1 hour');
 INSERT INTO public.storage_reservations(org_id,upload_session_id,reserved_bytes,state,created_at,expires_at) VALUES ('36000000-0000-0000-0000-000000000001','36800000-0000-0000-0000-000000000001',1,'active',now()-interval '25 hours',now()-interval '1 hour');
 INSERT INTO public.intake_items(org_id,asset_id,upload_session_id,uploaded_by) VALUES('36000000-0000-0000-0000-000000000001','36700000-0000-0000-0000-000000000001','36800000-0000-0000-0000-000000000001','36100000-0000-0000-0000-000000000002');
 SELECT * INTO r FROM public.maintain_document_upload_sessions(100); IF r.expired_sessions<1 OR (SELECT us.state FROM public.upload_sessions AS us WHERE us.id='36800000-0000-0000-0000-000000000001')<>'expired' OR (SELECT us.state FROM public.upload_sessions AS us WHERE us.idempotency_key='36500000-0000-0000-0000-000000000001')<>'finalized' THEN RAISE EXCEPTION 'expiry maintenance'; END IF;
 IF EXISTS(SELECT 1 FROM public.document_upload_command_diagnostics) THEN RAISE EXCEPTION 'upload diagnostics'; END IF;
END $service$;
RESET ROLE;
ROLLBACK;
