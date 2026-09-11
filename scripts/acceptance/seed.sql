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
  ('00000000-0000-0000-0000-000000000000', 'a0010000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'owner@acceptance.test', crypt('CaseChain-local-only-2026!', gen_salt('bf')), now(), '', '', '', '', '{"provider":"email","providers":["email"]}', '{"full_name":"Acceptance Owner"}', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('00000000-0000-0000-0000-000000000000', 'a0010000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'viewer@acceptance.test', crypt('CaseChain-local-only-2026!', gen_salt('bf')), now(), '', '', '', '', '{"provider":"email","providers":["email"]}', '{"full_name":"Read-only Viewer"}', '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z'),
  ('00000000-0000-0000-0000-000000000000', 'a0010000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'foreign@acceptance.test', crypt('CaseChain-local-only-2026!', gen_salt('bf')), now(), '', '', '', '', '{"provider":"email","providers":["email"]}', '{"full_name":"Foreign Owner"}', '2026-01-03T00:00:00Z', '2026-01-03T00:00:00Z'),
  ('00000000-0000-0000-0000-000000000000', 'a0010000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'admin@acceptance.test', crypt('CaseChain-local-only-2026!', gen_salt('bf')), now(), '', '', '', '', '{"provider":"email","providers":["email"]}', '{"full_name":"Acceptance Administrator"}', '2026-01-04T00:00:00Z', '2026-01-04T00:00:00Z'),
  ('00000000-0000-0000-0000-000000000000', 'a0010000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'suspended@acceptance.test', crypt('CaseChain-local-only-2026!', gen_salt('bf')), now(), '', '', '', '', '{"provider":"email","providers":["email"]}', '{"full_name":"Suspended Associate"}', '2026-01-05T00:00:00Z', '2026-01-05T00:00:00Z'),
  ('00000000-0000-0000-0000-000000000000', 'a0010000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'associate@acceptance.test', crypt('CaseChain-local-only-2026!', gen_salt('bf')), now(), '', '', '', '', '{"provider":"email","providers":["email"]}', '{"full_name":"Acceptance Associate"}', '2026-01-06T00:00:00Z', '2026-01-06T00:00:00Z');

INSERT INTO auth.identities (provider_id, user_id, identity_data, provider, id, created_at, updated_at, last_sign_in_at) VALUES
  ('owner@acceptance.test', 'a0010000-0000-0000-0000-000000000001', '{"sub":"a0010000-0000-0000-0000-000000000001","email":"owner@acceptance.test","email_verified":true}', 'email', 'a0010000-0000-0000-0000-000000000001', now(), now(), now()),
  ('viewer@acceptance.test', 'a0010000-0000-0000-0000-000000000002', '{"sub":"a0010000-0000-0000-0000-000000000002","email":"viewer@acceptance.test","email_verified":true}', 'email', 'a0010000-0000-0000-0000-000000000002', now(), now(), now()),
  ('foreign@acceptance.test', 'a0010000-0000-0000-0000-000000000003', '{"sub":"a0010000-0000-0000-0000-000000000003","email":"foreign@acceptance.test","email_verified":true}', 'email', 'a0010000-0000-0000-0000-000000000003', now(), now(), now()),
  ('admin@acceptance.test', 'a0010000-0000-0000-0000-000000000004', '{"sub":"a0010000-0000-0000-0000-000000000004","email":"admin@acceptance.test","email_verified":true}', 'email', 'a0010000-0000-0000-0000-000000000004', now(), now(), now()),
  ('suspended@acceptance.test', 'a0010000-0000-0000-0000-000000000005', '{"sub":"a0010000-0000-0000-0000-000000000005","email":"suspended@acceptance.test","email_verified":true}', 'email', 'a0010000-0000-0000-0000-000000000005', now(), now(), now()),
  ('associate@acceptance.test', 'a0010000-0000-0000-0000-000000000006', '{"sub":"a0010000-0000-0000-0000-000000000006","email":"associate@acceptance.test","email_verified":true}', 'email', 'a0010000-0000-0000-0000-000000000006', now(), now(), now());

INSERT INTO public.organisations (id, name, created_by) VALUES
  ('b0010000-0000-0000-0000-000000000001', 'Acceptance Chambers', 'a0010000-0000-0000-0000-000000000001'),
  ('b0010000-0000-0000-0000-000000000002', 'Foreign Chambers', 'a0010000-0000-0000-0000-000000000003');

-- Two cancelled signed-upload sessions conservatively retain the 50 MiB token
-- ceiling apiece. Give this disposable tenant room to prove same-file
-- reselection without weakening the production/default-policy SQL fixture.
INSERT INTO public.organisation_storage_policies (org_id, unique_asset_entitlement_bytes) VALUES
  ('b0010000-0000-0000-0000-000000000001', 268435456);

INSERT INTO public.org_members (org_id, user_id, role, joined_at) VALUES
  ('b0010000-0000-0000-0000-000000000001', 'a0010000-0000-0000-0000-000000000002', 'viewer', '2026-01-02T00:00:00Z'),
  ('b0010000-0000-0000-0000-000000000001', 'a0010000-0000-0000-0000-000000000004', 'admin', '2026-01-04T00:00:00Z'),
  ('b0010000-0000-0000-0000-000000000001', 'a0010000-0000-0000-0000-000000000005', 'associate', '2026-01-05T00:00:00Z'),
  ('b0010000-0000-0000-0000-000000000001', 'a0010000-0000-0000-0000-000000000006', 'associate', '2026-01-06T00:00:00Z');

UPDATE public.organisation_memberships
SET state = 'suspended',
    suspended_at = '2026-08-01T00:00:00Z',
    suspended_by = 'a0010000-0000-0000-0000-000000000001',
    suspension_reason = 'Synthetic acceptance state'
WHERE org_id = 'b0010000-0000-0000-0000-000000000001'
  AND user_id = 'a0010000-0000-0000-0000-000000000005';

INSERT INTO public.user_profiles (user_id, display_name, professional_title) VALUES
  ('a0010000-0000-0000-0000-000000000001', 'Acceptance Owner', 'Partner'),
  ('a0010000-0000-0000-0000-000000000002', 'Read-only Viewer', 'Observer'),
  ('a0010000-0000-0000-0000-000000000003', 'Foreign Owner', 'Partner'),
  ('a0010000-0000-0000-0000-000000000004', 'Acceptance Administrator', 'Operations lead'),
  ('a0010000-0000-0000-0000-000000000005', 'Suspended Associate', 'Associate'),
  ('a0010000-0000-0000-0000-000000000006', 'Acceptance Associate', 'Associate')
ON CONFLICT (user_id) DO UPDATE
SET display_name = EXCLUDED.display_name,
    professional_title = EXCLUDED.professional_title;

INSERT INTO public.clients (id, org_id, name) VALUES
  ('c0010000-0000-0000-0000-000000000001', 'b0010000-0000-0000-0000-000000000001', 'Aster Manufacturing'),
  ('c0010000-0000-0000-0000-000000000002', 'b0010000-0000-0000-0000-000000000002', 'Foreign Manufacturing');

INSERT INTO public.matters (id, org_id, client_id, title, matter_code, financial_year, work_state, current_forum) VALUES
  ('d0010000-0000-0000-0000-000000000001', 'b0010000-0000-0000-0000-000000000001', 'c0010000-0000-0000-0000-000000000001', 'Aster GST appeal', 'AC/GST/2026/001', '2025-26', 'active', 'tribunal'),
  ('d0020000-0000-4000-8000-000000000001', 'b0010000-0000-0000-0000-000000000001', 'c0010000-0000-0000-0000-000000000001', 'Aster upload acceptance', 'AC/GST/2026/UPLOAD', '2024-25', 'active', 'adjudication'),
  ('d0010000-0000-0000-0000-000000000002', 'b0010000-0000-0000-0000-000000000002', 'c0010000-0000-0000-0000-000000000002', 'Foreign confidential matter', 'FC/GST/2026/001', '2025-26', 'active', 'adjudication');

INSERT INTO public.documents (
  id, org_id, matter_id, display_title, doc_type, reference_number, doc_date,
  direction, document_class, origin_kind, content_availability, status, created_by, created_at
) VALUES
  ('e0010000-0000-0000-0000-000000000001', 'b0010000-0000-0000-0000-000000000001', 'd0010000-0000-0000-0000-000000000001', 'Order in Original', 'OIO', 'OIO/ASTER/2026/17', '2026-08-19', 'incoming', 'proceeding', 'upload', 'source_attached', 'placed', 'a0010000-0000-0000-0000-000000000001', '2026-08-19T10:00:00Z'),
  ('e0010000-0000-0000-0000-000000000003', 'b0010000-0000-0000-0000-000000000001', 'd0010000-0000-0000-0000-000000000001', 'Reply to Show Cause Notice', 'REPLY', 'REPLY/ASTER/2026/04', '2026-07-11', 'outgoing', 'proceeding', 'manual_record', 'metadata_only', 'placed', 'a0010000-0000-0000-0000-000000000001', '2026-07-11T10:00:00Z'),
  ('e0010000-0000-0000-0000-000000000004', 'b0010000-0000-0000-0000-000000000001', 'd0010000-0000-0000-0000-000000000001', 'Hearing Notice - source missing', 'NOTICE', 'NOTICE/ASTER/2026/08', '2026-09-01', 'incoming', 'proceeding', 'upload', 'source_unreadable', 'failed', 'a0010000-0000-0000-0000-000000000001', '2026-09-01T10:00:00Z'),
  ('e0010000-0000-0000-0000-000000000002', 'b0010000-0000-0000-0000-000000000002', 'd0010000-0000-0000-0000-000000000002', 'Foreign order', 'OIO', 'OIO/FOREIGN/2026/9', '2026-08-20', 'incoming', 'proceeding', 'manual_record', 'metadata_only', 'placed', 'a0010000-0000-0000-0000-000000000003', '2026-08-20T10:00:00Z');

INSERT INTO public.file_assets (
  id, org_id, bucket_id, object_key, byte_size, detected_mime_type, availability,
  created_by, validated_at, validated_page_count
) VALUES
  ('f0010000-0000-0000-0000-000000000001', 'b0010000-0000-0000-0000-000000000001', 'documents', 'orgs/b0010000-0000-0000-0000-000000000001/assets/f0010000-0000-0000-0000-000000000001/original.pdf', 4530, 'application/pdf', 'available', 'a0010000-0000-0000-0000-000000000001', '2026-08-19T10:00:00Z', 4),
  ('f0010000-0000-0000-0000-000000000002', 'b0010000-0000-0000-0000-000000000001', 'documents', 'orgs/b0010000-0000-0000-0000-000000000001/assets/f0010000-0000-0000-0000-000000000002/original.pdf', 4530, 'application/pdf', 'available', 'a0010000-0000-0000-0000-000000000001', '2026-09-01T10:00:00Z', 4);

INSERT INTO public.file_assets (
  id, org_id, bucket_id, object_key, sha256, byte_size, detected_mime_type, availability,
  created_by, validated_at, validated_page_count
) VALUES (
  'f0010000-0000-0000-0000-000000000003', 'b0010000-0000-0000-0000-000000000001', 'documents',
  'orgs/b0010000-0000-0000-0000-000000000001/assets/f0010000-0000-0000-0000-000000000003/original.pdf',
  '85a3dab46944bea47387d4a11867fe7c62afa3855f5c4ef68a4c442b867fb5cb',
  4564, 'application/pdf', 'available', 'a0010000-0000-0000-0000-000000000001', now(), 4
);
INSERT INTO public.upload_sessions (
  id,org_id,asset_id,declared_filename,declared_byte_size,state,created_by,uploaded_at,finalized_at
) VALUES (
  'f2010000-0000-0000-0000-000000000001','b0010000-0000-0000-0000-000000000001',
  'f0010000-0000-0000-0000-000000000003','owner-shared-intake.pdf',4564,'finalized',
  'a0010000-0000-0000-0000-000000000001',now(),now()
);
INSERT INTO public.intake_items (id,org_id,asset_id,upload_session_id,state,uploaded_by) VALUES (
  'f3010000-0000-0000-0000-000000000001','b0010000-0000-0000-0000-000000000001',
  'f0010000-0000-0000-0000-000000000003','f2010000-0000-0000-0000-000000000001','ready',
  'a0010000-0000-0000-0000-000000000001'
);

UPDATE public.file_assets
SET sha256 = 'e5ed1b9997d8267aea013af774223c8785d9c8802f642a6adc2e6ad33b7af113'
WHERE id = 'f0010000-0000-0000-0000-000000000001';

INSERT INTO public.document_versions (
  id, org_id, document_id, asset_id, version_number, original_filename, page_count,
  validation_state, state, created_by, created_at, validated_at, promoted_at
) VALUES
  ('f1010000-0000-0000-0000-000000000001', 'b0010000-0000-0000-0000-000000000001', 'e0010000-0000-0000-0000-000000000001', 'f0010000-0000-0000-0000-000000000001', 1, 'synthetic-order.pdf', 4, 'valid', 'current', 'a0010000-0000-0000-0000-000000000001', '2026-08-19T10:00:00Z', '2026-08-19T10:00:00Z', '2026-08-19T10:00:00Z'),
  ('f1010000-0000-0000-0000-000000000002', 'b0010000-0000-0000-0000-000000000001', 'e0010000-0000-0000-0000-000000000004', 'f0010000-0000-0000-0000-000000000002', 1, 'missing-hearing-notice.pdf', 4, 'valid', 'current', 'a0010000-0000-0000-0000-000000000001', '2026-09-01T10:00:00Z', '2026-09-01T10:00:00Z', '2026-09-01T10:00:00Z');

UPDATE public.documents
SET current_version_id = CASE id
      WHEN 'e0010000-0000-0000-0000-000000000001' THEN 'f1010000-0000-0000-0000-000000000001'::uuid
      WHEN 'e0010000-0000-0000-0000-000000000004' THEN 'f1010000-0000-0000-0000-000000000002'::uuid
    END,
    effective_filename = CASE id
      WHEN 'e0010000-0000-0000-0000-000000000001' THEN 'synthetic-order.pdf'
      WHEN 'e0010000-0000-0000-0000-000000000004' THEN 'missing-hearing-notice.pdf'
    END,
    effective_size_bytes = 4530
WHERE id IN (
  'e0010000-0000-0000-0000-000000000001',
  'e0010000-0000-0000-0000-000000000004'
);

INSERT INTO public.documents (id,org_id,matter_id,display_title,document_class,origin_kind,content_availability,status,created_by) VALUES
  ('e0010000-0000-0000-0000-000000000005','b0010000-0000-0000-0000-000000000001','d0020000-0000-4000-8000-000000000001','Final-window retention fixture','proceeding','manual_record','metadata_only','placed','a0010000-0000-0000-0000-000000000001'),
  ('e0010000-0000-0000-0000-000000000006','b0010000-0000-0000-0000-000000000001','d0020000-0000-4000-8000-000000000001','Blocked retention fixture','proceeding','manual_record','metadata_only','placed','a0010000-0000-0000-0000-000000000001');

SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000001',true);
SELECT public.trash_resource('document','e0010000-0000-0000-0000-000000000005','acceptance.final-window');
SELECT public.trash_resource('document','e0010000-0000-0000-0000-000000000006','acceptance.blocked');
SELECT set_config('request.jwt.claim.role','',true);
UPDATE public.trash_operations SET retention_mode='retention_period',retention_days=30,
  auto_purge_enabled_snapshot=true,purge_eligible_at=now()+interval '6 days 5 hours',auto_purge_at=now()+interval '6 days 5 hours'
WHERE root_resource_id='e0010000-0000-0000-0000-000000000005';
UPDATE public.trash_operations SET retention_mode='retention_period',retention_days=30,
  auto_purge_enabled_snapshot=true,purge_eligible_at=now(),auto_purge_at=now()
WHERE root_resource_id='e0010000-0000-0000-0000-000000000006';
INSERT INTO public.trash_purge_blockers(org_id,operation_id,resource_type,resource_id,blocker_kind,opaque_reference)
SELECT org_id,id,'document',root_resource_id,'active_export','b0090000-0000-0000-0000-000000000001'
FROM public.trash_operations WHERE root_resource_id='e0010000-0000-0000-0000-000000000006';

COMMIT;
