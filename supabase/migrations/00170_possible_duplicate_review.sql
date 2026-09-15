-- D08-T08: a conservative, exact-key warning between two distinct current PDFs.
BEGIN;
ALTER TYPE public.review_item_type ADD VALUE 'possible_duplicate';
COMMIT;
BEGIN;

ALTER TABLE public.review_items DROP CONSTRAINT review_items_reason_code_check;
ALTER TABLE public.review_items ADD CONSTRAINT review_items_reason_code_check CHECK (
  (type='extraction_conflict' AND reason_code='material_candidate_conflict') OR
  (type='processing_recovery' AND reason_code IN ('invalid_model_output','provider_failed','domain_invalid')) OR
  (type='ambiguous_placement' AND reason_code='multiple_eligible_matters') OR
  (type='deadline_verification' AND reason_code='source_stated_due_date') OR
  (type='placement_conflict' AND reason_code='verified_matter_identity_mismatch') OR
  (type='multi_placement_conflict' AND reason_code='multiple_verified_matter_identity_mismatches') OR
  (type='possible_duplicate' AND reason_code='shared_verified_document_identifier'));
ALTER TABLE public.review_items DROP CONSTRAINT review_items_priority_check;
ALTER TABLE public.review_items ADD CONSTRAINT review_items_priority_check CHECK (
  priority='high' OR (type='possible_duplicate' AND priority='normal'));
ALTER TABLE public.review_items DROP CONSTRAINT review_items_type_shape_check;
ALTER TABLE public.review_items ADD CONSTRAINT review_items_type_shape_check CHECK (
  (type='deadline_verification' AND document_id IS NOT NULL AND document_version_id IS NOT NULL AND binding_id IS NOT NULL AND candidate_sequence>0 AND field_path='document.legal_date.due' AND semantic_candidate_key IS NOT NULL AND field_decision_sequence>=0 AND can_select AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL AND processing_run_id IS NULL AND source_analysis_run_id IS NULL AND source_page_number IS NULL AND document_lifecycle_revision IS NULL)
  OR (type='extraction_conflict' AND document_id IS NOT NULL AND document_version_id IS NOT NULL AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL AND binding_id IS NOT NULL AND candidate_sequence>0 AND field_path IS NOT NULL AND semantic_candidate_key IS NOT NULL AND field_decision_sequence>=0 AND processing_run_id IS NULL AND source_analysis_run_id IS NULL AND source_page_number IS NULL AND document_lifecycle_revision IS NULL)
  OR (type='processing_recovery' AND document_id IS NOT NULL AND document_version_id IS NOT NULL AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL AND binding_id IS NULL AND candidate_sequence IS NULL AND field_path IS NULL AND semantic_candidate_key IS NULL AND field_decision_sequence IS NULL AND NOT can_select AND processing_run_id IS NOT NULL AND source_analysis_run_id IS NOT NULL AND source_page_number=1 AND document_lifecycle_revision>0)
  OR (type='ambiguous_placement' AND document_id IS NULL AND document_version_id IS NULL AND intake_id IS NOT NULL AND placement_run_id IS NOT NULL AND intake_asset_id IS NOT NULL AND binding_id IS NULL AND candidate_sequence IS NULL AND field_path IS NULL AND semantic_candidate_key IS NULL AND field_decision_sequence IS NULL AND can_select AND processing_run_id IS NULL AND source_analysis_run_id IS NULL AND source_page_number=1 AND document_lifecycle_revision IS NULL)
  OR (type IN ('placement_conflict','multi_placement_conflict','possible_duplicate') AND document_id IS NOT NULL AND document_version_id IS NOT NULL AND binding_id IS NOT NULL AND candidate_sequence>0 AND field_path='document.official_reference.self_identifier' AND semantic_candidate_key IS NOT NULL AND field_decision_sequence>=0 AND NOT can_select AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL AND processing_run_id IS NULL AND source_analysis_run_id IS NULL AND source_page_number IS NOT NULL AND source_page_number>0 AND document_lifecycle_revision>0));

CREATE TABLE public.possible_duplicate_sources (
  org_id uuid NOT NULL, review_item_id uuid NOT NULL, ordinal integer NOT NULL CHECK(ordinal IN (1,2)),
  document_id uuid NOT NULL, document_version_id uuid NOT NULL, asset_id uuid NOT NULL,
  identifier_id uuid NOT NULL, identifier_revision bigint NOT NULL CHECK(identifier_revision>0),
  identifier_kind public.matter_identifier_kind NOT NULL, issuer_namespace_normalized text NOT NULL,
  normalized_value text NOT NULL, display_value text NOT NULL,
  evidence_page_number integer NOT NULL CHECK(evidence_page_number>0),
  evidence_quote text NOT NULL CHECK(char_length(evidence_quote) BETWEEN 1 AND 1000),
  verified_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(review_item_id,ordinal), UNIQUE(review_item_id,document_id),
  FOREIGN KEY(org_id,review_item_id) REFERENCES public.review_items(org_id,id));
CREATE TRIGGER possible_duplicate_sources_immutable BEFORE UPDATE OR DELETE ON public.possible_duplicate_sources
  FOR EACH ROW EXECUTE FUNCTION public.activity_events_prevent_mutation();
ALTER TABLE public.possible_duplicate_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.possible_duplicate_sources FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.possible_duplicate_sources FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE public.possible_duplicate_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),org_id uuid NOT NULL,review_item_id uuid NOT NULL,
  expected_revision bigint NOT NULL CHECK(expected_revision>0),result_revision bigint NOT NULL CHECK(result_revision=expected_revision+1),
  action text NOT NULL CHECK(action IN ('distinct_documents','possible_same_document')),
  reason text NOT NULL CHECK(char_length(reason) BETWEEN 2 AND 500 AND reason=btrim(reason) AND reason !~ '[[:cntrl:]]'),
  actor_user_id uuid NOT NULL REFERENCES auth.users(id),idempotency_key uuid NOT NULL,
  request_fingerprint text NOT NULL CHECK(request_fingerprint ~ '^[0-9a-f]{64}$'),
  pair_fingerprint text NOT NULL CHECK(pair_fingerprint ~ '^[0-9a-f]{32}$'),
  created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(org_id,actor_user_id,idempotency_key),
  FOREIGN KEY(org_id,review_item_id) REFERENCES public.review_items(org_id,id));
CREATE TRIGGER possible_duplicate_decisions_immutable BEFORE UPDATE OR DELETE ON public.possible_duplicate_decisions
  FOR EACH ROW EXECUTE FUNCTION public.activity_events_prevent_mutation();
ALTER TABLE public.possible_duplicate_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.possible_duplicate_decisions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.possible_duplicate_decisions FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO public.activity_event_definitions(event_type,event_version,category,subject_types,default_visibility,metadata_contract,renderer_key)
VALUES('review.possible_duplicate_decided',1,'review',ARRAY['document'],'matter','{"action":"code","revision":"integer"}','review.possible_duplicate_decided.v1');

-- One current, source-grounded self identifier per logical document and key.
CREATE VIEW public.possible_duplicate_eligible WITH (security_barrier=true) AS
SELECT i.org_id,i.id identifier_id,i.revision identifier_revision,i.document_id,i.document_version_id,
  v.asset_id,asset.sha256,i.identifier_kind,i.issuer_namespace_normalized,i.normalized_value,i.display_value,
  i.evidence_page_number,i.evidence_quote,i.verified_at,i.document_version_analysis_binding_id binding_id,
  candidate.materialization_sequence,candidate.semantic_candidate_key,d.lifecycle_revision
FROM public.document_self_identifiers i
JOIN public.documents d ON d.org_id=i.org_id AND d.id=i.document_id AND d.current_version_id=i.document_version_id
JOIN public.document_versions v ON v.org_id=d.org_id AND v.document_id=d.id AND v.id=d.current_version_id
JOIN public.file_assets asset ON asset.org_id=v.org_id AND asset.id=v.asset_id
JOIN public.document_field_candidates candidate ON candidate.org_id=i.org_id AND candidate.id=i.document_field_candidate_id
WHERE i.lifecycle_state='active' AND i.evidence_purged_at IS NULL AND i.verified_source_anchor IS NOT NULL
  AND i.identifier_kind<>'other_official_reference' AND i.evidence_quote IS NOT NULL
  AND candidate.document_version_id=i.document_version_id AND candidate.validation_state<>'invalid'
  AND candidate.field_path='document.official_reference.self_identifier'
  AND candidate.normalized_value->>'role'='self_identifier'
  AND candidate.normalized_value->>'completeness'='complete'
  AND candidate.normalized_value->>'match_eligible'='true'
  AND v.state='current' AND v.validation_state='valid' AND asset.sha256 IS NOT NULL AND asset.availability='available'
  AND asset.storage_deleted_at IS NULL AND d.content_availability IN ('source_attached','source_indexed')
  AND d.copied_from_document_id IS NULL AND public.review_document_available(d.org_id,d.id);
REVOKE ALL ON public.possible_duplicate_eligible FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.possible_duplicate_pair_key(p_item_id uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT md5(string_agg(concat_ws(':',s.document_id,s.document_version_id,s.asset_id,s.identifier_id,s.identifier_revision,
    s.evidence_page_number,s.evidence_quote,s.display_value),',' ORDER BY s.ordinal))
  FROM public.possible_duplicate_sources s WHERE s.review_item_id=p_item_id
$$;
CREATE FUNCTION public.possible_duplicate_current(p_item_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE item public.review_items%ROWTYPE; source public.possible_duplicate_sources%ROWTYPE; key_count integer; raw_count integer; current_key text;
BEGIN
  SELECT * INTO item FROM public.review_items WHERE id=p_item_id;
  IF item.id IS NULL OR item.type<>'possible_duplicate' OR item.status<>'needs_review' THEN RETURN false; END IF;
  SELECT * INTO source FROM public.possible_duplicate_sources WHERE review_item_id=item.id AND ordinal=1;
  IF source.review_item_id IS NULL THEN RETURN false; END IF;
  SELECT count(*),md5(string_agg(concat_ws(':',e.document_id,e.document_version_id,e.asset_id,e.identifier_id,e.identifier_revision,
    e.evidence_page_number,e.evidence_quote,e.display_value),',' ORDER BY e.document_id))
    INTO key_count,current_key FROM public.possible_duplicate_eligible e
    WHERE e.org_id=item.org_id AND e.identifier_kind=source.identifier_kind
      AND e.issuer_namespace_normalized=source.issuer_namespace_normalized AND e.normalized_value=source.normalized_value;
  SELECT count(*) INTO raw_count FROM public.document_self_identifiers i WHERE i.org_id=item.org_id
    AND i.identifier_kind=source.identifier_kind AND i.issuer_namespace_normalized=source.issuer_namespace_normalized
    AND i.normalized_value=source.normalized_value AND i.lifecycle_state='active'
    AND i.document_id IS NOT NULL AND i.evidence_purged_at IS NULL;
  RETURN raw_count=2 AND key_count=2 AND current_key=public.possible_duplicate_pair_key(item.id)
    AND (SELECT count(DISTINCT asset_id) FROM public.possible_duplicate_sources WHERE review_item_id=item.id)=2
    AND (SELECT count(DISTINCT sha256) FROM public.possible_duplicate_eligible e WHERE e.org_id=item.org_id
      AND e.identifier_kind=source.identifier_kind AND e.issuer_namespace_normalized=source.issuer_namespace_normalized
      AND e.normalized_value=source.normalized_value)=2
    AND NOT EXISTS(SELECT 1 FROM public.possible_duplicate_sources s WHERE s.review_item_id=item.id
      AND NOT EXISTS(SELECT 1 FROM public.possible_duplicate_eligible e WHERE e.org_id=s.org_id AND e.identifier_id=s.identifier_id
        AND e.identifier_revision=s.identifier_revision AND e.document_id=s.document_id AND e.document_version_id=s.document_version_id
        AND e.asset_id=s.asset_id AND e.evidence_quote=s.evidence_quote AND e.evidence_page_number=s.evidence_page_number
        AND e.display_value=s.display_value));
END $$;

CREATE FUNCTION public.reconcile_possible_duplicate_key(p_org_id uuid,p_kind public.matter_identifier_kind,p_namespace text,p_value text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE pair_count integer; distinct_assets integer; raw_count integer; prior_count integer; pair_key text; first_source record; item_id uuid;
BEGIN
  IF p_org_id IS NULL OR p_kind IS NULL OR p_namespace IS NULL OR p_value IS NULL THEN RETURN; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_org_id::text||':'||p_kind::text||':'||p_namespace||':'||p_value,8078));
  SELECT count(*),count(DISTINCT sha256),
    md5(string_agg(concat_ws(':',document_id,document_version_id,asset_id,identifier_id,identifier_revision,
      evidence_page_number,evidence_quote,display_value),',' ORDER BY document_id))
    INTO pair_count,distinct_assets,pair_key FROM public.possible_duplicate_eligible
    WHERE org_id=p_org_id AND identifier_kind=p_kind AND issuer_namespace_normalized=p_namespace AND normalized_value=p_value;
  SELECT count(*) INTO raw_count FROM public.document_self_identifiers i WHERE i.org_id=p_org_id
    AND i.identifier_kind=p_kind AND i.issuer_namespace_normalized=p_namespace AND i.normalized_value=p_value
    AND i.lifecycle_state='active' AND i.document_id IS NOT NULL AND i.evidence_purged_at IS NULL;
  UPDATE public.review_items item SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
    WHERE item.org_id=p_org_id AND item.type='possible_duplicate' AND item.status='needs_review'
      AND EXISTS(SELECT 1 FROM public.possible_duplicate_sources source WHERE source.review_item_id=item.id
        AND source.identifier_kind=p_kind AND source.issuer_namespace_normalized=p_namespace AND source.normalized_value=p_value)
      AND (raw_count<>2 OR pair_count<>2 OR distinct_assets<>2 OR public.possible_duplicate_pair_key(item.id)<>pair_key OR NOT public.possible_duplicate_current(item.id));
  IF raw_count<>2 OR pair_count<>2 OR distinct_assets<>2 OR EXISTS(SELECT 1 FROM public.review_items item
      JOIN public.possible_duplicate_sources source ON source.review_item_id=item.id AND source.ordinal=1
      WHERE item.org_id=p_org_id AND item.type='possible_duplicate' AND item.status='needs_review'
        AND source.identifier_kind=p_kind AND source.issuer_namespace_normalized=p_namespace AND source.normalized_value=p_value)
    OR EXISTS(SELECT 1 FROM public.possible_duplicate_decisions decision
      WHERE decision.org_id=p_org_id AND decision.pair_fingerprint=pair_key)
    THEN RETURN; END IF;
  SELECT * INTO first_source FROM public.possible_duplicate_eligible e
    WHERE e.org_id=p_org_id AND e.identifier_kind=p_kind AND e.issuer_namespace_normalized=p_namespace AND e.normalized_value=p_value
    ORDER BY e.document_id LIMIT 1;
  SELECT count(*) INTO prior_count FROM public.review_items item JOIN public.possible_duplicate_sources source
    ON source.review_item_id=item.id AND source.ordinal=1
    WHERE item.org_id=p_org_id AND item.type='possible_duplicate' AND public.possible_duplicate_pair_key(item.id)=pair_key;
  INSERT INTO public.review_items(org_id,document_id,document_version_id,binding_id,candidate_sequence,type,reason_code,
    field_path,semantic_candidate_key,impact,priority,priority_reason,can_select,field_decision_sequence,dedupe_key,
    source_page_number,document_lifecycle_revision)
  VALUES(p_org_id,first_source.document_id,first_source.document_version_id,first_source.binding_id,first_source.materialization_sequence,
    'possible_duplicate','shared_verified_document_identifier','document.official_reference.self_identifier',first_source.semantic_candidate_key,
    'Two distinct current PDFs share an exact verified official self-identifier. Compare both sources; no document is blocked or changed.',
    'normal','Exact shared official key needs a human document-identity interpretation.',false,0,
    md5('possible_duplicate:'||p_org_id::text||':'||pair_key||':'||prior_count::text),first_source.evidence_page_number,first_source.lifecycle_revision)
  ON CONFLICT(dedupe_key) DO NOTHING RETURNING id INTO item_id;
  IF item_id IS NULL THEN RETURN; END IF;
  INSERT INTO public.possible_duplicate_sources(org_id,review_item_id,ordinal,document_id,document_version_id,asset_id,
    identifier_id,identifier_revision,identifier_kind,issuer_namespace_normalized,normalized_value,display_value,
    evidence_page_number,evidence_quote,verified_at)
  SELECT p_org_id,item_id,row_number() OVER(ORDER BY e.document_id),e.document_id,e.document_version_id,e.asset_id,
    e.identifier_id,e.identifier_revision,e.identifier_kind,e.issuer_namespace_normalized,e.normalized_value,e.display_value,
    e.evidence_page_number,e.evidence_quote,e.verified_at
  FROM public.possible_duplicate_eligible e WHERE e.org_id=p_org_id AND e.identifier_kind=p_kind
    AND e.issuer_namespace_normalized=p_namespace AND e.normalized_value=p_value;
END $$;

CREATE FUNCTION public.possible_duplicate_identifier_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  PERFORM public.reconcile_possible_duplicate_key(COALESCE(NEW.org_id,OLD.org_id),COALESCE(NEW.identifier_kind,OLD.identifier_kind),
    COALESCE(NEW.issuer_namespace_normalized,OLD.issuer_namespace_normalized),COALESCE(NEW.normalized_value,OLD.normalized_value));
  RETURN COALESCE(NEW,OLD);
END $$;
CREATE TRIGGER possible_duplicate_identifier_changed AFTER INSERT OR UPDATE OF lifecycle_state,revision,evidence_purged_at ON public.document_self_identifiers
  FOR EACH ROW EXECUTE FUNCTION public.possible_duplicate_identifier_changed();

CREATE FUNCTION public.possible_duplicate_document_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE identifier record;
BEGIN
  FOR identifier IN SELECT DISTINCT identifier_kind,issuer_namespace_normalized,normalized_value FROM public.document_self_identifiers
    WHERE org_id=NEW.org_id AND document_id=NEW.id AND lifecycle_state='active' LOOP
    PERFORM public.reconcile_possible_duplicate_key(NEW.org_id,identifier.identifier_kind,identifier.issuer_namespace_normalized,identifier.normalized_value);
  END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER possible_duplicate_document_changed AFTER UPDATE OF current_version_id,record_state,deleted_at,copied_from_document_id,content_availability ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.possible_duplicate_document_changed();

CREATE FUNCTION public.possible_duplicate_asset_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE identifier record;
BEGIN
  FOR identifier IN SELECT DISTINCT i.org_id,i.identifier_kind,i.issuer_namespace_normalized,i.normalized_value
    FROM public.document_versions v JOIN public.document_self_identifiers i ON i.org_id=v.org_id AND i.document_version_id=v.id
    WHERE v.asset_id=NEW.id AND v.org_id=NEW.org_id AND i.lifecycle_state='active' LOOP
    PERFORM public.reconcile_possible_duplicate_key(identifier.org_id,identifier.identifier_kind,identifier.issuer_namespace_normalized,identifier.normalized_value);
  END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER possible_duplicate_asset_changed AFTER UPDATE OF availability,storage_deleted_at ON public.file_assets
  FOR EACH ROW EXECUTE FUNCTION public.possible_duplicate_asset_changed();

ALTER FUNCTION public.read_review_detail(uuid) RENAME TO read_review_detail_before_possible_duplicate;
CREATE FUNCTION public.read_review_detail(p_review_item_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; item public.review_items%ROWTYPE; result jsonb; current_fact boolean;
BEGIN
  SELECT * INTO actor FROM public.review_actor(); IF actor.actor_user_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  IF item.id IS NULL THEN RETURN NULL; END IF;
  IF item.type<>'possible_duplicate' THEN RETURN public.read_review_detail_before_possible_duplicate(p_review_item_id); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.possible_duplicate_sources s WHERE s.review_item_id=item.id
      GROUP BY s.review_item_id HAVING count(*)=2 AND bool_and(public.review_document_available(s.org_id,s.document_id))) THEN RETURN NULL; END IF;
  current_fact:=public.possible_duplicate_current(item.id);
  SELECT (to_jsonb(item)-'source_analysis_run_id')||jsonb_build_object(
    'document_title',d.display_title,'matter_title',m.title,'client_name',c.name,
    'version_number',v.version_number,'is_current',d.current_version_id=item.document_version_id,
    'source_identity','Two exact document versions','record_baseline',NULL,
    'conflict_current',current_fact,
    'allowed_actions',CASE WHEN actor.can_resolve AND current_fact THEN jsonb_build_array('distinct_documents','possible_same_document') ELSE '[]'::jsonb END,
    'evidence',(SELECT jsonb_agg(jsonb_build_object('candidate_id',s.identifier_id,'ordinal',s.ordinal,'selectable',false,
      'page_number',s.evidence_page_number,'quotation',s.evidence_quote,'validation_state','provisional',
      'value',jsonb_build_object('document_id',s.document_id,'document_version_id',s.document_version_id,
        'document_title',source_d.display_title,'version_number',source_v.version_number,
        'matter_title',source_m.title,'client_name',source_c.name,'display',s.display_value,'kind',s.identifier_kind,
        'namespace',s.issuer_namespace_normalized,'normalized_value',s.normalized_value,'verified_at',s.verified_at)) ORDER BY s.ordinal)
      FROM public.possible_duplicate_sources s JOIN public.documents source_d ON source_d.org_id=s.org_id AND source_d.id=s.document_id
      JOIN public.document_versions source_v ON source_v.org_id=s.org_id AND source_v.document_id=s.document_id AND source_v.id=s.document_version_id
      JOIN public.matters source_m ON source_m.org_id=s.org_id AND source_m.id=source_d.matter_id
      JOIN public.clients source_c ON source_c.org_id=s.org_id AND source_c.id=source_m.client_id WHERE s.review_item_id=item.id),
    'last_decision',(SELECT jsonb_build_object('action',decision.action,'selected_candidate_id',NULL,'reason',decision.reason,'created_at',decision.created_at)
      FROM public.possible_duplicate_decisions decision WHERE decision.review_item_id=item.id ORDER BY decision.created_at DESC LIMIT 1)
  ) INTO result FROM public.documents d JOIN public.document_versions v ON v.org_id=d.org_id AND v.document_id=d.id AND v.id=item.document_version_id
    JOIN public.matters m ON m.org_id=d.org_id AND m.id=d.matter_id JOIN public.clients c ON c.org_id=m.org_id AND c.id=m.client_id
    WHERE d.org_id=item.org_id AND d.id=item.document_id;
  RETURN result;
END $$;

DROP FUNCTION public.read_review_queue(text,text,text,text,integer,integer);
CREATE FUNCTION public.read_review_queue(p_status text DEFAULT 'needs_review',p_type text DEFAULT 'all',p_priority text DEFAULT 'all',
  p_search text DEFAULT '',p_page integer DEFAULT 1,p_page_size integer DEFAULT 25)
RETURNS TABLE(items jsonb,total_count bigint,can_resolve boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record;
BEGIN
  SELECT * INTO actor FROM public.review_actor(); IF actor.actor_user_id IS NULL THEN RETURN; END IF;
  IF p_status IS NULL OR p_status NOT IN ('needs_review','closed','all')
    OR p_type IS NULL OR p_type NOT IN ('extraction_conflict','processing_recovery','ambiguous_placement','deadline_verification','placement_conflict','multi_placement_conflict','possible_duplicate','all')
    OR p_priority IS NULL OR p_priority NOT IN ('normal','high','urgent','all')
    OR p_search IS NULL OR char_length(p_search)>200 OR p_page IS NULL OR p_page NOT BETWEEN 1 AND 100000
    OR p_page_size IS NULL OR p_page_size NOT BETWEEN 1 AND 50 THEN RETURN; END IF;
  RETURN QUERY WITH projected AS MATERIALIZED (
    SELECT i.id,i.type,i.field_path,i.reason_code,i.impact,i.priority,i.priority_reason,i.status,i.closure_reason,
      i.revision,i.created_at,i.document_id,i.document_version_id,i.intake_id,i.source_page_number,
      coalesce(d.display_title,s.declared_filename) document_title,
      CASE WHEN i.type='ambiguous_placement' THEN 'Multiple eligible Matters' ELSE m.title END matter_title,
      CASE WHEN i.type='ambiguous_placement' THEN 'Global Intake' ELSE c.name END client_name
    FROM public.review_items i LEFT JOIN public.documents d ON d.id=i.document_id AND d.org_id=i.org_id
    LEFT JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id
    LEFT JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id
    LEFT JOIN public.intake_items intake ON intake.id=i.intake_id AND intake.org_id=i.org_id
    LEFT JOIN public.upload_sessions s ON s.id=intake.upload_session_id AND s.org_id=intake.org_id
    WHERE i.org_id=actor.org_id
      AND ((i.type='ambiguous_placement' AND intake.id IS NOT NULL)
        OR (i.type='possible_duplicate' AND EXISTS(SELECT 1 FROM public.possible_duplicate_sources source
          WHERE source.review_item_id=i.id GROUP BY source.review_item_id HAVING count(*)=2
            AND bool_and(public.review_document_available(source.org_id,source.document_id))))
        OR (i.type NOT IN ('ambiguous_placement','possible_duplicate') AND public.review_document_available(i.org_id,i.document_id)))
      AND (i.status='closed' OR i.type='ambiguous_placement' OR d.current_version_id=i.document_version_id)
  ), filtered AS MATERIALIZED (SELECT * FROM projected WHERE
    (p_status='all' OR status::text=p_status) AND (p_type='all' OR type::text=p_type)
    AND (p_priority='all' OR priority::text=p_priority)
    AND (p_search='' OR strpos(lower(concat_ws(' ',field_path,reason_code,document_title,matter_title,client_name)),lower(p_search))>0)
  ), page_rows AS (SELECT * FROM filtered ORDER BY priority DESC,created_at,id LIMIT p_page_size OFFSET (p_page-1)*p_page_size)
  SELECT coalesce((SELECT jsonb_agg(to_jsonb(page_rows) ORDER BY priority DESC,created_at,id) FROM page_rows),'[]'::jsonb),
    (SELECT count(*) FROM filtered),actor.can_resolve;
END $$;

CREATE FUNCTION public.resolve_possible_duplicate(p_review_item_id uuid,p_expected_revision bigint,p_action text,p_reason text,p_idempotency_key uuid)
RETURNS TABLE(code text,current_item jsonb,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public SET lock_timeout='5s' AS $$
DECLARE actor record; item public.review_items%ROWTYPE; prior public.possible_duplicate_decisions%ROWTYPE;
  request_hash text; pair_key text; first_source public.possible_duplicate_sources%ROWTYPE; client_id_value uuid; matter_id_value uuid;
BEGIN
  IF p_review_item_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1
    OR p_action NOT IN ('distinct_documents','possible_same_document') OR p_idempotency_key IS NULL
    OR p_reason IS NULL OR p_reason<>btrim(p_reason) OR char_length(p_reason) NOT BETWEEN 2 AND 500 OR p_reason ~ '[[:cntrl:]]'
    THEN RETURN QUERY SELECT 'invalid_request',NULL::jsonb,false; RETURN; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text,8081));
  SELECT * INTO actor FROM public.review_actor(true);
  IF actor.actor_user_id IS NULL OR NOT actor.can_resolve THEN RETURN QUERY SELECT 'forbidden',NULL::jsonb,false; RETURN; END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  IF item.id IS NULL OR item.type<>'possible_duplicate' THEN RETURN QUERY SELECT 'unavailable',NULL::jsonb,false; RETURN; END IF;
  PERFORM 1 FROM public.possible_duplicate_sources s JOIN public.documents d ON d.org_id=s.org_id AND d.id=s.document_id
    WHERE s.review_item_id=item.id ORDER BY d.id FOR UPDATE OF d;
  PERFORM 1 FROM public.possible_duplicate_sources s JOIN public.document_versions v ON v.org_id=s.org_id AND v.id=s.document_version_id
    JOIN public.file_assets a ON a.org_id=v.org_id AND a.id=v.asset_id
    WHERE s.review_item_id=item.id ORDER BY v.id FOR SHARE OF v,a;
  PERFORM 1 FROM public.possible_duplicate_sources s JOIN public.document_self_identifiers i ON i.org_id=s.org_id AND i.id=s.identifier_id
    WHERE s.review_item_id=item.id ORDER BY i.id FOR SHARE OF i;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id FOR UPDATE;
  request_hash:=encode(extensions.digest(convert_to(jsonb_build_array(p_review_item_id,p_expected_revision,p_action,p_reason)::text,'utf8'),'sha256'),'hex');
  SELECT * INTO prior FROM public.possible_duplicate_decisions decision WHERE decision.org_id=actor.org_id
    AND decision.actor_user_id=actor.actor_user_id AND decision.idempotency_key=p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.request_fingerprint=request_hash THEN RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),true;
    ELSE RETURN QUERY SELECT 'idempotency_conflict',public.read_review_detail(item.id),false; END IF; RETURN;
  END IF;
  IF item.status<>'needs_review' OR item.revision<>p_expected_revision OR NOT public.possible_duplicate_current(item.id)
    THEN RETURN QUERY SELECT 'stale',public.read_review_detail(item.id),false; RETURN; END IF;
  pair_key:=public.possible_duplicate_pair_key(item.id);
  SELECT * INTO first_source FROM public.possible_duplicate_sources WHERE review_item_id=item.id AND ordinal=1;
  SELECT m.id,m.client_id INTO matter_id_value,client_id_value FROM public.documents d JOIN public.matters m ON m.org_id=d.org_id AND m.id=d.matter_id
    WHERE d.org_id=actor.org_id AND d.id=first_source.document_id;
  INSERT INTO public.possible_duplicate_decisions(org_id,review_item_id,expected_revision,result_revision,action,reason,
    actor_user_id,idempotency_key,request_fingerprint,pair_fingerprint)
  VALUES(actor.org_id,item.id,item.revision,item.revision+1,p_action,p_reason,actor.actor_user_id,p_idempotency_key,request_hash,pair_key);
  UPDATE public.review_items SET status='closed',closure_reason='decision_recorded',closed_at=now(),updated_at=now(),revision=revision+1 WHERE id=item.id;
  PERFORM public.append_activity_event(actor.org_id,'review.possible_duplicate_decided',1::smallint,'user',actor.actor_user_id,'Member',
    'document',first_source.document_id,client_id_value,matter_id_value,'Document','Possible duplicate Review decision recorded',
    jsonb_build_object('action',p_action,'revision',item.revision+1),'document',first_source.document_id,first_source.document_version_id,item.id,NULL,
    'review.possible_duplicate.'||actor.org_id||'.'||actor.actor_user_id||'.'||p_idempotency_key,now());
  RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),false;
EXCEPTION WHEN lock_not_available OR deadlock_detected THEN RETURN QUERY SELECT 'busy',NULL::jsonb,false;
  WHEN others THEN RETURN QUERY SELECT 'failed',NULL::jsonb,false;
END $$;

REVOKE ALL ON FUNCTION public.possible_duplicate_pair_key(uuid),public.possible_duplicate_current(uuid),
  public.reconcile_possible_duplicate_key(uuid,public.matter_identifier_kind,text,text),
  public.possible_duplicate_identifier_changed(),public.possible_duplicate_document_changed(),public.possible_duplicate_asset_changed(),
  public.read_review_detail_before_possible_duplicate(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.read_review_queue(text,text,text,text,integer,integer),public.read_review_detail(uuid),
  public.resolve_possible_duplicate(uuid,bigint,text,text,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.read_review_queue(text,text,text,text,integer,integer),public.read_review_detail(uuid),
  public.resolve_possible_duplicate(uuid,bigint,text,text,uuid) TO authenticated;
COMMIT;
