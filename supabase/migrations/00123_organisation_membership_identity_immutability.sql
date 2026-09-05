-- Organisation Administration prerequisite: a canonical membership generation
-- is a durable identity anchor for downstream history, including departure-case
-- lineage.  Lifecycle fields deliberately remain outside this fence.
BEGIN;

CREATE OR REPLACE FUNCTION public.organisation_membership_identity_is_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.org_id IS DISTINCT FROM OLD.org_id
     OR NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.generation IS DISTINCT FROM OLD.generation
     OR NEW.joined_at IS DISTINCT FROM OLD.joined_at
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'membership identity and generation creation facts are immutable';
  END IF;
  RETURN NEW;
END;
$$;

-- PostgreSQL executes same-event triggers alphabetically.  This trigger runs
-- before the existing revision and departure-notice snapshot triggers, so an
-- identity rewrite fails before either lifecycle-compatible trigger mutates NEW.
CREATE TRIGGER organisation_memberships_identity_immutable
  BEFORE UPDATE ON public.organisation_memberships
  FOR EACH ROW EXECUTE FUNCTION public.organisation_membership_identity_is_immutable();

REVOKE ALL ON FUNCTION public.organisation_membership_identity_is_immutable()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.organisation_membership_identity_is_immutable() IS
  'Rejects rewrites of canonical membership identity and generation creation facts while preserving role/state lifecycle updates.';
COMMENT ON TRIGGER organisation_memberships_identity_immutable ON public.organisation_memberships IS
  'Runs before revision and departure-notice triggers to keep a membership generation permanently bound to its identity.';

COMMIT;
