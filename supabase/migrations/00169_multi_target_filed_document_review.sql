-- D08-T06: multiple exact, distinct verified Matter keys on one current PDF.
BEGIN;
ALTER TYPE public.review_item_type ADD VALUE 'multi_placement_conflict';
COMMIT;
BEGIN;

ALTER TABLE public.review_items DROP CONSTRAINT review_items_reason_code_check;
ALTER TABLE public.review_items ADD CONSTRAINT review_items_reason_code_check CHECK (
  (type='extraction_conflict' AND reason_code='material_candidate_conflict') OR
  (type='processing_recovery' AND reason_code IN ('invalid_model_output','provider_failed','domain_invalid')) OR
  (type='ambiguous_placement' AND reason_code='multiple_eligible_matters') OR
  (type='deadline_verification' AND reason_code='source_stated_due_date') OR
  (type='placement_conflict' AND reason_code='verified_matter_identity_mismatch') OR
  (type='multi_placement_conflict' AND reason_code='multiple_verified_matter_identity_mismatches'));
ALTER TABLE public.review_items DROP CONSTRAINT review_items_type_shape_check;
ALTER TABLE public.review_items ADD CONSTRAINT review_items_type_shape_check CHECK (
  (type='deadline_verification' AND document_id IS NOT NULL AND document_version_id IS NOT NULL AND binding_id IS NOT NULL AND candidate_sequence>0 AND field_path='document.legal_date.due' AND semantic_candidate_key IS NOT NULL AND field_decision_sequence>=0 AND can_select AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL AND processing_run_id IS NULL AND source_analysis_run_id IS NULL AND source_page_number IS NULL AND document_lifecycle_revision IS NULL)
  OR (type='extraction_conflict' AND document_id IS NOT NULL AND document_version_id IS NOT NULL AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL AND binding_id IS NOT NULL AND candidate_sequence>0 AND field_path IS NOT NULL AND semantic_candidate_key IS NOT NULL AND field_decision_sequence>=0 AND processing_run_id IS NULL AND source_analysis_run_id IS NULL AND source_page_number IS NULL AND document_lifecycle_revision IS NULL)
  OR (type='processing_recovery' AND document_id IS NOT NULL AND document_version_id IS NOT NULL AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL AND binding_id IS NULL AND candidate_sequence IS NULL AND field_path IS NULL AND semantic_candidate_key IS NULL AND field_decision_sequence IS NULL AND NOT can_select AND processing_run_id IS NOT NULL AND source_analysis_run_id IS NOT NULL AND source_page_number=1 AND document_lifecycle_revision>0)
  OR (type='ambiguous_placement' AND document_id IS NULL AND document_version_id IS NULL AND intake_id IS NOT NULL AND placement_run_id IS NOT NULL AND intake_asset_id IS NOT NULL AND binding_id IS NULL AND candidate_sequence IS NULL AND field_path IS NULL AND semantic_candidate_key IS NULL AND field_decision_sequence IS NULL AND can_select AND processing_run_id IS NULL AND source_analysis_run_id IS NULL AND source_page_number=1 AND document_lifecycle_revision IS NULL)
  OR (type IN ('placement_conflict','multi_placement_conflict') AND document_id IS NOT NULL AND document_version_id IS NOT NULL AND binding_id IS NOT NULL AND candidate_sequence>0 AND field_path='document.official_reference.self_identifier' AND semantic_candidate_key IS NOT NULL AND field_decision_sequence>=0 AND NOT can_select AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL AND processing_run_id IS NULL AND source_analysis_run_id IS NULL AND source_page_number IS NOT NULL AND source_page_number>0 AND document_lifecycle_revision>0));

CREATE TABLE public.multi_placement_conflict_sources (
  org_id uuid NOT NULL, review_item_id uuid NOT NULL,
  document_id uuid NOT NULL, document_version_id uuid NOT NULL, candidate_set_key text NOT NULL CHECK(candidate_set_key ~ '^[0-9a-f]{32}$'),
  old_matter_id uuid NOT NULL, old_matter_code text NOT NULL,
  candidate_ordinal integer NOT NULL CHECK(candidate_ordinal>0),
  source_candidate_id uuid NOT NULL, source_analysis_run_id uuid NOT NULL,
  source_page_number integer NOT NULL CHECK(source_page_number>0),
  source_quote text NOT NULL CHECK(char_length(source_quote) BETWEEN 1 AND 1000 AND source_quote !~ '[[:cntrl:]]'),
  source_anchor jsonb NOT NULL,
  target_matter_id uuid NOT NULL, target_matter_code text NOT NULL,
  target_matter_title text NOT NULL, target_client_name text NOT NULL,
  target_identifier_id uuid NOT NULL, target_identifier_revision bigint NOT NULL CHECK(target_identifier_revision>0),
  identifier_kind public.matter_identifier_kind NOT NULL, issuer_namespace_normalized text NOT NULL,
  normalized_value text NOT NULL, display_value text NOT NULL, target_verified_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(review_item_id,target_matter_id), UNIQUE(review_item_id,candidate_ordinal),
  FOREIGN KEY(org_id,review_item_id) REFERENCES public.review_items(org_id,id),
  CHECK(old_matter_id<>target_matter_id));
CREATE TABLE public.multi_placement_conflict_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), org_id uuid NOT NULL, review_item_id uuid NOT NULL,
  expected_revision bigint NOT NULL CHECK(expected_revision>0), result_revision bigint NOT NULL CHECK(result_revision=expected_revision+1),
  action text NOT NULL CHECK(action IN ('keep','move')), reason text NOT NULL CHECK(char_length(reason) BETWEEN 2 AND 500 AND reason=btrim(reason) AND reason !~ '[[:cntrl:]]'),
  actor_user_id uuid NOT NULL REFERENCES auth.users(id), idempotency_key uuid NOT NULL,
  request_fingerprint text NOT NULL CHECK(request_fingerprint ~ '^[0-9a-f]{64}$'), impact_fingerprint text,
  old_matter_id uuid NOT NULL, selected_target_matter_id uuid, document_version_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(org_id,actor_user_id,idempotency_key), FOREIGN KEY(org_id,review_item_id) REFERENCES public.review_items(org_id,id),
  CHECK((action='keep' AND selected_target_matter_id IS NULL AND impact_fingerprint IS NULL) OR
    (action='move' AND selected_target_matter_id IS NOT NULL AND impact_fingerprint ~ '^[0-9a-f]{64}$')));
CREATE TRIGGER multi_placement_conflict_sources_immutable BEFORE UPDATE OR DELETE ON public.multi_placement_conflict_sources FOR EACH ROW EXECUTE FUNCTION public.activity_events_prevent_mutation();
CREATE TRIGGER multi_placement_conflict_decisions_immutable BEFORE UPDATE OR DELETE ON public.multi_placement_conflict_decisions FOR EACH ROW EXECUTE FUNCTION public.activity_events_prevent_mutation();
ALTER TABLE public.multi_placement_conflict_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.multi_placement_conflict_sources FORCE ROW LEVEL SECURITY;
ALTER TABLE public.multi_placement_conflict_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.multi_placement_conflict_decisions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.multi_placement_conflict_sources,public.multi_placement_conflict_decisions FROM PUBLIC,anon,authenticated,service_role;

INSERT INTO public.activity_event_definitions(event_type,event_version,category,subject_types,default_visibility,metadata_contract,renderer_key)
VALUES('review.multi_placement_conflict_decided',1,'review',ARRAY['document'],'matter','{"action":"code","revision":"integer"}','review.multi_placement_conflict_decided.v1');

-- One deterministic, source-grounded representative per distinct active target.
CREATE VIEW public.multi_placement_current_candidates WITH (security_barrier=true) AS
SELECT DISTINCT ON (c.document_id,identifier.matter_id)
  c.org_id,c.document_id,c.document_version_id,c.id source_candidate_id,
  c.document_version_analysis_binding_id binding_id,c.materialization_sequence,c.semantic_candidate_key,
  c.page_number,c.quotation,s.source_analysis_run_id,s.verified_source_anchor,
  identifier.id identifier_id,identifier.matter_id target_matter_id,identifier.revision identifier_revision,
  identifier.identifier_kind,identifier.issuer_namespace_normalized,identifier.normalized_value,
  identifier.display_value,identifier.verified_at,
  target_m.matter_code target_matter_code,target_m.title target_matter_title,target_c.name target_client_name
FROM public.documents d
JOIN public.document_field_candidates c ON c.document_id=d.id AND c.org_id=d.org_id AND c.document_version_id=d.current_version_id
JOIN public.source_field_candidates s ON s.id=c.source_field_candidate_id AND s.org_id=c.org_id
JOIN public.document_version_analysis_bindings b ON b.id=c.document_version_analysis_binding_id AND b.org_id=c.org_id AND b.source_analysis_run_id=s.source_analysis_run_id
JOIN public.matter_identifiers identifier ON identifier.org_id=c.org_id
  AND identifier.identifier_kind::text=c.normalized_value->>'kind'
  AND identifier.issuer_namespace_normalized=c.normalized_value->>'namespace_normalized'
  AND identifier.normalized_value=c.normalized_value->>'normalized_value'
JOIN public.matters target_m ON target_m.id=identifier.matter_id AND target_m.org_id=d.org_id
JOIN public.clients target_c ON target_c.id=target_m.client_id AND target_c.org_id=d.org_id
WHERE c.field_path='document.official_reference.self_identifier' AND c.value_type='structured'
  AND c.validation_state<>'invalid' AND c.normalized_value->>'role'='self_identifier'
  AND c.normalized_value->>'completeness'='complete' AND c.normalized_value->>'match_eligible'='true'
  AND c.normalized_value->>'kind'<>'other_official_reference'
  AND s.verified_source_anchor IS NOT NULL
  AND identifier.lifecycle_state='active' AND identifier.identity_eligible
  AND identifier.identifier_role='self_identifier' AND identifier.verification_method='human_source'
  AND identifier.verified_at IS NOT NULL AND identifier.evidence_purged_at IS NULL
  AND identifier.matter_id<>d.matter_id
  AND target_m.record_state='active' AND target_m.deleted_at IS NULL
  AND target_c.record_state='active' AND target_c.deleted_at IS NULL
ORDER BY c.document_id,identifier.matter_id,c.page_number,c.id,identifier.id;
REVOKE ALL ON public.multi_placement_current_candidates FROM PUBLIC,anon,authenticated,service_role;

ALTER FUNCTION public.reconcile_placed_document_identity_conflict(uuid) RENAME TO reconcile_placed_document_identity_conflict_single;
CREATE FUNCTION public.reconcile_placed_document_identity_conflict(p_document_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE d public.documents%ROWTYPE; candidate_count integer; set_key text; prior_count integer; item_id uuid; first_source record;
BEGIN
  PERFORM public.reconcile_placed_document_identity_conflict_single(p_document_id);
  SELECT * INTO d FROM public.documents WHERE id=p_document_id FOR UPDATE;
  IF d.id IS NULL THEN RETURN; END IF;
  SELECT count(*) INTO candidate_count FROM public.multi_placement_current_candidates WHERE document_id=d.id AND org_id=d.org_id;
  IF candidate_count<2 OR EXISTS(SELECT 1 FROM public.multi_placement_current_candidates c
      WHERE c.document_id=d.id AND c.org_id=d.org_id
      GROUP BY c.identifier_kind,c.issuer_namespace_normalized,c.normalized_value
      HAVING count(DISTINCT c.target_matter_id)>1)
    OR NOT public.review_document_available(d.org_id,d.id)
    OR NOT EXISTS(SELECT 1 FROM public.document_versions v JOIN public.file_assets a ON a.id=v.asset_id AND a.org_id=v.org_id
      WHERE v.id=d.current_version_id AND v.org_id=d.org_id AND v.document_id=d.id AND v.state='current'
      AND v.validation_state='valid' AND a.availability='available' AND a.storage_deleted_at IS NULL)
    OR d.content_availability NOT IN ('source_attached','source_indexed') THEN
    UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
      WHERE org_id=d.org_id AND document_id=d.id AND type='multi_placement_conflict' AND status='needs_review';
    RETURN;
  END IF;
  SELECT md5(string_agg(concat_ws(':',target_matter_id,source_candidate_id,identifier_id,identifier_revision),','
    ORDER BY target_matter_id,source_candidate_id,identifier_id)) INTO set_key
    FROM public.multi_placement_current_candidates WHERE document_id=d.id AND org_id=d.org_id;
  -- A Keep rejects the unchanged source-version, filing and entire candidate set.
  IF EXISTS(SELECT 1 FROM public.multi_placement_conflict_decisions decision
    JOIN public.review_items item ON item.id=decision.review_item_id AND item.org_id=decision.org_id
    WHERE decision.org_id=d.org_id AND item.document_id=d.id AND decision.action='keep'
      AND decision.document_version_id=d.current_version_id AND decision.old_matter_id=d.matter_id
      AND EXISTS(SELECT 1 FROM public.multi_placement_conflict_sources source
        WHERE source.review_item_id=item.id AND source.candidate_set_key=set_key)) THEN
    UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
      WHERE org_id=d.org_id AND document_id=d.id AND type='multi_placement_conflict' AND status='needs_review';
    RETURN;
  END IF;
  UPDATE public.review_items item SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
    WHERE item.org_id=d.org_id AND item.document_id=d.id AND item.type='multi_placement_conflict' AND item.status='needs_review'
      AND NOT EXISTS(SELECT 1 FROM public.multi_placement_conflict_sources s
        WHERE s.review_item_id=item.id AND s.document_version_id=d.current_version_id AND s.old_matter_id=d.matter_id
          AND s.candidate_set_key=set_key);
  IF EXISTS(SELECT 1 FROM public.review_items WHERE org_id=d.org_id AND document_id=d.id
      AND type='multi_placement_conflict' AND status='needs_review') THEN RETURN; END IF;
  SELECT count(*) INTO prior_count FROM public.review_items WHERE org_id=d.org_id AND document_id=d.id
    AND type='multi_placement_conflict' AND EXISTS(SELECT 1 FROM public.multi_placement_conflict_sources source
      WHERE source.review_item_id=review_items.id AND source.candidate_set_key=set_key);
  SELECT * INTO first_source FROM public.multi_placement_current_candidates
    WHERE document_id=d.id AND org_id=d.org_id ORDER BY target_matter_id LIMIT 1;
  INSERT INTO public.review_items(org_id,document_id,document_version_id,binding_id,candidate_sequence,type,reason_code,
    field_path,semantic_candidate_key,impact,priority,priority_reason,can_select,field_decision_sequence,dedupe_key,
    source_page_number,document_lifecycle_revision)
  VALUES(d.org_id,d.id,d.current_version_id,first_source.binding_id,first_source.materialization_sequence,
    'multi_placement_conflict','multiple_verified_matter_identity_mismatches','document.official_reference.self_identifier',first_source.semantic_candidate_key,
    'Current filing remains unchanged. Review every exact printed candidate and one current Move impact before deciding.',
    'high','Multiple verified proceeding keys contradict the current filing.',false,0,
    md5('multi_placement:'||d.id::text||':'||d.current_version_id::text||':'||d.matter_id::text||':'||set_key||':'||prior_count::text),
    first_source.page_number,d.lifecycle_revision) RETURNING id INTO item_id;
  INSERT INTO public.multi_placement_conflict_sources(org_id,review_item_id,document_id,document_version_id,candidate_set_key,old_matter_id,old_matter_code,
    candidate_ordinal,source_candidate_id,source_analysis_run_id,source_page_number,source_quote,source_anchor,
    target_matter_id,target_matter_code,target_matter_title,target_client_name,target_identifier_id,target_identifier_revision,
    identifier_kind,issuer_namespace_normalized,normalized_value,display_value,target_verified_at)
  SELECT d.org_id,item_id,d.id,d.current_version_id,set_key,d.matter_id,coalesce(old_m.matter_code,old_m.id::text),
    row_number() OVER(ORDER BY c.target_matter_id),c.source_candidate_id,c.source_analysis_run_id,c.page_number,c.quotation,c.verified_source_anchor,
    c.target_matter_id,coalesce(c.target_matter_code,c.target_matter_id::text),c.target_matter_title,c.target_client_name,
    c.identifier_id,c.identifier_revision,c.identifier_kind,c.issuer_namespace_normalized,c.normalized_value,c.display_value,c.verified_at
  FROM public.multi_placement_current_candidates c JOIN public.matters old_m ON old_m.id=d.matter_id AND old_m.org_id=d.org_id
  WHERE c.document_id=d.id AND c.org_id=d.org_id;
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
    OR p_type IS NULL OR p_type NOT IN ('extraction_conflict','processing_recovery','ambiguous_placement','deadline_verification','placement_conflict','multi_placement_conflict','all')
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

ALTER FUNCTION public.read_review_detail(uuid) RENAME TO read_review_detail_before_multi_placement;
CREATE FUNCTION public.read_review_detail(p_review_item_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; item public.review_items%ROWTYPE; result jsonb; current_fact boolean;
  old_source public.multi_placement_conflict_sources%ROWTYPE;
  current_matter_id uuid; current_matter_title text; current_matter_code text;
BEGIN
  SELECT * INTO actor FROM public.review_actor(); IF actor.actor_user_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  IF item.id IS NULL THEN RETURN NULL; END IF;
  IF item.type<>'multi_placement_conflict' THEN RETURN public.read_review_detail_before_multi_placement(p_review_item_id); END IF;
  IF NOT public.review_document_available(item.org_id,item.document_id) THEN RETURN NULL; END IF;
  SELECT * INTO old_source FROM public.multi_placement_conflict_sources WHERE review_item_id=item.id ORDER BY candidate_ordinal LIMIT 1;
  IF old_source.review_item_id IS NULL THEN RETURN NULL; END IF;
  current_fact:=public.multi_placement_conflict_current(item.id);
  SELECT m.id,m.title,m.matter_code INTO current_matter_id,current_matter_title,current_matter_code
    FROM public.documents d JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id
    JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id
    WHERE d.id=item.document_id AND d.org_id=item.org_id AND d.record_state='active' AND d.deleted_at IS NULL
      AND m.record_state='active' AND m.deleted_at IS NULL AND c.record_state='active' AND c.deleted_at IS NULL;
  SELECT to_jsonb(item)||jsonb_build_object(
    'document_title',d.display_title,'matter_title',old_m.title,'client_name',old_c.name,
    'version_number',v.version_number,'is_current',d.current_version_id=item.document_version_id,
    'source_identity','Document version '||v.version_number,'record_baseline',NULL,
    'old_matter_id',old_source.old_matter_id,'old_matter_code',old_source.old_matter_code,
    'source_analysis_run_id',old_source.source_analysis_run_id,'source_candidate_id',old_source.source_candidate_id,
    'source_quote',old_source.source_quote,
    'current_matter_id',current_matter_id,'current_matter_title',current_matter_title,'current_matter_code',current_matter_code,
    'conflict_current',coalesce(current_fact,false),
    'allowed_actions',CASE WHEN actor.can_resolve AND current_fact THEN jsonb_build_array('keep_placement','move_placement') ELSE '[]'::jsonb END,
    'evidence',(SELECT coalesce(jsonb_agg(jsonb_build_object('candidate_id',source.target_matter_id,'ordinal',source.candidate_ordinal,
      'selectable',true,'page_number',source.source_page_number,'quotation',source.source_quote,
      'value',jsonb_build_object('target_matter_id',source.target_matter_id,'target_matter_title',source.target_matter_title,
        'target_matter_code',source.target_matter_code,'target_client_name',source.target_client_name,
        'target_identifier_id',source.target_identifier_id,'target_identifier_revision',source.target_identifier_revision,
        'kind',source.identifier_kind,'namespace',source.issuer_namespace_normalized,'normalized_value',source.normalized_value,
        'display',source.display_value,'verified_at',source.target_verified_at,'source_candidate_id',source.source_candidate_id,
        'source_analysis_run_id',source.source_analysis_run_id),
      'validation_state','provisional') ORDER BY source.candidate_ordinal),'[]'::jsonb)
      FROM public.multi_placement_conflict_sources source WHERE source.review_item_id=item.id),
    'last_decision',(SELECT jsonb_build_object('action',decision.action,'selected_candidate_id',decision.selected_target_matter_id,
      'reason',decision.reason,'created_at',decision.created_at)
      FROM public.multi_placement_conflict_decisions decision WHERE decision.review_item_id=item.id
      ORDER BY decision.created_at DESC,decision.id DESC LIMIT 1)
  ) INTO result FROM public.documents d
    JOIN public.document_versions v ON v.id=old_source.document_version_id AND v.org_id=d.org_id AND v.document_id=d.id
    JOIN public.matters old_m ON old_m.id=old_source.old_matter_id AND old_m.org_id=d.org_id
    JOIN public.clients old_c ON old_c.id=old_m.client_id AND old_c.org_id=d.org_id
    WHERE d.id=item.document_id AND d.org_id=item.org_id;
  RETURN result;
END $$;

CREATE FUNCTION public.preview_multi_placement_conflict_move(p_review_item_id uuid,p_target_matter_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; item public.review_items%ROWTYPE; source public.multi_placement_conflict_sources%ROWTYPE;
BEGIN
  SELECT * INTO actor FROM public.review_actor();
  IF actor.actor_user_id IS NULL OR NOT actor.can_resolve THEN RETURN jsonb_build_object('code','forbidden'); END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  SELECT * INTO source FROM public.multi_placement_conflict_sources
    WHERE review_item_id=item.id AND org_id=actor.org_id AND target_matter_id=p_target_matter_id;
  IF item.id IS NULL THEN RETURN jsonb_build_object('code','forbidden'); END IF;
  IF item.type<>'multi_placement_conflict' OR item.status<>'needs_review'
    OR source.review_item_id IS NULL OR NOT public.multi_placement_conflict_current(item.id)
    THEN RETURN jsonb_build_object('code','stale'); END IF;
  RETURN public.preview_document_boundary_repair(item.document_id,source.target_matter_id,'move');
END $$;

CREATE FUNCTION public.multi_placement_conflict_current(p_review_item_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE item public.review_items%ROWTYPE; source public.multi_placement_conflict_sources%ROWTYPE;
  d public.documents%ROWTYPE; current_key text; source_count integer; active_count integer;
BEGIN
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id;
  SELECT * INTO source FROM public.multi_placement_conflict_sources WHERE review_item_id=item.id ORDER BY candidate_ordinal LIMIT 1;
  SELECT * INTO d FROM public.documents WHERE id=item.document_id AND org_id=item.org_id;
  IF item.type<>'multi_placement_conflict' OR item.status<>'needs_review' OR source.review_item_id IS NULL
    OR d.id IS NULL OR d.current_version_id<>source.document_version_id OR d.matter_id<>source.old_matter_id
    OR NOT public.review_document_available(item.org_id,d.id)
    OR NOT EXISTS(SELECT 1 FROM public.document_versions v JOIN public.file_assets a ON a.id=v.asset_id AND a.org_id=v.org_id
      WHERE v.id=d.current_version_id AND v.org_id=d.org_id AND v.document_id=d.id AND v.state='current'
      AND v.validation_state='valid' AND a.availability='available' AND a.storage_deleted_at IS NULL)
    THEN RETURN false; END IF;
  SELECT md5(string_agg(concat_ws(':',target_matter_id,source_candidate_id,identifier_id,identifier_revision),','
    ORDER BY target_matter_id,source_candidate_id,identifier_id)),count(*) INTO current_key,active_count
    FROM public.multi_placement_current_candidates WHERE document_id=d.id AND org_id=d.org_id;
  SELECT count(*) INTO source_count FROM public.multi_placement_conflict_sources WHERE review_item_id=item.id;
  IF active_count<2 OR source_count<>active_count OR current_key<>source.candidate_set_key
    OR EXISTS(SELECT 1 FROM public.multi_placement_current_candidates c
      WHERE c.document_id=d.id AND c.org_id=d.org_id
      GROUP BY c.identifier_kind,c.issuer_namespace_normalized,c.normalized_value
      HAVING count(DISTINCT c.target_matter_id)>1) THEN RETURN false; END IF;
  RETURN NOT EXISTS(SELECT 1 FROM public.multi_placement_conflict_sources s
    LEFT JOIN public.matter_identifiers identifier ON identifier.id=s.target_identifier_id AND identifier.org_id=s.org_id
    LEFT JOIN public.document_field_candidates c ON c.id=s.source_candidate_id AND c.org_id=s.org_id
    LEFT JOIN public.source_field_candidates printed ON printed.id=c.source_field_candidate_id AND printed.org_id=c.org_id
    LEFT JOIN public.document_version_analysis_bindings b ON b.id=c.document_version_analysis_binding_id AND b.org_id=c.org_id
    WHERE s.review_item_id=item.id AND (
      identifier.id IS NULL OR identifier.revision<>s.target_identifier_revision OR identifier.lifecycle_state<>'active'
      OR NOT identifier.identity_eligible OR identifier.identifier_role<>'self_identifier' OR identifier.verification_method<>'human_source'
      OR identifier.matter_id<>s.target_matter_id OR identifier.identifier_kind<>s.identifier_kind
      OR identifier.issuer_namespace_normalized<>s.issuer_namespace_normalized OR identifier.normalized_value<>s.normalized_value
      OR c.id IS NULL OR c.document_version_id<>s.document_version_id OR c.page_number<>s.source_page_number
      OR c.quotation<>s.source_quote OR c.validation_state='invalid' OR c.normalized_value->>'role'<>'self_identifier'
      OR c.normalized_value->>'completeness'<>'complete' OR c.normalized_value->>'match_eligible'<>'true'
      OR printed.id IS NULL OR printed.source_analysis_run_id<>s.source_analysis_run_id
      OR printed.verified_source_anchor<>s.source_anchor OR b.id IS NULL OR b.source_analysis_run_id<>s.source_analysis_run_id));
END $$;

CREATE FUNCTION public.resolve_multi_placement_conflict(
  p_review_item_id uuid,p_expected_revision bigint,p_action text,p_target_matter_id uuid,
  p_expected_impact_fingerprint text,p_reason text,p_idempotency_key uuid
) RETURNS TABLE(code text,current_item jsonb,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public SET lock_timeout='5s' AS $$
DECLARE actor record; item public.review_items%ROWTYPE; source public.multi_placement_conflict_sources%ROWTYPE;
  prior public.multi_placement_conflict_decisions%ROWTYPE; d public.documents%ROWTYPE;
  impact jsonb; moved jsonb; request_hash text; client_id_value uuid;
BEGIN
  IF p_review_item_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1
    OR p_action NOT IN ('keep','move') OR p_idempotency_key IS NULL
    OR p_reason IS NULL OR p_reason<>btrim(p_reason) OR char_length(p_reason) NOT BETWEEN 2 AND 500 OR p_reason ~ '[[:cntrl:]]'
    OR (p_action='keep' AND (p_target_matter_id IS NOT NULL OR p_expected_impact_fingerprint IS NOT NULL))
    OR (p_action='move' AND (p_target_matter_id IS NULL OR p_expected_impact_fingerprint IS NULL
      OR p_expected_impact_fingerprint !~ '^[0-9a-f]{64}$'))
    THEN RETURN QUERY SELECT 'invalid_request',NULL::jsonb,false; RETURN; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text,8051));
  SELECT * INTO actor FROM public.review_actor(true);
  IF actor.actor_user_id IS NULL OR NOT actor.can_resolve THEN RETURN QUERY SELECT 'forbidden',NULL::jsonb,false; RETURN; END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  IF item.id IS NULL OR item.type<>'multi_placement_conflict' THEN RETURN QUERY SELECT 'unavailable',NULL::jsonb,false; RETURN; END IF;
  SELECT * INTO d FROM public.documents WHERE id=item.document_id AND org_id=actor.org_id FOR UPDATE;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id FOR UPDATE;
  -- Freeze the entire snapshotted candidate set, not only the chosen target.
  -- A simultaneous key correction, Trash/Restore, or source-asset transition
  -- must wait or lose to this one decision, never alter an unexamined option.
  PERFORM 1 FROM public.multi_placement_conflict_sources s
    JOIN public.matter_identifiers identifier ON identifier.id=s.target_identifier_id AND identifier.org_id=s.org_id
    WHERE s.review_item_id=item.id ORDER BY identifier.id FOR SHARE OF identifier;
  PERFORM 1 FROM public.multi_placement_conflict_sources s
    JOIN public.matters m ON m.id=s.target_matter_id AND m.org_id=s.org_id
    JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id
    WHERE s.review_item_id=item.id ORDER BY m.id FOR SHARE OF m,c;
  PERFORM 1 FROM public.matters m JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id
    WHERE m.id=d.matter_id AND m.org_id=actor.org_id FOR SHARE OF m,c;
  PERFORM 1 FROM public.document_versions v JOIN public.file_assets a ON a.id=v.asset_id AND a.org_id=v.org_id
    WHERE v.id=d.current_version_id AND v.org_id=actor.org_id FOR SHARE OF v,a;
  request_hash:=encode(extensions.digest(convert_to(jsonb_build_array(p_review_item_id,p_expected_revision,p_action,
    p_target_matter_id,p_expected_impact_fingerprint,p_reason)::text,'utf8'),'sha256'),'hex');
  SELECT * INTO prior FROM public.multi_placement_conflict_decisions decision
    WHERE decision.org_id=actor.org_id AND decision.actor_user_id=actor.actor_user_id AND decision.idempotency_key=p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.request_fingerprint=request_hash THEN RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),true;
    ELSE RETURN QUERY SELECT 'idempotency_conflict',public.read_review_detail(item.id),false; END IF;
    RETURN;
  END IF;
  IF d.id IS NULL OR item.status<>'needs_review' OR item.revision<>p_expected_revision
    OR NOT public.multi_placement_conflict_current(item.id) THEN
    RETURN QUERY SELECT 'stale',public.read_review_detail(item.id),false; RETURN; END IF;
  IF p_action='move' THEN
    SELECT * INTO source FROM public.multi_placement_conflict_sources
      WHERE review_item_id=item.id AND org_id=actor.org_id AND target_matter_id=p_target_matter_id;
    IF source.review_item_id IS NULL THEN RETURN QUERY SELECT 'invalid_target',public.read_review_detail(item.id),false; RETURN; END IF;
    IF NOT public.multi_placement_conflict_current(item.id) THEN RETURN QUERY SELECT 'stale',public.read_review_detail(item.id),false; RETURN; END IF;
    impact:=public.preview_document_boundary_repair(d.id,source.target_matter_id,'move');
    IF impact->>'code'<>'ok' OR impact->>'fingerprint'<>p_expected_impact_fingerprint THEN
      RETURN QUERY SELECT 'stale_preview',public.read_review_detail(item.id),false; RETURN; END IF;
    IF jsonb_array_length(impact->'blockers')>0 THEN RETURN QUERY SELECT 'blocked',public.read_review_detail(item.id),false; RETURN; END IF;
    PERFORM set_config('casechain.placement_review_move','on',true);
    moved:=public.execute_document_boundary_repair(d.id,source.target_matter_id,'move',
      p_expected_impact_fingerprint,p_reason,p_idempotency_key);
    PERFORM set_config('casechain.placement_review_move','',true);
    IF moved->>'code'<>'ok' OR coalesce((moved->>'replayed')::boolean,true) THEN
      RETURN QUERY SELECT coalesce(moved->>'code','failed'),public.read_review_detail(item.id),false; RETURN; END IF;
  ELSE
    SELECT * INTO source FROM public.multi_placement_conflict_sources WHERE review_item_id=item.id ORDER BY candidate_ordinal LIMIT 1;
  END IF;
  SELECT client_id INTO client_id_value FROM public.matters
    WHERE id=CASE WHEN p_action='move' THEN source.target_matter_id ELSE source.old_matter_id END AND org_id=actor.org_id;
  INSERT INTO public.multi_placement_conflict_decisions(org_id,review_item_id,expected_revision,result_revision,action,reason,
    actor_user_id,idempotency_key,request_fingerprint,impact_fingerprint,old_matter_id,selected_target_matter_id,document_version_id)
  VALUES(actor.org_id,item.id,item.revision,item.revision+1,p_action,p_reason,actor.actor_user_id,p_idempotency_key,
    request_hash,p_expected_impact_fingerprint,source.old_matter_id,p_target_matter_id,source.document_version_id);
  UPDATE public.review_items SET status='closed',closure_reason='decision_recorded',closed_at=now(),updated_at=now(),revision=revision+1 WHERE id=item.id;
  PERFORM public.append_activity_event(actor.org_id,'review.multi_placement_conflict_decided',1::smallint,'user',
    actor.actor_user_id,'Member','document',item.document_id,client_id_value,
    CASE WHEN p_action='move' THEN source.target_matter_id ELSE source.old_matter_id END,
    'Document','Filed document Review decision recorded',jsonb_build_object('action',p_action,'revision',item.revision+1),
    'document',item.document_id,item.document_version_id,item.id,NULL,
    'review.multi_placement.'||actor.org_id||'.'||actor.actor_user_id||'.'||p_idempotency_key,now());
  RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),false;
EXCEPTION WHEN lock_not_available OR deadlock_detected THEN RETURN QUERY SELECT 'busy',NULL::jsonb,false;
  WHEN others THEN RETURN QUERY SELECT 'failed',NULL::jsonb,false;
END $$;

REVOKE ALL ON FUNCTION public.reconcile_placed_document_identity_conflict_single(uuid),
  public.reconcile_placed_document_identity_conflict(uuid),public.multi_placement_conflict_current(uuid),
  public.preview_multi_placement_conflict_move(uuid,uuid),public.resolve_multi_placement_conflict(uuid,bigint,text,uuid,text,text,uuid),
  public.read_review_detail_before_multi_placement(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.read_review_queue(text,text,text,text,integer,integer),
  public.read_review_detail(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.read_review_queue(text,text,text,text,integer,integer),
  public.read_review_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.preview_multi_placement_conflict_move(uuid,uuid),
  public.resolve_multi_placement_conflict(uuid,bigint,text,uuid,text,text,uuid) TO authenticated;
COMMIT;
