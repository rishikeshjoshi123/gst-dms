\set ON_ERROR_STOP on
BEGIN;

INSERT INTO public.tasks(id,org_id,client_id,matter_id,title,origin_kind,origin_note_id,origin_snapshot,
  creator_user_id,assignee_user_id,status,priority,lifecycle_state,status_changed_by,completed_at,completed_by)
VALUES
 ('16100000-0000-4000-8000-000000000001','b0010000-0000-0000-0000-000000000001','c0010000-0000-0000-0000-000000000001','d0010000-0000-0000-0000-000000000001','Open suspension task','case_note','16110000-0000-4000-8000-000000000001','Open suspension task','a0010000-0000-0000-0000-000000000001','a0010000-0000-0000-0000-000000000006','open','normal','active','a0010000-0000-0000-0000-000000000001',NULL,NULL),
 ('16100000-0000-4000-8000-000000000002','b0010000-0000-0000-0000-000000000001','c0010000-0000-0000-0000-000000000001','d0010000-0000-0000-0000-000000000001','Progress suspension task','case_note','16110000-0000-4000-8000-000000000002','Progress suspension task','a0010000-0000-0000-0000-000000000001','a0010000-0000-0000-0000-000000000006','in_progress','high','active','a0010000-0000-0000-0000-000000000001',NULL,NULL),
 ('16100000-0000-4000-8000-000000000003','b0010000-0000-0000-0000-000000000001','c0010000-0000-0000-0000-000000000001','d0010000-0000-0000-0000-000000000001','Completed preserved task','case_note','16110000-0000-4000-8000-000000000003','Completed preserved task','a0010000-0000-0000-0000-000000000001','a0010000-0000-0000-0000-000000000006','completed','normal','active','a0010000-0000-0000-0000-000000000001',now(),'a0010000-0000-0000-0000-000000000001'),
 ('16100000-0000-4000-8000-000000000004','b0010000-0000-0000-0000-000000000001','c0010000-0000-0000-0000-000000000001','d0010000-0000-0000-0000-000000000001','Replay assignment task','case_note','16110000-0000-4000-8000-000000000004','Replay assignment task','a0010000-0000-0000-0000-000000000001',NULL,'open','normal','active','a0010000-0000-0000-0000-000000000001',NULL,NULL);

INSERT INTO public.notifications(id,org_id,user_id,type,title,body)
VALUES('16130000-0000-4000-8000-000000000001','b0010000-0000-0000-0000-000000000001','a0010000-0000-0000-0000-000000000006','mention','Private notification','Must disappear on suspension');

SELECT set_config('casechain.target_associate_membership',(SELECT id::text FROM public.organisation_memberships WHERE user_id='a0010000-0000-0000-0000-000000000006' AND state='active'),true);
SELECT set_config('casechain.target_viewer_membership',(SELECT id::text FROM public.organisation_memberships WHERE user_id='a0010000-0000-0000-0000-000000000002' AND state='active'),true);
SELECT set_config('casechain.actor_admin_membership',(SELECT id::text FROM public.organisation_memberships WHERE user_id='a0010000-0000-0000-0000-000000000004' AND state='active'),true);
SELECT set_config('casechain.actor_owner_membership',(SELECT id::text FROM public.organisation_memberships WHERE user_id='a0010000-0000-0000-0000-000000000001' AND state='active'),true);
SELECT set_config('casechain.foreign_membership',(SELECT id::text FROM public.organisation_memberships WHERE user_id='a0010000-0000-0000-0000-000000000003' AND state='active'),true);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);

-- Ordinary and suspended callers cannot inspect or execute administration.
SELECT set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000002',true);
DO $$ DECLARE r record; target uuid; BEGIN
 target:=current_setting('casechain.target_associate_membership')::uuid;
 SELECT * INTO r FROM public.get_standard_member_suspension_impact(target); IF r.code<>'not_allowed' THEN RAISE EXCEPTION 'viewer impact outcome %',r.code; END IF;
 SELECT * INTO r FROM public.suspend_standard_organisation_member(target,1,'Viewer cannot suspend','return_open_tasks_to_team',repeat('0',64),'16120000-0000-4000-8000-000000000001'); IF r.code<>'not_allowed' THEN RAISE EXCEPTION 'viewer command allowed'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000005',true);
DO $$ DECLARE r record; target uuid:=current_setting('casechain.target_associate_membership')::uuid; BEGIN SELECT * INTO r FROM public.suspend_standard_organisation_member(target,1,'Suspended cannot suspend','return_open_tasks_to_team',repeat('0',64),'16120000-0000-4000-8000-000000000002'); IF r.code<>'not_allowed' THEN RAISE EXCEPTION 'suspended command allowed'; END IF; END $$;

-- Admin cannot target self, another Admin/Owner, foreign members, or stale state.
SELECT set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000004',true);
DO $$ DECLARE r record; impact record; own_id uuid; owner_id uuid; foreign_id uuid; target uuid; rev bigint; BEGIN
 own_id:=current_setting('casechain.actor_admin_membership')::uuid;
 owner_id:=current_setting('casechain.actor_owner_membership')::uuid;
 foreign_id:=current_setting('casechain.foreign_membership')::uuid;
 target:=current_setting('casechain.target_associate_membership')::uuid; SELECT * INTO impact FROM public.get_standard_member_suspension_impact(target); rev:=impact.target_revision;
 SELECT * INTO r FROM public.suspend_standard_organisation_member(own_id,1,'Self denied','return_open_tasks_to_team',repeat('0',64),'16120000-0000-4000-8000-000000000003'); IF r.code<>'not_available' THEN RAISE EXCEPTION 'self allowed'; END IF;
 SELECT * INTO r FROM public.suspend_standard_organisation_member(owner_id,1,'Owner denied','return_open_tasks_to_team',repeat('0',64),'16120000-0000-4000-8000-000000000004'); IF r.code<>'not_available' THEN RAISE EXCEPTION 'owner allowed'; END IF;
 SELECT * INTO r FROM public.suspend_standard_organisation_member(foreign_id,1,'Foreign denied','return_open_tasks_to_team',repeat('0',64),'16120000-0000-4000-8000-000000000005'); IF r.code<>'not_available' THEN RAISE EXCEPTION 'foreign allowed'; END IF;
 SELECT * INTO r FROM public.suspend_standard_organisation_member(target,rev+1,'Stale denied','return_open_tasks_to_team',impact.task_impact_fingerprint,'16120000-0000-4000-8000-000000000006'); IF r.code<>'conflict' THEN RAISE EXCEPTION 'stale accepted'; END IF;
END $$;

-- A Task revision change invalidates preview even when membership revision is unchanged.
SELECT set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000001',true);
DO $$ DECLARE impact record; result record; target uuid:=current_setting('casechain.target_associate_membership')::uuid; BEGIN
 SELECT * INTO impact FROM public.get_standard_member_suspension_impact(target);
 SELECT * INTO result FROM public.transition_task('16100000-0000-4000-8000-000000000001','set_due_date',1,'16120000-0000-4000-8000-000000000008',NULL,current_date+7);
 IF result.code<>'ok' THEN RAISE EXCEPTION 'fixture task mutation failed: %',result.code; END IF;
 SELECT * INTO result FROM public.suspend_standard_organisation_member(target,impact.target_revision,'Stale task impact','return_open_tasks_to_team',impact.task_impact_fingerprint,'16120000-0000-4000-8000-000000000007');
 IF result.code<>'impact_conflict' THEN RAISE EXCEPTION 'stale task impact accepted: %',result.code; END IF;
END $$;

-- Owner preview and command atomically return exactly the actionable Tasks.
SELECT set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000001',true);
DO $$ DECLARE impact record; result record; target uuid; rev bigint; BEGIN
 target:=current_setting('casechain.target_associate_membership')::uuid;
 SELECT * INTO result FROM public.transition_task('16100000-0000-4000-8000-000000000004','set_assignee',1,'16120000-0000-4000-8000-000000000009','a0010000-0000-0000-0000-000000000006',NULL);
 IF result.code<>'ok' OR result.replayed OR result.revision<>2 THEN RAISE EXCEPTION 'assignment fixture failed'; END IF;
 SELECT target_revision INTO rev FROM public.get_standard_member_suspension_impact(target);
 SELECT * INTO impact FROM public.get_standard_member_suspension_impact(target);
 IF impact.code<>'ok' OR impact.open_task_count<>3 OR impact.task_disposition<>'return_open_tasks_to_team'
   OR impact.verified_deadlines_applicable OR impact.review_claims_applicable OR impact.invitation_governance_applicable
   OR impact.digest_grants_applicable OR impact.internal_expense_grants_applicable THEN RAISE EXCEPTION 'impact mismatch'; END IF;
 SELECT * INTO result FROM public.suspend_standard_organisation_member(target,rev,'Security access review','return_open_tasks_to_team',impact.task_impact_fingerprint,'16120000-0000-4000-8000-000000000010');
 IF result.code<>'suspended' OR result.returned_task_count<>3 OR result.replayed THEN RAISE EXCEPTION 'owner suspension failed'; END IF;
 SELECT * INTO result FROM public.transition_task('16100000-0000-4000-8000-000000000004','set_assignee',1,'16120000-0000-4000-8000-000000000009','a0010000-0000-0000-0000-000000000006',NULL);
 IF result.code<>'ok' OR NOT result.replayed OR result.revision<>2 THEN RAISE EXCEPTION 'post-suspension assignment replay failed: %',result.code; END IF;
 SELECT * INTO result FROM public.transition_task('16100000-0000-4000-8000-000000000004','set_assignee',1,'16120000-0000-4000-8000-000000000009','a0010000-0000-0000-0000-000000000001',NULL);
 IF result.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'post-suspension assignment mismatch accepted: %',result.code; END IF;
 SELECT * INTO result FROM public.suspend_standard_organisation_member(target,rev,'Security access review','return_open_tasks_to_team',impact.task_impact_fingerprint,'16120000-0000-4000-8000-000000000010');
 IF result.code<>'suspended' OR NOT result.replayed THEN RAISE EXCEPTION 'replay failed'; END IF;
 SELECT * INTO result FROM public.suspend_standard_organisation_member(target,rev,'Changed reason','return_open_tasks_to_team',impact.task_impact_fingerprint,'16120000-0000-4000-8000-000000000010');
 IF result.code<>'idempotency_subject_mismatch' THEN RAISE EXCEPTION 'mismatch not denied'; END IF;
END $$;

-- A non-owner Admin has the same standard-member suspension capability.
SELECT set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000004',true);
DO $$ DECLARE result record; impact record; target uuid; rev bigint; BEGIN
 target:=current_setting('casechain.target_viewer_membership')::uuid; SELECT * INTO impact FROM public.get_standard_member_suspension_impact(target); rev:=impact.target_revision;
 SELECT * INTO result FROM public.suspend_standard_organisation_member(target,rev,'Administrative access review','return_open_tasks_to_team',impact.task_impact_fingerprint,'16120000-0000-4000-8000-000000000011');
 IF result.code<>'suspended' OR result.returned_task_count<>0 THEN RAISE EXCEPTION 'admin suspension failed'; END IF;
 SELECT * INTO result FROM public.transition_task('16100000-0000-4000-8000-000000000004','set_assignee',1,'16120000-0000-4000-8000-000000000009','a0010000-0000-0000-0000-000000000006',NULL);
 IF result.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'cross-actor receipt disclosed or replayed: %',result.code; END IF;
END $$;

RESET ROLE;

-- Suspension closes notification read/update immediately under the still-valid session.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','a0010000-0000-0000-0000-000000000006',true);
DO $$ DECLARE visible integer; changed integer; BEGIN
 SELECT count(*) INTO visible FROM public.notifications WHERE id='16130000-0000-4000-8000-000000000001';
 IF visible<>0 THEN RAISE EXCEPTION 'suspended notification remained visible'; END IF;
 UPDATE public.notifications SET is_read=true WHERE id='16130000-0000-4000-8000-000000000001'; GET DIAGNOSTICS changed=ROW_COUNT;
 IF changed<>0 THEN RAISE EXCEPTION 'suspended notification update succeeded'; END IF;
END $$;
RESET ROLE;

-- Neither public nor service_role can invoke the private pre-fence transition.
SET LOCAL ROLE service_role;
DO $$ BEGIN BEGIN PERFORM public.transition_task_pre_suspension_fence('16100000-0000-4000-8000-000000000001','start',1,gen_random_uuid(),NULL,NULL); RAISE EXCEPTION 'private transition executable'; EXCEPTION WHEN insufficient_privilege THEN NULL; END; END $$;
RESET ROLE;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.tasks WHERE id='16100000-0000-4000-8000-000000000001' AND assignee_user_id IS NULL AND revision=3)
    OR NOT EXISTS(SELECT 1 FROM public.tasks WHERE id='16100000-0000-4000-8000-000000000002' AND assignee_user_id IS NULL AND revision=2)
    OR NOT EXISTS(SELECT 1 FROM public.tasks WHERE id='16100000-0000-4000-8000-000000000004' AND assignee_user_id IS NULL AND revision=3) THEN RAISE EXCEPTION 'tasks not returned'; END IF;
 IF (SELECT assignee_user_id FROM public.tasks WHERE id='16100000-0000-4000-8000-000000000003') IS DISTINCT FROM 'a0010000-0000-0000-0000-000000000006'::uuid THEN RAISE EXCEPTION 'completed task changed'; END IF;
 IF (SELECT count(*) FROM public.task_transition_history WHERE task_id IN ('16100000-0000-4000-8000-000000000001','16100000-0000-4000-8000-000000000002','16100000-0000-4000-8000-000000000004') AND command='return_to_team_for_member_suspension')<>3 THEN RAISE EXCEPTION 'history missing'; END IF;
 IF (SELECT count(*) FROM public.activity_events WHERE subject_id IN ('16100000-0000-4000-8000-000000000001','16100000-0000-4000-8000-000000000002','16100000-0000-4000-8000-000000000004') AND event_type='task.transitioned' AND metadata->>'command'='return_to_team_for_member_suspension')<>3 THEN RAISE EXCEPTION 'activity missing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organisation_memberships WHERE user_id='a0010000-0000-0000-0000-000000000006' AND state='suspended' AND suspension_reason='Security access review') THEN RAISE EXCEPTION 'membership not suspended'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.administration_events WHERE event_kind='organisation_membership.suspended.v1' AND target_user_id='a0010000-0000-0000-0000-000000000006') THEN RAISE EXCEPTION 'audit missing'; END IF;
END $$;

-- Direct lifecycle mutation remains denied to both browser and service roles.
DO $$ BEGIN
 IF has_table_privilege('authenticated','public.tasks','UPDATE') OR has_table_privilege('service_role','public.tasks','UPDATE') THEN RAISE EXCEPTION 'direct Task UPDATE grant reopened'; END IF;
END $$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN BEGIN UPDATE public.organisation_memberships SET state='active' WHERE user_id='a0010000-0000-0000-0000-000000000006'; RAISE EXCEPTION 'authenticated direct update allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END; END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$ BEGIN BEGIN UPDATE public.organisation_memberships SET state='active' WHERE user_id='a0010000-0000-0000-0000-000000000006'; RAISE EXCEPTION 'service direct update allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END; END $$;
RESET ROLE;

ROLLBACK;
