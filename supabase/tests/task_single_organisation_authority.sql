-- Run after `npx supabase db reset --local --no-seed`.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000','c1000000-0000-0000-0000-000000000001','authenticated','authenticated','authority-owner-a@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','c1000000-0000-0000-0000-000000000002','authenticated','authenticated','authority-owner-b@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','c1000000-0000-0000-0000-000000000003','authenticated','authenticated','authority-removed@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','c1000000-0000-0000-0000-000000000004','authenticated','authenticated','authority-suspended@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','c1000000-0000-0000-0000-000000000005','authenticated','authenticated','authority-zero@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','c1000000-0000-0000-0000-000000000006','authenticated','authenticated','authority-duplicate@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES
  ('c1100000-0000-0000-0000-000000000001','Authority A','c1000000-0000-0000-0000-000000000001'),
  ('c1100000-0000-0000-0000-000000000002','Authority B','c1000000-0000-0000-0000-000000000002');
UPDATE public.organisations AS organisation SET owner_membership_id=membership.id
FROM public.organisation_memberships AS membership
WHERE organisation.id=membership.org_id AND organisation.created_by=membership.user_id;

-- Removed history does not retain current authority and can rejoin elsewhere.
INSERT INTO public.org_members(org_id,user_id,role) VALUES ('c1100000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000003','associate');
DELETE FROM public.org_members WHERE org_id='c1100000-0000-0000-0000-000000000001' AND user_id='c1000000-0000-0000-0000-000000000003';
INSERT INTO public.org_members(org_id,user_id,role) VALUES ('c1100000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000004','associate');
UPDATE public.organisation_memberships SET state='suspended',suspended_at=now(),suspended_by='c1000000-0000-0000-0000-000000000001',suspension_reason='fixture'
WHERE org_id='c1100000-0000-0000-0000-000000000001' AND user_id='c1000000-0000-0000-0000-000000000004' AND state='active';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000005',true);
DO $zero_creation$
DECLARE result record; blocked boolean := false;
BEGIN
  SELECT * INTO result FROM public.create_organisation('Authority created by zero member','c1200000-0000-0000-0000-000000000001');
  IF result.code<>'ok' OR result.org_id IS NULL OR (SELECT count(*) FROM public.current_active_tenant_membership())<>1 THEN RAISE EXCEPTION 'zero-member creation did not establish exactly one active membership'; END IF;
  BEGIN INSERT INTO public.organisations(name,created_by) VALUES('Direct insert denied',auth.uid()); EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
  IF NOT blocked THEN RAISE EXCEPTION 'authenticated direct organisation insert bypassed creation command'; END IF;
END $zero_creation$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000004',true);
DO $suspended_denial$
DECLARE result record;
BEGIN
  IF EXISTS(SELECT 1 FROM public.current_active_tenant_membership()) OR EXISTS(SELECT 1 FROM public.get_my_tasks(NULL,10,0)) THEN RAISE EXCEPTION 'suspended membership retained Task reader authority'; END IF;
  SELECT * INTO result FROM public.transition_task('00000000-0000-0000-0000-000000000001','start',1,'c1200000-0000-0000-0000-000000000002');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'suspended membership retained Task mutation authority'; END IF;
END $suspended_denial$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000002',true);
DO $invite_rejoin$
DECLARE invite record; accepted record;
BEGIN
  SELECT * INTO invite FROM public.create_organisation_invite('authority-removed@test.invalid','associate',repeat('a',64),'c1200000-0000-0000-0000-000000000003');
  IF invite.code<>'created' THEN RAISE EXCEPTION 'fixture invite creation failed: %',invite.code; END IF;
  PERFORM set_config('casechain.invite_id',invite.invite_id::text,true);
END $invite_rejoin$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000003',true);
DO $removed_rejoin$
DECLARE accepted record;
BEGIN
  SELECT * INTO accepted FROM public.accept_organisation_invite(current_setting('casechain.invite_id')::uuid,NULL,NULL,'c1200000-0000-0000-0000-000000000004');
  IF accepted.code<>'accepted' OR accepted.org_id<>'c1100000-0000-0000-0000-000000000002'::uuid OR (SELECT count(*) FROM public.current_active_tenant_membership())<>1 THEN RAISE EXCEPTION 'removed history did not rejoin as one current membership'; END IF;
END $removed_rejoin$;
RESET ROLE;

-- Simulate an impossible restored/import-corrupt duplicate state. The Task
-- projections must fail closed even if a privileged repair is still pending.
DROP INDEX public.organisation_memberships_one_current_org_per_user;
INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_at) VALUES
  ('c1100000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000006','associate','active',1,now()),
  ('c1100000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000006','associate','active',1,now());
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','c1000000-0000-0000-0000-000000000006',true);
DO $duplicate_denial$
DECLARE result record;
BEGIN
  IF EXISTS(SELECT 1 FROM public.current_active_tenant_membership()) OR EXISTS(SELECT 1 FROM public.get_my_tasks(NULL,10,0)) OR EXISTS(SELECT 1 FROM public.get_task_workspace_members()) THEN RAISE EXCEPTION 'duplicate current memberships exposed Task authority'; END IF;
  SELECT * INTO result FROM public.transition_task('00000000-0000-0000-0000-000000000001','start',1,'c1200000-0000-0000-0000-000000000005');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'duplicate current memberships retained Task mutation authority'; END IF;
END $duplicate_denial$;
RESET ROLE;

ROLLBACK;
