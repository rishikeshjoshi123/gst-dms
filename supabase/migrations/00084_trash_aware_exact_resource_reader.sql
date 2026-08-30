-- Read-only, authenticated context for exact Client/Matter/Document routes.
-- Private Trash tables remain inaccessible to browser clients; this function
-- discloses only a valid, tenant-scoped Trash context for a single exact row.
BEGIN;

CREATE OR REPLACE FUNCTION public.get_exact_resource_trash_context(
  p_resource_type public.trash_resource_type,
  p_resource_id uuid,
  p_expected_matter_id uuid DEFAULT NULL
)
RETURNS TABLE(
  resource_id uuid,
  resource_type public.trash_resource_type,
  membership_id uuid,
  cause public.resource_trash_cause,
  parent_membership_id uuid,
  operation_id uuid,
  root_resource_id uuid,
  root_resource_type public.trash_resource_type,
  operation_state public.trash_operation_state,
  trashed_at timestamptz,
  trashed_by uuid,
  retention_mode public.trash_retention_mode,
  retention_days integer,
  purge_eligible_at timestamptz,
  auto_purge_enabled boolean,
  auto_purge_at timestamptz,
  purge_scheduled_at timestamptz,
  blocker_count integer,
  can_restore boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  resource_org_id uuid;
  resource_state text;
  active_membership_id uuid;
  resource_matter_id uuid;
  caller record;
BEGIN
  IF p_resource_type IS NULL OR p_resource_id IS NULL THEN
    RETURN;
  END IF;

  IF p_resource_type = 'client' THEN
    IF p_expected_matter_id IS NOT NULL THEN RETURN; END IF;
    SELECT client.org_id, client.record_state::text, client.active_trash_membership_id, NULL::uuid
      INTO resource_org_id, resource_state, active_membership_id, resource_matter_id
    FROM public.clients AS client
    WHERE client.id = p_resource_id;
  ELSIF p_resource_type = 'matter' THEN
    IF p_expected_matter_id IS NOT NULL THEN RETURN; END IF;
    SELECT matter.org_id, matter.record_state::text, matter.active_trash_membership_id, matter.id
      INTO resource_org_id, resource_state, active_membership_id, resource_matter_id
    FROM public.matters AS matter
    WHERE matter.id = p_resource_id;
  ELSE
    SELECT document.org_id, document.record_state::text, document.active_trash_membership_id, document.matter_id
      INTO resource_org_id, resource_state, active_membership_id, resource_matter_id
    FROM public.documents AS document
    WHERE document.id = p_resource_id;
    IF resource_matter_id IS DISTINCT FROM p_expected_matter_id THEN RETURN; END IF;
  END IF;

  -- Resolve caller membership before returning any resource state. This also
  -- makes foreign IDs and inactive memberships non-disclosing.
  SELECT * INTO caller
  FROM public.get_my_organisation_context() AS context
  WHERE context.org_id = resource_org_id
    AND context.state = 'active'
    AND auth.uid() IS NOT NULL
  LIMIT 1;
  IF caller.org_id IS NULL
     OR resource_state <> 'trashed'
     OR active_membership_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    membership.resource_id,
    membership.resource_type,
    membership.id,
    membership.cause,
    membership.parent_membership_id,
    operation.id,
    operation.root_resource_id,
    operation.root_resource_type,
    operation.state,
    membership.created_at,
    operation.actor_user_id,
    operation.retention_mode,
    operation.retention_days::integer,
    operation.purge_eligible_at,
    operation.auto_purge_enabled_snapshot,
    operation.auto_purge_at,
    operation.purge_scheduled_at,
    operation.blocker_count,
    (
      caller.is_owner
      OR caller.role = 'admin'::public.org_member_role
      OR (
        caller.role = 'associate'::public.org_member_role
        AND membership.resource_type = 'document'::public.trash_resource_type
        AND membership.cause = 'direct'::public.resource_trash_cause
        AND operation.actor_user_id = auth.uid()
      )
    )
  FROM public.resource_trash_memberships AS membership
  JOIN public.trash_operations AS operation
    ON operation.org_id = membership.org_id
   AND operation.id = membership.operation_id
  WHERE membership.org_id = resource_org_id
    AND membership.id = active_membership_id
    AND membership.resource_type = p_resource_type
    AND membership.resource_id = p_resource_id
    AND membership.state = 'active'::public.resource_trash_membership_state
    AND operation.state IN (
      'trashed'::public.trash_operation_state,
      'restore_blocked'::public.trash_operation_state,
      'purge_scheduled'::public.trash_operation_state
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_exact_resource_trash_context(public.trash_resource_type,uuid,uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_exact_resource_trash_context(public.trash_resource_type,uuid,uuid) TO authenticated;

COMMENT ON FUNCTION public.get_exact_resource_trash_context(public.trash_resource_type,uuid,uuid) IS
  'Authenticated, read-only exact-resource Trash context. Validates membership, organisation, lineage, and restore-display policy; it grants no write authority.';

COMMIT;
