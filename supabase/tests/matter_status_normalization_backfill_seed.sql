-- PRE-00141 SETUP: run only against a disposable database migrated through
-- 00140. Migration 00141 must be applied after this atomic seed, followed by
-- matter_status_normalization_backfill_assert.sql. Never run against shared or
-- production data; the disposable database is the cleanup boundary.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  'f4100000-0000-0000-0000-000000000001',
  'authenticated','authenticated','matter-backfill@test.invalid','x',now(),
  '{}','{}',now(),now()
);

INSERT INTO public.organisations(id,name,created_by) VALUES (
  'f4110000-0000-0000-0000-000000000001',
  'Matter normalization backfill fixture',
  'f4100000-0000-0000-0000-000000000001'
);
INSERT INTO public.clients(id,org_id,name) VALUES (
  'f4130000-0000-0000-0000-000000000001',
  'f4110000-0000-0000-0000-000000000001',
  'Matter normalization backfill client'
);

INSERT INTO public.matters(id,org_id,client_id,title,financial_year,status)
SELECT
  ('f4140000-0000-0000-0000-'||lpad(ordinality::text,12,'0'))::uuid,
  'f4110000-0000-0000-0000-000000000001',
  'f4130000-0000-0000-0000-000000000001',
  'Pre-00141 '||legacy_status,
  'FY-'||ordinality,
  legacy_status::public.matter_status
FROM unnest(ARRAY[
  'active','stayed','disposed','appeal_pending','tribunal','high_court',
  'supreme_court','closed'
]::text[]) WITH ORDINALITY AS legacy(legacy_status,ordinality);

UPDATE public.matters
SET record_state='trashed',deleted_at=now()
WHERE id='f4140000-0000-0000-0000-000000000008';

COMMIT;
