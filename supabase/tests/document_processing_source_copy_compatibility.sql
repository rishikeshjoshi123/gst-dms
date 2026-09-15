-- Rollback-only actual Copy: approved native page source + validated AI binding
-- coexist with a later terminal model-not-called lineage binding.
BEGIN;
DO $copy$
DECLARE
  org uuid:='16620000-0000-4000-8000-000000000001';
  actor uuid:='16620000-0000-4000-8000-000000000002';
  client uuid:='16620000-0000-4000-8000-000000000003';
  source_matter uuid:='16620000-0000-4000-8000-000000000004';
  target_matter uuid:='16620000-0000-4000-8000-000000000005';
  doc uuid:='16620000-0000-4000-8000-000000000006';
  asset uuid:='16620000-0000-4000-8000-000000000007';
  ver uuid:='16620000-0000-4000-8000-000000000008';
  validated_source uuid:='16620000-0000-4000-8000-000000000009';
  validated_processing uuid:='16620000-0000-4000-8000-000000000010';
  no_call_processing uuid:='16620000-0000-4000-8000-000000000011';
  no_call_lease uuid:='16620000-0000-4000-8000-000000000012';
  artifact uuid:='16620000-0000-4000-8000-000000000013';
  claim record; cancelled record; preview jsonb; result jsonb; copied uuid;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    VALUES('00000000-0000-0000-0000-000000000000',actor,'authenticated','authenticated','source-copy@example.test','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES(org,'Source Copy fixture',actor);
  INSERT INTO public.clients(id,org_id,name) VALUES(client,org,'Fixture client');
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code) VALUES
    (source_matter,org,client,'Source matter','SRC-166'),(target_matter,org,client,'Target matter','DST-166');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,display_title,document_class,origin_kind,content_availability,status,created_by)
    VALUES(doc,org,source_matter,'legacy/source-copy.pdf','Source Copy document','proceeding','upload','source_attached','placed',actor);
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
    VALUES(asset,org,'documents','orgs/'||org::text||'/assets/'||asset::text||'/original.pdf',repeat('a',64),99,'application/pdf','available',now(),1,actor);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
    VALUES(ver,org,doc,asset,1,'fixture.pdf',1,'valid','current',now(),now(),actor);
  UPDATE public.documents SET current_version_id=ver WHERE id=doc;
  INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,completed_at)
    VALUES(validated_processing,org,doc,ver,'full','fixture.copy.validated','completed','ready',now(),now());
  INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at,completed_at)
    VALUES(validated_source,org,asset,'ai_extraction.'||validated_processing::text,'ai_extraction.'||validated_processing::text,
      'ai_extraction','validated','succeeded','vertex-ai','gemini-2.5-flash','fixture-model','fixture-prompt','fixture-schema','fixture-catalogue','fixture-normalizer',now(),now());
  INSERT INTO public.document_version_analysis_bindings(org_id,document_id,document_version_id,source_analysis_run_id,binding_reason,created_by)
    VALUES(org,doc,ver,validated_source,'processing_extraction',actor);
  INSERT INTO public.document_page_text_artifacts(id,org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,content_fingerprint)
    VALUES(artifact,org,doc,ver,validated_processing,validated_source,'ready',1,repeat('b',64));
  INSERT INTO public.document_page_text_pages(org_id,artifact_id,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages)
    VALUES(org,artifact,1,'Safe synthetic source.','[]','[]',repeat('c',64),'native_pdf','native-pdf-quality-v1','{}','{}');
  IF NOT public.document_page_text_artifact_has_approved_acquisition(artifact,1) THEN RAISE EXCEPTION 'Copy fixture lacks approved page source'; END IF;

  INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
    VALUES(no_call_processing,org,doc,ver,'full','fixture.copy.no_call','running','extracting',now(),no_call_lease,now()+interval '10 minutes',now());
  SELECT * INTO claim FROM public.begin_current_document_processing_ai_extraction(no_call_processing,no_call_lease,
    'vertex-ai','gemini-2.5-flash','fixture-model','fixture-prompt','fixture-schema','fixture-catalogue','fixture-normalizer');
  IF claim.code<>'claimed' THEN RAISE EXCEPTION 'No-call Copy source claim failed'; END IF;
  UPDATE public.matters SET work_state='closed' WHERE id=source_matter;
  SELECT * INTO cancelled FROM public.cancel_uncalled_document_processing_ai_extraction(
    no_call_processing,no_call_lease,claim.source_analysis_run_id,claim.source_analysis_lease_token);
  IF cancelled.code<>'cancelled' THEN RAISE EXCEPTION 'No-call Copy source was not terminalized'; END IF;
  UPDATE public.matters SET work_state='active' WHERE id=source_matter;
  SELECT * INTO cancelled FROM public.finish_document_processing_work(no_call_processing,no_call_lease,'no_work');
  IF cancelled.code<>'already_complete' THEN RAISE EXCEPTION 'No-call outer run was not cancelled'; END IF;
  IF (SELECT count(*) FROM public.document_version_analysis_bindings WHERE document_version_id=ver)<>2
    OR EXISTS(SELECT 1 FROM public.document_field_candidates candidate
      JOIN public.document_version_analysis_bindings binding ON binding.id=candidate.document_version_analysis_binding_id
      WHERE binding.source_analysis_run_id=claim.source_analysis_run_id) THEN
    RAISE EXCEPTION 'No-call lineage is absent or created model candidates'; END IF;

  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  preview:=public.preview_document_boundary_repair(doc,target_matter,'copy');
  IF preview->>'code'<>'ok' OR jsonb_array_length(preview->'blockers')<>0 THEN RAISE EXCEPTION 'Copy preview blocked: %',preview; END IF;
  result:=public.execute_document_boundary_repair(doc,target_matter,'copy',preview->>'fingerprint','Share approved source',gen_random_uuid());
  IF result->>'code'<>'ok' THEN RAISE EXCEPTION 'Actual Copy failed with no-call lineage: %',result; END IF;
  copied:=(result->>'documentId')::uuid;
  IF copied=doc OR NOT EXISTS(SELECT 1 FROM public.document_version_analysis_bindings
      WHERE document_id=copied AND source_analysis_run_id=validated_source AND binding_reason='boundary_copy')
    OR EXISTS(SELECT 1 FROM public.document_version_analysis_bindings WHERE document_id=copied AND source_analysis_run_id=claim.source_analysis_run_id)
    OR EXISTS(SELECT 1 FROM public.document_field_candidates WHERE document_id=copied)
    OR NOT EXISTS(SELECT 1 FROM public.document_page_text_artifacts WHERE document_id=copied AND copied_from_artifact_id=artifact) THEN
    RAISE EXCEPTION 'Copy did not preserve approved source while excluding no-call evidence'; END IF;
END $copy$;
ROLLBACK;
