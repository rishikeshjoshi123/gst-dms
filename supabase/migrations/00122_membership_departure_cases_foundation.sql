-- Durable, private departure-case storage only. Command/RPC, early-release,
-- membership removal, and offboarding coordination are deliberately deferred.
BEGIN;

CREATE TYPE public.membership_departure_case_state AS ENUM (
  'active', 'withdrawn', 'offboarding_started', 'completed', 'failed_pending_cleanup'
);
CREATE TYPE public.membership_departure_notice_snapshot_state AS ENUM (
  'accepted', 'legacy_unavailable'
);

CREATE TABLE public.membership_departure_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  membership_id uuid NOT NULL REFERENCES public.organisation_memberships(id) ON DELETE RESTRICT,
  submitted_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  notice_snapshot_state public.membership_departure_notice_snapshot_state NOT NULL,
  notice_days smallint,
  notice_policy_version bigint,
  notice_accepted_at timestamptz,
  effective_date date,
  state public.membership_departure_case_state NOT NULL DEFAULT 'active',
  reason text,
  handover_note text,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision >= 1),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT membership_departure_cases_reason_length CHECK (reason IS NULL OR char_length(reason) <= 2000),
  CONSTRAINT membership_departure_cases_handover_note_length CHECK (handover_note IS NULL OR char_length(handover_note) <= 8000),
  CONSTRAINT membership_departure_cases_notice_snapshot_consistent CHECK (
    (notice_snapshot_state = 'accepted'
      AND notice_days IN (30, 60)
      AND notice_policy_version >= 1
      AND notice_accepted_at IS NOT NULL
      AND effective_date IS NOT NULL)
    OR (notice_snapshot_state = 'legacy_unavailable'
      AND notice_days IS NULL
      AND notice_policy_version IS NULL
      AND notice_accepted_at IS NULL
      AND effective_date IS NULL)
  )
);

-- Treat retryable cleanup and an in-progress coordinator handoff as open. A
-- later command/coordinator cannot accidentally create a second case for the
-- same immutable membership generation.
CREATE UNIQUE INDEX membership_departure_cases_one_open_generation
  ON public.membership_departure_cases (membership_id)
  WHERE state IN ('active', 'offboarding_started', 'failed_pending_cleanup');
CREATE INDEX membership_departure_cases_open_org_effective_date_idx
  ON public.membership_departure_cases (org_id, effective_date, created_at)
  WHERE state IN ('active', 'offboarding_started', 'failed_pending_cleanup');

CREATE OR REPLACE FUNCTION public.enforce_membership_departure_case_lineage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_membership public.organisation_memberships%ROWTYPE;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT * INTO v_membership
    FROM public.organisation_memberships AS membership
    WHERE membership.id = NEW.membership_id
    FOR KEY SHARE;
    IF v_membership.id IS NULL
       OR v_membership.org_id <> NEW.org_id
       OR v_membership.user_id <> NEW.submitted_by_user_id THEN
      RAISE EXCEPTION 'membership departure case lineage is invalid';
    END IF;
    IF NEW.notice_snapshot_state = 'accepted' AND (
      v_membership.departure_notice_days IS NULL
      OR v_membership.departure_notice_policy_version IS NULL
      OR v_membership.departure_notice_accepted_at IS NULL
      OR NEW.notice_days <> v_membership.departure_notice_days
      OR NEW.notice_policy_version <> v_membership.departure_notice_policy_version
      OR NEW.notice_accepted_at IS DISTINCT FROM v_membership.departure_notice_accepted_at
    ) THEN
      RAISE EXCEPTION 'membership departure case accepted notice snapshot is invalid';
    END IF;
    IF NEW.notice_snapshot_state = 'legacy_unavailable' AND (
      v_membership.departure_notice_days IS NOT NULL
      OR v_membership.departure_notice_policy_version IS NOT NULL
      OR v_membership.departure_notice_accepted_at IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'membership departure case legacy notice state is invalid';
    END IF;
  ELSE
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.org_id IS DISTINCT FROM OLD.org_id
       OR NEW.membership_id IS DISTINCT FROM OLD.membership_id
       OR NEW.submitted_by_user_id IS DISTINCT FROM OLD.submitted_by_user_id
       OR NEW.notice_snapshot_state IS DISTINCT FROM OLD.notice_snapshot_state
       OR NEW.notice_days IS DISTINCT FROM OLD.notice_days
       OR NEW.notice_policy_version IS DISTINCT FROM OLD.notice_policy_version
       OR NEW.notice_accepted_at IS DISTINCT FROM OLD.notice_accepted_at
       OR NEW.effective_date IS DISTINCT FROM OLD.effective_date
       OR NEW.reason IS DISTINCT FROM OLD.reason
       OR NEW.handover_note IS DISTINCT FROM OLD.handover_note
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'membership departure case facts and notice snapshot are immutable';
    END IF;
    IF (OLD.state = 'active' AND NEW.state NOT IN ('active', 'withdrawn', 'offboarding_started'))
       OR (OLD.state = 'offboarding_started' AND NEW.state NOT IN ('offboarding_started', 'completed', 'failed_pending_cleanup'))
       OR (OLD.state = 'failed_pending_cleanup' AND NEW.state NOT IN ('failed_pending_cleanup', 'offboarding_started'))
       OR (OLD.state IN ('withdrawn', 'completed') AND NEW.state <> OLD.state) THEN
      RAISE EXCEPTION 'membership departure case state transition is invalid';
    END IF;
    NEW.revision := OLD.revision + 1;
    NEW.updated_at := now();
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER membership_departure_cases_enforce_lineage
  BEFORE INSERT OR UPDATE ON public.membership_departure_cases
  FOR EACH ROW EXECUTE FUNCTION public.enforce_membership_departure_case_lineage();

ALTER TABLE public.membership_departure_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.membership_departure_cases FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.membership_departure_cases FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.enforce_membership_departure_case_lineage() FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE public.membership_departure_cases IS 'Private, membership-generation-bound departure case history. Future typed commands must derive tenant and actor from current canonical membership.';
COMMENT ON COLUMN public.membership_departure_cases.notice_snapshot_state IS 'accepted copies a post-00112 membership notice snapshot; legacy_unavailable explicitly preserves pre-policy NULL history without inventing consent.';
COMMENT ON INDEX public.membership_departure_cases_one_open_generation IS 'Prevents more than one active/coordinator-open departure case for a membership generation.';

COMMIT;
