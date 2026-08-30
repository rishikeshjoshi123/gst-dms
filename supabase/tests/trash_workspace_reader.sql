-- Run after a clean reset through migration 00085. Verifies the bounded Trash
-- workspace projection, root-only shape, selected hierarchy, and privileges.
BEGIN;

DO $fixture$
DECLARE
  org_a uuid := '85000000-0000-0000-0000-000000000001';
  org_b uuid := '85000000-0000-0000-0000-000000000002';
  admin_a uuid := '85100000-0000-0000-0000-000000000001';
  viewer_a uuid := '85100000-0000-0000-0000-000000000002';
  admin_b uuid := '85100000-0000-0000-0000-000000000003';
  client_a uuid := '85200000-0000-0000-0000-000000000001';
  client_b uuid := '85200000-0000-0000-0000-000000000002';
  matter_a uuid := '85300000-0000-0000-0000-000000000001';
  matter_b uuid := '85300000-0000-0000-0000-000000000002';
  document_a uuid := '85400000-0000-0000-0000-000000000001';
  document_b uuid := '85400000-0000-0000-0000-000000000002';
  owner_membership uuid;
  operation_a uuid;
  operation_b uuid;
  root_rows integer;
  child_rows integer;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES
    ('00000000-0000-0000-0000-000000000000',admin_a,'authenticated','authenticated','trash-workspace-admin-a@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',viewer_a,'authenticated','authenticated','trash-workspace-viewer-a@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',admin_b,'authenticated','authenticated','trash-workspace-admin-b@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.user_profiles(user_id,display_name) VALUES (admin_a,'Workspace Admin A'),(admin_b,'Workspace Admin B');
  INSERT INTO public.organisations(id,name,created_by) VALUES (org_a,'Workspace org A',admin_a),(org_b,'Workspace org B',admin_b);
  SELECT id INTO owner_membership FROM public.organisation_memberships WHERE org_id=org_a AND user_id=admin_a;
  UPDATE public.organisations SET owner_membership_id=owner_membership WHERE id=org_a;
  SELECT id INTO owner_membership FROM public.organisation_memberships WHERE org_id=org_b AND user_id=admin_b;
  UPDATE public.organisations SET owner_membership_id=owner_membership WHERE id=org_b;
  INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_by)
  VALUES (org_a,viewer_a,'viewer','active',1,admin_a);

  INSERT INTO public.clients(id,org_id,name) VALUES
    (client_a,org_a,'Alpha Client'),(client_b,org_b,'Beta Client');
  INSERT INTO public.matters(id,org_id,client_id,title,financial_year) VALUES
    (matter_a,org_a,client_a,'Alpha Appeal','2026-27'),
    (matter_b,org_b,client_b,'Beta Appeal','2026-27');
  INSERT INTO public.documents(id,org_id,matter_id,display_title,created_by) VALUES
    (document_a,org_a,matter_a,'Alpha evidence.pdf',admin_a),
    (document_b,org_b,matter_b,'Beta evidence.pdf',admin_b);

  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',admin_a::text,true);
  SELECT result.operation_id INTO operation_a
  FROM public.trash_resource('matter',matter_a,'fixture.workspace.a') AS result;
  PERFORM set_config('request.jwt.claim.sub',admin_b::text,true);
  SELECT result.operation_id INTO operation_b
  FROM public.trash_resource('matter',matter_b,'fixture.workspace.b') AS result;

  PERFORM set_config('request.jwt.claim.sub',admin_a::text,true);
  SELECT count(DISTINCT workspace.operation_id) INTO root_rows
  FROM public.get_trash_workspace(org_a,NULL,NULL,NULL,50) AS workspace
  WHERE workspace.row_kind='operation';
  IF root_rows <> 1 THEN RAISE EXCEPTION 'root-only tenant list shape failed'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.get_trash_workspace(org_a,NULL,NULL,NULL,50) AS workspace
    WHERE workspace.member_membership_id IS NOT NULL
  ) THEN RAISE EXCEPTION 'unselected descendant enumeration was exposed'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.get_trash_workspace(org_a,NULL,NULL,NULL,50) AS workspace
    WHERE workspace.operation_id=operation_b OR workspace.root_name ILIKE '%Beta%'
  ) THEN RAISE EXCEPTION 'cross-tenant operation was exposed'; END IF;

  SELECT count(*) INTO child_rows
  FROM public.get_trash_workspace(org_a,NULL,NULL,operation_a,50) AS workspace
  WHERE workspace.member_resource_type='document'
    AND workspace.member_resource_id=document_a
    AND workspace.member_parent_membership_id IS NOT NULL;
  IF child_rows <> 1 THEN RAISE EXCEPTION 'selected inherited tree containment failed'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.get_trash_workspace(org_a,NULL,NULL,operation_b,50) AS workspace
    WHERE workspace.member_membership_id IS NOT NULL
  ) THEN RAISE EXCEPTION 'forged foreign selected root enumerated descendants'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.get_trash_workspace(org_a,'Beta',NULL,NULL,50) AS workspace
    WHERE workspace.row_kind='operation'
  ) THEN RAISE EXCEPTION 'search crossed tenant boundary'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.get_trash_workspace(org_a,'%',NULL,NULL,50) AS workspace
    WHERE workspace.row_kind='operation'
  ) THEN RAISE EXCEPTION 'search treated wildcard input as a pattern'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.get_trash_workspace(org_a,NULL,'document',NULL,50) AS workspace
    WHERE workspace.row_kind='operation'
  ) THEN RAISE EXCEPTION 'root resource-type filter returned inherited documents'; END IF;

  -- Every active member may browse Trash; read access is not mutation authority.
  PERFORM set_config('request.jwt.claim.sub',viewer_a::text,true);
  IF NOT EXISTS (
    SELECT 1 FROM public.get_trash_workspace(org_a,'Alpha','matter',operation_a,50) AS workspace
    WHERE workspace.operation_id=operation_a
  ) THEN RAISE EXCEPTION 'active Viewer could not browse its organisation Trash'; END IF;

  -- A caller cannot switch to an organisation where they have no membership.
  IF EXISTS (SELECT 1 FROM public.get_trash_workspace(org_b,NULL,NULL,operation_b,50)) THEN
    RAISE EXCEPTION 'forged organisation was exposed';
  END IF;

  -- Once lifecycle leaves the readable states, neither root nor descendants
  -- remain in the operation projection.
  PERFORM set_config('request.jwt.claim.role','',true);
  UPDATE public.matters SET record_state='purging' WHERE id=matter_a;
  UPDATE public.documents SET record_state='purging' WHERE id=document_a;
  UPDATE public.resource_trash_memberships SET state='purging' WHERE operation_id=operation_a;
  UPDATE public.trash_operations SET state='purging',purge_started_at=now() WHERE id=operation_a;
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',admin_a::text,true);
  IF EXISTS (
    SELECT 1 FROM public.get_trash_workspace(org_a,NULL,NULL,operation_a,50) AS workspace
    WHERE workspace.row_kind='operation'
  ) THEN RAISE EXCEPTION 'purging operation remained browsable'; END IF;
END $fixture$;

DO $privileges$
BEGIN
  IF has_function_privilege('anon','public.get_trash_workspace(uuid,text,public.trash_resource_type,uuid,integer)','EXECUTE')
     OR has_function_privilege('service_role','public.get_trash_workspace(uuid,text,public.trash_resource_type,uuid,integer)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.get_trash_workspace(uuid,text,public.trash_resource_type,uuid,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'Trash workspace function privileges are unsafe';
  END IF;
  IF has_table_privilege('authenticated','public.trash_operations','SELECT')
     OR has_table_privilege('authenticated','public.resource_trash_memberships','SELECT') THEN
    RAISE EXCEPTION 'private Trash table grant was introduced';
  END IF;
END $privileges$;

ROLLBACK;
