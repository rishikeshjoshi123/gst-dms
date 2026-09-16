\set ON_ERROR_STOP on
BEGIN;
DO $test$
DECLARE
  actor uuid:='153a0000-0000-0000-0000-000000000001';
  admin uuid:='153a0000-0000-0000-0000-000000000002';
  associate uuid:='153a0000-0000-0000-0000-000000000003';
  viewer uuid:='153a0000-0000-0000-0000-000000000004';
  resolving_member uuid;
  recovery uuid; conflict uuid; result record; detail jsonb;
  key uuid:='15790000-0000-0000-0000-000000000001';
  metadata jsonb:='{"doc_type":"SCN","reference_number":"SCN/MANUAL/42","document_date":"2026-09-15","direction":"incoming","issued_by":"GST Authority"}';
BEGIN
  SELECT id INTO recovery FROM public.review_items
    WHERE document_id='153e0000-0000-0000-0000-000000000005' AND type='processing_recovery';
  SELECT id INTO conflict FROM public.review_items WHERE type='extraction_conflict' LIMIT 1;
  IF recovery IS NULL OR (SELECT count(*) FROM public.review_items WHERE document_id='153e0000-0000-0000-0000-000000000005' AND type='processing_recovery')<>1 THEN RAISE EXCEPTION 'Terminal failure did not produce exactly one typed recovery item'; END IF;
  PERFORM public.produce_processing_recovery_review(
    (SELECT processing_run_id FROM public.review_items WHERE id=recovery),
    (SELECT source_analysis_run_id FROM public.review_items WHERE id=recovery),'invalid_model_output');
  IF (SELECT count(*) FROM public.review_items WHERE document_id='153e0000-0000-0000-0000-000000000005' AND type='processing_recovery')<>1 THEN RAISE EXCEPTION 'Recovery producer did not dedupe'; END IF;
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  SELECT * INTO result FROM public.read_review_queue('needs_review','processing_recovery','high','Review source 5',1,25);
  IF result.total_count<>1 OR result.items#>>'{0,reason_code}'<>'invalid_model_output'
    OR result.items::text ~* 'provider.response|raw.response|prompt|storage.path' THEN RAISE EXCEPTION 'Recovery queue is unsafe or incomplete'; END IF;
  detail:=public.read_review_detail(recovery);
  IF detail->'allowed_actions'<>'["continue_manual"]' OR detail->>'source_identity'<>'Document version 1'
    OR detail->>'source_page_number'<>'1' OR jsonb_array_length(detail->'evidence')<>0 THEN RAISE EXCEPTION 'Recovery detail authority/source shape failed: %',detail; END IF;
  IF (detail->>'source_analysis_run_id') IS NULL OR NOT (detail->>'source_analysis_run_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') THEN RAISE EXCEPTION 'Processing recovery lost its owned source run: %',detail; END IF;
  FOREACH resolving_member IN ARRAY ARRAY[actor,admin,associate] LOOP
    PERFORM set_config('request.jwt.claim.sub',resolving_member::text,true);
    IF public.read_review_detail(recovery)->'allowed_actions'<>'["continue_manual"]'::jsonb THEN
      RAISE EXCEPTION 'Owner/Admin/Associate recovery authority failed for %',resolving_member;
    END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  BEGIN
    UPDATE public.documents SET current_version_id=NULL WHERE id='153e0000-0000-0000-0000-000000000005';
    IF (SELECT closure_reason FROM public.review_items WHERE id=recovery)<>'source_replaced'
      OR public.read_review_detail(recovery)->'allowed_actions'<>'[]'::jsonb THEN RAISE EXCEPTION 'Recovery source replacement did not close safely'; END IF;
    RAISE EXCEPTION 'rollback recovery replacement probe';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'rollback recovery replacement probe' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
  IF public.read_review_detail(recovery)->'allowed_actions'<>'[]'::jsonb THEN RAISE EXCEPTION 'Viewer received recovery authority'; END IF;
  SELECT * INTO result FROM public.resolve_processing_recovery(recovery,1,'continue_manual',metadata,'Viewer attempt',gen_random_uuid());
  IF result.code<>'forbidden' THEN RAISE EXCEPTION 'Viewer resolved recovery'; END IF;
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  SELECT * INTO result FROM public.resolve_processing_recovery(recovery,1,'continue_manual',metadata-'document_date','Missing date',gen_random_uuid());
  IF result.code<>'invalid_request' THEN RAISE EXCEPTION 'Incomplete manual metadata accepted'; END IF;
  SELECT * INTO result FROM public.resolve_processing_recovery(conflict,1,'continue_manual',metadata,'Wrong type',gen_random_uuid());
  IF result.code<>'unavailable' THEN RAISE EXCEPTION 'Recovery resolver accepted another Review type'; END IF;
  SELECT * INTO result FROM public.resolve_processing_recovery(recovery,1,'continue_manual',metadata,'Verified against the immutable PDF.',key);
  IF result.code<>'ok' OR result.replayed OR result.current_item->>'status'<>'closed' THEN RAISE EXCEPTION 'Manual continuation failed: %',result.code; END IF;
  IF (SELECT count(*) FROM public.document_field_candidates WHERE manual_review_item_id=recovery AND origin_kind='manual_recovery')<>5
    OR (SELECT count(*) FROM public.document_field_decisions d JOIN public.document_field_candidates c ON c.id=d.document_field_candidate_id WHERE c.manual_review_item_id=recovery AND d.action='accepted')<>5 THEN RAISE EXCEPTION 'Canonical manual candidate/decision set is incomplete'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.document_effective_metadata WHERE document_id='153e0000-0000-0000-0000-000000000005' AND field_path='document.type' AND normalized_value='"SCN"' AND resolution='accepted')
    OR NOT EXISTS(SELECT 1 FROM public.document_effective_metadata WHERE document_id='153e0000-0000-0000-0000-000000000005' AND field_path='document.reference_number' AND normalized_value='"SCN/MANUAL/42"' AND resolution='accepted')
    OR NOT EXISTS(SELECT 1 FROM public.document_effective_metadata WHERE document_id='153e0000-0000-0000-0000-000000000005' AND field_path='document.date' AND normalized_value='"2026-09-15"' AND resolution='accepted') THEN RAISE EXCEPTION 'Manual metadata did not become effective'; END IF;
  IF (SELECT status FROM public.documents WHERE id='153e0000-0000-0000-0000-000000000005')<>'analyzed'
    OR (SELECT review_reason FROM public.documents WHERE id='153e0000-0000-0000-0000-000000000005') IS NOT NULL THEN RAISE EXCEPTION 'Matching recovery state was not cleared'; END IF;
  IF (SELECT count(*) FROM public.activity_events WHERE correlation_id=recovery AND event_type='review.processing_recovery_decided')<>1
    OR (SELECT count(*) FROM public.activity_projector_outbox_events o JOIN public.activity_events e ON e.id=o.activity_event_id WHERE e.correlation_id=recovery)<>1
    OR EXISTS(SELECT 1 FROM public.outbox_events WHERE aggregate_id='153e0000-0000-0000-0000-000000000005' AND payload->>'scope'='extract') THEN RAISE EXCEPTION 'Activity/outbox effects are not exact or extraction retry was queued'; END IF;
  SELECT * INTO result FROM public.resolve_processing_recovery(recovery,1,'continue_manual',metadata,'Verified against the immutable PDF.',key);
  IF result.code<>'ok' OR NOT result.replayed THEN RAISE EXCEPTION 'Exact replay failed'; END IF;
  SELECT * INTO result FROM public.resolve_processing_recovery(recovery,1,'continue_manual',jsonb_set(metadata,'{reference_number}','"CHANGED"'),'Verified against the immutable PDF.',key);
  IF result.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'Changed replay was accepted'; END IF;
  IF (SELECT count(*) FROM public.document_field_candidates WHERE manual_review_item_id=recovery)<>5 THEN RAISE EXCEPTION 'Replay duplicated manual facts'; END IF;
END $test$;
ROLLBACK;
