-- Immutable document-version provenance bindings and document-level candidate
-- materialization. Source candidates remain the sole model-output boundary:
-- this migration never invokes a provider or accepts provider payloads.
BEGIN;

-- The lifecycle foundation created this table as a transitional asset binding.
-- Retain its stable identity and historical rows while adding the document
-- identity needed by all later document-level provenance consumers.
ALTER TABLE public.document_version_analysis_bindings
  ADD COLUMN document_id uuid;

UPDATE public.document_version_analysis_bindings AS binding
SET document_id = version.document_id
FROM public.document_versions AS version
WHERE version.org_id = binding.org_id
  AND version.id = binding.document_version_id;

ALTER TABLE public.document_version_analysis_bindings
  ALTER COLUMN document_id SET NOT NULL,
  ADD CONSTRAINT document_version_analysis_bindings_document_org_fkey
    FOREIGN KEY (org_id, document_id)
    REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT document_version_analysis_bindings_reason_safe
    CHECK (binding_reason ~ '^[a-z][a-z0-9_]{0,63}$');

CREATE INDEX document_version_analysis_bindings_document_created_idx
  ON public.document_version_analysis_bindings (org_id, document_id, created_at DESC);

-- Source candidates already preserve their source validation state. A document
-- candidate freezes that source snapshot against one immutable document
-- version; later decisions will append separate rows instead of mutating it.
CREATE TABLE public.document_field_candidates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  document_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  document_version_analysis_binding_id uuid NOT NULL,
  source_field_candidate_id uuid NOT NULL,
  semantic_candidate_key text NOT NULL,
  field_path text NOT NULL,
  value_type public.source_field_candidate_value_type NOT NULL,
  normalized_value jsonb NOT NULL,
  page_number integer NOT NULL,
  evidence_page_count integer NOT NULL,
  quotation text NOT NULL,
  evidence_regions jsonb,
  confidence numeric(4, 3) NOT NULL,
  validation_state public.source_field_candidate_validation_state NOT NULL,
  validation_error_codes text[],
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_field_candidates_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT document_field_candidates_document_org_fkey
    FOREIGN KEY (org_id, document_id)
    REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_field_candidates_version_org_fkey
    FOREIGN KEY (org_id, document_version_id)
    REFERENCES public.document_versions(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_field_candidates_binding_org_fkey
    FOREIGN KEY (org_id, document_version_analysis_binding_id)
    REFERENCES public.document_version_analysis_bindings(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_field_candidates_source_org_fkey
    FOREIGN KEY (org_id, source_field_candidate_id)
    REFERENCES public.source_field_candidates(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_field_candidates_binding_source_unique
    UNIQUE (document_version_analysis_binding_id, source_field_candidate_id),
  CONSTRAINT document_field_candidates_safe_identity CHECK (
    semantic_candidate_key ~ '^[a-z][a-z0-9_.:-]{0,199}$'
    AND field_path ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){0,15}$'
  ),
  CONSTRAINT document_field_candidates_typed_value CHECK (
    public.source_field_candidate_normalized_value_is_valid(value_type, normalized_value)
  ),
  CONSTRAINT document_field_candidates_page_and_quote CHECK (
    page_number > 0
    AND evidence_page_count > 0
    AND page_number <= evidence_page_count
    AND char_length(quotation) BETWEEN 1 AND 1000
    AND quotation !~ '[[:cntrl:]]'
  ),
  CONSTRAINT document_field_candidates_regions_valid CHECK (
    public.source_field_candidate_regions_are_valid(evidence_regions)
  ),
  CONSTRAINT document_field_candidates_confidence_valid CHECK (
    confidence >= 0 AND confidence <= 1
  ),
  CONSTRAINT document_field_candidates_validation_errors_safe CHECK (
    public.source_field_candidate_validation_errors_are_safe(validation_error_codes)
  ),
  CONSTRAINT document_field_candidates_validation_state_consistent CHECK (
    (validation_state = 'invalid' AND validation_error_codes IS NOT NULL)
    OR (validation_state <> 'invalid' AND validation_error_codes IS NULL)
  )
);

CREATE INDEX document_field_candidates_document_version_path_idx
  ON public.document_field_candidates (
    org_id, document_id, document_version_id, field_path, semantic_candidate_key
  );
CREATE INDEX document_field_candidates_source_idx
  ON public.document_field_candidates (org_id, source_field_candidate_id);

CREATE OR REPLACE FUNCTION public.document_version_analysis_binding_insert_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  version_document_id uuid;
  version_asset_id uuid;
  version_validation_state public.document_version_validation_state;
  version_state public.document_version_state;
  run_asset_id uuid;
  run_kind public.source_analysis_kind;
  run_analysis_state public.source_analysis_provenance_state;
  run_state public.source_analysis_run_state;
BEGIN
  SELECT document_id, asset_id, validation_state, state
    INTO version_document_id, version_asset_id, version_validation_state, version_state
  FROM public.document_versions
  WHERE org_id = NEW.org_id AND id = NEW.document_version_id
  FOR KEY SHARE;

  SELECT asset_id, analysis_kind, analysis_state, state
    INTO run_asset_id, run_kind, run_analysis_state, run_state
  FROM public.source_analysis_runs
  WHERE org_id = NEW.org_id AND id = NEW.source_analysis_run_id
  FOR KEY SHARE;

  IF NEW.document_id IS NULL THEN
    NEW.document_id := version_document_id;
  END IF;

  IF version_document_id IS NULL
     OR NEW.document_id IS DISTINCT FROM version_document_id
     OR run_asset_id IS NULL
     OR run_asset_id IS DISTINCT FROM version_asset_id THEN
    RAISE EXCEPTION 'analysis binding must reference one organisation document version and its exact asset';
  END IF;

  IF version_validation_state <> 'valid'::public.document_version_validation_state
     OR version_state NOT IN ('current'::public.document_version_state, 'superseded'::public.document_version_state) THEN
    RAISE EXCEPTION 'analysis binding requires a valid current or superseded immutable document version';
  END IF;

  -- Keep the completed validation-worker contract compatible. New
  -- document-candidate materialization below additionally requires a
  -- validated AI extraction run, so an asset-validation binding can never be
  -- mistaken for model-derived document evidence.
  IF NOT (
    (run_kind = 'ai_extraction'::public.source_analysis_kind
      AND run_analysis_state = 'validated'::public.source_analysis_provenance_state)
    OR (run_kind = 'asset_validation'::public.source_analysis_kind
      AND run_state = 'succeeded'::public.source_analysis_run_state)
  ) THEN
    RAISE EXCEPTION 'analysis binding requires a terminal compatible source analysis run';
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS bindings_asset_consistent ON public.document_version_analysis_bindings;
CREATE TRIGGER document_version_analysis_bindings_insert_guard
  BEFORE INSERT ON public.document_version_analysis_bindings
  FOR EACH ROW EXECUTE FUNCTION public.document_version_analysis_binding_insert_guard();

CREATE FUNCTION public.document_version_analysis_binding_immutable_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  RAISE EXCEPTION 'document version analysis bindings are immutable once materialized';
END $$;

CREATE TRIGGER document_version_analysis_bindings_no_update
  BEFORE UPDATE ON public.document_version_analysis_bindings
  FOR EACH ROW EXECUTE FUNCTION public.document_version_analysis_binding_immutable_guard();

-- The foundation's existing no-delete trigger remains intentionally in place.

CREATE FUNCTION public.document_field_candidate_insert_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  binding_row public.document_version_analysis_bindings%ROWTYPE;
  source_row public.source_field_candidates%ROWTYPE;
  version_asset_id uuid;
  version_page_count integer;
BEGIN
  SELECT * INTO binding_row
  FROM public.document_version_analysis_bindings
  WHERE org_id = NEW.org_id AND id = NEW.document_version_analysis_binding_id
  FOR KEY SHARE;
  SELECT * INTO source_row
  FROM public.source_field_candidates
  WHERE org_id = NEW.org_id AND id = NEW.source_field_candidate_id
  FOR KEY SHARE;
  SELECT asset_id, page_count INTO version_asset_id, version_page_count
  FROM public.document_versions
  WHERE org_id = NEW.org_id AND id = NEW.document_version_id
  FOR KEY SHARE;

  IF binding_row.id IS NULL
     OR source_row.id IS NULL
     OR NEW.document_id IS DISTINCT FROM binding_row.document_id
     OR NEW.document_version_id IS DISTINCT FROM binding_row.document_version_id
     OR source_row.source_analysis_run_id IS DISTINCT FROM binding_row.source_analysis_run_id
     OR source_row.asset_id IS DISTINCT FROM version_asset_id
     OR version_page_count IS NULL
     OR source_row.evidence_page_count <> version_page_count
     OR source_row.page_number > version_page_count THEN
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

CREATE TRIGGER document_field_candidates_insert_guard
  BEFORE INSERT ON public.document_field_candidates
  FOR EACH ROW EXECUTE FUNCTION public.document_field_candidate_insert_guard();

CREATE FUNCTION public.document_field_candidate_immutable_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  RAISE EXCEPTION 'document field candidates are immutable once materialized';
END $$;

CREATE TRIGGER document_field_candidates_no_update
  BEFORE UPDATE ON public.document_field_candidates
  FOR EACH ROW EXECUTE FUNCTION public.document_field_candidate_immutable_guard();
CREATE TRIGGER document_field_candidates_no_delete
  BEFORE DELETE ON public.document_field_candidates
  FOR EACH ROW EXECUTE FUNCTION public.document_field_candidate_immutable_guard();

-- This service-only command binds a terminal source analysis to exactly one
-- immutable current or historical version and copies every source candidate
-- from that run. It deliberately has no provider/model input and therefore
-- cannot trigger a duplicate generation.
CREATE FUNCTION public.materialize_document_version_analysis(
  p_document_version_id uuid,
  p_source_analysis_run_id uuid,
  p_binding_reason text,
  p_created_by uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  version_row public.document_versions%ROWTYPE;
  run_row public.source_analysis_runs%ROWTYPE;
  existing_binding public.document_version_analysis_bindings%ROWTYPE;
  binding_id uuid;
  source_count bigint;
  materialized_count bigint;
BEGIN
  IF p_document_version_id IS NULL
     OR p_source_analysis_run_id IS NULL
     OR p_binding_reason IS NULL
     OR p_binding_reason !~ '^[a-z][a-z0-9_]{0,63}$' THEN
    RAISE EXCEPTION 'document version analysis materialization request is incomplete or unsafe';
  END IF;

  SELECT * INTO version_row
  FROM public.document_versions
  WHERE id = p_document_version_id
  FOR UPDATE;
  SELECT * INTO run_row
  FROM public.source_analysis_runs
  WHERE id = p_source_analysis_run_id
  FOR UPDATE;

  IF version_row.id IS NULL
     OR run_row.id IS NULL
     OR version_row.org_id IS DISTINCT FROM run_row.org_id
     OR version_row.asset_id IS DISTINCT FROM run_row.asset_id
     OR version_row.validation_state <> 'valid'::public.document_version_validation_state
     OR version_row.state NOT IN ('current'::public.document_version_state, 'superseded'::public.document_version_state)
     OR version_row.page_count IS NULL
     OR run_row.analysis_kind <> 'ai_extraction'::public.source_analysis_kind
     OR run_row.analysis_state <> 'validated'::public.source_analysis_provenance_state THEN
    RAISE EXCEPTION 'document version analysis materialization requires a compatible validated extraction and immutable document version';
  END IF;

  -- A supplied human actor is immutable audit provenance, not a caller-
  -- asserted label. Resolve it through the canonical membership/capability
  -- matrix for this exact tenant. NULL remains reserved for trusted system
  -- materialization where there is no human actor to record.
  IF p_created_by IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.organisation_memberships AS membership
    JOIN public.organisations AS organisation
      ON organisation.id = membership.org_id
    WHERE membership.org_id = version_row.org_id
      AND membership.user_id = p_created_by
      AND membership.state = 'active'::public.organisation_membership_state
      AND 'document.version.attach' = ANY(
        public.organisation_member_capabilities(
          membership.role,
          organisation.owner_membership_id = membership.id,
          membership.state
        )
      )
  ) THEN
    RAISE EXCEPTION 'document version analysis actor must be an active authorised organisation member';
  END IF;

  SELECT * INTO existing_binding
  FROM public.document_version_analysis_bindings
  WHERE document_version_id = version_row.id
    AND source_analysis_run_id = run_row.id
  FOR KEY SHARE;

  IF existing_binding.id IS NOT NULL THEN
    IF existing_binding.document_id IS DISTINCT FROM version_row.document_id
       OR existing_binding.binding_reason IS DISTINCT FROM p_binding_reason
       OR existing_binding.created_by IS DISTINCT FROM p_created_by THEN
      RAISE EXCEPTION 'document version analysis binding conflicts with existing immutable materialization';
    END IF;
    binding_id := existing_binding.id;
  ELSE
    INSERT INTO public.document_version_analysis_bindings(
      org_id, document_id, document_version_id, source_analysis_run_id,
      binding_reason, created_by
    ) VALUES (
      version_row.org_id, version_row.document_id, version_row.id, run_row.id,
      p_binding_reason, p_created_by
    ) RETURNING id INTO binding_id;
  END IF;

  INSERT INTO public.document_field_candidates(
    org_id, document_id, document_version_id, document_version_analysis_binding_id,
    source_field_candidate_id, semantic_candidate_key, field_path, value_type,
    normalized_value, page_number, evidence_page_count, quotation,
    evidence_regions, confidence, validation_state, validation_error_codes
  )
  SELECT
    source.org_id, version_row.document_id, version_row.id, binding_id,
    source.id, source.semantic_candidate_key, source.field_path, source.value_type,
    source.normalized_value, source.page_number, source.evidence_page_count,
    source.quotation, source.evidence_regions, source.confidence,
    source.validation_state, source.validation_error_codes
  FROM public.source_field_candidates AS source
  WHERE source.org_id = run_row.org_id
    AND source.source_analysis_run_id = run_row.id
  ON CONFLICT (document_version_analysis_binding_id, source_field_candidate_id)
  DO NOTHING;

  SELECT count(*) INTO source_count
  FROM public.source_field_candidates
  WHERE org_id = run_row.org_id AND source_analysis_run_id = run_row.id;
  SELECT count(*) INTO materialized_count
  FROM public.document_field_candidates
  WHERE org_id = run_row.org_id AND document_version_analysis_binding_id = binding_id;
  IF source_count <> materialized_count THEN
    RAISE EXCEPTION 'document version analysis materialization is incomplete';
  END IF;

  RETURN binding_id;
END $$;

ALTER TABLE public.document_version_analysis_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_version_analysis_bindings FORCE ROW LEVEL SECURITY;
ALTER TABLE public.document_field_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_field_candidates FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.document_version_analysis_bindings, public.document_field_candidates
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.document_version_analysis_binding_insert_guard(),
  public.document_version_analysis_binding_immutable_guard(),
  public.document_field_candidate_insert_guard(),
  public.document_field_candidate_immutable_guard(),
  public.materialize_document_version_analysis(uuid, uuid, text, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.materialize_document_version_analysis(uuid, uuid, text, uuid)
  TO service_role;

COMMENT ON TABLE public.document_version_analysis_bindings IS
  'Immutable asset-compatible source-analysis bindings to exact current or historical valid document versions. Browser and direct service access are denied.';
COMMENT ON TABLE public.document_field_candidates IS
  'Immutable document-version copies of source candidates. Later decisions and effective metadata are intentionally out of scope.';
COMMENT ON FUNCTION public.materialize_document_version_analysis(uuid, uuid, text, uuid) IS
  'Service-only, idempotent binding and source-candidate materialization. Accepts no model payload and never invokes model generation.';

COMMIT;
