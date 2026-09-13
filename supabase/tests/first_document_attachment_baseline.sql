BEGIN;
CREATE FUNCTION pg_temp.attachment_observation(p_document uuid,p_value text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE org uuid; version uuid; asset uuid; processing uuid:=gen_random_uuid(); run uuid:=gen_random_uuid(); lease uuid:=gen_random_uuid(); source_lease uuid:=gen_random_uuid(); finished record;
BEGIN
  SELECT d.org_id,d.current_version_id,v.asset_id INTO org,version,asset FROM public.documents d JOIN public.document_versions v ON v.id=d.current_version_id WHERE d.id=p_document;
  INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
    VALUES(processing,org,p_document,version,'full','fixture.attachment.'||processing,'running','extracting',now(),lease,now()+interval '10 minutes',now());
  INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at,attempt_count,lease_token,lease_expires_at,heartbeat_at)
    VALUES(run,org,asset,'ai_extraction.'||processing,'ai_extraction.'||processing,'ai_extraction','running','running','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4','gst-legal-material-observation-catalogue-v3','typed-material-observation-normalizer-v3',now(),1,source_lease,now()+interval '10 minutes',now());
  INSERT INTO public.source_analysis_attempts(org_id,source_analysis_run_id,attempt_number,state,retry_reason,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at)
    VALUES(org,run,1,'running','initial','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4','gst-legal-material-observation-catalogue-v3','typed-material-observation-normalizer-v3',now());
  INSERT INTO public.document_page_text_artifacts(org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,content_fingerprint)
    VALUES(org,p_document,version,processing,run,'ready',4,repeat('a',64)) ON CONFLICT(org_id,document_id,document_version_id) DO UPDATE SET processing_run_id=EXCLUDED.processing_run_id,source_analysis_run_id=EXCLUDED.source_analysis_run_id;
  INSERT INTO public.document_page_text_pages(org_id,artifact_id,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages)
    SELECT org,id,n,'SCN and OIO','[]','[]',repeat('a',64),'native_pdf','native-pdf-quality-v1','{}','{}' FROM public.document_page_text_artifacts CROSS JOIN generate_series(1,4) n WHERE source_analysis_run_id=run ON CONFLICT DO NOTHING;
  SELECT * INTO finished FROM public.finish_document_processing_ai_extraction(processing,lease,run,source_lease,'validated',1,1,1,
    jsonb_build_array(jsonb_build_object('semantic_candidate_key','document.type','field_path','document.type','value_type','code','normalized_value',p_value,'page_number',2,'quotation',p_value,'evidence_regions',NULL,'confidence',0.99,'validation_state','eligible','validation_error_codes',NULL,'verified_source_anchor',NULL)),false,
    jsonb_build_object('doc_type',p_value,'reference_number','AI-CHANGED','doc_date','2026-01-01','direction','outgoing','issued_by','AI authority','financial_years','["2025-26"]'::jsonb,'summary','AI summary','prompt_version','v4.0'));
  IF finished.binding_id IS NULL THEN RAISE EXCEPTION 'Attachment finisher failed: %',finished.code; END IF;
  UPDATE public.document_processing_runs SET state='completed',stage='ready',completed_at=now(),lease_token=NULL,lease_expires_at=NULL WHERE id=processing AND state='running';
END $$;
DO $$
DECLARE u attachment_test.uploads%ROWTYPE; r record; before_metadata jsonb; item uuid; detail jsonb; accepted uuid; version_id uuid; replacement_item uuid;
BEGIN
  SELECT * INTO u FROM attachment_test.uploads WHERE n=4;
  PERFORM public.auto_assign_intended_matter_intake(u.intake_id,u.event_id);
  SELECT metadata INTO before_metadata FROM public.document_attachment_baselines WHERE document_id=u.document_id;
  SELECT current_version_id INTO version_id FROM public.documents WHERE id=u.document_id;
  IF public.attachment_scalar_disagrees(version_id,'document.reference_number','document.reference_number','" human / 154 "')
    OR public.attachment_scalar_disagrees(version_id,'document.reference_number','document.reference_number',to_jsonb(U&'HUMAN\2013154'::text))
    OR public.attachment_scalar_disagrees(version_id,'document.issued_by','document.issued_by',to_jsonb(U&'\00A0hUmAn\2003\2003AUTHORITY\00A0'::text))
    OR public.attachment_scalar_disagrees(version_id,'document.date','document.date','"2020/01/02"')
    OR public.attachment_scalar_disagrees(version_id,'document.type','document.type','" scn "')
    OR public.attachment_scalar_disagrees(version_id,'document.direction','document.direction','" INCOMING "') THEN RAISE EXCEPTION 'Harmless scalar formatting caused conflict'; END IF;
  IF NOT public.attachment_scalar_disagrees(version_id,'document.reference_number','document.reference_number','"HUMAN-155"')
    OR NOT public.attachment_scalar_disagrees(version_id,'document.issued_by','document.issued_by','"Other authority"')
    OR NOT public.attachment_scalar_disagrees(version_id,'document.date','document.date','"2021-01-02"') THEN RAISE EXCEPTION 'Scalar normalization hid genuine contradiction'; END IF;
  IF public.attachment_scalar_comparison('document.reference_number','SCN / 001 / 2020-21')<>public.attachment_scalar_comparison('document.reference_number','scn-001-2020/21')
    OR public.attachment_scalar_comparison('document.reference_number','SCN/001/2020-21')=public.attachment_scalar_comparison('document.reference_number','SCN/001/2021-22')
    OR public.attachment_scalar_comparison('document.reference_number','SCN/001')=public.attachment_scalar_comparison('document.reference_number','SCN/1')
    OR public.attachment_scalar_comparison('document.reference_number','SCN/12')=public.attachment_scalar_comparison('document.reference_number','SCN1/2')
    OR public.attachment_scalar_comparison('document.issued_by',U&'  M\00FCller\2003Office  ')<>public.attachment_scalar_comparison('document.issued_by',U&'M\00DCLLER OFFICE')
    OR public.attachment_scalar_comparison('document.tax_period','2020-21') IS NOT NULL
    OR public.attachment_scalar_comparison(NULL,'SCN') IS NOT NULL THEN RAISE EXCEPTION 'Conservative scalar comparison boundary failed'; END IF;
  PERFORM pg_temp.attachment_observation(u.document_id,'SCN');
  IF EXISTS(SELECT 1 FROM public.review_items WHERE document_id=u.document_id) THEN RAISE EXCEPTION 'Matching baseline created Review'; END IF;
  PERFORM pg_temp.attachment_observation(u.document_id,'OIO');
  IF (SELECT count(*) FROM public.review_items WHERE document_id=u.document_id AND status='needs_review')<>1 THEN RAISE EXCEPTION 'Expected one baseline conflict'; END IF;
  SELECT id INTO item FROM public.review_items WHERE document_id=u.document_id AND status='needs_review';
  PERFORM set_config('request.jwt.claim.sub','154a0000-0000-0000-0000-000000000001',true);
  detail:=public.read_review_detail(item);
  IF detail->'record_baseline'->>'value'<>'SCN' OR detail->'allowed_actions'<>'["request_clarification"]'::jsonb OR EXISTS(SELECT 1 FROM public.review_item_evidence WHERE review_item_id=item AND selectable) THEN RAISE EXCEPTION 'Baseline presented as selectable source: %',detail; END IF;
  IF EXISTS(SELECT 1 FROM public.document_effective_metadata WHERE document_id=u.document_id AND field_path='document.type' AND resolution='automatic') THEN RAISE EXCEPTION 'Conflicting automatic value leaked'; END IF;
  SELECT * INTO r FROM public.resolve_extraction_conflict(item,1,'request_clarification',NULL,'Confirm imported type against source page 2',gen_random_uuid());
  IF r.code<>'ok' OR (SELECT status FROM public.review_items WHERE id=item)<>'needs_review' THEN RAISE EXCEPTION 'Clarification failed'; END IF;
  PERFORM pg_temp.attachment_observation(u.document_id,'OIO');
  SELECT id INTO replacement_item FROM public.review_items WHERE document_id=u.document_id AND status='needs_review';
  IF replacement_item IS NULL OR (SELECT count(*) FROM public.review_items WHERE document_id=u.document_id AND status='needs_review')<>1
    OR (replacement_item<>item AND (SELECT closure_reason FROM public.review_items WHERE id=item) IS DISTINCT FROM 'source_replaced')
    OR NOT EXISTS(SELECT 1 FROM public.review_item_decisions WHERE review_item_id=item AND action='request_clarification')
    OR EXISTS(SELECT 1 FROM public.document_effective_metadata WHERE document_id=u.document_id AND field_path='document.type' AND resolution='automatic') THEN RAISE EXCEPTION 'Clarification suppressed later disagreement or rewrote history'; END IF;
  PERFORM pg_temp.attachment_observation(u.document_id,'SCN');
  IF EXISTS(SELECT 1 FROM public.review_items WHERE document_id=u.document_id AND status='needs_review') THEN RAISE EXCEPTION 'Matching new source failed to retire obsolete conflict'; END IF;
  IF (SELECT metadata FROM public.document_attachment_baselines WHERE document_id=u.document_id) IS DISTINCT FROM before_metadata THEN RAISE EXCEPTION 'Baseline mutated'; END IF;
  IF (SELECT jsonb_build_object('doc_type',d.doc_type,'reference_number',d.reference_number,'doc_date',d.doc_date,'direction',d.direction,'issued_by',d.issued_by,'financial_year',d.financial_year,'summary',d.summary,'raw_metadata',d.raw_metadata,'ai_prompt_version',d.ai_prompt_version) FROM public.documents d WHERE id=u.document_id) IS DISTINCT FROM before_metadata THEN RAISE EXCEPTION 'Later AI overwrote pre-attachment human metadata'; END IF;
  SELECT id INTO accepted FROM public.document_field_candidates WHERE document_id=u.document_id AND field_path='document.type' AND normalized_value='"SCN"'::jsonb ORDER BY materialization_sequence DESC LIMIT 1;
  PERFORM public.record_document_field_decision(accepted,'accepted',NULL,'Human confirms the imported type','154a0000-0000-0000-0000-000000000001','attachment.baseline.human');
  PERFORM pg_temp.attachment_observation(u.document_id,'OIO');
  IF NOT EXISTS(SELECT 1 FROM public.document_effective_metadata WHERE document_id=u.document_id AND winning_document_field_candidate_id=accepted AND resolution='accepted') THEN RAISE EXCEPTION 'Baseline bridge suppressed human field authority'; END IF;
END $$;
ROLLBACK;
