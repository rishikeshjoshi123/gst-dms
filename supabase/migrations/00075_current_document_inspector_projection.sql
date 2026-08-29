-- Service-only current-version projection for the existing document inspector.
-- It carries the winning immutable candidate identity solely so an authorised
-- server action can append a correction through record_document_field_decision.
BEGIN;

CREATE FUNCTION public.read_current_document_inspector_projection(
  p_org_id uuid,
  p_document_ids uuid[]
)
RETURNS TABLE (
  document_id uuid,
  document_version_id uuid,
  document_field_candidate_id uuid,
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
    effective.winning_document_field_candidate_id,
    effective.semantic_candidate_key,
    effective.field_path,
    effective.value_type,
    effective.normalized_value,
    effective.resolution,
    effective.computed_at
  FROM public.document_effective_metadata AS effective
  JOIN public.read_current_document_effective_metadata(p_org_id, p_document_ids) AS current_metadata
    ON current_metadata.document_id = effective.document_id
    AND current_metadata.document_version_id = effective.document_version_id
    AND current_metadata.semantic_candidate_key = effective.semantic_candidate_key
    AND current_metadata.field_path = effective.field_path
  WHERE effective.org_id = p_org_id
$$;

REVOKE ALL ON FUNCTION public.read_current_document_inspector_projection(uuid, uuid[])
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_current_document_inspector_projection(uuid, uuid[])
  TO service_role;

COMMENT ON FUNCTION public.read_current_document_inspector_projection(uuid, uuid[]) IS
  'Service-only current effective metadata plus immutable winning-candidate identity for the document inspector. Browser access and raw-metadata fallback are forbidden.';

COMMIT;
