-- Privileged, bounded retention of successfully delivered outbox history.
-- This never touches delivery states that could still require operator action.
BEGIN;

CREATE TABLE public.outbox_delivery_receipts (
  event_id uuid PRIMARY KEY,
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  aggregate_type text NOT NULL,
  aggregate_id uuid NOT NULL,
  event_kind text NOT NULL CHECK (event_kind ~ '^[a-z][a-z0-9_.]*\.v[1-9][0-9]*$'),
  event_version integer NOT NULL CHECK (event_version > 0),
  final_trigger_run_id text NOT NULL CHECK (final_trigger_run_id ~ '^[A-Za-z0-9._:-]{1,200}$'),
  attempt_count integer NOT NULL CHECK (attempt_count BETWEEN 1 AND 5),
  delivered_at timestamptz NOT NULL,
  compacted_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT outbox_delivery_receipts_event_version_matches_kind
    CHECK (event_kind ~ ('\.v' || event_version::text || '$'))
);

-- The execution journal makes bounded maintenance observable without storing
-- caller data, envelope payloads, paths, or provider output.
CREATE TABLE public.outbox_retention_maintenance_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operation text NOT NULL CHECK (operation IN ('compact_delivered', 'record_compaction_skips', 'cleanup_receipts')),
  cutoff_at timestamptz NOT NULL,
  affected_count integer NOT NULL CHECK (affected_count >= 0),
  executed_by name NOT NULL DEFAULT session_user,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Earlier schemas permitted delivered rows with an attempt count outside the
-- receipt contract. Keep those rows intact and record a bounded, payload-free
-- exception once, so one legacy row cannot roll back a whole maintenance run.
CREATE TABLE public.outbox_delivery_compaction_skips (
  event_id uuid PRIMARY KEY,
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  observed_attempt_count integer NOT NULL CHECK (observed_attempt_count >= 0),
  reason_code text NOT NULL
    CHECK (reason_code IN ('attempt_count_unrepresentable', 'missing_final_trigger_run_id')),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT outbox_delivery_compaction_skips_reason_consistent
    CHECK (
      (reason_code = 'attempt_count_unrepresentable' AND observed_attempt_count NOT BETWEEN 1 AND 5)
      OR (reason_code = 'missing_final_trigger_run_id' AND observed_attempt_count BETWEEN 0 AND 5)
    )
);

ALTER TABLE public.source_analysis_runs
  DROP CONSTRAINT IF EXISTS source_analysis_runs_outbox_event_id_fkey,
  ADD CONSTRAINT source_analysis_runs_outbox_event_id_fkey
    FOREIGN KEY (outbox_event_id) REFERENCES public.outbox_events(id) ON DELETE SET NULL;
ALTER TABLE public.document_processing_runs
  DROP CONSTRAINT IF EXISTS document_processing_runs_outbox_event_id_fkey,
  ADD CONSTRAINT document_processing_runs_outbox_event_id_fkey
    FOREIGN KEY (outbox_event_id) REFERENCES public.outbox_events(id) ON DELETE SET NULL;

-- This index is deliberately separate from the pending/lease hot path. It
-- permits bounded cleanup without changing any dispatcher index or query.
CREATE INDEX outbox_events_delivered_compaction_idx
  ON public.outbox_events (delivered_at, id)
  WHERE delivery_state = 'delivered';
CREATE INDEX outbox_delivery_receipts_retention_idx
  ON public.outbox_delivery_receipts (compacted_at, event_id);

-- The lifecycle guard remains fail-closed for every record except a deletion
-- made inside this function's transaction-scoped maintenance fence. Neither
-- table grants nor this setting are exposed to service or ordinary roles.
CREATE OR REPLACE FUNCTION public.document_lifecycle_prevent_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF session_user = 'postgres'
     AND TG_TABLE_NAME = 'outbox_events'
     AND current_setting('document_lifecycle.outbox_compaction_delete', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'lifecycle records are retained until the authorised purge boundary';
END $$;

CREATE OR REPLACE FUNCTION public.outbox_dispatch_attempt_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_OP = 'DELETE' AND session_user = 'postgres'
     AND current_setting('document_lifecycle.outbox_compaction_delete', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'outbox dispatch attempts are append-only';
END $$;

CREATE OR REPLACE FUNCTION public.compact_delivered_document_outbox_events(
  p_batch_size integer DEFAULT 100,
  p_delivered_before timestamptz DEFAULT NULL
) RETURNS TABLE(compacted_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE cutoff timestamptz; count_compacted integer; count_skipped integer;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'invalid delivered outbox compaction batch size';
  END IF;
  cutoff := coalesce(p_delivered_before, now() - interval '30 days');
  IF cutoff > now() - interval '30 days' THEN
    RAISE EXCEPTION 'delivered outbox compaction cutoff must retain at least 30 days';
  END IF;
  PERFORM set_config('document_lifecycle.outbox_compaction_delete', 'on', true);

  WITH candidates AS (
    SELECT event.id
    FROM public.outbox_events AS event
    LEFT JOIN public.outbox_delivery_receipts AS receipt ON receipt.event_id = event.id
    LEFT JOIN public.outbox_delivery_compaction_skips AS skip ON skip.event_id = event.id
    WHERE event.delivery_state = 'delivered'
      AND event.delivered_at <= cutoff
      AND receipt.event_id IS NULL
      AND skip.event_id IS NULL
    ORDER BY event.delivered_at, event.id
    FOR UPDATE OF event SKIP LOCKED
    LIMIT p_batch_size
  ), skipped AS (
    INSERT INTO public.outbox_delivery_compaction_skips(event_id, org_id, observed_attempt_count, reason_code)
    SELECT event.id, event.org_id, event.attempt_count,
      CASE WHEN event.trigger_run_id IS NULL THEN 'missing_final_trigger_run_id'
        ELSE 'attempt_count_unrepresentable' END
    FROM public.outbox_events AS event
    JOIN candidates AS candidate ON candidate.id = event.id
    WHERE event.trigger_run_id IS NULL OR event.attempt_count NOT BETWEEN 1 AND 5
    ON CONFLICT (event_id) DO NOTHING
    RETURNING event_id
  ), receipts AS (
    INSERT INTO public.outbox_delivery_receipts(
      event_id, org_id, aggregate_type, aggregate_id, event_kind, event_version,
      final_trigger_run_id, attempt_count, delivered_at
    )
    SELECT event.id, event.org_id, event.aggregate_type, event.aggregate_id,
      event.event_kind,
      substring(event.event_kind FROM '\.v([1-9][0-9]*)$')::integer,
      event.trigger_run_id, event.attempt_count, event.delivered_at
    FROM public.outbox_events AS event
    JOIN candidates AS candidate ON candidate.id = event.id
    WHERE event.trigger_run_id IS NOT NULL AND event.attempt_count BETWEEN 1 AND 5
    ON CONFLICT (event_id) DO NOTHING
    RETURNING event_id
  ), removed_attempts AS (
    DELETE FROM public.outbox_dispatch_attempts AS attempt
    USING receipts
    WHERE attempt.event_id = receipts.event_id
  ), removed_events AS (
    DELETE FROM public.outbox_events AS event
    USING receipts
    WHERE event.id = receipts.event_id
    RETURNING event.id
  )
  SELECT
    (SELECT count(*)::integer FROM removed_events),
    (SELECT count(*)::integer FROM skipped)
  INTO count_compacted, count_skipped;

  INSERT INTO public.outbox_retention_maintenance_runs(operation, cutoff_at, affected_count)
  VALUES ('compact_delivered', cutoff, count_compacted);
  INSERT INTO public.outbox_retention_maintenance_runs(operation, cutoff_at, affected_count)
  VALUES ('record_compaction_skips', cutoff, count_skipped);
  RETURN QUERY SELECT count_compacted;
END $$;

CREATE OR REPLACE FUNCTION public.cleanup_compacted_outbox_delivery_receipts(
  p_batch_size integer DEFAULT 100,
  p_compacted_before timestamptz DEFAULT NULL
) RETURNS TABLE(deleted_receipt_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE cutoff timestamptz; count_deleted integer;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'invalid outbox receipt cleanup batch size';
  END IF;
  cutoff := coalesce(p_compacted_before, now() - interval '180 days');
  IF cutoff > now() - interval '180 days' THEN
    RAISE EXCEPTION 'outbox receipt cleanup cutoff must retain at least 180 days';
  END IF;

  WITH candidates AS (
    SELECT receipt.event_id
    FROM public.outbox_delivery_receipts AS receipt
    WHERE receipt.compacted_at <= cutoff
    ORDER BY receipt.compacted_at, receipt.event_id
    FOR UPDATE SKIP LOCKED
    LIMIT p_batch_size
  ), deleted AS (
    DELETE FROM public.outbox_delivery_receipts AS receipt
    USING candidates
    WHERE receipt.event_id = candidates.event_id
    RETURNING receipt.event_id
  )
  SELECT count(*)::integer INTO count_deleted FROM deleted;

  INSERT INTO public.outbox_retention_maintenance_runs(operation, cutoff_at, affected_count)
  VALUES ('cleanup_receipts', cutoff, count_deleted);
  RETURN QUERY SELECT count_deleted;
END $$;

ALTER TABLE public.outbox_delivery_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outbox_delivery_receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE public.outbox_retention_maintenance_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outbox_retention_maintenance_runs FORCE ROW LEVEL SECURITY;
ALTER TABLE public.outbox_delivery_compaction_skips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outbox_delivery_compaction_skips FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.outbox_delivery_receipts, public.outbox_retention_maintenance_runs,
  public.outbox_delivery_compaction_skips
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.compact_delivered_document_outbox_events(integer, timestamptz),
  public.cleanup_compacted_outbox_delivery_receipts(integer, timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  public.compact_delivered_document_outbox_events(integer, timestamptz),
  public.cleanup_compacted_outbox_delivery_receipts(integer, timestamptz)
  TO postgres;

COMMIT;
