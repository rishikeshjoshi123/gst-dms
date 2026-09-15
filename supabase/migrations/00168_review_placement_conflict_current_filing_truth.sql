-- Closed placement Reviews preserve their recorded old/target Matter snapshots.
-- Enrich an already authorised typed detail with the live filing separately so
-- a later governed Move cannot make a historical decision read as current.
ALTER FUNCTION public.read_review_detail(uuid) RENAME TO read_review_detail_before_current_filing_truth;

CREATE FUNCTION public.read_review_detail(p_review_item_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE detail jsonb; current_matter_id uuid; current_matter_title text; current_matter_code text;
BEGIN
  detail:=public.read_review_detail_before_current_filing_truth(p_review_item_id);
  IF detail IS NULL OR detail->>'type'<>'placement_conflict' THEN RETURN detail; END IF;
  SELECT m.id,m.title,m.matter_code INTO current_matter_id,current_matter_title,current_matter_code
  FROM public.documents d
  JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id
  JOIN public.clients client ON client.id=m.client_id AND client.org_id=m.org_id
  WHERE d.id=(detail->>'document_id')::uuid AND d.org_id=(detail->>'org_id')::uuid
    AND d.record_state='active' AND d.deleted_at IS NULL
    AND m.record_state='active' AND m.deleted_at IS NULL
    AND client.record_state='active' AND client.deleted_at IS NULL;
  RETURN detail||jsonb_build_object('current_matter_id',current_matter_id,
    'current_matter_title',current_matter_title,'current_matter_code',current_matter_code);
END $$;

REVOKE ALL ON FUNCTION public.read_review_detail_before_current_filing_truth(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.read_review_detail(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.read_review_detail(uuid) TO authenticated;
