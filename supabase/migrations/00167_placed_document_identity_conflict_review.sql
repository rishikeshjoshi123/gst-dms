-- D08-T05: a source-grounded self identifier contradicts a human placement.
BEGIN;
ALTER TYPE public.review_item_type ADD VALUE 'placement_conflict';
COMMIT;
BEGIN;

ALTER TABLE public.review_items DROP CONSTRAINT review_items_reason_code_check;
ALTER TABLE public.review_items ADD CONSTRAINT review_items_reason_code_check CHECK (
  (type='extraction_conflict' AND reason_code='material_candidate_conflict') OR
  (type='processing_recovery' AND reason_code IN ('invalid_model_output','provider_failed','domain_invalid')) OR
  (type='ambiguous_placement' AND reason_code='multiple_eligible_matters') OR
  (type='deadline_verification' AND reason_code='source_stated_due_date') OR
  (type='placement_conflict' AND reason_code='verified_matter_identity_mismatch'));
ALTER TABLE public.review_items DROP CONSTRAINT review_items_type_shape_check;
ALTER TABLE public.review_items ADD CONSTRAINT review_items_type_shape_check CHECK (
  (type='deadline_verification' AND document_id IS NOT NULL AND document_version_id IS NOT NULL
    AND binding_id IS NOT NULL AND candidate_sequence>0 AND field_path='document.legal_date.due'
    AND semantic_candidate_key IS NOT NULL AND field_decision_sequence>=0 AND can_select
    AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL
    AND processing_run_id IS NULL AND source_analysis_run_id IS NULL
    AND source_page_number IS NULL AND document_lifecycle_revision IS NULL)
  OR (type='extraction_conflict' AND document_id IS NOT NULL AND document_version_id IS NOT NULL
    AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL
    AND binding_id IS NOT NULL AND candidate_sequence>0 AND field_path IS NOT NULL
    AND semantic_candidate_key IS NOT NULL AND field_decision_sequence>=0
    AND processing_run_id IS NULL AND source_analysis_run_id IS NULL
    AND source_page_number IS NULL AND document_lifecycle_revision IS NULL)
  OR (type='processing_recovery' AND document_id IS NOT NULL AND document_version_id IS NOT NULL
    AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL
    AND binding_id IS NULL AND candidate_sequence IS NULL AND field_path IS NULL
    AND semantic_candidate_key IS NULL AND field_decision_sequence IS NULL AND NOT can_select
    AND processing_run_id IS NOT NULL AND source_analysis_run_id IS NOT NULL
    AND source_page_number=1 AND document_lifecycle_revision>0)
  OR (type='ambiguous_placement' AND document_id IS NULL AND document_version_id IS NULL
    AND intake_id IS NOT NULL AND placement_run_id IS NOT NULL AND intake_asset_id IS NOT NULL
    AND binding_id IS NULL AND candidate_sequence IS NULL AND field_path IS NULL
    AND semantic_candidate_key IS NULL AND field_decision_sequence IS NULL AND can_select
    AND processing_run_id IS NULL AND source_analysis_run_id IS NULL
    AND source_page_number=1 AND document_lifecycle_revision IS NULL)
  OR (type='placement_conflict' AND document_id IS NOT NULL AND document_version_id IS NOT NULL
    AND binding_id IS NOT NULL AND candidate_sequence>0
    AND field_path='document.official_reference.self_identifier'
    AND semantic_candidate_key IS NOT NULL AND field_decision_sequence>=0 AND NOT can_select
    AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL
    AND processing_run_id IS NULL AND source_analysis_run_id IS NULL
    AND source_page_number IS NOT NULL AND source_page_number>0
    AND document_lifecycle_revision>0));

CREATE TABLE public.placement_conflict_sources (
  org_id uuid NOT NULL,
  review_item_id uuid PRIMARY KEY,
  document_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  source_candidate_id uuid NOT NULL,
  source_analysis_run_id uuid NOT NULL,
  source_page_number integer NOT NULL CHECK(source_page_number>0),
  source_quote text NOT NULL CHECK(char_length(source_quote) BETWEEN 1 AND 1000 AND source_quote !~ '[[:cntrl:]]'),
  source_anchor jsonb NOT NULL,
  old_matter_id uuid NOT NULL,
  old_matter_code text NOT NULL,
  target_matter_id uuid NOT NULL,
  target_matter_code text NOT NULL,
  target_identifier_id uuid NOT NULL,
  target_identifier_revision bigint NOT NULL CHECK(target_identifier_revision>0),
  identifier_kind public.matter_identifier_kind NOT NULL,
  issuer_namespace_normalized text NOT NULL,
  normalized_value text NOT NULL,
  display_value text NOT NULL,
  target_verified_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(org_id,review_item_id) REFERENCES public.review_items(org_id,id),
  -- Historical exact locators survive governed source/key purge without
  -- retaining live candidate or identifier rows.
  CHECK(old_matter_id<>target_matter_id)
);
CREATE TABLE public.placement_conflict_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  review_item_id uuid NOT NULL,
  expected_revision bigint NOT NULL CHECK(expected_revision>0),
  result_revision bigint NOT NULL CHECK(result_revision=expected_revision+1),
  action text NOT NULL CHECK(action IN ('keep','move')),
  reason text NOT NULL CHECK(char_length(reason) BETWEEN 2 AND 500 AND reason=btrim(reason) AND reason !~ '[[:cntrl:]]'),
  actor_user_id uuid NOT NULL REFERENCES auth.users(id),
  idempotency_key uuid NOT NULL,
  request_fingerprint text NOT NULL CHECK(request_fingerprint ~ '^[0-9a-f]{64}$'),
  impact_fingerprint text,
  old_matter_id uuid NOT NULL,
  target_matter_id uuid NOT NULL,
  source_candidate_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(org_id,actor_user_id,idempotency_key),
  FOREIGN KEY(org_id,review_item_id) REFERENCES public.review_items(org_id,id),
  CHECK((action='keep' AND impact_fingerprint IS NULL) OR (action='move' AND impact_fingerprint ~ '^[0-9a-f]{64}$'))
);
CREATE TRIGGER placement_conflict_sources_immutable BEFORE UPDATE OR DELETE ON public.placement_conflict_sources
  FOR EACH ROW EXECUTE FUNCTION public.activity_events_prevent_mutation();
CREATE TRIGGER placement_conflict_decisions_immutable BEFORE UPDATE OR DELETE ON public.placement_conflict_decisions
  FOR EACH ROW EXECUTE FUNCTION public.activity_events_prevent_mutation();
ALTER TABLE public.placement_conflict_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.placement_conflict_sources FORCE ROW LEVEL SECURITY;
ALTER TABLE public.placement_conflict_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.placement_conflict_decisions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.placement_conflict_sources,public.placement_conflict_decisions FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO public.activity_event_definitions(event_type,event_version,category,subject_types,default_visibility,metadata_contract,renderer_key)
VALUES('review.placement_conflict_decided',1,'review',ARRAY['document'],'matter',
  '{"action":"code","revision":"integer"}','review.placement_conflict_decided.v1');

-- The producer accepts no browser/provider destination. A canonical printed
-- self identifier must exactly match one active human-verified Matter key.
CREATE FUNCTION public.reconcile_placed_document_identity_conflict(p_document_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE d public.documents%ROWTYPE; source record; item_id uuid; key text; target_count integer; prior_count integer;
BEGIN
  SELECT * INTO d FROM public.documents WHERE id=p_document_id FOR UPDATE;
  IF d.id IS NULL THEN RETURN; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(d.id::text,805));
  IF NOT public.review_document_available(d.org_id,d.id)
    OR NOT EXISTS(SELECT 1 FROM public.document_versions v JOIN public.file_assets asset
      ON asset.id=v.asset_id AND asset.org_id=v.org_id
      WHERE v.id=d.current_version_id AND v.org_id=d.org_id AND v.document_id=d.id
        AND v.state='current' AND v.validation_state='valid'
        AND asset.availability='available' AND asset.storage_deleted_at IS NULL)
    OR d.content_availability NOT IN ('source_attached','source_indexed') THEN
    UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
      WHERE org_id=d.org_id AND document_id=d.id AND type='placement_conflict' AND status='needs_review';
    RETURN;
  END IF;
  SELECT count(DISTINCT identifier.matter_id) INTO target_count
  FROM public.document_field_candidates c
  JOIN public.source_field_candidates s ON s.id=c.source_field_candidate_id AND s.org_id=c.org_id
  JOIN public.document_version_analysis_bindings b ON b.id=c.document_version_analysis_binding_id AND b.org_id=c.org_id
  JOIN public.matter_identifiers identifier ON identifier.org_id=c.org_id
    AND identifier.identifier_kind::text=c.normalized_value->>'kind'
    AND identifier.issuer_namespace_normalized=c.normalized_value->>'namespace_normalized'
    AND identifier.normalized_value=c.normalized_value->>'normalized_value'
  WHERE c.org_id=d.org_id AND c.document_id=d.id AND c.document_version_id=d.current_version_id
    AND c.field_path='document.official_reference.self_identifier' AND c.value_type='structured'
    AND c.validation_state<>'invalid' AND c.normalized_value->>'role'='self_identifier'
    AND c.normalized_value->>'completeness'='complete' AND c.normalized_value->>'match_eligible'='true'
    AND c.normalized_value->>'kind'<>'other_official_reference'
    AND s.verified_source_anchor IS NOT NULL AND b.source_analysis_run_id=s.source_analysis_run_id
    AND identifier.lifecycle_state='active' AND identifier.identity_eligible
    AND identifier.identifier_role='self_identifier' AND identifier.verification_method='human_source'
    AND identifier.verified_at IS NOT NULL AND identifier.evidence_purged_at IS NULL
    AND identifier.matter_id<>d.matter_id
    AND EXISTS(SELECT 1 FROM public.matters m JOIN public.clients client ON client.id=m.client_id AND client.org_id=m.org_id
      WHERE m.id=identifier.matter_id AND m.org_id=d.org_id AND m.record_state='active' AND m.deleted_at IS NULL
        AND client.record_state='active' AND client.deleted_at IS NULL);
  IF target_count<>1 THEN
    UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
      WHERE org_id=d.org_id AND document_id=d.id AND type='placement_conflict' AND status='needs_review';
    RETURN;
  END IF;
  SELECT c.*,s.source_analysis_run_id,s.verified_source_anchor,identifier.id AS identifier_id,
    identifier.matter_id AS verified_target_matter_id,identifier.revision AS identifier_revision,
    identifier.verified_at AS identifier_verified_at,identifier.display_value AS verified_display
  INTO source
  FROM public.document_field_candidates c
  JOIN public.source_field_candidates s ON s.id=c.source_field_candidate_id AND s.org_id=c.org_id
  JOIN public.document_version_analysis_bindings b ON b.id=c.document_version_analysis_binding_id AND b.org_id=c.org_id
  JOIN public.matter_identifiers identifier ON identifier.org_id=c.org_id
    AND identifier.identifier_kind::text=c.normalized_value->>'kind'
    AND identifier.issuer_namespace_normalized=c.normalized_value->>'namespace_normalized'
    AND identifier.normalized_value=c.normalized_value->>'normalized_value'
  WHERE c.org_id=d.org_id AND c.document_id=d.id AND c.document_version_id=d.current_version_id
    AND c.field_path='document.official_reference.self_identifier' AND c.value_type='structured'
    AND c.validation_state<>'invalid' AND c.normalized_value->>'role'='self_identifier'
    AND c.normalized_value->>'completeness'='complete' AND c.normalized_value->>'match_eligible'='true'
    AND c.normalized_value->>'kind'<>'other_official_reference'
    AND s.verified_source_anchor IS NOT NULL AND b.source_analysis_run_id=s.source_analysis_run_id
    AND identifier.lifecycle_state='active' AND identifier.identity_eligible
    AND identifier.identifier_role='self_identifier' AND identifier.verification_method='human_source'
    AND identifier.verified_at IS NOT NULL AND identifier.evidence_purged_at IS NULL
    AND identifier.matter_id<>d.matter_id
    AND EXISTS(SELECT 1 FROM public.matters m JOIN public.clients client ON client.id=m.client_id AND client.org_id=m.org_id
      WHERE m.id=identifier.matter_id AND m.org_id=d.org_id AND m.record_state='active' AND m.deleted_at IS NULL
        AND client.record_state='active' AND client.deleted_at IS NULL)
  ORDER BY c.id,identifier.id LIMIT 1;
  IF source.id IS NULL THEN RETURN; END IF;
  -- Negative human learning suppresses an unchanged printed source/key pair.
  IF EXISTS(SELECT 1 FROM public.placement_conflict_decisions decision
    WHERE decision.org_id=d.org_id AND decision.action='keep' AND decision.document_version_id=d.current_version_id
      AND decision.source_candidate_id=source.id AND decision.old_matter_id=d.matter_id
      AND decision.target_matter_id=source.verified_target_matter_id) THEN
    UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
      WHERE org_id=d.org_id AND document_id=d.id AND type='placement_conflict' AND status='needs_review';
    RETURN;
  END IF;
  UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
    WHERE org_id=d.org_id AND document_id=d.id AND type='placement_conflict' AND status='needs_review'
      AND NOT EXISTS(SELECT 1 FROM public.placement_conflict_sources prior_source
        WHERE prior_source.review_item_id=review_items.id AND prior_source.document_version_id=d.current_version_id
          AND prior_source.source_candidate_id=source.id AND prior_source.old_matter_id=d.matter_id
          AND prior_source.target_matter_id=source.verified_target_matter_id
          AND prior_source.target_identifier_id=source.identifier_id
          AND prior_source.target_identifier_revision=source.identifier_revision);
  IF EXISTS(SELECT 1 FROM public.review_items current_item
    JOIN public.placement_conflict_sources current_source ON current_source.review_item_id=current_item.id
    WHERE current_item.org_id=d.org_id AND current_item.document_id=d.id
      AND current_item.type='placement_conflict' AND current_item.status='needs_review'
      AND current_source.document_version_id=d.current_version_id
      AND current_source.source_candidate_id=source.id AND current_source.old_matter_id=d.matter_id
      AND current_source.target_matter_id=source.verified_target_matter_id
      AND current_source.target_identifier_id=source.identifier_id
      AND current_source.target_identifier_revision=source.identifier_revision) THEN RETURN; END IF;
  SELECT count(*) INTO prior_count FROM public.review_items prior_item
    JOIN public.placement_conflict_sources prior_source ON prior_source.review_item_id=prior_item.id
    WHERE prior_item.org_id=d.org_id AND prior_item.document_id=d.id AND prior_item.type='placement_conflict'
      AND prior_source.document_version_id=d.current_version_id AND prior_source.source_candidate_id=source.id
      AND prior_source.old_matter_id=d.matter_id AND prior_source.target_matter_id=source.verified_target_matter_id
      AND prior_source.target_identifier_id=source.identifier_id
      AND prior_source.target_identifier_revision=source.identifier_revision;
  key:=md5('placement_conflict:'||d.id::text||':'||d.current_version_id::text||':'||d.matter_id::text||':'||
    source.verified_target_matter_id::text||':'||source.id::text||':'||source.identifier_id::text||':'||
    source.identifier_revision::text||':'||prior_count::text);
  INSERT INTO public.review_items(org_id,document_id,document_version_id,binding_id,candidate_sequence,type,reason_code,
    field_path,semantic_candidate_key,impact,priority,priority_reason,can_select,field_decision_sequence,dedupe_key,
    source_page_number,document_lifecycle_revision)
  VALUES(d.org_id,d.id,d.current_version_id,source.document_version_analysis_binding_id,source.materialization_sequence,
    'placement_conflict','verified_matter_identity_mismatch','document.official_reference.self_identifier',source.semantic_candidate_key,
    'Current filing remains unchanged. Review the exact source and a current Move impact before deciding.',
    'high','A verified proceeding key contradicts the current filing.',false,0,key,source.page_number,d.lifecycle_revision)
  RETURNING id INTO item_id;
  INSERT INTO public.placement_conflict_sources(org_id,review_item_id,document_id,document_version_id,
    source_candidate_id,source_analysis_run_id,source_page_number,source_quote,source_anchor,
    old_matter_id,old_matter_code,target_matter_id,target_matter_code,target_identifier_id,target_identifier_revision,
    identifier_kind,issuer_namespace_normalized,normalized_value,display_value,target_verified_at)
  SELECT d.org_id,item_id,d.id,d.current_version_id,source.id,source.source_analysis_run_id,source.page_number,
    source.quotation,source.verified_source_anchor,d.matter_id,coalesce(old_m.matter_code,old_m.id::text),source.verified_target_matter_id,
    coalesce(target_m.matter_code,target_m.id::text),source.identifier_id,source.identifier_revision,
    (source.normalized_value->>'kind')::public.matter_identifier_kind,source.normalized_value->>'namespace_normalized',
    source.normalized_value->>'normalized_value',source.verified_display,source.identifier_verified_at
  FROM public.matters old_m,public.matters target_m WHERE old_m.id=d.matter_id AND target_m.id=source.verified_target_matter_id;
END $$;

-- Candidate INSERT is too early: the extraction-conflict reconciler runs after
-- materialization and must not close this separate decision boundary.
CREATE FUNCTION public.placed_identity_verified_key_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE document_id_value uuid;
BEGIN
  IF NEW.identity_eligible AND NEW.identifier_role='self_identifier' AND NEW.verification_method='human_source' THEN
    FOR document_id_value IN SELECT DISTINCT c.document_id FROM public.document_field_candidates c
      WHERE c.org_id=NEW.org_id AND c.field_path='document.official_reference.self_identifier'
        AND c.normalized_value->>'kind'=NEW.identifier_kind::text
        AND c.normalized_value->>'namespace_normalized'=NEW.issuer_namespace_normalized
        AND c.normalized_value->>'normalized_value'=NEW.normalized_value
    LOOP PERFORM public.reconcile_placed_document_identity_conflict(document_id_value); END LOOP;
  END IF;
  IF TG_OP='UPDATE' AND OLD.lifecycle_state='active' AND NEW.lifecycle_state<>'active' THEN
    UPDATE public.review_items i SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
      FROM public.placement_conflict_sources source
      WHERE source.review_item_id=i.id AND source.target_identifier_id=NEW.id AND i.status='needs_review';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER placed_identity_verified_key_changed AFTER INSERT OR UPDATE OF lifecycle_state,revision ON public.matter_identifiers
  FOR EACH ROW EXECUTE FUNCTION public.placed_identity_verified_key_changed();
-- Governed Matter Trash/Restore changes target availability without changing
-- the immutable verified identifier row. Reevaluate only printed keys owned
-- by that Matter, not every document in the organisation.
CREATE FUNCTION public.placed_identity_target_matter_availability_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE document_id_value uuid;
BEGIN
  IF NEW.record_state IS DISTINCT FROM OLD.record_state OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at THEN
    FOR document_id_value IN
      SELECT DISTINCT c.document_id FROM public.matter_identifiers identifier
      JOIN public.document_field_candidates c ON c.org_id=identifier.org_id
        AND c.field_path='document.official_reference.self_identifier'
        AND c.normalized_value->>'kind'=identifier.identifier_kind::text
        AND c.normalized_value->>'namespace_normalized'=identifier.issuer_namespace_normalized
        AND c.normalized_value->>'normalized_value'=identifier.normalized_value
      WHERE identifier.org_id=NEW.org_id AND identifier.matter_id=NEW.id
        AND identifier.lifecycle_state='active' AND identifier.identity_eligible
        AND identifier.identifier_role='self_identifier' AND identifier.verification_method='human_source'
    LOOP PERFORM public.reconcile_placed_document_identity_conflict(document_id_value); END LOOP;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER placed_identity_target_matter_availability_changed
  AFTER UPDATE OF record_state,deleted_at ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.placed_identity_target_matter_availability_changed();
CREATE FUNCTION public.placed_identity_filing_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NEW.matter_id IS DISTINCT FROM OLD.matter_id
    AND current_setting('casechain.placement_review_move',true) IS DISTINCT FROM 'on' THEN
    UPDATE public.review_items item SET status='closed',closure_reason='source_replaced',
      closed_at=now(),updated_at=now(),revision=revision+1
      FROM public.placement_conflict_sources source
      WHERE source.review_item_id=item.id AND item.org_id=NEW.org_id AND item.document_id=NEW.id
        AND item.type='placement_conflict' AND item.status='needs_review';
    PERFORM public.reconcile_placed_document_identity_conflict(NEW.id);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER placed_identity_filing_changed AFTER UPDATE OF matter_id ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.placed_identity_filing_changed();

-- An extraction-field reconciliation must never close another Review type
-- merely because it shares the printed self-identifier field path.
CREATE OR REPLACE FUNCTION public.reconcile_extraction_conflict_review(p_binding_id uuid,p_create boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE binding public.document_version_analysis_bindings%ROWTYPE; group_row record; item_id uuid;
  selectable_count integer; candidate_ids uuid[]; key text; conflict boolean; baseline_conflict boolean;
BEGIN
  SELECT * INTO binding FROM public.document_version_analysis_bindings WHERE id=p_binding_id;
  IF binding.id IS NULL OR NOT public.review_document_available(binding.org_id,binding.document_id)
    OR NOT EXISTS(SELECT 1 FROM public.documents WHERE id=binding.document_id AND current_version_id=binding.document_version_id) THEN RETURN; END IF;
  FOR group_row IN
    SELECT DISTINCT c.field_path,c.semantic_candidate_key FROM public.document_field_candidates c
    WHERE c.document_version_analysis_binding_id=binding.id
  LOOP
    SELECT array_agg(c.id ORDER BY c.id),count(DISTINCT public.review_candidate_value(c.normalized_value))
      FILTER(WHERE c.validation_state IN ('eligible','provisional') AND coalesce(c.normalized_value->>'conflict','false')<>'true'),
      coalesce(bool_or(c.validation_state='conflicting'),false)
        OR count(DISTINCT public.review_candidate_value(c.normalized_value)) FILTER(WHERE c.validation_state IN ('eligible','provisional'))>1
    INTO candidate_ids,selectable_count,conflict
    FROM public.review_comparison_candidates(binding.id,group_row.field_path,group_row.semantic_candidate_key,p_create) c;
    SELECT coalesce(bool_or(public.attachment_scalar_disagrees(binding.document_version_id,c.field_path,c.semantic_candidate_key,c.normalized_value)),false)
      INTO baseline_conflict FROM public.document_field_candidates c
      WHERE c.id=ANY(candidate_ids) AND c.validation_state IN ('eligible','provisional');
    conflict:=conflict OR baseline_conflict;
    IF NOT conflict THEN
      UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
        WHERE org_id=binding.org_id AND document_id=binding.document_id AND document_version_id=binding.document_version_id
          AND field_path=group_row.field_path AND semantic_candidate_key=group_row.semantic_candidate_key
          AND type='extraction_conflict' AND status='needs_review';
      CONTINUE;
    END IF;
    IF NOT p_create THEN CONTINUE; END IF;
    key:=md5(binding.document_version_id::text||':'||group_row.field_path||':'||group_row.semantic_candidate_key||':'||candidate_ids::text);
    IF EXISTS(SELECT 1 FROM public.review_items WHERE dedupe_key=key) THEN CONTINUE; END IF;
    UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
      WHERE org_id=binding.org_id AND document_id=binding.document_id AND document_version_id=binding.document_version_id
        AND field_path=group_row.field_path AND semantic_candidate_key=group_row.semantic_candidate_key
        AND type='extraction_conflict' AND status='needs_review';
    INSERT INTO public.review_items(org_id,document_id,document_version_id,binding_id,candidate_sequence,
      field_path,semantic_candidate_key,can_select,dedupe_key,field_decision_sequence)
    VALUES(binding.org_id,binding.document_id,binding.document_version_id,binding.id,
      (SELECT max(materialization_sequence) FROM public.document_field_candidates
        WHERE document_version_id=binding.document_version_id AND field_path=group_row.field_path
          AND semantic_candidate_key=group_row.semantic_candidate_key),group_row.field_path,group_row.semantic_candidate_key,
      selectable_count>=2 AND NOT baseline_conflict,key,
      (SELECT coalesce(max(decision_sequence),0) FROM public.document_field_decisions
        WHERE document_version_id=binding.document_version_id AND field_path=group_row.field_path
          AND semantic_candidate_key=group_row.semantic_candidate_key)) RETURNING id INTO item_id;
    INSERT INTO public.review_item_evidence(org_id,review_item_id,candidate_id,ordinal,selectable)
      SELECT binding.org_id,item_id,c.id,row_number() OVER(ORDER BY c.page_number,c.materialization_sequence,c.id),
        selectable_count>=2 AND NOT baseline_conflict AND c.validation_state IN ('eligible','provisional')
          AND coalesce(c.normalized_value->>'conflict','false')<>'true'
      FROM public.document_field_candidates c WHERE c.id=ANY(candidate_ids);
  END LOOP;
  PERFORM public.recompute_document_effective_metadata(binding.document_version_id);
END $$;

ALTER FUNCTION public.materialize_document_version_analysis(uuid,uuid,text,uuid)
  RENAME TO materialize_document_version_analysis_before_placement_conflict;
CREATE FUNCTION public.materialize_document_version_analysis(
  p_document_version_id uuid,p_source_analysis_run_id uuid,p_binding_reason text,p_created_by uuid DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE bound_id uuid; document_id_value uuid;
BEGIN
  bound_id:=public.materialize_document_version_analysis_before_placement_conflict(
    p_document_version_id,p_source_analysis_run_id,p_binding_reason,p_created_by);
  IF p_binding_reason<>'processing_ai_extraction' AND bound_id IS NOT NULL THEN
    SELECT document_id INTO document_id_value FROM public.document_version_analysis_bindings WHERE id=bound_id;
    PERFORM public.reconcile_placed_document_identity_conflict(document_id_value);
  END IF;
  RETURN bound_id;
END $$;
ALTER FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb)
  RENAME TO finish_ai_extraction_before_placement_conflict;
CREATE FUNCTION public.finish_document_processing_ai_extraction(
  p_processing_run_id uuid,p_processing_lease_token uuid,p_source_analysis_run_id uuid,
  p_source_analysis_lease_token uuid,p_outcome text,p_input_tokens bigint,p_output_tokens bigint,
  p_latency_ms integer,p_candidates jsonb DEFAULT '[]',p_review_required boolean DEFAULT false,
  p_legacy_metadata jsonb DEFAULT NULL
) RETURNS TABLE(code text,binding_id uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE finished record; document_id_value uuid;
BEGIN
  SELECT * INTO finished FROM public.finish_ai_extraction_before_placement_conflict(
    p_processing_run_id,p_processing_lease_token,p_source_analysis_run_id,p_source_analysis_lease_token,
    p_outcome,p_input_tokens,p_output_tokens,p_latency_ms,p_candidates,p_review_required,p_legacy_metadata);
  IF p_outcome='validated' AND finished.code IN ('validated','review_required') AND finished.binding_id IS NOT NULL THEN
    SELECT document_id INTO document_id_value FROM public.document_version_analysis_bindings WHERE id=finished.binding_id;
    PERFORM public.reconcile_placed_document_identity_conflict(document_id_value);
  END IF;
  RETURN QUERY SELECT finished.code::text,finished.binding_id::uuid;
END $$;

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
    OR p_type IS NULL OR p_type NOT IN ('extraction_conflict','processing_recovery','ambiguous_placement','deadline_verification','placement_conflict','all')
    OR p_priority IS NULL OR p_priority NOT IN ('normal','high','urgent','all')
    OR p_search IS NULL OR char_length(p_search)>200 OR p_page IS NULL OR p_page NOT BETWEEN 1 AND 100000
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
      AND ((i.type='ambiguous_placement' AND intake.id IS NOT NULL)
        OR (i.type<>'ambiguous_placement' AND public.review_document_available(i.org_id,i.document_id)))
      AND (i.status='closed' OR i.type='ambiguous_placement' OR d.current_version_id=i.document_version_id)
  ), filtered AS MATERIALIZED (SELECT * FROM projected WHERE
    (p_status='all' OR status::text=p_status) AND (p_type='all' OR type::text=p_type)
    AND (p_priority='all' OR priority::text=p_priority)
    AND (p_search='' OR strpos(lower(concat_ws(' ',field_path,reason_code,document_title,matter_title,client_name)),lower(p_search))>0)
  ), page_rows AS (SELECT * FROM filtered ORDER BY priority DESC,created_at,id LIMIT p_page_size OFFSET (p_page-1)*p_page_size)
  SELECT coalesce((SELECT jsonb_agg(to_jsonb(page_rows) ORDER BY priority DESC,created_at,id) FROM page_rows),'[]'::jsonb),
    (SELECT count(*) FROM filtered),actor.can_resolve;
END $$;

ALTER FUNCTION public.read_review_detail(uuid) RENAME TO read_review_detail_before_placement_conflict;
CREATE FUNCTION public.read_review_detail(p_review_item_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; item public.review_items%ROWTYPE; source public.placement_conflict_sources%ROWTYPE; result jsonb;
  current_fact boolean;
BEGIN
  SELECT * INTO actor FROM public.review_actor();
  IF actor.actor_user_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  IF item.id IS NULL THEN RETURN NULL; END IF;
  IF item.type<>'placement_conflict' THEN RETURN public.read_review_detail_before_placement_conflict(p_review_item_id); END IF;
  IF NOT public.review_document_available(item.org_id,item.document_id) THEN RETURN NULL; END IF;
  SELECT * INTO source FROM public.placement_conflict_sources WHERE review_item_id=item.id AND org_id=item.org_id;
  IF source.review_item_id IS NULL THEN RETURN NULL; END IF;
  SELECT item.status='needs_review' AND d.current_version_id=source.document_version_id
    AND d.matter_id=source.old_matter_id AND identifier.lifecycle_state='active'
    AND identifier.revision=source.target_identifier_revision AND identifier.identity_eligible
    AND identifier.identifier_role='self_identifier' AND identifier.verification_method='human_source'
    AND identifier.matter_id=source.target_matter_id
    AND public.review_document_available(item.org_id,item.document_id)
    AND EXISTS(SELECT 1 FROM public.document_versions current_v JOIN public.file_assets asset
      ON asset.id=current_v.asset_id AND asset.org_id=current_v.org_id
      WHERE current_v.id=d.current_version_id AND current_v.org_id=d.org_id AND current_v.document_id=d.id
        AND current_v.state='current' AND current_v.validation_state='valid'
        AND asset.availability='available' AND asset.storage_deleted_at IS NULL)
    AND target_m.record_state='active' AND target_m.deleted_at IS NULL
    AND target_c.record_state='active' AND target_c.deleted_at IS NULL
  INTO current_fact FROM public.documents d
    JOIN public.matter_identifiers identifier ON identifier.id=source.target_identifier_id AND identifier.org_id=d.org_id
    JOIN public.matters target_m ON target_m.id=source.target_matter_id AND target_m.org_id=d.org_id
    JOIN public.clients target_c ON target_c.id=target_m.client_id AND target_c.org_id=d.org_id
    WHERE d.id=item.document_id AND d.org_id=item.org_id;
  SELECT to_jsonb(item)||jsonb_build_object(
    'document_title',d.display_title,'matter_title',old_m.title,'client_name',old_c.name,
    'version_number',v.version_number,'is_current',d.current_version_id=item.document_version_id,
    'source_identity','Document version '||v.version_number,
    'record_baseline',NULL,'conflict_current',coalesce(current_fact,false),
    'allowed_actions',CASE WHEN actor.can_resolve AND current_fact THEN jsonb_build_array('keep_placement','move_placement') ELSE '[]'::jsonb END,
    'old_matter_id',source.old_matter_id,'old_matter_code',source.old_matter_code,
    'target_matter_id',source.target_matter_id,'target_matter_code',source.target_matter_code,
    'target_matter_title',target_m.title,'target_client_name',target_c.name,
    'target_identifier_id',source.target_identifier_id,'target_identifier_revision',source.target_identifier_revision,
    'identifier_kind',source.identifier_kind,'issuer_namespace_normalized',source.issuer_namespace_normalized,
    'normalized_value',source.normalized_value,'display_value',source.display_value,
    'target_verified_at',source.target_verified_at,'source_analysis_run_id',source.source_analysis_run_id,
    'source_candidate_id',source.source_candidate_id,'source_page_number',source.source_page_number,
    'source_quote',source.source_quote,
    'evidence',jsonb_build_array(jsonb_build_object('candidate_id',source.source_candidate_id,'ordinal',1,
      'selectable',false,'page_number',source.source_page_number,'quotation',source.source_quote,
      'value',jsonb_build_object('display',source.display_value,'kind',source.identifier_kind,
        'namespace',source.issuer_namespace_normalized),'validation_state','provisional')),
    'last_decision',(SELECT jsonb_build_object('action',decision.action,'selected_candidate_id',NULL,
      'reason',decision.reason,'created_at',decision.created_at)
      FROM public.placement_conflict_decisions decision WHERE decision.review_item_id=item.id
      ORDER BY decision.created_at DESC,decision.id DESC LIMIT 1)
  ) INTO result FROM public.documents d
    JOIN public.document_versions v ON v.id=source.document_version_id AND v.org_id=d.org_id AND v.document_id=d.id
    JOIN public.matters old_m ON old_m.id=source.old_matter_id AND old_m.org_id=d.org_id
    JOIN public.clients old_c ON old_c.id=old_m.client_id AND old_c.org_id=d.org_id
    JOIN public.matters target_m ON target_m.id=source.target_matter_id AND target_m.org_id=d.org_id
    JOIN public.clients target_c ON target_c.id=target_m.client_id AND target_c.org_id=d.org_id
    WHERE d.id=item.document_id AND d.org_id=item.org_id;
  RETURN result;
END $$;

CREATE FUNCTION public.preview_placement_conflict_move(p_review_item_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; item public.review_items%ROWTYPE; source public.placement_conflict_sources%ROWTYPE;
BEGIN
  SELECT * INTO actor FROM public.review_actor();
  IF actor.actor_user_id IS NULL OR NOT actor.can_resolve THEN RETURN jsonb_build_object('code','forbidden'); END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  SELECT * INTO source FROM public.placement_conflict_sources WHERE review_item_id=item.id AND org_id=actor.org_id;
  IF item.type<>'placement_conflict' OR item.status<>'needs_review' OR source.review_item_id IS NULL
    OR NOT EXISTS(SELECT 1 FROM public.documents d WHERE d.id=item.document_id AND d.org_id=actor.org_id
      AND d.current_version_id=source.document_version_id AND d.matter_id=source.old_matter_id)
    OR NOT EXISTS(SELECT 1 FROM public.matter_identifiers identifier WHERE identifier.id=source.target_identifier_id
      AND identifier.org_id=actor.org_id AND identifier.revision=source.target_identifier_revision
      AND identifier.lifecycle_state='active' AND identifier.identity_eligible AND identifier.matter_id=source.target_matter_id)
    THEN RETURN jsonb_build_object('code','stale'); END IF;
  RETURN public.preview_document_boundary_repair(item.document_id,source.target_matter_id,'move');
END $$;

CREATE FUNCTION public.resolve_placement_conflict(
  p_review_item_id uuid,p_expected_revision bigint,p_action text,p_expected_impact_fingerprint text,
  p_reason text,p_idempotency_key uuid
) RETURNS TABLE(code text,current_item jsonb,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public SET lock_timeout='5s' AS $$
DECLARE actor record; item public.review_items%ROWTYPE; source public.placement_conflict_sources%ROWTYPE;
  prior public.placement_conflict_decisions%ROWTYPE; d public.documents%ROWTYPE; identifier public.matter_identifiers%ROWTYPE;
  impact jsonb; moved jsonb; request_hash text; client_id_value uuid;
BEGIN
  IF p_review_item_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1
    OR p_action NOT IN ('keep','move') OR p_idempotency_key IS NULL
    OR p_reason IS NULL OR p_reason<>btrim(p_reason) OR char_length(p_reason) NOT BETWEEN 2 AND 500
    OR p_reason ~ '[[:cntrl:]]'
    OR (p_action='keep' AND p_expected_impact_fingerprint IS NOT NULL)
    OR (p_action='move' AND (p_expected_impact_fingerprint IS NULL OR p_expected_impact_fingerprint !~ '^[0-9a-f]{64}$'))
    THEN RETURN QUERY SELECT 'invalid_request',NULL::jsonb,false; RETURN; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text,8051));
  SELECT * INTO actor FROM public.review_actor(true);
  IF actor.actor_user_id IS NULL OR NOT actor.can_resolve THEN
    RETURN QUERY SELECT 'forbidden',NULL::jsonb,false; RETURN; END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  IF item.id IS NULL OR item.type<>'placement_conflict' THEN
    RETURN QUERY SELECT 'unavailable',NULL::jsonb,false; RETURN; END IF;
  SELECT * INTO d FROM public.documents WHERE id=item.document_id AND org_id=actor.org_id FOR UPDATE;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id FOR UPDATE;
  SELECT * INTO source FROM public.placement_conflict_sources WHERE review_item_id=item.id AND org_id=actor.org_id;
  request_hash:=encode(extensions.digest(convert_to(jsonb_build_array(p_review_item_id,p_expected_revision,p_action,
    p_expected_impact_fingerprint,p_reason)::text,'utf8'),'sha256'),'hex');
  SELECT * INTO prior FROM public.placement_conflict_decisions decision
    WHERE decision.org_id=actor.org_id AND decision.actor_user_id=actor.actor_user_id
      AND decision.idempotency_key=p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.request_fingerprint=request_hash THEN
      RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),true;
    ELSE RETURN QUERY SELECT 'idempotency_conflict',public.read_review_detail(item.id),false; END IF;
    RETURN;
  END IF;
  SELECT * INTO identifier FROM public.matter_identifiers WHERE id=source.target_identifier_id AND org_id=actor.org_id FOR SHARE;
  IF source.review_item_id IS NULL OR d.id IS NULL OR item.status<>'needs_review' OR item.revision<>p_expected_revision
    OR d.current_version_id IS DISTINCT FROM source.document_version_id
    OR d.matter_id IS DISTINCT FROM source.old_matter_id OR NOT public.review_document_available(actor.org_id,d.id)
    OR NOT EXISTS(SELECT 1 FROM public.document_versions current_v JOIN public.file_assets asset
      ON asset.id=current_v.asset_id AND asset.org_id=current_v.org_id
      WHERE current_v.id=d.current_version_id AND current_v.org_id=d.org_id AND current_v.document_id=d.id
        AND current_v.state='current' AND current_v.validation_state='valid'
        AND asset.availability='available' AND asset.storage_deleted_at IS NULL)
    OR identifier.id IS NULL OR identifier.lifecycle_state<>'active' OR NOT identifier.identity_eligible
    OR identifier.identifier_role<>'self_identifier' OR identifier.verification_method<>'human_source'
    OR identifier.revision<>source.target_identifier_revision OR identifier.matter_id<>source.target_matter_id
    OR identifier.identifier_kind<>source.identifier_kind
    OR identifier.issuer_namespace_normalized<>source.issuer_namespace_normalized
    OR identifier.normalized_value<>source.normalized_value
    OR NOT EXISTS(SELECT 1 FROM public.document_field_candidates c
      JOIN public.source_field_candidates s ON s.id=c.source_field_candidate_id AND s.org_id=c.org_id
      JOIN public.document_version_analysis_bindings b ON b.id=c.document_version_analysis_binding_id AND b.org_id=c.org_id
      WHERE c.id=source.source_candidate_id AND c.org_id=actor.org_id
        AND c.document_id=d.id AND c.document_version_id=d.current_version_id
        AND c.field_path='document.official_reference.self_identifier'
        AND c.page_number=source.source_page_number AND c.quotation=source.source_quote
        AND c.normalized_value->>'kind'=source.identifier_kind::text
        AND c.normalized_value->>'namespace_normalized'=source.issuer_namespace_normalized
        AND c.normalized_value->>'normalized_value'=source.normalized_value
        AND c.normalized_value->>'role'='self_identifier' AND c.normalized_value->>'completeness'='complete'
        AND c.normalized_value->>'match_eligible'='true' AND c.validation_state<>'invalid'
        AND s.source_analysis_run_id=source.source_analysis_run_id
        AND s.verified_source_anchor=source.source_anchor AND b.source_analysis_run_id=s.source_analysis_run_id)
    THEN RETURN QUERY SELECT 'stale',public.read_review_detail(item.id),false; RETURN; END IF;
  IF p_action='move' THEN
    impact:=public.preview_document_boundary_repair(d.id,source.target_matter_id,'move');
    IF impact->>'code'<>'ok' OR impact->>'fingerprint'<>p_expected_impact_fingerprint
      THEN RETURN QUERY SELECT 'stale_preview',public.read_review_detail(item.id),false; RETURN; END IF;
    IF jsonb_array_length(impact->'blockers')>0 THEN
      RETURN QUERY SELECT 'blocked',public.read_review_detail(item.id),false; RETURN; END IF;
    PERFORM set_config('casechain.placement_review_move','on',true);
    moved:=public.execute_document_boundary_repair(d.id,source.target_matter_id,'move',
      p_expected_impact_fingerprint,p_reason,p_idempotency_key);
    PERFORM set_config('casechain.placement_review_move','',true);
    IF moved->>'code'<>'ok' OR coalesce((moved->>'replayed')::boolean,true) THEN
      RETURN QUERY SELECT coalesce(moved->>'code','failed'),public.read_review_detail(item.id),false; RETURN; END IF;
  END IF;
  SELECT client_id INTO client_id_value FROM public.matters
    WHERE id=CASE WHEN p_action='move' THEN source.target_matter_id ELSE source.old_matter_id END
      AND org_id=actor.org_id;
  INSERT INTO public.placement_conflict_decisions(org_id,review_item_id,expected_revision,result_revision,action,reason,
    actor_user_id,idempotency_key,request_fingerprint,impact_fingerprint,old_matter_id,target_matter_id,
    source_candidate_id,document_version_id)
  VALUES(actor.org_id,item.id,item.revision,item.revision+1,p_action,p_reason,actor.actor_user_id,p_idempotency_key,
    request_hash,p_expected_impact_fingerprint,source.old_matter_id,source.target_matter_id,
    source.source_candidate_id,source.document_version_id);
  UPDATE public.review_items SET status='closed',closure_reason='decision_recorded',closed_at=now(),updated_at=now(),
    revision=revision+1 WHERE id=item.id;
  PERFORM public.append_activity_event(actor.org_id,'review.placement_conflict_decided',1::smallint,'user',
    actor.actor_user_id,'Member','document',item.document_id,client_id_value,
    CASE WHEN p_action='move' THEN source.target_matter_id ELSE source.old_matter_id END,
    'Document','Placement Review decision recorded',jsonb_build_object('action',p_action,'revision',item.revision+1),
    'document',item.document_id,item.document_version_id,item.id,NULL,
    'review.placement.'||actor.org_id||'.'||actor.actor_user_id||'.'||p_idempotency_key,now());
  RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),false;
EXCEPTION WHEN lock_not_available OR deadlock_detected THEN RETURN QUERY SELECT 'busy',NULL::jsonb,false;
  WHEN others THEN RETURN QUERY SELECT 'failed',NULL::jsonb,false;
END $$;

REVOKE ALL ON FUNCTION public.reconcile_placed_document_identity_conflict(uuid),
  public.placed_identity_verified_key_changed(),public.placed_identity_target_matter_availability_changed(),
  public.placed_identity_filing_changed(),
  public.materialize_document_version_analysis_before_placement_conflict(uuid,uuid,text,uuid),
  public.finish_ai_extraction_before_placement_conflict(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb),
  public.read_review_detail_before_placement_conflict(uuid),public.preview_placement_conflict_move(uuid),
  public.resolve_placement_conflict(uuid,bigint,text,text,text,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.preview_placement_conflict_move(uuid),
  public.resolve_placement_conflict(uuid,bigint,text,text,text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.materialize_document_version_analysis(uuid,uuid,text,uuid),
  public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.materialize_document_version_analysis(uuid,uuid,text,uuid),
  public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.read_review_queue(text,text,text,text,integer,integer),public.read_review_detail(uuid)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.read_review_queue(text,text,text,text,integer,integer),public.read_review_detail(uuid) TO authenticated;

COMMIT;
