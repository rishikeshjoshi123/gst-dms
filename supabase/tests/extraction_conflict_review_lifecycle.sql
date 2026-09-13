\set ON_ERROR_STOP on
BEGIN;
-- Session-local fixture helper: uses the real validated finisher, never a provider.
CREATE FUNCTION pg_temp.finish_review_observation(p_document uuid,p_value text,p_review boolean) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE org uuid; version uuid; asset uuid; processing uuid:=gen_random_uuid(); run uuid:=gen_random_uuid(); lease uuid:=gen_random_uuid(); source_lease uuid:=gen_random_uuid(); finished record;
BEGIN
  SELECT d.org_id,d.current_version_id,v.asset_id INTO org,version,asset FROM public.documents d JOIN public.document_versions v ON v.id=d.current_version_id WHERE d.id=p_document;
  INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
    VALUES(processing,org,p_document,version,'full','fixture.lifecycle.'||processing,'running','extracting',now(),lease,now()+interval '10 minutes',now());
  INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at,attempt_count,lease_token,lease_expires_at,heartbeat_at)
    VALUES(run,org,asset,'ai_extraction.'||processing,'ai_extraction.'||processing,'ai_extraction','running','running','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4','gst-legal-material-observation-catalogue-v3','typed-material-observation-normalizer-v3',now(),1,source_lease,now()+interval '10 minutes',now());
  INSERT INTO public.source_analysis_attempts(org_id,source_analysis_run_id,attempt_number,state,retry_reason,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at)
    VALUES(org,run,1,'running','initial','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4','gst-legal-material-observation-catalogue-v3','typed-material-observation-normalizer-v3',now());
  UPDATE public.document_page_text_artifacts SET processing_run_id=processing,source_analysis_run_id=run WHERE document_id=p_document AND document_version_id=version;
  SELECT * INTO finished FROM public.finish_document_processing_ai_extraction(processing,lease,run,source_lease,'validated',1,1,1,
    jsonb_build_array(jsonb_build_object('semantic_candidate_key','document.type','field_path','document.type','value_type','code','normalized_value',p_value,'page_number',CASE WHEN p_value='SCN' THEN 1 ELSE 2 END,'quotation',p_value,'evidence_regions',NULL,'confidence',0.99,'validation_state','eligible','validation_error_codes',NULL,'verified_source_anchor',NULL)),p_review,
    jsonb_build_object('doc_type',p_value,'reference_number',NULL,'doc_date',NULL,'direction',NULL,'issued_by',NULL,'financial_years','[]'::jsonb,'summary','Fixture','prompt_version','v4.0'));
  IF finished.binding_id IS NULL THEN RAISE EXCEPTION 'Lifecycle finisher failed: %',finished.code; END IF;
  UPDATE public.document_processing_runs SET state='completed',stage='ready',completed_at=now(),lease_token=NULL,lease_expires_at=NULL WHERE id=processing AND state='running';
END $$;
DO $$
DECLARE doc uuid:='153e0000-0000-0000-0000-000000000001'; item uuid; selected uuid; result record; history bigint; fresh uuid;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','153a0000-0000-0000-0000-000000000001',true);
  SELECT id INTO item FROM public.review_items WHERE document_id=doc AND status='needs_review';
  SELECT candidate_id INTO selected FROM public.review_item_evidence WHERE review_item_id=item AND ordinal=2;
  SELECT * INTO result FROM public.resolve_extraction_conflict(item,1,'select_candidate',selected,'Human selects OIO',gen_random_uuid());
  IF result.code<>'ok' THEN RAISE EXCEPTION 'Lifecycle initial resolution failed'; END IF;
  SELECT count(*) INTO history FROM public.document_field_decisions WHERE document_id=doc;
  -- Repeating the accepted value must not reconsider immutable rejected SCN.
  PERFORM pg_temp.finish_review_observation(doc,'OIO',true);
  IF EXISTS(SELECT 1 FROM public.review_items WHERE document_id=doc AND status='needs_review') THEN RAISE EXCEPTION 'Accepted value repeat reopened Review'; END IF;
  IF (SELECT count(*) FROM public.review_items WHERE document_id=doc)<>1 THEN RAISE EXCEPTION 'Rejected history alone recreated conflict'; END IF;
  -- A genuinely fresh contradiction is compared with the human winner.
  PERFORM pg_temp.finish_review_observation(doc,'SCN',true);
  SELECT id INTO fresh FROM public.review_items WHERE document_id=doc AND status='needs_review';
  IF fresh IS NULL OR (SELECT count(*) FROM public.review_item_evidence WHERE review_item_id=fresh)<>2 OR NOT EXISTS(SELECT 1 FROM public.review_item_evidence WHERE review_item_id=fresh AND candidate_id=selected) THEN RAISE EXCEPTION 'Fresh contradiction did not retain accepted authority and exact fresh evidence'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.document_effective_metadata WHERE document_id=doc AND winning_document_field_candidate_id=selected AND resolution='accepted') THEN RAISE EXCEPTION 'Fresh conflict suppressed human authority'; END IF;
  -- Clean repeat of authority closes the unresolved later conflict, no replacement.
  PERFORM pg_temp.finish_review_observation(doc,'OIO',false);
  IF EXISTS(SELECT 1 FROM public.review_items WHERE document_id=doc AND status='needs_review') OR (SELECT closure_reason FROM public.review_items WHERE id=fresh)<>'source_replaced' THEN RAISE EXCEPTION 'Clean later run failed to retire obsolete conflict'; END IF;
  PERFORM pg_temp.finish_review_observation(doc,'OIO',true);
  IF (SELECT count(*) FROM public.review_items WHERE document_id=doc)<>2 THEN RAISE EXCEPTION 'Historical alternatives sustained conflict'; END IF;
  IF (SELECT count(*) FROM public.document_field_decisions WHERE document_id=doc)<>history THEN RAISE EXCEPTION 'Reconciliation rewrote human history'; END IF;
  -- Without any human decision, a new clean binding replaces unresolved history.
  doc:='153e0000-0000-0000-0000-000000000002';
  PERFORM pg_temp.finish_review_observation(doc,'OIO',false);
  IF EXISTS(SELECT 1 FROM public.review_items WHERE document_id=doc AND status='needs_review') OR NOT EXISTS(SELECT 1 FROM public.document_effective_metadata WHERE document_id=doc AND resolution='automatic') THEN RAISE EXCEPTION 'Clean replacement did not close and restore automatic authority'; END IF;
END $$;
ROLLBACK;
