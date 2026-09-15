-- Run after document_boundary_repair_setup.sql on the exclusively owned Review DB.
\set ON_ERROR_STOP on
BEGIN;
DO $test$
DECLARE org uuid:='152b0000-0000-0000-0000-000000000001';
  owner uuid:='152a0000-0000-0000-0000-000000000001'; viewer uuid:='152a0000-0000-0000-0000-000000000002';
  suspended uuid:='152a0000-0000-0000-0000-000000000003'; foreign_actor uuid:='152a0000-0000-0000-0000-000000000004';
  source_m uuid:='152d0000-0000-0000-0000-000000000001'; target_m uuid:='152d0000-0000-0000-0000-000000000002';
  source_doc uuid:='152e0000-0000-0000-0000-000000000001'; moving_doc uuid:='152e0000-0000-0000-0000-000000000002';
  target_doc uuid:='152e0000-0000-0000-0000-000000000003'; outbound_doc uuid:='152e0000-0000-0000-0000-000000000004';
  source_item uuid; moving_item uuid; current_version uuid; asset uuid; rev bigint; created record;
  inactive_created record; inactive_m uuid:='152d0000-0000-0000-0000-000000000003';
  inactive_doc uuid:='152e0000-0000-0000-0000-000000000005';
  inactive_asset uuid:='152f0000-0000-0000-0000-000000000005';
  inactive_version uuid:='15200000-0000-0000-0000-000000000005';
  lower_source uuid:='00000000-0000-0000-0000-000000000001';
  lower_candidate uuid:='00000000-0000-0000-0000-000000000002';
  candidate_to_clone uuid; adversarial_item uuid; trash_op uuid; restore_code text;
  preview jsonb; move_fingerprint text; result record; keep_key uuid:=gen_random_uuid(); move_key uuid:=gen_random_uuid();
  activity_before bigint; before_count bigint; trash_code text; resolve_code text;
BEGIN
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',owner::text,true);
  IF EXISTS(SELECT 1 FROM public.review_items WHERE type='placement_conflict' AND document_id IN(source_doc,moving_doc,outbound_doc,target_doc))
    THEN RAISE EXCEPTION 'Provisional printed candidate alone created placement Review'; END IF;
  SELECT revision INTO rev FROM public.matters WHERE id=target_m;
  SELECT * INTO created FROM public.activate_matter_identifier(target_m,rev,'order_reference','self_identifier',
    'GST Tribunal','GST/555/2026','GST/555/2026',target_doc,
    '15200000-0000-0000-0000-000000000003',1,'GST/555/2026','[]',
    'Human verification of exact target source',gen_random_uuid());
  IF created.code<>'ok' THEN RAISE EXCEPTION 'Exact target Matter key was not verified: %',created.code; END IF;
  -- A lower-ordered, source-grounded candidate points to a human-verified
  -- identifier whose Matter is then governed-Trashed. It must not displace
  -- the one active verified target from the producer's selected source.
  BEGIN
    INSERT INTO public.matters(id,org_id,client_id,title,matter_code)
      VALUES(inactive_m,org,'152c0000-0000-0000-0000-000000000001','Inactive target','REF-152-C');
    INSERT INTO public.documents(id,org_id,matter_id,storage_path,display_title,document_class,origin_kind,
      content_availability,status,created_by)
      VALUES(inactive_doc,org,inactive_m,'fixture/inactive-reference.pdf','Inactive source','proceeding','upload',
        'source_attached','placed',owner);
    INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,
      validated_at,validated_page_count,created_by)
      VALUES(inactive_asset,org,'documents','orgs/'||org||'/assets/'||inactive_asset||'/original.pdf',
        lpad('5',64,'5'),100,'application/pdf','available',now(),1,owner);
    INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,
      validation_state,state,validated_at,promoted_at,created_by)
      VALUES(inactive_version,org,inactive_doc,inactive_asset,1,'inactive-reference.pdf',1,
        'valid','current',now(),now(),owner);
    UPDATE public.documents SET current_version_id=inactive_version WHERE id=inactive_doc;
    SELECT revision INTO rev FROM public.matters WHERE id=inactive_m;
    SELECT * INTO inactive_created FROM public.activate_matter_identifier(inactive_m,rev,'order_reference',
      'self_identifier','GST Tribunal','GST/556/2026','GST/556/2026',inactive_doc,inactive_version,
      1,'GST/556/2026','[]','Human-verified exact inactive source',gen_random_uuid());
    IF inactive_created.code<>'ok' THEN RAISE EXCEPTION 'Inactive target key verification failed: %',inactive_created.code; END IF;
    IF (SELECT count(*) FROM public.review_items WHERE document_id=moving_doc AND type='placement_conflict'
      AND status='needs_review')<>0
      THEN RAISE EXCEPTION 'Two active verified destinations did not close single-target Review'; END IF;
    SELECT c.id INTO candidate_to_clone FROM public.document_field_candidates c
      WHERE c.document_id=moving_doc AND c.normalized_value->>'normalized_value'='GST/556/2026' LIMIT 1;
    IF candidate_to_clone IS NULL THEN RAISE EXCEPTION 'Adversarial printed source was not materialized'; END IF;
    INSERT INTO public.source_field_candidates(id,org_id,source_analysis_run_id,asset_id,semantic_candidate_key,
      field_path,value_type,normalized_value,page_number,evidence_page_count,quotation,evidence_regions,
      confidence,validation_state,validation_error_codes,verified_source_anchor)
      SELECT lower_source,s.org_id,s.source_analysis_run_id,s.asset_id,'official_reference:inactive_lower',
        s.field_path,s.value_type,s.normalized_value,s.page_number,s.evidence_page_count,s.quotation,
        s.evidence_regions,s.confidence,s.validation_state,s.validation_error_codes,s.verified_source_anchor
      FROM public.source_field_candidates s JOIN public.document_field_candidates c
        ON c.source_field_candidate_id=s.id WHERE c.id=candidate_to_clone;
    INSERT INTO public.document_field_candidates(id,org_id,document_id,document_version_id,
      document_version_analysis_binding_id,source_field_candidate_id,semantic_candidate_key,field_path,
      value_type,normalized_value,page_number,evidence_page_count,quotation,evidence_regions,
      confidence,validation_state,validation_error_codes)
      SELECT lower_candidate,c.org_id,c.document_id,c.document_version_id,c.document_version_analysis_binding_id,
        lower_source,'official_reference:inactive_lower',c.field_path,c.value_type,c.normalized_value,
        c.page_number,c.evidence_page_count,c.quotation,c.evidence_regions,c.confidence,
        c.validation_state,c.validation_error_codes
      FROM public.document_field_candidates c WHERE c.id=candidate_to_clone;
    IF lower_candidate>candidate_to_clone THEN RAISE EXCEPTION 'Adversarial candidate did not sort first'; END IF;
    SELECT code,operation_id INTO trash_code,trash_op FROM public.trash_resource('matter',inactive_m,'fixture.inactive-target');
    IF trash_code<>'trashed' OR trash_op IS NULL THEN RAISE EXCEPTION 'Inactive target Trash failed: %',trash_code; END IF;
    -- No explicit producer call: the governed Matter availability trigger must
    -- create a new actionable item rather than mutate the closed history.
    SELECT item.id INTO adversarial_item FROM public.review_items item
      JOIN public.placement_conflict_sources source ON source.review_item_id=item.id
      WHERE item.document_id=moving_doc AND item.status='needs_review'
        AND source.target_matter_id=target_m AND source.source_candidate_id<>lower_candidate;
    IF adversarial_item IS NULL OR
      (SELECT count(*) FROM public.review_items WHERE document_id=moving_doc AND type='placement_conflict'
        AND status='needs_review')<>1 OR
      (SELECT count(*) FROM public.review_items WHERE document_id=moving_doc AND type='placement_conflict')<>2
      THEN RAISE EXCEPTION 'Lower inactive key suppressed or displaced active verified target: active item %, rows %, matters %, document %',
        adversarial_item,(SELECT coalesce(jsonb_agg(jsonb_build_object('item',item.id,'status',item.status,
          'reason',item.closure_reason,'target',source.target_matter_id,'candidate',source.source_candidate_id)),'[]'::jsonb)
          FROM public.review_items item LEFT JOIN public.placement_conflict_sources source ON source.review_item_id=item.id
          WHERE item.document_id=moving_doc AND item.type='placement_conflict'),
        (SELECT jsonb_agg(jsonb_build_object('matter',m.id,'state',m.record_state,'deleted',m.deleted_at,
          'keys',(SELECT jsonb_agg(jsonb_build_object('key',mi.normalized_value,'state',mi.lifecycle_state))
            FROM public.matter_identifiers mi WHERE mi.matter_id=m.id))) FROM public.matters m WHERE m.id IN(target_m,inactive_m)),
        (SELECT jsonb_build_object('matter',d.matter_id,'version',d.current_version_id,'content',d.content_availability)
          FROM public.documents d WHERE d.id=moving_doc); END IF;
    PERFORM public.reconcile_placed_document_identity_conflict(moving_doc);
    IF (SELECT count(*) FROM public.review_items WHERE document_id=moving_doc AND type='placement_conflict')<>2
      THEN RAISE EXCEPTION 'Repeated producer invocation duplicated reemerged Review'; END IF;
    SELECT code INTO restore_code FROM public.restore_trash_operation(trash_op,'fixture.inactive-target.restore');
    IF restore_code<>'restored' OR (SELECT status FROM public.review_items WHERE id=adversarial_item)<>'closed'
      THEN RAISE EXCEPTION 'Governed Matter Restore did not close now-ambiguous Review: %',restore_code; END IF;
    SELECT code INTO trash_code FROM public.trash_resource('matter',inactive_m,'fixture.inactive-target.again');
    IF trash_code<>'trashed' OR
      (SELECT count(*) FROM public.review_items WHERE document_id=moving_doc AND type='placement_conflict')<>3 OR
      (SELECT count(*) FROM public.review_items WHERE document_id=moving_doc AND type='placement_conflict'
        AND status='needs_review')<>1
      THEN RAISE EXCEPTION 'Second governed Trash did not reemerge exactly one new active-target Review: %',trash_code; END IF;
    RAISE EXCEPTION USING ERRCODE='Z0167',MESSAGE='rollback inactive-target selection fault';
  EXCEPTION WHEN SQLSTATE 'Z0167' THEN NULL; END;
  SELECT id INTO source_item FROM public.review_items WHERE type='placement_conflict' AND document_id=source_doc AND status='needs_review';
  SELECT id INTO moving_item FROM public.review_items WHERE type='placement_conflict' AND document_id=moving_doc AND status='needs_review';
  IF source_item IS NULL OR moving_item IS NULL OR (SELECT count(*) FROM public.review_items WHERE type='placement_conflict' AND status='needs_review')<>2
    OR EXISTS(SELECT 1 FROM public.review_items WHERE type='placement_conflict' AND document_id IN(target_doc,outbound_doc))
    OR (SELECT matter_id FROM public.documents WHERE id=source_doc)<>source_m
    OR (SELECT matter_id FROM public.documents WHERE id=moving_doc)<>source_m
    THEN RAISE EXCEPTION 'Exact mismatch did not create one Review per affected current filing without moving PDFs'; END IF;
  SELECT current_version_id INTO current_version FROM public.documents WHERE id=moving_doc;
  SELECT asset_id INTO asset FROM public.document_versions WHERE id=current_version;
  IF public.read_review_detail(moving_item)#>>'{evidence,0,page_number}'<>'1'
    OR public.read_review_detail(moving_item)->'allowed_actions'<>'["keep_placement","move_placement"]'::jsonb
    OR public.read_review_detail(moving_item)->>'target_matter_id'<>target_m::text
    OR (SELECT total_count FROM public.read_review_queue('needs_review','placement_conflict'))<>2
    THEN RAISE EXCEPTION 'Typed Review reader lost exact source or authority'; END IF;
  PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
  IF public.read_review_detail(moving_item)->'allowed_actions'<>'[]'::jsonb
    OR (SELECT code FROM public.resolve_placement_conflict(moving_item,1,'keep',NULL,'Viewer denied',gen_random_uuid()))<>'forbidden'
    THEN RAISE EXCEPTION 'Viewer resolved placement conflict'; END IF;
  PERFORM set_config('request.jwt.claim.sub',suspended::text,true);
  IF public.read_review_detail(moving_item) IS NOT NULL
    OR (SELECT code FROM public.resolve_placement_conflict(moving_item,1,'keep',NULL,'Suspended denied',gen_random_uuid()))<>'forbidden'
    THEN RAISE EXCEPTION 'Inactive member resolved placement conflict'; END IF;
  PERFORM set_config('request.jwt.claim.sub',foreign_actor::text,true);
  IF public.read_review_detail(moving_item) IS NOT NULL
    OR (SELECT code FROM public.resolve_placement_conflict(moving_item,1,'keep',NULL,'Foreign denied',gen_random_uuid())) NOT IN ('unavailable','forbidden')
    THEN RAISE EXCEPTION 'Foreign tenant accessed placement conflict'; END IF;
  PERFORM set_config('request.jwt.claim.sub',owner::text,true);
  -- Each governed lifecycle fault is scoped to a savepoint and rolled back;
  -- the decisive Keep/Move checks below still see the original exact source.
  BEGIN
    UPDATE public.documents SET current_version_id=NULL WHERE id=source_doc;
    IF (SELECT closure_reason FROM public.review_items WHERE id=source_item)<>'source_replaced'
      OR (SELECT code FROM public.resolve_placement_conflict(source_item,1,'keep',NULL,'Old source denied',gen_random_uuid()))<>'stale'
      THEN RAISE EXCEPTION 'Replaced source remained actionable'; END IF;
    RAISE EXCEPTION USING ERRCODE='Z0167',MESSAGE='rollback source replacement fault';
  EXCEPTION WHEN SQLSTATE 'Z0167' THEN NULL; END;
  BEGIN
    preview:=public.preview_document_boundary_repair(moving_doc,target_m,'move');
    IF preview->>'code'<>'ok' OR jsonb_array_length(preview->'blockers')<>0
      THEN RAISE EXCEPTION 'Independent governed Move precondition failed: %',preview; END IF;
    IF public.execute_document_boundary_repair(moving_doc,target_m,'move',preview->>'fingerprint',
      'Independent authorised correction of current filing',gen_random_uuid())->>'code'<>'ok'
      OR (SELECT closure_reason FROM public.review_items WHERE id=moving_item)<>'source_replaced'
      OR (SELECT code FROM public.resolve_placement_conflict(moving_item,1,'keep',NULL,
        'Old filing no longer current',gen_random_uuid()))<>'stale'
      THEN RAISE EXCEPTION 'Independent Move retained stale placement Review'; END IF;
    RAISE EXCEPTION USING ERRCODE='Z0167',MESSAGE='rollback independent Move fault';
  EXCEPTION WHEN SQLSTATE 'Z0167' THEN NULL; END;
  BEGIN
    SELECT revision INTO rev FROM public.matters WHERE id=target_m;
    SELECT * INTO created FROM public.revoke_matter_identifier(created.identifier_id,1,rev,
      'Verified key is no longer authoritative',gen_random_uuid());
    IF created.code<>'ok' OR (SELECT closure_reason FROM public.review_items WHERE id=moving_item)<>'source_replaced'
      OR (SELECT code FROM public.resolve_placement_conflict(moving_item,1,'move',repeat('a',64),'Revoked key denied',gen_random_uuid()))<>'stale'
      THEN RAISE EXCEPTION 'Revoked verified key remained actionable'; END IF;
    RAISE EXCEPTION USING ERRCODE='Z0167',MESSAGE='rollback verified-key revocation fault';
  EXCEPTION WHEN SQLSTATE 'Z0167' THEN NULL; END;
  BEGIN
    SELECT code INTO trash_code FROM public.trash_resource('matter',target_m,'placement-conflict.fixture.target-trash');
    SELECT code INTO resolve_code FROM public.resolve_placement_conflict(moving_item,1,'move',repeat('a',64),'Trashed target denied',gen_random_uuid());
    IF trash_code<>'trashed' OR resolve_code NOT IN ('stale','blocked','stale_preview')
      OR public.read_review_detail(moving_item)->>'conflict_current'<>'false'
      THEN RAISE EXCEPTION 'Trashed target remained a Move destination: trash %, resolver %',trash_code,resolve_code; END IF;
    RAISE EXCEPTION USING ERRCODE='Z0167',MESSAGE='rollback target Trash fault';
  EXCEPTION WHEN SQLSTATE 'Z0167' THEN NULL; END;
  IF (SELECT code FROM public.resolve_placement_conflict(moving_item,2,'keep',NULL,'Wrong revision',gen_random_uuid()))<>'stale'
    THEN RAISE EXCEPTION 'Stale Review revision applied'; END IF;
  activity_before:=(SELECT count(*) FROM public.activity_events WHERE org_id=org AND event_type='review.placement_conflict_decided');
  SELECT * INTO result FROM public.resolve_placement_conflict(source_item,1,'keep',NULL,'Printed key refers to a different procedural chain',keep_key);
  IF result.code<>'ok' OR result.replayed OR (SELECT matter_id FROM public.documents WHERE id=source_doc)<>source_m
    OR (SELECT closure_reason FROM public.review_items WHERE id=source_item)<>'decision_recorded'
    THEN RAISE EXCEPTION 'Keep did not preserve current exact filing'; END IF;
  SELECT * INTO result FROM public.resolve_placement_conflict(source_item,1,'keep',NULL,'Printed key refers to a different procedural chain',keep_key);
  IF result.code<>'ok' OR NOT result.replayed
    OR (SELECT code FROM public.resolve_placement_conflict(source_item,1,'move',repeat('a',64),'Changed request',keep_key))<>'idempotency_conflict'
    THEN RAISE EXCEPTION 'Keep replay was not actor/request bound'; END IF;
  PERFORM public.reconcile_placed_document_identity_conflict(source_doc);
  IF (SELECT count(*) FROM public.review_items WHERE type='placement_conflict' AND document_id=source_doc)<>1
    THEN RAISE EXCEPTION 'Unchanged rejected evidence recreated Review'; END IF;
  preview:=public.preview_placement_conflict_move(moving_item);
  IF preview->>'code'<>'ok' OR jsonb_array_length(preview->'blockers')<>0
    THEN RAISE EXCEPTION 'Authoritative Move preview unexpectedly blocked: %',preview; END IF;
  IF (SELECT code FROM public.resolve_placement_conflict(moving_item,1,'move',repeat('a',64),'Stale preview',gen_random_uuid()))<>'stale_preview'
    THEN RAISE EXCEPTION 'Stale impact preview applied Move'; END IF;
  SELECT * INTO result FROM public.resolve_placement_conflict(moving_item,1,'move',preview->>'fingerprint',
    'Human checked exact verified target and current impact',move_key);
  move_fingerprint:=preview->>'fingerprint';
  IF result.code<>'ok' OR result.replayed OR (SELECT matter_id FROM public.documents WHERE id=moving_doc)<>target_m
    OR (SELECT current_version_id FROM public.documents WHERE id=moving_doc)<>current_version
    OR (SELECT asset_id FROM public.document_versions WHERE id=current_version)<>asset
    OR public.read_review_detail(moving_item)->>'current_matter_id'<>target_m::text
    OR public.read_review_detail(moving_item)->>'current_matter_title'<>'Reference B'
    OR (SELECT closure_reason FROM public.review_items WHERE id=moving_item)<>'decision_recorded'
    OR (SELECT count(*) FROM public.placement_conflict_decisions WHERE review_item_id=moving_item)<>1
    THEN RAISE EXCEPTION 'Typed transactional Move lost logical document/version/asset or Review closure'; END IF;
  BEGIN
    -- The first governed Move queues reprocessing; finish only this synthetic
    -- fixture attempt before testing a separate authorised later Move.
    UPDATE public.document_processing_runs SET state='completed',stage='ready',
      started_at=coalesce(started_at,now()),completed_at=now(),
      lease_token=NULL,lease_expires_at=NULL WHERE org_id=org AND document_id=moving_doc
        AND state IN ('queued','running');
    preview:=public.preview_document_boundary_repair(moving_doc,source_m,'move');
    IF preview->>'code'<>'ok' OR jsonb_array_length(preview->'blockers')<>0
      THEN RAISE EXCEPTION 'Later governed Move precondition failed: %',preview; END IF;
    IF public.execute_document_boundary_repair(moving_doc,source_m,'move',preview->>'fingerprint',
      'Later authorised Matter correction',gen_random_uuid())->>'code'<>'ok'
      OR public.read_review_detail(moving_item)->>'current_matter_id'<>source_m::text
      OR public.read_review_detail(moving_item)->>'target_matter_id'<>target_m::text
      OR (SELECT closure_reason FROM public.review_items WHERE id=moving_item)<>'decision_recorded'
      THEN RAISE EXCEPTION 'Closed Move falsely retained its recorded destination as live current filing'; END IF;
    RAISE EXCEPTION USING ERRCODE='Z0167',MESSAGE='rollback later governed Move';
  EXCEPTION WHEN SQLSTATE 'Z0167' THEN NULL; END;
  SELECT * INTO result FROM public.resolve_placement_conflict(moving_item,1,'move',move_fingerprint,
    'Human checked exact verified target and current impact',move_key);
  SELECT code INTO resolve_code FROM public.resolve_placement_conflict(moving_item,1,'keep',NULL,'Racing Keep',gen_random_uuid());
  IF result.code<>'ok' OR NOT result.replayed OR resolve_code<>'stale'
    OR (SELECT count(*) FROM public.activity_events WHERE org_id=org AND event_type='review.placement_conflict_decided')<>activity_before+2
    THEN RAISE EXCEPTION 'Racing or replayed decision duplicated Review Activity: replay %, replayed %, race %, before %, after %',
      result.code,result.replayed,resolve_code,activity_before,
      (SELECT count(*) FROM public.activity_events WHERE org_id=org AND event_type='review.placement_conflict_decided'); END IF;
END $test$;
SET LOCAL ROLE authenticated;
DO $rls$
BEGIN
  BEGIN PERFORM 1 FROM public.placement_conflict_sources; RAISE EXCEPTION 'Private snapshots directly readable';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM 1 FROM public.placement_conflict_decisions; RAISE EXCEPTION 'Private decisions directly readable';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $rls$;
ROLLBACK;
