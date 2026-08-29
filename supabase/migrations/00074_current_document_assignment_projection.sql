-- Bounded, service-only assignment input. Assignment is intentionally a
-- consumer of current effective metadata, never of a model payload or the
-- transitional documents.raw_metadata compatibility copy.
BEGIN;

CREATE FUNCTION public.read_current_document_assignment_projection(
  p_org_id uuid,
  p_document_ids uuid[]
)
RETURNS TABLE (
  document_id uuid,
  document_version_id uuid,
  gstin text,
  client_identifiers text[],
  client_name text,
  financial_years text[],
  reference_number text,
  referenced_document_numbers text[]
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT
    document.id,
    version.id,
    CASE
      WHEN effective.gstin_rows = 1
        AND coalesce(cardinality(effective.gstin_values), 0) = 1
        THEN effective.gstin_values[1]
      ELSE NULL
    END,
    CASE WHEN effective.client_identifier_rows = 0 THEN ARRAY[]::text[]
      ELSE coalesce(effective.client_identifier_values, ARRAY[]::text[]) END,
    CASE
      WHEN effective.client_name_rows = 1
        AND coalesce(cardinality(effective.client_name_values), 0) = 1
        THEN effective.client_name_values[1]
      ELSE NULL
    END,
    CASE WHEN effective.financial_year_rows = 0 THEN ARRAY[]::text[]
      ELSE coalesce(effective.financial_year_values, ARRAY[]::text[]) END,
    CASE
      WHEN effective.reference_number_rows = 1
        AND coalesce(cardinality(effective.reference_number_values), 0) = 1
        THEN effective.reference_number_values[1]
      ELSE NULL
    END,
    CASE WHEN effective.referenced_document_rows = 0 THEN ARRAY[]::text[]
      ELSE coalesce(effective.referenced_document_values, ARRAY[]::text[]) END
  FROM public.documents AS document
  JOIN public.document_versions AS version
    ON version.org_id = document.org_id
    AND version.id = document.current_version_id
    AND version.document_id = document.id
    AND version.state = 'current'::public.document_version_state
    AND version.validation_state = 'valid'::public.document_version_validation_state
  CROSS JOIN LATERAL (
    SELECT
      count(*) FILTER (WHERE metadata.field_path = 'document.gstin') AS gstin_rows,
      array_agg(metadata.normalized_value #>> '{}') FILTER (
        WHERE metadata.field_path = 'document.gstin'
          AND metadata.normalized_value IS NOT NULL
          AND jsonb_typeof(metadata.normalized_value) = 'string'
      ) AS gstin_values,
      count(*) FILTER (WHERE metadata.field_path = 'document.client_identifier') AS client_identifier_rows,
      array_agg(DISTINCT metadata.normalized_value #>> '{}' ORDER BY metadata.normalized_value #>> '{}') FILTER (
        WHERE metadata.field_path = 'document.client_identifier'
          AND metadata.normalized_value IS NOT NULL
          AND jsonb_typeof(metadata.normalized_value) = 'string'
      ) AS client_identifier_values,
      count(*) FILTER (WHERE metadata.field_path = 'document.client_name') AS client_name_rows,
      array_agg(metadata.normalized_value #>> '{}') FILTER (
        WHERE metadata.field_path = 'document.client_name'
          AND metadata.normalized_value IS NOT NULL
          AND jsonb_typeof(metadata.normalized_value) = 'string'
      ) AS client_name_values,
      count(*) FILTER (WHERE metadata.field_path = 'document.financial_year') AS financial_year_rows,
      array_agg(DISTINCT metadata.normalized_value #>> '{}' ORDER BY metadata.normalized_value #>> '{}') FILTER (
        WHERE metadata.field_path = 'document.financial_year'
          AND metadata.normalized_value IS NOT NULL
          AND jsonb_typeof(metadata.normalized_value) = 'string'
      ) AS financial_year_values,
      count(*) FILTER (WHERE metadata.field_path = 'document.reference_number') AS reference_number_rows,
      array_agg(metadata.normalized_value #>> '{}') FILTER (
        WHERE metadata.field_path = 'document.reference_number'
          AND metadata.normalized_value IS NOT NULL
          AND jsonb_typeof(metadata.normalized_value) = 'string'
      ) AS reference_number_values,
      count(*) FILTER (WHERE metadata.field_path = 'document.referenced_document_number') AS referenced_document_rows,
      array_agg(DISTINCT metadata.normalized_value #>> '{}' ORDER BY metadata.normalized_value #>> '{}') FILTER (
        WHERE metadata.field_path = 'document.referenced_document_number'
          AND metadata.normalized_value IS NOT NULL
          AND jsonb_typeof(metadata.normalized_value) = 'string'
      ) AS referenced_document_values
    FROM public.read_current_document_effective_metadata(p_org_id, ARRAY[document.id]) AS metadata
  ) AS effective
  WHERE document.org_id = p_org_id
    AND document.id = ANY(p_document_ids)
    AND document.deleted_at IS NULL
    AND document.record_state = 'active'::public.document_record_state
$$;

REVOKE ALL ON FUNCTION public.read_current_document_assignment_projection(uuid, uuid[])
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_current_document_assignment_projection(uuid, uuid[])
  TO service_role;

COMMENT ON FUNCTION public.read_current_document_assignment_projection(uuid, uuid[]) IS
  'Service-only current-version assignment projection. Corrected values are returned; cleared, rejected, ambiguous, non-current, invalid, deleted, and cross-tenant values never fall back to documents.raw_metadata.';

COMMIT;
