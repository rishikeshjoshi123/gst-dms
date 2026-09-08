-- Run after migration 00127. The transaction is always rolled back.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
('00000000-0000-0000-0000-000000000000','bd000000-0000-0000-0000-000000000001','authenticated','authenticated','matter-owner@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bd000000-0000-0000-0000-000000000002','authenticated','authenticated','matter-associate@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bd000000-0000-0000-0000-000000000003','authenticated','authenticated','matter-admin@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bd000000-0000-0000-0000-000000000004','authenticated','authenticated','matter-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bd000000-0000-0000-0000-000000000005','authenticated','authenticated','matter-suspended@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bd000000-0000-0000-0000-000000000006','authenticated','authenticated','matter-removed@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bd000000-0000-0000-0000-000000000007','authenticated','authenticated','matter-foreign@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES
('bd100000-0000-0000-0000-000000000001','Matter authority organisation','bd000000-0000-0000-0000-000000000001'),
('bd100000-0000-0000-0000-000000000002','Foreign matter organisation','bd000000-0000-0000-0000-000000000007');
INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at,suspended_at,suspended_by,suspension_reason,removed_at,removed_by,removal_reason)
VALUES
('bd110000-0000-0000-0000-000000000002','bd100000-0000-0000-0000-000000000001','bd000000-0000-0000-0000-000000000002','associate','active',1,now(),NULL,NULL,NULL,NULL,NULL,NULL),
('bd110000-0000-0000-0000-000000000003','bd100000-0000-0000-0000-000000000001','bd000000-0000-0000-0000-000000000003','admin','active',1,now(),NULL,NULL,NULL,NULL,NULL,NULL),
('bd110000-0000-0000-0000-000000000004','bd100000-0000-0000-0000-000000000001','bd000000-0000-0000-0000-000000000004','viewer','active',1,now(),NULL,NULL,NULL,NULL,NULL,NULL),
('bd110000-0000-0000-0000-000000000005','bd100000-0000-0000-0000-000000000001','bd000000-0000-0000-0000-000000000005','associate','suspended',1,now(),now(),'bd000000-0000-0000-0000-000000000001','fixture',NULL,NULL,NULL),
('bd110000-0000-0000-0000-000000000006','bd100000-0000-0000-0000-000000000001','bd000000-0000-0000-0000-000000000006','associate','removed',1,now(),NULL,NULL,NULL,now(),'bd000000-0000-0000-0000-000000000001','fixture');
UPDATE public.organisations AS organisation SET owner_membership_id=membership.id
FROM public.organisation_memberships AS membership
WHERE organisation.id=membership.org_id AND membership.user_id=organisation.created_by;
INSERT INTO public.clients(id,org_id,name) VALUES
('bd200000-0000-0000-0000-000000000001','bd100000-0000-0000-0000-000000000001','Matter client'),
('bd200000-0000-0000-0000-000000000002','bd100000-0000-0000-0000-000000000002','Foreign matter client'),
('bd200000-0000-0000-0000-000000000003','bd100000-0000-0000-0000-000000000001','Inactive matter client');
UPDATE public.clients SET deleted_at=now() WHERE id='bd200000-0000-0000-0000-000000000003';
INSERT INTO public.matters(id,org_id,client_id,title,financial_year) VALUES
('bd400000-0000-0000-0000-000000000001','bd100000-0000-0000-0000-000000000001','bd200000-0000-0000-0000-000000000001','Existing matter','Unknown FY'),
('bd400000-0000-0000-0000-000000000002','bd100000-0000-0000-0000-000000000002','bd200000-0000-0000-0000-000000000002','Foreign matter','2024-25'),
('bd400000-0000-0000-0000-000000000003','bd100000-0000-0000-0000-000000000001','bd200000-0000-0000-0000-000000000001','Inactive matter','2024-25');
UPDATE public.matters SET deleted_at=now() WHERE id='bd400000-0000-0000-0000-000000000003';
INSERT INTO public.documents(id,org_id,matter_id,display_title,financial_year)
VALUES('bd500000-0000-0000-0000-000000000001','bd100000-0000-0000-0000-000000000001','bd400000-0000-0000-0000-000000000001','Unknown FY document','Unknown FY');

DO $privileges$
BEGIN
  IF has_table_privilege('authenticated','public.matters','INSERT') OR has_table_privilege('authenticated','public.matters','UPDATE')
     OR has_table_privilege('service_role','public.matters','INSERT') OR has_table_privilege('service_role','public.matters','UPDATE')
     OR has_table_privilege('authenticated','public.matter_command_receipts','SELECT')
     OR has_function_privilege('service_role','public.create_matter_command(uuid,text,text,text,public.matter_status,uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.update_matter_command(uuid,bigint,text,text,text,public.matter_status,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'direct matter/receipt/service command privilege survived';
  END IF;
END $privileges$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000002',true);
DO $associate_paths$
DECLARE created record; replay record; changed record; updated record; stale record; created_id uuid;
BEGIN
  SELECT * INTO created FROM public.create_matter_command('bd200000-0000-0000-0000-000000000001','Created matter','2024-25','','active','bd300000-0000-0000-0000-000000000001');
  IF created.code<>'ok' OR created.matter_id IS NULL OR created.client_id<>'bd200000-0000-0000-0000-000000000001' OR created.revision<>1 OR created.replayed THEN RAISE EXCEPTION 'associate create failed'; END IF;
  created_id:=created.matter_id;
  SELECT * INTO replay FROM public.create_matter_command('bd200000-0000-0000-0000-000000000001','Created matter','2024-25','','active','bd300000-0000-0000-0000-000000000001');
  IF replay.code<>'ok' OR replay.matter_id<>created_id OR replay.revision<>1 OR NOT replay.replayed THEN RAISE EXCEPTION 'create replay failed'; END IF;
  SELECT * INTO changed FROM public.create_matter_command('bd200000-0000-0000-0000-000000000001','Changed payload','2024-25','','active','bd300000-0000-0000-0000-000000000001');
  IF changed.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'changed create replay was accepted'; END IF;
  SELECT * INTO updated FROM public.update_matter_command('bd400000-0000-0000-0000-000000000001',1,'Updated matter','2023-24','Updated description','stayed','bd300000-0000-0000-0000-000000000002');
  IF updated.code<>'ok' OR updated.revision<>2 OR updated.replayed THEN RAISE EXCEPTION 'associate update failed'; END IF;
  SELECT * INTO replay FROM public.update_matter_command('bd400000-0000-0000-0000-000000000001',1,'Updated matter','2023-24','Updated description','stayed','bd300000-0000-0000-0000-000000000002');
  IF replay.code<>'ok' OR replay.revision<>2 OR NOT replay.replayed THEN RAISE EXCEPTION 'update replay failed'; END IF;
  SELECT * INTO stale FROM public.update_matter_command('bd400000-0000-0000-0000-000000000001',1,'Stale update','2023-24','','active','bd300000-0000-0000-0000-000000000003');
  IF stale.code<>'conflict' OR stale.revision<>2 THEN RAISE EXCEPTION 'stale revision did not conflict'; END IF;
  SELECT * INTO stale FROM public.create_matter_command('bd200000-0000-0000-0000-000000000003','Inactive client matter','2024-25','','active','bd300000-0000-0000-0000-000000000004');
  IF stale.code<>'context_unavailable' THEN RAISE EXCEPTION 'inactive client accepted create'; END IF;
  SELECT * INTO stale FROM public.update_matter_command('bd400000-0000-0000-0000-000000000003',1,'Inactive update','2024-25','','active','bd300000-0000-0000-0000-000000000005');
  IF stale.code<>'context_unavailable' THEN RAISE EXCEPTION 'inactive matter accepted update'; END IF;
END $associate_paths$;
RESET ROLE;

DO $atomic_effects$
BEGIN
  IF (SELECT financial_year FROM public.documents WHERE id='bd500000-0000-0000-0000-000000000001')<>'2023-24'
     OR (SELECT count(*) FROM public.activity_logs WHERE action='matter_created' AND user_id='bd000000-0000-0000-0000-000000000002')<>1
     OR (SELECT count(*) FROM public.activity_logs WHERE action='matter_updated' AND entity_id='bd400000-0000-0000-0000-000000000001')<>1 THEN
    RAISE EXCEPTION 'matter mutation side effects were missing or duplicated';
  END IF;
END $atomic_effects$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000004',true);
DO $viewer_denial$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.create_matter_command('bd200000-0000-0000-0000-000000000001','Viewer matter','2024-25','','active','bd300000-0000-0000-0000-000000000006');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'Viewer created a matter'; END IF;
  BEGIN INSERT INTO public.matters(org_id,client_id,title,financial_year) VALUES('bd100000-0000-0000-0000-000000000001','bd200000-0000-0000-0000-000000000001','Direct viewer','2024-25'); RAISE EXCEPTION 'direct Viewer insert succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $viewer_denial$;
RESET ROLE;

SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000003',true);
DO $admin_path$ DECLARE result record; BEGIN SELECT * INTO result FROM public.create_matter_command('bd200000-0000-0000-0000-000000000001','Admin matter','2022-23','','active','bd300000-0000-0000-0000-000000000007'); IF result.code<>'ok' THEN RAISE EXCEPTION 'Admin create failed'; END IF; END $admin_path$;
RESET ROLE;
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000001',true);
DO $owner_path$ DECLARE result record; BEGIN SELECT * INTO result FROM public.create_matter_command('bd200000-0000-0000-0000-000000000001','Owner matter','2021-22','','active','bd300000-0000-0000-0000-000000000008'); IF result.code<>'ok' THEN RAISE EXCEPTION 'Owner create failed'; END IF; END $owner_path$;
RESET ROLE;
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000005',true);
DO $suspended_denial$ DECLARE result record; BEGIN SELECT * INTO result FROM public.create_matter_command('bd200000-0000-0000-0000-000000000001','Suspended matter','2024-25','','active','bd300000-0000-0000-0000-000000000009'); IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'suspended member created a matter'; END IF; END $suspended_denial$;
RESET ROLE;
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000006',true);
DO $removed_denial$ DECLARE result record; BEGIN SELECT * INTO result FROM public.create_matter_command('bd200000-0000-0000-0000-000000000001','Removed matter','2024-25','','active','bd300000-0000-0000-0000-000000000010'); IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'removed member created a matter'; END IF; END $removed_denial$;
RESET ROLE;
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','bd000000-0000-0000-0000-000000000007',true);
DO $cross_tenant_denial$ DECLARE result record; BEGIN SELECT * INTO result FROM public.update_matter_command('bd400000-0000-0000-0000-000000000001',2,'Foreign update','2024-25','','active','bd300000-0000-0000-0000-000000000011'); IF result.code<>'context_unavailable' OR result.matter_id IS NOT NULL THEN RAISE EXCEPTION 'cross-tenant matter was disclosed'; END IF; END $cross_tenant_denial$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $service_direct_denial$ BEGIN
  BEGIN UPDATE public.matters SET title='Service bypass' WHERE id='bd400000-0000-0000-0000-000000000001'; RAISE EXCEPTION 'service update succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $service_direct_denial$;
RESET ROLE;

ROLLBACK;
