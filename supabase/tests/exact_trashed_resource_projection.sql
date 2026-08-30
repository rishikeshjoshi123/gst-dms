-- Run after migration 00086. Verifies exact Trash legal-content projection,
-- hierarchy binding, tenant isolation, readable dependent data, and the
-- separate exact versioned-PDF grant.
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000','86100000-0000-0000-0000-000000000001','authenticated','authenticated','projection-admin@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','86100000-0000-0000-0000-000000000002','authenticated','authenticated','projection-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','86100000-0000-0000-0000-000000000003','authenticated','authenticated','projection-other@test.invalid','x',now(),'{}','{}',now(),now());

INSERT INTO public.organisations(id,name,created_by) VALUES
  ('86000000-0000-0000-0000-000000000001','Projection fixture','86100000-0000-0000-0000-000000000001'),
  ('86000000-0000-0000-0000-000000000002','Projection other fixture','86100000-0000-0000-0000-000000000003');
UPDATE public.organisations AS organisation
SET owner_membership_id = membership.id
FROM public.organisation_memberships AS membership
WHERE membership.org_id = organisation.id
  AND membership.user_id = organisation.created_by;
INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_by)
VALUES ('86000000-0000-0000-0000-000000000001','86100000-0000-0000-0000-000000000002','viewer','active',1,'86100000-0000-0000-0000-000000000001');
UPDATE public.user_profiles SET display_name='Projection Admin' WHERE user_id='86100000-0000-0000-0000-000000000001';

INSERT INTO public.clients(id,org_id,name) VALUES
  ('86200000-0000-0000-0000-000000000001','86000000-0000-0000-0000-000000000001','Projection client');
INSERT INTO public.matters(id,org_id,client_id,title,financial_year) VALUES
  ('86300000-0000-0000-0000-000000000001','86000000-0000-0000-0000-000000000001','86200000-0000-0000-0000-000000000001','Projection matter','2026-27'),
  ('86300000-0000-0000-0000-000000000002','86000000-0000-0000-0000-000000000001','86200000-0000-0000-0000-000000000001','Wrong route matter','2025-26');
INSERT INTO public.documents(id,org_id,matter_id,storage_path,display_title,created_by) VALUES
  ('86400000-0000-0000-0000-000000000001','86000000-0000-0000-0000-000000000001','86300000-0000-0000-0000-000000000001','legacy/projection.pdf','Projection document','86100000-0000-0000-0000-000000000001'),
  ('86400000-0000-0000-0000-000000000002','86000000-0000-0000-0000-000000000001','86300000-0000-0000-0000-000000000001','legacy/second.pdf','Second document','86100000-0000-0000-0000-000000000001');
INSERT INTO public.wiki_sections(id,matter_id,section_key,title,content)
VALUES ('86500000-0000-0000-0000-000000000001','86300000-0000-0000-0000-000000000001','executive_summary','Executive summary','{"text":"Readable wiki"}');
INSERT INTO public.case_notes(id,matter_id,document_id,org_id,author_id,content)
VALUES
  ('86500000-0000-0000-0000-000000000002','86300000-0000-0000-0000-000000000001','86400000-0000-0000-0000-000000000001','86000000-0000-0000-0000-000000000001','86100000-0000-0000-0000-000000000001','Readable note'),
  ('86500000-0000-0000-0000-000000000003','86300000-0000-0000-0000-000000000001','86400000-0000-0000-0000-000000000002','86000000-0000-0000-0000-000000000001','86100000-0000-0000-0000-000000000001','Independently trashed child note');

INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,created_by,validated_at)
VALUES
  (
    '86600000-0000-0000-0000-000000000001','86000000-0000-0000-0000-000000000001','documents',
    'orgs/86000000-0000-0000-0000-000000000001/assets/86600000-0000-0000-0000-000000000001/original.pdf',
    repeat('8',64),128,'application/pdf','available','86100000-0000-0000-0000-000000000001',now()
  ),
  (
    '86600000-0000-0000-0000-000000000002','86000000-0000-0000-0000-000000000001','documents',
    'orgs/86000000-0000-0000-0000-000000000001/assets/86600000-0000-0000-0000-000000000002/original.pdf',
    repeat('9',64),64,'application/pdf','available','86100000-0000-0000-0000-000000000001',now()
  );
INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,created_by,validated_at,promoted_at)
VALUES
  ('86700000-0000-0000-0000-000000000001','86000000-0000-0000-0000-000000000001','86400000-0000-0000-0000-000000000001','86600000-0000-0000-0000-000000000001',1,'projection.pdf',1,'valid','current','86100000-0000-0000-0000-000000000001',now(),now()),
  ('86700000-0000-0000-0000-000000000002','86000000-0000-0000-0000-000000000001','86400000-0000-0000-0000-000000000002','86600000-0000-0000-0000-000000000002',1,'second.pdf',1,'valid','current','86100000-0000-0000-0000-000000000001',now(),now());
UPDATE public.documents SET current_version_id='86700000-0000-0000-0000-000000000001' WHERE id='86400000-0000-0000-0000-000000000001';
UPDATE public.documents SET current_version_id='86700000-0000-0000-0000-000000000002' WHERE id='86400000-0000-0000-0000-000000000002';
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','86100000-0000-0000-0000-000000000001',true);
SELECT public.trash_resource('document','86400000-0000-0000-0000-000000000002','fixture.projection.independent_document');
SELECT public.trash_resource('matter','86300000-0000-0000-0000-000000000001','fixture.projection.matter');

DO $fixture$
DECLARE projection record; grant_row record;
BEGIN
  SELECT * INTO projection
  FROM public.get_exact_trashed_resource_projection('matter','86300000-0000-0000-0000-000000000001',NULL);
  IF projection.resource_id IS NULL OR projection.resource_record->>'title' <> 'Projection matter' THEN
    RAISE EXCEPTION 'exact trashed matter body was not projected';
  END IF;
  IF jsonb_array_length(projection.related_documents) <> 2
     OR jsonb_array_length(projection.related_wiki_sections) <> 1
     OR jsonb_array_length(projection.related_notes) <> 2 THEN
    RAISE EXCEPTION 'trashed matter dependent data was incomplete';
  END IF;
  IF projection.resource_record ?| ARRAY['storage_path','raw_metadata','content_hash','embedding','search_vector']
     OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(projection.related_documents) AS document
       WHERE document ?| ARRAY['storage_path','raw_metadata','content_hash','embedding','search_vector']
     ) THEN RAISE EXCEPTION 'exact projection exposed private document fields'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(projection.related_notes) AS note
    WHERE note->>'document_id'='86400000-0000-0000-0000-000000000001'
      AND note->'documents'->>'display_title'='Projection document'
      AND NOT (note->'documents' ? 'storage_path')
  ) THEN RAISE EXCEPTION 'safe note document identity was not projected'; END IF;
  IF projection.root_resource_name <> 'Projection matter'
     OR projection.trashed_by_name <> 'Projection Admin'
     OR projection.cause <> 'direct' THEN
    RAISE EXCEPTION 'Trash strip context was incomplete';
  END IF;

  SELECT * INTO projection FROM public.get_exact_trashed_resource_projection(
    'document','86400000-0000-0000-0000-000000000002','86300000-0000-0000-0000-000000000001'
  );
  IF projection.cause <> 'direct' OR projection.root_resource_type <> 'document'::public.trash_resource_type
     OR projection.root_resource_id <> '86400000-0000-0000-0000-000000000002'::uuid THEN
    RAISE EXCEPTION 'independently trashed child lost its own Trash operation';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.get_exact_trashed_resource_projection(
      'document','86400000-0000-0000-0000-000000000001','86300000-0000-0000-0000-000000000002'
    )
  ) THEN RAISE EXCEPTION 'wrong document/matter route disclosed Trash data'; END IF;

  SELECT * INTO grant_row FROM public.get_trashed_document_version_read_grant(
    '86400000-0000-0000-0000-000000000001','86300000-0000-0000-0000-000000000001','86700000-0000-0000-0000-000000000001'
  );
  IF grant_row.code <> 'ok' OR grant_row.object_key NOT LIKE 'orgs/%/original.pdf' THEN
    RAISE EXCEPTION 'authorised exact Trash PDF grant failed';
  END IF;
  IF EXISTS (SELECT 1 FROM public.get_trashed_document_version_read_grant(
    '86400000-0000-0000-0000-000000000001','86300000-0000-0000-0000-000000000002','86700000-0000-0000-0000-000000000001'
  )) THEN RAISE EXCEPTION 'wrong-matter Trash PDF grant disclosed a locator'; END IF;
  IF EXISTS (SELECT 1 FROM public.get_trashed_document_version_read_grant(
    '86400000-0000-0000-0000-000000000001','86300000-0000-0000-0000-000000000001','86700000-0000-0000-0000-000000000002'
  )) THEN RAISE EXCEPTION 'version from another document disclosed a Trash PDF locator'; END IF;
END $fixture$;

-- A child whose independent lifecycle has begun purging cannot contribute its
-- document body, note, metadata, or links to a readable ancestor projection.
RESET ROLE;
UPDATE public.documents SET record_state='purging' WHERE id='86400000-0000-0000-0000-000000000002';
UPDATE public.resource_trash_memberships SET state='purging'
WHERE id=(SELECT active_trash_membership_id FROM public.documents WHERE id='86400000-0000-0000-0000-000000000002');
UPDATE public.trash_operations SET state='purging',purge_started_at=now()
WHERE id=(SELECT operation_id FROM public.resource_trash_memberships WHERE id=(SELECT active_trash_membership_id FROM public.documents WHERE id='86400000-0000-0000-0000-000000000002'));
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','86100000-0000-0000-0000-000000000001',true);
DO $fixture$
DECLARE projection record;
BEGIN
  SELECT * INTO projection FROM public.get_exact_trashed_resource_projection('matter','86300000-0000-0000-0000-000000000001',NULL);
  IF jsonb_array_length(projection.related_documents) <> 1 OR jsonb_array_length(projection.related_notes) <> 1 THEN
    RAISE EXCEPTION 'purging independent child leaked through readable ancestor projection';
  END IF;
  IF EXISTS (SELECT 1 FROM public.get_exact_trashed_resource_projection(
    'document','86400000-0000-0000-0000-000000000002','86300000-0000-0000-0000-000000000001'
  )) THEN RAISE EXCEPTION 'purging child remained exactly readable'; END IF;
END $fixture$;

SELECT set_config('request.jwt.claim.sub','86100000-0000-0000-0000-000000000002',true);
DO $fixture$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.get_exact_trashed_resource_projection('document','86400000-0000-0000-0000-000000000001','86300000-0000-0000-0000-000000000001')) THEN
    RAISE EXCEPTION 'authorised Viewer could not read exact Trash document';
  END IF;
END $fixture$;

-- Scheduled roots stay readable and link back to the workspace; malformed,
-- inactive, purging, and purged lineage never discloses exact content.
RESET ROLE;
UPDATE public.trash_operations
SET state='purge_scheduled',purge_scheduled_at=now()
WHERE id=(SELECT operation_id FROM public.resource_trash_memberships WHERE id=(SELECT active_trash_membership_id FROM public.matters WHERE id='86300000-0000-0000-0000-000000000001'));
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','86100000-0000-0000-0000-000000000001',true);
DO $fixture$
DECLARE projection record; operation uuid;
BEGIN
  SELECT * INTO projection FROM public.get_exact_trashed_resource_projection('matter','86300000-0000-0000-0000-000000000001',NULL);
  operation := projection.operation_id;
  IF projection.operation_state <> 'purge_scheduled'::public.trash_operation_state THEN
    RAISE EXCEPTION 'purge-scheduled exact route was not readable';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.get_trash_workspace('86000000-0000-0000-0000-000000000001',NULL,NULL,operation,50) AS workspace
    WHERE workspace.row_kind='operation' AND workspace.operation_id=operation
  ) THEN RAISE EXCEPTION 'purge-scheduled Back to Trash destination was missing'; END IF;
END $fixture$;

RESET ROLE;
UPDATE public.resource_trash_memberships SET state='restoring'
WHERE id=(SELECT active_trash_membership_id FROM public.matters WHERE id='86300000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','86100000-0000-0000-0000-000000000001',true);
DO $fixture$ BEGIN
  IF EXISTS (SELECT 1 FROM public.get_exact_trashed_resource_projection('matter','86300000-0000-0000-0000-000000000001',NULL)) THEN
    RAISE EXCEPTION 'inactive membership remained exactly readable';
  END IF;
END $fixture$;

RESET ROLE;
UPDATE public.resource_trash_memberships SET state='active'
WHERE id=(SELECT active_trash_membership_id FROM public.matters WHERE id='86300000-0000-0000-0000-000000000001');
UPDATE public.matters SET active_trash_membership_id=(
  SELECT active_trash_membership_id FROM public.documents WHERE id='86400000-0000-0000-0000-000000000001'
) WHERE id='86300000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','86100000-0000-0000-0000-000000000001',true);
DO $fixture$ BEGIN
  IF EXISTS (SELECT 1 FROM public.get_exact_trashed_resource_projection('matter','86300000-0000-0000-0000-000000000001',NULL)) THEN
    RAISE EXCEPTION 'malformed active membership pointer disclosed content';
  END IF;
END $fixture$;

RESET ROLE;
UPDATE public.matters SET active_trash_membership_id=(
  SELECT id FROM public.resource_trash_memberships
  WHERE resource_type='matter' AND resource_id='86300000-0000-0000-0000-000000000001' AND state='active'
) WHERE id='86300000-0000-0000-0000-000000000001';
UPDATE public.trash_operations
SET root_resource_id='86300000-0000-0000-0000-000000000002',root_matter_id='86300000-0000-0000-0000-000000000002'
WHERE id=(SELECT operation_id FROM public.resource_trash_memberships WHERE id=(SELECT active_trash_membership_id FROM public.matters WHERE id='86300000-0000-0000-0000-000000000001'));
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','86100000-0000-0000-0000-000000000001',true);
DO $fixture$ BEGIN
  IF EXISTS (SELECT 1 FROM public.get_exact_trashed_resource_projection('matter','86300000-0000-0000-0000-000000000001',NULL)) THEN
    RAISE EXCEPTION 'malformed operation root lineage disclosed content';
  END IF;
END $fixture$;

RESET ROLE;
UPDATE public.trash_operations
SET root_resource_id='86300000-0000-0000-0000-000000000001',root_matter_id='86300000-0000-0000-0000-000000000001',
    state='purging',purge_scheduled_at=NULL,purge_started_at=now()
WHERE root_matter_id='86300000-0000-0000-0000-000000000002';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','86100000-0000-0000-0000-000000000001',true);
DO $fixture$ BEGIN
  IF EXISTS (SELECT 1 FROM public.get_exact_trashed_resource_projection('matter','86300000-0000-0000-0000-000000000001',NULL)) THEN
    RAISE EXCEPTION 'purging operation remained exactly readable';
  END IF;
END $fixture$;

RESET ROLE;
UPDATE public.trash_operations SET state='purged',purged_at=now()
WHERE root_matter_id='86300000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','86100000-0000-0000-0000-000000000001',true);
DO $fixture$ BEGIN
  IF EXISTS (SELECT 1 FROM public.get_exact_trashed_resource_projection('matter','86300000-0000-0000-0000-000000000001',NULL)) THEN
    RAISE EXCEPTION 'purged operation remained exactly readable';
  END IF;
END $fixture$;

SELECT set_config('request.jwt.claim.sub','86100000-0000-0000-0000-000000000003',true);
DO $fixture$
BEGIN
  IF EXISTS (SELECT 1 FROM public.get_exact_trashed_resource_projection('matter','86300000-0000-0000-0000-000000000001',NULL)) THEN
    RAISE EXCEPTION 'cross-tenant Trash content was disclosed';
  END IF;
  IF EXISTS (SELECT 1 FROM public.get_trashed_document_version_read_grant(
    '86400000-0000-0000-0000-000000000001','86300000-0000-0000-0000-000000000001','86700000-0000-0000-0000-000000000001'
  )) THEN RAISE EXCEPTION 'cross-tenant Trash PDF locator was disclosed'; END IF;
END $fixture$;

SET LOCAL ROLE service_role;
DO $fixture$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.get_exact_trashed_resource_projection('matter','86300000-0000-0000-0000-000000000001',NULL);
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'service role could execute exact Trash projection'; END IF;
END $fixture$;

ROLLBACK;
