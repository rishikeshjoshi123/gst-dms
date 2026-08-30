-- Run after a clean reset through migration 00083 against a disposable local database.
-- Covers active/history priority, live Intake, direct and inherited Trash,
-- identifier non-disclosure, assignment fencing, replay, and tenant denial.
BEGIN;

DO $fixture$
DECLARE
  org_a uuid := '81000000-0000-0000-0000-000000000001';
  org_b uuid := '81000000-0000-0000-0000-000000000002';
  owner uuid := '81100000-0000-0000-0000-000000000001';
  other uuid := '81100000-0000-0000-0000-000000000002';
  client_a uuid := '81200000-0000-0000-0000-000000000001';
  matter_a uuid := '81300000-0000-0000-0000-000000000001';
  matter_inherited uuid := '81300000-0000-0000-0000-000000000002';
  doc_active uuid := '81400000-0000-0000-0000-000000000001';
  doc_direct uuid := '81400000-0000-0000-0000-000000000002';
  doc_inherited uuid := '81400000-0000-0000-0000-000000000003';
  doc_assignment uuid := '81400000-0000-0000-0000-000000000004';
  asset_active uuid := '81500000-0000-0000-0000-000000000001';
  asset_current uuid := '81500000-0000-0000-0000-000000000002';
  asset_direct uuid := '81500000-0000-0000-0000-000000000003';
  asset_inherited uuid := '81500000-0000-0000-0000-000000000004';
  asset_live uuid := '81500000-0000-0000-0000-000000000005';
  asset_assignment uuid := '81500000-0000-0000-0000-000000000006';
  subject_active uuid := '81500000-0000-0000-0000-000000000011';
  subject_direct uuid := '81500000-0000-0000-0000-000000000012';
  subject_inherited uuid := '81500000-0000-0000-0000-000000000013';
  subject_live uuid := '81500000-0000-0000-0000-000000000014';
  session_active uuid := '81600000-0000-0000-0000-000000000001';
  session_direct uuid := '81600000-0000-0000-0000-000000000002';
  session_inherited uuid := '81600000-0000-0000-0000-000000000003';
  session_live uuid := '81600000-0000-0000-0000-000000000004';
  session_assignment uuid := '81600000-0000-0000-0000-000000000005';
  intake_active uuid := '81700000-0000-0000-0000-000000000001';
  intake_direct uuid := '81700000-0000-0000-0000-000000000002';
  intake_inherited uuid := '81700000-0000-0000-0000-000000000003';
  intake_live_subject uuid := '81700000-0000-0000-0000-000000000004';
  intake_live_target uuid := '81700000-0000-0000-0000-000000000005';
  intake_assignment uuid := '81700000-0000-0000-0000-000000000006';
  version_current uuid := '81800000-0000-0000-0000-000000000001';
  version_history uuid := '81800000-0000-0000-0000-000000000002';
  version_direct uuid := '81800000-0000-0000-0000-000000000003';
  version_inherited uuid := '81800000-0000-0000-0000-000000000004';
  version_assignment uuid := '81800000-0000-0000-0000-000000000005';
  result record;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000',owner,'authenticated','authenticated','duplicate-owner@test.invalid','x',now(),'{}','{}',now(),now()),
         ('00000000-0000-0000-0000-000000000000',other,'authenticated','authenticated','duplicate-other@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES(org_a,'Duplicate A',owner),(org_b,'Duplicate B',other);
  INSERT INTO public.clients(id,org_id,name) VALUES(client_a,org_a,'Client');
  INSERT INTO public.matters(id,org_id,client_id,title,financial_year)
  VALUES (matter_a,org_a,client_a,'Active','2025-26'),
         (matter_inherited,org_a,client_a,'Inherited','2026-27');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
  SELECT id,org_a,'documents','orgs/'||org_a||'/assets/'||id||'/original.pdf',hash,10,'application/pdf','available',now(),1,owner
  FROM unnest(ARRAY[asset_active,asset_current,asset_direct,asset_inherited,asset_live,asset_assignment,subject_active,subject_direct,subject_inherited,subject_live])
       WITH ORDINALITY AS source(id,n)
  CROSS JOIN LATERAL (SELECT lpad(to_hex(source.n),64,'0') AS hash) AS value;
  INSERT INTO public.documents(id,org_id,matter_id,display_title,origin_kind,content_availability,status,created_by)
  VALUES(doc_active,org_a,matter_a,'Active','upload','source_attached','placed',owner),
        (doc_direct,org_a,matter_a,'Direct trash','upload','source_attached','placed',owner),
        (doc_inherited,org_a,matter_inherited,'Inherited trash','upload','source_attached','placed',owner),
        (doc_assignment,org_a,matter_a,'Existing assignment','upload','source_attached','placed',owner);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,validation_state,state,validated_at,promoted_at,superseded_at)
  VALUES(version_history,org_a,doc_active,asset_active,1,'history.pdf','valid','superseded',now(),NULL,now()),
        (version_current,org_a,doc_active,asset_current,2,'current.pdf','valid','current',now(),now(),NULL),
        (version_direct,org_a,doc_direct,asset_direct,1,'direct.pdf','valid','current',now(),now(),NULL),
        (version_inherited,org_a,doc_inherited,asset_inherited,1,'inherited.pdf','valid','current',now(),now(),NULL),
        (version_assignment,org_a,doc_assignment,asset_assignment,1,'assignment.pdf','valid','current',now(),now(),NULL);
  UPDATE public.documents SET current_version_id=CASE id
    WHEN doc_active THEN version_current WHEN doc_direct THEN version_direct
    WHEN doc_inherited THEN version_inherited WHEN doc_assignment THEN version_assignment END
  WHERE id IN (doc_active,doc_direct,doc_inherited,doc_assignment);
  INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,uploaded_at,finalized_at)
  VALUES(session_active,org_a,subject_active,'active.pdf','application/pdf',10,'finalized',owner,now(),now()),
        (session_direct,org_a,subject_direct,'direct.pdf','application/pdf',10,'finalized',owner,now(),now()),
        (session_inherited,org_a,subject_inherited,'inherited.pdf','application/pdf',10,'finalized',owner,now(),now()),
        (session_live,org_a,subject_live,'live.pdf','application/pdf',10,'finalized',owner,now(),now()),
        (session_assignment,org_a,asset_assignment,'assignment.pdf','application/pdf',10,'finalized',owner,now(),now());
  INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,state,uploaded_by)
  VALUES(intake_active,org_a,subject_active,session_active,'duplicate',owner),
        (intake_direct,org_a,subject_direct,session_direct,'duplicate',owner),
        (intake_inherited,org_a,subject_inherited,session_inherited,'duplicate',owner),
        (intake_live_subject,org_a,subject_live,session_live,'duplicate',owner),
        (intake_live_target,org_a,asset_live,NULL,'ready',owner),
        (intake_assignment,org_a,asset_assignment,session_assignment,'ready',owner);
  INSERT INTO public.document_upload_command_receipts(org_id,upload_session_id,command,idempotency_key,code,duplicate_asset_id)
  VALUES(org_a,session_active,'complete','81900000-0000-0000-0000-000000000001','duplicate',asset_active),
        (org_a,session_direct,'complete','81900000-0000-0000-0000-000000000002','duplicate',asset_direct),
        (org_a,session_inherited,'complete','81900000-0000-0000-0000-000000000003','duplicate',asset_inherited),
        (org_a,session_live,'complete','81900000-0000-0000-0000-000000000004','duplicate',asset_live);

  PERFORM set_config('request.jwt.claim.sub',owner::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  SELECT * INTO result FROM public.trash_resource('document',doc_direct,'duplicate.direct');
  IF result.code <> 'trashed' THEN RAISE EXCEPTION 'direct trash setup failed'; END IF;
  SELECT * INTO result FROM public.trash_resource('matter',matter_inherited,'duplicate.inherited');
  IF result.code <> 'trashed' THEN RAISE EXCEPTION 'inherited trash setup failed'; END IF;

  SELECT * INTO result FROM public.get_intake_duplicate_resolution(intake_active);
  IF result.code <> 'ok' OR result.document_id <> doc_active OR result.matter_id <> matter_a OR result.intake_id IS NOT NULL THEN
    RAISE EXCEPTION 'historical active duplicate priority failed';
  END IF;
  SELECT * INTO result FROM public.get_intake_duplicate_resolution(intake_live_subject);
  IF result.code <> 'intake' OR result.intake_id <> intake_live_target OR result.document_id IS NOT NULL OR result.matter_id IS NOT NULL THEN
    RAISE EXCEPTION 'live Intake duplicate resolution failed';
  END IF;
  SELECT * INTO result FROM public.get_intake_duplicate_resolution(intake_direct);
  IF result.code <> 'in_trash' OR result.document_id IS NOT NULL OR result.matter_id IS NOT NULL OR result.intake_id IS NOT NULL THEN
    RAISE EXCEPTION 'direct Trash duplicate disclosed an identifier';
  END IF;
  SELECT * INTO result FROM public.get_intake_duplicate_resolution(intake_inherited);
  IF result.code <> 'in_trash' OR result.document_id IS NOT NULL OR result.matter_id IS NOT NULL OR result.intake_id IS NOT NULL THEN
    RAISE EXCEPTION 'inherited Trash duplicate disclosed an identifier';
  END IF;
  SELECT * INTO result FROM public.assign_intake_to_new_document(intake_assignment,matter_a,'Blocked','81100000-0000-0000-0000-000000000001','81900000-0000-0000-0000-000000000005');
  IF result.code <> 'duplicate_reference' OR result.document_id IS NOT NULL OR result.document_version_id IS NOT NULL THEN
    RAISE EXCEPTION 'assignment duplicate fence failed';
  END IF;
  SELECT * INTO result FROM public.assign_intake_to_new_document(intake_assignment,matter_a,'Blocked','81100000-0000-0000-0000-000000000001','81900000-0000-0000-0000-000000000005');
  IF result.code <> 'duplicate_reference' THEN RAISE EXCEPTION 'assignment duplicate replay failed'; END IF;
  IF (SELECT count(*) FROM public.documents WHERE org_id=org_a) <> 4 THEN RAISE EXCEPTION 'duplicate assignment created a document'; END IF;
END $fixture$;

-- 00082 closes the remaining writer paths.  The exact-PDF fence applies to
-- attach, replace, and service-only intended assignment as well as creating a
-- new record; a version already owned by this same logical document remains
-- valid audited history.
DO $writer_paths$
DECLARE
  org_a uuid := '81000000-0000-0000-0000-000000000001';
  owner uuid := '81100000-0000-0000-0000-000000000001';
  matter_a uuid := '81300000-0000-0000-0000-000000000001';
  doc_active uuid := '81400000-0000-0000-0000-000000000001';
  doc_assignment uuid := '81400000-0000-0000-0000-000000000004';
  asset_active uuid := '81500000-0000-0000-0000-000000000001';
  asset_assignment uuid := '81500000-0000-0000-0000-000000000006';
  metadata_doc uuid := '81400000-0000-0000-0000-000000000005';
  session_attach uuid := '81600000-0000-0000-0000-000000000006';
  session_replace uuid := '81600000-0000-0000-0000-000000000007';
  session_auto uuid := '81600000-0000-0000-0000-000000000008';
  session_history uuid := '81600000-0000-0000-0000-000000000009';
  intake_attach uuid := '81700000-0000-0000-0000-000000000007';
  intake_replace uuid := '81700000-0000-0000-0000-000000000008';
  intake_auto uuid := '81700000-0000-0000-0000-000000000009';
  intake_history uuid := '81700000-0000-0000-0000-000000000010';
  auto_event uuid := '81900000-0000-0000-0000-000000000010';
  revision bigint;
  result record;
BEGIN
  INSERT INTO public.documents(id,org_id,matter_id,display_title,origin_kind,record_state,content_availability,status,storage_path,created_by)
  VALUES(metadata_doc,org_a,matter_a,'Metadata target','manual_record','active','metadata_only','placed',NULL,owner);
  INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,uploaded_at,finalized_at)
  VALUES(session_attach,org_a,asset_assignment,'attach.pdf','application/pdf',10,'finalized',owner,now(),now()),
        (session_replace,org_a,asset_assignment,'replace.pdf','application/pdf',10,'finalized',owner,now(),now()),
        (session_auto,org_a,asset_assignment,'auto.pdf','application/pdf',10,'finalized',owner,now(),now()),
        (session_history,org_a,asset_active,'history-copy.pdf','application/pdf',10,'finalized',owner,now(),now());
  INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,intended_matter_id,state,uploaded_by)
  VALUES(intake_attach,org_a,asset_assignment,session_attach,NULL,'ready',owner),
        (intake_replace,org_a,asset_assignment,session_replace,NULL,'ready',owner),
        (intake_auto,org_a,asset_assignment,session_auto,matter_a,'ready',owner),
        (intake_history,org_a,asset_active,session_history,NULL,'ready',owner);

  SELECT lifecycle_revision INTO revision FROM public.documents WHERE id=metadata_doc;
  SELECT * INTO result FROM public.attach_intake_to_document(metadata_doc,intake_attach,revision,owner,'81900000-0000-0000-0000-000000000011');
  IF result.code <> 'duplicate_reference' OR result.document_version_id IS NOT NULL THEN RAISE EXCEPTION 'attach duplicate fence failed'; END IF;
  SELECT * INTO result FROM public.attach_intake_to_document(metadata_doc,intake_attach,revision,owner,'81900000-0000-0000-0000-000000000011');
  IF result.code <> 'duplicate_reference' THEN RAISE EXCEPTION 'attach duplicate replay failed'; END IF;

  SELECT lifecycle_revision INTO revision FROM public.documents WHERE id=doc_active;
  SELECT * INTO result FROM public.replace_document_version(doc_active,intake_replace,revision,'cross-document duplicate',owner,'81900000-0000-0000-0000-000000000012');
  IF result.code <> 'duplicate_reference' OR result.document_version_id IS NOT NULL THEN RAISE EXCEPTION 'replace duplicate fence failed'; END IF;

  INSERT INTO public.outbox_events(id,org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key)
  VALUES(auto_event,org_a,'document',intake_auto,'document.intake_validated.v1',jsonb_build_object('intake_id',intake_auto::text,'asset_id',asset_assignment::text,'result_code','ok'),'duplicate-auto-fence');
  SET LOCAL ROLE service_role;
  SELECT * INTO result FROM public.auto_assign_intended_matter_intake(intake_auto,auto_event);
  RESET ROLE;
  IF result.code <> 'duplicate_reference' OR result.document_id IS NOT NULL THEN RAISE EXCEPTION 'auto assignment duplicate fence failed'; END IF;

  SELECT lifecycle_revision INTO revision FROM public.documents WHERE id=doc_active;
  SELECT * INTO result FROM public.replace_document_version(doc_active,intake_history,revision,'audited same-document history',owner,'81900000-0000-0000-0000-000000000013');
  IF result.code <> 'same_asset' OR result.document_version_id IS NOT NULL THEN RAISE EXCEPTION 'same-document history replay was not handled safely'; END IF;
  IF EXISTS (SELECT 1 FROM public.document_versions WHERE asset_id=asset_active AND document_id<>doc_active AND validation_state='valid' AND state IN ('current','superseded')) THEN RAISE EXCEPTION 'writer fence created a cross-document duplicate'; END IF;
  IF (SELECT count(*) FROM public.document_versions WHERE asset_id=asset_active AND document_id=doc_active AND validation_state='valid' AND state IN ('current','superseded')) <> 1 THEN RAISE EXCEPTION 'same-document history was not retained'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.document_versions WHERE asset_id=asset_assignment AND document_id=doc_assignment AND validation_state='valid' AND state IN ('current','superseded')) THEN RAISE EXCEPTION 'writer fixture lost the source reference'; END IF;
END $writer_paths$;

-- 00083 serializes same actor/key replays before any resource fence and binds
-- each attach/replace receipt to its complete document/Intake subject.
DO $idempotency_replays$
DECLARE
  org_a uuid := '81000000-0000-0000-0000-000000000001';
  owner uuid := '81100000-0000-0000-0000-000000000001';
  matter_a uuid := '81300000-0000-0000-0000-000000000001';
  attach_document uuid := '81400000-0000-0000-0000-000000000006';
  attach_other_document uuid := '81400000-0000-0000-0000-000000000007';
  replace_document uuid := '81400000-0000-0000-0000-000000000008';
  replace_other_document uuid := '81400000-0000-0000-0000-000000000009';
  attach_asset uuid := '81500000-0000-0000-0000-000000000020';
  attach_other_asset uuid := '81500000-0000-0000-0000-000000000021';
  replace_old_asset uuid := '81500000-0000-0000-0000-000000000022';
  replace_other_old_asset uuid := '81500000-0000-0000-0000-000000000023';
  replace_asset uuid := '81500000-0000-0000-0000-000000000024';
  replace_other_asset uuid := '81500000-0000-0000-0000-000000000025';
  attach_session uuid := '81600000-0000-0000-0000-000000000010';
  attach_other_session uuid := '81600000-0000-0000-0000-000000000011';
  replace_session uuid := '81600000-0000-0000-0000-000000000012';
  replace_other_session uuid := '81600000-0000-0000-0000-000000000013';
  attach_intake uuid := '81700000-0000-0000-0000-000000000011';
  attach_other_intake uuid := '81700000-0000-0000-0000-000000000012';
  replace_intake uuid := '81700000-0000-0000-0000-000000000013';
  replace_other_intake uuid := '81700000-0000-0000-0000-000000000014';
  replace_old_version uuid := '81800000-0000-0000-0000-000000000006';
  replace_other_old_version uuid := '81800000-0000-0000-0000-000000000007';
  attach_revision bigint;
  replace_revision bigint;
  replace_other_revision bigint;
  first_result record;
  result record;
BEGIN
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
  VALUES
    (attach_asset,org_a,'documents','orgs/'||org_a||'/assets/'||attach_asset||'/original.pdf',repeat('b',64),10,'application/pdf','available',now(),1,owner),
    (attach_other_asset,org_a,'documents','orgs/'||org_a||'/assets/'||attach_other_asset||'/original.pdf',repeat('c',64),10,'application/pdf','available',now(),1,owner),
    (replace_old_asset,org_a,'documents','orgs/'||org_a||'/assets/'||replace_old_asset||'/original.pdf',repeat('d',64),10,'application/pdf','available',now(),1,owner),
    (replace_other_old_asset,org_a,'documents','orgs/'||org_a||'/assets/'||replace_other_old_asset||'/original.pdf',repeat('e',64),10,'application/pdf','available',now(),1,owner),
    (replace_asset,org_a,'documents','orgs/'||org_a||'/assets/'||replace_asset||'/original.pdf',repeat('f',64),10,'application/pdf','available',now(),1,owner),
    (replace_other_asset,org_a,'documents','orgs/'||org_a||'/assets/'||replace_other_asset||'/original.pdf',repeat('1',64),10,'application/pdf','available',now(),1,owner);
  INSERT INTO public.documents(id,org_id,matter_id,display_title,origin_kind,record_state,content_availability,status,storage_path,created_by)
  VALUES
    (attach_document,org_a,matter_a,'Replay attach','manual_record','active','metadata_only','placed',NULL,owner),
    (attach_other_document,org_a,matter_a,'Replay attach other','manual_record','active','metadata_only','placed',NULL,owner),
    (replace_document,org_a,matter_a,'Replay replace','upload','active','source_attached','placed',NULL,owner),
    (replace_other_document,org_a,matter_a,'Replay replace other','upload','active','source_attached','placed',NULL,owner);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,validation_state,state,validated_at,promoted_at)
  VALUES
    (replace_old_version,org_a,replace_document,replace_old_asset,1,'replace-old.pdf','valid','current',now(),now()),
    (replace_other_old_version,org_a,replace_other_document,replace_other_old_asset,1,'replace-other-old.pdf','valid','current',now(),now());
  UPDATE public.documents SET current_version_id=CASE id
    WHEN replace_document THEN replace_old_version
    WHEN replace_other_document THEN replace_other_old_version
  END WHERE id IN (replace_document,replace_other_document);
  INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,uploaded_at,finalized_at)
  VALUES
    (attach_session,org_a,attach_asset,'replay-attach.pdf','application/pdf',10,'finalized',owner,now(),now()),
    (attach_other_session,org_a,attach_other_asset,'replay-attach-other.pdf','application/pdf',10,'finalized',owner,now(),now()),
    (replace_session,org_a,replace_asset,'replay-replace.pdf','application/pdf',10,'finalized',owner,now(),now()),
    (replace_other_session,org_a,replace_other_asset,'replay-replace-other.pdf','application/pdf',10,'finalized',owner,now(),now());
  INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,state,uploaded_by)
  VALUES
    (attach_intake,org_a,attach_asset,attach_session,'ready',owner),
    (attach_other_intake,org_a,attach_other_asset,attach_other_session,'ready',owner),
    (replace_intake,org_a,replace_asset,replace_session,'ready',owner),
    (replace_other_intake,org_a,replace_other_asset,replace_other_session,'ready',owner);

  SELECT lifecycle_revision INTO attach_revision FROM public.documents WHERE id=attach_document;
  SELECT * INTO first_result FROM public.attach_intake_to_document(attach_document,attach_intake,attach_revision,owner,'81900000-0000-0000-0000-000000000014');
  IF first_result.code <> 'ok' OR first_result.document_version_id IS NULL THEN RAISE EXCEPTION 'attach ordinary success failed'; END IF;
  SELECT * INTO result FROM public.attach_intake_to_document(attach_document,attach_intake,attach_revision,owner,'81900000-0000-0000-0000-000000000014');
  IF result.code <> 'ok' OR result.document_version_id IS DISTINCT FROM first_result.document_version_id OR result.lifecycle_revision IS DISTINCT FROM first_result.lifecycle_revision THEN RAISE EXCEPTION 'attach ordinary retry did not replay its original result'; END IF;
  SELECT * INTO result FROM public.attach_intake_to_document(attach_other_document,attach_other_intake,0,owner,'81900000-0000-0000-0000-000000000014');
  IF result.code <> 'idempotency_subject_mismatch' OR result.document_version_id IS NOT NULL OR result.lifecycle_revision IS NOT NULL THEN RAISE EXCEPTION 'attach cross-subject key reuse did not fail closed'; END IF;
  IF (SELECT current_version_id IS NULL AND content_availability='metadata_only' FROM public.documents WHERE id=attach_other_document) IS NOT TRUE
     OR (SELECT state='ready' FROM public.intake_items WHERE id=attach_other_intake) IS NOT TRUE THEN
    RAISE EXCEPTION 'attach cross-subject key reuse mutated its new subject';
  END IF;

  SELECT lifecycle_revision INTO replace_revision FROM public.documents WHERE id=replace_document;
  SELECT * INTO first_result FROM public.replace_document_version(replace_document,replace_intake,replace_revision,'replay replacement',owner,'81900000-0000-0000-0000-000000000015');
  IF first_result.code <> 'ok' OR first_result.document_version_id IS NULL THEN RAISE EXCEPTION 'replace ordinary success failed'; END IF;
  SELECT * INTO result FROM public.replace_document_version(replace_document,replace_intake,replace_revision,'replay replacement',owner,'81900000-0000-0000-0000-000000000015');
  IF result.code <> 'ok' OR result.document_version_id IS DISTINCT FROM first_result.document_version_id OR result.lifecycle_revision IS DISTINCT FROM first_result.lifecycle_revision THEN RAISE EXCEPTION 'replace ordinary retry did not replay its original result'; END IF;
  SELECT lifecycle_revision INTO replace_other_revision FROM public.documents WHERE id=replace_other_document;
  SELECT * INTO result FROM public.replace_document_version(replace_other_document,replace_other_intake,replace_other_revision,'other replacement',owner,'81900000-0000-0000-0000-000000000015');
  IF result.code <> 'idempotency_subject_mismatch' OR result.document_version_id IS NOT NULL OR result.lifecycle_revision IS NOT NULL THEN RAISE EXCEPTION 'replace cross-subject key reuse did not fail closed'; END IF;
  IF (SELECT current_version_id=replace_other_old_version FROM public.documents WHERE id=replace_other_document) IS NOT TRUE
     OR (SELECT state='ready' FROM public.intake_items WHERE id=replace_other_intake) IS NOT TRUE THEN
    RAISE EXCEPTION 'replace cross-subject key reuse mutated its new subject';
  END IF;
END $idempotency_replays$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','81100000-0000-0000-0000-000000000002',true);
DO $cross_tenant$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.get_intake_duplicate_resolution('81700000-0000-0000-0000-000000000001');
  IF result.code <> 'not_available' OR result.document_id IS NOT NULL OR result.matter_id IS NOT NULL OR result.intake_id IS NOT NULL THEN
    RAISE EXCEPTION 'cross-tenant duplicate lookup disclosed a result';
  END IF;
END $cross_tenant$;
RESET ROLE;
ROLLBACK;
