-- Organisation Administration prerequisite: the departure policy is private
-- and prospective, while every newly created membership generation carries an
-- immutable copy of the policy it accepted.  Departure cases remain a later
-- command tranche; this migration deliberately adds neither a case table nor
-- a browser-facing policy setter.
BEGIN;

ALTER TABLE public.organisation_operational_settings
  ADD COLUMN departure_notice_days smallint NOT NULL DEFAULT 30,
  ADD COLUMN departure_notice_policy_version bigint NOT NULL DEFAULT 1,
  ADD CONSTRAINT organisation_operational_settings_departure_notice_days_check
    CHECK (departure_notice_days IN (30, 60)),
  ADD CONSTRAINT org_operational_notice_policy_version_check
    CHECK (departure_notice_policy_version >= 1);

-- PostgreSQL executes same-event triggers alphabetically.  The inherited
-- `on_org_created` bridge writes org_members, so the private settings row must
-- be initialised before that bridge can create its canonical membership.
DROP TRIGGER organisations_initialise_operational_settings ON public.organisations;
CREATE TRIGGER a_organisations_initialise_operational_settings
  AFTER INSERT ON public.organisations
  FOR EACH ROW EXECUTE FUNCTION public.initialise_organisation_operational_settings();

-- Existing membership generations predate an accepted departure-policy
-- contract.  Retain an all-NULL compatibility state rather than inventing
-- historical consent; every later insert is completed by the trigger below.
ALTER TABLE public.organisation_memberships
  ADD COLUMN departure_notice_days smallint,
  ADD COLUMN departure_notice_policy_version bigint,
  ADD COLUMN departure_notice_accepted_at timestamptz,
  ADD CONSTRAINT organisation_memberships_departure_notice_snapshot_consistent
    CHECK (
      (
        departure_notice_days IS NULL
        AND departure_notice_policy_version IS NULL
        AND departure_notice_accepted_at IS NULL
      )
      OR (
        departure_notice_days IN (30, 60)
        AND departure_notice_policy_version >= 1
        AND departure_notice_accepted_at IS NOT NULL
      )
    );

-- Preserve the existing timezone/revision contract and give the prospective
-- policy its own immutable version.  A timezone-only update must not alter
-- what future membership generations accept; a notice-day change always
-- advances exactly one policy version.
CREATE OR REPLACE FUNCTION public.organisation_operational_settings_validate()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  NEW.timezone := btrim(NEW.timezone);
  IF NEW.timezone = ''
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = NEW.timezone) THEN
    RAISE EXCEPTION 'organisation operational timezone is invalid';
  END IF;
  IF NEW.departure_notice_days NOT IN (30, 60) THEN
    RAISE EXCEPTION 'organisation departure notice days must be 30 or 60';
  END IF;
  IF NEW.departure_notice_policy_version < 1 THEN
    RAISE EXCEPTION 'organisation departure notice policy version is invalid';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    NEW.org_id := OLD.org_id;
    NEW.revision := OLD.revision + 1;
    NEW.departure_notice_policy_version := CASE
      WHEN NEW.departure_notice_days IS DISTINCT FROM OLD.departure_notice_days
        THEN OLD.departure_notice_policy_version + 1
      ELSE OLD.departure_notice_policy_version
    END;
    NEW.updated_at := now();
  END IF;
  RETURN NEW;
END $$;

-- This boundary is intentionally on the canonical membership table, not on a
-- particular RPC.  The live organisation-creation, invite-acceptance, and
-- legacy rejoin paths all write through org_members and its canonical sync
-- trigger; any future privileged canonical writer receives the same fence.
CREATE OR REPLACE FUNCTION public.snapshot_membership_departure_notice()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_policy public.organisation_operational_settings%ROWTYPE;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.departure_notice_days IS DISTINCT FROM OLD.departure_notice_days
       OR NEW.departure_notice_policy_version IS DISTINCT FROM OLD.departure_notice_policy_version
       OR NEW.departure_notice_accepted_at IS DISTINCT FROM OLD.departure_notice_accepted_at THEN
      RAISE EXCEPTION 'membership departure notice snapshot is immutable';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.departure_notice_days IS NOT NULL
     OR NEW.departure_notice_policy_version IS NOT NULL
     OR NEW.departure_notice_accepted_at IS NOT NULL THEN
    RAISE EXCEPTION 'membership departure notice snapshot is database managed';
  END IF;

  -- SHARE conflicts with an operational-policy update.  Thus a concurrent
  -- policy edit can yield only its complete old or complete new tuple, never
  -- notice days from one policy version and a version from another.
  SELECT * INTO v_policy
  FROM public.organisation_operational_settings AS settings
  WHERE settings.org_id = NEW.org_id
  FOR SHARE;
  IF v_policy.org_id IS NULL THEN
    RAISE EXCEPTION 'organisation departure notice policy is unavailable'
      USING ERRCODE = 'integrity_constraint_violation';
  END IF;

  NEW.departure_notice_days := v_policy.departure_notice_days;
  NEW.departure_notice_policy_version := v_policy.departure_notice_policy_version;
  NEW.departure_notice_accepted_at := COALESCE(NEW.joined_at, now());
  RETURN NEW;
END $$;

CREATE TRIGGER organisation_memberships_snapshot_departure_notice
  BEFORE INSERT OR UPDATE OF departure_notice_days, departure_notice_policy_version, departure_notice_accepted_at
  ON public.organisation_memberships
  FOR EACH ROW EXECUTE FUNCTION public.snapshot_membership_departure_notice();

REVOKE ALL ON FUNCTION public.snapshot_membership_departure_notice() FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON COLUMN public.organisation_operational_settings.departure_notice_days IS 'Prospective departure notice policy: only 30 or 60 days; defaults to 30.';
COMMENT ON COLUMN public.organisation_operational_settings.departure_notice_policy_version IS 'Increments only when the prospective departure notice days change.';
COMMENT ON COLUMN public.organisation_memberships.departure_notice_days IS 'Immutable notice-days snapshot for generations created after migration 00112; NULL means pre-policy compatibility history.';
COMMENT ON COLUMN public.organisation_memberships.departure_notice_policy_version IS 'Immutable policy-version snapshot for generations created after migration 00112; NULL means pre-policy compatibility history.';
COMMENT ON COLUMN public.organisation_memberships.departure_notice_accepted_at IS 'Immutable accepted/joined instant for a post-00112 membership generation; NULL means pre-policy compatibility history.';
COMMENT ON FUNCTION public.snapshot_membership_departure_notice() IS 'Canonical membership-insert fence that atomically snapshots the private prospective departure policy.';

COMMIT;
