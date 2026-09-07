-- Run after migration 00125. The transaction is always rolled back.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
('00000000-0000-0000-0000-000000000000','bb000000-0000-0000-0000-000000000001','authenticated','authenticated','client-owner@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bb000000-0000-0000-0000-000000000002','authenticated','authenticated','client-associate@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bb000000-0000-0000-0000-000000000003','authenticated','authenticated','client-admin@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bb000000-0000-0000-0000-000000000004','authenticated','authenticated','client-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bb000000-0000-0000-0000-000000000005','authenticated','authenticated','client-suspended@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bb000000-0000-0000-0000-000000000006','authenticated','authenticated','client-removed@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bb000000-0000-0000-0000-000000000007','authenticated','authenticated','client-foreign@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES
('bb100000-0000-0000-0000-000000000001','Client authority organisation','bb000000-0000-0000-0000-000000000001'),
('bb100000-0000-0000-0000-000000000002','Foreign client organisation','bb000000-0000-0000-0000-000000000007');
INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at,suspended_at,suspended_by,suspension_reason,removed_at,removed_by,removal_reason)
VALUES
('bb110000-0000-0000-0000-000000000002','bb100000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-000000000002','associate','active',1,now(),NULL,NULL,NULL,NULL,NULL,NULL),
('bb110000-0000-0000-0000-000000000003','bb100000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-000000000003','admin','active',1,now(),NULL,NULL,NULL,NULL,NULL,NULL),
('bb110000-0000-0000-0000-000000000004','bb100000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-000000000004','viewer','active',1,now(),NULL,NULL,NULL,NULL,NULL,NULL),
('bb110000-0000-0000-0000-000000000005','bb100000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-000000000005','associate','suspended',1,now(),now(),'bb000000-0000-0000-0000-000000000001','fixture suspension',NULL,NULL,NULL),
('bb110000-0000-0000-0000-000000000006','bb100000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-000000000006','associate','removed',1,now(),NULL,NULL,NULL,now(),'bb000000-0000-0000-0000-000000000001','fixture removal');
UPDATE public.organisations AS organisation SET owner_membership_id=membership.id
FROM public.organisation_memberships AS membership
WHERE organisation.id=membership.org_id AND membership.user_id=organisation.created_by;
INSERT INTO public.clients(id,org_id,name) VALUES
('bb200000-0000-0000-0000-000000000001','bb100000-0000-0000-0000-000000000001','Existing client'),
('bb200000-0000-0000-0000-000000000002','bb100000-0000-0000-0000-000000000002','Foreign client'),
('bb200000-0000-0000-0000-000000000003','bb100000-0000-0000-0000-000000000001','Inactive client');
UPDATE public.clients SET deleted_at=now() WHERE id='bb200000-0000-0000-0000-000000000003';

DO $privileges$
BEGIN
  IF has_table_privilege('authenticated','public.clients','INSERT') OR has_table_privilege('authenticated','public.clients','UPDATE')
     OR has_table_privilege('service_role','public.clients','INSERT') OR has_table_privilege('service_role','public.clients','UPDATE')
     OR has_table_privilege('authenticated','public.client_command_receipts','SELECT')
     OR has_function_privilege('service_role','public.create_client_command(text,text,text,uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.update_client_command(uuid,bigint,text,text,text,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'direct client/receipt/service command privilege survived';
  END IF;
END $privileges$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','bb000000-0000-0000-0000-000000000002',true);
DO $associate_paths$
DECLARE created record; replay record; changed record; updated record; stale record; created_id uuid;
BEGIN
  SELECT * INTO created FROM public.create_client_command('Created client','','','bb300000-0000-0000-0000-000000000001');
  IF created.code<>'ok' OR created.client_id IS NULL OR created.revision<>1 OR created.replayed THEN RAISE EXCEPTION 'associate create failed'; END IF;
  created_id:=created.client_id;
  SELECT * INTO replay FROM public.create_client_command('Created client','','','bb300000-0000-0000-0000-000000000001');
  IF replay.code<>'ok' OR replay.client_id<>created_id OR replay.revision<>1 OR NOT replay.replayed THEN RAISE EXCEPTION 'create replay failed'; END IF;
  SELECT * INTO changed FROM public.create_client_command('Changed payload','','','bb300000-0000-0000-0000-000000000001');
  IF changed.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'changed create replay was accepted'; END IF;
  SELECT * INTO updated FROM public.update_client_command('bb200000-0000-0000-0000-000000000001',1,'Updated client','','','bb300000-0000-0000-0000-000000000002');
  IF updated.code<>'ok' OR updated.revision<>2 OR updated.replayed THEN RAISE EXCEPTION 'associate update failed'; END IF;
  SELECT * INTO replay FROM public.update_client_command('bb200000-0000-0000-0000-000000000001',1,'Updated client','','','bb300000-0000-0000-0000-000000000002');
  IF replay.code<>'ok' OR replay.revision<>2 OR NOT replay.replayed THEN RAISE EXCEPTION 'update replay failed'; END IF;
  SELECT * INTO stale FROM public.update_client_command('bb200000-0000-0000-0000-000000000001',1,'Stale update','','','bb300000-0000-0000-0000-000000000003');
  IF stale.code<>'conflict' OR stale.revision<>2 THEN RAISE EXCEPTION 'stale revision did not conflict'; END IF;
  SELECT * INTO stale FROM public.update_client_command('bb200000-0000-0000-0000-000000000003',1,'Inactive update','','','bb300000-0000-0000-0000-000000000004');
  IF stale.code<>'context_unavailable' THEN RAISE EXCEPTION 'inactive client accepted update'; END IF;
END $associate_paths$;
RESET ROLE;

DO $atomic_activity$
BEGIN
  IF (SELECT count(*) FROM public.activity_logs WHERE action='client_created' AND user_id='bb000000-0000-0000-0000-000000000002')<>1
     OR (SELECT count(*) FROM public.activity_logs WHERE action='client_updated' AND entity_id='bb200000-0000-0000-0000-000000000001')<>1 THEN
    RAISE EXCEPTION 'client mutation activity was missing or duplicated';
  END IF;
END $atomic_activity$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bb000000-0000-0000-0000-000000000004',true);
DO $viewer_denial$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.create_client_command('Viewer client','','','bb300000-0000-0000-0000-000000000005');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'Viewer created a client'; END IF;
  BEGIN INSERT INTO public.clients(org_id,name) VALUES('bb100000-0000-0000-0000-000000000001','Direct viewer'); RAISE EXCEPTION 'direct Viewer insert succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $viewer_denial$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bb000000-0000-0000-0000-000000000003',true);
DO $admin_path$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.create_client_command('Admin client','','','bb300000-0000-0000-0000-000000000006');
  IF result.code<>'ok' THEN RAISE EXCEPTION 'Admin create failed'; END IF;
END $admin_path$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bb000000-0000-0000-0000-000000000001',true);
DO $owner_path$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.create_client_command('Owner client','','','bb300000-0000-0000-0000-000000000007');
  IF result.code<>'ok' THEN RAISE EXCEPTION 'Owner create failed'; END IF;
END $owner_path$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bb000000-0000-0000-0000-000000000005',true);
DO $suspended_denial$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.create_client_command('Suspended client','','','bb300000-0000-0000-0000-000000000008');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'suspended member created a client'; END IF;
END $suspended_denial$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bb000000-0000-0000-0000-000000000006',true);
DO $removed_denial$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.create_client_command('Removed client','','','bb300000-0000-0000-0000-000000000009');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'removed member created a client'; END IF;
END $removed_denial$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bb000000-0000-0000-0000-000000000007',true);
DO $cross_tenant_denial$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.update_client_command('bb200000-0000-0000-0000-000000000001',2,'Foreign update','','','bb300000-0000-0000-0000-000000000010');
  IF result.code<>'context_unavailable' OR result.client_id IS NOT NULL THEN RAISE EXCEPTION 'cross-tenant client was disclosed'; END IF; END $cross_tenant_denial$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $service_direct_denial$ BEGIN
  BEGIN UPDATE public.clients SET name='Service bypass' WHERE id='bb200000-0000-0000-0000-000000000001'; RAISE EXCEPTION 'service update succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $service_direct_denial$;
RESET ROLE;

ROLLBACK;
