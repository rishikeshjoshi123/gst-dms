-- Platform Operations prerequisite: a trust domain that is deliberately
-- independent of tenant memberships. This migration establishes identity and
-- capability authority only; it creates no console routes, policy, usage, or
-- alert surface.
--
-- First-owner runbook contract:
--   1. In a controlled deploy session, verify the intended auth.users UUID
--      out of band (including its provider verification state).
--   2. Connect as the database owner and call bootstrap_platform_owner with
--      that UUID, a safe reason code, and a fresh idempotency UUID.
--   3. Record the returned opaque operator UUID in the deployment evidence.
-- The function is intentionally not executable by API roles, does not embed a
-- UID, and can succeed only once. It is not a browser bootstrap mechanism.
BEGIN;

CREATE TYPE public.platform_operator_role AS ENUM (
  'platform_owner',
  'platform_operator',
  'platform_auditor'
);

CREATE TYPE public.platform_operator_state AS ENUM (
  'active',
  'suspended',
  'removed'
);

CREATE OR REPLACE FUNCTION public.platform_capability_is_known(p_capability text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(p_capability = ANY (ARRAY[
    'platform.overview.read',
    'platform.organisations.read',
    'platform.usage.read',
    'platform.jobs.read',
    'platform.storage.read',
    'platform.models.read',
    'platform.audit.read',
    'platform.operators.read',
    'platform.alerts.manage',
    'platform.jobs.retry',
    'platform.organisations.safety_mode.manage',
    'platform.organisations.entitlement.manage',
    'platform.policy.storage_quota.manage',
    'platform.models.runtime_pricing.manage',
    'platform.features.kill_switch.manage',
    'platform.operators.manage'
  ]::text[]), false)
$$;

CREATE OR REPLACE FUNCTION public.platform_operator_capabilities(
  p_role public.platform_operator_role,
  p_state public.platform_operator_state
)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT CASE
    WHEN p_role IS NULL OR p_state IS DISTINCT FROM 'active'::public.platform_operator_state
      THEN ARRAY[]::text[]
    WHEN p_role = 'platform_owner'::public.platform_operator_role THEN ARRAY[
      'platform.overview.read',
      'platform.organisations.read',
      'platform.usage.read',
      'platform.jobs.read',
      'platform.storage.read',
      'platform.models.read',
      'platform.audit.read',
      'platform.operators.read',
      'platform.alerts.manage',
      'platform.jobs.retry',
      'platform.organisations.safety_mode.manage',
      'platform.organisations.entitlement.manage',
      'platform.policy.storage_quota.manage',
      'platform.models.runtime_pricing.manage',
      'platform.features.kill_switch.manage',
      'platform.operators.manage'
    ]::text[]
    WHEN p_role = 'platform_operator'::public.platform_operator_role THEN ARRAY[
      'platform.overview.read',
      'platform.organisations.read',
      'platform.usage.read',
      'platform.jobs.read',
      'platform.storage.read',
      'platform.models.read',
      'platform.audit.read',
      'platform.alerts.manage',
      'platform.jobs.retry',
      'platform.organisations.safety_mode.manage',
      'platform.organisations.entitlement.manage'
    ]::text[]
    WHEN p_role = 'platform_auditor'::public.platform_operator_role THEN ARRAY[
      'platform.overview.read',
      'platform.organisations.read',
      'platform.usage.read',
      'platform.jobs.read',
      'platform.storage.read',
      'platform.models.read',
      'platform.audit.read'
    ]::text[]
    ELSE ARRAY[]::text[]
  END
$$;

CREATE TABLE public.platform_operators (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  role public.platform_operator_role NOT NULL,
  state public.platform_operator_state NOT NULL,
  generation integer NOT NULL CHECK (generation > 0),
  prior_operator_id uuid REFERENCES public.platform_operators(id) ON DELETE RESTRICT,
  lifecycle_reason_code text NOT NULL CHECK (
    lifecycle_reason_code ~ '^[a-z0-9_.-]{1,80}$'
  ),
  idempotency_key uuid NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT platform_operators_generation_unique UNIQUE (user_id, generation),
  CONSTRAINT platform_operators_history_shape CHECK (
    (generation = 1 AND prior_operator_id IS NULL)
    OR (generation > 1 AND prior_operator_id IS NOT NULL)
  )
);

CREATE TABLE public.platform_audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_operator_id uuid REFERENCES public.platform_operators(id) ON DELETE RESTRICT,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  capability text CHECK (capability IS NULL OR public.platform_capability_is_known(capability)),
  target_type text NOT NULL CHECK (target_type = 'platform_operator'),
  target_id uuid NOT NULL REFERENCES public.platform_operators(id) ON DELETE RESTRICT,
  action text NOT NULL CHECK (action = 'platform_operator.bootstrap.v1'),
  reason_code text NOT NULL CHECK (reason_code ~ '^[a-z0-9_.-]{1,80}$'),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  correlation_id uuid NOT NULL,
  idempotency_key uuid NOT NULL UNIQUE,
  outcome text NOT NULL CHECK (outcome = 'succeeded'),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT platform_audit_events_bootstrap_actor_shape CHECK (
    action <> 'platform_operator.bootstrap.v1'
    OR (actor_operator_id IS NULL AND actor_user_id IS NULL AND capability IS NULL)
  )
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
      WHERE key NOT IN ('generation', 'operator_role', 'operator_state')
    )
    AND (NOT p_metadata ? 'generation'
      OR jsonb_typeof(p_metadata -> 'generation') = 'number'
        AND (p_metadata ->> 'generation') ~ '^[1-9][0-9]*$')
    AND (NOT p_metadata ? 'operator_role'
      OR p_metadata ->> 'operator_role' IN ('platform_owner', 'platform_operator', 'platform_auditor'))
    AND (NOT p_metadata ? 'operator_state'
      OR p_metadata ->> 'operator_state' IN ('active', 'suspended', 'removed'))
$$;

ALTER TABLE public.platform_audit_events
  ADD CONSTRAINT platform_audit_events_safe_metadata
  CHECK (public.platform_audit_metadata_is_safe(metadata));

CREATE OR REPLACE FUNCTION public.platform_operator_history_is_contiguous()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  predecessor public.platform_operators%ROWTYPE;
BEGIN
  IF NEW.generation = 1 THEN
    IF NEW.prior_operator_id IS NOT NULL THEN
      RAISE EXCEPTION 'first platform operator generation cannot have a predecessor';
    END IF;
    RETURN NEW;
  END IF;

  SELECT * INTO predecessor
  FROM public.platform_operators
  WHERE id = NEW.prior_operator_id
  FOR KEY SHARE;

  IF predecessor.id IS NULL
     OR predecessor.user_id IS DISTINCT FROM NEW.user_id
     OR predecessor.generation <> NEW.generation - 1 THEN
    RAISE EXCEPTION 'platform operator history must extend the preceding generation for the same user';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_operators_are_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'platform operator history is append-only';
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_audit_events_are_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'platform audit events are append-only';
END;
$$;

CREATE OR REPLACE FUNCTION public.assert_platform_owner_invariant()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  -- Serialise state snapshots so two concurrent transitions cannot each see
  -- the other owner as active and commit with no active owner remaining.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('casechain.platform_operators.owner_invariant'));

  IF NOT EXISTS (
    WITH current_operator AS (
      SELECT DISTINCT ON (operator.user_id)
        operator.user_id, operator.role, operator.state
      FROM public.platform_operators AS operator
      ORDER BY operator.user_id, operator.generation DESC
    )
    SELECT 1
    FROM current_operator
    WHERE role = 'platform_owner'::public.platform_operator_role
      AND state = 'active'::public.platform_operator_state
  ) THEN
    RAISE EXCEPTION 'at least one active platform owner is required';
  END IF;
  RETURN NULL;
END;
$$;

CREATE TRIGGER platform_operators_validate_history
  BEFORE INSERT ON public.platform_operators
  FOR EACH ROW EXECUTE FUNCTION public.platform_operator_history_is_contiguous();
CREATE TRIGGER platform_operators_prevent_mutation
  BEFORE UPDATE OR DELETE ON public.platform_operators
  FOR EACH ROW EXECUTE FUNCTION public.platform_operators_are_append_only();
CREATE CONSTRAINT TRIGGER platform_operators_require_active_owner
  AFTER INSERT ON public.platform_operators
  DEFERRABLE INITIALLY IMMEDIATE
  FOR EACH ROW EXECUTE FUNCTION public.assert_platform_owner_invariant();
CREATE TRIGGER platform_audit_events_prevent_mutation
  BEFORE UPDATE OR DELETE ON public.platform_audit_events
  FOR EACH ROW EXECUTE FUNCTION public.platform_audit_events_are_append_only();

CREATE OR REPLACE FUNCTION public.get_my_platform_context()
RETURNS TABLE(
  code text,
  operator_id uuid,
  role public.platform_operator_role,
  capabilities text[],
  generation integer
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public, pg_temp
AS $$
  WITH current_operator AS (
    SELECT DISTINCT ON (operator.user_id)
      operator.id, operator.user_id, operator.role, operator.state, operator.generation
    FROM public.platform_operators AS operator
    WHERE operator.user_id = auth.uid()
    ORDER BY operator.user_id, operator.generation DESC
  )
  SELECT
    CASE WHEN operator.state = 'active'::public.platform_operator_state THEN 'authorized' ELSE 'not_authorized' END,
    CASE WHEN operator.state = 'active'::public.platform_operator_state THEN operator.id ELSE NULL::uuid END,
    CASE WHEN operator.state = 'active'::public.platform_operator_state THEN operator.role ELSE NULL::public.platform_operator_role END,
    CASE WHEN operator.state = 'active'::public.platform_operator_state
      THEN public.platform_operator_capabilities(operator.role, operator.state)
      ELSE ARRAY[]::text[] END,
    CASE WHEN operator.state = 'active'::public.platform_operator_state THEN operator.generation ELSE NULL::integer END
  FROM current_operator AS operator
  UNION ALL
  SELECT 'not_authorized'::text, NULL::uuid, NULL::public.platform_operator_role, ARRAY[]::text[], NULL::integer
  WHERE NOT EXISTS (SELECT 1 FROM current_operator)
$$;

CREATE OR REPLACE FUNCTION public.has_platform_capability(requested_capability text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT COALESCE(requested_capability IS NOT NULL
    AND public.platform_capability_is_known(requested_capability)
    AND EXISTS (
      SELECT 1
      FROM public.get_my_platform_context() AS context
      WHERE context.code = 'authorized'
        AND requested_capability = ANY(context.capabilities)
    ), false)
$$;

CREATE OR REPLACE FUNCTION public.bootstrap_platform_owner(
  p_user_id uuid,
  p_reason_code text,
  p_idempotency_key uuid
)
RETURNS TABLE(code text, operator_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  created_operator_id uuid;
BEGIN
  IF p_user_id IS NULL
     OR p_idempotency_key IS NULL
     OR p_reason_code IS NULL
     OR p_reason_code !~ '^[a-z0-9_.-]{1,80}$'
     OR NOT EXISTS (
       SELECT 1 FROM auth.users
       WHERE id = p_user_id AND email_confirmed_at IS NOT NULL
     ) THEN
    RETURN QUERY SELECT 'invalid_bootstrap_request'::text, NULL::uuid;
    RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('casechain.platform_operators.bootstrap'));
  IF EXISTS (SELECT 1 FROM public.platform_operators) THEN
    RETURN QUERY SELECT 'already_bootstrapped'::text, NULL::uuid;
    RETURN;
  END IF;

  INSERT INTO public.platform_operators (
    user_id, role, state, generation, prior_operator_id, lifecycle_reason_code, idempotency_key
  ) VALUES (
    p_user_id,
    'platform_owner'::public.platform_operator_role,
    'active'::public.platform_operator_state,
    1,
    NULL,
    p_reason_code,
    p_idempotency_key
  ) RETURNING id INTO created_operator_id;

  INSERT INTO public.platform_audit_events (
    target_type, target_id, action, reason_code, metadata, correlation_id, idempotency_key, outcome
  ) VALUES (
    'platform_operator',
    created_operator_id,
    'platform_operator.bootstrap.v1',
    p_reason_code,
    jsonb_build_object('generation', 1, 'operator_role', 'platform_owner', 'operator_state', 'active'),
    p_idempotency_key,
    p_idempotency_key,
    'succeeded'
  );

  RETURN QUERY SELECT 'bootstrapped'::text, created_operator_id;
END;
$$;

ALTER TABLE public.platform_operators ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_operators FORCE ROW LEVEL SECURITY;
ALTER TABLE public.platform_audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_audit_events FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.platform_operators, public.platform_audit_events
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.platform_capability_is_known(text),
  public.platform_operator_capabilities(public.platform_operator_role, public.platform_operator_state),
  public.platform_audit_metadata_is_safe(jsonb),
  public.platform_operator_history_is_contiguous(),
  public.platform_operators_are_append_only(),
  public.platform_audit_events_are_append_only(),
  public.assert_platform_owner_invariant(),
  public.bootstrap_platform_owner(uuid, text, uuid),
  public.get_my_platform_context(),
  public.has_platform_capability(text)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_platform_context(), public.has_platform_capability(text)
  TO authenticated;

COMMIT;
