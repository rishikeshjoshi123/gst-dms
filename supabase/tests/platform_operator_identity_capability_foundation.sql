-- Run only against a disposable local database after migration 00100. This
-- fixture creates no committed users, operators, or audit records.
BEGIN;

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'tenant-owner@example.test', 'not-used', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'platform-owner@example.test', 'not-used', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'platform-operator@example.test', 'not-used', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'outsider@example.test', 'not-used', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'unconfirmed@example.test', 'not-used', NULL, '{}', '{}', now(), now());

-- The normal organisation trigger makes this identity a canonical tenant
-- Owner. Tenant ownership must not influence platform context.
INSERT INTO public.organisations (id, name, created_by)
VALUES ('b0000000-0000-0000-0000-000000000001', 'Platform isolation fixture', 'a0000000-0000-0000-0000-000000000001');

DO $test$
DECLARE
  owner_user uuid := 'a0000000-0000-0000-0000-000000000002';
  operator_user uuid := 'a0000000-0000-0000-0000-000000000003';
  tenant_owner uuid := 'a0000000-0000-0000-0000-000000000001';
  outsider_user uuid := 'a0000000-0000-0000-0000-000000000004';
  unconfirmed_user uuid := 'a0000000-0000-0000-0000-000000000005';
  owner_operator uuid;
  operator_snapshot uuid;
  bootstrap_code text;
  attempted boolean;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', tenant_owner::text, true);
  IF NOT public.is_org_admin('b0000000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'tenant fixture was not made an organisation owner';
  END IF;
  IF (SELECT code FROM public.get_my_platform_context()) <> 'not_authorized'
     OR EXISTS (
       SELECT 1 FROM public.get_my_platform_context()
       WHERE operator_id IS NOT NULL OR role IS NOT NULL OR generation IS NOT NULL
     )
     OR public.has_platform_capability('platform.overview.read')
     OR public.has_platform_capability(NULL) THEN
    RAISE EXCEPTION 'tenant owner acquired platform authority';
  END IF;

  SELECT code, operator_id INTO bootstrap_code, owner_operator
  FROM public.bootstrap_platform_owner(unconfirmed_user, 'controlled_deploy_bootstrap', 'c0000000-0000-0000-0000-000000000001');
  IF bootstrap_code <> 'invalid_bootstrap_request' OR owner_operator IS NOT NULL THEN
    RAISE EXCEPTION 'unconfirmed identity bootstrap was accepted';
  END IF;

  SELECT code, operator_id INTO bootstrap_code, owner_operator
  FROM public.bootstrap_platform_owner(owner_user, 'controlled_deploy_bootstrap', 'c0000000-0000-0000-0000-000000000002');
  IF bootstrap_code <> 'bootstrapped' OR owner_operator IS NULL THEN
    RAISE EXCEPTION 'one-time owner bootstrap failed';
  END IF;
  IF (SELECT code FROM public.bootstrap_platform_owner(owner_user, 'controlled_deploy_bootstrap', 'c0000000-0000-0000-0000-000000000002')) <> 'already_bootstrapped'
     OR (SELECT count(*) FROM public.platform_operators) <> 1
     OR (SELECT count(*) FROM public.platform_audit_events) <> 1 THEN
    RAISE EXCEPTION 'bootstrap replay created an additional operator or audit record';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', owner_user::text, true);
  IF (SELECT code FROM public.get_my_platform_context()) <> 'authorized'
     OR (SELECT role FROM public.get_my_platform_context()) <> 'platform_owner'::public.platform_operator_role
     OR NOT public.has_platform_capability('platform.operators.manage')
     OR NOT public.has_platform_capability('platform.operators.read')
     OR public.has_platform_capability('platform.unknown')
     OR public.has_platform_capability(NULL)
     OR public.platform_capability_is_known(NULL) THEN
    RAISE EXCEPTION 'owner capability context did not use the authoritative fail-closed matrix';
  END IF;

  INSERT INTO public.platform_operators (
    user_id, role, state, generation, lifecycle_reason_code, idempotency_key
  ) VALUES (
    operator_user, 'platform_operator', 'active', 1, 'fixture_operator', 'c0000000-0000-0000-0000-000000000003'
  ) RETURNING id INTO operator_snapshot;
  INSERT INTO public.platform_operators (
    user_id, role, state, generation, prior_operator_id, lifecycle_reason_code, idempotency_key
  ) VALUES (
    operator_user, 'platform_operator', 'suspended', 2, operator_snapshot, 'fixture_suspend', 'c0000000-0000-0000-0000-000000000004'
  );
  PERFORM set_config('request.jwt.claim.sub', operator_user::text, true);
  IF (SELECT code FROM public.get_my_platform_context()) <> 'not_authorized'
     OR COALESCE((SELECT cardinality(capabilities) FROM public.get_my_platform_context()), -1) <> 0
     OR public.has_platform_capability('platform.alerts.manage') THEN
    RAISE EXCEPTION 'suspended platform operator retained authority';
  END IF;
  PERFORM set_config('request.jwt.claim.sub', outsider_user::text, true);
  IF (SELECT code FROM public.get_my_platform_context()) <> 'not_authorized'
     OR EXISTS (SELECT 1 FROM public.get_my_platform_context() WHERE operator_id IS NOT NULL OR role IS NOT NULL OR generation IS NOT NULL) THEN
    RAISE EXCEPTION 'non-operator context disclosed lifecycle information';
  END IF;

  -- A new immutable snapshot that disables the sole active owner must fail.
  attempted := false;
  BEGIN
    INSERT INTO public.platform_operators (
      user_id, role, state, generation, prior_operator_id, lifecycle_reason_code, idempotency_key
    ) VALUES (
      owner_user, 'platform_owner', 'suspended', 2, owner_operator, 'fixture_suspend', 'c0000000-0000-0000-0000-000000000005'
    );
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'at least one active platform owner is required' THEN RAISE; END IF;
    attempted := true;
  END;
  IF NOT attempted THEN
    RAISE EXCEPTION 'last active platform owner could be disabled';
  END IF;

  attempted := false;
  BEGIN
    UPDATE public.platform_operators SET state = 'removed' WHERE id = owner_operator;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'platform operator history is append-only' THEN RAISE; END IF;
    attempted := true;
  END;
  IF NOT attempted THEN RAISE EXCEPTION 'platform operator history was mutable'; END IF;
  attempted := false;
  BEGIN
    DELETE FROM public.platform_audit_events;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'platform audit events are append-only' THEN RAISE; END IF;
    attempted := true;
  END;
  IF NOT attempted THEN RAISE EXCEPTION 'platform audit history was mutable'; END IF;
  attempted := false;
  BEGIN
    INSERT INTO public.platform_audit_events (
      target_type, target_id, action, reason_code, metadata, correlation_id, idempotency_key, outcome
    ) VALUES (
      'platform_operator', owner_operator, 'platform_operator.bootstrap.v1', 'fixture_bad_metadata',
      '{"email":"disallowed@example.test"}'::jsonb,
      'c0000000-0000-0000-0000-000000000006', 'c0000000-0000-0000-0000-000000000006', 'succeeded'
    );
  EXCEPTION WHEN check_violation THEN
    attempted := true;
  END;
  IF NOT attempted THEN RAISE EXCEPTION 'unsafe audit metadata was accepted'; END IF;
END;
$test$;

-- Authenticated callers can only request their non-disclosing context. They
-- cannot enumerate/mutate operator or audit tables, or invoke the runbook.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'a0000000-0000-0000-0000-000000000001';
DO $test$
DECLARE statement text;
BEGIN
  FOREACH statement IN ARRAY ARRAY[
    $sql$SELECT * FROM public.platform_operators$sql$,
    $sql$SELECT * FROM public.platform_audit_events$sql$,
    $sql$INSERT INTO public.platform_operators (user_id, role, state, generation, lifecycle_reason_code, idempotency_key) VALUES ('a0000000-0000-0000-0000-000000000001', 'platform_owner', 'active', 1, 'forged', 'c0000000-0000-0000-0000-000000000007')$sql$,
    $sql$UPDATE public.platform_operators SET state = 'removed'$sql$,
    $sql$DELETE FROM public.platform_audit_events$sql$,
    $sql$SELECT * FROM public.bootstrap_platform_owner('a0000000-0000-0000-0000-000000000001', 'forged', 'c0000000-0000-0000-0000-000000000008')$sql$
  ] LOOP
    BEGIN
      EXECUTE statement;
      RAISE EXCEPTION 'authenticated direct platform access unexpectedly succeeded: %', statement;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
END;
$test$;
RESET ROLE;

-- Service role is deliberately not a table-writing escape hatch and cannot
-- call the database-owner bootstrap function.
SET LOCAL ROLE service_role;
DO $test$
DECLARE statement text;
BEGIN
  FOREACH statement IN ARRAY ARRAY[
    $sql$INSERT INTO public.platform_operators (user_id, role, state, generation, lifecycle_reason_code, idempotency_key) VALUES ('a0000000-0000-0000-0000-000000000004', 'platform_owner', 'active', 1, 'forged_service', 'c0000000-0000-0000-0000-000000000009')$sql$,
    $sql$INSERT INTO public.platform_audit_events (target_type, target_id, action, reason_code, metadata, correlation_id, idempotency_key, outcome) VALUES ('platform_operator', '00000000-0000-0000-0000-000000000001', 'platform_operator.bootstrap.v1', 'forged_service', '{}', 'c0000000-0000-0000-0000-000000000010', 'c0000000-0000-0000-0000-000000000010', 'succeeded')$sql$,
    $sql$SELECT * FROM public.bootstrap_platform_owner('a0000000-0000-0000-0000-000000000004', 'forged_service', 'c0000000-0000-0000-0000-000000000011')$sql$
  ] LOOP
    BEGIN
      EXECUTE statement;
      RAISE EXCEPTION 'service-role platform bypass unexpectedly succeeded: %', statement;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
END;
$test$;
RESET ROLE;

ROLLBACK;
