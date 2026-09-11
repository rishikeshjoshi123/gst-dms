-- Exact logical Trash expiry and shared legal-worker Intake authority.
BEGIN;
\set ON_ERROR_STOP on

DO $fixture$
DECLARE
  org_a uuid := '14300000-0000-0000-0000-000000000001';
  org_b uuid := '14300000-0000-0000-0000-000000000002';
  owner_a uuid := '14310000-0000-0000-0000-000000000001';
  admin_a uuid := '14310000-0000-0000-0000-000000000002';
  associate_a uuid := '14310000-0000-0000-0000-000000000003';
  viewer_a uuid := '14310000-0000-0000-0000-000000000004';
  owner_b uuid := '14310000-0000-0000-0000-000000000005';
  client_a uuid := '14320000-0000-0000-0000-000000000001';
  client_c uuid := '14320000-0000-0000-0000-000000000002';
  matter_a uuid := '14330000-0000-0000-0000-000000000001';
  matter_c uuid := '14330000-0000-0000-0000-000000000002';
  document_a uuid := '14340000-0000-0000-0000-000000000001';
  document_b uuid := '14340000-0000-0000-0000-000000000002';
  document_c uuid := '14340000-0000-0000-0000-000000000003';
  operation_a uuid; operation_b uuid; operation_c uuid; owner_membership uuid;
  owner_intake uuid := '14380000-0000-0000-0000-000000000001';
  associate_intake uuid := '14380000-0000-0000-0000-000000000002';
  foreign_intake uuid := '14380000-0000-0000-0000-000000000003';
  row_count integer; outcome text; expired_deadline timestamptz;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES
    ('00000000-0000-0000-0000-000000000000',owner_a,'authenticated','authenticated','expiry-owner@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',admin_a,'authenticated','authenticated','expiry-admin@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',associate_a,'authenticated','authenticated','expiry-associate@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',viewer_a,'authenticated','authenticated','expiry-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',owner_b,'authenticated','authenticated','expiry-foreign@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES (org_a,'Expiry org',owner_a),(org_b,'Foreign org',owner_b);
  SELECT id INTO owner_membership FROM public.organisation_memberships WHERE org_id=org_a AND user_id=owner_a;
  UPDATE public.organisations SET owner_membership_id=owner_membership WHERE id=org_a;
  SELECT id INTO owner_membership FROM public.organisation_memberships WHERE org_id=org_b AND user_id=owner_b;
  UPDATE public.organisations SET owner_membership_id=owner_membership WHERE id=org_b;
  INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_by) VALUES
    (org_a,admin_a,'admin','active',1,owner_a),(org_a,associate_a,'associate','active',1,owner_a),
    (org_a,viewer_a,'viewer','active',1,owner_a);

  INSERT INTO public.clients(id,org_id,name) VALUES
    (client_a,org_a,'Expiry client'),(client_c,org_a,'Expired client root');
  INSERT INTO public.matters(id,org_id,client_id,title,financial_year) VALUES
    (matter_a,org_a,client_a,'Expiry matter','2026-27'),
    (matter_c,org_a,client_c,'Expired client descendant matter','2026-27');
  INSERT INTO public.documents(id,org_id,matter_id,display_title,created_by) VALUES
    (document_a,org_a,matter_a,'Expired descendant',owner_a),
    (document_b,org_a,matter_a,'Blocked document',owner_a),
    (document_c,org_a,matter_c,'Expired client descendant document',owner_a);
  INSERT INTO public.file_assets(
    id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,
    availability,created_by,validated_at,validated_page_count
  ) VALUES (
    '14350000-0000-0000-0000-000000000010',org_a,'documents',
    'orgs/14300000-0000-0000-0000-000000000001/assets/14350000-0000-0000-0000-000000000010/original.pdf',
    repeat('a',64),100,'application/pdf','available',owner_a,clock_timestamp(),1
  );
  INSERT INTO public.document_versions(
    id,org_id,document_id,asset_id,version_number,original_filename,page_count,
    validation_state,state,created_by,validated_at,promoted_at
  ) VALUES (
    '14370000-0000-0000-0000-000000000010',org_a,document_b,
    '14350000-0000-0000-0000-000000000010',1,'blocked.pdf',1,
    'valid','current',owner_a,clock_timestamp(),clock_timestamp()
  );
  UPDATE public.documents
  SET current_version_id='14370000-0000-0000-0000-000000000010',
      effective_filename='blocked.pdf',effective_size_bytes=100
  WHERE id=document_b;

  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',owner_a::text,true);
  SELECT result.operation_id INTO operation_b FROM public.trash_resource('document',document_b,'fixture.blocked') result;
  SELECT result.operation_id INTO operation_a FROM public.trash_resource('matter',matter_a,'fixture.expired') result;
  SELECT result.operation_id INTO operation_c FROM public.trash_resource('client',client_c,'fixture.expired-client') result;
  PERFORM set_config('request.jwt.claim.role','',true);
  expired_deadline := clock_timestamp()-interval '1 millisecond';
  UPDATE public.trash_operations SET retention_mode='retention_period',retention_days=30,
    auto_purge_enabled_snapshot=true,purge_eligible_at=expired_deadline,
    auto_purge_at=expired_deadline,
    created_at=CASE
      WHEN id=operation_a THEN clock_timestamp()
      WHEN id=operation_c THEN clock_timestamp()-interval '2 hours'
      ELSE clock_timestamp()-interval '1 day'
    END
  WHERE id IN (operation_a,operation_b,operation_c);
  INSERT INTO public.trash_purge_blockers(org_id,operation_id,resource_type,resource_id,blocker_kind,opaque_reference)
  VALUES(org_a,operation_b,'document',document_b,'active_export','14390000-0000-0000-0000-000000000001');

  -- Exact boundary: ordinary root and inherited child disclose no legal body,
  -- restore preflight/command, or operation identity.
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',owner_a::text,true);
  IF NOT EXISTS(
    SELECT 1 FROM public.trash_operations
    WHERE id=operation_a AND now()<auto_purge_at AND clock_timestamp()>=auto_purge_at
  ) THEN
    RAISE EXCEPTION 'fixture did not establish transaction-time versus wall-clock expiry';
  END IF;
  IF EXISTS(SELECT 1 FROM public.get_trash_workspace(org_a,NULL,NULL,operation_a,50) WHERE operation_id=operation_a)
     OR EXISTS(SELECT 1 FROM public.get_exact_trashed_resource_projection('matter',matter_a,NULL))
     OR EXISTS(SELECT 1 FROM public.get_exact_trashed_resource_projection('document',document_a,matter_a))
     OR EXISTS(SELECT 1 FROM public.get_trash_workspace(org_a,NULL,NULL,operation_c,50) WHERE operation_id=operation_c)
     OR EXISTS(SELECT 1 FROM public.get_exact_trashed_resource_projection('client',client_c,NULL))
     OR EXISTS(SELECT 1 FROM public.get_exact_trashed_resource_projection('matter',matter_c,NULL))
     OR EXISTS(SELECT 1 FROM public.get_exact_trashed_resource_projection('document',document_c,matter_c))
     OR EXISTS(SELECT 1 FROM public.get_exact_resource_trash_context('matter',matter_a,NULL)) THEN
    RAISE EXCEPTION 'ordinary logical expiry disclosed a root or descendant';
  END IF;
  SELECT code INTO outcome FROM public.get_trash_restore_preflight(operation_a);
  IF outcome<>'not_available' THEN RAISE EXCEPTION 'expired Restore preflight remained available'; END IF;
  SELECT code INTO outcome FROM public.restore_trash_operation(operation_a,'fixture.expired.restore');
  IF outcome<>'not_available' OR EXISTS(SELECT 1 FROM public.trash_restore_receipts WHERE operation_id=operation_a) THEN
    RAISE EXCEPTION 'expired Restore command disclosed or wrote a receipt';
  END IF;
  BEGIN
    UPDATE public.trash_operations SET state='restoring' WHERE id=operation_a;
    RAISE EXCEPTION 'expired state transition bypassed the wall-clock fence';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'trash_restore_deadline_expired' THEN RAISE; END IF;
  END;

  -- An active mandatory blocker remains as content-safe status only for Owner/Admin.
  IF NOT EXISTS(SELECT 1 FROM public.get_trash_workspace(org_a,NULL,NULL,operation_b,50) WHERE operation_id=operation_b)
     OR NOT EXISTS(SELECT 1 FROM public.get_trash_workspace(org_a,NULL,NULL,NULL,1) WHERE operation_id=operation_b)
     OR NOT EXISTS(SELECT 1 FROM public.get_trash_workspace_retention(org_a,ARRAY[operation_b]) WHERE retention_status='blocked' AND blocker_count=1)
     OR EXISTS(SELECT 1 FROM public.get_exact_trashed_resource_projection('document',document_b,matter_a))
     OR EXISTS(SELECT 1 FROM public.get_trashed_document_version_read_grant(
       document_b,matter_a,'14370000-0000-0000-0000-000000000010'
     )) THEN
    RAISE EXCEPTION 'blocked expiry visibility was not content-safe and truthful';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',admin_a::text,true);
  IF NOT EXISTS(SELECT 1 FROM public.get_trash_workspace(org_a,NULL,NULL,operation_b,50) WHERE operation_id=operation_b) THEN
    RAISE EXCEPTION 'Admin could not see blocked expiry status';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',associate_a::text,true);
  IF EXISTS(SELECT 1 FROM public.get_trash_workspace(org_a,NULL,NULL,operation_b,50) WHERE operation_id=operation_b) THEN
    RAISE EXCEPTION 'Associate saw blocked expired operation';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',viewer_a::text,true);
  IF EXISTS(SELECT 1 FROM public.get_trash_workspace(org_a,NULL,NULL,operation_b,50) WHERE operation_id=operation_b) THEN
    RAISE EXCEPTION 'Viewer saw blocked expired operation';
  END IF;
  IF EXISTS(SELECT 1 FROM public.get_trash_workspace(org_b,NULL,NULL,NULL,50)) THEN
    RAISE EXCEPTION 'forged organisation disclosed Trash rows';
  END IF;

  -- A purge failure does not resurrect ordinary logically expired content.
  PERFORM set_config('request.jwt.claim.role','',true);
  UPDATE public.trash_operations SET state='purge_scheduled',purge_scheduled_at=now() WHERE id=operation_a;
  UPDATE public.trash_operations SET state='purging',purge_started_at=now() WHERE id=operation_a;
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',owner_a::text,true);
  IF EXISTS(SELECT 1 FROM public.get_trash_workspace(org_a,NULL,NULL,operation_a,50) WHERE operation_id=operation_a)
     OR EXISTS(SELECT 1 FROM public.get_exact_trashed_resource_projection('matter',matter_a,NULL)) THEN
    RAISE EXCEPTION 'in-progress purge resurrected logically expired content';
  END IF;
  PERFORM set_config('request.jwt.claim.role','',true);
  UPDATE public.trash_operations SET state='purge_failed',purge_failed_at=now(),last_error_code='provider_retryable'
    WHERE id=operation_a;
  UPDATE public.matters SET record_state='purging' WHERE id=matter_a;
  UPDATE public.documents SET record_state='purging' WHERE id=document_a;
  UPDATE public.resource_trash_memberships SET state='purging' WHERE operation_id=operation_a;
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',owner_a::text,true);
  IF EXISTS(SELECT 1 FROM public.get_trash_workspace(org_a,NULL,NULL,operation_a,50) WHERE operation_id=operation_a)
     OR EXISTS(SELECT 1 FROM public.get_exact_trashed_resource_projection('matter',matter_a,NULL)) THEN
    RAISE EXCEPTION 'purge failure resurrected logically expired content';
  END IF;

  -- Synthetic canonical Intake rows for two tenant members and one foreign tenant.
  PERFORM set_config('request.jwt.claim.role','',true);
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,created_by,validated_at) VALUES
    ('14350000-0000-0000-0000-000000000001',org_a,'documents','orgs/14300000-0000-0000-0000-000000000001/assets/14350000-0000-0000-0000-000000000001/original.pdf',repeat('1',64),100,'application/pdf','available',owner_a,now()),
    ('14350000-0000-0000-0000-000000000002',org_a,'documents','orgs/14300000-0000-0000-0000-000000000001/assets/14350000-0000-0000-0000-000000000002/original.pdf',repeat('2',64),100,'application/pdf','available',associate_a,now()),
    ('14350000-0000-0000-0000-000000000003',org_b,'documents','orgs/14300000-0000-0000-0000-000000000002/assets/14350000-0000-0000-0000-000000000003/original.pdf',repeat('3',64),100,'application/pdf','available',owner_b,now());
  INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_byte_size,state,created_by,uploaded_at,finalized_at) VALUES
    ('14360000-0000-0000-0000-000000000001',org_a,'14350000-0000-0000-0000-000000000001','owner.pdf',100,'finalized',owner_a,now(),now()),
    ('14360000-0000-0000-0000-000000000002',org_a,'14350000-0000-0000-0000-000000000002','associate.pdf',100,'finalized',associate_a,now(),now()),
    ('14360000-0000-0000-0000-000000000003',org_b,'14350000-0000-0000-0000-000000000003','foreign.pdf',100,'finalized',owner_b,now(),now());
  INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,state,uploaded_by) VALUES
    (owner_intake,org_a,'14350000-0000-0000-0000-000000000001','14360000-0000-0000-0000-000000000001','ready',owner_a),
    (associate_intake,org_a,'14350000-0000-0000-0000-000000000002','14360000-0000-0000-0000-000000000002','ready',associate_a),
    (foreign_intake,org_b,'14350000-0000-0000-0000-000000000003','14360000-0000-0000-0000-000000000003','ready',owner_b);

  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',associate_a::text,true);
  SELECT count(*) INTO row_count FROM public.get_document_hub_intake('mine',0,50,NULL);
  IF row_count<>1 OR NOT EXISTS(SELECT 1 FROM public.get_document_hub_intake('mine',0,50,NULL) WHERE id=associate_intake AND is_mine)
     OR (SELECT count(*) FROM public.get_document_hub_intake('all',0,50,NULL))<>2
     OR EXISTS(SELECT 1 FROM public.get_document_hub_intake('all',0,50,NULL) WHERE id=foreign_intake)
     OR NOT EXISTS(SELECT 1 FROM public.get_intake_item_triage_context(owner_intake) WHERE uploaded_by=owner_a)
     OR NOT EXISTS(SELECT 1 FROM public.get_intake_item_read_grant(owner_intake) WHERE code='ok' AND object_key LIKE 'orgs/%/original.pdf') THEN
    RAISE EXCEPTION 'Associate shared Intake read/triage authority failed';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',owner_a::text,true);
  IF (SELECT count(*) FROM public.get_document_hub_intake('all',0,50,NULL))<>2 THEN
    RAISE EXCEPTION 'Owner could not read organisation-wide Intake';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',admin_a::text,true);
  IF (SELECT count(*) FROM public.get_document_hub_intake('all',0,50,NULL))<>2 THEN
    RAISE EXCEPTION 'Admin could not read organisation-wide Intake';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',viewer_a::text,true);
  IF EXISTS(SELECT 1 FROM public.get_document_hub_intake('all',0,50,NULL))
     OR EXISTS(SELECT 1 FROM public.get_intake_item_triage_context(owner_intake))
     OR EXISTS(SELECT 1 FROM public.get_intake_item_read_grant(owner_intake)) THEN
    RAISE EXCEPTION 'Viewer received unplaced Intake data or source authority';
  END IF;
  SELECT code INTO outcome FROM public.discard_intake_item(owner_intake,'14390000-0000-0000-0000-000000000002');
  IF outcome<>'invalid_request' THEN RAISE EXCEPTION 'Viewer direct Intake action was not denied'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.intake_items WHERE id=owner_intake AND state='ready') THEN
    RAISE EXCEPTION 'Viewer denial changed Intake state';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',associate_a::text,true);
  IF EXISTS(SELECT 1 FROM public.get_intake_item_triage_context(foreign_intake))
     OR EXISTS(SELECT 1 FROM public.get_intake_item_read_grant(foreign_intake)) THEN
    RAISE EXCEPTION 'foreign Intake identifier disclosed data or source authority';
  END IF;
  SELECT code INTO outcome FROM public.discard_intake_item(foreign_intake,'14390000-0000-0000-0000-000000000004');
  IF outcome<>'not_found' THEN RAISE EXCEPTION 'foreign Intake direct action was not denied'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.intake_items WHERE id=foreign_intake AND state='ready') THEN
    RAISE EXCEPTION 'foreign denial changed Intake state';
  END IF;
  SELECT code INTO outcome FROM public.discard_intake_item(owner_intake,'14390000-0000-0000-0000-000000000003');
  IF outcome<>'ok' THEN RAISE EXCEPTION 'Associate could not triage a shared Intake row'; END IF;
END $fixture$;

DO $privileges$
BEGIN
  IF has_function_privilege('anon','public.get_document_hub_intake(text,integer,integer,uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.get_document_hub_intake(text,integer,integer,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.get_document_hub_intake(text,integer,integer,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.get_trash_workspace_before_logical_expiry(uuid,text,public.trash_resource_type,uuid,integer)','EXECUTE')
     OR has_function_privilege('authenticated','public.get_exact_trashed_resource_projection_before_logical_expiry(public.trash_resource_type,uuid,uuid)','EXECUTE')
     OR has_table_privilege('authenticated','public.intake_items','SELECT') THEN
    RAISE EXCEPTION 'logical-expiry or shared-Intake privileges are unsafe';
  END IF;
END $privileges$;

ROLLBACK;
