BEGIN;

ALTER FUNCTION public.read_review_detail(uuid)
  RENAME TO read_review_detail_before_source_run_projection_normalization;
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC;
ALTER FUNCTION public.read_review_detail_before_source_run_projection_normalization(uuid)
  SET SCHEMA private;

CREATE FUNCTION public.read_review_detail(p_review_item_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE detail jsonb;
BEGIN
  detail:=private.read_review_detail_before_source_run_projection_normalization(p_review_item_id);
  IF detail IS NULL THEN RETURN NULL; END IF;

  -- `review_items` has a nullable source-run column, but only Review types that
  -- own a source run may expose it. Preserve real identifiers and omit an
  -- irrelevant/null key so the typed detail model remains fail-closed.
  IF detail->>'source_analysis_run_id' IS NULL THEN detail:=detail-'source_analysis_run_id'; END IF;
  RETURN detail;
END $$;

REVOKE ALL ON FUNCTION public.read_review_detail(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_review_detail(uuid) TO authenticated;
REVOKE ALL ON FUNCTION private.read_review_detail_before_source_run_projection_normalization(uuid)
  FROM PUBLIC,anon,authenticated,service_role;

COMMIT;
