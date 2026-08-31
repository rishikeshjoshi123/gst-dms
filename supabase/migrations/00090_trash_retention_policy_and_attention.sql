-- Live organisation Trash retention policy and durable 24-hour attention.
--
-- Permanent-deletion execution remains deliberately absent. This migration
-- owns only the prospective 30/60/90-day policy, atomic operation snapshots,
-- the durable schedule, and the authorised Team attention projection.
BEGIN;

-- The legacy columns remain as private compatibility storage because existing
-- operations may carry the earlier manual-only shape. The live organisation
-- policy itself is now exactly one automatic 30/60/90-day choice.
UPDATE public.organisation_retention_settings
SET trash_retention_mode='retention_period',
    trash_retention_days=90,
    auto_purge_enabled=true,
    updated_at=now()
WHERE trash_retention_mode<>'retention_period'
   OR trash_retention_days IS NULL
   OR trash_retention_days NOT IN (30,60,90)
   OR NOT auto_purge_enabled;

INSERT INTO public.organisation_retention_settings(
  org_id,trash_retention_mode,trash_retention_days,auto_purge_enabled
)
SELECT organisation.id,'retention_period',90,true
FROM public.organisations organisation
ON CONFLICT (org_id) DO NOTHING;

ALTER TABLE public.organisation_retention_settings
  DROP CONSTRAINT organisation_retention_settings_policy,
  ALTER COLUMN trash_retention_mode SET DEFAULT 'retention_period',
  ALTER COLUMN trash_retention_days SET DEFAULT 90,
  ALTER COLUMN trash_retention_days SET NOT NULL,
  ALTER COLUMN auto_purge_enabled SET DEFAULT true,
  ADD CONSTRAINT organisation_retention_settings_policy CHECK (
    trash_retention_mode='retention_period'
    AND trash_retention_days IN (30,60,90)
    AND auto_purge_enabled
  );

CREATE FUNCTION public.initialise_organisation_trash_retention_policy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  INSERT INTO public.organisation_retention_settings(
    org_id,trash_retention_mode,trash_retention_days,auto_purge_enabled
  ) VALUES (NEW.id,'retention_period',90,true)
  ON CONFLICT (org_id) DO NOTHING;
  RETURN NEW;
END $$;

CREATE TRIGGER organisations_initialise_trash_retention_policy
  AFTER INSERT ON public.organisations
  FOR EACH ROW EXECUTE FUNCTION public.initialise_organisation_trash_retention_policy();

-- Keep the capability catalogue canonical. The UI may use this capability for
-- presentation, but both RPCs below independently derive it from auth.uid().
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
      'trash.retention.manage','document.view','document.intake.create',
      'document.record.create','document.intake.assign','document.intake.discard',
      'document.version.attach','document.version.replace','document.reprocess',
      'document.metadata.decide','trash.document','trash.hierarchy'
    ]::text[]
    WHEN p_role='admin' THEN ARRAY[
      'team.view','team.invite.standard','team.role.manage_standard',
      'team.membership.suspend_standard','organisation.profile.manage',
      'organisation.operations.manage','trash.purge','trash.retention.manage',
      'document.view','document.intake.create','document.record.create',
      'document.intake.assign','document.intake.discard','document.version.attach',
      'document.version.replace','document.reprocess','document.metadata.decide',
      'trash.document','trash.hierarchy'
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
  SELECT membership.id,membership.org_id,membership.role,
    (organisation.owner_membership_id=membership.id),membership.state,8,
    public.organisation_member_capabilities(
      membership.role,organisation.owner_membership_id=membership.id,membership.state
    ),membership.revision
  FROM public.organisation_memberships membership
  JOIN public.organisations organisation ON organisation.id=membership.org_id
  WHERE membership.user_id=auth.uid() AND membership.state IN ('active','suspended')
$$;

CREATE FUNCTION public.get_organisation_trash_retention_policy(p_org_id uuid)
RETURNS TABLE(
  trash_retention_days smallint,
  policy_version integer,
  updated_at timestamptz,
  can_manage boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE actor record;
BEGIN
  IF p_org_id IS NULL OR auth.uid() IS NULL THEN RETURN; END IF;
  SELECT * INTO actor FROM public.get_my_organisation_context() context
  WHERE context.org_id=p_org_id AND context.state='active' LIMIT 1;
  IF actor.org_id IS NULL THEN RETURN; END IF;
  RETURN QUERY
  SELECT settings.trash_retention_days,settings.policy_version,settings.updated_at,
    ('trash.retention.manage'=ANY(actor.capabilities))
  FROM public.organisation_retention_settings settings
  WHERE settings.org_id=p_org_id;
END $$;

CREATE FUNCTION public.update_organisation_trash_retention_policy(
  p_org_id uuid,
  p_trash_retention_days integer,
  p_expected_policy_version integer
)
RETURNS TABLE(code text, trash_retention_days smallint, policy_version integer, updated_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE actor record; settings public.organisation_retention_settings%ROWTYPE;
BEGIN
  IF p_org_id IS NULL OR p_trash_retention_days NOT IN (30,60,90)
     OR p_expected_policy_version IS NULL OR p_expected_policy_version<1
     OR auth.uid() IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::smallint,NULL::integer,NULL::timestamptz;
    RETURN;
  END IF;
  SELECT * INTO actor FROM public.get_my_organisation_context() context
  WHERE context.org_id=p_org_id AND context.state='active' LIMIT 1;
  IF actor.org_id IS NULL OR NOT ('trash.retention.manage'=ANY(actor.capabilities)) THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::smallint,NULL::integer,NULL::timestamptz;
    RETURN;
  END IF;

  -- This is the same lock used by trash_resource. Whichever transaction wins
  -- defines the complete old-or-new policy snapshot; a mixed snapshot cannot
  -- be observed by a new root operation.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(p_org_id::text),
    pg_catalog.hashtext('hierarchical-resource-trash')
  );
  SELECT target.* INTO settings FROM public.organisation_retention_settings target
  WHERE target.org_id=p_org_id FOR UPDATE;
  IF settings.org_id IS NULL THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::smallint,NULL::integer,NULL::timestamptz;
    RETURN;
  END IF;
  IF settings.policy_version<>p_expected_policy_version THEN
    RETURN QUERY SELECT 'conflict'::text,settings.trash_retention_days,
      settings.policy_version,settings.updated_at;
    RETURN;
  END IF;

  UPDATE public.organisation_retention_settings target
  SET trash_retention_mode='retention_period',trash_retention_days=p_trash_retention_days::smallint,
      auto_purge_enabled=true,policy_version=target.policy_version+1,
      updated_by=auth.uid(),updated_at=now()
  WHERE target.org_id=p_org_id
  RETURNING target.* INTO settings;
  RETURN QUERY SELECT 'updated'::text,settings.trash_retention_days,
    settings.policy_version,settings.updated_at;
END $$;

-- Replace the live command in place so the policy read and operation insert
-- remain one database transaction. No application-supplied policy value is
-- accepted and no new command surface is introduced.
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
  retention public.organisation_retention_settings%ROWTYPE;
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
  v_now timestamptz := transaction_timestamp();
  v_delete_at timestamptz;
BEGIN
  IF p_resource_type IS NULL OR p_resource_id IS NULL OR p_idempotency_key IS NULL
     OR p_idempotency_key !~ '^[a-z][a-z0-9_.:-]{0,127}$' THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,0,0,0,0; RETURN;
  END IF;

  SELECT * INTO actor FROM public.get_my_organisation_context() context
  WHERE context.state='active' AND auth.uid() IS NOT NULL LIMIT 1;
  IF actor.org_id IS NULL THEN RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,0,0,0,0; RETURN; END IF;
  v_root_org_id:=actor.org_id;

  -- Bind every root lookup to the authenticated tenant before resolving any
  -- hierarchy. A forged foreign ID is indistinguishable from an unavailable
  -- local ID and cannot disclose that the foreign resource exists.
  IF p_resource_type='client' THEN
    SELECT * INTO root_client FROM public.clients WHERE id=p_resource_id AND org_id=v_root_org_id;
    IF root_client.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN; END IF;
  ELSIF p_resource_type='matter' THEN
    SELECT * INTO root_matter FROM public.matters WHERE id=p_resource_id AND org_id=v_root_org_id;
    IF root_matter.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN; END IF;
    SELECT * INTO root_client FROM public.clients WHERE id=root_matter.client_id AND org_id=v_root_org_id;
    IF root_client.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN; END IF;
  ELSE
    SELECT * INTO root_document FROM public.documents WHERE id=p_resource_id AND org_id=v_root_org_id;
    IF root_document.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN; END IF;
    SELECT * INTO root_matter FROM public.matters WHERE id=root_document.matter_id AND org_id=v_root_org_id;
    SELECT * INTO root_client FROM public.clients WHERE id=root_matter.client_id AND org_id=v_root_org_id;
    IF root_matter.id IS NULL OR root_client.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN; END IF;
  END IF;

  IF (p_resource_type='document' AND NOT ('trash.document'=ANY(actor.capabilities)))
     OR (p_resource_type IN ('client','matter') AND NOT ('trash.hierarchy'=ANY(actor.capabilities))) THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,0,0,0,0; RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_root_org_id::text),pg_catalog.hashtext('hierarchical-resource-trash')
  );
  SELECT target.* INTO retention FROM public.organisation_retention_settings target
  WHERE target.org_id=v_root_org_id FOR UPDATE;
  IF retention.org_id IS NULL OR retention.trash_retention_mode<>'retention_period'
     OR retention.trash_retention_days NOT IN (30,60,90) OR NOT retention.auto_purge_enabled THEN
    RAISE EXCEPTION 'organisation Trash retention policy is unavailable';
  END IF;
  v_delete_at:=v_now+pg_catalog.make_interval(days=>retention.trash_retention_days);

  IF p_resource_type='client' THEN
    SELECT * INTO root_client FROM public.clients WHERE id=p_resource_id AND org_id=v_root_org_id FOR UPDATE;
    IF root_client.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN; END IF;
  ELSIF p_resource_type='matter' THEN
    SELECT * INTO root_matter FROM public.matters WHERE id=p_resource_id AND org_id=v_root_org_id FOR UPDATE;
    IF root_matter.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN; END IF;
    SELECT * INTO root_client FROM public.clients WHERE id=root_matter.client_id AND org_id=v_root_org_id FOR UPDATE;
    IF root_client.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN; END IF;
  ELSE
    SELECT * INTO root_document FROM public.documents WHERE id=p_resource_id AND org_id=v_root_org_id FOR UPDATE;
    IF root_document.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN; END IF;
    SELECT * INTO root_matter FROM public.matters WHERE id=root_document.matter_id AND org_id=v_root_org_id FOR UPDATE;
    SELECT * INTO root_client FROM public.clients WHERE id=root_matter.client_id AND org_id=v_root_org_id FOR UPDATE;
    IF root_matter.id IS NULL OR root_client.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN; END IF;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_root_org_id::text),
    pg_catalog.hashtext(auth.uid()::text||':trash:'||p_idempotency_key)
  );
  SELECT * INTO prior FROM public.trash_operations
  WHERE org_id=v_root_org_id AND actor_user_id=auth.uid() AND idempotency_key=p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.root_resource_type<>p_resource_type OR prior.root_resource_id<>p_resource_id THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text,prior.id,prior.included_client_count,prior.included_matter_count,prior.included_document_count,prior.preexisting_trashed_descendant_count;
    ELSE
      RETURN QUERY SELECT 'already_trashed'::text,prior.id,prior.included_client_count,prior.included_matter_count,prior.included_document_count,prior.preexisting_trashed_descendant_count;
    END IF;
    RETURN;
  END IF;

  IF (p_resource_type='client' AND (root_client.record_state<>'active' OR root_client.deleted_at IS NOT NULL))
     OR (p_resource_type='matter' AND (root_matter.record_state<>'active' OR root_matter.deleted_at IS NOT NULL
       OR root_client.record_state<>'active' OR root_client.deleted_at IS NOT NULL))
     OR (p_resource_type='document' AND (root_document.record_state<>'active' OR root_document.deleted_at IS NOT NULL
       OR root_matter.record_state<>'active' OR root_matter.deleted_at IS NOT NULL
       OR root_client.record_state<>'active' OR root_client.deleted_at IS NOT NULL)) THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid,0,0,0,0; RETURN;
  END IF;

  IF p_resource_type='client' THEN
    FOR descendant IN SELECT matter.* FROM public.matters matter
      WHERE matter.org_id=v_root_org_id AND matter.client_id=root_client.id ORDER BY matter.id FOR UPDATE LOOP
      IF descendant.record_state='active' AND descendant.deleted_at IS NULL THEN v_matters:=v_matters+1; ELSE v_excluded:=v_excluded+1; END IF;
    END LOOP;
    FOR descendant IN SELECT document.* FROM public.documents document
      JOIN public.matters matter ON matter.id=document.matter_id AND matter.org_id=document.org_id
      WHERE document.org_id=v_root_org_id AND matter.client_id=root_client.id
        AND matter.record_state='active' AND matter.deleted_at IS NULL
      ORDER BY document.id FOR UPDATE OF document LOOP
      IF descendant.record_state::text='active' AND descendant.deleted_at IS NULL THEN v_documents:=v_documents+1; ELSE v_excluded:=v_excluded+1; END IF;
    END LOOP;
    v_clients:=1;
  ELSIF p_resource_type='matter' THEN
    FOR descendant IN SELECT document.* FROM public.documents document
      WHERE document.org_id=v_root_org_id AND document.matter_id=root_matter.id ORDER BY document.id FOR UPDATE LOOP
      IF descendant.record_state::text='active' AND descendant.deleted_at IS NULL THEN v_documents:=v_documents+1; ELSE v_excluded:=v_excluded+1; END IF;
    END LOOP;
    v_matters:=1;
  ELSE v_documents:=1;
  END IF;

  INSERT INTO public.trash_operations(
    org_id,root_resource_type,root_resource_id,root_client_id,root_matter_id,root_document_id,
    actor_user_id,idempotency_key,retention_mode,retention_days,
    auto_purge_enabled_snapshot,retention_policy_version,purge_eligible_at,auto_purge_at,
    included_client_count,included_matter_count,included_document_count,
    preexisting_trashed_descendant_count,created_at,updated_at
  ) VALUES (
    v_root_org_id,p_resource_type,p_resource_id,
    CASE WHEN p_resource_type='client' THEN p_resource_id END,
    CASE WHEN p_resource_type='matter' THEN p_resource_id END,
    CASE WHEN p_resource_type='document' THEN p_resource_id END,
    auth.uid(),p_idempotency_key,'retention_period',retention.trash_retention_days,true,
    retention.policy_version,v_delete_at,v_delete_at,v_clients,v_matters,v_documents,v_excluded,v_now,v_now
  ) RETURNING id INTO v_operation_id;

  IF p_resource_type='client' THEN
    INSERT INTO public.resource_trash_memberships(org_id,operation_id,resource_type,resource_id,client_id,cause,created_at,updated_at)
    VALUES(v_root_org_id,v_operation_id,'client',root_client.id,root_client.id,'direct',v_now,v_now) RETURNING id INTO v_client_membership;
    UPDATE public.clients SET record_state='trashed',active_trash_membership_id=v_client_membership,deleted_at=v_now WHERE id=root_client.id AND org_id=v_root_org_id;
    FOR descendant IN SELECT matter.* FROM public.matters matter WHERE matter.org_id=v_root_org_id AND matter.client_id=root_client.id
      AND matter.record_state='active' AND matter.deleted_at IS NULL ORDER BY matter.id FOR UPDATE LOOP
      INSERT INTO public.resource_trash_memberships(org_id,operation_id,resource_type,resource_id,matter_id,parent_membership_id,cause,created_at,updated_at)
      VALUES(v_root_org_id,v_operation_id,'matter',descendant.id,descendant.id,v_client_membership,'inherited',v_now,v_now) RETURNING id INTO v_matter_membership;
      UPDATE public.matters SET record_state='trashed',active_trash_membership_id=v_matter_membership,deleted_at=v_now WHERE id=descendant.id AND org_id=v_root_org_id;
      FOR root_document IN SELECT document.* FROM public.documents document WHERE document.org_id=v_root_org_id AND document.matter_id=descendant.id
        AND document.record_state='active' AND document.deleted_at IS NULL ORDER BY document.id FOR UPDATE LOOP
        INSERT INTO public.resource_trash_memberships(org_id,operation_id,resource_type,resource_id,document_id,parent_membership_id,cause,created_at,updated_at)
        VALUES(v_root_org_id,v_operation_id,'document',root_document.id,root_document.id,v_matter_membership,'inherited',v_now,v_now)
        RETURNING id INTO v_document_membership;
        UPDATE public.documents SET record_state='trashed',active_trash_membership_id=v_document_membership,
          deleted_at=v_now,trashed_at=v_now,trashed_by=auth.uid(),trashed_reason='trash_operation'
        WHERE id=root_document.id AND org_id=v_root_org_id;
      END LOOP;
    END LOOP;
  ELSIF p_resource_type='matter' THEN
    INSERT INTO public.resource_trash_memberships(org_id,operation_id,resource_type,resource_id,matter_id,cause,created_at,updated_at)
    VALUES(v_root_org_id,v_operation_id,'matter',root_matter.id,root_matter.id,'direct',v_now,v_now) RETURNING id INTO v_matter_membership;
    UPDATE public.matters SET record_state='trashed',active_trash_membership_id=v_matter_membership,deleted_at=v_now WHERE id=root_matter.id AND org_id=v_root_org_id;
    FOR root_document IN SELECT document.* FROM public.documents document WHERE document.org_id=v_root_org_id AND document.matter_id=root_matter.id
      AND document.record_state='active' AND document.deleted_at IS NULL ORDER BY document.id FOR UPDATE LOOP
      INSERT INTO public.resource_trash_memberships(org_id,operation_id,resource_type,resource_id,document_id,parent_membership_id,cause,created_at,updated_at)
      VALUES(v_root_org_id,v_operation_id,'document',root_document.id,root_document.id,v_matter_membership,'inherited',v_now,v_now)
      RETURNING id INTO v_document_membership;
      UPDATE public.documents SET record_state='trashed',active_trash_membership_id=v_document_membership,
        deleted_at=v_now,trashed_at=v_now,trashed_by=auth.uid(),trashed_reason='trash_operation'
      WHERE id=root_document.id AND org_id=v_root_org_id;
    END LOOP;
  ELSE
    INSERT INTO public.resource_trash_memberships(org_id,operation_id,resource_type,resource_id,document_id,cause,created_at,updated_at)
    VALUES(v_root_org_id,v_operation_id,'document',root_document.id,root_document.id,'direct',v_now,v_now) RETURNING id INTO v_document_membership;
    UPDATE public.documents SET record_state='trashed',active_trash_membership_id=v_document_membership,
      deleted_at=v_now,trashed_at=v_now,trashed_by=auth.uid(),trashed_reason='trash_operation'
    WHERE id=root_document.id AND org_id=v_root_org_id;
  END IF;

  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata,is_reversible,created_at)
  VALUES(v_root_org_id,auth.uid(),'resource_trashed',p_resource_type::text::public.entity_type,p_resource_id,
    'Moved resource to Trash',jsonb_build_object('operation_id',v_operation_id::text,'resource_type',p_resource_type::text),true,v_now);
  INSERT INTO public.outbox_events(org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key,created_at,updated_at)
  VALUES(v_root_org_id,'trash_operation',v_operation_id,'trash.operation_created.v1',
    jsonb_build_object('operation_id',v_operation_id::text,'root_resource_id',p_resource_id::text,'root_resource_type',p_resource_type::text),
    'trash.operation.'||v_operation_id::text,v_now,v_now);

  RETURN QUERY SELECT 'trashed'::text,v_operation_id,v_clients,v_matters,v_documents,v_excluded;
END $$;

CREATE TYPE public.trash_retention_attention_state AS ENUM ('active','resolved');
CREATE TYPE public.trash_retention_attention_resolution AS ENUM (
  'source_restored','source_purged','source_ineligible'
);

CREATE TABLE public.trash_retention_team_attention_items (
  operation_id uuid PRIMARY KEY,
  org_id uuid NOT NULL,
  state public.trash_retention_attention_state NOT NULL DEFAULT 'active',
  available_at timestamptz NOT NULL,
  scheduled_permanent_deletion_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  resolution public.trash_retention_attention_resolution,
  CONSTRAINT trash_retention_attention_operation_org_fkey FOREIGN KEY (org_id,operation_id)
    REFERENCES public.trash_operations(org_id,id) ON DELETE RESTRICT,
  CONSTRAINT trash_retention_attention_state_shape CHECK (
    (state='active' AND resolved_at IS NULL AND resolution IS NULL)
    OR (state='resolved' AND resolved_at IS NOT NULL AND resolution IS NOT NULL)
  ),
  CONSTRAINT trash_retention_attention_window CHECK (
    available_at=scheduled_permanent_deletion_at-interval '24 hours'
  )
);
CREATE INDEX trash_retention_attention_active_org_idx
  ON public.trash_retention_team_attention_items(org_id,scheduled_permanent_deletion_at,operation_id)
  WHERE state='active';
CREATE INDEX trash_operations_retention_attention_due_idx
  ON public.trash_operations(auto_purge_at,org_id,id)
  WHERE auto_purge_enabled_snapshot AND auto_purge_at IS NOT NULL
    AND state IN ('trashed','restore_blocked','purge_scheduled');

ALTER TABLE public.trash_retention_team_attention_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trash_retention_team_attention_items FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.trash_retention_team_attention_items FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.project_due_trash_retention_team_attention(p_batch_size integer DEFAULT 100)
RETURNS TABLE(projected_count integer, already_projected_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE projected integer:=0; selected_count integer:=0;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'invalid Trash retention attention batch size';
  END IF;
  WITH candidates AS (
    SELECT operation.id,operation.org_id,operation.auto_purge_at
    FROM public.trash_operations operation
    WHERE operation.auto_purge_enabled_snapshot
      AND operation.retention_mode='retention_period'
      AND operation.retention_days IN (30,60,90)
      AND operation.auto_purge_at IS NOT NULL
      AND operation.purge_eligible_at=operation.auto_purge_at
      AND operation.auto_purge_at-interval '24 hours'<=now()
      AND operation.auto_purge_at>now()
      AND operation.state IN ('trashed','restore_blocked','purge_scheduled')
      AND EXISTS (
        SELECT 1 FROM public.resource_trash_memberships root_membership
        WHERE root_membership.org_id=operation.org_id
          AND root_membership.operation_id=operation.id
          AND root_membership.resource_type=operation.root_resource_type
          AND root_membership.resource_id=operation.root_resource_id
          AND root_membership.cause='direct'
          AND root_membership.parent_membership_id IS NULL
          AND root_membership.state='active'
      )
    ORDER BY operation.auto_purge_at,operation.id
    FOR UPDATE OF operation SKIP LOCKED
    LIMIT p_batch_size
  ), counted AS (
    SELECT *,count(*) OVER ()::integer AS selected_count FROM candidates
  ), inserted AS (
    INSERT INTO public.trash_retention_team_attention_items(
      operation_id,org_id,available_at,scheduled_permanent_deletion_at
    )
    SELECT id,org_id,auto_purge_at-interval '24 hours',auto_purge_at FROM counted
    ON CONFLICT (operation_id) DO NOTHING
    RETURNING 1
  )
  SELECT coalesce((SELECT count(*) FROM inserted),0)::integer,
         coalesce((SELECT max(counted.selected_count) FROM counted),0)::integer
  INTO projected,selected_count;
  RETURN QUERY SELECT projected,greatest(selected_count-projected,0);
END $$;

CREATE FUNCTION public.resolve_trash_retention_team_attention()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE resolution_code public.trash_retention_attention_resolution;
BEGIN
  -- Transitional purge/restore states are suppressed by the authenticated
  -- reader but are not resolved prematurely. Only the terminal source state
  -- determines the durable resolution reason.
  IF NEW.state NOT IN ('restored','purged') THEN RETURN NEW; END IF;
  resolution_code:=CASE
    WHEN NEW.state='restored' THEN 'source_restored'::public.trash_retention_attention_resolution
    ELSE 'source_purged'::public.trash_retention_attention_resolution
  END;
  UPDATE public.trash_retention_team_attention_items item
  SET state='resolved',resolved_at=now(),resolution=resolution_code
  WHERE item.org_id=NEW.org_id AND item.operation_id=NEW.id AND item.state='active';
  RETURN NEW;
END $$;

CREATE TRIGGER trash_operations_resolve_retention_attention
  AFTER UPDATE OF state ON public.trash_operations
  FOR EACH ROW EXECUTE FUNCTION public.resolve_trash_retention_team_attention();

CREATE FUNCTION public.get_trash_retention_team_attention(
  p_org_id uuid,
  p_limit integer DEFAULT 25
)
RETURNS TABLE(
  operation_id uuid,
  root_resource_type public.trash_resource_type,
  root_label text,
  scheduled_permanent_deletion_at timestamptz,
  projected_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE actor record;
BEGIN
  IF p_org_id IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 OR auth.uid() IS NULL THEN RETURN; END IF;
  SELECT * INTO actor FROM public.get_my_organisation_context() context
  WHERE context.org_id=p_org_id AND context.state='active' LIMIT 1;
  IF actor.org_id IS NULL OR NOT ('trash.retention.manage'=ANY(actor.capabilities)) THEN RETURN; END IF;

  RETURN QUERY
  SELECT operation.id,operation.root_resource_type,
    CASE operation.root_resource_type
      WHEN 'client' THEN root_client.name
      WHEN 'matter' THEN root_matter.title
      ELSE coalesce(root_document.display_title,root_document.effective_filename,'Untitled document')
    END,
    item.scheduled_permanent_deletion_at,item.created_at
  FROM public.trash_retention_team_attention_items item
  JOIN public.trash_operations operation
    ON operation.org_id=item.org_id AND operation.id=item.operation_id
  JOIN public.resource_trash_memberships root_membership
    ON root_membership.org_id=operation.org_id AND root_membership.operation_id=operation.id
   AND root_membership.resource_type=operation.root_resource_type
   AND root_membership.resource_id=operation.root_resource_id
   AND root_membership.cause='direct' AND root_membership.parent_membership_id IS NULL
   AND root_membership.state='active'
  LEFT JOIN public.clients root_client
    ON operation.root_resource_type='client' AND root_client.org_id=operation.org_id
   AND root_client.id=operation.root_resource_id AND root_client.record_state='trashed'
  LEFT JOIN public.matters root_matter
    ON operation.root_resource_type='matter' AND root_matter.org_id=operation.org_id
   AND root_matter.id=operation.root_resource_id AND root_matter.record_state='trashed'
  LEFT JOIN public.documents root_document
    ON operation.root_resource_type='document' AND root_document.org_id=operation.org_id
   AND root_document.id=operation.root_resource_id AND root_document.record_state='trashed'
  WHERE item.org_id=p_org_id AND item.state='active' AND item.available_at<=now()
    AND operation.state IN ('trashed','restore_blocked','purge_scheduled')
    AND operation.auto_purge_enabled_snapshot
    AND operation.auto_purge_at=item.scheduled_permanent_deletion_at
    AND (
      (operation.root_resource_type='client' AND root_client.id IS NOT NULL)
      OR (operation.root_resource_type='matter' AND root_matter.id IS NOT NULL)
      OR (operation.root_resource_type='document' AND root_document.id IS NOT NULL)
    )
  ORDER BY item.scheduled_permanent_deletion_at,item.operation_id
  LIMIT p_limit;
END $$;

REVOKE ALL ON FUNCTION
  public.initialise_organisation_trash_retention_policy(),
  public.project_due_trash_retention_team_attention(integer),
  public.resolve_trash_retention_team_attention()
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.project_due_trash_retention_team_attention(integer) TO service_role;

REVOKE ALL ON FUNCTION
  public.get_organisation_trash_retention_policy(uuid),
  public.update_organisation_trash_retention_policy(uuid,integer,integer),
  public.get_trash_retention_team_attention(uuid,integer)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION
  public.get_organisation_trash_retention_policy(uuid),
  public.update_organisation_trash_retention_policy(uuid,integer,integer),
  public.get_trash_retention_team_attention(uuid,integer)
  TO authenticated;

-- Preserve the command's existing browser-only authority after replacement.
REVOKE ALL ON FUNCTION public.trash_resource(public.trash_resource_type,uuid,text)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.trash_resource(public.trash_resource_type,uuid,text) TO authenticated;

COMMENT ON TABLE public.organisation_retention_settings IS
  'Service-private prospective Trash policy. Live policy is exactly automatic 30, 60, or 90 days; legacy mode columns are compatibility storage only.';
COMMENT ON TABLE public.trash_retention_team_attention_items IS
  'Content-free, operation-keyed Today Team attention projection created once in the 24-hour pre-deletion window and resolved from source lifecycle.';
COMMENT ON FUNCTION public.trash_resource(public.trash_resource_type,uuid,text) IS
  'Authenticated hierarchy-aware Trash command. Atomically snapshots the locked organisation retention policy and schedules permanent deletion without executing it.';
COMMENT ON FUNCTION public.project_due_trash_retention_team_attention(integer) IS
  'Service-only replay-safe projector for operation-keyed Trash warnings in the 24-hour pre-deletion window. It never executes permanent deletion.';

COMMIT;
