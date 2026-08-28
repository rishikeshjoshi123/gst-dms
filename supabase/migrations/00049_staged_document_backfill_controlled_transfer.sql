-- Controlled, service-only transfer of already verified legacy staging bytes.
--
-- This is deliberately an expand-only tranche. It neither changes the legacy
-- source row/object nor retires the compatibility adapter. A worker must hold
-- a fresh transfer lease, re-read the trusted source, copy without upsert, and
-- independently re-read the destination before this migration will materialise
-- an ordinary canonical Intake item.
BEGIN;

ALTER TABLE public.staged_document_backfill_items
  ADD COLUMN transfer_attempt_count integer NOT NULL DEFAULT 0
    CHECK (transfer_attempt_count >= 0),
  ADD COLUMN transfer_lease_token uuid,
  ADD COLUMN transfer_lease_expires_at timestamptz,
  ADD COLUMN transfer_completed_at timestamptz,
  ADD CONSTRAINT staged_document_backfill_items_transfer_lease_consistent
    CHECK (
      (transfer_lease_token IS NULL AND transfer_lease_expires_at IS NULL)
      OR (transfer_lease_token IS NOT NULL AND transfer_lease_expires_at IS NOT NULL)
    );

ALTER TABLE public.staged_document_backfill_items
  DROP CONSTRAINT staged_document_backfill_items_outcome_consistent;
ALTER TABLE public.staged_document_backfill_items
  ADD CONSTRAINT staged_document_backfill_items_outcome_consistent
  CHECK (
    (outcome = 'verification_required'
      AND canonical_asset_id IS NULL AND canonical_intake_item_id IS NULL AND duplicate_asset_id IS NULL
      AND transfer_completed_at IS NULL AND terminal_classified_at IS NULL)
    OR (outcome = 'transfer_pending'
      AND canonical_asset_id IS NOT NULL AND duplicate_asset_id IS NULL
      AND observed_sha256 IS NOT NULL AND observed_byte_size IS NOT NULL
      AND terminal_classified_at IS NOT NULL
      AND (
        (canonical_intake_item_id IS NULL AND transfer_completed_at IS NULL)
        OR (canonical_intake_item_id IS NOT NULL AND transfer_completed_at IS NOT NULL)
      ))
    OR (outcome = 'duplicate_reference'
      AND canonical_asset_id IS NULL AND canonical_intake_item_id IS NULL AND duplicate_asset_id IS NOT NULL
      AND transfer_completed_at IS NULL AND terminal_classified_at IS NOT NULL)
    OR (outcome IN ('missing_object', 'unreadable_source', 'malformed_pdf', 'encrypted_pdf', 'non_pdf', 'oversize', 'invalid_lineage', 'already_migrated')
      AND canonical_asset_id IS NULL AND canonical_intake_item_id IS NULL AND duplicate_asset_id IS NULL
      AND transfer_completed_at IS NULL AND terminal_classified_at IS NOT NULL)
  );
CREATE INDEX staged_document_backfill_items_transfer_claim_idx
  ON public.staged_document_backfill_items (org_id, transfer_lease_expires_at, created_at)
  WHERE outcome = 'transfer_pending' AND transfer_completed_at IS NULL;

-- Return only an opaque source identifier and a new lease. The source and
-- destination keys are released separately and only while this lease is held.
CREATE OR REPLACE FUNCTION public.claim_staged_document_backfill_transfer_batch(
  p_org_id uuid,
  p_batch_size integer DEFAULT 10
)
RETURNS TABLE(code text, legacy_staged_document_id uuid, transfer_lease_token uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE candidate record; next_token uuid;
BEGIN
  IF p_org_id IS NULL OR p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 25 THEN
    RAISE EXCEPTION 'invalid staged-document backfill transfer batch request';
  END IF;

  FOR candidate IN
    SELECT m.id AS map_id, m.legacy_staged_document_id
    FROM public.staged_document_backfill_items AS m
    JOIN public.staged_documents AS s
      ON s.org_id = m.org_id AND s.id = m.legacy_staged_document_id
    JOIN public.file_assets AS asset
      ON asset.org_id = m.org_id AND asset.id = m.canonical_asset_id
    WHERE m.org_id = p_org_id
      AND m.outcome = 'transfer_pending'
      AND m.transfer_completed_at IS NULL
      AND (m.transfer_lease_expires_at IS NULL OR m.transfer_lease_expires_at <= now())
      AND asset.legacy_staged_backfill_pending
      AND asset.availability = 'quarantined'
      AND asset.storage_deleted_at IS NULL
    ORDER BY m.created_at, m.id
    FOR UPDATE OF m, s, asset SKIP LOCKED
    LIMIT p_batch_size
  LOOP
    -- Re-check the legacy lineage under the same lock used for the lease.
    IF NOT public.staged_document_backfill_source_is_valid(
      p_org_id,
      (SELECT s.storage_path FROM public.staged_documents AS s
       WHERE s.org_id = p_org_id AND s.id = candidate.legacy_staged_document_id),
      (SELECT s.intake_matter_id FROM public.staged_documents AS s
       WHERE s.org_id = p_org_id AND s.id = candidate.legacy_staged_document_id)
    ) THEN
      CONTINUE;
    END IF;
    next_token := gen_random_uuid();
    UPDATE public.staged_document_backfill_items
    SET transfer_attempt_count = transfer_attempt_count + 1,
        transfer_lease_token = next_token,
        transfer_lease_expires_at = now() + interval '15 minutes'
    WHERE id = candidate.map_id;
    RETURN QUERY SELECT 'transfer_pending'::text, candidate.legacy_staged_document_id, next_token;
  END LOOP;
END $$;

-- The source comes only from this fresh, lease-bound database grant. The
-- canonical target is read from its existing immutable asset record rather
-- than derived from task input. Expected observations are worker-only facts
-- used to reject an altered source or destination before finalisation.
CREATE OR REPLACE FUNCTION public.get_staged_document_backfill_transfer_grant(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_transfer_lease_token uuid
)
RETURNS TABLE(
  code text,
  source_bucket_id text,
  source_object_key text,
  destination_bucket_id text,
  destination_object_key text,
  expected_byte_size bigint,
  expected_sha256 text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT CASE
           WHEN m.id IS NULL OR s.id IS NULL THEN 'not_found'
           WHEN m.outcome <> 'transfer_pending' THEN m.outcome::text
           WHEN asset.id IS NULL THEN 'not_found'
           WHEN m.transfer_completed_at IS NOT NULL THEN 'already_transferred'
           WHEN m.transfer_lease_token IS DISTINCT FROM p_transfer_lease_token
             OR m.transfer_lease_expires_at IS NULL OR m.transfer_lease_expires_at <= now() THEN 'lease_not_held'
           WHEN NOT asset.legacy_staged_backfill_pending OR asset.availability <> 'quarantined'
             OR asset.storage_deleted_at IS NOT NULL THEN 'destination_not_pending'
           WHEN NOT public.staged_document_backfill_source_is_valid(s.org_id, s.storage_path, s.intake_matter_id) THEN 'invalid_lineage'
           ELSE 'ok'
         END,
         CASE WHEN m.transfer_lease_token = p_transfer_lease_token
                    AND m.transfer_lease_expires_at > now()
                    AND m.transfer_completed_at IS NULL
                    AND public.staged_document_backfill_source_is_valid(s.org_id, s.storage_path, s.intake_matter_id)
              THEN 'staging' END,
         CASE WHEN m.transfer_lease_token = p_transfer_lease_token
                    AND m.transfer_lease_expires_at > now()
                    AND m.transfer_completed_at IS NULL
                    AND public.staged_document_backfill_source_is_valid(s.org_id, s.storage_path, s.intake_matter_id)
              THEN s.storage_path END,
         CASE WHEN m.transfer_lease_token = p_transfer_lease_token
                    AND m.transfer_lease_expires_at > now()
                    AND m.transfer_completed_at IS NULL
                    AND asset.legacy_staged_backfill_pending
                    AND asset.availability = 'quarantined'
                    AND asset.storage_deleted_at IS NULL
              THEN asset.bucket_id END,
         CASE WHEN m.transfer_lease_token = p_transfer_lease_token
                    AND m.transfer_lease_expires_at > now()
                    AND m.transfer_completed_at IS NULL
                    AND asset.legacy_staged_backfill_pending
                    AND asset.availability = 'quarantined'
                    AND asset.storage_deleted_at IS NULL
              THEN asset.object_key END,
         CASE WHEN m.transfer_lease_token = p_transfer_lease_token
                    AND m.transfer_lease_expires_at > now()
                    AND m.transfer_completed_at IS NULL
              THEN m.observed_byte_size END,
         CASE WHEN m.transfer_lease_token = p_transfer_lease_token
                    AND m.transfer_lease_expires_at > now()
                    AND m.transfer_completed_at IS NULL
              THEN m.observed_sha256 END
  FROM public.staged_document_backfill_items AS m
  LEFT JOIN public.staged_documents AS s
    ON s.org_id = m.org_id AND s.id = m.legacy_staged_document_id
  LEFT JOIN public.file_assets AS asset
    ON asset.org_id = m.org_id AND asset.id = m.canonical_asset_id
  WHERE m.org_id = p_org_id AND m.legacy_staged_document_id = p_legacy_staged_document_id;
$$;

-- Finalisation trusts only a worker that has independently read both source
-- and destination through the fresh grant. It re-checks every prior source
-- observation before atomically making the asset available and creating ready
-- Intake. No legacy row or staging object is changed here.
CREATE OR REPLACE FUNCTION public.complete_staged_document_backfill_transfer(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_transfer_lease_token uuid,
  p_source_observed_bytes bigint,
  p_source_sha256 text,
  p_source_page_count integer,
  p_destination_observed_bytes bigint,
  p_destination_sha256 text
)
RETURNS TABLE(code text, asset_id uuid, intake_item_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE map_row public.staged_document_backfill_items%ROWTYPE;
  source_row public.staged_documents%ROWTYPE;
  asset_row public.file_assets%ROWTYPE;
  duplicate_asset uuid;
  intake_id uuid;
BEGIN
  IF p_org_id IS NULL OR p_legacy_staged_document_id IS NULL OR p_transfer_lease_token IS NULL
     OR p_source_observed_bytes IS NULL OR p_destination_observed_bytes IS NULL
     OR p_source_observed_bytes <= 0 OR p_destination_observed_bytes <= 0
     OR p_source_page_count IS NULL OR p_source_page_count <= 0
     OR p_source_sha256 IS NULL OR p_destination_sha256 IS NULL
     OR p_source_sha256 !~ '^[0-9a-f]{64}$' OR p_destination_sha256 !~ '^[0-9a-f]{64}$' THEN
    RETURN QUERY SELECT 'invalid_observation'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;

  SELECT * INTO map_row
  FROM public.staged_document_backfill_items AS m
  WHERE m.org_id = p_org_id AND m.legacy_staged_document_id = p_legacy_staged_document_id
  FOR UPDATE;
  IF map_row.id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;
  IF map_row.outcome <> 'transfer_pending' THEN
    RETURN QUERY SELECT map_row.outcome::text,
      CASE WHEN map_row.outcome = 'duplicate_reference' THEN map_row.duplicate_asset_id ELSE NULL::uuid END,
      NULL::uuid;
    RETURN;
  END IF;
  IF map_row.transfer_completed_at IS NOT NULL THEN
    RETURN QUERY SELECT 'already_transferred'::text, map_row.canonical_asset_id, map_row.canonical_intake_item_id;
    RETURN;
  END IF;
  IF map_row.transfer_lease_token IS DISTINCT FROM p_transfer_lease_token
     OR map_row.transfer_lease_expires_at IS NULL OR map_row.transfer_lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'lease_not_held'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;

  SELECT * INTO source_row
  FROM public.staged_documents AS s
  WHERE s.org_id = p_org_id AND s.id = p_legacy_staged_document_id
  FOR UPDATE;
  SELECT * INTO asset_row
  FROM public.file_assets AS asset
  WHERE asset.org_id = p_org_id AND asset.id = map_row.canonical_asset_id
  FOR UPDATE;
  IF source_row.id IS NULL OR asset_row.id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;
  IF NOT public.staged_document_backfill_source_is_valid(source_row.org_id, source_row.storage_path, source_row.intake_matter_id) THEN
    RETURN QUERY SELECT 'invalid_lineage'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;
  IF NOT asset_row.legacy_staged_backfill_pending OR asset_row.availability <> 'quarantined'
     OR asset_row.storage_deleted_at IS NOT NULL THEN
    RETURN QUERY SELECT 'destination_not_pending'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;
  IF p_source_observed_bytes <> map_row.observed_byte_size
     OR p_source_sha256 <> map_row.observed_sha256 THEN
    RETURN QUERY SELECT 'source_observation_conflict'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;
  IF p_destination_observed_bytes <> map_row.observed_byte_size
     OR p_destination_sha256 <> map_row.observed_sha256
     OR p_destination_observed_bytes <> p_source_observed_bytes
     OR p_destination_sha256 <> p_source_sha256 THEN
    RETURN QUERY SELECT 'destination_observation_conflict'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;

  -- Match the upload command's per-tenant hash lock. A new upload may have
  -- completed after the verification tranche; do not turn that race into a
  -- unique-index exception or overwrite. A detected duplicate becomes the
  -- existing terminal duplicate_reference mapping outcome below.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(p_org_id::text), pg_catalog.hashtext(map_row.observed_sha256)
  );
  SELECT asset.id INTO duplicate_asset
  FROM public.file_assets AS asset
  WHERE asset.org_id = p_org_id
    AND asset.id <> asset_row.id
    AND asset.sha256 = map_row.observed_sha256
  ORDER BY EXISTS (SELECT 1 FROM public.document_versions AS version WHERE version.asset_id = asset.id) DESC,
           asset.created_at
  LIMIT 1;
  IF duplicate_asset IS NOT NULL THEN
    UPDATE public.staged_document_backfill_items
    SET outcome = 'duplicate_reference',
        canonical_asset_id = NULL,
        canonical_intake_item_id = NULL,
        duplicate_asset_id = duplicate_asset,
        safe_reason_code = 'duplicate_asset_reference',
        transfer_lease_token = NULL,
        transfer_lease_expires_at = NULL
    WHERE id = map_row.id;
    RETURN QUERY SELECT 'duplicate_reference'::text, duplicate_asset, NULL::uuid;
    RETURN;
  END IF;

  INSERT INTO public.intake_items (
    org_id, asset_id, intended_matter_id, state, uploaded_by, updated_at
  ) VALUES (
    p_org_id, asset_row.id, source_row.intake_matter_id, 'ready', source_row.uploaded_by, now()
  ) RETURNING id INTO intake_id;

  UPDATE public.file_assets
  SET sha256 = map_row.observed_sha256,
      byte_size = map_row.observed_byte_size,
      detected_mime_type = 'application/pdf',
      availability = 'available',
      validated_at = now(),
      validated_page_count = p_source_page_count,
      failure_code = NULL,
      legacy_staged_backfill_pending = false
  WHERE id = asset_row.id;
  UPDATE public.staged_document_backfill_items
  SET canonical_intake_item_id = intake_id,
      transfer_completed_at = now(),
      transfer_lease_token = NULL,
      transfer_lease_expires_at = NULL,
      safe_reason_code = 'canonical_transfer_completed'
  WHERE id = map_row.id;

  RETURN QUERY SELECT 'transferred'::text, asset_row.id, intake_id;
END $$;

-- Legacy staging never had a trustworthy user filename. A completed transfer
-- deliberately has no synthetic upload session, so version materialisation
-- accepts only this mapped Intake shape and uses a fixed safe display name.
-- Ordinary session-less Intake still fails closed exactly as before.
CREATE OR REPLACE FUNCTION public.document_materialization_insert_version(
  p_org uuid, p_document uuid, p_intake uuid, p_actor uuid, p_reason text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_intake public.intake_items%ROWTYPE; v_asset public.file_assets%ROWTYPE;
  v_name text; v_number integer; v_version uuid;
BEGIN
  SELECT * INTO v_intake FROM public.intake_items WHERE id=p_intake AND org_id=p_org FOR UPDATE;
  SELECT * INTO v_asset FROM public.file_assets WHERE id=v_intake.asset_id AND org_id=p_org FOR UPDATE;
  IF v_intake.id IS NULL OR v_intake.state<>'ready' OR v_asset.id IS NULL OR v_asset.availability<>'available'
     OR v_asset.detected_mime_type<>'application/pdf' OR v_asset.validated_page_count IS NULL THEN
    RAISE EXCEPTION 'intake is not a ready validated PDF';
  END IF;
  SELECT declared_filename INTO v_name FROM public.upload_sessions
    WHERE id=v_intake.upload_session_id AND org_id=p_org;
  IF v_name IS NULL AND EXISTS (
    SELECT 1 FROM public.staged_document_backfill_items AS map
    WHERE map.org_id=p_org AND map.canonical_intake_item_id=v_intake.id
      AND map.outcome='transfer_pending' AND map.transfer_completed_at IS NOT NULL
  ) THEN
    v_name := 'legacy-staged-document.pdf';
  END IF;
  IF v_name IS NULL THEN RAISE EXCEPTION 'trusted upload filename is unavailable'; END IF;
  SELECT coalesce(max(version_number),0)+1 INTO v_number FROM public.document_versions
    WHERE document_id=p_document;
  INSERT INTO public.document_versions AS document_version (org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,replacement_reason,created_by,validated_at,promoted_at)
  VALUES(p_org,p_document,v_asset.id,v_number,v_name,v_asset.validated_page_count,'valid','current',p_reason,p_actor,now(),now()) RETURNING document_version.id INTO v_version;
  RETURN v_version;
END $$;

CREATE OR REPLACE VIEW public.staged_document_backfill_reports AS
SELECT
  s.org_id,
  count(*)::bigint AS legacy_source_count,
  count(*) FILTER (WHERE s.status IN ('pending_assignment', 'analyzing', 'ready_to_assign', 'failed'))::bigint AS active_source_count,
  count(*) FILTER (WHERE m.id IS NULL)::bigint AS unmapped_source_count,
  count(*) FILTER (WHERE m.outcome = 'verification_required')::bigint AS verification_required_count,
  count(*) FILTER (WHERE m.outcome = 'transfer_pending' AND m.transfer_completed_at IS NULL)::bigint AS transfer_pending_count,
  count(*) FILTER (WHERE m.outcome = 'missing_object')::bigint AS missing_object_count,
  count(*) FILTER (WHERE m.outcome = 'unreadable_source')::bigint AS unreadable_source_count,
  count(*) FILTER (WHERE m.outcome = 'malformed_pdf')::bigint AS malformed_pdf_count,
  count(*) FILTER (WHERE m.outcome = 'encrypted_pdf')::bigint AS encrypted_pdf_count,
  count(*) FILTER (WHERE m.outcome = 'non_pdf')::bigint AS non_pdf_count,
  count(*) FILTER (WHERE m.outcome = 'oversize')::bigint AS oversize_count,
  count(*) FILTER (WHERE m.outcome = 'invalid_lineage')::bigint AS invalid_lineage_count,
  count(*) FILTER (WHERE m.outcome = 'duplicate_reference')::bigint AS duplicate_reference_count,
  count(*) FILTER (WHERE m.outcome = 'already_migrated')::bigint AS already_migrated_count,
  (count(*) FILTER (WHERE m.id IS NULL OR m.outcome = 'verification_required') = 0) AS classification_complete,
  false AS staging_retirement_ready,
  count(*) FILTER (WHERE m.outcome = 'transfer_pending' AND m.transfer_completed_at IS NOT NULL)::bigint AS transfer_completed_count
FROM public.staged_documents AS s
LEFT JOIN public.staged_document_backfill_items AS m
  ON m.org_id = s.org_id AND m.legacy_staged_document_id = s.id
GROUP BY s.org_id;

DROP VIEW public.staged_document_backfill_diagnostics;
CREATE VIEW public.staged_document_backfill_diagnostics AS
SELECT issues.org_id, issues.issue, count(*)::bigint AS affected_count
FROM (
  SELECT m.org_id, 'mapped_asset_not_quarantined'::text AS issue
  FROM public.staged_document_backfill_items AS m
  JOIN public.file_assets AS asset
    ON asset.id = m.canonical_asset_id AND asset.org_id = m.org_id
  WHERE m.outcome = 'transfer_pending'
    AND m.transfer_completed_at IS NULL
    AND (asset.availability <> 'quarantined' OR NOT asset.legacy_staged_backfill_pending)
  UNION ALL
  SELECT m.org_id, 'transfer_pending_has_runnable_intake'::text
  FROM public.staged_document_backfill_items AS m
  WHERE m.outcome = 'transfer_pending'
    AND m.transfer_completed_at IS NULL
    AND m.canonical_intake_item_id IS NOT NULL
  UNION ALL
  SELECT m.org_id, 'transfer_completed_asset_not_available'::text
  FROM public.staged_document_backfill_items AS m
  JOIN public.file_assets AS asset
    ON asset.id = m.canonical_asset_id AND asset.org_id = m.org_id
  JOIN public.intake_items AS intake
    ON intake.id = m.canonical_intake_item_id AND intake.org_id = m.org_id
  WHERE m.outcome = 'transfer_pending'
    AND m.transfer_completed_at IS NOT NULL
    AND (asset.legacy_staged_backfill_pending OR asset.availability <> 'available'
         OR asset.sha256 IS DISTINCT FROM m.observed_sha256
         OR asset.byte_size IS DISTINCT FROM m.observed_byte_size
         OR intake.state <> 'ready')
  UNION ALL
  SELECT m.org_id, 'source_organisation_mismatch'::text
  FROM public.staged_document_backfill_items AS m
  JOIN public.staged_documents AS source
    ON source.id = m.legacy_staged_document_id
  WHERE source.org_id <> m.org_id
) AS issues
GROUP BY issues.org_id, issues.issue;

REVOKE ALL ON FUNCTION public.claim_staged_document_backfill_transfer_batch(uuid, integer),
  public.get_staged_document_backfill_transfer_grant(uuid, uuid, uuid),
  public.complete_staged_document_backfill_transfer(uuid, uuid, uuid, bigint, text, integer, bigint, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_staged_document_backfill_transfer_batch(uuid, integer),
  public.get_staged_document_backfill_transfer_grant(uuid, uuid, uuid),
  public.complete_staged_document_backfill_transfer(uuid, uuid, uuid, bigint, text, integer, bigint, text)
  TO service_role;
REVOKE ALL ON TABLE public.staged_document_backfill_diagnostics FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.staged_document_backfill_diagnostics TO service_role, postgres;

COMMENT ON FUNCTION public.claim_staged_document_backfill_transfer_batch(uuid, integer) IS
  'Service-only bounded claims for transfer_pending staged-document backfill maps. Returns no storage path.';
COMMENT ON FUNCTION public.get_staged_document_backfill_transfer_grant(uuid, uuid, uuid) IS
  'Service-only lease-bound source/destination grant for controlled staged-document transfer.';
COMMENT ON FUNCTION public.complete_staged_document_backfill_transfer(uuid, uuid, uuid, bigint, text, integer, bigint, text) IS
  'Atomically creates ready Intake and clears the staging transfer fence only after worker-proven source/destination equality.';

COMMIT;
