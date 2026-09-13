-- D09-T06 source-backed fixture setup; reusable by the concurrency harness.
\set ON_ERROR_STOP on


DO $fixture$
DECLARE
  actor uuid:='152a0000-0000-0000-0000-000000000001'; viewer uuid:='152a0000-0000-0000-0000-000000000002'; suspended uuid:='152a0000-0000-0000-0000-000000000003'; foreign_actor uuid:='152a0000-0000-0000-0000-000000000004'; ambiguous_actor uuid:='152a0000-0000-0000-0000-000000000005'; admin_actor uuid:='152a0000-0000-0000-0000-000000000006'; associate_actor uuid:='152a0000-0000-0000-0000-000000000007';
  org uuid:='152b0000-0000-0000-0000-000000000001'; foreign_org uuid:='152b0000-0000-0000-0000-000000000002'; client uuid:='152c0000-0000-0000-0000-000000000001';
  matter_a uuid:='152d0000-0000-0000-0000-000000000001'; matter_b uuid:='152d0000-0000-0000-0000-000000000002';
  docs uuid[]:=ARRAY['152e0000-0000-0000-0000-000000000001','152e0000-0000-0000-0000-000000000002','152e0000-0000-0000-0000-000000000003','152e0000-0000-0000-0000-000000000004']::uuid[];
  assets uuid[]:=ARRAY['152f0000-0000-0000-0000-000000000001','152f0000-0000-0000-0000-000000000002','152f0000-0000-0000-0000-000000000003','152f0000-0000-0000-0000-000000000004']::uuid[];
  versions uuid[]:=ARRAY['15200000-0000-0000-0000-000000000001','15200000-0000-0000-0000-000000000002','15200000-0000-0000-0000-000000000003','15200000-0000-0000-0000-000000000004']::uuid[];
  processes uuid[]:=ARRAY['15210000-0000-0000-0000-000000000001','15210000-0000-0000-0000-000000000002','15210000-0000-0000-0000-000000000003','15210000-0000-0000-0000-000000000004']::uuid[];
  process_leases uuid[]:=ARRAY['15220000-0000-0000-0000-000000000001','15220000-0000-0000-0000-000000000002','15220000-0000-0000-0000-000000000003','15220000-0000-0000-0000-000000000004']::uuid[];
  runs uuid[]:=ARRAY['15230000-0000-0000-0000-000000000001','15230000-0000-0000-0000-000000000002','15230000-0000-0000-0000-000000000003','15230000-0000-0000-0000-000000000004']::uuid[];
  run_leases uuid[]:=ARRAY['15240000-0000-0000-0000-000000000001','15240000-0000-0000-0000-000000000002','15240000-0000-0000-0000-000000000003','15240000-0000-0000-0000-000000000004']::uuid[];
  catalogue text:='gst-legal-material-observation-catalogue-v3'; normalizer text:='typed-material-observation-normalizer-v3';
  ref jsonb; candidates jsonb; finished record; i integer; page_text text; source_candidate uuid; target_a_candidate uuid; target_b_candidate uuid;
  activated record; target_a_identifier uuid; target_b_identifier uuid; source_identifier uuid; corrected_identifier uuid; correction_candidate uuid; outbound_candidate uuid; mention_one uuid; mention_two uuid;
  matter_identifier uuid; v_revision bigint; rejected boolean; links_before bigint; relationships_before bigint; outbox_before bigint; effective_before bigint; decisions_before bigint; activity_before bigint; identifiers_before bigint; query_plan json;
  purged_identifier uuid; trashed record; purge_impact record; purge_queue record; purge_job record; purge_step record; storage_step record;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
    ('00000000-0000-0000-0000-000000000000',actor,'authenticated','authenticated','reference-owner@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',viewer,'authenticated','authenticated','reference-viewer@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',suspended,'authenticated','authenticated','reference-suspended@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',foreign_actor,'authenticated','authenticated','reference-foreign@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',ambiguous_actor,'authenticated','authenticated','reference-ambiguous@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',admin_actor,'authenticated','authenticated','reference-admin@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',associate_actor,'authenticated','authenticated','reference-associate@example.test','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES(org,'Reference fixture',actor),(foreign_org,'Foreign reference fixture',foreign_actor);
  INSERT INTO public.org_members(org_id,user_id,role) VALUES(org,viewer,'viewer'),(org,suspended,'associate'),(org,admin_actor,'admin'),(org,associate_actor,'associate');
  UPDATE public.organisation_memberships SET state='suspended',suspended_at=now(),suspended_by=actor,suspension_reason='fixture' WHERE org_id=org AND user_id=suspended;
  INSERT INTO public.clients(id,org_id,name) VALUES(client,org,'Reference client');
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code) VALUES(matter_a,org,client,'Reference A','REF-152-A'),(matter_b,org,client,'Reference B','REF-152-B');
  FOR i IN 1..4 LOOP
    INSERT INTO public.documents(id,org_id,matter_id,storage_path,display_title,document_class,origin_kind,content_availability,status,created_by)
      VALUES(docs[i],org,CASE WHEN i=3 THEN matter_b ELSE matter_a END,'fixture/reference-'||i||'.pdf','Reference '||i,'proceeding','upload','source_attached','placed',actor);
    INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
      VALUES(assets[i],org,'documents','orgs/'||org||'/assets/'||assets[i]||'/original.pdf',lpad(i::text,64,i::text),100,'application/pdf','available',now(),1,actor);
    INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
      VALUES(versions[i],org,docs[i],assets[i],1,'reference-'||i||'.pdf',1,'valid','current',now(),now(),actor);
    UPDATE public.documents SET current_version_id=versions[i] WHERE id=docs[i];
    INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
      VALUES(processes[i],org,docs[i],versions[i],'full','fixture.reference.'||i,'running','extracting',now(),process_leases[i],now()+interval '10 minutes',now());
    INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at,attempt_count,lease_token,lease_expires_at,heartbeat_at)
      VALUES(runs[i],org,assets[i],'ai_extraction.'||processes[i],'ai_extraction.'||processes[i],'ai_extraction','running','running','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4',catalogue,normalizer,now(),1,run_leases[i],now()+interval '10 minutes',now());
    INSERT INTO public.source_analysis_attempts(org_id,source_analysis_run_id,attempt_number,state,retry_reason,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at)
      VALUES(org,runs[i],1,'running','initial','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4',catalogue,normalizer,now());
    page_text:=CASE WHEN i IN (1,4) THEN 'References GST/555/2026 in this proceeding.' WHEN i=2 THEN 'Order identifiers GST/555/2026 and GST/556/2026.' ELSE 'Order identifier GST/555/2026.' END;
    INSERT INTO public.document_page_text_artifacts(org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,content_fingerprint)
      VALUES(org,docs[i],versions[i],processes[i],runs[i],'ready',1,repeat(i::text,64));
    INSERT INTO public.document_page_text_pages(org_id,artifact_id,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages)
      SELECT org,id,1,page_text,'[]','[]',repeat(i::text,64),'native_pdf','native-pdf-quality-v1','{}','{}' FROM public.document_page_text_artifacts WHERE source_analysis_run_id=runs[i];

    ref:=jsonb_build_object('role',CASE WHEN i IN (1,4) THEN 'outbound_mention' ELSE 'self_identifier' END,'kind','order_reference','namespace','GST Tribunal','namespace_normalized','GST TRIBUNAL','raw','GST/555/2026','display','GST/555/2026','normalized_value','GST/555/2026','components',jsonb_build_object('kind','order_reference','segments',jsonb_build_array('GST','555','2026'),'prefix','GST','numericCore','555','year','2026'),'completeness','complete','match_eligible',true,'catalogue_version',catalogue,'normalizer_version',normalizer);
    candidates:=jsonb_build_array(jsonb_build_object('semantic_candidate_key','official_reference:'||lpad(i::text,32,i::text),'field_path','document.official_reference.'||(ref->>'role'),'value_type','structured','normalized_value',ref,'page_number',1,'quotation','GST/555/2026','evidence_regions',NULL,'confidence',0.99,'validation_state','provisional','validation_error_codes',NULL,'verified_source_anchor',jsonb_build_object('char_start',strpos(page_text,'GST/555/2026')-1,'char_end',strpos(page_text,'GST/555/2026')-1+char_length('GST/555/2026'),'token_start',NULL,'token_end',NULL,'table_cell',NULL)));
    IF i=1 THEN
      ref:=jsonb_set(ref,'{role}','"self_identifier"');
      candidates:=candidates||jsonb_build_array(jsonb_build_object('semantic_candidate_key','official_reference:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','field_path','document.official_reference.self_identifier','value_type','structured','normalized_value',ref,'page_number',1,'quotation','GST/555/2026','evidence_regions',NULL,'confidence',0.99,'validation_state','provisional','validation_error_codes',NULL,'verified_source_anchor',jsonb_build_object('char_start',11,'char_end',23,'token_start',NULL,'token_end',NULL,'table_cell',NULL)));
    END IF;
    IF i=2 THEN
      ref:=jsonb_set(jsonb_set(jsonb_set(ref,'{raw}','"GST/556/2026"'),'{display}','"GST/556/2026"'),'{normalized_value}','"GST/556/2026"');
      ref:=jsonb_set(ref,'{components}',jsonb_build_object('kind','order_reference','segments',jsonb_build_array('GST','556','2026'),'prefix','GST','numericCore','556','year','2026'));
      candidates:=candidates||jsonb_build_array(jsonb_build_object('semantic_candidate_key','official_reference:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','field_path','document.official_reference.self_identifier','value_type','structured','normalized_value',ref,'page_number',1,'quotation','GST/556/2026','evidence_regions',NULL,'confidence',0.99,'validation_state','provisional','validation_error_codes',NULL,'verified_source_anchor',jsonb_build_object('char_start',strpos(page_text,'GST/556/2026')-1,'char_end',strpos(page_text,'GST/556/2026')-1+char_length('GST/556/2026'),'token_start',NULL,'token_end',NULL,'table_cell',NULL)));
    END IF;
    SELECT * INTO finished FROM public.finish_document_processing_ai_extraction(processes[i],process_leases[i],runs[i],run_leases[i],'validated',1,1,1,candidates,false,jsonb_build_object('doc_type','OIO','reference_number','GST/555/2026','doc_date','2026-01-01','direction',NULL,'issued_by','GST Tribunal','financial_years','[]'::jsonb,'summary','Fixture','prompt_version','v4.0'));
    IF finished.code<>'validated' OR finished.binding_id IS NULL THEN RAISE EXCEPTION 'fenced v4 finisher failed for row %: %',i,finished.code; END IF;
  END LOOP;

  UPDATE public.document_processing_runs SET state='completed',stage='ready',completed_at=now(),lease_token=NULL,lease_expires_at=NULL WHERE org_id=org;
END $fixture$;
