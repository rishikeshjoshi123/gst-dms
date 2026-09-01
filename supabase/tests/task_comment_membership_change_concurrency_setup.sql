-- Run after a local reset, before task_comment_membership_change_concurrency.sh.
\set ON_ERROR_STOP on
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
('00000000-0000-0000-0000-000000000000','f1000000-0000-0000-0000-000000000001','authenticated','authenticated','comment-member-owner@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','f1000000-0000-0000-0000-000000000002','authenticated','authenticated','comment-member-associate@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES ('f1100000-0000-0000-0000-000000000001','Comment membership race','f1000000-0000-0000-0000-000000000001');
INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at) VALUES ('f1110000-0000-0000-0000-000000000002','f1100000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','associate','active',1,now());
UPDATE public.organisations AS organisation SET owner_membership_id=membership.id FROM public.organisation_memberships AS membership WHERE organisation.id=membership.org_id AND membership.user_id=organisation.created_by;
INSERT INTO public.clients(id,org_id,name) VALUES ('f1200000-0000-0000-0000-000000000001','f1100000-0000-0000-0000-000000000001','Comment membership client');
INSERT INTO public.matters(id,org_id,client_id,title) VALUES ('f1300000-0000-0000-0000-000000000001','f1100000-0000-0000-0000-000000000001','f1200000-0000-0000-0000-000000000001','Comment membership matter');
INSERT INTO public.tasks(id,org_id,client_id,matter_id,title,origin_kind,origin_note_id,origin_snapshot,creator_user_id,status_changed_by) VALUES ('f1500000-0000-0000-0000-000000000001','f1100000-0000-0000-0000-000000000001','f1200000-0000-0000-0000-000000000001','f1300000-0000-0000-0000-000000000001','Comment membership task','case_note','f1400000-0000-0000-0000-000000000001','Independent origin','f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001');
