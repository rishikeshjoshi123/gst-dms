-- Run after document_boundary_repair_setup.sql on disposable dms-review-153.
\set ON_ERROR_STOP on
BEGIN;
DO $test$
DECLARE org uuid:='152b0000-0000-0000-0000-000000000001';
  owner uuid:='152a0000-0000-0000-0000-000000000001'; viewer uuid:='152a0000-0000-0000-0000-000000000002';
  suspended uuid:='152a0000-0000-0000-0000-000000000003'; foreign_actor uuid:='152a0000-0000-0000-0000-000000000004';
  source_m uuid:='152d0000-0000-0000-0000-000000000001'; target_b uuid:='152d0000-0000-0000-0000-000000000002';
  target_c uuid:='169d0000-0000-0000-0000-000000000003'; target_c_doc uuid:='169e0000-0000-0000-0000-000000000003';
  target_c_asset uuid:='169f0000-0000-0000-0000-000000000003'; target_c_version uuid:='16900000-0000-0000-0000-000000000003';
  source_doc uuid:='152e0000-0000-0000-0000-000000000002'; target_b_doc uuid:='152e0000-0000-0000-0000-000000000003';
  target_b_version uuid:='15200000-0000-0000-0000-000000000003';
  rev bigint; created record; item_id uuid; single_id uuid; detail jsonb; preview jsonb; result record;
  impact text; keep_key uuid:=gen_random_uuid(); move_key uuid:=gen_random_uuid(); activity_before bigint; trash_code text;
BEGIN
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',owner::text,true);
  SELECT revision INTO rev FROM public.matters WHERE id=target_b;
  SELECT * INTO created FROM public.activate_matter_identifier(target_b,rev,'order_reference','self_identifier',
    'GST Tribunal','GST/555/2026','GST/555/2026',target_b_doc,target_b_version,1,'GST/555/2026','[]',
    'Human-verified exact target B source',gen_random_uuid());
  IF created.code<>'ok' THEN RAISE EXCEPTION 'Target B key failed: %',created.code; END IF;
  SELECT id INTO single_id FROM public.review_items WHERE document_id=source_doc AND type='placement_conflict' AND status='needs_review';
  IF single_id IS NULL THEN RAISE EXCEPTION 'One-target prerequisite Review absent'; END IF;
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code)
    VALUES(target_c,org,'152c0000-0000-0000-0000-000000000001','Reference C','REF-169-C');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,display_title,document_class,origin_kind,
    content_availability,status,created_by)
    VALUES(target_c_doc,org,target_c,'fixture/reference-c.pdf','Reference C key source','proceeding','upload','source_attached','placed',owner);
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,
    validated_at,validated_page_count,created_by)
    VALUES(target_c_asset,org,'documents','orgs/'||org||'/assets/'||target_c_asset||'/original.pdf',
      repeat('9',64),100,'application/pdf','available',now(),1,owner);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,
    validation_state,state,validated_at,promoted_at,created_by)
    VALUES(target_c_version,org,target_c_doc,target_c_asset,1,'reference-c.pdf',1,'valid','current',now(),now(),owner);
  UPDATE public.documents SET current_version_id=target_c_version WHERE id=target_c_doc;
  SELECT revision INTO rev FROM public.matters WHERE id=target_c;
  SELECT * INTO created FROM public.activate_matter_identifier(target_c,rev,'order_reference','self_identifier',
    'GST Tribunal','GST/556/2026','GST/556/2026',target_c_doc,target_c_version,1,'GST/556/2026','[]',
    'Human-verified exact target C source',gen_random_uuid());
  IF created.code<>'ok' THEN RAISE EXCEPTION 'Target C key failed: %',created.code; END IF;
  IF (SELECT status FROM public.review_items WHERE id=single_id)<>'closed'
    OR (SELECT closure_reason FROM public.review_items WHERE id=single_id)<>'source_replaced'
    OR (SELECT count(*) FROM public.review_items WHERE document_id=source_doc AND type='multi_placement_conflict' AND status='needs_review')<>1
    THEN RAISE EXCEPTION 'One-to-many transition failed'; END IF;
  SELECT id INTO item_id FROM public.review_items WHERE document_id=source_doc AND type='multi_placement_conflict' AND status='needs_review';
  PERFORM public.reconcile_placed_document_identity_conflict(source_doc);
  IF (SELECT count(*) FROM public.review_items WHERE document_id=source_doc AND type='multi_placement_conflict')<>1
    OR (SELECT count(DISTINCT target_matter_id) FROM public.multi_placement_conflict_sources WHERE review_item_id=item_id)<>2
    THEN RAISE EXCEPTION 'Repeat producer duplicated or omitted distinct targets'; END IF;
  detail:=public.read_review_detail(item_id);
  IF detail->>'type'<>'multi_placement_conflict' OR jsonb_array_length(detail->'evidence')<>2
    OR detail->>'old_matter_id'<>source_m::text OR detail->>'current_matter_id'<>source_m::text
    OR detail->>'conflict_current'<>'true'
    OR NOT EXISTS(SELECT 1 FROM public.multi_placement_conflict_sources WHERE review_item_id=item_id AND target_matter_id=target_b
      AND source_quote='GST/555/2026' AND source_page_number=1)
    OR NOT EXISTS(SELECT 1 FROM public.multi_placement_conflict_sources WHERE review_item_id=item_id AND target_matter_id=target_c
      AND source_quote='GST/556/2026' AND source_page_number=1)
    THEN RAISE EXCEPTION 'Exact per-target printed/key detail failed: %',detail; END IF;
  preview:=public.preview_multi_placement_conflict_move(item_id,target_c);
  IF preview->>'code'<>'ok' OR preview->>'fingerprint' IS NULL THEN RAISE EXCEPTION 'Target C impact preview failed: %',preview; END IF;
  impact:=preview->>'fingerprint';
  PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
  IF public.read_review_detail(item_id)->'allowed_actions'<>'[]'::jsonb
    OR public.preview_multi_placement_conflict_move(item_id,target_c)->>'code'<>'forbidden'
    THEN RAISE EXCEPTION 'Viewer received multi-target authority'; END IF;
  SELECT * INTO result FROM public.resolve_multi_placement_conflict(item_id,1,'keep',NULL,NULL,'Viewer denied',gen_random_uuid());
  IF result.code<>'forbidden' THEN RAISE EXCEPTION 'Viewer resolved: %',result.code; END IF;
  PERFORM set_config('request.jwt.claim.sub',suspended::text,true);
  IF public.read_review_detail(item_id) IS NOT NULL OR public.preview_multi_placement_conflict_move(item_id,target_c)->>'code'<>'forbidden'
    THEN RAISE EXCEPTION 'Suspended actor saw packet'; END IF;
  PERFORM set_config('request.jwt.claim.sub',foreign_actor::text,true);
  IF public.read_review_detail(item_id) IS NOT NULL OR public.preview_multi_placement_conflict_move(item_id,target_c)->>'code'<>'forbidden'
    THEN RAISE EXCEPTION 'Foreign actor saw packet'; END IF;
  PERFORM set_config('request.jwt.claim.sub',owner::text,true);
  SELECT count(*) INTO activity_before FROM public.activity_events WHERE org_id=org;
  SELECT * INTO result FROM public.resolve_multi_placement_conflict(item_id,(detail->>'revision')::bigint+1,
    'keep',NULL,NULL,'Wrong Review revision denied',gen_random_uuid());
  IF result.code<>'stale' THEN RAISE EXCEPTION 'Review revision mismatch applied: %',result.code; END IF;
  BEGIN
    UPDATE public.documents SET current_version_id=NULL WHERE id=source_doc;
    SELECT * INTO result FROM public.resolve_multi_placement_conflict(item_id,(detail->>'revision')::bigint,
      'keep',NULL,NULL,'Replaced source version denied',gen_random_uuid());
    IF result.code<>'stale' OR (SELECT status FROM public.review_items WHERE id=item_id)<>'closed'
      THEN RAISE EXCEPTION 'Current source-version replacement remained actionable: %',result.code; END IF;
    RAISE EXCEPTION USING ERRCODE='Z0169',MESSAGE='rollback source-version race';
  EXCEPTION WHEN SQLSTATE 'Z0169' THEN NULL; END;
  BEGIN
    SELECT revision INTO rev FROM public.matters WHERE id=target_c;
    SELECT * INTO created FROM public.revoke_matter_identifier(
      (SELECT target_identifier_id FROM public.multi_placement_conflict_sources
        WHERE review_item_id=item_id AND target_matter_id=target_c),1,rev,
      'Verified key withdrawn before decision',gen_random_uuid());
    SELECT * INTO result FROM public.resolve_multi_placement_conflict(item_id,(detail->>'revision')::bigint,
      'move',target_c,impact,'Withdrawn target must fail',gen_random_uuid());
    IF created.code<>'ok' OR (SELECT status FROM public.review_items WHERE id=item_id)<>'closed'
      OR result.code<>'stale' OR public.read_review_detail(item_id)->>'conflict_current'<>'false'
      THEN RAISE EXCEPTION 'Verified-key revision race remained actionable: key %, decision %',created.code,result.code; END IF;
    RAISE EXCEPTION USING ERRCODE='Z0169',MESSAGE='rollback key-revision race';
  EXCEPTION WHEN SQLSTATE 'Z0169' THEN NULL; END;
  BEGIN
    SELECT code INTO trash_code FROM public.trash_resource('matter',target_c,'multi-placement.fixture.target-trash');
    SELECT * INTO result FROM public.resolve_multi_placement_conflict(item_id,(detail->>'revision')::bigint,
      'move',target_c,impact,'Trashed target must fail',gen_random_uuid());
    IF trash_code<>'trashed' OR (SELECT status FROM public.review_items WHERE id=item_id)<>'closed'
      OR result.code<>'stale' OR public.read_review_detail(item_id)->>'conflict_current'<>'false'
      THEN RAISE EXCEPTION 'Target lifecycle race remained actionable: Trash %, decision %',trash_code,result.code; END IF;
    RAISE EXCEPTION USING ERRCODE='Z0169',MESSAGE='rollback Matter Trash race';
  EXCEPTION WHEN SQLSTATE 'Z0169' THEN NULL; END;
  BEGIN
    SELECT * INTO result FROM public.resolve_multi_placement_conflict(item_id,(detail->>'revision')::bigint,
      'keep',NULL,NULL,'These are separately actionable references',keep_key);
    IF result.code<>'ok' OR (SELECT matter_id FROM public.documents WHERE id=source_doc)<>source_m
      THEN RAISE EXCEPTION 'Keep failed: %',result.code; END IF;
    SELECT * INTO result FROM public.resolve_multi_placement_conflict(item_id,(detail->>'revision')::bigint,
      'keep',NULL,NULL,'These are separately actionable references',keep_key);
    IF result.code<>'ok' OR NOT result.replayed THEN RAISE EXCEPTION 'Keep replay failed: %',result.code; END IF;
    PERFORM public.reconcile_placed_document_identity_conflict(source_doc);
    IF (SELECT count(*) FROM public.review_items WHERE document_id=source_doc AND type='multi_placement_conflict')<>1
      THEN RAISE EXCEPTION 'Unchanged Keep generated new Review'; END IF;
    RAISE EXCEPTION USING ERRCODE='Z0169',MESSAGE='rollback Keep branch for Move branch';
  EXCEPTION WHEN SQLSTATE 'Z0169' THEN NULL; END;
  SELECT * INTO result FROM public.resolve_multi_placement_conflict(item_id,(detail->>'revision')::bigint,
    'move',target_c,repeat('0',64),'Choose printed GST/556 reference',move_key);
  IF result.code<>'stale_preview' OR (SELECT matter_id FROM public.documents WHERE id=source_doc)<>source_m
    THEN RAISE EXCEPTION 'Wrong impact did not fail closed: %',result.code; END IF;
  SELECT * INTO result FROM public.resolve_multi_placement_conflict(item_id,(detail->>'revision')::bigint,
    'move',target_c,impact,'Choose printed GST/556 reference',move_key);
  IF result.code<>'ok' OR result.replayed OR (SELECT matter_id FROM public.documents WHERE id=source_doc)<>target_c
    OR (SELECT status FROM public.review_items WHERE id=item_id)<>'closed'
    OR (SELECT count(*) FROM public.multi_placement_conflict_decisions WHERE review_item_id=item_id)<>1
    THEN RAISE EXCEPTION 'Atomic chosen-target Move failed: %',result.code; END IF;
  SELECT * INTO result FROM public.resolve_multi_placement_conflict(item_id,(detail->>'revision')::bigint,
    'move',target_c,impact,'Choose printed GST/556 reference',move_key);
  IF result.code<>'ok' OR NOT result.replayed THEN RAISE EXCEPTION 'Move replay failed: %',result.code; END IF;
  IF (SELECT count(*) FROM public.activity_events WHERE org_id=org)<>activity_before+2
    OR (SELECT count(*) FROM public.activity_events WHERE org_id=org AND subject_id=source_doc
      AND event_type='review.multi_placement_conflict_decided')<>1
    OR (SELECT count(*) FROM public.activity_events WHERE org_id=org AND subject_id=source_doc
      AND event_type='document.boundary_repaired' AND metadata->>'mode'='move')<>1
    OR (SELECT current_version_id FROM public.documents WHERE id=source_doc)<>'15200000-0000-0000-0000-000000000002'::uuid
    OR (SELECT asset_id FROM public.document_versions WHERE id='15200000-0000-0000-0000-000000000002')<>'152f0000-0000-0000-0000-000000000002'::uuid
    THEN RAISE EXCEPTION 'Move/replay did not retain exact version and exactly one event of each kind'; END IF;
  SELECT * INTO result FROM public.resolve_multi_placement_conflict(item_id,(detail->>'revision')::bigint,
    'move',target_b,impact,'Choose printed GST/555 reference',gen_random_uuid());
  IF result.code<>'stale' THEN RAISE EXCEPTION 'Closed item permitted second target: %',result.code; END IF;
END $test$;
ROLLBACK;
