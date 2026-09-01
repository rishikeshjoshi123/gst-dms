-- Run only through organisation_departure_notice_snapshots_concurrency.sh.
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000','d3100000-0000-0000-0000-000000000001','authenticated','authenticated','notice-race-owner@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','d3100000-0000-0000-0000-000000000002','authenticated','authenticated','notice-race-invite@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by)
VALUES ('d3200000-0000-0000-0000-000000000001','Notice snapshot race','d3100000-0000-0000-0000-000000000001');
UPDATE public.organisations AS organisation
SET owner_membership_id = membership.id
FROM public.organisation_memberships AS membership
WHERE organisation.id = 'd3200000-0000-0000-0000-000000000001'
  AND membership.org_id = organisation.id
  AND membership.user_id = 'd3100000-0000-0000-0000-000000000001';
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','d3100000-0000-0000-0000-000000000001',true);
DO $invite$
DECLARE v_result record;
BEGIN
  SELECT * INTO v_result FROM public.create_organisation_invite(
    'notice-race-invite@test.invalid','associate',repeat('b',64),'d3300000-0000-0000-0000-000000000001'
  );
  IF v_result.code <> 'created' THEN
    RAISE EXCEPTION 'concurrency invite fixture failed: %', v_result.code;
  END IF;
END $invite$;
COMMIT;
