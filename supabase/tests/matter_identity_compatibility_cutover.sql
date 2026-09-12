-- Run after migration 00148. Rollback-only coverage for the Matter identity
-- compatibility cutover, governed commands, Restore, and effective FY facts.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
  ('00000000-0000-0000-0000-000000000000','a1480000-0000-0000-0000-000000000001','authenticated','authenticated','owner@matter-cutover.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1480000-0000-0000-0000-000000000002','authenticated','authenticated','admin@matter-cutover.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1480000-0000-0000-0000-000000000003','authenticated','authenticated','associate@matter-cutover.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1480000-0000-0000-0000-000000000004','authenticated','authenticated','viewer@matter-cutover.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1480000-0000-0000-0000-000000000005','authenticated','authenticated','suspended@matter-cutover.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1480000-0000-0000-0000-000000000006','authenticated','authenticated','foreign@matter-cutover.test','x',now(),'{}','{}',now(),now());

INSERT INTO public.organisations(id,name,created_by) VALUES
  ('b1480000-0000-0000-0000-000000000001','Matter identity cutover','a1480000-0000-0000-0000-000000000001'),
  ('b1480000-0000-0000-0000-000000000002','Foreign Matter identity cutover','a1480000-0000-0000-0000-000000000006');
INSERT INTO public.org_members(org_id,user_id,role) VALUES
  ('b1480000-0000-0000-0000-000000000001','a1480000-0000-0000-0000-000000000002','admin'),
  ('b1480000-0000-0000-0000-000000000001','a1480000-0000-0000-0000-000000000003','associate'),
  ('b1480000-0000-0000-0000-000000000001','a1480000-0000-0000-0000-000000000004','viewer'),
  ('b1480000-0000-0000-0000-000000000001','a1480000-0000-0000-0000-000000000005','associate');
UPDATE public.organisation_memberships
SET state='suspended',suspended_at=now(),suspended_by='a1480000-0000-0000-0000-000000000001',suspension_reason='fixture'
WHERE org_id='b1480000-0000-0000-0000-000000000001'
  AND user_id='a1480000-0000-0000-0000-000000000005';

INSERT INTO public.clients(id,org_id,name) VALUES
  ('c1480000-0000-0000-0000-000000000001','b1480000-0000-0000-0000-000000000001','Compatibility Client'),
  ('c1480000-0000-0000-0000-000000000002','b1480000-0000-0000-0000-000000000002','Foreign Compatibility Client');

-- Deliberately leave suffix 02 unused and hold suffix 03 through Trash. The
-- first governed allocation must be 04, never COUNT(*)+1 and never gap reuse.
INSERT INTO public.matters(id,org_id,client_id,title,financial_year,matter_code) VALUES
  ('d1480000-0000-0000-0000-000000000001','b1480000-0000-0000-0000-000000000001','c1480000-0000-0000-0000-000000000001','First same-year proceeding','2026-27','CMP-2627-01'),
  ('d1480000-0000-0000-0000-000000000003','b1480000-0000-0000-0000-000000000001','c1480000-0000-0000-0000-000000000001','Restorable same-year proceeding','2026-27','CMP-2627-03'),
  ('d1480000-0000-0000-0000-000000000004','b1480000-0000-0000-0000-000000000002','c1480000-0000-0000-0000-000000000002','Foreign proceeding','2026-27','FRC-2627-01');

INSERT INTO public.documents(id,org_id,matter_id,storage_path,display_title,document_class,origin_kind,content_availability,status,created_by) VALUES
  ('e1480000-0000-0000-0000-000000000001','b1480000-0000-0000-0000-000000000001','d1480000-0000-0000-0000-000000000001','fixture/cutover-first.pdf','Multi-year source','proceeding','upload','source_attached','placed','a1480000-0000-0000-0000-000000000001'),
  ('e1480000-0000-0000-0000-000000000003','b1480000-0000-0000-0000-000000000001','d1480000-0000-0000-0000-000000000003','fixture/cutover-restorable.pdf','Restorable identifier source','proceeding','upload','source_attached','placed','a1480000-0000-0000-0000-000000000001');
INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by) VALUES
  ('f1480000-0000-0000-0000-000000000001','b1480000-0000-0000-0000-000000000001','documents','orgs/b1480000-0000-0000-0000-000000000001/assets/f1480000-0000-0000-0000-000000000001/original.pdf',repeat('8',64),100,'application/pdf','available',now(),2,'a1480000-0000-0000-0000-000000000001'),
  ('f1480000-0000-0000-0000-000000000003','b1480000-0000-0000-0000-000000000001','documents','orgs/b1480000-0000-0000-0000-000000000001/assets/f1480000-0000-0000-0000-000000000003/original.pdf',repeat('9',64),100,'application/pdf','available',now(),1,'a1480000-0000-0000-0000-000000000001');
INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by) VALUES
  ('01480000-0000-0000-0000-000000000001','b1480000-0000-0000-0000-000000000001','e1480000-0000-0000-0000-000000000001','f1480000-0000-0000-0000-000000000001',1,'cutover-first.pdf',2,'valid','current',now(),now(),'a1480000-0000-0000-0000-000000000001'),
  ('01480000-0000-0000-0000-000000000003','b1480000-0000-0000-0000-000000000001','e1480000-0000-0000-0000-000000000003','f1480000-0000-0000-0000-000000000003',1,'cutover-restorable.pdf',1,'valid','current',now(),now(),'a1480000-0000-0000-0000-000000000001');
UPDATE public.documents SET current_version_id=CASE id
  WHEN 'e1480000-0000-0000-0000-000000000001' THEN '01480000-0000-0000-0000-000000000001'::uuid
  ELSE '01480000-0000-0000-0000-000000000003'::uuid END
WHERE id IN ('e1480000-0000-0000-0000-000000000001','e1480000-0000-0000-0000-000000000003');

-- One source document in one ordinary Matter carries two independent current
-- effective FY facts. No magic Matter FY value represents that span.
INSERT INTO public.source_analysis_runs(
  id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,
  provider,model_identifier,model_config_version,prompt_version,schema_version,
  catalogue_version,normalizer_version,started_at,completed_at
) VALUES (
  '11480000-0000-0000-0000-000000000001','b1480000-0000-0000-0000-000000000001',
  'f1480000-0000-0000-0000-000000000001','cutover-fy-facts','cutover-fy-facts',
  'ai_extraction','validated','succeeded','fixture','fixture','fixture','fixture',
  'fixture','fixture','fixture',now(),now()
);
SELECT public.materialize_source_field_candidate(
  '11480000-0000-0000-0000-000000000001','fy.2023','document.financial_year',
  'code','"2023-24"'::jsonb,1,'FY 2023-24',NULL,0.99,'eligible',NULL
);
SELECT public.materialize_source_field_candidate(
  '11480000-0000-0000-0000-000000000001','fy.2024','document.financial_year',
  'code','"2024-25"'::jsonb,1,'FY 2024-25',NULL,0.99,'eligible',NULL
);
SELECT public.materialize_document_version_analysis(
  '01480000-0000-0000-0000-000000000001',
  '11480000-0000-0000-0000-000000000001','matter_identity_cutover_fixture',
  'a1480000-0000-0000-0000-000000000001'
);

DO $schema_and_source_contract$
DECLARE
  v_generator text := pg_get_functiondef('public.generate_matter_code()'::regprocedure);
  v_restore text := pg_get_functiondef('public.trash_restore_blocker(uuid,uuid)'::regprocedure);
BEGIN
  IF to_regclass('public.idx_matters_unique_client_fy') IS NOT NULL
     OR to_regclass('public.matters_active_client_financial_year_lookup_idx') IS NULL
     OR to_regclass('public.matters_org_matter_code_unique') IS NULL
     OR to_regclass('public.matter_identifiers_verified_identity_reservation') IS NULL
     OR position('pg_advisory_xact_lock' IN v_generator)=0
     OR position('max(substring' IN lower(v_generator))=0
     OR position('active.client_id=restoring.client_id' IN replace(v_restore,' ',''))>0
     OR position('matter_identifiers' IN v_restore)=0 THEN
    RAISE EXCEPTION 'Matter identity cutover source/index contract failed';
  END IF;
  IF (SELECT count(*) FROM public.matters
      WHERE org_id='b1480000-0000-0000-0000-000000000001'
        AND client_id='c1480000-0000-0000-0000-000000000001'
        AND financial_year='2026-27')<>2
     OR (SELECT array_agg(normalized_value #>> '{}' ORDER BY semantic_candidate_key)
         FROM public.document_effective_metadata
         WHERE document_id='e1480000-0000-0000-0000-000000000001'
           AND field_path='document.financial_year')
        IS DISTINCT FROM ARRAY['2023-24','2024-25']::text[]
     OR (SELECT financial_year FROM public.matters WHERE id='d1480000-0000-0000-0000-000000000001')
        IN ('Unknown FY','Multi-year','Multiple FY') THEN
    RAISE EXCEPTION 'same-client/year or multi-year effective-fact contract failed';
  END IF;
END $schema_and_source_contract$;

DO $code_uniqueness$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    INSERT INTO public.matters(org_id,client_id,title,financial_year,matter_code)
    VALUES('b1480000-0000-0000-0000-000000000001','c1480000-0000-0000-0000-000000000001','Duplicate code','2026-27','CMP-2627-03');
  EXCEPTION WHEN unique_violation THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'active/Trash Matter code reservation failed'; END IF;
END $code_uniqueness$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','a1480000-0000-0000-0000-000000000003',true);
DO $associate_commands$
DECLARE first_result record; second_result record; replay record; conflict record; updated record; stale record;
BEGIN
  SELECT * INTO first_result FROM public.create_matter_command(
    'c1480000-0000-0000-0000-000000000001','Sequential same-year A','2026-27','',
    'active'::public.matter_work_state,'adjudication'::public.matter_current_forum,
    '14800000-0000-0000-0000-000000000001');
  SELECT * INTO replay FROM public.create_matter_command(
    'c1480000-0000-0000-0000-000000000001','Sequential same-year A','2026-27','',
    'active'::public.matter_work_state,'adjudication'::public.matter_current_forum,
    '14800000-0000-0000-0000-000000000001');
  SELECT * INTO conflict FROM public.create_matter_command(
    'c1480000-0000-0000-0000-000000000001','Changed replay','2026-27','',
    'active'::public.matter_work_state,'adjudication'::public.matter_current_forum,
    '14800000-0000-0000-0000-000000000001');
  SELECT * INTO second_result FROM public.create_matter_command(
    'c1480000-0000-0000-0000-000000000001','Sequential same-year B','2026-27','',
    'active'::public.matter_work_state,'adjudication'::public.matter_current_forum,
    '14800000-0000-0000-0000-000000000002');
  IF first_result.code<>'ok' OR second_result.code<>'ok'
     OR first_result.matter_id=second_result.matter_id
     OR (SELECT matter_code FROM public.matters WHERE id=first_result.matter_id)<>'CMP-2627-04'
     OR (SELECT matter_code FROM public.matters WHERE id=second_result.matter_id)<>'CMP-2627-05'
     OR replay.code<>'ok' OR NOT replay.replayed OR replay.matter_id<>first_result.matter_id
     OR conflict.code<>'idempotency_conflict' THEN
    RAISE EXCEPTION 'sequential same-year allocation or replay failed';
  END IF;

  SELECT * INTO updated FROM public.update_matter_command(
    'd1480000-0000-0000-0000-000000000001',1,'First proceeding corrected','Corrected',
    'active'::public.matter_work_state,'adjudication'::public.matter_current_forum,
    '14800000-0000-0000-0000-000000000003');
  SELECT * INTO replay FROM public.update_matter_command(
    'd1480000-0000-0000-0000-000000000001',1,'First proceeding corrected','Corrected',
    'active'::public.matter_work_state,'adjudication'::public.matter_current_forum,
    '14800000-0000-0000-0000-000000000003');
  SELECT * INTO stale FROM public.update_matter_command(
    'd1480000-0000-0000-0000-000000000001',1,'Stale correction','Stale',
    'active'::public.matter_work_state,'adjudication'::public.matter_current_forum,
    '14800000-0000-0000-0000-000000000004');
  IF updated.code<>'ok' OR updated.revision<>2 OR replay.code<>'ok' OR NOT replay.replayed
     OR stale.code<>'conflict' OR stale.revision<>2 THEN
    RAISE EXCEPTION 'Matter CAS/replay contract failed';
  END IF;
END $associate_commands$;
RESET ROLE;

DO $associate_effects$
BEGIN
  IF (SELECT count(*) FROM public.matter_command_receipts
      WHERE actor_user_id='a1480000-0000-0000-0000-000000000003' AND command='create')<>2
     OR (SELECT count(*) FROM public.activity_logs
         WHERE user_id='a1480000-0000-0000-0000-000000000003' AND action='matter_created')<>2
     OR (SELECT count(*) FROM public.activity_events
         WHERE actor_id='a1480000-0000-0000-0000-000000000003'
           AND event_type='matter.profile_updated' AND summary='Matter created')<>2
     OR (SELECT count(*) FROM public.activity_projector_outbox_events AS outbox
         JOIN public.activity_events AS event ON event.id=outbox.activity_event_id
         WHERE event.actor_id='a1480000-0000-0000-0000-000000000003'
           AND event.event_type='matter.profile_updated' AND event.summary='Matter created')<>2
     OR (SELECT count(*) FROM public.matter_command_receipts
         WHERE idempotency_key='14800000-0000-0000-0000-000000000004')<>0 THEN
    RAISE EXCEPTION 'Matter create/CAS effects were missing, duplicated, or partial';
  END IF;
END $associate_effects$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1480000-0000-0000-0000-000000000001',true);
DO $owner_create$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.create_matter_command(
    'c1480000-0000-0000-0000-000000000001','Owner same-year','2026-27','',
    'active'::public.matter_work_state,'adjudication'::public.matter_current_forum,
    '14800000-0000-0000-0000-000000000011');
  IF result.code<>'ok' THEN RAISE EXCEPTION 'Owner same-year create failed: %',result.code; END IF;
END $owner_create$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1480000-0000-0000-0000-000000000002',true);
DO $admin_create$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.create_matter_command(
    'c1480000-0000-0000-0000-000000000001','Admin same-year','2026-27','',
    'active'::public.matter_work_state,'adjudication'::public.matter_current_forum,
    '14800000-0000-0000-0000-000000000012');
  IF result.code<>'ok' THEN RAISE EXCEPTION 'Admin same-year create failed: %',result.code; END IF;
END $admin_create$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1480000-0000-0000-0000-000000000004',true);
DO $viewer_denial$
DECLARE result record; denied boolean:=false;
BEGIN
  SELECT * INTO result FROM public.create_matter_command(
    'c1480000-0000-0000-0000-000000000001','Viewer denied','2026-27','',
    'active'::public.matter_work_state,'adjudication'::public.matter_current_forum,
    '14800000-0000-0000-0000-000000000013');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'Viewer created Matter'; END IF;
  BEGIN
    INSERT INTO public.matters(org_id,client_id,title,financial_year)
    VALUES('b1480000-0000-0000-0000-000000000001','c1480000-0000-0000-0000-000000000001','Direct viewer','2026-27');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'authenticated direct Matter DML succeeded'; END IF;
END $viewer_denial$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1480000-0000-0000-0000-000000000005',true);
DO $suspended_denial$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.create_matter_command(
    'c1480000-0000-0000-0000-000000000001','Suspended denied','2026-27','',
    'active'::public.matter_work_state,'adjudication'::public.matter_current_forum,
    '14800000-0000-0000-0000-000000000014');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'suspended member created Matter'; END IF;
END $suspended_denial$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1480000-0000-0000-0000-000000000003',true);
DO $cross_tenant_denial$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.create_matter_command(
    'c1480000-0000-0000-0000-000000000002','Foreign denied','2026-27','',
    'active'::public.matter_work_state,'adjudication'::public.matter_current_forum,
    '14800000-0000-0000-0000-000000000015');
  IF result.code<>'context_unavailable' OR result.matter_id IS NOT NULL THEN
    RAISE EXCEPTION 'foreign client was disclosed or accepted';
  END IF;
END $cross_tenant_denial$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $service_dml_denial$
DECLARE denied boolean:=false;
BEGIN
  BEGIN
    UPDATE public.matters SET title='Forged service update'
    WHERE id='d1480000-0000-0000-0000-000000000001';
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'service-role direct Matter DML succeeded'; END IF;
END $service_dml_denial$;
RESET ROLE;

-- A verified external key is held while its Matter is in Trash. A second
-- Matter cannot claim it, and the original Matter restores beside another
-- active same-client/year Matter without changing its code or reservation.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1480000-0000-0000-0000-000000000001',true);
DO $trash_restore_and_verified_key$
DECLARE activated record; collision record; trashed record; v_revision bigint;
BEGIN
  SELECT matter.revision INTO v_revision FROM public.matters AS matter
  WHERE matter.id='d1480000-0000-0000-0000-000000000003';
  SELECT * INTO activated FROM public.activate_matter_identifier(
    'd1480000-0000-0000-0000-000000000003',v_revision,'proceeding_case_id','self_identifier',
    'GST Portal','GST/148/2026','GST/148/2026',
    'e1480000-0000-0000-0000-000000000003','01480000-0000-0000-0000-000000000003',1,
    'Proceeding reference GST / 148 / 2026','[]',NULL,
    '14800000-0000-0000-0000-000000000021');
  IF activated.code<>'ok' THEN RAISE EXCEPTION 'verified-key setup failed: %',activated.code; END IF;

  SELECT * INTO trashed FROM public.trash_resource(
    'matter','d1480000-0000-0000-0000-000000000003','cutover.fixture.trash');
  IF trashed.code<>'trashed' THEN RAISE EXCEPTION 'Matter Trash setup failed: %',trashed.code; END IF;

  SELECT matter.revision INTO v_revision FROM public.matters AS matter
  WHERE matter.id='d1480000-0000-0000-0000-000000000001';
  SELECT * INTO collision FROM public.activate_matter_identifier(
    'd1480000-0000-0000-0000-000000000001',v_revision,'proceeding_case_id','self_identifier',
    'GST Portal','GST/148/2026','GST/148/2026',
    'e1480000-0000-0000-0000-000000000001','01480000-0000-0000-0000-000000000001',1,
    'Proceeding reference GST / 148 / 2026','[]',NULL,
    '14800000-0000-0000-0000-000000000022');
  IF collision.code<>'identifier_conflict' THEN
    RAISE EXCEPTION 'Trash released verified external identity: %',collision.code;
  END IF;
  PERFORM set_config('test.cutover.identifier_id',activated.identifier_id::text,true);
  PERFORM set_config('test.cutover.trash_operation_id',trashed.operation_id::text,true);
END $trash_restore_and_verified_key$;
RESET ROLE;

-- The global unique indexes normally make both corrupt states impossible.
-- Remove each one only inside a savepoint to prove the Restore preflight still
-- fails closed if legacy or privileged corruption is ever encountered.
SAVEPOINT matter_code_restore_collision_probe;
DROP INDEX public.matters_org_matter_code_unique;
UPDATE public.matters
SET matter_code='CMP-2627-01'
WHERE id='d1480000-0000-0000-0000-000000000003';
DO $matter_code_restore_collision$
DECLARE blocker record;
BEGIN
  SELECT * INTO blocker FROM public.trash_restore_blocker(
    'b1480000-0000-0000-0000-000000000001',
    current_setting('test.cutover.trash_operation_id')::uuid
  ) LIMIT 1;
  IF blocker.blocker_code<>'matter_identifier_conflict' THEN
    RAISE EXCEPTION 'Restore did not reject a genuine active Matter-code collision: %',blocker.blocker_code;
  END IF;
END $matter_code_restore_collision$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1480000-0000-0000-0000-000000000001',true);
DO $matter_code_restore_collision_public$
DECLARE preflight record; restored record;
BEGIN
  SELECT * INTO preflight FROM public.get_trash_restore_preflight(
    current_setting('test.cutover.trash_operation_id')::uuid
  );
  IF preflight.code<>'restore_blocked'
     OR preflight.can_restore
     OR preflight.blocker_code<>'matter_identifier_conflict' THEN
    RAISE EXCEPTION 'public preflight did not reject a genuine Matter-code collision: %/%',
      preflight.code,preflight.blocker_code;
  END IF;

  SELECT * INTO restored FROM public.restore_trash_operation(
    current_setting('test.cutover.trash_operation_id')::uuid,
    'cutover.fixture.restore-code-conflict'
  );
  IF restored.code<>'restore_blocked'
     OR restored.blocker_code<>'matter_identifier_conflict' THEN
    RAISE EXCEPTION 'public Restore did not reject a genuine Matter-code collision: %/%',
      restored.code,restored.blocker_code;
  END IF;
END $matter_code_restore_collision_public$;
RESET ROLE;
DO $matter_code_restore_collision_atomicity$
DECLARE v_operation_id uuid:=current_setting('test.cutover.trash_operation_id')::uuid;
BEGIN
  IF (SELECT state FROM public.trash_operations WHERE id=v_operation_id)<>'restore_blocked'
     OR (SELECT record_state FROM public.matters
         WHERE id='d1480000-0000-0000-0000-000000000003')<>'trashed'
     OR (SELECT deleted_at FROM public.matters
         WHERE id='d1480000-0000-0000-0000-000000000003') IS NULL
     OR EXISTS(
       SELECT 1 FROM public.resource_trash_memberships AS membership
       WHERE membership.operation_id=v_operation_id AND membership.state<>'active'
     )
     OR EXISTS(
       SELECT 1
       FROM public.resource_trash_memberships AS membership
       JOIN public.matters AS matter
         ON membership.resource_type='matter' AND matter.id=membership.resource_id
       WHERE membership.operation_id=v_operation_id AND matter.record_state<>'trashed'
     )
     OR EXISTS(
       SELECT 1
       FROM public.resource_trash_memberships AS membership
       JOIN public.documents AS document
         ON membership.resource_type='document' AND document.id=membership.resource_id
       WHERE membership.operation_id=v_operation_id AND document.record_state<>'trashed'
     )
     OR (SELECT count(*) FROM public.trash_restore_receipts
         WHERE operation_id=v_operation_id
           AND actor_user_id='a1480000-0000-0000-0000-000000000001'
           AND idempotency_key='cutover.fixture.restore-code-conflict'
           AND result_code='restore_blocked'
           AND blocker_code='matter_identifier_conflict')<>1
     OR EXISTS(
       SELECT 1 FROM public.activity_logs
       WHERE action='resource_restored'
         AND metadata->>'operation_id'=v_operation_id::text
     )
     OR EXISTS(
       SELECT 1 FROM public.outbox_events
       WHERE aggregate_type='trash_operation' AND aggregate_id=v_operation_id
         AND event_kind IN (
           'trash.operation_restored.v1',
           'trash.search_reindex_requested.v1',
           'trash.schedule_reevaluation_requested.v1'
         )
     ) THEN
    RAISE EXCEPTION 'blocked Matter-code Restore left partial state or effects';
  END IF;
END $matter_code_restore_collision_atomicity$;
ROLLBACK TO SAVEPOINT matter_code_restore_collision_probe;

SAVEPOINT verified_key_restore_collision_probe;
DROP INDEX public.matter_identifiers_verified_identity_reservation;
INSERT INTO public.matter_identifiers(
  id,org_id,client_id,matter_id,identifier_kind,identifier_role,catalogue_version,
  normalizer_key,normalizer_version,identity_eligible,
  issuer_namespace_raw,issuer_namespace_display,issuer_namespace_normalized,
  raw_value,display_value,normalized_value,normalized_components,
  evidence_document_id,evidence_document_version_id,evidence_page_number,
  evidence_quote,evidence_regions,verification_method,verified_by,verified_at
)
SELECT
  '21480000-0000-0000-0000-000000000001',identifier.org_id,identifier.client_id,
  'd1480000-0000-0000-0000-000000000001',identifier.identifier_kind,
  identifier.identifier_role,identifier.catalogue_version,identifier.normalizer_key,
  identifier.normalizer_version,identifier.identity_eligible,
  identifier.issuer_namespace_raw,identifier.issuer_namespace_display,
  identifier.issuer_namespace_normalized,identifier.raw_value,identifier.display_value,
  identifier.normalized_value,identifier.normalized_components,
  'e1480000-0000-0000-0000-000000000001',
  '01480000-0000-0000-0000-000000000001',1,
  'Proceeding reference GST / 148 / 2026','[]'::jsonb,
  identifier.verification_method,identifier.verified_by,identifier.verified_at
FROM public.matter_identifiers AS identifier
WHERE identifier.id=current_setting('test.cutover.identifier_id')::uuid;
DO $verified_key_restore_collision$
DECLARE blocker record;
BEGIN
  SELECT * INTO blocker FROM public.trash_restore_blocker(
    'b1480000-0000-0000-0000-000000000001',
    current_setting('test.cutover.trash_operation_id')::uuid
  ) LIMIT 1;
  IF blocker.blocker_code<>'matter_identifier_conflict' THEN
    RAISE EXCEPTION 'Restore did not reject a genuine active verified-key collision: %',blocker.blocker_code;
  END IF;
END $verified_key_restore_collision$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1480000-0000-0000-0000-000000000001',true);
DO $verified_key_restore_collision_public$
DECLARE preflight record; restored record;
BEGIN
  SELECT * INTO preflight FROM public.get_trash_restore_preflight(
    current_setting('test.cutover.trash_operation_id')::uuid
  );
  IF preflight.code<>'restore_blocked'
     OR preflight.can_restore
     OR preflight.blocker_code<>'matter_identifier_conflict' THEN
    RAISE EXCEPTION 'public preflight did not reject a genuine verified-key collision: %/%',
      preflight.code,preflight.blocker_code;
  END IF;

  SELECT * INTO restored FROM public.restore_trash_operation(
    current_setting('test.cutover.trash_operation_id')::uuid,
    'cutover.fixture.restore-verified-key-conflict'
  );
  IF restored.code<>'restore_blocked'
     OR restored.blocker_code<>'matter_identifier_conflict' THEN
    RAISE EXCEPTION 'public Restore did not reject a genuine verified-key collision: %/%',
      restored.code,restored.blocker_code;
  END IF;
END $verified_key_restore_collision_public$;
RESET ROLE;
DO $verified_key_restore_collision_atomicity$
DECLARE v_operation_id uuid:=current_setting('test.cutover.trash_operation_id')::uuid;
BEGIN
  IF (SELECT state FROM public.trash_operations WHERE id=v_operation_id)<>'restore_blocked'
     OR (SELECT record_state FROM public.matters
         WHERE id='d1480000-0000-0000-0000-000000000003')<>'trashed'
     OR (SELECT deleted_at FROM public.matters
         WHERE id='d1480000-0000-0000-0000-000000000003') IS NULL
     OR EXISTS(
       SELECT 1 FROM public.resource_trash_memberships AS membership
       WHERE membership.operation_id=v_operation_id AND membership.state<>'active'
     )
     OR EXISTS(
       SELECT 1
       FROM public.resource_trash_memberships AS membership
       JOIN public.matters AS matter
         ON membership.resource_type='matter' AND matter.id=membership.resource_id
       WHERE membership.operation_id=v_operation_id AND matter.record_state<>'trashed'
     )
     OR EXISTS(
       SELECT 1
       FROM public.resource_trash_memberships AS membership
       JOIN public.documents AS document
         ON membership.resource_type='document' AND document.id=membership.resource_id
       WHERE membership.operation_id=v_operation_id AND document.record_state<>'trashed'
     )
     OR (SELECT count(*) FROM public.trash_restore_receipts
         WHERE operation_id=v_operation_id
           AND actor_user_id='a1480000-0000-0000-0000-000000000001'
           AND idempotency_key='cutover.fixture.restore-verified-key-conflict'
           AND result_code='restore_blocked'
           AND blocker_code='matter_identifier_conflict')<>1
     OR EXISTS(
       SELECT 1 FROM public.activity_logs
       WHERE action='resource_restored'
         AND metadata->>'operation_id'=v_operation_id::text
     )
     OR EXISTS(
       SELECT 1 FROM public.outbox_events
       WHERE aggregate_type='trash_operation' AND aggregate_id=v_operation_id
         AND event_kind IN (
           'trash.operation_restored.v1',
           'trash.search_reindex_requested.v1',
           'trash.schedule_reevaluation_requested.v1'
         )
     ) THEN
    RAISE EXCEPTION 'blocked verified-key Restore left partial state or effects';
  END IF;
END $verified_key_restore_collision_atomicity$;
ROLLBACK TO SAVEPOINT verified_key_restore_collision_probe;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1480000-0000-0000-0000-000000000001',true);
DO $same_year_restore$
DECLARE restored record;
BEGIN
  SELECT * INTO restored FROM public.restore_trash_operation(
    current_setting('test.cutover.trash_operation_id')::uuid,'cutover.fixture.restore');
  IF restored.code<>'restored'
     OR (SELECT record_state FROM public.matters WHERE id='d1480000-0000-0000-0000-000000000003')<>'active'
     OR (SELECT matter_code FROM public.matters WHERE id='d1480000-0000-0000-0000-000000000003')<>'CMP-2627-03' THEN
    RAISE EXCEPTION 'same-client/year Restore changed or blocked true identity';
  END IF;
END $same_year_restore$;
RESET ROLE;

DO $denial_atomicity$
BEGIN
  IF EXISTS(SELECT 1 FROM public.matter_command_receipts
      WHERE idempotency_key IN (
        '14800000-0000-0000-0000-000000000013',
        '14800000-0000-0000-0000-000000000014',
        '14800000-0000-0000-0000-000000000015'
      ))
     OR EXISTS(SELECT 1 FROM public.activity_events
       WHERE idempotency_key IN (
        '14800000-0000-0000-0000-000000000013',
        '14800000-0000-0000-0000-000000000014',
        '14800000-0000-0000-0000-000000000015'
       ))
     OR NOT EXISTS(SELECT 1 FROM public.matter_identifiers
       WHERE id=current_setting('test.cutover.identifier_id')::uuid AND lifecycle_state='active') THEN
    RAISE EXCEPTION 'denied commands left partial receipts or Activity';
  END IF;
END $denial_atomicity$;

SAVEPOINT malformed_sequence_probe;
INSERT INTO public.matters(org_id,client_id,title,financial_year,matter_code)
VALUES(
  'b1480000-0000-0000-0000-000000000001',
  'c1480000-0000-0000-0000-000000000001',
  'Malformed held sequence probe','2026-27','CMP-2627-BAD'
);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1480000-0000-0000-0000-000000000001',true);
DO $malformed_sequence_fails_safe$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.create_matter_command(
    'c1480000-0000-0000-0000-000000000001','Malformed sequence denied','2026-27','',
    'active'::public.matter_work_state,'adjudication'::public.matter_current_forum,
    '14800000-0000-0000-0000-000000000031');
  IF result.code<>'identifier_conflict' OR result.matter_id IS NOT NULL THEN
    RAISE EXCEPTION 'malformed held sequence did not fail safely: %',result.code;
  END IF;
END $malformed_sequence_fails_safe$;
RESET ROLE;
ROLLBACK TO SAVEPOINT malformed_sequence_probe;

SAVEPOINT exhausted_sequence_probe;
INSERT INTO public.matters(org_id,client_id,title,financial_year,matter_code)
VALUES(
  'b1480000-0000-0000-0000-000000000001',
  'c1480000-0000-0000-0000-000000000001',
  'Exhausted held sequence probe','2026-27','CMP-2627-999999999999999999'
);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1480000-0000-0000-0000-000000000001',true);
DO $exhausted_sequence_fails_safe$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.create_matter_command(
    'c1480000-0000-0000-0000-000000000001','Exhausted sequence denied','2026-27','',
    'active'::public.matter_work_state,'adjudication'::public.matter_current_forum,
    '14800000-0000-0000-0000-000000000032');
  IF result.code<>'identifier_conflict' OR result.matter_id IS NOT NULL THEN
    RAISE EXCEPTION 'exhausted held sequence did not fail safely: %',result.code;
  END IF;
END $exhausted_sequence_fails_safe$;
RESET ROLE;
ROLLBACK TO SAVEPOINT exhausted_sequence_probe;

ROLLBACK;
