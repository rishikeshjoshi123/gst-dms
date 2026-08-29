-- Read-only, service-owned access to the current-version effective metadata
-- projection. Consumers must not query the secured projection table directly
-- or fall back to arbitrary document JSON paths.
BEGIN;

CREATE FUNCTION public.read_current_document_effective_metadata(
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
  WHERE effective.org_id = p_org_id
    AND effective.document_id = ANY(p_document_ids)
    AND document.deleted_at IS NULL
    AND document.record_state = 'active'::public.document_record_state
$$;

REVOKE ALL ON FUNCTION public.read_current_document_effective_metadata(uuid, uuid[])
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_current_document_effective_metadata(uuid, uuid[])
  TO service_role;

COMMENT ON FUNCTION public.read_current_document_effective_metadata(uuid, uuid[]) IS
  'Service-only current-version effective metadata reader for bounded document sets. Direct projection-table reads and arbitrary raw metadata paths remain forbidden.';

COMMIT;
