-- Final authority closure for the live Notes->Task writer and Task transitions.
BEGIN;

INSERT INTO public.activity_event_definitions(
  event_type,event_version,category,subject_types,default_visibility,metadata_contract,renderer_key
) VALUES (
  'task.transitioned',1,'work',ARRAY['task'],'matter',
  '{"command":"code","from_status":"code","to_status":"code","revision":"integer"}',
  'task.transitioned'
);

-- Notes creation derives authority from the exact-active helper. The browser
-- organisation preference never participates in this command or its replay.
CREATE OR REPLACE FUNCTION public.create_note_with_optional_task(
  p_matter_id uuid,p_content text,p_template_type public.note_template_type,p_is_action_item boolean,p_idempotency_key uuid,
  p_document_id uuid DEFAULT NULL,p_action_item_assignee uuid DEFAULT NULL,p_action_item_due_date date DEFAULT NULL,
  p_parent_note_id uuid DEFAULT NULL,p_quote text DEFAULT NULL,p_page_number integer DEFAULT NULL
) RETURNS TABLE(code text,note_id uuid,task_id uuid,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_org uuid; v_actor_role public.org_member_role; v_client uuid;
  v_note public.case_notes%ROWTYPE; v_task uuid; v_receipt public.task_command_receipts%ROWTYPE;
  v_parent public.case_notes%ROWTYPE; v_timezone text; v_fingerprint text; v_title text; v_activity_idempotency_key text;
BEGIN
  IF v_actor IS NULL OR p_idempotency_key IS NULL OR p_matter_id IS NULL OR p_content IS NULL OR btrim(p_content)='' OR char_length(p_content)>20000 OR p_template_type IS NULL OR p_is_action_item IS NULL OR (p_page_number IS NOT NULL AND p_page_number<1) OR (p_quote IS NOT NULL AND char_length(p_quote)>20000) THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,false; RETURN; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,95));
  SELECT membership.org_id,membership.role INTO v_org,v_actor_role FROM public.current_active_tenant_membership() AS membership;
  IF v_org IS NULL OR v_actor_role='viewer' THEN RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::uuid,false; RETURN; END IF;
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object('matter_id',p_matter_id,'document_id',p_document_id,'content',p_content,'template_type',p_template_type::text,'is_action_item',p_is_action_item,'action_item_assignee',p_action_item_assignee,'action_item_due_date',p_action_item_due_date,'parent_note_id',p_parent_note_id,'quote',p_quote,'page_number',p_page_number)::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.task_command_receipts WHERE idempotency_key=p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id<>v_actor OR v_receipt.request_fingerprint<>v_fingerprint THEN RETURN QUERY SELECT 'idempotency_conflict'::text,NULL::uuid,NULL::uuid,false;
    ELSE RETURN QUERY SELECT 'ok'::text,v_receipt.note_id,v_receipt.task_id,true; END IF;
    RETURN;
  END IF;
  SELECT matter.client_id INTO v_client FROM public.matters AS matter JOIN public.clients AS client ON client.id=matter.client_id AND client.org_id=matter.org_id WHERE matter.id=p_matter_id AND matter.org_id=v_org AND matter.record_state='active' AND matter.deleted_at IS NULL AND client.record_state='active' AND client.deleted_at IS NULL FOR KEY SHARE OF matter,client;
  IF v_client IS NULL THEN RETURN QUERY SELECT 'context_unavailable'::text,NULL::uuid,NULL::uuid,false; RETURN; END IF;
  IF p_document_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.documents AS document WHERE document.id=p_document_id AND document.org_id=v_org AND document.matter_id=p_matter_id AND document.record_state='active' AND document.deleted_at IS NULL FOR KEY SHARE) THEN RETURN QUERY SELECT 'context_unavailable'::text,NULL::uuid,NULL::uuid,false; RETURN; END IF;
  IF p_parent_note_id IS NOT NULL THEN SELECT * INTO v_parent FROM public.case_notes AS parent_note WHERE parent_note.id=p_parent_note_id AND parent_note.org_id=v_org AND parent_note.matter_id=p_matter_id AND parent_note.deleted_at IS NULL FOR KEY SHARE; IF v_parent.id IS NULL THEN RETURN QUERY SELECT 'invalid_parent_note'::text,NULL::uuid,NULL::uuid,false; RETURN; END IF; END IF;
  IF p_is_action_item AND p_action_item_assignee IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.organisation_memberships AS assignee WHERE assignee.org_id=v_org AND assignee.user_id=p_action_item_assignee AND assignee.state='active' AND assignee.role IN ('admin','associate')) THEN RETURN QUERY SELECT 'invalid_assignee'::text,NULL::uuid,NULL::uuid,false; RETURN; END IF;
  IF NOT p_is_action_item AND (p_action_item_assignee IS NOT NULL OR p_action_item_due_date IS NOT NULL) THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,false; RETURN; END IF;
  IF p_is_action_item THEN SELECT settings.timezone INTO v_timezone FROM public.organisation_operational_settings AS settings WHERE settings.org_id=v_org FOR KEY SHARE; IF v_timezone IS NULL OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=v_timezone) THEN RETURN QUERY SELECT 'invalid_timezone'::text,NULL::uuid,NULL::uuid,false; RETURN; END IF; END IF;
  INSERT INTO public.case_notes(org_id,author_id,matter_id,document_id,content,template_type,is_action_item,action_item_assignee,action_item_due_date,parent_note_id,quote,page_number,is_pinned,action_item_resolved) VALUES(v_org,v_actor,p_matter_id,p_document_id,p_content,p_template_type,p_is_action_item,CASE WHEN p_is_action_item THEN p_action_item_assignee ELSE NULL END,CASE WHEN p_is_action_item THEN p_action_item_due_date ELSE NULL END,p_parent_note_id,p_quote,p_page_number,false,false) RETURNING * INTO v_note;
  IF p_is_action_item THEN
    v_title:=left(regexp_replace(btrim(p_content),'[[:space:]]+',' ','g'),240);
    INSERT INTO public.tasks(org_id,client_id,matter_id,document_id,title,description,origin_kind,origin_note_id,origin_snapshot,creator_user_id,assignee_user_id,priority,status,due_date,due_time,due_timezone,revision,lifecycle_state,status_changed_by) VALUES(v_org,v_client,p_matter_id,p_document_id,v_title,NULL,'case_note',v_note.id,p_content,v_actor,p_action_item_assignee,'normal','open',p_action_item_due_date,NULL,CASE WHEN p_action_item_due_date IS NULL THEN NULL ELSE v_timezone END,1,'active',v_actor) RETURNING id INTO v_task;
  END IF;
  INSERT INTO public.task_command_receipts(org_id,actor_user_id,idempotency_key,request_fingerprint,note_id,task_id) VALUES(v_org,v_actor,p_idempotency_key,v_fingerprint,v_note.id,v_task);
  IF v_task IS NOT NULL THEN
    v_activity_idempotency_key:=encode(extensions.digest(convert_to(jsonb_build_object('command','task.created','task_id',v_task,'command_idempotency_key',p_idempotency_key,'org_id',v_org,'actor_id',v_actor)::text,'utf8'),'sha256'),'hex');
    PERFORM public.append_activity_event(v_org,'task.created',1::smallint,'user',v_actor,NULL,'task',v_task,v_client,p_matter_id,'Task','Task created','{}'::jsonb,'task',v_task,NULL,p_idempotency_key,NULL,v_activity_idempotency_key,now());
  END IF;
  RETURN QUERY SELECT 'ok'::text,v_note.id,v_task,false;
END $$;

-- A transition locks the complete current-membership record FOR UPDATE before
-- deciding authority. A concurrent suspend/remove must wait until either this
-- transaction commits atomically (Task/history/Activity/outbox) or rolls back.
CREATE OR REPLACE FUNCTION public.transition_task(
  p_task_id uuid,p_command text,p_expected_revision bigint,p_idempotency_key uuid,p_assignee_user_id uuid DEFAULT NULL,p_due_date date DEFAULT NULL
) RETURNS TABLE(code text,task_id uuid,revision bigint,status public.task_status,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_org uuid; v_membership_id uuid; v_role public.org_member_role;
  v_current_count integer:=0; v_active_count integer:=0; v_locked_membership public.organisation_memberships%ROWTYPE;
  v_task public.tasks%ROWTYPE; v_previous public.tasks%ROWTYPE; v_receipt public.task_transition_receipts%ROWTYPE;
  v_timezone text; v_fingerprint text; v_command text:=nullif(btrim(p_command),''); v_status public.task_status; v_assignee uuid; v_due_date date; v_due_timezone text; v_status_changed boolean:=false; v_activity_idempotency_key text;
BEGIN
  IF v_actor IS NULL OR p_task_id IS NULL OR p_idempotency_key IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1 OR v_command IS NULL OR v_command NOT IN ('start','complete','reopen','cancel','set_assignee','set_due_date','clear_due_date') THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::bigint,NULL::public.task_status,false; RETURN; END IF;
  IF (v_command='set_assignee' AND p_assignee_user_id IS NULL) OR (v_command='set_due_date' AND p_due_date IS NULL) OR (v_command IN ('start','complete','reopen','cancel','clear_due_date') AND (p_assignee_user_id IS NOT NULL OR p_due_date IS NOT NULL)) THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::bigint,NULL::public.task_status,false; RETURN; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,100));
  FOR v_locked_membership IN SELECT * FROM public.organisation_memberships AS membership WHERE membership.user_id=v_actor AND membership.state IN ('active','suspended') FOR UPDATE LOOP
    v_current_count:=v_current_count+1;
    IF v_locked_membership.state='active' THEN v_active_count:=v_active_count+1;v_org:=v_locked_membership.org_id;v_membership_id:=v_locked_membership.id;v_role:=v_locked_membership.role; END IF;
  END LOOP;
  IF v_current_count<>1 OR v_active_count<>1 THEN IF v_current_count>1 THEN RAISE LOG 'organisation membership invariant violation during Task transition for actor %: % current memberships',v_actor,v_current_count; END IF; RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::bigint,NULL::public.task_status,false; RETURN; END IF;
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
  v_previous:=v_task;v_status:=v_task.status;v_assignee:=v_task.assignee_user_id;v_due_date:=v_task.due_date;v_due_timezone:=v_task.due_timezone;
  IF v_command='start' THEN IF v_task.status<>'open' THEN RETURN QUERY SELECT 'invalid_transition'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF;v_status:='in_progress';v_status_changed:=true;
  ELSIF v_command='complete' THEN IF v_task.status NOT IN ('open','in_progress') THEN RETURN QUERY SELECT 'invalid_transition'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF;v_status:='completed';v_status_changed:=true;
  ELSIF v_command='reopen' THEN IF v_task.status NOT IN ('completed','cancelled') THEN RETURN QUERY SELECT 'invalid_transition'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF;v_status:='open';v_status_changed:=true;
  ELSIF v_command='cancel' THEN IF v_task.status NOT IN ('open','in_progress') THEN RETURN QUERY SELECT 'invalid_transition'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF;v_status:='cancelled';v_status_changed:=true;
  ELSIF v_command='set_assignee' THEN IF v_task.status NOT IN ('open','in_progress') THEN RETURN QUERY SELECT 'invalid_transition'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF;IF NOT EXISTS(SELECT 1 FROM public.organisation_memberships AS assignee LEFT JOIN public.organisations AS organisation ON organisation.id=assignee.org_id WHERE assignee.org_id=v_org AND assignee.user_id=p_assignee_user_id AND assignee.state='active' AND (assignee.role IN ('admin','associate') OR organisation.owner_membership_id=assignee.id)) THEN RETURN QUERY SELECT 'invalid_assignee'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF;v_assignee:=p_assignee_user_id;
  ELSIF v_command='set_due_date' THEN IF v_task.status NOT IN ('open','in_progress') THEN RETURN QUERY SELECT 'invalid_transition'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF;SELECT settings.timezone INTO v_timezone FROM public.organisation_operational_settings AS settings WHERE settings.org_id=v_org FOR KEY SHARE;IF v_timezone IS NULL OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=v_timezone) THEN RETURN QUERY SELECT 'invalid_timezone'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF;v_due_date:=p_due_date;v_due_timezone:=v_timezone;
  ELSE IF v_task.status NOT IN ('open','in_progress') THEN RETURN QUERY SELECT 'invalid_transition'::text,v_task.id,v_task.revision,v_task.status,false; RETURN; END IF;v_due_date:=NULL;v_due_timezone:=NULL;
  END IF;
  UPDATE public.tasks AS task SET status=v_status,assignee_user_id=v_assignee,due_date=v_due_date,due_time=CASE WHEN v_command IN ('set_due_date','clear_due_date') THEN NULL ELSE task.due_time END,due_timezone=v_due_timezone,revision=task.revision+1,status_changed_at=CASE WHEN v_status_changed THEN now() ELSE task.status_changed_at END,status_changed_by=CASE WHEN v_status_changed THEN v_actor ELSE task.status_changed_by END,completed_at=CASE WHEN v_status='completed' THEN now() ELSE NULL END,completed_by=CASE WHEN v_status='completed' THEN v_actor ELSE NULL END,updated_at=now() WHERE task.id=v_task.id RETURNING * INTO v_task;
  INSERT INTO public.task_transition_history(org_id,task_id,actor_user_id,command,from_status,to_status,from_assignee_user_id,to_assignee_user_id,from_due_date,to_due_date,from_due_timezone,to_due_timezone,revision,idempotency_key) VALUES(v_org,v_task.id,v_actor,v_command,v_previous.status,v_task.status,v_previous.assignee_user_id,v_task.assignee_user_id,v_previous.due_date,v_task.due_date,v_previous.due_timezone,v_task.due_timezone,v_task.revision,p_idempotency_key);
  INSERT INTO public.task_transition_receipts(org_id,actor_user_id,idempotency_key,request_fingerprint,task_id,result_revision,result_status) VALUES(v_org,v_actor,p_idempotency_key,v_fingerprint,v_task.id,v_task.revision,v_task.status);
  v_activity_idempotency_key:=encode(extensions.digest(convert_to(jsonb_build_object('command','task.transitioned','task_id',v_task.id,'revision',v_task.revision,'command_idempotency_key',p_idempotency_key,'org_id',v_org,'actor_id',v_actor)::text,'utf8'),'sha256'),'hex');
  PERFORM public.append_activity_event(v_org,'task.transitioned',1::smallint,'user',v_actor,NULL,'task',v_task.id,v_task.client_id,v_task.matter_id,'Task','Task updated',jsonb_build_object('command',v_command,'from_status',v_previous.status::text,'to_status',v_task.status::text,'revision',v_task.revision),'task',v_task.id,NULL,p_idempotency_key,NULL,v_activity_idempotency_key,now());
  RETURN QUERY SELECT 'ok'::text,v_task.id,v_task.revision,v_task.status,false;
END $$;

REVOKE ALL ON FUNCTION public.create_note_with_optional_task(uuid,text,public.note_template_type,boolean,uuid,uuid,uuid,date,uuid,text,integer),public.transition_task(uuid,text,bigint,uuid,uuid,date) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.create_note_with_optional_task(uuid,text,public.note_template_type,boolean,uuid,uuid,uuid,date,uuid,text,integer),public.transition_task(uuid,text,bigint,uuid,uuid,date) TO authenticated;
COMMENT ON FUNCTION public.transition_task(uuid,text,bigint,uuid,uuid,date) IS 'Exact-active membership command with row-lock state fence, CAS/idempotency, append-only Task Activity, and transactional projector outbox.';
COMMIT;
