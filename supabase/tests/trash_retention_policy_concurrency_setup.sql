INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES('00000000-0000-0000-0000-000000000000','91100000-0000-0000-0000-000000000001','authenticated','authenticated','retention-race@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by)
VALUES('91000000-0000-0000-0000-000000000001','Retention race','91100000-0000-0000-0000-000000000001');
UPDATE public.organisations organisation SET owner_membership_id=membership.id
FROM public.organisation_memberships membership
WHERE organisation.id='91000000-0000-0000-0000-000000000001'
  AND membership.org_id=organisation.id AND membership.user_id='91100000-0000-0000-0000-000000000001';
INSERT INTO public.clients(id,org_id,name,gstin,pan)
VALUES('91200000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001','Retention race','27GGGGG0000G1Z5','GGGGG0000G');
INSERT INTO public.matters(id,org_id,client_id,title,financial_year,matter_code)
VALUES('91300000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001','91200000-0000-0000-0000-000000000001','Retention race matter','2026-27','RACE-2627-01');
INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by)
VALUES('91400000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001','91300000-0000-0000-0000-000000000001','fixture/retention-race.pdf','91100000-0000-0000-0000-000000000001');
