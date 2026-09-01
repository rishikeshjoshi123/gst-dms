-- Run after `npx supabase db reset --local --no-seed` on a disposable database.
-- The fixture rolls back all data; it verifies creation, acceptance, rejoin,
-- compatibility history, validation, privacy, and immutable snapshots.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000','d2100000-0000-0000-0000-000000000001','authenticated','authenticated','notice-owner@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','d2100000-0000-0000-0000-000000000002','authenticated','authenticated','notice-invite@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','d2100000-0000-0000-0000-000000000003','authenticated','authenticated','notice-rejoin@test.invalid','x',now(),'{}','{}',now(),now());

-- Existing history is deliberately not backfilled with invented acceptance.
INSERT INTO public.organisations(id,name,created_by)
VALUES ('d2200000-0000-0000-0000-000000000001','Notice snapshots','d2100000-0000-0000-0000-000000000001');
UPDATE public.organisations AS organisation
SET owner_membership_id = membership.id
FROM public.organisation_memberships AS membership
WHERE organisation.id = 'd2200000-0000-0000-0000-000000000001'
  AND membership.org_id = organisation.id
  AND membership.user_id = 'd2100000-0000-0000-0000-000000000001';

DO $creation$
DECLARE
  v_owner public.organisation_memberships%ROWTYPE;
  v_settings public.organisation_operational_settings%ROWTYPE;
  v_blocked boolean := false;
BEGIN
  SELECT * INTO v_owner FROM public.organisation_memberships
  WHERE org_id = 'd2200000-0000-0000-0000-000000000001'
    AND user_id = 'd2100000-0000-0000-0000-000000000001';
  SELECT * INTO v_settings FROM public.organisation_operational_settings
  WHERE org_id = 'd2200000-0000-0000-0000-000000000001';
  IF v_owner.departure_notice_days <> 30
     OR v_owner.departure_notice_policy_version <> 1
     OR v_owner.departure_notice_accepted_at IS DISTINCT FROM v_owner.joined_at
     OR v_settings.departure_notice_days <> 30
     OR v_settings.departure_notice_policy_version <> 1 THEN
    RAISE EXCEPTION 'organisation creation did not snapshot the default departure policy';
  END IF;
  BEGIN
    UPDATE public.organisation_operational_settings
    SET departure_notice_days = 45
    WHERE org_id = v_settings.org_id;
  EXCEPTION WHEN check_violation OR raise_exception THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'invalid departure notice policy was accepted';
  END IF;
END $creation$;

-- A prospective edit has a new policy version, but does not drift the owner.
UPDATE public.organisation_operational_settings
SET departure_notice_days = 60
WHERE org_id = 'd2200000-0000-0000-0000-000000000001';
DO $prospective$
BEGIN
  IF (SELECT departure_notice_days || ':' || departure_notice_policy_version
      FROM public.organisation_operational_settings
      WHERE org_id = 'd2200000-0000-0000-0000-000000000001') <> '60:2'
     OR (SELECT departure_notice_days || ':' || departure_notice_policy_version
         FROM public.organisation_memberships
         WHERE org_id = 'd2200000-0000-0000-0000-000000000001'
           AND user_id = 'd2100000-0000-0000-0000-000000000001') <> '30:1' THEN
    RAISE EXCEPTION 'prospective policy edit drifted an existing membership snapshot';
  END IF;
END $prospective$;

-- The current invite-acceptance writer reaches the canonical snapshot fence.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','d2100000-0000-0000-0000-000000000001',true);
DO $invite$
DECLARE v_result record;
BEGIN
  SELECT * INTO v_result FROM public.create_organisation_invite(
    'notice-invite@test.invalid','associate',repeat('a',64),'d2300000-0000-0000-0000-000000000001'
  );
  IF v_result.code <> 'created' THEN
    RAISE EXCEPTION 'invite fixture creation failed: %', v_result.code;
  END IF;
END $invite$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','d2100000-0000-0000-0000-000000000002',true);
DO $accept$
DECLARE v_result record;
BEGIN
  SELECT * INTO v_result FROM public.accept_organisation_invite(
    NULL,repeat('a',64),NULL,'d2300000-0000-0000-0000-000000000002'
  );
  IF v_result.code <> 'accepted' THEN
    RAISE EXCEPTION 'invite acceptance fixture failed: %', v_result.code;
  END IF;
END $accept$;
RESET ROLE;

-- The retained legacy writer is still canonical for direct/rejoin membership
-- synchronization, so both generations must snapshot the current policy.
INSERT INTO public.org_members(org_id,user_id,role)
VALUES ('d2200000-0000-0000-0000-000000000001','d2100000-0000-0000-0000-000000000003','viewer');
DELETE FROM public.org_members
WHERE org_id = 'd2200000-0000-0000-0000-000000000001'
  AND user_id = 'd2100000-0000-0000-0000-000000000003';
INSERT INTO public.org_members(org_id,user_id,role)
VALUES ('d2200000-0000-0000-0000-000000000001','d2100000-0000-0000-0000-000000000003','viewer');

DO $snapshots$
DECLARE v_immutable boolean := false;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.organisation_memberships AS membership
    WHERE membership.org_id = 'd2200000-0000-0000-0000-000000000001'
      AND membership.user_id IN ('d2100000-0000-0000-0000-000000000002','d2100000-0000-0000-0000-000000000003')
      AND (
        membership.departure_notice_days <> 60
        OR membership.departure_notice_policy_version <> 2
        OR membership.departure_notice_accepted_at IS DISTINCT FROM membership.joined_at
      )
  ) OR (SELECT count(*) FROM public.organisation_memberships
        WHERE org_id = 'd2200000-0000-0000-0000-000000000001'
          AND user_id = 'd2100000-0000-0000-0000-000000000003') <> 2 THEN
    RAISE EXCEPTION 'invite acceptance or legacy rejoin missed the policy snapshot';
  END IF;
  BEGIN
    UPDATE public.organisation_memberships
    SET departure_notice_days = 30
    WHERE org_id = 'd2200000-0000-0000-0000-000000000001'
      AND user_id = 'd2100000-0000-0000-0000-000000000002';
  EXCEPTION WHEN raise_exception THEN
    v_immutable := true;
  END;
  IF NOT v_immutable THEN
    RAISE EXCEPTION 'membership notice snapshot was mutable';
  END IF;
END $snapshots$;

SET LOCAL ROLE authenticated;
DO $privacy$
DECLARE v_blocked boolean := false;
BEGIN
  BEGIN
    SELECT departure_notice_days
    FROM public.organisation_operational_settings
    WHERE org_id = 'd2200000-0000-0000-0000-000000000001';
  EXCEPTION WHEN insufficient_privilege THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'authenticated caller read private operational departure policy directly';
  END IF;
END $privacy$;
RESET ROLE;

ROLLBACK;
