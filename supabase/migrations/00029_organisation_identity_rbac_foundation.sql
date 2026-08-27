-- Organisation administration identity/RBAC foundation.
-- This is an additive expand/backfill migration.  Legacy org_members remains
-- the application write path until the invitation and RLS cut-over tranche.
BEGIN;

CREATE TYPE public.organisation_membership_state AS ENUM ('active', 'suspended', 'removed');

CREATE TABLE public.user_profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
  display_name text,
  professional_title text,
  locale text NOT NULL DEFAULT 'en-IN',
  timezone text NOT NULL DEFAULT 'Asia/Kolkata',
  revision bigint NOT NULL DEFAULT 1 CHECK (revision >= 1),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_profiles_display_name_length CHECK (display_name IS NULL OR char_length(display_name) <= 200),
  CONSTRAINT user_profiles_professional_title_length CHECK (professional_title IS NULL OR char_length(professional_title) <= 200)
);

CREATE TABLE public.organisation_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  role public.org_member_role NOT NULL DEFAULT 'associate',
  state public.organisation_membership_state NOT NULL DEFAULT 'active',
  generation integer NOT NULL,
  invited_through_id uuid,
  joined_at timestamptz NOT NULL DEFAULT now(),
  joined_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  suspended_at timestamptz,
  suspended_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  suspension_reason text,
  removed_at timestamptz,
  removed_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  removal_reason text,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision >= 1),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT organisation_memberships_generation_positive CHECK (generation > 0),
  CONSTRAINT organisation_memberships_generation_unique UNIQUE (org_id, user_id, generation),
  CONSTRAINT organisation_memberships_lifecycle_consistent CHECK (
    (state = 'active' AND suspended_at IS NULL AND suspended_by IS NULL AND suspension_reason IS NULL
      AND removed_at IS NULL AND removed_by IS NULL AND removal_reason IS NULL)
    OR (state = 'suspended' AND suspended_at IS NOT NULL
      AND removed_at IS NULL AND removed_by IS NULL AND removal_reason IS NULL)
    OR (state = 'removed' AND removed_at IS NOT NULL
      AND suspended_at IS NULL AND suspended_by IS NULL AND suspension_reason IS NULL)
  )
);

CREATE UNIQUE INDEX organisation_memberships_current_generation_unique
  ON public.organisation_memberships (org_id, user_id)
  WHERE state IN ('active', 'suspended');
CREATE UNIQUE INDEX organisation_memberships_one_current_org_per_user
  ON public.organisation_memberships (user_id)
  WHERE state IN ('active', 'suspended');
CREATE INDEX organisation_memberships_org_current_idx
  ON public.organisation_memberships (org_id, state, joined_at)
  WHERE state IN ('active', 'suspended');

ALTER TABLE public.organisations
  ADD COLUMN owner_membership_id uuid,
  ADD COLUMN revision bigint NOT NULL DEFAULT 1 CHECK (revision >= 1),
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now(),
  ADD CONSTRAINT organisations_owner_membership_id_fkey
    FOREIGN KEY (owner_membership_id) REFERENCES public.organisation_memberships(id)
    ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

CREATE OR REPLACE FUNCTION public.organisation_identity_set_revision()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    NEW.revision := OLD.revision + 1;
    NEW.updated_at := now();
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.organisations_identity_is_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.created_by IS DISTINCT FROM OLD.created_by
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'organisation id, creator, and creation timestamp are immutable';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER user_profiles_set_revision
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.organisation_identity_set_revision();
CREATE TRIGGER organisation_memberships_set_revision
  BEFORE UPDATE ON public.organisation_memberships
  FOR EACH ROW EXECUTE FUNCTION public.organisation_identity_set_revision();
CREATE TRIGGER organisations_set_revision
  BEFORE UPDATE ON public.organisations
  FOR EACH ROW EXECUTE FUNCTION public.organisation_identity_set_revision();
CREATE TRIGGER organisations_identity_immutable
  BEFORE UPDATE ON public.organisations
  FOR EACH ROW EXECUTE FUNCTION public.organisations_identity_is_immutable();

-- Seed the canonical history from the current legacy rows.  Do not infer email
-- or lifecycle history; the source table has neither.
INSERT INTO public.organisation_memberships (org_id, user_id, role, state, generation, joined_at)
SELECT m.org_id, m.user_id, m.role, 'active', 1, m.joined_at
FROM public.org_members AS m;

INSERT INTO public.user_profiles (user_id, display_name)
SELECT
  m.user_id,
  NULLIF(left(btrim(COALESCE(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name')), 200), '')
FROM public.org_members AS m
JOIN auth.users AS u ON u.id = m.user_id
ON CONFLICT (user_id) DO NOTHING;

UPDATE public.organisations AS o
SET owner_membership_id = membership.id,
    revision = o.revision + 1
FROM public.organisation_memberships AS membership
JOIN public.org_members AS legacy
  ON legacy.org_id = membership.org_id
 AND legacy.user_id = membership.user_id
WHERE o.id = membership.org_id
  AND o.created_by = membership.user_id
  AND legacy.role = 'admin'
  AND membership.role = 'admin'
  AND membership.state = 'active';

CREATE OR REPLACE FUNCTION public.assert_organisation_owner_eligible()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  checked_org_id uuid;
  checked_owner_id uuid;
BEGIN
  IF TG_TABLE_NAME = 'organisations' THEN
    checked_org_id := NEW.id;
    checked_owner_id := NEW.owner_membership_id;
  ELSE
    checked_owner_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;
    SELECT o.id, o.owner_membership_id INTO checked_org_id, checked_owner_id
    FROM public.organisations AS o
    WHERE o.owner_membership_id = checked_owner_id;
    IF checked_org_id IS NULL THEN
      RETURN NULL;
    END IF;
  END IF;

  IF checked_owner_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.organisation_memberships AS membership
    WHERE membership.id = checked_owner_id
      AND membership.org_id = checked_org_id
      AND membership.state = 'active'
      AND membership.role = 'admin'
  ) THEN
    RAISE EXCEPTION 'organisation owner must reference an active admin membership in the same organisation';
  END IF;
  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER organisations_owner_must_be_eligible
  AFTER INSERT OR UPDATE OF owner_membership_id ON public.organisations
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.assert_organisation_owner_eligible();
CREATE CONSTRAINT TRIGGER organisation_memberships_owner_must_remain_eligible
  AFTER INSERT OR UPDATE OR DELETE ON public.organisation_memberships
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.assert_organisation_owner_eligible();

-- Keep canonical membership history in step with the legacy application write
-- path until commands and legacy RLS are replaced in a later migration.
CREATE OR REPLACE FUNCTION public.sync_legacy_org_member_to_canonical()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  membership_id uuid;
  next_generation integer;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT id INTO membership_id
    FROM public.organisation_memberships
    WHERE org_id = NEW.org_id AND user_id = NEW.user_id
      AND state IN ('active', 'suspended')
    FOR UPDATE;

    IF membership_id IS NULL THEN
      SELECT COALESCE(max(generation), 0) + 1 INTO next_generation
      FROM public.organisation_memberships
      WHERE org_id = NEW.org_id AND user_id = NEW.user_id;
      INSERT INTO public.organisation_memberships (org_id, user_id, role, state, generation, joined_at, joined_by)
      VALUES (NEW.org_id, NEW.user_id, NEW.role, 'active', next_generation, NEW.joined_at, auth.uid())
      RETURNING id INTO membership_id;
    ELSE
      UPDATE public.organisation_memberships
      SET role = NEW.role,
          revision = revision + 1
      WHERE id = membership_id AND role IS DISTINCT FROM NEW.role;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.user_profiles WHERE user_id = NEW.user_id
    ) THEN
      INSERT INTO public.user_profiles (user_id) VALUES (NEW.user_id);
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.organisations
      WHERE id = NEW.org_id AND created_by = NEW.user_id AND owner_membership_id IS NULL
    ) AND NEW.role = 'admin' THEN
      UPDATE public.organisations
      SET owner_membership_id = membership_id,
          revision = revision + 1
      WHERE id = NEW.org_id AND owner_membership_id IS NULL;
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    SELECT id INTO membership_id
    FROM public.organisation_memberships
    WHERE org_id = NEW.org_id AND user_id = NEW.user_id
      AND state IN ('active', 'suspended')
    FOR UPDATE;
    IF membership_id IS NULL THEN
      RAISE EXCEPTION 'legacy membership has no current canonical membership';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.organisations
      WHERE owner_membership_id = membership_id
    ) AND NEW.role <> 'admin' THEN
      RAISE EXCEPTION 'cannot demote the current organisation owner below admin';
    END IF;
    UPDATE public.organisation_memberships
    SET role = NEW.role,
        revision = revision + 1
    WHERE id = membership_id AND role IS DISTINCT FROM NEW.role;
    RETURN NEW;
  ELSE
    SELECT id INTO membership_id
    FROM public.organisation_memberships
    WHERE org_id = OLD.org_id AND user_id = OLD.user_id
      AND state IN ('active', 'suspended')
    FOR UPDATE;
    IF membership_id IS NULL THEN
      RAISE EXCEPTION 'legacy membership has no current canonical membership';
    END IF;
    IF EXISTS (SELECT 1 FROM public.organisations WHERE owner_membership_id = membership_id) THEN
      RAISE EXCEPTION 'cannot delete the current organisation owner through legacy membership path';
    END IF;
    UPDATE public.organisation_memberships
    SET state = 'removed',
        suspended_at = NULL,
        suspended_by = NULL,
        suspension_reason = NULL,
        removed_at = now(),
        removed_by = auth.uid(),
        removal_reason = 'legacy org_members delete',
        revision = revision + 1
    WHERE id = membership_id;
    RETURN OLD;
  END IF;
END;
$$;

CREATE TRIGGER org_members_sync_canonical_after_insert
  AFTER INSERT ON public.org_members
  FOR EACH ROW EXECUTE FUNCTION public.sync_legacy_org_member_to_canonical();
CREATE TRIGGER org_members_sync_canonical_after_role_update
  AFTER UPDATE OF role ON public.org_members
  FOR EACH ROW WHEN (OLD.role IS DISTINCT FROM NEW.role)
  EXECUTE FUNCTION public.sync_legacy_org_member_to_canonical();
CREATE TRIGGER org_members_sync_canonical_after_delete
  AFTER DELETE ON public.org_members
  FOR EACH ROW EXECUTE FUNCTION public.sync_legacy_org_member_to_canonical();

-- Harden inherited helpers while preserving the legacy RLS and action surface
-- during the dual-write window.
CREATE OR REPLACE FUNCTION public.is_org_member(check_org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.org_members AS member
    WHERE member.org_id = check_org_id AND member.user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.is_org_admin(check_org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.org_members AS member
    WHERE member.org_id = check_org_id
      AND member.user_id = auth.uid()
      AND member.role = 'admin'
  );
$$;

CREATE OR REPLACE FUNCTION public.my_org_ids()
RETURNS uuid[]
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT array_agg(member.org_id) FROM public.org_members AS member
  WHERE member.user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.is_email_in_any_org(search_email text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM auth.users AS auth_user
    JOIN public.org_members AS member ON member.user_id = auth_user.id
    WHERE lower(auth_user.email) = lower(search_email)
  );
$$;

CREATE OR REPLACE FUNCTION public.handle_new_org()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  INSERT INTO public.org_members (org_id, user_id, role)
  VALUES (NEW.id, NEW.created_by, 'admin');
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.generate_matter_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  client_name_val text;
  consonants text;
  abbr text;
  fy_raw text;
  fy_short text;
  seq int;
BEGIN
  SELECT name INTO client_name_val FROM public.clients WHERE id = NEW.client_id;

  consonants := upper(regexp_replace(client_name_val, '[AaEeIiOoUu\s\W0-9]', '', 'g'));
  abbr := left(consonants, 3);
  IF length(abbr) < 3 THEN
    abbr := upper(left(regexp_replace(client_name_val, '[^A-Za-z0-9]', '', 'g'), 3));
  END IF;
  abbr := rpad(abbr, 3, 'X');

  fy_raw := regexp_replace(NEW.financial_year, '[^0-9]', '', 'g');
  IF length(fy_raw) >= 6 THEN
    fy_short := substring(fy_raw FROM 3 FOR 2) || substring(fy_raw FROM 5 FOR 2);
  ELSE
    fy_short := fy_raw;
  END IF;

  SELECT COUNT(*) + 1 INTO seq
  FROM public.matters
  WHERE org_id = NEW.org_id
    AND matter_code LIKE abbr || '-' || fy_short || '-%';

  NEW.matter_code := abbr || '-' || fy_short || '-' || lpad(seq::text, 2, '0');
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_active_org_member(check_org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.organisation_memberships AS membership
    WHERE membership.org_id = check_org_id
      AND membership.user_id = auth.uid()
      AND membership.state = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.get_my_organisation_context()
RETURNS TABLE (
  membership_id uuid,
  org_id uuid,
  role public.org_member_role,
  is_owner boolean,
  state public.organisation_membership_state,
  capability_version integer,
  capabilities text[],
  revision bigint
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT membership.id,
         membership.org_id,
         membership.role,
         (organisation.owner_membership_id = membership.id),
         membership.state,
         1,
         CASE
           WHEN membership.state <> 'active' THEN ARRAY[]::text[]
           WHEN organisation.owner_membership_id = membership.id THEN ARRAY[
             'team.view', 'team.invite.standard', 'team.role.manage_standard',
             'team.membership.suspend_standard', 'organisation.profile.manage',
             'organisation.operations.manage', 'team.invite.admin',
             'team.role.manage_admin', 'team.membership.manage_admin', 'team.ownership.transfer',
             'trash.purge'
           ]::text[]
           WHEN membership.role = 'admin' THEN ARRAY[
             'team.view', 'team.invite.standard', 'team.role.manage_standard',
             'team.membership.suspend_standard', 'organisation.profile.manage',
             'organisation.operations.manage', 'trash.purge'
           ]::text[]
           ELSE ARRAY['team.view']::text[] END,
         membership.revision
  FROM public.organisation_memberships AS membership
  JOIN public.organisations AS organisation ON organisation.id = membership.org_id
  WHERE membership.user_id = auth.uid()
    AND membership.state IN ('active', 'suspended');
$$;

CREATE OR REPLACE FUNCTION public.has_team_capability(check_org_id uuid, requested_capability text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.get_my_organisation_context() AS context
    WHERE context.org_id = check_org_id
      AND requested_capability = ANY (context.capabilities)
  );
$$;

CREATE OR REPLACE FUNCTION public.get_my_team_members()
RETURNS TABLE (
  membership_id uuid,
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
    SELECT context.org_id, context.is_owner, context.role
    FROM public.get_my_organisation_context() AS context
    WHERE context.state = 'active' AND 'team.view' = ANY (context.capabilities)
  )
  SELECT membership.id,
         profile.display_name,
         profile.professional_title,
         membership.role,
         (organisation.owner_membership_id = membership.id),
         membership.state,
         membership.joined_at,
         membership.revision,
         CASE
           WHEN membership.state <> 'active' THEN ARRAY[]::text[]
           WHEN organisation.owner_membership_id = membership.id THEN ARRAY[
             'team.view', 'team.invite.standard', 'team.role.manage_standard',
             'team.membership.suspend_standard', 'organisation.profile.manage',
             'organisation.operations.manage', 'team.invite.admin',
             'team.role.manage_admin', 'team.membership.manage_admin', 'team.ownership.transfer',
             'trash.purge'
           ]::text[]
           WHEN membership.role = 'admin' THEN ARRAY[
             'team.view', 'team.invite.standard', 'team.role.manage_standard',
             'team.membership.suspend_standard', 'organisation.profile.manage',
             'organisation.operations.manage', 'trash.purge'
           ]::text[]
           ELSE ARRAY['team.view']::text[] END,
         CASE WHEN (caller.is_owner OR caller.role = 'admin' OR membership.user_id = auth.uid())
                   AND auth_user.email_confirmed_at IS NOT NULL
              THEN auth_user.email END
  FROM caller
  JOIN public.organisation_memberships AS membership
    ON membership.org_id = caller.org_id
  JOIN public.organisations AS organisation ON organisation.id = membership.org_id
  LEFT JOIN public.user_profiles AS profile ON profile.user_id = membership.user_id
  LEFT JOIN auth.users AS auth_user ON auth_user.id = membership.user_id
  WHERE membership.state = 'active'
     OR (membership.state = 'suspended' AND (caller.is_owner OR caller.role = 'admin'));
$$;

CREATE VIEW public.organisation_identity_cutover_diagnostics AS
  SELECT 'organisation_missing_eligible_owner'::text AS issue_code, o.id AS org_id,
         NULL::uuid AS user_id, o.owner_membership_id AS membership_id, '{}'::jsonb AS detail
  FROM public.organisations AS o
  WHERE NOT EXISTS (
    SELECT 1 FROM public.organisation_memberships AS m
    WHERE m.id = o.owner_membership_id AND m.org_id = o.id AND m.role = 'admin' AND m.state = 'active'
  )
  UNION ALL
  SELECT 'owner_pointer_invalid', o.id, NULL::uuid, o.owner_membership_id, '{}'::jsonb
  FROM public.organisations AS o
  WHERE o.owner_membership_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.organisation_memberships AS m
    WHERE m.id = o.owner_membership_id AND m.org_id = o.id AND m.role = 'admin' AND m.state = 'active'
  )
  UNION ALL
  SELECT 'legacy_membership_missing_canonical', legacy.org_id, legacy.user_id, NULL::uuid, '{}'::jsonb
  FROM public.org_members AS legacy
  WHERE NOT EXISTS (
    SELECT 1 FROM public.organisation_memberships AS m
    WHERE m.org_id = legacy.org_id AND m.user_id = legacy.user_id AND m.state IN ('active', 'suspended')
  )
  UNION ALL
  SELECT 'canonical_membership_missing_legacy', m.org_id, m.user_id, m.id, '{}'::jsonb
  FROM public.organisation_memberships AS m
  WHERE m.state IN ('active', 'suspended') AND NOT EXISTS (
    SELECT 1 FROM public.org_members AS legacy WHERE legacy.org_id = m.org_id AND legacy.user_id = m.user_id
  )
  UNION ALL
  SELECT 'legacy_canonical_role_mismatch', legacy.org_id, legacy.user_id, m.id,
         jsonb_build_object('legacy_role', legacy.role, 'canonical_role', m.role)
  FROM public.org_members AS legacy
  JOIN public.organisation_memberships AS m
    ON m.org_id = legacy.org_id AND m.user_id = legacy.user_id AND m.state IN ('active', 'suspended')
  WHERE m.role <> legacy.role
  UNION ALL
  SELECT 'current_member_missing_profile', m.org_id, m.user_id, m.id, '{}'::jsonb
  FROM public.organisation_memberships AS m
  WHERE m.state IN ('active', 'suspended')
    AND NOT EXISTS (SELECT 1 FROM public.user_profiles AS p WHERE p.user_id = m.user_id)
  UNION ALL
  SELECT 'multiple_current_memberships_for_org_user', m.org_id, m.user_id, NULL::uuid,
         jsonb_build_object('count', count(*))
  FROM public.organisation_memberships AS m
  WHERE m.state IN ('active', 'suspended')
  GROUP BY m.org_id, m.user_id HAVING count(*) > 1
  UNION ALL
  SELECT 'multiple_current_organisations_for_user', NULL::uuid, m.user_id, NULL::uuid,
         jsonb_build_object('count', count(*))
  FROM public.organisation_memberships AS m
  WHERE m.state IN ('active', 'suspended')
  GROUP BY m.user_id HAVING count(*) > 1;

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organisation_memberships ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_profiles_select_self ON public.user_profiles
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY organisation_memberships_select_self ON public.organisation_memberships
  FOR SELECT TO authenticated USING (user_id = auth.uid());

REVOKE ALL ON TABLE public.user_profiles, public.organisation_memberships FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.user_profiles, public.organisation_memberships TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_profiles, public.organisation_memberships TO service_role;
-- Migration 00002 granted UPDATE on every public table to authenticated.  Keep
-- the legacy organisation-name edit path, but prevent direct ownership and
-- revision/identity writes until trusted administration commands replace it.
REVOKE UPDATE ON TABLE public.organisations FROM anon, authenticated;
GRANT UPDATE (name) ON TABLE public.organisations TO authenticated;
REVOKE ALL ON TABLE public.organisation_identity_cutover_diagnostics FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.organisation_identity_cutover_diagnostics TO service_role;

REVOKE ALL ON FUNCTION public.is_active_org_member(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_organisation_context() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.has_team_capability(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_team_members() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_org_member(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_org_admin(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.my_org_ids() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_email_in_any_org(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_new_org() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.generate_matter_code() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.organisation_identity_set_revision() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.organisations_identity_is_immutable() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.assert_organisation_owner_eligible() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_legacy_org_member_to_canonical() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_active_org_member(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_organisation_context() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.has_team_capability(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_team_members() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_org_member(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_org_admin(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.my_org_ids() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_email_in_any_org(text) TO service_role;

COMMENT ON TABLE public.user_profiles IS 'Personal profile data only; authentication email and provider/security data remain in auth.';
COMMENT ON TABLE public.organisation_memberships IS 'Canonical, generation-preserving organisation membership history during legacy org_members dual-write.';
COMMENT ON VIEW public.organisation_identity_cutover_diagnostics IS 'Service-only expand-phase drift and unsafe-owner report; clear before legacy cut-over.';

COMMIT;
