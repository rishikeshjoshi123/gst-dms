-- D08-T04: trusted global-Intake placement ambiguity -> typed Review ->
-- canonical document materialisation. Matter-origin Intake is deliberately
-- excluded: its intended destination remains authoritative.
ALTER TYPE public.review_item_type ADD VALUE 'ambiguous_placement';
ALTER TYPE public.review_extraction_action ADD VALUE 'select_destination';
ALTER TYPE public.review_item_closure ADD VALUE 'source_unavailable';

COMMIT;
BEGIN;

CREATE TYPE public.intake_placement_run_state AS ENUM ('ambiguous','superseded','resolved','unavailable');
CREATE TYPE public.intake_placement_evidence_kind AS ENUM (
  'matter_code_exact','external_proceeding_id_exact','referenced_document_exact',
  'verified_client_identifier','tax_period_overlap','procedure_compatible'
);

CREATE TABLE public.intake_placement_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id),
  intake_id uuid NOT NULL,
  asset_id uuid NOT NULL,
  asset_sha256 text NOT NULL CHECK(asset_sha256 ~ '^[0-9a-f]{64}$'),
  intake_updated_at timestamptz NOT NULL,
  source_revision text NOT NULL CHECK(source_revision ~ '^[a-z][a-z0-9_.:-]{0,127}$'),
  policy_version integer NOT NULL DEFAULT 1 CHECK(policy_version=1),
  candidate_count integer NOT NULL CHECK(candidate_count BETWEEN 2 AND 20),
  state public.intake_placement_run_state NOT NULL DEFAULT 'ambiguous',
  created_at timestamptz NOT NULL DEFAULT now(),
  superseded_at timestamptz,
  resolved_at timestamptz,
  unavailable_at timestamptz,
  UNIQUE(org_id,id),
  UNIQUE(org_id,intake_id,source_revision,asset_sha256),
  FOREIGN KEY(org_id,intake_id) REFERENCES public.intake_items(org_id,id),
  FOREIGN KEY(org_id,asset_id) REFERENCES public.file_assets(org_id,id),
  CHECK (
    (state='ambiguous' AND superseded_at IS NULL AND resolved_at IS NULL AND unavailable_at IS NULL) OR
    (state='superseded' AND superseded_at IS NOT NULL AND resolved_at IS NULL AND unavailable_at IS NULL) OR
    (state='resolved' AND superseded_at IS NULL AND resolved_at IS NOT NULL AND unavailable_at IS NULL) OR
    (state='unavailable' AND superseded_at IS NULL AND resolved_at IS NULL AND unavailable_at IS NOT NULL)
  )
);

CREATE TABLE public.intake_placement_candidates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  placement_run_id uuid NOT NULL,
  matter_id uuid NOT NULL,
  matter_revision bigint NOT NULL CHECK(matter_revision>0),
  client_id uuid NOT NULL,
  client_revision bigint NOT NULL CHECK(client_revision>0),
  ordinal integer NOT NULL CHECK(ordinal BETWEEN 1 AND 20),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(org_id,id),
  UNIQUE(placement_run_id,matter_id),
  UNIQUE(placement_run_id,ordinal),
  FOREIGN KEY(org_id,placement_run_id) REFERENCES public.intake_placement_runs(org_id,id),
  FOREIGN KEY(org_id,matter_id) REFERENCES public.matters(org_id,id),
  FOREIGN KEY(org_id,client_id) REFERENCES public.clients(org_id,id)
);

CREATE TABLE public.intake_placement_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  placement_candidate_id uuid NOT NULL,
  ordinal integer NOT NULL CHECK(ordinal BETWEEN 1 AND 20),
  kind public.intake_placement_evidence_kind NOT NULL,
  source_page_number integer CHECK(source_page_number IS NULL OR source_page_number>0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(placement_candidate_id,ordinal),
  UNIQUE(placement_candidate_id,kind,source_page_number),
  FOREIGN KEY(org_id,placement_candidate_id) REFERENCES public.intake_placement_candidates(org_id,id)
);

CREATE TABLE public.intake_placement_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  placement_run_id uuid NOT NULL,
  review_item_id uuid NOT NULL,
  placement_candidate_id uuid NOT NULL,
  matter_id uuid NOT NULL,
  document_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id),
  reason text NOT NULL CHECK(char_length(btrim(reason)) BETWEEN 1 AND 500 AND reason !~ '[[:cntrl:]]'),
  idempotency_key uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(org_id,actor_user_id,idempotency_key),
  UNIQUE(review_item_id),
  FOREIGN KEY(org_id,review_item_id) REFERENCES public.review_items(org_id,id),
  FOREIGN KEY(org_id,placement_run_id) REFERENCES public.intake_placement_runs(org_id,id),
  FOREIGN KEY(org_id,placement_candidate_id) REFERENCES public.intake_placement_candidates(org_id,id),
  FOREIGN KEY(org_id,matter_id) REFERENCES public.matters(org_id,id),
  FOREIGN KEY(org_id,document_id) REFERENCES public.documents(org_id,id),
  FOREIGN KEY(org_id,document_version_id) REFERENCES public.document_versions(org_id,id)
);

CREATE TRIGGER intake_placement_runs_immutable BEFORE DELETE ON public.intake_placement_runs
  FOR EACH ROW EXECUTE FUNCTION public.activity_events_prevent_mutation();
CREATE TRIGGER intake_placement_candidates_immutable BEFORE UPDATE OR DELETE ON public.intake_placement_candidates
  FOR EACH ROW EXECUTE FUNCTION public.activity_events_prevent_mutation();
CREATE TRIGGER intake_placement_evidence_immutable BEFORE UPDATE OR DELETE ON public.intake_placement_evidence
  FOR EACH ROW EXECUTE FUNCTION public.activity_events_prevent_mutation();
CREATE TRIGGER intake_placement_decisions_immutable BEFORE UPDATE OR DELETE ON public.intake_placement_decisions
  FOR EACH ROW EXECUTE FUNCTION public.activity_events_prevent_mutation();

ALTER TABLE public.review_items
  DROP CONSTRAINT review_items_type_shape_check,
  DROP CONSTRAINT review_items_reason_code_check,
  ALTER COLUMN document_id DROP NOT NULL,
  ALTER COLUMN document_version_id DROP NOT NULL,
  ADD COLUMN intake_id uuid,
  ADD COLUMN placement_run_id uuid,
  ADD COLUMN intake_asset_id uuid,
  ADD CONSTRAINT review_items_intake_fkey FOREIGN KEY(org_id,intake_id) REFERENCES public.intake_items(org_id,id),
  ADD CONSTRAINT review_items_placement_run_fkey FOREIGN KEY(org_id,placement_run_id) REFERENCES public.intake_placement_runs(org_id,id),
  ADD CONSTRAINT review_items_intake_asset_fkey FOREIGN KEY(org_id,intake_asset_id) REFERENCES public.file_assets(org_id,id),
  ADD CONSTRAINT review_items_reason_code_check CHECK (
    (type='extraction_conflict' AND reason_code='material_candidate_conflict') OR
    (type='processing_recovery' AND reason_code IN ('invalid_model_output','provider_failed','domain_invalid')) OR
    (type='ambiguous_placement' AND reason_code='multiple_eligible_matters')
  ),
  ADD CONSTRAINT review_items_type_shape_check CHECK (
    (type='extraction_conflict' AND document_id IS NOT NULL AND document_version_id IS NOT NULL
      AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL
      AND binding_id IS NOT NULL AND candidate_sequence>0
      AND field_path ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){0,15}$'
      AND semantic_candidate_key ~ '^[a-z][a-z0-9_.:-]{0,199}$'
      AND field_decision_sequence>=0 AND processing_run_id IS NULL
      AND source_analysis_run_id IS NULL AND source_page_number IS NULL
      AND document_lifecycle_revision IS NULL)
    OR
    (type='processing_recovery' AND document_id IS NOT NULL AND document_version_id IS NOT NULL
      AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL
      AND binding_id IS NULL AND candidate_sequence IS NULL AND field_path IS NULL
      AND semantic_candidate_key IS NULL AND field_decision_sequence IS NULL AND NOT can_select
      AND processing_run_id IS NOT NULL AND source_analysis_run_id IS NOT NULL
      AND source_page_number=1 AND document_lifecycle_revision>0)
    OR
    (type='ambiguous_placement' AND document_id IS NULL AND document_version_id IS NULL
      AND intake_id IS NOT NULL AND placement_run_id IS NOT NULL AND intake_asset_id IS NOT NULL
      AND binding_id IS NULL AND candidate_sequence IS NULL AND field_path IS NULL
      AND semantic_candidate_key IS NULL AND field_decision_sequence IS NULL AND can_select
      AND processing_run_id IS NULL AND source_analysis_run_id IS NULL
      AND source_page_number=1 AND document_lifecycle_revision IS NULL)
  );

ALTER TABLE public.review_item_decisions
  DROP CONSTRAINT review_item_decisions_action_shape_check,
  ADD COLUMN placement_candidate_id uuid,
  ADD COLUMN result_matter_id uuid,
  ADD COLUMN result_document_id uuid,
  ADD COLUMN result_document_version_id uuid,
  ADD COLUMN result_lifecycle_revision bigint,
  ADD CONSTRAINT review_item_decisions_placement_candidate_fkey
    FOREIGN KEY(org_id,placement_candidate_id) REFERENCES public.intake_placement_candidates(org_id,id),
  ADD CONSTRAINT review_item_decisions_action_shape_check CHECK (
    (action='select_candidate' AND selected_candidate_id IS NOT NULL AND manual_metadata IS NULL
      AND placement_candidate_id IS NULL AND result_matter_id IS NULL AND result_document_id IS NULL
      AND result_document_version_id IS NULL AND result_lifecycle_revision IS NULL) OR
    (action='request_clarification' AND selected_candidate_id IS NULL AND manual_metadata IS NULL
      AND placement_candidate_id IS NULL AND result_matter_id IS NULL AND result_document_id IS NULL
      AND result_document_version_id IS NULL AND result_lifecycle_revision IS NULL) OR
    (action='continue_manual' AND selected_candidate_id IS NULL AND manual_metadata IS NOT NULL
      AND placement_candidate_id IS NULL AND result_matter_id IS NULL AND result_document_id IS NULL
      AND result_document_version_id IS NULL AND result_lifecycle_revision IS NULL) OR
    (action='select_destination' AND selected_candidate_id IS NULL AND manual_metadata IS NULL
      AND placement_candidate_id IS NOT NULL AND result_matter_id IS NOT NULL AND result_document_id IS NOT NULL
      AND result_document_version_id IS NOT NULL AND result_lifecycle_revision>0)
  );

CREATE FUNCTION public.produce_ambiguous_intake_placement_review(
  p_intake_id uuid,p_source_revision text,p_candidates jsonb
) RETURNS TABLE(code text,review_item_id uuid,placement_run_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE
  intake_row public.intake_items%ROWTYPE; asset_row public.file_assets%ROWTYPE;
  candidate jsonb; evidence jsonb; matter_row public.matters%ROWTYPE; client_row public.clients%ROWTYPE;
  run_id uuid; item_id uuid; candidate_id uuid; candidate_count integer;
  candidate_ids uuid[]:='{}'; candidate_ordinal integer:=0; evidence_ordinal integer;
BEGIN
  IF auth.role()<>'service_role' OR p_intake_id IS NULL OR p_source_revision IS NULL
    OR p_source_revision !~ '^[a-z][a-z0-9_.:-]{0,127}$' OR jsonb_typeof(p_candidates)<>'array'
    OR jsonb_array_length(p_candidates) NOT BETWEEN 2 AND 20 THEN
    RETURN QUERY SELECT 'invalid_request',NULL::uuid,NULL::uuid; RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_intake_id::text,804));
  SELECT * INTO intake_row FROM public.intake_items WHERE id=p_intake_id FOR UPDATE;
  IF intake_row.id IS NULL OR intake_row.intended_matter_id IS NOT NULL THEN
    RETURN QUERY SELECT 'ineligible_intake',NULL::uuid,NULL::uuid; RETURN;
  END IF;
  SELECT * INTO asset_row FROM public.file_assets
    WHERE id=intake_row.asset_id AND org_id=intake_row.org_id FOR UPDATE;
  IF intake_row.state<>'ready' OR intake_row.uploaded_by IS NULL OR asset_row.id IS NULL
    OR asset_row.availability<>'available' OR asset_row.detected_mime_type<>'application/pdf'
    OR asset_row.storage_deleted_at IS NOT NULL OR asset_row.sha256 IS NULL
    OR asset_row.validated_page_count IS NULL OR asset_row.validated_page_count<1 THEN
    RETURN QUERY SELECT 'ineligible_intake',NULL::uuid,NULL::uuid; RETURN;
  END IF;
  SELECT count(DISTINCT value->>'matter_id') INTO candidate_count
    FROM jsonb_array_elements(p_candidates) entry(value)
    WHERE public.jsonb_object_has_exact_keys(value,ARRAY['matter_id','evidence'])
      AND jsonb_typeof(value->'matter_id')='string' AND jsonb_typeof(value->'evidence')='array'
      AND jsonb_array_length(value->'evidence') BETWEEN 1 AND 20
      AND pg_input_is_valid(value->>'matter_id','uuid');
  IF candidate_count<>jsonb_array_length(p_candidates) OR candidate_count<2 THEN
    RETURN QUERY SELECT 'invalid_request',NULL::uuid,NULL::uuid; RETURN;
  END IF;
  INSERT INTO public.intake_placement_runs(org_id,intake_id,asset_id,asset_sha256,intake_updated_at,source_revision,candidate_count)
    VALUES(intake_row.org_id,intake_row.id,asset_row.id,asset_row.sha256,intake_row.updated_at,p_source_revision,candidate_count)
    ON CONFLICT(org_id,intake_id,source_revision,asset_sha256) DO NOTHING RETURNING id INTO run_id;
  IF run_id IS NULL THEN
    SELECT r.id INTO run_id FROM public.intake_placement_runs r
      WHERE r.org_id=intake_row.org_id AND r.intake_id=intake_row.id
        AND r.source_revision=p_source_revision AND r.asset_sha256=asset_row.sha256;
    SELECT i.id INTO item_id FROM public.review_items i WHERE i.placement_run_id=run_id;
    RETURN QUERY SELECT 'ok',item_id,run_id; RETURN;
  END IF;
  UPDATE public.intake_placement_runs SET state='superseded',superseded_at=now()
    WHERE org_id=intake_row.org_id AND intake_id=intake_row.id AND id<>run_id AND state='ambiguous';
  UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
    WHERE org_id=intake_row.org_id AND intake_id=intake_row.id AND status='needs_review';
  FOR candidate IN SELECT value FROM jsonb_array_elements(p_candidates) entry(value) ORDER BY value->>'matter_id' LOOP
    SELECT * INTO matter_row FROM public.matters m
      WHERE m.id=(candidate->>'matter_id')::uuid AND m.org_id=intake_row.org_id FOR SHARE;
    SELECT * INTO client_row FROM public.clients c
      WHERE c.id=matter_row.client_id AND c.org_id=intake_row.org_id FOR SHARE;
    IF matter_row.id IS NULL OR matter_row.record_state<>'active' OR matter_row.deleted_at IS NOT NULL
      OR client_row.id IS NULL OR client_row.record_state<>'active' OR client_row.deleted_at IS NOT NULL THEN
      RAISE EXCEPTION 'trusted placement candidate must be an active destination';
    END IF;
    candidate_ordinal:=candidate_ordinal+1;
    INSERT INTO public.intake_placement_candidates(org_id,placement_run_id,matter_id,matter_revision,client_id,client_revision,ordinal)
      VALUES(intake_row.org_id,run_id,matter_row.id,matter_row.revision,client_row.id,client_row.revision,candidate_ordinal) RETURNING id INTO candidate_id;
    candidate_ids:=array_append(candidate_ids,candidate_id);
    evidence_ordinal:=0;
    FOR evidence IN SELECT value FROM jsonb_array_elements(candidate->'evidence') entry(value) LOOP
      IF NOT public.jsonb_object_has_exact_keys(evidence,ARRAY['kind','source_page_number'])
        OR jsonb_typeof(evidence->'kind')<>'string'
        OR evidence->>'kind' NOT IN ('matter_code_exact','external_proceeding_id_exact','referenced_document_exact','verified_client_identifier','tax_period_overlap','procedure_compatible')
        OR (evidence->'source_page_number'<>'null'::jsonb AND
          (jsonb_typeof(evidence->'source_page_number')<>'number' OR NOT pg_input_is_valid(evidence->>'source_page_number','integer')
            OR (evidence->>'source_page_number')::integer<1
            OR (evidence->>'source_page_number')::integer>asset_row.validated_page_count)) THEN
        RAISE EXCEPTION 'invalid trusted placement evidence';
      END IF;
      evidence_ordinal:=evidence_ordinal+1;
      INSERT INTO public.intake_placement_evidence(org_id,placement_candidate_id,ordinal,kind,source_page_number)
        VALUES(intake_row.org_id,candidate_id,evidence_ordinal,(evidence->>'kind')::public.intake_placement_evidence_kind,
          CASE WHEN evidence->'source_page_number'='null'::jsonb THEN NULL ELSE (evidence->>'source_page_number')::integer END);
    END LOOP;
  END LOOP;
  INSERT INTO public.review_items(org_id,type,reason_code,impact,priority,priority_reason,can_select,dedupe_key,
    intake_id,placement_run_id,intake_asset_id,source_page_number,field_decision_sequence)
  VALUES(intake_row.org_id,'ambiguous_placement','multiple_eligible_matters',
    'Choose the eligible Matter that should receive this unassigned Intake PDF.','high',
    'Multiple active Matter destinations are supported by trusted placement evidence.',true,
    md5('ambiguous_placement:'||run_id::text),intake_row.id,run_id,asset_row.id,1,NULL)
  RETURNING id INTO item_id;
  RETURN QUERY SELECT 'ok',item_id,run_id;
END $$;

CREATE FUNCTION public.ambiguous_intake_review_lifecycle() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_TABLE_NAME='intake_items' THEN
    IF OLD.state='ready' AND NEW.state='assigned' AND EXISTS(
      SELECT 1 FROM public.review_items i WHERE i.intake_id=NEW.id AND i.type='ambiguous_placement' AND i.status='needs_review'
    ) THEN RAISE EXCEPTION 'ambiguous_intake_requires_typed_review'; END IF;
    IF NEW.state<>'ready' OR NEW.asset_id IS DISTINCT FROM OLD.asset_id OR NEW.intended_matter_id IS NOT NULL
      OR NEW.updated_at IS DISTINCT FROM OLD.updated_at THEN
      UPDATE public.review_items SET status='closed',closure_reason='source_unavailable',closed_at=now(),updated_at=now(),revision=revision+1
        WHERE intake_id=NEW.id AND type='ambiguous_placement' AND status='needs_review';
      UPDATE public.intake_placement_runs SET state='unavailable',unavailable_at=now()
        WHERE intake_id=NEW.id AND state='ambiguous';
    END IF;
  ELSIF TG_TABLE_NAME='file_assets' AND (NEW.availability IS DISTINCT FROM OLD.availability
    OR NEW.storage_deleted_at IS DISTINCT FROM OLD.storage_deleted_at
    OR NEW.sha256 IS DISTINCT FROM OLD.sha256
    OR NEW.detected_mime_type IS DISTINCT FROM OLD.detected_mime_type
    OR NEW.validated_page_count IS DISTINCT FROM OLD.validated_page_count) THEN
    UPDATE public.review_items SET status='closed',closure_reason='source_unavailable',closed_at=now(),updated_at=now(),revision=revision+1
      WHERE intake_asset_id=NEW.id AND type='ambiguous_placement' AND status='needs_review';
    UPDATE public.intake_placement_runs SET state='unavailable',unavailable_at=now()
      WHERE asset_id=NEW.id AND state='ambiguous';
  ELSIF TG_TABLE_NAME='matters' AND (NEW.record_state<>'active' OR NEW.deleted_at IS NOT NULL OR NEW.revision<>OLD.revision) THEN
    UPDATE public.review_items SET status='closed',closure_reason='source_unavailable',closed_at=now(),updated_at=now(),revision=revision+1
      WHERE type='ambiguous_placement' AND status='needs_review' AND placement_run_id IN(
        SELECT placement_run_id FROM public.intake_placement_candidates WHERE matter_id=NEW.id
      );
    UPDATE public.intake_placement_runs SET state='unavailable',unavailable_at=now()
      WHERE state='ambiguous' AND id IN(SELECT placement_run_id FROM public.intake_placement_candidates WHERE matter_id=NEW.id);
  END IF;
  RETURN NEW;
END $$;
CREATE FUNCTION public.ambiguous_intake_review_client_lifecycle() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NEW.record_state<>'active' OR NEW.deleted_at IS NOT NULL OR NEW.revision<>OLD.revision THEN
    UPDATE public.review_items SET status='closed',closure_reason='source_unavailable',closed_at=now(),updated_at=now(),revision=revision+1
      WHERE type='ambiguous_placement' AND status='needs_review' AND placement_run_id IN(
        SELECT placement_run_id FROM public.intake_placement_candidates WHERE client_id=NEW.id
      );
    UPDATE public.intake_placement_runs SET state='unavailable',unavailable_at=now()
      WHERE state='ambiguous' AND id IN(SELECT placement_run_id FROM public.intake_placement_candidates WHERE client_id=NEW.id);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER ambiguous_intake_review_intake_lifecycle AFTER UPDATE ON public.intake_items
  FOR EACH ROW EXECUTE FUNCTION public.ambiguous_intake_review_lifecycle();
CREATE TRIGGER ambiguous_intake_review_asset_lifecycle AFTER UPDATE ON public.file_assets
  FOR EACH ROW EXECUTE FUNCTION public.ambiguous_intake_review_lifecycle();
CREATE TRIGGER ambiguous_intake_review_matter_lifecycle AFTER UPDATE ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.ambiguous_intake_review_lifecycle();
CREATE TRIGGER ambiguous_intake_review_client_lifecycle AFTER UPDATE ON public.clients
  FOR EACH ROW EXECUTE FUNCTION public.ambiguous_intake_review_client_lifecycle();

DROP FUNCTION public.read_review_queue(text,text,text,text,integer,integer);
CREATE FUNCTION public.read_review_queue(
  p_status text DEFAULT 'needs_review',p_type text DEFAULT 'all',p_priority text DEFAULT 'all',
  p_search text DEFAULT '',p_page integer DEFAULT 1,p_page_size integer DEFAULT 25
) RETURNS TABLE(items jsonb,total_count bigint,can_resolve boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record;
BEGIN
  SELECT * INTO actor FROM public.review_actor(); IF actor.actor_user_id IS NULL THEN RETURN; END IF;
  IF p_status IS NULL OR p_status NOT IN ('needs_review','closed','all')
    OR p_type IS NULL OR p_type NOT IN ('extraction_conflict','processing_recovery','ambiguous_placement','all')
    OR p_priority IS NULL OR p_priority NOT IN ('normal','high','urgent','all') OR p_search IS NULL
    OR char_length(p_search)>200 OR p_page IS NULL OR p_page NOT BETWEEN 1 AND 100000
    OR p_page_size IS NULL OR p_page_size NOT BETWEEN 1 AND 50 THEN RETURN; END IF;
  RETURN QUERY WITH projected AS MATERIALIZED (
    SELECT i.id,i.type,i.field_path,i.reason_code,i.impact,i.priority,i.priority_reason,i.status,i.closure_reason,
      i.revision,i.created_at,i.document_id,i.document_version_id,i.intake_id,i.source_page_number,
      coalesce(d.display_title,s.declared_filename) document_title,
      CASE WHEN i.type='ambiguous_placement' THEN 'Multiple eligible Matters' ELSE m.title END matter_title,
      CASE WHEN i.type='ambiguous_placement' THEN 'Global Intake' ELSE c.name END client_name
    FROM public.review_items i
    LEFT JOIN public.documents d ON d.id=i.document_id AND d.org_id=i.org_id
    LEFT JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id
    LEFT JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id
    LEFT JOIN public.intake_items intake ON intake.id=i.intake_id AND intake.org_id=i.org_id
    LEFT JOIN public.upload_sessions s ON s.id=intake.upload_session_id AND s.org_id=intake.org_id
    WHERE i.org_id=actor.org_id
      AND ((i.type='ambiguous_placement' AND intake.id IS NOT NULL) OR (i.type<>'ambiguous_placement' AND public.review_document_available(i.org_id,i.document_id)))
      AND (i.status='closed' OR i.type='ambiguous_placement' OR d.current_version_id=i.document_version_id)
  ), filtered AS MATERIALIZED (SELECT * FROM projected WHERE
    (p_status='all' OR status::text=p_status) AND (p_type='all' OR type::text=p_type)
    AND (p_priority='all' OR priority::text=p_priority)
    AND (p_search='' OR strpos(lower(concat_ws(' ',field_path,reason_code,document_title,matter_title,client_name)),lower(p_search))>0)
  ), page_rows AS (SELECT * FROM filtered ORDER BY priority DESC,created_at,id LIMIT p_page_size OFFSET (p_page-1)*p_page_size)
  SELECT coalesce((SELECT jsonb_agg(to_jsonb(page_rows) ORDER BY priority DESC,created_at,id) FROM page_rows),'[]'::jsonb),
    (SELECT count(*) FROM filtered),actor.can_resolve;
END $$;

DROP FUNCTION public.read_review_detail(uuid);
CREATE FUNCTION public.read_review_detail(p_review_item_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; item public.review_items%ROWTYPE; result jsonb; source_current boolean;
BEGIN
  SELECT * INTO actor FROM public.review_actor(); IF actor.actor_user_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  IF item.id IS NULL THEN RETURN NULL; END IF;
  IF item.type='ambiguous_placement' THEN
    SELECT to_jsonb(item)||jsonb_build_object(
      'document_title',s.declared_filename,'matter_title','Multiple eligible Matters','client_name','Global Intake',
      'version_number',NULL,'is_current',intake.state='ready','source_identity','Immutable Intake PDF · Page 1',
      'allowed_actions',CASE WHEN actor.can_resolve AND item.status='needs_review' AND intake.state='ready'
        AND intake.intended_matter_id IS NULL AND asset.id=item.intake_asset_id AND asset.availability='available'
        AND asset.storage_deleted_at IS NULL AND asset.sha256=run.asset_sha256
        AND asset.detected_mime_type='application/pdf' AND asset.validated_page_count>=1
        AND intake.updated_at=run.intake_updated_at
        AND run.state='ambiguous' AND NOT EXISTS(SELECT 1 FROM public.intake_placement_candidates pc JOIN public.matters m ON m.id=pc.matter_id AND m.org_id=pc.org_id
          JOIN public.clients c ON c.id=pc.client_id AND c.org_id=pc.org_id WHERE pc.placement_run_id=run.id AND
          (m.client_id<>pc.client_id OR m.revision<>pc.matter_revision OR m.record_state<>'active' OR m.deleted_at IS NOT NULL
            OR c.revision<>pc.client_revision OR c.record_state<>'active' OR c.deleted_at IS NOT NULL))
        THEN jsonb_build_array('select_destination') ELSE '[]'::jsonb END,
      'record_baseline',NULL,'evidence',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'candidate_id',pc.id,'ordinal',pc.ordinal,'selectable',true,'page_number',1,
        'quotation','Trusted placement evidence','value',jsonb_build_object('matter_id',m.id,'matter_title',m.title,
          'matter_code',m.matter_code,'client_name',c.name,'evidence',coalesce(ev.rows,'[]'::jsonb)),
        'validation_state','eligible') ORDER BY pc.ordinal)
        FROM public.intake_placement_candidates pc JOIN public.matters m ON m.id=pc.matter_id AND m.org_id=pc.org_id
        JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id
        LEFT JOIN LATERAL (SELECT jsonb_agg(jsonb_build_object('kind',e.kind,'source_page_number',e.source_page_number) ORDER BY e.ordinal) rows
          FROM public.intake_placement_evidence e WHERE e.placement_candidate_id=pc.id) ev ON true
        WHERE pc.placement_run_id=run.id),'[]'::jsonb),
      'last_decision',(SELECT jsonb_build_object('action',d.action,'selected_candidate_id',NULL,
        'placement_candidate_id',d.placement_candidate_id,'result_matter_id',d.result_matter_id,
        'result_document_id',d.result_document_id,'result_document_version_id',d.result_document_version_id,
        'result_lifecycle_revision',d.result_lifecycle_revision,'manual_metadata',NULL,'reason',d.reason,'created_at',d.created_at)
        FROM public.review_item_decisions d WHERE d.review_item_id=item.id ORDER BY d.result_revision DESC LIMIT 1)
    ) INTO result FROM public.intake_items intake JOIN public.file_assets asset ON asset.id=intake.asset_id AND asset.org_id=intake.org_id
      JOIN public.upload_sessions s ON s.id=intake.upload_session_id AND s.org_id=intake.org_id
      JOIN public.intake_placement_runs run ON run.id=item.placement_run_id AND run.org_id=item.org_id
      WHERE intake.id=item.intake_id AND intake.org_id=item.org_id;
    RETURN result;
  END IF;
  IF NOT public.review_document_available(item.org_id,item.document_id) THEN RETURN NULL; END IF;
  source_current:=item.type='processing_recovery' AND EXISTS(SELECT 1 FROM public.source_analysis_runs r
    JOIN public.document_processing_runs p ON p.id=item.processing_run_id AND p.org_id=r.org_id
    JOIN public.document_versions v ON v.id=item.document_version_id AND v.org_id=r.org_id AND v.asset_id=r.asset_id
    WHERE r.id=item.source_analysis_run_id AND r.org_id=item.org_id AND (p.source_analysis_run_id IS NULL OR p.source_analysis_run_id=r.id)
      AND r.idempotency_key='ai_extraction.'||p.id::text AND r.analysis_state::text=CASE item.reason_code WHEN 'domain_invalid' THEN 'review_required' ELSE item.reason_code END);
  SELECT to_jsonb(item)||jsonb_build_object('document_title',d.display_title,'matter_title',m.title,'client_name',c.name,
    'version_number',v.version_number,'is_current',d.current_version_id=item.document_version_id,'source_identity','Document version '||v.version_number,
    'record_baseline',CASE WHEN item.type='extraction_conflict' THEN public.attachment_review_baseline(item.document_version_id,item.field_path) ELSE NULL END,
    'allowed_actions',CASE WHEN actor.can_resolve AND item.status='needs_review' AND d.current_version_id=item.document_version_id AND item.type='processing_recovery' AND source_current AND d.lifecycle_revision=item.document_lifecycle_revision THEN jsonb_build_array('continue_manual')
      WHEN actor.can_resolve AND item.status='needs_review' AND d.current_version_id=item.document_version_id AND item.type='extraction_conflict' THEN CASE WHEN item.can_select THEN jsonb_build_array('select_candidate','request_clarification') ELSE jsonb_build_array('request_clarification') END ELSE '[]'::jsonb END,
    'evidence',coalesce((SELECT jsonb_agg(jsonb_build_object('candidate_id',candidate.id,'ordinal',e.ordinal,'selectable',e.selectable,'page_number',candidate.page_number,'quotation',candidate.quotation,'value',candidate.normalized_value,'validation_state',candidate.validation_state) ORDER BY e.ordinal)
      FROM public.review_item_evidence e JOIN public.document_field_candidates candidate ON candidate.id=e.candidate_id AND candidate.org_id=e.org_id WHERE e.review_item_id=item.id),'[]'::jsonb),
    'last_decision',(SELECT jsonb_build_object('action',decision.action,'selected_candidate_id',decision.selected_candidate_id,'placement_candidate_id',NULL,
      'result_matter_id',NULL,'result_document_id',NULL,'result_document_version_id',NULL,'result_lifecycle_revision',NULL,
      'reason',decision.reason,'manual_metadata',decision.manual_metadata,'created_at',decision.created_at) FROM public.review_item_decisions decision WHERE decision.review_item_id=item.id ORDER BY decision.result_revision DESC LIMIT 1)
  ) INTO result FROM public.documents d JOIN public.document_versions v ON v.id=item.document_version_id AND v.document_id=d.id AND v.org_id=d.org_id
    JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id WHERE d.id=item.document_id;
  RETURN result;
END $$;

INSERT INTO public.activity_event_definitions(event_type,event_version,category,subject_types,default_visibility,metadata_contract,renderer_key)
VALUES('review.ambiguous_placement_decided',1,'review',ARRAY['document'],'matter',
  '{"action":"code","intake_id":"uuid","matter_id":"uuid","revision":"integer"}','review.ambiguous_placement_decided.v1');

CREATE FUNCTION public.resolve_ambiguous_intake_placement(
  p_review_item_id uuid,p_expected_revision bigint,p_placement_candidate_id uuid,p_reason text,p_idempotency_key uuid
) RETURNS TABLE(code text,current_item jsonb,replayed boolean,matter_id uuid,document_id uuid,document_version_id uuid,lifecycle_revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; item public.review_items%ROWTYPE; prior public.review_item_decisions%ROWTYPE;
  intake_row public.intake_items%ROWTYPE; asset_row public.file_assets%ROWTYPE; run_row public.intake_placement_runs%ROWTYPE;
  candidate_row public.intake_placement_candidates%ROWTYPE; matter_row public.matters%ROWTYPE; client_row public.clients%ROWTYPE;
  assigned record; reason_value text:=btrim(p_reason);
BEGIN
  SELECT * INTO actor FROM public.review_actor(true);
  IF actor.actor_user_id IS NULL OR NOT actor.can_resolve THEN RETURN QUERY SELECT 'forbidden',NULL::jsonb,false,NULL::uuid,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
  IF p_review_item_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1 OR p_placement_candidate_id IS NULL
    OR p_idempotency_key IS NULL OR reason_value IS NULL OR char_length(reason_value) NOT BETWEEN 1 AND 500 OR reason_value ~ '[[:cntrl:]]' THEN
    RETURN QUERY SELECT 'invalid_request',NULL::jsonb,false,NULL::uuid,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  IF item.id IS NULL OR item.type<>'ambiguous_placement' THEN RETURN QUERY SELECT 'unavailable',NULL::jsonb,false,NULL::uuid,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(item.intake_id::text,804));
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id FOR UPDATE;
  SELECT * INTO prior FROM public.review_item_decisions WHERE org_id=actor.org_id AND actor_user_id=actor.actor_user_id AND idempotency_key=p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.review_item_id<>item.id OR prior.expected_revision<>p_expected_revision OR prior.action<>'select_destination'
      OR prior.placement_candidate_id<>p_placement_candidate_id OR prior.reason<>reason_value THEN
      RETURN QUERY SELECT 'idempotency_conflict',public.read_review_detail(item.id),false,NULL::uuid,NULL::uuid,NULL::uuid,NULL::bigint;
    ELSE RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),true,prior.result_matter_id,prior.result_document_id,prior.result_document_version_id,prior.result_lifecycle_revision; END IF;
    RETURN;
  END IF;
  SELECT * INTO intake_row FROM public.intake_items WHERE id=item.intake_id AND org_id=item.org_id FOR UPDATE;
  SELECT * INTO asset_row FROM public.file_assets WHERE id=item.intake_asset_id AND org_id=item.org_id FOR UPDATE;
  SELECT * INTO run_row FROM public.intake_placement_runs WHERE id=item.placement_run_id AND org_id=item.org_id FOR UPDATE;
  SELECT * INTO candidate_row FROM public.intake_placement_candidates WHERE id=p_placement_candidate_id AND placement_run_id=run_row.id AND org_id=item.org_id;
  SELECT * INTO matter_row FROM public.matters WHERE id=candidate_row.matter_id AND org_id=item.org_id FOR UPDATE;
  SELECT * INTO client_row FROM public.clients WHERE id=candidate_row.client_id AND org_id=item.org_id FOR SHARE;
  IF item.revision<>p_expected_revision OR item.status<>'needs_review' OR run_row.state<>'ambiguous' OR candidate_row.id IS NULL
    OR intake_row.state<>'ready' OR intake_row.intended_matter_id IS NOT NULL OR intake_row.asset_id<>asset_row.id
    OR intake_row.updated_at<>run_row.intake_updated_at OR asset_row.sha256<>run_row.asset_sha256 OR asset_row.availability<>'available'
    OR asset_row.storage_deleted_at IS NOT NULL OR asset_row.detected_mime_type<>'application/pdf' OR asset_row.validated_page_count<1
    OR matter_row.revision<>candidate_row.matter_revision OR matter_row.record_state<>'active' OR matter_row.deleted_at IS NOT NULL
    OR matter_row.client_id<>candidate_row.client_id OR client_row.id IS NULL OR client_row.revision<>candidate_row.client_revision
    OR client_row.record_state<>'active' OR client_row.deleted_at IS NOT NULL THEN
    RETURN QUERY SELECT 'stale',public.read_review_detail(item.id),false,NULL::uuid,NULL::uuid,NULL::uuid,NULL::bigint; RETURN;
  END IF;
  UPDATE public.review_items SET status='closed',closure_reason='decision_recorded',closed_at=now(),updated_at=now(),revision=revision+1 WHERE id=item.id;
  UPDATE public.intake_placement_runs SET state='resolved',resolved_at=now() WHERE id=run_row.id;
  SELECT * INTO assigned FROM public.assign_intake_to_new_document(intake_row.id,matter_row.id,
    (SELECT declared_filename FROM public.upload_sessions WHERE id=intake_row.upload_session_id AND org_id=item.org_id),intake_row.uploaded_by,p_idempotency_key);
  IF assigned.code<>'ok' THEN RAISE EXCEPTION 'canonical intake assignment failed: %',assigned.code; END IF;
  INSERT INTO public.review_item_decisions(org_id,review_item_id,expected_revision,result_revision,action,selected_candidate_id,
    placement_candidate_id,result_matter_id,result_document_id,result_document_version_id,result_lifecycle_revision,manual_metadata,reason,actor_user_id,idempotency_key)
  VALUES(item.org_id,item.id,item.revision,item.revision+1,'select_destination',NULL,candidate_row.id,matter_row.id,
    assigned.document_id,assigned.document_version_id,assigned.lifecycle_revision,NULL,reason_value,actor.actor_user_id,p_idempotency_key);
  INSERT INTO public.intake_placement_decisions(org_id,placement_run_id,review_item_id,placement_candidate_id,matter_id,document_id,document_version_id,actor_user_id,reason,idempotency_key)
  VALUES(item.org_id,run_row.id,item.id,candidate_row.id,matter_row.id,assigned.document_id,assigned.document_version_id,actor.actor_user_id,reason_value,p_idempotency_key);
  PERFORM public.append_activity_event(item.org_id,'review.ambiguous_placement_decided',1::smallint,'user',actor.actor_user_id,'Member','document',
    assigned.document_id,client_row.id,matter_row.id,'Document','Intake placement decision recorded',
    jsonb_build_object('action','select_destination','intake_id',intake_row.id,'matter_id',matter_row.id,'revision',item.revision+1),
    'document',assigned.document_id,assigned.document_version_id,item.id,NULL,
    'review.placement.'||item.org_id||'.'||actor.actor_user_id||'.'||p_idempotency_key,now());
  RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),false,matter_row.id,assigned.document_id,assigned.document_version_id,assigned.lifecycle_revision;
END $$;

-- Hide ordinary assignment context while typed placement Review owns the decision.
CREATE OR REPLACE FUNCTION public.get_intake_item_triage_context(p_intake_id uuid)
RETURNS TABLE(code text,uploaded_by uuid,declared_filename text)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=pg_catalog,public AS $$
  SELECT 'ok'::text,intake.uploaded_by,session.declared_filename
  FROM public.get_my_organisation_context() actor
  JOIN public.intake_items intake ON intake.org_id=actor.org_id AND intake.id=p_intake_id
  JOIN public.upload_sessions session ON session.org_id=intake.org_id AND session.id=intake.upload_session_id
  WHERE actor.state='active' AND 'document.intake.assign'=ANY(actor.capabilities) AND auth.uid() IS NOT NULL AND intake.state='ready'
    AND NOT EXISTS(SELECT 1 FROM public.review_items r WHERE r.org_id=intake.org_id AND r.intake_id=intake.id AND r.type='ambiguous_placement' AND r.status='needs_review')
  LIMIT 1
$$;

ALTER TABLE public.intake_placement_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intake_placement_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intake_placement_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intake_placement_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intake_placement_runs FORCE ROW LEVEL SECURITY;
ALTER TABLE public.intake_placement_candidates FORCE ROW LEVEL SECURITY;
ALTER TABLE public.intake_placement_evidence FORCE ROW LEVEL SECURITY;
ALTER TABLE public.intake_placement_decisions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.intake_placement_runs,public.intake_placement_candidates,public.intake_placement_evidence,public.intake_placement_decisions FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.produce_ambiguous_intake_placement_review(uuid,text,jsonb),public.ambiguous_intake_review_lifecycle(),public.ambiguous_intake_review_client_lifecycle() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.produce_ambiguous_intake_placement_review(uuid,text,jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.read_review_queue(text,text,text,text,integer,integer),public.read_review_detail(uuid),public.resolve_ambiguous_intake_placement(uuid,bigint,uuid,text,uuid),public.get_intake_item_triage_context(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_review_queue(text,text,text,text,integer,integer),public.read_review_detail(uuid),public.resolve_ambiguous_intake_placement(uuid,bigint,uuid,text,uuid),public.get_intake_item_triage_context(uuid) TO authenticated;

COMMIT;
