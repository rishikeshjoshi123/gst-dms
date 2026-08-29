-- Close the release-upgrade gap left by 00056. Earlier deployments could
-- persist non-search reprocess runs before their scope was fenced. Those runs
-- have no safe generic worker, so they must become durable Review/recovery
-- work instead of being acknowledged as successful delivery.
BEGIN;

ALTER TABLE public.document_processing_runs
  ADD COLUMN next_retry_at timestamptz;

ALTER TABLE public.document_processing_recovery_cases
  DROP CONSTRAINT document_processing_recovery_cases_recovery_reason_check;
ALTER TABLE public.document_processing_recovery_cases
  ADD CONSTRAINT document_processing_recovery_cases_recovery_reason_check
  CHECK (recovery_reason IN (
    'legacy_processing_replay_unsafe',
    'scoped_reprocess_replay_unsafe',
    'scoped_reprocess_unavailable',
    'scoped_search_index_retry_exhausted'
  ));

ALTER TABLE public.outbox_events
  DROP CONSTRAINT outbox_events_last_error_code_safe;
ALTER TABLE public.outbox_events
  ADD CONSTRAINT outbox_events_last_error_code_safe
  CHECK (last_error_code IS NULL OR last_error_code IN (
    'gateway_unavailable', 'gateway_timeout', 'gateway_rejected',
    'dispatch_failed', 'scoped_reprocess_unavailable'
  ));

-- The first failed claim waits 30–44 seconds; the second waits 60–74
-- seconds. Jitter is deterministic per run and attempt, so reconciliation is
-- testable and duplicate schedulers never manufacture a different deadline.
CREATE OR REPLACE FUNCTION public.search_index_reprocess_retry_delay_seconds(
  p_processing_run_id uuid,
  p_attempt_number integer
) RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT CASE
    WHEN p_processing_run_id IS NULL OR p_attempt_number NOT BETWEEN 1 AND 2 THEN NULL
    ELSE 30 * (2 ^ (p_attempt_number - 1))::integer
      + (get_byte(decode(md5(p_processing_run_id::text || ':' || p_attempt_number::text), 'hex'), 0) % 15)
  END
$$;

-- Existing failed index runs receive the same deterministic deadline on
-- upgrade. There is no retry for attempt three; the reconciler opens a case.
UPDATE public.document_processing_runs AS run
SET next_retry_at = coalesce(run.failed_at, run.created_at) + make_interval(
  secs => public.search_index_reprocess_retry_delay_seconds(run.id, run.attempt_count)
)
FROM public.outbox_events AS event
WHERE event.id = run.outbox_event_id
  AND event.event_kind = 'document.reprocess_requested.v1'
  AND run.scope = 'search_index'
  AND run.state = 'failed'
  AND run.attempt_count BETWEEN 1 AND 2
  AND run.next_retry_at IS NULL;

-- The migration itself fences every still-queued retired scope. Pending and
-- leased envelopes are terminalized as dead letters so a concurrent or later
-- dispatcher cannot turn an unavailable request into a false acknowledgement.
WITH legacy_runs AS (
  SELECT run.id, run.org_id
  FROM public.document_processing_runs AS run
  JOIN public.outbox_events AS event ON event.id = run.outbox_event_id
  WHERE event.event_kind = 'document.reprocess_requested.v1'
    AND run.scope <> 'search_index'
    AND run.state = 'queued'
  FOR UPDATE OF run
), fenced AS (
  UPDATE public.document_processing_runs AS run
  SET state = 'failed', stage = 'review', failed_at = now(),
      safe_error_code = 'scoped_reprocess_unavailable',
      lease_token = NULL, lease_expires_at = NULL, next_retry_at = NULL,
      heartbeat_at = now()
  FROM legacy_runs AS legacy
  WHERE run.id = legacy.id
  RETURNING run.id, run.org_id
)
INSERT INTO public.document_processing_recovery_cases(org_id, processing_run_id, recovery_reason)
SELECT org_id, id, 'scoped_reprocess_unavailable' FROM fenced
ON CONFLICT (processing_run_id) DO UPDATE SET updated_at = now();

UPDATE public.outbox_events AS event
SET delivery_state = 'dead_letter', delivered_at = NULL, failed_at = now(),
    lease_token = NULL, lease_expires_at = NULL,
    last_error_code = 'scoped_reprocess_unavailable', updated_at = now()
WHERE event.event_kind = 'document.reprocess_requested.v1'
  AND event.payload->>'scope' IS DISTINCT FROM 'search_index'
  AND event.delivery_state IN ('pending', 'leased');

-- A Trigger task may begin just before or during an upgrade. This function
-- holds the delivery fence, transitions the exact retired run, records its
-- case, and consumes the envelope. It never invokes the legacy processor.
CREATE OR REPLACE FUNCTION public.recover_unavailable_document_reprocess_event(
  p_event_id uuid,
  p_expected_org_id uuid,
  p_delivery_lease_token uuid
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE event_row public.outbox_events%ROWTYPE;
DECLARE run_row public.document_processing_runs%ROWTYPE;
BEGIN
  IF p_event_id IS NULL OR p_expected_org_id IS NULL OR p_delivery_lease_token IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text;
    RETURN;
  END IF;
  SELECT * INTO event_row FROM public.outbox_events
  WHERE id = p_event_id FOR UPDATE;
  IF event_row.id IS NULL OR event_row.org_id IS DISTINCT FROM p_expected_org_id THEN
    RETURN QUERY SELECT 'not_found'::text;
    RETURN;
  END IF;
  IF event_row.delivery_state <> 'leased'
     OR event_row.lease_token IS DISTINCT FROM p_delivery_lease_token
     OR event_row.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'delivery_lease_invalid'::text;
    RETURN;
  END IF;
  IF event_row.event_kind <> 'document.reprocess_requested.v1'
     OR jsonb_typeof(event_row.payload) <> 'object'
     OR event_row.payload->>'scope' IS NULL
     OR event_row.payload->>'scope' = 'search_index' THEN
    RETURN QUERY SELECT 'invalid_event'::text;
    RETURN;
  END IF;

  SELECT * INTO run_row FROM public.document_processing_runs
  WHERE outbox_event_id = event_row.id
  FOR UPDATE;
  IF run_row.id IS NOT NULL AND run_row.scope <> 'search_index'
     AND run_row.state = 'queued' THEN
    UPDATE public.document_processing_runs
    SET state = 'failed', stage = 'review', failed_at = now(),
        safe_error_code = 'scoped_reprocess_unavailable',
        lease_token = NULL, lease_expires_at = NULL, next_retry_at = NULL,
        heartbeat_at = now()
    WHERE id = run_row.id;
    INSERT INTO public.document_processing_recovery_cases(org_id, processing_run_id, recovery_reason)
    VALUES (run_row.org_id, run_row.id, 'scoped_reprocess_unavailable')
    ON CONFLICT (processing_run_id) DO UPDATE SET updated_at = now();
  END IF;

  UPDATE public.outbox_events
  SET delivery_state = 'dead_letter', delivered_at = NULL, failed_at = now(),
      lease_token = NULL, lease_expires_at = NULL,
      last_error_code = 'scoped_reprocess_unavailable', updated_at = now()
  WHERE id = event_row.id;
  RETURN QUERY SELECT CASE WHEN run_row.id IS NULL THEN 'event_terminalized' ELSE 'recovery_opened' END::text;
END $$;

-- A failed index claim records the next deterministic retry deadline; a
-- terminal outcome cannot retain a stale retry. Preserve the 00056 provider
-- usage contract while replacing its completion function.
ALTER FUNCTION public.finish_document_search_index_reprocess_work(uuid,uuid,text,vector,text,text,integer)
  RENAME TO finish_document_search_index_reprocess_work_retry_fence;
REVOKE ALL ON FUNCTION public.finish_document_search_index_reprocess_work_retry_fence(uuid,uuid,text,vector,text,text,integer)
  FROM PUBLIC, anon, authenticated, service_role;
CREATE FUNCTION public.finish_document_search_index_reprocess_work(
  p_processing_run_id uuid, p_lease_token uuid, p_outcome text,
  p_embedding vector(768) DEFAULT NULL, p_embedding_model text DEFAULT NULL,
  p_embedding_version text DEFAULT NULL, p_input_tokens integer DEFAULT NULL
) RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE result record; run_row public.document_processing_runs%ROWTYPE;
BEGIN
  SELECT * INTO result FROM public.finish_document_search_index_reprocess_work_retry_fence(
    p_processing_run_id, p_lease_token, p_outcome, p_embedding,
    p_embedding_model, p_embedding_version, p_input_tokens
  );
  IF result.code = 'failed' THEN
    SELECT * INTO run_row FROM public.document_processing_runs WHERE id = p_processing_run_id FOR UPDATE;
    IF run_row.id IS NOT NULL AND run_row.state = 'failed'
       AND run_row.attempt_count BETWEEN 1 AND 2 THEN
      UPDATE public.document_processing_runs
      SET next_retry_at = failed_at + make_interval(
        secs => public.search_index_reprocess_retry_delay_seconds(id, attempt_count)
      )
      WHERE id = run_row.id;
    END IF;
  ELSIF result.code IN ('indexed', 'not_indexable', 'version_not_current') THEN
    UPDATE public.document_processing_runs
    SET next_retry_at = NULL
    WHERE id = p_processing_run_id;
  END IF;
  RETURN QUERY SELECT result.code::text;
END $$;
REVOKE ALL ON FUNCTION public.finish_document_search_index_reprocess_work(uuid,uuid,text,vector,text,text,integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finish_document_search_index_reprocess_work(uuid,uuid,text,vector,text,text,integer)
  TO service_role;

-- Reconciliation is the only retry scheduler. It converts expired leases to
-- safe failed state, waits until the persisted deterministic deadline, and
-- requeues at most twice (three total claims). All non-search work remains
-- recovery-only, including a direct legacy row that somehow survives upgrade.
CREATE OR REPLACE FUNCTION public.reconcile_document_processing_work(p_batch_size integer DEFAULT 100)
RETURNS TABLE(validation_requeued integer, processing_requeued integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE validation_count integer := 0; processing_count integer := 0;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'invalid batch size';
  END IF;

  WITH candidates AS (
    SELECT sar.id, sar.outbox_event_id FROM public.source_analysis_runs AS sar
    WHERE sar.outbox_event_id IS NOT NULL AND sar.state = 'running' AND sar.lease_expires_at <= now()
    ORDER BY coalesce(sar.lease_expires_at, sar.created_at) FOR UPDATE SKIP LOCKED LIMIT p_batch_size
  ), reset_runs AS (
    UPDATE public.source_analysis_runs AS sar
    SET state = 'queued', started_at = NULL, failed_at = NULL, safe_error_code = 'work_requeued',
        lease_token = NULL, lease_expires_at = NULL, heartbeat_at = now()
    FROM candidates AS candidate WHERE sar.id = candidate.id RETURNING candidate.outbox_event_id
  ), reset_events AS (
    UPDATE public.outbox_events AS event
    SET delivery_state = 'pending', delivered_at = NULL, failed_at = NULL, lease_token = NULL,
        lease_expires_at = NULL, next_attempt_at = now(), last_error_code = 'dispatch_failed', updated_at = now()
    FROM reset_runs AS run WHERE event.id = run.outbox_event_id AND event.delivery_state = 'delivered'
    RETURNING event.id
  ) SELECT count(*) INTO validation_count FROM reset_events;

  WITH expired AS (
    SELECT run.id FROM public.document_processing_runs AS run
    JOIN public.outbox_events AS event ON event.id = run.outbox_event_id
    WHERE event.event_kind = 'document.reprocess_requested.v1'
      AND run.scope = 'search_index' AND run.state = 'running'
      AND run.lease_expires_at <= now()
    ORDER BY run.lease_expires_at FOR UPDATE OF run SKIP LOCKED LIMIT p_batch_size
  ) UPDATE public.document_processing_runs AS run
  SET state = 'failed', stage = 'failed', failed_at = lease_expires_at,
      safe_error_code = 'search_index_lease_expired', lease_token = NULL,
      next_retry_at = lease_expires_at + make_interval(
        secs => public.search_index_reprocess_retry_delay_seconds(run.id, run.attempt_count)
      ), heartbeat_at = now()
  FROM expired WHERE run.id = expired.id AND run.attempt_count BETWEEN 1 AND 2;

  WITH candidates AS (
    SELECT run.id, run.outbox_event_id FROM public.document_processing_runs AS run
    JOIN public.outbox_events AS event ON event.id = run.outbox_event_id
    WHERE event.event_kind = 'document.reprocess_requested.v1'
      AND run.scope = 'search_index' AND run.state = 'failed'
      AND run.attempt_count BETWEEN 1 AND 2
      AND run.next_retry_at IS NOT NULL AND run.next_retry_at <= now()
    ORDER BY run.next_retry_at FOR UPDATE OF run SKIP LOCKED LIMIT p_batch_size
  ), reset_runs AS (
    UPDATE public.document_processing_runs AS run
    SET state = 'queued', stage = 'queued', started_at = NULL, failed_at = NULL,
        safe_error_code = 'search_index_retry_scheduled', lease_token = NULL,
        lease_expires_at = NULL, next_retry_at = NULL, heartbeat_at = now()
    FROM candidates AS candidate WHERE run.id = candidate.id RETURNING candidate.outbox_event_id
  ), reset_events AS (
    UPDATE public.outbox_events AS event
    SET delivery_state = 'pending', delivered_at = NULL, failed_at = NULL, lease_token = NULL,
        lease_expires_at = NULL, next_attempt_at = now(), last_error_code = 'dispatch_failed', updated_at = now()
    FROM reset_runs AS run WHERE event.id = run.outbox_event_id AND event.delivery_state = 'delivered'
    RETURNING event.id
  ) SELECT count(*) INTO processing_count FROM reset_events;

  WITH candidates AS (
    SELECT run.id, run.org_id, run.outbox_event_id,
      CASE
        WHEN event.event_kind = 'document.reprocess_requested.v1' AND run.scope <> 'search_index'
          THEN 'scoped_reprocess_unavailable'
        WHEN event.event_kind = 'document.reprocess_requested.v1' AND run.scope = 'search_index'
          THEN 'scoped_search_index_retry_exhausted'
        WHEN event.event_kind = 'document.reprocess_requested.v1'
          THEN 'scoped_reprocess_replay_unsafe'
        ELSE 'legacy_processing_replay_unsafe'
      END AS reason
    FROM public.document_processing_runs AS run
    JOIN public.outbox_events AS event ON event.id = run.outbox_event_id
    WHERE run.outbox_event_id IS NOT NULL
      AND (
        (event.event_kind = 'document.reprocess_requested.v1' AND run.scope <> 'search_index' AND run.state = 'queued')
        OR (run.state = 'failed' AND NOT (
          event.event_kind = 'document.reprocess_requested.v1'
          AND run.scope = 'search_index' AND run.attempt_count BETWEEN 1 AND 2
          AND run.next_retry_at IS NOT NULL AND run.next_retry_at > now()
        ))
        OR (run.state = 'running' AND run.lease_expires_at <= now())
      )
    ORDER BY coalesce(run.next_retry_at, run.lease_expires_at, run.failed_at, run.created_at)
    FOR UPDATE OF run SKIP LOCKED LIMIT p_batch_size
  ), fenced AS (
    UPDATE public.document_processing_runs AS run
    SET state = 'failed', stage = CASE WHEN candidate.reason LIKE 'scoped_%'
          THEN 'review'::public.document_processing_stage ELSE 'failed'::public.document_processing_stage END,
        failed_at = coalesce(run.failed_at, now()), safe_error_code = CASE
          WHEN candidate.reason = 'scoped_reprocess_unavailable' THEN 'scoped_reprocess_unavailable'
          WHEN candidate.reason = 'scoped_reprocess_replay_unsafe' THEN 'scoped_reprocess_replay_unsafe'
          WHEN candidate.reason = 'scoped_search_index_retry_exhausted' THEN 'search_index_retry_exhausted'
          ELSE 'legacy_processing_recovery_required'
        END, lease_token = NULL, lease_expires_at = NULL, next_retry_at = NULL, heartbeat_at = now()
    FROM candidates AS candidate WHERE run.id = candidate.id
    RETURNING run.id, run.org_id, run.outbox_event_id, candidate.reason
  ), terminal_events AS (
    UPDATE public.outbox_events AS event
    SET delivery_state = 'dead_letter', delivered_at = NULL, failed_at = now(),
        lease_token = NULL, lease_expires_at = NULL,
        last_error_code = 'scoped_reprocess_unavailable', updated_at = now()
    FROM fenced WHERE fenced.reason = 'scoped_reprocess_unavailable'
      AND event.id = fenced.outbox_event_id
      AND event.delivery_state IN ('pending', 'leased')
    RETURNING event.id
  )
  INSERT INTO public.document_processing_recovery_cases(org_id, processing_run_id, recovery_reason)
  SELECT org_id, id, reason FROM fenced
  ON CONFLICT (processing_run_id) DO UPDATE SET updated_at = now();

  RETURN QUERY SELECT validation_count, processing_count;
END $$;

REVOKE ALL ON FUNCTION public.search_index_reprocess_retry_delay_seconds(uuid,integer),
  public.recover_unavailable_document_reprocess_event(uuid,uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.search_index_reprocess_retry_delay_seconds(uuid,integer),
  public.recover_unavailable_document_reprocess_event(uuid,uuid,uuid)
  TO service_role;

COMMIT;
