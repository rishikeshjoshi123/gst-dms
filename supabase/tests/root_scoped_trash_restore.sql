-- Run after a clean reset through migration 00088 against disposable local DB.
-- Rollback-only coverage for authority, root scope, independently trashed
-- descendants, parent blocking, uniqueness, idempotency, purge scheduling,
-- atomic intents, and direct privilege denial.
BEGIN;

DO $fixture$
DECLARE
  org uuid := '88000000-0000-0000-0000-000000000001';
  other_org uuid := '88000000-0000-0000-0000-000000000002';
  admin uuid := '88100000-0000-0000-0000-000000000001';
  associate uuid := '88100000-0000-0000-0000-000000000002';
  viewer uuid := '88100000-0000-0000-0000-000000000003';
  other_admin uuid := '88100000-0000-0000-0000-000000000004';
  client uuid := '88200000-0000-0000-0000-000000000001';
  matter uuid := '88300000-0000-0000-0000-000000000001';
  doc uuid := '88400000-0000-0000-0000-000000000001';
  independent_doc uuid := '88400000-0000-0000-0000-000000000002';
  blocked_doc uuid := '88400000-0000-0000-0000-000000000003';
  conflict_client uuid := '88200000-0000-0000-0000-000000000002';
  replacement_client uuid := '88200000-0000-0000-0000-000000000003';
  scheduled_client uuid := '88200000-0000-0000-0000-000000000004';
  other_client uuid := '88200000-0000-0000-0000-000000000005';
  membership uuid;
  hierarchy_operation uuid;
  independent_operation uuid;
  blocked_operation uuid;
  parent_operation uuid;
  conflict_operation uuid;
  scheduled_operation uuid;
  other_operation uuid;
  result record;
  effect_event record;
  effect_result record;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES
    ('00000000-0000-0000-0000-000000000000',admin,'authenticated','authenticated','restore-admin@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',associate,'authenticated','authenticated','restore-associate@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',viewer,'authenticated','authenticated','restore-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',other_admin,'authenticated','authenticated','restore-other@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES(org,'Restore fixture',admin),(other_org,'Other restore fixture',other_admin);
  SELECT id INTO membership FROM public.organisation_memberships WHERE org_id=org AND user_id=admin AND state='active';
  UPDATE public.organisations SET owner_membership_id=membership WHERE id=org;
  SELECT id INTO membership FROM public.organisation_memberships WHERE org_id=other_org AND user_id=other_admin AND state='active';
  UPDATE public.organisations SET owner_membership_id=membership WHERE id=other_org;
  INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_by)
  VALUES(org,associate,'associate','active',1,admin),(org,viewer,'viewer','active',1,admin);

  INSERT INTO public.clients(id,org_id,name,gstin,pan) VALUES
    (client,org,'Hierarchy','27AAAAA0000A1Z5','AAAAA0000A'),
    (conflict_client,org,'Conflict','27BBBBB0000B1Z5','BBBBB0000B'),
    (scheduled_client,org,'Scheduled','27CCCCC0000C1Z5','CCCCC0000C'),
    (other_client,other_org,'Other tenant','27DDDDD0000D1Z5','DDDDD0000D');
  INSERT INTO public.matters(id,org_id,client_id,title,financial_year,matter_code) VALUES
    (matter,org,client,'Hierarchy matter','2026-27','RST-2627-01');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by) VALUES
    (doc,org,matter,'restore/root.pdf',admin),
    (independent_doc,org,matter,'restore/independent.pdf',admin),
    (blocked_doc,org,matter,'restore/blocked.pdf',associate);
  INSERT INTO public.file_assets(
    id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,
    availability,validated_at,validated_page_count,created_by
  ) VALUES (
    '88500000-0000-0000-0000-000000000001',org,'documents',
    'orgs/88000000-0000-0000-0000-000000000001/assets/88500000-0000-0000-0000-000000000001/original.pdf',repeat('e',64),10,
    'application/pdf','available',now(),1,admin
  );
  INSERT INTO public.document_versions(
    id,org_id,document_id,asset_id,version_number,original_filename,
    validation_state,state,validated_at,promoted_at
  ) VALUES (
    '88600000-0000-0000-0000-000000000001',org,doc,
    '88500000-0000-0000-0000-000000000001',1,'root.pdf',
    'valid','current',now(),now()
  );
  UPDATE public.documents SET current_version_id='88600000-0000-0000-0000-000000000001'
  WHERE id=doc;
  INSERT INTO public.deadlines(id,matter_id,document_id,type,due_date,description) VALUES
    ('88700000-0000-0000-0000-000000000001',matter,doc,'other',current_date-1,'Elapsed while in Trash'),
    ('88700000-0000-0000-0000-000000000002',matter,doc,'other',current_date+45,'Future window'),
    ('88700000-0000-0000-0000-000000000003',matter,independent_doc,'other',current_date-1,'Independent Trash group'),
    ('88700000-0000-0000-0000-000000000004',matter,doc,'other',current_date,'Due today'),
    ('88700000-0000-0000-0000-000000000005',matter,doc,'other',current_date+20,'Future 30-day window');

  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',admin::text,true);

  PERFORM set_config('request.jwt.claim.sub',other_admin::text,true);
  SELECT operation_id INTO other_operation FROM public.trash_resource('client',other_client,'fixture.other-tenant');
  PERFORM set_config('request.jwt.claim.sub',admin::text,true);
  SELECT * INTO result FROM public.restore_trash_operation(other_operation,'restore.fixture.cross-tenant');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'cross-tenant operation restore was disclosed or accepted'; END IF;

  -- A pre-existing direct document is excluded from the later client group and
  -- remains in its original operation after the client group is restored.
  SELECT operation_id INTO independent_operation FROM public.trash_resource('document',independent_doc,'fixture.independent');
  SELECT operation_id INTO hierarchy_operation FROM public.trash_resource('client',client,'fixture.hierarchy');
  SELECT * INTO result FROM public.restore_trash_operation(hierarchy_operation,'restore.fixture.hierarchy');
  IF result.code<>'restored' THEN RAISE EXCEPTION 'hierarchy restore failed: %',result.code; END IF;
  IF (SELECT record_state FROM public.clients WHERE id=client)<>'active'
     OR (SELECT record_state FROM public.matters WHERE id=matter)<>'active'
     OR (SELECT record_state::text FROM public.documents WHERE id=doc)<>'active'
     OR (SELECT record_state::text FROM public.documents WHERE id=independent_doc)<>'trashed' THEN
    RAISE EXCEPTION 'restore changed the wrong operation members';
  END IF;
  IF (SELECT count(*) FROM public.outbox_events WHERE aggregate_id=hierarchy_operation AND event_kind LIKE 'trash.%restore%')<>1
     OR (SELECT count(*) FROM public.outbox_events WHERE aggregate_id=hierarchy_operation AND event_kind IN ('trash.search_reindex_requested.v1','trash.schedule_reevaluation_requested.v1'))<>2
     OR (SELECT count(*) FROM public.activity_logs WHERE entity_id=client AND action='resource_restored')<>1 THEN
    RAISE EXCEPTION 'restore did not atomically record activity and three durable intents';
  END IF;

  -- Each Restore event is completed under its delivery lease. Search queues
  -- the existing scoped index worker for the restored current version;
  -- scheduling observes elapsed reminder windows without touching a deadline
  -- belonging to an independently trashed descendant or a future window.
  PERFORM public.lease_document_outbox_events(100,120);
  SELECT * INTO effect_event FROM public.outbox_events
  WHERE aggregate_id=hierarchy_operation
    AND event_kind='trash.search_reindex_requested.v1';
  SELECT * INTO effect_result FROM public.ack_document_outbox_event(
    effect_event.id,effect_event.lease_token,'fixture-premature-ack'
  );
  IF effect_result.code<>'effect_not_handled'
     OR (SELECT delivery_state FROM public.outbox_events WHERE id=effect_event.id)<>'leased' THEN
    RAISE EXCEPTION 'Restore effect was acknowledged before it was handled';
  END IF;
  FOR effect_event IN
    SELECT id,event_kind,lease_token FROM public.outbox_events
    WHERE aggregate_id=hierarchy_operation
      AND event_kind IN (
        'trash.operation_restored.v1',
        'trash.search_reindex_requested.v1',
        'trash.schedule_reevaluation_requested.v1'
      )
    ORDER BY event_kind
  LOOP
    SELECT * INTO effect_result FROM public.handle_trash_restore_effect(
      effect_event.id,org,effect_event.lease_token,effect_event.event_kind
    );
    IF effect_result.code<>'handled' THEN
      RAISE EXCEPTION 'restore effect was not handled: % %',effect_event.event_kind,effect_result.code;
    END IF;
    SELECT * INTO effect_result FROM public.handle_trash_restore_effect(
      effect_event.id,org,effect_event.lease_token,effect_event.event_kind
    );
    IF effect_result.code<>'already_handled' THEN
      RAISE EXCEPTION 'restore effect replay was not idempotent: %',effect_event.event_kind;
    END IF;
    SELECT * INTO effect_result FROM public.ack_document_outbox_event(
      effect_event.id,effect_event.lease_token,'fixture-restore-effect'
    );
    IF effect_result.code<>'ok' THEN
      RAISE EXCEPTION 'handled Restore effect was not acknowledged: % %',effect_event.event_kind,effect_result.code;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.trash_restore_effect_receipts WHERE operation_id=hierarchy_operation)<>3
     OR (SELECT count(*) FROM public.outbox_events WHERE aggregate_id=hierarchy_operation
       AND event_kind IN (
         'trash.operation_restored.v1','trash.search_reindex_requested.v1',
         'trash.schedule_reevaluation_requested.v1'
       ) AND delivery_state='delivered')<>3
     OR NOT EXISTS (
       SELECT 1 FROM public.document_processing_runs run
       WHERE run.org_id=org AND run.document_id=doc AND run.scope='search_index'
         AND run.idempotency_key='trash.restore.search.run.'||hierarchy_operation::text||'.'||doc::text
     )
     OR NOT (SELECT reminder_sent_30d AND reminder_sent_7d FROM public.deadlines
       WHERE id='88700000-0000-0000-0000-000000000001')
     OR NOT (SELECT reminder_sent_30d AND reminder_sent_7d FROM public.deadlines
       WHERE id='88700000-0000-0000-0000-000000000004')
     OR (SELECT reminder_sent_30d OR reminder_sent_7d FROM public.deadlines
       WHERE id='88700000-0000-0000-0000-000000000002')
     OR (SELECT reminder_sent_30d OR reminder_sent_7d FROM public.deadlines
       WHERE id='88700000-0000-0000-0000-000000000005')
     OR (SELECT reminder_sent_30d OR reminder_sent_7d FROM public.deadlines
       WHERE id='88700000-0000-0000-0000-000000000003') THEN
    RAISE EXCEPTION 'restore dependent-domain reactivation was incomplete or unsafe';
  END IF;
  SELECT * INTO result FROM public.restore_trash_operation(hierarchy_operation,'restore.fixture.hierarchy');
  IF result.code<>'restored' OR (SELECT count(*) FROM public.trash_restore_receipts WHERE operation_id=hierarchy_operation)<>1 THEN
    RAISE EXCEPTION 'restore replay did not return the original result';
  END IF;

  -- Associate may restore only their own direct document. Viewer is denied and
  -- an Associate cannot restore a document trashed by an Admin.
  PERFORM set_config('request.jwt.claim.sub',associate::text,true);
  SELECT operation_id INTO blocked_operation FROM public.trash_resource('document',blocked_doc,'fixture.associate.document');
  SELECT * INTO result FROM public.restore_trash_operation(blocked_operation,'restore.fixture.associate');
  IF result.code<>'restored' THEN RAISE EXCEPTION 'associate own-document restore failed'; END IF;
  SELECT * INTO result FROM public.restore_trash_operation(blocked_operation,'restore.fixture.associate');
  IF result.code<>'restored' THEN RAISE EXCEPTION 'associate own-document replay failed'; END IF;
  SELECT * INTO result FROM public.restore_trash_operation(independent_operation,'restore.fixture.other-actor');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'associate restored another actor document'; END IF;
  PERFORM set_config('request.jwt.claim.sub',viewer::text,true);
  SELECT * INTO result FROM public.restore_trash_operation(independent_operation,'restore.fixture.viewer');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'viewer received restore authority'; END IF;

  -- A separately trashed parent blocks a child-root restore and exposes only
  -- the parent operation identifier needed for safe navigation.
  PERFORM set_config('request.jwt.claim.sub',admin::text,true);
  SELECT operation_id INTO blocked_operation FROM public.trash_resource('document',blocked_doc,'fixture.blocked.child');
  SELECT operation_id INTO parent_operation FROM public.trash_resource('matter',matter,'fixture.blocked.parent');
  SELECT * INTO result FROM public.restore_trash_operation(blocked_operation,'restore.fixture.parent-block');
  IF result.code<>'restore_blocked' OR result.blocker_code<>'parent_in_trash'
     OR result.blocking_operation_id IS DISTINCT FROM parent_operation
     OR (SELECT record_state::text FROM public.documents WHERE id=blocked_doc)<>'trashed' THEN
    RAISE EXCEPTION 'separately trashed parent did not atomically block child restore';
  END IF;

  -- Active uniqueness conflicts leave the entire group in Trash and persist a
  -- safe blocker; no identifier is silently cleared or renamed.
  SELECT operation_id INTO conflict_operation FROM public.trash_resource('client',conflict_client,'fixture.conflict');
  INSERT INTO public.clients(id,org_id,name,gstin,pan)
  VALUES(replacement_client,org,'Replacement','27BBBBB0000B1Z5','BBBBB0000B');
  SELECT * INTO result FROM public.restore_trash_operation(conflict_operation,'restore.fixture.conflict');
  IF result.code<>'restore_blocked' OR result.blocker_code<>'client_identifier_conflict'
     OR (SELECT state FROM public.trash_operations WHERE id=conflict_operation)<>'restore_blocked'
     OR (SELECT gstin FROM public.clients WHERE id=conflict_client)<>'27BBBBB0000B1Z5' THEN
    RAISE EXCEPTION 'client uniqueness conflict was not safely blocked';
  END IF;
  SELECT * INTO result FROM public.restore_trash_operation(independent_operation,'restore.fixture.conflict');
  IF result.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'cross-subject restore key reuse was accepted'; END IF;

  -- A scheduled purge is never silently cancelled by Restore.
  SELECT operation_id INTO scheduled_operation FROM public.trash_resource('client',scheduled_client,'fixture.scheduled');
  UPDATE public.trash_operations SET state='purge_scheduled',purge_scheduled_at=now() WHERE id=scheduled_operation;
  SELECT * INTO result FROM public.restore_trash_operation(scheduled_operation,'restore.fixture.scheduled');
  IF result.code<>'purge_scheduled' OR (SELECT state FROM public.trash_operations WHERE id=scheduled_operation)<>'purge_scheduled' THEN
    RAISE EXCEPTION 'purge-scheduled operation was restored or altered';
  END IF;
END $fixture$;

-- Browser and service roles have RPC-only authority and no direct receipt/table
-- mutation privileges. Helper execution remains private.
SET LOCAL ROLE authenticated;
DO $authenticated_denial$
BEGIN
  IF has_table_privilege('authenticated','public.trash_restore_receipts','INSERT')
     OR has_table_privilege('authenticated','public.trash_restore_effect_receipts','SELECT')
     OR has_function_privilege('authenticated','public.trash_restore_blocker(uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated direct restore internals were exposed';
  END IF;
  IF NOT has_function_privilege('authenticated','public.restore_trash_operation(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated restore command grant missing';
  END IF;
END $authenticated_denial$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $service_denial$
BEGIN
  IF has_table_privilege('service_role','public.trash_restore_receipts','SELECT')
     OR has_function_privilege('service_role','public.restore_trash_operation(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'service role bypasses restore authority';
  END IF;
  IF has_table_privilege('service_role','public.trash_restore_effect_receipts','SELECT')
     OR NOT has_function_privilege('service_role','public.handle_trash_restore_effect(uuid,uuid,uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'service Restore effect boundary is incorrect';
  END IF;
END $service_denial$;
RESET ROLE;

ROLLBACK;
