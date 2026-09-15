-- Immediate, governed suspension of an ordinary organisation member.
BEGIN;

CREATE TABLE public.organisation_membership_suspension_receipts (
  idempotency_key uuid PRIMARY KEY,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  target_membership_id uuid NOT NULL REFERENCES public.organisation_memberships(id) ON DELETE RESTRICT,
  request_fingerprint text NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  result_code text NOT NULL CHECK (result_code = 'suspended'),
  returned_task_count integer NOT NULL CHECK (returned_task_count >= 0),
  result_revision bigint NOT NULL CHECK (result_revision >= 2),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.organisation_membership_suspension_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organisation_membership_suspension_receipts FORCE ROW LEVEL SECURITY;

ALTER TABLE public.task_transition_history
  DROP CONSTRAINT task_transition_history_command_check,
  ADD CONSTRAINT task_transition_history_command_check CHECK (command IN (
    'start','complete','reopen','cancel','set_assignee','set_due_date','clear_due_date',
    'return_to_team_for_member_suspension'
  ));

-- Every Task writer must fence an assignee's canonical lifecycle row. This
-- closes the inverse race where another administrator assigns new work after
-- suspension has locked the target but before it has scanned their Tasks.
CREATE FUNCTION public.task_assignee_must_be_active()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public
AS $$
DECLARE assignee record;
BEGIN
  IF NEW.assignee_user_id IS NULL THEN RETURN NEW; END IF;
  SELECT membership.id,membership.role,organisation.owner_membership_id=membership.id is_owner
    INTO assignee
  FROM public.organisation_memberships membership
  JOIN public.organisations organisation ON organisation.id=membership.org_id
  WHERE membership.org_id=NEW.org_id AND membership.user_id=NEW.assignee_user_id
    AND membership.state='active' FOR UPDATE OF membership;
  IF assignee.id IS NULL OR (assignee.role NOT IN ('admin','associate') AND NOT assignee.is_owner) THEN
    RAISE EXCEPTION 'Task assignee must be an active eligible organisation member' USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tasks_assignee_active_fence
  BEFORE INSERT OR UPDATE OF assignee_user_id ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.task_assignee_must_be_active();

CREATE FUNCTION public.get_standard_member_suspension_impact(p_target_membership_id uuid)
RETURNS TABLE(
  code text,target_membership_id uuid,target_revision bigint,target_user_id uuid,
  target_display_name text,target_role public.org_member_role,open_task_count integer,
  task_disposition text,verified_deadlines_applicable boolean,review_claims_applicable boolean,
  invitation_governance_applicable boolean,digest_grants_applicable boolean,
  internal_expense_grants_applicable boolean
)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path=pg_catalog,public
AS $$
DECLARE actor record; target record; v_owner boolean:=false;
BEGIN
  IF auth.uid() IS NULL OR p_target_membership_id IS NULL THEN
    RETURN QUERY SELECT 'invalid_request',NULL::uuid,NULL::bigint,NULL::uuid,NULL::text,NULL::public.org_member_role,NULL::integer,NULL::text,false,false,false,false,false;
    RETURN;
  END IF;
  SELECT current.membership_id,current.org_id,current.role INTO actor
  FROM public.current_active_tenant_membership() current;
  IF actor.membership_id IS NULL THEN
    RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,NULL::uuid,NULL::text,NULL::public.org_member_role,NULL::integer,NULL::text,false,false,false,false,false;
    RETURN;
  END IF;
  SELECT organisation.owner_membership_id=actor.membership_id INTO v_owner
  FROM public.organisations organisation WHERE organisation.id=actor.org_id;
  IF NOT ('team.membership.suspend_standard'=ANY(public.organisation_member_capabilities(actor.role,coalesce(v_owner,false),'active'))) THEN
    RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,NULL::uuid,NULL::text,NULL::public.org_member_role,NULL::integer,NULL::text,false,false,false,false,false;
    RETURN;
  END IF;
  SELECT membership.id,membership.revision,membership.user_id,membership.role,
    coalesce(nullif(btrim(profile.display_name),''),'Team member') display_name
  INTO target
  FROM public.organisation_memberships membership
  LEFT JOIN public.user_profiles profile ON profile.user_id=membership.user_id
  WHERE membership.id=p_target_membership_id AND membership.org_id=actor.org_id
    AND membership.state='active' AND membership.role IN ('associate','viewer')
    AND membership.id<>actor.membership_id;
  IF target.id IS NULL THEN
    RETURN QUERY SELECT 'not_available',NULL::uuid,NULL::bigint,NULL::uuid,NULL::text,NULL::public.org_member_role,NULL::integer,NULL::text,false,false,false,false,false;
    RETURN;
  END IF;
  RETURN QUERY SELECT 'ok',target.id,target.revision,target.user_id,target.display_name,target.role,
    (SELECT count(*)::integer FROM public.tasks task WHERE task.org_id=actor.org_id
      AND task.assignee_user_id=target.user_id AND task.lifecycle_state='active'
      AND task.status IN ('open','in_progress')),
    'return_open_tasks_to_team'::text,
    false,false,false,false,false;
END $$;

CREATE FUNCTION public.suspend_standard_organisation_member(
  p_target_membership_id uuid,p_expected_revision bigint,p_reason text,
  p_task_disposition text,p_idempotency_key uuid
)
RETURNS TABLE(code text,target_membership_id uuid,target_revision bigint,returned_task_count integer,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public
AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_actor_row public.organisation_memberships%ROWTYPE;
  v_target public.organisation_memberships%ROWTYPE; v_owner boolean:=false;
  v_reason text:=nullif(btrim(p_reason),''); v_fingerprint text; v_receipt public.organisation_membership_suspension_receipts%ROWTYPE;
  v_task public.tasks%ROWTYPE; v_count integer:=0; v_history_key uuid; v_activity_key text; v_correlation uuid:=gen_random_uuid();
BEGIN
  IF v_actor IS NULL OR p_target_membership_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1
     OR p_idempotency_key IS NULL OR p_task_disposition<>'return_open_tasks_to_team'
     OR v_reason IS NULL OR char_length(v_reason)<3 OR char_length(v_reason)>500 OR v_reason~'[[:cntrl:]]' THEN
    RETURN QUERY SELECT 'invalid_request',NULL::uuid,NULL::bigint,NULL::integer,false; RETURN;
  END IF;
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'actor_user_id',v_actor,'target_membership_id',p_target_membership_id,'expected_revision',p_expected_revision,
    'reason',v_reason,'task_disposition',p_task_disposition)::text,'utf8'),'sha256'),'hex');
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,161));
  SELECT * INTO v_receipt FROM public.organisation_membership_suspension_receipts receipt WHERE receipt.idempotency_key=p_idempotency_key;
  IF v_receipt.idempotency_key IS NOT NULL THEN
    IF v_receipt.actor_user_id<>v_actor OR v_receipt.target_membership_id<>p_target_membership_id OR v_receipt.request_fingerprint<>v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_subject_mismatch',NULL::uuid,NULL::bigint,NULL::integer,false;
    ELSE
      RETURN QUERY SELECT v_receipt.result_code,v_receipt.target_membership_id,v_receipt.result_revision,v_receipt.returned_task_count,true;
    END IF;
    RETURN;
  END IF;
  SELECT membership.* INTO v_actor_row FROM public.organisation_memberships membership
  WHERE membership.user_id=v_actor AND membership.state IN ('active','suspended') FOR UPDATE;
  IF NOT FOUND OR v_actor_row.state<>'active' OR
     (SELECT count(*) FROM public.organisation_memberships membership WHERE membership.user_id=v_actor AND membership.state IN ('active','suspended'))<>1 THEN
    RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,NULL::integer,false; RETURN;
  END IF;
  SELECT organisation.owner_membership_id=v_actor_row.id INTO v_owner FROM public.organisations organisation WHERE organisation.id=v_actor_row.org_id;
  IF NOT ('team.membership.suspend_standard'=ANY(public.organisation_member_capabilities(v_actor_row.role,coalesce(v_owner,false),v_actor_row.state))) THEN
    RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,NULL::integer,false; RETURN;
  END IF;
  SELECT membership.* INTO v_target FROM public.organisation_memberships membership WHERE membership.id=p_target_membership_id FOR UPDATE;
  IF v_target.id IS NULL OR v_target.org_id<>v_actor_row.org_id OR v_target.user_id=v_actor
     OR v_target.state<>'active' OR v_target.role NOT IN ('associate','viewer') THEN
    RETURN QUERY SELECT 'not_available',NULL::uuid,NULL::bigint,NULL::integer,false; RETURN;
  END IF;
  IF v_target.revision<>p_expected_revision THEN
    RETURN QUERY SELECT 'conflict',v_target.id,v_target.revision,NULL::integer,false; RETURN;
  END IF;
  FOR v_task IN SELECT task.* FROM public.tasks task WHERE task.org_id=v_actor_row.org_id
    AND task.assignee_user_id=v_target.user_id AND task.lifecycle_state='active'
    AND task.status IN ('open','in_progress') ORDER BY task.id FOR UPDATE
  LOOP
    UPDATE public.tasks task SET assignee_user_id=NULL,revision=task.revision+1,updated_at=now()
      WHERE task.id=v_task.id;
    v_history_key:=gen_random_uuid();
    INSERT INTO public.task_transition_history(org_id,task_id,actor_user_id,command,from_status,to_status,
      from_assignee_user_id,to_assignee_user_id,from_due_date,to_due_date,from_due_timezone,to_due_timezone,revision,idempotency_key)
    VALUES(v_task.org_id,v_task.id,v_actor,'return_to_team_for_member_suspension',v_task.status,v_task.status,
      v_task.assignee_user_id,NULL,v_task.due_date,v_task.due_date,v_task.due_timezone,v_task.due_timezone,v_task.revision+1,v_history_key);
    v_activity_key:=encode(extensions.digest(convert_to(jsonb_build_object('command','task.transitioned','task_id',v_task.id,
      'revision',v_task.revision+1,'suspension_idempotency_key',p_idempotency_key,'org_id',v_task.org_id,'actor_id',v_actor)::text,'utf8'),'sha256'),'hex');
    PERFORM public.append_activity_event(v_task.org_id,'task.transitioned',1::smallint,'user',v_actor,NULL,'task',v_task.id,
      v_task.client_id,v_task.matter_id,'Task','Task returned to the team queue',jsonb_build_object(
        'command','return_to_team_for_member_suspension','from_status',v_task.status::text,'to_status',v_task.status::text,'revision',v_task.revision+1),
      'task',v_task.id,NULL,v_correlation,NULL,v_activity_key,now());
    v_count:=v_count+1;
  END LOOP;
  UPDATE public.organisation_memberships membership SET state='suspended',suspended_at=now(),suspended_by=v_actor,
    suspension_reason=v_reason WHERE membership.id=v_target.id RETURNING * INTO v_target;
  INSERT INTO public.administration_events(org_id,event_kind,actor_user_id,target_user_id,target_snapshot,metadata,reason,correlation_id,idempotency_key)
  VALUES(v_actor_row.org_id,'organisation_membership.suspended.v1',v_actor,v_target.user_id,
    jsonb_build_object('membership_id',v_target.id,'role',v_target.role::text),jsonb_build_object('task_disposition',p_task_disposition,'returned_task_count',v_count),
    v_reason,v_correlation,p_idempotency_key);
  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata)
  VALUES(v_actor_row.org_id,v_actor,'organisation_membership.suspended','organisation',v_actor_row.org_id,
    'Team member access suspended',jsonb_build_object('target_membership_id',v_target.id,'returned_task_count',v_count));
  INSERT INTO public.organisation_membership_suspension_receipts(idempotency_key,actor_user_id,org_id,target_membership_id,
    request_fingerprint,result_code,returned_task_count,result_revision)
  VALUES(p_idempotency_key,v_actor,v_actor_row.org_id,v_target.id,v_fingerprint,'suspended',v_count,v_target.revision);
  RETURN QUERY SELECT 'suspended',v_target.id,v_target.revision,v_count,false;
END $$;

REVOKE ALL ON TABLE public.organisation_membership_suspension_receipts FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_standard_member_suspension_impact(uuid),
  public.suspend_standard_organisation_member(uuid,bigint,text,text,uuid),
  public.task_assignee_must_be_active() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_standard_member_suspension_impact(uuid),
  public.suspend_standard_organisation_member(uuid,bigint,text,text,uuid) TO authenticated;

-- Canonical lifecycle state is command-owned. Legacy identity remains readable
-- only through its active-canonical RLS bridge and cannot restore access.
REVOKE INSERT,UPDATE,DELETE ON public.org_members FROM service_role;
REVOKE INSERT,UPDATE,DELETE ON public.organisation_memberships FROM service_role;

COMMENT ON FUNCTION public.get_standard_member_suspension_impact(uuid) IS
  'Admin-only bounded impact: open Tasks are actionable; verified deadlines, Review claims, invite governance, digests and optional grants are currently non-applicable.';
COMMENT ON FUNCTION public.suspend_standard_organisation_member(uuid,bigint,text,text,uuid) IS
  'Atomically returns target open Tasks to the team and suspends one same-tenant active Associate/Viewer with CAS and actor-bound global idempotency.';
COMMIT;
