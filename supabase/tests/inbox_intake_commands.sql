-- Run after migration 00046 against a disposable local Supabase database.
BEGIN;

DO $setup$
DECLARE org_a uuid:='43000000-0000-0000-0000-000000000001'; org_b uuid:='43000000-0000-0000-0000-000000000002';
  owner uuid:='43100000-0000-0000-0000-000000000001'; viewer uuid:='43100000-0000-0000-0000-000000000002'; other uuid:='43100000-0000-0000-0000-000000000003';
  client_id uuid:='43200000-0000-0000-0000-000000000001'; matter_id uuid:='43300000-0000-0000-0000-000000000001';
  document_active uuid:='43900000-0000-0000-0000-000000000001'; document_trashed uuid:='43900000-0000-0000-0000-000000000002'; version_historical uuid:='44000000-0000-0000-0000-000000000001'; version_current uuid:='44000000-0000-0000-0000-000000000002'; version_trashed uuid:='44000000-0000-0000-0000-000000000003';
  asset_ready uuid:='43400000-0000-0000-0000-000000000001'; asset_discard uuid:='43400000-0000-0000-0000-000000000002'; asset_failed uuid:='43400000-0000-0000-0000-000000000003'; asset_duplicate uuid:='43400000-0000-0000-0000-000000000004'; asset_expired uuid:='43400000-0000-0000-0000-000000000005'; asset_assigned uuid:='43400000-0000-0000-0000-000000000006'; asset_trash uuid:='43400000-0000-0000-0000-000000000007';
  session_ready uuid:='43500000-0000-0000-0000-000000000001'; session_discard uuid:='43500000-0000-0000-0000-000000000002'; session_failed uuid:='43500000-0000-0000-0000-000000000003'; session_duplicate uuid:='43500000-0000-0000-0000-000000000004'; session_expired uuid:='43500000-0000-0000-0000-000000000005'; session_assigned uuid:='43500000-0000-0000-0000-000000000006'; session_trash uuid:='43500000-0000-0000-0000-000000000007';
  intake_ready uuid:='43600000-0000-0000-0000-000000000001'; intake_discard uuid:='43600000-0000-0000-0000-000000000002'; intake_failed uuid:='43600000-0000-0000-0000-000000000003'; intake_duplicate uuid:='43600000-0000-0000-0000-000000000004'; intake_expired uuid:='43600000-0000-0000-0000-000000000005'; intake_assigned uuid:='43600000-0000-0000-0000-000000000006'; intake_trash uuid:='43600000-0000-0000-0000-000000000007';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  SELECT '00000000-0000-0000-0000-000000000000',id,'authenticated','authenticated',id::text||'@inbox.test','x',now(),'{}','{}',now(),now()
  FROM unnest(ARRAY[owner,viewer,other]) AS id;
  INSERT INTO public.organisations(id,name,created_by) VALUES(org_a,'Inbox A',owner),(org_b,'Inbox B',other);
  INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at)
    VALUES('43700000-0000-0000-0000-000000000001',org_a,viewer,'viewer','active',1,now());
  INSERT INTO public.clients(id,org_id,name) VALUES(client_id,org_a,'Inbox client');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES(matter_id,org_a,client_id,'Inbox matter');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
    VALUES(asset_ready,org_a,'documents','orgs/'||org_a||'/assets/'||asset_ready||'/original.pdf',10,'application/pdf','available',now(),1,owner),
          (asset_discard,org_a,'documents','orgs/'||org_a||'/assets/'||asset_discard||'/original.pdf',20,'application/pdf','available',now(),1,owner),
          (asset_failed,org_a,'documents','orgs/'||org_a||'/assets/'||asset_failed||'/original.pdf',30,'application/pdf','available',now(),1,owner),
          (asset_duplicate,org_a,'documents','orgs/'||org_a||'/assets/'||asset_duplicate||'/original.pdf',40,'application/pdf','available',now(),1,owner),
          (asset_expired,org_a,'documents','orgs/'||org_a||'/assets/'||asset_expired||'/original.pdf',50,'application/pdf','available',now(),1,owner),
          (asset_assigned,org_a,'documents','orgs/'||org_a||'/assets/'||asset_assigned||'/original.pdf',60,'application/pdf','available',now(),1,owner),
          (asset_trash,org_a,'documents','orgs/'||org_a||'/assets/'||asset_trash||'/original.pdf',70,'application/pdf','available',now(),1,owner);
  UPDATE public.file_assets SET availability='failed',validated_at=NULL,failed_at=now(),failure_code='validation_failed' WHERE id=asset_failed;
  INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,uploaded_at,finalized_at)
    VALUES(session_ready,org_a,asset_ready,'ready.pdf','application/pdf',10,'finalized',owner,now(),now()),
          (session_discard,org_a,asset_discard,'discard.pdf','application/pdf',20,'finalized',owner,now(),now()),
          (session_failed,org_a,asset_failed,'failed.pdf','application/pdf',30,'finalized',owner,now(),now()),
          (session_duplicate,org_a,asset_duplicate,'duplicate.pdf','application/pdf',40,'finalized',owner,now(),now()),
          (session_expired,org_a,asset_expired,'expired.pdf','application/pdf',50,'finalized',owner,now(),now()),
          (session_assigned,org_a,asset_assigned,'assigned.pdf','application/pdf',60,'finalized',owner,now(),now()),
          (session_trash,org_a,asset_trash,'trashed.pdf','application/pdf',70,'finalized',owner,now(),now());
  INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,state,uploaded_by,failed_at,failure_code)
    VALUES(intake_ready,org_a,asset_ready,session_ready,'ready',owner,NULL,NULL),
          (intake_discard,org_a,asset_discard,session_discard,'ready',owner,NULL,NULL),
          (intake_failed,org_a,asset_failed,session_failed,'failed',owner,now(),'validation_failed'),
          (intake_duplicate,org_a,asset_duplicate,session_duplicate,'duplicate',owner,NULL,'duplicate'),
          (intake_trash,org_a,asset_trash,session_trash,'duplicate',owner,NULL,'duplicate');
  INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,state,uploaded_by,expired_at,failure_code)
    VALUES(intake_expired,org_a,asset_expired,session_expired,'expired',owner,now(),'upload_expired');
  INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,state,uploaded_by,assigned_at)
    VALUES(intake_assigned,org_a,asset_assigned,session_assigned,'assigned',owner,now());
  INSERT INTO public.documents(id,org_id,matter_id,display_title,origin_kind,record_state,content_availability,status,storage_path,created_by,trashed_at,deleted_at)
    VALUES(document_active,org_a,matter_id,'Replaced duplicate','upload','active','source_attached','placed',NULL,owner,NULL,NULL),
          (document_trashed,org_a,matter_id,'Trashed duplicate','upload','trashed','source_attached','placed',NULL,owner,now(),now());
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,validation_state,state,validated_at,promoted_at,superseded_at)
    VALUES(version_historical,org_a,document_active,asset_duplicate,1,'duplicate.pdf','valid','superseded',now(),NULL,now()),
          (version_current,org_a,document_active,asset_assigned,2,'replacement.pdf','valid','current',now(),now(),NULL),
          (version_trashed,org_a,document_trashed,asset_trash,1,'trashed.pdf','valid','current',now(),now(),NULL);
  UPDATE public.documents SET current_version_id=version_current WHERE id=document_active;
  UPDATE public.documents SET current_version_id=version_trashed WHERE id=document_trashed;
  INSERT INTO public.document_upload_command_receipts(org_id,upload_session_id,command,idempotency_key,code,duplicate_asset_id)
    VALUES(org_a,session_duplicate,'complete','43800000-0000-0000-0000-000000000008','duplicate',asset_duplicate),
          (org_a,session_trash,'complete','43800000-0000-0000-0000-000000000009','duplicate',asset_trash);
END $setup$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','43100000-0000-0000-0000-000000000001',true);
DO $owner$
DECLARE read_grant record; placed record; discarded record; retried record; terminal_result record; duplicate_result record;
BEGIN
  SELECT * INTO read_grant FROM public.get_intake_item_read_grant('43600000-0000-0000-0000-000000000001');
  IF read_grant.code<>'ok' OR read_grant.bucket_id<>'documents' OR read_grant.object_key !~ '/original.pdf$' THEN RAISE EXCEPTION 'ready intake signing grant'; END IF;
  SELECT * INTO placed FROM public.assign_intake_to_new_document('43600000-0000-0000-0000-000000000001','43300000-0000-0000-0000-000000000001','Ready intake','43100000-0000-0000-0000-000000000001','43800000-0000-0000-0000-000000000001');
  IF placed.code<>'ok' OR placed.document_id IS NULL OR placed.document_version_id IS NULL THEN RAISE EXCEPTION 'atomic placement'; END IF;
  PERFORM set_config('test.inbox_placed_document',placed.document_id::text,true);
  PERFORM set_config('test.inbox_placed_version',placed.document_version_id::text,true);
  SELECT * INTO terminal_result FROM public.assign_intake_to_new_document('43600000-0000-0000-0000-000000000002','43300000-0000-0000-0000-000000000001','Must not reuse receipt','43100000-0000-0000-0000-000000000001','43800000-0000-0000-0000-000000000001');
  IF terminal_result.code<>'idempotency_subject_mismatch' OR terminal_result.document_id IS NOT NULL THEN RAISE EXCEPTION 'assignment receipt subject binding'; END IF;
  SELECT * INTO discarded FROM public.discard_intake_item('43600000-0000-0000-0000-000000000002','43800000-0000-0000-0000-000000000002');
  SELECT * INTO retried FROM public.discard_intake_item('43600000-0000-0000-0000-000000000002','43800000-0000-0000-0000-000000000002');
  IF discarded.code<>'ok' OR retried.code<>'ok' THEN RAISE EXCEPTION 'safe idempotent discard command'; END IF;
  SELECT * INTO terminal_result FROM public.discard_intake_item('43600000-0000-0000-0000-000000000003','43800000-0000-0000-0000-000000000002');
  IF terminal_result.code<>'idempotency_subject_mismatch' THEN RAISE EXCEPTION 'discard receipt subject binding'; END IF;
  SELECT * INTO terminal_result FROM public.discard_intake_item('43600000-0000-0000-0000-000000000003','43800000-0000-0000-0000-000000000004');
  IF terminal_result.code<>'intake_not_discardable' THEN RAISE EXCEPTION 'failed intake terminal command'; END IF;
  SELECT * INTO terminal_result FROM public.discard_intake_item('43600000-0000-0000-0000-000000000004','43800000-0000-0000-0000-000000000005');
  IF terminal_result.code<>'intake_not_discardable' THEN RAISE EXCEPTION 'duplicate intake terminal command'; END IF;
  SELECT * INTO terminal_result FROM public.discard_intake_item('43600000-0000-0000-0000-000000000005','43800000-0000-0000-0000-000000000006');
  IF terminal_result.code<>'intake_not_discardable' THEN RAISE EXCEPTION 'expired intake terminal command'; END IF;
  SELECT * INTO terminal_result FROM public.discard_intake_item('43600000-0000-0000-0000-000000000006','43800000-0000-0000-0000-000000000007');
  IF terminal_result.code<>'intake_not_discardable' THEN RAISE EXCEPTION 'assigned intake terminal command'; END IF;
  SELECT * INTO duplicate_result FROM public.get_intake_duplicate_resolution('43600000-0000-0000-0000-000000000004');
  IF duplicate_result.code<>'ok' OR duplicate_result.document_id<>'43900000-0000-0000-0000-000000000001'::uuid OR duplicate_result.matter_id<>'43300000-0000-0000-0000-000000000001'::uuid THEN RAISE EXCEPTION 'historical duplicate did not recover active logical document'; END IF;
  SELECT * INTO duplicate_result FROM public.get_intake_duplicate_resolution('43600000-0000-0000-0000-000000000007');
  IF duplicate_result.code<>'in_trash' OR duplicate_result.document_id IS NOT NULL OR duplicate_result.matter_id IS NOT NULL THEN RAISE EXCEPTION 'trashed duplicate disclosed identifiers or was not restore-required'; END IF;
END $owner$;
RESET ROLE;

DO $inspection$
DECLARE placed_version uuid:=current_setting('test.inbox_placed_version')::uuid;
BEGIN
  IF (SELECT asset_id FROM public.document_versions WHERE id=placed_version) <> '43400000-0000-0000-0000-000000000001'::uuid
     OR (SELECT state FROM public.intake_items WHERE id='43600000-0000-0000-0000-000000000001')<>'assigned' THEN RAISE EXCEPTION 'placement copied or did not assign'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.outbox_events WHERE event_kind='intake.assigned.v1' AND aggregate_id='43600000-0000-0000-0000-000000000001'
                 AND payload::text !~* '(path|object|filename|content|token)') THEN RAISE EXCEPTION 'assignment event missing or unsafe'; END IF;
  IF (SELECT state FROM public.intake_items WHERE id='43600000-0000-0000-0000-000000000002')<>'discarded'
     OR (SELECT availability FROM public.file_assets WHERE id='43400000-0000-0000-0000-000000000002')<>'failed'
     OR NOT EXISTS (SELECT 1 FROM public.outbox_events WHERE event_kind='intake.discarded.v1' AND aggregate_id='43600000-0000-0000-0000-000000000002') THEN RAISE EXCEPTION 'safe idempotent discard state'; END IF;
  IF (SELECT state FROM public.intake_items WHERE id='43600000-0000-0000-0000-000000000003')<>'failed'
     OR (SELECT state FROM public.intake_items WHERE id='43600000-0000-0000-0000-000000000004')<>'duplicate'
     OR (SELECT state FROM public.intake_items WHERE id='43600000-0000-0000-0000-000000000005')<>'expired'
     OR (SELECT state FROM public.intake_items WHERE id='43600000-0000-0000-0000-000000000006')<>'assigned' THEN RAISE EXCEPTION 'terminal intake state changed'; END IF;
END $inspection$;

SET LOCAL ROLE service_role;
DO $storage_cleanup$
DECLARE claimed record; completion record; repeated_completion record;
BEGIN
  -- Discard has left this failed asset without a document-version reference.
  -- Claim it directly to protect the worker RPC contract from output-column
  -- ambiguity, then ensure the completion path writes a durable tombstone.
  SELECT * INTO claimed
  FROM public.claim_document_asset_storage_deletion_work(100)
  WHERE asset_id='43400000-0000-0000-0000-000000000002'::uuid;
  IF NOT FOUND
     OR claimed.bucket_id<>'documents'
     OR claimed.object_key<>'orgs/43000000-0000-0000-0000-000000000001/assets/43400000-0000-0000-0000-000000000002/original.pdf'
     OR claimed.lease_token IS NULL THEN
    RAISE EXCEPTION 'terminal asset storage deletion claim';
  END IF;

  SELECT * INTO completion
  FROM public.finish_document_asset_storage_deletion_work(claimed.asset_id,claimed.lease_token,'deleted');
  IF completion.code<>'deleted'
     OR NOT EXISTS (
       SELECT 1 FROM public.file_assets AS fa
       WHERE fa.id=claimed.asset_id
         AND fa.storage_deleted_at IS NOT NULL
         AND fa.storage_delete_attempted_at IS NOT NULL
         AND fa.storage_deletion_lease_token IS NULL
         AND fa.storage_deletion_lease_expires_at IS NULL
     ) THEN
    RAISE EXCEPTION 'terminal asset storage deletion tombstone';
  END IF;

  SELECT * INTO repeated_completion
  FROM public.finish_document_asset_storage_deletion_work(claimed.asset_id,claimed.lease_token,'deleted');
  IF repeated_completion.code<>'already_deleted' THEN
    RAISE EXCEPTION 'terminal asset storage deletion completion idempotency';
  END IF;
END $storage_cleanup$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','43100000-0000-0000-0000-000000000002',true);
DO $viewer$
DECLARE read_grant record; discard_result record;
BEGIN
  SELECT * INTO read_grant FROM public.get_intake_item_read_grant('43600000-0000-0000-0000-000000000002');
  IF read_grant.code IS NOT NULL THEN RAISE EXCEPTION 'discarded intake grant leaked'; END IF;
  SELECT * INTO discard_result FROM public.discard_intake_item('43600000-0000-0000-0000-000000000001','43800000-0000-0000-0000-000000000003');
  IF discard_result.code<>'invalid_request' THEN RAISE EXCEPTION 'viewer discard was not denied'; END IF;
END $viewer$;
RESET ROLE;
ROLLBACK;
