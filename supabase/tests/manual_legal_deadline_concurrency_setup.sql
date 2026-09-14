\set ON_ERROR_STOP on
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES('00000000-0000-0000-0000-000000000000','a1590000-0000-0000-0000-000000000101','authenticated','authenticated','concurrency@deadline.test','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES('b1590000-0000-0000-0000-000000000101','Deadline concurrency','a1590000-0000-0000-0000-000000000101');
INSERT INTO public.clients(id,org_id,name) VALUES('c1590000-0000-0000-0000-000000000101','b1590000-0000-0000-0000-000000000101','Concurrency client');
INSERT INTO public.matters(id,org_id,client_id,title,status) VALUES('d1590000-0000-0000-0000-000000000101','b1590000-0000-0000-0000-000000000101','c1590000-0000-0000-0000-000000000101','Concurrency matter','active');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',false);
SELECT set_config('request.jwt.claim.sub','a1590000-0000-0000-0000-000000000101',false);
SELECT deadline_id FROM public.create_manual_legal_deadline('d1590000-0000-0000-0000-000000000101','Concurrent amendment','Original obligation','other_legal','2028-02-29','Human-checked leap-day fixture','f1590000-0000-0000-0000-000000000101');
