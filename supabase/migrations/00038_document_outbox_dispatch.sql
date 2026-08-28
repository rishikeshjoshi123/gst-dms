-- Durable, fenced transport from the transactional outbox to Trigger.dev.
BEGIN;

ALTER TABLE public.outbox_events
  ADD COLUMN next_attempt_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN lease_token uuid,
  ADD COLUMN trigger_run_id text,
  ADD COLUMN last_attempt_at timestamptz,
  ADD CONSTRAINT outbox_events_trigger_run_id_safe CHECK (trigger_run_id IS NULL OR trigger_run_id ~ '^[A-Za-z0-9._:-]{1,200}$');

-- A pre-00038 lease has no fencing token. Make it due again rather than
-- pretending a worker holding that old lease can safely acknowledge it.
UPDATE public.outbox_events
SET delivery_state='pending', lease_expires_at=NULL, next_attempt_at=now(), updated_at=now()
WHERE delivery_state='leased';

ALTER TABLE public.outbox_events DROP CONSTRAINT outbox_events_state_timestamps;
ALTER TABLE public.outbox_events ADD CONSTRAINT outbox_events_state_timestamps CHECK (
  (delivery_state = 'leased' AND lease_expires_at IS NOT NULL AND lease_token IS NOT NULL AND delivered_at IS NULL AND failed_at IS NULL) OR
  (delivery_state = 'delivered' AND lease_expires_at IS NULL AND lease_token IS NULL AND delivered_at IS NOT NULL AND failed_at IS NULL) OR
  (delivery_state IN ('failed','dead_letter') AND lease_expires_at IS NULL AND lease_token IS NULL AND delivered_at IS NULL AND failed_at IS NOT NULL) OR
  (delivery_state = 'pending' AND lease_expires_at IS NULL AND lease_token IS NULL AND delivered_at IS NULL AND failed_at IS NULL)
);

CREATE TABLE public.outbox_dispatch_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.outbox_events(id) ON DELETE RESTRICT,
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  attempt_number integer NOT NULL CHECK (attempt_number > 0),
  -- Correlates a fenced lease without retaining the bearer token itself.
  lease_fingerprint text NOT NULL CHECK (lease_fingerprint ~ '^[0-9a-f]{64}$'),
  outcome text NOT NULL CHECK (outcome IN ('leased','accepted','retry_scheduled','dead_letter')),
  trigger_run_id text CHECK (trigger_run_id IS NULL OR trigger_run_id ~ '^[A-Za-z0-9._:-]{1,200}$'),
  safe_error_code text CHECK (safe_error_code IS NULL OR safe_error_code IN ('gateway_unavailable','gateway_timeout','gateway_rejected','dispatch_failed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT outbox_dispatch_attempts_outcome_fields CHECK (
    (outcome='accepted' AND trigger_run_id IS NOT NULL AND safe_error_code IS NULL) OR
    (outcome IN ('retry_scheduled','dead_letter') AND trigger_run_id IS NULL AND safe_error_code IS NOT NULL) OR
    (outcome='leased' AND trigger_run_id IS NULL AND safe_error_code IS NULL)
  ),
  UNIQUE(event_id, attempt_number, lease_fingerprint, outcome)
);
CREATE INDEX outbox_events_dispatch_due_idx
  ON public.outbox_events(delivery_state, next_attempt_at, created_at, id);
CREATE INDEX outbox_dispatch_attempts_event_idx
  ON public.outbox_dispatch_attempts(event_id, created_at);
ALTER TABLE public.outbox_dispatch_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outbox_dispatch_attempts FORCE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.outbox_dispatch_attempt_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  RAISE EXCEPTION 'outbox dispatch attempts are append-only';
END $$;
CREATE TRIGGER outbox_dispatch_attempts_no_mutation
  BEFORE UPDATE OR DELETE ON public.outbox_dispatch_attempts
  FOR EACH ROW EXECUTE FUNCTION public.outbox_dispatch_attempt_immutable();

CREATE OR REPLACE FUNCTION public.lease_document_outbox_events(p_limit integer DEFAULT 25, p_lease_seconds integer DEFAULT 120)
RETURNS TABLE(event_id uuid, org_id uuid, event_kind text, aggregate_type text, aggregate_id uuid, payload jsonb, idempotency_key text, lease_token uuid, attempt_number integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_lease_seconds IS NULL OR p_lease_seconds NOT BETWEEN 30 AND 600 THEN
    RAISE EXCEPTION 'invalid dispatch lease request';
  END IF;

  WITH expired AS (
    SELECT oe.id AS event_id, oe.org_id AS event_org_id, oe.attempt_count AS event_attempt_count, oe.lease_token AS event_lease_token
    FROM public.outbox_events AS oe
    WHERE oe.delivery_state='leased' AND oe.lease_expires_at <= now() AND oe.attempt_count >= 5
    FOR UPDATE
  ), ledger AS (
    INSERT INTO public.outbox_dispatch_attempts(event_id,org_id,attempt_number,lease_fingerprint,outcome,safe_error_code)
    SELECT expired.event_id, expired.event_org_id, expired.event_attempt_count, encode(extensions.digest(expired.event_lease_token::text, 'sha256'), 'hex'),'dead_letter','dispatch_failed'
    FROM expired
  )
  UPDATE public.outbox_events AS oe
  SET delivery_state='dead_letter', lease_expires_at=NULL, lease_token=NULL, failed_at=now(), last_error_code='dispatch_failed', updated_at=now()
  FROM expired WHERE oe.id=expired.event_id;

  UPDATE public.outbox_events AS oe
  SET delivery_state='pending', lease_expires_at=NULL, lease_token=NULL, next_attempt_at=now(), last_error_code='dispatch_failed', updated_at=now()
  WHERE oe.delivery_state='leased' AND oe.lease_expires_at <= now() AND oe.attempt_count < 5;

  RETURN QUERY
  WITH due AS (
    SELECT oe.id AS event_id FROM public.outbox_events AS oe
    WHERE oe.delivery_state='pending' AND oe.next_attempt_at <= now()
    ORDER BY oe.next_attempt_at, oe.created_at, oe.id
    FOR UPDATE SKIP LOCKED LIMIT p_limit
  ), leased AS (
    UPDATE public.outbox_events AS oe
    SET delivery_state='leased', lease_token=gen_random_uuid(), lease_expires_at=now()+make_interval(secs => p_lease_seconds),
        attempt_count=oe.attempt_count+1, last_attempt_at=now(), next_attempt_at=now(), updated_at=now()
    FROM due WHERE oe.id=due.event_id
    RETURNING oe.id AS event_id, oe.org_id AS event_org_id, oe.event_kind AS event_kind, oe.aggregate_type AS aggregate_type, oe.aggregate_id AS aggregate_id, oe.payload AS payload, oe.idempotency_key AS idempotency_key, oe.lease_token AS lease_token, oe.attempt_count AS attempt_number
  ), ledger AS (
    INSERT INTO public.outbox_dispatch_attempts(event_id,org_id,attempt_number,lease_fingerprint,outcome)
    SELECT leased.event_id, leased.event_org_id, leased.attempt_number, encode(extensions.digest(leased.lease_token::text, 'sha256'), 'hex'),'leased'
    FROM leased
  )
  SELECT leased.event_id AS event_id, leased.event_org_id AS org_id, leased.event_kind AS event_kind, leased.aggregate_type AS aggregate_type, leased.aggregate_id AS aggregate_id, leased.payload AS payload, leased.idempotency_key AS idempotency_key, leased.lease_token AS lease_token, leased.attempt_number AS attempt_number
  FROM leased;
END $$;

CREATE OR REPLACE FUNCTION public.ack_document_outbox_event(p_event_id uuid,p_lease_token uuid,p_trigger_run_id text)
RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE e public.outbox_events%ROWTYPE;
BEGIN
  IF p_event_id IS NULL OR p_lease_token IS NULL OR p_trigger_run_id IS NULL OR p_trigger_run_id !~ '^[A-Za-z0-9._:-]{1,200}$' THEN RETURN QUERY SELECT 'invalid_request'::text; RETURN; END IF;
  SELECT oe.* INTO e FROM public.outbox_events AS oe WHERE oe.id=p_event_id FOR UPDATE;
  IF e.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text; RETURN; END IF;
  IF e.delivery_state='delivered' THEN RETURN QUERY SELECT 'already_accepted'::text; RETURN; END IF;
  IF e.delivery_state<>'leased' OR e.lease_token IS DISTINCT FROM p_lease_token OR e.lease_expires_at <= now() THEN RETURN QUERY SELECT 'stale_lease'::text; RETURN; END IF;
  UPDATE public.outbox_events AS oe SET delivery_state='delivered',lease_token=NULL,lease_expires_at=NULL,delivered_at=now(),trigger_run_id=p_trigger_run_id,updated_at=now() WHERE oe.id=e.id;
  INSERT INTO public.outbox_dispatch_attempts(event_id,org_id,attempt_number,lease_fingerprint,outcome,trigger_run_id) VALUES(e.id,e.org_id,e.attempt_count,encode(extensions.digest(p_lease_token::text, 'sha256'), 'hex'),'accepted',p_trigger_run_id);
  RETURN QUERY SELECT 'ok'::text;
END $$;

CREATE OR REPLACE FUNCTION public.fail_document_outbox_event(p_event_id uuid,p_lease_token uuid,p_safe_error_code text)
RETURNS TABLE(code text,next_attempt_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE e public.outbox_events%ROWTYPE; retry_at timestamptz;
BEGIN
  IF p_event_id IS NULL OR p_lease_token IS NULL OR p_safe_error_code NOT IN ('gateway_unavailable','gateway_timeout','gateway_rejected','dispatch_failed') THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::timestamptz; RETURN; END IF;
  SELECT oe.* INTO e FROM public.outbox_events AS oe WHERE oe.id=p_event_id FOR UPDATE;
  IF e.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text,NULL::timestamptz; RETURN; END IF;
  IF e.delivery_state='dead_letter' THEN RETURN QUERY SELECT 'already_dead_letter'::text,NULL::timestamptz; RETURN; END IF;
  IF e.delivery_state<>'leased' OR e.lease_token IS DISTINCT FROM p_lease_token OR e.lease_expires_at <= now() THEN RETURN QUERY SELECT 'stale_lease'::text,NULL::timestamptz; RETURN; END IF;
  IF e.attempt_count >= 5 THEN
    UPDATE public.outbox_events AS oe SET delivery_state='dead_letter',lease_token=NULL,lease_expires_at=NULL,failed_at=now(),last_error_code=p_safe_error_code,updated_at=now() WHERE oe.id=e.id;
    INSERT INTO public.outbox_dispatch_attempts(event_id,org_id,attempt_number,lease_fingerprint,outcome,safe_error_code) VALUES(e.id,e.org_id,e.attempt_count,encode(extensions.digest(p_lease_token::text, 'sha256'), 'hex'),'dead_letter',p_safe_error_code);
    RETURN QUERY SELECT 'dead_letter'::text,NULL::timestamptz; RETURN;
  END IF;
  retry_at := now() + make_interval(secs => least(300, 5 * (2 ^ least(e.attempt_count, 6))::integer));
  UPDATE public.outbox_events AS oe SET delivery_state='pending',lease_token=NULL,lease_expires_at=NULL,next_attempt_at=retry_at,last_error_code=p_safe_error_code,updated_at=now() WHERE oe.id=e.id;
  INSERT INTO public.outbox_dispatch_attempts(event_id,org_id,attempt_number,lease_fingerprint,outcome,safe_error_code) VALUES(e.id,e.org_id,e.attempt_count,encode(extensions.digest(p_lease_token::text, 'sha256'), 'hex'),'retry_scheduled',p_safe_error_code);
  RETURN QUERY SELECT 'retry_scheduled'::text,retry_at;
END $$;

CREATE VIEW public.document_outbox_dispatch_diagnostics AS
SELECT delivery_state, count(*)::bigint AS event_count,
  min(next_attempt_at) FILTER (WHERE delivery_state='pending') AS oldest_due_at,
  max(now()-lease_expires_at) FILTER (WHERE delivery_state='leased') AS oldest_lease_age
FROM public.outbox_events GROUP BY delivery_state;

-- Command-side inserts remain available through existing security-definer
-- functions. Dispatch workers must use the fenced RPC surface exclusively.
REVOKE ALL ON TABLE public.outbox_events FROM service_role;
REVOKE ALL ON TABLE public.outbox_dispatch_attempts, public.document_outbox_dispatch_diagnostics FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.document_outbox_dispatch_diagnostics TO service_role, postgres;
REVOKE ALL ON FUNCTION public.outbox_dispatch_attempt_immutable(), public.lease_document_outbox_events(integer,integer), public.ack_document_outbox_event(uuid,uuid,text), public.fail_document_outbox_event(uuid,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lease_document_outbox_events(integer,integer), public.ack_document_outbox_event(uuid,uuid,text), public.fail_document_outbox_event(uuid,uuid,text) TO service_role;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.outbox_dispatch_attempts) THEN RAISE EXCEPTION 'outbox dispatch ledger is unexpectedly populated'; END IF;
END $$;
COMMIT;
