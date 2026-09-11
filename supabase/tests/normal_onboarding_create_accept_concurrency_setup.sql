\set ON_ERROR_STOP on
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000','14550000-0000-0000-0000-000000000001','authenticated','authenticated','race-owner@onboarding.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','14550000-0000-0000-0000-000000000002','authenticated','authenticated','race-entry@onboarding.test','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by)
VALUES('14551000-0000-0000-0000-000000000001','Concurrent inviting organisation','14550000-0000-0000-0000-000000000001');
INSERT INTO public.organisation_invites(id,org_id,normalized_email,role,state,selector_hash,invited_by_user_id,lifecycle_actor_id,idempotency_key)
VALUES('14552000-0000-0000-0000-000000000001','14551000-0000-0000-0000-000000000001','race-entry@onboarding.test','associate','pending',repeat('d',64),'14550000-0000-0000-0000-000000000001','14550000-0000-0000-0000-000000000001','14553000-0000-0000-0000-000000000001');
