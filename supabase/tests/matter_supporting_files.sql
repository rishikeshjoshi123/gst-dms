-- Run after migration 00156 against a disposable local Supabase database.
-- Comprehensive Matter Files acceptance: category, association, privilege, and
-- negative-case matrix. Fixture is rollback-only.
\set ON_ERROR_STOP on
BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- Fixture: users, org, members, matters, documents
-- ═══════════════════════════════════════════════════════════════════════════
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
  ('00000000-0000-0000-0000-000000000000','a1560000-0000-0000-0000-000000000001','authenticated','authenticated','owner@files.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1560000-0000-0000-0000-000000000002','authenticated','authenticated','admin@files.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1560000-0000-0000-0000-000000000003','authenticated','authenticated','associate@files.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1560000-0000-0000-0000-000000000004','authenticated','authenticated','viewer@files.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1560000-0000-0000-0000-000000000005','authenticated','authenticated','suspended@files.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1560000-0000-0000-0000-000000000006','authenticated','authenticated','foreign@files.test','x',now(),'{}','{}',now(),now());

INSERT INTO public.organisations(id,name,created_by) VALUES
  ('b1560000-0000-0000-0000-000000000001','Files organisation','a1560000-0000-0000-0000-000000000001'),
  ('b1560000-0000-0000-0000-000000000002','Foreign files organisation','a1560000-0000-0000-0000-000000000006');
INSERT INTO public.org_members(org_id,user_id,role) VALUES
  ('b1560000-0000-0000-0000-000000000001','a1560000-0000-0000-0000-000000000002','admin'),
  ('b1560000-0000-0000-0000-000000000001','a1560000-0000-0000-0000-000000000003','associate'),
  ('b1560000-0000-0000-0000-000000000001','a1560000-0000-0000-0000-000000000004','viewer'),
  ('b1560000-0000-0000-0000-000000000001','a1560000-0000-0000-0000-000000000005','associate');
UPDATE public.organisation_memberships
SET state='suspended',suspended_at=now(),suspended_by='a1560000-0000-0000-0000-000000000001',suspension_reason='fixture'
WHERE org_id='b1560000-0000-0000-0000-000000000001' AND user_id='a1560000-0000-0000-0000-000000000005';

INSERT INTO public.clients(id,org_id,name) VALUES
  ('c1560000-0000-0000-0000-000000000001','b1560000-0000-0000-0000-000000000001','Files client'),
  ('c1560000-0000-0000-0000-000000000002','b1560000-0000-0000-0000-000000000002','Foreign client');
INSERT INTO public.matters(id,org_id,client_id,title,financial_year,status) VALUES
  ('d1560000-0000-0000-0000-000000000001','b1560000-0000-0000-0000-000000000001','c1560000-0000-0000-0000-000000000001','Files matter','2026-27','active'),
  ('d1560000-0000-0000-0000-000000000002','b1560000-0000-0000-0000-000000000001','c1560000-0000-0000-0000-000000000001','Other matter','2027-28','active'),
  ('d1560000-0000-0000-0000-000000000003','b1560000-0000-0000-0000-000000000001','c1560000-0000-0000-0000-000000000001','Closed matter','2028-29','closed'),
  ('d1560000-0000-0000-0000-000000000004','b1560000-0000-0000-0000-000000000002','c1560000-0000-0000-0000-000000000002','Foreign matter','2026-27','active');

INSERT INTO public.documents(id,org_id,matter_id,display_title,document_class,origin_kind,content_availability,status,created_by) VALUES
  ('e1560000-0000-0000-0000-000000000001','b1560000-0000-0000-0000-000000000001','d1560000-0000-0000-0000-000000000001','Supporting invoice','supporting','manual_record','metadata_only','placed','a1560000-0000-0000-0000-000000000001'),
  ('e1560000-0000-0000-0000-000000000002','b1560000-0000-0000-0000-000000000001','d1560000-0000-0000-0000-000000000001','Proceeding SCN','proceeding','manual_record','metadata_only','placed','a1560000-0000-0000-0000-000000000001'),
  ('e1560000-0000-0000-0000-000000000003','b1560000-0000-0000-0000-000000000001','d1560000-0000-0000-0000-000000000001','Supporting receipt','supporting','manual_record','metadata_only','placed','a1560000-0000-0000-0000-000000000001'),
  ('e1560000-0000-0000-0000-000000000004','b1560000-0000-0000-0000-000000000001','d1560000-0000-0000-0000-000000000001','Trashed supporting','supporting','manual_record','metadata_only','placed','a1560000-0000-0000-0000-000000000001'),
  ('e1560000-0000-0000-0000-000000000005','b1560000-0000-0000-0000-000000000001','d1560000-0000-0000-0000-000000000001','Trashed proceeding','proceeding','manual_record','metadata_only','placed','a1560000-0000-0000-0000-000000000001'),
  ('e1560000-0000-0000-0000-000000000006','b1560000-0000-0000-0000-000000000001','d1560000-0000-0000-0000-000000000002','Other matter supporting','supporting','manual_record','metadata_only','placed','a1560000-0000-0000-0000-000000000001'),
  ('e1560000-0000-0000-0000-000000000007','b1560000-0000-0000-0000-000000000001','d1560000-0000-0000-0000-000000000002','Other matter proceeding','proceeding','manual_record','metadata_only','placed','a1560000-0000-0000-0000-000000000001'),
  ('e1560000-0000-0000-0000-000000000008','b1560000-0000-0000-0000-000000000001','d1560000-0000-0000-0000-000000000003','Closed supporting','supporting','manual_record','metadata_only','placed','a1560000-0000-0000-0000-000000000001'),
  ('e1560000-0000-0000-0000-000000000009','b1560000-0000-0000-0000-000000000001','d1560000-0000-0000-0000-000000000003','Closed proceeding','proceeding','manual_record','metadata_only','placed','a1560000-0000-0000-0000-000000000001'),
  ('e1560000-0000-0000-0000-000000000010','b1560000-0000-0000-0000-000000000002','d1560000-0000-0000-0000-000000000004','Foreign supporting','supporting','manual_record','metadata_only','placed','a1560000-0000-0000-0000-000000000006');
UPDATE public.documents SET record_state='trashed',deleted_at=now(),trashed_at=now()
WHERE id IN ('e1560000-0000-0000-0000-000000000004','e1560000-0000-0000-0000-000000000005');

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 1: Exact enum values
-- ═══════════════════════════════════════════════════════════════════════════
DO $enum$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM pg_type t JOIN pg_enum e ON t.oid=e.enumtypid
  WHERE t.typname='document_evidence_association_kind';
  ASSERT v_count = 4, 'Expected exactly 4 enum values';
  ASSERT EXISTS (SELECT 1 FROM pg_type t JOIN pg_enum e ON t.oid=e.enumtypid WHERE t.typname='document_evidence_association_kind' AND e.enumlabel='supports');
  ASSERT EXISTS (SELECT 1 FROM pg_type t JOIN pg_enum e ON t.oid=e.enumtypid WHERE t.typname='document_evidence_association_kind' AND e.enumlabel='submitted_with');
  ASSERT EXISTS (SELECT 1 FROM pg_type t JOIN pg_enum e ON t.oid=e.enumtypid WHERE t.typname='document_evidence_association_kind' AND e.enumlabel='attachment_to');
  ASSERT EXISTS (SELECT 1 FROM pg_type t JOIN pg_enum e ON t.oid=e.enumtypid WHERE t.typname='document_evidence_association_kind' AND e.enumlabel='background');
END $enum$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 2: Exact category seeds
-- ═══════════════════════════════════════════════════════════════════════════
DO $seeds$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.supporting_file_categories WHERE org_id IS NULL AND lifecycle='active';
  ASSERT v_count = 6, 'Expected 6 system categories';
  ASSERT EXISTS (SELECT 1 FROM public.supporting_file_categories WHERE id='01560000-0000-0000-0000-000000000001' AND category_key='evidence' AND label='Evidence');
  ASSERT EXISTS (SELECT 1 FROM public.supporting_file_categories WHERE id='01560000-0000-0000-0000-000000000002' AND category_key='financial_records' AND label='Invoices & financial records');
  ASSERT EXISTS (SELECT 1 FROM public.supporting_file_categories WHERE id='01560000-0000-0000-0000-000000000003' AND category_key='correspondence' AND label='Correspondence');
  ASSERT EXISTS (SELECT 1 FROM public.supporting_file_categories WHERE id='01560000-0000-0000-0000-000000000004' AND category_key='research_authorities' AND label='Research & authorities');
  ASSERT EXISTS (SELECT 1 FROM public.supporting_file_categories WHERE id='01560000-0000-0000-0000-000000000005' AND category_key='media_site_material' AND label='Media & site material');
  ASSERT EXISTS (SELECT 1 FROM public.supporting_file_categories WHERE id='01560000-0000-0000-0000-000000000006' AND category_key='other' AND label='Other' AND sort_order=9000);
END $seeds$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 3: Base table SELECT/INSERT/UPDATE/DELETE denied on all new tables
-- ═══════════════════════════════════════════════════════════════════════════
DO $acl$
DECLARE tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'supporting_file_categories', 'supporting_category_command_receipts',
    'document_supporting_category_command_receipts', 'document_supporting_category_decisions',
    'document_evidence_associations', 'document_evidence_association_command_receipts',
    'document_evidence_association_decisions'
  ] LOOP
    ASSERT NOT has_table_privilege('authenticated', 'public.' || tbl, 'SELECT'),
      'authenticated should not SELECT ' || tbl;
    ASSERT NOT has_table_privilege('authenticated', 'public.' || tbl, 'INSERT'),
      'authenticated should not INSERT ' || tbl;
    ASSERT NOT has_table_privilege('authenticated', 'public.' || tbl, 'UPDATE'),
      'authenticated should not UPDATE ' || tbl;
    ASSERT NOT has_table_privilege('authenticated', 'public.' || tbl, 'DELETE'),
      'authenticated should not DELETE ' || tbl;
    ASSERT NOT has_table_privilege('anon', 'public.' || tbl, 'SELECT'),
      'anon should not SELECT ' || tbl;
    ASSERT NOT has_table_privilege('service_role', 'public.' || tbl, 'SELECT'),
      'service_role should not SELECT ' || tbl;
  END LOOP;
END $acl$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 4: Function privilege matrix
-- ═══════════════════════════════════════════════════════════════════════════
DO $fn_acl$
DECLARE fn_sig text;
BEGIN
  -- Projection and command functions: granted to authenticated, denied to PUBLIC/anon/service_role
  FOREACH fn_sig IN ARRAY ARRAY[
    'public.get_active_supporting_categories(uuid)',
    'public.get_document_supporting_category(uuid)',
    'public.get_active_evidence_associations(uuid,uuid,uuid)',
    'public.supersede_supporting_file_category(uuid,text,text,smallint,bigint,uuid)',
    'public.change_document_supporting_category(uuid,uuid,uuid,bigint,uuid)',
    'public.activate_document_evidence_association(uuid,uuid,uuid,public.document_evidence_association_kind,text,bigint,bigint,uuid)',
    'public.archive_document_evidence_association(uuid,uuid,bigint,text,uuid)'
  ] LOOP
    ASSERT has_function_privilege('authenticated', fn_sig, 'EXECUTE'),
      'authenticated should EXECUTE ' || fn_sig;
    ASSERT NOT has_function_privilege('anon', fn_sig, 'EXECUTE'),
      'anon should not EXECUTE ' || fn_sig;
    ASSERT NOT has_function_privilege('service_role', fn_sig, 'EXECUTE'),
      'service_role should not EXECUTE ' || fn_sig;
  END LOOP;
  -- Trigger/helper functions: denied to everyone
  FOREACH fn_sig IN ARRAY ARRAY[
    'public.supporting_categories_system_immutable()',
    'public.supporting_category_receipts_prevent_mutation()',
    'public.documents_enforce_supporting_category()',
    'public.enforce_document_supporting_category_decision()',
    'public.doc_category_decisions_prevent_mutation()',
    'public.enforce_document_evidence_association()',
    'public.enforce_evidence_association_decision()',
    'public.evidence_association_decisions_prevent_mutation()'
  ] LOOP
    ASSERT NOT has_function_privilege('authenticated', fn_sig, 'EXECUTE'),
      'authenticated should not EXECUTE helper ' || fn_sig;
    ASSERT NOT has_function_privilege('anon', fn_sig, 'EXECUTE'),
      'anon should not EXECUTE helper ' || fn_sig;
    ASSERT NOT has_function_privilege('service_role', fn_sig, 'EXECUTE'),
      'service_role should not EXECUTE helper ' || fn_sig;
  END LOOP;
END $fn_acl$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 5: System category immutability
-- ═══════════════════════════════════════════════════════════════════════════
DO $sys_imm$
BEGIN
  BEGIN
    UPDATE public.supporting_file_categories SET label='Hacked' WHERE id='01560000-0000-0000-0000-000000000001';
    ASSERT false, 'System category UPDATE should fail';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    DELETE FROM public.supporting_file_categories WHERE id='01560000-0000-0000-0000-000000000001';
    ASSERT false, 'System category DELETE should fail';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END $sys_imm$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 6: Wrong-class assignment (proceeding → supporting category)
-- ═══════════════════════════════════════════════════════════════════════════
DO $wrong_class$
BEGIN
  BEGIN
    UPDATE public.documents SET supporting_category_id='01560000-0000-0000-0000-000000000001'
    WHERE id='e1560000-0000-0000-0000-000000000002'; -- proceeding
    ASSERT false, 'Proceeding document should not accept a supporting category';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $wrong_class$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 7: Cross-org category assignment at DB boundary
-- ═══════════════════════════════════════════════════════════════════════════
DO $cross_org_cat$
DECLARE
  v_temp_doc uuid := gen_random_uuid();
BEGIN
  -- Insert a temp supporting document in org1
  INSERT INTO public.documents (
    id, org_id, matter_id, display_title, document_class, origin_kind,
    content_availability, status, created_by
  ) VALUES (
    v_temp_doc, 'b1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
    'Temp test doc', 'supporting', 'manual_record', 'metadata_only', 'placed',
    'a1560000-0000-0000-0000-000000000001'
  );

  -- Create an org category in the foreign org
  INSERT INTO public.supporting_file_categories (id,category_key,label,sort_order,lifecycle,org_id,category_version,created_by)
  VALUES ('f1560000-0000-0000-0000-000000000001','foreign_cat','Foreign cat',10,'active','b1560000-0000-0000-0000-000000000002',1,'a1560000-0000-0000-0000-000000000006');

  BEGIN
    UPDATE public.documents SET supporting_category_id='f1560000-0000-0000-0000-000000000001'
    WHERE id=v_temp_doc; -- org1 supporting doc
    ASSERT false, 'Cross-org category assignment should fail';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- System category should work fine on any org's doc
  UPDATE public.documents SET supporting_category_id='01560000-0000-0000-0000-000000000001'
  WHERE id=v_temp_doc;
END $cross_org_cat$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 8: Owner category change + projections
-- ═══════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000001',true);
DO $owner_cat$
DECLARE v_result record; v_cat record; v_doc_cat record; v_act_count integer; v_outbox_count integer;
BEGIN
  -- Before: check active categories include 6 system
  SELECT count(*) INTO v_act_count FROM public.get_active_supporting_categories('b1560000-0000-0000-0000-000000000001');
  ASSERT v_act_count = 6, 'Expected 6 active system categories, got ' || v_act_count;

  -- Change category to evidence
  SELECT * INTO v_result FROM public.change_document_supporting_category(
    'e1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
    '01560000-0000-0000-0000-000000000001', 1, 'f0000001-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'ok', 'Category change should succeed: ' || v_result.code;
  ASSERT v_result.revision = 2, 'Expected revision 2';
  ASSERT NOT v_result.replayed;

  -- Verify selected-category reader works (including for later retired test)
  SELECT * INTO v_doc_cat FROM public.get_document_supporting_category('e1560000-0000-0000-0000-000000000001');
  ASSERT v_doc_cat.id = '01560000-0000-0000-0000-000000000001', 'Selected category should be evidence';
  ASSERT v_doc_cat.category_key = 'evidence';
  ASSERT v_doc_cat.lifecycle = 'active';

  -- Replay: same command returns ok+replayed
  SELECT * INTO v_result FROM public.change_document_supporting_category(
    'e1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
    '01560000-0000-0000-0000-000000000001', 1, 'f0000001-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'ok' AND v_result.replayed, 'Replay should succeed';

  -- Idempotency conflict: same key, different payload
  SELECT * INTO v_result FROM public.change_document_supporting_category(
    'e1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
    '01560000-0000-0000-0000-000000000002', 1, 'f0000001-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'idempotency_conflict', 'Different payload should conflict';

  -- Stale revision
  SELECT * INTO v_result FROM public.change_document_supporting_category(
    'e1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
    '01560000-0000-0000-0000-000000000003', 1, 'f0000001-0000-0000-0000-000000000002'
  );
  ASSERT v_result.code = 'conflict', 'Stale revision should conflict, got ' || v_result.code;
END $owner_cat$;
RESET ROLE;

DO $owner_cat_events$
BEGIN
  -- Verify Activity row was created
  ASSERT EXISTS (SELECT 1 FROM public.activity_events WHERE idempotency_key = 'document.category.f0000001-0000-0000-0000-000000000001'),
    'Activity event should exist';

  -- Verify outbox event was created with correct bounded payload
  ASSERT EXISTS (SELECT 1 FROM public.outbox_events
    WHERE event_kind = 'document.supporting_category_changed.v1'
      AND aggregate_type = 'document'
      AND aggregate_id = 'e1560000-0000-0000-0000-000000000001'
      AND idempotency_key = 'f0000001-0000-0000-0000-000000000001'
      AND payload->>'category_id' = '01560000-0000-0000-0000-000000000001'
      AND payload->>'revision' = '2'),
    'Outbox event should exist with category_id and revision';
END $owner_cat_events$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 9: Viewer cannot change category
-- ═══════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000004',true);
DO $viewer_cat$
DECLARE v_result record;
BEGIN
  SELECT * INTO v_result FROM public.change_document_supporting_category(
    'e1560000-0000-0000-0000-000000000003', 'd1560000-0000-0000-0000-000000000001',
    '01560000-0000-0000-0000-000000000001', 1, 'f0000002-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'not_allowed', 'Viewer should not change category';
END $viewer_cat$;
-- Viewer can read active categories
DO $viewer_read$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.get_active_supporting_categories('b1560000-0000-0000-0000-000000000001');
  ASSERT v_count >= 6, 'Viewer should read active categories';
  -- Viewer can read document's selected category
  SELECT count(*) INTO v_count FROM public.get_document_supporting_category('e1560000-0000-0000-0000-000000000001');
  ASSERT v_count = 1, 'Viewer should read document selected category';
END $viewer_read$;
RESET ROLE;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 10: Suspended member fail-closed
-- ═══════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000005',true);
DO $suspended$
DECLARE v_result record; v_count integer;
BEGIN
  SELECT * INTO v_result FROM public.change_document_supporting_category(
    'e1560000-0000-0000-0000-000000000003', 'd1560000-0000-0000-0000-000000000001',
    '01560000-0000-0000-0000-000000000001', 1, 'f0000003-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'not_allowed', 'Suspended member should be denied';
  -- Suspended reads fail-closed
  SELECT count(*) INTO v_count FROM public.get_active_supporting_categories('b1560000-0000-0000-0000-000000000001');
  ASSERT v_count = 0, 'Suspended should not read categories';
END $suspended$;
RESET ROLE;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 11: Foreign member fail-closed
-- ═══════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000006',true);
DO $foreign$
DECLARE v_result record; v_count integer;
BEGIN
  SELECT * INTO v_result FROM public.change_document_supporting_category(
    'e1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
    '01560000-0000-0000-0000-000000000001', 2, 'f0000004-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'context_unavailable', 'Foreign member should get context_unavailable, got ' || v_result.code;
  SELECT count(*) INTO v_count FROM public.get_active_supporting_categories('b1560000-0000-0000-0000-000000000001');
  ASSERT v_count = 0, 'Foreign should not read org1 categories';
END $foreign$;
RESET ROLE;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 12: Trashed document category change fails
-- ═══════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000001',true);
DO $trashed_cat$
DECLARE v_result record;
BEGIN
  SELECT * INTO v_result FROM public.change_document_supporting_category(
    'e1560000-0000-0000-0000-000000000004', 'd1560000-0000-0000-0000-000000000001',
    '01560000-0000-0000-0000-000000000001', 1, 'f0000005-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'context_unavailable', 'Trashed document should be context_unavailable, got ' || v_result.code;
END $trashed_cat$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 13: Closed matter category change fails
-- ═══════════════════════════════════════════════════════════════════════════
DO $closed_cat$
DECLARE v_result record;
BEGIN
  SELECT * INTO v_result FROM public.change_document_supporting_category(
    'e1560000-0000-0000-0000-000000000008', 'd1560000-0000-0000-0000-000000000003',
    '01560000-0000-0000-0000-000000000001', 1, 'f0000006-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'matter_read_only', 'Closed matter should be matter_read_only, got ' || v_result.code;
END $closed_cat$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 14: Wrong-class via RPC (proceeding doc)
-- ═══════════════════════════════════════════════════════════════════════════
DO $rpc_wrong_class$
DECLARE v_result record;
BEGIN
  SELECT * INTO v_result FROM public.change_document_supporting_category(
    'e1560000-0000-0000-0000-000000000002', 'd1560000-0000-0000-0000-000000000001',
    '01560000-0000-0000-0000-000000000001', 1, 'f0000007-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'invalid_endpoint_class', 'Proceeding doc should get invalid_endpoint_class, got ' || v_result.code;
END $rpc_wrong_class$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 15: Catalogue supersede (Owner/Admin only) with CAS
-- ═══════════════════════════════════════════════════════════════════════════
DO $supersede$
DECLARE v_result record; v_count integer;
BEGIN
  -- Create new org category (expected_revision=0 for first version)
  SELECT * INTO v_result FROM public.supersede_supporting_file_category(
    'b1560000-0000-0000-0000-000000000001', 'custom_cat', 'Custom category', 15::smallint, 0,
    'f0000010-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'ok', 'Supersede create should succeed: ' || v_result.code;
  ASSERT v_result.revision = 1;

  -- Supersede with new label
  SELECT * INTO v_result FROM public.supersede_supporting_file_category(
    'b1560000-0000-0000-0000-000000000001', 'custom_cat', 'Updated category', 16::smallint, 1,
    'f0000010-0000-0000-0000-000000000002'
  );
  ASSERT v_result.code = 'ok', 'Supersede update should succeed: ' || v_result.code;
  ASSERT v_result.revision = 2;

  -- Replay
  SELECT * INTO v_result FROM public.supersede_supporting_file_category(
    'b1560000-0000-0000-0000-000000000001', 'custom_cat', 'Updated category', 16::smallint, 1,
    'f0000010-0000-0000-0000-000000000002'
  );
  ASSERT v_result.code = 'ok' AND v_result.replayed, 'Supersede replay should succeed';

  -- Idempotency conflict
  SELECT * INTO v_result FROM public.supersede_supporting_file_category(
    'b1560000-0000-0000-0000-000000000001', 'custom_cat', 'Different label', 16::smallint, 1,
    'f0000010-0000-0000-0000-000000000002'
  );
  ASSERT v_result.code = 'idempotency_conflict';

  -- Stale revision
  SELECT * INTO v_result FROM public.supersede_supporting_file_category(
    'b1560000-0000-0000-0000-000000000001', 'custom_cat', 'Version3', 17::smallint, 1,
    'f0000010-0000-0000-0000-000000000003'
  );
  ASSERT v_result.code = 'conflict', 'Stale revision should conflict';

  -- System key immutable through RPC
  SELECT * INTO v_result FROM public.supersede_supporting_file_category(
    'b1560000-0000-0000-0000-000000000001', 'evidence', 'My evidence', 10::smallint, 0,
    'f0000010-0000-0000-0000-000000000004'
  );
  ASSERT v_result.code = 'system_immutable', 'System key should be immutable';

  -- Active categories now includes the org row
  SELECT count(*) INTO v_count FROM public.get_active_supporting_categories('b1560000-0000-0000-0000-000000000001');
  ASSERT v_count = 7, 'Expected 7 active categories (6 system + 1 org), got ' || v_count;
END $supersede$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 16: Catalogue supersede denied for Viewer/Associate
-- ═══════════════════════════════════════════════════════════════════════════
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000004',true);
DO $viewer_supersede$
DECLARE v_result record;
BEGIN
  SELECT * INTO v_result FROM public.supersede_supporting_file_category(
    'b1560000-0000-0000-0000-000000000001', 'viewer_cat', 'Viewer cat', 10::smallint, 0,
    'f0000011-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'not_allowed', 'Viewer should not supersede categories';
END $viewer_supersede$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000003',true);
DO $assoc_supersede$
DECLARE v_result record;
BEGIN
  SELECT * INTO v_result FROM public.supersede_supporting_file_category(
    'b1560000-0000-0000-0000-000000000001', 'assoc_cat', 'Assoc cat', 10::smallint, 0,
    'f0000012-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'not_allowed', 'Associate should not supersede categories';
END $assoc_supersede$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 17: Retired category rendering
-- ═══════════════════════════════════════════════════════════════════════════
-- Associate can change doc category
DO $assoc_cat$
DECLARE v_result record;
BEGIN
  SELECT * INTO v_result FROM public.change_document_supporting_category(
    'e1560000-0000-0000-0000-000000000003', 'd1560000-0000-0000-0000-000000000001',
    '01560000-0000-0000-0000-000000000002', 1, 'f0000020-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'ok', 'Associate should change category: ' || v_result.code;
END $assoc_cat$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000001',true);
DO $retired_render$
DECLARE v_result record; v_cat_id uuid; v_doc_cat record; v_active_count integer;
BEGIN
  -- Supersede custom_cat (v2→v3). Assign doc to v2 first.
  -- v2 is already active from test 15. Get its id via projection.
  SELECT id INTO v_cat_id FROM public.get_active_supporting_categories('b1560000-0000-0000-0000-000000000001')
  WHERE category_key='custom_cat';
  -- Assign doc e1560000...0003 to this custom category
  SELECT * INTO v_result FROM public.change_document_supporting_category(
    'e1560000-0000-0000-0000-000000000003', 'd1560000-0000-0000-0000-000000000001',
    v_cat_id, 2, 'f0000021-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'ok', 'Assign to org cat should succeed: ' || v_result.code;

  -- Now supersede custom_cat v2→v3, retiring v2
  SELECT * INTO v_result FROM public.supersede_supporting_file_category(
    'b1560000-0000-0000-0000-000000000001', 'custom_cat', 'Version 3', 17::smallint, 2,
    'f0000021-0000-0000-0000-000000000002'
  );
  ASSERT v_result.code = 'ok', 'Supersede v2→v3 should succeed';

  -- Active categories should show v3, not v2
  SELECT count(*) INTO v_active_count FROM public.get_active_supporting_categories('b1560000-0000-0000-0000-000000000001')
  WHERE category_key = 'custom_cat' AND label = 'Version 3';
  ASSERT v_active_count = 1, 'Active should show v3';

  -- But document's selected category reader still returns the retired v2
  SELECT * INTO v_doc_cat FROM public.get_document_supporting_category('e1560000-0000-0000-0000-000000000003');
  ASSERT v_doc_cat.id = v_cat_id, 'Selected category should still return retired v2';
  ASSERT v_doc_cat.lifecycle = 'retired', 'Selected category lifecycle should be retired';
  ASSERT v_doc_cat.label = 'Updated category', 'Selected category label should be v2 label';
END $retired_render$;
RESET ROLE;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 18: Activate evidence association (happy path)
-- ═══════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000001',true);
DO $activate_assoc$
DECLARE
  v_result record;
  v_assocs integer;
  v_supp_rev bigint;
  v_proc_rev bigint;
BEGIN
  SELECT lifecycle_revision INTO v_supp_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000001';
  SELECT lifecycle_revision INTO v_proc_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000002';

  SELECT * INTO v_result FROM public.activate_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000001', -- supporting
    'e1560000-0000-0000-0000-000000000002', -- proceeding
    'supports', 'Key invoice', v_supp_rev, v_proc_rev,
    'f0000030-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'ok', 'Activation should succeed: ' || v_result.code;
  ASSERT v_result.revision = 1;
  ASSERT NOT v_result.replayed;

  -- Active associations visible via projection
  SELECT count(*) INTO v_assocs FROM public.get_active_evidence_associations(
    'b1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000001'
  );
  ASSERT v_assocs = 1, 'Should see 1 active association';

  -- Replay
  SELECT * INTO v_result FROM public.activate_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000001', 'e1560000-0000-0000-0000-000000000002',
    'supports', 'Key invoice', v_supp_rev, v_proc_rev, 'f0000030-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'ok' AND v_result.replayed, 'Replay should succeed';

  -- Idempotency conflict
  SELECT * INTO v_result FROM public.activate_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000001', 'e1560000-0000-0000-0000-000000000002',
    'background', NULL, v_supp_rev, v_proc_rev, 'f0000030-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'idempotency_conflict';
END $activate_assoc$;
RESET ROLE;

DO $activate_events$
BEGIN
  -- Activity and outbox created
  ASSERT EXISTS (SELECT 1 FROM public.activity_events WHERE idempotency_key = 'evidence.activate.f0000030-0000-0000-0000-000000000001');
  ASSERT EXISTS (SELECT 1 FROM public.outbox_events
    WHERE event_kind = 'document.evidence_association_changed.v1'
      AND idempotency_key = 'f0000030-0000-0000-0000-000000000001'
      AND payload->>'revision' = '1');
END $activate_events$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 19: Duplicate active pair+kind
-- ═══════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000001',true);
DO $dup_active$
DECLARE
  v_result record;
  v_supp_rev bigint;
  v_proc_rev bigint;
BEGIN
  SELECT lifecycle_revision INTO v_supp_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000001';
  SELECT lifecycle_revision INTO v_proc_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000002';

  SELECT * INTO v_result FROM public.activate_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000001', 'e1560000-0000-0000-0000-000000000002',
    'supports', NULL, v_supp_rev, v_proc_rev, 'f0000031-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'duplicate_active', 'Duplicate active pair+kind should fail: ' || v_result.code;
  -- Different kind is OK
  SELECT * INTO v_result FROM public.activate_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000001', 'e1560000-0000-0000-0000-000000000002',
    'background', NULL, v_supp_rev, v_proc_rev, 'f0000031-0000-0000-0000-000000000002'
  );
  ASSERT v_result.code = 'ok', 'Different kind should succeed: ' || v_result.code;
END $dup_active$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 20: Trashed endpoints
-- ═══════════════════════════════════════════════════════════════════════════
DO $trashed_endpoints$
DECLARE
  v_result record;
  v_supp_rev bigint;
  v_proc_rev bigint;
BEGIN
  -- Both trashed: supporting trashed
  SELECT lifecycle_revision INTO v_supp_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000004';
  SELECT lifecycle_revision INTO v_proc_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000002';
  SELECT * INTO v_result FROM public.activate_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000004', 'e1560000-0000-0000-0000-000000000002',
    'supports', NULL, coalesce(v_supp_rev, 1), coalesce(v_proc_rev, 1), 'f0000032-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'endpoint_unavailable', 'Trashed supporting should fail: ' || v_result.code;
  -- Proceeding trashed
  SELECT lifecycle_revision INTO v_supp_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000001';
  SELECT lifecycle_revision INTO v_proc_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000005';
  SELECT * INTO v_result FROM public.activate_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000001', 'e1560000-0000-0000-0000-000000000005',
    'supports', NULL, coalesce(v_supp_rev, 1), coalesce(v_proc_rev, 1), 'f0000032-0000-0000-0000-000000000002'
  );
  ASSERT v_result.code = 'endpoint_unavailable', 'Trashed proceeding should fail: ' || v_result.code;
END $trashed_endpoints$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 21: Different matters
-- ═══════════════════════════════════════════════════════════════════════════
DO $diff_matter$
DECLARE
  v_result record;
  v_supp_rev bigint;
  v_proc_rev bigint;
BEGIN
  SELECT lifecycle_revision INTO v_supp_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000006';
  SELECT lifecycle_revision INTO v_proc_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000002';
  SELECT * INTO v_result FROM public.activate_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000006', -- other matter supporting
    'e1560000-0000-0000-0000-000000000002', -- this matter proceeding
    'supports', NULL, v_supp_rev, v_proc_rev, 'f0000033-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'context_unavailable', 'Cross-matter should fail: ' || v_result.code;
END $diff_matter$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 22: Closed matter association
-- ═══════════════════════════════════════════════════════════════════════════
DO $closed_assoc$
DECLARE
  v_result record;
  v_supp_rev bigint;
  v_proc_rev bigint;
BEGIN
  SELECT lifecycle_revision INTO v_supp_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000008';
  SELECT lifecycle_revision INTO v_proc_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000009';
  SELECT * INTO v_result FROM public.activate_document_evidence_association(
    'd1560000-0000-0000-0000-000000000003',
    'e1560000-0000-0000-0000-000000000008', 'e1560000-0000-0000-0000-000000000009',
    'supports', NULL, v_supp_rev, v_proc_rev, 'f0000034-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'matter_read_only', 'Closed matter should fail: ' || v_result.code;
END $closed_assoc$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 23: Archive association
-- ═══════════════════════════════════════════════════════════════════════════
DO $archive_assoc$
DECLARE v_result record; v_assoc_id uuid; v_assocs integer;
BEGIN
  -- Get the association ID from test 18 via projection
  SELECT id INTO v_assoc_id FROM public.get_active_evidence_associations(
    'b1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000001'
  ) WHERE kind='supports';

  -- Archive it
  SELECT * INTO v_result FROM public.archive_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001', v_assoc_id, 1,
    'No longer relevant', 'f0000040-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'ok', 'Archive should succeed: ' || v_result.code;
  ASSERT v_result.revision = 2;

  -- Replay
  SELECT * INTO v_result FROM public.archive_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001', v_assoc_id, 1,
    'No longer relevant', 'f0000040-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'ok' AND v_result.replayed, 'Archive replay should succeed';

  -- Stale CAS
  SELECT * INTO v_result FROM public.archive_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001', v_assoc_id, 1,
    'Different reason', 'f0000040-0000-0000-0000-000000000002'
  );
  ASSERT v_result.code = 'already_archived', 'Already archived should return already_archived: ' || v_result.code;

  -- Archive should remove from active projections
  SELECT count(*) INTO v_assocs FROM public.get_active_evidence_associations(
    'b1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000001'
  ) WHERE kind = 'supports';
  ASSERT v_assocs = 0, 'Archived supports association should not appear in active';

  -- Background association still active
  SELECT count(*) INTO v_assocs FROM public.get_active_evidence_associations(
    'b1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000001'
  ) WHERE kind = 'background';
  ASSERT v_assocs = 1, 'Background association should still be active';
END $archive_assoc$;
RESET ROLE;

DO $archive_events$
BEGIN
  ASSERT EXISTS (SELECT 1 FROM public.outbox_events
    WHERE event_kind = 'document.evidence_association_changed.v1'
      AND idempotency_key = 'f0000040-0000-0000-0000-000000000001'
      AND payload->>'revision' = '2'),
    'Archive outbox event should exist with revision 2';
END $archive_events$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 24: Archive with trashed endpoint (deterministic code)
-- ═══════════════════════════════════════════════════════════════════════════
DO $archive_trashed_setup$
BEGIN
  PERFORM set_config('test.archive_assoc_id', (
    SELECT id::text FROM public.document_evidence_associations
    WHERE org_id='b1560000-0000-0000-0000-000000000001'
      AND supporting_document_id='e1560000-0000-0000-0000-000000000001'
      AND kind='background' AND record_state='active'
  ), true);
  UPDATE public.documents SET record_state='trashed', deleted_at=now(), trashed_at=now()
  WHERE id='e1560000-0000-0000-0000-000000000001';
END $archive_trashed_setup$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000001',true);
DO $archive_trashed$
DECLARE v_result record;
BEGIN
  -- Archive should return endpoint_unavailable, not a constraint exception
  SELECT * INTO v_result FROM public.archive_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001',
    current_setting('test.archive_assoc_id')::uuid, 1,
    'Cleanup after trash', 'f0000041-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'endpoint_unavailable', 'Trashed endpoint archive should be deterministic: ' || v_result.code;
END $archive_trashed$;
RESET ROLE;

-- Restore for subsequent tests
UPDATE public.documents SET record_state='active', deleted_at=NULL, trashed_at=NULL
WHERE id='e1560000-0000-0000-0000-000000000001';

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 25: Concise note validation
-- ═══════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000001',true);
DO $note_val$
DECLARE
  v_result record;
  v_supp_rev bigint;
  v_proc_rev bigint;
BEGIN
  SELECT lifecycle_revision INTO v_supp_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000003';
  SELECT lifecycle_revision INTO v_proc_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000002';
  -- Control character in note
  SELECT * INTO v_result FROM public.activate_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000003', 'e1560000-0000-0000-0000-000000000002',
    'submitted_with', E'bad\nnote', v_supp_rev, v_proc_rev, 'f0000050-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'invalid_request', 'Control char in note should fail: ' || v_result.code;
  -- Overly long note (> 200 chars)
  SELECT * INTO v_result FROM public.activate_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000003', 'e1560000-0000-0000-0000-000000000002',
    'submitted_with', repeat('x', 201), v_supp_rev, v_proc_rev, 'f0000050-0000-0000-0000-000000000002'
  );
  ASSERT v_result.code = 'invalid_request', 'Long note should fail: ' || v_result.code;
END $note_val$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 26: Archive reason validation
-- ═══════════════════════════════════════════════════════════════════════════
DO $reason_val$
DECLARE
  v_result record;
  v_assoc_id uuid;
  v_supp_rev bigint;
  v_proc_rev bigint;
BEGIN
  SELECT lifecycle_revision INTO v_supp_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000003';
  SELECT lifecycle_revision INTO v_proc_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000002';
  -- Get or create an active association to test archive
  SELECT * INTO v_result FROM public.activate_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000003', 'e1560000-0000-0000-0000-000000000002',
    'submitted_with', NULL, v_supp_rev, v_proc_rev, 'f0000051-0000-0000-0000-000000000001'
  );
  v_assoc_id := v_result.association_id;

  -- Empty reason
  SELECT * INTO v_result FROM public.archive_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001', v_assoc_id, 1,
    '', 'f0000051-0000-0000-0000-000000000002'
  );
  ASSERT v_result.code = 'invalid_request', 'Empty reason should fail: ' || v_result.code;

  -- Null reason
  SELECT * INTO v_result FROM public.archive_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001', v_assoc_id, 1,
    NULL, 'f0000051-0000-0000-0000-000000000003'
  );
  ASSERT v_result.code = 'invalid_request', 'Null reason should fail: ' || v_result.code;

  -- Control char in reason
  SELECT * INTO v_result FROM public.archive_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001', v_assoc_id, 1,
    E'bad\treason', 'f0000051-0000-0000-0000-000000000004'
  );
  ASSERT v_result.code = 'invalid_request', 'Control char reason should fail: ' || v_result.code;
END $reason_val$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 27: Viewer can read associations but not write
-- ═══════════════════════════════════════════════════════════════════════════
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000004',true);
DO $viewer_assoc$
DECLARE
  v_result record;
  v_count integer;
  v_supp_rev bigint;
  v_proc_rev bigint;
BEGIN
  SELECT count(*) INTO v_count FROM public.get_active_evidence_associations(
    'b1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000002'
  );
  -- background association is still active from test 19
  ASSERT v_count >= 1, 'Viewer should read associations';
  SELECT lifecycle_revision INTO v_supp_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000003';
  SELECT lifecycle_revision INTO v_proc_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000002';
  -- Viewer cannot create
  SELECT * INTO v_result FROM public.activate_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000003', 'e1560000-0000-0000-0000-000000000002',
    'attachment_to', NULL, v_supp_rev, v_proc_rev, 'f0000060-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'not_allowed', 'Viewer should not activate: ' || v_result.code;
END $viewer_assoc$;
RESET ROLE;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 28: Foreign member cannot see or write org1 associations
-- ═══════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000006',true);
DO $foreign_assoc$
DECLARE
  v_result record;
  v_count integer;
  v_supp_rev bigint;
  v_proc_rev bigint;
BEGIN
  SELECT count(*) INTO v_count FROM public.get_active_evidence_associations(
    'b1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000002'
  );
  ASSERT v_count = 0, 'Foreign should not see org1 associations';
  SELECT lifecycle_revision INTO v_supp_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000001';
  SELECT lifecycle_revision INTO v_proc_rev FROM public.documents WHERE id = 'e1560000-0000-0000-0000-000000000002';
  SELECT * INTO v_result FROM public.activate_document_evidence_association(
    'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000001', 'e1560000-0000-0000-0000-000000000002',
    'supports', NULL, coalesce(v_supp_rev, 1), coalesce(v_proc_rev, 1), 'f0000061-0000-0000-0000-000000000001'
  );
  ASSERT v_result.code = 'context_unavailable', 'Foreign should not activate: ' || v_result.code;
END $foreign_assoc$;
RESET ROLE;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 29: No rows in document_relationships or Timeline
-- ═══════════════════════════════════════════════════════════════════════════
DO $no_timeline$
DECLARE v_dr_count integer; v_tl record;
BEGIN
  SELECT count(*) INTO v_dr_count FROM public.document_relationships
  WHERE org_id = 'b1560000-0000-0000-0000-000000000001'
    AND (source_document_id IN ('e1560000-0000-0000-0000-000000000001','e1560000-0000-0000-0000-000000000003')
         OR target_document_id IN ('e1560000-0000-0000-0000-000000000001','e1560000-0000-0000-0000-000000000003'));
  ASSERT v_dr_count = 0, 'Supporting docs should not appear in document_relationships';
END $no_timeline$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000001',true);
DO $no_timeline_proj$
DECLARE v_tl record;
BEGIN
  SELECT * INTO v_tl FROM public.read_matter_timeline_relationships('d1560000-0000-0000-0000-000000000001', NULL);
  ASSERT v_tl.outcome = 'ok' AND v_tl.relationships = '[]'::jsonb,
    'Timeline relationships should be empty (no proceeding-to-proceeding relationships created)';
END $no_timeline_proj$;
RESET ROLE;

-- ═══════════════════════════════════════════════════════════════════════════
-- ═══════════════════════════════════════════════════════════════════════════
-- Test 30: Outbox envelope validation for new event kinds
-- ═══════════════════════════════════════════════════════════════════════════
DO $envelope$
BEGIN
  -- Valid supporting_category_changed
  ASSERT public.document_lifecycle_outbox_envelope_is_safe(
    'document.supporting_category_changed.v1', 'document',
    'e1560000-0000-0000-0000-000000000001',
    '{"document_id":"e1560000-0000-0000-0000-000000000001","matter_id":"d1560000-0000-0000-0000-000000000001","category_id":"01560000-0000-0000-0000-000000000001","revision":"1"}'::jsonb
  ), 'Valid category changed envelope should pass';

  -- Valid evidence_association_changed
  ASSERT public.document_lifecycle_outbox_envelope_is_safe(
    'document.evidence_association_changed.v1', 'document',
    'e1560000-0000-0000-0000-000000000001',
    '{"document_id":"e1560000-0000-0000-0000-000000000001","matter_id":"d1560000-0000-0000-0000-000000000001","association_id":"a1560000-0000-0000-0000-000000000001","revision":"1"}'::jsonb
  ), 'Valid association changed envelope should pass';

  -- Invalid: revision = '0' (non-positive)
  ASSERT NOT public.document_lifecycle_outbox_envelope_is_safe(
    'document.supporting_category_changed.v1', 'document',
    'e1560000-0000-0000-0000-000000000001',
    '{"document_id":"e1560000-0000-0000-0000-000000000001","matter_id":"d1560000-0000-0000-0000-000000000001","category_id":"01560000-0000-0000-0000-000000000001","revision":"0"}'::jsonb
  ), 'Zero revision should fail';

  -- Invalid: missing revision
  ASSERT NOT public.document_lifecycle_outbox_envelope_is_safe(
    'document.supporting_category_changed.v1', 'document',
    'e1560000-0000-0000-0000-000000000001',
    '{"document_id":"e1560000-0000-0000-0000-000000000001","matter_id":"d1560000-0000-0000-0000-000000000001","category_id":"01560000-0000-0000-0000-000000000001"}'::jsonb
  ), 'Missing revision should fail';

  -- Invalid: extra key
  ASSERT NOT public.document_lifecycle_outbox_envelope_is_safe(
    'document.supporting_category_changed.v1', 'document',
    'e1560000-0000-0000-0000-000000000001',
    '{"document_id":"e1560000-0000-0000-0000-000000000001","matter_id":"d1560000-0000-0000-0000-000000000001","category_id":"01560000-0000-0000-0000-000000000001","revision":"1","extra":"x"}'::jsonb
  ), 'Extra key should fail';

  -- Invalid: wrong aggregate_type
  ASSERT NOT public.document_lifecycle_outbox_envelope_is_safe(
    'document.supporting_category_changed.v1', 'document_upload',
    'e1560000-0000-0000-0000-000000000001',
    '{"document_id":"e1560000-0000-0000-0000-000000000001","matter_id":"d1560000-0000-0000-0000-000000000001","category_id":"01560000-0000-0000-0000-000000000001","revision":"1"}'::jsonb
  ), 'Wrong aggregate_type should fail';

  -- Invalid: non-UUID value
  ASSERT NOT public.document_lifecycle_outbox_envelope_is_safe(
    'document.evidence_association_changed.v1', 'document',
    'e1560000-0000-0000-0000-000000000001',
    '{"document_id":"e1560000-0000-0000-0000-000000000001","matter_id":"not-a-uuid","association_id":"a1560000-0000-0000-0000-000000000001","revision":"1"}'::jsonb
  ), 'Non-UUID matter_id should fail';

  -- Existing rows still validate
  ASSERT public.document_lifecycle_outbox_envelope_is_safe(
    'document.upload_reserved.v1', 'document_upload',
    'a0000000-0000-0000-0000-000000000001',
    '{"session_id":"a0000000-0000-0000-0000-000000000001","intake_id":"b0000000-0000-0000-0000-000000000001","asset_id":"c0000000-0000-0000-0000-000000000001"}'::jsonb
  ), 'Pre-existing upload_reserved should still pass';
END $envelope$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 31: Category scoped uniqueness (system vs tenant, one active per key)
-- ═══════════════════════════════════════════════════════════════════════════
DO $scoped_uniqueness$
BEGIN
  -- 1. Cannot insert duplicate active system category for same key
  BEGIN
    INSERT INTO public.supporting_file_categories (
      id, org_id, category_key, category_version, label, sort_order, lifecycle, created_by
    ) VALUES (
      gen_random_uuid(), NULL, 'evidence', 2, 'Duplicate Active System Evidence', 1, 'active', 'a1560000-0000-0000-0000-000000000001'
    );
    ASSERT false, 'Duplicate active system category key should fail unique constraint';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- 2. Org CAN define an active category with key 'evidence' (independent from system scope)
  INSERT INTO public.supporting_file_categories (
    id, org_id, category_key, category_version, label, sort_order, lifecycle, created_by
  ) VALUES (
    'f1560000-0000-0000-0000-000000000002', 'b1560000-0000-0000-0000-000000000001',
    'evidence', 1, 'Org Custom Evidence', 10, 'active', 'a1560000-0000-0000-0000-000000000001'
  );

  -- 3. But the same org CANNOT have two active versions for the same key
  BEGIN
    INSERT INTO public.supporting_file_categories (
      id, org_id, category_key, category_version, label, sort_order, lifecycle, created_by
    ) VALUES (
      gen_random_uuid(), 'b1560000-0000-0000-0000-000000000001',
      'evidence', 2, 'Second Org Active Evidence', 11, 'active', 'a1560000-0000-0000-0000-000000000001'
    );
    ASSERT false, 'Duplicate active org category key in same org should fail';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $scoped_uniqueness$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 32: Supporting doc deterministic Other fallback & proceeding rejection
-- ═══════════════════════════════════════════════════════════════════════════
DO $fallback_and_rejection$
DECLARE
  v_new_doc_id uuid := gen_random_uuid();
  v_assigned_cat uuid;
BEGIN
  -- Insert supporting document with NULL category -> trigger assigns 'other' (0156...06)
  INSERT INTO public.documents (
    id, org_id, matter_id, display_title, document_class, origin_kind, content_availability,
    status, created_by, supporting_category_id
  ) VALUES (
    v_new_doc_id, 'b1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
    'Fallback Test Doc', 'supporting', 'manual_record', 'metadata_only', 'placed',
    'a1560000-0000-0000-0000-000000000001', NULL
  );

  SELECT supporting_category_id INTO v_assigned_cat FROM public.documents WHERE id = v_new_doc_id;
  ASSERT v_assigned_cat = '01560000-0000-0000-0000-000000000006'::uuid,
    'Supporting document without category should default to deterministic Other category, got ' || coalesce(v_assigned_cat::text, 'null');

  -- Setting category on proceeding document must fail at database boundary
  BEGIN
    INSERT INTO public.documents (
      id, org_id, matter_id, display_title, document_class, origin_kind, content_availability,
      status, created_by, supporting_category_id
    ) VALUES (
      gen_random_uuid(), 'b1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
      'Proceeding Doc Reject', 'proceeding', 'manual_record', 'metadata_only', 'placed',
      'a1560000-0000-0000-0000-000000000001', '01560000-0000-0000-0000-000000000006'
    );
    ASSERT false, 'Proceeding document with category should be rejected by trigger';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $fallback_and_rejection$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Test 33: Active association projection hides trashed, moved, and closed endpoints
-- ═══════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000001',true);
DO $hide_endpoints$
DECLARE
  v_count integer;
BEGIN
  -- Background association is active for d156...0001 and e156...0001
  SELECT count(*) INTO v_count FROM public.get_active_evidence_associations(
    'b1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000001'
  );
  ASSERT v_count >= 1, 'Should find active background association before move/close';

  -- If queried with closed matter d156...0003, returns 0 rows
  SELECT count(*) INTO v_count FROM public.get_active_evidence_associations(
    'b1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000003',
    'e1560000-0000-0000-0000-000000000008'
  );
  ASSERT v_count = 0, 'Closed matter should return 0 associations from projection';
END $hide_endpoints$;
RESET ROLE;

-- If supporting document is moved to different matter, projection should hide it
UPDATE public.documents SET matter_id = 'd1560000-0000-0000-0000-000000000002'
WHERE id = 'e1560000-0000-0000-0000-000000000001';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1560000-0000-0000-0000-000000000001',true);
DO $hide_moved$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.get_active_evidence_associations(
    'b1560000-0000-0000-0000-000000000001', 'd1560000-0000-0000-0000-000000000001',
    'e1560000-0000-0000-0000-000000000001'
  );
  ASSERT v_count = 0, 'Moved endpoint should be hidden from active associations projection';
END $hide_moved$;
RESET ROLE;

-- Restore matter_id
UPDATE public.documents SET matter_id = 'd1560000-0000-0000-0000-000000000001'
WHERE id = 'e1560000-0000-0000-0000-000000000001';

ROLLBACK;
