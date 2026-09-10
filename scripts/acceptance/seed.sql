\set ON_ERROR_STOP on
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- These auto-confirmed, synthetic accounts exercise feature sessions only.
-- They are not evidence for confirmation-required signup or captured mail.
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('00000000-0000-0000-0000-000000000000', 'a0010000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'owner@acceptance.test', crypt('CaseChain-local-only-2026!', gen_salt('bf')), now(), '', '', '', '', '{"provider":"email","providers":["email"]}', '{"full_name":"Acceptance Owner"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a0010000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'viewer@acceptance.test', crypt('CaseChain-local-only-2026!', gen_salt('bf')), now(), '', '', '', '', '{"provider":"email","providers":["email"]}', '{"full_name":"Read-only Viewer"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a0010000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'foreign@acceptance.test', crypt('CaseChain-local-only-2026!', gen_salt('bf')), now(), '', '', '', '', '{"provider":"email","providers":["email"]}', '{"full_name":"Foreign Owner"}', now(), now());

INSERT INTO auth.identities (provider_id, user_id, identity_data, provider, id, created_at, updated_at, last_sign_in_at) VALUES
  ('owner@acceptance.test', 'a0010000-0000-0000-0000-000000000001', '{"sub":"a0010000-0000-0000-0000-000000000001","email":"owner@acceptance.test","email_verified":true}', 'email', 'a0010000-0000-0000-0000-000000000001', now(), now(), now()),
  ('viewer@acceptance.test', 'a0010000-0000-0000-0000-000000000002', '{"sub":"a0010000-0000-0000-0000-000000000002","email":"viewer@acceptance.test","email_verified":true}', 'email', 'a0010000-0000-0000-0000-000000000002', now(), now(), now()),
  ('foreign@acceptance.test', 'a0010000-0000-0000-0000-000000000003', '{"sub":"a0010000-0000-0000-0000-000000000003","email":"foreign@acceptance.test","email_verified":true}', 'email', 'a0010000-0000-0000-0000-000000000003', now(), now(), now());

INSERT INTO public.organisations (id, name, created_by) VALUES
  ('b0010000-0000-0000-0000-000000000001', 'Acceptance Chambers', 'a0010000-0000-0000-0000-000000000001'),
  ('b0010000-0000-0000-0000-000000000002', 'Foreign Chambers', 'a0010000-0000-0000-0000-000000000003');

INSERT INTO public.org_members (org_id, user_id, role) VALUES
  ('b0010000-0000-0000-0000-000000000001', 'a0010000-0000-0000-0000-000000000002', 'viewer');

INSERT INTO public.user_profiles (user_id, display_name, professional_title) VALUES
  ('a0010000-0000-0000-0000-000000000001', 'Acceptance Owner', 'Partner'),
  ('a0010000-0000-0000-0000-000000000002', 'Read-only Viewer', 'Observer'),
  ('a0010000-0000-0000-0000-000000000003', 'Foreign Owner', 'Partner')
ON CONFLICT (user_id) DO UPDATE
SET display_name = EXCLUDED.display_name,
    professional_title = EXCLUDED.professional_title;

INSERT INTO public.clients (id, org_id, name) VALUES
  ('c0010000-0000-0000-0000-000000000001', 'b0010000-0000-0000-0000-000000000001', 'Aster Manufacturing'),
  ('c0010000-0000-0000-0000-000000000002', 'b0010000-0000-0000-0000-000000000002', 'Foreign Manufacturing');

INSERT INTO public.matters (id, org_id, client_id, title, matter_code, financial_year, work_state, current_forum) VALUES
  ('d0010000-0000-0000-0000-000000000001', 'b0010000-0000-0000-0000-000000000001', 'c0010000-0000-0000-0000-000000000001', 'Aster GST appeal', 'AC/GST/2026/001', '2025-26', 'active', 'tribunal'),
  ('d0010000-0000-0000-0000-000000000002', 'b0010000-0000-0000-0000-000000000002', 'c0010000-0000-0000-0000-000000000002', 'Foreign confidential matter', 'FC/GST/2026/001', '2025-26', 'active', 'adjudication');

INSERT INTO public.documents (
  id, org_id, matter_id, display_title, doc_type, reference_number, doc_date,
  direction, document_class, origin_kind, content_availability, status, created_by
) VALUES
  ('e0010000-0000-0000-0000-000000000001', 'b0010000-0000-0000-0000-000000000001', 'd0010000-0000-0000-0000-000000000001', 'Order in Original', 'OIO', 'OIO/ASTER/2026/17', '2026-08-19', 'incoming', 'proceeding', 'manual_record', 'metadata_only', 'placed', 'a0010000-0000-0000-0000-000000000001'),
  ('e0010000-0000-0000-0000-000000000002', 'b0010000-0000-0000-0000-000000000002', 'd0010000-0000-0000-0000-000000000002', 'Foreign order', 'OIO', 'OIO/FOREIGN/2026/9', '2026-08-20', 'incoming', 'proceeding', 'manual_record', 'metadata_only', 'placed', 'a0010000-0000-0000-0000-000000000003');

COMMIT;
