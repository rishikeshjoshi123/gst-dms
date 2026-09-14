-- D08-T03: terminal extraction failure -> typed Review -> manual continuation.
-- This deliberately does not enqueue extraction retry work.
ALTER TYPE public.review_item_type ADD VALUE 'processing_recovery';
ALTER TYPE public.review_extraction_action ADD VALUE 'continue_manual';

COMMIT;
BEGIN;

ALTER TABLE public.review_items
  DROP CONSTRAINT review_items_reason_code_check,
  DROP CONSTRAINT review_items_candidate_sequence_check,
  DROP CONSTRAINT review_items_field_path_check,
  DROP CONSTRAINT review_items_semantic_candidate_key_check,
  ALTER COLUMN binding_id DROP NOT NULL,
  ALTER COLUMN candidate_sequence DROP NOT NULL,
  ALTER COLUMN field_path DROP NOT NULL,
  ALTER COLUMN semantic_candidate_key DROP NOT NULL,
  ALTER COLUMN field_decision_sequence DROP NOT NULL,
  ADD COLUMN processing_run_id uuid,
  ADD COLUMN source_analysis_run_id uuid,
  ADD COLUMN source_page_number integer,
  ADD COLUMN document_lifecycle_revision bigint,
  ADD CONSTRAINT review_items_reason_code_check CHECK (
    (type='extraction_conflict' AND reason_code='material_candidate_conflict') OR
    (type='processing_recovery' AND reason_code IN ('invalid_model_output','provider_failed','domain_invalid'))
  ),
  ADD CONSTRAINT review_items_type_shape_check CHECK (
    (type='extraction_conflict' AND binding_id IS NOT NULL AND candidate_sequence>0
      AND field_path ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){0,15}$'
      AND semantic_candidate_key ~ '^[a-z][a-z0-9_.:-]{0,199}$'
      AND field_decision_sequence>=0 AND processing_run_id IS NULL
      AND source_analysis_run_id IS NULL AND source_page_number IS NULL
      AND document_lifecycle_revision IS NULL)
    OR
    (type='processing_recovery' AND binding_id IS NULL AND candidate_sequence IS NULL
      AND field_path IS NULL AND semantic_candidate_key IS NULL
      AND field_decision_sequence IS NULL AND NOT can_select
      AND processing_run_id IS NOT NULL AND source_analysis_run_id IS NOT NULL
      AND source_page_number=1 AND document_lifecycle_revision>0)
  );

ALTER TABLE public.review_item_decisions
  DROP CONSTRAINT review_item_decisions_check,
  DROP CONSTRAINT review_item_decisions_check1,
  ADD COLUMN manual_metadata jsonb,
  ADD CONSTRAINT review_item_decisions_action_shape_check CHECK (
    (action='select_candidate' AND selected_candidate_id IS NOT NULL AND manual_metadata IS NULL) OR
    (action='request_clarification' AND selected_candidate_id IS NULL AND manual_metadata IS NULL) OR
    (action='continue_manual' AND selected_candidate_id IS NULL AND manual_metadata IS NOT NULL)
  );

-- Manual recovery uses the canonical candidate -> decision -> effective
-- metadata pipeline, but it must not pretend that a failed provider produced
-- source evidence. These candidates therefore carry an explicit manual Review
-- origin and no source-analysis binding.
ALTER TABLE public.document_field_candidates
  ALTER COLUMN document_version_analysis_binding_id DROP NOT NULL,
  ALTER COLUMN source_field_candidate_id DROP NOT NULL,
  ADD COLUMN origin_kind text NOT NULL DEFAULT 'extraction'
    CHECK(origin_kind IN ('extraction','manual_recovery')),
  ADD COLUMN manual_review_item_id uuid REFERENCES public.review_items(id),
  ADD CONSTRAINT document_field_candidates_origin_shape_check CHECK(
    (origin_kind='extraction' AND document_version_analysis_binding_id IS NOT NULL
      AND source_field_candidate_id IS NOT NULL AND manual_review_item_id IS NULL)
    OR
    (origin_kind='manual_recovery' AND document_version_analysis_binding_id IS NULL
      AND source_field_candidate_id IS NULL AND manual_review_item_id IS NOT NULL
      AND validation_state='provisional' AND validation_error_codes IS NULL
      AND confidence=0 AND evidence_regions IS NULL)
  );

CREATE OR REPLACE FUNCTION public.document_field_candidate_insert_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE
  binding_row public.document_version_analysis_bindings%ROWTYPE;
  source_row public.source_field_candidates%ROWTYPE;
  version_asset_id uuid; version_page_count integer;
  review_row public.review_items%ROWTYPE;
BEGIN
  SELECT asset_id,page_count INTO version_asset_id,version_page_count
    FROM public.document_versions WHERE org_id=NEW.org_id AND id=NEW.document_version_id FOR KEY SHARE;
  IF NEW.origin_kind='manual_recovery' THEN
    SELECT * INTO review_row FROM public.review_items
      WHERE id=NEW.manual_review_item_id AND org_id=NEW.org_id FOR KEY SHARE;
    IF review_row.id IS NULL OR review_row.type<>'processing_recovery'
      OR review_row.status<>'needs_review' OR review_row.document_id<>NEW.document_id
      OR review_row.document_version_id<>NEW.document_version_id
      OR version_page_count IS NULL OR NEW.page_number<>review_row.source_page_number
      OR NEW.evidence_page_count<>version_page_count
      OR NEW.quotation<>'Manual recovery entry; not an extracted quotation.' THEN
      RAISE EXCEPTION 'manual candidate must preserve its current typed Review and version boundary';
    END IF;
    RETURN NEW;
  END IF;
  SELECT * INTO binding_row FROM public.document_version_analysis_bindings
    WHERE org_id=NEW.org_id AND id=NEW.document_version_analysis_binding_id FOR KEY SHARE;
  SELECT * INTO source_row FROM public.source_field_candidates
    WHERE org_id=NEW.org_id AND id=NEW.source_field_candidate_id FOR KEY SHARE;
  IF binding_row.id IS NULL OR source_row.id IS NULL
    OR NEW.document_id IS DISTINCT FROM binding_row.document_id
    OR NEW.document_version_id IS DISTINCT FROM binding_row.document_version_id
    OR source_row.source_analysis_run_id IS DISTINCT FROM binding_row.source_analysis_run_id
    OR source_row.asset_id IS DISTINCT FROM version_asset_id OR version_page_count IS NULL
    OR source_row.evidence_page_count<>version_page_count OR source_row.page_number>version_page_count THEN
    RAISE EXCEPTION 'document candidate must preserve one exact compatible binding, source candidate, and version evidence boundary';
  END IF;
  IF NEW.semantic_candidate_key IS DISTINCT FROM source_row.semantic_candidate_key
    OR NEW.field_path IS DISTINCT FROM source_row.field_path
    OR NEW.value_type IS DISTINCT FROM source_row.value_type
    OR NEW.normalized_value IS DISTINCT FROM source_row.normalized_value
    OR NEW.page_number IS DISTINCT FROM source_row.page_number
    OR NEW.evidence_page_count IS DISTINCT FROM source_row.evidence_page_count
    OR NEW.quotation IS DISTINCT FROM source_row.quotation
    OR NEW.evidence_regions IS DISTINCT FROM source_row.evidence_regions
    OR NEW.confidence IS DISTINCT FROM source_row.confidence
    OR NEW.validation_state IS DISTINCT FROM source_row.validation_state
    OR NEW.validation_error_codes IS DISTINCT FROM source_row.validation_error_codes THEN
    RAISE EXCEPTION 'document candidate must be an exact immutable source-candidate materialization';
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION public.produce_processing_recovery_review(
  p_processing_run_id uuid,
  p_source_analysis_run_id uuid,
  p_outcome text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE
  processing public.document_processing_runs%ROWTYPE;
  source_run public.source_analysis_runs%ROWTYPE;
  version_row public.document_versions%ROWTYPE;
  document_row public.documents%ROWTYPE;
  recovery_reason text;
  recovery_impact text;
  item_id uuid;
BEGIN
  IF p_outcome NOT IN ('invalid_model_output','provider_failed','review_required') THEN RETURN NULL; END IF;
  SELECT * INTO processing FROM public.document_processing_runs WHERE id=p_processing_run_id;
  SELECT * INTO source_run FROM public.source_analysis_runs WHERE id=p_source_analysis_run_id AND org_id=processing.org_id;
  SELECT * INTO version_row FROM public.document_versions WHERE id=processing.document_version_id AND org_id=processing.org_id;
  SELECT * INTO document_row FROM public.documents WHERE id=processing.document_id AND org_id=processing.org_id;
  IF processing.id IS NULL OR source_run.id IS NULL OR version_row.id IS NULL OR document_row.id IS NULL
    OR (processing.source_analysis_run_id IS NOT NULL AND processing.source_analysis_run_id IS DISTINCT FROM source_run.id)
    OR source_run.idempotency_key IS DISTINCT FROM ('ai_extraction.'||processing.id::text)
    OR source_run.asset_id IS DISTINCT FROM version_row.asset_id
    OR source_run.analysis_state::text IS DISTINCT FROM p_outcome
    OR processing.document_id IS DISTINCT FROM version_row.document_id
    OR document_row.current_version_id IS DISTINCT FROM version_row.id
    OR NOT public.review_document_available(processing.org_id,processing.document_id) THEN RETURN NULL; END IF;
  recovery_reason:=CASE WHEN p_outcome='review_required' THEN 'domain_invalid' ELSE p_outcome END;
  recovery_impact:=CASE recovery_reason
    WHEN 'invalid_model_output' THEN 'Automated metadata could not be validated. Continue manually before relying on the document record.'
    WHEN 'provider_failed' THEN 'Automated metadata could not be produced. Continue manually using the immutable source PDF.'
    ELSE 'Automated metadata failed domain validation. Continue manually before relying on the document record.' END;
  INSERT INTO public.review_items(
    org_id,document_id,document_version_id,type,reason_code,impact,priority,
    priority_reason,can_select,dedupe_key,processing_run_id,
    source_analysis_run_id,source_page_number,document_lifecycle_revision,
    field_decision_sequence
  ) VALUES (
    processing.org_id,processing.document_id,processing.document_version_id,
    'processing_recovery',recovery_reason,recovery_impact,'high',
    'Automated extraction did not produce usable metadata for this current PDF.',false,
    md5('processing_recovery:'||source_run.id::text),processing.id,source_run.id,1,
    document_row.lifecycle_revision,NULL
  ) ON CONFLICT(dedupe_key) DO NOTHING RETURNING id INTO item_id;
  IF item_id IS NULL THEN
    SELECT id INTO item_id FROM public.review_items WHERE dedupe_key=md5('processing_recovery:'||source_run.id::text);
  END IF;
  RETURN item_id;
END $$;

ALTER FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb)
  RENAME TO finish_document_processing_ai_extraction_before_recovery;
CREATE FUNCTION public.finish_document_processing_ai_extraction(
  p_processing_run_id uuid,p_processing_lease_token uuid,p_source_analysis_run_id uuid,
  p_source_analysis_lease_token uuid,p_outcome text,p_input_tokens bigint,
  p_output_tokens bigint,p_latency_ms integer,p_candidates jsonb DEFAULT '[]',
  p_review_required boolean DEFAULT false,p_legacy_metadata jsonb DEFAULT NULL
) RETURNS TABLE(code text,binding_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE finished record;
BEGIN
  SELECT * INTO finished FROM public.finish_document_processing_ai_extraction_before_recovery(
    p_processing_run_id,p_processing_lease_token,p_source_analysis_run_id,
    p_source_analysis_lease_token,p_outcome,p_input_tokens,p_output_tokens,
    p_latency_ms,p_candidates,p_review_required,p_legacy_metadata
  );
  IF finished.code IN ('invalid_model_output','provider_failed','review_required')
    AND finished.code=p_outcome THEN
    PERFORM public.produce_processing_recovery_review(
      p_processing_run_id,p_source_analysis_run_id,p_outcome
    );
  END IF;
  RETURN QUERY SELECT finished.code::text,finished.binding_id::uuid;
END $$;

DROP FUNCTION public.read_review_queue(text,text,text,text,integer,integer);
CREATE FUNCTION public.read_review_queue(
  p_status text DEFAULT 'needs_review',p_type text DEFAULT 'all',
  p_priority text DEFAULT 'all',p_search text DEFAULT '',p_page integer DEFAULT 1,
  p_page_size integer DEFAULT 25
) RETURNS TABLE(items jsonb,total_count bigint,can_resolve boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record;
BEGIN
  SELECT * INTO actor FROM public.review_actor();
  IF actor.actor_user_id IS NULL THEN RETURN; END IF;
  IF p_status IS NULL OR p_status NOT IN ('needs_review','closed','all')
    OR p_type IS NULL OR p_type NOT IN ('extraction_conflict','processing_recovery','all')
    OR p_priority IS NULL OR p_priority NOT IN ('normal','high','urgent','all')
    OR p_search IS NULL OR char_length(p_search)>200 OR p_page IS NULL
    OR p_page NOT BETWEEN 1 AND 100000 OR p_page_size IS NULL
    OR p_page_size NOT BETWEEN 1 AND 50 THEN RETURN; END IF;
  RETURN QUERY WITH filtered AS MATERIALIZED (
    SELECT i.id,i.type,i.field_path,i.reason_code,i.impact,i.priority,
      i.priority_reason,i.status,i.closure_reason,i.revision,i.created_at,
      i.document_id,i.document_version_id,i.source_page_number,
      d.display_title AS document_title,m.title AS matter_title,c.name AS client_name
    FROM public.review_items i
    JOIN public.documents d ON d.id=i.document_id AND d.org_id=i.org_id
    JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id
    JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id
    WHERE i.org_id=actor.org_id AND public.review_document_available(i.org_id,i.document_id)
      AND (i.status='closed' OR d.current_version_id=i.document_version_id)
      AND (p_status='all' OR i.status::text=p_status)
      AND (p_type='all' OR i.type::text=p_type)
      AND (p_priority='all' OR i.priority::text=p_priority)
      AND (p_search='' OR strpos(lower(concat_ws(' ',i.field_path,i.reason_code,d.display_title,m.title,c.name)),lower(p_search))>0)
  ), page_rows AS (
    SELECT * FROM filtered ORDER BY priority DESC,created_at,id
    LIMIT p_page_size OFFSET (p_page-1)*p_page_size
  )
  SELECT coalesce((SELECT jsonb_agg(to_jsonb(page_rows) ORDER BY priority DESC,created_at,id) FROM page_rows),'[]'::jsonb),
    (SELECT count(*) FROM filtered),actor.can_resolve;
END $$;

DROP FUNCTION public.read_review_detail(uuid);
CREATE FUNCTION public.read_review_detail(p_review_item_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; item public.review_items%ROWTYPE; result jsonb; source_current boolean;
BEGIN
  SELECT * INTO actor FROM public.review_actor();
  IF actor.actor_user_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  IF item.id IS NULL OR NOT public.review_document_available(item.org_id,item.document_id) THEN RETURN NULL; END IF;
  source_current:=item.type='processing_recovery' AND EXISTS(
    SELECT 1 FROM public.source_analysis_runs r
    JOIN public.document_processing_runs p ON p.id=item.processing_run_id
      AND p.org_id=r.org_id
    JOIN public.document_versions v ON v.id=item.document_version_id
      AND v.org_id=r.org_id AND v.asset_id=r.asset_id
    WHERE r.id=item.source_analysis_run_id AND r.org_id=item.org_id
      AND (p.source_analysis_run_id IS NULL OR p.source_analysis_run_id=r.id)
      AND r.idempotency_key='ai_extraction.'||p.id::text
      AND r.analysis_state::text=CASE item.reason_code WHEN 'domain_invalid' THEN 'review_required' ELSE item.reason_code END
  );
  SELECT to_jsonb(item)||jsonb_build_object(
    'document_title',d.display_title,'matter_title',m.title,'client_name',c.name,
    'version_number',v.version_number,'is_current',d.current_version_id=item.document_version_id,
    'source_identity','Document version '||v.version_number,
    'record_baseline',CASE WHEN item.type='extraction_conflict'
      THEN public.attachment_review_baseline(item.document_version_id,item.field_path)
      ELSE NULL END,
    'allowed_actions',CASE
      WHEN actor.can_resolve AND item.status='needs_review'
        AND d.current_version_id=item.document_version_id
        AND item.type='processing_recovery' AND source_current
        AND d.lifecycle_revision=item.document_lifecycle_revision THEN jsonb_build_array('continue_manual')
      WHEN actor.can_resolve AND item.status='needs_review'
        AND d.current_version_id=item.document_version_id
        AND item.type='extraction_conflict' THEN
          CASE WHEN item.can_select THEN jsonb_build_array('select_candidate','request_clarification')
          ELSE jsonb_build_array('request_clarification') END
      ELSE '[]'::jsonb END,
    'evidence',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'candidate_id',candidate.id,'ordinal',e.ordinal,'selectable',e.selectable,
      'page_number',candidate.page_number,'quotation',candidate.quotation,
      'value',candidate.normalized_value,'validation_state',candidate.validation_state
    ) ORDER BY e.ordinal) FROM public.review_item_evidence e
      JOIN public.document_field_candidates candidate
        ON candidate.id=e.candidate_id AND candidate.org_id=e.org_id
      WHERE e.review_item_id=item.id),'[]'::jsonb),
    'last_decision',(SELECT jsonb_build_object('action',decision.action,
      'selected_candidate_id',decision.selected_candidate_id,'reason',decision.reason,
      'manual_metadata',decision.manual_metadata,'created_at',decision.created_at) FROM public.review_item_decisions decision
      WHERE decision.review_item_id=item.id ORDER BY decision.result_revision DESC LIMIT 1)
  ) INTO result
  FROM public.documents d
  JOIN public.document_versions v ON v.id=item.document_version_id
    AND v.document_id=d.id AND v.org_id=d.org_id
  JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id
  JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id
  WHERE d.id=item.document_id;
  RETURN result;
END $$;

INSERT INTO public.activity_event_definitions(
  event_type,event_version,category,subject_types,default_visibility,
  metadata_contract,renderer_key
) VALUES (
  'review.processing_recovery_decided',1,'review',ARRAY['document'],'matter',
  '{"action":"code","reason_code":"code","revision":"integer"}',
  'review.processing_recovery_decided.v1'
);

CREATE FUNCTION public.resolve_processing_recovery(
  p_review_item_id uuid,p_expected_revision bigint,
  p_action public.review_extraction_action,p_metadata jsonb,p_reason text,p_idempotency_key uuid
) RETURNS TABLE(code text,current_item jsonb,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE
  actor record; item public.review_items%ROWTYPE; prior public.review_item_decisions%ROWTYPE;
  processing public.document_processing_runs%ROWTYPE; version_row public.document_versions%ROWTYPE;
  d public.documents%ROWTYPE; source_run public.source_analysis_runs%ROWTYPE;
  client_id_value uuid; reason_value text:=btrim(p_reason);
  field_row record; candidate_id uuid; decision_id uuid;
BEGIN
  SELECT * INTO actor FROM public.review_actor(true);
  IF actor.actor_user_id IS NULL OR NOT actor.can_resolve THEN
    RETURN QUERY SELECT 'forbidden',NULL::jsonb,false; RETURN;
  END IF;
  IF p_review_item_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1
    OR p_action IS DISTINCT FROM 'continue_manual' OR p_idempotency_key IS NULL
    OR reason_value IS NULL OR char_length(reason_value) NOT BETWEEN 1 AND 500
    OR reason_value ~ '[[:cntrl:]]' OR jsonb_typeof(p_metadata)<>'object'
    OR NOT public.jsonb_object_has_exact_keys(p_metadata,
      ARRAY['doc_type','reference_number','document_date','direction','issued_by'])
    OR jsonb_typeof(p_metadata->'doc_type')<>'string'
    OR p_metadata->>'doc_type' NOT IN ('DRC-01','DRC-01A','DRC-01C','DRC-03','DRC-07','SCN','OIO','OIA','APL-01','APL-02','APL-05','STAY','REPLY','HC_PETITION','HC_ORDER','SC_PETITION','SC_ORDER','OTHER')
    OR jsonb_typeof(p_metadata->'reference_number')<>'string'
    OR char_length(btrim(p_metadata->>'reference_number')) NOT BETWEEN 1 AND 300
    OR (p_metadata->>'reference_number') ~ '[[:cntrl:]]'
    OR jsonb_typeof(p_metadata->'document_date')<>'string'
    OR NOT pg_input_is_valid(p_metadata->>'document_date','date')
    OR (p_metadata->>'document_date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    OR jsonb_typeof(p_metadata->'direction')<>'string'
    OR p_metadata->>'direction' NOT IN ('incoming','outgoing')
    OR jsonb_typeof(p_metadata->'issued_by')<>'string'
    OR char_length(btrim(p_metadata->>'issued_by')) NOT BETWEEN 1 AND 300
    OR (p_metadata->>'issued_by') ~ '[[:cntrl:]]' THEN
    RETURN QUERY SELECT 'invalid_request',NULL::jsonb,false; RETURN;
  END IF;
  SELECT * INTO item FROM public.review_items
    WHERE id=p_review_item_id AND org_id=actor.org_id;
  IF item.id IS NULL OR item.type<>'processing_recovery' THEN
    RETURN QUERY SELECT 'unavailable',NULL::jsonb,false; RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock_shared(hashtextextended(item.document_id::text,1521));
  SELECT * INTO processing FROM public.document_processing_runs
    WHERE id=item.processing_run_id AND org_id=item.org_id FOR UPDATE;
  SELECT * INTO version_row FROM public.document_versions
    WHERE id=item.document_version_id AND org_id=item.org_id FOR UPDATE;
  SELECT * INTO d FROM public.documents
    WHERE id=item.document_id AND org_id=item.org_id FOR UPDATE;
  SELECT m.client_id INTO client_id_value FROM public.matters m WHERE m.id=d.matter_id;
  PERFORM 1 FROM public.matters WHERE id=d.matter_id FOR SHARE;
  PERFORM 1 FROM public.clients WHERE id=client_id_value FOR SHARE;
  SELECT * INTO source_run FROM public.source_analysis_runs
    WHERE id=item.source_analysis_run_id AND org_id=item.org_id FOR UPDATE;
  SELECT * INTO item FROM public.review_items
    WHERE id=p_review_item_id AND org_id=actor.org_id FOR UPDATE;
  IF NOT public.review_document_available(actor.org_id,item.document_id) THEN
    RETURN QUERY SELECT 'unavailable',NULL::jsonb,false; RETURN;
  END IF;
  SELECT * INTO prior FROM public.review_item_decisions
    WHERE org_id=actor.org_id AND actor_user_id=actor.actor_user_id
      AND idempotency_key=p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.review_item_id<>item.id OR prior.expected_revision<>p_expected_revision
      OR prior.action<>p_action OR prior.selected_candidate_id IS NOT NULL
      OR prior.reason<>reason_value OR prior.manual_metadata IS DISTINCT FROM p_metadata THEN
      RETURN QUERY SELECT 'idempotency_conflict',public.read_review_detail(item.id),false;
    ELSE
      RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),true;
    END IF;
    RETURN;
  END IF;
  IF item.revision<>p_expected_revision OR item.status='closed'
    OR d.current_version_id IS DISTINCT FROM item.document_version_id
    OR d.lifecycle_revision<>item.document_lifecycle_revision
    OR processing.id IS NULL OR processing.document_id<>item.document_id
    OR processing.document_version_id<>item.document_version_id
    OR (processing.source_analysis_run_id IS NOT NULL AND processing.source_analysis_run_id IS DISTINCT FROM source_run.id)
    OR source_run.idempotency_key IS DISTINCT FROM ('ai_extraction.'||processing.id::text)
    OR version_row.id IS NULL OR version_row.document_id<>item.document_id
    OR version_row.asset_id IS DISTINCT FROM source_run.asset_id
    OR source_run.analysis_state::text IS DISTINCT FROM
      (CASE item.reason_code WHEN 'domain_invalid' THEN 'review_required' ELSE item.reason_code END) THEN
    RETURN QUERY SELECT 'stale',public.read_review_detail(item.id),false; RETURN;
  END IF;
  FOR field_row IN SELECT * FROM (VALUES
    ('document.type','code',p_metadata->'doc_type'),
    ('document.reference_number','text',to_jsonb(btrim(p_metadata->>'reference_number'))),
    ('document.date','date',p_metadata->'document_date'),
    ('document.direction','code',p_metadata->'direction'),
    ('document.issued_by','text',to_jsonb(btrim(p_metadata->>'issued_by')))
  ) AS fields(field_path,value_type,normalized_value) LOOP
    INSERT INTO public.document_field_candidates(
      org_id,document_id,document_version_id,document_version_analysis_binding_id,
      source_field_candidate_id,semantic_candidate_key,field_path,value_type,
      normalized_value,page_number,evidence_page_count,quotation,evidence_regions,
      confidence,validation_state,validation_error_codes,origin_kind,manual_review_item_id
    ) VALUES (
      item.org_id,item.document_id,item.document_version_id,NULL,NULL,
      'manual:'||replace(item.id::text,'-','')||':'||field_row.field_path,
      field_row.field_path,field_row.value_type::public.source_field_candidate_value_type,
      field_row.normalized_value,item.source_page_number,version_row.page_count,
      'Manual recovery entry; not an extracted quotation.',NULL,0,'provisional',NULL,
      'manual_recovery',item.id
    ) RETURNING id INTO candidate_id;
    INSERT INTO public.document_field_decisions(
      org_id,document_id,document_version_id,document_field_candidate_id,
      semantic_candidate_key,field_path,value_type,action,replacement_value,
      reason,actor_user_id,idempotency_key
    ) VALUES (
      item.org_id,item.document_id,item.document_version_id,candidate_id,
      'placeholder','placeholder','text','accepted',NULL,reason_value,
      actor.actor_user_id,'review.recovery.'||p_idempotency_key::text||'.'||replace(field_row.field_path,'.','_')
    ) RETURNING id INTO decision_id;
  END LOOP;
  INSERT INTO public.review_item_decisions(
    org_id,review_item_id,expected_revision,result_revision,action,
    selected_candidate_id,manual_metadata,reason,actor_user_id,idempotency_key
  ) VALUES (
    item.org_id,item.id,item.revision,item.revision+1,p_action,NULL,p_metadata,
    reason_value,actor.actor_user_id,p_idempotency_key
  );
  UPDATE public.review_items SET revision=revision+1,updated_at=now(),
    status='closed',closure_reason='decision_recorded',closed_at=now()
    WHERE id=item.id;
  PERFORM public.recompute_document_effective_metadata(item.document_version_id);
  IF NOT EXISTS(SELECT 1 FROM public.review_items other
      WHERE other.document_id=item.document_id AND other.status='needs_review'
        AND other.id<>item.id) THEN
    UPDATE public.documents SET status='analyzed',review_reason=NULL
      WHERE id=item.document_id AND current_version_id=item.document_version_id
        AND status='needs_review'
        AND review_reason IN ('provenance_invalid_model_output','provenance_provider_failed','provenance_candidate_review_required');
  END IF;
  PERFORM public.append_activity_event(
    item.org_id,'review.processing_recovery_decided',1::smallint,'user',
    actor.actor_user_id,'Member','document',item.document_id,client_id_value,
    d.matter_id,'Document','Manual processing continuation recorded',
    jsonb_build_object('action',p_action,'reason_code',item.reason_code,
      'revision',item.revision+1),'document',item.document_id,
    item.document_version_id,item.id,NULL,
    'review.recovery.'||item.org_id||'.'||actor.actor_user_id||'.'||p_idempotency_key,now()
  );
  RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),false;
END $$;

REVOKE ALL ON FUNCTION public.produce_processing_recovery_review(uuid,uuid,text),
  public.finish_document_processing_ai_extraction_before_recovery(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.read_review_queue(text,text,text,text,integer,integer),
  public.read_review_detail(uuid),
  public.resolve_processing_recovery(uuid,bigint,public.review_extraction_action,jsonb,text,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_review_queue(text,text,text,text,integer,integer),
  public.read_review_detail(uuid),
  public.resolve_processing_recovery(uuid,bigint,public.review_extraction_action,jsonb,text,uuid)
  TO authenticated;
REVOKE ALL ON FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb)
  TO service_role;

COMMIT;
