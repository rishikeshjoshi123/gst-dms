-- Immutable, asset-scoped source field candidates for validated AI analysis.
--
-- This tranche deliberately stops at source candidates. It does not bind a
-- candidate to a document version, make it effective metadata, retain raw
-- provider output, or change any processing consumer.
BEGIN;

CREATE TYPE public.source_field_candidate_value_type AS ENUM (
  'text',
  'code',
  'date',
  'integer',
  'decimal',
  'boolean'
);

CREATE TYPE public.source_field_candidate_validation_state AS ENUM (
  'eligible',
  'provisional',
  'conflicting',
  'invalid'
);

-- Values are purposefully a small, typed JSON scalar contract. This retains
-- exact normalized decimal/integer representations without accepting object,
-- array, or arbitrary provider-response JSON at the candidate boundary.
CREATE FUNCTION public.source_field_candidate_normalized_value_is_valid(
  p_value_type public.source_field_candidate_value_type,
  p_value jsonb
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  value_text text;
BEGIN
  IF p_value IS NULL THEN
    RETURN false;
  END IF;

  IF p_value_type = 'boolean'::public.source_field_candidate_value_type THEN
    RETURN jsonb_typeof(p_value) = 'boolean';
  END IF;

  IF jsonb_typeof(p_value) <> 'string' THEN
    RETURN false;
  END IF;
  value_text := p_value #>> '{}';

  IF p_value_type = 'text'::public.source_field_candidate_value_type THEN
    RETURN char_length(value_text) BETWEEN 1 AND 1024
      AND value_text !~ '[[:cntrl:]]';
  ELSIF p_value_type = 'code'::public.source_field_candidate_value_type THEN
    RETURN value_text ~ '^[A-Za-z0-9][A-Za-z0-9 .,/()&+#:_-]{0,255}$';
  ELSIF p_value_type = 'date'::public.source_field_candidate_value_type THEN
    RETURN value_text ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      AND pg_input_is_valid(value_text, 'date');
  ELSIF p_value_type = 'integer'::public.source_field_candidate_value_type THEN
    RETURN value_text ~ '^-?(0|[1-9][0-9]{0,17})$';
  ELSIF p_value_type = 'decimal'::public.source_field_candidate_value_type THEN
    RETURN value_text ~ '^-?(0|[1-9][0-9]{0,17})(\.[0-9]{1,6})?$';
  END IF;

  RETURN false;
END $$;

-- Regions are optional normalized page rectangles. Their strict shape keeps
-- evidence structured and bounded; the short quotation remains the primary
-- human-readable evidence anchor.
CREATE FUNCTION public.source_field_candidate_regions_are_valid(p_regions jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  region jsonb;
  x numeric;
  y numeric;
  width numeric;
  height numeric;
BEGIN
  IF p_regions IS NULL THEN
    RETURN true;
  END IF;
  IF jsonb_typeof(p_regions) <> 'array'
     OR jsonb_array_length(p_regions) NOT BETWEEN 1 AND 16 THEN
    RETURN false;
  END IF;

  FOR region IN SELECT value FROM jsonb_array_elements(p_regions) LOOP
    IF jsonb_typeof(region) <> 'object'
       OR (SELECT count(*) FROM jsonb_object_keys(region)) <> 4
       OR NOT (region ?& ARRAY['x', 'y', 'width', 'height'])
       OR jsonb_typeof(region -> 'x') <> 'number'
       OR jsonb_typeof(region -> 'y') <> 'number'
       OR jsonb_typeof(region -> 'width') <> 'number'
       OR jsonb_typeof(region -> 'height') <> 'number' THEN
      RETURN false;
    END IF;

    BEGIN
      x := (region ->> 'x')::numeric;
      y := (region ->> 'y')::numeric;
      width := (region ->> 'width')::numeric;
      height := (region ->> 'height')::numeric;
    EXCEPTION WHEN others THEN
      RETURN false;
    END;

    IF x < 0 OR y < 0 OR width <= 0 OR height <= 0
       OR x + width > 1 OR y + height > 1 THEN
      RETURN false;
    END IF;
  END LOOP;

  RETURN true;
END $$;

CREATE FUNCTION public.source_field_candidate_validation_errors_are_safe(p_errors text[])
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  error_code text;
BEGIN
  IF p_errors IS NULL THEN
    RETURN true;
  END IF;
  IF cardinality(p_errors) NOT BETWEEN 1 AND 16
     OR array_position(p_errors, NULL) IS NOT NULL THEN
    RETURN false;
  END IF;
  FOREACH error_code IN ARRAY p_errors LOOP
    IF error_code !~ '^[a-z][a-z0-9_]{0,99}$' THEN
      RETURN false;
    END IF;
  END LOOP;
  RETURN true;
END $$;

CREATE TABLE public.source_field_candidates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  source_analysis_run_id uuid NOT NULL,
  asset_id uuid NOT NULL,
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
  CONSTRAINT source_field_candidates_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT source_field_candidates_run_org_fkey
    FOREIGN KEY (org_id, source_analysis_run_id)
    REFERENCES public.source_analysis_runs(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT source_field_candidates_asset_org_fkey
    FOREIGN KEY (org_id, asset_id)
    REFERENCES public.file_assets(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT source_field_candidates_run_semantic_key_unique
    UNIQUE (source_analysis_run_id, semantic_candidate_key),
  CONSTRAINT source_field_candidates_safe_identity CHECK (
    semantic_candidate_key ~ '^[a-z][a-z0-9_.:-]{0,199}$'
    AND field_path ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){0,15}$'
  ),
  CONSTRAINT source_field_candidates_typed_value CHECK (
    public.source_field_candidate_normalized_value_is_valid(value_type, normalized_value)
  ),
  CONSTRAINT source_field_candidates_page_and_quote CHECK (
    page_number > 0
    AND evidence_page_count > 0
    AND page_number <= evidence_page_count
    AND char_length(quotation) BETWEEN 1 AND 1000
    AND quotation !~ '[[:cntrl:]]'
  ),
  CONSTRAINT source_field_candidates_regions_valid CHECK (
    public.source_field_candidate_regions_are_valid(evidence_regions)
  ),
  CONSTRAINT source_field_candidates_confidence_valid CHECK (
    confidence >= 0 AND confidence <= 1
  ),
  CONSTRAINT source_field_candidates_validation_errors_safe CHECK (
    public.source_field_candidate_validation_errors_are_safe(validation_error_codes)
  ),
  CONSTRAINT source_field_candidates_validation_state_consistent CHECK (
    (validation_state = 'invalid' AND validation_error_codes IS NOT NULL)
    OR (validation_state <> 'invalid' AND validation_error_codes IS NULL)
  )
);

CREATE INDEX source_field_candidates_run_path_idx
  ON public.source_field_candidates (org_id, source_analysis_run_id, field_path, semantic_candidate_key);
CREATE INDEX source_field_candidates_asset_page_idx
  ON public.source_field_candidates (org_id, asset_id, page_number, created_at);

CREATE FUNCTION public.source_field_candidate_insert_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  run_asset_id uuid;
  run_kind public.source_analysis_kind;
  run_state public.source_analysis_provenance_state;
  asset_availability public.file_asset_availability;
  asset_validated_at timestamptz;
  asset_mime_type text;
  validated_pages integer;
BEGIN
  SELECT asset_id, analysis_kind, analysis_state
    INTO run_asset_id, run_kind, run_state
  FROM public.source_analysis_runs
  WHERE org_id = NEW.org_id AND id = NEW.source_analysis_run_id
  FOR KEY SHARE;

  IF run_asset_id IS NULL
     OR run_kind <> 'ai_extraction'::public.source_analysis_kind
     OR run_state <> 'validated'::public.source_analysis_provenance_state THEN
    RAISE EXCEPTION 'source field candidates require a validated AI extraction run';
  END IF;
  IF NEW.asset_id IS DISTINCT FROM run_asset_id THEN
    RAISE EXCEPTION 'source field candidate evidence must reference its run asset';
  END IF;

  SELECT availability, validated_at, detected_mime_type, validated_page_count
    INTO asset_availability, asset_validated_at, asset_mime_type, validated_pages
  FROM public.file_assets
  WHERE org_id = NEW.org_id AND id = NEW.asset_id
  FOR KEY SHARE;
  IF asset_availability <> 'available'::public.file_asset_availability
     OR asset_validated_at IS NULL
     OR asset_mime_type <> 'application/pdf'
     OR validated_pages IS NULL
     OR validated_pages <= 0 THEN
    RAISE EXCEPTION 'source field candidates require an available validated PDF asset';
  END IF;
  IF NEW.page_number > validated_pages THEN
    RAISE EXCEPTION 'source field candidate page is outside the validated asset';
  END IF;

  -- The candidate owns this page-bound evidence snapshot. The file asset's
  -- page count is additionally fenced below once it is known, preventing a
  -- later permitted lifecycle update from shrinking the evidence boundary.
  NEW.evidence_page_count := validated_pages;

  RETURN NEW;
END $$;

CREATE TRIGGER source_field_candidates_insert_guard
  BEFORE INSERT ON public.source_field_candidates
  FOR EACH ROW EXECUTE FUNCTION public.source_field_candidate_insert_guard();

CREATE FUNCTION public.source_field_candidate_immutable_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  RAISE EXCEPTION 'source field candidates are immutable once materialized';
END $$;

CREATE TRIGGER source_field_candidates_no_update
  BEFORE UPDATE ON public.source_field_candidates
  FOR EACH ROW EXECUTE FUNCTION public.source_field_candidate_immutable_guard();

CREATE TRIGGER source_field_candidates_no_delete
  BEFORE DELETE ON public.source_field_candidates
  FOR EACH ROW EXECUTE FUNCTION public.source_field_candidate_immutable_guard();

-- A validated asset is immutable evidence. The lifecycle may still advance
-- availability through its existing state machine, but it may not revise the
-- page boundary that source candidates have recorded.
CREATE OR REPLACE FUNCTION public.document_lifecycle_asset_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.org_id IS DISTINCT FROM OLD.org_id
     OR NEW.bucket_id IS DISTINCT FROM OLD.bucket_id
     OR NEW.object_key IS DISTINCT FROM OLD.object_key
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'file asset identity is immutable';
  END IF;
  IF (OLD.sha256 IS NOT NULL AND NEW.sha256 IS DISTINCT FROM OLD.sha256)
     OR (OLD.sha256 IS NULL AND NEW.sha256 IS NOT NULL AND NEW.sha256 !~ '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'file asset sha256 is immutable';
  END IF;
  IF (OLD.byte_size IS NOT NULL AND NEW.byte_size IS DISTINCT FROM OLD.byte_size)
     OR (OLD.byte_size IS NULL AND NEW.byte_size IS NOT NULL AND NEW.byte_size <= 0) THEN
    RAISE EXCEPTION 'file asset byte size is immutable';
  END IF;
  IF OLD.detected_mime_type IS NOT NULL
     AND NEW.detected_mime_type IS DISTINCT FROM OLD.detected_mime_type THEN
    RAISE EXCEPTION 'file asset mime type is immutable';
  END IF;
  IF OLD.validated_page_count IS NOT NULL
     AND NEW.validated_page_count IS DISTINCT FROM OLD.validated_page_count THEN
    RAISE EXCEPTION 'validated file asset page count is immutable';
  END IF;
  RETURN NEW;
END $$;

-- This is the only service-writable materialization boundary. Repeated calls
-- with the same exact canonical candidate return the original row; a semantic
-- key collision with different material is rejected instead of being updated.
CREATE FUNCTION public.materialize_source_field_candidate(
  p_source_analysis_run_id uuid,
  p_semantic_candidate_key text,
  p_field_path text,
  p_value_type public.source_field_candidate_value_type,
  p_normalized_value jsonb,
  p_page_number integer,
  p_quotation text,
  p_evidence_regions jsonb,
  p_confidence numeric,
  p_validation_state public.source_field_candidate_validation_state,
  p_validation_error_codes text[] DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  run_row public.source_analysis_runs%ROWTYPE;
  existing_row public.source_field_candidates%ROWTYPE;
  candidate_id uuid;
  canonical_confidence numeric(4, 3);
BEGIN
  IF p_source_analysis_run_id IS NULL
     OR p_semantic_candidate_key IS NULL
     OR p_field_path IS NULL
     OR p_value_type IS NULL
     OR p_normalized_value IS NULL
     OR p_page_number IS NULL
     OR p_quotation IS NULL
     OR p_confidence IS NULL
     OR p_validation_state IS NULL THEN
    RAISE EXCEPTION 'source field candidate materialization request is incomplete';
  END IF;

  IF p_confidence < 0 OR p_confidence > 1 THEN
    RAISE EXCEPTION 'source field candidate confidence must be between zero and one';
  END IF;
  canonical_confidence := round(p_confidence, 3)::numeric(4, 3);

  SELECT * INTO run_row
  FROM public.source_analysis_runs
  WHERE id = p_source_analysis_run_id
  FOR UPDATE;
  IF run_row.id IS NULL
     OR run_row.analysis_kind <> 'ai_extraction'::public.source_analysis_kind
     OR run_row.analysis_state <> 'validated'::public.source_analysis_provenance_state THEN
    RAISE EXCEPTION 'source field candidate materialization requires a validated AI extraction run';
  END IF;

  SELECT * INTO existing_row
  FROM public.source_field_candidates
  WHERE source_analysis_run_id = p_source_analysis_run_id
    AND semantic_candidate_key = p_semantic_candidate_key
  FOR KEY SHARE;
  IF existing_row.id IS NOT NULL THEN
    IF existing_row.field_path IS DISTINCT FROM p_field_path
       OR existing_row.value_type IS DISTINCT FROM p_value_type
       OR existing_row.normalized_value IS DISTINCT FROM p_normalized_value
       OR existing_row.asset_id IS DISTINCT FROM run_row.asset_id
       OR existing_row.page_number IS DISTINCT FROM p_page_number
       OR existing_row.quotation IS DISTINCT FROM p_quotation
       OR existing_row.evidence_regions IS DISTINCT FROM p_evidence_regions
       OR existing_row.confidence IS DISTINCT FROM canonical_confidence
       OR existing_row.validation_state IS DISTINCT FROM p_validation_state
       OR existing_row.validation_error_codes IS DISTINCT FROM p_validation_error_codes THEN
      RAISE EXCEPTION 'source field candidate semantic key conflicts with existing materialization';
    END IF;
    RETURN existing_row.id;
  END IF;

  INSERT INTO public.source_field_candidates(
    org_id, source_analysis_run_id, asset_id, semantic_candidate_key, field_path,
    value_type, normalized_value, page_number, quotation, evidence_regions,
    confidence, validation_state, validation_error_codes
  ) VALUES (
    run_row.org_id, run_row.id, run_row.asset_id, p_semantic_candidate_key, p_field_path,
    p_value_type, p_normalized_value, p_page_number, p_quotation, p_evidence_regions,
    canonical_confidence, p_validation_state, p_validation_error_codes
  ) RETURNING id INTO candidate_id;

  RETURN candidate_id;
END $$;

ALTER TABLE public.source_field_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.source_field_candidates FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.source_field_candidates
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.source_field_candidate_normalized_value_is_valid(public.source_field_candidate_value_type, jsonb),
  public.source_field_candidate_regions_are_valid(jsonb),
  public.source_field_candidate_validation_errors_are_safe(text[]),
  public.source_field_candidate_insert_guard(),
  public.source_field_candidate_immutable_guard(),
  public.materialize_source_field_candidate(uuid, text, text, public.source_field_candidate_value_type, jsonb, integer, text, jsonb, numeric, public.source_field_candidate_validation_state, text[])
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.materialize_source_field_candidate(
  uuid, text, text, public.source_field_candidate_value_type, jsonb, integer,
  text, jsonb, numeric, public.source_field_candidate_validation_state, text[]
) TO service_role;

COMMENT ON TABLE public.source_field_candidates IS
  'Immutable, source-run materialized field candidates with bounded typed values and asset/page/quotation evidence. Browser roles have no direct access; service materializes through the command only.';
COMMENT ON FUNCTION public.materialize_source_field_candidate(uuid, text, text, public.source_field_candidate_value_type, jsonb, integer, text, jsonb, numeric, public.source_field_candidate_validation_state, text[]) IS
  'Service-only idempotent source candidate materialization for terminal validated AI runs; no raw provider output is accepted or retained.';

COMMIT;
