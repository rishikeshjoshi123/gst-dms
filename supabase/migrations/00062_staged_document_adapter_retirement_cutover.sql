-- Contract the retired staged-document compatibility surface only after every
-- legacy source has a zero-unresolved, database-verifiable retirement record.
--
-- This migration deliberately keeps staged_documents, mappings, audits, and
-- content-free purge tombstones as history.  It removes no evidence rows or
-- storage objects.  New Inbox intake is canonical; unassigned legacy sources
-- must have been resolved by an explicit human decision before this can run.
BEGIN;

CREATE OR REPLACE FUNCTION public.assert_staged_document_adapter_retirement_ready()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE unresolved_organisations bigint;
BEGIN
  WITH relevant_organisations AS (
    SELECT org_id FROM public.staged_documents
    UNION SELECT org_id FROM public.staged_document_backfill_items
    UNION SELECT org_id FROM public.staged_document_retirement_audit_items
    UNION SELECT org_id FROM public.staged_document_legacy_action_leases
    UNION SELECT org_id FROM public.staged_document_source_purge_tombstones
    UNION SELECT org_id FROM public.staged_document_source_purge_blockers
    UNION SELECT org_id FROM public.file_assets WHERE legacy_staged_backfill_pending
  ), unresolved AS (
    SELECT org.org_id
    FROM relevant_organisations AS org
    LEFT JOIN public.staged_document_backfill_reports AS backfill_report
      ON backfill_report.org_id = org.org_id
    LEFT JOIN public.staged_document_source_purge_reports AS purge_report
      ON purge_report.org_id = org.org_id
    WHERE backfill_report.staging_retirement_ready IS DISTINCT FROM true
      OR COALESCE(purge_report.verification_candidate_count, 0) <> 0
      OR COALESCE(purge_report.delete_intended_count, 0) <> 0
      OR COALESCE(purge_report.recovery_required_count, 0) <> 0
      OR COALESCE(purge_report.active_purge_lease_count, 0) <> 0
      OR COALESCE(purge_report.active_blocker_count, 0) <> 0
      -- A verified map is not retired until the corresponding staging-object
      -- deletion was confirmed durably.  A deleted tombstone is content-free
      -- and preserves the historical source/canonical relationship.
      OR EXISTS (
        SELECT 1
        FROM public.staged_document_backfill_items AS map
        LEFT JOIN public.staged_document_source_purge_tombstones AS tombstone
          ON tombstone.org_id = map.org_id
          AND tombstone.legacy_staged_document_id = map.legacy_staged_document_id
        WHERE map.org_id = org.org_id
          AND tombstone.state IS DISTINCT FROM 'deleted'
      )
      -- Queued/running canonical work, including a missing lease, is
      -- unresolved work.  Do not infer that it is safe merely because an old
      -- lease has expired; recovery remains explicit and tenant-scoped.
      OR EXISTS (
        SELECT 1
        FROM public.source_analysis_runs AS analysis
        JOIN public.staged_document_backfill_items AS map
          ON map.org_id = analysis.org_id AND map.canonical_asset_id = analysis.asset_id
        WHERE analysis.org_id = org.org_id AND analysis.state IN ('queued', 'running')
      )
      OR EXISTS (
        SELECT 1
        FROM public.document_processing_runs AS run
        JOIN public.document_versions AS version
          ON version.org_id = run.org_id AND version.id = run.document_version_id
        JOIN public.staged_document_backfill_items AS map
          ON map.org_id = version.org_id AND map.canonical_asset_id = version.asset_id
        WHERE run.org_id = org.org_id AND run.state IN ('queued', 'running')
      )
      OR EXISTS (
        SELECT 1
        FROM public.document_processing_recovery_cases AS recovery
        JOIN public.document_processing_runs AS run
          ON run.org_id = recovery.org_id AND run.id = recovery.processing_run_id
        JOIN public.document_versions AS version
          ON version.org_id = run.org_id AND version.id = run.document_version_id
        JOIN public.staged_document_backfill_items AS map
          ON map.org_id = version.org_id AND map.canonical_asset_id = version.asset_id
        WHERE recovery.org_id = org.org_id AND recovery.state = 'open'
      )
      -- Delivery is a separate durable authority from processing.  A mapped
      -- canonical asset must not be retired while any lifecycle envelope for
      -- its Intake, document, or version remains pending or leased, including
      -- an expired lease awaiting replay/reconciliation.
      OR EXISTS (
        SELECT 1
        FROM public.outbox_events AS event
        JOIN public.staged_document_backfill_items AS map
          ON map.org_id = event.org_id
        LEFT JOIN public.document_versions AS version
          ON version.org_id = map.org_id
          AND version.asset_id = map.canonical_asset_id
        LEFT JOIN public.documents AS document
          ON document.org_id = version.org_id
          AND document.id = version.document_id
        WHERE event.org_id = org.org_id
          AND event.delivery_state IN ('pending', 'leased')
          AND event.event_kind IN (
            'document.upload_reserved.v1',
            'document.upload_validation_requested.v1',
            'document.upload_duplicate.v1',
            'document.upload_failed.v1',
            'document.upload_expired.v1',
            'document.intake_validated.v1',
            'document.intake_validation_failed.v1',
            'document.metadata_created.v1',
            'document.processing_requested.v1',
            'document.reprocess_requested.v1',
            'intake.assigned.v1',
            'intake.discarded.v1'
          )
          AND (
            event.payload ->> 'asset_id' = map.canonical_asset_id::text
            OR event.payload ->> 'intake_id' = map.canonical_intake_item_id::text
            OR event.payload ->> 'version_id' = version.id::text
            OR event.payload ->> 'document_version_id' = version.id::text
            OR (event.aggregate_type = 'document' AND event.aggregate_id = document.id)
          )
      )
  )
  SELECT count(*) INTO unresolved_organisations FROM unresolved;

  IF unresolved_organisations <> 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'check_violation',
      MESSAGE = 'staged-document adapter retirement is blocked by unresolved retirement evidence',
      DETAIL = 'Resolve every organisation in the aggregate service-only retirement reports before removing compatibility reads or legacy assignment.';
  END IF;
END $$;

-- This is the migration gate.  It is intentionally before every privilege or
-- function change below, so a nonzero report leaves the old compatibility
-- contract entirely intact.
SELECT public.assert_staged_document_adapter_retirement_ready();

-- Preserve legacy data as read-only historical evidence.  The canonical
-- Intake/document/Trash lifecycle remains the sole product path.
REVOKE ALL ON TABLE public.staged_documents FROM anon, authenticated;

-- The old browser staging bucket and realtime channel would otherwise remain
-- a second, mutable transport surface after the adapter is gone.  Preserve
-- the bucket and every object as historical evidence; remove only browser
-- policy access and the table's live publication.
DROP POLICY IF EXISTS "staging_upload" ON storage.objects;
DROP POLICY IF EXISTS "staging_read" ON storage.objects;
DROP POLICY IF EXISTS "staging_delete" ON storage.objects;
ALTER PUBLICATION supabase_realtime DROP TABLE public.staged_documents;

-- These reports remain service-readable historical evidence after retirement.
-- Their two former adapter-fence diagnostics were prospective worker-contract
-- checks: the gate above has already proved them before revocation.  Keep
-- every retained count, but replace those live function calls with their
-- cutover-proven value so reading history never reopens a source-ID locator.
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
  SELECT asset.org_id, 'unproven_quarantined_backfill_asset'::text
  FROM public.file_assets AS asset
  WHERE asset.legacy_staged_backfill_pending AND asset.availability = 'quarantined'
    AND asset.storage_deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.staged_document_backfill_items AS linked
      WHERE linked.org_id = asset.org_id AND linked.canonical_asset_id = asset.id
    )
) AS issue
GROUP BY issue.org_id, issue.issue;

CREATE OR REPLACE VIEW public.staged_document_backfill_reports AS
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
    0::bigint AS adapter_fence_mismatch_count,
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

-- Existing callers cannot accidentally resume a legacy action after rollout.
-- Keep signatures as non-authorising compatibility tombstones so delayed
-- worker payloads cannot obtain a source key or mutate a legacy row.
CREATE OR REPLACE FUNCTION public.get_staged_document_backfill_action_guard(
  p_org_id uuid,
  p_legacy_staged_document_id uuid
)
RETURNS TABLE(code text)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$ SELECT 'adapter_retired'::text $$;

CREATE OR REPLACE FUNCTION public.reserve_legacy_staged_document_action(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_action_kind public.staged_document_legacy_action_kind
)
RETURNS TABLE(code text, lease_token uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT 'adapter_retired'::text, NULL::uuid $$;

CREATE OR REPLACE FUNCTION public.get_legacy_staged_document_action_source_grant(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_lease_token uuid,
  p_action_kind public.staged_document_legacy_action_kind
)
RETURNS TABLE(code text, bucket_id text, object_key text, uploaded_by uuid, intake_matter_id uuid)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$ SELECT 'adapter_retired'::text, NULL::text, NULL::text, NULL::uuid, NULL::uuid $$;

CREATE OR REPLACE FUNCTION public.release_legacy_staged_document_action(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_lease_token uuid
)
RETURNS TABLE(code text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT 'adapter_retired'::text $$;

CREATE OR REPLACE FUNCTION public.get_legacy_staged_document_read_grant(
  p_org_id uuid,
  p_legacy_staged_document_id uuid
)
RETURNS TABLE(code text, bucket_id text, object_key text)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$ SELECT 'adapter_retired'::text, NULL::text, NULL::text $$;

CREATE OR REPLACE FUNCTION public.get_legacy_staged_document_eligible_ids(p_org_id uuid)
RETURNS TABLE(legacy_staged_document_id uuid)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$ SELECT NULL::uuid WHERE false $$;

REVOKE ALL ON FUNCTION public.assert_staged_document_adapter_retirement_ready() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.assert_staged_document_adapter_retirement_ready() TO postgres;
REVOKE ALL ON FUNCTION public.get_staged_document_backfill_action_guard(uuid, uuid),
  public.reserve_legacy_staged_document_action(uuid, uuid, public.staged_document_legacy_action_kind),
  public.get_legacy_staged_document_action_source_grant(uuid, uuid, uuid, public.staged_document_legacy_action_kind),
  public.release_legacy_staged_document_action(uuid, uuid, uuid),
  public.get_legacy_staged_document_read_grant(uuid, uuid),
  public.get_legacy_staged_document_eligible_ids(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- The remaining backfill, transfer, audit, and physical-purge RPCs are
-- worker-only capabilities.  The zero-unresolved gate makes further worker
-- action invalid, so revoke their service execution rather than exposing
-- another compatibility locator or action tombstone.  Historical tables and
-- reports remain in place for retention/audit.
REVOKE ALL ON FUNCTION
  public.get_staged_document_backfill_source_grant(uuid, uuid, uuid),
  public.get_staged_document_backfill_adapter_fences(uuid),
  public.claim_staged_document_backfill_batch(uuid, integer),
  public.record_staged_document_backfill_verification(uuid, uuid, uuid, public.staged_document_backfill_source_result, bigint, text),
  public.claim_staged_document_backfill_transfer_batch(uuid, integer),
  public.get_staged_document_backfill_transfer_grant(uuid, uuid, uuid),
  public.complete_staged_document_backfill_transfer(uuid, uuid, uuid, bigint, text, integer, bigint, text),
  public.claim_staged_document_retirement_audit_batch(uuid, integer),
  public.get_staged_document_retirement_audit_grant(uuid, uuid, uuid),
  public.record_staged_document_retirement_audit(uuid, uuid, uuid, public.staged_document_retirement_audit_outcome, bigint, text, bigint, text),
  public.claim_staged_document_source_purge_batch(uuid, integer),
  public.get_staged_document_source_purge_grant(uuid, uuid, uuid),
  public.record_staged_document_source_purge_intent(uuid, uuid, uuid, bigint, text, integer, bigint, text, integer),
  public.confirm_staged_document_source_purge(uuid, uuid, uuid, text),
  public.record_staged_document_source_purge_recovery(uuid, uuid, uuid, text),
  public.create_staged_document_source_purge_blocker(
    uuid,
    public.staged_document_source_purge_blocker_scope,
    uuid,
    uuid,
    public.staged_document_source_purge_blocker_kind
  )
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.assert_staged_document_adapter_retirement_ready() IS
  'Migration-only zero-unresolved gate for staged compatibility retirement. It fails closed on any report, work, recovery, quarantine, lineage, or purge uncertainty.';
COMMENT ON TABLE public.staged_documents IS
  'Historical legacy staging records retained after canonical Inbox cutover. Browser policy/realtime access and legacy worker or assignment/read grants are retired; do not delete or repurpose this evidence table.';

COMMIT;
