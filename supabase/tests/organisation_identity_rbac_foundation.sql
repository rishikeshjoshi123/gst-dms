-- Run only against a disposable local Supabase database after migration 00044.
-- Requires a database owner/service role capable of inserting isolated auth.users
-- fixtures. This script rolls back all fixtures and must not be aimed at a
-- shared or persistent database.
BEGIN;

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'owner@example.test', 'not-used', now(), '{}', '{"full_name":"Owner One"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'admin@example.test', 'not-used', now(), '{}', '{"name":"Admin Two"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'associate@example.test', 'not-used', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'viewer@example.test', 'not-used', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'newcomer@example.test', 'not-used', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'other-owner@example.test', 'not-used', now(), '{}', '{}', now(), now());

-- The legacy creator trigger inserts the initial Admin and the compatibility
-- trigger creates the canonical Owner membership.
INSERT INTO public.organisations (id, name, created_by)
VALUES
  ('20000000-0000-0000-0000-000000000001', 'Identity contract fixture', '10000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002', 'Second identity fixture', '10000000-0000-0000-0000-000000000006');
INSERT INTO public.org_members (org_id, user_id, role) VALUES
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 'admin'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', 'associate'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000004', 'viewer');

DO $test$
DECLARE
  fixture_org uuid := '20000000-0000-0000-0000-000000000001';
  other_org uuid := '20000000-0000-0000-0000-000000000002';
  fixture_owner uuid := '10000000-0000-0000-0000-000000000001';
  fixture_admin uuid := '10000000-0000-0000-0000-000000000002';
  fixture_associate uuid := '10000000-0000-0000-0000-000000000003';
  fixture_viewer uuid := '10000000-0000-0000-0000-000000000004';
  fixture_newcomer uuid := '10000000-0000-0000-0000-000000000005';
  owner_membership uuid;
  initial_revision bigint;
  expected_failure boolean;
  failure_message text;
BEGIN
  SELECT owner_membership_id INTO owner_membership FROM public.organisations WHERE id = fixture_org;
  IF owner_membership IS NULL THEN RAISE EXCEPTION 'creator admin was not made owner'; END IF;

  -- Exact capability matrix, including the implicit team.view capability.
  PERFORM set_config('request.jwt.claim.sub', fixture_owner::text, true);
  IF (SELECT capabilities FROM public.get_my_organisation_context()) <> ARRAY[
    'team.view', 'team.invite.standard', 'team.role.manage_standard',
    'team.membership.suspend_standard', 'organisation.profile.manage',
    'organisation.operations.manage', 'team.invite.admin', 'team.role.manage_admin',
    'team.membership.manage_admin', 'team.ownership.transfer', 'trash.purge', 'document.view', 'document.intake.create',
    'document.record.create', 'document.intake.assign', 'document.intake.discard', 'document.version.attach', 'document.version.replace'
  ]::text[] THEN RAISE EXCEPTION 'owner capability matrix failed'; END IF;
  IF (SELECT capability_version FROM public.get_my_organisation_context()) <> 4 THEN
    RAISE EXCEPTION 'capability version did not identify the current matrix'; END IF;
  IF NOT public.has_team_capability(fixture_org, 'trash.purge') THEN
    RAISE EXCEPTION 'owner trash purge capability failed'; END IF;
  PERFORM set_config('request.jwt.claim.sub', fixture_admin::text, true);
  IF (SELECT capabilities FROM public.get_my_organisation_context()) <> ARRAY[
    'team.view', 'team.invite.standard', 'team.role.manage_standard',
    'team.membership.suspend_standard', 'organisation.profile.manage', 'organisation.operations.manage', 'trash.purge', 'document.view', 'document.intake.create',
    'document.record.create', 'document.intake.assign', 'document.intake.discard', 'document.version.attach', 'document.version.replace'
  ]::text[] THEN RAISE EXCEPTION 'admin capability matrix failed'; END IF;
  IF NOT public.has_team_capability(fixture_org, 'trash.purge') THEN
    RAISE EXCEPTION 'admin trash purge capability failed'; END IF;
  PERFORM set_config('request.jwt.claim.sub', fixture_associate::text, true);
  IF (SELECT capabilities FROM public.get_my_organisation_context()) <> ARRAY['team.view','document.view','document.intake.create','document.record.create','document.intake.assign','document.intake.discard','document.version.attach','document.version.replace']::text[] THEN
    RAISE EXCEPTION 'associate capability matrix failed'; END IF;
  IF public.has_team_capability(fixture_org, 'trash.purge') THEN
    RAISE EXCEPTION 'associate trash purge capability must be denied'; END IF;
  PERFORM set_config('request.jwt.claim.sub', fixture_viewer::text, true);
  IF (SELECT capabilities FROM public.get_my_organisation_context()) <> ARRAY['team.view','document.view']::text[] THEN
    RAISE EXCEPTION 'viewer capability matrix failed'; END IF;
  IF public.has_team_capability(fixture_org, 'trash.purge') THEN
    RAISE EXCEPTION 'viewer trash purge capability must be denied'; END IF;
  IF public.has_team_capability(fixture_org, 'unknown.capability') THEN
    RAISE EXCEPTION 'unknown capability must fail closed'; END IF;
  IF NOT public.is_email_in_any_org('OWNER@EXAMPLE.TEST') THEN
    RAISE EXCEPTION 'service-context email helper did not preserve case-insensitive lookup'; END IF;
  PERFORM set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000099', true);
  IF public.is_active_org_member(fixture_org)
     OR EXISTS (SELECT 1 FROM public.get_my_organisation_context()) THEN
    RAISE EXCEPTION 'no-membership caller did not fail closed'; END IF;
  PERFORM set_config('request.jwt.claim.sub', fixture_owner::text, true);

  -- The legacy path must create, update, remove, and rejoin canonical history.
  INSERT INTO public.org_members (org_id, user_id, role) VALUES (fixture_org, fixture_newcomer, 'viewer');
  UPDATE public.org_members SET role = 'associate'
  WHERE org_id = fixture_org AND user_id = fixture_newcomer;
  SELECT revision INTO initial_revision FROM public.organisation_memberships
  WHERE org_id = fixture_org AND user_id = fixture_newcomer AND state = 'active';
  IF initial_revision < 2 THEN RAISE EXCEPTION 'legacy role update did not increment canonical revision'; END IF;
  DELETE FROM public.org_members WHERE org_id = fixture_org AND user_id = fixture_newcomer;
  IF NOT EXISTS (SELECT 1 FROM public.organisation_memberships
                 WHERE org_id = fixture_org AND user_id = fixture_newcomer AND state = 'removed' AND generation = 1) THEN
    RAISE EXCEPTION 'legacy delete did not preserve canonical removal history'; END IF;
  PERFORM set_config('request.jwt.claim.sub', fixture_newcomer::text, true);
  IF public.is_active_org_member(fixture_org)
     OR EXISTS (SELECT 1 FROM public.get_my_organisation_context()) THEN
    RAISE EXCEPTION 'removed caller did not fail closed'; END IF;
  INSERT INTO public.org_members (org_id, user_id, role) VALUES (fixture_org, fixture_newcomer, 'viewer');
  IF NOT EXISTS (SELECT 1 FROM public.organisation_memberships
                 WHERE org_id = fixture_org AND user_id = fixture_newcomer AND state = 'active' AND generation = 2) THEN
    RAISE EXCEPTION 'legacy rejoin did not create the next canonical generation'; END IF;

  -- The partial unique pilot invariant rejects a second current organisation.
  BEGIN
    INSERT INTO public.organisation_memberships (org_id, user_id, role, state, generation)
    VALUES (other_org, fixture_owner, 'admin', 'active', 1);
    RAISE EXCEPTION 'second current organisation should have failed';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.organisation_memberships (org_id, user_id, role, state, generation, removed_at)
    VALUES (fixture_org, fixture_newcomer, 'viewer', 'removed', 2, now());
    RAISE EXCEPTION 'duplicate membership generation should have failed';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.organisation_memberships
    SET state = 'removed', removed_at = now(), suspended_at = now(), suspended_by = fixture_owner
    WHERE org_id = fixture_org AND user_id = fixture_newcomer AND state = 'active';
    RAISE EXCEPTION 'removed membership with suspension fields should have failed';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.organisation_memberships
    SET removed_at = now()
    WHERE org_id = fixture_org AND user_id = fixture_newcomer AND state = 'active';
    RAISE EXCEPTION 'active membership with removal timestamp should have failed';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Suspension removes active capability/context access but preserves history.
  UPDATE public.organisation_memberships
  SET state = 'suspended', suspended_at = now(), suspended_by = fixture_owner
  WHERE org_id = fixture_org AND user_id = fixture_viewer AND state = 'active';
  PERFORM set_config('request.jwt.claim.sub', fixture_viewer::text, true);
  IF public.is_active_org_member(fixture_org)
     OR COALESCE((SELECT cardinality(capabilities) FROM public.get_my_organisation_context()), -1) <> 0 THEN
    RAISE EXCEPTION 'suspended caller did not fail closed'; END IF;

  -- Ordinary callers receive active team rows, only their own verified email,
  -- while Admin can receive verified emails and suspended rows.
  PERFORM set_config('request.jwt.claim.sub', fixture_associate::text, true);
  IF EXISTS (SELECT 1 FROM public.get_my_team_members() WHERE authorised_email IS NOT NULL AND membership_id <>
      (SELECT membership_id FROM public.get_my_organisation_context()))
     OR EXISTS (SELECT 1 FROM public.get_my_team_members() WHERE state = 'suspended') THEN
    RAISE EXCEPTION 'ordinary directory projection exposed restricted data'; END IF;
  IF (SELECT capabilities FROM public.get_my_team_members()
      WHERE membership_id = (SELECT membership_id FROM public.get_my_organisation_context()))
      <> ARRAY['team.view','document.view','document.intake.create','document.record.create','document.intake.assign','document.intake.discard','document.version.attach','document.version.replace']::text[] THEN
    RAISE EXCEPTION 'associate directory capability projection failed'; END IF;
  PERFORM set_config('request.jwt.claim.sub', fixture_admin::text, true);
  IF NOT EXISTS (SELECT 1 FROM public.get_my_team_members() WHERE state = 'suspended')
     OR NOT EXISTS (SELECT 1 FROM public.get_my_team_members() WHERE authorised_email = 'owner@example.test') THEN
    RAISE EXCEPTION 'admin directory projection omitted authorised data'; END IF;
  IF (SELECT capabilities FROM public.get_my_team_members() WHERE state = 'suspended') <> ARRAY[]::text[]
     OR (SELECT capabilities FROM public.get_my_team_members()
         WHERE membership_id = owner_membership) <> ARRAY[
           'team.view', 'team.invite.standard', 'team.role.manage_standard',
           'team.membership.suspend_standard', 'organisation.profile.manage',
           'organisation.operations.manage', 'team.invite.admin', 'team.role.manage_admin',
           'team.membership.manage_admin', 'team.ownership.transfer', 'trash.purge', 'document.view', 'document.intake.create',
           'document.record.create', 'document.intake.assign', 'document.intake.discard', 'document.version.attach', 'document.version.replace'
         ]::text[] THEN
    RAISE EXCEPTION 'admin directory capability projection failed'; END IF;
  IF (SELECT capabilities FROM public.get_my_team_members()
      WHERE membership_id = (SELECT id FROM public.organisation_memberships WHERE org_id = fixture_org AND user_id = fixture_admin AND state = 'active')) <> ARRAY[
        'team.view', 'team.invite.standard', 'team.role.manage_standard',
        'team.membership.suspend_standard', 'organisation.profile.manage', 'organisation.operations.manage',
        'trash.purge', 'document.view', 'document.intake.create',
        'document.record.create', 'document.intake.assign', 'document.intake.discard', 'document.version.attach', 'document.version.replace'
      ]::text[] THEN RAISE EXCEPTION 'admin target capability projection failed'; END IF;
  UPDATE public.organisation_memberships
  SET state = 'active', suspended_at = NULL, suspended_by = NULL, suspension_reason = NULL
  WHERE org_id = fixture_org AND user_id = fixture_viewer AND state = 'suspended';
  IF (SELECT capabilities FROM public.get_my_team_members()
      WHERE membership_id = (SELECT id FROM public.organisation_memberships WHERE org_id = fixture_org AND user_id = fixture_viewer AND state = 'active'))
      <> ARRAY['team.view','document.view']::text[] THEN RAISE EXCEPTION 'viewer target capability projection failed'; END IF;

  -- Owner authority cannot be demoted or removed through the legacy path.
  expected_failure := false;
  BEGIN
    UPDATE public.org_members SET role = 'associate' WHERE org_id = fixture_org AND user_id = fixture_owner;
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS failure_message = MESSAGE_TEXT;
    IF failure_message <> 'cannot demote the current organisation owner below admin' THEN RAISE; END IF;
    expected_failure := true;
  END;
  IF NOT expected_failure THEN RAISE EXCEPTION 'owner demotion should have failed'; END IF;
  expected_failure := false;
  BEGIN
    DELETE FROM public.org_members WHERE org_id = fixture_org AND user_id = fixture_owner;
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS failure_message = MESSAGE_TEXT;
    IF failure_message <> 'cannot delete the current organisation owner through legacy membership path' THEN RAISE; END IF;
    expected_failure := true;
  END;
  IF NOT expected_failure THEN RAISE EXCEPTION 'owner deletion should have failed'; END IF;

  -- Service/owner context may expose diagnostics. Create two controlled drift
  -- cases and prove the report clears after repair.
  UPDATE public.organisation_memberships SET role = 'viewer'
  WHERE org_id = fixture_org AND user_id = fixture_associate AND state = 'active';
  DELETE FROM public.user_profiles WHERE user_id = fixture_associate;
  IF NOT EXISTS (SELECT 1 FROM public.organisation_identity_cutover_diagnostics WHERE issue_code = 'legacy_canonical_role_mismatch')
     OR NOT EXISTS (SELECT 1 FROM public.organisation_identity_cutover_diagnostics WHERE issue_code = 'current_member_missing_profile') THEN
    RAISE EXCEPTION 'cutover diagnostics failed to report introduced drift'; END IF;
  UPDATE public.organisation_memberships SET role = 'associate'
  WHERE org_id = fixture_org AND user_id = fixture_associate AND state = 'active';
  INSERT INTO public.user_profiles (user_id, display_name) VALUES (fixture_associate, 'Associate Three');
  IF EXISTS (SELECT 1 FROM public.organisation_identity_cutover_diagnostics) THEN
    RAISE EXCEPTION 'cutover diagnostics did not clear after repair'; END IF;
END;
$test$;

-- Browser table APIs may read only their own base rows; all canonical mutation
-- and protected organisation-column writes are denied. Legacy Admin name edit
-- remains available through its existing RLS policy and column-level grant.
SET LOCAL ROLE service_role;
DO $$
BEGIN
  IF NOT public.is_email_in_any_org('owner@example.test') THEN
    RAISE EXCEPTION 'service role could not call the legacy email helper';
  END IF;
  PERFORM count(*) FROM public.organisation_identity_cutover_diagnostics;
END;
$$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '10000000-0000-0000-0000-000000000002';
DO $$
DECLARE
  statement text;
BEGIN
  FOREACH statement IN ARRAY ARRAY[
    $sql$INSERT INTO public.organisation_memberships (org_id, user_id, role, state, generation) VALUES ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 'admin', 'active', 99)$sql$,
    $sql$UPDATE public.organisation_memberships SET role = 'viewer' WHERE user_id = '10000000-0000-0000-0000-000000000002'$sql$,
    $sql$DELETE FROM public.organisation_memberships WHERE user_id = '10000000-0000-0000-0000-000000000002'$sql$,
    $sql$INSERT INTO public.user_profiles (user_id) VALUES ('10000000-0000-0000-0000-000000000002')$sql$,
    $sql$UPDATE public.user_profiles SET display_name = 'forbidden' WHERE user_id = '10000000-0000-0000-0000-000000000002'$sql$,
    $sql$DELETE FROM public.user_profiles WHERE user_id = '10000000-0000-0000-0000-000000000002'$sql$,
    $sql$UPDATE public.organisations SET owner_membership_id = NULL WHERE id = '20000000-0000-0000-0000-000000000001'$sql$,
    $sql$UPDATE public.organisations SET created_by = '10000000-0000-0000-0000-000000000002' WHERE id = '20000000-0000-0000-0000-000000000001'$sql$,
    $sql$UPDATE public.organisations SET id = '20000000-0000-0000-0000-000000000099' WHERE id = '20000000-0000-0000-0000-000000000001'$sql$,
    $sql$UPDATE public.organisations SET revision = 999 WHERE id = '20000000-0000-0000-0000-000000000001'$sql$,
    $sql$UPDATE public.organisations SET updated_at = now() WHERE id = '20000000-0000-0000-0000-000000000001'$sql$,
    $sql$SELECT public.is_email_in_any_org('owner@example.test')$sql$,
    $sql$SELECT * FROM public.organisation_identity_cutover_diagnostics$sql$
  ] LOOP
    BEGIN
      EXECUTE statement;
      RAISE EXCEPTION 'authenticated direct mutation unexpectedly succeeded: %', statement;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
END;
$$;
UPDATE public.organisations SET name = 'Identity contract fixture renamed by admin'
WHERE id = '20000000-0000-0000-0000-000000000001';
RESET ROLE;

DO $$
BEGIN
  IF (SELECT name FROM public.organisations WHERE id = '20000000-0000-0000-0000-000000000001')
       <> 'Identity contract fixture renamed by admin' THEN
    RAISE EXCEPTION 'authorized legacy admin name update failed';
  END IF;
END;
$$;

ROLLBACK;
