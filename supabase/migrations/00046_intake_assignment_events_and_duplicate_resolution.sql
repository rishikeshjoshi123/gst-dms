-- Consumer-safe assignment history and duplicate recovery resolution.
BEGIN;

-- Duplicate receipts retain the authoritative matching asset. Resolve that
-- through all durable version/document lineage after tenant and document-view
-- checks; no storage key or raw receipt is exposed to the browser. A current
-- active document is preferred, but a superseded version remains a duplicate
-- of its current logical document. Trashed matches are intentionally typed
-- without resource identifiers until the dedicated restore boundary exists.
CREATE OR REPLACE FUNCTION public.get_intake_duplicate_resolution(p_intake_id uuid)
RETURNS TABLE(code text, document_id uuid, matter_id uuid)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
 WITH actor AS (
   SELECT org_id FROM public.get_my_organisation_context()
   WHERE state='active' AND 'document.view'=ANY(capabilities)
   LIMIT 1
 ), duplicate_receipt AS (
   SELECT i.org_id,r.duplicate_asset_id
   FROM actor
   JOIN public.intake_items AS i
     ON i.id=p_intake_id AND i.org_id=actor.org_id AND i.state='duplicate'
   JOIN public.document_upload_command_receipts AS r
     ON r.upload_session_id=i.upload_session_id AND r.org_id=i.org_id
    AND r.command='complete' AND r.code='duplicate'
 ), active_match AS (
   SELECT d.id,d.matter_id
   FROM duplicate_receipt AS r
   JOIN public.document_versions AS v
     ON v.asset_id=r.duplicate_asset_id AND v.org_id=r.org_id
    AND v.validation_state='valid' AND v.state IN ('current','superseded')
   JOIN public.documents AS d ON d.id=v.document_id AND d.org_id=r.org_id
   WHERE d.record_state='active' AND d.deleted_at IS NULL
   ORDER BY (d.current_version_id=v.id) DESC, v.created_at DESC, d.created_at DESC
   LIMIT 1
 ), trashed_match AS (
   SELECT 1
   FROM duplicate_receipt AS r
   JOIN public.document_versions AS v
     ON v.asset_id=r.duplicate_asset_id AND v.org_id=r.org_id
    AND v.validation_state='valid' AND v.state IN ('current','superseded')
   JOIN public.documents AS d ON d.id=v.document_id AND d.org_id=r.org_id
   WHERE NOT (d.record_state='active' AND d.deleted_at IS NULL)
   LIMIT 1
 )
 SELECT CASE
          WHEN active_match.id IS NOT NULL THEN 'ok'
          WHEN EXISTS (SELECT 1 FROM trashed_match) THEN 'in_trash'
          ELSE 'not_available'
        END,
        active_match.id,
        active_match.matter_id
 FROM (SELECT 1) AS result
 LEFT JOIN active_match ON true;
$$;
REVOKE ALL ON FUNCTION public.get_intake_duplicate_resolution(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_intake_duplicate_resolution(uuid) TO authenticated;
COMMIT;
