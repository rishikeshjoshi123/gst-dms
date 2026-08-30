\set ON_ERROR_STOP on
BEGIN;
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES('00000000-0000-0000-0000-000000000000','88100000-0000-0000-0000-000000000010','authenticated','authenticated','restore-concurrency@test.invalid','x',now(),'{}','{}',now(),now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.organisations(id,name,created_by)
VALUES('88000000-0000-0000-0000-000000000010','Restore concurrency','88100000-0000-0000-0000-000000000010')
ON CONFLICT (id) DO NOTHING;
UPDATE public.organisations organisation SET owner_membership_id=membership.id
FROM public.organisation_memberships membership
WHERE organisation.id='88000000-0000-0000-0000-000000000010'
  AND membership.org_id=organisation.id AND membership.user_id='88100000-0000-0000-0000-000000000010';
INSERT INTO public.clients(id,org_id,name) VALUES(
  '88200000-0000-0000-0000-000000000010','88000000-0000-0000-0000-000000000010','Restore concurrency client'
) ON CONFLICT (id) DO NOTHING;
INSERT INTO public.matters(id,org_id,client_id,title,financial_year,matter_code) VALUES(
  '88300000-0000-0000-0000-000000000010','88000000-0000-0000-0000-000000000010',
  '88200000-0000-0000-0000-000000000010','Restore concurrency matter','2026-27','RSC-2627-10'
) ON CONFLICT (id) DO NOTHING;
INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by) VALUES(
  '88400000-0000-0000-0000-000000000010','88000000-0000-0000-0000-000000000010',
  '88300000-0000-0000-0000-000000000010','restore/concurrent.pdf','88100000-0000-0000-0000-000000000010'
) ON CONFLICT (id) DO NOTHING;
SELECT set_config('request.jwt.claim.role','authenticated',false);
SELECT set_config('request.jwt.claim.sub','88100000-0000-0000-0000-000000000010',false);
SELECT operation_id AS operation_id FROM public.trash_resource(
  'document','88400000-0000-0000-0000-000000000010','fixture.concurrent.restore'
) \gset
COMMIT;
\echo :operation_id
