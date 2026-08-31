-- Work plan step 3 prerequisite: Task dates are organisation-operational
-- dates. Keep the setting private and make the existing live Notes command
-- read it atomically when it creates a due-dated Task.
BEGIN;

CREATE TABLE public.organisation_operational_settings (
  org_id uuid PRIMARY KEY REFERENCES public.organisations(id) ON DELETE RESTRICT,
  timezone text NOT NULL DEFAULT 'Asia/Kolkata',
  revision bigint NOT NULL DEFAULT 1 CHECK (revision >= 1),
  updated_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.organisation_operational_settings_validate()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  NEW.timezone := btrim(NEW.timezone);
  IF NEW.timezone = ''
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = NEW.timezone) THEN
    RAISE EXCEPTION 'organisation operational timezone is invalid';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    NEW.org_id := OLD.org_id;
    NEW.revision := OLD.revision + 1;
    NEW.updated_at := now();
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER organisation_operational_settings_validate
  BEFORE INSERT OR UPDATE ON public.organisation_operational_settings
  FOR EACH ROW EXECUTE FUNCTION public.organisation_operational_settings_validate();

CREATE OR REPLACE FUNCTION public.initialise_organisation_operational_settings()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  INSERT INTO public.organisation_operational_settings (org_id)
  VALUES (NEW.id)
  ON CONFLICT (org_id) DO NOTHING;
  RETURN NEW;
END $$;

INSERT INTO public.organisation_operational_settings (org_id)
SELECT organisation.id
FROM public.organisations AS organisation
ON CONFLICT (org_id) DO NOTHING;

CREATE TRIGGER organisations_initialise_operational_settings
  AFTER INSERT ON public.organisations
  FOR EACH ROW EXECUTE FUNCTION public.initialise_organisation_operational_settings();

CREATE OR REPLACE FUNCTION public.get_my_organisation_operational_settings()
RETURNS TABLE(code text, timezone text, revision bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_org uuid;
  v_settings public.organisation_operational_settings%ROWTYPE;
BEGIN
  IF v_actor IS NULL THEN
    RETURN QUERY SELECT 'not_allowed'::text, NULL::text, NULL::bigint;
    RETURN;
  END IF;
  SELECT membership.org_id INTO v_org
  FROM public.organisation_memberships AS membership
  WHERE membership.user_id = v_actor AND membership.state = 'active'
  ORDER BY membership.created_at DESC
  LIMIT 1;
  IF v_org IS NULL OR NOT public.has_team_capability(v_org, 'organisation.operations.manage') THEN
    RETURN QUERY SELECT 'not_allowed'::text, NULL::text, NULL::bigint;
    RETURN;
  END IF;
  SELECT * INTO v_settings
  FROM public.organisation_operational_settings AS settings
  WHERE settings.org_id = v_org;
  IF v_settings.org_id IS NULL THEN
    RETURN QUERY SELECT 'not_available'::text, NULL::text, NULL::bigint;
    RETURN;
  END IF;
  RETURN QUERY SELECT 'ok'::text, v_settings.timezone, v_settings.revision;
END $$;

CREATE OR REPLACE FUNCTION public.set_my_organisation_operational_timezone(
  p_timezone text,
  p_expected_revision bigint
)
RETURNS TABLE(code text, timezone text, revision bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_org uuid;
  v_timezone text := nullif(btrim(p_timezone), '');
  v_settings public.organisation_operational_settings%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_expected_revision IS NULL OR p_expected_revision < 1
     OR v_timezone IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::text, NULL::bigint;
    RETURN;
  END IF;
  SELECT membership.org_id INTO v_org
  FROM public.organisation_memberships AS membership
  WHERE membership.user_id = v_actor AND membership.state = 'active'
  ORDER BY membership.created_at DESC
  LIMIT 1;
  IF v_org IS NULL OR NOT public.has_team_capability(v_org, 'organisation.operations.manage') THEN
    RETURN QUERY SELECT 'not_allowed'::text, NULL::text, NULL::bigint;
    RETURN;
  END IF;
  SELECT * INTO v_settings
  FROM public.organisation_operational_settings AS settings
  WHERE settings.org_id = v_org
  FOR UPDATE;
  IF v_settings.org_id IS NULL THEN
    RETURN QUERY SELECT 'not_available'::text, NULL::text, NULL::bigint;
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = v_timezone) THEN
    RETURN QUERY SELECT 'invalid_timezone'::text, v_settings.timezone, v_settings.revision;
    RETURN;
  END IF;
  IF v_settings.revision <> p_expected_revision THEN
    RETURN QUERY SELECT 'conflict'::text, v_settings.timezone, v_settings.revision;
    RETURN;
  END IF;
  UPDATE public.organisation_operational_settings AS settings
  SET timezone = v_timezone,
      updated_by = v_actor
  WHERE settings.org_id = v_org
  RETURNING settings.* INTO v_settings;
  RETURN QUERY SELECT 'updated'::text, v_settings.timezone, v_settings.revision;
END $$;

-- Preserve all pre-existing validation and Activity effects. The only changed
-- source is the Task due timezone: it comes exclusively from the actor's
-- active organisation's private operational setting, never user_profiles.
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
  -- Replay is a command result, not an access grant. Resolve the caller's
  -- current active membership before inspecting a durable receipt so a
  -- suspended/removed actor cannot recover historical note or Task locators.
  SELECT membership.org_id, membership.role INTO v_org, v_actor_role
  FROM public.organisation_memberships membership
  WHERE membership.user_id = v_actor AND membership.state = 'active'
  ORDER BY membership.created_at DESC LIMIT 1;
  IF v_org IS NULL OR v_actor_role = 'viewer' THEN
    RETURN QUERY SELECT 'not_allowed'::text, NULL::uuid, NULL::uuid, false;
    RETURN;
  END IF;
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
    SELECT settings.timezone INTO v_timezone
    FROM public.organisation_operational_settings AS settings
    WHERE settings.org_id = v_org
    FOR KEY SHARE;
    IF v_timezone IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = v_timezone) THEN
      RETURN QUERY SELECT 'invalid_timezone'::text, NULL::uuid, NULL::uuid, false; RETURN;
    END IF;
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

ALTER TABLE public.organisation_operational_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organisation_operational_settings FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.organisation_operational_settings FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.organisation_operational_settings_validate(), public.initialise_organisation_operational_settings() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_organisation_operational_settings(), public.set_my_organisation_operational_timezone(text,bigint) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.create_note_with_optional_task(uuid,text,public.note_template_type,boolean,uuid,uuid,uuid,date,uuid,text,integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_organisation_operational_settings(), public.set_my_organisation_operational_timezone(text,bigint), public.create_note_with_optional_task(uuid,text,public.note_template_type,boolean,uuid,uuid,uuid,date,uuid,text,integer) TO authenticated;

COMMENT ON TABLE public.organisation_operational_settings IS 'Private organisation operational policy. Task due dates read its validated timezone; browser and service roles have no direct table authority.';
COMMENT ON FUNCTION public.set_my_organisation_operational_timezone(text,bigint) IS 'Owner/Admin-only operational-timezone command for a future organisation settings surface.';
COMMIT;
