-- Run after migration 00128. The transaction is always rolled back.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
('00000000-0000-0000-0000-000000000000','bf000000-0000-0000-0000-000000000001','authenticated','authenticated','document-owner@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bf000000-0000-0000-0000-000000000002','authenticated','authenticated','document-associate@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bf000000-0000-0000-0000-000000000003','authenticated','authenticated','document-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bf000000-0000-0000-0000-000000000004','authenticated','authenticated','document-suspended@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bf000000-0000-0000-0000-000000000005','authenticated','authenticated','document-foreign@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES
('bf100000-0000-0000-0000-000000000001','Document authority organisation','bf000000-0000-0000-0000-000000000001'),
('bf100000-0000-0000-0000-000000000002','Foreign document organisation','bf000000-0000-0000-0000-000000000005');
INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at,suspended_at,suspended_by,suspension_reason)
VALUES
('bf110000-0000-0000-0000-000000000002','bf100000-0000-0000-0000-000000000001','bf000000-0000-0000-0000-000000000002','associate','active',1,now(),NULL,NULL,NULL),
('bf110000-0000-0000-0000-000000000003','bf100000-0000-0000-0000-000000000001','bf000000-0000-0000-0000-000000000003','viewer','active',1,now(),NULL,NULL,NULL),
('bf110000-0000-0000-0000-000000000004','bf100000-0000-0000-0000-000000000001','bf000000-0000-0000-0000-000000000004','associate','suspended',1,now(),now(),'bf000000-0000-0000-0000-000000000001','fixture');
UPDATE public.organisations AS organisation SET owner_membership_id=membership.id
FROM public.organisation_memberships AS membership
WHERE organisation.id=membership.org_id AND membership.user_id=organisation.created_by;
INSERT INTO public.clients(id,org_id,name) VALUES
('bf200000-0000-0000-0000-000000000001','bf100000-0000-0000-0000-000000000001','Document client'),
('bf200000-0000-0000-0000-000000000002','bf100000-0000-0000-0000-000000000002','Foreign document client');
INSERT INTO public.matters(id,org_id,client_id,title,financial_year) VALUES
('bf300000-0000-0000-0000-000000000001','bf100000-0000-0000-0000-000000000001','bf200000-0000-0000-0000-000000000001','Document matter','2024-25'),
('bf300000-0000-0000-0000-000000000002','bf100000-0000-0000-0000-000000000002','bf200000-0000-0000-0000-000000000002','Foreign document matter','2024-25');

DO $privileges$
BEGIN
  IF has_table_privilege('authenticated','public.documents','INSERT')
     OR has_table_privilege('service_role','public.documents','INSERT')
     OR EXISTS (
       SELECT 1 FROM information_schema.columns AS column_info
       WHERE column_info.table_schema='public' AND column_info.table_name='documents'
         AND (has_column_privilege('authenticated',format('public.%I',column_info.table_name),column_info.column_name,'INSERT')
           OR has_column_privilege('service_role',format('public.%I',column_info.table_name),column_info.column_name,'INSERT'))
     ) THEN RAISE EXCEPTION 'direct document insert privilege survived';
  END IF;
END $privileges$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','bf000000-0000-0000-0000-000000000002',true);
DO $associate_command$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.create_metadata_only_document('bf300000-0000-0000-0000-000000000001','Governed record','Notice','REF-128',current_date,'bf400000-0000-0000-0000-000000000001');
  IF result.code<>'ok' OR result.document_id IS NULL THEN RAISE EXCEPTION 'Associate canonical creation failed'; END IF;
  BEGIN INSERT INTO public.documents(org_id,matter_id,display_title) VALUES('bf100000-0000-0000-0000-000000000001','bf300000-0000-0000-0000-000000000001','Direct Associate'); RAISE EXCEPTION 'direct Associate insert succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $associate_command$;
RESET ROLE;

SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','bf000000-0000-0000-0000-000000000003',true);
DO $viewer_denial$ DECLARE result record; BEGIN SELECT * INTO result FROM public.create_metadata_only_document('bf300000-0000-0000-0000-000000000001','Viewer record',NULL,NULL,NULL,'bf400000-0000-0000-0000-000000000002'); IF result.document_id IS NOT NULL THEN RAISE EXCEPTION 'Viewer created document'; END IF; END $viewer_denial$;
RESET ROLE;
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','bf000000-0000-0000-0000-000000000004',true);
DO $suspended_denial$ DECLARE result record; BEGIN SELECT * INTO result FROM public.create_metadata_only_document('bf300000-0000-0000-0000-000000000001','Suspended record',NULL,NULL,NULL,'bf400000-0000-0000-0000-000000000003'); IF result.document_id IS NOT NULL THEN RAISE EXCEPTION 'suspended member created document'; END IF; END $suspended_denial$;
RESET ROLE;
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','bf000000-0000-0000-0000-000000000005',true);
DO $foreign_denial$ DECLARE result record; BEGIN SELECT * INTO result FROM public.create_metadata_only_document('bf300000-0000-0000-0000-000000000001','Foreign record',NULL,NULL,NULL,'bf400000-0000-0000-0000-000000000004'); IF result.code<>'invalid_matter' OR result.document_id IS NOT NULL THEN RAISE EXCEPTION 'cross-tenant document creation disclosed or succeeded'; END IF; END $foreign_denial$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $service_denial$ BEGIN
  BEGIN INSERT INTO public.documents(org_id,matter_id,display_title) VALUES('bf100000-0000-0000-0000-000000000001','bf300000-0000-0000-0000-000000000001','Direct service'); RAISE EXCEPTION 'direct service insert succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $service_denial$;
RESET ROLE;

ROLLBACK;
