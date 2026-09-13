-- D08-T02: private, typed extraction-conflict Review. No legacy backfill.
BEGIN;
CREATE TYPE public.review_item_type AS ENUM ('extraction_conflict');
CREATE TYPE public.review_item_status AS ENUM ('needs_review','closed');
CREATE TYPE public.review_item_priority AS ENUM ('normal','high','urgent');
CREATE TYPE public.review_item_closure AS ENUM ('decision_recorded','source_replaced');
CREATE TYPE public.review_extraction_action AS ENUM ('select_candidate','request_clarification');

CREATE TABLE public.review_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id),
  document_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  binding_id uuid NOT NULL,
  candidate_sequence bigint NOT NULL CHECK(candidate_sequence>0),
  type public.review_item_type NOT NULL DEFAULT 'extraction_conflict',
  reason_code text NOT NULL DEFAULT 'material_candidate_conflict' CHECK(reason_code='material_candidate_conflict'),
  field_path text NOT NULL CHECK(field_path ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){0,15}$'),
  semantic_candidate_key text NOT NULL CHECK(semantic_candidate_key ~ '^[a-z][a-z0-9_.:-]{0,199}$'),
  impact text NOT NULL DEFAULT 'Resolve the conflicting source observation before relying on this field.' CHECK(char_length(impact) BETWEEN 1 AND 280),
  priority public.review_item_priority NOT NULL DEFAULT 'high' CHECK(priority='high'),
  priority_reason text NOT NULL DEFAULT 'This conflict materially affects the document record.' CHECK(char_length(priority_reason) BETWEEN 1 AND 280),
  status public.review_item_status NOT NULL DEFAULT 'needs_review',
  closure_reason public.review_item_closure,
  revision bigint NOT NULL DEFAULT 1 CHECK(revision>0),
  can_select boolean NOT NULL,
  field_decision_sequence bigint NOT NULL DEFAULT 0 CHECK(field_decision_sequence>=0),
  dedupe_key text NOT NULL UNIQUE CHECK(dedupe_key ~ '^[0-9a-f]{32}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz,
  UNIQUE(org_id,id),
  CHECK((status='needs_review' AND closure_reason IS NULL AND closed_at IS NULL) OR (status='closed' AND closure_reason IS NOT NULL AND closed_at IS NOT NULL))
);
CREATE INDEX review_items_queue ON public.review_items(org_id,status,priority,created_at,id);
CREATE INDEX review_items_document ON public.review_items(org_id,document_id,document_version_id);
CREATE TABLE public.review_item_evidence (
  org_id uuid NOT NULL,
  review_item_id uuid NOT NULL,
  candidate_id uuid NOT NULL,
  ordinal integer NOT NULL CHECK(ordinal>0),
  selectable boolean NOT NULL,
  PRIMARY KEY(review_item_id,candidate_id),
  UNIQUE(review_item_id,ordinal),
  FOREIGN KEY(org_id,review_item_id) REFERENCES public.review_items(org_id,id)
);
CREATE TABLE public.review_item_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  review_item_id uuid NOT NULL,
  expected_revision bigint NOT NULL CHECK(expected_revision>0),
  result_revision bigint NOT NULL CHECK(result_revision=expected_revision+1),
  action public.review_extraction_action NOT NULL,
  selected_candidate_id uuid,
  reason text NOT NULL CHECK(char_length(btrim(reason)) BETWEEN 1 AND 500 AND reason !~ '[[:cntrl:]]'),
  actor_user_id uuid NOT NULL REFERENCES auth.users(id),
  idempotency_key uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(org_id,actor_user_id,idempotency_key),
  FOREIGN KEY(org_id,review_item_id) REFERENCES public.review_items(org_id,id),
  FOREIGN KEY(review_item_id,selected_candidate_id) REFERENCES public.review_item_evidence(review_item_id,candidate_id),
  CHECK((action='select_candidate' AND selected_candidate_id IS NOT NULL) OR (action='request_clarification' AND selected_candidate_id IS NULL))
);
CREATE TRIGGER review_decisions_immutable BEFORE UPDATE OR DELETE ON public.review_item_decisions FOR EACH ROW EXECUTE FUNCTION public.activity_events_prevent_mutation();
CREATE TRIGGER review_evidence_immutable BEFORE UPDATE OR DELETE ON public.review_item_evidence FOR EACH ROW EXECUTE FUNCTION public.activity_events_prevent_mutation();
CREATE TRIGGER review_boundary_lock BEFORE INSERT OR UPDATE OR DELETE ON public.review_items FOR EACH ROW EXECUTE FUNCTION public.document_boundary_dependency_lock();
-- Immutable locators deliberately have no source FK: governed source purge
-- must not be blocked by Review history. Evidence content is read through its
-- authorised live candidate, and unavailable/purged documents return no detail.

ALTER FUNCTION public.recompute_document_effective_metadata(uuid) RENAME TO recompute_document_effective_metadata_before_review;
CREATE FUNCTION public.recompute_document_effective_metadata(p_document_version_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  PERFORM public.recompute_document_effective_metadata_before_review(p_document_version_id);
  DELETE FROM public.document_effective_metadata effective
  USING public.review_items item,public.documents document
  WHERE effective.document_version_id=p_document_version_id AND effective.winning_document_field_decision_id IS NULL
    AND item.org_id=effective.org_id AND item.document_version_id=effective.document_version_id
    AND item.field_path=effective.field_path AND item.semantic_candidate_key=effective.semantic_candidate_key
    AND item.status='needs_review' AND document.id=item.document_id AND document.org_id=item.org_id
    AND document.current_version_id=item.document_version_id;
END $$;

-- Read paths take no locks and never assign work. Mutation authority locks the
-- current membership so a simultaneous suspension cannot race a decision.
CREATE FUNCTION public.review_actor(p_lock boolean DEFAULT false)
RETURNS TABLE(actor_user_id uuid,org_id uuid,can_resolve boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE member public.organisation_memberships%ROWTYPE; current_count integer; capabilities text[];
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;
  IF p_lock THEN PERFORM 1 FROM public.organisation_memberships m WHERE m.user_id=auth.uid() AND m.state IN ('active','suspended') ORDER BY m.id FOR UPDATE; END IF;
  SELECT count(*) INTO current_count FROM public.organisation_memberships m WHERE m.user_id=auth.uid() AND m.state IN ('active','suspended');
  IF current_count<>1 THEN RETURN; END IF;
  SELECT * INTO member FROM public.organisation_memberships m WHERE m.user_id=auth.uid() AND m.state IN ('active','suspended');
  SELECT public.organisation_member_capabilities(member.role,o.owner_membership_id=member.id,member.state) INTO capabilities FROM public.organisations o WHERE o.id=member.org_id;
  IF member.state<>'active' OR NOT ('document.view'=ANY(capabilities)) THEN RETURN; END IF;
  RETURN QUERY SELECT member.user_id,member.org_id,'document.metadata.decide'=ANY(capabilities);
END $$;

CREATE FUNCTION public.review_document_available(p_org uuid,p_document uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT EXISTS(SELECT 1 FROM public.documents d JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id
    WHERE d.org_id=p_org AND d.id=p_document AND d.record_state='active' AND d.deleted_at IS NULL
      AND m.record_state='active' AND m.deleted_at IS NULL AND c.record_state='active' AND c.deleted_at IS NULL
      AND NOT EXISTS(SELECT 1 FROM public.resource_trash_memberships t WHERE t.org_id=p_org AND t.state='active' AND t.resource_id IN(d.id,m.id,c.id)))
$$;

-- Compare one semantic fact across immutable runs. Never compare different
-- array entries simply because they share a field path.
CREATE FUNCTION public.review_candidate_value(p_value jsonb) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT CASE WHEN jsonb_typeof(p_value)='object' THEN p_value-ARRAY['raw','display','catalogue_version','normalizer_version'] ELSE p_value END
$$;
CREATE FUNCTION public.review_comparison_candidates(p_binding_id uuid,p_field_path text,p_semantic_key text,p_include_unresolved_history boolean)
RETURNS SETOF public.document_field_candidates LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  WITH binding AS (SELECT * FROM public.document_version_analysis_bindings WHERE id=p_binding_id),
  authority AS (
    SELECT decision.* FROM public.document_field_decisions decision,binding
    WHERE decision.document_version_id=binding.document_version_id AND decision.field_path=p_field_path AND decision.semantic_candidate_key=p_semantic_key
    ORDER BY decision.decision_sequence DESC LIMIT 1
  )
  SELECT candidate.* FROM public.document_field_candidates candidate,binding
  WHERE candidate.org_id=binding.org_id AND candidate.document_version_id=binding.document_version_id AND candidate.field_path=p_field_path AND candidate.semantic_candidate_key=p_semantic_key
    AND coalesce((SELECT decision.action::text FROM public.document_field_decisions decision WHERE decision.document_field_candidate_id=candidate.id ORDER BY decision.decision_sequence DESC LIMIT 1),'') NOT IN ('rejected','cleared')
    AND (candidate.document_version_analysis_binding_id=binding.id
      OR candidate.id=(SELECT document_field_candidate_id FROM authority WHERE action IN ('accepted','corrected'))
      OR (p_include_unresolved_history AND NOT EXISTS(SELECT 1 FROM authority WHERE action IN ('accepted','corrected'))))
$$;
CREATE FUNCTION public.reconcile_extraction_conflict_review(p_binding_id uuid,p_create boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE binding public.document_version_analysis_bindings%ROWTYPE; group_row record; item_id uuid; selectable_count integer; candidate_ids uuid[]; key text; conflict boolean;
BEGIN
  SELECT * INTO binding FROM public.document_version_analysis_bindings WHERE id=p_binding_id;
  IF binding.id IS NULL OR NOT public.review_document_available(binding.org_id,binding.document_id)
    OR NOT EXISTS(SELECT 1 FROM public.documents WHERE id=binding.document_id AND current_version_id=binding.document_version_id) THEN RETURN; END IF;
  FOR group_row IN
    SELECT DISTINCT c.field_path,c.semantic_candidate_key
    FROM public.document_field_candidates c
    WHERE c.document_version_analysis_binding_id=binding.id
  LOOP
    SELECT array_agg(c.id ORDER BY c.id),count(DISTINCT public.review_candidate_value(c.normalized_value)) FILTER(WHERE c.validation_state IN ('eligible','provisional') AND coalesce(c.normalized_value->>'conflict','false')<>'true'),
      coalesce(bool_or(c.validation_state='conflicting'),false) OR count(DISTINCT public.review_candidate_value(c.normalized_value)) FILTER(WHERE c.validation_state IN ('eligible','provisional'))>1
    INTO candidate_ids,selectable_count,conflict FROM public.review_comparison_candidates(binding.id,group_row.field_path,group_row.semantic_candidate_key,p_create) c;
    IF NOT conflict THEN
      UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
        WHERE org_id=binding.org_id AND document_id=binding.document_id AND document_version_id=binding.document_version_id AND field_path=group_row.field_path AND semantic_candidate_key=group_row.semantic_candidate_key AND status='needs_review';
      CONTINUE;
    END IF;
    IF NOT p_create THEN CONTINUE; END IF;
    key:=md5(binding.document_version_id::text||':'||group_row.field_path||':'||group_row.semantic_candidate_key||':'||candidate_ids::text);
    IF EXISTS(SELECT 1 FROM public.review_items WHERE dedupe_key=key) THEN CONTINUE; END IF;
    UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
      WHERE org_id=binding.org_id AND document_id=binding.document_id AND document_version_id=binding.document_version_id AND field_path=group_row.field_path AND semantic_candidate_key=group_row.semantic_candidate_key AND status='needs_review';
    INSERT INTO public.review_items(org_id,document_id,document_version_id,binding_id,candidate_sequence,field_path,semantic_candidate_key,can_select,dedupe_key,field_decision_sequence)
      VALUES(binding.org_id,binding.document_id,binding.document_version_id,binding.id,
        (SELECT max(materialization_sequence) FROM public.document_field_candidates WHERE document_version_id=binding.document_version_id AND field_path=group_row.field_path AND semantic_candidate_key=group_row.semantic_candidate_key),group_row.field_path,group_row.semantic_candidate_key,selectable_count>=2,key,
        (SELECT coalesce(max(decision_sequence),0) FROM public.document_field_decisions WHERE document_version_id=binding.document_version_id AND field_path=group_row.field_path AND semantic_candidate_key=group_row.semantic_candidate_key)) RETURNING id INTO item_id;
    INSERT INTO public.review_item_evidence(org_id,review_item_id,candidate_id,ordinal,selectable)
      SELECT binding.org_id,item_id,c.id,row_number() OVER(ORDER BY c.page_number,c.materialization_sequence,c.id),selectable_count>=2 AND c.validation_state IN ('eligible','provisional') AND coalesce(c.normalized_value->>'conflict','false')<>'true'
      FROM public.document_field_candidates c WHERE c.id=ANY(candidate_ids);
  END LOOP;
  PERFORM public.recompute_document_effective_metadata(binding.document_version_id);
END $$;
CREATE FUNCTION public.produce_extraction_conflict_review(p_binding_id uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ SELECT public.reconcile_extraction_conflict_review(p_binding_id,true) $$;

ALTER FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb) RENAME TO finish_document_processing_ai_extraction_before_review;
CREATE FUNCTION public.finish_document_processing_ai_extraction(p_processing_run_id uuid,p_processing_lease_token uuid,p_source_analysis_run_id uuid,p_source_analysis_lease_token uuid,p_outcome text,p_input_tokens bigint,p_output_tokens bigint,p_latency_ms integer,p_candidates jsonb DEFAULT '[]',p_review_required boolean DEFAULT false,p_legacy_metadata jsonb DEFAULT NULL)
RETURNS TABLE(code text,binding_id uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE finished record;
BEGIN
  PERFORM pg_advisory_xact_lock_shared(hashtextextended(document_id::text,1521)) FROM public.document_processing_runs WHERE id=p_processing_run_id;
  SELECT * INTO finished FROM public.finish_document_processing_ai_extraction_before_review(p_processing_run_id,p_processing_lease_token,p_source_analysis_run_id,p_source_analysis_lease_token,p_outcome,p_input_tokens,p_output_tokens,p_latency_ms,p_candidates,p_review_required,p_legacy_metadata);
  IF p_outcome='validated' AND finished.code IN ('validated','review_required') AND finished.binding_id IS NOT NULL THEN
    IF p_review_required THEN PERFORM public.produce_extraction_conflict_review(finished.binding_id);
    ELSE PERFORM public.reconcile_extraction_conflict_review(finished.binding_id,false); END IF;
  END IF;
  RETURN QUERY SELECT finished.code::text,finished.binding_id::uuid;
END $$;
CREATE FUNCTION public.review_source_replaced() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NEW.current_version_id IS DISTINCT FROM OLD.current_version_id THEN
    UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
      WHERE org_id=NEW.org_id AND document_id=NEW.id AND document_version_id IS DISTINCT FROM NEW.current_version_id AND status='needs_review';
    IF NEW.current_version_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.document_versions WHERE id=NEW.current_version_id AND validation_state='valid' AND state='current') THEN
      PERFORM public.recompute_document_effective_metadata(NEW.current_version_id);
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER review_source_replaced AFTER UPDATE OF current_version_id ON public.documents FOR EACH ROW EXECUTE FUNCTION public.review_source_replaced();

CREATE FUNCTION public.read_review_queue(p_status text DEFAULT 'needs_review',p_type text DEFAULT 'all',p_priority text DEFAULT 'all',p_search text DEFAULT '',p_page integer DEFAULT 1,p_page_size integer DEFAULT 25)
RETURNS TABLE(items jsonb,total_count bigint,can_resolve boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record;
BEGIN
  SELECT * INTO actor FROM public.review_actor();
  IF actor.actor_user_id IS NULL THEN RETURN; END IF;
  IF p_status IS NULL OR p_status NOT IN ('needs_review','closed','all') OR p_type IS NULL OR p_type NOT IN ('extraction_conflict','all') OR p_priority IS NULL OR p_priority NOT IN ('normal','high','urgent','all') OR p_search IS NULL OR char_length(p_search)>200 OR p_page IS NULL OR p_page NOT BETWEEN 1 AND 100000 OR p_page_size IS NULL OR p_page_size NOT BETWEEN 1 AND 50 THEN RETURN; END IF;
  RETURN QUERY WITH filtered AS MATERIALIZED (
    SELECT i.id,i.type,i.field_path,i.priority,i.priority_reason,i.status,i.closure_reason,i.revision,i.created_at,i.document_id,i.document_version_id,d.display_title AS document_title,m.title AS matter_title,c.name AS client_name
    FROM public.review_items i JOIN public.documents d ON d.id=i.document_id AND d.org_id=i.org_id JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id
    WHERE i.org_id=actor.org_id AND public.review_document_available(i.org_id,i.document_id)
      AND (i.status='closed' OR d.current_version_id=i.document_version_id)
      AND (p_status='all' OR i.status::text=p_status) AND (p_type='all' OR i.type::text=p_type) AND (p_priority='all' OR i.priority::text=p_priority)
      AND (p_search='' OR strpos(lower(concat_ws(' ',i.field_path,d.display_title,m.title,c.name)),lower(p_search))>0)
  ), page_rows AS (SELECT * FROM filtered ORDER BY priority DESC,created_at,id LIMIT p_page_size OFFSET (p_page-1)*p_page_size)
  SELECT coalesce((SELECT jsonb_agg(to_jsonb(page_rows) ORDER BY priority DESC,created_at,id) FROM page_rows),'[]'::jsonb),(SELECT count(*) FROM filtered),actor.can_resolve;
END $$;

CREATE FUNCTION public.read_review_detail(p_review_item_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; item public.review_items%ROWTYPE; result jsonb;
BEGIN
  SELECT * INTO actor FROM public.review_actor();
  IF actor.actor_user_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  IF item.id IS NULL OR NOT public.review_document_available(item.org_id,item.document_id) THEN RETURN NULL; END IF;
  SELECT to_jsonb(item)||jsonb_build_object('document_title',d.display_title,'matter_title',m.title,'client_name',c.name,'version_number',v.version_number,'is_current',d.current_version_id=item.document_version_id,
    'allowed_actions',CASE WHEN actor.can_resolve AND item.status='needs_review' AND d.current_version_id=item.document_version_id THEN CASE WHEN item.can_select THEN jsonb_build_array('select_candidate','request_clarification') ELSE jsonb_build_array('request_clarification') END ELSE '[]'::jsonb END,
    'evidence',coalesce((SELECT jsonb_agg(jsonb_build_object('candidate_id',candidate.id,'ordinal',e.ordinal,'selectable',e.selectable,'page_number',candidate.page_number,'quotation',candidate.quotation,'value',candidate.normalized_value,'validation_state',candidate.validation_state) ORDER BY e.ordinal) FROM public.review_item_evidence e JOIN public.document_field_candidates candidate ON candidate.id=e.candidate_id AND candidate.org_id=e.org_id WHERE e.review_item_id=item.id),'[]'::jsonb),
    'last_decision',(SELECT jsonb_build_object('action',decision.action,'selected_candidate_id',decision.selected_candidate_id,'reason',decision.reason,'created_at',decision.created_at) FROM public.review_item_decisions decision WHERE decision.review_item_id=item.id ORDER BY decision.result_revision DESC LIMIT 1)) INTO result
  FROM public.documents d JOIN public.document_versions v ON v.id=item.document_version_id AND v.document_id=d.id AND v.org_id=d.org_id JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id WHERE d.id=item.document_id;
  RETURN result;
END $$;

INSERT INTO public.activity_event_definitions(event_type,event_version,category,subject_types,default_visibility,metadata_contract,renderer_key) VALUES
  ('review.extraction_decided',1,'review',ARRAY['document'],'matter','{"action":"code","revision":"integer"}','review.extraction_decided.v1');

CREATE FUNCTION public.resolve_extraction_conflict(p_review_item_id uuid,p_expected_revision bigint,p_action public.review_extraction_action,p_candidate_id uuid,p_reason text,p_idempotency_key uuid)
RETURNS TABLE(code text,current_item jsonb,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; item public.review_items%ROWTYPE; prior public.review_item_decisions%ROWTYPE; d public.documents%ROWTYPE; candidate record; client_id_value uuid; reason_value text:=btrim(p_reason); evidence_ids uuid[]; current_ids uuid[];
BEGIN
  SELECT * INTO actor FROM public.review_actor(true);
  IF actor.actor_user_id IS NULL OR NOT actor.can_resolve THEN RETURN QUERY SELECT 'forbidden',NULL::jsonb,false; RETURN; END IF;
  IF p_review_item_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1 OR p_action IS NULL OR p_idempotency_key IS NULL OR reason_value IS NULL OR char_length(reason_value) NOT BETWEEN 1 AND 500 OR reason_value ~ '[[:cntrl:]]' OR (p_action='select_candidate')<>(p_candidate_id IS NOT NULL) THEN RETURN QUERY SELECT 'invalid_request',NULL::jsonb,false; RETURN; END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  IF item.id IS NULL THEN RETURN QUERY SELECT 'unavailable',NULL::jsonb,false; RETURN; END IF;
  -- Same order as the provenance finisher; shared boundary fence excludes Move.
  PERFORM pg_advisory_xact_lock_shared(hashtextextended(item.document_id::text,1521));
  PERFORM 1 FROM public.document_versions WHERE id=item.document_version_id FOR UPDATE;
  SELECT * INTO d FROM public.documents WHERE id=item.document_id AND org_id=actor.org_id FOR UPDATE;
  PERFORM 1 FROM public.matters WHERE id=d.matter_id FOR SHARE;
  SELECT m.client_id INTO client_id_value FROM public.matters m WHERE m.id=d.matter_id;
  PERFORM 1 FROM public.clients WHERE id=client_id_value FOR SHARE;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id FOR UPDATE;
  IF NOT public.review_document_available(actor.org_id,item.document_id) THEN RETURN QUERY SELECT 'unavailable',NULL::jsonb,false; RETURN; END IF;
  SELECT * INTO prior FROM public.review_item_decisions WHERE org_id=actor.org_id AND actor_user_id=actor.actor_user_id AND idempotency_key=p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.review_item_id<>item.id OR prior.expected_revision<>p_expected_revision OR prior.action<>p_action OR prior.selected_candidate_id IS DISTINCT FROM p_candidate_id OR prior.reason<>reason_value THEN RETURN QUERY SELECT 'idempotency_conflict',public.read_review_detail(item.id),false;
    ELSE RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),true; END IF; RETURN;
  END IF;
  IF item.revision<>p_expected_revision OR item.status='closed' OR d.current_version_id IS DISTINCT FROM item.document_version_id THEN RETURN QUERY SELECT 'stale',public.read_review_detail(item.id),false; RETURN; END IF;
  SELECT array_agg(candidate_id ORDER BY candidate_id) INTO evidence_ids FROM public.review_item_evidence WHERE review_item_id=item.id;
  SELECT array_agg(id ORDER BY id) INTO current_ids FROM public.review_comparison_candidates(item.binding_id,item.field_path,item.semantic_candidate_key,true);
  IF evidence_ids IS DISTINCT FROM current_ids THEN RETURN QUERY SELECT 'stale',public.read_review_detail(item.id),false; RETURN; END IF;
  IF item.candidate_sequence<>(SELECT max(materialization_sequence) FROM public.document_field_candidates WHERE document_version_id=item.document_version_id AND field_path=item.field_path AND semantic_candidate_key=item.semantic_candidate_key) THEN RETURN QUERY SELECT 'stale',public.read_review_detail(item.id),false; RETURN; END IF;
  IF item.field_decision_sequence<>(SELECT coalesce(max(decision_sequence),0) FROM public.document_field_decisions WHERE document_version_id=item.document_version_id AND field_path=item.field_path AND semantic_candidate_key=item.semantic_candidate_key) THEN RETURN QUERY SELECT 'stale',public.read_review_detail(item.id),false; RETURN; END IF;
  IF p_action='select_candidate' THEN
    IF NOT item.can_select OR NOT EXISTS(SELECT 1 FROM public.review_item_evidence e JOIN public.document_field_candidates c ON c.id=e.candidate_id AND c.org_id=e.org_id WHERE e.review_item_id=item.id AND e.candidate_id=p_candidate_id AND e.selectable AND c.validation_state IN ('eligible','provisional') AND coalesce(c.normalized_value->>'conflict','false')<>'true') THEN RETURN QUERY SELECT 'invalid_candidate',public.read_review_detail(item.id),false; RETURN; END IF;
    -- The existing immutable field-decision insert guard validates the actor,
    -- exact candidate and version for each row. Append the accepted row last
    -- and recompute once, after Review closure, inside this transaction.
    INSERT INTO public.document_field_decisions(org_id,document_id,document_version_id,document_field_candidate_id,semantic_candidate_key,field_path,value_type,action,reason,actor_user_id,idempotency_key)
      SELECT c.org_id,c.document_id,c.document_version_id,c.id,c.semantic_candidate_key,c.field_path,c.value_type,'rejected',reason_value,actor.actor_user_id,'review.'||p_idempotency_key||'.'||c.id
      FROM public.document_field_candidates c WHERE c.id=ANY(evidence_ids) AND c.id<>p_candidate_id ORDER BY c.id;
    INSERT INTO public.document_field_decisions(org_id,document_id,document_version_id,document_field_candidate_id,semantic_candidate_key,field_path,value_type,action,reason,actor_user_id,idempotency_key)
      SELECT c.org_id,c.document_id,c.document_version_id,c.id,c.semantic_candidate_key,c.field_path,c.value_type,'accepted',reason_value,actor.actor_user_id,'review.'||p_idempotency_key||'.'||c.id
      FROM public.document_field_candidates c WHERE c.id=p_candidate_id;
  END IF;
  INSERT INTO public.review_item_decisions(org_id,review_item_id,expected_revision,result_revision,action,selected_candidate_id,reason,actor_user_id,idempotency_key)
    VALUES(item.org_id,item.id,item.revision,item.revision+1,p_action,p_candidate_id,reason_value,actor.actor_user_id,p_idempotency_key);
  UPDATE public.review_items SET revision=revision+1,updated_at=now(),status=CASE WHEN p_action='select_candidate' THEN 'closed'::public.review_item_status ELSE status END,
    closure_reason=CASE WHEN p_action='select_candidate' THEN 'decision_recorded'::public.review_item_closure ELSE NULL END,closed_at=CASE WHEN p_action='select_candidate' THEN now() ELSE NULL END WHERE id=item.id;
  IF p_action='select_candidate' THEN PERFORM public.recompute_document_effective_metadata(item.document_version_id); END IF;
  PERFORM public.append_activity_event(item.org_id,'review.extraction_decided',1::smallint,'user',actor.actor_user_id,'Member','document',item.document_id,client_id_value,d.matter_id,'Document','Extraction Review decision recorded',jsonb_build_object('action',p_action,'revision',item.revision+1),'document',item.document_id,item.document_version_id,item.id,NULL,'review.'||item.org_id||'.'||actor.actor_user_id||'.'||p_idempotency_key,now());
  RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),false;
END $$;

ALTER TABLE public.review_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_items FORCE ROW LEVEL SECURITY;
ALTER TABLE public.review_item_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_item_evidence FORCE ROW LEVEL SECURITY;
ALTER TABLE public.review_item_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_item_decisions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.review_items,public.review_item_evidence,public.review_item_decisions FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.review_actor(boolean),public.review_document_available(uuid,uuid),public.review_candidate_value(jsonb),public.produce_extraction_conflict_review(uuid),public.review_source_replaced(),public.finish_document_processing_ai_extraction_before_review(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.review_comparison_candidates(uuid,text,text,boolean),public.reconcile_extraction_conflict_review(uuid,boolean) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.recompute_document_effective_metadata_before_review(uuid),public.recompute_document_effective_metadata(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.recompute_document_effective_metadata(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.read_review_queue(text,text,text,text,integer,integer),public.read_review_detail(uuid),public.resolve_extraction_conflict(uuid,bigint,public.review_extraction_action,uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_review_queue(text,text,text,text,integer,integer),public.read_review_detail(uuid),public.resolve_extraction_conflict(uuid,bigint,public.review_extraction_action,uuid,text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb) TO service_role;
COMMIT;
