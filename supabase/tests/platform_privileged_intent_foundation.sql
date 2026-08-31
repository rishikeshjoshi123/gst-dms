-- Run only against a disposable local database after migration 00101. This
-- fixture leaves no users, operator snapshots, intents, receipts, or audit
-- rows behind.
BEGIN;

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
  ('00000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'intent-owner@example.test', 'not-used', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'intent-operator@example.test', 'not-used', now(), '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'a1000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'intent-other@example.test', 'not-used', now(), '{}', '{}', now(), now());

DO $test$
DECLARE
  owner_user uuid := 'a1000000-0000-0000-0000-000000000001';
  operator_user uuid := 'a1000000-0000-0000-0000-000000000002';
  other_user uuid := 'a1000000-0000-0000-0000-000000000003';
  owner_operator uuid;
  operator_snapshot uuid;
  issued record;
  replayed record;
  consumed record;
  result record;
  rejected boolean;
BEGIN
  SELECT operator_id INTO owner_operator
  FROM public.bootstrap_platform_owner(owner_user, 'intent_fixture_bootstrap', 'b1000000-0000-0000-0000-000000000001');
  IF owner_operator IS NULL THEN RAISE EXCEPTION 'intent fixture owner bootstrap failed'; END IF;

  INSERT INTO public.platform_operators (
    user_id, role, state, generation, lifecycle_reason_code, idempotency_key
  ) VALUES (
    operator_user, 'platform_operator', 'active', 1, 'intent_fixture_operator', 'b1000000-0000-0000-0000-000000000002'
  ) RETURNING id INTO operator_snapshot;

  -- auth.jwt() reads the signed-request claims representation. The separate
  -- sub GUC also mirrors the local Supabase test convention used by auth.uid().
  PERFORM set_config('request.jwt.claim.sub', owner_user::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', owner_user, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  SELECT * INTO result FROM public.issue_platform_privileged_intent('platform.jobs.retry', 'b1000000-0000-0000-0000-000000000003');
  IF result.code <> 'not_authorized' OR result.intent_id IS NOT NULL THEN
    RAISE EXCEPTION 'AAL1 issued a privileged intent';
  END IF;

  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', owner_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  IF NOT public.platform_current_request_has_aal2() THEN
    RAISE EXCEPTION 'server-verifiable AAL2 claim was not recognized';
  END IF;
  SELECT * INTO issued FROM public.issue_platform_privileged_intent('platform.operators.manage', 'b1000000-0000-0000-0000-000000000004');
  IF issued.code <> 'issued' OR issued.intent_id IS NULL OR issued.nonce IS NULL
     OR issued.expires_at <= now() OR issued.expires_at > now() + interval '10 minutes' THEN
    RAISE EXCEPTION 'owner intent issuance did not produce a bounded receipt';
  END IF;
  SELECT * INTO replayed FROM public.issue_platform_privileged_intent('platform.operators.manage', 'b1000000-0000-0000-0000-000000000004');
  IF replayed.code <> 'issued' OR replayed.intent_id <> issued.intent_id OR replayed.nonce <> issued.nonce
     OR (SELECT count(*) FROM public.platform_privileged_intents WHERE issuance_idempotency_key='b1000000-0000-0000-0000-000000000004') <> 1 THEN
    RAISE EXCEPTION 'issuance idempotency did not preserve one intent';
  END IF;

  SELECT * INTO result FROM public.validate_platform_privileged_intent(issued.intent_id, issued.nonce, 'platform.operators.manage');
  IF result.code <> 'valid' OR NOT result.valid THEN RAISE EXCEPTION 'fresh valid intent was rejected'; END IF;
  SELECT * INTO result FROM public.validate_platform_privileged_intent(issued.intent_id, issued.nonce, 'platform.jobs.retry');
  IF result.code <> 'not_authorized' OR result.valid THEN RAISE EXCEPTION 'wrong command family was accepted'; END IF;
  SELECT * INTO result FROM public.validate_platform_privileged_intent(issued.intent_id, 'b1000000-0000-0000-0000-000000000099', 'platform.operators.manage');
  IF result.code <> 'not_authorized' OR result.valid THEN RAISE EXCEPTION 'forged nonce was accepted'; END IF;
  SELECT * INTO result FROM public.validate_platform_privileged_intent('b1000000-0000-0000-0000-000000000099', issued.nonce, 'platform.operators.manage');
  IF result.code <> 'not_authorized' OR result.valid THEN RAISE EXCEPTION 'forged intent identifier was accepted'; END IF;

  PERFORM set_config('request.jwt.claim.sub', other_user::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', other_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  SELECT * INTO result FROM public.validate_platform_privileged_intent(issued.intent_id, issued.nonce, 'platform.operators.manage');
  IF result.code <> 'not_authorized' OR result.valid THEN RAISE EXCEPTION 'wrong operator validated an intent'; END IF;

  PERFORM set_config('request.jwt.claim.sub', operator_user::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', operator_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  SELECT * INTO result FROM public.issue_platform_privileged_intent('platform.jobs.retry', 'b1000000-0000-0000-0000-000000000005');
  IF result.code <> 'issued' OR result.intent_id IS NULL THEN RAISE EXCEPTION 'operator retry intent was rejected'; END IF;
  SELECT * INTO result FROM public.issue_platform_privileged_intent('platform.models.runtime_pricing.manage', 'b1000000-0000-0000-0000-000000000006');
  IF result.code <> 'not_authorized' OR result.intent_id IS NOT NULL THEN RAISE EXCEPTION 'operator issued an Owner-only intent'; END IF;

  PERFORM set_config('request.jwt.claim.sub', owner_user::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', owner_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  INSERT INTO public.platform_privileged_intents (
    id, operator_id, command_family, issued_at, expires_at, nonce, issuance_idempotency_key
  ) VALUES (
    'b1000000-0000-0000-0000-000000000007', owner_operator, 'platform.jobs.retry',
    now() - interval '20 minutes', now() - interval '10 minutes',
    'b1000000-0000-0000-0000-000000000008', 'b1000000-0000-0000-0000-000000000009'
  );
  SELECT * INTO result FROM public.validate_platform_privileged_intent(
    'b1000000-0000-0000-0000-000000000007', 'b1000000-0000-0000-0000-000000000008', 'platform.jobs.retry'
  );
  IF result.code <> 'not_authorized' OR result.valid THEN RAISE EXCEPTION 'expired intent was accepted'; END IF;

  SELECT * INTO consumed FROM public.consume_platform_privileged_intent(
    issued.intent_id, issued.nonce, 'platform.operators.manage', 'b1000000-0000-0000-0000-000000000010'
  );
  IF consumed.code <> 'consumed' OR consumed.receipt_id IS NULL THEN RAISE EXCEPTION 'valid intent was not consumed'; END IF;
  SELECT * INTO result FROM public.consume_platform_privileged_intent(
    issued.intent_id, issued.nonce, 'platform.operators.manage', 'b1000000-0000-0000-0000-000000000010'
  );
  IF result.code <> 'already_consumed' OR result.receipt_id IS NOT NULL THEN RAISE EXCEPTION 'reused intent did not fail closed'; END IF;
  SELECT * INTO result FROM public.validate_platform_privileged_intent(issued.intent_id, issued.nonce, 'platform.operators.manage');
  IF result.code <> 'not_authorized' OR result.valid THEN RAISE EXCEPTION 'consumed intent remained valid'; END IF;
  IF (SELECT count(*) FROM public.platform_privileged_intent_receipts WHERE intent_id=issued.intent_id) <> 1 THEN
    RAISE EXCEPTION 'intent consumption did not create exactly one receipt';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.platform_audit_events
    WHERE target_id=issued.intent_id
      AND (actor_user_id IS NOT NULL OR metadata ? 'nonce'
        OR metadata::text ~* '(email|secret|password|content|prompt|raw)')
  ) THEN RAISE EXCEPTION 'intent audit retained identity, secret, or raw content'; END IF;
  IF (SELECT count(*) FROM public.platform_audit_events
      WHERE target_id=issued.intent_id AND action IN ('platform_privileged_intent.issued.v1','platform_privileged_intent.consumed.v1')) <> 2 THEN
    RAISE EXCEPTION 'intent issue/consume audit was incomplete or duplicated';
  END IF;

  rejected := false;
  BEGIN
    UPDATE public.platform_privileged_intents SET expires_at=now() WHERE id=issued.intent_id;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'platform privileged intents are append-only' THEN RAISE; END IF;
    rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'intent row was mutable'; END IF;
  rejected := false;
  BEGIN
    DELETE FROM public.platform_privileged_intent_receipts WHERE id=consumed.receipt_id;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'platform privileged intent receipts are append-only' THEN RAISE; END IF;
    rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'intent receipt was mutable'; END IF;

  IF has_table_privilege('authenticated','public.platform_privileged_intents','SELECT')
     OR has_table_privilege('authenticated','public.platform_privileged_intent_receipts','INSERT')
     OR has_table_privilege('service_role','public.platform_privileged_intents','SELECT')
     OR has_table_privilege('service_role','public.platform_privileged_intent_receipts','INSERT')
     OR has_function_privilege('authenticated','public.issue_platform_privileged_intent(public.platform_privileged_command_family,uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.consume_platform_privileged_intent(uuid,uuid,public.platform_privileged_command_family,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'ordinary API authority leaked into private intents';
  END IF;
END;
$test$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'a1000000-0000-0000-0000-000000000001';
SET LOCAL request.jwt.claims = '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';
DO $test$
DECLARE statement text;
BEGIN
  FOREACH statement IN ARRAY ARRAY[
    $sql$SELECT * FROM public.platform_privileged_intents$sql$,
    $sql$SELECT * FROM public.platform_privileged_intent_receipts$sql$,
    $sql$SELECT * FROM public.issue_platform_privileged_intent('platform.jobs.retry','b1000000-0000-0000-0000-000000000011')$sql$,
    $sql$SELECT * FROM public.validate_platform_privileged_intent('b1000000-0000-0000-0000-000000000012','b1000000-0000-0000-0000-000000000013','platform.jobs.retry')$sql$,
    $sql$SELECT * FROM public.consume_platform_privileged_intent('b1000000-0000-0000-0000-000000000012','b1000000-0000-0000-0000-000000000013','platform.jobs.retry','b1000000-0000-0000-0000-000000000014')$sql$
  ] LOOP
    BEGIN
      EXECUTE statement;
      RAISE EXCEPTION 'authenticated intent bypass unexpectedly succeeded: %', statement;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
END;
$test$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $test$
DECLARE statement text;
BEGIN
  FOREACH statement IN ARRAY ARRAY[
    $sql$INSERT INTO public.platform_privileged_intents (operator_id,command_family,expires_at,issuance_idempotency_key) VALUES ('00000000-0000-0000-0000-000000000001','platform.jobs.retry',now()+interval '10 minutes','b1000000-0000-0000-0000-000000000015')$sql$,
    $sql$SELECT * FROM public.issue_platform_privileged_intent('platform.jobs.retry','b1000000-0000-0000-0000-000000000016')$sql$,
    $sql$SELECT * FROM public.consume_platform_privileged_intent('b1000000-0000-0000-0000-000000000012','b1000000-0000-0000-0000-000000000013','platform.jobs.retry','b1000000-0000-0000-0000-000000000017')$sql$
  ] LOOP
    BEGIN
      EXECUTE statement;
      RAISE EXCEPTION 'service-role intent bypass unexpectedly succeeded: %', statement;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
END;
$test$;
RESET ROLE;

ROLLBACK;
