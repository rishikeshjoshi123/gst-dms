-- Run after migration 00038 against a disposable local Supabase database.
BEGIN;

DO $fixture$
DECLARE
  org uuid := '38000000-0000-0000-0000-000000000001';
  owner_id uuid := '38100000-0000-0000-0000-000000000001';
  event_one uuid := '38200000-0000-0000-0000-000000000001';
  event_retry uuid := '38200000-0000-0000-0000-000000000002';
  event_expired uuid := '38200000-0000-0000-0000-000000000003';
  stale_token uuid := '38300000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000',owner_id,'authenticated','authenticated','outbox-dispatch@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES (org,'Outbox dispatch fixture',owner_id);

  INSERT INTO public.outbox_events(id,org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key,next_attempt_at) VALUES
    (event_one,org,'document','38400000-0000-0000-0000-000000000001','document.processing_requested.v1','{"document_id":"38400000-0000-0000-0000-000000000001","version_id":"38500000-0000-0000-0000-000000000001","intake_id":"38600000-0000-0000-0000-000000000001"}','dispatch-one',now()-interval '1 minute'),
    (event_retry,org,'document','38400000-0000-0000-0000-000000000002','document.processing_requested.v1','{"document_id":"38400000-0000-0000-0000-000000000002","version_id":"38500000-0000-0000-0000-000000000002","intake_id":"38600000-0000-0000-0000-000000000002"}','dispatch-retry',now()+interval '1 day'),
    (event_expired,org,'document','38400000-0000-0000-0000-000000000003','document.processing_requested.v1','{"document_id":"38400000-0000-0000-0000-000000000003","version_id":"38500000-0000-0000-0000-000000000003","intake_id":"38600000-0000-0000-0000-000000000003"}','dispatch-expired',now()-interval '1 minute');
  UPDATE public.outbox_events
  SET delivery_state='leased', attempt_count=1, lease_token=stale_token, lease_expires_at=now()-interval '1 minute', last_attempt_at=now()-interval '2 minutes'
  WHERE id=event_expired;
  PERFORM set_config('test.outbox_one',event_one::text,true);
  PERFORM set_config('test.outbox_retry',event_retry::text,true);
  PERFORM set_config('test.outbox_expired',event_expired::text,true);
  PERFORM set_config('test.outbox_stale',stale_token::text,true);
END $fixture$;

SET LOCAL ROLE service_role;
DO $service_surface$
DECLARE r record; denied boolean := false;
BEGIN
  BEGIN
    PERFORM 1 FROM public.outbox_events LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'service role can read raw outbox events directly'; END IF;
  denied:=false;
  BEGIN
    UPDATE public.outbox_events SET delivery_state='delivered' WHERE id=current_setting('test.outbox_one')::uuid;
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'service role can mutate dispatch state directly'; END IF;

  SELECT * INTO r FROM public.lease_document_outbox_events(1,120) WHERE event_id=current_setting('test.outbox_one')::uuid;
  IF r.event_id IS NULL OR r.lease_token IS NULL OR r.attempt_number<>1 OR r.idempotency_key<>'dispatch-one' THEN RAISE EXCEPTION 'due event was not leased'; END IF;
  PERFORM set_config('test.outbox_one_lease',r.lease_token::text,true);
  -- Expired delivery leases are reconciled into their bounded retry schedule
  -- before a later lease, rather than being immediately reissued.
  SELECT * INTO r FROM public.ack_document_outbox_event(current_setting('test.outbox_expired')::uuid,current_setting('test.outbox_stale')::uuid,'run_stale');
  IF r.code<>'stale_lease' THEN RAISE EXCEPTION 'stale worker acknowledgement was accepted'; END IF;
  SELECT * INTO r FROM public.ack_document_outbox_event(current_setting('test.outbox_one')::uuid,current_setting('test.outbox_one_lease')::uuid,'run_one');
  IF r.code<>'ok' THEN RAISE EXCEPTION 'accepted delivery acknowledgement failed'; END IF;
  SELECT * INTO r FROM public.ack_document_outbox_event(current_setting('test.outbox_one')::uuid,current_setting('test.outbox_one_lease')::uuid,'run_one');
  IF r.code<>'already_accepted' THEN RAISE EXCEPTION 'acknowledgement is not idempotent'; END IF;
END $service_surface$;

DO $invalid_lease_request$
DECLARE denied boolean:=false;
BEGIN
  BEGIN
    PERFORM 1 FROM public.lease_document_outbox_events(0,120);
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='invalid dispatch lease request' THEN denied:=true; ELSE RAISE; END IF;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'invalid lease limit failed open'; END IF;
END $invalid_lease_request$;
RESET ROLE;

DO $retry_to_dead_letter$
DECLARE r record; event_retry uuid:=current_setting('test.outbox_retry')::uuid; token uuid;
BEGIN
  UPDATE public.outbox_events SET next_attempt_at=now()-interval '1 second' WHERE id=event_retry;
  FOR i IN 1..5 LOOP
    EXECUTE 'SET LOCAL ROLE service_role';
    SELECT * INTO r FROM public.lease_document_outbox_events(10,120) WHERE event_id=event_retry;
    IF r.event_id IS NULL OR r.lease_token IS NULL THEN RAISE EXCEPTION 'retry event did not lease on attempt %',i; END IF;
    token:=r.lease_token;
    SELECT * INTO r FROM public.fail_document_outbox_event(event_retry,token,'gateway_timeout');
    IF i<5 AND r.code<>'retry_scheduled' THEN RAISE EXCEPTION 'retry failure was not scheduled on attempt %',i; END IF;
    IF i=5 AND r.code<>'dead_letter' THEN RAISE EXCEPTION 'terminal dispatch failure was not dead-lettered'; END IF;
    EXECUTE 'RESET ROLE';
    IF i<5 THEN UPDATE public.outbox_events SET next_attempt_at=now()-interval '1 second' WHERE id=event_retry; END IF;
  END LOOP;
  EXECUTE 'SET LOCAL ROLE service_role';
  SELECT * INTO r FROM public.fail_document_outbox_event(event_retry,token,'gateway_timeout');
  IF r.code<>'already_dead_letter' THEN RAISE EXCEPTION 'dead-letter failure is not idempotent'; END IF;
  EXECUTE 'RESET ROLE';
END $retry_to_dead_letter$;

DO $privileged_assertions$
DECLARE blocked boolean:=false;
BEGIN
  IF (SELECT delivery_state FROM public.outbox_events WHERE id=current_setting('test.outbox_one')::uuid)<>'delivered'
    OR (SELECT trigger_run_id FROM public.outbox_events WHERE id=current_setting('test.outbox_one')::uuid)<>'run_one'
    OR (SELECT delivery_state FROM public.outbox_events WHERE id=current_setting('test.outbox_retry')::uuid)<>'dead_letter' THEN
    RAISE EXCEPTION 'delivery state transitions are incorrect';
  END IF;
  IF (SELECT count(*) FROM public.outbox_dispatch_attempts WHERE event_id=current_setting('test.outbox_one')::uuid AND outcome='accepted')<>1
    OR EXISTS(SELECT 1 FROM public.outbox_dispatch_attempts WHERE safe_error_code !~ '^(gateway_unavailable|gateway_timeout|gateway_rejected|dispatch_failed)$') THEN
    RAISE EXCEPTION 'dispatch attempt ledger is incomplete or unsafe';
  END IF;
  BEGIN
    UPDATE public.outbox_events SET payload='{"document_id":"mutated"}' WHERE id=current_setting('test.outbox_one')::uuid;
  EXCEPTION WHEN raise_exception THEN blocked:=true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'prior outbox event payload was mutable'; END IF;
  blocked:=false;
  BEGIN
    DELETE FROM public.outbox_dispatch_attempts WHERE event_id=current_setting('test.outbox_one')::uuid;
  EXCEPTION WHEN raise_exception THEN blocked:=true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'dispatch attempt ledger was deletable'; END IF;
  IF NOT (SELECT relforcerowsecurity FROM pg_class WHERE oid='public.outbox_dispatch_attempts'::regclass)
    OR EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='outbox_dispatch_attempts' AND column_name='lease_token')
    OR EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='document_outbox_dispatch_diagnostics' AND column_name IN ('payload','org_id','aggregate_id','event_id','lease_token','trigger_run_id'))
    OR pg_get_viewdef('public.document_outbox_dispatch_diagnostics'::regclass) ~* '(payload|filename|object_key|token|content)' THEN
    RAISE EXCEPTION 'dispatch diagnostics expose unsafe data';
  END IF;
END $privileged_assertions$;

SET LOCAL ROLE service_role;
DO $diagnostics$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.document_outbox_dispatch_diagnostics WHERE delivery_state IN ('delivered','dead_letter')) THEN RAISE EXCEPTION 'service diagnostics unavailable'; END IF;
END $diagnostics$;
RESET ROLE;

DO $grant_surface$
BEGIN
  IF has_table_privilege('service_role','public.outbox_events','UPDATE')
    OR has_table_privilege('service_role','public.outbox_dispatch_attempts','INSERT')
    OR has_function_privilege('authenticated','public.lease_document_outbox_events(integer,integer)','EXECUTE')
    OR has_function_privilege('anon','public.ack_document_outbox_event(uuid,uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'outbox dispatch grant surface is too broad';
  END IF;
END $grant_surface$;
ROLLBACK;
