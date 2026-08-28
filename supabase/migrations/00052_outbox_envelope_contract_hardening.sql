-- The database is the authority for the complete safe outbox envelope.
-- Transport validation remains defence in depth; an invalid envelope must
-- never become a leased row.
BEGIN;

-- Jitter is included inside, never beyond, the documented 300 second retry
-- ceiling. The deterministic value avoids an unbounded retry burst without
-- turning the cap into an approximation.
CREATE OR REPLACE FUNCTION public.outbox_delivery_retry_delay_seconds(
  p_event_id uuid,
  p_attempt_number integer
) RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT least(
    300,
    least(300, 5 * (2 ^ least(greatest(p_attempt_number, 1), 6))::integer)
      + (get_byte(decode(md5(p_event_id::text || ':' || p_attempt_number::text), 'hex'), 0) % 17)
  )
$$;

CREATE OR REPLACE FUNCTION public.document_lifecycle_outbox_envelope_is_safe(
  p_event_kind text,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_payload jsonb
) RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  WITH contract(event_kind, aggregate_type, identifier_key, expected_keys) AS (
    VALUES
      ('document.upload_reserved.v1', 'document_upload', 'session_id', ARRAY['session_id', 'intake_id', 'asset_id']::text[]),
      ('document.upload_validation_requested.v1', 'document_upload', 'session_id', ARRAY['session_id', 'intake_id', 'asset_id']::text[]),
      ('document.upload_duplicate.v1', 'document_upload', 'session_id', ARRAY['session_id', 'intake_id']::text[]),
      ('document.upload_failed.v1', 'document_upload', 'session_id', ARRAY['session_id', 'intake_id', 'error_code']::text[]),
      ('document.upload_expired.v1', 'document_upload', 'session_id', ARRAY['session_id']::text[]),
      ('document.intake_validated.v1', 'document', 'intake_id', ARRAY['intake_id', 'asset_id', 'result_code']::text[]),
      ('document.intake_validation_failed.v1', 'document', 'intake_id', ARRAY['intake_id', 'asset_id', 'result_code']::text[]),
      ('document.metadata_created.v1', 'document', 'document_id', ARRAY['document_id', 'matter_id']::text[]),
      ('document.processing_requested.v1', 'document', 'document_id', ARRAY['document_id', 'version_id', 'intake_id']::text[]),
      ('intake.assigned.v1', 'document', 'intake_id', ARRAY['intake_id', 'document_id', 'document_version_id']::text[]),
      ('intake.discarded.v1', 'document', 'intake_id', ARRAY['intake_id', 'result_code']::text[])
  )
  SELECT COALESCE((
    SELECT p_event_kind IS NOT NULL
      AND p_aggregate_type = c.aggregate_type
      AND p_aggregate_id IS NOT NULL
      AND jsonb_typeof(p_payload) = 'object'
      AND p_aggregate_id::text = p_payload ->> c.identifier_key
      AND NOT EXISTS (
        SELECT 1 FROM jsonb_object_keys(p_payload) AS payload_key
        WHERE NOT payload_key = ANY(c.expected_keys)
      )
      AND NOT EXISTS (
        SELECT 1 FROM unnest(c.expected_keys) AS expected_key
        WHERE NOT p_payload ? expected_key
          OR jsonb_typeof(p_payload -> expected_key) <> 'string'
          OR char_length(p_payload ->> expected_key) NOT BETWEEN 1 AND 128
      )
      AND NOT EXISTS (
        SELECT 1 FROM unnest(ARRAY['session_id', 'intake_id', 'asset_id', 'document_id', 'matter_id', 'version_id', 'document_version_id']::text[]) AS identifier_key
        WHERE p_payload ? identifier_key
          AND p_payload ->> identifier_key !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      )
      AND (NOT p_payload ? 'error_code' OR p_payload ->> 'error_code' IN ('upload_failed', 'invalid_pdf', 'malware_suspect', 'storage_missing', 'validation_failed', 'upload_rejected'))
      AND (NOT p_payload ? 'result_code' OR p_payload ->> 'result_code' IN ('ok', 'already_ready', 'not_available', 'invalid_pdf', 'encrypted_pdf', 'malware_suspect', 'storage_missing', 'validation_failed', 'discarded'))
    FROM contract AS c
    WHERE c.event_kind = p_event_kind
  ), false)
$$;

-- Existing installations may contain rows admitted by the earlier broad
-- contract. Preserve those rows in place (including their immutable audit
-- payload), record a content-free quarantine marker, and exclude them from
-- delivery before enforcing the stricter contract for every new write.
-- The same preflight also makes the runtime lease invariants authoritative:
-- a future lease can only contain a bounded attempt and an opaque, bounded
-- idempotency key.
CREATE TABLE public.outbox_event_envelope_quarantines (
  event_id uuid PRIMARY KEY REFERENCES public.outbox_events(id) ON DELETE RESTRICT,
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  prior_delivery_state public.outbox_delivery_state NOT NULL,
  prior_attempt_count integer NOT NULL CHECK (prior_attempt_count >= 0),
  prior_trigger_run_id text,
  prior_delivered_at timestamptz,
  prior_failed_at timestamptz,
  reason_code text NOT NULL DEFAULT 'legacy_invalid_envelope'
    CHECK (reason_code IN ('legacy_invalid_envelope')),
  quarantined_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.outbox_event_envelope_quarantines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outbox_event_envelope_quarantines FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.outbox_event_envelope_quarantines
  FROM PUBLIC, anon, authenticated, service_role;
CREATE OR REPLACE FUNCTION public.quarantine_legacy_outbox_event_envelopes()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE quarantined_count integer;
BEGIN
  WITH candidates AS (
    SELECT oe.id, oe.org_id, oe.delivery_state, oe.attempt_count,
      oe.trigger_run_id, oe.delivered_at, oe.failed_at
    FROM public.outbox_events AS oe
    WHERE NOT public.document_lifecycle_outbox_envelope_is_safe(
        oe.event_kind, oe.aggregate_type, oe.aggregate_id, oe.payload
      )
      OR oe.idempotency_key !~ '^[A-Za-z0-9._:-]{1,200}$'
      OR oe.attempt_count NOT BETWEEN 0 AND 5
      OR (oe.delivery_state = 'pending' AND oe.attempt_count >= 5)
    FOR UPDATE
  ), recorded AS (
    INSERT INTO public.outbox_event_envelope_quarantines(
      event_id, org_id, prior_delivery_state, prior_attempt_count,
      prior_trigger_run_id, prior_delivered_at, prior_failed_at
    )
    SELECT id, org_id, delivery_state, attempt_count,
      trigger_run_id, delivered_at, failed_at
    FROM candidates
    ON CONFLICT (event_id) DO NOTHING
    RETURNING event_id
  ), terminalised AS (
    UPDATE public.outbox_events AS oe
    SET delivery_state='dead_letter',
        lease_token=NULL,
        lease_expires_at=NULL,
        delivered_at=NULL,
        failed_at=now(),
        last_error_code='dispatch_failed',
        updated_at=now()
    FROM recorded AS r
    WHERE oe.id=r.event_id
    RETURNING oe.id
  )
  SELECT count(*) INTO quarantined_count FROM terminalised;
  RETURN quarantined_count;
END $$;
SELECT public.quarantine_legacy_outbox_event_envelopes();

ALTER TABLE public.outbox_events
  ADD CONSTRAINT outbox_events_safe_envelope CHECK (
    public.document_lifecycle_outbox_envelope_is_safe(event_kind, aggregate_type, aggregate_id, payload)
  ) NOT VALID;
ALTER TABLE public.outbox_events
  ADD CONSTRAINT outbox_events_idempotency_key_safe CHECK (
    idempotency_key ~ '^[A-Za-z0-9._:-]{1,200}$'
  ) NOT VALID,
  ADD CONSTRAINT outbox_events_attempt_count_bounded CHECK (
    attempt_count BETWEEN 0 AND 5
    AND (delivery_state <> 'pending' OR attempt_count < 5)
  ) NOT VALID;

ALTER TABLE public.outbox_events
  DROP CONSTRAINT outbox_events_last_error_code_safe;
ALTER TABLE public.outbox_events
  ADD CONSTRAINT outbox_events_last_error_code_safe CHECK (
    last_error_code IS NULL
    OR last_error_code IN ('gateway_unavailable', 'gateway_timeout', 'gateway_rejected', 'dispatch_failed')
  );

-- Helpers remain useful transaction boundaries for existing command writers,
-- but cannot manufacture an event outside the table's immutable envelope
-- constraint. Keep them inaccessible to untrusted callers explicitly.
REVOKE ALL ON FUNCTION public.document_lifecycle_outbox_envelope_is_safe(text, text, uuid, jsonb),
  public.quarantine_legacy_outbox_event_envelopes(),
  public.document_upload_safe_event(uuid, uuid, text, text, jsonb),
  public.document_materialization_safe_event(uuid, uuid, text, text, jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
