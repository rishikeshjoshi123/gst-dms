-- Run after extraction_conflict_review_setup.sql on a disposable isolated DB.
\set ON_ERROR_STOP on
BEGIN;
DO $fixture$
DECLARE org uuid:='153b0000-0000-0000-0000-000000000001';
  doc uuid:='153e0000-0000-0000-0000-000000000001';
  version uuid:='15300000-0000-0000-0000-000000000001';
  asset uuid:='153f0000-0000-0000-0000-000000000001';
  processing uuid:=gen_random_uuid(); source_run uuid:=gen_random_uuid();
  processing_lease uuid:=gen_random_uuid(); source_lease uuid:=gen_random_uuid();
  candidate jsonb; finished record; item uuid; deadline uuid; rejected_item uuid; rejected_deadline uuid;
  actor uuid:='153a0000-0000-0000-0000-000000000001';
  copy_doc uuid:=gen_random_uuid(); copy_version uuid:=gen_random_uuid(); copy_binding uuid;
  decision_key uuid:=gen_random_uuid(); output record; before_count integer;
BEGIN
  INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
    VALUES(processing,org,doc,version,'full','fixture.due.'||processing,'running','extracting',now(),processing_lease,now()+interval '10 minutes',now());
  INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at,attempt_count,lease_token,lease_expires_at,heartbeat_at)
    VALUES(source_run,org,asset,'ai_extraction.'||processing,'ai_extraction.'||processing,'ai_extraction','running','running','vertex-ai','fixture-offline','fixture-model','v4.0','document-extraction-v4','gst-legal-material-observation-catalogue-v3','typed-material-observation-normalizer-v3',now(),1,source_lease,now()+interval '10 minutes',now());
  INSERT INTO public.source_analysis_attempts(org_id,source_analysis_run_id,attempt_number,state,retry_reason,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at)
    VALUES(org,source_run,1,'running','initial','vertex-ai','fixture-offline','fixture-model','v4.0','document-extraction-v4','gst-legal-material-observation-catalogue-v3','typed-material-observation-normalizer-v3',now());
  UPDATE public.document_page_text_artifacts SET processing_run_id=processing,source_analysis_run_id=source_run
    WHERE document_version_id=version AND org_id=org;
  UPDATE public.document_page_text_pages SET page_text='Reply must be filed by 2026-10-15. Payment is due 2026-10-20.'
    WHERE page_number=2 AND artifact_id=(SELECT id FROM public.document_page_text_artifacts WHERE document_version_id=version AND org_id=org);
  candidate:=jsonb_build_array(jsonb_build_object(
    'semantic_candidate_key','legal_date:explicit-fixture','field_path','document.legal_date.due','value_type','structured',
    'normalized_value',jsonb_build_object('meaning','due','raw','Reply must be filed by 2026-10-15.',
      'display','Reply must be filed by 2026-10-15.','precision','exact','normalized_date','2026-10-15',
      'proposed_normalized_date','2026-10-15','normalization_state','valid','validation_error',NULL,
      'catalogue_version','gst-legal-material-observation-catalogue-v3',
      'normalizer_version','typed-material-observation-normalizer-v3'),
    'page_number',2,'quotation','Reply must be filed by 2026-10-15.','evidence_regions',NULL,
    'confidence',0.98,'validation_state','provisional','validation_error_codes',NULL,
    'verified_source_anchor',jsonb_build_object('char_start',0,'char_end',34,'token_start',NULL,'token_end',NULL,'table_cell',NULL)));
  candidate:=candidate||jsonb_build_array(jsonb_build_object(
    'semantic_candidate_key','legal_date:reject-fixture','field_path','document.legal_date.due','value_type','structured',
    'normalized_value',jsonb_build_object('meaning','due','raw','Payment is due 2026-10-20.',
      'display','Payment is due 2026-10-20.','precision','exact','normalized_date','2026-10-20',
      'proposed_normalized_date','2026-10-20','normalization_state','valid','validation_error',NULL,
      'catalogue_version','gst-legal-material-observation-catalogue-v3',
      'normalizer_version','typed-material-observation-normalizer-v3'),
    'page_number',2,'quotation','Payment is due 2026-10-20.','evidence_regions',NULL,
    'confidence',0.94,'validation_state','provisional','validation_error_codes',NULL,
    'verified_source_anchor',jsonb_build_object('char_start',35,'char_end',61,'token_start',NULL,'token_end',NULL,'table_cell',NULL)));
  SELECT * INTO finished FROM public.finish_document_processing_ai_extraction(processing,processing_lease,source_run,source_lease,
    'validated',1,1,1,candidate,true,jsonb_build_object('doc_type','SCN','reference_number',NULL,
      'doc_date',NULL,'direction',NULL,'issued_by',NULL,'financial_years','[]'::jsonb,'summary','Fixture','prompt_version','v4.0'));
  IF finished.binding_id IS NULL THEN RAISE EXCEPTION 'Exact source completion did not bind'; END IF;
  SELECT d.id,i.id INTO deadline,item FROM public.deadlines d
    JOIN public.deadline_candidate_bindings b ON b.deadline_id=d.id AND b.org_id=d.org_id
    JOIN public.review_item_evidence e ON e.candidate_id=b.candidate_id
    JOIN public.review_items i ON i.id=e.review_item_id
    WHERE d.document_id=doc AND d.origin='document_explicit' AND i.type='deadline_verification'
      AND b.source_due_date='2026-10-15';
  IF deadline IS NULL OR item IS NULL OR (SELECT verification_state FROM public.deadlines WHERE id=deadline)<>'provisional'
    OR (SELECT count(*) FROM public.deadline_versions WHERE deadline_id=deadline)<>1
    OR (SELECT actor_user_id FROM public.deadline_versions WHERE deadline_id=deadline) IS NOT NULL
    THEN RAISE EXCEPTION 'Extraction invented human authority'; END IF;
  SELECT d.id,i.id INTO rejected_deadline,rejected_item FROM public.deadlines d
    JOIN public.deadline_candidate_bindings b ON b.deadline_id=d.id AND b.org_id=d.org_id
    JOIN public.review_item_evidence e ON e.candidate_id=b.candidate_id
    JOIN public.review_items i ON i.id=e.review_item_id
    WHERE d.document_id=doc AND d.origin='document_explicit' AND i.type='deadline_verification'
      AND b.source_due_date='2026-10-20';
  IF rejected_item IS NULL THEN RAISE EXCEPTION 'Independent source date lost'; END IF;
  before_count:=(SELECT count(*) FROM public.deadlines WHERE origin='document_explicit');
  PERFORM public.produce_explicit_due_date_review(finished.binding_id);
  PERFORM public.materialize_document_version_analysis(version,source_run,'processing_ai_extraction',NULL);
  IF (SELECT count(*) FROM public.deadlines WHERE origin='document_explicit')<>before_count THEN
    RAISE EXCEPTION 'Same candidate replay duplicated a deadline'; END IF;
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  IF (public.read_review_detail(item)->'allowed_actions')<>'["verify_deadline","correct_deadline","reject_deadline","clear_deadline"]'::jsonb
    OR (public.read_review_detail(item)#>>'{evidence,0,page_number}')::integer<>2
    THEN RAISE EXCEPTION 'Review exact evidence/actions missing'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.read_matter_manual_legal_deadline_agenda('153d0000-0000-0000-0000-000000000001') agenda
    WHERE agenda.items @> jsonb_build_array(jsonb_build_object('id',deadline,'verification_state','provisional')))
    THEN RAISE EXCEPTION 'Matter does not show truthful provisional date'; END IF;
  PERFORM set_config('request.jwt.claim.sub','153a0000-0000-0000-0000-000000000004',true);
  IF public.read_review_detail(item)->'allowed_actions'<>'[]'::jsonb
    OR (SELECT code FROM public.resolve_explicit_due_date_review(item,1,'verify',NULL,'Viewer attempt',gen_random_uuid()))<>'forbidden'
    THEN RAISE EXCEPTION 'Viewer could activate date'; END IF;
  PERFORM set_config('request.jwt.claim.sub','153a0000-0000-0000-0000-000000000005',true);
  IF public.read_review_detail(item) IS NOT NULL
    OR EXISTS(SELECT 1 FROM public.read_matter_manual_legal_deadline_agenda('153d0000-0000-0000-0000-000000000001'))
    OR (SELECT code FROM public.resolve_explicit_due_date_review(item,1,'verify',NULL,'Foreign tenant attempt',gen_random_uuid()))<>'unavailable'
    THEN RAISE EXCEPTION 'Cross-organisation due date disclosed'; END IF;
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  SELECT * INTO output FROM public.resolve_explicit_due_date_review(item,1,'correct','2026-10-17','PDF clarified source date',decision_key);
  IF output.code<>'ok' OR output.replayed OR (SELECT due_date FROM public.deadlines WHERE id=deadline)<>'2026-10-17'
    OR (SELECT verification_state FROM public.deadlines WHERE id=deadline)<>'verified'
    THEN RAISE EXCEPTION 'Correction did not activate exact human date'; END IF;
  SELECT * INTO output FROM public.resolve_explicit_due_date_review(item,1,'correct','2026-10-17','PDF clarified source date',decision_key);
  IF output.code<>'ok' OR NOT output.replayed THEN RAISE EXCEPTION 'Identical decision did not replay'; END IF;
  IF (SELECT code FROM public.resolve_explicit_due_date_review(item,1,'correct','2026-10-18','Changed decision',decision_key))<>'idempotency_conflict'
    OR (SELECT code FROM public.resolve_explicit_due_date_review(item,1,'verify',NULL,'Stale decision',gen_random_uuid()))<>'stale'
    OR (SELECT count(*) FROM public.deadline_candidate_decisions WHERE deadline_id=deadline)<>1
    THEN RAISE EXCEPTION 'Decision replay/CAS not fenced'; END IF;
  PERFORM public.produce_explicit_due_date_review(finished.binding_id);
  IF (SELECT count(*) FROM public.deadlines WHERE origin='document_explicit')<>before_count
    OR (SELECT due_date FROM public.deadlines WHERE id=deadline)<>'2026-10-17'
    THEN RAISE EXCEPTION 'Re-extraction overwrote human correction'; END IF;
  SELECT * INTO output FROM public.amend_manual_legal_deadline(deadline,2,'Verified reply due',
    'File the signed reply','reply_due','2026-10-19','Written extension checked by counsel',
    'Authority granted a later explicit date',gen_random_uuid());
  IF output.code<>'ok' OR output.revision<>3
    OR (SELECT due_date FROM public.deadlines WHERE id=deadline)<>'2026-10-19'
    OR (SELECT count(*) FROM public.deadline_versions WHERE deadline_id=deadline)<>3
    OR (SELECT code FROM public.amend_manual_legal_deadline(deadline,2,'Verified reply due',
      'File the signed reply','reply_due','2026-10-20','Written extension checked by counsel',
      'Stale update',gen_random_uuid()))<>'stale_revision'
    THEN RAISE EXCEPTION 'Human extracted-date amendment/history not governed'; END IF;
  PERFORM public.produce_explicit_due_date_review(finished.binding_id);
  IF (SELECT due_date FROM public.deadlines WHERE id=deadline)<>'2026-10-19'
    THEN RAISE EXCEPTION 'Re-extraction replaced later human amendment'; END IF;
  SELECT * INTO output FROM public.record_manual_legal_deadline_outcome(deadline,3,'satisfied',
    'Reply filed and acknowledged',gen_random_uuid());
  IF output.code<>'ok' OR (SELECT lifecycle FROM public.deadlines WHERE id=deadline)<>'satisfied'
    THEN RAISE EXCEPTION 'Verified extracted date cannot record its outcome'; END IF;
  SELECT * INTO output FROM public.resolve_explicit_due_date_review(rejected_item,1,'reject',NULL,
    'Page evidence does not establish this obligation',gen_random_uuid());
  IF output.code<>'ok' OR (SELECT verification_state FROM public.deadlines WHERE id=rejected_deadline)<>'rejected'
    OR EXISTS(SELECT 1 FROM public.read_matter_manual_legal_deadline_agenda('153d0000-0000-0000-0000-000000000001') agenda
      WHERE agenda.items @> jsonb_build_array(jsonb_build_object('id',rejected_deadline)))
    THEN RAISE EXCEPTION 'Rejected candidate became agenda authority'; END IF;
  UPDATE public.documents SET current_version_id=NULL WHERE id=doc;
  IF (SELECT total_count FROM public.read_review_queue('needs_review','deadline_verification'))<>0
    OR EXISTS(SELECT 1 FROM public.read_matter_manual_legal_deadline_agenda('153d0000-0000-0000-0000-000000000001') agenda
      WHERE agenda.items @> jsonb_build_array(jsonb_build_object('id',deadline)))
    THEN RAISE EXCEPTION 'Replaced source stayed actionable'; END IF;
  INSERT INTO public.documents(id,org_id,matter_id,display_title,document_class,origin_kind,
    content_availability,status,created_by)
    VALUES(copy_doc,org,'153d0000-0000-0000-0000-000000000001','Bounded Copy source',
      'proceeding','upload','source_attached','placed',actor);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,
    page_count,validation_state,state,validated_at,promoted_at,created_by)
    VALUES(copy_version,org,copy_doc,asset,1,'review-copy.pdf',4,'valid','current',now(),now(),actor);
  UPDATE public.documents SET current_version_id=copy_version WHERE id=copy_doc;
  copy_binding:=public.materialize_document_version_analysis(copy_version,source_run,'boundary_copy',actor);
  IF copy_binding IS NULL
    OR (SELECT count(*) FROM public.review_items WHERE document_id=copy_doc
      AND type='deadline_verification' AND status='needs_review')<>2
    OR (SELECT count(*) FROM public.deadline_candidate_bindings WHERE document_id=copy_doc)<>2
    THEN RAISE EXCEPTION 'Current same-tenant Copy did not project independent exact-source Review'; END IF;
  PERFORM public.materialize_document_version_analysis(copy_version,source_run,'boundary_copy',actor);
  IF (SELECT count(*) FROM public.deadline_candidate_bindings WHERE document_id=copy_doc)<>2
    THEN RAISE EXCEPTION 'Copy binder retry duplicated source dates'; END IF;
END $fixture$;
SET LOCAL ROLE authenticated;
DO $rls$
BEGIN
  BEGIN PERFORM 1 FROM public.deadline_candidate_bindings; RAISE EXCEPTION 'Bindings directly readable';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM 1 FROM public.deadline_candidate_decisions; RAISE EXCEPTION 'Decisions directly readable';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN INSERT INTO public.deadline_candidate_decisions DEFAULT VALUES; RAISE EXCEPTION 'Direct insert allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE public.deadline_candidate_decisions SET reason=reason WHERE false; RAISE EXCEPTION 'Direct update allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN DELETE FROM public.deadline_candidate_decisions WHERE false; RAISE EXCEPTION 'Direct delete allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN INSERT INTO public.deadline_candidate_bindings DEFAULT VALUES; RAISE EXCEPTION 'Binding insert allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE public.deadline_candidate_bindings SET org_id=org_id WHERE false; RAISE EXCEPTION 'Binding update allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN DELETE FROM public.deadline_candidate_bindings WHERE false; RAISE EXCEPTION 'Binding delete allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $rls$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $rls$
BEGIN
  BEGIN PERFORM 1 FROM public.deadline_candidate_bindings; RAISE EXCEPTION 'Service direct binding read allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN INSERT INTO public.deadline_candidate_decisions DEFAULT VALUES; RAISE EXCEPTION 'Service direct decision insert allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE public.deadline_candidate_bindings SET org_id=org_id WHERE false; RAISE EXCEPTION 'Service direct binding update allowed';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $rls$;
ROLLBACK;
SELECT 'explicit due date rollback fixture passed' AS result;
