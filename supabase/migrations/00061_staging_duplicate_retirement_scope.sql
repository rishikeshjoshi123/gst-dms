-- Align staged-source cleanup with the approved storage ownership boundary.
--
-- An unassigned Intake item is never an automatic purge candidate.  After
-- assignment, the staging object is only a transport duplicate once the exact
-- canonical document version has been independently proved equal.  Matter
-- legal hold, export, backup, and retention policy govern that canonical
-- document and its Trash lifecycle; they do not preserve a redundant staging
-- object.  Staging-specific recovery conflicts remain fail-closed.
BEGIN;

DROP VIEW public.staged_document_source_purge_reports;

DROP TRIGGER staged_document_source_purge_guard_coverage_reconcile_intents
  ON public.staged_document_source_purge_guard_coverage;
DROP TRIGGER organisations_seed_staged_document_source_purge_guard_coverage
  ON public.organisations;

DROP FUNCTION public.attest_staged_document_source_purge_guard_coverage(
  uuid,
  public.staged_document_source_purge_guard_kind,
  public.staged_document_source_purge_guard_coverage_state,
  timestamptz
);
DROP FUNCTION public.reconcile_staged_document_source_purge_guard_coverage();
DROP FUNCTION public.seed_staged_document_source_purge_guard_coverage();
DROP TABLE public.staged_document_source_purge_guard_coverage;
DROP TYPE public.staged_document_source_purge_guard_coverage_state;
DROP TYPE public.staged_document_source_purge_guard_kind;

-- Kept as a compatibility shim because the already-deployed 00060 eligibility,
-- grant, intent, and confirmation functions call it.  It no longer represents
-- an operational attestation or a policy gate.
CREATE OR REPLACE FUNCTION public.staged_document_source_purge_guard_coverage_is_current(
  p_org_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT p_org_id IS NOT NULL
$$;

-- Only a staging/canonical integrity recovery investigation can block removal
-- of the redundant staging object.  Matter-level safety controls apply to the
-- canonical document and Trash hierarchy instead.
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
    SELECT 1
    FROM public.staged_document_source_purge_blockers AS blocker
    WHERE blocker.org_id = p_org_id
      AND blocker.released_at IS NULL
      AND blocker.blocker_kind = 'recovery'
      AND (
        blocker.scope = 'organisation'
        OR (blocker.scope = 'legacy_source'
          AND blocker.legacy_staged_document_id = p_legacy_staged_document_id)
        OR (blocker.scope = 'canonical_asset'
          AND blocker.canonical_asset_id = p_canonical_asset_id)
      )
  )
$$;

CREATE OR REPLACE FUNCTION public.reconcile_staged_document_source_purge_blocker_intents()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.blocker_kind = 'recovery' AND NEW.released_at IS NULL AND (
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
        OR (NEW.scope = 'legacy_source'
          AND map.legacy_staged_document_id = NEW.legacy_staged_document_id)
        OR (NEW.scope = 'canonical_asset'
          AND map.canonical_asset_id = NEW.canonical_asset_id)
      );
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.create_staged_document_source_purge_blocker(
  p_org_id uuid,
  p_scope public.staged_document_source_purge_blocker_scope,
  p_legacy_staged_document_id uuid DEFAULT NULL,
  p_canonical_asset_id uuid DEFAULT NULL,
  p_blocker_kind public.staged_document_source_purge_blocker_kind DEFAULT 'recovery'
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE blocker_id uuid;
BEGIN
  IF p_org_id IS NULL OR p_scope IS NULL OR p_blocker_kind IS NULL
    OR (p_scope = 'organisation'
      AND (p_legacy_staged_document_id IS NOT NULL OR p_canonical_asset_id IS NOT NULL))
    OR (p_scope = 'legacy_source'
      AND (p_legacy_staged_document_id IS NULL OR p_canonical_asset_id IS NOT NULL))
    OR (p_scope = 'canonical_asset'
      AND (p_legacy_staged_document_id IS NOT NULL OR p_canonical_asset_id IS NULL)) THEN
    RETURN QUERY SELECT 'invalid_request'::text;
    RETURN;
  END IF;
  IF p_blocker_kind <> 'recovery' THEN
    RETURN QUERY SELECT 'not_applicable'::text;
    RETURN;
  END IF;

  PERFORM 1
  FROM public.staged_document_backfill_items AS map
  WHERE map.org_id = p_org_id
    AND (
      p_scope = 'organisation'
      OR (p_scope = 'legacy_source'
        AND map.legacy_staged_document_id = p_legacy_staged_document_id)
      OR (p_scope = 'canonical_asset'
        AND map.canonical_asset_id = p_canonical_asset_id)
    )
  FOR UPDATE;
  IF p_scope <> 'organisation' AND NOT FOUND THEN
    RETURN QUERY SELECT 'not_found'::text;
    RETURN;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.staged_document_source_purge_tombstones AS tombstone
    JOIN public.staged_document_backfill_items AS map
      ON map.org_id = tombstone.org_id
      AND map.legacy_staged_document_id = tombstone.legacy_staged_document_id
    WHERE tombstone.org_id = p_org_id
      AND tombstone.state = 'delete_intended'
      AND (
        p_scope = 'organisation'
        OR (p_scope = 'legacy_source'
          AND map.legacy_staged_document_id = p_legacy_staged_document_id)
        OR (p_scope = 'canonical_asset'
          AND map.canonical_asset_id = p_canonical_asset_id)
      )
    FOR UPDATE OF tombstone
  ) THEN
    RETURN QUERY SELECT 'purge_in_progress'::text;
    RETURN;
  END IF;
  SELECT id
  INTO blocker_id
  FROM public.staged_document_source_purge_blockers
  WHERE org_id = p_org_id
    AND scope = p_scope
    AND blocker_kind = p_blocker_kind
    AND released_at IS NULL
    AND legacy_staged_document_id IS NOT DISTINCT FROM p_legacy_staged_document_id
    AND canonical_asset_id IS NOT DISTINCT FROM p_canonical_asset_id
  FOR UPDATE;
  IF blocker_id IS NOT NULL THEN
    RETURN QUERY SELECT 'already_active'::text;
    RETURN;
  END IF;
  INSERT INTO public.staged_document_source_purge_blockers(
    org_id, scope, legacy_staged_document_id, canonical_asset_id, blocker_kind
  ) VALUES (
    p_org_id, p_scope, p_legacy_staged_document_id, p_canonical_asset_id, p_blocker_kind
  );
  RETURN QUERY SELECT 'created'::text;
END $$;

CREATE VIEW public.staged_document_source_purge_reports AS
WITH orgs AS (
  SELECT org_id FROM public.staged_document_backfill_items
  UNION SELECT org_id FROM public.staged_document_source_purge_tombstones
), counts AS (
  SELECT
    org.org_id,
    (SELECT count(*) FROM public.staged_document_backfill_items AS map
      LEFT JOIN public.staged_document_source_purge_tombstones AS tombstone
        ON tombstone.org_id = map.org_id
        AND tombstone.legacy_staged_document_id = map.legacy_staged_document_id
      WHERE map.org_id = org.org_id
        AND (tombstone.state IS NULL OR tombstone.state IN ('claimed', 'delete_intended'))
        AND public.staged_document_source_purge_is_eligible(
          map.org_id, map.legacy_staged_document_id
        )
    )::bigint AS verification_candidate_count,
    (SELECT count(*) FROM public.staged_document_source_purge_tombstones AS tombstone
      WHERE tombstone.org_id = org.org_id
        AND tombstone.state = 'delete_intended')::bigint AS delete_intended_count,
    (SELECT count(*) FROM public.staged_document_source_purge_tombstones AS tombstone
      WHERE tombstone.org_id = org.org_id
        AND tombstone.state = 'deleted')::bigint AS deleted_tombstone_count,
    (SELECT count(*) FROM public.staged_document_source_purge_tombstones AS tombstone
      WHERE tombstone.org_id = org.org_id
        AND tombstone.state = 'recovery_required')::bigint AS recovery_required_count,
    (SELECT count(*) FROM public.staged_document_source_purge_tombstones AS tombstone
      WHERE tombstone.org_id = org.org_id
        AND tombstone.state IN ('claimed', 'delete_intended')
        AND tombstone.lease_expires_at > now())::bigint AS active_purge_lease_count,
    (SELECT count(*) FROM public.staged_document_source_purge_blockers AS blocker
      WHERE blocker.org_id = org.org_id
        AND blocker.released_at IS NULL
        AND blocker.blocker_kind = 'recovery')::bigint AS active_blocker_count
  FROM orgs AS org
)
SELECT * FROM counts;

REVOKE ALL ON FUNCTION public.staged_document_source_purge_guard_coverage_is_current(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.staged_document_source_purge_blocker_affects(uuid, uuid, uuid),
  public.reconcile_staged_document_source_purge_blocker_intents(),
  public.create_staged_document_source_purge_blocker(
    uuid,
    public.staged_document_source_purge_blocker_scope,
    uuid,
    uuid,
    public.staged_document_source_purge_blocker_kind
  )
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.staged_document_source_purge_reports
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_staged_document_source_purge_blocker(
  uuid,
  public.staged_document_source_purge_blocker_scope,
  uuid,
  uuid,
  public.staged_document_source_purge_blocker_kind
) TO service_role;
GRANT SELECT ON TABLE public.staged_document_source_purge_reports TO service_role, postgres;

COMMENT ON FUNCTION public.staged_document_source_purge_guard_coverage_is_current(uuid) IS
  'Compatibility shim for migration 00060. Staging cleanup is not gated by matter legal-hold, export, backup, or retention policy.';
COMMENT ON TABLE public.staged_document_source_purge_blockers IS
  'Content-free staging recovery blockers scoped to organisation, canonical asset, or legacy source. Non-recovery policy belongs to the canonical document and Trash hierarchy.';
COMMENT ON VIEW public.staged_document_source_purge_reports IS
  'Content-free per-organisation staging duplicate cleanup counts. Active blockers count staging-specific recovery investigations only.';

COMMIT;
