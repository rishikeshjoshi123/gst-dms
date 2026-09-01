-- Run after `npx supabase db reset --local --no-seed` on a disposable database.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES ('00000000-0000-0000-0000-000000000000','b1000000-0000-0000-0000-000000000001','authenticated','authenticated','task-transition-race@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by)
VALUES ('b1100000-0000-0000-0000-000000000001','Task transition race','b1000000-0000-0000-0000-000000000001');
UPDATE public.organisations AS organisation
SET owner_membership_id = membership.id
FROM public.organisation_memberships AS membership
WHERE organisation.id=membership.org_id AND membership.user_id=organisation.created_by;
INSERT INTO public.clients(id,org_id,name)
VALUES ('b1200000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','Task transition race client');
INSERT INTO public.matters(id,org_id,client_id,title)
VALUES ('b1300000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-000000000001','Task transition race matter');
INSERT INTO public.case_notes(id,org_id,author_id,matter_id,content,template_type,is_action_item)
VALUES ('b1400000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','Race origin','general',true);
INSERT INTO public.tasks(id,org_id,client_id,matter_id,title,origin_kind,origin_note_id,origin_snapshot,creator_user_id,status_changed_by)
VALUES ('b1500000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','Race Task','case_note','b1400000-0000-0000-0000-000000000001','Race origin','b1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001');
COMMIT;
