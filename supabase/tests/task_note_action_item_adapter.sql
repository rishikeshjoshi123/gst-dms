-- Run after `npx supabase db reset --local --no-seed`.
BEGIN;

DO $fixture$
DECLARE
  owner_a uuid := '95000000-0000-0000-0000-000000000001';
  associate_a uuid := '95000000-0000-0000-0000-000000000002';
  viewer_a uuid := '95000000-0000-0000-0000-000000000003';
  owner_b uuid := '95000000-0000-0000-0000-000000000004';
  org_a uuid := '95100000-0000-0000-0000-000000000001';
  org_b uuid := '95100000-0000-0000-0000-000000000002';
  client_a uuid := '95200000-0000-0000-0000-000000000001';
  client_b uuid := '95200000-0000-0000-0000-000000000002';
  matter_a uuid := '95300000-0000-0000-0000-000000000001';
  matter_b uuid := '95300000-0000-0000-0000-000000000002';
  doc_a uuid := '95400000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
    ('00000000-0000-0000-0000-000000000000',owner_a,'authenticated','authenticated','task-owner-a@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',associate_a,'authenticated','authenticated','task-associate-a@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',viewer_a,'authenticated','authenticated','task-viewer-a@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',owner_b,'authenticated','authenticated','task-owner-b@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES
    (org_a,'Task fixture A',owner_a),(org_b,'Task fixture B',owner_b);
  INSERT INTO public.org_members(org_id,user_id,role) VALUES
    (org_a,associate_a,'associate'),(org_a,viewer_a,'viewer');
  INSERT INTO public.clients(id,org_id,name) VALUES
    (client_a,org_a,'Task client A'),(client_b,org_b,'Task client B');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES
    (matter_a,org_a,client_a,'Task matter A'),(matter_b,org_b,client_b,'Task matter B');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by) VALUES
    (doc_a,org_a,matter_a,'fixture/task-note.pdf',owner_a);
END $fixture$;

DO $operational_timezone_defaults$
BEGIN
  UPDATE public.user_profiles
  SET timezone = CASE user_id::text
    WHEN '95000000-0000-0000-0000-000000000001' THEN 'America/Los_Angeles'
    WHEN '95000000-0000-0000-0000-000000000002' THEN 'Asia/Tokyo'
    WHEN '95000000-0000-0000-0000-000000000003' THEN 'Europe/Berlin'
    ELSE timezone
  END
  WHERE user_id IN (
    '95000000-0000-0000-0000-000000000001',
    '95000000-0000-0000-0000-000000000002',
    '95000000-0000-0000-0000-000000000003'
  );
  IF (SELECT count(*) FROM public.organisation_operational_settings
      WHERE org_id IN ('95100000-0000-0000-0000-000000000001', '95100000-0000-0000-0000-000000000002')
        AND timezone = 'Asia/Kolkata' AND revision = 1) <> 2 THEN
    RAISE EXCEPTION 'organisation operational timezone was not initialized to Asia/Kolkata';
  END IF;
END $operational_timezone_defaults$;

SET LOCAL ROLE authenticated;
DO $command$
DECLARE first_result record; replay_result record; configured_result record; configured_replay record;
  no_due_result record; associate_first_result record; associate_replay_result record;
  ordinary_result record; result record;
BEGIN
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub','95000000-0000-0000-0000-000000000001',true);
  SELECT * INTO first_result FROM public.create_note_with_optional_task(
    '95300000-0000-0000-0000-000000000001','Prepare the hearing bundle','general',true,
    '95500000-0000-0000-0000-000000000001','95400000-0000-0000-0000-000000000001',
    '95000000-0000-0000-0000-000000000002',DATE '2026-09-15',NULL,NULL,NULL);
  IF first_result.code<>'ok' OR first_result.note_id IS NULL OR first_result.task_id IS NULL OR first_result.replayed THEN
    RAISE EXCEPTION 'action-item note command did not create one note/task';
  END IF;
  SELECT * INTO replay_result FROM public.create_note_with_optional_task(
    '95300000-0000-0000-0000-000000000001','Prepare the hearing bundle','general',true,
    '95500000-0000-0000-0000-000000000001','95400000-0000-0000-0000-000000000001',
    '95000000-0000-0000-0000-000000000002',DATE '2026-09-15',NULL,NULL,NULL);
  IF replay_result.code<>'ok' OR NOT replay_result.replayed OR replay_result.note_id<>first_result.note_id OR replay_result.task_id<>first_result.task_id THEN
    RAISE EXCEPTION 'same Task command retry did not return the durable original';
  END IF;
  SELECT * INTO result FROM public.get_my_organisation_operational_settings();
  IF result.code<>'ok' OR result.timezone<>'Asia/Kolkata' OR result.revision<>1 THEN
    RAISE EXCEPTION 'owner/admin operational timezone read did not return the initialized own-org setting';
  END IF;
  SELECT * INTO result FROM public.set_my_organisation_operational_timezone('Invalid/Timezone', 1);
  IF result.code<>'invalid_timezone' OR result.timezone<>'Asia/Kolkata' OR result.revision<>1 THEN
    RAISE EXCEPTION 'invalid organisation timezone was accepted or changed the setting';
  END IF;
  SELECT * INTO result FROM public.set_my_organisation_operational_timezone('America/New_York', 1);
  IF result.code<>'updated' OR result.timezone<>'America/New_York' OR result.revision<>2 THEN
    RAISE EXCEPTION 'owner/admin operational timezone command did not update the own-org setting';
  END IF;
  SELECT * INTO configured_result FROM public.create_note_with_optional_task(
    '95300000-0000-0000-0000-000000000001','Use the organisation timezone','general',true,
    '95500000-0000-0000-0000-000000000007',NULL,
    '95000000-0000-0000-0000-000000000002',DATE '2026-09-16',NULL,NULL,NULL);
  IF configured_result.code<>'ok' OR configured_result.task_id IS NULL OR configured_result.replayed THEN
    RAISE EXCEPTION 'configured organisation-timezone Task was not created';
  END IF;
  SELECT * INTO no_due_result FROM public.create_note_with_optional_task(
    '95300000-0000-0000-0000-000000000001','No due date has no timezone','general',true,
    '95500000-0000-0000-0000-000000000008');
  IF no_due_result.code<>'ok' OR no_due_result.task_id IS NULL OR no_due_result.replayed THEN
    RAISE EXCEPTION 'undated Task was not created';
  END IF;
  SELECT * INTO result FROM public.set_my_organisation_operational_timezone('Europe/London', 2);
  IF result.code<>'updated' OR result.timezone<>'Europe/London' OR result.revision<>3 THEN
    RAISE EXCEPTION 'operational timezone did not support a subsequent revisioned update';
  END IF;
  SELECT * INTO configured_replay FROM public.create_note_with_optional_task(
    '95300000-0000-0000-0000-000000000001','Use the organisation timezone','general',true,
    '95500000-0000-0000-0000-000000000007',NULL,
    '95000000-0000-0000-0000-000000000002',DATE '2026-09-16',NULL,NULL,NULL);
  IF configured_replay.code<>'ok' OR NOT configured_replay.replayed
     OR configured_replay.task_id<>configured_result.task_id THEN
    RAISE EXCEPTION 'Task replay did not return the original Task after timezone changed';
  END IF;
  PERFORM set_config('request.jwt.claim.sub','95000000-0000-0000-0000-000000000002',true);
  SELECT * INTO associate_first_result FROM public.create_note_with_optional_task(
    '95300000-0000-0000-0000-000000000001','Associate replay safety','general',true,
    '95500000-0000-0000-0000-000000000009',NULL,NULL,DATE '2026-09-17',NULL,NULL,NULL);
  IF associate_first_result.code<>'ok' OR associate_first_result.note_id IS NULL
     OR associate_first_result.task_id IS NULL OR associate_first_result.replayed THEN
    RAISE EXCEPTION 'active associate command did not create a replayable Task';
  END IF;
  SELECT * INTO associate_replay_result FROM public.create_note_with_optional_task(
    '95300000-0000-0000-0000-000000000001','Associate replay safety','general',true,
    '95500000-0000-0000-0000-000000000009',NULL,NULL,DATE '2026-09-17',NULL,NULL,NULL);
  IF associate_replay_result.code<>'ok' OR NOT associate_replay_result.replayed
     OR associate_replay_result.note_id<>associate_first_result.note_id
     OR associate_replay_result.task_id<>associate_first_result.task_id THEN
    RAISE EXCEPTION 'active associate replay did not return the durable original';
  END IF;
  PERFORM set_config('request.jwt.claim.sub','95000000-0000-0000-0000-000000000001',true);
  SELECT * INTO ordinary_result FROM public.create_note_with_optional_task(
    '95300000-0000-0000-0000-000000000001','Ordinary note has no Task Activity','general',false,
    '95500000-0000-0000-0000-000000000006');
  IF ordinary_result.code<>'ok' OR ordinary_result.note_id IS NULL OR ordinary_result.task_id IS NOT NULL OR ordinary_result.replayed THEN
    RAISE EXCEPTION 'ordinary note command did not remain Task-free';
  END IF;
  -- The successful command must not leave any reusable transaction setting or
  -- table privilege that lets a direct insert escape the Task transaction.
  PERFORM set_config('casechain.task_note_adapter','create',true);
  BEGIN
    INSERT INTO public.case_notes(org_id,author_id,matter_id,content,template_type,is_action_item)
    VALUES('95100000-0000-0000-0000-000000000001',auth.uid(),'95300000-0000-0000-0000-000000000001','Forged action','general',true);
    RAISE EXCEPTION 'direct action-item insert unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  SELECT * INTO result FROM public.create_note_with_optional_task(
    '95300000-0000-0000-0000-000000000001','Changed replay payload','general',true,
    '95500000-0000-0000-0000-000000000001','95400000-0000-0000-0000-000000000001',
    '95000000-0000-0000-0000-000000000002',DATE '2026-09-15',NULL,NULL,NULL);
  IF result.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'same key with changed command replayed'; END IF;
  SELECT * INTO result FROM public.create_note_with_optional_task(
    '95300000-0000-0000-0000-000000000002','Foreign matter','general',false,
    '95500000-0000-0000-0000-000000000002');
  IF result.code<>'context_unavailable' THEN RAISE EXCEPTION 'cross-tenant matter was accepted'; END IF;
  SELECT * INTO result FROM public.create_note_with_optional_task(
    '95300000-0000-0000-0000-000000000001','Viewer assignment','general',true,
    '95500000-0000-0000-0000-000000000003',NULL,'95000000-0000-0000-0000-000000000003');
  IF result.code<>'invalid_assignee' THEN RAISE EXCEPTION 'viewer assignment was accepted'; END IF;
  PERFORM set_config('request.jwt.claim.sub','95000000-0000-0000-0000-000000000003',true);
  SELECT * INTO result FROM public.get_my_organisation_operational_settings();
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'viewer read the operational setting'; END IF;
  SELECT * INTO result FROM public.set_my_organisation_operational_timezone('Pacific/Auckland', 3);
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'viewer changed the operational setting'; END IF;
  SELECT * INTO result FROM public.create_note_with_optional_task(
    '95300000-0000-0000-0000-000000000001','Viewer mutation','general',false,
    '95500000-0000-0000-0000-000000000004');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'viewer Task/note command was accepted'; END IF;
  PERFORM set_config('request.jwt.claim.sub','95000000-0000-0000-0000-000000000004',true);
  SELECT * INTO result FROM public.create_note_with_optional_task(
    '95300000-0000-0000-0000-000000000002','Actor B replay','general',false,
    '95500000-0000-0000-0000-000000000001');
  IF result.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'cross-actor/tenant idempotency replay was accepted'; END IF;
END $command$;
RESET ROLE;

DO $durability$
DECLARE note_id uuid; task_id uuid; configured_task_id uuid; no_due_task_id uuid; ordinary_note_id uuid;
BEGIN
  SELECT receipt.note_id,receipt.task_id INTO note_id,task_id FROM public.task_command_receipts receipt
    WHERE receipt.idempotency_key='95500000-0000-0000-0000-000000000001';
  SELECT receipt.note_id INTO ordinary_note_id FROM public.task_command_receipts receipt
    WHERE receipt.idempotency_key='95500000-0000-0000-0000-000000000006';
  SELECT receipt.task_id INTO configured_task_id FROM public.task_command_receipts receipt
    WHERE receipt.idempotency_key='95500000-0000-0000-0000-000000000007';
  SELECT receipt.task_id INTO no_due_task_id FROM public.task_command_receipts receipt
    WHERE receipt.idempotency_key='95500000-0000-0000-0000-000000000008';
  IF (SELECT count(*) FROM public.tasks WHERE origin_note_id=note_id)<>1
     OR NOT EXISTS (SELECT 1 FROM public.tasks task WHERE task.id=task_id
       AND task.org_id='95100000-0000-0000-0000-000000000001'
       AND task.client_id='95200000-0000-0000-0000-000000000001'
       AND task.matter_id='95300000-0000-0000-0000-000000000001'
       AND task.document_id='95400000-0000-0000-0000-000000000001'
       AND task.creator_user_id='95000000-0000-0000-0000-000000000001'
       AND task.assignee_user_id='95000000-0000-0000-0000-000000000002'
       AND task.status='open' AND task.priority='normal' AND task.lifecycle_state='active'
       AND task.due_date=DATE '2026-09-15' AND task.due_time IS NULL AND task.due_timezone='Asia/Kolkata'
       AND task.revision=1 AND task.origin_snapshot='Prepare the hearing bundle') THEN
    RAISE EXCEPTION 'Task did not retain the approved context/origin/date-only contract';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tasks task WHERE task.id=configured_task_id
    AND task.due_date=DATE '2026-09-16' AND task.due_time IS NULL
    AND task.due_timezone='America/New_York') THEN
    RAISE EXCEPTION 'Task used a personal or changed organisation timezone instead of its creation-time operational timezone';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tasks task WHERE task.id=no_due_task_id
    AND task.due_date IS NULL AND task.due_time IS NULL AND task.due_timezone IS NULL) THEN
    RAISE EXCEPTION 'undated Task retained a timezone';
  END IF;
  IF (SELECT count(*) FROM public.activity_events event WHERE event.subject_type='task' AND event.subject_id=task_id AND event.event_type='task.created' AND event.event_version=1)<>1
     OR (SELECT count(*) FROM public.activity_projector_outbox_events outbox JOIN public.activity_events event ON event.id=outbox.activity_event_id WHERE event.subject_type='task' AND event.subject_id=task_id AND event.event_type='task.created')<>1
     OR NOT EXISTS (SELECT 1 FROM public.activity_events event WHERE event.subject_id=task_id
       AND event.org_id='95100000-0000-0000-0000-000000000001'
       AND event.client_id='95200000-0000-0000-0000-000000000001'
       AND event.matter_id='95300000-0000-0000-0000-000000000001'
       AND event.target_type='task' AND event.target_id=task_id
       AND event.subject_snapshot='Task' AND event.summary='Task created' AND event.metadata='{}'::jsonb
       AND event.idempotency_key ~ '^[0-9a-f]{64}$') THEN
    RAISE EXCEPTION 'Task Activity/outbox was not exactly once, lineaged, or snapshot-safe';
  END IF;
  IF EXISTS (SELECT 1 FROM public.activity_events event WHERE event.event_type='task.created' AND event.subject_id=ordinary_note_id)
     OR EXISTS (SELECT 1 FROM public.tasks task WHERE task.origin_note_id=ordinary_note_id) THEN
    RAISE EXCEPTION 'ordinary note created Task state or Task Activity';
  END IF;
  INSERT INTO public.tasks(id,org_id,client_id,matter_id,title,origin_kind,origin_note_id,origin_snapshot,creator_user_id,status_changed_by)
  VALUES ('95400000-0000-0000-0000-000000000002','95100000-0000-0000-0000-000000000001','95200000-0000-0000-0000-000000000001','95300000-0000-0000-0000-000000000001','Other task','case_note',gen_random_uuid(),'Other task', '95000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001');
  UPDATE public.case_notes SET content='Edited note',action_item_resolved=true,deleted_at=now() WHERE id=note_id;
  IF NOT EXISTS (SELECT 1 FROM public.tasks task WHERE task.id=task_id AND task.status='open'
    AND task.origin_snapshot='Prepare the hearing bundle' AND task.lifecycle_state='active') THEN
    RAISE EXCEPTION 'note edit/delete or legacy completion toggle silently changed its Task';
  END IF;
END $durability$;

SET LOCAL ROLE authenticated;
DO $direct_bypass$
DECLARE blocked boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub','95000000-0000-0000-0000-000000000001',true);
  BEGIN
    INSERT INTO public.tasks(org_id,title,origin_kind,origin_note_id,origin_snapshot,creator_user_id,status_changed_by)
    VALUES('95100000-0000-0000-0000-000000000001','Forged','case_note',gen_random_uuid(),'Forged',auth.uid(),auth.uid());
  EXCEPTION WHEN insufficient_privilege THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'authenticated direct Task table insert was accepted'; END IF;
  blocked := false;
  BEGIN
    INSERT INTO public.case_notes(org_id,author_id,matter_id,content,template_type,is_action_item)
    VALUES('95100000-0000-0000-0000-000000000001',auth.uid(),'95300000-0000-0000-0000-000000000001','Forged action','general',true);
  EXCEPTION WHEN insufficient_privilege THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'direct action-item note bypass was accepted'; END IF;
END $direct_bypass$;
RESET ROLE;

SET LOCAL ROLE authenticated;
DO $operational_timezone_direct_table_bypass$
DECLARE blocked boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub','95000000-0000-0000-0000-000000000001',true);
  BEGIN
    SELECT timezone FROM public.organisation_operational_settings
    WHERE org_id='95100000-0000-0000-0000-000000000002';
  EXCEPTION WHEN insufficient_privilege THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'authenticated user read a forged organisation operational setting directly'; END IF;
  blocked := false;
  BEGIN
    UPDATE public.organisation_operational_settings SET timezone='Pacific/Auckland'
    WHERE org_id='95100000-0000-0000-0000-000000000001';
  EXCEPTION WHEN insufficient_privilege THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'authenticated user changed an organisation operational setting directly'; END IF;
END $operational_timezone_direct_table_bypass$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $service_note_bypass$
DECLARE blocked boolean := false;
BEGIN
  BEGIN
    INSERT INTO public.case_notes(org_id,author_id,matter_id,content,template_type,is_action_item)
    VALUES('95100000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001','95300000-0000-0000-0000-000000000001','Forged service note','general',false);
  EXCEPTION WHEN insufficient_privilege THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'service role direct note insert was accepted'; END IF;
END $service_note_bypass$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $service_operational_timezone_bypass$
DECLARE blocked boolean := false;
BEGIN
  BEGIN
    SELECT timezone FROM public.organisation_operational_settings
    WHERE org_id='95100000-0000-0000-0000-000000000001';
  EXCEPTION WHEN insufficient_privilege THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'service role read an organisation operational setting directly'; END IF;
  IF has_function_privilege('service_role','public.get_my_organisation_operational_settings()','EXECUTE')
     OR has_function_privilege('service_role','public.set_my_organisation_operational_timezone(text,bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'service role received an operational timezone RPC bypass';
  END IF;
END $service_operational_timezone_bypass$;
RESET ROLE;

DO $task_created_target_setup$
DECLARE task_a uuid;
BEGIN
  SELECT task_id INTO task_a FROM public.task_command_receipts
    WHERE idempotency_key='95500000-0000-0000-0000-000000000001';
  PERFORM set_config('casechain.fixture_task_a', task_a::text, true);
END $task_created_target_setup$;

SET LOCAL ROLE service_role;
DO $task_created_target$
DECLARE task_a uuid := current_setting('casechain.fixture_task_a')::uuid; blocked boolean := false;
BEGIN
  BEGIN
    PERFORM public.append_activity_event(
      '95100000-0000-0000-0000-000000000001','task.created',1::smallint,'user',
      '95000000-0000-0000-0000-000000000001',NULL,'task',task_a,
      '95200000-0000-0000-0000-000000000001','95300000-0000-0000-0000-000000000001',
      'Task','Task created','{}'::jsonb,'task','95400000-0000-0000-0000-000000000002',NULL,
      NULL,NULL,'task-fixture-forged-created-target',now()
    );
  EXCEPTION WHEN raise_exception THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'task.created accepted another Task in the same matter as its target'; END IF;
END $task_created_target$;
RESET ROLE;

SET LOCAL ROLE authenticated;
DO $trash$
DECLARE result record;
BEGIN
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub','95000000-0000-0000-0000-000000000001',true);
  PERFORM public.trash_resource('matter','95300000-0000-0000-0000-000000000001','task.fixture.trash');
  SELECT * INTO result FROM public.create_note_with_optional_task(
    '95300000-0000-0000-0000-000000000001','Trashed matter','general',false,
    '95500000-0000-0000-0000-000000000005');
  IF result.code<>'context_unavailable' THEN RAISE EXCEPTION 'trashed context accepted a Task command'; END IF;
END $trash$;
RESET ROLE;

DO $suspend_associate$
BEGIN
  UPDATE public.organisation_memberships
  SET state='suspended',
      suspended_at=now(),
      suspended_by='95000000-0000-0000-0000-000000000001'
  WHERE org_id='95100000-0000-0000-0000-000000000001'
    AND user_id='95000000-0000-0000-0000-000000000002'
    AND state='active';
  IF NOT EXISTS (
    SELECT 1 FROM public.organisation_memberships
    WHERE org_id='95100000-0000-0000-0000-000000000001'
      AND user_id='95000000-0000-0000-0000-000000000002'
      AND state='suspended'
  ) THEN
    RAISE EXCEPTION 'fixture could not suspend the replay actor';
  END IF;
END $suspend_associate$;

SET LOCAL ROLE authenticated;
DO $suspended_actor_replay$
DECLARE result record;
BEGIN
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub','95000000-0000-0000-0000-000000000002',true);
  SELECT * INTO result FROM public.create_note_with_optional_task(
    '95300000-0000-0000-0000-000000000001','Associate replay safety','general',true,
    '95500000-0000-0000-0000-000000000009',NULL,NULL,DATE '2026-09-17',NULL,NULL,NULL);
  IF result.code<>'not_allowed' OR result.note_id IS NOT NULL OR result.task_id IS NOT NULL OR result.replayed THEN
    RAISE EXCEPTION 'suspended actor replay returned a historical note or Task locator';
  END IF;
END $suspended_actor_replay$;
RESET ROLE;

DO $grant_surface$
BEGIN
  IF has_table_privilege('authenticated','public.tasks','INSERT')
     OR has_table_privilege('authenticated','public.tasks','UPDATE')
     OR has_table_privilege('service_role','public.tasks','INSERT')
     OR has_table_privilege('service_role','public.activity_events','INSERT')
     OR has_table_privilege('authenticated','public.organisation_operational_settings','SELECT')
     OR has_table_privilege('authenticated','public.organisation_operational_settings','UPDATE')
     OR has_table_privilege('service_role','public.organisation_operational_settings','SELECT')
     OR has_table_privilege('service_role','public.organisation_operational_settings','UPDATE')
     OR has_function_privilege('authenticated','public.append_activity_event(uuid,text,smallint,public.activity_actor_kind,uuid,text,text,uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid,uuid,uuid,text,timestamptz)','EXECUTE')
     OR has_function_privilege('service_role','public.create_note_with_optional_task(uuid,text,public.note_template_type,boolean,uuid,uuid,uuid,date,uuid,text,integer)','EXECUTE')
     OR has_function_privilege('service_role','public.set_my_organisation_operational_timezone(text,bigint)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.set_my_organisation_operational_timezone(text,bigint)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.create_note_with_optional_task(uuid,text,public.note_template_type,boolean,uuid,uuid,uuid,date,uuid,text,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'Task command grant surface is unsafe';
  END IF;
END $grant_surface$;

ROLLBACK;
