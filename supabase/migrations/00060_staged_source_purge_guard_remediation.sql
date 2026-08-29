-- Safety remediation for staged-source purge authority.
--
-- Coverage is a positive authority, not an empty-table assumption.  Every
-- organisation starts unknown for every required guard and stays non-purgable
-- until a PostgreSQL-owner operational attestation marks each guard current.
BEGIN;

CREATE TYPE public.staged_document_source_purge_guard_kind AS ENUM (
  'legal_hold',
  'export',
  'backup',
  'recovery',
  'retention_lock'
);

CREATE TYPE public.staged_document_source_purge_guard_coverage_state AS ENUM (
  'unknown',
  'enforced',
  'disabled_verified'
);

CREATE TYPE public.staged_document_source_purge_blocker_scope AS ENUM (
  'organisation',
  'canonical_asset',
  'legacy_source'
);

ALTER TYPE public.staged_document_source_purge_blocker_kind ADD VALUE IF NOT EXISTS 'export';
ALTER TYPE public.staged_document_source_purge_blocker_kind ADD VALUE IF NOT EXISTS 'backup';
ALTER TYPE public.staged_document_source_purge_blocker_kind ADD VALUE IF NOT EXISTS 'retention_lock';

CREATE TABLE public.staged_document_source_purge_guard_coverage (
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  guard_kind public.staged_document_source_purge_guard_kind NOT NULL,
  coverage_state public.staged_document_source_purge_guard_coverage_state NOT NULL DEFAULT 'unknown',
  attestation_code text,
  attested_at timestamptz,
  valid_until timestamptz,
  attested_by name,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (org_id, guard_kind),
  CONSTRAINT staged_document_source_purge_guard_coverage_shape CHECK (
    (coverage_state = 'unknown' AND attestation_code IS NULL AND attested_at IS NULL
      AND valid_until IS NULL AND attested_by IS NULL)
    OR (coverage_state = 'enforced' AND attestation_code = 'coverage_enforced'
      AND attested_at IS NOT NULL AND valid_until IS NOT NULL AND valid_until > attested_at
      AND attested_by IS NOT NULL)
    OR (coverage_state = 'disabled_verified' AND attestation_code = 'disabled_by_authorized_operation'
      AND attested_at IS NOT NULL AND valid_until IS NOT NULL AND valid_until > attested_at
      AND attested_by IS NOT NULL)
  )
);
CREATE INDEX staged_document_source_purge_guard_coverage_fresh_idx
  ON public.staged_document_source_purge_guard_coverage (org_id, valid_until);

-- Existing organisations are intentionally seeded as unknown.  This does not
-- attest coverage and therefore cannot enable any delete by itself.
INSERT INTO public.staged_document_source_purge_guard_coverage (org_id, guard_kind)
SELECT org.id, guard.guard_kind
FROM public.organisations AS org
CROSS JOIN unnest(enum_range(NULL::public.staged_document_source_purge_guard_kind)) AS guard(guard_kind)
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.seed_staged_document_source_purge_guard_coverage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  INSERT INTO public.staged_document_source_purge_guard_coverage (org_id, guard_kind)
  SELECT NEW.id, guard.guard_kind
  FROM unnest(enum_range(NULL::public.staged_document_source_purge_guard_kind)) AS guard(guard_kind)
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END $$;
CREATE TRIGGER organisations_seed_staged_document_source_purge_guard_coverage
  AFTER INSERT ON public.organisations
  FOR EACH ROW EXECUTE FUNCTION public.seed_staged_document_source_purge_guard_coverage();

-- Only the PostgreSQL owner may make a current attestation.  The required
-- operational procedure is to verify the named guard's authoritative system,
-- then run this bounded command with a short (at most 24h) expiry.  It must be
-- repeated for all five guards; this migration does not claim any attestation
-- has occurred.
CREATE OR REPLACE FUNCTION public.attest_staged_document_source_purge_guard_coverage(
  p_org_id uuid,
  p_guard_kind public.staged_document_source_purge_guard_kind,
  p_coverage_state public.staged_document_source_purge_guard_coverage_state,
  p_valid_until timestamptz
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF session_user <> 'postgres' THEN
    RAISE EXCEPTION 'staged-source purge guard attestation requires PostgreSQL owner';
  END IF;
  IF p_org_id IS NULL OR p_guard_kind IS NULL
    OR p_coverage_state NOT IN ('enforced', 'disabled_verified')
    OR p_valid_until IS NULL OR p_valid_until <= now() OR p_valid_until > now() + interval '24 hours' THEN
    RETURN QUERY SELECT 'invalid_request'::text;
    RETURN;
  END IF;
  INSERT INTO public.staged_document_source_purge_guard_coverage AS coverage (
    org_id, guard_kind, coverage_state, attestation_code, attested_at, valid_until, attested_by
  ) VALUES (
    p_org_id, p_guard_kind, p_coverage_state,
    CASE WHEN p_coverage_state = 'enforced' THEN 'coverage_enforced' ELSE 'disabled_by_authorized_operation' END,
    now(), p_valid_until, session_user
  )
  ON CONFLICT (org_id, guard_kind) DO UPDATE
    SET coverage_state = EXCLUDED.coverage_state,
        attestation_code = EXCLUDED.attestation_code,
        attested_at = EXCLUDED.attested_at,
        valid_until = EXCLUDED.valid_until,
        attested_by = EXCLUDED.attested_by,
        updated_at = now();
  RETURN QUERY SELECT 'attested'::text;
END $$;

CREATE OR REPLACE FUNCTION public.staged_document_source_purge_guard_coverage_is_current(
  p_org_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT count(*) = 5
    AND bool_and(coverage_state IN ('enforced', 'disabled_verified') AND valid_until > now())
  FROM public.staged_document_source_purge_guard_coverage
  WHERE org_id = p_org_id
$$;

-- A guard becoming unknown/stale before the external effect must fence every
-- outstanding intent.  A time-based expiry is also checked by every purge
-- authority, so it cannot silently permit a later delete.
CREATE OR REPLACE FUNCTION public.reconcile_staged_document_source_purge_guard_coverage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.coverage_state = 'unknown' OR NEW.valid_until IS NULL OR NEW.valid_until <= now() THEN
    UPDATE public.staged_document_source_purge_tombstones
    SET state = 'recovery_required', recovery_code = 'late_guard_blocker',
        verification_code = NULL, lease_token = NULL, lease_expires_at = NULL
    WHERE org_id = NEW.org_id AND state = 'delete_intended';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER staged_document_source_purge_guard_coverage_reconcile_intents
  AFTER INSERT OR UPDATE ON public.staged_document_source_purge_guard_coverage
  FOR EACH ROW EXECUTE FUNCTION public.reconcile_staged_document_source_purge_guard_coverage();

ALTER TABLE public.staged_document_source_purge_tombstones
  DROP CONSTRAINT staged_document_source_purge_tombstone_safe_codes,
  ADD CONSTRAINT staged_document_source_purge_tombstone_safe_codes CHECK (
    (verification_code IS NULL OR verification_code = 'fresh_equal_pdf')
    AND (recovery_code IS NULL OR recovery_code IN (
      'source_missing_before_intent',
      'source_observation_conflict',
      'destination_missing',
      'destination_observation_conflict',
      'source_pdf_invalid',
      'destination_pdf_invalid',
      'database_inconsistent',
      'late_guard_blocker',
      'late_eligibility_blocker',
      'attempt_cap_exhausted'
    ))
  );

-- Expand the blocker ledger to the only scopes that can protect this source:
-- organisation-wide policy, the canonical asset, or the legacy source.  It
-- remains service-inaccessible; future writers must use their own privileged
-- command and are serialised by the trigger below.
ALTER TABLE public.staged_document_source_purge_blockers
  DROP CONSTRAINT staged_document_source_purge_blockers_pkey,
  DROP CONSTRAINT staged_document_source_purge_blockers_map_fkey,
  ADD COLUMN id uuid NOT NULL DEFAULT gen_random_uuid(),
  ADD COLUMN scope public.staged_document_source_purge_blocker_scope NOT NULL DEFAULT 'legacy_source',
  ADD COLUMN canonical_asset_id uuid,
  ALTER COLUMN legacy_staged_document_id DROP NOT NULL,
  ADD CONSTRAINT staged_document_source_purge_blockers_pkey PRIMARY KEY (id),
  ADD CONSTRAINT staged_document_source_purge_blockers_org_fkey
    FOREIGN KEY (org_id) REFERENCES public.organisations(id) ON DELETE RESTRICT,
  ADD CONSTRAINT staged_document_source_purge_blockers_source_fkey
    FOREIGN KEY (org_id, legacy_staged_document_id)
    REFERENCES public.staged_document_backfill_items(org_id, legacy_staged_document_id) ON DELETE RESTRICT,
  ADD CONSTRAINT staged_document_source_purge_blockers_asset_fkey
    FOREIGN KEY (org_id, canonical_asset_id)
    REFERENCES public.file_assets(org_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT staged_document_source_purge_blockers_scope_shape CHECK (
    (scope = 'organisation' AND legacy_staged_document_id IS NULL AND canonical_asset_id IS NULL)
    OR (scope = 'canonical_asset' AND legacy_staged_document_id IS NULL AND canonical_asset_id IS NOT NULL)
    OR (scope = 'legacy_source' AND legacy_staged_document_id IS NOT NULL AND canonical_asset_id IS NULL)
  );
DROP INDEX public.staged_document_source_purge_active_blocker_idx;
CREATE UNIQUE INDEX staged_document_source_purge_active_org_blocker_unique
  ON public.staged_document_source_purge_blockers (org_id, blocker_kind)
  WHERE released_at IS NULL AND scope = 'organisation';
CREATE UNIQUE INDEX staged_document_source_purge_active_asset_blocker_unique
  ON public.staged_document_source_purge_blockers (org_id, canonical_asset_id, blocker_kind)
  WHERE released_at IS NULL AND scope = 'canonical_asset';
CREATE UNIQUE INDEX staged_document_source_purge_active_source_blocker_unique
  ON public.staged_document_source_purge_blockers (org_id, legacy_staged_document_id, blocker_kind)
  WHERE released_at IS NULL AND scope = 'legacy_source';
CREATE INDEX staged_document_source_purge_active_blocker_lookup_idx
  ON public.staged_document_source_purge_blockers (org_id, scope, legacy_staged_document_id, canonical_asset_id)
  WHERE released_at IS NULL;

CREATE OR REPLACE FUNCTION public.staged_document_source_purge_blocker_affects(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_canonical_asset_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.staged_document_source_purge_blockers AS blocker
    WHERE blocker.org_id = p_org_id AND blocker.released_at IS NULL
      AND (
        blocker.scope = 'organisation'
        OR (blocker.scope = 'legacy_source' AND blocker.legacy_staged_document_id = p_legacy_staged_document_id)
        OR (blocker.scope = 'canonical_asset' AND blocker.canonical_asset_id = p_canonical_asset_id)
      )
  )
$$;

-- Direct privileged repair writes retain a recovery fence.  Operational
-- hold/export/backup/recovery writers must instead call the service RPC below,
-- which serializes before intent and refuses to start after intent.
CREATE OR REPLACE FUNCTION public.reconcile_staged_document_source_purge_blocker_intents()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.released_at IS NULL AND (
    TG_OP = 'INSERT' OR OLD.released_at IS NOT NULL
    OR OLD.scope IS DISTINCT FROM NEW.scope
    OR OLD.org_id IS DISTINCT FROM NEW.org_id
    OR OLD.legacy_staged_document_id IS DISTINCT FROM NEW.legacy_staged_document_id
    OR OLD.canonical_asset_id IS DISTINCT FROM NEW.canonical_asset_id
  ) THEN
    UPDATE public.staged_document_source_purge_tombstones AS tombstone
    SET state = 'recovery_required', recovery_code = 'late_guard_blocker',
        verification_code = NULL, lease_token = NULL, lease_expires_at = NULL
    FROM public.staged_document_backfill_items AS map
    WHERE map.org_id = tombstone.org_id
      AND map.legacy_staged_document_id = tombstone.legacy_staged_document_id
      AND tombstone.state = 'delete_intended'
      AND map.org_id = NEW.org_id
      AND (
        NEW.scope = 'organisation'
        OR (NEW.scope = 'legacy_source' AND map.legacy_staged_document_id = NEW.legacy_staged_document_id)
        OR (NEW.scope = 'canonical_asset' AND map.canonical_asset_id = NEW.canonical_asset_id)
      );
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER staged_document_source_purge_blockers_reconcile_intents
  AFTER INSERT OR UPDATE ON public.staged_document_source_purge_blockers
  FOR EACH ROW EXECUTE FUNCTION public.reconcile_staged_document_source_purge_blocker_intents();

-- The only service authority for a future safety writer.  It locks the same
-- mapped sources used by the intent command before deciding.  Therefore a
-- writer that wins first records its blocker and causes intent to fail; a
-- writer that arrives after delete_intended receives purge_in_progress and
-- writes nothing.  This is the point-of-no-return: a physical delete cannot
-- begin while an external safety writer has successfully serialized.
CREATE OR REPLACE FUNCTION public.create_staged_document_source_purge_blocker(
  p_org_id uuid,
  p_scope public.staged_document_source_purge_blocker_scope,
  p_legacy_staged_document_id uuid DEFAULT NULL,
  p_canonical_asset_id uuid DEFAULT NULL,
  p_blocker_kind public.staged_document_source_purge_blocker_kind DEFAULT 'legal_hold'
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE blocker_id uuid;
BEGIN
  IF p_org_id IS NULL OR p_scope IS NULL OR p_blocker_kind IS NULL
    OR (p_scope = 'organisation' AND (p_legacy_staged_document_id IS NOT NULL OR p_canonical_asset_id IS NOT NULL))
    OR (p_scope = 'legacy_source' AND (p_legacy_staged_document_id IS NULL OR p_canonical_asset_id IS NOT NULL))
    OR (p_scope = 'canonical_asset' AND (p_legacy_staged_document_id IS NOT NULL OR p_canonical_asset_id IS NULL)) THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  -- Serialize with claim and intent via the authoritative mapped source row.
  PERFORM 1 FROM public.staged_document_backfill_items AS map
  WHERE map.org_id = p_org_id AND (
    p_scope = 'organisation'
    OR (p_scope = 'legacy_source' AND map.legacy_staged_document_id = p_legacy_staged_document_id)
    OR (p_scope = 'canonical_asset' AND map.canonical_asset_id = p_canonical_asset_id)
  ) FOR UPDATE;
  IF p_scope <> 'organisation' AND NOT FOUND THEN
    RETURN QUERY SELECT 'not_found'::text; RETURN;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.staged_document_source_purge_tombstones AS tombstone
    JOIN public.staged_document_backfill_items AS map
      ON map.org_id = tombstone.org_id AND map.legacy_staged_document_id = tombstone.legacy_staged_document_id
    WHERE tombstone.org_id = p_org_id AND tombstone.state = 'delete_intended'
      AND (p_scope = 'organisation'
        OR (p_scope = 'legacy_source' AND map.legacy_staged_document_id = p_legacy_staged_document_id)
        OR (p_scope = 'canonical_asset' AND map.canonical_asset_id = p_canonical_asset_id))
    FOR UPDATE OF tombstone
  ) THEN
    RETURN QUERY SELECT 'purge_in_progress'::text; RETURN;
  END IF;
  SELECT id INTO blocker_id FROM public.staged_document_source_purge_blockers
  WHERE org_id=p_org_id AND scope=p_scope AND blocker_kind=p_blocker_kind AND released_at IS NULL
    AND legacy_staged_document_id IS NOT DISTINCT FROM p_legacy_staged_document_id
    AND canonical_asset_id IS NOT DISTINCT FROM p_canonical_asset_id
  FOR UPDATE;
  IF blocker_id IS NOT NULL THEN RETURN QUERY SELECT 'already_active'::text; RETURN; END IF;
  INSERT INTO public.staged_document_source_purge_blockers(
    org_id,scope,legacy_staged_document_id,canonical_asset_id,blocker_kind
  ) VALUES (p_org_id,p_scope,p_legacy_staged_document_id,p_canonical_asset_id,p_blocker_kind);
  RETURN QUERY SELECT 'created'::text;
END $$;

-- Replace the original ready-Intake predicate with assignment-complete
-- immutable-document lineage.  A canonical copy is not redundant proof until
-- an assigned current document version references the exact same asset.
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
    JOIN public.matters AS assigned_matter
      ON assigned_matter.org_id = map.org_id AND assigned_matter.id = source.intake_matter_id
      AND assigned_matter.status = 'active' AND assigned_matter.deleted_at IS NULL
    JOIN public.file_assets AS asset
      ON asset.org_id = map.org_id AND asset.id = map.canonical_asset_id
    JOIN public.intake_items AS intake
      ON intake.org_id = map.org_id AND intake.id = map.canonical_intake_item_id
    JOIN public.intake_item_assignments AS assignment
      ON assignment.org_id = map.org_id AND assignment.intake_item_id = intake.id
    JOIN public.documents AS document_record
      ON document_record.org_id = map.org_id AND document_record.id = assignment.document_id
      AND document_record.matter_id = source.intake_matter_id
      AND document_record.record_state = 'active' AND document_record.deleted_at IS NULL
    JOIN public.document_versions AS version
      ON version.org_id = map.org_id AND version.id = document_record.current_version_id
      AND version.id = assignment.document_version_id
      AND version.document_id = document_record.id AND version.asset_id = map.canonical_asset_id
      AND version.state = 'current' AND version.validation_state = 'valid'
    JOIN public.staged_document_retirement_audit_items AS audit
      ON audit.org_id = map.org_id AND audit.legacy_staged_document_id = map.legacy_staged_document_id
    WHERE map.org_id = p_org_id
      AND map.legacy_staged_document_id = p_legacy_staged_document_id
      AND source.status IN ('pending_assignment', 'analyzing', 'ready_to_assign', 'failed')
      AND source.intake_matter_id IS NOT NULL
      AND public.staged_document_backfill_source_is_valid(source.org_id, source.storage_path, source.intake_matter_id)
      AND map.outcome = 'transfer_pending' AND map.transfer_completed_at IS NOT NULL
      AND map.observed_byte_size IS NOT NULL AND map.observed_sha256 ~ '^[0-9a-f]{64}$'
      AND asset.availability = 'available' AND NOT asset.legacy_staged_backfill_pending
      AND asset.storage_deleted_at IS NULL AND asset.byte_size = map.observed_byte_size
      AND asset.sha256 = map.observed_sha256
      AND intake.state = 'assigned' AND intake.assigned_at IS NOT NULL
      AND intake.asset_id = map.canonical_asset_id AND intake.intended_matter_id = source.intake_matter_id
      AND audit.outcome = 'verified_equal' AND audit.lease_expires_at IS NULL
      AND public.staged_document_source_purge_guard_coverage_is_current(map.org_id)
      AND (map.verification_lease_expires_at IS NULL OR map.verification_lease_expires_at <= now())
      AND (map.transfer_lease_expires_at IS NULL OR map.transfer_lease_expires_at <= now())
      AND NOT EXISTS (
        SELECT 1 FROM public.staged_document_legacy_action_leases AS action_lease
        WHERE action_lease.org_id = map.org_id
          AND action_lease.legacy_staged_document_id = map.legacy_staged_document_id
          AND action_lease.expires_at > now()
      )
      AND NOT public.staged_document_source_purge_blocker_affects(
        map.org_id, map.legacy_staged_document_id, map.canonical_asset_id
      )
      -- A running row without a lease is unknown work.  An expired lease is
      -- also retained until its owner reconciles it; purge never races that
      -- reconciliation by interpreting expiry as permission.
      AND NOT EXISTS (
        SELECT 1 FROM public.source_analysis_runs AS analysis
        WHERE analysis.org_id = map.org_id AND analysis.asset_id = map.canonical_asset_id
          AND analysis.state = 'running'
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.document_processing_runs AS run
        JOIN public.document_versions AS running_version
          ON running_version.id = run.document_version_id AND running_version.org_id = run.org_id
        WHERE run.org_id = map.org_id AND running_version.asset_id = map.canonical_asset_id
          AND run.state = 'running'
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.document_processing_recovery_cases AS recovery
        JOIN public.document_processing_runs AS run
          ON run.id = recovery.processing_run_id AND run.org_id = recovery.org_id
        JOIN public.document_versions AS recovery_version
          ON recovery_version.id = run.document_version_id AND recovery_version.org_id = run.org_id
        WHERE recovery.org_id = map.org_id AND recovery.state = 'open'
          AND recovery_version.asset_id = map.canonical_asset_id
      )
  )
$$;

-- Exhausted retries are terminal safe recovery, not an arithmetic error that
-- aborts the whole batch.  The map lock serializes the cap transition with
-- intent and future blocker writers; later candidates continue normally.
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
    SELECT map.legacy_staged_document_id, tombstone.attempt_count
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
    IF candidate.attempt_count >= 1000 THEN
      UPDATE public.staged_document_source_purge_tombstones AS tombstone
      SET state='recovery_required', recovery_code='attempt_cap_exhausted', verification_code=NULL,
          lease_token=NULL, lease_expires_at=NULL
      WHERE tombstone.org_id=p_org_id AND tombstone.legacy_staged_document_id=candidate.legacy_staged_document_id
        AND tombstone.state IN ('claimed','delete_intended') AND tombstone.attempt_count >= 1000
        AND (tombstone.lease_expires_at IS NULL OR tombstone.lease_expires_at <= now());
      CONTINUE;
    END IF;
    next_token := gen_random_uuid();
    INSERT INTO public.staged_document_source_purge_tombstones(
      org_id,legacy_staged_document_id,state,lease_token,lease_expires_at,attempt_count
    ) VALUES (p_org_id,candidate.legacy_staged_document_id,'claimed',next_token,now()+interval '10 minutes',1)
    ON CONFLICT ON CONSTRAINT staged_document_source_purge_tombstones_pkey DO UPDATE
      SET state='claimed', lease_token=EXCLUDED.lease_token, lease_expires_at=EXCLUDED.lease_expires_at,
          attempt_count=public.staged_document_source_purge_tombstones.attempt_count+1
      WHERE public.staged_document_source_purge_tombstones.state IN ('claimed','delete_intended')
        AND (public.staged_document_source_purge_tombstones.lease_expires_at IS NULL
          OR public.staged_document_source_purge_tombstones.lease_expires_at <= now())
        AND public.staged_document_source_purge_tombstones.attempt_count < 1000;
    IF FOUND THEN
      RETURN QUERY SELECT 'purge_required'::text,candidate.legacy_staged_document_id,next_token;
    ELSE
      -- A concurrent claimant reached the cap after candidate selection.
      UPDATE public.staged_document_source_purge_tombstones AS tombstone
      SET state='recovery_required', recovery_code='attempt_cap_exhausted', verification_code=NULL,
          lease_token=NULL, lease_expires_at=NULL
      WHERE tombstone.org_id=p_org_id AND tombstone.legacy_staged_document_id=candidate.legacy_staged_document_id
        AND tombstone.state IN ('claimed','delete_intended') AND tombstone.attempt_count >= 1000
        AND (tombstone.lease_expires_at IS NULL OR tombstone.lease_expires_at <= now());
    END IF;
  END LOOP;
END $$;

-- The existing grant keeps its no-key-on-failure surface.  Its visible code
-- now distinguishes missing/stale positive guard coverage from all other
-- fail-closed conditions; every key column still calls the authoritative
-- predicate above.
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
      WHEN NOT public.staged_document_source_purge_guard_coverage_is_current(p_org_id) THEN 'guard_coverage_incomplete'
      WHEN NOT public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id) THEN 'not_eligible'
      ELSE 'ok'
    END,
    CASE WHEN tombstone.lease_token = p_purge_lease_token AND tombstone.lease_expires_at > now()
      AND tombstone.state IN ('claimed', 'delete_intended')
      AND public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id)
      THEN 'staging' END,
    CASE WHEN tombstone.lease_token = p_purge_lease_token AND tombstone.lease_expires_at > now()
      AND tombstone.state IN ('claimed', 'delete_intended')
      AND public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id)
      THEN source.storage_path END,
    CASE WHEN tombstone.lease_token = p_purge_lease_token AND tombstone.lease_expires_at > now()
      AND tombstone.state IN ('claimed', 'delete_intended')
      AND public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id)
      THEN asset.bucket_id END,
    CASE WHEN tombstone.lease_token = p_purge_lease_token AND tombstone.lease_expires_at > now()
      AND tombstone.state IN ('claimed', 'delete_intended')
      AND public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id)
      THEN asset.object_key END,
    CASE WHEN tombstone.lease_token = p_purge_lease_token AND tombstone.lease_expires_at > now()
      AND tombstone.state IN ('claimed', 'delete_intended')
      AND public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id)
      THEN map.observed_byte_size END,
    CASE WHEN tombstone.lease_token = p_purge_lease_token AND tombstone.lease_expires_at > now()
      AND tombstone.state IN ('claimed', 'delete_intended')
      AND public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id)
      THEN map.observed_sha256 END
  FROM (SELECT 1) AS request
  LEFT JOIN public.staged_document_backfill_items AS map
    ON map.org_id = p_org_id AND map.legacy_staged_document_id = p_legacy_staged_document_id
  LEFT JOIN public.staged_document_source_purge_tombstones AS tombstone
    ON tombstone.org_id = map.org_id AND tombstone.legacy_staged_document_id = map.legacy_staged_document_id
  LEFT JOIN public.staged_documents AS source
    ON source.org_id = map.org_id AND source.id = map.legacy_staged_document_id
  LEFT JOIN public.file_assets AS asset
    ON asset.org_id = map.org_id AND asset.id = map.canonical_asset_id
$$;

-- Intent and confirmation must each repeat the same authoritative predicate.
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
    RETURN QUERY SELECT 'invalid_observation'::text; RETURN;
  END IF;
  SELECT * INTO map_row FROM public.staged_document_backfill_items AS map
    WHERE map.org_id = p_org_id AND map.legacy_staged_document_id = p_legacy_staged_document_id FOR UPDATE;
  SELECT * INTO tombstone_row FROM public.staged_document_source_purge_tombstones AS tombstone
    WHERE tombstone.org_id = p_org_id AND tombstone.legacy_staged_document_id = p_legacy_staged_document_id FOR UPDATE;
  IF map_row.id IS NULL OR tombstone_row.legacy_staged_document_id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text; RETURN;
  END IF;
  IF tombstone_row.state IN ('deleted', 'recovery_required') THEN
    RETURN QUERY SELECT tombstone_row.state::text; RETURN;
  END IF;
  IF tombstone_row.lease_token IS DISTINCT FROM p_purge_lease_token
    OR tombstone_row.lease_expires_at IS NULL OR tombstone_row.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'lease_not_held'::text; RETURN;
  END IF;
  IF NOT public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id) THEN
    RETURN QUERY SELECT CASE WHEN NOT public.staged_document_source_purge_guard_coverage_is_current(p_org_id)
      THEN 'guard_coverage_incomplete' ELSE 'not_eligible' END; RETURN;
  END IF;
  IF p_source_observed_bytes <> map_row.observed_byte_size
    OR p_destination_observed_bytes <> map_row.observed_byte_size
    OR p_source_sha256 <> map_row.observed_sha256
    OR p_destination_sha256 <> map_row.observed_sha256
    OR p_source_observed_bytes <> p_destination_observed_bytes
    OR p_source_sha256 <> p_destination_sha256 THEN
    RETURN QUERY SELECT 'observation_conflict'::text; RETURN;
  END IF;
  UPDATE public.staged_document_source_purge_tombstones
  SET state = 'delete_intended', intent_created_at = coalesce(intent_created_at, now()),
      storage_delete_attempted_at = now(), verification_code = NULL, recovery_code = NULL
  WHERE org_id = p_org_id AND legacy_staged_document_id = p_legacy_staged_document_id;
  RETURN QUERY SELECT 'delete_intended'::text;
END $$;

-- A worker that observes a revoked second grant after durable intent uses
-- this same content-free terminal fence.  It is deliberately not available
-- to browser/service roles except through the already leased recovery RPC.
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
      'source_pdf_invalid', 'destination_pdf_invalid', 'database_inconsistent',
      'late_guard_blocker', 'late_eligibility_blocker'
    ) THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  SELECT * INTO tombstone_row FROM public.staged_document_source_purge_tombstones AS tombstone
    WHERE tombstone.org_id = p_org_id AND tombstone.legacy_staged_document_id = p_legacy_staged_document_id FOR UPDATE;
  IF tombstone_row.legacy_staged_document_id IS NULL THEN RETURN QUERY SELECT 'not_found'::text; RETURN; END IF;
  IF tombstone_row.state IN ('deleted', 'recovery_required') THEN RETURN QUERY SELECT tombstone_row.state::text; RETURN; END IF;
  IF tombstone_row.lease_token IS DISTINCT FROM p_purge_lease_token
    OR tombstone_row.lease_expires_at IS NULL OR tombstone_row.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'lease_not_held'::text; RETURN;
  END IF;
  UPDATE public.staged_document_source_purge_tombstones
  SET state = 'recovery_required', recovery_code = p_recovery_code,
      verification_code = NULL, lease_token = NULL, lease_expires_at = NULL
  WHERE org_id = p_org_id AND legacy_staged_document_id = p_legacy_staged_document_id;
  RETURN QUERY SELECT 'recovery_required'::text;
END $$;

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
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  SELECT * INTO tombstone_row FROM public.staged_document_source_purge_tombstones AS tombstone
    WHERE tombstone.org_id = p_org_id AND tombstone.legacy_staged_document_id = p_legacy_staged_document_id FOR UPDATE;
  IF tombstone_row.legacy_staged_document_id IS NULL THEN RETURN QUERY SELECT 'not_found'::text; RETURN; END IF;
  IF tombstone_row.state = 'deleted' THEN RETURN QUERY SELECT 'already_deleted'::text; RETURN; END IF;
  IF tombstone_row.state <> 'delete_intended'
    AND NOT (p_confirmation = 'storage_missing_after_intent'
      AND tombstone_row.state = 'claimed' AND tombstone_row.intent_created_at IS NOT NULL) THEN
    RETURN QUERY SELECT tombstone_row.state::text; RETURN;
  END IF;
  IF tombstone_row.lease_token IS DISTINCT FROM p_purge_lease_token
    OR tombstone_row.lease_expires_at IS NULL OR tombstone_row.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'lease_not_held'::text; RETURN;
  END IF;
  IF NOT public.staged_document_source_purge_is_eligible(p_org_id, p_legacy_staged_document_id) THEN
    -- The external effect has already been reported.  A changed guard or
    -- eligibility fact must become durable recovery, never a stranded intent.
    UPDATE public.staged_document_source_purge_tombstones
    SET state = 'recovery_required',
        recovery_code = CASE WHEN NOT public.staged_document_source_purge_guard_coverage_is_current(p_org_id)
          THEN 'late_guard_blocker' ELSE 'late_eligibility_blocker' END,
        verification_code = NULL, lease_token = NULL, lease_expires_at = NULL
    WHERE org_id = p_org_id AND legacy_staged_document_id = p_legacy_staged_document_id;
    RETURN QUERY SELECT 'recovery_required'::text; RETURN;
  END IF;
  UPDATE public.staged_document_source_purge_tombstones
  SET state = 'deleted', storage_deleted_at = now(), verification_code = 'fresh_equal_pdf',
      recovery_code = NULL, lease_token = NULL, lease_expires_at = NULL
  WHERE org_id = p_org_id AND legacy_staged_document_id = p_legacy_staged_document_id;
  RETURN QUERY SELECT 'deleted'::text;
END $$;

CREATE OR REPLACE VIEW public.staged_document_source_purge_reports AS
WITH orgs AS (
  SELECT org_id FROM public.staged_document_backfill_items
  UNION SELECT org_id FROM public.staged_document_source_purge_tombstones
  UNION SELECT org_id FROM public.staged_document_source_purge_guard_coverage
), counts AS (
  SELECT
    org.org_id,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map
      LEFT JOIN public.staged_document_source_purge_tombstones AS tombstone
        ON tombstone.org_id = map.org_id AND tombstone.legacy_staged_document_id = map.legacy_staged_document_id
      WHERE map.org_id = org.org_id AND (tombstone.state IS NULL OR tombstone.state IN ('claimed', 'delete_intended'))
        AND public.staged_document_source_purge_is_eligible(map.org_id, map.legacy_staged_document_id)
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
      WHERE blocker.org_id = org.org_id AND blocker.released_at IS NULL)::bigint AS active_blocker_count,
    (SELECT count(*) FROM public.staged_document_source_purge_guard_coverage AS coverage
      WHERE coverage.org_id = org.org_id AND coverage.coverage_state = 'unknown')::bigint AS guard_coverage_unknown_count,
    (SELECT count(*) FROM public.staged_document_source_purge_guard_coverage AS coverage
      WHERE coverage.org_id = org.org_id
        AND (coverage.coverage_state <> 'unknown' AND (coverage.valid_until IS NULL OR coverage.valid_until <= now())))::bigint AS guard_coverage_stale_count,
    public.staged_document_source_purge_guard_coverage_is_current(org.org_id) AS guard_coverage_complete
  FROM orgs AS org
)
SELECT * FROM counts;

ALTER TABLE public.staged_document_source_purge_guard_coverage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staged_document_source_purge_guard_coverage FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.staged_document_source_purge_guard_coverage FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.seed_staged_document_source_purge_guard_coverage(),
  public.attest_staged_document_source_purge_guard_coverage(uuid, public.staged_document_source_purge_guard_kind, public.staged_document_source_purge_guard_coverage_state, timestamptz),
  public.staged_document_source_purge_guard_coverage_is_current(uuid),
  public.reconcile_staged_document_source_purge_guard_coverage(),
  public.staged_document_source_purge_blocker_affects(uuid, uuid, uuid),
  public.reconcile_staged_document_source_purge_blocker_intents(),
  public.create_staged_document_source_purge_blocker(uuid, public.staged_document_source_purge_blocker_scope, uuid, uuid, public.staged_document_source_purge_blocker_kind)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.attest_staged_document_source_purge_guard_coverage(uuid, public.staged_document_source_purge_guard_kind, public.staged_document_source_purge_guard_coverage_state, timestamptz)
  TO postgres;
-- The service-only count report evaluates this content-free boolean under the
-- caller's role.  It is not attestation authority and exposes no guard data.
GRANT EXECUTE ON FUNCTION public.staged_document_source_purge_guard_coverage_is_current(uuid)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.create_staged_document_source_purge_blocker(uuid, public.staged_document_source_purge_blocker_scope, uuid, uuid, public.staged_document_source_purge_blocker_kind)
  TO service_role;

COMMENT ON TABLE public.staged_document_source_purge_guard_coverage IS
  'PostgreSQL-owner-only, content-free proof of current legal-hold, export, backup, recovery, and retention-lock coverage. Unknown or expired coverage blocks staged-source purge.';
COMMENT ON FUNCTION public.attest_staged_document_source_purge_guard_coverage(uuid, public.staged_document_source_purge_guard_kind, public.staged_document_source_purge_guard_coverage_state, timestamptz) IS
  'Operational procedure: PostgreSQL owner verifies one authoritative guard, then attests it for no more than 24 hours. This function does not itself verify or clear any hold/export/backup/recovery system.';
COMMENT ON TABLE public.staged_document_source_purge_blockers IS
  'Content-free purge blockers scoped to organisation, canonical asset, or legacy source. Future safety writers must use the service-only creation RPC, which serializes before delete intent and refuses purge_in_progress after intent.';

COMMIT;
