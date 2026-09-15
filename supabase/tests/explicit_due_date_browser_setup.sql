-- Disposable Review browser source; uses the existing private four-page asset.
\set ON_ERROR_STOP on
DO $fixture$
DECLARE org uuid:='153b0000-0000-0000-0000-000000000001';
  doc uuid:='153e0000-0000-0000-0000-000000000001';
  version uuid:='15300000-0000-0000-0000-000000000001';
  asset uuid:='153f0000-0000-0000-0000-000000000001';
  processing uuid:=gen_random_uuid(); source_run uuid:=gen_random_uuid();
  processing_lease uuid:=gen_random_uuid(); source_lease uuid:=gen_random_uuid();
  finished record; candidate jsonb;
BEGIN
  INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
    VALUES(processing,org,doc,version,'full','fixture.browser.due.'||processing,'running','extracting',now(),processing_lease,now()+interval '10 minutes',now());
  INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at,attempt_count,lease_token,lease_expires_at,heartbeat_at)
    VALUES(source_run,org,asset,'ai_extraction.'||processing,'ai_extraction.'||processing,'ai_extraction','running','running','vertex-ai','fixture-offline','fixture-model','v4.0','document-extraction-v4','gst-legal-material-observation-catalogue-v3','typed-material-observation-normalizer-v3',now(),1,source_lease,now()+interval '10 minutes',now());
  INSERT INTO public.source_analysis_attempts(org_id,source_analysis_run_id,attempt_number,state,retry_reason,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at)
    VALUES(org,source_run,1,'running','initial','vertex-ai','fixture-offline','fixture-model','v4.0','document-extraction-v4','gst-legal-material-observation-catalogue-v3','typed-material-observation-normalizer-v3',now());
  UPDATE public.document_page_text_artifacts SET processing_run_id=processing,source_analysis_run_id=source_run
    WHERE document_version_id=version AND org_id=org;
  UPDATE public.document_page_text_pages SET page_text='Reply must be filed by 2026-10-15.'
    WHERE page_number=2 AND artifact_id=(SELECT id FROM public.document_page_text_artifacts WHERE document_version_id=version AND org_id=org);
  candidate:=jsonb_build_array(jsonb_build_object('semantic_candidate_key','legal_date:browser-source',
    'field_path','document.legal_date.due','value_type','structured',
    'normalized_value',jsonb_build_object('meaning','due','raw','Reply must be filed by 2026-10-15.',
      'display','Reply must be filed by 2026-10-15.','precision','exact','normalized_date','2026-10-15',
      'proposed_normalized_date','2026-10-15','normalization_state','valid','validation_error',NULL,
      'catalogue_version','gst-legal-material-observation-catalogue-v3',
      'normalizer_version','typed-material-observation-normalizer-v3'),
    'page_number',2,'quotation','Reply must be filed by 2026-10-15.','evidence_regions',NULL,
    'confidence',0.98,'validation_state','provisional','validation_error_codes',NULL,
    'verified_source_anchor',jsonb_build_object('char_start',0,'char_end',34,'token_start',NULL,'token_end',NULL,'table_cell',NULL)));
  SELECT * INTO finished FROM public.finish_document_processing_ai_extraction(processing,processing_lease,
    source_run,source_lease,'validated',1,1,1,candidate,true,jsonb_build_object('doc_type','SCN',
      'reference_number',NULL,'doc_date',NULL,'direction',NULL,'issued_by',NULL,'financial_years','[]'::jsonb,
      'summary','Fixture','prompt_version','v4.0'));
  IF finished.binding_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.review_items
    WHERE type='deadline_verification' AND document_id=doc AND status='needs_review')
    THEN RAISE EXCEPTION 'Browser source date did not reach typed Review'; END IF;
END $fixture$;
