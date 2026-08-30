-- Run after a clean reset through migration 00080 against a disposable local database.
-- Covers command authority, hierarchy, replay, tenant forgery, exclusion, and
-- direct-write denial. The concurrent race companion is intentionally a shell
-- harness concern because it needs two database sessions.
BEGIN;

DO $fixture$
DECLARE
  org uuid := '80000000-0000-0000-0000-000000000001';
  other_org uuid := '80000000-0000-0000-0000-000000000002';
  admin uuid := '80100000-0000-0000-0000-000000000001';
  associate uuid := '80100000-0000-0000-0000-000000000002';
  viewer uuid := '80100000-0000-0000-0000-000000000003';
  other_admin uuid := '80100000-0000-0000-0000-000000000004';
  client uuid := '80200000-0000-0000-0000-000000000001';
  matter uuid := '80300000-0000-0000-0000-000000000001';
  doc uuid := '80400000-0000-0000-0000-000000000001';
  hierarchy_client uuid := '80200000-0000-0000-0000-000000000002';
  hierarchy_matter uuid := '80300000-0000-0000-0000-000000000002';
  hierarchy_doc uuid := '80400000-0000-0000-0000-000000000002';
  pretrashed_doc uuid := '80400000-0000-0000-0000-000000000003';
  other_client uuid := '80200000-0000-0000-0000-000000000003';
  other_matter uuid := '80300000-0000-0000-0000-000000000003';
  other_doc uuid := '80400000-0000-0000-0000-000000000004';
  membership uuid;
  result record;
  activity_count integer;
  outbox_count integer;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES
    ('00000000-0000-0000-0000-000000000000',admin,'authenticated','authenticated','trash-admin@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',associate,'authenticated','authenticated','trash-associate@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',viewer,'authenticated','authenticated','trash-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',other_admin,'authenticated','authenticated','trash-other@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES (org,'Trash fixture',admin),(other_org,'Other Trash fixture',other_admin);
  SELECT id INTO membership FROM public.organisation_memberships WHERE org_id=org AND user_id=admin AND state='active';
  UPDATE public.organisations SET owner_membership_id=membership WHERE id=org;
  SELECT id INTO membership FROM public.organisation_memberships WHERE org_id=other_org AND user_id=other_admin AND state='active';
  UPDATE public.organisations SET owner_membership_id=membership WHERE id=other_org;
  INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_by)
  VALUES (org,associate,'associate','active',1,admin),(org,viewer,'viewer','active',1,admin);

  INSERT INTO public.clients(id,org_id,name) VALUES (client,org,'Direct'),(hierarchy_client,org,'Hierarchy'),(other_client,other_org,'Other');
  INSERT INTO public.matters(id,org_id,client_id,title,financial_year) VALUES
    (matter,org,client,'Direct matter','2026-27'),
    (hierarchy_matter,org,hierarchy_client,'Hierarchy matter','2026-27'),
    (other_matter,other_org,other_client,'Other matter','2026-27');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by) VALUES
    (doc,org,matter,'fixture/direct.pdf',admin),
    (hierarchy_doc,org,hierarchy_matter,'fixture/hierarchy.pdf',admin),
    (pretrashed_doc,org,hierarchy_matter,'fixture/preexisting.pdf',admin),
    (other_doc,other_org,other_matter,'fixture/other.pdf',other_admin);

  -- Associate can trash only an individual document in an accessible active
  -- matter. The same key returns the original operation and one activity/outbox.
  PERFORM set_config('request.jwt.claim.sub',associate::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  SELECT * INTO result FROM public.trash_resource('document',doc,'fixture.associate.doc');
  IF result.code <> 'trashed' OR result.included_document_count <> 1 THEN RAISE EXCEPTION 'associate document trash failed'; END IF;
  SELECT * INTO result FROM public.trash_resource('document',doc,'fixture.associate.doc');
  IF result.code <> 'already_trashed' THEN RAISE EXCEPTION 'duplicate retry did not return original result'; END IF;
  SELECT count(*) INTO activity_count FROM public.activity_logs WHERE org_id=org AND action='resource_trashed' AND entity_id=doc;
  SELECT count(*) INTO outbox_count FROM public.outbox_events WHERE org_id=org AND aggregate_id=result.operation_id;
  IF activity_count<>1 OR outbox_count<>1 THEN RAISE EXCEPTION 'retry duplicated activity or outbox'; END IF;
  SELECT * INTO result FROM public.trash_resource('matter',matter,'fixture.associate.matter');
  IF result.code <> 'not_allowed' THEN RAISE EXCEPTION 'associate received hierarchy trash'; END IF;

  -- A previous direct document operation remains untouched when its client is
  -- trashed later; only active descendants join the new operation.
  PERFORM set_config('request.jwt.claim.sub',admin::text,true);
  SELECT * INTO result FROM public.trash_resource('document',pretrashed_doc,'fixture.preexisting.doc');
  IF result.code <> 'trashed' THEN RAISE EXCEPTION 'pre-existing document setup failed'; END IF;
  SELECT * INTO result FROM public.trash_resource('client',hierarchy_client,'fixture.client');
  IF result.code <> 'trashed' OR result.included_client_count<>1 OR result.included_matter_count<>1
     OR result.included_document_count<>1 OR result.preexisting_trashed_descendant_count<>1 THEN
    RAISE EXCEPTION 'client hierarchy or pre-existing exclusion failed';
  END IF;
  IF (SELECT operation_id FROM public.resource_trash_memberships WHERE resource_id=pretrashed_doc AND state='active') = result.operation_id THEN
    RAISE EXCEPTION 'independently trashed descendant was adopted';
  END IF;
  SELECT * INTO result FROM public.trash_resource('document',hierarchy_doc,'fixture.client');
  IF result.code <> 'idempotency_conflict' THEN RAISE EXCEPTION 'same key was leaked to a different subject'; END IF;
  SELECT * INTO result FROM public.trash_resource('document',other_doc,'fixture.forged.other-org');
  IF result.code <> 'not_allowed' THEN RAISE EXCEPTION 'cross-organisation forged id was accepted'; END IF;

  PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
  SELECT * INTO result FROM public.trash_resource('document',other_doc,'fixture.viewer');
  IF result.code <> 'not_allowed' THEN RAISE EXCEPTION 'viewer received document trash'; END IF;
END $fixture$;

-- The table guard must reject an authenticated direct update and a service
-- update even when each forges the legacy marker value first. Legitimate RPC
-- success was proved above without relying on that marker.
SELECT set_config('request.jwt.claim.sub','80100000-0000-0000-0000-000000000001',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('casechain.resource_trash_command','authorised',true);
SET LOCAL ROLE authenticated;
DO $direct_authenticated_write$
DECLARE blocked boolean := false;
BEGIN
  BEGIN
    UPDATE public.clients SET record_state='trashed' WHERE id='80200000-0000-0000-0000-000000000001';
  EXCEPTION WHEN raise_exception THEN
    blocked := SQLERRM = 'trash resource state is writable only through a service-owned command';
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'direct authenticated state write was not denied'; END IF;
END $direct_authenticated_write$;
RESET ROLE;

SELECT set_config('casechain.resource_trash_command','authorised',true);
SET LOCAL ROLE service_role;
DO $direct_service_write$
DECLARE blocked boolean := false;
BEGIN
  BEGIN
    UPDATE public.clients SET record_state='trashed' WHERE id='80200000-0000-0000-0000-000000000001';
  EXCEPTION WHEN raise_exception THEN
    blocked := SQLERRM = 'trash resource state is writable only through a service-owned command';
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'direct service state write was not denied'; END IF;
END $direct_service_write$;
RESET ROLE;

ROLLBACK;
