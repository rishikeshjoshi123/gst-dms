BEGIN;

-- The output-column names declared by RETURNS TABLE are PL/pgSQL variables.
-- Qualify the leased relation explicitly so claiming terminal assets does not
-- resolve bucket_id/object_key ambiguously at runtime.
CREATE OR REPLACE FUNCTION public.claim_document_asset_storage_deletion_work(p_batch_size integer DEFAULT 100)
RETURNS TABLE(asset_id uuid, bucket_id text, object_key text, lease_token uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  IF p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'invalid batch size';
  END IF;
  RETURN QUERY
  WITH candidates AS (
    SELECT fa.id
    FROM public.file_assets AS fa
    WHERE fa.storage_deleted_at IS NULL
      AND fa.availability IN ('failed','expired','quarantined')
      AND NOT EXISTS (SELECT 1 FROM public.document_versions AS dv WHERE dv.asset_id=fa.id)
      AND (fa.storage_deletion_lease_expires_at IS NULL OR fa.storage_deletion_lease_expires_at<=now())
    ORDER BY fa.created_at
    FOR UPDATE SKIP LOCKED
    LIMIT p_batch_size
  ), leased AS (
    UPDATE public.file_assets AS fa
    SET storage_delete_attempted_at=now(), storage_deletion_lease_token=gen_random_uuid(),
        storage_deletion_lease_expires_at=now()+interval '10 minutes', storage_delete_failure_code=NULL
    FROM candidates AS c
    WHERE fa.id=c.id
    RETURNING fa.id,fa.bucket_id,fa.object_key,fa.storage_deletion_lease_token
  )
  SELECT l.id AS asset_id, l.bucket_id AS bucket_id, l.object_key AS object_key,
         l.storage_deletion_lease_token AS lease_token
  FROM leased AS l;
END $$;

COMMIT;
