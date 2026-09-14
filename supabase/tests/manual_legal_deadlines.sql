-- Run after 00159 against an exclusively owned disposable database.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 ('00000000-0000-0000-0000-000000000000','a1590000-0000-0000-0000-000000000001','authenticated','authenticated','owner@deadline.test','x',now(),'{}','{}',now(),now()),
 ('00000000-0000-0000-0000-000000000000','a1590000-0000-0000-0000-000000000002','authenticated','authenticated','admin@deadline.test','x',now(),'{}','{}',now(),now()),
 ('00000000-0000-0000-0000-000000000000','a1590000-0000-0000-0000-000000000003','authenticated','authenticated','associate@deadline.test','x',now(),'{}','{}',now(),now()),
 ('00000000-0000-0000-0000-000000000000','a1590000-0000-0000-0000-000000000004','authenticated','authenticated','viewer@deadline.test','x',now(),'{}','{}',now(),now()),
 ('00000000-0000-0000-0000-000000000000','a1590000-0000-0000-0000-000000000005','authenticated','authenticated','suspended@deadline.test','x',now(),'{}','{}',now(),now()),
 ('00000000-0000-0000-0000-000000000000','a1590000-0000-0000-0000-000000000006','authenticated','authenticated','foreign@deadline.test','x',now(),'{}','{}',now(),now()),
 ('00000000-0000-0000-0000-000000000000','a1590000-0000-0000-0000-000000000007','authenticated','authenticated','none@deadline.test','x',now(),'{}','{}',now(),now());
INSERT INTO public.user_profiles(user_id,display_name) VALUES('a1590000-0000-0000-0000-000000000001','Deadline Owner');
INSERT INTO public.organisations(id,name,created_by) VALUES
 ('b1590000-0000-0000-0000-000000000001','Deadline organisation','a1590000-0000-0000-0000-000000000001'),
 ('b1590000-0000-0000-0000-000000000002','Foreign organisation','a1590000-0000-0000-0000-000000000006');
INSERT INTO public.org_members(org_id,user_id,role) VALUES
 ('b1590000-0000-0000-0000-000000000001','a1590000-0000-0000-0000-000000000002','admin'),
 ('b1590000-0000-0000-0000-000000000001','a1590000-0000-0000-0000-000000000003','associate'),
 ('b1590000-0000-0000-0000-000000000001','a1590000-0000-0000-0000-000000000004','viewer'),
 ('b1590000-0000-0000-0000-000000000001','a1590000-0000-0000-0000-000000000005','associate');
UPDATE public.organisation_memberships SET state='suspended',suspended_at=now(),suspended_by='a1590000-0000-0000-0000-000000000001',suspension_reason='fixture' WHERE user_id='a1590000-0000-0000-0000-000000000005';
INSERT INTO public.clients(id,org_id,name) VALUES
 ('c1590000-0000-0000-0000-000000000001','b1590000-0000-0000-0000-000000000001','Active client'),
 ('c1590000-0000-0000-0000-000000000002','b1590000-0000-0000-0000-000000000001','Trashed client'),
 ('c1590000-0000-0000-0000-000000000003','b1590000-0000-0000-0000-000000000002','Foreign client');
INSERT INTO public.matters(id,org_id,client_id,title,status) VALUES
 ('d1590000-0000-0000-0000-000000000001','b1590000-0000-0000-0000-000000000001','c1590000-0000-0000-0000-000000000001','Active matter','active'),
 ('d1590000-0000-0000-0000-000000000002','b1590000-0000-0000-0000-000000000001','c1590000-0000-0000-0000-000000000001','Trashed matter','active'),
 ('d1590000-0000-0000-0000-000000000003','b1590000-0000-0000-0000-000000000001','c1590000-0000-0000-0000-000000000002','Deleted client matter','active'),
 ('d1590000-0000-0000-0000-000000000004','b1590000-0000-0000-0000-000000000001','c1590000-0000-0000-0000-000000000001','Closed matter','closed'),
 ('d1590000-0000-0000-0000-000000000005','b1590000-0000-0000-0000-000000000002','c1590000-0000-0000-0000-000000000003','Foreign matter','active');
UPDATE public.matters SET record_state='trashed',deleted_at=now() WHERE id='d1590000-0000-0000-0000-000000000002';
UPDATE public.clients SET record_state='trashed',deleted_at=now() WHERE id='c1590000-0000-0000-0000-000000000002';
UPDATE public.organisation_operational_settings SET timezone='Pacific/Kiritimati' WHERE org_id='b1590000-0000-0000-0000-000000000001';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','a1590000-0000-0000-0000-000000000001',true);
DO $owner_flow$ DECLARE r record; agenda record; item jsonb; deadline uuid; today date:=(clock_timestamp() AT TIME ZONE 'Pacific/Kiritimati')::date; BEGIN
 SELECT * INTO r FROM public.create_manual_legal_deadline('d1590000-0000-0000-0000-000000000001','File reply','File the written reply','reply_due',today-1,'Order dated 14 September 2026','f1590000-0000-0000-0000-000000000001');
 IF r.code<>'ok' OR r.revision<>1 OR r.replayed THEN RAISE EXCEPTION 'owner create failed'; END IF; deadline:=r.deadline_id;
 SELECT * INTO r FROM public.create_manual_legal_deadline('d1590000-0000-0000-0000-000000000001','File reply','File the written reply','reply_due',today-1,'Order dated 14 September 2026','f1590000-0000-0000-0000-000000000001');
 IF r.code<>'ok' OR NOT r.replayed OR r.deadline_id<>deadline THEN RAISE EXCEPTION 'exact replay failed'; END IF;
 SELECT * INTO r FROM public.create_manual_legal_deadline('d1590000-0000-0000-0000-000000000001','Different title','File the written reply','reply_due',today-1,'Order dated 14 September 2026','f1590000-0000-0000-0000-000000000001');
 IF r.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'payload mismatch not rejected'; END IF;
 SELECT * INTO agenda FROM public.read_matter_manual_legal_deadline_agenda('d1590000-0000-0000-0000-000000000001',50); item:=agenda.items->0;
 IF agenda.timezone<>'Pacific/Kiritimati' OR item->>'temporal'<>'missed' OR item->>'verification_state'<>'verified' OR item->>'origin'<>'manual' OR NOT agenda.can_mutate THEN RAISE EXCEPTION 'timezone agenda failed %',agenda.items; END IF;
 SELECT * INTO r FROM public.amend_manual_legal_deadline(deadline,1,'File amended reply','File the revised written reply','reply_due',today,'Registry instruction','Corrected after registry clarification','f1590000-0000-0000-0000-000000000002');
 IF r.code<>'ok' OR r.revision<>2 THEN RAISE EXCEPTION 'amend failed'; END IF;
 SELECT * INTO agenda FROM public.read_matter_manual_legal_deadline_agenda('d1590000-0000-0000-0000-000000000001',50);
 SELECT value INTO item FROM jsonb_array_elements(agenda.items) value WHERE value->>'id'=deadline::text;
 IF item->>'manual_basis'<>'Registry instruction' OR item->'history'->1->>'actor_label'<>'Deadline Owner' OR (item->'history'->1 ? 'actor_user_id') THEN RAISE EXCEPTION 'current basis or safe actor projection failed %',item; END IF;
 SELECT * INTO r FROM public.amend_manual_legal_deadline(deadline,2,'File amended reply','File the revised written reply','reply_due',today,'Registry instruction updated','Preserved and refined the current basis','f1590000-0000-0000-0000-000000000008');
 IF r.code<>'ok' OR r.revision<>3 THEN RAISE EXCEPTION 'second amend failed'; END IF;
 SELECT * INTO agenda FROM public.read_matter_manual_legal_deadline_agenda('d1590000-0000-0000-0000-000000000001',50);
 SELECT value INTO item FROM jsonb_array_elements(agenda.items) value WHERE value->>'id'=deadline::text;
 IF item->>'manual_basis'<>'Registry instruction updated' THEN RAISE EXCEPTION 'second amend basis did not round-trip %',item; END IF;
 SELECT * INTO r FROM public.amend_manual_legal_deadline(deadline,1,'Stale','Stale obligation','reply_due',today,'Stale basis','Stale reason','f1590000-0000-0000-0000-000000000003');
 IF r.code<>'stale_revision' THEN RAISE EXCEPTION 'stale amend not rejected'; END IF;
 SELECT * INTO r FROM public.record_manual_legal_deadline_outcome(deadline,3,'satisfied','Filed at registry','f1590000-0000-0000-0000-000000000004');
 IF r.code<>'ok' OR r.revision<>4 THEN RAISE EXCEPTION 'satisfy failed'; END IF;
 SELECT * INTO r FROM public.record_manual_legal_deadline_outcome(deadline,3,'satisfied','Filed at registry','f1590000-0000-0000-0000-000000000004');
 IF r.code<>'ok' OR NOT r.replayed THEN RAISE EXCEPTION 'outcome replay failed'; END IF;
 SELECT * INTO agenda FROM public.read_matter_manual_legal_deadline_agenda('d1590000-0000-0000-0000-000000000001',50);
 SELECT value INTO item FROM jsonb_array_elements(agenda.items) value WHERE value->>'id'=deadline::text;
 IF item->>'lifecycle'<>'satisfied' OR jsonb_array_length(item->'history')<>4 THEN RAISE EXCEPTION 'history not preserved %',item; END IF;
 SELECT * INTO r FROM public.create_manual_legal_deadline('d1590000-0000-0000-0000-000000000001','Cancelled filing','Do not file after withdrawal','other_legal',today,'Written client withdrawal','f1590000-0000-0000-0000-000000000005');
 deadline:=r.deadline_id;
 SELECT * INTO r FROM public.record_manual_legal_deadline_outcome(deadline,1,'cancelled','Client withdrew the proposed filing','f1590000-0000-0000-0000-000000000006');
 IF r.code<>'ok' OR r.revision<>2 THEN RAISE EXCEPTION 'cancel failed'; END IF;
 SELECT * INTO agenda FROM public.read_matter_manual_legal_deadline_agenda('d1590000-0000-0000-0000-000000000001',50);
 SELECT value INTO item FROM jsonb_array_elements(agenda.items) value WHERE value->>'id'=deadline::text;
 IF item->>'lifecycle'<>'cancelled' OR item->>'temporal'<>'due_today' OR jsonb_array_length(item->'history')<>2 THEN RAISE EXCEPTION 'cancel history failed %',item; END IF;
 SELECT * INTO r FROM public.create_manual_legal_deadline('d1590000-0000-0000-0000-000000000001','Serve evidence','Serve the verified evidence bundle','compliance_due',today+7,'Procedural order checked by the matter team','f1590000-0000-0000-0000-000000000007');
 IF r.code<>'ok' THEN RAISE EXCEPTION 'due-soon setup failed %',r.code; END IF;
 deadline:=r.deadline_id;
 SELECT * INTO agenda FROM public.read_matter_manual_legal_deadline_agenda('d1590000-0000-0000-0000-000000000001',50);
 SELECT value INTO item FROM jsonb_array_elements(agenda.items) value WHERE value->>'id'=deadline::text;
 IF item->>'temporal'<>'due_soon' THEN RAISE EXCEPTION 'due-soon boundary failed %',item; END IF;
END $owner_flow$;

DO $lineage_denials$ DECLARE r record; matter uuid; BEGIN
 FOREACH matter IN ARRAY ARRAY['d1590000-0000-0000-0000-000000000002'::uuid,'d1590000-0000-0000-0000-000000000003'::uuid,'d1590000-0000-0000-0000-000000000004'::uuid,'d1590000-0000-0000-0000-000000000005'::uuid] LOOP
  SELECT * INTO r FROM public.create_manual_legal_deadline(matter,'Denied date','Denied obligation','other_legal',current_date,'Manual basis',gen_random_uuid());
  IF r.code<>'not_allowed' THEN RAISE EXCEPTION 'lineage denial failed % %',matter,r.code; END IF;
 END LOOP;
END $lineage_denials$;

SELECT set_config('request.jwt.claim.sub','a1590000-0000-0000-0000-000000000002',true);
DO $admin$ DECLARE r record; BEGIN SELECT * INTO r FROM public.create_manual_legal_deadline('d1590000-0000-0000-0000-000000000001','Admin date','Admin obligation','other_legal',current_date+9,'Written court notice','f1590000-0000-0000-0000-000000000012'); IF r.code<>'ok' THEN RAISE EXCEPTION 'admin denied'; END IF; END $admin$;
SELECT set_config('request.jwt.claim.sub','a1590000-0000-0000-0000-000000000003',true);
DO $associate$ DECLARE r record; BEGIN SELECT * INTO r FROM public.create_manual_legal_deadline('d1590000-0000-0000-0000-000000000001','Associate date','Associate obligation','compliance_due',current_date+8,'Written client instruction','f1590000-0000-0000-0000-000000000010'); IF r.code<>'ok' THEN RAISE EXCEPTION 'associate denied'; END IF; END $associate$;
SELECT set_config('request.jwt.claim.sub','a1590000-0000-0000-0000-000000000004',true);
DO $viewer$ DECLARE r record; agenda record; BEGIN SELECT * INTO agenda FROM public.read_matter_manual_legal_deadline_agenda('d1590000-0000-0000-0000-000000000001',50); IF agenda.can_mutate OR jsonb_array_length(agenda.items)<>5 THEN RAISE EXCEPTION 'viewer read failed'; END IF; SELECT * INTO r FROM public.create_manual_legal_deadline('d1590000-0000-0000-0000-000000000001','Viewer date','Viewer obligation','other_legal',current_date,'Viewer basis','f1590000-0000-0000-0000-000000000011'); IF r.code<>'not_allowed' THEN RAISE EXCEPTION 'viewer mutated'; END IF; END $viewer$;
SELECT set_config('request.jwt.claim.sub','a1590000-0000-0000-0000-000000000005',true);
DO $suspended$ DECLARE r record; BEGIN SELECT * INTO r FROM public.read_matter_manual_legal_deadline_agenda('d1590000-0000-0000-0000-000000000001',50); IF r.items IS NOT NULL THEN RAISE EXCEPTION 'suspended read'; END IF; END $suspended$;
SELECT set_config('request.jwt.claim.sub','a1590000-0000-0000-0000-000000000007',true);
DO $absent$ DECLARE r record; BEGIN SELECT * INTO r FROM public.read_matter_manual_legal_deadline_agenda('d1590000-0000-0000-0000-000000000001',50); IF r.items IS NOT NULL THEN RAISE EXCEPTION 'absent read'; END IF; END $absent$;

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1590000-0000-0000-0000-000000000003',true);
DO $direct_write_denied$ DECLARE denied boolean:=false; BEGIN
 BEGIN INSERT INTO public.deadlines(org_id,matter_id,type,due_date,description,title,legal_type,origin,verification_state,lifecycle,current_revision,created_by) VALUES('b1590000-0000-0000-0000-000000000001','d1590000-0000-0000-0000-000000000001','other',current_date,'Direct write','Direct write','other_legal','manual','verified','open',1,'a1590000-0000-0000-0000-000000000003'); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'direct table write succeeded'; END IF;
END $direct_write_denied$;
RESET ROLE;

-- Corrupt duplicate current membership must fail closed even when uniqueness is temporarily removed in this rollback-only fixture.
DROP INDEX public.organisation_memberships_one_current_org_per_user;
INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation) VALUES('b1590000-0000-0000-0000-000000000002','a1590000-0000-0000-0000-000000000003','associate','active',2);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','a1590000-0000-0000-0000-000000000003',true);
DO $duplicate$ DECLARE r record; BEGIN SELECT * INTO r FROM public.read_matter_manual_legal_deadline_agenda('d1590000-0000-0000-0000-000000000001',50); IF r.items IS NOT NULL THEN RAISE EXCEPTION 'duplicate membership did not fail closed'; END IF; END $duplicate$;
RESET ROLE;

ROLLBACK;
SELECT 'manual legal deadline fixture passed' AS result;
