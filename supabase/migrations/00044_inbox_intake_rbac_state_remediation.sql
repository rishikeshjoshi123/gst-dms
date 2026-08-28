-- Restore one versioned capability matrix and preserve Intake terminal states.
BEGIN;

-- This is the sole role-to-capability matrix for the controlled-pilot tenant
-- contract. Context and directory projections call it rather than carrying
-- feature-local copies that can drift on later document capability additions.
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
      'document.version.replace'
    ]::text[]
    WHEN p_role='admin' THEN ARRAY[
      'team.view','team.invite.standard','team.role.manage_standard',
      'team.membership.suspend_standard','organisation.profile.manage',
      'organisation.operations.manage','trash.purge','document.view',
      'document.intake.create','document.record.create','document.intake.assign',
      'document.intake.discard','document.version.attach','document.version.replace'
    ]::text[]
    WHEN p_role='associate' THEN ARRAY[
      'team.view','document.view','document.intake.create','document.record.create',
      'document.intake.assign','document.intake.discard','document.version.attach',
      'document.version.replace'
    ]::text[]
    ELSE ARRAY['team.view','document.view']::text[]
  END
$$;

CREATE OR REPLACE FUNCTION public.get_my_organisation_context()
RETURNS TABLE (membership_id uuid, org_id uuid, role public.org_member_role,
  is_owner boolean, state public.organisation_membership_state,
  capability_version integer, capabilities text[], revision bigint)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
 SELECT m.id,m.org_id,m.role,(o.owner_membership_id=m.id),m.state,4,
   public.organisation_member_capabilities(m.role,o.owner_membership_id=m.id,m.state),m.revision
 FROM public.organisation_memberships m JOIN public.organisations o ON o.id=m.org_id
 WHERE m.user_id=auth.uid() AND m.state IN ('active','suspended');
$$;

CREATE OR REPLACE FUNCTION public.get_my_team_members()
RETURNS TABLE (membership_id uuid, display_name text, professional_title text,
  role public.org_member_role, is_owner boolean,
  state public.organisation_membership_state, joined_at timestamptz,
  revision bigint, capabilities text[], authorised_email text)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
 WITH caller AS (
   SELECT c.org_id,c.is_owner,c.role FROM public.get_my_organisation_context() c
   WHERE c.state='active' AND 'team.view'=ANY(c.capabilities)
 )
 SELECT m.id,p.display_name,p.professional_title,m.role,(o.owner_membership_id=m.id),
   m.state,m.joined_at,m.revision,
   public.organisation_member_capabilities(m.role,o.owner_membership_id=m.id,m.state),
   CASE WHEN (c.is_owner OR c.role='admin' OR m.user_id=auth.uid())
          AND u.email_confirmed_at IS NOT NULL THEN u.email END
 FROM caller c JOIN public.organisation_memberships m ON m.org_id=c.org_id
 JOIN public.organisations o ON o.id=m.org_id
 LEFT JOIN public.user_profiles p ON p.user_id=m.user_id
 LEFT JOIN auth.users u ON u.id=m.user_id
 WHERE m.state='active' OR (m.state='suspended' AND (c.is_owner OR c.role='admin'));
$$;

-- Discard is a deliberate placement decision for a successfully validated,
-- still-unassigned source. Failed, duplicate, expired, assigned, and already
-- discarded rows retain their terminal semantics and cannot be relabelled.
CREATE OR REPLACE FUNCTION public.discard_intake_item(p_intake_id uuid,p_idempotency uuid)
RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE x record; i public.intake_items%ROWTYPE; a public.file_assets%ROWTYPE;
  prior public.document_command_receipts%ROWTYPE;
BEGIN
  SELECT * INTO x FROM public.document_materialization_actor('document.intake.discard') LIMIT 1;
  IF x.org_id IS NULL OR p_intake_id IS NULL OR p_idempotency IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  SELECT * INTO prior FROM public.document_command_receipts
    WHERE org_id=x.org_id AND actor_user_id=x.actor_id
      AND command_kind='discard_intake' AND idempotency_key=p_idempotency;
  IF prior.id IS NOT NULL THEN RETURN QUERY SELECT prior.result_code; RETURN; END IF;
  SELECT * INTO i FROM public.intake_items WHERE id=p_intake_id AND org_id=x.org_id FOR UPDATE;
  IF i.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text; RETURN; END IF;
  IF i.state='discarded' THEN
    INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code)
      VALUES(x.org_id,x.actor_id,'discard_intake',p_idempotency,i.id,'already_discarded');
    RETURN QUERY SELECT 'already_discarded'::text; RETURN;
  END IF;
  IF i.state<>'ready' OR EXISTS (SELECT 1 FROM public.intake_item_assignments ia WHERE ia.intake_item_id=i.id) THEN
    RETURN QUERY SELECT 'intake_not_discardable'::text; RETURN;
  END IF;
  SELECT * INTO a FROM public.file_assets WHERE id=i.asset_id AND org_id=x.org_id FOR UPDATE;
  IF a.id IS NULL OR a.availability<>'available' THEN RETURN QUERY SELECT 'intake_not_discardable'::text; RETURN; END IF;
  UPDATE public.intake_items SET state='discarded',discarded_at=now(),updated_at=now(),failure_code='discarded' WHERE id=i.id;
  UPDATE public.file_assets SET availability='failed',validated_at=NULL,failed_at=now(),failure_code='discarded'
    WHERE id=a.id AND NOT EXISTS (SELECT 1 FROM public.document_versions dv WHERE dv.asset_id=a.id);
  INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code)
    VALUES(x.org_id,x.actor_id,'discard_intake',p_idempotency,i.id,'ok');
  PERFORM public.document_materialization_safe_event(x.org_id,i.id,'intake.discarded.v1',
    'intake.discard.'||i.id::text,jsonb_build_object('intake_id',i.id::text,'result_code','discarded'));
  RETURN QUERY SELECT 'ok'::text;
END $$;

REVOKE ALL ON FUNCTION public.organisation_member_capabilities(public.org_member_role,boolean,public.organisation_membership_state) FROM PUBLIC, anon, authenticated;
COMMIT;
