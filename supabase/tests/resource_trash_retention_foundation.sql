-- Run after 00079 against a disposable local Supabase database.
-- This validates the prerequisite contract only; no delete/restore/purge
-- command or user-facing workflow is claimed here.
BEGIN;

DO $fixture$
DECLARE
  org_a uuid := '79000000-0000-0000-0000-000000000001';
  org_b uuid := '79000000-0000-0000-0000-000000000002';
  user_a uuid := '79100000-0000-0000-0000-000000000001';
  user_b uuid := '79100000-0000-0000-0000-000000000002';
  client_a uuid := '79200000-0000-0000-0000-000000000001';
  client_b uuid := '79200000-0000-0000-0000-000000000002';
  legacy_client uuid := '79200000-0000-0000-0000-000000000003';
  legacy_action_client uuid := '79200000-0000-0000-0000-000000000004';
  matter_a uuid := '79300000-0000-0000-0000-000000000001';
  document_a uuid := '79400000-0000-0000-0000-000000000001';
  operation_a uuid := '79500000-0000-0000-0000-000000000001';
  operation_b uuid := '79500000-0000-0000-0000-000000000002';
  member_client uuid := '79600000-0000-0000-0000-000000000001';
  member_matter uuid := '79600000-0000-0000-0000-000000000002';
  member_document uuid := '79600000-0000-0000-0000-000000000003';
  failed boolean;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
    ('00000000-0000-0000-0000-000000000000',user_a,'authenticated','authenticated','trash-a@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',user_b,'authenticated','authenticated','trash-b@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES (org_a,'Trash A',user_a),(org_b,'Trash B',user_b);
  INSERT INTO public.clients(id,org_id,name) VALUES
    (client_a,org_a,'Client A'),(client_b,org_b,'Client B'),
    (legacy_client,org_a,'Legacy historical client'),(legacy_action_client,org_a,'Legacy action client');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES (matter_a,org_a,client_a,'Matter A');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by) VALUES (document_a,org_a,matter_a,'legacy/trash-a.pdf',user_a);

  -- Existing retained soft-deleted records remain representable without a
  -- forged operation until the later synthetic-operation migration.
  UPDATE public.clients SET deleted_at=now(), record_state='trashed' WHERE id=legacy_client;
  IF (SELECT record_state FROM public.clients WHERE id=legacy_client) <> 'trashed'
     OR (SELECT active_trash_membership_id FROM public.clients WHERE id=legacy_client) IS NOT NULL THEN
    RAISE EXCEPTION 'legacy soft-deleted client compatibility failed';
  END IF;
  -- Existing delete callers have not cut over yet. A deleted_at-only action
  -- remains valid and cannot masquerade as a trash membership.
  UPDATE public.clients SET deleted_at=now() WHERE id=legacy_action_client;
  IF (SELECT record_state FROM public.clients WHERE id=legacy_action_client) <> 'active'
     OR (SELECT active_trash_membership_id FROM public.clients WHERE id=legacy_action_client) IS NOT NULL THEN
    RAISE EXCEPTION 'legacy deleted_at-only action compatibility failed';
  END IF;
  IF (SELECT record_state FROM public.documents WHERE id=document_a) <> 'active' THEN
    RAISE EXCEPTION 'active documents must remain valid after the foundation migration';
  END IF;

  INSERT INTO public.organisation_retention_settings(org_id) VALUES (org_a);
  IF NOT EXISTS (SELECT 1 FROM public.organisation_retention_settings
    WHERE org_id=org_a AND trash_retention_mode='manual_only' AND trash_retention_days IS NULL
      AND NOT auto_purge_enabled AND policy_version=1) THEN
    RAISE EXCEPTION 'manual-only retention default is not deliberate';
  END IF;

  -- Build one valid Client -> Matter -> Document operation atomically.
  INSERT INTO public.trash_operations(id,org_id,root_resource_type,root_resource_id,root_client_id,actor_user_id)
    VALUES(operation_a,org_a,'client',client_a,client_a,user_a);
  INSERT INTO public.resource_trash_memberships(id,org_id,operation_id,resource_type,resource_id,client_id,cause)
    VALUES(member_client,org_a,operation_a,'client',client_a,client_a,'direct');
  INSERT INTO public.resource_trash_memberships(id,org_id,operation_id,resource_type,resource_id,matter_id,parent_membership_id,cause)
    VALUES(member_matter,org_a,operation_a,'matter',matter_a,matter_a,member_client,'inherited');
  INSERT INTO public.resource_trash_memberships(id,org_id,operation_id,resource_type,resource_id,document_id,parent_membership_id,cause)
    VALUES(member_document,org_a,operation_a,'document',document_a,document_a,member_matter,'inherited');
  UPDATE public.clients SET deleted_at=now(),record_state='trashed',active_trash_membership_id=member_client WHERE id=client_a;
  UPDATE public.matters SET deleted_at=now(),record_state='trashed',active_trash_membership_id=member_matter WHERE id=matter_a;
  UPDATE public.documents SET deleted_at=now(),trashed_at=now(),record_state='trashed',active_trash_membership_id=member_document WHERE id=document_a;
  SET CONSTRAINTS ALL IMMEDIATE;

  -- Cross-tenant resource association cannot be forged through polymorphic IDs.
  failed:=false; BEGIN
    INSERT INTO public.trash_operations(org_id,root_resource_type,root_resource_id,root_client_id)
      VALUES(org_b,'client',client_a,client_a);
  EXCEPTION WHEN foreign_key_violation THEN failed:=true; END;
  IF NOT failed THEN RAISE EXCEPTION 'cross-org operation root accepted'; END IF;
  failed:=false; BEGIN
    INSERT INTO public.resource_holds(org_id,resource_type,resource_id,client_id,reason)
      VALUES(org_b,'client',client_a,client_a,'forged cross-org hold');
  EXCEPTION WHEN foreign_key_violation THEN failed:=true; END;
  IF NOT failed THEN RAISE EXCEPTION 'cross-org hold locator accepted'; END IF;

  -- A resource type cannot be paired with the wrong typed FK, and a resource
  -- cannot have a second active membership across operations.
  failed:=false; BEGIN
    INSERT INTO public.resource_trash_memberships(org_id,operation_id,resource_type,resource_id,client_id,cause)
      VALUES(org_a,operation_a,'matter',matter_a,client_a,'direct');
  EXCEPTION WHEN check_violation THEN failed:=true; END;
  IF NOT failed THEN RAISE EXCEPTION 'wrong resource-type locator accepted'; END IF;
  INSERT INTO public.trash_operations(id,org_id,root_resource_type,root_resource_id,root_document_id)
    VALUES(operation_b,org_a,'document',document_a,document_a);
  failed:=false; BEGIN
    INSERT INTO public.resource_trash_memberships(org_id,operation_id,resource_type,resource_id,document_id,cause)
      VALUES(org_a,operation_b,'document',document_a,document_a,'direct');
  EXCEPTION WHEN unique_violation THEN failed:=true; END;
  IF NOT failed THEN RAISE EXCEPTION 'duplicate active membership accepted'; END IF;
  DELETE FROM public.trash_operations WHERE id=operation_b;

  -- A membership-only mutation cannot leave the root operation in its prior
  -- lifecycle state, even when every affected resource is changed to match.
  failed:=false; BEGIN
    SET CONSTRAINTS ALL DEFERRED;
    UPDATE public.resource_trash_memberships SET state='purging'
      WHERE id IN (member_client,member_matter,member_document);
    UPDATE public.clients SET record_state='purging' WHERE id=client_a;
    UPDATE public.matters SET record_state='purging' WHERE id=matter_a;
    UPDATE public.documents SET record_state='purging' WHERE id=document_a;
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN raise_exception THEN failed:=true; END;
  IF NOT failed THEN RAISE EXCEPTION 'membership-only lifecycle drift from operation accepted'; END IF;

  -- An inherited child cannot outlive, or be in a different lifecycle state
  -- from, its parent membership.
  failed:=false; BEGIN
    UPDATE public.resource_trash_memberships SET state='restoring' WHERE id=member_matter;
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN raise_exception THEN failed:=true; END;
  IF NOT failed THEN RAISE EXCEPTION 'inherited membership accepted an inactive parent'; END IF;
  failed:=false; BEGIN
    UPDATE public.resource_trash_memberships SET parent_membership_id=member_client WHERE id=member_document;
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN raise_exception THEN failed:=true; END;
  IF NOT failed THEN RAISE EXCEPTION 'inherited document accepted a non-matter parent'; END IF;

  -- A later purge command can reach the intended terminal representation:
  -- terminal memberships remain historical while resources no longer expose
  -- an active-membership reference.
  SET CONSTRAINTS ALL DEFERRED;
  UPDATE public.trash_operations SET state='purging',purge_started_at=now() WHERE id=operation_a;
  UPDATE public.resource_trash_memberships SET state='purging' WHERE id IN (member_client,member_matter,member_document);
  UPDATE public.clients SET record_state='purging' WHERE id=client_a;
  UPDATE public.matters SET record_state='purging' WHERE id=matter_a;
  UPDATE public.documents SET record_state='purging' WHERE id=document_a;
  UPDATE public.trash_operations SET state='purged',purged_at=now() WHERE id=operation_a;
  UPDATE public.resource_trash_memberships SET state='purged',purged_at=now() WHERE id IN (member_client,member_matter,member_document);
  UPDATE public.clients SET record_state='purged',active_trash_membership_id=NULL WHERE id=client_a;
  UPDATE public.matters SET record_state='purged',active_trash_membership_id=NULL WHERE id=matter_a;
  UPDATE public.documents SET record_state='purged',active_trash_membership_id=NULL WHERE id=document_a;
  SET CONSTRAINTS ALL IMMEDIATE;
  IF EXISTS (SELECT 1 FROM public.resource_trash_memberships WHERE operation_id=operation_a AND state<>'purged')
     OR EXISTS (SELECT 1 FROM public.clients WHERE id=client_a AND (record_state<>'purged' OR active_trash_membership_id IS NOT NULL)) THEN
    RAISE EXCEPTION 'purged terminal contract is not representable';
  END IF;
  failed:=false; BEGIN
    UPDATE public.trash_operations SET state='restored',restored_at=now() WHERE id=operation_a;
  EXCEPTION WHEN raise_exception THEN failed:=true; END;
  IF NOT failed THEN RAISE EXCEPTION 'terminal operation transition accepted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='trash_operation_state')
     OR NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid WHERE t.typname='document_record_state' AND e.enumlabel='purged') THEN
    RAISE EXCEPTION 'typed trash state contract missing';
  END IF;
  IF NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.trash_operations'::regclass)
     OR NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.resource_trash_memberships'::regclass) THEN
    RAISE EXCEPTION 'private trash-table RLS force missing';
  END IF;
  IF has_table_privilege('anon','public.trash_operations','SELECT')
     OR has_table_privilege('authenticated','public.resource_holds','INSERT')
     OR has_table_privilege('service_role','public.resource_trash_memberships','UPDATE')
     OR has_function_privilege('service_role','public.assert_resource_trash_contract()','EXECUTE') THEN
    RAISE EXCEPTION 'trash private grant surface leaked';
  END IF;
END $fixture$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '79100000-0000-0000-0000-000000000001';
SET LOCAL request.jwt.claim.role = 'authenticated';
DO $authenticated_insert_denial$
DECLARE denied boolean:=false;
BEGIN
  BEGIN
    INSERT INTO public.clients(id,org_id,name,record_state)
      VALUES ('79200000-0000-0000-0000-000000000099','79000000-0000-0000-0000-000000000001','Forged trashed client','trashed');
  EXCEPTION WHEN raise_exception THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'authenticated caller inserted a forged trash resource state'; END IF;
END $authenticated_insert_denial$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $service_role_denial$
DECLARE denied boolean:=false;
BEGIN
  BEGIN
    SELECT 1 FROM public.trash_operations LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'service role direct trash read allowed'; END IF;

  denied:=false;
  BEGIN
    INSERT INTO public.clients(id,org_id,name,deleted_at,record_state)
      VALUES ('79200000-0000-0000-0000-000000000098','79000000-0000-0000-0000-000000000001',
        'Forged service trashed client',now(),'trashed');
  EXCEPTION WHEN raise_exception THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'service role inserted a forged trash resource state'; END IF;

  denied:=false;
  BEGIN
    UPDATE public.clients SET record_state='trashed'
    WHERE id='79200000-0000-0000-0000-000000000004';
  EXCEPTION WHEN raise_exception THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'service role updated a forged trash resource state'; END IF;
END $service_role_denial$;
RESET ROLE;

ROLLBACK;
