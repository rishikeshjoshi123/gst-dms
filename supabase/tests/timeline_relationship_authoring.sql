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


DO $acl$ BEGIN
  IF has_table_privilege('authenticated','public.document_relationship_catalogue','SELECT')
     OR has_function_privilege('anon','public.read_matter_relationship_authoring_context(uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.read_matter_relationship_authoring_context(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'authoring context privileges are too broad';
  END IF;
END $acl$;
UPDATE public.documents SET display_title = 'Reply corrected', reference_number = 'REF-155' WHERE id='e1460000-0000-0000-0000-000000000002';
INSERT INTO public.document_relationship_catalogue
  SELECT relationship_type,2,'responds directly to',progression_phrase,timeline_visible,acyclic,
    allowed_source_classes,allowed_target_classes,reject_same_type_inverse,display_priority,now()
  FROM public.document_relationship_catalogue WHERE relationship_type='responds_to' AND catalogue_version=1;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','a1460000-0000-0000-0000-000000000001',true);
DO $owner$ DECLARE r record; edge record; a record; initial_revision text; BEGIN
  SELECT * INTO r FROM public.read_matter_relationship_authoring_context('d1460000-0000-0000-0000-000000000001');
  initial_revision := r.relationship_source_revision;
  IF initial_revision IS DISTINCT FROM (SELECT source_revision FROM public.read_matter_timeline_relationships('d1460000-0000-0000-0000-000000000001',NULL)) THEN RAISE EXCEPTION 'graph revision diverged'; END IF;
  IF r.outcome <> 'ok' OR jsonb_array_length(r.documents) <> 4 OR jsonb_array_length(r.relationship_types) <> 9
     OR NOT r.documents @> '[{"id":"e1460000-0000-0000-0000-000000000002","lifecycleRevision":2,"referenceNumber":"REF-155"},{"id":"e1460000-0000-0000-0000-000000000001","referenceNumber":null}]'::jsonb
     OR NOT r.relationship_types @> '[{"relationshipType":"responds_to","catalogueVersion":2,"canonicalPhrase":"responds directly to","progressionPhrase":"answered by"}]'::jsonb
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(r.relationship_types) t WHERE t->>'relationshipType' IN ('other','refers_to'))
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(r.documents) d WHERE (SELECT count(*) FROM jsonb_object_keys(d)) <> 4) THEN
    RAISE EXCEPTION 'authorised bounded context/catalogue/lifecycle projection failed: %', row_to_json(r);
  END IF;
  SELECT * INTO r FROM public.read_matter_relationship_authoring_context('d1460000-0000-0000-0000-000000000003');
  IF r.outcome <> 'unavailable' OR r.documents <> '[]'::jsonb THEN RAISE EXCEPTION 'closed context leaked'; END IF;
  SELECT * INTO r FROM public.read_matter_relationship_authoring_context('d1460000-0000-0000-0000-000000000004');
  IF r.outcome <> 'unavailable' OR r.relationship_types <> '[]'::jsonb THEN RAISE EXCEPTION 'foreign context leaked'; END IF;
  SELECT * INTO edge FROM public.activate_document_relationship('d1460000-0000-0000-0000-000000000001','e1460000-0000-0000-0000-000000000002','e1460000-0000-0000-0000-000000000001','responds_to',2,1,'Authoring fixture','f1550000-0000-0000-0000-000000000001');
  IF edge.code <> 'ok' THEN RAISE EXCEPTION 'fixture activation failed: %',edge.code; END IF;
  SELECT * INTO r FROM public.read_matter_relationship_authoring_context('d1460000-0000-0000-0000-000000000001');
  IF r.relationship_source_revision = initial_revision THEN RAISE EXCEPTION 'activation did not invalidate graph revision'; END IF;
  SELECT * INTO a FROM public.archive_matter_timeline_relationship('d1460000-0000-0000-0000-000000000002',edge.relationship_id,1,'Wrong context','f1550000-0000-0000-0000-000000000002');
  IF a.code <> 'context_unavailable' THEN RAISE EXCEPTION 'mismatched Matter archive allowed'; END IF;
  SELECT * INTO a FROM public.archive_matter_timeline_relationship('d1460000-0000-0000-0000-000000000001',edge.relationship_id,1,'Reviewed archive','f1550000-0000-0000-0000-000000000003');
  IF a.code <> 'ok' THEN RAISE EXCEPTION 'archive failed'; END IF;
  SELECT * INTO a FROM public.archive_matter_timeline_relationship('d1460000-0000-0000-0000-000000000001',edge.relationship_id,1,'Reviewed archive','f1550000-0000-0000-0000-000000000003');
  IF a.code <> 'ok' OR NOT a.replayed THEN RAISE EXCEPTION 'archive response-loss replay failed'; END IF;
  SELECT * INTO r FROM public.read_matter_relationship_authoring_context('d1460000-0000-0000-0000-000000000001');
  IF r.relationship_source_revision <> initial_revision THEN RAISE EXCEPTION 'archive did not restore effective graph revision'; END IF;
END $owner$;
DO $roles$ DECLARE actor text; r record; BEGIN
  FOREACH actor IN ARRAY ARRAY['a1460000-0000-0000-0000-000000000002','a1460000-0000-0000-0000-000000000003'] LOOP
    PERFORM set_config('request.jwt.claim.sub',actor,true);
    SELECT * INTO r FROM public.read_matter_relationship_authoring_context('d1460000-0000-0000-0000-000000000001');
    IF r.outcome <> 'ok' THEN RAISE EXCEPTION 'contributor denied'; END IF;
  END LOOP;
  FOREACH actor IN ARRAY ARRAY['a1460000-0000-0000-0000-000000000004','a1460000-0000-0000-0000-000000000005','a1460000-0000-0000-0000-000000000006'] LOOP
    PERFORM set_config('request.jwt.claim.sub',actor,true);
    SELECT * INTO r FROM public.read_matter_relationship_authoring_context('d1460000-0000-0000-0000-000000000001');
    IF r.outcome <> 'unavailable' OR r.documents <> '[]'::jsonb OR r.relationship_types <> '[]'::jsonb THEN RAISE EXCEPTION 'unauthorised context leaked'; END IF;
  END LOOP;
END $roles$;
SELECT set_config('request.jwt.claim.sub','a1460000-0000-0000-0000-000000000001',true);
SAVEPOINT matter_trash_context;
SELECT * FROM public.trash_resource('matter','d1460000-0000-0000-0000-000000000001','authoring.matter-context');
DO $matter_trash$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.read_matter_relationship_authoring_context('d1460000-0000-0000-0000-000000000001');
  IF r.outcome <> 'unavailable' OR r.documents <> '[]'::jsonb THEN RAISE EXCEPTION 'trashed Matter exposed authoring'; END IF;
END $matter_trash$;
ROLLBACK TO SAVEPOINT matter_trash_context;
SAVEPOINT client_trash_context;
SELECT * FROM public.trash_resource('client','c1460000-0000-0000-0000-000000000001','authoring.client-context');
DO $client_trash$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.read_matter_relationship_authoring_context('d1460000-0000-0000-0000-000000000001');
  IF r.outcome <> 'unavailable' OR r.documents <> '[]'::jsonb THEN RAISE EXCEPTION 'trashed Client exposed authoring'; END IF;
END $client_trash$;
ROLLBACK TO SAVEPOINT client_trash_context;
RESET ROLE;
INSERT INTO public.documents(org_id,matter_id,display_title,document_class,origin_kind,content_availability,status,created_by)
SELECT 'b1460000-0000-0000-0000-000000000001','d1460000-0000-0000-0000-000000000001','Bounded document '||n,'proceeding','manual_record','metadata_only','placed','a1460000-0000-0000-0000-000000000001' FROM generate_series(1,997) n;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1460000-0000-0000-0000-000000000001',true);
DO $capacity$ DECLARE r record; BEGIN
  SELECT * INTO r FROM public.read_matter_relationship_authoring_context('d1460000-0000-0000-0000-000000000001');
  IF r.outcome <> 'capacity' OR r.documents <> '[]'::jsonb THEN RAISE EXCEPTION 'endpoint bound failed'; END IF;
END $capacity$;
ROLLBACK;
