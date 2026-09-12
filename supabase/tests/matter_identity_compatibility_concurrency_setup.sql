-- Persistent disposable setup for the simultaneous same-client/year create race.
\set ON_ERROR_STOP on
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
  ('00000000-0000-0000-0000-000000000000','a1481000-0000-0000-0000-000000000001','authenticated','authenticated','race-owner@matter-cutover.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1481000-0000-0000-0000-000000000002','authenticated','authenticated','race-associate@matter-cutover.test','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by)
VALUES('b1481000-0000-0000-0000-000000000001','Concurrent Matter identity cutover','a1481000-0000-0000-0000-000000000001');
INSERT INTO public.org_members(org_id,user_id,role)
VALUES('b1481000-0000-0000-0000-000000000001','a1481000-0000-0000-0000-000000000002','associate');
INSERT INTO public.clients(id,org_id,name)
VALUES('c1481000-0000-0000-0000-000000000001','b1481000-0000-0000-0000-000000000001','Race Compatibility Client');
