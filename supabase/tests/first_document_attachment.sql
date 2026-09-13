BEGIN;
DO $$
DECLARE role_name text; table_name text; operation text; denied boolean;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['authenticated','service_role'] LOOP
    FOREACH table_name IN ARRAY ARRAY['document_attachment_intents','document_attachment_baselines'] LOOP
      FOREACH operation IN ARRAY ARRAY['SELECT * FROM %I LIMIT 0','INSERT INTO %I DEFAULT VALUES','UPDATE %I SET org_id=org_id WHERE false','DELETE FROM %I WHERE false'] LOOP
        EXECUTE format('SET LOCAL ROLE %I',role_name);
        denied:=false;
        BEGIN EXECUTE format(operation,table_name); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
        RESET ROLE;
        IF NOT denied THEN RAISE EXCEPTION 'private write/read permitted: % % %',role_name,table_name,operation; END IF;
      END LOOP;
    END LOOP;
  END LOOP;
END $$;
DO $$
DECLARE r record; u attachment_test.uploads%ROWTYPE; actor uuid; denied boolean;
BEGIN
  FOREACH actor IN ARRAY ARRAY['154a0000-0000-0000-0000-000000000003'::uuid,'154a0000-0000-0000-0000-000000000004'::uuid] LOOP
    PERFORM set_config('request.jwt.claim.sub',actor::text,true);
    SET LOCAL ROLE authenticated;
    SELECT * INTO r FROM public.reserve_document_attachment('154e0000-0000-0000-0000-000000000008','denied.pdf',4530,gen_random_uuid());
    RESET ROLE;
    IF r.code NOT IN ('not_allowed','target_unavailable') THEN RAISE EXCEPTION 'Viewer/foreign reservation permitted'; END IF;
  END LOOP;
  SELECT * INTO u FROM attachment_test.uploads WHERE n=8;
  SELECT * INTO r FROM public.cancel_document_upload(u.session_id,u.idempotency,'154a0000-0000-0000-0000-000000000001','154b0000-0000-0000-0000-000000000001');
  IF r.code<>'cancelled' THEN RAISE EXCEPTION 'Cancel failed'; END IF;
  SELECT * INTO r FROM public.complete_document_upload(u.session_id,4530,repeat('8',64),'application/pdf',u.idempotency,'154a0000-0000-0000-0000-000000000001','154b0000-0000-0000-0000-000000000001');
  IF r.code='ok' THEN RAISE EXCEPTION 'Cancelled upload finalized'; END IF;
  SELECT * INTO u FROM attachment_test.uploads WHERE n=5;
  UPDATE public.documents SET display_title='Changed after reservation' WHERE id=u.document_id;
  -- An ordinary title edit is preserved, not a materialisation retarget.
  UPDATE public.documents SET lifecycle_revision=lifecycle_revision+1 WHERE id=u.document_id;
  SELECT * INTO r FROM public.auto_assign_intended_matter_intake(u.intake_id,u.event_id);
  IF r.code<>'stale_target' OR EXISTS(SELECT 1 FROM public.document_versions WHERE document_id=u.document_id) THEN RAISE EXCEPTION 'Stale target attached: %',r.code; END IF;
  SELECT * INTO u FROM attachment_test.uploads WHERE n=6;
  PERFORM set_config('request.jwt.claim.sub','154a0000-0000-0000-0000-000000000001',true);
  SET LOCAL ROLE authenticated;
  SELECT * INTO r FROM public.attach_intake_to_document(u.document_id,u.intake_id,1,'154a0000-0000-0000-0000-000000000004',gen_random_uuid());
  RESET ROLE;
  IF r.code<>'intake_unavailable' THEN RAISE EXCEPTION 'Legacy command bypassed bound intent'; END IF;
  denied:=false;
  BEGIN UPDATE public.document_attachment_intents SET document_id='154e0000-0000-0000-0000-000000000008' WHERE intake_item_id=u.intake_id; EXCEPTION WHEN raise_exception THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Intent was mutable'; END IF;
END $$;
DO $$
DECLARE u attachment_test.uploads%ROWTYPE; r record; before_metadata jsonb; v uuid; original_count integer;
BEGIN
  SELECT * INTO u FROM attachment_test.uploads WHERE n=3;
  SELECT to_jsonb(d)-ARRAY['current_version_id','content_availability','effective_filename','effective_size_bytes','lifecycle_revision','lifecycle_updated_at','updated_at'] INTO before_metadata FROM public.documents d WHERE id=u.document_id;
  -- Finalized while valid, asynchronous validation/attachment after expiry.
  UPDATE public.upload_sessions SET created_at=now()-interval '2 days',expires_at=now()-interval '1 day',uploaded_at=now()-interval '2 days'+interval '1 hour',finalized_at=now()-interval '2 days'+interval '1 hour' WHERE id=u.session_id;
  SELECT count(*) INTO original_count FROM public.documents;
  SELECT * INTO r FROM public.auto_assign_intended_matter_intake(u.intake_id,u.event_id);
  IF r.code<>'ok' OR r.document_id<>u.document_id THEN RAISE EXCEPTION 'same-record attachment: %',r; END IF; v:=r.document_version_id;
  IF (SELECT count(*) FROM public.documents)<>original_count OR (SELECT version_number FROM public.document_versions WHERE id=v)<>1 THEN RAISE EXCEPTION 'new document or replacement'; END IF;
  IF (SELECT to_jsonb(d)-ARRAY['current_version_id','content_availability','effective_filename','effective_size_bytes','lifecycle_revision','lifecycle_updated_at','updated_at'] FROM public.documents d WHERE id=u.document_id) IS DISTINCT FROM before_metadata THEN RAISE EXCEPTION 'human metadata changed: %',(SELECT jsonb_object_agg(kv.k,kv.v) FROM public.documents d CROSS JOIN LATERAL jsonb_each(to_jsonb(d)) kv(k,v) WHERE d.id=u.document_id AND before_metadata ? kv.k AND before_metadata->kv.k IS DISTINCT FROM kv.v); END IF;
  SELECT * INTO r FROM public.auto_assign_intended_matter_intake(u.intake_id,u.event_id);
  IF r.code<>'ok' OR r.document_version_id<>v THEN RAISE EXCEPTION 'routing replay'; END IF;
  PERFORM set_config('request.jwt.claim.sub','154a0000-0000-0000-0000-000000000001',true);
  SELECT * INTO r FROM public.reserve_document_attachment(u.document_id,'attachment-3.pdf',4530,u.idempotency);
  IF r.code<>'already_completed' OR r.upload_session_id<>u.session_id THEN RAISE EXCEPTION 'completed reservation replay: %',r; END IF;
  SELECT * INTO r FROM public.reserve_document_attachment(u.document_id,'different.pdf',4530,u.idempotency);
  IF r.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'filename retarget'; END IF;
  SELECT * INTO r FROM public.reserve_document_attachment('154e0000-0000-0000-0000-000000000004','attachment-3.pdf',4530,u.idempotency);
  IF r.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'document retarget'; END IF;
  IF (SELECT count(*) FROM public.activity_events WHERE subject_id=u.document_id AND event_type='document.file_attached')<>1 OR (SELECT count(*) FROM public.outbox_events WHERE aggregate_id=u.document_id AND event_kind='document.processing_requested.v1')<>1 THEN RAISE EXCEPTION 'attachment side effect count'; END IF;
END $$;
ROLLBACK;
