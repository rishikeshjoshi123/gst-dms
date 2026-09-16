-- D09-T05 rollback-only acceptance for governed document aliases and exact,
-- bidirectional, non-procedural reference resolution.
\set ON_ERROR_STOP on
BEGIN;

DO $fixture$
DECLARE
  actor uuid:='151a0000-0000-0000-0000-000000000001'; viewer uuid:='151a0000-0000-0000-0000-000000000002'; suspended uuid:='151a0000-0000-0000-0000-000000000003'; foreign_actor uuid:='151a0000-0000-0000-0000-000000000004'; ambiguous_actor uuid:='151a0000-0000-0000-0000-000000000005'; admin_actor uuid:='151a0000-0000-0000-0000-000000000006'; associate_actor uuid:='151a0000-0000-0000-0000-000000000007';
  org uuid:='151b0000-0000-0000-0000-000000000001'; foreign_org uuid:='151b0000-0000-0000-0000-000000000002'; client uuid:='151c0000-0000-0000-0000-000000000001';
  matter_a uuid:='151d0000-0000-0000-0000-000000000001'; matter_b uuid:='151d0000-0000-0000-0000-000000000002';
  docs uuid[]:=ARRAY['151e0000-0000-0000-0000-000000000001','151e0000-0000-0000-0000-000000000002','151e0000-0000-0000-0000-000000000003','151e0000-0000-0000-0000-000000000004']::uuid[];
  assets uuid[]:=ARRAY['151f0000-0000-0000-0000-000000000001','151f0000-0000-0000-0000-000000000002','151f0000-0000-0000-0000-000000000003','151f0000-0000-0000-0000-000000000004']::uuid[];
  versions uuid[]:=ARRAY['15100000-0000-0000-0000-000000000001','15100000-0000-0000-0000-000000000002','15100000-0000-0000-0000-000000000003','15100000-0000-0000-0000-000000000004']::uuid[];
  processes uuid[]:=ARRAY['15110000-0000-0000-0000-000000000001','15110000-0000-0000-0000-000000000002','15110000-0000-0000-0000-000000000003','15110000-0000-0000-0000-000000000004']::uuid[];
  process_leases uuid[]:=ARRAY['15120000-0000-0000-0000-000000000001','15120000-0000-0000-0000-000000000002','15120000-0000-0000-0000-000000000003','15120000-0000-0000-0000-000000000004']::uuid[];
  runs uuid[]:=ARRAY['15130000-0000-0000-0000-000000000001','15130000-0000-0000-0000-000000000002','15130000-0000-0000-0000-000000000003','15130000-0000-0000-0000-000000000004']::uuid[];
  run_leases uuid[]:=ARRAY['15140000-0000-0000-0000-000000000001','15140000-0000-0000-0000-000000000002','15140000-0000-0000-0000-000000000003','15140000-0000-0000-0000-000000000004']::uuid[];
  catalogue text:='gst-legal-material-observation-catalogue-v3'; normalizer text:='typed-material-observation-normalizer-v3';
  ref jsonb; candidates jsonb; finished record; i integer; page_text text; source_candidate uuid; target_a_candidate uuid; target_b_candidate uuid;
  activated record; target_a_identifier uuid; target_b_identifier uuid; source_identifier uuid; corrected_identifier uuid; correction_candidate uuid; outbound_candidate uuid; mention_one uuid; mention_two uuid;
  matter_identifier uuid; v_revision bigint; rejected boolean; links_before bigint; relationships_before bigint; outbox_before bigint; effective_before bigint; decisions_before bigint; activity_before bigint; identifiers_before bigint; query_plan json;
  purged_identifier uuid; trashed record; purge_impact record; purge_queue record; purge_job record; purge_step record; storage_step record;
  duplicate_item uuid; duplicate_revision bigint; duplicate_resolution record; third_identifier uuid;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
    ('00000000-0000-0000-0000-000000000000',actor,'authenticated','authenticated','reference-owner@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',viewer,'authenticated','authenticated','reference-viewer@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',suspended,'authenticated','authenticated','reference-suspended@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',foreign_actor,'authenticated','authenticated','reference-foreign@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',ambiguous_actor,'authenticated','authenticated','reference-ambiguous@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',admin_actor,'authenticated','authenticated','reference-admin@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',associate_actor,'authenticated','authenticated','reference-associate@example.test','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES(org,'Reference fixture',actor),(foreign_org,'Foreign reference fixture',foreign_actor);
  INSERT INTO public.org_members(org_id,user_id,role) VALUES(org,viewer,'viewer'),(org,suspended,'associate'),(org,admin_actor,'admin'),(org,associate_actor,'associate');
  UPDATE public.organisation_memberships SET state='suspended',suspended_at=now(),suspended_by=actor,suspension_reason='fixture' WHERE org_id=org AND user_id=suspended;
  DROP INDEX public.organisation_memberships_one_current_org_per_user;
  ALTER TABLE public.org_members DROP CONSTRAINT unique_user_id;
  INSERT INTO public.org_members(org_id,user_id,role) VALUES(org,ambiguous_actor,'associate'),(foreign_org,ambiguous_actor,'associate');
  INSERT INTO public.clients(id,org_id,name) VALUES(client,org,'Reference client');
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code) VALUES(matter_a,org,client,'Reference A','REF-151-A'),(matter_b,org,client,'Reference B','REF-151-B');
  FOR i IN 1..4 LOOP
    INSERT INTO public.documents(id,org_id,matter_id,storage_path,display_title,document_class,origin_kind,content_availability,status,created_by)
      VALUES(docs[i],org,CASE WHEN i=3 THEN matter_b ELSE matter_a END,'fixture/reference-'||i||'.pdf','Reference '||i,'proceeding','upload','source_attached','placed',actor);
    INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
      VALUES(assets[i],org,'documents','orgs/'||org||'/assets/'||assets[i]||'/original.pdf',lpad(i::text,64,i::text),100,'application/pdf','available',now(),1,actor);
    INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
      VALUES(versions[i],org,docs[i],assets[i],1,'reference-'||i||'.pdf',1,'valid','current',now(),now(),actor);
    UPDATE public.documents SET current_version_id=versions[i] WHERE id=docs[i];
    INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
      VALUES(processes[i],org,docs[i],versions[i],'full','fixture.reference.'||i,'running','extracting',now(),process_leases[i],now()+interval '10 minutes',now());
    INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at,attempt_count,lease_token,lease_expires_at,heartbeat_at)
      VALUES(runs[i],org,assets[i],'ai_extraction.'||processes[i],'ai_extraction.'||processes[i],'ai_extraction','running','running','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4',catalogue,normalizer,now(),1,run_leases[i],now()+interval '10 minutes',now());
    INSERT INTO public.source_analysis_attempts(org_id,source_analysis_run_id,attempt_number,state,retry_reason,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at)
      VALUES(org,runs[i],1,'running','initial','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4',catalogue,normalizer,now());
    page_text:=CASE WHEN i IN (1,4) THEN 'References GST/555/2026 in this proceeding.' WHEN i=2 THEN 'Order identifiers GST/555/2026 and GST/556/2026.' ELSE 'Order identifier GST/555/2026.' END;
    INSERT INTO public.document_page_text_artifacts(org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,content_fingerprint)
      VALUES(org,docs[i],versions[i],processes[i],runs[i],'ready',1,repeat(i::text,64));
    INSERT INTO public.document_page_text_pages(org_id,artifact_id,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages)
      SELECT org,id,1,page_text,'[]','[]',repeat(i::text,64),'native_pdf','native-pdf-quality-v1','{}','{}' FROM public.document_page_text_artifacts WHERE source_analysis_run_id=runs[i];

    ref:=jsonb_build_object('role',CASE WHEN i IN (1,4) THEN 'outbound_mention' ELSE 'self_identifier' END,'kind','order_reference','namespace','GST Tribunal','namespace_normalized','GST TRIBUNAL','raw','GST/555/2026','display','GST/555/2026','normalized_value','GST/555/2026','components',jsonb_build_object('kind','order_reference','segments',jsonb_build_array('GST','555','2026'),'prefix','GST','numericCore','555','year','2026'),'completeness','complete','match_eligible',true,'catalogue_version',catalogue,'normalizer_version',normalizer);
    candidates:=jsonb_build_array(jsonb_build_object('semantic_candidate_key','official_reference:'||lpad(i::text,32,i::text),'field_path','document.official_reference.'||(ref->>'role'),'value_type','structured','normalized_value',ref,'page_number',1,'quotation','GST/555/2026','evidence_regions',NULL,'confidence',0.99,'validation_state','provisional','validation_error_codes',NULL,'verified_source_anchor',jsonb_build_object('char_start',strpos(page_text,'GST/555/2026')-1,'char_end',strpos(page_text,'GST/555/2026')-1+char_length('GST/555/2026'),'token_start',NULL,'token_end',NULL,'table_cell',NULL)));
    IF i=1 THEN
      ref:=jsonb_set(ref,'{role}','"self_identifier"');
      candidates:=candidates||jsonb_build_array(jsonb_build_object('semantic_candidate_key','official_reference:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','field_path','document.official_reference.self_identifier','value_type','structured','normalized_value',ref,'page_number',1,'quotation','GST/555/2026','evidence_regions',NULL,'confidence',0.99,'validation_state','provisional','validation_error_codes',NULL,'verified_source_anchor',jsonb_build_object('char_start',11,'char_end',23,'token_start',NULL,'token_end',NULL,'table_cell',NULL)));
    END IF;
    IF i=2 THEN
      ref:=jsonb_set(jsonb_set(jsonb_set(ref,'{raw}','"GST/556/2026"'),'{display}','"GST/556/2026"'),'{normalized_value}','"GST/556/2026"');
      ref:=jsonb_set(ref,'{components}',jsonb_build_object('kind','order_reference','segments',jsonb_build_array('GST','556','2026'),'prefix','GST','numericCore','556','year','2026'));
      candidates:=candidates||jsonb_build_array(jsonb_build_object('semantic_candidate_key','official_reference:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','field_path','document.official_reference.self_identifier','value_type','structured','normalized_value',ref,'page_number',1,'quotation','GST/556/2026','evidence_regions',NULL,'confidence',0.99,'validation_state','provisional','validation_error_codes',NULL,'verified_source_anchor',jsonb_build_object('char_start',strpos(page_text,'GST/556/2026')-1,'char_end',strpos(page_text,'GST/556/2026')-1+char_length('GST/556/2026'),'token_start',NULL,'token_end',NULL,'table_cell',NULL)));
    END IF;
    SELECT * INTO finished FROM public.finish_document_processing_ai_extraction(processes[i],process_leases[i],runs[i],run_leases[i],'validated',1,1,1,candidates,false,jsonb_build_object('doc_type','OIO','reference_number','GST/555/2026','doc_date','2026-01-01','direction',NULL,'issued_by','GST Tribunal','financial_years','[]'::jsonb,'summary','Fixture','prompt_version','v4.0'));
    IF finished.code<>'validated' OR finished.binding_id IS NULL THEN RAISE EXCEPTION 'fenced v4 finisher failed for row %: %',i,finished.code; END IF;
  END LOOP;

  -- The server-read SHA fence prevents an alternate asset with the same bytes;
  -- the possible-duplicate path cannot turn that exact upload into a second item.
  BEGIN
    INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
      VALUES('151f0000-0000-0000-0000-000000000099',org,'documents','orgs/'||org||'/assets/151f0000-0000-0000-0000-000000000099/original.pdf',
        (SELECT sha256 FROM public.file_assets WHERE id=assets[1]),100,'application/pdf','available',now(),1,actor);
    RAISE EXCEPTION 'same-hash alternate asset bypassed exact upload fence';
  EXCEPTION WHEN unique_violation THEN
    IF (SELECT count(*) FROM public.file_assets WHERE org_id=org AND sha256=(SELECT sha256 FROM public.file_assets WHERE id=assets[1]))<>1
      OR EXISTS(SELECT 1 FROM public.review_items WHERE org_id=org AND type='possible_duplicate') THEN
      RAISE EXCEPTION 'same-hash duplicate was not fenced before Review'; END IF;
  END;

  SELECT id INTO mention_one FROM public.document_reference_mentions WHERE source_document_id=docs[1];
  IF mention_one IS NULL OR (SELECT outcome FROM public.current_document_reference_resolutions WHERE mention_id=mention_one)<>'unresolved' THEN RAISE EXCEPTION 'mention-first unresolved state was not durable'; END IF;
  SELECT id INTO correction_candidate FROM public.document_field_candidates WHERE document_id=docs[2] AND field_path='document.official_reference.self_identifier' AND normalized_value->>'normalized_value'='GST/556/2026';
  SELECT id INTO target_a_candidate FROM public.document_field_candidates WHERE document_id=docs[2] AND field_path='document.official_reference.self_identifier' AND normalized_value->>'normalized_value'='GST/555/2026';
  SELECT id INTO target_b_candidate FROM public.document_field_candidates WHERE document_id=docs[3] AND field_path='document.official_reference.self_identifier';

  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',actor,'iat',extract(epoch FROM now())::bigint)::text,true);

  -- The optional Matter binding is exact, active, and derived from the same
  -- source document evidence; the document command still accepts only a
  -- candidate identity rather than caller-reconstructed evidence.
  SELECT matter_row.revision INTO v_revision FROM public.matters matter_row WHERE id=matter_a;
  SELECT identifier_id INTO matter_identifier FROM public.activate_matter_identifier(matter_a,v_revision,'order_reference','self_identifier','GST Tribunal','GST/555/2026','GST/555/2026',docs[2],versions[2],1,'GST/555/2026',NULL,'fixture binding','15150000-0000-0000-0000-000000000001');
  SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[2];
  SELECT * INTO activated FROM public.activate_document_self_identifier(target_a_candidate,v_revision,matter_identifier,'15160000-0000-0000-0000-000000000001');
  IF activated.code<>'ok' OR activated.replayed THEN RAISE EXCEPTION 'target activation failed: %',activated.code; END IF;
  target_a_identifier:=activated.identifier_id;
  IF (SELECT outcome FROM public.current_document_reference_resolutions WHERE mention_id=mention_one)<>'unique_exact'
    OR (SELECT target_document_id FROM public.current_document_reference_resolutions WHERE mention_id=mention_one)<>docs[2] THEN RAISE EXCEPTION 'later target did not resolve the pending mention'; END IF;
  SELECT * INTO activated FROM public.activate_document_self_identifier(target_a_candidate,v_revision,matter_identifier,'15160000-0000-0000-0000-000000000001');
  IF activated.code<>'ok' OR NOT activated.replayed OR activated.identifier_id<>target_a_identifier THEN RAISE EXCEPTION 'activation replay did not converge'; END IF;
  SELECT count(*) INTO decisions_before FROM public.document_identifier_decisions;
  SELECT count(*) INTO activity_before FROM public.activity_events WHERE event_type='document.identifier_changed';
  SELECT * INTO activated FROM public.activate_document_self_identifier(target_a_candidate,v_revision+1,matter_identifier,'15160000-0000-0000-0000-000000000001');
  IF activated.code<>'idempotency_conflict'
    OR (SELECT count(*) FROM public.document_identifier_decisions)<>decisions_before
    OR (SELECT count(*) FROM public.activity_events WHERE event_type='document.identifier_changed')<>activity_before THEN
    RAISE EXCEPTION 'idempotency fingerprint mismatch did not fail without effects';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.activity_events WHERE event_type='document.identifier_changed' AND subject_id=docs[2])
    OR NOT EXISTS(SELECT 1 FROM public.activity_projector_outbox_events WHERE activity_event_id IN (SELECT id FROM public.activity_events WHERE event_type='document.identifier_changed' AND subject_id=docs[2])) THEN RAISE EXCEPTION 'human identifier decision did not append canonical Activity/projector work'; END IF;

  SELECT id INTO mention_two FROM public.document_reference_mentions WHERE source_document_id=docs[4];
  IF mention_two IS NULL OR (SELECT outcome FROM public.current_document_reference_resolutions WHERE mention_id=mention_two)<>'unique_exact' THEN RAISE EXCEPTION 'target-first arrival did not resolve immediately'; END IF;

  SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[3];
  SELECT * INTO activated FROM public.activate_document_self_identifier(target_b_candidate,v_revision,NULL,'15160000-0000-0000-0000-000000000002');
  target_b_identifier:=activated.identifier_id;
  IF activated.code<>'ok' OR EXISTS(SELECT 1 FROM public.current_document_reference_resolutions WHERE mention_id IN (mention_one,mention_two) AND outcome<>'ambiguous') THEN RAISE EXCEPTION 'same exact key did not become ambiguous'; END IF;
  SELECT id,revision INTO duplicate_item,duplicate_revision FROM public.review_items WHERE org_id=org AND type='possible_duplicate' AND status='needs_review';
  IF duplicate_item IS NULL OR (SELECT count(*) FROM public.review_items WHERE org_id=org AND type='possible_duplicate' AND status='needs_review')<>1
    OR NOT public.possible_duplicate_current(duplicate_item)
    OR jsonb_array_length(public.read_review_detail(duplicate_item)->'evidence')<>2
    OR EXISTS(SELECT 1 FROM public.possible_duplicate_sources WHERE review_item_id=duplicate_item GROUP BY review_item_id HAVING count(DISTINCT asset_id)<>2)
    THEN RAISE EXCEPTION 'two source-grounded distinct assets did not make exactly one current Review: item %, current %, sources %, eligible %, detail %',
      duplicate_item,public.possible_duplicate_current(duplicate_item),
      (SELECT jsonb_agg(jsonb_build_object('doc',s.document_id,'revision',s.document_lifecycle_revision,'sha',s.sha256)) FROM public.possible_duplicate_sources s WHERE s.review_item_id=duplicate_item),
      (SELECT jsonb_agg(jsonb_build_object('doc',e.document_id,'revision',e.lifecycle_revision,'sha',e.sha256)) FROM public.possible_duplicate_eligible e WHERE e.org_id=org AND e.normalized_value='GST/555/2026'),
      public.read_review_detail(duplicate_item); END IF;
  -- Three current sources close the formerly active pair and present one complete group, not pairwise items.
  SELECT id INTO source_candidate FROM public.document_field_candidates WHERE document_id=docs[1] AND field_path='document.official_reference.self_identifier';
  SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[1];
  SELECT * INTO activated FROM public.activate_document_self_identifier(source_candidate,v_revision,NULL,'15160000-0000-0000-0000-000000000016');
  third_identifier:=activated.identifier_id;
  IF activated.code<>'ok' OR (SELECT count(*) FROM public.document_self_identifiers WHERE org_id=org AND lifecycle_state='active'
      AND normalized_value='GST/555/2026')<>3
    OR (SELECT count(*) FROM public.review_items WHERE org_id=org AND type='possible_duplicate' AND status='needs_review')<>1
    OR (SELECT closure_reason FROM public.review_items WHERE id=duplicate_item)<>'source_replaced'
    THEN RAISE EXCEPTION 'three-way collision did not replace the old pair with one group'; END IF;
  SELECT id,revision INTO duplicate_item,duplicate_revision FROM public.review_items WHERE org_id=org AND type='possible_duplicate' AND status='needs_review';
  IF NOT public.possible_duplicate_current(duplicate_item) OR jsonb_array_length(public.read_review_detail(duplicate_item)->'evidence')<>3
    OR (SELECT count(DISTINCT document_id) FROM public.possible_duplicate_sources WHERE review_item_id=duplicate_item)<>3
    OR (SELECT count(DISTINCT asset_id) FROM public.possible_duplicate_sources WHERE review_item_id=duplicate_item)<>3
    THEN RAISE EXCEPTION 'group detail omitted an exact current source'; END IF;
  SELECT * INTO duplicate_resolution FROM public.resolve_possible_duplicate(duplicate_item,duplicate_revision,'possible_same_document',
    'One selected source is not a subset',ARRAY[docs[1]],gen_random_uuid());
  IF duplicate_resolution.code<>'invalid_request' THEN RAISE EXCEPTION 'single-member finding was accepted'; END IF;
  SELECT * INTO duplicate_resolution FROM public.resolve_possible_duplicate(duplicate_item,duplicate_revision,'possible_same_document',
    'Unlisted source is not a member',ARRAY[docs[1],docs[4]],gen_random_uuid());
  IF duplicate_resolution.code<>'invalid_selection' THEN RAISE EXCEPTION 'foreign member was accepted'; END IF;
  BEGIN
    SELECT * INTO duplicate_resolution FROM public.resolve_possible_duplicate(duplicate_item,duplicate_revision,'possible_same_document',
      'These two may be the same, with no claim about the third',ARRAY[docs[2],docs[3]],gen_random_uuid());
    IF duplicate_resolution.code<>'ok' OR duplicate_resolution.replayed
      OR (SELECT selected_document_ids FROM public.possible_duplicate_decisions WHERE review_item_id=duplicate_item)<>ARRAY[docs[2],docs[3]]
      OR (SELECT count(*) FROM public.activity_events WHERE event_type='review.possible_duplicate_decided')<>1
      OR jsonb_array_length(public.read_review_detail(duplicate_item)->'last_decision'->'selected_document_ids')<>2
      THEN RAISE EXCEPTION 'subset finding was not exact, immutable and single-Activity'; END IF;
    PERFORM public.reconcile_possible_duplicate_key(org,'order_reference','GST TRIBUNAL','GST/555/2026');
    IF (SELECT count(*) FROM public.review_items WHERE org_id=org AND type='possible_duplicate' AND status='needs_review')<>0
      OR (SELECT count(*) FROM public.possible_duplicate_decisions WHERE review_item_id=duplicate_item)<>1
      THEN RAISE EXCEPTION 'unchanged possible-same subset flooded Review'; END IF;
    SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[1];
    SELECT * INTO activated FROM public.revoke_document_self_identifier(third_identifier,1,v_revision,
      'Changed full source set after subset decision',gen_random_uuid());
    IF activated.code<>'ok' OR (SELECT count(*) FROM public.review_items WHERE org_id=org AND type='possible_duplicate' AND status='needs_review')<>1
      OR EXISTS(SELECT 1 FROM public.review_items item JOIN public.possible_duplicate_sources source ON source.review_item_id=item.id
        WHERE item.org_id=org AND item.type='possible_duplicate' AND item.status='needs_review'
        GROUP BY item.id HAVING count(*)<>2)
      THEN RAISE EXCEPTION 'materially changed source set did not reevaluate'; END IF;
    RAISE EXCEPTION USING ERRCODE='Z0171',MESSAGE='rollback group finding for lifecycle assertions';
  EXCEPTION WHEN SQLSTATE 'Z0171' THEN NULL; END;
  BEGIN
    SELECT * INTO duplicate_resolution FROM public.resolve_possible_duplicate(duplicate_item,duplicate_revision,'distinct_documents',
      'All three exact sources are separate current documents','{}'::uuid[],gen_random_uuid());
    IF duplicate_resolution.code<>'ok' OR duplicate_resolution.replayed
      OR (SELECT cardinality(selected_document_ids) FROM public.possible_duplicate_decisions WHERE review_item_id=duplicate_item)<>0
      OR (SELECT count(*) FROM public.activity_events WHERE event_type='review.possible_duplicate_decided')<>1
      THEN RAISE EXCEPTION 'all-distinct group decision was not exact and single-Activity'; END IF;
    PERFORM public.reconcile_possible_duplicate_key(org,'order_reference','GST TRIBUNAL','GST/555/2026');
    IF (SELECT count(*) FROM public.review_items WHERE org_id=org AND type='possible_duplicate' AND status='needs_review')<>0
      THEN RAISE EXCEPTION 'unchanged all-distinct full set reopened'; END IF;
    RAISE EXCEPTION USING ERRCODE='Z0171',MESSAGE='rollback all-distinct for lifecycle assertions';
  EXCEPTION WHEN SQLSTATE 'Z0171' THEN NULL; END;
  SELECT * INTO duplicate_resolution FROM public.resolve_possible_duplicate(duplicate_item,duplicate_revision,'distinct_documents',
    'Stale former pair','15170000-0000-0000-0000-000000000010');
  IF duplicate_resolution.code<>'invalid_request' OR EXISTS(SELECT 1 FROM public.possible_duplicate_decisions WHERE review_item_id=duplicate_item)
    THEN RAISE EXCEPTION 'legacy pair-only resolver accepted a group'; END IF;
  UPDATE public.documents SET record_state='trashed',deleted_at=now(),trashed_at=now(),trashed_by=actor,lifecycle_revision=lifecycle_revision+1 WHERE id=docs[1];
  IF (SELECT count(*) FROM public.possible_duplicate_eligible WHERE org_id=org AND normalized_value='GST/555/2026')<>2
    OR EXISTS(SELECT 1 FROM public.review_items WHERE org_id=org AND type='possible_duplicate' AND status='needs_review')
    THEN RAISE EXCEPTION 'unavailable third source was silently omitted to create a pair'; END IF;
  UPDATE public.documents SET record_state='active',deleted_at=NULL,trashed_at=NULL,trashed_by=NULL,restored_at=now(),lifecycle_revision=lifecycle_revision+1 WHERE id=docs[1];
  SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[1];
  PERFORM public.revoke_document_self_identifier(third_identifier,1,v_revision,'Three-way abstention fixture reset',
    '15160000-0000-0000-0000-000000000017');
  SELECT id,revision INTO duplicate_item,duplicate_revision FROM public.review_items WHERE org_id=org AND type='possible_duplicate' AND status='needs_review';
  IF duplicate_item IS NULL OR (SELECT count(*) FROM public.review_items WHERE org_id=org AND type='possible_duplicate' AND status='needs_review')<>1
    THEN RAISE EXCEPTION 'return from three-way abstention did not refresh one current pair'; END IF;
  FOREACH source_candidate IN ARRAY ARRAY[viewer,suspended,ambiguous_actor,foreign_actor] LOOP
    PERFORM set_config('request.jwt.claim.sub',source_candidate::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',source_candidate,'iat',extract(epoch FROM now())::bigint)::text,true);
    IF source_candidate=viewer THEN
      IF public.read_review_detail(duplicate_item)->'allowed_actions'<>'[]'::jsonb
        OR (SELECT total_count FROM public.read_review_queue('needs_review','possible_duplicate','all','',1,25))<>1 THEN
        RAISE EXCEPTION 'Viewer source read or decision capability was wrong'; END IF;
    ELSE
      IF public.read_review_detail(duplicate_item) IS NOT NULL
        OR EXISTS(SELECT 1 FROM public.read_review_queue('needs_review','possible_duplicate','all','',1,25) WHERE total_count>0) THEN
        RAISE EXCEPTION 'non-member context disclosed possible-duplicate Review'; END IF;
    END IF;
    SELECT * INTO duplicate_resolution FROM public.resolve_possible_duplicate(duplicate_item,duplicate_revision,'distinct_documents',
      'Unauthorised direct item attempt',gen_random_uuid());
    IF (source_candidate=foreign_actor AND duplicate_resolution.code<>'unavailable')
      OR (source_candidate<>foreign_actor AND duplicate_resolution.code<>'forbidden')
      OR EXISTS(SELECT 1 FROM public.possible_duplicate_decisions WHERE review_item_id=duplicate_item) THEN
      RAISE EXCEPTION 'direct possible-duplicate resolver authority leaked to %: %',source_candidate,duplicate_resolution.code; END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',actor,'iat',extract(epoch FROM now())::bigint)::text,true);
  SELECT * INTO duplicate_resolution FROM public.resolve_possible_duplicate(duplicate_item,duplicate_revision,'distinct_documents',
    'Later order legitimately reuses the official reference','15170000-0000-0000-0000-000000000001');
  IF duplicate_resolution.code<>'ok' OR duplicate_resolution.replayed OR (SELECT status FROM public.review_items WHERE id=duplicate_item)<>'closed'
    OR (SELECT count(*) FROM public.activity_events WHERE event_type='review.possible_duplicate_decided')<>1
    THEN RAISE EXCEPTION 'distinct decision did not close once with Activity'; END IF;
  SELECT * INTO duplicate_resolution FROM public.resolve_possible_duplicate(duplicate_item,duplicate_revision,'distinct_documents',
    'Later order legitimately reuses the official reference','15170000-0000-0000-0000-000000000001');
  IF duplicate_resolution.code<>'ok' OR NOT duplicate_resolution.replayed THEN RAISE EXCEPTION 'duplicate decision replay diverged'; END IF;
  SELECT * INTO duplicate_resolution FROM public.resolve_possible_duplicate(duplicate_item,duplicate_revision,'possible_same_document',
    'Different request under the same idempotency key','15170000-0000-0000-0000-000000000001');
  IF duplicate_resolution.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'decision key replay accepted different payload'; END IF;
  PERFORM public.reconcile_possible_duplicate_key(org,'order_reference','GST TRIBUNAL','GST/555/2026');
  IF EXISTS(SELECT 1 FROM public.review_items WHERE org_id=org AND type='possible_duplicate' AND status='needs_review')
    OR (SELECT count(*) FROM public.possible_duplicate_decisions WHERE org_id=org)<>1 THEN
    RAISE EXCEPTION 'unchanged distinct decision reopened or duplicated'; END IF;
  IF EXISTS(SELECT 1 FROM public.current_document_reference_resolutions WHERE mention_id IN (mention_one,mention_two) AND (target_document_id IS NOT NULL OR target_identifier_id IS NOT NULL)) THEN RAISE EXCEPTION 'ambiguous outcome leaked target identities'; END IF;

  SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[3];
  SELECT * INTO activated FROM public.revoke_document_self_identifier(target_b_identifier,1,v_revision,'Duplicate document identity','15160000-0000-0000-0000-000000000003');
  IF activated.code<>'ok' OR EXISTS(SELECT 1 FROM public.current_document_reference_resolutions WHERE mention_id IN (mention_one,mention_two) AND outcome<>'unique_exact') THEN RAISE EXCEPTION 'targeted revoke reevaluation did not converge'; END IF;

  -- A source document claiming the exact key is a hard self-target conflict.
  SELECT id INTO source_candidate FROM public.document_field_candidates WHERE document_id=docs[1] AND field_path='document.official_reference.self_identifier';
  SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[1];
  SELECT * INTO activated FROM public.activate_document_self_identifier(source_candidate,v_revision,NULL,'15160000-0000-0000-0000-000000000004');
  source_identifier:=activated.identifier_id;
  IF activated.code<>'ok' OR (SELECT outcome FROM public.current_document_reference_resolutions WHERE mention_id=mention_one)<>'conflicting' THEN RAISE EXCEPTION 'self-target did not become conflicting'; END IF;
  SELECT id,revision INTO duplicate_item,duplicate_revision FROM public.review_items WHERE org_id=org AND type='possible_duplicate' AND status='needs_review';
  IF duplicate_item IS NULL OR (SELECT count(*) FROM public.review_items WHERE org_id=org AND type='possible_duplicate' AND status='needs_review')<>1
    THEN RAISE EXCEPTION 'new legitimate same-reference pair was not independently reviewed'; END IF;
  SELECT * INTO duplicate_resolution FROM public.resolve_possible_duplicate(duplicate_item,duplicate_revision+1,'possible_same_document',
    'Check whether these versions represent one source','15170000-0000-0000-0000-000000000002');
  IF duplicate_resolution.code<>'stale' THEN RAISE EXCEPTION 'possible-duplicate resolver accepted a stale revision'; END IF;
  SELECT * INTO duplicate_resolution FROM public.resolve_possible_duplicate(duplicate_item,duplicate_revision,'possible_same_document',
    'Check whether these versions represent one source','15170000-0000-0000-0000-000000000002');
  IF duplicate_resolution.code<>'ok' OR duplicate_resolution.replayed
    OR (SELECT count(*) FROM public.possible_duplicate_decisions WHERE action='possible_same_document')<>1
    OR (SELECT count(*) FROM public.activity_events WHERE event_type='review.possible_duplicate_decided')<>2
    OR NOT EXISTS(SELECT 1 FROM public.documents d JOIN public.document_versions v ON v.id=d.current_version_id AND v.org_id=d.org_id
      WHERE d.id=docs[1] AND d.org_id=org AND v.asset_id=assets[1] AND d.matter_id=matter_a)
    OR NOT EXISTS(SELECT 1 FROM public.documents d JOIN public.document_versions v ON v.id=d.current_version_id AND v.org_id=d.org_id
      WHERE d.id=docs[2] AND d.org_id=org AND v.asset_id=assets[2] AND d.matter_id=matter_a)
    THEN RAISE EXCEPTION 'possible-same interpretation did not close once without changing either document'; END IF;
  SELECT * INTO duplicate_resolution FROM public.resolve_possible_duplicate(duplicate_item,duplicate_revision,'possible_same_document',
    'Check whether these versions represent one source','15170000-0000-0000-0000-000000000002');
  IF duplicate_resolution.code<>'ok' OR NOT duplicate_resolution.replayed THEN RAISE EXCEPTION 'possible-same replay diverged'; END IF;
  IF (SELECT target_document_id FROM public.current_document_reference_resolutions WHERE mention_id=mention_one) IS NOT NULL THEN RAISE EXCEPTION 'conflict leaked a target'; END IF;
  SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[1];
  PERFORM public.revoke_document_self_identifier(source_identifier,1,v_revision,'Self claim corrected','15160000-0000-0000-0000-000000000005');

  -- Trash and Restore use the document-state hook and never mutate assignment.
  UPDATE public.documents SET record_state='trashed',deleted_at=now(),trashed_at=now(),trashed_by=actor,lifecycle_revision=lifecycle_revision+1 WHERE id=docs[2];
  IF EXISTS(SELECT 1 FROM public.current_document_reference_resolutions WHERE mention_id IN (mention_one,mention_two) AND outcome<>'unresolved') THEN RAISE EXCEPTION 'Trash target remained match eligible'; END IF;
  UPDATE public.documents SET record_state='active',deleted_at=NULL,trashed_at=NULL,trashed_by=NULL,restored_at=now(),lifecycle_revision=lifecycle_revision+1 WHERE id=docs[2];
  IF EXISTS(SELECT 1 FROM public.current_document_reference_resolutions WHERE mention_id IN (mention_one,mention_two) AND outcome<>'unique_exact') THEN RAISE EXCEPTION 'Restore did not reactivate exact resolution'; END IF;

  -- The controlled permanent-purge workflow is not blocked by reference
  -- history. A formerly unique target is scrubbed from historical results and
  -- cannot remain or reappear as a current match after its evidence is gone.
  SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[3];
  SELECT * INTO activated FROM public.activate_document_self_identifier(target_b_candidate,v_revision,NULL,'15160000-0000-0000-0000-000000000013');
  purged_identifier:=activated.identifier_id;
  IF activated.code<>'ok' THEN RAISE EXCEPTION 'purge target reactivation failed'; END IF;
  UPDATE public.documents SET record_state='trashed',deleted_at=now(),trashed_at=now(),trashed_by=actor,lifecycle_revision=lifecycle_revision+1 WHERE id=docs[2];
  IF EXISTS(SELECT 1 FROM public.current_document_reference_resolutions WHERE mention_id IN (mention_one,mention_two) AND (outcome<>'unique_exact' OR target_document_id<>docs[3])) THEN
    RAISE EXCEPTION 'purge probe did not establish a unique target';
  END IF;
  SELECT * INTO trashed FROM public.trash_resource('document',docs[3],'reference.fixture.trash.purge');
  IF trashed.code<>'trashed' THEN RAISE EXCEPTION 'controlled purge setup failed: %',trashed.code; END IF;
  SELECT * INTO purge_impact FROM public.get_trash_purge_impact(trashed.operation_id);
  IF NOT purge_impact.can_purge THEN RAISE EXCEPTION 'document reference history incorrectly blocked purge'; END IF;
  SELECT * INTO purge_queue FROM public.confirm_trash_purge(trashed.operation_id,purge_impact.impact_fingerprint,'Reference 3','reference.fixture.confirm.purge');
  IF purge_queue.code<>'queued' THEN RAISE EXCEPTION 'document reference purge did not queue: %',purge_queue.code; END IF;
  SELECT * INTO purge_job FROM public.claim_trash_purge_work(10,120) WHERE operation_id=trashed.operation_id;
  SELECT * INTO purge_step FROM public.prepare_trash_purge_database(purge_job.job_id,purge_job.lease_token);
  IF purge_step.code<>'prepared' THEN RAISE EXCEPTION 'document reference purge preparation failed: %',purge_step.code; END IF;
  FOR storage_step IN SELECT * FROM public.claim_trash_purge_storage_deletions(purge_job.job_id,purge_job.lease_token,25,120) LOOP
    PERFORM public.finish_trash_purge_storage_deletion(storage_step.deletion_id,storage_step.lease_token,'deleted');
  END LOOP;
  SELECT * INTO purge_step FROM public.finish_trash_purge_attempt(purge_job.job_id,purge_job.lease_token);
  IF purge_step.code<>'purged'
    OR (SELECT record_state::text FROM public.documents WHERE id=docs[3])<>'purged'
    OR NOT EXISTS(SELECT 1 FROM public.document_self_identifiers WHERE id=purged_identifier AND lifecycle_state='revoked' AND document_id IS NULL AND evidence_purged_at IS NOT NULL)
    OR EXISTS(SELECT 1 FROM public.document_reference_resolution_results WHERE target_document_id=docs[3] OR target_identifier_id=purged_identifier)
    OR EXISTS(SELECT 1 FROM public.current_document_reference_resolutions WHERE mention_id IN (mention_one,mention_two) AND (outcome<>'unresolved' OR target_document_id IS NOT NULL OR target_identifier_id IS NOT NULL)) THEN
    RAISE EXCEPTION 'purged exact target remained reusable or disclosed: state=%, alias=%, historical_target=%, current_bad=%',
      (SELECT record_state::text FROM public.documents WHERE id=docs[3]),
      (SELECT jsonb_build_object('state',lifecycle_state,'document',document_id,'purged',evidence_purged_at IS NOT NULL) FROM public.document_self_identifiers WHERE id=purged_identifier),
      EXISTS(SELECT 1 FROM public.document_reference_resolution_results WHERE target_document_id=docs[3] OR target_identifier_id=purged_identifier),
      EXISTS(SELECT 1 FROM public.current_document_reference_resolutions WHERE mention_id IN (mention_one,mention_two) AND (outcome<>'unresolved' OR target_document_id IS NOT NULL OR target_identifier_id IS NOT NULL));
  END IF;
  UPDATE public.documents SET record_state='active',deleted_at=NULL,trashed_at=NULL,trashed_by=NULL,restored_at=now(),lifecycle_revision=lifecycle_revision+1 WHERE id=docs[2];
  IF EXISTS(SELECT 1 FROM public.current_document_reference_resolutions WHERE mention_id IN (mention_one,mention_two) AND (outcome<>'unique_exact' OR target_document_id<>docs[2])) THEN
    RAISE EXCEPTION 'surviving exact target did not recover after purge';
  END IF;

  -- Duplicate exact-key delivery is idempotent at the run identity.
  PERFORM public.reevaluate_document_reference_exact_key(org,'GST TRIBUNAL','order_reference','GST/555/2026','explicit_retry','retry.same-key');
  PERFORM public.reevaluate_document_reference_exact_key(org,'GST TRIBUNAL','order_reference','GST/555/2026','explicit_retry','retry.same-key');
  IF (SELECT count(*) FROM public.document_reference_resolution_runs WHERE trigger_key='retry.same-key')<>1 THEN RAISE EXCEPTION 'duplicate reevaluation event created duplicate runs'; END IF;

  -- Viewer and direct authenticated/service DML are denied opaquely.
  PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',viewer,'iat',extract(epoch FROM now())::bigint)::text,true);
  SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[2];
  SELECT * INTO activated FROM public.revoke_document_self_identifier(target_a_identifier,1,v_revision,'Viewer attempt','15160000-0000-0000-0000-000000000006');
  IF activated.code<>'not_allowed' THEN RAISE EXCEPTION 'Viewer command was not denied opaquely'; END IF;
  IF (SELECT count(*) FROM public.read_current_document_reference_resolutions(ARRAY[docs[1],docs[4]]))<>2
    OR (SELECT count(*) FROM public.read_current_document_self_identifiers(ARRAY[docs[2]]))<>1 THEN RAISE EXCEPTION 'Viewer-safe current projections were unavailable'; END IF;

  -- A foreign/wrong-document successor cannot revoke the active predecessor;
  -- then a valid same-document correction is append-only and atomic.
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',actor,'iat',extract(epoch FROM now())::bigint)::text,true);
  SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[2];
  SELECT * INTO activated FROM public.correct_document_self_identifier(target_a_identifier,source_candidate,1,v_revision,NULL,'Invalid successor probe','15160000-0000-0000-0000-000000000007');
  IF activated.code<>'invalid_candidate' OR NOT EXISTS(SELECT 1 FROM public.document_self_identifiers WHERE id=target_a_identifier AND lifecycle_state='active' AND revision=1) THEN RAISE EXCEPTION 'failed correction revoked its predecessor'; END IF;
  SELECT * INTO activated FROM public.correct_document_self_identifier(target_a_identifier,correction_candidate,1,v_revision,NULL,'Corrected official reference','15160000-0000-0000-0000-000000000008');
  corrected_identifier:=activated.identifier_id;
  IF activated.code<>'ok' OR activated.previous_identifier_id<>target_a_identifier
    OR NOT EXISTS(SELECT 1 FROM public.document_self_identifiers WHERE id=target_a_identifier AND lifecycle_state='revoked' AND revision=2)
    OR NOT EXISTS(SELECT 1 FROM public.document_self_identifiers WHERE id=corrected_identifier AND predecessor_identifier_id=target_a_identifier AND lifecycle_state='active')
    OR EXISTS(SELECT 1 FROM public.current_document_reference_resolutions WHERE mention_id IN (mention_one,mention_two) AND outcome<>'unresolved') THEN RAISE EXCEPTION 'governed correction lineage or old-key reevaluation failed'; END IF;
  SELECT * INTO activated FROM public.correct_document_self_identifier(target_a_identifier,correction_candidate,1,v_revision,NULL,'Corrected official reference','15160000-0000-0000-0000-000000000008');
  IF activated.code<>'ok' OR NOT activated.replayed OR activated.identifier_id<>corrected_identifier THEN RAISE EXCEPTION 'correction replay did not converge'; END IF;
  SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[2];
  SELECT * INTO activated FROM public.correct_document_self_identifier(corrected_identifier,target_a_candidate,1,v_revision,matter_identifier,'Restored exact source value','15160000-0000-0000-0000-000000000009');
  target_a_identifier:=activated.identifier_id;
  IF activated.code<>'ok' OR EXISTS(SELECT 1 FROM public.current_document_reference_resolutions WHERE mention_id IN (mention_one,mention_two) AND outcome<>'unique_exact') THEN RAISE EXCEPTION 'second correction did not restore the exact-key target'; END IF;

  -- All approved ordinary-legal-work roles can make governed decisions; each
  -- still goes through candidate authority, revision CAS, receipts and audit.
  PERFORM set_config('request.jwt.claim.sub',admin_actor::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',admin_actor,'iat',extract(epoch FROM now())::bigint)::text,true);
  SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[2];
  SELECT * INTO activated FROM public.revoke_document_self_identifier(target_a_identifier,1,v_revision,'Admin authority probe','15160000-0000-0000-0000-000000000010');
  IF activated.code<>'ok' THEN RAISE EXCEPTION 'Admin governed identifier decision failed'; END IF;
  PERFORM set_config('request.jwt.claim.sub',associate_actor::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',associate_actor,'iat',extract(epoch FROM now())::bigint)::text,true);
  SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[2];
  SELECT * INTO activated FROM public.activate_document_self_identifier(target_a_candidate,v_revision,matter_identifier,'15160000-0000-0000-0000-000000000011');
  target_a_identifier:=activated.identifier_id;
  IF activated.code<>'ok' THEN RAISE EXCEPTION 'Associate governed identifier decision failed'; END IF;
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',actor,'iat',extract(epoch FROM now())::bigint)::text,true);

  -- Replacing the target source version makes the old verified alias historical;
  -- no current projection may continue using it.
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
    VALUES('151f0000-0000-0000-0000-000000000099',org,'documents','orgs/'||org||'/assets/151f0000-0000-0000-0000-000000000099/original.pdf',repeat('9',64),101,'application/pdf','available',now(),1,actor);
  UPDATE public.document_versions SET state='superseded',superseded_at=now() WHERE id=versions[2];
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
    VALUES('15100000-0000-0000-0000-000000000099',org,docs[2],'151f0000-0000-0000-0000-000000000099',2,'replacement.pdf',1,'valid','current',now(),now(),actor);
  UPDATE public.documents SET current_version_id='15100000-0000-0000-0000-000000000099',lifecycle_revision=lifecycle_revision+1 WHERE id=docs[2];
  IF EXISTS(SELECT 1 FROM public.current_document_reference_resolutions WHERE mention_id IN (mention_one,mention_two) AND outcome<>'unresolved')
    OR (SELECT count(*) FROM public.read_current_document_self_identifiers(ARRAY[docs[2]]))<>0 THEN RAISE EXCEPTION 'version replacement left a historical alias current-match eligible'; END IF;

  SELECT count(*) INTO identifiers_before FROM public.document_self_identifiers;
  SELECT id INTO outbound_candidate FROM public.document_field_candidates WHERE document_id=docs[4] AND field_path='document.official_reference.outbound_mention';
  SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[4];
  SELECT * INTO activated FROM public.activate_document_self_identifier(outbound_candidate,v_revision,NULL,'15160000-0000-0000-0000-000000000012');
  IF activated.code<>'invalid_candidate' THEN RAISE EXCEPTION 'outbound mention candidate was accepted as a self identifier'; END IF;
  SELECT lifecycle_revision INTO v_revision FROM public.documents WHERE id=docs[2];
  SELECT * INTO activated FROM public.activate_document_self_identifier(target_a_candidate,v_revision,NULL,'15160000-0000-0000-0000-000000000014');
  IF activated.code<>'invalid_candidate' OR (SELECT count(*) FROM public.document_self_identifiers)<>identifiers_before THEN
    RAISE EXCEPTION 'historical-version candidate was accepted or wrote state';
  END IF;

  -- Every non-writer authority shape fails without exposing candidate tenancy.
  FOREACH source_candidate IN ARRAY ARRAY[suspended,ambiguous_actor,foreign_actor] LOOP
    PERFORM set_config('request.jwt.claim.sub',source_candidate::text,true);
    PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',source_candidate,'iat',extract(epoch FROM now())::bigint)::text,true);
    SELECT * INTO activated FROM public.activate_document_self_identifier(target_a_candidate,1,NULL,gen_random_uuid());
    IF activated.code NOT IN ('not_allowed','context_unavailable') THEN RAISE EXCEPTION 'non-writer authority was not denied opaquely: %',activated.code; END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',actor,'iat',extract(epoch FROM now())::bigint)::text,true);

  SELECT count(*) INTO links_before FROM public.document_links; SELECT count(*) INTO relationships_before FROM public.document_relationships;
  SELECT count(*) INTO outbox_before FROM public.outbox_events; SELECT count(*) INTO effective_before FROM public.document_effective_metadata;
  IF EXISTS(SELECT 1 FROM public.document_reference_resolution_results WHERE outcome<>'unique_exact' AND (target_document_id IS NOT NULL OR target_identifier_id IS NOT NULL))
    OR NOT EXISTS(SELECT 1 FROM pg_indexes WHERE indexname='document_self_identifiers_exact_active_idx' AND indexdef LIKE '%issuer_namespace_normalized%normalized_value%')
    OR NOT EXISTS(SELECT 1 FROM pg_indexes WHERE indexname='document_reference_mentions_exact_idx' AND indexdef LIKE '%issuer_namespace_normalized%normalized_value%') THEN RAISE EXCEPTION 'resolution disclosure or indexed-key contract failed'; END IF;
  IF (SELECT count(*) FROM public.document_links)<>links_before OR (SELECT count(*) FROM public.document_relationships)<>relationships_before OR (SELECT count(*) FROM public.outbox_events)<>outbox_before OR (SELECT count(*) FROM public.document_effective_metadata)<>effective_before THEN RAISE EXCEPTION 'reference resolution created a prohibited consequence'; END IF;
  PERFORM set_config('enable_seqscan','off',true);
  EXECUTE format('EXPLAIN (FORMAT JSON) SELECT id FROM public.document_self_identifiers WHERE org_id=%L AND issuer_namespace_normalized=%L AND identifier_kind=%L AND normalized_value=%L AND lifecycle_state=%L AND document_id IS NOT NULL AND evidence_purged_at IS NULL',org,'GST TRIBUNAL','order_reference','GST/555/2026','active') INTO query_plan;
  IF query_plan::text NOT LIKE '%document_self_identifiers_exact_active_idx%'
    AND query_plan::text NOT LIKE '%document_self_identifiers_document_active_idx%' THEN RAISE EXCEPTION 'self-identifier exact-key query did not use a bounded exact-key index'; END IF;
  EXECUTE format('EXPLAIN (FORMAT JSON) SELECT id FROM public.document_reference_mentions WHERE org_id=%L AND issuer_namespace_normalized=%L AND identifier_kind=%L AND normalized_value=%L',org,'GST TRIBUNAL','order_reference','GST/555/2026') INTO query_plan;
  IF query_plan::text NOT LIKE '%document_reference_mentions_exact_idx%'
    AND query_plan::text NOT LIKE '%document_reference_mentions_source_current_idx%' THEN RAISE EXCEPTION 'mention exact-key query did not use a bounded exact-key index'; END IF;
  EXECUTE format('EXPLAIN (FORMAT JSON) SELECT issuer_namespace_normalized,identifier_kind,normalized_value FROM public.document_self_identifiers WHERE org_id=%L AND document_id=%L AND lifecycle_state=%L AND evidence_purged_at IS NULL',org,docs[2],'active') INTO query_plan;
  IF query_plan::text NOT LIKE '%document_self_identifiers_document_active_idx%' THEN RAISE EXCEPTION 'document availability self-identifier lookup did not use its bounded index'; END IF;
  EXECUTE format('EXPLAIN (FORMAT JSON) SELECT issuer_namespace_normalized,identifier_kind,normalized_value FROM public.document_reference_mentions WHERE org_id=%L AND source_document_id=%L AND evidence_purged_at IS NULL',org,docs[1]) INTO query_plan;
  IF query_plan::text NOT LIKE '%document_reference_mentions_source_current_idx%' THEN RAISE EXCEPTION 'document availability mention lookup did not use its bounded index'; END IF;
END $fixture$;

SET LOCAL ROLE authenticated;
DO $direct_dml$ DECLARE denied boolean:=false; BEGIN
  BEGIN DELETE FROM public.document_reference_mentions; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'authenticated direct mention DML was accepted'; END IF;
END $direct_dml$;
RESET ROLE;
SET LOCAL ROLE anon;
DO $anonymous_surface$ DECLARE denied_mutation boolean:=false; denied_reader boolean:=false; BEGIN
  BEGIN PERFORM public.activate_document_self_identifier('15170000-0000-0000-0000-000000000001',1,NULL,'15170000-0000-0000-0000-000000000002'); EXCEPTION WHEN insufficient_privilege THEN denied_mutation:=true; END;
  BEGIN PERFORM public.read_current_document_reference_resolutions(ARRAY['15170000-0000-0000-0000-000000000003'::uuid]); EXCEPTION WHEN insufficient_privilege THEN denied_reader:=true; END;
  IF NOT denied_mutation OR NOT denied_reader THEN RAISE EXCEPTION 'anonymous document reference surface was executable'; END IF;
END $anonymous_surface$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $service_dml$ DECLARE denied boolean:=false; BEGIN
  BEGIN UPDATE public.document_self_identifiers SET revision=revision+1; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service-role direct identifier DML was accepted'; END IF;
END $service_dml$;
RESET ROLE;

DO $surface$
BEGIN
  IF has_table_privilege('authenticated','public.document_self_identifiers','SELECT')
    OR has_table_privilege('service_role','public.document_reference_mentions','INSERT')
    OR has_function_privilege('service_role','public.activate_document_self_identifier(uuid,bigint,uuid,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.read_current_document_reference_resolutions(uuid[])','EXECUTE') THEN
    RAISE EXCEPTION 'document reference authority surface is unsafe';
  END IF;
END $surface$;

ROLLBACK;
