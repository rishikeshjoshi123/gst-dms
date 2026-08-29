-- Bounded, service-only relationship inputs. Re-evaluation consumes the
-- current valid effective projection and never revives documents.raw_metadata.
BEGIN;

CREATE FUNCTION public.read_current_matter_relationship_projection(
  p_org_id uuid,
  p_matter_id uuid
)
RETURNS TABLE (
  document_id uuid,
  document_version_id uuid,
  doc_type text,
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
    CASE WHEN effective.type_rows = 1 AND cardinality(effective.type_values) = 1
      THEN effective.type_values[1] ELSE NULL END,
    CASE WHEN effective.reference_rows = 1 AND cardinality(effective.reference_values) = 1
      THEN effective.reference_values[1] ELSE NULL END,
    coalesce(effective.referenced_values, ARRAY[]::text[])
  FROM public.documents AS document
  JOIN public.document_versions AS version
    ON version.org_id = document.org_id
    AND version.id = document.current_version_id
    AND version.document_id = document.id
    AND version.state = 'current'::public.document_version_state
    AND version.validation_state = 'valid'::public.document_version_validation_state
  CROSS JOIN LATERAL (
    SELECT
      count(*) FILTER (WHERE metadata.field_path = 'document.type') AS type_rows,
      array_agg(metadata.normalized_value #>> '{}') FILTER (
        WHERE metadata.field_path = 'document.type'
          AND jsonb_typeof(metadata.normalized_value) = 'string'
      ) AS type_values,
      count(*) FILTER (WHERE metadata.field_path = 'document.reference_number') AS reference_rows,
      array_agg(metadata.normalized_value #>> '{}') FILTER (
        WHERE metadata.field_path = 'document.reference_number'
          AND jsonb_typeof(metadata.normalized_value) = 'string'
      ) AS reference_values,
      array_agg(DISTINCT metadata.normalized_value #>> '{}' ORDER BY metadata.normalized_value #>> '{}') FILTER (
        WHERE metadata.field_path = 'document.referenced_document_number'
          AND jsonb_typeof(metadata.normalized_value) = 'string'
      ) AS referenced_values
    FROM public.read_current_document_effective_metadata(p_org_id, ARRAY[document.id]) AS metadata
  ) AS effective
  WHERE document.org_id = p_org_id
    AND document.matter_id = p_matter_id
    AND document.deleted_at IS NULL
    AND document.record_state = 'active'::public.document_record_state
$$;

CREATE FUNCTION public.fuzzy_match_current_matter_relationship_reference(
  p_org_id uuid,
  p_matter_id uuid,
  p_reference_number text
)
RETURNS TABLE (document_id uuid, doc_type text, reference_number text, sim_score real)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT relationship.document_id, relationship.doc_type, relationship.reference_number,
    similarity(relationship.reference_number, p_reference_number)::real
  FROM public.read_current_matter_relationship_projection(p_org_id, p_matter_id) AS relationship
  WHERE relationship.reference_number IS NOT NULL
    AND similarity(relationship.reference_number, p_reference_number) > 0.6
  ORDER BY similarity(relationship.reference_number, p_reference_number) DESC
  LIMIT 1
$$;

CREATE FUNCTION public.current_relationship_reference_exists_in_other_matter(
  p_org_id uuid,
  p_matter_id uuid,
  p_reference_number text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.documents AS document
    JOIN public.document_versions AS version
      ON version.org_id = document.org_id
      AND version.id = document.current_version_id
      AND version.document_id = document.id
      AND version.state = 'current'::public.document_version_state
      AND version.validation_state = 'valid'::public.document_version_validation_state
    CROSS JOIN LATERAL (
      SELECT count(*) AS rows,
        array_agg(metadata.normalized_value #>> '{}') FILTER (
          WHERE jsonb_typeof(metadata.normalized_value) = 'string'
        ) AS values
      FROM public.read_current_document_effective_metadata(p_org_id, ARRAY[document.id]) AS metadata
      WHERE metadata.field_path = 'document.reference_number'
    ) AS reference
    WHERE document.org_id = p_org_id
      AND document.matter_id <> p_matter_id
      AND document.deleted_at IS NULL
      AND document.record_state = 'active'::public.document_record_state
      AND reference.rows = 1
      AND cardinality(reference.values) = 1
      AND reference.values[1] = p_reference_number
  )
$$;

REVOKE ALL ON FUNCTION public.read_current_matter_relationship_projection(uuid, uuid),
  public.fuzzy_match_current_matter_relationship_reference(uuid, uuid, text),
  public.current_relationship_reference_exists_in_other_matter(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_current_matter_relationship_projection(uuid, uuid),
  public.fuzzy_match_current_matter_relationship_reference(uuid, uuid, text),
  public.current_relationship_reference_exists_in_other_matter(uuid, uuid, text)
  TO service_role;

COMMENT ON FUNCTION public.read_current_matter_relationship_projection(uuid, uuid) IS
  'Service-only current valid effective relationship projection for an authorised matter. Cleared, rejected, ambiguous, stale, deleted, inactive, invalid, and cross-tenant values do not fall back.';

COMMIT;
