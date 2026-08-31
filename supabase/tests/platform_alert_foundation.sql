-- Run only against a disposable local database after migration 00102. This
-- fixture is rollback-scoped and exercises the sole trusted-worker surface;
-- it creates no persistent alert, occurrence, event, or audit history.
BEGIN;

SET LOCAL ROLE service_role;
DO $test$
DECLARE
  opened record; replay record; result record; occurred record;
BEGIN
  SELECT * INTO opened FROM public.upsert_platform_alert(
    'operational_health','warning','organisation','d2000000-0000-0000-0000-000000000001','worker.liveness',
    jsonb_build_object('safe_code','heartbeat_stale','rule_version',1,'threshold',300),
    'd2000000-0000-0000-0000-000000000010',NULL,false,now(),'platform_alert.detected'
  );
  IF opened.code <> 'opened' OR opened.alert_id IS NULL OR opened.state <> 'open' OR opened.revision <> 1 THEN
    RAISE EXCEPTION 'trusted alert creation did not create an open revision-one alert';
  END IF;
  SELECT * INTO replay FROM public.upsert_platform_alert(
    'operational_health','warning','organisation','d2000000-0000-0000-0000-000000000001','worker.liveness',
    jsonb_build_object('safe_code','heartbeat_stale','rule_version',1,'threshold',300),
    'd2000000-0000-0000-0000-000000000010',NULL,false,now(),'platform_alert.detected'
  );
  IF replay.code <> 'replayed' OR replay.alert_id <> opened.alert_id OR replay.revision <> 1 THEN
    RAISE EXCEPTION 'exact producer replay was not idempotent';
  END IF;
  SELECT * INTO result FROM public.upsert_platform_alert(
    'storage_guard','warning','organisation','d2000000-0000-0000-0000-000000000001','worker.liveness','{}',
    'd2000000-0000-0000-0000-000000000010',NULL,false,now(),'platform_alert.detected'
  );
  IF result.code <> 'idempotency_conflict' THEN RAISE EXCEPTION 'cross-identity replay was accepted'; END IF;
  SELECT * INTO result FROM public.upsert_platform_alert(
    'operational_health','warning','organisation','d2000000-0000-0000-0000-000000000001','worker.liveness',
    jsonb_build_object('raw_provider_error','do not retain'),'d2000000-0000-0000-0000-000000000011',1,false,now(),'platform_alert.detected'
  );
  IF result.code <> 'invalid_request' THEN RAISE EXCEPTION 'raw provider metadata was accepted'; END IF;
  SELECT * INTO result FROM public.upsert_platform_alert(
    'operational_health','warning','organisation','d2000000-0000-0000-0000-000000000001','worker.liveness',
    jsonb_build_object('safe_code','ok','storage_path','private/legal.pdf'),'d2000000-0000-0000-0000-000000000012',1,false,now(),'platform_alert.detected'
  );
  IF result.code <> 'invalid_request' THEN RAISE EXCEPTION 'tenant-content path metadata was accepted'; END IF;
  SELECT * INTO result FROM public.upsert_platform_alert(
    'operational_health','critical','organisation','d2000000-0000-0000-0000-000000000001','worker.liveness',
    jsonb_build_object('safe_code','heartbeat_stale','rule_version',1,'threshold',300),
    'd2000000-0000-0000-0000-000000000013',99,false,now(),'platform_alert.detected'
  );
  IF result.code <> 'stale_revision' OR result.revision <> 1 THEN RAISE EXCEPTION 'stale producer overwrote alert state'; END IF;
  SELECT * INTO occurred FROM public.upsert_platform_alert(
    'operational_health','critical','organisation','d2000000-0000-0000-0000-000000000001','worker.liveness',
    jsonb_build_object('safe_code','heartbeat_stale','rule_version',1,'threshold',600),
    'd2000000-0000-0000-0000-000000000018',1,false,now(),'platform_alert.detected'
  );
  IF occurred.code <> 'occurred' OR occurred.state <> 'open' OR occurred.revision <> 2 THEN
    RAISE EXCEPTION 'current open alert occurrence was not revision-fenced and durable';
  END IF;
END;
$test$;
RESET ROLE;

DO $test$
BEGIN
  IF (SELECT count(*) FROM public.platform_alerts) <> 1
     OR (SELECT count(*) FROM public.platform_alert_occurrences) <> 2
     OR (SELECT count(*) FROM public.platform_alert_events) <> 2
     OR (SELECT count(*) FROM public.platform_audit_events WHERE target_type='platform_alert') <> 2
  THEN
    RAISE EXCEPTION 'immutable alert occurrence/event/audit history was incomplete';
  END IF;
END;
$test$;

DO $test$
DECLARE rejected boolean;
BEGIN
  PERFORM set_config('casechain.platform_alerts.write', '', true);
  rejected := false;
  BEGIN UPDATE public.platform_alerts SET state='resolved'; EXCEPTION WHEN raise_exception THEN rejected := SQLERRM='platform alerts require the trusted alert contract'; END;
  IF NOT rejected THEN RAISE EXCEPTION 'direct alert mutation bypassed trusted contract'; END IF;
  rejected := false;
  BEGIN DELETE FROM public.platform_alert_occurrences; EXCEPTION WHEN raise_exception THEN rejected := SQLERRM='platform alert occurrences are append-only'; END;
  IF NOT rejected THEN RAISE EXCEPTION 'alert occurrence history was mutable'; END IF;
  rejected := false;
  BEGIN DELETE FROM public.platform_alert_events; EXCEPTION WHEN raise_exception THEN rejected := SQLERRM='platform alert events are append-only'; END;
  IF NOT rejected THEN RAISE EXCEPTION 'alert event history was mutable'; END IF;
  IF has_table_privilege('authenticated','public.platform_alerts','SELECT')
     OR has_table_privilege('anon','public.platform_alert_events','INSERT')
     OR has_table_privilege('service_role','public.platform_alert_occurrences','INSERT')
     OR has_function_privilege('authenticated','public.upsert_platform_alert(public.platform_alert_kind,public.platform_alert_severity,public.platform_alert_subject_type,uuid,text,jsonb,uuid,integer,boolean,timestamptz,text)','EXECUTE')
     OR to_regprocedure('public.acknowledge_platform_alert(uuid,integer,text,uuid)') IS NOT NULL
     OR to_regprocedure('public.resolve_platform_alert(uuid,integer,text,uuid)') IS NOT NULL
     OR NOT has_function_privilege('service_role','public.upsert_platform_alert(public.platform_alert_kind,public.platform_alert_severity,public.platform_alert_subject_type,uuid,text,jsonb,uuid,integer,boolean,timestamptz,text)','EXECUTE') THEN
    RAISE EXCEPTION 'private alert privilege boundary is unsafe';
  END IF;
END;
$test$;

SET LOCAL ROLE authenticated;
DO $test$
DECLARE statement text;
BEGIN
  FOREACH statement IN ARRAY ARRAY[
    $sql$SELECT * FROM public.platform_alerts$sql$,
    $sql$SELECT * FROM public.platform_alert_occurrences$sql$,
    $sql$UPDATE public.platform_alerts SET state='resolved'$sql$,
    $sql$SELECT * FROM public.upsert_platform_alert('operational_health','warning','platform','d2000000-0000-0000-0000-000000000099','forged','{}','d2000000-0000-0000-0000-000000000099')$sql$
  ] LOOP
    BEGIN EXECUTE statement; RAISE EXCEPTION 'authenticated alert bypass unexpectedly succeeded: %', statement;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
END;
$test$;
RESET ROLE;

ROLLBACK;
