-- Run after a clean reset through migration 00089. This fixture exercises the
-- creation event's tenant/payload/lease/lifecycle fence and its narrow derived
-- search-state invalidation without carrying any legal content in receipts.
BEGIN;

DO $fixture$
DECLARE
  org uuid := '89000000-0000-0000-0000-000000000001';
  other_org uuid := '89000000-0000-0000-0000-000000000002';
  admin uuid := '89100000-0000-0000-0000-000000000001';
  other_admin uuid := '89100000-0000-0000-0000-000000000002';
  client uuid := '89200000-0000-0000-0000-000000000001';
  matter uuid := '89300000-0000-0000-0000-000000000001';
  document_id uuid := '89400000-0000-0000-0000-000000000001';
  independent_document uuid := '89400000-0000-0000-0000-000000000002';
  blocked_document uuid := '89400000-0000-0000-0000-000000000003';
  scheduled_document uuid := '89400000-0000-0000-0000-000000000004';
  root_operation_id uuid;
  independent_operation uuid;
  old_operation_id uuid;
  event_row record;
  result record;
  membership uuid;
  denied boolean := false;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES
    ('00000000-0000-0000-0000-000000000000',admin,'authenticated','authenticated','created-effect-admin@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',other_admin,'authenticated','authenticated','created-effect-other@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES(org,'Creation effect fixture',admin),(other_org,'Other fixture',other_admin);
  SELECT id INTO membership FROM public.organisation_memberships WHERE org_id=org AND user_id=admin;
  UPDATE public.organisations SET owner_membership_id=membership WHERE id=org;
  SELECT id INTO membership FROM public.organisation_memberships WHERE org_id=other_org AND user_id=other_admin;
  UPDATE public.organisations SET owner_membership_id=membership WHERE id=other_org;
  INSERT INTO public.clients(id,org_id,name,gstin,pan) VALUES(client,org,'Created effect','27EEEEE0000E1Z5','EEEEE0000E');
  INSERT INTO public.matters(id,org_id,client_id,title,financial_year,matter_code) VALUES(matter,org,client,'Creation effect matter','2026-27','CRT-2627-01');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by,embedding,embedding_model,embedding_version)
  VALUES
    (document_id,org,matter,'fixture/owned.pdf',admin,array_fill(0.1::real, ARRAY[768])::vector,'fixture-model','fixture-v1'),
    (independent_document,org,matter,'fixture/independent.pdf',admin,array_fill(0.2::real, ARRAY[768])::vector,'fixture-model','fixture-v1'),
    (blocked_document,org,matter,'fixture/blocked.pdf',admin,array_fill(0.4::real, ARRAY[768])::vector,'fixture-model','fixture-v1'),
    (scheduled_document,org,matter,'fixture/scheduled.pdf',admin,array_fill(0.5::real, ARRAY[768])::vector,'fixture-model','fixture-v1');

  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',admin::text,true);
  SELECT command_result.operation_id INTO independent_operation
  FROM public.trash_resource('document',independent_document,'created.fixture.independent') command_result;
  SELECT command_result.operation_id INTO root_operation_id
  FROM public.trash_resource('client',client,'created.fixture.root') command_result;
  -- The independently trashed child remains excluded from the root operation.
  IF EXISTS (SELECT 1 FROM public.resource_trash_memberships membership
    WHERE membership.operation_id=root_operation_id AND membership.resource_id=independent_document) THEN
    RAISE EXCEPTION 'creation effect fixture adopted independent child';
  END IF;
  SELECT * INTO event_row FROM public.outbox_events
  WHERE org_id=org AND aggregate_id=root_operation_id AND event_kind='trash.operation_created.v1';
  PERFORM public.lease_document_outbox_events(100,120);
  SELECT * INTO event_row FROM public.outbox_events WHERE id=event_row.id;

  -- A forged tenant/event-kind cannot consume or write a receipt. The durable
  -- outbox's immutable exact-payload constraint rejects malformed envelopes at
  -- insertion; the handler repeats that check before its effect.
  SELECT * INTO result FROM public.handle_trash_operation_created_effect(event_row.id,other_org,event_row.lease_token,'trash.operation_created.v1');
  IF result.code<>'invalid_event' THEN RAISE EXCEPTION 'cross-tenant created effect was accepted'; END IF;
  SELECT * INTO result FROM public.handle_trash_operation_created_effect(event_row.id,org,event_row.lease_token,'trash.operation_restored.v1');
  IF result.code<>'invalid_request' THEN RAISE EXCEPTION 'wrong expected event kind was accepted'; END IF;
  SELECT * INTO result FROM public.ack_document_outbox_event(event_row.id,event_row.lease_token,'created-effect-before-receipt');
  IF result.code<>'effect_not_handled' THEN RAISE EXCEPTION 'created event acknowledged before its receipt'; END IF;
  SELECT * INTO result FROM public.handle_trash_operation_created_effect(event_row.id,org,gen_random_uuid(),'trash.operation_created.v1');
  IF result.code<>'invalid_event'
     OR EXISTS (SELECT 1 FROM public.trash_operation_created_effect_receipts receipt WHERE receipt.event_id=event_row.id) THEN
    RAISE EXCEPTION 'stale creation lease wrote or claimed a receipt';
  END IF;

  SELECT * INTO result FROM public.handle_trash_operation_created_effect(event_row.id,org,event_row.lease_token,'trash.operation_created.v1');
  IF result.code<>'handled' OR result.outcome_code<>'operation_semantic_index_invalidated' OR result.affected_count<>3 THEN
    RAISE EXCEPTION 'creation effect did not invalidate exactly its owned document: %, %, %',result.code,result.outcome_code,result.affected_count;
  END IF;
  IF (SELECT embedding IS NULL AND embedding_model IS NULL AND embedding_version IS NULL AND embedding_document_version_id IS NULL FROM public.documents WHERE id=document_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'owned document semantic fields were not cleared';
  END IF;
  IF (SELECT embedding IS NOT NULL FROM public.documents WHERE id=independent_document) IS NOT TRUE THEN
    RAISE EXCEPTION 'independent operation document was changed';
  END IF;
  IF (SELECT count(*) FROM public.documents WHERE id IN (blocked_document,scheduled_document) AND embedding IS NULL)<>2 THEN
    RAISE EXCEPTION 'root operation did not invalidate every operation-owned document';
  END IF;
  SELECT * INTO result FROM public.handle_trash_operation_created_effect(event_row.id,org,event_row.lease_token,'trash.operation_created.v1');
  IF result.code<>'already_handled' OR result.affected_count<>3
     OR (SELECT count(*) FROM public.trash_operation_created_effect_receipts WHERE event_id=event_row.id)<>1 THEN
    RAISE EXCEPTION 'creation replay was not one stable receipt';
  END IF;
  SELECT * INTO result FROM public.ack_document_outbox_event(event_row.id,event_row.lease_token,'created-effect-run');
  IF result.code<>'ok' THEN RAISE EXCEPTION 'receipt did not unlock acknowledgement'; END IF;

  SELECT * INTO result FROM public.restore_trash_operation(root_operation_id,'created.fixture.root-restore');
  IF result.code<>'restored'
     OR (SELECT record_state::text='active' AND embedding IS NULL FROM public.documents WHERE id=document_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'handler-before-Restore race did not preserve the safe invalidated state';
  END IF;
  UPDATE public.documents SET embedding=array_fill(0.4::real, ARRAY[768])::vector,embedding_model='fixture-model',embedding_version='fixture-v1'
  WHERE id=blocked_document;
  UPDATE public.documents SET embedding=array_fill(0.5::real, ARRAY[768])::vector,embedding_model='fixture-model',embedding_version='fixture-v1'
  WHERE id=scheduled_document;

  -- A restored operation is acknowledged with a receipt but never clears a
  -- rebuilt active embedding if its creation event is delivered late.
  SELECT command_result.operation_id INTO old_operation_id
  FROM public.trash_resource('document',document_id,'created.fixture.restored') command_result;
  SELECT * INTO result FROM public.restore_trash_operation(old_operation_id,'created.fixture.restore');
  IF result.code<>'restored' THEN RAISE EXCEPTION 'fixture Restore failed'; END IF;
  UPDATE public.documents SET embedding=array_fill(0.3::real, ARRAY[768])::vector,embedding_model='new-operation',embedding_version='new-operation-v1'
  WHERE id=document_id;
  SELECT command_result.operation_id INTO root_operation_id
  FROM public.trash_resource('document',document_id,'created.fixture.new-operation') command_result;
  SELECT * INTO event_row FROM public.outbox_events WHERE aggregate_id=old_operation_id AND event_kind='trash.operation_created.v1';
  PERFORM public.lease_document_outbox_events(100,120);
  SELECT * INTO event_row FROM public.outbox_events WHERE id=event_row.id;
  SELECT * INTO result FROM public.handle_trash_operation_created_effect(event_row.id,org,event_row.lease_token,'trash.operation_created.v1');
  IF result.code<>'handled' OR result.outcome_code<>'operation_no_longer_trashed' OR result.affected_count<>0
     OR (SELECT embedding_model='new-operation' FROM public.documents WHERE id=document_id) IS NOT TRUE THEN
    RAISE EXCEPTION 'old late creation event cleared a newer operation embedding';
  END IF;

  -- These states retain active memberships and trashed resources. A delayed
  -- creation event must still invalidate only the operation's own document.
  SELECT command_result.operation_id INTO root_operation_id
  FROM public.trash_resource('document',blocked_document,'created.fixture.restore-blocked') command_result;
  UPDATE public.trash_operations SET state='restore_blocked',restore_blocked_at=now(),last_error_code='fixture_blocked'
  WHERE id=root_operation_id;
  SELECT * INTO event_row FROM public.outbox_events WHERE aggregate_id=root_operation_id AND event_kind='trash.operation_created.v1';
  PERFORM public.lease_document_outbox_events(100,120);
  SELECT * INTO event_row FROM public.outbox_events WHERE id=event_row.id;
  SELECT * INTO result FROM public.handle_trash_operation_created_effect(event_row.id,org,event_row.lease_token,'trash.operation_created.v1');
  IF result.code<>'handled' OR result.outcome_code<>'operation_semantic_index_invalidated' OR result.affected_count<>1
     OR (SELECT embedding IS NULL FROM public.documents WHERE id=blocked_document) IS NOT TRUE THEN
    RAISE EXCEPTION 'late restore_blocked creation event was not invalidated';
  END IF;
  SELECT * INTO result FROM public.ack_document_outbox_event(event_row.id,event_row.lease_token,'created-effect-blocked');
  IF result.code<>'ok' THEN RAISE EXCEPTION 'restore_blocked created effect did not acknowledge'; END IF;

  SELECT command_result.operation_id INTO root_operation_id
  FROM public.trash_resource('document',scheduled_document,'created.fixture.purge-scheduled') command_result;
  UPDATE public.trash_operations SET state='purge_scheduled',purge_scheduled_at=now(),last_error_code=NULL
  WHERE id=root_operation_id;
  SELECT * INTO event_row FROM public.outbox_events WHERE aggregate_id=root_operation_id AND event_kind='trash.operation_created.v1';
  PERFORM public.lease_document_outbox_events(100,120);
  SELECT * INTO event_row FROM public.outbox_events WHERE id=event_row.id;
  SELECT * INTO result FROM public.handle_trash_operation_created_effect(event_row.id,org,event_row.lease_token,'trash.operation_created.v1');
  IF result.code<>'handled' OR result.outcome_code<>'operation_semantic_index_invalidated' OR result.affected_count<>1
     OR (SELECT embedding IS NULL FROM public.documents WHERE id=scheduled_document) IS NOT TRUE THEN
    RAISE EXCEPTION 'late purge_scheduled creation event was not invalidated';
  END IF;
  SELECT * INTO result FROM public.ack_document_outbox_event(event_row.id,event_row.lease_token,'created-effect-scheduled');
  IF result.code<>'ok' THEN RAISE EXCEPTION 'purge_scheduled created effect did not acknowledge'; END IF;

  -- Direct invocation/table DML remains unavailable even with caller/session
  -- role claims; only the Trigger service client may execute the RPC.
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.handle_trash_operation_created_effect(event_row.id,org,event_row.lease_token,'trash.operation_created.v1');
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'authenticated created-effect RPC call allowed'; END IF;
  SET LOCAL ROLE service_role;
  denied := false;
  BEGIN
    INSERT INTO public.trash_operation_created_effect_receipts(event_id,org_id,operation_id,event_kind,outcome_code,affected_count)
    VALUES(gen_random_uuid(),org,root_operation_id,'trash.operation_created.v1','operation_semantic_index_invalidated',0);
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'service role direct creation receipt write allowed'; END IF;
  denied := false;
  BEGIN
    UPDATE public.trash_operation_created_effect_receipts SET affected_count=999 WHERE event_id=event_row.id;
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'service role direct creation receipt update allowed'; END IF;
END $fixture$;

ROLLBACK;
