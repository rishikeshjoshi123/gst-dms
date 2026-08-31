-- Work plan step 3: adopt the existing live action-item note command as the
-- first typed Task Activity producer. This remains a write-only adapter: no
-- Task/Activity reader, projector worker, transition, or notification consumer
-- is introduced here.
BEGIN;

-- Tasks are private state, but they are valid immutable Activity subjects and
-- targets. Keep the registry and locator allowlists in lockstep.
ALTER TABLE public.activity_event_definitions
  DROP CONSTRAINT IF EXISTS activity_event_definitions_subject_types_check;
ALTER TABLE public.activity_event_definitions
  ADD CONSTRAINT activity_event_definitions_subject_types_check CHECK (
    cardinality(subject_types) > 0
    AND subject_types <@ ARRAY['organisation','client','matter','document','task','trash_operation']::text[]
  );

ALTER TABLE public.activity_events
  DROP CONSTRAINT IF EXISTS activity_events_subject_type_check,
  DROP CONSTRAINT IF EXISTS activity_events_target_type_check;
ALTER TABLE public.activity_events
  ADD CONSTRAINT activity_events_subject_type_check CHECK (
    subject_type = ANY(ARRAY['organisation','client','matter','document','task','trash_operation']::text[])
  ),
  ADD CONSTRAINT activity_events_target_type_check CHECK (
    target_type = ANY(ARRAY['organisation','client','matter','document','task','trash_operation']::text[])
  );

CREATE OR REPLACE FUNCTION public.activity_validate_subject(
  p_org_id uuid,p_subject_type text,p_subject_id uuid,p_client_id uuid,p_matter_id uuid,p_target_type text,p_target_id uuid,p_target_version_id uuid
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=pg_catalog,public AS $$
DECLARE
  actual_client uuid;
  actual_matter uuid;
  actual_document uuid;
  target_org uuid;
  target_client uuid;
  target_matter uuid;
  root_type public.trash_resource_type;
BEGIN
  IF p_subject_type='organisation' THEN
    IF p_subject_id<>p_org_id OR p_client_id IS NOT NULL OR p_matter_id IS NOT NULL THEN RETURN false; END IF;
  ELSIF p_subject_type='client' THEN
    SELECT id INTO actual_client FROM public.clients WHERE id=p_subject_id AND org_id=p_org_id;
    IF actual_client IS NULL OR p_client_id IS DISTINCT FROM actual_client OR p_matter_id IS NOT NULL THEN RETURN false; END IF;
  ELSIF p_subject_type='matter' THEN
    SELECT client_id INTO actual_client FROM public.matters WHERE id=p_subject_id AND org_id=p_org_id;
    IF actual_client IS NULL OR p_client_id IS DISTINCT FROM actual_client OR p_matter_id IS DISTINCT FROM p_subject_id THEN RETURN false; END IF;
  ELSIF p_subject_type='document' THEN
    SELECT m.client_id,d.matter_id INTO actual_client,actual_matter
    FROM public.documents d JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id
    WHERE d.id=p_subject_id AND d.org_id=p_org_id;
    IF actual_matter IS NULL OR p_client_id IS DISTINCT FROM actual_client OR p_matter_id IS DISTINCT FROM actual_matter THEN RETURN false; END IF;
  ELSIF p_subject_type='task' THEN
    SELECT client_id,matter_id INTO actual_client,actual_matter
    FROM public.tasks WHERE id=p_subject_id AND org_id=p_org_id;
    IF NOT FOUND OR p_client_id IS DISTINCT FROM actual_client OR p_matter_id IS DISTINCT FROM actual_matter THEN RETURN false; END IF;
  ELSIF p_subject_type='trash_operation' THEN
    SELECT root_resource_type,root_client_id,root_matter_id,root_document_id
    INTO root_type,actual_client,actual_matter,actual_document
    FROM public.trash_operations WHERE id=p_subject_id AND org_id=p_org_id;
    IF root_type IS NULL THEN RETURN false; END IF;
    IF root_type='matter' THEN
      SELECT client_id INTO actual_client FROM public.matters WHERE id=actual_matter AND org_id=p_org_id;
    ELSIF root_type='document' THEN
      SELECT m.client_id,d.matter_id INTO actual_client,actual_matter
      FROM public.documents d JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id
      WHERE d.id=actual_document AND d.org_id=p_org_id;
    END IF;
    IF (root_type='client' AND actual_client IS NULL)
       OR (root_type IN ('matter','document') AND (actual_client IS NULL OR actual_matter IS NULL))
       OR p_client_id IS DISTINCT FROM actual_client OR p_matter_id IS DISTINCT FROM actual_matter THEN RETURN false; END IF;
  ELSE
    RETURN false;
  END IF;

  IF p_target_type='organisation' THEN RETURN p_target_version_id IS NULL AND p_target_id=p_org_id; END IF;
  IF p_target_type='client' THEN
    SELECT org_id INTO target_org FROM public.clients WHERE id=p_target_id;
  ELSIF p_target_type='matter' THEN
    SELECT org_id INTO target_org FROM public.matters WHERE id=p_target_id;
  ELSIF p_target_type='document' THEN
    SELECT org_id INTO target_org FROM public.documents WHERE id=p_target_id;
  ELSIF p_target_type='task' THEN
    SELECT org_id,client_id,matter_id INTO target_org,target_client,target_matter FROM public.tasks WHERE id=p_target_id;
    IF target_client IS DISTINCT FROM p_client_id OR target_matter IS DISTINCT FROM p_matter_id THEN RETURN false; END IF;
  ELSIF p_target_type='trash_operation' THEN
    SELECT org_id INTO target_org FROM public.trash_operations WHERE id=p_target_id;
  ELSE
    RETURN false;
  END IF;
  IF target_org IS DISTINCT FROM p_org_id OR (p_target_type<>'document' AND p_target_version_id IS NOT NULL) THEN RETURN false; END IF;
  RETURN p_target_version_id IS NULL OR EXISTS (
    SELECT 1 FROM public.document_versions version
    WHERE version.id=p_target_version_id AND version.org_id=p_org_id AND version.document_id=p_target_id
  );
END $$;

-- Bind replay to the actor as well as the already-bound tenant, subject, and
-- definition. Existing trusted producers retain their signatures.
CREATE OR REPLACE FUNCTION public.append_activity_event(
  p_org_id uuid,p_event_type text,p_event_version smallint,p_actor_kind public.activity_actor_kind,p_actor_id uuid,p_actor_snapshot text,
  p_subject_type text,p_subject_id uuid,p_client_id uuid,p_matter_id uuid,p_subject_snapshot text,p_summary text,p_metadata jsonb,
  p_target_type text,p_target_id uuid,p_target_version_id uuid,p_correlation_id uuid,p_causation_event_id uuid,p_idempotency_key text,p_occurred_at timestamptz DEFAULT now()
) RETURNS TABLE(activity_event_id uuid,outbox_event_id uuid,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE definition public.activity_event_definitions%ROWTYPE; existing public.activity_events%ROWTYPE; snapshot text; created_event uuid; created_outbox uuid;
BEGIN
  IF p_org_id IS NULL OR p_idempotency_key !~ '^[A-Za-z0-9._:-]{1,200}$' OR p_occurred_at IS NULL OR p_occurred_at>now()+interval '5 minutes' THEN RAISE EXCEPTION 'invalid Activity append request'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_idempotency_key));
  SELECT * INTO existing FROM public.activity_events WHERE idempotency_key=p_idempotency_key;
  IF existing.id IS NOT NULL THEN
    IF existing.org_id<>p_org_id OR existing.actor_kind<>p_actor_kind OR existing.actor_id IS DISTINCT FROM p_actor_id OR existing.subject_type<>p_subject_type OR existing.subject_id<>p_subject_id OR existing.event_type<>p_event_type OR existing.event_version<>p_event_version THEN RAISE EXCEPTION 'Activity idempotency key is bound to another tenant, actor, or subject'; END IF;
    RETURN QUERY SELECT existing.id,(SELECT outbox.id FROM public.activity_projector_outbox_events AS outbox WHERE outbox.activity_event_id=existing.id),true;
    RETURN;
  END IF;
  SELECT * INTO definition FROM public.activity_event_definitions WHERE event_type=p_event_type AND event_version=p_event_version AND lifecycle='active';
  IF definition.event_type IS NULL OR NOT p_subject_type=ANY(definition.subject_types) OR NOT public.activity_metadata_is_safe(definition.metadata_contract,coalesce(p_metadata,'{}'::jsonb)) OR NOT public.activity_validate_subject(p_org_id,p_subject_type,p_subject_id,p_client_id,p_matter_id,p_target_type,p_target_id,p_target_version_id) THEN RAISE EXCEPTION 'Activity definition, lineage, metadata, or locator is invalid'; END IF;
  -- Creation is a self-locating event: the locator must resolve to the exact
  -- newly created Task, rather than another valid Task in the same matter.
  -- Do not impose this on future Task event definitions (for example, a
  -- reassignment may intentionally target a related member or context).
  IF p_event_type='task.created' AND (
    p_subject_type<>'task' OR p_target_type<>'task'
    OR p_target_id IS DISTINCT FROM p_subject_id OR p_target_version_id IS NOT NULL
  ) THEN RAISE EXCEPTION 'Task creation Activity must target its created Task'; END IF;
  IF p_actor_kind IN ('user','integration') THEN
    SELECT coalesce(nullif(btrim(profile.display_name),''),CASE WHEN p_actor_kind='integration' THEN 'Integration member' ELSE 'Member' END)
    INTO snapshot FROM public.organisation_memberships membership LEFT JOIN public.user_profiles profile ON profile.user_id=membership.user_id
    WHERE membership.org_id=p_org_id AND membership.user_id=p_actor_id AND membership.state='active';
    IF snapshot IS NULL THEN RAISE EXCEPTION 'Activity actor is not an active organisation member'; END IF;
  ELSE snapshot:=p_actor_snapshot;
  END IF;
  IF NOT public.activity_safe_text(snapshot,160) OR NOT public.activity_safe_text(p_subject_snapshot,200) OR NOT public.activity_safe_text(p_summary,280) OR (p_actor_kind='system' AND p_actor_id IS NOT NULL) OR (p_actor_kind='integration' AND p_actor_id IS NULL) THEN RAISE EXCEPTION 'Activity snapshot or actor is unsafe'; END IF;
  IF p_causation_event_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.activity_events WHERE id=p_causation_event_id AND org_id=p_org_id) THEN RAISE EXCEPTION 'Activity causation must remain tenant-scoped'; END IF;
  INSERT INTO public.activity_events(org_id,client_id,matter_id,actor_kind,actor_id,actor_snapshot,event_type,event_version,subject_type,subject_id,subject_snapshot,summary,metadata,visibility,renderer_key,target_type,target_id,target_version_id,correlation_id,causation_event_id,idempotency_key,occurred_at)
  VALUES(p_org_id,p_client_id,p_matter_id,p_actor_kind,p_actor_id,snapshot,p_event_type,p_event_version,p_subject_type,p_subject_id,p_subject_snapshot,p_summary,coalesce(p_metadata,'{}'::jsonb),definition.default_visibility,definition.renderer_key,p_target_type,p_target_id,p_target_version_id,p_correlation_id,p_causation_event_id,p_idempotency_key,p_occurred_at) RETURNING id INTO created_event;
  INSERT INTO public.activity_projector_outbox_events(activity_event_id,org_id) VALUES(created_event,p_org_id) RETURNING id INTO created_outbox;
  RETURN QUERY SELECT created_event,created_outbox,false;
END $$;

INSERT INTO public.activity_event_definitions(event_type,event_version,category,subject_types,default_visibility,metadata_contract,renderer_key)
VALUES ('task.created',1,'work',ARRAY['task'],'matter','{}','task.created');

CREATE OR REPLACE FUNCTION public.create_note_with_optional_task(
  p_matter_id uuid,
  p_content text,
  p_template_type public.note_template_type,
  p_is_action_item boolean,
  p_idempotency_key uuid,
  p_document_id uuid DEFAULT NULL,
  p_action_item_assignee uuid DEFAULT NULL,
  p_action_item_due_date date DEFAULT NULL,
  p_parent_note_id uuid DEFAULT NULL,
  p_quote text DEFAULT NULL,
  p_page_number integer DEFAULT NULL
) RETURNS TABLE(code text, note_id uuid, task_id uuid, replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_actor uuid := auth.uid(); v_org uuid; v_actor_role public.org_member_role; v_client uuid;
  v_note public.case_notes%ROWTYPE; v_task uuid; v_receipt public.task_command_receipts%ROWTYPE;
  v_parent public.case_notes%ROWTYPE; v_timezone text; v_fingerprint text; v_title text; v_activity_idempotency_key text;
BEGIN
  IF v_actor IS NULL OR p_idempotency_key IS NULL OR p_matter_id IS NULL
     OR p_content IS NULL OR btrim(p_content) = '' OR char_length(p_content) > 20000
     OR p_template_type IS NULL OR p_is_action_item IS NULL
     OR (p_page_number IS NOT NULL AND p_page_number < 1)
     OR (p_quote IS NOT NULL AND char_length(p_quote) > 20000) THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid, NULL::uuid, false; RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text, 95));
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'matter_id', p_matter_id, 'document_id', p_document_id, 'content', p_content,
    'template_type', p_template_type::text, 'is_action_item', p_is_action_item,
    'action_item_assignee', p_action_item_assignee, 'action_item_due_date', p_action_item_due_date,
    'parent_note_id', p_parent_note_id, 'quote', p_quote, 'page_number', p_page_number
  )::text, 'utf8'), 'sha256'), 'hex');
  SELECT * INTO v_receipt FROM public.task_command_receipts WHERE idempotency_key = p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id <> v_actor OR v_receipt.request_fingerprint <> v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::uuid, NULL::uuid, false;
    ELSE
      RETURN QUERY SELECT 'ok'::text, v_receipt.note_id, v_receipt.task_id, true;
    END IF;
    RETURN;
  END IF;
  SELECT membership.org_id, membership.role INTO v_org, v_actor_role
  FROM public.organisation_memberships membership
  WHERE membership.user_id = v_actor AND membership.state = 'active'
  ORDER BY membership.created_at DESC LIMIT 1;
  IF v_org IS NULL OR v_actor_role = 'viewer' THEN RETURN QUERY SELECT 'not_allowed'::text, NULL::uuid, NULL::uuid, false; RETURN; END IF;
  SELECT matter.client_id INTO v_client FROM public.matters matter
  JOIN public.clients client ON client.id = matter.client_id AND client.org_id = matter.org_id
  WHERE matter.id = p_matter_id AND matter.org_id = v_org AND matter.record_state = 'active' AND matter.deleted_at IS NULL AND client.record_state = 'active' AND client.deleted_at IS NULL
  FOR KEY SHARE OF matter, client;
  IF v_client IS NULL THEN RETURN QUERY SELECT 'context_unavailable'::text, NULL::uuid, NULL::uuid, false; RETURN; END IF;
  IF p_document_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.documents document WHERE document.id = p_document_id AND document.org_id = v_org AND document.matter_id = p_matter_id AND document.record_state = 'active' AND document.deleted_at IS NULL FOR KEY SHARE
  ) THEN RETURN QUERY SELECT 'context_unavailable'::text, NULL::uuid, NULL::uuid, false; RETURN; END IF;
  IF p_parent_note_id IS NOT NULL THEN
    SELECT * INTO v_parent FROM public.case_notes parent_note WHERE parent_note.id = p_parent_note_id AND parent_note.org_id = v_org AND parent_note.matter_id = p_matter_id AND parent_note.deleted_at IS NULL FOR KEY SHARE;
    IF v_parent.id IS NULL THEN RETURN QUERY SELECT 'invalid_parent_note'::text, NULL::uuid, NULL::uuid, false; RETURN; END IF;
  END IF;
  IF p_is_action_item AND p_action_item_assignee IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.organisation_memberships assignee WHERE assignee.org_id = v_org AND assignee.user_id = p_action_item_assignee AND assignee.state = 'active' AND assignee.role IN ('admin', 'associate')
  ) THEN RETURN QUERY SELECT 'invalid_assignee'::text, NULL::uuid, NULL::uuid, false; RETURN; END IF;
  IF NOT p_is_action_item AND (p_action_item_assignee IS NOT NULL OR p_action_item_due_date IS NOT NULL) THEN RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid, NULL::uuid, false; RETURN; END IF;
  IF p_is_action_item THEN
    SELECT profile.timezone INTO v_timezone FROM public.user_profiles profile WHERE profile.user_id = v_actor;
    v_timezone := COALESCE(v_timezone, 'Asia/Kolkata');
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = v_timezone) THEN RETURN QUERY SELECT 'invalid_timezone'::text, NULL::uuid, NULL::uuid, false; RETURN; END IF;
  END IF;
  INSERT INTO public.case_notes (org_id,author_id,matter_id,document_id,content,template_type,is_action_item,action_item_assignee,action_item_due_date,parent_note_id,quote,page_number,is_pinned,action_item_resolved)
  VALUES (v_org,v_actor,p_matter_id,p_document_id,p_content,p_template_type,p_is_action_item,CASE WHEN p_is_action_item THEN p_action_item_assignee ELSE NULL END,CASE WHEN p_is_action_item THEN p_action_item_due_date ELSE NULL END,p_parent_note_id,p_quote,p_page_number,false,false)
  RETURNING * INTO v_note;
  IF p_is_action_item THEN
    v_title := left(regexp_replace(btrim(p_content), '[[:space:]]+', ' ', 'g'), 240);
    INSERT INTO public.tasks (org_id,client_id,matter_id,document_id,title,description,origin_kind,origin_note_id,origin_snapshot,creator_user_id,assignee_user_id,priority,status,due_date,due_time,due_timezone,revision,lifecycle_state,status_changed_by)
    VALUES (v_org,v_client,p_matter_id,p_document_id,v_title,NULL,'case_note',v_note.id,p_content,v_actor,p_action_item_assignee,'normal','open',p_action_item_due_date,NULL,CASE WHEN p_action_item_due_date IS NULL THEN NULL ELSE v_timezone END,1,'active',v_actor)
    RETURNING id INTO v_task;
  END IF;
  INSERT INTO public.task_command_receipts (org_id,actor_user_id,idempotency_key,request_fingerprint,note_id,task_id)
  VALUES (v_org,v_actor,p_idempotency_key,v_fingerprint,v_note.id,v_task);
  IF v_task IS NOT NULL THEN
    -- Digest the command-bound values. They remain opaque correlation material,
    -- never a user-visible snapshot or UUID-bearing metadata field.
    v_activity_idempotency_key := encode(extensions.digest(convert_to(jsonb_build_object(
      'command', 'task.created', 'task_id', v_task, 'command_idempotency_key', p_idempotency_key,
      'org_id', v_org, 'actor_id', v_actor
    )::text, 'utf8'), 'sha256'), 'hex');
    PERFORM public.append_activity_event(
      v_org,'task.created',1::smallint,'user',v_actor,NULL,
      'task',v_task,v_client,p_matter_id,'Task','Task created','{}'::jsonb,
      'task',v_task,NULL,p_idempotency_key,NULL,v_activity_idempotency_key,now()
    );
  END IF;
  RETURN QUERY SELECT 'ok'::text, v_note.id, v_task, false;
END $$;

REVOKE ALL ON FUNCTION public.activity_validate_subject(uuid,text,uuid,uuid,uuid,text,uuid,uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.append_activity_event(uuid,text,smallint,public.activity_actor_kind,uuid,text,text,uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid,uuid,uuid,text,timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.append_activity_event(uuid,text,smallint,public.activity_actor_kind,uuid,text,text,uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid,uuid,uuid,text,timestamptz) TO service_role;

COMMENT ON TABLE public.activity_events IS 'Append-only Activity contract. The action-item note command is the first live producer; readers remain unreleased.';
COMMIT;
