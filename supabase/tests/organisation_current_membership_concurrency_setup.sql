-- Run after `npx supabase db reset --local --no-seed`.
\set ON_ERROR_STOP on
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000','d1000000-0000-0000-0000-000000000001','authenticated','authenticated','race-owner-a@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','d1000000-0000-0000-0000-000000000002','authenticated','authenticated','race-owner-b@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','d1000000-0000-0000-0000-000000000003','authenticated','authenticated','race-joiner@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES
  ('d1100000-0000-0000-0000-000000000001','Race organisation A','d1000000-0000-0000-0000-000000000001'),
  ('d1100000-0000-0000-0000-000000000002','Race organisation B','d1000000-0000-0000-0000-000000000002');
UPDATE public.organisations AS organisation SET owner_membership_id=membership.id FROM public.organisation_memberships AS membership WHERE organisation.id=membership.org_id AND organisation.created_by=membership.user_id;
INSERT INTO public.organisation_invites(id,org_id,normalized_email,role,state,selector_hash,invited_by_user_id,lifecycle_actor_id,idempotency_key)
VALUES
  ('d1200000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000001','race-joiner@test.invalid','associate','pending',repeat('a',64),'d1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','d1300000-0000-0000-0000-000000000001'),
  ('d1200000-0000-0000-0000-000000000002','d1100000-0000-0000-0000-000000000002','race-joiner@test.invalid','associate','pending',repeat('b',64),'d1000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000002','d1300000-0000-0000-0000-000000000002');
