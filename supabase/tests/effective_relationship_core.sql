-- Run after migration 00146 against a disposable local Supabase database.
-- The fixture is rollback-only and never reads or backfills legacy links.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
  ('00000000-0000-0000-0000-000000000000','a1460000-0000-0000-0000-000000000001','authenticated','authenticated','owner@relationship.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1460000-0000-0000-0000-000000000002','authenticated','authenticated','admin@relationship.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1460000-0000-0000-0000-000000000003','authenticated','authenticated','associate@relationship.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1460000-0000-0000-0000-000000000004','authenticated','authenticated','viewer@relationship.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1460000-0000-0000-0000-000000000005','authenticated','authenticated','suspended@relationship.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1460000-0000-0000-0000-000000000006','authenticated','authenticated','foreign@relationship.test','x',now(),'{}','{}',now(),now());

INSERT INTO public.organisations(id,name,created_by) VALUES
  ('b1460000-0000-0000-0000-000000000001','Relationship organisation','a1460000-0000-0000-0000-000000000001'),
  ('b1460000-0000-0000-0000-000000000002','Foreign relationship organisation','a1460000-0000-0000-0000-000000000006');
INSERT INTO public.org_members(org_id,user_id,role) VALUES
  ('b1460000-0000-0000-0000-000000000001','a1460000-0000-0000-0000-000000000002','admin'),
  ('b1460000-0000-0000-0000-000000000001','a1460000-0000-0000-0000-000000000003','associate'),
  ('b1460000-0000-0000-0000-000000000001','a1460000-0000-0000-0000-000000000004','viewer'),
  ('b1460000-0000-0000-0000-000000000001','a1460000-0000-0000-0000-000000000005','associate');
UPDATE public.organisation_memberships
SET state='suspended',suspended_at=now(),suspended_by='a1460000-0000-0000-0000-000000000001',suspension_reason='fixture'
WHERE org_id='b1460000-0000-0000-0000-000000000001' AND user_id='a1460000-0000-0000-0000-000000000005';

INSERT INTO public.clients(id,org_id,name) VALUES
  ('c1460000-0000-0000-0000-000000000001','b1460000-0000-0000-0000-000000000001','Relationship client'),
  ('c1460000-0000-0000-0000-000000000002','b1460000-0000-0000-0000-000000000002','Foreign client');
INSERT INTO public.matters(id,org_id,client_id,title,financial_year,status) VALUES
  ('d1460000-0000-0000-0000-000000000001','b1460000-0000-0000-0000-000000000001','c1460000-0000-0000-0000-000000000001','Relationship matter','2026-27','active'),
  ('d1460000-0000-0000-0000-000000000002','b1460000-0000-0000-0000-000000000001','c1460000-0000-0000-0000-000000000001','Other matter','2027-28','active'),
  ('d1460000-0000-0000-0000-000000000003','b1460000-0000-0000-0000-000000000001','c1460000-0000-0000-0000-000000000001','Closed matter','2028-29','closed'),
  ('d1460000-0000-0000-0000-000000000004','b1460000-0000-0000-0000-000000000002','c1460000-0000-0000-0000-000000000002','Foreign matter','2026-27','active');

INSERT INTO public.documents(id,org_id,matter_id,display_title,document_class,origin_kind,content_availability,status,created_by) VALUES
  ('e1460000-0000-0000-0000-000000000001','b1460000-0000-0000-0000-000000000001','d1460000-0000-0000-0000-000000000001','Show Cause Notice','proceeding','manual_record','metadata_only','placed','a1460000-0000-0000-0000-000000000001'),
  ('e1460000-0000-0000-0000-000000000002','b1460000-0000-0000-0000-000000000001','d1460000-0000-0000-0000-000000000001','Reply','proceeding','manual_record','metadata_only','placed','a1460000-0000-0000-0000-000000000001'),
  ('e1460000-0000-0000-0000-000000000003','b1460000-0000-0000-0000-000000000001','d1460000-0000-0000-0000-000000000001','Order','proceeding','manual_record','metadata_only','placed','a1460000-0000-0000-0000-000000000001'),
  ('e1460000-0000-0000-0000-000000000004','b1460000-0000-0000-0000-000000000001','d1460000-0000-0000-0000-000000000001','Appeal','proceeding','manual_record','metadata_only','placed','a1460000-0000-0000-0000-000000000001'),
  ('e1460000-0000-0000-0000-000000000005','b1460000-0000-0000-0000-000000000001','d1460000-0000-0000-0000-000000000001','Supporting invoice','supporting','manual_record','metadata_only','placed','a1460000-0000-0000-0000-000000000001'),
  ('e1460000-0000-0000-0000-000000000006','b1460000-0000-0000-0000-000000000001','d1460000-0000-0000-0000-000000000001','Trashed proceeding','proceeding','manual_record','metadata_only','placed','a1460000-0000-0000-0000-000000000001'),
  ('e1460000-0000-0000-0000-000000000007','b1460000-0000-0000-0000-000000000001','d1460000-0000-0000-0000-000000000002','Other-matter proceeding','proceeding','manual_record','metadata_only','placed','a1460000-0000-0000-0000-000000000001'),
  ('e1460000-0000-0000-0000-000000000008','b1460000-0000-0000-0000-000000000001','d1460000-0000-0000-0000-000000000003','Closed source','proceeding','manual_record','metadata_only','placed','a1460000-0000-0000-0000-000000000001'),
  ('e1460000-0000-0000-0000-000000000009','b1460000-0000-0000-0000-000000000001','d1460000-0000-0000-0000-000000000003','Closed target','proceeding','manual_record','metadata_only','placed','a1460000-0000-0000-0000-000000000001'),
  ('e1460000-0000-0000-0000-000000000010','b1460000-0000-0000-0000-000000000002','d1460000-0000-0000-0000-000000000004','Foreign proceeding','proceeding','manual_record','metadata_only','placed','a1460000-0000-0000-0000-000000000006');
UPDATE public.documents
SET record_state='trashed',deleted_at=now(),trashed_at=now()
WHERE id='e1460000-0000-0000-0000-000000000006';

-- A legacy row is valid legacy data, but it must never become canonical.
INSERT INTO public.document_links(from_doc_id,to_doc_id,link_type,status,match_method)
VALUES('e1460000-0000-0000-0000-000000000004','e1460000-0000-0000-0000-000000000001','summarizes','confirmed','fixture');

DO $catalogue$
BEGIN
  IF (SELECT count(*) FROM public.document_relationship_catalogue WHERE catalogue_version=1)<>11
     OR NOT EXISTS(SELECT 1 FROM public.document_relationship_catalogue WHERE relationship_type='responds_to' AND canonical_phrase='responds to' AND progression_phrase='answered by' AND timeline_visible AND acyclic)
     OR EXISTS(SELECT 1 FROM public.document_relationship_catalogue WHERE timeline_visible AND NOT acyclic) THEN
    RAISE EXCEPTION 'relationship catalogue contract failed';
  END IF;
  IF NOT ('relationship.manage'=ANY(public.organisation_member_capabilities('associate',false,'active')))
     OR 'relationship.manage'=ANY(public.organisation_member_capabilities('viewer',false,'active'))
     OR cardinality(public.organisation_member_capabilities('associate',false,'suspended'))<>0 THEN
    RAISE EXCEPTION 'relationship capability baseline failed';
  END IF;
END $catalogue$;

DO $acl$
BEGIN
  IF has_table_privilege('authenticated','public.document_relationships','SELECT')
     OR has_table_privilege('service_role','public.document_relationships','SELECT')
     OR has_function_privilege('anon','public.activate_document_relationship(uuid,uuid,uuid,public.document_relationship_type,bigint,bigint,text,uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.activate_document_relationship(uuid,uuid,uuid,public.document_relationship_type,bigint,bigint,text,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.read_matter_timeline_relationships(uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'relationship ACL contract failed';
  END IF;
END $acl$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);

SELECT set_config('request.jwt.claim.sub','a1460000-0000-0000-0000-000000000001',true);
DO $owner_success$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000002','responds_to',1,1,'Manual procedural review','f1460000-0000-0000-0000-000000000001');
  IF result.code<>'ok' OR result.relationship_id IS NULL OR result.revision<>1 OR result.replayed THEN RAISE EXCEPTION 'Owner activation failed'; END IF;
  PERFORM set_config('test.relationship_id',result.relationship_id::text,true);
END $owner_success$;

SELECT set_config('request.jwt.claim.sub','a1460000-0000-0000-0000-000000000002',true);
DO $admin_success$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000002','e1460000-0000-0000-0000-000000000003','modifies',1,1,NULL,'f1460000-0000-0000-0000-000000000002');
  IF result.code<>'ok' OR result.relationship_id IS NULL THEN RAISE EXCEPTION 'Admin activation failed'; END IF;
END $admin_success$;

SELECT set_config('request.jwt.claim.sub','a1460000-0000-0000-0000-000000000003',true);
DO $associate_success$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000003','e1460000-0000-0000-0000-000000000004','challenges',1,1,NULL,'f1460000-0000-0000-0000-000000000003');
  IF result.code<>'ok' OR result.relationship_id IS NULL THEN RAISE EXCEPTION 'Associate activation failed'; END IF;
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000002','arises_from',1,1,NULL,'f1460000-0000-0000-0000-000000000004');
  IF result.code<>'ok' THEN RAISE EXCEPTION 'Separate relationship type failed'; END IF;
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000003','refers_to',1,1,NULL,'f1460000-0000-0000-0000-000000000005');
  IF result.code<>'ok' THEN RAISE EXCEPTION 'Non-Timeline relationship failed'; END IF;
END $associate_success$;

-- Denials and integrity failures must not append rows, decisions, Activity,
-- projector outbox work, or success receipts.
DO $failure_matrix$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000001','responds_to',1,1,NULL,'f1460000-0000-0000-0000-000000000011');
  IF result.code<>'self_relationship' THEN RAISE EXCEPTION 'self relationship not rejected'; END IF;
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000002','responds_to',1,1,NULL,'f1460000-0000-0000-0000-000000000012');
  IF result.code<>'duplicate_active' THEN RAISE EXCEPTION 'duplicate relationship not rejected'; END IF;
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000002','e1460000-0000-0000-0000-000000000001','responds_to',1,1,NULL,'f1460000-0000-0000-0000-000000000013');
  IF result.code<>'inverse_conflict' THEN RAISE EXCEPTION 'inverse relationship not rejected'; END IF;
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000004','e1460000-0000-0000-0000-000000000001','supersedes',1,1,NULL,'f1460000-0000-0000-0000-000000000014');
  IF result.code<>'cycle_detected' THEN RAISE EXCEPTION 'cycle not rejected'; END IF;
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000005','e1460000-0000-0000-0000-000000000001','other',1,1,NULL,'f1460000-0000-0000-0000-000000000015');
  IF result.code<>'invalid_endpoint_class' THEN RAISE EXCEPTION 'supporting endpoint not rejected'; END IF;
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000006','e1460000-0000-0000-0000-000000000001','other',1,1,NULL,'f1460000-0000-0000-0000-000000000016');
  IF result.code<>'endpoint_unavailable' THEN RAISE EXCEPTION 'trashed endpoint not rejected'; END IF;
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000007','e1460000-0000-0000-0000-000000000001','other',1,1,NULL,'f1460000-0000-0000-0000-000000000017');
  IF result.code<>'context_unavailable' THEN RAISE EXCEPTION 'cross-matter endpoint not rejected'; END IF;
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000010','e1460000-0000-0000-0000-000000000001','other',1,1,NULL,'f1460000-0000-0000-0000-000000000018');
  IF result.code<>'context_unavailable' THEN RAISE EXCEPTION 'cross-tenant endpoint not rejected'; END IF;
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000003','e1460000-0000-0000-0000-000000000008','e1460000-0000-0000-0000-000000000009','other',1,1,NULL,'f1460000-0000-0000-0000-000000000019');
  IF result.code<>'matter_read_only' THEN RAISE EXCEPTION 'closed matter not rejected'; END IF;
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000004','other',99,1,NULL,'f1460000-0000-0000-0000-000000000020');
  IF result.code<>'conflict' THEN RAISE EXCEPTION 'endpoint revision conflict not rejected'; END IF;
  SELECT * INTO result FROM public.archive_document_relationship(current_setting('test.relationship_id')::uuid,99,'Stale archive','f1460000-0000-0000-0000-000000000024');
  IF result.code<>'conflict' THEN RAISE EXCEPTION 'relationship revision conflict not rejected'; END IF;
  SELECT * INTO result FROM public.archive_document_relationship(current_setting('test.relationship_id')::uuid,1,'','f1460000-0000-0000-0000-000000000025');
  IF result.code<>'invalid_request' THEN RAISE EXCEPTION 'empty archive reason not rejected'; END IF;
END $failure_matrix$;

SELECT set_config('request.jwt.claim.sub','a1460000-0000-0000-0000-000000000004',true);
DO $viewer_denial$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000004','other',1,1,NULL,'f1460000-0000-0000-0000-000000000021');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'Viewer mutation not denied'; END IF;
  SELECT * INTO result FROM public.archive_document_relationship(current_setting('test.relationship_id')::uuid,1,'Viewer archive','f1460000-0000-0000-0000-000000000026');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'Viewer archive not denied'; END IF;
END $viewer_denial$;
SELECT set_config('request.jwt.claim.sub','a1460000-0000-0000-0000-000000000005',true);
DO $suspended_denial$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000004','other',1,1,NULL,'f1460000-0000-0000-0000-000000000022');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'Suspended mutation not denied'; END IF;
  SELECT * INTO result FROM public.archive_document_relationship(current_setting('test.relationship_id')::uuid,1,'Suspended archive','f1460000-0000-0000-0000-000000000027');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'Suspended archive not denied'; END IF;
END $suspended_denial$;
SELECT set_config('request.jwt.claim.sub','a1460000-0000-0000-0000-000000000006',true);
DO $foreign_actor_denial$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000004','other',1,1,NULL,'f1460000-0000-0000-0000-000000000023');
  IF result.code<>'context_unavailable' THEN RAISE EXCEPTION 'Foreign actor mutation leaked context'; END IF;
  SELECT * INTO result FROM public.archive_document_relationship(current_setting('test.relationship_id')::uuid,1,'Foreign archive','f1460000-0000-0000-0000-000000000028');
  IF result.code<>'context_unavailable' THEN RAISE EXCEPTION 'Foreign actor archive leaked context'; END IF;
END $foreign_actor_denial$;

RESET ROLE;
DO $no_partial_failure_writes$
BEGIN
  IF (SELECT count(*) FROM public.document_relationships)<>5
     OR (SELECT count(*) FROM public.document_relationship_decisions)<>5
     OR (SELECT count(*) FROM public.document_relationship_command_receipts)<>5
     OR (SELECT count(*) FROM public.activity_events WHERE idempotency_key LIKE 'relationship.%')<>5
     OR (SELECT count(*) FROM public.activity_projector_outbox_events AS outbox JOIN public.activity_events AS event ON event.id=outbox.activity_event_id WHERE event.idempotency_key LIKE 'relationship.%')<>5 THEN
    RAISE EXCEPTION 'failed relationship command made a partial write';
  END IF;
  IF (SELECT count(*) FROM public.document_relationships WHERE source_document_id='e1460000-0000-0000-0000-000000000001' AND target_document_id='e1460000-0000-0000-0000-000000000002' AND lifecycle_state='active')<>2 THEN
    RAISE EXCEPTION 'multiple relationship types did not remain separate';
  END IF;
END $no_partial_failure_writes$;

-- Archive also requires an active Matter and two active proceeding endpoints.
UPDATE public.documents
SET record_state='trashed',deleted_at=now(),trashed_at=now()
WHERE id='e1460000-0000-0000-0000-000000000002';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1460000-0000-0000-0000-000000000001',true);
DO $archive_trashed_endpoint$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.archive_document_relationship(current_setting('test.relationship_id')::uuid,1,'Archive with unavailable endpoint','f1460000-0000-0000-0000-000000000031');
  IF result.code<>'endpoint_unavailable' THEN RAISE EXCEPTION 'trashed archive endpoint not rejected'; END IF;
END $archive_trashed_endpoint$;
RESET ROLE;
UPDATE public.documents
SET record_state='active',deleted_at=NULL,trashed_at=NULL
WHERE id='e1460000-0000-0000-0000-000000000002';
UPDATE public.matters SET work_state='closed'
WHERE id='d1460000-0000-0000-0000-000000000001';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1460000-0000-0000-0000-000000000001',true);
DO $archive_closed_matter$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.archive_document_relationship(current_setting('test.relationship_id')::uuid,1,'Archive in closed matter','f1460000-0000-0000-0000-000000000032');
  IF result.code<>'matter_read_only' THEN RAISE EXCEPTION 'closed matter archive not rejected'; END IF;
END $archive_closed_matter$;
RESET ROLE;
UPDATE public.matters SET work_state='active'
WHERE id='d1460000-0000-0000-0000-000000000001';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1460000-0000-0000-0000-000000000001',true);
DO $archive_and_replay$
DECLARE relationship_id uuid:=current_setting('test.relationship_id')::uuid; result record;
BEGIN
  SELECT * INTO result FROM public.archive_document_relationship(relationship_id,1,'Superseded after legal review','f1460000-0000-0000-0000-000000000030');
  IF result.code<>'ok' OR result.revision<>2 OR result.replayed THEN RAISE EXCEPTION 'archive failed'; END IF;
  SELECT * INTO result FROM public.archive_document_relationship(relationship_id,1,'Superseded after legal review','f1460000-0000-0000-0000-000000000030');
  IF result.code<>'ok' OR result.revision<>2 OR NOT result.replayed THEN RAISE EXCEPTION 'archive replay failed'; END IF;
  SELECT * INTO result FROM public.archive_document_relationship(relationship_id,1,'Different reason','f1460000-0000-0000-0000-000000000030');
  IF result.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'archive idempotency conflict failed'; END IF;
  SELECT * INTO result FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000002','responds_to',1,1,'Manual procedural review','f1460000-0000-0000-0000-000000000001');
  IF result.code<>'ok' OR NOT result.replayed THEN RAISE EXCEPTION 'activation replay failed after archive'; END IF;
END $archive_and_replay$;

DO $projection$
DECLARE result record; item jsonb;
BEGIN
  SELECT * INTO result FROM public.read_matter_timeline_relationships('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000001');
  IF result.outcome<>'ok' OR jsonb_array_length(result.relationships)<>1 OR result.source_revision IS NULL THEN RAISE EXCEPTION 'selected relationship projection failed'; END IF;
  item:=result.relationships->0;
  IF item->>'relationshipType'<>'arises_from' OR item->>'canonicalPhrase'<>'arises from' OR item->>'progressionPhrase'<>'gives rise to'
     OR item->>'canonicalSourceDocumentId'<>'e1460000-0000-0000-0000-000000000001'
     OR item->>'canonicalTargetDocumentId'<>'e1460000-0000-0000-0000-000000000002'
     OR item->>'displayFromDocumentId'<>'e1460000-0000-0000-0000-000000000002'
     OR item->>'displayToDocumentId'<>'e1460000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'projection phrases or direction ids failed';
  END IF;
  SELECT * INTO result FROM public.read_matter_timeline_relationships('d1460000-0000-0000-0000-000000000001',NULL);
  IF jsonb_array_length(result.relationships)<>3 THEN RAISE EXCEPTION 'projection did not exclude archive/refers-to/legacy link'; END IF;
END $projection$;
RESET ROLE;

DO $history_and_append_only$
BEGIN
  IF (SELECT count(*) FROM public.document_relationship_decisions)<>6
     OR (SELECT count(*) FROM public.activity_events WHERE idempotency_key LIKE 'relationship.%')<>6
     OR (SELECT count(*) FROM public.activity_projector_outbox_events AS outbox JOIN public.activity_events AS event ON event.id=outbox.activity_event_id WHERE event.idempotency_key LIKE 'relationship.%')<>6
     OR NOT EXISTS(SELECT 1 FROM public.document_relationship_decisions WHERE action='archive' AND reason='Superseded after legal review' AND resulting_revision=2) THEN
    RAISE EXCEPTION 'archive history or Activity/outbox failed';
  END IF;
  BEGIN
    UPDATE public.document_relationship_decisions SET reason='mutated' WHERE action='archive';
    RAISE EXCEPTION 'append-only decision update succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='append-only decision update succeeded' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO public.document_relationships(org_id,matter_id,source_document_id,target_document_id,relationship_type,catalogue_version,verification,provenance,lifecycle_state,activated_by)
    VALUES('b1460000-0000-0000-0000-000000000001','d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000002','e1460000-0000-0000-0000-000000000001','arises_from',1,'human','manual','active','a1460000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'table inverse guard succeeded unexpectedly';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.document_relationships(org_id,matter_id,source_document_id,target_document_id,relationship_type,catalogue_version,verification,provenance,lifecycle_state,activated_by)
    VALUES('b1460000-0000-0000-0000-000000000001','d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000004','e1460000-0000-0000-0000-000000000001','supersedes',1,'human','manual','active','a1460000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'table cycle guard succeeded unexpectedly';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $history_and_append_only$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1460000-0000-0000-0000-000000000006',true);
DO $foreign_projection$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.read_matter_timeline_relationships('d1460000-0000-0000-0000-000000000001',NULL);
  IF result.outcome<>'unavailable' OR result.relationships<>'[]' OR result.source_revision IS NOT NULL THEN RAISE EXCEPTION 'foreign projection leaked'; END IF;
END $foreign_projection$;
RESET ROLE;

ROLLBACK;
