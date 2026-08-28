-- Run after migration 00051 against a disposable local Supabase database.
BEGIN;

DO $fixture$
DECLARE
  owner_a uuid := '51000000-0000-0000-0000-000000000001';
  owner_b uuid := '51000000-0000-0000-0000-000000000002';
  org_a uuid := '51100000-0000-0000-0000-000000000001';
  org_b uuid := '51100000-0000-0000-0000-000000000002';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES
    ('00000000-0000-0000-0000-000000000000',owner_a,'authenticated','authenticated','outbox-authority-a@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',owner_b,'authenticated','authenticated','outbox-authority-b@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by)
  VALUES (org_a,'Outbox authority A',owner_a),(org_b,'Outbox authority B',owner_b);

  INSERT INTO public.outbox_events(id,org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key,next_attempt_at)
  VALUES
    ('51200000-0000-0000-0000-000000000001',org_a,'document','51300000-0000-0000-0000-000000000001','document.processing_requested.v1',jsonb_build_object('document_id','51300000-0000-0000-0000-000000000001','version_id','51400000-0000-0000-0000-000000000001','intake_id','51500000-0000-0000-0000-000000000001'),'fair-a-one',now()-interval '3 minutes'),
    ('51200000-0000-0000-0000-000000000002',org_a,'document','51300000-0000-0000-0000-000000000002','document.processing_requested.v1',jsonb_build_object('document_id','51300000-0000-0000-0000-000000000002','version_id','51400000-0000-0000-0000-000000000002','intake_id','51500000-0000-0000-0000-000000000002'),'fair-a-two',now()-interval '2 minutes'),
    ('51200000-0000-0000-0000-000000000003',org_b,'document','51300000-0000-0000-0000-000000000003','document.processing_requested.v1',jsonb_build_object('document_id','51300000-0000-0000-0000-000000000003','version_id','51400000-0000-0000-0000-000000000003','intake_id','51500000-0000-0000-0000-000000000003'),'fair-b-one',now()-interval '1 minute'),
    ('51200000-0000-0000-0000-000000000004',org_a,'document','51300000-0000-0000-0000-000000000004','document.processing_requested.v1',jsonb_build_object('document_id','51300000-0000-0000-0000-000000000004','version_id','51400000-0000-0000-0000-000000000004','intake_id','51500000-0000-0000-0000-000000000004'),'expired-retry',now()+interval '1 hour'),
    ('51200000-0000-0000-0000-000000000005',org_b,'document','51300000-0000-0000-0000-000000000005','document.processing_requested.v1',jsonb_build_object('document_id','51300000-0000-0000-0000-000000000005','version_id','51400000-0000-0000-0000-000000000005','intake_id','51500000-0000-0000-0000-000000000005'),'expired-dead',now()+interval '1 hour');
  UPDATE public.outbox_events
  SET delivery_state='leased', attempt_count=4,
      lease_token='51600000-0000-0000-0000-000000000004',
      lease_expires_at=now()-interval '1 minute', last_attempt_at=now()-interval '2 minutes'
  WHERE id='51200000-0000-0000-0000-000000000004';
  UPDATE public.outbox_events
  SET delivery_state='leased', attempt_count=5,
      lease_token='51600000-0000-0000-0000-000000000005',
      lease_expires_at=now()-interval '1 minute', last_attempt_at=now()-interval '2 minutes'
  WHERE id='51200000-0000-0000-0000-000000000005';
END $fixture$;

-- Model an upgrade from the prior broad contract. A poisoned historical row
-- remains in its audit table, but is terminalised and marked without copying
-- its payload. Re-adding NOT VALID checks lets the strict contract govern all
-- future writes while preserving that historical record.
DO $legacy_upgrade_quarantine$
DECLARE
  quarantined integer;
  marker record;
BEGIN
  ALTER TABLE public.outbox_events
    DROP CONSTRAINT outbox_events_safe_envelope,
    DROP CONSTRAINT outbox_events_idempotency_key_safe,
    DROP CONSTRAINT outbox_events_attempt_count_bounded;
  INSERT INTO public.outbox_events(
    id, org_id, aggregate_type, aggregate_id, event_kind, payload,
    idempotency_key, attempt_count
  ) VALUES (
    '51200000-0000-0000-0000-000000000006',
    '51100000-0000-0000-0000-000000000001',
    'document', '51300000-0000-0000-0000-000000000006',
    'document.processing_requested.v1',
    jsonb_build_object('instruction', 'legacy provider prompt'),
    'legacy unsafe key', 6
  );
  INSERT INTO public.outbox_events(
    id, org_id, aggregate_type, aggregate_id, event_kind, payload,
    idempotency_key, attempt_count
  ) VALUES (
    '51200000-0000-0000-0000-000000000007',
    '51100000-0000-0000-0000-000000000001',
    'document', '51300000-0000-0000-0000-000000000007',
    'document.processing_requested.v1',
    jsonb_build_object(
      'document_id', '51300000-0000-0000-0000-000000000007',
      'version_id', '51400000-0000-0000-0000-000000000007',
      'intake_id', '51500000-0000-0000-0000-000000000007'
    ),
    'legacy-at-cap', 5
  );
  SELECT public.quarantine_legacy_outbox_event_envelopes() INTO quarantined;
  IF quarantined<>2 THEN
    RAISE EXCEPTION 'legacy outbox preflight did not quarantine every invalid envelope';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.outbox_events
    WHERE id='51200000-0000-0000-0000-000000000006'
      AND payload=jsonb_build_object('instruction', 'legacy provider prompt')
      AND delivery_state='dead_letter'
      AND last_error_code='dispatch_failed'
      AND failed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'legacy invalid envelope was deleted or left deliverable';
  END IF;
  SELECT * INTO marker FROM public.outbox_event_envelope_quarantines
  WHERE event_id='51200000-0000-0000-0000-000000000006';
  IF marker.event_id IS NULL OR marker.prior_delivery_state<>'pending'
     OR marker.prior_attempt_count<>6 THEN
    RAISE EXCEPTION 'legacy invalid envelope lost its delivery audit marker';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.outbox_events AS oe
    JOIN public.outbox_event_envelope_quarantines AS q ON q.event_id=oe.id
    WHERE oe.id='51200000-0000-0000-0000-000000000007'
      AND oe.delivery_state='dead_letter'
      AND q.prior_delivery_state='pending'
      AND q.prior_attempt_count=5
  ) THEN
    RAISE EXCEPTION 'legacy pending event at its delivery cap was left leaseable';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_attribute
    WHERE attrelid='public.outbox_event_envelope_quarantines'::regclass
      AND attname='payload' AND NOT attisdropped
  ) THEN
    RAISE EXCEPTION 'quarantine marker must remain content-free';
  END IF;
  ALTER TABLE public.outbox_events
    ADD CONSTRAINT outbox_events_safe_envelope CHECK (
      public.document_lifecycle_outbox_envelope_is_safe(event_kind, aggregate_type, aggregate_id, payload)
    ) NOT VALID,
    ADD CONSTRAINT outbox_events_idempotency_key_safe CHECK (
      idempotency_key ~ '^[A-Za-z0-9._:-]{1,200}$'
    ) NOT VALID,
    ADD CONSTRAINT outbox_events_attempt_count_bounded CHECK (
      attempt_count BETWEEN 0 AND 5
      AND (delivery_state <> 'pending' OR attempt_count < 5)
    ) NOT VALID;
END $legacy_upgrade_quarantine$;

SET LOCAL ROLE service_role;
DO $delivery_contract$
DECLARE claimed record; result record; orgs uuid[]; run_count bigint;
BEGIN
  SELECT * INTO result FROM public.reconcile_document_outbox_delivery(10);
  IF result.retried_count<>1 OR result.dead_letter_count<>1 THEN
    RAISE EXCEPTION 'expired delivery leases were not safely reconciled';
  END IF;

  SELECT array_agg(org_id ORDER BY org_id) INTO orgs
  FROM public.lease_document_outbox_events(2,120)
  WHERE event_id IN ('51200000-0000-0000-0000-000000000001','51200000-0000-0000-0000-000000000002','51200000-0000-0000-0000-000000000003');
  IF orgs IS DISTINCT FROM ARRAY['51100000-0000-0000-0000-000000000001'::uuid,'51100000-0000-0000-0000-000000000002'::uuid] THEN
    RAISE EXCEPTION 'organisation fair leasing did not reserve one slot per active organisation';
  END IF;

  SELECT * INTO claimed FROM public.lease_document_outbox_events(2,120)
  WHERE event_id='51200000-0000-0000-0000-000000000002';
  IF claimed.event_id IS NULL OR claimed.lease_token IS NULL THEN
    RAISE EXCEPTION 'borrowable capacity did not lease the remaining due work';
  END IF;
  SELECT * INTO result FROM public.ack_document_outbox_event(claimed.event_id,claimed.lease_token,'authority-run-1');
  IF result.code<>'ok' THEN RAISE EXCEPTION 'delivery acknowledgement failed'; END IF;
  SELECT * INTO result FROM public.ack_document_outbox_event(claimed.event_id,claimed.lease_token,'different-run');
  IF result.code<>'delivery_already_complete' THEN RAISE EXCEPTION 'different delivery acknowledgement was treated as idempotent ownership'; END IF;
  PERFORM set_config('test.outbox_authority_claimed_event',claimed.event_id::text,true);
END $delivery_contract$;
RESET ROLE;

DO $delivery_inspection$
DECLARE run_count bigint;
BEGIN
  IF (SELECT delivery_state FROM public.outbox_events WHERE id='51200000-0000-0000-0000-000000000004')<>'pending'
     OR (SELECT delivery_state FROM public.outbox_events WHERE id='51200000-0000-0000-0000-000000000005')<>'dead_letter'
     OR NOT EXISTS (SELECT 1 FROM public.outbox_dispatch_attempts WHERE event_id='51200000-0000-0000-0000-000000000004' AND outcome='lease_expired' AND safe_error_code='dispatch_failed') THEN
    RAISE EXCEPTION 'expired delivery leases were not safely reconciled';
  END IF;
  SELECT count(*) INTO run_count FROM public.document_processing_runs
  WHERE outbox_event_id=current_setting('test.outbox_authority_claimed_event')::uuid;
  IF run_count<>0 THEN RAISE EXCEPTION 'delivery acknowledgement incorrectly inferred processing completion'; END IF;
END $delivery_inspection$;

SET LOCAL ROLE service_role;
DO $helper_write_surface$
DECLARE blocked boolean:=false;
BEGIN
  BEGIN
    PERFORM public.document_upload_safe_event(
      '51100000-0000-0000-0000-000000000001',
      '51700000-0000-0000-0000-000000000099',
      'document.processing_requested.v2',
      'unsafe-helper-probe',
      jsonb_build_object('instruction','unsafe')
    );
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN blocked:=true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'service helper accepted an unsafe outbox envelope'; END IF;
END $helper_write_surface$;
RESET ROLE;

DO $safety_surface$
DECLARE blocked boolean:=false; index_count integer; view_sql text; valid_event_count integer; invalid_payload jsonb;
BEGIN
  BEGIN
    PERFORM public.reconcile_document_outbox_delivery(0);
  EXCEPTION WHEN raise_exception THEN
    blocked := SQLERRM='invalid delivery reconciliation batch size';
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'delivery reconciliation batch limit failed open'; END IF;
  IF public.outbox_delivery_retry_delay_seconds('51200000-0000-0000-0000-000000000004',99)>300 THEN
    RAISE EXCEPTION 'delivery retry delay exceeded its hard cap';
  END IF;
  -- Every currently emitted kind/version has one precise identifier-only
  -- shape. These inserts prove the DB contract accepts the real writers.
  INSERT INTO public.outbox_events(org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key) VALUES
    ('51100000-0000-0000-0000-000000000001','document_upload','51700000-0000-0000-0000-000000000001','document.upload_reserved.v1',jsonb_build_object('session_id','51700000-0000-0000-0000-000000000001','intake_id','51800000-0000-0000-0000-000000000001','asset_id','51900000-0000-0000-0000-000000000001'),'probe-reserved'),
    ('51100000-0000-0000-0000-000000000001','document_upload','51700000-0000-0000-0000-000000000002','document.upload_validation_requested.v1',jsonb_build_object('session_id','51700000-0000-0000-0000-000000000002','intake_id','51800000-0000-0000-0000-000000000002','asset_id','51900000-0000-0000-0000-000000000002'),'probe-validation-requested'),
    ('51100000-0000-0000-0000-000000000001','document_upload','51700000-0000-0000-0000-000000000003','document.upload_duplicate.v1',jsonb_build_object('session_id','51700000-0000-0000-0000-000000000003','intake_id','51800000-0000-0000-0000-000000000003'),'probe-duplicate'),
    ('51100000-0000-0000-0000-000000000001','document_upload','51700000-0000-0000-0000-000000000004','document.upload_failed.v1',jsonb_build_object('session_id','51700000-0000-0000-0000-000000000004','intake_id','51800000-0000-0000-0000-000000000004','error_code','upload_rejected'),'probe-upload-failed'),
    ('51100000-0000-0000-0000-000000000001','document_upload','51700000-0000-0000-0000-000000000005','document.upload_expired.v1',jsonb_build_object('session_id','51700000-0000-0000-0000-000000000005'),'probe-expired'),
    ('51100000-0000-0000-0000-000000000001','document','51800000-0000-0000-0000-000000000006','document.intake_validated.v1',jsonb_build_object('intake_id','51800000-0000-0000-0000-000000000006','asset_id','51900000-0000-0000-0000-000000000006','result_code','ok'),'probe-intake-valid'),
    ('51100000-0000-0000-0000-000000000001','document','51800000-0000-0000-0000-000000000007','document.intake_validation_failed.v1',jsonb_build_object('intake_id','51800000-0000-0000-0000-000000000007','asset_id','51900000-0000-0000-0000-000000000007','result_code','invalid_pdf'),'probe-intake-invalid'),
    ('51100000-0000-0000-0000-000000000001','document','51300000-0000-0000-0000-000000000008','document.metadata_created.v1',jsonb_build_object('document_id','51300000-0000-0000-0000-000000000008','matter_id','52000000-0000-0000-0000-000000000008'),'probe-metadata'),
    ('51100000-0000-0000-0000-000000000001','document','51300000-0000-0000-0000-000000000009','document.processing_requested.v1',jsonb_build_object('document_id','51300000-0000-0000-0000-000000000009','version_id','51400000-0000-0000-0000-000000000009','intake_id','51800000-0000-0000-0000-000000000009'),'probe-processing'),
    ('51100000-0000-0000-0000-000000000001','document','51800000-0000-0000-0000-000000000010','intake.assigned.v1',jsonb_build_object('intake_id','51800000-0000-0000-0000-000000000010','document_id','51300000-0000-0000-0000-000000000010','document_version_id','51400000-0000-0000-0000-000000000010'),'probe-assigned'),
    ('51100000-0000-0000-0000-000000000001','document','51800000-0000-0000-0000-000000000011','intake.discarded.v1',jsonb_build_object('intake_id','51800000-0000-0000-0000-000000000011','result_code','discarded'),'probe-discarded');
  SELECT count(*) INTO valid_event_count FROM public.outbox_events WHERE idempotency_key LIKE 'probe-%';
  IF valid_event_count<>11 THEN RAISE EXCEPTION 'valid existing event envelope was rejected'; END IF;
  FOR invalid_payload IN SELECT jsonb 'null' UNION ALL SELECT jsonb_build_object('document_id','51300000-0000-0000-0000-000000000012','version_id',jsonb_build_object('instruction','bad'),'intake_id','51800000-0000-0000-0000-000000000012') UNION ALL SELECT jsonb_build_object('document_id','51300000-0000-0000-0000-000000000013','version_id','51400000-0000-0000-0000-000000000013','intake_id','51800000-0000-0000-0000-000000000013','instruction','bad') LOOP
    blocked:=false;
    BEGIN
      INSERT INTO public.outbox_events(org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key)
      VALUES('51100000-0000-0000-0000-000000000001','document','51300000-0000-0000-0000-000000000012','document.processing_requested.v1',invalid_payload,'probe-invalid-'||gen_random_uuid()::text);
    EXCEPTION WHEN check_violation THEN blocked:=true;
    END;
    IF NOT blocked THEN RAISE EXCEPTION 'non-scalar or arbitrary outbox payload was accepted'; END IF;
  END LOOP;
  blocked:=false;
  BEGIN
    INSERT INTO public.outbox_events(org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key)
    VALUES('51100000-0000-0000-0000-000000000001','document','51300000-0000-0000-0000-000000000014','document.processing_requested.v2',jsonb_build_object('document_id','51300000-0000-0000-0000-000000000014','version_id','51400000-0000-0000-0000-000000000014','intake_id','51800000-0000-0000-0000-000000000014'),'probe-unknown-version');
  EXCEPTION WHEN check_violation THEN blocked:=true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'unknown outbox event version was accepted'; END IF;
  blocked:=false;
  BEGIN
    INSERT INTO public.outbox_events(org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key)
    VALUES('51100000-0000-0000-0000-000000000001','document','51300000-0000-0000-0000-000000000015','document.processing_requested.v1',jsonb_build_object('document_id','51300000-0000-0000-0000-000000000015','version_id','51400000-0000-0000-0000-000000000015','intake_id','51800000-0000-0000-0000-000000000015'),'unsafe key');
  EXCEPTION WHEN check_violation THEN blocked:=true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'unsafe outbox idempotency key was accepted'; END IF;
  blocked:=false;
  BEGIN
    INSERT INTO public.outbox_events(
      org_id, aggregate_type, aggregate_id, event_kind, payload,
      idempotency_key, attempt_count
    ) VALUES (
      '51100000-0000-0000-0000-000000000001',
      'document', '51300000-0000-0000-0000-000000000016',
      'document.processing_requested.v1',
      jsonb_build_object(
        'document_id', '51300000-0000-0000-0000-000000000016',
        'version_id', '51400000-0000-0000-0000-000000000016',
        'intake_id', '51800000-0000-0000-0000-000000000016'
      ),
      'probe-attempt-cap', 5
    );
  EXCEPTION WHEN check_violation THEN blocked:=true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'pending outbox event at its delivery cap was accepted'; END IF;
  blocked:=false;
  BEGIN
    UPDATE public.outbox_events SET last_error_code='not_safe_but_regex_valid'
    WHERE id='51200000-0000-0000-0000-000000000001';
  EXCEPTION WHEN check_violation THEN blocked:=true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'arbitrary last error code was accepted'; END IF;
  SELECT count(*) INTO index_count
  FROM pg_indexes
  WHERE schemaname='public' AND tablename='outbox_events'
    AND indexname IN ('outbox_events_due_pending_idx','outbox_events_due_pending_org_idx','outbox_events_expired_lease_idx');
  IF index_count<>3 THEN RAISE EXCEPTION 'outbox hot-path indexes missing'; END IF;
  SELECT pg_get_viewdef('public.document_outbox_delivery_diagnostics'::regclass) INTO view_sql;
  IF view_sql ~* '(payload|aggregate_id|org_id|token|path|object|content|filename|trigger_run)' THEN
    RAISE EXCEPTION 'delivery diagnostics expose operationally unsafe data';
  END IF;
  IF has_table_privilege('service_role','public.outbox_events','SELECT')
    OR has_table_privilege('service_role','public.outbox_dispatch_attempts','INSERT')
    OR has_function_privilege('service_role','public.document_upload_safe_event(uuid,uuid,text,text,jsonb)','EXECUTE')
    OR has_function_privilege('service_role','public.document_materialization_safe_event(uuid,uuid,text,text,jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','public.reconcile_document_outbox_delivery(integer)','EXECUTE')
    OR NOT has_function_privilege('service_role','public.reconcile_document_outbox_delivery(integer)','EXECUTE')
    OR NOT (SELECT relforcerowsecurity FROM pg_class WHERE oid='public.outbox_events'::regclass) THEN
    RAISE EXCEPTION 'delivery authority grant surface is too broad';
  END IF;
END $safety_surface$;

SET LOCAL ROLE service_role;
DO $diagnostics$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.document_outbox_delivery_diagnostics WHERE delivery_state IN ('delivered','dead_letter','pending')) THEN
    RAISE EXCEPTION 'content-free delivery diagnostics are unavailable';
  END IF;
END $diagnostics$;
RESET ROLE;
ROLLBACK;
