\set ON_ERROR_STOP on
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
('00000000-0000-0000-0000-000000000000','bc000000-0000-0000-0000-000000000001','authenticated','authenticated','client-race-owner@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','bc000000-0000-0000-0000-000000000002','authenticated','authenticated','client-race-associate@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by)
VALUES('bc100000-0000-0000-0000-000000000001','Client mutation race','bc000000-0000-0000-0000-000000000001');
INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at)
VALUES('bc110000-0000-0000-0000-000000000002','bc100000-0000-0000-0000-000000000001','bc000000-0000-0000-0000-000000000002','associate','active',1,now());
UPDATE public.organisations AS organisation SET owner_membership_id=membership.id
FROM public.organisation_memberships AS membership
WHERE organisation.id=membership.org_id AND membership.user_id=organisation.created_by;
