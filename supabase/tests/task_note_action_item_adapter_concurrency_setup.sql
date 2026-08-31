\set ON_ERROR_STOP on
BEGIN;
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000','95600000-0000-0000-0000-000000000001','authenticated','authenticated','task-race@test.invalid','x',now(),'{}','{}',now(),now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.organisations(id,name,created_by)
VALUES('95700000-0000-0000-0000-000000000001','Task race fixture','95600000-0000-0000-0000-000000000001')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.clients(id,org_id,name)
VALUES('95800000-0000-0000-0000-000000000001','95700000-0000-0000-0000-000000000001','Task race client')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.matters(id,org_id,client_id,title)
VALUES('95900000-0000-0000-0000-000000000001','95700000-0000-0000-0000-000000000001','95800000-0000-0000-0000-000000000001','Task race matter')
ON CONFLICT (id) DO NOTHING;
COMMIT;
