-- Exact-version, source-stated date-only observations. No reminder or inferred legal type.
BEGIN;
ALTER TYPE public.review_item_type ADD VALUE 'deadline_verification';
COMMIT;
BEGIN;

ALTER TABLE public.deadlines DROP CONSTRAINT deadlines_origin_check;
ALTER TABLE public.deadlines ADD CONSTRAINT deadlines_origin_check CHECK(origin IN ('manual','legacy','document_explicit'));
ALTER TABLE public.deadlines DROP CONSTRAINT deadlines_verification_check;
ALTER TABLE public.deadlines ADD CONSTRAINT deadlines_verification_check CHECK(verification_state IN ('verified','provisional','rejected'));
ALTER TABLE public.deadlines ADD CONSTRAINT deadlines_extracted_shape_check CHECK(
  origin<>'document_explicit' OR document_id IS NOT NULL);
ALTER TABLE public.deadline_versions ALTER COLUMN actor_user_id DROP NOT NULL;
ALTER TABLE public.deadline_versions ALTER COLUMN manual_basis DROP NOT NULL;
ALTER TABLE public.deadline_versions ADD CONSTRAINT deadline_versions_extracted_basis CHECK(
  (revision=1 AND actor_user_id IS NULL AND manual_basis IS NULL)
  OR (actor_user_id IS NOT NULL AND manual_basis IS NOT NULL));
ALTER TABLE public.deadline_command_receipts DROP CONSTRAINT deadline_command_receipts_command_check;
ALTER TABLE public.deadline_command_receipts ADD CONSTRAINT deadline_command_receipts_command_check
  CHECK(command IN ('create','amend','satisfy','cancel','deadline_review'));

CREATE TABLE public.deadline_candidate_bindings(
  org_id uuid NOT NULL,
  candidate_id uuid PRIMARY KEY,
  deadline_id uuid NOT NULL UNIQUE,
  document_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  binding_id uuid NOT NULL,
  semantic_candidate_key text NOT NULL,
  page_number integer NOT NULL CHECK(page_number>0),
  quotation text NOT NULL CHECK(char_length(quotation) BETWEEN 1 AND 1000 AND quotation !~ '[[:cntrl:]]'),
  source_due_date date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(org_id,deadline_id),
  FOREIGN KEY(org_id,candidate_id) REFERENCES public.document_field_candidates(org_id,id),
  FOREIGN KEY(org_id,deadline_id) REFERENCES public.deadlines(org_id,id),
  FOREIGN KEY(org_id,document_version_id) REFERENCES public.document_versions(org_id,id),
  FOREIGN KEY(org_id,binding_id) REFERENCES public.document_version_analysis_bindings(org_id,id)
);
CREATE TABLE public.deadline_candidate_decisions(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  deadline_id uuid NOT NULL,
  candidate_id uuid NOT NULL,
  review_item_id uuid NOT NULL,
  expected_revision bigint NOT NULL CHECK(expected_revision>0),
  result_revision bigint NOT NULL CHECK(result_revision=expected_revision+1),
  action text NOT NULL CHECK(action IN ('verify','correct','reject','clear')),
  decided_due_date date,
  reason text NOT NULL CHECK(char_length(reason) BETWEEN 2 AND 500 AND reason=btrim(reason) AND reason !~ '[[:cntrl:]]'),
  actor_user_id uuid NOT NULL REFERENCES auth.users(id),
  idempotency_key uuid NOT NULL,
  decided_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(org_id,actor_user_id,idempotency_key),
  FOREIGN KEY(org_id,deadline_id) REFERENCES public.deadlines(org_id,id),
  FOREIGN KEY(org_id,candidate_id) REFERENCES public.document_field_candidates(org_id,id),
  FOREIGN KEY(org_id,review_item_id) REFERENCES public.review_items(org_id,id),
  CHECK((action IN ('verify','correct') AND decided_due_date IS NOT NULL)
    OR (action IN ('reject','clear') AND decided_due_date IS NULL))
);
ALTER TABLE public.deadline_candidate_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deadline_candidate_bindings FORCE ROW LEVEL SECURITY;
ALTER TABLE public.deadline_candidate_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deadline_candidate_decisions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.deadline_candidate_bindings,public.deadline_candidate_decisions FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER deadline_candidate_bindings_immutable BEFORE UPDATE OR DELETE ON public.deadline_candidate_bindings
  FOR EACH ROW EXECUTE FUNCTION public.deadline_append_only_guard();
CREATE TRIGGER deadline_candidate_decisions_immutable BEFORE UPDATE OR DELETE ON public.deadline_candidate_decisions
  FOR EACH ROW EXECUTE FUNCTION public.deadline_append_only_guard();
CREATE INDEX deadline_extracted_matter_idx ON public.deadlines(org_id,matter_id,due_date,id)
  WHERE origin='document_explicit';

ALTER TABLE public.review_items DROP CONSTRAINT review_items_reason_code_check;
ALTER TABLE public.review_items ADD CONSTRAINT review_items_reason_code_check CHECK(
  (type='extraction_conflict' AND reason_code='material_candidate_conflict') OR
  (type='processing_recovery' AND reason_code IN ('invalid_model_output','provider_failed','domain_invalid')) OR
  (type='ambiguous_placement' AND reason_code='multiple_eligible_matters') OR
  (type='deadline_verification' AND reason_code='source_stated_due_date'));
ALTER TABLE public.review_items DROP CONSTRAINT review_items_type_shape_check;
ALTER TABLE public.review_items ADD CONSTRAINT review_items_type_shape_check CHECK(
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
    AND source_page_number=1 AND document_lifecycle_revision IS NULL));

CREATE FUNCTION public.produce_explicit_due_date_review(p_binding_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE binding public.document_version_analysis_bindings%ROWTYPE; candidate record; created public.deadlines%ROWTYPE;
  item_id uuid; title text; due date; prior_command_setting text;
BEGIN
  SELECT * INTO binding FROM public.document_version_analysis_bindings WHERE id=p_binding_id;
  IF binding.id IS NULL OR NOT public.review_document_available(binding.org_id,binding.document_id)
    OR NOT EXISTS(SELECT 1 FROM public.documents d WHERE d.id=binding.document_id
      AND d.org_id=binding.org_id AND d.current_version_id=binding.document_version_id)
    THEN RETURN; END IF;
  prior_command_setting:=current_setting('casechain.deadline_command',true);
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('deadline.version.'||binding.document_version_id::text,165));
  FOR candidate IN
    SELECT c.*,s.verified_source_anchor FROM public.document_field_candidates c
    JOIN public.source_field_candidates s ON s.id=c.source_field_candidate_id AND s.org_id=c.org_id
    WHERE c.org_id=binding.org_id AND c.document_version_id=binding.document_version_id
      AND c.document_version_analysis_binding_id=binding.id AND c.field_path='document.legal_date.due'
      AND c.value_type='structured' AND c.validation_state='provisional'
      AND c.normalized_value->>'meaning'='due' AND c.normalized_value->>'precision'='exact'
      AND c.normalized_value->>'normalization_state'='valid'
      AND c.normalized_value->>'normalized_date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      AND pg_input_is_valid(c.normalized_value->>'normalized_date','date')
      AND s.verified_source_anchor IS NOT NULL
    ORDER BY c.id
  LOOP
    IF EXISTS(SELECT 1 FROM public.deadline_candidate_bindings x WHERE x.candidate_id=candidate.id)
      OR EXISTS(SELECT 1 FROM public.deadline_candidate_bindings x
        WHERE x.org_id=binding.org_id AND x.document_version_id=binding.document_version_id
          AND x.semantic_candidate_key=candidate.semantic_candidate_key)
      THEN CONTINUE; END IF;
    title:=left(btrim(coalesce(nullif(candidate.normalized_value->>'display',''),candidate.normalized_value->>'raw','Source-stated legal date')),160);
    IF char_length(title)<2 OR title ~ '[[:cntrl:]]' THEN title:='Source-stated legal date'; END IF;
    due:=(candidate.normalized_value->>'normalized_date')::date;
    PERFORM set_config('casechain.deadline_command','on',true);
    INSERT INTO public.deadlines(org_id,matter_id,document_id,type,due_date,description,title,legal_type,origin,verification_state,lifecycle,current_revision)
      SELECT binding.org_id,d.matter_id,binding.document_id,'other',due,title,title,'other_legal',
        'document_explicit','provisional','open',1 FROM public.documents d
      WHERE d.id=binding.document_id AND d.org_id=binding.org_id RETURNING * INTO created;
    INSERT INTO public.deadline_versions(deadline_id,org_id,revision,title,obligation,legal_type,due_date,manual_basis,actor_user_id)
      VALUES(created.id,binding.org_id,1,title,title,'other_legal',due,NULL,NULL);
    INSERT INTO public.deadline_candidate_bindings(org_id,candidate_id,deadline_id,document_id,document_version_id,binding_id,semantic_candidate_key,page_number,quotation,source_due_date)
      VALUES(binding.org_id,candidate.id,created.id,binding.document_id,binding.document_version_id,binding.id,candidate.semantic_candidate_key,candidate.page_number,candidate.quotation,due);
    INSERT INTO public.review_items(org_id,document_id,document_version_id,binding_id,candidate_sequence,type,reason_code,field_path,semantic_candidate_key,impact,priority,priority_reason,can_select,field_decision_sequence,dedupe_key)
      VALUES(binding.org_id,binding.document_id,binding.document_version_id,binding.id,candidate.materialization_sequence,
        'deadline_verification','source_stated_due_date','document.legal_date.due',candidate.semantic_candidate_key,
        'Verify the explicit source date before treating it as a legal deadline.','high',
        'A proposed legal due date needs human verification.',true,0,md5('deadline:'||candidate.id::text))
      RETURNING id INTO item_id;
    INSERT INTO public.review_item_evidence(org_id,review_item_id,candidate_id,ordinal,selectable)
      VALUES(binding.org_id,item_id,candidate.id,1,true);
  END LOOP;
  PERFORM set_config('casechain.deadline_command',coalesce(prior_command_setting,''),true);
END $$;

-- Placement, attachment and same-tenant Copy may bind an already validated
-- immutable source run without a second AI finisher call. The binding boundary
-- is therefore the canonical producer; the finisher hook below also closes
-- successful terminal retries without introducing a second item.
ALTER FUNCTION public.materialize_document_version_analysis(uuid,uuid,text,uuid)
  RENAME TO materialize_document_version_analysis_before_due_dates;
CREATE FUNCTION public.materialize_document_version_analysis(
  p_document_version_id uuid,p_source_analysis_run_id uuid,p_binding_reason text,
  p_created_by uuid DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE bound_id uuid;
BEGIN
  bound_id:=public.materialize_document_version_analysis_before_due_dates(
    p_document_version_id,p_source_analysis_run_id,p_binding_reason,p_created_by);
  -- The full finisher runs extraction-conflict reconciliation after binding.
  -- That older reconciler closes all matching open field-path items, so its
  -- deadline producer must run at the terminal finisher boundary below.
  IF p_binding_reason<>'processing_ai_extraction' THEN
    PERFORM public.produce_explicit_due_date_review(bound_id);
  END IF;
  RETURN bound_id;
END $$;

ALTER FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb)
  RENAME TO finish_document_processing_ai_extraction_before_due_dates;
CREATE FUNCTION public.finish_document_processing_ai_extraction(
  p_processing_run_id uuid,p_processing_lease_token uuid,p_source_analysis_run_id uuid,
  p_source_analysis_lease_token uuid,p_outcome text,p_input_tokens bigint,p_output_tokens bigint,
  p_latency_ms integer,p_candidates jsonb DEFAULT '[]',p_review_required boolean DEFAULT false,
  p_legacy_metadata jsonb DEFAULT NULL
) RETURNS TABLE(code text,binding_id uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE finished record;
BEGIN
  SELECT * INTO finished FROM public.finish_document_processing_ai_extraction_before_due_dates(
    p_processing_run_id,p_processing_lease_token,p_source_analysis_run_id,p_source_analysis_lease_token,
    p_outcome,p_input_tokens,p_output_tokens,p_latency_ms,p_candidates,p_review_required,p_legacy_metadata);
  IF p_outcome='validated' AND finished.code IN ('validated','review_required')
    AND finished.binding_id IS NOT NULL THEN
    PERFORM public.produce_explicit_due_date_review(finished.binding_id);
  END IF;
  RETURN QUERY SELECT finished.code::text,finished.binding_id::uuid;
END $$;

-- Keep the Review queue's existing shape, paging and tenant boundary; extend
-- only its type catalogue and the one exact-source detail branch.
CREATE OR REPLACE FUNCTION public.read_review_queue(
  p_status text DEFAULT 'needs_review',p_type text DEFAULT 'all',p_priority text DEFAULT 'all',
  p_search text DEFAULT '',p_page integer DEFAULT 1,p_page_size integer DEFAULT 25
) RETURNS TABLE(items jsonb,total_count bigint,can_resolve boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record;
BEGIN
  SELECT * INTO actor FROM public.review_actor(); IF actor.actor_user_id IS NULL THEN RETURN; END IF;
  IF p_status IS NULL OR p_status NOT IN ('needs_review','closed','all')
    OR p_type IS NULL OR p_type NOT IN ('extraction_conflict','processing_recovery','ambiguous_placement','deadline_verification','all')
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

ALTER FUNCTION public.read_review_detail(uuid) RENAME TO read_review_detail_before_due_dates;
CREATE FUNCTION public.read_review_detail(p_review_item_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; item public.review_items%ROWTYPE; result jsonb;
BEGIN
  SELECT * INTO actor FROM public.review_actor();
  IF actor.actor_user_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  IF item.id IS NULL THEN RETURN NULL; END IF;
  IF item.type<>'deadline_verification' THEN RETURN public.read_review_detail_before_due_dates(p_review_item_id); END IF;
  IF NOT public.review_document_available(item.org_id,item.document_id) THEN RETURN NULL; END IF;
  SELECT to_jsonb(item)||jsonb_build_object(
    'document_title',d.display_title,'matter_title',m.title,'client_name',c.name,
    'version_number',v.version_number,'is_current',d.current_version_id=item.document_version_id,
    'source_identity','Document version '||v.version_number,'record_baseline',NULL,
    'allowed_actions',CASE WHEN actor.can_resolve AND item.status='needs_review'
      AND d.current_version_id=item.document_version_id AND deadline.verification_state='provisional'
      AND deadline.current_revision=1 THEN jsonb_build_array('verify_deadline','correct_deadline','reject_deadline','clear_deadline')
      ELSE '[]'::jsonb END,
    'deadline_id',deadline.id,'deadline_revision',deadline.current_revision,
    'candidate_due_date',binding.source_due_date,'decision_history',
      coalesce((SELECT jsonb_agg(jsonb_build_object('action',decision.action,'due_date',decision.decided_due_date,
        'reason',decision.reason,'decided_at',decision.decided_at) ORDER BY decision.decided_at,decision.id)
        FROM public.deadline_candidate_decisions decision WHERE decision.deadline_id=deadline.id),'[]'::jsonb),
    'evidence',jsonb_build_array(jsonb_build_object('candidate_id',candidate.id,'ordinal',1,
      'selectable',true,'page_number',binding.page_number,'quotation',binding.quotation,
      'value',candidate.normalized_value,'validation_state',candidate.validation_state)),
    'last_decision',(SELECT jsonb_build_object('action',decision.action,'selected_candidate_id',
      CASE WHEN decision.action IN ('verify','correct') THEN candidate.id ELSE NULL END,
      'reason',decision.reason,'created_at',decision.decided_at)
      FROM public.deadline_candidate_decisions decision WHERE decision.deadline_id=deadline.id
      ORDER BY decision.decided_at DESC,decision.id DESC LIMIT 1)
  ) INTO result FROM public.deadline_candidate_bindings binding
    JOIN public.deadlines deadline ON deadline.id=binding.deadline_id AND deadline.org_id=binding.org_id
    JOIN public.document_field_candidates candidate ON candidate.id=binding.candidate_id AND candidate.org_id=binding.org_id
    JOIN public.documents d ON d.id=binding.document_id AND d.org_id=binding.org_id
    JOIN public.document_versions v ON v.id=binding.document_version_id AND v.document_id=d.id AND v.org_id=d.org_id
    JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id
    JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id
    WHERE binding.org_id=item.org_id AND binding.candidate_id=(
      SELECT evidence.candidate_id FROM public.review_item_evidence evidence
      WHERE evidence.review_item_id=item.id AND evidence.ordinal=1);
  RETURN result;
END $$;

CREATE FUNCTION public.resolve_explicit_due_date_review(
  p_review_item_id uuid,p_expected_revision bigint,p_action text,p_corrected_due_date date,
  p_reason text,p_idempotency_key uuid
) RETURNS TABLE(code text,current_item jsonb,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; item public.review_items%ROWTYPE; deadline public.deadlines%ROWTYPE;
  binding public.deadline_candidate_bindings%ROWTYPE; prior public.deadline_candidate_decisions%ROWTYPE;
  fingerprint text; next_revision bigint; due date;
BEGIN
  p_reason:=btrim(p_reason);
  IF p_review_item_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1
    OR p_idempotency_key IS NULL OR p_action IS NULL OR p_action NOT IN ('verify','correct','reject','clear')
    OR p_reason IS NULL OR char_length(p_reason) NOT BETWEEN 2 AND 500 OR p_reason ~ '[[:cntrl:]]'
    OR (p_action='correct' AND p_corrected_due_date IS NULL)
    OR (p_action<>'correct' AND p_corrected_due_date IS NOT NULL)
    THEN RETURN QUERY SELECT 'invalid_request',NULL::jsonb,false; RETURN; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,159));
  SELECT * INTO actor FROM public.review_actor(true);
  IF actor.actor_user_id IS NULL OR NOT actor.can_resolve THEN
    RETURN QUERY SELECT 'forbidden',NULL::jsonb,false; RETURN; END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id FOR UPDATE;
  IF item.id IS NULL OR item.type<>'deadline_verification' THEN
    RETURN QUERY SELECT 'unavailable',NULL::jsonb,false; RETURN; END IF;
  SELECT b.* INTO binding FROM public.deadline_candidate_bindings b
    JOIN public.review_item_evidence e ON e.candidate_id=b.candidate_id AND e.org_id=b.org_id
    WHERE e.review_item_id=item.id AND e.ordinal=1 AND b.org_id=actor.org_id;
  SELECT * INTO deadline FROM public.deadlines WHERE id=binding.deadline_id AND org_id=actor.org_id FOR UPDATE;
  fingerprint:=public.deadline_fingerprint(jsonb_build_object('item',p_review_item_id,
    'revision',p_expected_revision,'action',p_action,'corrected_date',p_corrected_due_date,'reason',p_reason));
  SELECT * INTO prior FROM public.deadline_candidate_decisions decision
    WHERE decision.org_id=actor.org_id AND decision.actor_user_id=actor.actor_user_id
      AND decision.idempotency_key=p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.review_item_id=p_review_item_id AND prior.expected_revision=p_expected_revision
      AND prior.action=p_action AND prior.decided_due_date IS NOT DISTINCT FROM
        (CASE WHEN p_action='correct' THEN p_corrected_due_date
          WHEN p_action='verify' THEN binding.source_due_date ELSE NULL END)
      AND prior.reason=p_reason THEN
      RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),true;
    ELSE RETURN QUERY SELECT 'idempotency_conflict',public.read_review_detail(item.id),false; END IF;
    RETURN;
  END IF;
  IF binding.candidate_id IS NULL OR deadline.id IS NULL
    OR NOT public.review_document_available(actor.org_id,item.document_id)
    OR NOT EXISTS(SELECT 1 FROM public.documents d WHERE d.id=item.document_id
      AND d.org_id=actor.org_id AND d.current_version_id=item.document_version_id)
    THEN RETURN QUERY SELECT 'unavailable',public.read_review_detail(item.id),false; RETURN; END IF;
  IF item.status<>'needs_review' OR item.revision<>p_expected_revision
    OR deadline.current_revision<>1 OR deadline.verification_state<>'provisional'
    THEN RETURN QUERY SELECT 'stale',public.read_review_detail(item.id),false; RETURN; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.document_field_candidates c
    JOIN public.source_field_candidates s ON s.id=c.source_field_candidate_id AND s.org_id=c.org_id
    WHERE c.id=binding.candidate_id AND c.org_id=actor.org_id
      AND c.document_version_id=binding.document_version_id
      AND c.document_version_analysis_binding_id=binding.binding_id
      AND c.page_number=binding.page_number AND c.quotation=binding.quotation
      AND c.normalized_value->>'normalized_date'=binding.source_due_date::text
      AND c.validation_state='provisional' AND s.verified_source_anchor IS NOT NULL)
    THEN RETURN QUERY SELECT 'unavailable',public.read_review_detail(item.id),false; RETURN; END IF;
  due:=CASE WHEN p_action='correct' THEN p_corrected_due_date ELSE binding.source_due_date END;
  next_revision:=deadline.current_revision+1;
  PERFORM set_config('casechain.deadline_command','on',true);
  IF p_action IN ('verify','correct') THEN
    UPDATE public.deadlines SET verification_state='verified',due_date=due,
      created_by=actor.actor_user_id,current_revision=next_revision,updated_at=now()
      WHERE id=deadline.id;
    INSERT INTO public.deadline_versions(deadline_id,org_id,revision,title,obligation,legal_type,due_date,
      manual_basis,amendment_reason,actor_user_id)
      VALUES(deadline.id,actor.org_id,next_revision,deadline.title,deadline.description,
        deadline.legal_type,due,CASE WHEN p_action='correct' THEN 'Human correction of cited source.'
          ELSE 'Human verification of cited source.' END,p_reason,actor.actor_user_id);
  ELSE
    UPDATE public.deadlines SET verification_state='rejected',current_revision=next_revision,
      updated_at=now() WHERE id=deadline.id;
  END IF;
  INSERT INTO public.deadline_candidate_decisions(org_id,deadline_id,candidate_id,review_item_id,
    expected_revision,result_revision,action,decided_due_date,reason,actor_user_id,idempotency_key)
    VALUES(actor.org_id,deadline.id,binding.candidate_id,item.id,p_expected_revision,
      p_expected_revision+1,p_action,CASE WHEN p_action IN ('verify','correct') THEN due END,
      p_reason,actor.actor_user_id,p_idempotency_key);
  UPDATE public.review_items SET status='closed',closure_reason='decision_recorded',
    closed_at=now(),updated_at=now(),revision=revision+1 WHERE id=item.id;
  RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),false;
END $$;

CREATE OR REPLACE FUNCTION public.read_matter_manual_legal_deadline_agenda(
  p_matter_id uuid,p_limit integer DEFAULT 50
) RETURNS TABLE(items jsonb,timezone text,as_of_date date,can_mutate boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; today date;
BEGIN
  IF p_matter_id IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RETURN; END IF;
  SELECT * INTO actor FROM public.deadline_actor_for_matter(p_matter_id,false);
  IF actor.actor_user_id IS NULL THEN RETURN; END IF;
  today:=(clock_timestamp() AT TIME ZONE actor.timezone)::date;
  RETURN QUERY SELECT coalesce(jsonb_agg(item.obj ORDER BY item.rank,item.due_date,item.id),'[]'::jsonb),
    actor.timezone,today,actor.can_mutate FROM (
    SELECT d.id,d.due_date,
      CASE WHEN d.verification_state='provisional' THEN 0
        WHEN d.lifecycle='open' AND d.due_date<today THEN 1 WHEN d.lifecycle='open' THEN 2 ELSE 3 END rank,
      jsonb_build_object('id',d.id,'title',d.title,'obligation',d.description,
        'legal_type',d.legal_type,'due_date',d.due_date,
        'manual_basis',version.manual_basis,'origin',d.origin,'verification_state',d.verification_state,
        'lifecycle',d.lifecycle,'revision',d.current_revision,
        'temporal',CASE WHEN d.due_date<today THEN 'missed' WHEN d.due_date=today THEN 'due_today'
          WHEN d.due_date<=today+7 THEN 'due_soon' ELSE 'upcoming' END,
        'created_at',d.created_at,'updated_at',d.updated_at,
        'source',CASE WHEN binding.candidate_id IS NOT NULL THEN jsonb_build_object(
          'document_id',binding.document_id,'document_version_id',binding.document_version_id,
          'page_number',binding.page_number,'quotation',binding.quotation,
          'candidate_due_date',binding.source_due_date,'review_item_id',review.id) END,
        'history',coalesce((
          SELECT jsonb_agg(h.obj ORDER BY h.at,h.revision,h.kind) FROM (
            SELECT v.created_at at,v.revision,'version' kind,jsonb_build_object(
              'kind',CASE WHEN v.revision=1 THEN CASE WHEN d.origin='manual' THEN 'created'
                ELSE 'extracted' END ELSE 'amended' END,'revision',v.revision,
              'at',v.created_at,'actor_label',CASE WHEN v.actor_user_id IS NULL THEN 'Source extraction'
                ELSE coalesce(nullif(btrim(profile.display_name),''),'Organisation member') END,
              'title',v.title,'obligation',v.obligation,'legal_type',v.legal_type,
              'due_date',v.due_date,'manual_basis',v.manual_basis,'reason',v.amendment_reason) obj
              FROM public.deadline_versions v LEFT JOIN public.user_profiles profile
                ON profile.user_id=v.actor_user_id WHERE v.deadline_id=d.id
            UNION ALL SELECT o.recorded_at,o.revision,'outcome',jsonb_build_object(
              'kind',o.outcome,'revision',o.revision,'at',o.recorded_at,
              'actor_label',coalesce(nullif(btrim(profile.display_name),''),'Organisation member'),
              'reason',o.reason) FROM public.deadline_outcomes o
              LEFT JOIN public.user_profiles profile ON profile.user_id=o.actor_user_id
              WHERE o.deadline_id=d.id
            UNION ALL SELECT decision.decided_at,decision.result_revision,'decision',jsonb_build_object(
              'kind',decision.action,'revision',decision.result_revision,'at',decision.decided_at,
              'actor_label',coalesce(nullif(btrim(profile.display_name),''),'Organisation member'),
              'due_date',decision.decided_due_date,'reason',decision.reason)
              FROM public.deadline_candidate_decisions decision
              LEFT JOIN public.user_profiles profile ON profile.user_id=decision.actor_user_id
              WHERE decision.deadline_id=d.id
          ) h),'[]'::jsonb)) obj
    FROM public.deadlines d
    JOIN LATERAL (SELECT v.manual_basis FROM public.deadline_versions v
      WHERE v.deadline_id=d.id AND v.org_id=d.org_id AND v.revision<=d.current_revision
      ORDER BY v.revision DESC LIMIT 1) version ON true
    LEFT JOIN public.deadline_candidate_bindings binding ON binding.deadline_id=d.id AND binding.org_id=d.org_id
    LEFT JOIN LATERAL (SELECT item.id FROM public.review_item_evidence evidence
      JOIN public.review_items item ON item.id=evidence.review_item_id AND item.org_id=evidence.org_id
      WHERE evidence.candidate_id=binding.candidate_id AND evidence.ordinal=1
        AND item.type='deadline_verification' ORDER BY item.created_at,item.id LIMIT 1) review ON true
    WHERE d.org_id=actor.org_id AND d.matter_id=p_matter_id
      AND ((d.origin='manual' AND d.verification_state='verified')
        OR (d.origin='document_explicit' AND d.verification_state IN ('provisional','verified')
          AND EXISTS(SELECT 1 FROM public.documents document
            WHERE document.id=d.document_id AND document.org_id=d.org_id
              AND document.current_version_id=binding.document_version_id
              AND public.review_document_available(document.org_id,document.id))))
    ORDER BY rank,d.due_date,d.id LIMIT p_limit
  ) item;
END $$;

CREATE OR REPLACE FUNCTION public.record_manual_legal_deadline_outcome(
  p_deadline_id uuid,p_expected_revision bigint,p_outcome text,p_reason text,p_idempotency_key uuid
) RETURNS TABLE(code text,deadline_id uuid,revision bigint,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE d public.deadlines%ROWTYPE; actor record; receipt public.deadline_command_receipts%ROWTYPE;
  fingerprint text; next_revision bigint; reason text:=nullif(btrim(p_reason),'');
  expected_command text:=CASE WHEN p_outcome='satisfied' THEN 'satisfy' ELSE 'cancel' END;
BEGIN
  IF p_deadline_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1
    OR p_idempotency_key IS NULL OR p_outcome IS NULL OR p_outcome NOT IN ('satisfied','cancelled')
    OR (p_outcome='cancelled' AND (reason IS NULL OR char_length(reason) NOT BETWEEN 2 AND 500 OR reason ~ '[[:cntrl:]]'))
    OR (reason IS NOT NULL AND (char_length(reason) NOT BETWEEN 2 AND 500 OR reason ~ '[[:cntrl:]]'))
    THEN RETURN QUERY SELECT 'invalid_request',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,159));
  SELECT * INTO d FROM public.deadlines WHERE id=p_deadline_id;
  IF d.id IS NULL THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  SELECT * INTO actor FROM public.deadline_actor_for_matter(d.matter_id,true);
  IF actor.actor_user_id IS NULL OR actor.org_id<>d.org_id THEN
    RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  SELECT * INTO d FROM public.deadlines WHERE id=p_deadline_id AND org_id=actor.org_id FOR UPDATE;
  IF d.id IS NULL THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  fingerprint:=public.deadline_fingerprint(jsonb_build_object('command',p_outcome,
    'deadline_id',p_deadline_id,'expected_revision',p_expected_revision,'reason',reason));
  SELECT * INTO receipt FROM public.deadline_command_receipts r WHERE r.idempotency_key=p_idempotency_key;
  IF receipt.idempotency_key IS NOT NULL THEN
    IF receipt.actor_user_id=actor.actor_user_id AND receipt.org_id=actor.org_id
      AND receipt.command=expected_command AND receipt.request_fingerprint=fingerprint
      THEN RETURN QUERY SELECT 'ok',receipt.deadline_id,receipt.result_revision,true;
    ELSE RETURN QUERY SELECT 'idempotency_conflict',NULL::uuid,NULL::bigint,false; END IF; RETURN; END IF;
  IF d.origin NOT IN ('manual','document_explicit') OR d.verification_state<>'verified'
    OR d.lifecycle<>'open' OR (d.origin='document_explicit' AND NOT EXISTS(
      SELECT 1 FROM public.deadline_candidate_bindings b JOIN public.documents document
        ON document.id=b.document_id AND document.org_id=b.org_id
      WHERE b.deadline_id=d.id AND b.org_id=d.org_id
        AND document.current_version_id=b.document_version_id
        AND public.review_document_available(document.org_id,document.id)))
    THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  IF d.current_revision<>p_expected_revision THEN
    RETURN QUERY SELECT 'stale_revision',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  next_revision:=d.current_revision+1; PERFORM set_config('casechain.deadline_command','on',true);
  UPDATE public.deadlines SET lifecycle=p_outcome,is_resolved=true,
    resolved_by=actor.actor_user_id,resolved_at=now(),current_revision=next_revision,updated_at=now() WHERE id=d.id;
  INSERT INTO public.deadline_outcomes(deadline_id,org_id,revision,outcome,reason,actor_user_id)
    VALUES(d.id,d.org_id,next_revision,p_outcome,reason,actor.actor_user_id);
  INSERT INTO public.deadline_command_receipts
    VALUES(p_idempotency_key,d.org_id,actor.actor_user_id,expected_command,fingerprint,d.id,next_revision,now());
  RETURN QUERY SELECT 'ok',d.id,next_revision,false;
END $$;

CREATE OR REPLACE FUNCTION public.amend_manual_legal_deadline(
  p_deadline_id uuid,p_expected_revision bigint,p_title text,p_obligation text,p_legal_type text,
  p_due_date date,p_manual_basis text,p_reason text,p_idempotency_key uuid
) RETURNS TABLE(code text,deadline_id uuid,revision bigint,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE d public.deadlines%ROWTYPE; actor record; receipt public.deadline_command_receipts%ROWTYPE;
  fingerprint text; next_revision bigint;
BEGIN
  p_title:=btrim(p_title); p_obligation:=btrim(p_obligation);
  p_manual_basis:=btrim(p_manual_basis); p_reason:=btrim(p_reason);
  IF p_deadline_id IS NULL OR p_title IS NULL OR p_obligation IS NULL OR p_manual_basis IS NULL
    OR p_reason IS NULL OR p_legal_type IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1
    OR p_due_date IS NULL OR p_idempotency_key IS NULL
    OR char_length(p_title) NOT BETWEEN 2 AND 160 OR p_title ~ '[[:cntrl:]]'
    OR char_length(p_obligation) NOT BETWEEN 2 AND 1000 OR p_obligation ~ '[[:cntrl:]]'
    OR char_length(p_manual_basis) NOT BETWEEN 2 AND 500 OR p_manual_basis ~ '[[:cntrl:]]'
    OR char_length(p_reason) NOT BETWEEN 2 AND 500 OR p_reason ~ '[[:cntrl:]]'
    OR p_legal_type NOT IN ('reply_due','appeal_due','payment_or_predeposit_due','compliance_due',
      'stay_application_due','other_legal')
    THEN RETURN QUERY SELECT 'invalid_request',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,159));
  SELECT * INTO d FROM public.deadlines WHERE id=p_deadline_id;
  IF d.id IS NULL THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  SELECT * INTO actor FROM public.deadline_actor_for_matter(d.matter_id,true);
  IF actor.actor_user_id IS NULL OR actor.org_id<>d.org_id THEN
    RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  SELECT * INTO d FROM public.deadlines WHERE id=p_deadline_id AND org_id=actor.org_id FOR UPDATE;
  IF d.id IS NULL THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  fingerprint:=public.deadline_fingerprint(jsonb_build_object('command','amend',
    'deadline_id',p_deadline_id,'expected_revision',p_expected_revision,'title',p_title,
    'obligation',p_obligation,'legal_type',p_legal_type,'due_date',p_due_date,
    'manual_basis',p_manual_basis,'reason',p_reason));
  SELECT * INTO receipt FROM public.deadline_command_receipts r WHERE r.idempotency_key=p_idempotency_key;
  IF receipt.idempotency_key IS NOT NULL THEN
    IF receipt.actor_user_id=actor.actor_user_id AND receipt.org_id=actor.org_id
      AND receipt.command='amend' AND receipt.request_fingerprint=fingerprint
      THEN RETURN QUERY SELECT 'ok',receipt.deadline_id,receipt.result_revision,true;
    ELSE RETURN QUERY SELECT 'idempotency_conflict',NULL::uuid,NULL::bigint,false; END IF; RETURN; END IF;
  IF d.origin NOT IN ('manual','document_explicit') OR d.verification_state<>'verified'
    OR d.lifecycle<>'open' OR (d.origin='document_explicit' AND NOT EXISTS(
      SELECT 1 FROM public.deadline_candidate_bindings b JOIN public.documents document
        ON document.id=b.document_id AND document.org_id=b.org_id
      WHERE b.deadline_id=d.id AND b.org_id=d.org_id
        AND document.current_version_id=b.document_version_id
        AND public.review_document_available(document.org_id,document.id)))
    THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  IF d.current_revision<>p_expected_revision THEN
    RETURN QUERY SELECT 'stale_revision',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  next_revision:=d.current_revision+1; PERFORM set_config('casechain.deadline_command','on',true);
  UPDATE public.deadlines SET title=p_title,description=p_obligation,legal_type=p_legal_type,
    due_date=p_due_date,current_revision=next_revision,updated_at=now() WHERE id=d.id;
  INSERT INTO public.deadline_versions(deadline_id,org_id,revision,title,obligation,legal_type,
    due_date,manual_basis,amendment_reason,actor_user_id)
    VALUES(d.id,d.org_id,next_revision,p_title,p_obligation,p_legal_type,p_due_date,
      p_manual_basis,p_reason,actor.actor_user_id);
  INSERT INTO public.deadline_command_receipts
    VALUES(p_idempotency_key,d.org_id,actor.actor_user_id,'amend',fingerprint,d.id,next_revision,now());
  RETURN QUERY SELECT 'ok',d.id,next_revision,false;
END $$;

CREATE OR REPLACE FUNCTION public.read_current_deadline_attention(p_limit integer DEFAULT 5)
RETURNS TABLE(items jsonb,timezone text,as_of_date date)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE member record; owner boolean; operational_timezone text; today date;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 20 THEN RETURN; END IF;
  SELECT * INTO member FROM public.current_active_tenant_membership();
  IF member.membership_id IS NULL THEN RETURN; END IF;
  SELECT organisation.owner_membership_id=member.membership_id INTO owner
    FROM public.organisations organisation WHERE organisation.id=member.org_id;
  IF NOT ('document.view'=ANY(public.organisation_member_capabilities(
    member.role,coalesce(owner,false),'active'::public.organisation_membership_state))) THEN RETURN; END IF;
  SELECT settings.timezone INTO operational_timezone FROM public.organisation_operational_settings settings
    WHERE settings.org_id=member.org_id AND EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names zone WHERE zone.name=settings.timezone);
  IF operational_timezone IS NULL THEN RETURN; END IF;
  today:=(clock_timestamp() AT TIME ZONE operational_timezone)::date;
  RETURN QUERY SELECT coalesce(jsonb_agg(attention.item ORDER BY attention.due_date,attention.id),'[]'::jsonb),
    operational_timezone,today FROM (
    SELECT deadline.id,deadline.due_date,jsonb_build_object(
      'id',deadline.id,'due_date',deadline.due_date,'type',deadline.type::text,'description',deadline.description,
      'matter_title',matter.title,'client_name',client.name) item
    FROM public.deadlines deadline
    JOIN public.matters matter ON matter.id=deadline.matter_id AND matter.org_id=deadline.org_id
      AND matter.record_state='active' AND matter.deleted_at IS NULL AND matter.work_state='active'
    JOIN public.clients client ON client.id=matter.client_id AND client.org_id=matter.org_id
      AND client.record_state='active' AND client.deleted_at IS NULL
    WHERE deadline.org_id=member.org_id AND deadline.verification_state='verified'
      AND deadline.lifecycle='open' AND NOT deadline.is_resolved
      AND (deadline.origin='manual' OR (deadline.origin='document_explicit' AND EXISTS(
        SELECT 1 FROM public.deadline_candidate_bindings b JOIN public.documents d
          ON d.id=b.document_id AND d.org_id=b.org_id
        WHERE b.deadline_id=deadline.id AND b.org_id=deadline.org_id
          AND d.current_version_id=b.document_version_id
          AND public.review_document_available(d.org_id,d.id))))
    ORDER BY deadline.due_date,deadline.id LIMIT p_limit
  ) attention;
END $$;

REVOKE ALL ON FUNCTION public.produce_explicit_due_date_review(uuid),
  public.materialize_document_version_analysis_before_due_dates(uuid,uuid,text,uuid),
  public.finish_document_processing_ai_extraction_before_due_dates(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb),
  public.read_review_detail_before_due_dates(uuid),
  public.resolve_explicit_due_date_review(uuid,bigint,text,date,text,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_explicit_due_date_review(uuid,bigint,text,date,text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.materialize_document_version_analysis(uuid,uuid,text,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.materialize_document_version_analysis(uuid,uuid,text,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb) TO service_role;
COMMIT;
