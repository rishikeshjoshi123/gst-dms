-- D11-T13: a unique exact, current, same-Matter D09 reference proposes only
-- source -> target `refers_to`. It is not effective until one human decision.
BEGIN;
ALTER TYPE public.review_item_type ADD VALUE 'relationship_suggestion';
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
  (type='possible_duplicate' AND reason_code='shared_verified_document_identifier') OR
  (type='relationship_suggestion' AND reason_code='unique_exact_reference'));
ALTER TABLE public.review_items DROP CONSTRAINT review_items_priority_check;
ALTER TABLE public.review_items ADD CONSTRAINT review_items_priority_check CHECK (
  priority='high' OR (type IN ('possible_duplicate','relationship_suggestion') AND priority='normal'));
ALTER TABLE public.review_items DROP CONSTRAINT review_items_type_shape_check;
ALTER TABLE public.review_items ADD CONSTRAINT review_items_type_shape_check CHECK (
  (type='deadline_verification' AND document_id IS NOT NULL AND document_version_id IS NOT NULL AND binding_id IS NOT NULL AND candidate_sequence>0 AND field_path='document.legal_date.due' AND semantic_candidate_key IS NOT NULL AND field_decision_sequence>=0 AND can_select AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL AND processing_run_id IS NULL AND source_analysis_run_id IS NULL AND source_page_number IS NULL AND document_lifecycle_revision IS NULL)
  OR (type='extraction_conflict' AND document_id IS NOT NULL AND document_version_id IS NOT NULL AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL AND binding_id IS NOT NULL AND candidate_sequence>0 AND field_path IS NOT NULL AND semantic_candidate_key IS NOT NULL AND field_decision_sequence>=0 AND processing_run_id IS NULL AND source_analysis_run_id IS NULL AND source_page_number IS NULL AND document_lifecycle_revision IS NULL)
  OR (type='processing_recovery' AND document_id IS NOT NULL AND document_version_id IS NOT NULL AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL AND binding_id IS NULL AND candidate_sequence IS NULL AND field_path IS NULL AND semantic_candidate_key IS NULL AND field_decision_sequence IS NULL AND NOT can_select AND processing_run_id IS NOT NULL AND source_analysis_run_id IS NOT NULL AND source_page_number=1 AND document_lifecycle_revision>0)
  OR (type='ambiguous_placement' AND document_id IS NULL AND document_version_id IS NULL AND intake_id IS NOT NULL AND placement_run_id IS NOT NULL AND intake_asset_id IS NOT NULL AND binding_id IS NULL AND candidate_sequence IS NULL AND field_path IS NULL AND semantic_candidate_key IS NULL AND field_decision_sequence IS NULL AND can_select AND processing_run_id IS NULL AND source_analysis_run_id IS NULL AND source_page_number=1 AND document_lifecycle_revision IS NULL)
  OR (type IN ('placement_conflict','multi_placement_conflict','possible_duplicate') AND document_id IS NOT NULL AND document_version_id IS NOT NULL AND binding_id IS NOT NULL AND candidate_sequence>0 AND field_path='document.official_reference.self_identifier' AND semantic_candidate_key IS NOT NULL AND field_decision_sequence>=0 AND NOT can_select AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL AND processing_run_id IS NULL AND source_analysis_run_id IS NULL AND source_page_number IS NOT NULL AND source_page_number>0 AND document_lifecycle_revision>0)
  OR (type='relationship_suggestion' AND document_id IS NOT NULL AND document_version_id IS NOT NULL AND binding_id IS NOT NULL AND candidate_sequence>0 AND field_path='document.official_reference.outbound_mention' AND semantic_candidate_key IS NOT NULL AND field_decision_sequence>=0 AND NOT can_select AND intake_id IS NULL AND placement_run_id IS NULL AND intake_asset_id IS NULL AND processing_run_id IS NULL AND source_analysis_run_id IS NOT NULL AND source_page_number IS NOT NULL AND source_page_number>0 AND document_lifecycle_revision>0));

CREATE TABLE public.relationship_suggestion_sources (
  org_id uuid NOT NULL, review_item_id uuid PRIMARY KEY, mention_id uuid NOT NULL,
  resolution_run_id uuid NOT NULL, resolution_result_id uuid NOT NULL,
  target_identifier_id uuid NOT NULL, target_identifier_revision bigint NOT NULL CHECK(target_identifier_revision>0),
  source_document_id uuid NOT NULL, source_document_version_id uuid NOT NULL,
  source_lifecycle_revision bigint NOT NULL CHECK(source_lifecycle_revision>0),
  target_document_id uuid NOT NULL, target_document_version_id uuid NOT NULL,
  target_lifecycle_revision bigint NOT NULL CHECK(target_lifecycle_revision>0),
  matter_id uuid NOT NULL, matter_revision bigint NOT NULL CHECK(matter_revision>0),
  client_id uuid NOT NULL, client_revision bigint NOT NULL CHECK(client_revision>0),
  source_asset_id uuid NOT NULL, source_asset_sha256 text NOT NULL CHECK(source_asset_sha256 ~ '^[0-9a-f]{64}$'),
  target_asset_id uuid NOT NULL, target_asset_sha256 text NOT NULL CHECK(target_asset_sha256 ~ '^[0-9a-f]{64}$'),
  source_field_candidate_id uuid NOT NULL, source_analysis_run_id uuid NOT NULL, source_binding_id uuid NOT NULL,
  identifier_kind public.matter_identifier_kind NOT NULL, issuer_namespace_normalized text NOT NULL, normalized_value text NOT NULL,
  mention_catalogue_version text NOT NULL, mention_normalizer_version text NOT NULL,
  evidence_page_number integer NOT NULL CHECK(evidence_page_number>0),
  evidence_quote text NOT NULL CHECK(char_length(evidence_quote) BETWEEN 1 AND 1000),
  verified_source_anchor jsonb NOT NULL CHECK(jsonb_typeof(verified_source_anchor)='object'),
  proposed_relationship_type public.document_relationship_type NOT NULL CHECK(proposed_relationship_type='refers_to'),
  proposed_catalogue_version integer NOT NULL CHECK(proposed_catalogue_version>0),
  source_fingerprint text NOT NULL CHECK(source_fingerprint ~ '^[0-9a-f]{64}$'), created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(org_id,review_item_id) REFERENCES public.review_items(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,mention_id) REFERENCES public.document_reference_mentions(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,resolution_run_id) REFERENCES public.document_reference_resolution_runs(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,resolution_result_id) REFERENCES public.document_reference_resolution_results(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,target_identifier_id) REFERENCES public.document_self_identifiers(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,source_document_id) REFERENCES public.documents(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,target_document_id) REFERENCES public.documents(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,source_document_id,source_document_version_id) REFERENCES public.document_versions(org_id,document_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,target_document_id,target_document_version_id) REFERENCES public.document_versions(org_id,document_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,matter_id) REFERENCES public.matters(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,client_id) REFERENCES public.clients(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,source_asset_id) REFERENCES public.file_assets(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,target_asset_id) REFERENCES public.file_assets(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,source_field_candidate_id) REFERENCES public.document_field_candidates(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,source_analysis_run_id) REFERENCES public.source_analysis_runs(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,source_binding_id) REFERENCES public.document_version_analysis_bindings(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(proposed_relationship_type,proposed_catalogue_version) REFERENCES public.document_relationship_catalogue(relationship_type,catalogue_version) ON DELETE RESTRICT,
  CHECK(source_document_id<>target_document_id),
  CHECK(char_length(issuer_namespace_normalized) BETWEEN 2 AND 160 AND char_length(normalized_value) BETWEEN 1 AND 300));
CREATE INDEX relationship_suggestion_sources_mention_idx ON public.relationship_suggestion_sources(org_id,mention_id,created_at DESC);
CREATE INDEX relationship_suggestion_sources_documents_idx ON public.relationship_suggestion_sources(org_id,source_document_id,target_document_id);

CREATE TABLE public.relationship_suggestion_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), org_id uuid NOT NULL, review_item_id uuid NOT NULL,
  expected_revision bigint NOT NULL CHECK(expected_revision>0), result_revision bigint NOT NULL CHECK(result_revision=expected_revision+1),
  action text NOT NULL CHECK(action IN ('accept_relationship','correct_relationship','reject_relationship')),
  relationship_id uuid, relationship_type public.document_relationship_type, catalogue_version integer,
  source_document_id uuid, target_document_id uuid,
  reason text NOT NULL CHECK(char_length(reason) BETWEEN 2 AND 500 AND reason=btrim(reason) AND reason !~ '[[:cntrl:]]'),
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT, idempotency_key uuid NOT NULL,
  request_fingerprint text NOT NULL CHECK(request_fingerprint ~ '^[0-9a-f]{64}$'),
  source_fingerprint text NOT NULL CHECK(source_fingerprint ~ '^[0-9a-f]{64}$'), created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(org_id,actor_user_id,idempotency_key),
  FOREIGN KEY(org_id,review_item_id) REFERENCES public.review_items(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,relationship_id) REFERENCES public.document_relationships(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(relationship_type,catalogue_version) REFERENCES public.document_relationship_catalogue(relationship_type,catalogue_version) ON DELETE RESTRICT,
  CHECK((action='reject_relationship' AND relationship_id IS NULL AND relationship_type IS NULL AND catalogue_version IS NULL AND source_document_id IS NULL AND target_document_id IS NULL)
    OR (action<>'reject_relationship' AND relationship_id IS NOT NULL AND relationship_type IS NOT NULL AND catalogue_version IS NOT NULL AND source_document_id IS NOT NULL AND target_document_id IS NOT NULL AND source_document_id<>target_document_id)));
CREATE INDEX relationship_suggestion_decisions_source_idx ON public.relationship_suggestion_decisions(org_id,source_fingerprint);
CREATE TRIGGER relationship_suggestion_sources_immutable BEFORE UPDATE OR DELETE ON public.relationship_suggestion_sources FOR EACH ROW EXECUTE FUNCTION public.activity_events_prevent_mutation();
CREATE TRIGGER relationship_suggestion_decisions_immutable BEFORE UPDATE OR DELETE ON public.relationship_suggestion_decisions FOR EACH ROW EXECUTE FUNCTION public.activity_events_prevent_mutation();
ALTER TABLE public.relationship_suggestion_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.relationship_suggestion_sources FORCE ROW LEVEL SECURITY;
ALTER TABLE public.relationship_suggestion_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.relationship_suggestion_decisions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.relationship_suggestion_sources,public.relationship_suggestion_decisions FROM PUBLIC,anon,authenticated,service_role;

CREATE VIEW public.relationship_suggestion_eligible WITH (security_barrier=true) AS
WITH latest_refers_to AS (
  SELECT * FROM public.document_relationship_catalogue WHERE relationship_type='refers_to' ORDER BY catalogue_version DESC LIMIT 1
), eligible AS (
  SELECT mention.org_id,mention.id mention_id,current_resolution.run_id resolution_run_id,current_resolution.result_id resolution_result_id,
    current_resolution.target_identifier_id,target_identifier.revision target_identifier_revision,
    source_document.id source_document_id,source_document.current_version_id source_document_version_id,source_document.lifecycle_revision source_lifecycle_revision,
    target_document.id target_document_id,target_document.current_version_id target_document_version_id,target_document.lifecycle_revision target_lifecycle_revision,
    source_document.matter_id,matter.revision matter_revision,matter.client_id,client.revision client_revision,
    source_version.asset_id source_asset_id,source_asset.sha256 source_asset_sha256,target_version.asset_id target_asset_id,target_asset.sha256 target_asset_sha256,
    mention.document_field_candidate_id source_field_candidate_id,mention.source_analysis_run_id,mention.document_version_analysis_binding_id source_binding_id,
    candidate.materialization_sequence,candidate.semantic_candidate_key,mention.identifier_kind,mention.issuer_namespace_normalized,mention.normalized_value,
    mention.catalogue_version mention_catalogue_version,mention.normalizer_version mention_normalizer_version,
    mention.evidence_page_number,mention.evidence_quote,mention.verified_source_anchor,
    catalogue.relationship_type proposed_relationship_type,catalogue.catalogue_version proposed_catalogue_version
  FROM public.document_reference_mentions mention
  JOIN public.current_document_reference_resolutions current_resolution ON current_resolution.org_id=mention.org_id AND current_resolution.mention_id=mention.id
    AND current_resolution.outcome='unique_exact' AND current_resolution.source_document_id=mention.source_document_id
  JOIN public.document_reference_resolution_results resolution_result ON resolution_result.org_id=current_resolution.org_id
    AND resolution_result.id=current_resolution.result_id AND resolution_result.run_id=current_resolution.run_id AND resolution_result.mention_id=mention.id
    AND resolution_result.outcome='unique_exact' AND resolution_result.target_document_id=current_resolution.target_document_id
    AND resolution_result.target_identifier_id=current_resolution.target_identifier_id
  JOIN public.document_self_identifiers target_identifier ON target_identifier.org_id=current_resolution.org_id
    AND target_identifier.id=current_resolution.target_identifier_id AND target_identifier.document_id=current_resolution.target_document_id
    AND target_identifier.lifecycle_state='active' AND target_identifier.evidence_purged_at IS NULL
    AND target_identifier.issuer_namespace_normalized=mention.issuer_namespace_normalized
    AND target_identifier.identifier_kind=mention.identifier_kind AND target_identifier.normalized_value=mention.normalized_value
  JOIN public.documents source_document ON source_document.org_id=mention.org_id AND source_document.id=mention.source_document_id
    AND source_document.current_version_id=mention.source_document_version_id
  JOIN public.documents target_document ON target_document.org_id=mention.org_id AND target_document.id=current_resolution.target_document_id
    AND target_document.current_version_id=target_identifier.document_version_id
  JOIN public.document_versions source_version ON source_version.org_id=source_document.org_id AND source_version.id=source_document.current_version_id
    AND source_version.document_id=source_document.id AND source_version.state='current' AND source_version.validation_state='valid'
  JOIN public.document_versions target_version ON target_version.org_id=target_document.org_id AND target_version.id=target_document.current_version_id
    AND target_version.document_id=target_document.id AND target_version.state='current' AND target_version.validation_state='valid'
  JOIN public.file_assets source_asset ON source_asset.org_id=source_version.org_id AND source_asset.id=source_version.asset_id
    AND source_asset.availability='available' AND source_asset.storage_deleted_at IS NULL AND source_asset.sha256 IS NOT NULL
  JOIN public.file_assets target_asset ON target_asset.org_id=target_version.org_id AND target_asset.id=target_version.asset_id
    AND target_asset.availability='available' AND target_asset.storage_deleted_at IS NULL AND target_asset.sha256 IS NOT NULL
  JOIN public.document_field_candidates candidate ON candidate.org_id=mention.org_id AND candidate.id=mention.document_field_candidate_id
    AND candidate.document_id=source_document.id AND candidate.document_version_id=source_version.id
    AND candidate.document_version_analysis_binding_id=mention.document_version_analysis_binding_id
    AND candidate.field_path='document.official_reference.outbound_mention' AND candidate.validation_state<>'invalid'
  JOIN public.document_version_analysis_bindings binding ON binding.org_id=mention.org_id AND binding.id=mention.document_version_analysis_binding_id
    AND binding.document_version_id=source_version.id AND binding.source_analysis_run_id=mention.source_analysis_run_id
  JOIN public.source_analysis_runs analysis ON analysis.org_id=mention.org_id AND analysis.id=mention.source_analysis_run_id
    AND analysis.asset_id=source_version.asset_id AND analysis.state='succeeded'
  JOIN public.matters matter ON matter.org_id=source_document.org_id AND matter.id=source_document.matter_id
    AND target_document.matter_id=matter.id AND matter.record_state='active' AND matter.deleted_at IS NULL AND matter.work_state IS DISTINCT FROM 'closed'
  JOIN public.clients client ON client.org_id=matter.org_id AND client.id=matter.client_id AND client.record_state='active' AND client.deleted_at IS NULL
  CROSS JOIN latest_refers_to catalogue
  WHERE mention.evidence_purged_at IS NULL AND mention.verified_source_anchor IS NOT NULL AND mention.evidence_page_number>0 AND mention.evidence_quote IS NOT NULL
    AND source_document.id<>target_document.id AND source_document.record_state='active' AND source_document.deleted_at IS NULL AND source_document.document_class='proceeding'
    AND target_document.record_state='active' AND target_document.deleted_at IS NULL AND target_document.document_class='proceeding'
    AND source_document.copied_from_document_id IS NULL AND target_document.copied_from_document_id IS NULL
    AND source_document.content_availability IN ('source_attached','source_indexed') AND target_document.content_availability IN ('source_attached','source_indexed')
    AND 'proceeding'=ANY(catalogue.allowed_source_classes) AND 'proceeding'=ANY(catalogue.allowed_target_classes)
    AND public.review_document_available(source_document.org_id,source_document.id) AND public.review_document_available(target_document.org_id,target_document.id)
    AND NOT EXISTS(SELECT 1 FROM public.document_relationships relationship WHERE relationship.org_id=source_document.org_id AND relationship.lifecycle_state='active'
      AND ((relationship.source_document_id=source_document.id AND relationship.target_document_id=target_document.id)
        OR (relationship.source_document_id=target_document.id AND relationship.target_document_id=source_document.id)))
)
SELECT eligible.*,encode(extensions.digest(convert_to(jsonb_build_array(
  mention_id,resolution_run_id,resolution_result_id,target_identifier_id,target_identifier_revision,
  source_document_id,source_document_version_id,source_lifecycle_revision,target_document_id,target_document_version_id,target_lifecycle_revision,
  matter_id,matter_revision,client_id,client_revision,source_asset_id,source_asset_sha256,target_asset_id,target_asset_sha256,
  source_field_candidate_id,source_analysis_run_id,source_binding_id,identifier_kind,issuer_namespace_normalized,normalized_value,
  mention_catalogue_version,mention_normalizer_version,evidence_page_number,evidence_quote,verified_source_anchor,
  proposed_relationship_type,proposed_catalogue_version)::text,'utf8'),'sha256'),'hex') source_fingerprint FROM eligible;
REVOKE ALL ON public.relationship_suggestion_eligible FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.relationship_suggestion_current(p_review_item_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT EXISTS(SELECT 1 FROM public.review_items item
  JOIN public.relationship_suggestion_sources source ON source.org_id=item.org_id AND source.review_item_id=item.id
  JOIN public.relationship_suggestion_eligible eligible ON eligible.org_id=source.org_id AND eligible.mention_id=source.mention_id
  WHERE item.id=p_review_item_id AND item.type='relationship_suggestion' AND item.status='needs_review'
    AND eligible.source_fingerprint=source.source_fingerprint)
$$;

CREATE FUNCTION public.reconcile_exact_reference_relationship(p_mention_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE eligible public.relationship_suggestion_eligible%ROWTYPE; item_id uuid; prior_count integer;
BEGIN
  IF p_mention_id IS NULL THEN RETURN; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_mention_id::text,8173));
  SELECT * INTO eligible FROM public.relationship_suggestion_eligible WHERE mention_id=p_mention_id;
  UPDATE public.review_items item SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
  WHERE item.type='relationship_suggestion' AND item.status='needs_review'
    AND EXISTS(SELECT 1 FROM public.relationship_suggestion_sources source WHERE source.review_item_id=item.id AND source.mention_id=p_mention_id)
    AND (eligible.mention_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.relationship_suggestion_sources source
      WHERE source.review_item_id=item.id AND source.source_fingerprint=eligible.source_fingerprint));
  IF eligible.mention_id IS NULL
    OR EXISTS(SELECT 1 FROM public.review_items item JOIN public.relationship_suggestion_sources source ON source.review_item_id=item.id
      WHERE item.type='relationship_suggestion' AND item.status='needs_review' AND source.mention_id=p_mention_id AND source.source_fingerprint=eligible.source_fingerprint)
    OR EXISTS(SELECT 1 FROM public.relationship_suggestion_decisions decision WHERE decision.org_id=eligible.org_id AND decision.source_fingerprint=eligible.source_fingerprint)
    THEN RETURN; END IF;
  SELECT count(*) INTO prior_count FROM public.relationship_suggestion_sources WHERE org_id=eligible.org_id AND mention_id=p_mention_id;
  INSERT INTO public.review_items(org_id,document_id,document_version_id,binding_id,candidate_sequence,type,reason_code,field_path,
    semantic_candidate_key,impact,priority,priority_reason,can_select,field_decision_sequence,dedupe_key,source_analysis_run_id,
    source_page_number,document_lifecycle_revision)
  VALUES(eligible.org_id,eligible.source_document_id,eligible.source_document_version_id,eligible.source_binding_id,eligible.materialization_sequence,
    'relationship_suggestion','unique_exact_reference','document.official_reference.outbound_mention',eligible.semantic_candidate_key,
    'A current PDF exactly references another current proceeding in this Matter. Decide whether to record an inspectable relationship.',
    'normal','A unique exact source reference needs a human relationship decision.',false,0,
    md5('relationship_suggestion:'||eligible.source_fingerprint||':'||prior_count::text),eligible.source_analysis_run_id,
    eligible.evidence_page_number,eligible.source_lifecycle_revision)
  ON CONFLICT(dedupe_key) DO NOTHING RETURNING id INTO item_id;
  IF item_id IS NULL THEN RETURN; END IF;
  INSERT INTO public.relationship_suggestion_sources(org_id,review_item_id,mention_id,resolution_run_id,resolution_result_id,target_identifier_id,
    target_identifier_revision,source_document_id,source_document_version_id,source_lifecycle_revision,target_document_id,target_document_version_id,
    target_lifecycle_revision,matter_id,matter_revision,client_id,client_revision,source_asset_id,source_asset_sha256,target_asset_id,target_asset_sha256,
    source_field_candidate_id,source_analysis_run_id,source_binding_id,identifier_kind,issuer_namespace_normalized,normalized_value,
    mention_catalogue_version,mention_normalizer_version,evidence_page_number,evidence_quote,verified_source_anchor,
    proposed_relationship_type,proposed_catalogue_version,source_fingerprint)
  VALUES(eligible.org_id,item_id,eligible.mention_id,eligible.resolution_run_id,eligible.resolution_result_id,eligible.target_identifier_id,
    eligible.target_identifier_revision,eligible.source_document_id,eligible.source_document_version_id,eligible.source_lifecycle_revision,
    eligible.target_document_id,eligible.target_document_version_id,eligible.target_lifecycle_revision,eligible.matter_id,eligible.matter_revision,
    eligible.client_id,eligible.client_revision,eligible.source_asset_id,eligible.source_asset_sha256,eligible.target_asset_id,eligible.target_asset_sha256,
    eligible.source_field_candidate_id,eligible.source_analysis_run_id,eligible.source_binding_id,eligible.identifier_kind,
    eligible.issuer_namespace_normalized,eligible.normalized_value,eligible.mention_catalogue_version,eligible.mention_normalizer_version,
    eligible.evidence_page_number,eligible.evidence_quote,eligible.verified_source_anchor,eligible.proposed_relationship_type,
    eligible.proposed_catalogue_version,eligible.source_fingerprint);
END $$;

CREATE FUNCTION public.resolve_relationship_suggestion(
  p_review_item_id uuid,p_expected_revision bigint,p_action text,p_relationship_type public.document_relationship_type,
  p_catalogue_version integer,p_source_document_id uuid,p_target_document_id uuid,p_reason text,p_idempotency_key uuid)
RETURNS TABLE(code text,current_item jsonb,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public SET lock_timeout='5s' AS $$
DECLARE actor record; item public.review_items%ROWTYPE; source public.relationship_suggestion_sources%ROWTYPE;
  prior public.relationship_suggestion_decisions%ROWTYPE; catalogue public.document_relationship_catalogue%ROWTYPE;
  relationship public.document_relationships%ROWTYPE; request_hash text; latest_version integer;
  selected_action public.document_relationship_decision_action;
BEGIN
  IF p_review_item_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1
    OR p_action NOT IN ('accept_relationship','correct_relationship','reject_relationship') OR p_idempotency_key IS NULL
    OR p_reason IS NULL OR p_reason<>btrim(p_reason) OR char_length(p_reason) NOT BETWEEN 2 AND 500 OR p_reason ~ '[[:cntrl:]]'
    OR (p_action='reject_relationship' AND (p_relationship_type IS NOT NULL OR p_catalogue_version IS NOT NULL OR p_source_document_id IS NOT NULL OR p_target_document_id IS NOT NULL))
    OR (p_action<>'reject_relationship' AND (p_relationship_type IS NULL OR p_catalogue_version IS NULL OR p_catalogue_version<1
      OR p_source_document_id IS NULL OR p_target_document_id IS NULL OR p_source_document_id=p_target_document_id))
    THEN RETURN QUERY SELECT 'invalid_request',NULL::jsonb,false; RETURN; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text,8173));
  SELECT * INTO actor FROM public.review_actor(true);
  IF actor.actor_user_id IS NULL OR NOT actor.can_resolve THEN RETURN QUERY SELECT 'forbidden',NULL::jsonb,false; RETURN; END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  IF item.id IS NULL OR item.type<>'relationship_suggestion' THEN RETURN QUERY SELECT 'unavailable',NULL::jsonb,false; RETURN; END IF;
  SELECT * INTO source FROM public.relationship_suggestion_sources WHERE review_item_id=item.id AND org_id=actor.org_id;
  IF source.review_item_id IS NULL THEN RETURN QUERY SELECT 'unavailable',NULL::jsonb,false; RETURN; END IF;
  request_hash:=encode(extensions.digest(convert_to(jsonb_build_array(p_review_item_id,p_expected_revision,p_action,
    p_relationship_type,p_catalogue_version,p_source_document_id,p_target_document_id,p_reason)::text,'utf8'),'sha256'),'hex');
  SELECT * INTO prior FROM public.relationship_suggestion_decisions decision WHERE decision.org_id=actor.org_id
    AND decision.actor_user_id=actor.actor_user_id AND decision.idempotency_key=p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.request_fingerprint=request_hash THEN RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),true;
    ELSE RETURN QUERY SELECT 'idempotency_conflict',public.read_review_detail(item.id),false; END IF; RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(source.org_id::text||':'||source.matter_id::text,146));
  LOCK TABLE public.document_relationship_catalogue IN SHARE MODE;
  PERFORM 1 FROM public.matters matter JOIN public.clients client ON client.org_id=matter.org_id AND client.id=matter.client_id
    WHERE matter.org_id=source.org_id AND matter.id=source.matter_id FOR UPDATE OF matter,client;
  PERFORM 1 FROM public.documents document WHERE document.org_id=source.org_id
    AND document.id IN(source.source_document_id,source.target_document_id) ORDER BY document.id FOR UPDATE;
  PERFORM 1 FROM public.document_versions version JOIN public.file_assets asset ON asset.org_id=version.org_id AND asset.id=version.asset_id
    WHERE version.org_id=source.org_id AND version.id IN(source.source_document_version_id,source.target_document_version_id)
    ORDER BY version.id FOR SHARE OF version,asset;
  PERFORM 1 FROM public.document_self_identifiers identifier WHERE identifier.org_id=source.org_id AND identifier.id=source.target_identifier_id FOR SHARE;
  PERFORM 1 FROM public.current_document_reference_resolutions resolution WHERE resolution.org_id=source.org_id AND resolution.mention_id=source.mention_id FOR SHARE;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id FOR UPDATE;
  IF item.status<>'needs_review' OR item.revision<>p_expected_revision OR NOT public.relationship_suggestion_current(item.id) THEN
    IF item.status='needs_review' THEN UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1 WHERE id=item.id; END IF;
    RETURN QUERY SELECT 'stale',public.read_review_detail(item.id),false; RETURN;
  END IF;
  IF p_action<>'reject_relationship' THEN
    IF NOT (ARRAY[p_source_document_id,p_target_document_id]::uuid[] @> ARRAY[source.source_document_id,source.target_document_id]::uuid[]
      AND ARRAY[p_source_document_id,p_target_document_id]::uuid[] <@ ARRAY[source.source_document_id,source.target_document_id]::uuid[])
      OR (p_action='accept_relationship' AND (p_source_document_id<>source.source_document_id OR p_target_document_id<>source.target_document_id
        OR p_relationship_type<>'refers_to' OR p_catalogue_version<>source.proposed_catalogue_version))
      THEN RETURN QUERY SELECT 'invalid_request',public.read_review_detail(item.id),false; RETURN; END IF;
    SELECT max(catalogue_version) INTO latest_version FROM public.document_relationship_catalogue WHERE relationship_type=p_relationship_type;
    SELECT * INTO catalogue FROM public.document_relationship_catalogue WHERE relationship_type=p_relationship_type AND catalogue_version=p_catalogue_version;
    IF catalogue.relationship_type IS NULL OR latest_version<>p_catalogue_version
      OR NOT ('proceeding'=ANY(catalogue.allowed_source_classes)) OR NOT ('proceeding'=ANY(catalogue.allowed_target_classes))
      THEN RETURN QUERY SELECT 'invalid_relationship_type',public.read_review_detail(item.id),false; RETURN; END IF;
    IF EXISTS(SELECT 1 FROM public.document_relationships existing WHERE existing.org_id=source.org_id AND existing.lifecycle_state='active'
      AND ((existing.source_document_id=source.source_document_id AND existing.target_document_id=source.target_document_id)
        OR (existing.source_document_id=source.target_document_id AND existing.target_document_id=source.source_document_id)))
      THEN UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1 WHERE id=item.id;
      RETURN QUERY SELECT 'conflict',public.read_review_detail(item.id),false; RETURN; END IF;
    IF catalogue.acyclic AND EXISTS(
      WITH RECURSIVE reachable(document_id) AS (
        SELECT edge.target_document_id FROM public.document_relationships edge
        JOIN public.document_relationship_catalogue edge_catalogue ON edge_catalogue.relationship_type=edge.relationship_type
          AND edge_catalogue.catalogue_version=edge.catalogue_version AND edge_catalogue.acyclic
        WHERE edge.org_id=source.org_id AND edge.matter_id=source.matter_id AND edge.lifecycle_state='active'
          AND edge.source_document_id=p_target_document_id
        UNION
        SELECT edge.target_document_id FROM reachable JOIN public.document_relationships edge ON edge.source_document_id=reachable.document_id
          AND edge.org_id=source.org_id AND edge.matter_id=source.matter_id AND edge.lifecycle_state='active'
        JOIN public.document_relationship_catalogue edge_catalogue ON edge_catalogue.relationship_type=edge.relationship_type
          AND edge_catalogue.catalogue_version=edge.catalogue_version AND edge_catalogue.acyclic)
      SELECT 1 FROM reachable WHERE document_id=p_source_document_id)
      THEN RETURN QUERY SELECT 'cycle_detected',public.read_review_detail(item.id),false; RETURN; END IF;
    -- The relationship trigger normally retires candidates when any effective edge
    -- appears. This resolver owns the same atomic close, so suppress only that
    -- re-entrant reconciliation while its candidate edge is inserted.
    PERFORM set_config('casechain.relationship_suggestion_resolving',item.id::text,true);
    INSERT INTO public.document_relationships(org_id,matter_id,source_document_id,target_document_id,relationship_type,
      catalogue_version,verification,provenance,lifecycle_state,activated_by)
    VALUES(source.org_id,source.matter_id,p_source_document_id,p_target_document_id,p_relationship_type,
      p_catalogue_version,'human','candidate','active',actor.actor_user_id) RETURNING * INTO relationship;
    PERFORM set_config('casechain.relationship_suggestion_resolving','',true);
    selected_action:=CASE WHEN p_action='accept_relationship' THEN 'accept'::public.document_relationship_decision_action ELSE 'correct'::public.document_relationship_decision_action END;
    INSERT INTO public.document_relationship_decisions(org_id,matter_id,relationship_id,source_document_id,target_document_id,
      relationship_type,action,from_lifecycle,to_lifecycle,reason,actor_user_id,resulting_revision,idempotency_key)
    VALUES(source.org_id,source.matter_id,relationship.id,p_source_document_id,p_target_document_id,p_relationship_type,
      selected_action,NULL,'active',p_reason,actor.actor_user_id,relationship.revision,p_idempotency_key);
  END IF;
  INSERT INTO public.relationship_suggestion_decisions(org_id,review_item_id,expected_revision,result_revision,action,
    relationship_id,relationship_type,catalogue_version,source_document_id,target_document_id,reason,actor_user_id,
    idempotency_key,request_fingerprint,source_fingerprint)
  VALUES(source.org_id,item.id,item.revision,item.revision+1,p_action,relationship.id,p_relationship_type,p_catalogue_version,
    p_source_document_id,p_target_document_id,p_reason,actor.actor_user_id,p_idempotency_key,request_hash,source.source_fingerprint);
  UPDATE public.review_items SET status='closed',closure_reason='decision_recorded',closed_at=now(),updated_at=now(),revision=revision+1 WHERE id=item.id;
  PERFORM public.append_activity_event(source.org_id,'review.relationship_suggestion_decided',1::smallint,'user',actor.actor_user_id,'Member',
    'document',source.source_document_id,source.client_id,source.matter_id,'Document','Relationship Review decision recorded',
    jsonb_build_object('action',p_action,'revision',item.revision+1),'document',source.target_document_id,
    source.target_document_version_id,item.id,NULL,'review.relationship_suggestion.'||source.org_id||'.'||actor.actor_user_id||'.'||p_idempotency_key,now());
  RETURN QUERY SELECT 'ok',public.read_review_detail(item.id),false;
EXCEPTION WHEN lock_not_available OR deadlock_detected THEN RETURN QUERY SELECT 'busy',NULL::jsonb,false;
  WHEN unique_violation OR check_violation OR foreign_key_violation THEN RETURN QUERY SELECT 'conflict',public.read_review_detail(p_review_item_id),false;
  WHEN others THEN RETURN QUERY SELECT 'failed',NULL::jsonb,false;
END $$;

CREATE FUNCTION public.relationship_suggestion_resolution_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  PERFORM public.reconcile_exact_reference_relationship(CASE WHEN TG_OP='DELETE' THEN OLD.mention_id ELSE NEW.mention_id END);
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;

CREATE TRIGGER relationship_suggestion_resolution_changed AFTER INSERT OR UPDATE OR DELETE ON public.current_document_reference_resolutions
  FOR EACH ROW EXECUTE FUNCTION public.relationship_suggestion_resolution_changed();

CREATE FUNCTION public.relationship_suggestion_document_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE mention_id_value uuid;
BEGIN
  FOR mention_id_value IN SELECT DISTINCT mention_id FROM (
    SELECT source.mention_id FROM public.relationship_suggestion_sources source
      WHERE source.org_id=NEW.org_id AND NEW.id IN(source.source_document_id,source.target_document_id)
    UNION ALL SELECT resolution.mention_id FROM public.current_document_reference_resolutions resolution
      WHERE resolution.org_id=NEW.org_id AND NEW.id IN(resolution.source_document_id,resolution.target_document_id)
  ) mentions ORDER BY mention_id
  LOOP PERFORM public.reconcile_exact_reference_relationship(mention_id_value); END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER relationship_suggestion_document_changed AFTER UPDATE OF matter_id,current_version_id,lifecycle_revision,record_state,deleted_at,copied_from_document_id,content_availability ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.relationship_suggestion_document_changed();

CREATE FUNCTION public.relationship_suggestion_asset_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE mention_id_value uuid;
BEGIN
  FOR mention_id_value IN SELECT DISTINCT source.mention_id FROM public.relationship_suggestion_sources source
    WHERE source.org_id=NEW.org_id AND NEW.id IN(source.source_asset_id,source.target_asset_id) ORDER BY source.mention_id
  LOOP PERFORM public.reconcile_exact_reference_relationship(mention_id_value); END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER relationship_suggestion_asset_changed AFTER UPDATE OF sha256,availability,storage_deleted_at ON public.file_assets
  FOR EACH ROW EXECUTE FUNCTION public.relationship_suggestion_asset_changed();

CREATE FUNCTION public.relationship_suggestion_matter_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE mention_id_value uuid;
BEGIN
  FOR mention_id_value IN SELECT DISTINCT source.mention_id FROM public.relationship_suggestion_sources source
    WHERE source.org_id=NEW.org_id AND source.matter_id=NEW.id ORDER BY source.mention_id
  LOOP PERFORM public.reconcile_exact_reference_relationship(mention_id_value); END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER relationship_suggestion_matter_changed AFTER UPDATE OF revision,record_state,deleted_at,work_state ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.relationship_suggestion_matter_changed();

CREATE FUNCTION public.relationship_suggestion_client_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE mention_id_value uuid;
BEGIN
  FOR mention_id_value IN SELECT DISTINCT source.mention_id FROM public.relationship_suggestion_sources source
    WHERE source.org_id=NEW.org_id AND source.client_id=NEW.id ORDER BY source.mention_id
  LOOP PERFORM public.reconcile_exact_reference_relationship(mention_id_value); END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER relationship_suggestion_client_changed AFTER UPDATE OF revision,record_state,deleted_at ON public.clients
  FOR EACH ROW EXECUTE FUNCTION public.relationship_suggestion_client_changed();

CREATE FUNCTION public.relationship_suggestion_relationship_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE mention_id_value uuid; org_id_value uuid:=CASE WHEN TG_OP='DELETE' THEN OLD.org_id ELSE NEW.org_id END;
DECLARE source_id_value uuid:=CASE WHEN TG_OP='DELETE' THEN OLD.source_document_id ELSE NEW.source_document_id END;
DECLARE target_id_value uuid:=CASE WHEN TG_OP='DELETE' THEN OLD.target_document_id ELSE NEW.target_document_id END;
BEGIN
  IF nullif(current_setting('casechain.relationship_suggestion_resolving',true),'') IS NOT NULL THEN
    RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
  END IF;
  FOR mention_id_value IN SELECT DISTINCT source.mention_id FROM public.relationship_suggestion_sources source
    WHERE source.org_id=org_id_value AND ((source.source_document_id=source_id_value AND source.target_document_id=target_id_value)
      OR (source.source_document_id=target_id_value AND source.target_document_id=source_id_value)) ORDER BY source.mention_id
  LOOP PERFORM public.reconcile_exact_reference_relationship(mention_id_value); END LOOP;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER relationship_suggestion_relationship_changed AFTER INSERT OR UPDATE OF lifecycle_state OR DELETE ON public.document_relationships
  FOR EACH ROW EXECUTE FUNCTION public.relationship_suggestion_relationship_changed();

CREATE FUNCTION public.relationship_suggestion_catalogue_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE mention_id_value uuid;
BEGIN
  IF NEW.relationship_type<>'refers_to' THEN RETURN NEW; END IF;
  FOR mention_id_value IN SELECT DISTINCT mention_id FROM public.relationship_suggestion_sources ORDER BY mention_id
  LOOP PERFORM public.reconcile_exact_reference_relationship(mention_id_value); END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER relationship_suggestion_catalogue_changed AFTER INSERT ON public.document_relationship_catalogue
  FOR EACH ROW EXECUTE FUNCTION public.relationship_suggestion_catalogue_changed();

INSERT INTO public.activity_event_definitions(event_type,event_version,category,subject_types,default_visibility,metadata_contract,renderer_key)
VALUES('review.relationship_suggestion_decided',1,'review',ARRAY['document'],'matter','{"action":"code","revision":"integer"}','review.relationship_suggestion_decided.v1');

ALTER FUNCTION public.read_review_detail(uuid) RENAME TO read_review_detail_before_relationship_suggestion;
CREATE FUNCTION public.read_review_detail(p_review_item_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; item public.review_items%ROWTYPE; source public.relationship_suggestion_sources%ROWTYPE; result jsonb; current_fact boolean;
BEGIN
  SELECT * INTO actor FROM public.review_actor(); IF actor.actor_user_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO item FROM public.review_items WHERE id=p_review_item_id AND org_id=actor.org_id;
  IF item.id IS NULL THEN RETURN NULL; END IF;
  IF item.type<>'relationship_suggestion' THEN RETURN public.read_review_detail_before_relationship_suggestion(p_review_item_id); END IF;
  SELECT * INTO source FROM public.relationship_suggestion_sources WHERE review_item_id=item.id;
  IF source.review_item_id IS NULL OR NOT public.review_document_available(source.org_id,source.source_document_id)
    OR NOT public.review_document_available(source.org_id,source.target_document_id) THEN RETURN NULL; END IF;
  current_fact:=public.relationship_suggestion_current(item.id);
  SELECT to_jsonb(item)||jsonb_build_object(
    'document_title',source_document.display_title,'matter_title',matter.title,'client_name',client.name,
    'version_number',source_version.version_number,'is_current',source_document.current_version_id=item.document_version_id,
    'source_identity','Exact current same-Matter reference','record_baseline',NULL,'conflict_current',current_fact,
    'suggested_relationship_type',source.proposed_relationship_type,'suggested_catalogue_version',source.proposed_catalogue_version,
    'target_document_id',source.target_document_id,'target_document_version_id',source.target_document_version_id,
    'target_document_title',target_document.display_title,'target_lifecycle_revision',source.target_lifecycle_revision,
    'source_lifecycle_revision',source.source_lifecycle_revision,'current_matter_id',source.matter_id,
    'allowed_actions',CASE WHEN actor.can_resolve AND current_fact THEN jsonb_build_array('accept_relationship','correct_relationship','reject_relationship') ELSE '[]'::jsonb END,
    'relationship_catalogue',(SELECT coalesce(jsonb_agg(jsonb_build_object('relationship_type',catalogue.relationship_type,
      'catalogue_version',catalogue.catalogue_version,'canonical_phrase',catalogue.canonical_phrase,
      'progression_phrase',catalogue.progression_phrase,'timeline_visible',catalogue.timeline_visible)
      ORDER BY catalogue.display_priority,catalogue.relationship_type),'[]'::jsonb)
      FROM (SELECT DISTINCT ON (relationship_type) * FROM public.document_relationship_catalogue
        WHERE 'proceeding'=ANY(allowed_source_classes) AND 'proceeding'=ANY(allowed_target_classes)
        ORDER BY relationship_type,catalogue_version DESC) catalogue),
    'evidence',jsonb_build_array(jsonb_build_object('candidate_id',source.mention_id,'ordinal',1,'selectable',false,
      'page_number',source.evidence_page_number,'quotation',source.evidence_quote,'validation_state','provisional',
      'value',jsonb_build_object('source_document_id',source.source_document_id,'source_document_version_id',source.source_document_version_id,
        'source_document_title',source_document.display_title,'target_document_id',source.target_document_id,
        'target_document_version_id',source.target_document_version_id,'target_document_title',target_document.display_title,
        'identifier_kind',source.identifier_kind,'namespace',source.issuer_namespace_normalized,'normalized_value',source.normalized_value))),
    'last_decision',(SELECT jsonb_build_object('action',decision.action,'selected_candidate_id',NULL,
      'reason',decision.reason,'created_at',decision.created_at,'relationship_type',decision.relationship_type,
      'catalogue_version',decision.catalogue_version,'source_document_id',decision.source_document_id,
      'target_document_id',decision.target_document_id)
      FROM public.relationship_suggestion_decisions decision WHERE decision.review_item_id=item.id ORDER BY decision.created_at DESC LIMIT 1)
  ) INTO result FROM public.documents source_document
  JOIN public.document_versions source_version ON source_version.org_id=source_document.org_id AND source_version.id=source.source_document_version_id
  JOIN public.documents target_document ON target_document.org_id=source_document.org_id AND target_document.id=source.target_document_id
  JOIN public.matters matter ON matter.org_id=source_document.org_id AND matter.id=source.matter_id
  JOIN public.clients client ON client.org_id=matter.org_id AND client.id=source.client_id
  WHERE source_document.org_id=source.org_id AND source_document.id=source.source_document_id;
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
    OR p_type IS NULL OR p_type NOT IN ('extraction_conflict','processing_recovery','ambiguous_placement','deadline_verification','placement_conflict','multi_placement_conflict','possible_duplicate','relationship_suggestion','all')
    OR p_priority IS NULL OR p_priority NOT IN ('normal','high','urgent','all')
    OR p_search IS NULL OR char_length(p_search)>200 OR p_page IS NULL OR p_page NOT BETWEEN 1 AND 100000
    OR p_page_size IS NULL OR p_page_size NOT BETWEEN 1 AND 50 THEN RETURN; END IF;
  RETURN QUERY WITH projected AS MATERIALIZED (
    SELECT i.id,i.type,i.field_path,i.reason_code,i.impact,i.priority,i.priority_reason,i.status,i.closure_reason,
      i.revision,i.created_at,i.document_id,i.document_version_id,i.intake_id,i.source_page_number,
      CASE WHEN i.type='possible_duplicate' THEN (SELECT count(*) FROM public.possible_duplicate_sources WHERE review_item_id=i.id) ELSE NULL END source_count,
      coalesce(d.display_title,s.declared_filename) document_title,
      CASE WHEN i.type='ambiguous_placement' THEN 'Multiple eligible Matters' ELSE m.title END matter_title,
      CASE WHEN i.type='ambiguous_placement' THEN 'Global Intake' ELSE c.name END client_name
    FROM public.review_items i LEFT JOIN public.documents d ON d.id=i.document_id AND d.org_id=i.org_id
    LEFT JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id LEFT JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id
    LEFT JOIN public.intake_items intake ON intake.id=i.intake_id AND intake.org_id=i.org_id
    LEFT JOIN public.upload_sessions s ON s.id=intake.upload_session_id AND s.org_id=intake.org_id
    WHERE i.org_id=actor.org_id
      AND ((i.type='ambiguous_placement' AND intake.id IS NOT NULL)
        OR (i.type='possible_duplicate' AND EXISTS(SELECT 1 FROM public.possible_duplicate_sources source WHERE source.review_item_id=i.id
          GROUP BY source.review_item_id HAVING count(*) BETWEEN 2 AND 8 AND bool_and(public.review_document_available(source.org_id,source.document_id))))
        OR (i.type='relationship_suggestion' AND EXISTS(SELECT 1 FROM public.relationship_suggestion_sources source WHERE source.review_item_id=i.id
          AND public.review_document_available(source.org_id,source.source_document_id) AND public.review_document_available(source.org_id,source.target_document_id)))
        OR (i.type NOT IN ('ambiguous_placement','possible_duplicate','relationship_suggestion') AND public.review_document_available(i.org_id,i.document_id)))
      AND (i.status='closed' OR i.type='ambiguous_placement' OR d.current_version_id=i.document_version_id)
  ), filtered AS MATERIALIZED (SELECT * FROM projected WHERE (p_status='all' OR status::text=p_status)
    AND (p_type='all' OR type::text=p_type) AND (p_priority='all' OR priority::text=p_priority)
    AND (p_search='' OR strpos(lower(concat_ws(' ',field_path,reason_code,document_title,matter_title,client_name)),lower(p_search))>0)),
  page_rows AS (SELECT * FROM filtered ORDER BY priority DESC,created_at,id LIMIT p_page_size OFFSET (p_page-1)*p_page_size)
  SELECT coalesce((SELECT jsonb_agg(to_jsonb(page_rows) ORDER BY priority DESC,created_at,id) FROM page_rows),'[]'::jsonb),
    (SELECT count(*) FROM filtered),actor.can_resolve;
END $$;

REVOKE ALL ON FUNCTION public.relationship_suggestion_current(uuid),public.reconcile_exact_reference_relationship(uuid),
  public.relationship_suggestion_resolution_changed(),public.relationship_suggestion_document_changed(),public.relationship_suggestion_asset_changed(),
  public.relationship_suggestion_matter_changed(),public.relationship_suggestion_client_changed(),public.relationship_suggestion_relationship_changed(),
  public.relationship_suggestion_catalogue_changed(),public.read_review_detail_before_relationship_suggestion(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.read_review_queue(text,text,text,text,integer,integer),public.read_review_detail(uuid),
  public.resolve_relationship_suggestion(uuid,bigint,text,public.document_relationship_type,integer,uuid,uuid,text,uuid)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.read_review_queue(text,text,text,text,integer,integer),public.read_review_detail(uuid),
  public.resolve_relationship_suggestion(uuid,bigint,text,public.document_relationship_type,integer,uuid,uuid,text,uuid)
  TO authenticated;
COMMIT;
