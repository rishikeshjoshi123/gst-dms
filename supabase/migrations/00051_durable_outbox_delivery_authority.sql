-- Durable outbox delivery authority. Delivery to Trigger is deliberately kept
-- separate from document/source processing state: accepting an event is not a
-- processing completion signal.
BEGIN;

ALTER TABLE public.outbox_events
  ADD CONSTRAINT outbox_events_last_error_code_safe
  CHECK (last_error_code IS NULL OR last_error_code ~ '^[a-z][a-z0-9_]{0,63}$');

-- The pre-existing delivery ledger is retained so outstanding work and its
-- audit trail keep their identifiers. Expired leases are now recorded as a
-- first-class, content-free delivery outcome before they are retried.
ALTER TABLE public.outbox_dispatch_attempts
  DROP CONSTRAINT outbox_dispatch_attempts_outcome_fields;
ALTER TABLE public.outbox_dispatch_attempts
  DROP CONSTRAINT outbox_dispatch_attempts_outcome_check;
ALTER TABLE public.outbox_dispatch_attempts
  ADD CONSTRAINT outbox_dispatch_attempts_outcome_check
    CHECK (outcome IN ('leased', 'accepted', 'retry_scheduled', 'lease_expired', 'dead_letter')),
  ADD CONSTRAINT outbox_dispatch_attempts_outcome_fields CHECK (
    (outcome = 'accepted' AND trigger_run_id IS NOT NULL AND safe_error_code IS NULL)
    OR (outcome = 'leased' AND trigger_run_id IS NULL AND safe_error_code IS NULL)
    OR (outcome IN ('retry_scheduled', 'lease_expired', 'dead_letter')
      AND trigger_run_id IS NULL AND safe_error_code IS NOT NULL)
  );

-- These partial indexes are the only hot read path. Delivered and dead-letter
-- history is excluded, including when that history becomes large.
DROP INDEX IF EXISTS public.outbox_events_dispatch_due_idx;
CREATE INDEX outbox_events_due_pending_idx
  ON public.outbox_events (next_attempt_at, created_at, id)
  WHERE delivery_state = 'pending';
CREATE INDEX outbox_events_due_pending_org_idx
  ON public.outbox_events (org_id, next_attempt_at, created_at, id)
  WHERE delivery_state = 'pending';
CREATE INDEX outbox_events_expired_lease_idx
  ON public.outbox_events (lease_expires_at, id)
  WHERE delivery_state = 'leased';

CREATE OR REPLACE FUNCTION public.outbox_delivery_retry_delay_seconds(
  p_event_id uuid,
  p_attempt_number integer
) RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT least(300, 5 * (2 ^ least(greatest(p_attempt_number, 1), 6))::integer)
    + (get_byte(decode(md5(p_event_id::text || ':' || p_attempt_number::text), 'hex'), 0) % 17)
$$;

-- Reconciliation owns only delivery leases. It never creates, completes, or
-- replays source-analysis/document-processing runs. A lost dispatcher lease
-- therefore becomes a bounded delivery retry (or a visible dead letter), not
-- an inference about the underlying document work.
CREATE OR REPLACE FUNCTION public.reconcile_document_outbox_delivery(
  p_batch_size integer DEFAULT 100
) RETURNS TABLE(retried_count bigint, dead_letter_count bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'invalid delivery reconciliation batch size';
  END IF;

  RETURN QUERY
  WITH candidates AS (
    SELECT oe.id, oe.org_id, oe.attempt_count, oe.lease_token
    FROM public.outbox_events AS oe
    WHERE oe.delivery_state = 'leased'
      AND oe.lease_expires_at <= now()
    ORDER BY oe.lease_expires_at, oe.id
    FOR UPDATE SKIP LOCKED
    LIMIT p_batch_size
  ), dead_lettered AS (
    UPDATE public.outbox_events AS oe
    SET delivery_state = 'dead_letter',
        lease_token = NULL,
        lease_expires_at = NULL,
        failed_at = now(),
        last_error_code = 'dispatch_failed',
        updated_at = now()
    FROM candidates AS c
    WHERE oe.id = c.id AND c.attempt_count >= 5
    RETURNING oe.id, oe.org_id, c.attempt_count, c.lease_token
  ), dead_ledger AS (
    INSERT INTO public.outbox_dispatch_attempts(
      event_id, org_id, attempt_number, lease_fingerprint, outcome, safe_error_code
    )
    SELECT d.id, d.org_id, d.attempt_count,
      encode(extensions.digest(d.lease_token::text, 'sha256'), 'hex'),
      'dead_letter', 'dispatch_failed'
    FROM dead_lettered AS d
    RETURNING event_id
  ), retried AS (
    UPDATE public.outbox_events AS oe
    SET delivery_state = 'pending',
        lease_token = NULL,
        lease_expires_at = NULL,
        next_attempt_at = now() + make_interval(
          secs => public.outbox_delivery_retry_delay_seconds(c.id, c.attempt_count)
        ),
        last_error_code = 'dispatch_failed',
        updated_at = now()
    FROM candidates AS c
    WHERE oe.id = c.id AND c.attempt_count < 5
    RETURNING oe.id, oe.org_id, c.attempt_count, c.lease_token
  ), retry_ledger AS (
    INSERT INTO public.outbox_dispatch_attempts(
      event_id, org_id, attempt_number, lease_fingerprint, outcome, safe_error_code
    )
    SELECT r.id, r.org_id, r.attempt_count,
      encode(extensions.digest(r.lease_token::text, 'sha256'), 'hex'),
      'lease_expired', 'dispatch_failed'
    FROM retried AS r
    RETURNING event_id
  )
  SELECT
    (SELECT count(*)::bigint FROM retry_ledger),
    (SELECT count(*)::bigint FROM dead_ledger);
END $$;

-- One first due event per organisation is selected before unused capacity is
-- borrowed by later events. This prevents a large tenant's oldest backlog from
-- monopolising a bounded lease while retaining throughput when few tenants are
-- active. SKIP LOCKED keeps overlapping dispatcher wake-ups fenced.
CREATE OR REPLACE FUNCTION public.lease_document_outbox_events(
  p_limit integer DEFAULT 25,
  p_lease_seconds integer DEFAULT 120
) RETURNS TABLE(
  event_id uuid,
  org_id uuid,
  event_kind text,
  aggregate_type text,
  aggregate_id uuid,
  payload jsonb,
  idempotency_key text,
  lease_token uuid,
  attempt_number integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
     OR p_lease_seconds IS NULL OR p_lease_seconds NOT BETWEEN 30 AND 600 THEN
    RAISE EXCEPTION 'invalid dispatch lease request';
  END IF;

  PERFORM public.reconcile_document_outbox_delivery(least(p_limit, 100));

  RETURN QUERY
  WITH per_organisation AS (
    SELECT DISTINCT ON (oe.org_id)
      oe.id, oe.org_id, oe.next_attempt_at, oe.created_at
    FROM public.outbox_events AS oe
    WHERE oe.delivery_state = 'pending'
      AND oe.next_attempt_at <= now()
    ORDER BY oe.org_id, oe.next_attempt_at, oe.created_at, oe.id
  ), fair AS (
    SELECT po.id, po.org_id, po.next_attempt_at, po.created_at, 0 AS priority
    FROM per_organisation AS po
    ORDER BY po.next_attempt_at, po.created_at, po.id
    LIMIT p_limit
  ), borrowed AS (
    SELECT oe.id, oe.org_id, oe.next_attempt_at, oe.created_at, 1 AS priority
    FROM public.outbox_events AS oe
    WHERE oe.delivery_state = 'pending'
      AND oe.next_attempt_at <= now()
      AND NOT EXISTS (SELECT 1 FROM fair AS f WHERE f.id = oe.id)
    ORDER BY oe.next_attempt_at, oe.created_at, oe.id
    LIMIT p_limit
  ), selected AS (
    SELECT picked.id, picked.org_id, picked.next_attempt_at, picked.created_at
    FROM (
      SELECT * FROM fair
      UNION ALL
      SELECT * FROM borrowed
    ) AS picked
    ORDER BY picked.priority, picked.next_attempt_at, picked.created_at, picked.id
    LIMIT p_limit
  ), locked AS (
    SELECT oe.id
    FROM public.outbox_events AS oe
    JOIN selected AS s ON s.id = oe.id
    ORDER BY s.next_attempt_at, s.created_at, s.id
    FOR UPDATE OF oe SKIP LOCKED
  ), leased AS (
    UPDATE public.outbox_events AS oe
    SET delivery_state = 'leased',
        lease_token = gen_random_uuid(),
        lease_expires_at = now() + make_interval(secs => p_lease_seconds),
        attempt_count = oe.attempt_count + 1,
        last_attempt_at = now(),
        next_attempt_at = now(),
        last_error_code = NULL,
        updated_at = now()
    FROM locked AS l
    WHERE oe.id = l.id
    RETURNING oe.id, oe.org_id, oe.event_kind, oe.aggregate_type, oe.aggregate_id,
      oe.payload, oe.idempotency_key, oe.lease_token, oe.attempt_count
  ), ledger AS (
    INSERT INTO public.outbox_dispatch_attempts(
      event_id, org_id, attempt_number, lease_fingerprint, outcome
    )
    SELECT l.id, l.org_id, l.attempt_count,
      encode(extensions.digest(l.lease_token::text, 'sha256'), 'hex'), 'leased'
    FROM leased AS l
  )
  SELECT l.id, l.org_id, l.event_kind, l.aggregate_type, l.aggregate_id,
    l.payload, l.idempotency_key, l.lease_token, l.attempt_count
  FROM leased AS l;
END $$;

CREATE OR REPLACE FUNCTION public.ack_document_outbox_event(
  p_event_id uuid,
  p_lease_token uuid,
  p_trigger_run_id text
) RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE e public.outbox_events%ROWTYPE;
BEGIN
  IF p_event_id IS NULL OR p_lease_token IS NULL OR p_trigger_run_id IS NULL
     OR p_trigger_run_id !~ '^[A-Za-z0-9._:-]{1,200}$' THEN
    RETURN QUERY SELECT 'invalid_request'::text;
    RETURN;
  END IF;

  SELECT oe.* INTO e FROM public.outbox_events AS oe WHERE oe.id = p_event_id FOR UPDATE;
  IF e.id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text;
    RETURN;
  END IF;
  IF e.delivery_state = 'delivered' THEN
    RETURN QUERY SELECT CASE
      WHEN e.trigger_run_id = p_trigger_run_id THEN 'already_accepted'::text
      ELSE 'delivery_already_complete'::text
    END;
    RETURN;
  END IF;
  IF e.delivery_state <> 'leased' OR e.lease_token IS DISTINCT FROM p_lease_token
     OR e.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'stale_lease'::text;
    RETURN;
  END IF;

  UPDATE public.outbox_events
  SET delivery_state = 'delivered',
      lease_token = NULL,
      lease_expires_at = NULL,
      delivered_at = now(),
      trigger_run_id = p_trigger_run_id,
      last_error_code = NULL,
      updated_at = now()
  WHERE id = e.id;
  INSERT INTO public.outbox_dispatch_attempts(
    event_id, org_id, attempt_number, lease_fingerprint, outcome, trigger_run_id
  ) VALUES (
    e.id, e.org_id, e.attempt_count,
    encode(extensions.digest(p_lease_token::text, 'sha256'), 'hex'),
    'accepted', p_trigger_run_id
  );
  RETURN QUERY SELECT 'ok'::text;
END $$;

CREATE OR REPLACE FUNCTION public.fail_document_outbox_event(
  p_event_id uuid,
  p_lease_token uuid,
  p_safe_error_code text
) RETURNS TABLE(code text, next_attempt_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE e public.outbox_events%ROWTYPE; retry_at timestamptz;
BEGIN
  IF p_event_id IS NULL OR p_lease_token IS NULL
     OR p_safe_error_code NOT IN ('gateway_unavailable', 'gateway_timeout', 'gateway_rejected', 'dispatch_failed') THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT oe.* INTO e FROM public.outbox_events AS oe WHERE oe.id = p_event_id FOR UPDATE;
  IF e.id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::timestamptz;
    RETURN;
  END IF;
  IF e.delivery_state = 'dead_letter' THEN
    RETURN QUERY SELECT 'already_dead_letter'::text, NULL::timestamptz;
    RETURN;
  END IF;
  IF e.delivery_state <> 'leased' OR e.lease_token IS DISTINCT FROM p_lease_token
     OR e.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'stale_lease'::text, NULL::timestamptz;
    RETURN;
  END IF;

  IF e.attempt_count >= 5 THEN
    UPDATE public.outbox_events
    SET delivery_state = 'dead_letter', lease_token = NULL, lease_expires_at = NULL,
        failed_at = now(), last_error_code = p_safe_error_code, updated_at = now()
    WHERE id = e.id;
    INSERT INTO public.outbox_dispatch_attempts(
      event_id, org_id, attempt_number, lease_fingerprint, outcome, safe_error_code
    ) VALUES (
      e.id, e.org_id, e.attempt_count,
      encode(extensions.digest(p_lease_token::text, 'sha256'), 'hex'),
      'dead_letter', p_safe_error_code
    );
    RETURN QUERY SELECT 'dead_letter'::text, NULL::timestamptz;
    RETURN;
  END IF;

  retry_at := now() + make_interval(
    secs => public.outbox_delivery_retry_delay_seconds(e.id, e.attempt_count)
  );
  UPDATE public.outbox_events
  SET delivery_state = 'pending', lease_token = NULL, lease_expires_at = NULL,
      next_attempt_at = retry_at, last_error_code = p_safe_error_code, updated_at = now()
  WHERE id = e.id;
  INSERT INTO public.outbox_dispatch_attempts(
    event_id, org_id, attempt_number, lease_fingerprint, outcome, safe_error_code
  ) VALUES (
    e.id, e.org_id, e.attempt_count,
    encode(extensions.digest(p_lease_token::text, 'sha256'), 'hex'),
    'retry_scheduled', p_safe_error_code
  );
  RETURN QUERY SELECT 'retry_scheduled'::text, retry_at;
END $$;

-- Content-free operational view: no tenant identity, aggregate identifiers,
-- event payloads, paths, task tokens, or provider output are projected.
CREATE OR REPLACE VIEW public.document_outbox_delivery_diagnostics AS
SELECT
  delivery_state,
  count(*)::bigint AS event_count,
  min(next_attempt_at) FILTER (WHERE delivery_state = 'pending') AS oldest_due_at,
  max(now() - lease_expires_at) FILTER (WHERE delivery_state = 'leased') AS oldest_lease_age,
  max(attempt_count)::integer AS highest_attempt_count
FROM public.outbox_events
GROUP BY delivery_state;

ALTER TABLE public.outbox_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outbox_events FORCE ROW LEVEL SECURITY;
ALTER TABLE public.outbox_dispatch_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outbox_dispatch_attempts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.outbox_events, public.outbox_dispatch_attempts,
  public.document_outbox_delivery_diagnostics
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.document_outbox_delivery_diagnostics TO service_role, postgres;
REVOKE ALL ON FUNCTION
  public.outbox_delivery_retry_delay_seconds(uuid, integer),
  public.reconcile_document_outbox_delivery(integer),
  public.lease_document_outbox_events(integer, integer),
  public.ack_document_outbox_event(uuid, uuid, text),
  public.fail_document_outbox_event(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.reconcile_document_outbox_delivery(integer),
  public.lease_document_outbox_events(integer, integer),
  public.ack_document_outbox_event(uuid, uuid, text),
  public.fail_document_outbox_event(uuid, uuid, text)
  TO service_role;

COMMIT;
