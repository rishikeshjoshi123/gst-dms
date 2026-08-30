-- Run after a clean reset through migration 00084. Verifies that the private
-- Trash context reader is tenant-, lineage-, membership-, and role-safe.
BEGIN;

DO $fixture$
DECLARE
  org uuid := '84000000-0000-0000-0000-000000000001';
  other_org uuid := '84000000-0000-0000-0000-000000000002';
  admin uuid := '84100000-0000-0000-0000-000000000001';
  associate uuid := '84100000-0000-0000-0000-000000000002';
  viewer uuid := '84100000-0000-0000-0000-000000000003';
  other_admin uuid := '84100000-0000-0000-0000-000000000004';
  client uuid := '84200000-0000-0000-0000-000000000001';
  matter uuid := '84300000-0000-0000-0000-000000000001';
  direct_document uuid := '84400000-0000-0000-0000-000000000001';
  inherited_document uuid := '84400000-0000-0000-0000-000000000002';
  wrong_matter uuid := '84300000-0000-0000-0000-000000000002';
  membership uuid;
  context record;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES
    ('00000000-0000-0000-0000-000000000000',admin,'authenticated','authenticated','reader-admin@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',associate,'authenticated','authenticated','reader-associate@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',viewer,'authenticated','authenticated','reader-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',other_admin,'authenticated','authenticated','reader-other@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES (org,'Reader fixture',admin),(other_org,'Other reader fixture',other_admin);
  SELECT id INTO membership FROM public.organisation_memberships WHERE org_id=org AND user_id=admin;
  UPDATE public.organisations SET owner_membership_id=membership WHERE id=org;
  INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_by)
  VALUES (org,associate,'associate','active',1,admin),(org,viewer,'viewer','active',1,admin);
  INSERT INTO public.clients(id,org_id,name) VALUES (client,org,'Reader client');
  INSERT INTO public.matters(id,org_id,client_id,title,financial_year) VALUES
    (matter,org,client,'Reader matter','2026-27'),
    (wrong_matter,org,client,'Wrong route matter','2025-26');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by) VALUES
    (direct_document,org,matter,'fixture/direct-reader.pdf',associate),
    (inherited_document,org,matter,'fixture/inherited-reader.pdf',admin);

  PERFORM set_config('request.jwt.claim.sub',associate::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM public.trash_resource('document',direct_document,'fixture.reader.direct');
  SELECT * INTO context FROM public.get_exact_resource_trash_context('document',direct_document,matter);
  IF context.cause <> 'direct' OR NOT context.can_restore THEN
    RAISE EXCEPTION 'associate direct-document restore display policy failed';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',admin::text,true);
  PERFORM public.trash_resource('matter',matter,'fixture.reader.matter');
  SELECT * INTO context FROM public.get_exact_resource_trash_context('document',inherited_document,matter);
  IF context.cause <> 'inherited' OR context.root_resource_type <> 'matter' OR context.root_resource_id <> matter OR NOT context.can_restore THEN
    RAISE EXCEPTION 'admin inherited Trash context failed';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',associate::text,true);
  SELECT * INTO context FROM public.get_exact_resource_trash_context('document',inherited_document,matter);
  IF context.can_restore THEN RAISE EXCEPTION 'associate inherited document received restore hint'; END IF;
  IF EXISTS (SELECT 1 FROM public.get_exact_resource_trash_context('document',inherited_document,wrong_matter)) THEN
    RAISE EXCEPTION 'forged document/matter lineage was disclosed';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
  SELECT * INTO context FROM public.get_exact_resource_trash_context('matter',matter,NULL);
  IF context.can_restore THEN RAISE EXCEPTION 'viewer received restore hint'; END IF;

  -- A scheduled purge has not started: the normal route can still receive a
  -- read-only Trash context with the retention/scheduling status it needs.
  PERFORM set_config('request.jwt.claim.sub',admin::text,true);
  UPDATE public.trash_operations
  SET state='purge_scheduled', purge_scheduled_at=now()
  WHERE id=context.operation_id;
  SELECT * INTO context FROM public.get_exact_resource_trash_context('matter',matter,NULL);
  IF context.operation_state <> 'purge_scheduled' OR context.purge_scheduled_at IS NULL THEN
    RAISE EXCEPTION 'scheduled purge was not exposed as a read-only Trash context';
  END IF;

  -- Once purge starts, the operation and every member leave the readable
  -- Trash context; a terminal state must not be exposed either.
  PERFORM set_config('request.jwt.claim.role','',true);
  UPDATE public.resource_trash_memberships SET state='purging'
  WHERE operation_id=context.operation_id;
  UPDATE public.trash_operations SET state='purging', purge_started_at=now()
  WHERE id=context.operation_id;
  IF EXISTS (SELECT 1 FROM public.get_exact_resource_trash_context('matter',matter,NULL)) THEN
    RAISE EXCEPTION 'purging operation was exposed as readable Trash context';
  END IF;
  UPDATE public.resource_trash_memberships SET state='purged', purged_at=now()
  WHERE operation_id=context.operation_id;
  UPDATE public.matters SET record_state='purged', active_trash_membership_id=NULL WHERE id=matter;
  UPDATE public.documents SET record_state='purged', active_trash_membership_id=NULL WHERE matter_id=matter;
  UPDATE public.trash_operations SET state='purged', purged_at=now() WHERE id=context.operation_id;
  IF EXISTS (SELECT 1 FROM public.get_exact_resource_trash_context('matter',matter,NULL)) THEN
    RAISE EXCEPTION 'purged operation was exposed as readable Trash context';
  END IF;

  PERFORM set_config('request.jwt.claim.sub',other_admin::text,true);
  IF EXISTS (SELECT 1 FROM public.get_exact_resource_trash_context('matter',matter,NULL)) THEN
    RAISE EXCEPTION 'cross-tenant Trash context was disclosed';
  END IF;
END $fixture$;

ROLLBACK;
