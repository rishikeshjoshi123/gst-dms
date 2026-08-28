-- Resumable, service-only staged-document backfill foundation.
--
-- This migration intentionally does not move, copy, delete, or rewrite a
-- legacy staged object/row. A trusted worker verifies an object outside SQL,
-- then records only safe observation facts here. A verified unique source is
-- represented only by a quarantined canonical asset and a transfer-pending
-- map; the later controlled-transfer tranche must make the canonical object
-- available and create ordinary Intake before validation or placement.
BEGIN;

CREATE TYPE public.staged_document_backfill_outcome AS ENUM (
  'verification_required',
  'transfer_pending',
  'missing_object',
  'unreadable_source',
  'malformed_pdf',
  'encrypted_pdf',
  'non_pdf',
  'oversize',
  'invalid_lineage',
  'duplicate_reference',
  'already_migrated'
);

-- The historical table has only a primary key. Make its tenant identity
-- referenceable without changing its data or its legacy read/write contract.
CREATE UNIQUE INDEX staged_documents_org_id_id_unique
  ON public.staged_documents (org_id, id);

-- Canonical assets created from staging are deliberately quarantined until a
-- later worker copies the verified source into their canonical private key.
-- This prevents both signing and terminal-storage cleanup from treating a
-- not-yet-copied destination as an ordinary failed object.
ALTER TABLE public.file_assets
  ADD COLUMN legacy_staged_backfill_pending boolean NOT NULL DEFAULT false;
ALTER TABLE public.file_assets
  ADD CONSTRAINT file_assets_legacy_staged_backfill_pending_check
  CHECK (
    NOT legacy_staged_backfill_pending
    OR (availability = 'quarantined' AND storage_deleted_at IS NULL)
  );

CREATE TYPE public.staged_document_backfill_source_result AS ENUM (
  'valid_pdf',
  'missing',
  'unreadable',
  'malformed_pdf',
  'encrypted_pdf',
  'non_pdf',
  'oversize'
);

CREATE TABLE public.staged_document_backfill_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  legacy_staged_document_id uuid NOT NULL,
  safe_item_key text NOT NULL,
  outcome public.staged_document_backfill_outcome NOT NULL DEFAULT 'verification_required',
  canonical_asset_id uuid,
  canonical_intake_item_id uuid,
  duplicate_asset_id uuid,
  observed_sha256 text,
  observed_byte_size bigint,
  safe_reason_code text,
  verification_attempt_count integer NOT NULL DEFAULT 0 CHECK (verification_attempt_count >= 0),
  verification_lease_token uuid,
  verification_lease_expires_at timestamptz,
  first_claimed_at timestamptz,
  externally_verified_at timestamptz,
  terminal_classified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT staged_document_backfill_items_source_fkey
    FOREIGN KEY (org_id, legacy_staged_document_id)
    REFERENCES public.staged_documents(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT staged_document_backfill_items_asset_fkey
    FOREIGN KEY (org_id, canonical_asset_id)
    REFERENCES public.file_assets(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT staged_document_backfill_items_intake_fkey
    FOREIGN KEY (org_id, canonical_intake_item_id)
    REFERENCES public.intake_items(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT staged_document_backfill_items_duplicate_asset_fkey
    FOREIGN KEY (org_id, duplicate_asset_id)
    REFERENCES public.file_assets(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT staged_document_backfill_items_source_unique
    UNIQUE (org_id, legacy_staged_document_id),
  CONSTRAINT staged_document_backfill_items_safe_key_unique
    UNIQUE (org_id, safe_item_key),
  CONSTRAINT staged_document_backfill_items_safe_key_format
    CHECK (safe_item_key ~ '^legacy-staged/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),
  CONSTRAINT staged_document_backfill_items_reason_safe
    CHECK (safe_reason_code IS NULL OR safe_reason_code ~ '^[a-z][a-z0-9_]{0,63}$'),
  CONSTRAINT staged_document_backfill_items_observation_safe
    CHECK (
      (observed_sha256 IS NULL AND observed_byte_size IS NULL)
      OR (observed_sha256 ~ '^[0-9a-f]{64}$' AND observed_byte_size > 0)
    ),
  CONSTRAINT staged_document_backfill_items_lease_consistent
    CHECK (
      (verification_lease_token IS NULL AND verification_lease_expires_at IS NULL)
      OR (verification_lease_token IS NOT NULL AND verification_lease_expires_at IS NOT NULL)
    ),
  CONSTRAINT staged_document_backfill_items_outcome_consistent
    CHECK (
      (outcome = 'verification_required'
        AND canonical_asset_id IS NULL AND canonical_intake_item_id IS NULL AND duplicate_asset_id IS NULL
        AND terminal_classified_at IS NULL)
      OR (outcome = 'transfer_pending'
        AND canonical_asset_id IS NOT NULL AND canonical_intake_item_id IS NULL AND duplicate_asset_id IS NULL
        AND observed_sha256 IS NOT NULL AND observed_byte_size IS NOT NULL
        AND terminal_classified_at IS NOT NULL)
      OR (outcome = 'duplicate_reference'
        AND canonical_asset_id IS NULL AND canonical_intake_item_id IS NULL AND duplicate_asset_id IS NOT NULL
        AND terminal_classified_at IS NOT NULL)
      OR (outcome IN ('missing_object', 'unreadable_source', 'malformed_pdf', 'encrypted_pdf', 'non_pdf', 'oversize', 'invalid_lineage', 'already_migrated')
        AND canonical_asset_id IS NULL AND canonical_intake_item_id IS NULL AND duplicate_asset_id IS NULL
        AND terminal_classified_at IS NOT NULL)
    )
);
CREATE INDEX staged_document_backfill_items_claim_idx
  ON public.staged_document_backfill_items (org_id, outcome, verification_lease_expires_at, created_at)
  WHERE outcome = 'verification_required';

CREATE OR REPLACE FUNCTION public.staged_document_backfill_touch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;
CREATE TRIGGER staged_document_backfill_items_touch
  BEFORE UPDATE ON public.staged_document_backfill_items
  FOR EACH ROW EXECUTE FUNCTION public.staged_document_backfill_touch();

-- The legacy Storage policy only permits the historical namespace
-- staging/{org UUID}/{temporary UUID}/original.pdf. Do not hand a worker a
-- path unless it matches that exact namespace: the bucket is supplied
-- separately, and path traversal, foreign tenant prefixes, and alternate
-- filenames are all invalid lineage rather than objects to inspect.
CREATE OR REPLACE FUNCTION public.staged_document_backfill_storage_path_is_valid(
  p_org_id uuid,
  p_storage_path text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT p_org_id IS NOT NULL
    AND p_storage_path ~ (
      '^staging/' || p_org_id::text ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/original[.]pdf$'
    )
$$;

CREATE OR REPLACE FUNCTION public.staged_document_backfill_source_is_valid(
  p_org_id uuid,
  p_storage_path text,
  p_intake_matter_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT public.staged_document_backfill_storage_path_is_valid(p_org_id, p_storage_path)
    AND (p_intake_matter_id IS NULL OR EXISTS (
      SELECT 1 FROM public.matters AS matter
      WHERE matter.id = p_intake_matter_id AND matter.org_id = p_org_id
    ))
$$;

-- The verifier receives a raw legacy path only through this leased grant.
-- Other service operations receive opaque IDs or fence codes, never a path.
CREATE OR REPLACE FUNCTION public.get_staged_document_backfill_source_grant(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_verification_lease_token uuid
)
RETURNS TABLE(code text, bucket_id text, object_key text)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT CASE
           WHEN m.id IS NULL OR s.id IS NULL THEN 'not_found'
           WHEN m.outcome <> 'verification_required' THEN m.outcome::text
           WHEN m.verification_lease_token IS DISTINCT FROM p_verification_lease_token
             OR m.verification_lease_expires_at IS NULL OR m.verification_lease_expires_at <= now()
             THEN 'lease_not_held'
           WHEN NOT public.staged_document_backfill_source_is_valid(s.org_id, s.storage_path, s.intake_matter_id)
             THEN 'invalid_lineage'
           ELSE 'ok'
         END,
         CASE
           WHEN m.outcome = 'verification_required'
             AND m.verification_lease_token = p_verification_lease_token
             AND m.verification_lease_expires_at > now()
             AND public.staged_document_backfill_source_is_valid(s.org_id, s.storage_path, s.intake_matter_id)
             THEN 'staging'
           ELSE NULL
         END,
         CASE
           WHEN m.outcome = 'verification_required'
             AND m.verification_lease_token = p_verification_lease_token
             AND m.verification_lease_expires_at > now()
             AND public.staged_document_backfill_source_is_valid(s.org_id, s.storage_path, s.intake_matter_id)
             THEN s.storage_path
           ELSE NULL
         END
  FROM public.staged_document_backfill_items AS m
  LEFT JOIN public.staged_documents AS s
    ON s.id = m.legacy_staged_document_id AND s.org_id = m.org_id
  WHERE m.org_id = p_org_id AND m.legacy_staged_document_id = p_legacy_staged_document_id;
$$;

-- The compatibility adapter and every remaining legacy mutation path use
-- these small service-only projections. A mapping fences a source regardless
-- of its outcome, including terminal classifications, so it cannot be copied,
-- assigned, retried, or deleted through the legacy workflow.
CREATE OR REPLACE FUNCTION public.get_staged_document_backfill_adapter_fences(p_org_id uuid)
RETURNS TABLE(legacy_staged_document_id uuid)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT m.legacy_staged_document_id
  FROM public.staged_document_backfill_items AS m
  WHERE m.org_id = p_org_id
$$;

CREATE OR REPLACE FUNCTION public.get_staged_document_backfill_action_guard(
  p_org_id uuid,
  p_legacy_staged_document_id uuid
)
RETURNS TABLE(code text)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT CASE
    WHEN EXISTS (
      SELECT 1 FROM public.staged_document_backfill_items AS m
      WHERE m.org_id = p_org_id AND m.legacy_staged_document_id = p_legacy_staged_document_id
    ) THEN 'backfill_fenced'
    WHEN EXISTS (
      SELECT 1 FROM public.staged_documents AS s
      WHERE s.org_id = p_org_id AND s.id = p_legacy_staged_document_id
    ) THEN 'ok'
    ELSE 'not_found'
  END
$$;

CREATE OR REPLACE FUNCTION public.prevent_mapped_staged_document_legacy_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE source_id uuid; source_org_id uuid;
BEGIN
  source_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;
  source_org_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.org_id ELSE NEW.org_id END;
  IF EXISTS (
    SELECT 1 FROM public.staged_document_backfill_items AS m
    WHERE m.org_id = source_org_id AND m.legacy_staged_document_id = source_id
  ) THEN
    RAISE EXCEPTION 'mapped staged document is fenced from legacy mutation';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER staged_documents_prevent_mapped_legacy_mutation
  BEFORE UPDATE OR DELETE ON public.staged_documents
  FOR EACH ROW EXECUTE FUNCTION public.prevent_mapped_staged_document_legacy_mutation();

-- A legacy action must reserve its source before touching Storage.  The
-- reservation and the backfill claim both lock the same staged row, making a
-- mapping and an old-flow copy/delete mutually exclusive rather than merely
-- relying on an application-level check made before a slow Storage call.
CREATE TYPE public.staged_document_legacy_action_kind AS ENUM (
  'assign', 'discard', 'analyze'
);

CREATE TABLE public.staged_document_legacy_action_leases (
  org_id uuid NOT NULL,
  legacy_staged_document_id uuid NOT NULL,
  action_kind public.staged_document_legacy_action_kind NOT NULL,
  lease_token uuid NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (org_id, legacy_staged_document_id),
  FOREIGN KEY (org_id, legacy_staged_document_id)
    REFERENCES public.staged_documents(org_id, id) ON DELETE CASCADE
);
CREATE INDEX staged_document_legacy_action_leases_expiry_idx
  ON public.staged_document_legacy_action_leases (expires_at);

CREATE OR REPLACE FUNCTION public.reserve_legacy_staged_document_action(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_action_kind public.staged_document_legacy_action_kind
)
RETURNS TABLE(code text, lease_token uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE source_row public.staged_documents%ROWTYPE;
DECLARE existing_lease public.staged_document_legacy_action_leases%ROWTYPE;
DECLARE next_token uuid;
BEGIN
  SELECT * INTO source_row FROM public.staged_documents AS s
  WHERE s.org_id = p_org_id AND s.id = p_legacy_staged_document_id
  FOR UPDATE;
  IF source_row.id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid;
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM public.staged_document_backfill_items AS m
             WHERE m.org_id = p_org_id AND m.legacy_staged_document_id = p_legacy_staged_document_id) THEN
    RETURN QUERY SELECT 'backfill_fenced'::text, NULL::uuid;
    RETURN;
  END IF;
  IF NOT public.staged_document_backfill_source_is_valid(source_row.org_id, source_row.storage_path, source_row.intake_matter_id) THEN
    RETURN QUERY SELECT 'invalid_lineage'::text, NULL::uuid;
    RETURN;
  END IF;
  SELECT * INTO existing_lease FROM public.staged_document_legacy_action_leases AS l
  WHERE l.org_id = p_org_id AND l.legacy_staged_document_id = p_legacy_staged_document_id
  FOR UPDATE;
  IF existing_lease.lease_token IS NOT NULL AND existing_lease.expires_at > now() THEN
    RETURN QUERY SELECT 'action_reserved'::text, NULL::uuid;
    RETURN;
  END IF;
  DELETE FROM public.staged_document_legacy_action_leases AS l
  WHERE l.org_id = p_org_id AND l.legacy_staged_document_id = p_legacy_staged_document_id;
  next_token := gen_random_uuid();
  INSERT INTO public.staged_document_legacy_action_leases (
    org_id, legacy_staged_document_id, action_kind, lease_token, expires_at
  ) VALUES (p_org_id, p_legacy_staged_document_id, p_action_kind, next_token, now() + interval '15 minutes');
  RETURN QUERY SELECT 'ok'::text, next_token;
END $$;

-- All paths returned from a legacy source are database-issued.  The caller
-- cannot substitute a browser/task payload path, and an expired/missing lease
-- deliberately returns no object key.
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
AS $$
  SELECT CASE
    WHEN s.id IS NULL THEN 'not_found'
    WHEN EXISTS (SELECT 1 FROM public.staged_document_backfill_items m
                 WHERE m.org_id = p_org_id AND m.legacy_staged_document_id = p_legacy_staged_document_id) THEN 'backfill_fenced'
    WHEN l.lease_token IS NULL OR l.lease_token IS DISTINCT FROM p_lease_token
      OR l.action_kind IS DISTINCT FROM p_action_kind OR l.expires_at <= now() THEN 'lease_not_held'
    WHEN NOT public.staged_document_backfill_source_is_valid(s.org_id, s.storage_path, s.intake_matter_id) THEN 'invalid_lineage'
    ELSE 'ok' END,
    CASE WHEN l.lease_token = p_lease_token AND l.action_kind = p_action_kind AND l.expires_at > now()
      AND NOT EXISTS (SELECT 1 FROM public.staged_document_backfill_items m WHERE m.org_id = p_org_id AND m.legacy_staged_document_id = p_legacy_staged_document_id)
      AND public.staged_document_backfill_source_is_valid(s.org_id, s.storage_path, s.intake_matter_id) THEN 'staging' ELSE NULL END,
    CASE WHEN l.lease_token = p_lease_token AND l.action_kind = p_action_kind AND l.expires_at > now()
      AND NOT EXISTS (SELECT 1 FROM public.staged_document_backfill_items m WHERE m.org_id = p_org_id AND m.legacy_staged_document_id = p_legacy_staged_document_id)
      AND public.staged_document_backfill_source_is_valid(s.org_id, s.storage_path, s.intake_matter_id) THEN s.storage_path ELSE NULL END,
    CASE WHEN l.lease_token = p_lease_token AND l.action_kind = p_action_kind AND l.expires_at > now()
      AND NOT EXISTS (SELECT 1 FROM public.staged_document_backfill_items m WHERE m.org_id = p_org_id AND m.legacy_staged_document_id = p_legacy_staged_document_id)
      AND public.staged_document_backfill_source_is_valid(s.org_id, s.storage_path, s.intake_matter_id) THEN s.uploaded_by ELSE NULL END,
    CASE WHEN l.lease_token = p_lease_token AND l.action_kind = p_action_kind AND l.expires_at > now()
      AND NOT EXISTS (SELECT 1 FROM public.staged_document_backfill_items m WHERE m.org_id = p_org_id AND m.legacy_staged_document_id = p_legacy_staged_document_id)
      AND public.staged_document_backfill_source_is_valid(s.org_id, s.storage_path, s.intake_matter_id) THEN s.intake_matter_id ELSE NULL END
  FROM public.staged_documents s
  LEFT JOIN public.staged_document_legacy_action_leases l
    ON l.org_id = s.org_id AND l.legacy_staged_document_id = s.id
  WHERE s.org_id = p_org_id AND s.id = p_legacy_staged_document_id
$$;

CREATE OR REPLACE FUNCTION public.release_legacy_staged_document_action(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_lease_token uuid
)
RETURNS TABLE(code text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  WITH released AS (
    DELETE FROM public.staged_document_legacy_action_leases AS l
    WHERE l.org_id = p_org_id AND l.legacy_staged_document_id = p_legacy_staged_document_id
      AND l.lease_token = p_lease_token AND l.expires_at > now()
    RETURNING 1
  )
  SELECT CASE WHEN EXISTS (SELECT 1 FROM released) THEN 'ok' ELSE 'lease_not_held' END
$$;

CREATE OR REPLACE FUNCTION public.get_legacy_staged_document_read_grant(
  p_org_id uuid,
  p_legacy_staged_document_id uuid
)
RETURNS TABLE(code text, bucket_id text, object_key text)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT CASE
    WHEN s.id IS NULL THEN 'not_found'
    WHEN EXISTS (SELECT 1 FROM public.staged_document_backfill_items m WHERE m.org_id = p_org_id AND m.legacy_staged_document_id = p_legacy_staged_document_id) THEN 'backfill_fenced'
    WHEN EXISTS (SELECT 1 FROM public.staged_document_legacy_action_leases l WHERE l.org_id = p_org_id AND l.legacy_staged_document_id = p_legacy_staged_document_id AND l.expires_at > now()) THEN 'action_reserved'
    WHEN NOT public.staged_document_backfill_source_is_valid(s.org_id, s.storage_path, s.intake_matter_id) THEN 'invalid_lineage'
    ELSE 'ok' END,
    CASE WHEN NOT EXISTS (SELECT 1 FROM public.staged_document_backfill_items m WHERE m.org_id = p_org_id AND m.legacy_staged_document_id = p_legacy_staged_document_id)
      AND NOT EXISTS (SELECT 1 FROM public.staged_document_legacy_action_leases l WHERE l.org_id = p_org_id AND l.legacy_staged_document_id = p_legacy_staged_document_id AND l.expires_at > now())
      AND public.staged_document_backfill_source_is_valid(s.org_id, s.storage_path, s.intake_matter_id) THEN 'staging' ELSE NULL END,
    CASE WHEN NOT EXISTS (SELECT 1 FROM public.staged_document_backfill_items m WHERE m.org_id = p_org_id AND m.legacy_staged_document_id = p_legacy_staged_document_id)
      AND NOT EXISTS (SELECT 1 FROM public.staged_document_legacy_action_leases l WHERE l.org_id = p_org_id AND l.legacy_staged_document_id = p_legacy_staged_document_id AND l.expires_at > now())
      AND public.staged_document_backfill_source_is_valid(s.org_id, s.storage_path, s.intake_matter_id) THEN s.storage_path ELSE NULL END
  FROM public.staged_documents s WHERE s.org_id = p_org_id AND s.id = p_legacy_staged_document_id
$$;

CREATE OR REPLACE FUNCTION public.get_legacy_staged_document_eligible_ids(p_org_id uuid)
RETURNS TABLE(legacy_staged_document_id uuid)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT s.id FROM public.staged_documents s
  WHERE s.org_id = p_org_id
    AND NOT EXISTS (SELECT 1 FROM public.staged_document_backfill_items m WHERE m.org_id = s.org_id AND m.legacy_staged_document_id = s.id)
    AND NOT EXISTS (SELECT 1 FROM public.staged_document_legacy_action_leases l WHERE l.org_id = s.org_id AND l.legacy_staged_document_id = s.id AND l.expires_at > now())
$$;

-- Claim only opaque work identifiers. The service worker resolves the legacy
-- storage path in its own trusted read, so diagnostics/reports never contain a
-- legacy object key, filename, or extracted metadata.
CREATE OR REPLACE FUNCTION public.claim_staged_document_backfill_batch(
  p_org_id uuid,
  p_batch_size integer DEFAULT 25
)
RETURNS TABLE(
  code text,
  legacy_staged_document_id uuid,
  safe_item_key text,
  verification_lease_token uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  source_row public.staged_documents%ROWTYPE;
  map_row public.staged_document_backfill_items%ROWTYPE;
  lease_token uuid;
  safe_key text;
  invalid_source boolean;
BEGIN
  IF p_org_id IS NULL OR p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'invalid staged-document backfill batch request';
  END IF;

  FOR source_row IN
    SELECT s.*
    FROM public.staged_documents AS s
    LEFT JOIN public.staged_document_backfill_items AS m
      ON m.org_id = s.org_id AND m.legacy_staged_document_id = s.id
    WHERE s.org_id = p_org_id
      AND NOT EXISTS (
        SELECT 1 FROM public.staged_document_legacy_action_leases AS action_lease
        WHERE action_lease.org_id = s.org_id
          AND action_lease.legacy_staged_document_id = s.id
          AND action_lease.expires_at > now()
      )
      AND (
        m.id IS NULL
        OR (m.outcome = 'verification_required' AND (
          m.verification_lease_expires_at IS NULL OR m.verification_lease_expires_at <= now()
        ))
      )
    ORDER BY s.created_at, s.id
    FOR UPDATE OF s SKIP LOCKED
    LIMIT p_batch_size
  LOOP
    SELECT * INTO map_row
    FROM public.staged_document_backfill_items AS m
    WHERE m.org_id = source_row.org_id AND m.legacy_staged_document_id = source_row.id
    FOR UPDATE;

    safe_key := 'legacy-staged/' || source_row.id::text;

    IF source_row.status IN ('manually_assigned', 'auto_assigned') THEN
      INSERT INTO public.staged_document_backfill_items (
        org_id, legacy_staged_document_id, safe_item_key, outcome,
        safe_reason_code, terminal_classified_at
      ) VALUES (
        source_row.org_id, source_row.id, safe_key, 'already_migrated',
        'legacy_assignment_terminal', now()
      )
      ON CONFLICT ON CONSTRAINT staged_document_backfill_items_source_unique DO UPDATE
      SET outcome = 'already_migrated', canonical_asset_id = NULL,
          canonical_intake_item_id = NULL, duplicate_asset_id = NULL,
          safe_reason_code = 'legacy_assignment_terminal',
          verification_lease_token = NULL, verification_lease_expires_at = NULL,
          terminal_classified_at = coalesce(staged_document_backfill_items.terminal_classified_at, now());
      RETURN QUERY SELECT 'already_migrated'::text, source_row.id, safe_key, NULL::uuid;
      CONTINUE;
    END IF;

    invalid_source := NOT public.staged_document_backfill_source_is_valid(
      source_row.org_id, source_row.storage_path, source_row.intake_matter_id
    );

    IF invalid_source THEN
      INSERT INTO public.staged_document_backfill_items (
        org_id, legacy_staged_document_id, safe_item_key, outcome,
        safe_reason_code, terminal_classified_at
      ) VALUES (
        source_row.org_id, source_row.id, safe_key, 'invalid_lineage',
        'legacy_source_lineage_invalid', now()
      )
      ON CONFLICT ON CONSTRAINT staged_document_backfill_items_source_unique DO UPDATE
      SET outcome = 'invalid_lineage', canonical_asset_id = NULL,
          canonical_intake_item_id = NULL, duplicate_asset_id = NULL,
          safe_reason_code = 'legacy_source_lineage_invalid',
          verification_lease_token = NULL, verification_lease_expires_at = NULL,
          terminal_classified_at = coalesce(staged_document_backfill_items.terminal_classified_at, now());
      RETURN QUERY SELECT 'invalid_lineage'::text, source_row.id, safe_key, NULL::uuid;
      CONTINUE;
    END IF;

    lease_token := gen_random_uuid();
    INSERT INTO public.staged_document_backfill_items (
      org_id, legacy_staged_document_id, safe_item_key, outcome,
      verification_attempt_count, verification_lease_token,
      verification_lease_expires_at, first_claimed_at
    ) VALUES (
      source_row.org_id, source_row.id, safe_key, 'verification_required',
      1, lease_token, now() + interval '10 minutes', now()
    )
    ON CONFLICT ON CONSTRAINT staged_document_backfill_items_source_unique DO UPDATE
    SET verification_attempt_count = staged_document_backfill_items.verification_attempt_count + 1,
        verification_lease_token = excluded.verification_lease_token,
        verification_lease_expires_at = excluded.verification_lease_expires_at,
        first_claimed_at = coalesce(staged_document_backfill_items.first_claimed_at, now()),
        safe_reason_code = NULL
    WHERE staged_document_backfill_items.outcome = 'verification_required'
    RETURNING staged_document_backfill_items.verification_lease_token INTO lease_token;

    IF lease_token IS NOT NULL THEN
      RETURN QUERY SELECT 'verification_required'::text, source_row.id, safe_key, lease_token;
    END IF;
  END LOOP;
END $$;

-- Record an observation made by a trusted storage worker. SQL intentionally
-- cannot ask Storage whether a legacy object exists, so only this explicit
-- service result can classify a source as missing. No binary operation occurs.
CREATE OR REPLACE FUNCTION public.record_staged_document_backfill_verification(
  p_org_id uuid,
  p_legacy_staged_document_id uuid,
  p_verification_lease_token uuid,
  p_source_result public.staged_document_backfill_source_result,
  p_observed_bytes bigint DEFAULT NULL,
  p_sha256 text DEFAULT NULL
)
RETURNS TABLE(code text, asset_id uuid, intake_item_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  map_row public.staged_document_backfill_items%ROWTYPE;
  source_row public.staged_documents%ROWTYPE;
  duplicate_asset uuid;
  canonical_asset uuid;
  invalid_source boolean;
BEGIN
  IF p_org_id IS NULL OR p_legacy_staged_document_id IS NULL
     OR p_verification_lease_token IS NULL OR p_source_result IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid, NULL::uuid;
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
  IF map_row.outcome = 'transfer_pending' THEN
    RETURN QUERY SELECT 'already_migrated'::text, map_row.canonical_asset_id, NULL::uuid;
    RETURN;
  END IF;
  IF map_row.outcome <> 'verification_required' THEN
    RETURN QUERY SELECT map_row.outcome::text, map_row.duplicate_asset_id, NULL::uuid;
    RETURN;
  END IF;
  IF map_row.verification_lease_token IS DISTINCT FROM p_verification_lease_token
     OR map_row.verification_lease_expires_at IS NULL
     OR map_row.verification_lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'lease_not_held'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;

  SELECT * INTO source_row
  FROM public.staged_documents AS s
  WHERE s.org_id = p_org_id AND s.id = p_legacy_staged_document_id
  FOR UPDATE;
  IF source_row.id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;

  IF source_row.status IN ('manually_assigned', 'auto_assigned') THEN
    UPDATE public.staged_document_backfill_items
    SET outcome = 'already_migrated', safe_reason_code = 'legacy_assignment_terminal',
        verification_lease_token = NULL, verification_lease_expires_at = NULL,
        terminal_classified_at = now()
    WHERE id = map_row.id;
    RETURN QUERY SELECT 'already_migrated'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;

  invalid_source := NOT public.staged_document_backfill_source_is_valid(
    source_row.org_id, source_row.storage_path, source_row.intake_matter_id
  );
  IF invalid_source THEN
    UPDATE public.staged_document_backfill_items
    SET outcome = 'invalid_lineage', safe_reason_code = 'legacy_source_lineage_invalid',
        verification_lease_token = NULL, verification_lease_expires_at = NULL,
        terminal_classified_at = now()
    WHERE id = map_row.id;
    RETURN QUERY SELECT 'invalid_lineage'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;

  IF p_source_result = 'missing' THEN
    UPDATE public.staged_document_backfill_items
    SET outcome = 'missing_object', safe_reason_code = 'storage_missing',
        verification_lease_token = NULL, verification_lease_expires_at = NULL,
        externally_verified_at = now(), terminal_classified_at = now()
    WHERE id = map_row.id;
    RETURN QUERY SELECT 'missing_object'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;

  IF p_source_result IN ('unreadable', 'malformed_pdf', 'encrypted_pdf', 'non_pdf', 'oversize') THEN
    UPDATE public.staged_document_backfill_items
    SET outcome = CASE p_source_result
          WHEN 'unreadable' THEN 'unreadable_source'::public.staged_document_backfill_outcome
          WHEN 'malformed_pdf' THEN 'malformed_pdf'::public.staged_document_backfill_outcome
          WHEN 'encrypted_pdf' THEN 'encrypted_pdf'::public.staged_document_backfill_outcome
          WHEN 'non_pdf' THEN 'non_pdf'::public.staged_document_backfill_outcome
          ELSE 'oversize'::public.staged_document_backfill_outcome
        END,
        safe_reason_code = CASE p_source_result
          WHEN 'unreadable' THEN 'source_unreadable'
          WHEN 'malformed_pdf' THEN 'invalid_pdf'
          WHEN 'encrypted_pdf' THEN 'encrypted_pdf'
          WHEN 'non_pdf' THEN 'non_pdf'
          ELSE 'file_too_large'
        END,
        verification_lease_token = NULL, verification_lease_expires_at = NULL,
        externally_verified_at = now(), terminal_classified_at = now()
    WHERE id = map_row.id;
    RETURN QUERY SELECT CASE p_source_result
      WHEN 'unreadable' THEN 'unreadable_source'
      ELSE p_source_result::text
    END, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;

  IF p_source_result <> 'valid_pdf' OR p_observed_bytes IS NULL OR p_observed_bytes <= 0
     OR p_sha256 IS NULL OR p_sha256 !~ '^[0-9a-f]{64}$' THEN
    RETURN QUERY SELECT 'invalid_observation'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;

  IF p_observed_bytes > coalesce((
    SELECT policy.max_pdf_bytes
    FROM public.organisation_storage_policies AS policy
    WHERE policy.org_id = p_org_id
  ), 26214400) THEN
    UPDATE public.staged_document_backfill_items
    SET outcome = 'oversize', safe_reason_code = 'file_too_large',
        verification_lease_token = NULL, verification_lease_expires_at = NULL,
        externally_verified_at = now(), terminal_classified_at = now()
    WHERE id = map_row.id;
    RETURN QUERY SELECT 'oversize'::text, NULL::uuid, NULL::uuid;
    RETURN;
  END IF;

  -- The partial hash index is per tenant. Serialising same-org observations
  -- makes a duplicate/reference result deterministic without cross-org reuse.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(p_org_id::text), pg_catalog.hashtext(p_sha256)
  );
  SELECT candidate.asset_id INTO duplicate_asset
  FROM (
    SELECT fa.id AS asset_id, 0 AS priority, fa.created_at
    FROM public.file_assets AS fa
    WHERE fa.org_id = p_org_id AND fa.sha256 = p_sha256
    UNION ALL
    SELECT mapped.canonical_asset_id AS asset_id, 1 AS priority, mapped.created_at
    FROM public.staged_document_backfill_items AS mapped
    WHERE mapped.org_id = p_org_id
      AND mapped.outcome = 'transfer_pending'
      AND mapped.observed_sha256 = p_sha256
  ) AS candidate
  ORDER BY candidate.priority,
           EXISTS (SELECT 1 FROM public.document_versions AS version WHERE version.asset_id = candidate.asset_id) DESC,
           candidate.created_at
  LIMIT 1;

  IF duplicate_asset IS NOT NULL THEN
    UPDATE public.staged_document_backfill_items
    SET outcome = 'duplicate_reference', duplicate_asset_id = duplicate_asset,
        safe_reason_code = 'duplicate_asset_reference',
        verification_lease_token = NULL, verification_lease_expires_at = NULL,
        externally_verified_at = now(), terminal_classified_at = now()
    WHERE id = map_row.id;
    RETURN QUERY SELECT 'duplicate_reference'::text, duplicate_asset, NULL::uuid;
    RETURN;
  END IF;

  canonical_asset := gen_random_uuid();
  INSERT INTO public.file_assets (
    id, org_id, bucket_id, object_key, detected_mime_type,
    availability, failure_code, created_by, legacy_staged_backfill_pending
  ) VALUES (
    canonical_asset, source_row.org_id, 'documents',
    'orgs/' || source_row.org_id::text || '/assets/' || canonical_asset::text || '/original.pdf',
    'application/pdf',
    'quarantined', 'legacy_staging_transfer_required', source_row.uploaded_by, true
  );

  -- Do not create Intake before transfer. A pre-transfer source is not a
  -- runnable canonical item and must not masquerade as ordinary processing.
  -- The mapping preserves context for the later authorised transfer command.
  UPDATE public.staged_document_backfill_items
  SET outcome = 'transfer_pending', canonical_asset_id = canonical_asset,
      canonical_intake_item_id = NULL,
      observed_sha256 = p_sha256, observed_byte_size = p_observed_bytes,
      safe_reason_code = 'legacy_staging_transfer_required',
      verification_lease_token = NULL, verification_lease_expires_at = NULL,
      externally_verified_at = now(), terminal_classified_at = now()
  WHERE id = map_row.id;

  RETURN QUERY SELECT 'transfer_pending'::text, canonical_asset, NULL::uuid;
END $$;

-- Safe, per-organisation operational report. It contains counts and opaque
-- IDs only; object keys, filenames, raw metadata, and PDF-derived content are
-- intentionally absent. A false retirement flag is deliberate: this tranche
-- does not prove canonical object reachability or retire legacy staging.
CREATE OR REPLACE VIEW public.staged_document_backfill_reports AS
SELECT
  s.org_id,
  count(*)::bigint AS legacy_source_count,
  count(*) FILTER (WHERE s.status IN ('pending_assignment', 'analyzing', 'ready_to_assign', 'failed'))::bigint AS active_source_count,
  count(*) FILTER (WHERE m.id IS NULL)::bigint AS unmapped_source_count,
  count(*) FILTER (WHERE m.outcome = 'verification_required')::bigint AS verification_required_count,
  count(*) FILTER (WHERE m.outcome = 'transfer_pending')::bigint AS transfer_pending_count,
  count(*) FILTER (WHERE m.outcome = 'missing_object')::bigint AS missing_object_count,
  count(*) FILTER (WHERE m.outcome = 'unreadable_source')::bigint AS unreadable_source_count,
  count(*) FILTER (WHERE m.outcome = 'malformed_pdf')::bigint AS malformed_pdf_count,
  count(*) FILTER (WHERE m.outcome = 'encrypted_pdf')::bigint AS encrypted_pdf_count,
  count(*) FILTER (WHERE m.outcome = 'non_pdf')::bigint AS non_pdf_count,
  count(*) FILTER (WHERE m.outcome = 'oversize')::bigint AS oversize_count,
  count(*) FILTER (WHERE m.outcome = 'invalid_lineage')::bigint AS invalid_lineage_count,
  count(*) FILTER (WHERE m.outcome = 'duplicate_reference')::bigint AS duplicate_reference_count,
  count(*) FILTER (WHERE m.outcome = 'already_migrated')::bigint AS already_migrated_count,
  (
    count(*) FILTER (WHERE m.id IS NULL OR m.outcome = 'verification_required') = 0
  ) AS classification_complete,
  false AS staging_retirement_ready
FROM public.staged_documents AS s
LEFT JOIN public.staged_document_backfill_items AS m
  ON m.org_id = s.org_id AND m.legacy_staged_document_id = s.id
GROUP BY s.org_id;

CREATE OR REPLACE VIEW public.staged_document_backfill_diagnostics AS
SELECT m.org_id, m.legacy_staged_document_id, m.safe_item_key,
       'mapped_asset_not_quarantined'::text AS issue
FROM public.staged_document_backfill_items AS m
JOIN public.file_assets AS asset
  ON asset.id = m.canonical_asset_id AND asset.org_id = m.org_id
WHERE m.outcome = 'transfer_pending'
  AND (asset.availability <> 'quarantined' OR NOT asset.legacy_staged_backfill_pending)
UNION ALL
SELECT m.org_id, m.legacy_staged_document_id, m.safe_item_key,
       'transfer_pending_has_runnable_intake'::text AS issue
FROM public.staged_document_backfill_items AS m
WHERE m.outcome = 'transfer_pending'
  AND m.canonical_intake_item_id IS NOT NULL
UNION ALL
SELECT m.org_id, m.legacy_staged_document_id, m.safe_item_key,
       'source_organisation_mismatch'::text AS issue
FROM public.staged_document_backfill_items AS m
JOIN public.staged_documents AS source
  ON source.id = m.legacy_staged_document_id
WHERE source.org_id <> m.org_id;

-- Never send a quarantined destination that has not been copied from staging
-- to the terminal-object cleanup worker.
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
      AND fa.legacy_staged_backfill_pending = false
      AND fa.availability IN ('failed','expired','quarantined')
      AND NOT EXISTS (SELECT 1 FROM public.document_versions AS dv WHERE dv.asset_id = fa.id)
      AND (fa.storage_deletion_lease_expires_at IS NULL OR fa.storage_deletion_lease_expires_at <= now())
    ORDER BY fa.created_at
    FOR UPDATE SKIP LOCKED
    LIMIT p_batch_size
  ), leased AS (
    UPDATE public.file_assets AS fa
    SET storage_delete_attempted_at = now(), storage_deletion_lease_token = gen_random_uuid(),
        storage_deletion_lease_expires_at = now() + interval '10 minutes', storage_delete_failure_code = NULL
    FROM candidates AS candidate
    WHERE fa.id = candidate.id
    RETURNING fa.id, fa.bucket_id, fa.object_key, fa.storage_deletion_lease_token
  )
  SELECT leased.id AS asset_id, leased.bucket_id AS bucket_id, leased.object_key AS object_key,
         leased.storage_deletion_lease_token AS lease_token
  FROM leased;
END $$;

ALTER TABLE public.staged_document_backfill_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staged_document_backfill_items FORCE ROW LEVEL SECURITY;
ALTER TABLE public.staged_document_legacy_action_leases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staged_document_legacy_action_leases FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.staged_document_backfill_items, public.staged_document_legacy_action_leases,
  public.staged_document_backfill_reports, public.staged_document_backfill_diagnostics
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.staged_document_backfill_reports,
  public.staged_document_backfill_diagnostics TO service_role, postgres;

REVOKE ALL ON FUNCTION public.staged_document_backfill_touch(),
  public.staged_document_backfill_storage_path_is_valid(uuid, text),
  public.staged_document_backfill_source_is_valid(uuid, text, uuid),
  public.get_staged_document_backfill_source_grant(uuid, uuid, uuid),
  public.get_staged_document_backfill_adapter_fences(uuid),
  public.get_staged_document_backfill_action_guard(uuid, uuid),
  public.reserve_legacy_staged_document_action(uuid, uuid, public.staged_document_legacy_action_kind),
  public.get_legacy_staged_document_action_source_grant(uuid, uuid, uuid, public.staged_document_legacy_action_kind),
  public.release_legacy_staged_document_action(uuid, uuid, uuid),
  public.get_legacy_staged_document_read_grant(uuid, uuid),
  public.get_legacy_staged_document_eligible_ids(uuid),
  public.prevent_mapped_staged_document_legacy_mutation(),
  public.claim_staged_document_backfill_batch(uuid, integer),
  public.record_staged_document_backfill_verification(uuid, uuid, uuid, public.staged_document_backfill_source_result, bigint, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_staged_document_backfill_source_grant(uuid, uuid, uuid),
  public.get_staged_document_backfill_adapter_fences(uuid),
  public.get_staged_document_backfill_action_guard(uuid, uuid),
  public.reserve_legacy_staged_document_action(uuid, uuid, public.staged_document_legacy_action_kind),
  public.get_legacy_staged_document_action_source_grant(uuid, uuid, uuid, public.staged_document_legacy_action_kind),
  public.release_legacy_staged_document_action(uuid, uuid, uuid),
  public.get_legacy_staged_document_read_grant(uuid, uuid),
  public.get_legacy_staged_document_eligible_ids(uuid),
  public.claim_staged_document_backfill_batch(uuid, integer),
  public.record_staged_document_backfill_verification(uuid, uuid, uuid, public.staged_document_backfill_source_result, bigint, text)
  TO service_role;

COMMENT ON TABLE public.staged_document_backfill_items IS
  'Service-only staged-document migration map. It stores opaque legacy IDs and safe outcome codes, never source object paths or legal content.';
COMMENT ON VIEW public.staged_document_backfill_reports IS
  'Service-only per-organisation staged-document backfill counts. transfer_pending is intentionally not Intake; staging_retirement_ready remains false until the separate verified transfer/cutover tranche.';

COMMIT;
