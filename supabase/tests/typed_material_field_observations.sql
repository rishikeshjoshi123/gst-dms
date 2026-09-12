-- D09-T04 rollback fixture: structured material observations retain exact
-- evidence and copy/replay safely without activating any domain consequence.
BEGIN;

DO $fixture$
DECLARE
  actor uuid:='15010000-0000-0000-0000-000000000001'; actor_b uuid:='15010000-0000-0000-0000-000000000002';
  org uuid:='15020000-0000-0000-0000-000000000001'; org_b uuid:='15020000-0000-0000-0000-000000000002';
  client uuid:='15030000-0000-0000-0000-000000000001'; client_b uuid:='15030000-0000-0000-0000-000000000002';
  matter uuid:='15040000-0000-0000-0000-000000000001'; matter_b uuid:='15040000-0000-0000-0000-000000000002';
  document uuid:='15050000-0000-0000-0000-000000000001'; document_copy uuid:='15050000-0000-0000-0000-000000000002'; document_b uuid:='15050000-0000-0000-0000-000000000003';
  asset uuid:='15060000-0000-0000-0000-000000000001'; asset_b uuid:='15060000-0000-0000-0000-000000000002';
  version uuid:='15070000-0000-0000-0000-000000000001'; version_copy uuid:='15070000-0000-0000-0000-000000000002'; version_b uuid:='15070000-0000-0000-0000-000000000003';
  run uuid:='15080000-0000-0000-0000-000000000001'; processing uuid:='15090000-0000-0000-0000-000000000001';
  processing_lease uuid:='15090000-0000-0000-0000-000000000002'; source_lease uuid:='15080000-0000-0000-0000-000000000002';
  issuer_run uuid:='15080000-0000-0000-0000-000000000003'; issuer_source_lease uuid:='15080000-0000-0000-0000-000000000004';
  issuer_processing uuid:='15090000-0000-0000-0000-000000000003'; issuer_processing_lease uuid:='15090000-0000-0000-0000-000000000004';
  page_text text:='27AAPFU0939F1ZV. 27AAPFU0939F1ZU. 30 January 2025. Deputy Commissioner, GST Department, Division I, Mumbai. Example Private Limited. ₹ 9,007,199,254,740,993,123.67. Section 73 of CGST Act.';
  catalogue constant text:='gst-legal-material-observation-catalogue-v3'; normalizer constant text:='typed-material-observation-normalizer-v3';
  gstin jsonb; invalid_gstin jsonb; legal_date jsonb; issuer jsonb; recipient jsonb; party jsonb; money jsonb; provision jsonb; forged_provision jsonb; pan_zwsp jsonb;
  candidates jsonb:='[]'; issuer_candidates jsonb; item jsonb; raw text; quote_text text; key text; path text; state text; errors jsonb; start_at integer; finish record;
  source_ids uuid[]; binding_copy uuid; replay uuid; rejected boolean;
  identifiers_before bigint; links_before bigint; relationships_before bigint; effective_before bigint; outbox_before bigint;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
    ('00000000-0000-0000-0000-000000000000',actor,'authenticated','authenticated','material@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',actor_b,'authenticated','authenticated','material-b@example.test','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES(org,'Material A',actor),(org_b,'Material B',actor_b);
  INSERT INTO public.clients(id,org_id,name) VALUES(client,org,'Client A'),(client_b,org_b,'Client B');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES(matter,org,client,'Matter A'),(matter_b,org_b,client_b,'Matter B');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by) VALUES
    (document,org,matter,'fixture/material.pdf',actor),(document_copy,org,matter,'fixture/material-copy.pdf',actor),(document_b,org_b,matter_b,'fixture/material-b.pdf',actor_b);
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by) VALUES
    (asset,org,'documents','orgs/'||org||'/assets/'||asset||'/original.pdf',repeat('e',64),64,'application/pdf','available',now(),1,actor),
    (asset_b,org_b,'documents','orgs/'||org_b||'/assets/'||asset_b||'/original.pdf',repeat('f',64),64,'application/pdf','available',now(),1,actor_b);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by) VALUES
    (version,org,document,asset,1,'material.pdf',1,'valid','current',now(),now(),actor),
    (version_copy,org,document_copy,asset,1,'copy.pdf',1,'valid','current',now(),now(),actor),
    (version_b,org_b,document_b,asset_b,1,'b.pdf',1,'valid','current',now(),now(),actor_b);
  UPDATE public.documents SET current_version_id=version WHERE id=document;
  UPDATE public.documents SET current_version_id=version_copy WHERE id=document_copy;
  UPDATE public.documents SET current_version_id=version_b WHERE id=document_b;
  INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
    VALUES(processing,org,document,version,'full','fixture.material','running','extracting',now(),processing_lease,now()+interval '10 minutes',now());
  INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at)
    VALUES(run,org,asset,'ai_extraction.'||processing,'ai_extraction.'||processing,'ai_extraction','running','running','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4',catalogue,normalizer,now());
  UPDATE public.source_analysis_runs SET attempt_count=1,lease_token=source_lease,lease_expires_at=now()+interval '10 minutes',heartbeat_at=now() WHERE id=run;
  INSERT INTO public.source_analysis_attempts(org_id,source_analysis_run_id,attempt_number,state,retry_reason,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at)
    VALUES(org,run,1,'running','initial','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4',catalogue,normalizer,now());
  INSERT INTO public.document_page_text_artifacts(org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,content_fingerprint)
    VALUES(org,document,version,processing,run,'ready',1,repeat('1',64));
  INSERT INTO public.document_page_text_pages(org_id,artifact_id,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages)
    SELECT org,id,1,page_text,'[]','[]',repeat('2',64),'native_pdf','native-pdf-quality-v1','{}','{}' FROM public.document_page_text_artifacts WHERE source_analysis_run_id=run;

  gstin:=jsonb_build_object('kind','gstin','catalogue_kind',NULL,'raw','27AAPFU0939F1ZV','display','27AAPFU0939F1ZV','precision','exact','normalized_value','27AAPFU0939F1ZV','normalization_state','valid','validation_error',NULL,'catalogue_version',catalogue,'normalizer_version',normalizer);
  invalid_gstin:=jsonb_build_object('kind','gstin','catalogue_kind',NULL,'raw','27AAPFU0939F1ZU','display','27AAPFU0939F1ZU','precision','exact','normalized_value',NULL,'normalization_state','invalid','validation_error','invalid_gstin','catalogue_version',catalogue,'normalizer_version',normalizer);
  legal_date:=jsonb_build_object('meaning','issue','proposed_normalized_date','2025-01-30','normalized_date','2025-01-30','raw','30 January 2025','display','30 January 2025','precision','exact','normalization_state','valid','validation_error',NULL,'catalogue_version',catalogue,'normalizer_version',normalizer);
  issuer:=jsonb_build_object('actor_kind','issuer','procedural_role','authority','authority','GST Department','office','Division I','jurisdiction','Mumbai','raw','Deputy Commissioner','display','Deputy Commissioner','precision','exact','normalized',jsonb_build_object('procedural_role','authority','authority','GST Department','office','Division I','jurisdiction','Mumbai'),'normalization_state','valid','validation_error',NULL,'catalogue_version',catalogue,'normalizer_version',normalizer);
  recipient:=jsonb_build_object('actor_kind','recipient','procedural_role','taxpayer','authority',NULL,'office',NULL,'jurisdiction',NULL,'raw','Example Private Limited','display','Example Private Limited','precision','exact','normalized',jsonb_build_object('procedural_role','taxpayer','authority',NULL,'office',NULL,'jurisdiction',NULL),'normalization_state','valid','validation_error',NULL,'catalogue_version',catalogue,'normalizer_version',normalizer);
  party:=jsonb_build_object('procedural_role','taxpayer','raw','Example Private Limited','display','Example Private Limited','precision','exact','normalized',jsonb_build_object('name','Example Private Limited','procedural_role','taxpayer'),'normalization_state','valid','validation_error',NULL,'catalogue_version',catalogue,'normalizer_version',normalizer);
  money:=jsonb_build_object('representation','decimal','amount','9007199254740993123.67','currency','INR','component','tax','applicable_period_reference',NULL,'legal_posture','alleged','raw','₹ 9,007,199,254,740,993,123.67','display','₹ 9,007,199,254,740,993,123.67','precision','exact','normalized',jsonb_build_object('representation','decimal','value','9007199254740993123.67','currency','INR','component','tax','applicable_period_reference',NULL,'legal_posture','alleged'),'normalization_state','valid','validation_error',NULL,'catalogue_version',catalogue,'normalizer_version',normalizer);
  provision:=jsonb_build_object('act_kind','cgst_act','act','CGST Act','provision_kind','section','provision_value','73','raw','Section 73 of CGST Act','display','Section 73 of CGST Act','precision','exact','normalized',jsonb_build_object('act_kind','cgst_act','act','CGST Act','provision_kind','section','value','73','components',jsonb_build_array('73')),'normalization_state','valid','validation_error',NULL,'catalogue_version',catalogue,'normalizer_version',normalizer);
  pan_zwsp:=jsonb_build_object('kind','pan','catalogue_kind',NULL,'raw','AB'||chr(65279)||'CDE1234F','display','AB'||chr(65279)||'CDE1234F','precision','exact','normalized_value','ABCDE1234F','normalization_state','valid','validation_error',NULL,'catalogue_version',catalogue,'normalizer_version',normalizer);

  FOREACH item IN ARRAY ARRAY[
    jsonb_set(issuer,'{actor_kind}','null'),jsonb_set(issuer,'{actor_kind}','{}'),
    jsonb_set(issuer,'{procedural_role}','null'),jsonb_set(issuer,'{procedural_role}','{}'),
    jsonb_set(issuer,'{normalized,procedural_role}','null'),jsonb_set(issuer,'{normalized,authority}','{}')
  ] LOOP
    IF public.typed_actor_candidate_is_valid(item) IS NOT FALSE THEN RAISE EXCEPTION 'malformed actor returned true or null'; END IF;
  END LOOP;
  FOREACH item IN ARRAY ARRAY[
    jsonb_set(party,'{procedural_role}','null'),jsonb_set(party,'{procedural_role}','{}'),
    jsonb_set(party,'{normalized,name}','null'),jsonb_set(party,'{normalized,procedural_role}','{}')
  ] LOOP
    IF public.typed_party_candidate_is_valid(item) IS NOT FALSE THEN RAISE EXCEPTION 'malformed party returned true or null'; END IF;
  END LOOP;
  FOREACH item IN ARRAY ARRAY[
    jsonb_set(money,'{representation}','null'),jsonb_set(money,'{representation}','{}'),
    jsonb_set(money,'{amount}','null'),jsonb_set(money,'{amount}','{}'),
    jsonb_set(money,'{currency}','null'),jsonb_set(money,'{currency}','{}'),
    jsonb_set(money,'{component}','null'),jsonb_set(money,'{component}','{}'),
    jsonb_set(money,'{legal_posture}','null'),jsonb_set(money,'{legal_posture}','{}'),
    jsonb_set(money,'{normalized,value}','null'),jsonb_set(money,'{normalized,currency}','{}')
  ] LOOP
    IF public.typed_money_candidate_is_valid(item) IS NOT FALSE THEN RAISE EXCEPTION 'malformed money returned true or null'; END IF;
  END LOOP;
  FOREACH item IN ARRAY ARRAY[
    jsonb_set(provision,'{act_kind}','null'),jsonb_set(provision,'{act_kind}','{}'),
    jsonb_set(provision,'{provision_kind}','null'),jsonb_set(provision,'{provision_kind}','{}'),
    jsonb_set(provision,'{provision_value}','null'),jsonb_set(provision,'{provision_value}','{}'),
    jsonb_set(provision,'{normalized,value}','null'),jsonb_set(provision,'{normalized,components}','{}')
  ] LOOP
    IF public.typed_legal_provision_candidate_is_valid(item) IS NOT FALSE THEN RAISE EXCEPTION 'malformed legal provision returned true or null'; END IF;
  END LOOP;
  item:=jsonb_set(jsonb_set(issuer,'{authority}',to_jsonb('ＧＳＴ Department'::text)),'{normalized,authority}',to_jsonb('ＧＳＴ Department'::text));
  IF public.source_field_candidate_value_match_count('structured',item,'Deputy Commissioner, GST Department, Division I, Mumbai')<>1 THEN
    RAISE EXCEPTION 'actor NFKC source-match parity failed';
  END IF;
  IF NOT public.typed_client_identifier_candidate_is_valid(pan_zwsp)
    OR public.source_field_candidate_value_match_count('structured',pan_zwsp,'AB'||chr(65279)||'CDE1234F')<>1 THEN
    RAISE EXCEPTION 'identifier U+FEFF normalization parity failed';
  END IF;
  forged_provision:=jsonb_set(jsonb_set(jsonb_set(jsonb_set(provision,'{act_kind}','"igst_act"'),'{act}','"IGST Act"'),'{normalized,act_kind}','"igst_act"'),'{normalized,act}','"IGST Act"');
  IF public.source_field_candidate_value_match_count('structured',forged_provision,provision->>'raw')<>0 THEN
    RAISE EXCEPTION 'forged legal act identity resolved against a different source Act';
  END IF;
  item:=jsonb_set(jsonb_set(provision,'{act}',to_jsonb('ＣＧＳＴ Act'::text)),'{normalized,act}',to_jsonb('ＣＧＳＴ Act'::text));
  IF public.source_field_candidate_value_match_count('structured',item,provision->>'raw')<>1 THEN
    RAISE EXCEPTION 'legal Act NFKC source-match parity failed';
  END IF;

  FOR item,key,path,state,errors IN SELECT * FROM (VALUES
    (gstin,'client_identifier:11111111111111111111111111111111','document.client_identifier.gstin','provisional',NULL::jsonb),
    (invalid_gstin,'client_identifier:22222222222222222222222222222222','document.client_identifier.gstin','invalid','["invalid_gstin"]'::jsonb),
    (legal_date,'legal_date:33333333333333333333333333333333','document.legal_date.issue','provisional',NULL::jsonb),
    (issuer,'actor:44444444444444444444444444444444','document.actor.issuer','provisional',NULL::jsonb),
    (recipient,'actor:88888888888888888888888888888888','document.actor.recipient','provisional',NULL::jsonb),
    (party,'party:55555555555555555555555555555555','document.party.taxpayer','provisional',NULL::jsonb),
    (money,'money:66666666666666666666666666666666','document.money.tax','provisional',NULL::jsonb),
    (provision,'legal_provision:77777777777777777777777777777777','document.legal_provision.section','provisional',NULL::jsonb)
  ) valueset(item,key,path,state,errors) LOOP
    raw:=CASE WHEN path='document.legal_date.issue' THEN item->>'normalized_date' WHEN path='document.money.tax' THEN item->>'amount' WHEN path='document.client_identifier.gstin' AND item->>'normalized_value' IS NOT NULL THEN item->>'normalized_value' ELSE item->>'raw' END;
    quote_text:=CASE WHEN path='document.actor.issuer' THEN 'Deputy Commissioner, GST Department, Division I, Mumbai' ELSE item->>'raw' END;
    start_at:=strpos(page_text,quote_text)-1;
    candidates:=candidates||jsonb_build_array(jsonb_build_object('semantic_candidate_key',key,'field_path',path,'value_type','structured','normalized_value',item,'page_number',1,'quotation',quote_text,'evidence_regions',NULL,'confidence',0.96,'validation_state',state,'validation_error_codes',errors,'verified_source_anchor',jsonb_build_object('char_start',start_at,'char_end',start_at+char_length(quote_text),'token_start',NULL,'token_end',NULL,'table_cell',NULL)));
  END LOOP;

  rejected:=false; BEGIN
    PERFORM public.finish_document_processing_ai_extraction(processing,processing_lease,run,source_lease,'validated',1,1,1,jsonb_set(candidates,'{0,unknown_key}','true'),true,'{}');
  EXCEPTION WHEN others THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'v4 candidate envelope accepted an unknown key'; END IF;
  rejected:=false; BEGIN
    PERFORM public.finish_document_processing_ai_extraction(processing,processing_lease,run,source_lease,'validated',1,1,1,candidates#-'{0,quotation}',true,'{}');
  EXCEPTION WHEN others THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'v4 candidate envelope accepted a missing key'; END IF;

  rejected:=false;
  BEGIN
    PERFORM public.materialize_verified_source_field_candidate(run,'client_identifier:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','document.client_identifier.gstin','structured',gstin,1,gstin->>'raw',NULL,.9,'eligible',NULL,
      jsonb_build_object('char_start',strpos(page_text,gstin->>'raw')-1,'char_end',strpos(page_text,gstin->>'raw')-1+char_length(gstin->>'raw'),'token_start',NULL,'token_end',NULL,'table_cell',NULL));
  EXCEPTION WHEN others THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'eligible material candidate bypassed provisional consequence fence'; END IF;
  forged_provision:=jsonb_set(jsonb_set(jsonb_set(provision,'{provision_value}','"74"'),'{normalized,value}','"74"'),'{normalized,components}','["74"]');
  rejected:=false; BEGIN PERFORM public.materialize_verified_source_field_candidate(run,'legal_provision:99999999999999999999999999999999','document.legal_provision.section','structured',forged_provision,1,provision->>'raw',NULL,.9,'provisional',NULL,jsonb_build_object('char_start',strpos(page_text,provision->>'raw')-1,'char_end',strpos(page_text,provision->>'raw')-1+char_length(provision->>'raw'),'token_start',NULL,'token_end',NULL,'table_cell',NULL)); EXCEPTION WHEN others THEN rejected:=true; END; IF NOT rejected THEN RAISE EXCEPTION 'forged legal provision normalization accepted against different source value'; END IF;

  SELECT count(*) INTO identifiers_before FROM public.matter_identifiers; SELECT count(*) INTO links_before FROM public.document_links;
  SELECT count(*) INTO relationships_before FROM public.document_relationships; SELECT count(*) INTO effective_before FROM public.document_effective_metadata; SELECT count(*) INTO outbox_before FROM public.outbox_events;
  SELECT * INTO finish FROM public.finish_document_processing_ai_extraction(processing,processing_lease,run,source_lease,'validated',1,1,1,candidates,true,
    jsonb_build_object('doc_type','SCN','reference_number',NULL,'doc_date','2025-01-30','direction','outgoing','issued_by','Deputy Commissioner','financial_years','[]'::jsonb,'summary','Synthetic','prompt_version','v4.0'));
  IF finish.code<>'review_required' OR finish.binding_id IS NULL OR (SELECT direction FROM public.documents WHERE id=document)<>'incoming' THEN RAISE EXCEPTION 'v4 actor-derived direction did not override caller metadata'; END IF;
  SELECT array_agg(id ORDER BY semantic_candidate_key) INTO source_ids FROM public.source_field_candidates WHERE source_analysis_run_id=run;
  IF cardinality(source_ids)<>8 OR EXISTS(SELECT 1 FROM public.source_field_candidates WHERE source_analysis_run_id=run AND value_type<>'structured') THEN RAISE EXCEPTION 'structured candidate materialization failed'; END IF;
  replay:=public.materialize_verified_source_field_candidate(run,'client_identifier:11111111111111111111111111111111','document.client_identifier.gstin','structured',gstin,1,'27AAPFU0939F1ZV',NULL,0.96,'provisional',NULL,jsonb_build_object('char_start',strpos(page_text,'27AAPFU0939F1ZV')-1,'char_end',strpos(page_text,'27AAPFU0939F1ZV')-1+15,'token_start',NULL,'token_end',NULL,'table_cell',NULL));
  IF replay IS NULL OR NOT replay=ANY(source_ids) THEN RAISE EXCEPTION 'candidate replay failed'; END IF;
  binding_copy:=public.materialize_document_version_analysis(version_copy,run,'copy',NULL);
  IF binding_copy IS NULL OR (SELECT count(*) FROM public.document_field_candidates WHERE source_field_candidate_id=ANY(source_ids))<>16 THEN RAISE EXCEPTION 'same-source copy did not preserve candidates'; END IF;
  forged_provision:=jsonb_set(jsonb_set(jsonb_set(jsonb_set(provision,'{act_kind}','"igst_act"'),'{act}','"IGST Act"'),'{normalized,act_kind}','"igst_act"'),'{normalized,act}','"IGST Act"');
  rejected:=false; BEGIN PERFORM public.materialize_verified_source_field_candidate(run,'legal_provision:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','document.legal_provision.section','structured',forged_provision,1,provision->>'raw',NULL,.9,'provisional',NULL,jsonb_build_object('char_start',strpos(page_text,provision->>'raw')-1,'char_end',strpos(page_text,provision->>'raw')-1+char_length(provision->>'raw'),'token_start',NULL,'token_end',NULL,'table_cell',NULL)); EXCEPTION WHEN others THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'source-mismatched normalized Act was accepted as provisional'; END IF;
  PERFORM public.materialize_verified_source_field_candidate(run,'legal_provision:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','document.legal_provision.section','structured',forged_provision,1,provision->>'raw',NULL,.9,'invalid',ARRAY['act_not_in_quote'],NULL);
  IF NOT EXISTS(SELECT 1 FROM public.source_field_candidates WHERE source_analysis_run_id=run AND semantic_candidate_key='legal_provision:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' AND validation_state='invalid' AND verified_source_anchor IS NULL) THEN
    RAISE EXCEPTION 'source-mismatched normalized Act was not retained as bounded invalid evidence';
  END IF;
  INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
    VALUES(issuer_processing,org,document_copy,version_copy,'full','fixture.material.issuer-only','running','extracting',now(),issuer_processing_lease,now()+interval '10 minutes',now());
  INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at,attempt_count,lease_token,lease_expires_at,heartbeat_at)
    VALUES(issuer_run,org,asset,'ai_extraction.'||issuer_processing,'ai_extraction.'||issuer_processing,'ai_extraction','running','running','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4',catalogue,normalizer,now(),1,issuer_source_lease,now()+interval '10 minutes',now());
  INSERT INTO public.source_analysis_attempts(org_id,source_analysis_run_id,attempt_number,state,retry_reason,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at)
    VALUES(org,issuer_run,1,'running','initial','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4',catalogue,normalizer,now());
  INSERT INTO public.document_page_text_artifacts(org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,content_fingerprint)
    VALUES(org,document_copy,version_copy,issuer_processing,issuer_run,'ready',1,repeat('3',64));
  INSERT INTO public.document_page_text_pages(org_id,artifact_id,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages)
    SELECT org,id,1,page_text,'[]','[]',repeat('4',64),'native_pdf','native-pdf-quality-v1','{}','{}' FROM public.document_page_text_artifacts WHERE source_analysis_run_id=issuer_run;
  SELECT jsonb_agg(value) INTO issuer_candidates FROM jsonb_array_elements(candidates) WHERE value->>'field_path'='document.actor.issuer';
  SELECT * INTO finish FROM public.finish_document_processing_ai_extraction(issuer_processing,issuer_processing_lease,issuer_run,issuer_source_lease,'validated',1,1,1,issuer_candidates,true,
    jsonb_build_object('doc_type','SCN','reference_number',NULL,'doc_date','2025-01-30','direction','incoming','issued_by','Deputy Commissioner','financial_years','[]'::jsonb,'summary','Issuer only','prompt_version','v4.0'));
  IF finish.code<>'review_required' OR (SELECT direction FROM public.documents WHERE id=document_copy) IS NOT NULL THEN RAISE EXCEPTION 'issuer-only v4 actors did not override forged caller direction with null'; END IF;
  rejected:=false; BEGIN PERFORM public.materialize_document_version_analysis(version_b,run,'copy',NULL); EXCEPTION WHEN others THEN rejected:=true; END; IF NOT rejected THEN RAISE EXCEPTION 'cross-tenant copy accepted'; END IF;
  rejected:=false; BEGIN PERFORM public.materialize_verified_source_field_candidate(run,'money:forged','document.money.tax','structured',jsonb_set(money,'{normalized,value}','"1"'),1,money->>'raw',NULL,.9,'invalid',ARRAY['fixture'],NULL); EXCEPTION WHEN others THEN rejected:=true; END; IF NOT rejected THEN RAISE EXCEPTION 'forged money normalized value accepted'; END IF;
  rejected:=false; BEGIN PERFORM public.materialize_verified_source_field_candidate(run,'gstin:forged','document.client_identifier.gstin','structured',invalid_gstin||'{"normalized_value":"27AAPFU0939F1ZU","normalization_state":"valid","validation_error":null}',1,invalid_gstin->>'raw',NULL,.9,'invalid',ARRAY['fixture'],NULL); EXCEPTION WHEN others THEN rejected:=true; END; IF NOT rejected THEN RAISE EXCEPTION 'forged invalid GSTIN normalization accepted'; END IF;
  rejected:=false; BEGIN PERFORM public.materialize_verified_source_field_candidate(run,'date:source-mismatch','document.legal_date.issue','structured',legal_date||'{"proposed_normalized_date":"2025-01-31","normalized_date":"2025-01-31"}',1,legal_date->>'raw',NULL,.9,'invalid',ARRAY['fixture'],jsonb_build_object('char_start',strpos(page_text,legal_date->>'raw')-1,'char_end',strpos(page_text,legal_date->>'raw')-1+char_length(legal_date->>'raw'),'token_start',NULL,'token_end',NULL,'table_cell',NULL)); EXCEPTION WHEN others THEN rejected:=true; END; IF NOT rejected THEN RAISE EXCEPTION 'forged source-mismatched date accepted'; END IF;
  rejected:=false; BEGIN PERFORM public.materialize_verified_source_field_candidate(run,'actor:wrong-path','document.actor.recipient','structured',issuer,1,issuer->>'raw',NULL,.9,'invalid',ARRAY['fixture'],NULL); EXCEPTION WHEN others THEN rejected:=true; END; IF NOT rejected THEN RAISE EXCEPTION 'forged actor path accepted'; END IF;
  rejected:=false; BEGIN PERFORM public.materialize_verified_source_field_candidate(run,'party:wrong-version','document.party.taxpayer','structured',jsonb_set(party,'{catalogue_version}','"forged-v1"'),1,party->>'raw',NULL,.9,'invalid',ARRAY['fixture'],NULL); EXCEPTION WHEN others THEN rejected:=true; END; IF NOT rejected THEN RAISE EXCEPTION 'forged observation version accepted'; END IF;
  rejected:=false; BEGIN UPDATE public.source_field_candidates SET confidence=.5 WHERE id=source_ids[1]; EXCEPTION WHEN others THEN rejected:=true; END; IF NOT rejected THEN RAISE EXCEPTION 'source candidate update accepted'; END IF;
  rejected:=false; BEGIN DELETE FROM public.document_field_candidates WHERE source_field_candidate_id=source_ids[1]; EXCEPTION WHEN others THEN rejected:=true; END; IF NOT rejected THEN RAISE EXCEPTION 'document candidate delete accepted'; END IF;
  IF (SELECT count(*) FROM public.matter_identifiers)<>identifiers_before OR (SELECT count(*) FROM public.document_links)<>links_before OR (SELECT count(*) FROM public.document_relationships)<>relationships_before
    OR (SELECT count(*) FROM public.document_effective_metadata)<>effective_before OR (SELECT count(*) FROM public.outbox_events)<>outbox_before THEN RAISE EXCEPTION 'material observations caused a prohibited consequence'; END IF;
END $fixture$;

SET LOCAL ROLE authenticated;
DO $dml$ DECLARE denied boolean:=false; BEGIN
  BEGIN INSERT INTO public.source_field_candidates(org_id,source_analysis_run_id,asset_id,semantic_candidate_key,field_path,value_type,normalized_value,page_number,evidence_page_count,quotation,confidence,validation_state)
    VALUES('15020000-0000-0000-0000-000000000001','15080000-0000-0000-0000-000000000001','15060000-0000-0000-0000-000000000001','forged','document.money.tax','structured','{}',1,1,'forged',.9,'invalid');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'authenticated direct candidate DML accepted'; END IF;
END $dml$;
RESET ROLE;

DO $surface$ BEGIN
  IF has_function_privilege('service_role','public.finish_document_processing_ai_extraction_v3(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb)','EXECUTE')
    OR NOT has_function_privilege('service_role','public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb)','EXECUTE')
    OR has_table_privilege('service_role','public.source_field_candidates','INSERT') THEN RAISE EXCEPTION 'finisher or direct-DML privilege surface is unsafe'; END IF;
END $surface$;

ROLLBACK;
