-- Run after `npx supabase db reset --local --no-seed`.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
('00000000-0000-0000-0000-000000000000','b1000000-0000-0000-0000-000000000001','authenticated','authenticated','comments-owner@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','b1000000-0000-0000-0000-000000000002','authenticated','authenticated','comments-associate@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','b1000000-0000-0000-0000-000000000003','authenticated','authenticated','comments-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','b1000000-0000-0000-0000-000000000004','authenticated','authenticated','comments-inactive@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','b1000000-0000-0000-0000-000000000005','authenticated','authenticated','comments-foreign@test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES
('b1100000-0000-0000-0000-000000000001','Comments fixture','b1000000-0000-0000-0000-000000000001'),
('b1100000-0000-0000-0000-000000000002','Comments foreign','b1000000-0000-0000-0000-000000000005');
INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at,suspended_at,suspended_by,suspension_reason) VALUES
('b1110000-0000-0000-0000-000000000002','b1100000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000002','associate','active',1,now(),NULL,NULL,NULL),
('b1110000-0000-0000-0000-000000000003','b1100000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000003','viewer','active',1,now(),NULL,NULL,NULL),
('b1110000-0000-0000-0000-000000000004','b1100000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000004','associate','suspended',1,now(),now(),'b1000000-0000-0000-0000-000000000001','fixture');
UPDATE public.organisations AS organisation SET owner_membership_id=membership.id FROM public.organisation_memberships AS membership WHERE organisation.id=membership.org_id AND membership.user_id=organisation.created_by;
INSERT INTO public.clients(id,org_id,name) VALUES
('b1200000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','Comments client'),
('b1200000-0000-0000-0000-000000000002','b1100000-0000-0000-0000-000000000002','Foreign client');
INSERT INTO public.matters(id,org_id,client_id,title) VALUES
('b1300000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-000000000001','Comments matter'),
('b1300000-0000-0000-0000-000000000002','b1100000-0000-0000-0000-000000000002','b1200000-0000-0000-0000-000000000002','Foreign matter');
INSERT INTO public.case_notes(id,org_id,author_id,matter_id,content,template_type,is_action_item) VALUES
('b1400000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','Origin remains independent','general',true);
INSERT INTO public.tasks(id,org_id,client_id,matter_id,title,origin_kind,origin_note_id,origin_snapshot,creator_user_id,assignee_user_id,status_changed_by) VALUES
('b1500000-0000-0000-0000-000000000001','b1100000-0000-0000-0000-000000000001','b1200000-0000-0000-0000-000000000001','b1300000-0000-0000-0000-000000000001','Comments task','case_note','b1400000-0000-0000-0000-000000000001','Origin remains independent','b1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000001'),
('b1500000-0000-0000-0000-000000000002','b1100000-0000-0000-0000-000000000002','b1200000-0000-0000-0000-000000000002','b1300000-0000-0000-0000-000000000002','Foreign comments task','case_note','b1410000-0000-0000-0000-000000000001','Foreign','b1000000-0000-0000-0000-000000000005','b1000000-0000-0000-0000-000000000005','b1000000-0000-0000-0000-000000000005');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
DO $owner_post$
DECLARE first_post record; replay record; thread_row record; comment_row record; result record;
BEGIN
  SELECT * INTO first_post FROM public.post_task_comment('b1500000-0000-0000-0000-000000000001','A private Task comment','b1600000-0000-0000-0000-000000000001',NULL,ARRAY['b1000000-0000-0000-0000-000000000002'::uuid]);
  IF first_post.code <> 'ok' OR first_post.sequence <> 1 OR first_post.replayed THEN RAISE EXCEPTION 'first Task comment was not created'; END IF;
  SELECT * INTO replay FROM public.post_task_comment('b1500000-0000-0000-0000-000000000001','A private Task comment','b1600000-0000-0000-0000-000000000001',NULL,ARRAY['b1000000-0000-0000-0000-000000000002'::uuid]);
  IF replay.code <> 'ok' OR NOT replay.replayed OR replay.comment_id <> first_post.comment_id THEN RAISE EXCEPTION 'same comment replay was not idempotent'; END IF;
  SELECT * INTO result FROM public.post_task_comment('b1500000-0000-0000-0000-000000000001','changed body','b1600000-0000-0000-0000-000000000001');
  IF result.code <> 'idempotency_conflict' THEN RAISE EXCEPTION 'changed payload reused a global comment key'; END IF;
  SELECT * INTO thread_row FROM public.get_task_comment_thread('b1500000-0000-0000-0000-000000000001');
  SELECT * INTO comment_row FROM public.get_task_comments('b1500000-0000-0000-0000-000000000001');
  IF thread_row.latest_sequence <> 1 OR thread_row.observed_sequence <> 0 OR thread_row.unread_count <> 1 OR comment_row.body <> 'A private Task comment' OR comment_row.mentioned_user_ids <> ARRAY['b1000000-0000-0000-0000-000000000002'::uuid] THEN RAISE EXCEPTION 'Task comment reader/cursor/mention projection was wrong'; END IF;
  IF (SELECT count(*) FROM public.case_notes WHERE id='b1400000-0000-0000-0000-000000000001' AND content='Origin remains independent') <> 1 OR thread_row.latest_sequence <> 1 THEN RAISE EXCEPTION 'Notes origin was copied or changed'; END IF;
  SELECT * INTO result FROM public.post_task_comment('b1500000-0000-0000-0000-000000000001','bad mention','b1600000-0000-0000-0000-000000000002',NULL,ARRAY['b1000000-0000-0000-0000-000000000004'::uuid]);
  IF result.code <> 'invalid_mentions' THEN RAISE EXCEPTION 'inactive mention target was accepted'; END IF;
  SELECT * INTO result FROM public.transition_task('b1500000-0000-0000-0000-000000000001','start',1,'b1600000-0000-0000-0000-000000000010');
  IF result.code <> 'ok' THEN RAISE EXCEPTION 'fixture could not start Task before terminal comment test'; END IF;
  SELECT * INTO result FROM public.transition_task('b1500000-0000-0000-0000-000000000001','complete',2,'b1600000-0000-0000-0000-000000000011');
  IF result.code <> 'ok' THEN RAISE EXCEPTION 'fixture could not complete Task before terminal comment test'; END IF;
  SELECT * INTO result FROM public.post_task_comment('b1500000-0000-0000-0000-000000000001','Terminal context is commentable','b1600000-0000-0000-0000-000000000003',first_post.comment_id);
  IF result.code <> 'ok' OR result.sequence <> 2 THEN RAISE EXCEPTION 'completed Task rejected a comment'; END IF;
END $owner_post$;
RESET ROLE;

INSERT INTO public.task_comment_read_cursors(thread_id,org_id,user_id,observed_sequence,observed_at)
  SELECT id,org_id,'b1000000-0000-0000-0000-000000000001',1,now()
  FROM public.task_comment_threads WHERE task_id='b1500000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
DO $post_preserves_cursor$
DECLARE result record; thread_row record;
BEGIN
  SELECT * INTO result FROM public.post_task_comment('b1500000-0000-0000-0000-000000000001','Posting does not observe unread comments','b1600000-0000-0000-0000-000000000012');
  SELECT * INTO thread_row FROM public.get_task_comment_thread('b1500000-0000-0000-0000-000000000001');
  IF result.code <> 'ok' OR result.sequence <> 3 OR thread_row.observed_sequence <> 1 OR thread_row.latest_sequence <> 3 OR thread_row.unread_count <> 2 THEN
    RAISE EXCEPTION 'posting silently advanced the Task comment read cursor';
  END IF;
END $post_preserves_cursor$;
RESET ROLE;

DO $comment_activity_audit$
BEGIN
  IF (SELECT count(*) FROM public.activity_events WHERE subject_id='b1500000-0000-0000-0000-000000000001' AND event_type='task.comment_posted' AND event_version=1) <> 3
     OR (SELECT count(*) FROM public.activity_projector_outbox_events AS outbox JOIN public.activity_events AS event ON event.id=outbox.activity_event_id WHERE event.subject_id='b1500000-0000-0000-0000-000000000001' AND event.event_type='task.comment_posted') <> 3
     OR EXISTS (SELECT 1 FROM public.activity_events WHERE subject_id='b1500000-0000-0000-0000-000000000001' AND event_type='task.comment_posted' AND (metadata->>'sequence' IS NULL OR metadata->>'mention_count' IS NULL)) THEN
    RAISE EXCEPTION 'Task comment Activity/outbox was not exactly-once or safely shaped';
  END IF;
END $comment_activity_audit$;

UPDATE public.tasks SET status='suspended',completed_at=NULL,completed_by=NULL WHERE id='b1500000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
DO $suspended_task$
DECLARE result record;
BEGIN
  IF EXISTS (SELECT 1 FROM public.get_task_comments('b1500000-0000-0000-0000-000000000001')) THEN RAISE EXCEPTION 'suspended Task still exposed comments'; END IF;
  SELECT * INTO result FROM public.post_task_comment('b1500000-0000-0000-0000-000000000001','suspended Task write','b1600000-0000-0000-0000-000000000013');
  IF result.code <> 'context_unavailable' THEN RAISE EXCEPTION 'suspended Task accepted a comment'; END IF;
END $suspended_task$;
RESET ROLE;
UPDATE public.tasks SET status='completed',completed_at=now(),completed_by='b1000000-0000-0000-0000-000000000001' WHERE id='b1500000-0000-0000-0000-000000000001';

UPDATE public.tasks SET lifecycle_state='archived' WHERE id='b1500000-0000-0000-0000-000000000001';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000003',true);
DO $viewer$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.post_task_comment('b1500000-0000-0000-0000-000000000001','Viewer write','b1600000-0000-0000-0000-000000000004');
  IF result.code <> 'not_allowed' THEN RAISE EXCEPTION 'Viewer wrote a Task comment'; END IF;
END $viewer$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','b1000000-0000-0000-0000-000000000001',true);
DO $tenant_and_lifecycle$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.post_task_comment('b1500000-0000-0000-0000-000000000002','foreign','b1600000-0000-0000-0000-000000000005');
  IF result.code <> 'not_found' THEN RAISE EXCEPTION 'tenant-forged Task identifier disclosed comment authority'; END IF;
  IF EXISTS (SELECT 1 FROM public.get_task_comments('b1500000-0000-0000-0000-000000000001')) THEN RAISE EXCEPTION 'unavailable Task still exposed comments'; END IF;
  SELECT * INTO result FROM public.post_task_comment('b1500000-0000-0000-0000-000000000001','archived','b1600000-0000-0000-0000-000000000006');
  IF result.code <> 'context_unavailable' THEN RAISE EXCEPTION 'unavailable Task accepted a comment'; END IF;
END $tenant_and_lifecycle$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $direct_bypass$ DECLARE blocked boolean := false; BEGIN
  BEGIN SELECT * FROM public.task_comments; EXCEPTION WHEN insufficient_privilege THEN blocked := true; END;
  IF NOT blocked OR has_function_privilege('service_role','public.post_task_comment(uuid,text,uuid,uuid,uuid[])','EXECUTE') OR has_function_privilege('service_role','public.get_task_comments(uuid,bigint,integer)','EXECUTE') THEN RAISE EXCEPTION 'service role bypassed private Task comment tables/RPC'; END IF;
END $direct_bypass$;
RESET ROLE;
ROLLBACK;
