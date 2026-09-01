-- Run by task_legacy_note_action_item_backfill_concurrency.sh after a local reset.
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES ('00000000-0000-0000-0000-000000000000','11600000-0000-0000-0000-000000000001','authenticated','authenticated','legacy-backfill-concurrency@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by)
VALUES ('11700000-0000-0000-0000-000000000001','Legacy backfill concurrency','11600000-0000-0000-0000-000000000001');
INSERT INTO public.clients(id,org_id,name)
VALUES ('11800000-0000-0000-0000-000000000001','11700000-0000-0000-0000-000000000001','Legacy concurrency client');
INSERT INTO public.matters(id,org_id,client_id,title,financial_year)
VALUES ('11900000-0000-0000-0000-000000000001','11700000-0000-0000-0000-000000000001','11800000-0000-0000-0000-000000000001','Legacy concurrency matter','2026-27');
INSERT INTO public.case_notes(id,org_id,author_id,matter_id,content,template_type,is_action_item)
VALUES ('11a00000-0000-0000-0000-000000000001','11700000-0000-0000-0000-000000000001','11600000-0000-0000-0000-000000000001','11900000-0000-0000-0000-000000000001','Concurrent legacy action','general',true);
