-- Standalone rollback-only boundary repair behavior and fault acceptance.
\set ON_ERROR_STOP on
BEGIN;
-- D09-T06 source-backed fixture setup; reusable by the concurrency harness.
\set ON_ERROR_STOP on


DO $fixture$
DECLARE
  actor uuid:='152a0000-0000-0000-0000-000000000001'; viewer uuid:='152a0000-0000-0000-0000-000000000002'; suspended uuid:='152a0000-0000-0000-0000-000000000003'; foreign_actor uuid:='152a0000-0000-0000-0000-000000000004'; ambiguous_actor uuid:='152a0000-0000-0000-0000-000000000005'; admin_actor uuid:='152a0000-0000-0000-0000-000000000006'; associate_actor uuid:='152a0000-0000-0000-0000-000000000007';
  org uuid:='152b0000-0000-0000-0000-000000000001'; foreign_org uuid:='152b0000-0000-0000-0000-000000000002'; client uuid:='152c0000-0000-0000-0000-000000000001';
  matter_a uuid:='152d0000-0000-0000-0000-000000000001'; matter_b uuid:='152d0000-0000-0000-0000-000000000002';
  docs uuid[]:=ARRAY['152e0000-0000-0000-0000-000000000001','152e0000-0000-0000-0000-000000000002','152e0000-0000-0000-0000-000000000003','152e0000-0000-0000-0000-000000000004']::uuid[];
  assets uuid[]:=ARRAY['152f0000-0000-0000-0000-000000000001','152f0000-0000-0000-0000-000000000002','152f0000-0000-0000-0000-000000000003','152f0000-0000-0000-0000-000000000004']::uuid[];
  versions uuid[]:=ARRAY['15200000-0000-0000-0000-000000000001','15200000-0000-0000-0000-000000000002','15200000-0000-0000-0000-000000000003','15200000-0000-0000-0000-000000000004']::uuid[];
  processes uuid[]:=ARRAY['15210000-0000-0000-0000-000000000001','15210000-0000-0000-0000-000000000002','15210000-0000-0000-0000-000000000003','15210000-0000-0000-0000-000000000004']::uuid[];
  process_leases uuid[]:=ARRAY['15220000-0000-0000-0000-000000000001','15220000-0000-0000-0000-000000000002','15220000-0000-0000-0000-000000000003','15220000-0000-0000-0000-000000000004']::uuid[];
  runs uuid[]:=ARRAY['15230000-0000-0000-0000-000000000001','15230000-0000-0000-0000-000000000002','15230000-0000-0000-0000-000000000003','15230000-0000-0000-0000-000000000004']::uuid[];
  run_leases uuid[]:=ARRAY['15240000-0000-0000-0000-000000000001','15240000-0000-0000-0000-000000000002','15240000-0000-0000-0000-000000000003','15240000-0000-0000-0000-000000000004']::uuid[];
  catalogue text:='gst-legal-material-observation-catalogue-v3'; normalizer text:='typed-material-observation-normalizer-v3';
  ref jsonb; candidates jsonb; finished record; i integer; page_text text; source_candidate uuid; target_a_candidate uuid; target_b_candidate uuid;
  activated record; target_a_identifier uuid; target_b_identifier uuid; source_identifier uuid; corrected_identifier uuid; correction_candidate uuid; outbound_candidate uuid; mention_one uuid; mention_two uuid;
  matter_identifier uuid; v_revision bigint; rejected boolean; links_before bigint; relationships_before bigint; outbox_before bigint; effective_before bigint; decisions_before bigint; activity_before bigint; identifiers_before bigint; query_plan json;
  purged_identifier uuid; trashed record; purge_impact record; purge_queue record; purge_job record; purge_step record; storage_step record;
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
  INSERT INTO public.clients(id,org_id,name) VALUES(client,org,'Reference client');
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code) VALUES(matter_a,org,client,'Reference A','REF-152-A'),(matter_b,org,client,'Reference B','REF-152-B');
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

  UPDATE public.document_processing_runs SET state='completed',stage='ready',completed_at=now(),lease_token=NULL,lease_expires_at=NULL WHERE org_id=org;
END $fixture$;

DO $corrected_history$
DECLARE created record; corrected record; rev bigint; p jsonb; r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claim.sub','152a0000-0000-0000-0000-000000000001',true);
    SELECT revision INTO rev FROM public.matters WHERE id='152d0000-0000-0000-0000-000000000001';
    SELECT * INTO created FROM public.activate_matter_identifier('152d0000-0000-0000-0000-000000000001',rev,'order_reference','self_identifier','GST Tribunal','GST/555/2026','GST/555/2026','152e0000-0000-0000-0000-000000000004','15200000-0000-0000-0000-000000000004',1,'GST/555/2026','[]','Fixture original identity',gen_random_uuid());
    IF created.code<>'ok' THEN RAISE EXCEPTION 'Identity setup failed: %',created.code; END IF;
    SELECT revision INTO rev FROM public.matters WHERE id='152d0000-0000-0000-0000-000000000001';
    SELECT * INTO corrected FROM public.correct_matter_identifier(created.identifier_id,1,rev,'order_reference','self_identifier','GST Tribunal','GST/556/2026','GST/556/2026','152e0000-0000-0000-0000-000000000002','15200000-0000-0000-0000-000000000002',1,'GST/556/2026','[]','Correct evidence anchor',gen_random_uuid());
    IF corrected.code<>'ok' THEN RAISE EXCEPTION 'Identity correction failed: %',corrected.code; END IF;
    p:=public.preview_document_boundary_repair('152e0000-0000-0000-0000-000000000004','152d0000-0000-0000-0000-000000000002','move');
    r:=public.execute_document_boundary_repair('152e0000-0000-0000-0000-000000000004','152d0000-0000-0000-0000-000000000002','move',p->>'fingerprint','Corrected historical anchor repair',gen_random_uuid());
    IF r->>'code'<>'ok' OR NOT EXISTS(SELECT 1 FROM public.matter_identifiers WHERE id=created.identifier_id AND lifecycle_state<>'active' AND evidence_document_id='152e0000-0000-0000-0000-000000000004' AND matter_id='152d0000-0000-0000-0000-000000000001') THEN RAISE EXCEPTION 'Corrected history blocks Move: %',r; END IF;
    RAISE EXCEPTION USING ERRCODE='Z0152',MESSAGE='rollback independent history scenario';
  EXCEPTION WHEN SQLSTATE 'Z0152' THEN NULL; END;
END $corrected_history$;

DO $test$
DECLARE p jsonb; r jsonb; actor uuid:='152a0000-0000-0000-0000-000000000001';
  org uuid:='152b0000-0000-0000-0000-000000000001'; d uuid:='152e0000-0000-0000-0000-000000000001';
  target uuid:='152d0000-0000-0000-0000-000000000002'; source uuid:='152d0000-0000-0000-0000-000000000001';
  note_row record; edge_row record; copied uuid; key uuid:=gen_random_uuid(); actor_suffix text; n integer;
BEGIN
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  FOREACH actor_suffix IN ARRAY ARRAY['2','3','4'] LOOP
    PERFORM set_config('request.jwt.claim.sub','152a0000-0000-0000-0000-00000000000'||actor_suffix,true);
    p:=public.preview_document_boundary_repair(d,target,'move');
    IF p->>'code' NOT IN ('not_allowed','context_unavailable') OR p ? 'documentTitle' THEN RAISE EXCEPTION 'Denied actor leaked preview: %',p; END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  UPDATE public.documents SET content_availability='source_indexed' WHERE id=d;
  p:=public.preview_document_boundary_repair(d,target,'move');
  IF p->>'code'<>'ok' THEN RAISE EXCEPTION 'Indexed source cannot be repaired: %',p; END IF;
  p:=public.preview_document_boundary_repair(d,source,'move');
  IF p->>'code'<>'context_unavailable' THEN RAISE EXCEPTION 'Same Matter allowed'; END IF;
  SELECT * INTO note_row FROM public.create_note_with_optional_task(source,'Preserve this exact note','general',true,gen_random_uuid(),d,actor,'2026-10-01',NULL,'GST/555/2026',1,'15200000-0000-0000-0000-000000000001');
  IF note_row.code<>'ok' THEN RAISE EXCEPTION 'Note setup: %',note_row.code; END IF;
  INSERT INTO public.deadlines(matter_id,document_id,type,due_date,description) VALUES(source,d,'reply_deadline','2026-10-02','Document deadline');
  SELECT * INTO edge_row FROM public.activate_document_relationship(source,d,'152e0000-0000-0000-0000-000000000002','responds_to',(SELECT lifecycle_revision FROM public.documents WHERE id=d),(SELECT lifecycle_revision FROM public.documents WHERE id='152e0000-0000-0000-0000-000000000002'),'Verified proceeding chain',gen_random_uuid());
  IF edge_row.code<>'ok' THEN RAISE EXCEPTION 'Relationship setup: %',edge_row.code; END IF;
  p:=public.preview_document_boundary_repair(d,target,'move');
  IF p->>'code'<>'ok' OR jsonb_array_length(p->'blockers')<>0 THEN RAISE EXCEPTION 'Move preview: %',p; END IF;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p->'categories') c WHERE c->>'key'='citations' AND c->>'count'='1') THEN RAISE EXCEPTION 'Citation count missing'; END IF;
  r:=public.execute_document_boundary_repair(d,target,'move',p->>'fingerprint','',key);
  IF r->>'code'<>'invalid_request' THEN RAISE EXCEPTION 'Empty reason allowed'; END IF;
  UPDATE public.deadlines SET description='Updated deadline' WHERE document_id=d;
  r:=public.execute_document_boundary_repair(d,target,'move',p->>'fingerprint','Separate proceeding',key);
  IF r->>'code'<>'stale_preview' THEN RAISE EXCEPTION 'Dependency change escaped CAS: %',r; END IF;
  p:=public.preview_document_boundary_repair(d,target,'move');
  r:=public.execute_document_boundary_repair(d,target,'move',p->>'fingerprint','Separate proceeding',key);
  IF r->>'code'<>'ok' OR r->>'documentId'<>d::text THEN RAISE EXCEPTION 'Move failed: %',r; END IF;
  IF (SELECT matter_id FROM public.documents WHERE id=d)<>target
     OR (SELECT matter_id FROM public.case_notes WHERE id=note_row.note_id)<>target
     OR (SELECT matter_id FROM public.note_document_quotes WHERE note_id=note_row.note_id)<>target
     OR (SELECT matter_id FROM public.tasks WHERE id=note_row.task_id)<>target
     OR EXISTS(SELECT 1 FROM public.deadlines WHERE document_id=d AND matter_id<>target)
     OR (SELECT lifecycle_state FROM public.document_relationships WHERE id=edge_row.relationship_id)<>'archived'
     OR (SELECT excerpt FROM public.note_document_quotes WHERE note_id=note_row.note_id)<>'GST/555/2026' THEN RAISE EXCEPTION 'Move did not preserve dependent context'; END IF;
  r:=public.execute_document_boundary_repair(d,target,'move',p->>'fingerprint','Separate proceeding',key);
  IF r->>'code'<>'ok' OR r->>'replayed'<>'true' THEN RAISE EXCEPTION 'Replay failed: %',r; END IF;
  r:=public.execute_document_boundary_repair(d,target,'move',p->>'fingerprint','Changed reason',key);
  IF r->>'code'<>'idempotency_conflict' THEN RAISE EXCEPTION 'Changed replay accepted'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.document_processing_runs WHERE document_id=d AND state='queued' AND scope='search_index') THEN RAISE EXCEPTION 'Missing durable search rebuild'; END IF;
  UPDATE public.document_processing_runs SET state='completed',stage='ready',started_at=now(),completed_at=now() WHERE document_id=d AND state='queued';
  p:=public.preview_document_boundary_repair(d,source,'copy');
  IF p->>'code'<>'ok' OR jsonb_array_length(p->'blockers')<>0 THEN RAISE EXCEPTION 'Copy preview: %',p; END IF;
  r:=public.execute_document_boundary_repair(d,source,'copy',p->>'fingerprint','Shared proceeding source',gen_random_uuid());
  IF r->>'code'<>'ok' THEN RAISE EXCEPTION 'Copy failed: %',r; END IF;
  copied:=(r->>'documentId')::uuid;
  IF copied=d OR (SELECT copied_from_document_id FROM public.documents WHERE id=copied)<>d
     OR (SELECT asset_id FROM public.document_versions WHERE document_id=copied)<>(SELECT asset_id FROM public.document_versions WHERE id='15200000-0000-0000-0000-000000000001')
     OR (SELECT source_analysis_run_id FROM public.document_version_analysis_bindings WHERE document_id=copied)<>(SELECT source_analysis_run_id FROM public.document_version_analysis_bindings WHERE document_id=d)
     OR EXISTS(SELECT 1 FROM public.case_notes WHERE document_id=copied)
     OR EXISTS(SELECT 1 FROM public.tasks WHERE document_id=copied)
     OR EXISTS(SELECT 1 FROM public.document_self_identifiers WHERE document_id=copied)
     OR NOT EXISTS(SELECT 1 FROM public.document_reference_mentions WHERE source_document_id=copied)
     OR (SELECT count(*) FROM public.file_assets WHERE org_id=org)<>4 THEN RAISE EXCEPTION 'Copy source/lineage contract failed'; END IF;
  p:=public.preview_document_boundary_repair(d,source,'copy');
  IF jsonb_array_length(p->'blockers')=0 THEN RAISE EXCEPTION 'Duplicate target not blocked'; END IF;
  SELECT count(*) INTO n FROM public.document_boundary_repair_receipts WHERE org_id=org;
  IF n<>2 OR (SELECT count(*) FROM public.activity_events WHERE org_id=org AND event_type='document.boundary_repaired')<>2
     OR (SELECT count(*) FROM public.activity_projector_outbox_events WHERE activity_event_id IN(SELECT id FROM public.activity_events WHERE org_id=org AND event_type='document.boundary_repaired'))<>2 THEN RAISE EXCEPTION 'Receipt/Activity/outbox counts incorrect'; END IF;
END $test$;

DO $inherited_fields$
DECLARE candidate public.document_field_candidates%ROWTYPE; decision uuid; action public.document_field_decision_action;
  destination uuid; copied uuid; p jsonb; r jsonb; replacement jsonb; effective public.document_effective_metadata%ROWTYPE;
BEGIN
  SELECT * INTO candidate FROM public.document_field_candidates WHERE document_id='152e0000-0000-0000-0000-000000000002' ORDER BY id LIMIT 1;
  FOREACH action IN ARRAY ARRAY['accepted','corrected','rejected','cleared']::public.document_field_decision_action[] LOOP
    replacement:=CASE WHEN action='corrected' THEN jsonb_set(candidate.normalized_value,'{display}','"Human corrected display"') ELSE NULL END;
    decision:=public.record_document_field_decision(candidate.id,action,replacement,'Human source review','152a0000-0000-0000-0000-000000000001','fixture.copy.'||action::text);
    destination:=gen_random_uuid();
    INSERT INTO public.matters(id,org_id,client_id,title,matter_code) VALUES(destination,candidate.org_id,'152c0000-0000-0000-0000-000000000001','Private destination title', 'COPY-'||action::text);
    p:=public.preview_document_boundary_repair(candidate.document_id,destination,'copy');
    r:=public.execute_document_boundary_repair(candidate.document_id,destination,'copy',p->>'fingerprint','Share reviewed source',gen_random_uuid());
    IF r->>'code'<>'ok' THEN RAISE EXCEPTION 'Human % Copy failed: %',action,r; END IF;
    copied:=(r->>'documentId')::uuid;
    SELECT * INTO effective FROM public.document_effective_metadata WHERE document_id=copied AND field_path=candidate.field_path AND semantic_candidate_key=candidate.semantic_candidate_key;
    IF effective.resolution::text IS DISTINCT FROM action::text
      OR NOT EXISTS(SELECT 1 FROM public.document_field_decisions WHERE id=effective.winning_document_field_decision_id AND inherited_from_decision_id=decision)
      OR effective.normalized_value IS DISTINCT FROM (CASE WHEN action='accepted' THEN candidate.normalized_value WHEN action='corrected' THEN replacement ELSE NULL END)
      OR EXISTS(SELECT 1 FROM public.document_versions WHERE document_id=copied AND replacement_reason IS NOT NULL) THEN RAISE EXCEPTION 'Human % Copy lost effective value/provenance',action; END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM public.document_boundary_repair_receipts WHERE impact ? 'documentTitle' OR impact ? 'sourceMatterTitle' OR impact ? 'targetMatterTitle' OR impact ? 'blockers' OR impact ? 'categories' OR impact::text LIKE '%Private destination title%') THEN RAISE EXCEPTION 'Receipt retained legal display content'; END IF;
END $inherited_fields$;

DO $identifier_and_roles$
DECLARE p jsonb; r jsonb; created record; revision bigint; candidate uuid; identity_id uuid;
  d uuid:='152e0000-0000-0000-0000-000000000002';
  source uuid:='152d0000-0000-0000-0000-000000000001'; target uuid:='152d0000-0000-0000-0000-000000000002';
BEGIN
  SELECT m.revision INTO revision FROM public.matters m WHERE m.id=source;
  SELECT * INTO created FROM public.activate_matter_identifier(source,revision,'order_reference','self_identifier','GST Tribunal','GST/555/2026','GST/555/2026',d,'15200000-0000-0000-0000-000000000002',1,'GST/555/2026','[]','Fixture identity',gen_random_uuid());
  IF created.code<>'ok' THEN RAISE EXCEPTION 'Matter identity setup: %',created.code; END IF;
  identity_id:=created.identifier_id;
  p:=public.preview_document_boundary_repair(d,target,'move');
  IF p->>'code'<>'ok' OR jsonb_array_length(p->'blockers')=0 THEN RAISE EXCEPTION 'Anchored Matter evidence not blocked'; END IF;
  r:=public.execute_document_boundary_repair(d,target,'move',p->>'fingerprint','Invalid identity repair',gen_random_uuid());
  IF r->>'code'<>'blocked' THEN RAISE EXCEPTION 'Anchored identity moved: %',r; END IF;
  -- Copy may share the source without transferring a reserved Matter identity.
  PERFORM set_config('request.jwt.claim.sub','152a0000-0000-0000-0000-000000000007',true);
  p:=public.preview_document_boundary_repair(d,target,'copy');
  r:=public.execute_document_boundary_repair(d,target,'copy',p->>'fingerprint','Associate shares evidence',gen_random_uuid());
  IF r->>'code'<>'ok' OR (SELECT matter_id FROM public.matter_identifiers WHERE id=identity_id)<>source THEN RAISE EXCEPTION 'Associate shared Copy or reserved identity failed: %',r; END IF;
  PERFORM set_config('request.jwt.claim.sub','152a0000-0000-0000-0000-000000000001',true);
  SELECT m.revision INTO revision FROM public.matters m WHERE m.id=source;
  SELECT * INTO created FROM public.revoke_matter_identifier(identity_id,1,revision,'Historical identifier correction',gen_random_uuid());
  IF created.code<>'ok' THEN RAISE EXCEPTION 'Revoke failed: %',created.code; END IF;
  p:=public.preview_document_boundary_repair(d,target,'move');
  r:=public.execute_document_boundary_repair(d,target,'move',p->>'fingerprint','Move after identity review',gen_random_uuid());
  IF r->>'code'<>'ok' OR NOT EXISTS(SELECT 1 FROM public.matter_identifiers WHERE id=identity_id AND lifecycle_state='revoked' AND matter_id=source AND evidence_document_id=d) THEN RAISE EXCEPTION 'Historical identifier prevented Move or lost immutable history: %',r; END IF;
END $identifier_and_roles$;

-- Inject failure after all repair effects, at receipt append. The public
-- command's exception block must undo placement, versions and derived writes.
CREATE FUNCTION public.test_boundary_repair_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'fixture failure'; END $$;
CREATE TRIGGER test_boundary_repair_fail BEFORE INSERT ON public.document_boundary_repair_receipts FOR EACH ROW EXECUTE FUNCTION public.test_boundary_repair_fail();
DO $fault$
DECLARE p jsonb; r jsonb; mode text; before_docs bigint; before_events bigint;
BEGIN
  FOREACH mode IN ARRAY ARRAY['move','copy'] LOOP
    p:=public.preview_document_boundary_repair('152e0000-0000-0000-0000-000000000004','152d0000-0000-0000-0000-000000000002',mode);
    SELECT count(*) INTO before_docs FROM public.documents;
    SELECT count(*) INTO before_events FROM public.activity_events;
    r:=public.execute_document_boundary_repair('152e0000-0000-0000-0000-000000000004','152d0000-0000-0000-0000-000000000002',mode,p->>'fingerprint','Fault atomicity',gen_random_uuid());
    IF r->>'code'<>'write_failed' OR (SELECT count(*) FROM public.documents)<>before_docs OR (SELECT count(*) FROM public.activity_events)<>before_events
      OR (SELECT matter_id FROM public.documents WHERE id='152e0000-0000-0000-0000-000000000004')<>'152d0000-0000-0000-0000-000000000001' THEN RAISE EXCEPTION 'Fault left partial % effects: %',mode,r; END IF;
  END LOOP;
END $fault$;
DO $acl$
BEGIN
  IF has_table_privilege('authenticated','public.document_boundary_repair_receipts','INSERT')
     OR has_table_privilege('service_role','public.document_boundary_repair_receipts','SELECT')
     OR has_column_privilege('authenticated','public.documents','matter_id','UPDATE')
     OR has_table_privilege('authenticated','public.documents','INSERT')
     OR has_function_privilege('service_role','public.execute_document_boundary_repair(uuid,uuid,text,text,text,uuid)','EXECUTE')
     OR has_function_privilege('anon','public.preview_document_boundary_repair(uuid,uuid,text)','EXECUTE') THEN RAISE EXCEPTION 'Authority fence widened'; END IF;
END $acl$;
ROLLBACK;
