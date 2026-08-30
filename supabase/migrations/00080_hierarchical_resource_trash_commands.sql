-- Transactional, hierarchy-aware Trash commands.
--
-- This is deliberately limited to the live trash transition. Restore, purge,
-- dependent-domain suspension, and Trash UI remain separate slices.
BEGIN;

-- Keep the authorisation vocabulary in the one canonical capability matrix.
-- Associates receive only an individual document command; hierarchy roots stay
-- an Owner/Admin operation.
CREATE OR REPLACE FUNCTION public.organisation_member_capabilities(
  p_role public.org_member_role,
  p_is_owner boolean,
  p_state public.organisation_membership_state
)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT CASE
    WHEN p_state <> 'active' THEN ARRAY[]::text[]
    WHEN p_is_owner THEN ARRAY[
      'team.view','team.invite.standard','team.role.manage_standard',
      'team.membership.suspend_standard','organisation.profile.manage',
      'organisation.operations.manage','team.invite.admin','team.role.manage_admin',
      'team.membership.manage_admin','team.ownership.transfer','trash.purge',
      'document.view','document.intake.create','document.record.create',
      'document.intake.assign','document.intake.discard','document.version.attach',
      'document.version.replace','document.reprocess','document.metadata.decide',
      'trash.document','trash.hierarchy'
    ]::text[]
    WHEN p_role='admin' THEN ARRAY[
      'team.view','team.invite.standard','team.role.manage_standard',
      'team.membership.suspend_standard','organisation.profile.manage',
      'organisation.operations.manage','trash.purge','document.view',
      'document.intake.create','document.record.create','document.intake.assign',
      'document.intake.discard','document.version.attach','document.version.replace',
      'document.reprocess','document.metadata.decide','trash.document','trash.hierarchy'
    ]::text[]
    WHEN p_role='associate' THEN ARRAY[
      'team.view','document.view','document.intake.create','document.record.create',
      'document.intake.assign','document.intake.discard','document.version.attach',
      'document.version.replace','document.reprocess','document.metadata.decide',
      'trash.document'
    ]::text[]
    ELSE ARRAY['team.view','document.view']::text[] END
$$;

CREATE OR REPLACE FUNCTION public.get_my_organisation_context()
RETURNS TABLE (membership_id uuid, org_id uuid, role public.org_member_role,
  is_owner boolean, state public.organisation_membership_state,
  capability_version integer, capabilities text[], revision bigint)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
  SELECT m.id,m.org_id,m.role,(o.owner_membership_id=m.id),m.state,7,
    public.organisation_member_capabilities(m.role,o.owner_membership_id=m.id,m.state),m.revision
  FROM public.organisation_memberships AS m
  JOIN public.organisations AS o ON o.id=m.org_id
  WHERE m.user_id=auth.uid() AND m.state IN ('active','suspended')
$$;

-- The foundation reserved an organisation-wide key. A command key belongs to
-- its authenticated actor as well as its subject, so independent users cannot
-- collide and a reuse is still bound to the immutable root below.
DROP INDEX public.trash_operations_org_idempotency_key_unique;
CREATE UNIQUE INDEX trash_operations_org_actor_idempotency_key_unique
  ON public.trash_operations(org_id, actor_user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- The dispatch table is a strict identifier-only envelope. A trash event is
-- durable intent for later domain workers; it contains no names or content.
CREATE OR REPLACE FUNCTION public.document_lifecycle_outbox_envelope_is_safe(
  p_event_kind text,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_payload jsonb
) RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  WITH contract(event_kind, aggregate_type, identifier_key, expected_keys) AS (
    VALUES
      ('document.upload_reserved.v1', 'document_upload', 'session_id', ARRAY['session_id', 'intake_id', 'asset_id']::text[]),
      ('document.upload_validation_requested.v1', 'document_upload', 'session_id', ARRAY['session_id', 'intake_id', 'asset_id']::text[]),
      ('document.upload_duplicate.v1', 'document_upload', 'session_id', ARRAY['session_id', 'intake_id']::text[]),
      ('document.upload_failed.v1', 'document_upload', 'session_id', ARRAY['session_id', 'intake_id', 'error_code']::text[]),
      ('document.upload_expired.v1', 'document_upload', 'session_id', ARRAY['session_id']::text[]),
      ('document.intake_validated.v1', 'document', 'intake_id', ARRAY['intake_id', 'asset_id', 'result_code']::text[]),
      ('document.intake_validation_failed.v1', 'document', 'intake_id', ARRAY['intake_id', 'asset_id', 'result_code']::text[]),
      ('document.metadata_created.v1', 'document', 'document_id', ARRAY['document_id', 'matter_id']::text[]),
      ('document.processing_requested.v1', 'document', 'document_id', ARRAY['document_id', 'version_id', 'intake_id']::text[]),
      ('document.reprocess_requested.v1', 'document', 'document_id', ARRAY['document_id', 'version_id', 'scope']::text[]),
      ('intake.assigned.v1', 'document', 'intake_id', ARRAY['intake_id', 'document_id', 'document_version_id']::text[]),
      ('intake.discarded.v1', 'document', 'intake_id', ARRAY['intake_id', 'result_code']::text[]),
      ('trash.operation_created.v1', 'trash_operation', 'operation_id', ARRAY['operation_id', 'root_resource_id', 'root_resource_type']::text[])
  )
  SELECT COALESCE((
    SELECT p_event_kind IS NOT NULL
      AND p_aggregate_type = c.aggregate_type
      AND p_aggregate_id IS NOT NULL
      AND jsonb_typeof(p_payload) = 'object'
      AND p_aggregate_id::text = p_payload ->> c.identifier_key
      AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p_payload) AS key WHERE NOT key = ANY(c.expected_keys))
      AND NOT EXISTS (
        SELECT 1 FROM unnest(c.expected_keys) AS key
        WHERE NOT p_payload ? key OR jsonb_typeof(p_payload -> key) <> 'string'
          OR char_length(p_payload ->> key) NOT BETWEEN 1 AND 128
      )
      AND NOT EXISTS (
        SELECT 1 FROM unnest(ARRAY['session_id','intake_id','asset_id','document_id','matter_id','version_id','document_version_id','operation_id','root_resource_id']::text[]) AS key
        WHERE p_payload ? key AND p_payload ->> key !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      )
      AND (NOT p_payload ? 'scope' OR p_payload ->> 'scope' IN ('extract','ocr','relationships','search_index','full'))
      AND (NOT p_payload ? 'root_resource_type' OR p_payload ->> 'root_resource_type' IN ('client','matter','document'))
      AND (NOT p_payload ? 'error_code' OR p_payload ->> 'error_code' IN ('upload_failed','invalid_pdf','malware_suspect','storage_missing','validation_failed','upload_rejected'))
      AND (NOT p_payload ? 'result_code' OR p_payload ->> 'result_code' IN ('ok','already_ready','not_available','invalid_pdf','encrypted_pdf','malware_suspect','storage_missing','validation_failed','discarded'))
    FROM contract AS c WHERE c.event_kind = p_event_kind
  ), false)
$$;

-- The foundation's protection trigger correctly rejects every direct browser
-- or service-table state edit. Do not use a custom GUC here: service_role can
-- set one before issuing direct DML. Trigger SQL executed by trash_resource's
-- SECURITY DEFINER body retains that function owner's current_user; direct
-- authenticated/service_role DML does not. SECURITY INVOKER is intentional.
CREATE OR REPLACE FUNCTION public.resource_trash_protected_state_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF (NEW.record_state IS DISTINCT FROM OLD.record_state
      OR NEW.active_trash_membership_id IS DISTINCT FROM OLD.active_trash_membership_id)
     AND current_user <> pg_catalog.pg_get_userbyid(
       (SELECT proc.proowner FROM pg_catalog.pg_proc AS proc
        WHERE proc.oid = 'public.trash_resource(public.trash_resource_type,uuid,text)'::regprocedure)
     ) THEN
    RAISE EXCEPTION 'trash resource state is writable only through a service-owned command';
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.trash_resource(
  p_resource_type public.trash_resource_type,
  p_resource_id uuid,
  p_idempotency_key text
)
RETURNS TABLE(
  code text,
  operation_id uuid,
  included_client_count integer,
  included_matter_count integer,
  included_document_count integer,
  preexisting_trashed_descendant_count integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  root_client public.clients%ROWTYPE;
  root_matter public.matters%ROWTYPE;
  root_document public.documents%ROWTYPE;
  actor record;
  prior public.trash_operations%ROWTYPE;
  v_operation_id uuid;
  v_root_org_id uuid;
  v_clients integer := 0;
  v_matters integer := 0;
  v_documents integer := 0;
  v_excluded integer := 0;
  v_client_membership uuid;
  v_matter_membership uuid;
  v_document_membership uuid;
  descendant record;
BEGIN
  IF p_resource_type IS NULL OR p_resource_id IS NULL OR p_idempotency_key IS NULL
     OR p_idempotency_key !~ '^[a-z][a-z0-9_.:-]{0,127}$' THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,0,0,0,0;
    RETURN;
  END IF;

  -- Resolve and lock the requested subject before examining caller state. The
  -- response is deliberately non-disclosing for an absent or foreign ID.
  IF p_resource_type = 'client' THEN
    SELECT * INTO root_client FROM public.clients WHERE id=p_resource_id;
    IF root_client.id IS NULL THEN
      RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN;
    END IF;
    v_root_org_id := root_client.org_id;
  ELSIF p_resource_type = 'matter' THEN
    SELECT * INTO root_matter FROM public.matters WHERE id=p_resource_id;
    IF root_matter.id IS NULL THEN
      RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN;
    END IF;
    SELECT * INTO root_client FROM public.clients WHERE id=root_matter.client_id AND org_id=root_matter.org_id;
    IF root_client.id IS NULL THEN
      RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN;
    END IF;
    v_root_org_id := root_matter.org_id;
  ELSE
    SELECT * INTO root_document FROM public.documents WHERE id=p_resource_id;
    IF root_document.id IS NULL THEN
      RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN;
    END IF;
    SELECT * INTO root_matter FROM public.matters WHERE id=root_document.matter_id AND org_id=root_document.org_id;
    SELECT * INTO root_client FROM public.clients WHERE id=root_matter.client_id AND org_id=root_document.org_id;
    IF root_matter.id IS NULL OR root_client.id IS NULL THEN
      RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN;
    END IF;
    v_root_org_id := root_document.org_id;
  END IF;

  SELECT * INTO actor FROM public.get_my_organisation_context() AS context
  WHERE context.org_id=v_root_org_id AND context.state='active' AND auth.uid() IS NOT NULL LIMIT 1;
  IF actor.org_id IS NULL THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,0,0,0,0; RETURN;
  END IF;
  IF (p_resource_type='document' AND NOT ('trash.document'=ANY(actor.capabilities)))
     OR (p_resource_type IN ('client','matter') AND NOT ('trash.hierarchy'=ANY(actor.capabilities))) THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,0,0,0,0; RETURN;
  END IF;

  -- Serialize every hierarchy command in an organisation before acquiring any
  -- hierarchy rows. The preliminary reads above establish tenant authority;
  -- re-reading after this lock prevents stale success if a concurrent command
  -- changed the root or parent before this command entered the critical path.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_root_org_id::text),
    pg_catalog.hashtext('hierarchical-resource-trash')
  );
  IF p_resource_type = 'client' THEN
    SELECT * INTO root_client FROM public.clients WHERE id=p_resource_id AND org_id=v_root_org_id FOR UPDATE;
    IF root_client.id IS NULL THEN
      RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN;
    END IF;
  ELSIF p_resource_type = 'matter' THEN
    SELECT * INTO root_matter FROM public.matters WHERE id=p_resource_id AND org_id=v_root_org_id FOR UPDATE;
    IF root_matter.id IS NULL THEN
      RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN;
    END IF;
    SELECT * INTO root_client FROM public.clients WHERE id=root_matter.client_id AND org_id=v_root_org_id FOR UPDATE;
    IF root_client.id IS NULL THEN
      RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN;
    END IF;
  ELSE
    SELECT * INTO root_document FROM public.documents WHERE id=p_resource_id AND org_id=v_root_org_id FOR UPDATE;
    IF root_document.id IS NULL THEN
      RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN;
    END IF;
    SELECT * INTO root_matter FROM public.matters WHERE id=root_document.matter_id AND org_id=v_root_org_id FOR UPDATE;
    SELECT * INTO root_client FROM public.clients WHERE id=root_matter.client_id AND org_id=v_root_org_id FOR UPDATE;
    IF root_matter.id IS NULL OR root_client.id IS NULL THEN
      RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN;
    END IF;
  END IF;

  -- Serialise an actor's retries within this organisation before inspection.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_root_org_id::text),
    pg_catalog.hashtext(auth.uid()::text || ':trash:' || p_idempotency_key)
  );
  SELECT * INTO prior FROM public.trash_operations
  WHERE org_id=v_root_org_id AND actor_user_id=auth.uid() AND idempotency_key=p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.root_resource_type <> p_resource_type OR prior.root_resource_id <> p_resource_id THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text,prior.id,prior.included_client_count,prior.included_matter_count,prior.included_document_count,prior.preexisting_trashed_descendant_count;
    ELSE
      RETURN QUERY SELECT 'already_trashed'::text,prior.id,prior.included_client_count,prior.included_matter_count,prior.included_document_count,prior.preexisting_trashed_descendant_count;
    END IF;
    RETURN;
  END IF;

  -- An already-trashing/trashed root is not a new command. This check comes
  -- after replay handling so an identical retry returns its original result.
  IF (p_resource_type='client' AND (root_client.record_state <> 'active' OR root_client.deleted_at IS NOT NULL))
     OR (p_resource_type='matter' AND (root_matter.record_state <> 'active' OR root_matter.deleted_at IS NOT NULL
       OR root_client.record_state <> 'active' OR root_client.deleted_at IS NOT NULL))
     OR (p_resource_type='document' AND (root_document.record_state <> 'active' OR root_document.deleted_at IS NOT NULL
       OR root_matter.record_state <> 'active' OR root_matter.deleted_at IS NOT NULL
       OR root_client.record_state <> 'active' OR root_client.deleted_at IS NOT NULL)) THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0;
    RETURN;
  END IF;

  -- Lock the full active subtree after the parent lock so no child can enter
  -- the snapshot while we construct its membership tree.
  IF p_resource_type='client' THEN
    FOR descendant IN SELECT m.* FROM public.matters AS m
      WHERE m.org_id=v_root_org_id AND m.client_id=root_client.id ORDER BY m.id FOR UPDATE LOOP
      IF descendant.record_state='active' AND descendant.deleted_at IS NULL THEN
        v_matters := v_matters + 1;
      ELSE
        v_excluded := v_excluded + 1;
      END IF;
    END LOOP;
    FOR descendant IN SELECT d.* FROM public.documents AS d
      JOIN public.matters AS m ON m.id=d.matter_id AND m.org_id=d.org_id
      WHERE d.org_id=v_root_org_id AND m.client_id=root_client.id
        AND m.record_state='active' AND m.deleted_at IS NULL
      ORDER BY d.id FOR UPDATE OF d LOOP
      IF descendant.record_state::text='active' AND descendant.deleted_at IS NULL THEN
        v_documents := v_documents + 1;
      ELSE
        v_excluded := v_excluded + 1;
      END IF;
    END LOOP;
    v_clients := 1;
  ELSIF p_resource_type='matter' THEN
    FOR descendant IN SELECT d.* FROM public.documents AS d
      WHERE d.org_id=v_root_org_id AND d.matter_id=root_matter.id ORDER BY d.id FOR UPDATE LOOP
      IF descendant.record_state::text='active' AND descendant.deleted_at IS NULL THEN
        v_documents := v_documents + 1;
      ELSE
        v_excluded := v_excluded + 1;
      END IF;
    END LOOP;
    v_matters := 1;
  ELSE
    v_documents := 1;
  END IF;

  INSERT INTO public.trash_operations(
    org_id,root_resource_type,root_resource_id,root_client_id,root_matter_id,root_document_id,
    actor_user_id,idempotency_key,included_client_count,included_matter_count,included_document_count,
    preexisting_trashed_descendant_count
  ) VALUES (
    v_root_org_id,p_resource_type,p_resource_id,
    CASE WHEN p_resource_type='client' THEN p_resource_id END,
    CASE WHEN p_resource_type='matter' THEN p_resource_id END,
    CASE WHEN p_resource_type='document' THEN p_resource_id END,
    auth.uid(),p_idempotency_key,v_clients,v_matters,v_documents,v_excluded
  ) RETURNING id INTO v_operation_id;

  IF p_resource_type='client' THEN
    INSERT INTO public.resource_trash_memberships(org_id,operation_id,resource_type,resource_id,client_id,cause)
    VALUES(v_root_org_id,v_operation_id,'client',root_client.id,root_client.id,'direct') RETURNING id INTO v_client_membership;
    UPDATE public.clients SET record_state='trashed',active_trash_membership_id=v_client_membership,deleted_at=now() WHERE id=root_client.id AND org_id=v_root_org_id;
    FOR descendant IN SELECT m.* FROM public.matters AS m WHERE m.org_id=v_root_org_id AND m.client_id=root_client.id
      AND m.record_state='active' AND m.deleted_at IS NULL ORDER BY m.id FOR UPDATE LOOP
      INSERT INTO public.resource_trash_memberships(org_id,operation_id,resource_type,resource_id,matter_id,parent_membership_id,cause)
      VALUES(v_root_org_id,v_operation_id,'matter',descendant.id,descendant.id,v_client_membership,'inherited') RETURNING id INTO v_matter_membership;
      UPDATE public.matters SET record_state='trashed',active_trash_membership_id=v_matter_membership,deleted_at=now() WHERE id=descendant.id AND org_id=v_root_org_id;
      FOR root_document IN SELECT d.* FROM public.documents AS d WHERE d.org_id=v_root_org_id AND d.matter_id=descendant.id
        AND d.record_state='active' AND d.deleted_at IS NULL ORDER BY d.id FOR UPDATE LOOP
        INSERT INTO public.resource_trash_memberships(org_id,operation_id,resource_type,resource_id,document_id,parent_membership_id,cause)
        VALUES(v_root_org_id,v_operation_id,'document',root_document.id,root_document.id,v_matter_membership,'inherited')
        RETURNING id INTO v_document_membership;
        UPDATE public.documents SET record_state='trashed',active_trash_membership_id=v_document_membership,deleted_at=now(),trashed_at=now(),trashed_by=auth.uid(),trashed_reason='trash_operation' WHERE id=root_document.id AND org_id=v_root_org_id;
      END LOOP;
    END LOOP;
  ELSIF p_resource_type='matter' THEN
    INSERT INTO public.resource_trash_memberships(org_id,operation_id,resource_type,resource_id,matter_id,cause)
    VALUES(v_root_org_id,v_operation_id,'matter',root_matter.id,root_matter.id,'direct') RETURNING id INTO v_matter_membership;
    UPDATE public.matters SET record_state='trashed',active_trash_membership_id=v_matter_membership,deleted_at=now() WHERE id=root_matter.id AND org_id=v_root_org_id;
    FOR root_document IN SELECT d.* FROM public.documents AS d WHERE d.org_id=v_root_org_id AND d.matter_id=root_matter.id
      AND d.record_state='active' AND d.deleted_at IS NULL ORDER BY d.id FOR UPDATE LOOP
      INSERT INTO public.resource_trash_memberships(org_id,operation_id,resource_type,resource_id,document_id,parent_membership_id,cause)
      VALUES(v_root_org_id,v_operation_id,'document',root_document.id,root_document.id,v_matter_membership,'inherited')
      RETURNING id INTO v_document_membership;
      UPDATE public.documents SET record_state='trashed',active_trash_membership_id=v_document_membership,deleted_at=now(),trashed_at=now(),trashed_by=auth.uid(),trashed_reason='trash_operation' WHERE id=root_document.id AND org_id=v_root_org_id;
    END LOOP;
  ELSE
    INSERT INTO public.resource_trash_memberships(org_id,operation_id,resource_type,resource_id,document_id,cause)
    VALUES(v_root_org_id,v_operation_id,'document',root_document.id,root_document.id,'direct') RETURNING id INTO v_document_membership;
    UPDATE public.documents SET record_state='trashed',active_trash_membership_id=v_document_membership,deleted_at=now(),trashed_at=now(),trashed_by=auth.uid(),trashed_reason='trash_operation' WHERE id=root_document.id AND org_id=v_root_org_id;
  END IF;

  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata,is_reversible)
  VALUES(v_root_org_id,auth.uid(),'resource_trashed',p_resource_type::text::public.entity_type,p_resource_id,
    'Moved resource to Trash',jsonb_build_object('operation_id',v_operation_id::text,'resource_type',p_resource_type::text),true);
  INSERT INTO public.outbox_events(org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key)
  VALUES(v_root_org_id,'trash_operation',v_operation_id,'trash.operation_created.v1',
    jsonb_build_object('operation_id',v_operation_id::text,'root_resource_id',p_resource_id::text,'root_resource_type',p_resource_type::text),
    'trash.operation.' || v_operation_id::text);

  RETURN QUERY SELECT 'trashed'::text,v_operation_id,v_clients,v_matters,v_documents,v_excluded;
END $$;

REVOKE ALL ON FUNCTION public.trash_resource(public.trash_resource_type,uuid,text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.trash_resource(public.trash_resource_type,uuid,text) TO authenticated;

COMMENT ON FUNCTION public.trash_resource(public.trash_resource_type,uuid,text) IS
  'Authenticated hierarchy-aware Trash command. Locks the root and active descendants, records one operation and tree, and emits identifier-only intent. Restore and purge are intentionally absent.';

COMMIT;
