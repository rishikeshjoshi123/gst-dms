-- Run after migration 00121 against a disposable local Supabase database.
-- Rollback-only: proves the completion transaction admits only canonical page
-- anchors, preserves their exact replay identity, and retains its authority
-- and lease fences.
BEGIN;

DO $setup$
DECLARE
  org_a uuid := '11700000-0000-0000-0000-000000000001';
  org_b uuid := '11700000-0000-0000-0000-000000000002';
  actor_a uuid := '11710000-0000-0000-0000-000000000001';
  actor_b uuid := '11710000-0000-0000-0000-000000000002';
  client_a uuid := '11720000-0000-0000-0000-000000000001';
  matter_a uuid := '11730000-0000-0000-0000-000000000001';
  document_a uuid := '11740000-0000-0000-0000-000000000001';
  asset_a uuid := '11750000-0000-0000-0000-000000000001';
  asset_b uuid := '11750000-0000-0000-0000-000000000002';
  version_a uuid := '11760000-0000-0000-0000-000000000001';
  processing_a uuid := '11770000-0000-0000-0000-000000000001';
  processing_lease uuid := '11780000-0000-0000-0000-000000000001';
  source_a uuid := '11790000-0000-0000-0000-000000000001';
  source_lease uuid := '11790000-0000-0000-0000-000000000002';
  source_b uuid := '11790000-0000-0000-0000-000000000003';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES
    ('00000000-0000-0000-0000-000000000000',actor_a,'authenticated','authenticated','verified-anchor-a@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',actor_b,'authenticated','authenticated','verified-anchor-b@example.test','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES (org_a,'Verified anchor A',actor_a),(org_b,'Verified anchor B',actor_b);
  INSERT INTO public.clients(id,org_id,name) VALUES (client_a,org_a,'Anchor client');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES (matter_a,org_a,client_a,'Anchor matter');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by) VALUES (document_a,org_a,matter_a,'fixtures/anchor.pdf',actor_a);
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
  VALUES
    (asset_a,org_a,'documents','orgs/' || org_a::text || '/assets/' || asset_a::text || '/original.pdf',repeat('a',64),42,'application/pdf','available',now(),2,actor_a),
    (asset_b,org_b,'documents','orgs/' || org_b::text || '/assets/' || asset_b::text || '/original.pdf',repeat('b',64),42,'application/pdf','available',now(),1,actor_b);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
  VALUES (version_a,org_a,document_a,asset_a,1,'anchor.pdf',2,'valid','current',now(),now(),actor_a);
  UPDATE public.documents SET current_version_id=version_a WHERE id=document_a;
  INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
  VALUES (processing_a,org_a,document_a,version_a,'full','fixture.verified-anchor','running','extracting',now(),processing_lease,now()+interval '10 minutes',now());
  INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,attempt_count,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at,lease_token,lease_expires_at,heartbeat_at)
  VALUES
    (source_a,org_a,asset_a,'ai_extraction.' || processing_a::text,'ai_extraction.' || processing_a::text,'ai_extraction','running','running',1,'vertex-ai','gemini-2.5-flash','fixture-model','fixture-prompt','fixture-schema','fixture-catalogue','fixture-normalizer',now(),source_lease,now()+interval '10 minutes',now()),
    (source_b,org_b,asset_b,'ai_extraction.foreign','ai_extraction.foreign','ai_extraction','running','running',1,'vertex-ai','gemini-2.5-flash','fixture-model','fixture-prompt','fixture-schema','fixture-catalogue','fixture-normalizer',now(),gen_random_uuid(),now()+interval '10 minutes',now());
  INSERT INTO public.source_analysis_attempts(org_id,source_analysis_run_id,attempt_number,state,retry_reason,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at)
  VALUES (org_a,source_a,1,'running','initial','vertex-ai','gemini-2.5-flash','fixture-model','fixture-prompt','fixture-schema','fixture-catalogue','fixture-normalizer',now());
  INSERT INTO public.document_page_text_artifacts(org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,content_fingerprint)
  VALUES (org_a,document_a,version_a,processing_a,source_a,'ready',2,repeat('c',64));
  INSERT INTO public.document_page_text_pages(org_id,artifact_id,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages,ocr_processor_identifier,ocr_processor_version)
  SELECT org_a,id,1,'Reference ABC/123. Total 1,000. Due by 29.01.2025.','[{"text":"Reference","x":0.1,"y":0.1,"width":0.2,"height":0.1},{"text":"ABC/123","x":0.4,"y":0.1,"width":0.2,"height":0.1}]'::jsonb,'[{"table_index":0,"row_index":1,"column_index":1,"row_span":1,"column_span":1,"reading_order":3,"text":"Total 1,000","x":0.4,"y":0.3,"width":0.2,"height":0.05},{"table_index":0,"row_index":1,"column_index":2,"row_span":1,"column_span":1,"reading_order":4,"text":"Unrelated 999","x":0.7,"y":0.3,"width":0.2,"height":0.05}]'::jsonb,repeat('d',64),'native_pdf','native-pdf-quality-v1','{}','{}',NULL,NULL
  FROM public.document_page_text_artifacts WHERE org_id=org_a AND document_id=document_a;
  INSERT INTO public.document_page_text_pages(org_id,artifact_id,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages,ocr_processor_identifier,ocr_processor_version)
  SELECT org_a,id,2,'Exact code ABC/123. Prefix code XABC/123. Repeated code DUP/1 and DUP/1. Exact text Finding. Prefix text Findings. Exact date 29 January 2025. Embedded dates 12025-01-29 X2025-01-29 2025-01-290. Exact amount 1,000. Prefix amount 1,000.50.','[]'::jsonb,
    '[{"table_index":0,"row_index":2,"column_index":1,"row_span":1,"column_span":1,"reading_order":5,"text":"Exact amount 1,000","x":0.1,"y":0.5,"width":0.3,"height":0.05},{"table_index":0,"row_index":2,"column_index":2,"row_span":1,"column_span":1,"reading_order":6,"text":"Prefix amount 1,000.50","x":0.5,"y":0.5,"width":0.4,"height":0.05}]'::jsonb,repeat('e',64),'native_pdf','native-pdf-quality-v1','{}','{}',NULL,NULL
  FROM public.document_page_text_artifacts WHERE org_id=org_a AND document_id=document_a;
END $setup$;

DO $completion_contract$
DECLARE
  processing_a uuid := '11770000-0000-0000-0000-000000000001';
  processing_lease uuid := '11780000-0000-0000-0000-000000000001';
  source_a uuid := '11790000-0000-0000-0000-000000000001';
  source_lease uuid := '11790000-0000-0000-0000-000000000002';
  source_b uuid := '11790000-0000-0000-0000-000000000003';
  result record;
  candidate_id uuid;
  replay_id uuid;
  rejected boolean;
  anchored_candidate constant jsonb := '{"semantic_candidate_key":"document.reference_number.abc123","field_path":"document.reference_number","value_type":"code","normalized_value":"ABC/123","page_number":1,"quotation":"Reference ABC/123","evidence_regions":[{"x":0.1,"y":0.1,"width":0.2,"height":0.1},{"x":0.4,"y":0.1,"width":0.2,"height":0.1}],"verified_source_anchor":{"char_start":0,"char_end":17,"token_start":0,"token_end":1,"table_cell":null},"confidence":0.95,"validation_state":"eligible","validation_error_codes":null}'::jsonb;
  anchored_table_candidate constant jsonb := '{"semantic_candidate_key":"financial.total_demand.1000","field_path":"financial.total_demand","value_type":"decimal","normalized_value":"1000","page_number":1,"quotation":"Total 1,000","evidence_regions":[{"x":0.4,"y":0.3,"width":0.2,"height":0.05}],"verified_source_anchor":{"char_start":19,"char_end":30,"token_start":null,"token_end":null,"table_cell":{"table_index":0,"row_index":1,"column_index":1}},"confidence":0.95,"validation_state":"eligible","validation_error_codes":null}'::jsonb;
BEGIN
  SELECT * INTO result FROM public.finish_document_processing_ai_extraction(processing_a,processing_lease,source_a,gen_random_uuid(),'review_required',0,0,1,'[]'::jsonb,true,NULL);
  IF result.code <> 'source_lease_invalid' THEN RAISE EXCEPTION 'foreign or stale source lease was accepted'; END IF;
  SELECT * INTO result FROM public.finish_document_processing_ai_extraction(processing_a,processing_lease,source_b,gen_random_uuid(),'review_required',0,0,1,'[]'::jsonb,true,NULL);
  IF result.code <> 'source_identity_invalid' THEN RAISE EXCEPTION 'foreign source run was accepted'; END IF;

  rejected := false;
  BEGIN
    PERFORM public.finish_document_processing_ai_extraction(processing_a,processing_lease,source_a,source_lease,'validated',1,1,1,jsonb_build_array(anchored_candidate || jsonb_build_object('verified_source_anchor',jsonb_build_object('char_start',1,'char_end',18,'token_start',0,'token_end',1,'table_cell',NULL))),false,'{"doc_type":"OTHER","direction":"incoming"}'::jsonb);
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected OR (SELECT analysis_state FROM public.source_analysis_runs WHERE id=source_a) <> 'running' THEN
    RAISE EXCEPTION 'forged canonical-page anchor changed terminal provenance';
  END IF;

  rejected := false;
  BEGIN
    PERFORM public.finish_document_processing_ai_extraction(processing_a,processing_lease,source_a,source_lease,'validated',1,1,1,jsonb_build_array(anchored_candidate || jsonb_build_object('verified_source_anchor',jsonb_build_object('char_start',0,'char_end',17,'token_start',1,'token_end',1,'table_cell',NULL))),false,'{"doc_type":"OTHER","direction":"incoming"}'::jsonb);
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected OR (SELECT analysis_state FROM public.source_analysis_runs WHERE id=source_a) <> 'running' THEN
    RAISE EXCEPTION 'in-bounds forged token indices changed terminal provenance';
  END IF;

  rejected := false;
  BEGIN
    PERFORM public.finish_document_processing_ai_extraction(processing_a,processing_lease,source_a,source_lease,'validated',1,1,1,jsonb_build_array(anchored_candidate || jsonb_build_object('evidence_regions',jsonb_build_array(jsonb_build_object('x',0.9,'y',0.9,'width',0.05,'height',0.05)))),false,'{"doc_type":"OTHER","direction":"incoming"}'::jsonb);
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected OR (SELECT analysis_state FROM public.source_analysis_runs WHERE id=source_a) <> 'running' THEN
    RAISE EXCEPTION 'forged in-bounds token geometry changed terminal provenance';
  END IF;

  rejected := false;
  BEGIN
    PERFORM public.finish_document_processing_ai_extraction(processing_a,processing_lease,source_a,source_lease,'validated',1,1,1,jsonb_build_array(anchored_table_candidate || jsonb_build_object('evidence_regions',jsonb_build_array(jsonb_build_object('x',0.1,'y',0.1,'width',0.1,'height',0.1)))),false,'{"doc_type":"OTHER","direction":"incoming"}'::jsonb);
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected OR (SELECT analysis_state FROM public.source_analysis_runs WHERE id=source_a) <> 'running' THEN
    RAISE EXCEPTION 'forged table-cell geometry changed terminal provenance';
  END IF;

  rejected := false;
  BEGIN
    PERFORM public.finish_document_processing_ai_extraction(processing_a,processing_lease,source_a,source_lease,'validated',1,1,1,jsonb_build_array(anchored_table_candidate || jsonb_build_object(
      'verified_source_anchor',jsonb_build_object('char_start',19,'char_end',30,'token_start',NULL,'token_end',NULL,'table_cell',jsonb_build_object('table_index',0,'row_index',1,'column_index',2)),
      'evidence_regions',jsonb_build_array(jsonb_build_object('x',0.7,'y',0.3,'width',0.2,'height',0.05))
    )),false,'{"doc_type":"OTHER","direction":"incoming"}'::jsonb);
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected OR (SELECT analysis_state FROM public.source_analysis_runs WHERE id=source_a) <> 'running' THEN
    RAISE EXCEPTION 'unrelated canonical table cell changed terminal provenance';
  END IF;

  rejected := false;
  BEGIN
    PERFORM public.finish_document_processing_ai_extraction(processing_a,processing_lease,source_a,source_lease,'validated',1,1,1,jsonb_build_array(anchored_candidate - 'verified_source_anchor'),false,'{"doc_type":"OTHER","direction":"incoming"}'::jsonb);
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected OR (SELECT analysis_state FROM public.source_analysis_runs WHERE id=source_a) <> 'running' THEN
    RAISE EXCEPTION 'missing critical anchor changed terminal provenance';
  END IF;

  SELECT * INTO result FROM public.finish_document_processing_ai_extraction(processing_a,processing_lease,source_a,source_lease,'validated',1,1,1,jsonb_build_array(anchored_candidate,anchored_table_candidate),false,'{"doc_type":"OTHER","direction":"incoming"}'::jsonb);
  IF result.code <> 'validated' OR result.binding_id IS NULL THEN RAISE EXCEPTION 'anchored completion was not materialized atomically'; END IF;
  SELECT id INTO candidate_id FROM public.source_field_candidates WHERE source_analysis_run_id=source_a AND semantic_candidate_key='document.reference_number.abc123';
  IF candidate_id IS NULL OR (SELECT verified_source_anchor FROM public.source_field_candidates WHERE id=candidate_id) IS DISTINCT FROM anchored_candidate->'verified_source_anchor'
     OR NOT EXISTS (SELECT 1 FROM public.document_field_candidates WHERE source_field_candidate_id=candidate_id) THEN
    RAISE EXCEPTION 'completion did not persist the exact verified anchor and document materialization';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.source_field_candidates WHERE source_analysis_run_id=source_a AND semantic_candidate_key='financial.total_demand.1000' AND verified_source_anchor IS NOT DISTINCT FROM anchored_table_candidate->'verified_source_anchor' AND evidence_regions IS NOT DISTINCT FROM anchored_table_candidate->'evidence_regions') THEN
    RAISE EXCEPTION 'completion did not persist the exact canonical table-cell anchor';
  END IF;

  -- Date, code, and decimal values must resolve using the same formatting
  -- semantics as the TypeScript verifier, rather than literal quote equality.
  PERFORM public.materialize_verified_source_field_candidate(source_a,'deadline.due_date.2025-01-29','deadline.due_date','date','"2025-01-29"'::jsonb,1,'29.01.2025',NULL,0.95,'eligible',NULL,'{"char_start":39,"char_end":49,"token_start":null,"token_end":null,"table_cell":null}'::jsonb);
  IF NOT EXISTS (SELECT 1 FROM public.source_field_candidates WHERE source_analysis_run_id=source_a AND semantic_candidate_key='deadline.due_date.2025-01-29') THEN
    RAISE EXCEPTION 'semantic date normalization did not materialize';
  END IF;

  rejected := false;
  BEGIN
    PERFORM public.materialize_verified_source_field_candidate(source_a,'document.reference_number.wrong-value','document.reference_number','code','"ABC/124"'::jsonb,1,'Reference ABC/123','[{"x":0.1,"y":0.1,"width":0.2,"height":0.1},{"x":0.4,"y":0.1,"width":0.2,"height":0.1}]'::jsonb,0.95,'eligible',NULL,anchored_candidate->'verified_source_anchor');
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'mismatched normalized code was accepted by its canonical quote'; END IF;
  rejected := false;
  BEGIN
    PERFORM public.materialize_verified_source_field_candidate(source_a,'financial.total_demand.wrong-value','financial.total_demand','decimal','"1001"'::jsonb,1,'Total 1,000','[{"x":0.4,"y":0.3,"width":0.2,"height":0.05}]'::jsonb,0.95,'eligible',NULL,anchored_table_candidate->'verified_source_anchor');
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'mismatched normalized decimal was accepted by its canonical table cell'; END IF;
  rejected := false;
  BEGIN
    PERFORM public.materialize_verified_source_field_candidate(source_a,'deadline.due_date.wrong-value','deadline.due_date','date','"2025-01-30"'::jsonb,1,'29.01.2025',NULL,0.95,'eligible',NULL,'{"char_start":39,"char_end":49,"token_start":null,"token_end":null,"table_cell":null}'::jsonb);
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'mismatched normalized date was accepted by its canonical quote'; END IF;

  IF public.document_page_text_table_cells_are_safe('[{"table_index":0,"row_index":1,"column_index":1,"row_span":1,"column_span":1,"reading_order":3,"text":"Total 1,000","x":0.4,"y":0.3,"width":0.2,"height":0.05},{"table_index":0,"row_index":1,"column_index":1,"row_span":1,"column_span":1,"reading_order":4,"text":"Duplicate Total 1,000","x":0.7,"y":0.3,"width":0.2,"height":0.05}]'::jsonb) THEN
    RAISE EXCEPTION 'duplicate canonical table-cell coordinates were accepted';
  END IF;

  replay_id := public.materialize_verified_source_field_candidate(source_a,'document.reference_number.abc123','document.reference_number','code','"ABC/123"'::jsonb,1,'Reference ABC/123','[{"x":0.1,"y":0.1,"width":0.2,"height":0.1},{"x":0.4,"y":0.1,"width":0.2,"height":0.1}]'::jsonb,0.95,'eligible',NULL,anchored_candidate->'verified_source_anchor');
  IF replay_id IS DISTINCT FROM candidate_id THEN RAISE EXCEPTION 'exact anchored materialization did not replay'; END IF;
  rejected := false;
  BEGIN
    PERFORM public.materialize_verified_source_field_candidate(source_a,'document.reference_number.abc123','document.reference_number','code','"ABC/123"'::jsonb,1,'Reference ABC/123',NULL,0.95,'eligible',NULL,'{"char_start":0,"char_end":17,"token_start":null,"token_end":null}'::jsonb);
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'semantic replay accepted different verified anchor material'; END IF;
END $completion_contract$;

DO $strict_semantic_matching_contract$
DECLARE
  source_a uuid := '11790000-0000-0000-0000-000000000001';
  page_text constant text := 'Exact code ABC/123. Prefix code XABC/123. Repeated code DUP/1 and DUP/1. Exact text Finding. Prefix text Findings. Exact date 29 January 2025. Embedded dates 12025-01-29 X2025-01-29 2025-01-290. Exact amount 1,000. Prefix amount 1,000.50.';
  quote_text text; anchor jsonb; rejected boolean;
BEGIN
  quote_text := 'Exact code ABC/123';
  anchor := jsonb_build_object('char_start',strpos(page_text,quote_text)-1,'char_end',strpos(page_text,quote_text)-1+char_length(quote_text),'token_start',NULL,'token_end',NULL,'table_cell',NULL);
  PERFORM public.materialize_verified_source_field_candidate(source_a,'strict.code.valid','document.reference_number','code','"ABC/123"'::jsonb,2,quote_text,NULL,0.95,'eligible',NULL,anchor);

  quote_text := 'Exact text Finding';
  anchor := jsonb_build_object('char_start',strpos(page_text,quote_text)-1,'char_end',strpos(page_text,quote_text)-1+char_length(quote_text),'token_start',NULL,'token_end',NULL,'table_cell',NULL);
  PERFORM public.materialize_verified_source_field_candidate(source_a,'strict.text.valid','document.title','text','"Finding"'::jsonb,2,quote_text,NULL,0.95,'eligible',NULL,anchor);

  quote_text := 'Exact date 29 January 2025';
  anchor := jsonb_build_object('char_start',strpos(page_text,quote_text)-1,'char_end',strpos(page_text,quote_text)-1+char_length(quote_text),'token_start',NULL,'token_end',NULL,'table_cell',NULL);
  PERFORM public.materialize_verified_source_field_candidate(source_a,'strict.date.valid','deadline.due_date','date','"2025-01-29"'::jsonb,2,quote_text,NULL,0.95,'eligible',NULL,anchor);

  quote_text := 'Exact amount 1,000';
  anchor := jsonb_build_object('char_start',strpos(page_text,quote_text)-1,'char_end',strpos(page_text,quote_text)-1+char_length(quote_text),'token_start',NULL,'token_end',NULL,'table_cell',jsonb_build_object('table_index',0,'row_index',2,'column_index',1));
  PERFORM public.materialize_verified_source_field_candidate(source_a,'strict.decimal.valid','financial.total_demand','decimal','"1000"'::jsonb,2,quote_text,'[{"x":0.1,"y":0.5,"width":0.3,"height":0.05}]'::jsonb,0.95,'eligible',NULL,anchor);

  rejected := false;
  BEGIN
    quote_text := 'Prefix code XABC/123';
    anchor := jsonb_build_object('char_start',strpos(page_text,quote_text)-1,'char_end',strpos(page_text,quote_text)-1+char_length(quote_text),'token_start',NULL,'token_end',NULL,'table_cell',NULL);
    PERFORM public.materialize_verified_source_field_candidate(source_a,'strict.code.prefix','document.reference_number','code','"ABC/123"'::jsonb,2,quote_text,NULL,0.95,'eligible',NULL,anchor);
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'strict code matching accepted a prefixed source token'; END IF;

  rejected := false;
  BEGIN
    quote_text := 'Prefix text Findings';
    anchor := jsonb_build_object('char_start',strpos(page_text,quote_text)-1,'char_end',strpos(page_text,quote_text)-1+char_length(quote_text),'token_start',NULL,'token_end',NULL,'table_cell',NULL);
    PERFORM public.materialize_verified_source_field_candidate(source_a,'strict.text.prefix','document.title','text','"Finding"'::jsonb,2,quote_text,NULL,0.95,'eligible',NULL,anchor);
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'strict text matching accepted a prefixed source word'; END IF;

  rejected := false;
  BEGIN
    quote_text := 'Repeated code DUP/1 and DUP/1';
    anchor := jsonb_build_object('char_start',strpos(page_text,quote_text)-1,'char_end',strpos(page_text,quote_text)-1+char_length(quote_text),'token_start',NULL,'token_end',NULL,'table_cell',NULL);
    PERFORM public.materialize_verified_source_field_candidate(source_a,'strict.code.repeat','document.reference_number','code','"DUP/1"'::jsonb,2,quote_text,NULL,0.95,'eligible',NULL,anchor);
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'strict matching accepted repeated source values'; END IF;

  rejected := false;
  BEGIN
    quote_text := 'Prefix amount 1,000.50';
    anchor := jsonb_build_object('char_start',strpos(page_text,quote_text)-1,'char_end',strpos(page_text,quote_text)-1+char_length(quote_text),'token_start',NULL,'token_end',NULL,'table_cell',jsonb_build_object('table_index',0,'row_index',2,'column_index',2));
    PERFORM public.materialize_verified_source_field_candidate(source_a,'strict.decimal.prefix','financial.total_demand','decimal','"1000"'::jsonb,2,quote_text,'[{"x":0.5,"y":0.5,"width":0.4,"height":0.05}]'::jsonb,0.95,'eligible',NULL,anchor);
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'strict decimal matching accepted a fractional-prefix table cell'; END IF;
END $strict_semantic_matching_contract$;

DO $strict_date_token_boundary_contract$
DECLARE
  candidate constant jsonb := '"2025-01-29"'::jsonb;
  source_text text;
BEGIN
  FOREACH source_text IN ARRAY ARRAY[
    '2025-01-29',
    '29.01.2025',
    '29 January 2025',
    'January 29, 2025'
  ] LOOP
    IF public.source_field_candidate_value_match_count('date',candidate,source_text) <> 1 THEN
      RAISE EXCEPTION 'strict date matching rejected supported standalone date: %', source_text;
    END IF;
  END LOOP;

  FOREACH source_text IN ARRAY ARRAY[
    '12025-01-29',
    'X2025-01-29',
    '2025-01-290',
    '0001-01-29',
    'X29.01.2025',
    '29.01.2025X',
    'X29 January 2025',
    'January 29, 2025X'
  ] LOOP
    IF public.source_field_candidate_value_match_count('date',candidate,source_text) <> 0 THEN
      RAISE EXCEPTION 'strict date matching accepted an embedded source date: %', source_text;
    END IF;
  END LOOP;
END $strict_date_token_boundary_contract$;

SET LOCAL ROLE authenticated;
DO $browser_denied$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.finish_document_processing_ai_extraction('11770000-0000-0000-0000-000000000001','11780000-0000-0000-0000-000000000001','11790000-0000-0000-0000-000000000001','11790000-0000-0000-0000-000000000002','review_required',0,0,1,'[]'::jsonb,true,NULL);
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied OR has_function_privilege('authenticated','public.materialize_verified_source_field_candidate(uuid,text,text,public.source_field_candidate_value_type,jsonb,integer,text,jsonb,numeric,public.source_field_candidate_validation_state,text[],jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'browser role can execute verified candidate materialization';
  END IF;
END $browser_denied$;
RESET ROLE;

ROLLBACK;
