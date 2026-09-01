-- Run after a local reset, before task_comment_trash_concurrency.sh.
\set ON_ERROR_STOP on
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
('00000000-0000-0000-0000-000000000000','d1000000-0000-0000-0000-000000000001','authenticated','authenticated','comment-trash-owner@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','d1000000-0000-0000-0000-000000000002','authenticated','authenticated','comment-trash-associate@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES ('d1100000-0000-0000-0000-000000000001','Comment Trash race','d1000000-0000-0000-0000-000000000001');
INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at) VALUES ('d1110000-0000-0000-0000-000000000002','d1100000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000002','associate','active',1,now());
UPDATE public.organisations AS organisation SET owner_membership_id=membership.id FROM public.organisation_memberships AS membership WHERE organisation.id=membership.org_id AND membership.user_id=organisation.created_by;
INSERT INTO public.clients(id,org_id,name) VALUES ('d1200000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000001','Comment Trash client');
INSERT INTO public.matters(id,org_id,client_id,title) VALUES ('d1300000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000001','d1200000-0000-0000-0000-000000000001','Comment Trash matter');
INSERT INTO public.tasks(id,org_id,client_id,matter_id,title,origin_kind,origin_note_id,origin_snapshot,creator_user_id,status_changed_by) VALUES ('d1500000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000001','d1200000-0000-0000-0000-000000000001','d1300000-0000-0000-0000-000000000001','Comment Trash task','case_note','d1400000-0000-0000-0000-000000000001','Independent origin','d1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001');
