-- A direct Trigger invocation must not be able to substitute a tenant for a
-- durable processing event. Verify the expected organisation before delegating
-- to the existing fenced claim, then return the database event organisation
-- with the claim for child-task identity and concurrency scoping.
BEGIN;

CREATE FUNCTION public.claim_document_processing_work_for_dispatch(
  p_event_id uuid,
  p_trigger_run_id text,
  p_expected_org_id uuid
) RETURNS TABLE(
  code text,
  org_id uuid,
  processing_run_id uuid,
  document_id uuid,
  document_version_id uuid,
  matter_id uuid,
  actor_id uuid,
  bucket_id text,
  object_key text,
  lease_token uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE event_row public.outbox_events%ROWTYPE;
BEGIN
  IF p_event_id IS NULL OR p_expected_org_id IS NULL THEN
    RETURN QUERY SELECT
      'invalid_request'::text, NULL::uuid, NULL::uuid, NULL::uuid,
      NULL::uuid, NULL::uuid, NULL::uuid, NULL::text, NULL::text, NULL::uuid;
    RETURN;
  END IF;

  SELECT oe.* INTO event_row
  FROM public.outbox_events AS oe
  WHERE oe.id=p_event_id
  FOR UPDATE;

  IF event_row.id IS NULL OR event_row.event_kind<>'document.processing_requested.v1' THEN
    RETURN QUERY SELECT
      'not_found'::text, NULL::uuid, NULL::uuid, NULL::uuid,
      NULL::uuid, NULL::uuid, NULL::uuid, NULL::text, NULL::text, NULL::uuid;
    RETURN;
  END IF;

  IF event_row.org_id IS DISTINCT FROM p_expected_org_id THEN
    -- Do not claim or mutate the processing run on a forged task payload.
    RETURN QUERY SELECT
      'organisation_mismatch'::text, event_row.org_id, NULL::uuid, NULL::uuid,
      NULL::uuid, NULL::uuid, NULL::uuid, NULL::text, NULL::text, NULL::uuid;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    claimed.code,
    event_row.org_id,
    claimed.processing_run_id,
    claimed.document_id,
    claimed.document_version_id,
    claimed.matter_id,
    claimed.actor_id,
    claimed.bucket_id,
    claimed.object_key,
    claimed.lease_token
  FROM public.claim_document_processing_work(p_event_id,p_trigger_run_id) AS claimed;
END $$;

REVOKE ALL ON FUNCTION public.claim_document_processing_work_for_dispatch(uuid,text,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_document_processing_work_for_dispatch(uuid,text,uuid)
  TO service_role;

COMMIT;
