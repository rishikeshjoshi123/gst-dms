-- Run after `npx supabase db reset --local --no-seed` on a disposable DB.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000','d4100000-0000-0000-0000-000000000001','authenticated','authenticated','case-owner@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','d4100000-0000-0000-0000-000000000002','authenticated','authenticated','case-member@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','d4100000-0000-0000-0000-000000000003','authenticated','authenticated','case-legacy@test.invalid','x',now(),'{}','{}',now(),now());

INSERT INTO public.organisations(id,name,created_by)
VALUES ('d4200000-0000-0000-0000-000000000001','Departure case foundation','d4100000-0000-0000-0000-000000000001');
INSERT INTO public.org_members(org_id,user_id,role)
VALUES ('d4200000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000002','associate');

DO $accepted_snapshot$
DECLARE v_member public.organisation_memberships%ROWTYPE; v_case uuid; v_immutable boolean := false; v_id_immutable boolean := false; v_lineage boolean := false; v_duplicate boolean := false;
BEGIN
  SELECT * INTO v_member FROM public.organisation_memberships
  WHERE org_id='d4200000-0000-0000-0000-000000000001' AND user_id='d4100000-0000-0000-0000-000000000002';
  INSERT INTO public.membership_departure_cases(org_id,membership_id,submitted_by_user_id,notice_snapshot_state,notice_days,notice_policy_version,notice_accepted_at,effective_date)
  VALUES(v_member.org_id,v_member.id,v_member.user_id,'accepted',v_member.departure_notice_days,v_member.departure_notice_policy_version,v_member.departure_notice_accepted_at,(now() AT TIME ZONE 'Asia/Kolkata')::date+v_member.departure_notice_days)
  RETURNING id INTO v_case;
  BEGIN
    UPDATE public.membership_departure_cases SET notice_days=60 WHERE id=v_case;
  EXCEPTION WHEN raise_exception THEN v_immutable := true;
  END;
  BEGIN
    UPDATE public.membership_departure_cases SET id=gen_random_uuid() WHERE id=v_case;
  EXCEPTION WHEN raise_exception THEN v_id_immutable := true;
  END;
  BEGIN
    INSERT INTO public.membership_departure_cases(org_id,membership_id,submitted_by_user_id,notice_snapshot_state,notice_days,notice_policy_version,notice_accepted_at,effective_date)
    VALUES(v_member.org_id,v_member.id,v_member.user_id,'accepted',v_member.departure_notice_days,v_member.departure_notice_policy_version+1,v_member.departure_notice_accepted_at,current_date+30);
  EXCEPTION WHEN raise_exception THEN v_lineage := true;
  END;
  BEGIN
    INSERT INTO public.membership_departure_cases(org_id,membership_id,submitted_by_user_id,notice_snapshot_state,notice_days,notice_policy_version,notice_accepted_at,effective_date)
    VALUES(v_member.org_id,v_member.id,v_member.user_id,'accepted',v_member.departure_notice_days,v_member.departure_notice_policy_version,v_member.departure_notice_accepted_at,current_date+30);
  EXCEPTION WHEN unique_violation THEN v_duplicate := true;
  END;
  IF NOT v_immutable OR NOT v_id_immutable OR NOT v_lineage OR NOT v_duplicate THEN RAISE EXCEPTION 'accepted departure case invariant was not enforced'; END IF;
END $accepted_snapshot$;

-- Pre-00112 history remains all-NULL and is explicitly representable only as
-- legacy-unavailable; no policy/version/date is invented.
SET LOCAL session_replication_role = replica;
INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at)
VALUES ('d4300000-0000-0000-0000-000000000003','d4200000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-000000000003','viewer','active',1,now());
SET LOCAL session_replication_role = origin;
INSERT INTO public.membership_departure_cases(org_id,membership_id,submitted_by_user_id,notice_snapshot_state)
VALUES ('d4200000-0000-0000-0000-000000000001','d4300000-0000-0000-0000-000000000003','d4100000-0000-0000-0000-000000000003','legacy_unavailable');
DO $legacy_snapshot$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.membership_departure_cases WHERE membership_id='d4300000-0000-0000-0000-000000000003' AND notice_snapshot_state='legacy_unavailable' AND notice_days IS NULL AND effective_date IS NULL) THEN
    RAISE EXCEPTION 'legacy NULL notice snapshot was not explicit';
  END IF;
END $legacy_snapshot$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','d4100000-0000-0000-0000-000000000002',true);
DO $rls$
DECLARE v_read_blocked boolean := false; v_write_blocked boolean := false;
BEGIN
  BEGIN
    PERFORM 1 FROM public.membership_departure_cases;
  EXCEPTION WHEN insufficient_privilege THEN v_read_blocked := true;
  END;
  BEGIN
    INSERT INTO public.membership_departure_cases(org_id,membership_id,submitted_by_user_id,notice_snapshot_state)
    VALUES ('d4200000-0000-0000-0000-000000000001','d4300000-0000-0000-0000-000000000003',auth.uid(),'legacy_unavailable');
  EXCEPTION WHEN insufficient_privilege THEN v_write_blocked := true;
  END;
  IF NOT v_read_blocked OR NOT v_write_blocked THEN RAISE EXCEPTION 'authenticated browser role bypassed departure-case table boundary'; END IF;
END $rls$;
RESET ROLE;

ROLLBACK;
