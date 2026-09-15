\set ON_ERROR_STOP on
BEGIN;
DO $test$
DECLARE
  actor uuid:='153a0000-0000-0000-0000-000000000001';
  viewer uuid:='153a0000-0000-0000-0000-000000000004';
  org uuid:='153b0000-0000-0000-0000-000000000001';
  client_id uuid:='153c0000-0000-0000-0000-000000000001';
  matter_a uuid:='162d0000-0000-0000-0000-000000000001';
  matter_b uuid:='162d0000-0000-0000-0000-000000000002';
  asset_id uuid:='162f0000-0000-0000-0000-000000000001';
  session_id uuid:='16280000-0000-0000-0000-000000000001';
  fixture_intake_id uuid:='16270000-0000-0000-0000-000000000001';
  intended_intake uuid:='16270000-0000-0000-0000-000000000002';
  item_id uuid; candidate_id uuid; key uuid:='16290000-0000-0000-0000-000000000001';
  produced record; resolved record; detail jsonb; before_count bigint;
  candidates jsonb:=jsonb_build_array(
    jsonb_build_object('matter_id',matter_a,'evidence',jsonb_build_array(jsonb_build_object('kind','matter_code_exact','source_page_number',NULL))),
    jsonb_build_object('matter_id',matter_b,'evidence',jsonb_build_array(jsonb_build_object('kind','referenced_document_exact','source_page_number',1)))
  );
BEGIN
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code) VALUES
    (matter_a,org,client_id,'First eligible proceeding','PLACEMENT-01'),
    (matter_b,org,client_id,'Second eligible proceeding','PLACEMENT-02');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
    VALUES(asset_id,org,'documents','orgs/'||org||'/assets/'||asset_id||'/original.pdf',repeat('b',64),4530,'application/pdf','available',now(),4,actor);
  INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,uploaded_at,finalized_at)
    VALUES(session_id,org,asset_id,'ambiguous-intake.pdf','application/pdf',4530,'finalized',actor,now(),now());
  INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,state,uploaded_by)
    VALUES(fixture_intake_id,org,asset_id,session_id,'ready',actor);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  SELECT * INTO produced FROM public.produce_ambiguous_intake_placement_review(fixture_intake_id,'trusted-placement-v1',candidates);
  item_id:=produced.review_item_id;
  IF produced.code<>'ok' OR item_id IS NULL OR (SELECT count(*) FROM public.review_items WHERE intake_id=fixture_intake_id)<>1 THEN
    RAISE EXCEPTION 'Trusted multi-candidate producer did not create exactly one item';
  END IF;
  SELECT * INTO produced FROM public.produce_ambiguous_intake_placement_review(fixture_intake_id,'trusted-placement-v1',candidates);
  IF produced.review_item_id<>item_id OR (SELECT count(*) FROM public.intake_placement_runs WHERE intake_id=fixture_intake_id)<>1 THEN
    RAISE EXCEPTION 'Trusted producer replay did not dedupe';
  END IF;
  -- Matter-origin Intake remains outside this packet even if candidates exist.
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
    VALUES('162f0000-0000-0000-0000-000000000002',org,'documents','orgs/'||org||'/assets/162f0000-0000-0000-0000-000000000002/original.pdf',repeat('c',64),100,'application/pdf','available',now(),1,actor);
  INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,uploaded_at,finalized_at)
    VALUES('16280000-0000-0000-0000-000000000002',org,'162f0000-0000-0000-0000-000000000002','intended.pdf','application/pdf',100,'finalized',actor,now(),now());
  INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,intended_matter_id,state,uploaded_by)
    VALUES(intended_intake,org,'162f0000-0000-0000-0000-000000000002','16280000-0000-0000-0000-000000000002',matter_a,'ready',actor);
  SELECT * INTO produced FROM public.produce_ambiguous_intake_placement_review(intended_intake,'trusted-placement-v1',candidates);
  IF produced.code<>'ineligible_intake' OR EXISTS(SELECT 1 FROM public.review_items WHERE intake_id=intended_intake) THEN
    RAISE EXCEPTION 'Matter-origin Intake entered ambiguous placement Review';
  END IF;
  -- Ordinary ready global Intake has no Review until a trusted run explicitly reports ambiguity.
  IF EXISTS(SELECT 1 FROM public.review_items WHERE intake_id=intended_intake) THEN RAISE EXCEPTION 'Ordinary Intake entered Review'; END IF;
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  SELECT * INTO produced FROM public.produce_ambiguous_intake_placement_review(fixture_intake_id,'browser-forged-v1',candidates);
  IF produced.code<>'invalid_request' THEN RAISE EXCEPTION 'Browser invoked trusted producer'; END IF;
  detail:=public.read_review_detail(item_id);
  IF detail->'allowed_actions'<>'["select_destination"]'::jsonb OR jsonb_array_length(detail->'evidence')<>2
    OR detail->>'intake_id'<>fixture_intake_id::text OR detail::text ~* 'bucket_id|object_key|confidence|provider' THEN
    RAISE EXCEPTION 'Placement detail is unsafe or incomplete: %',detail;
  END IF;
  PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
  IF public.read_review_detail(item_id)->'allowed_actions'<>'[]'::jsonb THEN RAISE EXCEPTION 'Viewer received placement authority'; END IF;
  SELECT * INTO resolved FROM public.resolve_ambiguous_intake_placement(item_id,1,
    (SELECT id FROM public.intake_placement_candidates WHERE placement_run_id=produced.placement_run_id LIMIT 1),
    'Viewer decision',gen_random_uuid());
  IF resolved.code<>'forbidden' THEN RAISE EXCEPTION 'Viewer resolved placement'; END IF;
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  SELECT id INTO candidate_id FROM public.intake_placement_candidates WHERE placement_run_id=(SELECT placement_run_id FROM public.review_items WHERE id=item_id) AND matter_id=matter_b;
  SELECT * INTO resolved FROM public.resolve_ambiguous_intake_placement(item_id,1,candidate_id,'Exact referenced document identifies this proceeding.',key);
  IF resolved.code<>'ok' OR resolved.replayed OR resolved.matter_id<>matter_b OR resolved.document_id IS NULL OR resolved.document_version_id IS NULL THEN
    RAISE EXCEPTION 'Typed placement failed: %',resolved.code;
  END IF;
  IF (SELECT matter_id FROM public.documents WHERE id=resolved.document_id)<>matter_b
    OR (SELECT current_version_id FROM public.documents WHERE id=resolved.document_id)<>resolved.document_version_id
    OR (SELECT state FROM public.intake_items WHERE id=fixture_intake_id)<>'assigned'
    OR (SELECT count(*) FROM public.intake_item_assignments WHERE intake_item_id=fixture_intake_id)<>1
    OR (SELECT count(*) FROM public.review_item_decisions WHERE review_item_id=item_id)<>1
    OR (SELECT count(*) FROM public.intake_placement_decisions WHERE review_item_id=item_id)<>1
    OR (SELECT count(*) FROM public.activity_events WHERE correlation_id=item_id AND event_type='review.ambiguous_placement_decided')<>1
    OR (SELECT count(*) FROM public.activity_projector_outbox_events o JOIN public.activity_events e ON e.id=o.activity_event_id WHERE e.correlation_id=item_id)<>1 THEN
    RAISE EXCEPTION 'Atomic placement effects are incomplete';
  END IF;
  SELECT * INTO resolved FROM public.resolve_ambiguous_intake_placement(item_id,1,candidate_id,'Exact referenced document identifies this proceeding.',key);
  IF resolved.code<>'ok' OR NOT resolved.replayed OR resolved.matter_id<>matter_b THEN RAISE EXCEPTION 'Exact replay failed'; END IF;
  SELECT * INTO resolved FROM public.resolve_ambiguous_intake_placement(item_id,1,candidate_id,'Changed reason',key);
  IF resolved.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'Mismatched replay succeeded'; END IF;
  before_count:=(SELECT count(*) FROM public.documents WHERE org_id=org);
  SELECT * INTO resolved FROM public.resolve_ambiguous_intake_placement(item_id,1,candidate_id,'Second decision',gen_random_uuid());
  IF resolved.code<>'stale' OR (SELECT count(*) FROM public.documents WHERE org_id=org)<>before_count THEN RAISE EXCEPTION 'Stale decision mutated'; END IF;
  IF has_table_privilege('authenticated','public.intake_placement_runs','INSERT,UPDATE,DELETE')
    OR has_table_privilege('service_role','public.intake_placement_candidates','INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'Direct placement-table DML privilege leaked';
  END IF;
END $test$;
ROLLBACK;
