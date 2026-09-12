-- D09-T05: governed document self identifiers and exact reference resolution.
-- Reference resolution is intentionally separate from Matter identity, placement,
-- procedural relationships, effective metadata, Review, and notifications.
BEGIN;

CREATE TYPE public.document_identifier_lifecycle AS ENUM ('active','revoked');
CREATE TYPE public.document_identifier_decision_action AS ENUM ('activate','correct','revoke');
CREATE TYPE public.document_reference_resolution_outcome AS ENUM ('unique_exact','ambiguous','conflicting','unresolved');

CREATE TABLE public.document_self_identifiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  document_id uuid,
  document_version_id uuid,
  document_field_candidate_id uuid,
  source_field_candidate_id uuid,
  source_analysis_run_id uuid,
  document_version_analysis_binding_id uuid,
  semantic_candidate_key text NOT NULL,
  identifier_kind public.matter_identifier_kind NOT NULL,
  issuer_namespace_normalized text NOT NULL,
  normalized_value text NOT NULL,
  normalized_components jsonb NOT NULL CHECK (jsonb_typeof(normalized_components)='object'),
  raw_value text NOT NULL,
  display_value text NOT NULL,
  catalogue_version text NOT NULL,
  normalizer_version text NOT NULL,
  evidence_page_number integer,
  evidence_quote text,
  evidence_regions jsonb,
  verified_source_anchor jsonb,
  matter_identifier_id uuid,
  verified_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  verified_at timestamptz NOT NULL DEFAULT now(),
  lifecycle_state public.document_identifier_lifecycle NOT NULL DEFAULT 'active',
  revision bigint NOT NULL DEFAULT 1 CHECK (revision>=1),
  predecessor_identifier_id uuid,
  activated_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  revoked_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  revocation_reason text,
  evidence_purged_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_self_identifiers_org_id_id_unique UNIQUE(org_id,id),
  CONSTRAINT document_self_identifiers_document_fkey FOREIGN KEY(org_id,document_id) REFERENCES public.documents(org_id,id) ON DELETE SET NULL (document_id),
  CONSTRAINT document_self_identifiers_version_fkey FOREIGN KEY(org_id,document_id,document_version_id) REFERENCES public.document_versions(org_id,document_id,id) ON DELETE SET NULL (document_id,document_version_id),
  CONSTRAINT document_self_identifiers_candidate_fkey FOREIGN KEY(org_id,document_field_candidate_id) REFERENCES public.document_field_candidates(org_id,id) ON DELETE SET NULL (document_field_candidate_id),
  CONSTRAINT document_self_identifiers_source_candidate_fkey FOREIGN KEY(org_id,source_field_candidate_id) REFERENCES public.source_field_candidates(org_id,id) ON DELETE SET NULL (source_field_candidate_id),
  CONSTRAINT document_self_identifiers_source_run_fkey FOREIGN KEY(org_id,source_analysis_run_id) REFERENCES public.source_analysis_runs(org_id,id) ON DELETE SET NULL (source_analysis_run_id),
  CONSTRAINT document_self_identifiers_binding_fkey FOREIGN KEY(org_id,document_version_analysis_binding_id) REFERENCES public.document_version_analysis_bindings(org_id,id) ON DELETE SET NULL (document_version_analysis_binding_id),
  CONSTRAINT document_self_identifiers_matter_identifier_fkey FOREIGN KEY(org_id,matter_identifier_id) REFERENCES public.matter_identifiers(org_id,id) ON DELETE SET NULL (matter_identifier_id),
  CONSTRAINT document_self_identifiers_predecessor_fkey FOREIGN KEY(org_id,predecessor_identifier_id) REFERENCES public.document_self_identifiers(org_id,id) ON DELETE RESTRICT,
  CONSTRAINT document_self_identifiers_snapshot_safe CHECK (
    semantic_candidate_key ~ '^[a-z][a-z0-9_.:-]{0,199}$'
    AND char_length(issuer_namespace_normalized) BETWEEN 2 AND 160
    AND char_length(normalized_value) BETWEEN 1 AND 300
    AND char_length(raw_value) BETWEEN 1 AND 300
    AND char_length(display_value) BETWEEN 1 AND 300
    AND catalogue_version ~ '^[a-z0-9][a-z0-9_.-]{0,127}$'
    AND normalizer_version ~ '^[a-z0-9][a-z0-9_.-]{0,127}$'
    AND raw_value !~ '[[:cntrl:]]' AND display_value !~ '[[:cntrl:]]'
  ),
  CONSTRAINT document_self_identifiers_evidence_shape CHECK (
    (evidence_purged_at IS NULL AND document_id IS NOT NULL AND document_version_id IS NOT NULL
      AND document_field_candidate_id IS NOT NULL AND source_field_candidate_id IS NOT NULL
      AND source_analysis_run_id IS NOT NULL AND document_version_analysis_binding_id IS NOT NULL
      AND evidence_page_number IS NOT NULL AND evidence_page_number>0
      AND evidence_quote IS NOT NULL AND char_length(evidence_quote) BETWEEN 1 AND 1000
      AND public.source_field_candidate_regions_are_valid(evidence_regions)
      AND verified_source_anchor IS NOT NULL)
    OR (evidence_purged_at IS NOT NULL AND document_id IS NULL AND document_version_id IS NULL
      AND document_field_candidate_id IS NULL AND source_field_candidate_id IS NULL
      AND source_analysis_run_id IS NULL AND document_version_analysis_binding_id IS NULL
      AND evidence_page_number IS NULL AND evidence_quote IS NULL
      AND evidence_regions IS NULL AND verified_source_anchor IS NULL)
  ),
  CONSTRAINT document_self_identifiers_lifecycle_shape CHECK (
    (lifecycle_state='active' AND revoked_at IS NULL AND revoked_by IS NULL AND revocation_reason IS NULL)
    OR (lifecycle_state='revoked' AND revoked_at IS NOT NULL AND revoked_by IS NOT NULL
      AND revocation_reason IS NOT NULL AND char_length(revocation_reason) BETWEEN 1 AND 500
      AND revocation_reason !~ '[[:cntrl:]]')
  )
);

-- Deliberately not globally unique: two documents may claim the same exact key,
-- which is represented as an ambiguous resolution. One logical document cannot
-- carry a duplicate active tuple.
CREATE UNIQUE INDEX document_self_identifiers_one_active_document_key
  ON public.document_self_identifiers(org_id,document_id,issuer_namespace_normalized,identifier_kind,normalized_value)
  WHERE lifecycle_state='active' AND document_id IS NOT NULL;
CREATE INDEX document_self_identifiers_exact_active_idx
  ON public.document_self_identifiers(org_id,issuer_namespace_normalized,identifier_kind,normalized_value,document_id)
  WHERE lifecycle_state='active' AND document_id IS NOT NULL AND evidence_purged_at IS NULL;
CREATE INDEX document_self_identifiers_document_active_idx
  ON public.document_self_identifiers(org_id,document_id,issuer_namespace_normalized,identifier_kind,normalized_value)
  WHERE lifecycle_state='active' AND document_id IS NOT NULL AND evidence_purged_at IS NULL;

CREATE TABLE public.document_identifier_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  decision_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  document_id uuid,
  identifier_id uuid NOT NULL,
  previous_identifier_id uuid,
  action public.document_identifier_decision_action NOT NULL,
  reason text,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  resulting_identifier_revision bigint NOT NULL CHECK(resulting_identifier_revision>=1),
  resulting_document_revision bigint NOT NULL CHECK(resulting_document_revision>=1),
  idempotency_key uuid NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_identifier_decisions_identifier_fkey FOREIGN KEY(org_id,identifier_id) REFERENCES public.document_self_identifiers(org_id,id) ON DELETE RESTRICT,
  CONSTRAINT document_identifier_decisions_previous_fkey FOREIGN KEY(org_id,previous_identifier_id) REFERENCES public.document_self_identifiers(org_id,id) ON DELETE RESTRICT
);
CREATE INDEX document_identifier_decisions_history_idx ON public.document_identifier_decisions(org_id,document_id,decision_sequence);

CREATE TABLE public.document_identifier_command_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL UNIQUE,
  command text NOT NULL CHECK(command IN ('activate','correct','revoke')),
  request_fingerprint text NOT NULL CHECK(request_fingerprint ~ '^[0-9a-f]{64}$'),
  identifier_id uuid NOT NULL,
  previous_identifier_id uuid,
  result_identifier_revision bigint NOT NULL,
  result_document_revision bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_identifier_receipts_identifier_fkey FOREIGN KEY(org_id,identifier_id) REFERENCES public.document_self_identifiers(org_id,id) ON DELETE RESTRICT,
  CONSTRAINT document_identifier_receipts_previous_fkey FOREIGN KEY(org_id,previous_identifier_id) REFERENCES public.document_self_identifiers(org_id,id) ON DELETE RESTRICT
);

CREATE TABLE public.document_reference_mentions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  source_document_id uuid,
  source_document_version_id uuid,
  document_field_candidate_id uuid,
  source_field_candidate_id uuid,
  source_analysis_run_id uuid,
  document_version_analysis_binding_id uuid,
  semantic_candidate_key text NOT NULL,
  identifier_kind public.matter_identifier_kind NOT NULL,
  issuer_namespace_normalized text NOT NULL,
  normalized_value text NOT NULL,
  normalized_components jsonb NOT NULL CHECK(jsonb_typeof(normalized_components)='object'),
  raw_value text,
  display_value text,
  catalogue_version text NOT NULL,
  normalizer_version text NOT NULL,
  evidence_page_number integer,
  evidence_quote text,
  evidence_regions jsonb,
  verified_source_anchor jsonb,
  evidence_purged_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_reference_mentions_org_id_id_unique UNIQUE(org_id,id),
  CONSTRAINT document_reference_mentions_candidate_unique UNIQUE(document_field_candidate_id),
  CONSTRAINT document_reference_mentions_document_fkey FOREIGN KEY(org_id,source_document_id) REFERENCES public.documents(org_id,id) ON DELETE SET NULL (source_document_id),
  CONSTRAINT document_reference_mentions_version_fkey FOREIGN KEY(org_id,source_document_id,source_document_version_id) REFERENCES public.document_versions(org_id,document_id,id) ON DELETE SET NULL (source_document_id,source_document_version_id),
  CONSTRAINT document_reference_mentions_candidate_fkey FOREIGN KEY(org_id,document_field_candidate_id) REFERENCES public.document_field_candidates(org_id,id) ON DELETE SET NULL (document_field_candidate_id),
  CONSTRAINT document_reference_mentions_source_candidate_fkey FOREIGN KEY(org_id,source_field_candidate_id) REFERENCES public.source_field_candidates(org_id,id) ON DELETE SET NULL (source_field_candidate_id),
  CONSTRAINT document_reference_mentions_source_run_fkey FOREIGN KEY(org_id,source_analysis_run_id) REFERENCES public.source_analysis_runs(org_id,id) ON DELETE SET NULL (source_analysis_run_id),
  CONSTRAINT document_reference_mentions_binding_fkey FOREIGN KEY(org_id,document_version_analysis_binding_id) REFERENCES public.document_version_analysis_bindings(org_id,id) ON DELETE SET NULL (document_version_analysis_binding_id),
  CONSTRAINT document_reference_mentions_key_safe CHECK(char_length(issuer_namespace_normalized) BETWEEN 2 AND 160 AND char_length(normalized_value) BETWEEN 1 AND 300),
  CONSTRAINT document_reference_mentions_evidence_shape CHECK(
    (evidence_purged_at IS NULL AND source_document_id IS NOT NULL AND source_document_version_id IS NOT NULL
      AND document_field_candidate_id IS NOT NULL AND source_field_candidate_id IS NOT NULL
      AND source_analysis_run_id IS NOT NULL AND document_version_analysis_binding_id IS NOT NULL
      AND evidence_page_number IS NOT NULL AND evidence_quote IS NOT NULL
      AND public.source_field_candidate_regions_are_valid(evidence_regions) AND verified_source_anchor IS NOT NULL)
    OR (evidence_purged_at IS NOT NULL AND source_document_id IS NULL AND source_document_version_id IS NULL
      AND document_field_candidate_id IS NULL AND source_field_candidate_id IS NULL
      AND source_analysis_run_id IS NULL AND document_version_analysis_binding_id IS NULL
      AND evidence_page_number IS NULL AND evidence_quote IS NULL AND evidence_regions IS NULL AND verified_source_anchor IS NULL)
  )
);
CREATE INDEX document_reference_mentions_exact_idx
  ON public.document_reference_mentions(org_id,issuer_namespace_normalized,identifier_kind,normalized_value,source_document_id,source_document_version_id);
CREATE INDEX document_reference_mentions_source_current_idx
  ON public.document_reference_mentions(org_id,source_document_id,source_document_version_id,issuer_namespace_normalized,identifier_kind,normalized_value)
  WHERE source_document_id IS NOT NULL AND evidence_purged_at IS NULL;

CREATE TABLE public.document_reference_resolution_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  issuer_namespace_normalized text NOT NULL,
  identifier_kind public.matter_identifier_kind NOT NULL,
  normalized_value text NOT NULL,
  trigger_kind text NOT NULL CHECK(trigger_kind IN ('mention_materialized','identifier_activated','identifier_corrected','identifier_revoked','document_availability_changed','explicit_retry')),
  trigger_key text NOT NULL CHECK(trigger_key ~ '^[A-Za-z0-9._:-]{1,200}$'),
  rule_version text NOT NULL DEFAULT 'document-reference-exact-v1',
  state text NOT NULL DEFAULT 'completed' CHECK(state='completed'),
  evaluated_count integer NOT NULL DEFAULT 0 CHECK(evaluated_count BETWEEN 0 AND 10000),
  unique_count integer NOT NULL DEFAULT 0 CHECK(unique_count BETWEEN 0 AND evaluated_count),
  ambiguous_count integer NOT NULL DEFAULT 0 CHECK(ambiguous_count BETWEEN 0 AND evaluated_count),
  conflicting_count integer NOT NULL DEFAULT 0 CHECK(conflicting_count BETWEEN 0 AND evaluated_count),
  unresolved_count integer NOT NULL DEFAULT 0 CHECK(unresolved_count BETWEEN 0 AND evaluated_count),
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_reference_resolution_runs_org_id_id_unique UNIQUE(org_id,id),
  CONSTRAINT document_reference_resolution_runs_replay UNIQUE(org_id,trigger_key,issuer_namespace_normalized,identifier_kind,normalized_value),
  CONSTRAINT document_reference_resolution_runs_counts CHECK(evaluated_count=unique_count+ambiguous_count+conflicting_count+unresolved_count)
);

CREATE TABLE public.document_reference_resolution_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  run_id uuid NOT NULL REFERENCES public.document_reference_resolution_runs(id) ON DELETE RESTRICT,
  mention_id uuid NOT NULL,
  outcome public.document_reference_resolution_outcome NOT NULL,
  target_document_id uuid,
  target_identifier_id uuid,
  target_purged_at timestamptz,
  reason_code text NOT NULL CHECK(reason_code ~ '^[a-z][a-z0-9_]{0,63}$'),
  rule_version text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_reference_resolution_results_org_id_id_unique UNIQUE(org_id,id),
  CONSTRAINT document_reference_resolution_results_run_mention_unique UNIQUE(run_id,mention_id),
  CONSTRAINT document_reference_resolution_results_run_fkey FOREIGN KEY(org_id,run_id) REFERENCES public.document_reference_resolution_runs(org_id,id) ON DELETE RESTRICT,
  CONSTRAINT document_reference_resolution_results_mention_fkey FOREIGN KEY(org_id,mention_id) REFERENCES public.document_reference_mentions(org_id,id) ON DELETE RESTRICT,
  CONSTRAINT document_reference_resolution_results_target_document_fkey FOREIGN KEY(org_id,target_document_id) REFERENCES public.documents(org_id,id) ON DELETE SET NULL (target_document_id),
  CONSTRAINT document_reference_resolution_results_target_identifier_fkey FOREIGN KEY(org_id,target_identifier_id) REFERENCES public.document_self_identifiers(org_id,id) ON DELETE SET NULL (target_identifier_id),
  CONSTRAINT document_reference_resolution_results_target_shape CHECK(
    (outcome='unique_exact' AND target_document_id IS NOT NULL AND target_identifier_id IS NOT NULL AND target_purged_at IS NULL)
    OR (outcome='unique_exact' AND target_document_id IS NULL AND target_identifier_id IS NULL AND target_purged_at IS NOT NULL)
    OR (outcome<>'unique_exact' AND target_document_id IS NULL AND target_identifier_id IS NULL AND target_purged_at IS NULL)
  )
);

CREATE TABLE public.current_document_reference_resolutions (
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  mention_id uuid NOT NULL,
  run_id uuid NOT NULL,
  result_id uuid NOT NULL,
  source_document_id uuid,
  outcome public.document_reference_resolution_outcome NOT NULL,
  target_document_id uuid,
  target_identifier_id uuid,
  target_purged_at timestamptz,
  resolved_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(org_id,mention_id),
  CONSTRAINT current_document_reference_resolutions_run_fkey FOREIGN KEY(org_id,run_id) REFERENCES public.document_reference_resolution_runs(org_id,id) ON DELETE RESTRICT,
  CONSTRAINT current_document_reference_resolutions_result_fkey FOREIGN KEY(org_id,result_id) REFERENCES public.document_reference_resolution_results(org_id,id) ON DELETE RESTRICT,
  CONSTRAINT current_document_reference_resolutions_mention_fkey FOREIGN KEY(org_id,mention_id) REFERENCES public.document_reference_mentions(org_id,id) ON DELETE RESTRICT,
  CONSTRAINT current_document_reference_resolutions_source_fkey FOREIGN KEY(org_id,source_document_id) REFERENCES public.documents(org_id,id) ON DELETE SET NULL (source_document_id),
  CONSTRAINT current_document_reference_resolutions_target_fkey FOREIGN KEY(org_id,target_document_id) REFERENCES public.documents(org_id,id) ON DELETE SET NULL (target_document_id),
  CONSTRAINT current_document_reference_resolutions_target_identifier_fkey FOREIGN KEY(org_id,target_identifier_id) REFERENCES public.document_self_identifiers(org_id,id) ON DELETE SET NULL (target_identifier_id),
  CONSTRAINT current_document_reference_resolutions_target_shape CHECK(
    (outcome='unique_exact' AND target_document_id IS NOT NULL AND target_identifier_id IS NOT NULL AND target_purged_at IS NULL)
    OR (outcome='unique_exact' AND target_document_id IS NULL AND target_identifier_id IS NULL AND target_purged_at IS NOT NULL)
    OR (outcome<>'unique_exact' AND target_document_id IS NULL AND target_identifier_id IS NULL AND target_purged_at IS NULL)
  )
);

CREATE OR REPLACE FUNCTION public.document_reference_private_rows_immutable() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
  IF current_setting('casechain.document_reference_internal',true)='on' THEN
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'Document reference history is append-only';
END $$;
CREATE TRIGGER document_identifier_decisions_immutable BEFORE UPDATE OR DELETE ON public.document_identifier_decisions FOR EACH ROW EXECUTE FUNCTION public.document_reference_private_rows_immutable();
CREATE TRIGGER document_identifier_receipts_immutable BEFORE UPDATE OR DELETE ON public.document_identifier_command_receipts FOR EACH ROW EXECUTE FUNCTION public.document_reference_private_rows_immutable();
CREATE TRIGGER document_reference_mentions_immutable BEFORE UPDATE OR DELETE ON public.document_reference_mentions FOR EACH ROW EXECUTE FUNCTION public.document_reference_private_rows_immutable();
CREATE TRIGGER document_reference_runs_immutable BEFORE UPDATE OR DELETE ON public.document_reference_resolution_runs FOR EACH ROW EXECUTE FUNCTION public.document_reference_private_rows_immutable();
CREATE TRIGGER document_reference_results_immutable BEFORE UPDATE OR DELETE ON public.document_reference_resolution_results FOR EACH ROW EXECUTE FUNCTION public.document_reference_private_rows_immutable();

CREATE OR REPLACE FUNCTION public.document_identifier_decision_enforce() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE identifier public.document_self_identifiers%ROWTYPE; predecessor public.document_self_identifiers%ROWTYPE;
BEGIN
  SELECT * INTO identifier FROM public.document_self_identifiers WHERE org_id=NEW.org_id AND id=NEW.identifier_id;
  IF identifier.id IS NULL OR identifier.document_id IS DISTINCT FROM NEW.document_id
    OR identifier.revision<>NEW.resulting_identifier_revision
    OR NOT EXISTS(SELECT 1 FROM public.documents d WHERE d.org_id=NEW.org_id AND d.id=NEW.document_id AND d.lifecycle_revision=NEW.resulting_document_revision)
    OR (NEW.action='activate' AND (NEW.previous_identifier_id IS NOT NULL OR identifier.lifecycle_state<>'active' OR identifier.predecessor_identifier_id IS NOT NULL))
    OR (NEW.action='revoke' AND (NEW.previous_identifier_id IS NOT NULL OR identifier.lifecycle_state<>'revoked')) THEN
    RAISE EXCEPTION 'Document identifier decision lineage is invalid';
  END IF;
  IF NEW.action='correct' THEN
    SELECT * INTO predecessor FROM public.document_self_identifiers WHERE org_id=NEW.org_id AND id=NEW.previous_identifier_id;
    IF predecessor.id IS NULL OR predecessor.document_id IS DISTINCT FROM NEW.document_id OR predecessor.lifecycle_state<>'revoked'
      OR identifier.lifecycle_state<>'active' OR identifier.predecessor_identifier_id IS DISTINCT FROM predecessor.id THEN
      RAISE EXCEPTION 'Document identifier correction lineage is invalid';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER document_identifier_decisions_enforce BEFORE INSERT ON public.document_identifier_decisions FOR EACH ROW EXECUTE FUNCTION public.document_identifier_decision_enforce();

CREATE OR REPLACE FUNCTION public.document_self_identifier_enforce() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE candidate record; matter_identifier public.matter_identifiers%ROWTYPE;
BEGIN
  IF TG_OP='UPDATE' THEN
    IF current_setting('casechain.document_identifier_write',true)<>'on' THEN RAISE EXCEPTION 'Document identifier updates require a governed command'; END IF;
    RETURN NEW;
  END IF;
  SELECT document_candidate.*,source_candidate.source_analysis_run_id,source_candidate.verified_source_anchor,
    binding.source_analysis_run_id AS binding_source_run_id
  INTO candidate
  FROM public.document_field_candidates document_candidate
  JOIN public.source_field_candidates source_candidate ON source_candidate.org_id=document_candidate.org_id AND source_candidate.id=document_candidate.source_field_candidate_id
  JOIN public.document_version_analysis_bindings binding ON binding.org_id=document_candidate.org_id AND binding.id=document_candidate.document_version_analysis_binding_id
  JOIN public.documents document_row ON document_row.org_id=document_candidate.org_id AND document_row.id=document_candidate.document_id
  JOIN public.document_versions version ON version.org_id=document_candidate.org_id AND version.id=document_candidate.document_version_id
  WHERE document_candidate.org_id=NEW.org_id AND document_candidate.id=NEW.document_field_candidate_id
    AND document_candidate.document_id=NEW.document_id AND document_candidate.document_version_id=NEW.document_version_id
    AND document_candidate.field_path='document.official_reference.self_identifier'
    AND document_candidate.value_type='structured' AND document_candidate.validation_state<>'invalid'
    AND document_candidate.normalized_value->>'role'='self_identifier'
    AND document_candidate.normalized_value->>'completeness'='complete'
    AND document_candidate.normalized_value->>'match_eligible'='true'
    AND document_candidate.normalized_value->>'kind'<>'other_official_reference'
    AND source_candidate.id=NEW.source_field_candidate_id AND source_candidate.verified_source_anchor IS NOT NULL
    AND binding.id=NEW.document_version_analysis_binding_id AND binding.source_analysis_run_id=source_candidate.source_analysis_run_id
    AND document_row.current_version_id=document_candidate.document_version_id
    AND document_row.record_state='active' AND document_row.deleted_at IS NULL
    AND version.state='current' AND version.validation_state='valid';
  IF candidate.id IS NULL OR NEW.revision<>1 OR NEW.lifecycle_state<>'active'
    OR NEW.source_analysis_run_id IS DISTINCT FROM candidate.source_analysis_run_id
    OR NEW.verified_source_anchor IS DISTINCT FROM candidate.verified_source_anchor
    OR NEW.semantic_candidate_key IS DISTINCT FROM candidate.semantic_candidate_key
    OR NEW.identifier_kind::text IS DISTINCT FROM candidate.normalized_value->>'kind'
    OR NEW.issuer_namespace_normalized IS DISTINCT FROM candidate.normalized_value->>'namespace_normalized'
    OR NEW.normalized_value IS DISTINCT FROM candidate.normalized_value->>'normalized_value'
    OR NEW.normalized_components IS DISTINCT FROM candidate.normalized_value->'components'
    OR NEW.raw_value IS DISTINCT FROM candidate.normalized_value->>'raw'
    OR NEW.display_value IS DISTINCT FROM candidate.normalized_value->>'display'
    OR NEW.catalogue_version IS DISTINCT FROM candidate.normalized_value->>'catalogue_version'
    OR NEW.normalizer_version IS DISTINCT FROM candidate.normalized_value->>'normalizer_version'
    OR NEW.evidence_page_number IS DISTINCT FROM candidate.page_number
    OR NEW.evidence_quote IS DISTINCT FROM candidate.quotation
    OR NEW.evidence_regions IS DISTINCT FROM candidate.evidence_regions THEN
    RAISE EXCEPTION 'Document identifier must preserve one eligible current source candidate';
  END IF;
  IF NEW.matter_identifier_id IS NOT NULL THEN
    SELECT identifier.* INTO matter_identifier FROM public.matter_identifiers identifier
    JOIN public.documents document_row ON document_row.org_id=identifier.org_id AND document_row.matter_id=identifier.matter_id
    WHERE identifier.org_id=NEW.org_id AND identifier.id=NEW.matter_identifier_id AND document_row.id=NEW.document_id
      AND identifier.lifecycle_state='active' AND identifier.identifier_role='self_identifier'
      AND identifier.verification_method='human_source' AND identifier.identity_eligible
      AND identifier.issuer_namespace_normalized=NEW.issuer_namespace_normalized
      AND identifier.identifier_kind=NEW.identifier_kind AND identifier.normalized_value=NEW.normalized_value;
    IF matter_identifier.id IS NULL THEN RAISE EXCEPTION 'Matter identifier binding is not an exact active same-Matter key'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER document_self_identifiers_enforce BEFORE INSERT OR UPDATE ON public.document_self_identifiers FOR EACH ROW EXECUTE FUNCTION public.document_self_identifier_enforce();

CREATE OR REPLACE FUNCTION public.reevaluate_document_reference_exact_key(
  p_org_id uuid,p_namespace text,p_kind public.matter_identifier_kind,p_value text,
  p_trigger_kind text,p_trigger_key text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE run_id uuid; mention public.document_reference_mentions%ROWTYPE; outcome public.document_reference_resolution_outcome;
DECLARE target_count integer; target_document uuid; target_identifier uuid; result_id uuid;
DECLARE v_unique_count integer:=0; v_ambiguous_count integer:=0; v_conflicting_count integer:=0; v_unresolved_count integer:=0; v_evaluated integer:=0;
DECLARE eligible_mentions integer;
BEGIN
  IF p_org_id IS NULL OR p_namespace IS NULL OR p_kind IS NULL OR p_value IS NULL
    OR p_trigger_kind NOT IN ('mention_materialized','identifier_activated','identifier_corrected','identifier_revoked','document_availability_changed','explicit_retry')
    OR p_trigger_key !~ '^[A-Za-z0-9._:-]{1,200}$' THEN RAISE EXCEPTION 'Invalid exact-key reevaluation request'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_org_id::text||':'||p_namespace||':'||p_kind::text||':'||p_value,151));
  PERFORM set_config('casechain.document_reference_internal','on',true);
  SELECT id INTO run_id FROM public.document_reference_resolution_runs
    WHERE org_id=p_org_id AND trigger_key=p_trigger_key AND issuer_namespace_normalized=p_namespace AND identifier_kind=p_kind AND normalized_value=p_value;
  IF run_id IS NOT NULL THEN RETURN run_id; END IF;
  SELECT count(*) INTO eligible_mentions
  FROM public.document_reference_mentions m JOIN public.documents d ON d.org_id=m.org_id AND d.id=m.source_document_id
  WHERE m.org_id=p_org_id AND m.issuer_namespace_normalized=p_namespace AND m.identifier_kind=p_kind AND m.normalized_value=p_value
    AND m.source_document_version_id=d.current_version_id;
  IF eligible_mentions>10000 THEN RAISE EXCEPTION 'Exact-key reevaluation exceeds bounded capacity'; END IF;
  INSERT INTO public.document_reference_resolution_runs(org_id,issuer_namespace_normalized,identifier_kind,normalized_value,trigger_kind,trigger_key)
    VALUES(p_org_id,p_namespace,p_kind,p_value,p_trigger_kind,p_trigger_key) RETURNING id INTO run_id;
  FOR mention IN
    SELECT m.* FROM public.document_reference_mentions m
    JOIN public.documents d ON d.org_id=m.org_id AND d.id=m.source_document_id
    WHERE m.org_id=p_org_id AND m.issuer_namespace_normalized=p_namespace AND m.identifier_kind=p_kind AND m.normalized_value=p_value
      AND m.source_document_version_id=d.current_version_id
    ORDER BY m.id
  LOOP
    v_evaluated:=v_evaluated+1; target_document:=NULL; target_identifier:=NULL;
    IF mention.source_document_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.documents d JOIN public.matters m ON m.org_id=d.org_id AND m.id=d.matter_id JOIN public.clients c ON c.org_id=m.org_id AND c.id=m.client_id WHERE d.org_id=p_org_id AND d.id=mention.source_document_id AND d.record_state='active' AND d.deleted_at IS NULL AND d.current_version_id=mention.source_document_version_id AND m.record_state='active' AND m.deleted_at IS NULL AND c.record_state='active' AND c.deleted_at IS NULL) THEN
      outcome:='unresolved'; v_unresolved_count:=v_unresolved_count+1;
    ELSIF EXISTS(SELECT 1 FROM public.document_self_identifiers i JOIN public.documents d ON d.org_id=i.org_id AND d.id=i.document_id JOIN public.matters m ON m.org_id=d.org_id AND m.id=d.matter_id JOIN public.clients c ON c.org_id=m.org_id AND c.id=m.client_id WHERE i.org_id=p_org_id AND i.issuer_namespace_normalized=p_namespace AND i.identifier_kind=p_kind AND i.normalized_value=p_value AND i.lifecycle_state='active' AND i.document_id=mention.source_document_id AND i.document_version_id=d.current_version_id AND d.record_state='active' AND d.deleted_at IS NULL AND m.record_state='active' AND m.deleted_at IS NULL AND c.record_state='active' AND c.deleted_at IS NULL) THEN
      outcome:='conflicting'; v_conflicting_count:=v_conflicting_count+1;
    ELSE
      SELECT count(DISTINCT i.document_id)
      INTO target_count
      FROM public.document_self_identifiers i JOIN public.documents d ON d.org_id=i.org_id AND d.id=i.document_id
      JOIN public.matters m ON m.org_id=d.org_id AND m.id=d.matter_id JOIN public.clients c ON c.org_id=m.org_id AND c.id=m.client_id
      JOIN public.document_versions v ON v.org_id=i.org_id AND v.id=i.document_version_id
      WHERE i.org_id=p_org_id AND i.issuer_namespace_normalized=p_namespace AND i.identifier_kind=p_kind AND i.normalized_value=p_value
        AND i.lifecycle_state='active' AND i.evidence_purged_at IS NULL AND i.document_id<>mention.source_document_id
        AND d.record_state='active' AND d.deleted_at IS NULL AND d.current_version_id=i.document_version_id
        AND v.state='current' AND v.validation_state='valid' AND m.record_state='active' AND m.deleted_at IS NULL AND c.record_state='active' AND c.deleted_at IS NULL;
      IF target_count=1 THEN
        SELECT i.document_id,i.id INTO target_document,target_identifier
        FROM public.document_self_identifiers i JOIN public.documents d ON d.org_id=i.org_id AND d.id=i.document_id
        JOIN public.matters m ON m.org_id=d.org_id AND m.id=d.matter_id JOIN public.clients c ON c.org_id=m.org_id AND c.id=m.client_id
        JOIN public.document_versions v ON v.org_id=i.org_id AND v.id=i.document_version_id
        WHERE i.org_id=p_org_id AND i.issuer_namespace_normalized=p_namespace AND i.identifier_kind=p_kind AND i.normalized_value=p_value
          AND i.lifecycle_state='active' AND i.evidence_purged_at IS NULL AND i.document_id<>mention.source_document_id
          AND d.record_state='active' AND d.deleted_at IS NULL AND d.current_version_id=i.document_version_id
          AND v.state='current' AND v.validation_state='valid' AND m.record_state='active' AND m.deleted_at IS NULL AND c.record_state='active' AND c.deleted_at IS NULL
        ORDER BY i.document_id,i.id LIMIT 1;
      END IF;
      IF target_count=0 THEN outcome:='unresolved'; target_document:=NULL; target_identifier:=NULL; v_unresolved_count:=v_unresolved_count+1;
      ELSIF target_count>1 THEN outcome:='ambiguous'; target_document:=NULL; target_identifier:=NULL; v_ambiguous_count:=v_ambiguous_count+1;
      ELSIF EXISTS(
        SELECT 1 FROM public.document_self_identifiers target_identifier_row
        JOIN public.matter_identifiers target_matter_identifier ON target_matter_identifier.id=target_identifier_row.matter_identifier_id AND target_matter_identifier.org_id=target_identifier_row.org_id
        JOIN public.documents source_document ON source_document.org_id=p_org_id AND source_document.id=mention.source_document_id
        JOIN public.matter_identifiers source_matter_identifier ON source_matter_identifier.org_id=p_org_id AND source_matter_identifier.matter_id=source_document.matter_id
          AND source_matter_identifier.lifecycle_state='active' AND source_matter_identifier.identifier_role='self_identifier'
          AND source_matter_identifier.verification_method='human_source' AND source_matter_identifier.identity_eligible
          AND source_matter_identifier.issuer_namespace_normalized=p_namespace AND source_matter_identifier.identifier_kind=p_kind AND source_matter_identifier.normalized_value=p_value
        WHERE target_identifier_row.id=target_identifier AND target_matter_identifier.matter_id<>source_matter_identifier.matter_id
      ) THEN outcome:='conflicting'; target_document:=NULL; target_identifier:=NULL; v_conflicting_count:=v_conflicting_count+1;
      ELSE outcome:='unique_exact'; v_unique_count:=v_unique_count+1; END IF;
    END IF;
    INSERT INTO public.document_reference_resolution_results(org_id,run_id,mention_id,outcome,target_document_id,target_identifier_id,target_purged_at,reason_code,rule_version)
      VALUES(p_org_id,run_id,mention.id,outcome,target_document,target_identifier,
        NULL,
        CASE outcome WHEN 'unique_exact' THEN 'one_active_exact_target' WHEN 'ambiguous' THEN 'multiple_active_exact_targets' WHEN 'conflicting' THEN 'hard_identity_conflict' ELSE 'no_active_exact_target' END,
        'document-reference-exact-v1') RETURNING id INTO result_id;
    INSERT INTO public.current_document_reference_resolutions(org_id,mention_id,run_id,result_id,source_document_id,outcome,target_document_id,target_identifier_id,target_purged_at,resolved_at)
      VALUES(p_org_id,mention.id,run_id,result_id,mention.source_document_id,outcome,target_document,target_identifier,NULL,now())
      ON CONFLICT(org_id,mention_id) DO UPDATE SET run_id=excluded.run_id,result_id=excluded.result_id,source_document_id=excluded.source_document_id,outcome=excluded.outcome,target_document_id=excluded.target_document_id,target_identifier_id=excluded.target_identifier_id,target_purged_at=NULL,resolved_at=excluded.resolved_at;
  END LOOP;
  UPDATE public.document_reference_resolution_runs SET evaluated_count=v_evaluated,unique_count=v_unique_count,ambiguous_count=v_ambiguous_count,conflicting_count=v_conflicting_count,unresolved_count=v_unresolved_count WHERE id=run_id;
  RETURN run_id;
END $$;

CREATE OR REPLACE FUNCTION public.materialize_document_reference_mentions(p_binding_id uuid,p_trigger_key text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE inserted_count integer; key_row record;
BEGIN
  INSERT INTO public.document_reference_mentions(org_id,source_document_id,source_document_version_id,document_field_candidate_id,source_field_candidate_id,source_analysis_run_id,document_version_analysis_binding_id,semantic_candidate_key,identifier_kind,issuer_namespace_normalized,normalized_value,normalized_components,raw_value,display_value,catalogue_version,normalizer_version,evidence_page_number,evidence_quote,evidence_regions,verified_source_anchor)
  SELECT c.org_id,c.document_id,c.document_version_id,c.id,c.source_field_candidate_id,s.source_analysis_run_id,c.document_version_analysis_binding_id,c.semantic_candidate_key,
    (c.normalized_value->>'kind')::public.matter_identifier_kind,c.normalized_value->>'namespace_normalized',c.normalized_value->>'normalized_value',c.normalized_value->'components',c.normalized_value->>'raw',c.normalized_value->>'display',c.normalized_value->>'catalogue_version',c.normalized_value->>'normalizer_version',c.page_number,c.quotation,c.evidence_regions,s.verified_source_anchor
  FROM public.document_field_candidates c JOIN public.source_field_candidates s ON s.org_id=c.org_id AND s.id=c.source_field_candidate_id
  WHERE c.document_version_analysis_binding_id=p_binding_id AND c.field_path='document.official_reference.outbound_mention'
    AND c.value_type='structured' AND c.validation_state<>'invalid' AND c.normalized_value->>'role'='outbound_mention'
    AND c.normalized_value->>'completeness'='complete' AND c.normalized_value->>'match_eligible'='true'
    AND c.normalized_value->>'kind'<>'other_official_reference' AND s.verified_source_anchor IS NOT NULL
  ON CONFLICT(document_field_candidate_id) DO NOTHING;
  GET DIAGNOSTICS inserted_count=ROW_COUNT;
  FOR key_row IN SELECT DISTINCT org_id,issuer_namespace_normalized,identifier_kind,normalized_value FROM public.document_reference_mentions WHERE document_version_analysis_binding_id=p_binding_id ORDER BY org_id,issuer_namespace_normalized,identifier_kind,normalized_value LOOP
    PERFORM public.reevaluate_document_reference_exact_key(key_row.org_id,key_row.issuer_namespace_normalized,key_row.identifier_kind,key_row.normalized_value,'mention_materialized',p_trigger_key||':'||substr(md5(key_row.issuer_namespace_normalized||':'||key_row.identifier_kind::text||':'||key_row.normalized_value),1,24));
  END LOOP;
  RETURN inserted_count;
END $$;

INSERT INTO public.activity_event_definitions(event_type,event_version,category,subject_types,default_visibility,metadata_contract,renderer_key)
VALUES('document.identifier_changed',1,'record',ARRAY['document'],'matter','{"change":"code","identifier_kind":"code"}'::jsonb,'document.identifier_changed');

CREATE OR REPLACE FUNCTION public.perform_document_identifier_command(
  p_command text,p_identifier_id uuid,p_candidate_id uuid,p_expected_identifier_revision bigint,p_expected_document_revision bigint,
  p_matter_identifier_id uuid,p_reason text,p_idempotency_key uuid
) RETURNS TABLE(code text,identifier_id uuid,previous_identifier_id uuid,identifier_revision bigint,document_revision bigint,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; receipt public.document_identifier_command_receipts%ROWTYPE; candidate record; previous public.document_self_identifiers%ROWTYPE; created public.document_self_identifiers%ROWTYPE; document_row public.documents%ROWTYPE; effective_document_id uuid; previous_id_out uuid; document_client_id uuid; key_namespace text; key_kind public.matter_identifier_kind; key_value text; old_key_text text; new_key_text text; fingerprint text; reason text:=nullif(btrim(p_reason),'');
BEGIN
  IF p_command NOT IN ('activate','correct','revoke') OR p_idempotency_key IS NULL OR p_expected_document_revision IS NULL OR p_expected_document_revision<1
    OR (p_command='activate' AND (p_identifier_id IS NOT NULL OR p_candidate_id IS NULL OR p_expected_identifier_revision IS NOT NULL))
    OR (p_command='correct' AND (p_identifier_id IS NULL OR p_candidate_id IS NULL OR p_expected_identifier_revision IS NULL))
    OR (p_command='revoke' AND (p_identifier_id IS NULL OR p_candidate_id IS NOT NULL OR p_expected_identifier_revision IS NULL OR p_matter_identifier_id IS NOT NULL))
    OR (p_command IN ('correct','revoke') AND (reason IS NULL OR char_length(reason)>500 OR reason ~ '[[:cntrl:]]')) THEN
    RETURN QUERY SELECT 'invalid_request',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false; RETURN;
  END IF;
  SELECT * INTO actor FROM public.lock_matter_identifier_actor();
  IF actor.actor_user_id IS NULL THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false; RETURN; END IF;
  fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object('command',p_command,'identifier_id',p_identifier_id,'candidate_id',p_candidate_id,'expected_identifier_revision',p_expected_identifier_revision,'expected_document_revision',p_expected_document_revision,'matter_identifier_id',p_matter_identifier_id,'reason',reason)::text,'utf8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text,151));
  SELECT * INTO receipt FROM public.document_identifier_command_receipts r WHERE r.idempotency_key=p_idempotency_key;
  IF receipt.id IS NOT NULL THEN
    IF receipt.org_id<>actor.org_id OR receipt.actor_user_id<>actor.actor_user_id OR receipt.command<>p_command OR receipt.request_fingerprint<>fingerprint THEN RETURN QUERY SELECT 'idempotency_conflict',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
    ELSE RETURN QUERY SELECT 'ok',receipt.identifier_id,receipt.previous_identifier_id,receipt.result_identifier_revision,receipt.result_document_revision,true; END IF; RETURN;
  END IF;
  IF p_command IN ('correct','revoke') THEN
    SELECT * INTO previous FROM public.document_self_identifiers i WHERE i.org_id=actor.org_id AND i.id=p_identifier_id FOR NO KEY UPDATE;
    IF previous.id IS NULL OR previous.document_id IS NULL THEN RETURN QUERY SELECT 'context_unavailable',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false; RETURN; END IF;
    IF previous.lifecycle_state<>'active' THEN RETURN QUERY SELECT 'identifier_unavailable',NULL::uuid,NULL::uuid,previous.revision,NULL::bigint,false; RETURN; END IF;
    IF previous.revision<>p_expected_identifier_revision THEN RETURN QUERY SELECT 'conflict',previous.id,NULL::uuid,previous.revision,NULL::bigint,false; RETURN; END IF;
    effective_document_id:=previous.document_id;
    key_namespace:=previous.issuer_namespace_normalized; key_kind:=previous.identifier_kind; key_value:=previous.normalized_value;
  END IF;
  IF p_command IN ('activate','correct') THEN
    SELECT c.*,s.source_analysis_run_id,s.verified_source_anchor INTO candidate
    FROM public.document_field_candidates c JOIN public.source_field_candidates s ON s.org_id=c.org_id AND s.id=c.source_field_candidate_id
    WHERE c.org_id=actor.org_id AND c.id=p_candidate_id;
    IF candidate.id IS NULL THEN RETURN QUERY SELECT 'context_unavailable',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false; RETURN; END IF;
    IF p_command='correct' THEN
      IF candidate.document_id<>previous.document_id THEN RETURN QUERY SELECT 'invalid_candidate',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false; RETURN; END IF;
      previous_id_out:=previous.id;
    END IF;
    effective_document_id:=candidate.document_id;
    key_namespace:=candidate.normalized_value->>'namespace_normalized'; key_kind:=(candidate.normalized_value->>'kind')::public.matter_identifier_kind; key_value:=candidate.normalized_value->>'normalized_value';
  END IF;
  SELECT d.* INTO document_row FROM public.documents d JOIN public.matters m ON m.org_id=d.org_id AND m.id=d.matter_id JOIN public.clients c ON c.org_id=m.org_id AND c.id=m.client_id
    WHERE d.org_id=actor.org_id AND d.id=effective_document_id AND d.record_state='active' AND d.deleted_at IS NULL
      AND m.record_state='active' AND m.deleted_at IS NULL AND c.record_state='active' AND c.deleted_at IS NULL FOR NO KEY UPDATE OF d;
  IF document_row.id IS NULL THEN RETURN QUERY SELECT 'context_unavailable',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false; RETURN; END IF;
  SELECT m.client_id INTO document_client_id FROM public.matters m WHERE m.org_id=actor.org_id AND m.id=document_row.matter_id;
  IF document_row.lifecycle_revision<>p_expected_document_revision THEN RETURN QUERY SELECT 'conflict',NULL::uuid,NULL::uuid,NULL::bigint,document_row.lifecycle_revision,false; RETURN; END IF;
  IF p_command IN ('activate','correct') THEN
    IF candidate.document_version_id<>document_row.current_version_id OR candidate.field_path<>'document.official_reference.self_identifier' OR candidate.value_type<>'structured' OR candidate.validation_state='invalid' OR candidate.normalized_value->>'role'<>'self_identifier' OR candidate.normalized_value->>'completeness'<>'complete' OR candidate.normalized_value->>'match_eligible'<>'true' OR candidate.normalized_value->>'kind'='other_official_reference' OR candidate.verified_source_anchor IS NULL THEN
      RETURN QUERY SELECT 'invalid_candidate',NULL::uuid,NULL::uuid,NULL::bigint,document_row.lifecycle_revision,false; RETURN;
    END IF;
  END IF;
  new_key_text:=actor.org_id::text||':'||key_namespace||':'||key_kind::text||':'||key_value;
  IF p_command='correct' THEN
    old_key_text:=actor.org_id::text||':'||previous.issuer_namespace_normalized||':'||previous.identifier_kind::text||':'||previous.normalized_value;
    IF old_key_text<new_key_text THEN
      PERFORM pg_advisory_xact_lock(hashtextextended(old_key_text,151));
      PERFORM pg_advisory_xact_lock(hashtextextended(new_key_text,151));
    ELSIF old_key_text>new_key_text THEN
      PERFORM pg_advisory_xact_lock(hashtextextended(new_key_text,151));
      PERFORM pg_advisory_xact_lock(hashtextextended(old_key_text,151));
    ELSE
      PERFORM pg_advisory_xact_lock(hashtextextended(new_key_text,151));
    END IF;
  ELSE
    PERFORM pg_advisory_xact_lock(hashtextextended(new_key_text,151));
  END IF;
  IF p_command IN ('activate','correct') THEN
    IF p_matter_identifier_id IS NOT NULL AND NOT EXISTS(
      SELECT 1 FROM public.matter_identifiers mi WHERE mi.org_id=actor.org_id AND mi.id=p_matter_identifier_id
        AND mi.matter_id=document_row.matter_id AND mi.lifecycle_state='active' AND mi.identifier_role='self_identifier'
        AND mi.verification_method='human_source' AND mi.identity_eligible
        AND mi.issuer_namespace_normalized=candidate.normalized_value->>'namespace_normalized'
        AND mi.identifier_kind::text=candidate.normalized_value->>'kind' AND mi.normalized_value=candidate.normalized_value->>'normalized_value'
    ) THEN RETURN QUERY SELECT 'invalid_candidate',NULL::uuid,NULL::uuid,NULL::bigint,document_row.lifecycle_revision,false; RETURN; END IF;
    IF EXISTS(
      SELECT 1 FROM public.document_self_identifiers i WHERE i.org_id=actor.org_id AND i.document_id=document_row.id
        AND i.issuer_namespace_normalized=candidate.normalized_value->>'namespace_normalized'
        AND i.identifier_kind::text=candidate.normalized_value->>'kind' AND i.normalized_value=candidate.normalized_value->>'normalized_value'
        AND i.lifecycle_state='active' AND i.id IS DISTINCT FROM p_identifier_id
    ) THEN RETURN QUERY SELECT 'duplicate_active',NULL::uuid,NULL::uuid,NULL::bigint,document_row.lifecycle_revision,false; RETURN; END IF;
  END IF;
  PERFORM set_config('casechain.document_identifier_write','on',true);
  IF p_command IN ('correct','revoke') THEN
    UPDATE public.document_self_identifiers i SET lifecycle_state='revoked',revision=i.revision+1,revoked_at=clock_timestamp(),revoked_by=actor.actor_user_id,revocation_reason=reason,updated_at=clock_timestamp() WHERE i.id=previous.id RETURNING * INTO previous;
  END IF;
  IF p_command IN ('activate','correct') THEN
    INSERT INTO public.document_self_identifiers(org_id,document_id,document_version_id,document_field_candidate_id,source_field_candidate_id,source_analysis_run_id,document_version_analysis_binding_id,semantic_candidate_key,identifier_kind,issuer_namespace_normalized,normalized_value,normalized_components,raw_value,display_value,catalogue_version,normalizer_version,evidence_page_number,evidence_quote,evidence_regions,verified_source_anchor,matter_identifier_id,verified_by,verified_at,predecessor_identifier_id)
    VALUES(actor.org_id,candidate.document_id,candidate.document_version_id,candidate.id,candidate.source_field_candidate_id,candidate.source_analysis_run_id,candidate.document_version_analysis_binding_id,candidate.semantic_candidate_key,(candidate.normalized_value->>'kind')::public.matter_identifier_kind,candidate.normalized_value->>'namespace_normalized',candidate.normalized_value->>'normalized_value',candidate.normalized_value->'components',candidate.normalized_value->>'raw',candidate.normalized_value->>'display',candidate.normalized_value->>'catalogue_version',candidate.normalized_value->>'normalizer_version',candidate.page_number,candidate.quotation,candidate.evidence_regions,candidate.verified_source_anchor,p_matter_identifier_id,actor.actor_user_id,now(),previous_id_out) RETURNING * INTO created;
  ELSE created:=previous; END IF;
  UPDATE public.documents d SET lifecycle_revision=d.lifecycle_revision+1,lifecycle_updated_at=clock_timestamp() WHERE d.id=document_row.id RETURNING * INTO document_row;
  INSERT INTO public.document_identifier_decisions(org_id,document_id,identifier_id,previous_identifier_id,action,reason,actor_user_id,resulting_identifier_revision,resulting_document_revision,idempotency_key)
    VALUES(actor.org_id,document_row.id,created.id,previous_id_out,p_command::public.document_identifier_decision_action,reason,actor.actor_user_id,created.revision,document_row.lifecycle_revision,p_idempotency_key);
  PERFORM public.append_activity_event(actor.org_id,'document.identifier_changed',1::smallint,'user',actor.actor_user_id,'Member','document',document_row.id,document_client_id,document_row.matter_id,'Document','Document identifier '||CASE p_command WHEN 'activate' THEN 'activated' WHEN 'correct' THEN 'corrected' ELSE 'revoked' END,jsonb_build_object('change',CASE p_command WHEN 'activate' THEN 'activated' WHEN 'correct' THEN 'corrected' ELSE 'revoked' END,'identifier_kind',created.identifier_kind::text),'matter',document_row.matter_id,NULL,p_idempotency_key,NULL,'document.identifier.'||p_command||'.'||p_idempotency_key::text,now());
  INSERT INTO public.document_identifier_command_receipts(org_id,actor_user_id,idempotency_key,command,request_fingerprint,identifier_id,previous_identifier_id,result_identifier_revision,result_document_revision)
    VALUES(actor.org_id,actor.actor_user_id,p_idempotency_key,p_command,fingerprint,created.id,previous_id_out,created.revision,document_row.lifecycle_revision);
  IF p_command IN ('correct','revoke') THEN PERFORM public.reevaluate_document_reference_exact_key(actor.org_id,previous.issuer_namespace_normalized,previous.identifier_kind,previous.normalized_value,CASE p_command WHEN 'correct' THEN 'identifier_corrected' ELSE 'identifier_revoked' END,'old.'||p_idempotency_key::text); END IF;
  IF p_command IN ('activate','correct') THEN PERFORM public.reevaluate_document_reference_exact_key(actor.org_id,created.issuer_namespace_normalized,created.identifier_kind,created.normalized_value,'identifier_'||CASE WHEN p_command='activate' THEN 'activated' ELSE 'corrected' END,'new.'||p_idempotency_key::text); END IF;
  RETURN QUERY SELECT 'ok',created.id,previous_id_out,created.revision,document_row.lifecycle_revision,false;
END $$;

CREATE FUNCTION public.activate_document_self_identifier(p_candidate_id uuid,p_expected_document_revision bigint,p_matter_identifier_id uuid,p_idempotency_key uuid)
RETURNS TABLE(code text,identifier_id uuid,previous_identifier_id uuid,identifier_revision bigint,document_revision bigint,replayed boolean)
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ SELECT * FROM public.perform_document_identifier_command('activate',NULL,p_candidate_id,NULL,p_expected_document_revision,p_matter_identifier_id,NULL,p_idempotency_key) $$;
CREATE FUNCTION public.correct_document_self_identifier(p_identifier_id uuid,p_candidate_id uuid,p_expected_identifier_revision bigint,p_expected_document_revision bigint,p_matter_identifier_id uuid,p_reason text,p_idempotency_key uuid)
RETURNS TABLE(code text,identifier_id uuid,previous_identifier_id uuid,identifier_revision bigint,document_revision bigint,replayed boolean)
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ SELECT * FROM public.perform_document_identifier_command('correct',p_identifier_id,p_candidate_id,p_expected_identifier_revision,p_expected_document_revision,p_matter_identifier_id,p_reason,p_idempotency_key) $$;
CREATE FUNCTION public.revoke_document_self_identifier(p_identifier_id uuid,p_expected_identifier_revision bigint,p_expected_document_revision bigint,p_reason text,p_idempotency_key uuid)
RETURNS TABLE(code text,identifier_id uuid,previous_identifier_id uuid,identifier_revision bigint,document_revision bigint,replayed boolean)
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ SELECT * FROM public.perform_document_identifier_command('revoke',p_identifier_id,NULL,p_expected_identifier_revision,p_expected_document_revision,NULL,p_reason,p_idempotency_key) $$;

CREATE FUNCTION public.current_document_reference_reader_actor() RETURNS TABLE(actor_user_id uuid,org_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor uuid:=auth.uid(); membership public.organisation_memberships%ROWTYPE; membership_count integer; owner_state boolean;
BEGIN
  IF actor IS NULL THEN RETURN; END IF;
  SELECT count(*) INTO membership_count FROM public.organisation_memberships m WHERE m.user_id=actor AND m.state IN ('active','suspended');
  IF membership_count<>1 THEN RETURN; END IF;
  SELECT * INTO membership FROM public.organisation_memberships m WHERE m.user_id=actor AND m.state IN ('active','suspended');
  SELECT o.owner_membership_id=membership.id INTO owner_state FROM public.organisations o WHERE o.id=membership.org_id;
  IF membership.state<>'active' OR NOT ('document.view'=ANY(public.organisation_member_capabilities(membership.role,coalesce(owner_state,false),membership.state))) THEN RETURN; END IF;
  RETURN QUERY SELECT actor,membership.org_id;
END $$;

CREATE FUNCTION public.read_current_document_reference_resolutions(p_document_ids uuid[])
RETURNS TABLE(mention_id uuid,source_document_id uuid,source_document_version_id uuid,identifier_kind public.matter_identifier_kind,issuer_namespace_normalized text,normalized_value text,outcome public.document_reference_resolution_outcome,target_document_id uuid,resolved_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record;
BEGIN
  SELECT * INTO actor FROM public.current_document_reference_reader_actor();
  IF actor.actor_user_id IS NULL OR p_document_ids IS NULL OR cardinality(p_document_ids)>100 OR EXISTS(SELECT 1 FROM unnest(p_document_ids) id WHERE id IS NULL) THEN RETURN; END IF;
  RETURN QUERY SELECT m.id,m.source_document_id,m.source_document_version_id,m.identifier_kind,m.issuer_namespace_normalized,m.normalized_value,c.outcome,c.target_document_id,c.resolved_at
  FROM public.document_reference_mentions m JOIN public.current_document_reference_resolutions c ON c.org_id=m.org_id AND c.mention_id=m.id
  JOIN public.documents d ON d.org_id=m.org_id AND d.id=m.source_document_id
  WHERE m.org_id=actor.org_id AND m.source_document_id=ANY(p_document_ids) AND d.record_state='active' AND d.deleted_at IS NULL AND d.current_version_id=m.source_document_version_id
  ORDER BY m.source_document_id,m.id;
END $$;

CREATE FUNCTION public.read_current_document_self_identifiers(p_document_ids uuid[])
RETURNS TABLE(identifier_id uuid,document_id uuid,document_version_id uuid,identifier_kind public.matter_identifier_kind,issuer_namespace_normalized text,normalized_value text,display_value text,matter_identifier_id uuid,verified_by uuid,verified_at timestamptz,revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record;
BEGIN
  SELECT * INTO actor FROM public.current_document_reference_reader_actor();
  IF actor.actor_user_id IS NULL OR p_document_ids IS NULL OR cardinality(p_document_ids)>100 OR EXISTS(SELECT 1 FROM unnest(p_document_ids) id WHERE id IS NULL) THEN RETURN; END IF;
  RETURN QUERY SELECT i.id,i.document_id,i.document_version_id,i.identifier_kind,i.issuer_namespace_normalized,i.normalized_value,i.display_value,i.matter_identifier_id,i.verified_by,i.verified_at,i.revision
  FROM public.document_self_identifiers i JOIN public.documents d ON d.org_id=i.org_id AND d.id=i.document_id
  WHERE i.org_id=actor.org_id AND i.document_id=ANY(p_document_ids) AND i.lifecycle_state='active' AND i.evidence_purged_at IS NULL
    AND d.record_state='active' AND d.deleted_at IS NULL AND d.current_version_id=i.document_version_id
  ORDER BY i.document_id,i.identifier_kind,i.id;
END $$;

-- Materialize mentions only after the existing fenced finisher reports a
-- committed validated/review-required v4 binding.
ALTER FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb)
  RENAME TO finish_document_processing_ai_extraction_v4;
CREATE FUNCTION public.finish_document_processing_ai_extraction(p_processing_run_id uuid,p_processing_lease_token uuid,p_source_analysis_run_id uuid,p_source_analysis_lease_token uuid,p_outcome text,p_input_tokens bigint,p_output_tokens bigint,p_latency_ms integer,p_candidates jsonb DEFAULT '[]'::jsonb,p_review_required boolean DEFAULT false,p_legacy_metadata jsonb DEFAULT NULL)
RETURNS TABLE(code text,binding_id uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE finished record; schema_version text;
BEGIN
  SELECT * INTO finished FROM public.finish_document_processing_ai_extraction_v4(p_processing_run_id,p_processing_lease_token,p_source_analysis_run_id,p_source_analysis_lease_token,p_outcome,p_input_tokens,p_output_tokens,p_latency_ms,p_candidates,p_review_required,p_legacy_metadata);
  SELECT source.schema_version INTO schema_version FROM public.source_analysis_runs source WHERE source.id=p_source_analysis_run_id;
  IF finished.code IN ('validated','review_required') AND schema_version='document-extraction-v4' AND finished.binding_id IS NOT NULL THEN
    PERFORM public.materialize_document_reference_mentions(finished.binding_id,'binding.'||finished.binding_id::text);
  END IF;
  RETURN QUERY SELECT finished.code::text,finished.binding_id::uuid;
END $$;

CREATE FUNCTION public.document_reference_document_availability_hook() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE key_row record; trigger_key text;
BEGIN
  IF NEW.record_state IS NOT DISTINCT FROM OLD.record_state AND NEW.deleted_at IS NOT DISTINCT FROM OLD.deleted_at AND NEW.current_version_id IS NOT DISTINCT FROM OLD.current_version_id THEN RETURN NEW; END IF;
  trigger_key:='document.'||NEW.id::text||'.revision.'||NEW.lifecycle_revision::text;
  PERFORM set_config('casechain.document_reference_internal','on',true);
  DELETE FROM public.current_document_reference_resolutions current_resolution
  USING public.document_reference_mentions mention
  WHERE current_resolution.org_id=NEW.org_id AND mention.org_id=current_resolution.org_id
    AND mention.id=current_resolution.mention_id AND mention.source_document_id=NEW.id
    AND mention.source_document_version_id IS DISTINCT FROM NEW.current_version_id;
  FOR key_row IN
    SELECT DISTINCT org_id,issuer_namespace_normalized,identifier_kind,normalized_value
    FROM public.document_self_identifiers
    WHERE org_id=NEW.org_id AND document_id=NEW.id AND lifecycle_state='active' AND evidence_purged_at IS NULL
    UNION
    SELECT DISTINCT org_id,issuer_namespace_normalized,identifier_kind,normalized_value
    FROM public.document_reference_mentions
    WHERE org_id=NEW.org_id AND source_document_id=NEW.id AND evidence_purged_at IS NULL
    ORDER BY org_id,issuer_namespace_normalized,identifier_kind,normalized_value
  LOOP PERFORM public.reevaluate_document_reference_exact_key(key_row.org_id,key_row.issuer_namespace_normalized,key_row.identifier_kind,key_row.normalized_value,'document_availability_changed',trigger_key||'.'||substr(md5(key_row.issuer_namespace_normalized||':'||key_row.identifier_kind::text||':'||key_row.normalized_value),1,24)); END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER documents_reference_availability AFTER UPDATE OF record_state,deleted_at,current_version_id ON public.documents FOR EACH ROW EXECUTE FUNCTION public.document_reference_document_availability_hook();

CREATE FUNCTION public.scrub_document_reference_evidence_before_document_delete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  PERFORM set_config('casechain.document_identifier_write','on',true);
  PERFORM set_config('casechain.document_reference_internal','on',true);
  UPDATE public.document_reference_resolution_results SET target_document_id=NULL,target_identifier_id=NULL,target_purged_at=clock_timestamp() WHERE org_id=OLD.org_id AND target_document_id=OLD.id AND outcome='unique_exact';
  UPDATE public.current_document_reference_resolutions SET outcome='unresolved',target_document_id=NULL,target_identifier_id=NULL,target_purged_at=NULL,resolved_at=clock_timestamp() WHERE org_id=OLD.org_id AND target_document_id=OLD.id AND outcome='unique_exact';
  UPDATE public.document_self_identifiers SET document_id=NULL,document_version_id=NULL,document_field_candidate_id=NULL,source_field_candidate_id=NULL,source_analysis_run_id=NULL,document_version_analysis_binding_id=NULL,evidence_page_number=NULL,evidence_quote=NULL,evidence_regions=NULL,verified_source_anchor=NULL,evidence_purged_at=clock_timestamp(),matter_identifier_id=NULL,lifecycle_state='revoked',revision=revision+1,revoked_at=coalesce(revoked_at,clock_timestamp()),revoked_by=coalesce(revoked_by,OLD.trashed_by,verified_by),revocation_reason=coalesce(revocation_reason,'Source document permanently purged'),updated_at=clock_timestamp() WHERE org_id=OLD.org_id AND document_id=OLD.id;
  UPDATE public.document_reference_mentions SET source_document_id=NULL,source_document_version_id=NULL,document_field_candidate_id=NULL,source_field_candidate_id=NULL,source_analysis_run_id=NULL,document_version_analysis_binding_id=NULL,raw_value=NULL,display_value=NULL,evidence_page_number=NULL,evidence_quote=NULL,evidence_regions=NULL,verified_source_anchor=NULL,evidence_purged_at=clock_timestamp() WHERE org_id=OLD.org_id AND source_document_id=OLD.id;
  RETURN OLD;
END $$;
CREATE TRIGGER documents_scrub_reference_evidence BEFORE DELETE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.scrub_document_reference_evidence_before_document_delete();

CREATE FUNCTION public.scrub_document_reference_evidence_before_candidate_delete() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  PERFORM set_config('casechain.document_identifier_write','on',true);
  PERFORM set_config('casechain.document_reference_internal','on',true);
  UPDATE public.document_reference_resolution_results result_row
  SET target_document_id=NULL,target_identifier_id=NULL,target_purged_at=clock_timestamp()
  WHERE result_row.org_id=OLD.org_id AND result_row.outcome='unique_exact'
    AND result_row.target_identifier_id IN (
      SELECT identifier.id FROM public.document_self_identifiers identifier
      WHERE identifier.org_id=OLD.org_id AND identifier.document_field_candidate_id=OLD.id
    );
  UPDATE public.current_document_reference_resolutions current_row
  SET outcome='unresolved',target_document_id=NULL,target_identifier_id=NULL,target_purged_at=NULL,resolved_at=clock_timestamp()
  WHERE current_row.org_id=OLD.org_id AND current_row.outcome='unique_exact'
    AND current_row.target_identifier_id IN (
      SELECT identifier.id FROM public.document_self_identifiers identifier
      WHERE identifier.org_id=OLD.org_id AND identifier.document_field_candidate_id=OLD.id
    );
  DELETE FROM public.current_document_reference_resolutions current_row
  USING public.document_reference_mentions mention
  WHERE current_row.org_id=OLD.org_id AND mention.org_id=current_row.org_id
    AND mention.id=current_row.mention_id AND mention.document_field_candidate_id=OLD.id;
  UPDATE public.document_self_identifiers SET document_id=NULL,document_version_id=NULL,document_field_candidate_id=NULL,source_field_candidate_id=NULL,source_analysis_run_id=NULL,document_version_analysis_binding_id=NULL,evidence_page_number=NULL,evidence_quote=NULL,evidence_regions=NULL,verified_source_anchor=NULL,evidence_purged_at=clock_timestamp(),matter_identifier_id=NULL,lifecycle_state='revoked',revision=revision+1,revoked_at=coalesce(revoked_at,clock_timestamp()),revoked_by=coalesce(revoked_by,verified_by),revocation_reason=coalesce(revocation_reason,'Source evidence permanently purged'),updated_at=clock_timestamp() WHERE org_id=OLD.org_id AND document_field_candidate_id=OLD.id;
  UPDATE public.document_reference_mentions SET source_document_id=NULL,source_document_version_id=NULL,document_field_candidate_id=NULL,source_field_candidate_id=NULL,source_analysis_run_id=NULL,document_version_analysis_binding_id=NULL,raw_value=NULL,display_value=NULL,evidence_page_number=NULL,evidence_quote=NULL,evidence_regions=NULL,verified_source_anchor=NULL,evidence_purged_at=clock_timestamp() WHERE org_id=OLD.org_id AND document_field_candidate_id=OLD.id;
  RETURN OLD;
END $$;
CREATE TRIGGER document_field_candidates_scrub_reference_evidence BEFORE DELETE ON public.document_field_candidates FOR EACH ROW EXECUTE FUNCTION public.scrub_document_reference_evidence_before_candidate_delete();

ALTER TABLE public.document_self_identifiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_identifier_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_identifier_command_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_reference_mentions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_reference_resolution_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_reference_resolution_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.current_document_reference_resolutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_self_identifiers FORCE ROW LEVEL SECURITY;
ALTER TABLE public.document_identifier_decisions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.document_identifier_command_receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE public.document_reference_mentions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.document_reference_resolution_runs FORCE ROW LEVEL SECURITY;
ALTER TABLE public.document_reference_resolution_results FORCE ROW LEVEL SECURITY;
ALTER TABLE public.current_document_reference_resolutions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.document_self_identifiers,public.document_identifier_decisions,public.document_identifier_command_receipts,public.document_reference_mentions,public.document_reference_resolution_runs,public.document_reference_resolution_results,public.current_document_reference_resolutions FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.perform_document_identifier_command(text,uuid,uuid,bigint,bigint,uuid,text,uuid),public.reevaluate_document_reference_exact_key(uuid,text,public.matter_identifier_kind,text,text,text),public.materialize_document_reference_mentions(uuid,text),public.document_self_identifier_enforce(),public.document_identifier_decision_enforce(),public.document_reference_private_rows_immutable(),public.current_document_reference_reader_actor(),public.document_reference_document_availability_hook(),public.scrub_document_reference_evidence_before_document_delete(),public.scrub_document_reference_evidence_before_candidate_delete(),public.finish_document_processing_ai_extraction_v4(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.activate_document_self_identifier(uuid,bigint,uuid,uuid),public.correct_document_self_identifier(uuid,uuid,bigint,bigint,uuid,text,uuid),public.revoke_document_self_identifier(uuid,bigint,bigint,text,uuid),public.read_current_document_reference_resolutions(uuid[]),public.read_current_document_self_identifiers(uuid[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.activate_document_self_identifier(uuid,bigint,uuid,uuid),public.correct_document_self_identifier(uuid,uuid,bigint,bigint,uuid,text,uuid),public.revoke_document_self_identifier(uuid,bigint,bigint,text,uuid),public.read_current_document_reference_resolutions(uuid[]),public.read_current_document_self_identifiers(uuid[]) TO authenticated;
REVOKE ALL ON FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb) TO service_role;

COMMENT ON FUNCTION public.reevaluate_document_reference_exact_key(uuid,text,public.matter_identifier_kind,text,text,text) IS 'Bounded indexed exact-key resolver. It never changes Matter identity, placement, effective metadata, procedural relationships, Review, or notifications.';
COMMIT;
