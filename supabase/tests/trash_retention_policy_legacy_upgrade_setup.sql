-- Migration 00079 accepts this legacy row because the CHECK expression is
-- UNKNOWN for retention_period + NULL days. Migration 00090 must normalize it
-- before making trash_retention_days NOT NULL.
INSERT INTO auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
)
VALUES(
  '00000000-0000-0000-0000-000000000000',
  '92100000-0000-0000-0000-000000000001',
  'authenticated','authenticated','retention-legacy-upgrade@test.invalid','x',now(),
  '{}','{}',now(),now()
);

INSERT INTO public.organisations(id,name,created_by)
VALUES(
  '92000000-0000-0000-0000-000000000001',
  'Legacy retention upgrade fixture',
  '92100000-0000-0000-0000-000000000001'
);

INSERT INTO public.organisation_retention_settings(
  org_id,trash_retention_mode,trash_retention_days,auto_purge_enabled,policy_version
)
VALUES(
  '92000000-0000-0000-0000-000000000001',
  'retention_period',NULL,true,1
);
