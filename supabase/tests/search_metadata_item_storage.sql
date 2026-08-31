-- Run after migration 00097 against a disposable local Supabase database.
-- This is intentionally a rollback fixture: it leaves no rows behind.
BEGIN;

DO $setup$
DECLARE
  owner_id uuid := '97100000-0000-0000-0000-000000000001';
  foreign_owner_id uuid := '97100000-0000-0000-0000-000000000002';
  org_id uuid := '97200000-0000-0000-0000-000000000001';
  foreign_org_id uuid := '97200000-0000-0000-0000-000000000002';
  client_id uuid := '97300000-0000-0000-0000-000000000001';
  replacement_client_id uuid := '97300000-0000-0000-0000-000000000002';
  foreign_client_id uuid := '97300000-0000-0000-0000-000000000003';
  matter_id uuid := '97400000-0000-0000-0000-000000000001';
  asset_id uuid := '97500000-0000-0000-0000-000000000001';
  document_id uuid := '97600000-0000-0000-0000-000000000001';
  version_id uuid := '97700000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES
    ('00000000-0000-0000-0000-000000000000',owner_id,'authenticated','authenticated','search-item-owner@test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',foreign_owner_id,'authenticated','authenticated','search-item-foreign@test','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES
    (org_id,'Search metadata fixture',owner_id),
    (foreign_org_id,'Foreign search metadata fixture',foreign_owner_id);
  INSERT INTO public.clients(id,org_id,name) VALUES
    (client_id,org_id,'Fixture client'),
    (replacement_client_id,org_id,'Reassigned fixture client'),
    (foreign_client_id,foreign_org_id,'Foreign fixture client');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES(matter_id,org_id,client_id,'Fixture matter');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
  VALUES(asset_id,org_id,'documents','orgs/'||org_id||'/assets/'||asset_id||'/original.pdf',10,'application/pdf','available',now(),1,owner_id);
  INSERT INTO public.documents(id,org_id,matter_id,display_title,origin_kind,record_state,content_availability,status,doc_type,reference_number,summary,financial_year,issued_by,created_by)
  VALUES(document_id,org_id,matter_id,'Safe metadata document','upload','active','source_attached','placed','SCN','SAFE/1','Never store this summary in search item metadata.','2024-25','Fixture authority',owner_id);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
  VALUES(version_id,org_id,document_id,asset_id,1,'fixture.pdf',1,'valid','current',now(),now(),owner_id);
  UPDATE public.documents SET current_version_id=version_id WHERE id=document_id;
END $setup$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','97100000-0000-0000-0000-000000000001',true);
DO $request$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.request_document_reprocess(
    '97600000-0000-0000-0000-000000000001','search_index',
    '97800000-0000-0000-0000-000000000001',8
  );
  IF result.code <> 'queued' THEN RAISE EXCEPTION 'metadata search fixture was not queued: %', result.code; END IF;
  PERFORM set_config('test.search_metadata_event',result.outbox_event_id::text,true);
END $request$;
RESET ROLE;

UPDATE public.outbox_events
SET delivery_state='leased',lease_token='97900000-0000-0000-0000-000000000001',
    lease_expires_at=now()+interval '2 minutes',delivered_at=NULL,failed_at=NULL
WHERE id=current_setting('test.search_metadata_event')::uuid;

SET LOCAL ROLE service_role;
DO $leased_completion$
DECLARE claim record; input_row record; completion record; replay record;
BEGIN
  SELECT * INTO claim FROM public.claim_document_search_index_reprocess_work(
    current_setting('test.search_metadata_event')::uuid,'search-metadata-storage-test',
    '97200000-0000-0000-0000-000000000001','97900000-0000-0000-0000-000000000001'
  );
  SELECT * INTO input_row FROM public.get_document_search_index_reprocess_input(claim.processing_run_id,claim.lease_token);
  SELECT * INTO completion FROM public.finish_document_search_index_reprocess_work(
    claim.processing_run_id,claim.lease_token,'indexed',
    ('['||repeat('0,',767)||'0]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7,input_row.projection_fingerprint
  );
  SELECT * INTO replay FROM public.finish_document_search_index_reprocess_work(
    claim.processing_run_id,claim.lease_token,'indexed',
    ('['||repeat('0,',767)||'0]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7,input_row.projection_fingerprint
  );
  IF claim.code <> 'claimed' OR input_row.code <> 'ready'
     OR completion.code <> 'indexed' OR replay.code <> 'already_complete' THEN
    RAISE EXCEPTION 'leased metadata Search completion did not preserve its existing fence';
  END IF;
  PERFORM set_config('test.search_metadata_run',claim.processing_run_id::text,true);
  PERFORM set_config('test.search_metadata_fingerprint',input_row.projection_fingerprint,true);
END $leased_completion$;
RESET ROLE;

DO $initial_inspection$
BEGIN
  IF (SELECT count(*) FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001') <> 1
     OR (SELECT count(*) FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') <> 1
     OR (SELECT content_fingerprint FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001')
        <> current_setting('test.search_metadata_fingerprint')
     OR (SELECT state FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') <> 'indexed'
     OR (SELECT attempt_count FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') <> 1
     OR (SELECT metadata ? 'summary' OR metadata ? 'storage_path' OR metadata ? 'embedding'
         FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001')
     OR (SELECT metadata ->> 'reference_number' FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001') <> 'SAFE/1'
     OR (SELECT metadata -> 'financial_years' FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001') <> '["2024-25"]'::jsonb
     OR EXISTS (
       SELECT 1
       FROM information_schema.columns
       WHERE table_schema='public' AND table_name IN ('search_items','search_index_runs')
         AND column_name IN ('embedding','raw_metadata','storage_path','object_key','signed_url','provider_payload','query_text')
     ) THEN
    RAISE EXCEPTION 'current metadata item/run is incomplete, unsafe, or duplicated';
  END IF;
END $initial_inspection$;

-- A later provider failure must record safe operational state without
-- breaking the existing current item/run relationship.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','97100000-0000-0000-0000-000000000001',true);
DO $failed_retry_request$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.request_document_reprocess(
    '97600000-0000-0000-0000-000000000001','search_index',
    '97800000-0000-0000-0000-000000000003',8
  );
  IF result.code <> 'queued' THEN RAISE EXCEPTION 'failed retry fixture was not queued: %', result.code; END IF;
  PERFORM set_config('test.search_metadata_failed_event',result.outbox_event_id::text,true);
END $failed_retry_request$;
RESET ROLE;

UPDATE public.outbox_events
SET delivery_state='leased',lease_token='97900000-0000-0000-0000-000000000003',
    lease_expires_at=now()+interval '2 minutes',delivered_at=NULL,failed_at=NULL
WHERE id=current_setting('test.search_metadata_failed_event')::uuid;

SET LOCAL ROLE service_role;
DO $failed_retry_completion$
DECLARE claim record; result record;
BEGIN
  SELECT * INTO claim FROM public.claim_document_search_index_reprocess_work(
    current_setting('test.search_metadata_failed_event')::uuid,'search-metadata-failed-test',
    '97200000-0000-0000-0000-000000000001','97900000-0000-0000-0000-000000000003'
  );
  SELECT * INTO result FROM public.finish_document_search_index_reprocess_work(
    claim.processing_run_id,claim.lease_token,'failed',NULL,NULL,NULL,NULL,NULL
  );
  IF claim.code <> 'claimed' OR result.code <> 'failed' THEN
    RAISE EXCEPTION 'failed retry completion was not recorded safely';
  END IF;
END $failed_retry_completion$;
RESET ROLE;

DO $failed_retry_inspection$
DECLARE item_id uuid;
BEGIN
  SELECT id INTO item_id FROM public.search_items
  WHERE document_id='97600000-0000-0000-0000-000000000001';
  IF item_id IS NULL
     OR (SELECT count(*) FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001') <> 1
     OR (SELECT search_item_id FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') IS DISTINCT FROM item_id
     OR (SELECT state FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') <> 'failed'
     OR (SELECT safe_error_code FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') <> 'search_index_failed'
     OR (SELECT started_at IS NULL OR failed_at IS NULL OR completed_at IS NOT NULL
         FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'failed retry broke current Search item/run linkage or timestamps';
  END IF;
END $failed_retry_inspection$;

-- Valid same-org reparenting removes every affected document projection
-- before a current writer rebuilds it with the replacement client lineage.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','97100000-0000-0000-0000-000000000001',true);
UPDATE public.matters SET client_id='97300000-0000-0000-0000-000000000002'
WHERE id='97400000-0000-0000-0000-000000000001';
RESET ROLE;

DO $same_org_reparent_withdrawal$
BEGIN
  IF (SELECT client_id FROM public.matters WHERE id='97400000-0000-0000-0000-000000000001')
       <> '97300000-0000-0000-0000-000000000002'::uuid
     OR EXISTS (SELECT 1 FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001')
     OR EXISTS (SELECT 1 FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'same-org matter reparent retained stale private Search lineage';
  END IF;
END $same_org_reparent_withdrawal$;

SET LOCAL ROLE service_role;
DO $same_org_reparent_current_writer$
DECLARE projection_row record; result record;
BEGIN
  SELECT * INTO projection_row FROM public.read_current_document_search_index_projection(
    '97200000-0000-0000-0000-000000000001',ARRAY['97600000-0000-0000-0000-000000000001'::uuid]
  );
  SELECT * INTO result FROM public.write_current_document_search_index_embedding(
    '97200000-0000-0000-0000-000000000001','97600000-0000-0000-0000-000000000001',projection_row.document_version_id,
    ('['||repeat('0,',767)||'0]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7,projection_row.projection_fingerprint
  );
  IF result.code <> 'indexed' THEN RAISE EXCEPTION 'same-org reparent current writer was not accepted'; END IF;
END $same_org_reparent_current_writer$;
RESET ROLE;

DO $same_org_reparent_recreated$
BEGIN
  IF (SELECT client_id FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001')
       <> '97300000-0000-0000-0000-000000000002'::uuid
     OR (SELECT count(*) FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') <> 1 THEN
    RAISE EXCEPTION 'same-org reparent did not rebuild correct private Search lineage';
  END IF;
END $same_org_reparent_recreated$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','97100000-0000-0000-0000-000000000001',true);
DO $cross_org_reparent_denied$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    UPDATE public.matters SET client_id='97300000-0000-0000-0000-000000000003'
    WHERE id='97400000-0000-0000-0000-000000000001';
  EXCEPTION WHEN raise_exception THEN
    denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'cross-org matter client assignment was accepted'; END IF;
END $cross_org_reparent_denied$;
RESET ROLE;

DO $cross_org_reparent_inspection$
BEGIN
  IF (SELECT client_id FROM public.matters WHERE id='97400000-0000-0000-0000-000000000001')
       <> '97300000-0000-0000-0000-000000000002'::uuid
     OR (SELECT client_id FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001')
       <> '97300000-0000-0000-0000-000000000002'::uuid THEN
    RAISE EXCEPTION 'cross-org reparent changed matter or private Search lineage';
  END IF;
END $cross_org_reparent_inspection$;

-- A forged tenant/document writer cannot create a second item or run.
SET LOCAL ROLE service_role;
DO $forged_writer$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.write_current_document_search_index_embedding(
    '97200000-0000-0000-0000-000000000002',
    '97600000-0000-0000-0000-000000000001',
    '97700000-0000-0000-0000-000000000001',
    ('['||repeat('0,',767)||'0]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7,current_setting('test.search_metadata_fingerprint')
  );
  IF result.code <> 'version_not_current' THEN
    RAISE EXCEPTION 'forged organisation was accepted by the current metadata writer';
  END IF;
END $forged_writer$;
RESET ROLE;

-- Projection drift cancels the leased completion before either private table
-- changes. A subsequent current direct writer updates the one stable row.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','97100000-0000-0000-0000-000000000001',true);
DO $stale_request$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.request_document_reprocess(
    '97600000-0000-0000-0000-000000000001','search_index',
    '97800000-0000-0000-0000-000000000002',8
  );
  IF result.code <> 'queued' THEN RAISE EXCEPTION 'stale metadata fixture was not queued: %', result.code; END IF;
  PERFORM set_config('test.search_metadata_stale_event',result.outbox_event_id::text,true);
END $stale_request$;
RESET ROLE;

UPDATE public.outbox_events
SET delivery_state='leased',lease_token='97900000-0000-0000-0000-000000000002',
    lease_expires_at=now()+interval '2 minutes',delivered_at=NULL,failed_at=NULL
WHERE id=current_setting('test.search_metadata_stale_event')::uuid;

SET LOCAL ROLE service_role;
DO $stale_projection$
DECLARE claim record; input_row record; result record;
BEGIN
  SELECT * INTO claim FROM public.claim_document_search_index_reprocess_work(
    current_setting('test.search_metadata_stale_event')::uuid,'search-metadata-stale-test',
    '97200000-0000-0000-0000-000000000001','97900000-0000-0000-0000-000000000002'
  );
  SELECT * INTO input_row FROM public.get_document_search_index_reprocess_input(claim.processing_run_id,claim.lease_token);
  UPDATE public.documents SET reference_number='SAFE/2' WHERE id='97600000-0000-0000-0000-000000000001';
  SELECT * INTO result FROM public.finish_document_search_index_reprocess_work(
    claim.processing_run_id,claim.lease_token,'indexed',
    ('['||repeat('0,',767)||'0]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7,input_row.projection_fingerprint
  );
  PERFORM set_config('test.search_metadata_stale_result',result.code,true);
END $stale_projection$;
RESET ROLE;

DO $stale_projection_inspection$
BEGIN
  IF current_setting('test.search_metadata_stale_result') <> 'projection_changed'
     OR EXISTS (SELECT 1 FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001')
     OR EXISTS (SELECT 1 FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'stale projection wrote private metadata Search storage';
  END IF;
END $stale_projection_inspection$;

SET LOCAL ROLE service_role;
DO $current_projection_write$
DECLARE projection_row record; result record;
BEGIN
  SELECT * INTO projection_row FROM public.read_current_document_search_index_projection(
    '97200000-0000-0000-0000-000000000001',ARRAY['97600000-0000-0000-0000-000000000001'::uuid]
  );
  SELECT * INTO result FROM public.write_current_document_search_index_embedding(
    '97200000-0000-0000-0000-000000000001',
    '97600000-0000-0000-0000-000000000001',projection_row.document_version_id,
    ('['||repeat('0,',767)||'0]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7,projection_row.projection_fingerprint
  );
  PERFORM set_config('test.search_metadata_current_result',result.code,true);
END $current_projection_write$;
RESET ROLE;

DO $current_projection_inspection$
BEGIN
  IF current_setting('test.search_metadata_current_result') <> 'indexed'
     OR (SELECT count(*) FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001') <> 1
     OR (SELECT count(*) FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') <> 1
     OR (SELECT metadata ->> 'reference_number' FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001') <> 'SAFE/2' THEN
    RAISE EXCEPTION 'current projection did not supersede one stable metadata item/run';
  END IF;
END $current_projection_inspection$;

-- A current effective-metadata projection is not merely a later embedding
-- concern: it immediately withdraws the private metadata item/run. Rebuild
-- through the canonical source/candidate/materialization path, then prove a
-- fresh writer uses the new fingerprint. A cleared decision is represented by
-- a NULL effective value and must withdraw it in exactly the same way.
DO $effective_metadata_change$
DECLARE
  source_run_id uuid := '98000000-0000-0000-0000-000000000001';
  candidate_id uuid;
BEGIN
  INSERT INTO public.source_analysis_runs(
    id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,
    started_at,completed_at,lease_token,lease_expires_at,provider,model_identifier,
    model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version
  ) VALUES (
    source_run_id,'97200000-0000-0000-0000-000000000001',
    '97500000-0000-0000-0000-000000000001','metadata-storage-effective','metadata-storage-effective',
    'ai_extraction','validated','succeeded',now()-interval '2 minutes',now()-interval '1 minute',
    gen_random_uuid(),now()+interval '1 minute','vertex-ai','gemini-2.5-flash',
    'fixture-model','fixture-prompt','fixture-schema','fixture-catalogue','fixture-normalizer'
  );
  PERFORM public.materialize_source_field_candidate(
    source_run_id,'document.reference_number','document.reference_number','text',
    '"EFFECTIVE/3"'::jsonb,1,'Effective fixture reference',NULL,0.99,'eligible',NULL
  );
  PERFORM public.materialize_document_version_analysis(
    '97700000-0000-0000-0000-000000000001',source_run_id,
    'metadata_storage_effective','97100000-0000-0000-0000-000000000001'
  );
  SELECT id INTO candidate_id FROM public.document_field_candidates
  WHERE document_version_id='97700000-0000-0000-0000-000000000001'
    AND semantic_candidate_key='document.reference_number';
  IF candidate_id IS NULL THEN RAISE EXCEPTION 'effective metadata fixture candidate was not materialized'; END IF;
  PERFORM set_config('test.search_metadata_effective_candidate',candidate_id::text,true);
END $effective_metadata_change$;

DO $effective_metadata_withdrawal$
DECLARE projection_row record;
BEGIN
  SELECT * INTO projection_row FROM public.read_current_document_search_index_projection(
    '97200000-0000-0000-0000-000000000001',ARRAY['97600000-0000-0000-0000-000000000001'::uuid]
  );
  IF EXISTS (SELECT 1 FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001')
     OR EXISTS (SELECT 1 FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001')
     OR projection_row.reference_number <> 'EFFECTIVE/3'
     OR projection_row.projection_fingerprint = current_setting('test.search_metadata_fingerprint') THEN
    RAISE EXCEPTION 'effective metadata change did not atomically withdraw stale private Search storage';
  END IF;
  PERFORM set_config('test.search_metadata_effective_fingerprint',projection_row.projection_fingerprint,true);
END $effective_metadata_withdrawal$;

SET LOCAL ROLE service_role;
DO $effective_metadata_current_writer$
DECLARE projection_row record; result record;
BEGIN
  SELECT * INTO projection_row FROM public.read_current_document_search_index_projection(
    '97200000-0000-0000-0000-000000000001',ARRAY['97600000-0000-0000-0000-000000000001'::uuid]
  );
  SELECT * INTO result FROM public.write_current_document_search_index_embedding(
    '97200000-0000-0000-0000-000000000001','97600000-0000-0000-0000-000000000001',projection_row.document_version_id,
    ('['||repeat('0,',767)||'0]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7,projection_row.projection_fingerprint
  );
  IF result.code <> 'indexed' THEN RAISE EXCEPTION 'current effective metadata writer was not accepted'; END IF;
END $effective_metadata_current_writer$;
RESET ROLE;

DO $effective_metadata_recreated$
BEGIN
  IF (SELECT content_fingerprint FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001')
       <> current_setting('test.search_metadata_effective_fingerprint')
     OR (SELECT metadata ->> 'reference_number' FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001') <> 'EFFECTIVE/3'
     OR (SELECT count(*) FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') <> 1 THEN
    RAISE EXCEPTION 'fresh writer did not recreate current effective metadata storage';
  END IF;
END $effective_metadata_recreated$;

SET LOCAL ROLE service_role;
DO $cleared_effective_metadata_change$
BEGIN
  PERFORM public.record_document_field_decision(
    current_setting('test.search_metadata_effective_candidate')::uuid,'cleared',NULL,
    'Fixture clear','97100000-0000-0000-0000-000000000001','metadata-storage-effective-clear'
  );
END $cleared_effective_metadata_change$;
RESET ROLE;

DO $cleared_effective_metadata_withdrawal$
DECLARE projection_row record;
BEGIN
  SELECT * INTO projection_row FROM public.read_current_document_search_index_projection(
    '97200000-0000-0000-0000-000000000001',ARRAY['97600000-0000-0000-0000-000000000001'::uuid]
  );
  IF EXISTS (SELECT 1 FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001')
     OR EXISTS (SELECT 1 FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001')
     OR projection_row.reference_number IS NOT NULL THEN
    RAISE EXCEPTION 'cleared effective metadata retained stale private Search storage';
  END IF;
END $cleared_effective_metadata_withdrawal$;

SET LOCAL ROLE service_role;
DO $cleared_effective_metadata_current_writer$
DECLARE projection_row record; result record;
BEGIN
  SELECT * INTO projection_row FROM public.read_current_document_search_index_projection(
    '97200000-0000-0000-0000-000000000001',ARRAY['97600000-0000-0000-0000-000000000001'::uuid]
  );
  SELECT * INTO result FROM public.write_current_document_search_index_embedding(
    '97200000-0000-0000-0000-000000000001','97600000-0000-0000-0000-000000000001',projection_row.document_version_id,
    ('['||repeat('0,',767)||'0]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7,projection_row.projection_fingerprint
  );
  IF result.code <> 'indexed' THEN RAISE EXCEPTION 'cleared effective metadata writer was not accepted'; END IF;
END $cleared_effective_metadata_current_writer$;
RESET ROLE;

DO $cleared_effective_metadata_recreated$
BEGIN
  IF (SELECT count(*) FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001') <> 1
     OR (SELECT metadata ? 'reference_number' FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001')
     OR (SELECT count(*) FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') <> 1 THEN
    RAISE EXCEPTION 'cleared effective metadata current writer did not recreate a safe item/run';
  END IF;
END $cleared_effective_metadata_recreated$;

-- Replacing the current version clears both private projections. The old
-- version cannot revive them, while the new version reuses one stable item.
DO $replacement_setup$
DECLARE asset_id uuid := '97500000-0000-0000-0000-000000000002';
DECLARE version_id uuid := '97700000-0000-0000-0000-000000000002';
BEGIN
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
  VALUES(asset_id,'97200000-0000-0000-0000-000000000001','documents',
    'orgs/97200000-0000-0000-0000-000000000001/assets/'||asset_id||'/original.pdf',
    11,'application/pdf','available',now(),1,'97100000-0000-0000-0000-000000000001');
  UPDATE public.document_versions SET state='superseded',superseded_at=now()
  WHERE id='97700000-0000-0000-0000-000000000001';
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
  VALUES(version_id,'97200000-0000-0000-0000-000000000001','97600000-0000-0000-0000-000000000001',asset_id,2,'replacement.pdf',1,'valid','current',now(),now(),'97100000-0000-0000-0000-000000000001');
  UPDATE public.documents SET current_version_id=version_id,content_availability='source_attached'
  WHERE id='97600000-0000-0000-0000-000000000001';
  IF EXISTS (SELECT 1 FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001')
     OR EXISTS (SELECT 1 FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'current-version replacement retained stale private Search metadata';
  END IF;
END $replacement_setup$;

SET LOCAL ROLE service_role;
DO $replacement_fences$
DECLARE projection_row record; result record;
BEGIN
  SELECT * INTO result FROM public.write_current_document_search_index_embedding(
    '97200000-0000-0000-0000-000000000001','97600000-0000-0000-0000-000000000001',
    '97700000-0000-0000-0000-000000000001',('['||repeat('0,',767)||'0]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7,'a'||repeat('0',63)
  );
  IF result.code <> 'version_not_current' THEN
    RAISE EXCEPTION 'superseded version revived a metadata Search item';
  END IF;
  SELECT * INTO projection_row FROM public.read_current_document_search_index_projection(
    '97200000-0000-0000-0000-000000000001',ARRAY['97600000-0000-0000-0000-000000000001'::uuid]
  );
  SELECT * INTO result FROM public.write_current_document_search_index_embedding(
    '97200000-0000-0000-0000-000000000001','97600000-0000-0000-0000-000000000001',
    projection_row.document_version_id,('['||repeat('0,',767)||'0]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7,projection_row.projection_fingerprint
  );
  PERFORM set_config('test.search_metadata_replacement_result',result.code,true);
END $replacement_fences$;
RESET ROLE;

DO $replacement_inspection$
BEGIN
  IF current_setting('test.search_metadata_replacement_result') <> 'indexed'
     OR (SELECT count(*) FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001') <> 1
     OR (SELECT count(*) FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') <> 1 THEN
    RAISE EXCEPTION 'new current version did not write one private metadata item/run';
  END IF;
END $replacement_inspection$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','97100000-0000-0000-0000-000000000001',true);
DO $trash_fence$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.trash_resource(
    'document','97600000-0000-0000-0000-000000000001','search-metadata-storage-trash'
  );
  IF result.code <> 'trashed' THEN
    RAISE EXCEPTION 'fixture document was not trashed: %', result.code;
  END IF;
END $trash_fence$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $trashed_writer_denied$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.write_current_document_search_index_embedding(
    '97200000-0000-0000-0000-000000000001','97600000-0000-0000-0000-000000000001',
    '97700000-0000-0000-0000-000000000002',('['||repeat('0,',767)||'0]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7,'a'||repeat('0',63)
  );
  IF result.code <> 'version_not_current' THEN
    RAISE EXCEPTION 'trashed document accepted a current metadata Search write';
  END IF;
END $trashed_writer_denied$;
RESET ROLE;

DO $trash_storage_inspection$
BEGIN
  IF (SELECT record_state FROM public.documents WHERE id='97600000-0000-0000-0000-000000000001') <> 'trashed'
     OR EXISTS (SELECT 1 FROM public.search_items WHERE document_id='97600000-0000-0000-0000-000000000001')
     OR EXISTS (SELECT 1 FROM public.search_index_runs WHERE document_id='97600000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'Trash retained or rewrote current metadata Search storage';
  END IF;
END $trash_storage_inspection$;

DO $authority_surface$
BEGIN
  IF has_table_privilege('anon','public.search_items','SELECT')
     OR has_table_privilege('authenticated','public.search_items','INSERT')
     OR has_table_privilege('service_role','public.search_items','UPDATE')
     OR has_table_privilege('anon','public.search_index_runs','SELECT')
     OR has_table_privilege('authenticated','public.search_index_runs','INSERT')
     OR has_table_privilege('service_role','public.search_index_runs','UPDATE')
     OR has_function_privilege('anon','public.finish_document_search_index_reprocess_work(uuid,uuid,text,vector,text,text,integer,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.finish_document_search_index_reprocess_work(uuid,uuid,text,vector,text,text,integer,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.finish_document_search_index_reprocess_work(uuid,uuid,text,vector,text,text,integer,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.write_current_document_search_index_embedding(uuid,uuid,uuid,vector,text,text,integer,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.write_current_document_search_index_embedding(uuid,uuid,uuid,vector,text,text,integer,text)','EXECUTE') THEN
    RAISE EXCEPTION 'metadata Search storage authority surface is not private and service-RPC-only';
  END IF;
END $authority_surface$;

SET LOCAL ROLE service_role;
DO $service_direct_table_mutation_denied$
BEGIN
  BEGIN
    INSERT INTO public.search_items DEFAULT VALUES;
    RAISE EXCEPTION 'service role directly inserted into private search_items';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  BEGIN
    INSERT INTO public.search_index_runs DEFAULT VALUES;
    RAISE EXCEPTION 'service role directly inserted into private search_index_runs';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END $service_direct_table_mutation_denied$;
RESET ROLE;

SET LOCAL ROLE authenticated;
DO $browser_direct_table_mutation_denied$
BEGIN
  BEGIN
    INSERT INTO public.search_items DEFAULT VALUES;
    RAISE EXCEPTION 'authenticated caller directly inserted into private search_items';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  BEGIN
    INSERT INTO public.search_index_runs DEFAULT VALUES;
    RAISE EXCEPTION 'authenticated caller directly inserted into private search_index_runs';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END $browser_direct_table_mutation_denied$;
RESET ROLE;

ROLLBACK;
