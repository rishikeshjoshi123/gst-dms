-- Run after `npx supabase db reset --local --no-seed`.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000','a1000000-0000-0000-0000-000000000001','authenticated','authenticated','task-owner@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1000000-0000-0000-0000-000000000002','authenticated','authenticated','task-associate@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1000000-0000-0000-0000-000000000003','authenticated','authenticated','task-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1000000-0000-0000-0000-000000000004','authenticated','authenticated','task-foreign@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by)
VALUES
  ('a1100000-0000-0000-0000-000000000001','Task closure organisation','a1000000-0000-0000-0000-000000000001'),
  ('a1100000-0000-0000-0000-000000000002','Foreign organisation','a1000000-0000-0000-0000-000000000004');
INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at)
VALUES
  ('a1110000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000002','associate','active',1,now()),
  ('a1110000-0000-0000-0000-000000000003','a1100000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000003','viewer','active',1,now());
UPDATE public.organisations AS organisation
SET owner_membership_id = membership.id
FROM public.organisation_memberships AS membership
WHERE organisation.id = membership.org_id
  AND membership.user_id = organisation.created_by
  AND membership.state = 'active';
INSERT INTO public.clients(id,org_id,name)
VALUES ('a1200000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001','Task closure client'),
  ('a1200000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000002','Foreign task client');
INSERT INTO public.matters(id,org_id,client_id,title)
VALUES ('a1300000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000001','a1200000-0000-0000-0000-000000000001','Task closure matter'),
  ('a1300000-0000-0000-0000-000000000002','a1100000-0000-0000-0000-000000000002','a1200000-0000-0000-0000-000000000002','Foreign task matter');
INSERT INTO public.tasks(id,org_id,client_id,matter_id,title,origin_kind,origin_note_id,origin_snapshot,creator_user_id,status_changed_by)
VALUES ('a1500000-0000-0000-0000-000000000001','a1100000-0000-0000-0000-000000000002','a1200000-0000-0000-0000-000000000002','a1300000-0000-0000-0000-000000000002','Foreign Task','case_note','a1510000-0000-0000-0000-000000000001','Foreign Task','a1000000-0000-0000-0000-000000000004','a1000000-0000-0000-0000-000000000004');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
DO $create_and_read$
DECLARE created record; listed record; detail record; summary record;
BEGIN
  SELECT * INTO created FROM public.create_note_with_optional_task(
    'a1300000-0000-0000-0000-000000000001','Prepare the appeal paper book','general',true,
    'a1400000-0000-0000-0000-000000000001',NULL,
    'a1000000-0000-0000-0000-000000000002',DATE '2026-10-01');
  IF created.code <> 'ok' OR created.task_id IS NULL OR created.replayed THEN
    RAISE EXCEPTION 'fixture task creation failed';
  END IF;
  PERFORM set_config('casechain.task_id', created.task_id::text, true);
  PERFORM set_config('casechain.note_id', created.note_id::text, true);
  SELECT * INTO listed FROM public.get_my_tasks(NULL, 20, 0) WHERE task_id=created.task_id;
  IF listed.task_id IS DISTINCT FROM created.task_id OR listed.status <> 'open'
     OR listed.due_date <> DATE '2026-10-01' OR listed.due_timezone <> 'Asia/Kolkata'
     OR NOT listed.origin_available THEN
    RAISE EXCEPTION 'authorised task list omitted or corrupted the Task projection';
  END IF;
  SELECT * INTO detail FROM public.get_task_detail(created.task_id);
  IF detail.origin_note_id <> created.note_id OR NOT detail.origin_available
     OR detail.completed_at IS NOT NULL OR detail.completed_by IS NOT NULL THEN
    RAISE EXCEPTION 'authorised Task detail did not preserve the safe origin/current state contract';
  END IF;
  SELECT * INTO summary FROM public.get_note_task_summaries(ARRAY[created.note_id]);
  IF summary.task_id <> created.task_id OR summary.status <> 'open' OR summary.revision <> 1 THEN
    RAISE EXCEPTION 'Notes Task summary did not return one current Task';
  END IF;
END $create_and_read$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
DO $transitions$
DECLARE task_a uuid := current_setting('casechain.task_id')::uuid; note_a uuid := current_setting('casechain.note_id')::uuid;
  result record; detail record; legacy_assignee uuid; legacy_due date; legacy_resolved boolean; blocked boolean := false;
BEGIN
  SELECT action_item_assignee,action_item_due_date,action_item_resolved
  INTO legacy_assignee,legacy_due,legacy_resolved FROM public.case_notes WHERE id=note_a;
  BEGIN
    UPDATE public.case_notes SET action_item_resolved=true WHERE id=note_a;
  EXCEPTION WHEN insufficient_privilege THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'legacy Note state mutation bypassed Task authority'; END IF;
  SELECT * INTO result FROM public.transition_task(task_a,'start',1,'a1400000-0000-0000-0000-000000000002');
  IF result.code <> 'ok' OR result.revision <> 2 OR result.status <> 'in_progress' OR result.replayed THEN
    RAISE EXCEPTION 'start transition did not apply with revision 2';
  END IF;
  SELECT * INTO result FROM public.transition_task(task_a,'start',1,'a1400000-0000-0000-0000-000000000002');
  IF result.code <> 'ok' OR result.revision <> 2 OR NOT result.replayed THEN
    RAISE EXCEPTION 'same-key transition retry was not safe';
  END IF;
  SELECT * INTO result FROM public.transition_task(task_a,'complete',1,'a1400000-0000-0000-0000-000000000003');
  IF result.code <> 'conflict' OR result.revision <> 2 OR result.status <> 'in_progress' THEN
    RAISE EXCEPTION 'stale revision applied or did not disclose current authorised revision';
  END IF;
  SELECT * INTO result FROM public.transition_task(task_a,'complete',2,'a1400000-0000-0000-0000-000000000002');
  IF result.code <> 'idempotency_conflict' THEN
    RAISE EXCEPTION 'same idempotency key with a changed payload was accepted';
  END IF;
  SELECT * INTO result FROM public.transition_task(task_a,'complete',2,'a1400000-0000-0000-0000-000000000004');
  IF result.code <> 'ok' OR result.revision <> 3 OR result.status <> 'completed' THEN
    RAISE EXCEPTION 'complete transition did not apply';
  END IF;
  SELECT * INTO detail FROM public.get_task_detail(task_a);
  IF detail.completed_at IS NULL OR detail.completed_by <> auth.uid() THEN
    RAISE EXCEPTION 'complete transition did not set completion audit fields';
  END IF;
  SELECT * INTO result FROM public.transition_task(task_a,'reopen',3,'a1400000-0000-0000-0000-000000000005');
  SELECT * INTO detail FROM public.get_task_detail(task_a);
  IF result.code <> 'ok' OR result.revision <> 4 OR result.status <> 'open'
     OR detail.completed_at IS NOT NULL OR detail.completed_by IS NOT NULL THEN
    RAISE EXCEPTION 'reopen transition did not clear completion fields';
  END IF;
  SELECT * INTO result FROM public.transition_task(task_a,'set_assignee',4,'a1400000-0000-0000-0000-000000000006','a1000000-0000-0000-0000-000000000002');
  IF result.code <> 'ok' OR result.revision <> 5 THEN RAISE EXCEPTION 'valid operational reassignment failed'; END IF;
  SELECT * INTO result FROM public.transition_task(task_a,'set_due_date',5,'a1400000-0000-0000-0000-000000000007',NULL,DATE '2026-10-08');
  SELECT * INTO detail FROM public.get_task_detail(task_a);
  IF result.code <> 'ok' OR result.revision <> 6
     OR detail.due_date <> DATE '2026-10-08' OR detail.due_time IS NOT NULL OR detail.due_timezone <> 'Asia/Kolkata' THEN
    RAISE EXCEPTION 'organisation-timezone date-only due change failed';
  END IF;
  SELECT * INTO result FROM public.transition_task(task_a,'clear_due_date',6,'a1400000-0000-0000-0000-000000000008');
  SELECT * INTO detail FROM public.get_task_detail(task_a);
  IF result.code <> 'ok' OR result.revision <> 7
     OR detail.due_date IS NOT NULL OR detail.due_time IS NOT NULL OR detail.due_timezone IS NOT NULL THEN
    RAISE EXCEPTION 'clear due date did not restore the null due contract';
  END IF;
  IF EXISTS (SELECT 1 FROM public.case_notes WHERE id=note_a
    AND (action_item_assignee IS DISTINCT FROM legacy_assignee
      OR action_item_due_date IS DISTINCT FROM legacy_due
      OR action_item_resolved IS DISTINCT FROM legacy_resolved)) THEN
    RAISE EXCEPTION 'Task transition mutated legacy Note current state';
  END IF;
  IF (SELECT count(*) FROM public.get_task_transition_history(task_a)) <> 6 THEN
    RAISE EXCEPTION 'authorised Task transition history was not readable';
  END IF;
END $transitions$;
RESET ROLE;

DO $transition_audit$
DECLARE task_a uuid := current_setting('casechain.task_id')::uuid;
BEGIN
  IF (SELECT count(*) FROM public.task_transition_history WHERE task_id=task_a) <> 6
     OR (SELECT count(*) FROM public.task_transition_receipts WHERE task_id=task_a) <> 6
     OR (SELECT count(*) FROM public.activity_events WHERE subject_type='task' AND subject_id=task_a AND event_type='task.transitioned' AND event_version=1) <> 6
     OR (SELECT count(*) FROM public.activity_projector_outbox_events AS outbox JOIN public.activity_events AS event ON event.id=outbox.activity_event_id WHERE event.subject_type='task' AND event.subject_id=task_a AND event.event_type='task.transitioned') <> 6
     OR EXISTS (SELECT 1 FROM public.activity_events WHERE subject_type='task' AND subject_id=task_a AND event_type='task.transitioned' AND metadata->>'command' NOT IN ('start','complete','reopen','set_assignee','set_due_date','clear_due_date'))
     OR NOT EXISTS (SELECT 1 FROM public.task_transition_history WHERE task_id=task_a
       AND command='start' AND from_status='open' AND to_status='in_progress' AND revision=2)
     OR NOT EXISTS (SELECT 1 FROM public.task_transition_history WHERE task_id=task_a
       AND command='complete' AND from_status='in_progress' AND to_status='completed' AND revision=3) THEN
    RAISE EXCEPTION 'transition audit/receipt history is not exactly once or did not retain locked pre-transition state';
  END IF;
END $transition_audit$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000003',true);
DO $viewer_and_cross_tenant$
DECLARE task_a uuid := current_setting('casechain.task_id')::uuid; result record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.get_task_detail(task_a)) THEN
    RAISE EXCEPTION 'active Viewer could not read an authorised Task';
  END IF;
  SELECT * INTO result FROM public.transition_task(task_a,'start',7,'a1400000-0000-0000-0000-000000000009');
  IF result.code <> 'not_allowed' THEN RAISE EXCEPTION 'Viewer mutated a Task'; END IF;
  SELECT * INTO result FROM public.get_task_detail('a1500000-0000-0000-0000-000000000001');
  IF result.task_id IS NOT NULL THEN RAISE EXCEPTION 'cross-tenant Task identifier disclosed a result'; END IF;
END $viewer_and_cross_tenant$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $direct_bypass$
DECLARE blocked boolean := false;
BEGIN
  BEGIN
    SELECT * FROM public.tasks;
  EXCEPTION WHEN insufficient_privilege THEN blocked := true;
  END;
  IF NOT blocked OR has_function_privilege('service_role','public.transition_task(uuid,text,bigint,uuid,uuid,date)','EXECUTE')
     OR has_function_privilege('service_role','public.get_my_tasks(public.task_status[],integer,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'service role received a private Task table or RPC bypass';
  END IF;
END $direct_bypass$;
RESET ROLE;

UPDATE public.case_notes SET deleted_at=now() WHERE id=current_setting('casechain.note_id')::uuid;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
DO $deleted_origin$
DECLARE task_a uuid := current_setting('casechain.task_id')::uuid; detail record;
BEGIN
  SELECT * INTO detail FROM public.get_task_detail(task_a);
  IF detail.task_id <> task_a OR detail.origin_available OR detail.origin_note_id IS NOT NULL THEN
    RAISE EXCEPTION 'deleted Task origin disclosed identity or hid the authorised Task';
  END IF;
  IF EXISTS (SELECT 1 FROM public.get_note_task_summaries(ARRAY[current_setting('casechain.note_id')::uuid])) THEN
    RAISE EXCEPTION 'deleted Note retained a live Task summary';
  END IF;
END $deleted_origin$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
SELECT public.trash_resource('matter','a1300000-0000-0000-0000-000000000001','task.closure.trash');
DO $trashed_context$
DECLARE task_a uuid := current_setting('casechain.task_id')::uuid; result record;
BEGIN
  IF EXISTS (SELECT 1 FROM public.get_task_detail(task_a)) OR EXISTS (SELECT 1 FROM public.get_my_tasks(NULL,20,0) WHERE task_id=task_a) THEN
    RAISE EXCEPTION 'trashed task context remained readable in active Task projections';
  END IF;
  SELECT * INTO result FROM public.transition_task(task_a,'start',7,'a1400000-0000-0000-0000-000000000010');
  IF result.code <> 'context_unavailable' THEN RAISE EXCEPTION 'trashed task context accepted a transition'; END IF;
  SELECT * INTO result FROM public.transition_task(task_a,'clear_due_date',6,'a1400000-0000-0000-0000-000000000008');
  IF result.code <> 'context_unavailable' OR result.task_id IS NOT NULL OR result.replayed THEN
    RAISE EXCEPTION 'trashed Task context replayed a historical command receipt';
  END IF;
END $trashed_context$;
RESET ROLE;

ROLLBACK;
