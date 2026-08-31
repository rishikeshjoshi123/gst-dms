-- Run after a clean reset through migration 00090. Every mutation is rolled
-- back. The fixture covers policy capability/CAS, atomic operation snapshots,
-- durable warning projection, source resolution, and private-table grants.
BEGIN;

DO $fixture$
DECLARE
  org uuid := '90000000-0000-0000-0000-000000000001';
  other_org uuid := '90000000-0000-0000-0000-000000000002';
  owner uuid := '90100000-0000-0000-0000-000000000001';
  associate_user uuid := '90100000-0000-0000-0000-000000000002';
  viewer_user uuid := '90100000-0000-0000-0000-000000000003';
  other_owner uuid := '90100000-0000-0000-0000-000000000004';
  client uuid := '90200000-0000-0000-0000-000000000001';
  matter uuid := '90300000-0000-0000-0000-000000000001';
  first_document uuid := '90400000-0000-0000-0000-000000000001';
  second_document uuid := '90400000-0000-0000-0000-000000000002';
  third_document uuid := '90400000-0000-0000-0000-000000000003';
  other_client uuid := '90200000-0000-0000-0000-000000000002';
  other_matter uuid := '90300000-0000-0000-0000-000000000002';
  other_document uuid := '90400000-0000-0000-0000-000000000004';
  membership uuid;
  first_operation uuid;
  second_operation uuid;
  third_operation uuid;
  first_schedule timestamptz;
  result record;
  policy record;
  denied boolean;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES
    ('00000000-0000-0000-0000-000000000000',owner,'authenticated','authenticated','retention-owner@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',associate_user,'authenticated','authenticated','retention-associate@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',viewer_user,'authenticated','authenticated','retention-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',other_owner,'authenticated','authenticated','retention-other@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by)
  VALUES(org,'Retention policy fixture',owner),(other_org,'Other retention fixture',other_owner);
  SELECT id INTO membership FROM public.organisation_memberships WHERE org_id=org AND user_id=owner;
  UPDATE public.organisations SET owner_membership_id=membership WHERE id=org;
  SELECT id INTO membership FROM public.organisation_memberships WHERE org_id=other_org AND user_id=other_owner;
  UPDATE public.organisations SET owner_membership_id=membership WHERE id=other_org;
  INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_by)
  VALUES
    (org,associate_user,'associate','active',1,owner),
    (org,viewer_user,'viewer','active',1,owner);

  IF NOT EXISTS (
    SELECT 1 FROM public.organisation_retention_settings settings
    WHERE settings.org_id=org AND settings.trash_retention_mode='retention_period'
      AND settings.trash_retention_days=90 AND settings.auto_purge_enabled
      AND settings.policy_version=1
  ) THEN RAISE EXCEPTION 'new organisation did not receive the 90-day automatic policy'; END IF;

  INSERT INTO public.clients(id,org_id,name,gstin,pan)
  VALUES(client,org,'Retention fixture client','27FFFFF0000F1Z5','FFFFF0000F');
  INSERT INTO public.matters(id,org_id,client_id,title,financial_year,matter_code)
  VALUES(matter,org,client,'Retention fixture matter','2026-27','RET-2627-01');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by,display_title)
  VALUES
    (first_document,org,matter,'fixture/retention-first.pdf',owner,'First retained document'),
    (second_document,org,matter,'fixture/retention-second.pdf',owner,'Second retained document'),
    (third_document,org,matter,'fixture/retention-third.pdf',owner,'Third retained document');
  INSERT INTO public.clients(id,org_id,name,gstin,pan)
  VALUES(other_client,other_org,'Other retention client','27HHHHH0000H1Z5','HHHHH0000H');
  INSERT INTO public.matters(id,org_id,client_id,title,financial_year,matter_code)
  VALUES(other_matter,other_org,other_client,'Other retention matter','2026-27','OTHER-2627-01');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by,display_title)
  VALUES(other_document,other_org,other_matter,'fixture/retention-other.pdf',other_owner,'Other retained document');

  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',associate_user::text,true);
  SELECT * INTO policy FROM public.get_organisation_trash_retention_policy(org);
  IF policy.trash_retention_days<>90 OR policy.policy_version<>1 OR policy.can_manage THEN
    RAISE EXCEPTION 'Associate did not receive the read-only policy';
  END IF;
  SELECT * INTO result FROM public.update_organisation_trash_retention_policy(org,30,1);
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'Associate changed retention policy'; END IF;

  PERFORM set_config('request.jwt.claim.sub',viewer_user::text,true);
  SELECT * INTO policy FROM public.get_organisation_trash_retention_policy(org);
  IF policy.trash_retention_days<>90 OR policy.can_manage THEN
    RAISE EXCEPTION 'Viewer did not receive the read-only policy';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',owner::text,true);
  SELECT * INTO policy FROM public.get_organisation_trash_retention_policy(org);
  IF NOT policy.can_manage OR policy.policy_version<>1 THEN RAISE EXCEPTION 'Owner policy capability missing'; END IF;
  SELECT * INTO result FROM public.update_organisation_trash_retention_policy(org,30,1);
  IF result.code<>'updated' OR result.trash_retention_days<>30 OR result.policy_version<>2 THEN
    RAISE EXCEPTION 'Owner policy update failed';
  END IF;
  SELECT * INTO result FROM public.update_organisation_trash_retention_policy(org,60,1);
  IF result.code<>'conflict' OR result.trash_retention_days<>30 OR result.policy_version<>2 THEN
    RAISE EXCEPTION 'stale policy save overwrote or hid the current version';
  END IF;
  SELECT * INTO result FROM public.update_organisation_trash_retention_policy(other_org,60,1);
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'cross-tenant policy update was accepted'; END IF;
  IF EXISTS (SELECT 1 FROM public.get_organisation_trash_retention_policy(other_org)) THEN
    RAISE EXCEPTION 'cross-tenant policy read disclosed a row';
  END IF;
  SELECT * INTO result FROM public.trash_resource('document',other_document,'retention.fixture.forged');
  IF result.code<>'not_available' OR result.operation_id IS NOT NULL
     OR (SELECT record_state::text FROM public.documents WHERE id=other_document)<>'active' THEN
    RAISE EXCEPTION 'forged cross-tenant Trash resource ID was disclosed or mutated';
  END IF;

  SELECT operation_id INTO first_operation
  FROM public.trash_resource('document',first_document,'retention.fixture.first');
  SELECT operation.auto_purge_at INTO first_schedule FROM public.trash_operations operation WHERE operation.id=first_operation;
  IF NOT EXISTS (
    SELECT 1 FROM public.trash_operations operation
    WHERE operation.id=first_operation AND operation.retention_mode='retention_period'
      AND operation.retention_days=30 AND operation.auto_purge_enabled_snapshot
      AND operation.retention_policy_version=2
      AND operation.purge_eligible_at=operation.auto_purge_at
      AND operation.auto_purge_at=operation.created_at+interval '30 days'
  ) THEN RAISE EXCEPTION 'first Trash operation did not atomically snapshot 30-day policy v2'; END IF;

  SELECT * INTO result FROM public.update_organisation_trash_retention_policy(org,60,2);
  IF result.code<>'updated' OR result.policy_version<>3 THEN RAISE EXCEPTION 'second policy update failed'; END IF;
  IF (SELECT auto_purge_at FROM public.trash_operations WHERE id=first_operation) IS DISTINCT FROM first_schedule
     OR (SELECT retention_days FROM public.trash_operations WHERE id=first_operation)<>30 THEN
    RAISE EXCEPTION 'prospective policy update changed an existing Trash operation';
  END IF;

  SELECT operation_id INTO second_operation
  FROM public.trash_resource('document',second_document,'retention.fixture.second');
  SELECT operation_id INTO third_operation
  FROM public.trash_resource('document',third_document,'retention.fixture.third');
  IF NOT EXISTS (
    SELECT 1 FROM public.trash_operations operation
    WHERE operation.id IN (second_operation,third_operation)
      AND operation.retention_days=60 AND operation.retention_policy_version=3
      AND operation.auto_purge_at=operation.created_at+interval '60 days'
  ) THEN RAISE EXCEPTION 'new Trash operation did not use the current 60-day policy'; END IF;

  -- Move only the first schedule into the warning window. This is test setup,
  -- not a product policy mutation path; the private table remains ungranted.
  UPDATE public.trash_operations
  SET purge_eligible_at=now()+interval '23 hours',auto_purge_at=now()+interval '23 hours'
  WHERE id=first_operation;
  SELECT * INTO result FROM public.project_due_trash_retention_team_attention(100);
  IF result.projected_count<>1 OR result.already_projected_count<>0 THEN
    RAISE EXCEPTION 'due projector did not create exactly one item';
  END IF;
  SELECT * INTO result FROM public.project_due_trash_retention_team_attention(100);
  IF result.projected_count<>0 OR result.already_projected_count<>1
     OR (SELECT count(*) FROM public.trash_retention_team_attention_items WHERE operation_id=first_operation)<>1 THEN
    RAISE EXCEPTION 'due projector replay duplicated the Team attention item';
  END IF;
  IF EXISTS (SELECT 1 FROM public.trash_retention_team_attention_items WHERE operation_id IN (second_operation,third_operation)) THEN
    RAISE EXCEPTION 'projector created an item outside the 24-hour window';
  END IF;

  SELECT * INTO result FROM public.get_trash_retention_team_attention(org,25);
  IF result.operation_id<>first_operation OR result.root_label<>'First retained document'
     OR result.scheduled_permanent_deletion_at IS NULL THEN
    RAISE EXCEPTION 'Owner Team attention projection was incomplete';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',associate_user::text,true);
  IF EXISTS (SELECT 1 FROM public.get_trash_retention_team_attention(org,25)) THEN
    RAISE EXCEPTION 'Associate received Owner/Admin Team attention content';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',owner::text,true);
  SELECT * INTO result FROM public.restore_trash_operation(first_operation,'retention.fixture.restore');
  IF result.code<>'restored'
     OR NOT EXISTS (
       SELECT 1 FROM public.trash_retention_team_attention_items item
       WHERE item.operation_id=first_operation AND item.state='resolved'
         AND item.resolution='source_restored' AND item.resolved_at IS NOT NULL
     ) OR EXISTS (SELECT 1 FROM public.get_trash_retention_team_attention(org,25)) THEN
    RAISE EXCEPTION 'restored source did not resolve and suppress Team attention';
  END IF;

  -- An elapsed schedule does not execute purge. The source remains intact and
  -- the projector has no permanent-delete authority.
  UPDATE public.trash_operations
  SET purge_eligible_at=now()-interval '1 minute',auto_purge_at=now()-interval '1 minute'
  WHERE id=second_operation;
  PERFORM public.project_due_trash_retention_team_attention(100);
  IF (SELECT state FROM public.trash_operations WHERE id=second_operation)<>'trashed'
     OR (SELECT record_state::text FROM public.documents WHERE id=second_document)<>'trashed' THEN
    RAISE EXCEPTION 'attention projector executed or changed permanent deletion';
  END IF;

  -- Simulate only the authoritative operation's future terminal transition to
  -- prove projection resolution. No resource row or storage object is deleted.
  UPDATE public.trash_operations
  SET purge_eligible_at=now()+interval '23 hours',auto_purge_at=now()+interval '23 hours'
  WHERE id=third_operation;
  PERFORM public.project_due_trash_retention_team_attention(100);
  IF NOT EXISTS (
    SELECT 1 FROM public.trash_retention_team_attention_items
    WHERE operation_id=third_operation AND state='active'
  ) THEN RAISE EXCEPTION 'purged-source attention setup was not projected'; END IF;
  UPDATE public.trash_operations
  SET state='purging',purge_started_at=now(),updated_at=now()
  WHERE id=third_operation;
  IF EXISTS (SELECT 1 FROM public.get_trash_retention_team_attention(org,25)) THEN
    RAISE EXCEPTION 'purging source remained visible in Team attention';
  END IF;
  UPDATE public.trash_operations
  SET state='purged',purged_at=now(),updated_at=now()
  WHERE id=third_operation;
  IF NOT EXISTS (
    SELECT 1 FROM public.trash_retention_team_attention_items item
    WHERE item.operation_id=third_operation AND item.state='resolved'
      AND item.resolution='source_purged' AND item.resolved_at IS NOT NULL
  ) THEN RAISE EXCEPTION 'purged source did not resolve Team attention'; END IF;

  IF has_table_privilege('authenticated','public.organisation_retention_settings','SELECT')
     OR has_table_privilege('authenticated','public.organisation_retention_settings','UPDATE')
     OR has_table_privilege('service_role','public.organisation_retention_settings','SELECT')
     OR has_table_privilege('service_role','public.organisation_retention_settings','UPDATE')
     OR has_table_privilege('authenticated','public.trash_retention_team_attention_items','SELECT')
     OR has_table_privilege('service_role','public.trash_retention_team_attention_items','INSERT') THEN
    RAISE EXCEPTION 'private retention table privilege leaked';
  END IF;
  IF has_function_privilege('service_role','public.get_organisation_trash_retention_policy(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.update_organisation_trash_retention_policy(uuid,integer,integer)','EXECUTE')
     OR has_function_privilege('service_role','public.get_trash_retention_team_attention(uuid,integer)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.project_due_trash_retention_team_attention(integer)','EXECUTE') THEN
    RAISE EXCEPTION 'retention RPC capability boundary is incorrect';
  END IF;
  SELECT count(*) INTO result FROM information_schema.columns
  WHERE table_schema='public' AND table_name='trash_retention_team_attention_items'
    AND column_name IN ('title','body','root_label','resource_name','storage_path','content');
  IF result.count<>0 THEN RAISE EXCEPTION 'durable attention projection stores content'; END IF;
END $fixture$;

-- Exercise actual role enforcement, not only grant introspection.
SET LOCAL ROLE authenticated;
DO $authenticated_denial$
DECLARE denied boolean:=false;
BEGIN
  BEGIN
    UPDATE public.organisation_retention_settings SET trash_retention_days=90;
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'authenticated direct policy update succeeded'; END IF;
END $authenticated_denial$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $service_denial$
DECLARE denied boolean:=false;
BEGIN
  BEGIN
    INSERT INTO public.trash_retention_team_attention_items(
      operation_id,org_id,available_at,scheduled_permanent_deletion_at
    ) VALUES(gen_random_uuid(),gen_random_uuid(),now(),now()+interval '24 hours');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'service role direct attention insert succeeded'; END IF;
END $service_denial$;
RESET ROLE;

ROLLBACK;
