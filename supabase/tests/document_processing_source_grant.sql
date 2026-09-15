-- Rollback-only disposable local SQL authority and lifecycle acceptance.
BEGIN;
DO $test$
DECLARE
  org uuid := '16600000-0000-4000-8000-000000000001';
  actor uuid := '16600000-0000-4000-8000-000000000002';
  client uuid := '16600000-0000-4000-8000-000000000003';
  matter uuid := '16600000-0000-4000-8000-000000000004';
  doc uuid := '16600000-0000-4000-8000-000000000005';
  asset uuid := '16600000-0000-4000-8000-000000000006';
  ver uuid := '16600000-0000-4000-8000-000000000007';
  run_id uuid := '16600000-0000-4000-8000-000000000008';
  lease uuid := '16600000-0000-4000-8000-000000000009';
  marked_run uuid := '16600000-0000-4000-8000-000000000011';
  marked_lease uuid := '16600000-0000-4000-8000-000000000012';
  source_run uuid;
  source_lease uuid;
  marked_source uuid;
  marked_source_lease uuid;
  result record;
  denied boolean := false;
BEGIN
  IF has_function_privilege('anon','public.grant_current_document_processing_source(uuid,uuid)','EXECUTE')
    OR has_function_privilege('authenticated','public.grant_current_document_processing_source(uuid,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.begin_current_document_processing_ai_extraction(uuid,uuid,text,text,text,text,text,text,text)','EXECUTE')
    OR has_function_privilege('authenticated','public.begin_current_document_processing_ai_extraction(uuid,uuid,text,text,text,text,text,text,text)','EXECUTE')
    OR NOT has_function_privilege('service_role','public.grant_current_document_processing_source(uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'processing-source privilege boundary failed';
  END IF;
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000',actor,'authenticated','authenticated','source-grant@example.test','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES (org,'Source grant fixture',actor);
  INSERT INTO public.clients(id,org_id,name) VALUES (client,org,'Fixture client');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES (matter,org,client,'Fixture matter');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by) VALUES (doc,org,matter,'legacy/fixture.pdf',actor);
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
    VALUES (asset,org,'documents','orgs/'||org::text||'/assets/'||asset::text||'/original.pdf',repeat('a',64),99,'application/pdf','available',now(),2,actor);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
    VALUES (ver,org,doc,asset,1,'fixture.pdf',2,'valid','current',now(),now(),actor);
  UPDATE public.documents SET current_version_id=ver WHERE id=doc;
  INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
    VALUES (run_id,org,doc,ver,'full','fixture.source.grant','running','extracting',now(),lease,now()+interval '10 minutes',now());

  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.grant_current_document_processing_source(run_id,lease);
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'authenticated direct source grant was not denied'; END IF;
  SELECT * INTO result FROM public.grant_current_document_processing_source(gen_random_uuid(),lease);
  IF result.code<>'stale_lease' OR result.object_key IS NOT NULL THEN RAISE EXCEPTION 'foreign processing run leaked source'; END IF;

  SELECT * INTO result FROM public.grant_current_document_processing_source(run_id,gen_random_uuid());
  IF result.code<>'stale_lease' OR result.object_key IS NOT NULL OR result.expected_sha256 IS NOT NULL THEN RAISE EXCEPTION 'forged lease leaked source'; END IF;
  SELECT * INTO result FROM public.grant_current_document_processing_source(run_id,lease);
  IF result.code<>'ready' OR result.document_version_id<>ver OR result.expected_sha256<>repeat('a',64) OR result.expected_bytes<>99 THEN RAISE EXCEPTION 'live authoritative source was not granted'; END IF;

  UPDATE public.documents SET record_state='trashed',deleted_at=now(),trashed_at=now() WHERE id=doc;
  SELECT * INTO result FROM public.grant_current_document_processing_source(run_id,lease);
  IF result.code<>'source_unavailable' OR result.object_key IS NOT NULL THEN RAISE EXCEPTION 'Trash source was granted'; END IF;
  SELECT * INTO result FROM public.begin_current_document_processing_ai_extraction(run_id,lease,'vertex-ai','gemini-2.5-flash','fixture-model','fixture-prompt','fixture-schema','fixture-catalogue','fixture-normalizer');
  IF result.code<>'source_unavailable' OR result.source_analysis_run_id IS NOT NULL THEN RAISE EXCEPTION 'Trash crossed provenance begin'; END IF;
  UPDATE public.documents SET record_state='active',deleted_at=NULL,trashed_at=NULL WHERE id=doc;

  UPDATE public.matters SET record_state='trashed',deleted_at=now() WHERE id=matter;
  SELECT * INTO result FROM public.grant_current_document_processing_source(run_id,lease);
  IF result.code<>'source_unavailable' THEN RAISE EXCEPTION 'trashed matter was granted'; END IF;
  UPDATE public.matters SET record_state='active',deleted_at=NULL WHERE id=matter;
  UPDATE public.clients SET record_state='trashed',deleted_at=now() WHERE id=client;
  SELECT * INTO result FROM public.grant_current_document_processing_source(run_id,lease);
  IF result.code<>'source_unavailable' THEN RAISE EXCEPTION 'trashed client was granted'; END IF;
  UPDATE public.clients SET record_state='active',deleted_at=NULL WHERE id=client;
  UPDATE public.documents SET current_version_id=NULL WHERE id=doc;
  SELECT * INTO result FROM public.grant_current_document_processing_source(run_id,lease);
  IF result.code<>'source_unavailable' THEN RAISE EXCEPTION 'retired current version was granted'; END IF;
  UPDATE public.documents SET current_version_id=ver WHERE id=doc;

  UPDATE public.matters SET work_state='closed' WHERE id=matter;
  SELECT * INTO result FROM public.grant_current_document_processing_source(run_id,lease);
  IF result.code<>'source_unavailable' THEN RAISE EXCEPTION 'closed matter work was granted'; END IF;
  UPDATE public.matters SET work_state='active' WHERE id=matter;

  UPDATE public.file_assets SET availability='failed',validated_at=NULL,failed_at=now() WHERE id=asset;
  SELECT * INTO result FROM public.grant_current_document_processing_source(run_id,lease);
  IF result.code<>'source_unavailable' THEN RAISE EXCEPTION 'unavailable asset was granted'; END IF;
  UPDATE public.file_assets SET availability='available',validated_at=now(),failed_at=NULL WHERE id=asset;
  UPDATE public.document_versions SET page_count=3 WHERE id=ver;
  SELECT * INTO result FROM public.grant_current_document_processing_source(run_id,lease);
  IF result.code<>'source_unavailable' THEN RAISE EXCEPTION 'mismatched validated page count was granted'; END IF;
  UPDATE public.document_versions SET page_count=2 WHERE id=ver;

  SELECT * INTO result FROM public.begin_current_document_processing_ai_extraction(run_id,lease,'vertex-ai','gemini-2.5-flash','fixture-model','fixture-prompt','fixture-schema','fixture-catalogue','fixture-normalizer');
  IF result.code<>'claimed' OR result.page_count<>2 THEN RAISE EXCEPTION 'authoritative provenance begin failed'; END IF;
  source_run:=result.source_analysis_run_id; source_lease:=result.source_analysis_lease_token;
  denied:=false;
  BEGIN
    INSERT INTO public.document_version_analysis_bindings(org_id,document_id,document_version_id,source_analysis_run_id,binding_reason)
      VALUES(org,doc,ver,source_run,'no_call_processing_source');
  EXCEPTION WHEN raise_exception THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'running AI source forged a no-call lineage binding'; END IF;
  SELECT * INTO result FROM public.begin_current_document_processing_ai_extraction(run_id,lease,'vertex-ai','gemini-2.5-flash','fixture-model','fixture-prompt','fixture-schema','fixture-catalogue','fixture-normalizer');
  IF result.code<>'already_running' OR (SELECT count(*) FROM public.source_analysis_attempts WHERE source_analysis_run_id=result.source_analysis_run_id)<>1 THEN
    RAISE EXCEPTION 'provenance begin replay created duplicate work';
  END IF;
  UPDATE public.document_processing_runs SET lease_expires_at=now()-interval '1 second' WHERE id=run_id;
  SELECT * INTO result FROM public.grant_current_document_processing_source(run_id,lease);
  IF result.code<>'stale_lease' OR result.object_key IS NOT NULL THEN RAISE EXCEPTION 'expired lease leaked source'; END IF;
  UPDATE public.document_processing_runs SET lease_expires_at=now()+interval '10 minutes' WHERE id=run_id;
  INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
    VALUES (marked_run,org,doc,ver,'full','fixture.source.marked','running','extracting',now(),marked_lease,now()+interval '10 minutes',now());
  SELECT * INTO result FROM public.begin_current_document_processing_ai_extraction(marked_run,marked_lease,'vertex-ai','gemini-2.5-flash','fixture-model','fixture-prompt','fixture-schema','fixture-catalogue','fixture-normalizer');
  IF result.code<>'claimed' THEN RAISE EXCEPTION 'second provenance claim failed'; END IF;
  marked_source:=result.source_analysis_run_id; marked_source_lease:=result.source_analysis_lease_token;
  SELECT * INTO result FROM public.mark_current_document_processing_ai_provider_call(marked_run,marked_lease,marked_source,marked_source_lease);
  IF result.code<>'ready' OR NOT EXISTS(SELECT 1 FROM public.source_analysis_attempts WHERE source_analysis_run_id=marked_source AND provider_call_started_at IS NOT NULL) THEN
    RAISE EXCEPTION 'provider-call marker was not durable'; END IF;
  SELECT * INTO result FROM public.mark_current_document_processing_ai_provider_call(marked_run,marked_lease,marked_source,marked_source_lease);
  IF result.code<>'unsafe_to_call' THEN RAISE EXCEPTION 'marker replay permitted duplicate provider call'; END IF;
  denied:=false;
  BEGIN
    UPDATE public.source_analysis_attempts SET provider_call_started_at=NULL
      WHERE source_analysis_run_id=marked_source AND attempt_number=1;
  EXCEPTION WHEN raise_exception THEN denied:=true;
  END;
  IF NOT denied OR NOT EXISTS(SELECT 1 FROM public.source_analysis_attempts
      WHERE source_analysis_run_id=marked_source AND attempt_number=1 AND provider_call_started_at IS NOT NULL) THEN
    RAISE EXCEPTION 'possibly-called marker could be erased'; END IF;
  UPDATE public.source_analysis_runs SET lease_expires_at=now()-interval '1 second' WHERE id=marked_source;
  denied:=false;
  BEGIN
    SELECT * INTO result FROM public.begin_current_document_processing_ai_extraction(marked_run,marked_lease,
      'vertex-ai','gemini-2.5-flash','fixture-model','fixture-prompt','fixture-schema','fixture-catalogue','fixture-normalizer');
  EXCEPTION WHEN raise_exception THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'wrapper replayed expired possibly-called source'; END IF;
  denied:=false;
  BEGIN
    SELECT * INTO result FROM public.begin_document_processing_ai_extraction(marked_run,marked_lease,
      'vertex-ai','gemini-2.5-flash','fixture-model','fixture-prompt','fixture-schema','fixture-catalogue','fixture-normalizer',
      doc,ver,matter,org,'documents','orgs/'||org::text||'/assets/'||asset::text||'/original.pdf',actor);
  EXCEPTION WHEN raise_exception THEN denied:=true;
  END;
  IF NOT denied OR (SELECT count(*) FROM public.source_analysis_attempts WHERE source_analysis_run_id=marked_source)<>1
    OR (SELECT analysis_state FROM public.source_analysis_runs WHERE id=marked_source)<>'running'
    OR (SELECT state FROM public.source_analysis_attempts WHERE source_analysis_run_id=marked_source AND attempt_number=1)<>'running' THEN
    RAISE EXCEPTION 'legacy begin replayed or altered possibly-called source'; END IF;
  INSERT INTO public.trash_operations(id,org_id,root_resource_type,root_resource_id,root_document_id)
    VALUES ('16600000-0000-4000-8000-000000000010',org,'document',doc,doc);
  INSERT INTO public.resource_trash_memberships(org_id,operation_id,resource_type,resource_id,document_id,cause)
    VALUES (org,'16600000-0000-4000-8000-000000000010','document',doc,doc,'direct');
  SELECT * INTO result FROM public.grant_current_document_processing_source(run_id,lease);
  IF result.code<>'source_unavailable' THEN RAISE EXCEPTION 'active Trash membership was granted'; END IF;
  UPDATE public.document_processing_runs SET lease_expires_at=now()-interval '1 second' WHERE id=marked_run;
  SELECT * INTO result FROM public.cancel_uncalled_document_processing_ai_extraction(marked_run,marked_lease,marked_source,marked_source_lease);
  IF result.code<>'unsafe_to_cancel' OR (SELECT analysis_state FROM public.source_analysis_runs WHERE id=marked_source)<>'running' THEN
    RAISE EXCEPTION 'possibly called provider run was falsely cancelled'; END IF;
  SELECT * INTO result FROM public.cancel_uncalled_document_processing_ai_extraction(run_id,gen_random_uuid(),source_run,source_lease);
  IF result.code<>'stale_lease' THEN RAISE EXCEPTION 'forged processing lease cancelled source'; END IF;
  UPDATE public.document_processing_runs SET lease_token=gen_random_uuid() WHERE id=run_id;
  SELECT * INTO result FROM public.cancel_uncalled_document_processing_ai_extraction(run_id,lease,source_run,source_lease);
  IF result.code<>'stale_lease' OR (SELECT analysis_state FROM public.source_analysis_runs WHERE id=source_run)<>'running' THEN
    RAISE EXCEPTION 'newer outer lease allowed historical cleanup'; END IF;
  UPDATE public.document_processing_runs SET lease_token=lease WHERE id=run_id;
  UPDATE public.source_analysis_runs SET lease_token=gen_random_uuid() WHERE id=source_run;
  SELECT * INTO result FROM public.cancel_uncalled_document_processing_ai_extraction(run_id,lease,source_run,source_lease);
  IF result.code<>'identity_invalid' OR (SELECT analysis_state FROM public.source_analysis_runs WHERE id=source_run)<>'running' THEN
    RAISE EXCEPTION 'newer nested lease allowed historical cleanup'; END IF;
  UPDATE public.source_analysis_runs SET lease_token=source_lease,lease_expires_at=now()-interval '1 second' WHERE id=source_run;
  UPDATE public.document_processing_runs SET lease_expires_at=now()-interval '1 second' WHERE id=run_id;
  SELECT * INTO result FROM public.cancel_uncalled_document_processing_ai_extraction(run_id,lease,source_run,source_lease);
  IF result.code<>'cancelled'
    OR (SELECT analysis_state FROM public.source_analysis_runs WHERE id=source_run)<>'provider_failed'
    OR (SELECT safe_error_code FROM public.source_analysis_runs WHERE id=source_run)<>'source_revoked_before_model'
    OR (SELECT state FROM public.source_analysis_attempts WHERE source_analysis_run_id=source_run AND attempt_number=1)<>'provider_failed'
    OR EXISTS(SELECT 1 FROM public.source_analysis_attempts WHERE source_analysis_run_id=source_run
      AND (provider_call_started_at IS NOT NULL OR input_tokens IS NOT NULL OR output_tokens IS NOT NULL OR usage_recorded_at IS NOT NULL))
    OR EXISTS(SELECT 1 FROM public.source_field_candidates WHERE source_analysis_run_id=source_run)
    OR (SELECT state FROM public.document_processing_runs WHERE id=run_id)<>'cancelled' THEN
    RAISE EXCEPTION 'no-call cancellation did not terminalize both rows without provider usage/content'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.document_version_analysis_bindings binding
      WHERE binding.org_id=org AND binding.document_id=doc AND binding.document_version_id=ver
        AND binding.source_analysis_run_id=source_run AND binding.binding_reason='no_call_processing_source')
    OR EXISTS(SELECT 1 FROM public.source_analysis_runs run WHERE run.id=source_run AND run.asset_id=asset
      AND NOT EXISTS(SELECT 1 FROM public.document_version_analysis_bindings binding
        WHERE binding.org_id=run.org_id AND binding.source_analysis_run_id=run.id AND binding.document_id=doc)) THEN
    RAISE EXCEPTION 'terminal no-call source remains unbound for Trash ownership'; END IF;
  SELECT * INTO result FROM public.cancel_uncalled_document_processing_ai_extraction(run_id,lease,source_run,source_lease);
  IF result.code<>'already_cancelled' THEN RAISE EXCEPTION 'no-call cancellation replay was not idempotent'; END IF;
  SELECT * INTO result FROM public.finish_document_processing_work(run_id,lease,'no_work');
  IF result.code<>'already_complete' OR (SELECT state FROM public.document_processing_runs WHERE id=run_id)<>'cancelled' THEN
    RAISE EXCEPTION 'outer no-work terminalization failed after nested cancellation'; END IF;
END $test$;
ROLLBACK;
