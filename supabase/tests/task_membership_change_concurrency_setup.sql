-- Run after `npx supabase db reset --local --no-seed`.
\set ON_ERROR_STOP on
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000','e1000000-0000-0000-0000-000000000001','authenticated','authenticated','task-race-owner@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','e1000000-0000-0000-0000-000000000002','authenticated','authenticated','task-race-associate@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES ('e1100000-0000-0000-0000-000000000001','Task membership race','e1000000-0000-0000-0000-000000000001');
INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at) VALUES ('e1110000-0000-0000-0000-000000000002','e1100000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000002','associate','active',1,now());
UPDATE public.organisations AS organisation SET owner_membership_id=membership.id FROM public.organisation_memberships AS membership WHERE organisation.id=membership.org_id AND membership.user_id=organisation.created_by;
INSERT INTO public.clients(id,org_id,name) VALUES ('e1200000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001','Task membership race client');
INSERT INTO public.matters(id,org_id,client_id,title) VALUES ('e1300000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001','e1200000-0000-0000-0000-000000000001','Task membership race matter');
INSERT INTO public.case_notes(id,org_id,author_id,matter_id,content,template_type,is_action_item) VALUES ('e1400000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','e1300000-0000-0000-0000-000000000001','Task membership race','general',true);
INSERT INTO public.tasks(id,org_id,client_id,matter_id,title,origin_kind,origin_note_id,origin_snapshot,creator_user_id,status_changed_by) VALUES ('e1500000-0000-0000-0000-000000000001','e1100000-0000-0000-0000-000000000001','e1200000-0000-0000-0000-000000000001','e1300000-0000-0000-0000-000000000001','Task membership race','case_note','e1400000-0000-0000-0000-000000000001','Task membership race','e1000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001');
