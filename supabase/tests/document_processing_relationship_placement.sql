-- Run after a clean reset through migration 00078 against a disposable local database.
-- This is one DO statement so `supabase db query --file` can execute it.
DO $fixture$
DECLARE
  org uuid := '78000000-0000-0000-0000-000000000001'; actor uuid := '78100000-0000-0000-0000-000000000001'; client uuid := '78200000-0000-0000-0000-000000000001'; inactive_client uuid := '78200000-0000-0000-0000-000000000002'; matter uuid := '78300000-0000-0000-0000-000000000001'; other_matter uuid := '78300000-0000-0000-0000-000000000002'; inactive_client_matter uuid := '78300000-0000-0000-0000-000000000003';
  src uuid; tgt uuid; ver uuid; asset uuid; candidate uuid; source_candidate uuid; source_run uuid; binding uuid; membership uuid; result record; definition text; i integer;
  docs uuid[] := ARRAY['78400000-0000-0000-0000-000000000001'::uuid,'78400000-0000-0000-0000-000000000002'::uuid,'78400000-0000-0000-0000-000000000003'::uuid,'78400000-0000-0000-0000-000000000004'::uuid,'78400000-0000-0000-0000-000000000005'::uuid,'78400000-0000-0000-0000-000000000006'::uuid,'78400000-0000-0000-0000-000000000007'::uuid,'78400000-0000-0000-0000-000000000008'::uuid,'78400000-0000-0000-0000-000000000009'::uuid,'78400000-0000-0000-0000-000000000010'::uuid,'78400000-0000-0000-0000-000000000011'::uuid,'78400000-0000-0000-0000-000000000012'::uuid,'78400000-0000-0000-0000-000000000013'::uuid,'78400000-0000-0000-0000-000000000014'::uuid,'78400000-0000-0000-0000-000000000015'::uuid,'78400000-0000-0000-0000-000000000016'::uuid,'78400000-0000-0000-0000-000000000017'::uuid,'78400000-0000-0000-0000-000000000018'::uuid,'78400000-0000-0000-0000-000000000019'::uuid,'78400000-0000-0000-0000-000000000020'::uuid,'78400000-0000-0000-0000-000000000021'::uuid,'78400000-0000-0000-0000-000000000022'::uuid,'78400000-0000-0000-0000-000000000023'::uuid];
  refs text[] := ARRAY['EXACT','EXACT','FUZZ-REFX','FUZZ-REF-2024','CROSS','CROSS',NULL,NULL,NULL,'CONFLICT',NULL,'INVALID','DELETED','DELETED','MATTER-INACTIVE','MATTER-INACTIVE','CLIENT-DELETED','CLIENT-DELETED',NULL,'COLLISION','COLLISION',NULL,'REFRESH-TYPE'];
  cited text[] := ARRAY['EXACT',NULL,'FUZZ-REF',NULL,'CROSS',NULL,'MISSING',NULL,NULL,NULL,NULL,NULL,'DELETED',NULL,'MATTER-INACTIVE',NULL,'CLIENT-DELETED',NULL,'COLLISION',NULL,NULL,'REFRESH-TYPE',NULL];
BEGIN
  -- The fixture follows the normal asset → validated provenance run → binding
  -- → candidate → effective projection lifecycle; it needs no superuser mode.
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES ('00000000-0000-0000-0000-000000000000',actor,'authenticated','authenticated','placement@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES (org,'Placement fixture',actor);
  -- Organisation creation performs the canonical legacy-to-membership
  -- dual-write. Reuse that active admin generation instead of duplicating it.
  SELECT id INTO membership FROM public.organisation_memberships
  WHERE org_id=org AND user_id=actor AND role='admin' AND state='active' AND generation=1;
  UPDATE public.organisations SET owner_membership_id=membership WHERE id=org;
  INSERT INTO public.clients(id,org_id,name) VALUES (client,org,'Client'), (inactive_client,org,'Inactive client');
  INSERT INTO public.matters(id,org_id,client_id,title,financial_year) VALUES
    (matter,org,client,'Matter','2024-25'),
    (other_matter,org,client,'Other','2025-26'),
    (inactive_client_matter,org,inactive_client,'Inactive client matter','2026-27');
  FOR i IN 1..array_length(docs,1) LOOP
    src:=docs[i]; ver:=('78500000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid; asset:=('78600000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
    INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by) VALUES(src,org,CASE WHEN i IN (6,16) THEN other_matter WHEN i=18 THEN inactive_client_matter ELSE matter END,'orgs/'||org::text||'/documents/'||src::text||'/original.pdf',actor);
    INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by) VALUES(asset,org,'documents','orgs/'||org::text||'/assets/'||asset::text||'/original.pdf',lpad(i::text,64,'a'),1,'application/pdf','available',now(),1,actor);
    INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by) VALUES(ver,org,src,asset,1,'fixture.pdf',1,'valid','current',now(),now(),actor);
    UPDATE public.documents SET current_version_id=ver WHERE id=src;
    source_run:=gen_random_uuid(); INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at,completed_at) VALUES(source_run,org,asset,'fixture.run.'||i,'fixture.run.'||i,'ai_extraction','validated','succeeded','fixture','fixture','fixture','fixture','fixture','fixture','fixture',now(),now());
    binding:=gen_random_uuid(); INSERT INTO public.document_version_analysis_bindings(id,org_id,document_version_id,source_analysis_run_id,binding_reason,created_by) VALUES(binding,org,ver,source_run,'processing_ai_extraction',actor);
    source_candidate:=gen_random_uuid(); INSERT INTO public.source_field_candidates(id,org_id,source_analysis_run_id,asset_id,semantic_candidate_key,field_path,value_type,normalized_value,page_number,evidence_page_count,quotation,confidence,validation_state) VALUES(source_candidate,org,source_run,asset,'type','document.type','code','"SCN"',1,1,'fixture',.9,'eligible');
    candidate:=gen_random_uuid(); INSERT INTO public.document_field_candidates(id,org_id,document_id,document_version_id,document_version_analysis_binding_id,source_field_candidate_id,semantic_candidate_key,field_path,value_type,normalized_value,page_number,evidence_page_count,quotation,confidence,validation_state) VALUES(candidate,org,src,ver,binding,source_candidate,'type','document.type','code','"SCN"',1,1,'fixture',.9,'eligible');
    -- The normal document-candidate trigger recomputes the automatic effective
    -- projection after every insert; do not duplicate that authoritative row.
    IF refs[i] IS NOT NULL THEN source_candidate:=gen_random_uuid(); INSERT INTO public.source_field_candidates(id,org_id,source_analysis_run_id,asset_id,semantic_candidate_key,field_path,value_type,normalized_value,page_number,evidence_page_count,quotation,confidence,validation_state) VALUES(source_candidate,org,source_run,asset,'ref','document.reference_number','code',to_jsonb(refs[i]),1,1,'fixture',.9,'eligible'); candidate:=gen_random_uuid(); INSERT INTO public.document_field_candidates(id,org_id,document_id,document_version_id,document_version_analysis_binding_id,source_field_candidate_id,semantic_candidate_key,field_path,value_type,normalized_value,page_number,evidence_page_count,quotation,confidence,validation_state) VALUES(candidate,org,src,ver,binding,source_candidate,'ref','document.reference_number','code',to_jsonb(refs[i]),1,1,'fixture',.9,'eligible'); END IF;
    IF cited[i] IS NOT NULL THEN source_candidate:=gen_random_uuid(); INSERT INTO public.source_field_candidates(id,org_id,source_analysis_run_id,asset_id,semantic_candidate_key,field_path,value_type,normalized_value,page_number,evidence_page_count,quotation,confidence,validation_state) VALUES(source_candidate,org,source_run,asset,'cited','document.referenced_document_number','code',to_jsonb(cited[i]),1,1,'fixture',.9,'eligible'); candidate:=gen_random_uuid(); INSERT INTO public.document_field_candidates(id,org_id,document_id,document_version_id,document_version_analysis_binding_id,source_field_candidate_id,semantic_candidate_key,field_path,value_type,normalized_value,page_number,evidence_page_count,quotation,confidence,validation_state) VALUES(candidate,org,src,ver,binding,source_candidate,'cited','document.referenced_document_number','code',to_jsonb(cited[i]),1,1,'fixture',.9,'eligible'); END IF;
  END LOOP;
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[1],(SELECT current_version_id FROM public.documents WHERE id=docs[1]),actor); IF result.link_count<>1 OR NOT EXISTS(SELECT 1 FROM public.document_links WHERE from_doc_id=docs[1] AND to_doc_id=docs[2] AND status='confirmed') THEN RAISE EXCEPTION 'exact failed'; END IF;
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[3],(SELECT current_version_id FROM public.documents WHERE id=docs[3]),actor); IF result.link_count<>1 OR result.notification_count<>1 THEN RAISE EXCEPTION 'fuzzy failed'; END IF;
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[3],(SELECT current_version_id FROM public.documents WHERE id=docs[3]),actor); IF result.link_count<>0 OR result.notification_count<>0 OR (SELECT count(*) FROM public.notifications WHERE entity_id=docs[3])<>1 THEN RAISE EXCEPTION 'replay duplicated fuzzy effects'; END IF;
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[5],(SELECT current_version_id FROM public.documents WHERE id=docs[5]),actor); IF result.notification_count<>1 OR EXISTS(SELECT 1 FROM public.document_links WHERE from_doc_id=docs[5]) OR (SELECT status FROM public.documents WHERE id=docs[5])<>'needs_review' THEN RAISE EXCEPTION 'cross-matter policy failed'; END IF;
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[7],(SELECT current_version_id FROM public.documents WHERE id=docs[7]),actor); IF NOT EXISTS(SELECT 1 FROM public.document_links WHERE from_doc_id=docs[7] AND to_doc_id IS NULL AND pending_ref_number='MISSING') THEN RAISE EXCEPTION 'pending failed'; END IF;
  SELECT id INTO candidate FROM public.document_field_candidates WHERE document_id=docs[7] AND field_path='document.referenced_document_number';
  PERFORM public.record_document_field_decision(candidate,'cleared',NULL,'fixture clear',actor,'fixture.clear.7');
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[7],(SELECT current_version_id FROM public.documents WHERE id=docs[7]),actor);
  IF result.code<>'no_effective_references' OR result.link_count<>0 THEN RAISE EXCEPTION 'cleared cited reference did not fail closed'; END IF;
  SELECT id INTO candidate FROM public.document_field_candidates WHERE document_id=docs[3] AND field_path='document.referenced_document_number';
  PERFORM public.record_document_field_decision(candidate,'rejected',NULL,'fixture reject',actor,'fixture.reject.3');
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[3],(SELECT current_version_id FROM public.documents WHERE id=docs[3]),actor);
  IF result.code<>'no_effective_references' OR result.link_count<>0 OR result.notification_count<>0 THEN RAISE EXCEPTION 'rejected cited reference did not fail closed'; END IF;
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[8],(SELECT current_version_id FROM public.documents WHERE id=docs[8]),actor); IF result.code<>'no_effective_references' THEN RAISE EXCEPTION 'missing/cleared/rejected effective values did not fail closed'; END IF;
  -- Conflicting and invalid relationship candidates remain immutable audit
  -- evidence, but their normal effective-metadata recomputes must expose no
  -- relationship value to placement. These are real source and document
  -- candidates, rather than a forged effective-projection row.
  SELECT source_analysis_run_id, id INTO source_run, binding FROM public.document_version_analysis_bindings WHERE document_id=docs[9];
  SELECT asset_id INTO asset FROM public.document_versions WHERE document_id=docs[9] AND state='current';
  source_candidate:=gen_random_uuid(); INSERT INTO public.source_field_candidates(id,org_id,source_analysis_run_id,asset_id,semantic_candidate_key,field_path,value_type,normalized_value,page_number,evidence_page_count,quotation,confidence,validation_state) VALUES(source_candidate,org,source_run,asset,'conflict_cited','document.referenced_document_number','code','"CONFLICT"',1,1,'fixture',.9,'conflicting');
  candidate:=gen_random_uuid(); INSERT INTO public.document_field_candidates(id,org_id,document_id,document_version_id,document_version_analysis_binding_id,source_field_candidate_id,semantic_candidate_key,field_path,value_type,normalized_value,page_number,evidence_page_count,quotation,confidence,validation_state) VALUES(candidate,org,docs[9],(SELECT current_version_id FROM public.documents WHERE id=docs[9]),binding,source_candidate,'conflict_cited','document.referenced_document_number','code','"CONFLICT"',1,1,'fixture',.9,'conflicting');
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[9],(SELECT current_version_id FROM public.documents WHERE id=docs[9]),actor);
  IF result.code<>'no_effective_references' OR result.link_count<>0 OR result.notification_count<>0 OR EXISTS(SELECT 1 FROM public.document_links WHERE from_doc_id=docs[9]) OR EXISTS(SELECT 1 FROM public.document_relationship_placement_effects WHERE document_id=docs[9]) THEN RAISE EXCEPTION 'conflicting relationship candidate did not fail closed'; END IF;
  SELECT source_analysis_run_id, id INTO source_run, binding FROM public.document_version_analysis_bindings WHERE document_id=docs[11];
  SELECT asset_id INTO asset FROM public.document_versions WHERE document_id=docs[11] AND state='current';
  source_candidate:=gen_random_uuid(); INSERT INTO public.source_field_candidates(id,org_id,source_analysis_run_id,asset_id,semantic_candidate_key,field_path,value_type,normalized_value,page_number,evidence_page_count,quotation,confidence,validation_state,validation_error_codes) VALUES(source_candidate,org,source_run,asset,'invalid_cited','document.referenced_document_number','code','"INVALID"',1,1,'fixture',.9,'invalid',ARRAY['invalid_reference']);
  candidate:=gen_random_uuid(); INSERT INTO public.document_field_candidates(id,org_id,document_id,document_version_id,document_version_analysis_binding_id,source_field_candidate_id,semantic_candidate_key,field_path,value_type,normalized_value,page_number,evidence_page_count,quotation,confidence,validation_state,validation_error_codes) VALUES(candidate,org,docs[11],(SELECT current_version_id FROM public.documents WHERE id=docs[11]),binding,source_candidate,'invalid_cited','document.referenced_document_number','code','"INVALID"',1,1,'fixture',.9,'invalid',ARRAY['invalid_reference']);
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[11],(SELECT current_version_id FROM public.documents WHERE id=docs[11]),actor);
  IF result.code<>'no_effective_references' OR result.link_count<>0 OR result.notification_count<>0 OR EXISTS(SELECT 1 FROM public.document_links WHERE from_doc_id=docs[11]) OR EXISTS(SELECT 1 FROM public.document_relationship_placement_effects WHERE document_id=docs[11]) THEN RAISE EXCEPTION 'invalid relationship candidate did not fail closed'; END IF;
  -- Move each target through its ordinary persisted lifecycle state before
  -- placement. It must not be selected for an exact/fuzzy/cross-matter
  -- effect; the ordinary unmatched-reference policy may safely add one
  -- source-side pending link without notification, ledger, or review change.
  UPDATE public.documents SET deleted_at=now(), record_state='trashed', trashed_at=now(), trashed_by=actor, trashed_reason='fixture lifecycle exclusion' WHERE id=docs[14];
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[13],(SELECT current_version_id FROM public.documents WHERE id=docs[13]),actor);
  IF result.link_count<>1 OR result.notification_count<>0
     OR (SELECT count(*) FROM public.document_links WHERE from_doc_id=docs[13] AND to_doc_id IS NULL AND status='pending' AND match_method='pending' AND pending_ref_number='DELETED')<>1
     OR EXISTS(SELECT 1 FROM public.document_links WHERE from_doc_id=docs[13] AND to_doc_id=docs[14])
     OR EXISTS(SELECT 1 FROM public.document_relationship_placement_effects WHERE document_id=docs[13])
     OR (SELECT status FROM public.documents WHERE id=docs[13])<>'uploaded' THEN RAISE EXCEPTION 'deleted or trashed target was selected outside the safe pending policy'; END IF;
  UPDATE public.matters SET status='closed' WHERE id=other_matter;
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[15],(SELECT current_version_id FROM public.documents WHERE id=docs[15]),actor);
  IF result.link_count<>1 OR result.notification_count<>0
     OR (SELECT count(*) FROM public.document_links WHERE from_doc_id=docs[15] AND to_doc_id IS NULL AND status='pending' AND match_method='pending' AND pending_ref_number='MATTER-INACTIVE')<>1
     OR EXISTS(SELECT 1 FROM public.document_links WHERE from_doc_id=docs[15] AND to_doc_id=docs[16])
     OR EXISTS(SELECT 1 FROM public.document_relationship_placement_effects WHERE document_id=docs[15])
     OR (SELECT status FROM public.documents WHERE id=docs[15])<>'uploaded' THEN RAISE EXCEPTION 'inactive target matter was selected outside the safe pending policy'; END IF;
  UPDATE public.clients SET deleted_at=now() WHERE id=inactive_client;
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[17],(SELECT current_version_id FROM public.documents WHERE id=docs[17]),actor);
  IF result.link_count<>1 OR result.notification_count<>0
     OR (SELECT count(*) FROM public.document_links WHERE from_doc_id=docs[17] AND to_doc_id IS NULL AND status='pending' AND match_method='pending' AND pending_ref_number='CLIENT-DELETED')<>1
     OR EXISTS(SELECT 1 FROM public.document_links WHERE from_doc_id=docs[17] AND to_doc_id=docs[18])
     OR EXISTS(SELECT 1 FROM public.document_relationship_placement_effects WHERE document_id=docs[17])
     OR (SELECT status FROM public.documents WHERE id=docs[17])<>'uploaded' THEN RAISE EXCEPTION 'deleted target client was selected outside the safe pending policy'; END IF;
  -- Two current same-matter exact references are never confirmation-safe. The
  -- approved fallback is one fuzzy pending suggestion and its replay ledger.
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[19],(SELECT current_version_id FROM public.documents WHERE id=docs[19]),actor);
  IF result.code<>'placed' OR result.link_count<>1 OR result.notification_count<>1
     OR (SELECT count(*) FROM public.document_links WHERE from_doc_id=docs[19] AND status='confirmed' AND match_method='exact_reference')<>0
     OR (SELECT count(*) FROM public.document_links WHERE from_doc_id=docs[19] AND status='pending' AND match_method='fuzzy_reference')<>1
     OR (SELECT count(*) FROM public.notifications WHERE entity_id=docs[19])<>1
     OR (SELECT count(*) FROM public.document_relationship_placement_effects WHERE document_id=docs[19] AND effect_key LIKE 'fuzzy:COLLISION:%')<>1 THEN
    RAISE EXCEPTION 'exact-reference collision was not reduced to one fuzzy pending suggestion';
  END IF;
  -- This single-session case cannot simulate a separate-session race. It does
  -- prove that the command uses the refreshed, current effective target type
  -- when it makes a post-lock exact decision.
  SELECT id INTO candidate FROM public.document_field_candidates WHERE document_id=docs[22] AND field_path='document.type';
  PERFORM public.record_document_field_decision(candidate,'corrected','"APL-01"','fixture source type refresh',actor,'fixture.type-refresh.source');
  SELECT id INTO candidate FROM public.document_field_candidates WHERE document_id=docs[23] AND field_path='document.type';
  PERFORM public.record_document_field_decision(candidate,'corrected','"OIO"','fixture target type refresh',actor,'fixture.type-refresh.target');
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[22],(SELECT current_version_id FROM public.documents WHERE id=docs[22]),actor);
  IF result.code<>'placed' OR result.link_count<>1
     OR NOT EXISTS(SELECT 1 FROM public.document_links WHERE from_doc_id=docs[22] AND to_doc_id=docs[23] AND status='confirmed' AND match_method='exact_reference' AND link_type='challenges') THEN
    RAISE EXCEPTION 'post-lock target type was not refreshed for exact placement';
  END IF;
  -- Exercise the stale-writer fence through a real same-document replacement,
  -- not a forged current-version pointer. The document/version lifecycle
  -- constraints are deferrable specifically for this atomic transition.
  SET CONSTRAINTS ALL DEFERRED;
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
  VALUES ('78600000-0000-0000-0000-000000000099',org,'documents','orgs/'||org::text||'/assets/78600000-0000-0000-0000-000000000099/original.pdf',lpad('99',64,'a'),1,'application/pdf','available',now(),1,actor);
  UPDATE public.document_versions SET state='superseded',superseded_at=now()
  WHERE id=(SELECT current_version_id FROM public.documents WHERE id=docs[1]);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
  VALUES ('78500000-0000-0000-0000-000000000099',org,docs[1],'78600000-0000-0000-0000-000000000099',2,'replacement.pdf',1,'valid','current',now(),now(),actor);
  UPDATE public.documents SET current_version_id='78500000-0000-0000-0000-000000000099' WHERE id=docs[1];
  SET CONSTRAINTS ALL IMMEDIATE;
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[1],'78500000-0000-0000-0000-000000000001',actor);
  IF result.code<>'identity_mismatch' THEN RAISE EXCEPTION 'stale version accepted'; END IF;
  -- Every non-null forged identity dimension fails before any placement write.
  SELECT * INTO result FROM public.place_document_processing_relationships('78000000-0000-0000-0000-000000000099',matter,docs[2],(SELECT current_version_id FROM public.documents WHERE id=docs[2]),actor);
  IF result.code<>'identity_mismatch' THEN RAISE EXCEPTION 'forged organisation accepted'; END IF;
  SELECT * INTO result FROM public.place_document_processing_relationships(org,'78300000-0000-0000-0000-000000000099',docs[2],(SELECT current_version_id FROM public.documents WHERE id=docs[2]),actor);
  IF result.code<>'identity_mismatch' THEN RAISE EXCEPTION 'forged matter accepted'; END IF;
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,'78400000-0000-0000-0000-000000000099',(SELECT current_version_id FROM public.documents WHERE id=docs[2]),actor);
  IF result.code<>'identity_mismatch' THEN RAISE EXCEPTION 'forged document accepted'; END IF;
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[2],'78500000-0000-0000-0000-000000000098',actor);
  IF result.code<>'identity_mismatch' THEN RAISE EXCEPTION 'forged version accepted'; END IF;
  SELECT * INTO result FROM public.place_document_processing_relationships(org,matter,docs[2],(SELECT current_version_id FROM public.documents WHERE id=docs[2]),'78100000-0000-0000-0000-000000000099');
  IF result.code<>'identity_mismatch' THEN RAISE EXCEPTION 'forged uploader accepted'; END IF;
  -- Static source checks complement the concrete single-session collision and
  -- lifecycle cases above; this DO block does not claim to emulate two DB
  -- sessions (the paired local-Supabase harness covers the busy-target path). The
  -- command must follow provenance's source version -> document ->
  -- matter/client order, lock the complete same-matter target set with NOWAIT,
  -- and return no effect rather than wait while it holds the matter fence.
  SELECT pg_get_functiondef('public.place_document_processing_relationships(uuid,uuid,uuid,uuid,uuid)'::regprocedure) INTO definition; IF definition ~ 'raw_metadata|progression_inference|current_relationship_reference_exists_in_other_matter' OR definition !~ 'Lock every active, non-deleted current-version document' OR definition !~ 'document.deleted_at IS NULL' OR definition !~ 'post-lock projection' OR definition !~ 'FOR UPDATE NOWAIT' OR definition !~ 'FOR UPDATE OF effective NOWAIT' OR definition !~ 'target_snapshot_busy' OR definition !~ 'cross-matter target changed' OR definition !~ 'pg_advisory_xact_lock' OR strpos(definition,'SELECT * INTO source_version') >= strpos(definition,'SELECT document.* INTO source_document') OR strpos(definition,'SELECT document.* INTO source_document') >= strpos(definition,'FOR UPDATE OF matter, client') OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.document_relationship_placement_effects'::regclass AND contype='u') THEN RAISE EXCEPTION 'typed current-version, lifecycle, lock-order, or NOWAIT target fence missing'; END IF;
  IF has_function_privilege('authenticated','public.place_document_processing_relationships(uuid,uuid,uuid,uuid,uuid)','EXECUTE')
     OR has_table_privilege('authenticated','public.document_relationship_placement_effects','SELECT')
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.document_relationship_placement_effects'::regclass) THEN
    RAISE EXCEPTION 'browser authority or placement ledger RLS leaked';
  END IF;
END $fixture$;
