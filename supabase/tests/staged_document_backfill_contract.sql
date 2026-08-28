-- Run after migration 00049 against a disposable local Supabase database.
-- SQL cannot inspect Storage. It claims only a path proven to use the old
-- staging namespace, then accepts a trusted worker's safe observation result.
BEGIN;

DO $setup$
DECLARE
  org_a uuid := '48000000-0000-0000-0000-000000000001';
  org_b uuid := '48000000-0000-0000-0000-000000000002';
  user_a uuid := '48100000-0000-0000-0000-000000000001';
  user_b uuid := '48100000-0000-0000-0000-000000000002';
  client_a uuid := '48200000-0000-0000-0000-000000000001';
  client_b uuid := '48200000-0000-0000-0000-000000000002';
  matter_a uuid := '48300000-0000-0000-0000-000000000001';
  matter_b uuid := '48300000-0000-0000-0000-000000000002';
  asset_a uuid := '48400000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES
    ('00000000-0000-0000-0000-000000000000',user_a,'authenticated','authenticated','backfill-a@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',user_b,'authenticated','authenticated','backfill-b@example.test','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES (org_a,'Backfill A',user_a),(org_b,'Backfill B',user_b);
  INSERT INTO public.clients(id,org_id,name) VALUES(client_a,org_a,'Backfill client A'),(client_b,org_b,'Backfill client B');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES(matter_a,org_a,client_a,'Backfill matter A'),(matter_b,org_b,client_b,'Backfill matter B');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,created_by)
  VALUES(asset_a,org_a,'documents','orgs/'||org_a||'/assets/'||asset_a||'/original.pdf',repeat('a',64),11,'application/pdf','available',now(),user_a);
  INSERT INTO public.staged_documents(id,org_id,uploaded_by,storage_path,status,intake_matter_id,created_at) VALUES
    ('48500000-0000-0000-0000-000000000001',org_a,user_a,'staging/'||org_a||'/49000000-0000-0000-0000-000000000001/original.pdf','ready_to_assign',matter_a,now()),
    ('48500000-0000-0000-0000-000000000002',org_a,user_a,'staging/'||org_a||'/49000000-0000-0000-0000-000000000002/original.pdf','analyzing',NULL,now()+interval '1 second'),
    ('48500000-0000-0000-0000-000000000003',org_a,user_a,'staging/'||org_a||'/49000000-0000-0000-0000-000000000003/original.pdf','ready_to_assign',NULL,now()+interval '2 seconds'),
    ('48500000-0000-0000-0000-000000000004',org_a,user_a,'staging/'||org_a||'/49000000-0000-0000-0000-000000000004/original.pdf','failed',matter_b,now()+interval '3 seconds'),
    ('48500000-0000-0000-0000-000000000005',org_a,user_a,'staging/'||org_a||'/49000000-0000-0000-0000-000000000005/original.pdf','manually_assigned',NULL,now()+interval '4 seconds'),
    ('48500000-0000-0000-0000-000000000006',org_b,user_b,'staging/'||org_b||'/49000000-0000-0000-0000-000000000006/original.pdf','pending_assignment',matter_b,now()),
    ('48500000-0000-0000-0000-000000000007',org_a,user_a,'staging/'||org_b||'/49000000-0000-0000-0000-000000000007/original.pdf','pending_assignment',NULL,now()+interval '5 seconds'),
    ('48500000-0000-0000-0000-000000000008',org_a,user_a,'staging/'||org_a||'/../49000000-0000-0000-0000-000000000008/original.pdf','pending_assignment',NULL,now()+interval '6 seconds'),
    ('48500000-0000-0000-0000-000000000009',org_a,user_a,'staging/'||org_a||'/49000000-0000-0000-0000-000000000009/original.pdf','pending_assignment',NULL,now()+interval '7 seconds'),
    ('48500000-0000-0000-0000-000000000010',org_a,user_a,'staging/'||org_a||'/49000000-0000-0000-0000-000000000010/original.pdf','pending_assignment',NULL,now()+interval '8 seconds'),
    ('48500000-0000-0000-0000-000000000011',org_a,user_a,'staging/'||org_a||'/49000000-0000-0000-0000-000000000011/original.pdf','pending_assignment',NULL,now()+interval '9 seconds'),
    ('48500000-0000-0000-0000-000000000012',org_a,user_a,'staging/'||org_a||'/49000000-0000-0000-0000-000000000012/original.pdf','pending_assignment',NULL,now()+interval '10 seconds'),
    ('48500000-0000-0000-0000-000000000013',org_a,user_a,'staging/'||org_a||'/49000000-0000-0000-0000-000000000013/original.pdf','pending_assignment',NULL,now()+interval '11 seconds'),
    ('48500000-0000-0000-0000-000000000014',org_a,user_a,'staging/'||org_a||'/49000000-0000-0000-0000-000000000014/original.pdf','pending_assignment',NULL,now()+interval '12 seconds'),
    ('48500000-0000-0000-0000-000000000015',org_a,user_a,'staging/'||org_a||'/49000000-0000-0000-0000-000000000015/original.pdf','ready_to_assign',NULL,now()+interval '13 seconds');
END $setup$;

SET LOCAL ROLE service_role;
DO $service$
DECLARE
  claimed record;
  source_grant record;
  present_lease uuid;
  missing_lease uuid;
  duplicate_lease uuid;
  unreadable_lease uuid;
  malformed_lease uuid;
  encrypted_lease uuid;
  non_pdf_lease uuid;
  oversize_lease uuid;
  valid_but_oversize_lease uuid;
  action_lease uuid;
  org_b_lease uuid;
  transfer_lease uuid;
  org_b_transfer_lease uuid;
  present_asset uuid;
  org_b_transfer_asset uuid;
  org_b_duplicate_asset uuid := '48400000-0000-0000-0000-000000000002';
  present_intake uuid;
  result record;
  report_a public.staged_document_backfill_reports%ROWTYPE;
  report_b public.staged_document_backfill_reports%ROWTYPE;
  source_digest_before text;
  source_digest_after text;
  documents_before bigint;
  direct_dml_denied boolean := false;
  legacy_update_denied boolean := false;
  legacy_delete_denied boolean := false;
  action_source_claimed boolean := false;
BEGIN
  SELECT md5(string_agg(id::text || ':' || status::text || ':' || storage_path, ',' ORDER BY id))
  INTO source_digest_before
  FROM public.staged_documents
  WHERE org_id = '48000000-0000-0000-0000-000000000001';
  SELECT count(*) INTO documents_before FROM public.documents WHERE org_id='48000000-0000-0000-0000-000000000001';

  BEGIN
    INSERT INTO public.staged_document_backfill_items(org_id,legacy_staged_document_id,safe_item_key)
    VALUES ('48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001','legacy-staged/48500000-0000-0000-0000-000000000001');
  EXCEPTION WHEN insufficient_privilege THEN direct_dml_denied := true;
  END;
  IF NOT direct_dml_denied THEN RAISE EXCEPTION 'service direct backfill mapping DML allowed'; END IF;
  -- An action lease is an atomic source-row reservation. While it is held,
  -- a backfill claim cannot create the map that would race a Storage delete.
  SELECT * INTO result FROM public.reserve_legacy_staged_document_action(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000015','discard');
  IF result.code <> 'ok' OR result.lease_token IS NULL THEN RAISE EXCEPTION 'legacy action reservation was not granted'; END IF;
  action_lease := result.lease_token;
  SELECT * INTO source_grant FROM public.get_legacy_staged_document_action_source_grant(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000015',action_lease,'discard');
  IF source_grant.code <> 'ok' OR source_grant.object_key <> 'staging/48000000-0000-0000-0000-000000000001/49000000-0000-0000-0000-000000000015/original.pdf' THEN
    RAISE EXCEPTION 'action source grant did not bind the reserved source path';
  END IF;
  BEGIN
    PERFORM * FROM public.claim_staged_document_backfill_batch('48000000-0000-0000-0000-000000000001', 101);
    RAISE EXCEPTION 'backfill batch size was not rate limited';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'invalid staged-document backfill batch request' THEN RAISE; END IF;
  END;

  FOR claimed IN
    SELECT * FROM public.claim_staged_document_backfill_batch('48000000-0000-0000-0000-000000000001', 100)
  LOOP
    IF claimed.safe_item_key <> 'legacy-staged/' || claimed.legacy_staged_document_id::text THEN
      RAISE EXCEPTION 'claim exposed an unsafe item key';
    END IF;
    CASE claimed.legacy_staged_document_id
      WHEN '48500000-0000-0000-0000-000000000015'::uuid THEN action_source_claimed := true;
      WHEN '48500000-0000-0000-0000-000000000001'::uuid THEN present_lease := claimed.verification_lease_token;
      WHEN '48500000-0000-0000-0000-000000000002'::uuid THEN missing_lease := claimed.verification_lease_token;
      WHEN '48500000-0000-0000-0000-000000000003'::uuid THEN duplicate_lease := claimed.verification_lease_token;
      WHEN '48500000-0000-0000-0000-000000000009'::uuid THEN unreadable_lease := claimed.verification_lease_token;
      WHEN '48500000-0000-0000-0000-000000000010'::uuid THEN malformed_lease := claimed.verification_lease_token;
      WHEN '48500000-0000-0000-0000-000000000011'::uuid THEN encrypted_lease := claimed.verification_lease_token;
      WHEN '48500000-0000-0000-0000-000000000012'::uuid THEN non_pdf_lease := claimed.verification_lease_token;
      WHEN '48500000-0000-0000-0000-000000000013'::uuid THEN oversize_lease := claimed.verification_lease_token;
      WHEN '48500000-0000-0000-0000-000000000014'::uuid THEN valid_but_oversize_lease := claimed.verification_lease_token;
      WHEN '48500000-0000-0000-0000-000000000004'::uuid,
           '48500000-0000-0000-0000-000000000007'::uuid,
           '48500000-0000-0000-0000-000000000008'::uuid THEN
        IF claimed.code <> 'invalid_lineage' OR claimed.verification_lease_token IS NOT NULL THEN
          RAISE EXCEPTION 'malformed, traversal, or foreign staging path was not terminally classified';
        END IF;
      WHEN '48500000-0000-0000-0000-000000000005'::uuid THEN
        IF claimed.code <> 'already_migrated' OR claimed.verification_lease_token IS NOT NULL THEN
          RAISE EXCEPTION 'legacy assigned source was not terminally classified';
        END IF;
    END CASE;
  END LOOP;
  IF action_source_claimed THEN RAISE EXCEPTION 'backfill claimed a legacy row during its action lease'; END IF;
  IF present_lease IS NULL OR missing_lease IS NULL OR duplicate_lease IS NULL
     OR unreadable_lease IS NULL OR malformed_lease IS NULL OR encrypted_lease IS NULL
     OR non_pdf_lease IS NULL OR oversize_lease IS NULL OR valid_but_oversize_lease IS NULL THEN
    RAISE EXCEPTION 'safe active staged sources were not claimed for external verification';
  END IF;
  SELECT * INTO source_grant FROM public.get_staged_document_backfill_source_grant(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001',present_lease);
  IF source_grant.code <> 'ok' OR source_grant.bucket_id <> 'staging'
     OR source_grant.object_key <> 'staging/48000000-0000-0000-0000-000000000001/49000000-0000-0000-0000-000000000001/original.pdf' THEN
    RAISE EXCEPTION 'worker source grant did not enforce the exact legacy namespace';
  END IF;
  SELECT * INTO source_grant FROM public.get_staged_document_backfill_source_grant(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000007',gen_random_uuid());
  IF source_grant.code <> 'invalid_lineage' OR source_grant.object_key IS NOT NULL THEN
    RAISE EXCEPTION 'foreign tenant prefix reached worker source grant';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.staged_document_backfill_reports
    WHERE org_id='48000000-0000-0000-0000-000000000001'
      AND verification_required_count=9 AND missing_object_count=0
      AND staging_retirement_ready=false
  ) THEN RAISE EXCEPTION 'database incorrectly classified Storage before worker verification'; END IF;

  SELECT * INTO result FROM public.record_staged_document_backfill_verification(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001',present_lease,'valid_pdf',12,repeat('b',64));
  IF result.code <> 'transfer_pending' OR result.asset_id IS NULL OR result.intake_item_id IS NOT NULL THEN
    RAISE EXCEPTION 'validated source did not become mapping-only transfer-pending asset';
  END IF;
  present_asset := result.asset_id;
  IF NOT EXISTS (
    SELECT 1 FROM public.file_assets AS asset
    WHERE asset.id=present_asset AND asset.org_id='48000000-0000-0000-0000-000000000001'
      AND asset.legacy_staged_backfill_pending AND asset.availability='quarantined'
      AND asset.sha256 IS NULL AND asset.byte_size IS NULL
  ) OR EXISTS (SELECT 1 FROM public.intake_items WHERE asset_id=present_asset) THEN
    RAISE EXCEPTION 'pre-transfer source created runnable Intake or lost its quarantine fence';
  END IF;
  IF EXISTS (SELECT 1 FROM public.claim_document_asset_storage_deletion_work(100) WHERE asset_id = present_asset) THEN
    RAISE EXCEPTION 'unmoved backfill asset entered terminal storage cleanup'; END IF;
  SELECT * INTO result FROM public.get_staged_document_backfill_action_guard(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001');
  IF result.code <> 'backfill_fenced' OR NOT EXISTS (
    SELECT 1 FROM public.get_staged_document_backfill_adapter_fences('48000000-0000-0000-0000-000000000001')
    WHERE legacy_staged_document_id='48500000-0000-0000-0000-000000000001'::uuid
  ) THEN RAISE EXCEPTION 'mapped ready legacy source remained in legacy action surface'; END IF;
  SELECT * INTO result FROM public.reserve_legacy_staged_document_action(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001','assign');
  IF result.code <> 'backfill_fenced' THEN RAISE EXCEPTION 'mapped legacy source could reserve a legacy action'; END IF;
  SELECT * INTO source_grant FROM public.get_legacy_staged_document_read_grant(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001');
  IF source_grant.code <> 'backfill_fenced' OR source_grant.object_key IS NOT NULL THEN
    RAISE EXCEPTION 'mapped legacy source could receive a presentation path';
  END IF;
  BEGIN
    UPDATE public.staged_documents SET status='manually_assigned' WHERE id='48500000-0000-0000-0000-000000000001';
  EXCEPTION WHEN raise_exception THEN legacy_update_denied := true;
  END;
  BEGIN
    DELETE FROM public.staged_documents WHERE id='48500000-0000-0000-0000-000000000001';
  EXCEPTION WHEN raise_exception THEN legacy_delete_denied := true;
  END;
  IF NOT legacy_update_denied OR NOT legacy_delete_denied
     OR (SELECT count(*) FROM public.documents WHERE org_id='48000000-0000-0000-0000-000000000001') <> documents_before THEN
    RAISE EXCEPTION 'mapped ready legacy source could update, delete, or create a legacy copy';
  END IF;
  SELECT * INTO result FROM public.record_staged_document_backfill_verification(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001',present_lease,'valid_pdf',12,repeat('b',64));
  IF result.code <> 'already_migrated' THEN RAISE EXCEPTION 'repeated verified source was not idempotent'; END IF;

  SELECT * INTO result FROM public.record_staged_document_backfill_verification(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000002',missing_lease,'missing');
  IF result.code <> 'missing_object' THEN RAISE EXCEPTION 'missing source was not terminally classified'; END IF;
  SELECT * INTO result FROM public.record_staged_document_backfill_verification(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000003',duplicate_lease,'valid_pdf',11,repeat('a',64));
  IF result.code <> 'duplicate_reference' OR result.asset_id <> '48400000-0000-0000-0000-000000000001'::uuid THEN
    RAISE EXCEPTION 'same-org checksum was not recorded as duplicate reference'; END IF;
  SELECT * INTO result FROM public.record_staged_document_backfill_verification(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000009',unreadable_lease,'unreadable');
  IF result.code <> 'unreadable_source' THEN RAISE EXCEPTION 'unreadable source was not distinguished'; END IF;
  SELECT * INTO result FROM public.record_staged_document_backfill_verification(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000010',malformed_lease,'malformed_pdf');
  IF result.code <> 'malformed_pdf' THEN RAISE EXCEPTION 'malformed PDF was not distinguished'; END IF;
  SELECT * INTO result FROM public.record_staged_document_backfill_verification(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000011',encrypted_lease,'encrypted_pdf');
  IF result.code <> 'encrypted_pdf' THEN RAISE EXCEPTION 'encrypted PDF was not distinguished'; END IF;
  SELECT * INTO result FROM public.record_staged_document_backfill_verification(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000012',non_pdf_lease,'non_pdf');
  IF result.code <> 'non_pdf' THEN RAISE EXCEPTION 'non-PDF source was not distinguished'; END IF;
  SELECT * INTO result FROM public.record_staged_document_backfill_verification(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000013',oversize_lease,'oversize');
  IF result.code <> 'oversize' THEN RAISE EXCEPTION 'worker-reported oversize source was not distinguished'; END IF;
  SELECT * INTO result FROM public.record_staged_document_backfill_verification(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000014',valid_but_oversize_lease,'valid_pdf',26214401,repeat('c',64));
  IF result.code <> 'oversize' THEN RAISE EXCEPTION 'bounded PDF observation created an unsafe canonical asset'; END IF;

  SELECT * INTO result FROM public.record_staged_document_backfill_verification(
    '48000000-0000-0000-0000-000000000002','48500000-0000-0000-0000-000000000001',present_lease,'valid_pdf',12,repeat('b',64));
  IF result.code <> 'not_found' THEN RAISE EXCEPTION 'cross-org verification could address another tenant mapping'; END IF;
  FOR claimed IN SELECT * FROM public.claim_staged_document_backfill_batch('48000000-0000-0000-0000-000000000002', 10) LOOP
    org_b_lease := claimed.verification_lease_token;
  END LOOP;
  IF org_b_lease IS NULL THEN RAISE EXCEPTION 'other tenant source was not independently claimable'; END IF;
  SELECT * INTO result FROM public.record_staged_document_backfill_verification(
    '48000000-0000-0000-0000-000000000002','48500000-0000-0000-0000-000000000006',org_b_lease,'valid_pdf',11,repeat('a',64));
  IF result.code <> 'transfer_pending' OR result.asset_id IS NULL THEN
    RAISE EXCEPTION 'cross-tenant bytes were incorrectly deduplicated'; END IF;
  org_b_transfer_asset := result.asset_id;

  SELECT * INTO result FROM public.release_legacy_staged_document_action(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000015',action_lease);
  IF result.code <> 'ok' THEN RAISE EXCEPTION 'legacy action lease did not release'; END IF;
  SELECT * INTO result FROM public.claim_staged_document_backfill_batch(
    '48000000-0000-0000-0000-000000000001', 1);
  IF result.legacy_staged_document_id <> '48500000-0000-0000-0000-000000000015'::uuid OR result.code <> 'verification_required'
     OR result.verification_lease_token IS NULL THEN
    RAISE EXCEPTION 'released ready-to-assign action source was not immediately claimable by backfill';
  END IF;
  SELECT * INTO result FROM public.record_staged_document_backfill_verification(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000015',result.verification_lease_token,'missing');
  IF result.code <> 'missing_object' THEN RAISE EXCEPTION 'released ready-to-assign source did not complete normally'; END IF;

  BEGIN
    PERFORM * FROM public.claim_staged_document_backfill_transfer_batch('48000000-0000-0000-0000-000000000001', 26);
    RAISE EXCEPTION 'transfer batch size was not rate limited';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'invalid staged-document backfill transfer batch request' THEN RAISE; END IF;
  END;
  SELECT * INTO result FROM public.claim_staged_document_backfill_transfer_batch(
    '48000000-0000-0000-0000-000000000001', 1);
  IF result.code <> 'transfer_pending' OR result.legacy_staged_document_id <> '48500000-0000-0000-0000-000000000001'::uuid
     OR result.transfer_lease_token IS NULL THEN
    RAISE EXCEPTION 'transfer-pending map was not leased as bounded opaque work';
  END IF;
  transfer_lease := result.transfer_lease_token;
  SELECT * INTO source_grant FROM public.get_staged_document_backfill_transfer_grant(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001',transfer_lease);
  IF source_grant.code <> 'ok' OR source_grant.source_bucket_id <> 'staging'
     OR source_grant.source_object_key <> 'staging/48000000-0000-0000-0000-000000000001/49000000-0000-0000-0000-000000000001/original.pdf'
     OR source_grant.destination_bucket_id <> 'documents'
     OR source_grant.destination_object_key <> 'orgs/48000000-0000-0000-0000-000000000001/assets/' || present_asset::text || '/original.pdf'
     OR source_grant.expected_byte_size <> 12 OR source_grant.expected_sha256 <> repeat('b',64) THEN
    RAISE EXCEPTION 'transfer grant did not bind fresh source and predetermined destination';
  END IF;
  SELECT * INTO result FROM public.complete_staged_document_backfill_transfer(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001',transfer_lease,
    12,repeat('b',64),1,11,repeat('b',64));
  IF result.code <> 'destination_observation_conflict' THEN
    RAISE EXCEPTION 'mismatched destination was allowed to clear the staging fence';
  END IF;
  SELECT * INTO result FROM public.complete_staged_document_backfill_transfer(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001',transfer_lease,
    12,repeat('b',64),1,12,repeat('b',64));
  IF result.code <> 'transferred' OR result.asset_id <> present_asset OR result.intake_item_id IS NULL THEN
    RAISE EXCEPTION 'verified destination did not atomically create canonical Intake';
  END IF;
  present_intake := result.intake_item_id;
  IF NOT EXISTS (
    SELECT 1 FROM public.file_assets AS asset
    JOIN public.intake_items AS intake ON intake.asset_id=asset.id AND intake.org_id=asset.org_id
    WHERE asset.id=present_asset AND asset.org_id='48000000-0000-0000-0000-000000000001'
      AND asset.bucket_id='documents' AND asset.availability='available'
      AND NOT asset.legacy_staged_backfill_pending AND asset.sha256=repeat('b',64)
      AND asset.byte_size=12 AND asset.validated_page_count=1
      AND intake.id=present_intake AND intake.state='ready'
      AND intake.intended_matter_id='48300000-0000-0000-0000-000000000001'::uuid
  ) THEN RAISE EXCEPTION 'canonical Intake asset facts or context were not preserved'; END IF;
  SELECT * INTO result FROM public.complete_staged_document_backfill_transfer(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001',transfer_lease,
    12,repeat('b',64),1,12,repeat('b',64));
  IF result.code <> 'already_transferred' OR result.intake_item_id <> present_intake THEN
    RAISE EXCEPTION 'completed transfer was not idempotent';
  END IF;
  SELECT * INTO result FROM public.claim_staged_document_backfill_transfer_batch(
    '48000000-0000-0000-0000-000000000002', 1);
  IF result.code <> 'transfer_pending' OR result.legacy_staged_document_id <> '48500000-0000-0000-0000-000000000006'::uuid
     OR result.transfer_lease_token IS NULL THEN RAISE EXCEPTION 'other tenant transfer was not independently claimable'; END IF;
  org_b_transfer_lease := result.transfer_lease_token;
  SELECT * INTO result FROM public.complete_staged_document_backfill_transfer(
    '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000006',org_b_transfer_lease,
    11,repeat('a',64),1,11,repeat('a',64));
  IF result.code <> 'not_found' THEN RAISE EXCEPTION 'cross-org transfer could address another tenant mapping'; END IF;
  -- Reproduce a same-org upload completing after verification but before
  -- transfer finalisation. This must be terminal duplicate reference work,
  -- not a retry loop, and it must retain both copied and staging bytes.
  INSERT INTO public.file_assets(
    id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,created_by
  ) VALUES (
    org_b_duplicate_asset,'48000000-0000-0000-0000-000000000002','documents',
    'orgs/48000000-0000-0000-0000-000000000002/assets/' || org_b_duplicate_asset::text || '/original.pdf',
    repeat('a',64),11,'application/pdf','available',now(),'48100000-0000-0000-0000-000000000002'
  );
  SELECT * INTO result FROM public.complete_staged_document_backfill_transfer(
    '48000000-0000-0000-0000-000000000002','48500000-0000-0000-0000-000000000006',org_b_transfer_lease,
    11,repeat('a',64),1,11,repeat('a',64));
  IF result.code <> 'duplicate_reference' OR result.asset_id <> org_b_duplicate_asset OR result.intake_item_id IS NOT NULL THEN
    RAISE EXCEPTION 'post-verification same-org duplicate did not terminally resolve'; END IF;
  SELECT * INTO source_grant FROM public.get_staged_document_backfill_transfer_grant(
    '48000000-0000-0000-0000-000000000002','48500000-0000-0000-0000-000000000006',org_b_transfer_lease);
  IF source_grant.code <> 'duplicate_reference' OR source_grant.source_object_key IS NOT NULL
     OR source_grant.destination_object_key IS NOT NULL THEN
    RAISE EXCEPTION 'post-verification duplicate map was not terminal and fenced'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.file_assets AS asset
    WHERE asset.id=org_b_transfer_asset AND asset.org_id='48000000-0000-0000-0000-000000000002'
      AND asset.legacy_staged_backfill_pending AND asset.availability='quarantined'
      AND asset.storage_deleted_at IS NULL
  ) OR EXISTS (SELECT 1 FROM public.intake_items WHERE asset_id=org_b_transfer_asset) THEN
    RAISE EXCEPTION 'duplicate race deleted or materialised the copied canonical asset'; END IF;
  IF EXISTS (SELECT 1 FROM public.claim_staged_document_backfill_transfer_batch('48000000-0000-0000-0000-000000000002', 1)) THEN
    RAISE EXCEPTION 'terminal duplicate transfer was reclaimed'; END IF;
  SELECT * INTO result FROM public.complete_staged_document_backfill_transfer(
    '48000000-0000-0000-0000-000000000002','48500000-0000-0000-0000-000000000006',org_b_transfer_lease,
    11,repeat('a',64),1,11,repeat('a',64));
  IF result.code <> 'duplicate_reference' OR result.asset_id <> org_b_duplicate_asset THEN
    RAISE EXCEPTION 'terminal duplicate transfer was not idempotent'; END IF;

  IF EXISTS (SELECT 1 FROM public.claim_staged_document_backfill_batch('48000000-0000-0000-0000-000000000001', 100)) THEN
    RAISE EXCEPTION 'completed backfill batch was not resumably idempotent'; END IF;
  SELECT * INTO report_a FROM public.staged_document_backfill_reports WHERE org_id='48000000-0000-0000-0000-000000000001';
  IF report_a.legacy_source_count <> 14 OR report_a.active_source_count <> 13
     OR report_a.unmapped_source_count <> 0 OR report_a.verification_required_count <> 0
     OR report_a.transfer_pending_count <> 0 OR report_a.transfer_completed_count <> 1 OR report_a.missing_object_count <> 2
     OR report_a.unreadable_source_count <> 1 OR report_a.malformed_pdf_count <> 1
     OR report_a.encrypted_pdf_count <> 1 OR report_a.non_pdf_count <> 1 OR report_a.oversize_count <> 2
     OR report_a.invalid_lineage_count <> 3 OR report_a.duplicate_reference_count <> 1
     OR report_a.already_migrated_count <> 1 OR NOT report_a.classification_complete
     OR report_a.staging_retirement_ready THEN RAISE EXCEPTION 'backfill count/report contract failed'; END IF;
  SELECT * INTO report_b FROM public.staged_document_backfill_reports WHERE org_id='48000000-0000-0000-0000-000000000002';
  IF report_b.transfer_pending_count <> 0 OR report_b.duplicate_reference_count <> 1 OR NOT report_b.classification_complete THEN
    RAISE EXCEPTION 'other tenant report was not isolated'; END IF;
  IF EXISTS (SELECT 1 FROM public.staged_document_backfill_diagnostics) THEN RAISE EXCEPTION 'backfill diagnostics are not clean'; END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='staged_document_backfill_diagnostics'
      AND column_name IN ('storage_path','object_key','raw_metadata','filename','content','legacy_staged_document_id','safe_item_key','sha256','byte_size')
  ) THEN RAISE EXCEPTION 'diagnostics expose legal source data'; END IF;

  SELECT md5(string_agg(id::text || ':' || status::text || ':' || storage_path, ',' ORDER BY id))
  INTO source_digest_after FROM public.staged_documents
  WHERE org_id = '48000000-0000-0000-0000-000000000001';
  IF source_digest_after IS DISTINCT FROM source_digest_before THEN RAISE EXCEPTION 'backfill altered a legacy staged source row'; END IF;
END $service$;
RESET ROLE;

SET LOCAL ROLE authenticated;
DO $browser$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    PERFORM * FROM public.claim_staged_document_backfill_batch('48000000-0000-0000-0000-000000000001', 1);
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'browser could execute service-only backfill command'; END IF;
  denied := false;
  BEGIN
    PERFORM * FROM public.claim_staged_document_backfill_transfer_batch('48000000-0000-0000-0000-000000000001', 1);
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'browser could execute service-only transfer claim'; END IF;
  denied := false;
  BEGIN
    PERFORM * FROM public.get_staged_document_backfill_transfer_grant(
      '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001',gen_random_uuid());
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'browser could obtain a controlled transfer storage grant'; END IF;
  denied := false;
  BEGIN
    PERFORM * FROM public.complete_staged_document_backfill_transfer(
      '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001',gen_random_uuid(),12,repeat('b',64),1,12,repeat('b',64));
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'browser could finalise a controlled transfer'; END IF;
  denied := false;
  BEGIN
    PERFORM * FROM public.get_staged_document_backfill_source_grant('48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001',gen_random_uuid());
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'browser could obtain a legacy storage path'; END IF;
  denied := false;
  BEGIN
    PERFORM * FROM public.reserve_legacy_staged_document_action(
      '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001','assign');
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'browser could reserve a legacy Storage action'; END IF;
  denied := false;
  BEGIN
    PERFORM * FROM public.get_legacy_staged_document_read_grant(
      '48000000-0000-0000-0000-000000000001','48500000-0000-0000-0000-000000000001');
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'browser could obtain a legacy presentation path'; END IF;
  denied := false;
  BEGIN
    PERFORM 1 FROM public.staged_document_backfill_reports;
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'browser could read service-only backfill report'; END IF;
END $browser$;
RESET ROLE;

ROLLBACK;
