\set ON_ERROR_STOP on
INSERT INTO public.tasks(id,org_id,client_id,matter_id,title,origin_kind,origin_note_id,origin_snapshot,
  creator_user_id,assignee_user_id,status,priority,lifecycle_state,status_changed_by)
VALUES('16100000-0000-4000-8000-000000000021','b0010000-0000-0000-0000-000000000001','c0010000-0000-0000-0000-000000000001','d0010000-0000-0000-0000-000000000001',
  'Concurrent suspension task','case_note','16110000-0000-4000-8000-000000000021','Concurrent suspension task',
  'a0010000-0000-0000-0000-000000000001','a0010000-0000-0000-0000-000000000006','open','normal','active','a0010000-0000-0000-0000-000000000001');

INSERT INTO public.tasks(id,org_id,client_id,matter_id,title,origin_kind,origin_note_id,origin_snapshot,
  creator_user_id,assignee_user_id,status,priority,lifecycle_state,status_changed_by)
VALUES('16100000-0000-4000-8000-000000000022','b0010000-0000-0000-0000-000000000001','c0010000-0000-0000-0000-000000000001','d0010000-0000-0000-0000-000000000001',
  'Inverse assignment task','case_note','16110000-0000-4000-8000-000000000022','Inverse assignment task',
  'a0010000-0000-0000-0000-000000000001',NULL,'open','normal','active','a0010000-0000-0000-0000-000000000001');
