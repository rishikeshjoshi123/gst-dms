-- Run after `npx supabase db reset --local --no-seed` on a disposable database.
BEGIN;

DO $fixture$
DECLARE
  owner_a uuid := '11000000-0000-0000-0000-000000000001';
  associate_a uuid := '11000000-0000-0000-0000-000000000002';
  owner_b uuid := '11000000-0000-0000-0000-000000000003';
  former_assignee uuid := '11000000-0000-0000-0000-000000000004';
  org_a uuid := '11100000-0000-0000-0000-000000000001';
  org_b uuid := '11100000-0000-0000-0000-000000000002';
  client_a uuid := '11200000-0000-0000-0000-000000000001';
  client_b uuid := '11200000-0000-0000-0000-000000000002';
  client_a_other uuid := '11200000-0000-0000-0000-000000000003';
  matter_a uuid := '11300000-0000-0000-0000-000000000001';
  matter_b uuid := '11300000-0000-0000-0000-000000000002';
  matter_trashed uuid := '11300000-0000-0000-0000-000000000003';
  matter_document uuid := '11300000-0000-0000-0000-000000000004';
  document_trashed uuid := '11400000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES
    ('00000000-0000-0000-0000-000000000000',owner_a,'authenticated','authenticated','legacy-backfill-owner-a@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',associate_a,'authenticated','authenticated','legacy-backfill-associate-a@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',owner_b,'authenticated','authenticated','legacy-backfill-owner-b@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',former_assignee,'authenticated','authenticated','legacy-backfill-former@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by)
  VALUES (org_a,'Legacy backfill A',owner_a),(org_b,'Legacy backfill B',owner_b);
  INSERT INTO public.org_members(org_id,user_id,role) VALUES (org_a,associate_a,'associate');
  INSERT INTO public.clients(id,org_id,name)
  VALUES
    (client_a,org_a,'Legacy client A'),
    (client_b,org_b,'Legacy client B'),
    (client_a_other,org_a,'Legacy client A other');
  INSERT INTO public.matters(id,org_id,client_id,title,financial_year)
  VALUES
    (matter_a,org_a,client_a,'Legacy matter A','2026-27'),
    (matter_b,org_b,client_b,'Legacy matter B','2026-27'),
    (matter_trashed,org_a,client_a,'Legacy trashed matter','2027-28'),
    (matter_document,org_a,client_a,'Legacy document matter','2028-29');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by)
  VALUES (document_trashed,org_a,matter_document,'fixture/legacy-backfill.pdf',owner_a);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',owner_a::text,true);
  PERFORM public.trash_resource('matter',matter_trashed,'legacy-backfill-trashed-matter');
  PERFORM public.trash_resource('document',document_trashed,'legacy-backfill-trashed-document');

  INSERT INTO public.case_notes(
    id,org_id,author_id,matter_id,document_id,content,template_type,
    is_action_item,action_item_assignee,action_item_due_date,action_item_resolved,deleted_at
  ) VALUES
    ('11500000-0000-0000-0000-000000000001',org_a,owner_a,matter_a,NULL,'Open legacy action','general',true,associate_a,DATE '2026-10-03',false,NULL),
    ('11500000-0000-0000-0000-000000000002',org_a,owner_a,matter_a,NULL,'Resolved legacy action','general',true,NULL,DATE '2026-10-04',true,NULL),
    ('11500000-0000-0000-0000-000000000003',org_a,owner_a,matter_a,NULL,'Deleted legacy action','general',true,NULL,NULL,false,now()),
    ('11500000-0000-0000-0000-000000000004',org_a,owner_a,matter_trashed,NULL,'Trashed matter legacy action','general',true,NULL,NULL,false,NULL),
    ('11500000-0000-0000-0000-000000000005',org_a,owner_a,matter_document,document_trashed,'Trashed document legacy action','general',true,NULL,NULL,false,NULL),
    ('11500000-0000-0000-0000-000000000006',org_a,owner_a,matter_a,NULL,'Former assignee legacy action','general',true,former_assignee,NULL,false,NULL),
    ('11500000-0000-0000-0000-000000000007',org_a,owner_a,matter_a,NULL,'Existing Task legacy action','general',true,NULL,NULL,false,NULL),
    ('11500000-0000-0000-0000-000000000008',org_a,owner_a,matter_a,NULL,'Cross-tenant Task legacy action','general',true,NULL,NULL,false,NULL),
    ('11500000-0000-0000-0000-000000000009',org_a,owner_a,matter_a,NULL,'   ','general',true,NULL,NULL,false,NULL),
    ('11500000-0000-0000-0000-000000000010',org_a,owner_a,matter_a,NULL,'Wrong client Task legacy action','general',true,NULL,NULL,false,NULL);

  INSERT INTO public.tasks(
    org_id,client_id,matter_id,title,origin_kind,origin_note_id,origin_snapshot,
    creator_user_id,status,status_changed_by
  ) VALUES
    (org_a,client_a,matter_a,'Existing Task legacy action','case_note',
      '11500000-0000-0000-0000-000000000007','Existing Task legacy action',owner_a,'open',owner_a),
    (org_b,client_b,matter_b,'Cross-tenant Task legacy action','case_note',
      '11500000-0000-0000-0000-000000000008','Cross-tenant Task legacy action',owner_b,'open',owner_b),
    (org_a,client_a_other,matter_a,'Wrong client Task legacy action','case_note',
      '11500000-0000-0000-0000-000000000010','Wrong client Task legacy action',owner_a,'open',owner_a);
END $fixture$;

DO $browser_denial$
DECLARE blocked boolean := false;
BEGIN
  IF has_function_privilege('authenticated','public.backfill_legacy_note_action_items(uuid,integer)','EXECUTE')
     OR has_table_privilege('authenticated','public.task_legacy_note_backfill_diagnostics','SELECT')
     OR has_table_privilege('service_role','public.tasks','INSERT') THEN
    RAISE EXCEPTION 'legacy backfill grant surface is unsafe';
  END IF;
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub','11000000-0000-0000-0000-000000000001',true);
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.backfill_legacy_note_action_items('11100000-0000-0000-0000-000000000001',250);
  EXCEPTION WHEN insufficient_privilege THEN blocked := true;
  END;
  RESET ROLE;
  IF NOT blocked THEN RAISE EXCEPTION 'authenticated caller invoked service-only legacy backfill'; END IF;
END $browser_denial$;

SET LOCAL ROLE service_role;
SELECT * FROM public.backfill_legacy_note_action_items('11100000-0000-0000-0000-000000000001',250);
RESET ROLE;

DO $results$
DECLARE result_count bigint;
BEGIN
  IF (SELECT count(*) FROM public.task_legacy_note_backfill_diagnostics
      WHERE source_org_id='11100000-0000-0000-0000-000000000001') <> 10 THEN
    RAISE EXCEPTION 'legacy action items did not receive explicit dispositions';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.task_legacy_note_backfill_diagnostics WHERE source_note_id='11500000-0000-0000-0000-000000000001' AND disposition='migrated')
     OR NOT EXISTS (SELECT 1 FROM public.task_legacy_note_backfill_diagnostics WHERE source_note_id='11500000-0000-0000-0000-000000000002' AND disposition='migrated')
     OR NOT EXISTS (SELECT 1 FROM public.task_legacy_note_backfill_diagnostics WHERE source_note_id='11500000-0000-0000-0000-000000000003' AND disposition='deleted_note')
     OR NOT EXISTS (SELECT 1 FROM public.task_legacy_note_backfill_diagnostics WHERE source_note_id='11500000-0000-0000-0000-000000000004' AND disposition='matter_context_unavailable')
     OR NOT EXISTS (SELECT 1 FROM public.task_legacy_note_backfill_diagnostics WHERE source_note_id='11500000-0000-0000-0000-000000000005' AND disposition='document_context_unavailable')
     OR NOT EXISTS (SELECT 1 FROM public.task_legacy_note_backfill_diagnostics WHERE source_note_id='11500000-0000-0000-0000-000000000006' AND disposition='invalid_assignee')
     OR NOT EXISTS (SELECT 1 FROM public.task_legacy_note_backfill_diagnostics WHERE source_note_id='11500000-0000-0000-0000-000000000007' AND disposition='existing_task')
     OR NOT EXISTS (SELECT 1 FROM public.task_legacy_note_backfill_diagnostics WHERE source_note_id='11500000-0000-0000-0000-000000000008' AND disposition='existing_task_lineage_conflict')
     OR NOT EXISTS (SELECT 1 FROM public.task_legacy_note_backfill_diagnostics WHERE source_note_id='11500000-0000-0000-0000-000000000009' AND disposition='invalid_origin_snapshot')
     OR NOT EXISTS (SELECT 1 FROM public.task_legacy_note_backfill_diagnostics WHERE source_note_id='11500000-0000-0000-0000-000000000010' AND disposition='existing_task_lineage_conflict') THEN
    RAISE EXCEPTION 'legacy action-item dispositions are incomplete or unsafe';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE origin_note_id='11500000-0000-0000-0000-000000000001'
      AND assignee_user_id='11000000-0000-0000-0000-000000000002'
      AND due_date=DATE '2026-10-03' AND due_time IS NULL
      AND due_timezone='Asia/Kolkata' AND status='open'
      AND origin_snapshot='Open legacy action'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.tasks
    WHERE origin_note_id='11500000-0000-0000-0000-000000000002'
      AND status='completed' AND completed_at IS NOT NULL AND completed_by='11000000-0000-0000-0000-000000000001'
  ) THEN
    RAISE EXCEPTION 'eligible legacy state was not mapped to canonical Task state';
  END IF;
  IF (SELECT count(*) FROM public.activity_events WHERE org_id='11100000-0000-0000-0000-000000000001'
      AND event_type='task.created' AND actor_kind='system' AND subject_type='task'
      AND subject_id IN (SELECT task_id FROM public.task_legacy_note_backfill_diagnostics WHERE source_org_id='11100000-0000-0000-0000-000000000001' AND disposition='migrated')) <> 2
     OR (SELECT count(*) FROM public.activity_projector_outbox_events AS outbox
         JOIN public.activity_events AS event ON event.id=outbox.activity_event_id
         WHERE event.org_id='11100000-0000-0000-0000-000000000001'
           AND outbox.org_id='11100000-0000-0000-0000-000000000001'
           AND event.event_type='task.created' AND event.actor_kind='system'
           AND event.subject_id IN (SELECT task_id FROM public.task_legacy_note_backfill_diagnostics WHERE source_org_id='11100000-0000-0000-0000-000000000001' AND disposition='migrated')) <> 2 THEN
    RAISE EXCEPTION 'migrated Tasks did not receive one system-owned Activity/outbox pair';
  END IF;
  SELECT count(*) INTO result_count FROM public.backfill_legacy_note_action_items('11100000-0000-0000-0000-000000000001',250);
  IF result_count <> 0 OR (SELECT count(*) FROM public.tasks WHERE origin_note_id IN (
      '11500000-0000-0000-0000-000000000001','11500000-0000-0000-0000-000000000002'
    )) <> 2 THEN
    RAISE EXCEPTION 'legacy backfill replay was not idempotent';
  END IF;
  UPDATE public.case_notes SET content='Edited legacy origin' WHERE id='11500000-0000-0000-0000-000000000001';
  IF (SELECT origin_snapshot FROM public.tasks WHERE origin_note_id='11500000-0000-0000-0000-000000000001') <> 'Open legacy action' THEN
    RAISE EXCEPTION 'legacy note edit overwrote immutable Task origin snapshot';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.task_legacy_note_backfill_reports
    WHERE org_id='11100000-0000-0000-0000-000000000001'
      AND source_count=10 AND disposed_count=10 AND pending_count=0
      AND migrated_count=2 AND existing_task_count=1 AND excluded_count=7
  ) THEN
    RAISE EXCEPTION 'legacy backfill aggregate report is inaccurate';
  END IF;
END $results$;

ROLLBACK;
