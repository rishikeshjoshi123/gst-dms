-- Adapter-retirement gate acceptance. Rollback-only: it proves the migration
-- rejects a remaining legacy source before any compatibility contract changes.
BEGIN;

DO $zero_state_passes$
BEGIN
  PERFORM public.assert_staged_document_adapter_retirement_ready();
END $zero_state_passes$;

-- The completed-cutover fixture is only to exercise the migration gate. The
-- retired historical reports must remain readable without restoring any
-- backfill fence or action capability.
DO $pending_outbox_rejects$
DECLARE
  fixture_org_id uuid := '62300000-0000-0000-0000-000000000001';
  user_id uuid := '62400000-0000-0000-0000-000000000001';
  client_id uuid := '62500000-0000-0000-0000-000000000001';
  matter_id uuid := '62600000-0000-0000-0000-000000000001';
  source_id uuid := '62700000-0000-0000-0000-000000000001';
  asset_id uuid := '62800000-0000-0000-0000-000000000001';
  intake_id uuid := '62900000-0000-0000-0000-000000000001';
  document_id uuid := '62a00000-0000-0000-0000-000000000001';
  version_id uuid := '62b00000-0000-0000-0000-000000000001';
  rejected boolean := false;
BEGIN
  INSERT INTO auth.users(
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000000', user_id, 'authenticated',
    'authenticated', 'adapter-outbox@example.test', 'x', now(), '{}'::jsonb,
    '{}'::jsonb, now(), now()
  );
  INSERT INTO public.organisations(id, name, created_by)
    VALUES (fixture_org_id, 'Adapter outbox gate', user_id);
  INSERT INTO public.clients(id, org_id, name) VALUES (client_id, fixture_org_id, 'Outbox client');
  INSERT INTO public.matters(id, org_id, client_id, title)
    VALUES (matter_id, fixture_org_id, client_id, 'Outbox matter');
  INSERT INTO public.staged_documents(id, org_id, uploaded_by, storage_path, status, intake_matter_id)
    VALUES (source_id, fixture_org_id, user_id,
      'staging/' || fixture_org_id::text || '/62c00000-0000-0000-0000-000000000001/original.pdf', 'ready_to_assign', matter_id);
  INSERT INTO public.file_assets(
    id, org_id, bucket_id, object_key, sha256, byte_size, detected_mime_type,
    availability, validated_at, validated_page_count, created_by
  ) VALUES (
    asset_id, fixture_org_id, 'documents', 'orgs/' || fixture_org_id::text || '/assets/' || asset_id::text || '/original.pdf',
    repeat('a', 64), 17, 'application/pdf', 'available', now(), 1, user_id
  );
  INSERT INTO public.intake_items(id, org_id, asset_id, intended_matter_id, state, uploaded_by)
    VALUES (intake_id, fixture_org_id, asset_id, matter_id, 'ready', user_id);
  INSERT INTO public.documents(id, org_id, matter_id, display_title, status, storage_path, created_by)
    VALUES (document_id, fixture_org_id, matter_id, 'Outbox evidence', 'placed', NULL, user_id);
  INSERT INTO public.document_versions(
    id, org_id, document_id, asset_id, version_number, original_filename,
    page_count, validation_state, state, created_by, validated_at, promoted_at
  ) VALUES (
    version_id, fixture_org_id, document_id, asset_id, 1, 'original.pdf', 1,
    'valid', 'current', user_id, now(), now()
  );
  UPDATE public.documents AS document_row SET current_version_id = version_id
    WHERE document_row.id = document_id AND document_row.org_id = fixture_org_id;
  INSERT INTO public.staged_document_backfill_items(
    org_id, legacy_staged_document_id, safe_item_key, outcome, canonical_asset_id,
    canonical_intake_item_id, observed_sha256, observed_byte_size, safe_reason_code,
    terminal_classified_at, transfer_completed_at
  ) VALUES (
    fixture_org_id, source_id, 'legacy-staged/' || source_id::text, 'transfer_pending', asset_id,
    intake_id, repeat('a', 64), 17, 'canonical_transfer_completed', now(), now()
  );
  INSERT INTO public.staged_document_retirement_audit_items(
    org_id, legacy_staged_document_id, outcome, audited_at
  ) VALUES (fixture_org_id, source_id, 'verified_equal', now());
  INSERT INTO public.staged_document_source_purge_tombstones(
    org_id, legacy_staged_document_id, state, storage_deleted_at, verification_code
  ) VALUES (fixture_org_id, source_id, 'deleted', now(), 'fresh_equal_pdf');

  PERFORM public.assert_staged_document_adapter_retirement_ready();

  INSERT INTO public.outbox_events(
    org_id, aggregate_type, aggregate_id, event_kind, payload, idempotency_key
  ) VALUES (
    fixture_org_id, 'document', document_id, 'document.processing_requested.v1',
    jsonb_build_object(
      'document_id', document_id::text,
      'version_id', version_id::text,
      'intake_id', intake_id::text
    ),
    'adapter-retirement-pending-outbox'
  );
  BEGIN
    PERFORM public.assert_staged_document_adapter_retirement_ready();
  EXCEPTION WHEN check_violation THEN
    rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'adapter retirement accepted a pending mapped canonical outbox event';
  END IF;

  UPDATE public.outbox_events
  SET delivery_state = 'delivered', delivered_at = now(), lease_token = NULL, lease_expires_at = NULL
  WHERE org_id = fixture_org_id AND idempotency_key = 'adapter-retirement-pending-outbox';
  PERFORM public.assert_staged_document_adapter_retirement_ready();

  rejected := false;
  INSERT INTO public.outbox_events(
    org_id, aggregate_type, aggregate_id, event_kind, payload, idempotency_key
  ) VALUES (
    fixture_org_id, 'document', intake_id, 'intake.assigned.v1',
    jsonb_build_object(
      'intake_id', intake_id::text,
      'document_id', document_id::text,
      'document_version_id', version_id::text
    ),
    'adapter-retirement-pending-intake-assigned'
  );
  BEGIN
    PERFORM public.assert_staged_document_adapter_retirement_ready();
  EXCEPTION WHEN check_violation THEN
    rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'adapter retirement accepted a pending mapped intake assignment event';
  END IF;

  UPDATE public.outbox_events
  SET delivery_state = 'delivered', delivered_at = now(), lease_token = NULL, lease_expires_at = NULL
  WHERE org_id = fixture_org_id AND idempotency_key = 'adapter-retirement-pending-intake-assigned';
  PERFORM public.assert_staged_document_adapter_retirement_ready();

  rejected := false;
  INSERT INTO public.outbox_events(
    org_id, aggregate_type, aggregate_id, event_kind, payload, idempotency_key,
    delivery_state, lease_token, lease_expires_at
  ) VALUES (
    fixture_org_id, 'document', intake_id, 'intake.assigned.v1',
    jsonb_build_object(
      'intake_id', intake_id::text,
      'document_id', document_id::text,
      'document_version_id', version_id::text
    ),
    'adapter-retirement-leased-intake-assigned', 'leased', gen_random_uuid(), now() + interval '5 minutes'
  );
  BEGIN
    PERFORM public.assert_staged_document_adapter_retirement_ready();
  EXCEPTION WHEN check_violation THEN
    rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'adapter retirement accepted a leased mapped intake assignment event';
  END IF;

  UPDATE public.outbox_events
  SET delivery_state = 'delivered', delivered_at = now(), lease_token = NULL, lease_expires_at = NULL
  WHERE org_id = fixture_org_id AND idempotency_key = 'adapter-retirement-leased-intake-assigned';
  PERFORM public.assert_staged_document_adapter_retirement_ready();

  rejected := false;
  INSERT INTO public.outbox_events(
    org_id, aggregate_type, aggregate_id, event_kind, payload, idempotency_key,
    delivery_state, lease_token, lease_expires_at
  ) VALUES (
    fixture_org_id, 'document', intake_id, 'intake.discarded.v1',
    jsonb_build_object('intake_id', intake_id::text, 'result_code', 'discarded'),
    'adapter-retirement-leased-intake-discarded', 'leased', gen_random_uuid(), now() + interval '5 minutes'
  );
  BEGIN
    PERFORM public.assert_staged_document_adapter_retirement_ready();
  EXCEPTION WHEN check_violation THEN
    rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'adapter retirement accepted a leased mapped intake discard event';
  END IF;

  UPDATE public.outbox_events
  SET delivery_state = 'delivered', delivered_at = now(), lease_token = NULL, lease_expires_at = NULL
  WHERE org_id = fixture_org_id AND idempotency_key = 'adapter-retirement-leased-intake-discarded';
  PERFORM public.assert_staged_document_adapter_retirement_ready();

  rejected := false;
  INSERT INTO public.outbox_events(
    org_id, aggregate_type, aggregate_id, event_kind, payload, idempotency_key
  ) VALUES (
    fixture_org_id, 'document', intake_id, 'intake.discarded.v1',
    jsonb_build_object('intake_id', intake_id::text, 'result_code', 'discarded'),
    'adapter-retirement-pending-intake-discarded'
  );
  BEGIN
    PERFORM public.assert_staged_document_adapter_retirement_ready();
  EXCEPTION WHEN check_violation THEN
    rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'adapter retirement accepted a pending mapped intake discard event';
  END IF;
END $pending_outbox_rejects$;

SET LOCAL ROLE service_role;
DO $historical_report_remains_readable$
DECLARE report_count bigint;
BEGIN
  SELECT count(*) INTO report_count FROM public.staged_document_backfill_reports;
  IF report_count <> 1 THEN
    RAISE EXCEPTION 'service role could not read the retained staged retirement report';
  END IF;
END $historical_report_remains_readable$;
RESET ROLE;

DO $released_surface_is_fenced$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname IN ('staging_upload', 'staging_read', 'staging_delete')
  ) THEN
    RAISE EXCEPTION 'legacy staging storage policy remained after adapter retirement';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
      AND tablename = 'staged_documents'
  ) THEN
    RAISE EXCEPTION 'legacy staged documents remained in realtime publication';
  END IF;
  IF has_function_privilege('service_role', 'public.get_staged_document_backfill_source_grant(uuid,uuid,uuid)'::regprocedure, 'EXECUTE')
    OR has_function_privilege('service_role', 'public.get_staged_document_backfill_adapter_fences(uuid)'::regprocedure, 'EXECUTE')
    OR has_function_privilege('service_role', 'public.get_staged_document_backfill_transfer_grant(uuid,uuid,uuid)'::regprocedure, 'EXECUTE')
    OR has_function_privilege('service_role', 'public.get_staged_document_retirement_audit_grant(uuid,uuid,uuid)'::regprocedure, 'EXECUTE')
    OR has_function_privilege('service_role', 'public.claim_staged_document_source_purge_batch(uuid,integer)'::regprocedure, 'EXECUTE')
    OR has_function_privilege('service_role', 'public.get_staged_document_source_purge_grant(uuid,uuid,uuid)'::regprocedure, 'EXECUTE')
    OR has_function_privilege('service_role', 'public.record_staged_document_source_purge_intent(uuid,uuid,uuid,bigint,text,integer,bigint,text,integer)'::regprocedure, 'EXECUTE')
    OR has_function_privilege('service_role', 'public.confirm_staged_document_source_purge(uuid,uuid,uuid,text)'::regprocedure, 'EXECUTE')
    OR has_function_privilege('service_role', 'public.record_staged_document_source_purge_recovery(uuid,uuid,uuid,text)'::regprocedure, 'EXECUTE')
    OR has_function_privilege('service_role', 'public.create_staged_document_source_purge_blocker(uuid,public.staged_document_source_purge_blocker_scope,uuid,uuid,public.staged_document_source_purge_blocker_kind)'::regprocedure, 'EXECUTE') THEN
    RAISE EXCEPTION 'retired staged worker capability still executable by service role';
  END IF;
END $released_surface_is_fenced$;

DO $unresolved_source_rejects$
DECLARE
  org_id uuid := '62000000-0000-0000-0000-000000000001';
  user_id uuid := '62100000-0000-0000-0000-000000000001';
  rejected boolean := false;
BEGIN
  INSERT INTO auth.users(
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000000', user_id, 'authenticated',
    'authenticated', 'adapter-gate@example.test', 'x', now(), '{}'::jsonb,
    '{}'::jsonb, now(), now()
  );
  INSERT INTO public.organisations(id, name, created_by)
    VALUES (org_id, 'Adapter gate', user_id);
  INSERT INTO public.staged_documents(id, org_id, uploaded_by, storage_path, status)
    VALUES ('62200000-0000-0000-0000-000000000001', org_id, user_id,
      'staging/' || org_id::text || '/legacy.pdf', 'pending_assignment');

  BEGIN
    PERFORM public.assert_staged_document_adapter_retirement_ready();
  EXCEPTION WHEN check_violation THEN
    rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'adapter retirement accepted unresolved legacy source';
  END IF;
END $unresolved_source_rejects$;

ROLLBACK;
