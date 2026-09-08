-- Run after migration 00141. This transaction is always rolled back.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES
('00000000-0000-0000-0000-000000000000','e4100000-0000-0000-0000-000000000001','authenticated','authenticated','state-owner@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','e4100000-0000-0000-0000-000000000002','authenticated','authenticated','state-associate@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','e4100000-0000-0000-0000-000000000003','authenticated','authenticated','state-admin@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','e4100000-0000-0000-0000-000000000004','authenticated','authenticated','state-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','e4100000-0000-0000-0000-000000000005','authenticated','authenticated','state-suspended@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','e4100000-0000-0000-0000-000000000006','authenticated','authenticated','state-removed@test.invalid','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','e4100000-0000-0000-0000-000000000007','authenticated','authenticated','state-foreign@test.invalid','x',now(),'{}','{}',now(),now());

INSERT INTO public.organisations(id,name,created_by) VALUES
('e4110000-0000-0000-0000-000000000001','Matter state organisation','e4100000-0000-0000-0000-000000000001'),
('e4110000-0000-0000-0000-000000000002','Foreign state organisation','e4100000-0000-0000-0000-000000000007');
INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at,suspended_at,suspended_by,suspension_reason,removed_at,removed_by,removal_reason)
VALUES
('e4120000-0000-0000-0000-000000000002','e4110000-0000-0000-0000-000000000001','e4100000-0000-0000-0000-000000000002','associate','active',1,now(),NULL,NULL,NULL,NULL,NULL,NULL),
('e4120000-0000-0000-0000-000000000003','e4110000-0000-0000-0000-000000000001','e4100000-0000-0000-0000-000000000003','admin','active',1,now(),NULL,NULL,NULL,NULL,NULL,NULL),
('e4120000-0000-0000-0000-000000000004','e4110000-0000-0000-0000-000000000001','e4100000-0000-0000-0000-000000000004','viewer','active',1,now(),NULL,NULL,NULL,NULL,NULL,NULL),
('e4120000-0000-0000-0000-000000000005','e4110000-0000-0000-0000-000000000001','e4100000-0000-0000-0000-000000000005','associate','suspended',1,now(),now(),'e4100000-0000-0000-0000-000000000001','fixture',NULL,NULL,NULL),
('e4120000-0000-0000-0000-000000000006','e4110000-0000-0000-0000-000000000001','e4100000-0000-0000-0000-000000000006','associate','removed',1,now(),NULL,NULL,NULL,now(),'e4100000-0000-0000-0000-000000000001','fixture');
UPDATE public.organisations AS organisation SET owner_membership_id=membership.id
FROM public.organisation_memberships AS membership
WHERE organisation.id=membership.org_id AND membership.user_id=organisation.created_by;

INSERT INTO public.clients(id,org_id,name) VALUES
('e4130000-0000-0000-0000-000000000001','e4110000-0000-0000-0000-000000000001','State client'),
('e4130000-0000-0000-0000-000000000002','e4110000-0000-0000-0000-000000000002','Foreign state client'),
('e4130000-0000-0000-0000-000000000003','e4110000-0000-0000-0000-000000000001','Inactive state client'),
('e4130000-0000-0000-0000-000000000004','e4110000-0000-0000-0000-000000000001','Mapping client');
UPDATE public.clients SET record_state='trashed',deleted_at=now()
WHERE id='e4130000-0000-0000-0000-000000000003';

-- Every legacy value, defaults, and closed ambiguity use no document evidence.
INSERT INTO public.matters(id,org_id,client_id,title,financial_year,status) VALUES
('e4140000-0000-0000-0000-000000000001','e4110000-0000-0000-0000-000000000001','e4130000-0000-0000-0000-000000000004','Map active','2010-11','active'),
('e4140000-0000-0000-0000-000000000002','e4110000-0000-0000-0000-000000000001','e4130000-0000-0000-0000-000000000004','Map stayed','2011-12','stayed'),
('e4140000-0000-0000-0000-000000000003','e4110000-0000-0000-0000-000000000001','e4130000-0000-0000-0000-000000000004','Map disposed','2012-13','disposed'),
('e4140000-0000-0000-0000-000000000004','e4110000-0000-0000-0000-000000000001','e4130000-0000-0000-0000-000000000004','Map appeal','2013-14','appeal_pending'),
('e4140000-0000-0000-0000-000000000005','e4110000-0000-0000-0000-000000000001','e4130000-0000-0000-0000-000000000004','Map tribunal','2014-15','tribunal'),
('e4140000-0000-0000-0000-000000000006','e4110000-0000-0000-0000-000000000001','e4130000-0000-0000-0000-000000000004','Map high court','2015-16','high_court'),
('e4140000-0000-0000-0000-000000000007','e4110000-0000-0000-0000-000000000001','e4130000-0000-0000-0000-000000000004','Map supreme court','2016-17','supreme_court'),
('e4140000-0000-0000-0000-000000000008','e4110000-0000-0000-0000-000000000001','e4130000-0000-0000-0000-000000000004','Map ambiguous closed','2017-18','closed'),
('e4140000-0000-0000-0000-000000000009','e4110000-0000-0000-0000-000000000001','e4130000-0000-0000-0000-000000000004','Map defaults','2018-19',DEFAULT);

DO $mapping$
DECLARE actual text[];
BEGIN
  SELECT array_agg(work_state::text||'/'||current_forum::text ORDER BY id) INTO actual
  FROM public.matters WHERE id BETWEEN 'e4140000-0000-0000-0000-000000000001' AND 'e4140000-0000-0000-0000-000000000009';
  IF actual IS DISTINCT FROM ARRAY[
    'active/adjudication','stayed/adjudication','disposed/adjudication','active/first_appeal',
    'active/tribunal','active/high_court','active/supreme_court','closed/other','active/adjudication'
  ] THEN RAISE EXCEPTION 'legacy/default mapping mismatch: %',actual; END IF;
  IF public.matter_legacy_status('active','remand')<>'active'
     OR public.matter_legacy_status('active','other')<>'active'
     OR public.matter_legacy_status('closed','supreme_court')<>'closed' THEN
    RAISE EXCEPTION 'legacy compatibility mapping mismatch';
  END IF;
END $mapping$;

INSERT INTO public.matters(id,org_id,client_id,title,financial_year,description) VALUES
('e4140000-0000-0000-0000-000000000020','e4110000-0000-0000-0000-000000000001','e4130000-0000-0000-0000-000000000001','Governed matter','2024-25','Original synopsis'),
('e4140000-0000-0000-0000-000000000021','e4110000-0000-0000-0000-000000000002','e4130000-0000-0000-0000-000000000002','Foreign matter','2024-25','Foreign'),
('e4140000-0000-0000-0000-000000000022','e4110000-0000-0000-0000-000000000001','e4130000-0000-0000-0000-000000000001','Unavailable matter','2023-24','Unavailable'),
('e4140000-0000-0000-0000-000000000023','e4110000-0000-0000-0000-000000000001','e4130000-0000-0000-0000-000000000003','Unavailable parent matter','2024-25','Original unavailable-parent synopsis');
UPDATE public.matters SET deleted_at=now() WHERE id='e4140000-0000-0000-0000-000000000022';

INSERT INTO public.documents(id,org_id,matter_id,display_title,financial_year,raw_metadata,storage_path) VALUES
('e4150000-0000-0000-0000-000000000001','e4110000-0000-0000-0000-000000000001','e4140000-0000-0000-0000-000000000020','Evidence one','2024-25','{"tax_amount":12500}','fixture/evidence-one.pdf'),
('e4150000-0000-0000-0000-000000000002','e4110000-0000-0000-0000-000000000001','e4140000-0000-0000-0000-000000000020','Evidence two','2024-25','{"interest_amount":300}','fixture/evidence-two.pdf');
INSERT INTO public.document_links(id,from_doc_id,to_doc_id,link_type,status)
VALUES('e4160000-0000-0000-0000-000000000001','e4150000-0000-0000-0000-000000000001','e4150000-0000-0000-0000-000000000002','responds_to','confirmed');
INSERT INTO public.deadlines(id,matter_id,document_id,type,due_date,description)
VALUES('e4170000-0000-0000-0000-000000000001','e4140000-0000-0000-0000-000000000020','e4150000-0000-0000-0000-000000000001','reply_deadline','2030-01-01','Preserve deadline');

DO $privileges$
BEGIN
  IF has_table_privilege('authenticated','public.matters','UPDATE')
     OR has_table_privilege('service_role','public.matters','UPDATE')
     OR has_table_privilege('authenticated','public.matter_status_normalization_report','SELECT')
     OR has_function_privilege('service_role','public.update_matter_command(uuid,bigint,text,text,public.matter_work_state,public.matter_current_forum,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'direct Matter/report/service authority survived';
  END IF;
END $privileges$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','e4100000-0000-0000-0000-000000000002',true);
DO $associate$
DECLARE result record; replay record; stale record; created record;
BEGIN
  SELECT * INTO result FROM public.update_matter_command('e4140000-0000-0000-0000-000000000020',1,'Associate title','Associate synopsis','stayed'::public.matter_work_state,'tribunal'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000001');
  IF result.code<>'ok' OR result.revision<>2 OR result.replayed THEN RAISE EXCEPTION 'Associate ordinary edit failed'; END IF;
  SELECT * INTO replay FROM public.update_matter_command('e4140000-0000-0000-0000-000000000020',1,'Associate title','Associate synopsis','stayed'::public.matter_work_state,'tribunal'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000001');
  IF replay.code<>'ok' OR replay.revision<>2 OR NOT replay.replayed THEN RAISE EXCEPTION 'typed replay failed'; END IF;
  SELECT * INTO stale FROM public.update_matter_command('e4140000-0000-0000-0000-000000000020',1,'Stale title','Stale','active'::public.matter_work_state,'adjudication'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000002');
  IF stale.code<>'conflict' OR stale.revision<>2 THEN RAISE EXCEPTION 'stale revision accepted'; END IF;
  SELECT * INTO stale FROM public.update_matter_command('e4140000-0000-0000-0000-000000000020',2,'Changed replay','Associate synopsis','stayed'::public.matter_work_state,'tribunal'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000001');
  IF stale.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'changed replay accepted'; END IF;
  SELECT * INTO stale FROM public.update_matter_command('e4140000-0000-0000-0000-000000000020',2,'Associate title','Associate synopsis','closed'::public.matter_work_state,'tribunal'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000003');
  IF stale.code<>'not_allowed' THEN RAISE EXCEPTION 'Associate closed Matter'; END IF;
  SELECT * INTO stale FROM public.update_matter_command('e4140000-0000-0000-0000-000000000022',1,'Unavailable','Unavailable','active'::public.matter_work_state,'adjudication'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000004');
  IF stale.code<>'context_unavailable' THEN RAISE EXCEPTION 'trashed Matter accepted edit'; END IF;
  SELECT * INTO stale FROM public.update_matter_command('e4140000-0000-0000-0000-000000000023',1,'Parent bypass','Mutated','stayed'::public.matter_work_state,'tribunal'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000016');
  IF stale.code<>'context_unavailable' OR stale.matter_id IS NOT NULL OR stale.client_id IS NOT NULL OR stale.revision IS NOT NULL THEN RAISE EXCEPTION 'Matter with unavailable parent Client accepted or disclosed update'; END IF;
  SELECT * INTO created FROM public.create_matter_command('e4130000-0000-0000-0000-000000000001','Typed created matter','2025-26','Created synopsis','active'::public.matter_work_state,'first_appeal'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000012');
  IF created.code<>'ok' OR created.revision<>1 OR created.replayed THEN RAISE EXCEPTION 'Associate typed create failed'; END IF;
  SELECT * INTO replay FROM public.create_matter_command('e4130000-0000-0000-0000-000000000001','Typed created matter','2025-26','Created synopsis','active'::public.matter_work_state,'first_appeal'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000012');
  IF replay.code<>'ok' OR replay.matter_id<>created.matter_id OR NOT replay.replayed THEN RAISE EXCEPTION 'typed create replay failed'; END IF;
  SELECT * INTO stale FROM public.create_matter_command('e4130000-0000-0000-0000-000000000001','Closed create denied','2025-26','Denied','closed'::public.matter_work_state,'other'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000013');
  IF stale.code<>'not_allowed' THEN RAISE EXCEPTION 'Associate created closed Matter'; END IF;
  SELECT * INTO stale FROM public.create_matter_command('e4130000-0000-0000-0000-000000000002','Foreign create denied','2025-26','Denied','active'::public.matter_work_state,'adjudication'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000014');
  IF stale.code<>'context_unavailable' THEN RAISE EXCEPTION 'Associate created cross-tenant Matter'; END IF;
END $associate$;
RESET ROLE;

DO $preserved_after_state_forum$
BEGIN
  IF (SELECT client_id FROM public.matters WHERE id='e4140000-0000-0000-0000-000000000020')<>'e4130000-0000-0000-0000-000000000001'
     OR (SELECT financial_year FROM public.matters WHERE id='e4140000-0000-0000-0000-000000000020')<>'2024-25'
     OR (SELECT count(*) FROM public.documents WHERE matter_id='e4140000-0000-0000-0000-000000000020' AND financial_year='2024-25' AND raw_metadata IN ('{"tax_amount":12500}','{"interest_amount":300}'))<>2
     OR (SELECT count(*) FROM public.document_links WHERE id='e4160000-0000-0000-0000-000000000001')<>1
     OR (SELECT count(*) FROM public.deadlines WHERE id='e4170000-0000-0000-0000-000000000001' AND due_date='2030-01-01')<>1 THEN
    RAISE EXCEPTION 'state/forum edit altered identity, document metadata, relationship, deadline, or financial fact';
  END IF;
  IF (SELECT count(*) FROM public.activity_events WHERE idempotency_key LIKE 'matter.%.e4180000-0000-0000-0000-000000000001')<>3
     OR (SELECT count(*) FROM public.activity_projector_outbox_events o JOIN public.activity_events e ON e.id=o.activity_event_id WHERE e.idempotency_key LIKE 'matter.%.e4180000-0000-0000-0000-000000000001')<>3 THEN
    RAISE EXCEPTION 'canonical Activity/outbox was missing or duplicated';
  END IF;
  IF (SELECT count(*) FROM public.activity_events WHERE idempotency_key='matter.create.e4180000-0000-0000-0000-000000000012')<>1
     OR (SELECT count(*) FROM public.activity_projector_outbox_events o JOIN public.activity_events e ON e.id=o.activity_event_id WHERE e.idempotency_key='matter.create.e4180000-0000-0000-0000-000000000012')<>1 THEN
    RAISE EXCEPTION 'typed create Activity/outbox was missing or duplicated';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.matter_command_receipts receipt
    JOIN public.matters matter ON matter.id=receipt.matter_id AND matter.org_id=receipt.org_id
    WHERE receipt.idempotency_key='e4180000-0000-0000-0000-000000000012'
      AND matter.work_state='active' AND matter.current_forum='first_appeal' AND matter.status='appeal_pending'
  ) THEN RAISE EXCEPTION 'typed create compatibility status mismatch'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.matters
    WHERE id='e4140000-0000-0000-0000-000000000023'
      AND title='Unavailable parent matter' AND description='Original unavailable-parent synopsis'
      AND revision=1 AND work_state='active' AND current_forum='adjudication' AND status='active'
  ) OR EXISTS(
    SELECT 1 FROM public.matter_command_receipts
    WHERE idempotency_key='e4180000-0000-0000-0000-000000000016'
  ) THEN RAISE EXCEPTION 'unavailable parent denial mutated Matter state or wrote a receipt'; END IF;
END $preserved_after_state_forum$;

SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','e4100000-0000-0000-0000-000000000003',true);
DO $admin_close$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.update_matter_command('e4140000-0000-0000-0000-000000000020',2,'Associate title','Associate synopsis','closed'::public.matter_work_state,'tribunal'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000005');
  IF result.code<>'ok' OR result.revision<>3 THEN RAISE EXCEPTION 'Admin close failed'; END IF;
END $admin_close$;
RESET ROLE;

SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','e4100000-0000-0000-0000-000000000001',true);
DO $owner_reopen$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.update_matter_command('e4140000-0000-0000-0000-000000000020',3,'Associate title','Associate synopsis','active'::public.matter_work_state,'remand'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000006');
  IF result.code<>'ok' OR result.revision<>4 THEN RAISE EXCEPTION 'Owner reopen failed'; END IF;
END $owner_reopen$;
RESET ROLE;

SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','e4100000-0000-0000-0000-000000000002',true);
DO $legacy_wrapper$ DECLARE result record; replay record; BEGIN
  SELECT * INTO result FROM public.update_matter_command('e4140000-0000-0000-0000-000000000001',1,'Legacy wrapper title','1900-01','Legacy wrapper synopsis','supreme_court'::public.matter_status,'e4180000-0000-0000-0000-000000000015');
  IF result.code<>'ok' OR result.revision<>2 THEN RAISE EXCEPTION 'legacy wrapper failed'; END IF;
  SELECT * INTO replay FROM public.update_matter_command('e4140000-0000-0000-0000-000000000001',1,'Legacy wrapper title','Legacy wrapper synopsis','active'::public.matter_work_state,'supreme_court'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000015');
  IF replay.code<>'ok' OR replay.revision<>2 OR NOT replay.replayed THEN RAISE EXCEPTION 'legacy-to-typed replay mismatch'; END IF;
END $legacy_wrapper$;
RESET ROLE;
DO $legacy_wrapper_preserved$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.matters WHERE id='e4140000-0000-0000-0000-000000000001' AND financial_year='2010-11' AND work_state='active' AND current_forum='supreme_court' AND status='supreme_court') THEN RAISE EXCEPTION 'legacy wrapper compatibility mismatch'; END IF;
END $legacy_wrapper_preserved$;

SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','e4100000-0000-0000-0000-000000000004',true);
DO $viewer$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.update_matter_command('e4140000-0000-0000-0000-000000000020',4,'Viewer edit','No','active'::public.matter_work_state,'remand'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000007');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'Viewer edited Matter'; END IF;
  BEGIN UPDATE public.matters SET title='Direct viewer edit' WHERE id='e4140000-0000-0000-0000-000000000020'; RAISE EXCEPTION 'direct table write succeeded'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $viewer$;
RESET ROLE;

SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','e4100000-0000-0000-0000-000000000005',true);
DO $suspended$ DECLARE result record; BEGIN SELECT * INTO result FROM public.update_matter_command('e4140000-0000-0000-0000-000000000020',4,'Suspended','No','active'::public.matter_work_state,'remand'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000008'); IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'suspended member edited'; END IF; END $suspended$;
RESET ROLE;
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','e4100000-0000-0000-0000-000000000006',true);
DO $removed$ DECLARE result record; BEGIN SELECT * INTO result FROM public.update_matter_command('e4140000-0000-0000-0000-000000000020',4,'Removed','No','active'::public.matter_work_state,'remand'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000009'); IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'removed member edited'; END IF; END $removed$;
RESET ROLE;
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','e4100000-0000-0000-0000-000000000007',true);
DO $foreign$ DECLARE result record; BEGIN SELECT * INTO result FROM public.update_matter_command('e4140000-0000-0000-0000-000000000020',4,'Foreign','No','active'::public.matter_work_state,'remand'::public.matter_current_forum,'e4180000-0000-0000-0000-000000000010'); IF result.code<>'context_unavailable' OR result.matter_id IS NOT NULL THEN RAISE EXCEPTION 'cross-tenant lineage leaked'; END IF; END $foreign$;
RESET ROLE;

-- Trash preserves typed procedural state and the exact projection exposes it.
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','e4100000-0000-0000-0000-000000000001',true);
DO $trash_projection$ DECLARE trashed record; projection record; BEGIN
  SELECT * INTO trashed FROM public.trash_resource('matter','e4140000-0000-0000-0000-000000000005','e4180000-0000-0000-0000-000000000011');
  IF trashed.code<>'trashed' THEN RAISE EXCEPTION 'fixture Matter trash failed: %',trashed.code; END IF;
  SELECT * INTO projection FROM public.get_exact_trashed_resource_projection('matter','e4140000-0000-0000-0000-000000000005',NULL);
  IF projection.resource_record->>'work_state'<>'active' OR projection.resource_record->>'current_forum'<>'tribunal' THEN RAISE EXCEPTION 'typed Trash projection mismatch'; END IF;
END $trash_projection$;
RESET ROLE;

ROLLBACK;
