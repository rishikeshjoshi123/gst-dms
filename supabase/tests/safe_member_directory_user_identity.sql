-- Run after migration 00126. The transaction is always rolled back.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
('00000000-0000-0000-0000-000000000000','bd000000-0000-0000-0000-000000000001','authenticated','authenticated','directory-owner@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bd000000-0000-0000-0000-000000000002','authenticated','authenticated','directory-associate@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bd000000-0000-0000-0000-000000000003','authenticated','authenticated','directory-admin@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bd000000-0000-0000-0000-000000000004','authenticated','authenticated','directory-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bd000000-0000-0000-0000-000000000005','authenticated','authenticated','directory-suspended@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bd000000-0000-0000-0000-000000000006','authenticated','authenticated','directory-removed@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bd000000-0000-0000-0000-000000000007','authenticated','authenticated','directory-foreign@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.user_profiles(user_id,display_name,professional_title) VALUES
('bd000000-0000-0000-0000-000000000001','Directory Owner','Partner'),
('bd000000-0000-0000-0000-000000000002','Directory Associate','Associate'),
('bd000000-0000-0000-0000-000000000003','Directory Admin','Administrator'),
('bd000000-0000-0000-0000-000000000004','Directory Viewer','Observer'),
('bd000000-0000-0000-0000-000000000005','Directory Suspended','Associate'),
('bd000000-0000-0000-0000-000000000006','Directory Removed','Associate'),
('bd000000-0000-0000-0000-000000000007','Directory Foreign','Partner');
INSERT INTO public.organisations(id,name,created_by) VALUES
('bd100000-0000-0000-0000-000000000001','Directory organisation','bd000000-0000-0000-0000-000000000001'),
('bd100000-0000-0000-0000-000000000002','Foreign directory organisation','bd000000-0000-0000-0000-000000000007');
INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at,suspended_at,suspended_by,suspension_reason,removed_at,removed_by,removal_reason)
VALUES
('bd110000-0000-0000-0000-000000000002','bd100000-0000-0000-0000-000000000001','bd000000-0000-0000-0000-000000000002','associate','active',1,now(),NULL,NULL,NULL,NULL,NULL,NULL),
('bd110000-0000-0000-0000-000000000003','bd100000-0000-0000-0000-000000000001','bd000000-0000-0000-0000-000000000003','admin','active',1,now(),NULL,NULL,NULL,NULL,NULL,NULL),
('bd110000-0000-0000-0000-000000000004','bd100000-0000-0000-0000-000000000001','bd000000-0000-0000-0000-000000000004','viewer','active',1,now(),NULL,NULL,NULL,NULL,NULL,NULL),
('bd110000-0000-0000-0000-000000000005','bd100000-0000-0000-0000-000000000001','bd000000-0000-0000-0000-000000000005','associate','suspended',1,now(),now(),'bd000000-0000-0000-0000-000000000001','fixture suspension',NULL,NULL,NULL),
('bd110000-0000-0000-0000-000000000006','bd100000-0000-0000-0000-000000000001','bd000000-0000-0000-0000-000000000006','associate','removed',1,now(),NULL,NULL,NULL,now(),'bd000000-0000-0000-0000-000000000001','fixture removal');
UPDATE public.organisations AS organisation SET owner_membership_id=membership.id
FROM public.organisation_memberships AS membership
WHERE organisation.id=membership.org_id AND membership.user_id=organisation.created_by;

DO $privilege$
BEGIN
  IF has_function_privilege('service_role','public.get_my_team_members()','EXECUTE') THEN
    RAISE EXCEPTION 'service role retained safe-directory execution';
  END IF;
END $privilege$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000002',true);
DO $associate_projection$
DECLARE row_count integer; leaked_count integer; own record;
BEGIN
  SELECT count(*) INTO row_count FROM public.get_my_team_members();
  IF row_count<>4 THEN RAISE EXCEPTION 'associate directory did not contain exactly active tenant members: %',row_count; END IF;
  SELECT count(*) INTO leaked_count FROM public.get_my_team_members()
    WHERE user_id IN ('bd000000-0000-0000-0000-000000000005','bd000000-0000-0000-0000-000000000006','bd000000-0000-0000-0000-000000000007');
  IF leaked_count<>0 THEN RAISE EXCEPTION 'associate directory leaked inactive or foreign member'; END IF;
  SELECT * INTO own FROM public.get_my_team_members() WHERE user_id='bd000000-0000-0000-0000-000000000002';
  IF own.membership_id<>'bd110000-0000-0000-0000-000000000002'::uuid OR own.display_name<>'Directory Associate'
     OR own.authorised_email<>'directory-associate@test.invalid' THEN RAISE EXCEPTION 'safe user locator/profile/self-email mismatch'; END IF;
  IF EXISTS(SELECT 1 FROM public.get_my_team_members() WHERE user_id<>auth.uid() AND authorised_email IS NOT NULL) THEN
    RAISE EXCEPTION 'associate recovered another member email';
  END IF;
END $associate_projection$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000003',true);
DO $admin_projection$
DECLARE row_count integer;
BEGIN
  SELECT count(*) INTO row_count FROM public.get_my_team_members();
  IF row_count<>5 THEN RAISE EXCEPTION 'admin directory did not include active plus suspended tenant members'; END IF;
  IF EXISTS(SELECT 1 FROM public.get_my_team_members() WHERE authorised_email IS NULL)
     OR NOT EXISTS(SELECT 1 FROM public.get_my_team_members() WHERE user_id='bd000000-0000-0000-0000-000000000005' AND state='suspended')
     OR EXISTS(SELECT 1 FROM public.get_my_team_members() WHERE user_id IN ('bd000000-0000-0000-0000-000000000006','bd000000-0000-0000-0000-000000000007')) THEN
    RAISE EXCEPTION 'admin directory email/lifecycle/tenant boundary failed';
  END IF;
END $admin_projection$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000005',true);
DO $suspended_caller$
BEGIN
  IF EXISTS(SELECT 1 FROM public.get_my_team_members()) THEN RAISE EXCEPTION 'suspended caller read the directory'; END IF;
END $suspended_caller$;
RESET ROLE;

ROLLBACK;
