-- Fail-closed physical retirement of redundant legacy staging objects.
--
-- This is deliberately narrower than adapter retirement: it never deletes a
-- legacy staged row, changes its compatibility fence, or releases a legacy
-- read/assignment path.  The only external effect is deletion of a staging
-- object that has a fresh, lease-bound proof of a healthy canonical twin.
BEGIN;

CREATE TYPE public.staged_document_source_purge_state AS ENUM (
  'claimed',
  'delete_intended',
  'deleted',
  'recovery_required'
);

CREATE TYPE public.staged_document_source_purge_blocker_kind AS ENUM (
  'legal_hold',
  'export_backup',
  'recovery'
);

-- This is both the durable external-effect intent ledger and, once confirmed,
-- the minimal tombstone.  It intentionally contains no path, filename, hash,
-- byte count, document content, provider response, or user-supplied reason.
CREATE TABLE public.staged_document_source_purge_tombstones (
  org_id uuid NOT NULL,
  legacy_staged_document_id uuid NOT NULL,
  state public.staged_document_source_purge_state NOT NULL DEFAULT 'claimed',
  lease_token uuid,
  lease_expires_at timestamptz,
  intent_created_at timestamptz,
  storage_delete_attempted_at timestamptz,
  storage_deleted_at timestamptz,
  verification_code text,
  recovery_code text,
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0 AND attempt_count <= 1000),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (org_id, legacy_staged_document_id),
  CONSTRAINT staged_document_source_purge_tombstones_map_fkey
    FOREIGN KEY (org_id, legacy_staged_document_id)
    REFERENCES public.staged_document_backfill_items(org_id, legacy_staged_document_id)
    ON DELETE RESTRICT,
  CONSTRAINT staged_document_source_purge_tombstone_lease_consistent CHECK (
    (lease_token IS NULL AND lease_expires_at IS NULL)
    OR (lease_token IS NOT NULL AND lease_expires_at IS NOT NULL)
  ),
  CONSTRAINT staged_document_source_purge_tombstone_deleted_consistent CHECK (
    (state = 'deleted' AND storage_deleted_at IS NOT NULL AND verification_code = 'fresh_equal_pdf')
    OR (state <> 'deleted' AND storage_deleted_at IS NULL)
  ),
  CONSTRAINT staged_document_source_purge_tombstone_recovery_consistent CHECK (
    (state = 'recovery_required' AND recovery_code IS NOT NULL)
    OR (state <> 'recovery_required' AND recovery_code IS NULL)
  ),
  CONSTRAINT staged_document_source_purge_tombstone_intent_consistent CHECK (
    (state = 'delete_intended' AND intent_created_at IS NOT NULL)
    OR state <> 'delete_intended'
  ),
  CONSTRAINT staged_document_source_purge_tombstone_safe_codes CHECK (
    (verification_code IS NULL OR verification_code = 'fresh_equal_pdf')
    AND (recovery_code IS NULL OR recovery_code IN (
      'source_missing_before_intent',
      'source_observation_conflict',
      'destination_missing',
      'destination_observation_conflict',
      'source_pdf_invalid',
      'destination_pdf_invalid',
      'database_inconsistent'
    ))
  )
);
CREATE INDEX staged_document_source_purge_claim_idx
  ON public.staged_document_source_purge_tombstones (org_id, lease_expires_at)
  WHERE state IN ('claimed', 'delete_intended');

-- The Trash plan's broader blocker model is not yet deployed.  This narrow,
-- service-only bridge makes a missing future integration fail closed rather
-- than treating absence of a UI/table as authority to purge a legal source.
CREATE TABLE public.staged_document_source_purge_blockers (
  org_id uuid NOT NULL,
  legacy_staged_document_id uuid NOT NULL,
  blocker_kind public.staged_document_source_purge_blocker_kind NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz,
  PRIMARY KEY (org_id, legacy_staged_document_id, blocker_kind),
  CONSTRAINT staged_document_source_purge_blockers_map_fkey
    FOREIGN KEY (org_id, legacy_staged_document_id)
    REFERENCES public.staged_document_backfill_items(org_id, legacy_staged_document_id)
    ON DELETE RESTRICT
);
CREATE INDEX staged_document_source_purge_active_blocker_idx
  ON public.staged_document_source_purge_blockers (org_id, legacy_staged_document_id)
  WHERE released_at IS NULL;

CREATE OR REPLACE FUNCTION public.staged_document_source_purge_touch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;
CREATE TRIGGER staged_document_source_purge_tombstones_touch
  BEFORE UPDATE ON public.staged_document_source_purge_tombstones
  FOR EACH ROW EXECUTE FUNCTION public.staged_document_source_purge_touch();

-- This boolean contains the database-authoritative half of the deletion
-- proof.  Storage reachability, byte/hash equality, and PDF readability are
-- supplied only by the leased worker immediately before it writes an intent.
CREATE OR REPLACE FUNCTION public.staged_document_source_purge_is_eligible(
  p_org_id uuid,
  p_legacy_staged_document_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.staged_document_backfill_items AS map
    JOIN public.staged_documents AS source
      ON source.org_id = map.org_id AND source.id = map.legacy_staged_document_id
    JOIN public.file_assets AS asset
      ON asset.org_id = map.org_id AND asset.id = map.canonical_asset_id
    JOIN public.intake_items AS intake
      ON intake.org_id = map.org_id AND intake.id = map.canonical_intake_item_id
    JOIN public.staged_document_retirement_audit_items AS audit
      ON audit.org_id = map.org_id AND audit.legacy_staged_document_id = map.legacy_staged_document_id
    WHERE map.org_id = p_org_id
      AND map.legacy_staged_document_id = p_legacy_staged_document_id
      -- Assignment/reference: the legacy source remains an unassigned
      -- compatibility row while a ready canonical intake owns the bytes.
      AND source.status IN ('pending_assignment', 'analyzing', 'ready_to_assign', 'failed')
      AND public.staged_document_backfill_source_is_valid(source.org_id, source.storage_path, source.intake_matter_id)
      AND map.outcome = 'transfer_pending'
      AND map.transfer_completed_at IS NOT NULL
      AND map.observed_byte_size IS NOT NULL
      AND map.observed_sha256 ~ '^[0-9a-f]{64}$'
      AND asset.availability = 'available'
      AND NOT asset.legacy_staged_backfill_pending
      AND asset.storage_deleted_at IS NULL
      AND asset.byte_size = map.observed_byte_size
      AND asset.sha256 = map.observed_sha256
      AND intake.state = 'ready'
      AND intake.asset_id = map.canonical_asset_id
      AND audit.outcome = 'verified_equal'
      AND audit.lease_expires_at IS NULL
      -- No active legacy, verification, transfer, audit, or purge work may
      -- race the external deletion.
      AND (map.verification_lease_expires_at IS NULL OR map.verification_lease_expires_at <= now())
      AND (map.transfer_lease_expires_at IS NULL OR map.transfer_lease_expires_at <= now())
      AND NOT EXISTS (
        SELECT 1 FROM public.staged_document_legacy_action_leases AS action_lease
        WHERE action_lease.org_id = map.org_id
          AND action_lease.legacy_staged_document_id = map.legacy_staged_document_id
          AND action_lease.expires_at > now()
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.staged_document_source_purge_blockers AS blocker
        WHERE blocker.org_id = map.org_id
          AND blocker.legacy_staged_document_id = map.legacy_staged_document_id
          AND blocker.released_at IS NULL
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.source_analysis_runs AS analysis
        WHERE analysis.org_id = map.org_id
          AND analysis.asset_id = map.canonical_asset_id
          AND analysis.state = 'running'
          AND analysis.lease_expires_at > now()
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.document_processing_runs AS run
        JOIN public.document_versions AS version
          ON version.id = run.document_version_id AND version.org_id = run.org_id
        WHERE run.org_id = map.org_id
          AND version.asset_id = map.canonical_asset_id
          AND run.state = 'running'
          AND run.lease_expires_at > now()
      )
      -- An unresolved canonical processing recovery is an explicit retention
      -- blocker even though the bytes already have a canonical copy.
      AND NOT EXISTS (
        SELECT 1
        FROM public.document_processing_recovery_cases AS recovery
        JOIN public.document_processing_runs AS run
          ON run.id = recovery.processing_run_id AND run.org_id = recovery.org_id
        JOIN public.document_versions AS version
          ON version.id = run.document_version_id AND version.org_id = run.org_id
        WHERE recovery.org_id = map.org_id
          AND recovery.state = 'open'
          AND version.asset_id = map.canonical_asset_id
      )
  )
$$;

-- Claims contain only opaque source identifiers.  An expired unconfirmed
-- intent is deliberately reclaimable so the worker can reconcile an unknown
-- Storage response instead of treating a timeout as success.
CREATE OR REPLACE FUNCTION public.claim_staged_document_source_purge_batch(
  p_org_id uuid,
  p_batch_size integer DEFAULT 10
)
RETURNS TABLE(code text, legacy_staged_document_id uuid, purge_lease_token uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE candidate record; next_token uuid;
BEGIN
  IF p_org_id IS NULL OR p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 25 THEN
    RAISE EXCEPTION 'invalid staged-source purge batch request';
  END IF;

  FOR candidate IN
    SELECT map.legacy_staged_document_id
    FROM public.staged_document_backfill_items AS map
    LEFT JOIN public.staged_document_source_purge_tombstones AS tombstone
      ON tombstone.org_id = map.org_id AND tombstone.legacy_staged_document_id = map.legacy_staged_document_id
    WHERE map.org_id = p_org_id
      AND (tombstone.state IS NULL OR tombstone.state IN ('claimed', 'delete_intended'))
      AND (tombstone.lease_expires_at IS NULL OR tombstone.lease_expires_at <= now())
      AND public.staged_document_source_purge_is_eligible(map.org_id, map.legacy_staged_document_id)
    ORDER BY map.transfer_completed_at, map.legacy_staged_document_id
    FOR UPDATE OF map SKIP LOCKED
    LIMIT p_batch_size
  LOOP
    next_token := gen_random_uuid();
    INSERT INTO public.staged_document_source_purge_tombstones (
      org_id, legacy_staged_document_id, state, lease_token, lease_expires_at, attempt_count
    ) VALUES (
      p_org_id, candidate.legacy_staged_document_id, 'claimed', next_token, now() + interval '10 minutes', 1
    )
    ON CONFLICT ON CONSTRAINT staged_document_source_purge_tombstones_pkey DO UPDATE
      SET state = 'claimed', lease_token = EXCLUDED.lease_token,
          lease_expires_at = EXCLUDED.lease_expires_at,
          attempt_count = public.staged_document_source_purge_tombstones.attempt_count + 1
      WHERE public.staged_document_source_purge_tombstones.state IN ('claimed', 'delete_intended')
        AND (public.staged_document_source_purge_tombstones.lease_expires_at IS NULL
          OR public.staged_document_source_purge_tombstones.lease_expires_at <= now());
    IF FOUND THEN
      RETURN QUERY SELECT 'purge_required'::text, candidate.legacy_staged_document_id, next_token;
    END IF;
  END LOOP;
END $$;

-- Storage names exist only in this short-lived service grant.  The key is
-- never part of a task payload, report, tombstone, or recovery record.
CREATE OR REPLACE FUNCTION public.get_staged_document_source_purge_grant(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_purge_lease_token uuid
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
  SELECT
    CASE
      WHEN map.id IS NULL OR tombstone.legacy_staged_document_id IS NULL THEN 'not_found'
      WHEN tombstone.state NOT IN ('claimed', 'delete_intended') THEN tombstone.state::text
      WHEN tombstone.lease_token IS DISTINCT FROM p_purge_lease_token
        OR tombstone.lease_expires_at IS NULL OR tombstone.lease_expires_at <= now() THEN 'lease_not_held'
      WHEN source.id IS NULL OR asset.id IS NULL OR intake.id IS NULL OR audit.legacy_staged_document_id IS NULL
        OR map.outcome <> 'transfer_pending' OR map.transfer_completed_at IS NULL
        OR source.status NOT IN ('pending_assignment', 'analyzing', 'ready_to_assign', 'failed')
        OR NOT public.staged_document_backfill_source_is_valid(source.org_id, source.storage_path, source.intake_matter_id)
        OR map.observed_byte_size IS NULL OR map.observed_sha256 !~ '^[0-9a-f]{64}$'
        OR asset.availability <> 'available' OR asset.legacy_staged_backfill_pending
        OR asset.storage_deleted_at IS NOT NULL OR asset.byte_size IS DISTINCT FROM map.observed_byte_size
        OR asset.sha256 IS DISTINCT FROM map.observed_sha256
        OR intake.state <> 'ready' OR intake.asset_id IS DISTINCT FROM map.canonical_asset_id
        OR audit.outcome <> 'verified_equal' THEN 'database_inconsistent'
      WHEN EXISTS (
        SELECT 1 FROM public.staged_document_source_purge_blockers AS blocker
        WHERE blocker.org_id = map.org_id AND blocker.legacy_staged_document_id = map.legacy_staged_document_id
          AND blocker.released_at IS NULL
      ) OR EXISTS (
        SELECT 1
        FROM public.document_processing_recovery_cases AS recovery
        JOIN public.document_processing_runs AS run
          ON run.id = recovery.processing_run_id AND run.org_id = recovery.org_id
        JOIN public.document_versions AS version
          ON version.id = run.document_version_id AND version.org_id = run.org_id
        WHERE recovery.org_id = map.org_id AND recovery.state = 'open'
          AND version.asset_id = map.canonical_asset_id
      ) THEN 'blocked'
      WHEN (map.verification_lease_expires_at IS NOT NULL AND map.verification_lease_expires_at > now())
        OR (map.transfer_lease_expires_at IS NOT NULL AND map.transfer_lease_expires_at > now())
        OR audit.lease_expires_at > now()
        OR EXISTS (
          SELECT 1 FROM public.staged_document_legacy_action_leases AS action_lease
          WHERE action_lease.org_id = map.org_id AND action_lease.legacy_staged_document_id = map.legacy_staged_document_id
            AND action_lease.expires_at > now()
        ) OR EXISTS (
          SELECT 1 FROM public.source_analysis_runs AS analysis
          WHERE analysis.org_id = map.org_id AND analysis.asset_id = map.canonical_asset_id
            AND analysis.state = 'running' AND analysis.lease_expires_at > now()
        ) OR EXISTS (
          SELECT 1 FROM public.document_processing_runs AS run
          JOIN public.document_versions AS version
            ON version.id = run.document_version_id AND version.org_id = run.org_id
          WHERE run.org_id = map.org_id AND version.asset_id = map.canonical_asset_id
            AND run.state = 'running' AND run.lease_expires_at > now()
        ) THEN 'work_active'
      WHEN NOT public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id) THEN 'not_eligible'
      ELSE 'ok'
    END AS code,
    CASE WHEN tombstone.lease_token = p_purge_lease_token AND tombstone.lease_expires_at > now()
      AND tombstone.state IN ('claimed', 'delete_intended')
      AND public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id)
      THEN 'staging' END AS source_bucket_id,
    CASE WHEN tombstone.lease_token = p_purge_lease_token AND tombstone.lease_expires_at > now()
      AND tombstone.state IN ('claimed', 'delete_intended')
      AND public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id)
      THEN source.storage_path END AS source_object_key,
    CASE WHEN tombstone.lease_token = p_purge_lease_token AND tombstone.lease_expires_at > now()
      AND tombstone.state IN ('claimed', 'delete_intended')
      AND public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id)
      THEN asset.bucket_id END AS destination_bucket_id,
    CASE WHEN tombstone.lease_token = p_purge_lease_token AND tombstone.lease_expires_at > now()
      AND tombstone.state IN ('claimed', 'delete_intended')
      AND public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id)
      THEN asset.object_key END AS destination_object_key,
    CASE WHEN tombstone.lease_token = p_purge_lease_token AND tombstone.lease_expires_at > now()
      AND tombstone.state IN ('claimed', 'delete_intended')
      AND public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id)
      THEN map.observed_byte_size END AS expected_byte_size,
    CASE WHEN tombstone.lease_token = p_purge_lease_token AND tombstone.lease_expires_at > now()
      AND tombstone.state IN ('claimed', 'delete_intended')
      AND public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id)
      THEN map.observed_sha256 END AS expected_sha256
  FROM (SELECT 1) AS request
  LEFT JOIN public.staged_document_backfill_items AS map
    ON map.org_id = p_org_id AND map.legacy_staged_document_id = p_legacy_staged_document_id
  LEFT JOIN public.staged_document_source_purge_tombstones AS tombstone
    ON tombstone.org_id = map.org_id AND tombstone.legacy_staged_document_id = map.legacy_staged_document_id
  LEFT JOIN public.staged_documents AS source
    ON source.org_id = map.org_id AND source.id = map.legacy_staged_document_id
  LEFT JOIN public.file_assets AS asset
    ON asset.org_id = map.org_id AND asset.id = map.canonical_asset_id
  LEFT JOIN public.intake_items AS intake
    ON intake.org_id = map.org_id AND intake.id = map.canonical_intake_item_id
  LEFT JOIN public.staged_document_retirement_audit_items AS audit
    ON audit.org_id = map.org_id AND audit.legacy_staged_document_id = map.legacy_staged_document_id
$$;

-- A fresh, independently parsed source/destination observation becomes a
-- durable intent before any Storage deletion.  Observations are checked but
-- never retained, so the intent/tombstone remains content-free.
CREATE OR REPLACE FUNCTION public.record_staged_document_source_purge_intent(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_purge_lease_token uuid,
  p_source_observed_bytes bigint,
  p_source_sha256 text,
  p_source_page_count integer,
  p_destination_observed_bytes bigint,
  p_destination_sha256 text,
  p_destination_page_count integer
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE map_row public.staged_document_backfill_items%ROWTYPE;
DECLARE tombstone_row public.staged_document_source_purge_tombstones%ROWTYPE;
BEGIN
  IF p_org_id IS NULL OR p_legacy_staged_document_id IS NULL OR p_purge_lease_token IS NULL
    OR p_source_observed_bytes IS NULL OR p_destination_observed_bytes IS NULL
    OR p_source_observed_bytes <= 0 OR p_destination_observed_bytes <= 0
    OR p_source_page_count IS NULL OR p_destination_page_count IS NULL
    OR p_source_page_count <= 0 OR p_destination_page_count <= 0
    OR p_source_sha256 IS NULL OR p_destination_sha256 IS NULL
    OR p_source_sha256 !~ '^[0-9a-f]{64}$' OR p_destination_sha256 !~ '^[0-9a-f]{64}$' THEN
    RETURN QUERY SELECT 'invalid_observation'::text;
    RETURN;
  END IF;
  SELECT * INTO map_row FROM public.staged_document_backfill_items AS map
    WHERE map.org_id = p_org_id AND map.legacy_staged_document_id = p_legacy_staged_document_id FOR UPDATE;
  SELECT * INTO tombstone_row FROM public.staged_document_source_purge_tombstones AS tombstone
    WHERE tombstone.org_id = p_org_id AND tombstone.legacy_staged_document_id = p_legacy_staged_document_id FOR UPDATE;
  IF map_row.id IS NULL OR tombstone_row.legacy_staged_document_id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text;
    RETURN;
  END IF;
  IF tombstone_row.state IN ('deleted', 'recovery_required') THEN
    RETURN QUERY SELECT tombstone_row.state::text;
    RETURN;
  END IF;
  IF tombstone_row.lease_token IS DISTINCT FROM p_purge_lease_token
    OR tombstone_row.lease_expires_at IS NULL OR tombstone_row.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'lease_not_held'::text;
    RETURN;
  END IF;
  IF NOT public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id) THEN
    RETURN QUERY SELECT 'not_eligible'::text;
    RETURN;
  END IF;
  IF p_source_observed_bytes <> map_row.observed_byte_size
    OR p_destination_observed_bytes <> map_row.observed_byte_size
    OR p_source_sha256 <> map_row.observed_sha256
    OR p_destination_sha256 <> map_row.observed_sha256
    OR p_source_observed_bytes <> p_destination_observed_bytes
    OR p_source_sha256 <> p_destination_sha256 THEN
    RETURN QUERY SELECT 'observation_conflict'::text;
    RETURN;
  END IF;
  UPDATE public.staged_document_source_purge_tombstones
  SET state = 'delete_intended', intent_created_at = coalesce(intent_created_at, now()),
      storage_delete_attempted_at = now(), verification_code = NULL, recovery_code = NULL
  WHERE org_id = p_org_id AND legacy_staged_document_id = p_legacy_staged_document_id;
  RETURN QUERY SELECT 'delete_intended'::text;
END $$;

-- Success and a trusted 404 after an older durable intent are both durable
-- confirmation paths.  The latter reconciles a lost worker response; a 404
-- before any intent is deliberately rejected and must enter recovery.
CREATE OR REPLACE FUNCTION public.confirm_staged_document_source_purge(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_purge_lease_token uuid,
  p_confirmation text
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE tombstone_row public.staged_document_source_purge_tombstones%ROWTYPE;
BEGIN
  IF p_org_id IS NULL OR p_legacy_staged_document_id IS NULL OR p_purge_lease_token IS NULL
    OR p_confirmation NOT IN ('storage_deleted', 'storage_missing_after_intent') THEN
    RETURN QUERY SELECT 'invalid_request'::text;
    RETURN;
  END IF;
  SELECT * INTO tombstone_row FROM public.staged_document_source_purge_tombstones AS tombstone
    WHERE tombstone.org_id = p_org_id AND tombstone.legacy_staged_document_id = p_legacy_staged_document_id FOR UPDATE;
  IF tombstone_row.legacy_staged_document_id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text;
    RETURN;
  END IF;
  IF tombstone_row.state = 'deleted' THEN
    RETURN QUERY SELECT 'already_deleted'::text;
    RETURN;
  END IF;
  IF tombstone_row.state <> 'delete_intended'
    AND NOT (p_confirmation = 'storage_missing_after_intent'
      AND tombstone_row.state = 'claimed' AND tombstone_row.intent_created_at IS NOT NULL) THEN
    RETURN QUERY SELECT 'intent_not_recorded'::text;
    RETURN;
  END IF;
  IF tombstone_row.lease_token IS DISTINCT FROM p_purge_lease_token
    OR tombstone_row.lease_expires_at IS NULL OR tombstone_row.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'lease_not_held'::text;
    RETURN;
  END IF;
  UPDATE public.staged_document_source_purge_tombstones
  SET state = 'deleted', storage_deleted_at = now(), verification_code = 'fresh_equal_pdf',
      recovery_code = NULL, lease_token = NULL, lease_expires_at = NULL
  WHERE org_id = p_org_id AND legacy_staged_document_id = p_legacy_staged_document_id;
  RETURN QUERY SELECT 'deleted'::text;
END $$;

-- Contradictions are retained as durable, content-free recovery work.  A
-- transient Storage failure never calls this function and instead expires its
-- lease for a later safe retry.
CREATE OR REPLACE FUNCTION public.record_staged_document_source_purge_recovery(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_purge_lease_token uuid,
  p_recovery_code text
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE tombstone_row public.staged_document_source_purge_tombstones%ROWTYPE;
BEGIN
  IF p_org_id IS NULL OR p_legacy_staged_document_id IS NULL OR p_purge_lease_token IS NULL
    OR p_recovery_code NOT IN (
      'source_missing_before_intent', 'source_observation_conflict',
      'destination_missing', 'destination_observation_conflict',
      'source_pdf_invalid', 'destination_pdf_invalid', 'database_inconsistent'
    ) THEN
    RETURN QUERY SELECT 'invalid_request'::text;
    RETURN;
  END IF;
  SELECT * INTO tombstone_row FROM public.staged_document_source_purge_tombstones AS tombstone
    WHERE tombstone.org_id = p_org_id AND tombstone.legacy_staged_document_id = p_legacy_staged_document_id FOR UPDATE;
  IF tombstone_row.legacy_staged_document_id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text;
    RETURN;
  END IF;
  IF tombstone_row.state IN ('deleted', 'recovery_required') THEN
    RETURN QUERY SELECT tombstone_row.state::text;
    RETURN;
  END IF;
  IF tombstone_row.lease_token IS DISTINCT FROM p_purge_lease_token
    OR tombstone_row.lease_expires_at IS NULL OR tombstone_row.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'lease_not_held'::text;
    RETURN;
  END IF;
  UPDATE public.staged_document_source_purge_tombstones
  SET state = 'recovery_required', recovery_code = p_recovery_code,
      verification_code = NULL, lease_token = NULL, lease_expires_at = NULL
  WHERE org_id = p_org_id AND legacy_staged_document_id = p_legacy_staged_document_id;
  RETURN QUERY SELECT 'recovery_required'::text;
END $$;

CREATE OR REPLACE VIEW public.staged_document_source_purge_reports AS
WITH orgs AS (
  SELECT org_id FROM public.staged_document_backfill_items
  UNION SELECT org_id FROM public.staged_document_source_purge_tombstones
), counts AS (
  SELECT
    org.org_id,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map
      JOIN public.staged_document_retirement_audit_items AS audit
        ON audit.org_id = map.org_id AND audit.legacy_staged_document_id = map.legacy_staged_document_id
      LEFT JOIN public.staged_document_source_purge_tombstones AS tombstone
        ON tombstone.org_id = map.org_id AND tombstone.legacy_staged_document_id = map.legacy_staged_document_id
      WHERE map.org_id = org.org_id AND audit.outcome = 'verified_equal'
        AND (tombstone.state IS NULL OR tombstone.state IN ('claimed', 'delete_intended'))
    )::bigint AS verification_candidate_count,
    (SELECT count(*) FROM public.staged_document_source_purge_tombstones AS tombstone
      WHERE tombstone.org_id = org.org_id AND tombstone.state = 'delete_intended')::bigint AS delete_intended_count,
    (SELECT count(*) FROM public.staged_document_source_purge_tombstones AS tombstone
      WHERE tombstone.org_id = org.org_id AND tombstone.state = 'deleted')::bigint AS deleted_tombstone_count,
    (SELECT count(*) FROM public.staged_document_source_purge_tombstones AS tombstone
      WHERE tombstone.org_id = org.org_id AND tombstone.state = 'recovery_required')::bigint AS recovery_required_count,
    (SELECT count(*) FROM public.staged_document_source_purge_tombstones AS tombstone
      WHERE tombstone.org_id = org.org_id AND tombstone.state IN ('claimed', 'delete_intended')
        AND tombstone.lease_expires_at > now())::bigint AS active_purge_lease_count,
    (SELECT count(*) FROM public.staged_document_source_purge_blockers AS blocker
      WHERE blocker.org_id = org.org_id AND blocker.released_at IS NULL)::bigint AS active_blocker_count
  FROM orgs AS org
)
SELECT * FROM counts;

ALTER TABLE public.staged_document_source_purge_tombstones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staged_document_source_purge_tombstones FORCE ROW LEVEL SECURITY;
ALTER TABLE public.staged_document_source_purge_blockers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staged_document_source_purge_blockers FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.staged_document_source_purge_tombstones,
  public.staged_document_source_purge_blockers, public.staged_document_source_purge_reports
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.staged_document_source_purge_reports TO service_role, postgres;

REVOKE ALL ON FUNCTION public.staged_document_source_purge_touch(),
  public.staged_document_source_purge_is_eligible(uuid, uuid),
  public.claim_staged_document_source_purge_batch(uuid, integer),
  public.get_staged_document_source_purge_grant(uuid, uuid, uuid),
  public.record_staged_document_source_purge_intent(uuid, uuid, uuid, bigint, text, integer, bigint, text, integer),
  public.confirm_staged_document_source_purge(uuid, uuid, uuid, text),
  public.record_staged_document_source_purge_recovery(uuid, uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_staged_document_source_purge_batch(uuid, integer),
  public.get_staged_document_source_purge_grant(uuid, uuid, uuid),
  public.record_staged_document_source_purge_intent(uuid, uuid, uuid, bigint, text, integer, bigint, text, integer),
  public.confirm_staged_document_source_purge(uuid, uuid, uuid, text),
  public.record_staged_document_source_purge_recovery(uuid, uuid, uuid, text)
  TO service_role;

COMMENT ON TABLE public.staged_document_source_purge_tombstones IS
  'Service-only staged-source purge intent and minimal content-free confirmation tombstones. It stores no object path, filename, hash, byte count, content, or provider response.';
COMMENT ON TABLE public.staged_document_source_purge_blockers IS
  'Service-only content-free bridge for legal hold, export/backup, and recovery blockers before the broader Trash blocker contract is deployed.';
COMMENT ON VIEW public.staged_document_source_purge_reports IS
  'Service-only aggregate staged-source purge counts. It exposes no source identifiers, object names, hashes, byte counts, contents, or provider errors.';

COMMIT;
