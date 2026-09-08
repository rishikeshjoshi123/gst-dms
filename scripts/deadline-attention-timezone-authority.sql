-- Run after `npx supabase db reset --local --no-seed`. The transaction always rolls back.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000','d1100000-0000-0000-0000-000000000001','authenticated','authenticated','deadline-owner-a@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','d1100000-0000-0000-0000-000000000002','authenticated','authenticated','deadline-owner-b@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','d1100000-0000-0000-0000-000000000003','authenticated','authenticated','deadline-suspended@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','d1100000-0000-0000-0000-000000000004','authenticated','authenticated','deadline-removed@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','d1100000-0000-0000-0000-000000000005','authenticated','authenticated','deadline-none@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','d1100000-0000-0000-0000-000000000006','authenticated','authenticated','deadline-duplicate@test.invalid','x',now(),'{}','{}',now(),now());

INSERT INTO public.organisations(id,name,created_by)
VALUES
  ('d1200000-0000-0000-0000-000000000001','Deadline authority A','d1100000-0000-0000-0000-000000000001'),
  ('d1200000-0000-0000-0000-000000000002','Deadline authority B','d1100000-0000-0000-0000-000000000002');

UPDATE public.organisation_operational_settings
SET timezone = CASE org_id
  WHEN 'd1200000-0000-0000-0000-000000000001'::uuid THEN 'Pacific/Kiritimati'
  ELSE 'America/Adak'
END
WHERE org_id IN (
  'd1200000-0000-0000-0000-000000000001'::uuid,
  'd1200000-0000-0000-0000-000000000002'::uuid
);

INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_at,suspended_at,suspension_reason)
VALUES ('d1200000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000003','associate','suspended',1,now(),now(),'fixture');
INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_at,removed_at,removal_reason)
VALUES ('d1200000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000004','associate','removed',1,now(),now(),'fixture');

DO $privileges$
BEGIN
  IF has_function_privilege('anon','public.get_current_organisation_operational_timezone()','EXECUTE')
     OR has_function_privilege('service_role','public.get_current_organisation_operational_timezone()','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.get_current_organisation_operational_timezone()','EXECUTE') THEN
    RAISE EXCEPTION 'deadline timezone reader grant surface is incorrect';
  END IF;
  IF NOT (SELECT prosecdef AND provolatile = 's' AND proconfig = ARRAY['search_path=pg_catalog, public']
          FROM pg_catalog.pg_proc
          WHERE oid = 'public.get_current_organisation_operational_timezone()'::regprocedure) THEN
    RAISE EXCEPTION 'deadline timezone reader execution contract is incorrect';
  END IF;
END $privileges$;

SET LOCAL ROLE anon;
DO $anonymous_denial$
BEGIN
  BEGIN
    PERFORM public.get_current_organisation_operational_timezone();
    RAISE EXCEPTION 'anonymous deadline timezone read unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END $anonymous_denial$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000001',true);
DO $active_exact_membership$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.get_current_organisation_operational_timezone();
  IF result.org_id <> 'd1200000-0000-0000-0000-000000000001'::uuid
     OR result.timezone <> 'Pacific/Kiritimati'
     OR (SELECT count(*) FROM public.get_current_organisation_operational_timezone()) <> 1 THEN
    RAISE EXCEPTION 'active exact membership did not return its own validated timezone';
  END IF;
END $active_exact_membership$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
DO $inactive_memberships$
DECLARE actor uuid;
BEGIN
  FOREACH actor IN ARRAY ARRAY[
    'd1100000-0000-0000-0000-000000000003'::uuid,
    'd1100000-0000-0000-0000-000000000004'::uuid,
    'd1100000-0000-0000-0000-000000000005'::uuid
  ] LOOP
    PERFORM set_config('request.jwt.claim.sub',actor::text,true);
    IF EXISTS (SELECT 1 FROM public.get_current_organisation_operational_timezone()) THEN
      RAISE EXCEPTION 'inactive/no-current actor % received an organisation timezone', actor;
    END IF;
  END LOOP;
END $inactive_memberships$;
RESET ROLE;

-- Manufacture an impossible imported duplicate only inside this rollback-only transaction.
DROP INDEX public.organisation_memberships_one_current_org_per_user;
INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_at)
VALUES
  ('d1200000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000006','associate','active',1,now()),
  ('d1200000-0000-0000-0000-000000000002','d1100000-0000-0000-0000-000000000006','associate','active',1,now());

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','d1100000-0000-0000-0000-000000000006',true);
DO $duplicate_denial$
BEGIN
  IF EXISTS (SELECT 1 FROM public.get_current_organisation_operational_timezone()) THEN
    RAISE EXCEPTION 'duplicate-corruption actor received an organisation timezone';
  END IF;
END $duplicate_denial$;
RESET ROLE;

ROLLBACK;
