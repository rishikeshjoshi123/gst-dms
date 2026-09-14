\set ON_ERROR_STOP on
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES('00000000-0000-0000-0000-000000000000','16500000-0000-0000-0000-000000000001','authenticated','authenticated','race-owner@invite.test','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by)
VALUES('16510000-0000-0000-0000-000000000001','Invitation race fixture','16500000-0000-0000-0000-000000000001');
