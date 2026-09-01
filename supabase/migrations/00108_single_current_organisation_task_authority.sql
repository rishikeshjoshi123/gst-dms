-- One-current-organisation authority for ordinary authenticated users.
-- This expands the existing partial uniqueness fence with serialised entry
-- commands and replaces Task's former "newest membership" fallback.
BEGIN;

-- The partial unique indexes introduced by 00029 are the durable database
-- fence. Keep the names explicit so an accidental index drop is detected by
-- migration/schema verification rather than silently weakening entry paths.
CREATE UNIQUE INDEX IF NOT EXISTS organisation_memberships_current_generation_unique
  ON public.organisation_memberships (org_id, user_id)
  WHERE state IN ('active', 'suspended');
CREATE UNIQUE INDEX IF NOT EXISTS organisation_memberships_one_current_org_per_user
  ON public.organisation_memberships (user_id)
  WHERE state IN ('active', 'suspended');

-- Return a membership only when the caller has exactly one current generation
-- and it is active. A corrupt duplicate state fails closed; its identifying
-- detail is written only to privileged database logs for the repair runbook.
CREATE OR REPLACE FUNCTION public.current_active_tenant_membership()
RETURNS TABLE(membership_id uuid, org_id uuid, role public.org_member_role)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_current_count integer;
  v_active_count integer;
BEGIN
  IF v_actor IS NULL THEN
    RETURN;
  END IF;

  SELECT count(*), count(*) FILTER (WHERE membership.state = 'active')
  INTO v_current_count, v_active_count
  FROM public.organisation_memberships AS membership
  WHERE membership.user_id = v_actor
    AND membership.state IN ('active', 'suspended');

  IF v_current_count <> 1 OR v_active_count <> 1 THEN
    IF v_current_count > 1 THEN
      RAISE LOG 'organisation membership invariant violation for authenticated actor %: % current memberships', v_actor, v_current_count;
    END IF;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT membership.id, membership.org_id, membership.role
  FROM public.organisation_memberships AS membership
  WHERE membership.user_id = v_actor
    AND membership.state = 'active';
END $$;

-- Organisation creation is a command, rather than a browser table insert.
-- The per-user transaction lock gives a competing creation/accept operation a
-- deterministic safe denial instead of exposing a partial-index exception.
CREATE OR REPLACE FUNCTION public.create_organisation(
  p_name text,
  p_idempotency_key uuid DEFAULT NULL
)
RETURNS TABLE(code text, org_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_name text := nullif(btrim(p_name), '');
  v_org_id uuid;
BEGIN
  IF v_actor IS NULL OR v_name IS NULL OR char_length(v_name) < 2 OR char_length(v_name) > 200 THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid;
    RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text, 801));
  IF EXISTS (
    SELECT 1 FROM public.organisation_memberships AS membership
    WHERE membership.user_id = v_actor
      AND membership.state IN ('active', 'suspended')
  ) THEN
    RETURN QUERY SELECT 'not_available'::text, NULL::uuid;
    RETURN;
  END IF;

  INSERT INTO public.organisations (name, created_by)
  VALUES (v_name, v_actor)
  RETURNING id INTO v_org_id;

  -- handle_new_org -> org_members -> canonical membership is deliberately
  -- retained during the approved compatibility window. Verify it completed.
  IF NOT EXISTS (
    SELECT 1 FROM public.organisation_memberships AS membership
    WHERE membership.org_id = v_org_id AND membership.user_id = v_actor
      AND membership.state = 'active'
  ) THEN
    RAISE EXCEPTION 'organisation creation did not establish active membership'
      USING ERRCODE = 'integrity_constraint_violation';
  END IF;

  RETURN QUERY SELECT 'ok'::text, v_org_id;
END $$;

-- Authenticated clients must use create_organisation. The trigger remains the
-- sole legacy bridge, and direct inserts cannot race it into another tenant.
DROP POLICY IF EXISTS "org_insert" ON public.organisations;
REVOKE INSERT ON TABLE public.organisations FROM anon, authenticated;

-- Acceptance locks the same actor key as organisation creation. Removed
-- generations are intentionally ignored; active and suspended generations
-- both deny a new current membership.
CREATE OR REPLACE FUNCTION public.accept_organisation_invite(
  p_invite_id uuid DEFAULT NULL,
  p_selector_hash text DEFAULT NULL,
  p_nonce_hash text DEFAULT NULL,
  p_idempotency_key uuid DEFAULT gen_random_uuid()
)
RETURNS TABLE(code text, org_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_invite public.organisation_invites;
  v_email text;
  v_membership uuid;
  v_current_count integer := 0;
  v_active_count integer := 0;
  v_current_org uuid;
  v_current_state public.organisation_membership_state;
BEGIN
  IF v_actor IS NULL OR p_idempotency_key IS NULL
     OR ((p_invite_id IS NOT NULL)::integer + (p_selector_hash IS NOT NULL)::integer + (p_nonce_hash IS NOT NULL)::integer) <> 1 THEN
    RETURN QUERY SELECT 'not_available'::text, NULL::uuid;
    RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text, 801));
  SELECT lower(user_row.email) INTO v_email
  FROM auth.users AS user_row
  WHERE user_row.id = v_actor AND user_row.email_confirmed_at IS NOT NULL;
  IF v_email IS NULL THEN
    RETURN QUERY SELECT 'not_available'::text, NULL::uuid;
    RETURN;
  END IF;

  IF p_nonce_hash IS NOT NULL THEN
    SELECT intent.invite_id INTO p_invite_id
    FROM public.organisation_invitation_accept_intents AS intent
    WHERE intent.nonce_hash = p_nonce_hash AND intent.consumed_at IS NULL AND intent.expires_at > now()
    FOR UPDATE;
  END IF;
  IF p_selector_hash IS NOT NULL THEN
    SELECT * INTO v_invite FROM public.organisation_invites AS invite
    WHERE invite.selector_hash = p_selector_hash AND invite.state = 'pending'
    FOR UPDATE;
  ELSE
    SELECT * INTO v_invite FROM public.organisation_invites AS invite
    WHERE invite.id = p_invite_id
    FOR UPDATE;
  END IF;
  IF v_invite.id IS NULL THEN
    RETURN QUERY SELECT 'not_available'::text, NULL::uuid;
    RETURN;
  END IF;

  -- Lock every current row before examining it so a remove/suspend cannot
  -- race a Task-like authority decision in the middle of this command.
  FOR v_membership, v_current_org, v_current_state IN
    SELECT membership.id, membership.org_id, membership.state
    FROM public.organisation_memberships AS membership
    WHERE membership.user_id = v_actor
      AND membership.state IN ('active', 'suspended')
    FOR KEY SHARE
  LOOP
    v_current_count := v_current_count + 1;
    IF v_current_state = 'active' THEN
      v_active_count := v_active_count + 1;
    END IF;
  END LOOP;
  IF v_current_count > 1 THEN
    RAISE LOG 'organisation membership invariant violation during invite acceptance for actor %: % current memberships', v_actor, v_current_count;
    RETURN QUERY SELECT 'not_available'::text, NULL::uuid;
    RETURN;
  END IF;

  IF v_invite.state = 'accepted' AND v_invite.accepted_by_user_id = v_actor
     AND v_current_count = 1 AND v_active_count = 1 AND v_current_org = v_invite.org_id THEN
    RETURN QUERY SELECT 'accepted'::text, v_invite.org_id;
    RETURN;
  END IF;
  IF v_invite.state <> 'pending' OR v_invite.expires_at <= now() OR v_email <> v_invite.normalized_email
     OR v_current_count <> 0 THEN
    RETURN QUERY SELECT 'not_available'::text, NULL::uuid;
    RETURN;
  END IF;

  INSERT INTO public.org_members (org_id, user_id, role)
  VALUES (v_invite.org_id, v_actor, v_invite.role)
  ON CONFLICT ON CONSTRAINT org_members_pkey DO NOTHING;
  SELECT membership.id INTO v_membership
  FROM public.organisation_memberships AS membership
  WHERE membership.org_id = v_invite.org_id AND membership.user_id = v_actor
    AND membership.state = 'active';
  IF v_membership IS NULL THEN
    RETURN QUERY SELECT 'not_available'::text, NULL::uuid;
    RETURN;
  END IF;

  UPDATE public.organisation_invites AS invite
  SET state = 'accepted', selector_hash = NULL, accepted_at = now(),
      accepted_by_user_id = v_actor, accepted_membership_id = v_membership,
      lifecycle_actor_id = v_actor
  WHERE invite.id = v_invite.id;
  IF p_nonce_hash IS NOT NULL THEN
    UPDATE public.organisation_invitation_accept_intents AS intent
    SET consumed_at = now() WHERE intent.nonce_hash = p_nonce_hash;
  END IF;
  INSERT INTO public.organisation_invitation_command_receipts(
    actor_user_id, idempotency_key, command_kind, invite_id, result_code, result_org_id
  ) VALUES (v_actor, p_idempotency_key, 'accept', v_invite.id, 'accepted', v_invite.org_id)
  ON CONFLICT (actor_user_id, idempotency_key) DO NOTHING;
  PERFORM public.invitation_event(v_invite.org_id, 'organisation_invitation.accepted.v1', v_actor, v_actor, NULL, v_invite.correlation_id, p_idempotency_key);
  RETURN QUERY SELECT 'accepted'::text, v_invite.org_id;
END $$;

-- Task readers derive their tenant from the exact-active helper. No reader
-- accepts a tenant parameter or makes a recency-based membership choice.
CREATE OR REPLACE FUNCTION public.get_my_tasks(
  p_statuses public.task_status[] DEFAULT NULL,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(task_id uuid, client_id uuid, matter_id uuid, document_id uuid, title text,
  priority public.task_priority, status public.task_status, assignee_user_id uuid,
  due_date date, due_time time without time zone, due_timezone text, revision bigint,
  created_at timestamptz, updated_at timestamptz, origin_available boolean)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
DECLARE v_org uuid;
BEGIN
  IF auth.uid() IS NULL OR p_limit IS NULL OR p_offset IS NULL OR p_limit < 1 OR p_limit > 200 OR p_offset < 0 THEN RETURN; END IF;
  SELECT current_membership.org_id INTO v_org FROM public.current_active_tenant_membership() AS current_membership;
  IF v_org IS NULL THEN RETURN; END IF;
  RETURN QUERY SELECT task.id,task.client_id,task.matter_id,task.document_id,task.title,task.priority,task.status,task.assignee_user_id,task.due_date,task.due_time,task.due_timezone,task.revision,task.created_at,task.updated_at,
    EXISTS(SELECT 1 FROM public.case_notes AS note WHERE note.id=task.origin_note_id AND note.org_id=task.org_id AND note.matter_id=task.matter_id AND note.deleted_at IS NULL)
  FROM public.tasks AS task
  JOIN public.clients AS client ON client.id=task.client_id AND client.org_id=task.org_id AND client.record_state='active' AND client.deleted_at IS NULL
  JOIN public.matters AS matter ON matter.id=task.matter_id AND matter.org_id=task.org_id AND matter.client_id=task.client_id AND matter.record_state='active' AND matter.deleted_at IS NULL
  LEFT JOIN public.documents AS document ON document.id=task.document_id AND document.org_id=task.org_id AND document.matter_id=task.matter_id AND document.record_state='active' AND document.deleted_at IS NULL
  WHERE task.org_id=v_org AND task.lifecycle_state='active' AND (task.document_id IS NULL OR document.id IS NOT NULL) AND (p_statuses IS NULL OR task.status=ANY(p_statuses))
  ORDER BY task.due_date NULLS LAST,task.priority DESC,task.created_at DESC,task.id LIMIT p_limit OFFSET p_offset;
END $$;

CREATE OR REPLACE FUNCTION public.get_task_detail(p_task_id uuid)
RETURNS TABLE(task_id uuid, client_id uuid, matter_id uuid, document_id uuid, title text, description text,
  creator_user_id uuid, assignee_user_id uuid, priority public.task_priority, status public.task_status,
  due_date date, due_time time without time zone, due_timezone text, revision bigint, status_changed_at timestamptz,
  completed_at timestamptz, completed_by uuid, created_at timestamptz, updated_at timestamptz,
  origin_note_id uuid, origin_available boolean)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
DECLARE v_org uuid;
BEGIN
  IF auth.uid() IS NULL OR p_task_id IS NULL THEN RETURN; END IF;
  SELECT current_membership.org_id INTO v_org FROM public.current_active_tenant_membership() AS current_membership;
  IF v_org IS NULL THEN RETURN; END IF;
  RETURN QUERY SELECT task.id,task.client_id,task.matter_id,task.document_id,task.title,task.description,task.creator_user_id,task.assignee_user_id,task.priority,task.status,task.due_date,task.due_time,task.due_timezone,task.revision,task.status_changed_at,task.completed_at,task.completed_by,task.created_at,task.updated_at,
    CASE WHEN note.id IS NULL THEN NULL::uuid ELSE note.id END,note.id IS NOT NULL
  FROM public.tasks AS task
  JOIN public.clients AS client ON client.id=task.client_id AND client.org_id=task.org_id AND client.record_state='active' AND client.deleted_at IS NULL
  JOIN public.matters AS matter ON matter.id=task.matter_id AND matter.org_id=task.org_id AND matter.client_id=task.client_id AND matter.record_state='active' AND matter.deleted_at IS NULL
  LEFT JOIN public.documents AS document ON document.id=task.document_id AND document.org_id=task.org_id AND document.matter_id=task.matter_id AND document.record_state='active' AND document.deleted_at IS NULL
  LEFT JOIN public.case_notes AS note ON note.id=task.origin_note_id AND note.org_id=task.org_id AND note.matter_id=task.matter_id AND note.deleted_at IS NULL
  WHERE task.id=p_task_id AND task.org_id=v_org AND task.lifecycle_state='active' AND (task.document_id IS NULL OR document.id IS NOT NULL);
END $$;

CREATE OR REPLACE FUNCTION public.get_note_task_summaries(p_note_ids uuid[] DEFAULT NULL)
RETURNS TABLE(note_id uuid, task_id uuid, status public.task_status, assignee_user_id uuid, due_date date,
  due_time time without time zone, due_timezone text, revision bigint)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
DECLARE v_org uuid;
BEGIN
  IF auth.uid() IS NULL OR p_note_ids IS NULL OR cardinality(p_note_ids)=0 OR cardinality(p_note_ids)>500 THEN RETURN; END IF;
  SELECT current_membership.org_id INTO v_org FROM public.current_active_tenant_membership() AS current_membership;
  IF v_org IS NULL THEN RETURN; END IF;
  RETURN QUERY SELECT note.id,task.id,task.status,task.assignee_user_id,task.due_date,task.due_time,task.due_timezone,task.revision
  FROM public.case_notes AS note JOIN public.tasks AS task ON task.org_id=note.org_id AND task.origin_kind='case_note' AND task.origin_note_id=note.id
  JOIN public.clients AS client ON client.id=task.client_id AND client.org_id=task.org_id AND client.record_state='active' AND client.deleted_at IS NULL
  JOIN public.matters AS matter ON matter.id=task.matter_id AND matter.org_id=task.org_id AND matter.client_id=task.client_id AND matter.record_state='active' AND matter.deleted_at IS NULL
  LEFT JOIN public.documents AS document ON document.id=task.document_id AND document.org_id=task.org_id AND document.matter_id=task.matter_id AND document.record_state='active' AND document.deleted_at IS NULL
  WHERE note.org_id=v_org AND note.id=ANY(p_note_ids) AND note.deleted_at IS NULL AND note.matter_id=task.matter_id AND task.lifecycle_state='active' AND (task.document_id IS NULL OR document.id IS NOT NULL);
END $$;

CREATE OR REPLACE FUNCTION public.get_task_transition_history(p_task_id uuid)
RETURNS TABLE(transition_id uuid, command text, actor_user_id uuid, from_status public.task_status, to_status public.task_status,
  from_assignee_user_id uuid, to_assignee_user_id uuid, from_due_date date, to_due_date date,
  from_due_timezone text, to_due_timezone text, revision bigint, occurred_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
DECLARE v_org uuid;
BEGIN
  IF auth.uid() IS NULL OR p_task_id IS NULL THEN RETURN; END IF;
  SELECT current_membership.org_id INTO v_org FROM public.current_active_tenant_membership() AS current_membership;
  IF v_org IS NULL OR NOT EXISTS(SELECT 1 FROM public.get_task_detail(p_task_id)) THEN RETURN; END IF;
  RETURN QUERY SELECT history.id,history.command,history.actor_user_id,history.from_status,history.to_status,history.from_assignee_user_id,history.to_assignee_user_id,history.from_due_date,history.to_due_date,history.from_due_timezone,history.to_due_timezone,history.revision,history.occurred_at
  FROM public.task_transition_history AS history WHERE history.task_id=p_task_id AND history.org_id=v_org ORDER BY history.revision ASC;
END $$;

-- Task-only support projection. It avoids the cookie and service-role browser
-- path while retaining the current workspace's member/assignment affordance.
CREATE OR REPLACE FUNCTION public.get_task_workspace_members()
RETURNS TABLE(current_user_id uuid, can_manage boolean, member_user_id uuid, display_name text, can_be_assigned boolean)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
DECLARE v_org uuid; v_membership uuid; v_role public.org_member_role; v_can_manage boolean;
BEGIN
  SELECT current_membership.membership_id,current_membership.org_id,current_membership.role INTO v_membership,v_org,v_role FROM public.current_active_tenant_membership() AS current_membership;
  IF v_org IS NULL THEN RETURN; END IF;
  v_can_manage := v_role <> 'viewer' OR EXISTS(SELECT 1 FROM public.organisations AS organisation WHERE organisation.id=v_org AND organisation.owner_membership_id=v_membership);
  RETURN QUERY SELECT auth.uid(),v_can_manage,membership.user_id,COALESCE(NULLIF(btrim(profile.display_name),''),'Team member'),
    membership.role IN ('admin','associate') OR organisation.owner_membership_id=membership.id
  FROM public.organisation_memberships AS membership
  JOIN public.organisations AS organisation ON organisation.id=membership.org_id
  LEFT JOIN public.user_profiles AS profile ON profile.user_id=membership.user_id
  WHERE membership.org_id=v_org AND membership.state='active';
END $$;

-- Transition needs a keyed membership lock (readers do not mutate). This
-- exact-current block replaces the former ORDER BY/LIMIT authority selection.
CREATE OR REPLACE FUNCTION public.transition_task(
  p_task_id uuid,p_command text,p_expected_revision bigint,p_idempotency_key uuid,
  p_assignee_user_id uuid DEFAULT NULL,p_due_date date DEFAULT NULL
)
RETURNS TABLE(code text, task_id uuid, revision bigint, status public.task_status, replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_actor uuid := auth.uid(); v_org uuid; v_membership_id uuid; v_role public.org_member_role;
  v_current_count integer := 0; v_active_count integer := 0; v_locked_membership public.organisation_memberships%ROWTYPE;
  v_task public.tasks%ROWTYPE; v_previous public.tasks%ROWTYPE; v_receipt public.task_transition_receipts%ROWTYPE;
  v_timezone text; v_fingerprint text; v_command text := nullif(btrim(p_command), '');
  v_status public.task_status; v_assignee uuid; v_due_date date; v_due_timezone text; v_status_changed boolean := false;
BEGIN
  IF v_actor IS NULL OR p_task_id IS NULL OR p_idempotency_key IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1 OR v_command IS NULL OR v_command NOT IN ('start','complete','reopen','cancel','set_assignee','set_due_date','clear_due_date') THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::bigint,NULL::public.task_status,false; RETURN; END IF;
  IF (v_command='set_assignee' AND p_assignee_user_id IS NULL) OR (v_command='set_due_date' AND p_due_date IS NULL) OR (v_command IN ('start','complete','reopen','cancel','clear_due_date') AND (p_assignee_user_id IS NOT NULL OR p_due_date IS NOT NULL)) THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::bigint,NULL::public.task_status,false; RETURN; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,100));
  FOR v_locked_membership IN SELECT * FROM public.organisation_memberships AS membership WHERE membership.user_id=v_actor AND membership.state IN ('active','suspended') FOR KEY SHARE LOOP
    v_current_count:=v_current_count+1;
    IF v_locked_membership.state='active' THEN v_active_count:=v_active_count+1; v_org:=v_locked_membership.org_id; v_membership_id:=v_locked_membership.id; v_role:=v_locked_membership.role; END IF;
  END LOOP;
  IF v_current_count<>1 OR v_active_count<>1 THEN
    IF v_current_count>1 THEN RAISE LOG 'organisation membership invariant violation during Task transition for actor %: % current memberships',v_actor,v_current_count; END IF;
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::bigint,NULL::public.task_status,false; RETURN;
  END IF;
  IF v_role='viewer' AND NOT EXISTS(SELECT 1 FROM public.organisations AS organisation WHERE organisation.id=v_org AND organisation.owner_membership_id=v_membership_id) THEN RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::bigint,NULL::public.task_status,false; RETURN; END IF;
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object('task_id',p_task_id,'command',v_command,'expected_revision',p_expected_revision,'assignee_user_id',p_assignee_user_id,'due_date',p_due_date)::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.task_transition_receipts WHERE idempotency_key=p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id<>v_actor OR v_receipt.org_id<>v_org OR v_receipt.request_fingerprint<>v_fingerprint THEN RETURN QUERY SELECT 'idempotency_conflict'::text,NULL::uuid,NULL::bigint,NULL::public.task_status,false;
    ELSIF NOT EXISTS(SELECT 1 FROM public.tasks AS task JOIN public.clients AS client ON client.id=task.client_id AND client.org_id=task.org_id AND client.record_state='active' AND client.deleted_at IS NULL JOIN public.matters AS matter ON matter.id=task.matter_id AND matter.org_id=task.org_id AND matter.client_id=task.client_id AND matter.record_state='active' AND matter.deleted_at IS NULL LEFT JOIN public.documents AS document ON document.id=task.document_id AND document.org_id=task.org_id AND document.matter_id=task.matter_id AND document.record_state='active' AND document.deleted_at IS NULL WHERE task.id=v_receipt.task_id AND task.org_id=v_org AND task.lifecycle_state='active' AND (task.document_id IS NULL OR document.id IS NOT NULL)) THEN RETURN QUERY SELECT 'context_unavailable'::text,NULL::uuid,NULL::bigint,NULL::public.task_status,false;
    ELSE RETURN QUERY SELECT 'ok'::text,v_receipt.task_id,v_receipt.result_revision,v_receipt.result_status,true; END IF;
    RETURN;
  END IF;
  SELECT * INTO v_task FROM public.tasks AS task WHERE task.id=p_task_id AND task.org_id=v_org FOR UPDATE;
  IF v_task.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::bigint,NULL::public.task_status,false; RETURN; END IF;
  IF v_task.lifecycle_state<>'active' OR NOT EXISTS(SELECT 1 FROM public.clients AS client JOIN public.matters AS matter ON matter.id=v_task.matter_id AND matter.org_id=v_task.org_id AND matter.client_id=v_task.client_id AND matter.record_state='active' AND matter.deleted_at IS NULL WHERE client.id=v_task.client_id AND client.org_id=v_task.org_id AND client.record_state='active' AND client.deleted_at IS NULL) OR (v_task.document_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.documents AS document WHERE document.id=v_task.document_id AND document.org_id=v_task.org_id AND document.matter_id=v_task.matter_id AND document.record_state='active' AND document.deleted_at IS NULL)) THEN RETURN QUERY SELECT 'context_unavailable'::text,NULL::uuid,NULL::bigint,NULL::public.task_status,false; RETURN; END IF;
  IF v_task.revision<>p_expected_revision THEN RETURN QUERY SELECT 'conflict'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF;
  v_previous:=v_task; v_status:=v_task.status; v_assignee:=v_task.assignee_user_id; v_due_date:=v_task.due_date; v_due_timezone:=v_task.due_timezone;
  IF v_command='start' THEN IF v_task.status<>'open' THEN RETURN QUERY SELECT 'invalid_transition'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF; v_status:='in_progress';v_status_changed:=true;
  ELSIF v_command='complete' THEN IF v_task.status NOT IN ('open','in_progress') THEN RETURN QUERY SELECT 'invalid_transition'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF; v_status:='completed';v_status_changed:=true;
  ELSIF v_command='reopen' THEN IF v_task.status NOT IN ('completed','cancelled') THEN RETURN QUERY SELECT 'invalid_transition'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF; v_status:='open';v_status_changed:=true;
  ELSIF v_command='cancel' THEN IF v_task.status NOT IN ('open','in_progress') THEN RETURN QUERY SELECT 'invalid_transition'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF; v_status:='cancelled';v_status_changed:=true;
  ELSIF v_command='set_assignee' THEN IF v_task.status NOT IN ('open','in_progress') THEN RETURN QUERY SELECT 'invalid_transition'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF; IF NOT EXISTS(SELECT 1 FROM public.organisation_memberships AS assignee LEFT JOIN public.organisations AS organisation ON organisation.id=assignee.org_id WHERE assignee.org_id=v_org AND assignee.user_id=p_assignee_user_id AND assignee.state='active' AND (assignee.role IN ('admin','associate') OR organisation.owner_membership_id=assignee.id)) THEN RETURN QUERY SELECT 'invalid_assignee'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF; v_assignee:=p_assignee_user_id;
  ELSIF v_command='set_due_date' THEN IF v_task.status NOT IN ('open','in_progress') THEN RETURN QUERY SELECT 'invalid_transition'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF; SELECT settings.timezone INTO v_timezone FROM public.organisation_operational_settings AS settings WHERE settings.org_id=v_org FOR KEY SHARE; IF v_timezone IS NULL OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=v_timezone) THEN RETURN QUERY SELECT 'invalid_timezone'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF; v_due_date:=p_due_date;v_due_timezone:=v_timezone;
  ELSE IF v_task.status NOT IN ('open','in_progress') THEN RETURN QUERY SELECT 'invalid_transition'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF; v_due_date:=NULL;v_due_timezone:=NULL;
  END IF;
  UPDATE public.tasks AS task SET status=v_status,assignee_user_id=v_assignee,due_date=v_due_date,due_time=CASE WHEN v_command IN ('set_due_date','clear_due_date') THEN NULL ELSE task.due_time END,due_timezone=v_due_timezone,revision=task.revision+1,status_changed_at=CASE WHEN v_status_changed THEN now() ELSE task.status_changed_at END,status_changed_by=CASE WHEN v_status_changed THEN v_actor ELSE task.status_changed_by END,completed_at=CASE WHEN v_status='completed' THEN now() ELSE NULL END,completed_by=CASE WHEN v_status='completed' THEN v_actor ELSE NULL END,updated_at=now() WHERE task.id=v_task.id RETURNING * INTO v_task;
  INSERT INTO public.task_transition_history(org_id,task_id,actor_user_id,command,from_status,to_status,from_assignee_user_id,to_assignee_user_id,from_due_date,to_due_date,from_due_timezone,to_due_timezone,revision,idempotency_key) VALUES(v_org,v_task.id,v_actor,v_command,v_previous.status,v_task.status,v_previous.assignee_user_id,v_task.assignee_user_id,v_previous.due_date,v_task.due_date,v_previous.due_timezone,v_task.due_timezone,v_task.revision,p_idempotency_key);
  INSERT INTO public.task_transition_receipts(org_id,actor_user_id,idempotency_key,request_fingerprint,task_id,result_revision,result_status) VALUES(v_org,v_actor,p_idempotency_key,v_fingerprint,v_task.id,v_task.revision,v_task.status);
  RETURN QUERY SELECT 'ok'::text,v_task.id,v_task.revision,v_task.status,false;
END $$;

REVOKE ALL ON FUNCTION public.current_active_tenant_membership(), public.create_organisation(text,uuid), public.get_task_workspace_members() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.accept_organisation_invite(uuid,text,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_active_tenant_membership(), public.create_organisation(text,uuid), public.get_task_workspace_members(), public.accept_organisation_invite(uuid,text,text,uuid) TO authenticated;

COMMENT ON FUNCTION public.current_active_tenant_membership() IS 'Returns one tenant only for exactly one active current membership; zero, suspended, and corrupt duplicate current states fail closed.';
COMMENT ON FUNCTION public.create_organisation(text,uuid) IS 'Serialised ordinary-user organisation creation. Direct authenticated organisation inserts are forbidden.';
COMMENT ON FUNCTION public.get_task_workspace_members() IS 'Task workspace support projection derived from exactly one active membership; never from a browser organisation preference.';
COMMIT;
