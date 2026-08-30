-- Persistent disposable setup for the Restore-vs-version-writer SHA race.
BEGIN;
INSERT INTO auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '89100000-0000-0000-0000-000000000001','authenticated','authenticated',
  'restore-writer-race@test.invalid','x',now(),'{}','{}',now(),now()
);
INSERT INTO public.organisations(id,name,created_by) VALUES (
  '89000000-0000-0000-0000-000000000001','Restore writer race',
  '89100000-0000-0000-0000-000000000001'
);
UPDATE public.organisations organisation SET owner_membership_id=membership.id
FROM public.organisation_memberships membership
WHERE organisation.id='89000000-0000-0000-0000-000000000001'
  AND membership.org_id=organisation.id
  AND membership.user_id='89100000-0000-0000-0000-000000000001'
  AND membership.state='active';
INSERT INTO public.clients(id,org_id,name) VALUES (
  '89200000-0000-0000-0000-000000000001',
  '89000000-0000-0000-0000-000000000001','Restore writer client'
);
INSERT INTO public.matters(id,org_id,client_id,title) VALUES (
  '89300000-0000-0000-0000-000000000001',
  '89000000-0000-0000-0000-000000000001',
  '89200000-0000-0000-0000-000000000001','Restore writer matter'
);
INSERT INTO public.file_assets(
  id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,
  availability,validated_at,validated_page_count,created_by
) VALUES (
  '89400000-0000-0000-0000-000000000001',
  '89000000-0000-0000-0000-000000000001','documents',
  'orgs/89000000-0000-0000-0000-000000000001/assets/89400000-0000-0000-0000-000000000001/original.pdf',
  repeat('f',64),10,'application/pdf','available',now(),1,
  '89100000-0000-0000-0000-000000000001'
);
INSERT INTO public.documents(
  id,org_id,matter_id,display_title,origin_kind,record_state,
  content_availability,status,storage_path,created_by
) VALUES (
  '89800000-0000-0000-0000-000000000001',
  '89000000-0000-0000-0000-000000000001',
  '89300000-0000-0000-0000-000000000001','Restore source',
  'upload','active','source_attached','placed',NULL,
  '89100000-0000-0000-0000-000000000001'
);
INSERT INTO public.document_versions(
  id,org_id,document_id,asset_id,version_number,original_filename,
  validation_state,state,validated_at,promoted_at
) VALUES (
  '89900000-0000-0000-0000-000000000001',
  '89000000-0000-0000-0000-000000000001',
  '89800000-0000-0000-0000-000000000001',
  '89400000-0000-0000-0000-000000000001',1,'restore-source.pdf',
  'valid','current',now(),now()
);
UPDATE public.documents SET current_version_id='89900000-0000-0000-0000-000000000001'
WHERE id='89800000-0000-0000-0000-000000000001';
INSERT INTO public.upload_sessions(
  id,org_id,asset_id,declared_filename,declared_mime_type,
  declared_byte_size,state,created_by,uploaded_at,finalized_at
) VALUES (
  '89700000-0000-0000-0000-000000000001',
  '89000000-0000-0000-0000-000000000001',
  '89400000-0000-0000-0000-000000000001','writer.pdf',
  'application/pdf',10,'finalized','89100000-0000-0000-0000-000000000001',now(),now()
);
INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,state,uploaded_by)
VALUES (
  '89500000-0000-0000-0000-000000000001',
  '89000000-0000-0000-0000-000000000001',
  '89400000-0000-0000-0000-000000000001',
  '89700000-0000-0000-0000-000000000001','ready',
  '89100000-0000-0000-0000-000000000001'
);
SET LOCAL "request.jwt.claim.sub"='89100000-0000-0000-0000-000000000001';
SET LOCAL "request.jwt.claim.role"='authenticated';
SELECT operation_id FROM public.trash_resource(
  'document','89800000-0000-0000-0000-000000000001','fixture.restore-writer-race'
);
COMMIT;
