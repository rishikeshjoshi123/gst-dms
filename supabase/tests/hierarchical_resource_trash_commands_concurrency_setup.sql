-- Disposable setup for the two-session hierarchy Trash race harness.
DO $setup$
DECLARE
  org uuid := '81000000-0000-0000-0000-000000000001';
  actor uuid := '81100000-0000-0000-0000-000000000001';
  client uuid := '81200000-0000-0000-0000-000000000001';
  matter uuid := '81300000-0000-0000-0000-000000000001';
  document uuid := '81400000-0000-0000-0000-000000000001';
  membership uuid;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000',actor,'authenticated','authenticated','trash-race@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES (org,'Trash race fixture',actor);
  SELECT id INTO membership FROM public.organisation_memberships WHERE org_id=org AND user_id=actor AND state='active';
  UPDATE public.organisations SET owner_membership_id=membership WHERE id=org;
  INSERT INTO public.clients(id,org_id,name) VALUES (client,org,'Race client');
  INSERT INTO public.matters(id,org_id,client_id,title,financial_year) VALUES (matter,org,client,'Race matter','2026-27');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by) VALUES (document,org,matter,'fixture/race.pdf',actor);
END $setup$;
