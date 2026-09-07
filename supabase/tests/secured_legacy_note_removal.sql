-- Run after migration 00124. The transaction is always rolled back.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000','b1000000-0000-0000-0000-000000000001','authenticated','authenticated','note-owner@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','b1000000-0000-0000-0000-000000000002','authenticated','authenticated','note-author@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','b1000000-0000-0000-0000-000000000003','authenticated','authenticated','note-peer@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','b1000000-0000-0000-0000-000000000004','authenticated','authenticated','note-admin@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','b1000000-0000-0000-0000-000000000005','authenticated','authenticated','note-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','b1000000-0000-0000-0000-000000000006','authenticated','authenticated','note-suspended@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','b1000000-0000-0000-0000-000000000007','authenticated','authenticated','note-foreign@test.invalid','x',now(),'{}','{}',now(),now());

INSERT INTO public.organisations(id,name,created_by)
VALUES
  ('b1100000-0000-0000-0000-000000000001','Note removal organisation','b1000000-0000-0000-0000-000000000001'),
  ('b1100000-0000-0000-0000-000000000002','Foreign note organisation','b1000000-0000-0000-0000-000000000007');

INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at,suspended_at,suspended_by,suspension_reason)
VALUES
  ('b1110000-0000-0000-0000-000000000002','b1100000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000002','associate','active',1,now(),NULL,NULL,NULL),
  ('b1110000-0000-0000-0000-000000000003','b1100000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000003','associate','active',1,now(),NULL,NULL,NULL),
  ('b1110000-0000-0000-0000-000000000004','b1100000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000004','admin','active',1,now(),NULL,NULL,NULL),
  ('b1110000-0000-0000-0000-000000000005','b1100000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000005','viewer','active',1,now(),NULL,NULL,NULL),
  ('b1110000-0000-0000-0000-000000000006','b1100000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000006','associate','suspended',1,now(),now(),'b1000000-0000-0000-0000-000000000001','fixture suspension');

UPDATE public.organisations AS organisation
SET owner_membership_id = membership.id
FROM public.organisation_memberships AS membership
WHERE organisation.id = membership.org_id
  AND membership.user_id = organisation.created_by
  AND membership.state = 'active';

INSERT INTO public.clients(id,org_id,name)
VALUES
  ('b1200000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','Note removal client'),
  ('b1200000-0000-0000-0000-000000000002','b1100000-0000-0000-0000-000000000002','Foreign note client');
INSERT INTO public.matters(id,org_id,client_id,title)
VALUES
  ('b1300000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-000000000001','Note removal matter'),
  ('b1300000-0000-0000-0000-000000000002','b1100000-0000-0000-0000-000000000002','b1200000-0000-0000-0000-000000000002','Foreign note matter');

INSERT INTO public.case_notes(id,org_id,matter_id,author_id,content)
VALUES
  ('b1400000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000002','Author removal target'),
  ('b1400000-0000-0000-0000-000000000002','b1100000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000002','Peer denial target'),
  ('b1400000-0000-0000-0000-000000000003','b1100000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000002','Admin moderation target'),
  ('b1400000-0000-0000-0000-000000000004','b1100000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000002','Owner moderation target'),
  ('b1400000-0000-0000-0000-000000000005','b1100000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000002','Inactive context target');

DO $privileges$
BEGIN
  IF has_function_privilege('service_role', 'public.remove_case_note(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'service role retained note-removal command access';
  END IF;
END $privileges$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000002',true);
DO $author_paths$
DECLARE result record; first_removed_at timestamptz; blocked boolean := false;
BEGIN
  BEGIN
    UPDATE public.case_notes SET deleted_at = now()
    WHERE id = 'b1400000-0000-0000-0000-000000000001';
  EXCEPTION WHEN insufficient_privilege THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'direct authenticated removal bypassed the command'; END IF;

  SELECT * INTO result FROM public.remove_case_note('b1400000-0000-0000-0000-000000000001', NULL);
  IF result.code <> 'ok' OR result.matter_id <> 'b1300000-0000-0000-0000-000000000001'::uuid
     OR result.removed_at IS NULL THEN
    RAISE EXCEPTION 'author removal failed: %', result.code;
  END IF;
  first_removed_at := result.removed_at;
  SELECT * INTO result FROM public.remove_case_note('b1400000-0000-0000-0000-000000000001', NULL);
  IF result.code <> 'already_removed' OR result.removed_at IS DISTINCT FROM first_removed_at THEN
    RAISE EXCEPTION 'author retry was not idempotent';
  END IF;
END $author_paths$;
RESET ROLE;

DO $author_audit$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.case_notes
    WHERE id='b1400000-0000-0000-0000-000000000001'
      AND deleted_by='b1000000-0000-0000-0000-000000000002'
      AND deletion_kind='author' AND deletion_reason IS NULL
      AND content='Author removal target' AND matter_id='b1300000-0000-0000-0000-000000000001'
  ) THEN RAISE EXCEPTION 'author tombstone lost required audit or source fields'; END IF;
END $author_audit$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
DO $peer_denial$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.remove_case_note('b1400000-0000-0000-0000-000000000002', NULL);
  IF result.code <> 'not_allowed' OR result.matter_id IS NOT NULL THEN
    RAISE EXCEPTION 'non-author associate received removal authority';
  END IF;
END $peer_denial$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000005',true);
DO $viewer_denial$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.remove_case_note('b1400000-0000-0000-0000-000000000002', NULL);
  IF result.code <> 'not_allowed' THEN RAISE EXCEPTION 'viewer received removal authority'; END IF;
END $viewer_denial$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000004',true);
DO $admin_moderation$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.remove_case_note('b1400000-0000-0000-0000-000000000003', NULL);
  IF result.code <> 'reason_required' THEN RAISE EXCEPTION 'admin moderation did not require a reason'; END IF;
  SELECT * INTO result FROM public.remove_case_note('b1400000-0000-0000-0000-000000000003', 'Violates matter communication policy');
  IF result.code <> 'ok' THEN RAISE EXCEPTION 'admin moderation failed: %', result.code; END IF;
END $admin_moderation$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
DO $owner_moderation$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.remove_case_note('b1400000-0000-0000-0000-000000000004', 'Owner moderation audit reason');
  IF result.code <> 'ok' THEN RAISE EXCEPTION 'owner moderation failed: %', result.code; END IF;
END $owner_moderation$;
RESET ROLE;

DO $moderation_audit$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.case_notes
    WHERE id='b1400000-0000-0000-0000-000000000003'
      AND deleted_by='b1000000-0000-0000-0000-000000000004'
      AND deletion_kind='moderation'
      AND deletion_reason='Violates matter communication policy'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.case_notes
    WHERE id='b1400000-0000-0000-0000-000000000004'
      AND deleted_by='b1000000-0000-0000-0000-000000000001'
      AND deletion_kind='moderation'
      AND deletion_reason='Owner moderation audit reason'
  ) THEN RAISE EXCEPTION 'moderation audit was not retained'; END IF;
END $moderation_audit$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000006',true);
DO $suspended_denial$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.remove_case_note('b1400000-0000-0000-0000-000000000002', NULL);
  IF result.code <> 'not_allowed' THEN RAISE EXCEPTION 'suspended member received removal authority'; END IF;
END $suspended_denial$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000007',true);
DO $cross_tenant_denial$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.remove_case_note('b1400000-0000-0000-0000-000000000002', NULL);
  IF result.code <> 'context_unavailable' OR result.matter_id IS NOT NULL THEN
    RAISE EXCEPTION 'cross-tenant note existence was disclosed';
  END IF;
END $cross_tenant_denial$;
RESET ROLE;

UPDATE public.matters SET deleted_at=now() WHERE id='b1300000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000002',true);
DO $inactive_context_denial$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.remove_case_note('b1400000-0000-0000-0000-000000000005', NULL);
  IF result.code <> 'context_unavailable' THEN RAISE EXCEPTION 'inactive Matter allowed note removal'; END IF;
END $inactive_context_denial$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $service_role_direct_denial$
DECLARE blocked boolean := false;
BEGIN
  BEGIN
    UPDATE public.case_notes SET deleted_at=now()
    WHERE id='b1400000-0000-0000-0000-000000000002';
  EXCEPTION WHEN insufficient_privilege THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'service role direct removal bypassed the trigger'; END IF;
END $service_role_direct_denial$;
RESET ROLE;

ROLLBACK;
