-- Service-only, non-destructive retirement evidence for legacy staging.
--
-- This tranche deliberately records only proof state and aggregate-safe
-- diagnostics. It never deletes or changes a legacy staged row/object, does
-- not release compatibility fences, and does not authorise retention or
-- consumer cut-over.
BEGIN;

CREATE TYPE public.staged_document_retirement_audit_outcome AS ENUM (
  'verified_equal',
  'source_missing',
  'destination_missing',
  'source_observation_conflict',
  'destination_observation_conflict'
);

CREATE TABLE public.staged_document_retirement_audit_items (
  org_id uuid NOT NULL,
  legacy_staged_document_id uuid NOT NULL,
  outcome public.staged_document_retirement_audit_outcome,
  lease_token uuid,
  lease_expires_at timestamptz,
  audited_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (org_id, legacy_staged_document_id),
  CONSTRAINT staged_document_retirement_audit_items_map_fkey
    FOREIGN KEY (org_id, legacy_staged_document_id)
    REFERENCES public.staged_document_backfill_items(org_id, legacy_staged_document_id)
    ON DELETE RESTRICT,
  CONSTRAINT staged_document_retirement_audit_items_lease_consistent
    CHECK (
      (lease_token IS NULL AND lease_expires_at IS NULL)
      OR (lease_token IS NOT NULL AND lease_expires_at IS NOT NULL)
    ),
  CONSTRAINT staged_document_retirement_audit_items_result_consistent
    CHECK (
      (outcome IS NULL AND audited_at IS NULL)
      OR (outcome IS NOT NULL AND audited_at IS NOT NULL)
    )
);
CREATE INDEX staged_document_retirement_audit_claim_idx
  ON public.staged_document_retirement_audit_items (org_id, lease_expires_at)
  WHERE outcome IS NULL;

CREATE OR REPLACE FUNCTION public.staged_document_retirement_audit_touch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;
CREATE TRIGGER staged_document_retirement_audit_items_touch
  BEFORE UPDATE ON public.staged_document_retirement_audit_items
  FOR EACH ROW EXECUTE FUNCTION public.staged_document_retirement_audit_touch();

-- Claim only completed transfers that have no audit conclusion. The caller
-- gets an opaque legacy identifier; it cannot supply a path or an asset id.
CREATE OR REPLACE FUNCTION public.claim_staged_document_retirement_audit_batch(
  p_org_id uuid,
  p_batch_size integer DEFAULT 10
)
RETURNS TABLE(code text, legacy_staged_document_id uuid, audit_lease_token uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE candidate record; next_token uuid;
BEGIN
  IF p_org_id IS NULL OR p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 25 THEN
    RAISE EXCEPTION 'invalid staged-document retirement audit batch request';
  END IF;

  FOR candidate IN
    SELECT m.legacy_staged_document_id
    FROM public.staged_document_backfill_items AS m
    JOIN public.staged_documents AS source
      ON source.org_id = m.org_id AND source.id = m.legacy_staged_document_id
    JOIN public.file_assets AS asset
      ON asset.org_id = m.org_id AND asset.id = m.canonical_asset_id
    JOIN public.intake_items AS intake
      ON intake.org_id = m.org_id AND intake.id = m.canonical_intake_item_id
    LEFT JOIN public.staged_document_retirement_audit_items AS audit
      ON audit.org_id = m.org_id AND audit.legacy_staged_document_id = m.legacy_staged_document_id
    WHERE m.org_id = p_org_id
      AND m.outcome = 'transfer_pending'
      AND m.transfer_completed_at IS NOT NULL
      AND audit.outcome IS NULL
      AND (audit.lease_expires_at IS NULL OR audit.lease_expires_at <= now())
      AND asset.availability = 'available'
      AND NOT asset.legacy_staged_backfill_pending
      AND asset.storage_deleted_at IS NULL
      AND intake.state = 'ready'
      AND intake.asset_id = m.canonical_asset_id
      AND public.staged_document_backfill_source_is_valid(source.org_id, source.storage_path, source.intake_matter_id)
    ORDER BY m.transfer_completed_at, m.legacy_staged_document_id
    FOR UPDATE OF m, source, asset, intake SKIP LOCKED
    LIMIT p_batch_size
  LOOP
    next_token := gen_random_uuid();
    INSERT INTO public.staged_document_retirement_audit_items (
      org_id, legacy_staged_document_id, lease_token, lease_expires_at
    ) VALUES (
      p_org_id, candidate.legacy_staged_document_id, next_token, now() + interval '15 minutes'
    )
    ON CONFLICT ON CONSTRAINT staged_document_retirement_audit_items_pkey DO UPDATE
      SET lease_token = EXCLUDED.lease_token, lease_expires_at = EXCLUDED.lease_expires_at
      WHERE public.staged_document_retirement_audit_items.outcome IS NULL
        AND (public.staged_document_retirement_audit_items.lease_expires_at IS NULL
          OR public.staged_document_retirement_audit_items.lease_expires_at <= now());
    IF FOUND THEN
      RETURN QUERY SELECT 'audit_required'::text, candidate.legacy_staged_document_id, next_token;
    END IF;
  END LOOP;
END $$;

-- Source and destination keys are exposed only to a live audit lease. The
-- original source is revalidated before every read; the destination is the
-- immutable canonical asset recorded by the completed transfer.
CREATE OR REPLACE FUNCTION public.get_staged_document_retirement_audit_grant(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_audit_lease_token uuid
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
    WHEN m.id IS NULL OR source.id IS NULL OR asset.id IS NULL OR intake.id IS NULL THEN 'not_found'
    WHEN m.outcome <> 'transfer_pending' OR m.transfer_completed_at IS NULL THEN 'not_completed'
    WHEN audit.lease_token IS DISTINCT FROM p_audit_lease_token
      OR audit.lease_expires_at IS NULL OR audit.lease_expires_at <= now() THEN 'lease_not_held'
    WHEN NOT public.staged_document_backfill_source_is_valid(source.org_id, source.storage_path, source.intake_matter_id) THEN 'invalid_lineage'
    WHEN asset.availability <> 'available' OR asset.legacy_staged_backfill_pending
      OR asset.storage_deleted_at IS NOT NULL OR intake.state <> 'ready'
      OR intake.asset_id IS DISTINCT FROM m.canonical_asset_id
      OR asset.sha256 IS DISTINCT FROM m.observed_sha256 OR asset.byte_size IS DISTINCT FROM m.observed_byte_size THEN 'database_inconsistent'
    ELSE 'ok'
  END,
  CASE WHEN audit.lease_token = p_audit_lease_token AND audit.lease_expires_at > now()
    AND m.outcome = 'transfer_pending' AND m.transfer_completed_at IS NOT NULL
    AND public.staged_document_backfill_source_is_valid(source.org_id, source.storage_path, source.intake_matter_id)
    AND asset.availability = 'available' AND NOT asset.legacy_staged_backfill_pending
    AND asset.storage_deleted_at IS NULL AND intake.state = 'ready' AND intake.asset_id = m.canonical_asset_id
    AND asset.sha256 IS NOT DISTINCT FROM m.observed_sha256 AND asset.byte_size IS NOT DISTINCT FROM m.observed_byte_size
    THEN 'staging' END,
  CASE WHEN audit.lease_token = p_audit_lease_token AND audit.lease_expires_at > now()
    AND m.outcome = 'transfer_pending' AND m.transfer_completed_at IS NOT NULL
    AND public.staged_document_backfill_source_is_valid(source.org_id, source.storage_path, source.intake_matter_id)
    AND asset.availability = 'available' AND NOT asset.legacy_staged_backfill_pending
    AND asset.storage_deleted_at IS NULL AND intake.state = 'ready' AND intake.asset_id = m.canonical_asset_id
    AND asset.sha256 IS NOT DISTINCT FROM m.observed_sha256 AND asset.byte_size IS NOT DISTINCT FROM m.observed_byte_size
    THEN source.storage_path END,
  CASE WHEN audit.lease_token = p_audit_lease_token AND audit.lease_expires_at > now()
    AND m.outcome = 'transfer_pending' AND m.transfer_completed_at IS NOT NULL
    AND asset.availability = 'available' AND NOT asset.legacy_staged_backfill_pending
    AND asset.storage_deleted_at IS NULL AND intake.state = 'ready' AND intake.asset_id = m.canonical_asset_id
    AND asset.sha256 IS NOT DISTINCT FROM m.observed_sha256 AND asset.byte_size IS NOT DISTINCT FROM m.observed_byte_size
    AND public.staged_document_backfill_source_is_valid(source.org_id, source.storage_path, source.intake_matter_id)
    THEN asset.bucket_id END,
  CASE WHEN audit.lease_token = p_audit_lease_token AND audit.lease_expires_at > now()
    AND m.outcome = 'transfer_pending' AND m.transfer_completed_at IS NOT NULL
    AND asset.availability = 'available' AND NOT asset.legacy_staged_backfill_pending
    AND asset.storage_deleted_at IS NULL AND intake.state = 'ready' AND intake.asset_id = m.canonical_asset_id
    AND asset.sha256 IS NOT DISTINCT FROM m.observed_sha256 AND asset.byte_size IS NOT DISTINCT FROM m.observed_byte_size
    AND public.staged_document_backfill_source_is_valid(source.org_id, source.storage_path, source.intake_matter_id)
    THEN asset.object_key END,
  CASE WHEN audit.lease_token = p_audit_lease_token AND audit.lease_expires_at > now()
    AND m.outcome = 'transfer_pending' AND m.transfer_completed_at IS NOT NULL
    AND public.staged_document_backfill_source_is_valid(source.org_id, source.storage_path, source.intake_matter_id)
    AND asset.availability = 'available' AND NOT asset.legacy_staged_backfill_pending
    AND asset.storage_deleted_at IS NULL AND intake.state = 'ready' AND intake.asset_id = m.canonical_asset_id
    AND asset.sha256 IS NOT DISTINCT FROM m.observed_sha256 AND asset.byte_size IS NOT DISTINCT FROM m.observed_byte_size
    THEN m.observed_byte_size END,
  CASE WHEN audit.lease_token = p_audit_lease_token AND audit.lease_expires_at > now()
    AND m.outcome = 'transfer_pending' AND m.transfer_completed_at IS NOT NULL
    AND public.staged_document_backfill_source_is_valid(source.org_id, source.storage_path, source.intake_matter_id)
    AND asset.availability = 'available' AND NOT asset.legacy_staged_backfill_pending
    AND asset.storage_deleted_at IS NULL AND intake.state = 'ready' AND intake.asset_id = m.canonical_asset_id
    AND asset.sha256 IS NOT DISTINCT FROM m.observed_sha256 AND asset.byte_size IS NOT DISTINCT FROM m.observed_byte_size
    THEN m.observed_sha256 END
  FROM (SELECT 1) AS request
  LEFT JOIN public.staged_document_backfill_items AS m
    ON m.org_id = p_org_id AND m.legacy_staged_document_id = p_legacy_staged_document_id
  LEFT JOIN public.staged_documents AS source
    ON source.org_id = m.org_id AND source.id = m.legacy_staged_document_id
  LEFT JOIN public.file_assets AS asset
    ON asset.org_id = m.org_id AND asset.id = m.canonical_asset_id
  LEFT JOIN public.intake_items AS intake
    ON intake.org_id = m.org_id AND intake.id = m.canonical_intake_item_id
  LEFT JOIN public.staged_document_retirement_audit_items AS audit
    ON audit.org_id = m.org_id AND audit.legacy_staged_document_id = m.legacy_staged_document_id
  ;
$$;

-- Only an exact fresh source/destination observation can record equal proof.
-- Conflict/missing outcomes carry no paths, hashes, byte values, or provider
-- errors into the database report surface.
CREATE OR REPLACE FUNCTION public.record_staged_document_retirement_audit(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_audit_lease_token uuid,
  p_outcome public.staged_document_retirement_audit_outcome,
  p_source_observed_bytes bigint DEFAULT NULL,
  p_source_sha256 text DEFAULT NULL,
  p_destination_observed_bytes bigint DEFAULT NULL,
  p_destination_sha256 text DEFAULT NULL
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE map_row public.staged_document_backfill_items%ROWTYPE;
DECLARE audit_row public.staged_document_retirement_audit_items%ROWTYPE;
BEGIN
  IF p_org_id IS NULL OR p_legacy_staged_document_id IS NULL OR p_audit_lease_token IS NULL OR p_outcome IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text;
    RETURN;
  END IF;
  SELECT * INTO map_row FROM public.staged_document_backfill_items AS m
    WHERE m.org_id = p_org_id AND m.legacy_staged_document_id = p_legacy_staged_document_id FOR UPDATE;
  SELECT * INTO audit_row FROM public.staged_document_retirement_audit_items AS audit
    WHERE audit.org_id = p_org_id AND audit.legacy_staged_document_id = p_legacy_staged_document_id FOR UPDATE;
  IF map_row.id IS NULL OR audit_row.legacy_staged_document_id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text;
    RETURN;
  END IF;
  IF audit_row.outcome IS NOT NULL THEN
    RETURN QUERY SELECT audit_row.outcome::text;
    RETURN;
  END IF;
  IF audit_row.lease_token IS DISTINCT FROM p_audit_lease_token OR audit_row.lease_expires_at IS NULL OR audit_row.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'lease_not_held'::text;
    RETURN;
  END IF;
  IF map_row.outcome <> 'transfer_pending' OR map_row.transfer_completed_at IS NULL THEN
    RETURN QUERY SELECT 'not_completed'::text;
    RETURN;
  END IF;
  IF p_outcome = 'verified_equal' AND (
    p_source_observed_bytes IS NULL OR p_destination_observed_bytes IS NULL
    OR p_source_sha256 IS NULL OR p_destination_sha256 IS NULL
    OR p_source_observed_bytes <> map_row.observed_byte_size
    OR p_destination_observed_bytes <> map_row.observed_byte_size
    OR p_source_sha256 <> map_row.observed_sha256
    OR p_destination_sha256 <> map_row.observed_sha256
    OR p_source_observed_bytes <> p_destination_observed_bytes
    OR p_source_sha256 <> p_destination_sha256
  ) THEN
    RETURN QUERY SELECT 'observation_conflict'::text;
    RETURN;
  END IF;
  IF p_outcome <> 'verified_equal' AND (
    p_source_observed_bytes IS NOT NULL OR p_destination_observed_bytes IS NOT NULL
    OR p_source_sha256 IS NOT NULL OR p_destination_sha256 IS NOT NULL
  ) THEN
    RETURN QUERY SELECT 'invalid_observation'::text;
    RETURN;
  END IF;
  UPDATE public.staged_document_retirement_audit_items
  SET outcome = p_outcome, audited_at = now(), lease_token = NULL, lease_expires_at = NULL
  WHERE org_id = p_org_id AND legacy_staged_document_id = p_legacy_staged_document_id;
  RETURN QUERY SELECT p_outcome::text;
END $$;

DROP VIEW public.staged_document_backfill_reports;
CREATE VIEW public.staged_document_backfill_reports AS
WITH retirement_orgs AS (
  SELECT org_id FROM public.staged_documents
  UNION SELECT org_id FROM public.staged_document_backfill_items
  UNION SELECT org_id FROM public.file_assets WHERE legacy_staged_backfill_pending
), counts AS (
  SELECT
    org.org_id,
    (SELECT count(*) FROM public.staged_documents AS source WHERE source.org_id = org.org_id)::bigint AS legacy_source_count,
    (SELECT count(*) FROM public.staged_documents AS source WHERE source.org_id = org.org_id AND source.status IN ('pending_assignment', 'analyzing', 'ready_to_assign', 'failed'))::bigint AS active_source_count,
    (SELECT count(*) FROM public.staged_documents AS source WHERE source.org_id = org.org_id AND NOT EXISTS (SELECT 1 FROM public.staged_document_backfill_items AS map WHERE map.org_id = source.org_id AND map.legacy_staged_document_id = source.id))::bigint AS unmapped_source_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.outcome = 'verification_required')::bigint AS verification_required_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.outcome = 'transfer_pending' AND map.transfer_completed_at IS NULL)::bigint AS transfer_pending_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.outcome = 'transfer_pending' AND map.transfer_completed_at IS NOT NULL)::bigint AS transfer_completed_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.outcome = 'missing_object')::bigint AS missing_object_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.outcome = 'unreadable_source')::bigint AS unreadable_source_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.outcome = 'malformed_pdf')::bigint AS malformed_pdf_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.outcome = 'encrypted_pdf')::bigint AS encrypted_pdf_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.outcome = 'non_pdf')::bigint AS non_pdf_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.outcome = 'oversize')::bigint AS oversize_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.outcome = 'invalid_lineage')::bigint AS invalid_lineage_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.outcome = 'duplicate_reference')::bigint AS duplicate_reference_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.outcome = 'already_migrated')::bigint AS already_migrated_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.outcome NOT IN ('transfer_pending', 'verification_required'))::bigint AS terminal_exception_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map LEFT JOIN public.file_assets AS asset ON asset.org_id = map.org_id AND asset.id = map.canonical_asset_id LEFT JOIN public.intake_items AS intake ON intake.org_id = map.org_id AND intake.id = map.canonical_intake_item_id WHERE map.org_id = org.org_id AND map.outcome = 'transfer_pending' AND map.transfer_completed_at IS NOT NULL AND (asset.id IS NULL OR asset.legacy_staged_backfill_pending OR asset.availability <> 'available' OR asset.storage_deleted_at IS NOT NULL OR asset.sha256 IS DISTINCT FROM map.observed_sha256 OR asset.byte_size IS DISTINCT FROM map.observed_byte_size OR intake.id IS NULL OR intake.state <> 'ready' OR intake.asset_id IS DISTINCT FROM map.canonical_asset_id))::bigint AS completed_transfer_inconsistent_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map LEFT JOIN public.file_assets AS target ON target.org_id = map.org_id AND target.id = map.duplicate_asset_id WHERE map.org_id = org.org_id AND map.outcome = 'duplicate_reference' AND (target.id IS NULL OR target.availability <> 'available' OR target.storage_deleted_at IS NOT NULL OR target.sha256 IS NULL))::bigint AS duplicate_target_invalid_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map JOIN public.staged_documents AS source ON source.org_id = map.org_id AND source.id = map.legacy_staged_document_id WHERE map.org_id = org.org_id AND NOT public.staged_document_backfill_source_is_valid(source.org_id, source.storage_path, source.intake_matter_id))::bigint AS mapped_lineage_invalid_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND NOT EXISTS (SELECT 1 FROM public.get_staged_document_backfill_adapter_fences(map.org_id) AS fence WHERE fence.legacy_staged_document_id = map.legacy_staged_document_id))::bigint AS adapter_fence_mismatch_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.verification_lease_expires_at > now())::bigint AS active_verification_lease_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.transfer_lease_expires_at > now())::bigint AS active_transfer_lease_count,
    (SELECT count(*) FROM public.staged_document_legacy_action_leases AS legacy_lease WHERE legacy_lease.org_id = org.org_id AND legacy_lease.expires_at > now())::bigint AS active_legacy_action_lease_count,
    (SELECT count(*) FROM public.staged_document_retirement_audit_items AS audit WHERE audit.org_id = org.org_id AND audit.outcome = 'verified_equal')::bigint AS transfer_reachability_verified_count,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map WHERE map.org_id = org.org_id AND map.outcome = 'transfer_pending' AND map.transfer_completed_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.staged_document_retirement_audit_items AS audit WHERE audit.org_id = map.org_id AND audit.legacy_staged_document_id = map.legacy_staged_document_id AND audit.outcome IS NOT NULL))::bigint AS transfer_reachability_audit_pending_count,
    (SELECT count(*) FROM public.staged_document_retirement_audit_items AS audit WHERE audit.org_id = org.org_id AND audit.outcome IS NULL AND audit.lease_expires_at > now())::bigint AS active_retirement_audit_lease_count,
    (SELECT count(*) FROM public.staged_document_retirement_audit_items AS audit WHERE audit.org_id = org.org_id AND audit.outcome = 'source_missing')::bigint AS audit_source_missing_count,
    (SELECT count(*) FROM public.staged_document_retirement_audit_items AS audit WHERE audit.org_id = org.org_id AND audit.outcome = 'destination_missing')::bigint AS audit_destination_missing_count,
    (SELECT count(*) FROM public.staged_document_retirement_audit_items AS audit WHERE audit.org_id = org.org_id AND audit.outcome = 'source_observation_conflict')::bigint AS audit_source_conflict_count,
    (SELECT count(*) FROM public.staged_document_retirement_audit_items AS audit WHERE audit.org_id = org.org_id AND audit.outcome = 'destination_observation_conflict')::bigint AS audit_destination_conflict_count,
    (SELECT count(*) FROM public.file_assets AS asset WHERE asset.org_id = org.org_id AND asset.legacy_staged_backfill_pending AND asset.availability = 'quarantined' AND asset.storage_deleted_at IS NULL AND NOT EXISTS (SELECT 1 FROM public.staged_document_backfill_items AS linked WHERE linked.org_id = asset.org_id AND linked.canonical_asset_id = asset.id))::bigint AS unproven_quarantined_backfill_asset_count
  FROM retirement_orgs AS org
), diagnostics AS (
  SELECT org_id, count(*)::bigint AS diagnostic_count
  FROM public.staged_document_backfill_diagnostics
  GROUP BY org_id
)
SELECT
  counts.*,
  (unmapped_source_count = 0 AND verification_required_count = 0) AS classification_complete,
  COALESCE(diagnostics.diagnostic_count, 0)::bigint AS diagnostic_count,
  (
    unmapped_source_count = 0
    AND verification_required_count = 0
    AND transfer_pending_count = 0
    AND active_verification_lease_count = 0
    AND active_transfer_lease_count = 0
    AND active_legacy_action_lease_count = 0
    AND active_retirement_audit_lease_count = 0
    AND transfer_reachability_audit_pending_count = 0
    AND transfer_completed_count = transfer_reachability_verified_count
    AND audit_source_missing_count = 0
    AND audit_destination_missing_count = 0
    AND audit_source_conflict_count = 0
    AND audit_destination_conflict_count = 0
    AND terminal_exception_count = 0
    AND completed_transfer_inconsistent_count = 0
    AND duplicate_target_invalid_count = 0
    AND mapped_lineage_invalid_count = 0
    AND adapter_fence_mismatch_count = 0
    AND unproven_quarantined_backfill_asset_count = 0
    AND COALESCE(diagnostics.diagnostic_count, 0) = 0
  ) AS staging_retirement_ready
FROM counts
LEFT JOIN diagnostics ON diagnostics.org_id = counts.org_id;

CREATE OR REPLACE VIEW public.staged_document_backfill_diagnostics AS
SELECT issue.org_id, issue.issue, count(*)::bigint AS affected_count
FROM (
  SELECT map.org_id, 'source_organisation_mismatch'::text AS issue
  FROM public.staged_document_backfill_items AS map
  JOIN public.staged_documents AS source ON source.id = map.legacy_staged_document_id
  WHERE source.org_id <> map.org_id
  UNION ALL
  SELECT map.org_id, 'mapped_source_invalid_lineage'::text
  FROM public.staged_document_backfill_items AS map
  JOIN public.staged_documents AS source ON source.org_id = map.org_id AND source.id = map.legacy_staged_document_id
  WHERE NOT public.staged_document_backfill_source_is_valid(source.org_id, source.storage_path, source.intake_matter_id)
  UNION ALL
  SELECT map.org_id, 'transfer_completed_database_inconsistent'::text
  FROM public.staged_document_backfill_items AS map
  LEFT JOIN public.file_assets AS asset ON asset.org_id = map.org_id AND asset.id = map.canonical_asset_id
  LEFT JOIN public.intake_items AS intake ON intake.org_id = map.org_id AND intake.id = map.canonical_intake_item_id
  WHERE map.outcome = 'transfer_pending' AND map.transfer_completed_at IS NOT NULL
    AND (asset.id IS NULL OR asset.legacy_staged_backfill_pending OR asset.availability <> 'available'
      OR asset.storage_deleted_at IS NOT NULL OR asset.sha256 IS DISTINCT FROM map.observed_sha256
      OR asset.byte_size IS DISTINCT FROM map.observed_byte_size OR intake.id IS NULL OR intake.state <> 'ready'
      OR intake.asset_id IS DISTINCT FROM map.canonical_asset_id)
  UNION ALL
  SELECT map.org_id, 'duplicate_target_not_available'::text
  FROM public.staged_document_backfill_items AS map
  LEFT JOIN public.file_assets AS target ON target.org_id = map.org_id AND target.id = map.duplicate_asset_id
  WHERE map.outcome = 'duplicate_reference'
    AND (target.id IS NULL OR target.availability <> 'available' OR target.storage_deleted_at IS NOT NULL OR target.sha256 IS NULL)
  UNION ALL
  SELECT map.org_id, 'adapter_fence_mismatch'::text
  FROM public.staged_document_backfill_items AS map
  WHERE NOT EXISTS (
    SELECT 1 FROM public.get_staged_document_backfill_adapter_fences(map.org_id) AS fence
    WHERE fence.legacy_staged_document_id = map.legacy_staged_document_id
  )
  UNION ALL
  SELECT asset.org_id, 'unproven_quarantined_backfill_asset'::text
  FROM public.file_assets AS asset
  WHERE asset.legacy_staged_backfill_pending AND asset.availability = 'quarantined'
    AND asset.storage_deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.staged_document_backfill_items AS linked
      WHERE linked.org_id = asset.org_id AND linked.canonical_asset_id = asset.id
    )
  UNION ALL
  SELECT org.org_id, 'legacy_adapter_fence_contract_unavailable'::text
  FROM (SELECT DISTINCT org_id FROM public.staged_document_backfill_items) AS org
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS proc
    WHERE proc.oid = 'public.get_staged_document_backfill_action_guard(uuid,uuid)'::regprocedure
      AND NOT has_function_privilege('authenticated', proc.oid, 'EXECUTE')
      AND has_function_privilege('service_role', proc.oid, 'EXECUTE')
  )
) AS issue
GROUP BY issue.org_id, issue.issue;

ALTER TABLE public.staged_document_retirement_audit_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staged_document_retirement_audit_items FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.staged_document_retirement_audit_items,
  public.staged_document_backfill_reports, public.staged_document_backfill_diagnostics
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.staged_document_backfill_reports,
  public.staged_document_backfill_diagnostics TO service_role, postgres;

REVOKE ALL ON FUNCTION public.claim_staged_document_retirement_audit_batch(uuid, integer),
  public.get_staged_document_retirement_audit_grant(uuid, uuid, uuid),
  public.record_staged_document_retirement_audit(uuid, uuid, uuid, public.staged_document_retirement_audit_outcome, bigint, text, bigint, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_staged_document_retirement_audit_batch(uuid, integer),
  public.get_staged_document_retirement_audit_grant(uuid, uuid, uuid),
  public.record_staged_document_retirement_audit(uuid, uuid, uuid, public.staged_document_retirement_audit_outcome, bigint, text, bigint, text)
  TO service_role;

COMMENT ON TABLE public.staged_document_retirement_audit_items IS
  'Service-only proof state for a non-destructive staging retirement review. It contains no paths, hashes, bytes, content, or provider errors.';
COMMENT ON VIEW public.staged_document_backfill_reports IS
  'Service-only aggregate per-organisation retirement evidence. Readiness proves only complete evidence; it is not human retention, deletion, adapter retirement, or consumer cut-over authorisation.';
COMMENT ON VIEW public.staged_document_backfill_diagnostics IS
  'Service-only aggregate-safe staged retirement diagnostics. It intentionally emits no object paths, identifiers, hashes, bytes, content, or provider errors.';

COMMIT;
