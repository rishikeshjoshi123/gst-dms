-- Search reindexing has two delivery paths: matter backfill and the fenced
-- event-driven worker. Both consume this one current-version projection so
-- human corrections, clears, and repeated financial years have identical
-- semantics without reading legacy raw metadata.
BEGIN;

CREATE OR REPLACE FUNCTION public.read_current_document_effective_metadata(
  p_org_id uuid,
  p_document_ids uuid[]
)
RETURNS TABLE (
  document_id uuid,
  document_version_id uuid,
  semantic_candidate_key text,
  field_path text,
  value_type public.source_field_candidate_value_type,
  normalized_value jsonb,
  resolution public.document_effective_metadata_resolution,
  computed_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT
    effective.document_id,
    effective.document_version_id,
    effective.semantic_candidate_key,
    effective.field_path,
    effective.value_type,
    effective.normalized_value,
    effective.resolution,
    effective.computed_at
  FROM public.document_effective_metadata AS effective
  JOIN public.documents AS document
    ON document.org_id = effective.org_id
    AND document.id = effective.document_id
    AND document.current_version_id = effective.document_version_id
  JOIN public.document_versions AS version
    ON version.org_id = effective.org_id
    AND version.id = effective.document_version_id
    AND version.document_id = effective.document_id
    AND version.state = 'current'::public.document_version_state
    AND version.validation_state = 'valid'::public.document_version_validation_state
  WHERE effective.org_id = p_org_id
    AND effective.document_id = ANY(p_document_ids)
    AND document.deleted_at IS NULL
    AND document.record_state = 'active'::public.document_record_state
$$;

CREATE FUNCTION public.read_current_document_search_index_projection(
  p_org_id uuid,
  p_document_ids uuid[]
)
RETURNS TABLE (
  document_id uuid,
  doc_type text,
  reference_number text,
  summary text,
  financial_years text[],
  issued_by text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT
    document.id,
    CASE
      WHEN effective.doc_type_rows = 0 THEN document.doc_type
      WHEN effective.doc_type_rows = 1
        AND coalesce(cardinality(effective.doc_type_values), 0) = 1
        THEN effective.doc_type_values[1]
      ELSE NULL
    END,
    CASE
      WHEN effective.reference_number_rows = 0 THEN document.reference_number
      WHEN effective.reference_number_rows = 1
        AND coalesce(cardinality(effective.reference_number_values), 0) = 1
        THEN effective.reference_number_values[1]
      ELSE NULL
    END,
    CASE WHEN char_length(coalesce(document.summary, '')) <= 12000 THEN document.summary ELSE NULL END,
    CASE
      WHEN effective.financial_year_rows = 0 THEN
        CASE WHEN document.financial_year IS NULL THEN ARRAY[]::text[] ELSE ARRAY[document.financial_year] END
      ELSE coalesce(effective.financial_year_values, ARRAY[]::text[])
    END,
    CASE
      WHEN effective.issued_by_rows = 0 THEN document.issued_by
      WHEN effective.issued_by_rows = 1
        AND coalesce(cardinality(effective.issued_by_values), 0) = 1
        THEN effective.issued_by_values[1]
      ELSE NULL
    END
  FROM public.documents AS document
  JOIN public.document_versions AS version
    ON version.org_id = document.org_id
    AND version.id = document.current_version_id
    AND version.document_id = document.id
    AND version.state = 'current'::public.document_version_state
    AND version.validation_state = 'valid'::public.document_version_validation_state
  CROSS JOIN LATERAL (
    SELECT
      count(*) FILTER (WHERE metadata.field_path = 'document.type') AS doc_type_rows,
      array_agg(metadata.normalized_value #>> '{}') FILTER (
        WHERE metadata.field_path = 'document.type'
          AND metadata.normalized_value IS NOT NULL
          AND jsonb_typeof(metadata.normalized_value) = 'string'
      ) AS doc_type_values,
      count(*) FILTER (WHERE metadata.field_path = 'document.reference_number') AS reference_number_rows,
      array_agg(metadata.normalized_value #>> '{}') FILTER (
        WHERE metadata.field_path = 'document.reference_number'
          AND metadata.normalized_value IS NOT NULL
          AND jsonb_typeof(metadata.normalized_value) = 'string'
      ) AS reference_number_values,
      count(*) FILTER (WHERE metadata.field_path = 'document.financial_year') AS financial_year_rows,
      array_agg(DISTINCT metadata.normalized_value #>> '{}' ORDER BY metadata.normalized_value #>> '{}') FILTER (
        WHERE metadata.field_path = 'document.financial_year'
          AND metadata.normalized_value IS NOT NULL
          AND jsonb_typeof(metadata.normalized_value) = 'string'
      ) AS financial_year_values,
      count(*) FILTER (WHERE metadata.field_path = 'document.issued_by') AS issued_by_rows,
      array_agg(metadata.normalized_value #>> '{}') FILTER (
        WHERE metadata.field_path = 'document.issued_by'
          AND metadata.normalized_value IS NOT NULL
          AND jsonb_typeof(metadata.normalized_value) = 'string'
      ) AS issued_by_values
    FROM public.read_current_document_effective_metadata(p_org_id, ARRAY[document.id]) AS metadata
  ) AS effective
  WHERE document.org_id = p_org_id
    AND document.id = ANY(p_document_ids)
    AND document.deleted_at IS NULL
    AND document.record_state = 'active'::public.document_record_state
$$;

ALTER FUNCTION public.get_document_search_index_reprocess_input(uuid, uuid)
  RENAME TO get_document_search_index_reprocess_input_legacy_typed;
REVOKE ALL ON FUNCTION public.get_document_search_index_reprocess_input_legacy_typed(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.get_document_search_index_reprocess_input(
  p_processing_run_id uuid,
  p_lease_token uuid
)
RETURNS TABLE(
  code text,
  doc_type text,
  reference_number text,
  summary text,
  financial_years text[],
  issued_by text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  run_row public.document_processing_runs%ROWTYPE;
  document_row public.documents%ROWTYPE;
  version_row public.document_versions%ROWTYPE;
  projection_row record;
BEGIN
  IF p_processing_run_id IS NULL OR p_lease_token IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::text, NULL::text, NULL::text, NULL::text[], NULL::text;
    RETURN;
  END IF;
  SELECT * INTO run_row
  FROM public.document_processing_runs AS run
  WHERE run.id = p_processing_run_id
  FOR KEY SHARE;
  IF run_row.id IS NULL OR run_row.scope <> 'search_index'::public.document_processing_scope THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::text, NULL::text, NULL::text, NULL::text[], NULL::text;
    RETURN;
  END IF;
  IF run_row.state <> 'running'::public.document_processing_state
     OR run_row.lease_token IS DISTINCT FROM p_lease_token
     OR run_row.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'stale_lease'::text, NULL::text, NULL::text, NULL::text, NULL::text[], NULL::text;
    RETURN;
  END IF;
  SELECT * INTO document_row
  FROM public.documents AS document
  WHERE document.id = run_row.document_id
    AND document.org_id = run_row.org_id
  FOR KEY SHARE;
  SELECT * INTO version_row
  FROM public.document_versions AS version
  WHERE version.id = run_row.document_version_id
    AND version.org_id = run_row.org_id
    AND version.document_id = run_row.document_id
  FOR KEY SHARE;
  IF document_row.id IS NULL OR version_row.id IS NULL
     OR document_row.current_version_id IS DISTINCT FROM version_row.id
     OR document_row.record_state <> 'active'::public.document_record_state
     OR document_row.deleted_at IS NOT NULL
     OR version_row.state <> 'current'::public.document_version_state
     OR version_row.validation_state <> 'valid'::public.document_version_validation_state THEN
    RETURN QUERY SELECT 'version_not_current'::text, NULL::text, NULL::text, NULL::text, NULL::text[], NULL::text;
    RETURN;
  END IF;
  SELECT * INTO projection_row
  FROM public.read_current_document_search_index_projection(
    run_row.org_id,
    ARRAY[run_row.document_id]
  );
  IF projection_row.document_id IS NULL THEN
    RETURN QUERY SELECT 'version_not_current'::text, NULL::text, NULL::text, NULL::text, NULL::text[], NULL::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT
    'ready'::text,
    projection_row.doc_type,
    projection_row.reference_number,
    projection_row.summary,
    projection_row.financial_years,
    projection_row.issued_by;
END $$;

REVOKE ALL ON FUNCTION public.read_current_document_search_index_projection(uuid, uuid[])
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_document_search_index_reprocess_input(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_current_document_search_index_projection(uuid, uuid[])
  TO service_role;
GRANT EXECUTE ON FUNCTION public.get_document_search_index_reprocess_input(uuid, uuid)
  TO service_role;

COMMENT ON FUNCTION public.read_current_document_search_index_projection(uuid, uuid[]) IS
  'Service-only scalar Search projection for active current valid document versions. Effective rows suppress legacy scalar fallback when a decision clears or rejects them, and preserve all effective financial years.';
COMMENT ON FUNCTION public.get_document_search_index_reprocess_input(uuid, uuid) IS
  'Service-only fenced Search reprocess input from the shared current effective Search projection.';

COMMIT;
