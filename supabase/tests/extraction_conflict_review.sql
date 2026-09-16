\set ON_ERROR_STOP on
BEGIN;
DO $test$
DECLARE actor uuid:='153a0000-0000-0000-0000-000000000001'; org uuid:='153b0000-0000-0000-0000-000000000001'; item uuid; selected uuid; clarify uuid; result record; initial_count bigint; user_id uuid; i integer; rejected boolean; detail jsonb;
BEGIN
  SELECT id INTO item FROM public.review_items WHERE document_id='153e0000-0000-0000-0000-000000000001';
  SELECT candidate_id INTO selected FROM public.review_item_evidence WHERE review_item_id=item AND ordinal=2;
  SELECT id INTO clarify FROM public.review_items WHERE document_id='153e0000-0000-0000-0000-000000000003';
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  BEGIN
    PERFORM public.record_document_field_decision(selected,'accepted',NULL,'External human selection',actor,'fixture.external.review');
    PERFORM public.recompute_document_effective_metadata('15300000-0000-0000-0000-000000000001');
    IF NOT EXISTS(SELECT 1 FROM public.document_effective_metadata WHERE document_id='153e0000-0000-0000-0000-000000000001' AND resolution='accepted' AND winning_document_field_candidate_id=selected) THEN RAISE EXCEPTION 'Human winner was suppressed'; END IF;
    SELECT * INTO result FROM public.resolve_extraction_conflict(item,1,'select_candidate',selected,'Stale competing decision',gen_random_uuid());
    IF result.code<>'stale' THEN RAISE EXCEPTION 'Changed field authority was overwritten'; END IF;
    RAISE EXCEPTION 'rollback human authority probe';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'rollback human authority probe' THEN RAISE; END IF; END;
  SELECT * INTO result FROM public.read_review_queue('needs_review','all','all','',1,1);
  IF result.total_count<>8 OR jsonb_array_length(result.items)<>1 OR NOT result.can_resolve THEN RAISE EXCEPTION 'Queue pagination/count/authority failed'; END IF;
  IF EXISTS(SELECT 1 FROM public.document_effective_metadata WHERE document_id IN('153e0000-0000-0000-0000-000000000001','153e0000-0000-0000-0000-000000000002') AND resolution='automatic') THEN RAISE EXCEPTION 'Unresolved conflict leaked an automatic effective value'; END IF;
  IF (SELECT total_count FROM public.read_review_queue('closed'))<>0 OR (SELECT total_count FROM public.read_review_queue('all','all','all','Review source 1'))<>1 THEN RAISE EXCEPTION 'Queue filtering failed'; END IF;
  IF EXISTS(SELECT 1 FROM public.read_review_queue('bogus')) OR EXISTS(SELECT 1 FROM public.read_review_queue('all','all','all','',0,25)) THEN RAISE EXCEPTION 'Invalid filters accepted'; END IF;
  detail:=public.read_review_detail(item);
  IF detail->'allowed_actions'<>'["select_candidate", "request_clarification"]'::jsonb OR (detail#>>'{evidence,1,page_number}')::int<>2 OR detail->>'document_version_id'<>'15300000-0000-0000-0000-000000000001' THEN RAISE EXCEPTION 'Detail authority or exact evidence failed'; END IF;
  IF detail ? 'source_analysis_run_id' THEN RAISE EXCEPTION 'Extraction conflict leaked an irrelevant null source run'; END IF;
  IF public.read_review_detail(clarify)->'allowed_actions'<>'["request_clarification"]'::jsonb THEN RAISE EXCEPTION 'Conflicting observation is selectable'; END IF;
  IF (SELECT revision FROM public.review_items WHERE id=item)<>1 THEN RAISE EXCEPTION 'Reading mutated item'; END IF;
  SELECT count(*) INTO initial_count FROM public.review_items;
  PERFORM public.produce_extraction_conflict_review(document_version_analysis_binding_id) FROM public.document_field_candidates WHERE document_id='153e0000-0000-0000-0000-000000000001';
  IF (SELECT count(*) FROM public.review_items)<>initial_count THEN RAISE EXCEPTION 'Producer did not dedupe'; END IF;
  FOR i IN 4..7 LOOP
    user_id:=('153a0000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
    PERFORM set_config('request.jwt.claim.sub',user_id::text,true);
    SELECT * INTO result FROM public.resolve_extraction_conflict(item,1,'select_candidate',selected,'Supported source',gen_random_uuid());
    IF result.code NOT IN ('forbidden','unavailable') THEN RAISE EXCEPTION 'Forbidden user % resolved: %',i,result.code; END IF;
    IF i=4 THEN
      IF public.read_review_detail(item)->'allowed_actions'<>'[]'::jsonb THEN RAISE EXCEPTION 'Viewer received actions'; END IF;
    ELSIF public.read_review_detail(item) IS NOT NULL THEN RAISE EXCEPTION 'Unavailable actor saw detail'; END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  SELECT * INTO result FROM public.resolve_extraction_conflict(item,1,'request_clarification',NULL,'',gen_random_uuid());
  IF result.code<>'invalid_request' THEN RAISE EXCEPTION 'Empty reason accepted'; END IF;
  SELECT * INTO result FROM public.resolve_extraction_conflict(clarify,1,'select_candidate',(SELECT candidate_id FROM public.review_item_evidence WHERE review_item_id=clarify LIMIT 1),'Unsupported',gen_random_uuid());
  IF result.code<>'invalid_candidate' THEN RAISE EXCEPTION 'Clarification-only item accepted selection'; END IF;
  SELECT * INTO result FROM public.resolve_extraction_conflict(item,1,'select_candidate',gen_random_uuid(),'Foreign candidate',gen_random_uuid());
  IF result.code<>'invalid_candidate' THEN RAISE EXCEPTION 'Unrelated candidate accepted'; END IF;
  -- Append/outbox failure must roll back domain decisions and item state.
  ALTER TABLE public.activity_projector_outbox_events ADD CONSTRAINT review_fault CHECK(false) NOT VALID;
  rejected:=false;
  BEGIN PERFORM public.resolve_extraction_conflict(item,1,'select_candidate',selected,'Fault probe',gen_random_uuid()); EXCEPTION WHEN check_violation THEN rejected:=true; END;
  ALTER TABLE public.activity_projector_outbox_events DROP CONSTRAINT review_fault;
  IF NOT rejected OR EXISTS(SELECT 1 FROM public.review_item_decisions WHERE review_item_id=item) OR EXISTS(SELECT 1 FROM public.document_field_decisions WHERE document_id='153e0000-0000-0000-0000-000000000001') OR (SELECT revision FROM public.review_items WHERE id=item)<>1 THEN RAISE EXCEPTION 'Resolver did not roll back atomically'; END IF;
  FOR i IN 1..3 LOOP
    PERFORM set_config('request.jwt.claim.sub',('153a0000-0000-0000-0000-'||lpad(i::text,12,'0')),true);
    SELECT * INTO result FROM public.resolve_extraction_conflict(item,i,'request_clarification',NULL,'Check both source pages',('15390000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid);
    IF result.code<>'ok' OR result.current_item->>'status'<>'needs_review' THEN RAISE EXCEPTION 'Role % clarification failed: %',i,result.code; END IF;
    IF EXISTS(SELECT 1 FROM public.document_effective_metadata WHERE document_id='153e0000-0000-0000-0000-000000000001' AND resolution='automatic') THEN RAISE EXCEPTION 'Clarification published unresolved automatic value'; END IF;
  END LOOP;
  SELECT * INTO result FROM public.resolve_extraction_conflict(item,4,'select_candidate',selected,'Supported by page two','15390000-0000-0000-0000-000000000004');
  IF result.code<>'ok' OR result.current_item->>'status'<>'closed' THEN RAISE EXCEPTION 'Selection failed: %',result.code; END IF;
  SELECT * INTO result FROM public.resolve_extraction_conflict(item,4,'select_candidate',selected,'Supported by page two','15390000-0000-0000-0000-000000000004');
  IF result.code<>'ok' OR NOT result.replayed THEN RAISE EXCEPTION 'Replay failed'; END IF;
  SELECT * INTO result FROM public.resolve_extraction_conflict(item,4,'select_candidate',selected,'Changed reason','15390000-0000-0000-0000-000000000004');
  IF result.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'Conflicting replay accepted'; END IF;
  SELECT * INTO result FROM public.resolve_extraction_conflict(item,4,'request_clarification',NULL,'Stale',gen_random_uuid());
  IF result.code<>'stale' OR result.current_item->>'status'<>'closed' THEN RAISE EXCEPTION 'Stale loser did not receive closed state'; END IF;
  IF (SELECT count(*) FROM public.document_field_decisions WHERE document_id='153e0000-0000-0000-0000-000000000001')<>2 OR NOT EXISTS(SELECT 1 FROM public.document_effective_metadata WHERE document_id='153e0000-0000-0000-0000-000000000001' AND resolution='accepted' AND winning_document_field_candidate_id=selected) THEN RAISE EXCEPTION 'Competing candidate decisions or effective winner failed'; END IF;
  IF (SELECT count(*) FROM public.activity_events WHERE correlation_id=item)<>4 OR (SELECT count(*) FROM public.activity_projector_outbox_events o JOIN public.activity_events e ON e.id=o.activity_event_id WHERE e.correlation_id=item)<>4 THEN RAISE EXCEPTION 'Activity/outbox effects are not exact'; END IF;
  BEGIN UPDATE public.review_item_decisions SET reason='Changed' WHERE review_item_id=item; RAISE EXCEPTION 'Mutable decision'; EXCEPTION WHEN raise_exception THEN IF SQLERRM='Mutable decision' THEN RAISE; END IF; END;
  -- Trash is excluded from both counts and direct-ID readers.
  UPDATE public.clients SET deleted_at=now() WHERE id='153c0000-0000-0000-0000-000000000001';
  IF public.read_review_detail(item) IS NOT NULL OR (SELECT total_count FROM public.read_review_queue('all'))<>0 THEN RAISE EXCEPTION 'Trashed parent leaked'; END IF;
  UPDATE public.clients SET deleted_at=NULL WHERE id='153c0000-0000-0000-0000-000000000001';
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  -- Replacing the current pointer closes old-version active Review.
  UPDATE public.documents SET current_version_id=NULL WHERE id='153e0000-0000-0000-0000-000000000003';
  IF (SELECT closure_reason FROM public.review_items WHERE id=clarify)<>'source_replaced' THEN RAISE EXCEPTION 'Source replacement did not close item'; END IF;
  IF public.read_review_detail(clarify)->'allowed_actions'<>'[]'::jsonb THEN RAISE EXCEPTION 'Old version exposes mutation'; END IF;
  FOR i IN 1..3 LOOP
    IF NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid=('public.'||CASE i WHEN 1 THEN 'review_items' WHEN 2 THEN 'review_item_evidence' ELSE 'review_item_decisions' END)::regclass) THEN RAISE EXCEPTION 'Private table lacks force RLS'; END IF;
  END LOOP;
END $test$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN PERFORM 1 FROM public.review_items; RAISE EXCEPTION 'Direct private read allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.produce_extraction_conflict_review(gen_random_uuid()); RAISE EXCEPTION 'Direct producer allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$
DECLARE role_name text; table_name text; command text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['authenticated','service_role'] LOOP
    EXECUTE format('SET LOCAL ROLE %I',role_name);
    FOREACH table_name IN ARRAY ARRAY['review_items','review_item_evidence','review_item_decisions'] LOOP
      FOREACH command IN ARRAY ARRAY[
        format('INSERT INTO public.%I DEFAULT VALUES',table_name),
        format('UPDATE public.%I SET org_id=org_id WHERE false',table_name),
        format('DELETE FROM public.%I WHERE false',table_name)
      ] LOOP
        BEGIN
          EXECUTE command;
          RAISE EXCEPTION 'Direct write allowed for %: %',role_name,command;
        EXCEPTION WHEN insufficient_privilege THEN NULL;
        END;
      END LOOP;
    END LOOP;
    RESET ROLE;
  END LOOP;
END $$;
ROLLBACK;
