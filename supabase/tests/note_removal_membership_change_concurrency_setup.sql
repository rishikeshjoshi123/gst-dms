\set ON_ERROR_STOP on
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000','ba000000-0000-0000-0000-000000000001','authenticated','authenticated','note-race-owner@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','ba000000-0000-0000-0000-000000000002','authenticated','authenticated','note-race-author@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by)
VALUES ('ba100000-0000-0000-0000-000000000001','Note removal race','ba000000-0000-0000-0000-000000000001');
INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at)
VALUES ('ba110000-0000-0000-0000-000000000002','ba100000-0000-0000-0000-000000000001','ba000000-0000-0000-0000-000000000002','associate','active',1,now());
UPDATE public.organisations AS organisation SET owner_membership_id=membership.id
FROM public.organisation_memberships AS membership
WHERE organisation.id=membership.org_id AND membership.user_id=organisation.created_by;
INSERT INTO public.clients(id,org_id,name)
VALUES ('ba200000-0000-0000-0000-000000000001','ba100000-0000-0000-0000-000000000001','Note race client');
INSERT INTO public.matters(id,org_id,client_id,title)
VALUES ('ba300000-0000-0000-0000-000000000001','ba100000-0000-0000-0000-000000000001','ba200000-0000-0000-0000-000000000001','Note race matter');
INSERT INTO public.case_notes(id,org_id,matter_id,author_id,content)
VALUES ('ba400000-0000-0000-0000-000000000001','ba100000-0000-0000-0000-000000000001','ba300000-0000-0000-0000-000000000001','ba000000-0000-0000-0000-000000000002','Membership-lock removal');
