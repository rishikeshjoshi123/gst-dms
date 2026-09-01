-- Run after a local reset, before task_comment_thread_concurrency.sh.
\set ON_ERROR_STOP on
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
('00000000-0000-0000-0000-000000000000','c1000000-0000-0000-0000-000000000001','authenticated','authenticated','comment-race-owner@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','c1000000-0000-0000-0000-000000000002','authenticated','authenticated','comment-race-associate@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES ('c1100000-0000-0000-0000-000000000001','Comment race','c1000000-0000-0000-0000-000000000001');
INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at) VALUES ('c1110000-0000-0000-0000-000000000002','c1100000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002','associate','active',1,now());
UPDATE public.organisations AS organisation SET owner_membership_id=membership.id FROM public.organisation_memberships AS membership WHERE organisation.id=membership.org_id AND membership.user_id=organisation.created_by;
INSERT INTO public.clients(id,org_id,name) VALUES ('c1200000-0000-0000-0000-000000000001','c1100000-0000-0000-0000-000000000001','Comment race client');
INSERT INTO public.matters(id,org_id,client_id,title) VALUES ('c1300000-0000-0000-0000-000000000001','c1100000-0000-0000-0000-000000000001','c1200000-0000-0000-0000-000000000001','Comment race matter');
INSERT INTO public.tasks(id,org_id,client_id,matter_id,title,origin_kind,origin_note_id,origin_snapshot,creator_user_id,assignee_user_id,status_changed_by) VALUES ('c1500000-0000-0000-0000-000000000001','c1100000-0000-0000-0000-000000000001','c1200000-0000-0000-0000-000000000001','c1300000-0000-0000-0000-000000000001','Comment race task','case_note','c1400000-0000-0000-0000-000000000001','Independent origin','c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000001');
