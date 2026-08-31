-- Platform Operations prerequisite: private, durable alert identity and
-- lifecycle authority. This is deliberately only a trusted-worker contract;
-- it creates neither a console surface nor a live producer or notification
-- consumer. Alert metadata is an explicit safe operational allowlist.
BEGIN;

CREATE TYPE public.platform_alert_kind AS ENUM (
  'configuration_integrity',
  'operational_health',
  'provider_usage_unpriced',
  'storage_guard',
  'backup_freshness',
  'restore_drill'
);

CREATE TYPE public.platform_alert_severity AS ENUM ('warning', 'critical');
CREATE TYPE public.platform_alert_state AS ENUM ('open', 'acknowledged', 'resolved');
CREATE TYPE public.platform_alert_subject_type AS ENUM ('platform', 'organisation', 'operational_run');
CREATE TYPE public.platform_alert_event_type AS ENUM (
  'opened', 'occurred', 'reopened', 'acknowledged', 'resolved'
);

CREATE OR REPLACE FUNCTION public.platform_alert_metadata_is_safe(p_metadata jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT jsonb_typeof(p_metadata) = 'object'
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_object_keys(p_metadata) AS key
      WHERE key NOT IN ('safe_code', 'rule_version', 'threshold', 'observed_count', 'expected_count')
    )
    AND (NOT p_metadata ? 'safe_code'
      OR jsonb_typeof(p_metadata -> 'safe_code') = 'string'
        AND p_metadata ->> 'safe_code' ~ '^[a-z0-9_.-]{1,80}$')
    AND (NOT p_metadata ? 'rule_version'
      OR jsonb_typeof(p_metadata -> 'rule_version') = 'number'
        AND p_metadata ->> 'rule_version' ~ '^[1-9][0-9]*$')
    AND (NOT p_metadata ? 'threshold'
      OR jsonb_typeof(p_metadata -> 'threshold') = 'number'
        AND p_metadata ->> 'threshold' ~ '^(0|[1-9][0-9]*)$')
    AND (NOT p_metadata ? 'observed_count'
      OR jsonb_typeof(p_metadata -> 'observed_count') = 'number'
        AND p_metadata ->> 'observed_count' ~ '^(0|[1-9][0-9]*)$')
    AND (NOT p_metadata ? 'expected_count'
      OR jsonb_typeof(p_metadata -> 'expected_count') = 'number'
        AND p_metadata ->> 'expected_count' ~ '^(0|[1-9][0-9]*)$')
$$;

CREATE TABLE public.platform_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_kind public.platform_alert_kind NOT NULL,
  severity public.platform_alert_severity NOT NULL,
  subject_type public.platform_alert_subject_type NOT NULL,
  subject_id uuid NOT NULL,
  dedupe_key text NOT NULL CHECK (dedupe_key ~ '^[a-z0-9_.:-]{1,120}$'),
  state public.platform_alert_state NOT NULL DEFAULT 'open',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (public.platform_alert_metadata_is_safe(metadata)),
  first_detected_at timestamptz NOT NULL,
  last_detected_at timestamptz NOT NULL,
  occurrence_count integer NOT NULL DEFAULT 1 CHECK (occurrence_count > 0),
  revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  acknowledged_at timestamptz,
  acknowledged_reason_code text CHECK (acknowledged_reason_code IS NULL OR acknowledged_reason_code ~ '^[a-z0-9_.-]{1,80}$'),
  resolved_at timestamptz,
  resolved_reason_code text CHECK (resolved_reason_code IS NULL OR resolved_reason_code ~ '^[a-z0-9_.-]{1,80}$'),
  CONSTRAINT platform_alerts_detected_order CHECK (last_detected_at >= first_detected_at),
  CONSTRAINT platform_alerts_acknowledgement_shape CHECK (
    (acknowledged_at IS NULL AND acknowledged_reason_code IS NULL)
    OR (acknowledged_at IS NOT NULL AND acknowledged_reason_code IS NOT NULL)
  ),
  CONSTRAINT platform_alerts_resolution_shape CHECK (
    (resolved_at IS NULL AND resolved_reason_code IS NULL)
    OR (resolved_at IS NOT NULL AND resolved_reason_code IS NOT NULL)
  ),
  CONSTRAINT platform_alerts_state_shape CHECK (
    (state = 'open' AND acknowledged_at IS NULL AND resolved_at IS NULL)
    OR (state = 'acknowledged' AND acknowledged_at IS NOT NULL AND resolved_at IS NULL)
    OR (state = 'resolved' AND resolved_at IS NOT NULL)
  ),
  CONSTRAINT platform_alerts_logical_identity_unique
    UNIQUE (alert_kind, subject_type, subject_id, dedupe_key)
);

CREATE TABLE public.platform_alert_occurrences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id uuid NOT NULL REFERENCES public.platform_alerts(id) ON DELETE RESTRICT,
  source_occurrence_id uuid NOT NULL UNIQUE,
  observed_at timestamptz NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (public.platform_alert_metadata_is_safe(metadata)),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.platform_alert_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id uuid NOT NULL REFERENCES public.platform_alerts(id) ON DELETE RESTRICT,
  occurrence_id uuid REFERENCES public.platform_alert_occurrences(id) ON DELETE RESTRICT,
  event_type public.platform_alert_event_type NOT NULL,
  prior_state public.platform_alert_state,
  state public.platform_alert_state NOT NULL,
  revision integer NOT NULL CHECK (revision > 0),
  reason_code text NOT NULL CHECK (reason_code ~ '^[a-z0-9_.-]{1,80}$'),
  idempotency_key uuid NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT platform_alert_events_transition_shape CHECK (
    (event_type = 'opened' AND prior_state IS NULL AND state = 'open' AND occurrence_id IS NOT NULL)
    OR (event_type = 'occurred' AND prior_state = state AND occurrence_id IS NOT NULL)
    OR (event_type = 'reopened' AND prior_state = 'resolved' AND state = 'open' AND occurrence_id IS NOT NULL)
    OR (event_type = 'acknowledged' AND prior_state = 'open' AND state = 'acknowledged' AND occurrence_id IS NULL)
    OR (event_type = 'resolved' AND prior_state IN ('open', 'acknowledged') AND state = 'resolved' AND occurrence_id IS NULL)
  )
);

CREATE INDEX platform_alerts_active_order_idx
  ON public.platform_alerts (state, severity, last_detected_at DESC);
CREATE INDEX platform_alert_occurrences_alert_observed_idx
  ON public.platform_alert_occurrences (alert_id, observed_at DESC);
CREATE INDEX platform_alert_events_alert_created_idx
  ON public.platform_alert_events (alert_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.platform_alerts_are_write_controlled()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF current_setting('casechain.platform_alerts.write', true) IS DISTINCT FROM 'allowed' THEN
    RAISE EXCEPTION 'platform alerts require the trusted alert contract';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_alert_occurrences_are_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'platform alert occurrences are append-only';
  END IF;
  IF current_setting('casechain.platform_alerts.write', true) IS DISTINCT FROM 'allowed' THEN
    RAISE EXCEPTION 'platform alert occurrences require the trusted alert contract';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_alert_events_are_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'platform alert events are append-only';
  END IF;
  IF current_setting('casechain.platform_alerts.write', true) IS DISTINCT FROM 'allowed' THEN
    RAISE EXCEPTION 'platform alert events require the trusted alert contract';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER platform_alerts_require_trusted_contract
  BEFORE INSERT OR UPDATE OR DELETE ON public.platform_alerts
  FOR EACH ROW EXECUTE FUNCTION public.platform_alerts_are_write_controlled();
CREATE TRIGGER platform_alert_occurrences_prevent_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.platform_alert_occurrences
  FOR EACH ROW EXECUTE FUNCTION public.platform_alert_occurrences_are_append_only();
CREATE TRIGGER platform_alert_events_prevent_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.platform_alert_events
  FOR EACH ROW EXECUTE FUNCTION public.platform_alert_events_are_append_only();

-- Extend the existing private audit contract with alert-safe, opaque events.
ALTER TABLE public.platform_audit_events
  DROP CONSTRAINT platform_audit_events_action_check,
  DROP CONSTRAINT platform_audit_events_target_type_check,
  DROP CONSTRAINT platform_audit_events_safe_metadata;

ALTER TABLE public.platform_audit_events
  ADD CONSTRAINT platform_audit_events_action_check CHECK (action IN (
    'platform_operator.bootstrap.v1',
    'platform_privileged_intent.issued.v1',
    'platform_privileged_intent.consumed.v1',
    'platform_alert.opened.v1',
    'platform_alert.occurred.v1',
    'platform_alert.reopened.v1',
    'platform_alert.acknowledged.v1',
    'platform_alert.resolved.v1'
  )),
  ADD CONSTRAINT platform_audit_events_target_type_check CHECK (
    target_type IN ('platform_operator', 'platform_privileged_intent', 'platform_alert')
  );

CREATE OR REPLACE FUNCTION public.platform_audit_metadata_is_safe(p_metadata jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT jsonb_typeof(p_metadata) = 'object'
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_object_keys(p_metadata) AS key
      WHERE key NOT IN (
        'generation', 'operator_role', 'operator_state', 'command_family',
        'alert_kind', 'severity', 'subject_type', 'state', 'revision', 'occurrence_count'
      )
    )
    AND (NOT p_metadata ? 'generation' OR (jsonb_typeof(p_metadata -> 'generation') = 'number' AND (p_metadata ->> 'generation') ~ '^[1-9][0-9]*$'))
    AND (NOT p_metadata ? 'operator_role' OR p_metadata ->> 'operator_role' IN ('platform_owner', 'platform_operator', 'platform_auditor'))
    AND (NOT p_metadata ? 'operator_state' OR p_metadata ->> 'operator_state' IN ('active', 'suspended', 'removed'))
    AND (NOT p_metadata ? 'command_family' OR p_metadata ->> 'command_family' IN (
      'platform.jobs.retry', 'platform.organisations.safety_mode.manage', 'platform.organisations.entitlement.manage',
      'platform.policy.storage_quota.manage', 'platform.models.runtime_pricing.manage', 'platform.features.kill_switch.manage',
      'platform.operators.manage', 'platform.backup_recovery.execute'))
    AND (NOT p_metadata ? 'alert_kind' OR p_metadata ->> 'alert_kind' IN (
      'configuration_integrity', 'operational_health', 'provider_usage_unpriced', 'storage_guard', 'backup_freshness', 'restore_drill'))
    AND (NOT p_metadata ? 'severity' OR p_metadata ->> 'severity' IN ('warning', 'critical'))
    AND (NOT p_metadata ? 'subject_type' OR p_metadata ->> 'subject_type' IN ('platform', 'organisation', 'operational_run'))
    AND (NOT p_metadata ? 'state' OR p_metadata ->> 'state' IN ('open', 'acknowledged', 'resolved'))
    AND (NOT p_metadata ? 'revision' OR (jsonb_typeof(p_metadata -> 'revision') = 'number' AND (p_metadata ->> 'revision') ~ '^[1-9][0-9]*$'))
    AND (NOT p_metadata ? 'occurrence_count' OR (jsonb_typeof(p_metadata -> 'occurrence_count') = 'number' AND (p_metadata ->> 'occurrence_count') ~ '^[1-9][0-9]*$'))
$$;

ALTER TABLE public.platform_audit_events
  ADD CONSTRAINT platform_audit_events_safe_metadata CHECK (public.platform_audit_metadata_is_safe(metadata));

CREATE OR REPLACE FUNCTION public.platform_audit_events_validate_contract()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  intent public.platform_privileged_intents%ROWTYPE;
  actor public.platform_operators%ROWTYPE;
  alert public.platform_alerts%ROWTYPE;
  expected_capability text;
BEGIN
  IF NEW.action = 'platform_operator.bootstrap.v1' THEN
    IF NEW.target_type <> 'platform_operator' OR NEW.actor_operator_id IS NOT NULL OR NEW.actor_user_id IS NOT NULL
       OR NEW.capability IS NOT NULL OR NOT EXISTS (SELECT 1 FROM public.platform_operators WHERE id = NEW.target_id)
       OR NEW.metadata ? 'command_family' THEN RAISE EXCEPTION 'invalid platform bootstrap audit event'; END IF;
    RETURN NEW;
  END IF;

  IF NEW.action IN ('platform_alert.opened.v1','platform_alert.occurred.v1','platform_alert.reopened.v1','platform_alert.acknowledged.v1','platform_alert.resolved.v1') THEN
    SELECT * INTO alert FROM public.platform_alerts WHERE id = NEW.target_id;
    IF NEW.target_type <> 'platform_alert' OR NEW.actor_operator_id IS NOT NULL OR NEW.actor_user_id IS NOT NULL
       OR NEW.capability IS NOT NULL OR alert.id IS NULL
       OR NOT (NEW.metadata ?& ARRAY['alert_kind','severity','subject_type','state','revision','occurrence_count'])
       OR NEW.metadata ->> 'alert_kind' <> alert.alert_kind::text
       OR NEW.metadata ->> 'severity' <> alert.severity::text
       OR NEW.metadata ->> 'subject_type' <> alert.subject_type::text
       OR NEW.metadata ->> 'state' <> alert.state::text
       OR (NEW.metadata ->> 'revision')::integer <> alert.revision
       OR (NEW.metadata ->> 'occurrence_count')::integer <> alert.occurrence_count THEN
      RAISE EXCEPTION 'invalid platform alert audit event';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.action NOT IN ('platform_privileged_intent.issued.v1', 'platform_privileged_intent.consumed.v1')
     OR NEW.target_type <> 'platform_privileged_intent' OR NEW.actor_operator_id IS NULL
     OR NEW.actor_user_id IS NOT NULL OR NOT (NEW.metadata ? 'command_family') THEN
    RAISE EXCEPTION 'invalid platform privileged intent audit event';
  END IF;
  SELECT * INTO intent FROM public.platform_privileged_intents WHERE id = NEW.target_id;
  SELECT * INTO actor FROM public.platform_operators WHERE id = NEW.actor_operator_id;
  expected_capability := public.platform_privileged_command_capability((NEW.metadata ->> 'command_family')::public.platform_privileged_command_family);
  IF intent.id IS NULL OR actor.id IS NULL OR intent.operator_id <> actor.id
     OR intent.command_family::text <> NEW.metadata ->> 'command_family' OR NEW.capability IS DISTINCT FROM expected_capability
     OR (intent.command_family = 'platform.backup_recovery.execute'::public.platform_privileged_command_family AND actor.role <> 'platform_owner'::public.platform_operator_role)
     OR (NEW.action = 'platform_privileged_intent.consumed.v1' AND NOT EXISTS (SELECT 1 FROM public.platform_privileged_intent_receipts receipt WHERE receipt.intent_id = intent.id)) THEN
    RAISE EXCEPTION 'invalid platform privileged intent audit reference';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_platform_alert_audit(
  p_alert public.platform_alerts,
  p_action text,
  p_reason_code text,
  p_idempotency_key uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  INSERT INTO public.platform_audit_events (
    target_type, target_id, action, reason_code, metadata, correlation_id, idempotency_key, outcome
  ) VALUES (
    'platform_alert', p_alert.id, p_action, p_reason_code,
    jsonb_build_object('alert_kind', p_alert.alert_kind::text, 'severity', p_alert.severity::text,
      'subject_type', p_alert.subject_type::text, 'state', p_alert.state::text,
      'revision', p_alert.revision, 'occurrence_count', p_alert.occurrence_count),
    p_idempotency_key, p_idempotency_key, 'succeeded'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_platform_alert(
  p_alert_kind public.platform_alert_kind,
  p_severity public.platform_alert_severity,
  p_subject_type public.platform_alert_subject_type,
  p_subject_id uuid,
  p_dedupe_key text,
  p_metadata jsonb,
  p_source_occurrence_id uuid,
  p_expected_revision integer DEFAULT NULL,
  p_reopen_resolved boolean DEFAULT false,
  p_observed_at timestamptz DEFAULT now(),
  p_reason_code text DEFAULT 'platform_alert.detected'
)
RETURNS TABLE(code text, alert_id uuid, state public.platform_alert_state, revision integer, occurrence_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  alert public.platform_alerts%ROWTYPE;
  occurrence public.platform_alert_occurrences%ROWTYPE;
  event_type public.platform_alert_event_type;
  audit_action text;
  prior_state public.platform_alert_state;
BEGIN
  IF p_alert_kind IS NULL OR p_severity IS NULL OR p_subject_type IS NULL OR p_subject_id IS NULL
     OR p_dedupe_key IS NULL OR p_dedupe_key !~ '^[a-z0-9_.:-]{1,120}$'
     OR p_metadata IS NULL OR NOT public.platform_alert_metadata_is_safe(p_metadata)
     OR p_source_occurrence_id IS NULL OR p_observed_at IS NULL OR p_reason_code IS NULL
     OR p_reason_code !~ '^[a-z0-9_.-]{1,80}$' OR p_expected_revision IS NOT NULL AND p_expected_revision < 1 THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid, NULL::public.platform_alert_state, NULL::integer, NULL::uuid;
    RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('casechain.platform_alerts.' || p_alert_kind::text || '.' || p_subject_type::text || '.' || p_subject_id::text || '.' || p_dedupe_key));
  SELECT * INTO occurrence FROM public.platform_alert_occurrences
  WHERE source_occurrence_id = p_source_occurrence_id;
  IF occurrence.id IS NOT NULL THEN
    SELECT * INTO alert FROM public.platform_alerts WHERE id = occurrence.alert_id;
    IF alert.alert_kind = p_alert_kind AND alert.subject_type = p_subject_type AND alert.subject_id = p_subject_id AND alert.dedupe_key = p_dedupe_key THEN
      RETURN QUERY SELECT 'replayed'::text, alert.id, alert.state, alert.revision, occurrence.id;
    ELSE
      RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::uuid, NULL::public.platform_alert_state, NULL::integer, NULL::uuid;
    END IF;
    RETURN;
  END IF;
  SELECT * INTO alert FROM public.platform_alerts
  WHERE alert_kind = p_alert_kind AND subject_type = p_subject_type AND subject_id = p_subject_id AND dedupe_key = p_dedupe_key FOR UPDATE;
  PERFORM set_config('casechain.platform_alerts.write', 'allowed', true);
  IF alert.id IS NULL THEN
    IF p_expected_revision IS NOT NULL THEN
      RETURN QUERY SELECT 'stale_revision'::text, NULL::uuid, NULL::public.platform_alert_state, NULL::integer, NULL::uuid;
      RETURN;
    END IF;
    INSERT INTO public.platform_alerts (alert_kind,severity,subject_type,subject_id,dedupe_key,state,metadata,first_detected_at,last_detected_at,occurrence_count,revision)
    VALUES (p_alert_kind,p_severity,p_subject_type,p_subject_id,p_dedupe_key,'open',p_metadata,p_observed_at,p_observed_at,1,1)
    RETURNING * INTO alert;
    event_type := 'opened'; audit_action := 'platform_alert.opened.v1'; prior_state := NULL;
  ELSE
    IF p_expected_revision IS DISTINCT FROM alert.revision THEN
      RETURN QUERY SELECT 'stale_revision'::text, alert.id, alert.state, alert.revision, NULL::uuid;
      RETURN;
    END IF;
    prior_state := alert.state;
    IF alert.state = 'resolved' AND p_reopen_resolved THEN
      UPDATE public.platform_alerts SET severity=p_severity, metadata=p_metadata, last_detected_at=GREATEST(last_detected_at,p_observed_at), occurrence_count=platform_alerts.occurrence_count+1,
        revision=platform_alerts.revision+1, state='open', acknowledged_at=NULL, acknowledged_reason_code=NULL, resolved_at=NULL, resolved_reason_code=NULL
      WHERE id=alert.id RETURNING * INTO alert;
      event_type := 'reopened'; audit_action := 'platform_alert.reopened.v1';
    ELSE
      UPDATE public.platform_alerts SET severity=p_severity, metadata=p_metadata, last_detected_at=GREATEST(last_detected_at,p_observed_at), occurrence_count=platform_alerts.occurrence_count+1, revision=platform_alerts.revision+1
      WHERE id=alert.id RETURNING * INTO alert;
      event_type := 'occurred'; audit_action := 'platform_alert.occurred.v1';
    END IF;
  END IF;
  INSERT INTO public.platform_alert_occurrences (alert_id,source_occurrence_id,observed_at,metadata)
  VALUES (alert.id,p_source_occurrence_id,p_observed_at,p_metadata) RETURNING * INTO occurrence;
  INSERT INTO public.platform_alert_events (alert_id,occurrence_id,event_type,prior_state,state,revision,reason_code,idempotency_key)
  VALUES (alert.id,occurrence.id,event_type,prior_state,alert.state,alert.revision,p_reason_code,p_source_occurrence_id);
  PERFORM public.record_platform_alert_audit(alert,audit_action,p_reason_code,p_source_occurrence_id);
  RETURN QUERY SELECT CASE WHEN event_type='occurred' AND prior_state='resolved' THEN 'resolved_recorded' ELSE event_type::text END, alert.id, alert.state, alert.revision, occurrence.id;
END;
$$;

ALTER TABLE public.platform_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_alerts FORCE ROW LEVEL SECURITY;
ALTER TABLE public.platform_alert_occurrences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_alert_occurrences FORCE ROW LEVEL SECURITY;
ALTER TABLE public.platform_alert_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_alert_events FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.platform_alerts, public.platform_alert_occurrences, public.platform_alert_events FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.platform_alert_metadata_is_safe(jsonb), public.platform_alerts_are_write_controlled(),
  public.platform_alert_occurrences_are_append_only(), public.platform_alert_events_are_append_only(),
  public.record_platform_alert_audit(public.platform_alerts,text,text,uuid),
  public.upsert_platform_alert(public.platform_alert_kind,public.platform_alert_severity,public.platform_alert_subject_type,uuid,text,jsonb,uuid,integer,boolean,timestamptz,text)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  public.upsert_platform_alert(public.platform_alert_kind,public.platform_alert_severity,public.platform_alert_subject_type,uuid,text,jsonb,uuid,integer,boolean,timestamptz,text)
TO service_role;

COMMIT;
