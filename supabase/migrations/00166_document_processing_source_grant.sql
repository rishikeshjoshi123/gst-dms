BEGIN;

-- A child invocation is not authority to name a Storage object. Only the
-- current, live, validated processing lease may receive this private locator.
CREATE FUNCTION public.grant_current_document_processing_source(
  p_processing_run_id uuid, p_lease_token uuid
) RETURNS TABLE(code text, document_version_id uuid, bucket_id text, object_key text, expected_sha256 text, expected_bytes bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  r public.document_processing_runs%ROWTYPE;
  d public.documents%ROWTYPE;
  v public.document_versions%ROWTYPE;
  a public.file_assets%ROWTYPE;
  m public.matters%ROWTYPE;
  c public.clients%ROWTYPE;
BEGIN
  IF p_processing_run_id IS NULL OR p_lease_token IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::text,NULL::text,NULL::text,NULL::bigint; RETURN;
  END IF;
  SELECT * INTO r FROM public.document_processing_runs WHERE id=p_processing_run_id FOR SHARE;
  IF r.id IS NULL OR r.state<>'running' OR r.lease_token IS DISTINCT FROM p_lease_token
    OR r.lease_expires_at IS NULL OR r.lease_expires_at<=now() OR r.scope<>'full' THEN
    RETURN QUERY SELECT 'stale_lease'::text,NULL::uuid,NULL::text,NULL::text,NULL::text,NULL::bigint; RETURN;
  END IF;
  -- FOR UPDATE on hierarchy rows also fences FK-backed Trash membership
  -- insertion inside the transactional provenance-begin wrapper.
  SELECT * INTO d FROM public.documents WHERE id=r.document_id AND org_id=r.org_id FOR UPDATE;
  SELECT * INTO v FROM public.document_versions WHERE id=r.document_version_id AND org_id=r.org_id FOR SHARE;
  SELECT * INTO a FROM public.file_assets WHERE id=v.asset_id AND org_id=r.org_id FOR SHARE;
  SELECT * INTO m FROM public.matters WHERE id=d.matter_id AND org_id=r.org_id FOR UPDATE;
  SELECT * INTO c FROM public.clients WHERE id=m.client_id AND org_id=r.org_id FOR UPDATE;
  IF d.id IS NULL OR v.id IS NULL OR a.id IS NULL OR m.id IS NULL OR c.id IS NULL
    OR v.document_id IS DISTINCT FROM d.id OR d.current_version_id IS DISTINCT FROM v.id
    OR d.record_state<>'active' OR d.deleted_at IS NOT NULL
    OR m.record_state<>'active' OR m.deleted_at IS NOT NULL OR m.work_state<>'active'
    OR c.record_state<>'active' OR c.deleted_at IS NOT NULL
    OR v.state<>'current' OR v.validation_state<>'valid' OR v.page_count IS NULL
    OR a.availability<>'available' OR a.storage_deleted_at IS NOT NULL
    OR a.detected_mime_type<>'application/pdf' OR a.validated_page_count IS DISTINCT FROM v.page_count
    OR a.bucket_id<>'documents' OR a.object_key IS NULL OR a.object_key=''
    OR a.sha256 IS NULL OR a.sha256 !~ '^[0-9a-f]{64}$' OR a.byte_size IS NULL OR a.byte_size<=0
    OR EXISTS (SELECT 1 FROM public.resource_trash_memberships t
      WHERE t.org_id=r.org_id AND t.state='active' AND t.resource_id IN (d.id,m.id,c.id)) THEN
    RETURN QUERY SELECT 'source_unavailable'::text,NULL::uuid,NULL::text,NULL::text,NULL::text,NULL::bigint; RETURN;
  END IF;
  RETURN QUERY SELECT 'ready'::text,v.id,a.bucket_id,a.object_key,a.sha256,a.byte_size;
END $$;

-- The active hierarchy check and provenance begin share one transaction.
-- The caller cannot supply a stale or forged bucket/path/actor to begin.
CREATE FUNCTION public.begin_current_document_processing_ai_extraction(
  p_processing_run_id uuid, p_processing_lease_token uuid,
  p_provider text, p_model_identifier text, p_model_config_version text,
  p_prompt_version text, p_schema_version text, p_catalogue_version text,
  p_normalizer_version text
) RETURNS TABLE(code text, source_analysis_run_id uuid, source_analysis_lease_token uuid, page_count integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  source_row record;
  r public.document_processing_runs%ROWTYPE;
  d public.documents%ROWTYPE;
  a public.file_assets%ROWTYPE;
BEGIN
  SELECT * INTO source_row FROM public.grant_current_document_processing_source(p_processing_run_id,p_processing_lease_token);
  IF source_row.code IS DISTINCT FROM 'ready' THEN
    RETURN QUERY SELECT source_row.code::text,NULL::uuid,NULL::uuid,NULL::integer; RETURN;
  END IF;
  SELECT * INTO r FROM public.document_processing_runs WHERE id=p_processing_run_id FOR KEY SHARE;
  SELECT * INTO d FROM public.documents WHERE id=r.document_id AND org_id=r.org_id FOR KEY SHARE;
  SELECT * INTO a FROM public.file_assets WHERE id=(SELECT asset_id FROM public.document_versions WHERE id=r.document_version_id) AND org_id=r.org_id FOR KEY SHARE;
  RETURN QUERY SELECT result.code,result.source_analysis_run_id,result.source_analysis_lease_token,result.page_count
    FROM public.begin_document_processing_ai_extraction(
      p_processing_run_id,p_processing_lease_token,p_provider,p_model_identifier,p_model_config_version,
      p_prompt_version,p_schema_version,p_catalogue_version,p_normalizer_version,
      d.id,r.document_version_id,d.matter_id,r.org_id,source_row.bucket_id,source_row.object_key,d.created_by
    ) AS result;
END $$;

-- A claimed AI attempt can be abandoned before Vertex is called. Persist an
-- invocation marker just before the call; cancellation must refuse any attempt
-- for which a paid effect may have begun, even if the provider response is lost.
ALTER TABLE public.source_analysis_attempts ADD COLUMN provider_call_started_at timestamptz;

CREATE FUNCTION public.mark_current_document_processing_ai_provider_call(
  p_processing_run_id uuid, p_processing_lease_token uuid,
  p_source_analysis_run_id uuid, p_source_analysis_lease_token uuid
) RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  source_grant record;
  r public.document_processing_runs%ROWTYPE;
  s public.source_analysis_runs%ROWTYPE;
  attempt public.source_analysis_attempts%ROWTYPE;
BEGIN
  SELECT * INTO source_grant FROM public.grant_current_document_processing_source(p_processing_run_id,p_processing_lease_token);
  IF source_grant.code IS DISTINCT FROM 'ready' THEN
    RETURN QUERY SELECT 'source_unavailable'::text; RETURN;
  END IF;
  SELECT * INTO r FROM public.document_processing_runs WHERE id=p_processing_run_id FOR SHARE;
  SELECT * INTO s FROM public.source_analysis_runs WHERE id=p_source_analysis_run_id AND org_id=r.org_id FOR UPDATE;
  SELECT * INTO attempt FROM public.source_analysis_attempts
    WHERE source_analysis_run_id=s.id AND attempt_number=s.attempt_count FOR UPDATE;
  IF s.id IS NULL OR attempt.id IS NULL OR s.analysis_kind<>'ai_extraction'
    OR s.idempotency_key IS DISTINCT FROM 'ai_extraction.'||r.id::text
    OR s.request_key IS DISTINCT FROM s.idempotency_key
    OR s.asset_id IS DISTINCT FROM (SELECT asset_id FROM public.document_versions WHERE id=source_grant.document_version_id)
    OR s.analysis_state<>'running' OR s.state<>'running'
    OR s.lease_token IS DISTINCT FROM p_source_analysis_lease_token OR s.lease_expires_at<=now()
    OR attempt.state<>'running' OR attempt.provider_call_started_at IS NOT NULL THEN
    RETURN QUERY SELECT 'unsafe_to_call'::text; RETURN;
  END IF;
  UPDATE public.source_analysis_attempts SET provider_call_started_at=now() WHERE id=attempt.id;
  RETURN QUERY SELECT 'ready'::text;
END $$;

CREATE FUNCTION public.cancel_uncalled_document_processing_ai_extraction(
  p_processing_run_id uuid, p_processing_lease_token uuid,
  p_source_analysis_run_id uuid, p_source_analysis_lease_token uuid
) RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  r public.document_processing_runs%ROWTYPE;
  s public.source_analysis_runs%ROWTYPE;
  attempt public.source_analysis_attempts%ROWTYPE;
BEGIN
  IF p_processing_run_id IS NULL OR p_processing_lease_token IS NULL
    OR p_source_analysis_run_id IS NULL OR p_source_analysis_lease_token IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  SELECT * INTO r FROM public.document_processing_runs WHERE id=p_processing_run_id FOR UPDATE;
  IF r.id IS NULL OR r.state<>'running' OR r.lease_token IS DISTINCT FROM p_processing_lease_token
    OR r.lease_expires_at<=now() OR r.scope<>'full' THEN
    RETURN QUERY SELECT 'stale_lease'::text; RETURN;
  END IF;
  SELECT * INTO s FROM public.source_analysis_runs WHERE id=p_source_analysis_run_id AND org_id=r.org_id FOR UPDATE;
  IF s.id IS NULL OR s.analysis_kind<>'ai_extraction'
    OR s.idempotency_key IS DISTINCT FROM 'ai_extraction.'||r.id::text
    OR s.request_key IS DISTINCT FROM s.idempotency_key
    OR s.asset_id IS DISTINCT FROM (SELECT asset_id FROM public.document_versions WHERE id=r.document_version_id AND org_id=r.org_id)
    OR s.lease_token IS DISTINCT FROM p_source_analysis_lease_token THEN
    RETURN QUERY SELECT 'identity_invalid'::text; RETURN;
  END IF;
  IF s.analysis_state='provider_failed' AND s.safe_error_code='source_revoked_before_model' THEN
    RETURN QUERY SELECT 'already_cancelled'::text; RETURN;
  END IF;
  SELECT * INTO attempt FROM public.source_analysis_attempts
    WHERE source_analysis_run_id=s.id AND attempt_number=s.attempt_count FOR UPDATE;
  IF s.analysis_state<>'running' OR s.state<>'running' OR s.lease_expires_at<=now()
    OR attempt.id IS NULL OR attempt.state<>'running' OR attempt.provider_call_started_at IS NOT NULL
    OR attempt.provider_request_id IS NOT NULL OR attempt.provider_operation_id IS NOT NULL
    OR attempt.input_tokens IS NOT NULL OR attempt.output_tokens IS NOT NULL OR attempt.usage_recorded_at IS NOT NULL
    OR s.provider_request_id IS NOT NULL OR s.provider_operation_id IS NOT NULL
    OR s.input_tokens IS NOT NULL OR s.output_tokens IS NOT NULL OR s.usage_recorded_at IS NOT NULL
    OR EXISTS(SELECT 1 FROM public.source_field_candidates WHERE source_analysis_run_id=s.id)
    OR EXISTS(SELECT 1 FROM public.document_version_analysis_bindings WHERE source_analysis_run_id=s.id) THEN
    RETURN QUERY SELECT 'unsafe_to_cancel'::text; RETURN;
  END IF;
  UPDATE public.source_analysis_attempts SET state='provider_failed',failed_at=now(),
    safe_error_category='unknown',safe_error_code='source_revoked_before_model' WHERE id=attempt.id;
  UPDATE public.source_analysis_runs SET state='failed',analysis_state='provider_failed',failed_at=now(),heartbeat_at=now(),
    safe_error_category='unknown',safe_error_code='source_revoked_before_model' WHERE id=s.id;
  -- A terminal but unbound source still blocks 00091 unique/shared-asset Trash
  -- purge. This is lineage-only: no model candidates or effective values exist.
  INSERT INTO public.document_version_analysis_bindings(
    org_id,document_id,document_version_id,source_analysis_run_id,binding_reason
  ) VALUES (r.org_id,r.document_id,r.document_version_id,s.id,'no_call_processing_source')
  ON CONFLICT (document_version_id,source_analysis_run_id) DO NOTHING;
  RETURN QUERY SELECT 'cancelled'::text;
END $$;

-- Preserve the validated-AI evidence authority while allowing precisely one
-- content-free terminal no-call lineage binding for Trash ownership checks.
CREATE OR REPLACE FUNCTION public.document_version_analysis_binding_insert_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  version_document_id uuid;
  version_asset_id uuid;
  version_validation_state public.document_version_validation_state;
  version_state public.document_version_state;
  run_row public.source_analysis_runs%ROWTYPE;
BEGIN
  SELECT document_id,asset_id,validation_state,state
    INTO version_document_id,version_asset_id,version_validation_state,version_state
    FROM public.document_versions WHERE org_id=NEW.org_id AND id=NEW.document_version_id FOR KEY SHARE;
  SELECT * INTO run_row FROM public.source_analysis_runs
    WHERE org_id=NEW.org_id AND id=NEW.source_analysis_run_id FOR KEY SHARE;
  IF NEW.document_id IS NULL THEN NEW.document_id:=version_document_id; END IF;
  IF version_document_id IS NULL OR NEW.document_id IS DISTINCT FROM version_document_id
    OR run_row.id IS NULL OR run_row.asset_id IS DISTINCT FROM version_asset_id THEN
    RAISE EXCEPTION 'analysis binding must reference one organisation document version and its exact asset';
  END IF;
  IF version_validation_state<>'valid' OR version_state NOT IN ('current','superseded') THEN
    RAISE EXCEPTION 'analysis binding requires a valid current or superseded immutable document version';
  END IF;
  IF NOT (
    (NEW.binding_reason<>'no_call_processing_source' AND run_row.analysis_kind='ai_extraction' AND run_row.analysis_state='validated')
    OR (NEW.binding_reason<>'no_call_processing_source' AND run_row.analysis_kind='asset_validation' AND run_row.state='succeeded')
    OR (
      NEW.binding_reason='no_call_processing_source'
      AND run_row.analysis_kind='ai_extraction' AND run_row.analysis_state='provider_failed'
      AND run_row.state='failed' AND run_row.safe_error_code='source_revoked_before_model'
      AND run_row.provider_request_id IS NULL AND run_row.provider_operation_id IS NULL
      AND run_row.input_tokens IS NULL AND run_row.output_tokens IS NULL AND run_row.usage_recorded_at IS NULL
      AND NOT EXISTS(SELECT 1 FROM public.source_field_candidates WHERE source_analysis_run_id=run_row.id)
      AND EXISTS(SELECT 1 FROM public.source_analysis_attempts attempt
        WHERE attempt.source_analysis_run_id=run_row.id AND attempt.attempt_number=run_row.attempt_count
          AND attempt.state='provider_failed' AND attempt.safe_error_code='source_revoked_before_model'
          AND attempt.provider_call_started_at IS NULL AND attempt.provider_request_id IS NULL
          AND attempt.provider_operation_id IS NULL AND attempt.input_tokens IS NULL
          AND attempt.output_tokens IS NULL AND attempt.usage_recorded_at IS NULL)
      AND EXISTS(SELECT 1 FROM public.document_processing_runs processing
        WHERE processing.org_id=NEW.org_id AND processing.document_id=NEW.document_id
          AND processing.document_version_id=NEW.document_version_id
          AND run_row.idempotency_key='ai_extraction.'||processing.id::text
          AND run_row.request_key=run_row.idempotency_key)
    )
  ) THEN
    RAISE EXCEPTION 'analysis binding requires a terminal compatible source analysis run';
  END IF;
  RETURN NEW;
END $$;

-- Preserve the approved 00152 Copy authority and exception behavior. Only the
-- binding iteration below excludes content-free no-call lineage from AI materialization.
CREATE OR REPLACE FUNCTION public.execute_document_boundary_repair(p_document_id uuid,p_target_matter_id uuid,p_mode text,
  p_expected_fingerprint text,p_reason text,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public SET lock_timeout='5s' AS $$
DECLARE actor record; prior public.document_boundary_repair_receipts%ROWTYPE; impact jsonb; fingerprint text;
  reason text:=nullif(btrim(p_reason),''); d public.documents%ROWTYPE; v public.document_versions%ROWTYPE;
  result_doc uuid; result_version uuid; binding record; binding_id uuid; edge public.document_relationships%ROWTYPE; key_row record; search_event uuid;
  source_decision record; destination_candidate uuid; search_run uuid; source_artifact public.document_page_text_artifacts%ROWTYPE; copied_artifact uuid;
BEGIN
  IF p_idempotency_key IS NULL OR p_expected_fingerprint IS NULL OR p_expected_fingerprint !~ '^[0-9a-f]{64}$'
     OR NOT public.matter_identifier_reason_is_safe(reason,true) THEN RETURN jsonb_build_object('code','invalid_request'); END IF;
  SELECT * INTO actor FROM public.lock_matter_identifier_actor();
  IF actor.org_id IS NULL THEN RETURN jsonb_build_object('code','not_allowed'); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text,152));
  fingerprint:=encode(extensions.digest(convert_to(jsonb_build_array(p_document_id,p_target_matter_id,p_mode,p_expected_fingerprint,reason)::text,'utf8'),'sha256'),'hex');
  SELECT * INTO prior FROM public.document_boundary_repair_receipts WHERE idempotency_key=p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.org_id<>actor.org_id OR prior.actor_user_id<>actor.actor_user_id OR prior.request_fingerprint<>fingerprint THEN RETURN jsonb_build_object('code','idempotency_conflict'); END IF;
    RETURN jsonb_build_object('code','ok','documentId',prior.result_document_id,'sourceMatterId',prior.source_matter_id,'targetMatterId',prior.target_matter_id,'replayed',true);
  END IF;
  impact:=public.document_boundary_repair_impact(actor.org_id,p_document_id,p_target_matter_id,p_mode);
  IF impact->>'code'<>'ok' THEN RETURN impact; END IF;
  IF impact->>'fingerprint'<>p_expected_fingerprint THEN RETURN jsonb_build_object('code','stale_preview'); END IF;
  IF jsonb_array_length(impact->'blockers')>0 THEN RETURN jsonb_build_object('code','blocked'); END IF;
  SELECT * INTO d FROM public.documents WHERE id=p_document_id;
  SELECT * INTO v FROM public.document_versions WHERE id=d.current_version_id;
  IF p_mode='move' THEN
    FOR edge IN SELECT * FROM public.document_relationships WHERE org_id=actor.org_id AND d.id IN(source_document_id,target_document_id) AND lifecycle_state='active' ORDER BY id LOOP
      UPDATE public.document_relationships SET lifecycle_state='archived',revision=revision+1,archived_at=now(),archived_by=actor.actor_user_id,archive_reason=reason,updated_at=now() WHERE id=edge.id;
      INSERT INTO public.document_relationship_decisions(org_id,matter_id,relationship_id,source_document_id,target_document_id,relationship_type,action,from_lifecycle,to_lifecycle,reason,actor_user_id,resulting_revision,idempotency_key)
      VALUES(edge.org_id,edge.matter_id,edge.id,edge.source_document_id,edge.target_document_id,edge.relationship_type,'archive','active','archived',reason,actor.actor_user_id,edge.revision+1,gen_random_uuid());
    END LOOP;
    SET CONSTRAINTS note_document_quotes_note_lineage_fkey,note_document_quotes_document_lineage_fkey DEFERRED;
    UPDATE public.documents SET matter_id=p_target_matter_id,content_availability='source_attached',
      embedding=NULL,embedding_model=NULL,embedding_version=NULL,embedding_document_version_id=NULL WHERE id=d.id;
    UPDATE public.case_notes SET matter_id=p_target_matter_id WHERE org_id=actor.org_id AND document_id=d.id;
    UPDATE public.note_document_quotes SET matter_id=p_target_matter_id WHERE org_id=actor.org_id AND document_id=d.id;
    UPDATE public.deadlines SET matter_id=p_target_matter_id WHERE document_id=d.id;
    UPDATE public.tasks SET matter_id=p_target_matter_id,client_id=(SELECT client_id FROM public.matters WHERE id=p_target_matter_id),revision=revision+1,updated_at=now() WHERE org_id=actor.org_id AND document_id=d.id;
    SET CONSTRAINTS note_document_quotes_note_lineage_fkey,note_document_quotes_document_lineage_fkey IMMEDIATE;
    result_doc:=d.id; result_version:=v.id;
    FOR key_row IN SELECT DISTINCT org_id,issuer_namespace_normalized,identifier_kind,normalized_value FROM public.document_self_identifiers WHERE org_id=actor.org_id AND document_id=d.id
      UNION SELECT DISTINCT org_id,issuer_namespace_normalized,identifier_kind,normalized_value FROM public.document_reference_mentions WHERE org_id=actor.org_id AND source_document_id=d.id ORDER BY org_id,issuer_namespace_normalized,identifier_kind,normalized_value LOOP
      PERFORM public.reevaluate_document_reference_exact_key(key_row.org_id,key_row.issuer_namespace_normalized,key_row.identifier_kind,key_row.normalized_value,'document_availability_changed','repair.'||p_idempotency_key::text||'.'||md5(key_row.issuer_namespace_normalized||key_row.identifier_kind::text||key_row.normalized_value));
    END LOOP;
  ELSE
    INSERT INTO public.documents(org_id,matter_id,display_title,document_class,document_category,origin_kind,copied_from_document_id,content_availability,status,created_by,doc_type,reference_number,doc_date,direction,issued_by,financial_year,summary)
    VALUES(d.org_id,p_target_matter_id,d.display_title,d.document_class,d.document_category,d.origin_kind,d.id,'metadata_only','placed',actor.actor_user_id,d.doc_type,d.reference_number,d.doc_date,d.direction,d.issued_by,d.financial_year,d.summary) RETURNING id INTO result_doc;
    INSERT INTO public.document_versions(org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,created_by,validated_at,promoted_at)
    VALUES(d.org_id,result_doc,v.asset_id,1,v.original_filename,v.page_count,'valid','current',actor.actor_user_id,v.validated_at,now()) RETURNING id INTO result_version;
    UPDATE public.documents SET current_version_id=result_version,content_availability='source_attached',effective_filename=v.original_filename,effective_size_bytes=d.effective_size_bytes WHERE id=result_doc;
    -- Content-free no-call lineage is retained for Trash ownership, not copied as validated AI evidence.
    FOR binding IN SELECT * FROM public.document_version_analysis_bindings WHERE org_id=d.org_id AND document_version_id=v.id AND binding_reason<>'no_call_processing_source' ORDER BY id LOOP
      binding_id:=public.materialize_document_version_analysis(result_version,binding.source_analysis_run_id,'boundary_copy',actor.actor_user_id);
      PERFORM public.materialize_document_reference_mentions(binding_id,'repair.'||p_idempotency_key::text||'.'||binding_id::text);
    END LOOP;
    -- Preserve each current human outcome, including negative decisions that
    -- suppress AI fallback. The copied decision records the confirming actor
    -- and the exact original decision locator; verified identities are separate.
    FOR source_decision IN
      SELECT decision.*, candidate.source_field_candidate_id
      FROM public.document_effective_metadata effective
      JOIN public.document_field_decisions decision ON decision.id=effective.winning_document_field_decision_id
      JOIN public.document_field_candidates candidate ON candidate.id=decision.document_field_candidate_id
      WHERE effective.document_version_id=v.id AND effective.org_id=d.org_id ORDER BY decision.decision_sequence
    LOOP
      SELECT id INTO destination_candidate FROM public.document_field_candidates
      WHERE document_version_id=result_version AND source_field_candidate_id=source_decision.source_field_candidate_id;
      IF destination_candidate IS NULL THEN RAISE EXCEPTION 'Copy decision candidate is unavailable'; END IF;
      INSERT INTO public.document_field_decisions(org_id,document_id,document_version_id,document_field_candidate_id,semantic_candidate_key,field_path,value_type,
        action,replacement_value,reason,actor_user_id,idempotency_key,inherited_from_decision_id)
      VALUES(d.org_id,result_doc,result_version,destination_candidate,source_decision.semantic_candidate_key,source_decision.field_path,source_decision.value_type,
        source_decision.action,source_decision.replacement_value,'Inherited through explicit document Copy',actor.actor_user_id,
        'copy.'||p_idempotency_key::text||'.'||source_decision.id::text,source_decision.id);
    END LOOP;
    PERFORM public.recompute_document_effective_metadata(result_version);
  END IF;
  -- Invalidate all current Search facts and append the existing fenced,
  -- version-scoped Search worker intent. No base extraction/provider request.
  PERFORM public.invalidate_current_document_structured_search_facts(d.org_id,result_doc);
  INSERT INTO public.outbox_events(org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key)
  VALUES(d.org_id,'document',result_doc,'document.reprocess_requested.v1',
    jsonb_build_object('document_id',result_doc::text,'version_id',result_version::text,'scope','search_index'),
    'document.repair.search.'||p_idempotency_key::text) RETURNING id INTO search_event;
  INSERT INTO public.document_processing_runs(org_id,document_id,document_version_id,scope,stage,state,idempotency_key,outbox_event_id)
  VALUES(d.org_id,result_doc,result_version,'search_index','queued','queued','repair.search.'||p_idempotency_key::text,search_event) RETURNING id INTO search_run;
  IF p_mode='copy' THEN
    SELECT * INTO source_artifact FROM public.document_page_text_artifacts WHERE document_version_id=v.id AND org_id=d.org_id AND state='ready';
    IF source_artifact.id IS NULL OR NOT public.document_page_text_artifact_has_approved_acquisition(source_artifact.id,source_artifact.page_count) THEN RAISE EXCEPTION 'Approved Copy page source is unavailable'; END IF;
    INSERT INTO public.document_page_text_artifacts(org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,content_fingerprint,copied_from_artifact_id)
    VALUES(d.org_id,result_doc,result_version,search_run,source_artifact.source_analysis_run_id,'ready',source_artifact.page_count,source_artifact.content_fingerprint,source_artifact.id) RETURNING id INTO copied_artifact;
    INSERT INTO public.document_page_text_pages(org_id,artifact_id,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages,ocr_processor_identifier,ocr_processor_version)
    SELECT org_id,copied_artifact,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages,ocr_processor_identifier,ocr_processor_version
    FROM public.document_page_text_pages WHERE artifact_id=source_artifact.id ORDER BY page_number;
  END IF;
  PERFORM public.append_activity_event(d.org_id,'document.boundary_repaired',1::smallint,'user',actor.actor_user_id,'Member','document',result_doc,
    (SELECT client_id FROM public.matters WHERE id=p_target_matter_id),p_target_matter_id,'Document','Document '||CASE p_mode WHEN 'move' THEN 'moved' ELSE 'copied' END,
    jsonb_build_object('mode',p_mode),'document',result_doc,result_version,p_idempotency_key,NULL,'document.repair.'||p_idempotency_key::text,now());
  INSERT INTO public.document_boundary_repair_receipts(org_id,actor_user_id,idempotency_key,request_fingerprint,mode,source_document_id,source_matter_id,target_matter_id,result_document_id,result_version_id,reason,impact)
  VALUES(d.org_id,actor.actor_user_id,p_idempotency_key,fingerprint,p_mode,d.id,d.matter_id,p_target_matter_id,result_doc,result_version,reason,
    jsonb_build_object('documentId',d.id,'sourceMatterId',d.matter_id,'targetMatterId',p_target_matter_id,'versionId',v.id,
      'fingerprint',impact->>'fingerprint','documentRevision',impact->'documentRevision','sourceRevision',impact->'sourceRevision','targetRevision',impact->'targetRevision',
      'counts',(SELECT jsonb_object_agg(category->>'key',category->'count') FROM jsonb_array_elements(impact->'categories') category)));
  RETURN jsonb_build_object('code','ok','documentId',result_doc,'sourceMatterId',d.matter_id,'targetMatterId',p_target_matter_id,'replayed',false);
EXCEPTION WHEN lock_not_available OR deadlock_detected THEN RETURN jsonb_build_object('code','busy');
  WHEN others THEN RETURN jsonb_build_object('code','write_failed');
END $$;

REVOKE ALL ON FUNCTION public.grant_current_document_processing_source(uuid,uuid),
  public.begin_current_document_processing_ai_extraction(uuid,uuid,text,text,text,text,text,text,text),
  public.mark_current_document_processing_ai_provider_call(uuid,uuid,uuid,uuid),
  public.cancel_uncalled_document_processing_ai_extraction(uuid,uuid,uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.grant_current_document_processing_source(uuid,uuid),
  public.begin_current_document_processing_ai_extraction(uuid,uuid,text,text,text,text,text,text,text),
  public.mark_current_document_processing_ai_provider_call(uuid,uuid,uuid,uuid),
  public.cancel_uncalled_document_processing_ai_extraction(uuid,uuid,uuid,uuid)
  TO service_role;
COMMIT;
