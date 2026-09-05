-- Run after `npx supabase db reset --local --no-seed` on a disposable database.
-- Requires a database owner/service role capable of inserting isolated auth.users
-- fixtures. This script rolls back all fixtures and must not target a shared DB.
BEGIN;

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000', 'd5100000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'identity-owner@test.invalid', 'x', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'd5100000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'identity-member@test.invalid', 'x', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'd5100000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'identity-other@test.invalid', 'x', now(), '{}', '{}', now(), now());

INSERT INTO public.organisations (id, name, created_by)
VALUES
  ('d5200000-0000-0000-0000-000000000001', 'Membership identity fixture', 'd5100000-0000-0000-0000-000000000001');
INSERT INTO public.org_members (org_id, user_id, role)
VALUES ('d5200000-0000-0000-0000-000000000001', 'd5100000-0000-0000-0000-000000000002', 'viewer');

DO $test$
DECLARE
  v_member public.organisation_memberships%ROWTYPE;
  v_case uuid;
  v_identity_rewrite_blocked boolean;
  v_revision bigint;
BEGIN
  SELECT * INTO v_member
  FROM public.organisation_memberships
  WHERE org_id = 'd5200000-0000-0000-0000-000000000001'
    AND user_id = 'd5100000-0000-0000-0000-000000000002'
    AND state = 'active';

  IF v_member.id IS NULL
     OR v_member.departure_notice_days IS NULL
     OR v_member.departure_notice_policy_version IS NULL
     OR v_member.departure_notice_accepted_at IS NULL THEN
    RAISE EXCEPTION 'fixture membership did not receive its managed notice snapshot';
  END IF;

  INSERT INTO public.membership_departure_cases (
    org_id, membership_id, submitted_by_user_id, notice_snapshot_state,
    notice_days, notice_policy_version, notice_accepted_at, effective_date
  ) VALUES (
    v_member.org_id, v_member.id, v_member.user_id, 'accepted',
    v_member.departure_notice_days, v_member.departure_notice_policy_version,
    v_member.departure_notice_accepted_at, current_date + 30
  ) RETURNING id INTO v_case;

  -- Every identity and generation-creation fact must reject a privileged rewrite.
  BEGIN
    UPDATE public.organisation_memberships
    SET id = 'd5300000-0000-0000-0000-000000000001'
    WHERE id = v_member.id;
  EXCEPTION WHEN raise_exception THEN v_identity_rewrite_blocked := true;
  END;
  IF NOT COALESCE(v_identity_rewrite_blocked, false) THEN
    RAISE EXCEPTION 'membership id rewrite was accepted';
  END IF;

  v_identity_rewrite_blocked := false;
  BEGIN
    UPDATE public.organisation_memberships
    SET org_id = 'd5200000-0000-0000-0000-000000000002'
    WHERE id = v_member.id;
  EXCEPTION WHEN raise_exception THEN v_identity_rewrite_blocked := true;
  END;
  IF NOT v_identity_rewrite_blocked THEN RAISE EXCEPTION 'membership organisation rewrite was accepted'; END IF;

  v_identity_rewrite_blocked := false;
  BEGIN
    UPDATE public.organisation_memberships
    SET user_id = 'd5100000-0000-0000-0000-000000000003'
    WHERE id = v_member.id;
  EXCEPTION WHEN raise_exception THEN v_identity_rewrite_blocked := true;
  END;
  IF NOT v_identity_rewrite_blocked THEN RAISE EXCEPTION 'membership user rewrite was accepted'; END IF;

  v_identity_rewrite_blocked := false;
  BEGIN
    UPDATE public.organisation_memberships SET generation = v_member.generation + 1 WHERE id = v_member.id;
  EXCEPTION WHEN raise_exception THEN v_identity_rewrite_blocked := true;
  END;
  IF NOT v_identity_rewrite_blocked THEN RAISE EXCEPTION 'membership generation rewrite was accepted'; END IF;

  v_identity_rewrite_blocked := false;
  BEGIN
    UPDATE public.organisation_memberships SET joined_at = v_member.joined_at + interval '1 second' WHERE id = v_member.id;
  EXCEPTION WHEN raise_exception THEN v_identity_rewrite_blocked := true;
  END;
  IF NOT v_identity_rewrite_blocked THEN RAISE EXCEPTION 'membership joined-at rewrite was accepted'; END IF;

  v_identity_rewrite_blocked := false;
  BEGIN
    UPDATE public.organisation_memberships SET created_at = v_member.created_at + interval '1 second' WHERE id = v_member.id;
  EXCEPTION WHEN raise_exception THEN v_identity_rewrite_blocked := true;
  END;
  IF NOT v_identity_rewrite_blocked THEN RAISE EXCEPTION 'membership created-at rewrite was accepted'; END IF;

  -- The linked departure case still resolves the original identity after all
  -- attempted privileged rewrites.
  IF NOT EXISTS (
    SELECT 1
    FROM public.membership_departure_cases AS departure_case
    JOIN public.organisation_memberships AS membership ON membership.id = departure_case.membership_id
    WHERE departure_case.id = v_case
      AND membership.org_id = v_member.org_id
      AND membership.user_id = v_member.user_id
      AND membership.generation = v_member.generation
  ) THEN
    RAISE EXCEPTION 'departure case lineage was reinterpreted by a membership update';
  END IF;

  -- Existing lifecycle-compatible canonical and legacy bridge updates remain valid.
  SELECT revision INTO v_revision FROM public.organisation_memberships WHERE id = v_member.id;
  UPDATE public.organisation_memberships
  SET state = 'suspended', suspended_at = now(), suspended_by = 'd5100000-0000-0000-0000-000000000001'
  WHERE id = v_member.id;
  UPDATE public.organisation_memberships
  SET state = 'active', suspended_at = NULL, suspended_by = NULL, suspension_reason = NULL
  WHERE id = v_member.id;
  UPDATE public.org_members SET role = 'associate'
  WHERE org_id = v_member.org_id AND user_id = v_member.user_id;
  IF NOT EXISTS (
    SELECT 1 FROM public.organisation_memberships
    WHERE id = v_member.id
      AND role = 'associate'
      AND state = 'active'
      AND revision > v_revision
      AND departure_notice_days = v_member.departure_notice_days
      AND departure_notice_policy_version = v_member.departure_notice_policy_version
      AND departure_notice_accepted_at = v_member.departure_notice_accepted_at
  ) THEN
    RAISE EXCEPTION 'permitted membership lifecycle or legacy role bridge regressed';
  END IF;
END $test$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', 'd5100000-0000-0000-0000-000000000002', true);
DO $rls$
DECLARE v_blocked boolean := false;
BEGIN
  BEGIN
    UPDATE public.organisation_memberships
    SET generation = 99
    WHERE org_id = 'd5200000-0000-0000-0000-000000000001'
      AND user_id = auth.uid();
  EXCEPTION WHEN insufficient_privilege THEN v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'authenticated direct membership identity update was accepted';
  END IF;
END $rls$;
RESET ROLE;

ROLLBACK;
