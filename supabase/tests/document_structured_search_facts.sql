-- Run after migration 00114 against a disposable local Supabase database.
-- This fixture exercises the durable reprocess completion rather than a
-- parallel matter/direct writer and leaves no rows behind.
BEGIN;

DO $setup$
DECLARE
  owner_id uuid := '11400000-0000-0000-0000-000000000001';
  org_id uuid := '11400000-0000-0000-0000-000000000002';
  client_id uuid := '11400000-0000-0000-0000-000000000003';
  matter_id uuid := '11400000-0000-0000-0000-000000000004';
  asset_id uuid := '11400000-0000-0000-0000-000000000005';
  document_id uuid := '11400000-0000-0000-0000-000000000006';
  version_id uuid := '11400000-0000-0000-0000-000000000007';
  source_run_id uuid := '11400000-0000-0000-0000-000000000008';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000',owner_id,'authenticated','authenticated','structured-search@test','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES(org_id,'Structured Search fixture',owner_id);
  INSERT INTO public.clients(id,org_id,name) VALUES(client_id,org_id,'Fixture taxpayer');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES(matter_id,org_id,client_id,'Structured fact matter');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
  VALUES(asset_id,org_id,'documents','orgs/'||org_id||'/assets/'||asset_id||'/original.pdf',10,'application/pdf','available',now(),1,owner_id);
  INSERT INTO public.documents(id,org_id,matter_id,display_title,origin_kind,record_state,content_availability,status,doc_type,reference_number,summary,created_by)
  VALUES(document_id,org_id,matter_id,'Structured source','upload','active','source_attached','placed','SCN','SCN/STRUCTURED','Safe fixture summary.',owner_id);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
  VALUES(version_id,org_id,document_id,asset_id,1,'structured.pdf',1,'valid','current',now(),now(),owner_id);
  UPDATE public.documents SET current_version_id=version_id WHERE id=document_id;
  INSERT INTO public.source_analysis_runs(
    id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,started_at,completed_at,
    lease_token,lease_expires_at,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version
  ) VALUES (
    source_run_id,org_id,asset_id,'structured-search-fixture','structured-search-fixture','ai_extraction','validated','succeeded',
    now()-interval '2 minutes',now()-interval '1 minute',gen_random_uuid(),now()+interval '1 minute','vertex-ai','gemini-2.5-flash',
    'fixture','fixture','fixture','fixture','fixture'
  );
  PERFORM public.materialize_source_field_candidate(source_run_id,'document.type','document.type','code','"oio"'::jsonb,1,'OIO',NULL,.99,'eligible',NULL);
  PERFORM public.materialize_source_field_candidate(source_run_id,'document.client_name','document.client_name','text','"  Acme   Private Limited "'::jsonb,1,'Acme Private Limited',NULL,.99,'eligible',NULL);
  PERFORM public.materialize_source_field_candidate(source_run_id,'document.gstin','document.gstin','code','"27ABCDE1234F1Z5"'::jsonb,1,'27ABCDE1234F1Z5',NULL,.99,'eligible',NULL);
  PERFORM public.materialize_source_field_candidate(source_run_id,'fy.first','document.financial_year','code','"2023-24"'::jsonb,1,'FY 2023-24',NULL,.99,'eligible',NULL);
  PERFORM public.materialize_source_field_candidate(source_run_id,'fy.repeat','document.financial_year','code','"2023-24"'::jsonb,1,'FY 2023-24 again',NULL,.99,'eligible',NULL);
  PERFORM public.materialize_source_field_candidate(source_run_id,'deadline.reply','deadline.due_date','date','"2025-01-31"'::jsonb,1,'Reply due on 31 January 2025',NULL,.99,'eligible',NULL);
  PERFORM public.materialize_source_field_candidate(source_run_id,'amount.tax','financial.tax','decimal','"1400000.01"'::jsonb,1,'Tax demand INR 14,00,000.01',NULL,.99,'eligible',NULL);
  PERFORM public.materialize_source_field_candidate(source_run_id,'amount.reject','financial.penalty','decimal','"1.001"'::jsonb,1,'Penalty INR 1.001',NULL,.99,'eligible',NULL);
  PERFORM public.materialize_source_field_candidate(source_run_id,'legal.73','legal_reference.provision_number','code','"73"'::jsonb,1,'Section 73',NULL,.99,'eligible',NULL);
  PERFORM public.materialize_document_version_analysis(version_id,source_run_id,'structured_search_fixture',owner_id);
END $setup$;

-- Internal SECURITY DEFINER helpers must never become a direct service or
-- tenant write route; only the leased public completion authority is granted.
DO $catalog_acl$
BEGIN
  IF has_function_privilege('anon',
       'public.upsert_document_metadata_search_storage_legacy_b(uuid,uuid,uuid,text,uuid,text,integer,text)',
       'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.upsert_document_metadata_search_storage_legacy_b(uuid,uuid,uuid,text,uuid,text,integer,text)',
       'EXECUTE')
     OR has_function_privilege('service_role',
       'public.upsert_document_metadata_search_storage_legacy_b(uuid,uuid,uuid,text,uuid,text,integer,text)',
       'EXECUTE')
     OR has_function_privilege('anon',
       'public.finish_search_index_reprocess_pre_facts(uuid,uuid,text,vector,text,text,integer,text)',
       'EXECUTE')
     OR has_function_privilege('authenticated',
       'public.finish_search_index_reprocess_pre_facts(uuid,uuid,text,vector,text,text,integer,text)',
       'EXECUTE')
     OR has_function_privilege('service_role',
       'public.finish_search_index_reprocess_pre_facts(uuid,uuid,text,vector,text,text,integer,text)',
       'EXECUTE') THEN
    RAISE EXCEPTION 'internal structured Search completion helpers have execute privileges';
  END IF;
END $catalog_acl$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11400000-0000-0000-0000-000000000001',true);
DO $request$
DECLARE queued record;
BEGIN
  SELECT * INTO queued FROM public.request_document_reprocess(
    '11400000-0000-0000-0000-000000000006','search_index','11400000-0000-0000-0000-000000000009',8
  );
  IF queued.code <> 'queued' THEN RAISE EXCEPTION 'durable structured-fact request was not queued'; END IF;
  PERFORM set_config('test.structured_event',queued.outbox_event_id::text,true);
END $request$;
RESET ROLE;

UPDATE public.outbox_events SET delivery_state='leased',lease_token='11400000-0000-0000-0000-000000000010',
  lease_expires_at=now()+interval '2 minutes',delivered_at=NULL,failed_at=NULL
WHERE id=current_setting('test.structured_event')::uuid;

SET LOCAL ROLE service_role;
DO $complete$
DECLARE claim record; input_row record; complete record; replay record; direct_denied boolean := false;
BEGIN
  SELECT * INTO claim FROM public.claim_document_search_index_reprocess_work(
    current_setting('test.structured_event')::uuid,'structured-search-fixture',
    '11400000-0000-0000-0000-000000000002','11400000-0000-0000-0000-000000000010'
  );
  SELECT * INTO input_row FROM public.get_document_search_index_reprocess_input(claim.processing_run_id,claim.lease_token);
  SELECT * INTO complete FROM public.finish_document_search_index_reprocess_work(
    claim.processing_run_id,claim.lease_token,'indexed',
    ('['||repeat('0,',767)||'0]')::vector,'gemini-embedding-001','gemini-embedding-001-768-v1',7,input_row.projection_fingerprint
  );
  SELECT * INTO replay FROM public.finish_document_search_index_reprocess_work(
    claim.processing_run_id,claim.lease_token,'indexed',
    ('['||repeat('0,',767)||'0]')::vector,'gemini-embedding-001','gemini-embedding-001-768-v1',7,input_row.projection_fingerprint
  );
  BEGIN
    INSERT INTO public.search_document_structured_facts(
      org_id,document_id,document_version_id,fact_family,field_path,semantic_candidate_key,normalized_text,resolution,winning_document_field_candidate_id
    ) VALUES (
      '11400000-0000-0000-0000-000000000002','11400000-0000-0000-0000-000000000006','11400000-0000-0000-0000-000000000007',
      'gstin','document.gstin','forged','27ABCDE1234F1Z5','automatic','11400000-0000-0000-0000-000000000008'
    );
  EXCEPTION WHEN insufficient_privilege THEN direct_denied := true;
  END;
  IF claim.code <> 'claimed' OR input_row.code <> 'ready' OR complete.code <> 'indexed'
     OR replay.code <> 'already_complete' OR NOT direct_denied THEN
    RAISE EXCEPTION 'leased structured Search completion or direct-write fence failed';
  END IF;
  PERFORM set_config('test.structured_fingerprint',input_row.projection_fingerprint,true);
END $complete$;
RESET ROLE;

DO $facts$
BEGIN
  IF (SELECT count(*) FROM public.search_document_structured_facts WHERE document_id='11400000-0000-0000-0000-000000000006') <> 6
     OR NOT EXISTS (SELECT 1 FROM public.search_document_structured_facts WHERE fact_family='document_type' AND normalized_text='OIO')
     OR NOT EXISTS (SELECT 1 FROM public.search_document_structured_facts WHERE fact_family='party' AND normalized_text='acme private limited')
     OR NOT EXISTS (SELECT 1 FROM public.search_document_structured_facts WHERE fact_family='gstin' AND normalized_text='27ABCDE1234F1Z5')
     OR (SELECT count(*) FROM public.search_document_structured_facts WHERE fact_family='financial_year') <> 1
     OR NOT EXISTS (SELECT 1 FROM public.search_document_structured_facts WHERE fact_family='deadline' AND value_date='2025-01-31'::date)
     OR NOT EXISTS (SELECT 1 FROM public.search_document_structured_facts WHERE fact_family='amount' AND field_path='financial.tax' AND amount_paise=140000001)
     OR EXISTS (SELECT 1 FROM public.search_document_structured_facts WHERE field_path='financial.penalty')
     OR EXISTS (SELECT 1 FROM public.search_document_structured_facts WHERE fact_family='legal_reference')
     OR (SELECT state FROM public.search_index_runs WHERE document_id='11400000-0000-0000-0000-000000000006') <> 'indexed'
     OR NOT EXISTS (SELECT 1 FROM public.search_items
       WHERE document_id='11400000-0000-0000-0000-000000000006'
         AND source_type='document_metadata'
         AND document_version_id='11400000-0000-0000-0000-000000000007')
     OR (SELECT embedding_document_version_id FROM public.documents
       WHERE id='11400000-0000-0000-0000-000000000006') <> '11400000-0000-0000-0000-000000000007'::uuid THEN
    RAISE EXCEPTION 'structured fact normalization, exact paise, duplicate suppression, or metadata completion failed';
  END IF;
END $facts$;

-- Decisions are a service-only inspector authority.  The user identity stays
-- in the immutable decision provenance; the authenticated role is used only
-- for the public reprocess request below.
SET LOCAL ROLE service_role;
DO $correct$
DECLARE party_candidate uuid;
BEGIN
  SELECT document_field_candidate_id INTO party_candidate
  FROM public.read_current_document_inspector_projection(
    '11400000-0000-0000-0000-000000000002', ARRAY['11400000-0000-0000-0000-000000000006'::uuid]
  )
  WHERE semantic_candidate_key='document.client_name';
  PERFORM public.record_document_field_decision(
    party_candidate,'corrected','"Acme Holdings Private Limited"'::jsonb,'Fixture correction',
    '11400000-0000-0000-0000-000000000001','structured-search-correct'
  );
END $correct$;
RESET ROLE;

DO $correction_retracts$
BEGIN
  IF EXISTS (SELECT 1 FROM public.search_document_structured_facts WHERE document_id='11400000-0000-0000-0000-000000000006') THEN
    RAISE EXCEPTION 'effective metadata correction did not retract structured facts';
  END IF;
END $correction_retracts$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11400000-0000-0000-0000-000000000001',true);
DO $correction_request$
DECLARE queued record;
BEGIN
  SELECT * INTO queued FROM public.request_document_reprocess(
    '11400000-0000-0000-0000-000000000006','search_index','11400000-0000-0000-0000-000000000013',8
  );
  IF queued.code <> 'queued' THEN RAISE EXCEPTION 'post-correction durable request was not queued'; END IF;
  PERFORM set_config('test.structured_correction_event',queued.outbox_event_id::text,true);
END $correction_request$;
RESET ROLE;

UPDATE public.outbox_events SET delivery_state='leased',lease_token='11400000-0000-0000-0000-000000000014',
  lease_expires_at=now()+interval '2 minutes',delivered_at=NULL,failed_at=NULL
WHERE id=current_setting('test.structured_correction_event')::uuid;

SET LOCAL ROLE service_role;
DO $correction_completion$
DECLARE claim record; input_row record; malformed record;
BEGIN
  SELECT * INTO claim FROM public.claim_document_search_index_reprocess_work(
    current_setting('test.structured_correction_event')::uuid,'structured-search-correction-fixture',
    '11400000-0000-0000-0000-000000000002','11400000-0000-0000-0000-000000000014'
  );
  SELECT * INTO input_row FROM public.get_document_search_index_reprocess_input(claim.processing_run_id,claim.lease_token);
  SELECT * INTO malformed FROM public.finish_document_search_index_reprocess_work(
    claim.processing_run_id,claim.lease_token,'indexed',
    ('['||repeat('0,',767)||'0]')::vector,'gemini-embedding-001','gemini-embedding-001-768-v1',-1,input_row.projection_fingerprint
  );
  IF malformed.code <> 'invalid_request' THEN
    RAISE EXCEPTION 'malformed completion mutated facts or its leased processing run';
  END IF;
  IF claim.code <> 'claimed' OR input_row.code <> 'ready' THEN
    RAISE EXCEPTION 'post-correction structured Search run was not claimed and ready';
  END IF;
  PERFORM set_config('test.structured_correction_run',claim.processing_run_id::text,true);
  PERFORM set_config('test.structured_correction_lease',claim.lease_token::text,true);
  PERFORM set_config('test.structured_correction_fingerprint',input_row.projection_fingerprint,true);
END $correction_completion$;
RESET ROLE;

DO $malformed_completion_facts$
BEGIN
  IF EXISTS (SELECT 1 FROM public.search_document_structured_facts
    WHERE document_id='11400000-0000-0000-0000-000000000006')
     OR (SELECT state FROM public.document_processing_runs
       WHERE id=current_setting('test.structured_correction_run')::uuid) <> 'running' THEN
    RAISE EXCEPTION 'malformed completion wrote private structured facts';
  END IF;
END $malformed_completion_facts$;

SET LOCAL ROLE service_role;
DO $correction_valid_completion$
DECLARE completion record;
BEGIN
  SELECT * INTO completion FROM public.finish_document_search_index_reprocess_work(
    current_setting('test.structured_correction_run')::uuid,
    current_setting('test.structured_correction_lease')::uuid,'indexed',
    ('['||repeat('0,',767)||'0]')::vector,'gemini-embedding-001','gemini-embedding-001-768-v1',7,
    current_setting('test.structured_correction_fingerprint')
  );
  IF completion.code <> 'indexed' THEN
    RAISE EXCEPTION 'post-correction structured Search run did not complete indexed';
  END IF;
END $correction_valid_completion$;
RESET ROLE;

DO $correction_facts$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.search_document_structured_facts
    WHERE document_id='11400000-0000-0000-0000-000000000006' AND fact_family='party'
      AND normalized_text='acme holdings private limited') THEN
    RAISE EXCEPTION 'post-correction indexed run did not write corrected fact';
  END IF;
END $correction_facts$;

-- A clear removes the private projection immediately; a new durable run will
-- never resurrect the source candidate as a fallback value.
SET LOCAL ROLE service_role;
DO $clear$
DECLARE gstin_candidate uuid;
BEGIN
  SELECT document_field_candidate_id INTO gstin_candidate
  FROM public.read_current_document_inspector_projection(
    '11400000-0000-0000-0000-000000000002', ARRAY['11400000-0000-0000-0000-000000000006'::uuid]
  )
  WHERE semantic_candidate_key='document.gstin';
  PERFORM public.record_document_field_decision(
    gstin_candidate,'cleared',NULL,'Fixture clear','11400000-0000-0000-0000-000000000001','structured-search-clear'
  );
END $clear$;
RESET ROLE;

DO $clear_retracts$
BEGIN
  IF EXISTS (SELECT 1 FROM public.search_document_structured_facts WHERE document_id='11400000-0000-0000-0000-000000000006') THEN
    RAISE EXCEPTION 'effective metadata change did not retract structured facts';
  END IF;
END $clear_retracts$;

-- The post-clear route must complete a fresh leased run, not merely retract
-- and leave retry work. Its structured source has no GSTIN fallback.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11400000-0000-0000-0000-000000000001',true);
DO $post_clear_request$
DECLARE queued record;
BEGIN
  SELECT * INTO queued FROM public.request_document_reprocess(
    '11400000-0000-0000-0000-000000000006','search_index','11400000-0000-0000-0000-000000000011',8
  );
  IF queued.code <> 'queued' THEN RAISE EXCEPTION 'post-clear durable request was not queued'; END IF;
  PERFORM set_config('test.structured_clear_event',queued.outbox_event_id::text,true);
END $post_clear_request$;
RESET ROLE;

UPDATE public.outbox_events SET delivery_state='leased',lease_token='11400000-0000-0000-0000-000000000012',
  lease_expires_at=now()+interval '2 minutes',delivered_at=NULL,failed_at=NULL
WHERE id=current_setting('test.structured_clear_event')::uuid;

SET LOCAL ROLE service_role;
DO $post_clear_complete$
DECLARE claim record; input_row record; completion record;
BEGIN
  SELECT * INTO claim FROM public.claim_document_search_index_reprocess_work(
    current_setting('test.structured_clear_event')::uuid,'structured-search-clear-fixture',
    '11400000-0000-0000-0000-000000000002','11400000-0000-0000-0000-000000000012'
  );
  SELECT * INTO input_row FROM public.get_document_search_index_reprocess_input(claim.processing_run_id,claim.lease_token);
  SELECT * INTO completion FROM public.finish_document_search_index_reprocess_work(
    claim.processing_run_id,claim.lease_token,'indexed',
    ('['||repeat('0,',767)||'0]')::vector,'gemini-embedding-001','gemini-embedding-001-768-v1',7,input_row.projection_fingerprint
  );
  IF claim.code <> 'claimed' OR input_row.code <> 'ready' OR completion.code <> 'indexed' THEN
    RAISE EXCEPTION 'post-clear structured Search run did not complete indexed';
  END IF;
END $post_clear_complete$;
RESET ROLE;

DO $post_clear_facts$
BEGIN
  IF EXISTS (SELECT 1 FROM public.search_document_structured_facts
    WHERE document_id='11400000-0000-0000-0000-000000000006' AND fact_family='gstin')
     OR (SELECT state FROM public.search_index_runs WHERE document_id='11400000-0000-0000-0000-000000000006') <> 'indexed' THEN
    RAISE EXCEPTION 'post-clear indexing retained a cleared GSTIN or failed to become current indexed state';
  END IF;
END $post_clear_facts$;

-- Change a structured-only field after the worker reads A.  Legacy metadata
-- B is deliberately unchanged, so this proves the fact-authority fence, not
-- only the legacy completion fence, cancels the stale leased writer.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11400000-0000-0000-0000-000000000001',true);
DO $stale_request$
DECLARE queued record;
BEGIN
  SELECT * INTO queued FROM public.request_document_reprocess(
    '11400000-0000-0000-0000-000000000006','search_index','11400000-0000-0000-0000-000000000015',8
  );
  IF queued.code <> 'queued' THEN RAISE EXCEPTION 'stale-fence durable request was not queued'; END IF;
  PERFORM set_config('test.structured_stale_event',queued.outbox_event_id::text,true);
END $stale_request$;
RESET ROLE;

UPDATE public.outbox_events SET delivery_state='leased',lease_token='11400000-0000-0000-0000-000000000016',
  lease_expires_at=now()+interval '2 minutes',delivered_at=NULL,failed_at=NULL
WHERE id=current_setting('test.structured_stale_event')::uuid;

SET LOCAL ROLE service_role;
DO $stale_completion$
DECLARE claim record; input_row record; completion record; party_candidate uuid;
BEGIN
  SELECT * INTO claim FROM public.claim_document_search_index_reprocess_work(
    current_setting('test.structured_stale_event')::uuid,'structured-search-stale-fixture',
    '11400000-0000-0000-0000-000000000002','11400000-0000-0000-0000-000000000016'
  );
  SELECT * INTO input_row FROM public.get_document_search_index_reprocess_input(claim.processing_run_id,claim.lease_token);
  SELECT document_field_candidate_id INTO party_candidate
  FROM public.read_current_document_inspector_projection(
    '11400000-0000-0000-0000-000000000002', ARRAY['11400000-0000-0000-0000-000000000006'::uuid]
  )
  WHERE semantic_candidate_key='document.client_name';
  PERFORM public.record_document_field_decision(
    party_candidate,'cleared',NULL,'Fixture stale fence','11400000-0000-0000-0000-000000000001','structured-search-stale'
  );
  SELECT * INTO completion FROM public.finish_document_search_index_reprocess_work(
    claim.processing_run_id,claim.lease_token,'indexed',
    ('['||repeat('0,',767)||'0]')::vector,'gemini-embedding-001','gemini-embedding-001-768-v1',7,input_row.projection_fingerprint
  );
  IF claim.code <> 'claimed' OR input_row.code <> 'ready' OR completion.code <> 'projection_changed'
  THEN
    RAISE EXCEPTION 'structured-only stale fence permitted a completion or fact write';
  END IF;
  PERFORM set_config('test.structured_stale_run',claim.processing_run_id::text,true);
END $stale_completion$;
RESET ROLE;

DO $stale_completion_assertion$
BEGIN
  IF (SELECT state FROM public.document_processing_runs
      WHERE id=current_setting('test.structured_stale_run')::uuid) <> 'cancelled'
     OR EXISTS (SELECT 1 FROM public.search_document_structured_facts
       WHERE document_id='11400000-0000-0000-0000-000000000006') THEN
    RAISE EXCEPTION 'structured-only stale fence permitted a completion or fact write';
  END IF;
END $stale_completion_assertion$;

ROLLBACK;
