-- D09-T03 rollback fixture: typed observations are immutable, source-bound,
-- copy-safe candidates and produce no identity, relationship, placement or notification effects.
BEGIN;

DO $setup$
DECLARE
  actor uuid := '14910000-0000-0000-0000-000000000001'; actor_b uuid := '14910000-0000-0000-0000-000000000002'; org_a uuid := '14920000-0000-0000-0000-000000000001'; org_b uuid := '14920000-0000-0000-0000-000000000002';
  client_a uuid := '14930000-0000-0000-0000-000000000001'; client_b uuid := '14930000-0000-0000-0000-000000000002';
  matter_a uuid := '14940000-0000-0000-0000-000000000001'; matter_b uuid := '14940000-0000-0000-0000-000000000002';
  document_a uuid := '14950000-0000-0000-0000-000000000001'; document_copy uuid := '14950000-0000-0000-0000-000000000002'; document_b uuid := '14950000-0000-0000-0000-000000000003';
  asset_a uuid := '14960000-0000-0000-0000-000000000001'; asset_b uuid := '14960000-0000-0000-0000-000000000002';
  version_a uuid := '14970000-0000-0000-0000-000000000001'; version_copy uuid := '14970000-0000-0000-0000-000000000002'; version_b uuid := '14970000-0000-0000-0000-000000000003';
  run_a uuid := '14980000-0000-0000-0000-000000000001'; processing_a uuid := '14990000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000',actor,'authenticated','authenticated','typed-observation@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',actor_b,'authenticated','authenticated','typed-observation-b@example.test','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES (org_a,'Typed observations A',actor),(org_b,'Typed observations B',actor_b);
  INSERT INTO public.clients(id,org_id,name) VALUES (client_a,org_a,'Client A'),(client_b,org_b,'Client B');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES (matter_a,org_a,client_a,'Matter A'),(matter_b,org_b,client_b,'Matter B');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by) VALUES
    (document_a,org_a,matter_a,'fixture/a.pdf',actor),(document_copy,org_a,matter_a,'fixture/copy.pdf',actor),(document_b,org_b,matter_b,'fixture/b.pdf',actor);
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by) VALUES
    (asset_a,org_a,'documents','orgs/'||org_a||'/assets/'||asset_a||'/original.pdf',repeat('a',64),64,'application/pdf','available',now(),1,actor),
    (asset_b,org_b,'documents','orgs/'||org_b||'/assets/'||asset_b||'/original.pdf',repeat('b',64),64,'application/pdf','available',now(),1,actor);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by) VALUES
    (version_a,org_a,document_a,asset_a,1,'a.pdf',1,'valid','current',now(),now(),actor),
    (version_copy,org_a,document_copy,asset_a,1,'copy.pdf',1,'valid','current',now(),now(),actor),
    (version_b,org_b,document_b,asset_b,1,'b.pdf',1,'valid','current',now(),now(),actor);
  UPDATE public.documents SET current_version_id=version_a WHERE id=document_a;
  UPDATE public.documents SET current_version_id=version_copy WHERE id=document_copy;
  UPDATE public.documents SET current_version_id=version_b WHERE id=document_b;
  INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
  VALUES(processing_a,org_a,document_a,version_a,'full','fixture.typed-observations','running','extracting',now(),'14990000-0000-0000-0000-000000000002',now()+interval '10 minutes',now());
  INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at,completed_at)
  VALUES(run_a,org_a,asset_a,'ai_extraction.'||processing_a::text,'ai_extraction.'||processing_a::text,'ai_extraction','running','running','vertex-ai','gemini-2.5-flash','fixture-model','v3.0','document-extraction-v3','gst-document-and-official-reference-catalogue-v2','typed-period-reference-normalizer-v2',now()-interval '1 minute',NULL);
  UPDATE public.source_analysis_runs SET attempt_count=1,lease_token='14980000-0000-0000-0000-000000000002',lease_expires_at=now()+interval '10 minutes',heartbeat_at=now() WHERE id=run_a;
  INSERT INTO public.source_analysis_attempts(org_id,source_analysis_run_id,attempt_number,state,retry_reason,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at)
  VALUES(org_a,run_a,1,'running','initial','vertex-ai','gemini-2.5-flash','fixture-model','v3.0','document-extraction-v3','gst-document-and-official-reference-catalogue-v2','typed-period-reference-normalizer-v2',now());
  INSERT INTO public.document_page_text_artifacts(org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,content_fingerprint)
  VALUES(org_a,document_a,version_a,processing_a,run_a,'ready',1,repeat('c',64));
  INSERT INTO public.document_page_text_pages(org_id,artifact_id,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages)
  SELECT org_a,id,1,'Tax period JAN 2020. Notice SCN / 01. Against OIO / 09.','[]','[]',repeat('d',64),'native_pdf','native-pdf-quality-v1','{}','{}'
  FROM public.document_page_text_artifacts WHERE source_analysis_run_id=run_a;
END $setup$;

DO $contract$
DECLARE
  run_a uuid := '14980000-0000-0000-0000-000000000001'; version_a uuid := '14970000-0000-0000-0000-000000000001'; version_copy uuid := '14970000-0000-0000-0000-000000000002'; version_b uuid := '14970000-0000-0000-0000-000000000003';
  period jsonb := '{"kind":"month","raw":"JAN 2020","display":"January 2020","precision":"month","segments":[{"kind":"month","month":"2020-01","quarter":null,"financial_year":null,"start_date":null,"end_date":null}],"financial_years":["2019-20"],"printed_financial_years":["2020-21"],"derived_financial_years":["2019-20"],"conflict":true,"catalogue_version":"gst-document-and-official-reference-catalogue-v2","normalizer_version":"typed-period-reference-normalizer-v2"}';
  self_ref jsonb := '{"role":"self_identifier","kind":"notice_reference","completeness":"complete","namespace":"cbic . gst","namespace_normalized":"CBIC.GST","raw":"SCN / 01","display":"SCN/01","normalized_value":"SCN/01","components":{"kind":"notice_reference","segments":["SCN","01"],"prefix":"SCN","numericCore":"01"},"match_eligible":true,"catalogue_version":"gst-document-and-official-reference-catalogue-v2","normalizer_version":"typed-period-reference-normalizer-v2"}';
  outbound_ref jsonb := '{"role":"outbound_mention","kind":"order_reference","completeness":"complete","namespace":"cbic.gst","namespace_normalized":"CBIC.GST","raw":"OIO / 09","display":"OIO/09","normalized_value":"OIO/09","components":{"kind":"order_reference","segments":["OIO","09"],"prefix":"OIO","numericCore":"09"},"match_eligible":true,"catalogue_version":"gst-document-and-official-reference-catalogue-v2","normalizer_version":"typed-period-reference-normalizer-v2"}';
  reordered_period jsonb := '{"kind":"multi_financial_year","raw":"FY 2022-23 and FY 2021-22","display":"FY 2022-23 and FY 2021-22","precision":"financial_year","segments":[{"kind":"financial_year","month":null,"quarter":null,"financial_year":"2022-23","start_date":null,"end_date":null},{"kind":"financial_year","month":null,"quarter":null,"financial_year":"2021-22","start_date":null,"end_date":null}],"financial_years":["2022-23","2021-22"],"printed_financial_years":["2021-22","2022-23"],"derived_financial_years":["2022-23","2021-22"],"conflict":false,"catalogue_version":"gst-document-and-official-reference-catalogue-v2","normalizer_version":"typed-period-reference-normalizer-v2"}';
  period_id uuid; self_id uuid; outbound_id uuid; binding_a uuid; binding_copy uuid; replay uuid; rejected boolean; finish_result record;
  identities_before bigint; links_before bigint; relationships_before bigint; outbox_before bigint;
BEGIN
  SELECT count(*) INTO identities_before FROM public.matter_identifiers; SELECT count(*) INTO links_before FROM public.document_links;
  SELECT count(*) INTO relationships_before FROM public.document_relationships; SELECT count(*) INTO outbox_before FROM public.outbox_events;
  SELECT * INTO finish_result FROM public.finish_document_processing_ai_extraction(
    '14990000-0000-0000-0000-000000000001','14990000-0000-0000-0000-000000000002',run_a,'14980000-0000-0000-0000-000000000002',
    'validated',1,1,1,jsonb_build_array(
      jsonb_build_object('semantic_candidate_key','tax_period:11111111111111111111111111111111','field_path','document.tax_period','value_type','structured','normalized_value',period,'page_number',1,'quotation','Tax period JAN 2020','evidence_regions',NULL,'confidence',0.96,'validation_state','conflicting','validation_error_codes',NULL,'verified_source_anchor','{"char_start":0,"char_end":19,"token_start":null,"token_end":null,"table_cell":null}'::jsonb),
      jsonb_build_object('semantic_candidate_key','official_reference:self_identifier:22222222222222222222222222222222','field_path','document.official_reference.self_identifier','value_type','structured','normalized_value',self_ref,'page_number',1,'quotation','Notice SCN / 01','evidence_regions',NULL,'confidence',0.99,'validation_state','provisional','validation_error_codes',NULL,'verified_source_anchor','{"char_start":21,"char_end":36,"token_start":null,"token_end":null,"table_cell":null}'::jsonb),
      jsonb_build_object('semantic_candidate_key','official_reference:outbound_mention:33333333333333333333333333333333','field_path','document.official_reference.outbound_mention','value_type','structured','normalized_value',outbound_ref,'page_number',1,'quotation','Against OIO / 09','evidence_regions',NULL,'confidence',0.97,'validation_state','provisional','validation_error_codes',NULL,'verified_source_anchor','{"char_start":38,"char_end":54,"token_start":null,"token_end":null,"table_cell":null}'::jsonb)
    ),true,'{"doc_type":"SCN","reference_number":"SCN/01","direction":"incoming","financial_years":["2019-20"],"summary":"Synthetic","prompt_version":"v3.0"}'::jsonb);
  IF finish_result.code<>'review_required' OR finish_result.binding_id IS NULL THEN RAISE EXCEPTION 'legacy finisher did not atomically accept typed candidates: %',finish_result.code; END IF;
  SELECT id INTO period_id FROM public.source_field_candidates WHERE source_analysis_run_id=run_a AND semantic_candidate_key LIKE 'tax_period:%';
  SELECT id INTO self_id FROM public.source_field_candidates WHERE source_analysis_run_id=run_a AND field_path='document.official_reference.self_identifier';
  SELECT id INTO outbound_id FROM public.source_field_candidates WHERE source_analysis_run_id=run_a AND field_path='document.official_reference.outbound_mention';
  replay:=public.materialize_verified_source_field_candidate(run_a,'official_reference:self_identifier:22222222222222222222222222222222','document.official_reference.self_identifier','structured',self_ref,1,'Notice SCN / 01',NULL,0.99,'provisional',NULL,'{"char_start":21,"char_end":36,"token_start":null,"token_end":null,"table_cell":null}');
  IF replay IS DISTINCT FROM self_id OR period_id IS NULL OR outbound_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.source_field_candidates WHERE id=period_id AND raw_value='JAN 2020' AND display_value='January 2020'
      AND value_precision='month' AND catalogue_version='gst-document-and-official-reference-catalogue-v2'
      AND normalizer_version='typed-period-reference-normalizer-v2'
  ) THEN RAISE EXCEPTION 'typed observation replay/materialization failed'; END IF;
  binding_a:=finish_result.binding_id;
  binding_copy:=public.materialize_document_version_analysis(version_copy,run_a,'copy',NULL);
  IF binding_a=binding_copy OR (SELECT count(*) FROM public.document_field_candidates WHERE source_field_candidate_id IN(period_id,self_id,outbound_id))<>6 THEN RAISE EXCEPTION 'source observations did not bind/copy exactly'; END IF;
  rejected:=false; BEGIN PERFORM public.materialize_document_version_analysis(version_b,run_a,'copy',NULL); EXCEPTION WHEN others THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'cross-tenant candidate binding was accepted'; END IF;
  rejected:=false; BEGIN PERFORM public.materialize_verified_source_field_candidate(run_a,'tax_period:bad','document.tax_period','structured',period||'{"start_date":"2020-01-01"}',1,'Tax period JAN 2020',NULL,0.96,'conflicting',NULL,'{"char_start":0,"char_end":19,"token_start":null,"token_end":null,"table_cell":null}'); EXCEPTION WHEN others THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'unknown structured tax-period key was accepted'; END IF;
  rejected:=false; BEGIN PERFORM public.materialize_verified_source_field_candidate(run_a,'official_reference:false-components','document.official_reference.self_identifier','structured',jsonb_set(self_ref,'{components,year}','"9999"'),1,'Notice SCN / 01',NULL,0.9,'invalid',ARRAY['fixture'],NULL); EXCEPTION WHEN others THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'provider-forged official-reference components were accepted'; END IF;
  rejected:=false; BEGIN PERFORM public.materialize_verified_source_field_candidate(run_a,'official_reference:null-raw','document.official_reference.self_identifier','structured',jsonb_set(self_ref,'{raw}','null'),1,'Notice SCN / 01',NULL,0.9,'invalid',ARRAY['fixture'],NULL); EXCEPTION WHEN others THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'JSON-null required official-reference scalar was accepted'; END IF;
  rejected:=false; BEGIN PERFORM public.materialize_verified_source_field_candidate(run_a,'official_reference:wrong-components-type','document.official_reference.self_identifier','structured',jsonb_set(self_ref,'{components}','[]'),1,'Notice SCN / 01',NULL,0.9,'invalid',ARRAY['fixture'],NULL); EXCEPTION WHEN others THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'wrong-type official-reference components were accepted'; END IF;
  rejected:=false; BEGIN PERFORM public.materialize_verified_source_field_candidate(run_a,'tax_period:forged-derived','document.tax_period','structured',jsonb_set(period,'{derived_financial_years}','["2020-21"]'),1,'Tax period JAN 2020',NULL,0.9,'invalid',ARRAY['fixture'],NULL); EXCEPTION WHEN others THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'forged derived financial years were accepted'; END IF;
  rejected:=false; BEGIN PERFORM public.materialize_verified_source_field_candidate(run_a,'tax_period:forged-conflict','document.tax_period','structured',jsonb_set(period,'{conflict}','false'),1,'Tax period JAN 2020',NULL,0.9,'invalid',ARRAY['fixture'],NULL); EXCEPTION WHEN others THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'forged period conflict flag was accepted'; END IF;
  rejected:=false; BEGIN PERFORM public.materialize_verified_source_field_candidate(run_a,'tax_period:null-display','document.tax_period','structured',jsonb_set(period,'{display}','null'),1,'Tax period JAN 2020',NULL,0.9,'invalid',ARRAY['fixture'],NULL); EXCEPTION WHEN others THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'JSON-null required tax-period scalar was accepted'; END IF;
  PERFORM public.materialize_verified_source_field_candidate(run_a,'tax_period:reordered-set','document.tax_period','structured',reordered_period,1,'FY 2022-23 and FY 2021-22',NULL,0.9,'invalid',ARRAY['fixture'],NULL);
  PERFORM public.materialize_verified_source_field_candidate(run_a,'official_reference:unicode-parity','document.official_reference.self_identifier','structured',self_ref||'{"raw":"ＳＣＮ ‐ 001 / 2026","display":"SCN-001/2026","normalized_value":"SCN-001/2026","components":{"kind":"notice_reference","segments":["SCN","001","2026"],"prefix":"SCN","numericCore":"001","year":"2026"}}',1,'Notice SCN / 01',NULL,0.9,'invalid',ARRAY['fixture'],NULL);
  PERFORM public.materialize_verified_source_field_candidate(run_a,'official_reference:outbound-role-duplicate','document.official_reference.outbound_mention','structured',self_ref||'{"role":"outbound_mention"}',1,'Notice SCN / 01',NULL,0.9,'invalid',ARRAY['fixture'],NULL);
  PERFORM public.materialize_verified_source_field_candidate(run_a,'official_reference:partial','document.official_reference.self_identifier','structured',self_ref||'{"completeness":"partial","namespace":null,"namespace_normalized":null,"match_eligible":false}',1,'Notice SCN / 01',NULL,0.9,'invalid',ARRAY['fixture'],NULL);
  PERFORM public.materialize_verified_source_field_candidate(run_a,'official_reference:other','document.official_reference.outbound_mention','structured',outbound_ref||'{"kind":"other_official_reference","components":{"kind":"other_official_reference","segments":["OIO","09"],"prefix":"OIO","numericCore":"09"},"match_eligible":false}',1,'Against OIO / 09',NULL,0.9,'invalid',ARRAY['fixture'],NULL);
  IF (SELECT count(*) FROM public.source_field_candidates WHERE source_analysis_run_id=run_a AND normalized_value->>'match_eligible'='false')<>2 THEN RAISE EXCEPTION 'non-matchable observations were not retained'; END IF;
  rejected:=false; BEGIN UPDATE public.source_field_candidates SET normalized_value=self_ref WHERE id=period_id; EXCEPTION WHEN others THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'source structured observation was mutable'; END IF;
  rejected:=false; BEGIN DELETE FROM public.document_field_candidates WHERE source_field_candidate_id=self_id; EXCEPTION WHEN others THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'document structured candidate was deletable'; END IF;
  IF (SELECT count(*) FROM public.matter_identifiers)<>identities_before OR (SELECT count(*) FROM public.document_links)<>links_before
    OR (SELECT count(*) FROM public.document_relationships)<>relationships_before OR (SELECT count(*) FROM public.outbox_events)<>outbox_before THEN
    RAISE EXCEPTION 'typed extraction candidates created a prohibited identity/relationship/notification effect'; END IF;
END $contract$;

SET LOCAL ROLE authenticated;
DO $direct_dml_denied$ DECLARE rejected boolean:=false; BEGIN
  BEGIN INSERT INTO public.source_field_candidates(org_id,source_analysis_run_id,asset_id,semantic_candidate_key,field_path,value_type,normalized_value,page_number,evidence_page_count,quotation,confidence,validation_state)
    VALUES('14920000-0000-0000-0000-000000000001','14980000-0000-0000-0000-000000000001','14960000-0000-0000-0000-000000000001','tax_period:forged','document.tax_period','structured','{}',1,1,'forged',0.9,'provisional');
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'authenticated direct candidate DML was accepted'; END IF;
END $direct_dml_denied$;
RESET ROLE;

DO $surface$ BEGIN
  IF has_table_privilege('authenticated','public.source_field_candidates','SELECT') OR has_table_privilege('service_role','public.source_field_candidates','INSERT')
    OR NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='source_official_reference_lookup_idx')
    OR NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='document_official_reference_lookup_idx')
    OR EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname IN ('source_official_reference_lookup_idx','document_official_reference_lookup_idx')
      AND (indexdef NOT LIKE '%match_eligible%' OR indexdef NOT LIKE '%other_official_reference%' OR indexdef NOT LIKE '%namespace_normalized%')) THEN
    RAISE EXCEPTION 'typed observation authority/index surface is unsafe'; END IF;
END $surface$;

ROLLBACK;
