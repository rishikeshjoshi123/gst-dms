-- Run after migration 00139. This disposable fixture always rolls back.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
  ('00000000-0000-0000-0000-000000000000','13900000-0000-0000-0000-000000000001','authenticated','authenticated','owner@team.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','13900000-0000-0000-0000-000000000002','authenticated','authenticated','associate-hidden@team.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','13900000-0000-0000-0000-000000000003','authenticated','authenticated','suspended@team.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','13900000-0000-0000-0000-000000000004','authenticated','authenticated','foreign@team.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','13900000-0000-0000-0000-000000000005','authenticated','authenticated','admin@team.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','13900000-0000-0000-0000-000000000006','authenticated','authenticated','viewer@team.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','13900000-0000-0000-0000-000000000007','authenticated','authenticated','removed@team.test','x',now(),'{}','{}',now(),now());

INSERT INTO public.organisations(id,name,created_by) VALUES
  ('13910000-0000-0000-0000-000000000001','Team fixture','13900000-0000-0000-0000-000000000001'),
  ('13910000-0000-0000-0000-000000000002','Foreign fixture','13900000-0000-0000-0000-000000000004');
-- Organisation creation retains the canonical legacy bridge, which creates
-- the Owner generation. Add the other fixture members through that same path.
INSERT INTO public.org_members(org_id,user_id,role) VALUES
  ('13910000-0000-0000-0000-000000000001','13900000-0000-0000-0000-000000000002','associate'),
  ('13910000-0000-0000-0000-000000000001','13900000-0000-0000-0000-000000000003','viewer'),
  ('13910000-0000-0000-0000-000000000001','13900000-0000-0000-0000-000000000005','admin'),
  ('13910000-0000-0000-0000-000000000001','13900000-0000-0000-0000-000000000006','viewer'),
  ('13910000-0000-0000-0000-000000000001','13900000-0000-0000-0000-000000000007','associate');
UPDATE public.organisation_memberships
SET state='suspended', suspended_at=now(), suspended_by='13900000-0000-0000-0000-000000000001', suspension_reason='fixture'
WHERE org_id='13910000-0000-0000-0000-000000000001' AND user_id='13900000-0000-0000-0000-000000000003';
UPDATE public.organisation_memberships
SET state='removed', removed_at=now(), removed_by='13900000-0000-0000-0000-000000000001', removal_reason='fixture'
WHERE org_id='13910000-0000-0000-0000-000000000001' AND user_id='13900000-0000-0000-0000-000000000007';
INSERT INTO public.user_profiles(user_id,display_name,professional_title) VALUES
  ('13900000-0000-0000-0000-000000000001','Owner One','Partner'),
  ('13900000-0000-0000-0000-000000000002',E'Back\\slash Associate','Counsel'),
  ('13900000-0000-0000-0000-000000000003','Suspended Three',NULL),
  ('13900000-0000-0000-0000-000000000004','Foreign Four',NULL),
  ('13900000-0000-0000-0000-000000000005','Admin Five',NULL),
  ('13900000-0000-0000-0000-000000000006','Percent %_ Viewer',NULL),
  ('13900000-0000-0000-0000-000000000007','Removed Seven',NULL)
ON CONFLICT (user_id) DO UPDATE SET display_name=EXCLUDED.display_name, professional_title=EXCLUDED.professional_title;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','13900000-0000-0000-0000-000000000001',true);
DO $owner$
DECLARE result_count integer; email_count integer; reported_total bigint;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE authorised_email IS NOT NULL), min(total_count)
  INTO result_count,email_count,reported_total
  FROM public.get_team_directory(NULL,NULL,NULL,100,0);
  IF result_count <> 5 OR email_count <> 5 OR reported_total <> 5 THEN RAISE EXCEPTION 'owner did not receive bounded active/suspended authorised directory'; END IF;
  IF (SELECT pg_typeof(authorised_email) FROM public.get_team_directory(NULL,NULL,NULL,1,0) LIMIT 1) <> 'text'::regtype THEN RAISE EXCEPTION 'authorised email did not retain the public text contract'; END IF;
  IF EXISTS (SELECT 1 FROM public.get_team_directory(NULL,NULL,NULL,100,0) WHERE user_id IN ('13900000-0000-0000-0000-000000000004','13900000-0000-0000-0000-000000000007')) THEN RAISE EXCEPTION 'foreign or removed member leaked'; END IF;
  IF (SELECT total_count FROM public.get_team_directory(NULL,'admin','active',100,0) LIMIT 1) <> 2 THEN RAISE EXCEPTION 'role filter failed'; END IF;
  IF (SELECT total_count FROM public.get_team_directory(NULL,NULL,'suspended',100,0) LIMIT 1) <> 1 THEN RAISE EXCEPTION 'state filter failed'; END IF;
  IF (SELECT total_count FROM public.get_team_directory('%',NULL,NULL,100,0) LIMIT 1) <> 1
     OR (SELECT total_count FROM public.get_team_directory('_',NULL,NULL,100,0) LIMIT 1) <> 1
     OR (SELECT total_count FROM public.get_team_directory(E'\\',NULL,NULL,100,0) LIMIT 1) <> 1 THEN
    RAISE EXCEPTION 'LIKE metacharacters were not treated literally';
  END IF;
  IF (SELECT total_count FROM public.get_team_directory(NULL,NULL,NULL,1,10000) LIMIT 1) <> 5
     OR (SELECT page_offset FROM public.get_team_directory(NULL,NULL,NULL,1,10000) LIMIT 1) <> 4 THEN
    RAISE EXCEPTION 'out-of-range pagination did not retain total and canonicalize offset';
  END IF;
END $owner$;

SELECT set_config('request.jwt.claim.sub','13900000-0000-0000-0000-000000000002',true);
DO $associate$
DECLARE result_count integer; email_count integer; search_count integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE authorised_email IS NOT NULL) INTO result_count,email_count
  FROM public.get_team_directory(NULL,NULL,NULL,100,0);
  IF result_count <> 4 OR email_count <> 1 THEN RAISE EXCEPTION 'ordinary member visibility leaked suspended membership or email'; END IF;
  SELECT total_count INTO search_count FROM public.get_team_directory('owner@team.test',NULL,NULL,100,0);
  IF search_count <> 0 OR NOT EXISTS (SELECT 1 FROM public.get_team_directory('owner@team.test',NULL,NULL,100,0) WHERE outcome_code='ok' AND membership_id IS NULL) THEN RAISE EXCEPTION 'hidden email changed ordinary member search result'; END IF;
  IF EXISTS (SELECT 1 FROM public.get_team_directory('Counsel',NULL,NULL,100,0) WHERE membership_id IS NOT NULL) THEN RAISE EXCEPTION 'professional title was searchable'; END IF;
END $associate$;

SELECT set_config('request.jwt.claim.sub','13900000-0000-0000-0000-000000000005',true);
DO $admin$
BEGIN
  IF (SELECT total_count FROM public.get_team_directory(NULL,NULL,NULL,100,0) LIMIT 1) <> 5
     OR (SELECT count(*) FROM public.get_team_directory(NULL,NULL,NULL,100,0) WHERE authorised_email IS NOT NULL) <> 5 THEN
    RAISE EXCEPTION 'admin directory authority was incomplete';
  END IF;
END $admin$;

SELECT set_config('request.jwt.claim.sub','13900000-0000-0000-0000-000000000006',true);
DO $viewer$
BEGIN
  IF (SELECT total_count FROM public.get_team_directory(NULL,NULL,NULL,100,0) LIMIT 1) <> 4
     OR (SELECT count(*) FROM public.get_team_directory(NULL,NULL,NULL,100,0) WHERE authorised_email IS NOT NULL) <> 1 THEN
    RAISE EXCEPTION 'viewer directory visibility was unsafe';
  END IF;
END $viewer$;

SELECT set_config('request.jwt.claim.sub','13900000-0000-0000-0000-000000000003',true);
DO $suspended$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.get_team_directory(NULL,NULL,NULL,100,0) WHERE outcome_code='unavailable' AND membership_id IS NULL) THEN RAISE EXCEPTION 'suspended caller retained directory access'; END IF;
END $suspended$;

SELECT set_config('request.jwt.claim.sub','13900000-0000-0000-0000-000000000007',true);
DO $removed$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.get_team_directory(NULL,NULL,NULL,100,0) WHERE outcome_code='unavailable' AND membership_id IS NULL) THEN RAISE EXCEPTION 'removed caller retained directory access'; END IF;
END $removed$;

SELECT set_config('request.jwt.claim.sub','13900000-0000-0000-0000-000000000001',true);
DO $invalid_inputs$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.get_team_directory(NULL,'owner',NULL,100,0) WHERE outcome_code='unavailable')
     OR NOT EXISTS (SELECT 1 FROM public.get_team_directory(NULL,NULL,'removed',100,0) WHERE outcome_code='unavailable')
     OR NOT EXISTS (SELECT 1 FROM public.get_team_directory(NULL,NULL,NULL,0,0) WHERE outcome_code='unavailable')
     OR NOT EXISTS (SELECT 1 FROM public.get_team_directory(NULL,NULL,NULL,100,-1) WHERE outcome_code='unavailable')
     OR NOT EXISTS (SELECT 1 FROM public.get_team_directory(repeat('x',121),NULL,NULL,100,0) WHERE outcome_code='unavailable') THEN
    RAISE EXCEPTION 'invalid directory inputs did not fail safely';
  END IF;
END $invalid_inputs$;

DO $stable_pagination$
DECLARE first_id uuid; repeated_first_id uuid; second_id uuid;
BEGIN
  SELECT membership_id INTO first_id FROM public.get_team_directory(NULL,NULL,NULL,1,0);
  SELECT membership_id INTO repeated_first_id FROM public.get_team_directory(NULL,NULL,NULL,1,0);
  SELECT membership_id INTO second_id FROM public.get_team_directory(NULL,NULL,NULL,1,1);
  IF first_id IS NULL OR first_id <> repeated_first_id OR second_id IS NULL OR first_id = second_id THEN
    RAISE EXCEPTION 'directory pagination was not stable';
  END IF;
END $stable_pagination$;

RESET ROLE;

-- Simulate the corruption/backfill invariant the production unique index
-- prevents. The directory must still fail closed if that invariant is ever
-- absent during recovery. The surrounding transaction restores the index.
DROP INDEX public.organisation_memberships_one_current_org_per_user;
-- Insert the deliberately corrupt canonical generation directly. The legacy
-- org_members bridge correctly retains its one-user constraint and is not the
-- authority being exercised by this recovery-only check.
INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_at) VALUES
  ('13910000-0000-0000-0000-000000000002','13900000-0000-0000-0000-000000000002','viewer','active',1,now());
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','13900000-0000-0000-0000-000000000002',true);
DO $multiple_contexts$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.get_team_directory(NULL,NULL,NULL,100,0) WHERE outcome_code='unavailable' AND membership_id IS NULL) THEN
    RAISE EXCEPTION 'multiple active organisation contexts did not fail closed';
  END IF;
END $multiple_contexts$;
RESET ROLE;

DO $grants$
BEGIN
  IF has_function_privilege('service_role','public.get_team_directory(text,text,text,integer,integer)','EXECUTE')
     OR has_function_privilege('anon','public.get_team_directory(text,text,text,integer,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'Team directory grants are unsafe';
  END IF;
END $grants$;

ROLLBACK;
