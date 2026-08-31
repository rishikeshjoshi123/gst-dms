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

SET LOCAL ROLE authenticated;
DO $command$
DECLARE first_result record; replay_result record; result record;
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
DECLARE note_id uuid; task_id uuid;
BEGIN
  SELECT receipt.note_id,receipt.task_id INTO note_id,task_id FROM public.task_command_receipts receipt
    WHERE receipt.idempotency_key='95500000-0000-0000-0000-000000000001';
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

DO $grant_surface$
BEGIN
  IF has_table_privilege('authenticated','public.tasks','INSERT')
     OR has_table_privilege('authenticated','public.tasks','UPDATE')
     OR has_table_privilege('service_role','public.tasks','INSERT')
     OR has_function_privilege('service_role','public.create_note_with_optional_task(uuid,text,public.note_template_type,boolean,uuid,uuid,uuid,date,uuid,text,integer)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.create_note_with_optional_task(uuid,text,public.note_template_type,boolean,uuid,uuid,uuid,date,uuid,text,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'Task command grant surface is unsafe';
  END IF;
END $grant_surface$;

ROLLBACK;
