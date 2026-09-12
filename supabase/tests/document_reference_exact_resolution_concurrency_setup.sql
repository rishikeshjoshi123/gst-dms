\set ON_ERROR_STOP on
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES('00000000-0000-0000-0000-000000000000','151a0000-0000-0000-0000-000000000099','authenticated','authenticated','reference-race@example.test','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by)
VALUES('151b0000-0000-0000-0000-000000000099','Reference race','151a0000-0000-0000-0000-000000000099');

DO $setup$
DECLARE
  actor uuid:='151a0000-0000-0000-0000-000000000099'; org uuid:='151b0000-0000-0000-0000-000000000099';
  client uuid:='151c0000-0000-0000-0000-000000000099'; matter uuid:='151d0000-0000-0000-0000-000000000099';
  docs uuid[]:=ARRAY['151e0000-0000-0000-0000-000000000098','151e0000-0000-0000-0000-000000000099']::uuid[];
  assets uuid[]:=ARRAY['151f0000-0000-0000-0000-000000000098','151f0000-0000-0000-0000-000000000099']::uuid[];
  versions uuid[]:=ARRAY['15100000-0000-0000-0000-000000000098','15100000-0000-0000-0000-000000000099']::uuid[];
  processes uuid[]:=ARRAY['15110000-0000-0000-0000-000000000098','15110000-0000-0000-0000-000000000099']::uuid[];
  process_leases uuid[]:=ARRAY['15120000-0000-0000-0000-000000000098','15120000-0000-0000-0000-000000000099']::uuid[];
  runs uuid[]:=ARRAY['15130000-0000-0000-0000-000000000098','15130000-0000-0000-0000-000000000099']::uuid[];
  run_leases uuid[]:=ARRAY['15140000-0000-0000-0000-000000000098','15140000-0000-0000-0000-000000000099']::uuid[];
  catalogue text:='gst-legal-material-observation-catalogue-v3'; normalizer text:='typed-material-observation-normalizer-v3';
  candidates jsonb; candidate jsonb; reference jsonb; finished record; i integer; value text; role text; field text; page_text text;
  old_candidate uuid; old_identifier uuid; document_revision bigint; swap_binding uuid; swap_candidate uuid;
BEGIN
  INSERT INTO public.clients(id,org_id,name) VALUES(client,org,'Reference race client');
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code) VALUES(matter,org,client,'Reference race matter','REF-RACE');
  FOR i IN 1..2 LOOP
    INSERT INTO public.documents(id,org_id,matter_id,storage_path,display_title,document_class,origin_kind,content_availability,status,created_by)
      VALUES(docs[i],org,matter,'fixture/reference-race-'||i||'.pdf','Reference race '||i,'proceeding','upload','source_attached','placed',actor);
    INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
      VALUES(assets[i],org,'documents','orgs/'||org||'/assets/'||assets[i]||'/original.pdf',repeat(i::text,64),100,'application/pdf','available',now(),1,actor);
    INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
      VALUES(versions[i],org,docs[i],assets[i],1,'reference-race-'||i||'.pdf',1,'valid','current',now(),now(),actor);
    UPDATE public.documents SET current_version_id=versions[i] WHERE id=docs[i];
    INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
      VALUES(processes[i],org,docs[i],versions[i],'full','fixture.reference.race.'||i,'running','extracting',now(),process_leases[i],now()+interval '10 minutes',now());
    INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at,attempt_count,lease_token,lease_expires_at,heartbeat_at)
      VALUES(runs[i],org,assets[i],'ai_extraction.'||processes[i],'ai_extraction.'||processes[i],'ai_extraction','running','running','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4',catalogue,normalizer,now(),1,run_leases[i],now()+interval '10 minutes',now());
    INSERT INTO public.source_analysis_attempts(org_id,source_analysis_run_id,attempt_number,state,retry_reason,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at)
      VALUES(org,runs[i],1,'running','initial','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4',catalogue,normalizer,now());
    page_text:='References GST/701/2026, GST/702/2026 and GST/703/2026.';
    INSERT INTO public.document_page_text_artifacts(org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,content_fingerprint)
      VALUES(org,docs[i],versions[i],processes[i],runs[i],'ready',1,repeat(i::text,64));
    INSERT INTO public.document_page_text_pages(org_id,artifact_id,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages)
      SELECT org,id,1,page_text,'[]','[]',repeat(i::text,64),'native_pdf','native-pdf-quality-v1','{}','{}' FROM public.document_page_text_artifacts WHERE source_analysis_run_id=runs[i];
    candidates:='[]'::jsonb;
    FOREACH value IN ARRAY ARRAY['GST/701/2026','GST/702/2026','GST/703/2026'] LOOP
      IF i=1 AND value='GST/702/2026' THEN CONTINUE; END IF;
      role:=CASE WHEN i=1 THEN 'outbound_mention' ELSE 'self_identifier' END;
      field:='document.official_reference.'||role;
      reference:=jsonb_build_object('role',role,'kind','order_reference','namespace','Race Tribunal','namespace_normalized','RACE TRIBUNAL','raw',value,'display',value,'normalized_value',value,'components',jsonb_build_object('kind','order_reference','segments',to_jsonb(string_to_array(value,'/')),'prefix','GST','numericCore',split_part(value,'/',2),'year',split_part(value,'/',3)),'completeness','complete','match_eligible',true,'catalogue_version',catalogue,'normalizer_version',normalizer);
      candidate:=jsonb_build_object('semantic_candidate_key','official_reference:'||substr(md5(i::text||value),1,32),'field_path',field,'value_type','structured','normalized_value',reference,'page_number',1,'quotation',value,'evidence_regions',NULL,'confidence',0.99,'validation_state','provisional','validation_error_codes',NULL,'verified_source_anchor',jsonb_build_object('char_start',strpos(page_text,value)-1,'char_end',strpos(page_text,value)-1+char_length(value),'token_start',NULL,'token_end',NULL,'table_cell',NULL));
      candidates:=candidates||jsonb_build_array(candidate);
    END LOOP;
    SELECT * INTO finished FROM public.finish_document_processing_ai_extraction(processes[i],process_leases[i],runs[i],run_leases[i],'validated',1,1,1,candidates,false,jsonb_build_object('doc_type','OIO','reference_number','GST/701/2026','doc_date','2026-01-01','direction',NULL,'issued_by','Race Tribunal','financial_years','[]'::jsonb,'summary','Race fixture','prompt_version','v4.0'));
    IF finished.code<>'validated' THEN RAISE EXCEPTION 'race fixture finisher failed'; END IF;
  END LOOP;

  -- Two additional documents reuse the already validated source asset/run.
  -- Their own immutable version bindings materialize governed candidates for
  -- a cross-key correction swap without another provider-shaped payload.
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,display_title,document_class,origin_kind,content_availability,status,created_by) VALUES
    ('151e0000-0000-0000-0000-000000000096',org,matter,'fixture/reference-swap-a.pdf','Reference swap A','proceeding','upload','source_attached','placed',actor),
    ('151e0000-0000-0000-0000-000000000097',org,matter,'fixture/reference-swap-b.pdf','Reference swap B','proceeding','upload','source_attached','placed',actor);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by) VALUES
    ('15100000-0000-0000-0000-000000000096',org,'151e0000-0000-0000-0000-000000000096',assets[2],1,'reference-swap-a.pdf',1,'valid','current',now(),now(),actor),
    ('15100000-0000-0000-0000-000000000097',org,'151e0000-0000-0000-0000-000000000097',assets[2],1,'reference-swap-b.pdf',1,'valid','current',now(),now(),actor);
  UPDATE public.documents SET current_version_id=CASE id WHEN '151e0000-0000-0000-0000-000000000096'::uuid THEN '15100000-0000-0000-0000-000000000096'::uuid ELSE '15100000-0000-0000-0000-000000000097'::uuid END
    WHERE id IN ('151e0000-0000-0000-0000-000000000096','151e0000-0000-0000-0000-000000000097');
  SELECT public.materialize_document_version_analysis('15100000-0000-0000-0000-000000000096',runs[2],'processing_ai_extraction',NULL) INTO swap_binding;
  SELECT public.materialize_document_version_analysis('15100000-0000-0000-0000-000000000097',runs[2],'processing_ai_extraction',NULL) INTO swap_binding;

  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',actor,'iat',extract(epoch FROM now())::bigint)::text,true);
  SELECT id INTO old_candidate FROM public.document_field_candidates WHERE document_id=docs[2] AND normalized_value->>'normalized_value'='GST/701/2026';
  SELECT lifecycle_revision INTO document_revision FROM public.documents WHERE id=docs[2];
  SELECT identifier_id INTO old_identifier FROM public.activate_document_self_identifier(old_candidate,document_revision,NULL,'15160000-0000-0000-0000-000000000099');
  PERFORM set_config('test.reference_race.old_identifier',old_identifier::text,false);

  -- Keep the durable candidate/binding but remove its first materialization so
  -- the shell harness can race later mention arrival against target activation.
  PERFORM set_config('casechain.document_reference_internal','on',true);
  DELETE FROM public.current_document_reference_resolutions WHERE mention_id IN (SELECT id FROM public.document_reference_mentions WHERE normalized_value='GST/703/2026' AND org_id=org);
  DELETE FROM public.document_reference_resolution_results WHERE mention_id IN (SELECT id FROM public.document_reference_mentions WHERE normalized_value='GST/703/2026' AND org_id=org);
  DELETE FROM public.document_reference_resolution_runs WHERE org_id=org AND normalized_value='GST/703/2026';
  DELETE FROM public.document_reference_mentions WHERE org_id=org AND normalized_value='GST/703/2026';
  IF EXISTS(SELECT 1 FROM public.document_reference_mentions WHERE org_id=org AND normalized_value='GST/703/2026')
    OR EXISTS(SELECT 1 FROM public.document_reference_resolution_runs WHERE org_id=org AND normalized_value='GST/703/2026') THEN
    RAISE EXCEPTION 'race setup failed to remove the prior mention materialization';
  END IF;
END $setup$;
