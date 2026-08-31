-- Platform Operations prerequisite: private, single-use privileged intents
-- for consequential commands. There is intentionally no browser grant or
-- production caller in this tranche; later server command boundaries must
-- retain the same actor, AAL2, capability, nonce, and consumption checks.
BEGIN;

CREATE TYPE public.platform_privileged_command_family AS ENUM (
  'platform.jobs.retry',
  'platform.organisations.safety_mode.manage',
  'platform.organisations.entitlement.manage',
  'platform.policy.storage_quota.manage',
  'platform.models.runtime_pricing.manage',
  'platform.features.kill_switch.manage',
  'platform.operators.manage',
  'platform.backup_recovery.execute'
);

CREATE OR REPLACE FUNCTION public.platform_privileged_command_capability(
  p_command_family public.platform_privileged_command_family
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT CASE p_command_family
    WHEN 'platform.jobs.retry'::public.platform_privileged_command_family
      THEN 'platform.jobs.retry'
    WHEN 'platform.organisations.safety_mode.manage'::public.platform_privileged_command_family
      THEN 'platform.organisations.safety_mode.manage'
    WHEN 'platform.organisations.entitlement.manage'::public.platform_privileged_command_family
      THEN 'platform.organisations.entitlement.manage'
    WHEN 'platform.policy.storage_quota.manage'::public.platform_privileged_command_family
      THEN 'platform.policy.storage_quota.manage'
    WHEN 'platform.models.runtime_pricing.manage'::public.platform_privileged_command_family
      THEN 'platform.models.runtime_pricing.manage'
    WHEN 'platform.features.kill_switch.manage'::public.platform_privileged_command_family
      THEN 'platform.features.kill_switch.manage'
    WHEN 'platform.operators.manage'::public.platform_privileged_command_family
      THEN 'platform.operators.manage'
    -- Backup/recovery remains a controlled Owner runbook, not a browser
    -- capability. The Owner role check below is deliberately explicit.
    WHEN 'platform.backup_recovery.execute'::public.platform_privileged_command_family
      THEN NULL::text
    ELSE NULL::text
  END
$$;

-- auth.jwt() is populated from a verified Supabase Auth JWT by the API
-- gateway. No caller-supplied MFA/AAL parameter is accepted by any intent
-- function. Direct database-owner sessions remain trusted deployment/test
-- sessions and are not API access paths.
CREATE OR REPLACE FUNCTION public.platform_current_request_has_aal2()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT COALESCE(
    auth.uid() IS NOT NULL
    AND auth.jwt() ->> 'aal' = 'aal2',
    false
  )
$$;

CREATE TABLE public.platform_privileged_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id uuid NOT NULL REFERENCES public.platform_operators(id) ON DELETE RESTRICT,
  command_family public.platform_privileged_command_family NOT NULL,
  issued_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  nonce uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  issuance_idempotency_key uuid NOT NULL UNIQUE,
  CONSTRAINT platform_privileged_intents_expiry_window CHECK (
    expires_at > issued_at
    AND expires_at <= issued_at + interval '10 minutes'
  ),
  CONSTRAINT platform_privileged_intents_actor_command_unique
    UNIQUE (id, operator_id, command_family)
);

CREATE TABLE public.platform_privileged_intent_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  intent_id uuid NOT NULL,
  operator_id uuid NOT NULL,
  command_family public.platform_privileged_command_family NOT NULL,
  consumed_at timestamptz NOT NULL DEFAULT now(),
  consumption_idempotency_key uuid NOT NULL UNIQUE,
  CONSTRAINT platform_privileged_intent_receipts_single_consumption UNIQUE (intent_id),
  CONSTRAINT platform_privileged_intent_receipts_intent_actor_command_fkey
    FOREIGN KEY (intent_id, operator_id, command_family)
    REFERENCES public.platform_privileged_intents(id, operator_id, command_family)
    ON DELETE RESTRICT
);

CREATE OR REPLACE FUNCTION public.platform_privileged_intents_are_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'platform privileged intents are append-only';
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_privileged_intent_receipts_are_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'platform privileged intent receipts are append-only';
END;
$$;

CREATE TRIGGER platform_privileged_intents_prevent_mutation
  BEFORE UPDATE OR DELETE ON public.platform_privileged_intents
  FOR EACH ROW EXECUTE FUNCTION public.platform_privileged_intents_are_append_only();
CREATE TRIGGER platform_privileged_intent_receipts_prevent_mutation
  BEFORE UPDATE OR DELETE ON public.platform_privileged_intent_receipts
  FOR EACH ROW EXECUTE FUNCTION public.platform_privileged_intent_receipts_are_append_only();

-- 00100 initially constrained audit targets to the bootstrap operator row.
-- Intent issuance/consumption needs the same private, append-only audit store
-- without ever writing non-opaque identity, nonce, secret, or command content.
ALTER TABLE public.platform_audit_events
  DROP CONSTRAINT platform_audit_events_bootstrap_actor_shape,
  DROP CONSTRAINT platform_audit_events_safe_metadata,
  DROP CONSTRAINT platform_audit_events_action_check,
  DROP CONSTRAINT platform_audit_events_target_type_check,
  DROP CONSTRAINT platform_audit_events_target_id_fkey;

ALTER TABLE public.platform_audit_events
  ADD CONSTRAINT platform_audit_events_action_check CHECK (
    action IN (
      'platform_operator.bootstrap.v1',
      'platform_privileged_intent.issued.v1',
      'platform_privileged_intent.consumed.v1'
    )
  ),
  ADD CONSTRAINT platform_audit_events_target_type_check CHECK (
    target_type IN ('platform_operator', 'platform_privileged_intent')
  );

CREATE OR REPLACE FUNCTION public.platform_audit_metadata_is_safe(p_metadata jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT jsonb_typeof(p_metadata) = 'object'
    AND NOT EXISTS (
      SELECT 1
      FROM jsonb_object_keys(p_metadata) AS key
      WHERE key NOT IN ('generation', 'operator_role', 'operator_state', 'command_family')
    )
    AND (NOT p_metadata ? 'generation'
      OR jsonb_typeof(p_metadata -> 'generation') = 'number'
        AND (p_metadata ->> 'generation') ~ '^[1-9][0-9]*$')
    AND (NOT p_metadata ? 'operator_role'
      OR p_metadata ->> 'operator_role' IN ('platform_owner', 'platform_operator', 'platform_auditor'))
    AND (NOT p_metadata ? 'operator_state'
      OR p_metadata ->> 'operator_state' IN ('active', 'suspended', 'removed'))
    AND (NOT p_metadata ? 'command_family'
      OR p_metadata ->> 'command_family' IN (
        'platform.jobs.retry',
        'platform.organisations.safety_mode.manage',
        'platform.organisations.entitlement.manage',
        'platform.policy.storage_quota.manage',
        'platform.models.runtime_pricing.manage',
        'platform.features.kill_switch.manage',
        'platform.operators.manage',
        'platform.backup_recovery.execute'
      ))
$$;

ALTER TABLE public.platform_audit_events
  ADD CONSTRAINT platform_audit_events_safe_metadata
  CHECK (public.platform_audit_metadata_is_safe(metadata));

CREATE OR REPLACE FUNCTION public.platform_audit_events_validate_contract()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  intent public.platform_privileged_intents%ROWTYPE;
  actor public.platform_operators%ROWTYPE;
  expected_capability text;
BEGIN
  IF NEW.action = 'platform_operator.bootstrap.v1' THEN
    IF NEW.target_type <> 'platform_operator'
       OR NEW.actor_operator_id IS NOT NULL
       OR NEW.actor_user_id IS NOT NULL
       OR NEW.capability IS NOT NULL
       OR NOT EXISTS (SELECT 1 FROM public.platform_operators WHERE id = NEW.target_id)
       OR NEW.metadata ? 'command_family' THEN
      RAISE EXCEPTION 'invalid platform bootstrap audit event';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.action NOT IN (
    'platform_privileged_intent.issued.v1',
    'platform_privileged_intent.consumed.v1'
  )
     OR NEW.target_type <> 'platform_privileged_intent'
     OR NEW.actor_operator_id IS NULL
     OR NEW.actor_user_id IS NOT NULL
     OR NOT (NEW.metadata ? 'command_family') THEN
    RAISE EXCEPTION 'invalid platform privileged intent audit event';
  END IF;

  SELECT * INTO intent
  FROM public.platform_privileged_intents
  WHERE id = NEW.target_id;
  SELECT * INTO actor
  FROM public.platform_operators
  WHERE id = NEW.actor_operator_id;
  expected_capability := public.platform_privileged_command_capability(
    (NEW.metadata ->> 'command_family')::public.platform_privileged_command_family
  );

  IF intent.id IS NULL
     OR actor.id IS NULL
     OR intent.operator_id <> actor.id
     OR intent.command_family::text <> NEW.metadata ->> 'command_family'
     OR NEW.capability IS DISTINCT FROM expected_capability
     OR (intent.command_family = 'platform.backup_recovery.execute'::public.platform_privileged_command_family
       AND actor.role <> 'platform_owner'::public.platform_operator_role)
     OR (NEW.action = 'platform_privileged_intent.consumed.v1'
       AND NOT EXISTS (
         SELECT 1
         FROM public.platform_privileged_intent_receipts AS receipt
         WHERE receipt.intent_id = intent.id
       )) THEN
    RAISE EXCEPTION 'invalid platform privileged intent audit reference';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER platform_audit_events_validate_contract
  BEFORE INSERT OR UPDATE ON public.platform_audit_events
  FOR EACH ROW EXECUTE FUNCTION public.platform_audit_events_validate_contract();

CREATE OR REPLACE FUNCTION public.issue_platform_privileged_intent(
  p_command_family public.platform_privileged_command_family,
  p_issuance_idempotency_key uuid
)
RETURNS TABLE(
  code text,
  intent_id uuid,
  nonce uuid,
  expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  caller record;
  existing public.platform_privileged_intents%ROWTYPE;
  required_capability text;
  created_intent public.platform_privileged_intents%ROWTYPE;
BEGIN
  IF p_command_family IS NULL
     OR p_issuance_idempotency_key IS NULL
     OR NOT public.platform_current_request_has_aal2() THEN
    RETURN QUERY SELECT 'not_authorized'::text, NULL::uuid, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT * INTO caller
  FROM public.get_my_platform_context() AS context
  WHERE context.code = 'authorized'
  LIMIT 1;
  required_capability := public.platform_privileged_command_capability(p_command_family);
  IF caller.operator_id IS NULL
     OR (required_capability IS NOT NULL AND NOT (required_capability = ANY (caller.capabilities)))
     OR (p_command_family = 'platform.backup_recovery.execute'::public.platform_privileged_command_family
       AND caller.role <> 'platform_owner'::public.platform_operator_role) THEN
    RETURN QUERY SELECT 'not_authorized'::text, NULL::uuid, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('casechain.platform_privileged_intents.issue'),
    pg_catalog.hashtext(p_issuance_idempotency_key::text)
  );
  SELECT * INTO existing
  FROM public.platform_privileged_intents
  WHERE issuance_idempotency_key = p_issuance_idempotency_key;
  IF existing.id IS NOT NULL THEN
    IF existing.operator_id = caller.operator_id
       AND existing.command_family = p_command_family
       AND existing.expires_at > now() THEN
      RETURN QUERY SELECT 'issued'::text, existing.id, existing.nonce, existing.expires_at;
    ELSE
      RETURN QUERY SELECT 'not_authorized'::text, NULL::uuid, NULL::uuid, NULL::timestamptz;
    END IF;
    RETURN;
  END IF;

  INSERT INTO public.platform_privileged_intents (
    operator_id, command_family, expires_at, issuance_idempotency_key
  ) VALUES (
    caller.operator_id,
    p_command_family,
    now() + interval '10 minutes',
    p_issuance_idempotency_key
  ) RETURNING * INTO created_intent;

  INSERT INTO public.platform_audit_events (
    actor_operator_id, capability, target_type, target_id, action, reason_code,
    metadata, correlation_id, idempotency_key, outcome
  ) VALUES (
    caller.operator_id,
    required_capability,
    'platform_privileged_intent',
    created_intent.id,
    'platform_privileged_intent.issued.v1',
    'platform_privileged_intent.issue',
    jsonb_build_object('command_family', p_command_family::text),
    p_issuance_idempotency_key,
    p_issuance_idempotency_key,
    'succeeded'
  );

  RETURN QUERY SELECT 'issued'::text, created_intent.id, created_intent.nonce, created_intent.expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_platform_privileged_intent(
  p_intent_id uuid,
  p_nonce uuid,
  p_command_family public.platform_privileged_command_family
)
RETURNS TABLE(code text, valid boolean)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  caller record;
  required_capability text;
BEGIN
  IF p_intent_id IS NULL
     OR p_nonce IS NULL
     OR p_command_family IS NULL
     OR NOT public.platform_current_request_has_aal2() THEN
    RETURN QUERY SELECT 'not_authorized'::text, false;
    RETURN;
  END IF;
  SELECT * INTO caller
  FROM public.get_my_platform_context() AS context
  WHERE context.code = 'authorized'
  LIMIT 1;
  required_capability := public.platform_privileged_command_capability(p_command_family);
  IF caller.operator_id IS NULL
     OR (required_capability IS NOT NULL AND NOT (required_capability = ANY (caller.capabilities)))
     OR (p_command_family = 'platform.backup_recovery.execute'::public.platform_privileged_command_family
       AND caller.role <> 'platform_owner'::public.platform_operator_role) THEN
    RETURN QUERY SELECT 'not_authorized'::text, false;
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.platform_privileged_intents AS intent
    WHERE intent.id = p_intent_id
      AND intent.nonce = p_nonce
      AND intent.operator_id = caller.operator_id
      AND intent.command_family = p_command_family
      AND intent.expires_at > now()
      AND NOT EXISTS (
        SELECT 1
        FROM public.platform_privileged_intent_receipts AS receipt
        WHERE receipt.intent_id = intent.id
      )
  ) THEN
    RETURN QUERY SELECT 'valid'::text, true;
  ELSE
    RETURN QUERY SELECT 'not_authorized'::text, false;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.consume_platform_privileged_intent(
  p_intent_id uuid,
  p_nonce uuid,
  p_command_family public.platform_privileged_command_family,
  p_consumption_idempotency_key uuid
)
RETURNS TABLE(code text, receipt_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  caller record;
  intent public.platform_privileged_intents%ROWTYPE;
  prior_receipt public.platform_privileged_intent_receipts%ROWTYPE;
  created_receipt public.platform_privileged_intent_receipts%ROWTYPE;
  required_capability text;
BEGIN
  IF p_intent_id IS NULL
     OR p_nonce IS NULL
     OR p_command_family IS NULL
     OR p_consumption_idempotency_key IS NULL
     OR NOT public.platform_current_request_has_aal2() THEN
    RETURN QUERY SELECT 'not_authorized'::text, NULL::uuid;
    RETURN;
  END IF;
  SELECT * INTO caller
  FROM public.get_my_platform_context() AS context
  WHERE context.code = 'authorized'
  LIMIT 1;
  required_capability := public.platform_privileged_command_capability(p_command_family);
  IF caller.operator_id IS NULL
     OR (required_capability IS NOT NULL AND NOT (required_capability = ANY (caller.capabilities)))
     OR (p_command_family = 'platform.backup_recovery.execute'::public.platform_privileged_command_family
       AND caller.role <> 'platform_owner'::public.platform_operator_role) THEN
    RETURN QUERY SELECT 'not_authorized'::text, NULL::uuid;
    RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('casechain.platform_privileged_intents.consume'),
    pg_catalog.hashtext(p_intent_id::text)
  );
  SELECT * INTO intent
  FROM public.platform_privileged_intents
  WHERE id = p_intent_id
  FOR UPDATE;
  IF intent.id IS NULL
     OR intent.nonce <> p_nonce
     OR intent.operator_id <> caller.operator_id
     OR intent.command_family <> p_command_family
     OR intent.expires_at <= now() THEN
    RETURN QUERY SELECT 'not_authorized'::text, NULL::uuid;
    RETURN;
  END IF;

  SELECT * INTO prior_receipt
  FROM public.platform_privileged_intent_receipts
  WHERE intent_id = intent.id;
  IF prior_receipt.id IS NOT NULL THEN
    RETURN QUERY SELECT 'already_consumed'::text, NULL::uuid;
    RETURN;
  END IF;

  SELECT * INTO prior_receipt
  FROM public.platform_privileged_intent_receipts
  WHERE consumption_idempotency_key = p_consumption_idempotency_key;
  IF prior_receipt.id IS NOT NULL THEN
    RETURN QUERY SELECT 'not_authorized'::text, NULL::uuid;
    RETURN;
  END IF;

  INSERT INTO public.platform_privileged_intent_receipts (
    intent_id, operator_id, command_family, consumption_idempotency_key
  ) VALUES (
    intent.id, caller.operator_id, p_command_family, p_consumption_idempotency_key
  ) RETURNING * INTO created_receipt;

  INSERT INTO public.platform_audit_events (
    actor_operator_id, capability, target_type, target_id, action, reason_code,
    metadata, correlation_id, idempotency_key, outcome
  ) VALUES (
    caller.operator_id,
    required_capability,
    'platform_privileged_intent',
    intent.id,
    'platform_privileged_intent.consumed.v1',
    'platform_privileged_intent.consume',
    jsonb_build_object('command_family', p_command_family::text),
    p_consumption_idempotency_key,
    p_consumption_idempotency_key,
    'succeeded'
  );

  RETURN QUERY SELECT 'consumed'::text, created_receipt.id;
END;
$$;

ALTER TABLE public.platform_privileged_intents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_privileged_intents FORCE ROW LEVEL SECURITY;
ALTER TABLE public.platform_privileged_intent_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_privileged_intent_receipts FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.platform_privileged_intents, public.platform_privileged_intent_receipts
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.platform_privileged_command_capability(public.platform_privileged_command_family),
  public.platform_current_request_has_aal2(),
  public.platform_privileged_intents_are_append_only(),
  public.platform_privileged_intent_receipts_are_append_only(),
  public.platform_audit_events_validate_contract(),
  public.issue_platform_privileged_intent(public.platform_privileged_command_family, uuid),
  public.validate_platform_privileged_intent(uuid, uuid, public.platform_privileged_command_family),
  public.consume_platform_privileged_intent(uuid, uuid, public.platform_privileged_command_family, uuid)
FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
