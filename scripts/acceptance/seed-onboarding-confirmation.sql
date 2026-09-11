\set ON_ERROR_STOP on
BEGIN;

DO $seed$
DECLARE
  owner_a uuid := '14600000-0000-0000-0000-000000000001';
  owner_b uuid := '14600000-0000-0000-0000-000000000002';
  org_a uuid := '14610000-0000-0000-0000-000000000001';
  org_b uuid := '14610000-0000-0000-0000-000000000002';
BEGIN
  INSERT INTO auth.users(
    instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    raw_app_meta_data,raw_user_meta_data,created_at,updated_at
  ) VALUES
    ('00000000-0000-0000-0000-000000000000',owner_a,'authenticated','authenticated','confirmation-owner-a@onboarding.test','x',clock_timestamp(),'{}','{"full_name":"Confirmation Owner A"}',clock_timestamp(),clock_timestamp()),
    ('00000000-0000-0000-0000-000000000000',owner_b,'authenticated','authenticated','confirmation-owner-b@onboarding.test','x',clock_timestamp(),'{}','{"full_name":"Confirmation Owner B"}',clock_timestamp(),clock_timestamp());

  INSERT INTO public.organisations(id,name,created_by) VALUES
    (org_a,'Bengaluru Indirect Tax Chambers',owner_a),
    (org_b,'A very long invited organisation name used to prove that onboarding actions remain available without horizontal overflow on a narrow phone viewport',owner_b);

  INSERT INTO public.organisation_invites(
    id,org_id,normalized_email,role,state,selector_hash,invited_by_user_id,
    lifecycle_actor_id,idempotency_key,expires_at,expired_at,revoked_at
  ) VALUES
    ('14620000-0000-0000-0000-000000000001',org_a,'join-browser@onboarding.test','associate','pending',repeat('a',64),owner_a,owner_a,'14630000-0000-0000-0000-000000000001',clock_timestamp()+interval '1 day',NULL,NULL),
    ('14620000-0000-0000-0000-000000000002',org_b,'join-browser@onboarding.test','viewer','pending',repeat('b',64),owner_b,owner_b,'14630000-0000-0000-0000-000000000002',clock_timestamp()+interval '1 day',NULL,NULL),
    ('14620000-0000-0000-0000-000000000003',org_a,'join-browser@onboarding.test','viewer','expired',NULL,owner_a,owner_a,'14630000-0000-0000-0000-000000000003',clock_timestamp()-interval '1 second',clock_timestamp(),NULL),
    ('14620000-0000-0000-0000-000000000004',org_b,'join-browser@onboarding.test','viewer','revoked',NULL,owner_b,owner_b,'14630000-0000-0000-0000-000000000004',clock_timestamp()+interval '1 day',NULL,clock_timestamp()),
    ('14620000-0000-0000-0000-000000000005',org_a,'foreign-browser@onboarding.test','viewer','pending',repeat('c',64),owner_a,owner_a,'14630000-0000-0000-0000-000000000005',clock_timestamp()+interval '1 day',NULL,NULL);
END $seed$;

COMMIT;
