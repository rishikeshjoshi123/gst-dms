-- Give live collaboration consumers a tenant-safe user locator so they do not
-- reconstruct names/emails through the global Auth admin directory.

DROP FUNCTION public.get_my_team_members();
CREATE FUNCTION public.get_my_team_members()
RETURNS TABLE (
  membership_id uuid,
  user_id uuid,
  display_name text,
  professional_title text,
  role public.org_member_role,
  is_owner boolean,
  state public.organisation_membership_state,
  joined_at timestamptz,
  revision bigint,
  capabilities text[],
  authorised_email text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  WITH caller AS (
    SELECT context.org_id,context.is_owner,context.role
    FROM public.get_my_organisation_context() AS context
    WHERE context.state='active' AND 'team.view'=ANY(context.capabilities)
  )
  SELECT membership.id,membership.user_id,profile.display_name,profile.professional_title,
    membership.role,(organisation.owner_membership_id=membership.id),membership.state,
    membership.joined_at,membership.revision,
    public.organisation_member_capabilities(
      membership.role,organisation.owner_membership_id=membership.id,membership.state
    ),
    CASE WHEN (caller.is_owner OR caller.role='admin' OR membership.user_id=auth.uid())
      AND auth_user.email_confirmed_at IS NOT NULL THEN auth_user.email END
  FROM caller
  JOIN public.organisation_memberships AS membership ON membership.org_id=caller.org_id
  JOIN public.organisations AS organisation ON organisation.id=membership.org_id
  LEFT JOIN public.user_profiles AS profile ON profile.user_id=membership.user_id
  LEFT JOIN auth.users AS auth_user ON auth_user.id=membership.user_id
  WHERE membership.state='active'
    OR (membership.state='suspended' AND (caller.is_owner OR caller.role='admin'));
$$;

REVOKE ALL ON FUNCTION public.get_my_team_members() FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_my_team_members() TO authenticated;
COMMENT ON FUNCTION public.get_my_team_members() IS
  'Tenant-safe live member directory. user_id supports collaboration locators; email remains self/admin scoped and removed members are omitted.';
